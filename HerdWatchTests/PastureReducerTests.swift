import XCTest
import HerdWatchShared
@testable import HerdWatch

final class PastureReducerTests: XCTestCase {
    private var assignments: CharacterAssignmentStore!
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("herdwatch-tests-\(UUID().uuidString)")
        assignments = CharacterAssignmentStore(directory: tempDir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func pane(_ id: String, agent: String? = "claude", status: String = "idle",
                      session: String? = nil) -> PaneInfo {
        PaneInfo(paneID: id,
                 terminalID: "term_\(id)",
                 workspaceID: String(id.prefix(2)),
                 tabID: nil, focused: false, cwd: nil,
                 agent: agent, agentStatus: status, revision: 0,
                 agentSession: session.map { AgentSessionRef(source: "hook", agent: agent, kind: "session_id", value: $0) })
    }

    private let workspaces = [
        WorkspaceInfo(workspaceID: "wA", number: 1, label: "alpha", focused: false, agentStatus: nil),
        WorkspaceInfo(workspaceID: "wB", number: 2, label: "beta", focused: false, agentStatus: nil),
    ]

    func testSnapshotOnlyAgentPanesBecomeCharacters() {
        var order = 0
        let result = PastureReducer.mergeSnapshot(
            panes: [pane("wA:p1"), pane("wA:p2", agent: nil), pane("wB:p1", status: "working")],
            workspaces: workspaces, into: [:], assignments: assignments, nextOrder: &order, now: Date())
        XCTAssertEqual(result.count, 2, "agent未検出のpaneはキャラにならない")
        XCTAssertEqual(order, 2)
    }

    func testSnapshotPreservesIdentityCharacterAndOrder() {
        var order = 0
        let first = PastureReducer.mergeSnapshot(
            panes: [pane("wA:p1"), pane("wB:p1")],
            workspaces: workspaces, into: [:], assignments: assignments, nextOrder: &order, now: Date())
        let identity = AgentIdentity(pane: pane("wA:p1"))
        let originalCharacter = first[identity]!.character
        let originalOrder = first[identity]!.order

        let second = PastureReducer.mergeSnapshot(
            panes: [pane("wA:p1", status: "blocked")],
            workspaces: workspaces, into: first, assignments: assignments, nextOrder: &order, now: Date())
        XCTAssertEqual(second.count, 1, "snapshotに居ないpaneのエージェントは退場")
        XCTAssertEqual(second[identity]?.character, originalCharacter, "キャラは維持")
        XCTAssertEqual(second[identity]?.order, originalOrder)
        XCTAssertEqual(second[identity]?.state, .blocked)
    }

    func testWorkspaceLabelResolution() {
        var order = 0
        let result = PastureReducer.mergeSnapshot(
            panes: [pane("wA:p1"), pane("wZ:p1")],
            workspaces: workspaces, into: [:], assignments: assignments, nextOrder: &order, now: Date())
        let alpha = result[AgentIdentity(pane: pane("wA:p1"))]!
        XCTAssertEqual(alpha.workspaceLabel, "alpha")
        XCTAssertEqual(alpha.displayLabel, "alpha:claude p1")
        let unknownWS = result[AgentIdentity(pane: pane("wZ:p1"))]!
        XCTAssertEqual(unknownWS.workspaceLabel, "wZ", "label未取得はworkspace_idへフォールバック")
    }

    func testDuplicateWorkspaceIDsAreToleratedNotCrash() {
        var order = 0
        let duplicated = [
            WorkspaceInfo(workspaceID: "wA", number: 1, label: "alpha", focused: false, agentStatus: nil),
            WorkspaceInfo(workspaceID: "wA", number: 1, label: "alpha-dup", focused: false, agentStatus: nil),
        ]
        let result = PastureReducer.mergeSnapshot(
            panes: [pane("wA:p1")],
            workspaces: duplicated, into: [:], assignments: assignments, nextOrder: &order, now: Date())
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[AgentIdentity(pane: pane("wA:p1"))]?.workspaceLabel, "alpha")
    }

    func testStatusChangeFullTransitionMapping() {
        var order = 0
        var state = PastureReducer.mergeSnapshot(
            panes: [pane("wA:p1", status: "idle")],
            workspaces: workspaces, into: [:], assignments: assignments, nextOrder: &order, now: Date())
        let identity = AgentIdentity(pane: pane("wA:p1"))

        // 採取した実遷移: working → done →（閲覧）→ idle
        for expected in [AgentState.working, .done, .idle, .blocked, .unknown] {
            state = PastureReducer.applyStatusChange(
                AgentStatusChangedData(paneID: "wA:p1", workspaceID: "wA",
                                       agent: "claude", agentStatus: expected.rawValue),
                to: state, now: Date())
            XCTAssertEqual(state[identity]?.state, expected)
        }
    }

    func testStatusChangeForUnknownPaneIsNoop() {
        var order = 0
        let state = PastureReducer.mergeSnapshot(
            panes: [pane("wA:p1")],
            workspaces: workspaces, into: [:], assignments: assignments, nextOrder: &order, now: Date())
        let after = PastureReducer.applyStatusChange(
            AgentStatusChangedData(paneID: "wX:p9", workspaceID: nil, agent: nil, agentStatus: "done"),
            to: state, now: Date())
        XCTAssertEqual(after, state)
    }

    func testRemovePane() {
        var order = 0
        let state = PastureReducer.mergeSnapshot(
            panes: [pane("wA:p1"), pane("wB:p1")],
            workspaces: workspaces, into: [:], assignments: assignments, nextOrder: &order, now: Date())
        let after = PastureReducer.removePane("wA:p1", from: state)
        XCTAssertEqual(after.count, 1)
        XCTAssertNil(after[AgentIdentity(pane: pane("wA:p1"))])
    }

