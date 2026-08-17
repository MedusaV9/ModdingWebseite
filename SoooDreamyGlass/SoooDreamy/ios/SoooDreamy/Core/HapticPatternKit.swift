import Foundation

// Haptics composer — the Foundation-only core (models, recording
// normalization, AHAP export, presets). Playback lives in Haptics.swift;
// this file is part of the Linux logic-test target, keep it UIKit-free.

// MARK: - Wire models

/// One event on a vibration timeline; maps 1:1 to a CoreHaptics/AHAP event.
/// `t` = start (s), `i` = intensity 0…1, `s` = sharpness 0…1,
/// `d` = duration (s) — 0 means a transient tap.
struct HapticEventSpec: Codable, Hashable {
    var t: Double
    var i: Double
    var s: Double
    var d: Double

    init(t: Double, i: Double = 0.7, s: Double = 0.5, d: Double = 0) {
        self.t = t
        self.i = i
        self.s = s
        self.d = d
    }
}

/// A saved pattern in the couple-shared library.
struct HapticPatternModel: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var emoji: String?
    var events: [HapticEventSpec]
    let createdBy: String
    let createdAt: Date
    var sentCount: Int?
}

/// One relayed send (saved pattern or ad-hoc recording).
struct HapticSend: Codable, Identifiable, Hashable {
    let id: String
    let patternId: String?
    let name: String?
    let emoji: String?
    let events: [HapticEventSpec]
    let senderId: String
    let createdAt: Date
}

struct HapticPatternsResponse: Codable { let patterns: [HapticPatternModel] }
struct HapticPatternResponse: Codable { let pattern: HapticPatternModel }
struct HapticSendResponse: Codable { let haptic: HapticSend }
struct HapticsRecentResponse: Codable { let haptics: [HapticSend] }

// MARK: - Timeline math

enum HapticTimeline {
    /// Server-mirrored caps (LIMITS.hapticEvents / HAPTIC_MAX_SECONDS).
    static let maxSeconds = 15.0
    static let maxEvents = 128

    /// Total audible length of a pattern (end of its last event).
    static func duration(of events: [HapticEventSpec]) -> Double {
        events.map { $0.t + $0.d }.max() ?? 0
    }
}

// MARK: - Recording

/// Turns raw press/release timestamps from the composer pad into normalized
/// events. Press DURATION drives the feel: short presses become sharp
/// transient taps whose intensity grows with hold time; long presses become
/// soft continuous rumbles. Time is injected (plain Doubles) so this stays
/// deterministic and unit-testable.
struct HapticRecordingBuilder {
    /// Presses shorter than this become transient taps.
    static let tapThreshold = 0.22
    /// A single continuous event is capped so one long hold can't eat the
    /// whole timeline.
    static let maxHold = 3.0

    private(set) var events: [HapticEventSpec] = []
    private(set) var timelineStart: Double?
    private var pressStart: Double?

    var isEmpty: Bool { events.isEmpty }
    var isFull: Bool { events.count >= HapticTimeline.maxEvents }

    /// Seconds already used on the (capped) timeline.
    var recordedDuration: Double { HapticTimeline.duration(of: events) }

    /// Elapsed recording time for a progress display.
    func elapsed(now: Double) -> Double {
        guard let timelineStart else { return 0 }
        return min(now - timelineStart, HapticTimeline.maxSeconds)
    }

    /// Finger down — the first press anchors the timeline at t=0.
    mutating func press(at time: Double) {
        if timelineStart == nil { timelineStart = time }
        pressStart = time
    }

    /// Finger up — appends the event derived from the press duration.
    /// Returns the appended event (nil when the timeline is full/overrun).
    @discardableResult
    mutating func release(at time: Double) -> HapticEventSpec? {
        guard let start = pressStart, let origin = timelineStart else { return nil }
        pressStart = nil
        let t = start - origin
        guard !isFull, t >= 0, t < HapticTimeline.maxSeconds else { return nil }
        let held = max(0, time - start)
        let event: HapticEventSpec
        if held < Self.tapThreshold {
            // Tap: harder = longer contact. 0.55…1.0, crisp.
            let intensity = 0.55 + (held / Self.tapThreshold) * 0.45
            event = HapticEventSpec(t: round3(t), i: round3(intensity), s: 0.6)
        } else {
            // Hold: a soft swell whose strength grows with hold time.
            let duration = min(min(held, Self.maxHold), HapticTimeline.maxSeconds - t)
            let intensity = min(1.0, 0.45 + held * 0.25)
            event = HapticEventSpec(t: round3(t), i: round3(intensity), s: 0.25, d: round3(duration))
        }
        events.append(event)
        return event
    }

