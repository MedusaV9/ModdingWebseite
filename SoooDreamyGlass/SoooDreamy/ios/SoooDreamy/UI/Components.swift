import SwiftUI
import UIKit

// MARK: - Avatar

struct EmojiAvatarView: View {
    let emoji: String?
    let colorHex: String?
    var size: CGFloat = 52
    var online: Bool? = nil
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(
                    // Fallback vor dem Kennenlernen: Siegellack, nie das
                    // tote Template-Lila (Re-Eval: violettes Herz im
                    // Accessory war das letzte Pink-Lila-Relikt).
                    LinearGradient(colors: [Color(hex: colorHex ?? PaperRules.wachsRotHex).opacity(0.95),
                                            Color(hex: colorHex ?? PaperRules.wachsRotHex).opacity(0.55)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5))
                .frame(width: size, height: size)
                .overlay {
                    if let emoji {
                        Text(emoji)
                            .font(.system(size: size * 0.52))
                    } else {
                        // SF-Herz in Brief-Ton statt Emoji-Fallback —
                        // Emojis bleiben Paar-Wahl, nie Chrome.
                        Image(systemName: "heart.fill")
                            .font(.system(size: size * 0.44))
                            .foregroundStyle(Color(hex: PaperRules.briefHex))
                    }
                }
            if let online {
                Circle()
                    .fill(online ? Theme.mint : Color.gray.opacity(0.7))
                    .frame(width: size * 0.26, height: size * 0.26)
                    .overlay(Circle().strokeBorder(Theme.bgTop, lineWidth: 2))
                    .overlay {
                        if differentiateWithoutColor {
                            Image(systemName: online ? "checkmark" : "xmark")
                                .font(.system(size: max(7, size * 0.11), weight: .black))
                                .foregroundStyle(Theme.bgTop)
                        }
                    }
            }
        }
    }
}

// MARK: - Section header

/// Quiet section header: the symbol keeps to text-secondary so sections
/// frame the couple's content instead of staging the app; only the
/// trailing action carries the couple's shared color as affordance.
/// `onPaper` switches the header to the ink family (Papier & Licht law:
/// on paper only Tinte.* text plus couple INK accents — the raw blend
/// stays a night/glass color).
struct SectionHeader: View {
    let title: String
    /// Optional SF Symbol shown before the title — hierarchical
    /// rendering keeps it quiet; purely decorative for VoiceOver.
    var systemImage: String? = nil
    var trailing: String? = nil
    var onTrailingTap: (() -> Void)? = nil
    /// True when the header sits on a paper card — text becomes ink.
    var onPaper: Bool = false

    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        HStack(spacing: Space.s) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    // Increased Contrast: the decorative icon firms up with
                    // the same token step as every secondary text.
                    .foregroundStyle(onPaper ? Tinte.sekundaer
                                     : Theme.Contrast.textSecondary(
                                        increased: colorSchemeContrast == .increased))
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(Typo.title)
                .foregroundStyle(onPaper ? Tinte.dunkel : Theme.textPrimary)
            Spacer()
            if let trailing {
                Button(action: { onTrailingTap?() }) {
                    Text(trailing)
                        .font(Typo.label)
                        .foregroundStyle(onPaper ? coupleTint.tinte : coupleTint.blend)
                }
            }
        }
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    /// An SF Symbol in the couple's tint, hierarchical — emoji is UI chrome
    /// here and violates commandment 1, so there is no emoji path anymore.
    let systemImage: String
    let title: String
    let subtitle: String
    /// W8: empty states are invitations, not dead ends — when the subtitle
    /// asks for an action, this button IS the way in.
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    @Environment(\.coupleTint) private var coupleTint

    init(systemImage: String, title: String, subtitle: String,
         actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: LayoutMetrics.s(10)) {
            Image(systemName: systemImage)
                .font(.system(.largeTitle).weight(.medium))
                .imageScale(.large)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(coupleTint.blend)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            Text(subtitle)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                }
                .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                .padding(.top, LayoutMetrics.s(6))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xxl)
        .padding(.horizontal, Space.xl)
    }
}

// MARK: - Loading

/// The ONE sanctioned in-control spinner (DESIGN.md, commandment 7):
/// spinners are legitimate ONLY inside buttons and compact controls for
/// sub-second actions — whole surfaces wait with `GlassSkeleton` shapes.
/// Features use this named control so "busy" has one look everywhere.
struct BusySpinner: View {
    var tint: Color = .white

