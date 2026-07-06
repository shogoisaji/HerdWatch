import XCTest
@testable import HerdWatchShared

final class CharacterAssignmentStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("herdwatch-assign-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testStableAssignmentAcrossLookups() {
        let store = CharacterAssignmentStore(directory: tempDir)
        let identity = AgentIdentity(key: "pane:wA:p1|claude")
        let first = store.assignment(for: identity)
        XCTAssertEqual(store.assignment(for: identity), first)
    }

    func testPersistenceRoundTrip() {
        let identity = AgentIdentity(key: "session:sess-1")
        let first = CharacterAssignmentStore(directory: tempDir).assignment(for: identity)
        // 別インスタンス（=アプリ再起動相当）でも同じ割当
        let reloaded = CharacterAssignmentStore(directory: tempDir).assignment(for: identity)
        XCTAssertEqual(reloaded, first)
    }

    func testRerollAlwaysChangesCombination() {
        let store = CharacterAssignmentStore(directory: tempDir)
        let identity = AgentIdentity(key: "pane:wA:p1|claude")
        var current = store.assignment(for: identity)
        for _ in 0..<20 {
            let next = store.reroll(for: identity)
            XCTAssertNotEqual(next, current)
            current = next
        }
    }

    func testUnknownSpeciesEntryIsDroppedWithoutLosingOthers() throws {
        // 種の廃止・改名（例: goat→deer）で保存済みJSONに未知種が残っても、
        // 他キャラの割当まで巻き添えで消えないこと
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let json = """
        {"stale": {"species": "dragon", "paletteIndex": 1},
         "kept": {"species": "cow", "paletteIndex": 2}}
        """
        try Data(json.utf8)
            .write(to: tempDir.appendingPathComponent("character-assignments.json"))
        let store = CharacterAssignmentStore(directory: tempDir)
        XCTAssertEqual(store.assignment(for: AgentIdentity(key: "kept")),
                       CharacterAssignment(species: .cow, paletteIndex: 2))
        _ = store.assignment(for: AgentIdentity(key: "stale"))  // 再割当される（クラッシュしない）
    }

    func testCorruptedFileStartsEmpty() throws {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try Data("not json at all".utf8)
            .write(to: tempDir.appendingPathComponent("character-assignments.json"))
        let store = CharacterAssignmentStore(directory: tempDir)
        let identity = AgentIdentity(key: "pane:wA:p1|claude")
        _ = store.assignment(for: identity)  // クラッシュせず空から開始できる
    }
}
