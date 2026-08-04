import SwiftUI
import WidgetKit

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var showProfileEdit = false
    @State private var showServers = false
    @State private var showAbout = false
    @State private var showPairingCode = false
    @State private var confirmDissolve = false
    @State private var confirmLeave = false

    @State private var soundsOn = SoundEngine.enabled
    @State private var hapticsOn = Haptics.enabled
    @State private var reminderOn = ReminderManager.isEnabled
    @State private var streakGuardOn = ReminderManager.isStreakGuardEnabled
    @State private var couponReminderOn = CouponReminder.isEnabled
    @State private var appLockOn = AppLock.isEnabled
    @State private var pulseOn = CouplePulseController.isEnabled
    @State private var reminderTime: Date = {
        let t = ReminderManager.time
        return Calendar.current.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: Date()) ?? Date()
    }()

    @State private var alertsOn = NotificationPrefs.enabled
    @State private var alertSound = NotificationPrefs.globalSound
    @State private var alertKinds: [CoupleAlertKind: Bool] = Dictionary(
        uniqueKeysWithValues: CoupleAlertKind.allCases.map { ($0, NotificationPrefs.isEnabled($0)) })

    @State private var widgetPrefs = SharedStore.readPrefs()

    @State private var coupleName = ""
    @State private var anniversary = Date()
    @State private var hasAnniversary = false

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                ScrollView {
                    VStack(spacing: LayoutMetrics.s(16)) {
                        profileCard
                        coupleCard
                        serverCard
                        appCard
                        notificationsCard
                        dangerCard
                        aboutCard
                    }
                    .padding(LayoutMetrics.s(16))
                }
            }
            .navigationTitle(L10n.t("settings.title"))
        }
        .sheet(isPresented: $showProfileEdit) { ProfileEditSheet() }
        .sheet(isPresented: $showServers) { ServerListSheet() }
        .sheet(isPresented: $showAbout) { AboutSheet() }
        .sheet(isPresented: $showPairingCode) { PairingCodeSheet() }
        .onAppear { syncFromState() }
        .onChange(of: appState.couple) { syncFromState() }
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
                        .foregroundStyle(Theme.textPrimary)
                    Text(L10n.t("settings.profile"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.scaled(13, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .glassCard(padding: 14)
        }
        .buttonStyle(.plain)
    }

    private var coupleCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(14)) {
            SectionHeader(title: L10n.t("settings.couple"))

            TextField(L10n.t("settings.coupleName"), text: $coupleName)
                .textFieldStyle(DreamyFieldStyle())
                .submitLabel(.done)
                .onSubmit { saveCoupleName() }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t("settings.anniversary"))
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                DatePicker(L10n.t("settings.anniversaryHint"),
                           selection: $anniversary,
                           in: ...Date(),
                           displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .colorScheme(.dark)
                    .onChange(of: anniversary) { _, newValue in
                        saveAnniversary(newValue)
                    }
                if !hasAnniversary {
                    Text(L10n.t("home.sinceHint"))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
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
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .glassCard(padding: 16)
    }

    private var serverCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(12)) {
            SectionHeader(title: L10n.t("settings.connection"))

            if let profile = appState.servers.activeProfile {
                HStack(spacing: LayoutMetrics.s(10)) {
                    Image(systemName: "server.rack")
                        .foregroundStyle(Theme.pink)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.name)
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(profile.urlString)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
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
        }
        .glassCard(padding: 16)
    }

    private var appCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(14)) {
            SectionHeader(title: "App")

            // Language
            HStack {
                Label(L10n.t("settings.language"), systemImage: "globe")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Menu {
                    ForEach(AppLanguage.allCases) { lang in
                        Button {
                            L10n.language = lang
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
                        .foregroundStyle(Theme.pink)
                }
            }

            Toggle(isOn: $soundsOn) {
                Label(L10n.t("settings.sounds"), systemImage: "speaker.wave.2.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.pink)
            .onChange(of: soundsOn) { _, on in
                SoundEngine.enabled = on
                if on { SoundEngine.shared.play(.chime) }
            }

            Toggle(isOn: $hapticsOn) {
                Label(L10n.t("settings.haptics"), systemImage: "iphone.radiowaves.left.and.right")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.pink)
            .onChange(of: hapticsOn) { _, on in
                Haptics.enabled = on
                if on { Haptics.shared.play(.heartbeat) }
            }

            if AppLock.isAvailable {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: $appLockOn) {
                        Label(L10n.t("settings.appLock"), systemImage: "faceid")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .tint(Theme.pink)
                    .onChange(of: appLockOn) { _, on in
                        AppLock.isEnabled = on
                        Haptics.shared.tap()
                    }
                    Text(L10n.t("settings.appLockHint"))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            // Couple Pulse Live Activity (lock screen + Dynamic Island)
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $pulseOn) {
                    Label(L10n.t("settings.pulse"), systemImage: "heart.text.square.fill")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .tint(Theme.pink)
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
                    .foregroundStyle(Theme.textTertiary)
            }

            VStack(alignment: .leading, spacing: LayoutMetrics.s(8)) {
                Label(L10n.t("settings.widgets"), systemImage: "square.grid.2x2.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(L10n.t("settings.widgetsHint"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)

                Text(L10n.t("settings.widgetBackground"))
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, LayoutMetrics.s(4))
                widgetStyleRow

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: $widgetPrefs.usePhotoChrome) {
                        Label(L10n.t("settings.widgetPhotoChrome"), systemImage: "photo.on.rectangle.angled")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .tint(Theme.pink)
                    Text(L10n.t("settings.widgetPhotoChromeHint"))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .onChange(of: widgetPrefs) { _, prefs in
                SharedStore.writePrefs(prefs)
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
        .glassCard(padding: 16)
    }

    // MARK: Widget background picker

    /// Preview swatches for the widget background styles.
    /// Keep the hexes in sync with `WTheme.backgroundColors(named:)`
    /// in Widgets/WidgetTheme.swift (the widget target isn't linked here).
    private static let widgetStyles: [(name: String, hexes: [String])] = [
        ("night", ["17062A", "2B0F4A"]),
        ("sunset", ["2B0B3A", "8A2E4F", "E8785A"]),
        ("ocean", ["04203F", "0E4D64", "16697A"]),
        ("blush", ["3B0F2A", "7C2949", "C95D7C"]),
        ("mono", ["0D0D12", "232331"]),
        ("photo", []),
    ]

    private var widgetStyleRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LayoutMetrics.s(12)) {
                ForEach(Self.widgetStyles, id: \.name) { style in
                    widgetStyleSwatch(style.name, hexes: style.hexes)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func widgetStyleSwatch(_ name: String, hexes: [String]) -> some View {
        let selected = widgetPrefs.background == name
        return Button {
            widgetPrefs.background = name
            Haptics.shared.tap()
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    if hexes.isEmpty {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(colors: [Theme.indigo.opacity(0.55), Theme.purple.opacity(0.55)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        Image(systemName: "photo.fill")
                            .font(.scaled(14))
                            .foregroundStyle(.white.opacity(0.85))
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(colors: hexes.map { Color(hex: $0) },
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                }
                .frame(width: LayoutMetrics.s(46), height: LayoutMetrics.s(46))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(selected ? Theme.pink : Color.white.opacity(0.15),
                                      lineWidth: selected ? 2.5 : 1)
                )
                .shadow(color: selected ? Theme.pink.opacity(0.5) : .clear, radius: 6)
                Text(L10n.t("settings.widgetBg.\(name)"))
                    .font(.system(.caption2, design: .rounded).weight(selected ? .bold : .regular))
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var notificationsCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(14)) {
            SectionHeader(title: L10n.t("notif.section"))

            // Master switch for couple alerts (local, WebSocket-driven)
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $alertsOn) {
                    Label(L10n.t("notif.master"), systemImage: "bell.and.waves.left.and.right")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .tint(Theme.pink)
                .onChange(of: alertsOn) { _, on in
                    NotificationPrefs.enabled = on
                    if on {
                        Task {
                            let ok = await CoupleNotify.requestAuthorizationIfNeeded()
                            if !ok {
                                alertsOn = false
                                NotificationPrefs.enabled = false
                            }
                        }
                    }
                }
                Text(L10n.t("notif.masterHint"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }

            if alertsOn {
                // Sound picker (horizontal chips)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("notif.sound"))
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: LayoutMetrics.s(8)) {
                            ForEach(NotificationSound.allCases) { sound in
                                soundChip(sound)
                            }
                        }
                    }
                }

                // Per-event toggles
                ForEach(CoupleAlertKind.allCases) { kind in
                    Toggle(isOn: alertBinding(kind)) {
                        Label(L10n.t(kind.titleKey), systemImage: kind.icon)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .tint(Theme.pink)
                }
            }

            Divider().overlay(Color.white.opacity(0.1))

            // Daily reminder
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $reminderOn) {
                    Label(L10n.t("settings.reminder"), systemImage: "bell.badge.fill")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .tint(Theme.pink)
                .onChange(of: reminderOn) { _, on in
                    Task {
                        let ok = await ReminderManager.setEnabled(on)
                        if !ok { reminderOn = false }
                    }
                }
                Text(L10n.t("settings.reminderHint"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                if reminderOn {
                    DatePicker(L10n.t("settings.reminderTime"),
                               selection: $reminderTime,
                               displayedComponents: .hourAndMinute)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .tint(Theme.pink)
                        .onChange(of: reminderTime) { _, newValue in
                            let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                            Task {
                                await ReminderManager.setTime(hour: comps.hour ?? 20,
                                                              minute: comps.minute ?? 0)
                            }
                        }
                }
            }

            // Streak guard (second, "streak at risk" evening nudge)
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $streakGuardOn) {
                    Label(L10n.t("settings.streakGuard"), systemImage: "flame.fill")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .tint(Theme.pink)
                .onChange(of: streakGuardOn) { _, on in
                    Task {
                        let ok = await ReminderManager.setStreakGuardEnabled(on, entry: appState.dailyEntry)
                        if !ok { streakGuardOn = false }
                    }
                }
                Text(L10n.t("settings.streakGuardHint"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }

            // Coupon expiry reminder ("expiring soon" nudge)
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $couponReminderOn) {
                    Label(L10n.t("settings.couponReminder"), systemImage: "ticket.fill")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
                .tint(Theme.pink)
                .onChange(of: couponReminderOn) { _, on in
                    Task {
                        var coupons: [Coupon] = []
                        if on, let api = appState.api {
                            coupons = (try? await api.coupons()) ?? []
                        }
                        let ok = await CouponReminder.setEnabled(on, coupons: coupons,
                                                                 myMemberId: appState.memberId)
                        if !ok { couponReminderOn = false }
                    }
                }
                Text(L10n.t("settings.couponReminderHint"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .glassCard(padding: 16)
    }

    private func soundChip(_ sound: NotificationSound) -> some View {
        let selected = alertSound == sound
        return Button {
            alertSound = sound
            NotificationPrefs.globalSound = sound
            Haptics.shared.tap()
            sound.preview()
            Task { await ReminderManager.rescheduleIfNeeded() }
        } label: {
            HStack(spacing: LayoutMetrics.s(5)) {
                Text(sound.emoji)
                    .font(.scaled(13))
                Text(sound.displayName)
                    .font(.system(.caption, design: .rounded).weight(.semibold))
            }
            .padding(.horizontal, LayoutMetrics.s(12))
            .padding(.vertical, LayoutMetrics.s(8))
            .background(Capsule().fill(selected ? Theme.pink.opacity(0.32) : Color.white.opacity(0.06)))
            .overlay(Capsule().strokeBorder(selected ? Theme.pink : Color.white.opacity(0.12), lineWidth: 1))
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private func alertBinding(_ kind: CoupleAlertKind) -> Binding<Bool> {
        Binding(
            get: { alertKinds[kind] ?? true },
            set: { on in
                alertKinds[kind] = on
                NotificationPrefs.setEnabled(on, for: kind)
            }
        )
    }

    private var dangerCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(12)) {
            Button {
                confirmLeave = true
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Label(L10n.t("settings.leaveDevice"), systemImage: "rectangle.portrait.and.arrow.right")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.gold)
                    Text(L10n.t("settings.leaveDeviceHint"))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .buttonStyle(.plain)
            .confirmationDialog(L10n.t("settings.leaveDevice"), isPresented: $confirmLeave, titleVisibility: .visible) {
                Button(L10n.t("settings.leaveDevice"), role: .destructive) {
                    appState.leaveDevice()
                }
                Button(L10n.t("common.cancel"), role: .cancel) {}
            }

            Divider().overlay(Color.white.opacity(0.1))

            Button {
                confirmDissolve = true
            } label: {
                Label(L10n.t("settings.unpair"), systemImage: "heart.slash.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Color(hex: "F87171"))
            }
            .buttonStyle(.plain)
            .confirmationDialog(L10n.t("settings.unpairConfirm"), isPresented: $confirmDissolve, titleVisibility: .visible) {
                Button(L10n.t("settings.unpair"), role: .destructive) {
                    Task { await appState.dissolveCouple() }
                }
                Button(L10n.t("common.cancel"), role: .cancel) {}
            }
        }
        .glassCard(padding: 16)
    }

    private var aboutCard: some View {
        Button {
            showAbout = true
        } label: {
            HStack {
                Label(L10n.t("settings.about"), systemImage: "heart.text.square.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.scaled(13, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .glassCard(padding: 16)
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
    @State private var avatar = Theme.avatarEmojis[0]
    @State private var colorHex = Theme.memberColors[0]
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                ScrollView {
                    VStack(alignment: .leading, spacing: LayoutMetrics.s(16)) {
                        HStack(spacing: LayoutMetrics.s(14)) {
                            EmojiAvatarView(emoji: avatar, colorHex: colorHex, size: LayoutMetrics.s(64))
                            TextField(L10n.t("pairing.yourName"), text: $name)
                                .textFieldStyle(DreamyFieldStyle())
                        }
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
                            if busy { ProgressView().tint(.white) } else { Text(L10n.t("common.save")) }
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
            avatar = appState.me?.avatar ?? Theme.avatarEmojis[0]
            colorHex = appState.me?.color.replacingOccurrences(of: "#", with: "") ?? Theme.memberColors[0]
        }
    }

    private func save() async {
        guard let api = appState.api else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await api.updateMe(name: name.trimmingCharacters(in: .whitespaces),
                                       avatar: avatar, color: "#" + colorHex)
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

    @State private var copied = false

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                ScrollView {
                    VStack(spacing: LayoutMetrics.s(16)) {
                        Text("💞")
                            .font(.scaled(48))
                        Text(L10n.t("pairing.yourCode"))
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                            .foregroundStyle(Theme.textPrimary)

                        if let code = appState.couple?.code {
                            Text(code.map(String.init).joined(separator: " "))
                                .font(.scaled(34, weight: .heavy, design: .monospaced))
                                .foregroundStyle(Theme.gold)
                                .padding(.vertical, LayoutMetrics.s(10))
                                .padding(.horizontal, LayoutMetrics.s(18))
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(Color.black.opacity(0.3))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .strokeBorder(Theme.gold.opacity(0.4), lineWidth: 1)
                                        )
                                )

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
                                        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
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
        return L10n.isGerman
            ? "Komm zu mir auf SoooDreamy! 💜\nServer: \(server)\nCode: \(code)"
            : "Join me on SoooDreamy! 💜\nServer: \(server)\nCode: \(code)"
    }
}

// MARK: - About

struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground()
                VStack(spacing: LayoutMetrics.s(16)) {
                    Spacer()
                    Text("💜")
                        .font(.scaled(72))
                        .shadow(color: Theme.pink.opacity(0.7), radius: 24)
                    Text("SoooDreamy")
                        .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(L10n.t("settings.version")) \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                    Text(L10n.t("settings.madeWith"))
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, LayoutMetrics.s(40))
                    Spacer()
                    Spacer()
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("common.done")) { dismiss() }
                }
            }
        }
    }
}
