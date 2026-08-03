import Foundation
import ActivityKit

/// Starts/stops/updates the countdown Live Activity (lock screen + Dynamic Island).
/// Updates come from the WebSocket while the app is open — no APNs involved.
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
        let content = ActivityContent(state: currentState(), staleDate: nil)
        do {
            _ = try Activity.request(attributes: attributes, content: content)
            return true
        } catch {
            return false
        }
    }

    /// Refreshes all running countdown activities from the shared widget snapshot.
    static func updateFromSnapshot() {
        let snapshot = SharedStore.readSnapshot()
        update(partnerOnline: snapshot?.partnerOnline,
               mood: snapshot?.partnerMood,
               lastTouchEmoji: snapshot?.lastTouchType.map(TouchEmoji.map),
               streak: snapshot?.streak,
               note: snapshot?.partnerMoodNote)
    }

    /// Pushes fresh couple context into every running countdown activity.
    static func update(partnerOnline: Bool?, mood: String?, lastTouchEmoji: String?,
                       streak: Int?, note: String? = nil) {
        let activities = Activity<CountdownActivityAttributes>.activities
        guard !activities.isEmpty else { return }
        let state = CountdownActivityAttributes.ContentState(refreshedAt: Date(),
                                                             partnerOnline: partnerOnline,
                                                             partnerMood: mood,
                                                             lastTouchEmoji: lastTouchEmoji,
                                                             streak: streak,
                                                             note: note)
        let content = ActivityContent(state: state, staleDate: nil)
        for activity in activities {
            Task {
                await activity.update(content)
            }
        }
    }

    /// Ends running countdowns for a deleted event (matched by title).
    static func stop(matchingTitle title: String) {
        for activity in Activity<CountdownActivityAttributes>.activities
        where activity.attributes.title == title {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// Ends countdowns whose event no longer exists (e.g. partner deleted it).
    static func stopIfEventMissing(events: [EventItem]) {
        let titles = Set(events.map(\.title))
        for activity in Activity<CountdownActivityAttributes>.activities
        where !titles.contains(activity.attributes.title) {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    static func stopAll() {
        for activity in Activity<CountdownActivityAttributes>.activities {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private static func currentState() -> CountdownActivityAttributes.ContentState {
        let snapshot = SharedStore.readSnapshot()
        return CountdownActivityAttributes.ContentState(
            refreshedAt: Date(),
            partnerOnline: snapshot?.partnerOnline,
            partnerMood: snapshot?.partnerMood,
            lastTouchEmoji: snapshot?.lastTouchType.map(TouchEmoji.map),
            streak: snapshot?.streak,
            note: snapshot?.partnerMoodNote)
    }
}
