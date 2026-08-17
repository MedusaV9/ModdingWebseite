import XCTest
@testable import SoooDreamyLogic

/// v10.1 — the `sooodreamy://rejoin` deep-link / QR-payload contract shared
/// with the admin web panel and the partner-help QR (docs/REJOIN-QR.md).
final class RejoinLinkTests: XCTestCase {

    // MARK: Server address normalization (shared with Settings)

    func testServerAddressNormalization() {
        // Bare host:port gets the http:// default — the private couple
        // server speaks plain HTTP, never forced to https.
        XCTAssertEqual(ServerAddress.normalize("192.168.1.20:4321"), "http://192.168.1.20:4321")
        XCTAssertEqual(ServerAddress.normalize(" 192.168.1.20:4321 "), "http://192.168.1.20:4321")
        // Explicit schemes survive untouched (http is NOT rewritten).
        XCTAssertEqual(ServerAddress.normalize("http://138.201.60.230:4321"), "http://138.201.60.230:4321")
        XCTAssertEqual(ServerAddress.normalize("https://dreamy.example.com"), "https://dreamy.example.com")
        // Trailing slashes are dropped.
        XCTAssertEqual(ServerAddress.normalize("http://home.local:4321///"), "http://home.local:4321")
        // Garbage → nil.
        XCTAssertNil(ServerAddress.normalize(""))
        XCTAssertNil(ServerAddress.normalize("   "))
        XCTAssertNil(ServerAddress.normalize("http://"))   // scheme without host
    }

    // MARK: Parsing

    func testParsesPartnerHelpLink() {
        let link = RejoinLink.parse(
            "sooodreamy://rejoin?server=http://192.168.1.20:4321&code=AB23CD&replaceCode=WXYZ2345")
        XCTAssertNotNil(link)
        XCTAssertEqual(link?.server, "http://192.168.1.20:4321")
        XCTAssertEqual(link?.code, "AB23CD")
        XCTAssertEqual(link?.replaceCode, "WXYZ2345")
        XCTAssertEqual(link?.proof, .replaceCode(code: "AB23CD", replaceCode: "WXYZ2345"))
    }

    func testParsesAdminPanelTokenLink() {
        // The admin web panel QR carries server URL + previous session token
        // (percent-encoded) — the token alone is a valid rejoin proof.
        let link = RejoinLink.parse(
            "sooodreamy://rejoin?server=http%3A%2F%2F138.201.60.230%3A4321&token=tk_abc.DEF-123")
        XCTAssertEqual(link?.server, "http://138.201.60.230:4321")
        XCTAssertEqual(link?.token, "tk_abc.DEF-123")
        XCTAssertEqual(link?.proof, .token("tk_abc.DEF-123"))
    }

    func testParsesRecoveryKeyLink() {
        let key = "rec_" + String(repeating: "ab12", count: 10)
        let link = RejoinLink.parse("sooodreamy://rejoin?code=ab23cd&recoveryKey=\(key)")
        // Pairing code is uppercased (server compares uppercase)…
        XCTAssertEqual(link?.code, "AB23CD")
        // …the recovery key is passed through verbatim.
        XCTAssertEqual(link?.recoveryKey, key)
        XCTAssertEqual(link?.proof, .recoveryKey(code: "AB23CD", recoveryKey: key))
        XCTAssertNil(link?.server)
    }

    func testAcceptsParameterAliasesAndCaseInsensitiveNames() {
        // The admin panel is built in parallel — give it wiggle room.
        let link = RejoinLink.parse(
            "sooodreamy://rejoin?url=home.local:4321&couplecode=ab23cd&replace=xyz23456")
        XCTAssertEqual(link?.server, "http://home.local:4321")
        XCTAssertEqual(link?.code, "AB23CD")
        XCTAssertEqual(link?.replaceCode, "XYZ23456")

        let upper = RejoinLink.parse("sooodreamy://rejoin?CODE=ab23cd&KEY=secret-key")
        XCTAssertEqual(upper?.code, "AB23CD")
        XCTAssertEqual(upper?.recoveryKey, "secret-key")
    }

