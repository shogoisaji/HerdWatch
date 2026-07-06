import XCTest
@testable import HerdWatchShared

final class CompanionProtocolTests: XCTestCase {

    // MARK: - メッセージ種別判定

    func test_kind_snapshot() {
        let msg = CompanionMessage(snapshot: CompanionSnapshot(agents: [], connectionState: "live"))
        XCTAssertEqual(msg.kind, .snapshot)
    }

    func test_kind_focus() {
        let msg = CompanionMessage(focus: CompanionFocusCommand(paneID: "host:0:1"))
        XCTAssertEqual(msg.kind, .focus)
    }

    func test_kind_reload() {
        let msg = CompanionMessage(reload: CompanionReloadRequest())
        XCTAssertEqual(msg.kind, .reload)
    }

    func test_kind_unknown_whenBothNil() {
        // Codable経由で両方nilのメッセージが来た場合の安全判定
        let json = "{}".data(using: .utf8)!
        let msg = CompanionCodec.decode(json)
        XCTAssertEqual(msg?.kind, .unknown)
    }

    // MARK: - エンコード/デコード往復

    func test_codec_snapshotRoundTrip() throws {
        let agent = CompanionAgent(identityKey: "session:abc", paneID: "host:0:1",
                                   workspaceID: "ws1", workspaceLabel: "api",
                                   agentLabel: "claude", state: "working",
                                   species: "sheep", paletteIndex: 2, order: 0)
        let snapshot = CompanionSnapshot(agents: [agent], connectionState: "live")
        let msg = CompanionMessage(snapshot: snapshot)

        let data = try CompanionCodec.encode(msg)
        let decoded = CompanionCodec.decode(data)

        XCTAssertEqual(decoded, msg)
        XCTAssertEqual(decoded?.kind, .snapshot)
        XCTAssertEqual(decoded?.snapshot?.agents.first?.species, "sheep")
        XCTAssertEqual(decoded?.snapshot?.agents.first?.state, "working")
        XCTAssertEqual(decoded?.snapshot?.connectionState, "live")
    }

    func test_codec_focusRoundTrip() throws {
        let msg = CompanionMessage(focus: CompanionFocusCommand(paneID: "host:0:3"))
        let data = try CompanionCodec.encode(msg)
        let decoded = CompanionCodec.decode(data)

        XCTAssertEqual(decoded, msg)
        XCTAssertEqual(decoded?.kind, .focus)
        XCTAssertEqual(decoded?.focus?.paneID, "host:0:3")
    }

    func test_codec_reloadRoundTrip() throws {
        let msg = CompanionMessage(reload: CompanionReloadRequest())
        let data = try CompanionCodec.encode(msg)
        let decoded = CompanionCodec.decode(data)

        XCTAssertEqual(decoded, msg)
        XCTAssertEqual(decoded?.kind, .reload)
        XCTAssertNotNil(decoded?.reload)
    }

    // MARK: - 寛容デコード（未知フィールドは無視）

    func test_decode_ignoresUnknownFields() {
        let json = """
        {"focus":{"paneID":"host:0:9"},"extra":"ignored","snapshot":null}
        """.data(using: .utf8)!
        let msg = CompanionCodec.decode(json)
        XCTAssertEqual(msg?.kind, .focus)
        XCTAssertEqual(msg?.focus?.paneID, "host:0:9")
    }

    func test_decode_invalidJSONReturnsNil() {
        XCTAssertNil(CompanionCodec.decode("{not json".data(using: .utf8)!))
        XCTAssertNil(CompanionCodec.decode(Data()))
    }

    // MARK: - 空スナップショット

    func test_codec_emptySnapshotRoundTrip() throws {
        let snapshot = CompanionSnapshot(agents: [], connectionState: "connecting")
        let data = try CompanionCodec.encode(CompanionMessage(snapshot: snapshot))
        let decoded = CompanionCodec.decode(data)
        XCTAssertEqual(decoded?.snapshot?.agents, [])
        XCTAssertEqual(decoded?.snapshot?.connectionState, "connecting")
    }

    // MARK: - working開始時刻の往復・寛容デコード

    func test_codec_workingStartedAtRoundTrip() throws {
        let start = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let agent = CompanionAgent(identityKey: "session:abc", paneID: "host:0:1",
                                   workspaceID: "ws1", workspaceLabel: "api",
                                   agentLabel: "claude", state: "working",
                                   species: "sheep", paletteIndex: 2, order: 0,
                                   workingStartedAt: start)
        let data = try CompanionCodec.encode(CompanionMessage(
            snapshot: CompanionSnapshot(agents: [agent], connectionState: "live")))
        let decoded = CompanionCodec.decode(data)
        XCTAssertEqual(decoded?.snapshot?.agents.first?.workingStartedAt, start)
    }

    func test_decode_missingWorkingStartedAtIsNil() throws {
        // 旧Mac（field未送信）からのスナップショットでも寛容にnilへ
        let json = """
        {"snapshot":{"agents":[{"identityKey":"k","paneID":"p","workspaceID":"w","workspaceLabel":"ws","agentLabel":"a","state":"working","species":"sheep","paletteIndex":0,"order":0}],"connectionState":"live"},"focus":null}
        """.data(using: .utf8)!
        let msg = CompanionCodec.decode(json)
        XCTAssertNil(msg?.snapshot?.agents.first?.workingStartedAt)
    }
}
