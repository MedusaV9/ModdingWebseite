import Foundation

// MARK: - Server models (mirror docs/API.md exactly)

struct Member: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var avatar: String
    var color: String
    var petName: String?
    var mood: String?
    var moodNote: String?
    var moodUpdatedAt: Date?
    var online: Bool?
    var lastSeenAt: Date?
    var lastReadAt: Date?
    /// "currently listening to …" — the server nils it after 60 min.
    var nowPlaying: NowPlaying?
    /// 🟢🟡🔴 after-work energy light — the server nils it after 12 h.
    var energy: MemberEnergy?
    /// 🎯/😴 presence mode — the server nils it once `until` passed.
    var presence: MemberPresence?
    var joinedAt: Date?
}

/// „Nähe trotz Distanz": a member's declared focus/sleep mode. The
/// partner's app shows a gentle hint instead of expecting an answer.
struct MemberPresence: Codable, Hashable {
    /// Raw server value; `PresenceModeKind(rawValue:)` for typed access.
    let mode: String
    let note: String?
    /// Auto-expiry — nil means "until I turn it off".
    let until: Date?
    let setAt: Date

    var kind: PresenceModeKind? { PresenceModeKind(rawValue: mode) }
}

/// A member's now-playing music status (set manually or from the
/// system player; auto-hidden by the server once older than 60 minutes).
struct NowPlaying: Codable, Hashable {
    let title: String
    let artist: String?
    let setAt: Date
}

struct Couple: Codable, Hashable {
    let id: String
    let code: String
    var name: String?
    var anniversary: String?
    var palette: CouplePalette?
    var monogramStyle: MonogramStyle?
    let createdAt: Date
    var members: [Member]
}

struct AuthResponse: Codable {
    let token: String
    let sessionId: String?
    let expiresAt: Date?
    let coupleId: String
    let memberId: String
    let couple: Couple
    /// v10: create/join return the one-time recovery key; the app stores it
    /// in the iCloud keychain right away. Rejoin responses carry none.
    let recoveryKey: String?
    /// v10 rejoin responses: true + "recoveryKey" | "token" | "replaceCode".
    let rejoined: Bool?
    let method: String?
}

// MARK: - Multi-device sessions (docs/API.md „Multi-device sessions & fanout")

/// One row of `GET /api/sessions` — a device seat of the CURRENT member
/// (bounded view, never bearer values). `revokedAt != nil` rows are dead
/// but retained; `current` is the server's "this is the calling session".
struct DeviceSession: Codable, Identifiable, Hashable {
    let id: String
    let deviceId: String?
    let deviceName: String?
    let createdAt: Date?
    let lastUsedAt: Date?
    let expiresAt: Date?
    let revokedAt: Date?
    let current: Bool?

    var isRevoked: Bool { revokedAt != nil }

    /// "This device" marking: the server flag, backed by comparing the
    /// locally persisted sessionId (Keychain) against the row id.
    func isThisDevice(ownSessionId: String?) -> Bool {
        if current == true { return true }
        guard let ownSessionId, !ownSessionId.isEmpty else { return false }
        return id == ownSessionId
    }
}

struct SessionsResponse: Codable { let sessions: [DeviceSession] }

/// `POST /api/sessions/link-code` — the one-time device link code minted on
/// a signed-in device. With `?format=qr` the server additionally renders
/// `deepLink` (`sooodreamy://link?server=…&code=…`) as SVG and echoes the
/// base URL it embedded.
struct LinkCodeResponse: Codable {
    let linkCode: String
    let expiresAt: Date
    let createdAt: Date?
    let memberId: String?
    let deepLink: String?
    let svg: String?
    let server: String?
}

/// `device_linked` WS frame — sent to all of MY member's existing devices
/// when a new one attaches (the partner is deliberately not notified).
struct DeviceLinkedPayload: Codable {
    let memberId: String
    let sessionId: String?
    let deviceId: String?
    let deviceName: String?
    let linkedAt: Date?
}

/// `sessions_changed` WS frame (contract v11): a device seat of `memberId`
/// changed. All fields beyond `memberId` are tolerated as optional so
/// future reasons keep decoding.
struct SessionsChangedPayload: Codable {
    let memberId: String
    let reason: String?
    let sessionId: String?
    let deviceName: String?
}

// v10 „Der große Runde" — pairing recovery client (server contract v6.1)

struct RecoveryKeyStatus: Codable {
    let configured: Bool
    let createdAt: Date?
}

struct RecoveryKeyIssued: Codable {
    let recoveryKey: String
    let createdAt: Date
    let rotated: Bool
}

struct ReplaceCodeResponse: Codable {
    let replaceCode: String
    let expiresAt: Date
    let target: Member
}

struct CoupleResponse: Codable {
    let couple: Couple
    let me: String
}

enum TouchKind: String, Codable, CaseIterable, Identifiable {
    case heartbeat, kiss, hug, missyou, tickle, thinking
    // FullRelease P6-B: „Stolz auf dich" + „Halt durch".
    case stolz
    case halteDurch = "haltedurch"
    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .heartbeat: return "💓"
        case .kiss: return "😘"
        case .hug: return "🫂"
        case .missyou: return "🥺"
        case .tickle: return "🪶"
        case .thinking: return "💭"
        case .stolz: return "⭐"
        case .halteDurch: return "✊"
        }
    }

    var titleKey: String { "touch.\(rawValue)" }
}

