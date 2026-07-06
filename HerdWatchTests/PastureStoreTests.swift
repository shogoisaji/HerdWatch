import XCTest
import HerdWatchShared
@testable import HerdWatch

@MainActor
final class PastureStoreRefreshTests: XCTestCase {
    func testRefreshAppliesSnapshotBeforeReturning() async throws {
        let fake = FakeTransport(panes: [("wA:p1", "idle")])
        var config = HerdrClient.Config()
        config.pollInterval = nil
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("herdwatch-refresh-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let store = PastureStore(client: HerdrClient(transport: fake, config: config),
                                 assignments: CharacterAssignmentStore(directory: tempDir))

        fake.setPanes([("wA:p1", "idle"), ("wA:p2", "working")])
        await store.refresh()

        XCTAssertEqual(store.agentsByID.count, 2,
                       "awaitが返った時点で最新snapshotが反映済みであること（⌘Rの直後にsortedAgentsを読む呼び出し元が古いrosterを掴まないため）")
    }
}
