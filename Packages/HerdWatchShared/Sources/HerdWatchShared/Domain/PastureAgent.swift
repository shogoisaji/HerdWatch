import Foundation

/// 放牧場に表示される、状態とキャラクターがマージ済みのエージェント1体。
public struct PastureAgent: Identifiable, Equatable {
    public let identity: AgentIdentity
    public var paneID: String
    public var workspaceID: String
    public var workspaceLabel: String
    public var agentLabel: String
    public var state: AgentState
    public var character: CharacterAssignment
    /// 初登場順（表示順を安定させる）
    public var order: Int
    /// 現在のworking連続区間の開始時刻。stateがworkingのときのみ非nil。
    /// workingへ入った瞬間にnowを記録し、working以外へ遷移したらnilに戻す。
    /// 経過時間表示は描画側で now - workingStartedAt で算出する（アプリ側で未読管理しない: ADR-0001）。
    public var workingStartedAt: Date? = nil

    public var id: AgentIdentity { identity }

    private var paneNumber: String {
        paneID.split(separator: ":").last.map(String.init) ?? paneID
    }

    /// ログ・アクセシビリティ用の1行表記
    public var displayLabel: String {
        "\(workspaceLabel):\(agentLabel) \(paneNumber)"
    }

    /// 足元ラベル上段: workspace名
    public var primaryLabel: String { workspaceLabel }

    /// 足元ラベル下段: agent名 + pane番号
    public var secondaryLabel: String { "\(agentLabel) \(paneNumber)" }

    public init(identity: AgentIdentity, paneID: String, workspaceID: String,
                workspaceLabel: String, agentLabel: String, state: AgentState,
                character: CharacterAssignment, order: Int,
                workingStartedAt: Date? = nil) {
        self.identity = identity
        self.paneID = paneID
        self.workspaceID = workspaceID
        self.workspaceLabel = workspaceLabel
        self.agentLabel = agentLabel
        self.state = state
        self.character = character
        self.order = order
        self.workingStartedAt = workingStartedAt
    }
}