struct Touch: Codable, Identifiable, Hashable {
    let id: String
    let type: TouchKind
    let senderId: String
    let createdAt: Date
    /// P6-B echo reply: true on a touch that was "sent back".
    var echo: Bool? = nil
    /// Id of the original touch this one echoes (journal chains).
    var echoOf: String? = nil
    /// True when a Zeitpost delivery (not a live tap) created this touch.
    var viaPost: Bool? = nil
}

enum MessageKind: String, Codable {
    case text, letter, voice, photo, sticker
}

enum MessageEffect: String, Codable, CaseIterable, Identifiable {
    case hearts, snow, sparkle, fireworks, slam, invisible
    var id: String { rawValue }
}

struct Message: Codable, Identifiable, Hashable {
    let id: String
    let senderId: String
    /// Stable client id for durable outbox retries; nil on pre-v4 messages.
    let clientMessageId: String?
    let type: MessageKind
    let text: String?
    let title: String?
    let audioUrl: String?
    let durationSec: Double?
    /// Photo messages only: id of the referenced gallery photo.
    /// The photo has its own lifetime — its media may 404 after deletion.
    let photoId: String?
    /// Letters only: seal tag like "sad", "missme", "custom:<text>" —
    /// the recipient opens the letter when the moment fits.
    let openWhen: String?
    let effect: MessageEffect?
    let sticker: StickerRecipe?
    /// Emoji reactions: emoji → memberIds who reacted.
    var reactions: [String: [String]]?
    /// Set when the sender edited the text (text/letter only);
    /// nil = never edited. `createdAt` (and thus ordering) never changes.
    var editedAt: Date?
    let createdAt: Date
}

struct Photo: Codable, Identifiable, Hashable {
    let id: String
    let uploaderId: String
    var caption: String?
    let url: String
    let thumbUrl: String?
    let width: Int?
    let height: Int?
    /// Optional album name (free string) — nil = not filed in any album.
    var album: String?
    /// memberIds who marked this photo as a favorite.
    var favorites: [String]?
    /// EXIF capture time, read client-side before the re-encode strips
    /// metadata; nil for canvas exports and pre-EXIF uploads.
    let takenAt: Date?
    let createdAt: Date

    /// The gallery sorts and groups by when the moment HAPPENED, not by
    /// when someone got around to uploading it.
    var sortDate: Date { takenAt ?? createdAt }

    func isFavorite(of memberId: String?) -> Bool {
        guard let memberId else { return false }
        return favorites?.contains(memberId) ?? false
    }
}

/// A shared gallery video (streamed from the server with Range support).
struct Video: Codable, Identifiable, Hashable {
    let id: String
    let uploaderId: String
    var caption: String?
    let url: String
    var thumbUrl: String?
    let width: Int?
    let height: Int?
    /// Playback length in seconds (rounded to 0.1 s by the server).
    let duration: Double?
    /// File size on the server — shown in the player info line.
    let bytes: Int?
    /// memberIds who marked this video as a favorite.
    var favorites: [String]?
    let createdAt: Date

    func isFavorite(of memberId: String?) -> Bool {
        guard let memberId else { return false }
        return favorites?.contains(memberId) ?? false
    }

