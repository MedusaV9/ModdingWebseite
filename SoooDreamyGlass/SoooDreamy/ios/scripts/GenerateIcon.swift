// Renders the SoooDreamy app icon (1024x1024 PNG) purely from code so no
// binary assets need to live in the repo. Runs on macOS (CI) via:
//   swift ios/scripts/GenerateIcon.swift <output.png> [variant]
//
// FullRelease N3-Icon — motif 3.0 "Das versiegelte Polaroid"
// (STYLE_DECISION.md §3.8 / DIRECTION_PAPIER_LICHT.md §7). Four layers,
// back → front:
//   L1 Zimmer   — vertical variant gradient (palette `bg`, bent sepia-warm)
//                 + soft lamp cone falling in from 10 o'clock (invariant
//                 Licht.lampengold — the lamp is the brand, not the gift)
//   L2 Papier   — near-square polaroid card #FAF6EC with a wider bottom
//                 border, hairline edge #E3D6BC, tilted −4°, soft drop
//                 shadow toward 16 o'clock (invariant — paper is the brand)
//   L3 Licht/Foto — inside the photo window: two interflowing ink arcs
//                 (palette heart color + hue-shifted companion) over a dark
//                 photo ground — the memory the couple shares
//   L4 Siegel   — wax seal (heart hex bent toward Wachs.rot #B33A3A) sitting
//                 half over the lower polaroid edge, embossed heart relief,
//                 matte gloss point; light pool from `caustic` underneath
//
// v3.0 CLI contract is unchanged: `variant` selects one of the alternate-icon
// palettes (icon gifts — Agent C); omitted/unknown variants render "classic".
// NEW: when <output> ends in ".svg" the same geometry is emitted as an SVG
// (pure Foundation — runs on Linux) so the motif can be previewed off-macOS.
// CI keeps calling the .png form; nothing there changes.
//
// The `Palette` struct and the palette table are the frozen interface
// (IconVariantPreview + WidgetStudio mirror the same bg/heart hexes):
// the polaroid geometry reads `bg` (L1), `pane[1]` (== the published heart
// hex → L4 wax + L3 ink) and `caustic` (seal light pool). `aurora`, `glow`,
// `pane[0/2]` and `rim` are no longer read — data stays, no struct rework
// (STYLE_DECISION §3.8: "kein Struct-Umbau").
import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
#endif

let size = 1024
let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: GenerateIcon.swift <output.png|output.svg> [variant]\n".data(using: .utf8)!)
    exit(1)
}
let outURL = URL(fileURLWithPath: args[1])
try? FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)

// MARK: Variant palettes (v3.0 icon gifts) — FROZEN interface, do not edit.
//
// Hex-Änderungen ⇒ WidgetThemesTests nachziehen: die veröffentlichten Werte
// (bg-Stops + pane[1]-Herz) sind dreifach gespiegelt — AppIconKit.variants
// (IconGiftView.swift) und WidgetThemes.iconPalettes (Shared/WidgetStudio.swift)
// tragen dieselben Hexes, und `testIconPaletteHexesArePinnedToTheAppIconKitTable`
// pinnt sie hart. Wer hier einen Stop oder das Herz ändert, zieht beide
// Spiegel UND die Pin-Tabelle im selben Commit nach, sonst bricht der Build.

typealias RGB = (r: CGFloat, g: CGFloat, b: CGFloat)

/// Everything that differs between icon variants — the geometry, particles
/// and glass shading stay identical so the family reads as one set.
struct Palette {
    let bg: [RGB]        // 3 background gradient stops (bottom → top-right)
    let aurora: [RGB]    // 3 aurora blob colors
    let glow: RGB        // back glow behind the heart
    let pane: [RGB]      // 3 glass pane gradient stops
    let caustic: RGB     // light pooling at the heart's bottom tip
    let rim: RGB         // colored third stop of the rim light
}

