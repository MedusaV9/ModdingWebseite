import XCTest
@testable import SoooDreamyLogic

/// Pins the game ceremony rules (roadmap 24): tier matrix, the BIG budget
/// (anti-inflation, DESIGN.md Gebot 4) and the victory-motif shape.
final class GameDelightRulesTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_900_000_000)

    // MARK: Requested tiers

    func testRequestedTierMatrix() {
        XCTAssertEqual(GameDelightRules.requestedTier(for: .move), .subtle)
        XCTAssertEqual(GameDelightRules.requestedTier(for: .roundWon), .normal)
        XCTAssertEqual(GameDelightRules.requestedTier(for: .matchWon), .big)
        XCTAssertEqual(GameDelightRules.requestedTier(for: .matchTied), .normal)
        XCTAssertEqual(GameDelightRules.requestedTier(for: .matchLost), .subtle)
        XCTAssertEqual(GameDelightRules.requestedTier(for: .seasonMilestone), .big)
    }

    // MARK: Budget

    func testBudgetGrantsTwoBigsThenDowngrades() {
        var ledger = GameCeremonyLedger()
        let first = GameDelightRules.grant(event: .matchWon, ledger: ledger, now: t0)
        XCTAssertEqual(first.tier, .big)
        ledger = first.ledger

        let second = GameDelightRules.grant(event: .matchWon, ledger: ledger,
                                            now: t0.addingTimeInterval(60))
        XCTAssertEqual(second.tier, .big)
        ledger = second.ledger

        // Third match win inside the window: still a win, but normal tier.
        let third = GameDelightRules.grant(event: .matchWon, ledger: ledger,
                                           now: t0.addingTimeInterval(120))
        XCTAssertEqual(third.tier, .normal)
        // A downgraded ceremony consumes NO budget.
        XCTAssertEqual(third.ledger.bigMoments.count, 2)
    }

    func testBudgetRecoversAfterTheWindow() {
        var ledger = GameCeremonyLedger()
        ledger = GameDelightRules.grant(event: .matchWon, ledger: ledger, now: t0).ledger
        ledger = GameDelightRules.grant(event: .matchWon, ledger: ledger,
                                        now: t0.addingTimeInterval(60)).ledger
        let later = t0.addingTimeInterval(GameDelightRules.bigWindow + 61)
        let next = GameDelightRules.grant(event: .matchWon, ledger: ledger, now: later)
        XCTAssertEqual(next.tier, .big)
        // Expired entries were pruned; only the fresh grant remains + itself.
        XCTAssertEqual(next.ledger.bigMoments.count, 1)
    }

    func testSeasonMilestoneSharesTheSameBudget() {
        var ledger = GameCeremonyLedger()
        ledger = GameDelightRules.grant(event: .matchWon, ledger: ledger, now: t0).ledger
        ledger = GameDelightRules.grant(event: .seasonMilestone, ledger: ledger,
                                        now: t0.addingTimeInterval(30)).ledger
        let third = GameDelightRules.grant(event: .matchWon, ledger: ledger,
                                           now: t0.addingTimeInterval(60))
        XCTAssertEqual(third.tier, .normal)
    }

    func testSmallTiersNeverTouchTheBudget() {
        let ledger = GameCeremonyLedger()
        for event in [GameCeremonyEvent.move, .roundWon, .matchTied, .matchLost] {
            let granted = GameDelightRules.grant(event: event, ledger: ledger, now: t0)
            XCTAssertEqual(granted.tier, GameDelightRules.requestedTier(for: event), event.rawValue)
            XCTAssertTrue(granted.ledger.bigMoments.isEmpty, event.rawValue)
        }
    }

    func testGrantPrunesFutureAndExpiredEntries() {
        // Clock weirdness (device time set back) must not poison the window.
        let ledger = GameCeremonyLedger(bigMoments: [
            t0.addingTimeInterval(3600),                          // future
            t0.addingTimeInterval(-GameDelightRules.bigWindow),   // expired
        ])
        let granted = GameDelightRules.grant(event: .matchWon, ledger: ledger, now: t0)
        XCTAssertEqual(granted.tier, .big)
        XCTAssertEqual(granted.ledger.bigMoments, [t0])
    }

    // MARK: Rendering matrix

    func testMoveStaysFoleyOnly() {
        let spec = GameDelightRules.spec(event: .move, tier: .subtle)
        XCTAssertNil(spec.overlay)
        XCTAssertNil(spec.fanfare)
        XCTAssertNil(spec.victoryMotif)
    }

    func testRoundWonIsALiftNotACeremony() {
        let spec = GameDelightRules.spec(event: .roundWon, tier: .normal)
        XCTAssertNil(spec.overlay)
        XCTAssertEqual(spec.fanfare, .success)
        XCTAssertNil(spec.victoryMotif)
    }

    func testMatchWonRendersByGrantedTier() {
        let big = GameDelightRules.spec(event: .matchWon, tier: .big)
        XCTAssertEqual(big.overlay, .epic)
        XCTAssertEqual(big.fanfare, .fanfareEpic)
        XCTAssertEqual(big.victoryMotif, GameDelightRules.victoryMotif(tier: .big))

        let downgraded = GameDelightRules.spec(event: .matchWon, tier: .normal)
        XCTAssertEqual(downgraded.overlay, .medium)
        XCTAssertEqual(downgraded.fanfare, .fanfareMedium)
        XCTAssertEqual(downgraded.victoryMotif, GameDelightRules.victoryMotif(tier: .normal))
    }

    func testTieAndLossKeepTheWarmLanguage() {
        let tie = GameDelightRules.spec(event: .matchTied, tier: .normal)
        XCTAssertEqual(tie.overlay, .medium)
        XCTAssertEqual(tie.fanfare, .fanfareMedium)
        XCTAssertNil(tie.victoryMotif)

        let loss = GameDelightRules.spec(event: .matchLost, tier: .subtle)
        XCTAssertEqual(loss.overlay, .small)
        XCTAssertEqual(loss.fanfare, .lose)
        XCTAssertNil(loss.victoryMotif, "a loss never gets the victory motif")
    }

    func testSeasonMilestoneKeepsTheGenericFanfareTwin() {
        // The victory motif is EXCLUSIVE to match wins — that exclusivity
        // is what makes it a signature.
        let big = GameDelightRules.spec(event: .seasonMilestone, tier: .big)
        XCTAssertEqual(big.overlay, .epic)
        XCTAssertNil(big.victoryMotif)
    }

    // MARK: Victory motif shape

    func testVictoryMotifIsShortAndTiered() {
        let big = GameDelightRules.victoryMotif(tier: .big)
        let normal = GameDelightRules.victoryMotif(tier: .normal)
        let subtle = GameDelightRules.victoryMotif(tier: .subtle)
        // Bigger tier = longer, richer motif; all stay short signatures.
        XCTAssertGreaterThan(big.count, normal.count)
        XCTAssertGreaterThan(normal.count, subtle.count)
        XCTAssertLessThanOrEqual(HapticTimeline.duration(of: big), 3.0)
        XCTAssertLessThanOrEqual(HapticTimeline.duration(of: normal), 1.5)
        for events in [big, normal, subtle] {
            for event in events {
                XCTAssertGreaterThanOrEqual(event.i, 0); XCTAssertLessThanOrEqual(event.i, 1)
                XCTAssertGreaterThanOrEqual(event.s, 0); XCTAssertLessThanOrEqual(event.s, 1)
                XCTAssertGreaterThanOrEqual(event.t, 0)
            }
            // Events arrive in timeline order (AHAP requirement).
            XCTAssertEqual(events.map(\.t), events.map(\.t).sorted())
        }
    }

    func testVictoryMotifOpensWithTheDoubleHeartbeat() {
        // The signature: two soft heartbeats before the ta-daa. Pinned so
        // a future tweak keeps the identity or fails a test consciously.
        let big = GameDelightRules.victoryMotif(tier: .big)
        XCTAssertGreaterThanOrEqual(big.count, 5)
        XCTAssertGreaterThan(big[0].i, big[1].i, "lub is stronger than dub")
        XCTAssertGreaterThan(big[2].i, big[3].i, "second heartbeat too")
        let peak = big.max { $0.i < $1.i }
        XCTAssertEqual(peak?.i, 1.0, "the shared TA is the loudest moment")
    }
}
