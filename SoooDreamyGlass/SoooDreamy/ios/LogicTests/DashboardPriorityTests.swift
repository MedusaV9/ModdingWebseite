import XCTest
@testable import SoooDreamyLogic

final class DashboardPriorityTests: XCTestCase {
    func testUrgentNeedPutsRitualsFirst() {
        let context = DashboardPriorityContext(
            hasOpenNeed: true,
            hasUnlockableCapsule: false,
            gamesAwaitingMe: 1,
            dailyOpen: true,
            hasUpcomingMoment: true
        )
        XCTAssertEqual(DashboardPriority.orderedGroups(context: context).first, .rituals)
    }

    func testSeveralWaitingGamesOutrankEvergreenGroups() {
        let context = DashboardPriorityContext(
            hasOpenNeed: false,
            hasUnlockableCapsule: false,
            gamesAwaitingMe: 3,
            dailyOpen: false,
            hasUpcomingMoment: false
        )
        XCTAssertEqual(DashboardPriority.orderedGroups(context: context).first, .games)
    }

    func testPinnedAndHiddenPreferencesAreDeterministic() {
        let context = DashboardPriorityContext(
            hasOpenNeed: true,
            hasUnlockableCapsule: true,
            gamesAwaitingMe: 9,
            dailyOpen: true,
            hasUpcomingMoment: true
        )
        XCTAssertEqual(
            DashboardPriority.orderedGroups(
                context: context,
                pinnedFirst: .moments,
                hidden: [.games]
            ),
            [.moments, .rituals]
        )
    }

    func testWhatsNewAppearsOncePerVersion() {
        XCTAssertTrue(WhatsNewGate.shouldPresent(currentVersion: "4.2.0", lastPresentedVersion: "4.1.0"))
        XCTAssertFalse(WhatsNewGate.shouldPresent(currentVersion: "4.2.0", lastPresentedVersion: "4.2.0"))
        XCTAssertFalse(WhatsNewGate.shouldPresent(currentVersion: "", lastPresentedVersion: nil))
    }

    // MARK: Hero slot + card budget (Dossier 23)
    //
    // Neubau N2 (conscious re-pin, never en passant): `DayPhase` became
    // `Zustellrunde` — morning → morgenpost, midday → tagespost, and the
    // old evening+night pair → nachtpost (17–05, identical hero behavior).
    // Round boundaries are pinned in ZustellrundenLogicTests.

