import Foundation
import ActivityKit

/// Drives the Date-Night Live Activity: one activity per
/// planned date night, phase changes as state updates (never a restart —
/// the Dynamic Island would flicker). Both partners run their own activity;
/// the server relays plan + phase via `datenight_update`, and the activity's
/// own "Weiter" button (DateNightAdvanceIntent) works even app-closed.
///
/// W7 lifecycle: the flip to "live" may light the lock screen up once
/// (AlertConfiguration); the afterglow ends the evening with dignity — the
/// card parks and removes itself a few hours later instead of rotting.
@MainActor
enum DateNightActivityController {
    static var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Reconciles the running activity with the server state:
    /// nil → end, new id → restart, same id → phase/style update.
    /// `allowStart` is false when called from the background task — iOS
    /// forbids requesting activities from a backgrounded process, so the
    /// bridge only updates/ends there.
    static func sync(_ dateNight: DateNight?, allowStart: Bool = true) {
        let running = Activity<DateNightActivityAttributes>.activities
        guard let night = dateNight else {
            for activity in running {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
            return
        }
        let state = contentState(for: night)
        let stale = DateNightLifecycle.staleDate(isAfterglow: night.phase == .afterglow,
                                                 startsAt: night.startsAt,
                                                 phaseChangedAt: night.phaseChangedAt)
        if let existing = running.first(where: { $0.attributes.dateNightId == night.id }) {
            let old = existing.content.state
            if night.phase == .afterglow {
                // The evening winds down: park the afterglow card and let it
                // leave the lock screen on its own a few hours later.
                Task {
                    await existing.end(
                        ActivityContent(state: state, staleDate: stale),
                        dismissalPolicy: .after(DateNightLifecycle.endDate(phaseChangedAt: night.phaseChangedAt)))
                }
                return
            }
            guard ActivityUpdateHygiene.contentChanged(old, state) else { return }
            let content = ActivityContent(state: state, staleDate: stale)
            let alert = liveAlert(old: old, new: state, activity: existing)
            Task {
                await existing.update(content, alertConfiguration: alert)
            }
            return
        }
        for activity in running {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        guard isSupported, allowStart else { return }
        // Never resurrect an evening that already wound down.
        if night.phase == .afterglow,
           DateNightLifecycle.endDate(phaseChangedAt: night.phaseChangedAt) <= Date() { return }
        let attributes = DateNightActivityAttributes(
            dateNightId: night.id,
            partnerName: SharedStore.readSnapshot()?.partnerName)
        _ = try? Activity.request(attributes: attributes,
                                  content: ActivityContent(state: state, staleDate: stale))
    }

    /// 💞 The flip to "live" is THE lock-screen moment of the evening — it
    /// happens exactly once per date night, so no budget bookkeeping needed.
    private static func liveAlert(old: DateNightActivityAttributes.ContentState,
                                  new: DateNightActivityAttributes.ContentState,
                                  activity: Activity<DateNightActivityAttributes>) -> AlertConfiguration? {
        guard old.phase != DateNightPhaseID.live, new.phase == DateNightPhaseID.live
        else { return nil }
        let text = ActivityAlertText.dateNightLive(partnerName: activity.attributes.partnerName,
                                                   language: SharedStore.resolvedLanguage)
        return AlertConfiguration(title: "\(text.title)", body: "\(text.body)", sound: .default)
    }

    private static func contentState(for night: DateNight) -> DateNightActivityAttributes.ContentState {
        DateNightActivityAttributes.ContentState(
            title: night.title,
            emoji: night.emoji,
            startsAt: night.startsAt,
            phase: night.phase.rawValue,
            phaseChangedAt: night.phaseChangedAt,
            refreshedAt: Date(),
            config: SharedStore.readLiveActivityConfig())
    }
}
