import SwiftUI
import Combine

extension Color {
    /// "#FF5C8A" / "FF5C8A" → Color
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r, g, b: Double
        if s.count == 6 {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        } else {
            r = 1; g = 0.36; b = 0.54
        }
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Responsive layout scale

/// Design baseline = iPhone Pro Max (~430pt wide). Smaller CONTAINERS shrink
/// proportionally (the math lives in `LayoutRules`, Foundation-only and
/// tested); wider containers stay at 1.0 — on iPad the extra space becomes
/// column margins (`contentColumn`), never zoom. Driven by the root
/// GeometryReader (`fitsContainerLayout`), deliberately NOT by
/// `UIScreen.main`: in Split View / Slide Over / Stage Manager a window is
/// not the screen.
enum LayoutMetrics {
    static let designWidth: CGFloat = CGFloat(LayoutRules.designWidth)

    /// Mutable so the root container measurement can refresh it. Starts at
    /// the design baseline; the root GeometryReader corrects it in the very
    /// first layout pass, before any feature body evaluates.
    static var scale: CGFloat = 1

    /// Last measured root container width (see `fitsContainerLayout`) —
    /// the REAL window width, refreshed before every subtree layout pass.
    /// Feeds the AX5 layout gate (`DynamicTypeSize.prefersVerticalLayout`).
    static var containerWidth: CGFloat = designWidth

    static func scale(forWidth width: CGFloat) -> CGFloat {
        CGFloat(LayoutRules.scale(forWidth: Double(width)))
    }

    /// Apply current scale (rounded to 0.5pt for crisp layout).
    static func s(_ value: CGFloat) -> CGFloat {
        (value * scale * 2).rounded() / 2
    }

    static func update(forWidth width: CGFloat) {
        scale = scale(forWidth: width)
        containerWidth = width
    }

    // Regular-width (iPad) column tokens — unscaled: on regular widths the
    // scale is pinned at 1 and the remaining space becomes margin.
    /// Max width of a single reading column (settings, chat, ceremonies).
    static let readingColumnMax: CGFloat = 640
    /// Max width of a card-hub column (dashboard, memories, play grids).
    static let hubColumnMax: CGFloat = 980
    /// Max width of the letter-game column (wordle board + keys, hangman
    /// letters) — narrower than reading so two thumbs reach every key.
    /// Token lives in GameTableRules (Foundation) with the table matrix.
    static let keyboardColumnMax: CGFloat = CGFloat(GameTableRules.keyboardColumnMax)
    /// Fixed width of the persistent section sidebar in regular-width
    /// split layouts (Memories hub) — unscaled like the column tokens.
    static let sidebarWidth: CGFloat = 320
    /// Fixed width of the canvas tool rail on wide regular panes — the
    /// board takes the rest of the pane.
    static let toolRailWidth: CGFloat = 248

    // Bottom-chrome clearances (LayoutRules pins the math): accessory and
    // tab bar are SYSTEM chrome and do not shrink with the design scale,
    // so these stay deliberately UNSCALED — a scaled-down clearance would
    // undershoot the real glass on small phones.
    /// Resting clearance for tab-root scroll content above the
    /// accessory/tab-bar glass (contentMargins .bottom).
    static let restingBottomClearance =
        CGFloat(LayoutRules.restingBottomClearance)
    /// Breath between resting content and a glass edge where the chrome
    /// itself is already cleared (chat composer bar).
    static let glassEdgeBreath = CGFloat(LayoutRules.glassEdgeBreath)
    /// Bottom exclusion of celebration particle fields — no heart floats
    /// through the accessory/tab-bar glass.
    static let celebrationBottomExclusion =
        CGFloat(LayoutRules.celebrationBottomExclusion)

    // Adaptive tile minimums — grids derive their column count from these
    // instead of hard-coding "2 columns" (which only fit phones).
    /// Hub tiles (memories hub, game cards): 2 columns on phones, more as
    /// the window grows.
    static var hubTileMin: CGFloat { s(185) }
    /// Photo cells, big density (2 columns on phones).
    static var photoTileBigMin: CGFloat { s(150) }
    /// Photo cells, classic density (3 columns on phones).
    static var photoTileClassicMin: CGFloat { s(110) }
}

// MARK: - Content columns (regular width)

/// The named content-column widths for regular-width (iPad) panes —
/// features pick a name, never a number.
enum ColumnWidth {
    /// Single reading column — settings, chat, ceremonies, overlays.
    case reading
    /// Card-hub column — dashboard, memories and play grids.
    case hub
    /// Letter-game column — wordle/hangman board plus keys (roadmap 22).
    case keys

    var max: CGFloat {
        switch self {
        case .reading: return LayoutMetrics.readingColumnMax
        case .hub: return LayoutMetrics.hubColumnMax
        case .keys: return LayoutMetrics.keyboardColumnMax
        }
    }
}

private struct ContentColumnModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let column: ColumnWidth

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: horizontalSizeClass == .regular ? column.max : .infinity)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    /// Caps content to a named readable column, centered, on regular width;
    /// compact width keeps the full-bleed phone layout untouched. Always
    /// size-class-driven, never a device-idiom check — the same iPad runs
    /// both layouts depending on its window.
    func contentColumn(_ column: ColumnWidth = .reading) -> some View {
        modifier(ContentColumnModifier(column: column))
    }
}

// MARK: - Accessibility layout gate (AX5)

extension DynamicTypeSize {
    /// 0 outside the accessibility sizes, 1…5 for AX1…AX5 — the pure grid
    /// rule in `AccessibilityBudget` wants a number, not a SwiftUI type.
    var accessibilityLevel: Int {
        switch self {
        case .accessibility1: return 1
        case .accessibility2: return 2
        case .accessibility3: return 3
        case .accessibility4: return 4
        case .accessibility5: return 5
        default: return 0
        }
    }

    /// THE central AX5 layout gate: true when side-by-side rows should
    /// stack vertically (accessibility text sizes, ultra-narrow windows).
    /// The rule itself is Foundation-only in `AccessibilityBudget`; the
    /// width is the real measured window width from `fitsContainerLayout`.
    /// At these sizes, informative text is never shrunk via
    /// `minimumScaleFactor` and never forced onto one line — layouts make
    /// room instead (EVAL AX5: shattered headings, overlapping cards).
    var prefersVerticalLayout: Bool {
        AccessibilityBudget.prefersVerticalLayout(
            accessibilityText: isAccessibilitySize,
            availableWidth: Double(LayoutMetrics.containerWidth))
    }

    /// Column count for an `n`-column grid under this type size — grids
    /// collapse before their tile labels shatter (AccessibilityBudget).
    func gridColumns(regular: Int) -> Int {
        AccessibilityBudget.gridColumns(regular: regular,
                                        accessibilityLevel: accessibilityLevel)
    }
}

private struct LayoutScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = LayoutMetrics.scale
}

extension EnvironmentValues {
    var layoutScale: CGFloat {
        get { self[LayoutScaleKey.self] }
        set { self[LayoutScaleKey.self] = newValue }
    }
}

