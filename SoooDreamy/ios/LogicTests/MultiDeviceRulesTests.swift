import XCTest
@testable import SoooDreamyLogic

/// Welle 3 — the multi-device contract from docs/API.md („Multi-device
/// sessions & fanout"): recognizing own echoes via the `origin` marker,
/// the 8-char device link-code format, and the `sooodreamy://link`
/// deep-link / QR payload.
final class MultiDeviceRulesTests: XCTestCase {

    private func origin(member: String? = nil, device: String? = nil,
                        suffix: String? = nil) -> EventOrigin {
        EventOrigin(memberId: member, deviceId: device, sessionSuffix: suffix)
    }

    // MARK: Session suffix

    func testSessionSuffixTakesLastEightCharacters() {
        // Server: sessionId.slice(-8).
        XCTAssertEqual(MultiDeviceRules.sessionSuffixLength, 8)
        XCTAssertEqual(MultiDeviceRules.sessionSuffix(of: "sess_abcdef12345678"), "12345678")
        // Shorter ids compare whole — same behavior as String.suffix.
        XCTAssertEqual(MultiDeviceRules.sessionSuffix(of: "short"), "short")
        XCTAssertNil(MultiDeviceRules.sessionSuffix(of: nil))
        XCTAssertNil(MultiDeviceRules.sessionSuffix(of: ""))
    }

    // MARK: Own-echo recognition

    func testOwnEchoMatchesOnlyTheOwnSessionSuffix() {
        let mySession = "sess_abcdef12345678"
        XCTAssertTrue(MultiDeviceRules.isOwnEcho(
            origin: origin(member: "m1", suffix: "12345678"), sessionId: mySession))
        // A different session of the SAME member is not an echo.
        XCTAssertFalse(MultiDeviceRules.isOwnEcho(
            origin: origin(member: "m1", suffix: "87654321"), sessionId: mySession))
    }

    func testMissingMarkerNeverCountsAsEcho() {
        // Old servers / system frames carry no origin — partner behavior
        // must not change, so "unknown" is always "not me".
        let mySession = "sess_abcdef12345678"
        XCTAssertFalse(MultiDeviceRules.isOwnEcho(origin: nil, sessionId: mySession))
        XCTAssertFalse(MultiDeviceRules.isOwnEcho(
            origin: origin(member: "m1", suffix: nil), sessionId: mySession))
        XCTAssertFalse(MultiDeviceRules.isOwnEcho(
            origin: origin(member: "m1", suffix: ""), sessionId: mySession))
        // …and a client that does not know its own session id cannot
        // claim any frame as its echo either.
        XCTAssertFalse(MultiDeviceRules.isOwnEcho(
            origin: origin(member: "m1", suffix: "12345678"), sessionId: nil))
        XCTAssertFalse(MultiDeviceRules.isOwnEcho(
            origin: origin(member: "m1", suffix: "12345678"), sessionId: ""))
    }

    // MARK: "Me, but on another device"

    func testOwnOtherDeviceRequiresOwnMemberButForeignSession() {
        let mySession = "sess_abcdef12345678"
        // My iPad while I hold my iPhone: same member, different suffix.
        XCTAssertTrue(MultiDeviceRules.isOwnOtherDevice(
            origin: origin(member: "m1", suffix: "87654321"),
            memberId: "m1", sessionId: mySession))
        // My own echo is NOT "another device".
        XCTAssertFalse(MultiDeviceRules.isOwnOtherDevice(
            origin: origin(member: "m1", suffix: "12345678"),
            memberId: "m1", sessionId: mySession))
        // The partner is never "me on another device".
        XCTAssertFalse(MultiDeviceRules.isOwnOtherDevice(
            origin: origin(member: "m2", suffix: "87654321"),
            memberId: "m1", sessionId: mySession))
        // Unknown origins stay partner-shaped (conservative default).
        XCTAssertFalse(MultiDeviceRules.isOwnOtherDevice(
            origin: nil, memberId: "m1", sessionId: mySession))
        XCTAssertFalse(MultiDeviceRules.isOwnOtherDevice(
            origin: origin(member: nil, suffix: "87654321"),
            memberId: "m1", sessionId: mySession))
        XCTAssertFalse(MultiDeviceRules.isOwnOtherDevice(
            origin: origin(member: "m1", suffix: "87654321"),
            memberId: nil, sessionId: mySession))
    }

