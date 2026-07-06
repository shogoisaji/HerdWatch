import SwiftUI

/// herdrが報告するエージェント状態の鏡写し（独自解釈を加えない: ADR-0001）。
public enum AgentState: String, Codable, CaseIterable, Hashable {
    case idle
    case working
    case blocked
    case done
    case unknown

    public init(raw: String?) {
        self = raw.flatMap(AgentState.init(rawValue:)) ?? .unknown
    }

    /// 状態の代表色。バッジ・ラベル枠など状態を示す表現全体で共有する。idleは無色（強調しない）。
    public var accentColor: Color? {
        switch self {
        case .idle: nil
        case .working: Color(red: 0.25, green: 0.62, blue: 0.90)
        case .blocked: Color(red: 0.92, green: 0.30, blue: 0.32)
        case .done: Color(red: 0.30, green: 0.72, blue: 0.42)
        case .unknown: Color(red: 0.55, green: 0.55, blue: 0.58)
        }
    }
}
