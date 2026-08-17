import SwiftUI
import Combine

// Turnier-Modus & Saison-Trophäen 🏆 — monthly seasons across ALL games.
// The server's complete season ledger (games + bilingual Wordle) feeds the
// same deterministic tables (Content/TournamentLogic.swift). A closed
// season triggers a one-time ceremony; past seasons live on the shelf.
struct TournamentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint

    @State private var aggregateMatches: [SeasonAggregateMatch] = []
    @State private var loading = true
    @State private var requestFailed = false
    @State private var ceremonyTable: SeasonTable?

    var body: some View {
        ZStack {
            DreamyBackground()
            ScrollView {
                content
                    .padding(LayoutMetrics.s(16))
                    .padding(.bottom, LayoutMetrics.s(12))
            }
            .refreshable { await load() }
            if let table = ceremonyTable {
                ceremonyOverlay(table)
            }
        }
        .navigationTitle(L10n.t("games.season.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent, event.type == .gameEnded else { return }
            Task { await load() }
        }
    }

    // MARK: Data

    private func load() async {
        guard let api = appState.api else {
            requestFailed = true
            loading = false
            return
        }
        loading = true
        requestFailed = false
        do {
            let aggregate = try await api.seasonAggregate()
            aggregateMatches = aggregate.matches
        } catch {
            requestFailed = true
        }
        loading = false
        checkCeremony()
    }

    private var phase: SurfacePhase {
        SurfaceState.resolve(
            loading: loading,
            hasContent: !aggregateMatches.isEmpty,
            connected: appState.socket.state == .connected,
            requestFailed: requestFailed
        )
    }

    /// The server normalizes competitive, cooperative, and Wordle outcomes.
    private var matches: [SeasonMatch] {
        aggregateMatches.compactMap { match in
            guard let myId = appState.memberId,
                  let mine = match.scores[myId],
                  let theirs = match.scores.first(where: { $0.key != myId })?.value else {
                return nil
            }
            return SeasonMatch(type: match.type,
                               monthKey: match.monthKey,
                               mine: mine, theirs: theirs)
        }
    }

    private var currentMonth: String { Tournament.monthKey(of: SharedDates.todayKey()) }

    private var currentTable: SeasonTable {
        Tournament.table(matches: matches, month: currentMonth)
    }

    /// Closed seasons (past months with games), newest first.
    private var pastTables: [SeasonTable] {
        Tournament.tables(matches: matches).filter {
            $0.monthKey < currentMonth && $0.games > 0
        }
    }

    // MARK: Ceremony (one-time per closed season)

    private func ceremonyKey(_ month: String) -> String {
        "season.ceremony.\(appState.couple?.id ?? "?").\(month)"
    }

    private func checkCeremony() {
        guard let latest = pastTables.first,
              !UserDefaults.standard.bool(forKey: ceremonyKey(latest.monthKey)) else { return }
        withAnimation(Theme.Motion.playful) {
            ceremonyTable = latest
        }
        // A closed season IS the season milestone — one tiered ceremony
        // instead of the old double audio (raw win sound + epic fanfare).
        GameEndCelebration.seasonMilestone(theme: .confetti)
    }

    private func dismissCeremony() {
        if let table = ceremonyTable {
            UserDefaults.standard.set(true, forKey: ceremonyKey(table.monthKey))
        }
        withAnimation(Theme.Motion.settle) {
            ceremonyTable = nil
        }
    }

    private func ceremonyOverlay(_ table: SeasonTable) -> some View {
        VStack(spacing: LayoutMetrics.s(14)) {
            Image(systemName: "trophy.fill")
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.gold)
                .accessibilityHidden(true)
            Text(L10n.t("games.season.ceremony.title", ["month": monthName(table.monthKey)]))
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Text(leaderLine(table))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.gold)
                .multilineTextAlignment(.center)
            VStack(spacing: LayoutMetrics.s(8)) {
                ForEach(Tournament.trophies(for: table)) { trophy in
                    trophyRow(trophy, table: table)
                }
            }
            Button {
                dismissCeremony()
            } label: {
                Text(L10n.t("games.season.ceremony.dismiss"))
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(LayoutMetrics.s(24))
        .glass(.chrome, in: RoundedRectangle(cornerRadius: Radius.pane, style: .continuous))
        .padding(LayoutMetrics.s(24))
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView()
                .tint(coupleTint.blend)
                .padding(.top, LayoutMetrics.s(120))
        case .offline:
            StateNoticeView(
                kind: .offline,
                title: L10n.t("state.offline.title"),
                message: L10n.t("state.offline.body"),
                retry: { Task { await load() } }
            )
            .padding(.top, LayoutMetrics.s(48))
        case .failed:
            StateNoticeView(
                kind: .failed,
                title: L10n.t("state.failed.title"),
                message: L10n.t("state.failed.body"),
                retry: { Task { await load() } }
            )
            .padding(.top, LayoutMetrics.s(48))
        case .empty, .content:
            VStack(alignment: .leading, spacing: LayoutMetrics.s(14)) {
                seasonCard(currentTable, isCurrent: true)
                SectionHeader(title: L10n.t("games.season.shelf"))
                if pastTables.isEmpty {
                    Text(L10n.t("games.season.shelf.empty"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Nacht.tertiaer)
                        .frame(maxWidth: .infinity)
                        .nightCard(grain: false)
                } else {
                    ForEach(pastTables, id: \.monthKey) { table in
                        seasonCard(table, isCurrent: false)
                    }
                }
            }
        }
    }

    private func seasonCard(_ table: SeasonTable, isCurrent: Bool) -> some View {
        VStack(spacing: LayoutMetrics.s(12)) {
            HStack(spacing: LayoutMetrics.s(8)) {
                Image(systemName: isCurrent ? "flame.fill" : "calendar")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(isCurrent ? Licht.glut : Nacht.sekundaer)
                    .accessibilityHidden(true)
                Text(isCurrent
                     ? L10n.t("games.season.current", ["month": monthName(table.monthKey)])
                     : monthName(table.monthKey))
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                Spacer(minLength: 0)
                if isCurrent {
                    PillTag(text: L10n.t("games.season.daysLeft", ["n": "\(daysLeftInMonth)"]),
                            tint: Licht.glut)
                }
            }
            if table.games == 0 {
                Text(L10n.t("games.season.empty"))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, LayoutMetrics.s(8))
            } else {
                pointsRow(table)
                statsRow(table)
                if !isCurrent {
                    trophyStrip(table)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .nightCard()
    }

    private func pointsRow(_ table: SeasonTable) -> some View {
        HStack(spacing: LayoutMetrics.s(16)) {
            pointsColumn(name: appState.me?.name ?? L10n.t("common.you"),
                         avatar: appState.me?.avatar, colorHex: appState.me?.color,
                         points: table.myPoints,
                         highlight: table.leader == .me)
            Text(":")
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .foregroundStyle(Nacht.tertiaer)
            pointsColumn(name: appState.partnerName,
                         avatar: appState.partner?.avatar, colorHex: appState.partner?.color,
                         points: table.theirPoints,
                         highlight: table.leader == .partner)
        }
        .frame(maxWidth: .infinity)
    }

    private func pointsColumn(name: String, avatar: String?, colorHex: String?,
                              points: Int, highlight: Bool) -> some View {
        VStack(spacing: 4) {
            EmojiAvatarView(emoji: avatar, colorHex: colorHex, size: LayoutMetrics.s(36))
            Text(name)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
                .lineLimit(1)
            Text("\(points)")
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(highlight ? Licht.glut : Papier.aufNacht)
        }
        .frame(maxWidth: .infinity)
    }

    private func statsRow(_ table: SeasonTable) -> some View {
        HStack(spacing: LayoutMetrics.s(8)) {
            PillTag(text: L10n.t("games.season.games", ["n": "\(table.games)"]))
            PillTag(text: L10n.t("games.season.wins",
                                 ["a": "\(table.myWins)", "b": "\(table.theirWins)"]),
                    tint: coupleTint.blend)
            PillTag(text: L10n.t("games.season.ties", ["n": "\(table.ties)"]),
                    tint: Licht.glut)
            PillTag(text: L10n.t("games.season.types", ["n": "\(table.types.count)"]))
        }
        .frame(maxWidth: .infinity)
    }

    private func trophyStrip(_ table: SeasonTable) -> some View {
        VStack(spacing: LayoutMetrics.s(6)) {
            ForEach(Tournament.trophies(for: table)) { trophy in
                trophyRow(trophy, table: table)
            }
        }
    }

    /// One trophy line — night shelf cards and the glass ceremony overlay
    /// are both dark now, so a single night-ink rendering serves both.
    private func trophyRow(_ trophy: SeasonTrophy, table: SeasonTable) -> some View {
        HStack(spacing: LayoutMetrics.s(10)) {
            Text(trophyEmoji(trophy.kind))
                .font(.system(.title3, design: .rounded))
            Text(trophyLabel(trophy.kind, table: table))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if trophy.kind.isCoop {
                Image(systemName: "heart.circle.fill")
                    .foregroundStyle(Licht.lampengold)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, LayoutMetrics.s(12))
        .padding(.vertical, LayoutMetrics.s(8))
        .background(
            RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                .fill(Licht.lampengold.opacity(0.12))
        )
    }

    private func trophyEmoji(_ kind: SeasonTrophyKind) -> String {
        switch kind {
        case .goldMe, .goldPartner: return "🏆"
        case .shared: return "🤝"
        case .marathon: return "🎖️"
        case .explorers: return "🧭"
        }
    }

    private func trophyLabel(_ kind: SeasonTrophyKind, table: SeasonTable) -> String {
        switch kind {
        case .goldMe:
            return L10n.t("games.season.trophy.gold",
                          ["name": appState.me?.name ?? L10n.t("common.you")])
        case .goldPartner:
            return L10n.t("games.season.trophy.gold", ["name": appState.partnerName])
        case .shared:
            return L10n.t("games.season.trophy.shared")
        case .marathon:
            return L10n.t("games.season.trophy.marathon", ["n": "\(table.games)"])
        case .explorers:
            return L10n.t("games.season.trophy.explorers", ["n": "\(table.types.count)"])
        }
    }

    private func leaderLine(_ table: SeasonTable) -> String {
        switch table.leader {
        case .me:
            return L10n.t("games.season.leader.me",
                          ["points": "\(table.myPoints)", "theirs": "\(table.theirPoints)"])
        case .partner:
            return L10n.t("games.season.leader.partner",
                          ["name": appState.partnerName,
                           "points": "\(table.theirPoints)", "mine": "\(table.myPoints)"])
        case .tie:
            return L10n.t("games.season.leader.tie", ["points": "\(table.myPoints)"])
        }
    }

    // MARK: Date helpers

    private var daysLeftInMonth: Int {
        let calendar = SharedDates.calendar
        let now = Date()
        guard let range = calendar.range(of: .day, in: .month, for: now) else { return 0 }
        let day = calendar.component(.day, from: now)
        return Swift.max(0, range.count - day)
    }

    /// "2026-08" → localized "August 2026".
    private func monthName(_ monthKey: String) -> String {
        let parts = monthKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return monthKey }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = 1
        guard let date = SharedDates.calendar.date(from: components) else { return monthKey }
        return AppFormatters.monthYear(date, language: L10n.lang)
    }
}
