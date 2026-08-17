import XCTest
@testable import SoooDreamyLogic

/// Pins the deterministic W8C board & duel reducers
/// (`SoooDreamy/Content/BoardGameRules.swift`) against the documented
/// server rules (docs/API.md "W8C board & duel games" +
/// server/src/game-rules.js). Both phones must derive the identical board
/// from the same ordered move list — these tests are the contract.
final class BoardGameRulesTests: XCTestCase {

    private let anna = "member-anna"
    private let ben = "member-ben"

    // MARK: - Dame

    func testDameInitialBoardTwelveMenEachOnDarkSquares() {
        let state = Dame.reduce(moves: [], starter: anna, partner: ben)
        XCTAssertEqual(state.count(of: anna), 12)
        XCTAssertEqual(state.count(of: ben), 12)
        XCTAssertEqual(state.turn, anna)
        for index in 0..<64 where state.board[index] != nil {
            XCTAssertTrue(Dame.isPlayable(index), "piece on light square \(index)")
        }
        // Row 0 is the CREATOR's back row; the partner sits on rows 5–7.
        XCTAssertEqual(state.board[1]?.owner, anna)
        XCTAssertEqual(state.board[62]?.owner, ben)
        XCTAssertEqual(state.forward(of: anna), 1)
        XCTAssertEqual(state.forward(of: ben), -1)
    }

    func testDameQuietStepAlternatesAndCountsQuietPlies() {
        let state = Dame.reduce(moves: [(anna, [17, 26]), (ben, [40, 33])],
                                starter: anna, partner: ben)
        XCTAssertEqual(state.board[26]?.owner, anna)
        XCTAssertEqual(state.board[33]?.owner, ben)
        XCTAssertNil(state.board[17])
        XCTAssertEqual(state.turn, anna)
        XCTAssertEqual(state.quietPlies, 2)
    }

    func testDameMenCannotStepBackwards() {
        // After 17→26 anna may not walk the man back to 17.
        let state = Dame.reduce(moves: [(anna, [17, 26]), (ben, [40, 33]), (anna, [26, 17])],
                                starter: anna, partner: ben)
        XCTAssertEqual(state.moveCount, 2)
        XCTAssertEqual(state.board[26]?.owner, anna)
    }

    func testDameCaptureIsMandatory() {
        // 26 can jump over ben's man on 33 — the quiet step 19→28 is
        // refused (server: 409 capture_required) and therefore skipped.
        let moves: [(String, [Int])] = [(anna, [17, 26]), (ben, [40, 33]), (anna, [19, 28])]
        let state = Dame.reduce(moves: moves, starter: anna, partner: ben)
        XCTAssertEqual(state.moveCount, 2)
        XCTAssertEqual(state.turn, anna)
        let paths = Dame.legalPaths(state: state)
        XCTAssertTrue(paths.allSatisfy { $0.count >= 2 && abs(Dame.row($0[1]) - Dame.row($0[0])) == 2 },
                      "with a capture available only jump paths are legal: \(paths)")
        XCTAssertTrue(paths.contains([26, 40]))
    }

    func testDameCaptureRemovesVictimAndResetsQuietPlies() {
        let moves: [(String, [Int])] = [(anna, [17, 26]), (ben, [40, 33]), (anna, [26, 40])]
        let state = Dame.reduce(moves: moves, starter: anna, partner: ben)
        XCTAssertEqual(state.board[40]?.owner, anna)
        XCTAssertNil(state.board[33])
        XCTAssertEqual(state.count(of: ben), 11)
        XCTAssertEqual(state.quietPlies, 0)
    }

    func testDameMultiJumpTravelsAsOnePathAndMustFinishTheChain() {
        var board = [DamePiece?](repeating: nil, count: 64)
        board[8] = DamePiece(owner: anna, king: false)
        board[17] = DamePiece(owner: ben, king: false)
        board[35] = DamePiece(owner: ben, king: false)
        let full = Dame.trace(board: board, path: [8, 26, 44], owner: anna, forward: 1)
        XCTAssertEqual(full?.to, 44)
        XCTAssertEqual(Set(full?.captures ?? []), Set([17, 35]))
        // Stopping mid-chain is capture_incomplete — illegal.
        XCTAssertNil(Dame.trace(board: board, path: [8, 26], owner: anna, forward: 1))
    }

