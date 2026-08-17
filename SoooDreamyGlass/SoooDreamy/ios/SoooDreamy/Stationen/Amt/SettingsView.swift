import SwiftUI
import WidgetKit

/// Station 5 AMT (`tab.settings`) — the quiet operations room of the
/// night post office (Neubau N4, ENTSCHEID §4.5): six still sections on
/// night carton, no artifacts, no grain. Every sheet stays a sheet.
struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showProfileEdit = false
    @State private var showServers = false
    @State private var showAbout = false
    @State private var showPersonalization = false
    @State private var showPairingCode = false
    @State private var confirmDissolve = false
    @State private var confirmLeave = false

    @State private var soundsOn = SoundEngine.enabled
    @State private var hapticsOn = Haptics.enabled
    @State private var appLockOn = AppLock.isEnabled
    @State private var pulseOn = CouplePulseController.isEnabled

    @State private var alertsOn = NotificationPrefs.enabled
    /// W8 Settings-IA: the notification details moved into their own sheet —
    /// the card keeps the master switch and a one-line summary.
    @State private var showNotificationSheet = false
    @State private var showDiagnostics = false

    @State private var showWidgetStudio = false
    @State private var showLiveActivitySheet = false
    @State private var showICloudSheet = false
    @State private var showMigrationAssistant = false
    @State private var showIconGiftSheet = false
    @State private var showRecoverySheet = false
    /// FullRelease P6-C: replay the first-launch cinema, HERE and NOW —
    /// a fullScreenCover around `CinematicIntroView { dismiss }` instead of
    /// `CinematicIntroGate.resetForReplay()`, because the reset only takes
    /// effect on the next OnboardingFlowView appearance: paired couples
    /// never see onboarding again, so for them the flag reset would be a
    /// silent no-op. The cover plays for everyone, immediately. (The
    /// cinema's own `markSeen()` on finish is harmless — already seen.)
    @State private var showCinematicReplay = false
    /// Multi-device: sessions of MY member + the add-device QR flow.
    @State private var showDeviceManager = false
    /// W7-Rest: the automations gallery (5 Shortcuts recipes + Siri tips).
    @State private var showAutomations = false
    /// Setzkasten: the couple's own daily questions (ENTSCHEID §2.2 —
    /// also reachable from the daily letter's context menu).
    @State private var showCustomQuestions = false

    /// N2 wired the key and the Postfach staging — the Amt owns ONLY
    /// this switch (ENTSCHEID §4.6: staging is stage, never gate).
    @AppStorage("zustelldienst.rundenInszenieren") private var rundenInszenieren = true
    /// Schlüsseldreh trigger — each arming turns the key symbol once.
    @State private var keyTurns = 0

    @State private var coupleName = ""
    @State private var anniversary = Date()
    @State private var hasAnniversary = false

    /// Server version reported by `/api/health` (nil while loading/unreachable).
    @State private var serverVersion: String?

    var body: some View {
        NavigationStack {
            ZStack {
                // The Amt is the STILL room of the app (Fix-Runde 3,
                // Amt-Befund 8): `showStars` was inert while the ink
                // dust kept animating at 12 Hz underneath the forms —
                // `showBlobs: false` is the flag that actually rests
                // the dust. The room (gradient + lamp cone) stays.
                DreamyBackground(showBlobs: false)
                // The six still sections of the office as a NATIVE grouped
                // Form (bindender Bauplan §4.5, Amt-Eval S2): Unser Amt ·
                // Zustelldienst · Zweigstellen & Bezirke · Werkstatt ·
                // Sicherung & Schlüssel · Betriebsbuch (danger zone at the
                // end, as today). The section headers speak the
                // Amtsregister voice (`Typo.anschrift`); the existing
                // night cards ride as full-bleed rows on clear row chrome,
                // so every row, sheet and a11y-ID survives unchanged.
                Form {
                    amtSection("settings.section.unserAmt") {
                        profileCard
                        coupleCard
                    }
                    amtSection("settings.section.zustelldienst") {
                        notificationsCard
                        zustellrundenCard
                    }
                    amtSection("settings.section.zweigstellen") {
                        serverCard
                    }
                    amtSection("settings.section.werkstatt") {
                        appCard
                        SeasonThemeCard()
                    }
                    amtSection("settings.section.sicherung") {
                        securityCard
                    }
                    amtSection("settings.section.betriebsbuch") {
                        betriebsbuchCard
                        aboutCard
                        dangerCard
                    }
                }
                .formStyle(.grouped)
                // The night room stays the ground — the Form contributes
                // structure, never the system's grouped gray.
                .scrollContentBackground(.hidden)
                .listRowSpacing(LayoutMetrics.s(12))
                .listSectionSpacing(LayoutMetrics.s(20))
                .contentColumn(.reading)
                // Resting clearance above the bottom chrome — the about
                // card must not park inside the accessory/tab-bar
                // refraction band (glass mirrors resting text;
                // LayoutRules token, read-only).
                .contentMargins(.bottom, LayoutMetrics.restingBottomClearance,
                                for: .scrollContent)
                // Settings scrolls under real chrome on BOTH edges (system
                // navigation bar above, floating dock below) — soft edges,
                // matching the wave-2 aurora decision.
                .scrollEdgeEffectStyle(.soft, for: .vertical)
            }
            .navigationTitle(L10n.t("settings.title"))
            // FullRelease N1-A: help moved from the dock into the screen
            // headers — Settings has a real navigation bar, so it takes
            // the native toolbar item.
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HandbookButton(anchor: "settings", style: .toolbar)
                }
            }
        }
        .sheet(isPresented: $showProfileEdit) { ProfileEditSheet() }
        .sheet(isPresented: $showServers) { ServerListSheet() }
        .sheet(isPresented: $showAbout) { AboutSheet() }
        .sheet(isPresented: $showPersonalization) { PersonalizationSheet() }
        .sheet(isPresented: $showPairingCode) { PairingCodeSheet() }
        .sheet(isPresented: $showWidgetStudio) { WidgetStudioView() }
        .sheet(isPresented: $showLiveActivitySheet) { LiveActivitySheet() }
        .sheet(isPresented: $showICloudSheet) { ICloudSheet() }
        .sheet(isPresented: $showMigrationAssistant) { MigrationAssistantView() }
        .sheet(isPresented: $showIconGiftSheet) { IconGiftSheet() }
        .sheet(isPresented: $showRecoverySheet) { RecoverySheet() }
        .sheet(isPresented: $showDeviceManager) { DeviceManagerSheet() }
        .sheet(isPresented: $showAutomations) { AutomationsGalleryView() }
        .sheet(isPresented: $showNotificationSheet) { NotificationSettingsSheet() }
        .sheet(isPresented: $showDiagnostics) { DiagnosticsView() }
        .sheet(isPresented: $showCustomQuestions) { CustomQuestionsView() }
        .fullScreenCover(isPresented: $showCinematicReplay) {
            CinematicIntroView { showCinematicReplay = false }
        }
        .onAppear { syncFromState() }
        .onChange(of: appState.couple) { syncFromState() }
        .task(id: appState.servers.activeProfileID) { await loadServerVersion() }
    }

    /// Fetches the server version for the connection card — re-runs whenever
    /// the active server profile changes.
    private func loadServerVersion() async {
        serverVersion = nil
        guard let api = appState.api else { return }
        serverVersion = try? await api.health().version
    }

    private func syncFromState() {
        coupleName = appState.couple?.name ?? ""
        if let key = appState.couple?.anniversary, let date = SharedDates.parse(key) {
            anniversary = date
            hasAnniversary = true
        } else {
            hasAnniversary = false
        }
    }

    // MARK: Sections

    /// One NATIVE Form section of the office (ENTSCHEID §4.5): the
    /// header prints in the Amtsregister voice — `Typo.anschrift`, the
    /// app's one small-caps register (AX sizes drop the small caps).
    /// Rows keep the night-card material on cleared row chrome; the
    /// cards keep their own scope badges (couple vs. device) where they
    /// always were.
    private func amtSection<Content: View>(
        _ titleKey: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Section {
            content()
        } header: {
            Text(L10n.t(titleKey))
                .font(Typo.anschrift(
                    isAccessibilitySize: dynamicTypeSize.isAccessibilitySize))
                .foregroundStyle(Nacht.sekundaer)
                .textCase(nil)
                .accessibilityAddTraits(.isHeader)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }

    // MARK: Cards

    private var profileCard: some View {
        Button {
            showProfileEdit = true
        } label: {
            HStack(spacing: LayoutMetrics.s(14)) {
                EmojiAvatarView(emoji: appState.me?.avatar, colorHex: appState.me?.color, size: LayoutMetrics.s(56))
                VStack(alignment: .leading, spacing: 3) {
                    Text(appState.me?.name ?? "–")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Papier.aufNacht)
                    Text(L10n.t("settings.profile"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Nacht.sekundaer)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .foregroundStyle(Nacht.tertiaer)
            }
            .nightCard(grain: false)
        }
        .buttonStyle(.plain)
    }

    private var coupleCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(14)) {
            HStack(spacing: Space.s) {
                SectionHeader(title: L10n.t("settings.couple"))
                ScopeBadge(scope: .couple)
            }

            TextField(L10n.t("settings.coupleName"), text: $coupleName)
                .textFieldStyle(DreamyFieldStyle())
                .submitLabel(.done)
                .onSubmit { saveCoupleName() }

            VStack(alignment: .leading, spacing: 6) {
                // Form labels speak rounded on the night card (serif stays
                // paper-only).
                Text(L10n.t("settings.anniversary"))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Nacht.sekundaer)
                DatePicker(L10n.t("settings.anniversaryHint"),
                           selection: $anniversary,
                           in: ...Date(),
                           displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    // The picker sits on the night card — dark scheme,
                    // couple blend as tint.
                    .colorScheme(.dark)
                    .tint(coupleTint.blend)
                    // The system control follows the DEVICE locale, the
                    // office speaks the APP language — „16. Dez 2024",
                    // never "16. Dec 2024" in the German Amt (Befund 3).
                    .environment(\.locale, Locale(identifier: L10n.lang))
                    .onChange(of: anniversary) { _, newValue in
                        saveAnniversary(newValue)
                    }
                if !hasAnniversary {
                    Text(L10n.t("home.sinceHint"))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Nacht.tertiaer)
                }
            }

            // Re-show the pairing code & QR (new device, or partner needs it again).
            if appState.couple?.code != nil {
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        Haptics.shared.tap()
                        showPairingCode = true
                    } label: {
                        Label(L10n.t("settings.pairingShow"), systemImage: "qrcode")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Text(L10n.t("settings.pairingHint"))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Nacht.tertiaer)
                }
            }
        }
        .nightCard(grain: false)
    }

    /// Zweigstellen & Bezirke: the server districts (profiles), this
    /// member's branch offices (devices) and the moving assistant.
    private var serverCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(12)) {
            SectionHeader(title: L10n.t("settings.connection"))

            if let profile = appState.servers.activeProfile {
                HStack(spacing: LayoutMetrics.s(10)) {
                    Image(systemName: "server.rack")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Nacht.sekundaer)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.name)
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(Papier.aufNacht)
                        Text(profile.urlString)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Nacht.sekundaer)
                        if let serverVersion {
                            Text(L10n.t("settings.serverVersion", ["version": serverVersion]))
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(Nacht.tertiaer)
                        }
                    }
                    Spacer()
                    ConnectionBanner(state: appState.socket.state)
                }
            }

            Button {
                showServers = true
            } label: {
                Label(L10n.t("server.manage"), systemImage: "slider.horizontal.3")
            }
            .buttonStyle(SecondaryButtonStyle())

            // Multi-device: my sessions, "this device", revoke, add device.
            SettingsLinkRow(icon: "ipad.and.iphone",
                            title: L10n.t("devices.title"),
                            hint: L10n.t("devices.settingsHint")) {
                showDeviceManager = true
            }

            SettingsLinkRow(icon: "arrow.triangle.2.circlepath",
                            title: L10n.t("migration.title"),
                            hint: L10n.t("migration.settingsHint")) {
                showMigrationAssistant = true
            }
        }
        .nightCard(grain: false)
    }

    /// Werkstatt: everything that tunes THIS device's experience —
    /// language, sounds, haptics, pulse, Aushangkasten (widgets/Live
    /// Activity), Sortiermaschine (automations), Schreibzeug (inks),
    /// Prägeplatten (icons) and the intelligence consent.
    private var appCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(14)) {
            HStack(spacing: Space.s) {
                SectionHeader(title: L10n.t("settings.appSection"))
                ScopeBadge(scope: .device)
            }

            // Language
            HStack {
                Label(L10n.t("settings.language"), systemImage: "globe")
                    .labelStyle(SettingsRowLabelStyle())
                Spacer()
                Menu {
                    ForEach(AppLanguage.allCases) { lang in
                        Button {
                            L10n.language = lang
                            CinematicIntroGate.markLanguageChosen()
                            appState.uiRefresh += 1
                        } label: {
                            if L10n.language == lang {
                                Label(L10n.t(lang.displayNameKey), systemImage: "checkmark")
                            } else {
                                Text(L10n.t(lang.displayNameKey))
                            }
                        }
                    }
                } label: {
                    Text(L10n.t(L10n.language.displayNameKey))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Licht.lampengold)
                }
            }

            Toggle(isOn: $soundsOn) {
                Label(L10n.t("settings.sounds"), systemImage: "speaker.wave.2.fill")
                    .labelStyle(SettingsRowLabelStyle())
            }
            .tint(coupleTint.blend)
            .onChange(of: soundsOn) { _, on in
                SoundEngine.enabled = on
                if on { SoundEngine.shared.play(.chime) }
            }

            // Per-category volumes (release plays a preview)
            if soundsOn {
                VStack(alignment: .leading, spacing: LayoutMetrics.s(8)) {
                    Text(L10n.t("settings.soundvol.title"))
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(Nacht.tertiaer)
                    ForEach(SoundEngine.Category.allCases) { category in
                        SoundVolumeRow(category: category)
                    }
                }
                .padding(.leading, LayoutMetrics.s(30))
                .transition(.opacity)
            }

            Toggle(isOn: $hapticsOn) {
                Label(L10n.t("settings.haptics"), systemImage: "iphone.radiowaves.left.and.right")
                    .labelStyle(SettingsRowLabelStyle())
            }
            .tint(coupleTint.blend)
            .onChange(of: hapticsOn) { _, on in
                Haptics.enabled = on
                if on { Haptics.shared.play(.heartbeat) }
            }

            // Couple Pulse Live Activity (lock screen + Dynamic Island)
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $pulseOn) {
                    Label(L10n.t("settings.pulse"), systemImage: "heart.text.square.fill")
                        .labelStyle(SettingsRowLabelStyle())
                }
                .tint(coupleTint.blend)
                .onChange(of: pulseOn) { _, on in
                    CouplePulseController.isEnabled = on
                    Haptics.shared.tap()
                    if on {
                        if CouplePulseController.start(from: appState) {
                            appState.showToast(L10n.t("settings.pulseStarted"), style: .success)
                        } else {
                            pulseOn = false
                            CouplePulseController.isEnabled = false
                            appState.showToast(L10n.t("memories.events.liveFailed"), style: .error)
                        }
                    } else {
                        CouplePulseController.stop()
                    }
                }
                Text(L10n.t("settings.pulseHint"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
                    .padding(.leading, LayoutMetrics.s(40))
            }

            // Live Activity styling (theme, ticker, visible elements)
            SettingsLinkRow(icon: "bolt.badge.clock.fill",
                            title: L10n.t("la.title"),
                            hint: L10n.t("la.settingsHint")) {
                showLiveActivitySheet = true
            }

            // Widget Studio — live preview + configure every widget
            SettingsLinkRow(icon: "square.grid.2x2.fill",
                            title: L10n.t("studio.title"),
                            hint: L10n.t("studio.settingsHint")) {
                showWidgetStudio = true
            }

            // W7-Rest: automations gallery (the push replacement recipes)
            SettingsLinkRow(icon: "sparkles.rectangle.stack.fill",
                            title: L10n.t("automations.title"),
                            hint: L10n.t("automations.settingsHint")) {
                showAutomations = true
            }

            // Schreibzeug: couple palette, monogram & pet names — moved
            // from the couple card into the workshop (ENTSCHEID §2.2).
            SettingsLinkRow(icon: "paintpalette.fill",
                            title: L10n.t("personalization.title"),
                            hint: L10n.t("personalization.settings.hint")) {
                showPersonalization = true
            }

            // Prägeplatten: app icon & icon gifts (unwrap stays an overlay)
            SettingsLinkRow(icon: "app.gift.fill",
                            title: L10n.t("icongift.section"),
                            hint: L10n.t("icongift.pickMine")) {
                showIconGiftSheet = true
            }

            intelligenceBlock
        }
        .nightCard(grain: false)
    }

    // Sicherung & Schlüssel: one home for everything that guards the
    // couple — the app lock behind the key, the recovery safety net
    // (key, rejoin, partner replace) and the iCloud backup. Serious
    // night carton — the safe of the office, no grain play.
    private var securityCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(14)) {
            HStack(spacing: Space.s) {
                SectionHeader(title: L10n.t("settings.security"), systemImage: "lock.shield.fill")
                ScopeBadge(scope: .device)
            }

            if AppLock.isAvailable {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: $appLockOn) {
                        Label {
                            Text(L10n.t("settings.appLock"))
                        } icon: {
                            // Signature — Der Schlüsseldreh (ENTSCHEID
                            // §4.5): arming turns the key via NATIVE
                            // symbol motion (`raw_rotation_features`
                            // stays untouched); Reduce Motion sees only
                            // the outline→filled swap as a fade.
                            Image(systemName: appLockOn
                                  ? "key.horizontal.fill" : "key.horizontal")
                                .symbolEffect(.rotate.byLayer,
                                              options: .nonRepeating,
                                              value: keyTurns)
                                .contentTransition(reduceMotion
                                    ? .opacity : .symbolEffect(.replace))
                        }
                        .labelStyle(SettingsRowLabelStyle())
                    }
                    .tint(coupleTint.blend)
                    .onChange(of: appLockOn) { _, on in
                        AppLock.isEnabled = on
                        if on {
                            schluesseldreh()
                        } else {
                            Haptics.shared.tap()
                        }
                    }
                    Text(L10n.t("settings.appLockHint"))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Nacht.tertiaer)
                        .padding(.leading, LayoutMetrics.s(40))
                }
            }

            SettingsLinkRow(icon: "key.fill",
                            title: L10n.t("recovery.title"),
                            hint: L10n.t("recovery.settingsHint")) {
                showRecoverySheet = true
            }

            // iCloud & backup — CloudKit + file export/restore
            SettingsLinkRow(icon: "icloud.fill",
                            title: L10n.t("icloud.title"),
                            hint: L10n.t("icloud.settingsHint")) {
                showICloudSheet = true
            }
        }
        .nightCard(grain: false)
    }

    /// Signature — Der Schlüsseldreh: one native key turn plus the
    /// metallic unlock click from the AppCue stock, haptic-only —
    /// deliberately soundless (tool rooms stay quiet). Reduce Motion
    /// skips the turn (the symbol swap fades), the click stays.
    private func schluesseldreh() {
        if !reduceMotion { keyTurns += 1 }
        Haptics.shared.play(events: AppCue.unlock.hapticTwin)
    }

    /// Apple Intelligence in the privacy card: the durable consent switch
    /// on capable devices, the honest reason line everywhere else — the
    /// feature entry points hide, Settings does the explaining.
    @ViewBuilder private var intelligenceBlock: some View {
        let availability = Intelligence.shared.availability
        if availability == .available {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: Binding(
                    get: { Intelligence.shared.consent == .granted },
                    set: { on in
                        Intelligence.shared.apply(on ? .grant : .revoke)
                        Haptics.shared.tap()
                    }
                )) {
                    Label(L10n.t("ai.settings.toggle"), systemImage: "sparkles")
                        .labelStyle(SettingsRowLabelStyle())
                }
                .tint(coupleTint.blend)
                Text(L10n.t("ai.settings.hint"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
                    .padding(.leading, LayoutMetrics.s(40))
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Label(L10n.t("ai.consent.title"), systemImage: "sparkles")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Nacht.sekundaer)
                Text(L10n.t(availability.l10nKey))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var notificationsCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(14)) {
            HStack(spacing: Space.s) {
                SectionHeader(title: L10n.t("notif.section"))
                ScopeBadge(scope: .device)
            }

            // Master switch for local alerts and APNs when the signed build
            // and server both have their external push credentials.
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $alertsOn) {
                    Label(L10n.t("notif.master"), systemImage: "bell.and.waves.left.and.right")
                        .labelStyle(SettingsRowLabelStyle())
                }
                .tint(coupleTint.blend)
                .onChange(of: alertsOn) { _, on in
                    NotificationPrefs.enabled = on
                    if on {
                        Task {
                            let ok = await RemotePushRegistration.requestIfAuthorized()
                            if !ok {
                                alertsOn = false
                                NotificationPrefs.enabled = false
                            }
                        }
                    } else {
                        Task { await appState.unregisterPushDevice() }
                    }
                }
                Text(L10n.t("notif.masterHint"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
                    .padding(.leading, LayoutMetrics.s(40))
            }

            if alertsOn {
                Text(notificationSummary)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Nacht.sekundaer)
                    .padding(.leading, LayoutMetrics.s(40))
            }

            // Always reachable: the daily reminder and streak guard in the
            // sheet are local nudges, independent of the couple-alerts switch.
            SettingsLinkRow(icon: "bell.badge.waveform.fill",
                            title: L10n.t("notif.customize"),
                            hint: L10n.t("notif.customizeHint")) {
                showNotificationSheet = true
            }
        }
        .nightCard(grain: false)
    }

    /// One line instead of six toggles: „5 von 6 Ereignissen an".
    private var notificationSummary: String {
        // Recomputed whenever the sheet closes (state change re-evaluates body).
        _ = showNotificationSheet
        let total = CoupleAlertKind.allCases.count
        let on = CoupleAlertKind.allCases.filter { NotificationPrefs.isEnabled($0) }.count
        return L10n.t("notif.summary", ["on": String(on), "total": String(total)])
    }

    /// The delivery-round switch (ENTSCHEID §4.6, hard respect rule:
    /// staging is removable) plus the Setzkasten — the couple's own
    /// daily questions feeding the morning post.
    private var zustellrundenCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(14)) {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $rundenInszenieren) {
                    Label(L10n.t("settings.zustellrunden"), systemImage: "theatermasks")
                        .labelStyle(SettingsRowLabelStyle())
                }
                .tint(coupleTint.blend)
                .onChange(of: rundenInszenieren) { _, _ in
                    Haptics.shared.tap()
                }
                .accessibilityIdentifier("amt.zustellrunden")
                // Honest about the reach: rounds are stage, device-local,
                // never a gate (ENTSCHEID §4.6).
                Text(L10n.t("settings.zustellrundenHint"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
                    .padding(.leading, LayoutMetrics.s(40))
            }

            SettingsLinkRow(icon: "plus.bubble",
                            title: L10n.t("dailyq.title"),
                            hint: L10n.t("settings.dailyqHint")) {
                showCustomQuestions = true
            }
        }
        .nightCard(grain: false)
    }

    /// Betriebsbuch: the office's reference shelf — connection doctor
    /// and the founding film; version history, sound credits and the
    /// origin story live one row further in the about sheet.
    private var betriebsbuchCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(14)) {
            // W8 (Linse 12 #7): step-by-step checkup with traffic lights —
            // troubleshooting belongs into the app, not into the couple chat.
            SettingsLinkRow(icon: "stethoscope",
                            title: L10n.t("doctor.title"),
                            hint: L10n.t("doctor.settingsHint")) {
                showDiagnostics = true
            }

            // Replay the first-launch cinema, HERE and NOW (see
            // showCinematicReplay above) — its own Amt wording; the
            // cinema's a11y sentence doubles as the honest hint.
            SettingsLinkRow(icon: "movieclapper.fill",
                            title: L10n.t("settings.kinoReplay"),
                            hint: L10n.t("cinematic.a11y")) {
                Haptics.shared.tap()
                showCinematicReplay = true
            }
        }
        .nightCard(grain: false)
    }

    // W8B Settings-IA: the danger zone is serious, not loud — no red border
    // shouting at the whole card. Two calm rows in the standard icon column;
    // red is reserved for the one truly irreversible glyph, and the dissolve
    // dialog offers the backup sheet BEFORE the point of no return.
    private var dangerCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(12)) {
            SectionHeader(title: L10n.t("settings.dangerZone"),
                          systemImage: "exclamationmark.triangle.fill")

            Button {
                confirmLeave = true
            } label: {
                dangerRow(icon: "rectangle.portrait.and.arrow.right",
                          iconTint: Nacht.sekundaer,
                          title: L10n.t("settings.leaveDevice"),
                          hint: L10n.t("settings.leaveDeviceHint"))
            }
            .buttonStyle(.plain)
            .confirmationDialog(L10n.t("settings.leaveDevice"), isPresented: $confirmLeave, titleVisibility: .visible) {
                Button(L10n.t("settings.leaveDevice"), role: .destructive) {
                    appState.leaveDevice()
                }
                Button(L10n.t("common.cancel"), role: .cancel) {}
            }

            Divider().overlay(Nacht.naht)

            Button {
                confirmDissolve = true
            } label: {
                // Energy red — the one truly irreversible glyph on night.
                dangerRow(icon: "heart.slash.fill",
                          iconTint: Theme.energyRed,
                          title: L10n.t("settings.unpair"),
                          hint: L10n.t("settings.danger.unpairHint"))
            }
            .buttonStyle(.plain)
            .confirmationDialog(L10n.t("settings.unpairConfirm"), isPresented: $confirmDissolve, titleVisibility: .visible) {
                Button(L10n.t("settings.exportFirst")) {
                    showICloudSheet = true
                }
                Button(L10n.t("settings.unpair"), role: .destructive) {
                    Task { await appState.dissolveCouple() }
                }
                Button(L10n.t("common.cancel"), role: .cancel) {}
            }

            Text(L10n.t("settings.danger.footnote"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Nacht.tertiaer)
        }
        .nightCard(grain: false)
    }

    /// A danger-zone row in the shared Settings rhythm: icon column, plain
    /// title, honest hint — seriousness comes from the words, not from color.
    private func dangerRow(icon: String, iconTint: Color, title: String, hint: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LayoutMetrics.s(12)) {
            Image(systemName: icon)
                .font(.system(.body, design: .rounded))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconTint)
                .frame(width: LayoutMetrics.s(28))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Papier.aufNacht)
                Text(hint)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var aboutCard: some View {
        Button {
            showAbout = true
        } label: {
            HStack {
                Label(L10n.t("settings.about"), systemImage: "heart.text.square.fill")
                    .labelStyle(SettingsRowLabelStyle())
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .foregroundStyle(Nacht.tertiaer)
            }
            .nightCard(grain: false)
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func saveCoupleName() {
        guard let api = appState.api else { return }
        let trimmed = coupleName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != appState.couple?.name else { return }
        Task {
            do {
                let couple = try await api.updateCouple(name: trimmed)
                appState.couple = couple
                Haptics.shared.success()
            } catch {
                appState.handleAPIError(error)
            }
        }
    }

    private func saveAnniversary(_ date: Date) {
        guard let api = appState.api else { return }
        let c = SharedDates.calendar.dateComponents([.year, .month, .day], from: date)
        let key = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        guard key != appState.couple?.anniversary else { return }
        hasAnniversary = true
        Task {
            do {
                let couple = try await api.updateCouple(anniversary: key)
                appState.couple = couple
                appState.updateWidgetSnapshot()
                Haptics.shared.success()
            } catch {
                appState.handleAPIError(error)
            }
        }
    }
}

// MARK: - Profile edit

struct ProfileEditSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var petName = ""
    @State private var avatar = Theme.avatarEmojis[0]
    @State private var colorHex = Theme.memberColors[0]
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showBlobs: false)
                ScrollView {
                    VStack(alignment: .leading, spacing: LayoutMetrics.s(16)) {
                        HStack(spacing: LayoutMetrics.s(14)) {
                            EmojiAvatarView(emoji: avatar, colorHex: colorHex, size: LayoutMetrics.s(64))
                            TextField(L10n.t("pairing.yourName"), text: $name)
                                .textFieldStyle(DreamyFieldStyle())
                        }
                        TextField(L10n.t("personalization.petName"), text: $petName)
                            .textFieldStyle(DreamyFieldStyle())
                        Text(L10n.t("personalization.petName.hint"))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                        Text(L10n.t("pairing.avatar"))
                            .font(.system(.footnote, design: .rounded).weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                        EmojiPickerGrid(emojis: Theme.avatarEmojis, selection: $avatar)
                        Text(L10n.t("pairing.color"))
                            .font(.system(.footnote, design: .rounded).weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                        MemberColorPicker(selection: $colorHex)

                        Button {
                            Task { await save() }
                        } label: {
                            if busy { BusySpinner() } else { Text(L10n.t("common.save")) }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(LayoutMetrics.s(20))
                }
            }
            .navigationTitle(L10n.t("settings.profile"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                }
            }
        }
        .onAppear {
            name = appState.me?.name ?? ""
            petName = appState.me?.petName ?? ""
            avatar = appState.me?.avatar ?? Theme.avatarEmojis[0]
            colorHex = appState.me?.color.replacingOccurrences(of: "#", with: "") ?? Theme.memberColors[0]
        }
    }

    private func save() async {
        guard let api = appState.api else { return }
        let cleanedPetName = petName.trimmingCharacters(in: .whitespacesAndNewlines)
        busy = true
        defer { busy = false }
        do {
            _ = try await api.updateMe(name: name.trimmingCharacters(in: .whitespaces),
                                       avatar: avatar, color: "#" + colorHex,
                                       petName: .some(cleanedPetName.isEmpty ? nil : cleanedPetName))
            await appState.refreshCouple()
            appState.updateWidgetSnapshot()
            Haptics.shared.success()
            dismiss()
        } catch {
            appState.handleAPIError(error)
        }
    }
}

