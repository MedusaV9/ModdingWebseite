import SwiftUI
import UIKit

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppLock.self) private var appLock
    /// Reduce Motion: every root transition degrades to a plain crossfade —
    /// no scale pops, no edge moves (commandment 13; the overlay/ceremony
    /// transitions here were previously unfiltered).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Arrival transition for full-screen overlay moments: a soft
    /// scale-in normally, a pure crossfade under Reduce Motion.
    private var overlayTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.06))
    }

    /// Ceremonies use a slightly quieter scale — same Reduce-Motion rule.
    private var ceremonyTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.05))
    }

    private var toastTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
    }

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
                    .transition(overlayTransition)
                    .zIndex(10)
            }

            // Incoming custom vibration (haptics composer moment)
            if let haptic = appState.incomingHaptic {
                HapticReceivedOverlay(haptic: haptic)
                    .transition(overlayTransition)
                    .zIndex(10)
            }

            // Incoming thinking-of-you pulse (live or launch replay)
            if let pulse = appState.incomingPulse {
                PulseReceivedOverlay(pulse: pulse, moreCount: appState.incomingPulseCount)
                    .transition(overlayTransition)
                    .zIndex(10)
            }

            // FullRelease R1-D: a delivered Zeitpost note lands as a
            // MOMENT — the sealed-envelope overlay, same pattern and
            // layer as the touch overlay above.
            if let note = appState.incomingPostNote {
                PostNoteOverlay(note: note)
                    .transition(overlayTransition)
                    .zIndex(10)
            }

            // FullRelease R1-D: the app-wide Lichtschein host — the
            // lamp-gold bloom of every small/medium celebration, over
            // the tab panes and UNDER the moment overlays (the paper
            // twin of the Delight host below, which epic keeps).
            LichtscheinHost()
                .ignoresSafeArea()
                .zIndex(8)

            // W4: the daily-answer reveal ceremony — seal break, three acts,
            // reaction window. Fires once per couple/day/device.
            if let moment = RevealCeremony.shared.moment {
                DailyRevealCeremonyView(moment: moment)
                    .transition(ceremonyTransition)
                    .zIndex(10)
            }

            // Celebration hearts (partner joined etc.). The emitter field
            // ends ABOVE the bottom chrome: hearts drifting on behind the
            // accessory/tab-bar glass read as refraction ghosts through
            // the liquid glass (device feedback), so the field keeps the
            // token-based chrome exclusion and respects the bottom safe
            // area instead of spawning under the bar.
            if appState.celebrate {
                FloatingHeartsView(count: 26)
                    .padding(.bottom, LayoutMetrics.celebrationBottomExclusion)
                    .ignoresSafeArea(edges: [.top, .horizontal])
                    .zIndex(11)
            }

            if let effect = appState.incomingMessageEffect {
                MessageEffectOverlay(effect: effect)
                    .transition(.opacity)
                    .zIndex(11)
            }

            // Duet playback overlay — both phones, same instant
            if let duet = appState.activeDuet {
                DuetOverlayView(duet: duet)
                    .transition(.opacity)
                    .zIndex(9)
            }

            // Level-up / badge ceremonies + icon-gift unwrap
            if let ceremony = appState.levelUpCeremony {
                LevelUpCeremonyView(ceremony: ceremony)
                    .transition(ceremonyTransition)
                    .zIndex(10)
            } else if let badge = appState.badgeCeremony {
                BadgeCeremonyView(badge: badge)
                    .transition(ceremonyTransition)
                    .zIndex(10)
            } else if appState.phase == .main, let gift = appState.pendingIconGift {
                IconGiftUnwrapView(gift: gift)
                    .transition(ceremonyTransition)
                    .zIndex(10)
            }

            // Delight-Engine overlay (micro-celebrations, all screens)
            DelightOverlayHost()
                .zIndex(11)

            // W7 [30]: pairing/link ceremony — the two couple colors merge,
            // then the overlay hands over softly to the dashboard already
            // sitting underneath. Above toasts (it is opaque and carries
            // the announcement itself), below the app lock.
            if let moment = appState.pairingCeremony {
                PairingCeremonyView(moment: moment)
                    .transition(.opacity)
                    .zIndex(13)
            }

            // Toast
            if let toast = appState.toast {
                VStack {
                    ToastView(toast: toast)
                        .padding(.top, 8)
                    Spacer()
                }
                .transition(toastTransition)
                .zIndex(12)
            }

            // App lock gate (Face ID / passcode)
            if appLock.locked {
                LockScreenView()
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .animation(Theme.Motion.arrive, value: appState.phase)
        .animation(Theme.Motion.arrive, value: appState.incomingTouch != nil)
        .animation(Theme.Motion.arrive, value: appState.incomingHaptic != nil)
        .animation(Theme.Motion.arrive, value: appState.incomingPulse != nil)
        .animation(Theme.Motion.arrive, value: appState.incomingPostNote != nil)
        .animation(Theme.Motion.arrive, value: RevealCeremony.shared.moment != nil)
        .animation(Theme.Motion.arrive, value: appState.toast)
        .animation(Theme.Motion.arrive, value: appState.pairingCeremony != nil)
        .animation(Theme.Motion.arrive, value: appState.activeDuet != nil)
        .animation(Theme.Motion.arrive, value: appState.levelUpCeremony != nil)
        .animation(Theme.Motion.arrive, value: appState.badgeCeremony != nil)
        .animation(Theme.Motion.arrive, value: appState.pendingIconGift != nil)
        .animation(Theme.Motion.settle, value: appState.incomingMessageEffect)
        .animation(Theme.Motion.settle, value: appLock.locked)
        // v10: one-time recovery-key ceremony right after pairing.
        .sheet(isPresented: Binding(
            get: { appState.phase == .main && appState.freshRecoveryKey != nil },
            set: { if !$0 { appState.freshRecoveryKey = nil } }
        )) {
            if let key = appState.freshRecoveryKey {
                RecoveryKeyCeremonySheet(recoveryKey: key)
            }
        }
        .id(appState.uiRefresh)   // full rebuild on language switch
        .environment(\.couplePalette, appState.couple?.palette)
        // The window-driven layout scale (fitsContainerLayout) is installed
        // once at the window root in SoooDreamyApp — it must also cover the
        // staged CI screenshot branches that bypass RootView.
    }
}

