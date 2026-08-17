import SwiftUI

// Date night: the couple plans an evening; both phones run
// a Live Activity countdown with phases (anticipation → live → afterglow).
// This file: the dashboard card + the planning sheet.

struct DateNightCard: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @State private var showPlanSheet = false
    @State private var advancing = false

    var body: some View {
        Group {
            if let night = appState.dateNight {
                activeCard(night)
            } else if appState.partner != nil {
                planCTA
            }
        }
        .sheet(isPresented: $showPlanSheet) {
            DateNightPlanSheet()
        }
    }

    // MARK: No plan yet — one-line invitation

    private var planCTA: some View {
        Button {
            Haptics.shared.tap()
            showPlanSheet = true
        } label: {
            HStack(spacing: LayoutMetrics.s(12)) {
                IconBadge(icon: .night, accented: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("datenight.plan"))
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(Papier.aufNacht)
                    Text(L10n.t("datenight.liveActivityHint"))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Nacht.tertiaer)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(Typo.caption)
                    .foregroundStyle(Nacht.tertiaer)
            }
            .nightCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: Active plan

    private func activeCard(_ night: DateNight) -> some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
            HStack(spacing: LayoutMetrics.s(10)) {
                // The couple's chosen evening emoji — content, not chrome.
                Text(night.emoji ?? night.phase.emoji)
                    .font(.system(.title))
                VStack(alignment: .leading, spacing: 2) {
                    Text(night.title ?? L10n.t("datenight.card.title"))
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Papier.aufNacht)
                        .lineLimit(1)
                    Text(L10n.t("datenight.phase.\(night.phase.rawValue)"))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(Licht.glut)
                }
                Spacer(minLength: 0)
                if night.phase == .anticipation, night.startsAt > Date() {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(L10n.t("datenight.startsIn"))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Nacht.tertiaer)
                        Text(timerInterval: Date()...night.startsAt, countsDown: true)
                            .font(.system(.subheadline, design: .rounded).weight(.heavy))
                            .foregroundStyle(Licht.lampengold)
                            .monospacedDigit()
                    }
                }
            }

            // Phase dots mirroring the Live Activity.
            HStack(spacing: 6) {
                ForEach(DateNightPhase.allCases, id: \.self) { phase in
                    let reached = phaseIndex(night.phase) >= phaseIndex(phase)
                    Capsule()
                        .fill(reached ? coupleTint.blend : Papier.nachtInnenFill)
                        .frame(width: night.phase == phase ? 26 : 14, height: 5)
                }
                Spacer(minLength: 0)

                if night.phase.next != nil {
                    Button {
                        advance()
                    } label: {
                        if advancing {
                            BusySpinner(tint: Licht.lampengold)
                        } else {
                            Label(L10n.t("datenight.next"), systemImage: "chevron.right.2")
                                .font(.system(.caption, design: .rounded).weight(.bold))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Licht.lampengold)
                    .disabled(advancing)
                }

                Menu {
                    Button(role: .destructive) {
                        Task { await appState.cancelDateNight() }
                    } label: {
                        Label(L10n.t("datenight.cancel"), systemImage: "xmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(Typo.label)
                        .foregroundStyle(Nacht.tertiaer)
                }
            }

            Text(L10n.t("datenight.liveActivityHint"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Nacht.tertiaer)
        }
        .nightCard()
    }

    private func phaseIndex(_ phase: DateNightPhase) -> Int {
        DateNightPhase.allCases.firstIndex(of: phase) ?? 0
    }

    private func advance() {
        guard !advancing else { return }
        advancing = true
        Haptics.shared.tap()
        Task {
            await appState.advanceDateNightPhase()
            advancing = false
        }
    }
}

// MARK: - Planning sheet

struct DateNightPlanSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint

    @State private var title = ""
    @State private var emoji = "🌙"
    @State private var startsAt = Self.defaultStart
    @State private var saving = false

    private static let emojis = ["🌙", "🍝", "🎬", "🕯️", "🍷", "🎳", "🌃", "🧑‍🍳", "🎮", "💃"]

    /// Tonight 19:30, or +2 h when it's already evening.
    private static var defaultStart: Date {
        let cal = SharedDates.calendar
        let candidate = cal.date(bySettingHour: 19, minute: 30, second: 0, of: Date()) ?? Date()
        return candidate > Date().addingTimeInterval(15 * 60)
            ? candidate
            : Date().addingTimeInterval(2 * 3600)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                ScrollView {
                    VStack(alignment: .leading, spacing: LayoutMetrics.s(16)) {
                        EmojiPickerGrid(emojis: Self.emojis, selection: $emoji)

                        TextField(L10n.t("datenight.titlePlaceholder"), text: $title)
                            .textFieldStyle(DreamyFieldStyle())

                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.t("datenight.when"))
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundStyle(Theme.textSecondary)
                            DatePicker("", selection: $startsAt,
                                       in: Date()...Date().addingTimeInterval(30 * 86400),
                                       displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .colorScheme(.dark)
                                .tint(coupleTint.blend)
                                // Locale-Naht (Amt-Muster, Re-Eval №9).
                                .environment(\.locale, Locale(identifier: L10n.lang))
                        }

                        Button {
                            save()
                        } label: {
                            if saving {
                                BusySpinner()
                            } else {
                                Text(L10n.t("datenight.plan"))
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(saving)

                        Text(L10n.t("datenight.liveActivityHint"))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(LayoutMetrics.s(20))
                }
            }
            .navigationTitle(L10n.t("datenight.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard !saving else { return }
        saving = true
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await appState.planDateNight(title: trimmed.isEmpty ? nil : trimmed,
                                         emoji: emoji, startsAt: startsAt)
            saving = false
            dismiss()
        }
    }
}
