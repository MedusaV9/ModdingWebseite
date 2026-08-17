import XCTest
@testable import SoooDreamyLogic

/// Pins the Film-Roulette → Wochenplan planner (v3.0.1, EVAL-3.0 P0-3):
/// which movie_match gets suggested as a banner and which day the 1-tap
/// slot lands on.
final class MovieNightLogicTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_754_800_000) // 2025-08-10 ~05:00 UTC

    private func match(_ id: String, title: String? = "La La Land", hoursAgo: Double) -> MovieNight.Match {
        MovieNight.Match(id: id, title: title, createdAt: now.addingTimeInterval(-hoursAgo * 3600))
    }

    // MARK: Banner suggestion

    func testNewestRecentMatchIsSuggested() {
        let suggestion = MovieNight.suggestion(
            matches: [match("old", hoursAgo: 30), match("new", hoursAgo: 2)],
            movieSlotCreations: [], dismissedIds: [], now: now)
        XCTAssertEqual(suggestion?.id, "new")
    }

    func testMatchesOlderThanAWeekAreNotSuggested() {
        let stale = match("stale", hoursAgo: Double(MovieNight.suggestionMaxAgeDays) * 24 + 1)
        XCTAssertNil(MovieNight.suggestion(matches: [stale], movieSlotCreations: [],
                                           dismissedIds: [], now: now))
    }

    func testDismissedMatchesAreSkippedInFavorOfOlderOnes() {
        let suggestion = MovieNight.suggestion(
            matches: [match("older", hoursAgo: 20), match("newest", hoursAgo: 1)],
            movieSlotCreations: [], dismissedIds: ["newest"], now: now)
        XCTAssertEqual(suggestion?.id, "older")
    }

    func testAMovieSlotCreatedAfterTheMatchCoversIt() {
        // The couple already planned a movie night AFTER matching → no banner.
        let covered = MovieNight.suggestion(
            matches: [match("m", hoursAgo: 5)],
            movieSlotCreations: [now.addingTimeInterval(-3600)],
            dismissedIds: [], now: now)
        XCTAssertNil(covered)

        // A movie slot from BEFORE the match does not cover the fresh match.
        let open = MovieNight.suggestion(
            matches: [match("m", hoursAgo: 5)],
            movieSlotCreations: [now.addingTimeInterval(-6 * 3600)],
            dismissedIds: [], now: now)
        XCTAssertEqual(open?.id, "m")
    }

    func testNoMatchesMeansNoSuggestion() {
        XCTAssertNil(MovieNight.suggestion(matches: [], movieSlotCreations: [],
                                           dismissedIds: [], now: now))
    }

    // MARK: 1-tap slot day

    func testFirstUpcomingOverlapDayWins() {
        let today = SharedDates.todayKey(now)
        let inTwoDays = SharedDates.todayKey(now.addingTimeInterval(2 * 86_400))
        let inFourDays = SharedDates.todayKey(now.addingTimeInterval(4 * 86_400))
        XCTAssertEqual(MovieNight.slotDateKey(overlapDateKeys: [inFourDays, inTwoDays], now: now),
                       inTwoDays)
        // Today's overlap counts (movie night tonight!), past days never do.
        XCTAssertEqual(MovieNight.slotDateKey(overlapDateKeys: ["2001-01-01", today], now: now), today)
    }

    func testWithoutOverlapTheSlotFallsOnTheNextSaturday() {
        let key = MovieNight.slotDateKey(overlapDateKeys: [], now: now)
        guard let date = SharedDates.parse(key) else { return XCTFail("unparseable dateKey \(key)") }
        XCTAssertEqual(SharedDates.calendar.component(.weekday, from: date), 7) // Saturday
        XCTAssertGreaterThanOrEqual(key, SharedDates.todayKey(now))
        // At most 6 days out.
        let days = SharedDates.calendar.dateComponents(
            [.day], from: SharedDates.calendar.startOfDay(for: now),
            to: SharedDates.calendar.startOfDay(for: date)).day ?? 99
        XCTAssertLessThanOrEqual(days, 6)
    }
}