    var body: some View {
        ProgressView()
            .tint(tint)
    }
}

/// Shared waiting state: skeleton lines in the rhythm of coming content
/// instead of an anonymous spinner (commandment 7 — "gleich da", not
/// "vielleicht nie"). Screens that know their layout compose
/// `GlassSkeleton` shapes directly.
struct LoadingView: View {
    var text: String = L10n.t("common.loading")

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            GlassSkeleton(kind: .line(width: LayoutMetrics.s(180)))
            GlassSkeleton(kind: .line())
            GlassSkeleton(kind: .line(width: LayoutMetrics.s(220)))
        }
        .padding(.horizontal, Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// The PAPER counterpart to `GlassSkeleton` — waiting shapes for surfaces
/// that already ARE paper (loading rows inside a paper card): matte
/// `Papier.innenFill` shapes with a `Papier.kante` hairline and a slow
/// warm light sweep (the lamp brushing the empty sheet). The glass
/// skeleton stays the night-surface variant; screens pick by ground.
/// `onNacht` renders the night-card variant (matte `nachtInnenFill`
/// wash, `Nacht.naht` hairline, warm lamp sweep) for skeletons inside
/// `nightCard()`s — the paper styling stays the default, so existing
/// call sites are untouched until their card flips (P2,
/// MIGRATION_DUNKEL.md). Reduce Motion: the sweep never starts — the
/// shapes wait still.
struct PaperSkeleton: View {
    enum Kind {
        /// A text row — capsule, default height 14.
        case line(width: CGFloat? = nil)
        /// An image/photo cell — rounded rect using `Radius.control`.
        case tile(height: CGFloat = 88)
        /// A whole card placeholder using `Radius.papier`.
        case card(height: CGFloat = 120)
    }

    var kind: Kind = .card()
    /// True when the skeleton waits inside a `nightCard()` — the shapes
    /// switch to the night washes so they stay visible on the dark card.
    var onNacht = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    private var fill: Color { onNacht ? Papier.nachtInnenFill : Papier.innenFill }
    private var line: Color { onNacht ? Nacht.naht : Papier.kante }
    private var sweepLight: Color {
        onNacht ? Papier.nachtLichtkante.opacity(0.6)
                : Papier.lichtkante.opacity(0.7)
    }

    var body: some View {
        base
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, sweepLight, .clear],
                            startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.6)
                            .offset(x: sweep ? geo.size.width : -geo.size.width * 0.6)
                    }
                    .clipShape(sweepClip)
                }
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(Theme.Motion.drift(1.4).repeatForever(autoreverses: false)) {
                    sweep = true
                }
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    @ViewBuilder private var base: some View {
        switch kind {
        case .line(let width):
            Capsule()
                .fill(fill)
                .overlay(Capsule().strokeBorder(line,
                                                lineWidth: Theme.hairlineWidth))
                .frame(width: width, height: LayoutMetrics.s(14))
        case .tile(let height):
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(fill)
                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(line, lineWidth: Theme.hairlineWidth))
                .frame(height: LayoutMetrics.s(height))
        case .card(let height):
            RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                .fill(fill)
                .overlay(RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                    .strokeBorder(line, lineWidth: Theme.hairlineWidth))
                .frame(height: LayoutMetrics.s(height))
        }
    }

    private var sweepClip: AnyShape {
        switch kind {
        case .line: return AnyShape(Capsule())
        case .tile: return AnyShape(RoundedRectangle(cornerRadius: Radius.control,
                                                     style: .continuous))
        case .card: return AnyShape(RoundedRectangle(cornerRadius: Radius.papier,
                                                     style: .continuous))
        }
    }
}

// MARK: - Paper input field (ON paper cards)

/// The paper counterpart of `DreamyFieldStyle` (which is night chrome):
/// an input line ON a paper card — matte ink wash, kante hairline, dark
/// ink, and a caret in the couple's shared ink. Apply directly to a
/// `TextField` that sits inside a `paperCard`.
struct PaperFieldModifier: ViewModifier {
    @Environment(\.coupleTint) private var coupleTint

    func body(content: Content) -> some View {
        content
            .font(Typo.body)
            .foregroundStyle(Tinte.dunkel)
            .tint(coupleTint.tinte)
            .padding(.vertical, LayoutMetrics.s(13))
            .padding(.horizontal, Space.l)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Papier.innenFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .strokeBorder(Papier.kante, lineWidth: Theme.hairlineWidth))
            )
    }
}

