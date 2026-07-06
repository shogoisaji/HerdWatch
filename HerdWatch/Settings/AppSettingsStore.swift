import Foundation
import Observation

/// herdrが動きうる既知のターミナルアプリ。
struct TerminalApp: Identifiable, Hashable {
    let name: String
    let bundleID: String
    var id: String { bundleID }

    static let known: [TerminalApp] = [
        TerminalApp(name: "iTerm2", bundleID: "com.googlecode.iterm2"),
        TerminalApp(name: "Ghostty", bundleID: "com.mitchellh.ghostty"),
        TerminalApp(name: "WezTerm", bundleID: "com.github.wez.wezterm"),
        TerminalApp(name: "kitty", bundleID: "net.kovidgoyal.kitty"),
        TerminalApp(name: "Alacritty", bundleID: "org.alacritty"),
        TerminalApp(name: "Warp", bundleID: "dev.warp.Warp-Stable"),
        TerminalApp(name: "ターミナル", bundleID: "com.apple.Terminal"),
    ]
}

enum CharacterSize: String, CaseIterable {
    case tiny, small, medium, large

    var pixelSize: CGFloat {
        switch self {
        case .tiny: 1.5
        case .small: 2
        case .medium: 3
        case .large: 4
        }
    }

    func label(for language: AppLanguage) -> String {
        switch self {
        case .tiny: language == .japanese ? "極小" : "XS"
        case .small: language == .japanese ? "小" : "S"
        case .medium: language == .japanese ? "中" : "M"
        case .large: language == .japanese ? "大" : "L"
        }
    }
}

enum PastureBackground: String, CaseIterable {
    case grassland, wasteland, brick

    func label(for language: AppLanguage) -> String {
        switch self {
        case .grassland: language == .japanese ? "草原" : "Grassland"
        case .wasteland: language == .japanese ? "荒野" : "Wasteland"
        case .brick: language == .japanese ? "レンガ" : "Brick"
        }
    }
}

/// 設定画面の表示言語。macOSのシステム言語とは独立に、アプリ内トグルで即時切替する。
enum AppLanguage: String, CaseIterable {
    case english, japanese

    /// ピッカー上の表記は選択中言語に関わらず、その言語自身の呼称で出す（言語切替UIの定石）
    var nativeName: String {
        switch self {
        case .english: "English"
        case .japanese: "日本語"
        }
    }
}

@Observable @MainActor
final class AppSettingsStore {
    /// 空文字 = 自動（起動中の既知ターミナルを優先順で使う）
    var terminalBundleID: String {
        didSet { UserDefaults.standard.set(terminalBundleID, forKey: Keys.terminal) }
    }

    var alwaysOnTop: Bool {
        didSet { UserDefaults.standard.set(alwaysOnTop, forKey: Keys.alwaysOnTop) }
    }

    /// 空文字 = 既定（~/.config/herdr/herdr.sock）
    var socketPathOverride: String {
        didSet { UserDefaults.standard.set(socketPathOverride, forKey: Keys.socketPath) }
    }

    var characterSize: CharacterSize {
        didSet { UserDefaults.standard.set(characterSize.rawValue, forKey: Keys.characterSize) }
    }

    var background: PastureBackground {
        didSet { UserDefaults.standard.set(background.rawValue, forKey: Keys.background) }
    }

    var autoRearrangeOnResize: Bool {
        didSet { UserDefaults.standard.set(autoRearrangeOnResize, forKey: Keys.autoRearrangeOnResize) }
    }

    /// working中の経過時間を炎の横に表示するか。
    var showWorkingElapsed: Bool {
        didSet { UserDefaults.standard.set(showWorkingElapsed, forKey: Keys.showWorkingElapsed) }
    }

    /// 設定画面の表示言語（既定=英語）。macOSのシステム言語設定とは独立。
    var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Keys.language) }
    }

    private enum Keys {
        static let terminal = "terminalBundleID"
        static let alwaysOnTop = "alwaysOnTop"
        static let socketPath = "socketPathOverride"
        static let characterSize = "characterSize"
        static let background = "pastureBackground"
        static let autoRearrangeOnResize = "autoRearrangeOnResize"
        static let showWorkingElapsed = "showWorkingElapsed"
        static let language = "appLanguage"
    }

    init() {
        let defaults = UserDefaults.standard
        self.terminalBundleID = defaults.string(forKey: Keys.terminal) ?? ""
        self.alwaysOnTop = defaults.object(forKey: Keys.alwaysOnTop) as? Bool ?? true
        self.socketPathOverride = defaults.string(forKey: Keys.socketPath) ?? ""
        self.characterSize = defaults.string(forKey: Keys.characterSize)
            .flatMap(CharacterSize.init(rawValue:)) ?? .medium
        self.background = defaults.string(forKey: Keys.background)
            .flatMap(PastureBackground.init(rawValue:)) ?? .grassland
        self.autoRearrangeOnResize = defaults.object(forKey: Keys.autoRearrangeOnResize) as? Bool ?? true
        self.showWorkingElapsed = defaults.object(forKey: Keys.showWorkingElapsed) as? Bool ?? true
        self.language = defaults.string(forKey: Keys.language)
            .flatMap(AppLanguage.init(rawValue:)) ?? .english
    }

    var effectiveSocketPath: String {
        socketPathOverride.isEmpty
            ? HerdrSocketTransport.defaultSocketPath
            : NSString(string: socketPathOverride).expandingTildeInPath
    }
}
