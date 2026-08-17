import SwiftUI
import Combine

/// Gemeinsame Ziele & Sparziele: both partners book progress toward a
/// target value; milestone crossings (25/50/75/100 %) celebrate on both
/// phones via the goal_updated broadcast (see RitualsAppState).
struct GoalsView: View {
    @Environment(AppState.self) private var appState

    @State private var goals: [SharedGoal] = []
    @State private var loading = true
    @State private var loadFailed = false
    @State private var showCompose = false
    @State private var contributeGoal: SharedGoal?

    var body: some View {
        ZStack {
            DreamyBackground()
            ScrollView {
                VStack(spacing: Space.l) {
                    Text(L10n.t("goals.subtitle"))
                        .font(Typo.label)
                        .foregroundStyle(Theme.textSecondary)
                    Button {
                        Haptics.shared.tap()
                        showCompose = true
                    } label: {
                        Label(L10n.t("goals.new"), systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    if goals.isEmpty && !loading {
                        if loadFailed {
                            RitualsLoadFailedNotice(connected: appState.socket.state == .connected) {
                                Task { await reload() }
                            }
                        } else {
                            EmptyStateView(systemImage: "target",
                                           title: L10n.t("goals.empty.title"),
                                           subtitle: L10n.t("goals.empty.subtitle"))
                        }
                    }
                    if !active.isEmpty {
                        section(title: L10n.t("goals.activeSection"), items: active)
                    }
                    if !done.isEmpty {
                        section(title: L10n.t("goals.doneSection"), items: done)
                    }
                }
                .padding(Space.l)
            }
        }
        .navigationTitle(L10n.t("goals.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: appState.couple?.id) {
            await reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent else { return }
            switch event.type {
            case .goalAdded, .goalUpdated:
                if let goal = event.decode(GoalEventPayload.self)?.goal {
                    apply(goal)
                }
            case .goalDeleted:
                if let id = event.decode(IdPayload.self)?.id {
                    goals.removeAll { $0.id == id }
                }
            default:
                break
            }
        }
        .sheet(isPresented: $showCompose) {
            GoalComposeSheet { goal in
                apply(goal)
            }
        }
        .sheet(item: $contributeGoal) { goal in
            GoalContributeSheet(goal: goal) { updated in
                apply(updated)
            }
        }
    }

    private var active: [SharedGoal] { goals.filter { $0.completedAt == nil } }
    private var done: [SharedGoal] { goals.filter { $0.completedAt != nil } }

    private func apply(_ goal: SharedGoal) {
        if let idx = goals.firstIndex(where: { $0.id == goal.id }) {
            goals[idx] = goal
        } else {
            goals.insert(goal, at: 0)
        }
    }

    private func reload() async {
        guard let api = appState.api else { return }
        loading = true
        do {
            goals = try await api.goals()
            loadFailed = false
        } catch {
            // A failed primary load must not LOOK like an empty screen —
            // the shared failed/offline notice offers an honest retry.
            loadFailed = true
        }
        loading = false
    }

    private func section(title: String, items: [SharedGoal]) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(title)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(items) { goal in
                GoalRow(goal: goal,
                        onContribute: { contributeGoal = goal },
                        onDelete: { delete(goal) })
            }
        }
    }

    private func delete(_ goal: SharedGoal) {
        guard let api = appState.api else { return }
        Task {
            do {
                try await api.deleteGoal(id: goal.id)
                goals.removeAll { $0.id == goal.id }
            } catch {
                appState.handleAPIError(error)
            }
        }
    }
}

// MARK: - One goal

private struct GoalRow: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    let goal: SharedGoal
    let onContribute: () -> Void
    let onDelete: () -> Void

