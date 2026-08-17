import XCTest
@testable import SoooDreamyLogic

/// Pins the "Papier & Licht" law table (PaperRules) — the same pin
/// discipline as the PersonalizationLogic matrix: every hex the Art
/// Direction v2 fixes, both contrast anchors, the grain cap and the
/// seeded paper physics. A silent value drift breaks the build.
final class PaperRulesTests: XCTestCase {
    private func contrast(_ a: String, _ b: String) -> Double {
        CouplePaletteRules.contrastRatio(a, b) ?? 0
    }

    // MARK: The law table itself — exact hexes from STYLE_DECISION §3.1

    func testPaperLichtHexTableIsPinned() {
        // Nacht-first (P1-A): the room went one step darker (#201613 →
        // #1A100B / #33241B → #2A1B12) — late night, not golden hour.
        XCTAssertEqual(PaperRules.zimmerObenHex, "#1A100B")
        XCTAssertEqual(PaperRules.zimmerUntenHex, "#2A1B12")
        XCTAssertEqual(PaperRules.lichtkegelHex, "#4A3320")
        XCTAssertEqual(PaperRules.briefHex, "#F7F1E4")
        XCTAssertEqual(PaperRules.kartonHex, "#EFE6D2")
        XCTAssertEqual(PaperRules.kanteHex, "#E3D6BC")
        XCTAssertEqual(PaperRules.polaroidHex, "#FAF6EC")
        // The standard content card of the nacht-first direction — the
        // room's retired bottom tone, one step lighter than the room.
        XCTAssertEqual(PaperRules.nachtkartonHex, "#33241C")
        XCTAssertEqual(PaperRules.tinteDunkelHex, "#2E2318")
        XCTAssertEqual(PaperRules.tinteSekundaerHex, "#5A4A38")
        XCTAssertEqual(PaperRules.tinteTertiaerHex, "#6E5C46")
        XCTAssertEqual(PaperRules.lampengoldHex, "#FFC46B")
        XCTAssertEqual(PaperRules.glutHex, "#E8845E")
        XCTAssertEqual(PaperRules.kupferHex, "#B87333")
        XCTAssertEqual(PaperRules.wachsRotHex, "#B33A3A")
        XCTAssertEqual(PaperRules.wachsDunkelHex, "#7E2429")
        XCTAssertEqual(PaperRules.aufNachtHex, "#F3EAD9")
        XCTAssertEqual(PaperRules.energyRedHex, "#F87171")
        // Both anchors of the double-anchor law point INTO this table.
        XCTAssertEqual(CouplePaletteRules.darkBackgroundHex, PaperRules.zimmerObenHex)
        XCTAssertEqual(CouplePaletteRules.paperBackgroundHex, PaperRules.briefHex)
    }

    // MARK: Ink × paper matrix (3 inks × 4 papers)

    func testInksClearTheFloorOnEveryTextPaper() {
        // dunkel and sekundaer clear the floor on ALL four papers; the
        // tertiary ink clears it on every TEXT paper (brief/karton/
        // polaroid) — kante is edge material, see the pin below.
        for ink in [PaperRules.tinteDunkelHex, PaperRules.tinteSekundaerHex] {
            for paper in PaperRules.paperHexes {
                XCTAssertGreaterThanOrEqual(
                    contrast(ink, paper), CouplePaletteRules.minimumContrast,
                    "\(ink) must clear 4.5:1 on \(paper)")
            }
        }
        for paper in PaperRules.textPaperHexes {
            XCTAssertGreaterThanOrEqual(
                contrast(PaperRules.tinteTertiaerHex, paper),
                CouplePaletteRules.minimumContrast,
                "tertiaer must clear 4.5:1 on text paper \(paper)")
        }
    }

    func testKanteIsEdgeMaterialNotATextGround() {
        // Tinte.tertiaer on Papier.kante measures 4.45:1 — BELOW the
        // floor, deliberately pinned: the stacked-edge tone never carries
        // copy (dividers, card backs only). If this pin ever passes,
        // someone lightened kante — re-read the material law first.
        XCTAssertLessThan(contrast(PaperRules.tinteTertiaerHex, PaperRules.kanteHex),
                          CouplePaletteRules.minimumContrast)
    }

