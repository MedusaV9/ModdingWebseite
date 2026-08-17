import Foundation
import XCTest
@testable import SoooDreamyLogic

final class NotificationDampingTests: XCTestCase {
    private var originalLanguage: AppLanguage!

    override func setUp() {
        super.setUp()
        originalLanguage = L10n.language
    }

    override func tearDown() {
        L10n.language = originalLanguage
        super.tearDown()
    }

    func testPriorityClassesMatchTheNotificationConcept() {
        XCTAssertEqual(NotificationPriorityClass.classify(kindRawValue: "touch"), .heartbeat)
        XCTAssertEqual(NotificationPriorityClass.classify(kindRawValue: "coupon"), .heartbeat)
        XCTAssertEqual(NotificationPriorityClass.classify(kindRawValue: "message"), .conversation)
        XCTAssertEqual(NotificationPriorityClass.classify(kindRawValue: "photo"), .conversation)
        XCTAssertEqual(NotificationPriorityClass.classify(kindRawValue: "dailyReveal"), .ambient)
        XCTAssertEqual(NotificationPriorityClass.classify(kindRawValue: "partnerOnline"), .ambient)
        // Unknown future kinds arrive as normal conversation, never louder.
        XCTAssertEqual(NotificationPriorityClass.classify(kindRawValue: "somethingNew"), .conversation)
    }

    func testQuietWindowFollowsTheSleepUntilDate() {
        let now = Date(timeIntervalSince1970: 100_000)
        XCTAssertFalse(SleepQuietHours.isQuiet(sleepUntil: nil, now: now))
        XCTAssertTrue(SleepQuietHours.isQuiet(sleepUntil: now.addingTimeInterval(3600), now: now))
        XCTAssertTrue(SleepQuietHours.isQuiet(sleepUntil: .distantFuture, now: now))
        XCTAssertFalse(SleepQuietHours.isQuiet(sleepUntil: now.addingTimeInterval(-1), now: now))
    }

    func testSummaryFiresAtWakeTimeOrNextMorning() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!

        var comps = DateComponents()
        comps.year = 2026; comps.month = 8; comps.day = 13
        comps.hour = 23; comps.minute = 30
        comps.timeZone = calendar.timeZone
        let lateEvening = calendar.date(from: comps)!

        // Announced wake time within a day → exactly then.
        let wakeAt = lateEvening.addingTimeInterval(8 * 3600)
        XCTAssertEqual(SleepQuietHours.summaryFireDate(sleepUntil: wakeAt, now: lateEvening,
                                                       calendar: calendar), wakeAt)

        // Open-ended sleep → next 08:00.
        let openEnded = SleepQuietHours.summaryFireDate(sleepUntil: .distantFuture,
                                                        now: lateEvening, calendar: calendar)
        let openComps = calendar.dateComponents([.day, .hour, .minute], from: openEnded)
        XCTAssertEqual(openComps.day, 14)
        XCTAssertEqual(openComps.hour, 8)
        XCTAssertEqual(openComps.minute, 0)

        // Early-morning sleep start (02:00) → 08:00 the SAME day.
        comps.day = 14; comps.hour = 2; comps.minute = 0
        let earlyMorning = calendar.date(from: comps)!
        let sameDay = SleepQuietHours.summaryFireDate(sleepUntil: nil,
                                                      now: earlyMorning, calendar: calendar)
        let sameComps = calendar.dateComponents([.day, .hour], from: sameDay)
        XCTAssertEqual(sameComps.day, 14)
        XCTAssertEqual(sameComps.hour, 8)
    }

    func testSummaryBodyListsCountsWarmlyInBothLanguages() {
        L10n.language = .de
        let de = SleepQuietHours.summaryBody(
            counts: ["message": 3, "touch": 1, "photo": 2], partnerName: "Mia")
        XCTAssertNotNil(de)
        XCTAssertTrue(de!.contains("3 Nachrichten"), de!)
        XCTAssertTrue(de!.contains("1 Berührung"), de!)
        XCTAssertTrue(de!.contains("2 Fotos"), de!)
        XCTAssertTrue(de!.contains("Mia"), de!)

        L10n.language = .en
        let en = SleepQuietHours.summaryBody(counts: ["message": 1], partnerName: "Ben")
        XCTAssertNotNil(en)
        XCTAssertTrue(en!.contains("1 message"), en!)
        XCTAssertTrue(en!.contains("Ben"), en!)

        // Nothing arrived → no summary notification at all.
        XCTAssertNil(SleepQuietHours.summaryBody(counts: [:], partnerName: "Mia"))
        XCTAssertNil(SleepQuietHours.summaryBody(counts: ["partnerOnline": 5],
                                                 partnerName: "Mia"),
                     "ambient-only nights don't earn a morning summary")
    }
}
