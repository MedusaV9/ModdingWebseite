import Foundation

/// A localized string (German / English). The app is fully bilingual.
struct LText: Hashable {
    let de: String
    let en: String

    /// Resolve for the given language code ("de" or "en").
    func resolved(_ lang: String) -> String { lang == "de" ? de : en }

    /// Replace the `{partner}` placeholder with the partner's name.
    func filled(partner: String, lang: String) -> String {
        resolved(lang).replacingOccurrences(of: "{partner}", with: partner)
    }
}

/// Question of the day — both partners answer, answers reveal once both answered.
struct DailyQuestion: Identifiable, Hashable {
    let id: Int
    let text: LText
}

/// "Who knows who better?" quiz question about the partner.
/// Texts use the `{partner}` placeholder, e.g. "Was ist {partner}s Lieblingsessen?"
struct QuizQuestion: Identifiable, Hashable {
    let id: Int
    let text: LText
}

/// A pair of options — used by both "This or That" and "Would You Rather".
struct ChoicePair: Identifiable, Hashable {
    let id: Int
    let a: LText
    let b: LText
}

/// Truth-or-Dare card. `spice`: 1 = sweet, 2 = flirty, 3 = spicy (tasteful).
struct TruthOrDareItem: Identifiable, Hashable {
    let id: Int
    let isDare: Bool
    let spice: Int
    let text: LText
}

/// The classic "36 questions to fall in love" (Arthur Aron), in 3 sets of 12.
struct Question36: Identifiable, Hashable {
    let id: Int
    let set: Int
    let text: LText
}

/// Emoji riddle: guess the movie/song/place/… from an emoji sequence.
/// `category`: "movie" | "song" | "place" | "food" | "couple" | "activity".
struct EmojiRiddle: Identifiable, Hashable {
    let id: Int
    let emojis: String
    let answer: LText
    let category: String
}

/// Date idea for the generator. `budget`: 0 = free … 3 = splurge.
struct DateIdea: Identifiable, Hashable {
    let id: Int
    let emoji: String
    let title: LText
    let details: LText
    let indoor: Bool
    let budget: Int
    let tags: [String]
}

/// Namespace for all bundled content packs.
/// The data lives in `Content/Data/*.swift` as extensions of this enum.
enum ContentPack {
    /// Deterministic daily question for a given date & couple (same for both partners).
    static func dailyQuestion(dateKey: String, coupleId: String) -> DailyQuestion {
        let seed = (dateKey + coupleId).unicodeScalars.reduce(5381 as UInt64) { ($0 << 5) &+ $0 &+ UInt64($1.value) }
        let list = ContentPack.dailyQuestions
        return list[Int(seed % UInt64(list.count))]
    }
}
