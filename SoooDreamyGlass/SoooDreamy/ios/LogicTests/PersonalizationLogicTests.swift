import XCTest
@testable import SoooDreamyLogic

final class PersonalizationLogicTests: XCTestCase {
    func testPaletteDerivationIsDeterministicAndContrastGuarded() {
        let first = CouplePaletteRules.derived(first: "#FF5C8A", second: "#60A5FA")
        let second = CouplePaletteRules.derived(first: "#FF5C8A", second: "#60A5FA")
        XCTAssertEqual(first, second)
        XCTAssertTrue(CouplePaletteRules.acceptsAccent(first.accent))
        // Nacht-first re-anchoring (P1-A): the night anchor is the
        // DARKER sepia room now (#201613 → #1A100B) — the anchor moved
        // twice (violet → sepia → late-night sepia), the 4.5:1
        // guarantee never did.
        XCTAssertEqual(CouplePaletteRules.darkBackgroundHex, "#1A100B")
        XCTAssertGreaterThanOrEqual(
            CouplePaletteRules.contrastRatio(first.accent, "#1A100B") ?? 0,
            4.5
        )
        XCTAssertNil(CouplePaletteRules.contrastRatio("not-a-color", "#FFFFFF"))
    }

    func testEveryDerivedAccentClearsTheNewNightAnchor() {
        // The re-anchored derivation ladder must still deliver a passing
        // blend for EVERY member pairing — the anchor swap may not strand
        // a single couple below the floor.
        for a in memberColors {
            for b in memberColors where a != b {
                let accent = CouplePaletteRules.derived(first: a, second: b).accent
                XCTAssertGreaterThanOrEqual(
                    CouplePaletteRules.contrastRatio(
                        accent, CouplePaletteRules.darkBackgroundHex) ?? 0,
                    CouplePaletteRules.minimumContrast,
                    "blend of \(a)/\(b) must clear 4.5:1 on the sepia night")
            }
        }
    }

    // MARK: Readable foregrounds on couple colors (EVAL A11y contrast)

    func testLightCoupleFillsGetInkInsteadOfHardWhite() {
        // The three eval-critical member colors: white read 1.52:1 (mint),
        // 1.44:1 (gold) and 2.54:1 (sky) — all far below the 4.5:1 floor.
        for hex in ["#6EE7B7", "#FFD166", "#60A5FA"] {
            let fg = CouplePaletteRules.readableForeground(on: hex)
            XCTAssertNotEqual(fg, "#FFFFFF", "white must lose on \(hex)")
            XCTAssertGreaterThanOrEqual(
                CouplePaletteRules.contrastRatio(hex, fg) ?? 0,
                CouplePaletteRules.minimumContrast,
                "ink must clear WCAG on \(hex)"
            )
        }
    }

    func testDarkFillsKeepTheWhiteBrandLook() {
        XCTAssertEqual(CouplePaletteRules.readableForeground(on: "#7C3AED"), "#FFFFFF")
        XCTAssertEqual(CouplePaletteRules.readableForeground(on: "#B91C1C"), "#FFFFFF")
    }

    func testGradientForegroundIsJudgedByTheWorstStop() {
        // White clears both dark stops → the brand look survives.
        XCTAssertEqual(
            CouplePaletteRules.gradientForeground(first: "#7C3AED", second: "#B91C1C"),
            "#FFFFFF"
        )
        // One light stop drags the whole platter: a label crosses BOTH
        // stops, so the mint end forces the ink even next to dark violet.
        XCTAssertNotEqual(
            CouplePaletteRules.gradientForeground(first: "#7C3AED", second: "#6EE7B7"),
            "#FFFFFF"
        )
    }

    // MARK: gradientForeground contract matrix (re-eval round 2)

    /// Worst-stop contrast of a foreground across both gradient stops.
    private func worstStop(_ fg: String, _ a: String, _ b: String) -> Double {
        min(CouplePaletteRules.contrastRatio(a, fg) ?? 0,
            CouplePaletteRules.contrastRatio(b, fg) ?? 0)
    }

