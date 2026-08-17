import Foundation

// Welle 7 [27]+[28]: die Foundation-only-Hälfte der beiden Chat-Sprach-
// Features. Hier stehen die Regeln, WANN die Übersetzen-Aktion auf einer
// Partner-Bubble erscheint (samt der Stopwort-Heuristik dahinter) und der
// Cache-Vertrag der lokalen Voice-Transkripte. Die Framework-Aufrufe leben
// AUSSCHLIESSLICH in Core/ChatTranslation.swift bzw.
// Core/VoiceTranscription.swift — diese Datei bleibt Linux-testbar
// (Muster: Content/IntelligenceRules.swift).
//
// Produkt-Invarianten (IDEEN_ROADMAP §1.2 + Welle 7):
//   * Beides läuft on-device — der Server sieht weder Quelltext noch
//     Übersetzung noch Transkript, nie.
//   * Nichts passiert automatisch: Übersetzung und Transkript entstehen
//     nur auf eine explizite Kontextaktion hin.
//   * Das Original bleibt heilig — Übersetzungen erscheinen darunter,
//     Transkripte zusätzlich, nichts ersetzt je den Originalinhalt.

// MARK: - Chat-Übersetzung: Angebots-Regeln + Sprach-Heuristik

enum ChatTranslationRules {
    /// So viele echte Buchstaben braucht eine Nachricht, bevor die
    /// Übersetzen-Aktion erscheint — "ok", Zahlen- und Emoji-Nachrichten
    /// bleiben frei von Menü-Rauschen.
    static let minimumLetters = 3

    /// Die Übersetzen-Aktion erscheint NUR auf Partner-Nachrichten, deren
    /// Text nach fremdsprachiger Prosa aussieht: nie auf eigenen Bubbles,
    /// nie auf reinen Links, und nicht, wenn die Stopwort-Heuristik sicher
    /// ist, dass der Text schon in der App-Sprache steht.
    static func offersTranslation(text: String?, isMine: Bool, appLanguage: String) -> Bool {
        guard !isMine, let text else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard letterCount(trimmed) >= minimumLetters else { return false }
        guard !isLinkOnly(trimmed) else { return false }
        return stopwordLanguageGuess(trimmed) != appLanguage
    }

    /// Zielsprache der Session — die Sprache, die die Person liest.
    /// "de"/"en" sind gültige BCP-47-Kennungen für `Locale.Language`.
    static func targetLanguageIdentifier(appLanguage: String) -> String {
        appLanguage == "de" ? "de" : "en"
    }

