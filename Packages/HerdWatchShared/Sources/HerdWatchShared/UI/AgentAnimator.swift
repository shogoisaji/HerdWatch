import Foundation
import SwiftUI

/// キャラ1体の描画時点の姿。
public struct AnimatedCharacter {
    public let agent: PastureAgent
    public let position: CGPoint      // スプライト左上
    public let facing: Facing
    public let bobOffset: CGFloat     // blockedの跳ね（描画時にyへ加算する負値）
    public let isCarried: Bool        // ドラッグ中（首掴まれ・脚バタバタ）

    public init(agent: PastureAgent, position: CGPoint, facing: Facing,
                bobOffset: CGFloat, isCarried: Bool) {
        self.agent = agent
        self.position = position
        self.facing = facing
        self.bobOffset = bobOffset
        self.isCarried = isCarried
    }
}

/// 各エージェントの位置・向き・移動目標を保持する描画側の状態機械。
/// ストアの状態（AgentState）には一切書き戻さない。
final public class AgentAnimator {
    public struct Motion {
        public var position: CGPoint
        public var target: CGPoint?
        public var facing: Facing = .left
        public var nextDecisionAt: TimeInterval = 0

        public init(position: CGPoint, target: CGPoint? = nil, facing: Facing = .left,
                    nextDecisionAt: TimeInterval = 0) {
            self.position = position
            self.target = target
            self.facing = facing
            self.nextDecisionAt = nextDecisionAt
        }
    }

    // working中でも視線を奪わないよう、移動はゆっくり・まれ・近距離に留める
    // （足踏みアニメーションが主表現、移動は従）。
    public static let walkSpeed: CGFloat = 14           // pt/秒
    public static let wanderRadius: CGFloat = 44        // 1回の移動の最大距離
    public static let wanderInterval: ClosedRange<TimeInterval> = 8...16

    public static let hopDuration: TimeInterval = 0.35

    /// ウィンドウリサイズが止んでから再配置を行うまでの安定待ち時間（連続リサイズ中は毎tick延長される）
    public static let resizeSettleDelay: TimeInterval = 0.5

    private var motions: [AgentIdentity: Motion] = [:]
    private var carried: [AgentIdentity: CGPoint] = [:]  // ドラッグ中の掴み位置（カーソル）
    private var hops: [AgentIdentity: TimeInterval] = [:]  // フォーカス指示の反応ホップ開始時刻
    private var lastTick: TimeInterval?
    private var lastWalkArea: CGRect?
    private var lastSpriteSize: CGSize = .zero  // endCarry(_) の座標変換用に直近tickのspriteSizeを保持
    private var rearrangeDueAt: TimeInterval?
    private var rng: any RandomNumberGenerator

    public init(rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.rng = rng
    }

    /// 全キャラを互いに離れた位置へ再配置する（固まり解消用）。
    /// workspaceごとに帯状の領域へ振り分けることで、同じworkspaceのキャラがまとまって見えるようにする
    /// （配置アルゴリズム自体はspawnPointのまま。帯の並び順と範囲だけを変えている）。
    public func scatter(agents: [PastureAgent]) {
        rearrangeDueAt = nil
        guard let area = lastWalkArea, !area.isEmpty else { return }
        let workspaceOrder = Self.orderedWorkspaceIDs(from: agents)
        guard !workspaceOrder.isEmpty else { return }
        let bandWidth = area.width / CGFloat(workspaceOrder.count)

        var placed: [CGPoint] = []
        for (bandIndex, workspaceID) in workspaceOrder.enumerated() {
            let band = CGRect(x: area.minX + CGFloat(bandIndex) * bandWidth, y: area.minY,
                              width: bandWidth, height: area.height)
            let members = agents
                .filter { $0.workspaceID == workspaceID && motions[$0.identity] != nil }
                .sorted { $0.order < $1.order }
            let minDistance = max(band.width, band.height) / CGFloat(max(2, members.count))
            for agent in members {
                let point = Self.spawnPoint(in: band, avoiding: placed,
                                            minDistance: minDistance, using: &rng)
                placed.append(point)
                motions[agent.identity]?.position = point
                motions[agent.identity]?.target = nil
            }
        }
    }

