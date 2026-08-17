import XCTest
@testable import SoooDreamyLogic

/// Haptics composer core: recording normalization, timeline caps, AHAP
/// export shape and preset sanity. Mirrors the server-side validation in
/// server/src/router.js (asHapticEvents / LIMITS).
final class HapticPatternTests: XCTestCase {

    // MARK: Recording builder

    func testShortPressBecomesTransientTapWithDurationScaledIntensity() {
        var builder = HapticRecordingBuilder()
        builder.press(at: 100.0)
        let event = builder.release(at: 100.05)

        XCTAssertNotNil(event)
        XCTAssertEqual(event?.t, 0, "first press anchors the timeline at t=0")
        XCTAssertEqual(event?.d, 0, "short press must be a transient tap")
        // 50 ms of 220 ms threshold → 0.55 + (0.05/0.22)*0.45 ≈ 0.652
        XCTAssertEqual(event!.i, 0.652, accuracy: 0.005)

        builder.press(at: 100.5)
        let harder = builder.release(at: 100.71)   // just under the threshold
        XCTAssertGreaterThan(harder!.i, event!.i, "longer contact = stronger tap")
    }

    func testLongPressBecomesContinuousRumble() {
        var builder = HapticRecordingBuilder()
        builder.press(at: 10.0)
        let event = builder.release(at: 11.2)

        XCTAssertEqual(event?.d, 1.2)
        XCTAssertEqual(event?.s, 0.25, "holds are soft (low sharpness)")
        XCTAssertEqual(event!.i, 0.75, accuracy: 0.005) // 0.45 + 1.2*0.25
    }

    func testHoldIsCappedAtMaxHold() {
        var builder = HapticRecordingBuilder()
        builder.press(at: 0)
        let event = builder.release(at: 8)   // held way too long
        XCTAssertEqual(event?.d, HapticRecordingBuilder.maxHold)
    }

    func testTimelineRejectsEventsPastTheCap() {
        var builder = HapticRecordingBuilder()
        builder.press(at: 0)
        builder.release(at: 0.1)
        builder.press(at: 0 + HapticTimeline.maxSeconds + 1)
        XCTAssertNil(builder.release(at: HapticTimeline.maxSeconds + 1.1),
                     "presses after the 15 s window must be dropped")
        XCTAssertEqual(builder.events.count, 1)
    }

    func testEventCountCap() {
        var builder = HapticRecordingBuilder()
        for k in 0..<(HapticTimeline.maxEvents + 10) {
            builder.press(at: Double(k) * 0.05)
            builder.release(at: Double(k) * 0.05 + 0.01)
        }
        XCTAssertEqual(builder.events.count, HapticTimeline.maxEvents)
    }

    func testReleaseWithoutPressIsIgnoredAndResetClears() {
        var builder = HapticRecordingBuilder()
        XCTAssertNil(builder.release(at: 5))
        builder.press(at: 1)
        builder.release(at: 1.1)
        builder.reset()
        XCTAssertTrue(builder.isEmpty)
        XCTAssertNil(builder.timelineStart)
    }

    // MARK: Timeline math

    func testDurationIsEndOfLastEventIncludingHold() {
        let events = [
            HapticEventSpec(t: 0.0),
            HapticEventSpec(t: 1.0, d: 0.5),
            HapticEventSpec(t: 1.2),
        ]
        XCTAssertEqual(HapticTimeline.duration(of: events), 1.5)
        XCTAssertEqual(HapticTimeline.duration(of: []), 0)
    }

    // MARK: AHAP export

    func testAHAPDictionaryShape() throws {
        let events = [
            HapticEventSpec(t: 0, i: 1, s: 0.3),
            HapticEventSpec(t: 0.5, i: 0.6, s: 0.1, d: 1.25),
        ]
        let dict = HapticAHAP.dictionary(events: events)

        XCTAssertEqual(dict["Version"] as? Double, 1.0)
        let pattern = try XCTUnwrap(dict["Pattern"] as? [[String: Any]])
        XCTAssertEqual(pattern.count, 2)

        let tap = try XCTUnwrap(pattern[0]["Event"] as? [String: Any])
        XCTAssertEqual(tap["EventType"] as? String, "HapticTransient")
        XCTAssertNil(tap["EventDuration"], "transients must not carry a duration")

        let hold = try XCTUnwrap(pattern[1]["Event"] as? [String: Any])
        XCTAssertEqual(hold["EventType"] as? String, "HapticContinuous")
        XCTAssertEqual(hold["EventDuration"] as? Double, 1.25)
        let params = try XCTUnwrap(hold["EventParameters"] as? [[String: Any]])
        XCTAssertEqual(params.compactMap { $0["ParameterID"] as? String }.sorted(),
                       ["HapticIntensity", "HapticSharpness"])

        // Must serialize to valid JSON (CHHapticEngine.playPattern(from:) input).
        let data = try HapticAHAP.data(events: events)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(parsed?["Pattern"])
    }

    // MARK: Presets

    func testPresetsAreValidWithinServerLimits() {
        XCTAssertGreaterThanOrEqual(HapticPresets.all.count, 4, "spec asks for heartbeat, butterflies, rain, SOS kiss …")
        var seenIds = Set<String>()
        for preset in HapticPresets.all {
            XCTAssertTrue(seenIds.insert(preset.id).inserted, "duplicate preset id \(preset.id)")
            XCTAssertFalse(preset.events.isEmpty, "\(preset.id) has no events")
            XCTAssertLessThanOrEqual(preset.events.count, HapticTimeline.maxEvents)
            for event in preset.events {
                XCTAssertTrue((0...HapticTimeline.maxSeconds).contains(event.t), "\(preset.id): t out of range")
                XCTAssertTrue((0...1).contains(event.i), "\(preset.id): intensity out of range")
                XCTAssertTrue((0...1).contains(event.s), "\(preset.id): sharpness out of range")
                XCTAssertTrue((0...HapticTimeline.maxSeconds).contains(event.d), "\(preset.id): duration out of range")
            }
            XCTAssertLessThanOrEqual(HapticTimeline.duration(of: preset.events), HapticTimeline.maxSeconds,
                                     "\(preset.id) overruns the timeline cap")
        }
    }

    /// Every preset needs its DE/EN name in the L10n table.
    func testPresetNamesAreLocalized() {
        for preset in HapticPresets.all {
            let name = L10n.t(preset.nameKey)
            XCTAssertFalse(name.isEmpty)
            XCTAssertNotEqual(name, preset.nameKey, "missing localization for \(preset.nameKey)")
        }
    }
}
