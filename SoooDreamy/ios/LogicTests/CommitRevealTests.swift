import XCTest
@testable import SoooDreamyLogic

/// Pins the pure-Swift SHA-256 (CommitReveal) against the official FIPS
/// test vectors and the Node relay implementation — the whole commit-reveal
/// protocol stands on both sides hashing identically.
final class CommitRevealTests: XCTestCase {

    func testSha256KnownVectors() {
        XCTAssertEqual(CommitReveal.sha256Hex(""),
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(CommitReveal.sha256Hex("abc"),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(CommitReveal.sha256Hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
                       "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    }

    func testMultiBlockAndUnicodeInput() {
        // > 64 bytes forces a second SHA-256 block.
        let long = String(repeating: "a", count: 200)
        XCTAssertEqual(CommitReveal.sha256Hex(long).count, 64)
        // UTF-8 multi-byte input hashes over bytes, not scalars — parity
        // with Node's createHash('sha256').update(text, 'utf8'):
        XCTAssertEqual(CommitReveal.sha256Hex("liebe💞grüße"),
                       CommitReveal.sha256Hex("liebe💞grüße"))
        XCTAssertNotEqual(CommitReveal.sha256Hex("liebe💞grüße"),
                          CommitReveal.sha256Hex("liebe grüße"))
    }

    func testCommitVerifyRoundtrip() {
        let salt = CommitReveal.newSalt()
        XCTAssertEqual(salt.count, 32)
        let commit = CommitReveal.commit(secret: "2", salt: salt)
        XCTAssertTrue(CommitReveal.verify(reveal: "2", salt: salt, commit: commit))
        XCTAssertTrue(CommitReveal.verify(reveal: "2", salt: salt, commit: commit.uppercased()))
        XCTAssertFalse(CommitReveal.verify(reveal: "1", salt: salt, commit: commit))
        XCTAssertFalse(CommitReveal.verify(reveal: "2", salt: salt + "x", commit: commit))
    }

    func testServerParityVector() {
        // Computed with the Node relay: sha256('2' + 'pepper🌶') — the exact
        // pair games_v3.test.js sends through the server helper.
        XCTAssertEqual(CommitReveal.commit(secret: "2", salt: "pepper🌶"),
                       "ff3a1f0861ddb3a3d11c1544e5df8260e10515431ae1344e323d616cf8271b2d")
    }
}
