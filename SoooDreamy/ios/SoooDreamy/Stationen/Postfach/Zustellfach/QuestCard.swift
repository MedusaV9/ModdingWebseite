import SwiftUI

// Onboarding quest: "first week" checklist for new couples —
// seven guided mini-adventures, finale = bonus XP + badge (server-side).

struct QuestCard: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @State private var expanded = true

    /// Step id → (icon, tab to jump to). Steps mirror the server's list.
    private static let stepMeta: [String: (icon: Icon, tab: AppTab)] = [
        "touch": (.sendLove, .home),
        "message": (.chat, .chat),
        "daily": (.dailyQuestion, .home),
        "photo": (.photo, .memories),
        "canvas": (.canvas, .memories),
        "checkin": (.checkin, .home),
        "game": (.games, .play),
    ]

    var body: some View {
        // Only for fresh couples, and only until the quest is done — after
        // the finale ceremony the card retires from the dashboard for good.
        if let quest = appState.quest, quest.isNewCouple, !quest.done {
            card(quest)
        }
    }

    private func card(_ quest: QuestState) -> some View {
        let doneCount = quest.steps.filter(\.done).count
        return VStack(alignment: .leading, spacing: LayoutMetrics.s(12)) {
            Button {
                Haptics.shared.tap()
                withAnimation(Theme.Motion.settle) { expanded.toggle() }
            } label: {
                HStack(spacing: LayoutMetrics.s(10)) {
                    IconBadge(icon: .quest, accented: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("quest.card.title"))
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundStyle(Papier.aufNacht)
                        Text(L10n.t("quest.card.subtitle"))
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Nacht.sekundaer)
                    }
                    Spacer(minLength: 0)
                    Text(L10n.t("quest.progress",
                                ["done": String(doneCount), "total": String(quest.steps.count)]))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(Licht.glut)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(Typo.caption)
                        .foregroundStyle(Nacht.tertiaer)
                }
            }
            .buttonStyle(.plain)

            // Overall progress bar — fills gold as the week unfolds.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Papier.nachtInnenFill)
                    // The couple band as a progress OBJECT on the night card —
                    // the gradient never returns as a wash (Art Direction v2).
                    Capsule()
                        .fill(coupleTint.band)
                        .frame(width: max(6, geo.size.width
                            * CGFloat(doneCount) / CGFloat(max(1, quest.steps.count))))
                }
            }
            .frame(height: 7)

            if expanded {
                VStack(spacing: LayoutMetrics.s(8)) {
                    ForEach(quest.steps) { step in
                        stepRow(step)
                    }
                }
                Text(L10n.t("quest.bonus", ["xp": String(quest.bonusXp)]))
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(Licht.lampengold)
            }
        }
        .nightCard()
    }

    private func stepRow(_ step: QuestStep) -> some View {
        let meta = Self.stepMeta[step.id] ?? (.memory, .home)
        return Button {
            guard !step.done else { return }
            Haptics.shared.tap()
            appState.activeTab = meta.tab
        } label: {
            HStack(spacing: LayoutMetrics.s(10)) {
                Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(step.done ? Licht.lampengold : Nacht.tertiaer)
                IconBadge(icon: meta.icon, font: Typo.label)
                Text(L10n.t("quest.step.\(step.id)"))
                    .font(.system(.subheadline, design: .rounded).weight(step.done ? .regular : .semibold))
                    .foregroundStyle(step.done ? Nacht.tertiaer : Papier.aufNacht)
                    .strikethrough(step.done, color: Nacht.tertiaer)
                Spacer(minLength: 0)
                if !step.done {
                    Image(systemName: "chevron.right")
                        .font(Typo.caption)
                        .foregroundStyle(Nacht.tertiaer)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(step.done)
    }
}
