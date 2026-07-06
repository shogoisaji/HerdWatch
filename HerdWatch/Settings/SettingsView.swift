import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettingsStore
    let store: PastureStore

    private var strings: SettingsStrings { SettingsStrings(language: settings.language) }

    var body: some View {
        Form {
            Section(strings.windowSection) {
                Toggle(strings.alwaysOnTop, isOn: $settings.alwaysOnTop)
                Toggle(strings.autoRearrangeOnResize, isOn: $settings.autoRearrangeOnResize)
                Toggle(strings.showWorkingElapsed, isOn: $settings.showWorkingElapsed)
            }

            Section(strings.terminalSection) {
                Picker("Terminal", selection: $settings.terminalBundleID) {
                    Text(strings.terminalAuto).tag("")
                    ForEach(TerminalApp.known) { app in
                        Text(app.name).tag(app.bundleID)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Text(strings.focusHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(strings.characterSection) {
                Picker(strings.sizeLabel, selection: $settings.characterSize) {
                    ForEach(CharacterSize.allCases, id: \.self) { size in
                        Text(size.label(for: settings.language)).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                Button(strings.rerollAllButton) {
                    store.rerollAll()
                }
                Text(strings.rerollHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(strings.backgroundSection) {
                Picker(strings.backgroundSection, selection: $settings.background) {
                    ForEach(PastureBackground.allCases, id: \.self) { background in
                        Text(background.label(for: settings.language)).tag(background)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section(strings.connectionSection) {
                TextField(strings.socketPathPrompt, text: $settings.socketPathOverride,
                          prompt: Text("~/.config/herdr/herdr.sock"))
                    .textFieldStyle(.roundedBorder)
                Text(strings.socketPathHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(strings.languageSection) {
                Picker(strings.languageSection, selection: $settings.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.nativeName).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
