import Foundation

/// Dossier 40: the return moment. Pure dramaturgy for the "while you were
/// away" card — hero pick, chip order, bundled sentence — kept UI-free so
/// the emotional priority logic is testable on Linux.
enum MissedInboxLogic {

    /// Only real, otherwise-invisible events become chips (idea 20):
    /// "partner answered the daily" and "your move" are state info that the
    /// daily card and the Play-tab badge already show. Order = fixed weight,
    /// emotion before system (idea 8).
    enum Category: String, CaseIterable {
        case messages, touches, photos, coupons, songs, canvas
    }

    /// Counts decoupled from the network response — `InboxResponse` lives in
    /// the app target, this logic must not.
    struct Snapshot: Equatable {
        var messages = 0
        var touches = 0
        var photos = 0
        var coupons = 0
        var songs = 0
        var canvas = 0
        /// The newest missed message is a sealed letter — announced, never
        /// teased (idea 10).
        var lastMessageIsLetter = false
        /// An unanswered "I need you" signal waits (idea 9).
        var hasOpenNeed = false

        func count(_ category: Category) -> Int {
            switch category {
            case .messages: return messages
            case .touches: return touches
            case .photos: return photos
            case .coupons: return coupons
            case .songs: return songs
            case .canvas: return canvas
            }
        }

        var isEmpty: Bool {
            !hasOpenNeed && Category.allCases.allSatisfy { count($0) == 0 }
        }
    }

    /// The single event celebrated at the top of the card (idea 1). The
    /// fixed priority is emotional, not chronological: an open need beats
    /// everything, then a sealed letter, then felt touches, then photos.
    enum Hero: Equatable {
        case need
        case letter
        case touches(Int)
        case photos(Int)
    }

    static func hero(_ snapshot: Snapshot) -> Hero? {
        if snapshot.hasOpenNeed { return .need }
        if snapshot.lastMessageIsLetter, snapshot.messages > 0 { return .letter }
        if snapshot.touches > 0 { return .touches(snapshot.touches) }
        if snapshot.photos > 0 { return .photos(snapshot.photos) }
        return nil
    }

    /// One checklist entry below the hero.
    struct Chip: Equatable {
        let category: Category
        let count: Int
    }

    /// Everything the hero did not already celebrate, in weight order: the
    /// letter hero absorbs one message, a touches/photos hero absorbs its
    /// whole bucket (the hero line IS that bundle).
    static func chips(_ snapshot: Snapshot, hero: Hero?) -> [Chip] {
        var remaining = snapshot
        switch hero {
        case .letter: remaining.messages = max(0, remaining.messages - 1)
        case .touches: remaining.touches = 0
        case .photos: remaining.photos = 0
        case .need, nil: break
        }
        return Category.allCases.compactMap { category in
            let count = remaining.count(category)
            return count > 0 ? Chip(category: category, count: count) : nil
        }
    }

    /// "3 Herzschläge und ein Foto · +2 mehr" — the bundled rest as one
    /// natural sentence (idea 2); doubles as the VoiceOver label (idea 29).
    static func sentence(chips: [Chip]) -> String {
        let top = chips.prefix(2).map {
            L10n.t("home.missed.phrase.\($0.category.rawValue)", count: $0.count)
        }
        guard !top.isEmpty else { return "" }
        var text = top.joined(separator: L10n.t("home.missed.join"))
        let rest = chips.dropFirst(2).reduce(0) { $0 + $1.count }
        if rest > 0 {
            text += " · " + L10n.t("home.missed.more", ["count": String(rest)])
        }
        return text
    }

    /// The card is a checklist, not a one-shot (ideas 6/7): it dissolves by
    /// itself once every waiting thing was actually visited.
    static func caughtUp(_ snapshot: Snapshot, hero: Hero?, visited: Set<String>) -> Bool {
        if snapshot.hasOpenNeed, !visited.contains("need") { return false }
        return chips(snapshot, hero: hero).allSatisfy { visited.contains($0.category.rawValue) }
            && heroDone(hero, visited: visited)
    }

    private static func heroDone(_ hero: Hero?, visited: Set<String>) -> Bool {
        switch hero {
        case .need: return visited.contains("need")
        case .letter: return visited.contains(Category.messages.rawValue)
        case .touches: return visited.contains(Category.touches.rawValue)
        case .photos: return visited.contains(Category.photos.rawValue)
        case nil: return true
        }
    }
}
