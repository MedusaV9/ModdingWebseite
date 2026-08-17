import SwiftUI
import UIKit

// The two materials of the app (DESIGN.md, Zwei-Materialien-Gesetz):
//
//   GLASS floats — `GlassLevel.chrome` is real system glass for
//   everything that hovers: native tab bar, FAB, input bars, toolbar
//   pills, sheet chrome, toasts. The system renders refraction and edge;
//   content scrolls through underneath.
//
//   PAPER lies — `PaperLevel` (nachtkarton/brief/karton/polaroid/
//   briefbogen) is the opaque, matte content material: cards, chat
//   Zettel, game boards, polaroids, lists. Elevation shadow down-right,
//   1-pt light edge top-left — the lamp is the one light source.
//   Nacht-first: the STANDARD card is dark `nachtkarton` (nightCard());
//   light paper is reserved for the hero/artifact moments.
//
// The legacy glass levels `.surface`/`.tinted` stay FUNCTIONAL while the
// screen waves migrate (~323 `glassCard` call sites, ratchet
// `surface_glass_features` counts them to 0) but are DEPRECATED: real
// system glass belongs to the floating chrome only.
//
// Prohibitions (enforced in review, see DESIGN.md):
//   * Glass on glass is forbidden. Surfaces inside a glass card are matte
//     fills (`Theme.innerFill`), never a second material.
//   * PAPER ON GLASS is forbidden — paper always lies UNDER the chrome.
//     The one sanctioned touch point is the system tab-view accessory.
//   * Never rebuild glass on top of glass: no ultraThinMaterial layers,
//     refraction gradients or specular strokes painted over `glassEffect` —
//     the system material renders all of that itself.
//   * Inner surfaces ON PAPER are `Papier.innenFill` washes with a
//     `Papier.kante` hairline — never a second material.
//   * Colored glow shadows belong to `.tinted` panes and top-tier
//     celebrations only; everything else casts a neutral elevation shadow.
//
// Accessibility contract of the system material (why there is no manual
// glass fallback in this file):
//   * Reduce Transparency — the SYSTEM replaces every `glassEffect` (and the
//     `.glass`/`.glassProminent` button styles) with a near-opaque platter
//     on its own. Facade levels therefore never need a hand-rolled
//     `Theme.innerFill` swap; manual intervention is only required where a
//     feature paints translucency itself (matte fills on opaque backdrops
//     are fine and stay).
//   * Increased Contrast — system glass strengthens its own edge line.
//   * Reduce Motion — glass morphs (`glassEffectID`) only animate through
//     the animation that drives the state change; callers gate ornamental
//     morphs with `accessibilityReduceMotion` (functional state changes may
//     switch instantly instead).

enum GlassLevel {
    /// Floating controls & chrome: tab bar, FAB, input bars, pills,
    /// round toolbar buttons — the ONE material for everything that
    /// floats above content (never rebuild it with `ultraThinMaterial`).
    case chrome
    /// DEPRECATED (Zwei-Materialien-Gesetz): content that lies is opaque
    /// paper now — new cards use `PaperLevel.brief` via `paperCard()`.
    /// Stays functional while the screen waves migrate the existing
    /// call sites; never adopt it in new code.
    case surface
    /// DEPRECATED (Zwei-Materialien-Gesetz): the couple-color hero pane
    /// becomes the Briefbogen card (`PaperLevel.briefbogen` — paper +
    /// band + wax seal, exactly one per screen). Stays functional while
    /// the screen waves migrate; never adopt it in new code.
    case tinted(Color)

    /// The real iOS-26 material for this level.
    var material: Glass {
        switch self {
        case .chrome: return .regular
        case .surface: return .regular
        case .tinted(let color): return .regular.tint(color.opacity(0.35))
        }
    }

    var elevation: Elevation {
        switch self {
        case .chrome: return .floating
        case .surface: return .resting
        case .tinted: return .raised
        }
    }
}

/// Shadow tokens implementing the one light source of the app: light comes
/// from the 10-o'clock position, so shadows fall down and slightly right.
/// The farther a pane floats above the aurora, the softer and larger its
/// shadow. These are the ONLY drop shadows features may use.
enum Elevation {
    /// Content cards lying on the background.
    case resting
    /// Hero/tinted panes lifted a step above their siblings.
    case raised
    /// Chrome floating above everything (tab bar, FAB, overlays).
    case floating

    var color: Color {
        switch self {
        case .resting: return .black.opacity(0.22)
        case .raised: return .black.opacity(0.26)
        case .floating: return .black.opacity(0.30)
        }
    }

