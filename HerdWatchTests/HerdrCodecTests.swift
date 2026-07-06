import XCTest
import HerdWatchShared
@testable import HerdWatch

/// M0で実herdr(v0.7.0)から採取したワイヤフィクスチャに対するデコード検証。
final class HerdrCodecTests: XCTestCase {
    private func fixture(_ name: String, ext: String = "json") throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: ext),
                                "fixture \(name).\(ext) not bundled")
        return try Data(contentsOf: url)
    }

    func testDecodePaneList() throws {
        let resp = try JSONDecoder().decode(HerdrResponse.self, from: fixture("pane_list"))
        XCTAssertNil(resp.error)
        let result = try XCTUnwrap(resp.result).reencoded(as: PaneListResult.self)
        XCTAssertFalse(result.panes.isEmpty)
        let first = result.panes[0]
        XCTAssertEqual(first.paneID, "w9:p1")
        XCTAssertEqual(first.agent, "claude")
        XCTAssertEqual(first.agentStatus, "idle")
        // hooks未導入環境の採取なので agent_session は無い（あっても壊れない）
        XCTAssertNil(first.agentSession)
    }

    func testDecodeAgentListAsPanes() throws {
        let resp = try JSONDecoder().decode(HerdrResponse.self, from: fixture("agent_list"))
        let obj = try XCTUnwrap(resp.result)
        struct AgentListResult: Decodable { let agents: [PaneInfo] }
        let result = try obj.reencoded(as: AgentListResult.self)
        XCTAssertFalse(result.agents.isEmpty)
        XCTAssertTrue(result.agents.allSatisfy { $0.agent != nil })
    }

    func testDecodeWorkspaceListWithLabels() throws {
        let resp = try JSONDecoder().decode(HerdrResponse.self, from: fixture("workspace_list"))
        let result = try XCTUnwrap(resp.result).reencoded(as: WorkspaceListResult.self)
        XCTAssertFalse(result.workspaces.isEmpty)
        XCTAssertTrue(result.workspaces.contains { $0.label == "skill-store" })
    }

    func testDecodeErrorResponse() throws {
        let resp = try JSONDecoder().decode(HerdrResponse.self, from: fixture("err_agent_focus_0"))
        let err = try XCTUnwrap(resp.error)
        XCTAssertEqual(err.code, "invalid_request")
        XCTAssertTrue(err.message.contains("missing field `target`"))
    }

    func testDecodeEventStreamSample() throws {
        let data = try fixture("events_sample", ext: "ndjson")
        var reader = NDJSONLineReader()
        let lines = reader.append(data)
        XCTAssertFalse(lines.isEmpty)

        var statusChanges: [AgentStatusChangedData] = []
        var sawAck = false
        for line in lines {
            switch HerdrStreamLine.decode(line) {
            case .push(let push) where push.event == "pane.agent_status_changed":
                statusChanges.append(try push.data.reencoded(as: AgentStatusChangedData.self))
            case .response(let resp):
                sawAck = resp.error == nil
            case .push, .undecodable:
                continue
            }
        }
        XCTAssertTrue(sawAck, "subscription ack should decode as response")
        // 採取したdone→閲覧→idleの遷移実例が入っていること
        let statuses = statusChanges.filter { $0.paneID == "w9:p1" }.map(\.agentStatus)
        XCTAssertTrue(statuses.contains("done") && statuses.contains("idle"))
    }

    func testRequestWireFormat() throws {
        let req = HerdrRequest(id: "req_1", method: "agent.focus", params: ["target": "w9:p1"])
        let data = try JSONEncoder().encode(req)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["id"] as? String, "req_1")
        XCTAssertEqual(obj["method"] as? String, "agent.focus")
        XCTAssertEqual((obj["params"] as? [String: Any])?["target"] as? String, "w9:p1")
    }

    func testUnknownEventTypeIsTolerated() {
        let line = Data("{\"data\":{\"mystery\":true},\"event\":\"pane.some_future_event\"}".utf8)
        guard case .push(let push) = HerdrStreamLine.decode(line) else {
            return XCTFail("should decode as push")
        }
        XCTAssertEqual(push.event, "pane.some_future_event")
    }
}