extension View {
    /// Ink-on-paper input treatment for text fields inside paper cards.
    func paperField() -> some View {
        modifier(PaperFieldModifier())
    }
}

// MARK: - Poststempel (the third signature artifact)

/// The postmark: a dashed double circle Ø 56 pt carrying a
/// `Typo.anschrift` line (the ONE small-caps role) in faded stamp ink —
/// date/metadata embossing on paper (STYLE_DECISION §3.6, "TAG {n}").
/// Rotation −8° is part of the stamp's identity and counts as the ONE
/// rotated element of its screen; purely decorative for VoiceOver (the
/// carrying card announces the number). Above accessibility sizes the
/// line drops small caps via `Typo.anschrift` and the stamp stops
/// growing — decor never displaces text.
struct Poststempel: View {
    let text: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var diameter: CGFloat { LayoutMetrics.s(56) }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .padding(LayoutMetrics.s(5))
            Text(text)
                .font(Typo.anschrift(
                    isAccessibilitySize: dynamicTypeSize.isAccessibilitySize))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, LayoutMetrics.s(9))
        }
        .foregroundStyle(Tinte.sekundaer.opacity(0.7))
        .frame(width: diameter, height: diameter)
        .rotationEffect(.degrees(-8))
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

// MARK: - Wachssiegel (the first signature artifact — wax as MATERIAL)

/// The wax body outline: a circle whose edge is softly, seededly
/// deformed — poured wax never dries into a perfect circle. The jitter
/// comes from the PaperRules RNG (stable item seed, never flickers) and
/// stays subtle: amplitude ~5 % of the radius, smoothed through
/// midpoint quad curves so the rim reads organic, not spiky.
struct WachsBlobShape: Shape {
    var seed: UInt64
    /// Control points around the rim — enough for soft undulation.
    var points = 10
    /// Radial jitter as a fraction of the radius.
    var amplitude = 0.05

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let base = min(rect.width, rect.height) / 2
        let rim: [CGPoint] = (0..<points).map { index in
            let jitter = (PaperRules.unitRandom(seed: seed, index: index) * 2 - 1)
                * amplitude
            // 1 − amplitude keeps every bump inside the frame.
            let radius = base * (1 - amplitude + jitter)
            let angle = Double(index) / Double(points) * 2 * .pi
            return CGPoint(x: center.x + CGFloat(cos(angle)) * radius,
                           y: center.y + CGFloat(sin(angle)) * radius)
        }
        guard rim.count > 2 else { return Path(ellipseIn: rect) }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        var path = Path()
        path.move(to: mid(rim[points - 1], rim[0]))
        for index in 0..<points {
            path.addQuadCurve(to: mid(rim[index], rim[(index + 1) % points]),
                              control: rim[index])
        }
        path.closeSubpath()
        return path
    }
}

/// THE material wax seal (FullRelease R1-A — consolidates the flat
/// `ChatWaxSealView` disc and the Memories `WachsSiegelBadge` sketch
/// into ONE UI-layer building block; the chat view now delegates here):
/// a poured DEEP wax body (nacht-first P1-A: `Wachs.dunkel` →
/// `coupleTint.wachsTief` — the pale gold-era gradient washed the seal
/// peach and forced a near-black stamp, the Kino freeze proof case)
/// with a seeded irregular rim (never a perfect circle), a rim
/// light/shade that gives the pour thickness, the heart embossing
/// pressed IN as a relief (shadowed upper lip, lamplit lower lip on the
/// dark wax) and one SUBTLE matte highlight where the 10-o'clock lamp
/// brushes the wax. Material, not glow — the only shadow is the neutral
/// elevation. The embossing ink is `coupleTint.aufWachs` — LIGHT, and
/// judged against BOTH deep-wax stops (pinned matrix; same worst-stop
/// law as the retired gold-era stamp). Rotation is NOT built in:
/// callers spend their screen's one `paperTilt` budget deliberately.
struct WachsSiegel: View {
    /// Stable seed for the rim deformation — item id where there is
    /// one; the shared default keeps chrome seals identical app-wide.
    var seed: UInt64 = 0x53_49_45_47_45_4C // "SIEGEL"
    var size: CGFloat = LayoutMetrics.s(44)
    /// Embossing glyph role — follows the seal size semantically.
    var emboss: Font = .system(.footnote, design: .rounded).weight(.bold)

    @Environment(\.coupleTint) private var coupleTint

