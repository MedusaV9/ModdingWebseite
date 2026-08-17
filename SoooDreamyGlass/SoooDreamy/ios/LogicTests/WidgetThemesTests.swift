import XCTest
@testable import SoooDreamyLogic

/// W7/35-Rest icon+widget family sets: the "appicon" theme must resolve to
/// the palette of the ACTIVE home-screen icon — and always to a real spec.
final class WidgetThemesTests: XCTestCase {

    func testAppIconThemeIsRegisteredAndResolves() {
        XCTAssertTrue(WidgetThemes.all.contains { $0.id == "appicon" },
                      "the icon-matching theme must be pickable in the studio")
        XCTAssertEqual(WidgetThemes.iconSpec(iconId: "sunset").id, "icon-sunset")
        // No mirror yet (fresh install) and camera garbage both land on the
        // classic icon — never a dead widget.
        XCTAssertEqual(WidgetThemes.iconSpec(iconId: nil).id, "icon-classic")
        XCTAssertEqual(WidgetThemes.iconSpec(iconId: "not-an-icon").id, "icon-classic")
    }

    func testRenderSpecFollowsTheMirroredIconOnlyForAppicon() {
        XCTAssertEqual(WidgetThemes.renderSpec(id: "appicon", iconId: "gold").id, "icon-gold")
        // Static ids stay static, no matter which icon is active.
        XCTAssertEqual(WidgetThemes.renderSpec(id: "ocean", iconId: "gold").id, "ocean")
        XCTAssertEqual(WidgetThemes.renderSpec(id: nil, iconId: "gold").id, "night")
    }

    // MARK: Paper & light mirror (P6-C)

    /// The widget extension compiles standalone, so `WidgetPaperHex` MIRRORS
    /// the law table instead of importing it — this pin is the only thing
    /// keeping the two tables from drifting apart.
    func testWidgetPaperHexMirrorsThePaperRulesLawTable() {
        func bare(_ hex: String) -> String { hex.replacingOccurrences(of: "#", with: "") }
        XCTAssertEqual(WidgetPaperHex.zimmerOben, bare(PaperRules.zimmerObenHex))
        XCTAssertEqual(WidgetPaperHex.zimmerUnten, bare(PaperRules.zimmerUntenHex))
        XCTAssertEqual(WidgetPaperHex.brief, bare(PaperRules.briefHex))
        XCTAssertEqual(WidgetPaperHex.karton, bare(PaperRules.kartonHex))
        XCTAssertEqual(WidgetPaperHex.polaroid, bare(PaperRules.polaroidHex))
        XCTAssertEqual(WidgetPaperHex.tinteDunkel, bare(PaperRules.tinteDunkelHex))
        XCTAssertEqual(WidgetPaperHex.tinteSekundaer, bare(PaperRules.tinteSekundaerHex))
        XCTAssertEqual(WidgetPaperHex.aufNacht, bare(PaperRules.aufNachtHex))
        XCTAssertEqual(WidgetPaperHex.lampengold, bare(PaperRules.lampengoldHex))
        XCTAssertEqual(WidgetPaperHex.glut, bare(PaperRules.glutHex))
        XCTAssertEqual(WidgetPaperHex.wachsRot, bare(PaperRules.wachsRotHex))
        XCTAssertEqual(WidgetPaperHex.wachsGelb, bare(PaperRules.wachsGelbHex))
        XCTAssertEqual(WidgetPaperHex.nachtSekundaerOpacity, PaperRules.nachtSekundaerOpacity)
    }

