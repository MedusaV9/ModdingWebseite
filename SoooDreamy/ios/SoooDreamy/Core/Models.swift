import Foundation

// MARK: - Server models (mirror docs/API.md exactly)

struct Member: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var avatar: String
    var color: String
    var mood: String?
    var moodNote: String?
    var moodUpdatedAt: Date?
    var online: Bool?
    var lastSeenAt: Date?
    var joinedAt: Date?
}

struct Couple: Codable, Hashable {
    let id: String
    let code: String
    var name: String?
    var anniversary: String?
    let createdAt: Date
    var members: [Member]
}

struct AuthResponse: Codable {
    let token: String
    let coupleId: String
    let memberId: String
    let couple: Couple
}

struct CoupleResponse: Codable {
    let couple: Couple
    let me: String
}

enum TouchKind: String, Codable, CaseIterable, Identifiable {
    case heartbeat, kiss, hug, missyou, tickle, thinking
    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .heartbeat: return "💓"
        case .kiss: return "😘"
        case .hug: return "🫂"
        case .missyou: return "🥺"
        case .tickle: return "🪶"
        case .thinking: return "💭"
        }
    }

    var titleKey: String { "touch.\(rawValue)" }
}

struct Touch: Codable, Identifiable, Hashable {
    let id: String
    let type: TouchKind
    let senderId: String
    let createdAt: Date
}

enum MessageKind: String, Codable {
    case text, letter, voice
}

struct Message: Codable, Identifiable, Hashable {
    let id: String
    let senderId: String
    let type: MessageKind
    let text: String?
    let title: String?
    let audioUrl: String?
    let durationSec: Double?
    /// Letters only: seal tag like "sad", "missme", "custom:<text>" —
    /// the recipient opens the letter when the moment fits.
    let openWhen: String?
    /// Emoji reactions: emoji → memberIds who reacted.
    var reactions: [String: [String]]?
    let createdAt: Date
}

struct Photo: Codable, Identifiable, Hashable {
    let id: String
    let uploaderId: String
    let caption: String?
    let url: String
    let thumbUrl: String?
    let width: Int?
    let height: Int?
    /// memberIds who marked this photo as a favorite.
    var favorites: [String]?
    let createdAt: Date

    func isFavorite(of memberId: String?) -> Bool {
        guard let memberId else { return false }
        return favorites?.contains(memberId) ?? false
    }
}

// MARK: - Wordle duel

struct WordleResult: Codable, Hashable {
    let memberId: String
    let rows: Int
    let win: Bool
    let grid: String            // emoji grid (🟩🟨⬛ lines)
    let lang: String
    let finishedAt: Date
}

/// Per-member view: partner's result stays hidden until I finished (no spoilers).
/// Results are per language — the duel compares same-language boards.
struct WordleDayResponse: Codable, Hashable {
    let dateKey: String
    let lang: String?
    let mine: WordleResult?
    let partner: WordleResult?
    let partnerFinished: Bool
}

struct WordleHistoryResponse: Codable {
    let days: [WordleDayResponse]
}

// MARK: - Love coupons

struct Coupon: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    var emoji: String
    var note: String?
    let createdBy: String
    let forMember: String
    var redeemedAt: Date?
    let createdAt: Date
}

/// One entry of a member's mood history (server keeps the last ~60 per member).
struct MoodEntry: Codable, Identifiable, Hashable {
    let id: String
    let memberId: String
    let mood: String
    let moodNote: String?
    let createdAt: Date
}

struct EventItem: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    var emoji: String
    var date: String            // "YYYY-MM-DD"
    var repeatsYearly: Bool
    let createdBy: String
    let createdAt: Date
}

struct BucketItem: Codable, Identifiable, Hashable {
    let id: String
    var text: String
    var emoji: String?
    var done: Bool
    var doneAt: Date?
    let createdBy: String
    let createdAt: Date
}

struct CanvasStroke: Codable, Identifiable, Hashable {
    let id: String
    let memberId: String
    let color: String
    let width: Double
    let tool: String            // "pen" | "marker" | "eraser"
    let points: [[Double]]      // normalized 0..1
    let createdAt: Date
}

enum GameKind: String, Codable, CaseIterable, Identifiable {
    case quiz, thisorthat, wouldyourather, truthordare, questions36
    var id: String { rawValue }
}

struct GameMove: Codable, Identifiable, Hashable {
    let id: String
    let memberId: String
    let data: JSONValue
    let createdAt: Date
}

struct GameSession: Codable, Identifiable, Hashable {
    let id: String
    let type: String
    var state: String           // "lobby" | "active" | "ended"
    let createdBy: String
    var payload: JSONValue?
    var result: JSONValue?
    var moves: [GameMove]
    let createdAt: Date

    var kind: GameKind? { GameKind(rawValue: type) }
}

