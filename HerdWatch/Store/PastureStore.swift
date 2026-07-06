import Foundation
import Observation
import HerdWatchShared

@Observable @MainActor
final class PastureStore {
    private(set) var agentsByID: [AgentIdentity: PastureAgent] = [:]
    private(set) var connectionState: ConnectionState = .connecting

    /// 初登場順で安定ソートした表示用リスト。
    var sortedAgents: [PastureAgent] {
        agentsByID.values.sorted { $0.order < $1.order }
    }

    private let client: HerdrClient
    private let assignments: CharacterAssignmentStore
    private var nextOrder = 0
    private var consumeTask: Task<Void, Never>?

    init(client: HerdrClient, assignments: CharacterAssignmentStore) {
        self.client = client
        self.assignments = assignments
    }

    func start() {
        guard consumeTask == nil else { return }
        consumeTask = Task { [weak self] in
            guard let updates = self?.client.updates() else { return }
            for await update in updates {
                guard let self else { return }
                self.apply(update)
            }
        }
    }

    func stop() {
        consumeTask?.cancel()
        consumeTask = nil
    }

    /// 手動リロード（放牧場メニュー）: snapshotを取り直してherdrの現在状態を即時反映する。
    /// 呼び出し元がawait後にsortedAgentsを読めるよう、完了を待てる形にしている。
    func refresh() async {
        guard let snap = try? await client.snapshotNow() else { return }
        apply(.snapshot(panes: snap.panes, workspaces: snap.workspaces))
    }

    func reroll(_ identity: AgentIdentity) {
        guard var agent = agentsByID[identity] else { return }
        agent.character = assignments.reroll(for: identity)
        agentsByID[identity] = agent
    }

    func rerollAll() {
        for identity in agentsByID.keys {
            reroll(identity)
        }
    }

    func setCharacter(_ identity: AgentIdentity, species: Species, paletteIndex: Int) {
        guard var agent = agentsByID[identity] else { return }
        let assignment = CharacterAssignment(species: species, paletteIndex: paletteIndex)
        assignments.set(assignment, for: identity)
        agent.character = assignment
        agentsByID[identity] = agent
    }

    #if DEBUG
    /// 目視QA用: herdrを介さず全キャラの状態を1つ先へ回す（実状態は次のsnapshot/イベントで復元される）。
    func debugCycleStates() {
        let cycle: [AgentState] = [.idle, .working, .blocked, .done, .unknown]
        let now = Date()
        for (id, var agent) in agentsByID {
            let index = cycle.firstIndex(of: agent.state) ?? 0
            let newState = cycle[(index + 1) % cycle.count]
            agent.workingStartedAt = PastureReducer.resolveWorkingStart(
                old: agent.state, new: newState, current: agent.workingStartedAt, now: now)
            agent.state = newState
            agentsByID[id] = agent
        }
    }
    #endif

    private func apply(_ update: PastureUpdate) {
        switch update {
        case .connection(let state):
            connectionState = state
        case .snapshot(let panes, let workspaces):
            agentsByID = PastureReducer.mergeSnapshot(
                panes: panes, workspaces: workspaces,
                into: agentsByID, assignments: assignments, nextOrder: &nextOrder, now: Date())
        case .statusChanged(let change):
            agentsByID = PastureReducer.applyStatusChange(change, to: agentsByID, now: Date())
        case .paneClosed(let paneID):
            agentsByID = PastureReducer.removePane(paneID, from: agentsByID)
        }
    }
}
