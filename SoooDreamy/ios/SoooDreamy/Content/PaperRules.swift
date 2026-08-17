import Foundation

/// The Foundation law table of "Papier & Licht" (Art Direction v2,
/// STYLE_DECISION §3): every contrast-critical hex, the grain cap, the
/// kitsch budgets and the seeded tilt/torn math live HERE — not in
/// Theme.swift — following the heroGradient-stop precedent: the Logic
/// target must be able to prove the verdicts against the exact rendered
/// values, so `Theme`/`Papier`/`Tinte`/`Licht`/`Wachs` CONSUME these
/// constants and the rendered token and its contrast math can never
/// drift apart. Pure UI choreography (spring curves, paddings) stays in
/// the UI layer as before.
enum PaperRules {
    // MARK: Night tones — the room (contrast anchor: zimmerOben)

    /// Dark sepia umbra, upper screen edge — the night anchor of
    /// `CouplePaletteRules.darkBackground` (was the violet #17062A).
    /// NACHT-FIRST (P1-A): one step darker than the founding #201613 —
    /// the room is LATE night now, not golden hour (user feedback: the
    /// art style read "viel zu hell").
    static let zimmerObenHex = "#1A100B"
    /// Warm chestnut, lower edge — the room grows warmer toward the lamp
    /// (nacht-first: was #33241B; the old bottom tone became the card).
    static let zimmerUntenHex = "#2A1B12"
    /// The ONE radial lamp glow from 10 o'clock (opacity 0.30 → 0).
    static let lichtkegelHex = "#4A3320"

    // MARK: Night cardboard — the STANDARD content surface (nacht-first)

    /// Cardboard at night — THE standard card of the app since the
    /// nacht-first rebalance (P1-A): dark, warm, matte, described with
    /// `aufNacht` ink. Light paper (`brief`/`polaroid`) is EXCLUSIVELY
    /// for hero/artifact moments (letters, Tagesfrage-Briefbogen,
    /// polaroid frames, Zeitpost envelope, receipt Zettel) — paper is
    /// something special in a dark room, not wallpaper. This is the
    /// THIRD contrast anchor: every `aufNacht` ink step must clear
    /// 4.5:1 here (pinned below).
    static let nachtkartonHex = "#33241C"

    /// The warm 1-pt light edge on night cards: `nachtkarton` mixed
    /// toward the lamp gold at this pinned amount. Derived, never
    /// hand-picked (#664C30 today) — and DECOR only: 1.9:1 on the card,
    /// deliberately below the text floor.
    static let nachtLichtkanteMix = 0.25
    static var nachtLichtkanteHex: String {
        RGBColor(hex: nachtkartonHex)!
            .mixed(with: RGBColor(hex: lampengoldHex)!,
                   amount: nachtLichtkanteMix)
            .hex
    }

    // MARK: Paper tones — the content (opaque, replace the glass cards)

    /// Letter paper — the standard card surface and the PAPER anchor of
    /// the double-anchor contrast law (`inkOnPaper`).
    static let briefHex = "#F7F1E4"
    /// Cardboard — secondary cards, partner Zettel, inner surfaces.
    static let kartonHex = "#EFE6D2"
    /// Stacked edge / card backs / dividers ON paper. NOT a text ground:
    /// `Tinte.tertiaer` measures 4.45:1 here — deliberately pinned BELOW
    /// the floor by the Logic tests so nobody ever sets copy on the edge
    /// tone (text papers are brief/karton/polaroid).
    static let kanteHex = "#E3D6BC"
    /// Polaroid frame (photos only).
    static let polaroidHex = "#FAF6EC"
    /// All four paper tones — `inkOnPaper` must clear the floor on every
    /// one of them (one author, one ink, any Zettel).
    static var paperHexes: [String] { [briefHex, kartonHex, kanteHex, polaroidHex] }
    /// The papers that may CARRY text (kante is edge material, see above).
    static var textPaperHexes: [String] { [briefHex, kartonHex, polaroidHex] }

    // MARK: Inks — text on paper (measured against briefHex)

