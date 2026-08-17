import Foundation
import Observation

/// A saved server, incl. the pairing session on that server.
/// Sessions are per-server: switching servers switches the whole context.
struct ServerProfile: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var urlString: String
    var token: String?
    var sessionId: String?
    var tokenExpiresAt: Date?
    var coupleId: String?
    var memberId: String?
    /// v10: the couple's 6-char pairing code — remembered so a rejoin after
    /// session loss can be one tap (code + keychain recovery key). Not a
    /// secret by itself: joining also requires a free slot or a valid proof.
    var coupleCode: String?
    var addedAt: Date

    init(id: UUID = UUID(), name: String, urlString: String) {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.addedAt = Date()
    }

    var baseURL: URL? { URL(string: urlString) }
    var isPaired: Bool { token != nil }

    private enum CodingKeys: String, CodingKey {
        case id, name, urlString, token, coupleId, memberId, coupleCode, sessionId, tokenExpiresAt, addedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        urlString = try c.decode(String.self, forKey: .urlString)
        // v1-v3 migration only: v4 never writes tokens to defaults/exports.
        token = try c.decodeIfPresent(String.self, forKey: .token)
        coupleId = try c.decodeIfPresent(String.self, forKey: .coupleId)
        memberId = try c.decodeIfPresent(String.self, forKey: .memberId)
        coupleCode = try c.decodeIfPresent(String.self, forKey: .coupleCode)
        // Pre-multi-device migration only: sessionId now lives in the
        // Keychain next to the token (same lifetime as the session).
        sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)
        tokenExpiresAt = try c.decodeIfPresent(Date.self, forKey: .tokenExpiresAt)
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(urlString, forKey: .urlString)
        try c.encodeIfPresent(coupleId, forKey: .coupleId)
        try c.encodeIfPresent(memberId, forKey: .memberId)
        try c.encodeIfPresent(coupleCode, forKey: .coupleCode)
        try c.encodeIfPresent(tokenExpiresAt, forKey: .tokenExpiresAt)
        try c.encode(addedAt, forKey: .addedAt)
    }

    /// Normalizes a user-entered server address (e.g. "192.168.1.20:4321",
    /// "http://138.201.60.230:4321", "https://dreamy.example.com").
    /// Both http:// and https:// are fully supported without forced TLS.
    /// Shared with the rejoin deep links via `ServerAddress` (Linux-tested).
    static func normalize(_ raw: String) -> String? {
        ServerAddress.normalize(raw)
    }

    static func isPrivateHost(_ host: String) -> Bool {
        let h = host.lowercased()
        if h == "localhost" || h.hasSuffix(".local") || h == "::1" { return true }
        let parts = h.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4 {
            if parts[0] == 10 || parts[0] == 127 || (parts[0] == 192 && parts[1] == 168)
                || (parts[0] == 169 && parts[1] == 254) { return true }
            if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
            if parts[0] == 100 && (64...127).contains(parts[1]) { return true }
        }
        return h.hasPrefix("fc") || h.hasPrefix("fd") || h.hasPrefix("fe8")
            || h.hasPrefix("fe9") || h.hasPrefix("fea") || h.hasPrefix("feb")
    }

    mutating func enforceSecureTransport() {
        // Plain HTTP is explicitly supported for self-hosted / home servers.
        // We do not rewrite http:// to https:// so saved profiles stay intact.
    }
}

/// Manages the list of servers and which one is active.
@MainActor
@Observable
final class ServerStore {
    private(set) var profiles: [ServerProfile] = []
    private(set) var activeProfileID: UUID?

    private nonisolated static let storageKey = "sooodreamy.servers.v1"
    private nonisolated static let activeKey = "sooodreamy.activeServer.v1"

    init() {
        load()
    }

    var activeProfile: ServerProfile? {
        guard let activeProfileID else { return nil }
        return profiles.first { $0.id == activeProfileID }
    }

    // MARK: Mutations

    @discardableResult
    func add(name: String, urlString: String) -> ServerProfile? {
        guard let normalized = ServerProfile.normalize(urlString) else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let profile = ServerProfile(name: trimmedName.isEmpty ? normalized : trimmedName,
                                    urlString: normalized)
        profiles.append(profile)
        if activeProfileID == nil { activeProfileID = profile.id }
        persist()
        return profile
    }

    func update(_ profile: ServerProfile) {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[idx] = profile
        persist()
    }

    func remove(id: UUID) {
        SharedKeychain.removeToken(profileID: id)
        SharedKeychain.removeSessionId(profileID: id)
        // Deleting the profile is the ONLY place the recovery key dies —
        // "leave device" keeps it so a later rejoin stays one tap.
        SharedKeychain.removeRecoveryKey(profileID: id)
        // Tearing a server down aborts any invite-driven setup with it —
        // a parked code must not outlive the flow that parked it.
        PendingInvite.clear()
        CoreColdCacheStore.shared.remove(profileID: id)
        profiles.removeAll { $0.id == id }
        if activeProfileID == id {
            activeProfileID = profiles.first?.id
        }
        persist()
    }

