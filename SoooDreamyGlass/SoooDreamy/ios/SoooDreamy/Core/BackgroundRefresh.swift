import Foundation
import BackgroundTasks
import WidgetKit

// MARK: - Background refresh (BGTaskScheduler)
// Periodically pulls partner status / moments / daily-question state from the
// couple server WITHOUT the app being open, refreshes the app-group snapshot
// and reloads all widget timelines.
//
// Honest iOS reality check (documented in README too): iOS decides when (and
// whether) BGAppRefreshTask runs — based on usage patterns, charger, Low
// Power Mode … Expect a handful of runs per day at best, none guaranteed.
// `earliestBeginDate` is a lower bound, not a schedule. Widgets therefore
// also refresh themselves (photo widget fetches directly; day-math widgets
// carry future-dated timeline entries), and the app refreshes on every open.

enum BackgroundRefresh {
    /// Must match `BGTaskSchedulerPermittedIdentifiers` in project.yml.
    static let taskId = "app.sooodreamy.refresh"

    /// Queues the next refresh (~30 min out; iOS decides the actual time).
    /// Re-submitting the same id simply replaces the pending request.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Fetches fresh couple context and rewrites the widget snapshot.
    /// Runs headless (SwiftUI `.backgroundTask` — no AppState involved) using
    /// the app-group-mirrored credentials.
    static func refreshNow() async {
        guard let creds = SharedStore.readServerCredentials(),
              let token = SharedKeychain.activeToken(profileID: creds.profileID),
              let base = URL(string: creds.baseURLString) else { return }
        let api = API(baseURL: base, token: token)

        // The authenticated server snapshot is the canonical compact source
        // for partner energy, active goal, and relationship level. Asking
        // for the LOCAL day (Schlussrunde 6) keeps the daily block correct
        // across the UTC/local midnight gap; the date gate below stays as
        // the guard for old servers that ignore the query.
        guard let remote = try? await api.widgetSnapshot(dateKey: SharedDates.todayKey())
        else { return }
        let events = (try? await api.events()) ?? []

        let previous = SharedStore.readSnapshot()
        var snapshot = previous ?? WidgetSnapshot()
        snapshot.partnerName = remote.partner?.name
        snapshot.partnerAvatar = remote.partner?.avatar
        snapshot.partnerColorHex = remote.partner?.color
        snapshot.partnerMood = remote.partner?.mood
        snapshot.partnerMoodNote = remote.partner?.moodNote
        snapshot.partnerMoodUpdatedAt = remote.partner?.moodUpdatedAt
        snapshot.partnerEnergyLevel = remote.partner?.energy?.level
        snapshot.partnerEnergyNote = remote.partner?.energy?.note
        snapshot.partnerEnergySetAt = remote.partner?.energy?.setAt
        snapshot.partnerOnline = remote.partner?.online
        snapshot.myName = remote.me.name
        snapshot.anniversary = remote.couple.anniversary
        snapshot.daysTogether = remote.daysTogether

        let upcoming = events
            .compactMap { ev -> (EventItem, Int)? in
                guard let d = SharedDates.daysUntil(ev.date, repeatsYearly: ev.repeatsYearly),
                      d >= 0 else { return nil }
                return (ev, d)
            }
            .sorted { $0.1 < $1.1 }
        snapshot.nextEventTitle = remote.nextEvent?.title
        snapshot.nextEventEmoji = remote.nextEvent?.emoji
        snapshot.nextEventDate = remote.nextEvent?.date
        snapshot.allEvents = upcoming.map {
            WidgetEventLite(id: $0.0.id, title: $0.0.title, emoji: $0.0.emoji,
                            date: $0.0.date, repeatsYearly: $0.0.repeatsYearly)
        }

        snapshot.dailyAnsweredByMe = remote.dailyAnsweredByMe
        snapshot.dailyBothAnswered = remote.bothAnsweredToday
        snapshot.streak = remote.streak
        // Reveal seal: recomputed against the live RevealedDailyStore so a
        // ceremony broken in the app clears the seal on the next refresh.
        snapshot.coupleId = remote.couple.id
        snapshot.dailyRevealDateKey = SharedDates.todayKey()
        snapshot.dailyRevealPending = RevealedDailyStore.sealPending(
            coupleId: remote.couple.id, dateKey: SharedDates.todayKey(),
            bothAnswered: remote.bothAnsweredToday)
        // Pinned id wins (Schlussrunde 4): every device's widget must show
        // the question the server filed the answers under — but ONLY for
        // the day the server pinned it for (Schlussrunde 5): around
        // midnight the server's UTC day and this device's local day
        // diverge, and yesterday's pin must not freeze today's widget.
        let pinnedId = DailyPinRules.applicablePin(pinnedId: remote.dailyQuestionId,
                                                   pinDateKey: remote.dailyDateKey,
                                                   localDateKey: SharedDates.todayKey())
        let question = ContentPack.dailyQuestion(dateKey: SharedDates.todayKey(),
                                                 coupleId: remote.couple.id,
                                                 pinnedId: pinnedId,
                                                 pinnedText: pinnedId == nil ? nil : remote.dailyQuestion)
        snapshot.dailyQuestionDE = question.text.de
        snapshot.dailyQuestionEN = question.text.en
        snapshot.canvasStrokeCount = remote.canvasStrokeCount
        snapshot.goalTitle = remote.goal?.title
        snapshot.goalEmoji = remote.goal?.emoji
        snapshot.goalPercent = remote.goal?.percent
        snapshot.levelNumber = remote.level?.level
        snapshot.levelTitleDE = remote.level?.title.de
        snapshot.levelTitleEN = remote.level?.title.en
        snapshot.levelProgress = remote.level?.progress
        if let photo = remote.latestPhoto {
            snapshot.photoURLString = api.mediaURL(photo.thumbUrl ?? photo.url)?.absoluteString
            snapshot.photoCaption = photo.caption
        } else {
            snapshot.photoURLString = nil
            snapshot.photoCaption = nil
        }

        snapshot.updatedAt = Date()
        SharedStore.writeSnapshot(snapshot)
        // WidgetKit budgets reloads harshly — skip the reload when nothing
        // the widgets can see actually changed (the signature ignores the
        // write timestamp; widgets re-read `updatedAt` on natural renders).
        if previous?.contentSignature != snapshot.contentSignature {
            WidgetCenter.shared.reloadAllTimelines()
        }

        // W7 (B-find, lens 36): this task is the ONLY update channel for
        // Live Activities once the app is closed — a sideload has no APNs.
        // Bridge every run into ActivityKit: fresh couple context, due
        // celebrations, orphan cleanup, honest presence staleness.
        //
        // A failed date-night fetch must not end a running activity, so
        // network errors keep `nightFetch` nil while an explicit "no date
        // night" from the server arrives as .some(nil).
        let nightFetch: DateNight??
        do { nightFetch = try await api.dateNight() } catch { nightFetch = nil }
        await MainActor.run {
            CouplePulseController.updateFrom(snapshot: snapshot)
            CountdownActivityController.reconcile(events: events)
            if let night = nightFetch {
                // Backgrounded process: update/end only — starting a new
                // activity is not allowed here, iOS would reject it.
                DateNightActivityController.sync(night, allowStart: false)
            }
        }
    }
}
