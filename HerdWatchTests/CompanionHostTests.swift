import XCTest
import MultipeerConnectivity
import HerdWatchShared
@testable import HerdWatch

final class CompanionHostTests: XCTestCase {

    // MARK: - スナップショット生成（純粋関数）

    private func sampleAgent(order: Int, state: AgentState = .working) -> PastureAgent {
        PastureAgent(
            identity: AgentIdentity(key: "session:\(order)"),
            paneID: "host:0:\(order)",
            workspaceID: "ws\(order % 2)",
            workspaceLabel: "api",
            agentLabel: "claude",
            state: state,
            character: CharacterAssignment(species: .sheep, paletteIndex: order),
            order: order
        )
    }

    func test_buildSnapshot_mapsAgentsAndConnectionState() {
        let agents = [sampleAgent(order: 0), sampleAgent(order: 1, state: .done)]
        let snapshot = CompanionHostSnapshotBuilder.build(agents: agents, connectionState: .live)

        XCTAssertEqual(snapshot.connectionState, "live")
        XCTAssertEqual(snapshot.agents.count, 2)
        XCTAssertEqual(snapshot.agents[0].identityKey, "session:0")
        XCTAssertEqual(snapshot.agents[0].paneID, "host:0:0")
        XCTAssertEqual(snapshot.agents[0].state, "working")
        XCTAssertEqual(snapshot.agents[0].species, "sheep")
        XCTAssertEqual(snapshot.agents[0].paletteIndex, 0)
        XCTAssertEqual(snapshot.agents[0].order, 0)
        XCTAssertEqual(snapshot.agents[1].state, "done")
    }

    func test_buildSnapshot_connectionStateStrings() {
        XCTAssertEqual(
            CompanionHostSnapshotBuilder.build(agents: [], connectionState: .connecting).connectionState,
            "connecting")
        XCTAssertEqual(
            CompanionHostSnapshotBuilder.build(agents: [], connectionState: .live).connectionState,
            "live")
        XCTAssertEqual(
            CompanionHostSnapshotBuilder.build(agents: [], connectionState: .reconnecting(attempt: 3)).connectionState,
            "reconnecting")
    }

    func test_buildSnapshot_emptyAgents() {
        let snapshot = CompanionHostSnapshotBuilder.build(agents: [], connectionState: .live)
        XCTAssertEqual(snapshot.agents, [])
    }

    // MARK: - メッセージルーティング（純粋関数）

    func test_route_focusCommand() {
        let msg = CompanionMessage(focus: CompanionFocusCommand(paneID: "host:0:5"))
        XCTAssertEqual(CompanionHostRouter.route(msg), .focus(paneID: "host:0:5"))
    }

    func test_route_reloadCommand() {
        let msg = CompanionMessage(reload: CompanionReloadRequest())
        XCTAssertEqual(CompanionHostRouter.route(msg), .reload)
    }

    func test_route_snapshotMessage_isIgnored() {
        // iOS→Mac方向にsnapshotは来ないはずだが、来ても無視（堅牢性）
        let msg = CompanionMessage(snapshot: CompanionSnapshot(agents: [], connectionState: "live"))
        XCTAssertEqual(CompanionHostRouter.route(msg), .ignore)
    }

    func test_route_unknownMessageIsIgnored() {
        let json = "{}".data(using: .utf8)!
        let msg = CompanionCodec.decode(json)!
        XCTAssertEqual(CompanionHostRouter.route(msg), .ignore)
    }

    func test_linkCallsPeerConnectedOnConnectedState() {
        let link = CompanionLink(displayName: "test-host")
        let peer = MCPeerID(displayName: "test-peer")
        let session = MCSession(peer: peer)
        let expectation = expectation(description: "onPeerConnected")
        link.onPeerConnected = { expectation.fulfill() }

        link.session(session, peer: peer, didChange: .connected)

        wait(for: [expectation], timeout: 1)
    }
}
