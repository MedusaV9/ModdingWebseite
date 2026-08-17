import Foundation

struct RGBColor: Codable, Hashable {
    let red: Double
    let green: Double
    let blue: Double

    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, value.allSatisfy(\.isHexDigit),
              let raw = Int(value, radix: 16) else { return nil }
        red = Double((raw >> 16) & 255) / 255
        green = Double((raw >> 8) & 255) / 255
        blue = Double(raw & 255) / 255
    }

    var hex: String {
        String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    func mixed(with other: RGBColor, amount: Double = 0.5) -> RGBColor {
        let t = min(1, max(0, amount))
        return RGBColor(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t
        )
    }

    private init(red: Double, green: Double, blue: Double) {
        self.red = min(1, max(0, red))
        self.green = min(1, max(0, green))
        self.blue = min(1, max(0, blue))
    }

    /// Internal (not fileprivate): PaperRules derives the Lichtkante from
    /// the paper luminance, and the Logic tests pin the grain/edge caps
    /// against the same math the verdicts use.
    var luminance: Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }
}

struct CouplePalette: Codable, Hashable {
    let primary: String
    let secondary: String
    let accent: String
    let onAccent: String
}

/// Verdict of the gradient-foreground rule (FXD-2 #1): the ink to use,
/// plus whether the surface must lay the night-ink text-protection scrim
/// UNDER the label first. When `needsScrim` is true, `hex` is judged
/// against the SCRIMMED stops — painting the ink without the scrim is a
/// contract violation.
struct GradientForeground: Hashable {
    let hex: String
    /// True when NO single ink clears 4.5:1 on both raw stops (a dark and
    /// a light stop pin the foreground from both sides — e.g. the eval's
    /// #7C3AED/#6EE7B7, where the best ink managed only ≈3.68:1).
    let needsScrim: Bool
    /// Lightest scrim rung that lets `hex` clear the floor on both
    /// scrimmed stops; 0 while `needsScrim` is false.
    let scrimOpacity: Double
}

enum CouplePaletteRules {
    static let minimumContrast = 4.5
    /// The NIGHT anchor of the double-anchor contrast law (Papier & Licht,
    /// STYLE_DECISION §3.1/§4): the room's sepia umbra `Papier.zimmerOben`
    /// replaced the violet `#17062A` — every accent-on-night verdict is
    /// computed against this hex, never guessed. The hex lives in
    /// PaperRules with the rest of the Papier & Licht law table so the
    /// Logic tests pin anchor and verdicts against the same constant.
    static var darkBackgroundHex: String { PaperRules.zimmerObenHex }
    private static let darkBackground = RGBColor(hex: PaperRules.zimmerObenHex)!
    /// The PAPER anchor of the double-anchor law: `Papier.brief` — couple
    /// inks on paper run through `inkOnPaper` against the paper tones.
    static var paperBackgroundHex: String { PaperRules.briefHex }
    private static let white = RGBColor(hex: "#FFFFFF")!
    private static let black = RGBColor(hex: "#09040D")!

    /// The two fixed stops of the STATIC brand hero gradient — "goldene
    /// Tinte" (Siegellack brand): lamp gold → copper from the Papier &
    /// Licht law table. The pink→purple stops of the generic era are
    /// history (device eval: the first-launch finale still wore them).
    /// They live HERE — not in Theme.swift — so the Logic target can
    /// prove the `Theme.onHero` verdict against the exact rendered stops:
    /// Theme.heroGradient consumes these constants, the gradient and its
    /// contrast math can never drift apart. (White caps at 1.6:1 on the
    /// gold stop — the verdict lands on the night ink, 5.4:1 worst-stop.)
    static var heroGradientFirstHex: String { PaperRules.lampengoldHex }
    static var heroGradientSecondHex: String { PaperRules.kupferHex }