    var radius: CGFloat {
        switch self {
        case .resting: return LayoutMetrics.s(14)
        case .raised: return LayoutMetrics.s(16)
        case .floating: return LayoutMetrics.s(16)
        }
    }

    var offset: CGSize {
        switch self {
        case .resting: return CGSize(width: LayoutMetrics.s(1), height: LayoutMetrics.s(6))
        case .raised: return CGSize(width: LayoutMetrics.s(2), height: LayoutMetrics.s(6))
        case .floating: return CGSize(width: LayoutMetrics.s(2), height: LayoutMetrics.s(7))
        }
    }
}

// MARK: - Glass regions (GlassEffectContainer facade)

/// Named blend distances for `GlassGroup` regions — the only sanctioned
/// spacing values for `GlassEffectContainer`. The value is the distance at
/// which neighboring glass panes start melting into one another. Pick the
/// token BELOW the cluster's resting gaps: panes parked at or inside the
/// blend distance melt PERMANENTLY (the CI-verified lens-in-beam smear) —
/// resting panes must stay fully distinct, and only panes in transit
/// (appearing, disappearing, moving) cross the threshold.
enum GlassSpacing {
    /// Blends across `Space.s` — for clusters resting on `Space.m`+ gaps.
    case tight
    /// Blends across `Space.m` — for clusters resting on `Space.l`+ gaps.
    case grouped

    var value: CGFloat {
        switch self {
        case .tight: return Space.s
        case .grouped: return Space.m
        }
    }
}

/// The sanctioned wrapper around `GlassEffectContainer`: one `GlassGroup`
/// = one render region. Every glass pane inside renders in a single system
/// pass (instead of N standalone effects), neighboring panes blend when
/// they come closer than the named spacing, and `glassEffectID` morphs can
/// only happen between panes of the same group. Views pick a `GlassSpacing`
/// name — raw container values stay in this file.
///
/// Group-usage rules (CI-screenshot-verified on iOS 26):
///   * The consolidated pass can land ABOVE plain sibling foregrounds:
///     glyphs that merely sit on top of a `.background`-applied `glass()`
///     render dim and smeared inside a group — the dock regressed exactly
///     like that on CI, and the composer cluster and the pulse fan shared
///     the construction; all three are standalone glass again (see
///     the native tab bar's accessory, `ChatView.inputBar`,
///     `DashboardView.thinkingFab`).
///     Only group panes whose visible content is rendered by the glass
///     itself (system `.glass` button styles, `glassEffect` applied
///     directly to the labeled view) or content-free shapes.
///   * Panes resting closer than the group spacing melt permanently —
///     never park a tinted pane at 0-pt distance against chrome panes
///     (blend smear, overexposed tint). Keep resting gaps ABOVE the
///     `GlassSpacing` value and let only transitions cross it.
struct GlassGroup<Content: View>: View {
    var spacing: GlassSpacing = .tight
    @ViewBuilder var content: () -> Content

    var body: some View {
        GlassEffectContainer(spacing: spacing.value) {
            content()
        }
    }
}

extension View {
    /// Applies one of the three named glass levels — the only sanctioned
    /// way to put liquid glass behind a view. The pane lives in the
    /// background so only the glass casts the elevation shadow, never the
    /// content on top of it. `interactive` opts into the springy system
    /// press response for glass that IS a control (buttons, fields).
    func glass(_ level: GlassLevel, in shape: some Shape,
               interactive: Bool = false) -> some View {
        background(
            shape.fill(Color.clear)
                .glassEffect(interactive ? level.material.interactive()
                                         : level.material,
                             in: shape)
                .elevation(level.elevation)
        )
    }

    /// Morph-capable variant: identical glass, plus an identity inside a
    /// `GlassGroup`. Panes carrying a `morphID` melt out of / into their
    /// group neighbors when they appear, disappear or move — driven by
    /// whatever `Theme.Motion` curve animates the state change.
    func glass(_ level: GlassLevel, in shape: some Shape,
               morphID: some Hashable & Sendable, namespace: Namespace.ID,
               interactive: Bool = false) -> some View {
        background(
            shape.fill(Color.clear)
                .glassEffect(interactive ? level.material.interactive()
                                         : level.material,
                             in: shape)
                .glassEffectID(morphID, in: namespace)
                .glassEffectTransition(.matchedGeometry)
                .elevation(level.elevation)
        )
    }

