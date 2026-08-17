import Foundation

// Foundation-only Live Activity styling shared by app + widget extension.
// The config travels INSIDE the ContentState, so changing it in the app's
// Live-Activity sheet restyles running activities immediately (no restart).

/// User-configurable style + content for both Live Activities
/// (countdown & couple pulse). Persisted in the app group.
struct LiveActivityConfig: Codable, Hashable {
    /// Widget theme id (see `WidgetThemes`) driving accent + background tint.
    var themeId: String
    /// Show the partner's online/offline presence.
    var showPresence: Bool
    /// Show the partner's current mood emoji + note.
    var showMood: Bool
    /// Show the last received touch (emoji + relative time).
    var showTouch: Bool
    /// Show the daily-question streak flame.
    var showStreak: Bool
    /// Countdown: auto-filling progress bar towards the moment.
    var showProgress: Bool
    /// Pulse: show the days-together counter.
    var showDaysTogether: Bool
    /// Live ticking countdown (Text(timerInterval:)) vs. static day count.
    var liveTimer: Bool

    init(themeId: String = "night", showPresence: Bool = true, showMood: Bool = true,
         showTouch: Bool = true, showStreak: Bool = true, showProgress: Bool = true,
         showDaysTogether: Bool = true, liveTimer: Bool = true) {
        self.themeId = themeId
        self.showPresence = showPresence
        self.showMood = showMood
        self.showTouch = showTouch
        self.showStreak = showStreak
        self.showProgress = showProgress
        self.showDaysTogether = showDaysTogether
        self.liveTimer = liveTimer
    }
}

extension SharedStore {
    static let liveActivityConfigKey = "sooodreamy.liveActivityConfig.v1"

    static func writeLiveActivityConfig(_ config: LiveActivityConfig) {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: liveActivityConfigKey)
        }
    }

    static func readLiveActivityConfig() -> LiveActivityConfig {
        guard let data = defaults.data(forKey: liveActivityConfigKey),
              let config = try? JSONDecoder().decode(LiveActivityConfig.self, from: data) else {
            return LiveActivityConfig()
        }
        return config
    }
}
