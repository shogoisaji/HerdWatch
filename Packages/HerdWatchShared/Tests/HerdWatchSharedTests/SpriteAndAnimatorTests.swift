import XCTest
@testable import HerdWatchShared

final class SpriteConsistencyTests: XCTestCase {
    func testAllFramesHaveConsistentDimensions() {
        for species in Species.allCases {
            let art = SpriteArt.art(for: species)
            for (name, frame) in [("idle", art.idle), ("blink", art.blink), ("sitBlink", art.sitBlink),
                                  ("walk0", art.walk0), ("walk1", art.walk1),
                                  ("walk2", art.walk2), ("walk3", art.walk3),
                                  ("sit", art.sit), ("carried0", art.carried0),
                                  ("carried1", art.carried1)] {
                XCTAssertEqual(frame.rows.count, SpriteFrame.height, "\(species) \(name) height")
                for (i, row) in frame.rows.enumerated() {
                    XCTAssertEqual(row.count, SpriteFrame.width, "\(species) \(name) row \(i) width")
                    XCTAssertTrue(row.allSatisfy { ".bwdaeh".contains($0) },
                                  "\(species) \(name) row \(i) has unknown char")
                }
            }
            XCTAssertTrue(art.idle.rows.joined().contains("e"), "\(species) idleに目があること")
            XCTAssertFalse(art.blink.rows.joined().contains("e"), "\(species) blinkは閉眼")
            XCTAssertFalse(art.sitBlink.rows.joined().contains("e"), "\(species) sitBlinkは閉眼")
        }
    }

    func testFrameSelectionIsDeterministicAndLoops() {
        let anim = Species.sheep.animation(for: .working)
        XCTAssertEqual(anim.frames.count, 4)
        XCTAssertEqual(anim.frame(elapsed: 0), anim.frames[0])
        XCTAssertEqual(anim.frame(elapsed: anim.frameDuration * 1.5), anim.frames[1])
        XCTAssertEqual(anim.frame(elapsed: anim.frameDuration * 2.5), anim.frames[2])
        XCTAssertEqual(anim.frame(elapsed: anim.frameDuration * 4.5), anim.frames[0])
    }

    func testWorkingAnimationUsesFourDistinctFramesForEverySpecies() {
        for species in Species.allCases {
            let frames = species.animation(for: .working).frames
            let distinctFrames = Set(frames.map { $0.rows.joined(separator: "\n") })
            XCTAssertEqual(frames.count, 4, "\(species) working frame count")
            XCTAssertEqual(distinctFrames.count, 4, "\(species) working frames should be distinct")
        }
    }

    func testSpriteResolutionIsOneLevelHigherWithoutChangingDisplayFootprint() {
        XCTAssertEqual(SpriteFrame.width, 32)
        XCTAssertEqual(SpriteFrame.height, 24)
        XCTAssertEqual(SpriteRenderer.spriteSize(pixelSize: 3), CGSize(width: 72, height: 54))
    }

    func testIdleLoopContainsBlink() {
        for species in Species.allCases {
            let anim = species.animation(for: .idle)
            let art = SpriteArt.art(for: species)
            XCTAssertTrue(anim.frames.contains(art.sitBlink), "\(species) idleループにまばたきが入ること")
        }
    }

    func testEveryStateHasAnimation() {
        for species in Species.allCases {
            for state in AgentState.allCases {
                XCTAssertFalse(species.animation(for: state).frames.isEmpty, "\(species)/\(state)")
            }
        }
    }
}

final class AgentAnimatorMathTests: XCTestCase {
    func testStepMovesTowardTargetAtSpeed() {
        let next = AgentAnimator.step(from: .zero, toward: CGPoint(x: 100, y: 0), speed: 30, dt: 1)
        XCTAssertEqual(next.x, 30, accuracy: 0.001)
        XCTAssertEqual(next.y, 0, accuracy: 0.001)
    }

    func testStepSnapsToTargetWhenClose() {
        let next = AgentAnimator.step(from: CGPoint(x: 99, y: 0), toward: CGPoint(x: 100, y: 0),
                                      speed: 30, dt: 1)
        XCTAssertEqual(next, CGPoint(x: 100, y: 0))
    }

    func testRandomPointStaysInBounds() {
        var rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
        let rect = CGRect(x: 10, y: 20, width: 200, height: 100)
        for _ in 0..<100 {
            let p = AgentAnimator.randomPoint(in: rect, using: &rng)
            XCTAssertTrue(rect.contains(p) || p.x == rect.maxX || p.y == rect.maxY)
        }
    }

