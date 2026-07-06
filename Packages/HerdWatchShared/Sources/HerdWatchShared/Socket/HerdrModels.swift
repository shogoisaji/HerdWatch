import Foundation

// MARK: - リクエスト

public struct HerdrRequest: Encodable {
    public let id: String
    public let method: String
    public let params: [String: JSONValue]

    public init(id: String, method: String, params: [String: JSONValue]) {
        self.id = id
        self.method = method
        self.params = params
    }
}

// MARK: - レスポンス（単発RPC）

/// `{"id":..., "result":{...}}` または `{"id":..., "error":{...}}`
public struct HerdrResponse: Decodable {
    public let id: String
    public let result: JSONValue?
    public let error: HerdrError?

    public init(id: String, result: JSONValue?, error: HerdrError?) {
        self.id = id
        self.result = result
        self.error = error
    }
}

public struct HerdrError: Decodable, Error {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

// MARK: - pushイベント（実測: {"data":{...},"event":"<名前>"}）

public struct HerdrPushEvent: Decodable {
    public let event: String
    public let data: JSONValue

    public init(event: String, data: JSONValue) {
        self.event = event
        self.data = data
    }
}

/// 購読ストリームに流れてくる行は「購読ack（HerdrResponse）」か「pushイベント」のどちらか。
public enum HerdrStreamLine {
    case response(HerdrResponse)
    case push(HerdrPushEvent)
    case undecodable(String)

    public static func decode(_ line: Data) -> HerdrStreamLine {
        let decoder = JSONDecoder()
        if let push = try? decoder.decode(HerdrPushEvent.self, from: line) {
            return .push(push)
        }
        if let resp = try? decoder.decode(HerdrResponse.self, from: line) {
            return .response(resp)
        }
        return .undecodable(String(data: line, encoding: .utf8) ?? "<non-utf8>")
    }
}

// MARK: - ドメイン寄りのペイロード

public struct PaneInfo: Decodable, Equatable {
    public let paneID: String
    public let terminalID: String?
    public let workspaceID: String
    public let tabID: String?
    public let focused: Bool?
    public let cwd: String?
    public let agent: String?
    public let agentStatus: String?
    public let revision: Int?
    public let agentSession: AgentSessionRef?

    public init(paneID: String, terminalID: String? = nil, workspaceID: String,
                tabID: String? = nil, focused: Bool? = nil, cwd: String? = nil,
                agent: String? = nil, agentStatus: String? = nil, revision: Int? = nil,
                agentSession: AgentSessionRef? = nil) {
        self.paneID = paneID
        self.terminalID = terminalID
        self.workspaceID = workspaceID
        self.tabID = tabID
        self.focused = focused
        self.cwd = cwd
        self.agent = agent
        self.agentStatus = agentStatus
        self.revision = revision
        self.agentSession = agentSession
    }

    enum CodingKeys: String, CodingKey {
        case paneID = "pane_id"
        case terminalID = "terminal_id"
        case workspaceID = "workspace_id"
        case tabID = "tab_id"
        case focused, cwd, agent
        case agentStatus = "agent_status"
        case revision
        case agentSession = "agent_session"
    }
}

/// hooks連携導入時のみ載る、エージェントのネイティブセッション参照。
public struct AgentSessionRef: Decodable, Equatable {
    public let source: String?
    public let agent: String?
    public let kind: String?
    public let value: String?

    public init(source: String? = nil, agent: String? = nil, kind: String? = nil, value: String? = nil) {
        self.source = source
        self.agent = agent
        self.kind = kind
        self.value = value
    }
}

public struct WorkspaceInfo: Decodable, Equatable {
    public let workspaceID: String
    public let number: Int?
    public let label: String?
    public let focused: Bool?
    public let agentStatus: String?

    public init(workspaceID: String, number: Int? = nil, label: String? = nil,
                focused: Bool? = nil, agentStatus: String? = nil) {
        self.workspaceID = workspaceID
        self.number = number
        self.label = label
        self.focused = focused
        self.agentStatus = agentStatus
    }

    enum CodingKeys: String, CodingKey {
        case workspaceID = "workspace_id"
        case number, label, focused
        case agentStatus = "agent_status"
    }
}

public struct PaneListResult: Decodable {
    public let panes: [PaneInfo]
}

public struct WorkspaceListResult: Decodable {
    public let workspaces: [WorkspaceInfo]
}

/// pane.agent_status_changed の data（実測: revisionなし）
public struct AgentStatusChangedData: Decodable {
    public let paneID: String
    public let workspaceID: String?
    public let agent: String?
    public let agentStatus: String

    public init(paneID: String, workspaceID: String? = nil, agent: String? = nil, agentStatus: String) {
        self.paneID = paneID
        self.workspaceID = workspaceID
        self.agent = agent
        self.agentStatus = agentStatus
    }

    enum CodingKeys: String, CodingKey {
        case paneID = "pane_id"
        case workspaceID = "workspace_id"
        case agent
        case agentStatus = "agent_status"
    }
}

/// pane_created / pane_closed / pane_agent_detected 等の data（共通の緩い形）
public struct PaneLifecycleData: Decodable {
    public let paneID: String?
    public let workspaceID: String?
    public let agent: String?

    enum CodingKeys: String, CodingKey {
        case paneID = "pane_id"
        case workspaceID = "workspace_id"
        case agent
    }
}

// MARK: - JSONValue（任意のJSONを寛容に保持する）

public enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }

    /// ネストしたJSONValueを具体型へ再デコードする補助。
    public func reencoded<T: Decodable>(as type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(self)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByDictionaryLiteral, ExpressibleByArrayLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}