    var body: some View {
        let shape = WachsBlobShape(seed: seed)
        ZStack {
            shape.fill(
                LinearGradient(colors: [Wachs.dunkel, coupleTint.wachsTief],
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing))
            // Rim thickness: the lamp catches the upper-left lip of the
            // pour, the lower-right edge falls into its own shade.
            shape.stroke(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.30), location: 0),
                        .init(color: .clear, location: 0.45),
                        .init(color: Color.black.opacity(0.32), location: 1),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1)
            // Matte sheen — subtle on the deep wax: a quiet catch of
            // light, never a hard specular (nacht-first: 0.14).
            Ellipse()
                .fill(
                    RadialGradient(colors: [.white.opacity(0.14), .clear],
                                   center: .center,
                                   startRadius: 0, endRadius: size * 0.22))
                .frame(width: size * 0.42, height: size * 0.30)
                .offset(x: -size * 0.16, y: -size * 0.20)
            embossedHeart
        }
        .frame(width: size, height: size)
        .elevation(.resting)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    /// The pressed-in heart on DEEP wax: the recess's upper lip falls
    /// into shadow, the lower lip catches the 10-o'clock lamp
    /// (eingedrückt), with the LIGHT verdict-secured stamp ink between.
    private var embossedHeart: some View {
        let lip = max(0.5, size * 0.025)
        return ZStack {
            Image(systemName: "heart.fill")
                .font(emboss)
                .foregroundStyle(Color.black.opacity(0.35))
                .offset(y: -lip)
            Image(systemName: "heart.fill")
                .font(emboss)
                .foregroundStyle(.white.opacity(0.22))
                .offset(y: lip)
            Image(systemName: "heart.fill")
                .font(emboss)
                .foregroundStyle(coupleTint.aufWachs)
        }
    }
}

// MARK: - Briefbogen dressing (band + postmark for THE hero card)

/// The Briefbogen decor riding the ONE hero paper card of a screen
/// (STYLE_DECISION §3.3: paper + band + WAX SEAL): the couple's band
/// (`coupleTint.band`, `Papier.bandBreite`) wrapped horizontally just
/// under the top cut, the material `WachsSiegel` pressed onto the band
/// near its leading end (FullRelease R1-A — the hero finally carries
/// the seal the direction defines), plus an optional `Poststempel`
/// hanging over the top-trailing corner. All are overlay decor without
/// layout contribution (AX law: text never displaces a seal, a seal
/// never displaces text). The seal stays unrotated here — the stamp's
/// −8° already spends the screen's rotation budget. Apply ON TOP of
/// `paperCard(.briefbogen)`.
///
/// Fix2-A №1: the seal hangs INTO the sheet's top-left corner, exactly
/// where the Stempelzeile prints — decor must never eat information
/// („TAGESPOST" → „TA…POST"). Cards that print inside the seal's row
/// indent that line by `stempelEinzug(contentPadding:)` (below), the
/// named counterpart of the rendered geometry here.
struct BriefbogenDekor: ViewModifier {
    /// Postmark line, e.g. the "TAG {n}" embossing — nil for band only.
    var stamp: String?
    /// False renders the plain card untouched — lets a card that is only
    /// SOMETIMES the hero keep one code path.
    var active = true
    /// Stable seed for the seal's rim deformation — screens with an item
    /// identity pass it; the shared default keeps generic heroes calm.
    var seed: UInt64 = 0x42_52_49_45_46 // "BRIEF"

    @Environment(\.coupleTint) private var coupleTint

    /// Wax-seal diameter on the band — static so the rendered seal and
    /// the Stempelzeilen-Einzug below can never drift apart.
    static var sealSize: CGFloat { LayoutMetrics.s(40) }

    /// Horizontal room the seal claims from the sheet's OUTER leading
    /// edge: its leading inset, the wax body, and one breath of air.
    static var siegelUeberhang: CGFloat { Space.xl + sealSize + Space.s }

    /// Leading inset a stamp line inside a card with `contentPadding`
    /// needs so it starts clear of the overhanging seal (Fix2-A №1).
    static func stempelEinzug(contentPadding: CGFloat) -> CGFloat {
        max(0, siegelUeberhang - contentPadding)
    }

