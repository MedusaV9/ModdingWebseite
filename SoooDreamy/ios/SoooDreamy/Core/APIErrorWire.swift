import Foundation

// The typed half of the server's error bodies (contract v11) — split out of
// API.swift so the Linux logic-test package can pin the decoding. The server
// speaks TWO shapes for the same payloads:
//
//   * details-wrapped: `{error, message, details: {gameId, lease}}`
//     (`game_lease_held`)
//   * top-level:       `{error, message, current}` on rev-guard `409
//     conflict` (events/lists) and `{error, message, generation}` on canvas
//     `409 stale_generation` — the fields sit NEXT to `error`, not inside
//     `details`.
//
// The old client only read `details`, so the direct conflict adoption never
// ran against the live server (Re-Eval Runde 2). `APIErrorBody` accepts both
// forms; nested fields win, top-level fills the gaps.

/// Typed `details` object of selected error responses (contract v11):
/// `game_lease_held {gameId, lease}`, `409 conflict {current}` on
/// rev-guarded calendar/list mutations, `409 stale_generation {generation}`
/// on canvas strokes, `409 daily_question_mismatch {questionId,
/// questionText}` on the daily pin guard (Schlussrunde 5). Every field is
/// optional — the client never breaks when a server omits or extends the
/// payload.
struct APIErrorDetails: Decodable {
    let gameId: String?
    let lease: GameLease?
    /// The server's current resource on a `conflict` — raw JSON so ONE
    /// details type serves events and lists alike.
    let current: JSONValue?
    let generation: Int?
    /// The pinned daily question on `daily_question_mismatch`: the
    /// authoritative id, plus the bilingual text stored with the pin
    /// (null when the pinning client sent none) so the loser can render
    /// the question even without knowing the id.
    let questionId: Int?
    let questionText: LText?
}

/// One decoded error response body. A malformed/extended `details` object
/// must never cost the error code and message — everything decodes
/// forgivingly.
struct APIErrorBody: Decodable {
    let error: String?
    let message: String?
    let details: APIErrorDetails?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        let nested = try? c.decodeIfPresent(APIErrorDetails.self, forKey: .details)
        let topCurrent = try? c.decodeIfPresent(JSONValue.self, forKey: .current)
        let topGeneration = try? c.decodeIfPresent(Int.self, forKey: .generation)
        let topQuestionId = try? c.decodeIfPresent(Int.self, forKey: .questionId)
        let topQuestionText = try? c.decodeIfPresent(LText.self, forKey: .questionText)
        let current = nested?.current ?? topCurrent
        let generation = nested?.generation ?? topGeneration
        let questionId = nested?.questionId ?? topQuestionId
        let questionText = nested?.questionText ?? topQuestionText
        if nested == nil, current == nil, generation == nil,
           questionId == nil, questionText == nil {
            details = nil
        } else {
            details = APIErrorDetails(gameId: nested?.gameId, lease: nested?.lease,
                                      current: current, generation: generation,
                                      questionId: questionId, questionText: questionText)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case error, message, details, current, generation, questionId, questionText
    }
}
