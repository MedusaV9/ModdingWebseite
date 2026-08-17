import XCTest
@testable import SoooDreamyLogic

/// Pins the battleship reducer — the multiplayer protocol both phones (and
/// the fair-play audit) rely on. All rules here are frozen: changing them
/// desyncs running games.
final class BattleshipLogicTests: XCTestCase {
    private let anna = "member-a"
    private let ben = "member-b"

    private func state(_ events: [BattleshipEvent]) -> BattleshipState {
        Battleship.reduce(events: events, starter: anna, partner: ben)
    }

    // MARK: Layout

    func testRandomLayoutIsDeterministicAndValid() {
        for seed in [1, 7, 42, 987_654, 2_147_483_646] {
            let ships = Battleship.randomLayout(seed: seed)
            XCTAssertTrue(Battleship.isValidLayout(ships), "seed \(seed) produced invalid fleet")
            XCTAssertEqual(Battleship.encodeLayout(ships),
                           Battleship.encodeLayout(Battleship.randomLayout(seed: seed)),
                           "seed \(seed) not deterministic")
        }
        XCTAssertNotEqual(Battleship.encodeLayout(Battleship.randomLayout(seed: 1)),
                          Battleship.encodeLayout(Battleship.randomLayout(seed: 2)))
    }

    func testLayoutEncodingRoundTripsCanonically() {
        let ships = [[10, 11, 12], [0, 8, 16, 24], [40, 41], [50, 51, 52]]
        let encoded = Battleship.encodeLayout(ships)
        XCTAssertEqual(encoded, "0,8,16,24|10,11,12|40,41|50,51,52")
        XCTAssertEqual(Battleship.decodeLayout(encoded).map(Battleship.encodeLayout), encoded)
        XCTAssertNil(Battleship.decodeLayout("1,2,x|4"))
    }

    func testLayoutValidityRules() {
        XCTAssertTrue(Battleship.isValidLayout([[0, 1, 2, 3], [16, 24, 32], [40, 41, 42], [62, 63]]))
        // Wrong fleet sizes.
        XCTAssertFalse(Battleship.isValidLayout([[0, 1, 2, 3], [16, 24, 32], [40, 41, 42]]))
        // Diagonal ship.
        XCTAssertFalse(Battleship.isValidLayout([[0, 9, 18, 27], [16, 24, 32], [40, 41, 42], [62, 63]]))
        // Row wrap (7 → 8 crosses the board edge).
        XCTAssertFalse(Battleship.isValidLayout([[5, 6, 7, 8], [16, 24, 32], [40, 41, 42], [62, 63]]))
        // Overlap.
        XCTAssertFalse(Battleship.isValidLayout([[0, 1, 2, 3], [1, 9, 17], [40, 41, 42], [62, 63]]))
    }

    // MARK: Phases & turn order

    func testSetupUntilBothCommitted() {
        var s = state([.commit(member: anna)])
        XCTAssertEqual(s.phase, .setup)
        // Salvo before both commits is ignored.
        s = state([.commit(member: anna), .salvo(member: anna, cells: [0, 1])])
        XCTAssertTrue(s.salvos.isEmpty)
        s = state([.commit(member: anna), .commit(member: ben)])
        XCTAssertEqual(s.phase, .battle)
        XCTAssertEqual(Battleship.turn(state: s, starter: anna, partner: ben), anna)
    }

    func testSalvoAlternationAndDefensiveSkips() {
        let s = state([
            .commit(member: anna), .commit(member: ben),
            .salvo(member: ben, cells: [0, 1]),        // out of turn → skipped
            .salvo(member: anna, cells: [0, 0, 99, 1, 2]),  // dupes/out-of-range/over-long trimmed
            .salvo(member: anna, cells: [5]),          // out of turn (still ben) → skipped
            .salvo(member: ben, cells: [10, 11]),
            .salvo(member: anna, cells: [0, 1]),       // all cells already shot → skipped
        ])
        XCTAssertEqual(s.salvos.count, 2)
        XCTAssertEqual(s.salvos[0].member, anna)
        XCTAssertEqual(s.salvos[0].cells, [0, 1])      // trimmed to salvoSize, order kept
        XCTAssertEqual(s.salvos[1].member, ben)
        XCTAssertEqual(Battleship.turn(state: s, starter: anna, partner: ben), anna)
    }

    func testReportsOnlyFromDefenderAndOnlyOnce() {
        let s = state([
            .commit(member: anna), .commit(member: ben),
            .salvo(member: anna, cells: [0, 1]),
            .report(member: anna, index: 0, hits: [0, 1], sunk: []),  // attacker reporting → skipped
            .report(member: ben, index: 0, hits: [0, 7], sunk: [2]),  // 7 not in salvo → filtered
            .report(member: ben, index: 0, hits: [], sunk: []),       // duplicate → skipped
        ])
        XCTAssertEqual(s.reports[0]?.hits, [0])
        XCTAssertEqual(s.reports[0]?.sunk, [2])
        XCTAssertEqual(s.hitCount(by: anna), 1)
        XCTAssertEqual(s.sunkSizes(by: anna), [2])
        XCTAssertEqual(s.shotResults(by: anna)[0], .some(true))
        XCTAssertEqual(s.shotResults(by: anna)[1], .some(false))
    }