    private var sealSize: CGFloat { Self.sealSize }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if active {
                    // Band and seal move as ONE piece: the wax is poured
                    // where the band crosses the sheet.
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(coupleTint.band)
                            .frame(height: Papier.bandBreite)
                        WachsSiegel(seed: seed, size: sealSize)
                            .padding(.leading, Space.xl)
                    }
                    // Band top stays below the corner cut so it hugs the
                    // sheet; the seal overhangs it symmetrically.
                    .offset(y: Radius.papier - (sealSize - Papier.bandBreite) / 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .topTrailing) {
                if active, let stamp {
                    Poststempel(text: stamp)
                        .offset(x: LayoutMetrics.s(8), y: -LayoutMetrics.s(12))
                }
            }
    }
}

extension View {
    /// Dresses the screen's ONE `paperCard(.briefbogen)` hero with the
    /// couple band, the wax seal and (optionally) the "TAG {n}" postmark.
    func briefbogenDekor(stamp: String? = nil, active: Bool = true,
                         seed: UInt64 = 0x42_52_49_45_46) -> some View {
        modifier(BriefbogenDekor(stamp: stamp, active: active, seed: seed))
    }
}

// MARK: - Blättern & Legen (paper entry signatures)

/// Blättern — the hero/screen entry: the sheet rotates in around its
/// leading edge (Signature.blaetternDegrees → 0°, anchor `.leading`,
/// perspective Signature.blaetternPerspective), driven by
/// `Theme.Motion.blaettern`. Reduce Motion: a pure crossfade — the
/// rotation never engages.
struct BlaetternEntry: ViewModifier {
    @Environment(\.motionGate) private var motionGate
    @State private var arrived = false

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(arrived || motionGate.reduceMotion
                         ? 0 : Theme.Motion.Signature.blaetternDegrees),
                axis: (x: 0, y: 1, z: 0), anchor: .leading,
                perspective: Theme.Motion.Signature.blaetternPerspective)
            .opacity(arrived ? 1 : 0)
            .onAppear {
                withAnimation(Theme.Motion.blaettern) { arrived = true }
            }
    }
}

/// Legen — elements appear in the existing stack: the Zettel lands
/// (scale 1.04 → 1, y-offset 6 → 0), staggered by `legenStagger` for at
/// most `legenBudget` elements. Reduce Motion: fade without transform.
struct LegenEntry: ViewModifier {
    /// Stagger position in the arriving group (0-based, capped at the
    /// legenBudget — later elements land together with the sixth).
    var index = 0

    @Environment(\.motionGate) private var motionGate
    @State private var landed = false

    func body(content: Content) -> some View {
        let still = motionGate.reduceMotion
        content
            .scaleEffect(landed || still ? 1 : Theme.Motion.Signature.legenScale)
            .offset(y: landed || still ? 0 : Theme.Motion.Signature.legenOffsetY)
            .opacity(landed ? 1 : 0)
            .onAppear {
                guard !still else {
                    withAnimation(Theme.Motion.legen) { landed = true }
                    return
                }
                let slot = min(index, Theme.Motion.Signature.legenBudget - 1)
                withAnimation(Theme.Motion.legen
                    .delay(Theme.Motion.Signature.legenStagger * Double(slot))) {
                    landed = true
                }
            }
    }
}

extension View {
    /// Hero/screen entry on the Blättern signature (Reduce Motion: fade).
    func blaetternEntry() -> some View {
        modifier(BlaetternEntry())
    }

    /// Staggered element entry on the Legen signature (Reduce Motion:
    /// fade without transform).
    func legenEntry(index: Int = 0) -> some View {
        modifier(LegenEntry(index: index))
    }
}

// MARK: - Lichtschein (celebration glow — replaces confetti on levels 1–2)

/// The Lichtschein signature: a radial `Licht.lampengold` glow blooming
/// behind a celebrating element (opacity 0 → peak → rest, radius 0 →
/// 1.4 × size) and then STAYING — the moment remains lit. Parameters are
/// the named `Theme.Motion.Signature` values; Reduce Motion shows the
/// static end glow immediately (a painting, not a black hole).
struct LichtscheinGlow: View {
    /// Diameter of the celebrated element — the glow blooms to 1.4 ×.
    var size: CGFloat = 120

    @Environment(\.motionGate) private var motionGate
    /// 0 = dark, 1 = peak bloom, 2 = resting end glow.
    @State private var phase = 0

    private var radius: CGFloat {
        size * Theme.Motion.Signature.lichtscheinRadiusFactor
    }

    private var opacity: Double {
        switch phase {
        case 1: return Theme.Motion.Signature.lichtscheinPeakOpacity
        case 2: return Theme.Motion.Signature.lichtscheinRestOpacity
        default: return 0
        }
    }