    /// The effective stops a verdict foreground is rendered against: the
    /// raw stops, or — in the scrim case — the stops with the night-ink
    /// scrim composited on top (exactly what the surface paints).
    private func effectiveStops(_ verdict: GradientForeground,
                                _ a: String, _ b: String) -> (String, String) {
        guard verdict.needsScrim else { return (a, b) }
        return (CouplePaletteRules.scrimmedStop(a, opacity: verdict.scrimOpacity) ?? a,
                CouplePaletteRules.scrimmedStop(b, opacity: verdict.scrimOpacity) ?? b)
    }

    func testGradientForegroundContractAcrossAColorMatrix() {
        // Every member-color pairing plus the eval repro pair. Round-3
        // contract: the 4.5:1 floor holds WITHOUT EXCEPTION. Pairs that a
        // single ink can serve stay scrim-free (the brand look survives);
        // pairs no ink can serve become scrim cases, and the verdict ink
        // must clear the floor on the SCRIMMED stops it is rendered over.
        var pairs: [(String, String)] = [("#7C3AED", "#6EE7B7")]
        for a in memberColors {
            for b in memberColors where a != b {
                pairs.append((a, b))
            }
        }
        for (a, b) in pairs {
            let verdict = CouplePaletteRules.gradientForegroundVerdict(first: a,
                                                                       second: b)
            let stops = effectiveStops(verdict, a, b)
            XCTAssertGreaterThanOrEqual(
                worstStop(verdict.hex, stops.0, stops.1),
                CouplePaletteRules.minimumContrast,
                "4.5:1 without exception on \(a)/\(b) — scrim=\(verdict.needsScrim)")
            let bestPossible = max(worstStop("#FFFFFF", a, b),
                                   worstStop("#000000", a, b))
            if bestPossible >= CouplePaletteRules.minimumContrast {
                XCTAssertFalse(verdict.needsScrim,
                               "\(a)/\(b) passes ink-only — no scrim allowed")
                XCTAssertEqual(verdict.hex,
                               CouplePaletteRules.gradientForeground(first: a, second: b),
                               "ink-only verdicts must match the legacy pick")
            } else {
                XCTAssertTrue(verdict.needsScrim,
                              "no ink clears \(a)/\(b) — the verdict must demand the scrim")
            }
        }
    }

    func testEveryMemberColorPairingPassesWithoutAScrim() {
        // The reachable palettes are member-color pairs — they must never
        // need the scrim, or the brand platter would dim for real couples.
        for a in memberColors {
            for b in memberColors where a != b {
                XCTAssertFalse(
                    CouplePaletteRules.gradientForegroundVerdict(first: a, second: b)
                        .needsScrim,
                    "member pair \(a)/\(b) must stay scrim-free")
            }
        }
    }

    func testGradientForegroundReproPairBecomesTheScrimCase() {
        // #7C3AED/#6EE7B7: no single ink reaches 4.5:1 on both raw stops
        // (the violet stop needs ≥0.78 luminance, the mint stop ≤0.10; the
        // best ink stalled at ≈3.68:1). Round 3: the verdict demands the
        // night-ink scrim at the LIGHTEST rung that works, and the ink
        // clears the floor on the scrimmed stops.
        let verdict = CouplePaletteRules.gradientForegroundVerdict(
            first: "#7C3AED", second: "#6EE7B7")
        XCTAssertTrue(verdict.needsScrim)
        XCTAssertTrue(CouplePaletteRules.scrimOpacities.contains(verdict.scrimOpacity))
        let stops = effectiveStops(verdict, "#7C3AED", "#6EE7B7")
        XCTAssertGreaterThanOrEqual(
            worstStop(verdict.hex, stops.0, stops.1),
            CouplePaletteRules.minimumContrast,
            "the scrim case must clear the full 4.5:1 floor")
        // Lightest-rung property: one rung below (when one exists) must
        // genuinely be insufficient for every candidate — the scrim stays
        // as quiet as the math allows.
        if let index = CouplePaletteRules.scrimOpacities.firstIndex(of: verdict.scrimOpacity),
           index > 0 {
            let lighter = CouplePaletteRules.scrimOpacities[index - 1]
            let a = CouplePaletteRules.scrimmedStop("#7C3AED", opacity: lighter)!
            let b = CouplePaletteRules.scrimmedStop("#6EE7B7", opacity: lighter)!
            let bestLighter = max(worstStop("#FFFFFF", a, b), worstStop("#000000", a, b))
            XCTAssertLessThan(bestLighter, CouplePaletteRules.minimumContrast,
                              "a lighter rung would have sufficed — pick it instead")
        }
        // Scrim-incapable callers keep the legacy best-single-ink behavior.
        let legacy = CouplePaletteRules.gradientForeground(first: "#7C3AED",
                                                           second: "#6EE7B7")
        XCTAssertGreaterThan(worstStop(legacy, "#7C3AED", "#6EE7B7"), 3.6,
                             "legacy pick must not regress below its ≈3.68:1")
    }

