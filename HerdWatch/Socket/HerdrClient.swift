import Foundation
import os
import HerdWatchShared

enum ConnectionState: Equatable {
    case connecting
    case live
    case reconnecting(attempt: Int)
}

/// ソケット層からストア層へ渡す、前処理済みの更新。
enum PastureUpdate {
    case connection(ConnectionState)
    case snapshot(panes: [PaneInfo], workspaces: [WorkspaceInfo])
    case statusChanged(AgentStatusChangedData)
    case paneClosed(paneID: String)
}

/// 接続・購読・スナップショット・再接続のすべてを抱え、
/// ストアには PastureUpdate の直列ストリームだけを見せるファサード。
///
/// herdr実測制約（CLAUDE.md参照）:
/// - events.subscribe は1接続に1回だけ → 購読変更は接続の張り替えで行う
/// - pane別購読は pane_id 必須 → roster（既知pane集合）を維持し、変化したら張り替え
final class HerdrClient: @unchecked Sendable {
    struct Config {
        var pollInterval: Duration? = .seconds(45)
        var resubscribeDebounce: Duration = .milliseconds(300)
        var maxBackoff: Double = 15.0
    }

    private let transport: HerdrTransport
    private let config: Config
    private let sleeper: @Sendable (Duration) async throws -> Void
    private let logger = Logger(subsystem: "com.isaji134.HerdWatch", category: "client")

    init(transport: HerdrTransport,
         config: Config = Config(),
         sleeper: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.transport = transport
        self.config = config
        self.sleeper = sleeper
    }