    /// workspaceの並び順（初登場順で安定させる）
    public static func orderedWorkspaceIDs(from agents: [PastureAgent]) -> [String] {
        var seen = Set<String>()
        var order: [String] = []
        for agent in agents.sorted(by: { $0.order < $1.order }) {
            if seen.insert(agent.workspaceID).inserted {
                order.append(agent.workspaceID)
            }
        }
        return order
    }

    /// フォーカス指示への反応: 小さく1回跳ねる。
    public func triggerHop(_ identity: AgentIdentity, at time: TimeInterval) {
        hops[identity] = time
    }

    // MARK: - ドラッグ

    public func beginCarry(_ identity: AgentIdentity, at point: CGPoint) {
        carried[identity] = point
    }

    public func updateCarry(_ identity: AgentIdentity, to point: CGPoint) {
        guard carried[identity] != nil else { return }
        carried[identity] = point
    }

    public func endCarry(_ identity: AgentIdentity) {
        guard let point = carried.removeValue(forKey: identity) else { return }
        // grab点(カーソル)を「首を掴んだ見た目」のキャラ左上位置へ変換して保存する。
        // 変換しないとドラッグ中の描画位置から(width/2, height*0.25)だけ右下へズレる。
        // walkArea外にドロップした場合は次tickのclampが引き戻す。
        motions[identity]?.position = Self.carriedPosition(for: point, spriteSize: lastSpriteSize)
        motions[identity]?.target = nil
    }

    public func endCarry(_ identity: AgentIdentity, spriteSize: CGSize, bounds: CGRect) {
        endCarry(identity, spriteSize: spriteSize,
                 movementArea: Self.walkArea(bounds: bounds, spriteSize: spriteSize))
    }

    public func endCarry(_ identity: AgentIdentity, spriteSize: CGSize, movementArea: CGRect) {
        guard let point = carried.removeValue(forKey: identity) else { return }
        let clampedGrab = Self.clampedGrabPoint(point, spriteSize: spriteSize, movementArea: movementArea)
        motions[identity]?.position = Self.carriedPosition(for: clampedGrab, spriteSize: spriteSize)
        motions[identity]?.target = nil
    }

    public var isCarrying: Bool { !carried.isEmpty }