    func testPendingReportIsFoundForTheDefender() {
        let s = state([
            .commit(member: anna), .commit(member: ben),
            .salvo(member: anna, cells: [0, 1]),
        ])
        XCTAssertEqual(s.pendingReportIndex(defender: ben), 0)
        XCTAssertNil(s.pendingReportIndex(defender: anna))
    }

    func testWinnerWhenAllFleetCellsAreHit() {
        var events: [BattleshipEvent] = [.commit(member: anna), .commit(member: ben)]
        // Anna sinks Ben's whole 12-cell fleet in 6 salvos; Ben always misses.
        let benShips = [[0, 1, 2, 3], [8, 9, 10], [16, 17, 18], [24, 25]]
        let benCells = benShips.flatMap { $0 }
        var alreadyHit: Set<Int> = []
        for pair in 0..<6 {
            let shots = Array(benCells[(pair * 2)..<(pair * 2 + 2)])
            events.append(.salvo(member: anna, cells: shots))
            let answer = Battleship.report(cells: shots, layout: benShips, alreadyHit: alreadyHit)
            events.append(.report(member: ben, index: pair * 2, hits: answer.hits, sunk: answer.sunk))
            alreadyHit.formUnion(answer.hits)
            events.append(.salvo(member: ben, cells: [56 + pair]))
            events.append(.report(member: anna, index: pair * 2 + 1, hits: [], sunk: []))
        }
        let s = state(events)
        XCTAssertEqual(s.winner, anna)
        XCTAssertEqual(s.phase, .finished)
        XCTAssertEqual(s.hitCount(by: anna), Battleship.fleetCellCount)
        XCTAssertEqual(s.sunkSizes(by: anna).sorted(), Battleship.fleet.sorted())
        // No salvos accepted after the win.
        let after = state(events + [.salvo(member: anna, cells: [60])])
        XCTAssertEqual(after.salvos.count, s.salvos.count)
    }

    // MARK: Defender bookkeeping & fair play

    func testReportComputesHitsAndSinkMoments() {
        let layout = [[0, 1, 2, 3], [8, 9, 10], [16, 17, 18], [24, 25]]
        var answer = Battleship.report(cells: [0, 5], layout: layout, alreadyHit: [])
        XCTAssertEqual(answer.hits, [0])
        XCTAssertEqual(answer.sunk, [])
        answer = Battleship.report(cells: [24, 25], layout: layout, alreadyHit: [])
        XCTAssertEqual(answer.hits, [24, 25])
        XCTAssertEqual(answer.sunk, [2])
        // Sinking shot completes a ship that was partially hit before.
        answer = Battleship.report(cells: [10, 40], layout: layout, alreadyHit: [8, 9])
        XCTAssertEqual(answer.hits, [10])
        XCTAssertEqual(answer.sunk, [3])
        // A fully-sunk ship is not announced again.
        answer = Battleship.report(cells: [40], layout: layout, alreadyHit: [24, 25])
        XCTAssertEqual(answer.sunk, [])
    }

    func testHonestAuditExposesFalseReports() {
        let layout = [[0, 1, 2, 3], [8, 9, 10], [16, 17, 18], [24, 25]]
        let truthful = state([
            .commit(member: anna), .commit(member: ben),
            .salvo(member: anna, cells: [0, 4]),
            .report(member: ben, index: 0, hits: [0], sunk: []),
        ])
        XCTAssertTrue(Battleship.honest(state: truthful, defender: ben, layout: layout))
        let lying = state([
            .commit(member: anna), .commit(member: ben),
            .salvo(member: anna, cells: [0, 4]),
            .report(member: ben, index: 0, hits: [], sunk: []),   // hides the hit on 0
        ])
        XCTAssertFalse(Battleship.honest(state: lying, defender: ben, layout: layout))
    }

    func testCommitRevealRoundTripMatchesLayoutEncoding() {
        let ships = Battleship.randomLayout(seed: 99)
        let secret = Battleship.encodeLayout(ships)
        let salt = "0123456789abcdef"
        let commit = CommitReveal.commit(secret: secret, salt: salt)
        XCTAssertTrue(CommitReveal.verify(reveal: secret, salt: salt, commit: commit))
        XCTAssertFalse(CommitReveal.verify(reveal: secret + "|", salt: salt, commit: commit))
    }

    func testShareGridRendersShots() {
        let s = state([
            .commit(member: anna), .commit(member: ben),
            .salvo(member: anna, cells: [0, 1]),
            .report(member: ben, index: 0, hits: [0], sunk: []),
        ])
        let grid = Battleship.shareGrid(results: s.shotResults(by: anna))
        let rows = grid.split(separator: "\n")
        XCTAssertEqual(rows.count, 8)
        XCTAssertTrue(rows[0].hasPrefix("💥🌊⬛"))
    }
}