    // MARK: Static hero platter — Theme.onHero (Siegellack brand)

    func testStaticHeroGradientVerdictClearsTheFloorOnEffectiveStops() {
        // The STATIC brand gradient is "goldene Tinte" now: lamp gold →
        // copper from the Papier & Licht law table — the pink/purple
        // stops of the generic era are history (device eval: the
        // first-launch finale still wore them). Theme.heroGradient
        // consumes exactly these constants, so this test pins the
        // rendered `Theme.onHero` ink.
        XCTAssertEqual(CouplePaletteRules.heroGradientFirstHex,
                       PaperRules.lampengoldHex)
        XCTAssertEqual(CouplePaletteRules.heroGradientSecondHex,
                       PaperRules.kupferHex)
        let verdict = CouplePaletteRules.gradientForegroundVerdict(
            first: CouplePaletteRules.heroGradientFirstHex,
            second: CouplePaletteRules.heroGradientSecondHex)
        // White must lose here — it caps at 1.6:1 on the gold stop.
        XCTAssertNotEqual(verdict.hex, "#FFFFFF")
        let stops = effectiveStops(verdict,
                                   CouplePaletteRules.heroGradientFirstHex,
                                   CouplePaletteRules.heroGradientSecondHex)
        XCTAssertGreaterThanOrEqual(
            worstStop(verdict.hex, stops.0, stops.1),
            CouplePaletteRules.minimumContrast,
            "Theme.onHero must clear 4.5:1 on the (possibly scrimmed) brand stops")
        // The golden platter stays scrim-free: the night ink serves both
        // stops (12.9:1 on gold, 5.4:1 on copper). Should a future stop
        // change flip this, heroPlatter paints the scrim — but the flip
        // should be a conscious decision.
        XCTAssertFalse(verdict.needsScrim,
                       "gold/copper pass ink-only — no scrim on the brand platter")
    }

    func testPrePairingWordmarkInkIsMachineJudgedOnTheGoldenBlend() {
        // Before pairing the couple tint falls back to the golden ink:
        // blend = lampengold carries the wordmark on night (11.9:1,
        // pinned in PaperRulesTests) and `onBlend` comes from the
        // readableForeground verdict — white must lose on gold, and the
        // chosen ink must clear the floor (the guide's active language
        // chip renders exactly this pairing).
        let ink = CouplePaletteRules.readableForeground(on: PaperRules.lampengoldHex)
        XCTAssertNotEqual(ink, "#FFFFFF", "white caps at 1.6:1 on the gold blend")
        XCTAssertGreaterThanOrEqual(
            CouplePaletteRules.contrastRatio(ink, PaperRules.lampengoldHex) ?? 0,
            CouplePaletteRules.minimumContrast)
    }

    // MARK: accentOnLight ladder — couple ink on WHITE fills (Schlussrunde 5)

