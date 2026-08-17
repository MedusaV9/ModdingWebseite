import XCTest
@testable import SoooDreamyLogic

final class LiveActivityLogicTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 3_000_000)

    // MARK: Honesty

    func testPulseStaleIntervalNeverClaimsOnlineForHours() {
        // B-19: the dossier demands 20–30 minutes instead of the old 8 h.
        XCTAssertGreaterThanOrEqual(ActivityHonesty.pulseStaleInterval, 20 * 60)
        XCTAssertLessThanOrEqual(ActivityHonesty.pulseStaleInterval, 30 * 60)
    }

    func testTransparencyFooterShowsForOldOrStaleData() {
        XCTAssertFalse(ActivityHonesty.showsLastRefresh(
            refreshedAt: now.addingTimeInterval(-5 * 60), isStale: false, now: now))
        XCTAssertTrue(ActivityHonesty.showsLastRefresh(
            refreshedAt: now.addingTimeInterval(-11 * 60), isStale: false, now: now))
        // Stale always shows the footer, however young the stamp claims to be.
        XCTAssertTrue(ActivityHonesty.showsLastRefresh(
            refreshedAt: now, isStale: true, now: now))
    }

    func testPartnerAsleepMirrorsLazyPresenceExpiry() {
        XCTAssertTrue(ActivityHonesty.partnerAsleep(mode: "sleep", until: nil, now: now))
        XCTAssertTrue(ActivityHonesty.partnerAsleep(
            mode: "sleep", until: now.addingTimeInterval(60), now: now))
        XCTAssertFalse(ActivityHonesty.partnerAsleep(
            mode: "sleep", until: now.addingTimeInterval(-1), now: now))
        XCTAssertFalse(ActivityHonesty.partnerAsleep(mode: "focus", until: nil, now: now))
        XCTAssertFalse(ActivityHonesty.partnerAsleep(mode: nil, until: nil, now: now))
    }

    // MARK: Update hygiene

    private struct FakeState: RefreshStampedState {
        var mood: String?
        var streak: Int
        var refreshedAt: Date
    }

    func testContentChangedIgnoresTheRefreshStamp() {
        let base = FakeState(mood: "🥰", streak: 4, refreshedAt: now)
        var stampOnly = base
        stampOnly.refreshedAt = now.addingTimeInterval(90)
        XCTAssertFalse(ActivityUpdateHygiene.contentChanged(base, stampOnly))

        var realChange = stampOnly
        realChange.streak = 5
        XCTAssertTrue(ActivityUpdateHygiene.contentChanged(base, realChange))
    }

    func testIsNewerGuardsTheAlertMoment() {
        XCTAssertFalse(ActivityUpdateHygiene.isNewer(nil, than: now))
        XCTAssertTrue(ActivityUpdateHygiene.isNewer(now, than: nil))
        XCTAssertTrue(ActivityUpdateHygiene.isNewer(now.addingTimeInterval(1), than: now))
        XCTAssertFalse(ActivityUpdateHygiene.isNewer(now, than: now))
    }

    func testAlertBudgetStaysSparse() {
        XCTAssertTrue(ActivityAlertBudget.mayAlert(alreadySent: 0))
        XCTAssertTrue(ActivityAlertBudget.mayAlert(alreadySent: 1))
        XCTAssertFalse(ActivityAlertBudget.mayAlert(
            alreadySent: ActivityAlertBudget.maxAlertsPerActivity))
    }

    func testShouldPushSkipsStampChurnButKeepsStalenessSliding() {
        let interval = ActivityHonesty.pulseStaleInterval
        // Real content change → always push.
        XCTAssertTrue(ActivityHonesty.shouldPush(
            contentChanged: true, staleDate: now.addingTimeInterval(interval),
            staleInterval: interval, now: now))
        // Stamp-only churn right after a push → skip.
        XCTAssertFalse(ActivityHonesty.shouldPush(
            contentChanged: false,
            staleDate: now.addingTimeInterval(interval - 60),
            staleInterval: interval, now: now))
        // …but once the last push is old, a keep-alive slides the window.
        XCTAssertTrue(ActivityHonesty.shouldPush(
            contentChanged: false,
            staleDate: now.addingTimeInterval(interval - ActivityHonesty.keepAliveInterval),
            staleInterval: interval, now: now))
        // No stale date on record → push to establish one.
        XCTAssertTrue(ActivityHonesty.shouldPush(
            contentChanged: false, staleDate: nil,
            staleInterval: interval, now: now))
    }

    // MARK: Date-night lifecycle

    func testAfterglowEndsTheEveningInsteadOfLingering() {
        let changed = now
        XCTAssertEqual(DateNightLifecycle.endDate(phaseChangedAt: changed),
                       changed.addingTimeInterval(DateNightLifecycle.afterglowLinger))
        // Afterglow stales at its own end; earlier phases get the 6 h grace
        // window after the planned start.
        let start = now.addingTimeInterval(-3600)
        XCTAssertEqual(
            DateNightLifecycle.staleDate(isAfterglow: true, startsAt: start,
                                         phaseChangedAt: changed),
            DateNightLifecycle.endDate(phaseChangedAt: changed))
        XCTAssertEqual(
            DateNightLifecycle.staleDate(isAfterglow: false, startsAt: start,
                                         phaseChangedAt: changed),
            start.addingTimeInterval(DateNightLifecycle.liveGrace))
    }

    func testAlertTextsNameThePartnerAndCarryBothLanguages() {
        let touch = ActivityAlertText.touchReceived(partnerName: "Lea",
                                                    emoji: "💓", language: "de")
        XCTAssertEqual(touch.title, "💓 Lea")
        XCTAssertTrue(touch.body.contains("Lea"))

        let fallback = ActivityAlertText.touchReceived(partnerName: nil,
                                                       emoji: "💓", language: "en")
        XCTAssertTrue(fallback.title.contains("Your partner"))

        let arrived = ActivityAlertText.countdownArrived(title: "Italien",
                                                         emoji: "✈️", language: "de")
        XCTAssertEqual(arrived.title, "✈️ Italien")
        XCTAssertTrue(arrived.body.contains("Moment"))

        let live = ActivityAlertText.dateNightLive(partnerName: "Lea", language: "en")
        XCTAssertTrue(live.body.contains("Lea"))
    }

    // MARK: Countdown lifecycle

    func testStaleDateSitsExactlyOnTheTarget() {
        // B-20: the stale transition IS the guaranteed celebration re-render.
        let target = now.addingTimeInterval(86_400)
        XCTAssertEqual(CountdownLifecycle.staleDate(target: target), target)
    }

    func testCelebrationTruth() {
        let future = now.addingTimeInterval(3600)
        let past = now.addingTimeInterval(-1)
        XCTAssertTrue(CountdownLifecycle.isCelebrating(
            celebrationFlag: true, target: future, isStale: false, now: now))
        XCTAssertTrue(CountdownLifecycle.isCelebrating(
            celebrationFlag: nil, target: past, isStale: false, now: now))
        XCTAssertFalse(CountdownLifecycle.isCelebrating(
            celebrationFlag: nil, target: future, isStale: false, now: now))
        // Stale alone (e.g. old couple context) must not fake a celebration.
        XCTAssertFalse(CountdownLifecycle.isCelebrating(
            celebrationFlag: nil, target: future, isStale: true, now: now))
    }

    func testCompactTickerOnlyNearTheMoment() {
        XCTAssertTrue(CountdownLifecycle.showsCompactTicker(
            target: now.addingTimeInterval(47 * 3600), liveTimer: true, now: now))
        XCTAssertFalse(CountdownLifecycle.showsCompactTicker(
            target: now.addingTimeInterval(12 * 86_400), liveTimer: true, now: now))
        XCTAssertFalse(CountdownLifecycle.showsCompactTicker(
            target: now.addingTimeInterval(3600), liveTimer: false, now: now))
        XCTAssertFalse(CountdownLifecycle.showsCompactTicker(
            target: now.addingTimeInterval(-1), liveTimer: true, now: now))
    }

    func testOrphanMatchingPrefersIdsAndSparesCelebrations() {
        let future = now.addingTimeInterval(86_400)
        let activities: [(eventId: String?, title: String, target: Date)] = [
            ("a", "Italien", future),                       // 0: id known → keep
            ("b", "Italien", future),                       // 1: id gone → orphan
            (nil, "Jahrestag", future),                     // 2: legacy, title known → keep
            (nil, "Umbenannt", future),                     // 3: legacy, title gone → orphan
            ("gone", "Feier", now.addingTimeInterval(-60)), // 4: due → celebration, never orphan
        ]
        XCTAssertEqual(
            CountdownLifecycle.orphanIndices(activities: activities,
                                             eventIds: ["a"],
                                             eventTitles: ["Italien", "Jahrestag"],
                                             now: now),
            [1, 3]
        )
    }

    // MARK: Celebration day + confetti

    func testCelebrationEntryDatesSkipThePast() {
        let target = now.addingTimeInterval(-5 * 3600)
        let dates = CelebrationDay.entryDates(target: target, now: now)
        XCTAssertEqual(dates.count, 4)   // +8/+12/+16/+20 h are still ahead
        XCTAssertTrue(dates.allSatisfy { $0 > now })
        XCTAssertEqual(CelebrationDay.slot(for: now, target: target), 1)
        XCTAssertEqual(CelebrationDay.slot(for: target.addingTimeInterval(-60),
                                           target: target), 0)
    }

    func testConfettiIsDeterministicAndWellFormed() {
        let seed = ConfettiLayout.seed(eventKey: "Italien|2026-09-01", slot: 2)
        let first = ConfettiLayout.pieces(seed: seed, count: 18)
        let second = ConfettiLayout.pieces(seed: seed, count: 18)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 18)
        for piece in first {
            XCTAssertTrue((0.0...1.0).contains(piece.x))
            XCTAssertTrue((0.0...1.0).contains(piece.y))
            XCTAssertTrue((0.6...1.4).contains(piece.scale))
            XCTAssertTrue((0...3).contains(piece.paletteIndex))
        }
        // A different slot lays the confetti differently (the "alive" trick).
        let otherSlot = ConfettiLayout.pieces(
            seed: ConfettiLayout.seed(eventKey: "Italien|2026-09-01", slot: 3),
            count: 18)
        XCTAssertNotEqual(first, otherSlot)
    }

    // MARK: Day summary + good-night outcome

    func testPulseDaySummaryBuildsFromWhatActuallyHappened() {
        XCTAssertEqual(
            PulseDaySummary.line(streak: 12, bothAnswered: true,
                                 lastTouchEmoji: "💓", language: "de"),
            "Heute berührt 💓 · Serie 12 · Frage beantwortet ✓ · Gute Nacht 🌙")
        XCTAssertEqual(
            PulseDaySummary.line(streak: 0, bothAnswered: false,
                                 lastTouchEmoji: nil, language: "en"),
            "Good night 🌙")
    }

    func testGoodNightDialogsAreHonest() {
        let all = GoodNightOutcome(presenceSet: true, pulseSent: true, checkinDone: true)
        XCTAssertTrue(all.dialog(partnerName: "Lea", language: "de").contains("Lea"))

        let none = GoodNightOutcome(presenceSet: false, pulseSent: false, checkinDone: false)
        XCTAssertTrue(none.dialog(partnerName: "Lea", language: "de").contains("Server"))

        let partial = GoodNightOutcome(presenceSet: true, pulseSent: false, checkinDone: true)
        let dialog = partial.dialog(partnerName: nil, language: "de")
        XCTAssertTrue(dialog.contains("Schlafmodus an"))
        XCTAssertTrue(dialog.contains("Abend-Check-in"))
        XCTAssertFalse(dialog.contains("Puls unterwegs"))
        XCTAssertTrue(dialog.contains("öffne die App"))
    }

    // MARK: Deep links + connection state

    func testActivityLinksMatchTheRouterHosts() {
        // Hosts routed by AppState.handleURL — the contract for every
        // widgetURL/Link the activities and widgets set.
        XCTAssertEqual(ActivityLink.pulse, "sooodreamy://tab/home")
        XCTAssertEqual(ActivityLink.countdown, "sooodreamy://events")
        XCTAssertEqual(ActivityLink.celebration, "sooodreamy://photos")
        XCTAssertEqual(ActivityLink.daily, "sooodreamy://daily")
        // No dedicated date-night route in handleURL yet — the honest target
        // is the dashboard, where the date-night card lives.
        XCTAssertEqual(ActivityLink.dateNight, "sooodreamy://tab/home")
        XCTAssertNotNil(ActivityLink.url(ActivityLink.pulse))
    }

    func testWidgetConnectionStateSeparatesSignOutFromFirstLaunch() {
        XCTAssertEqual(WidgetConnection.state(hasAppGroup: false,
                                              hasCredentials: false,
                                              hasSnapshot: false),
                       .appGroupMissing)
        XCTAssertEqual(WidgetConnection.state(hasAppGroup: true,
                                              hasCredentials: true,
                                              hasSnapshot: true),
                       .ready)
        XCTAssertEqual(WidgetConnection.state(hasAppGroup: true,
                                              hasCredentials: false,
                                              hasSnapshot: true),
                       .signedOut)
        XCTAssertEqual(WidgetConnection.state(hasAppGroup: true,
                                              hasCredentials: true,
                                              hasSnapshot: false),
                       .awaitingFirstOpen)
        XCTAssertEqual(WidgetConnection.state(hasAppGroup: true,
                                              hasCredentials: false,
                                              hasSnapshot: false),
                       .awaitingFirstOpen)
    }

    // MARK: Siri partner status brief (43#4)

    func testPartnerStatusLineIsDefinedEvenWithEmptyCache() {
        // Automations break on errors — the empty cache still gets a sentence.
        XCTAssertEqual(PartnerStatusLine.line(snapshot: nil, name: "Lea", german: true),
                       "Öffne SoooDreamy einmal, dann weiß ich mehr über Lea.")
        let empty = WidgetSnapshot()
        XCTAssertEqual(PartnerStatusLine.line(snapshot: empty, name: "Lea", german: false),
                       "Lea hasn't shared anything yet today. 💭")
    }

    func testPartnerStatusLineCombinesMoodEnergyAndPresence() {
        let now = Date()
        var snapshot = WidgetSnapshot()
        snapshot.partnerMood = "🥰"
        snapshot.partnerEnergyLevel = "red"
        snapshot.partnerPresenceMode = "sleep"
        snapshot.partnerPresenceUntil = now.addingTimeInterval(3600)
        XCTAssertEqual(
            PartnerStatusLine.line(snapshot: snapshot, name: "Lea", german: true, now: now),
            "Lea fühlt sich 🥰, Energie niedrig 🪫, schläft gerade 😴.")
    }

    func testPartnerStatusLineDropsExpiredPresenceAndFallsBackToOnline() {
        let now = Date()
        var snapshot = WidgetSnapshot()
        snapshot.partnerMood = "😊"
        snapshot.partnerPresenceMode = "focus"
        snapshot.partnerPresenceUntil = now.addingTimeInterval(-60)   // expired
        snapshot.partnerOnline = true
        let line = PartnerStatusLine.line(snapshot: snapshot, name: "Lea",
                                          german: false, now: now)
        XCTAssertFalse(line.contains("focus mode"))
        XCTAssertTrue(line.contains("online right now"))
    }
}
