import Foundation

/// A half-written love letter — persisted so multitasking, a window resize
/// or an app kill never eats it. Codable because the whole draft lives in
/// one UserDefaults slot per server profile.
struct LetterDraft: Codable, Equatable {
    var title: String
    var text: String
    /// The armed "Öffnen wenn …" seal token (`nil` = unsealed), in the
    /// same `Message.openWhen` token format the composer sends.
    var sealToken: String?

    /// A draft with nothing worth keeping — its slot gets removed instead
    /// of storing empty strings forever.
    var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (sealToken?.isEmpty ?? true)
    }
}

/// Pure draft-continuity rules — Foundation-only so the Linux LogicTests
/// can pin them down. The storage itself follows the app's existing
/// pattern (`ChatComposerDrafts`): one UserDefaults slot per server
/// profile, because a text written for partner A must never surface in
/// couple context B.
enum DraftContinuityRules {
    /// UserDefaults key of the letter-draft slot for a server profile.
    /// Profileless states (no active server) share one honest "solo" slot
    /// instead of silently dropping the draft.
    static func letterDraftKey(profileID: String?) -> String {
        "sooodreamy.letterDraft.\(profileID ?? "solo")"
    }

    /// A stored draft is only restored into an EMPTY composer. Pre-filled
    /// launches (forwarding a letter as a new one) deliberately keep their
    /// own content — and must never clobber the saved draft either.
    static func shouldRestore(initialTitle: String, initialText: String) -> Bool {
        initialTitle.isEmpty && initialText.isEmpty
    }
}

/// Schlussrunde 6: a daily answer that loses the pin race during an offline
/// replay is preserved as a per-day draft instead of vanishing with the
/// dropped outbox entry — after the next launch the card prefills it under
/// the (adopted) pinned question. Pure rules; storage follows the
/// `LetterDraftStore` pattern in the app target.
enum DailyAnswerDraftRules {
    /// One slot per server profile AND day — yesterday's stranded answer
    /// must never surface under today's question, and profile A's text
    /// never in couple context B.
    static func draftKey(profileID: String?, dateKey: String) -> String {
        "sooodreamy.dailyAnswerDraft.\(profileID ?? "solo").\(dateKey)"
    }

    /// Prefill only an EMPTY editor and only while the day is still
    /// unanswered — a submitted answer or half-typed text always wins.
    static func shouldPrefill(editorText: String, alreadyAnswered: Bool) -> Bool {
        editorText.isEmpty && !alreadyAnswered
    }
}