    func testLightCoupleColorsDarkenUntilTheyPassOnWhite() {
        // The eval-critical light member colors: as capsule tint on the
        // WHITE voice-note controls they managed only 1.44–2.54:1.
        for hex in ["#6EE7B7", "#FFD166", "#60A5FA"] {
            let ink = CouplePaletteRules.accentOnLight(hex)
            XCTAssertNotEqual(ink, RGBColor(hex: hex)!.hex,
                              "\(hex) is light — the ladder must darken it")
            XCTAssertGreaterThanOrEqual(
                CouplePaletteRules.contrastRatio(ink, "#FFFFFF") ?? 0,
                CouplePaletteRules.minimumContrast,
                "onLight ink must clear WCAG on white for \(hex)")
        }
    }

    func testDarkCoupleColorsPassThroughTheLadderUnchanged() {
        // Dark colors already read on white — no pauschal darkening.
        // (Indigo #6366F1 deliberately NOT here: it sits at 4.47:1, a hair
        // under the floor, and correctly takes exactly one ladder rung.)
        for hex in ["#7C3AED", "#B91C1C", "#09040D"] {
            XCTAssertEqual(CouplePaletteRules.accentOnLight(hex),
                           RGBColor(hex: hex)!.hex,
                           "\(hex) already passes on white — keep it")
        }
    }

    func testEveryMemberColorGetsAPassingInkOnWhite() {
        for hex in memberColors {
            XCTAssertGreaterThanOrEqual(
                CouplePaletteRules.contrastRatio(
                    CouplePaletteRules.accentOnLight(hex), "#FFFFFF") ?? 0,
                CouplePaletteRules.minimumContrast,
                "member color \(hex) must land ≥4.5:1 on white")
        }
        // Invalid input falls back to the night ink (20.3:1 on white).
        XCTAssertGreaterThanOrEqual(
            CouplePaletteRules.contrastRatio(
                CouplePaletteRules.accentOnLight("not-a-color"), "#FFFFFF") ?? 0,
            CouplePaletteRules.minimumContrast)
    }

    func testLegacyChipInkStaysDarkOnGoldAndBlend() {
        // LEGACY (nacht-first P1-A): the gold→blend pairing left the
        // SEAL (which pours wachsDunkel→wachsTief now, see the deep-wax
        // matrix below) but survives as `CoupleTint.onWax` for the flat
        // `wachs`-chip call sites (needs-ack drop, streak both-cell) —
        // clearing gold AND blend keeps the blend chips readable until
        // P2 migrates them. Lamplight gold still caps white far below
        // the floor, so the single-ink rule keeps landing on a DARK ink
        // that clears the floor on both stops — for every member pairing.
        let gold = PaperRules.lampengoldHex
        XCTAssertEqual(gold, "#FFC46B")
        for a in memberColors {
            for b in memberColors where a != b {
                let blend = CouplePaletteRules.derived(first: a, second: b).accent
                let ink = CouplePaletteRules.gradientForeground(first: gold,
                                                                second: blend)
                XCTAssertNotEqual(ink, "#FFFFFF",
                                  "white must lose on the gold chip (\(a)/\(b))")
                XCTAssertGreaterThanOrEqual(
                    worstStop(ink, gold, blend),
                    CouplePaletteRules.minimumContrast,
                    "chip ink must clear 4.5:1 on gold AND blend (\(a)/\(b))")
            }
        }
    }

    // MARK: Deep couple wax — the nacht-first seal (P1-A)

    func testDeepWaxSealEmbossesLightForEveryDerivedBlend() {
        // The Kino freeze proof case reversed: the seal pours
        // wachsDunkel → waxDeepened(blend) now, and the embossing is
        // LIGHT (aufNacht) — judged against BOTH deep stops, for every
        // member pairing (the same worst-stop law the gold era used).
        let pour = PaperRules.wachsDunkelHex
        for a in memberColors {
            for b in memberColors where a != b {
                let blend = CouplePaletteRules.derived(first: a, second: b).accent
                let deep = CouplePaletteRules.waxDeepened(blend)
                XCTAssertEqual(deep, CouplePaletteRules.waxDeepened(blend),
                               "deep wax is deterministic (\(a)/\(b))")
                // The ladder darkens, never lightens — the wax stays
                // saturated couple color, only deeper.
                XCTAssertLessThanOrEqual(RGBColor(hex: deep)!.luminance,
                                         RGBColor(hex: blend)!.luminance,
                                         "waxDeepened must not lighten (\(a)/\(b))")
                let ink = CouplePaletteRules.waxEmbossInk(first: pour, second: deep)
                XCTAssertEqual(ink, PaperRules.aufNachtHex,
                               "the nacht-first seal embosses LIGHT (\(a)/\(b))")
                XCTAssertGreaterThanOrEqual(
                    worstStop(ink, pour, deep),
                    CouplePaletteRules.minimumContrast,
                    "embossing must clear 4.5:1 on BOTH deep-wax stops (\(a)/\(b))")
            }
        }
    }

