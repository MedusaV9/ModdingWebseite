import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case http(status: Int, code: String?, message: String?)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return L10n.t("error.invalidURL")
        case .http(let status, let code, let message):
            return message ?? code ?? "HTTP \(status)"
        case .decoding:
            return L10n.t("error.decoding")
        case .transport(let err):
            return err.localizedDescription
        }
    }

    var isUnauthorized: Bool {
        if case .http(let status, _, _) = self { return status == 401 }
        return false
    }
}

/// Stateless HTTP client for one server + token pair.
struct API {
    let baseURL: URL
    let token: String?

    // ISO8601DateFormatter is documented thread-safe; the unsafe marker only
    // silences the Swift 6 Sendable-capture warning.
    nonisolated(unsafe) private static let isoFracFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = API.isoFracFormatter.date(from: s) ?? API.isoFormatter.date(from: s) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad date: \(s)")
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 120
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    private struct ErrorBody: Decodable { let error: String?; let message: String? }
    private struct Empty: Decodable {}

    // MARK: Request core

    private func request<T: Decodable>(_ method: String, _ path: String,
                                       query: [String: String] = [:],
                                       jsonBody: [String: Any?]? = nil,
                                       rawBody: Data? = nil,
                                       contentType: String? = nil,
                                       headers: [String: String] = [:],
                                       as type: T.Type) async throws -> T {
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        comps.path = (comps.path.hasSuffix("/") ? String(comps.path.dropLast()) : comps.path) + path
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps.url else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if let jsonBody {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let clean = jsonBody.compactMapValues { $0 }
            req.httpBody = try JSONSerialization.data(withJSONObject: clean)
        } else if let rawBody {
            req.setValue(contentType ?? "application/octet-stream", forHTTPHeaderField: "Content-Type")
            req.httpBody = rawBody
        }

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await API.session.data(for: req)
        } catch {
            throw APIError.transport(error)
        }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = try? API.decoder.decode(ErrorBody.self, from: data)
            throw APIError.http(status: status, code: body?.error, message: body?.message)
        }
        if T.self == Data.self, let data = data as? T { return data }
        do {
            return try API.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    // MARK: Health & pairing (no token needed)

    func health() async throws -> HealthResponse {
        try await request("GET", "/api/health", as: HealthResponse.self)
    }

    func createCouple(name: String, avatar: String, color: String) async throws -> AuthResponse {
        try await request("POST", "/api/couples",
                          jsonBody: ["name": name, "avatar": avatar, "color": color],
                          as: AuthResponse.self)
    }

    func joinCouple(code: String, name: String, avatar: String, color: String) async throws -> AuthResponse {
        try await request("POST", "/api/couples/join",
                          jsonBody: ["code": code, "name": name, "avatar": avatar, "color": color],
                          as: AuthResponse.self)
    }

    // MARK: Couple & profile

    func getCouple() async throws -> CoupleResponse {
        try await request("GET", "/api/couple", as: CoupleResponse.self)
    }

    func updateMe(name: String? = nil, avatar: String? = nil, color: String? = nil,
                  mood: String?? = nil, moodNote: String?? = nil) async throws -> Member {
        var body: [String: Any?] = [:]
        if let name { body["name"] = name }
        if let avatar { body["avatar"] = avatar }
        if let color { body["color"] = color }
        if case .some(let m) = mood { body["mood"] = m ?? NSNull() }
        if case .some(let n) = moodNote { body["moodNote"] = n ?? NSNull() }
        return try await request("PATCH", "/api/me", jsonBody: body, as: MemberResponse.self).member
    }

    func updateCouple(name: String? = nil, anniversary: String? = nil) async throws -> Couple {
        var body: [String: Any?] = [:]
        if let name { body["name"] = name }
        if let anniversary { body["anniversary"] = anniversary }
        return try await request("PATCH", "/api/couple", jsonBody: body, as: CoupleOnlyResponse.self).couple
    }

    func dissolveCouple() async throws {
        struct OK: Decodable { let ok: Bool }
        _ = try await request("DELETE", "/api/couple", as: OK.self)
    }

    // MARK: Touches

    @discardableResult
    func sendTouch(_ kind: TouchKind) async throws -> Touch {
        try await request("POST", "/api/touches", jsonBody: ["type": kind.rawValue], as: TouchResponse.self).touch
    }

    func recentTouches(limit: Int = 30) async throws -> [Touch] {
        try await request("GET", "/api/touches/recent", query: ["limit": String(limit)], as: TouchesResponse.self).touches
    }

    // MARK: Messages & voice

    func messages(limit: Int = 50, before: String? = nil) async throws -> [Message] {
        var q = ["limit": String(limit)]
        if let before { q["before"] = before }
        return try await request("GET", "/api/messages", query: q, as: MessagesResponse.self).messages
    }

    @discardableResult
    func sendMessage(type: MessageKind, text: String, title: String? = nil,
                     openWhen: String? = nil) async throws -> Message {
        try await request("POST", "/api/messages",
                          jsonBody: ["type": type.rawValue, "text": text, "title": title,
                                     "openWhen": openWhen],
                          as: MessageResponse.self).message
    }

    @discardableResult
    func sendVoice(data: Data, durationSec: Double) async throws -> Message {
        try await request("POST", "/api/voice", rawBody: data, contentType: "audio/mp4",
                          headers: ["X-Duration-Sec": String(format: "%.2f", durationSec)],
                          as: MessageResponse.self).message
    }

    /// Toggle my emoji reaction on a message.
    @discardableResult
    func toggleReaction(messageId: String, emoji: String) async throws -> Message {
        try await request("POST", "/api/messages/\(messageId)/reactions",
                          jsonBody: ["emoji": emoji], as: MessageResponse.self).message
    }

    // MARK: Wordle duel

    @discardableResult
    func submitWordle(dateKey: String, rows: Int, win: Bool, grid: String, lang: String) async throws -> WordleDayResponse {
        try await request("POST", "/api/wordle/\(dateKey)",
                          jsonBody: ["rows": rows, "win": win, "grid": grid, "lang": lang],
                          as: WordleDayResponse.self)
    }

    func wordleDay(dateKey: String, lang: String) async throws -> WordleDayResponse {
        try await request("GET", "/api/wordle/\(dateKey)", query: ["lang": lang],
                          as: WordleDayResponse.self)
    }

    // MARK: Photos

    func photos() async throws -> [Photo] {
        try await request("GET", "/api/photos", as: PhotosResponse.self).photos
    }

    @discardableResult
    func uploadPhoto(jpeg: Data, caption: String?, width: Int?, height: Int?) async throws -> Photo {
        var headers: [String: String] = [:]
        if let caption, !caption.isEmpty {
            headers["X-Caption"] = caption.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        }
        if let width { headers["X-Width"] = String(width) }
        if let height { headers["X-Height"] = String(height) }
        return try await request("POST", "/api/photos", rawBody: jpeg, contentType: "image/jpeg",
                                 headers: headers, as: PhotoResponse.self).photo
    }

    func deletePhoto(id: String) async throws {
        struct OK: Decodable { let ok: Bool }
        _ = try await request("DELETE", "/api/photos/\(id)", as: OK.self)
    }

    /// Attach a small grid thumbnail to an uploaded photo (uploader only).
    @discardableResult
    func uploadPhotoThumb(photoId: String, jpeg: Data) async throws -> Photo {
        try await request("POST", "/api/photos/\(photoId)/thumb", rawBody: jpeg,
                          contentType: "image/jpeg", as: PhotoResponse.self).photo
    }

    /// Toggle whether the photo is one of MY favorites.
    @discardableResult
    func togglePhotoFavorite(id: String) async throws -> Photo {
        try await request("POST", "/api/photos/\(id)/favorite", jsonBody: [:],
                          as: PhotoResponse.self).photo
    }

    // MARK: Love coupons

    func coupons() async throws -> [Coupon] {
        try await request("GET", "/api/coupons", as: CouponsResponse.self).coupons
    }

    /// Creates a coupon FOR the partner (server resolves the receiver).
    @discardableResult
    func createCoupon(title: String, emoji: String, note: String?) async throws -> Coupon {
        try await request("POST", "/api/coupons",
                          jsonBody: ["title": title, "emoji": emoji, "note": note],
                          as: CouponResponse.self).coupon
    }

    /// Redeem a coupon that was made for me.
    @discardableResult
    func redeemCoupon(id: String) async throws -> Coupon {
        try await request("POST", "/api/coupons/\(id)/redeem", jsonBody: [:],
                          as: CouponResponse.self).coupon
    }

    /// Delete an unredeemed coupon I created.
    func deleteCoupon(id: String) async throws {
        struct OK: Decodable { let ok: Bool }
        _ = try await request("DELETE", "/api/coupons/\(id)", as: OK.self)
    }

    /// Absolute media URL with `?token=` for AsyncImage / AVPlayer.
    func mediaURL(_ path: String) -> URL? {
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return nil }
        comps.path = path
        if let token { comps.queryItems = [URLQueryItem(name: "token", value: token)] }
        return comps.url
    }

    // MARK: Events

    func events() async throws -> [EventItem] {
        try await request("GET", "/api/events", as: EventsResponse.self).events
    }

    @discardableResult
    func addEvent(title: String, emoji: String, date: String, repeatsYearly: Bool) async throws -> EventItem {
        try await request("POST", "/api/events",
                          jsonBody: ["title": title, "emoji": emoji, "date": date, "repeatsYearly": repeatsYearly],
                          as: EventResponse.self).event
    }

    @discardableResult
    func updateEvent(id: String, title: String? = nil, emoji: String? = nil,
                     date: String? = nil, repeatsYearly: Bool? = nil) async throws -> EventItem {
        var body: [String: Any?] = [:]
        if let title { body["title"] = title }
        if let emoji { body["emoji"] = emoji }
        if let date { body["date"] = date }
        if let repeatsYearly { body["repeatsYearly"] = repeatsYearly }
        return try await request("PATCH", "/api/events/\(id)", jsonBody: body, as: EventResponse.self).event
    }

    func deleteEvent(id: String) async throws {
        struct OK: Decodable { let ok: Bool }
        _ = try await request("DELETE", "/api/events/\(id)", as: OK.self)
    }

    // MARK: Bucket list

    func bucket() async throws -> [BucketItem] {
        try await request("GET", "/api/bucket", as: BucketResponse.self).items
    }

    @discardableResult
    func addBucketItem(text: String, emoji: String?) async throws -> BucketItem {
        try await request("POST", "/api/bucket", jsonBody: ["text": text, "emoji": emoji],
                          as: BucketItemResponse.self).item
    }

    @discardableResult
    func updateBucketItem(id: String, text: String? = nil, emoji: String? = nil, done: Bool? = nil) async throws -> BucketItem {
        var body: [String: Any?] = [:]
        if let text { body["text"] = text }
        if let emoji { body["emoji"] = emoji }
        if let done { body["done"] = done }
        return try await request("PATCH", "/api/bucket/\(id)", jsonBody: body, as: BucketItemResponse.self).item
    }

    func deleteBucketItem(id: String) async throws {
        struct OK: Decodable { let ok: Bool }
        _ = try await request("DELETE", "/api/bucket/\(id)", as: OK.self)
    }

    // MARK: Daily question

    func daily(dateKey: String) async throws -> DailyEntry {
        try await request("GET", "/api/daily/\(dateKey)", as: DailyEntry.self)
    }

    @discardableResult
    func answerDaily(dateKey: String, questionId: Int, text: String) async throws -> DailyEntry {
        try await request("POST", "/api/daily/\(dateKey)",
                          jsonBody: ["questionId": questionId, "text": text], as: DailyEntry.self)
    }

    // MARK: Canvas

    func canvasStrokes() async throws -> [CanvasStroke] {
        try await request("GET", "/api/canvas", as: StrokesResponse.self).strokes
    }

    @discardableResult
    func addStroke(color: String, width: Double, tool: String, points: [[Double]]) async throws -> CanvasStroke {
        try await request("POST", "/api/canvas/strokes",
                          jsonBody: ["color": color, "width": width, "tool": tool, "points": points],
                          as: StrokeResponse.self).stroke
    }

    func clearCanvas() async throws {
        struct OK: Decodable { let ok: Bool }
        _ = try await request("DELETE", "/api/canvas", as: OK.self)
    }

    /// Remove one of MY strokes (undo). 403 for the partner's strokes.
    func deleteStroke(id: String) async throws {
        struct OK: Decodable { let ok: Bool }
        _ = try await request("DELETE", "/api/canvas/strokes/\(id)", as: OK.self)
    }

    // MARK: Mood history & daily journal

    func moods(limit: Int = 80) async throws -> [MoodEntry] {
        try await request("GET", "/api/moods", query: ["limit": String(limit)],
                          as: MoodsResponse.self).moods
    }

    /// Past daily-question entries (my view), newest dateKey first.
    func dailyHistory(limit: Int = 60) async throws -> [DailyEntry] {
        try await request("GET", "/api/daily", query: ["limit": String(limit)],
                          as: DailyListResponse.self).entries
    }

    // MARK: Games

    @discardableResult
    func createGame(type: GameKind, payload: JSONValue? = nil) async throws -> GameSession {
        var body: [String: Any?] = ["type": type.rawValue]
        if let payload {
            let data = try API.encoder.encode(payload)
            body["payload"] = try JSONSerialization.jsonObject(with: data)
        }
        return try await request("POST", "/api/games", jsonBody: body, as: GameOnlyResponse.self).game
    }

    @discardableResult
    func joinGame(id: String) async throws -> GameSession {
        try await request("POST", "/api/games/\(id)/join", jsonBody: [:], as: GameOnlyResponse.self).game
    }

    @discardableResult
    func sendMove(gameId: String, data: JSONValue) async throws -> GameMove {
        let encoded = try API.encoder.encode(data)
        let obj = try JSONSerialization.jsonObject(with: encoded)
        return try await request("POST", "/api/games/\(gameId)/move", jsonBody: ["data": obj],
                                 as: MoveResponse.self).move
    }

    @discardableResult
    func endGame(id: String, result: JSONValue? = nil) async throws -> GameSession {
        var body: [String: Any?] = [:]
        if let result {
            let data = try API.encoder.encode(result)
            body["result"] = try JSONSerialization.jsonObject(with: data)
        }
        return try await request("POST", "/api/games/\(id)/end", jsonBody: body, as: GameOnlyResponse.self).game
    }

    func activeGame() async throws -> GameSession? {
        try await request("GET", "/api/games/active", as: GameResponse.self).game
    }

    // MARK: Stats

    func stats() async throws -> Stats {
        try await request("GET", "/api/stats", as: Stats.self)
    }
}