    /// "1:07" style duration badge for the grid.
    var durationLabel: String? {
        guard let duration, duration > 0 else { return nil }
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Spicy Vault

/// Public KDF parameters + PIN verifier for the end-to-end encrypted vault.
/// The server stores this openly — it contains no secrets (the verifier can
/// only be opened with the key derived from the couple's vault PIN).
struct VaultConfig: Codable, Hashable {
    let kdf: String
    let iterations: Int
    /// Base64 random per-couple salt.
    let salt: String
    /// Base64 AES-GCM sealed box of a known plaintext — decrypting it
    /// successfully proves the entered PIN is right.
    let verifier: String
    let createdBy: String?
    let createdAt: Date?
}

/// One encrypted vault blob as the server sees it. Everything sensitive
/// (caption, poster, the content itself) lives INSIDE the ciphertext.
struct VaultItem: Codable, Identifiable, Hashable {
    let id: String
    let uploaderId: String
    /// Coarse hint only ("photo" | "video" | "note") so the grid can show
    /// a matching placeholder while locked/undecrypted.
    let kind: String
    let url: String
    let bytes: Int?
    let createdAt: Date
}

struct VaultConfigResponse: Codable { let config: VaultConfig? }
struct VaultItemsResponse: Codable { let items: [VaultItem] }
struct VaultItemResponse: Codable { let item: VaultItem }

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

// MARK: - Shared soundtrack

struct Song: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    var artist: String?
    var note: String?
    var link: String?
    let addedBy: String
    var heartedBy: [String]?
    let createdAt: Date

    func isHearted(by memberId: String?) -> Bool {
        guard let memberId else { return false }
        return heartedBy?.contains(memberId) ?? false
    }
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
    /// Optional expiry — an unredeemed coupon past this date can no longer
    /// be redeemed (the server answers `409 expired`).
    var expiresAt: Date?
    let createdAt: Date

    /// Expired = past its expiry date and never redeemed.
    func isExpired(at now: Date = Date()) -> Bool {
        guard redeemedAt == nil, let expiresAt else { return false }
        return expiresAt <= now
    }
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
    /// Optimistic-concurrency revision (contract v11): mutations send it
    /// back as `ifRev`; a mismatch answers `409 conflict`. Old servers
    /// omit the field — the client then mutates without the guard.
    var rev: Int? = nil
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
    case quiz, thisorthat, wouldyourather, truthordare, questions36, emojiriddle
    // Realtime games
    case connectfour, photomemory, quizduel
    // Games & activities
    case battleship, pictionary, kniffel, movieroulette, stadtlandfluss
    case twotruths, dailyquests
    // Games Wave II
    case wordchain, hangman, bingo
    // Word & party trio — completes parity with the server's 28-type
    // manifest (docs/API.md "Game manifest", drift-watched by LogicTests).
    case wordleduo, rps, story
    // W8C board & duel games
    case dame, reversi, kaesekaestchen, gomoku, mancala, memoryduo
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
    /// Input leases (Welle 6): which device of each member currently
    /// drives this session, keyed by memberId. Absent on old servers —
    /// every consumer fails open (see GameLeaseRules).
    var leases: [String: GameLease]?
    /// Server-authoritative "whose turn is it", three-state like
    /// `MoveResponse` (contract v11/v12): outer `.none` = field missing
    /// (old server → consumers fall back to the local last-move
    /// derivation), `.some(nil)` = EXPLICITLY nobody (no-turn types such
    /// as the daily-quests checklist, simultaneous phases — the fallback
    /// must stay silent), `.some(id)` = explicit holder. A plain optional
    /// collapsed "explicit null" into "missing" here, so a REST reconcile
    /// after a WS gap resurrected "du bist dran" from the last-mover
    /// heuristic on games that await nobody (see GameTurnRules).
    var turnMemberId: String?? = .none

    var kind: GameKind? { GameKind(rawValue: type) }

    private enum CodingKeys: String, CodingKey {
        case id, type, state, createdBy, payload, result, moves, createdAt,
             leases, turnMemberId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        state = try container.decode(String.self, forKey: .state)
        createdBy = try container.decode(String.self, forKey: .createdBy)
        payload = try container.decodeIfPresent(JSONValue.self, forKey: .payload)
        result = try container.decodeIfPresent(JSONValue.self, forKey: .result)
        moves = try container.decode([GameMove].self, forKey: .moves)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        leases = try container.decodeIfPresent([String: GameLease].self, forKey: .leases)
        turnMemberId = try GameTurnRules.decodeVerdict(from: container,
                                                       key: .turnMemberId)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(state, forKey: .state)
        try container.encode(createdBy, forKey: .createdBy)
        try container.encodeIfPresent(payload, forKey: .payload)
        try container.encodeIfPresent(result, forKey: .result)
        try container.encode(moves, forKey: .moves)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(leases, forKey: .leases)
        // Three-state round trip: an explicit null must survive as null,
        // a missing field as absence — a synthesized encoder flattens both.
        switch turnMemberId {
        case .none: break
        case .some(nil): try container.encodeNil(forKey: .turnMemberId)
        case .some(let holder?): try container.encode(holder, forKey: .turnMemberId)
        }
    }
}

struct SeasonAggregateMatch: Codable, Identifiable, Hashable {
    let id: String
    let type: String
    let monthKey: String
    let createdAt: Date
    let scores: [String: Int]
    let source: String
}

struct SeasonAggregateResponse: Codable, Hashable {
    let month: String?
    let matches: [SeasonAggregateMatch]
    let months: [String]
    let total: Int
}

struct DailyEntry: Codable, Hashable {
    let dateKey: String
    let questionId: Int?
    /// Bilingual text stored with the pin (Schlussrunde 5) — lets this
    /// device render the pinned question even when its bundled pool does
    /// not know `questionId` (mixed-version couple). Old servers omit it.
    let questionText: LText?
    let myAnswer: String?
    let partnerAnswer: String?
    let bothAnswered: Bool
    let streak: Int
    /// Set on "custom days" — the couple's own question replaces the
    /// pack question. `authorId` stays nil for the partner until BOTH
    /// answered (classic reveal); pre-7.0 servers simply omit the field.
    let customQuestion: DailyCustomQuestion?
}

/// The couple-pool question asked on a custom day.
struct DailyCustomQuestion: Codable, Hashable {
    let id: String
    let text: String
    let authorId: String?
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
    /// Optional so the app still decodes pre-2.0 server responses.
    let videos: Int?
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

// MARK: - Widget snapshot (thin mirror of GET /api/widget-snapshot)

/// One-call server payload for home-screen widgets. Named `…Response` (with
/// nested parts) because `WidgetSnapshot` is taken by the App Group blob in
/// Shared/SharedBridge.swift, which compiles into the same targets.
struct WidgetSnapshotResponse: Codable, Hashable {
    struct Partner: Codable, Hashable {
        let id: String
        let name: String
        let avatar: String
        let color: String
        let mood: String?
        let moodNote: String?
        let moodUpdatedAt: Date?
        let online: Bool
        let lastSeenAt: Date?
        let energy: MemberEnergy?
    }

    struct Me: Codable, Hashable {
        let id: String
        let name: String
        let avatar: String
        let color: String
    }

    struct CoupleInfo: Codable, Hashable {
        let id: String
        let name: String?
        let anniversary: String?    // "YYYY-MM-DD"
    }