    func testDameLegalPathsListsOnlyCompleteCaptureChains() {
        var board = [DamePiece?](repeating: nil, count: 64)
        board[8] = DamePiece(owner: anna, king: false)
        board[17] = DamePiece(owner: ben, king: false)
        board[35] = DamePiece(owner: ben, king: false)
        let state = DameState(board: board, turn: anna, quietPlies: 0, moveCount: 0,
                              starter: anna, partner: ben)
        XCTAssertEqual(Dame.legalPaths(state: state), [[8, 26, 44]])
    }

    func testDameManPromotesOnlyWhenTheMoveEndsOnTheFarRow() {
        // Quiet step onto row 7 promotes.
        var board = [DamePiece?](repeating: nil, count: 64)
        board[49] = DamePiece(owner: anna, king: false)
        let stepState = DameState(board: board, turn: anna, quietPlies: 0, moveCount: 0,
                                  starter: anna, partner: ben)
        let promoted = Dame.applying(path: [49, 56], to: stepState)
        XCTAssertEqual(promoted?.board[56]?.king, true)
        // A jump chain PASSING THROUGH row 7 does not: 46→60→42 touches
        // the back row mid-path and ends on row 5 as a man.
        var chain = [DamePiece?](repeating: nil, count: 64)
        chain[46] = DamePiece(owner: anna, king: false)
        chain[53] = DamePiece(owner: ben, king: false)
        chain[51] = DamePiece(owner: ben, king: false)
        let chainState = DameState(board: chain, turn: anna, quietPlies: 3, moveCount: 4,
                                   starter: anna, partner: ben)
        let after = Dame.applying(path: [46, 60, 42], to: chainState)
        XCTAssertEqual(after?.board[42]?.king, false)
        XCTAssertEqual(after?.quietPlies, 0, "a capture resets the draw clock")
        XCTAssertNil(after?.board[53])
        XCTAssertNil(after?.board[51])
    }

    func testDameKingStepsInAllFourDiagonalsButNeverFlies() {
        var board = [DamePiece?](repeating: nil, count: 64)
        board[26] = DamePiece(owner: anna, king: true)
        XCTAssertEqual(Set(Dame.steps(board: board, from: 26, king: true, forward: 1)),
                       Set([17, 19, 33, 35]))
        // No flying kings: a two-square quiet diagonal is not a legal move.
        XCTAssertNil(Dame.trace(board: board, path: [26, 44], owner: anna, forward: 1))
    }

    func testDameStatusWinsWhenOpponentHasNoPiecesOrNoMove() {
        var noPieces = [DamePiece?](repeating: nil, count: 64)
        noPieces[1] = DamePiece(owner: anna, king: false)
        let wiped = DameState(board: noPieces, turn: ben, quietPlies: 0, moveCount: 10,
                              starter: anna, partner: ben)
        let wipedStatus = Dame.status(state: wiped, drawPlies: 40)
        XCTAssertTrue(wipedStatus.complete)
        XCTAssertEqual(wipedStatus.winner, anna)
        // Ben's only man sits on his own back row corner and is blocked.
        var blocked = [DamePiece?](repeating: nil, count: 64)
        blocked[1] = DamePiece(owner: ben, king: false)
        blocked[8] = DamePiece(owner: anna, king: false)
        blocked[10] = DamePiece(owner: anna, king: false)
        blocked[17] = DamePiece(owner: anna, king: false)
        blocked[19] = DamePiece(owner: anna, king: false)
        let stuck = DameState(board: blocked, turn: ben, quietPlies: 0, moveCount: 10,
                              starter: anna, partner: ben)
        let stuckStatus = Dame.status(state: stuck, drawPlies: 40)
        XCTAssertTrue(stuckStatus.complete)
        XCTAssertEqual(stuckStatus.winner, anna)
    }

    func testDameQuietPliesForceTheDraw() {
        let state = Dame.reduce(moves: [(anna, [17, 26]), (ben, [40, 33])],
                                starter: anna, partner: ben)
        let status = Dame.status(state: state, drawPlies: 2)
        XCTAssertTrue(status.complete)
        XCTAssertTrue(status.draw)
        XCTAssertNil(status.winner)
        XCTAssertFalse(Dame.status(state: state, drawPlies: 40).complete)
    }

    func testDameSkipsOutOfTurnAndMalformedPaths() {
        let moves: [(String, [Int])] = [
            (ben, [40, 33]),          // not his turn
            (anna, [16, 25]),         // 16 is a light square
            (anna, [17]),             // too short
            (anna, [17, 26]),         // finally a legal step
        ]
        let state = Dame.reduce(moves: moves, starter: anna, partner: ben)
        XCTAssertEqual(state.moveCount, 1)
        XCTAssertEqual(state.turn, ben)
    }