    /// Neutral drop shadow from the elevation scale (10-o'clock light).
    func elevation(_ elevation: Elevation) -> some View {
        shadow(color: elevation.color,
               radius: elevation.radius,
               x: elevation.offset.width,
               y: elevation.offset.height)
    }
}

// MARK: - Paper material (Papier & Licht — the second material)

/// The named paper hierarchy — everything that LIES is paper (opaque,
/// matte, warm), the counterpart to the floating glass chrome. Levels
/// replace the deprecated `GlassLevel.surface`/`.tinted`:
///   .nachtkarton — cardboard at night: THE standard content card of
///                 the nacht-first direction (adopt via `nightCard()`;
///                 text on it is `Papier.aufNacht`/`Nacht.*`, never
///                 Tinte.* — MIGRATION_DUNKEL.md has the mapping).
///   .brief      — letter paper: HERO/ARTIFACT moments only since
///                 nacht-first (letters, Tagesfrage-Briefbogen,
///                 Zeitpost envelope, receipt Zettel) — paper is
///                 something special in the dark room, not wallpaper.
///   .karton     — cardboard: secondary surfaces INSIDE paper heroes.
///   .polaroid   — photo frames only (Radius.polaroid).
///   .briefbogen — the hero: Papier.brief plus couple band and wax seal —
///                 exactly ONE per screen (inherits the charter hero rule;
///                 band and seal are the screen's own overlay artifacts).
enum PaperLevel {
    case brief
    case karton
    case polaroid
    case briefbogen
    case nachtkarton

    var fill: Color {
        switch self {
        case .brief, .briefbogen: return Papier.brief
        case .karton: return Papier.karton
        case .polaroid: return Papier.polaroid
        case .nachtkarton: return Papier.nachtkarton
        }
    }

    /// Cut paper is sharper than glass; photos are sharper still.
    var radius: CGFloat {
        self == .polaroid ? Radius.polaroid : Radius.papier
    }

    /// Paper rests on the desk; only the hero Briefbogen lifts a step.
    var elevation: Elevation {
        self == .briefbogen ? .raised : .resting
    }

    /// The grain family follows the ground: paper specks on paper, the
    /// fine dark Korn on night cards — same ±2 % luminance law.
    var grainStyle: PaperGrainStyle {
        self == .nachtkarton ? .nacht : .papier
    }

    /// The 10-o'clock light edge: bright `lichtkante` on paper, the
    /// warm lamp-gold lip on night cards.
    var lightEdge: LinearGradient {
        self == .nachtkarton ? PaperLightEdge.nachtGradient
                             : PaperLightEdge.gradient
    }
}

/// Paper card = opaque `PaperLevel` fill + procedural grain + the 1-pt
/// light edge top-left (`Papier.lichtkante`, the lamp) + the elevation
/// shadow down-right. The TARGET card API of the paper migration — the
/// screen waves swap `glassCard()` call sites to this, one wave at a
/// time. Grain is skipped under Increased Contrast (PaperRules cap) and
/// callers whose card is dominated by text below `.subheadline` pass
/// `grain: false` — legibility beats charm.
struct PaperCardModifier: ViewModifier {
    var level: PaperLevel = .brief
    /// Scaled padding (comes from a `CardPadding` token).
    var padding: CGFloat = Space.l
    var grain = true
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: level.radius, style: .continuous)
        content
            .padding(padding)
            .background(
                shape.fill(level.fill)
                    .overlay {
                        if grain && colorSchemeContrast != .increased {
                            PaperGrainView(style: level.grainStyle)
                                .clipShape(shape)
                        }
                    }
                    .overlay(shape.strokeBorder(level.lightEdge,
                                                lineWidth: Theme.hairlineWidth))
                    .elevation(level.elevation)
            )
    }
}

/// The 10-o'clock light edge as a stroke gradient: bright `lichtkante`
/// at the top-leading corner, fading out before the shadowed side — the
/// lamp catches the paper's upper edge, the shadow falls down-right.
enum PaperLightEdge {
    static var gradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Papier.lichtkante, location: 0),
                .init(color: Papier.lichtkante.opacity(0.4), location: 0.35),
                .init(color: .clear, location: 0.7),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The night-card variant: the lamp's warm gold catches the dark
    /// card's upper lip (`Papier.nachtLichtkante`, derived in
    /// PaperRules) — subtler than the paper edge, because night cards
    /// sit IN the room instead of lying on it.
    static var nachtGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Papier.nachtLichtkante, location: 0),
                .init(color: Papier.nachtLichtkante.opacity(0.35), location: 0.35),
                .init(color: .clear, location: 0.7),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Procedural paper grain — seeded hash noise, luminance capped by