    struct LatestPhoto: Codable, Hashable {
        let id: String
        let url: String
        let thumbUrl: String?
        let caption: String?
        let favorites: [String]
    }

    struct NextEvent: Codable, Hashable {
        let id: String
        let title: String
        let emoji: String?
        let date: String            // resolved next occurrence, "YYYY-MM-DD" (yearly events wrap)
        let repeatsYearly: Bool
    }

    struct GoalSummary: Codable, Hashable {
        let id: String
        let title: String
        let emoji: String?
        let targetValue: Double
        let unit: String?
        let targetDate: String?
        let total: Double
        let percent: Double
    }

    struct LevelSummary: Codable, Hashable {
        let level: Int
        let title: LocalizedText
        let progress: Double
        let xp: Int
    }

    let partner: Partner?           // nil on a single-member couple
    let me: Me
    let couple: CoupleInfo
    let daysTogether: Int
    let streak: Int
    let bothAnsweredToday: Bool
    let dailyAnsweredByMe: Bool
    /// Pinned daily question id (nil before the first answer / old server).
    let dailyQuestionId: Int?
    /// The server-UTC day `dailyQuestionId`/`dailyQuestion` belong to —
    /// clients apply the pin only when this matches their LOCAL day
    /// (midnight/timezone straddle, Schlussrunde 5). Nil on old servers,
    /// which disables the pin rather than guessing.
    let dailyDateKey: String?
    /// Bilingual text stored with the pin (nil without one) — renders the
    /// pinned question even when the local pool doesn't know the id.
    let dailyQuestion: LText?
    let latestPhoto: LatestPhoto?   // newest favorited, else newest overall
    let nextEvent: NextEvent?       // soonest upcoming
    let canvasStrokeCount: Int
    let canvasUpdatedAt: Date?
    let goal: GoalSummary?
    let level: LevelSummary?
    let serverTime: Date
}

// MARK: - Inbox (GET /api/inbox?since=ISO)

/// Aggregated "missed while you were away" activity strictly after `since`.
/// Mirrors the server shape: one `{count, last?}` bucket per category — the
/// buckets (and their counts) stay optional so the client tolerates servers
/// that omit categories. Untyped `last` teasers (touch/photo/coupon) are
/// ignored; only the message teaser is consumed for the dashboard card.
struct InboxResponse: Codable, Hashable {
    struct Bucket: Codable, Hashable {
        let count: Int?
    }

    /// Teaser of the newest missed message (`text` truncated server-side).
    struct MessageTeaser: Codable, Hashable {
        let id: String
        let senderId: String?
        let kind: String?
        let text: String?
        let createdAt: Date?
    }

    struct MessagesBucket: Codable, Hashable {
        let count: Int?
        let last: MessageTeaser?
    }

    /// "Du bist dran!" digest — open games where I should act.
    struct GamesBucket: Codable, Hashable {
        struct AwaitingGame: Codable, Hashable {
            let gameId: String
            let type: String
        }

        let count: Int?
        let awaitingMe: [AwaitingGame]?
    }

    /// Need button digest: new signals for me since `since`, plus the
    /// newest still-unacknowledged one so app-open can surface it (no push).
    struct NeedsBucket: Codable, Hashable {
        let count: Int?
        let openNeed: NeedSignal?
    }

    /// Teaser of the newest missed touch (contract v11) — old servers send
    /// a bare `{count}` bucket, which decodes with `last == nil`.
    struct TouchTeaser: Codable, Hashable {
        let type: String?
        let createdAt: Date?
    }

    struct TouchesBucket: Codable, Hashable {
        let count: Int?
        let last: TouchTeaser?
    }

    let messages: MessagesBucket?
    let touches: TouchesBucket?
    let photos: Bucket?
    let couponsForMe: Bucket?
    let songs: Bucket?
    let canvasStrokes: Bucket?
    let games: GamesBucket?
    let needsForMe: NeedsBucket?
    let dailyPartnerAnswered: Bool?
    let serverTime: Date?

    var messageCount: Int { messages?.count ?? 0 }
    var touchCount: Int { touches?.count ?? 0 }
    var photoCount: Int { photos?.count ?? 0 }
    var couponCount: Int { couponsForMe?.count ?? 0 }
    var songCount: Int { songs?.count ?? 0 }
    var canvasCount: Int { canvasStrokes?.count ?? 0 }
    var gamesCount: Int { games?.count ?? 0 }
    var needsCount: Int { needsForMe?.count ?? 0 }
    var partnerAnsweredDaily: Bool { dailyPartnerAnswered ?? false }

    var total: Int {
        messageCount + touchCount + photoCount + couponCount + songCount
            + canvasCount + gamesCount + needsCount + (partnerAnsweredDaily ? 1 : 0)
    }
    var isEmpty: Bool { total == 0 }
}

// MARK: - List wrappers

struct MessagesResponse: Codable { let messages: [Message] }
struct PhotosResponse: Codable { let photos: [Photo] }
struct MoodsResponse: Codable { let moods: [MoodEntry] }
struct DailyListResponse: Codable { let entries: [DailyEntry] }
struct CouponsResponse: Codable { let coupons: [Coupon] }
struct CouponResponse: Codable { let coupon: Coupon }
struct SongsResponse: Codable { let songs: [Song] }
struct SongResponse: Codable { let song: Song }
struct EventsResponse: Codable { let events: [EventItem] }
struct BucketResponse: Codable { let items: [BucketItem] }
/// `GET /api/canvas` — strokes plus the board `generation` (contract v11):
/// strokes POST it back; a stale value answers `409 stale_generation`.
/// Old servers omit the field — strokes then post without the guard.
struct StrokesResponse: Codable {
    let strokes: [CanvasStroke]
    var generation: Int? = nil
}
/// Decodes an array while SKIPPING elements that fail to decode — a server
/// ahead of this app version may fan out touches with kinds this build does
/// not know; old clients must drop the entry, never the whole list.
struct LossyArray<Element: Decodable>: Decodable {
    let elements: [Element]