    func updates() -> AsyncStream<PastureUpdate> {
        AsyncStream { continuation in
            let task = Task { [weak self] in
                await self?.run(continuation)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - メインループ

    private enum ConnectionEnd {
        case rosterChanged
        case streamEnded
    }

    private func run(_ c: AsyncStream<PastureUpdate>.Continuation) async {
        var attempt = 0
        var roster = Set<String>()
        while !Task.isCancelled {
            do {
                c.yield(.connection(attempt == 0 ? .connecting : .reconnecting(attempt: attempt)))
                let end = try await runConnection(c, roster: &roster)
                attempt = 0
                switch end {
                case .rosterChanged:
                    // 連続したpane増減をまとめてから張り替える
                    try await sleeper(config.resubscribeDebounce)
                case .streamEnded:
                    // サーバ側が閉じた（herdr再起動など）→ バックオフして再接続
                    attempt = 1
                    try await backoff(attempt: attempt)
                }
            } catch is CancellationError {
                return
            } catch {
                attempt += 1
                logger.warning("connection failed (attempt \(attempt)): \(String(describing: error))")
                do { try await backoff(attempt: attempt) } catch { return }
            }
        }
    }

    private func backoff(attempt: Int) async throws {
        let base = min(config.maxBackoff, 0.5 * pow(2.0, Double(attempt - 1)))
        let jitter = Double.random(in: 0.8...1.2)
        try await sleeper(.seconds(base * jitter))
    }

    /// 1本の購読接続のライフサイクル。ackを待ち、snapshotを取り、イベントを流し続ける。
    /// rosterが変わったら戻って張り替えを促す。
    private func runConnection(_ c: AsyncStream<PastureUpdate>.Continuation,
                               roster: inout Set<String>) async throws -> ConnectionEnd {
        let subs = Self.subscriptions(for: roster)
        let stream = transport.openEventStream(subscriptions: subs)

        // subscribe-first: 購読を開いた直後にsnapshotを取る。取得中に届いたイベントは
        // ストリームに滞留し、後で順に処理される（ack行も最初の消費で処理する）。
        // rosterはagent検出済みpaneに限定する。herdrのUI補助paneは高速に生成消滅するため、
        // 全paneを対象にすると張り替えが無限ループする（実測で確認）。
        let snapshot = try await fetchSnapshot()
        let snapshotPanes = Self.agentPaneIDs(snapshot.panes)
        c.yield(.connection(.live))
        c.yield(.snapshot(panes: snapshot.panes, workspaces: snapshot.workspaces))

        if snapshotPanes != roster {
            roster = snapshotPanes
            // 初回はグローバル購読のみで開いているため、pane別購読を張るためにやり直す
            return .rosterChanged
        }

        // 定期ポーリング（保険）とイベント消費を並走させ、先に終わった方に従う
        let currentRoster = roster
        return try await withThrowingTaskGroup(of: ConnectionEnd.self) { group in
            group.addTask { [weak self] in
                guard let self else { return .streamEnded }
                return try await self.consumeEvents(stream, c: c, roster: currentRoster)
            }
            if let interval = config.pollInterval {
                group.addTask { [weak self] in
                    guard let self else { return .streamEnded }
                    while true {
                        try await self.sleeper(interval)
                        let snap = try await self.fetchSnapshot()
                        c.yield(.snapshot(panes: snap.panes, workspaces: snap.workspaces))
                        if Self.agentPaneIDs(snap.panes) != currentRoster { return .rosterChanged }
                    }
                }
            }
            let result = try await group.next() ?? .streamEnded
            group.cancelAll()
            return result
        }
    }

    /// イベントを消費し、roster変化を検知したら戻る。ack行（response）もここで検査する。
    ///
    /// pane_agent_detected はsnapshotに現れない一時paneに対しても繰り返し発火する（実測）。
    /// 鵜呑みに張り替えるとreconnectが無限ループするため、snapshotで裏取りし、
    /// agent集合が本当に変わったときだけ張り替える。裏取り済みの空振りpaneは接続中は再検証しない。
    private func consumeEvents(_ stream: AsyncThrowingStream<HerdrStreamLine, Error>,
                               c: AsyncStream<PastureUpdate>.Continuation,
                               roster: Set<String>) async throws -> ConnectionEnd {
        var dismissedPanes = Set<String>()
        for try await line in stream {
            guard case .push(let push) = line else {
                if case .response(let ack) = line, let err = ack.error {
                    throw HerdrTransportError.rpcError(code: err.code, message: err.message)
                }
                continue
            }
            switch push.event {
            case "pane.agent_status_changed":
                if let data = try? push.data.reencoded(as: AgentStatusChangedData.self) {
                    c.yield(.statusChanged(data))
                }
            case "pane_agent_detected":
                guard let data = try? push.data.reencoded(as: PaneLifecycleData.self),
                      data.agent != nil, let paneID = data.paneID,
                      !roster.contains(paneID), !dismissedPanes.contains(paneID) else { continue }
                let snap = try await fetchSnapshot()
                c.yield(.snapshot(panes: snap.panes, workspaces: snap.workspaces))
                if Self.agentPaneIDs(snap.panes) != roster {
                    return .rosterChanged
                }
                dismissedPanes.insert(paneID)
            case "pane_closed":
                if let data = try? push.data.reencoded(as: PaneLifecycleData.self),
                   let paneID = data.paneID, roster.contains(paneID) {
                    c.yield(.paneClosed(paneID: paneID))
                    return .rosterChanged
                }
            default:
                break
            }
        }
        return .streamEnded
    }

    /// 手動リロード用: 購読接続には触れず、現在のsnapshotを1回取得する（1コール=1接続）。
    func snapshotNow() async throws -> (panes: [PaneInfo], workspaces: [WorkspaceInfo]) {
        try await fetchSnapshot()
    }

    private func fetchSnapshot() async throws -> (panes: [PaneInfo], workspaces: [WorkspaceInfo]) {
        let paneResp = try await transport.request("pane.list", params: [:])
        let wsResp = try await transport.request("workspace.list", params: [:])
        let panes = try (paneResp.result ?? .null).reencoded(as: PaneListResult.self).panes
        let workspaces = try (wsResp.result ?? .null).reencoded(as: WorkspaceListResult.self).workspaces
        return (panes, workspaces)
    }

    /// rosterの対象: agent検出済みpaneのみ（UI補助paneを含めると張り替えが無限ループする）。
    static func agentPaneIDs(_ panes: [PaneInfo]) -> Set<String> {
        Set(panes.filter { $0.agent != nil }.map(\.paneID))
    }

    /// roster（既知pane集合）に対する購読リスト: グローバル型 + pane別status購読。
    static func subscriptions(for roster: Set<String>) -> [JSONValue] {
        var subs: [JSONValue] = [
            .object(["type": "pane.closed"]),
            .object(["type": "pane.agent_detected"]),
            .object(["type": "workspace.renamed"]),
            .object(["type": "workspace.closed"]),
        ]
        for paneID in roster.sorted() {
            subs.append(.object(["type": "pane.agent_status_changed", "pane_id": .string(paneID)]))
        }
        return subs
    }
}