    func testInkContrastMatchesTheDecisionFigures() {
        // The headline figures of the decision document (§3.1), pinned
        // with margin: 13.6:1 / 7.6:1 / 5.7:1 on brief.
        XCTAssertGreaterThanOrEqual(contrast(PaperRules.tinteDunkelHex, PaperRules.briefHex), 13.0)
        XCTAssertGreaterThanOrEqual(contrast(PaperRules.tinteSekundaerHex, PaperRules.briefHex), 7.0)
        XCTAssertGreaterThanOrEqual(contrast(PaperRules.tinteTertiaerHex, PaperRules.briefHex), 5.5)
    }

    // MARK: Stempeltinte — the stamp-line composite (re-eval №3)

    func testStempelTinteIsTheOpaqueSecondaryInkOnBrief() {
        // A named COMPOSITE, never an opacity: the old
        // `Tinte.sekundaer.opacity(0.7)` composited to ~3.6:1 on brief —
        // below the 4.5 text floor. The stamp prints the PURE secondary
        // ink; both the family membership and the floor are pinned so
        // neither the name nor the figure can drift back to an alpha.
        XCTAssertEqual(PaperRules.stempelTinteHex, PaperRules.tinteSekundaerHex)
        XCTAssertGreaterThanOrEqual(
            contrast(PaperRules.stempelTinteHex, PaperRules.briefHex),
            CouplePaletteRules.minimumContrast)
        // The decision figure with margin (7.5:1 on brief).
        XCTAssertGreaterThanOrEqual(
            contrast(PaperRules.stempelTinteHex, PaperRules.briefHex), 7.0)
    }

    // MARK: Lamplight × night (the re-anchored accent verdicts)

    func testLamplightAccentsClearTheFloorOnTheNewNight() {
        let night = PaperRules.zimmerObenHex
        XCTAssertGreaterThanOrEqual(contrast(PaperRules.lampengoldHex, night), 11.0)
        XCTAssertGreaterThanOrEqual(contrast(PaperRules.glutHex, night), 6.5)
        XCTAssertGreaterThanOrEqual(contrast(PaperRules.aufNachtHex, night), 14.5)
        // energyRed keeps its hex but is re-pinned against the sepia room.
        XCTAssertGreaterThanOrEqual(contrast(PaperRules.energyRedHex, night),
                                    CouplePaletteRules.minimumContrast)
    }

    func testLampengoldIsForbiddenAsTextOnPaper() {
        // 1.4:1 — lamp gold is a glow behind paper edges, never ink.
        XCTAssertLessThan(contrast(PaperRules.lampengoldHex, PaperRules.briefHex), 2.0)
    }

    func testKupferIsANightAccentAndNeverInkOnPaper() {
        // The copper brand stop obeys the lamplight family law: an
        // accent on the room (4.9:1, pinned ≥ 4.5)…
        XCTAssertGreaterThanOrEqual(
            contrast(PaperRules.kupferHex, PaperRules.zimmerObenHex),
            CouplePaletteRules.minimumContrast)
        // …and NEVER text on paper (3.4:1 — same prohibition as the
        // lamp gold, pinned below the floor).
        XCTAssertLessThan(contrast(PaperRules.kupferHex, PaperRules.briefHex),
                          CouplePaletteRules.minimumContrast)
        // The golden ink runs gold → copper: the second stop is the
        // darker one, or the "ink" would brighten toward its tail.
        XCTAssertLessThan(RGBColor(hex: PaperRules.kupferHex)!.luminance,
                          RGBColor(hex: PaperRules.lampengoldHex)!.luminance)
    }

    // MARK: Siegellack — the brand primary button (Papier & Licht brand)

    func testSiegellackNamesPointIntoTheWaxAndPaperLaw() {
        // Semantic names, no new hexes: the seal pours the existing wax
        // and writes in the existing letter paper.
        XCTAssertEqual(PaperRules.siegellackHex, PaperRules.wachsRotHex)
        XCTAssertEqual(PaperRules.siegellackTiefHex, PaperRules.wachsDunkelHex)
        XCTAssertEqual(PaperRules.siegellackTextHex, PaperRules.briefHex)
    }

    func testSiegellackLabelClearsTheFloorOnBothPourStops() {
        // The label crosses the whole pour (rot → dunkel) AND survives
        // the pressed state (deep pour only): brief reads 5.2:1 on the
        // red and 8.6:1 on the deep wax — both pinned ≥ 4.5.
        XCTAssertGreaterThanOrEqual(
            contrast(PaperRules.siegellackTextHex, PaperRules.siegellackHex),
            CouplePaletteRules.minimumContrast)
        XCTAssertGreaterThanOrEqual(
            contrast(PaperRules.siegellackTextHex, PaperRules.siegellackTiefHex),
            CouplePaletteRules.minimumContrast)
    }