    /// Payload für die Übersetzungs-Anfrage: nur die Ränder getrimmt —
    /// Zeilenumbrüche im Inneren gehören zur Aussage und bleiben.
    static func normalizedSource(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Sprach-Heuristik

    /// Ehrliche, billige Stopwort-Schätzung — benutzt NUR fürs Menü-Gating:
    /// "de"/"en", wenn mindestens zwei eindeutige Stopwörter (oder deutsche
    /// Umlaute/ß) klar auf eine Sprache zeigen, sonst nil. Der nil-Fall
    /// BIETET die Übersetzung an — die echte Spracherkennung übernimmt das
    /// System während der Übersetzung selbst (source bleibt dort nil).
    static func stopwordLanguageGuess(_ text: String) -> String? {
        let words = text.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
        guard !words.isEmpty else { return nil }
        var germanHits = words.reduce(0) { $0 + (Self.germanStopwords.contains($1) ? 1 : 0) }
        let englishHits = words.reduce(0) { $0 + (Self.englishStopwords.contains($1) ? 1 : 0) }
        // Umlaute/ß sind für sich ein starkes Deutsch-Signal.
        if text.rangeOfCharacter(from: Self.germanMarkerCharacters) != nil {
            germanHits += 2
        }
        if germanHits >= 2 && germanHits > englishHits { return "de" }
        if englishHits >= 2 && englishHits > germanHits { return "en" }
        return nil
    }

    // MARK: Interna

    /// Nur Wörter, die es in GENAU EINER der beiden Sprachen gibt —
    /// Überlappungen wie "was"/"man"/"die"/"in" sind bewusst draußen,
    /// die Heuristik rät lieber gar nicht als falsch.
    private static let germanStopwords: Set<String> = [
        "und", "ich", "du", "nicht", "ist", "das", "der", "ein", "eine",
        "mit", "für", "auf", "wir", "dich", "mir", "dir", "aber", "auch",
        "noch", "wie", "schon", "heute", "morgen", "danke", "bitte",
        "mein", "dein", "kein", "doch", "jetzt", "wenn", "dann", "liebe",
    ]

    private static let englishStopwords: Set<String> = [
        "the", "and", "you", "are", "not", "with", "for", "this",
        "that", "have", "your", "what", "how", "just", "today", "tomorrow",
        "thanks", "please", "but", "too", "very", "really", "about", "now",
        "then", "when", "going", "want", "know", "love", "miss",
    ]

    private static let germanMarkerCharacters = CharacterSet(charactersIn: "äöüÄÖÜß")

    /// Grapheme-level letter count — `CharacterSet.letters` would count
    /// combining marks (emoji variation selectors!) as letters.
    private static func letterCount(_ text: String) -> Int {
        text.filter(\.isLetter).count
    }

    /// Ein-Wort-Nachrichten, die nur ein Link sind — eine URL zu
    /// übersetzen wäre Rauschen.
    private static func isLinkOnly(_ text: String) -> Bool {
        guard !text.contains(where: { $0.isWhitespace }) else { return false }
        let lower = text.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("www.")
    }
}

// MARK: - Voice-Transkripte: Cache-Vertrag + Locale-Wahl

/// Ein lokal gecachtes Transkript — nach Nachricht-Id, in der Liste von
/// alt → neu, damit die Kappung immer den ältesten Eintrag verdrängt.
struct VoiceTranscriptCacheEntry: Codable, Equatable {
    let id: String
    let text: String
}

enum VoiceTranscriptRules {
    /// Cache-Deckel pro Paar — Voice-Notes sind maximal 2 Minuten, 60
    /// Transkripte decken Wochen an Verlauf, ohne UserDefaults grenzenlos
    /// wachsen zu lassen.
    static let cacheLimit = 60

    /// Hängt ein Transkript an (bzw. frischt es auf) und verdrängt die
    /// ältesten Einträge jenseits des Deckels.
    static func appending(_ entry: VoiceTranscriptCacheEntry,
                          to entries: [VoiceTranscriptCacheEntry],
                          limit: Int = cacheLimit) -> [VoiceTranscriptCacheEntry] {
        var result = entries.filter { $0.id != entry.id }
        result.append(entry)
        if result.count > limit {
            result.removeFirst(result.count - limit)
        }
        return result
    }

    /// Wählt die Transkriptions-Locale für die App-Sprache aus den vom
    /// Gerät unterstützten BCP-47-Tags: erst die regionale Voreinstellung
    /// (de-DE / en-US), dann irgendeine Region derselben Sprache, nil wenn
    /// die Sprache gar nicht unterstützt wird (das UI sagt das ehrlich).
    static func matchingLocaleIdentifier(appLanguage: String,
                                         supportedBCP47: [String]) -> String? {
        let language = appLanguage.lowercased()
        let preferred = language == "de" ? "de-DE" : "en-US"
        if let exact = supportedBCP47.first(where: {
            $0.caseInsensitiveCompare(preferred) == .orderedSame
        }) {
            return exact
        }
        return supportedBCP47.first {
            let tag = $0.lowercased()
            return tag == language || tag.hasPrefix(language + "-")
        }
    }

    /// Normalisiert die rohe Analyzer-Ausgabe für die Bubble: Segmente
    /// werden mit Leerzeichen verkettet, also kollabieren Whitespace-Läufe
    /// zu einzelnen Leerzeichen und die Ränder werden getrimmt.
    static func normalizedTranscript(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
