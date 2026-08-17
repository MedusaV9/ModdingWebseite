import Foundation

// FullRelease R2 (Widgets-Final-Eval S2): THE single Foundation source for
// the ten published icon-variant palettes. `AppIconKit.variants`
// (IconGiftView.swift) and `WidgetThemes.iconPalettes` (WidgetStudio.swift)
// both DERIVE from this table, so those two mirrors can no longer drift by
// construction. The third mirror — the standalone icon script
// `scripts/GenerateIcon.swift` (float RGB, cannot import app modules) — is
// held to this table by `WidgetThemesTests.testGeneratorPalettesMatchTheTable`,
// which parses the script source and compares every channel with 1/255
// tolerance. Changing a published hex therefore means: edit it HERE, mirror
// it in the generator floats, and the tests stay the referee.
enum IconPaletteTable {
    struct Entry: Equatable {
        /// Icon id ("classic", "sunset", …) — widget theme ids prefix
        /// "icon-", asset names prefix "AppIcon-" (classic = primary icon).
        let id: String
        /// The three night-gradient background stops, bare RRGGBB.
        let bg: [String]
        /// The published heart hex (== the generator's `pane[1]` stop —
        /// wax + ink of the polaroid motif).
        let heart: String
    }

    static let entries: [Entry] = [
        // Nachtpostamt-Umfärbung (Gesamtbild-Eval S1 „Markenbruch"): the
        // DEFAULT icon wears the app's own room — no invented hexes, every
        // value is a PaperRules law: bg = Nachtraum ground (zimmerOben
        // 1A100B, zimmerUnten 2A1B12, lichtkegel 4A3320 as the lamp-lit
        // top stop), heart = goldene Tinte (Licht.lampengold FFC46B —
        // the generator bends its wax decisively toward Wachs.rot, see
        // `waxRedMix` in GenerateIcon.swift). Paper stays the invariant
        // Polaroid-Weiß FAF6EC.
        Entry(id: "classic", bg: ["1A100B", "2A1B12", "4A3320"], heart: "FFC46B"),
        Entry(id: "sunset", bg: ["24081A", "591424", "A63821"], heart: "FF7359"),
        Entry(id: "midnight", bg: ["03030D", "080D24", "121A40"], heart: "6B8CF2"),
        Entry(id: "mint", bg: ["031A1A", "053330", "0D5447"], heart: "59E6B8"),
        Entry(id: "rose", bg: ["290D17", "4D1729", "7A2940"], heart: "FF80A3"),
        Entry(id: "ocean", bg: ["030A1F", "051A3D", "083361"], heart: "4DB3F2"),
        // Sibling separation against the now-golden classic: the gold
        // GIFT variant switches its heart to Kupfer (PaperRules B87333)
        // — same warm family, clearly its own voice.
        Entry(id: "gold", bg: ["1A0D05", "381F0A", "663D14"], heart: "B87333"),
        Entry(id: "lavender", bg: ["141024", "291F47", "473870"], heart: "B88CF2"),
        Entry(id: "blossom", bg: ["1F051A", "3D0D33", "6B1F4D"], heart: "FF8CBF"),
        Entry(id: "aurora", bg: ["030814", "081A29", "143342"], heart: "59D9CC"),
    ]

    static func entry(_ id: String) -> Entry {
        entries.first { $0.id == id } ?? entries[0]
    }
}