    func setActive(id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileID = id
        persist()
    }

    /// Stores the auth session on the profile after create/join/device-link.
    func attachSession(profileID: UUID, token: String, coupleId: String, memberId: String,
                       sessionId: String?, expiresAt: Date?) {
        guard let idx = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[idx].token = token
        profiles[idx].sessionId = sessionId
        profiles[idx].tokenExpiresAt = expiresAt
        profiles[idx].coupleId = coupleId
        profiles[idx].memberId = memberId
        _ = SharedKeychain.setToken(token, profileID: profileID)
        _ = SharedKeychain.setSessionId(sessionId, profileID: profileID)
        persist()
    }

    /// iCloud restore: replace the whole server list at once.
    /// Existing profiles with the same id are overwritten; `activeId` wins
    /// when it exists in the restored list.
    func replaceAll(profiles newProfiles: [ServerProfile], activeId: UUID?) {
        profiles = newProfiles.map { profile in
            var hydrated = profile
            hydrated.token = SharedKeychain.token(profileID: profile.id)
            hydrated.sessionId = SharedKeychain.sessionId(profileID: profile.id)
            return hydrated
        }
        if let activeId, newProfiles.contains(where: { $0.id == activeId }) {
            activeProfileID = activeId
        } else {
            activeProfileID = newProfiles.first?.id
        }
        persist()
    }

    /// v10: remembers the couple's pairing code for the rejoin flow.
    func rememberCoupleCode(profileID: UUID, code: String?) {
        guard let idx = profiles.firstIndex(where: { $0.id == profileID }),
              profiles[idx].coupleCode != code else { return }
        profiles[idx].coupleCode = code
        persist()
    }

    /// Clears the session (e.g. token invalid or user left the couple).
    /// `coupleCode` and the keychain recovery key survive on purpose — they
    /// are exactly what makes the rejoin flow effortless afterwards.
    func clearSession(profileID: UUID) {
        guard let idx = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[idx].token = nil
        profiles[idx].sessionId = nil
        profiles[idx].tokenExpiresAt = nil
        profiles[idx].coupleId = nil
        profiles[idx].memberId = nil
        SharedKeychain.removeToken(profileID: profileID)
        SharedKeychain.removeSessionId(profileID: profileID)
        persist()
    }

    // MARK: Static access (App Intents run outside SwiftUI)

    /// Reads the active profile straight from UserDefaults without needing
    /// the main-actor store (used by App Intents / background helpers).
    nonisolated static func loadActiveProfileStatic() -> ServerProfile? {
        let d = UserDefaults.standard
        guard let data = d.data(forKey: storageKey),
              var profiles = try? JSONDecoder().decode([ServerProfile].self, from: data) else { return nil }
        for index in profiles.indices {
            profiles[index].enforceSecureTransport()
            profiles[index].token = SharedKeychain.token(profileID: profiles[index].id)
            profiles[index].sessionId = SharedKeychain.sessionId(profileID: profiles[index].id)
        }
        if let raw = d.string(forKey: activeKey), let id = UUID(uuidString: raw),
           let profile = profiles.first(where: { $0.id == id }) {
            return profile
        }
        return profiles.first
    }

    // MARK: Persistence

    private func load() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([ServerProfile].self, from: data) {
            profiles = decoded
            for index in profiles.indices {
                profiles[index].enforceSecureTransport()
                if let legacy = profiles[index].token {
                    _ = SharedKeychain.setToken(legacy, profileID: profiles[index].id)
                } else {
                    profiles[index].token = SharedKeychain.token(profileID: profiles[index].id)
                }
                if let legacySession = profiles[index].sessionId {
                    _ = SharedKeychain.setSessionId(legacySession, profileID: profiles[index].id)
                } else {
                    profiles[index].sessionId = SharedKeychain.sessionId(profileID: profiles[index].id)
                }
            }
        }
        if let raw = d.string(forKey: Self.activeKey), let id = UUID(uuidString: raw),
           profiles.contains(where: { $0.id == id }) {
            activeProfileID = id
        } else {
            activeProfileID = profiles.first?.id
        }
        persist() // strips any legacy token from defaults and saves HTTPS migration
    }

    private func persist() {
        let d = UserDefaults.standard
        if let data = try? JSONEncoder().encode(profiles) {
            d.set(data, forKey: Self.storageKey)
        }
        d.set(activeProfileID?.uuidString, forKey: Self.activeKey)
        mirrorCredentials()
    }

    /// Mirrors the active session into the app group so the widget extension
    /// (interactive send-love buttons, photo source override) and the
    /// background refresh task can reach the couple server on their own.
    private func mirrorCredentials() {
        if let profile = activeProfile, profile.token != nil {
            SharedStore.writeServerCredentials(
                SharedServerCredentials(baseURLString: profile.urlString, profileID: profile.id))
        } else {
            SharedStore.writeServerCredentials(nil)
        }
    }
}
