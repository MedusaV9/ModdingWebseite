import Foundation
import SwiftUI
import WidgetKit

// "Level, Delight & Plattform": gamification state, icon
// gifts, haptic duet, live heartbeat and date night — split out of
// AppState.swift so the three 3.0 agents don't collide in one file.
// Stored properties live in AppState (Observable macro needs them there).

private struct EnvelopeTs: Decodable { let ts: Date }

extension ServerEvent {
    /// Server timestamp every WS frame carries (clock sync source).
    var serverTime: Date? { try? API.decoder.decode(EnvelopeTs.self, from: rawData).ts }
}

extension AppState {
    // MARK: Refresh

    /// Pulls level, badges, quest and platform state — part of refreshAll().
    func refreshGamification() async {
        guard let api else { return }
        async let levelReq = try? api.level()
        async let badgesReq = try? api.badges()
        async let questReq = try? api.quest()
        async let giftReq = try? api.pendingIconGift()
        async let dateReq = try? api.dateNight()
        if let level = await levelReq { levelState = level }
        if let list = await badgesReq { badges = list }
        if let state = await questReq { quest = state }
        pendingIconGift = (await giftReq).flatMap { $0 }
        dateNight = (await dateReq).flatMap { $0 }
        DateNightActivityController.sync(dateNight)
    }

    /// Clears everything on sign-out / server switch.
    func resetPlatformState() {
        levelState = nil
        badges = []
        quest = nil
        pendingIconGift = nil
        dateNight = nil
        activeDuet = nil
        levelUpCeremony = nil
        badgeCeremony = nil
        celebrationBadgeStack = []
        celebrationPresentedAt = nil
        celebrationQueue.removeAll()
        partnerHeartbeatTap = nil
        partnerTapCount = 0
        duetPlayTask?.cancel()
        ClockSync.shared.reset()
        DateNightActivityController.sync(nil)
    }

    // MARK: WS events

    /// Called from AppState.handle's default branch for v3.0 event types.
    func handlePlatformEvent(_ event: ServerEvent) {
        switch event.type {
        case .pong:
            ClockSync.shared.handlePong(echo: event.decode(PongPayload.self)?.echo,
                                        serverTime: event.serverTime)

        case .levelUp:
            if let payload = event.decode(LevelUpPayload.self) {
                enqueueCelebration(.level(payload))
                Task {
                    await refreshGamification()
                    updateWidgetSnapshot()
                }
            }

        case .badgeUnlocked:
            if let badge = event.decode(BadgeUnlockedPayload.self)?.badge {
                enqueueCelebration(.badge(badge))
                Task { await refreshGamification() }
            }

        case .questCompleted:
            if let payload = event.decode(QuestCompletedPayload.self) {
                quest = payload.quest
                showToast(L10n.t("quest.completedToast"), style: .love)
            }

        case .iconGift:
            if let gift = event.decode(IconGiftPayload.self)?.gift {
                pendingIconGift = gift
                SoundEngine.shared.play(.sparkle)
                CoupleNotify.alert(.touch,
                                   title: L10n.t("icongift.notif.title"),
                                   body: L10n.t("icongift.notif.body", ["name": partnerName]),
                                   link: "sooodreamy://tab/home")
            }

        case .iconGiftOpened:
            if let gift = event.decode(IconGiftPayload.self)?.gift, gift.fromMemberId == memberId {
                showToast(L10n.t("icongift.openedToast", ["name": partnerName]), style: .love)
                // R1-D: the fixed-SMALL sender moment blooms in the
                // app-wide Lichtschein instead of confetti; the level/
                // badge paths below stay Delight (arbiter-sized, may
                // grant epic — only fixed small/medium moved).
                AppCue.fanfareSmall.play()
                LichtscheinCenter.shared.fire()
            }

        case .duetStart:
            if let duet = event.decode(DuetStartPayload.self)?.duet {
                beginDuetPlayback(duet)
            }

        case .heartbeatTap:
            if let tap = event.decode(HeartbeatTapPayload.self), tap.memberId != memberId {
                partnerHeartbeatTap = tap
                partnerTapCount += 1
                // Transient pulse scaled by the partner's touch strength.
                Haptics.shared.play(events: [
                    HapticEventSpec(t: 0, i: max(0.35, min(1, tap.intensity)), s: 0.45, d: 0)
                ])
            }

        case .datenightUpdate:
            if let payload = event.decode(DateNightUpdatePayload.self) {
                let previous = dateNight
                dateNight = payload.dateNight
                DateNightActivityController.sync(payload.dateNight)
                if let night = payload.dateNight, night.createdBy != memberId,
                   previous?.id != night.id {
                    showToast(L10n.t("datenight.plannedToast", ["name": partnerName]), style: .love)
                    SoundEngine.shared.play(.sparkle)
                }
            }

        case .gameCreated, .gameStarted, .gameMove, .gameEnded:
            // B-16 play-tab badge + decline/forfeit moments — the game views
            // keep observing .serverEvent themselves on top of this.
            handleGameEvent(event)

        case .appEvent:
            // XP is recomputed server-side; the next level/badge advance
            // arrives as its own event. Nothing to do live.
            break

        case .weekHighlight:
            // „Eure Woche": tailored per-member payload. WeekReviewView
            // keeps its own live copy; here only the global nudges.
            if let review = event.decode(WeekReviewResponse.self) {
                if review.highlight.bothShared {
                    showToast(L10n.t("weekreview.toast.revealed"), style: .love)
                    SoundEngine.shared.play(.sparkle)
                } else if review.highlight.mine == nil {
                    showToast(L10n.t("weekreview.toast.partnerShared", ["name": partnerName]),
                              style: .love)
                    SoundEngine.shared.play(.pop)
                }
            }

        default:
            break   // feature views observe .serverEvent themselves
        }
    }

