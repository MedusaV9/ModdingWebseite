import XCTest
@testable import SoooDreamyLogic

/// Pins the Apple-Pencil pressure→width mapping. The wire format carries ONE
/// width per stroke and the live relay clamps widths at 32, so these bounds
/// are protocol-load-bearing, not just aesthetics.
final class PencilInputRulesTests: XCTestCase {
    func testAveragePressDrawsTheChosenWidth() {
        // UITouch.force == 1 (an average press) is ≈ 0.24 of the pencil's
        // maximumPossibleForce — that grip must map to factor 1.0.
        let factor = PencilInputRules.widthFactor(normalizedForce: 0.24)
        XCTAssertEqual(factor, 1.0, accuracy: 0.001)
    }

    func testFactorStaysInsideBounds() {
        for force in stride(from: 0.0, through: 1.0, by: 0.05) {
            for altitude in stride(from: 0.0, through: PencilInputRules.verticalAltitude, by: 0.1) {
                let factor = PencilInputRules.widthFactor(normalizedForce: force, altitude: altitude)
                XCTAssertGreaterThanOrEqual(factor, PencilInputRules.minFactor)
                XCTAssertLessThanOrEqual(factor, PencilInputRules.maxFactor)
            }
        }
    }

    func testHarderPressNeverThinsTheLine() {
        var last = 0.0
        for force in stride(from: 0.0, through: 1.0, by: 0.01) {
            let factor = PencilInputRules.widthFactor(normalizedForce: force)
            XCTAssertGreaterThanOrEqual(factor + 0.0001, last,
                                        "width factor must grow with force (at \(force))")
            last = factor
        }
    }

    func testTiltBroadensTheLine() {
        // Shading with the pencil's side (small altitude) must widen the
        // stroke compared to the same force held upright.
        let upright = PencilInputRules.widthFactor(normalizedForce: 0.24)
        let leaning = PencilInputRules.widthFactor(normalizedForce: 0.24, altitude: 0.2)
        XCTAssertGreaterThan(leaning, upright)
    }

    func testWidestToolStaysUnderTheRelayClamp() {
        // The widest slider setting is 16; even a full-force, fully leaned
        // stroke must stay below the relay's width clamp of 32.
        let width = PencilInputRules.effectiveWidth(base: 16, normalizedForce: 1, altitude: 0)
        XCTAssertLessThanOrEqual(width, 32)
    }

    func testFingerStrokesKeepTheBaseWidth() {
        XCTAssertEqual(PencilInputRules.effectiveWidth(base: 6, normalizedForce: nil), 6)
        XCTAssertEqual(PencilInputRules.effectiveWidth(base: 6, normalizedForce: 0), 6)
    }

    func testFeatherLightStrokesStayVisible() {
        let width = PencilInputRules.effectiveWidth(base: 2, normalizedForce: 0.01)
        XCTAssertGreaterThanOrEqual(width, 1)
    }

    func testPreviewMirrorsTheRendererMultipliers() {
        // StrokeRenderer paints markers/erasers at 2.5×, glow at 1.6× —
        // the hover preview must show that same footprint.
        XCTAssertEqual(PencilInputRules.previewLineWidth(tool: "marker", width: 4), 10)
        XCTAssertEqual(PencilInputRules.previewLineWidth(tool: "eraser", width: 4), 10)
        XCTAssertEqual(PencilInputRules.previewLineWidth(tool: "glow", width: 5), 8)
        XCTAssertEqual(PencilInputRules.previewLineWidth(tool: "pen", width: 4), 4)
        XCTAssertEqual(PencilInputRules.previewLineWidth(tool: "heart", width: 7), 7)
    }

    func testPalmRejectionDropsFingerStrokesWhenThePencilLands() {
        // A finger stroke in flight + pencil touch-down = resting palm.
        XCTAssertTrue(PencilInputRules.discardsActiveStroke(strokeIsPencil: false,
                                                            pencilJustLanded: true))
        // Pencil-started strokes are never the palm.
        XCTAssertFalse(PencilInputRules.discardsActiveStroke(strokeIsPencil: true,
                                                             pencilJustLanded: true))
        // No pencil, no rejection — finger drawing stays first-class.
        XCTAssertFalse(PencilInputRules.discardsActiveStroke(strokeIsPencil: false,
                                                             pencilJustLanded: false))
    }

    func testStartWindowIsShortEnoughToFeelInstant() {
        // The width locks within the first few points; anything longer would
        // visibly repaint the stroke (one width per stroke on the wire).
        XCTAssertLessThanOrEqual(PencilInputRules.startWindowPoints, 8)
        XCTAssertGreaterThan(PencilInputRules.startWindowPoints, 0)
    }
}
