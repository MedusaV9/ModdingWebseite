import Foundation
import ActivityKit

/// Starts/stops/updates the "Couple Pulse" Live Activity — a living lock
/// screen / Dynamic Island card with the partner's presence, mood, last touch
/// and streak. Only one pulse activity runs at a time, and it is updated
/// locally from the WebSocket while the app is open (no APNs).
@MainActor
enum CouplePulseController {
    private static let enabledKey = "sooodreamy.pulseActivity.enabled"

    static var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Settings preference — when true the pulse auto-starts on entering the
    /// main (paired) phase.
    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var isRunning: Bool {
        !Activity<CouplePulseAttributes>.activities.isEmpty
    }

    @discardableResult
    static func start(from app: AppState) -> Bool {
        guard isSupported, app.phase == .main else { return false }
        stop()   // only one pulse activity at a time
        let attributes = CouplePulseAttributes(myName: app.me?.name ?? L10n.t("common.you"),
                                               partnerName: app.partnerName)
        let content = ActivityContent(state: state(from: app), staleDate: nil)
        do {
            _ = try Activity.request(attributes: attributes, content: content)
            return true
        } catch {
            return false
        }
    }

    /// Auto-start on entering the main phase, if the user opted in.
    static func startIfEnabled(from app: AppState) {
        guard isEnabled, !isRunning else { return }
        start(from: app)
    }

    static func stop() {
        for activity in Activity<CouplePulseAttributes>.activities {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    static func updateFrom(_ app: AppState) {
        update(state(from: app))
    }

    static func updateFrom(snapshot: WidgetSnapshot) {
        update(CouplePulseAttributes.ContentState(
            partnerOnline: snapshot.partnerOnline ?? false,
            partnerMood: snapshot.partnerMood,
            partnerMoodNote: snapshot.partnerMoodNote,
            lastTouchType: snapshot.lastTouchType,
            lastTouchAt: snapshot.lastTouchAt,
            streak: snapshot.streak,
            bothAnsweredToday: snapshot.dailyBothAnswered,
            daysTogether: snapshot.daysTogether,
            refreshedAt: Date()))
    }

    static func update(_ state: CouplePulseAttributes.ContentState) {
        let activities = Activity<CouplePulseAttributes>.activities
        guard !activities.isEmpty else { return }
        let content = ActivityContent(state: state, staleDate: nil)
        for activity in activities {
            Task {
                await activity.update(content)
            }
        }
    }

    private static func state(from app: AppState) -> CouplePulseAttributes.ContentState {
        CouplePulseAttributes.ContentState(
            partnerOnline: app.partner?.online ?? false,
            partnerMood: app.partner?.mood,
            partnerMoodNote: app.partner?.moodNote,
            lastTouchType: app.lastTouchType,
            lastTouchAt: app.lastTouchAt,
            streak: app.dailyEntry?.streak ?? 0,
            bothAnsweredToday: app.dailyEntry?.bothAnswered ?? false,
            daysTogether: app.daysTogether,
            refreshedAt: Date())
    }
}