    func testSiegellackSurfaceIsVisibleOnNightAndOnPaper() {
        // The seal is a UI COMPONENT, not text: its pour must hold the
        // 3:1 component floor against BOTH grounds it can rest on —
        // the night room (3.2:1) and a letter sheet (5.2:1).
        for ground in [PaperRules.zimmerObenHex, PaperRules.briefHex] {
            XCTAssertGreaterThanOrEqual(
                contrast(PaperRules.siegellackHex, ground), 3.0,
                "the seal must stay visible on \(ground)")
        }
    }

    func testSiegellackKanteIsDerivedWarmAndDecorOnly() {
        // Derived (wachsRot → lampengold at the SAME pinned mix as the
        // night-card Lichtkante), never hand-picked — deterministic.
        XCTAssertEqual(PaperRules.siegellackKanteHex, "#C65D46")
        XCTAssertEqual(PaperRules.siegellackKanteHex, PaperRules.siegellackKanteHex)
        // Visibly lighter than the pour (the lamp catches the lip)…
        XCTAssertGreaterThan(RGBColor(hex: PaperRules.siegellackKanteHex)!.luminance,
                             RGBColor(hex: PaperRules.wachsRotHex)!.luminance)
        // …but DECOR: pinned below the text floor so the warm lip never
        // becomes a text ground.
        XCTAssertLessThan(contrast(PaperRules.siegellackKanteHex,
                                   PaperRules.wachsRotHex),
                          CouplePaletteRules.minimumContrast)
    }

    func testWaxIsMaterialNotInkOnNight() {
        // Wachs.rot on night: 3.2:1 — pinned BELOW the floor so the wax
        // never becomes text on the room; on paper it passes (5.2:1),
        // where it only ever appears as seal material anyway.
        XCTAssertLessThan(contrast(PaperRules.wachsRotHex, PaperRules.zimmerObenHex),
                          CouplePaletteRules.minimumContrast)
        XCTAssertGreaterThanOrEqual(contrast(PaperRules.wachsRotHex, PaperRules.briefHex),
                                    CouplePaletteRules.minimumContrast)
    }

    // MARK: P6-C token additions — success ink, warn wax, expiry accent

    func testErfolgInkIsPinnedAndPaperSafe() {
        XCTAssertEqual(PaperRules.tinteErfolgHex, "#2F5D42")
        // An ink like the other three: ≥ 4.5 on every TEXT paper…
        for paper in PaperRules.textPaperHexes {
            XCTAssertGreaterThanOrEqual(
                contrast(PaperRules.tinteErfolgHex, paper),
                CouplePaletteRules.minimumContrast,
                "erfolg must clear 4.5:1 on text paper \(paper)")
        }
        // …with the decision figure pinned with margin on brief…
        XCTAssertGreaterThanOrEqual(
            contrast(PaperRules.tinteErfolgHex, PaperRules.briefHex), 6.5)
        // …and paper-ONLY: on night it sits below the floor (success
        // speaks in lamplight there), pinned so nobody promotes it.
        XCTAssertLessThan(contrast(PaperRules.tinteErfolgHex, PaperRules.zimmerObenHex),
                          CouplePaletteRules.minimumContrast)
    }

    func testWarnWaxIsPinnedAndMirrorsTheRedLaw() {
        XCTAssertEqual(PaperRules.wachsGelbHex, "#8A5A00")
        // Readable as caution ink on every TEXT paper (kante is edge
        // material and stays out, exactly like Wachs.rot)…
        for paper in PaperRules.textPaperHexes {
            XCTAssertGreaterThanOrEqual(
                contrast(PaperRules.wachsGelbHex, paper),
                CouplePaletteRules.minimumContrast,
                "warn wax must clear 4.5:1 on text paper \(paper)")
        }
        // …and MATERIAL on night, never ink — below the floor, the same
        // pin shape that keeps the red wax off night copy.
        XCTAssertLessThan(contrast(PaperRules.wachsGelbHex, PaperRules.zimmerObenHex),
                          CouplePaletteRules.minimumContrast)
    }

