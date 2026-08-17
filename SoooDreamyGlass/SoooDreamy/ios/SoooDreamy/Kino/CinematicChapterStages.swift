import SwiftUI

// FullRelease N3-Kino — the PROCEDURAL chapters of the first-launch
// cinema, staged from the app's own Papier & Licht tokens: the sepia
// Zimmer of the video scenes (CinematicRoomStage — gradient, lamp cone,
// ink dust; R1-B replaced the aurora vocabulary), letter paper, wax,
// ink. Scenes 1/4/5/7 always render here (interaction, runtime
// colors, the hand-off into the live UI); scenes 2/3/6 render here as
// the shorter Kurzfassung whenever their video is missing (Lite IPA,
// corrupt bundle) — same story, stage version.
//
// Every stage is a pure function of its chapter-LOCAL time `t`: the
// shell owns the clock (TimelineView), Reduce Motion passes a settled
// constant instead and gets a calm still of the same composition, and
// the CI screenshot freeze passes the frozen playhead. No stage keeps
// its own animation state besides recorded input times.

/// Shared curve vocabulary — the script keeps linear time, the stage
/// curves it (same math the W8D renderer used).
enum CinematicStageMath {
    /// Cubic smoothstep, clamped.
    static func smooth(_ x: Double) -> Double {
        let c = min(1, max(0, x))
        return c * c * (3 - 2 * c)
    }

    static func easeOut(_ x: Double) -> Double {
        let c = min(1, max(0, x))
        return 1 - pow(1 - c, 3)
    }

    /// Ease-out-back: overshoots ~10 % and settles — the merge pop and
    /// the postmark stamp swing past their resting pose like something
    /// alive (the cinematic's signature curve).
    static func easeOutBack(_ x: Double) -> Double {
        let c = min(1, max(0, x))
        let s = 1.70158
        let p = c - 1
        return 1 + (s + 1) * p * p * p + s * p * p
    }
}

/// The Zimmer of the CI-rendered look-scenes, staged live (Kino-Final-
/// Eval finding 3: the procedural chapters still played on the aurora/
/// star vocabulary — a visible hybrid break against the videos). This is
/// EXACTLY the videos' picture world, painted from the existing Papier &
/// Licht tokens with the geometry of `remotion/src/look.tsx` `Room`:
/// vertical sepia room gradient, the double lamp cone from 10 o'clock
/// (wide warm falloff + golden core), the warm floor ember and the
/// vignette. `strength` 0…1 — chapter 1's lamp click ignites the cone,
/// every later chapter keeps it burning; while lit, the light breathes
/// and wanders minimally like the videos' `lampDrift` (deliberately NO
/// soft-light cast over the paper cards: ink contrast on paper is law).
struct CinematicRoomStage: View {
    /// Chapter-local seconds — drives breath and wander only.
    let t: Double
    var strength: Double = 1
    /// Reduce Motion / frozen screenshots: the light stands still.
    var animated: Bool = true
    /// 0…1 — the finale's light hand-off (Kino-Final-Eval, letzter S2):
    /// crossfades the cinema's dramatic cone (0.52/0.28 + vignette) into
    /// EXACTLY the ambient composition `DreamyBackground` paints
    /// (`Theme.bgGradient` + `LampenkegelView`), so at the layer swap not
    /// only the buttons but every background pixel is identical.
    var ambientSettle: Double = 0

    private var drift: (breath: Double, x: Double, y: Double) {
        guard animated else { return (1, 0, 0) }
        return (1 + 0.02 * sin(t * 1.1 * .pi),
                0.009 * sin(t * 0.37),
                0.0055 * sin(t * 0.23 + 1.7))
    }

