import XCTest
@testable import SoooDreamyLogic

/// Pins the deterministic reducers of the v2.0 realtime games
/// (`SoooDreamy/Content/CoupleGamesLogic.swift`). The server relays moves
/// blindly, so BOTH phones must derive identical state from the same
/// ordered move list — these tests are the contract.
final class CoupleGamesTests: XCTestCase {

    private let anna = "member-anna"
    private let ben = "member-ben"

    // MARK: - Connect Four

    func testConnectFourAlternatesStartingWithCreator() {
        let state = ConnectFour.reduce(drops: [(anna, 0), (ben, 1), (anna, 0)],
                                       starter: anna, partner: ben)
        XCTAssertEqual(state.moveCount, 3)
        XCTAssertEqual(ConnectFour.turn(state: state, starter: anna, partner: ben), ben)
        XCTAssertEqual(state.owner(column: 0, row: 0), anna)
        XCTAssertEqual(state.owner(column: 0, row: 1), anna)
        XCTAssertEqual(state.owner(column: 1, row: 0), ben)
    }

    func testConnectFourSkipsOutOfTurnAndInvalidDrops() {
        // Ben tries to move first (not his turn), then a drop into column 9.
        let state = ConnectFour.reduce(drops: [(ben, 0), (anna, 9), (anna, 3), (ben, 3)],
                                       starter: anna, partner: ben)
        XCTAssertEqual(state.moveCount, 2)
        XCTAssertEqual(state.owner(column: 3, row: 0), anna)
        XCTAssertEqual(state.owner(column: 3, row: 1), ben)
        XCTAssertNil(state.owner(column: 0, row: 0))
    }

    func testConnectFourSkipsDropsIntoFullColumn() {
        var drops: [(String, Int)] = []
        for turn in 0..<ConnectFour.rows {
            drops.append((turn.isMultiple(of: 2) ? anna : ben, 2))
        }
        drops.append((anna, 2))     // column 2 is full — must be skipped
        let state = ConnectFour.reduce(drops: drops, starter: anna, partner: ben)
        XCTAssertEqual(state.height(2), ConnectFour.rows)
        XCTAssertEqual(state.moveCount, ConnectFour.rows)
        XCTAssertEqual(ConnectFour.turn(state: state, starter: anna, partner: ben), anna)
    }

    func testConnectFourVerticalWin() {
        // Anna stacks column 0, Ben scatters — Anna wins with 4 in a column.
        let state = ConnectFour.reduce(
            drops: [(anna, 0), (ben, 1), (anna, 0), (ben, 2),
                    (anna, 0), (ben, 3), (anna, 0)],
            starter: anna, partner: ben)
        XCTAssertEqual(state.winner, anna)
        XCTAssertEqual(state.winningCells.count, 4)
        XCTAssertTrue(state.winningCells.allSatisfy { $0.column == 0 })
    }

    func testConnectFourHorizontalWin() {
        let state = ConnectFour.reduce(
            drops: [(anna, 0), (ben, 0), (anna, 1), (ben, 1),
                    (anna, 2), (ben, 2), (anna, 3)],
            starter: anna, partner: ben)
        XCTAssertEqual(state.winner, anna)
        XCTAssertTrue(state.winningCells.allSatisfy { $0.row == 0 })
    }

    func testConnectFourDiagonalWin() {
        // Staircase for Anna: (0,0), (1,1), (2,2), (3,3).
        let state = ConnectFour.reduce(
            drops: [(anna, 0), (ben, 1), (anna, 1), (ben, 2),
                    (anna, 3), (ben, 2), (anna, 2), (ben, 3),
                    (anna, 4), (ben, 3), (anna, 3)],
            starter: anna, partner: ben)
        XCTAssertEqual(state.winner, anna)
        let cells = Set(state.winningCells)
        XCTAssertEqual(cells, Set([ConnectFourCell(column: 0, row: 0),
                                   ConnectFourCell(column: 1, row: 1),
                                   ConnectFourCell(column: 2, row: 2),
                                   ConnectFourCell(column: 3, row: 3)]))
    }