    /// An unremarkable afternoon: my answer is in, nothing waits.
    private func calmContext() -> DashboardCardContext {
        DashboardCardContext(
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
    }

    // Conscious re-pin (re-eval №2, never en passant): the day LETTER is
    // ALWAYS the stamped hero of a paired screen — the round's check-in
    // stopped being a hero and became the FIRST dark delivery card below.

    func testDayLetterStaysHeroWhileTheMorningRitualWaitsBelow() {
        var context = calmContext()
        context.runde = .morgenpost
        context.morningCheckinDone = false
        context.myDailyAnswered = false
        // The stamped letter never yields the stage to the ritual …
        XCTAssertEqual(DashboardPriority.heroCard(context: context), .daily)
        // … which presses as the first dark card under the paper instead.
        XCTAssertEqual(DashboardPriority.layout(context: context).visible.first,
                       .checkin)
        context.morningCheckinDone = true
        XCTAssertEqual(DashboardPriority.heroCard(context: context), .daily)
        // The done ritual falls back into the ranked field.
        XCTAssertNotEqual(DashboardPriority.layout(context: context).visible.first,
                          .checkin)
    }

    func testOpenRoundRitualOutranksEvenAnOpenNeedInTheField() {
        var context = calmContext()
        context.runde = .morgenpost
        context.morningCheckinDone = false
        context.hasOpenNeed = true
        let layout = DashboardPriority.layout(context: context)
        XCTAssertEqual(layout.hero, .daily)
        // Ritual (1 100) over open need (1 000): the round's own call
        // presses hardest among the dark cards.
        XCTAssertEqual(Array(layout.visible.prefix(2)), [.checkin, .rituals])
    }

    func testOpenObligationBeatsRevealBeatsDeliveryRound() {
        var context = calmContext()
        context.runde = .nachtpost
        context.myDailyAnswered = false
        context.revealPending = true
        // My own missing answer comes first …
        XCTAssertEqual(DashboardPriority.heroCard(context: context), .daily)
        context.myDailyAnswered = true
        context.bothAnswered = true
        // … then the waiting reveal …
        XCTAssertEqual(DashboardPriority.heroCard(context: context), .daily)
        context.revealPending = false
        // … then the letter keeps the stage while the night ritual waits
        // below as the first dark card (re-eval №2 — an open check-in
        // under "Alles geteilt" would give the resting reward the lie) …
        XCTAssertEqual(DashboardPriority.heroCard(context: context), .daily)
        XCTAssertEqual(DashboardPriority.layout(context: context).visible.first,
                       .checkin)
        context.nightCheckinDone = true
        // … and finally the resting reward.
        XCTAssertEqual(DashboardPriority.heroCard(context: context), .resting)
    }

    func testRestingRequiresNothingWaiting() {
        var context = calmContext()
        context.bothAnswered = true
        XCTAssertEqual(DashboardPriority.heroCard(context: context), .resting)
        context.gamesAwaitingMe = 1
        XCTAssertEqual(DashboardPriority.heroCard(context: context), .daily)
        context.gamesAwaitingMe = 0
        context.hasOpenNeed = true
        XCTAssertEqual(DashboardPriority.heroCard(context: context), .daily)
    }

    func testLayoutKeepsTheHardBudget() {
        let layout = DashboardPriority.layout(context: calmContext())
        XCTAssertEqual(layout.visible.count, DashboardPriority.cardBudget)
        // Everything else is folded away, nothing is lost, nothing doubles.
        let all = [layout.hero] + layout.visible + layout.more
        XCTAssertEqual(Set(all).count, all.count, "no card may appear twice")
        XCTAssertFalse(layout.visible.contains(.resting))
        XCTAssertFalse(layout.more.contains(.resting))
    }

    func testOpenNeedPutsRitualsIntoTheVisibleBudget() {
        var context = calmContext()
        context.hasOpenNeed = true
        let layout = DashboardPriority.layout(context: context)
        XCTAssertEqual(layout.visible.first, .rituals)
    }

    func testPinnedGroupWinsAndHiddenGroupDisappears() {
        var context = calmContext()
        context.gamesAwaitingMe = 5
        let layout = DashboardPriority.layout(
            context: context,
            pinned: .moments,
            hidden: [.games]
        )
        XCTAssertEqual(layout.visible.first, .moments)
        XCTAssertFalse((layout.visible + layout.more).contains(.quest))
    }

    func testHiddenRitualsNeverLeaveACheckinHero() {
        var context = calmContext()
        context.runde = .morgenpost
        context.morningCheckinDone = false
        let layout = DashboardPriority.layout(context: context, hidden: [.rituals])
        XCTAssertEqual(layout.hero, .daily)
        XCTAssertTrue(layout.visible.allSatisfy { $0.group != .rituals })
        XCTAssertTrue(layout.more.allSatisfy { $0.group != .rituals })
    }

    // MARK: AX composition (re-eval №9)

    func testJubilaeumSortsBehindTheHeroOnlyAtAccessibilitySizes() {
        // At accessibility text sizes the grown header plus the banner ate
        // the whole first screen — the banner celebrates BEHIND the day
        // hero there; regular sizes keep it as the celebratory opener.
        XCTAssertTrue(DashboardPriority.jubilaeumHinterHero(isAccessibilitySize: true))
        XCTAssertFalse(DashboardPriority.jubilaeumHinterHero(isAccessibilitySize: false))
    }

    // MARK: First moment (fresh couples, FX-O #4)

    func testFirstMomentPendingDerivation() {
        // Fresh couple, nothing shared yet — the stage is on.
        XCTAssertTrue(DashboardPriority.firstMomentPending(
            isNewCouple: true, questDone: false,
            dailyStepDone: false, touchStepDone: false, myDailyAnswered: false))
        // ANY first shared thing retires the stage: daily step, touch step,
        // or the live answer typed before the quest event arrives.
        XCTAssertFalse(DashboardPriority.firstMomentPending(
            isNewCouple: true, questDone: false,
            dailyStepDone: true, touchStepDone: false, myDailyAnswered: false))
        XCTAssertFalse(DashboardPriority.firstMomentPending(
            isNewCouple: true, questDone: false,
            dailyStepDone: false, touchStepDone: true, myDailyAnswered: false))
        XCTAssertFalse(DashboardPriority.firstMomentPending(
            isNewCouple: true, questDone: false,
            dailyStepDone: false, touchStepDone: false, myDailyAnswered: true))
        // Established couples never see the welcome stage.
        XCTAssertFalse(DashboardPriority.firstMomentPending(
            isNewCouple: false, questDone: false,
            dailyStepDone: false, touchStepDone: false, myDailyAnswered: false))
        XCTAssertFalse(DashboardPriority.firstMomentPending(
            isNewCouple: true, questDone: true,
            dailyStepDone: false, touchStepDone: false, myDailyAnswered: false))
    }

    func testFirstMomentHeroWinsAndCarriesItsOwnCalls() {
        var context = calmContext()
        context.runde = .morgenpost
        context.morningCheckinDone = false
        context.myDailyAnswered = false
        context.firstMomentPending = true
        let layout = DashboardPriority.layout(context: context)
        // The stage outranks even the morning ritual …
        XCTAssertEqual(layout.hero, .firstMoment)
        // … and the daily/touches cards stay off the page: the stage IS
        // those two calls — repeating them would split the focus.
        let rest = layout.visible + layout.more
        XCTAssertFalse(rest.contains(.daily))
        XCTAssertFalse(rest.contains(.touches))
        XCTAssertFalse(rest.contains(.firstMoment))
        // Once the first moment happened, the normal rhythm returns: the
        // day letter takes the stage (re-eval №2), the morning ritual
        // becomes the first dark card below it.
        context.firstMomentPending = false
        let after = DashboardPriority.layout(context: context)
        XCTAssertEqual(after.hero, .daily)
        XCTAssertEqual(after.visible.first, .checkin)
    }

    func testFirstMomentNeverRanksBelowTheHero() {
        // firstMoment is hero-only — an established couple's layout must
        // never surface it in visible/more.
        let layout = DashboardPriority.layout(context: calmContext())
        XCTAssertFalse((layout.visible + layout.more).contains(.firstMoment))
    }

    // MARK: Two independent columns (iPad grid holes, FX-O #4)

    func testColumnSplitAlternatesWithoutLoss() {
        // Uniform weights (the default) degrade to the old alternating
        // split — the ranking stays readable left-to-right.
        let split = DashboardPriority.columnSplit([1, 2, 3, 4, 5])
        XCTAssertEqual(split.left, [1, 3, 5])
        XCTAssertEqual(split.right, [2, 4])
        let pair = DashboardPriority.columnSplit(["a", "b"])
        XCTAssertEqual(pair.left, ["a"])
        XCTAssertEqual(pair.right, ["b"])
        let empty = DashboardPriority.columnSplit([Int]())
        XCTAssertTrue(empty.left.isEmpty)
        XCTAssertTrue(empty.right.isEmpty)
    }

    // MARK: Height-weighted columns (FXC-4 #8)

    func testColumnSplitWeightedStacksLightCardsAgainstHeavyOnes() {
        // The rituals block (calibrated to weight 6 in round 3 — it renders
        // up to seven sub-cards) lands left — blind alternation would put
        // only every second light card right, carving holes. The weighted
        // split fills the right column until the heights meet.
        let cards: [DashboardCard] = [.rituals, .level, .hugQueue, .dateNight]
        let split = DashboardPriority.columnSplit(
            cards, weight: DashboardPriority.columnWeight)
        XCTAssertEqual(split.left, [.rituals])
        XCTAssertEqual(split.right, [.level, .hugQueue, .dateNight])
    }

    func testRitualsWeightIsCalibratedToItsRenderedHeight() {
        // FXD-2 #9: weight 3 promised a balanced page while the rendered
        // right column ended ~330 pt (≈3 small-card units) early — the
        // block's honest height class is 6 small-card units.
        XCTAssertEqual(DashboardPriority.columnWeight(.rituals), 6)
        XCTAssertEqual(DashboardPriority.columnWeight(.touches), 2)
        XCTAssertEqual(DashboardPriority.columnWeight(.level), 1)
    }

    func testColumnSplitWeightedHeightsStayBalanced() {
        // Greedy shortest-column property: whatever the card mix, the two
        // column heights never differ by more than one heaviest card — and
        // nothing is lost or doubled.
        let mixes: [[DashboardCard]] = [
            [.rituals, .touches, .daily, .level, .hugQueue, .moments],
            [.touches, .rituals, .checkin, .quest, .dateNight],
            [.rituals, .touches],
            [.level, .hugQueue, .moments, .seasonDoor],
        ]
        for mix in mixes {
            let split = DashboardPriority.columnSplit(
                mix, weight: DashboardPriority.columnWeight)
            XCTAssertEqual(split.left.count + split.right.count, mix.count)
            let leftHeight = split.left.map(DashboardPriority.columnWeight).reduce(0, +)
            let rightHeight = split.right.map(DashboardPriority.columnWeight).reduce(0, +)
            let heaviest = mix.map(DashboardPriority.columnWeight).max() ?? 1
            XCTAssertLessThanOrEqual(abs(leftHeight - rightHeight), heaviest,
                                     "unbalanced columns for \(mix)")
        }
    }

    // MARK: Balanced columns pull light fold cards up (FXD-2 #9)

    private func height(_ cards: [DashboardCard]) -> Int {
        cards.map(DashboardPriority.columnWeight).reduce(0, +)
    }

    func testBalancedColumnsPullLightMoreCardsIntoTheShortColumn() {
        // The eval scenario: the rituals mega-block (6) holds the left
        // column against touches+quest (3) — the ~330 pt hole. Light fold
        // cards move up IN RANK ORDER until the heights differ by ≤ 1.
        let balanced = DashboardPriority.balancedColumns(
            visible: [.rituals, .touches, .quest],
            more: [.checkin, .seasonDoor, .moments, .dateNight, .hugQueue, .level])
        XCTAssertEqual(balanced.left, [.rituals])
        XCTAssertEqual(balanced.right, [.touches, .quest, .checkin, .seasonDoor])
        XCTAssertEqual(balanced.more, [.moments, .dateNight, .hugQueue, .level])
        XCTAssertLessThanOrEqual(abs(height(balanced.left) - height(balanced.right)), 1)
    }

    func testBalancedColumnsLeaveAnAlreadyBalancedPageAlone() {
        // Heights differ by ≤ 1 → nothing is pulled, the fold stays whole.
        let balanced = DashboardPriority.balancedColumns(
            visible: [.touches, .daily, .quest],
            more: [.hugQueue, .level])
        XCTAssertEqual(balanced.left, [.touches, .quest])
        XCTAssertEqual(balanced.right, [.daily])
        XCTAssertEqual(balanced.more, [.hugQueue, .level])
    }

    func testBalancedColumnsSkipFoldCardsHeavierThanTheGap() {
        // Gap 4: the touch grid (weight 2) ranks first and fits; then the
        // level card (1) closes the gap to 1 and the pulling stops — a
        // folded card heavier than the remaining gap must never overshoot
        // past balanced.
        let balanced = DashboardPriority.balancedColumns(
            visible: [.rituals, .quest, .moments],
            more: [.touches, .level, .hugQueue])
        XCTAssertEqual(balanced.left, [.rituals])
        XCTAssertEqual(balanced.right.prefix(2), [.quest, .moments])
        XCTAssertLessThanOrEqual(abs(height(balanced.left) - height(balanced.right)), 1)
        // No card lost, none doubled.
        let all = balanced.left + balanced.right + balanced.more
        XCTAssertEqual(all.count, 6)
        XCTAssertEqual(Set(all).count, 6)
    }

    func testBalancedColumnsNeverLoseOrDoubleCards() {
        let mixes: [(visible: [DashboardCard], more: [DashboardCard])] = [
            ([.rituals, .touches, .quest], [.checkin, .level]),
            ([.rituals, .level, .hugQueue], []),
            ([.daily, .touches], [.rituals, .level, .moments]),
            ([], [.level]),
        ]
        for mix in mixes {
            let balanced = DashboardPriority.balancedColumns(visible: mix.visible,
                                                             more: mix.more)
            let all = balanced.left + balanced.right + balanced.more
            XCTAssertEqual(Set(all), Set(mix.visible + mix.more),
                           "cards lost or doubled for \(mix)")
            XCTAssertEqual(all.count, mix.visible.count + mix.more.count)
        }
    }

    // MARK: Season-door card rank (FXC-4 #9)

    func testReadySeasonDoorClimbsIntoTheVisibleBudget() {
        var context = calmContext()
        context.seasonDoorReady = true
        let layout = DashboardPriority.layout(context: context)
        XCTAssertTrue(layout.visible.contains(.seasonDoor),
                      "a ready door is a waiting surprise — never in the fold")
        // While it merely counts down, the card waits quietly in the fold.
        context.seasonDoorReady = false
        let waiting = DashboardPriority.layout(context: context)
        XCTAssertFalse(waiting.visible.contains(.seasonDoor))
        XCTAssertTrue(waiting.more.contains(.seasonDoor))
    }

    func testSeasonDoorRespectsTheHiddenRitualsGroup() {
        var context = calmContext()
        context.seasonDoorReady = true
        let layout = DashboardPriority.layout(context: context, hidden: [.rituals])
        XCTAssertFalse((layout.visible + layout.more).contains(.seasonDoor))
    }
}