    private struct AnyDecodable: Decodable {}

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var out: [Element] = []
        while !container.isAtEnd {
            let before = container.currentIndex
            if let value = try? container.decode(Element.self) {
                out.append(value)
            }
            // A failed decode may not advance the slot — skip it explicitly
            // (and bail out if even that cannot move, to avoid spinning).
            if container.currentIndex == before {
                _ = try? container.decode(AnyDecodable.self)
                if container.currentIndex == before { break }
            }
        }
        elements = out
    }
}

/// `GET /api/touches/recent` — lossy on purpose (unknown future TouchKinds
/// are skipped instead of failing the whole history).
struct TouchesResponse: Decodable {
    let touches: [Touch]

    private enum CodingKeys: String, CodingKey { case touches }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        touches = try container.decode(LossyArray<Touch>.self, forKey: .touches).elements
    }
}
struct GameResponse: Codable { let game: GameSession? }
struct MemberResponse: Codable { let member: Member }
struct CoupleOnlyResponse: Codable { let couple: Couple }
struct MessageResponse: Codable { let message: Message }
struct PhotoResponse: Codable { let photo: Photo }
struct VideosResponse: Codable { let videos: [Video] }
struct VideoResponse: Codable { let video: Video }
struct EventResponse: Codable { let event: EventItem }
struct BucketItemResponse: Codable { let item: BucketItem }
struct StrokeResponse: Codable { let stroke: CanvasStroke }
struct TouchResponse: Codable { let touch: Touch }
/// `POST /api/touches` — outbox contract (v11): a replay the server already
/// committed answers `{duplicate:true}` (touch may be omitted). Both shapes
/// are success; old servers keep answering the plain `{touch}`.
struct TouchSendResponse: Codable {
    let touch: Touch?
    let duplicate: Bool?
}
struct GameOnlyResponse: Codable { let game: GameSession }
/// `POST /api/games/:id/move` — the accepted move; on a DECISIVE move of the
/// W8C board games the server ends the session in the same request and the
/// response additionally carries the final `game` (result + state "ended").
/// `duplicate: true` (contract v11) marks an idempotent replay hit — e.g. a
/// retried final move on an already-ended game; the carried `game` is
/// adopted like any decisive-move response.
/// `turnMemberId` (contract v12) is the post-move turn holder, three-state:
/// outer `.none` = field missing (old server → local fallback), `.some(nil)`
/// = explicitly nobody (decisive move), `.some(id)` = explicit holder.
struct MoveResponse: Codable {
    let move: GameMove
    let game: GameSession?
    var duplicate: Bool? = nil
    var turnMemberId: String?? = .none

