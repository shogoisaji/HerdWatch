import XCTest
@testable import HerdWatchShared

/// working状態の経過時間表示の書式化（19s / 90m / 2h のような最小単位の整数+単位）。
/// 境界: <60s→s, <60m→m, ≥60m→h（60m=1h）。
final class WorkingElapsedFormatterTests: XCTestCase {
    func testSecondsUnderOneMinute() {
        XCTAssertEqual(WorkingElapsedFormatter.format(seconds: 0), "0s")
        XCTAssertEqual(WorkingElapsedFormatter.format(seconds: 19), "19s")
        XCTAssertEqual(WorkingElapsedFormatter.format(seconds: 59), "59s")
    }

    func testMinutesUnderOneHour() {
        XCTAssertEqual(WorkingElapsedFormatter.format(seconds: 60), "1m")
        XCTAssertEqual(WorkingElapsedFormatter.format(seconds: 59 * 60 + 59), "59m")
    }

    func testHoursAtAndAboveOneHour() {
        XCTAssertEqual(WorkingElapsedFormatter.format(seconds: 60 * 60), "1h")
        XCTAssertEqual(WorkingElapsedFormatter.format(seconds: 2 * 60 * 60), "2h")
        XCTAssertEqual(WorkingElapsedFormatter.format(seconds: 25 * 60 * 60), "25h")
    }

    func testNegativeClampsToZero() {
        XCTAssertEqual(WorkingElapsedFormatter.format(seconds: -5), "0s")
    }
}