    func testDeepWaxLadderSurvivesInvalidInput() {
        // Invalid input falls back to the red seal wax, on which the
        // light embossing already clears the floor.
        let deep = CouplePaletteRules.waxDeepened("not-a-color")
        XCTAssertGreaterThanOrEqual(
            CouplePaletteRules.contrastRatio(PaperRules.aufNachtHex, deep) ?? 0,
            CouplePaletteRules.minimumContrast)
        // Already-deep input passes through unchanged — no pauschal
        // darkening (the night ink is its own deepest rung).
        XCTAssertEqual(CouplePaletteRules.waxDeepened("#09040D"), "#09040D")
    }

    // MARK: inkOnPaper ladder — the PAPER anchor (Papier & Licht)

    func testInkOnPaperCoversEveryMemberColorOnEveryPaperTone() {
        // The second anchor of the double-anchor law: one ink per member
        // color, readable on ALL FOUR paper tones (chat mixes brief and
        // karton Zettel; the darkest paper, kante, binds the ladder).
        for hex in memberColors {
            let ink = CouplePaletteRules.inkOnPaper(hex)
            for paper in PaperRules.paperHexes {
                XCTAssertGreaterThanOrEqual(
                    CouplePaletteRules.contrastRatio(ink, paper) ?? 0,
                    CouplePaletteRules.minimumContrast,
                    "ink of \(hex) must clear 4.5:1 on paper \(paper)")
            }
        }
    }

    func testInkOnPaperDarkensLightMemberColors() {
        // The eval-critical light member colors (mint, gold, sky) sit at
        // 1.4–2.5:1 on brief — the ladder must darken them into real ink.
        for hex in ["#6EE7B7", "#FFD166", "#60A5FA"] {
            XCTAssertNotEqual(CouplePaletteRules.inkOnPaper(hex),
                              RGBColor(hex: hex)!.hex,
                              "\(hex) is light — the ladder must darken it")
        }
    }

    func testInkOnPaperKeepsAlreadyDarkInksUntouched() {
        // The night ink already clears every paper tone (≥14:1 on the
        // darkest) — no pauschal darkening.
        XCTAssertEqual(CouplePaletteRules.inkOnPaper("#09040D"), "#09040D")
    }

    func testInkOnPaperIsDeterministicAndSurvivesInvalidInput() {
        XCTAssertEqual(CouplePaletteRules.inkOnPaper("#FF5C8A"),
                       CouplePaletteRules.inkOnPaper("FF5C8A"))
        // Invalid input falls back to the night ink — readable everywhere.
        for paper in PaperRules.paperHexes {
            XCTAssertGreaterThanOrEqual(
                CouplePaletteRules.contrastRatio(
                    CouplePaletteRules.inkOnPaper("not-a-color"), paper) ?? 0,
                CouplePaletteRules.minimumContrast)
        }
    }

    func testScrimSafetyNetCoversTheExtremeWhiteBlackPair() {
        // The hardest possible pair: a pure-white and a pure-black stop pin
        // every ink from both sides. The last scrim rung must still deliver
        // the full floor — the "without exception" in the contract.
        let verdict = CouplePaletteRules.gradientForegroundVerdict(
            first: "#FFFFFF", second: "#000000")
        XCTAssertTrue(verdict.needsScrim)
        let stops = effectiveStops(verdict, "#FFFFFF", "#000000")
        XCTAssertGreaterThanOrEqual(
            worstStop(verdict.hex, stops.0, stops.1),
            CouplePaletteRules.minimumContrast)
    }