    func testAblaufAccentIsTheEmberAndNightOnly() {
        // A semantic NAME, not a new color: countdown/expiry = glut.
        XCTAssertEqual(PaperRules.ablaufHex, PaperRules.glutHex)
        XCTAssertGreaterThanOrEqual(
            contrast(PaperRules.ablaufHex, PaperRules.zimmerObenHex),
            CouplePaletteRules.minimumContrast)
        // On paper the ember fails (2.4:1) — deadlines write in the warn
        // wax there; pinned so the accent never strays onto paper copy.
        XCTAssertLessThan(contrast(PaperRules.ablaufHex, PaperRules.briefHex),
                          CouplePaletteRules.minimumContrast)
    }

    // MARK: P6-C night ink steps (Nacht.sekundaer / Nacht.tertiaer)

    func testNightInkStepsArePinnedAndComposite() {
        XCTAssertEqual(PaperRules.nachtSekundaerOpacity, 0.78)
        XCTAssertEqual(PaperRules.nachtTertiaerOpacity, 0.64)
        // The steps are judged as the COMPOSITE the room actually shows
        // (aufNacht blended over zimmerOben), not as naive hex pairs.
        let sekundaer = PaperRules.nightInkCompositeHex(
            opacity: PaperRules.nachtSekundaerOpacity)
        let tertiaer = PaperRules.nightInkCompositeHex(
            opacity: PaperRules.nachtTertiaerOpacity)
        XCTAssertGreaterThanOrEqual(contrast(sekundaer, PaperRules.zimmerObenHex), 7.0,
                                    "secondary night copy holds AA-large with margin")
        XCTAssertGreaterThanOrEqual(contrast(tertiaer, PaperRules.zimmerObenHex),
                                    CouplePaletteRules.minimumContrast)
        // Hierarchy stays monotonic: sekundaer reads louder than tertiaer.
        XCTAssertGreaterThan(contrast(sekundaer, PaperRules.zimmerObenHex),
                             contrast(tertiaer, PaperRules.zimmerObenHex))
    }

    // MARK: Nacht-first (P1-A) — the THIRD anchor: nachtkarton

    func testNachtkartonAnchorsTheNightInkFamily() {
        let card = PaperRules.nachtkartonHex
        // aufNacht carries the standard card (12.5:1, pinned with margin
        // over the 4.5 floor)…
        XCTAssertGreaterThanOrEqual(contrast(PaperRules.aufNachtHex, card), 12.0)
        // …and the pinned opacity steps hold as the COMPOSITES the card
        // actually shows (aufNacht blended over nachtkarton).
        let sekundaer = PaperRules.nightInkCompositeHex(
            opacity: PaperRules.nachtSekundaerOpacity, overHex: card)
        let tertiaer = PaperRules.nightInkCompositeHex(
            opacity: PaperRules.nachtTertiaerOpacity, overHex: card)
        XCTAssertGreaterThanOrEqual(contrast(sekundaer, card), 7.0,
                                    "secondary copy holds AA-large with margin on the night card")
        XCTAssertGreaterThanOrEqual(contrast(tertiaer, card),
                                    CouplePaletteRules.minimumContrast)
        XCTAssertGreaterThan(contrast(sekundaer, card), contrast(tertiaer, card))
        // The PAPER inks are banned on the night card — dark on dark:
        // pinned far below the floor so nobody carries Tinte.* across.
        XCTAssertLessThan(contrast(PaperRules.tinteDunkelHex, card),
                          CouplePaletteRules.minimumContrast)
    }

    func testLamplightCarriesAccentsOnNachtkarton() {
        let card = PaperRules.nachtkartonHex
        // Lamplight stays the accent vocabulary on the dark card
        // (gold 9.5, glut 5.6, energyRed 5.4 — all pinned ≥ 4.5)…
        for accent in [PaperRules.lampengoldHex, PaperRules.glutHex,
                       PaperRules.energyRedHex] {
            XCTAssertGreaterThanOrEqual(contrast(accent, card),
                                        CouplePaletteRules.minimumContrast,
                                        "\(accent) must clear 4.5:1 on nachtkarton")
        }
        // …while wax and the paper-only success ink stay MATERIAL there,
        // exactly like on the room (pinned below the floor).
        for material in [PaperRules.wachsRotHex, PaperRules.wachsGelbHex,
                         PaperRules.wachsDunkelHex, PaperRules.tinteErfolgHex] {
            XCTAssertLessThan(contrast(material, card),
                              CouplePaletteRules.minimumContrast,
                              "\(material) is material on nachtkarton, never ink")
        }
    }