    var body: some View {
        RadialGradient(colors: [Licht.lampengold.opacity(opacity), .clear],
                       center: .center, startRadius: 0, endRadius: radius)
            .frame(width: radius * 2, height: radius * 2)
            .scaleEffect(phase == 0 ? 0.01 : 1)
            .onAppear {
                guard !motionGate.reduceMotion else {
                    // Reduce Motion: the painting is lit from the start.
                    phase = 2
                    return
                }
                withAnimation(Theme.Motion.lichtschein) { phase = 1 }
                Task {
                    // Choreography pause, not a swallowed error: after the
                    // bloom the glow settles to its resting brightness.
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    withAnimation(Theme.Motion.settle) { phase = 2 }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

enum StateNoticeKind {
    case empty
    case offline
    case failed

    /// SF Symbols, not emoji — state chrome answers to tint and weight
    /// (commandment 1).
    var systemImage: String {
        switch self {
        case .empty: return "sparkles"
        case .offline: return "antenna.radiowaves.left.and.right.slash"
        case .failed: return "lifepreserver"
        }
    }
}

/// Shared full state for a server-backed surface. A retry is always reachable
/// for transport failures and remains a 44-point native button.
struct StateNoticeView: View {
    let kind: StateNoticeKind
    let title: String
    let message: String
    var retry: (() -> Void)? = nil

    @Environment(\.coupleTint) private var coupleTint

    var body: some View {
        VStack(spacing: Space.m) {
            Image(systemName: kind.systemImage)
                .font(.system(.largeTitle).weight(.medium))
                .imageScale(.large)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(kind == .empty ? coupleTint.blend : Theme.textSecondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            if let retry {
                Button(L10n.t("common.retry"), action: retry)
                    .buttonStyle(PrimaryButtonStyle(fullWidth: false))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xxl)
        .padding(.horizontal, Space.xl)
    }
}

// MARK: - Toast

struct Toast: Equatable {
    enum Style { case info, success, error, love }
    let text: String
    var style: Style = .info

    var tint: Color {
        switch style {
        case .info: return Theme.blue
        case .success: return Theme.mint
        case .error: return Theme.energyRed
        case .love: return Theme.pink
        }
    }

    var icon: String {
        switch style {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .love: return "heart.fill"
        }
    }
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: LayoutMetrics.s(10)) {
            Image(systemName: toast.icon)
                .foregroundStyle(toast.tint)
            Text(toast.text)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
        }
        .padding(.vertical, LayoutMetrics.s(12))
        .padding(.horizontal, LayoutMetrics.s(18))
        // Chrome glass (carries its own floating elevation); the tint ring
        // stays — it is the toast's state color, not a specular stroke.
        .glass(.chrome, in: Capsule())
        .overlay(Capsule().strokeBorder(toast.tint.opacity(0.5),
                                        lineWidth: Theme.hairlineWidth))
        .padding(.horizontal, Space.xl)
    }
}

// MARK: - Floating hearts (celebrations, incoming touches)

struct FloatingHeartsView: View {
    var emojis: [String] = ["💜", "💖", "💗", "✨", "💞"]
    var count: Int = 18
    var startedAt = Date()

    /// Reduce Motion: the celebration holds still — one soft couple-tint
    /// glow instead of an endless particle timeline (commandment 13; the
    /// A11y eval found this canvas running unconditionally).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.coupleTint) private var coupleTint

    private struct Particle {
        let x: CGFloat
        let delay: Double
        let speed: Double
        let size: CGFloat
        let sway: CGFloat
        let emojiIndex: Int
    }

    private var particles: [Particle] {
        var seed: UInt64 = 0xC0FFEE
        func rnd() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
        }
        return (0..<count).map { i in
            Particle(x: 0.05 + rnd() * 0.9,
                     delay: Double(rnd()) * 1.4,
                     speed: 0.55 + Double(rnd()) * 0.8,
                     size: LayoutMetrics.s(18 + rnd() * 22),
                     sway: LayoutMetrics.s(14 + rnd() * 26),
                     emojiIndex: i % emojis.count)
        }
    }

    var body: some View {
        Group {
            if reduceMotion {
                staticGlow
            } else {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        let t = timeline.date.timeIntervalSince(startedAt)
                        for p in particles {
                            let life = (t - p.delay) * p.speed
                            guard life > 0 else { continue }
                            let progress = life.truncatingRemainder(dividingBy: 1.0)
                            let y = size.height * (1.05 - CGFloat(progress) * 1.15)
                            let x = p.x * size.width + sin(life * 4) * p.sway
                            let alpha = progress < 0.15 ? progress / 0.15 : (1 - progress)
                            let resolved = context.resolve(Text(emojis[p.emojiIndex]).font(.system(size: p.size)))
                            context.opacity = alpha
                            context.draw(resolved, at: CGPoint(x: x, y: y))
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        // Purely decorative — the accompanying overlay text/toast carries
        // the meaning for VoiceOver.
        .accessibilityHidden(true)
    }

    /// The Reduce-Motion stand-in: a still, centered aura in the couple's
    /// shared color — festive without a single moving part.
    private var staticGlow: some View {
        RadialGradient(colors: [coupleTint.blend.opacity(0.35), .clear],
                       center: .center,
                       startRadius: 0,
                       endRadius: LayoutMetrics.s(260))
    }
}

// MARK: - Connection banner

/// Compact socket-status pill (polish): a softly pulsing dot while
/// connecting, a clear wifi-slash badge while offline (the socket retries
/// on its own) and a short mint "Verbunden" flash right after a reconnect.
struct ConnectionBanner: View {
    let state: SocketState
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    /// True for a moment right after a reconnect — flashes the mint
    /// confirmation before the banner fades back to nothing.
    @State private var showReconnected = false
    @State private var reconnectFlashTask: Task<Void, Never>?

    var body: some View {
        Group {
            switch state {
            case .connected:
                if showReconnected {
                    label(L10n.t("conn.connected"), color: Theme.mint, icon: "checkmark")
                }
            case .connecting:
                label(L10n.t("conn.connecting"), color: Theme.gold, pulsing: true)
            case .disconnected:
                label(L10n.t("conn.offline"), color: Theme.energyRed, icon: "wifi.slash",
                      a11y: L10n.t("conn.offline.a11y"))
            }
        }
        .animation(Theme.Motion.settle, value: state)
        .animation(Theme.Motion.settle, value: showReconnected)
        .onChange(of: state) { oldValue, newValue in
            reconnectFlashTask?.cancel()
            guard newValue == .connected, oldValue != .connected else {
                showReconnected = false
                return
            }
            showReconnected = true
            reconnectFlashTask = Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard !Task.isCancelled else { return }
                showReconnected = false
            }
        }
    }

    /// The pill is a status word, never a paragraph: one line, natural
    /// size, no hyphenation — longer phrasing belongs in `a11y`, which
    /// VoiceOver reads instead of the visible word.
    private func label(_ text: String, color: Color,
                       icon: String? = nil, pulsing: Bool = false,
                       a11y: String? = nil) -> some View {
        HStack(spacing: 7) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(color)
            } else {
                if differentiateWithoutColor {
                    Image(systemName: "ellipsis")
                        .font(.system(.caption2, design: .rounded).weight(.black))
                        .foregroundStyle(color)
                } else {
                    ConnectionStatusDot(color: color, pulsing: pulsing)
                }
            }
            Text(text)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, LayoutMetrics.s(13))
        // Floating status chrome = real system glass (FullRelease R1-A —
        // the hand-painted black capsule was the last pseudo-glass in the
        // headers); the tint ring stays as the pill's STATE color, the
        // same pattern as the toast (never a specular rebuild).
        .glass(.chrome, in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.40),
                                        lineWidth: Theme.hairlineWidth))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y ?? text)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }
}

