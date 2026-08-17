import Foundation

// „Der große Runde" — pure logic for the recovery-key UX and the
// rebuilt onboarding. Foundation-only so `swift test` exercises it on Linux.
//
// Server contract (see docs/API.md „Pairing recovery"):
//   * recovery key  = "rec_" + 40 lowercase hex chars (20 random bytes),
//     returned EXACTLY ONCE by POST /api/couples, /join and /recovery-key.
//   * replace code  = 8 chars from ABCDEFGHJKLMNPQRSTUVWXYZ23456789
//     (no I/O/0/1 — unambiguous when read aloud), 15-minute TTL, single-use.
//   * pairing code  = 6 chars from the same alphabet.

/// Formatting + validation for the pairing-recovery secrets.
enum RecoveryKit {
    /// Alphabet shared by pairing codes and replace codes (server-side
    /// REPLACE_CODE_ALPHABET) — deliberately drops I, O, 0 and 1.
    static let codeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    static let replaceCodeLength = 8
    static let pairingCodeLength = 6

    static let recoveryKeyPrefix = "rec_"
    static let recoveryKeyHexLength = 40

    // MARK: Recovery key

    /// Loose sanity check for manual entry: "rec_" + 40 hex chars. Grouped
    /// display form ("rec_ab12 cd34 …") passes too — spaces are cosmetic.
    /// (The server is the real judge — this only gates obvious typos.)
    static func looksLikeRecoveryKey(_ raw: String) -> Bool {
        let normalized = normalizedRecoveryKey(raw)
        if normalized.hasPrefix(recoveryKeyPrefix) {
            let hex = normalized.dropFirst(recoveryKeyPrefix.count)
            return hex.count == recoveryKeyHexLength && hex.allSatisfy { $0.isHexDigit }
        }
        return normalized.count >= 4
    }

    /// Display grouping for the ceremony sheet: the hex tail in blocks of 4
    /// ("rec_ ab12 cd34 …") — much easier to write down on paper.
    static func grouped(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(recoveryKeyPrefix) else { return trimmed }
        let hex = Array(trimmed.dropFirst(recoveryKeyPrefix.count))
        var blocks: [String] = []
        var index = 0
        while index < hex.count {
            let end = min(index + 4, hex.count)
            blocks.append(String(hex[index..<end]))
            index = end
        }
        return recoveryKeyPrefix + blocks.joined(separator: " ")
    }

    /// Undoes `grouped` + clipboard noise before sending to the server.
    static func normalizedRecoveryKey(_ raw: String) -> String {
        raw.lowercased().filter { !$0.isWhitespace }
    }

    /// Settings row preview: enough to recognize the key, useless to a
    /// shoulder-surfer ("rec_ab12 ···· 89ef").
    static func masked(_ key: String) -> String {
        let normalized = normalizedRecoveryKey(key)
        guard normalized.hasPrefix(recoveryKeyPrefix),
              normalized.count == recoveryKeyPrefix.count + recoveryKeyHexLength else {
            return "····"
        }
        let hex = normalized.dropFirst(recoveryKeyPrefix.count)
        return "\(recoveryKeyPrefix)\(hex.prefix(4)) ···· \(hex.suffix(4))"
    }

    // MARK: Replace / pairing codes

    /// Uppercases and drops everything outside the code alphabet, capped at
    /// `length` — shared by the pairing-code and replace-code text fields.
    static func normalizedCode(_ raw: String, length: Int) -> String {
        String(raw.uppercased().filter { codeAlphabet.contains($0) }.prefix(length))
    }

    static func isCompleteReplaceCode(_ raw: String) -> Bool {
        normalizedCode(raw, length: replaceCodeLength).count == replaceCodeLength
    }

    // The server accepts per-member CUSTOM replace codes (≤ 32 chars,
    // digest of trim().toUpperCase()) next to the standard 8-char ones — so
    // the entry field must not strip "confusable" characters anymore.

    /// Server-side asString cap for replaceCode.
    static let replaceCodeMaxLength = 32

    /// Uppercases and caps at the server maximum; inner characters (digits,
    /// dashes, even spaces of custom codes) stay untouched. Trim outer
    /// whitespace at submit time, not while typing.
    static func normalizedFlexibleCode(_ raw: String) -> String {
        String(raw.uppercased().prefix(replaceCodeMaxLength))
    }

    /// Loose gate for the entry field: standard codes are 8 chars, custom
    /// codes at least 4 visible characters. The server digest check is the
    /// real judge — this only prevents obviously incomplete submissions.
    static func looksLikeReplaceCode(_ raw: String) -> Bool {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4
    }

    /// Remaining validity of a replace code, for the countdown pill.
    /// Returns nil once expired.
    static func replaceCodeRemaining(expiresAt: Date, now: Date = Date()) -> TimeInterval? {
        let remaining = expiresAt.timeIntervalSince(now)
        return remaining > 0 ? remaining : nil
    }

    /// "14:59" — mm:ss countdown label for the replace-code sheet.
    static func countdownLabel(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// The v10 onboarding pages moved to Content/OnboardingScript.swift
// (Re-Eval Runde 2: the script gained the hero/vignette split and the
// file the Fix-C mandate names).