    func testNachtLichtkanteIsDerivedWarmAndDecorOnly() {
        // Derived (nachtkarton → lampengold at the pinned mix), never
        // hand-picked — deterministic, so widgets/docs can mirror it.
        XCTAssertEqual(PaperRules.nachtLichtkanteMix, 0.25)
        XCTAssertEqual(PaperRules.nachtLichtkanteHex, "#664C30")
        XCTAssertEqual(PaperRules.nachtLichtkanteHex, PaperRules.nachtLichtkanteHex)
        // Visibly lighter than the card (the lamp catches the lip)…
        let card = RGBColor(hex: PaperRules.nachtkartonHex)!
        let edge = RGBColor(hex: PaperRules.nachtLichtkanteHex)!
        XCTAssertGreaterThan(edge.luminance, card.luminance * 2)
        // …but DECOR: pinned below the text floor so the warm edge never
        // becomes a text ground.
        XCTAssertLessThan(contrast(PaperRules.nachtLichtkanteHex,
                                   PaperRules.nachtkartonHex),
                          CouplePaletteRules.minimumContrast)
    }

    func testDeepWaxCarriesTheLightEmbossing() {
        // The fixed pour stop of the nacht-first seal: the light
        // embossing (aufNacht) clears the floor with margin (8.1:1)…
        XCTAssertGreaterThanOrEqual(
            contrast(PaperRules.aufNachtHex, PaperRules.wachsDunkelHex), 8.0)
        // …and the deep wax obeys the material law on the room like its
        // siblings — never ink on night (1.9:1, pinned).
        XCTAssertLessThan(contrast(PaperRules.wachsDunkelHex, PaperRules.zimmerObenHex),
                          CouplePaletteRules.minimumContrast)
    }

    // MARK: P6-C Wordle stamp verdicts (pinned, no view change)

    func testWordleMappingIsPinnedToTheStampVocabulary() {
        // Exactly the mapping WordleView documents: correct = dark-ink
        // stamp, present = wax-red pad, absent = innenFill wash on brief.
        XCTAssertEqual(PaperRules.wordleCorrectHex, PaperRules.tinteDunkelHex)
        XCTAssertEqual(PaperRules.wordlePresentHex, PaperRules.wachsRotHex)
        XCTAssertEqual(PaperRules.innenFillOpacity, 0.05)
        // The absent chip is DERIVED (wash over brief), never hand-picked
        // — and deterministic, so it can be mirrored (widgets, docs).
        XCTAssertEqual(PaperRules.wordleAbsentHex, "#EDE7DA")
        XCTAssertEqual(PaperRules.wordleAbsentHex, PaperRules.wordleAbsentHex)
    }

    func testWordleLabelsClearTheFloorOnTheirStamps() {
        // Tile labels as rendered: brief on correct/present, tertiaer on
        // the absent wash — every pairing ≥ 4.5:1.
        XCTAssertGreaterThanOrEqual(
            contrast(PaperRules.briefHex, PaperRules.wordleCorrectHex), 13.0)
        XCTAssertGreaterThanOrEqual(
            contrast(PaperRules.briefHex, PaperRules.wordlePresentHex),
            CouplePaletteRules.minimumContrast)
        XCTAssertGreaterThanOrEqual(
            contrast(PaperRules.tinteTertiaerHex, PaperRules.wordleAbsentHex),
            CouplePaletteRules.minimumContrast)
    }

    // MARK: Grain cap (ratchet rewrite, CI rule 5)

    func testGrainLuminanceCapIsPinned() {
        // The Korn cap is LAW: exactly 0.02 — the test breaks on every
        // increase, and Increased Contrast turns the grain off entirely.
        XCTAssertEqual(PaperRules.grainLuminance, 0.02)
        XCTAssertEqual(PaperRules.grainLuminance(increasedContrast: false), 0.02)
        XCTAssertEqual(PaperRules.grainLuminance(increasedContrast: true), 0)
    }

    // MARK: Light edge (+8 % luminance, derived not hand-picked)

    func testLightEdgeSitsJustAboveTheBoost() {
        let brief = RGBColor(hex: PaperRules.briefHex)!
        let edge = RGBColor(hex: PaperRules.lichtkanteHex)!
        let boost = edge.luminance / brief.luminance
        XCTAssertGreaterThanOrEqual(boost, 1 + PaperRules.lichtkanteBoost)
        // …and not runaway-bright: the first hundredth step that clears
        // the target must stay well under +13 %.
        XCTAssertLessThan(boost, 1.13)
        // Deterministic — the edge is a token, not a per-render dice roll.
        XCTAssertEqual(PaperRules.lichtkanteHex, PaperRules.lichtkanteHex)
    }

