import XCTest
@testable import SoooDreamyLogic

/// Pins the Kniffel reducer — dice derivation from the seed and the scoring
/// table are the multiplayer protocol.
final class KniffelLogicTests: XCTestCase {
    private let anna = "member-a"
    private let ben = "member-b"

    private func state(_ events: [KniffelEvent], seed: Int = 42) -> KniffelState {
        Kniffel.reduce(events: events, seed: seed, starter: anna, partner: ben)
    }

    // MARK: Deterministic dice

    func testPipsAreDeterministicAndInRange() {
        for turn in 0..<4 {
            for roll in 0..<3 {
                let a = Kniffel.pips(seed: 7, turn: turn, roll: roll)
                XCTAssertEqual(a, Kniffel.pips(seed: 7, turn: turn, roll: roll))
                XCTAssertEqual(a.count, 5)
                XCTAssertTrue(a.allSatisfy { (1...6).contains($0) })
            }
        }
        XCTAssertNotEqual(Kniffel.pips(seed: 7, turn: 0, roll: 0),
                          Kniffel.pips(seed: 8, turn: 0, roll: 0))
    }

    func testRerollKeepsHeldDice() {
        let first = state([.roll(member: anna, held: [])])
        XCTAssertEqual(first.rollCount, 1)
        let second = state([
            .roll(member: anna, held: []),
            .roll(member: anna, held: [0, 2]),
        ])
        XCTAssertEqual(second.rollCount, 2)
        XCTAssertEqual(second.dice[0], first.dice[0])
        XCTAssertEqual(second.dice[2], first.dice[2])
        let fresh = Kniffel.pips(seed: 42, turn: 0, roll: 1)
        XCTAssertEqual(second.dice[1], fresh[1])
        XCTAssertEqual(second.dice[3], fresh[3])
        XCTAssertEqual(second.dice[4], fresh[4])
    }

    func testDefensiveSkips() {
        // Ben cannot roll on Anna's turn; a 4th roll and premature score are skipped.
        var s = state([.roll(member: ben, held: [])])
        XCTAssertEqual(s.rollCount, 0)
        s = state([
            .roll(member: anna, held: []),
            .roll(member: anna, held: []),
            .roll(member: anna, held: []),
            .roll(member: anna, held: []),   // 4th roll → skipped
        ])
        XCTAssertEqual(s.rollCount, 3)
        s = state([.score(member: anna, category: "chance")])  // before rolling
        XCTAssertEqual(s.turnIndex, 0)
        XCTAssertTrue(s.scorecard(of: anna).isEmpty)
    }

    func testScoringBanksAndAdvancesTheTurn() {
        let s = state([
            .roll(member: anna, held: []),
            .score(member: anna, category: "chance"),
        ])
        let dice = Kniffel.pips(seed: 42, turn: 0, roll: 0)
        XCTAssertEqual(s.scorecard(of: anna)[.chance], dice.reduce(0, +))
        XCTAssertEqual(s.turnIndex, 1)
        XCTAssertEqual(s.rollCount, 0)
        XCTAssertTrue(s.dice.isEmpty)
        // Same category cannot be banked twice by the same player.
        let again = state([
            .roll(member: anna, held: []),
            .score(member: anna, category: "chance"),
            .roll(member: ben, held: []),
            .score(member: ben, category: "chance"),
            .roll(member: anna, held: []),
            .score(member: anna, category: "chance"),  // duplicate → skipped
        ])
        XCTAssertEqual(again.turnIndex, 2)
        XCTAssertEqual(again.rollCount, 1, "anna keeps her dice, turn not consumed")
    }

    // MARK: Scoring table

    func testCategoryScores() {
        XCTAssertEqual(KniffelCategory.ones.score(dice: [1, 1, 3, 4, 1]), 3)
        XCTAssertEqual(KniffelCategory.sixes.score(dice: [6, 6, 1, 2, 3]), 12)
        XCTAssertEqual(KniffelCategory.threeOfAKind.score(dice: [4, 4, 4, 2, 1]), 15)
        XCTAssertEqual(KniffelCategory.threeOfAKind.score(dice: [4, 4, 3, 2, 1]), 0)
        XCTAssertEqual(KniffelCategory.fourOfAKind.score(dice: [5, 5, 5, 5, 2]), 22)
        XCTAssertEqual(KniffelCategory.fullHouse.score(dice: [3, 3, 2, 2, 2]), 25)
        XCTAssertEqual(KniffelCategory.fullHouse.score(dice: [3, 3, 3, 3, 2]), 0)
        XCTAssertEqual(KniffelCategory.smallStraight.score(dice: [1, 2, 3, 4, 6]), 30)
        XCTAssertEqual(KniffelCategory.smallStraight.score(dice: [2, 2, 3, 4, 6]), 0)
        XCTAssertEqual(KniffelCategory.largeStraight.score(dice: [2, 3, 4, 5, 6]), 40)
        XCTAssertEqual(KniffelCategory.kniffel.score(dice: [4, 4, 4, 4, 4]), 50)
        XCTAssertEqual(KniffelCategory.chance.score(dice: [1, 2, 3, 4, 5]), 15)
    }

    func testUpperBonusAndTotals() {
        var card: [KniffelCategory: Int] = [
            .ones: 3, .twos: 6, .threes: 9, .fours: 12, .fives: 15, .sixes: 18,
        ]
        XCTAssertEqual(Kniffel.upperSum(card), 63)
        XCTAssertEqual(Kniffel.total(card), 63 + 35)
        card[.sixes] = 17
        XCTAssertEqual(Kniffel.total(card), 62, "no bonus below 63")
        card[.kniffel] = 50
        XCTAssertEqual(Kniffel.total(card), 112)
    }

    // MARK: Full game

    func testFullGameFinishesAfterAllCategories() {
        var events: [KniffelEvent] = []
        let categories = KniffelCategory.allCases
        for turn in 0..<Kniffel.totalTurns {
            let member = turn.isMultiple(of: 2) ? anna : ben
            events.append(.roll(member: member, held: []))
            events.append(.score(member: member, category: categories[turn / 2].rawValue))
        }
        let s = state(events)
        XCTAssertTrue(s.finished)
        XCTAssertEqual(s.scorecard(of: anna).count, 13)
        XCTAssertEqual(s.scorecard(of: ben).count, 13)
        // Winner is derived from the totals (nil only on a tie).
        let winner = Kniffel.winner(state: s, starter: anna, partner: ben)
        let totalA = Kniffel.total(s.scorecard(of: anna))
        let totalB = Kniffel.total(s.scorecard(of: ben))
        if totalA == totalB {
            XCTAssertNil(winner)
        } else {
            XCTAssertEqual(winner, totalA > totalB ? anna : ben)
        }
        // Nothing accepted after the end.
        let after = state(events + [.roll(member: anna, held: [])])
        XCTAssertEqual(after.rollCount, 0)
    }
}
