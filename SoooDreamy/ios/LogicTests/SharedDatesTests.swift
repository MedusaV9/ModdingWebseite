import XCTest
@testable import SoooDreamyLogic

/// Tests for the calendar-date helpers in `Shared/SharedBridge.swift` (`SharedDates`).
final class SharedDatesTests: XCTestCase {

    private var calendar: Calendar { SharedDates.calendar }

    /// Formats a Date as the "YYYY-MM-DD" key the helpers use.
    private func key(for date: Date) -> String {
        SharedDates.todayKey(date)
    }

    // MARK: - todayKey

    func testTodayKeyFormat() {
        let key = SharedDates.todayKey()
        XCTAssertNotNil(key.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression),
                        "todayKey \"\(key)\" must match YYYY-MM-DD")
    }

    func testTodayKeyForFixedDate() {
        var comps = DateComponents()
        comps.year = 2024; comps.month = 2; comps.day = 5
        let date = calendar.date(from: comps)!
        XCTAssertEqual(SharedDates.todayKey(date), "2024-02-05", "single-digit month/day must be zero-padded")
    }

    // MARK: - parse

    func testParseRoundTrips() {
        for key in ["2021-02-28", "2024-02-29", "1999-12-31", "2025-01-01"] {
            let parsed = SharedDates.parse(key)
            XCTAssertNotNil(parsed, "\"\(key)\" should parse")
            XCTAssertEqual(SharedDates.todayKey(parsed!), key, "parse → todayKey must round-trip")
        }
        let todayKey = SharedDates.todayKey()
        XCTAssertEqual(SharedDates.todayKey(SharedDates.parse(todayKey)!), todayKey)
    }

    func testParseRejectsGarbage() {
        XCTAssertNil(SharedDates.parse(nil))
        XCTAssertNil(SharedDates.parse("not-a-date"))
        XCTAssertNil(SharedDates.parse("2024-05"))
    }

    // MARK: - daysSince

    func testDaysSinceTenDaysAgo() {
        let now = Date()
        let tenDaysAgo = calendar.date(byAdding: .day, value: -10, to: now)!
        XCTAssertEqual(SharedDates.daysSince(key(for: tenDaysAgo), now: now), 10)
    }

    func testDaysSinceToday() {
        let now = Date()
        XCTAssertEqual(SharedDates.daysSince(key(for: now), now: now), 0)
    }

    func testDaysSinceNilForUnparseable() {
        XCTAssertNil(SharedDates.daysSince(nil))
        XCTAssertNil(SharedDates.daysSince("oops"))
    }

    // MARK: - daysUntil

    func testDaysUntilPastDateWithoutRepeatIsNegative() {
        let now = Date()
        let lastYear = calendar.date(byAdding: .day, value: -400, to: now)!
        let days = SharedDates.daysUntil(key(for: lastYear), repeatsYearly: false, now: now)
        XCTAssertNotNil(days)
        XCTAssertLessThan(days!, 0, "a past, non-repeating date must be negative days away")
    }

    func testDaysUntilRepeatsYearlyWrapsToNextOccurrence() {
        let now = Date()
        // An anniversary several years in the past.
        let past = calendar.date(byAdding: .year, value: -3, to: calendar.date(byAdding: .day, value: -100, to: now)!)!
        let days = SharedDates.daysUntil(key(for: past), repeatsYearly: true, now: now)
        XCTAssertNotNil(days)
        XCTAssertGreaterThanOrEqual(days!, 0, "yearly repeat must wrap into the future")
        XCTAssertLessThanOrEqual(days!, 366, "next yearly occurrence is at most a leap year away")
    }

    func testDaysUntilTodayIsZero() {
        let now = Date()
        XCTAssertEqual(SharedDates.daysUntil(key(for: now), repeatsYearly: false, now: now), 0)
        XCTAssertEqual(SharedDates.daysUntil(key(for: now), repeatsYearly: true, now: now), 0)
    }

    func testDaysUntilFutureDate() {
        let now = Date()
        let inAWeek = calendar.date(byAdding: .day, value: 7, to: now)!
        XCTAssertEqual(SharedDates.daysUntil(key(for: inAWeek), now: now), 7)
    }

    // MARK: - nextOccurrence

    func testNextOccurrenceRepeatsYearlyIsNotInThePast() {
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let past = calendar.date(byAdding: .day, value: -500, to: now)!
        let next = SharedDates.nextOccurrence(key(for: past), repeatsYearly: true, now: now)
        XCTAssertNotNil(next)
        XCTAssertGreaterThanOrEqual(next!, today,
                                    "next yearly occurrence of a past date must be today or later")
    }

    func testNextOccurrenceWithoutRepeatKeepsPastDate() {
        let now = Date()
        let past = calendar.date(byAdding: .day, value: -30, to: now)!
        let next = SharedDates.nextOccurrence(key(for: past), repeatsYearly: false, now: now)
        XCTAssertNotNil(next)
        XCTAssertLessThan(next!, calendar.startOfDay(for: now),
                          "non-repeating past dates stay in the past")
    }
}
