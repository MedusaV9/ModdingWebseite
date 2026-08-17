import SwiftUI

// MARK: - Live Activity sheet
// Configure style + content of both Live Activities (countdown & couple
// pulse): theme, live ticker, and which elements are visible. The config is
// stored in the app group and pushed INTO running activities immediately
// (it travels inside the ContentState — no restart needed).

struct LiveActivitySheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint

    @State private var config = SharedStore.readLiveActivityConfig()
    @State private var pulseRunning = CouplePulseController.isRunning

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showBlobs: false)
                // Native grouped Form (system semantics, spacing, focus
                // order); the rows sit as night cartons over the
                // DreamyBackground — same content, same order.
                Form {
                    previewSection
                    themeSection
                    elementsSection
                    pulseSection
                    hintSection
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .contentColumn(.reading)
            }
            .navigationTitle(L10n.t("la.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("common.done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: config) { _, newValue in
            SharedStore.writeLiveActivityConfig(newValue)
            CouplePulseController.pushConfig()
            CountdownActivityController.pushConfig()
        }
    }

    // MARK: Live preview (lock-screen replica)

    private var palette: WidgetPreviewPalette {
        // renderSpec + live icon id: the preview shows the icon-matching
        // palette the activity will really wear (W7/35-Rest).
        WidgetPreviewPalette(spec: WidgetThemes.renderSpec(id: config.themeId,
                                                           iconId: AppIconKit.currentId))
    }

    private var previewSection: some View {
        Section {
            lockScreenReplica
        } header: {
            Text(L10n.t("la.preview"))
        }
        .listRowBackground(Papier.nachtkarton)
    }

    private var lockScreenReplica: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text("💞")
                    .font(.system(.largeTitle))
                VStack(alignment: .leading, spacing: 2) {
                    // Palette ink instead of hard white: on the light "paper"
                    // theme white read 1.13:1 on the letter-paper ground —
                    // the preview must wear the inks the activity really uses.
                    Text(appState.partnerName)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    if config.liveTimer {
                        Text("12:34:56")
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(palette.heroGradient)
                    } else {
                        Text(L10n.isGerman ? "in 3 Tagen" : "in 3 days")
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                            .foregroundStyle(palette.heroGradient)
                    }
                    HStack(spacing: 8) {
                        if config.showPresence {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Theme.mint)
                                    .frame(width: 7, height: 7)
                                Text(L10n.t("home.online"))
                                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                                    .foregroundStyle(Theme.mint)
                            }
                        }
                        if config.showMood {
                            Text("🥰")
                                .font(.system(.caption))
                        }
                        if config.showTouch {
                            Text("💓")
                                .font(.system(.caption))
                        }
                        if config.showStreak {
                            Text("🔥 12")
                                .font(.system(.caption2, design: .rounded).weight(.bold))
                                .foregroundStyle(palette.accentSecondary)
                        }
                    }
                }
                Spacer(minLength: 0)
                if config.showDaysTogether {
                    VStack(spacing: 0) {
                        Text("847")
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                            .foregroundStyle(palette.accentSecondary)
                        Text(L10n.isGerman ? "Tage 💜" : "days 💜")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
            if config.showProgress {
                Capsule()
                    .fill(palette.chipFill)
                    .frame(height: 4)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule()
                                .fill(palette.accent)
                                .frame(width: geo.size.width * 0.62)
                        }
                    }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Color(hex: WidgetThemes.renderSpec(id: config.themeId,
                                                         iconId: AppIconKit.currentId)
                        .backgroundHexes.first ?? "17062A").opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: Theme.hairlineWidth)
        )
    }

    // MARK: Theme

    private var themeSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LayoutMetrics.s(10)) {
                    ForEach(WidgetThemes.all) { spec in
                        themeSwatch(spec)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text(L10n.t("la.theme"))
        }
        .listRowBackground(Papier.nachtkarton)
    }

    private func themeSwatch(_ spec: WidgetThemeSpec) -> some View {
        let selected = config.themeId == spec.id
        return Button {
            config.themeId = spec.id
            Haptics.shared.tap()
        } label: {
            VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(LinearGradient(colors: spec.backgroundHexes.map { Color(hex: $0) },
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: LayoutMetrics.s(44), height: LayoutMetrics.s(44))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .strokeBorder(selected ? AnyShapeStyle(coupleTint.blend)
                                                   : AnyShapeStyle(Nacht.naht),
                                          lineWidth: selected ? 2.5 : Theme.hairlineWidth)
                    )
                    .shadow(color: selected ? coupleTint.blend.opacity(0.35) : .clear, radius: 6)
                Text(spec.name(lang: L10n.lang))
                    .font(.system(.caption2, design: .rounded).weight(selected ? .bold : .regular))
                    .foregroundStyle(selected ? Papier.aufNacht : Nacht.sekundaer)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Elements

    private var elementsSection: some View {
        Section {
            elementToggle("la.liveTimer", icon: "timer",
                          binding: $config.liveTimer)
            elementToggle("la.progress", icon: "chart.bar.horizontal.page",
                          binding: $config.showProgress)
            elementToggle("la.presence", icon: "dot.radiowaves.left.and.right",
                          binding: $config.showPresence)
            elementToggle("la.mood", icon: "face.smiling",
                          binding: $config.showMood)
            elementToggle("la.touch", icon: "hand.tap.fill",
                          binding: $config.showTouch)
            elementToggle("la.streak", icon: "flame.fill",
                          binding: $config.showStreak)
            elementToggle("la.days", icon: "heart.circle.fill",
                          binding: $config.showDaysTogether)
        } header: {
            Text(L10n.t("la.elements"))
        }
        .listRowBackground(Papier.nachtkarton)
    }

    private func elementToggle(_ key: String, icon: String,
                               binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            Label(L10n.t(key), systemImage: icon)
                .labelStyle(SettingsRowLabelStyle())
        }
        .tint(coupleTint.blend)
    }

    // MARK: Pulse activity control

    private var pulseSection: some View {
        Section {
            Text(L10n.t("settings.pulseHint"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Nacht.tertiaer)
            Button {
                Haptics.shared.tap()
                if pulseRunning {
                    CouplePulseController.stop()
                    pulseRunning = false
                } else if CouplePulseController.start(from: appState) {
                    pulseRunning = true
                    appState.showToast(L10n.t("settings.pulseStarted"), style: .success)
                } else {
                    appState.showToast(L10n.t("memories.events.liveFailed"), style: .error)
                }
            } label: {
                Label(pulseRunning ? L10n.t("la.stopPulse") : L10n.t("la.startPulse"),
                      systemImage: pulseRunning ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LayoutMetrics.s(10))
                    .background(Capsule().fill(coupleTint.blend.opacity(pulseRunning ? 0.10 : 0.16)))
                    .overlay(Capsule().strokeBorder(coupleTint.blend.opacity(0.6), lineWidth: Theme.hairlineWidth))
                    .foregroundStyle(Papier.aufNacht)
            }
            .buttonStyle(.plain)
        } header: {
            Text(L10n.t("settings.pulse"))
        }
        .listRowBackground(Papier.nachtkarton)
    }

    private var hintSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label(L10n.t("la.countdownHintTitle"), systemImage: "calendar.badge.clock")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Papier.aufNacht)
                Text(L10n.t("la.countdownHint"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
                Text(L10n.t("la.limitHint"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .listRowBackground(Papier.nachtkarton)
    }
}