    func testConnectFourIgnoresMovesAfterWin() {
        let state = ConnectFour.reduce(
            drops: [(anna, 0), (ben, 1), (anna, 0), (ben, 1),
                    (anna, 0), (ben, 1), (anna, 0),      // Anna wins here
                    (ben, 1), (anna, 2)],                // must be ignored
            starter: anna, partner: ben)
        XCTAssertEqual(state.winner, anna)
        XCTAssertEqual(state.height(1), 3)
        XCTAssertEqual(state.height(2), 0)
    }

    // MARK: - Photo memory

    func testPhotoMemoryTilesDeterministicPairsAndSeed() {
        let a = PhotoMemory.tiles(pairCount: 6, seed: 42)
        let b = PhotoMemory.tiles(pairCount: 6, seed: 42)
        XCTAssertEqual(a, b, "same seed must give the identical board on both phones")
        XCTAssertEqual(a.count, 12)
        for pair in 0..<6 {
            XCTAssertEqual(a.filter { $0 == pair }.count, 2, "pair \(pair) must appear exactly twice")
        }
        XCTAssertNotEqual(a, PhotoMemory.tiles(pairCount: 6, seed: 43))
    }

    func testPhotoMemoryTilesClampsPairCount() {
        XCTAssertEqual(PhotoMemory.tiles(pairCount: 99, seed: 1).count, PhotoMemory.maxPairs * 2)
        XCTAssertEqual(PhotoMemory.tiles(pairCount: 0, seed: 1).count, 4)
    }

    func testPhotoMemoryMatchScoresAndKeepsTurn() {
        let tiles = PhotoMemory.tiles(pairCount: 4, seed: 7)
        // Find the two positions of pair 0 for a guaranteed match.
        let positions = tiles.indices.filter { tiles[$0] == 0 }
        let state = PhotoMemory.reduce(flips: [(anna, positions[0], positions[1])],
                                       tiles: tiles, starter: anna, partner: ben)
        XCTAssertEqual(state.matched[0], anna)
        XCTAssertEqual(state.score(of: anna), 1)
        XCTAssertEqual(state.turn, anna, "a match keeps the same player's turn")
    }

    func testPhotoMemoryMissSwitchesTurnAndIgnoresOutOfTurnFlips() {
        let tiles = PhotoMemory.tiles(pairCount: 4, seed: 7)
        let zero = tiles.indices.filter { tiles[$0] == 0 }
        let one = tiles.indices.filter { tiles[$0] == 1 }
        let state = PhotoMemory.reduce(
            flips: [(anna, zero[0], one[0]),        // miss → Ben's turn
                    (anna, zero[0], zero[1]),       // out of turn → skipped
                    (ben, one[0], one[1])],         // Ben matches pair 1
            tiles: tiles, starter: anna, partner: ben)
        XCTAssertNil(state.matched[0])
        XCTAssertEqual(state.matched[1], ben)
        XCTAssertEqual(state.score(of: anna), 0)
        XCTAssertEqual(state.score(of: ben), 1)
        XCTAssertEqual(state.turn, ben)
    }

    func testPhotoMemoryFinishedOnceAllPairsMatched() {
        let tiles = PhotoMemory.tiles(pairCount: 2, seed: 3)
        let zero = tiles.indices.filter { tiles[$0] == 0 }
        let one = tiles.indices.filter { tiles[$0] == 1 }
        var flips: [(memberId: String, first: Int, second: Int)] = [(anna, zero[0], zero[1])]
        var state = PhotoMemory.reduce(flips: flips, tiles: tiles, starter: anna, partner: ben)
        XCTAssertFalse(PhotoMemory.finished(state: state, tiles: tiles))
        flips.append((anna, one[0], one[1]))
        state = PhotoMemory.reduce(flips: flips, tiles: tiles, starter: anna, partner: ben)
        XCTAssertTrue(PhotoMemory.finished(state: state, tiles: tiles))
        XCTAssertEqual(state.score(of: anna), 2)
    }