/// FullRelease N1-A: the custom dock (`LiquidTabBar`) died — this is the
/// REAL iOS-26 `TabView` with system liquid glass, native badges and the
/// "Heute-Zettel" bottom accessory. iPad deliberately keeps the DEFAULT
/// tab-view style (no `sidebarAdaptable` in this wave — Recon §2.7: it
/// would stack a second system sidebar over the Memories split).
struct MainTabView: View {
    @Environment(AppState.self) private var appState
    /// Fix2-A №4: the accessory gate reads the type size — at AX sizes
    /// the „Zustellzettel" is not mounted at all (rule in `LayoutRules`).
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Tabs that materialized at least once. The native TabView is expected
    /// to keep visited panes alive itself (Recon §2.3), but that lifecycle
    /// is not formally documented — this defensive scaffold guarantees the
    /// lazy half either way: an unvisited pane never builds eagerly.
    @State private var visitedTabs: Set<AppTab> = []

    var body: some View {
        Group {
            // Fix2-A №4 (accessory gate): at accessibility text sizes the
            // bottom chrome (Zustellzettel + tab bar) ate the content, so
            // the accessory stays UNMOUNTED there — its information
            // (round + today status) lives in the Postfach itself. The
            // pure rule is `LayoutRules.accessoryMounted`; the Postfach
            // bottom clearance drops the accessory share in the same
            // stroke (`LayoutRules.restingBottomClearance(isAccessibilitySize:)`).
            if LayoutRules.accessoryMounted(
                isAccessibilitySize: dynamicTypeSize.isAccessibilitySize) {
                stationTabs
                    // No minimize-on-scroll: on real devices the minimized
                    // bar only grew back at the very TOP of the scroll (not
                    // on the way up), which read as broken — the bar stays
                    // fully visible instead. The "Heute-Zettel": partner
                    // presence + today's streak/daily hint as the
                    // persistent couple status above the bar (Recon §2.8).
                    .tabViewBottomAccessory {
                        TodayAccessoryView()
                    }
            } else {
                stationTabs
            }
        }
        // The system bar ticks silently — the selection haptic the custom
        // dock had stays.
        .sensoryFeedback(.selection, trigger: appState.activeTab)
        // Welle 7 [29]: demo mode wears its permanent badge as a top bar —
        // above every tab, impossible to miss, and itself the exit.
        // `safeAreaInset` (not `safeAreaBar`): on real devices the bar
        // variant floated OVER the panes without reserving space — the
        // home header slid under the DEMO band. The inset genuinely
        // shrinks every tab's safe area, one central fix for all five.
        .safeAreaInset(edge: .top, spacing: 0) {
            if appState.demoActive {
                DemoBadge()
                    .padding(.bottom, LayoutMetrics.s(6))
            }
        }
        // One source of truth for the accent: the derived couple tint
        // (falls back to the warm neutral before pairing) — it IS the
        // selection color of the system bar.
        .tint(CoupleTint(palette: appState.couple?.palette).blend)
        .onAppear {
            visitedTabs.insert(appState.activeTab)
        }
        .onChange(of: appState.activeTab) { _, newTab in
            visitedTabs.insert(newTab)
            if newTab == .chat { appState.unreadChat = 0 }
        }
        .background { tabShortcuts }
    }

