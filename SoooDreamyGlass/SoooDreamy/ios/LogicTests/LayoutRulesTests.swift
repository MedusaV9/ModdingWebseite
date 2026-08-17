import XCTest
@testable import SoooDreamyLogic

/// Pins the container-width rules behind the responsive layout — the same
/// function now drives phones AND iPad windows (full screen, Split View,
/// Slide Over), so its clamps are load-bearing.
final class LayoutRulesTests: XCTestCase {
    func testDesignWidthIsScaleOne() {
        XCTAssertEqual(LayoutRules.scale(forWidth: LayoutRules.designWidth), 1.0)
    }

    func testWiderContainersNeverScaleUp() {
        // iPad windows: portrait 11", landscape 13", Stage Manager tiles.
        for width in [672.0, 834.0, 1032.0, 1376.0] {
            XCTAssertEqual(LayoutRules.scale(forWidth: width), LayoutRules.maxScale,
                           "width \(width) must stay at the design baseline")
        }
    }

    func testNarrowSplitViewClampsAtMinScale() {
        // The narrowest Slide Over / 1/3-split slots.
        XCTAssertEqual(LayoutRules.scale(forWidth: 320), LayoutRules.minScale)
        XCTAssertEqual(LayoutRules.scale(forWidth: 280), LayoutRules.minScale)
    }

    func testStandardPhoneGetsCompression() {
        // iPhone 16 (393 pt) sits under the compression threshold.
        let expected = 393.0 / LayoutRules.designWidth * LayoutRules.compressionFactor
        XCTAssertEqual(LayoutRules.scale(forWidth: 393), expected, accuracy: 0.0001)
        // A width at the threshold gets NO compression.
        XCTAssertEqual(LayoutRules.scale(forWidth: 410), 410.0 / LayoutRules.designWidth,
                       accuracy: 0.0001)
    }

    func testScaleIsMonotonicAcrossTheThreshold() {
        var last = 0.0
        for width in stride(from: 250.0, through: 1400.0, by: 1.0) {
            let value = LayoutRules.scale(forWidth: width)
            XCTAssertGreaterThanOrEqual(value + 0.0001, last,
                                        "scale must never shrink as the window grows (at \(width))")
            last = value
        }
    }

    func testZeroAndNegativeWidthsFallBackToBaseline() {
        XCTAssertEqual(LayoutRules.scale(forWidth: 0), 1.0)
        XCTAssertEqual(LayoutRules.scale(forWidth: -100), 1.0)
    }

    func testColumnWidthCapsAtMaximum() {
        XCTAssertEqual(LayoutRules.columnWidth(container: 1032, max: 640), 640)
        XCTAssertEqual(LayoutRules.columnWidth(container: 393, max: 640), 393)
        XCTAssertEqual(LayoutRules.columnWidth(container: 0, max: 640), 0)
    }

    func testCanvasSideRailNeedsARegularANDWidePane() {
        // Full-screen 11" landscape: rail on.
        XCTAssertTrue(LayoutRules.canvasUsesSideRail(paneWidth: 1180, isRegularWidth: true))
        // Regular size class but a narrow Stage-Manager tile: stacked layout.
        XCTAssertFalse(LayoutRules.canvasUsesSideRail(paneWidth: 640, isRegularWidth: true))
        // Phones are never regular here, however wide the number looks.
        XCTAssertFalse(LayoutRules.canvasUsesSideRail(paneWidth: 900, isRegularWidth: false))
    }

    func testMemoriesSidebarPersistsOnlyOnTrulyWidePanes() {
        // Full-screen iPad windows keep the persistent sidebar.
        XCTAssertTrue(LayoutRules.memoriesUsesPersistentSidebar(paneWidth: 1032,
                                                                isRegularWidth: true))
        XCTAssertTrue(LayoutRules.memoriesUsesPersistentSidebar(
            paneWidth: LayoutRules.memoriesSidebarMinWidth, isRegularWidth: true))
        // A ~half-split or narrow Stage-Manager tile collapses it.
        XCTAssertFalse(LayoutRules.memoriesUsesPersistentSidebar(paneWidth: 834,
                                                                 isRegularWidth: true))
        // Compact widths never see the sidebar at all.
        XCTAssertFalse(LayoutRules.memoriesUsesPersistentSidebar(paneWidth: 1200,
                                                                 isRegularWidth: false))
    }

    func testSchrankfrontSplitsIntoTwoColumnsOnWideCompactPanes() {
        // Phones (portrait and the compact landscape widths) stay a
        // single column of full-width drawer cards.
        XCTAssertFalse(LayoutRules.schrankfrontUsesTwoColumns(paneWidth: 393))
        XCTAssertFalse(LayoutRules.schrankfrontUsesTwoColumns(paneWidth: 440))
        // iPad half-splits that are still compact-width get two columns.
        XCTAssertTrue(LayoutRules.schrankfrontUsesTwoColumns(
            paneWidth: LayoutRules.schrankfrontTwoColumnMinWidth))
        XCTAssertTrue(LayoutRules.schrankfrontUsesTwoColumns(paneWidth: 639))
    }

