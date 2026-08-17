import Foundation
import XCTest
@testable import SoooDreamyLogic

/// The error-mapping table (server machine codes → human DE/EN sentences)
/// is a contract: every mapped code resolves in both languages, quarantine
/// gets its own state, and 429 carries the retry-after countdown.
final class APIErrorHumanizerTests: XCTestCase {
    private var originalLanguage: AppLanguage!

    override func setUp() {
        super.setUp()
        originalLanguage = L10n.language
    }

    override func tearDown() {
        L10n.language = originalLanguage
        super.tearDown()
    }

    func testKnownCodesResolveToHumanSentencesInBothLanguages() {
        let cases: [(status: Int, code: String)] = [
            (400, "too_long"), (413, "too_large"), (413, "too_many_videos"),
            (409, "couple_full"), (404, "unknown_code"), (403, "bad_recovery_key"),
            (403, "session_revoked"), (403, "unknown_session"), (409, "expired"),
            (409, "already_redeemed"), (409, "wrong_turn"), (409, "game_ended"),
            (409, "game_not_active"), (409, "no_partner"), (403, "not_yours"),
            (403, "not_for_you"), (409, "cooldown_active"), (503, "server_capacity"),
            // W8C board & duel games — sentences live in GamesL10n.
            (409, "capture_required"), (409, "empty_pit"), (409, "no_flip"),
            (409, "pass_not_allowed"), (409, "already_matched"),
        ]
        for language in [AppLanguage.de, .en] {
            L10n.language = language
            for (status, code) in cases {
                let human = APIErrorHumanizer.humanize(status: status, code: code,
                                                       message: "raw operator text")
                XCTAssertFalse(human.text.contains("error.code."),
                               "unresolved key for \(code) in \(language)")
                XCTAssertNotEqual(human.text, "raw operator text",
                                  "\(code) must not leak the operator message")
                XCTAssertFalse(human.isQuarantine)
                XCTAssertNil(human.retryAfterSeconds)
            }
        }
    }

    func testQuarantineGetsItsOwnState() {
        for language in [AppLanguage.de, .en] {
            L10n.language = language
            let human = APIErrorHumanizer.humanize(status: 503,
                                                   code: "couple_data_quarantined",
                                                   message: nil)
            XCTAssertTrue(human.isQuarantine)
            XCTAssertFalse(human.text.contains("error.code."))
        }
    }

    func testRateLimitRespectsRetryAfter() {
        L10n.language = .en
        let limited = APIErrorHumanizer.humanize(status: 429, code: "rate_limited",
                                                 message: nil, retryAfter: 42)
        XCTAssertEqual(limited.retryAfterSeconds, 42)
        XCTAssertTrue(limited.text.contains("42"), "countdown must surface: \(limited.text)")

        // Missing header → small sane default, never zero.
        let headerless = APIErrorHumanizer.humanize(status: 429, code: "rate_limited",
                                                    message: nil, retryAfter: nil)
        XCTAssertEqual(headerless.retryAfterSeconds, 5)

        // Cooldown codes keep their own friendlier sentence, with countdown.
        let effect = APIErrorHumanizer.humanize(status: 429, code: "effect_cooldown",
                                                message: nil, retryAfter: 7)
        XCTAssertTrue(effect.text.contains("7"))
        let tooSoon = APIErrorHumanizer.humanize(status: 429, code: "too_soon",
                                                 message: nil, retryAfter: 3)
        XCTAssertTrue(tooSoon.text.contains("3"))
    }

    func testUnknownCodesFallBackPerStatusFamilyAndShowTheCode() {
        L10n.language = .de
        for (status, code) in [(400, "bad_palette"), (403, "wrong_actor"),
                               (409, "week_closed"), (413, "game_move_quota"),
                               (500, "internal"), (418, "teapot")] {
            let human = APIErrorHumanizer.humanize(status: status, code: code, message: nil)
            XCTAssertFalse(human.text.isEmpty)
            XCTAssertFalse(human.text.contains("error.status."),
                           "unresolved fallback for status \(status)")
            if [400, 403, 409, 418].contains(status) {
                XCTAssertTrue(human.text.contains(code),
                              "fallback should show the machine code: \(human.text)")
            }
        }
        // No code at all → the HTTP status stands in.
        let bare = APIErrorHumanizer.humanize(status: 400, code: nil, message: nil)
        XCTAssertTrue(bare.text.contains("HTTP 400"))
    }

    func testTransportMappingDistinguishesOfflineTimeoutUnreachable() {
        for language in [AppLanguage.de, .en] {
            L10n.language = language
            let offline = APIErrorHumanizer.humanizeTransport(urlErrorCode: -1009)
            let timeout = APIErrorHumanizer.humanizeTransport(urlErrorCode: -1001)
            let unreachable = APIErrorHumanizer.humanizeTransport(urlErrorCode: -1004)
            let generic = APIErrorHumanizer.humanizeTransport(urlErrorCode: nil)
            XCTAssertEqual(Set([offline, timeout, unreachable, generic]).count, 4,
                           "each transport family needs its own sentence in \(language)")
            for text in [offline, timeout, unreachable, generic] {
                XCTAssertFalse(text.contains("error.transport."), "unresolved key: \(text)")
            }
        }
    }
}