    private enum CodingKeys: String, CodingKey {
        case move, game, duplicate, turnMemberId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        move = try container.decode(GameMove.self, forKey: .move)
        game = try container.decodeIfPresent(GameSession.self, forKey: .game)
        duplicate = try container.decodeIfPresent(Bool.self, forKey: .duplicate)
        turnMemberId = try GameTurnRules.decodeVerdict(from: container,
                                                       key: .turnMemberId)
    }
}
/// `GET /api/games?limit=` — past sessions, newest first.
struct GamesListResponse: Codable { let games: [GameSession] }
/// `POST /api/messages/read` — server timestamp of the read receipt.
struct MessagesReadResponse: Codable { let at: Date }

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
    /// Ephemeral live co-drawing relay (in-progress stroke, not persisted).
    case canvasLive = "canvas_live"
    case photoAdded = "photo_added"
    case photoUpdated = "photo_updated"
    case photoDeleted = "photo_deleted"
    case videoAdded = "video_added"
    case videoUpdated = "video_updated"
    case videoDeleted = "video_deleted"
    case vaultConfigSet = "vault_config_set"
    case vaultItemAdded = "vault_item_added"
    case vaultItemDeleted = "vault_item_deleted"
    case vaultReset = "vault_reset"
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
    /// Input lease changed hands (member-only fanout, Welle 6).
    case gameLease = "game_lease"
    case messageUpdated = "message_updated"
    case wordleResult = "wordle_result"
    case couponAdded = "coupon_added"
    case couponRedeemed = "coupon_redeemed"
    case couponDeleted = "coupon_deleted"
    case songAdded = "song_added"
    case songUpdated = "song_updated"
    case songDeleted = "song_deleted"
    case messageDeleted = "message_deleted"
    case messageRead = "message_read"
    case haptic
    case hapticPatternAdded = "haptic_pattern_added"
    case hapticPatternUpdated = "haptic_pattern_updated"
    case hapticPatternDeleted = "haptic_pattern_deleted"
    // Couple features
    case checkin
    case listAdded = "list_added"
    case listUpdated = "list_updated"
    case listDeleted = "list_deleted"
    case hugQueued = "hug_queued"
    case hugOpened = "hug_opened"
    case potdSubmitted = "potd_submitted"
    case nowPlayingChanged = "now_playing"
    // Rituals & relationship
    case daymemo
    case capsuleSealed = "capsule_sealed"
    case capsuleOpened = "capsule_opened"
    case capsuleDeleted = "capsule_deleted"
    case need
    case needAcked = "need_acked"
    case goalAdded = "goal_added"
    case goalUpdated = "goal_updated"
    case goalDeleted = "goal_deleted"
    case weekplanAvailability = "weekplan_availability"
    case weekplanSlotAdded = "weekplan_slot_added"
    case weekplanSlotUpdated = "weekplan_slot_updated"
    case weekplanSlotDeleted = "weekplan_slot_deleted"
    case energy
    case magazineSeen = "magazine_seen"
    // Calm relationship-support tools
    case repairChanged = "repair_changed"
    case considerationChanged = "consideration_changed"
    case goodthings
    // Seasonal countdown calendars
    case seasonCalendarChanged = "season_calendar_changed"
    // „Eure Woche" weekly review
    case weekHighlight = "week_highlight"
    case weekReviewSeen = "week_review_seen"
    // Level & platform
    case appEvent = "app_event"
    case levelUp = "level_up"
    case badgeUnlocked = "badge_unlocked"
    case questCompleted = "quest_completed"
    case iconGift = "icon_gift"
    case iconGiftOpened = "icon_gift_opened"
    case duetStart = "duet_start"
    case heartbeatTap = "heartbeat_tap"
    case datenightUpdate = "datenight_update"
    // „Nähe trotz Distanz"
    case presenceMode = "presence_mode"
    case pulse
    case pulseFelt = "pulse_felt"
    // Post & Sendungen (FullRelease P6-B)
    /// A Zeitpost note arrived (couple broadcast on delivery).
    case postNote = "post_note"
    /// MY member scheduled a post on another device (never the partner).
    case postScheduled = "post_scheduled"
    /// MY member canceled a scheduled post on another device.
    case postCanceled = "post_canceled"
    // Multi-device: a NEW device of MY member attached via link code.
    case deviceLinked = "device_linked"
    /// A device session of MY member changed (linked, revoked, expired —
    /// contract v11). The device manager reloads its list on this; frames
    /// from servers that don't send it simply never arrive.
    case sessionsChanged = "sessions_changed"
    case typing, pong
}

/// A raw event received from the server socket. `payload` is re-decoded
/// by interested consumers via `decode(_:)`.
struct ServerEvent {
    let type: ServerEventType
    let rawData: Data

    private struct PayloadBox<T: Decodable>: Decodable { let payload: T }
    private struct OriginBox: Decodable { let origin: EventOrigin? }

    func decode<T: Decodable>(_ type: T.Type) -> T? {
        try? API.decoder.decode(PayloadBox<T>.self, from: rawData).payload
    }

    /// Top-level `origin` marker on member-caused frames (multi-device).
    /// Nil on system frames and pre-multi-device servers — consumers must
    /// treat that as "not me" (see MultiDeviceRules).
    var origin: EventOrigin? {
        (try? API.decoder.decode(OriginBox.self, from: rawData))?.origin
    }
}

extension Notification.Name {
    /// Posted on the main queue for every incoming `ServerEvent` (object = ServerEvent).
    static let serverEvent = Notification.Name("sooodreamy.serverEvent")
    /// Posted once when the server closes the socket with the terminal
    /// revocation code (4001) — this device's session was revoked remotely.
    static let sessionRevoked = Notification.Name("sooodreamy.sessionRevoked")
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

/// `game_move` fanout frame. `turnMemberId` (contract v12) names the turn
/// holder AFTER this move — extra moves keep it with the mover, a decisive
/// move sends an explicit null. Three-state like `MoveResponse`: outer
/// `.none` = field missing (old server), so consumers may fall back to the
/// last-mover derivation ONLY then.
struct GameMovePayload: Codable {
    let gameId: String
    let move: GameMove
    var turnMemberId: String?? = .none

    private enum CodingKeys: String, CodingKey {
        case gameId, move, turnMemberId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gameId = try container.decode(String.self, forKey: .gameId)
        move = try container.decode(GameMove.self, forKey: .move)
        turnMemberId = try GameTurnRules.decodeVerdict(from: container,
                                                       key: .turnMemberId)
    }
}

/// `game_lease` event AND `POST /api/games/:id/takeover` response: which of
/// MY devices drives a game now (input lease, Welle 6). `reason` is
/// "acquired" (first valid move / silent inheritance) or "takeover"; the
/// REST response carries none.
struct GameLeasePayload: Codable {
    let gameId: String
    let memberId: String
    let lease: GameLease?
    let reason: String?
}

/// `message_read` event: a member marked the chat as read at `at`.
struct MessageReadPayload: Codable {
    let memberId: String
    let at: Date
}

// MARK: - v9.0 „Nähe trotz Distanz"

/// A queued/relayed thinking-of-you pulse (the haptic pattern is derived
/// client-side from `kind` — see PulseKind.timeline).
struct Pulse: Codable, Identifiable, Hashable {
    let id: String
    let kind: String
    let senderId: String
    let createdAt: Date
    let feltAt: Date?

