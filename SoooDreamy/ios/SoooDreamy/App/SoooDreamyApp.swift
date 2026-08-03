import SwiftUI

@main
struct SoooDreamyApp: App {
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .preferredColorScheme(.dark)
                .task {
                    await appState.bootstrap()
                }
                .onOpenURL { url in
                    appState.handleURL(url)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        if appState.phase == .main {
                            appState.connectSocket()
                            Task { await appState.refreshAll() }
                        }
                    case .background:
                        appState.updateWidgetSnapshot()
                    default:
                        break
                    }
                }
        }
    }
}
