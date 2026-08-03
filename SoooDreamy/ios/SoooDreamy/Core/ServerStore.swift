import Foundation
import Observation

/// A saved server, incl. the pairing session on that server.
/// Sessions are per-server: switching servers switches the whole context.
struct ServerProfile: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var urlString: String
    var token: String?
    var coupleId: String?
    var memberId: String?
    var addedAt: Date

    init(id: UUID = UUID(), name: String, urlString: String) {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.addedAt = Date()
    }

    var baseURL: URL? { URL(string: urlString) }
    var isPaired: Bool { token != nil }

    /// Normalizes user input like "192.168.1.20:4321" → "http://192.168.1.20:4321".
    static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "http://" + s
        }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), let host = url.host, !host.isEmpty else { return nil }
        return s
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

    /// Stores the auth session on the profile after create/join.
    func attachSession(profileID: UUID, token: String, coupleId: String, memberId: String) {
        guard let idx = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[idx].token = token
        profiles[idx].coupleId = coupleId
        profiles[idx].memberId = memberId
        persist()
    }

    /// Clears the session (e.g. token invalid or user left the couple).
    func clearSession(profileID: UUID) {
        guard let idx = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[idx].token = nil
        profiles[idx].coupleId = nil
        profiles[idx].memberId = nil
        persist()
    }

    // MARK: Static access (App Intents run outside SwiftUI)

    /// Reads the active profile straight from UserDefaults without needing
    /// the main-actor store (used by App Intents / background helpers).
    nonisolated static func loadActiveProfileStatic() -> ServerProfile? {
        let d = UserDefaults.standard
        guard let data = d.data(forKey: storageKey),
              let profiles = try? JSONDecoder().decode([ServerProfile].self, from: data) else { return nil }
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
        }
        if let raw = d.string(forKey: Self.activeKey), let id = UUID(uuidString: raw),
           profiles.contains(where: { $0.id == id }) {
            activeProfileID = id
        } else {
            activeProfileID = profiles.first?.id
        }
    }

    private func persist() {
        let d = UserDefaults.standard
        if let data = try? JSONEncoder().encode(profiles) {
            d.set(data, forKey: Self.storageKey)
        }
        d.set(activeProfileID?.uuidString, forKey: Self.activeKey)
    }
}
