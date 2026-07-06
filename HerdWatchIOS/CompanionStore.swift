import Foundation
import Observation
import HerdWatchShared

/// iOS側のCompanion状態ストア。Macから受信したスナップショットを鏡写しで保持する。
/// 真実源はMacのPastureStore（ADR-0001準拠）。iOS側は状態を一切解釈・永続化しない。
@Observable @MainActor
final class CompanionStore {
    private(set) var agents: [PastureAgent] = []
    /// Mac側のherdr接続状態（"connecting"/"live"/"reconnecting"）。
    private(set) var hostConnectionState: String = "connecting"
    /// MacホストとのMultipeer接続の有無。
    private(set) var isConnectedToHost = false

    private let client: CompanionClient

    init(client: CompanionClient) {
        self.client = client
        client.onReceive = { [weak self] data in
            Task { @MainActor [weak self] in
                self?.applyIncoming(data)
            }
        }
        client.onStateChange = { [weak self] connected in
            Task { @MainActor [weak self] in
                self?.isConnectedToHost = connected
            }
        }
    }

    func start() {
        client.start()
    }

    func stop() {
        client.stop()
    }

    var sortedAgents: [PastureAgent] {
        agents.sorted { $0.order < $1.order }
    }

    /// キャラタップ時: Macへフォーカス命令を送る。
    func focus(paneID: String) {
        let message = CompanionMessage(focus: CompanionFocusCommand(paneID: paneID))
        guard let data = try? CompanionCodec.encode(message) else { return }
        client.send(data)
    }

    func reload() {
        let message = CompanionMessage(reload: CompanionReloadRequest())
        guard let data = try? CompanionCodec.encode(message) else { return }
        client.send(data)
    }

    private func applyIncoming(_ data: Data) {
        guard let message = CompanionCodec.decode(data) else { return }
        guard case .snapshot = message.kind, let snapshot = message.snapshot else { return }
        agents = snapshot.agents.map(Self.companionToAgent)
        hostConnectionState = snapshot.connectionState
    }

    /// CompanionAgent → PastureAgent への復元（純粋関数）。
    static func companionToAgent(_ c: CompanionAgent) -> PastureAgent {
        PastureAgent(
            identity: AgentIdentity(key: c.identityKey),
            paneID: c.paneID,
            workspaceID: c.workspaceID,
            workspaceLabel: c.workspaceLabel,
            agentLabel: c.agentLabel,
            state: AgentState(raw: c.state),
            character: CharacterAssignment(
                species: Species(rawValue: c.species) ?? .sheep,
                paletteIndex: c.paletteIndex),
            order: c.order,
            workingStartedAt: c.workingStartedAt)
    }
}