    func testClampPullsBackIntoRect() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertEqual(AgentAnimator.clamp(CGPoint(x: -5, y: 300), to: rect), CGPoint(x: 0, y: 100))
    }

    func testHopOffsetParabola() {
        let d = AgentAnimator.hopDuration
        XCTAssertEqual(AgentAnimator.hopOffset(elapsed: 0, duration: d, height: 10), 0, accuracy: 0.001)
        XCTAssertEqual(AgentAnimator.hopOffset(elapsed: d / 2, duration: d, height: 10), -10, accuracy: 0.001)
        XCTAssertEqual(AgentAnimator.hopOffset(elapsed: d, duration: d, height: 10), 0, accuracy: 0.001)
        XCTAssertEqual(AgentAnimator.hopOffset(elapsed: d * 2, duration: d, height: 10), 0)
        XCTAssertLessThan(AgentAnimator.hopOffset(elapsed: d / 4, duration: d, height: 10), 0, "上方向=負")
    }

    func testWalkAreaIsSmallerThanBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 600, height: 400)
        let area = AgentAnimator.walkArea(bounds: bounds, spriteSize: CGSize(width: 64, height: 48))
        XCTAssertTrue(bounds.contains(area))
        XCTAssertLessThan(area.maxY, bounds.maxY, "下端はラベル分の余白を残す")
    }
}

/// シード固定の決定的RNG（再配置テストの結果を再現可能にする）
private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

final class AgentAnimatorCarryTests: XCTestCase {
    private let spriteSize = CGSize(width: 24, height: 18)
    private let bounds = CGRect(x: 0, y: 0, width: 300, height: 240)

    private func makeAgent(_ key: String) -> PastureAgent {
        PastureAgent(identity: AgentIdentity(key: key), paneID: "p", workspaceID: "w",
                     workspaceLabel: "W", agentLabel: "A", state: .idle,
                     character: CharacterAssignment(species: .cow, paletteIndex: 0), order: 0)
    }

    func testCarriedPositionUsesGrabOffset() {
        let position = AgentAnimator.carriedPosition(for: CGPoint(x: 100, y: 80), spriteSize: spriteSize)
        XCTAssertEqual(position.x, 88, accuracy: 0.001)
        XCTAssertEqual(position.y, 75.5, accuracy: 0.001)
    }

    func testEndCarryWithSpriteSizeStoresVisiblePosition() {
        let animator = AgentAnimator(rng: SeededRNG(seed: 9))
        let agent = makeAgent("a")
        _ = animator.tick(agents: [agent], bounds: bounds, spriteSize: spriteSize, time: 0)
        let grab = CGPoint(x: 100, y: 80)

        animator.beginCarry(agent.identity, at: grab)
        animator.endCarry(agent.identity, spriteSize: spriteSize, bounds: bounds)
        let result = animator.tick(agents: [agent], bounds: bounds, spriteSize: spriteSize, time: 0.1)[0]

        let expected = AgentAnimator.carriedPosition(for: grab, spriteSize: spriteSize)
        XCTAssertEqual(result.position.x, expected.x, accuracy: 0.001)
        XCTAssertEqual(result.position.y, expected.y, accuracy: 0.001)
    }

    /// endCarry(_:) 単体版も grab点をcarriedPositionへ変換して保存することを検証する。
    /// 変換しないとドラッグ中の描画位置から(width/2, height*0.25)だけ右下へズレる。
    func testEndCarrySimpleStoresCarriedPositionNotRawGrab() {
        let animator = AgentAnimator(rng: SeededRNG(seed: 9))
        let agent = makeAgent("a")
        // tick前にlastSpriteSizeが設定される必要がある
        _ = animator.tick(agents: [agent], bounds: bounds, spriteSize: spriteSize, time: 0)
        let grab = CGPoint(x: 100, y: 80)

        animator.beginCarry(agent.identity, at: grab)
        animator.endCarry(agent.identity)
        let result = animator.tick(agents: [agent], bounds: bounds, spriteSize: spriteSize, time: 0.1)[0]

        let expected = AgentAnimator.carriedPosition(for: grab, spriteSize: spriteSize)
        XCTAssertEqual(result.position.x, expected.x, accuracy: 0.001)
        XCTAssertEqual(result.position.y, expected.y, accuracy: 0.001)
    }