    public func tick(agents: [PastureAgent],
              bounds: CGRect,
              spriteSize: CGSize,
              time: TimeInterval,
              autoRearrangeOnResize: Bool = false,
              movementArea: CGRect? = nil) -> [AnimatedCharacter] {
        let dt = lastTick.map { min(0.25, time - $0) } ?? 0
        lastTick = time
        lastSpriteSize = spriteSize

        let walkArea = movementArea ?? Self.walkArea(bounds: bounds, spriteSize: spriteSize)
        // サイズが変わるたびに再配置予定時刻を先送り（連続リサイズ中はデバウンスされる）
        if autoRearrangeOnResize, let previous = lastWalkArea, previous.size != walkArea.size {
            rearrangeDueAt = time + Self.resizeSettleDelay
        }
        lastWalkArea = walkArea
        if let due = rearrangeDueAt, time >= due {
            rearrangeDueAt = nil
            if autoRearrangeOnResize {
                scatter(agents: agents)
            }
        }
        var result: [AnimatedCharacter] = []
        var seen = Set<AgentIdentity>()

        for agent in agents {
            seen.insert(agent.identity)
            var motion = motions[agent.identity]
                ?? Motion(position: Self.spawnPoint(in: walkArea,
                                                    avoiding: motions.values.map(\.position),
                                                    minDistance: spriteSize.width * 1.1,
                                                    using: &rng))

            // ドラッグ中: カーソルに追従（首の付け根あたりを掴んでいる見た目になる位置）
            if let grabPoint = carried[agent.identity] {
                let held = Self.carriedPosition(for: grabPoint, spriteSize: spriteSize)
                motions[agent.identity] = motion
                result.append(AnimatedCharacter(agent: agent,
                                                position: held,
                                                facing: motion.facing,
                                                bobOffset: 0,
                                                isCarried: true))
                continue
            }

            switch agent.state {
            case .working:
                // 足踏みが主表現。移動はまれに・近距離だけ（視線を奪わない）
                if time >= motion.nextDecisionAt {
                    motion.target = Self.wanderTarget(from: motion.position,
                                                      radius: Self.wanderRadius,
                                                      in: walkArea, using: &rng)
                    motion.nextDecisionAt = time + TimeInterval.random(
                        in: Self.wanderInterval, using: &rng)
                }
                if let target = motion.target, !Self.reached(motion.position, target) {
                    let before = motion.position
                    motion.position = Self.step(from: before, toward: target,
                                                speed: Self.walkSpeed, dt: dt)
                    if abs(target.x - before.x) > 1 {
                        motion.facing = target.x < before.x ? .left : .right
                    }
                } else {
                    motion.target = nil
                }
            case .idle, .blocked, .done, .unknown:
                motion.target = nil
            }

            // ウィンドウリサイズで場外に出たら引き戻す
            motion.position = Self.clamp(motion.position, to: walkArea)

            var bob: CGFloat = agent.state == .blocked
                ? -abs(sin(time * 5.5)) * spriteSize.height * 0.18
                : 0
            if agent.state == .idle {
                bob += spriteSize.height / CGFloat(SpriteFrame.height)
            }
            if let hopStart = hops[agent.identity] {
                let elapsed = time - hopStart
                if elapsed < Self.hopDuration {
                    bob += Self.hopOffset(elapsed: elapsed, duration: Self.hopDuration,
                                          height: spriteSize.height * 0.22)
                } else {
                    hops.removeValue(forKey: agent.identity)
                }
            }

            motions[agent.identity] = motion
            result.append(AnimatedCharacter(agent: agent,
                                            position: motion.position,
                                            facing: motion.facing,
                                            bobOffset: bob,
                                            isCarried: false))
        }

        motions = motions.filter { seen.contains($0.key) }
        carried = carried.filter { seen.contains($0.key) }
        hops = hops.filter { seen.contains($0.key) }
        // 描画順（後ろ→前）: idle → アクティブ(not idle) → 持ち上げ中。同グループ内はy昇順の擬似奥行き
        return result.sorted {
            if $0.isCarried != $1.isCarried { return $1.isCarried }
            let lhsActive = $0.agent.state != .idle
            let rhsActive = $1.agent.state != .idle
            if lhsActive != rhsActive { return rhsActive }
            return $0.position.y < $1.position.y
        }
    }

    // MARK: - 純関数（テスト対象）

    public static func walkArea(bounds: CGRect, spriteSize: CGSize) -> CGRect {
        // 下部はラベル分の余白、上部はバッジ・炎（頭上~11px分）の余白を確保
        bounds.insetBy(dx: spriteSize.width * 0.2, dy: spriteSize.height * 0.65)
            .divided(atDistance: spriteSize.width, from: .maxXEdge).remainder
            .divided(atDistance: spriteSize.height * 1.6, from: .maxYEdge).remainder
    }

    public static func spriteOriginArea(in bounds: CGRect, spriteSize: CGSize) -> CGRect {
        CGRect(x: bounds.minX,
               y: bounds.minY,
               width: max(0, bounds.width - spriteSize.width),
               height: max(0, bounds.height - spriteSize.height))
    }

    /// walkAreaが歩けるだけの面積を持つために必要なウィンドウ最小高さ。
    /// walkAreaはspriteSize.height×2.9を余白として消費するため、それに歩行分の余白を上乗せする。
    public static func minimumWindowHeight(pixelSize: CGFloat) -> CGFloat {
        let spriteHeight = CGFloat(SpriteFrame.height) * pixelSize
        return (spriteHeight * 3.9).rounded(.up)
    }

    public static func step(from: CGPoint, toward target: CGPoint, speed: CGFloat, dt: TimeInterval) -> CGPoint {
        let dx = target.x - from.x
        let dy = target.y - from.y
        let distance = sqrt(dx * dx + dy * dy)
        let maxMove = speed * CGFloat(dt)
        guard distance > maxMove, distance > 0 else { return target }
        return CGPoint(x: from.x + dx / distance * maxMove,
                       y: from.y + dy / distance * maxMove)
    }

