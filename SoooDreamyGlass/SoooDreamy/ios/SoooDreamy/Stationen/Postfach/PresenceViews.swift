import SwiftUI

// „Nähe trotz Distanz": presence modes + thinking-of-you pulses.
// Sheet to set my own 🎯/😴 mode, the partner's gentle hint pill and the
// full-screen moment when a pulse arrives.

// MARK: - My presence sheet

/// Set (or clear) my focus/sleep mode: mode toggle, optional note and an
/// auto-expiry ("bis ich es ausschalte" / 30 min … 8 h).
struct PresenceSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint
    /// AX5: the mode tiles stack vertically instead of squeezing two grown
    /// tiles side by side.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var mode: PresenceModeKind = .focus
    @State private var note = ""
    @State private var minutes: Int?

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                ScrollView {
                    VStack(alignment: .leading, spacing: LayoutMetrics.s(16)) {
                        Text(L10n.t("presence.sheet.subtitle"))
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)

                        if dynamicTypeSize.prefersVerticalLayout {
                            VStack(spacing: 10) {
                                ForEach(PresenceModeKind.allCases) { kind in
                                    modeButton(kind)
                                }
                            }
                        } else {
                            HStack(spacing: 10) {
                                ForEach(PresenceModeKind.allCases) { kind in
                                    modeButton(kind)
                                }
                            }
                        }

                        TextField(L10n.t("presence.noteField"), text: $note, axis: .vertical)
                            .textFieldStyle(DreamyFieldStyle())
                            .lineLimit(1...2)

                        durationPicker

                        Button(L10n.t("presence.set")) {
                            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                            appState.setPresence(mode,
                                                 note: trimmed.isEmpty ? nil : trimmed,
                                                 minutes: minutes)
                            dismiss()
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        if appState.myPresence != nil {
                            Button(L10n.t("presence.clear")) {
                                appState.clearPresence()
                                dismiss()
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }

                        Text(L10n.t("presence.hint"))
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(LayoutMetrics.s(20))
                }
            }
            .navigationTitle(L10n.t("presence.sheet.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            if let current = appState.myPresence, let kind = current.kind {
                mode = kind
                note = current.note ?? ""
                minutes = PresenceLogic.remainingMinutes(until: current.until)
            }
        }
    }

    private func modeButton(_ kind: PresenceModeKind) -> some View {
        Button {
            mode = kind
            Haptics.shared.tap()
        } label: {
            VStack(spacing: 6) {
                Text(kind.emoji)
                    .font(.system(.largeTitle))
                Text(L10n.t(kind.titleKey))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(L10n.t(kind.subtitleKey))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LayoutMetrics.s(14))
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(mode == kind ? coupleTint.blend.opacity(0.32) : Theme.innerFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(mode == kind ? coupleTint.blend.opacity(0.8) : Theme.hairline,
                                  lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("presence.durationTitle"))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(PresenceLogic.durationChoicesMinutes.enumerated()), id: \.offset) { _, choice in
                        durationChip(choice)
                    }
                }
            }
        }
    }

    private func durationChip(_ choice: Int?) -> some View {
        let selected = minutes == choice
        return Button {
            minutes = choice
            Haptics.shared.tap()
        } label: {
            Text(durationLabel(choice))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                .padding(.vertical, 7)
                .padding(.horizontal, LayoutMetrics.s(12))
                .background(Capsule().fill(selected ? coupleTint.blend.opacity(0.4) : Theme.innerFill))
                .overlay(Capsule().strokeBorder(
                    selected ? coupleTint.blend.opacity(0.8) : Theme.hairline,
                    lineWidth: Theme.hairlineWidth))
        }
        .buttonStyle(.plain)
    }

    private func durationLabel(_ choice: Int?) -> String {
        guard let choice else { return L10n.t("presence.duration.open") }
        if choice >= 60 {
            return L10n.t("presence.duration.hours", ["hours": String(choice / 60)])
        }
        return L10n.t("presence.duration.minutes", ["minutes": String(choice)])
    }
}

// MARK: - Partner presence pill

