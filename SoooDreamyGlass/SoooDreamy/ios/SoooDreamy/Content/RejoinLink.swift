import Foundation

// „Große Polish-Runde" — "one scan and you're back".
//
// A rejoin link carries everything the app needs to re-attach a member slot
// in ONE step: the couple server's address plus one of the three proofs the
// existing POST /api/couples/rejoin route accepts. The SAME string is used
// as the payload of every rejoin QR code (admin web panel, partner's phone),
// so the iOS camera app, a scanned QR inside SoooDreamy and a tapped link
// all land in the same parser. Canonical format (see docs/REJOIN-QR.md):
//
//   sooodreamy://rejoin?server=<http(s)-URL>&code=<pairing code>&replaceCode=<code>
//   sooodreamy://rejoin?server=<http(s)-URL>&code=<pairing code>&recoveryKey=<rec_…>
//   sooodreamy://rejoin?server=<http(s)-URL>&token=<old bearer>
//
// Foundation-only so `swift test` exercises it on Linux.

/// Normalizes a user-entered / scanned server address. Shared by the server
/// profiles (Settings) and the rejoin deep links. Plain `http://` is a fully
/// supported first-class citizen — the private couple server speaks HTTP
/// only and ATS is configured accordingly (docs/ATS-HTTP.md).
enum ServerAddress {
    /// "192.168.1.20:4321" → "http://192.168.1.20:4321";
    /// trailing slashes dropped; nil when no usable host remains.
    static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "http://" + s
        }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), let host = url.host, !host.isEmpty,
              url.scheme == "http" || url.scheme == "https" else { return nil }
        return s
    }
}

/// Parsed `sooodreamy://rejoin` deep link / QR payload.
struct RejoinLink: Equatable {
    /// Normalized http(s) base URL of the couple server (optional — a QR
    /// from the partner's phone always has it; hand-built links may not).
    var server: String?
    /// The couple's pairing code (uppercased).
    var code: String?
    /// Per-member recovery key ("rec_…" or a custom secret).
    var recoveryKey: String?
    /// Partner-approved replace code (standard 8-char or custom, ≤ 32).
    var replaceCode: String?
    /// Previous session bearer — the proof the admin panel QR carries.
    var token: String?

    static let scheme = "sooodreamy"
    static let host = "rejoin"

    /// The server route accepts exactly one proof; mirror its check order
    /// (recoveryKey → token → replaceCode) so client and server always
    /// agree on which proof a mixed link uses.
    enum Proof: Equatable {
        case recoveryKey(code: String, recoveryKey: String)
        case token(String)
        case replaceCode(code: String, replaceCode: String)
    }

    /// First complete proof, or nil when the link can only prefill fields.
    var proof: Proof? {
        if let code, let recoveryKey { return .recoveryKey(code: code, recoveryKey: recoveryKey) }
        if let token { return .token(token) }
        if let code, let replaceCode { return .replaceCode(code: code, replaceCode: replaceCode) }
        return nil
    }

    var isEmpty: Bool {
        server == nil && code == nil && recoveryKey == nil && replaceCode == nil && token == nil
    }

    // MARK: Parsing

    /// Parses a deep link or QR payload. Returns nil for foreign schemes /
    /// hosts or links without a single usable parameter. Parameter names are
    /// case-insensitive and common aliases are accepted, so the admin panel
    /// has wiggle room without breaking older app builds.
    static func parse(_ text: String) -> RejoinLink? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == scheme,
              components.host?.lowercased() == host else { return nil }
        var link = RejoinLink()
        for item in components.queryItems ?? [] {
            guard let raw = item.value else { continue }
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            switch item.name.lowercased() {
            case "server", "url", "serverurl":
                link.server = ServerAddress.normalize(value)
            case "code", "couplecode", "couple":
                // The server uppercases before comparing — do the same.
                link.code = value.uppercased()
            case "recoverykey", "recovery", "key":
                link.recoveryKey = value
            case "replacecode", "replace":
                // Digest matching is done on trim().toUpperCase() — keep
                // inner characters (custom codes!) intact.
                link.replaceCode = value.uppercased()
            case "token":
                link.token = value
            default:
                break
            }
        }
        guard !link.isEmpty else { return nil }
        return link
    }

    // MARK: Encoding (partner-help QR, tests)

    /// Canonical URL — also the QR payload. Only non-nil parts are emitted,
    /// in a stable order so encodes are deterministic.
    var url: URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        var items: [URLQueryItem] = []
        if let server { items.append(URLQueryItem(name: "server", value: server)) }
        if let code { items.append(URLQueryItem(name: "code", value: code)) }
        if let recoveryKey { items.append(URLQueryItem(name: "recoveryKey", value: recoveryKey)) }
        if let replaceCode { items.append(URLQueryItem(name: "replaceCode", value: replaceCode)) }
        if let token { items.append(URLQueryItem(name: "token", value: token)) }
        guard !items.isEmpty else { return nil }
        components.queryItems = items
        return components.url
    }

    /// The QR payload shown in Settings → „Sicherheitsnetz" so the OTHER
    /// device gets back in with one scan (uses the replace-code route).
    static func partnerHelp(server: String, code: String, replaceCode: String) -> RejoinLink {
        RejoinLink(server: ServerAddress.normalize(server) ?? server,
                   code: code.uppercased(),
                   recoveryKey: nil,
                   replaceCode: replaceCode.uppercased(),
                   token: nil)
    }
}