    // MARK: FIFO ceremonies (budgeted + coalesced via DelightArbiter)

    func enqueueCelebration(_ celebration: QueuedCelebration) {
        // Coalescing: events landing right after a ceremony took the stage
        // (level-up + its badges arrive in the SAME server write) join it
        // as stacked content — ONE moment, one fanfare, nothing lost.
        if hasActiveCelebration,
           DelightArbiter.shouldCoalesce(lastPresentedAt: celebrationPresentedAt,
                                         next: Date()) {
            switch celebration {
            case .badge(let badge):
                stackBadge(badge)
                return
            case .level(let payload):
                // A level-up outranks the badge on stage: the medal moves
                // into the stack, the level leads — still one ceremony.
                if let onStage = badgeCeremony {
                    stackBadge(onStage)
                    badgeCeremony = nil
                    levelUpCeremony = payload
                    return
                }
            }
        }
        guard !hasActiveCelebration else {
            celebrationQueue.enqueue(celebration)
            return
        }
        presentCelebration(celebration)
    }

    private var hasActiveCelebration: Bool {
        levelUpCeremony != nil || badgeCeremony != nil
    }

    private func stackBadge(_ badge: BadgeState) {
        guard badgeCeremony?.id != badge.id,
              !celebrationBadgeStack.contains(where: { $0.id == badge.id }) else { return }
        celebrationBadgeStack.append(badge)
    }

    func dismissActiveCelebration() {
        levelUpCeremony = nil
        badgeCeremony = nil
        celebrationBadgeStack = []
        celebrationPresentedAt = nil
        if let next = celebrationQueue.dequeue() {
            presentCelebration(next)
        }
    }

    private func presentCelebration(_ celebration: QueuedCelebration) {
        celebrationPresentedAt = Date()
        switch celebration {
        case .level(let payload):
            levelUpCeremony = payload
            // The arbiter grants the size: epic while the app-wide budget
            // lasts, medium afterwards — degraded, never silenced.
            Delight.celebrate(DelightArbiterStore.request(.levelUp), theme: .confetti)
        case .badge(let badge):
            badgeCeremony = badge
            Delight.celebrate(
                DelightArbiterStore.request(badge.secret ? .secretBadge : .badge),
                theme: .stars)
        }
    }

    // MARK: Icon gifts

    /// Sends an icon as a gift; the partner gets the unwrap ceremony.
    func giftIcon(_ icon: String, note: String?) async -> Bool {
        guard let api else { return false }
        do {
            _ = try await api.sendIconGift(icon: icon, note: note)
            showToast(L10n.t("icongift.sentToast", ["name": partnerName]), style: .love)
            AppCue.sealed.play()
            return true
        } catch {
            handleAPIError(error)
            return false
        }
    }

    /// Unwraps my pending gift (the ceremony view applies the icon after).
    func unwrapIconGift() async -> IconGift? {
        guard let api else { return nil }
        do {
            let gift = try await api.openIconGift()
            pendingIconGift = nil
            return gift
        } catch {
            pendingIconGift = nil   // gone on the server → drop stale state
            return nil
        }
    }

    // MARK: Haptic duet & live heartbeat

    /// Starts a duet — playback happens via the `duet_start` broadcast so
    /// both phones (including this one) run the exact same schedule.
    func startDuet(events: [HapticEventSpec], name: String?) async {
        guard let api else { return }
        ClockSync.shared.sample(via: socket)
        do {
            _ = try await api.startDuet(events: events, name: name)
        } catch {
            handleAPIError(error)
        }
    }

    /// Countdown + scheduled playback at the shared server-time instant.
    func beginDuetPlayback(_ duet: DuetSession) {
        activeDuet = duet
        let fireAt = ClockSync.shared.localDate(forServerMs: duet.startAtMs,
                                                fallbackServerNowMs: duet.serverNowMs)
        duetPlayTask?.cancel()
        duetPlayTask = Task { [weak self] in
            let delay = fireAt.timeIntervalSinceNow
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            Haptics.shared.play(events: duet.events)
            SoundEngine.shared.play(.heartbeat)
            let linger = HapticTimeline.duration(of: duet.events) + 2.0
            try? await Task.sleep(nanoseconds: UInt64(max(3.0, linger) * 1_000_000_000))
            if !Task.isCancelled { self?.activeDuet = nil }
        }
    }

    /// Streams one live heartbeat tap to the partner (fire-and-forget WS).
    func sendHeartbeatTap(intensity: Double) {
        socket.send(["type": "heartbeat_tap",
                     "payload": ["intensity": max(0, min(1, intensity))]])
    }

    // MARK: Date night

    func planDateNight(title: String?, emoji: String?, startsAt: Date) async {
        guard let api else { return }
        do {
            let night = try await api.setDateNight(title: title, emoji: emoji, startsAt: startsAt)
            dateNight = night
            DateNightActivityController.sync(night)
            SoundEngine.shared.play(.sparkle)
        } catch {
            handleAPIError(error)
        }
    }

    func advanceDateNightPhase() async {
        guard let api, let night = dateNight, let next = night.phase.next else { return }
        do {
            let updated = try await api.setDateNightPhase(next)
            dateNight = updated
            DateNightActivityController.sync(updated)
            if next == .live {
                // R1-D: the date-night start blooms in the Lichtschein.
                AppCue.fanfareMedium.play()
                LichtscheinCenter.shared.fire()
            }
        } catch {
            handleAPIError(error)
        }
    }

    func cancelDateNight() async {
        guard let api else { return }
        do {
            try await api.clearDateNight()
            dateNight = nil
            DateNightActivityController.sync(nil)
        } catch {
            handleAPIError(error)
        }
    }
}
