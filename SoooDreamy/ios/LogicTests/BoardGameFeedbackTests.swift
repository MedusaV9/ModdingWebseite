import XCTest
@testable import SoooDreamyLogic

final class BoardGameFeedbackTests: XCTestCase {

    // MARK: Käsekästchen spatial edge names

    func testHorizontalEdgesDescribeTopAndBottomOfNamedBoxes() {
        // 3×3 board: edge 0 is the top edge of box A1 (row 0, col 0).
        XCTAssertEqual(BoardGameFeedback.kaeseEdgeDescription(size: 3, edge: 0),
                       KaeseEdgeDescription(side: .top, square: "A1"))
        // Row 1 horizontal edges are the TOP of the second box row.
        XCTAssertEqual(BoardGameFeedback.kaeseEdgeDescription(size: 3, edge: 4),
                       KaeseEdgeDescription(side: .top, square: "B2"))
        // The last horizontal row borders no box below → bottom of row 3.
        XCTAssertEqual(BoardGameFeedback.kaeseEdgeDescription(size: 3, edge: 11),
                       KaeseEdgeDescription(side: .bottom, square: "C3"))
    }

    func testVerticalEdgesDescribeLeftAndRightOfNamedBoxes() {
        let base = 3 * 4 // horizontal edges of a 3×3 board
        XCTAssertEqual(BoardGameFeedback.kaeseEdgeDescription(size: 3, edge: base),
                       KaeseEdgeDescription(side: .left, square: "A1"))
        // Column 3 (the rim) is the RIGHT edge of the last box in the row.
        XCTAssertEqual(BoardGameFeedback.kaeseEdgeDescription(size: 3, edge: base + 3),
                       KaeseEdgeDescription(side: .right, square: "C1"))
        XCTAssertEqual(BoardGameFeedback.kaeseEdgeDescription(size: 3, edge: base + 5),
                       KaeseEdgeDescription(side: .left, square: "B2"))
    }

    func testEveryEdgeOfEverySizeHasExactlyOneName() {
        for size in [3, 4, 5, 6] {
            let total = Kaesekaestchen.edgeCount(size: size)
            var names: Set<String> = []
            for edge in 0..<total {
                guard let description = BoardGameFeedback.kaeseEdgeDescription(size: size, edge: edge) else {
                    return XCTFail("edge \(edge) of size \(size) has no name")
                }
                names.insert("\(description.side.rawValue)#\(description.square)")
            }
            XCTAssertEqual(names.count, total, "size \(size) edge names must be unique")
            XCTAssertNil(BoardGameFeedback.kaeseEdgeDescription(size: size, edge: total))
        }
    }

    // MARK: Mancala sowing plan (read-only twin of Mancala.sow)

    func testSowPlanMatchesTheReducerOutcome() {
        let start = [4, 4, 4, 4, 4, 4]
        var pits = ["a": start, "b": start]
        var stores = ["a": 0, "b": 0]
        guard let plan = BoardGameFeedback.mancalaSowPlan(ownPits: start,
                                                          theirPits: start, pit: 2) else {
            return XCTFail("expected a plan for a filled pit")
        }
        let outcome = Mancala.sow(pits: &pits, stores: &stores, me: "a", them: "b", pit: 2)
        XCTAssertEqual(plan.landsInStore, outcome.extraTurn)
        XCTAssertEqual(plan.capturedStones, outcome.captured)
        XCTAssertEqual(plan.storeGain + plan.capturedStones, stores["a"])
        // Rebuilding the board from the plan's per-pit gains reproduces the
        // reducer's mutation exactly (no capture in this scenario).
        XCTAssertEqual((0..<6).map { ($0 == 2 ? 0 : start[$0]) + plan.ownGains[$0] },
                       pits["a"])
        XCTAssertEqual((0..<6).map { start[$0] + plan.theirGains[$0] }, pits["b"])
    }

    func testSowPlanPredictsCapture() {
        // Own pit 4 holds 1 stone → lands in own empty pit 5? No: sow from
        // pit 4 drops into pit 5. Make pit 5 empty and give the opposite
        // opponent pit (index 0) three stones.
        let plan = BoardGameFeedback.mancalaSowPlan(ownPits: [4, 4, 4, 4, 1, 0],
                                                    theirPits: [3, 4, 4, 4, 4, 4], pit: 4)
        XCTAssertEqual(plan?.landingOwnPit, 5)
        XCTAssertEqual(plan?.capturedOpponentPit, 0)
        XCTAssertEqual(plan?.capturedStones, 4)
        XCTAssertEqual(plan?.landsInStore, false)
    }

    func testSowPlanPredictsExtraTurn() {
        // Two stones from pit 4 end exactly in the store.
        let plan = BoardGameFeedback.mancalaSowPlan(ownPits: [4, 4, 4, 4, 2, 0],
                                                    theirPits: [4, 4, 4, 4, 4, 4], pit: 4)
        XCTAssertEqual(plan?.landsInStore, true)
        XCTAssertEqual(plan?.storeGain, 1)
        XCTAssertEqual(plan?.capturedStones, 0)
        XCTAssertNil(plan?.landingOwnPit)
    }

    func testSowPlanRejectsEmptyAndOutOfRangePits() {
        XCTAssertNil(BoardGameFeedback.mancalaSowPlan(ownPits: [0, 4, 4, 4, 4, 4],
                                                      theirPits: [4, 4, 4, 4, 4, 4], pit: 0))
        XCTAssertNil(BoardGameFeedback.mancalaSowPlan(ownPits: [4, 4, 4, 4, 4, 4],
                                                      theirPits: [4, 4, 4, 4, 4, 4], pit: 6))
    }

    func testMemoryPacingKeepsTheMismatchPauseReadable() {
        XCTAssertGreaterThanOrEqual(BoardGameFeedback.memoryMismatchPause, 0.6)
        XCTAssertGreaterThan(BoardGameFeedback.memoryMismatchPause,
                             BoardGameFeedback.memoryMatchPause)
    }
}