    func testChatRailNeedsRoomForRailPlusReadingColumn() {
        // The rail must leave a full reading-width conversation behind:
        // rail + reading column + margin ≤ threshold.
        XCTAssertGreaterThanOrEqual(LayoutRules.chatRailMinWidth,
                                    LayoutRules.chatRailWidth + 640)
        // The rail itself sits in the 280–320 HIG band.
        XCTAssertGreaterThanOrEqual(LayoutRules.chatRailWidth, 280)
        XCTAssertLessThanOrEqual(LayoutRules.chatRailWidth, 320)
        // Full 11"/13" landscape panes carry the rail…
        XCTAssertTrue(LayoutRules.chatUsesRail(paneWidth: 1180, isRegularWidth: true))
        // …portrait 11" and split tiles keep the plain conversation…
        XCTAssertFalse(LayoutRules.chatUsesRail(paneWidth: 834, isRegularWidth: true))
        // …and compact width never gains a rail.
        XCTAssertFalse(LayoutRules.chatUsesRail(paneWidth: 1200, isRegularWidth: false))
    }

    // MARK: Bottom chrome (accessory + tab bar) clearances

    func testRestingClearanceKeepsContentOutOfTheRefractionBand() {
        // The resting margin is exactly accessory + breath — the token
        // the five tab roots feed into `contentMargins(.bottom, …)`.
        XCTAssertEqual(LayoutRules.restingBottomClearance,
                       LayoutRules.accessoryRestHeight + LayoutRules.glassEdgeBreath)
        // The breath is real: resting text clears MORE than the bare
        // accessory height, so the last line never kisses the glass rim.
        XCTAssertGreaterThan(LayoutRules.restingBottomClearance,
                             LayoutRules.accessoryRestHeight)
        XCTAssertGreaterThan(LayoutRules.glassEdgeBreath, 0)
    }

    // MARK: Accessory-Gate + AX-Clearance (Fix2-A №4)

    func testAccessoryStaysUnmountedAtAccessibilitySizes() {
        // At AX sizes the Zustellzettel + tab bar ate the content — the
        // accessory is not mounted there (RootView gate); regular sizes
        // keep it.
        XCTAssertTrue(LayoutRules.accessoryMounted(isAccessibilitySize: false))
        XCTAssertFalse(LayoutRules.accessoryMounted(isAccessibilitySize: true))
    }

    func testBottomClearanceIsCoupledToTheRealChromeHeight() {
        // Accessory mounted: the pinned classic value (accessory + breath).
        XCTAssertEqual(LayoutRules.restingBottomClearance(isAccessibilitySize: false),
                       LayoutRules.restingBottomClearance)
        // Accessory unmounted (AX): only the breath above the tab-bar
        // glass remains — grown type gets the accessory share back.
        XCTAssertEqual(LayoutRules.restingBottomClearance(isAccessibilitySize: true),
                       LayoutRules.glassEdgeBreath)
        XCTAssertLessThan(LayoutRules.restingBottomClearance(isAccessibilitySize: true),
                          LayoutRules.restingBottomClearance(isAccessibilitySize: false))
    }

    // MARK: Postfach clearance (Fix2-A №2 — the 💭 FAB lives in the flow)

    func testPostfachClearanceIsTheChromeCoupledRestingClearance() {
        // The pulse quick action no longer floats over the scroll
        // content, so no FAB zone rides on top of the chrome clearance —
        // both size regimes use exactly the resting clearance.
        for ax in [false, true] {
            XCTAssertEqual(LayoutRules.postfachBottomClearance(isAccessibilitySize: ax),
                           LayoutRules.restingBottomClearance(isAccessibilitySize: ax))
        }
    }

    func testCelebrationEmitterNeverDipsBelowTheChromeEdge() {
        // The emitter exclusion covers the WHOLE chrome stack (bar +
        // accessory + breath) — a heart may never spawn or drift behind
        // the glass.
        XCTAssertEqual(LayoutRules.celebrationBottomExclusion,
                       LayoutRules.tabBarRestHeight
                           + LayoutRules.accessoryRestHeight
                           + LayoutRules.glassEdgeBreath)
        XCTAssertGreaterThanOrEqual(
            LayoutRules.celebrationBottomExclusion,
            LayoutRules.tabBarRestHeight + LayoutRules.accessoryRestHeight)
        // Emitters must clear MORE than resting scroll content: scroll
        // safe areas already end at the accessory, the emitter field is
        // measured from the window's bottom safe-area edge.
        XCTAssertGreaterThan(LayoutRules.celebrationBottomExclusion,
                             LayoutRules.restingBottomClearance)
    }

    // MARK: „Sendung Nr. 1" centering air (re-eval №4)

    func testSendungLuftIsAModestPaneFraction() {
        // The sealed first Sendung floats toward the calm middle on a
        // PROPORTIONAL breath of air — never a fixed frame. The fraction
        // stays modest so grown type and the unfolded QR keep room below.
        XCTAssertGreaterThan(LayoutRules.sendungLuftAnteil, 0)
        XCTAssertLessThanOrEqual(LayoutRules.sendungLuftAnteil, 0.2)
    }
}