    // MARK: - Reversi

    func testReversiInitialDiscsCreatorOn28And35() {
        let state = Reversi.reduce(moves: [], starter: anna, partner: ben)
        XCTAssertEqual(state.board[28], anna)
        XCTAssertEqual(state.board[35], anna)
        XCTAssertEqual(state.board[27], ben)
        XCTAssertEqual(state.board[36], ben)
        XCTAssertEqual(state.count(of: anna), 2)
        XCTAssertEqual(state.count(of: ben), 2)
        XCTAssertEqual(state.turn, anna)
        XCTAssertFalse(state.complete)
    }

    func testReversiOpeningLegalMoves() {
        let state = Reversi.reduce(moves: [], starter: anna, partner: ben)
        XCTAssertEqual(Set(Reversi.legalMoves(board: state.board, owner: anna)),
                       Set([19, 26, 37, 44]))
    }

    func testReversiPlacementFlipsTheEnclosedLine() {
        let state = Reversi.reduce(moves: [(anna, .place(19))], starter: anna, partner: ben)
        XCTAssertEqual(state.board[19], anna)
        XCTAssertEqual(state.board[27], anna, "the enclosed disc flips")
        XCTAssertEqual(state.count(of: anna), 4)
        XCTAssertEqual(state.count(of: ben), 1)
        XCTAssertEqual(state.turn, ben)
        XCTAssertEqual(state.placed, 5)
    }

    func testReversiSkipsNoFlipPlacementsAndOccupiedSquares() {
        // Corner 0 flips nothing (server: 409 no_flip); 28 is occupied.
        let state = Reversi.reduce(moves: [(anna, .place(0)), (anna, .place(28)),
                                           (anna, .place(19))],
                                   starter: anna, partner: ben)
        XCTAssertEqual(state.placed, 5)
        XCTAssertNil(state.board[0])
    }

    func testReversiPassIsSkippedWhileAPlacementExists() {
        // Server: 409 pass_not_allowed — the reducer must not advance.
        let state = Reversi.reduce(moves: [(anna, .pass), (anna, .place(19))],
                                   starter: anna, partner: ben)
        XCTAssertEqual(state.passes, 0)
        XCTAssertEqual(state.turn, ben)
    }

    func testReversiCompletesOnDoublePassOrFullBoard() {
        var byPasses = Reversi.reduce(moves: [], starter: anna, partner: ben)
        byPasses.passes = 2
        XCTAssertTrue(byPasses.complete)
        var byBoard = Reversi.reduce(moves: [], starter: anna, partner: ben)
        byBoard.placed = 64
        XCTAssertTrue(byBoard.complete)
    }

    func testReversiWinnerIsTheDiscMajority() {
        var state = Reversi.reduce(moves: [(anna, .place(19))], starter: anna, partner: ben)
        XCTAssertNil(state.winner, "no winner before the game completes")
        state.passes = 2
        XCTAssertEqual(state.winner, anna)
    }

    // MARK: - Käsekästchen

    func testKaeseEdgeIndexingMatchesTheServerLayout() {
        // size 5 (default): horizontal row*5+col, vertical 30+row*6+col.
        XCTAssertEqual(Kaesekaestchen.edgeCount(size: 5), 60)
        XCTAssertEqual(Kaesekaestchen.horizontalEdge(size: 5, row: 2, col: 3), 13)
        XCTAssertEqual(Kaesekaestchen.verticalEdge(size: 5, row: 2, col: 3), 45)
        // Box r*size+c → [top, bottom, left, right].
        XCTAssertEqual(Kaesekaestchen.boxEdges(size: 2, box: 0), [0, 2, 6, 7])
        XCTAssertEqual(Kaesekaestchen.boxEdges(size: 2, box: 3), [3, 5, 10, 11])
    }

    func testKaeseClosingABoxScoresAndGrantsAnotherTurn() {
        let moves: [(String, Int)] = [(anna, 0), (ben, 2), (anna, 6), (ben, 7)]
        let state = Kaesekaestchen.reduce(moves: moves, size: 2, starter: anna, partner: ben)
        XCTAssertEqual(state.owners[0], ben)
        XCTAssertEqual(state.scores[ben], 1)
        XCTAssertEqual(state.turn, ben, "closing a box grants ANOTHER turn")
    }

