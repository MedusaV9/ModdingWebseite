import Foundation

// „Eingabe-Lease im Client" — pure decision rules for the per-(game, member)
// input lease of Welle 6 (docs/API.md „Input lease & spectator devices").
// The SERVER enforces the lease (only one device per member may submit
// moves); these rules only decide what THIS device renders: driver seat
// (full controls), spectator seat (read-only banner + explicit takeover) or
// an open table (nobody moved yet). Foundation-only so Linux `swift test`
// covers every decision.

/// One member's lease as serialized in `game.leases[memberId]`, in
/// `game_lease` frames and in the `game_lease_held` error details: which
/// device drives, since when. `sessionSuffix` follows the origin-marker
/// convention (last 8 characters of the holding session id — recognizable
/// only by the member's own devices, useless for anything else).
/// `acquiredAt` stays the raw ISO string: the UI never computes with it.
struct GameLease: Codable, Hashable {
    let deviceId: String?
    let deviceName: String?
    let sessionSuffix: String?
    let acquiredAt: String?
}

enum GameLeaseRules {
    /// Server refusal code when a move bounces off a live foreign lease
    /// (docs/API.md error catalog).
    static let refusalCode = "game_lease_held"

    /// How THIS device relates to its member's lease in one game.
    enum Seat: Equatable {
        /// No lease yet — the first valid move will claim it silently.
        case open
        /// This very session holds the lease: full controls.
        case driver
        /// Another of MY devices holds it: read-only + takeover offer.
        case spectator(deviceName: String?)
    }

    /// Decides the seat from the member's lease view plus the own session
    /// id. Unknown identity NEVER locks the UI (fail open): old servers
    /// send no leases, fresh installs may not know their session yet — the
    /// server still refuses foreign moves either way, so failing open can
    /// at worst show controls that bounce, never hide controls wrongly.
    static func seat(lease: GameLease?, ownSessionId: String?) -> Seat {
        guard let suffix = lease?.sessionSuffix, !suffix.isEmpty else { return .open }
        guard let own = MultiDeviceRules.sessionSuffix(of: ownSessionId) else { return .open }
        return suffix == own ? .driver : .spectator(deviceName: lease?.deviceName)
    }

    /// True when the read-only banner (with its takeover button) shows.
    /// Only ACTIVE games have a table worth guarding — lobbies and ended
    /// games render their own states.
    static func showsSpectatorBanner(state: String?, lease: GameLease?,
                                     ownSessionId: String?) -> Bool {
        guard state == "active" else { return false }
        if case .spectator = seat(lease: lease, ownSessionId: ownSessionId) { return true }
        return false
    }

    /// Banner device label: the holding device's name, or the localized
    /// generic fallback (key, resolved by the view via L10n).
    static let unknownDeviceKey = "games.lease.banner.unknownDevice"

    static func bannerDeviceName(_ lease: GameLease?) -> String? {
        guard let name = lease?.deviceName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
        return name
    }
}
