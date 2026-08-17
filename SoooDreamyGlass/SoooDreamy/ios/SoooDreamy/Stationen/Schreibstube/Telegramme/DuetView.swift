import SwiftUI

// Haptic duet + live heartbeat: one pattern, two iPhones,
// the same instant — the server schedules a shared start time (server
// clock), ClockSync converts it locally on each phone. Plus a live pad
// that streams heartbeat taps straight onto the partner's 3D heart.

struct DuetSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.dismiss) private var dismiss
    /// AX5: the 3-column preset grid collapses (3 → 2 → 1) before its
    /// labels shatter (rule in `AccessibilityBudget.gridColumns`).
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var selectedPreset: HapticPreset? = HapticPresets.all.first
    @State private var starting = false

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                ScrollView {
                    VStack(alignment: .leading, spacing: LayoutMetrics.s(16)) {
                        duetCard
                        LiveHeartbeatPad()
                    }
                    .padding(LayoutMetrics.s(16))
                }
            }
            .navigationTitle(L10n.t("duet.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.close")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            // Warm up the clock offset before anyone hits start.
            ClockSync.shared.sample(via: appState.socket)
        }
    }

    // MARK: Synchronized duet

    private var duetCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(12)) {
            SectionHeader(title: L10n.t("duet.title"))
            Text(L10n.t("duet.subtitle"))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)

            Text(L10n.t("duet.pickPattern"))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Nacht.tertiaer)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                     count: dynamicTypeSize.gridColumns(regular: 3)),
                      spacing: 10) {
                ForEach(HapticPresets.all) { preset in
                    presetCell(preset)
                }
            }

            Button {
                startDuet()
            } label: {
                if starting {
                    BusySpinner()
                } else {
                    Label(L10n.t("duet.start"), systemImage: "waveform.path.ecg")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(starting || selectedPreset == nil || appState.partner == nil)

            if appState.partner?.online != true {
                Text(L10n.t("duet.hint", ["name": appState.partnerName]))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Licht.glut)
            }
        }
        .nightCard()
    }

    private func presetCell(_ preset: HapticPreset) -> some View {
        Button {
            Haptics.shared.tap()
            selectedPreset = preset
            // Preview locally so picking feels tactile.
            Haptics.shared.play(events: preset.events)
        } label: {
            VStack(spacing: 5) {
                Text(preset.emoji)
                    .font(.system(.title))
                Text(L10n.t(preset.nameKey))
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(Nacht.sekundaer)
                    // AX sizes: the collapsed grid grants full width — the
                    // name wraps at natural size instead of shrinking.
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LayoutMetrics.s(12))
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(selectedPreset?.id == preset.id
                        ? coupleTint.blend.opacity(0.22) : Papier.nachtInnenFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .strokeBorder(selectedPreset?.id == preset.id
                                ? coupleTint.blend : Nacht.naht, lineWidth: 1.5)))
        }
        .buttonStyle(.plain)
    }

    private func startDuet() {
        guard let preset = selectedPreset, !starting else { return }
        starting = true
        Haptics.shared.tap()
        Task {
            await appState.startDuet(events: preset.events,
                                     name: L10n.t(preset.nameKey))
            starting = false
        }
    }
}

// MARK: - Live heartbeat pad

/// Tap your rhythm — every tap streams over the socket and pulses on the
/// partner's 3D heart (and inside their pad, when open). Incoming partner
/// taps ripple here in their color.
struct LiveHeartbeatPad: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint

    @State private var myPulse = false
    @State private var partnerPulse = false
    @State private var lastSeenTapCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(12)) {
            SectionHeader(title: L10n.t("heartbeat.live.title"))
            Text(L10n.t(appState.partner?.online == true
                        ? "heartbeat.live.hint" : "heartbeat.live.offline",
                        ["name": appState.partnerName]))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(appState.partner?.online == true
                                 ? Nacht.sekundaer : Licht.glut)

            ZStack {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(coupleTint.blend.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                            .strokeBorder(coupleTint.blend.opacity(0.35),
                                          lineWidth: Theme.hairlineWidth))

                // Partner ripple (their color) behind my heart.
                Circle()
                    .stroke(Color(hex: appState.partner?.color ?? "A855F7"), lineWidth: 3)
                    .frame(width: 90, height: 90)
                    .scaleEffect(partnerPulse ? 1.9 : 0.8)
                    .opacity(partnerPulse ? 0 : 0.9)

                // One source of truth for the heartbeat signature — the
                // same content emoji the touch itself carries.
                Text(TouchKind.heartbeat.emoji)
                    .font(.system(.largeTitle))
                    .scaleEffect(myPulse ? 2.5 : 1.9)
            }
            .frame(height: LayoutMetrics.s(150))
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .onTapGesture {
                tap()
            }
            .accessibilityLabel(L10n.t("heartbeat.live.title"))
            .accessibilityAddTraits(.isButton)
        }
        .nightCard()
        .onChange(of: appState.partnerTapCount) { _, newCount in
            guard newCount != lastSeenTapCount else { return }
            lastSeenTapCount = newCount
            withAnimation(Theme.Motion.drift(0.7)) { partnerPulse = true }
            Task {
                try? await Task.sleep(nanoseconds: 700_000_000)
                partnerPulse = false
            }
        }
    }

    private func tap() {
        withAnimation(Theme.Motion.playful) { myPulse = true }
        Haptics.shared.play(events: [HapticEventSpec(t: 0, i: 0.8, s: 0.4)])
        appState.sendHeartbeatTap(intensity: 0.8)
        Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            withAnimation(Theme.Motion.settle) { myPulse = false }
        }
    }
}