    /// Primary text and headings on paper (13.6:1 on brief).
    static let tinteDunkelHex = "#2E2318"
    /// Secondary text — faded ink (7.5:1 on brief).
    static let tinteSekundaerHex = "#5A4A38"
    /// Timestamps, footnotes — never below `.caption` (5.7:1 on brief).
    static let tinteTertiaerHex = "#6E5C46"
    /// Success/confirmation ink ON paper (P6-C): a bottle-green from the
    /// same ink family — 6.8:1 on brief, 6.1:1 on karton, 7.0:1 on
    /// polaroid (all pinned ≥ 4.5). Like every ink it is paper-only:
    /// 2.5:1 on night, where success speaks in lamplight instead.
    static let tinteErfolgHex = "#2F5D42"
    static var inkHexes: [String] { [tinteDunkelHex, tinteSekundaerHex, tinteTertiaerHex] }

    /// Stempeltinte — the ink of the Stempelzeile printed on the Briefbogen
    /// hero ("MORGENPOST · TAG 137"). A named COMPOSITE, not an opacity:
    /// the old `Tinte.sekundaer.opacity(0.7)` composited to ~3.6:1 on brief
    /// (below the 4.5 floor). The stamp prints in the pure secondary ink
    /// (7.5:1 on brief, pinned) — faded by FAMILY, never by alpha.
    static var stempelTinteHex: String { tinteSekundaerHex }

    // MARK: Lamplight — accents on night (NEVER text on paper)

    /// Ceremony accent and glows on night (11.9:1 on zimmerOben, 9.5:1
    /// on nachtkarton). On paper it reads 1.4:1 — forbidden as text,
    /// legal only as a glow behind paper edges (the Logic tests pin
    /// BOTH directions).
    static let lampengoldHex = "#FFC46B"
    /// Second warm accent, active states on night (7.0:1 on zimmerOben,
    /// 5.6:1 on nachtkarton).
    static let glutHex = "#E8845E"
    /// Copper — the SECOND stop of the "goldene Tinte" brand gradient
    /// (Siegellack brand: the pink→purple hero gradient is history; the
    /// static brand platter pours lamp gold → copper now). An accent on
    /// night like its lamplight siblings (4.9:1 on zimmerOben, pinned)
    /// and NEVER text on paper (3.4:1 on brief, pinned below the floor
    /// — same law as the gold). The gradient ink is machine-judged via
    /// `CouplePaletteRules.gradientForegroundVerdict` against BOTH stops.
    static let kupferHex = "#B87333"
    /// Seal/stamp-pad wax — MATERIAL, never text on night (3.2:1 there,
    /// 5.2:1 on paper; both pinned).
    static let wachsRotHex = "#B33A3A"
    /// Deep seal wax (nacht-first P1-A): the dark, saturated pour the
    /// `WachsSiegel` gradient STARTS with — replaces the lamp-gold stop
    /// that washed the seal pale peach and forced a near-black stamp
    /// (the Kino freeze proof case). The light embossing (`aufNacht`)
    /// reads 8.1:1 on it (pinned); on night it stays MATERIAL like
    /// every wax (1.9:1, pinned below the floor).
    static let wachsDunkelHex = "#7E2429"
    /// Warn-amber wax (P6-C): the caution sibling of `Wachs.rot` — dark
    /// honey that reads as ink on every TEXT paper (5.3:1 brief, 4.8:1
    /// karton, 5.5:1 polaroid, pinned) and stays MATERIAL on night
    /// (3.2:1 there, pinned below the floor — same law as the red).
    static let wachsGelbHex = "#8A5A00"
    /// Countdown/expiry accent (P6-C, a semantic NAME, not a new color):
    /// running time glows in the ember — `glutHex` — on night (6.7:1
    /// pinned); ON PAPER a deadline writes in `wachsGelbHex` instead,
    /// because the ember reads 2.4:1 on brief (pinned below the floor).
    static var ablaufHex: String { glutHex }
    /// Text directly on the room (15.7:1) — replaces hard white. Also
    /// the ink of the THIRD anchor: 12.5:1 on `nachtkarton` (pinned).
    static let aufNachtHex = "#F3EAD9"
    /// Vulnerability red, unchanged hex — re-pinned against the NEW night
    /// anchor (6.8:1); still never in the couple-color channel.
    static let energyRedHex = "#F87171"

    // MARK: Night ink steps (P6-C — the 0.78/0.64 opacities become law)

    /// `Nacht.sekundaer` — secondary copy on the room: `aufNacht` at this
    /// opacity (composite 9.7:1 on zimmerOben, 8.1:1 on nachtkarton —
    /// both pinned ≥ 7). Was the anonymous `Theme.textSecondary` 0.78
    /// raw value.
    static let nachtSekundaerOpacity = 0.78
    /// `Nacht.tertiaer` — tertiary copy on the room: `aufNacht` at this
    /// opacity (composite 6.9:1 on zimmerOben, 6.0:1 on nachtkarton —
    /// both pinned ≥ 4.5). Was the anonymous `Theme.textTertiary` 0.64
    /// raw value (raised from 0.58 in the A11y eval).
    static let nachtTertiaerOpacity = 0.64

