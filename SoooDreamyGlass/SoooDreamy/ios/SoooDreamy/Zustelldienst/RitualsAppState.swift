import Foundation
import SwiftUI

// MARK: - App-wide reactions to ritual events
//
// Feature views keep their own live state; this extension only covers the
// GLOBAL reactions: toasts, local notifications, the partner's energy light
// on the member object and milestone confetti. Wired into AppState.handle
// via one `case … : handleRitualEvent(event)` line.

extension AppState {
    /// Mirrors an `energy` WS event (or my own PUT/DELETE) into the couple.
    func applyEnergy(memberId: String, energy: MemberEnergy?) {
        guard var couple else { return }
        if let idx = couple.members.firstIndex(where: { $0.id == memberId }) {
            couple.members[idx].energy = energy
            self.couple = couple
        }
    }

    func handleRitualEvent(_ event: ServerEvent) {
        switch event.type {
        case .need:
            if let need = event.decode(NeedEventPayload.self)?.need,
               need.forMember == memberId, let type = need.needType {
                SoundEngine.shared.play(.chime)
                Haptics.shared.tap()
                CoupleNotify.alert(.touch,
                                   title: L10n.t("needs.notif.title", ["name": partnerName]),
                                   body: "\(type.emoji) \(L10n.t(type.titleKey))",
                                   link: "sooodreamy://tab/home")
            }
        case .needAcked:
            if let need = event.decode(NeedEventPayload.self)?.need, need.senderId == memberId {
                showToast(L10n.t("needs.ackedToast", ["name": partnerName]), style: .love)
                SoundEngine.shared.play(.sparkle)
            }
        case .capsuleSealed:
            if let capsule = event.decode(CapsuleEventPayload.self)?.capsule,
               capsule.forMember == memberId {
                showToast(L10n.t("capsules.toast.sealedForYou", ["name": partnerName]), style: .love)
                SoundEngine.shared.play(.sparkle)
                CoupleNotify.alert(.message,
                                   title: L10n.t("capsules.notif.title"),
                                   body: L10n.t("capsules.notif.body", ["name": partnerName]),
                                   link: "sooodreamy://tab/memories")
            }
        case .capsuleOpened:
            if let capsule = event.decode(CapsuleEventPayload.self)?.capsule,
               capsule.createdBy == memberId {
                showToast(L10n.t("capsules.toast.openedByPartner", ["name": partnerName]), style: .love)
                SoundEngine.shared.play(.tada)
            }
        case .energy:
            if let payload = event.decode(EnergyEventPayload.self) {
                applyEnergy(memberId: payload.memberId, energy: payload.energy)
                updateWidgetSnapshot()
                if payload.memberId != memberId,
                   let energy = payload.energy,
                   let level = EnergyLevel(rawValue: energy.level) {
                    showToast(L10n.t("energy.toast.partner",
                                     ["name": partnerName,
                                      "level": "\(level.emoji) \(L10n.t(level.titleKey))"]),
                              style: .info)
                }
            }
        case .goalAdded, .goalUpdated:
            // Milestone crossings celebrate on BOTH phones, wherever they are.
            if let payload = event.decode(GoalEventPayload.self) {
                widgetGoal = payload.goal.completedAt == nil
                    ? WidgetSnapshotResponse.GoalSummary(
                        id: payload.goal.id, title: payload.goal.title, emoji: payload.goal.emoji,
                        targetValue: payload.goal.targetValue, unit: payload.goal.unit,
                        targetDate: payload.goal.targetDate, total: payload.goal.total,
                        percent: payload.goal.percent)
                    : nil
                updateWidgetSnapshot()
                guard let milestone = payload.milestone else { break }
                // The booking device already celebrated at REST success
                // (GoalContributeSheet) — its own echo of this broadcast
                // must not stage a SECOND ceremony nor book a second
                // arbiter slot for the same completion (documented eval
                // repro: double confetti + double budget booking). The
                // toast stays on every device; only the ceremony is a
                // partner effect.
                let celebrates = allowsPartnerEffects(event)
                if milestone >= 100 {
                    // Broadcast twin of GoalsView's completion path: the
                    // app-wide arbiter sizes the ceremony (epic while the
                    // budget lasts, medium afterwards — never silent).
                    if celebrates {
                        Delight.celebrate(DelightArbiterStore.request(.goalCompleted),
                                          theme: .confetti)
                    }
                    showToast(L10n.t("goals.toast.reached", ["title": payload.goal.title]), style: .love)
                } else {
                    if celebrates {
                        // R1-D: the fixed-MEDIUM milestone blooms in the
                        // app-wide Lichtschein; the arbiter-sized path
                        // above stays Delight (it may grant epic).
                        AppCue.fanfareMedium.play()
                        LichtscheinCenter.shared.fire()
                    }
                    showToast(L10n.t("goals.toast.milestone",
                                     ["percent": String(milestone), "title": payload.goal.title]),
                              style: .success)
                }
            }
        case .goalDeleted:
            Task {
                await refreshWidgetCore()
                updateWidgetSnapshot()
            }
        case .daymemo:
            // The reveal moment: my partner completed the pair for today.
            // The payload carries no member attribution, so the frame's
            // origin marker is the ONLY thing separating "partner finished
            // the pair" from "I finished it on my other device" — without
            // the gate, the own second device celebrated its own memo
            // (documented eval trace #3).
            if allowsPartnerEffects(event),
               let day = event.decode(DaymemoDay.self),
               day.dateKey == SharedDates.todayKey(),
               day.bothRecorded, day.partner != nil {
                SoundEngine.shared.play(.sparkle)
                CoupleNotify.alert(.dailyReveal,
                                   title: L10n.t("daymemo.notif.title"),
                                   body: L10n.t("daymemo.notif.body"),
                                   link: "sooodreamy://tab/home")
            }
        default:
            break
        }
    }
}

/// Shared honest error state for the primary rituals loaders (goals,
/// daymemos, capsules, needs history): a failed load shows THIS with a
/// retry instead of merely looking empty (SurfaceState/PolishAudit rule).
struct RitualsLoadFailedNotice: View {
    let connected: Bool
    let retry: () -> Void

    var body: some View {
        if connected {
            StateNoticeView(kind: .failed,
                            title: L10n.t("rituals.load.failed.title"),
                            message: L10n.t("rituals.load.failed.message"),
                            retry: retry)
        } else {
            StateNoticeView(kind: .offline,
                            title: L10n.t("rituals.load.offline.title"),
                            message: L10n.t("rituals.load.offline.message"),
                            retry: retry)
        }
    }
}