    func testCustomReplaceCodesSurviveUntouched() {
        // v10.1 server accepts per-member custom replace codes (≤ 32 chars,
        // digest of trim().toUpperCase()) — inner characters must never be
        // stripped, only uppercased.
        let link = RejoinLink.parse("sooodreamy://rejoin?code=AB23CD&replaceCode=mausi-2010")
        XCTAssertEqual(link?.replaceCode, "MAUSI-2010")
    }

    func testProofPriorityMatchesServerOrder() {
        // Mixed links: recoveryKey wins over token wins over replaceCode —
        // exactly the order POST /api/couples/rejoin checks proofs in.
        let all = RejoinLink(server: nil, code: "AB23CD", recoveryKey: "rec_x123",
                             replaceCode: "WXYZ2345", token: "tok")
        XCTAssertEqual(all.proof, .recoveryKey(code: "AB23CD", recoveryKey: "rec_x123"))

        let tokenAndReplace = RejoinLink(server: nil, code: "AB23CD", recoveryKey: nil,
                                         replaceCode: "WXYZ2345", token: "tok")
        XCTAssertEqual(tokenAndReplace.proof, .token("tok"))

        // recoveryKey / replaceCode without the couple code are NOT complete
        // proofs (the route needs the code to find the couple).
        let keyNoCode = RejoinLink(server: "http://x.local", code: nil,
                                   recoveryKey: "rec_x123", replaceCode: nil, token: nil)
        XCTAssertNil(keyNoCode.proof)
    }

    func testRejectsForeignAndEmptyLinks() {
        XCTAssertNil(RejoinLink.parse("https://rejoin?code=AB23CD"))               // wrong scheme
        XCTAssertNil(RejoinLink.parse("sooodreamy://tab/home"))                    // wrong host
        XCTAssertNil(RejoinLink.parse("sooodreamy://rejoin"))                      // nothing usable
        XCTAssertNil(RejoinLink.parse("sooodreamy://rejoin?code="))                // empty value
        XCTAssertNil(RejoinLink.parse("not a url at all …"))
        // Unknown params alone don't make a link.
        XCTAssertNil(RejoinLink.parse("sooodreamy://rejoin?foo=bar"))
        // …but are ignored next to real ones.
        XCTAssertEqual(RejoinLink.parse("sooodreamy://rejoin?foo=bar&code=AB23CD")?.code, "AB23CD")
    }

    // MARK: Encoding round-trip (partner-help QR payload)

    func testPartnerHelpRoundTrip() {
        let link = RejoinLink.partnerHelp(server: "192.168.1.20:4321",
                                          code: "ab23cd",
                                          replaceCode: "wxyz2345")
        guard let url = link.url else { return XCTFail("no url") }
        XCTAssertTrue(url.absoluteString.hasPrefix("sooodreamy://rejoin?"))

        let parsed = RejoinLink.parse(url.absoluteString)
        XCTAssertEqual(parsed, link)
        XCTAssertEqual(parsed?.proof, .replaceCode(code: "AB23CD", replaceCode: "WXYZ2345"))
    }

    func testEncodingEscapesServerURL() {
        let link = RejoinLink(server: "http://192.168.1.20:4321", code: "AB23CD",
                              recoveryKey: nil, replaceCode: "WXYZ2345", token: nil)
        let s = link.url?.absoluteString ?? ""
        // The inner "//" of the server URL must not produce a second host.
        XCTAssertEqual(RejoinLink.parse(s)?.server, "http://192.168.1.20:4321")
        // Deterministic parameter order → stable QR pixels for the same input.
        XCTAssertEqual(s, link.url?.absoluteString)
    }

    func testEmptyLinkHasNoURL() {
        XCTAssertNil(RejoinLink().url)
        XCTAssertTrue(RejoinLink().isEmpty)
    }
}
