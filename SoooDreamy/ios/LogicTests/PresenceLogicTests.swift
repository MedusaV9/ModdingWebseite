import XCTest
@testable import SoooDreamyLogic

/// v9.0 „Nähe trotz Distanz": presence expiry + pulse cooldown MUST mirror
/// server/src/presence.js; every dynamic L10n key (kind.titleKey & co. are
/// built at runtime, invisible to the static usage scan) must exist DE+EN.
final class PresenceLogicTests: XCTestCase {

    // MARK: Presence expiry (mirrors the server's lazy expiry)

    func testPresenceWithoutUntilStaysActive() {
        XCTAssertTrue(PresenceLogic.isActive(until: nil))
    }

    func testPresenceExpiresExactlyAtUntil() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertTrue(PresenceLogic.isActive(until: now.addingTimeInterval(1), now: now))
        // Server: `until <= now` → expired. Same instant means gone.
        XCTAssertFalse(PresenceLogic.isActive(until: now, now: now))
        XCTAssertFalse(PresenceLogic.isActive(until: now.addingTimeInterval(-1), now: now))
    }

    func testRemainingMinutesRoundsUpAndDropsExpired() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertNil(PresenceLogic.remainingMinutes(until: nil, now: now))
        XCTAssertNil(PresenceLogic.remainingMinutes(until: now.addingTimeInterval(-60), now: now))
        XCTAssertEqual(PresenceLogic.remainingMinutes(until: now.addingTimeInterval(60), now: now), 1)
        // 49:30 left reads as "noch 50 min", never "noch 49".
        XCTAssertEqual(PresenceLogic.remainingMinutes(until: now.addingTimeInterval(49 * 60 + 30), now: now), 50)
        XCTAssertEqual(PresenceLogic.remainingMinutes(until: now.addingTimeInterval(120 * 60), now: now), 120)
    }

    func testRemainingLabelSwitchesToHours() {
        let minutes = PresenceLogic.remainingLabel(minutes: 45)
        XCTAssertEqual(minutes.key, "presence.remaining.minutes")
        XCTAssertEqual(minutes.args["minutes"], "45")

        let hours = PresenceLogic.remainingLabel(minutes: 90)
        XCTAssertEqual(hours.key, "presence.remaining.hours")
        XCTAssertEqual(hours.args["hours"], "2") // 90 min rounds to 2 h — soft, not precise

        let exactly = PresenceLogic.remainingLabel(minutes: 60)
        XCTAssertEqual(exactly.key, "presence.remaining.hours")
        XCTAssertEqual(exactly.args["hours"], "1")
    }

    func testDurationChoicesRespectServerContract() {
        for choice in PresenceLogic.durationChoicesMinutes {
            guard let minutes = choice else { continue } // open-ended is client-only
            XCTAssertGreaterThanOrEqual(minutes, PresenceLogic.minMinutes)
            XCTAssertLessThanOrEqual(minutes, PresenceLogic.maxMinutes)
        }
        XCTAssertEqual(PresenceLogic.minMinutes, 5, "server/src/presence.js PRESENCE_LIMITS.minMinutes")
        XCTAssertEqual(PresenceLogic.maxMinutes, 720, "server/src/presence.js PRESENCE_LIMITS.maxMinutes")
        XCTAssertEqual(PresenceLogic.maxNoteLength, 80, "server/src/presence.js PRESENCE_LIMITS.note")
    }

    // MARK: Pulse cooldown (mirrors the server's 30 s throttle)

    func testCooldownMatchesServerAndCountsDown() {
        XCTAssertEqual(PulseLogic.cooldown, 30, "server/src/presence.js PRESENCE_LIMITS.pulseCooldownMs")
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(PulseLogic.cooldownRemaining(lastSentAt: nil, now: now), 0)
        XCTAssertEqual(PulseLogic.cooldownRemaining(lastSentAt: now.addingTimeInterval(-10), now: now), 20)
        XCTAssertEqual(PulseLogic.cooldownRemaining(lastSentAt: now.addingTimeInterval(-30), now: now), 0)
        XCTAssertEqual(PulseLogic.cooldownRemaining(lastSentAt: now.addingTimeInterval(-45), now: now), 0)
    }

    // MARK: Haptic signatures

    func testEveryPulseKindHasANonEmptyBoundedTimeline() {
        XCTAssertEqual(PulseKind.allCases.map(\.rawValue),
                       ["thinking", "goodnight", "heartbeat", "hug"],
                       "server/src/presence.js PULSE_KINDS — order is the UI order")
        for kind in PulseKind.allCases {
            let events = kind.timeline
            XCTAssertFalse(events.isEmpty, "\(kind) has no haptic events")
            for event in events {
                XCTAssertGreaterThanOrEqual(event.t, 0)
                XCTAssertTrue((0...1).contains(event.i), "\(kind) intensity out of range")
                XCTAssertTrue((0...1).contains(event.s), "\(kind) sharpness out of range")
                XCTAssertGreaterThanOrEqual(event.d, 0)
            }
            let duration = PulseLogic.timelineDuration(events)
            XCTAssertGreaterThan(duration, 0)
            XCTAssertLessThanOrEqual(duration, 3.0, "\(kind) longer than 3 s — a pulse, not a concert")
        }
    }

    func testTimelineDurationIncludesContinuousTails() {
        let events = [HapticEventSpec(t: 0.5, i: 0.5, s: 0.5, d: 1.0),
                      HapticEventSpec(t: 1.0, i: 0.5, s: 0.5)]
        XCTAssertEqual(PulseLogic.timelineDuration(events), 1.5)
        XCTAssertEqual(PulseLogic.timelineDuration([]), 0)
    }

    func testPulseSignaturesAreDistinct() {
        let signatures = PulseKind.allCases.map(\.timeline)
        for (i, a) in signatures.enumerated() {
            for b in signatures[(i + 1)...] {
                XCTAssertNotEqual(a, b, "two pulse kinds share the same haptic signature")
            }
        }
    }

    // MARK: L10n coverage for runtime-built keys

    func testEveryDynamicPresenceKeyExistsInBothLanguages() {
        var keys: [String] = []
        for mode in PresenceModeKind.allCases {
            keys.append(contentsOf: [mode.titleKey, mode.subtitleKey, mode.partnerHintKey])
        }
        for kind in PulseKind.allCases {
            keys.append(contentsOf: [kind.titleKey, kind.receivedKey])
        }
        for key in keys {
            guard let text = CoreStrings.table[key] else {
                XCTFail("\(key) missing from CoreStrings")
                continue
            }
            XCTAssertFalse(text.de.isEmpty, "\(key) has empty DE")
            XCTAssertFalse(text.en.isEmpty, "\(key) has empty EN")
        }
    }

    func testPartnerHintsAddressThePartnerByName() {
        for mode in PresenceModeKind.allCases {
            guard let text = CoreStrings.table[mode.partnerHintKey] else { continue }
            XCTAssertTrue(text.de.contains("{name}"), "\(mode.partnerHintKey) DE lacks {name}")
            XCTAssertTrue(text.en.contains("{name}"), "\(mode.partnerHintKey) EN lacks {name}")
        }
    }
}