    func testKaeseOneEdgeCanCloseTwoBoxes() {
        // Edge 7 is box 0's right AND box 1's left edge.
        let moves: [(String, Int)] = [(anna, 0), (ben, 1), (anna, 2), (ben, 3),
                                      (anna, 6), (ben, 8), (anna, 7)]
        let state = Kaesekaestchen.reduce(moves: moves, size: 2, starter: anna, partner: ben)
        XCTAssertEqual(state.scores[anna], 2)
        XCTAssertEqual(state.owners[0], anna)
        XCTAssertEqual(state.owners[1], anna)
        XCTAssertEqual(state.turn, anna)
    }

    func testKaeseNonClosingEdgePassesTheTurn() {
        let state = Kaesekaestchen.reduce(moves: [(anna, 0)], size: 2,
                                          starter: anna, partner: ben)
        XCTAssertEqual(state.turn, ben)
        XCTAssertEqual(state.scores[anna], 0)
    }

    func testKaeseSkipsDuplicateEdgesAndOutOfTurnMoves() {
        let moves: [(String, Int)] = [(ben, 0), (anna, 0), (ben, 0), (ben, 99), (ben, 1)]
        let state = Kaesekaestchen.reduce(moves: moves, size: 2, starter: anna, partner: ben)
        XCTAssertEqual(state.drawn, Set([0, 1]))
        XCTAssertEqual(state.turn, anna)
    }

    func testKaeseCompletesWhenEveryEdgeIsDrawnAndCountsTheWinner() {
        // Alternate through all 12 edges of the 2×2 board in index order.
        var moves: [(String, Int)] = []
        var turn = anna
        var state = Kaesekaestchen.reduce(moves: [], size: 2, starter: anna, partner: ben)
        for edge in 0..<12 {
            moves.append((turn, edge))
            state = Kaesekaestchen.reduce(moves: moves, size: 2, starter: anna, partner: ben)
            turn = state.turn
        }
        XCTAssertTrue(state.complete)
        XCTAssertEqual((state.scores[anna] ?? 0) + (state.scores[ben] ?? 0), 4)
        if state.scores[anna] == state.scores[ben] {
            XCTAssertNil(state.winner)
        } else {
            XCTAssertNotNil(state.winner)
        }
    }

    // MARK: - Gomoku

    func testGomokuAlternatesAndSkipsOccupiedIntersections() {
        let state = Gomoku.reduce(placements: [(anna, 0), (ben, 0), (ben, 30), (anna, 1)],
                                  starter: anna, partner: ben)
        XCTAssertEqual(state.placed, 3)
        XCTAssertEqual(state.board[0], anna)
        XCTAssertEqual(state.board[30], ben)
        XCTAssertEqual(state.turn, ben)
    }

    func testGomokuExactlyFiveWinsWithHighlightRun() {
        let placements: [(String, Int)] = [
            (anna, 0), (ben, 30), (anna, 1), (ben, 32), (anna, 2), (ben, 34),
            (anna, 3), (ben, 36), (anna, 4),
        ]
        let state = Gomoku.reduce(placements: placements, starter: anna, partner: ben)
        XCTAssertEqual(state.winner, anna)
        XCTAssertEqual(state.winningRun, [0, 1, 2, 3, 4])
        // Moves after the win are ignored.
        let after = Gomoku.reduce(placements: placements + [(ben, 40)],
                                  starter: anna, partner: ben)
        XCTAssertEqual(after.placed, 9)
    }

    func testGomokuOverlineOfSixDoesNotWin() {
        // Anna builds 0,1,2,3,5 and then fills the gap at 4 → six in a row.
        let placements: [(String, Int)] = [
            (anna, 0), (ben, 30), (anna, 1), (ben, 32), (anna, 2), (ben, 34),
            (anna, 3), (ben, 36), (anna, 5), (ben, 38), (anna, 4),
        ]
        let state = Gomoku.reduce(placements: placements, starter: anna, partner: ben)
        XCTAssertNil(state.winner, "an overline of six is NOT a win")
        XCTAssertTrue(state.winningRun.isEmpty)
    }

    func testGomokuDiagonalFiveWins() {
        let placements: [(String, Int)] = [
            (anna, 0), (ben, 1), (anna, 16), (ben, 2), (anna, 32), (ben, 3),
            (anna, 48), (ben, 5), (anna, 64),
        ]
        let state = Gomoku.reduce(placements: placements, starter: anna, partner: ben)
        XCTAssertEqual(state.winner, anna)
        XCTAssertEqual(state.winningRun, [0, 16, 32, 48, 64])
    }

