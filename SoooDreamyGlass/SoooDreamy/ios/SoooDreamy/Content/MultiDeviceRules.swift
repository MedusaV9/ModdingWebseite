import Foundation

// „Multi-Device im Client" — pure rules for simultaneous devices per member
// (docs/API.md „Multi-device sessions & fanout"). Three concerns live here:
//
//   1. The `origin` frame marker: recognizing "this frame is my own echo"
//      and "this frame is me, but on another device". UI decisions only —
//      never security decisions (the suffix is deliberately useless for
//      anything but self-recognition).
//   2. Device link codes: the 8-char format the server mints
//      (POST /api/sessions/link-code) and the new device redeems
//      (POST /api/couples/link).
//   3. The `sooodreamy://link?server=…&code=…` deep link / QR payload a
//      signed-in device shows so a NEW device attaches with one scan.
//
// Foundation-only so `swift test` exercises everything on Linux.

/// Top-level `origin` marker on member-caused WS frames:
/// `{memberId, deviceId, sessionSuffix}`. `sessionSuffix` is the LAST 8
/// characters of the acting session id — enough for a client to recognize
/// itself (it knows its own `sessionId` from the pairing/link response).
/// System frames (`welcome`, `pong`, `presence`, scheduler pushes) carry
/// none; old servers send none — every helper treats that as "not me".
struct EventOrigin: Codable, Hashable {
    let memberId: String?
    let deviceId: String?
    let sessionSuffix: String?
}

enum MultiDeviceRules {
    /// Length of `origin.sessionSuffix` (server: `sessionId.slice(-8)`).
    static let sessionSuffixLength = 8

    /// The session cap per member (server MAX_SESSIONS_PER_MEMBER) — shown
    /// in the device manager so a full house is visible before it 413s.
    static let maxSessionsPerMember = 8

    /// The comparable suffix of an own session id; nil when unknown.
    static func sessionSuffix(of sessionId: String?) -> String? {
        guard let sessionId, !sessionId.isEmpty else { return nil }
        return String(sessionId.suffix(sessionSuffixLength))
    }

    /// True when a frame was caused by THIS very session — its own echo of
    /// an idempotent broadcast. Unknown origins or an unknown own session
    /// id never count as echoes: partner behavior must not change when the
    /// marker is missing (old server, system frame).
    static func isOwnEcho(origin: EventOrigin?, sessionId: String?) -> Bool {
        guard let suffix = origin?.sessionSuffix, !suffix.isEmpty,
              let own = sessionSuffix(of: sessionId) else { return false }
        return suffix == own
    }

    /// True when a frame was caused by MY member on a DIFFERENT device
    /// (my iPad while I hold my iPhone). Such frames are "from me, other
    /// device" — never partner events.
    static func isOwnOtherDevice(origin: EventOrigin?, memberId: String?,
                                 sessionId: String?) -> Bool {
        guard let originMember = origin?.memberId, !originMember.isEmpty,
              let memberId, originMember == memberId else { return false }
        return !isOwnEcho(origin: origin, sessionId: sessionId)
    }

    /// Central partner-effect gate: a frame may drive partner-facing
    /// celebrations (toasts, sounds, notifications) only when it was NOT
    /// caused by my member — neither this session's own echo nor my member
    /// on another device. Frames without an origin marker (old servers,
    /// system frames) pass, so partner behavior never changes when the
    /// marker is missing.
    static func allowsPartnerEffects(origin: EventOrigin?, memberId: String?,
                                     sessionId: String?) -> Bool {
        !isOwnEcho(origin: origin, sessionId: sessionId)
            && !isOwnOtherDevice(origin: origin, memberId: memberId,
                                 sessionId: sessionId)
    }

