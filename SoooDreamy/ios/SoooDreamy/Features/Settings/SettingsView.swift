import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    @State private var showProfileEdit = false
    @State private var showServers = false
    @State private var showAbout = false
    @State private var confirmDissolve = false
    @State private var confirmLeave = false

    @State private var soundsOn = SoundEngine.enabled
    @State private var hapticsOn = Haptics.enabled
    @State private var reminderOn = ReminderManager.isEnabled
    @State private var appLockOn = AppLock.isEnabled

    @State private var coupleName = ""
    @State private var anniversary = Date()
    @State private var hasAnniversary = false

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                ScrollView {
                    VStack(spacing: 16) {
                        profileCard
                        coupleCard
                        serverCard
                        appCard
                        dangerCard
                        aboutCard
                    }
                    .padding(16)
                }
            }
            .navigationTitle(L10n.t("settings.title"))
        }
        .sheet(isPresented: $showProfileEdit) { ProfileEditSheet() }
        .sheet(isPresented: $showServers) { ServerListSheet() }
        .sheet(isPresented: $showAbout) { AboutSheet() }
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
            HStack(spacing: 14) {
                EmojiAvatarView(emoji: appState.me?.avatar, colorHex: appState.me?.color, size: 56)
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
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .glassCard(padding: 14)
        }
        .buttonStyle(.plain)
    }

    private var coupleCard: some View {
        VStack(alignment: .leading, spacing: 14) {
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
        }
        .glassCard(padding: 16)
    }

    private var serverCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: L10n.t("settings.connection"))

            if let profile = appState.servers.activeProfile {
                HStack(spacing: 10) {
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
        VStack(alignment: .leading, spacing: 14) {
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
            }

            VStack(alignment: .leading, spacing: 4) {
                Label(L10n.t("settings.widgets"), systemImage: "square.grid.2x2.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(L10n.t("settings.widgetsHint"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .glassCard(padding: 16)
    }

    private var dangerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                    .font(.system(size: 13, weight: .bold))
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
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 14) {
                            EmojiAvatarView(emoji: avatar, colorHex: colorHex, size: 64)
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
                    .padding(20)
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

// MARK: - About

struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground()
                VStack(spacing: 16) {
                    Spacer()
                    Text("💜")
                        .font(.system(size: 72))
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
                        .padding(.horizontal, 40)
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