    static func contrastRatio(_ first: String, _ second: String) -> Double? {
        guard let a = RGBColor(hex: first), let b = RGBColor(hex: second) else { return nil }
        let light = max(a.luminance, b.luminance)
        let dark = min(a.luminance, b.luminance)
        return (light + 0.05) / (dark + 0.05)
    }

    static func acceptsAccent(_ hex: String) -> Bool {
        (contrastRatio(hex, darkBackground.hex) ?? 0) >= minimumContrast
    }

    /// Readable text/icon color ON a single couple-color fill: white keeps
    /// the brand look whenever it truly clears the WCAG floor; light fills
    /// (mint, gold, sky) get the dark ink instead of hard white
    /// (EVAL A11y: white on mint 1.52:1, gold 1.44:1, blue 2.54:1).
    static func readableForeground(on hex: String) -> String {
        gradientForeground(first: hex, second: hex)
    }

    /// Readable foreground across BOTH stops of a two-stop gradient platter
    /// (hero platters, send capsules, own chat bubbles — the Siegellack
    /// `PrimaryButtonStyle` pours pinned wax instead and no longer consumes
    /// this verdict): judged by the WORST stop, because a label crosses the
    /// whole platter.
    ///
    /// Contract (re-eval round 2 — the old white-or-ink pick returned
    /// 3.56:1 for #7C3AED/#6EE7B7 and called it done):
    ///   1. White keeps the brand look when it truly clears
    ///      `minimumContrast` on both stops.
    ///   2. Otherwise the night ink, when IT clears both stops.
    ///   3. Otherwise the TONAL fallback: walk the ink's darker variants
    ///      down to pure black (the lightest variant — pure white — is
    ///      already candidate 1) and return the first that clears the
    ///      floor on both stops.
    ///   4. When no single color can clear 4.5:1 on both stops (a dark and
    ///      a light stop pin the foreground from both sides — for the
    ///      repro pair no luminance satisfies both inequalities), return
    ///      the candidate with the LARGEST worst-stop contrast. The tonal
    ///      extremes are the mathematical optimum of that min-max: between
    ///      the stops the worst-stop ratio only gets worse, outside them
    ///      it grows monotonically toward pure black/white.
    ///
    /// SCRIM-INCAPABLE callers only (final eval round 3): surfaces that CAN
    /// paint a layer under their label must use `gradientForegroundVerdict`
    /// instead, whose scrim path clears the 4.5:1 floor even for the pairs
    /// where this best-single-ink fallback stalls at ≈3.68:1.
    static func gradientForeground(first: String, second: String) -> String {
        func worstStop(_ candidate: RGBColor) -> Double {
            min(contrastRatio(first, candidate.hex) ?? 0,
                contrastRatio(second, candidate.hex) ?? 0)
        }
        let candidates = foregroundCandidates
        if let passing = candidates.first(where: { worstStop($0) >= minimumContrast }) {
            return passing.hex
        }
        let best = candidates.max { worstStop($0) < worstStop($1) } ?? black
        return best.hex
    }

    // MARK: Gradient foreground with scrim verdict (FXD-2 #1)

    /// The text-protection scrim ink: the existing night ink — never a new
    /// raw color. Surfaces paint it at the verdict's `scrimOpacity` UNDER
    /// the label (source-over on the gradient platter).
    static var scrimHex: String { black.hex }

    /// Scrim rungs, lightest first — the verdict picks the first rung whose
    /// composited stops admit a passing ink. The 0.6 rung is the safety
    /// net: even a pure-white stop composites down to ≈0.14 luminance
    /// there, so white clears 4.5:1 on ANY valid pair at the latest rung.
    static let scrimOpacities: [Double] = [0.35, 0.45, 0.6]

    /// The stop as it reads once the night-ink scrim at `opacity` lies on
    /// top — plain source-over per sRGB channel, exactly what the rendered
    /// overlay does.
    static func scrimmedStop(_ hex: String, opacity: Double) -> String? {
        guard let stop = RGBColor(hex: hex), let ink = RGBColor(hex: scrimHex) else {
            return nil
        }
        return stop.mixed(with: ink, amount: opacity).hex
    }

