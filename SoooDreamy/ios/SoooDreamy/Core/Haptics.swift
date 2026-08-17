import Foundation
import CoreHaptics
import UIKit

/// CoreHaptics wrapper: expressive patterns per touch type + simple feedback.
@MainActor
final class Haptics {
    static let shared = Haptics()

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "sooodreamy.hapticsEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "sooodreamy.hapticsEnabled") }
    }

    /// True on real iPhones with a Taptic Engine — false in the simulator
    /// and on most iPads (the studio shows an honesty hint then).
    static var deviceSupportsHaptics: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    private var engine: CHHapticEngine?
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    private init() {}

    func prepare() {
        guard supportsHaptics, engine == nil else { return }
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            engine.resetHandler = { [weak self] in
                Task { @MainActor in try? self?.engine?.start() }
            }
            try engine.start()
            self.engine = engine
        } catch {
            engine = nil
        }
    }

    // MARK: Simple feedback

    func tap() {
        guard Self.enabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    func success() {
        guard Self.enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func warning() {
        guard Self.enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    // MARK: Touch patterns

    func play(_ kind: TouchKind) {
        guard Self.enabled else { return }
        guard supportsHaptics else {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            return
        }
        prepare()
        guard let engine else { return }
        do {
            let pattern = try Self.pattern(for: kind)
            let player = try engine.makePlayer(with: pattern)
            try engine.start()
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    private static func transient(_ time: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient,
                      parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
                      ],
                      relativeTime: time)
    }

    private static func continuous(_ time: TimeInterval, duration: TimeInterval,
                                   intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticContinuous,
                      parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
                      ],
                      relativeTime: time, duration: duration)
    }

    // MARK: Composed patterns (haptics composer)

    /// Plays a recorded/preset timeline. Feeds the AHAP JSON straight into
    /// CoreHaptics (`playPattern(from:)` consumes the AHAP format); falls
    /// back to hand-built events, then to a plain impact on old hardware.
    func play(events: [HapticEventSpec]) {
        guard Self.enabled, !events.isEmpty else { return }
        guard supportsHaptics else {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            return
        }
        prepare()
        guard let engine else { return }
        do {
            try engine.start()
            try engine.playPattern(from: HapticAHAP.data(events: events))
        } catch {
            let chEvents = events.map { ev in
                ev.d > 0
                    ? Self.continuous(ev.t, duration: ev.d, intensity: Float(ev.i), sharpness: Float(ev.s))
                    : Self.transient(ev.t, intensity: Float(ev.i), sharpness: Float(ev.s))
            }
            if let pattern = try? CHHapticPattern(events: chEvents, parameters: []),
               let player = try? engine.makePlayer(with: pattern) {
                try? player.start(atTime: CHHapticTimeImmediate)
            } else {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
    }

    /// Single live tick while recording on the composer pad.
    func composerTick(intensity: Double) {
        guard Self.enabled else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: intensity)
    }

    private static func pattern(for kind: TouchKind) throws -> CHHapticPattern {
        let events: [CHHapticEvent]
        switch kind {
        case .heartbeat:
            // lub-dub … lub-dub
            events = [
                transient(0.00, intensity: 1.0, sharpness: 0.30),
                transient(0.18, intensity: 0.65, sharpness: 0.20),
                transient(0.75, intensity: 1.0, sharpness: 0.30),
                transient(0.93, intensity: 0.65, sharpness: 0.20)
            ]
        case .kiss:
            events = [
                continuous(0.00, duration: 0.18, intensity: 0.5, sharpness: 0.15),
                transient(0.22, intensity: 0.9, sharpness: 0.65)
            ]
        case .hug:
            events = [
                continuous(0.00, duration: 1.3, intensity: 0.85, sharpness: 0.08),
                transient(1.35, intensity: 0.5, sharpness: 0.2)
            ]
        case .missyou:
            events = [
                transient(0.00, intensity: 0.55, sharpness: 0.25),
                transient(0.30, intensity: 0.45, sharpness: 0.20),
                transient(0.60, intensity: 0.35, sharpness: 0.15),
                continuous(0.85, duration: 0.5, intensity: 0.3, sharpness: 0.1)
            ]
        case .tickle:
            events = (0..<9).map { i in
                transient(Double(i) * 0.07, intensity: 0.45 + Float(i % 3) * 0.12, sharpness: 0.9)
            }
        case .thinking:
            events = [
                transient(0.00, intensity: 0.5, sharpness: 0.4),
                transient(0.22, intensity: 0.7, sharpness: 0.5)
            ]
        case .stolz:
            // a rising three-step fanfare with a bright peak — chest swelling
            events = [
                transient(0.00, intensity: 0.45, sharpness: 0.35),
                transient(0.18, intensity: 0.70, sharpness: 0.50),
                transient(0.36, intensity: 1.00, sharpness: 0.70),
                continuous(0.48, duration: 0.35, intensity: 0.55, sharpness: 0.25)
            ]
        case .halteDurch:
            // a firm double squeeze, held — a hand gripping yours
            events = [
                continuous(0.00, duration: 0.45, intensity: 0.90, sharpness: 0.12),
                transient(0.55, intensity: 0.60, sharpness: 0.30),
                continuous(0.75, duration: 0.60, intensity: 0.75, sharpness: 0.10)
            ]
        }
        return try CHHapticPattern(events: events, parameters: [])
    }
}