/// Status dot with an optional expanding-ring pulse (while connecting).
private struct ConnectionStatusDot: View {
    let color: Color
    var pulsing = false

    @Environment(\.motionGate) private var motionGate
    @State private var animating = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(color.opacity(0.7), lineWidth: 1.5)
                    .scaleEffect(animating ? 2.2 : 1)
                    .opacity(animating ? 0 : 0.8)
            )
            .onAppear {
                // Reduce Motion: the dot alone says "connecting" — no
                // endlessly expanding ring.
                guard pulsing, motionGate.particlesEnabled else { return }
                withAnimation(Theme.Motion.drift(1).repeatForever(autoreverses: false)) {
                    animating = true
                }
            }
    }
}

// MARK: - Emoji picker row

struct EmojiPickerGrid: View {
    let emojis: [String]
    @Binding var selection: String

    @Environment(\.coupleTint) private var coupleTint

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s), count: 6),
                  spacing: Space.s) {
            ForEach(emojis, id: \.self) { e in
                Button {
                    selection = e
                    Haptics.shared.tap()
                } label: {
                    Text(e)
                        .font(.system(.title, design: .rounded))
                        .frame(width: LayoutMetrics.s(46), height: LayoutMetrics.s(46))
                        .background(
                            Circle().fill(selection == e ? coupleTint.blend.opacity(0.35)
                                                         : Theme.innerFill)
                        )
                        .overlay(
                            Circle().strokeBorder(selection == e ? coupleTint.blend : .clear, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("pairing.avatarPickA11y", ["emoji": e]))
                .accessibilityAddTraits(selection == e ? [.isSelected] : [])
            }
        }
    }
}