    /// Contract of the round-3 fix: the floor is 4.5:1 WITHOUT EXCEPTION.
    ///   1.–3. Same brand-ordered ink walk as `gradientForeground` — when
    ///         one ink clears both raw stops, no scrim is needed.
    ///   4. Otherwise the verdict escalates through `scrimOpacities`: the
    ///      lightest night-ink scrim whose composited stops admit a
    ///      passing ink wins, and THAT ink ships with `needsScrim`. The
    ///      old best-effort ≈3.68:1 pick survives only for callers of the
    ///      legacy single-hex API that cannot paint layers.
    static func gradientForegroundVerdict(first: String,
                                          second: String) -> GradientForeground {
        func worstStop(_ candidate: RGBColor, on stops: (String, String)) -> Double {
            min(contrastRatio(stops.0, candidate.hex) ?? 0,
                contrastRatio(stops.1, candidate.hex) ?? 0)
        }
        let candidates = foregroundCandidates
        if let passing = candidates.first(where: {
            worstStop($0, on: (first, second)) >= minimumContrast
        }) {
            return GradientForeground(hex: passing.hex, needsScrim: false,
                                      scrimOpacity: 0)
        }
        for opacity in scrimOpacities {
            guard let a = scrimmedStop(first, opacity: opacity),
                  let b = scrimmedStop(second, opacity: opacity) else { break }
            if let passing = candidates.first(where: {
                worstStop($0, on: (a, b)) >= minimumContrast
            }) {
                return GradientForeground(hex: passing.hex, needsScrim: true,
                                          scrimOpacity: opacity)
            }
        }
        // Only reachable with invalid hex input (the 0.6 rung provably
        // admits white on every valid pair) — fall back like the legacy API.
        return GradientForeground(hex: gradientForeground(first: first, second: second),
                                  needsScrim: false, scrimOpacity: 0)
    }

    /// Brand preference order: white, the night ink, then the ink's tonal
    /// ramp toward pure black — shared by the legacy pick and the verdict.
    private static var foregroundCandidates: [RGBColor] {
        let pureBlack = RGBColor(hex: "#000000")!
        var candidates = [white, black]
        for step in 1...4 {
            candidates.append(black.mixed(with: pureBlack, amount: Double(step) / 4))
        }
        return candidates
    }

    /// Couple ink for couple-tinted labels on a WHITE fill (the own
    /// voice-note play/speed capsules): light member colors fail on white
    /// (Schlussrunde 5 — mint 1.52:1, gold 1.44:1, sky 2.54:1), so the
    /// ladder darkens the color toward the night ink until it clears
    /// `minimumContrast` on #FFFFFF; colors that already pass stay
    /// untouched. Step 12 is the ink itself (20.3:1), so the ladder always
    /// terminates on a passing rung.
    static func accentOnLight(_ hex: String) -> String {
        darkenedUntilReadable(hex, on: [white.hex])
    }

    /// Couple ink on PAPER — the second anchor of the double-anchor law
    /// (Papier & Licht): identical ladder mechanics to `accentOnLight`,
    /// anchored against the paper tones instead of white. Judged against
    /// ALL FOUR paper tones (the darkest, `Papier.kante`, binds): one
    /// author keeps ONE ink across brief- and karton-Zettel, edge stripes
    /// and stacked-edge backs — a brief-only anchor would drop every
    /// member color under 4.5:1 on the darker papers (measured: worst
    /// stops 3.55–4.00:1). Use: 4-pt ink edges, signature lines, avatar
    /// rings, `brandTitle` on paper — body copy stays `Tinte.dunkel`.
    static func inkOnPaper(_ hex: String) -> String {
        darkenedUntilReadable(hex, on: PaperRules.paperHexes)
    }

    // MARK: Deep couple wax (nacht-first seal — P1-A)

