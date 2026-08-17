import SwiftUI

// MARK: - Duell-Bilanz — the couple's running Wordle duel record 📊

/// Pushed from `WordleView`. Loads the duel history (per-member views, newest
/// first, anti-spoiler already applied server-side) and shows a W·U·N record
/// card, an optional play-streak chip and an expandable day-by-day list.
struct WordleRecordView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var days: [WordleDayResponse] = []
    @State private var loading = true
    @State private var expandedKeys: Set<String> = []

    private var lang: String { L10n.lang }

    private var myName: String { appState.me?.name ?? L10n.t("common.you") }

    var body: some View {
        ZStack {
            DreamyBackground()
            ScrollView {
                content
                    .padding(LayoutMetrics.s(16))
                    .padding(.bottom, LayoutMetrics.s(12))
            }
            .refreshable { await load() }
        }
        .navigationTitle(L10n.t("games.wordle.record.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if loading && days.isEmpty {
            ProgressView()
                .tint(coupleTint.blend)
                .padding(.top, LayoutMetrics.s(120))
        } else if days.isEmpty {
            EmptyStateView(systemImage: "flag.2.crossed.fill",
                           title: L10n.t("games.wordle.record.emptyTitle"),
                           subtitle: L10n.t("games.wordle.record.emptyBody"),
                           actionTitle: L10n.t("games.wordle.record.empty.action"),
                           action: {
                               Haptics.shared.tap()
                               dismiss()
                           })
                .padding(.top, LayoutMetrics.s(80))
        } else {
            VStack(spacing: LayoutMetrics.s(12)) {
                recordCard
                if playStreak >= 2 {
                    PillTag(text: L10n.t("games.wordle.record.streak",
                                         ["n": "\(playStreak)"]),
                            tint: Licht.lampengold)
                }
                dayList
            }
        }
    }

    // MARK: Loading

    private func load() async {
        guard let api = appState.api else {
            loading = false
            return
        }
        let requestedLang = lang
        if let response = try? await api.wordleHistory(limit: 30, lang: requestedLang) {
            days = response
                .filter { ($0.lang ?? requestedLang) == requestedLang }
                .sorted { $0.dateKey > $1.dateKey }
        }
        loading = false
    }

    // MARK: Record (only days where BOTH results are visible count)

    private var record: (mine: Int, ties: Int, partner: Int) {
        var mine = 0, ties = 0, partner = 0
        for day in days {
            guard let myResult = day.mine, let partnerResult = day.partner else { continue }
            switch WordleDaily.duelOutcome(mine: myResult, partner: partnerResult) {
            case .meWin: mine += 1
            case .partnerWin: partner += 1
            case .tie: ties += 1
            }
        }
        return (mine, ties, partner)
    }

    // Nacht & Lampenlicht: the duel tally sheet is chrome, not board —
    // night card, win counts in aufNacht (identity lives in the avatars),
    // the leader line glowing in glut instead of wax (wax is material on
    // nachtkarton, glut is the pinned warm accent at 5.6:1).
    private var recordCard: some View {
        let record = record
        let total = record.mine + record.ties + record.partner
        return VStack(spacing: LayoutMetrics.s(12)) {
            HStack(alignment: .top, spacing: LayoutMetrics.s(12)) {
                recordColumn(name: myName,
                             avatar: appState.me?.avatar,
                             colorHex: appState.me?.color,
                             wins: record.mine,
                             ink: Papier.aufNacht)
                VStack(spacing: 4) {
                    Text("\(record.ties)")
                        .font(.system(.title2, design: .rounded).weight(.heavy).monospacedDigit())
                        .foregroundStyle(Nacht.sekundaer)
                        .padding(.top, LayoutMetrics.s(12))
                    Text(L10n.t("games.wordle.record.ties"))
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(Nacht.tertiaer)
                }
                recordColumn(name: appState.partnerName,
                             avatar: appState.partner?.avatar,
                             colorHex: appState.partner?.color,
                             wins: record.partner,
                             ink: Papier.aufNacht)
            }
            if total > 0 {
                Text(leaderLine(record))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Licht.glut)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.t("games.wordle.record.subtitle", ["n": "\(total)"]))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
            }
        }
        .frame(maxWidth: .infinity)
        .nightCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("games.wordle.record.title"))
        .accessibilityValue(L10n.t("games.wordle.record.a11y.value",
                                   ["mine": "\(record.mine)",
                                    "ties": "\(record.ties)",
                                    "name": appState.partnerName,
                                    "partner": "\(record.partner)"])
                            + (total > 0 ? ". " + leaderLine(record) : ""))
    }

    private func recordColumn(name: String, avatar: String?, colorHex: String?,
                              wins: Int, ink: Color) -> some View {
        VStack(spacing: 6) {
            EmojiAvatarView(emoji: avatar, colorHex: colorHex, size: LayoutMetrics.s(40))
            Text(name)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
                .lineLimit(1)
            Text("\(wins)")
                .font(.system(.title2, design: .rounded).weight(.heavy).monospacedDigit())
                .foregroundStyle(ink)
        }
        .frame(maxWidth: .infinity)
    }

    private func leaderLine(_ record: (mine: Int, ties: Int, partner: Int)) -> String {
        if record.mine > record.partner {
            return L10n.t("games.wordle.record.leaderMe")
        }
        if record.partner > record.mine {
            return L10n.t("games.wordle.record.leaderPartner",
                          ["name": appState.partnerName])
        }
        return L10n.t("games.wordle.record.leaderTie")
    }

    // MARK: Streak (consecutive calendar days from the newest where I finished)

    private var playStreak: Int {
        let calendar = SharedDates.calendar
        let played = Set(days.filter { $0.mine != nil }.map { $0.dateKey })
        var expected = calendar.startOfDay(for: Date())
        // The streak is still alive when today isn't played yet but
        // yesterday is — start walking from yesterday in that case.
        if !played.contains(SharedDates.todayKey(expected)),
           let yesterday = calendar.date(byAdding: .day, value: -1, to: expected) {
            expected = yesterday
        }
        var streak = 0
        while played.contains(SharedDates.todayKey(expected)) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: expected) else {
                break
            }
            expected = previous
        }
        return streak
    }

    // MARK: Day list

    private var dayList: some View {
        LazyVStack(spacing: LayoutMetrics.s(8)) {
            ForEach(days, id: \.dateKey) { day in
                dayRow(day)
            }
        }
    }

    private func dayRow(_ day: WordleDayResponse) -> some View {
        let expandable = day.mine != nil && day.partner != nil
        return VStack(spacing: LayoutMetrics.s(10)) {
            Button {
                toggle(day.dateKey)
            } label: {
                dayHeader(day, expandable: expandable)
            }
            .buttonStyle(.plain)
            .disabled(!expandable)
            .accessibilityLabel(prettyDate(day.dateKey))
            .accessibilityValue(dayA11yValue(day))
            if expandedKeys.contains(day.dateKey),
               let mine = day.mine, let partner = day.partner {
                expandedGrids(mine: mine, partner: partner)
            }
        }
        .nightCard(padding: .compact, grain: false)
    }

    private func dayHeader(_ day: WordleDayResponse, expandable: Bool) -> some View {
        HStack(spacing: LayoutMetrics.s(10)) {
            Text(prettyDate(day.dateKey))
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(Papier.aufNacht)
                .frame(maxWidth: .infinity, alignment: .leading)
            scoreText(day.mine)
            Text(":")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Nacht.tertiaer)
            scoreText(day.partner)
            Text(outcomeIcon(day))
                .font(Typo.body)
                .frame(width: 24)
            Image(systemName: "chevron.down")
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(Nacht.tertiaer)
                .rotationEffect(.degrees(expandedKeys.contains(day.dateKey) ? 180 : 0))
                .opacity(expandable ? 1 : 0)
        }
        .contentShape(Rectangle())
    }

    private func scoreText(_ result: WordleResult?) -> some View {
        let text: String
        let color: Color
        if let result {
            text = result.win ? "\(result.rows)/6" : "✗"
            color = result.win ? Licht.lampengold : Nacht.tertiaer
        } else {
            text = "—"
            color = Nacht.tertiaer
        }
        return Text(text)
            .font(.system(.footnote, design: .rounded).weight(.heavy))
            .monospacedDigit()
            .foregroundStyle(color)
            .frame(width: 34)
    }

    /// 🏆 I won · 💪 partner won · 💞 tie · 👀 partner played but stays
    /// hidden because I didn't — blank when only my result exists.
    private func outcomeIcon(_ day: WordleDayResponse) -> String {
        if let mine = day.mine, let partner = day.partner {
            switch WordleDaily.duelOutcome(mine: mine, partner: partner) {
            case .meWin: return "🏆"
            case .partnerWin: return "💪"
            case .tie: return "💞"
            }
        }
        if day.mine == nil && day.partnerFinished { return "👀" }
        return " "
    }

    /// Spoken summary of a day row — scores plus outcome, so the emoji
    /// column stays purely decorative for VoiceOver.
    private func dayA11yValue(_ day: WordleDayResponse) -> String {
        let scores = L10n.t("games.a11y.scoreValue",
                            ["mine": scoreSpoken(day.mine),
                             "name": appState.partnerName,
                             "theirs": scoreSpoken(day.partner)])
        let outcome: String
        if let mine = day.mine, let partner = day.partner {
            switch WordleDaily.duelOutcome(mine: mine, partner: partner) {
            case .meWin: outcome = L10n.t("games.wordle.record.a11y.win")
            case .partnerWin: outcome = L10n.t("games.wordle.record.a11y.partnerWin",
                                               ["name": appState.partnerName])
            case .tie: outcome = L10n.t("games.wordle.record.a11y.tie")
            }
        } else {
            outcome = L10n.t("games.wordle.record.a11y.pending")
        }
        return scores + " — " + outcome
    }

    private func scoreSpoken(_ result: WordleResult?) -> String {
        guard let result else { return L10n.t("games.wordle.record.a11y.pending") }
        return result.win ? "\(result.rows)/6" : L10n.t("games.wordle.record.a11y.noSolve")
    }

    private func expandedGrids(mine: WordleResult, partner: WordleResult) -> some View {
        HStack(alignment: .top, spacing: LayoutMetrics.s(14)) {
            gridColumn(name: myName, result: mine)
            Rectangle()
                .fill(Nacht.naht)
                .frame(width: 1)
            gridColumn(name: appState.partnerName, result: partner)
        }
    }

    private func gridColumn(name: String, result: WordleResult) -> some View {
        VStack(spacing: 6) {
            Text(name)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
                .lineLimit(1)
            VStack(spacing: 2) {
                ForEach(Array(result.grid.split(separator: "\n").enumerated()),
                        id: \.offset) { _, line in
                    Text(String(line))
                        .font(Typo.caption)
                        .kerning(1)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(scoreSpoken(result))
    }

    private func toggle(_ dateKey: String) {
        Haptics.shared.tap()
        withAnimation(reduceMotion ? nil : Theme.Motion.settle) {
            if expandedKeys.contains(dateKey) {
                expandedKeys.remove(dateKey)
            } else {
                expandedKeys.insert(dateKey)
            }
        }
    }

    private func prettyDate(_ dateKey: String) -> String {
        guard let date = SharedDates.parse(dateKey) else { return dateKey }
        return AppFormatters.date(date, language: L10n.lang)
    }
}