// MARK: - Pairing code & QR (re-show after pairing)

/// Shows the couple code + pairing QR again — e.g. to pair a new device or
/// when the partner needs the code once more. Mirrors WaitingForPartnerCard.
struct PairingCodeSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint

    @State private var copied = false

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showBlobs: false)
                ScrollView {
                    VStack(spacing: LayoutMetrics.s(16)) {
                        Image(systemName: "heart.circle.fill")
                            .font(.system(.largeTitle).weight(.medium))
                            .imageScale(.large)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(coupleTint.blend)
                            .accessibilityHidden(true)
                        Text(L10n.t("pairing.yourCode"))
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                            .foregroundStyle(Theme.textPrimary)

                        if let code = appState.couple?.code {
                            Text(code.map(String.init).joined(separator: " "))
                                .font(.system(.largeTitle, design: .monospaced).weight(.heavy))
                                .foregroundStyle(Theme.gold)
                                .padding(.vertical, LayoutMetrics.s(10))
                                .padding(.horizontal, LayoutMetrics.s(18))
                                .background(
                                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                        .fill(Color.black.opacity(0.3))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                                .strokeBorder(Theme.gold.opacity(0.4), lineWidth: Theme.hairlineWidth)
                                        )
                                )
                                // VoiceOver spells the code character by character (P2-9).
                                .accessibilityLabel(L10n.t("pairing.yourCodeA11y",
                                                           ["code": code.map(String.init).joined(separator: ", ")]))

                            HStack(spacing: LayoutMetrics.s(10)) {
                                Button {
                                    UIPasteboard.general.string = code
                                    copied = true
                                    Haptics.shared.success()
                                    Task {
                                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                                        copied = false
                                    }
                                } label: {
                                    Label(L10n.t(copied ? "common.copied" : "common.copy"),
                                          systemImage: copied ? "checkmark" : "doc.on.doc")
                                }
                                .buttonStyle(SecondaryButtonStyle())

                                ShareLink(item: shareText(code: code)) {
                                    Label(L10n.t("common.share"), systemImage: "square.and.arrow.up")
                                }
                                .buttonStyle(SecondaryButtonStyle())
                                .accessibilityHint(L10n.t("pairing.shareHintA11y"))
                            }

                            if let server = appState.servers.activeProfile?.urlString,
                               let qr = QRGenerator.image(for: PairQRPayload.encode(server: server, code: code)) {
                                VStack(spacing: 6) {
                                    Image(uiImage: qr)
                                        .resizable()
                                        .interpolation(.none)
                                        .scaledToFit()
                                        .frame(width: LayoutMetrics.s(200), height: LayoutMetrics.s(200))
                                        .padding(10)
                                        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(.white))
                                        .accessibilityLabel(L10n.t("pairing.qrImageA11y"))
                                    Text(L10n.t("pairing.qrHint"))
                                        .font(.system(.caption2, design: .rounded))
                                        .foregroundStyle(Theme.textTertiary)
                                        .multilineTextAlignment(.center)
                                }
                            }
                        }

                        Text(L10n.t("settings.pairingHint"))
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(LayoutMetrics.s(20))
                }
            }
            .navigationTitle(L10n.t("settings.pairingShow"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("common.done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func shareText(code: String) -> String {
        let server = appState.servers.activeProfile?.urlString ?? ""
        return L10n.t("pairing.shareInvite", ["server": server, "code": code])
    }
}

// MARK: - Sound volume row

/// One per-category volume slider — releasing the thumb plays a preview at
/// the new level so tuning is immediate.
private struct SoundVolumeRow: View {
    let category: SoundEngine.Category
    @State private var volume: Double
    @Environment(\.coupleTint) private var coupleTint

    init(category: SoundEngine.Category) {
        self.category = category
        _volume = State(initialValue: SoundEngine.volume(for: category))
    }

    var body: some View {
        HStack(spacing: LayoutMetrics.s(10)) {
            Image(systemName: category.icon)
                .font(.system(.caption2, design: .rounded))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Nacht.sekundaer)
                .frame(width: LayoutMetrics.s(20))
            Text(L10n.t(category.titleKey))
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(Nacht.sekundaer)
                .frame(width: LayoutMetrics.s(66), alignment: .leading)
            Slider(value: $volume, in: 0...1) { editing in
                if !editing {
                    SoundEngine.setVolume(volume, for: category)
                    SoundEngine.shared.play(category.previewSound)
                }
            }
            .tint(coupleTint.blend)
        }
    }
}

