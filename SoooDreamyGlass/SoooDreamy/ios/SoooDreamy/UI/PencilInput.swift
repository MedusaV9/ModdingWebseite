import SwiftUI
import UIKit

/// One raw Apple-Pencil reading: force normalized against
/// `maximumPossibleForce` (0…1) plus the barrel altitude in radians.
/// The mapping to stroke widths lives in `PencilInputRules` (pure, tested).
struct PencilSample: Equatable {
    var normalizedForce: Double
    var altitude: Double
}

/// Passive UIKit touch probe riding alongside the SwiftUI draw gesture:
/// it NEVER recognizes (stays in `.possible`), never delays or cancels
/// touches and never prevents another recognizer — it only reports what
/// kind of touch is on the surface and, for the pencil, how hard it
/// presses. SwiftUI's `DragGesture` cannot see `UITouch` properties;
/// this probe is the sanctioned bridge (iOS 18+ representable below).
final class PencilProbeRecognizer: UIGestureRecognizer {
    var onPencilSample: ((PencilSample) -> Void)?
    /// Pencil contact began/ended (any number of pencil touches).
    var onPencilContactChanged: ((Bool) -> Void)?
    /// Fired once per pencil touch-down — the palm-rejection trigger.
    var onPencilLanded: (() -> Void)?

    private var activePencilTouches = 0

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches where touch.type == .pencil {
            activePencilTouches += 1
            report(touch)
            onPencilLanded?()
        }
        if activePencilTouches > 0 { onPencilContactChanged?(true) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches where touch.type == .pencil {
            report(touch)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        release(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        release(touches)
    }

    /// The probe is an observer, never a participant in gesture arbitration.
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    private func release(_ touches: Set<UITouch>) {
        for touch in touches where touch.type == .pencil {
            activePencilTouches = max(activePencilTouches - 1, 0)
        }
        if activePencilTouches == 0 { onPencilContactChanged?(false) }
    }

    private func report(_ touch: UITouch) {
        let maxForce = touch.maximumPossibleForce
        let normalized = maxForce > 0 ? Double(touch.force / maxForce) : 0
        onPencilSample?(PencilSample(normalizedForce: normalized,
                                     altitude: Double(touch.altitudeAngle)))
    }
}

/// SwiftUI wrapper for the probe — attach with `.gesture(PencilProbe(…))`
/// next to the existing draw gesture. NOTE the overload choice:
/// `UIGestureRecognizerRepresentable` does NOT conform to `Gesture`, so
/// `simultaneousGesture(_:)` cannot take it (Xcode-26 build error);
/// representables ride their own `gesture(_:)` overload (the WWDC24
/// "What's new in SwiftUI" pattern) and arbitrate on the UIKit side.
/// Simultaneity is guaranteed there twice over: the coordinator-delegate
/// answers `shouldRecognizeSimultaneouslyWith` with `true` for every
/// pairing, and the recognizer itself never recognizes, delays or
/// prevents — the drag pipeline stays untouched, the probe only feeds
/// pressure, contact state and the palm-rejection trigger.
struct PencilProbe: UIGestureRecognizerRepresentable {
    var onSample: (PencilSample) -> Void
    var onContactChanged: (Bool) -> Void
    var onPencilLanded: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> PencilProbeRecognizer {
        let recognizer = PencilProbeRecognizer()
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        // UIKit-level simultaneity: without a delegate the system could
        // still sequence other recognizers against this one.
        recognizer.delegate = context.coordinator
        apply(to: recognizer)
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: PencilProbeRecognizer, context: Context) {
        apply(to: recognizer)
    }

    func handleUIGestureRecognizerAction(_ recognizer: PencilProbeRecognizer, context: Context) {
        // Callback-driven: the passive recognizer never fires actions.
    }

    private func apply(to recognizer: PencilProbeRecognizer) {
        recognizer.onPencilSample = onSample
        recognizer.onPencilContactChanged = onContactChanged
        recognizer.onPencilLanded = onPencilLanded
    }

    /// Delegate half of "run alongside everything, block nothing".
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
