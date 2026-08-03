import Foundation
import ActivityKit

/// Starts/stops the countdown Live Activity (lock screen + Dynamic Island).
@MainActor
enum CountdownActivityController {
    static var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    static var activeEventTitle: String? {
        Activity<CountdownActivityAttributes>.activities.first?.attributes.title
    }

    @discardableResult
    static func start(for event: EventItem, partnerName: String?) -> Bool {
        guard isSupported,
              let target = SharedDates.nextOccurrence(event.date, repeatsYearly: event.repeatsYearly),
              target > Date() else { return false }
        stopAll()
        let attributes = CountdownActivityAttributes(title: event.title,
                                                     emoji: event.emoji,
                                                     targetDate: target,
                                                     partnerName: partnerName)
        let content = ActivityContent(state: CountdownActivityAttributes.ContentState(refreshedAt: Date()),
                                      staleDate: nil)
        do {
            _ = try Activity.request(attributes: attributes, content: content)
            return true
        } catch {
            return false
        }
    }

    static func stopAll() {
        for activity in Activity<CountdownActivityAttributes>.activities {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