    @State private var confirmDelete = false
    @State private var showHistory = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.m) {
                Text(goal.emoji ?? "🎯")
                    .font(.system(.title))
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.title)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Papier.aufNacht)
                        .lineLimit(1)
                    if let targetDate = goal.targetDate, let date = SharedDates.parse(targetDate) {
                        Text(L10n.t("goals.until", ["date": ritualDateString(date)]))
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Nacht.tertiaer)
                    }
                }
                Spacer()
                if goal.completedAt != nil {
                    PillTag(text: L10n.t("goals.completedPill"), tint: Licht.glut)
                }
            }
            progressBar
            HStack {
                Text("\(formatValue(goal.total)) / \(formatValue(goal.targetValue))\(goal.unit.map { " \($0)" } ?? "")")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Papier.aufNacht)
                Spacer()
                Text("\(Int(goal.percent)) %")
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(goal.completedAt != nil ? Nacht.sekundaer : Licht.lampengold)
            }
            HStack(spacing: Space.m) {
                Button(L10n.t("goals.addProgress")) {
                    Haptics.shared.tap()
                    onContribute()
                }
                .buttonStyle(SecondaryButtonStyle(fullWidth: false))
                Spacer()
                if !goal.contributions.isEmpty {
                    Button {
                        withAnimation(Theme.Motion.settle) { showHistory.toggle() }
                    } label: {
                        Label(L10n.t("goals.contributions"),
                              systemImage: showHistory ? "chevron.up" : "clock.arrow.circlepath")
                            .font(Typo.caption)
                            .foregroundStyle(Nacht.tertiaer)
                    }
                    .buttonStyle(.plain)
                }
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Nacht.tertiaer)
                }
                .buttonStyle(.plain)
                .confirmationDialog(L10n.t("goals.deleteConfirm"),
                                    isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button(L10n.t("common.delete"), role: .destructive) { onDelete() }
                }
            }
            if showHistory {
                history
            }
        }
        .nightCard()
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Papier.nachtInnenFill)
                Capsule()
                    .fill(goal.completedAt != nil
                          ? AnyShapeStyle(Licht.lampengold)
                          : AnyShapeStyle(coupleTint.band))
                    .frame(width: max(8, geo.size.width * goal.percent / 100))
                // Milestone ticks at 25/50/75 % — reached ticks sit on the
                // band/lamplight (light ink), unreached on the dim track.
                ForEach([25, 50, 75], id: \.self) { tick in
                    Circle()
                        .fill(goal.percent >= Double(tick)
                              ? Papier.brief.opacity(0.9)
                              : Papier.aufNacht.opacity(0.4))
                        .frame(width: 5, height: 5)
                        .position(x: geo.size.width * CGFloat(tick) / 100, y: geo.size.height / 2)
                }
            }
        }
        .frame(height: LayoutMetrics.s(12))
        .animation(Theme.Motion.arrive, value: goal.percent)
    }

    private var history: some View {
        VStack(spacing: Space.s) {
            ForEach(goal.contributions.suffix(8).reversed()) { contribution in
                HStack(spacing: Space.s) {
                    Text(memberEmoji(contribution.memberId))
                        .font(.system(.subheadline))
                    Text((contribution.amount >= 0 ? "+" : "") + formatValue(contribution.amount)
                         + (goal.unit.map { " \($0)" } ?? ""))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(contribution.amount >= 0 ? Licht.lampengold : Licht.glut)
                    if let note = contribution.note, !note.isEmpty {
                        Text(note)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Nacht.sekundaer)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(L10n.relativeShort(contribution.createdAt))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Nacht.tertiaer)
                }
            }
        }
    }

    private func memberEmoji(_ memberId: String) -> String {
        appState.couple?.members.first { $0.id == memberId }?.avatar ?? "💜"
    }
}

/// "1.234,5" style value without trailing ".0" for integers.
private func formatValue(_ value: Double) -> String {
    AppFormatters.decimal(
        value,
        language: L10n.lang,
        maximumFractionDigits: value == value.rounded() ? 0 : 2
    )
}

// MARK: - Compose sheet