    func testGomokuFullBoardWithoutWinnerIsADraw() {
        var state = Gomoku.reduce(placements: [], starter: anna, partner: ben)
        XCTAssertFalse(state.draw)
        state.placed = Gomoku.squares
        XCTAssertTrue(state.draw)
    }

    // MARK: - Mancala

    func testMancalaSowLandingInOwnStoreGrantsExtraTurn() {
        let state = Mancala.reduce(sows: [(anna, 2)], stones: 4, starter: anna, partner: ben)
        XCTAssertEqual(state.pits[anna], [4, 4, 0, 5, 5, 5])
        XCTAssertEqual(state.stores[anna], 1)
        XCTAssertEqual(state.turn, anna, "last stone in the own store keeps the turn")
    }

    func testMancalaSowCrossesIntoOpponentPitsAndPassesTheTurn() {
        let state = Mancala.reduce(sows: [(anna, 2), (anna, 5)], stones: 4,
                                   starter: anna, partner: ben)
        XCTAssertEqual(state.pits[anna], [4, 4, 0, 5, 5, 0])
        XCTAssertEqual(state.stores[anna], 2)
        XCTAssertEqual(state.pits[ben], [5, 5, 5, 5, 4, 4])
        XCTAssertEqual(state.turn, ben)
    }

    func testMancalaLastStoneInOwnEmptyPitCapturesTheOppositePit() {
        var pits = [anna: [1, 0, 4, 4, 4, 4], ben: [4, 4, 4, 4, 6, 4]]
        var stores = [anna: 0, ben: 0]
        let outcome = Mancala.sow(pits: &pits, stores: &stores, me: anna, them: ben, pit: 0)
        XCTAssertEqual(outcome.captured, 7, "landing stone + opposite pit 5-1=4 (6 stones)")
        XCTAssertEqual(stores[anna], 7)
        XCTAssertEqual(pits[anna]?[1], 0)
        XCTAssertEqual(pits[ben]?[4], 0)
        XCTAssertFalse(outcome.extraTurn)
    }

    func testMancalaOpponentStoreIsSkippedOnFullLaps() {
        // 13 stones lap the whole track exactly once and land back in the
        // now-empty origin pit — the opponent store never receives a stone.
        var pits = [anna: [13, 4, 4, 4, 4, 4], ben: [4, 4, 4, 4, 4, 2]]
        var stores = [anna: 0, ben: 0]
        let outcome = Mancala.sow(pits: &pits, stores: &stores, me: anna, them: ben, pit: 0)
        XCTAssertEqual(stores[ben], 0, "the opponent store is skipped")
        XCTAssertEqual(outcome.captured, 4, "landing stone + opposite pit (2+1 sown)")
        XCTAssertEqual(stores[anna], 1 + 4)
        XCTAssertEqual(pits[ben]?.map { $0 }, [5, 5, 5, 5, 5, 0])
    }

    func testMancalaSweepEndsTheGame() {
        var pits = [anna: [0, 0, 0, 0, 0, 1], ben: [2, 0, 0, 0, 0, 0]]
        var stores = [anna: 3, ben: 1]
        let outcome = Mancala.sow(pits: &pits, stores: &stores, me: anna, them: ben, pit: 5)
        XCTAssertTrue(outcome.swept)
        XCTAssertEqual(stores[anna], 4)
        XCTAssertEqual(stores[ben], 3, "the other side sweeps its remaining stones")
        XCTAssertEqual(pits[anna], [0, 0, 0, 0, 0, 0])
        XCTAssertEqual(pits[ben], [0, 0, 0, 0, 0, 0])
    }

    func testMancalaReduceSkipsEmptyPitsAndOutOfTurnSows() {
        // Pit 2 grants an extra turn, then sowing the now-empty pit 2 and a
        // ben move out of turn are both skipped (server: 409 empty_pit).
        let state = Mancala.reduce(sows: [(anna, 2), (ben, 0), (anna, 2), (anna, 0)],
                                   stones: 4, starter: anna, partner: ben)
        XCTAssertEqual(state.pits[anna], [0, 5, 1, 6, 6, 5])
        XCTAssertEqual(state.turn, ben)
        XCTAssertEqual(state.pits[ben], [4, 4, 4, 4, 4, 4])
    }

