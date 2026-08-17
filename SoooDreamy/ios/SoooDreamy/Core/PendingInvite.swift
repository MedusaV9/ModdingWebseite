import Foundation

/// Hand-over slot for the page-1 invite scan (onboarding eval): the couple
/// code from a scanned invitation must survive the `.welcome` → `.pairing`
/// phase flip — two different screens. Parked here, consumed exactly once
/// by PairingView, which then starts in join mode with the code in place.
///
/// The slot is deliberately short-lived. It used to survive an abandoned
/// setup flow indefinitely, so a pairing attempt days later silently
/// adopted a stale code. Now `consume` honors a 15-minute shelf life, and
/// the divergent-intent paths (demo entry, rejoin link, completed auth,
/// profile removal) call `clear` explicitly. Foundation-only with injected
/// time/defaults so the Linux LogicTests cover every branch.
enum PendingInvite {
    static let codeKey = "sooodreamy.pendingInviteCode"
    static let storedAtKey = "sooodreamy.pendingInviteStoredAt"

    /// A parked invite is a NOW intent — whoever scans wants to pair
    /// within minutes. Anything older is an abandoned flow.
    static let shelfLife: TimeInterval = 15 * 60

    static func store(code: String, now: Date = Date(),
                      defaults: UserDefaults = .standard) {
        defaults.set(code, forKey: codeKey)
        defaults.set(now.timeIntervalSince1970, forKey: storedAtKey)
    }

    /// One-shot read: the slot empties on EVERY call; only a code younger
    /// than `shelfLife` is returned. A code without a stored-at stamp
    /// predates the expiry (exactly the stale kind this guards against)
    /// and a stamp in the future (device clock set back) is dropped too.
    static func consume(now: Date = Date(),
                        defaults: UserDefaults = .standard) -> String? {
        defer { clear(defaults: defaults) }
        guard let code = defaults.string(forKey: codeKey), !code.isEmpty else {
            return nil
        }
        let storedAt = defaults.double(forKey: storedAtKey)
        let age = now.timeIntervalSince1970 - storedAt
        guard storedAt > 0, age >= 0, age < shelfLife else { return nil }
        return code
    }

    /// Abort/replace of the setup flow: the parked code dies with the
    /// intent that parked it.
    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: codeKey)
        defaults.removeObject(forKey: storedAtKey)
    }
}
