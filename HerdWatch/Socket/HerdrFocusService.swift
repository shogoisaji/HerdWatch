import AppKit
import Foundation
import os

/// キャラタップ時のフォーカス動作:
/// 1. ターミナルアプリを前面化（設定 or 起動中の既知ターミナルを自動選択）
/// 2. herdrへ agent.focus（socket→失敗時CLIフォールバック）
final class HerdrFocusService: @unchecked Sendable {
    private let transport: HerdrTransport
    private let logger = Logger(subsystem: "com.isaji134.HerdWatch", category: "focus")

    init(transport: HerdrTransport) {
        self.transport = transport
    }

    func focus(paneID: String, terminalBundleID: String) async {
        await activateTerminal(preferredBundleID: terminalBundleID)
        do {
            _ = try await transport.request("agent.focus", params: ["target": .string(paneID)])
        } catch {
            logger.warning("agent.focus failed (\(String(describing: error))) — CLIへフォールバック")
            runHerdrCLI(["agent", "focus", paneID])
        }
    }

    // MARK: - ターミナル前面化

    @MainActor
    private func activateTerminal(preferredBundleID: String) {
        let candidates = preferredBundleID.isEmpty
            ? TerminalApp.known.map(\.bundleID)
            : [preferredBundleID]
        for bundleID in candidates {
            if let app = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID).first {
                app.activate()
                return
            }
        }
        logger.notice("実行中のターミナルアプリが見つからず前面化をスキップ")
    }

    // MARK: - CLIフォールバック

    private static let cliCandidates = [
        NSString(string: "~/homebrew/bin/herdr").expandingTildeInPath,
        "/opt/homebrew/bin/herdr",
        "/usr/local/bin/herdr",
    ]

    private func runHerdrCLI(_ arguments: [String]) {
        guard let path = Self.cliCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            logger.error("herdr CLIが見つからない")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            logger.error("herdr CLI起動失敗: \(String(describing: error))")
        }
    }
}
