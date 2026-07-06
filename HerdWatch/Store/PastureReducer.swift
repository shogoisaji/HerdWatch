import Foundation
import HerdWatchShared

/// PastureUpdate を辞書へ畳み込む純関数群。ソケット・UI非依存でテストする。
enum PastureReducer {
    /// snapshotとの突き合わせ。agent検出済みのpaneだけがキャラクターになる。
    /// 消えたpaneのエージェントは退場、新顔には初登場順を採番してキャラを割り当てる。
    static func mergeSnapshot(panes: [PaneInfo],
                              workspaces: [WorkspaceInfo],
                              into current: [AgentIdentity: PastureAgent],
                              assignments: CharacterAssignmentStore,
                              nextOrder: inout Int,
                              now: Date) -> [AgentIdentity: PastureAgent] {
        // サーバ応答は寛容に扱う方針のため、workspace_id重複でもクラッシュさせない（先勝ち）
        let labels = Dictionary(workspaces.map { ($0.workspaceID, $0.label ?? $0.workspaceID) },
                                uniquingKeysWith: { first, _ in first })
        var result: [AgentIdentity: PastureAgent] = [:]
        for pane in panes where pane.agent != nil {
            let identity = AgentIdentity(pane: pane)
            let wsLabel = labels[pane.workspaceID] ?? pane.workspaceID
            let newState = AgentState(raw: pane.agentStatus)
            if var existing = current[identity] {
                existing.paneID = pane.paneID
                existing.workspaceID = pane.workspaceID
                existing.workspaceLabel = wsLabel
                existing.workingStartedAt = Self.resolveWorkingStart(
                    old: existing.state, new: newState,
                    current: existing.workingStartedAt, now: now)
                existing.state = newState
                result[identity] = existing
            } else {
                result[identity] = PastureAgent(
                    identity: identity,
                    paneID: pane.paneID,
                    workspaceID: pane.workspaceID,
                    workspaceLabel: wsLabel,
                    agentLabel: pane.agent ?? "agent",
                    state: newState,
                    character: assignments.assignment(for: identity),
                    order: nextOrder,
                    workingStartedAt: newState == .working ? now : nil
                )
                nextOrder += 1
            }
        }
        return result
    }

    /// 状態変化イベント。paneIDで対象を探して状態だけ差し替える。
    static func applyStatusChange(_ change: AgentStatusChangedData,
                                  to current: [AgentIdentity: PastureAgent],
                                  now: Date) -> [AgentIdentity: PastureAgent] {
        var result = current
        for (identity, agent) in current where agent.paneID == change.paneID {
            var updated = agent
            let newState = AgentState(raw: change.agentStatus)
            updated.workingStartedAt = Self.resolveWorkingStart(
                old: updated.state, new: newState,
                current: updated.workingStartedAt, now: now)
            updated.state = newState
            result[identity] = updated
        }
        return result
    }

    /// working連続区間の開始時刻を解決する純粋関数。
    /// working→working は継続中なので現在値を保持。非working→working はnowで開始。
    /// working→非working はnil。非working→非working もnil。
    static func resolveWorkingStart(old: AgentState, new: AgentState,
                                    current: Date?, now: Date) -> Date? {
        if new == .working {
            return old == .working ? current : now
        }
        return nil
    }

    /// pane消滅。そのpaneに居たエージェントを退場させる。
    static func removePane(_ paneID: String,
                           from current: [AgentIdentity: PastureAgent]) -> [AgentIdentity: PastureAgent] {
        current.filter { $0.value.paneID != paneID }
    }
}
