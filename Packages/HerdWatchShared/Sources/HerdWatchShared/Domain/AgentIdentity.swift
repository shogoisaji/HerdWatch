import Foundation

/// エージェント個体の同一性キー。
/// hooks連携で agent_session が取れればそれを優先（herdr再起動を跨いで安定）。
/// 無ければ pane_id + 検出ラベル にフォールバック。
public struct AgentIdentity: Hashable, Codable, Sendable {
    public let key: String

    public init(pane: PaneInfo) {
        if let session = pane.agentSession?.value, !session.isEmpty {
            self.key = "session:\(session)"
        } else {
            self.key = "pane:\(pane.paneID)|\(pane.agent ?? "unknown")"
        }
    }

    public init(key: String) {
        self.key = key
    }
}