    // MARK: - Quiz duel

    func testQuizDuelDeckDeterministicAndSized() {
        let a = QuizDuel.deck(seed: 99, rounds: 10)
        let b = QuizDuel.deck(seed: 99, rounds: 10)
        XCTAssertEqual(a.map(\.id), b.map(\.id))
        XCTAssertEqual(a.count, 10)
        XCTAssertEqual(Set(a.map(\.id)).count, 10, "no duplicate questions in a deck")
    }

    func testQuizDuelFirstCorrectGetsTwoSecondCorrectGetsOne() {
        let deck = QuizDuel.deck(seed: 5, rounds: 3)
        let scores = QuizDuel.scores(
            answers: [(ben, 0, deck[0].correct),    // Ben buzzes first: +2
                      (anna, 0, deck[0].correct),   // Anna also right, later: +1
                      (anna, 1, wrongOption(deck[1])),
                      (ben, 1, deck[1].correct)],   // Ben first correct again: +2
            deck: deck)
        XCTAssertEqual(scores[ben], 4)
        XCTAssertEqual(scores[anna], 1)
    }

    func testQuizDuelOnlyFirstAnswerPerMemberCounts() {
        let deck = QuizDuel.deck(seed: 5, rounds: 2)
        let scores = QuizDuel.scores(
            answers: [(anna, 0, wrongOption(deck[0])),
                      (anna, 0, deck[0].correct)],  // second try must be ignored
            deck: deck)
        XCTAssertNil(scores[anna])
    }

    func testQuizDuelBothAnswered() {
        let deck = QuizDuel.deck(seed: 5, rounds: 2)
        let answers: [(memberId: String, round: Int, option: Int)] = [
            (anna, 0, deck[0].correct)
        ]
        XCTAssertFalse(QuizDuel.bothAnswered(answers: answers, round: 0, members: [anna, ben]))
        XCTAssertTrue(QuizDuel.bothAnswered(answers: answers + [(ben, 0, 0)],
                                            round: 0, members: [anna, ben]))
    }

    private func wrongOption(_ question: DuelQuestion) -> Int {
        (question.correct + 1) % question.options.count
    }

    // MARK: - This or That couch mode (Welle 7 [W6-Rest])

    func testCouchModeFullRoundFlowAndMatchCounting() {
        var state = ThisOrThatCouch.start(rounds: 2, startingPlayer: 0)
        XCTAssertEqual(state.phase, .firstPick)
        XCTAssertEqual(ThisOrThatCouch.currentPicker(state), 0)

        // Round 0: player 0 picks secretly, hand-off, player 1 matches.
        state = ThisOrThatCouch.pick(state, option: "a")
        XCTAssertEqual(state.phase, .handoff)
        XCTAssertNil(ThisOrThatCouch.currentPicker(state))
        state = ThisOrThatCouch.confirmHandoff(state)
        XCTAssertEqual(ThisOrThatCouch.currentPicker(state), 1)
        state = ThisOrThatCouch.pick(state, option: "a")
        XCTAssertEqual(state.phase, .reveal)
        XCTAssertTrue(ThisOrThatCouch.isMatch(state))
        XCTAssertEqual(state.matches, 1)
        XCTAssertEqual(ThisOrThatCouch.pick(of: 0, in: state), "a")
        XCTAssertEqual(ThisOrThatCouch.pick(of: 1, in: state), "a")

        // Round 1: the FIRST picker alternates — now player 1 starts.
        state = ThisOrThatCouch.advance(state)
        XCTAssertEqual(state.round, 1)
        XCTAssertEqual(state.phase, .firstPick)
        XCTAssertEqual(ThisOrThatCouch.currentPicker(state), 1)
        state = ThisOrThatCouch.pick(state, option: "a")
        state = ThisOrThatCouch.confirmHandoff(state)
        state = ThisOrThatCouch.pick(state, option: "b")
        XCTAssertFalse(ThisOrThatCouch.isMatch(state))
        XCTAssertEqual(state.matches, 1)
        XCTAssertEqual(ThisOrThatCouch.pick(of: 1, in: state), "a",
                       "player 1 was the first picker of round 1")
        XCTAssertEqual(ThisOrThatCouch.pick(of: 0, in: state), "b")

        // After the last reveal the game is finished.
        state = ThisOrThatCouch.advance(state)
        XCTAssertEqual(state.phase, .finished)
        XCTAssertNil(ThisOrThatCouch.currentPicker(state))
    }

