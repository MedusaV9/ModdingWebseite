import SwiftUI

// DesignSystem wave 1 (REDESIGN.md §2.2/§3): the empty state with charm.
// The existing EmptyStateView is honest but still — a symbol, two lines,
// done. DSEmptyState adds the arrival moment the brief asked for: the
// symbol bounces in ONCE (Theme.Motion.playful — the one curve allowed
// to overshoot) while a quiet lamp-gold Schein blooms behind it, and the
// whole state lies on a night card so an empty zone reads as a made bed,
// not a hole in the screen. Empty states stay invitations (commandment
// 8): subtitle speaks the next step, the optional chip IS the way in.
//
// Reduce Motion: no transform, the resting glow appears immediately —
// a painting, not a black hole.

struct DSEmptyState: View {
    /// SF Symbol in the couple's tint — never an emoji (commandment 1).
    let systemImage: String
    let title: String
    let subtitle: String
    /// Optional invitation chip — when the empty zone has a door, this
    /// is its handle.
    var actionTitle: String? = nil
    var actionIcon: String? = nil
    var action: (() -> Void)? = nil

    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.motionGate) private var motionGate
    /// False until the one welcome bounce has played.
    @State private var arrived = false

    var body: some View {
        VStack(spacing: Space.m) {
            Image(systemName: systemImage)
                .font(.system(.largeTitle).weight(.medium))
                .imageScale(.large)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(coupleTint.blend)
                .scaleEffect(arrived ? 1 : DS.Leben.startScale)
                .opacity(arrived ? 1 : 0)
                .background(glow)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Papier.aufNacht)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                DSChip(icon: actionIcon, title: actionTitle,
                       tint: coupleTint.blend, action: action)
                    .padding(.top, Space.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xl)
        .nightCard()
        .onAppear(perform: arrive)
    }

    /// The quiet Schein behind the symbol — the empty-state sibling of
    /// the celebration Lichtschein: same lamp gold, lower voice
    /// (`DS.Leben.glowOpacity`). As a `.background` it halos without
    /// growing the layout.
    private var glow: some View {
        RadialGradient(
            colors: [Licht.lampengold.opacity(
                arrived ? DS.Leben.glowOpacity : 0), .clear],
            center: .center,
            startRadius: 0,
            endRadius: DS.Leben.glowSize / 2)
            .frame(width: DS.Leben.glowSize, height: DS.Leben.glowSize)
            .accessibilityHidden(true)
    }

    private func arrive() {
        guard !motionGate.reduceMotion else {
            // The still path: the lit end state, immediately.
            arrived = true
            return
        }
        guard !arrived else { return }
        withAnimation(Theme.Motion.playful.delay(DS.Leben.bounceDelay)) {
            arrived = true
        }
    }
}
