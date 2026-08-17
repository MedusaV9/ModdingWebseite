import Foundation

// MARK: - „Erinnerungen" — mirrors server/src/memories.js

/// `{unit: "months"|"years", n}` — whole years collapse server-side.
struct MemoryDistance: Codable, Hashable {
    let unit: String
    let n: Int

    /// "Vor 3 Monaten" / "1 year ago" — localized via MemoriesLogic key.
    var label: String {
        L10n.t(MemoriesLogic.agoLabelKey(unit: unit, n: n), ["n": String(n)])
    }
}

/// One "on this day" memory. `kind` is "photo" or "daily"; unknown future
/// kinds decode fine and are skipped by the card.
struct OnThisDayItem: Codable, Hashable, Identifiable {
    let kind: String
    let dateKey: String
    let distance: MemoryDistance
    let photo: MagazinePhoto?
    let questionId: Int?
    let customText: String?
    let answers: [String: String]?

    var id: String { "\(kind):\(dateKey):\(photo?.id ?? "-")" }
}

struct OnThisDayResponse: Codable, Hashable {
    let dateKey: String
    let daysTogether: Int
    /// Whole-month distance to the couple's anniversary (if today is one).
    let monthiversary: MemoryDistance?
    let items: [OnThisDayItem]
}

/// One milestone of „Unsere Geschichte". Only the fields matching `kind`
/// are set — everything else stays nil (tolerant of future kinds).
struct StoryEntry: Codable, Hashable, Identifiable {
    let id: String
    let kind: String
    let dateKey: String
    let teaser: String?
    let photo: StoryPhoto?
    let gameType: String?
    let questionId: Int?
    let customText: String?
    let title: String?
    let emoji: String?
    let n: Int?
    let badgeId: String?
}

struct StoryPhoto: Codable, Hashable, Identifiable {
    let id: String
    let url: String
    let thumbUrl: String?
    let caption: String?
}

struct StoryResponse: Codable, Hashable {
    let sinceKey: String
    let daysTogether: Int
    let entries: [StoryEntry]
}

// MARK: - API

extension API {
    /// nil date = today. Deterministic: both partners get the same list.
    func onThisDay(date: String? = nil) async throws -> OnThisDayResponse {
        var query: [String: String] = [:]
        if let date { query["date"] = date }
        return try await request("GET", "/api/on-this-day", query: query,
                                 as: OnThisDayResponse.self)
    }

    func story() async throws -> StoryResponse {
        try await request("GET", "/api/story", as: StoryResponse.self)
    }
}