    /// 単発ホップの放物線オフセット（開始・終了で0、中間で最大。負=上方向）。
    public static func hopOffset(elapsed: TimeInterval, duration: TimeInterval, height: CGFloat) -> CGFloat {
        guard elapsed >= 0, elapsed < duration, duration > 0 else { return 0 }
        return -height * CGFloat(sin(.pi * elapsed / duration))
    }

    public static func reached(_ position: CGPoint, _ target: CGPoint?) -> Bool {
        guard let target else { return true }
        return hypot(target.x - position.x, target.y - position.y) < 2
    }

    public static func clamp(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        guard !rect.isEmpty else { return point }
        return CGPoint(x: min(max(point.x, rect.minX), rect.maxX),
                       y: min(max(point.y, rect.minY), rect.maxY))
    }

    public static func carriedPosition(for grabPoint: CGPoint, spriteSize: CGSize) -> CGPoint {
        CGPoint(x: grabPoint.x - spriteSize.width / 2,
                y: grabPoint.y - spriteSize.height * 0.25)
    }

    public static func clampedGrabPoint(_ grabPoint: CGPoint, spriteSize: CGSize, bounds: CGRect) -> CGPoint {
        clampedGrabPoint(grabPoint, spriteSize: spriteSize,
                         movementArea: walkArea(bounds: bounds, spriteSize: spriteSize))
    }

    public static func clampedGrabPoint(_ grabPoint: CGPoint, spriteSize: CGSize,
                                        movementArea: CGRect) -> CGPoint {
        let position = clamp(carriedPosition(for: grabPoint, spriteSize: spriteSize), to: movementArea)
        return CGPoint(x: position.x + spriteSize.width / 2,
                       y: position.y + spriteSize.height * 0.25)
    }

    /// 現在地の近傍からランダムな移動先を選ぶ（walkAreaへクランプ）。
    public static func wanderTarget(from position: CGPoint, radius: CGFloat,
                             in rect: CGRect, using rng: inout any RandomNumberGenerator) -> CGPoint {
        var box = AnyRNG(base: rng)
        defer { rng = box.base }
        let angle = CGFloat.random(in: 0..<(2 * .pi), using: &box)
        let distance = CGFloat.random(in: (radius * 0.3)...radius, using: &box)
        let raw = CGPoint(x: position.x + cos(angle) * distance,
                          y: position.y + sin(angle) * distance)
        return clamp(raw, to: rect)
    }

    /// 既存キャラとの重なりを避けたスポーン位置。候補を複数引き、最も離れたものを選ぶ。
    public static func spawnPoint(in rect: CGRect, avoiding others: [CGPoint],
                           minDistance: CGFloat,
                           using rng: inout any RandomNumberGenerator) -> CGPoint {
        var best = randomPoint(in: rect, using: &rng)
        guard !others.isEmpty else { return best }
        var bestDistance: CGFloat = -1
        for _ in 0..<12 {
            let candidate = randomPoint(in: rect, using: &rng)
            let nearest = others.map { hypot($0.x - candidate.x, $0.y - candidate.y) }.min() ?? .infinity
            if nearest >= minDistance { return candidate }
            if nearest > bestDistance {
                bestDistance = nearest
                best = candidate
            }
        }
        return best
    }

    public static func randomPoint(in rect: CGRect, using rng: inout any RandomNumberGenerator) -> CGPoint {
        guard !rect.isEmpty else { return CGPoint(x: rect.midX, y: rect.midY) }
        var box = AnyRNG(base: rng)
        defer { rng = box.base }
        return CGPoint(x: CGFloat.random(in: rect.minX...rect.maxX, using: &box),
                       y: CGFloat.random(in: rect.minY...rect.maxY, using: &box))
    }
}

private extension TimeInterval {
    static func random(in range: ClosedRange<TimeInterval>,
                       using rng: inout any RandomNumberGenerator) -> TimeInterval {
        var box = AnyRNG(base: rng)
        defer { rng = box.base }
        return TimeInterval.random(in: range, using: &box)
    }
}