let palettes: [String: Palette] = [
    // Nachtpostamt default (Gesamtbild-Eval S1): bg = PaperRules Nachtraum
    // ground (zimmerOben 1A100B, zimmerUnten 2A1B12, lichtkegel 4A3320),
    // pane[1] = goldene Tinte (Licht.lampengold FFC46B); the wax bends
    // toward Wachs.rot via `waxRedMix` below — tiefer Siegellack.
    "classic": Palette(
        bg: [(0.102, 0.063, 0.043), (0.165, 0.106, 0.071), (0.290, 0.200, 0.125)],
        aurora: [(1.0, 0.769, 0.420), (0.910, 0.518, 0.369), (0.722, 0.451, 0.200)],
        glow: (1.0, 0.769, 0.420),
        pane: [(1.0, 0.870, 0.620), (1.0, 0.769, 0.420), (0.722, 0.451, 0.200)],
        caustic: (1.0, 0.769, 0.420), rim: (1.0, 0.769, 0.420)),
    "sunset": Palette(
        bg: [(0.14, 0.03, 0.10), (0.35, 0.08, 0.14), (0.65, 0.22, 0.13)],
        aurora: [(1.0, 0.55, 0.25), (1.0, 0.35, 0.45), (1.0, 0.75, 0.30)],
        glow: (1.0, 0.45, 0.30),
        pane: [(1.0, 0.75, 0.55), (1.0, 0.45, 0.35), (0.85, 0.25, 0.45)],
        caustic: (1.0, 0.80, 0.60), rim: (1.0, 0.60, 0.40)),
    "midnight": Palette(
        bg: [(0.01, 0.01, 0.05), (0.03, 0.05, 0.14), (0.07, 0.10, 0.25)],
        aurora: [(0.20, 0.35, 0.85), (0.35, 0.25, 0.75), (0.10, 0.55, 0.85)],
        glow: (0.45, 0.65, 1.0),
        pane: [(0.70, 0.82, 1.0), (0.42, 0.55, 0.95), (0.30, 0.35, 0.80)],
        caustic: (0.75, 0.85, 1.0), rim: (0.55, 0.70, 1.0)),
    "mint": Palette(
        bg: [(0.01, 0.10, 0.10), (0.02, 0.20, 0.19), (0.05, 0.33, 0.28)],
        aurora: [(0.25, 0.90, 0.70), (0.15, 0.70, 0.75), (0.55, 0.95, 0.65)],
        glow: (0.35, 0.95, 0.75),
        pane: [(0.75, 1.0, 0.90), (0.35, 0.90, 0.72), (0.15, 0.60, 0.60)],
        caustic: (0.80, 1.0, 0.92), rim: (0.55, 0.95, 0.80)),
    "rose": Palette(
        bg: [(0.16, 0.05, 0.09), (0.30, 0.09, 0.16), (0.48, 0.16, 0.25)],
        aurora: [(1.0, 0.45, 0.60), (0.95, 0.60, 0.70), (0.85, 0.30, 0.50)],
        glow: (1.0, 0.50, 0.62),
        pane: [(1.0, 0.80, 0.86), (1.0, 0.50, 0.64), (0.80, 0.30, 0.52)],
        caustic: (1.0, 0.85, 0.90), rim: (1.0, 0.62, 0.75)),
    "ocean": Palette(
        bg: [(0.01, 0.04, 0.12), (0.02, 0.10, 0.24), (0.03, 0.20, 0.38)],
        aurora: [(0.10, 0.55, 0.85), (0.20, 0.75, 0.85), (0.25, 0.40, 0.90)],
        glow: (0.25, 0.70, 0.95),
        pane: [(0.65, 0.90, 1.0), (0.30, 0.70, 0.95), (0.20, 0.45, 0.85)],
        caustic: (0.70, 0.92, 1.0), rim: (0.45, 0.80, 1.0)),
    // Sibling separation against the golden classic: the gold GIFT
    // variant's heart is Kupfer (PaperRules B87333) since the recolor.
    "gold": Palette(
        bg: [(0.10, 0.05, 0.02), (0.22, 0.12, 0.04), (0.40, 0.24, 0.08)],
        aurora: [(1.0, 0.75, 0.30), (1.0, 0.55, 0.20), (0.95, 0.85, 0.45)],
        glow: (1.0, 0.78, 0.35),
        pane: [(1.0, 0.90, 0.65), (0.722, 0.451, 0.200), (0.85, 0.55, 0.20)],
        caustic: (1.0, 0.92, 0.70), rim: (1.0, 0.80, 0.45)),
    "lavender": Palette(
        bg: [(0.08, 0.06, 0.14), (0.16, 0.12, 0.28), (0.28, 0.22, 0.44)],
        aurora: [(0.70, 0.55, 0.95), (0.55, 0.45, 0.90), (0.85, 0.70, 1.0)],
        glow: (0.72, 0.58, 0.98),
        pane: [(0.90, 0.82, 1.0), (0.72, 0.55, 0.95), (0.50, 0.40, 0.85)],
        caustic: (0.92, 0.86, 1.0), rim: (0.78, 0.65, 1.0)),
    "blossom": Palette(
        bg: [(0.12, 0.02, 0.10), (0.24, 0.05, 0.20), (0.42, 0.12, 0.30)],
        aurora: [(1.0, 0.60, 0.80), (0.95, 0.40, 0.65), (1.0, 0.80, 0.88)],
        glow: (1.0, 0.55, 0.75),
        pane: [(1.0, 0.85, 0.92), (1.0, 0.55, 0.75), (0.75, 0.30, 0.60)],
        caustic: (1.0, 0.88, 0.94), rim: (1.0, 0.68, 0.85)),
    // v10 "aurora" — the tenth icon for the tenth version: polar-light teal
    // and violet dancing over a near-black sky.
    "aurora": Palette(
        bg: [(0.01, 0.03, 0.08), (0.03, 0.10, 0.16), (0.08, 0.20, 0.26)],
        aurora: [(0.20, 0.95, 0.70), (0.35, 0.55, 0.95), (0.65, 0.35, 0.90)],
        glow: (0.30, 0.90, 0.75),
        pane: [(0.72, 1.0, 0.92), (0.35, 0.85, 0.80), (0.45, 0.45, 0.90)],
        caustic: (0.78, 1.0, 0.94), rim: (0.55, 0.95, 0.85)),
]

let variantName = args.count >= 3 ? args[2] : "classic"
let pal = palettes[variantName] ?? palettes["classic"]!