    func testClampedGrabPointKeepsVisiblePositionInWalkArea() {
        let grab = AgentAnimator.clampedGrabPoint(CGPoint(x: -100, y: -100),
                                                  spriteSize: spriteSize, bounds: bounds)
        let visiblePosition = AgentAnimator.carriedPosition(for: grab, spriteSize: spriteSize)
        let walkArea = AgentAnimator.walkArea(bounds: bounds, spriteSize: spriteSize)
        XCTAssertEqual(visiblePosition.x, walkArea.minX, accuracy: 0.001)
        XCTAssertEqual(visiblePosition.y, walkArea.minY, accuracy: 0.001)
    }

    func testSpriteOriginAreaUsesOnlyBoundsMinusSpriteSize() {
        let safeBounds = CGRect(x: 12, y: 34, width: 300, height: 240)
        let area = AgentAnimator.spriteOriginArea(in: safeBounds, spriteSize: spriteSize)
        XCTAssertEqual(area.minX, safeBounds.minX, accuracy: 0.001)
        XCTAssertEqual(area.minY, safeBounds.minY, accuracy: 0.001)
        XCTAssertEqual(area.maxX, safeBounds.maxX - spriteSize.width, accuracy: 0.001)
        XCTAssertEqual(area.maxY, safeBounds.maxY - spriteSize.height, accuracy: 0.001)
    }

    func testClampedGrabPointCanUseExplicitMovementAreaWithoutWalkAreaPadding() {
        let safeBounds = CGRect(x: 12, y: 34, width: 300, height: 240)
        let movementArea = AgentAnimator.spriteOriginArea(in: safeBounds, spriteSize: spriteSize)
        let grab = AgentAnimator.clampedGrabPoint(CGPoint(x: -100, y: -100),
                                                  spriteSize: spriteSize, movementArea: movementArea)
        let visiblePosition = AgentAnimator.carriedPosition(for: grab, spriteSize: spriteSize)
        XCTAssertEqual(visiblePosition.x, safeBounds.minX, accuracy: 0.001)
        XCTAssertEqual(visiblePosition.y, safeBounds.minY, accuracy: 0.001)
    }
}

final class AgentAnimatorResizeTests: XCTestCase {
    private let spriteSize = CGSize(width: 24, height: 24)
    private let wideBounds = CGRect(x: 0, y: 0, width: 800, height: 400)
    private let narrowBounds = CGRect(x: 0, y: 0, width: 300, height: 400)

    private func makeAgent(_ key: String) -> PastureAgent {
        PastureAgent(identity: AgentIdentity(key: key), paneID: "p", workspaceID: "w",
                     workspaceLabel: "W", agentLabel: "A", state: .idle,
                     character: CharacterAssignment(species: .cow, paletteIndex: 0), order: 0)
    }

    func testAutoRearrangeDisabledOnlyClampsIntoNewArea() {
        let animator = AgentAnimator()
        let agent = makeAgent("a")

        let placed = animator.tick(agents: [agent], bounds: wideBounds,
                                   spriteSize: spriteSize, time: 0)[0].position
        _ = animator.tick(agents: [agent], bounds: narrowBounds, spriteSize: spriteSize,
                          time: 0.1, autoRearrangeOnResize: false)
        let afterSettle = animator.tick(agents: [agent], bounds: narrowBounds, spriteSize: spriteSize,
                                        time: 10, autoRearrangeOnResize: false)[0].position

        let walkArea = AgentAnimator.walkArea(bounds: narrowBounds, spriteSize: spriteSize)
        XCTAssertEqual(afterSettle, AgentAnimator.clamp(placed, to: walkArea),
                       "無効時はクランプのみで、スキャッターは発生しない")
    }

    func testAutoRearrangeScattersOnlyAfterResizeSettles() {
        let animator = AgentAnimator(rng: SeededRNG(seed: 1))
        let agent = makeAgent("a")

        let placed = animator.tick(agents: [agent], bounds: wideBounds, spriteSize: spriteSize,
                                   time: 0, autoRearrangeOnResize: true)[0].position
        let walkArea = AgentAnimator.walkArea(bounds: narrowBounds, spriteSize: spriteSize)
        let clamped = AgentAnimator.clamp(placed, to: walkArea)

        // リサイズ直後（安定待ち時間内）はまだ再配置しない
        let justResized = animator.tick(agents: [agent], bounds: narrowBounds, spriteSize: spriteSize,
                                        time: 0.1, autoRearrangeOnResize: true)[0].position
        XCTAssertEqual(justResized, clamped)

        // 安定待ち時間を過ぎ、以後サイズ変化がなければ再配置される
        let settled = animator.tick(agents: [agent], bounds: narrowBounds, spriteSize: spriteSize,
                                    time: 0.1 + AgentAnimator.resizeSettleDelay + 0.01,
                                    autoRearrangeOnResize: true)[0].position
        XCTAssertNotEqual(settled, clamped, "再配置により座標が変わること")
        XCTAssertTrue(walkArea.contains(settled))
    }

