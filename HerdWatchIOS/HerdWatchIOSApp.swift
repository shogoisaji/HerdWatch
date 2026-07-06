import SwiftUI

@main
struct HerdWatchIOSApp: App {
    @State private var store: CompanionStore

    init() {
        let client = CompanionClient()
        _store = State(initialValue: CompanionStore(client: client))
    }

    var body: some Scene {
        WindowGroup {
            CompanionPastureView(
                store: store,
                onFocus: { [store] agent in
                    store.focus(paneID: agent.paneID)
                },
                onReload: { [store] in
                    store.reload()
                }
            )
            .task { store.start() }
        }
    }
}
