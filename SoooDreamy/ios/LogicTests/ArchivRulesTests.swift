import XCTest
@testable import SoooDreamyLogic

/// Pins the Archiv cabinet law (NEUBAU_ENTSCHEID §4.4): every
/// `MemoriesSection` lies in EXACTLY one of the six drawers — nothing
/// missing, nothing doubled, nothing invented. `MemoriesSection` is
/// app-only (SwiftUI file), so like KartenschrankRulesTests this scans
/// the enum declaration from source — the completeness guarantee stays
/// testable across the 4 → 6 group recut (Welle N4 gate).
final class ArchivRulesTests: XCTestCase {

    /// Package root (ios/), derived from this file's location.
    private static let packageDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // LogicTests/
        .deletingLastPathComponent()  // ios/ — the package root

    /// Raw values of `MemoriesSection`, parsed from the enum declaration
    /// in Stationen/Archiv/MemoriesHubComponents.swift (all cases are
    /// bare identifiers — none carries an explicit raw value, so case
    /// name == rawValue; trailing `// …` comments are stripped).
    private func memoriesSectionCases() throws -> [String] {
        let components = Self.packageDir
            .appendingPathComponent("SoooDreamy/Stationen/Archiv/MemoriesHubComponents.swift")
        let source = try String(contentsOf: components, encoding: .utf8)
        guard let start = source.range(of: "enum MemoriesSection"),
              let end = source.range(of: "var id", range: start.upperBound..<source.endIndex) else {
            XCTFail("MemoriesHubComponents.swift: could not locate the MemoriesSection declaration")
            return []
        }
        let body = source[start.upperBound..<end.lowerBound]
        var cases: [String] = []
        for line in body.split(separator: "\n") {
            var trimmed = line.trimmingCharacters(in: .whitespaces)
            if let comment = trimmed.range(of: "//") {
                trimmed = String(trimmed[..<comment.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
            }
            guard trimmed.hasPrefix("case ") else { continue }
            cases += trimmed.dropFirst("case ".count)
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        return cases
    }

    // MARK: Completeness + uniqueness (the cabinet coverage law)

    func testEverySectionLiesInExactlyOneFach() throws {
        let cases = try memoriesSectionCases()
        XCTAssertFalse(cases.isEmpty, "source scan found no MemoriesSection cases")
        XCTAssertEqual(Set(cases).count, cases.count,
                       "MemoriesSection declares a case twice")

        // Exact coverage: the pinned universe IS the enum — a new hub
        // section must be filed in ArchivRules before it ships.
        let mapped = Set(ArchivRules.allSectionIds)
        XCTAssertEqual(mapped, Set(cases),
                       "mapping must cover MemoriesSection EXACTLY — missing: "
                       + "\(Set(cases).subtracting(mapped).sorted()), "
                       + "extra: \(mapped.subtracting(cases).sorted())")

        // …and exactly ONE drawer per section: summed drawer contents
        // equal the deduplicated universe, so no id appears twice.
        let summed = ArchivFach.allCases
            .reduce(0) { $0 + ArchivRules.sections(in: $1).count }
        XCTAssertEqual(summed, mapped.count,
                       "a section id appears in more than one Fach")
        for id in cases {
            XCTAssertNotNil(ArchivRules.fach(forSection: id), "\(id) has no Fach")
        }
    }

    func testPinnedInventoryMatchesTheEntscheidTable() {
        // ENTSCHEID §2.2: the eighteen tile sections plus week review,
        // express-note history and the countdown calendars — 6+3+2+7+2+1.
        // Pinned EXACTLY (contents + display order, Fix-C Befund 7):
        // a drawer that silently reorders or swaps a section breaks here.
        XCTAssertEqual(ArchivRules.allSectionIds.count, 21)
        XCTAssertEqual(ArchivRules.sections(in: .alben),
                       ["gallery", "videos", "potd", "events", "story", "yearReview"])
        XCTAssertEqual(ArchivRules.sections(in: .planfach),
                       ["lists", "bucket", "weekplan"])
        XCTAssertEqual(ArchivRules.sections(in: .wertfach),
                       ["coupons", "goals"])
        XCTAssertEqual(ArchivRules.sections(in: .chronik),
                       ["journal", "stats", "soundtrack", "canvas", "magazine",
                        "weekReview", "needsHistory"])
        XCTAssertEqual(ArchivRules.sections(in: .lagerfach),
                       ["capsules", "seasonCalendar"])
        XCTAssertEqual(ArchivRules.sections(in: .tresorfach),
                       ["vault"])
        // Cabinet order: drawers as the ENTSCHEID table lists them.
        XCTAssertEqual(ArchivFach.allCases,
                       [.alben, .planfach, .wertfach, .chronik, .lagerfach, .tresorfach])
    }

    // MARK: Archive search (Befund 5c — the pure rule behind .searchable)

    func testSearchMatchesTitlesCaseAndDiacriticInsensitive() {
        let titles = ["gallery": ["Galerie"], "videos": ["Videos"],
                      "bucket": ["Träumeliste"], "vault": ["Tresor"]]
        // Case-insensitive…
        XCTAssertEqual(ArchivRules.matchingSectionIds(query: "galerie", titles: titles),
                       ["gallery"])
        // …diacritic-insensitive ("traume" finds „Träumeliste")…
        XCTAssertEqual(ArchivRules.matchingSectionIds(query: "TRAUME", titles: titles),
                       ["bucket"])
        // …substring anywhere, and ids without a title fall back to the id.
        XCTAssertEqual(ArchivRules.matchingSectionIds(query: "week", titles: [:]),
                       ["weekplan", "weekReview"])
    }

    func testSearchKeepsCabinetOrderAndEmptyQueryMatchesAll() {
        // Result order is CABINET order (drawer by drawer), never the
        // dictionary's — pinned against a title map that hits several
        // drawers at once.
        let titles = ["vault": ["Schatz"], "gallery": ["Schatzkiste"],
                      "coupons": ["Schatzgutscheine"]]
        XCTAssertEqual(ArchivRules.matchingSectionIds(query: "schatz", titles: titles),
                       ["gallery", "coupons", "vault"])
        // Empty and whitespace queries show the full front.
        XCTAssertEqual(ArchivRules.matchingSectionIds(query: "", titles: titles),
                       ArchivRules.allSectionIds)
        XCTAssertEqual(ArchivRules.matchingSectionIds(query: "   ", titles: titles),
                       ArchivRules.allSectionIds)
    }

    func testSearchOpensExactlyTheDrawersWithHits() {
        let titles = ["gallery": ["Galerie"], "journal": ["Tagebuch"]]
        // A title hit in Chronik → exactly that drawer opens („tageb"
        // avoids the alias layer: „ta" would also hit potd's „tagesfoto").
        XCTAssertEqual(ArchivRules.matchingFaecher(query: "tageb", titles: titles),
                       [.chronik])
        XCTAssertEqual(ArchivRules.matchingFaecher(query: "galerie", titles: titles),
                       [.alben])
        // No hit → no drawer; empty query → the whole cabinet.
        XCTAssertEqual(ArchivRules.matchingFaecher(query: "xyz", titles: titles), [])
        XCTAssertEqual(ArchivRules.matchingFaecher(query: "", titles: titles),
                       ArchivFach.allCases)
    }

    func testEveryTitleVariantJoinsTheOneFoldIndex() {
        // Sprachunabhängiger Index (Fix-Runde 3, Archiv-Befund 7): one id
        // carries SEVERAL language variants — each of them matches, and an
        // id whose variant list is empty falls back to the id itself.
        let titles = ["vault": ["Tresor", "Vault"],
                      "lists": ["Unsere Listen", "Our Lists"],
                      "gallery": []]
        XCTAssertEqual(ArchivRules.matchingSectionIds(query: "tresor", titles: titles),
                       ["vault"])
        XCTAssertEqual(ArchivRules.matchingSectionIds(query: "vault", titles: titles),
                       ["vault"])
        XCTAssertEqual(ArchivRules.matchingSectionIds(query: "listen", titles: titles),
                       ["lists"])
        XCTAssertEqual(ArchivRules.matchingSectionIds(query: "our lists", titles: titles),
                       ["lists"])
        XCTAssertEqual(ArchivRules.matchingSectionIds(query: "gallery", titles: titles),
                       ["gallery"])
        // Drawer names carry variants the same way.
        let fachTitles: [ArchivFach: [String]] = [.alben: ["Alben", "Albums"]]
        XCTAssertEqual(ArchivRules.matchingFaecher(query: "albums", titles: [:],
                                                   fachTitles: fachTitles),
                       [.alben])
        XCTAssertEqual(ArchivRules.matchingFaecher(query: "alben", titles: [:],
                                                   fachTitles: fachTitles),
                       [.alben])
    }

    // MARK: Alias + drawer-name index (Re-Eval Runde 2: „Alben"/„Fotos"
    // found nothing — the index knew only the exact display titles)

    /// The localized drawer names as the view hands them in (MemoriesL10n
    /// „archiv.fach.*" — the rule itself never touches L10n).
    private let fachTitlesDE: [ArchivFach: [String]] = [
        .alben: ["Alben"], .planfach: ["Planfach"], .wertfach: ["Wertfach"],
        .chronik: ["Chronik"], .lagerfach: ["Lagerfach"], .tresorfach: ["Tresorfach"]
    ]

    func testSearchFindsDrawersByTheirName() {
        // „Alben" is only the DRAWER's name — no section title contains
        // it, yet the whole drawer must open with all its sections.
        XCTAssertEqual(ArchivRules.matchingFaecher(query: "Alben", titles: [:],
                                                   fachTitles: fachTitlesDE),
                       [.alben])
        XCTAssertEqual(ArchivRules.matchingSectionIds(query: "alben", titles: [:],
                                                      fachTitles: fachTitlesDE),
                       ArchivRules.sections(in: .alben))
        // „Chronik" and „Planfach" — the Befund's exact repro queries.
        XCTAssertEqual(ArchivRules.matchingFaecher(query: "chronik", titles: [:],
                                                   fachTitles: fachTitlesDE),
                       [.chronik])
        XCTAssertEqual(ArchivRules.matchingFaecher(query: "PLANFACH", titles: [:],
                                                   fachTitles: fachTitlesDE),
                       [.planfach])
        XCTAssertEqual(ArchivRules.matchingSectionIds(query: "planfach", titles: [:],
                                                      fachTitles: fachTitlesDE),
                       ArchivRules.sections(in: .planfach))
    }

    func testSearchFindsSectionsByCuratedAliases() {
        // DE everyday words → their section, and the hit still opens the
        // drawer (Treffer öffnen weiterhin das Fach).
        XCTAssertEqual(ArchivRules.matchingSectionIds(query: "Fotos", titles: [:]),
                       ["gallery"])
        XCTAssertEqual(ArchivRules.matchingFaecher(query: "fotos", titles: [:]),
                       [.alben])
        XCTAssertEqual(ArchivRules.matchingSectionIds(query: "geld", titles: [:]),
                       ["goals"])
        XCTAssertEqual(ArchivRules.matchingSectionIds(query: "sparen", titles: [:]),
                       ["goals"])
        XCTAssertEqual(ArchivRules.matchingFaecher(query: "sparen", titles: [:]),
                       [.wertfach])
        XCTAssertEqual(ArchivRules.matchingSectionIds(query: "einkauf", titles: [:]),
                       ["lists"])
        // EN mirrors: the alias table carries both languages.
        XCTAssertEqual(ArchivRules.matchingSectionIds(query: "pictures", titles: [:]),
                       ["gallery"])
        XCTAssertEqual(ArchivRules.matchingSectionIds(query: "shopping", titles: [:]),
                       ["lists"])
        XCTAssertEqual(ArchivRules.matchingSectionIds(query: "saving", titles: [:]),
                       ["goals"])
    }

    // MARK: DE×EN matrix (Fix-Runde 3, Archiv-Befund 7: „tresor"/
    // „listen"/„alben" found nothing in the EN UI — the index carried
    // only the CURRENT language's titles)

    /// The section title key exactly as `MemoriesSection.titleKey`
    /// derives it (the enum is app-only SwiftUI, so the mapping is
    /// mirrored here; `memoriesSectionCases()` already pins that the
    /// id universe cannot drift).
    private func titleKey(forSection id: String) -> String {
        switch id {
        case "yearReview": return "memories.card.yearreview"
        case "weekReview": return "weekreview.title"
        case "needsHistory": return "archiv.section.needsHistory"
        case "seasonCalendar": return "seasoncalendar.title"
        default: return "memories.card.\(id)"
        }
    }

    /// The index exactly as MemoriesView builds it: BOTH language
    /// variants of every section title and drawer name, resolved from
    /// the real L10n tables via `MemoriesL10n.searchTitleVariants`.
    private func realTitleIndex() -> (titles: [String: [String]],
                                      fachTitles: [ArchivFach: [String]]) {
        let titles = Dictionary(uniqueKeysWithValues: ArchivRules.allSectionIds.map {
            ($0, MemoriesL10n.searchTitleVariants(titleKey(forSection: $0)))
        })
        let fachTitles = Dictionary(uniqueKeysWithValues: ArchivFach.allCases.map {
            ($0, MemoriesL10n.searchTitleVariants($0.titleKey))
        })
        return (titles, fachTitles)
    }

    /// The FULL DE×EN matrix over the six mandatory terms × both UI
    /// languages: every term hits the same sections whether the app
    /// speaks German or English, because the index carries both
    /// language variants of every title (plus the folded aliases).
    func testSearchMatrixSixMandatoryTermsTimesBothUILanguages() {
        let matrix: [(term: String, sections: [String], faecher: [ArchivFach])] = [
            ("fotos", ["gallery"], [.alben]),
            ("videos", ["videos"], [.alben]),
            ("sparen", ["goals"], [.wertfach]),
            ("tresor", ["vault"], [.tresorfach]),
            ("woche", ["weekplan", "weekReview"], [.planfach, .chronik]),
            ("listen", ["lists"], [.planfach]),
        ]
        let previous = L10n.language
        defer { L10n.language = previous }
        for language in [AppLanguage.de, AppLanguage.en] {
            L10n.language = language
            // Rebuilt UNDER each UI language — the variants resolver
            // never consults the current language, so the index (and
            // with it every hit) is identical in both columns.
            let index = realTitleIndex()
            for row in matrix {
                XCTAssertEqual(
                    ArchivRules.matchingSectionIds(query: row.term,
                                                   titles: index.titles,
                                                   fachTitles: index.fachTitles),
                    row.sections,
                    "„\(row.term)“ in \(language.rawValue.uppercased())-UI")
                XCTAssertEqual(
                    ArchivRules.matchingFaecher(query: row.term,
                                                titles: index.titles,
                                                fachTitles: index.fachTitles),
                    row.faecher,
                    "„\(row.term)“ in \(language.rawValue.uppercased())-UI")
            }
        }
    }

    /// …and the mirror direction: EN terms hit in the DE UI (the other
    /// half of „DE-Begriffe im EN-UI treffen und umgekehrt").
    func testSearchMatrixEnglishTermsHitInTheGermanUI() {
        let previous = L10n.language
        defer { L10n.language = previous }
        L10n.language = .de
        let index = realTitleIndex()
        let mirror: [(term: String, sections: [String])] = [
            ("vault", ["vault"]),
            ("our lists", ["lists"]),
            ("photos", ["gallery"]),
            ("saving", ["goals"]),
        ]
        for row in mirror {
            XCTAssertEqual(
                ArchivRules.matchingSectionIds(query: row.term,
                                               titles: index.titles,
                                               fachTitles: index.fachTitles),
                row.sections, "„\(row.term)“ in DE-UI")
        }
        // The drawer-name layer speaks both languages too: "albums"
        // opens the Alben drawer in the German UI.
        XCTAssertEqual(
            ArchivRules.matchingFaecher(query: "albums", titles: index.titles,
                                        fachTitles: index.fachTitles),
            [.alben], "„albums“ in DE-UI")
    }

    /// The resolver itself is language-blind: flipping the UI language
    /// must never change the variants (that WAS the bug — the view used
    /// `L10n.t`, which resolves only the current language).
    func testSearchTitleVariantsIgnoreTheUILanguage() {
        let previous = L10n.language
        defer { L10n.language = previous }
        L10n.language = .de
        let de = MemoriesL10n.searchTitleVariants("memories.card.vault")
        L10n.language = .en
        let en = MemoriesL10n.searchTitleVariants("memories.card.vault")
        XCTAssertEqual(de, en)
        XCTAssertEqual(Set(de), ["Tresor", "Vault"])
        // Unknown keys fall back to the key, mirroring `L10n.t`.
        XCTAssertEqual(MemoriesL10n.searchTitleVariants("nope.key"), ["nope.key"])
        // Identical DE/EN strings collapse to one variant — no double
        // entry in the fold index.
        XCTAssertEqual(MemoriesL10n.searchTitleVariants("memories.card.videos"),
                       ["Videos"])
    }

    /// The resolver walks the ONE runtime table stack (Fix-Runde 4, S3:
    /// it now iterates `L10n.tables` itself — internal exactly for
    /// this). Every table of the stack must be reachable: with the old
    /// hand-copied twin, a key living only in a newly added eleventh
    /// table would have fallen back to the bare key and silently
    /// starved the search index.
    func testSearchTitleVariantsWalkEveryRuntimeTable() {
        XCTAssertFalse(L10n.tables.isEmpty)
        for table in L10n.tables {
            guard let key = table.keys.first else {
                XCTFail("empty L10n table in the runtime stack")
                continue
            }
            XCTAssertNotEqual(MemoriesL10n.searchTitleVariants(key), [key],
                              "„\(key)“ must resolve through the shared stack, "
                              + "never fall back to the bare key")
        }
    }

    func testAliasTableStaysWellFormed() {
        for (id, aliases) in ArchivRules.sectionAliases {
            // Every alias key is a filed section — a typo cannot create
            // a phantom drawer entry.
            XCTAssertNotNil(ArchivRules.fach(forSection: id),
                            "alias key \(id) is not a filed section id")
            XCTAssertFalse(aliases.isEmpty, "\(id): empty alias list")
            for alias in aliases {
                // Stored ALREADY FOLDED, so matching stays one plain
                // `contains` — no alias may need folding at query time.
                XCTAssertEqual(alias, ArchivRules.searchFold(alias),
                               "\(id): alias „\(alias)“ is not stored folded")
                XCTAssertFalse(alias.isEmpty)
            }
        }
    }

    func testPreviewLineJoinsWithMidDot() {
        XCTAssertEqual(ArchivRules.previewLine(titles: ["Galerie", "Videos", "Momente"]),
                       "Galerie · Videos · Momente")
        XCTAssertEqual(ArchivRules.previewLine(titles: ["Tresor"]), "Tresor")
        XCTAssertEqual(ArchivRules.previewLine(titles: []), "")
    }

    func testLookupIsDeterministic() {
        // Same input, same drawer — across repeated calls and regardless
        // of query order (the lookup walks a constant table).
        for id in ArchivRules.allSectionIds.sorted() {
            XCTAssertEqual(ArchivRules.fach(forSection: id),
                           ArchivRules.fach(forSection: id))
        }
        XCTAssertEqual(ArchivRules.fach(forSection: "gallery"), .alben)
        XCTAssertEqual(ArchivRules.fach(forSection: "weekplan"), .planfach)
        XCTAssertEqual(ArchivRules.fach(forSection: "coupons"), .wertfach)
        XCTAssertEqual(ArchivRules.fach(forSection: "needsHistory"), .chronik)
        XCTAssertEqual(ArchivRules.fach(forSection: "capsules"), .lagerfach)
        XCTAssertEqual(ArchivRules.fach(forSection: "vault"), .tresorfach)
        XCTAssertNil(ArchivRules.fach(forSection: "nope"))
    }
}
