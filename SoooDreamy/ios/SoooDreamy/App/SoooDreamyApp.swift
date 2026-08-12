import SwiftUI
import UserNotifications

@main
struct SoooDreamyApp: App {
    @State private var appState = AppState()
    @State private var appLock = AppLock()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Foreground banners + notification-tap deep links.
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(appLock)
                .preferredColorScheme(.dark)
                .task {
                    NotificationDelegate.shared.onOpenLink = { url in
                        appState.handleURL(url)
                    }
                    await appState.bootstrap()
                    // Ask for permission up-front only when paired and couple
                    // alerts are on (post() also asks lazily as a fallback).
                    if NotificationPrefs.enabled && appState.phase == .main {
                        _ = await CoupleNotify.requestAuthorizationIfNeeded()
                    }
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