    /// The effective hex of `aufNacht` at `opacity` composited over the
    /// room — the Logic tests pin the night ink steps against the same
    /// sRGB blend SwiftUI renders.
    static func nightInkCompositeHex(opacity: Double) -> String {
        nightInkCompositeHex(opacity: opacity, overHex: zimmerObenHex)
    }

    /// Same composite over ANY night ground — the third anchor
    /// (`nachtkarton`) pins its ink steps through this (nacht-first).
    static func nightInkCompositeHex(opacity: Double,
                                     overHex ground: String) -> String {
        let room = RGBColor(hex: ground)!
        let ink = RGBColor(hex: aufNachtHex)!
        return room.mixed(with: ink, amount: opacity).hex
    }

    // MARK: Inner fill (the ONE sanctioned wash inside paper cards)

    /// `Papier.innenFill` = `Tinte.dunkel` at this opacity — pinned here
    /// so the Wordle absent verdict below is computed against the exact
    /// wash the cards render.
    static let innenFillOpacity = 0.05

    // MARK: Wordle stamp verdicts (P6-C — pinned, no view change)

    /// The letter-game's paper mapping, exactly as WordleView renders it
    /// today: correct = the full dark-ink stamp, present = the wax-red
    /// stamp pad, absent = the faded innenFill wash on the sheet. Pinned
    /// as law so the tile colors and their label verdicts (brief on
    /// correct/present, tertiaer on absent — all ≥ 4.5:1) never drift.
    static var wordleCorrectHex: String { tinteDunkelHex }
    static var wordlePresentHex: String { wachsRotHex }
    /// Absent is a WASH, not a paint bucket: `innenFill` composited over
    /// `brief` — derived through the same sRGB blend SwiftUI renders
    /// (#EDE7DA today), never hand-picked.
    static var wordleAbsentHex: String {
        RGBColor(hex: briefHex)!
            .mixed(with: RGBColor(hex: tinteDunkelHex)!, amount: innenFillOpacity)
            .hex
    }

    // MARK: Paper grain (the Korn cap — CI rule 5 of the ratchet rewrite)

    /// Luminance cap of the procedural paper grain: ±2 %, pinned by a
    /// Logic test — any increase breaks the build. No animation, no
    /// bitmap; under Increased Contrast the grain is OFF (0).
    static let grainLuminance = 0.02

    static func grainLuminance(increasedContrast: Bool) -> Double {
        increasedContrast ? 0 : grainLuminance
    }

    // MARK: Light edge (the 10-o'clock lamp, now a named token)

    /// The 1-pt light edge every paper card wears top-left: `Papier.brief`
    /// raised by +8 % luminance — the lamp IS the light source.
    static let lichtkanteBoost = 0.08

    /// Derived, not hand-picked: brief mixed toward white in hundredth
    /// steps until the luminance boost is reached — deterministic, so the
    /// Logic tests pin the edge against the same math the paper uses.
    static var lichtkanteHex: String {
        let brief = RGBColor(hex: briefHex)!
        let white = RGBColor(hex: "#FFFFFF")!
        let target = brief.luminance * (1 + lichtkanteBoost)
        var edge = brief
        for step in 1...100 where edge.luminance < target {
            edge = brief.mixed(with: white, amount: Double(step) / 100)
        }
        return edge.hex
    }

    // MARK: Siegellack (the brand primary button — Papier & Licht brand)