// Deterministic PRNG so every CI run renders the identical icon.
var seed: UInt64 = 0x5EED_50DE
func rnd() -> Double {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return Double((seed >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
}

// MARK: Color math (pure Foundation — shared by both backends)

struct Ink {
    var r: Double, g: Double, b: Double, a: Double
    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    init(_ rgb: RGB, _ a: Double = 1) {
        self.init(Double(rgb.r), Double(rgb.g), Double(rgb.b), a)
    }
    init(hex: String, _ a: Double = 1) {
        var v: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&v)
        self.init(Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255, a)
    }
    func with(alpha: Double) -> Ink { Ink(r, g, b, alpha) }
    func mixed(with other: Ink, _ t: Double) -> Ink {
        Ink(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t, a + (other.a - a) * t)
    }
    func lightened(_ t: Double) -> Ink { mixed(with: Ink(1, 1, 1, a), t) }
    func darkened(_ t: Double) -> Ink { mixed(with: Ink(0, 0, 0, a), t) }
    /// HSL round-trip helpers — hue-preserving derivations (second ink,
    /// wax tone) that survive cool palettes where naive RGB mixes gray out.
    var hsl: (h: Double, s: Double, l: Double) {
        let mx = max(r, g, b), mn = min(r, g, b)
        let l = (mx + mn) / 2
        guard mx > mn else { return (0, 0, l) }
        let d = mx - mn
        let s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        var h: Double
        if mx == r { h = (g - b) / d + (g < b ? 6 : 0) }
        else if mx == g { h = (b - r) / d + 2 }
        else { h = (r - g) / d + 4 }
        return (h / 6, s, l)
    }
    static func fromHSL(_ h0: Double, _ s: Double, _ l: Double, _ a: Double = 1) -> Ink {
        var h = h0.truncatingRemainder(dividingBy: 1)
        if h < 0 { h += 1 }
        guard s > 0 else { return Ink(l, l, l, a) }
        func channel(_ t0: Double) -> Double {
            var t = t0
            if t < 0 { t += 1 }; if t > 1 { t -= 1 }
            let q = l < 0.5 ? l * (1 + s) : l + s - l * s
            let p = 2 * l - q
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        return Ink(channel(h + 1 / 3), channel(h), channel(h - 1 / 3), a)
    }
    func hueRotated(degrees: Double) -> Ink {
        let c = hsl
        return Ink.fromHSL(c.h + degrees / 360, c.s, c.l, a)
    }
    func withHSL(saturation: Double? = nil, lightness: Double? = nil) -> Ink {
        let c = hsl
        return Ink.fromHSL(c.h, saturation ?? c.s, lightness ?? c.l, a)
    }
}

// MARK: Derived variant colors

// Sibling separation (Widgets-Eval): after the sepia bend, classic/rose/
// blossom and mint/aurora rendered near-identical rooms and wax at home-
// screen size. The published palette table above stays FROZEN — the
// separation happens in the DERIVED colors only: rose lifts its room
// ground +8 % lightness, blossom sinks it −8 % (classic is the untouched
// anchor); mint turns its wax 8° greener, aurora 8° bluer. Conservative
// on purpose — the family must still read as one set.
let roomLightnessFactor: [String: Double] = ["rose": 1.08, "blossom": 0.92]
let waxHueDegrees: [String: Double] = ["mint": -8, "aurora": 8]
// Nachtpostamt-Umfärbung (Gesamtbild-Eval S1): classic's published heart is
// the GOLDEN INK (Licht.lampengold FFC46B) — wax poured straight from gold
// would read as amber, not as sealing wax. The default icon bends its wax
// decisively toward Wachs.rot instead (tiefer Siegellack under golden ink,
// like every letter in the app); all gift variants keep the gentle 0.22.
// IconVariantPreview mirrors this with a stronger Wachs.rot overlay.
let waxRedMix: [String: Double] = ["classic": 0.72]

// L1 room: variant bg bent toward warm lamp-lit sepia. The bend also lifts
// pitch-dark palettes a touch so the icon edge never melts into a dark or
// tinted home screen.
let sepia = Ink(0.42, 0.31, 0.20)
let room: [Ink] = {
    let base = pal.bg.map { Ink($0).mixed(with: sepia, 0.16) }
    guard let factor = roomLightnessFactor[variantName] else { return base }
    return base.map { $0.withHSL(lightness: min(1, $0.hsl.l * factor)) }
}()

// Invariant brand tones (Papier & Licht — DIRECTION_PAPIER_LICHT §7).
let lampGold = Ink(hex: "FFC46B")
let paperTone = Ink(hex: "FAF6EC")
let paperEdge = Ink(hex: "E3D6BC")

// pane[1] IS the published heart hex of every variant (AppIconKit.Variant
// mirrors it) — the frozen bridge into the wax + ink colors.
let heartInk = Ink(pal.pane[1])
let waxRed = Ink(hex: "B33A3A")               // Wachs.rot (STYLE_DECISION §2)
// Wax = the heart hex as MATERIAL: keep its hue, push saturation up and
// lightness into wax depth (HSL), then bend gently toward Wachs.rot. A big
// RGB mix would gray out cool palettes (mint/ocean/aurora) completely.
let heartHSL = heartInk.hsl
let wax: Ink = {
    let base = Ink.fromHSL(heartHSL.h, min(1, heartHSL.s * 1.15 + 0.08),
                           min(0.46, max(0.34, heartHSL.l * 0.72)))
        .mixed(with: waxRed, waxRedMix[variantName] ?? 0.22)
    guard let degrees = waxHueDegrees[variantName] else { return base }
    return base.hueRotated(degrees: degrees)
}()
let waxHSL = wax.hsl
let waxLight = Ink.fromHSL(waxHSL.h, waxHSL.s, min(0.72, waxHSL.l + 0.17)).mixed(with: lampGold, 0.12)
let waxDeep = Ink.fromHSL(waxHSL.h, min(1, waxHSL.s * 1.05), max(0.14, waxHSL.l - 0.20))
let inkA = heartInk
let inkB = heartInk.hueRotated(degrees: -40).darkened(0.08)
let photoTop = Ink(pal.bg[0]).mixed(with: Ink(0.02, 0.015, 0.02), 0.60)
let photoBottom = Ink(pal.bg[1]).mixed(with: Ink(0.05, 0.03, 0.04), 0.42)
let causticInk = Ink(pal.caustic)

// MARK: Geometry model (y-down, 1024-space — shared by both backends)

struct Pt { var x: Double; var y: Double }

enum PathOp {
    case move(Pt)
    case line(Pt)
    case curve(Pt, Pt, Pt)   // control1, control2, end
    case close
}

func roundedRectOps(x: Double, y: Double, w: Double, h: Double, r: Double) -> [PathOp] {
    let k = 0.5523 * r   // kappa: circle-from-bezier constant
    return [
        .move(Pt(x: x + r, y: y)),
        .line(Pt(x: x + w - r, y: y)),
        .curve(Pt(x: x + w - r + k, y: y), Pt(x: x + w, y: y + r - k), Pt(x: x + w, y: y + r)),
        .line(Pt(x: x + w, y: y + h - r)),
        .curve(Pt(x: x + w, y: y + h - r + k), Pt(x: x + w - r + k, y: y + h), Pt(x: x + w - r, y: y + h)),
        .line(Pt(x: x + r, y: y + h)),
        .curve(Pt(x: x + r - k, y: y + h), Pt(x: x, y: y + h - r + k), Pt(x: x, y: y + h - r)),
        .line(Pt(x: x, y: y + r)),
        .curve(Pt(x: x, y: y + r - k), Pt(x: x + r - k, y: y), Pt(x: x + r, y: y)),
        .close,
    ]
}

/// Hand-poured wax blob: circle whose radius breathes with two low-frequency
/// sinusoids (seeded once → deterministic across runs and backends).
func waxBlobOps(cx: Double, cy: Double, radius: Double, phase1: Double, phase2: Double) -> [PathOp] {
    var ops: [PathOp] = []
    let steps = 180
    for i in 0...steps {
        let t = Double(i) / Double(steps) * 2 * .pi
        let wobble = 1 + 0.022 * sin(3 * t + phase1) + 0.014 * sin(7 * t + phase2)
        let p = Pt(x: cx + cos(t) * radius * wobble, y: cy + sin(t) * radius * wobble)
        ops.append(i == 0 ? .move(p) : .line(p))
    }
    ops.append(.close)
    return ops
}

/// Classic parametric heart, emitted y-down (visual match with the SwiftUI
/// HeartGlyph used by IconVariantPreview).
func heartOps(cx: Double, cy: Double, scale: Double) -> [PathOp] {
    var ops: [PathOp] = []
    let steps = 200
    for i in 0...steps {
        let t = Double(i) / Double(steps) * 2 * .pi
        let hx = 16 * pow(sin(t), 3)
        let hy = 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)
        let p = Pt(x: cx + hx * scale, y: cy - hy * scale)
        ops.append(i == 0 ? .move(p) : .line(p))
    }
    ops.append(.close)
    return ops
}

/// Tapered ink ribbon along a cubic bezier spine — the "flowing ink arc".
/// The width swells around `belly` (0…1 along the spine) and tapers toward
/// calligraphic tips, so the strokes read as leaning figures, not tubes.
func ribbonOps(_ p0: Pt, _ c1: Pt, _ c2: Pt, _ p3: Pt, maxWidth: Double,
               tipWidth: Double = 3, belly: Double = 0.5) -> [PathOp] {
    let samples = 56
    func point(_ t: Double) -> Pt {
        let u = 1 - t
        let x = u * u * u * p0.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * p3.x
        let y = u * u * u * p0.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * p3.y
        return Pt(x: x, y: y)
    }
    func tangent(_ t: Double) -> Pt {
        let u = 1 - t
        let x = 3 * u * u * (c1.x - p0.x) + 6 * u * t * (c2.x - c1.x) + 3 * t * t * (p3.x - c2.x)
        let y = 3 * u * u * (c1.y - p0.y) + 6 * u * t * (c2.y - c1.y) + 3 * t * t * (p3.y - c2.y)
        let len = max(1e-6, (x * x + y * y).squareRoot())
        return Pt(x: x / len, y: y / len)
    }
    // Remap t so the width peak sits at `belly` instead of the middle.
    let skew = log(0.5) / log(max(0.05, min(0.95, belly)))
    var left: [Pt] = [], right: [Pt] = []
    for i in 0...samples {
        let t = Double(i) / Double(samples)
        let w = tipWidth + (maxWidth - tipWidth) * pow(sin(.pi * pow(t, skew)), 0.72)
        let c = point(t), tan = tangent(t)
        let n = Pt(x: -tan.y, y: tan.x)
        left.append(Pt(x: c.x + n.x * w / 2, y: c.y + n.y * w / 2))
        right.append(Pt(x: c.x - n.x * w / 2, y: c.y - n.y * w / 2))
    }
    var ops: [PathOp] = [.move(left[0])]
    for p in left.dropFirst() { ops.append(.line(p)) }
    for p in right.reversed() { ops.append(.line(p)) }
    ops.append(.close)
    return ops
}

// MARK: Paint & canvas abstraction

struct Stop { var color: Ink; var at: Double }

enum Paint {
    case solid(Ink)
    case linear([Stop], Pt, Pt)
    /// Radial gradient with independent x/y radii (soft light pools/cones).
    case radial([Stop], Pt, Double, Double)
}

protocol IconCanvas {
    func fill(_ ops: [PathOp], _ paint: Paint)
    func stroke(_ ops: [PathOp], _ color: Ink, width: Double)
    func pushRotation(degrees: Double, about: Pt)
    func pushTranslation(dx: Double, dy: Double)
    func pop()
    /// Fine luminance noise over what's drawn so far — breaks gradient
    /// banding in the 8-bit PNG. No-op for the (float-rendered) SVG preview.
    func dither(count: Int, maxAlpha: Double)
}

// MARK: The motif — drawn exactly once, for every backend

let canvasD = Double(size)

// L2 paper card: near-square, wider bottom border, optical center above mid.
let paperW = 640.0, paperBorder = 44.0, paperBottomBorder = 146.0
let photoW = paperW - 2 * paperBorder                       // 552
let paperH = paperBorder + photoW + paperBottomBorder       // 742
let paperX = (canvasD - paperW) / 2                         // 192
let paperY = 90.0
let paperCenter = Pt(x: canvasD / 2, y: paperY + paperH / 2)
let paperTilt = -4.0
// L4 seal: Ø ~34 % icon width, straddling the lower paper edge, right of mid.
let sealR = 170.0
let sealC = Pt(x: paperX + paperW * 0.63, y: paperY + paperH)

func drawIcon(on c: IconCanvas) {
    let full = roundedRectOps(x: 0, y: 0, w: canvasD, h: canvasD, r: 0.01)

    // ---- L1 Zimmer: sepia-warmed variant gradient, brightest at the top
    // where the lamp lives, darkest at the floor.
    c.fill(full, .linear([
        Stop(color: room[2], at: 0),
        Stop(color: room[1], at: 0.52),
        Stop(color: room[0], at: 1),
    ], Pt(x: canvasD / 2, y: 0), Pt(x: canvasD / 2, y: canvasD)))

    // Lamp cone from 10 o'clock — invariant Licht.lampengold, radial falloff.
    c.fill(full, .radial([
        Stop(color: lampGold.with(alpha: 0.55), at: 0),
        Stop(color: lampGold.with(alpha: 0.22), at: 0.45),
        Stop(color: lampGold.with(alpha: 0), at: 1),
    ], Pt(x: 110, y: -60), 950, 870))
    // Broad diagonal glaze so the light reads as direction, not as a disc.
    c.fill(full, .linear([
        Stop(color: lampGold.with(alpha: 0.12), at: 0),
        Stop(color: lampGold.with(alpha: 0), at: 1),
    ], Pt(x: 0, y: 0), Pt(x: 720, y: 720)))
    // Floor falloff grounds the scene (and the icon's bottom edge).
    c.fill(full, .linear([
        Stop(color: Ink(0, 0, 0, 0), at: 0),
        Stop(color: Ink(0, 0, 0, 0.22), at: 1),
    ], Pt(x: canvasD / 2, y: 760), Pt(x: canvasD / 2, y: canvasD)))

    c.dither(count: 9000, maxAlpha: 0.022)

    // ---- L2 Papier: tilt group (−4° about the card center).
    c.pushRotation(degrees: paperTilt, about: paperCenter)

    // Stacked soft drop shadow toward 16 o'clock (down-right) — every layer
    // is inflated so no un-blurred duplicate edge shows next to the card.
    let shadowSteps: [(offset: Double, grow: Double, alpha: Double)] = [
        (1, 6, 0.085), (2, 16, 0.065), (3, 28, 0.05), (4, 42, 0.038), (5, 58, 0.026),
    ]
    for s in shadowSteps {
        c.fill(roundedRectOps(x: paperX - s.grow / 2 + s.offset * 10,
                              y: paperY - s.grow / 2 + s.offset * 6.5,
                              w: paperW + s.grow, h: paperH + s.grow, r: 14 + s.grow / 2),
               .solid(Ink(0.03, 0.01, 0.03, s.alpha)))
    }

    // Paper: invariant warm white, faint vertical shading toward the bottom.
    let paperOps = roundedRectOps(x: paperX, y: paperY, w: paperW, h: paperH, r: 14)
    c.fill(paperOps, .linear([
        Stop(color: paperTone.lightened(0.05), at: 0),
        Stop(color: paperTone, at: 0.45),
        Stop(color: paperTone.mixed(with: Ink(0.72, 0.66, 0.55), 0.10), at: 1),
    ], Pt(x: paperCenter.x, y: paperY), Pt(x: paperCenter.x, y: paperY + paperH)))
    // Lamp kiss on the top-left of the card.
    c.fill(paperOps, .radial([
        Stop(color: lampGold.with(alpha: 0.20), at: 0),
        Stop(color: lampGold.with(alpha: 0), at: 1),
    ], Pt(x: paperX + 50, y: paperY + 24), 560, 500))
    c.stroke(paperOps, paperEdge, width: 3)

    // ---- L3 the photo window ("die Erinnerung").
    let winX = paperX + paperBorder, winY = paperY + paperBorder
    let winOps = roundedRectOps(x: winX, y: winY, w: photoW, h: photoW, r: 6)
    c.fill(winOps, .linear([
        Stop(color: photoTop, at: 0),
        Stop(color: photoBottom, at: 1),
    ], Pt(x: winX, y: winY), Pt(x: winX, y: winY + photoW)))
    // Corner vignette keeps the memory intimate.
    c.fill(winOps, .radial([
        Stop(color: Ink(0, 0, 0, 0), at: 0),
        Stop(color: Ink(0, 0, 0, 0), at: 0.68),
        Stop(color: Ink(0, 0, 0, 0.30), at: 1),
    ], Pt(x: winX + photoW / 2, y: winY + photoW / 2), photoW * 0.72, photoW * 0.72))
    // Recessed edges: inner shadow from top and left.
    c.fill(roundedRectOps(x: winX, y: winY, w: photoW, h: 30, r: 4), .linear([
        Stop(color: Ink(0, 0, 0, 0.38), at: 0), Stop(color: Ink(0, 0, 0, 0), at: 1),
    ], Pt(x: winX, y: winY), Pt(x: winX, y: winY + 30)))
    c.fill(roundedRectOps(x: winX, y: winY, w: 26, h: photoW, r: 4), .linear([
        Stop(color: Ink(0, 0, 0, 0.28), at: 0), Stop(color: Ink(0, 0, 0, 0), at: 1),
    ], Pt(x: winX, y: winY), Pt(x: winX + 26, y: winY)))

    // Two interflowing ink arcs — two figures leaning into each other.
    // Arc A (heart ink) stands tall and tips right; arc B (the hue-shifted
    // companion) is shorter and folds its head over A's shoulder — one
    // off-center crossing, like leaning heads. Bellies sit low so the
    // strokes ground like bodies; ink pools darker toward the tips so the
    // crossing reads as overlaid ink, not as a glow.
    let s = photoW / 552.0   // window-relative so paper resizes stay safe
    let a0 = Pt(x: winX + 190 * s, y: winY + 494 * s), a1 = Pt(x: winX + 138 * s, y: winY + 336 * s)
    let a2 = Pt(x: winX + 214 * s, y: winY + 148 * s), a3 = Pt(x: winX + 376 * s, y: winY + 94 * s)
    let b0 = Pt(x: winX + 402 * s, y: winY + 494 * s), b1 = Pt(x: winX + 446 * s, y: winY + 326 * s)
    let b2 = Pt(x: winX + 376 * s, y: winY + 164 * s), b3 = Pt(x: winX + 204 * s, y: winY + 122 * s)
    // Soft glow doubles beneath each stroke (ink bleeding into the photo).
    c.fill(ribbonOps(a0, a1, a2, a3, maxWidth: 176 * s, belly: 0.40), .solid(inkA.with(alpha: 0.15)))
    c.fill(ribbonOps(b0, b1, b2, b3, maxWidth: 162 * s, belly: 0.40), .solid(inkB.with(alpha: 0.15)))
    c.fill(ribbonOps(a0, a1, a2, a3, maxWidth: 118 * s, belly: 0.40), .linear([
        Stop(color: inkA.darkened(0.14).with(alpha: 0.93), at: 0),
        Stop(color: inkA.lightened(0.16).with(alpha: 0.95), at: 1),
    ], a3, a0))
    c.fill(ribbonOps(b0, b1, b2, b3, maxWidth: 106 * s, belly: 0.40), .linear([
        Stop(color: inkB.darkened(0.16).with(alpha: 0.90), at: 0),
        Stop(color: inkB.lightened(0.12).with(alpha: 0.92), at: 1),
    ], b3, b0))
    // Photo gloss: one quiet sheen across the upper-left of the print.
    c.fill(winOps, .linear([
        Stop(color: Ink(1, 1, 1, 0.07), at: 0),
        Stop(color: Ink(1, 1, 1, 0), at: 0.55),
    ], Pt(x: winX, y: winY), Pt(x: winX + photoW, y: winY + photoW)))

    // ---- L4 Siegel (still inside the paper tilt so it rides the card edge;
    // +7° inside the −4° group = +3° absolute for the emboss).
    // Light pool from `caustic` under the seal's bottom edge.
    c.fill(full, .radial([
        Stop(color: causticInk.with(alpha: 0.26), at: 0),
        Stop(color: causticInk.with(alpha: 0), at: 1),
    ], Pt(x: sealC.x, y: sealC.y + sealR * 0.86), 250, 88))
    // Seal shadow (down-right, tighter than the card's).
    for i in 1...3 {
        let g = Double(i) * 8
        c.fill(waxBlobOps(cx: sealC.x + 10 + Double(i) * 3, cy: sealC.y + 13 + Double(i) * 4,
                          radius: sealR + g / 2, phase1: 0.7, phase2: 2.1),
               .solid(Ink(0.02, 0.0, 0.02, 0.10 - Double(i) * 0.025)))
    }
    // Wax body: light from 10 o'clock → highlight top-left, depth low-right.
    let blob = waxBlobOps(cx: sealC.x, cy: sealC.y, radius: sealR, phase1: 0.7, phase2: 2.1)
    c.fill(blob, .radial([
        Stop(color: waxLight, at: 0),
        Stop(color: wax, at: 0.55),
        Stop(color: waxDeep, at: 1),
    ], Pt(x: sealC.x - sealR * 0.34, y: sealC.y - sealR * 0.38), sealR * 1.5, sealR * 1.5))
    // Pressed rim: dark groove + light counter-edge (stamp die ring).
    c.stroke(waxBlobOps(cx: sealC.x, cy: sealC.y, radius: sealR * 0.78, phase1: 0.7, phase2: 2.1),
             waxDeep.with(alpha: 0.55), width: 11)
    c.stroke(waxBlobOps(cx: sealC.x, cy: sealC.y, radius: sealR * 0.71, phase1: 0.7, phase2: 2.1),
             waxLight.with(alpha: 0.35), width: 5)

    c.pushRotation(degrees: 7, about: sealC)
    // Embossed heart: recessed fill, shadow edge up-left, lit relief
    // stroke down-right (the light comes from 10 o'clock, the heart is
    // pressed IN, so its lower-right inner wall catches the lamp).
    let hs = 5.6
    c.fill(heartOps(cx: sealC.x, cy: sealC.y - 6, scale: hs),
           .solid(waxDeep.mixed(with: wax, 0.30).with(alpha: 0.95)))
    c.stroke(heartOps(cx: sealC.x - 3, cy: sealC.y - 10, scale: hs),
             waxDeep.with(alpha: 0.65), width: 6)
    c.stroke(heartOps(cx: sealC.x + 3, cy: sealC.y - 2, scale: hs),
             waxLight.lightened(0.25).with(alpha: 0.85), width: 6)
    c.pop()

    // Matte gloss point on the wax, upper-left.
    c.fill(blob, .radial([
        Stop(color: Ink(1, 1, 1, 0.20), at: 0),
        Stop(color: Ink(1, 1, 1, 0), at: 1),
    ], Pt(x: sealC.x - sealR * 0.42, y: sealC.y - sealR * 0.48), sealR * 0.42, sealR * 0.30))

    c.pop()   // paper tilt

    // Global quiet lamp glaze from above — ties the layers into one room.
    c.fill(full, .linear([
        Stop(color: Ink(1, 1, 1, 0.05), at: 0),
        Stop(color: Ink(1, 1, 1, 0), at: 1),
    ], Pt(x: canvasD / 2, y: 0), Pt(x: canvasD / 2, y: 430)))
}

// MARK: SVG backend (pure Foundation — Linux preview / off-macOS check)

final class SVGCanvas: IconCanvas {
    private var defs = ""
    private var body = ""
    private var gradientCount = 0
    private var openGroups = 0

    private func fmt(_ v: Double) -> String { String(format: "%.2f", v) }
    private func colorAttr(_ ink: Ink) -> String {
        String(format: "#%02X%02X%02X",
               Int((ink.r.clamped01) * 255 + 0.5),
               Int((ink.g.clamped01) * 255 + 0.5),
               Int((ink.b.clamped01) * 255 + 0.5))
    }
    private func pathData(_ ops: [PathOp]) -> String {
        var d = ""
        for op in ops {
            switch op {
            case .move(let p): d += "M\(fmt(p.x)) \(fmt(p.y))"
            case .line(let p): d += "L\(fmt(p.x)) \(fmt(p.y))"
            case .curve(let c1, let c2, let p):
                d += "C\(fmt(c1.x)) \(fmt(c1.y)) \(fmt(c2.x)) \(fmt(c2.y)) \(fmt(p.x)) \(fmt(p.y))"
            case .close: d += "Z"
            }
        }
        return d
    }
    private func stopsXML(_ stops: [Stop]) -> String {
        stops.map {
            "<stop offset=\"\(fmt($0.at))\" stop-color=\"\(colorAttr($0.color))\" stop-opacity=\"\(fmt($0.color.a))\"/>"
        }.joined()
    }
    private func paintRef(_ paint: Paint) -> (fill: String, opacity: String) {
        switch paint {
        case .solid(let ink):
            return (colorAttr(ink), fmt(ink.a))
        case .linear(let stops, let from, let to):
            gradientCount += 1
            let id = "g\(gradientCount)"
            defs += "<linearGradient id=\"\(id)\" gradientUnits=\"userSpaceOnUse\" x1=\"\(fmt(from.x))\" y1=\"\(fmt(from.y))\" x2=\"\(fmt(to.x))\" y2=\"\(fmt(to.y))\">\(stopsXML(stops))</linearGradient>"
            return ("url(#\(id))", "1")
        case .radial(let stops, let center, let rx, let ry):
            gradientCount += 1
            let id = "g\(gradientCount)"
            // Squash the y axis via gradientTransform so rx/ry differ.
            let sy = ry / max(rx, 1e-6)
            let transform = "translate(\(fmt(center.x)) \(fmt(center.y))) scale(1 \(fmt(sy))) translate(\(fmt(-center.x)) \(fmt(-center.y)))"
            defs += "<radialGradient id=\"\(id)\" gradientUnits=\"userSpaceOnUse\" cx=\"\(fmt(center.x))\" cy=\"\(fmt(center.y))\" r=\"\(fmt(rx))\" gradientTransform=\"\(transform)\">\(stopsXML(stops))</radialGradient>"
            return ("url(#\(id))", "1")
        }
    }

    func fill(_ ops: [PathOp], _ paint: Paint) {
        let ref = paintRef(paint)
        body += "<path d=\"\(pathData(ops))\" fill=\"\(ref.fill)\" fill-opacity=\"\(ref.opacity)\"/>\n"
    }
    func stroke(_ ops: [PathOp], _ color: Ink, width: Double) {
        body += "<path d=\"\(pathData(ops))\" fill=\"none\" stroke=\"\(colorAttr(color))\" stroke-opacity=\"\(fmt(color.a))\" stroke-width=\"\(fmt(width))\" stroke-linejoin=\"round\" stroke-linecap=\"round\"/>\n"
    }
    func pushRotation(degrees: Double, about: Pt) {
        body += "<g transform=\"rotate(\(fmt(degrees)) \(fmt(about.x)) \(fmt(about.y)))\">\n"
        openGroups += 1
    }
    func pushTranslation(dx: Double, dy: Double) {
        body += "<g transform=\"translate(\(fmt(dx)) \(fmt(dy)))\">\n"
        openGroups += 1
    }
    func pop() {
        body += "</g>\n"
        openGroups -= 1
    }
    func dither(count: Int, maxAlpha: Double) {
        // SVG renderers rasterize gradients in float — no dither needed.
    }

    func svgDocument() -> String {
        precondition(openGroups == 0, "unbalanced canvas groups")
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(size)\" height=\"\(size)\" viewBox=\"0 0 \(size) \(size)\"><defs>\(defs)</defs>\n\(body)</svg>\n"
    }
}

extension Double {
    var clamped01: Double { Swift.min(1, Swift.max(0, self)) }
}

// MARK: CoreGraphics backend (macOS / CI — writes the shipping PNG)

#if canImport(CoreGraphics)
final class CGCanvas: IconCanvas {
    let ctx: CGContext
    let cs: CGColorSpace

    init(ctx: CGContext, colorSpace: CGColorSpace) {
        self.ctx = ctx
        self.cs = colorSpace
        // Flip once: all shared geometry is y-down (SVG-style, top-left
        // origin) — after this transform user space == image pixel space.
        ctx.translateBy(x: 0, y: CGFloat(size))
        ctx.scaleBy(x: 1, y: -1)
    }

    private func cgColor(_ ink: Ink) -> CGColor {
        CGColor(colorSpace: cs, components: [CGFloat(ink.r.clamped01), CGFloat(ink.g.clamped01),
                                             CGFloat(ink.b.clamped01), CGFloat(ink.a.clamped01)])!
    }
    private func cgPath(_ ops: [PathOp]) -> CGPath {
        let p = CGMutablePath()
        for op in ops {
            switch op {
            case .move(let pt): p.move(to: CGPoint(x: pt.x, y: pt.y))
            case .line(let pt): p.addLine(to: CGPoint(x: pt.x, y: pt.y))
            case .curve(let c1, let c2, let pt):
                p.addCurve(to: CGPoint(x: pt.x, y: pt.y),
                           control1: CGPoint(x: c1.x, y: c1.y),
                           control2: CGPoint(x: c2.x, y: c2.y))
            case .close: p.closeSubpath()
            }
        }
        return p
    }
    private func gradient(_ stops: [Stop]) -> CGGradient {
        CGGradient(colorsSpace: cs,
                   colors: stops.map { cgColor($0.color) } as CFArray,
                   locations: stops.map { CGFloat($0.at) })!
    }

    func fill(_ ops: [PathOp], _ paint: Paint) {
        switch paint {
        case .solid(let ink):
            ctx.setFillColor(cgColor(ink))
            ctx.addPath(cgPath(ops))
            ctx.fillPath()
        case .linear(let stops, let from, let to):
            ctx.saveGState()
            ctx.addPath(cgPath(ops))
            ctx.clip()
            ctx.drawLinearGradient(gradient(stops),
                                   start: CGPoint(x: from.x, y: from.y),
                                   end: CGPoint(x: to.x, y: to.y),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            ctx.restoreGState()
        case .radial(let stops, let center, let rx, let ry):
            ctx.saveGState()
            ctx.addPath(cgPath(ops))
            ctx.clip()
            // Squash y so rx/ry can differ (mirrors the SVG gradientTransform).
            let sy = ry / max(rx, 1e-6)
            ctx.translateBy(x: CGFloat(center.x), y: CGFloat(center.y))
            ctx.scaleBy(x: 1, y: CGFloat(sy))
            ctx.drawRadialGradient(gradient(stops),
                                   startCenter: .zero, startRadius: 0,
                                   endCenter: .zero, endRadius: CGFloat(rx),
                                   options: [.drawsAfterEndLocation])
            ctx.restoreGState()
        }
    }
    func stroke(_ ops: [PathOp], _ color: Ink, width: Double) {
        ctx.saveGState()
        ctx.setStrokeColor(cgColor(color))
        ctx.setLineWidth(CGFloat(width))
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.addPath(cgPath(ops))
        ctx.strokePath()
        ctx.restoreGState()
    }
    func pushRotation(degrees: Double, about: Pt) {
        ctx.saveGState()
        ctx.translateBy(x: CGFloat(about.x), y: CGFloat(about.y))
        ctx.rotate(by: CGFloat(degrees * .pi / 180))
        ctx.translateBy(x: CGFloat(-about.x), y: CGFloat(-about.y))
    }
    func pushTranslation(dx: Double, dy: Double) {
        ctx.saveGState()
        ctx.translateBy(x: CGFloat(dx), y: CGFloat(dy))
    }
    func pop() {
        ctx.restoreGState()
    }
    func dither(count: Int, maxAlpha: Double) {
        // Blue-ish noise dots break gradient banding in the 8-bit output.
        for _ in 0..<count {
            let x = rnd() * canvasD, y = rnd() * canvasD
            let bright = rnd() > 0.5
            let a = rnd() * maxAlpha
            ctx.setFillColor(cgColor(bright ? Ink(1, 1, 1, a) : Ink(0, 0, 0, a)))
            ctx.fill(CGRect(x: x, y: y, width: 1.5, height: 1.5))
        }
    }
}
#endif

// MARK: Main — pick a backend from the output extension

if outURL.pathExtension.lowercased() == "svg" {
    let canvas = SVGCanvas()
    drawIcon(on: canvas)
    try! canvas.svgDocument().data(using: .utf8)!.write(to: outURL)
    print("icon (svg) written to \(outURL.path)")
} else {
    #if canImport(CoreGraphics)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let canvas = CGCanvas(ctx: ctx, colorSpace: cs)
    drawIcon(on: canvas)
    let img = ctx.makeImage()!
    guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        FileHandle.standardError.write("cannot create png destination\n".data(using: .utf8)!)
        exit(1)
    }
    CGImageDestinationAddImage(dest, img, nil)
    guard CGImageDestinationFinalize(dest) else {
        FileHandle.standardError.write("png finalize failed\n".data(using: .utf8)!)
        exit(1)
    }
    print("icon written to \(outURL.path)")
    #else
    FileHandle.standardError.write("PNG output needs CoreGraphics (macOS). On this platform render an .svg instead.\n".data(using: .utf8)!)
    exit(1)
    #endif
}