    /// The couple's blend as DEEP seal wax: the blend darkened toward
    /// the night ink in twelfth steps until the LIGHT embossing ink
    /// (`PaperRules.aufNachtHex`) clears `minimumContrast` on it. Step
    /// 12 is the night ink itself (aufNacht reads 15+:1 there), so the
    /// ladder always terminates. The hue survives — the wax keeps the
    /// couple's color, only deep and saturated instead of the pale
    /// gold-era pour (the Kino freeze proof case: pale seal, black
    /// heart). Invalid input falls back to the red seal wax, on which
    /// aufNacht already clears the floor.
    static func waxDeepened(_ hex: String) -> String {
        let base = RGBColor(hex: hex) ?? RGBColor(hex: PaperRules.wachsRotHex)!
        var color = base
        for step in 1...12 where
            (contrastRatio(PaperRules.aufNachtHex, color.hex) ?? 0) < minimumContrast {
            color = base.mixed(with: black, amount: Double(step) / 12)
        }
        return color.hex
    }

    /// Embossing ink on the DEEP wax seal (`wachsDunkelHex` →
    /// `waxDeepened(blend)`): the warm paper white (`aufNacht`) whenever
    /// it clears BOTH stops — by construction always true for valid
    /// couple blends (waxDeepened guarantees its own stop, the fixed
    /// pour stop is pinned at 8.1:1) — with the single-ink verdict as
    /// the theoretical fallback. Light embossing on dark wax: the
    /// inverse of the retired gold-era dark stamp, same worst-stop law.
    static func waxEmbossInk(first: String, second: String) -> String {
        let aufNacht = PaperRules.aufNachtHex
        let clears = [first, second].allSatisfy {
            (contrastRatio(aufNacht, $0) ?? 0) >= minimumContrast
        }
        return clears ? aufNacht : gradientForeground(first: first, second: second)
    }

    /// The ONE darkening ladder behind `accentOnLight` and `inkOnPaper`:
    /// mixes the base toward the night ink in twelfth steps until the
    /// color clears `minimumContrast` on EVERY anchor. Step 12 is the ink
    /// itself (20.3:1 on white, 14.1:1 on the darkest paper), so the
    /// ladder always terminates on a passing rung.
    private static func darkenedUntilReadable(_ hex: String,
                                              on anchors: [String]) -> String {
        let base = RGBColor(hex: hex) ?? black
        var color = base
        for step in 1...12 where anchors.contains(where: {
            (contrastRatio(color.hex, $0) ?? 0) < minimumContrast
        }) {
            color = base.mixed(with: black, amount: Double(step) / 12)
        }
        return color.hex
    }

    static func derived(first: String, second: String) -> CouplePalette {
        let firstColor = RGBColor(hex: first) ?? RGBColor(hex: "#FF5C8A")!
        let secondColor = RGBColor(hex: second) ?? RGBColor(hex: "#A855F7")!
        var accent = firstColor.mixed(with: secondColor)
        for step in 1...12 where !acceptsAccent(accent.hex) {
            accent = accent.mixed(with: white, amount: Double(step) / 24)
        }
        let whiteContrast = contrastRatio(accent.hex, white.hex) ?? 0
        let blackContrast = contrastRatio(accent.hex, black.hex) ?? 0
        return CouplePalette(
            primary: firstColor.hex,
            secondary: secondColor.hex,
            accent: accent.hex,
            onAccent: whiteContrast >= blackContrast ? white.hex : black.hex
        )
    }

    static let presets: [CouplePalette] = [
        derived(first: "#FF5C8A", second: "#A855F7"),
        derived(first: "#60A5FA", second: "#6EE7B7"),
        derived(first: "#FFD166", second: "#FB923C"),
    ]

    /// The avatar color choices during profile setup — the SINGLE source of
    /// the member palette. `Theme.memberColors` (UI layer) passes this table
    /// through one-to-one, and the Logic tests run their contrast matrices
    /// (derivation ladder, gradient verdicts, inkOnPaper) over the SAME
    /// constant, so palette and proofs can never drift apart. Bare RRGGBB
    /// like the rest of the UI-facing tables; every contrast helper here
    /// accepts both forms.
    static let memberColorHexes: [String] = [
        "FF5C8A", "A855F7", "6366F1", "60A5FA",
        "6EE7B7", "FFD166", "FB923C", "F87171",
    ]
}

