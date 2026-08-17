import SwiftUI

// The floating "thinking of you" quick action — extracted from the old
// 2 300-line DashboardView (W8A component split).
//
// One-tap 💭 mini button floating over the dashboard — the most-loved
// touch without scrolling down to the touch grid. It sends a
// thinking-of-you PULSE — a haptic pattern the partner physically feels
// (queued and replayed if their app is closed, with a felt-receipt back).
//
// Long-press unfolds the pulse FAN (roadmap #02): the other pulse
// signatures appear above the button as their own standalone chrome
// circles. Deliberately NO `GlassGroup` around FAB + fan: the main FAB is
// permanently visible labeled chrome, and inside a container the
// consolidated glass pass dims sibling glyphs (emoji, xmark) — the
// CI-verified dock regression. Standalone glass plus scale/fade
// transitions keep every glyph crisp, and no blend distance can melt the
// `Space.m` resting gaps. Replaces the old context menu; VoiceOver keeps
// direct per-signature actions.

struct PulseFan: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Pop animation of the floating quick-action button.
    @State private var thinkingPulse = false
    /// The fan is unfolded — the other signatures float above the main
    /// button as glass circles (long-press opens, send/tap closes).
    @State private var fanOpen = false
    /// Mirrors the server's 30 s pulse throttle so the FAB disables itself
    /// instead of collecting 429s.
    @State private var coolingDown = false

    var body: some View {
        VStack(spacing: Space.m) {
            if fanOpen {
                ForEach(fanKinds) { kind in
                    fanButton(kind)
                }
            }
            fabButton
        }
        .padding(.trailing, Space.l)
        .padding(.bottom, Space.m)
        // Unfolding the fan is a heart gesture, not navigation — under
        // Reduce Motion it appears instantly instead of scaling in.
        .animation(reduceMotion ? nil : Theme.Motion.playful, value: fanOpen)
    }

    /// The other pulse signatures — the 💭 main button already IS .thinking.
    private var fanKinds: [PulseKind] {
        PulseKind.allCases.filter { $0 != .thinking }
    }

    private var fabButton: some View {
        Button {
            if fanOpen {
                fanOpen = false
            } else {
                send(.thinking)
            }
        } label: {
            Group {
                if fanOpen {
                    Image(systemName: "xmark")
                        .font(.system(.body, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                } else {
                    // The pulse kind's own emoji — one source of truth for the 💭.
                    Text(PulseKind.thinking.emoji)
                        .font(.system(.title, design: .rounded))
                        // Fix3 №5: the send pop is transform motion —
                        // gated like the fan unfold; the cooldown dim
                        // stays as the visible feedback.
                        .scaleEffect(thinkingPulse && !reduceMotion ? 1.3 : 1)
                }
            }
            .frame(width: LayoutMetrics.s(52), height: LayoutMetrics.s(52))
            // Chrome glass like every floating control; the ring is the
            // couple's shared color — the FAB is a heart gesture.
            .glass(.chrome, in: Circle(), interactive: true)
            .overlay(Circle().strokeBorder(coupleTint.blend.opacity(0.55), lineWidth: 1.5))
            .opacity(coolingDown ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .disabled(coolingDown)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                guard !coolingDown, !fanOpen else { return }
                Haptics.shared.tap()
                fanOpen = true
            }
        )
        .accessibilityLabel(fanOpen
                            ? L10n.t("common.cancel")
                            : L10n.t("home.thinkingFabA11y"))
        .accessibilityActions {
            // VoiceOver reaches every signature directly — the visual fan
            // is a sighted shortcut, never the only path.
            ForEach(PulseKind.allCases) { kind in
                Button(L10n.t(kind.titleKey)) { send(kind) }
            }
        }
    }

    /// One fanned-out pulse signature: a standalone chrome glass circle
    /// that scales in above the 💭 button (crisp emoji — no container
    /// pass over the glyph, see the type comment).
    private func fanButton(_ kind: PulseKind) -> some View {
        Button {
            fanOpen = false
            send(kind)
        } label: {
            Text(kind.emoji)
                .font(.system(.title3))
                .frame(width: LayoutMetrics.s(44), height: LayoutMetrics.s(44))
                .glass(.chrome, in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .accessibilityLabel(L10n.t(kind.titleKey))
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    private func send(_ kind: PulseKind) {
        guard !coolingDown else { return }
        // Fix3 №5 (RM-Gate, ChatPult-Muster): under Reduce Motion the
        // pop state flips without choreography — no 1.3× scale bounce.
        withAnimation(reduceMotion ? nil : Theme.Motion.playful) { thinkingPulse = true }
        coolingDown = true
        appState.sendPulse(kind)
        Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            withAnimation(reduceMotion ? nil : Theme.Motion.settle) { thinkingPulse = false }
            // Wake the FAB up again once the server-side 30 s throttle passed.
            try? await Task.sleep(nanoseconds: UInt64((PulseLogic.cooldown - 0.45) * 1_000_000_000))
            withAnimation(Theme.Motion.settle) { coolingDown = false }
        }
    }
}