    // MARK: Kitsch budgets (charter v3 guardrails)

    func testKitschBudgetsArePinned() {
        XCTAssertEqual(PaperRules.artifactBudgetPerScreen, 3)
        XCTAssertEqual(PaperRules.tornEdgeBudgetPerScreen, 1)
        XCTAssertEqual(PaperRules.rotationBudgetPerScreen, 1)
        XCTAssertEqual(PaperRules.tornEdgeAppCap, 6)
    }

    // MARK: R1-D — the collection exception to the rotation law

    func testRotationCollectionBudgetIsPinned() {
        // "Ein Screen kippt 1 Solitär ODER bis zu 3 in EINER Sammlung":
        // the solitaire budget stays 1, the card-grid exception (gallery
        // month sections and their kin) allows at most 3 tilted Zettel
        // inside ONE collection — pinned so neither number drifts.
        XCTAssertEqual(PaperRules.rotationBudgetPerScreen, 1)
        XCTAssertEqual(PaperRules.rotationBudgetPerCollection, 3)
        // The exception is wider than the solitaire rule by design —
        // if this inverts, someone rewrote the law backwards.
        XCTAssertGreaterThan(PaperRules.rotationBudgetPerCollection,
                             PaperRules.rotationBudgetPerScreen)
        // A collection may never out-tilt the artifact budget either:
        // 3 tilted cards are the ceiling of paper theatrics per screen.
        XCTAssertLessThanOrEqual(PaperRules.rotationBudgetPerCollection,
                                 PaperRules.artifactBudgetPerScreen)
    }

    // MARK: Seeded paper physics

    func testTiltIsDeterministicAndInsideTheRange() {
        for seed: UInt64 in [0, 1, 42, 137, 0xDEADBEEF, .max] {
            let tilt = PaperRules.tiltDegrees(seed: seed)
            XCTAssertEqual(tilt, PaperRules.tiltDegrees(seed: seed),
                           "same seed, same tilt — nothing flickers")
            XCTAssertLessThanOrEqual(abs(tilt), PaperRules.tiltMaxDegrees)
        }
        // Different seeds genuinely spread — the tilt is not a constant.
        XCTAssertNotEqual(PaperRules.tiltDegrees(seed: 1),
                          PaperRules.tiltDegrees(seed: 2))
    }

    func testGridTiltIsTheDampedSolitaireTilt() {
        // The damping is a real reduction (0 < damping < 1) — a grid
        // Zettel leans, it never swings its corners past the cell.
        XCTAssertGreaterThan(PaperRules.gridTiltDamping, 0)
        XCTAssertLessThan(PaperRules.gridTiltDamping, 1)
        for seed: UInt64 in [0, 1, 42, 137, 0xDEADBEEF, .max] {
            let grid = PaperRules.gridTiltDegrees(seed: seed)
            // Same seed math: a card keeps its lean direction, only the
            // amplitude is damped — and it stays inside the damped band.
            XCTAssertEqual(grid,
                           PaperRules.tiltDegrees(seed: seed) * PaperRules.gridTiltDamping,
                           accuracy: 0.0001)
            XCTAssertLessThanOrEqual(
                abs(grid), PaperRules.tiltMaxDegrees * PaperRules.gridTiltDamping)
            XCTAssertEqual(grid, PaperRules.gridTiltDegrees(seed: seed),
                           "same seed, same tilt — nothing flickers")
        }
    }

    func testTornEdgeStaysInsideAmplitudeAndPeriodBand() {
        for seed: UInt64 in [7, 99, 12_345] {
            let period = PaperRules.tornPeriod(seed: seed)
            XCTAssertGreaterThanOrEqual(period, PaperRules.tornPeriodMin)
            XCTAssertLessThanOrEqual(period, PaperRules.tornPeriodMax)
            XCTAssertEqual(period, PaperRules.tornPeriod(seed: seed))
            for index in 0..<32 {
                let offset = PaperRules.tornOffset(seed: seed, index: index)
                XCTAssertLessThanOrEqual(abs(offset), PaperRules.tornAmplitude,
                                         "tooth \(index) must respect the amplitude")
                XCTAssertEqual(offset, PaperRules.tornOffset(seed: seed, index: index))
            }
        }
    }
}
