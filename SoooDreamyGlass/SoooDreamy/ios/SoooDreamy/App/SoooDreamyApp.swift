import SwiftUI
import UIKit
import UserNotifications

/// CI screenshot launches (workflow job "simulator-screenshots"): the app
/// starts with one of these arguments and stages a small, coherent demo
/// state instead of talking to a server. Central so every view that takes
/// part in the staging (e.g. the dashboard's connection pill) reads the
/// same flags as the seeding code in `ScreenshotSeed`.
enum ScreenshotMode {
    static let about = has("-SoooDreamyScreenshotAbout")
    /// Freshly created couple, still waiting for the partner (pairing).
    static let main = has("-SoooDreamyScreenshotMain")
    /// Paired everyday dashboard with the couple's own palette.
    static let paired = has("-SoooDreamyScreenshotPaired")
    /// Chat with a staged conversation (reaction + typing indicator).
    static let chat = has("-SoooDreamyScreenshotChat")
    /// Both answered today's question — the sealed reveal card.
    static let reveal = has("-SoooDreamyScreenshotReveal")
    /// The play hub catalog.
    static let play = has("-SoooDreamyScreenshotPlay")
    /// The settings information architecture.
    static let settings = has("-SoooDreamyScreenshotSettings")
    /// The Us hub — on the iPad leg this proves the Welle-5 split layout
    /// (persistent section sidebar + detail pane on regular width).
    static let memories = has("-SoooDreamyScreenshotMemories")
    // A `-SoooDreamyScreenshotLandscape` variant existed briefly and was
    // removed after two CI rounds: neither a launch-time
    // `requestGeometryUpdate` nor the app-level
    // `supportedInterfaceOrientationsFor` contract rotates a headless
    // iPadOS 26 simulator (runs 31806640307 + 31814760385 shot portrait
    // both times), and `simctl` cannot rotate from the outside. Regular
    // width (and the ≥760 pt game-table threshold) is already proven by
    // the portrait 13-inch iPad shots, so the shot added no evidence.

    /// Modes staging the PAIRED demo couple (palette, partner, transcript).
    static var pairedDemo: Bool {
        paired || chat || reveal || play || settings || memories
    }
    /// Any mode that renders the main tab UI instead of RootView — these
    /// stub the connection pill to "connected" (no server in CI) and
    /// suppress the What's-New sheet.
    static var stagesMainUI: Bool { main || pairedDemo }

    private static func has(_ flag: String) -> Bool {
        ProcessInfo.processInfo.arguments.contains(flag)
    }
}

@main
struct SoooDreamyApp: App {
    @UIApplicationDelegateAdaptor(RemotePushAppDelegate.self) private var pushDelegate
    @State private var appState: AppState
    @State private var appLock = AppLock()
    @Environment(\.scenePhase) private var scenePhase
    private let capturesAboutScreenshot = ScreenshotMode.about
    /// CI screenshot modes for the main tab UI (liquid-glass bar): render
    /// MainTabView with a small seeded demo state, no server required.
    private let capturesMainUIScreenshot = ScreenshotMode.stagesMainUI

    init() {
        StartupPerformance.begin()
        // Foreground banners + notification-tap deep links.
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        // Screenshot modes: mark What's New as already seen so the sheet
        // never covers the captured main UI.
        if ScreenshotMode.stagesMainUI {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            UserDefaults.standard.set(version, forKey: "whatsNew.lastPresentedVersion")
        }
        // Staging BEFORE the first render: the seeded tab is the first tab
        // the tab bar materializes and the couple palette colors the very
        // first frame (no flash of the neutral fallback).
        let state = AppState()
        ScreenshotSeed.stage(state)
        _appState = State(initialValue: state)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if capturesAboutScreenshot {
                    AboutSheet()
                } else if capturesMainUIScreenshot {
                    // RootView normally injects the palette — the staged
                    // main UI must do the same, otherwise the demo couple's
                    // colors (THE point of the paired shots) stay invisible.
                    MainTabView()
                        .environment(\.couplePalette, appState.couple?.palette)
                } else {
                    RootView()
                }
            }
                // Window-driven layout scale for EVERY window root — the
                // staged CI screenshot branches bypass RootView, so the
                // container measurement lives here, once.
                .fitsContainerLayout()
                .environment(appState)
                .environment(appLock)
                .preferredColorScheme(.dark)
                .task {
                    guard !capturesAboutScreenshot, !capturesMainUIScreenshot else {
                        StartupPerformance.end()
                        return
                    }
                    NotificationDelegate.shared.onOpenLink = { url in
                        appState.handleURL(url)
                    }
                    // W7/35-Rest: seed/heal the app-group icon mirror so the
                    // "Passend zum Icon" widget theme matches the home screen.
                    AppIconKit.syncMirror()
                    await appState.bootstrap()
                    StartupPerformance.end()
                    // Ask for permission up-front only when paired and couple
                    // alerts are on. APNs registration then either produces a
                    // token or honestly fails on entitlement-less sideloads.
                    if NotificationPrefs.enabled && appState.phase == .main {
                        _ = await RemotePushRegistration.requestIfAuthorized()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .remotePushToken)) { note in
                    guard let token = note.object as? String else { return }
                    Task { await appState.registerPushToken(token) }
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
                        // Ask iOS for a periodic background refresh so the
                        // widgets stay fresh without the app being opened.
                        BackgroundRefresh.schedule()
                    default:
                        break
                    }
                }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.taskId)) {
            // Headless refresh: pull partner status/moments/daily state,
            // rewrite the app-group snapshot, reload widget timelines —
            // then immediately queue the next run.
            await BackgroundRefresh.refreshNow()
            BackgroundRefresh.schedule()
        }
    }

}
