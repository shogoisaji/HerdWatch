import XCTest
@testable import HerdWatch

final class SettingsLocalizationTests: XCTestCase {
    func testCharacterSizeAllCasesAreOrderedFromSmallestToLargest() {
        let sizes = CharacterSize.allCases.map(\.pixelSize)
        XCTAssertEqual(sizes, sizes.sorted(), "Picker表示順=小さい順であること")
    }

    func testTinyIsSmallerThanSmall() {
        XCTAssertLessThan(CharacterSize.tiny.pixelSize, CharacterSize.small.pixelSize)
    }

    func testCharacterSizeLabelsAreLanguageAware() {
        XCTAssertEqual(CharacterSize.tiny.label(for: .english), "XS")
        XCTAssertEqual(CharacterSize.tiny.label(for: .japanese), "極小")
        XCTAssertEqual(CharacterSize.large.label(for: .english), "L")
        XCTAssertEqual(CharacterSize.large.label(for: .japanese), "大")
    }

    func testSettingsStringsDefaultToEnglish() {
        let strings = SettingsStrings(language: .english)
        XCTAssertEqual(strings.windowSection, "Window")
        XCTAssertEqual(strings.alwaysOnTop, "Always on top")
        XCTAssertEqual(strings.characterSection, "Character")
    }

    func testSettingsStringsSwitchToJapanese() {
        let strings = SettingsStrings(language: .japanese)
        XCTAssertEqual(strings.windowSection, "ウィンドウ")
        XCTAssertEqual(strings.alwaysOnTop, "常に最前面に表示")
        XCTAssertEqual(strings.characterSection, "キャラクター")
    }

    func testPastureBackgroundCasesAreInPickerOrder() {
        XCTAssertEqual(PastureBackground.allCases, [.grassland, .wasteland, .brick])
    }

    func testPastureBackgroundLabelsAreLanguageAware() {
        XCTAssertEqual(PastureBackground.grassland.label(for: .english), "Grassland")
        XCTAssertEqual(PastureBackground.grassland.label(for: .japanese), "草原")
        XCTAssertEqual(PastureBackground.wasteland.label(for: .english), "Wasteland")
        XCTAssertEqual(PastureBackground.wasteland.label(for: .japanese), "荒野")
        XCTAssertEqual(PastureBackground.brick.label(for: .english), "Brick")
        XCTAssertEqual(PastureBackground.brick.label(for: .japanese), "レンガ")
    }

    func testSettingsStringsBackgroundSectionIsLanguageAware() {
        XCTAssertEqual(SettingsStrings(language: .english).backgroundSection, "Background")
        XCTAssertEqual(SettingsStrings(language: .japanese).backgroundSection, "背景")
    }

    func testSettingsStringsShowWorkingElapsedIsLanguageAware() {
        XCTAssertEqual(SettingsStrings(language: .english).showWorkingElapsed, "Show working elapsed time")
        XCTAssertEqual(SettingsStrings(language: .japanese).showWorkingElapsed, "作業中の経過時間を表示")
    }
}