// MARK: - Duet playback overlay (both phones)

/// Full-screen moment while a duet counts down and plays. Shown from
/// RootView whenever `appState.activeDuet` is set (the `duet_start`
/// broadcast sets it on BOTH phones — including the initiator's).
///
/// Accessibility contract (A11y eval): announces who started the duet,
/// moves VoiceOver focus onto the status line and offers a NAMED close
/// button — the full-surface tap stays a sighted shortcut. Reduce Motion
/// stills the beating heart; Reduce Transparency solidifies the scrim.
struct DuetOverlayView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.motionGate) private var motionGate
    let duet: DuetSession

    @State private var now = Date()
    @AccessibilityFocusState private var statusFocused: Bool
    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var fireAt: Date {
        ClockSync.shared.localDate(forServerMs: duet.startAtMs,
                                   fallbackServerNowMs: duet.serverNowMs)
    }

    private var playing: Bool { now >= fireAt }

    private var statusText: String {
        duet.startedBy == appState.memberId
            ? L10n.t("duet.countdown")
            : L10n.t("duet.startedBy", ["name": appState.partnerName])
    }

    var body: some View {
        ZStack {
            motionGate.scrim(0.78)
                .ignoresSafeArea()
            if playing {
                FloatingHeartsView(emojis: ["💓", "💗", "✨"], count: 16)
                    .ignoresSafeArea()
            }

            VStack(spacing: LayoutMetrics.s(18)) {
                Text(TouchKind.heartbeat.emoji)
                    .font(.system(.largeTitle))
                    .scaleEffect(playing ? 3.3 : 2.7)
                    .animation(motionGate.ambient(playing
                               ? Theme.Motion.drift(0.4).repeatForever(autoreverses: true)
                               : Theme.Motion.drift(0.8).repeatForever(autoreverses: true)),
                               value: playing)
                    .shadow(color: coupleTint.blend.opacity(0.8), radius: 44)
                    .accessibilityHidden(true)

                if let name = duet.name, !name.isEmpty {
                    Text(name)
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                        .foregroundStyle(Theme.gold)
                }

                if playing {
                    Text(L10n.t("duet.playing"))
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .foregroundStyle(.white)
                        .accessibilityFocused($statusFocused)
                } else {
                    Text(statusText)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .accessibilityFocused($statusFocused)
                    Text(String(format: "%.1f", max(0, fireAt.timeIntervalSince(now))))
                        .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                        .foregroundStyle(coupleTint.blend)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }

                Button {
                    dismissOverlay()
                } label: {
                    Label(L10n.t("common.close"), systemImage: "xmark")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, LayoutMetrics.s(18))
                        .padding(.vertical, LayoutMetrics.s(10))
                        .glass(.chrome, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(LayoutMetrics.s(30))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            dismissOverlay()
        }
        .accessibilityAddTraits(.isModal)
        .onReceive(ticker) { date in
            now = date
        }
        .onAppear {
            statusFocused = true
            let announced = [duet.name, statusText].compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            AccessibilityNotification.Announcement(announced).post()
        }
    }

    private func dismissOverlay() {
        // Closing cancels only the overlay UI; scheduled playback
        // continues (it feels wrong when the pattern suddenly dies).
        withAnimation(Theme.Motion.settle) {
            appState.activeDuet = nil
        }
    }
}
