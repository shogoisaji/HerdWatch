import XCTest
@testable import HerdWatch
import HerdWatchShared

final class CharacterSizeWalkAreaTests: XCTestCase {
    func testMinimumWindowHeightLeavesNonEmptyWalkAreaForEverySize() {
        for size in CharacterSize.allCases {
            let spriteSize = SpriteRenderer.spriteSize(pixelSize: size.pixelSize)
            let minHeight = AgentAnimator.minimumWindowHeight(pixelSize: size.pixelSize)
            let bounds = CGRect(x: 0, y: 0, width: 300, height: minHeight)
            let area = AgentAnimator.walkArea(bounds: bounds, spriteSize: spriteSize)
            XCTAssertFalse(area.isEmpty, "\(size)がアプリの最小ウィンドウ高さでwalkAreaを持てること")
        }
    }
}

final class PastureViewLabelTests: XCTestCase {
    func testTinyCharacterSizeUsesSmallerLabelFont() {
        let tiny = PastureView.labelFontSize(pixelSize: CharacterSize.tiny.pixelSize)
        let small = PastureView.labelFontSize(pixelSize: CharacterSize.small.pixelSize)
        XCTAssertEqual(tiny, small - 2, "極小は他サイズより2pt小さいこと")
    }

    func testNonTinyCharacterSizesShareTheDefaultLabelFontExceptLarge() {
        let small = PastureView.labelFontSize(pixelSize: CharacterSize.small.pixelSize)
        let medium = PastureView.labelFontSize(pixelSize: CharacterSize.medium.pixelSize)
        let large = PastureView.labelFontSize(pixelSize: CharacterSize.large.pixelSize)
        XCTAssertEqual(small, medium, "small/mediumはデフォルトサイズを共有")
        XCTAssertEqual(large, medium + 2, "Lサイズはデフォルトより+2pt大きいこと")
    }
}

final class PastureViewConnectionHintTests: XCTestCase {
    func testReconnectingHintIncludesAttemptNumber() {
        XCTAssertEqual(PastureView.reconnectingHint(attempt: 3),
                       "herdrへ再接続中(3回目)… herdrが起動しているか確認してください")
    }
}
