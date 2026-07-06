import Foundation

/// SettingsViewの表示文字列。macOSのシステムローカライズには頼らず、
/// アプリ内の言語ピッカー（AppLanguage）で即時切替できるようにする。
struct SettingsStrings {
    let language: AppLanguage

    private func pick(_ en: String, _ ja: String) -> String {
        language == .japanese ? ja : en
    }

    var windowSection: String { pick("Window", "ウィンドウ") }
    var alwaysOnTop: String { pick("Always on top", "常に最前面に表示") }
    var autoRearrangeOnResize: String {
        pick("Auto-rearrange characters after resize", "リサイズ後にキャラクターを自動で再配置")
    }
    var showWorkingElapsed: String {
        pick("Show working elapsed time", "作業中の経過時間を表示")
    }

    var terminalSection: String { pick("Terminal to focus", "フォーカスするターミナルアプリ") }
    var terminalAuto: String {
        pick("Automatic (known running terminal)", "自動（起動中の既知ターミナル）")
    }
    var focusHint: String {
        pick("Double-click a character to bring this app forward and jump to its pane.",
             "キャラクターをダブルクリックすると、このアプリを前面化して該当paneへジャンプします。")
    }

    var characterSection: String { pick("Character", "キャラクター") }
    var sizeLabel: String { pick("Size", "サイズ") }
    var rerollAllButton: String { pick("Reroll all characters", "全キャラクターを振り直す") }
    var rerollHint: String {
        pick("⌥ (Option) + click a character to reroll it individually.",
             "個別に振り直すには、キャラクターを ⌥（Option）+クリック。")
    }

    var backgroundSection: String { pick("Background", "背景") }

    var connectionSection: String { pick("Connection", "接続") }
    var socketPathPrompt: String { pick("Socket path (empty = default)", "ソケットパス（空=既定）") }
    var socketPathHint: String {
        pick("Changes take effect after restarting the app.", "変更はアプリ再起動後に反映されます。")
    }

    var languageSection: String { pick("Language", "言語") }
}
