import XCTest
import HerdWatchShared
@testable import HerdWatch

/// 台本制御できる偽トランスポート。
/// 「1接続に対しsubscribeは1回だけ（=購読変更は必ず新規接続）」の不変条件を
/// openEventStream呼び出し回数と購読リストで検証する。
final class FakeTransport: HerdrTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _openCalls: [[JSONValue]] = []
    private var _continuations: [AsyncThrowingStream<HerdrStreamLine, Error>.Continuation] = []
    private var _panes: [(id: String, status: String)]

    init(panes: [(id: String, status: String)]) {
        self._panes = panes
    }

    var openCalls: [[JSONValue]] {
        lock.lock(); defer { lock.unlock() }
        return _openCalls
    }

    func setPanes(_ panes: [(id: String, status: String)]) {
        lock.lock(); defer { lock.unlock() }
        _panes = panes
    }

    func emit(_ line: HerdrStreamLine, connection: Int) {
        lock.lock()
        let c = _continuations[connection]
        lock.unlock()
        c.yield(line)
    }

    func closeConnection(_ index: Int) {
        lock.lock()
        let c = _continuations[index]
        lock.unlock()
        c.finish()
    }

    func request(_ method: String, params: [String: JSONValue]) async throws -> HerdrResponse {
        respond(to: method)
    }

    // NSLockのlock/unlockはasync文脈で使えない（Swift 6でエラー）ため同期関数に切り出す
    private func respond(to method: String) -> HerdrResponse {
        lock.lock(); defer { lock.unlock() }
        switch method {
        case "pane.list":
            let panes = _panes.map { pane -> JSONValue in
                .object(["pane_id": .string(pane.id),
                         "workspace_id": .string(String(pane.id.prefix(2))),
                         "agent": "claude",
                         "agent_status": .string(pane.status)])
            }
            return HerdrResponse(id: "t", result: .object(["panes": .array(panes)]), error: nil)
        case "workspace.list":
            return HerdrResponse(id: "t", result: .object(["workspaces": .array([
                .object(["workspace_id": "wA", "label": "alpha"]),
            ])]), error: nil)
        default:
            return HerdrResponse(id: "t", result: .object([:]), error: nil)
        }
    }

    func openEventStream(subscriptions: [JSONValue]) -> AsyncThrowingStream<HerdrStreamLine, Error> {
        AsyncThrowingStream { continuation in
            lock.lock()
            _openCalls.append(subscriptions)
            _continuations.append(continuation)
            lock.unlock()
            continuation.yield(.response(HerdrResponse(id: "sub", result: .object(["type": "subscription_started"]), error: nil)))
        }
    }
}

