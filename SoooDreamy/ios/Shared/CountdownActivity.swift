import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Live Activity (lock screen + Dynamic Island) counting down to a couple event.
struct CountdownActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Bumped when the user refreshes; the countdown itself is rendered
        /// with `Text(timerInterval:)`, so no periodic updates are needed.
        var refreshedAt: Date
    }

    var title: String
    var emoji: String
    var targetDate: Date
    var partnerName: String?
}
#endif