    mutating func reset() {
        events = []
        timelineStart = nil
        pressStart = nil
    }

    private func round3(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }
}

// MARK: - AHAP export

/// Apple Haptic and Audio Pattern (AHAP) conversion. The JSON this emits is
/// the exact format `CHHapticEngine.playPattern(from:)` consumes and what a
/// `.ahap` file contains.
enum HapticAHAP {
    static func dictionary(events: [HapticEventSpec]) -> [String: Any] {
        let pattern: [[String: Any]] = events.map { ev in
            var event: [String: Any] = [
                "Time": ev.t,
                "EventType": ev.d > 0 ? "HapticContinuous" : "HapticTransient",
                "EventParameters": [
                    ["ParameterID": "HapticIntensity", "ParameterValue": ev.i],
                    ["ParameterID": "HapticSharpness", "ParameterValue": ev.s],
                ],
            ]
            if ev.d > 0 { event["EventDuration"] = ev.d }
            return ["Event": event]
        }
        return ["Version": 1.0, "Pattern": pattern]
    }

    static func data(events: [HapticEventSpec]) throws -> Data {
        try JSONSerialization.data(withJSONObject: dictionary(events: events), options: [.sortedKeys])
    }
}

// MARK: - Presets

struct HapticPreset: Identifiable, Hashable {
    let id: String
    let emoji: String
    let events: [HapticEventSpec]

    var nameKey: String { "haptic.preset.\(id)" }
}

enum HapticPresets {
    static let all: [HapticPreset] = [
        HapticPreset(id: "heartbeat", emoji: "💓", events: [
            HapticEventSpec(t: 0.00, i: 1.00, s: 0.30),
            HapticEventSpec(t: 0.18, i: 0.60, s: 0.20),
            HapticEventSpec(t: 0.80, i: 1.00, s: 0.30),
            HapticEventSpec(t: 0.98, i: 0.60, s: 0.20),
            HapticEventSpec(t: 1.60, i: 1.00, s: 0.30),
            HapticEventSpec(t: 1.78, i: 0.60, s: 0.20),
        ]),
        HapticPreset(id: "butterflies", emoji: "🦋", events:
            // Fluttering wings: airy fast taps over a faint carpet.
            [HapticEventSpec(t: 0, i: 0.25, s: 0.10, d: 1.9)]
            + stride(from: 0.0, through: 1.68, by: 0.12).enumerated().map { idx, t in
                HapticEventSpec(t: t, i: idx.isMultiple(of: 2) ? 0.45 : 0.30, s: 0.95)
            }),
        HapticPreset(id: "rain", emoji: "🌧️", events:
            // Irregular soft droplets — hand-placed so it never sounds mechanical.
            [0.00, 0.13, 0.31, 0.42, 0.60, 0.68, 0.85, 1.02, 1.10, 1.31, 1.45, 1.66,
             1.72, 1.94, 2.05, 2.24, 2.38, 2.55].enumerated().map { idx, t in
                HapticEventSpec(t: t, i: 0.28 + Double(idx % 4) * 0.09, s: 0.75)
            }),
        HapticPreset(id: "soskiss", emoji: "😘", events: {
            // Morse SOS (··· ––– ···) ending in one big kiss pop.
            var evs: [HapticEventSpec] = []
            var t = 0.0
            for _ in 0..<3 { evs.append(HapticEventSpec(t: t, i: 0.8, s: 0.9)); t += 0.22 }
            t += 0.25
            for _ in 0..<3 { evs.append(HapticEventSpec(t: t, i: 0.75, s: 0.30, d: 0.42)); t += 0.62 }
            t += 0.05
            for _ in 0..<3 { evs.append(HapticEventSpec(t: t, i: 0.8, s: 0.9)); t += 0.22 }
            evs.append(HapticEventSpec(t: t + 0.35, i: 1.0, s: 0.55))
            return evs
        }()),
        HapticPreset(id: "ocean", emoji: "🌊", events: [
            HapticEventSpec(t: 0.0, i: 0.55, s: 0.05, d: 1.5),
            HapticEventSpec(t: 1.9, i: 0.75, s: 0.10, d: 1.8),
            HapticEventSpec(t: 4.1, i: 0.45, s: 0.05, d: 1.3),
        ]),
        HapticPreset(id: "sparkle", emoji: "✨", events:
            (0..<7).map { k in
                HapticEventSpec(t: Double(k) * 0.09, i: 0.35 + Double(k) * 0.09, s: 1.0)
            }),
    ]
}
