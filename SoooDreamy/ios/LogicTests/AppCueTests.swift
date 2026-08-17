import XCTest
@testable import SoooDreamyLogic

/// The cue vocabulary's pure brain: rate limiter, burst throttle, quiet-hours
/// window and the catalog invariants (Dossier 06, ideas 1/6/21/25/30).
final class AppCueTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_755_000_000)

    // MARK: Catalog invariants

    func testEveryCueHasAHapticTwin() {
        for cue in AppCue.allCases {
            XCTAssertFalse(cue.hapticTwin.isEmpty, "\(cue.rawValue) has no haptic twin")
            for event in cue.hapticTwin {
                XCTAssertTrue((0...1).contains(event.i), "\(cue.rawValue): intensity out of range")
                XCTAssertTrue((0...1).contains(event.s), "\(cue.rawValue): sharpness out of range")
                XCTAssertGreaterThanOrEqual(event.t, 0)
            }
        }
    }

    func testThereIsNoErrorBuzzerCue() {
        // Silence rule: errors never sound. The vocabulary must not even
        // offer a cue named for failure feedback.
        let names = Set(AppCue.allCases.map { $0.rawValue.lowercased() })
        XCTAssertFalse(names.contains("error"))
        XCTAssertFalse(names.contains("failure"))
        XCTAssertFalse(names.contains("warning"))
    }

    func testFileNamesAreDeterministic() {
        for cue in AppCue.allCases {
            XCTAssertEqual(cue.fileName, "cue_\(cue.rawValue).caf")
        }
    }

    func testCategoryPrioritiesAreStrictlyOrdered() {
        XCTAssertGreaterThan(CueCategory.moments.schedulingPriority,
                             CueCategory.chat.schedulingPriority)
        XCTAssertGreaterThan(CueCategory.chat.schedulingPriority,
                             CueCategory.games.schedulingPriority)
        XCTAssertGreaterThan(CueCategory.games.schedulingPriority,
                             CueCategory.ui.schedulingPriority)
    }

    // MARK: One-channel rule (motion eval)

    func testOrdinaryCuesRideExactlyOneChannel() {
        // Sound OR haptic — never both. Only key moments earn `.full`.
        for cue in AppCue.allCases where !cue.isKeyMoment {
            var scheduler = CueScheduler()
            let decision = scheduler.decide(cue, now: t0)
            XCTAssertEqual(decision, .soundOnly,
                           "\(cue.rawValue) must lead with the ear alone")
        }
    }

    func testOnlyKeyMomentsEarnBothChannels() {
        XCTAssertEqual(Set(AppCue.allCases.filter(\.isKeyMoment)), [.pairing, .fanfareEpic])
        for cue in [AppCue.pairing, .fanfareEpic] {
            var scheduler = CueScheduler()
            XCTAssertEqual(scheduler.decide(cue, now: t0), .full)
        }
        // The epic fanfare's haptic motif answers AFTER the sound's first
        // accent — both channels never stack on the same instant.
        XCTAssertGreaterThan(CueScheduler.keyMomentHapticStagger, 0)
        XCTAssertLessThan(CueScheduler.keyMomentHapticStagger, 1)
    }

    // MARK: Double-trigger dedupe

    func testIdenticalDoubleTriggersCoalesce() {
        // Chat send fires a manual tap AND the `.sent` cue on the same
        // interaction — the second report inside ~150 ms is the same event.
        var scheduler = CueScheduler()
        XCTAssertEqual(scheduler.decide(.sent, now: t0), .soundOnly)
        XCTAssertEqual(scheduler.decide(.sent, now: t0.addingTimeInterval(0.08)), .silent)
        // Judged from the last NON-coalesced trigger: 0.14 s after t0 is
        // still the same interaction even though 0.06 s passed since the
        // swallowed duplicate.
        XCTAssertEqual(scheduler.decide(.sent, now: t0.addingTimeInterval(0.14)), .silent)
    }

    func testDifferentCuesNeverCoalesce() {
        var scheduler = CueScheduler()
        XCTAssertEqual(scheduler.decide(.click, now: t0), .soundOnly)
        // A DIFFERENT cue 50 ms later is a real second event — the rate
        // limiter may demote it, but it must not vanish.
        XCTAssertEqual(scheduler.decide(.chime, now: t0.addingTimeInterval(0.05)), .hapticOnly)
    }

    // MARK: Rate limiter

    func testRapidCuesOfSamePriorityAreThrottled() {
        var scheduler = CueScheduler()
        XCTAssertEqual(scheduler.decide(.click, now: t0), .soundOnly)
        XCTAssertEqual(scheduler.decide(.chime, now: t0.addingTimeInterval(0.1)), .hapticOnly)
        XCTAssertEqual(scheduler.decide(.click, now: t0.addingTimeInterval(0.5)), .soundOnly)
    }

    func testHigherPriorityCueRingsThroughTheGap() {
        var scheduler = CueScheduler()
        XCTAssertEqual(scheduler.decide(.click, now: t0), .soundOnly)
        // A moment beats an interface tick even inside the 300 ms window.
        XCTAssertEqual(scheduler.decide(.kiss, now: t0.addingTimeInterval(0.1)), .soundOnly)
        // ...but not the other way around.
        XCTAssertEqual(scheduler.decide(.click, now: t0.addingTimeInterval(0.2)), .hapticOnly)
    }

    // MARK: Chat burst throttle

    func testOnlyFirstMessageOfABurstRings() {
        var scheduler = CueScheduler()
        XCTAssertEqual(scheduler.decide(.received, now: t0), .soundOnly)
        XCTAssertEqual(scheduler.decide(.received, now: t0.addingTimeInterval(1.0)), .hapticOnly)
        XCTAssertEqual(scheduler.decide(.received, now: t0.addingTimeInterval(1.9)), .hapticOnly)
        // The burst window slides with EVERY message — 1.9 s + 2.5 s is a
        // fresh conversation beat and may ring again.
        XCTAssertEqual(scheduler.decide(.received, now: t0.addingTimeInterval(4.4)), .soundOnly)
    }

    func testOpenChatOnlyKnocks() {
        var scheduler = CueScheduler()
        XCTAssertEqual(scheduler.decide(.received, now: t0, chatVisible: true), .hapticOnly)
    }

    // MARK: Quiet hours

    func testQuietHoursReplaceSoundWithHaptics() {
        var scheduler = CueScheduler()
        let decision = scheduler.decide(.sparkle, now: t0, quietHours: true)
        XCTAssertEqual(decision, .hapticOnly)
        // The suppressed sound must not poison the rate limiter.
        XCTAssertEqual(scheduler.decide(.vibe, now: t0.addingTimeInterval(0.05)), .soundOnly)
    }

    func testQuietHoursWindowWrapsMidnight() {
        for hour in [22, 23, 0, 3, 7] {
            XCTAssertTrue(QuietHours.isQuiet(hour: hour), "hour \(hour) should be quiet")
        }
        for hour in [8, 12, 18, 21] {
            XCTAssertFalse(QuietHours.isQuiet(hour: hour), "hour \(hour) should ring")
        }
    }

    func testQuietHoursWindowWithoutWrap() {
        XCTAssertTrue(QuietHours.isQuiet(hour: 13, startHour: 12, endHour: 15))
        XCTAssertFalse(QuietHours.isQuiet(hour: 16, startHour: 12, endHour: 15))
        // Degenerate zero-length window never mutes.
        XCTAssertFalse(QuietHours.isQuiet(hour: 12, startHour: 12, endHour: 12))
    }
}