    func testManualScatterCancelsPendingAutoRearrange() {
        let animator = AgentAnimator(rng: SeededRNG(seed: 3))
        let agent = makeAgent("a")

        _ = animator.tick(agents: [agent], bounds: wideBounds, spriteSize: spriteSize,
                          time: 0, autoRearrangeOnResize: true)
        // リサイズしてrearrangeDueAtを保留状態にする
        _ = animator.tick(agents: [agent], bounds: narrowBounds, spriteSize: spriteSize,
                          time: 0.1, autoRearrangeOnResize: true)

        // 保留中に手動scatter（⌘R相当）を呼ぶ
        animator.scatter(agents: [agent])
        let afterManualScatter = animator.tick(agents: [agent], bounds: narrowBounds, spriteSize: spriteSize,
                                               time: 0.11, autoRearrangeOnResize: true)[0].position

        // 安定待ち時間を過ぎても、手動scatterで保留がキャンセル済みなので再配置されないこと
        let afterSettleWindow = animator.tick(agents: [agent], bounds: narrowBounds, spriteSize: spriteSize,
                                              time: 0.1 + AgentAnimator.resizeSettleDelay + 0.05,
                                              autoRearrangeOnResize: true)[0].position
        XCTAssertEqual(afterSettleWindow, afterManualScatter,
                      "手動scatter直後は保留中の自動再配置が二重に発火しないこと")
    }

    func testStaleDueAtDoesNotFireAfterReenablingWithoutNewResize() {
        let animator = AgentAnimator(rng: SeededRNG(seed: 5))
        let agent = makeAgent("a")

        _ = animator.tick(agents: [agent], bounds: wideBounds, spriteSize: spriteSize,
                          time: 0, autoRearrangeOnResize: true)
        // リサイズでrearrangeDueAtを保留状態にする
        let afterResize = animator.tick(agents: [agent], bounds: narrowBounds, spriteSize: spriteSize,
                                        time: 0.1, autoRearrangeOnResize: true)[0].position

        // 保留中にオフへ（発火せず時刻だけが取り残される）
        _ = animator.tick(agents: [agent], bounds: narrowBounds, spriteSize: spriteSize,
                          time: 0.1 + AgentAnimator.resizeSettleDelay + 0.05, autoRearrangeOnResize: false)

        // 新たなリサイズを挟まずに再度オンにしても、古い予定時刻で即scatterしないこと
        let afterReenable = animator.tick(agents: [agent], bounds: narrowBounds, spriteSize: spriteSize,
                                          time: 10, autoRearrangeOnResize: true)[0].position

        let walkArea = AgentAnimator.walkArea(bounds: narrowBounds, spriteSize: spriteSize)
        XCTAssertEqual(afterReenable, AgentAnimator.clamp(afterResize, to: walkArea),
                      "リサイズを伴わない再有効化では、古い予定時刻が再利用されないこと")
    }
}

final class AgentAnimatorWorkspaceGroupingTests: XCTestCase {
    private let spriteSize = CGSize(width: 24, height: 24)
    private let bounds = CGRect(x: 0, y: 0, width: 800, height: 400)

    private func makeAgent(_ key: String, workspace: String, order: Int) -> PastureAgent {
        PastureAgent(identity: AgentIdentity(key: key), paneID: "p-\(key)", workspaceID: workspace,
                     workspaceLabel: workspace, agentLabel: "A", state: .idle,
                     character: CharacterAssignment(species: .cow, paletteIndex: 0), order: order)
    }

    func testOrderedWorkspaceIDsFollowsFirstAppearanceOrder() {
        let agents = [
            makeAgent("b1", workspace: "beta", order: 2),
            makeAgent("a1", workspace: "alpha", order: 0),
            makeAgent("a2", workspace: "alpha", order: 1),
            makeAgent("b2", workspace: "beta", order: 3),
        ]
        XCTAssertEqual(AgentAnimator.orderedWorkspaceIDs(from: agents), ["alpha", "beta"])
    }

