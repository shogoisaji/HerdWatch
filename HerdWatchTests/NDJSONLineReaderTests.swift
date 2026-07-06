import XCTest
@testable import HerdWatch

final class NDJSONLineReaderTests: XCTestCase {
    func testSingleCompleteLine() {
        var reader = NDJSONLineReader()
        let lines = reader.append(Data("{\"a\":1}\n".utf8))
        XCTAssertEqual(lines.map { String(data: $0, encoding: .utf8) }, ["{\"a\":1}"])
    }

    func testLineSplitAcrossChunks() {
        var reader = NDJSONLineReader()
        XCTAssertTrue(reader.append(Data("{\"a\":".utf8)).isEmpty)
        let lines = reader.append(Data("1}\n{\"b\":".utf8))
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(String(data: lines[0], encoding: .utf8), "{\"a\":1}")
        let more = reader.append(Data("2}\n".utf8))
        XCTAssertEqual(String(data: more[0], encoding: .utf8), "{\"b\":2}")
    }

    func testMultipleLinesInOneChunk() {
        var reader = NDJSONLineReader()
        let lines = reader.append(Data("{\"a\":1}\n{\"b\":2}\n{\"c\":3}\n".utf8))
        XCTAssertEqual(lines.count, 3)
    }

    func testUTF8SplitMidCharacter() {
        var reader = NDJSONLineReader()
        let full = Data("{\"label\":\"羊\"}\n".utf8)
        // マルチバイト文字の途中で分割
        let cut = full.count - 4
        XCTAssertTrue(reader.append(full.prefix(cut)).isEmpty)
        let lines = reader.append(full.suffix(from: cut))
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(String(data: lines[0], encoding: .utf8), "{\"label\":\"羊\"}")
    }

    func testEmptyLinesSkipped() {
        var reader = NDJSONLineReader()
        let lines = reader.append(Data("\n\n{\"a\":1}\n\n".utf8))
        XCTAssertEqual(lines.count, 1)
    }

    func testFlushReturnsPartialLine() {
        var reader = NDJSONLineReader()
        _ = reader.append(Data("{\"a\":1}".utf8))
        XCTAssertEqual(reader.flush(), Data("{\"a\":1}".utf8))
        XCTAssertNil(reader.flush())
    }
}
