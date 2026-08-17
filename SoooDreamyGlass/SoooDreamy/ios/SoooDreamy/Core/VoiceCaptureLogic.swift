import Foundation

/// Pure decision rules for the voice-note recorder (Linse 27). The recorder
/// itself (AVFoundation) lives in the app target — the rules that guard
/// against data loss are Foundation-only so the Linux LogicTests can pin them.
enum VoiceCaptureGuard {
    /// Takes shorter than this are accidental taps, not messages.
    static let minimumSendableSeconds: Double = 0.5

    /// The recorder sheet may only vanish silently when nothing worth
    /// keeping would be lost: a finished take always asks first, and an
    /// in-flight recording asks once it's long enough to be a real take.
    static func dismissNeedsConfirmation(hasFinishedTake: Bool,
                                         isRecording: Bool,
                                         elapsed: Double) -> Bool {
        if hasFinishedTake { return true }
        return isRecording && elapsed >= minimumSendableSeconds
    }

    /// A phone call or Siri ends the take CLEANLY: real takes are kept
    /// (previewable, sendable), sub-threshold blips are dropped so the
    /// mic simply re-arms.
    static func keepTakeAfterInterruption(elapsed: Double) -> Bool {
        elapsed >= minimumSendableSeconds
    }
}
