import Darwin
import Foundation
import os
import HerdWatchShared

/// POSIX unixドメインソケット実装。
/// herdrは単発RPCのレスポンス直後に接続を閉じるため（実測）、1コール=1接続で扱う。
final class HerdrSocketTransport: HerdrTransport, @unchecked Sendable {
    static let defaultSocketPath = NSString(string: "~/.config/herdr/herdr.sock").expandingTildeInPath

    private let socketPath: String
    private let logger = Logger(subsystem: "com.isaji134.HerdWatch", category: "transport")

    init(socketPath: String = HerdrSocketTransport.defaultSocketPath) {
        self.socketPath = socketPath
    }

    // MARK: - 単発RPC

    func request(_ method: String, params: [String: JSONValue]) async throws -> HerdrResponse {
        let path = socketPath
        return try await Task.detached(priority: .userInitiated) {
            let fd = try Self.connectSocket(path: path, receiveTimeout: 5)
            defer { Darwin.close(fd) }

            let req = HerdrRequest(id: "req_\(UUID().uuidString.prefix(8))", method: method, params: params)
            var payload = try JSONEncoder().encode(req)
            payload.append(UInt8(ascii: "\n"))
            try Self.writeAll(fd: fd, data: payload)

            // 改行かEOFまで読む（サーバは応答直後に閉じるためEOFも正常系）
            var reader = NDJSONLineReader()
            var buf = [UInt8](repeating: 0, count: 65536)
            while true {
                let n = Darwin.read(fd, &buf, buf.count)
                if n < 0 { throw HerdrTransportError.connectionFailed(errno) }
                if n == 0 {
                    if let rest = reader.flush(), let resp = try? JSONDecoder().decode(HerdrResponse.self, from: rest) {
                        return try Self.unwrap(resp)
                    }
                    throw HerdrTransportError.emptyResponse
                }
                if let line = reader.append(Data(buf[0..<n])).first {
                    return try Self.unwrap(try JSONDecoder().decode(HerdrResponse.self, from: line))
                }
            }
        }.value
    }

    private static func unwrap(_ resp: HerdrResponse) throws -> HerdrResponse {
        if let err = resp.error {
            throw HerdrTransportError.rpcError(code: err.code, message: err.message)
        }
        return resp
    }

    // MARK: - 購読ストリーム

    func openEventStream(subscriptions: [JSONValue]) -> AsyncThrowingStream<HerdrStreamLine, Error> {
        let path = socketPath
        let logger = self.logger
        return AsyncThrowingStream { continuation in
            let fdBox = OSAllocatedUnfairLock<Int32>(initialState: -1)
            let task = Task.detached(priority: .utility) {
                do {
                    let fd = try Self.connectSocket(path: path, receiveTimeout: 0)
                    fdBox.withLock { $0 = fd }

                    let req = HerdrRequest(id: "sub", method: "events.subscribe",
                                           params: ["subscriptions": .array(subscriptions)])
                    var payload = try JSONEncoder().encode(req)
                    payload.append(UInt8(ascii: "\n"))
                    try Self.writeAll(fd: fd, data: payload)

                    var reader = NDJSONLineReader()
                    var buf = [UInt8](repeating: 0, count: 65536)
                    while !Task.isCancelled {
                        let n = Darwin.read(fd, &buf, buf.count)
                        if n <= 0 { break }
                        for line in reader.append(Data(buf[0..<n])) {
                            continuation.yield(HerdrStreamLine.decode(line))
                        }
                    }
                    continuation.finish()
                } catch {
                    logger.error("event stream failed: \(String(describing: error))")
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                // ブロック中のread()を解除するため別スレッドからclose
                let fd = fdBox.withLock { fd in
                    defer { fd = -1 }
                    return fd
                }
                if fd >= 0 { Darwin.close(fd) }
            }
        }
    }

    // MARK: - POSIXヘルパ

    private static func connectSocket(path: String, receiveTimeout seconds: Int) throws -> Int32 {
        guard FileManager.default.fileExists(atPath: path) else {
            throw HerdrTransportError.socketUnavailable(path)
        }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw HerdrTransportError.connectionFailed(errno) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path) - 1
        let bytes = Array(path.utf8)
        guard bytes.count <= maxLen else {
            Darwin.close(fd)
            throw HerdrTransportError.socketUnavailable(path)
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
        }

        if seconds > 0 {
            var tv = timeval(tv_sec: seconds, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        }

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let err = errno
            Darwin.close(fd)
            throw HerdrTransportError.connectionFailed(err)
        }
        return fd
    }

    private static func writeAll(fd: Int32, data: Data) throws {
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var offset = 0
            while offset < raw.count {
                let n = Darwin.write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if n <= 0 { throw HerdrTransportError.connectionFailed(errno) }
                offset += n
            }
        }
    }
}
