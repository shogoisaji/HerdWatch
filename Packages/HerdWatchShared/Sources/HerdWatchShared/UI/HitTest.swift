import Foundation

/// 直近tickの当たり判定レジストリ。描画パスが毎tick更新する。
final public class HitRegistry {
    /// 描画順（奥→手前）で積まれる
    public private(set) var entries: [(identity: AgentIdentity, rect: CGRect)] = []

    public init() {}

    public func reset() {
        entries.removeAll(keepingCapacity: true)
    }

    public func register(_ identity: AgentIdentity, rect: CGRect) {
        entries.append((identity, rect))
    }

    public func hit(at point: CGPoint) -> AgentIdentity? {
        hitTest(point: point, entries: entries)
    }
}

/// 手前（配列の後方=yが大きい）から走査する純関数。
public func hitTest(point: CGPoint, entries: [(identity: AgentIdentity, rect: CGRect)],
             padding: CGFloat = 6) -> AgentIdentity? {
    for entry in entries.reversed() {
        if entry.rect.insetBy(dx: -padding, dy: -padding).contains(point) {
            return entry.identity
        }
    }
    return nil
}