/// `PaperRules.grainLuminance` (±2 %, Logic-test-pinned). The decision
/// names a Metal `colorEffect` shader as the end state; this view
/// implements the identical law (static, procedural, capped) without a
/// new shader resource — swapping the backend is a screen-wave detail
/// that changes no call site (see MIGRATION_PAPIER.md).
///
/// P6-C perf: the grain used to be a per-card `Canvas`. A Canvas re-runs
/// its draw closure on every invalidation — most painfully on every SIZE
/// change, so an expanding/animating card re-hashed ~16k cells and
/// replayed thousands of 1-pt fills per frame, and N cards on a screen
/// each held their own display list even though every call site uses the
/// shared default seed. Now the noise is rasterized ONCE per seed into a
/// small tile (process-wide cache) and tiled by the render server: layout
/// changes just re-tile the cached texture — zero CPU redraw. The tile
/// repeats every 144 pt, invisible for ±2 % specks; the drawn pattern is
/// the same `PaperRules.unitRandom` law as before.
/// The two grain families (nacht-first): `papier` specks the light
/// sheets (dark ink + white), `nacht` is the fine dark Korn of the
/// night cards (black bite + a warm `aufNacht` catch). Same pattern,
/// same seeds, same pinned ±2 % luminance cap — only the speck inks
/// follow the ground.
enum PaperGrainStyle: Hashable {
    case papier
    case nacht
}

struct PaperGrainView: View {
    /// Stable by default — grain is texture, not identity; Zettel that
    /// want their OWN grain pass their item seed.
    var seed: UInt64 = 0x5041_5049_4552 // "PAPIER"
    /// Grain family — the card level picks it (`PaperLevel.grainStyle`).
    var style: PaperGrainStyle = .papier

    var body: some View {
        Image(uiImage: Self.tile(seed: seed, style: style))
            .resizable(resizingMode: .tile)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private struct TileKey: Hashable {
        let seed: UInt64
        let style: PaperGrainStyle
    }

    /// One rendered tile per seed and family for the app's lifetime
    /// (today: two — every call site keeps the default seed).
    @MainActor private static var tiles: [TileKey: UIImage] = [:]

    @MainActor private static func tile(seed: UInt64,
                                        style: PaperGrainStyle) -> UIImage {
        let key = TileKey(seed: seed, style: style)
        if let cached = tiles[key] { return cached }
        let cell: CGFloat = 3
        let side: CGFloat = 144 // 48 cells — small texture, invisible repeat
        let cells = Int(side / cell)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side),
                                            format: format).image { context in
            let dark: UIColor
            let light: UIColor
            switch style {
            case .papier:
                dark = UIColor(Tinte.dunkel)
                    .withAlphaComponent(PaperRules.grainLuminance)
                light = UIColor.white
                    .withAlphaComponent(PaperRules.grainLuminance)
            case .nacht:
                // The fine dark Korn: a black bite plus a warm aufNacht
                // catch — the lamp grazing rough cardboard at night.
                dark = UIColor.black
                    .withAlphaComponent(PaperRules.grainLuminance)
                light = UIColor(Papier.aufNacht)
                    .withAlphaComponent(PaperRules.grainLuminance)
            }
            for row in 0..<cells {
                for column in 0..<cells {
                    let noise = PaperRules.unitRandom(seed: seed,
                                                      index: row &* 4099 &+ column)
                    // Sparse specks: most cells stay clean paper; the
                    // rest split into darker and lighter grains.
                    guard noise > 0.62 else { continue }
                    (noise > 0.81 ? dark : light).setFill()
                    context.fill(CGRect(x: CGFloat(column) * cell,
                                        y: CGFloat(row) * cell,
                                        width: 1, height: 1))
                }
            }
        }
        tiles[key] = image
        return image
    }
}

extension View {
    /// The paper counterpart to `glassCard()`: a named paper level plus a
    /// named card density — the card rhythm stays a token, not a taste.
    ///
    /// Nacht-first (P1-A): the `.brief` default DELIBERATELY stays — a
    /// default flip would drop every existing card's `Tinte.*` ink onto
    /// a dark ground at once. STANDARD cards move to `nightCard()` in
    /// the P2 waves (card + ink mapping in one edit, one token per call
    /// site); `paperCard(...)` remains the hero/artifact paper API.
    func paperCard(_ level: PaperLevel = .brief,
                   padding: CardPadding = .regular,
                   grain: Bool = true) -> some View {
        modifier(PaperCardModifier(level: level, padding: padding.value,
                                   grain: grain))
    }

