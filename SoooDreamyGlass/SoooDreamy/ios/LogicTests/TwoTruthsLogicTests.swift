import XCTest
@testable import SoooDreamyLogic

/// Pins the Two-Truths-One-Lie reducer — the 3-move round protocol.
final class TwoTruthsLogicTests: XCTestCase {
    private let anna = "member-a"
    private let ben = "member-b"

    private func state(_ events: [TwoTruthsEvent], rounds: Int = 2) -> TwoTruthsState {
        TwoTruths.reduce(events: events, rounds: rounds, starter: anna, partner: ben)
    }

    private let texts = ["Ich war mal auf einem Vulkan", "Ich hasse Schokolade", "Ich kann jonglieren"]

    func testRolesAlternate() {
        XCTAssertEqual(TwoTruths.teller(round: 0, starter: anna, partner: ben), anna)
        XCTAssertEqual(TwoTruths.teller(round: 1, starter: anna, partner: ben), ben)
    }

    func testRoundPhaseFlow() {
        var s = state([])
        XCTAssertEqual(s.rounds[0].phase, .composing)
        // Only the teller may submit statements; three non-empty texts required.
        s = state([.statements(member: ben, round: 0, texts: texts)])
        XCTAssertEqual(s.rounds[0].phase, .composing)
        s = state([.statements(member: anna, round: 0, texts: ["a", "", "c"])])
        XCTAssertEqual(s.rounds[0].phase, .composing)
        s = state([.statements(member: anna, round: 0, texts: texts)])
        XCTAssertEqual(s.rounds[0].phase, .guessing)
        // The teller cannot guess their own round.
        s = state([
            .statements(member: anna, round: 0, texts: texts),
            .guess(member: anna, round: 0, pick: 1),
        ])
        XCTAssertEqual(s.rounds[0].phase, .guessing)
        // Reveal before the guess is sealed out.
        s = state([
            .statements(member: anna, round: 0, texts: texts),
            .reveal(member: anna, round: 0, lieIndex: 1, serverVerified: true),
        ])
        XCTAssertNil(s.rounds[0].lieIndex)
        // Full round: guess then reveal.
        s = state([
            .statements(member: anna, round: 0, texts: texts),
            .guess(member: ben, round: 0, pick: 1),
            .reveal(member: anna, round: 0, lieIndex: 1, serverVerified: true),
        ])
        XCTAssertEqual(s.rounds[0].phase, .done)
        XCTAssertEqual(s.rounds[0].guessedRight, true)
        XCTAssertEqual(s.currentRound, 1)
    }

    func testScoringGuesserVsTeller() {
        let s = state([
            // Round 0: ben catches anna's lie → ben point.
            .statements(member: anna, round: 0, texts: texts),
            .guess(member: ben, round: 0, pick: 2),
            .reveal(member: anna, round: 0, lieIndex: 2, serverVerified: true),
            // Round 1: ben fools anna → ben point again.
            .statements(member: ben, round: 1, texts: texts),
            .guess(member: anna, round: 1, pick: 0),
            .reveal(member: ben, round: 1, lieIndex: 1, serverVerified: true),
        ])
        XCTAssertTrue(s.finished)
        XCTAssertEqual(TwoTruths.score(state: s, member: ben, starter: anna, partner: ben), 2)
        XCTAssertEqual(TwoTruths.score(state: s, member: anna, starter: anna, partner: ben), 0)
    }

    func testFutureRoundsAreGated() {
        let s = state([.statements(member: ben, round: 1, texts: texts)])
        XCTAssertNil(s.rounds[1].texts, "round 1 locked while round 0 is open")
    }

    func testCommitRevealPairForLieIndex() {
        let salt = CommitReveal.newSalt()
        let commit = CommitReveal.commit(secret: "2", salt: salt)
        XCTAssertTrue(CommitReveal.verify(reveal: "2", salt: salt, commit: commit))
        XCTAssertFalse(CommitReveal.verify(reveal: "1", salt: salt, commit: commit))
    }
}