    func testSessionIdentitySurvivesPaneMove() {
        var order = 0
        let before = PastureReducer.mergeSnapshot(
            panes: [pane("wA:p1", session: "sess-123")],
            workspaces: workspaces, into: [:], assignments: assignments, nextOrder: &order, now: Date())
        // 同じsessionが別paneに現れても同一キャラ
        let after = PastureReducer.mergeSnapshot(
            panes: [pane("wB:p7", session: "sess-123")],
            workspaces: workspaces, into: before, assignments: assignments, nextOrder: &order, now: Date())
        let identity = AgentIdentity(pane: pane("wB:p7", session: "sess-123"))
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after[identity]?.character, before[identity]?.character)
        XCTAssertEqual(after[identity]?.paneID, "wB:p7")
    }

    // MARK: - working開始時刻の追跡

    func testNewWorkingAgentRecordsStartNow() {
        var order = 0
        let now = Date()
        let result = PastureReducer.mergeSnapshot(
            panes: [pane("wA:p1", status: "working")],
            workspaces: workspaces, into: [:], assignments: assignments, nextOrder: &order, now: now)
        XCTAssertEqual(result[AgentIdentity(pane: pane("wA:p1"))]?.workingStartedAt, now)
    }

    func testNewNonWorkingAgentHasNilStart() {
        var order = 0
        let result = PastureReducer.mergeSnapshot(
            panes: [pane("wA:p1", status: "idle")],
            workspaces: workspaces, into: [:], assignments: assignments, nextOrder: &order, now: Date())
        XCTAssertNil(result[AgentIdentity(pane: pane("wA:p1"))]?.workingStartedAt)
    }

    func testContinuedWorkingPreservesStart() {
        var order = 0
        let start = Date()
        var state = PastureReducer.mergeSnapshot(
            panes: [pane("wA:p1", status: "working")],
            workspaces: workspaces, into: [:], assignments: assignments, nextOrder: &order, now: start)
        // 同じworkingのまま再snapshot: 開始時刻は保存される（リセットしない）
        state = PastureReducer.mergeSnapshot(
            panes: [pane("wA:p1", status: "working")],
            workspaces: workspaces, into: state, assignments: assignments, nextOrder: &order, now: start.addingTimeInterval(60))
        XCTAssertEqual(state[AgentIdentity(pane: pane("wA:p1"))]?.workingStartedAt, start)
    }

    func testWorkingToDoneClearsStart() {
        var order = 0
        let start = Date()
        var state = PastureReducer.mergeSnapshot(
            panes: [pane("wA:p1", status: "working")],
            workspaces: workspaces, into: [:], assignments: assignments, nextOrder: &order, now: start)
        state = PastureReducer.mergeSnapshot(
            panes: [pane("wA:p1", status: "done")],
            workspaces: workspaces, into: state, assignments: assignments, nextOrder: &order, now: start.addingTimeInterval(30))
        XCTAssertNil(state[AgentIdentity(pane: pane("wA:p1"))]?.workingStartedAt)
    }

    func testIdleToWorkingSetsStart() {
        var order = 0
        let start = Date()
        var state = PastureReducer.mergeSnapshot(
            panes: [pane("wA:p1", status: "idle")],
            workspaces: workspaces, into: [:], assignments: assignments, nextOrder: &order, now: start)
        let later = start.addingTimeInterval(120)
        state = PastureReducer.mergeSnapshot(
            panes: [pane("wA:p1", status: "working")],
            workspaces: workspaces, into: state, assignments: assignments, nextOrder: &order, now: later)
        XCTAssertEqual(state[AgentIdentity(pane: pane("wA:p1"))]?.workingStartedAt, later)
    }

    func testStatusChangeWorkingToDoneClearsStart() {
        var order = 0
        let start = Date()
        var state = PastureReducer.mergeSnapshot(
            panes: [pane("wA:p1", status: "working")],
            workspaces: workspaces, into: [:], assignments: assignments, nextOrder: &order, now: start)
        state = PastureReducer.applyStatusChange(
            AgentStatusChangedData(paneID: "wA:p1", workspaceID: "wA",
                                   agent: "claude", agentStatus: "done"),
            to: state, now: start.addingTimeInterval(10))
        XCTAssertNil(state[AgentIdentity(pane: pane("wA:p1"))]?.workingStartedAt)
    }

    func testStatusChangeIdleToWorkingSetsStart() {
        var order = 0
        let start = Date()
        var state = PastureReducer.mergeSnapshot(
            panes: [pane("wA:p1", status: "idle")],
            workspaces: workspaces, into: [:], assignments: assignments, nextOrder: &order, now: start)
        let later = start.addingTimeInterval(5)
        state = PastureReducer.applyStatusChange(
            AgentStatusChangedData(paneID: "wA:p1", workspaceID: "wA",
                                   agent: "claude", agentStatus: "working"),
            to: state, now: later)
        XCTAssertEqual(state[AgentIdentity(pane: pane("wA:p1"))]?.workingStartedAt, later)
    }

    func testStatusChangeWorkingToWorkingPreservesStart() {
        var order = 0
        let start = Date()
        var state = PastureReducer.mergeSnapshot(
            panes: [pane("wA:p1", status: "working")],
            workspaces: workspaces, into: [:], assignments: assignments, nextOrder: &order, now: start)
        state = PastureReducer.applyStatusChange(
            AgentStatusChangedData(paneID: "wA:p1", workspaceID: "wA",
                                   agent: "claude", agentStatus: "working"),
            to: state, now: start.addingTimeInterval(99))
        XCTAssertEqual(state[AgentIdentity(pane: pane("wA:p1"))]?.workingStartedAt, start)
    }
}