    var body: some View {
        let d = drift
        let k = strength * d.breath
        let settle = min(max(ambientSettle, 0), 1)
        ZStack {
            // The room itself: dark sepia above, warm chestnut below —
            // the same vertical ramp the videos open and close on.
            LinearGradient(
                stops: [
                    .init(color: Papier.zimmerOben, location: 0),
                    .init(color: Papier.zimmerOben.mix(with: Papier.zimmerUnten,
                                                       by: 0.5),
                          location: 0.52),
                    .init(color: Papier.zimmerUnten, location: 1),
                ],
                startPoint: .top, endPoint: .bottom)
            // The cinema's dramatic light — breathes out during the finale.
            // P2-B Nachzug (MIGRATION_DUNKEL §6): the intensities follow the
            // theme's lamp reduction proportionally (× ≈ 0.85 cone, × ≈ 0.8
            // gold), so cinema and app tell the same late night and the
            // ambientSettle hand-off onto the recalibrated LampenkegelView
            // stays a soft crossfade instead of a visible brightness step.
            Group {
                // Wide cone falloff (umbra → nothing), wandering with the lamp.
                RadialGradient(
                    stops: [
                        .init(color: Papier.lichtkegel.opacity(0.52 * k), location: 0),
                        .init(color: Papier.lichtkegel.opacity(0.24 * k), location: 0.5),
                        .init(color: .clear, location: 1),
                    ],
                    center: UnitPoint(x: 0.16 + d.x, y: 0.04 + d.y),
                    startRadius: 0, endRadius: LayoutMetrics.s(700))
                // Golden lamp core — wanders a touch more (source parallax).
                RadialGradient(
                    stops: [
                        .init(color: Licht.lampengold.opacity(0.28 * k), location: 0),
                        .init(color: Licht.lampengold.opacity(0.10 * k), location: 0.61),
                        .init(color: .clear, location: 1),
                    ],
                    center: UnitPoint(x: 0.14 + d.x * 1.4, y: 0.02 + d.y * 1.4),
                    startRadius: 0, endRadius: LayoutMetrics.s(450))
                // Warm ember glowing back from the floor.
                RadialGradient(
                    stops: [
                        .init(color: Licht.glut.opacity(0.08 * k), location: 0),
                        .init(color: .clear, location: 0.7),
                    ],
                    center: UnitPoint(x: 0.42, y: 1.04),
                    startRadius: 0, endRadius: LayoutMetrics.s(330))
                // Vignette — the darker night carries a calmer edge falloff.
                RadialGradient(
                    stops: [
                        .init(color: .clear, location: 0.52),
                        .init(color: Color.black.opacity(0.55), location: 1),
                    ],
                    center: UnitPoint(x: 0.46, y: 0.42),
                    startRadius: 0, endRadius: LayoutMetrics.s(780))
            }
            .opacity(1 - settle)
            // The ambient hand-off target: the EXACT static composition the
            // real app paints behind every screen. At settle == 1 the room
            // gradient above is fully covered by the identical bgGradient
            // and the lamp is the pinned LampenkegelView — pixel parity.
            if settle > 0 {
                Theme.bgGradient.opacity(settle)
                LampenkegelView().opacity(settle)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Sparse ink dust drifting down the light cone — the DustMotes pass of
/// the videos, ported 1:1 (axis drift + cross swing + twinkle), seeded
/// through `PaperRules.unitRandom` so nothing flickers between renders.
/// Drawn in ONE Canvas pass above the stage props, like the videos
/// composite their dust above the paper.
struct CinematicRoomDust: View {
    /// Chapter-local seconds; a constant renders a static dust still.
    let t: Double
    var count: Int = 14

    private static let seed: UInt64 = 0x4E33_5354_4155_42 // "N3STAUB"

    var body: some View {
        Canvas { context, size in
            context.addFilter(.blur(radius: 0.6))
            for i in 0..<count {
                let u = PaperRules.unitRandom(seed: Self.seed, index: i * 6)
                let v = PaperRules.unitRandom(seed: Self.seed, index: i * 6 + 1)
                let r = 1.1 + PaperRules.unitRandom(seed: Self.seed, index: i * 6 + 2) * 1.8
                let speed = 0.35 + PaperRules.unitRandom(seed: Self.seed, index: i * 6 + 3) * 0.75
                let phi = PaperRules.unitRandom(seed: Self.seed, index: i * 6 + 4) * .pi * 2
                let tw = 0.5 + PaperRules.unitRandom(seed: Self.seed, index: i * 6 + 5) * 1.1
                // Cone axis from (14 %, 2 %) toward down-right; motes
                // drift slowly along it and swing across.
                let along = (v + t * 0.012 * speed).truncatingRemainder(dividingBy: 1)
                let spread = along * 0.52 + 0.05
                let cx = 0.14 + along * 0.52 + (u - 0.5) * spread * 1.5
                let cy = 0.02 + along * 0.78 + sin(t * speed + phi) * 0.012
                let twinkle = 0.5 + 0.5 * sin(t * tw * 2 + phi * 3)
                let axisDist = abs(u - 0.5) * 2
                let inCone = max(0, min(1, 1 - axisDist)) * max(0, min(1, 1.15 - along))
                let opacity = 0.2 * twinkle * inCone
                guard opacity >= 0.01 else { continue }
                let rect = CGRect(x: cx * size.width, y: cy * size.height,
                                  width: r, height: r)
                context.fill(Path(ellipseIn: rect),
                             with: .color(Licht.lampengold.opacity(opacity)))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Chapter 1 — Lampenklick (the language gate)

/// The room is dark, the lamp clicks on (~0.85 s, one felt beat) and
/// lights two paper cards: „Deutsch" / „English" — both readable at
/// once, classic bilingual first choice. Tapping chooses; the chosen
/// card lifts toward the light under a wax check seal (it becomes the
/// next scene's envelope), the other stays on stage and only dims
/// lightly (Fix-Runde 3, Kino-Befund 2 — nothing vanishes before the
/// crossfade). The gate is FUNCTION, not film: it waits as long as it
/// needs and can never be skipped.
struct CinematicLanguageGateStage: View {
    let t: Double
    let reduceMotion: Bool
    /// Fired once, on the choice — the shell persists and advances.
    let onChoose: (AppLanguage) -> Void

    @State private var chosen: AppLanguage?

    /// `staged` pre-sets the choice for the FROZEN CI shots (Re-Eval
    /// Runde 2: the t2 frame never proved the chosen state — stamp
    /// point + lift). Live runs pass nil; the gate then waits as ever.
    init(t: Double, reduceMotion: Bool, staged: AppLanguage? = nil,
         onChoose: @escaping (AppLanguage) -> Void) {
        self.t = t
        self.reduceMotion = reduceMotion
        self.onChoose = onChoose
        _chosen = State(initialValue: staged)
    }

    /// The lamp clicks at 0.85 s (the SHELL ignites the room's cone on
    /// the same beat) — the cards follow the light in.
    private var cardReveal: Double {
        reduceMotion ? 1 : CinematicStageMath.smooth((t - 1.1) / 0.7)
    }

    var body: some View {
        ZStack {
            VStack(spacing: Space.l) {
                languageCard(.de,
                             titleKey: "cinematic.language.de",
                             subKey: "cinematic.language.de.sub",
                             a11yKey: "cinematic.language.de.a11y")
                languageCard(.en,
                             titleKey: "cinematic.language.en",
                             subKey: "cinematic.language.en.sub",
                             a11yKey: "cinematic.language.en.a11y")
            }
            .padding(.horizontal, Space.xxl)
            .contentColumn(.reading)
            .opacity(cardReveal)
        }
    }

    private func languageCard(_ language: AppLanguage, titleKey: String,
                              subKey: String, a11yKey: String) -> some View {
        let isChosen = chosen == language
        let otherChosen = chosen != nil && !isChosen
        return Button {
            pick(language)
        } label: {
            VStack(spacing: Space.xs) {
                Text(L10n.t(titleKey))
                    .font(Typo.title)
                    .foregroundStyle(Tinte.dunkel)
                Text(L10n.t(subKey))
                    .font(Typo.caption)
                    .foregroundStyle(Tinte.sekundaer)
            }
            .frame(maxWidth: .infinity)
            .paperCard(.brief, padding: .regular)
            // Fix4 Befund 5: the CHOSEN card additionally wears a quiet
            // wax contour — selection reads through seal + contour +
            // lift, never through greying the other card down.
            .overlay {
                if isChosen {
                    RoundedRectangle(cornerRadius: PaperLevel.brief.radius,
                                     style: .continuous)
                        .strokeBorder(Wachs.rot.opacity(0.55),
                                      lineWidth: LayoutMetrics.s(2))
                }
            }
            // t2-Sprachgate (Fix-Runde 3, Kino-Befund 2): the CHOSEN
            // card seals its corner with a wax check — Wachs.rot pour,
            // light check embossed, the existing seal material one size
            // up from the old 12-pt point that read as a speck. The
            // card's text stays untouched underneath.
            .overlay(alignment: .topTrailing) {
                if isChosen {
                    ZStack {
                        Circle()
                            .fill(Wachs.rot)
                        Circle()
                            .strokeBorder(Wachs.dunkel.opacity(0.4),
                                          lineWidth: Theme.hairlineWidth)
                        Image(systemName: "checkmark")
                            .font(.system(.footnote, design: .rounded).weight(.bold))
                            .foregroundStyle(Papier.brief)
                    }
                    .frame(width: LayoutMetrics.s(28),
                           height: LayoutMetrics.s(28))
                    .padding(Space.s)
                    .transition(.opacity)
                    .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        // Fix-Runde 3 (Kino-Befund 2): no `.disabled` — the system dims
        // a disabled plain button's label, which made the CHOSEN card
        // read deactivated in the confirmation beat. `pick` already
        // drops second taps; hit-testing simply switches off.
        .allowsHitTesting(chosen == nil)
        // Both cards STAY on stage through the confirmation: the chosen
        // one lifts into the light (the next scene's envelope), the
        // other only dims LIGHTLY — still readable, never gone. The
        // crossfade to chapter 2 happens after, on the shell's hold.
        // Fix4 Befund 5: the unchosen card keeps its warm paper and full
        // ink — 0.85 is the dim ceiling (0.7 read disabled-grey); the
        // chosen one answers with a step up the elevation scale instead
        // (raised token values; clear color = no second resting shadow).
        .scaleEffect(isChosen && !reduceMotion ? 1.06 : 1)
        .shadow(color: isChosen ? Elevation.raised.color : .clear,
                radius: Elevation.raised.radius,
                x: Elevation.raised.offset.width,
                y: Elevation.raised.offset.height)
        .opacity(otherChosen ? 0.85 : 1)
        .accessibilityLabel(L10n.t(a11yKey))
        .accessibilityIdentifier("cinematic.language.\(language.rawValue)")
        .accessibilityAddTraits(isChosen ? [.isSelected] : [])
    }

    private func pick(_ language: AppLanguage) {
        guard chosen == nil else { return }
        withAnimation(Theme.Motion.arrive) { chosen = language }
        onChoose(language)
    }
}

// MARK: - Chapter 2 Kurzfassung — Der Umschlag

/// The envelope slides into the lamp cone (settle beat at 2.2 s), the
/// postmark stamps at 3.6 s (`.sealed` rings there). Text-free like the
/// video — the chapter caption speaks.
struct CinematicEnvelopeStage: View {
    let t: Double

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let slide = CinematicStageMath.easeOut(t / 2.2)
        ZStack {
            envelope
                .offset(x: (1 - slide) * -LayoutMetrics.s(280))
                .overlay(alignment: .topTrailing) {
                    if t >= 3.6 {
                        // ENTSCHIEDEN (t12, Kino-Eval S3): the postmark
                        // sits ENTIRELY on the envelope — ink is stamped
                        // ON paper, it cannot hang past the sheet. A firm
                        // 10 pt inset from both edges, never a tangent.
                        postmark
                            .offset(x: -LayoutMetrics.s(10), y: LayoutMetrics.s(10))
                    }
                }
        }
    }

    private var envelope: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
        return ZStack(alignment: .top) {
            shape.fill(Papier.brief)
            // The flap, folded down — cardboard tone against the letter.
            EnvelopeFlapShape()
                .fill(Papier.karton)
                .frame(height: LayoutMetrics.s(58))
            // Blank address lines — the words belong to the caption.
            VStack(alignment: .leading, spacing: Space.s) {
                Capsule().fill(Papier.kante)
                    .frame(width: LayoutMetrics.s(96), height: LayoutMetrics.s(6))
                Capsule().fill(Papier.kante)
                    .frame(width: LayoutMetrics.s(64), height: LayoutMetrics.s(6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, Space.xl)
            .padding(.top, LayoutMetrics.s(76))
        }
        .frame(width: LayoutMetrics.s(232), height: LayoutMetrics.s(148))
        .overlay(
            shape.strokeBorder(PaperLightEdge.gradient, lineWidth: Theme.hairlineWidth))
        .elevation(.resting)
    }

    /// The stamp lands with the cinematic's overshoot; the ring and the
    /// day line wear stamp-ink red (Wachs.rot is MATERIAL, never text on
    /// night — here it sits on paper).
    private var postmark: some View {
        let pop = CinematicStageMath.easeOutBack((t - 3.6) / 0.3)
        return ZStack {
            Circle()
                .strokeBorder(Wachs.rot.opacity(0.85), lineWidth: Theme.hairlineWidth * 2)
            Text(L10n.t("cinematic.umschlag.stamp"))
                .font(Typo.anschrift(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize))
                .foregroundStyle(Wachs.rot)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.horizontal, Space.xs)
        }
        .frame(width: LayoutMetrics.s(64), height: LayoutMetrics.s(64))
        .paperTilt(seed: 0x4E33_5354_414D_50) // "N3STAMP" — the scene's one tilt
        .scaleEffect(1.5 - 0.5 * pop)
        .opacity(min(1, max(0, (t - 3.6) / 0.12)))
    }
}

/// The folded-down envelope flap: a wide triangle from the top edge.
struct EnvelopeFlapShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Chapter 3 Kurzfassung — Der Siegelbruch

/// The neutral wax seal breaks at 2.2 s (`.unseal` rings, the strong
/// beat lands), the letter unfolds blank — the words are the caption's.
struct CinematicSealBreakStage: View {
    let t: Double

    var body: some View {
        // Letter growth: folded until the crack, then it unfolds.
        let unfold = CinematicStageMath.smooth((t - 2.2) / 1.8)
        let crack = CinematicStageMath.easeOut((t - 2.2) / 0.6)
        ZStack {
            letter(unfold: unfold)
            sealPieces(crack: crack)
        }
    }

    private func letter(unfold: Double) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
        let height = LayoutMetrics.s(96) + LayoutMetrics.s(150) * CGFloat(unfold)
        return shape
            .fill(Papier.brief)
            .overlay(shape.strokeBorder(PaperLightEdge.gradient,
                                        lineWidth: Theme.hairlineWidth))
            .overlay(alignment: .top) {
                // Blank serif lines surface as the paper opens.
                VStack(alignment: .leading, spacing: Space.m) {
                    Capsule().fill(Papier.kante)
                        .frame(width: LayoutMetrics.s(150), height: LayoutMetrics.s(6))
                    Capsule().fill(Papier.kante)
                        .frame(width: LayoutMetrics.s(120), height: LayoutMetrics.s(6))
                    Capsule().fill(Papier.kante)
                        .frame(width: LayoutMetrics.s(136), height: LayoutMetrics.s(6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.xl)
                .opacity(unfold)
            }
            .frame(width: LayoutMetrics.s(224), height: height)
            .elevation(.resting)
    }

    /// The wax seal sits whole until the crack, then its two halves part
    /// and fall out of the light.
    @ViewBuilder
    private func sealPieces(crack: Double) -> some View {
        if crack <= 0 {
            sealHalf(leading: true)
            sealHalf(leading: false)
        } else if crack < 1 {
            sealHalf(leading: true)
                .offset(x: -LayoutMetrics.s(34) * CGFloat(crack),
                        y: LayoutMetrics.s(46) * CGFloat(crack * crack))
                .opacity(1 - crack)
            sealHalf(leading: false)
                .offset(x: LayoutMetrics.s(34) * CGFloat(crack),
                        y: LayoutMetrics.s(52) * CGFloat(crack * crack))
                .opacity(1 - crack)
        }
    }

    /// One half of the neutral wax seal (Wachs.rot — no couple exists
    /// yet; the couple's own wax arrives in chapter 5).
    private func sealHalf(leading: Bool) -> some View {
        Circle()
            .fill(Wachs.rot)
            .overlay(
                Image(systemName: "heart.fill")
                    .font(Typo.label)
                    .foregroundStyle(Papier.brief.opacity(0.55))
            )
            .frame(width: LayoutMetrics.s(56), height: LayoutMetrics.s(56))
            .mask(alignment: leading ? .leading : .trailing) {
                Rectangle().frame(width: LayoutMetrics.s(28))
            }
            .elevation(.resting)
    }
}

// MARK: - Chapter 4 — Zwei Tintenfässer (the ink choice)

/// „Wähl deine Farbe": eight ink dots wait under two wells. The pick
/// drops into the left well and draws a stroke; the partner stroke
/// shimmers in lamp gold as a placeholder; both run toward each other
/// (`CinematicScript.inkApproachDuration`, the orb tones resolve INTO
/// the meeting) and mix into the blend. The chapter waits for the
/// person — the shell schedules the advance when the choice happens.
struct CinematicInkStage: View {
    let t: Double
    let reduceMotion: Bool
    /// Hex of the chosen member color, or nil while the chapter waits.
    let chosenHex: String?
    /// Chapter-local time of the pick (the shell records it).
    let pickTime: Double?
    let onPick: (String) -> Void

    @Environment(\.coupleTint) private var coupleTint

    /// Time since the pick — drives drop, stroke and approach.
    private var p: Double {
        guard let pickTime else { return 0 }
        return reduceMotion ? .greatestFiniteMagnitude : max(0, t - pickTime)
    }

    private var chosenColor: Color {
        Color(hex: chosenHex ?? Theme.memberColors[0])
    }

    /// The strokes meet and mix — the blend the wax seal will pour.
    private var blend: Color {
        chosenColor.mix(with: Licht.lampengold, by: 0.4)
    }

    var body: some View {
        // t30-Palette (Gesamtbild-Eval S2): after the pick the palette
        // does not pop away — it stands through the drop-and-stroke lead
        // (the un-chosen wells recede, the chosen one keeps its full
        // body) while the SELECTION draws itself as the ink stroke ON
        // the letter sheet, then the slot crossfades to the partner
        // line. Both live in one ZStack slot, so the sheet never jumps.
        let paletteFade = chosenHex == nil
            ? 0.0
            : CinematicStageMath.smooth((p - 0.8) / 0.5)
        return ZStack {
            VStack(spacing: Space.xxl) {
                strokeStage
                ZStack {
                    palette
                        .opacity(1 - paletteFade)
                    Text(L10n.t("cinematic.ink.partner"))
                        .font(Typo.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .opacity(partnerShimmer)
                }
            }
            .padding(.horizontal, Space.xxl)
            .contentColumn(.reading)
        }
    }

    // MARK: The two strokes

    /// 0…1 — how far the two strokes have run toward each other.
    private var approach: Double {
        guard chosenHex != nil else { return 0 }
        if reduceMotion { return 1 }
        return CinematicStageMath.smooth((p - 1.2) / CinematicScript.inkApproachDuration)
    }

    private var partnerShimmer: Double {
        guard chosenHex != nil else { return 0 }
        if reduceMotion { return 1 }
        return CinematicStageMath.smooth((p - 0.8) / 0.6)
    }

    private var strokeStage: some View {
        let drop = CinematicStageMath.easeOut(p / 0.5)
        let drawn = CinematicStageMath.easeOut((p - 0.4) / 0.8)
        let met = approach >= 1
        return ZStack {
            // The paper the strokes run on — a LETTER in the cone, not an
            // empty white rectangle (Weiß-Audit): the sheet carries the
            // same blank-letter grammar as the envelope and seal chapters
            // (kante address lines) plus faint ruled writing lines in low-
            // opacity ink. Purely static drawing — identical under Reduce
            // Motion and in the CI freeze.
            RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                .fill(Papier.brief)
                .overlay(letterFace)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                        .strokeBorder(PaperLightEdge.gradient,
                                      lineWidth: Theme.hairlineWidth))
                .frame(height: LayoutMetrics.s(120))
                .elevation(.resting)
            if let chosenHex {
                let inkColor = Color(hex: CouplePaletteRules.inkOnPaper(chosenHex))
                // The falling drop.
                if !reduceMotion, p < 0.5 {
                    Circle()
                        .fill(inkColor)
                        .frame(width: LayoutMetrics.s(10), height: LayoutMetrics.s(10))
                        .offset(x: -LayoutMetrics.s(86),
                                y: LayoutMetrics.s(-70) + LayoutMetrics.s(60) * CGFloat(drop))
                }
                // Your stroke, running right; the shimmer stroke, running
                // left — they meet in the middle and become the blend.
                inkStroke(inkColor, width: 60 * drawn + 30 * approach, side: -1)
                inkStroke(Licht.lampengold.opacity(0.55 * partnerShimmer),
                          width: 52 * partnerShimmer + 30 * approach, side: 1)
                if met {
                    Circle()
                        .fill(blend)
                        .frame(width: LayoutMetrics.s(26), height: LayoutMetrics.s(26))
                        .shadow(color: blend.opacity(0.5), radius: LayoutMetrics.s(14))
                        .transition(.opacity)
                }
            }
        }
    }

    /// The sheet's static letter face: blank kante address lines up top
    /// (the same grammar the envelope and seal chapters draw) and two
    /// faint ruled writing lines waiting for the ink below the strokes —
    /// low-opacity `Tinte` decor, purely static (Reduce Motion renders
    /// the identical still), hidden from VoiceOver.
    private var letterFace: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Space.s) {
                Capsule().fill(Papier.kante)
                    .frame(width: LayoutMetrics.s(64), height: LayoutMetrics.s(5))
                Capsule().fill(Papier.kante.opacity(0.7))
                    .frame(width: LayoutMetrics.s(44), height: LayoutMetrics.s(5))
            }
            Spacer(minLength: 0)
            VStack(spacing: Space.m) {
                Rectangle()
                    .fill(Tinte.tertiaer.opacity(0.22))
                    .frame(height: Theme.hairlineWidth)
                Rectangle()
                    .fill(Tinte.tertiaer.opacity(0.22))
                    .frame(height: Theme.hairlineWidth)
            }
        }
        .padding(Space.l)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func inkStroke(_ color: some ShapeStyle, width: Double,
                           side: CGFloat) -> some View {
        let w = LayoutMetrics.s(CGFloat(max(0, width)))
        let travel = LayoutMetrics.s(86) * (1 - CGFloat(approach))
        return Capsule()
            .fill(color)
            .frame(width: w, height: LayoutMetrics.s(8))
            .offset(x: side * travel)
            .opacity(width > 1 ? 1 : 0)
    }

    // MARK: The ink dots

    private var palette: some View {
        // t30-Palette (Gesamtbild-Eval S2): a CENTERED 4×2 raster — the
        // adaptive grid used to wrap 6+2 on phone widths, unbalanced and
        // without visible order. Fixed columns size the grid to its
        // content, so the raster centers itself under the sheet.
        let columns = Array(
            repeating: GridItem(.fixed(LayoutMetrics.s(52)), spacing: Space.m),
            count: 4)
        return LazyVGrid(columns: columns, spacing: Space.l) {
            ForEach(Array(Theme.memberColors.enumerated()), id: \.offset) { index, hex in
                let isChosen = chosenHex == hex
                Button {
                    Haptics.shared.tap()
                    onPick(hex)
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: LayoutMetrics.s(40), height: LayoutMetrics.s(40))
                        .overlay(Circle().strokeBorder(Papier.aufNacht.opacity(0.25),
                                                       lineWidth: Theme.hairlineWidth))
                        // The selection state: the un-chosen inks recede,
                        // the chosen well keeps its full body — and its
                        // ink runs as the STROKE on the letter sheet.
                        .opacity(chosenHex == nil || isChosen ? 1 : 0.3)
                        .scaleEffect(isChosen && !reduceMotion ? 1.12 : 1)
                }
                .buttonStyle(.plain)
                .minimumHitTarget()
                .accessibilityLabel(L10n.t("cinematic.ink.wellA11y",
                                           ["name": L10n.t(
                                                CinematicScript.inkWellNameKey(hex: hex)),
                                            "index": String(index + 1),
                                            "total": String(Theme.memberColors.count)]))
                .accessibilityAddTraits(isChosen ? [.isSelected] : [])
            }
        }
        .allowsHitTesting(chosenHex == nil)
        .accessibilityHidden(chosenHex != nil)
    }
}

// MARK: - Chapter 5 — Das Wachssiegel (the merge)

/// The blend pours into the wax seal (0–1.1 s) and embosses the heart ON
/// the merge beat — THE moment of the cinema, staged with the ceremony's
/// own curves (ease-out-back pop, a bloom ring across the room).
struct CinematicWaxSealStage: View {
    let t: Double
    /// The ink chapter's mix — falls back to the couple blend.
    let blend: Color?

    @Environment(\.coupleTint) private var coupleTint

    private var waxColor: Color { blend ?? coupleTint.blend }
    private var emboss: Double { CinematicStageMath.easeOutBack((t - 1.1) / 0.55) }

    var body: some View {
        let pour = CinematicStageMath.easeOut(t / 1.1)
        let breathe = t > 1.65 ? 1 + 0.02 * sin((t - 1.65) * 2.4) : 1
        ZStack {
            // The pour: a thin wax thread from above feeds the seal.
            if t < 1.2 {
                Capsule()
                    .fill(waxColor)
                    .frame(width: LayoutMetrics.s(6),
                           height: LayoutMetrics.s(110) * CGFloat(1 - pour))
                    .offset(y: -LayoutMetrics.s(120))
            }
            seal(pour: pour, breathe: breathe)
            // Final-Eval S2: the rings grow to ~680 pt — as a ZStack
            // SIBLING they inflated the stage's layout bounds and pushed
            // the skip/next chrome off the right edge. A zero-footprint
            // anchor renders them as pure overlay: the light expands,
            // the layout never moves.
            Color.clear
                .frame(width: 1, height: 1)
                .overlay { bloomRings }
                .allowsHitTesting(false)
        }
    }

    private func seal(pour: Double, breathe: Double) -> some View {
        // R2 (Artstil-Final-Eval S2): the ceremony presses the SAME material
        // seal the letters carry — seeded blob rim, embossed heart, matte
        // sheen (`WachsSiegel`) — instead of a flat glowing circle. The pour
        // scales the whole seal in as one object; a soft downward shadow
        // grounds it (no color glow: wax is matter, not light).
        WachsSiegel(seed: 0x4B_49_4E_4F, // "KINO" — stable ceremony pour
                    size: LayoutMetrics.s(120),
                    emboss: Typo.hero)
            .scaleEffect(CGFloat((0.3 + 0.7 * pour) * breathe))
            .shadow(color: Color.black.opacity(0.30 * pour),
                    radius: LayoutMetrics.s(14), y: LayoutMetrics.s(6))
    }

    /// The bloom claims the room — the ceremony's ring pair on the beat.
    @ViewBuilder
    private var bloomRings: some View {
        let life = (t - 1.1) / 1.2
        if life > 0, life < 1 {
            let eased = CinematicStageMath.easeOut(life)
            Circle()
                .strokeBorder(waxColor.opacity(0.55 * (1 - life)),
                              lineWidth: Theme.hairlineWidth * 2)
                .frame(width: LayoutMetrics.s(120) + LayoutMetrics.s(560) * CGFloat(eased),
                       height: LayoutMetrics.s(120) + LayoutMetrics.s(560) * CGFloat(eased))
        }
        let echo = (t - 1.35) / (1.2 + CinematicScript.mergeShimmerDuration)
        if echo > 0, echo < 1 {
            let eased = CinematicStageMath.easeOut(echo)
            Circle()
                .strokeBorder(waxColor.opacity(0.3 * (1 - echo)),
                              lineWidth: Theme.hairlineWidth)
                .frame(width: LayoutMetrics.s(120) + LayoutMetrics.s(450) * CGFloat(eased),
                       height: LayoutMetrics.s(120) + LayoutMetrics.s(450) * CGFloat(eased))
        }
    }
}

// MARK: - Chapter 6 Kurzfassung — Das leere Polaroid

/// An empty polaroid develops from white and STAYS empty — an
/// invitation, not a reproach (`.chime` exhales at 3.6 s on this path).
struct CinematicPolaroidStage: View {
    let t: Double

    var body: some View {
        let settle = CinematicStageMath.easeOut(t / 0.8)
        let develop = CinematicStageMath.smooth((t - 1.2) / 2.4)
        ZStack {
            polaroid(develop: develop)
                .offset(y: LayoutMetrics.s(16) * CGFloat(1 - settle))
                .opacity(settle)
        }
    }

    private func polaroid(develop: Double) -> some View {
        let frame = RoundedRectangle(cornerRadius: Radius.polaroid, style: .continuous)
        return VStack(spacing: Space.m) {
            // The photo area: white → the warm, waiting empty tone.
            Rectangle()
                .fill(.white)
                .overlay(Rectangle().fill(Papier.karton.opacity(develop)))
                .frame(width: LayoutMetrics.s(190), height: LayoutMetrics.s(190))
            // The caption strip stays blank — the first memory is theirs.
            Capsule()
                .fill(Papier.kante)
                .frame(width: LayoutMetrics.s(110), height: LayoutMetrics.s(6))
                .padding(.bottom, Space.s)
        }
        .padding(Space.m)
        .background(frame.fill(Papier.polaroid))
        .overlay(frame.strokeBorder(PaperLightEdge.gradient,
                                    lineWidth: Theme.hairlineWidth))
        .paperTilt(seed: 0x4E33_504F_4C41) // "N3POLA" — the scene's one tilt
        .elevation(.resting)
    }
}

// MARK: - Chapter 7 — Ankunft (the REAL hand-off)

/// The paper LAYS itself into the REAL first screen (Kino-Final-Eval
/// finding 1 — no mock, no crossfade cut): the guide is mounted UNDER
/// the cinema and reports the frames of its wordmark title and its three
/// entry cards through `CinematicHandoffFramesKey`. This finale lets its
/// papers fly onto EXACTLY those rects (`legen` signature — scale 1.04→1,
/// +6 pt→0, no rotation) while each paper morphs from letter paper with
/// ink into the REAL button rendering (the same styles and labels the
/// guide draws). When the cinema layer leaves, the pixels underneath are
/// identical — the mock BECOMES the original; the light never changes.
struct CinematicArrivalStage: View {
    let t: Double
    /// Measured guide frames in `CinematicHandoff.space` (== this stage's
    /// local space: both layers fill the same ZStack). Empty only if the
    /// guide could not be measured — then a centered fallback layout
    /// keeps the story intact.
    let targets: [CinematicHandoffElement: CGRect]

    private struct ArrivalCard {
        let element: CinematicHandoffElement
        let icon: String
        let titleKey: String
        /// Which real button rendering the paper becomes.
        let primary: Bool
    }

    private let cards: [ArrivalCard] = [
        ArrivalCard(element: .scan, icon: "qrcode.viewfinder",
                    titleKey: "onboarding.path.scan", primary: true),
        ArrivalCard(element: .server, icon: "server.rack",
                    titleKey: "onboarding.path.server", primary: false),
        ArrivalCard(element: .demo, icon: "sparkles",
                    titleKey: "onboarding.demo.enter", primary: false),
    ]

    var body: some View {
        GeometryReader { geo in
            let rise = CinematicStageMath.smooth((t - 0.4) / 0.8)
            let wordmarkRect = rect(for: .wordmark, in: geo.size)
            ZStack {
                // The wordmark rises exactly where the guide's hero title
                // rests — identical treatment (brandTitle), identical spot.
                Text(verbatim: "SoooDreamy")
                    .brandTitle()
                    .frame(width: wordmarkRect.width, height: wordmarkRect.height)
                    .position(x: wordmarkRect.midX,
                              y: wordmarkRect.midY
                                  + LayoutMetrics.s(14) * CGFloat(1 - CinematicStageMath.easeOut(rise)))
                    .opacity(rise)
                // The tagline is the cinema's own last line — it breathes
                // out before the swap; the guide's body lays in after.
                Text(L10n.t("cinematic.tagline"))
                    .font(Typo.label)
                    .foregroundStyle(Theme.textSecondary)
                    .position(x: wordmarkRect.midX,
                              y: wordmarkRect.maxY + LayoutMetrics.s(22))
                    .opacity(rise * (1 - CinematicStageMath.smooth((t - 4.4) / 0.7)))

                ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                    arrivalCard(card, index: index, in: geo.size)
                }
            }
        }
    }

    // MARK: One paper becomes one real card

    /// The paper flies from the desk center (where the polaroid rested)
    /// onto the card's REAL frame, lays down with the `legen` signature
    /// and dissolves its paper into the true button chrome.
    ///
    /// t57-Handoff (Gesamtbild-Eval S1): the words exist exactly ONCE —
    /// a single shared label rides ON TOP of the crossfading materials
    /// (letter paper below, real button chrome above), so the morph can
    /// never double or smear the text. Only the label's INK travels:
    /// from letter ink to the real button's label tone.
    @ViewBuilder
    private func arrivalCard(_ card: ArrivalCard, index: Int,
                             in size: CGSize) -> some View {
        let start = 1.2 + Double(index) * (Theme.Motion.Signature.legenStagger * 10)
        let laid = CinematicStageMath.easeOut((t - start) / 0.9)
        // The morph completes just after the landing settles.
        let morph = CinematicStageMath.smooth((t - start - 0.55) / 0.75)
        let target = rect(for: card.element, in: size)
        let from = CGPoint(x: size.width / 2,
                           y: size.height * 0.42 + LayoutMetrics.s(18) * CGFloat(index))
        let x = from.x + (target.midX - from.x) * CGFloat(CinematicStageMath.easeOut(laid))
        let y = from.y + (target.midY - from.y) * CGFloat(CinematicStageMath.easeOut(laid))
        ZStack {
            // The letter paper — material only, it carries no words…
            paperFace(height: target.height, morph: morph)
                .opacity(1 - morph)
            // …crossfading into the REAL button chrome (same styles as
            // the guide, its own label invisible — the shared label
            // above is the one set of words; inert, the living buttons
            // take over at the swap).
            realCardChrome(card)
                .opacity(morph)
            // THE one label — always fully opaque, only its ink morphs.
            sharedLabel(card, morph: morph)
        }
        .frame(width: target.width, height: target.height)
        .scaleEffect(1 + (Theme.Motion.Signature.legenScale - 1) * CGFloat(1 - laid))
        .position(x: x, y: y + Theme.Motion.Signature.legenOffsetY * CGFloat(1 - laid))
        .opacity(laid)
    }

    /// Blank letter paper — the "before" material of the morph. The
    /// corner radius relaxes from cut paper toward the button capsule
    /// while the morph runs. No words here: the shared label owns them.
    private func paperFace(height: CGFloat, morph: Double) -> some View {
        let radius = Radius.papier + (height / 2 - Radius.papier) * CGFloat(morph)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return shape.fill(Papier.brief)
            .overlay(shape.strokeBorder(PaperLightEdge.gradient,
                                        lineWidth: Theme.hairlineWidth))
            .elevation(.resting)
    }

    /// The true chrome the guide draws — same button styles, same
    /// metrics, but its own label rendered INVISIBLE (the shared label
    /// above is the one set of words). Hit-testing off — the REAL
    /// buttons live one layer below.
    @ViewBuilder
    private func realCardChrome(_ card: ArrivalCard) -> some View {
        if card.primary {
            Button {} label: {
                Label(L10n.t(card.titleKey), systemImage: card.icon)
                    .opacity(0)
            }
            .buttonStyle(PrimaryButtonStyle())
            .allowsHitTesting(false)
        } else {
            Button {} label: {
                Label(L10n.t(card.titleKey), systemImage: card.icon)
                    .opacity(0)
            }
            .buttonStyle(SecondaryButtonStyle())
            .allowsHitTesting(false)
        }
    }

    /// The ONE shared label of a card: set once in the REAL button's
    /// type (so the landed state is pixel-identical to the guide), its
    /// ink interpolating from letter ink to the button's label tone.
    private func sharedLabel(_ card: ArrivalCard, morph: Double) -> some View {
        let landedTone = card.primary ? Papier.brief : Theme.textPrimary
        return Label(L10n.t(card.titleKey), systemImage: card.icon)
            .font(.system(.headline, design: .rounded)
                .weight(card.primary ? .bold : .semibold))
            .foregroundStyle(Tinte.dunkel.mix(with: landedTone, by: morph))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, Space.m)
            .allowsHitTesting(false)
    }

    // MARK: Target frames — measured, with an honest fallback

    /// The guide's measured frame, or a centered stand-in mirroring the
    /// guide's page-0 layout (only if measurement never arrived — the
    /// story then still lands in plausible spots instead of collapsing).
    private func rect(for element: CinematicHandoffElement,
                      in size: CGSize) -> CGRect {
        if let measured = targets[element], measured.width > 1 {
            return measured
        }
        let columnWidth = min(size.width - Space.xxl * 2, LayoutMetrics.s(560))
        let buttonHeight = LayoutMetrics.s(50)
        let halfWidth = (columnWidth - LayoutMetrics.s(12)) / 2
        let centerX = size.width / 2
        switch element {
        case .wordmark:
            return CGRect(x: centerX - columnWidth / 2,
                          y: size.height * 0.30 - LayoutMetrics.s(24),
                          width: columnWidth, height: LayoutMetrics.s(48))
        case .scan:
            return CGRect(x: centerX - columnWidth / 2,
                          y: size.height * 0.62,
                          width: columnWidth, height: buttonHeight)
        case .server:
            return CGRect(x: centerX - columnWidth / 2,
                          y: size.height * 0.62 + buttonHeight + LayoutMetrics.s(12),
                          width: halfWidth, height: buttonHeight)
        case .demo:
            return CGRect(x: centerX + LayoutMetrics.s(6),
                          y: size.height * 0.62 + buttonHeight + LayoutMetrics.s(12),
                          width: halfWidth, height: buttonHeight)
        }
    }
}