private struct GoalComposeSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint
    let onCreated: (SharedGoal) -> Void

    @State private var title = ""
    @State private var emoji = "🎯"
    @State private var targetText = ""
    @State private var unit = ""
    @State private var useTargetDate = false
    @State private var targetDate = Date().addingTimeInterval(90 * 86400)
    @State private var creating = false

    private static let emojis = ["🎯", "✈️", "🏝️", "🏠", "💍", "🚗", "🎓", "👶", "🐶", "💰", "🎸", "⛺️"]

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.l) {
                        TextField(L10n.t("goals.compose.titleField"), text: $title)
                            .textFieldStyle(RitualFieldStyle())
                        emojiRow
                        HStack(spacing: Space.m) {
                            TextField(L10n.t("goals.compose.target"), text: $targetText)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(RitualFieldStyle())
                            TextField(L10n.t("goals.compose.unit"), text: $unit)
                                .textFieldStyle(RitualFieldStyle())
                                .frame(width: LayoutMetrics.s(120))
                        }
                        Toggle(L10n.t("goals.compose.targetDate"), isOn: $useTargetDate)
                            .font(Typo.label)
                            .foregroundStyle(Theme.textPrimary)
                            .tint(coupleTint.blend)
                        if useTargetDate {
                            DatePicker("", selection: $targetDate, in: Date()..., displayedComponents: [.date])
                                .datePickerStyle(.graphical)
                                .tint(coupleTint.blend)
                                .colorScheme(.dark)
                                // System pickers follow the DEVICE locale,
                                // the app speaks ITS language (Amt seam,
                                // Re-Eval Runde 2 roll-out).
                                .environment(\.locale, Locale(identifier: L10n.lang))
                        }
                        Button(L10n.t("goals.create")) {
                            create()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(creating || !isValid)
                    }
                    .padding(Space.l)
                }
            }
            .navigationTitle(L10n.t("goals.compose.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                }
            }
        }
    }

    private var emojiRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                ForEach(Self.emojis, id: \.self) { candidate in
                    Button {
                        emoji = candidate
                    } label: {
                        Text(candidate)
                            .font(.system(.title2))
                            .frame(width: LayoutMetrics.s(44), height: LayoutMetrics.s(44))
                            .background(
                                Circle().fill(emoji == candidate
                                              ? coupleTint.blend.opacity(0.35)
                                              : Theme.innerFill)
                            )
                            .overlay(
                                Circle().strokeBorder(emoji == candidate ? coupleTint.blend : .clear,
                                                      lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var targetValue: Double? {
        Double(targetText.replacingOccurrences(of: ",", with: "."))
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (targetValue ?? 0) > 0
    }

    private func create() {
        guard let api = appState.api, let target = targetValue, !creating else { return }
        creating = true
        let trimmedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let goal = try await api.createGoal(
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    emoji: emoji,
                    targetValue: target,
                    unit: trimmedUnit.isEmpty ? nil : trimmedUnit,
                    targetDate: useTargetDate ? SharedDates.todayKey(targetDate) : nil)
                SoundEngine.shared.play(.pop)
                Haptics.shared.success()
                appState.showToast(L10n.t("goals.createdToast"), style: .success)
                onCreated(goal)
                dismiss()
            } catch {
                creating = false
                appState.handleAPIError(error)
            }
        }
    }
}

// MARK: - Contribute sheet

private struct GoalContributeSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let goal: SharedGoal
    let onBooked: (SharedGoal) -> Void

    @State private var amountText = ""
    @State private var note = ""
    @State private var booking = false

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                VStack(alignment: .leading, spacing: Space.l) {
                    HStack(spacing: Space.s) {
                        Text(goal.emoji ?? "🎯")
                            .font(.system(.title))
                        Text(goal.title)
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    TextField(L10n.t("goals.amountField") + (goal.unit.map { " (\($0))" } ?? ""),
                              text: $amountText)
                        .keyboardType(.numbersAndPunctuation)
                        .textFieldStyle(RitualFieldStyle())
                    TextField(L10n.t("goals.progressNote"), text: $note)
                        .textFieldStyle(RitualFieldStyle())
                    Button(L10n.t("goals.book")) {
                        book()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(booking || amount == nil || amount == 0)
                    Spacer()
                }
                .padding(Space.l)
            }
            .navigationTitle(L10n.t("goals.addProgress"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var amount: Double? {
        Double(amountText.replacingOccurrences(of: ",", with: "."))
    }

    private func book() {
        guard let api = appState.api, let amount, !booking else { return }
        booking = true
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let result = try await api.contributeToGoal(id: goal.id, amount: amount,
                                                            note: trimmedNote.isEmpty ? nil : trimmedNote)
                Haptics.shared.success()
                // My own milestone confetti fires here — ONCE: the
                // goal_updated echo of this booking is origin-gated in
                // RitualsAppState, so only the partner's phone celebrates
                // via the broadcast. Completion asks the arbiter for its
                // epic — one budget slot per completion.
                if let milestone = result.milestone {
                    if milestone >= 100 {
                        // Completion asks the arbiter for its epic slot.
                        Delight.celebrate(DelightArbiterStore.request(.goalCompleted),
                                          theme: .confetti)
                    } else {
                        // Partial milestones (25/50/75 %) glow instead of
                        // raining confetti — the app-wide Lichtschein economy
                        // (R2: the last celebrate call site off the glow path).
                        AppCue.fanfareMedium.play()
                        LichtscheinCenter.shared.fire()
                    }
                } else {
                    SoundEngine.shared.play(.pop)
                }
                onBooked(result.goal)
                dismiss()
            } catch {
                booking = false
                appState.handleAPIError(error)
            }
        }
    }
}