struct DailyEntry: Codable, Hashable {
    let dateKey: String
    let questionId: Int?
    let myAnswer: String?
    let partnerAnswer: String?
    let bothAnswered: Bool
    let streak: Int
}

struct TouchStats: Codable, Hashable {
    let total: Int
    let byType: [String: Int]
}

struct Stats: Codable, Hashable {
    let daysTogether: Int?
    let touchesSent: TouchStats
    let touchesReceived: TouchStats
    let messages: Int
    let photos: Int
    let bucketDone: Int
    let bucketTotal: Int
    let dailyStreak: Int
    let dailyAnswered: Int
    let gamesPlayed: Int
}

struct HealthResponse: Codable {
    let ok: Bool
    let name: String
    let version: String
}

// MARK: - List wrappers

struct MessagesResponse: Codable { let messages: [Message] }
struct PhotosResponse: Codable { let photos: [Photo] }
struct MoodsResponse: Codable { let moods: [MoodEntry] }
struct DailyListResponse: Codable { let entries: [DailyEntry] }
struct CouponsResponse: Codable { let coupons: [Coupon] }
struct CouponResponse: Codable { let coupon: Coupon }
struct EventsResponse: Codable { let events: [EventItem] }
struct BucketResponse: Codable { let items: [BucketItem] }
struct StrokesResponse: Codable { let strokes: [CanvasStroke] }
struct TouchesResponse: Codable { let touches: [Touch] }
struct GameResponse: Codable { let game: GameSession? }
struct MemberResponse: Codable { let member: Member }
struct CoupleOnlyResponse: Codable { let couple: Couple }
struct MessageResponse: Codable { let message: Message }
struct PhotoResponse: Codable { let photo: Photo }
struct EventResponse: Codable { let event: EventItem }
struct BucketItemResponse: Codable { let item: BucketItem }
struct StrokeResponse: Codable { let stroke: CanvasStroke }
struct TouchResponse: Codable { let touch: Touch }
struct GameOnlyResponse: Codable { let game: GameSession }
struct MoveResponse: Codable { let move: GameMove }

// MARK: - WebSocket events

enum ServerEventType: String, Codable {
    case welcome, presence, touch, message
    case memberUpdated = "member_updated"
    case coupleUpdated = "couple_updated"
    case coupleDissolved = "couple_dissolved"
    case partnerJoined = "partner_joined"
    case dailyAnswer = "daily_answer"
    case canvasStroke = "canvas_stroke"
    case canvasClear = "canvas_clear"
    case photoAdded = "photo_added"
    case photoUpdated = "photo_updated"
    case photoDeleted = "photo_deleted"
    case canvasStrokeDeleted = "canvas_stroke_deleted"
    case eventAdded = "event_added"
    case eventUpdated = "event_updated"
    case eventDeleted = "event_deleted"
    case bucketAdded = "bucket_added"
    case bucketUpdated = "bucket_updated"
    case bucketDeleted = "bucket_deleted"
    case gameCreated = "game_created"
    case gameStarted = "game_started"
    case gameMove = "game_move"
    case gameEnded = "game_ended"
    case messageUpdated = "message_updated"
    case wordleResult = "wordle_result"
    case couponAdded = "coupon_added"
    case couponRedeemed = "coupon_redeemed"
    case couponDeleted = "coupon_deleted"
    case typing, pong
}

/// A raw event received from the server socket. `payload` is re-decoded
/// by interested consumers via `decode(_:)`.
struct ServerEvent {
    let type: ServerEventType
    let rawData: Data

    private struct PayloadBox<T: Decodable>: Decodable { let payload: T }

    func decode<T: Decodable>(_ type: T.Type) -> T? {
        try? API.decoder.decode(PayloadBox<T>.self, from: rawData).payload
    }
}

extension Notification.Name {
    /// Posted on the main queue for every incoming `ServerEvent` (object = ServerEvent).
    static let serverEvent = Notification.Name("sooodreamy.serverEvent")
}

// MARK: - Event payloads

struct PresencePayload: Codable {
    let memberId: String
    let online: Bool
    let lastSeenAt: Date?
}

struct WelcomePayload: Codable {
    let memberId: String
    let coupleId: String
    let partnerOnline: Bool
}

struct TypingPayload: Codable {
    let memberId: String
    let isTyping: Bool
}

struct IdPayload: Codable { let id: String }

struct GameMovePayload: Codable {
    let gameId: String
    let move: GameMove
}

// MARK: - JSONValue (free-form JSON for game payloads/moves)

enum JSONValue: Codable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    // Convenience accessors
    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    var numberValue: Double? { if case .number(let n) = self { return n }; return nil }
    var intValue: Int? { numberValue.map { Int($0) } }
    var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }

    subscript(key: String) -> JSONValue? { objectValue?[key] }
}