    /// The default theme (stable id "night", pinned in WidgetReliabilityTests)
    /// wears the sepia room; its daylight twin "paper" is the paper sheet.
    /// Every rendered text/accent pairing clears the 4.5:1 floor.
    func testHomeThemesWearThePaperLightSystemAndClearTheFloor() {
        let night = WidgetThemes.spec(id: "night")
        XCTAssertEqual(night.backgroundHexes,
                       [WidgetPaperHex.zimmerOben, WidgetPaperHex.zimmerUnten])
        XCTAssertEqual(night.accentHex, WidgetPaperHex.lampengold)
        XCTAssertEqual(night.accentSecondaryHex, WidgetPaperHex.glut)
        XCTAssertFalse(night.isLight)

        let paper = WidgetThemes.spec(id: "paper")
        XCTAssertEqual(paper.id, "paper", "the paper theme must be registered")
        XCTAssertEqual(paper.backgroundHexes,
                       [WidgetPaperHex.brief, WidgetPaperHex.karton])
        XCTAssertEqual(paper.accentHex, WidgetPaperHex.wachsRot)
        XCTAssertEqual(paper.accentSecondaryHex, WidgetPaperHex.wachsGelb)
        XCTAssertTrue(paper.isLight, "paper writes in ink — dark text")

        // Night room: aufNacht text + both lamp accents on BOTH stops.
        for stop in night.backgroundHexes {
            for ink in [WidgetPaperHex.aufNacht, night.accentHex, night.accentSecondaryHex] {
                XCTAssertGreaterThanOrEqual(
                    CouplePaletteRules.contrastRatio(ink, stop) ?? 0, 4.5,
                    "\(ink) must clear the floor on night stop \(stop)")
            }
        }
        // Paper sheet: both inks + both wax accents on BOTH stops.
        for stop in paper.backgroundHexes {
            for ink in [WidgetPaperHex.tinteDunkel, WidgetPaperHex.tinteSekundaer,
                        paper.accentHex, paper.accentSecondaryHex] {
                XCTAssertGreaterThanOrEqual(
                    CouplePaletteRules.contrastRatio(ink, stop) ?? 0, 4.5,
                    "\(ink) must clear the floor on paper stop \(stop)")
            }
        }
    }

    func testIconPalettesMirrorTheTenIconVariants() {
        XCTAssertEqual(WidgetThemes.iconPalettes.map(\.id),
                       ["icon-classic", "icon-sunset", "icon-midnight", "icon-mint",
                        "icon-rose", "icon-ocean", "icon-gold", "icon-lavender",
                        "icon-blossom", "icon-aurora"])
        for spec in WidgetThemes.iconPalettes {
            XCTAssertGreaterThanOrEqual(spec.backgroundHexes.count, 2,
                                        "\(spec.id): background must be a gradient")
            XCTAssertEqual(spec.accentHex.count, 6, "\(spec.id): accent must be RRGGBB")
            XCTAssertEqual(spec.accentSecondaryHex.count, 6,
                           "\(spec.id): secondary accent must be RRGGBB")
            XCTAssertFalse(spec.isLight, "icon palettes are night gradients — dark text would drown")
        }
    }

    // MARK: Icon-hex drift pins (R2: real three-way protection)

