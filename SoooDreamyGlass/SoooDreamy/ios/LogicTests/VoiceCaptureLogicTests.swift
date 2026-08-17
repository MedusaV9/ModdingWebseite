import Foundation
import XCTest
@testable import SoooDreamyLogic

final class VoiceCaptureLogicTests: XCTestCase {
    func testFinishedTakeAlwaysAsksBeforeDismissing() {
        XCTAssertTrue(VoiceCaptureGuard.dismissNeedsConfirmation(
            hasFinishedTake: true, isRecording: false, elapsed: 0))
        XCTAssertTrue(VoiceCaptureGuard.dismissNeedsConfirmation(
            hasFinishedTake: true, isRecording: false, elapsed: 42))
    }

    func testInFlightRecordingAsksOnceItIsARealTake() {
        XCTAssertFalse(VoiceCaptureGuard.dismissNeedsConfirmation(
            hasFinishedTake: false, isRecording: true, elapsed: 0.2),
            "a sub-second blip may be dropped silently")
        XCTAssertTrue(VoiceCaptureGuard.dismissNeedsConfirmation(
            hasFinishedTake: false, isRecording: true,
            elapsed: VoiceCaptureGuard.minimumSendableSeconds))
        XCTAssertTrue(VoiceCaptureGuard.dismissNeedsConfirmation(
            hasFinishedTake: false, isRecording: true, elapsed: 30))
    }

    func testArmedSheetDismissesFreely() {
        XCTAssertFalse(VoiceCaptureGuard.dismissNeedsConfirmation(
            hasFinishedTake: false, isRecording: false, elapsed: 0))
    }

    func testInterruptionKeepsRealTakesAndDropsBlips() {
        XCTAssertFalse(VoiceCaptureGuard.keepTakeAfterInterruption(elapsed: 0.1))
        XCTAssertTrue(VoiceCaptureGuard.keepTakeAfterInterruption(
            elapsed: VoiceCaptureGuard.minimumSendableSeconds))
        XCTAssertTrue(VoiceCaptureGuard.keepTakeAfterInterruption(elapsed: 90))
    }
}
