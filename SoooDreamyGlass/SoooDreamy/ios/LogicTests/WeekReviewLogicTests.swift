import XCTest
@testable import SoooDreamyLogic

/// „Eure Woche" (v7.0): the Swift ISO-week math must agree with
/// `server/src/weekreview.js` on every value both sides compute.
final class WeekReviewLogicTests: XCTestCase {

    func testDayNumberRoundTrip() {
        for key in ["1970-01-01", "2000-02-29", "2024-02-29", "2026-08-13", "1999-12-31"] {
            let parsed = WeekReviewLogic.parseDateKey(key)
            XCTAssertNotNil(parsed, key)
            let z = WeekReviewLogic.dayNumber(year: parsed!.year, month: parsed!.month, day: parsed!.day)
            XCTAssertEqual(WeekReviewLogic.dateKey(fromDayNumber: z), key)
        }
        XCTAssertEqual(WeekReviewLogic.dayNumber(year: 1970, month: 1, day: 1), 0)
        // 1970-01-01 was a Thursday → Monday-based weekday 3.
        XCTAssertEqual(WeekReviewLogic.mondayBasedWeekday(ofDayNumber: 0), 3)
    }

    func testWeekKeyMatchesServerFixtures() {
        // Fixtures asserted identically in server/test/weekreview.test.js.
        XCTAssertEqual(WeekReviewLogic.weekKey(forDateKey: "2026-01-01"), "2026-W01")
        XCTAssertEqual(WeekReviewLogic.weekKey(forDateKey: "2026-08-10"), "2026-W33")
        XCTAssertEqual(WeekReviewLogic.weekKey(forDateKey: "2026-08-16"), "2026-W33")
        XCTAssertEqual(WeekReviewLogic.weekKey(forDateKey: "2026-08-17"), "2026-W34")
        XCTAssertEqual(WeekReviewLogic.weekKey(forDateKey: "2027-01-01"), "2026-W53")
        XCTAssertEqual(WeekReviewLogic.weekKey(forDateKey: "2025-12-29"), "2026-W01")
        XCTAssertEqual(WeekReviewLogic.weekKey(forDateKey: "2024-12-31"), "2025-W01")
        XCTAssertNil(WeekReviewLogic.weekKey(forDateKey: "not-a-date"))
    }

    func testStartDateKeyInvertsWeekKey() {
        XCTAssertEqual(WeekReviewLogic.startDateKey(ofWeek: "2026-W33"), "2026-08-10")
        XCTAssertEqual(WeekReviewLogic.startDateKey(ofWeek: "2026-W01"), "2025-12-29")
        XCTAssertEqual(WeekReviewLogic.startDateKey(ofWeek: "2026-W53"), "2026-12-28")
        XCTAssertNil(WeekReviewLogic.startDateKey(ofWeek: "2025-W53")) // 2025 has 52 ISO weeks
        XCTAssertNil(WeekReviewLogic.startDateKey(ofWeek: "2026-W54"))
        XCTAssertNil(WeekReviewLogic.startDateKey(ofWeek: "garbage"))

        for key in ["2026-08-13", "2025-01-01", "2024-02-29", "2027-01-01"] {
            let week = WeekReviewLogic.weekKey(forDateKey: key)!
            let days = WeekReviewLogic.dateKeys(ofWeek: week)
            XCTAssertEqual(days.count, 7)
            XCTAssertTrue(days.contains(key), "\(key) must lie inside its own week \(week)")
            for day in days {
                XCTAssertEqual(WeekReviewLogic.weekKey(forDateKey: day), week)
            }
        }
    }

    func testPreviousAndLastCompletedWeek() {
        XCTAssertEqual(WeekReviewLogic.previousWeekKey("2026-W33"), "2026-W32")
        XCTAssertEqual(WeekReviewLogic.previousWeekKey("2026-W01"), "2025-W52")
        XCTAssertEqual(WeekReviewLogic.lastCompletedWeekKey(todayKey: "2026-08-13"), "2026-W32")
        XCTAssertEqual(WeekReviewLogic.lastCompletedWeekKey(todayKey: "2026-01-01"), "2025-W52")
        XCTAssertNil(WeekReviewLogic.lastCompletedWeekKey(todayKey: "bogus"))
    }

    func testStatCardsKeepRitualsAndHideEmptyActivity() {
        var stats = WeekReviewLogic.Stats()
        let empty = WeekReviewLogic.statCards(from: stats)
        // The three ritual counters always show, even at zero.
        XCTAssertEqual(empty.map(\.id), ["perfect", "daily", "checkin"])

        stats.messages = 12
        stats.photosAdded = 3
        stats.perfectDays = 2
        let cards = WeekReviewLogic.statCards(from: stats)
        XCTAssertEqual(cards.first?.id, "perfect")
        XCTAssertEqual(cards.first?.value, 2)
        XCTAssertTrue(cards.contains { $0.id == "messages" && $0.value == 12 })
        XCTAssertTrue(cards.contains { $0.id == "photos" && $0.value == 3 })
        XCTAssertFalse(cards.contains { $0.id == "videos" }, "zero-value activity cards hide")

        // Card ordering is stable and deterministic.
        XCTAssertEqual(cards.map(\.id), WeekReviewLogic.statCards(from: stats).map(\.id))
    }

    func testQuietWeekDetection() {
        XCTAssertTrue(WeekReviewLogic.isQuietWeek(WeekReviewLogic.Stats()))
        var stats = WeekReviewLogic.Stats()
        stats.touches = 1
        XCTAssertFalse(WeekReviewLogic.isQuietWeek(stats))
    }

    func testDramaturgyCardsLeadWithTheLoudestNumber() {
        var stats = WeekReviewLogic.Stats()
        stats.messages = 12
        stats.touches = 40
        stats.photosAdded = 12
        stats.perfectDays = 3
        let cards = WeekReviewLogic.dramaturgyCards(from: stats)
        // Rituals first (always, even at 0), then activity by size;
        // equal values keep their catalog order (messages before photos).
        XCTAssertEqual(cards.map(\.id), ["daily", "checkin", "touches", "messages", "photos"])
        // Perfect days are the hero card, never a grid tile here.
        XCTAssertFalse(cards.contains { $0.id == "perfect" })

        let quiet = WeekReviewLogic.dramaturgyCards(from: WeekReviewLogic.Stats())
        XCTAssertEqual(quiet.map(\.id), ["daily", "checkin"])
    }

    func testHighlightWindowCountdown() {
        // 2026-W33 = Aug 10–16; the window closes with Sunday Aug 23.
        XCTAssertEqual(WeekReviewLogic.highlightWindowDaysLeft(week: "2026-W33",
                                                               todayKey: "2026-08-10"), 14)
        XCTAssertEqual(WeekReviewLogic.highlightWindowDaysLeft(week: "2026-W33",
                                                               todayKey: "2026-08-16"), 8)
        XCTAssertEqual(WeekReviewLogic.highlightWindowDaysLeft(week: "2026-W33",
                                                               todayKey: "2026-08-23"), 1)
        XCTAssertNil(WeekReviewLogic.highlightWindowDaysLeft(week: "2026-W33",
                                                             todayKey: "2026-08-24"))
        XCTAssertNil(WeekReviewLogic.highlightWindowDaysLeft(week: "bogus",
                                                             todayKey: "2026-08-13"))
    }
}
