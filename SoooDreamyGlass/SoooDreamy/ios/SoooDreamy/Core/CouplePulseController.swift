import Foundation
import ActivityKit

/// Starts/stops/updates the "Couple Pulse" Live Activity — a living lock
/// screen / Dynamic Island card with the partner's presence, mood, last touch
/// and streak. Only one pulse activity runs at a time, and it is updated
/// locally from the WebSocket while the app is open plus from the background
/// refresh task while it is not (no APNs on a sideload).
///
/// Lifecycle (W7): every update sets a `staleDate` 25 min out — presence must
/// never look fresher than the app can actually vouch for (B-19). Updates are
/// deduplicated (a new refresh stamp alone is no reason to re-render the
/// island), a freshly received touch may light up the lock screen once via
/// `AlertConfiguration`, and the good-night ritual ends the card with a day
/// summary instead of letting it rot. When the user swipes the card away,
/// the in-app toggle follows (dismiss sync) — no silent auto-restarts.
@MainActor
enum CouplePulseController {
    private static let enabledKey = "sooodreamy.pulseActivity.enabled"
    /// Presence/mood data older than this is stale (shown dimmed by iOS).
    private static let staleInterval = ActivityHonesty.pulseStaleInterval

    /// Lock-screen alert budget per activity id (charter: at most two per
    /// activity lifetime — key moments, never a drumbeat).
    private static var alertsSent: [String: Int] = [:]
    /// One watcher task per running activity — flips the preference off when
    /// the user dismisses the card from the lock screen.
    private static var dismissWatchers: [String: Task<Void, Never>] = [:]

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
        let content = ActivityContent(state: state(from: app),
                                      staleDate: Date().addingTimeInterval(staleInterval))
        do {
            let activity = try Activity.request(attributes: attributes, content: content)
            watchDismissal(of: activity)
            return true
        } catch {
            return false
        }
    }

    /// Auto-start on entering the main phase, if the user opted in. Also
    /// re-attaches the dismiss watchers to activities that survived an app
    /// relaunch — otherwise a swipe-away would go unnoticed.
    static func startIfEnabled(from app: AppState) {
        for activity in Activity<CouplePulseAttributes>.activities {
            watchDismissal(of: activity)
        }
        guard isEnabled, !isRunning else { return }
        start(from: app)
    }

    static func stop() {
        for activity in Activity<CouplePulseAttributes>.activities {
            forget(activityId: activity.id)
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// W7: the good-night ritual's dignified ending — the card shows the
    /// day's summary ("Heute berührt 💓 · Serie 12 · Gute Nacht 🌙") and
    /// removes itself a couple of hours later instead of going stale.
    static func endWithDaySummary() {
        let snapshot = SharedStore.readSnapshot()
        let summary = PulseDaySummary.line(
            streak: snapshot?.streak ?? 0,
            bothAnswered: snapshot?.dailyBothAnswered ?? false,
            lastTouchEmoji: snapshot?.lastTouchType.map(TouchEmoji.map),
            language: SharedStore.resolvedLanguage)
        for activity in Activity<CouplePulseAttributes>.activities {
            forget(activityId: activity.id)
            var state = activity.content.state
            state.daySummary = summary
            state.refreshedAt = Date()
            let content = ActivityContent(state: state, staleDate: nil)
            Task {
                await activity.end(content,
                                   dismissalPolicy: .after(Date().addingTimeInterval(PulseDaySummary.linger)))
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
            partnerPresenceMode: freshPresenceMode(snapshot.partnerPresenceMode,
                                                   until: snapshot.partnerPresenceUntil),
            lastTouchType: snapshot.lastTouchType,
            lastTouchAt: snapshot.lastTouchAt,
            streak: snapshot.streak,
            bothAnsweredToday: snapshot.dailyBothAnswered,
            daysTogether: snapshot.daysTogether,
            refreshedAt: Date(),
            config: SharedStore.readLiveActivityConfig(),
            dailyRevealPending: snapshot.revealSealPending()))
    }

    /// Snapshot presence is only forwarded while still active —
    /// mirrors the server's lazy expiry so a stale glow never lingers.
    private static func freshPresenceMode(_ mode: String?, until: Date?) -> String? {
        guard let mode else { return nil }
        return PresenceLogic.isActive(until: until) ? mode : nil
    }

    /// Restyles the running pulse after the Live-Activity sheet changed the
    /// config — same data, new `config` in the state.
    static func pushConfig() {
        guard isRunning, let snapshot = SharedStore.readSnapshot() else { return }
        updateFrom(snapshot: snapshot)
    }

    static func update(_ state: CouplePulseAttributes.ContentState) {
        for activity in Activity<CouplePulseAttributes>.activities {
            let old = activity.content.state
            let changed = ActivityUpdateHygiene.contentChanged(old, state)
            // Skip stamp-only churn, but keep the short stale window sliding
            // while the app demonstrably lives (keep-alive pushes).
            guard ActivityHonesty.shouldPush(contentChanged: changed,
                                             staleDate: activity.content.staleDate,
                                             staleInterval: staleInterval) else { continue }
            let content = ActivityContent(state: state,
                                          staleDate: Date().addingTimeInterval(staleInterval))
            let alert = touchAlert(old: old, new: state, activity: activity)
            Task {
                await activity.update(content, alertConfiguration: alert)
            }
        }
    }

    /// A freshly received touch is THE lock-screen moment of the pulse —
    /// it may light the screen up, but only within the sparse alert budget.
    private static func touchAlert(old: CouplePulseAttributes.ContentState,
                                   new: CouplePulseAttributes.ContentState,
                                   activity: Activity<CouplePulseAttributes>) -> AlertConfiguration? {
        guard ActivityUpdateHygiene.isNewer(new.lastTouchAt, than: old.lastTouchAt),
              let type = new.lastTouchType,
              ActivityAlertBudget.mayAlert(alreadySent: alertsSent[activity.id] ?? 0)
        else { return nil }
        alertsSent[activity.id] = (alertsSent[activity.id] ?? 0) + 1
        let text = ActivityAlertText.touchReceived(partnerName: activity.attributes.partnerName,
                                                   emoji: TouchEmoji.map(type),
                                                   language: SharedStore.resolvedLanguage)
        return AlertConfiguration(title: "\(text.title)", body: "\(text.body)", sound: .default)
    }

    /// Dismiss sync: when the user swipes the card off the lock screen, the
    /// Settings toggle follows — the pulse must never silently come back.
    private static func watchDismissal(of activity: Activity<CouplePulseAttributes>) {
        guard dismissWatchers[activity.id] == nil else { return }
        dismissWatchers[activity.id] = Task {
            for await state in activity.activityStateUpdates where state == .dismissed {
                isEnabled = false
            }
            dismissWatchers[activity.id] = nil
        }
    }

    /// Deliberate (programmatic) ends must not count as user dismissals.
    private static func forget(activityId: String) {
        dismissWatchers[activityId]?.cancel()
        dismissWatchers[activityId] = nil
        alertsSent[activityId] = nil
    }

    private static func state(from app: AppState) -> CouplePulseAttributes.ContentState {
        CouplePulseAttributes.ContentState(
            partnerOnline: app.partner?.online ?? false,
            partnerMood: app.partner?.mood,
            partnerMoodNote: app.partner?.moodNote,
            partnerPresenceMode: app.partnerPresence?.mode,
            lastTouchType: app.lastTouchType,
            lastTouchAt: app.lastTouchAt,
            streak: app.dailyEntry?.streak ?? 0,
            bothAnsweredToday: app.dailyEntry?.bothAnswered ?? false,
            daysTogether: app.daysTogether,
            refreshedAt: Date(),
            config: SharedStore.readLiveActivityConfig(),
            dailyRevealPending: RevealedDailyStore.sealPending(
                coupleId: app.couple?.id,
                dateKey: SharedDates.todayKey(),
                bothAnswered: app.dailyEntry?.dateKey == SharedDates.todayKey()
                    && app.dailyEntry?.bothAnswered == true))
    }
}
