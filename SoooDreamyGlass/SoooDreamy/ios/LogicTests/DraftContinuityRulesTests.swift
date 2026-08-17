import XCTest
@testable import SoooDreamyLogic

/// Pins the letter-draft continuity rules: drafts must survive backgrounding,
/// window resizes and app kills, and must never leak across server profiles.
final class DraftContinuityRulesTests: XCTestCase {
    func testKeysAreSeparatedPerProfile() {
        let a = DraftContinuityRules.letterDraftKey(profileID: "profile-a")
        let b = DraftContinuityRules.letterDraftKey(profileID: "profile-b")
        XCTAssertNotEqual(a, b, "a letter for partner A must never surface in couple context B")
    }

    func testProfilelessStateGetsAStableSlot() {
        XCTAssertEqual(DraftContinuityRules.letterDraftKey(profileID: nil),
                       DraftContinuityRules.letterDraftKey(profileID: nil))
        XCTAssertNotEqual(DraftContinuityRules.letterDraftKey(profileID: nil),
                          DraftContinuityRules.letterDraftKey(profileID: "solo-x"))
    }

    func testOnlyEmptyComposersRestore() {
        XCTAssertTrue(DraftContinuityRules.shouldRestore(initialTitle: "", initialText: ""))
        // Pre-filled launches (forwarding a letter) keep their own content.
        XCTAssertFalse(DraftContinuityRules.shouldRestore(initialTitle: "Für dich", initialText: ""))
        XCTAssertFalse(DraftContinuityRules.shouldRestore(initialTitle: "", initialText: "Mein Schatz…"))
    }

    func testEmptyDraftsAreRecognized() {
        XCTAssertTrue(LetterDraft(title: "", text: "", sealToken: nil).isEmpty)
        XCTAssertTrue(LetterDraft(title: "  \n", text: "\t", sealToken: nil).isEmpty)
        XCTAssertFalse(LetterDraft(title: "Hey", text: "", sealToken: nil).isEmpty)
        XCTAssertFalse(LetterDraft(title: "", text: "…", sealToken: nil).isEmpty)
        // A chosen seal alone is worth keeping — arming it is deliberate.
        XCTAssertFalse(LetterDraft(title: "", text: "", sealToken: "mood:sad").isEmpty)
    }

    func testDraftRoundTripsThroughCodable() throws {
        let draft = LetterDraft(title: "Guten Morgen",
                                text: "Ich denk an dich ❤️",
                                sealToken: "date:2026-12-24")
        let data = try JSONEncoder().encode(draft)
        let decoded = try JSONDecoder().decode(LetterDraft.self, from: data)
        XCTAssertEqual(decoded, draft)
    }

    // MARK: Daily-answer salvage (Schlussrunde 6)

    func testDailyDraftSlotsSeparatePerProfileAndDay() {
        // A stranded answer must never surface under another couple's
        // context or under the NEXT day's question.
        let base = DailyAnswerDraftRules.draftKey(profileID: "p1", dateKey: "2026-08-15")
        XCTAssertNotEqual(base, DailyAnswerDraftRules.draftKey(profileID: "p2", dateKey: "2026-08-15"))
        XCTAssertNotEqual(base, DailyAnswerDraftRules.draftKey(profileID: "p1", dateKey: "2026-08-16"))
        XCTAssertEqual(base, DailyAnswerDraftRules.draftKey(profileID: "p1", dateKey: "2026-08-15"))
        XCTAssertNotEqual(DailyAnswerDraftRules.draftKey(profileID: nil, dateKey: "2026-08-15"),
                          DailyAnswerDraftRules.draftKey(profileID: "solo-x", dateKey: "2026-08-15"))
    }

    func testDailyDraftPrefillsOnlyEmptyUnansweredEditors() {
        XCTAssertTrue(DailyAnswerDraftRules.shouldPrefill(editorText: "", alreadyAnswered: false))
        // Half-typed text always wins over the stored draft.
        XCTAssertFalse(DailyAnswerDraftRules.shouldPrefill(editorText: "Ich wollte sagen…", alreadyAnswered: false))
        // A submitted answer makes the stranded draft stale.
        XCTAssertFalse(DailyAnswerDraftRules.shouldPrefill(editorText: "", alreadyAnswered: true))
        XCTAssertFalse(DailyAnswerDraftRules.shouldPrefill(editorText: "x", alreadyAnswered: true))
    }
}