    /// The avatar palette — the Foundation single source that
    /// `Theme.memberColors` passes through (no more duplicated hex table
    /// in this file: the matrices below run over exactly what renders).
    private let memberColors = CouplePaletteRules.memberColorHexes

    func testMemberColorTableIsTheExpectedPalette() {
        // Eight valid RRGGBB entries, no duplicates — the profile-setup
        // palette. A silent edit here re-runs every matrix in this file
        // against the changed table.
        XCTAssertEqual(memberColors.count, 8)
        XCTAssertEqual(Set(memberColors).count, memberColors.count)
        for hex in memberColors {
            XCTAssertNotNil(RGBColor(hex: hex), "\(hex) must be a valid RRGGBB")
        }
        XCTAssertEqual(memberColors.first, "FF5C8A",
                       "the first entry is the profile-setup default")
    }

    func testStickerLabelInkClearsTheFloorOnEveryMemberColor() {
        // ProceduralStickerView paints its label with
        // `readableForeground(on:)` instead of hard white (A11y S2): the
        // verdict must clear 4.5:1 on EVERY pickable sticker color.
        for hex in memberColors {
            let ink = CouplePaletteRules.readableForeground(on: hex)
            XCTAssertGreaterThanOrEqual(
                CouplePaletteRules.contrastRatio(ink, hex) ?? 0,
                CouplePaletteRules.minimumContrast,
                "sticker label ink must clear 4.5:1 on \(hex)")
        }
    }

    func testMonogramSVGAndPetNameTemplatesAreStable() {
        let palette = CouplePaletteRules.derived(first: "#6EE7B7", second: "#A855F7")
        XCTAssertEqual(CoupleMonogram.initials(first: "Mia", second: "Ben Bear"), "M·B")
        let svg = CoupleMonogram.svg(
            first: "Mia", second: "Ben", palette: palette, style: .ribbon
        )
        XCTAssertTrue(svg.contains("M·B"))
        XCTAssertTrue(svg.contains(#"stroke-dasharray="8 5""#))
        XCTAssertEqual(
            PetNameTemplate.render("Guten Morgen, {partner} — {me} denkt an dich.",
                                   me: "Fuchs", partner: "Bär"),
            "Guten Morgen, Bär — Fuchs denkt an dich."
        )
    }

    func testStickerRecipeUsesOnlyProceduralData() {
        let points = [
            StickerPoint(x: 0.1, y: 0.2),
            StickerPoint(x: 0.8, y: 0.7),
        ]
        let first = StickerWorkshop.recipe(points: points, color: "60A5FA", label: "  Für dich  ")
        let second = StickerWorkshop.recipe(points: points, color: "#60A5FA", label: "Für dich")
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.label, "Für dich")
        XCTAssertTrue(StickerShape.allCases.contains(first.shape))
    }

    func testSecretSwipeOnlyUnlocksAfterCompleteSequence() {
        var progress = SecretGestureProgress()
        let sequence: [SecretSwipe] = [
            .up, .up, .down, .down, .left, .right, .left, .right,
        ]
        for swipe in sequence.dropLast() {
            XCTAssertFalse(progress.consume(swipe))
        }
        XCTAssertTrue(progress.consume(sequence.last!))
        XCTAssertEqual(progress.index, 0)
        XCTAssertFalse(progress.consume(.left))
    }

    func testMessageEffectsHaveAQuietCooldown() {
        let now = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(MessageEffectPolicy.canSend(lastSentAt: nil, now: now))
        XCTAssertFalse(MessageEffectPolicy.canSend(
            lastSentAt: now.addingTimeInterval(-11.9), now: now
        ))
        XCTAssertTrue(MessageEffectPolicy.canSend(
            lastSentAt: now.addingTimeInterval(-12), now: now
        ))
    }
}