    /// THE standard content card of the nacht-first direction: dark,
    /// warm cardboard-at-night (`PaperLevel.nachtkarton`) with the fine
    /// dark Korn and the warm lamp edge — described with
    /// `Papier.aufNacht`/`Nacht.*` ink, never `Tinte.*` (dark ink
    /// drowns on the dark card). Light paper via `paperCard(_:)` stays
    /// EXCLUSIVELY for hero/artifact moments (letters, Tagesfrage-
    /// Briefbogen, polaroids, Zeitpost envelope, receipt Zettel).
    /// Migration rules and ink mapping: docs/styles/MIGRATION_DUNKEL.md.
    func nightCard(padding: CardPadding = .regular,
                   grain: Bool = true) -> some View {
        paperCard(.nachtkarton, padding: padding, grain: grain)
    }
}

// MARK: - Paper physics tokens (seeded — nothing flickers between renders)

/// THE one legal rotation source for paper: seeded −6°…+6°
/// (`PaperRules.tiltDegrees`), seed = stable item ID, max. ONE rotated
/// element per screen (charter budget; ratchet `raw_rotation_features`
/// counts free-hand `rotationEffect` in features down to 0).
struct PaperTilt {
    let degrees: Double

    /// `grid: true` damps the range (`PaperRules.gridTiltDegrees`) for
    /// Zettel inside a collection grid — tight cells near the bottom
    /// chrome must not swing their corners into the accessory line.
    init(seed: UInt64, grid: Bool = false) {
        degrees = grid ? PaperRules.gridTiltDegrees(seed: seed)
                       : PaperRules.tiltDegrees(seed: seed)
    }
}

/// The tilt as a modifier so it can read the environment (FullRelease
/// R1-A, A11y S2): under Reduce Motion every Zettel lies straight —
/// the seeded rotation is charm, not information, and the switch asks
/// for a calmer, squarer room. Centralized HERE so no call site needs
/// its own gate.
private struct PaperTiltModifier: ViewModifier {
    let seed: UInt64
    let grid: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.rotationEffect(
            .degrees(reduceMotion ? 0 : PaperTilt(seed: seed, grid: grid).degrees))
    }
}

extension View {
    /// Applies the seeded paper tilt — the only sanctioned way to rotate
    /// a Zettel, polaroid or seal. Respects Reduce Motion (tilt 0°).
    /// `grid: true` for cards inside a collection grid (damped range).
    func paperTilt(seed: UInt64, grid: Bool = false) -> some View {
        modifier(PaperTiltModifier(seed: seed, grid: grid))
    }
}

/// A paper shape whose ONE edge is torn: seeded jitter (amplitude 2.5 pt,
/// period 10–14 pt — `PaperRules`), seed = stable item ID so the tear
/// never flickers between renders. Max. ONE torn edge per screen; the
/// app-wide cap (≤ 6 uses) is enforced by charter_lint — tears are the
/// exception, never the rhythm. The other three edges stay straight cuts;
/// combine with `clipShape` over a paper fill.
struct TornEdgeShape: Shape {
    var seed: UInt64
    /// Which edge tears — bottom (default: torn-off Zettel, the icon's
    /// polaroid) or top (torn FROM a pad).
    var edge: VerticalEdge = .bottom

    func path(in rect: CGRect) -> Path {
        let period = CGFloat(PaperRules.tornPeriod(seed: seed))
        let teeth = max(2, Int((rect.width / period).rounded()))
        let step = rect.width / CGFloat(teeth)
        var path = Path()
        let tornY = edge == .bottom ? rect.maxY : rect.minY
        let flatY = edge == .bottom ? rect.minY : rect.maxY
        path.move(to: CGPoint(x: rect.minX, y: flatY))
        path.addLine(to: CGPoint(x: rect.maxX, y: flatY))
        // Down the trailing edge, then the torn run back to leading —
        // jitter stays inside the amplitude so no tooth leaves the rect.
        path.addLine(to: CGPoint(x: rect.maxX, y: tornY))
        for tooth in stride(from: teeth - 1, through: 1, by: -1) {
            let offset = CGFloat(PaperRules.tornOffset(seed: seed, index: tooth))
            let y = edge == .bottom ? tornY - abs(offset) : tornY + abs(offset)
            path.addLine(to: CGPoint(x: rect.minX + CGFloat(tooth) * step, y: y))
        }
        path.addLine(to: CGPoint(x: rect.minX, y: tornY))
        path.closeSubpath()
        return path
    }
}