    func testOwnOtherDeviceWithoutOwnSessionIdStillMatchesOwnMember() {
        // Right after a cold start the session id may hydrate late; a frame
        // from my member must still not render as a partner event.
        XCTAssertTrue(MultiDeviceRules.isOwnOtherDevice(
            origin: origin(member: "m1", suffix: "87654321"),
            memberId: "m1", sessionId: nil))
    }

    // MARK: Central partner-effect gate (eval traces)

    /// The three documented eval traces, replayed against the central gate.
    /// My session: sess_abcdef12345678 (suffix 12345678), my member: m1.
    func testPartnerEffectTraces() {
        let mySession = "sess_abcdef12345678"

        // Trace 1 (message, was ok): the PARTNER sends a message — the
        // frame carries her member + session. Partner effects fire.
        XCTAssertTrue(MultiDeviceRules.allowsPartnerEffects(
            origin: origin(member: "m2", suffix: "99999999"),
            memberId: "m1", sessionId: mySession))

        // Trace 2 (touch, was ok): MY OWN send echoes back to this very
        // session. No partner effects.
        XCTAssertFalse(MultiDeviceRules.allowsPartnerEffects(
            origin: origin(member: "m1", suffix: "12345678"),
            memberId: "m1", sessionId: mySession))

        // Trace 3 (daymemo, was WRONG): I completed the pair on my iPad;
        // my iPhone received the fanout and celebrated "partner finished".
        // The gate must block it — my member, foreign session suffix.
        XCTAssertFalse(MultiDeviceRules.allowsPartnerEffects(
            origin: origin(member: "m1", suffix: "87654321"),
            memberId: "m1", sessionId: mySession))
    }

    func testPartnerEffectsPassWithoutOriginMarker() {
        // Old servers and system frames carry no origin — partner behavior
        // must not change when the marker is missing (tolerant consumption).
        XCTAssertTrue(MultiDeviceRules.allowsPartnerEffects(
            origin: nil, memberId: "m1", sessionId: "sess_abcdef12345678"))
        XCTAssertTrue(MultiDeviceRules.allowsPartnerEffects(
            origin: origin(member: nil, suffix: nil),
            memberId: "m1", sessionId: "sess_abcdef12345678"))
    }

    func testPartnerEffectsBlockOwnMemberEvenWithLateSessionId() {
        // Cold start: the own session id hydrates late — a frame from my
        // member must still never celebrate as a partner event.
        XCTAssertFalse(MultiDeviceRules.allowsPartnerEffects(
            origin: origin(member: "m1", suffix: "87654321"),
            memberId: "m1", sessionId: nil))
    }

    // MARK: Terminal close codes (revoke contract)

    func testOnlyCloseCode4001IsTerminal() {
        XCTAssertEqual(SessionTerminationRules.revokedCloseCode, 4001)
        XCTAssertTrue(SessionTerminationRules.isTerminal(closeCode: 4001))
        // Normal shutdowns, network failures and unknown codes all stay
        // reconnect cases — only the explicit revoke is final.
        XCTAssertFalse(SessionTerminationRules.isTerminal(closeCode: 1000))
        XCTAssertFalse(SessionTerminationRules.isTerminal(closeCode: 1001))
        XCTAssertFalse(SessionTerminationRules.isTerminal(closeCode: 1006))
        XCTAssertFalse(SessionTerminationRules.isTerminal(closeCode: 4000))
        XCTAssertFalse(SessionTerminationRules.isTerminal(closeCode: 4002))
        XCTAssertFalse(SessionTerminationRules.isTerminal(closeCode: nil))
    }

    // MARK: Error mapping (docs/API.md catalog)

