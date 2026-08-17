import XCTest
@testable import SoooDreamyLogic

final class RepairConversationLogicTests: XCTestCase {
    func testSixStepSequenceProtectsUninterruptedTurns() {
        let expected: [(String, RepairTurnKind)] = [
            ("a", .feeling), ("b", .mirror), ("b", .feeling),
            ("a", .mirror), ("a", .agreement), ("b", .agreement),
        ]
        for (step, turn) in expected.enumerated() {
            XCTAssertEqual(
                RepairConversationLogic.expectedTurn(step: step, creatorID: "a", partnerID: "b"),
                RepairExpectedTurn(memberID: turn.0, kind: turn.1)
            )
        }
        XCTAssertNil(RepairConversationLogic.expectedTurn(step: 6, creatorID: "a", partnerID: "b"))
    }

    func testCooldownAndActorBothGateSubmission() {
        let now = Date(timeIntervalSince1970: 5_000)
        XCTAssertTrue(RepairConversationLogic.canSubmit(
            memberID: "a", kind: .feeling, step: 0,
            creatorID: "a", partnerID: "b", cooldownUntil: nil, now: now
        ))
        XCTAssertFalse(RepairConversationLogic.canSubmit(
            memberID: "b", kind: .feeling, step: 0,
            creatorID: "a", partnerID: "b", cooldownUntil: nil, now: now
        ))
        XCTAssertFalse(RepairConversationLogic.canSubmit(
            memberID: "a", kind: .feeling, step: 0,
            creatorID: "a", partnerID: "b",
            cooldownUntil: now.addingTimeInterval(60), now: now
        ))
    }

    func testConsiderationEnvelopeRejectsPlaintextAndExpiredData() {
        let now = Date(timeIntervalSince1970: 5_000)
        XCTAssertThrowsError(try ConsiderationCipherEnvelope(
            ciphertext: "plain text",
            visibility: "gentle",
            expiresAt: now.addingTimeInterval(60)
        ).validate(now: now))

        let ciphertext = Data(repeating: 7, count: 32).base64EncodedString()
        XCTAssertNoThrow(try ConsiderationCipherEnvelope(
            ciphertext: ciphertext,
            visibility: "detail",
            expiresAt: now.addingTimeInterval(60)
        ).validate(now: now))
        XCTAssertThrowsError(try ConsiderationCipherEnvelope(
            ciphertext: ciphertext,
            visibility: "gentle",
            expiresAt: now
        ).validate(now: now))
    }

    func testSensitivePromptPacksAreCompleteBilingualAndUnique() {
        let packs: [([RelationshipSupportPrompt], Int)] = [
            (RelationshipSupportContent.repairPrompts, 30),
            (RelationshipSupportContent.considerationHints, 20),
            (RelationshipSupportContent.gratitudePrompts, 25),
        ]
        for (pack, expectedCount) in packs {
            XCTAssertEqual(pack.count, expectedCount)
            XCTAssertEqual(Set(pack.map(\.id)).count, pack.count)
            XCTAssertTrue(pack.allSatisfy {
                !$0.text.de.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !$0.text.en.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
        }
    }
}
