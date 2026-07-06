import XCTest
@testable import HerdWatchShared

final class ShadowSpriteCacheTests: XCTestCase {
    func testPaddingIsDoubleBlurRadius() {
        // blur radius = pixelSize * 0.5, padding = radius * 2 = pixelSize
        XCTAssertEqual(ShadowSpriteCache.padding(for: 4), 4)
        XCTAssertEqual(ShadowSpriteCache.padding(for: 1.5), 1.5)
    }

    func testImageSizeIsSpritePlusPaddingBothSides() {
        let spriteSize = CGSize(width: 100, height: 80)
        let size = ShadowSpriteCache.imageSize(spriteSize: spriteSize, pixelSize: 4)
        // padding = 4, both sides = 8
        XCTAssertEqual(size.width, 108)
        XCTAssertEqual(size.height, 88)
    }

    func testDrawOffsetIsOriginMinusPadding() {
        let origin = CGPoint(x: 50, y: 30)
        let offset = ShadowSpriteCache.drawOffset(origin: origin, pixelSize: 4)
        XCTAssertEqual(offset.x, 46)
        XCTAssertEqual(offset.y, 26)
    }

    func testKeyEqualityByFrameFacingPixelSize() {
        let frame = SpriteFrame(rows: [".."])
        let k1 = ShadowSpriteCache.Key(frame: frame, facing: .left, pixelSize: 4)
        let k2 = ShadowSpriteCache.Key(frame: frame, facing: .left, pixelSize: 4)
        XCTAssertEqual(k1, k2)
        let k3 = ShadowSpriteCache.Key(frame: frame, facing: .right, pixelSize: 4)
        XCTAssertNotEqual(k1, k3)
        let k4 = ShadowSpriteCache.Key(frame: frame, facing: .left, pixelSize: 3)
        XCTAssertNotEqual(k1, k4)
    }
}
