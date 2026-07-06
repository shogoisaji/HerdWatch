import Foundation
import HerdWatchShared

protocol HerdrTransport: Sendable {
    /// 単発RPC。毎回新規接続で1リクエスト送り、1行のレスポンス（またはEOF）で完結する。
    func request(_ method: String, params: [String: JSONValue]) async throws -> HerdrResponse

    /// 購読ストリーム。1接続に対し events.subscribe をちょうど1回だけ送り、
    /// ack行とその後のpush行を順に流す。接続が切れたらストリームは終了する。
    func openEventStream(subscriptions: [JSONValue]) -> AsyncThrowingStream<HerdrStreamLine, Error>
}

enum HerdrTransportError: Error, Equatable {
    case socketUnavailable(String)
    case connectionFailed(Int32)
    case emptyResponse
    case rpcError(code: String, message: String)
}
