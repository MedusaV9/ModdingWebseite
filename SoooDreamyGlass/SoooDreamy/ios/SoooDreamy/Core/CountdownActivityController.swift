import Foundation
import ActivityKit

/// Starts/stops/updates the countdown Live Activity (lock screen + Dynamic Island).
/// Updates come from the WebSocket while the app is open and from the
/// background refresh task while it is not — no APNs involved.
///
/// Lifecycle (W7, B-20): the `staleDate` sits EXACTLY on the target, so the
/// stale transition is a guaranteed system-side re-render at the moment of
/// celebration even when the app has been dead since the night before. The
/// actual flip (`finishIfDue`) lights the lock screen up once and parks the
/// celebration for a few hours. Activities carry the stable `eventId`, so
/// renaming an event no longer orphans its countdown.
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
                                                     partnerName: partnerName,
                                                     eventId: event.id)
        let content = ActivityContent(state: currentState(),
                                      staleDate: CountdownLifecycle.staleDate(target: target))
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
        finishIfDue()
    }

    /// Pushes fresh couple context into every running countdown activity.
    /// Stamp-only churn is skipped: with the stale date pinned to the target,
    /// an update whose content did not change buys nothing but a re-render.
    static func update(partnerOnline: Bool?, mood: String?, lastTouchEmoji: String?,
                       streak: Int?, note: String? = nil) {
        let activities = Activity<CountdownActivityAttributes>.activities
        guard !activities.isEmpty else { return }
        let config = SharedStore.readLiveActivityConfig()
        for activity in activities {
            let old = activity.content.state
            let state = CountdownActivityAttributes.ContentState(
                refreshedAt: Date(),
                partnerOnline: partnerOnline,
                partnerMood: mood,
                lastTouchEmoji: lastTouchEmoji,
                streak: streak,
                note: note,
                config: config,
                celebration: old.celebration)
            guard ActivityUpdateHygiene.contentChanged(old, state) else { continue }
            let content = ActivityContent(
                state: state,
                staleDate: CountdownLifecycle.staleDate(target: activity.attributes.targetDate))
            Task {
                await activity.update(content)
            }
        }
    }

    /// Restyles running activities after the Live-Activity sheet changed the
    /// config — same data, new `config` in the state.
    static func pushConfig() {
        updateFromSnapshot()
    }

    /// Flips activities whose moment arrived into a celebration that lights
    /// the lock screen up once (AlertConfiguration) and dismisses itself a
    /// few hours later. Called from snapshot updates, foreground refreshes
    /// and the background task — the flip happens at most once per activity
    /// (`celebration` guards it).
    static func finishIfDue() {
        for activity in Activity<CountdownActivityAttributes>.activities
        where activity.attributes.targetDate <= Date() {
            var state = activity.content.state
            guard state.celebration != true else { continue }
            state.celebration = true
            state.refreshedAt = Date()
            state.config = SharedStore.readLiveActivityConfig()
            let content = ActivityContent(state: state, staleDate: nil)
            let text = ActivityAlertText.countdownArrived(title: activity.attributes.title,
                                                          emoji: activity.attributes.emoji,
                                                          language: SharedStore.resolvedLanguage)
            let alert = AlertConfiguration(title: "\(text.title)", body: "\(text.body)",
                                           sound: .default)
            Task {
                // The alert needs an update (end() cannot carry one); the end
                // right after parks the celebration and schedules the exit.
                await activity.update(content, alertConfiguration: alert)
                await activity.end(content,
                                   dismissalPolicy: .after(Date().addingTimeInterval(CountdownLifecycle.celebrationLinger)))
            }
        }
    }

    /// Ends running countdowns for a deleted event (matched by title —
    /// legacy path, prefer `stopIfEventMissing` which matches by id).
    static func stop(matchingTitle title: String) {
        for activity in Activity<CountdownActivityAttributes>.activities
        where activity.attributes.title == title {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// Ends countdowns whose event no longer exists (e.g. partner deleted
    /// it). W7 (B-20): prefers the stable event id, so renamed events keep
    /// their activity; pre-W7 activities without an id fall back to title
    /// matching. Celebrations already underway are never treated as orphans.
    static func stopIfEventMissing(events: [EventItem]) {
        let activities = Activity<CountdownActivityAttributes>.activities
        guard !activities.isEmpty else { return }
        let shaped = activities.map {
            (eventId: $0.attributes.eventId,
             title: $0.attributes.title,
             target: $0.attributes.targetDate)
        }
        let orphans = CountdownLifecycle.orphanIndices(activities: shaped,
                                                       eventIds: Set(events.map(\.id)),
                                                       eventTitles: Set(events.map(\.title)))
        for index in orphans {
            let activity = activities[index]
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// One sweep for app start and background refreshes: end orphans, flip
    /// due celebrations, push fresh couple context.
    static func reconcile(events: [EventItem]) {
        stopIfEventMissing(events: events)
        updateFromSnapshot()
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
            note: snapshot?.partnerMoodNote,
            config: SharedStore.readLiveActivityConfig())
    }
}
