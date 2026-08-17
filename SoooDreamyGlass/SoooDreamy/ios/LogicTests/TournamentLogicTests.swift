import XCTest
@testable import SoooDreamyLogic

/// Pins the season aggregation — both devices must derive identical
/// tables and trophies from the same server history.
final class TournamentLogicTests: XCTestCase {
    private func match(_ type: String, _ month: String, _ mine: Int, _ theirs: Int) -> SeasonMatch {
        SeasonMatch(type: type, monthKey: month, mine: mine, theirs: theirs)
    }

    func testMonthKey() {
        XCTAssertEqual(Tournament.monthKey(of: "2026-08-08"), "2026-08")
        XCTAssertEqual(Tournament.monthKey(of: "2025-12-31"), "2025-12")
    }

    func testTablePointsWinsAndTies() {
        let table = Tournament.table(matches: [
            match("quiz", "2026-08", 5, 3),         // my win → 3:0
            match("kniffel", "2026-08", 120, 180),  // their win → 0:3
            match("battleship", "2026-08", 1, 1),   // tie → 1:1
            match("quiz", "2026-07", 9, 0),         // other month — ignored
        ], month: "2026-08")
        XCTAssertEqual(table.games, 3)
        XCTAssertEqual(table.myPoints, 4)
        XCTAssertEqual(table.theirPoints, 4)
        XCTAssertEqual(table.myWins, 1)
        XCTAssertEqual(table.theirWins, 1)
        XCTAssertEqual(table.ties, 1)
        XCTAssertEqual(table.leader, .tie)
        XCTAssertEqual(table.types, ["quiz", "kniffel", "battleship"])
    }

    func testTablesAreGroupedNewestFirst() {
        let tables = Tournament.tables(matches: [
            match("quiz", "2026-06", 1, 0),
            match("quiz", "2026-08", 1, 0),
            match("quiz", "2026-07", 0, 1),
        ])
        XCTAssertEqual(tables.map(\.monthKey), ["2026-08", "2026-07", "2026-06"])
    }

    func testTrophiesGoldAndShared() {
        let gold = Tournament.trophies(for: Tournament.table(
            matches: [match("quiz", "2026-08", 2, 1)], month: "2026-08"))
        XCTAssertEqual(gold.map(\.kind), [.goldMe])

        let silver = Tournament.trophies(for: Tournament.table(
            matches: [match("quiz", "2026-08", 0, 2)], month: "2026-08"))
        XCTAssertEqual(silver.map(\.kind), [.goldPartner])

        let shared = Tournament.trophies(for: Tournament.table(
            matches: [match("quiz", "2026-08", 1, 1)], month: "2026-08"))
        XCTAssertEqual(shared.map(\.kind), [.shared])

        XCTAssertTrue(Tournament.trophies(for: SeasonTable(monthKey: "2026-08")).isEmpty,
                      "no games → no trophies")
    }

    func testCoopTrophies() {
        // 15 matches across 6 types → marathon AND explorers on top of gold.
        let types = ["quiz", "kniffel", "battleship", "pictionary", "twotruths", "connectfour"]
        var matches: [SeasonMatch] = []
        for index in 0..<Tournament.marathonGames {
            matches.append(match(types[index % types.count], "2026-08", 1, 0))
        }
        let trophies = Tournament.trophies(for: Tournament.table(matches: matches,
                                                                 month: "2026-08"))
        XCTAssertEqual(trophies.map(\.kind), [.goldMe, .marathon, .explorers])
        XCTAssertTrue(SeasonTrophyKind.marathon.isCoop)
        XCTAssertFalse(SeasonTrophyKind.goldMe.isCoop)
    }
}