    var pulseKind: PulseKind? { PulseKind(rawValue: kind) }
}

struct PulseResponse: Codable { let pulse: Pulse }
/// `POST /api/pulses` — same duplicate contract as `TouchSendResponse`.
struct PulseSendResponse: Codable {
    let pulse: Pulse?
    let duplicate: Bool?
}
struct PulsesResponse: Codable { let pulses: [Pulse] }
struct PulsesSeenResponse: Codable {
    let ok: Bool
    let count: Int
}

/// `presence_mode` event: a member set or cleared their focus/sleep mode.
struct PresenceModePayload: Codable {
    let memberId: String
    let presence: MemberPresence?
}

/// `pulse_felt` event: the partner's phone played my pulses (ids listed).
struct PulseFeltPayload: Codable {
    let memberId: String
    let ids: [String]
}

struct PresenceUpdateResponse: Codable { let presence: MemberPresence }

// MARK: - Post & Sendungen (FullRelease P6-B)

/// One open Zeitpost (mine only — the partner never sees pending posts).
/// `kind` / `type` / `pulseKind` stay raw strings so a newer server's
/// future kinds keep decoding; typed access via the computed accessors.
struct ScheduledPost: Codable, Identifiable, Hashable {
    let id: String
    let kind: String            // "touch" | "pulse" | "note"
    let type: String?
    let pulseKind: String?
    let note: String?
    let deliverAt: Date
    let senderId: String
    let createdAt: Date

    var postKind: PostKind? { PostKind(rawValue: kind) }
    var touchKind: TouchKind? { type.flatMap(TouchKind.init(rawValue:)) }
    var pulse: PulseKind? { pulseKind.flatMap(PulseKind.init(rawValue:)) }
}

struct ScheduledPostsResponse: Codable { let posts: [ScheduledPost] }

/// `POST /api/post/schedule` — same duplicate contract as `TouchSendResponse`.
struct ScheduledPostSendResponse: Codable {
    let post: ScheduledPost?
    let duplicate: Bool?
}

/// One line of the shared journal („Posteingang der Zärtlichkeiten").
struct PostJournalEntry: Codable, Identifiable, Hashable {
    let id: String
    let kind: String            // "touch" | "pulse" | "note"
    let type: String?
    let pulseKind: String?
    let note: String?
    let senderId: String
    let createdAt: Date
    let echo: Bool?
    let echoOf: String?
    let viaPost: Bool?

    var postKind: PostKind? { PostKind(rawValue: kind) }
    var touchKind: TouchKind? { type.flatMap(TouchKind.init(rawValue:)) }
    var pulse: PulseKind? { pulseKind.flatMap(PulseKind.init(rawValue:)) }
    var isEcho: Bool { echo == true }
    var isZeitpost: Bool { viaPost == true }
}

struct PostJournalResponse: Codable { let entries: [PostJournalEntry] }

/// A delivered Zeitpost note (the only artifact type Zeitpost invents).
struct PostNote: Codable, Identifiable, Hashable {
    let id: String
    let text: String
    let senderId: String
    let createdAt: Date
}

/// `post_note` WS event: a scheduled note just arrived.
struct PostNotePayload: Codable { let note: PostNote }

/// `post_scheduled` WS event (sender's other devices only).
struct PostScheduledPayload: Codable { let post: ScheduledPost }

/// `post_canceled` WS event (sender's other devices only).
struct PostCanceledPayload: Codable { let id: String }

// MARK: - v2.0 couple features

/// One check-in day: `memberId → ISO time` per kind. Missing = not yet.
struct CheckinDay: Codable, Hashable, Identifiable {
    let dateKey: String
    let morning: [String: Date]
    let night: [String: Date]

    var id: String { dateKey }

    func checkedIn(_ memberId: String?, kind: String) -> Bool {
        guard let memberId else { return false }
        return (kind == "morning" ? morning : night)[memberId] != nil
    }
}

struct CheckinsResponse: Codable {
    let days: [CheckinDay]
    let streak: Int
}

struct CheckinDayResponse: Codable {
    let day: CheckinDay
    let streak: Int
}

/// `checkin` WS event.
struct CheckinEventPayload: Codable {
    let memberId: String
    let kind: String
    let day: CheckinDay
    let streak: Int
}

/// A shared list (shopping, movies, …) with checkable items.
struct SharedList: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var emoji: String?
    let createdBy: String
    let createdAt: Date
    var items: [SharedListItem]
    /// Optimistic-concurrency revision (contract v11) — see `EventItem.rev`.
    var rev: Int? = nil

    var openCount: Int { items.filter { !$0.done }.count }
}

struct SharedListItem: Codable, Identifiable, Hashable {
    let id: String
    var text: String
    var done: Bool
    var doneAt: Date?
    let createdBy: String
    let createdAt: Date
}

struct SharedListsResponse: Codable { let lists: [SharedList] }
struct SharedListResponse: Codable { let list: SharedList }

/// A queued hug — sent while the partner sleeps, opened when they wake up.
struct Hug: Codable, Identifiable, Hashable {
    let id: String
    let from: String
    let to: String
    let note: String?
    let emoji: String
    let createdAt: Date
    var openedAt: Date?
}

struct HugsResponse: Codable { let hugs: [Hug] }
struct HugResponse: Codable { let hug: Hug }

/// Photo of the day: per member the submitted gallery photo for a dateKey.
struct PotdEntry: Codable, Hashable {
    let photoId: String
    let submittedAt: Date
}

