import SwiftUI
import Sparkle
import HerdWatchShared

@main
@MainActor
struct HerdWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings: AppSettingsStore
    @State private var store: PastureStore
    @State private var animator = AgentAnimator()
    private let focusService: HerdrFocusService
    private let companionHost: CompanionHostService

    init() {
        let settings = AppSettingsStore()
        let transport = HerdrSocketTransport(socketPath: settings.effectiveSocketPath)
        _settings = State(initialValue: settings)
        _store = State(initialValue: PastureStore(
            client: HerdrClient(transport: transport),
            assignments: CharacterAssignmentStore()
        ))
        focusService = HerdrFocusService(transport: transport)
        let link = CompanionLink()
        companionHost = CompanionHostService(
            store: _store.wrappedValue,
            focusService: focusService,
            terminalBundleID: { settings.terminalBundleID },
            link: link)
    }

    var body: some Scene {
        Window("HerdWatch", id: "pasture") {
            PastureView(
                store: store,
                onFocusAgent: { [focusService, settings] agent in
                    let bundleID = settings.terminalBundleID
                    Task { await focusService.focus(paneID: agent.paneID, terminalBundleID: bundleID) }
                },
                onRerollAgent: { [store] agent in
                    store.reroll(agent.identity)
                },
                pixelSize: settings.characterSize.pixelSize,
                autoRearrangeOnResize: settings.autoRearrangeOnResize,
                background: settings.background,
                showWorkingElapsed: settings.showWorkingElapsed,
                animator: animator
            )
            .frame(minWidth: 160,
                   minHeight: AgentAnimator.minimumWindowHeight(pixelSize: CharacterSize.tiny.pixelSize))
            .background(WindowLevelApplier(floating: settings.alwaysOnTop))
            .ignoresSafeArea()  // 旧タイトルバー領域まで芝生を広げる
            .task {
                store.start()
                companionHost.start()
            }
        }
        .windowResizability(.contentMinSize)
        // タイトルバーを透明化し、信号機ボタンだけをコンテンツ上に浮かせる
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appSettings) {
                Button("アップデートを確認…") {
                    appDelegate.checkForUpdates()
                }
            }

            CommandMenu("放牧場") {
                Button("リロード") {
                    Task { [store, animator, companionHost] in
                        await store.refresh()
                        animator.scatter(agents: store.sortedAgents)
                        companionHost.pushCurrentState()
                    }
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("キャラクターをランダムに振り直す") {
                    store.rerollAll()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            #if DEBUG
            CommandMenu("デバッグ") {
                Button("全キャラの状態を順送り") { store.debugCycleStates() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
            }
            #endif
        }

        Settings {
            SettingsView(settings: settings, store: store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var updaterController: SPUStandardUpdaterController?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Sparkle 自動更新を起動（SUFeedURL/SUPublicEDKey は Info.plist から読込）
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
}

/// SwiftUIのWindowシーンにfloatingレベルと「タイトルバー透明・信号機のみ」を適用するブリッジ。
struct WindowLevelApplier: NSViewRepresentable {
    let floating: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            Self.configure(view.window, floating: floating)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Self.configure(nsView.window, floating: floating)
    }

    private static func configure(_ window: NSWindow?, floating: Bool) {
        guard let window else { return }
        window.level = floating ? .floating : .normal
        // タイトルバーを透明化し、コンテンツを信号機ボタンの裏まで広げる
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.toolbar = nil
    }
}
