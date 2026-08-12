import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppLock.self) private var appLock

    var body: some View {
        ZStack {
            switch appState.phase {
            case .welcome:
                OnboardingFlowView()
                    .transition(.opacity)
            case .pairing:
                PairingView()
                    .transition(.opacity)
            case .main:
                MainTabView()
                    .transition(.opacity)
            }

            // Incoming touch overlay
            if let touch = appState.incomingTouch {
                TouchReceivedOverlay(touch: touch)
                    .transition(.opacity.combined(with: .scale(scale: 1.06)))
                    .zIndex(10)
            }

            // Celebration hearts (partner joined etc.)
            if appState.celebrate {
                FloatingHeartsView(count: 26)
                    .ignoresSafeArea()
                    .zIndex(11)
            }

            // Toast
            if let toast = appState.toast {
                VStack {
                    ToastView(toast: toast)
                        .padding(.top, 8)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(12)
            }

            // App lock gate (Face ID / passcode)
            if appLock.locked {
                LockScreenView()
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .animation(.spring(response: 0.4), value: appState.phase)
        .animation(.spring(response: 0.4), value: appState.incomingTouch != nil)
        .animation(.spring(response: 0.4), value: appState.toast)
        .animation(.easeOut(duration: 0.3), value: appLock.locked)
        .id(appState.uiRefresh)   // full rebuild on language switch
        .fitsPhoneLayout()        // shrink layout on non–Pro Max widths
    }
}

struct MainTabView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState
        TabView(selection: $state.activeTab) {
            DashboardView()
                .tabItem {
                    Label(L10n.t("tab.home"), systemImage: "house.fill")
                        .accessibilityLabel(L10n.t("tab.home"))
                }
                .tag(AppTab.home)

            ChatView()
                .tabItem {
                    Label(L10n.t("tab.chat"), systemImage: "bubble.left.and.bubble.right.fill")
                        .accessibilityLabel(chatTabA11yLabel)
                }
                .badge(appState.unreadChat > 0 ? appState.unreadChat : 0)
                .tag(AppTab.chat)

            PlayHubView()
                .tabItem {
                    Label(L10n.t("tab.play"), systemImage: "gamecontroller.fill")
                        .accessibilityLabel(L10n.t("tab.play"))
                }
                .tag(AppTab.play)

            MemoriesView()
                .tabItem {
                    Label(L10n.t("tab.us"), systemImage: "photo.on.rectangle.angled")
                        .accessibilityLabel(L10n.t("tab.us"))
                }
                .tag(AppTab.memories)

            SettingsView()
                .tabItem {
                    Label(L10n.t("tab.more"), systemImage: "ellipsis.circle.fill")
                        .accessibilityLabel(L10n.t("tab.more"))
                }
                .tag(AppTab.settings)
        }
        .tint(Theme.pink)
        .onChange(of: appState.activeTab) { _, newTab in
            if newTab == .chat { appState.unreadChat = 0 }
        }
    }

    /// VoiceOver announces the unread count together with the tab name.
    private var chatTabA11yLabel: String {
        appState.unreadChat > 0
            ? L10n.t("tab.chat.unreadA11y", ["n": String(appState.unreadChat)])
            : L10n.t("tab.chat")
    }
}
