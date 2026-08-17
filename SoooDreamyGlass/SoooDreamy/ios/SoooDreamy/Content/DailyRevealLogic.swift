import Foundation

/// Pure rules for the daily-answer reveal ceremony (K-03) — Foundation-only
/// so the jackpot detection is Linux-testable like the rest of Content.
enum DailyRevealLogic {
    /// Comparison form of an answer: lowercased, punctuation-free,
    /// whitespace collapsed. "Pizza!!" and " pizza " are the same thought.
    static func normalized(_ text: String) -> String {
        let lowered = text.lowercased()
        let kept = lowered.unicodeScalars.filter {
            !CharacterSet.punctuationCharacters.contains($0)
                && !CharacterSet.symbols.contains($0)
        }
        return String(String.UnicodeScalarView(kept))
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
    }

    /// The emotional jackpot: both partners wrote the same thing.
    static func isJackpot(mine: String?, theirs: String?) -> Bool {
        guard let mine, let theirs else { return false }
        let a = normalized(mine)
        let b = normalized(theirs)
        return !a.isEmpty && a == b
    }

    /// The smaller echo: a shared significant word (≥ 4 letters) — carries
    /// "Ihr habt beide ‚Pizza' gesagt" when the full answers differ.
    static func sharedWord(mine: String?, theirs: String?) -> String? {
        guard let mine, let theirs, !isJackpot(mine: mine, theirs: theirs) else { return nil }
        let mineWords = significantWords(mine)
        let theirWords = significantWords(theirs)
        return mineWords.first { theirWords.contains($0) }
    }

    private static func significantWords(_ text: String) -> [String] {
        normalized(text)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 4 }
    }
}