    /// L10n key for a failed link-code redemption, straight from the error
    /// catalog in docs/API.md. Nil = no special mapping (generic handling).
    static func linkErrorKey(status: Int, code: String?) -> String? {
        switch (status, code) {
        case (403, "bad_link_code"): return "devices.link.badCode"
        case (403, "link_code_expired"): return "devices.link.expired"
        case (409, "link_code_consumed"): return "devices.link.consumed"
        case (404, "unknown_couple"): return "devices.link.unknownCouple"
        case (413, _): return "devices.link.tooManySessions"
        case (429, _): return "devices.link.rateLimited"
        default: return nil
        }
    }

    /// SF Symbol for a device-session row, guessed from the device name the
    /// session was created with (`UIDevice.current.name` / model strings).
    static func deviceIcon(name: String?) -> String {
        let lower = (name ?? "").lowercased()
        if lower.contains("ipad") { return "ipad" }
        if lower.contains("mac") { return "macbook" }
        return "iphone"
    }
}

/// WebSocket close-code contract for session termination. The server closes
/// a revoked session's socket with code 4001 — that close is TERMINAL: no
/// reconnect, no silent recovery-key rejoin. Every other close (network,
/// restart, 1000/1001 shutdowns) stays a normal reconnect case.
enum SessionTerminationRules {
    /// Server SESSION_REVOKED_CLOSE_CODE.
    static let revokedCloseCode = 4001

    static func isTerminal(closeCode: Int?) -> Bool {
        closeCode == revokedCloseCode
    }
}

/// Format rules for the one-time device link codes: 8 chars from the shared
/// unambiguous alphabet (no 0/O/1/I), case-insensitive on the server.
enum DeviceLinkCode {
    /// Server-side LINK_CODE_LENGTH.
    static let length = 8

    /// Uppercases, drops everything outside the code alphabet, caps at 8 —
    /// shared with the pairing/replace-code fields via RecoveryKit.
    static func normalized(_ raw: String) -> String {
        RecoveryKit.normalizedCode(raw, length: length)
    }

    static func isComplete(_ raw: String) -> Bool {
        normalized(raw).count == length
    }
}

/// Parsed `sooodreamy://link?server=…&code=…` deep link — the QR payload of
/// the device hand-off (the server renders the same link as SVG).
struct DeviceLinkURL: Equatable {
    /// Normalized http(s) base URL of the couple server. Only http(s) is
    /// accepted; any other scheme parses as if no server were named.
    var server: String?
    /// The complete 8-char link code, normalized to the server alphabet.
    var code: String

    static let scheme = "sooodreamy"
    static let host = "link"

    /// Parses a deep link / scanned QR payload. Returns nil for foreign
    /// schemes or hosts and for links without a complete 8-char code — a
    /// device link without its code cannot do anything. Parameter names are
    /// case-insensitive; codes normalize (the server compares uppercase).
    static func parse(_ text: String) -> DeviceLinkURL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == scheme,
              components.host?.lowercased() == host else { return nil }
        var server: String?
        var code = ""
        for item in components.queryItems ?? [] {
            guard let raw = item.value else { continue }
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            switch item.name.lowercased() {
            case "server", "url", "serverurl":
                server = normalizedHTTPServer(value)
            case "code", "linkcode":
                code = DeviceLinkCode.normalized(value)
            default:
                break
            }
        }
        guard DeviceLinkCode.isComplete(code) else { return nil }
        return DeviceLinkURL(server: server, code: code)
    }

    /// Server addresses in device links must be http(s). An explicit
    /// foreign scheme (ftp://, javascript:, …) is rejected BEFORE
    /// `ServerAddress.normalize` would prefix it with http://.
    static func normalizedHTTPServer(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let separator = value.range(of: "://") {
            let scheme = value[..<separator.lowerBound].lowercased()
            guard scheme == "http" || scheme == "https" else { return nil }
        }
        return ServerAddress.normalize(value)
    }

    /// Canonical URL (also a QR payload) — mirrors the server's encoding,
    /// with only non-nil parts in a stable order.
    var url: URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        var items: [URLQueryItem] = []
        if let server { items.append(URLQueryItem(name: "server", value: server)) }
        items.append(URLQueryItem(name: "code", value: code))
        components.queryItems = items
        return components.url
    }
}