    func testMancalaPreviewMirrorsTheSowWithoutMutatingTheState() {
        let state = Mancala.reduce(sows: [], stones: 4, starter: anna, partner: ben)
        let preview = Mancala.preview(state: state, member: anna, pit: 2)
        XCTAssertEqual(preview?.outcome.extraTurn, true)
        XCTAssertEqual(preview?.state.stores[anna], 1)
        XCTAssertEqual(state.stores[anna], 0, "preview must not mutate")
        XCTAssertNil(Mancala.preview(state: state, member: ben, pit: 0),
                     "no preview out of turn")
    }

    func testMancalaWinnerIsTheStoreMajority() {
        var state = Mancala.reduce(sows: [], stones: 4, starter: anna, partner: ben)
        XCTAssertNil(state.winner)
        state.complete = true
        state.stores = [anna: 30, ben: 18]
        XCTAssertEqual(state.winner, anna)
        state.stores = [anna: 24, ben: 24]
        XCTAssertNil(state.winner, "equal stores draw")
    }

    // MARK: - Memory-Duo

    func testMemoryDuoFirstFlipStaysOpenAndRemembersTheFace() {
        let state = MemoryDuo.reduce(flips: [(anna, 7, 3)], cards: 36,
                                     starter: anna, partner: ben)
        XCTAssertEqual(state.open, 7)
        XCTAssertEqual(state.faces[7], 3)
        XCTAssertEqual(state.turn, anna)
    }

    func testMemoryDuoMatchScoresAndKeepsTheTurn() {
        let state = MemoryDuo.reduce(flips: [(anna, 7, 3), (anna, 12, 3)], cards: 36,
                                     starter: anna, partner: ben)
        XCTAssertEqual(state.matched[7], anna)
        XCTAssertEqual(state.matched[12], anna)
        XCTAssertEqual(state.scores[anna], 1)
        XCTAssertEqual(state.turn, anna)
        XCTAssertNil(state.open)
    }

    func testMemoryDuoMissPassesTheTurnButFacesStayKnown() {
        let state = MemoryDuo.reduce(flips: [(anna, 1, 2), (anna, 2, 9)], cards: 36,
                                     starter: anna, partner: ben)
        XCTAssertEqual(state.turn, ben)
        XCTAssertEqual(state.faces[1], 2, "everything once flipped stays visible")
        XCTAssertEqual(state.faces[2], 9)
        XCTAssertNil(state.matched[1])
    }

    func testMemoryDuoSkipsMatchedCardsAndTheOpenCardItself() {
        let flips: [(String, Int, Int)] = [
            (anna, 0, 5), (anna, 1, 5),   // match — anna keeps the turn
            (anna, 0, 5),                 // already matched → skipped
            (anna, 4, 9), (anna, 4, 9),   // same card twice → second skipped
        ]
        let state = MemoryDuo.reduce(flips: flips, cards: 36, starter: anna, partner: ben)
        XCTAssertEqual(state.scores[anna], 1)
        XCTAssertEqual(state.open, 4)
        XCTAssertEqual(state.turn, anna)
    }

    func testMemoryDuoOutOfTurnFlipsAreSkipped() {
        let state = MemoryDuo.reduce(flips: [(ben, 0, 1), (anna, 3, 2)], cards: 36,
                                     starter: anna, partner: ben)
        XCTAssertNil(state.faces[0])
        XCTAssertEqual(state.open, 3)
    }

    func testMemoryDuoCompletesWhenAllPairsAreMatched() {
        let flips: [(String, Int, Int)] = [
            (anna, 0, 0), (anna, 1, 0),
            (anna, 2, 1), (anna, 3, 1),
        ]
        let state = MemoryDuo.reduce(flips: flips, cards: 4, starter: anna, partner: ben)
        XCTAssertTrue(state.complete)
        XCTAssertEqual(state.winner, anna)
        XCTAssertEqual(state.scores[anna], 2)
    }

    func testMemoryDuoTieHasNoWinner() {
        let flips: [(String, Int, Int)] = [
            (anna, 0, 0), (anna, 1, 0),   // anna pairs, keeps turn
            (anna, 2, 1), (anna, 3, 2),   // miss → ben
            (ben, 2, 1), (ben, 4, 1),     // ben pairs 1 (cards 2+4)
            (ben, 3, 2), (ben, 5, 2),     // ben would lead 2:1… keep it a tie:
        ]
        let state = MemoryDuo.reduce(flips: Array(flips.prefix(6)), cards: 6,
                                     starter: anna, partner: ben)
        XCTAssertEqual(state.scores[anna], 1)
        XCTAssertEqual(state.scores[ben], 1)
        XCTAssertFalse(state.complete)
    }
}