final class HerdrClientReconnectTests: XCTestCase {
    private final class SleepRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _delays: [Duration] = []
        var delays: [Duration] { lock.lock(); defer { lock.unlock() }; return _delays }
        func record(_ d: Duration) { lock.lock(); _delays.append(d); lock.unlock() }
    }

    private func makeClient(_ fake: FakeTransport, recorder: SleepRecorder? = nil) -> HerdrClient {
        var config = HerdrClient.Config()
        config.pollInterval = nil
        config.resubscribeDebounce = .milliseconds(0)
        return HerdrClient(transport: fake, config: config, sleeper: { d in
            recorder?.record(d)
            try await Task.sleep(for: .milliseconds(1))
        })
    }

    private func paneSubIDs(_ subs: [JSONValue]) -> Set<String> {
        Set(subs.compactMap { sub -> String? in
            guard case .object(let o) = sub,
                  case .string("pane.agent_status_changed") = o["type"] ?? .null,
                  case .string(let id) = o["pane_id"] ?? .null else { return nil }
            return id
        })
    }

    /// 起動フロー: グローバル購読のみ→snapshotでroster確定→pane別購読で張り替え。
    func testStartupResubscribesWithPaneSubscriptions() async throws {
        let fake = FakeTransport(panes: [("wA:p1", "idle"), ("wB:p1", "working")])
        let client = makeClient(fake)

        var snapshots = 0
        for await update in client.updates() {
            if case .snapshot(let panes, let workspaces) = update {
                snapshots += 1
                XCTAssertEqual(panes.count, 2)
                XCTAssertEqual(workspaces.first?.label, "alpha")
                if snapshots == 2 { break }
            }
        }
        let calls = fake.openCalls
        XCTAssertEqual(calls.count, 2, "起動時は グローバルのみ→pane別込み の2接続")
        XCTAssertTrue(paneSubIDs(calls[0]).isEmpty)
        XCTAssertEqual(paneSubIDs(calls[1]), ["wA:p1", "wB:p1"])
    }

    /// 状態変化イベントがPastureUpdateとして流れる。
    func testStatusChangeEventFlowsThrough() async throws {
        let fake = FakeTransport(panes: [("wA:p1", "working")])
        let client = makeClient(fake)

        var snapshots = 0
        for await update in client.updates() {
            switch update {
            case .snapshot:
                snapshots += 1
                if snapshots == 2 {
                    fake.emit(.push(HerdrPushEvent(event: "pane.agent_status_changed",
                                                   data: .object(["pane_id": "wA:p1",
                                                                  "agent_status": "done",
                                                                  "agent": "claude",
                                                                  "workspace_id": "wA"]))),
                              connection: 1)
                }
            case .statusChanged(let data):
                XCTAssertEqual(data.paneID, "wA:p1")
                XCTAssertEqual(data.agentStatus, "done")
                return
            default:
                continue
            }
        }
        XCTFail("statusChanged update not received")
    }

    /// 未知paneの出現→接続を張り替えて新paneの購読を含める（同一接続への再subscribeはしない）。
    func testNewPaneTriggersResubscribeOnFreshConnection() async throws {
        let fake = FakeTransport(panes: [("wA:p1", "idle")])
        let client = makeClient(fake)

        var snapshots = 0
        for await update in client.updates() {
            guard case .snapshot = update else { continue }
            snapshots += 1
            if snapshots == 2 {
                fake.setPanes([("wA:p1", "idle"), ("wC:p9", "working")])
                fake.emit(.push(HerdrPushEvent(event: "pane_agent_detected",
                                               data: .object(["pane_id": "wC:p9", "workspace_id": "wC",
                                                              "agent": "claude"]))),
                          connection: 1)
            }
            // 新paneの購読を含む接続が張られるまで待つ（裏取りsnapshot分を含むため回数固定にしない）
            if let last = fake.openCalls.last, paneSubIDs(last).contains("wC:p9") { break }
            if snapshots >= 8 { break }
        }
        let calls = fake.openCalls
        XCTAssertGreaterThanOrEqual(calls.count, 3)
        XCTAssertTrue(paneSubIDs(calls.last!).contains("wC:p9"),
                      "最終接続の購読に新paneが含まれること")
    }

    /// サーバ切断（EOF）→バックオフして再接続。
    func testServerCloseTriggersBackoffReconnect() async throws {
        let fake = FakeTransport(panes: [("wA:p1", "idle")])
        let recorder = SleepRecorder()
        let client = makeClient(fake, recorder: recorder)

        var snapshots = 0
        var reconnecting = false
        for await update in client.updates() {
            switch update {
            case .snapshot:
                snapshots += 1
                if snapshots == 2 { fake.closeConnection(1) }
            case .connection(.reconnecting):
                reconnecting = true
            case .connection(.live) where reconnecting:
                XCTAssertGreaterThanOrEqual(fake.openCalls.count, 3)
                XCTAssertFalse(recorder.delays.isEmpty, "バックオフのsleepが記録されること")
                return
            default:
                continue
            }
        }
        XCTFail("did not reconnect after server close")
    }
}
