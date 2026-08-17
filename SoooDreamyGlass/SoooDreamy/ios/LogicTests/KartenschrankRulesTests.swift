import XCTest
@testable import SoooDreamyLogic

/// Pins the Spieltisch cabinet law (NEUBAU_ENTSCHEID §4.3, Adoption A1):
/// every `GameDestination` lies in EXACTLY one Fach — nothing missing,
/// nothing doubled, nothing invented — and the A1 register helpers
/// (played-rounds count, dotted line) stay pure and deterministic.
/// `GameDestination` is app-only (SwiftUI file), so like
/// GameKindParityTests this scans the enum declaration from source.
final class KartenschrankRulesTests: XCTestCase {

    /// Package root (ios/), derived from this file's location.
    private static let packageDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // LogicTests/
        .deletingLastPathComponent()  // ios/ — the package root

    /// Raw values of `GameDestination`, parsed from the enum declaration
    /// in Stationen/Spieltisch/PlayHubView.swift (all cases are bare
    /// lowercase identifiers — none carries an explicit raw value, so
    /// case name == rawValue; trailing `// …` comments are stripped).
    private func gameDestinationCases() throws -> [String] {
        let hub = Self.packageDir
            .appendingPathComponent("SoooDreamy/Stationen/Spieltisch/PlayHubView.swift")
        let source = try String(contentsOf: hub, encoding: .utf8)
        guard let start = source.range(of: "enum GameDestination"),
              let end = source.range(of: "var id", range: start.upperBound..<source.endIndex) else {
            XCTFail("PlayHubView.swift: could not locate the GameDestination declaration")
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

    func testEveryGameDestinationLiesInExactlyOneFach() throws {
        let cases = try gameDestinationCases()
        XCTAssertFalse(cases.isEmpty, "source scan found no GameDestination cases")
        XCTAssertEqual(Set(cases).count, cases.count,
                       "GameDestination declares a case twice")

        // Exact SINGLE coverage through the ONE shared frequency-counted
        // rule — the same `decktGenauEinmal` the hub asserts in DEBUG, so
        // test and assert can never diverge again. A doubled shelf entry
        // fails here even though set equality would still hold.
        XCTAssertTrue(KartenschrankRules.decktGenauEinmal(Set(cases)),
                      "mapping must cover GameDestination EXACTLY ONCE — missing: "
                      + "\(Set(cases).subtracting(KartenschrankRules.alleZiele).sorted()), "
                      + "extra: \(KartenschrankRules.alleZiele.subtracting(cases).sorted())")
        for id in cases {
            XCTAssertNotNil(KartenschrankRules.fach(fuer: id),
                            "\(id) has no Fach")
        }
    }

    func testDecktGenauEinmalCountsFrequencies() {
        let universe = KartenschrankRules.alleZiele
        XCTAssertTrue(KartenschrankRules.decktGenauEinmal(universe))
        // Missing and extra ids both break exact coverage.
        XCTAssertFalse(KartenschrankRules.decktGenauEinmal(universe.subtracting(["quiz"])))
        XCTAssertFalse(KartenschrankRules.decktGenauEinmal(universe.union(["poker"])))
        XCTAssertFalse(KartenschrankRules.decktGenauEinmal([]))
    }

    func testPinnedUniverseMatchesTheDossierTable() {
        // POSTAMT §2: „alle 34 GameDestination-Fälle" — the five shelves
        // carry 2 + 16 + 4 + 8 + 4 entries.
        XCTAssertEqual(KartenschrankRules.alleZiele.count, 34)
        XCTAssertEqual(KartenschrankRules.ziele(im: .aushang).count, 2)
        XCTAssertEqual(KartenschrankRules.ziele(im: .fernpartien).count, 16)
        XCTAssertEqual(KartenschrankRules.ziele(im: .amTisch).count, 4)
        XCTAssertEqual(KartenschrankRules.ziele(im: .festeFragen).count, 8)
        XCTAssertEqual(KartenschrankRules.ziele(im: .spielbuch).count, 4)
        // The physical cabinet has exactly its three drawers, shelf order.
        XCTAssertEqual(KartenschrankFach.schrank,
                       [.fernpartien, .amTisch, .festeFragen])
    }

    func testLookupIsDeterministic() {
        // Same input, same drawer — across repeated calls and regardless
        // of query order (the reverse map is built once from a constant).
        for id in KartenschrankRules.alleZiele.sorted() {
            XCTAssertEqual(KartenschrankRules.fach(fuer: id),
                           KartenschrankRules.fach(fuer: id))
        }
        XCTAssertEqual(KartenschrankRules.fach(fuer: "battleship"), .fernpartien)
        XCTAssertEqual(KartenschrankRules.fach(fuer: "rps"), .amTisch)
        XCTAssertEqual(KartenschrankRules.fach(fuer: "movieroulette"), .festeFragen)
        XCTAssertEqual(KartenschrankRules.fach(fuer: "wordle"), .aushang)
        XCTAssertEqual(KartenschrankRules.fach(fuer: "replay"), .spielbuch)
        XCTAssertNil(KartenschrankRules.fach(fuer: "poker"),
                     "ids outside the pinned universe have no Fach")
    }

    // MARK: Adoption A1 — the honest page number + the dotted line

    func testGespieltePartienCountsOnlyTheFachsRounds() {
        let verlauf = ["battleship", "battleship", "rps", "quiz",
                       "kniffel", "poker", "dailyquests"]
        XCTAssertEqual(KartenschrankRules.gespieltePartien(im: .fernpartien,
                                                           verlauf: verlauf), 3)
        XCTAssertEqual(KartenschrankRules.gespieltePartien(im: .amTisch,
                                                           verlauf: verlauf), 1)
        XCTAssertEqual(KartenschrankRules.gespieltePartien(im: .festeFragen,
                                                           verlauf: verlauf), 1)
        XCTAssertEqual(KartenschrankRules.gespieltePartien(im: .aushang,
                                                           verlauf: verlauf), 1)
        // Unknown types count nowhere; an empty history counts zero.
        XCTAssertEqual(KartenschrankRules.gespieltePartien(im: .spielbuch,
                                                           verlauf: verlauf), 0)
        XCTAssertEqual(KartenschrankRules.gespieltePartien(im: .fernpartien,
                                                           verlauf: []), 0)
    }

    func testGespieltePartienFromServerAggregate() {
        // The stats variant (`GET /api/games/stats` perKind) applies the
        // SAME drawer filter as the list variant — whole-history counts,
        // unknown types count nowhere.
        let zaehlung = ["battleship": 40, "kniffel": 13, "rps": 2,
                        "quiz": 1, "wordle": 5, "poker": 9]
        XCTAssertEqual(KartenschrankRules.gespieltePartien(im: .fernpartien,
                                                           zaehlung: zaehlung), 53)
        XCTAssertEqual(KartenschrankRules.gespieltePartien(im: .amTisch,
                                                           zaehlung: zaehlung), 2)
        XCTAssertEqual(KartenschrankRules.gespieltePartien(im: .festeFragen,
                                                           zaehlung: zaehlung), 1)
        XCTAssertEqual(KartenschrankRules.gespieltePartien(im: .aushang,
                                                           zaehlung: zaehlung), 5)
        XCTAssertEqual(KartenschrankRules.gespieltePartien(im: .spielbuch,
                                                           zaehlung: zaehlung), 0)
        XCTAssertEqual(KartenschrankRules.gespieltePartien(im: .fernpartien,
                                                           zaehlung: [:]), 0)
        // Both variants agree on the same history.
        let verlauf = ["battleship", "battleship", "rps", "quiz"]
        var counts: [String: Int] = [:]
        for typ in verlauf { counts[typ, default: 0] += 1 }
        for fach in KartenschrankFach.allCases {
            XCTAssertEqual(
                KartenschrankRules.gespieltePartien(im: fach, verlauf: verlauf),
                KartenschrankRules.gespieltePartien(im: fach, zaehlung: counts))
        }
    }

    func testPunktzeileIsPureFormatting() {
        XCTAssertEqual(KartenschrankRules.punktzeile(titel: "Fernpartien", zahl: 34),
                       "Fernpartien ····· 34")
        XCTAssertEqual(KartenschrankRules.punktzeile(titel: "Am Tisch", zahl: 0),
                       "Am Tisch ····· 0")
    }

    // MARK: L10n latch — the dynamic card keys (games.card.*)

    /// Raw values of `GameKind`, parsed from the enum declaration in
    /// Core/Models.swift — same source scan as GameKindParityTests (the
    /// enum is app-only, not in the Linux target).
    private func gameKindCases() throws -> [String] {
        let models = Self.packageDir.appendingPathComponent("SoooDreamy/Core/Models.swift")
        let source = try String(contentsOf: models, encoding: .utf8)
        guard let start = source.range(of: "enum GameKind"),
              let end = source.range(of: "var id", range: start.upperBound..<source.endIndex) else {
            XCTFail("Core/Models.swift: could not locate the GameKind declaration")
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

    /// The hub builds `games.card.\(id).title` / `.teaser` at RUNTIME for
    /// every envelope, recent chip and the hero — an id shelved without
    /// its L10n pair would render raw keys in the cabinet. The latch set
    /// is DERIVED, never appended by hand (re-eval 2, Befund 13):
    /// drawer ids ∪ (alleZiele ∩ GameKind cases via source scan) — so a
    /// future GameKind-backed destination OUTSIDE the three drawers (the
    /// dailyquests pattern) joins the latch automatically instead of
    /// escaping a hardcoded list. Pattern: ZustellrundenLogicTests'
    /// titleKey latch.
    func testEveryDynamicCardKeyIsPinnedInGamesL10n() throws {
        let schrankIds = KartenschrankFach.schrank
            .flatMap { KartenschrankRules.ziele(im: $0) }
        let kindCases = try Set(gameKindCases())
        XCTAssertFalse(kindCases.isEmpty, "source scan found no GameKind cases")
        let ids = Set(schrankIds)
            .union(KartenschrankRules.alleZiele.intersection(kindCases))
        // The derivation must at least cover today's known non-drawer
        // GameKind card (the Aushang's dailyquests) — a broken scan would
        // otherwise silently shrink the latch.
        XCTAssertTrue(ids.contains("dailyquests"),
                      "derived latch lost the dailyquests card")
        for id in ids.sorted() {
            XCTAssertNotNil(GamesL10n.table["games.card.\(id).title"],
                            "games.card.\(id).title missing from GamesL10n")
            XCTAssertNotNil(GamesL10n.table["games.card.\(id).teaser"],
                            "games.card.\(id).teaser missing from GamesL10n")
        }
    }
}
