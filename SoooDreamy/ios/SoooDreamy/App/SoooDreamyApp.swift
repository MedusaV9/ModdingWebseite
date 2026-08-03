import SwiftUI

@main
struct SoooDreamyApp: App {
    @State private var appState = AppState()
    @State private var appLock = AppLock()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(appLock)
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
                        if appLock.locked {
                            Task { await appLock.unlock() }
                        }
                    case .background:
                        appState.updateWidgetSnapshot()
                        appLock.lockIfNeeded()
                    default:
                        break
                    }
                }
        }
    }
}
