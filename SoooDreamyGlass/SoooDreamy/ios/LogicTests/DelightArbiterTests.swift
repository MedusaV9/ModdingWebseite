import XCTest
@testable import SoooDreamyLogic

/// The app-wide ceremony arbiter: ONE big budget for level-ups, badges,
/// streaks, jackpots, seasons AND games (GameDelightRules delegates here),
/// degradation instead of silence, and the coalesce window that bundles
/// simultaneous events into one ceremony.
final class DelightArbiterTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_900_000_000)

    // MARK: Requested intensities

    func testRequestedIntensityMatrix() {
        XCTAssertEqual(DelightArbiter.requestedIntensity(for: .levelUp), .epic)
        XCTAssertEqual(DelightArbiter.requestedIntensity(for: .secretBadge), .epic)
        XCTAssertEqual(DelightArbiter.requestedIntensity(for: .streakMilestone), .epic)
        XCTAssertEqual(DelightArbiter.requestedIntensity(for: .revealJackpot), .epic)
        XCTAssertEqual(DelightArbiter.requestedIntensity(for: .seasonMilestone), .epic)
        XCTAssertEqual(DelightArbiter.requestedIntensity(for: .gameMatchWon), .epic)
        XCTAssertEqual(DelightArbiter.requestedIntensity(for: .capsuleOpened), .epic)
        XCTAssertEqual(DelightArbiter.requestedIntensity(for: .goalCompleted), .epic)
        // Regular badges are medium BY DESIGN — they never touch the budget.
        XCTAssertEqual(DelightArbiter.requestedIntensity(for: .badge), .medium)
    }

    // MARK: Budget — two bigs, then degradation (never silence)

    func testBudgetGrantsTwoBigsThenDegradesToMedium() {
        var ledger = DelightLedger()
        let first = DelightArbiter.grant(.levelUp, ledger: ledger, now: t0)
        XCTAssertEqual(first.intensity, .epic)
        ledger = first.ledger

        let second = DelightArbiter.grant(.revealJackpot, ledger: ledger,
                                          now: t0.addingTimeInterval(60))
        XCTAssertEqual(second.intensity, .epic)
        ledger = second.ledger

        // Third big inside the window: degraded, NOT silenced.
        let third = DelightArbiter.grant(.streakMilestone, ledger: ledger,
                                         now: t0.addingTimeInterval(120))
        XCTAssertEqual(third.intensity, .medium)
        // A degraded ceremony consumes no budget.
        XCTAssertEqual(third.ledger.bigMoments.count, 2)
    }

    func testRegularBadgeNeverTouchesTheBudget() {
        let granted = DelightArbiter.grant(.badge, ledger: DelightLedger(), now: t0)
        XCTAssertEqual(granted.intensity, .medium)
        XCTAssertTrue(granted.ledger.bigMoments.isEmpty)
    }

    func testBudgetRecoversAfterTheWindow() {
        var ledger = DelightLedger()
        ledger = DelightArbiter.grant(.levelUp, ledger: ledger, now: t0).ledger
        ledger = DelightArbiter.grant(.secretBadge, ledger: ledger,
                                      now: t0.addingTimeInterval(30)).ledger
        let later = t0.addingTimeInterval(DelightArbiter.bigWindow + 31)
        let next = DelightArbiter.grant(.levelUp, ledger: ledger, now: later)
        XCTAssertEqual(next.intensity, .epic)
        XCTAssertEqual(next.ledger.bigMoments.count, 1)
    }

    func testPruningDropsFutureAndExpiredEntries() {
        let ledger = DelightLedger(bigMoments: [
            t0.addingTimeInterval(3600),                        // future (clock set back)
            t0.addingTimeInterval(-DelightArbiter.bigWindow),   // expired
        ])
        let granted = DelightArbiter.grant(.levelUp, ledger: ledger, now: t0)
        XCTAssertEqual(granted.intensity, .epic)
        XCTAssertEqual(granted.ledger.bigMoments, [t0])
    }

    // MARK: Games and app moments spend from the SAME purse

    func testGameGrantsAndAppGrantsShareOneBudget() {
        var ledger = DelightLedger()
        // A match win (via the games layer) …
        let match = GameDelightRules.grant(event: .matchWon, ledger: ledger, now: t0)
        XCTAssertEqual(match.tier, .big)
        ledger = match.ledger
        // … and a level-up spend big slots 1 and 2 …
        let level = DelightArbiter.grant(.levelUp, ledger: ledger,
                                         now: t0.addingTimeInterval(60))
        XCTAssertEqual(level.intensity, .epic)
        ledger = level.ledger
        // … so the next match win degrades to normal, and the next
        // jackpot to medium — one shared window.
        let secondMatch = GameDelightRules.grant(event: .matchWon, ledger: ledger,
                                                 now: t0.addingTimeInterval(120))
        XCTAssertEqual(secondMatch.tier, .normal)
        let jackpot = DelightArbiter.grant(.revealJackpot, ledger: ledger,
                                           now: t0.addingTimeInterval(180))
        XCTAssertEqual(jackpot.intensity, .medium)
    }

    func testGameLedgerTypeStaysCompatible() {
        // GameCeremonyLedger is the same Codable shape (typealias) — the
        // persisted games ledger keeps decoding.
        let ledger = GameCeremonyLedger(bigMoments: [t0])
        let data = try? JSONEncoder().encode(ledger)
        XCTAssertNotNil(data)
        let decoded = data.flatMap { try? JSONDecoder().decode(DelightLedger.self, from: $0) }
        XCTAssertEqual(decoded, ledger)
    }

    // MARK: Coalescing — simultaneous events become ONE ceremony

    func testCoalesceWindowBundlesOnlyTrulySimultaneousEvents() {
        XCTAssertFalse(DelightArbiter.shouldCoalesce(lastPresentedAt: nil, next: t0))
        XCTAssertTrue(DelightArbiter.shouldCoalesce(lastPresentedAt: t0, next: t0))
        XCTAssertTrue(DelightArbiter.shouldCoalesce(
            lastPresentedAt: t0,
            next: t0.addingTimeInterval(DelightArbiter.coalesceWindow - 0.01)))
        XCTAssertFalse(DelightArbiter.shouldCoalesce(
            lastPresentedAt: t0,
            next: t0.addingTimeInterval(DelightArbiter.coalesceWindow)))
        // Clock weirdness: an event "before" the presentation never joins.
        XCTAssertFalse(DelightArbiter.shouldCoalesce(
            lastPresentedAt: t0, next: t0.addingTimeInterval(-1)))
    }

    // MARK: Persisted runtime ledger

    @MainActor
    func testStoreRoundTripsAndAppliesTheBudget() async throws {
        let suite = "delight.arbiter.tests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.removeObject(forKey: DelightArbiterStore.defaultsKey)

        XCTAssertEqual(DelightArbiterStore.load(defaults: defaults), DelightLedger())
        XCTAssertEqual(DelightArbiterStore.request(.levelUp, now: t0, defaults: defaults), .epic)
        XCTAssertEqual(DelightArbiterStore.request(.revealJackpot,
                                                   now: t0.addingTimeInterval(1),
                                                   defaults: defaults), .epic)
        // Third within the window: the persisted ledger degrades it.
        XCTAssertEqual(DelightArbiterStore.request(.secretBadge,
                                                   now: t0.addingTimeInterval(2),
                                                   defaults: defaults), .medium)
        XCTAssertEqual(DelightArbiterStore.load(defaults: defaults).bigMoments.count, 2)
    }

    /// EVAL repro (runtime, not rules): GameEndCelebration used to keep a
    /// SEPARATE in-memory ledger, so a game epic never actually spent from
    /// the app purse. Now both request paths hit the ONE persisted store.
    @MainActor
    func testRuntimeStoreSharesOneBudgetAcrossAppAndGameEpics() async throws {
        let suite = "delight.arbiter.tests.mixed"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.removeObject(forKey: DelightArbiterStore.defaultsKey)

        // A game match win spends big slot 1 …
        XCTAssertEqual(DelightArbiterStore.requestGame(.matchWon, now: t0,
                                                       defaults: defaults), .big)
        // … a level-up spends slot 2 …
        XCTAssertEqual(DelightArbiterStore.request(.levelUp,
                                                   now: t0.addingTimeInterval(30),
                                                   defaults: defaults), .epic)
        // … so the NEXT game win degrades to normal and the next app epic
        // (capsule opening) to medium: one purse, no side ledger.
        XCTAssertEqual(DelightArbiterStore.requestGame(.matchWon,
                                                       now: t0.addingTimeInterval(60),
                                                       defaults: defaults), .normal)
        XCTAssertEqual(DelightArbiterStore.request(.capsuleOpened,
                                                   now: t0.addingTimeInterval(90),
                                                   defaults: defaults), .medium)
        // Non-big game tiers pass through without touching the purse.
        XCTAssertEqual(DelightArbiterStore.requestGame(.roundWon,
                                                       now: t0.addingTimeInterval(120),
                                                       defaults: defaults), .normal)
        XCTAssertEqual(DelightArbiterStore.load(defaults: defaults).bigMoments.count, 2)
    }

    /// EVAL repro (FXD-1 Fund 2): completing a shared goal used to
    /// celebrate TWICE on the booking device — once at REST success
    /// (GoalContributeSheet) and once for the own `goal_updated` WS echo
    /// (RitualsAppState) — spending two arbiter slots for one moment. The
    /// echo path now gates its ceremony behind
    /// `MultiDeviceRules.allowsPartnerEffects`; this test replays the flow
    /// against the persisted ledger: one completion = exactly ONE ceremony
    /// = exactly ONE budget booking on the booking device.
    @MainActor
    func testGoalCompletionBooksExactlyOneCeremonyAndOneBudgetSlot() async throws {
        let suite = "delight.arbiter.tests.goal"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.removeObject(forKey: DelightArbiterStore.defaultsKey)

        let mySessionId = "session-alpha-0001"
        var ceremonies = 0
        func celebrateCompletion(at now: Date) {
            _ = DelightArbiterStore.request(.goalCompleted, now: now,
                                            defaults: defaults)
            ceremonies += 1
        }

        // 1. The booking succeeds via REST — the booking device celebrates.
        celebrateCompletion(at: t0)

        // 2. Moments later the server broadcasts goal_updated back to EVERY
        //    session, the booking one included. Its origin marker names the
        //    booking session, so the partner-effect gate must block the
        //    echo's ceremony on this device.
        let origin = EventOrigin(
            memberId: "m1", deviceId: "d1",
            sessionSuffix: MultiDeviceRules.sessionSuffix(of: mySessionId))
        if MultiDeviceRules.allowsPartnerEffects(origin: origin,
                                                 memberId: "m1",
                                                 sessionId: mySessionId) {
            celebrateCompletion(at: t0.addingTimeInterval(0.5))
        }

        XCTAssertEqual(ceremonies, 1,
                       "one goal completion = exactly one ceremony")
        XCTAssertEqual(DelightArbiterStore.load(defaults: defaults).bigMoments.count, 1,
                       "one goal completion = exactly one budget booking")

        // 3. The PARTNER's phone sees the same frame as a genuine partner
        //    event — its ceremony (on its own device ledger) stays allowed.
        XCTAssertTrue(MultiDeviceRules.allowsPartnerEffects(
            origin: origin, memberId: "m2", sessionId: "session-beta-0002"))
    }

    /// EVAL repro: 64 unsynchronized parallel requests overdrew the window
    /// (34 epics). The `@MainActor` store serializes every load→grant→save
    /// so the budget holds EXACTLY.
    func testParallelRequestsNeverOverdrawTheBudget() async throws {
        let suite = "delight.arbiter.tests.parallel"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        await MainActor.run {
            defaults.removeObject(forKey: DelightArbiterStore.defaultsKey)
        }

        let base = t0
        let epics = await withTaskGroup(of: DelightIntensity.self,
                                        returning: Int.self) { group in
            for i in 0..<64 {
                group.addTask {
                    await DelightArbiterStore.request(
                        .levelUp,
                        now: base.addingTimeInterval(Double(i) / 1000),
                        defaults: defaults)
                }
            }
            var granted = 0
            for await intensity in group where intensity == .epic { granted += 1 }
            return granted
        }
        XCTAssertEqual(epics, DelightArbiter.maxBigPerWindow)
        await MainActor.run {
            XCTAssertEqual(DelightArbiterStore.load(defaults: defaults).bigMoments.count,
                           DelightArbiter.maxBigPerWindow)
        }
    }
}