    /// Neubau tab identity, complete (ENTSCHEID §2.1): N2 brought the
    /// five station SYMBOLS and "Postfach" (`postfach.tab.home`); N4
    /// renamed the remaining four labels IN CoreStrings — Schreibstube /
    /// Spieltisch / Archiv / Amt — in the same stroke as their UITest
    /// `switchTab` labelPrefix fallbacks and the `navigationBars["Amt"]`
    /// anchor. Every a11y-ID below stays literal (`switchTab` is
    /// ID-first).
    private var stationTabs: some View {
        TabView(selection: reselectAwareSelection) {
            Tab(L10n.t("postfach.tab.home"), systemImage: "tray.and.arrow.down",
                value: AppTab.home) {
                tabPane(.home) { DashboardView() }
            }
            .accessibilityIdentifier("tab.home")
            Tab(L10n.t("tab.chat"), systemImage: "envelope",
                value: AppTab.chat) {
                tabPane(.chat) { ChatView() }
            }
            // "99+" cap stays our logic (`TabBarLogic.badgeText`, LogicTest-
            // pinned); the `Text?` overload hides the badge via nil.
            .badge(TabBarLogic.badgeText(for: appState.unreadChat).map { Text($0) })
            .accessibilityLabel(Text(chatTabA11yLabel))
            .accessibilityIdentifier("tab.chat")
            Tab(L10n.t("tab.play"), systemImage: "dice",
                value: AppTab.play) {
                tabPane(.play) { PlayHubView() }
            }
            .badge(TabBarLogic.badgeText(for: appState.gamesAwaitingMe.count).map { Text($0) })
            .accessibilityLabel(Text(playTabA11yLabel))
            .accessibilityIdentifier("tab.play")
            Tab(L10n.t("tab.us"), systemImage: "archivebox",
                value: AppTab.memories) {
                tabPane(.memories) { MemoriesView() }
            }
            .accessibilityIdentifier("tab.us")
            Tab(L10n.t("tab.more"), systemImage: "building.columns",
                value: AppTab.settings) {
                tabPane(.settings) { SettingsView() }
            }
            .accessibilityIdentifier("tab.settings")
        }
    }