/// "🎯 Fokus · noch 45 min" under the partner's name — a gentle hint that
/// no quick answer is expected right now.
struct PartnerPresencePill: View {
    let presence: MemberPresence

    private var kind: PresenceModeKind? { presence.kind }

    var body: some View {
        HStack(spacing: 6) {
            Text(kind?.emoji ?? "🌙")
            Text(pillText)
                .lineLimit(1)
        }
        .font(.system(.caption, design: .rounded).weight(.semibold))
        .foregroundStyle(PresenceStyle.color(for: kind))
        .padding(.vertical, 5)
        .padding(.horizontal, LayoutMetrics.s(10))
        .background(Capsule().fill(PresenceStyle.color(for: kind).opacity(0.16)))
    }

    private var pillText: String {
        var text = kind.map { L10n.t($0.titleKey) } ?? presence.mode
        if let minutesLeft = PresenceLogic.remainingMinutes(until: presence.until) {
            let label = PresenceLogic.remainingLabel(minutes: minutesLeft)
            text += " · \(L10n.t(label.key, label.args))"
        }
        if let note = presence.note, !note.isEmpty {
            text += " · \(note)"
        }
        return text
    }
}

enum PresenceStyle {
    /// Focus = soft blue, sleep = soft violet — matches the live activity.
    static func color(for kind: PresenceModeKind?) -> Color {
        switch kind {
        case .focus: return Color(hex: "8BB8FF")
        case .sleep: return Color(hex: "B39DFF")
        case nil: return Theme.textSecondary
        }
    }
}

// MARK: - Incoming pulse overlay

/// Full-screen moment while the pulse's haptic signature plays: dimmed
/// backdrop, floating emojis and the sender line. Tap to dismiss.
///
/// Accessibility contract (A11y eval): announces sender + pulse, moves
/// VoiceOver focus onto the message and offers a NAMED close button — the
/// full-surface tap stays a sighted shortcut. Reduce Motion stills the
/// beat; Reduce Transparency swaps the scrim for solid ink.
struct PulseReceivedOverlay: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.motionGate) private var motionGate
    let pulse: Pulse
    let moreCount: Int

    @State private var beat = false
    @AccessibilityFocusState private var messageFocused: Bool

    private var kind: PulseKind? { pulse.pulseKind }

    private var floatingEmojis: [String] {
        switch kind {
        case .thinking, nil: return ["💭", "💜", "✨"]
        case .goodnight: return ["🌙", "⭐️", "💜"]
        case .heartbeat: return ["💓", "💗", "💖"]
        case .hug: return ["🤗", "🫂", "💞"]
        }
    }

    private var message: String {
        L10n.t(kind?.receivedKey ?? "pulse.received.thinking",
               ["name": appState.partnerName])
    }

    var body: some View {
        ZStack {
            motionGate.scrim(0.65)
                .ignoresSafeArea()

            FloatingHeartsView(emojis: floatingEmojis, count: 18)
                .ignoresSafeArea()

            VStack(spacing: LayoutMetrics.s(18)) {
                // Hero-size signature: semantic base font scaled up — emoji
                // are bitmaps, so the scale stays crisp (see TouchReceivedOverlay).
                Text(kind?.emoji ?? "💜")
                    .font(.system(.largeTitle))
                    .scaleEffect(beat ? 3.7 : 2.9)
                    .shadow(color: coupleTint.blend.opacity(0.8), radius: 40)
                    .animation(motionGate.ambient(
                        Theme.Motion.drift(0.6).repeatForever(autoreverses: true)),
                        value: beat)
                    .accessibilityHidden(true)

                Text(message)
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, LayoutMetrics.s(30))
                    .accessibilityFocused($messageFocused)

                if moreCount > 1 {
                    Text(L10n.t("pulse.moreWhileAway", count: moreCount - 1))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
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
            .contentColumn(.reading)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            dismissOverlay()
        }
        .accessibilityAddTraits(.isModal)
        .onAppear {
            beat = true
            messageFocused = true
            AccessibilityNotification.Announcement(message).post()
        }
    }

    private func dismissOverlay() {
        appState.incomingPulse = nil
        appState.incomingPulseCount = 0
    }
}
