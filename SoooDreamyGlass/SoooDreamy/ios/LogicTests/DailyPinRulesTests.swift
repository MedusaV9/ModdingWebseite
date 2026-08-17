import XCTest
@testable import SoooDreamyLogic

/// Schlussrunde 5: the server pins the daily question for ITS UTC day, but
/// clients render their LOCAL day — around midnight/timezone hops the two
/// disagree and a blindly applied pin would freeze yesterday's question
/// onto today's card/widget. `DailyPinRules.applicablePin` is the pure gate
/// both consumers (widget snapshot + app snapshot) share.
final class DailyPinRulesTests: XCTestCase {

    func testPinAppliesWhenTheServerDayMatchesTheLocalDay() {
        XCTAssertEqual(DailyPinRules.applicablePin(pinnedId: 410,
                                                   pinDateKey: "2026-08-15",
                                                   localDateKey: "2026-08-15"),
                       410)
    }

    func testYesterdaysPinNeverLeaksIntoTodaysCard() {
        // Just past local midnight the fetched snapshot still names the
        // old day — the pin must drop so the local derivation runs fresh.
        XCTAssertNil(DailyPinRules.applicablePin(pinnedId: 410,
                                                 pinDateKey: "2026-08-14",
                                                 localDateKey: "2026-08-15"))
        // The mirror case (server already on tomorrow, client not yet)
        // drops the pin just the same — date equality, not ordering.
        XCTAssertNil(DailyPinRules.applicablePin(pinnedId: 410,
                                                 pinDateKey: "2026-08-16",
                                                 localDateKey: "2026-08-15"))
    }

    func testNoPinStaysNoPin() {
        XCTAssertNil(DailyPinRules.applicablePin(pinnedId: nil,
                                                 pinDateKey: "2026-08-15",
                                                 localDateKey: "2026-08-15"))
    }

    func testOldServersWithoutAPinDayDisableThePinInsteadOfGuessing() {
        // Pre-Schlussrunde-5 servers send `dailyQuestionId` without
        // `dailyDateKey` — applying such a pin would risk exactly the
        // frozen-question bug this rule exists to prevent.
        XCTAssertNil(DailyPinRules.applicablePin(pinnedId: 410,
                                                 pinDateKey: nil,
                                                 localDateKey: "2026-08-15"))
    }
}