    /// Native re-tap detection (Recon §2.6): the selection binding's setter
    /// fires with the IDENTICAL value when the active tab is tapped again —
    /// that is the HIG "back to the top" gesture.
    private var reselectAwareSelection: Binding<AppTab> {
        Binding(
            get: { appState.activeTab },
            set: { newTab in
                if newTab == appState.activeTab {
                    scrollActivePaneToTop()
                }
                appState.activeTab = newTab
            }
        )
    }

    /// Hardware-keyboard tab switching (iPad, roadmap 19). Key map, in
    /// bar order: ⌘1 Home · ⌘2 Chat · ⌘3 Play · ⌘4 Us · ⌘5 More.
    /// (⌘↩ sends in Chat — see ChatView; Esc closes sheets — system.)
    /// Zero-size, invisible buttons: `keyboardShortcut` needs an installed
    /// Button — the native bar offers no numbered tab shortcuts of its own.
    private var tabShortcuts: some View {
        ForEach(Array(shortcutTabs.enumerated()), id: \.element) { index, tab in
            // Tab side effects (visited set, unread reset) live in the
            // existing `onChange(of: activeTab)` — one path for bar & keys.
            Button(String(index + 1)) {
                appState.activeTab = tab
            }
            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))),
                              modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    /// Same order as the Tab builders — ⌘-numbers always match the bar.
    private var shortcutTabs: [AppTab] { [.home, .chat, .play, .memories, .settings] }

    /// Defensive lazy scaffold inside the native Tab contents (Recon §1.5.5
    /// marks the eager-vs-lazy question as SDK-unverified): a pane builds
    /// when it IS the selection (covers the very first frame — the staged
    /// CI tab renders without an onAppear race) or once it was visited.
    /// Keep-alive itself is the native TabView's documented-in-practice
    /// behavior; this guard only prevents eager materialization.
    @ViewBuilder
    private func tabPane<Content: View>(
        _ tab: AppTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if appState.activeTab == tab || visitedTabs.contains(tab) {
            content()
        }
    }

    /// VoiceOver announces the unread count together with the tab name.
    private var chatTabA11yLabel: String {
        appState.unreadChat > 0
            ? L10n.t("tab.chat.unreadA11y", count: appState.unreadChat)
            : L10n.t("tab.chat")
    }

    private var playTabA11yLabel: String {
        appState.gamesAwaitingMe.isEmpty
            ? L10n.t("tab.play")
            : L10n.t("tab.play.awaitingA11y", count: appState.gamesAwaitingMe.count)
    }

    // MARK: Re-tap on the active tab → back to the top (HIG)

    /// Re-tapping the active tab returns its pane to the top. The panes are
    /// kept-alive SwiftUI views whose files the bar owner must not reach
    /// into — but SwiftUI scroll views ride on UIScrollView, so the owner
    /// walks the key window once and glides every surface that qualifies
    /// (visible, vertically scrollable, not already at the top — the pure
    /// rule lives in `TabBarLogic.shouldScrollToTop`) back up. Parked tab
    /// panes sit offscreen/hidden in the UIKit-backed TabView; the walk
    /// skips hidden/transparent branches whole so their scroll positions
    /// survive, as promised.
    private func scrollActivePaneToTop() {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        guard let window else { return }
        scrollToTop(walking: window)
    }

    private func scrollToTop(walking view: UIView) {
        for subview in view.subviews {
            if subview.isHidden || subview.alpha < 0.01 { continue }
            if let scroll = subview as? UIScrollView,
               TabBarLogic.shouldScrollToTop(
                   alpha: Double(scroll.alpha),
                   isHidden: scroll.isHidden || scroll.window == nil,
                   contentHeight: Double(scroll.contentSize.height),
                   boundsHeight: Double(scroll.bounds.height),
                   offsetY: Double(scroll.contentOffset.y),
                   topInset: Double(scroll.adjustedContentInset.top)) {
                scroll.setContentOffset(
                    CGPoint(x: scroll.contentOffset.x,
                            y: -scroll.adjustedContentInset.top),
                    animated: true)
            }
            scrollToTop(walking: subview)
        }
    }
}