    func testLinkErrorKeyCoversTheDocumentedCatalog() {
        XCTAssertEqual(MultiDeviceRules.linkErrorKey(status: 403, code: "bad_link_code"),
                       "devices.link.badCode")
        XCTAssertEqual(MultiDeviceRules.linkErrorKey(status: 403, code: "link_code_expired"),
                       "devices.link.expired")
        XCTAssertEqual(MultiDeviceRules.linkErrorKey(status: 409, code: "link_code_consumed"),
                       "devices.link.consumed")
        XCTAssertEqual(MultiDeviceRules.linkErrorKey(status: 404, code: "unknown_couple"),
                       "devices.link.unknownCouple")
        XCTAssertEqual(MultiDeviceRules.linkErrorKey(status: 413, code: "too_many_sessions"),
                       "devices.link.tooManySessions")
        XCTAssertEqual(MultiDeviceRules.linkErrorKey(status: 429, code: "rate_limited"),
                       "devices.link.rateLimited")
        // Unknown combos fall back to the generic API error path.
        XCTAssertNil(MultiDeviceRules.linkErrorKey(status: 500, code: nil))
        XCTAssertNil(MultiDeviceRules.linkErrorKey(status: 403, code: "bad_recovery_key"))
    }

    func testEveryLinkErrorKeyExistsInTheStringTables() {
        // The mapped keys must resolve in DE and EN — a raw key on a toast
        // would be the ugliest possible failure of an error path.
        let keys = ["devices.link.badCode", "devices.link.expired",
                    "devices.link.consumed", "devices.link.unknownCouple",
                    "devices.link.tooManySessions", "devices.link.rateLimited"]
        for key in keys {
            let entry = CoreStrings.table[key]
            XCTAssertNotNil(entry, "missing string table entry for \(key)")
            XCTAssertFalse(entry?.de.isEmpty ?? true, "\(key) needs a German text")
            XCTAssertFalse(entry?.en.isEmpty ?? true, "\(key) needs an English text")
        }
    }

    // MARK: Device icon

    func testDeviceIconGuessesFromTheDeviceName() {
        XCTAssertEqual(MultiDeviceRules.deviceIcon(name: "Lisas iPad Pro"), "ipad")
        XCTAssertEqual(MultiDeviceRules.deviceIcon(name: "MacBook von Jonas"), "macbook")
        XCTAssertEqual(MultiDeviceRules.deviceIcon(name: "iPhone 17"), "iphone")
        XCTAssertEqual(MultiDeviceRules.deviceIcon(name: nil), "iphone")
        XCTAssertEqual(MultiDeviceRules.deviceIcon(name: "Pixel 9"), "iphone")
    }

    // MARK: Link-code normalization

    func testLinkCodeNormalization() {
        XCTAssertEqual(DeviceLinkCode.length, 8)
        // Lowercase input uppercases; separators and spaces drop.
        XCTAssertEqual(DeviceLinkCode.normalized("h4xk-9pwz"), "H4XK9PWZ")
        XCTAssertEqual(DeviceLinkCode.normalized(" h4xk 9pwz "), "H4XK9PWZ")
        // Confusables (0/O/1/I) are NOT in the alphabet — they drop out
        // instead of being mapped, exactly like the server generator.
        XCTAssertEqual(DeviceLinkCode.normalized("H0XK9PW1"), "HXK9PW")
        // Overlong input caps at 8.
        XCTAssertEqual(DeviceLinkCode.normalized("ABCDEFGH23456789"), "ABCDEFGH")
    }

    func testLinkCodeCompleteness() {
        XCTAssertTrue(DeviceLinkCode.isComplete("H4XK9PWZ"))
        XCTAssertTrue(DeviceLinkCode.isComplete("h4xk 9pwz"))
        XCTAssertFalse(DeviceLinkCode.isComplete("H4XK9PW"))
        XCTAssertFalse(DeviceLinkCode.isComplete(""))
        // 8 raw chars that shrink after normalization are incomplete.
        XCTAssertFalse(DeviceLinkCode.isComplete("H0XK9PW1"))
    }