// MARK: - About

struct AboutSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint
    @State private var serverVersion: String?
    @State private var secretProgress = SecretGestureProgress()
    @State private var showSecretCredits = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "–"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Fix4 Befund 7: Werkzeugräume sind still — the About
                // sheet joins every other Amt sheet with a static room
                // (the dampened 0.45 dust was the last animated one).
                DreamyBackground(showBlobs: false)
                ScrollView {
                    VStack(spacing: LayoutMetrics.s(18)) {
                        // The About "logo" is the actual app icon — the same
                        // night-gradient glass heart the icon renderer paints,
                        // drawn live in the user's current variant — not a
                        // 72 pt emoji (commandment 1).
                        // Nachtpostamt-Umfärbung (Gesamtbild-Eval S1): the
                        // icon halo is lamp light, not the couple blend —
                        // a pink glow around the night icon was the last
                        // pre-recolor leftover on this sheet.
                        IconVariantPreview(variant: AppIconKit.variant(AppIconKit.currentId),
                                           size: LayoutMetrics.s(96))
                            .shadow(color: Licht.lampengold.opacity(0.45), radius: 24)
                            .accessibilityHidden(true)
                            .onLongPressGesture(minimumDuration: 10) {
                                unlockSecretCredits()
                            }
                        // The About wordmark writes in GOLDEN INK (its own
                        // style — brandTitle would fall back to the couple
                        // tint, which is exactly the cream/pink the eval
                        // flagged on about-de.png).
                        Text("SoooDreamy")
                            .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                            .foregroundStyle(Licht.lampengold)

                        // The Impressum sheet of the orderly secretary —
                        // facts on the night carton, the credit in lamplight.
                        VStack(spacing: LayoutMetrics.s(10)) {
                            aboutRow(L10n.t("settings.version"), value: appVersion)
                            aboutRow(L10n.t("settings.build"), value: buildNumber)
                            aboutRow(
                                L10n.t("settings.serverVersionLabel"),
                                value: serverVersion ?? L10n.t("settings.serverUnavailable")
                            )
                            Divider().overlay(Nacht.naht)
                            Text(L10n.t("settings.credit"))
                                .font(.system(.headline, design: .rounded).weight(.bold))
                                .foregroundStyle(Licht.lampengold)
                                .frame(maxWidth: .infinity)
                                .accessibilityAddTraits(.isHeader)
                        }
                        // The office is grain-free (§4.5) — About included.
                        .nightCard(grain: false)

                        // W8 (Linse 12 #6): the app's story as a narrated
                        // timeline — PATCHNOTES finally live inside the app.
                        NavigationLink {
                            VersionHistoryView()
                        } label: {
                            HStack(spacing: LayoutMetrics.s(12)) {
                                Image(systemName: "book.pages.fill")
                                    .font(.system(.body, design: .rounded))
                                    .foregroundStyle(coupleTint.blend)
                                    .frame(width: LayoutMetrics.s(34))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L10n.t("journey.title"))
                                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                        .foregroundStyle(Papier.aufNacht)
                                    Text(L10n.t("journey.settingsHint"))
                                        .font(.system(.caption2, design: .rounded))
                                        .foregroundStyle(Nacht.tertiaer)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(.caption, design: .rounded).weight(.bold))
                                    .foregroundStyle(Nacht.tertiaer)
                            }
                        }
                        .buttonStyle(.plain)
                        .nightCard(grain: false)

                        // Sound credits: generated from sound_credits.json —
                        // CC-BY attribution lives here, CC0 thanks included.
                        NavigationLink {
                            SoundCreditsView()
                        } label: {
                            HStack(spacing: LayoutMetrics.s(12)) {
                                Image(systemName: "music.note.list")
                                    .font(.system(.body, design: .rounded))
                                    .foregroundStyle(coupleTint.blend)
                                    .frame(width: LayoutMetrics.s(34))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L10n.t("settings.soundCredits.title"))
                                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                        .foregroundStyle(Papier.aufNacht)
                                    Text(L10n.t("settings.soundCredits.hint"))
                                        .font(.system(.caption2, design: .rounded))
                                        .foregroundStyle(Nacht.tertiaer)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(.caption, design: .rounded).weight(.bold))
                                    .foregroundStyle(Nacht.tertiaer)
                            }
                        }
                        .buttonStyle(.plain)
                        .nightCard(grain: false)

                        // The origin story instead of a template footer
                        // (FXC-4 #12): three honest sentences about where
                        // the app comes from — the credit above stays.
                        Text(L10n.t("settings.about.story"))
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(LayoutMetrics.s(24))
                    .contentShape(Rectangle())
                    .simultaneousGesture(secretSwipeGesture)
                }
                if showSecretCredits {
                    ZStack {
                        FloatingHeartsView(emojis: ["💜", "✨", "💞", "⭐️"], count: 24)
                        // Conscious glass exception: the secret credit is a
                        // floating celebration overlay, not lying content.
                        Text(L10n.t("settings.credit"))
                            .brandTitle(.system(.title, design: .rounded).weight(.heavy))
                            .padding(LayoutMetrics.s(20))
                            .glassCard()
                    }
                    .allowsHitTesting(false)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .task {
                guard let api = appState.api else { return }
                serverVersion = try? await api.health().version
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("common.done")) { dismiss() }
                }
            }
        }
    }

    private func aboutRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Nacht.sekundaer)
            Spacer()
            Text(value)
                .foregroundStyle(Papier.aufNacht)
                .fontWeight(.semibold)
        }
        .font(.system(.subheadline, design: .rounded))
        .accessibilityElement(children: .combine)
    }

    private var secretSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 34)
            .onEnded { value in
                let horizontal = abs(value.translation.width) > abs(value.translation.height)
                let swipe: SecretSwipe
                if horizontal {
                    swipe = value.translation.width > 0 ? .right : .left
                } else {
                    swipe = value.translation.height > 0 ? .down : .up
                }
                if secretProgress.consume(swipe) {
                    unlockSecretCredits()
                }
            }
    }

    private func unlockSecretCredits() {
        Haptics.shared.success()
        SoundEngine.shared.play(.tada)
        withAnimation(Theme.Motion.arrive) { showSecretCredits = true }
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            withAnimation(Theme.Motion.settle) { showSecretCredits = false }
        }
    }
}

