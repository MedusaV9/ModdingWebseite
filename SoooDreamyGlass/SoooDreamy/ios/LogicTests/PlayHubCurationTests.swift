import XCTest
@testable import SoooDreamyLogic

final class PlayHubCurationTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    // MARK: - isPlayedGame (re-eval 2, Spieltisch Befund 8)
    // The VERBATIM mirror of `isPlayedGame` in server/src/game-rules.js
    // (pinned there by test/games_stats.test.js): a session was PLAYED when
    // it ended with recorded moves or a real result — cancelled/declined
    // lobbies never feed history, hero heuristic or register numbers.

    func testPlayedGameRequiresAnEndedState() {
        XCTAssertFalse(PlayHubCuration.isPlayedGame(state: "lobby", moveCount: 0, result: nil))
        XCTAssertFalse(PlayHubCuration.isPlayedGame(state: "active", moveCount: 4, result: nil))
    }

    func testEndedWithMovesOrRealResultIsPlayed() {
        // Moves alone are proof of play, even without a result object.
        XCTAssertTrue(PlayHubCuration.isPlayedGame(state: "ended", moveCount: 1, result: nil))
        // A real result without moves (e.g. questions36 completion) counts too.
        XCTAssertTrue(PlayHubCuration.isPlayedGame(
            state: "ended", moveCount: 0,
            result: .object(["completedBy": .string("m1")])))
    }

    func testCancelledAndDeclinedLobbiesAreNotPartien() {
        XCTAssertFalse(PlayHubCuration.isPlayedGame(
            state: "ended", moveCount: 0,
            result: .object(["cancelled": .bool(true), "by": .string("m1")])))
        XCTAssertFalse(PlayHubCuration.isPlayedGame(
            state: "ended", moveCount: 0,
            result: .object(["declined": .bool(true), "by": .string("m2")])))
        // Ended with neither moves nor result — nothing was played.
        XCTAssertFalse(PlayHubCuration.isPlayedGame(state: "ended", moveCount: 0, result: nil))
        XCTAssertFalse(PlayHubCuration.isPlayedGame(state: "ended", moveCount: 0, result: .null))
    }

    // Fix-Runde 3, Befund 5 — the administrative-result truth table,
    // wortgleich with server/test/games_stats.test.js:
    //   1. ended + moves               → played (even when invalidated)
    //   2. ended + real result         → played
    //   3. ended + cancelled/declined  → not played
    //   4. ended + invalidated, 0 Züge → not played
    //   5. ended + {} / kein Ergebnis  → not played
    func testZeroMoveInvalidationsAndEmptyResultsAreAdministrative() {
        let invalidated = JSONValue.object([
            "invalidated": .bool(true),
            "reason": .string("rules_migration"),
            "detail": .string("x"),
        ])
        // A lobby the rules migration had to invalidate — never played.
        XCTAssertFalse(PlayHubCuration.isPlayedGame(
            state: "ended", moveCount: 0, result: invalidated))
        // Invalidated AFTER real play: the moves prove the Partie.
        XCTAssertTrue(PlayHubCuration.isPlayedGame(
            state: "ended", moveCount: 1, result: invalidated))
        // An empty `{}` result without moves carries no outcome.
        XCTAssertFalse(PlayHubCuration.isPlayedGame(
            state: "ended", moveCount: 0, result: .object([:])))
    }

    // MARK: - Spiele-Bilanz register number (Fix4 Befund 4)

    func testBilanzPartienCountsVerdictsNotTotal() {
        // The register row must bind decided + draws — the destination
        // (GamesRecordView) filters scoreless rounds, so binding a total
        // that includes them read „1" over „Noch keine Spiele".
        XCTAssertEqual(PlayHubCuration.bilanzPartien(decided: 3, draws: 2), 5)
        // One PLAYED but scoreless round: total would say 1, the Bilanz
        // stays honest at 0 — exactly the mismatch of the Befund.
        XCTAssertEqual(PlayHubCuration.bilanzPartien(decided: 0, draws: 0), 0)
    }

    func testNeverPlayedGameWinsDiscoveryReason() {
        let pick = PlayHubCuration.recommendation(
            candidates: ["quiz", "gomoku"],
            history: ["quiz": PlayHistoryEntry(lastPlayed: daysAgo(10), playCount: 5)],
            hour: 12, now: now, dateKey: "2023-11-14", playedThisSeason: false)
        XCTAssertEqual(pick?.gameId, "gomoku")
        XCTAssertEqual(pick?.reasonKey, "games.hub.hero.reason.discover")
    }

    // MARK: - Grounded history (Fix-Runde 3, Befund 8a)

    func testGroundedHistoryOverrulesTheListPage() {
        // "gomoku" was played 60 times, but every round fell off the
        // 50-item curation page — only the aggregate remembers it.
        let list = ["quiz": PlayHistoryEntry(lastPlayed: daysAgo(10), playCount: 5)]
        let grounded = PlayHubCuration.groundedHistory(
            list, aggregate: ["gomoku": 60, "quiz": 12, "dame": 0])
        // The aggregate-only game exists now (no date — long ago).
        XCTAssertEqual(grounded["gomoku"]?.playCount, 60)
        XCTAssertNil(grounded["gomoku"]?.lastPlayed)
        // Larger truth wins; the list's date stays.
        XCTAssertEqual(grounded["quiz"]?.playCount, 12)
        XCTAssertEqual(grounded["quiz"]?.lastPlayed, daysAgo(10))
        // Zero counts create no phantom entries.
        XCTAssertNil(grounded["dame"])
        // Pre-stats servers (nil aggregate) change nothing.
        XCTAssertEqual(PlayHubCuration.groundedHistory(list, aggregate: nil), list)
    }

    func testGroundedHistoryKeepsTheHeroHonestAboutNeverPlayed() {
        // The list page forgot gomoku entirely — without grounding, the
        // hero would recommend it as "Noch nie gespielt" (+30 discover).
        let history = PlayHubCuration.groundedHistory(
            ["quiz": PlayHistoryEntry(lastPlayed: daysAgo(10), playCount: 5)],
            aggregate: ["gomoku": 60])
        let pick = PlayHubCuration.recommendation(
            candidates: ["quiz", "gomoku"], history: history,
            hour: 12, now: now, dateKey: "2023-11-14", playedThisSeason: false)
        XCTAssertNotEqual(pick?.reasonKey, "games.hub.hero.reason.discover")
    }

    func testRestingFavoriteResurfaces() {
        let pick = PlayHubCuration.recommendation(
            candidates: ["quiz", "kniffel"],
            history: [
                "quiz": PlayHistoryEntry(lastPlayed: daysAgo(10), playCount: 5),
                "kniffel": PlayHistoryEntry(lastPlayed: daysAgo(1), playCount: 2),
            ],
            hour: 12, now: now, dateKey: "2023-11-14", playedThisSeason: false)
        XCTAssertEqual(pick?.gameId, "quiz")
        XCTAssertEqual(pick?.reasonKey, "games.hub.hero.reason.favorite")
    }

    func testEveningPrefersCozyConversationGames() {
        let history = [
            "questions36": PlayHistoryEntry(lastPlayed: daysAgo(5), playCount: 1),
            "quizduel": PlayHistoryEntry(lastPlayed: daysAgo(5), playCount: 1),
        ]
        let evening = PlayHubCuration.recommendation(
            candidates: ["questions36", "quizduel"], history: history,
            hour: 20, now: now, dateKey: "2023-11-14", playedThisSeason: false)
        XCTAssertEqual(evening?.gameId, "questions36")
        XCTAssertEqual(evening?.reasonKey, "games.hub.hero.reason.evening")
        let midday = PlayHubCuration.recommendation(
            candidates: ["questions36", "quizduel"], history: history,
            hour: 13, now: now, dateKey: "2023-11-14", playedThisSeason: false)
        XCTAssertEqual(midday?.gameId, "quizduel")
        XCTAssertEqual(midday?.reasonKey, "games.hub.hero.reason.quick")
    }

    func testRecentlyPlayedGamesAreDemotedForVariety() {
        // Both candidates were played yesterday — no positive pick remains.
        let pick = PlayHubCuration.recommendation(
            candidates: ["quiz", "kniffel"],
            history: [
                "quiz": PlayHistoryEntry(lastPlayed: daysAgo(1), playCount: 5),
                "kniffel": PlayHistoryEntry(lastPlayed: daysAgo(1), playCount: 5),
            ],
            hour: 12, now: now, dateKey: "2023-11-14", playedThisSeason: false)
        XCTAssertNil(pick)
    }

    func testSeasonParticipationBoostsSeasonGames() {
        let history = [
            "dame": PlayHistoryEntry(lastPlayed: daysAgo(5), playCount: 1),
            "truthordare": PlayHistoryEntry(lastPlayed: daysAgo(5), playCount: 1),
        ]
        let pick = PlayHubCuration.recommendation(
            candidates: ["dame", "truthordare"], history: history,
            hour: 13, now: now, dateKey: "2023-11-14", playedThisSeason: true)
        XCTAssertEqual(pick?.gameId, "dame")
        XCTAssertEqual(pick?.reasonKey, "games.hub.hero.reason.season")
    }

    func testRecommendationIsDeterministicPerDay() {
        let first = PlayHubCuration.recommendation(
            candidates: ["dame", "gomoku", "mancala"], history: [:],
            hour: 20, now: now, dateKey: "2023-11-14", playedThisSeason: false)
        let second = PlayHubCuration.recommendation(
            candidates: ["dame", "gomoku", "mancala"], history: [:],
            hour: 20, now: now, dateKey: "2023-11-14", playedThisSeason: false)
        XCTAssertEqual(first, second)
        XCTAssertNotNil(first)
    }

    func testRecentlyPlayedIsUniqueNewestFirstAndCapped() {
        let records: [(gameId: String, endedAt: Date)] = [
            ("quiz", daysAgo(3)), ("dame", daysAgo(1)),
            ("quiz", daysAgo(0.5)), ("kniffel", daysAgo(2)),
        ]
        XCTAssertEqual(PlayHubCuration.recentlyPlayed(records: records),
                       ["quiz", "dame", "kniffel"])
        XCTAssertEqual(PlayHubCuration.recentlyPlayed(records: records, limit: 2),
                       ["quiz", "dame"])
    }

    // MARK: - Running-series momentum (FXC-3, S3)

    func testRunningSeriesSurfacesAnOpenBestOf() {
        // 1:1 after two decided games — the classic "next round decides".
        let series = PlayHubCuration.runningSeries(results: [
            SeriesResult(gameId: "gomoku", mine: 3, theirs: 1, endedAt: daysAgo(2)),
            SeriesResult(gameId: "gomoku", mine: 0, theirs: 2, endedAt: daysAgo(1)),
        ])
        XCTAssertEqual(series, SeriesMomentum(gameId: "gomoku", myWins: 1, theirWins: 1))
    }

    func testRunningSeriesNeedsAtLeastTwoDecidedGames() {
        XCTAssertNil(PlayHubCuration.runningSeries(results: [
            SeriesResult(gameId: "dame", mine: 2, theirs: 0, endedAt: daysAgo(1)),
        ]))
        // Ties are not decided games — two draws still leave no series.
        XCTAssertNil(PlayHubCuration.runningSeries(results: [
            SeriesResult(gameId: "dame", mine: 1, theirs: 1, endedAt: daysAgo(2)),
            SeriesResult(gameId: "dame", mine: 2, theirs: 2, endedAt: daysAgo(1)),
        ]))
    }

    func testRunawaySeriesIsNotNudged() {
        // 3:0 is decided momentum, not an open rivalry — no nudge.
        XCTAssertNil(PlayHubCuration.runningSeries(results: [
            SeriesResult(gameId: "reversi", mine: 2, theirs: 0, endedAt: daysAgo(3)),
            SeriesResult(gameId: "reversi", mine: 5, theirs: 1, endedAt: daysAgo(2)),
            SeriesResult(gameId: "reversi", mine: 4, theirs: 2, endedAt: daysAgo(1)),
        ]))
    }

    func testMostRecentlyPlayedOpenSeriesCarriesTheMomentum() {
        let series = PlayHubCuration.runningSeries(results: [
            // Open 1:1 in dame, last played 5 days ago…
            SeriesResult(gameId: "dame", mine: 2, theirs: 0, endedAt: daysAgo(6)),
            SeriesResult(gameId: "dame", mine: 0, theirs: 3, endedAt: daysAgo(5)),
            // …and an open 2:1 in mancala, played yesterday — mancala wins.
            SeriesResult(gameId: "mancala", mine: 4, theirs: 2, endedAt: daysAgo(3)),
            SeriesResult(gameId: "mancala", mine: 1, theirs: 5, endedAt: daysAgo(2)),
            SeriesResult(gameId: "mancala", mine: 3, theirs: 0, endedAt: daysAgo(1)),
        ])
        XCTAssertEqual(series, SeriesMomentum(gameId: "mancala", myWins: 2, theirWins: 1))
    }
}
