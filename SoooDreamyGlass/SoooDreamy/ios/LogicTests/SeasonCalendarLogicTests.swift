import XCTest
@testable import SoooDreamyLogic

final class SeasonCalendarLogicTests: XCTestCase {
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func date(_ value: String, calendar: Calendar) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }

    func testDoorDatesStayOnLocalMidnightAcrossDSTAndLeapDay() {
        let berlin = calendar("Europe/Berlin")
        let dates = SeasonCalendarPlan.doorDates(
            startingAt: date("2028-02-28 18:30", calendar: berlin),
            count: 35,
            calendar: berlin
        )
        XCTAssertEqual(dates.count, 31)
        XCTAssertEqual(
            dates.prefix(3).map { berlin.dateComponents([.month, .day, .hour], from: $0) },
            [
                DateComponents(month: 2, day: 28, hour: 0),
                DateComponents(month: 2, day: 29, hour: 0),
                DateComponents(month: 3, day: 1, hour: 0),
            ]
        )
        XCTAssertTrue(dates.allSatisfy { berlin.component(.hour, from: $0) == 0 })
    }

    func testSeasonalFramesAreSuggestedNeverForced() {
        let utc = calendar("UTC")
        let anniversary = date("2020-02-14 12:00", calendar: utc)
        let events = SeasonalEvent.active(
            on: date("2028-02-14 09:00", calendar: utc),
            anniversary: anniversary,
            calendar: utc
        )
        XCTAssertEqual(events, [.valentine, .anniversary])
        XCTAssertEqual(SeasonalEvent.anniversary.suggestedWidgetSkin, "gold")
        XCTAssertEqual(
            SeasonalEvent.active(on: date("2028-10-31 09:00", calendar: utc), calendar: utc),
            [.halloween]
        )
    }

    func testDoorTemplatePackHasNinetyCompleteBilingualItems() {
        XCTAssertEqual(SeasonDoorTemplates.all.count, 102)
        XCTAssertEqual(Set(SeasonDoorTemplates.all.map(\.kind)), Set(SeasonDoorPayloadKind.allCases))
        let byKind = Dictionary(grouping: SeasonDoorTemplates.all, by: \.kind)
        for kind in SeasonDoorPayloadKind.allCases {
            XCTAssertGreaterThanOrEqual(byKind[kind]?.count ?? 0, 20,
                                        "kind \(kind) needs at least 20 templates")
        }
        XCTAssertEqual(Set(SeasonDoorTemplates.all.map(\.de)).count, SeasonDoorTemplates.all.count,
                       "German door templates must be unique")
        XCTAssertEqual(Set(SeasonDoorTemplates.all.map(\.en)).count, SeasonDoorTemplates.all.count,
                       "English door templates must be unique")
        for template in SeasonDoorTemplates.all {
            XCTAssertFalse(template.de.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(template.en.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertEqual(template.text(language: "de"), template.de)
            XCTAssertEqual(template.text(language: "en"), template.en)
        }
    }

    // MARK: Next-door dashboard visibility (FX-O #8)

    private func door(_ number: Int, unlockIn seconds: TimeInterval,
                      from now: Date, opened: Bool = false) -> SeasonDoorSummary {
        SeasonDoorSummary(number: number,
                          unlockAt: now.addingTimeInterval(seconds),
                          opened: opened)
    }

    func testNextDoorPrefersUnlockableOverCountdownAndSkipsOpened() {
        let now = Date()
        let feeds = [
            SeasonCalendarDoorFeed(forMe: true, doors: [
                door(1, unlockIn: -7_200, from: now, opened: true),   // already opened
                door(2, unlockIn: -3_600, from: now),                 // unlockable now
                door(3, unlockIn: 3_600, from: now),                  // tomorrow-ish
            ]),
        ]
        let next = SeasonDoorDashboard.nextDoor(in: feeds, now: now)
        XCTAssertEqual(next?.number, 2, "the ready door wins over any countdown")
        // Once door 2 is opened, the countdown door carries the card.
        let after = [
            SeasonCalendarDoorFeed(forMe: true, doors: [
                door(1, unlockIn: -7_200, from: now, opened: true),
                door(2, unlockIn: -3_600, from: now, opened: true),
                door(3, unlockIn: 3_600, from: now),
            ]),
        ]
        XCTAssertEqual(SeasonDoorDashboard.nextDoor(in: after, now: now)?.number, 3)
    }

    func testNextDoorIgnoresCalendarsForThePartner() {
        let now = Date()
        let feeds = [
            SeasonCalendarDoorFeed(forMe: false, doors: [door(1, unlockIn: -60, from: now)]),
        ]
        XCTAssertNil(SeasonDoorDashboard.nextDoor(in: feeds, now: now),
                     "the creator already knows what's inside — no teaser for them")
        XCTAssertNil(SeasonDoorDashboard.nextDoor(in: [], now: now))
    }

    func testDoorCountdownBands() {
        let now = Date()
        func countdown(_ seconds: TimeInterval) -> SeasonDoorCountdown {
            SeasonDoorDashboard.countdown(until: now.addingTimeInterval(seconds), now: now)
        }
        XCTAssertEqual(countdown(-1), .ready)
        XCTAssertEqual(countdown(0), .ready)
        XCTAssertEqual(countdown(30), .soon)
        XCTAssertEqual(countdown(15 * 60), .minutes(15))
        XCTAssertEqual(countdown(90 * 60), .hoursMinutes(1, 30))
        // 47 h stays hours+minutes; from 48 h whole days, nearest-rounded.
        XCTAssertEqual(countdown(47 * 3_600), .hoursMinutes(47, 0))
        XCTAssertEqual(countdown(49 * 3_600), .days(2))
        XCTAssertEqual(countdown(71 * 3_600), .days(3))
        XCTAssertEqual(countdown(5 * 86_400), .days(5))
    }

    func testReadyDoorLeadsTheVisibleCards() {
        // Neubau N2 re-pin: DayPhase.midday became Zustellrunde.tagespost.
        var context = DashboardCardContext(
            runde: .tagespost,
            morningCheckinDone: true,
            nightCheckinDone: false,
            myDailyAnswered: true,
            bothAnswered: false,
            revealPending: false,
            hasOpenNeed: false,
            gamesAwaitingMe: 0,
            hasMemoryToday: false,
            hasUpcomingMoment: false
        )
        // While nothing waits, the evergreen touches card leads the page …
        XCTAssertEqual(DashboardPriority.layout(context: context).visible.first, .touches)
        // … but a ready door leads as its OWN ranked card (FXC-4 #9) —
        // no longer buried as the seventh unit of the rituals block.
        context.seasonDoorReady = true
        let layout = DashboardPriority.layout(context: context)
        XCTAssertEqual(layout.visible.first, .seasonDoor)
        // An open need still outranks the door.
        context.hasOpenNeed = true
        XCTAssertGreaterThan(DashboardPriority.score(DashboardCard.rituals, context: context),
                             DashboardPriority.score(DashboardCard.seasonDoor, context: context))
    }
}