extension Font {
    /// Scaled display/hero font. Prefer semantic `.system(.body)` etc. for body copy.
    static func scaled(_ size: CGFloat,
                       weight: Font.Weight = .regular,
                       design: Font.Design = .rounded) -> Font {
        .system(size: LayoutMetrics.s(size), weight: weight, design: design)
    }
}

extension View {
    /// Scaled fixed frame (decorative glyphs, QR, hero canvases).
    func sFrame(width: CGFloat? = nil, height: CGFloat? = nil,
                alignment: Alignment = .center) -> some View {
        frame(width: width.map(LayoutMetrics.s),
              height: height.map(LayoutMetrics.s),
              alignment: alignment)
    }

    func sPadding(_ edges: Edge.Set = .all, _ length: CGFloat) -> some View {
        padding(edges, LayoutMetrics.s(length))
    }

    /// Root layout driver: measures the CONTAINER the app actually owns
    /// (the window — on iPad a window is not the screen) and installs the
    /// width-based layout scale for the subtree. Split View, Slide Over,
    /// Stage Manager and rotation all resize through here.
    func fitsContainerLayout() -> some View {
        modifier(ContainerLayoutModifier())
    }
}

private struct ContainerLayoutModifier: ViewModifier {
    func body(content: Content) -> some View {
        GeometryReader { geo in
            // Idempotent global refresh BEFORE the subtree evaluates, so
            // even the first pass lays out with the real container scale
            // (the old UIScreen-based default was wrong on iPad by
            // definition, and doubly wrong in Split View).
            let _ = LayoutMetrics.update(forWidth: geo.size.width)
            content
                .environment(\.layoutScale, LayoutMetrics.scale(forWidth: geo.size.width))
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// SoooDreamy design system — "Papier & Licht": warm paper in a dark room,
/// lit by one lamp (Art Direction v2, docs/styles/STYLE_DECISION.md §3).
///
/// This file is the ONLY place in the app layer that may hold raw design
/// values (colors, opacities, spring parameters). Features reference the
/// named tokens below — see DESIGN.md, commandment 11. Contrast-critical
/// hexes are CONSUMED from the Foundation law table (`PaperRules`,
/// `CouplePaletteRules`) following the heroGradient-stop precedent, so the
/// Logic tests pin exactly what renders.

// MARK: - Papier & Licht token families

/// The room and the paper — night canvas plus the opaque content material.
/// New names for the screen waves; the LEGACY `Theme.*` names below stay
/// functional and point here (migration table:
/// docs/styles/MIGRATION_PAPIER.md).
enum Papier {
    /// Dark sepia umbra — upper screen edge, the NIGHT contrast anchor
    /// (nacht-first P1-A: one step darker — late night, not golden hour).
    static let zimmerOben = Color(hex: PaperRules.zimmerObenHex)
    /// Warm chestnut — lower edge; the room warms toward the lamp.
    static let zimmerUnten = Color(hex: PaperRules.zimmerUntenHex)
    /// The ONE radial lamp glow from 10 o'clock (paint at 0.30 → 0).
    static let lichtkegel = Color(hex: PaperRules.lichtkegelHex)
    /// Letter paper — HERO/ARTIFACT paper since nacht-first (letters,
    /// Tagesfrage-Briefbogen, Zeitpost envelope, receipt Zettel); the
    /// STANDARD content card is `nachtkarton` (via `nightCard()`).
    static let brief = Color(hex: PaperRules.briefHex)
    /// Cardboard at night — THE standard content card of the nacht-first
    /// direction (PaperLevel.nachtkarton, the THIRD contrast anchor):
    /// dark warm karton, described with `aufNacht` ink (12.5:1, pinned).
    static let nachtkarton = Color(hex: PaperRules.nachtkartonHex)
    /// The warm 1-pt light edge on night cards (nachtkarton → lamp gold,
    /// derived in PaperRules) — the lamp brushes the dark card's upper
    /// lip; decor only, never a text ground.
    static let nachtLichtkante = Color(hex: PaperRules.nachtLichtkanteHex)
    /// Matte inner fill ON night cards (`aufNacht` wash at the pinned
    /// innenFill opacity) with a `Nacht.naht` hairline — the dark-card
    /// counterpart of `innenFill` (dark ink is invisible on nachtkarton).
    static let nachtInnenFill = Papier.aufNacht.opacity(PaperRules.innenFillOpacity)
    /// Cardboard — secondary cards, partner Zettel, inner surfaces.
    static let karton = Color(hex: PaperRules.kartonHex)
    /// Stacked edge / backs / dividers ON paper — never a text ground
    /// (Tinte.tertiaer reads 4.45:1 here, pinned below the floor).
    static let kante = Color(hex: PaperRules.kanteHex)
    /// Polaroid frame (photos only).
    static let polaroid = Color(hex: PaperRules.polaroidHex)
    /// Text directly on the room (15.7:1 on zimmerOben) — and the ink
    /// of the nachtkarton anchor (12.5:1 there, pinned).
    static let aufNacht = Color(hex: PaperRules.aufNachtHex)
    /// The 1-pt light edge every paper card wears top-left: brief at
    /// +8 % luminance — the lamp IS the 10-o'clock light source.
    static let lichtkante = Color(hex: PaperRules.lichtkanteHex)
    /// Matte inner fill ON paper (Tinte.dunkel wash at the PINNED
    /// PaperRules opacity) with a kante hairline — never a second
    /// material inside a paper card.
    static let innenFill = Tinte.dunkel.opacity(PaperRules.innenFillOpacity)
    /// Width of the couple band around the Briefbogen hero card.
    static var bandBreite: CGFloat { LayoutMetrics.s(6) }
    /// Width of the author ink edge on chat Zettel.
    static var tintenkante: CGFloat { LayoutMetrics.s(4) }
}

/// Text on paper — the inks (measured against Papier.brief;
/// couple colors become ink via `CouplePaletteRules.inkOnPaper`).
enum Tinte {
    /// Primary text and headings on paper (13.6:1).
    static let dunkel = Color(hex: PaperRules.tinteDunkelHex)
    /// Secondary text — faded ink (7.5:1).
    static let sekundaer = Color(hex: PaperRules.tinteSekundaerHex)
    /// Timestamps, footnotes — never below `.caption` (5.7:1).
    static let tertiaer = Color(hex: PaperRules.tinteTertiaerHex)
    /// Success/confirmation ink ON paper (6.8:1 on brief, ≥ 4.5 on every
    /// text paper — pinned). Paper-only like every ink: on night,
    /// success speaks in lamplight.
    static let erfolg = Color(hex: PaperRules.tinteErfolgHex)
}

/// Lamplight — accents on NIGHT, never text on paper (lampengold reads
/// 1.4:1 on brief; the Logic tests pin the prohibition). On nachtkarton
/// cards the lamplight IS the accent vocabulary (pinned ≥ 4.5:1 there).
enum Licht {
    /// Ceremony accent and glows on night (11.9:1 on zimmerOben).
    static let lampengold = Color(hex: PaperRules.lampengoldHex)
    /// Second warm accent — active states on night (7.0:1).
    static let glut = Color(hex: PaperRules.glutHex)
    /// Copper — the second stop of the "goldene Tinte" brand gradient
    /// (lamp gold → copper, see `Theme.heroGradient`). Accent on night
    /// (4.9:1, pinned), never text on paper (3.4:1 — same law as gold).
    static let kupfer = Color(hex: PaperRules.kupferHex)
    /// Countdown/expiry accent on night — a semantic NAME on the ember
    /// (`PaperRules.ablaufHex`), so deadline chrome stops borrowing
    /// colors ad hoc. ON PAPER a deadline writes in `Wachs.gelb`.
    static let ablauf = Color(hex: PaperRules.ablaufHex)
}

/// Seal material — wax is MATERIAL, never ink on night (3.2:1 there).
enum Wachs {
    static let rot = Color(hex: PaperRules.wachsRotHex)
    /// Warn-amber wax: caution ON paper (5.3:1 on brief, pinned) —
    /// material like the red, never ink on night (3.2:1 there).
    static let gelb = Color(hex: PaperRules.wachsGelbHex)
    /// Deep seal wax (nacht-first): the dark, saturated pour the
    /// `WachsSiegel` gradient starts with — ground of the LIGHT
    /// embossing (`aufNacht` reads 8.1:1 on it, pinned); material on
    /// night like its siblings (1.9:1 there).
    static let dunkel = Color(hex: PaperRules.wachsDunkelHex)
    /// The lamp on the Siegellack button's upper lip: `rot` mixed toward
    /// the lamp gold, derived in PaperRules like the night-card
    /// Lichtkante — decor only (1.4:1 on the pour), never a text ground.
    static let lichtkante = Color(hex: PaperRules.siegellackKanteHex)
}

/// Hairlines and ink steps on the night canvas.
enum Nacht {
    /// Quiet seam on night — Papier.aufNacht at 0.12 (Increased
    /// Contrast raises it to 0.38 via `Theme.Contrast.hairline`).
    static let naht = Papier.aufNacht.opacity(0.12)
    /// Secondary copy on the room — aufNacht at the PINNED 0.78 step
    /// (composite 9.7:1 on the room, 8.1:1 on nachtkarton). The named
    /// token behind `Theme.textSecondary`.
    static let sekundaer = Papier.aufNacht.opacity(PaperRules.nachtSekundaerOpacity)
    /// Tertiary copy on the room — aufNacht at the PINNED 0.64 step
    /// (composite 6.9:1 on the room, 6.0:1 on nachtkarton). The named
    /// token behind `Theme.textTertiary`.
    static let tertiaer = Papier.aufNacht.opacity(PaperRules.nachtTertiaerOpacity)
}

enum Theme {
    // Palette — every LEGACY name stays a property (~380 files reference
    // them) and points at its Papier & Licht value per the migration
    // table in docs/styles/MIGRATION_PAPIER.md; the screen waves then
    // move to the Papier/Tinte/Licht/Wachs names at their own pace.
    static let bgTop = Papier.zimmerOben
    static let bgBottom = Papier.zimmerUnten
    /// LEGACY → Papier.brief (was translucent white on the aurora).
    /// Nacht-first: the STANDARD card target is `Papier.nachtkarton`
    /// via `nightCard()`; brief stays the hero/artifact paper — the
    /// P2 waves migrate call sites per MIGRATION_DUNKEL.md.
    static let card = Papier.brief
    /// LEGACY → Papier.kante.
    static let cardBorder = Papier.kante
    // LEGACY affection colors — NO LONGER the brand stops (Siegellack
    // brand: `heroGradient` pours golden ink from the law table now).
    // They survive only where they are couple CONTENT, not chrome:
    // Delight heart particles, the AppLock heart, the `.love` toast
    // tint. Raw hexes are legal in this UI layer; nothing judges text
    // against them anymore. (`rose`, the old pre-pairing blend, is gone
    // — the fallback tint speaks golden ink.)
    static let pink = Color(hex: "FF5C8A")
    static let purple = Color(hex: "A855F7")
    /// LEGACY chrome roles → Licht.glut: the cool blue/mint/indigo accents
    /// hand their night duties to the warm ember (migration table).
    static let indigo = Licht.glut
    static let blue = Licht.glut
    static let mint = Licht.glut
    /// Hex kept addressable: the LEGACY chip ink (CoupleTint.onWax) is
    /// judged against gold as a gradient stop, not just the Color.
    /// Consumes the lamplight gold so chip and verdict can never drift
    /// apart. (The SEAL pours Wachs.dunkel → wachsTief since P1-A.)
    static let goldHex = PaperRules.lampengoldHex
    static let gold = Color(hex: goldHex)
    /// Warm "running on empty" red for the energy battery — deliberately
    /// NOT the love-pink: vulnerability and affection must not share a
    /// color channel (Dossier 32, idea 9). Hex unchanged, re-pinned
    /// against the sepia night (6.4:1).
    static let energyRed = Color(hex: PaperRules.energyRedHex)
    /// LEGACY → Papier.aufNacht: text on the night canvas is warm paper
    /// white now, never hard white. ON PAPER the screen waves switch to
    /// Tinte.dunkel — this compat property serves the night context the
    /// existing screens render in.
    static let textPrimary = Papier.aufNacht
    /// LEGACY → Nacht.sekundaer: the 0.78 step is a pinned PaperRules
    /// opacity now (P6-C), no longer an anonymous raw value.
    static let textSecondary = Nacht.sekundaer
    /// LEGACY → Nacht.tertiaer (raised from 0.58 in the A11y eval):
    /// tertiary copy sits on glass above the night canvas — the pinned
    /// 0.64 step keeps ~6.7:1 with margin over hotspots.
    static let textTertiary = Nacht.tertiaer

    // Surface tokens — matte fills INSIDE glass panes (glass-on-glass is
    // forbidden; inner surfaces are matte, never a second material).
    // On PAPER the equivalent is Papier.innenFill + Papier.kante hairline.
    /// Matte inner fill for controls/rows that sit inside a glass card.
    static let innerFill = Papier.aufNacht.opacity(0.05)
    /// 1-pt stroke color for quiet outlines on matte fills (= Nacht.naht).
    static let hairline = Nacht.naht
    /// The hairline stroke width (unscaled — strokes stay crisp).
    static let hairlineWidth: CGFloat = 1

    // Scaled layout tokens (read LayoutMetrics.scale at use time)
    static var cardPadding: CGFloat { Space.l }
    static var cardRadius: CGFloat { Radius.card }
    static var screenPadding: CGFloat { Space.l }
    static var sectionSpacing: CGFloat { LayoutMetrics.s(18) }

    // Gradients
    /// "Goldene Tinte" — the STATIC brand gradient (Siegellack brand):
    /// lamp gold → copper, consumed from the law-table stops so the
    /// Logic tests pin exactly what renders. Serves the brand chrome
    /// (active page dot, hero platters) and the neutral pre-pairing
    /// fallback; paired screens derive their gradients from
    /// `\.coupleTint` so the couple's own colors carry the app.
    static let heroGradient = LinearGradient(
        colors: [Color(hex: CouplePaletteRules.heroGradientFirstHex),
                 Color(hex: CouplePaletteRules.heroGradientSecondHex)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Verdict for the STATIC brand platter, computed ONCE through the same
    /// rule the dynamic couple platters use — never guessed (white caps at
    /// 1.6:1 on the gold stop, far under the 4.5:1 charter floor).
    private static let heroVerdict = CouplePaletteRules.gradientForegroundVerdict(
        first: CouplePaletteRules.heroGradientFirstHex,
        second: CouplePaletteRules.heroGradientSecondHex)
    /// Contrast-secured ink ON `heroGradient` — judged against BOTH stops
    /// (the worst one wins); for the golden-ink stops this is the night
    /// ink at 12.9:1 / 5.4:1, pinned by the Logic tests.
    static let onHero = Color(hex: heroVerdict.hex)
    /// Text-protection scrim under `onHero` content — nil while a single
    /// ink clears the floor on both stops (true today). Painted by
    /// `heroPlatter(in:)` so the scrim travels WITH the gradient, same
    /// philosophy as CoupleTint.gradientTextScrim.
    static let heroTextScrim: Color? = heroVerdict.needsScrim
        ? Color(hex: CouplePaletteRules.scrimHex).opacity(heroVerdict.scrimOpacity)
        : nil

    /// The static hero platter as ONE unit: gradient plus (should the
    /// verdict ever demand it) the night-ink scrim. Surfaces carrying
    /// `onHero` content fill THIS, never the bare gradient — no future
    /// stop change can strand a label without its shield (Schlussrunde 5).
    static func heroPlatter<S: Shape>(in shape: S) -> some View {
        shape.fill(heroGradient)
            .overlay(shape.fill(heroTextScrim ?? .clear))
    }

    static let bgGradient = LinearGradient(
        colors: [bgTop, bgBottom],
        startPoint: .top, endPoint: .bottom)

    /// Avatar color choices during profile setup. Single source lives in
    /// `CouplePaletteRules.memberColorHexes` (Foundation) so the contrast
    /// proofs and this palette can never drift apart (R1-E).
    static let memberColors: [String] = CouplePaletteRules.memberColorHexes

    /// Avatar emoji choices.
    static let avatarEmojis: [String] = [
        "🦊", "🐰", "🐻", "🐼", "🐨", "🦁", "🐯", "🐸", "🐙", "🦄", "🐝", "🦋",
        "🌸", "🌙", "⭐️", "🍓", "🍑", "🌈", "💫", "🔥", "🌊", "🍀", "🎀", "👑"
    ]
}

// MARK: - Spacing scale (4-pt grid)

/// The six spacing tokens of the app. Everything on screen breathes in this
/// rhythm — free-hand values like `s(7)` or `s(13)` read as visual noise.
/// Values are design-space (Pro Max baseline) and scale with the device.
enum Space {
    /// 4 — hairline gaps (icon-to-badge, stacked caption rows).
    static var xs: CGFloat { LayoutMetrics.s(4) }
    /// 8 — tight sibling spacing inside a control.
    static var s: CGFloat { LayoutMetrics.s(8) }
    /// 12 — default gap between elements inside a card.
    static var m: CGFloat { LayoutMetrics.s(12) }
    /// 16 — card padding, screen edge padding.
    static var l: CGFloat { LayoutMetrics.s(16) }
    /// 24 — separation between distinct content groups.
    static var xl: CGFloat { LayoutMetrics.s(24) }
    /// 32 — hero breathing room, empty-state padding.
    static var xxl: CGFloat { LayoutMetrics.s(32) }
}

// MARK: - Radius scale (concentric system)

/// Corner radii with names and a concentricity rule: a shape nested inside a
/// rounded parent uses `concentric(parent:padding:)` — inner radius = outer
/// radius − padding — so corners share one optical center (Apple's iOS-26
/// rule; the tab-bar selection lens already does this right).
enum Radius {
    /// 28 — screens, sheets, full-bleed panes.
    static var pane: CGFloat { LayoutMetrics.s(28) }
    /// 22 — glass content cards (legacy surface; paper cards use `papier`).
    static var card: CGFloat { LayoutMetrics.s(22) }
    /// 14 — buttons, fields and tiles inside cards.
    static var control: CGFloat { LayoutMetrics.s(14) }
    /// 10 — ALL paper cards: cut paper is sharper than glass.
    static var papier: CGFloat { LayoutMetrics.s(10) }
    /// 4 — polaroid photo frames.
    static var polaroid: CGFloat { LayoutMetrics.s(4) }
    /// Chips and pills are capsules — use `Capsule()`, not a number.

    /// Inner radius for a shape inset by `padding` inside a parent radius.
    static func concentric(parent: CGFloat, padding: CGFloat) -> CGFloat {
        max(parent - padding, 2)
    }
}

// MARK: - Increased-contrast token variants

extension Theme {
    /// Token variants for `colorSchemeContrast == .increased` — views pass
    /// the environment flag, the values stay central (charter: raw design
    /// values live ONLY in this file). Only tokens whose default rendering
    /// is deliberately quiet have a louder sibling here.
    enum Contrast {
        static func textSecondary(increased: Bool) -> Color {
            increased ? Papier.aufNacht.opacity(0.92) : Theme.textSecondary
        }

        static func textTertiary(increased: Bool) -> Color {
            increased ? Papier.aufNacht.opacity(0.84) : Theme.textTertiary
        }

        /// Nacht.naht firms up to 0.38 under Increased Contrast — the
        /// seam stays warm paper white, only louder.
        static func hairline(increased: Bool) -> Color {
            increased ? Papier.aufNacht.opacity(0.38) : Theme.hairline
        }

        /// Matte tint wash behind pills/chips — Increased Contrast firms
        /// the fill so the capsule reads as a surface, not a ghost.
        static func tintFill(_ tint: Color, increased: Bool) -> Color {
            tint.opacity(increased ? 0.45 : 0.30)
        }
    }
}

// MARK: - Motion & transparency gate

extension Theme {
    /// Central Reduce-Motion / Reduce-Transparency policy (commandment 13)
    /// — views read it ONCE from the environment (`\.motionGate`) instead
    /// of re-deriving ad-hoc rules per feature:
    ///   * `ambient(_:)` — ornamental/endless animation becomes `nil` under
    ///     Reduce Motion, so pulses appear ONCE and settle instead of
    ///     looping forever.
    ///   * `particlesEnabled` — particle canvases (FloatingHearts) render a
    ///     static glow instead of a running timeline.
    ///   * `scrim(_:)` — manually painted full-screen dim layers become the
    ///     solid night ink under Reduce Transparency (system glass swaps
    ///     itself; hand-painted translucency is ours to replace).
    struct MotionGate {
        var reduceMotion = false
        var reduceTransparency = false

        /// Ornamental animation (endless pulses, drifts): `nil` under
        /// Reduce Motion — the state applies once, without choreography.
        func ambient(_ animation: Animation) -> Animation? {
            reduceMotion ? nil : animation
        }

        /// Particle canvases run only while motion is welcome.
        var particlesEnabled: Bool { !reduceMotion }

        /// Backdrop for full-screen overlay moments: translucent black at
        /// `baseOpacity` normally, the OPAQUE night ink under Reduce
        /// Transparency.
        func scrim(_ baseOpacity: Double) -> Color {
            reduceTransparency ? Theme.bgTop : Color.black.opacity(baseOpacity)
        }
    }
}

extension EnvironmentValues {
    /// Derived from the two system accessibility switches — ONE gate for
    /// every ornamental animation and manual-translucency decision.
    var motionGate: Theme.MotionGate {
        Theme.MotionGate(reduceMotion: accessibilityReduceMotion,
                         reduceTransparency: accessibilityReduceTransparency)
    }
}

// MARK: - Motion library

extension Theme {
    /// The four named motion curves of the app — every interaction uses
    /// exactly one of them (DESIGN.md, commandment 11). New curves are
    /// named here first, never invented inline in a feature.
    enum Motion {
        /// State changes, selection, toggles — calm and immediate.
        static let settle = Animation.spring(response: 0.35, dampingFraction: 0.85)
        /// Content appearing: cards, sheets, banners — a soft arrival.
        static let arrive = Animation.spring(response: 0.5, dampingFraction: 0.8)
        /// Slight overshoot — ONLY for heart/streak/game moments, never
        /// for navigation.
        static let playful = Animation.spring(response: 0.4, dampingFraction: 0.6)
        /// Ambient drift (ink dust, glows, particles). Pass the period the
        /// scene needs; ambience is measured in many seconds.
        static func drift(_ duration: TimeInterval = 6) -> Animation {
            .easeInOut(duration: duration)
        }

        // The three Papier & Licht motion signatures — named aliases on
        // the four existing curves; a fifth curve still does not exist.
        // Every signature runs through `motionGate` (commandment 13) and
        // owns a documented Reduce-Motion path.

        /// Blättern — screen/hero entry: the card rotates in around its
        /// leading edge (`rotation3DEffect` Signature.blaetternDegrees →
        /// 0°, anchor `.leading`, perspective Signature.blaetternPerspective).
        /// Reduce Motion: a pure crossfade. (FullRelease R1-A: prose
        /// trimmed to what the modifiers actually render — the once-planned
        /// synchronous shadow travel was never built and is not promised.)
        static var blaettern: Animation { arrive }
        /// Legen — elements appear: the Zettel lands (scale
        /// Signature.legenScale → 1.0, y-offset Signature.legenOffsetY →
        /// 0), staggered by Signature.legenStagger for at most
        /// Signature.legenBudget elements. Reduce Motion: fade, no
        /// transform. (FullRelease R1-A: shadow/rest-rotation prose
        /// removed — the modifiers land with scale + offset only.)
        static var legen: Animation { settle }
        /// Lichtschein — celebration/arrival: a radial Licht.lampengold
        /// glow blooms behind the element (opacity 0 → 0.35 → 0.22,
        /// radius 0 → 1.4 × element size) and then STAYS — the moment
        /// remains lit. Replaces confetti on delight levels 1–2; `epic`
        /// keeps its particles. Reduce Motion: the static end glow
        /// appears immediately — a painting, not a black hole.
        static var lichtschein: Animation { drift(1.2) }

        /// The choreography parameters of the three signatures — named
        /// here so no feature re-invents the numbers (commandment 11).
        enum Signature {
            /// Blättern: entry rotation around the leading edge.
            static let blaetternDegrees: Double = -12
            static let blaetternPerspective: CGFloat = 0.3
            /// Legen: landing transform and stagger budget.
            static let legenScale: CGFloat = 1.04
            static var legenOffsetY: CGFloat { LayoutMetrics.s(6) }
            static let legenStagger: TimeInterval = 0.04
            static let legenBudget = 6
            /// Lichtschein: bloom opacities and radius factor.
            static let lichtscheinPeakOpacity = 0.35
            static let lichtscheinRestOpacity = 0.22
            static let lichtscheinRadiusFactor: CGFloat = 1.4
        }
    }
}

// MARK: - Typography roles

/// Named type roles. Rounded = "the app speaks" (printed), New York serif
/// = "written by you two" (pen) — and SERIF APPEARS ONLY ON PAPER
/// surfaces, never on glass, never on night (Papier & Licht law). `voice`
/// (serif italic) stays reserved for words the couple wrote themselves —
/// the week quote, journal and capsule texts, anniversary titles — and
/// appears NOWHERE else. All roles build on semantic styles so Dynamic
/// Type keeps working (including AX5).
enum Typo {
    /// Max. once per screen.
    static let hero = Font.system(.largeTitle, design: .rounded).weight(.heavy)
    static let title = Font.system(.title3, design: .rounded).weight(.bold)
    static let body = Font.system(.body, design: .rounded)
    static let label = Font.system(.subheadline, design: .rounded).weight(.semibold)
    static let caption = Font.system(.caption, design: .rounded).weight(.semibold)
    /// Stats, streaks, levels — digits keep their width while counting;
    /// numbers are print work, never serif.
    static let number = Font.system(.title2, design: .rounded).weight(.bold).monospacedDigit()
    /// "Stimme der Beziehung" — only for text the partners wrote.
    static let voice = Font.system(.title3, design: .serif).italic()
    /// Letter BODY while reading (LetterComposer/Reader, journal full
    /// text) — the upright reading voice next to the italic `voice`.
    /// Paper surfaces only.
    static let brief = Font.system(.body, design: .serif)
    /// Postmarks, date lines on paper, "Für dich" address lines — THE one
    /// and only small-caps use of the app (ratchet `smallcaps_features`
    /// pins every other occurrence to 0). Above accessibility sizes the
    /// role drops small caps — legibility beats form (pass
    /// `dynamicTypeSize.isAccessibilitySize`).
    static func anschrift(isAccessibilitySize: Bool = false) -> Font {
        let base = Font.system(.caption, design: .serif).weight(.semibold)
        return isAccessibilitySize ? base : base.smallCaps()
    }
}

// MARK: - Brand title (the ONE brand-title treatment)

/// THE named brand/feature-title style: rounded-heavy type in the SOLID
/// couple-blend color. The charter forbids gradients on text (DESIGN.md d)
/// — this modifier replaces the previously five-times-copied three-stop
/// text gradient, and it makes the couple's shared color the signature
/// that carries every title.
struct BrandTitleStyle: ViewModifier {
    /// Hierarchy level of the title; the treatment never changes.
    var font: Font
    @Environment(\.coupleTint) private var coupleTint

    func body(content: Content) -> some View {
        content
            .font(font)
            .foregroundStyle(coupleTint.blend)
    }
}

extension View {
    /// Applies the brand-title treatment: solid `coupleTint.blend`,
    /// never a gradient on text. Pass a heavier/smaller rounded font for
    /// lower hierarchy levels; the default is the hero role.
    func brandTitle(_ font: Font = Typo.hero) -> some View {
        modifier(BrandTitleStyle(font: font))
    }
}

// MARK: - Couple tint (derived roles instead of hard-coded pink)

/// Color roles derived from the couple's palette. `blend` is the emotional
/// core: the contrast-secured mix of both members' colors (already computed
/// by `CouplePaletteRules.derived`) — the couple's shared signature color
/// for milestones, streaks and heart features.
struct CoupleTint {
    let primary: Color
    let secondary: Color
    /// The couple's shared color — mix of both member colors.
    let blend: Color
    /// Readable text/icon color on top of `blend`.
    let onBlend: Color
    /// Readable text/icon color on the two-stop `heroGradient` platter —
    /// judged against BOTH stops (the worst one wins, see
    /// `CouplePaletteRules.gradientForegroundVerdict`): light couple colors
    /// (mint, gold, sky) get the dark ink instead of hard white (A11y eval:
    /// white on mint 1.52:1, gold 1.44:1, blue 2.54:1).
    let onGradient: Color
    /// Text-protection scrim for the heroGradient (round-3 A11y): non-nil
    /// exactly when NO single ink clears 4.5:1 on both stops — the surface
    /// then paints this night-ink layer UNDER the label and `onGradient` is
    /// judged against the scrimmed stops. Every member-color pairing passes
    /// scrim-free (pinned by the PersonalizationLogic test matrix), so this
    /// only fires for palettes like the eval's violet/mint repro.
    let gradientTextScrim: Color?
    /// Couple ink for couple-tinted labels on WHITE fills (the own
    /// voice-note play/speed capsules): light secondaries fail on white
    /// (Schlussrunde 5 — mint 1.52:1, gold 1.44:1, sky 2.54:1), so the
    /// `accentOnLight` ladder darkens them toward the night ink until
    /// ≥4.5:1; dark secondaries pass through unchanged.
    let onLight: Color
    /// LEGACY (nacht-first P1-A): the gold-era stamp ink, judged against
    /// gold AND blend via the scrim-incapable single-ink rule — kept
    /// for the flat `wachs`-chip call sites (needs-ack wax drop, streak
    /// both-cell), where clearing the blend stop keeps them readable.
    /// The SEAL itself embosses with `aufWachs` on `wachsTief` now;
    /// the chips migrate in P2 (MIGRATION_DUNKEL.md).
    let onWax: Color
    /// The couple's DEEP seal wax (nacht-first): `blend` darkened
    /// through `CouplePaletteRules.waxDeepened` until the light
    /// embossing clears the floor — the `WachsSiegel` body, saturated
    /// instead of the pale gold-era pour.
    let wachsTief: Color
    /// Light embossing ink on the deep seal (Wachs.dunkel → wachsTief):
    /// the warm paper white, judged against BOTH deep-wax stops
    /// (pinned matrix — the Kino freeze proof case reversed).
    let aufWachs: Color

    // Papier & Licht — the couple colors as MATERIAL (Art Direction v2):
    // two inks, one wax, one band. Screens adopt these roles in the
    // paper waves; body copy on paper stays Tinte.dunkel — the couple
    // inks mark authorship and identity, never running text.

    /// "Deine Tinte" — the member's primary color as readable ink on
    /// every paper tone (`CouplePaletteRules.inkOnPaper`, ≥4.5:1 pinned).
    /// Use: 4-pt ink edge on own Zettel, signature lines, avatar rings.
    let tintePrimary: Color
    /// "Meine Tinte" — the partner color through the same ladder.
    let tinteSecondary: Color
    /// The couple's SHARED ink: `blend` through the paper ladder —
    /// `brandTitle` on paper carries this instead of the raw blend.
    let tinte: Color

    /// The couple's wax as FLAT material (pour animations, break echoes,
    /// ack chips) — the raw blend. The SEAL body is the deep `wachsTief`
    /// since nacht-first; flat-wax call sites keep `onWax` and migrate
    /// to `wachsTief`/`aufWachs` in P2 (MIGRATION_DUNKEL.md).
    var wachs: Color { blend }

    /// The couple's band — the heroGradient as a 6-pt OBJECT
    /// (`Papier.bandBreite`) wrapped around the one Briefbogen hero card
    /// per screen, crossed under the seal. The gradient leaves the
    /// surface and becomes a thing; it never returns as a card wash.
    var band: LinearGradient { heroGradient }

    /// Two-stop hero gradient from the couple's own colors.
    var heroGradient: LinearGradient {
        LinearGradient(colors: [primary, secondary],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    init(palette: CouplePalette?) {
        let firstHex: String
        let secondHex: String
        let accentHex: String
        if let palette {
            firstHex = palette.primary
            secondHex = palette.secondary
            accentHex = palette.accent
            primary = Color(hex: palette.primary)
            secondary = Color(hex: palette.secondary)
            blend = Color(hex: palette.accent)
            onBlend = Color(hex: palette.onAccent)
        } else {
            // Pre-pairing the tint speaks GOLDEN INK (Siegellack brand):
            // the wordmark and every fallback platter pour lamp gold →
            // copper instead of the retired pink/purple ramp — the
            // first-launch finale and the guide underneath match by
            // construction (both read this very fallback).
            firstHex = PaperRules.lampengoldHex
            secondHex = PaperRules.kupferHex
            accentHex = PaperRules.lampengoldHex
            primary = Licht.lampengold
            secondary = Licht.kupfer
            blend = Licht.lampengold
            onBlend = Color(hex: CouplePaletteRules.readableForeground(
                on: PaperRules.lampengoldHex))
        }
        let verdict = CouplePaletteRules.gradientForegroundVerdict(
            first: firstHex, second: secondHex)
        onGradient = Color(hex: verdict.hex)
        gradientTextScrim = verdict.needsScrim
            ? Color(hex: CouplePaletteRules.scrimHex).opacity(verdict.scrimOpacity)
            : nil
        // The white capsules wear the SECONDARY as tint — the ladder secures
        // exactly that color against the white fill.
        onLight = Color(hex: CouplePaletteRules.accentOnLight(secondHex))
        onWax = Color(hex: CouplePaletteRules.gradientForeground(
            first: Theme.goldHex, second: accentHex))
        // Deep couple wax (nacht-first): the blend deepened until the
        // light embossing clears the floor on it — seal body + stamp
        // ink come from the same pinned ladder (waxDeepened/waxEmboss).
        let wachsTiefHex = CouplePaletteRules.waxDeepened(accentHex)
        wachsTief = Color(hex: wachsTiefHex)
        aufWachs = Color(hex: CouplePaletteRules.waxEmbossInk(
            first: PaperRules.wachsDunkelHex, second: wachsTiefHex))
        // Paper inks: one ladder result per color, readable on every
        // paper tone (the darkest, Papier.kante, binds — pinned matrix).
        tintePrimary = Color(hex: CouplePaletteRules.inkOnPaper(firstHex))
        tinteSecondary = Color(hex: CouplePaletteRules.inkOnPaper(secondHex))
        tinte = Color(hex: CouplePaletteRules.inkOnPaper(accentHex))
    }
}

extension EnvironmentValues {
    /// Derived from `couplePalette` — available wherever the palette is
    /// injected, with a warm neutral fallback before pairing.
    var coupleTint: CoupleTint {
        CoupleTint(palette: couplePalette)
    }
}

private struct CouplePaletteEnvironmentKey: EnvironmentKey {
    static let defaultValue: CouplePalette? = nil
}

extension EnvironmentValues {
    var couplePalette: CouplePalette? {
        get { self[CouplePaletteEnvironmentKey.self] }
        set { self[CouplePaletteEnvironmentKey.self] = newValue }
    }
}

// MARK: - Backgrounds

/// Full-screen background — THE sepia room of Papier & Licht
/// (FullRelease R1-A, STYLE_DECISION §3.1): the fixed room gradient
/// (`Papier.zimmerOben` → `zimmerUnten`), ONE warm lamp cone falling in
/// from 10 o'clock (static, `Papier.lichtkegel` umbra plus a
/// `Licht.lampengold` core — the soft double falloff of the Remotion
/// `look.tsx` reference geometry), and a sparse couple-ink dust drifting
/// inside the cone. The aurora blobs, the full-surface couple gradient
/// and the star field are gone: full-bleed color washes were the old
/// glass era, and stars belong to the cinema night sky, not the room.
/// The couple's colors BREATHE in the room as Tintenstaub — they never
/// flood it.
///
/// Legend check (contrast anchors, nacht-first): the night inks
/// (`Papier.aufNacht`, `Nacht.sekundaer/tertiaer`) and the chrome glass
/// stay pinned against `zimmerOben` #1A100B; the cone paints at most
/// the pinned 0.30 `lichtkegel` + a 0.08 gold breath, which keeps
/// `aufNacht` ≥ 11:1 and the tertiary step ≥ 5.5:1 even at the lamp's
/// brightest point — late night, one lamp, never golden hour.
///
/// Central ambience throttle: the room renders under EVERY screen, so
/// the pause lives here once instead of in every feature. Room gradient
/// and lamp cone are STATIC layers and never invalidate; ONLY the dust
/// animates, and it freezes into a still painting (its t = 0 frame,
/// never a black hole) when
///   * Reduce Motion is on (accessibility contract, commandment 13),
///   * the scene is not active (background/app switcher — hidden dust
///     must not keep invalidating at 12 Hz), or
///   * Low Power Mode is on (the couple's battery outranks ambience).
///
/// Legacy props — the ~100 call sites stay API-identical: `showBlobs`
/// now gates the ink dust (the couple-color ambience the blobs used to
/// carry), `blobIntensity` scales its opacity, and `showStars` is
/// accepted but inert (the room has no stars to show; quiet screens
/// that passed `false` are exactly as quiet as before).
struct DreamyBackground: View {
    var showStars: Bool = true
    var showBlobs: Bool = true
    /// Dust opacity multiplier (legacy name). Screens stacking several
    /// equal cards (About) dampen the ambience so no card catches a
    /// bright hotspot and reads "brighter" than its neighbors (EVAL P2-7).
    var blobIntensity: Double = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.couplePalette) private var couplePalette
    /// Mirrors `ProcessInfo.processInfo.isLowPowerModeEnabled`; refreshed
    /// via notification because power state is not observable directly.
    @State private var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var ambientAnimated: Bool {
        !reduceMotion && !lowPowerMode && scenePhase == .active
    }

    var body: some View {
        ZStack {
            Theme.bgGradient
            LampenkegelView()
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

/// The ONE lamp of the room: a wide `Papier.lichtkegel` falloff plus a
/// tighter `Licht.lampengold` core, both radiating from the 10-o'clock
/// corner (geometry after the Remotion `look.tsx` `Room` — wide umbra
/// cone, then the golden heart). Completely static: the light is a fact
/// of the room, not an animation, so this layer never invalidates and
/// needs no motion gate. Nacht-first (P1-A): the cone tops out at the
/// pinned 0.30 paint and fades out EARLIER (0.62 instead of 0.72) —
/// one lamp late at night, not a golden-hour wash; the hotspot keeps
/// `aufNacht` ≥ 11:1 and the tertiary step ≥ 5.5:1 (legend above).
struct LampenkegelView: View {
    var body: some View {
        GeometryReader { geo in
            let side = max(geo.size.width, geo.size.height)
            ZStack {
                // Wide umbra falloff — the cone's soft outer breath,
                // tighter than the golden-hour original.
                RadialGradient(
                    stops: [
                        .init(color: Papier.lichtkegel.opacity(0.30), location: 0),
                        .init(color: Papier.lichtkegel.opacity(0.12), location: 0.38),
                        .init(color: .clear, location: 0.62),
                    ],
                    center: UnitPoint(x: 0.16, y: 0.04),
                    startRadius: 0, endRadius: side * 1.1)
                // Golden lamp core — the warmer heart of the double falloff.
                RadialGradient(
                    stops: [
                        .init(color: Licht.lampengold.opacity(0.08), location: 0),
                        .init(color: Licht.lampengold.opacity(0.03), location: 0.45),
                        .init(color: .clear, location: 0.66),
                    ],
                    center: UnitPoint(x: 0.14, y: 0.02),
                    startRadius: 0, endRadius: side * 0.55)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Tintenstaub — sparse couple-ink dust drifting inside the lamp cone
/// (the jury precision in STYLE_DECISION §3.1): half the motes carry the
/// one member's color, half the other's, at half opacity and only WITHIN
/// the cone. One Canvas pass at ≤ 12 Hz while ambience is welcome; the
/// central throttle passes `animated: false` and the dust becomes its
/// still t = 0 painting.
struct TintenstaubView: View {
    var animated: Bool = true
    var palette: CouplePalette?
    /// Opacity multiplier, 0…1 — see `DreamyBackground.blobIntensity`.
    var intensity: Double = 1

    private struct Mote {
        let along: Double    // start position on the cone axis, 0…1
        let cross: Double    // −1…+1 across the axis
        let radius: CGFloat
        let speed: Double
        let phase: Double
        let twinkle: Double
    }

    /// Seeded once (PaperRules law, same family as every paper physic) —
    /// the dust never flickers between renders.
    private static let motes: [Mote] = {
        let seed: UInt64 = 0x54_49_4E_54_45 // "TINTE"
        func rnd(_ mote: Int, _ slot: Int) -> Double {
            PaperRules.unitRandom(seed: seed, index: mote * 7 + slot)
        }
        return (0..<18).map { i in
            Mote(along: rnd(i, 0),
                 cross: rnd(i, 1) * 2 - 1,
                 radius: 1.2 + CGFloat(rnd(i, 2)) * 2.2,
                 speed: 0.3 + rnd(i, 3) * 0.7,
                 phase: rnd(i, 4) * 2 * .pi,
                 twinkle: 0.5 + rnd(i, 5))
        }
    }()

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { timeline in
                canvas(t: timeline.date.timeIntervalSinceReferenceDate)
            }
            .allowsHitTesting(false)
        } else {
            canvas(t: 0)
                .allowsHitTesting(false)
        }
    }

    private func canvas(t: TimeInterval) -> some View {
        // Pre-pairing the dust glows in the golden ink (never the retired
        // pink/purple) — the guide's quiet night ambience IS the brand.
        let first = palette.map { Color(hex: $0.primary) } ?? Licht.lampengold
        let second = palette.map { Color(hex: $0.secondary) } ?? Licht.kupfer
        return Canvas { context, size in
            for (index, mote) in Self.motes.enumerated() {
                // Slow drift down the cone axis (10 o'clock → room center)
                // with a gentle cross-sway and a soft twinkle.
                let along = (mote.along + t * 0.008 * mote.speed)
                    .truncatingRemainder(dividingBy: 1)
                let spread = 0.06 + along * 0.30
                let x = (0.15 + along * 0.55 + mote.cross * spread) * size.width
                let y = (0.03 + along * 0.72
                         + sin(t * mote.speed + mote.phase) * 0.012) * size.height
                // Only inside the cone: dust fades toward the axis edge
                // and toward the cone's end — the room stays a room.
                let inCone = (1 - abs(mote.cross)) * max(0, 1.1 - along)
                let twinkle = 0.6 + 0.4 * sin(t * mote.twinkle + mote.phase)
                let opacity = 0.5 * inCone * twinkle * intensity
                guard opacity > 0.02 else { continue }
                let color = index.isMultiple(of: 2) ? first : second
                let rect = CGRect(x: x - mote.radius, y: y - mote.radius,
                                  width: mote.radius * 2, height: mote.radius * 2)
                context.fill(Path(ellipseIn: rect),
                             with: .color(color.opacity(opacity)))
            }
        }
    }
}

// MARK: - Card & buttons (Liquid Glass)

/// The three named card densities — the ONLY paddings a glass card may
/// have. Free-hand numbers produced nine competing card rhythms across
/// the features (EVAL P1-10); every card now breathes on the Space scale.
enum CardPadding {
    /// Dense rows, tiles and secondary cards — `Space.m`.
    case compact
    /// The default content card — `Space.l`.
    case regular
    /// Hero stages and panes that earn extra air — `Space.xl`.
    case hero

    /// Scaled padding (Space tokens already follow `LayoutMetrics`).
    var value: CGFloat {
        switch self {
        case .compact: return Space.m
        case .regular: return Space.l
        case .hero: return Space.xl
        }
    }
}

/// Content card = `GlassLevel.surface`: the REAL iOS-26 glass renders
/// refraction, specular edge and adaptive behavior itself — the previous
/// hand-painted material/gradient/stroke stack painted OVER that system
/// glass and is deliberately gone (DESIGN.md: never rebuild glass on top
/// of glass). Only the elevation shadow lifts the pane off the aurora.
///
/// DEPRECATED (Zwei-Materialien-Gesetz, Papier & Licht): content that
/// LIES becomes opaque paper — new cards use `paperCard(_:padding:)`;
/// this modifier stays FUNCTIONAL while the screen waves migrate the
/// 323 call sites (ratchet `surface_glass_features` counts them to 0).
struct GlassCardModifier: ViewModifier {
    /// Scaled padding (comes from a `CardPadding` token).
    var padding: CGFloat = Space.l

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .glass(.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius,
                                                  style: .continuous))
    }
}

extension View {
    /// A named card density instead of a raw padding number — the card
    /// rhythm is a token, not a taste (EVAL P1-10).
    ///
    /// DEPRECATED (Papier & Licht): stays functional as the glass-era
    /// card; the paper target API is `paperCard(_:padding:)` in Glass.swift
    /// — the screen waves swap call sites, never this shim.
    func glassCard(_ padding: CardPadding = .regular) -> some View {
        modifier(GlassCardModifier(padding: padding.value))
    }

    /// Apple accessibility minimum. Unlike visual spacing, hit targets must
    /// not shrink with the responsive phone-layout scale.
    func minimumHitTarget() -> some View {
        frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }
}

/// „Siegellack" — THE brand primary button (Papier & Licht): the action
/// is a seal of deep wax, poured `Wachs.rot` → `Wachs.dunkel` (the
/// WachsSiegel direction), its label written in letter paper
/// (`Papier.brief`, pinned ≥ 4.5:1 on BOTH pour stops — never hard
/// white, never a computed per-couple verdict: the seal is the same wax
/// for every couple). The lamp catches the pour's upper lip
/// (`Wachs.lichtkante`, derived in PaperRules like the night-card
/// Lichtkante); pressed, the seal is SET — the pour darkens to the deep
/// wax, the light leaves the lip and the capsule settles onto the desk
/// (`Theme.Motion.settle`, elevation raised → resting).
///
/// Deliberately NOT `.buttonStyle(.glassProminent)`: wax is the app's
/// one brand material on primary actions, and glass cannot pour. The
/// opaque wax platter is Reduce-Transparency-safe on its own; system
/// glass button styles serve the NEUTRAL chrome buttons instead (see
/// ChatView, SecondaryButtonStyle).
struct PrimaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = true
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.bold))
            .foregroundStyle(Papier.brief)
            .padding(.vertical, LayoutMetrics.s(14))
            .padding(.horizontal, LayoutMetrics.s(22))
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 44)
            .background(
                Capsule()
                    .fill(LinearGradient(
                        colors: pressed ? [Wachs.dunkel, Wachs.dunkel]
                                        : [Wachs.rot, Wachs.dunkel],
                        startPoint: .top, endPoint: .bottom))
                    // The 10-o'clock lamp on the wax lip — gone while the
                    // seal is pressed into the desk.
                    .overlay(Capsule().strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Wachs.lichtkante.opacity(pressed ? 0.3 : 1),
                                      location: 0),
                                .init(color: Wachs.lichtkante.opacity(pressed ? 0.1 : 0.35),
                                      location: 0.35),
                                .init(color: .clear, location: 0.7),
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: Theme.hairlineWidth))
                    // Increased Contrast: the seal edge firms up in the
                    // label's own paper tone.
                    .overlay {
                        if colorSchemeContrast == .increased {
                            Capsule().strokeBorder(Papier.brief.opacity(0.6),
                                                   lineWidth: Theme.hairlineWidth)
                        }
                    }
                    .elevation(pressed ? .resting : .raised)
            )
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(Theme.Motion.settle, value: pressed)
            // iPad pointer: primary actions lift under the cursor.
            .hoverEffect(.lift)
    }
}

/// Secondary actions ride on real interactive system glass — the springy
/// press response comes from the glass itself, identical to system chrome.
/// Kept as a custom style (instead of `.buttonStyle(.glass)`) because it
/// carries the app's typography and paddings; the MATERIAL is the same
/// system glass, so Reduce Transparency/Increased Contrast degrade it
/// exactly like the system style would.
struct SecondaryButtonStyle: ButtonStyle {
    var fullWidth: Bool = true
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.vertical, LayoutMetrics.s(13))
            .padding(.horizontal, LayoutMetrics.s(20))
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 44)
            .glassEffect(.regular.interactive(), in: Capsule())
            // Increased Contrast: a firm edge line on the glass capsule —
            // the same strengthening the primary platter already carries.
            .overlay {
                if colorSchemeContrast == .increased {
                    Capsule().strokeBorder(Theme.Contrast.hairline(increased: true),
                                           lineWidth: Theme.hairlineWidth)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Theme.Motion.settle, value: configuration.isPressed)
            .hoverEffect(.lift)
    }
}
