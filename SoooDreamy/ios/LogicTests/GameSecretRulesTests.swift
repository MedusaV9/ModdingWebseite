import XCTest
@testable import SoooDreamyLogic

final class GameSecretRulesTests: XCTestCase {

    private func move(_ member: String, kind: String?, round: Int? = nil,
                      commit: Bool = false) -> GameSecretMoveSummary {
        GameSecretMoveSummary(memberId: member, kind: kind, round: round,
                              carriesCommit: commit)
    }

    // MARK: Battleship (whole-game secret)

    func testBattleshipCommitWithoutRevealBlocksTakeover() {
        let moves = [move("a", kind: "commit", commit: true)]
        XCTAssertTrue(GameSecretRules.holdsSealedSecret(
            gameType: "battleship", state: "active", memberId: "a",
            createdBy: "a", payloadCarriesCommit: false, moves: moves))
        // The partner never committed — their devices may take over freely.
        XCTAssertFalse(GameSecretRules.holdsSealedSecret(
            gameType: "battleship", state: "active", memberId: "b",
            createdBy: "a", payloadCarriesCommit: false, moves: moves))
    }

    func testBattleshipRevealUnblocksTakeover() {
        let moves = [
            move("a", kind: "commit", commit: true),
            move("a", kind: "reveal"),
        ]
        XCTAssertFalse(GameSecretRules.holdsSealedSecret(
            gameType: "battleship", state: "active", memberId: "a",
            createdBy: "a", payloadCarriesCommit: false, moves: moves))
    }

    // MARK: Stadt-Land-Fluss / Zwei Wahrheiten (round-scoped secrets)

    func testRoundScopedCommitOnlyBlocksUntilTheSameRoundReveals() {
        let sealedRoundTwo = [
            move("a", kind: "commit", round: 1, commit: true),
            move("a", kind: "reveal", round: 1),
            move("a", kind: "commit", round: 2, commit: true),
        ]
        XCTAssertTrue(GameSecretRules.holdsSealedSecret(
            gameType: "stadtlandfluss", state: "active", memberId: "a",
            createdBy: "a", payloadCarriesCommit: false, moves: sealedRoundTwo))
        let revealed = sealedRoundTwo + [move("a", kind: "reveal", round: 2)]
        XCTAssertFalse(GameSecretRules.holdsSealedSecret(
            gameType: "stadtlandfluss", state: "active", memberId: "a",
            createdBy: "a", payloadCarriesCommit: false, moves: revealed))
    }

    func testTwoTruthsStatementsMoveCarriesTheCommit() {
        let moves = [move("b", kind: "statements", round: 0, commit: true)]
        XCTAssertTrue(GameSecretRules.holdsSealedSecret(
            gameType: "twotruths", state: "active", memberId: "b",
            createdBy: "a", payloadCarriesCommit: false, moves: moves))
    }

    // MARK: Hangman (secret sealed in the create payload)

    func testHangmanBindsTheSetterUntilTheReveal() {
        XCTAssertTrue(GameSecretRules.holdsSealedSecret(
            gameType: "hangman", state: "active", memberId: "a",
            createdBy: "a", payloadCarriesCommit: true, moves: []))
        // The guesser has no secret.
        XCTAssertFalse(GameSecretRules.holdsSealedSecret(
            gameType: "hangman", state: "active", memberId: "b",
            createdBy: "a", payloadCarriesCommit: true, moves: []))
        // After the fairness reveal, devices may change again.
        XCTAssertFalse(GameSecretRules.holdsSealedSecret(
            gameType: "hangman", state: "active", memberId: "a",
            createdBy: "a", payloadCarriesCommit: true,
            moves: [move("a", kind: "reveal")]))
    }

    // MARK: WordleDuo (creator's sealed target — whole-game secret, FXD-1 Fund 4)

