import SwiftUI

/// Welle 7 [30]: the moment the couple becomes whole on this device.
/// Non-nil on `AppState.pairingCeremony` drives the full-screen overlay.
struct PairingCeremonyMoment: Equatable {
    /// Pairing = the couple forming (create+join / partner joined);
    /// link = the Welle-3 second-device arrival. Same merge, different
    /// headline.
    enum Kind: Equatable {
        case paired
        case linked
    }

    let myName: String
    let partnerName: String
    let myColorHex: String
    let partnerColorHex: String
    let kind: Kind
}

/// The pairing signature moment: the two member colors drift toward each
/// other and melt into the couple's shared blend — the color that will
/// carry every milestone from here on. The merge speaks the SAME form
/// language as the first-launch cinematic (recognition!): the blend orb
/// POPS with a real ease-out-back overshoot and a bloom ring crosses the
/// whole display, exactly like `CinematicIntroView`'s merge beat. The two
/// protagonists are named on stage — each name rides under its own orb in
/// its own member color, and after the merge the headline carries both
/// names in their colors. Sound/haptics are exactly ONE cue (`.pairing`:
/// two soft pulses becoming one beat, the audible twin of the merge),
/// scheduled by CueKit — no fanfare stack on top, so the one-channel rule
/// holds. Once per pairing/link by construction, which keeps it far under
/// any delight budget. Afterwards the overlay fades and hands over softly
/// to the dashboard already waiting underneath. Reduce Motion swaps the
/// drift for a pure crossfade (no overshoot, no rings).
struct PairingCeremonyView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let moment: PairingCeremonyMoment

    /// Act 1: the two colors have drifted close (still two).
    @State private var approached = false
    /// Act 2: they became one — the blend takes over.
    @State private var merged = false
    /// Real-time anchor of the merge beat — drives the procedural pop and
    /// the bloom rings on the cinematic's own clock.
    @State private var mergeDate: Date?
    /// Names + headline fade in just after the merge beat.
    @State private var showWords = false

    private var myColor: Color { Color(hex: moment.myColorHex) }
    private var partnerColor: Color { Color(hex: moment.partnerColorHex) }
    /// Local mix as the merge target — deliberately computed from the
    /// moment itself so the orb is right even while the fresh couple
    /// palette is still loading.
    private var blend: Color { myColor.mix(with: partnerColor, by: 0.5) }

    private var orbSize: CGFloat { LayoutMetrics.s(104) }

    /// Half-distance of the two colors from center per act; Reduce Motion
    /// pins everything to center and lets opacity do the storytelling.
    private var orbOffset: CGFloat {
        guard !reduceMotion else { return 0 }
        if merged { return 0 }
        return approached ? LayoutMetrics.s(34) : LayoutMetrics.s(92)
    }

    var body: some View {
        ZStack {
            DreamyBackground()
            GeometryReader { geo in
                VStack(spacing: LayoutMetrics.s(26)) {
                    orbStage(in: geo.size)
                    words
                }
                .padding(LayoutMetrics.s(24))
                .contentColumn(.reading)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .onAppear { choreograph() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("pairing.ceremony.a11y",
                                   ["a": moment.myName, "b": moment.partnerName]))
        .accessibilityHint(L10n.t("pairing.ceremony.skipA11y"))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: The merge

    /// Two NAMED orbs drift together; at the merge beat they give way to
    /// the blend, which pops with the cinematic's overshoot while the
    /// bloom ring claims the room. Under Reduce Motion the same acts play
    /// as a pure crossfade (offset = 0, opacity only, no rings).
    private func orbStage(in size: CGSize) -> some View {
        ZStack {
            namedOrb(color: myColor, name: moment.myName, side: -1)
            namedOrb(color: partnerColor, name: moment.partnerName, side: 1)
            if let mergeDate {
                if reduceMotion {
                    Circle()
                        .fill(blend)
                        .frame(width: orbSize, height: orbSize)
                        .shadow(color: blend.opacity(0.55), radius: LayoutMetrics.s(34))
                        .opacity(merged ? 1 : 0)
                } else {
                    TimelineView(.animation) { timeline in
                        let t = timeline.date.timeIntervalSince(mergeDate)
                        blendPop(at: t)
                        mergeRings(at: t, in: size)
                    }
                }
            }
        }
        .frame(height: LayoutMetrics.s(190))
        .accessibilityHidden(true)
    }

    /// One protagonist: the orb with its owner's name riding underneath,
    /// in the owner's color — the ceremony stages PEOPLE, not just paint.
    private func namedOrb(color: Color, name: String, side: CGFloat) -> some View {
        VStack(spacing: LayoutMetrics.s(10)) {
            Circle()
                .fill(color)
                .frame(width: orbSize, height: orbSize)
            Text(name)
                .font(.system(.subheadline, design: .rounded).weight(.heavy))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: orbSize * 1.4)
        }
        .offset(x: side * orbOffset)
        .opacity(merged ? 0 : 0.9)
    }

    /// The blend orb pops on the merge beat with the cinematic's own
    /// ease-out-back (~10 % past its resting size, 0.55 s) — the couple
    /// color arrives like something ALIVE, not like a crossfade.
    @ViewBuilder
    private func blendPop(at t: Double) -> some View {
        let pop = easeOutBack(t / 0.55)
        Circle()
            .fill(blend)
            .frame(width: orbSize, height: orbSize)
            .shadow(color: blend.opacity(0.55), radius: LayoutMetrics.s(34))
            .scaleEffect(0.6 + 0.56 * CGFloat(pop))
            .opacity(min(1, easeOutValue(t / 0.3)))
    }

    /// The bloom ring crosses the WHOLE display (CinematicIntroView's
    /// merge parameters: 1.2 s life, hairline×2, target = width × 1.2),
    /// with the slower echo ring following for depth — the merge claims
    /// the room, not just the orb's neighborhood.
    @ViewBuilder
    private func mergeRings(at t: Double, in size: CGSize) -> some View {
        let target = max(size.width, orbSize * 2) * 1.2
        let life = t / 1.2
        if t >= 0, life < 1 {
            let eased = easeOutValue(life)
            Circle()
                .strokeBorder(blend.opacity(0.55 * (1 - life)),
                              lineWidth: Theme.hairlineWidth * 2)
                .frame(width: orbSize + (target - orbSize) * CGFloat(eased),
                       height: orbSize + (target - orbSize) * CGFloat(eased))
        }
        let echoLife = t / 2.4
        if t >= 0.25, echoLife < 1 {
            let eased = easeOutValue(echoLife)
            Circle()
                .strokeBorder(blend.opacity(0.3 * (1 - echoLife)),
                              lineWidth: Theme.hairlineWidth)
                .frame(width: orbSize + (target - orbSize) * CGFloat(eased) * 0.8,
                       height: orbSize + (target - orbSize) * CGFloat(eased) * 0.8)
        }
    }

    @ViewBuilder private var words: some View {
        VStack(spacing: LayoutMetrics.s(8)) {
            // Both names in their OWN colors — the merge headline keeps
            // the protagonists visible inside the new shared identity.
            (Text(moment.myName).foregroundStyle(myColor)
                + Text(verbatim: " & ").foregroundStyle(Theme.textSecondary)
                + Text(moment.partnerName).foregroundStyle(partnerColor))
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .multilineTextAlignment(.center)
            Text(L10n.t(moment.kind == .linked
                        ? "pairing.ceremony.linkedTitle"
                        : "pairing.ceremony.pairedTitle"))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .opacity(showWords ? 1 : 0)
        .accessibilityHidden(true)
    }

    // MARK: Motion math (CinematicIntroView's merge curves)

    /// Ease-out-back: overshoots its target by ~10 % and settles — the
    /// same curve as the cinematic's merge pop (s = 1.70158).
    private func easeOutBack(_ x: Double) -> Double {
        let c = min(1, max(0, x))
        let s = 1.70158
        let p = c - 1
        return 1 + (s + 1) * p * p * p + s * p * p
    }

    private func easeOutValue(_ x: Double) -> Double {
        let c = min(1, max(0, x))
        return 1 - pow(1 - c, 3)
    }

    // MARK: Choreography

    /// Timed to the `.pairing` haptic score: the colors approach during
    /// the two soft pulses (0.0 s / 0.5 s), the strong beat at ~1.1 s is
    /// exactly when they become one. The overlay releases itself — the
    /// dashboard is already underneath.
    private func choreograph() {
        withAnimation(Theme.Motion.arrive) {
            approached = true
        }
        Task {
            do {
                try await Task.sleep(nanoseconds: 1_050_000_000)
            } catch { return }
            mergeDate = Date()
            withAnimation(reduceMotion ? Theme.Motion.settle : Theme.Motion.playful) {
                merged = true
            }
            do {
                try await Task.sleep(nanoseconds: 450_000_000)
            } catch { return }
            withAnimation(Theme.Motion.arrive) {
                showWords = true
            }
            do {
                try await Task.sleep(nanoseconds: 2_100_000_000)
            } catch { return }
            finish()
        }
    }

    private func finish() {
        appState.endPairingCeremony()
    }
}
