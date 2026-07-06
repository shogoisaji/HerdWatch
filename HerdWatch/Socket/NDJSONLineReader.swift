import Foundation

/// 任意のバイトチャンクを受け取り、完成した行（\n区切り）だけを順に返すバッファ。
/// 行がチャンク境界やUTF-8境界で分断されても正しく復元する。
struct NDJSONLineReader {
    private var buffer = Data()

    mutating func append(_ chunk: Data) -> [Data] {
        buffer.append(chunk)
        var lines: [Data] = []
        while let nl = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            if !line.isEmpty {
                lines.append(line)
            }
        }
        return lines
    }

    /// EOF時に未完の行が残っていれば返す（サーバは改行を送ってから閉じるのが通常だが保険）。
    mutating func flush() -> Data? {
        guard !buffer.isEmpty else { return nil }
        defer { buffer.removeAll() }
        return buffer
    }
}
