import Foundation

// Film-Roulette 🍿 — pure deterministic core, UI-free.
//
// Both partners swipe through the SAME seeded deck (indexes, not titles, so
// display language never matters). A card both liked is a MATCH — the client
// whose swipe completes it annotates that move with `match: {cardIndex,
// title}`, which makes the relay emit a `movie_match` app event (the hook
// Agent A's weekly plan can pick up — see server/src/events.js).
//
// Move protocol: `{kind: "swipe", index, like: Bool, match?: {…}}`.

// MARK: - Events & state

enum MovieRouletteEvent {
    case swipe(member: String, index: Int, like: Bool)
}

struct MovieRouletteState {
    /// member → card index → liked?
    var swipes: [String: [Int: Bool]]
    /// Card indexes BOTH liked, in match-completion order.
    var matches: [Int]

    func swipeCount(of member: String) -> Int { swipes[member]?.count ?? 0 }

    /// Lowest deck index this member has not swiped yet (nil = deck done).
    func nextIndex(of member: String, deckSize: Int) -> Int? {
        let done = swipes[member] ?? [:]
        return (0..<deckSize).first { done[$0] == nil }
    }

    func finished(deckSize: Int, members: [String]) -> Bool {
        members.allSatisfy { swipeCount(of: $0) >= deckSize }
    }
}

// MARK: - Rules

enum MovieRoulette {
    static let defaultDeckSize = 20

    /// Deterministic deck for a session: seeded shuffle of the curated
    /// cards, topped up with the couple's custom titles (always included).
    static func deck(seed: Int, size: Int, custom: [String]) -> [MovieCard] {
        let curatedCount = Swift.max(0, Swift.min(size - custom.count,
                                                  MovieRouletteData.cards.count))
        let curated = MovieRouletteData.cards.seededShuffled(seed: seed).prefix(curatedCount)
        let customCards = custom.map {
            MovieCard(de: $0, en: $0, emoji: "🍿", genre: "custom")
        }
        // Second shuffle mixes the custom cards in — still fully seeded.
        return (Array(curated) + customCards).seededShuffled(seed: seed &+ 1)
    }

    /// Reduces ordered swipe events. Defensive: out-of-range indexes and
    /// re-swipes of the same card are SKIPPED (first swipe counts).
    static func reduce(events: [MovieRouletteEvent], deckSize: Int) -> MovieRouletteState {
        var state = MovieRouletteState(swipes: [:], matches: [])
        for event in events {
            switch event {
            case .swipe(let member, let index, let like):
                guard index >= 0, index < deckSize,
                      state.swipes[member]?[index] == nil else { continue }
                state.swipes[member, default: [:]][index] = like
                if like, isMutualLike(state: state, index: index) {
                    state.matches.append(index)
                }
            }
        }
        return state
    }

    /// True once BOTH recorded swipes for `index` and both are likes.
    private static func isMutualLike(state: MovieRouletteState, index: Int) -> Bool {
        let likes = state.swipes.values.filter { $0[index] == true }.count
        return likes >= 2
    }

    /// Whether MY pending like on `index` would complete a match (drives
    /// the `match` annotation on the outgoing move).
    static func completesMatch(state: MovieRouletteState, index: Int,
                               partner: String) -> Bool {
        state.swipes[partner]?[index] == true
    }
}