    func testWordleDuoBindsTheCreatorFromTargetCommitUntilReveal() {
        // The creator sealed the target word; guesses (from either member)
        // do not open it — only the creator's verified reveal does.
        let sealed = [
            move("a", kind: "target", commit: true),
            move("a", kind: "guess"),
            move("b", kind: "guess"),
        ]
        XCTAssertTrue(GameSecretRules.holdsSealedSecret(
            gameType: "wordleduo", state: "active", memberId: "a",
            createdBy: "a", payloadCarriesCommit: false, moves: sealed))
        // The guesser holds no secret — their devices may change freely.
        XCTAssertFalse(GameSecretRules.holdsSealedSecret(
            gameType: "wordleduo", state: "active", memberId: "b",
            createdBy: "a", payloadCarriesCommit: false, moves: sealed))
    }

    func testWordleDuoRevealFreesTheCreator() {
        let revealed = [
            move("a", kind: "target", commit: true),
            move("a", kind: "guess"),
            move("b", kind: "guess"),
            move("a", kind: "reveal"),
        ]
        XCTAssertFalse(GameSecretRules.holdsSealedSecret(
            gameType: "wordleduo", state: "active", memberId: "a",
            createdBy: "a", payloadCarriesCommit: false, moves: revealed))
    }

    // MARK: RPS (own sealed round — round-scoped secret, FXD-1 Fund 4)

    func testRpsBlocksEachMemberWhileTheirOwnRoundCommitIsSealed() {
        let bothSealed = [
            move("a", kind: "commit", round: 0, commit: true),
            move("b", kind: "commit", round: 0, commit: true),
        ]
        for member in ["a", "b"] {
            XCTAssertTrue(GameSecretRules.holdsSealedSecret(
                gameType: "rps", state: "active", memberId: member,
                createdBy: "a", payloadCarriesCommit: false, moves: bothSealed),
                "\(member)'s sealed round choice lives only in the driving device's vault")
        }
        // My own reveal frees ME even while the partner's seal is pending.
        let aRevealed = bothSealed + [move("a", kind: "reveal", round: 0)]
        XCTAssertFalse(GameSecretRules.holdsSealedSecret(
            gameType: "rps", state: "active", memberId: "a",
            createdBy: "a", payloadCarriesCommit: false, moves: aRevealed))
        XCTAssertTrue(GameSecretRules.holdsSealedSecret(
            gameType: "rps", state: "active", memberId: "b",
            createdBy: "a", payloadCarriesCommit: false, moves: aRevealed))
    }

    func testRpsNextRoundCommitSealsAgainAfterAFullyRevealedRound() {
        let roundTwoSealed = [
            move("a", kind: "commit", round: 0, commit: true),
            move("b", kind: "commit", round: 0, commit: true),
            move("a", kind: "reveal", round: 0),
            move("b", kind: "reveal", round: 0),
            move("a", kind: "commit", round: 1, commit: true),
        ]
        XCTAssertTrue(GameSecretRules.holdsSealedSecret(
            gameType: "rps", state: "active", memberId: "a",
            createdBy: "a", payloadCarriesCommit: false, moves: roundTwoSealed))
        XCTAssertFalse(GameSecretRules.holdsSealedSecret(
            gameType: "rps", state: "active", memberId: "b",
            createdBy: "a", payloadCarriesCommit: false, moves: roundTwoSealed))
    }

    // MARK: Guards

    func testOnlyActiveCommitRevealGamesBlock() {
        let moves = [move("a", kind: "commit", commit: true)]
        XCTAssertFalse(GameSecretRules.holdsSealedSecret(
            gameType: "battleship", state: "ended", memberId: "a",
            createdBy: "a", payloadCarriesCommit: false, moves: moves))
        XCTAssertFalse(GameSecretRules.holdsSealedSecret(
            gameType: "dame", state: "active", memberId: "a",
            createdBy: "a", payloadCarriesCommit: false, moves: moves))
    }
}