struct PotdDay: Codable, Identifiable, Hashable {
    let dateKey: String
    let entries: [String: PotdEntry]

    var id: String { dateKey }
}

struct PotdDaysResponse: Codable { let days: [PotdDay] }
struct PotdDayResponse: Codable { let day: PotdDay }

/// `potd_submitted` WS event.
struct PotdEventPayload: Codable {
    let dateKey: String
    let memberId: String
    let photoId: String
    let day: PotdDay
}

/// `now_playing` WS event (nowPlaying nil = cleared).
struct NowPlayingEventPayload: Codable {
    let memberId: String
    let nowPlaying: NowPlaying?
}

struct NowPlayingResponse: Codable { let nowPlaying: NowPlaying }

/// "Unser Jahr" — everything the server still remembers about one year.
/// Early-year numbers can be lower bounds (capped lists roll off).
struct YearReview: Codable, Hashable {
    let year: Int
    let generatedAt: Date
    let photosAdded: Int
    let videosAdded: Int
    let messagesByMember: [String: Int]
    let touchesByMember: [String: Int]
    let topTouchType: [String: String?]
    let gamesPlayed: Int
    let gameWins: [String: Int]
    let wordleDaysPlayed: Int
    let wordleWins: [String: Int]
    let dailyBothAnswered: Int
    let checkinDaysBoth: Int
    let checkinStreak: Int
    let hugsSent: Int
    let hugsOpened: Int
    let couponsRedeemed: Int
    let songsAdded: Int
    let bucketDone: Int
    let eventsCreated: Int
    let potdDays: Int
}

// MARK: - JSONValue (free-form JSON for game payloads/moves)
// The enum itself lives in Core/JSONValue.swift (Foundation-only, part of
// the Linux logic-test package next to the API error wire decoding).

// MARK: - Level, Badges, Quest & Platform

/// Server-delivered DE/EN string pair (level titles etc.).
struct LocalizedText: Codable, Hashable {
    let de: String
    let en: String

    var resolved: String { L10n.isGerman ? de : en }
}

/// `GET /api/level` — the couple's relationship level.
struct LevelState: Codable, Hashable {
    let xp: Int
    let level: Int
    let title: LocalizedText
    /// XP inside the current level / XP the level spans (ring display).
    let levelXp: Int
    let nextLevelXp: Int
    let progress: Double
    let maxTitleLevel: Int
}

/// One badge on the shelf. Secret badges stay disguised until unlocked.
struct BadgeState: Codable, Hashable, Identifiable {
    struct Progress: Codable, Hashable {
        let current: Int
        let target: Int
    }

    let id: String
    let secret: Bool
    let unlocked: Bool
    let unlockedAt: Date?
    let progress: Progress
}

struct BadgesResponse: Codable { let badges: [BadgeState] }

/// Onboarding quest ("first week"): 7 derived steps.
struct QuestStep: Codable, Hashable, Identifiable {
    let id: String
    let done: Bool
}

struct QuestState: Codable, Hashable {
    let steps: [QuestStep]
    let done: Bool
    let completedAt: Date?
    let isNewCouple: Bool
    let bonusXp: Int
}

/// A pending (or just-opened) app-icon gift from the partner.
struct IconGift: Codable, Hashable {
    let id: String
    let icon: String
    let note: String?
    let fromMemberId: String
    let sentAt: Date
    let openedAt: Date?
}

struct IconGiftResponse: Codable { let gift: IconGift? }

/// A synchronized haptic duet: both phones play `events` at server time
/// `startAtMs` (converted to local time via ClockSync).
struct DuetSession: Codable, Hashable {
    let id: String
    let name: String?
    let events: [HapticEventSpec]
    let startedBy: String
    let startAtMs: Double
    let serverNowMs: Double
}

struct DuetResponse: Codable { let duet: DuetSession }

enum DateNightPhase: String, Codable, CaseIterable {
    case anticipation, live, afterglow

    var emoji: String {
        switch self {
        case .anticipation: return "✨"
        case .live: return "💞"
        case .afterglow: return "🌙"
        }
    }

    var next: DateNightPhase? {
        switch self {
        case .anticipation: return .live
        case .live: return .afterglow
        case .afterglow: return nil
        }
    }
}

/// The couple's planned date night (drives the Live Activity on both phones).
struct DateNight: Codable, Hashable {
    let id: String
    let title: String?
    let emoji: String?
    let startsAt: Date
    let phase: DateNightPhase
    let createdBy: String
    let createdAt: Date
    let phaseChangedAt: Date
}

struct DateNightResponse: Codable { let dateNight: DateNight? }

// WS payloads

struct LevelUpPayload: Codable {
    let level: Int
    let title: LocalizedText
    let xp: Int
}

struct BadgeUnlockedPayload: Codable { let badge: BadgeState }
struct QuestCompletedPayload: Codable { let quest: QuestState }
struct IconGiftPayload: Codable { let gift: IconGift }
struct DuetStartPayload: Codable { let duet: DuetSession }
struct DateNightUpdatePayload: Codable { let dateNight: DateNight? }

struct HeartbeatTapPayload: Codable {
    let memberId: String
    let intensity: Double
}

/// `pong` payload — `echo` correlates the answer with our ping (ClockSync).
struct PongPayload: Codable { let echo: String? }