    func testCouchModeSkipsInvalidAndOutOfPhaseInputs() {
        var state = ThisOrThatCouch.start(rounds: 1, startingPlayer: 1)
        XCTAssertEqual(ThisOrThatCouch.currentPicker(state), 1,
                       "startingPlayer 1 picks first in round 0")

        // Invalid option and premature hand-off/advance change nothing.
        XCTAssertEqual(ThisOrThatCouch.pick(state, option: "c"), state)
        XCTAssertEqual(ThisOrThatCouch.confirmHandoff(state), state)
        XCTAssertEqual(ThisOrThatCouch.advance(state), state)

        state = ThisOrThatCouch.pick(state, option: "b")
        // A second pick during the hand-off (double-tap) is skipped.
        XCTAssertEqual(ThisOrThatCouch.pick(state, option: "a"), state)

        state = ThisOrThatCouch.confirmHandoff(state)
        state = ThisOrThatCouch.pick(state, option: "b")
        state = ThisOrThatCouch.advance(state)
        XCTAssertEqual(state.phase, .finished)
        XCTAssertEqual(state.matches, 1)
        // Terminal state is inert.
        XCTAssertEqual(ThisOrThatCouch.pick(state, option: "a"), state)
        XCTAssertEqual(ThisOrThatCouch.advance(state), state)
    }

    func testCouchModeStartClampsRoundsAndPlayer() {
        let clamped = ThisOrThatCouch.start(rounds: 0, startingPlayer: 7)
        XCTAssertEqual(clamped.totalRounds, 1)
        XCTAssertEqual(clamped.startingPlayer, 1, "non-zero collapses to player 1")
        XCTAssertEqual(ThisOrThatCouch.start(rounds: 12, startingPlayer: 0).startingPlayer, 0)
    }

    // MARK: - Duel question pack integrity

    func testDuelQuestionsPackIsValid() {
        XCTAssertGreaterThanOrEqual(ContentPack.duelQuestions.count, 60)
        XCTAssertEqual(Set(ContentPack.duelQuestions.map(\.id)).count,
                       ContentPack.duelQuestions.count, "duplicate duel question ids")
        XCTAssertEqual(Set(ContentPack.duelQuestions.map(\.text.de)).count,
                       ContentPack.duelQuestions.count, "duplicate German duel question texts")
        XCTAssertEqual(Set(ContentPack.duelQuestions.map(\.text.en)).count,
                       ContentPack.duelQuestions.count, "duplicate English duel question texts")
        for question in ContentPack.duelQuestions {
            XCTAssertEqual(question.options.count, 3,
                           "duel question \(question.id): needs exactly 3 options")
            XCTAssertTrue(question.options.indices.contains(question.correct),
                          "duel question \(question.id): correct index out of range")
            XCTAssertFalse(question.text.de.isEmpty)
            XCTAssertFalse(question.text.en.isEmpty)
            for option in question.options {
                XCTAssertFalse(option.de.isEmpty)
                XCTAssertFalse(option.en.isEmpty)
            }
        }
    }
}
