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
        }
        return try CHHapticPattern(events: events, parameters: [])
    }
}
