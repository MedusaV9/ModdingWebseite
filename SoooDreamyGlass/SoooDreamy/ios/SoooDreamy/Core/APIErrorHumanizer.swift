import Foundation

/// Pure mapping from the server's machine error catalog (`{error: "code"}`
/// plus HTTP status, see docs/API.md) to localized human sentences that
/// always name a way out. Lives on primitives so the table is fully covered
/// by Linux Swift tests — the `APIError` bridge stays in AppState.
enum APIErrorHumanizer {
    struct HumanizedError: Equatable {
        /// Ready-to-toast localized text (DE/EN via L10n).
        let text: String
        /// `couple_data_quarantined` — the server is protecting damaged data;
        /// callers give this its own app state instead of a passing toast.
        let isQuarantine: Bool
        /// Parsed `retry-after` seconds for 429 responses.
        let retryAfterSeconds: Int?
    }

    /// Server codes with a hand-written sentence. Everything else falls back
    /// to an honest per-status-family text (which still shows the code).
    private static let codeKeys: Set<String> = [
        "too_long", "too_large", "too_many_videos", "couple_full",
        "unknown_code", "bad_recovery_key", "session_revoked",
        "unknown_session", "expired", "already_redeemed", "wrong_turn",
        "game_ended", "game_not_active", "game_lease_held", "no_partner",
        "not_yours", "not_for_you", "cooldown_active", "too_soon",
        "effect_cooldown", "server_capacity", "couple_data_quarantined",
        // W8C board & duel games (sentences live in GamesL10n —
        // L10n.t merges all feature tables into one lookup).
        "capture_required", "empty_pit", "no_flip", "pass_not_allowed",
        "already_matched",
        // Schlussrunde 4: pool-growth race — the first answer pinned a
        // different question; the card refreshes to the pinned one.
        "daily_question_mismatch",
        // Post & Sendungen (FullRelease P6-B): Zeitpost + echoes.
        "post_limit", "echo_expired", "echo_taken", "bad_deliver_at",
    ]

    static func humanize(status: Int, code: String?, message: String?,
                         retryAfter: Int? = nil) -> HumanizedError {
        if code == "couple_data_quarantined" {
            return HumanizedError(text: L10n.t("error.code.couple_data_quarantined"),
                                  isQuarantine: true, retryAfterSeconds: nil)
        }
        if status == 429 {
            let seconds = max(1, retryAfter ?? 5)
            let key = (code.map(codeKeys.contains) == true)
                ? "error.code.\(code!)" : "error.status.429"
            return HumanizedError(text: L10n.t(key, ["s": String(seconds)]),
                                  isQuarantine: false, retryAfterSeconds: seconds)
        }
        if let code, codeKeys.contains(code) {
            return HumanizedError(text: L10n.t("error.code.\(code)"),
                                  isQuarantine: false, retryAfterSeconds: nil)
        }
        let familyKey: String
        switch status {
        case 400, 422: familyKey = "error.status.400"
        case 403: familyKey = "error.status.403"
        case 404: familyKey = "error.status.404"
        case 409: familyKey = "error.status.409"
        case 413: familyKey = "error.status.413"
        case 500...: familyKey = "error.status.500"
        default: familyKey = "error.status.other"
        }
        return HumanizedError(text: L10n.t(familyKey, ["code": code ?? "HTTP \(status)"]),
                              isQuarantine: false, retryAfterSeconds: nil)
    }

    /// Transport failures (no server verdict): distinguish the three states a
    /// human can actually act on — offline, timeout, unreachable host.
    /// `urlErrorCode` is `URLError.code.rawValue`; kept as a raw Int so the
    /// mapping compiles (and tests run) without importing anything.
    static func humanizeTransport(urlErrorCode: Int?) -> String {
        switch urlErrorCode {
        case -1009, -1020: // notConnectedToInternet, dataNotAllowed
            return L10n.t("error.transport.offline")
        case -1001:        // timedOut
            return L10n.t("error.transport.timeout")
        case -1003, -1004: // cannotFindHost, cannotConnectToHost
            return L10n.t("error.transport.unreachable")
        default:
            return L10n.t("error.network")
        }
    }
}