    func testScatterGroupsAgentsIntoPerWorkspaceBands() {
        let animator = AgentAnimator(rng: SeededRNG(seed: 7))
        let agents = [
            makeAgent("a1", workspace: "alpha", order: 0),
            makeAgent("a2", workspace: "alpha", order: 1),
            makeAgent("b1", workspace: "beta", order: 2),
            makeAgent("b2", workspace: "beta", order: 3),
        ]
        // walkAreaを確定させるため一度tickしてから再配置する
        _ = animator.tick(agents: agents, bounds: bounds, spriteSize: spriteSize, time: 0)
        animator.scatter(agents: agents)
        let result = animator.tick(agents: agents, bounds: bounds, spriteSize: spriteSize, time: 0.001)
        let xByKey = Dictionary(uniqueKeysWithValues: result.map { ($0.agent.identity.key, $0.position.x) })

        let walkArea = AgentAnimator.walkArea(bounds: bounds, spriteSize: spriteSize)
        let bandBoundary = walkArea.minX + walkArea.width / 2

        XCTAssertLessThanOrEqual(xByKey["a1"]!, bandBoundary + 0.001, "同一workspaceは同じ帯に収まること")
        XCTAssertLessThanOrEqual(xByKey["a2"]!, bandBoundary + 0.001)
        XCTAssertGreaterThan(xByKey["b1"]!, bandBoundary - 0.001, "別workspaceは別の帯に収まること")
        XCTAssertGreaterThan(xByKey["b2"]!, bandBoundary - 0.001)
    }
}

final class SilhouettePathTests: XCTestCase {
    private func frame(markingAt points: [(x: Int, y: Int)]) -> SpriteFrame {
        var rows = Array(repeating: String(repeating: ".", count: SpriteFrame.width), count: SpriteFrame.height)
        for p in points {
            var chars = Array(rows[p.y])
            chars[p.x] = "b"
            rows[p.y] = String(chars)
        }
        return SpriteFrame(rows: rows)
    }

    func testBoundingBoxMatchesOpaquePixelsWhenFacingLeft() {
        let f = frame(markingAt: [(x: 2, y: 3), (x: 5, y: 3)])
        let path = SpriteRenderer.silhouettePath(frame: f, pixelSize: 2, at: .zero, facing: .left)
        let rect = path.boundingRect
        let cellSize = SpriteRenderer.cellSize(pixelSize: 2)
        XCTAssertEqual(rect.minX, CGFloat(2) * cellSize)
        XCTAssertEqual(rect.maxX, CGFloat(5 + 1) * cellSize)
        XCTAssertEqual(rect.minY, CGFloat(3) * cellSize)
        XCTAssertEqual(rect.maxY, CGFloat(3 + 1) * cellSize)
    }

    func testMirrorsHorizontallyWhenFacingRight() {
        let f = frame(markingAt: [(x: 2, y: 3)])
        let path = SpriteRenderer.silhouettePath(frame: f, pixelSize: 2, at: .zero, facing: .right)
        let mirroredX = SpriteFrame.width - 1 - 2
        XCTAssertEqual(path.boundingRect.minX,
                       CGFloat(mirroredX) * SpriteRenderer.cellSize(pixelSize: 2))
    }

    func testEmptyWhenFrameIsFullyTransparent() {
        let f = frame(markingAt: [])
        let path = SpriteRenderer.silhouettePath(frame: f, pixelSize: 2, at: .zero, facing: .left)
        XCTAssertTrue(path.isEmpty)
    }
}

final class HitTestTests: XCTestCase {
    private let a = AgentIdentity(key: "a")
    private let b = AgentIdentity(key: "b")

    func testFrontmostWinsOnOverlap() {
        // 配列は奥→手前の順（描画順）
        let entries = [(a, CGRect(x: 0, y: 0, width: 50, height: 50)),
                       (b, CGRect(x: 25, y: 25, width: 50, height: 50))]
        XCTAssertEqual(hitTest(point: CGPoint(x: 40, y: 40), entries: entries), b)
        XCTAssertEqual(hitTest(point: CGPoint(x: 10, y: 10), entries: entries), a)
    }

    func testPaddingExtendsHitArea() {
        let entries = [(a, CGRect(x: 100, y: 100, width: 20, height: 20))]
        XCTAssertEqual(hitTest(point: CGPoint(x: 96, y: 100), entries: entries, padding: 6), a)
        XCTAssertNil(hitTest(point: CGPoint(x: 90, y: 100), entries: entries, padding: 6))
    }

    func testMissReturnsNil() {
        XCTAssertNil(hitTest(point: .zero, entries: []))
    }
}