// MARK: - Color picker row

struct MemberColorPicker: View {
    @Binding var selection: String

    /// VoiceOver names for `Theme.memberColors` — a silent colored circle
    /// is unusable for a blind partner (EVAL P2-9).
    private static let colorNameKeys: [String: String] = [
        "FF5C8A": "color.rose", "A855F7": "color.purple",
        "6366F1": "color.indigo", "60A5FA": "color.sky",
        "6EE7B7": "color.mint", "FFD166": "color.gold",
        "FB923C": "color.orange", "F87171": "color.coral",
    ]

    var body: some View {
        HStack(spacing: LayoutMetrics.s(12)) {
            ForEach(Theme.memberColors, id: \.self) { hex in
                Button {
                    selection = hex
                    Haptics.shared.tap()
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: LayoutMetrics.s(34), height: LayoutMetrics.s(34))
                        .overlay(
                            Circle().strokeBorder(.white, lineWidth: selection == hex ? 3 : 0)
                        )
                        .shadow(color: Color(hex: hex).opacity(0.6), radius: selection == hex ? 8 : 0)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t(
                    "pairing.colorPickA11y",
                    ["name": L10n.t(Self.colorNameKeys[hex] ?? "pairing.color")]))
                .accessibilityAddTraits(selection == hex ? [.isSelected] : [])
            }
        }
    }
}

// MARK: - Pill tag

struct PillTag: View {
    let text: String
    var tint: Color = Theme.purple
    /// True when the pill sits on a paper card: the label becomes dark
    /// ink (paper law — the tint wash stays material, never the text).
    var onPaper: Bool = false

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        let increased = colorSchemeContrast == .increased
        Text(text)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(onPaper ? Tinte.dunkel : Theme.textPrimary)
            .padding(.vertical, 5)
            .padding(.horizontal, LayoutMetrics.s(11))
            .background(
                // Increased Contrast: firmer wash + an edge line, via the
                // central Theme.Contrast tokens (no raw values here).
                Capsule()
                    .fill(Theme.Contrast.tintFill(tint, increased: increased))
                    .overlay {
                        if increased || onPaper {
                            Capsule().strokeBorder(
                                onPaper ? Papier.kante
                                        : Theme.Contrast.hairline(increased: true),
                                lineWidth: Theme.hairlineWidth)
                        }
                    }
            )
    }
}

// MARK: - Authenticated remote media

/// Header-authenticated equivalent of `AsyncImage`. Bearer tokens never enter
/// URLs, caches, screenshots, proxy logs or sharing sheets.
struct AuthenticatedAsyncImage<Content: View>: View {
    let api: API?
    let path: String?
    /// Decode budget in pixels — grids can pass a smaller budget so cells
    /// never pay for (or cache) full-screen bitmaps.
    var maxPixelSize = 2_048
    private let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty

    init(api: API?, path: String?, maxPixelSize: Int = 2_048,
         @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.api = api
        self.path = path
        self.maxPixelSize = maxPixelSize
        self.content = content
    }

    var body: some View {
        content(phase)
            .task(id: path) {
                guard let api, let path else {
                    phase = .empty
                    return
                }
                // Cache hit renders synchronously — recycled grid cells and
                // reopened screens never flash empty for a resident image.
                if let cached = ImagePipeline.shared.cachedImage(
                    baseURL: api.baseURL, path: path, maxPixelSize: maxPixelSize) {
                    phase = .success(Image(uiImage: cached))
                    return
                }
                phase = .empty
                do {
                    // Fetch + decode + downsample run off the main thread in
                    // the shared pipeline (with in-flight coalescing).
                    let image = try await ImagePipeline.shared.image(
                        api: api, path: path, maxPixelSize: maxPixelSize)
                    phase = .success(Image(uiImage: image))
                } catch {
                    if !(error is CancellationError) {
                        phase = .failure(error)
                    }
                }
            }
    }
}
