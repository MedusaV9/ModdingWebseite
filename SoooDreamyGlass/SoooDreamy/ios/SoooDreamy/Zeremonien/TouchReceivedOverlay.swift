import SwiftUI

// The incoming-touch celebration — extracted from the old 2 300-line
// DashboardView (W8A component split). The big signature emoji and the
// floating hearts are CONTENT (the partner sent exactly this gesture);
// the glow wears the couple's shared color, not stock pink.
//
// Accessibility contract (A11y eval): the overlay ANNOUNCES itself
// (sender + gesture), moves VoiceOver focus onto the message, and offers a
// NAMED close button — the full-surface tap stays as a sighted shortcut,
// never as the only way out. Reduce Motion collapses the endless pulse into
// one still arrival; Reduce Transparency swaps the dim scrim for solid ink.

struct TouchReceivedOverlay: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.motionGate) private var motionGate
    let touch: Touch

    @State private var pulse = false
    @AccessibilityFocusState private var messageFocused: Bool

    private var heartsFor: [String] {
        switch touch.type {
        case .heartbeat: return ["💓", "💗", "💖"]
        case .kiss: return ["💋", "😘", "💖"]
        case .hug: return ["🫂", "🤗", "💞"]
        case .missyou: return ["🥺", "💌", "💜"]
        case .tickle: return ["🪶", "😂", "✨"]
        case .thinking: return ["💭", "💜", "✨"]
        case .stolz: return ["⭐", "🌟", "💛"]
        case .halteDurch: return ["✊", "💪", "💗"]
        }
    }

    private var message: String {
        touch.echo == true
            ? L10n.t("touch.echo.received", ["name": appState.partnerName])
            : L10n.t("touch.received.\(touch.type.rawValue)",
                     ["name": appState.partnerName])
    }

    /// Echo affordance: a RECEIVED touch can be sent back once within
    /// 10 minutes (PostRules mirrors the server window). An incoming echo
    /// offers no counter-echo — not here and not in the journal (which has
    /// no echo button at all): one bounce per touch is the deliberate rule,
    /// and the server refuses echo-of-echo with 409 echo_taken to match.
    private var canEcho: Bool {
        PostRules.echoAllowed(originalSenderId: touch.senderId,
                              myMemberId: appState.memberId,
                              originalIsEcho: touch.echo == true,
                              originalCreatedAt: touch.createdAt,
                              alreadyEchoed: appState.echoedTouchIds.contains(touch.id))
    }

    var body: some View {
        ZStack {
            motionGate.scrim(0.6)
                .ignoresSafeArea()

            FloatingHeartsView(emojis: heartsFor, count: 22)
                .ignoresSafeArea()

            VStack(spacing: LayoutMetrics.s(18)) {
                // Hero-size signature: a semantic base font scaled up —
                // emoji are bitmaps, so the scale stays crisp and the
                // fixed-size counter stays quiet.
                Text(touch.type.emoji)
                    .font(.system(.largeTitle))
                    .scaleEffect(pulse ? 3.4 : 2.7)
                    .shadow(color: coupleTint.blend.opacity(0.8), radius: 40)
                    .animation(motionGate.ambient(
                        Theme.Motion.drift(0.55).repeatForever(autoreverses: true)),
                        value: pulse)
                    .accessibilityHidden(true)

                Text(message)
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, LayoutMetrics.s(30))
                    .padding(.top, Space.xl)
                    .accessibilityFocused($messageFocused)

                HStack(spacing: LayoutMetrics.s(10)) {
                    if canEcho {
                        echoButton
                    }
                    closeButton
                }
            }
            .contentColumn(.reading)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            appState.incomingTouch = nil
        }
        .accessibilityAddTraits(.isModal)
        .onAppear {
            pulse = true
            messageFocused = true
            AccessibilityNotification.Announcement(message).post()
        }
    }

    /// P6-B: one deliberate tap sends the same touch back (`echo:true`) —
    /// no cooldown, once per original. Quiet capsule like the close button;
    /// the couple color marks it as the warm choice of the two.
    private var echoButton: some View {
        Button {
            appState.echoTouch(touch)
            appState.incomingTouch = nil
        } label: {
            Label(L10n.t("touch.echo.action"), systemImage: "arrow.uturn.left")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(coupleTint.onGradient)
                .padding(.horizontal, LayoutMetrics.s(18))
                .padding(.vertical, LayoutMetrics.s(10))
                .background(
                    Capsule().fill(coupleTint.heroGradient)
                        .overlay(Capsule().fill(coupleTint.gradientTextScrim ?? .clear))
                )
        }
        .buttonStyle(.plain)
    }

    private var closeButton: some View {
        Button {
            appState.incomingTouch = nil
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
}
