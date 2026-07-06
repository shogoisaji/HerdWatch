import Foundation

// MARK: - Companion連携プロトコル（Mac↔iOS, MultipeerConnectivity上のJSON行）
//
// 設計意図:
// - Macアプリがherdrとの唯一の接点であり続け、iOSアプリはMac経由で状態を見る。
// - iOS側の機能範囲は「状態表示 + タップでフォーカス」のみ（キャラ編集はMac側）。
// - 通信はNDJSON1行=1メッセージ。既存のherdrプロトコルと同じ寛容デコード方針。
// - 真実源はMacのPastureStore。iOSは受信したスナップショットを鏡写しで描画するだけ。

/// Mac→iOS: 放牧場の全エージェントの現在状態。状態変化のたびにMacが送信する。
public struct CompanionSnapshot: Codable, Equatable, Sendable {
    public let agents: [CompanionAgent]
    /// Mac側の接続状態（iOS側でローディング表示の判断に使う）
    public let connectionState: String

    public init(agents: [CompanionAgent], connectionState: String) {
        self.agents = agents
        self.connectionState = connectionState
    }
}

/// iOS→Mac: キャラをタップしたときのフォーカス命令。MacがHerdrFocusServiceへ委譲する。
public struct CompanionFocusCommand: Codable, Equatable, Sendable {
    public let paneID: String

    public init(paneID: String) {
        self.paneID = paneID
    }
}

/// iOS→Mac: 現在状態を取り直して再送してほしいという手動リロード要求。
public struct CompanionReloadRequest: Codable, Equatable, Sendable {
    public init() {}
}

/// 1メッセージ=1JSON行のエンベロープ。snapshot/focus/reloadのいずれかが入る。
/// すべてnil、あるいは未知フィールドは寛容に扱う（log-and-skipは呼び出し元で）。
public struct CompanionMessage: Codable, Equatable, Sendable {
    public let snapshot: CompanionSnapshot?
    public let focus: CompanionFocusCommand?
    public let reload: CompanionReloadRequest?

    public init(snapshot: CompanionSnapshot) {
        self.snapshot = snapshot
        self.focus = nil
        self.reload = nil
    }

    public init(focus: CompanionFocusCommand) {
        self.snapshot = nil
        self.focus = focus
        self.reload = nil
    }

    public init(reload: CompanionReloadRequest) {
        self.snapshot = nil
        self.focus = nil
        self.reload = reload
    }

    /// 受信したメッセージの種別。すべてnilのときは .unknown。
    public var kind: Kind {
        if snapshot != nil { return .snapshot }
        if focus != nil { return .focus }
        if reload != nil { return .reload }
        return .unknown
    }

    public enum Kind: Equatable {
        case snapshot, focus, reload, unknown
    }
}

/// PastureAgentの通信向け直列化形。ドメイン型にAppKit依存がないためそのまま使えるが、
/// iOS側がPastureAgent定義に依存しなくて済むよう、通信専用の平坦な形にする。
public struct CompanionAgent: Codable, Equatable, Sendable {
    public let identityKey: String
    public let paneID: String
    public let workspaceID: String
    public let workspaceLabel: String
    public let agentLabel: String
    public let state: String
    public let species: String
    public let paletteIndex: Int
    public let order: Int
    /// working連続区間の開始時刻（stateがworkingのときのみ）。省略時=nil（寛容デコード）。
    public let workingStartedAt: Date?

    public init(identityKey: String, paneID: String, workspaceID: String,
         workspaceLabel: String, agentLabel: String, state: String,
         species: String, paletteIndex: Int, order: Int,
         workingStartedAt: Date? = nil) {
        self.identityKey = identityKey
        self.paneID = paneID
        self.workspaceID = workspaceID
        self.workspaceLabel = workspaceLabel
        self.agentLabel = agentLabel
        self.state = state
        self.species = species
        self.paletteIndex = paletteIndex
        self.order = order
        self.workingStartedAt = workingStartedAt
    }
}

// MARK: - 行エンコード/デコード（NDJSON1行相当）

public enum CompanionCodec {
    /// メッセージを1行のJSON Dataへ変換（末尾改行なし。呼び出し元で\nを付ける）。
    public static func encode(_ message: CompanionMessage) throws -> Data {
        try JSONEncoder().encode(message)
    }

    /// 1行のJSON Dataからメッセージへ復元。不正行はnil（呼び出し元でlog-and-skip）。
    public static func decode(_ data: Data) -> CompanionMessage? {
        try? JSONDecoder().decode(CompanionMessage.self, from: data)
    }
}
