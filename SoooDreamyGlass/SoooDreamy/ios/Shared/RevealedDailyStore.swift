import Foundation

/// Remembers which daily-question reveals were already broken open on this
/// device — the single truth behind "the ceremony fires exactly once per
/// couple, day and device" (Dossier 34, ideas 1/28).
///
/// Lives in `ios/Shared` on purpose: the seal state is written by the app
/// and READ by the widget extension (W7 seal widget), so both processes
/// share the app-group defaults.
///
/// ## Storage format (App Group `group.app.sooodreamy.shared`)
/// - Key:   `sooodreamy.revealedDaily.v1.<coupleId>`
/// - Value: `[String]` of revealed dateKeys (`"YYYY-MM-DD"`), sorted
///   ascending, capped to the newest 90 entries.
/// - Widget rule: a seal is PENDING when the snapshot says
///   `dailyBothAnswered == true` and today's dateKey is absent here.
enum RevealedDailyStore {
    static let keyPrefix = "sooodreamy.revealedDaily.v1."
    /// Enough for a quarter year of ceremony history; older days can never
    /// glow again anyway.
    static let capacity = 90

    static func storageKey(coupleId: String) -> String {
        keyPrefix + coupleId
    }

    static func revealedKeys(coupleId: String,
                             defaults: UserDefaults = SharedStore.defaults) -> Set<String> {
        Set(defaults.stringArray(forKey: storageKey(coupleId: coupleId)) ?? [])
    }

    static func isRevealed(coupleId: String?, dateKey: String,
                           defaults: UserDefaults = SharedStore.defaults) -> Bool {
        guard let coupleId else { return false }
        return revealedKeys(coupleId: coupleId, defaults: defaults).contains(dateKey)
    }

    /// True while both answered but the seal was never broken on this device
    /// — drives the gold glow on the card and the widget's glowing seal.
    static func sealPending(coupleId: String?, dateKey: String, bothAnswered: Bool,
                            defaults: UserDefaults = SharedStore.defaults) -> Bool {
        bothAnswered && !isRevealed(coupleId: coupleId, dateKey: dateKey, defaults: defaults)
    }

    /// Marks the day as revealed. Returns false when it already was — the
    /// caller uses that to guarantee the one-time ceremony semantics.
    @discardableResult
    static func markRevealed(coupleId: String?, dateKey: String,
                             defaults: UserDefaults = SharedStore.defaults) -> Bool {
        guard let coupleId else { return false }
        var keys = revealedKeys(coupleId: coupleId, defaults: defaults)
        guard !keys.contains(dateKey) else { return false }
        keys.insert(dateKey)
        // dateKeys sort chronologically as strings, so the suffix keeps the
        // newest days when the cap kicks in.
        let kept = Array(keys.sorted().suffix(capacity))
        defaults.set(kept, forKey: storageKey(coupleId: coupleId))
        return true
    }

    /// The very first reveal of a couple on this device gets the ritual
    /// explainer (Dossier 34, idea 19) — true while no day was revealed yet.
    static func isFirstReveal(coupleId: String?,
                              defaults: UserDefaults = SharedStore.defaults) -> Bool {
        guard let coupleId else { return false }
        return revealedKeys(coupleId: coupleId, defaults: defaults).isEmpty
    }
}

/// Widget-side seal truth. The snapshot flag alone would lie twice: after
/// midnight (yesterday's seal keeps glowing) and right after the in-app
/// ceremony (until the next snapshot write). Rebuilding the state from the
/// live store at render time keeps both moments honest.
extension WidgetSnapshot {
    func revealSealPending(now: Date = Date(),
                           defaults: UserDefaults = SharedStore.defaults) -> Bool {
        guard dailyRevealPending == true,
              let coupleId,
              let dateKey = dailyRevealDateKey,
              dateKey == SharedDates.todayKey(now) else { return false }
        return RevealedDailyStore.sealPending(coupleId: coupleId, dateKey: dateKey,
                                              bothAnswered: dailyBothAnswered,
                                              defaults: defaults)
    }
}