    /// `IconPaletteTable` is THE single source: `AppIconKit.variants` and
    /// `WidgetThemes.iconPalettes` both derive from it by construction.
    /// This pin freezes the published hexes as a human-visible anchor, and
    /// the derivation assert documents the construction.
    func testIconPaletteTableIsPinnedAndDrivesTheWidgetPalettes() {
        // Nachtpostamt-Umfärbung (Gesamtbild-Eval S1): classic wears the
        // PaperRules Nachtraum ground (zimmerOben/zimmerUnten/lichtkegel)
        // under the golden ink (Licht.lampengold); gold's gift heart is
        // Kupfer (sibling separation against the golden classic). All
        // published hexes ARE PaperRules law values — no inventions.
        let pinned: [(id: String, bg: [String], heart: String)] = [
            ("classic", ["1A100B", "2A1B12", "4A3320"], "FFC46B"),
            ("sunset", ["24081A", "591424", "A63821"], "FF7359"),
            ("midnight", ["03030D", "080D24", "121A40"], "6B8CF2"),
            ("mint", ["031A1A", "053330", "0D5447"], "59E6B8"),
            ("rose", ["290D17", "4D1729", "7A2940"], "FF80A3"),
            ("ocean", ["030A1F", "051A3D", "083361"], "4DB3F2"),
            ("gold", ["1A0D05", "381F0A", "663D14"], "B87333"),
            ("lavender", ["141024", "291F47", "473870"], "B88CF2"),
            ("blossom", ["1F051A", "3D0D33", "6B1F4D"], "FF8CBF"),
            ("aurora", ["030814", "081A29", "143342"], "59D9CC"),
        ]
        XCTAssertEqual(IconPaletteTable.entries.count, pinned.count)
        for expected in pinned {
            let entry = IconPaletteTable.entry(expected.id)
            XCTAssertEqual(entry.id, expected.id, "table lost variant \(expected.id)")
            XCTAssertEqual(entry.bg, expected.bg, "\(expected.id): published bg drifted")
            XCTAssertEqual(entry.heart, expected.heart, "\(expected.id): published heart drifted")
        }
        // The Nachtpostamt values are LITERALLY the PaperRules laws —
        // recoloring the room/ink there must recolor the icon with it.
        func bare(_ hex: String) -> String { hex.replacingOccurrences(of: "#", with: "") }
        let classic = IconPaletteTable.entry("classic")
        XCTAssertEqual(classic.bg, [bare(PaperRules.zimmerObenHex),
                                    bare(PaperRules.zimmerUntenHex),
                                    bare(PaperRules.lichtkegelHex)],
                       "classic ground must stay the PaperRules Nachtraum")
        XCTAssertEqual(classic.heart, bare(PaperRules.lampengoldHex),
                       "classic ink must stay the golden Licht.lampengold")
        XCTAssertEqual(IconPaletteTable.entry("gold").heart,
                       bare(PaperRules.kupferHex),
                       "the gold gift variant wears Kupfer since the recolor")
        for entry in IconPaletteTable.entries {
            guard let spec = WidgetThemes.iconPalettes.first(where: { $0.id == "icon-\(entry.id)" })
            else {
                XCTFail("icon palette icon-\(entry.id) is missing")
                continue
            }
            XCTAssertEqual(spec.backgroundHexes, entry.bg)
            XCTAssertEqual(spec.accentHex, entry.heart)
        }
    }

    /// The third mirror — the standalone `scripts/GenerateIcon.swift` CLI —
    /// cannot import the table (float RGB, no app modules). This test
    /// parses the script SOURCE and compares every published channel
    /// (`bg` stops + `pane[1]` heart) against `IconPaletteTable` with 1/255
    /// tolerance: a hex changed in only one place breaks the build.
    func testGeneratorPalettesMatchTheTable() throws {
        let scriptURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()      // LogicTests/
            .deletingLastPathComponent()      // ios/
            .appendingPathComponent("scripts/GenerateIcon.swift")
        let source = try String(contentsOf: scriptURL, encoding: .utf8)

        func channels(of hex: String) -> [Double] {
            stride(from: 0, to: 6, by: 2).map { offset in
                let start = hex.index(hex.startIndex, offsetBy: offset)
                let end = hex.index(start, offsetBy: 2)
                return Double(Int(hex[start..<end], radix: 16) ?? 0) / 255.0
            }
        }

        func tripleList(after label: String, in block: Substring) -> [[Double]] {
            guard let range = block.range(of: "\(label): [") else { return [] }
            guard let close = block[range.upperBound...].range(of: "]") else { return [] }
            let list = block[range.upperBound..<close.lowerBound]
            let numberPattern = #"\(([0-9.]+),\s*([0-9.]+),\s*([0-9.]+)\)"#
            let regex = try? NSRegularExpression(pattern: numberPattern)
            let text = String(list)
            let matches = regex?.matches(in: text,
                                         range: NSRange(text.startIndex..., in: text)) ?? []
            return matches.map { match in
                (1...3).map { i in
                    guard let r = Range(match.range(at: i), in: text) else { return 0.0 }
                    return Double(text[r]) ?? 0
                }
            }
        }

        for entry in IconPaletteTable.entries {
            guard let blockStart = source.range(of: "\"\(entry.id)\": Palette(") else {
                XCTFail("generator lost variant \(entry.id)")
                continue
            }
            let block = source[blockStart.upperBound...].prefix(600)
            let bg = tripleList(after: "bg", in: block)
            XCTAssertEqual(bg.count, 3, "\(entry.id): generator bg must have 3 stops")
            for (stop, hex) in zip(bg, entry.bg) {
                for (channel, expected) in zip(stop, channels(of: hex)) {
                    XCTAssertEqual(channel, expected, accuracy: 1.0 / 255.0,
                                   "\(entry.id): generator bg drifted from IconPaletteTable (\(hex))")
                }
            }
            let pane = tripleList(after: "pane", in: block)
            XCTAssertGreaterThanOrEqual(pane.count, 2, "\(entry.id): generator pane needs 2+ stops")
            for (channel, expected) in zip(pane[1], channels(of: entry.heart)) {
                XCTAssertEqual(channel, expected, accuracy: 1.0 / 255.0,
                               "\(entry.id): generator heart (pane[1]) drifted from IconPaletteTable (\(entry.heart))")
            }
        }
    }

