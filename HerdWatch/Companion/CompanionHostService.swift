import Foundation
import Observation
import os
import HerdWatchShared

// MARK: - 純粋ロジック（IOなし・テスト対象）

/// 受信メッセージをMac側で実行すべきコマンドへ振り分ける純粋関数。
enum CompanionHostRouter {
    static func route(_ message: CompanionMessage) -> CompanionHostCommand {
        switch message.kind {
        case .focus: return .focus(paneID: message.focus?.paneID ?? "")
        case .reload: return .reload
        case .snapshot, .unknown: return .ignore
        }
    }
}

enum CompanionHostCommand: Equatable {
    case focus(paneID: String)
    case reload
    case ignore
}

/// PastureStoreの状態をCompanionSnapshotへ変換する純粋関数。
enum CompanionHostSnapshotBuilder {
    static func build(agents: [PastureAgent], connectionState: ConnectionState) -> CompanionSnapshot {
        CompanionSnapshot(
            agents: agents.map(agentToCompanion),
            connectionState: connectionState.string)
    }

    static func agentToCompanion(_ agent: PastureAgent) -> CompanionAgent {
        CompanionAgent(
            identityKey: agent.identity.key,
            paneID: agent.paneID,
            workspaceID: agent.workspaceID,
            workspaceLabel: agent.workspaceLabel,
            agentLabel: agent.agentLabel,
            state: agent.state.rawValue,
            species: agent.character.species.rawValue,
            paletteIndex: agent.character.paletteIndex,
            order: agent.order,
            workingStartedAt: agent.workingStartedAt)
    }
}

private extension ConnectionState {
    var string: String {
        switch self {
        case .connecting: "connecting"
        case .live: "live"
        case .reconnecting: "reconnecting"
        }
    }
}

// MARK: - オーケストレータ（PastureStore観察 + 配信 + 命令実行）

/// Mac側Companionホスト。PastureStoreの状態変化をiOSへ配信し、iOSからのfocus命令を
/// HerdrFocusServiceへ委譲する。真実源はあくまでPastureStore（ADR-0001準拠）。
@MainActor
final class CompanionHostService {
    private let store: PastureStore
    private let focusService: HerdrFocusService
    private let terminalBundleID: () -> String
    private let link: CompanionLink
    private let logger = Logger(subsystem: "com.isaji134.HerdWatch", category: "companion-host")
    private var lastSentSnapshot: CompanionSnapshot?

    init(store: PastureStore,
         focusService: HerdrFocusService,
         terminalBundleID: @escaping () -> String,
         link: CompanionLink) {
        self.store = store
        self.focusService = focusService
        self.terminalBundleID = terminalBundleID
        self.link = link
    }

    func start() {
        link.onReceive = { [weak self] data in
            self?.handleIncoming(data)
        }
        link.onPeerConnected = { [weak self] in
            self?.pushCurrentState(force: true)
        }
        link.start()
        observeStore()
        pushCurrentState()
    }

    func stop() {
        link.stop()
    }

    /// 手動トリガ（リロード時など）: 現在状態を即時配信。
    func pushCurrentState(force: Bool = false) {
        let snapshot = CompanionHostSnapshotBuilder.build(
            agents: store.sortedAgents, connectionState: store.connectionState)
        send(snapshot, force: force)
    }

    private func observeStore() {
        // @Observableの変化を検知するため、withObservationTrackingでagentsByID/connectionStateを追跡。
        // 変更のたびに再登録する（Swift Observationの標準パターン）。
        let _: Void = withObservationTracking {
            _ = store.agentsByID
            _ = store.connectionState
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.pushCurrentState()
                self?.observeStore()
            }
        }
    }

    private func send(_ snapshot: CompanionSnapshot, force: Bool = false) {
        // 同一内容の再送は抑止（無駄なトラフィック回避）。ただし接続状態変化は内容に含まれるので再送される。
        guard force || lastSentSnapshot != snapshot else { return }
        let message = CompanionMessage(snapshot: snapshot)
        guard let data = try? CompanionCodec.encode(message) else { return }
        guard link.send(data) else { return }
        lastSentSnapshot = snapshot
    }

    private func handleIncoming(_ data: Data) {
        guard let message = CompanionCodec.decode(data) else {
            logger.warning("Companion: デコード不能なメッセージを受信（無視）")
            return
        }
        switch CompanionHostRouter.route(message) {
        case .focus(let paneID):
            guard !paneID.isEmpty else { return }
            logger.info("Companion: focus命令受信 paneID=\(paneID)")
            let bundleID = terminalBundleID()
            Task { [focusService] in
                await focusService.focus(paneID: paneID, terminalBundleID: bundleID)
            }
        case .reload:
            logger.info("Companion: reload命令受信")
            Task { [weak self] in
                guard let self else { return }
                await store.refresh()
                pushCurrentState(force: true)
            }
        case .ignore:
            break
        }
    }
}
