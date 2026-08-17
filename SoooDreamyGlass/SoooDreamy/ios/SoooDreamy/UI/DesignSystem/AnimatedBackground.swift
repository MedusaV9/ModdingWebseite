import SwiftUI

// DesignSystem wave 1 (REDESIGN.md §2.1): the living room. The static
// sepia room felt like a dead surface on large screens — nothing
// breathed. AnimatedBackground keeps EVERYTHING the room already is
// (fixed gradient, one static lamp cone, the couple-ink dust) and adds
// exactly one layer: the Atemglühen — two very slow glow fields in the
// couple's colors breathing under the lamp cone.
//
// Contrast legend (nacht-first anchors stay pinned): the breath peaks at
// `DS.Atem.peakPrimary` (0.10) / `peakSecondary` (0.07), far below the
// lamp cone's pinned 0.30 paint — every night-ink anchor keeps the same
// margin it holds at the lamp's brightest point.
//
// Central ambience throttle (same law as DreamyBackground): the breath
// freezes into a still mid-breath painting when Reduce Motion is on, the
// scene is inactive, or Low Power Mode is on — the couple's battery
// outranks ambience.

struct AnimatedBackground: View {
    /// Same legacy knobs as DreamyBackground so call sites can migrate
    /// by swapping ONE word: `showBlobs` gates the ink dust,
    /// `blobIntensity` scales it, `showStars` is accepted but inert.
    var showStars: Bool = true
    var showBlobs: Bool = true
    var blobIntensity: Double = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.couplePalette) private var couplePalette
    @State private var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var ambientAnimated: Bool {
        !reduceMotion && !lowPowerMode && scenePhase == .active
    }

    var body: some View {
        ZStack {
            Theme.bgGradient
            LampenkegelView()
            AtemgluehenView(animated: ambientAnimated, palette: couplePalette)
            if showBlobs {
                TintenstaubView(animated: ambientAnimated,
                                palette: couplePalette,
                                intensity: blobIntensity)
            }
        }
        .ignoresSafeArea()
        .onReceive(NotificationCenter.default
            .publisher(for: Notification.Name.NSProcessInfoPowerStateDidChange)
            .receive(on: RunLoop.main)) { _ in
            lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }
}

/// The Atemglühen: two radial glow fields in the couple's ink colors
/// (golden ink before pairing, same fallback as the dust), anchored at
/// the named `DS.Atem` unit points, breathing on the `DS.Atem.period`
/// rhythm — opacity and radius swell together, phase-shifted against
/// each other so the room never pulses like a metronome.
///
/// Rendered as plain gradients driven by a TimelineView at the
/// `DS.Atem.hz` frame budget (slower than the 12-Hz dust — a breath
/// needs less). `animated: false` shows the mid-breath painting: a lit
/// room, never a black hole.
struct AtemgluehenView: View {
    var animated: Bool = true
    var palette: CouplePalette?

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / DS.Atem.hz)) { timeline in
                fields(t: timeline.date.timeIntervalSinceReferenceDate)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        } else {
            // The still painting: both fields at their resting breath.
            fields(t: nil)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Breath position 0…1 for one field; `t == nil` is the frozen
    /// mid-breath (0.5) of the still painting.
    private func breath(t: TimeInterval?, phase: Double) -> Double {
        guard let t else { return 0.5 }
        let omega = 2 * Double.pi / DS.Atem.period
        return (sin(t * omega + phase) + 1) / 2
    }

    private func fields(t: TimeInterval?) -> some View {
        // Pre-pairing the room breathes in the golden ink — identical
        // fallback family as the Tintenstaub, so ambience never invents
        // a color the room does not already speak.
        let first = palette.map { Color(hex: $0.primary) } ?? Licht.lampengold
        let second = palette.map { Color(hex: $0.secondary) } ?? Licht.kupfer
        return GeometryReader { geo in
            let side = max(geo.size.width, geo.size.height)
            let primaryBreath = breath(t: t, phase: 0)
            let secondaryBreath = breath(t: t, phase: DS.Atem.secondaryPhase)
            ZStack {
                glowField(color: first,
                          breath: primaryBreath,
                          peak: DS.Atem.peakPrimary,
                          center: DS.Atem.primaryCenter,
                          side: side, size: geo.size)
                glowField(color: second,
                          breath: secondaryBreath,
                          peak: DS.Atem.peakSecondary,
                          center: DS.Atem.secondaryCenter,
                          side: side, size: geo.size)
            }
        }
    }

    /// One glow field: a radial falloff whose opacity and radius swell
    /// with the breath. The floor never drops to zero — the room keeps
    /// its warmth between breaths.
    private func glowField(color: Color, breath: Double, peak: Double,
                           center: UnitPoint, side: CGFloat,
                           size: CGSize) -> some View {
        let opacity = peak * (0.55 + 0.45 * breath)
        let radius = side * DS.Atem.radiusFactor
            * (1 + DS.Atem.radiusSwell * (breath - 0.5) * 2)
        return RadialGradient(
            colors: [color.opacity(opacity), .clear],
            center: center,
            startRadius: 0,
            endRadius: radius)
            .frame(width: size.width, height: size.height)
    }
}