// MARK: - Shared row (v10 settings cleanup)

/// The standard Settings navigation row on the night card: tinted icon,
/// title + hint, chevron. Replaces five hand-rolled copies of the same
/// 20-line HStack. Without an explicit tint the icon carries the couple's
/// raw blend (non-text accent on night) — navigation is the accent,
/// toggles stay quiet.
struct SettingsLinkRow: View {
    let icon: String
    let title: String
    let hint: String
    var tint: Color? = nil
    let action: () -> Void

    @Environment(\.coupleTint) private var coupleTint

    var body: some View {
        Button(action: action) {
            HStack(spacing: LayoutMetrics.s(12)) {
                Image(systemName: icon)
                    .font(.system(.title3, design: .rounded))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint ?? coupleTint.blend)
                    .frame(width: LayoutMetrics.s(34))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Papier.aufNacht)
                    Text(hint)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Nacht.tertiaer)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .foregroundStyle(Nacht.tertiaer)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Uniform icon column for Settings toggle/menu rows on the night card: a
/// quiet hierarchical symbol in a fixed-width slot so titles align across
/// every card — the control itself (toggle knob, menu value) carries the
/// accent, not the icon.
struct SettingsRowLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: LayoutMetrics.s(12)) {
            configuration.icon
                .font(.system(.body, design: .rounded))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Nacht.sekundaer)
                .frame(width: LayoutMetrics.s(28))
            configuration.title
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Papier.aufNacht)
        }
    }
}

// MARK: - Scope badge (W8 Settings-IA)

/// „gilt für euch beide" vs. „nur du" — some settings sync to the partner
/// (couple name, palette, anniversary), others stay on this device (sounds,
/// haptics, alerts). The badge makes that visible instead of surprising.
struct ScopeBadge: View {
    enum Scope {
        case couple, device
    }

    let scope: Scope

    @Environment(\.coupleTint) private var coupleTint

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: scope == .couple ? "person.2.fill" : "person.fill")
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .symbolRenderingMode(.hierarchical)
            Text(L10n.t(scope == .couple ? "settings.scope.couple" : "settings.scope.device"))
                .font(.system(.caption2, design: .rounded).weight(.semibold))
        }
        .foregroundStyle(scope == .couple ? Licht.lampengold : Nacht.tertiaer)
        .padding(.horizontal, LayoutMetrics.s(8))
        .padding(.vertical, 3)
        .background(
            Capsule().fill(scope == .couple ? Licht.lampengold.opacity(0.12) : Papier.nachtInnenFill)
        )
        .accessibilityElement(children: .combine)
    }
}
