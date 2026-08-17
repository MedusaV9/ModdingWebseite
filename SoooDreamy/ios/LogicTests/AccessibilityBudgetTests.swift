import XCTest
@testable import SoooDreamyLogic

final class AccessibilityBudgetTests: XCTestCase {
    func testReduceMotionRemovesParticlesAtEveryIntensity() {
        for intensity in [DelightIntensity.small, .medium, .epic] {
            XCTAssertEqual(AccessibilityBudget.particleLimit(
                intensity: intensity,
                reduceMotion: true,
                accessibilityText: false
            ), 0)
        }
    }

    func testAccessibilityTextCapsEpicParticleWork() {
        XCTAssertEqual(AccessibilityBudget.particleLimit(
            intensity: .epic,
            reduceMotion: false,
            accessibilityText: true
        ), 32)
        XCTAssertEqual(AccessibilityBudget.particleLimit(
            intensity: .epic,
            reduceMotion: false,
            accessibilityText: false
        ), 64)
    }

    func testVerticalLayoutPolicyCoversLargeTextAndNarrowPhones() {
        XCTAssertTrue(AccessibilityBudget.prefersVerticalLayout(
            accessibilityText: true, availableWidth: 430
        ))
        XCTAssertTrue(AccessibilityBudget.prefersVerticalLayout(
            accessibilityText: false, availableWidth: 320
        ))
        XCTAssertFalse(AccessibilityBudget.prefersVerticalLayout(
            accessibilityText: false, availableWidth: 390
        ))
    }

    // MARK: Grid columns under Dynamic Type (EVAL AX5)

    func testGridsKeepTheirColumnsOutsideAccessibilitySizes() {
        XCTAssertEqual(AccessibilityBudget.gridColumns(regular: 3, accessibilityLevel: 0), 3)
        XCTAssertEqual(AccessibilityBudget.gridColumns(regular: 2, accessibilityLevel: 0), 2)
    }

    func testGridsCollapseToTwoColumnsAtEarlyAccessibilitySizes() {
        // AX1/AX2: labels still fit two abreast — the 3-column touch grid
        // drops to 2 before its captions shatter into single letters.
        for level in 1...2 {
            XCTAssertEqual(AccessibilityBudget.gridColumns(regular: 3, accessibilityLevel: level), 2)
            XCTAssertEqual(AccessibilityBudget.gridColumns(regular: 6, accessibilityLevel: level), 2)
        }
    }

    func testGridsCollapseToASingleColumnAtGiantSizes() {
        // AX3…AX5: one full-width row per item — nothing may truncate.
        for level in 3...5 {
            XCTAssertEqual(AccessibilityBudget.gridColumns(regular: 3, accessibilityLevel: level), 1)
            XCTAssertEqual(AccessibilityBudget.gridColumns(regular: 2, accessibilityLevel: level), 1)
        }
    }

    func testSingleColumnGridsNeverGainColumns() {
        for level in 0...5 {
            XCTAssertEqual(AccessibilityBudget.gridColumns(regular: 1, accessibilityLevel: level), 1)
        }
    }
}