    // MARK: sooodreamy://link parsing

    func testParsesServerAndCode() {
        let link = DeviceLinkURL.parse(
            "sooodreamy://link?server=http://192.168.1.20:4321&code=H4XK9PWZ")
        XCTAssertNotNil(link)
        XCTAssertEqual(link?.server, "http://192.168.1.20:4321")
        XCTAssertEqual(link?.code, "H4XK9PWZ")
    }

    func testParsesPercentEncodedServerAndNormalizesCode() {
        let link = DeviceLinkURL.parse(
            "sooodreamy://link?server=https%3A%2F%2Fdreamy.example.com&code=h4xk9pwz")
        XCTAssertEqual(link?.server, "https://dreamy.example.com")
        XCTAssertEqual(link?.code, "H4XK9PWZ")
    }

    func testAcceptsParameterAliasesAndCaseInsensitiveNames() {
        let link = DeviceLinkURL.parse(
            "sooodreamy://link?url=home.local:4321&LINKCODE=h4xk9pwz")
        // Bare host:port gets the http:// default (private couple servers
        // speak plain HTTP).
        XCTAssertEqual(link?.server, "http://home.local:4321")
        XCTAssertEqual(link?.code, "H4XK9PWZ")
    }

    func testCodeOnlyLinkParsesWithoutServer() {
        let link = DeviceLinkURL.parse("sooodreamy://link?code=H4XK9PWZ")
        XCTAssertNotNil(link)
        XCTAssertNil(link?.server)
        XCTAssertEqual(link?.code, "H4XK9PWZ")
    }

    func testRejectsForeignSchemesHostsAndIncompleteCodes() {
        XCTAssertNil(DeviceLinkURL.parse("https://link?code=H4XK9PWZ"))       // wrong scheme
        XCTAssertNil(DeviceLinkURL.parse("sooodreamy://rejoin?code=H4XK9PWZ")) // wrong host
        XCTAssertNil(DeviceLinkURL.parse("sooodreamy://link"))                 // no code
        XCTAssertNil(DeviceLinkURL.parse("sooodreamy://link?code=H4XK9PW"))    // 7 chars
        XCTAssertNil(DeviceLinkURL.parse("sooodreamy://link?server=http://x.local")) // server only
        XCTAssertNil(DeviceLinkURL.parse("not a url …"))
    }

    func testNonHTTPServersAreDroppedNotPrefixed() {
        // ftp:// / javascript: must not survive — and must NOT be turned
        // into http://ftp://… by the address normalizer either.
        let ftp = DeviceLinkURL.parse("sooodreamy://link?server=ftp://evil.example&code=H4XK9PWZ")
        XCTAssertNotNil(ftp)
        XCTAssertNil(ftp?.server)
        XCTAssertEqual(ftp?.code, "H4XK9PWZ")

        XCTAssertNil(DeviceLinkURL.normalizedHTTPServer("ftp://evil.example"))
        XCTAssertNil(DeviceLinkURL.normalizedHTTPServer("javascript://alert(1)"))
        XCTAssertEqual(DeviceLinkURL.normalizedHTTPServer("192.168.1.20:4321"),
                       "http://192.168.1.20:4321")
        XCTAssertEqual(DeviceLinkURL.normalizedHTTPServer("https://dreamy.example.com"),
                       "https://dreamy.example.com")
    }

    func testEncodingRoundTrip() {
        let link = DeviceLinkURL(server: "http://192.168.1.20:4321", code: "H4XK9PWZ")
        guard let url = link.url else { return XCTFail("no url") }
        XCTAssertTrue(url.absoluteString.hasPrefix("sooodreamy://link?"))
        XCTAssertEqual(DeviceLinkURL.parse(url.absoluteString), link)

        // Server-less links round-trip too (manual entry keeps the active
        // server profile).
        let bare = DeviceLinkURL(server: nil, code: "H4XK9PWZ")
        XCTAssertEqual(DeviceLinkURL.parse(bare.url?.absoluteString ?? ""), bare)
    }
}
