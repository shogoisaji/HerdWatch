import XCTest
import HerdWatchShared
@testable import HerdWatch

/// 実herdrソケットに対するsmoke。ソケットが無い環境では自動skip。
final class IntegrationSmokeTests: XCTestCase {
    private var transport: HerdrSocketTransport!

    override func setUpWithError() throws {
        let path = HerdrSocketTransport.defaultSocketPath
        try XCTSkipUnless(FileManager.default.fileExists(atPath: path), "no live herdr socket")
        transport = HerdrSocketTransport(socketPath: path)
    }

    func testLivePaneListRoundTrip() async throws {
        let resp = try await transport.request("pane.list", params: [:])
        let result = try XCTUnwrap(resp.result).reencoded(as: PaneListResult.self)
        XCTAssertFalse(result.panes.isEmpty)
    }

    func testLiveWorkspaceListRoundTrip() async throws {
        let resp = try await transport.request("workspace.list", params: [:])
        let result = try XCTUnwrap(resp.result).reencoded(as: WorkspaceListResult.self)
        XCTAssertFalse(result.workspaces.isEmpty)
    }

    func testLiveSubscribeGetsAck() async throws {
        let resp = try await transport.request("pane.list", params: [:])
        let panes = try XCTUnwrap(resp.result).reencoded(as: PaneListResult.self).panes
        let subs: [JSONValue] = [.object(["type": "pane.created"])]
            + panes.prefix(3).map { .object(["type": "pane.agent_status_changed", "pane_id": .string($0.paneID)]) }

        let stream = transport.openEventStream(subscriptions: subs)
        for try await line in stream {
            if case .response(let ack) = line {
                XCTAssertNil(ack.error)
                return  // ackが来たら成功。ストリームはonTerminationでclose
            }
            return XCTFail("first line should be the subscription ack")
        }
        XCTFail("stream ended before ack")
    }

    func testLiveRpcErrorSurfaced() async throws {
        do {
            _ = try await transport.request("agent.focus", params: [:])
            XCTFail("should throw rpcError")
        } catch let HerdrTransportError.rpcError(code, message) {
            XCTAssertEqual(code, "invalid_request")
            XCTAssertTrue(message.contains("target"))
        }
    }
}