    /// The Siegellack pour: `PrimaryButtonStyle` fills wax red → deep
    /// wax (top → bottom, the WachsSiegel direction) and writes its
    /// label in letter paper. Semantic NAMES on existing wax/paper
    /// tones, no new hexes — pinned so button and contrast law can
    /// never drift: `Papier.brief` reads 5.2:1 on the red pour and
    /// 8.6:1 on the deep (pressed) pour, both ≥ 4.5 (pinned); the wax
    /// surface itself stays ≥ 3:1 against night AND paper grounds
    /// (UI-component floor), so the seal is visible in the room and on
    /// a letter alike.
    static var siegellackHex: String { wachsRotHex }
    /// The deep pour — the pressed ("gesetzt") state of the seal.
    static var siegellackTiefHex: String { wachsDunkelHex }
    /// The label ink on the seal: letter paper, never hard white.
    static var siegellackTextHex: String { briefHex }
    /// The lamp catches the wax pour's upper lip: `wachsRot` mixed
    /// toward the lamp gold at the SAME pinned amount as the night-card
    /// Lichtkante (`nachtLichtkanteMix`). Derived, never hand-picked
    /// (#C65D46 today) — and DECOR only: 1.4:1 on the pour, deliberately
    /// below the text floor.
    static var siegellackKanteHex: String {
        RGBColor(hex: wachsRotHex)!
            .mixed(with: RGBColor(hex: lampengoldHex)!,
                   amount: nachtLichtkanteMix)
            .hex
    }

    // MARK: Kitsch guardrails (charter v3 — review budgets, hard numbers)

    /// Max. paper artifacts per screen (seal, tape corner, postmark count).
    static let artifactBudgetPerScreen = 3
    /// Max. torn edges per screen.
    static let tornEdgeBudgetPerScreen = 1
    /// Max. rotated elements per screen.
    static let rotationBudgetPerScreen = 1
    /// FullRelease R1-D — the COLLECTION exception to the rotation law:
    /// a screen tilts ONE solitaire (rotationBudgetPerScreen) OR up to
    /// THREE Zettel inside a SINGLE collection — a card GRID whose items
    /// share one visual family (gallery month sections, polaroid walls).
    /// Never both on the same screen, never a second collection: the rule
    /// reads "Ein Screen kippt 1 Solitär ODER bis zu 3 in EINER Sammlung."
    static let rotationBudgetPerCollection = 3
    /// App-wide `TornEdgeShape` cap (charter_lint Deckel, not a ratchet):
    /// tears are the exception, never the rhythm.
    static let tornEdgeAppCap = 6

    // MARK: Seeded paper physics (PaperTilt / TornEdgeShape)

    /// Rotation range of the seeded `PaperTilt` token: −6°…+6°, max. one
    /// rotated element per screen.
    static let tiltMaxDegrees = 6.0
    /// Collection grids tilt QUIETER than a solitaire: grid cells sit
    /// tight and near the bottom chrome, and a full ±6° swings a card's
    /// corners (and its text) visually past its cell — on devices into
    /// the accessory line. Grid Zettel are damped to this fraction of
    /// `tiltMaxDegrees`.
    static let gridTiltDamping = 0.5
    /// Torn-edge jitter amplitude in points.
    static let tornAmplitude = 2.5
    /// Torn-edge jitter period in points (min…max).
    static let tornPeriodMin = 10.0
    static let tornPeriodMax = 14.0

    /// Deterministic hash behind every seeded paper decision — same LCG
    /// family as `StarFieldView`/`SeededRandom`, value in 0..<1. Seeds are
    /// stable item IDs, so a Zettel's tilt and tear NEVER flicker between
    /// renders.
    static func unitRandom(seed: UInt64, index: Int = 0) -> Double {
        var state = seed &+ UInt64(bitPattern: Int64(index)) &* 0x9E3779B97F4A7C15
        state = (state ^ (state >> 30)) &* 0xBF58476D1CE4E5B9
        state = (state ^ (state >> 27)) &* 0x94D049BB133111EB
        state ^= state >> 31
        return Double(state >> 11) / Double(1 << 53)
    }

    /// Seeded tilt in −tiltMaxDegrees…+tiltMaxDegrees.
    static func tiltDegrees(seed: UInt64) -> Double {
        (unitRandom(seed: seed) * 2 - 1) * tiltMaxDegrees
    }

    /// Seeded tilt for a Zettel INSIDE a collection grid — same seed
    /// math (a card keeps its lean), damped range.
    static func gridTiltDegrees(seed: UInt64) -> Double {
        tiltDegrees(seed: seed) * gridTiltDamping
    }

    /// Seeded torn-edge period within the allowed band.
    static func tornPeriod(seed: UInt64) -> Double {
        tornPeriodMin + unitRandom(seed: seed, index: 1) * (tornPeriodMax - tornPeriodMin)
    }

    /// Seeded jitter offset for tooth `index` of a torn edge, in
    /// −tornAmplitude…+tornAmplitude points.
    static func tornOffset(seed: UInt64, index: Int) -> Double {
        (unitRandom(seed: seed, index: index + 2) * 2 - 1) * tornAmplitude
    }
}
