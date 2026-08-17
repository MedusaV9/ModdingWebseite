import XCTest

@testable import SoooDreamyLogic

/// v3.0 season themes (Agent C): calendar mapping + preference resolution.
final class SeasonLogicTests: XCTestCase {
    private func date(month: Int, day: Int = 15) -> Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = month
        comps.day = day
        comps.hour = 12
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: comps)!
    }

    func testMeteorologicalSeasonBoundaries() {
        XCTAssertEqual(Season.current(for: date(month: 1)), .winter)
        XCTAssertEqual(Season.current(for: date(month: 2)), .winter)
        XCTAssertEqual(Season.current(for: date(month: 3, day: 1)), .spring)
        XCTAssertEqual(Season.current(for: date(month: 5, day: 31)), .spring)
        XCTAssertEqual(Season.current(for: date(month: 6, day: 1)), .summer)
        XCTAssertEqual(Season.current(for: date(month: 8, day: 31)), .summer)
        XCTAssertEqual(Season.current(for: date(month: 9, day: 1)), .autumn)
        XCTAssertEqual(Season.current(for: date(month: 11, day: 30)), .autumn)
        XCTAssertEqual(Season.current(for: date(month: 12, day: 1)), .winter)
    }

    func testPreferenceResolution() {
        let july = date(month: 7)
        XCTAssertNil(SeasonPreference.off.resolved(for: july))
        XCTAssertEqual(SeasonPreference.auto.resolved(for: july), .summer)
        XCTAssertEqual(SeasonPreference.auto.resolved(for: july, hemisphere: .southern), .winter)
        XCTAssertEqual(SeasonPreference.winter.resolved(for: july), .winter)
        XCTAssertEqual(SeasonPreference.spring.resolved(for: july), .spring)
    }

    func testSouthernHemisphereShiftsEverySeasonBySixMonths() {
        XCTAssertEqual(Season.current(for: date(month: 1), hemisphere: .southern), .summer)
        XCTAssertEqual(Season.current(for: date(month: 4), hemisphere: .southern), .autumn)
        XCTAssertEqual(Season.current(for: date(month: 7), hemisphere: .southern), .winter)
        XCTAssertEqual(Season.current(for: date(month: 10), hemisphere: .southern), .spring)
    }

    func testEverySeasonHasParticlesAndDistinctAccent() {
        var accents = Set<String>()
        for season in Season.allCases {
            XCTAssertFalse(season.particles.isEmpty, "\(season) needs particle motifs")
            XCTAssertEqual(season.accentHex.count, 6, "\(season) accent must be RRGGBB")
            accents.insert(season.accentHex)
        }
        XCTAssertEqual(accents.count, Season.allCases.count, "accents must be distinct")
    }

    func testPreferenceRoundTripsThroughRawValue() {
        for pref in SeasonPreference.allCases {
            XCTAssertEqual(SeasonPreference(rawValue: pref.rawValue), pref)
        }
        // The stored-preference fallback path: unknown string → nil → caller
        // defaults to .auto.
        XCTAssertNil(SeasonPreference(rawValue: "solstice"))
    }
}