enum MonogramStyle: String, Codable, CaseIterable {
    case seal
    case ribbon
    case minimal
}

enum CoupleMonogram {
    static func initials(first: String, second: String) -> String {
        [first, second].compactMap { name in
            name.split(whereSeparator: \.isWhitespace).first?.first.map {
                String($0).uppercased()
            }
        }.joined(separator: "·")
    }

    static func svg(first: String, second: String, palette: CouplePalette,
                    style: MonogramStyle) -> String {
        let letters = initials(first: first, second: second)
        let border = style == .minimal ? "1.5" : "4"
        let dash = style == .ribbon ? #" stroke-dasharray="8 5""# : ""
        return """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 160 160">
          <defs><linearGradient id="g"><stop stop-color="\(palette.primary)"/><stop offset="1" stop-color="\(palette.secondary)"/></linearGradient></defs>
          <circle cx="80" cy="80" r="68" fill="url(#g)" stroke="\(palette.accent)" stroke-width="\(border)"\(dash)/>
          <text x="80" y="91" text-anchor="middle" font-family="serif" font-size="42" font-weight="700" fill="\(palette.onAccent)">\(letters)</text>
        </svg>
        """
    }
}

enum PetNameTemplate {
    static func render(_ template: String, me: String, partner: String) -> String {
        template
            .replacingOccurrences(of: "{me}", with: me)
            .replacingOccurrences(of: "{partner}", with: partner)
    }
}

enum MessageEffectPolicy {
    static let cooldown: TimeInterval = 12

    static func canSend(lastSentAt: Date?, now: Date = Date()) -> Bool {
        guard let lastSentAt else { return true }
        return now.timeIntervalSince(lastSentAt) >= cooldown
    }
}

enum StickerShape: String, Codable, CaseIterable {
    case heart
    case cloud
    case burst
    case seal
}

struct StickerPoint: Codable, Hashable {
    let x: Double
    let y: Double
}

struct StickerRecipe: Codable, Hashable {
    let shape: StickerShape
    let color: String
    let seed: UInt64
    let label: String?
}

enum StickerWorkshop {
    static func recipe(points: [StickerPoint], color: String,
                       label: String?) -> StickerRecipe {
        let normalizedColor = RGBColor(hex: color)?.hex ?? "#FF5C8A"
        let hash = points.reduce(UInt64(14_695_981_039_346_656_037)) { partial, point in
            let x = UInt64(bitPattern: Int64((point.x * 10_000).rounded()))
            let y = UInt64(bitPattern: Int64((point.y * 10_000).rounded()))
            return (partial ^ x ^ (y &* 1099511628211)) &* 1099511628211
        }
        let seed = hash & 0x1F_FFFF_FFFF_FFFF // exact in a JavaScript Number
        let shape = StickerShape.allCases[Int(seed % UInt64(StickerShape.allCases.count))]
        let cleanLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        return StickerRecipe(
            shape: shape,
            color: normalizedColor,
            seed: seed,
            label: cleanLabel?.isEmpty == false ? String(cleanLabel!.prefix(24)) : nil
        )
    }
}

enum SecretSwipe: String, Codable {
    case up, down, left, right
}

struct SecretGestureProgress: Equatable {
    private static let sequence: [SecretSwipe] = [
        .up, .up, .down, .down, .left, .right, .left, .right,
    ]
    private(set) var index = 0

    mutating func consume(_ swipe: SecretSwipe) -> Bool {
        if swipe == Self.sequence[index] {
            index += 1
            if index == Self.sequence.count {
                index = 0
                return true
            }
        } else {
            index = swipe == Self.sequence[0] ? 1 : 0
        }
        return false
    }
}