    // MARK: Live-activity contrast (paper fix)

    /// The ink hexes a live activity really renders, mirrored from
    /// `WidgetPalette.textPrimary`/`textSecondary` (Widgets/WidgetTheme.swift
    /// compiles only in the extension target, so the mapping is restated
    /// here — the constants come from the same pinned `WidgetPaperHex`/
    /// `PaperRules` tables the mirror test above locks together).
    private func activityTextHexes(_ spec: WidgetThemeSpec,
                                   onStop stop: String) -> (primary: String,
                                                            secondary: String) {
        func composite(_ ink: String, opacity: Double) -> String {
            guard let ground = RGBColor(hex: stop), let top = RGBColor(hex: ink) else {
                return ink
            }
            return ground.mixed(with: top, amount: opacity).hex
        }
        if spec.isLight {
            return (WidgetPaperHex.tinteDunkel, WidgetPaperHex.tinteSekundaer)
        }
        if spec.id == "night" {
            return (WidgetPaperHex.aufNacht,
                    composite(WidgetPaperHex.aufNacht,
                              opacity: WidgetPaperHex.nachtSekundaerOpacity))
        }
        return ("FFFFFF", composite("FFFFFF", opacity: 0.65))
    }

    /// The DateNight/Countdown activities tint the lock-screen banner with
    /// the FIRST background stop (`palette.backgroundTint`). White on the
    /// light paper theme read 1.13:1 there — since the fix, body copy wears
    /// the palette inks, and every registered theme (plus every icon
    /// palette the "appicon" theme can resolve to) must keep both rendered
    /// text inks at or above the 4.5:1 floor on that tint. Accent-on-tint
    /// is pinned for the two home themes above; decorative accents keep
    /// their headroom debt out of this pin.
    func testLiveActivityTextInksClearTheFloorOnEveryThemeTint() {
        for spec in WidgetThemes.all + WidgetThemes.iconPalettes {
            guard let stop = spec.backgroundHexes.first else {
                XCTFail("\(spec.id): background must have a stop")
                continue
            }
            let inks = activityTextHexes(spec, onStop: stop)
            XCTAssertGreaterThanOrEqual(
                CouplePaletteRules.contrastRatio(inks.primary, stop) ?? 0, 4.5,
                "\(spec.id): activity textPrimary must clear 4.5:1 on the banner tint")
            XCTAssertGreaterThanOrEqual(
                CouplePaletteRules.contrastRatio(inks.secondary, stop) ?? 0, 4.5,
                "\(spec.id): activity textSecondary must clear 4.5:1 on the banner tint")
        }
    }

    /// The regression that motivated the fix, pinned verbatim: hard white
    /// on the paper theme's letter-paper tint is ~1.13:1 — far below the
    /// floor. Should anyone reintroduce white text on the paper activity,
    /// this documents WHY the palette inks are not optional.
    func testHardWhiteOnPaperTintStaysBanned() {
        let paper = WidgetThemes.spec(id: "paper")
        let tint = paper.backgroundHexes.first ?? ""
        let whiteOnPaper = CouplePaletteRules.contrastRatio("FFFFFF", tint) ?? 0
        XCTAssertLessThan(whiteOnPaper, 1.3,
                          "letter paper is nearly white — hard white text is invisible")
        XCTAssertGreaterThanOrEqual(
            CouplePaletteRules.contrastRatio(WidgetPaperHex.tinteDunkel, tint) ?? 0, 4.5)
        XCTAssertGreaterThanOrEqual(
            CouplePaletteRules.contrastRatio(WidgetPaperHex.tinteSekundaer, tint) ?? 0, 4.5)
    }
}
