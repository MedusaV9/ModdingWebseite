import SwiftUI
import Combine

// MARK: - Navigation destinations

// CaseIterable so the Kartenschrank coverage law is checkable: every case
// lies in exactly one Fach (`KartenschrankRules`, pinned by LogicTests and
// asserted against this very enum in DEBUG builds below).
enum GameDestination: String, Hashable, Identifiable, CaseIterable {
    case wordle, quiz, thisorthat, wouldyourather, truthordare, questions36, emojiriddle, dateideas
    case connectfour, photomemory, quizduel   // Realtime games
    case battleship, pictionary, kniffel, movieroulette, stadtlandfluss, twotruths
    case dailyquests   // Daily activity
    case wordchain, hangman, bingo   // Games Wave II
    case wordleduo, rps, story   // Word & party trio (server-manifest parity)
    case dame, reversi, kaesekaestchen, gomoku, mancala, memoryduo   // W8C board & duel games
    case tutorials   // interactive intros for all 19 session games
    case season   // Monthly tournament & trophy shelf
    case replay   // Replay & spectator mode
    case record   // scoreboard of past games
    var id: String { rawValue }
}

// MARK: - Play hub (the "Play" tab)

struct PlayHubView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Parallel sessions — one engine per game type, owned here.
    @State private var coordinator = GamesCoordinator()
    @State private var path: [GameDestination] = []
    @State private var wordleDoneToday = false
    @State private var wordleDuelWon: Bool?
    /// Finished sessions feeding the hero heuristic, "recently played"
    /// and the series nudge — CURATION only (same `GET /api/games` page
    /// the scoreboard reads; it stops at 50, so no register number may
    /// ever come from it — those read `gamesStats` below).
    @State private var pastGames: [GameSession] = []
    /// Whole-history aggregate for the honest register numbers (Spielbuch
    /// rows + Fach page numbers): `GET /api/games/stats` counts the FULL
    /// stored history server-side, so the biography stays true past game
    /// 51. Nil on pre-stats servers → list-derived fallback carries on.
    @State private var gamesStats: GamesStatsResponse?
    /// Season ledger for the compact standings row (same
    /// `GET /api/games/season` aggregate the tournament screen reads).
    @State private var seasonAggregate: [SeasonAggregateMatch] = []
    /// Context stamp for the three loads above (re-eval 2, Befund 10):
    /// bumped on every server-/couple switch, captured by each load before
    /// its await and compared after — a late response from the OLD couple
    /// context can never write stale numbers into the new one.
    @State private var ladeKontext = 0
    // Accordion (Eval S2 „Fächer-Erststart begraben"): all three drawer
    // heads stay visible, at most ONE drawer is open, and this remembers
    // the last open one. First start: empty → every drawer collapsed, so
    // „Am Tisch" is one tap away instead of buried under 16 Fernpartien.
    // (Replaces the three pre-N3 per-drawer collapse keys.)
    @AppStorage("sooodreamy.hub.openFach") private var offenesFach = ""

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                // Redesign wave 1 (REDESIGN.md §2.2): the living room —
                // the game table breathes with the same Atemglühen as
                // the mailbox.
                AnimatedBackground()
                ScrollView {
                    // The four zones of the games table, in the BINDING
                    // order of ENTSCHEID §4.3: (1) Aushang — season line +
                    // today's sheet, (2) aufliegende Blätter — the dealt
                    // hands, (3) Kartenschrank — three drawers, (4)
                    // Spielbuch — the register at the bottom.
                    VStack(spacing: LayoutMetrics.s(16)) {
                        header
                        // (1) Aushang
                        seasonStatusRow
                        heroCard
                        seriesMomentumCard
                        recentlyPlayedRow
                        categoryTab(title: L10n.t("games.group.daily"))
                        wordleCard
                        dailyQuestsCard
                        // (2) Aufliegende Blätter
                        aufliegendeBlaetter
                        // (3) Kartenschrank (Adoption A1 on the headers)
                        fachSection(.fernpartien)
                        fachSection(.amTisch)
                        fachSection(.festeFragen)
                        // (4) Spielbuch (same A1 register anatomy)
                        categoryTab(title: L10n.t("games.spielbuch.title"))
                        spielbuchZeilen
                    }
                    .padding(LayoutMetrics.s(16))
                    .contentColumn(.hub)
                }
                // Resting clearance above the bottom chrome: no index card
                // (or its tilt overhang) may touch the accessory line at
                // rest — the refraction band mirrors card text otherwise.
                .contentMargins(.bottom, LayoutMetrics.restingBottomClearance,
                                for: .scrollContent)
                // Game cards run softly under the floating dock instead of
                // cutting off hard (soft over the aurora, wave-2 decision).
                .scrollEdgeEffectStyle(.soft, for: .bottom)
                // Eval S3 „Soft-Fade überm Accessory": card typography used
                // to mirror through the refraction band right above the
                // dock. A quiet fade zone settles the last scroll points
                // into the room's own ground (token colors, no material).
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [Papier.zimmerUnten.opacity(0),
                                 Papier.zimmerUnten.opacity(0.85)],
                        startPoint: .top, endPoint: .bottom)
                        .frame(height: LayoutMetrics.s(32))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: GameDestination.self) { destination in
                gameView(for: destination)
            }
        }
        // FullRelease N2-C: the ONE Lichtschein host above every game
        // screen — match celebrations on delight levels 1–2 bloom here
        // instead of the full-screen confetti overlay (epic keeps its
        // particles, see GameEndCelebration).
        // R1-D mounted LichtscheinHost app-wide in RootView — a second local
        // host here would bloom every game glow twice.
        .task {
            // The cabinet coverage law, asserted against the live enum:
            // every GameDestination lies in EXACTLY one Fach. Frequency-
            // counted via the SAME `decktGenauEinmal` rule the LogicTests
            // pin on Linux — a doubled shelf entry breaks the DEBUG build
            // exactly like the test, not silently past set equality.
            assert(KartenschrankRules.decktGenauEinmal(
                       Set(GameDestination.allCases.map(\.rawValue))),
                   "Kartenschrank mapping must cover every GameDestination exactly once")
            coordinator.onError = { [weak appState] error in
                appState?.handleAPIError(error)
            }
            refreshWordleDone()
            await coordinator.refresh(api: appState.api)
            await loadPastGames()
            await loadStats()
            await loadSeason()
        }
        .onChange(of: path) { _, newPath in
            // Refresh the daily-card checkmark when coming back from the game.
            if newPath.isEmpty {
                refreshWordleDone()
            }
        }
        .onChange(of: appState.couple?.id) {
            // Pairing / couple switch changes the daily word and duel state
            // — and the whole biography: stale numbers of the previous
            // couple must never survive into the new context (Befund 10).
            refreshWordleDone()
            clearCoupleContext()
            Task { await reloadCoupleContext() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent else { return }
            receive(event)
        }
        .onChange(of: appState.servers.activeProfileID) {
            // Switching servers switches the whole couple context.
            coordinator.reset()
            path = []
            clearCoupleContext()
            Task {
                await coordinator.refresh(api: appState.api)
                await reloadCoupleContext()
            }
        }
    }

    /// Empties everything the previous couple context loaded (Befund 10):
    /// history, register aggregate and season ledger — and bumps the
    /// context stamp so responses still in flight are discarded on
    /// arrival instead of resurrecting the old numbers.
    private func clearCoupleContext() {
        ladeKontext += 1
        pastGames = []
        gamesStats = nil
        seasonAggregate = []
    }

    private func reloadCoupleContext() async {
        await loadPastGames()
        await loadStats()
        await loadSeason()
    }

    // MARK: Event handling

    private func receive(_ event: ServerEvent) {
        if event.type == .wordleResult {
            if let response = event.decode(WordleDayResponse.self) {
                applyWordleDuel(response)
            }
            return
        }
        if event.type == .gameEnded {
            // A finished match changes "recently played", the hero pick,
            // the register numbers, the season standings and the
            // running-series nudge.
            Task {
                await loadPastGames()
                await loadStats()
                await loadSeason()
            }
        }
        let knownIds = Set(coordinator.openSessions.map(\.id))
        coordinator.handle(event)
        // Little chime when a fresh invitation from the partner lands.
        guard event.type == .gameCreated,
              let session = coordinator.openSessions.first,
              !knownIds.contains(session.id),
              session.state == "lobby",
              session.createdBy != appState.memberId else { return }
        SoundEngine.shared.play(.chime)
        Haptics.shared.tap()
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Fix4 Befund 6: at AX sizes the tools leave the title row —
            // squeezed beside the grown brand title they forced the
            // hyphen break „Spiel-tisch". The title gets the full width;
            // question mark + dice wait on their own line below.
            if dynamicTypeSize.isAccessibilitySize {
                Text(L10n.t("games.title"))
                    .brandTitle()
                HStack(spacing: Space.m) {
                    HandbookButton(anchor: "play")
                    Image(systemName: "dice.fill")
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(coupleTint.blend)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }
            } else {
                HStack {
                    Text(L10n.t("games.title"))
                        .brandTitle()
                    Spacer()
                    // FullRelease N1-A: help moved from the dock into the
                    // screen headers.
                    HandbookButton(anchor: "play")
                    // SF Symbol instead of the 🎲-as-icon charter anti-example.
                    Image(systemName: "dice.fill")
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(coupleTint.blend)
                        .accessibilityHidden(true)
                }
            }
            Text(L10n.t("games.subtitle"))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
    }

    // MARK: Zone 2 — Aufliegende Blätter (open games as dealt hands)

    /// All open sessions — types this build cannot render get an honest
    /// fallback row (28#21) instead of silently occupying open-game slots.
    /// Whoever is to move sees their hand first (POSTAMT §3.3) — a stable
    /// partition, never a reshuffle of the server order.
    private var bannerSessions: [GameSession] {
        let sessions = coordinator.openSessions
        let mine = sessions.filter { coordinator.awaitingMe($0, myId: appState.memberId) }
        return mine + sessions.filter { !coordinator.awaitingMe($0, myId: appState.memberId) }
    }

    /// The dealt hands: each open round lies as a Blatt on the table with
    /// the seeded 2° fan (the sanctioned damped grid tilt — and the ONE
    /// rotation of this screen, collection budget ≤ 3, so later Blätter
    /// lie straight). Zug-Badge stays the native pill in the row.
    @ViewBuilder
    private var aufliegendeBlaetter: some View {
        let sessions = bannerSessions
        if !sessions.isEmpty {
            VStack(spacing: LayoutMetrics.s(10)) {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                    if index < PaperRules.rotationBudgetPerCollection {
                        sessionRow(session)
                            .paperTilt(seed: GamesPaperSeed.seed("blatt.\(session.id)"),
                                       grid: true)
                    } else {
                        sessionRow(session)
                    }
                }
            }
        } else {
            // Redesign wave 1 (REDESIGN.md §2.2): 0 open rounds used to
            // make this zone vanish wordlessly — the free table now says
            // so and hands over the door: the chip opens the „Am Tisch"
            // drawer of the cabinet right below.
            DSEmptyState(
                systemImage: "rectangle.portrait.on.rectangle.portrait.angled",
                title: L10n.t("games.tischfrei.titel"),
                subtitle: L10n.t("games.tischfrei.text"),
                actionTitle: L10n.t("games.tischfrei.cta"),
                actionIcon: "sparkles"
            ) {
                Haptics.shared.tap()
                withAnimation(Theme.Motion.settle) {
                    offenesFach = KartenschrankFach.amTisch.rawValue
                }
            }
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: GameSession) -> some View {
        if let kind = session.kind, let destination = destination(for: kind) {
            let awaiting = coordinator.awaitingMe(session, myId: appState.memberId)
            let invited = session.state == "lobby" && session.createdBy != appState.memberId
            HStack(spacing: LayoutMetrics.s(12)) {
                GameKindGlyph(kind: kind, size: 30, tint: Licht.lampengold)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(Self.gameTitle(for: kind))
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(Papier.aufNacht)
                            // Fix4 Befund 3 (Leisten-Muster): AX sizes
                            // wrap instead of ellipsing.
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        if awaiting {
                            // "Your turn" glows in the ember — the night
                            // sibling of the stamp-pad red (Nacht-Regel).
                            PillTag(text: L10n.t("games.turn.badge"), tint: Licht.glut)
                        }
                    }
                    Text(sessionSubtitle(session, invited: invited))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Nacht.sekundaer)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button {
                    if invited {
                        joinAndOpen(session, destination: destination)
                    } else {
                        path.append(destination)
                    }
                } label: {
                    Text(L10n.t(invited ? "games.invite.join" : "games.continue.button"))
                        .font(.system(.footnote, design: .rounded).weight(.bold))
                        .padding(.horizontal, LayoutMetrics.s(14))
                        .padding(.vertical, LayoutMetrics.s(8))
                        .background(
                            // An invitation from the partner glows in the
                            // couple's shared color (EVAL P1-2); the quiet
                            // state is the sanctioned night inner fill.
                            Capsule().fill(invited || awaiting
                                           ? AnyShapeStyle(coupleTint.blend)
                                           : AnyShapeStyle(Papier.nachtInnenFill))
                        )
                        .overlay {
                            if !(invited || awaiting) {
                                Capsule().strokeBorder(Nacht.naht,
                                                       lineWidth: Theme.hairlineWidth)
                            }
                        }
                        // Computed ink on the blend pill — hard white fails
                        // on light couple colors (mint/gold/sky, round 3).
                        .foregroundStyle(invited || awaiting ? coupleTint.onBlend : Papier.aufNacht)
                }
                // Redesign wave 1: the most-tapped control of the hub
                // answers with the shared press response.
                .buttonStyle(DSPressableStyle())
                .disabled(coordinator.engine(for: kind).busy)
            }
            .nightCard()
        } else {
            unknownSessionRow(session)
        }
    }

    /// Honest fallback for session types this build cannot render (28#21):
    /// the session is named instead of silently filtered, and a partner
    /// invitation can at least be declined so the open-game slot frees up.
    private func unknownSessionRow(_ session: GameSession) -> some View {
        let invited = session.state == "lobby" && session.createdBy != appState.memberId
        return HStack(spacing: LayoutMetrics.s(12)) {
            Image(systemName: "questionmark.app.dashed")
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.t("games.unknown.title", ["type": session.type]))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                Text(L10n.t("games.unknown.body"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if invited {
                Button {
                    declineUnknownSession(session)
                } label: {
                    Text(L10n.t("games.invite.decline"))
                        .font(.system(.footnote, design: .rounded).weight(.bold))
                        .padding(.horizontal, LayoutMetrics.s(14))
                        .padding(.vertical, LayoutMetrics.s(8))
                        .background(Capsule().fill(Papier.nachtInnenFill))
                        .overlay(Capsule().stroke(Nacht.naht, lineWidth: Theme.hairlineWidth))
                        .foregroundStyle(Papier.aufNacht)
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
            }
        }
        .nightCard()
    }

    /// Declines an invitation of a type without a UI — no engine exists for
    /// it, so the end call goes straight through the API.
    private func declineUnknownSession(_ session: GameSession) {
        guard let api = appState.api else { return }
        Task {
            do {
                _ = try await api.endGame(id: session.id)
                coordinator.openSessions.removeAll { $0.id == session.id }
            } catch {
                appState.handleAPIError(error)
            }
        }
    }

    private func sessionSubtitle(_ session: GameSession, invited: Bool) -> String {
        if invited {
            return L10n.t("games.invite.short", ["name": appState.partnerName])
        }
        if session.state == "lobby" {
            return appState.partner?.online == true
                ? L10n.t("games.invite.waitingBody", ["name": appState.partnerName])
                : L10n.t("games.invite.offline", ["name": appState.partnerName])
        }
        return coordinator.awaitingMe(session, myId: appState.memberId)
            ? L10n.t("games.turn.yours")
            : L10n.t("games.turn.partner", ["name": appState.partnerName])
    }

    private func joinAndOpen(_ session: GameSession, destination: GameDestination) {
        guard let kind = session.kind else { return }
        let engine = coordinator.engine(for: kind)
        Task {
            if engine.session?.id != session.id {
                engine.adopt(session)
            }
            if await engine.join(api: appState.api) {
                SoundEngine.shared.play(.pop)
                Haptics.shared.success()
                path.append(destination)
            }
        }
    }

    // MARK: Curation — hero recommendation + recently played

    /// PLAYED sessions, newest first (pre-v1.6 servers 404 → empty).
    /// CURATION input only — the register numbers read `gamesStats`.
    /// Filtered through the ONE shared `isPlayedGame` rule (Befund 8, the
    /// server twin lives in game-rules.js): cancelled/declined lobbies
    /// never surface as "Zuletzt gespielt" or feed the hero heuristic.
    private func loadPastGames() async {
        guard let api = appState.api else { return }
        let kontext = ladeKontext
        do {
            let sessions = try await api.games(limit: 50)
            guard kontext == ladeKontext else { return } // stale context
            pastGames = sessions.filter {
                PlayHubCuration.isPlayedGame(state: $0.state,
                                             moveCount: $0.moves.count,
                                             result: $0.result)
            }
            .sorted { $0.createdAt > $1.createdAt }
        } catch {
            // Curation is a progressive enhancement: without a history
            // list the hero/recent rows simply stay hidden — the catalog
            // below is complete either way. No banner for an old server.
        }
    }

    /// Whole-history aggregate for Spielbuch + Fach registers — counted
    /// server-side over the FULL store, so the numbers stay honest past
    /// game 51 (the list above pages at 50). Pre-stats servers 404 → the
    /// list-derived fallback keeps carrying the rows, same progressive-
    /// enhancement stance as the curation loads.
    private func loadStats() async {
        guard let api = appState.api else { return }
        let kontext = ladeKontext
        do {
            let stats = try await api.gamesStats()
            guard kontext == ladeKontext else { return } // stale context
            gamesStats = stats
        } catch {
            // Old server: keep whatever aggregate we last saw (or nil).
        }
    }

    /// Season ledger for the standings row — same canonical aggregate the
    /// tournament screen reads, no new endpoint.
    private func loadSeason() async {
        guard let api = appState.api else { return }
        let kontext = ladeKontext
        do {
            let matches = try await api.seasonAggregate().matches
            guard kontext == ladeKontext else { return } // stale context
            seasonAggregate = matches
        } catch {
            // Progressive enhancement like the curation rows: without a
            // ledger the hub simply shows no standings line.
        }
    }

    // MARK: Season standings + running-series nudge (FXC-3, S3)

    /// This month's season table, derived exactly like TournamentView —
    /// nil while the season has no games yet (no empty 0:0 row).
    private var currentSeasonTable: SeasonTable? {
        guard let myId = appState.memberId else { return nil }
        let matches: [SeasonMatch] = seasonAggregate.compactMap { match in
            guard let mine = match.scores[myId],
                  let theirs = match.scores.first(where: { $0.key != myId })?.value else {
                return nil
            }
            return SeasonMatch(type: match.type, monthKey: match.monthKey,
                               mine: mine, theirs: theirs)
        }
        let table = Tournament.table(matches: matches,
                                     month: Tournament.monthKey(of: SharedDates.todayKey()))
        return table.games > 0 ? table : nil
    }

    /// Compact standings line at the top of the hub — one tap into the
    /// full tournament screen.
    @ViewBuilder
    private var seasonStatusRow: some View {
        if let table = currentSeasonTable {
            Button {
                path.append(.season)
            } label: {
                HStack(spacing: Space.s) {
                    Image(systemName: "medal.fill")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Licht.lampengold)
                        .accessibilityHidden(true)
                    // The season line is a narrow night strip; the kicker
                    // speaks rounded lamplight.
                    Text(L10n.t("games.hub.season.kicker"))
                        .font(Typo.caption)
                        .foregroundStyle(Licht.lampengold)
                    // The Monats-Poststempel of the Aushang (ENTSCHEID
                    // §4.3): the running month as a stamped line — rounded
                    // Kapitälchen (caption + uppercase), because serif
                    // lives ONLY on paper and this strip is night (Fix-
                    // Runde 3, Befund 11). No rotated stamp circle (the
                    // fan of the dealt hands is this screen's ONE
                    // rotation).
                    Text(Date().formatted(.dateTime.month(.wide)))
                        .font(Typo.caption)
                        .textCase(.uppercase)
                        .foregroundStyle(Nacht.tertiaer)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(L10n.t("games.hub.season.score",
                                ["mine": "\(table.myPoints)",
                                 "theirs": "\(table.theirPoints)",
                                 "name": appState.partnerName]))
                        .font(.system(.footnote, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Papier.aufNacht)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(Nacht.tertiaer)
                        .accessibilityHidden(true)
                }
                .nightCard(padding: .compact, grain: false)
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
        }
    }

    /// This month's still-open best-of rivalry (existing Records data only,
    /// pure rule in `PlayHubCuration.runningSeries`).
    private var seriesMomentum: SeriesMomentum? {
        guard let myId = appState.memberId else { return nil }
        let now = Date()
        let results: [SeriesResult] = pastGames.compactMap { game in
            guard Calendar.current.isDate(game.createdAt, equalTo: now, toGranularity: .month),
                  Self.catalogIds.contains(game.type),
                  let scores = game.result?["scores"]?.objectValue,
                  let mine = scores[myId]?.intValue,
                  let theirs = scores.first(where: { $0.key != myId })?.value.intValue else {
                return nil
            }
            return SeriesResult(gameId: game.type, mine: mine, theirs: theirs,
                                endedAt: game.createdAt)
        }
        return PlayHubCuration.runningSeries(results: results)
    }

    /// "Weiterspielen" nudge for the liveliest open series.
    @ViewBuilder
    private var seriesMomentumCard: some View {
        if let series = seriesMomentum,
           let destination = GameDestination(rawValue: series.gameId) {
            Button {
                path.append(destination)
            } label: {
                HStack(spacing: LayoutMetrics.s(12)) {
                    GameKindGlyph(kind: GameKind(rawValue: series.gameId),
                                  size: 30, tint: Licht.lampengold)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("games.hub.series.title"))
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(Papier.aufNacht)
                        Text(L10n.t("games.hub.series.body",
                                    ["game": Self.gameTitle(for: GameKind(rawValue: series.gameId) ?? .quiz),
                                     "mine": "\(series.myWins)",
                                     "theirs": "\(series.theirWins)"]))
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Nacht.sekundaer)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Text(L10n.t("games.hub.series.play"))
                        .font(.system(.footnote, design: .rounded).weight(.bold))
                        .padding(.horizontal, LayoutMetrics.s(14))
                        .padding(.vertical, LayoutMetrics.s(8))
                        .background(Capsule().fill(Papier.nachtInnenFill))
                        .overlay(Capsule().strokeBorder(Nacht.naht,
                                                        lineWidth: Theme.hairlineWidth))
                        .foregroundStyle(Papier.aufNacht)
                }
                .nightCard()
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
        }
    }

    /// Session games the curation may recommend — the three cabinet
    /// drawers, minus the one drawer entry without a session engine
    /// (Wordle + quests have their own daily cards right below the hero).
    private static let catalogIds: [String] = KartenschrankFach.schrank
        .flatMap { KartenschrankRules.ziele(im: $0) }
        .filter { GameKind(rawValue: $0) != nil }

    /// List-derived history, grounded on the whole-history aggregate
    /// (Fix-Runde 3, Befund 8a): `gamesStats.perKind` overrules the
    /// 50-item page, so the hero can never recommend a genuinely played
    /// game as "Noch nie gespielt" just because its rounds fell off the
    /// curation page. Rule + pin live in `PlayHubCuration.groundedHistory`.
    private var playHistory: [String: PlayHistoryEntry] {
        var history: [String: PlayHistoryEntry] = [:]
        for game in pastGames {
            let entry = history[game.type]
            history[game.type] = PlayHistoryEntry(
                lastPlayed: max(entry?.lastPlayed ?? .distantPast, game.createdAt),
                playCount: (entry?.playCount ?? 0) + 1
            )
        }
        return PlayHubCuration.groundedHistory(history, aggregate: gamesStats?.perKind)
    }

    /// Today's local pick — Foundation-only heuristic in
    /// `Content/PlayHubCuration.swift`, pinned by the logic tests.
    private var heroPick: PlayRecommendation? {
        let now = Date()
        let playedThisSeason = pastGames.contains {
            Calendar.current.isDate($0.createdAt, equalTo: now, toGranularity: .month)
        }
        return PlayHubCuration.recommendation(
            candidates: Self.catalogIds,
            history: playHistory,
            hour: Calendar.current.component(.hour, from: now),
            now: now,
            dateKey: SharedDates.todayKey(),
            playedThisSeason: playedThisSeason
        )
    }

    /// "Heute für euch" — the hub's featured recommendation. A promo is
    /// night chrome, not a letter (Weiß-Audit, MIGRATION_DUNKEL §10):
    /// the hero speaks night ink on the night card and keeps its rank
    /// through a small paper Briefmarke around the game glyph — light
    /// paper stays an inset artifact, never the whole pane.
    @ViewBuilder
    private var heroCard: some View {
        if let pick = heroPick,
           let destination = GameDestination(rawValue: pick.gameId) {
            let kind = GameKind(rawValue: pick.gameId)
            Button {
                path.append(destination)
            } label: {
                VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
                    // The Tagesaushang kicker (Eval S2 „Titel + Hero"): the
                    // station's own notice instead of a generic promo line
                    // — in the established night-kicker pattern (rounded
                    // Typo.caption + lamplight, the season strip's voice),
                    // because serif/anschrift lives ONLY on paper and the
                    // hero is a night card (Fix-Runde 3, Befund 11).
                    Text(L10n.t(PlayHubCuration.isEvening(
                        hour: Calendar.current.component(.hour, from: Date()))
                        ? "games.hub.hero.kicker.evening" : "games.hub.hero.kicker.day"))
                        .font(Typo.caption)
                        .foregroundStyle(Licht.lampengold)
                    // AX5 gate (re-eval 2, Befund 11 — the TelegrammLeiste
                    // pattern): at accessibility sizes the row STACKS —
                    // Briefmarke on top, texts at full card width, the CTA
                    // as a full-width band — instead of squeezing the wax
                    // capsule beside a grown title until its label breaks
                    // character by character.
                    if dynamicTypeSize.prefersVerticalLayout {
                        VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
                            heroBriefmarke(kind)
                            heroTexts(pick)
                            heroCTA(fullWidth: true)
                        }
                    } else {
                        HStack(spacing: LayoutMetrics.s(14)) {
                            heroBriefmarke(kind)
                            heroTexts(pick)
                            Spacer(minLength: 0)
                            heroCTA(fullWidth: false)
                        }
                    }
                }
                .nightCard(padding: .hero)
            }
            .buttonStyle(.plain)
            .hoverEffect(.lift)
            // The hero arrives with "Blättern"; the crossfade path under
            // Reduce Motion lives in the modifier.
            .paperBlaettern()
        }
    }

    /// The Briefmarke: the glyph in couple ink on a stamp-sized bright
    /// paper inset with the classic perforated edge — its own tiny
    /// artifact, no longer borrowing the Polaroid (photo) mechanic.
    private func heroBriefmarke(_ kind: GameKind?) -> some View {
        BriefmarkenInset {
            GameKindGlyph(kind: kind, size: 28, tint: coupleTint.tinte)
                .frame(width: LayoutMetrics.s(28),
                       height: LayoutMetrics.s(28))
        }
        .accessibilityHidden(true)
    }

    private func heroTexts(_ pick: PlayRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.t("games.card.\(pick.gameId).title"))
                .font(Typo.title)
                .foregroundStyle(Papier.aufNacht)
            Text(L10n.t(pick.reasonKey))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
                // Fix4 Befund 3: the hard 2-line cap ellipsed the reason
                // at AX sizes („entdeckt etw…") — grown type wraps in
                // full instead (Leisten-Muster, TelegrammLeiste).
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Siegellack CTA (Eval S2): the hero's call to action pours the brand
    /// wax — label in letter paper, the lamp on the pour's upper lip —
    /// never a cyan capsule. In the ROW layout `fixedSize` keeps the label
    /// whole: squeezed beside a grown title it used to break CHARACTER BY
    /// CHARACTER (spieltisch-ax5). In the stacked AX layout the capsule
    /// spans the full card width instead and the label wraps word-wise.
    private func heroCTA(fullWidth: Bool) -> some View {
        Text(L10n.t("games.hub.hero.play"))
            .font(.system(.footnote, design: .rounded).weight(.bold))
            .foregroundStyle(Papier.brief)
            .fixedSize(horizontal: !fullWidth, vertical: true)
            .padding(.horizontal, LayoutMetrics.s(14))
            .padding(.vertical, LayoutMetrics.s(8))
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(
                Capsule()
                    .fill(LinearGradient(
                        colors: [Wachs.rot, Wachs.dunkel],
                        startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().strokeBorder(
                        Wachs.lichtkante.opacity(0.35),
                        lineWidth: Theme.hairlineWidth))
            )
    }

    /// One horizontal row of the last played games — straight back into
    /// a rematch without scanning the whole catalog.
    @ViewBuilder
    private var recentlyPlayedRow: some View {
        let recent = PlayHubCuration.recentlyPlayed(
            records: pastGames.map { ($0.type, $0.createdAt) }
        ).compactMap { GameDestination(rawValue: $0) }
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: LayoutMetrics.s(8)) {
                Text(L10n.t("games.hub.recent"))
                    .font(Typo.caption)
                    .foregroundStyle(Theme.textTertiary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: LayoutMetrics.s(8)) {
                        ForEach(recent) { destination in
                            recentChip(destination)
                        }
                    }
                }
            }
        }
    }

    private func recentChip(_ destination: GameDestination) -> some View {
        Button {
            path.append(destination)
        } label: {
            HStack(spacing: Space.s) {
                GameKindGlyph(kind: GameKind(rawValue: destination.rawValue),
                              size: 18, tint: coupleTint.blend)
                    .accessibilityHidden(true)
                Text(L10n.t("games.card.\(destination.rawValue).title"))
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            }
            .padding(.horizontal, LayoutMetrics.s(12))
            .padding(.vertical, LayoutMetrics.s(8))
            .background(Capsule().fill(Theme.innerFill))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: Theme.hairlineWidth))
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
    }

    // MARK: Daily Liebes-Wordle card

    private var wordleCard: some View {
        Button {
            path.append(.wordle)
        } label: {
            HStack(spacing: LayoutMetrics.s(14)) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "heart.text.square.fill")
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Licht.lampengold)
                        .accessibilityHidden(true)
                    if wordleDoneToday {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(Licht.lampengold)
                            .background(Circle().fill(Papier.nachtkarton).padding(1))
                            .offset(x: 4, y: 2)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(L10n.t("games.wordle.title"))
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundStyle(Papier.aufNacht)
                        PillTag(text: L10n.t("games.wordle.daily"), tint: Licht.glut)
                        if let won = wordleDuelWon {
                            // Duel verdict chip: trophy when decided,
                            // twin hearts for ties and shared defeats.
                            Image(systemName: won ? "trophy.fill" : "heart.circle.fill")
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Licht.lampengold)
                                .accessibilityHidden(true)
                        }
                    }
                    Text(L10n.t(wordleDoneToday ? "games.wordle.done" : "games.wordle.teaser"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Nacht.sekundaer)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: wordleDoneToday ? "checkmark.seal.fill" : "chevron.right")
                    .font(.system(wordleDoneToday ? .title3 : .footnote,
                                  design: .rounded).weight(.bold))
                    .foregroundStyle(wordleDoneToday ? Licht.lampengold : Nacht.tertiaer)
            }
            .nightCard()
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
    }

    /// Daily quests as a FULL-width daily-ritual row — no more lonely
    /// half-tile next to an empty grid slot.
    private var dailyQuestsCard: some View {
        Button {
            path.append(.dailyquests)
        } label: {
            HStack(spacing: LayoutMetrics.s(14)) {
                Image(systemName: "target")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Licht.lampengold)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(L10n.t("games.card.dailyquests.title"))
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundStyle(Papier.aufNacht)
                        PillTag(text: L10n.t("games.badge.multiplayer"),
                                tint: coupleTint.blend)
                    }
                    Text(L10n.t("games.card.dailyquests.teaser"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Nacht.sekundaer)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .foregroundStyle(Nacht.tertiaer)
            }
            .nightCard()
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
    }

    private func refreshWordleDone() {
        guard let couple = appState.couple else {
            wordleDoneToday = false
            wordleDuelWon = nil
            return
        }
        wordleDoneToday = WordleDaily.isFinished(coupleId: couple.id,
                                                 dateKey: SharedDates.todayKey(),
                                                 lang: L10n.lang)
        refreshWordleDuel()
    }

    /// Cheap, non-blocking duel check for the badge — only fires once my
    /// own board is done (before that no duel outcome can exist anyway).
    private func refreshWordleDuel() {
        guard wordleDoneToday, let api = appState.api else {
            wordleDuelWon = nil
            return
        }
        Task {
            guard let response = try? await api.wordleDay(dateKey: SharedDates.todayKey(),
                                                          lang: L10n.lang) else { return }
            applyWordleDuel(response)
        }
    }

    private func applyWordleDuel(_ response: WordleDayResponse) {
        guard response.dateKey == SharedDates.todayKey(),
              (response.lang ?? L10n.lang) == L10n.lang else { return }
        guard let mine = response.mine, let partner = response.partner else {
            wordleDuelWon = nil
            return
        }
        // Trophy when the duel has a winner, hearts for ties and shared
        // defeats.
        wordleDuelWon = mine.win != partner.win
            || (mine.win && partner.win && mine.rows != partner.rows)
    }

    // MARK: Zone 3 — Kartenschrank (three drawers, Adoption A1 headers)

    // GameGlyph completion (de-slop): every envelope renders its SF-Symbol
    // glyph via `gameSymbol` — icons are printed, the couple ink stays
    // reserved for identity.

    /// Adaptive: 2 columns on phones, more as the window grows (iPad —
    /// „Fächer zweispaltig ab regular width" comes free with the grid).
    /// AX law (`AccessibilityBudget.gridColumns`, EVAL AX5 family): at
    /// accessibility sizes the grid stops adapting and counts DOWN — 2 at
    /// AX1–2, one column at AX3+ — so envelope labels wrap in full
    /// instead of shattering (the cards lift their lineLimits then, see
    /// `UmschlagKarte`).
    private var gameColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return Array(repeating: GridItem(.flexible(), spacing: 12),
                         count: dynamicTypeSize.gridColumns(regular: 2))
        }
        return [GridItem(.adaptive(minimum: LayoutMetrics.hubTileMin), spacing: 12)]
    }

    /// One drawer of the cabinet: the tappable A1 register header
    /// („{Fach} ····· {gespielte Partien}") over the envelope grid.
    /// Accordion law (Eval S2): at most ONE drawer is open — opening a
    /// drawer folds its sibling, tapping the open head folds everything.
    /// `offenesFach` (@AppStorage) remembers the last open drawer.
    private func fachSection(_ fach: KartenschrankFach) -> some View {
        let collapsed = offenesFach != fach.rawValue
        return VStack(spacing: LayoutMetrics.s(12)) {
            Button {
                withAnimation(Theme.Motion.settle) {
                    offenesFach = collapsed ? fach.rawValue : ""
                }
                Haptics.shared.tap()
            } label: {
                KartenschrankFachKopf(
                    titel: fachTitel(fach),
                    partien: fachPartien(fach),
                    untergrenze: fachUntergrenze,
                    eingeklappt: collapsed)
                    .contentShape(Rectangle())
            }
            // Redesign wave 1: drawer heads answer the finger visibly
            // (DS press response) instead of replying only via haptics.
            .buttonStyle(DSPressableStyle())
            .accessibilityLabel(fachA11yLabel(fach))
            .accessibilityValue(L10n.t(collapsed
                                       ? "games.hub.group.collapsed"
                                       : "games.hub.group.expanded"))
            if !collapsed {
                fachGrid(fach)
            }
        }
    }

    /// A1 page number of one drawer: the server aggregate first (WHOLE
    /// history via `gamesStats.perKind`), the 50-item list only as the
    /// pre-stats-server fallback.
    private func fachPartien(_ fach: KartenschrankFach) -> Int {
        if let stats = gamesStats {
            return KartenschrankRules.gespieltePartien(im: fach,
                                                       zaehlung: stats.perKind)
        }
        return KartenschrankRules.gespieltePartien(im: fach,
                                                   verlauf: pastGames.map(\.type))
    }

    /// True when the aggregate the page numbers read was seeded from an
    /// ALREADY-capped store (Fix-Runde 3, Befund 6): evicted history is
    /// unprovable, so every stats-fed register number is an honest floor
    /// — shown as „{n}+" instead of pretending exactness.
    private var fachUntergrenze: Bool {
        gamesStats?.istUntergrenze == true
    }

    /// Pre-stats-server fallback for the Bilanz row (Fix4 Befund 4):
    /// mirrors the destination's own filter — only rounds carrying a
    /// verdict (head-to-head scores, or a match rate over real rounds)
    /// appear on the scoreboard, so only those may be counted here.
    private var bilanzFallback: Int {
        pastGames.filter {
            $0.result?["scores"]?.objectValue != nil
                || ($0.result?["matches"]?.intValue != nil
                    && ($0.result?["rounds"]?.intValue ?? 0) > 0)
        }.count
    }

    /// The envelopes of one drawer — order and coverage come from the
    /// PURE mapping (`KartenschrankRules`, LogicTest-pinned), the hub only
    /// deals them out. Starting a round runs „Lasche auf" inside the card
    /// and then pushes the destination — the board blätters in behind.
    private func fachGrid(_ fach: KartenschrankFach) -> some View {
        let ziele = KartenschrankRules.ziele(im: fach)
            .compactMap(GameDestination.init(rawValue:))
        return LazyVGrid(columns: gameColumns, spacing: 12) {
            ForEach(Array(ziele.enumerated()), id: \.element.id) { index, ziel in
                UmschlagKarte(
                    destination: ziel,
                    // Only correspondence rounds are addressed post
                    // (POSTAMT §3.3: „Für {Partner}").
                    anschrift: fach == .fernpartien
                        ? L10n.t("games.umschlag.anschrift",
                                 ["name": appState.partnerName])
                        : nil,
                    multiplayer: ziel != .questions36 && ziel != .dateideas
                ) {
                    path.append(ziel)
                }
                // The envelopes land on the table ("Legen", staggered,
                // max 6 — Reduce Motion: fade only).
                .paperLegen(index: index)
            }
        }
    }

    /// Display name of a cabinet drawer (the two non-cabinet shelves have
    /// their own zone chrome and never render a drawer header).
    private func fachTitel(_ fach: KartenschrankFach) -> String {
        switch fach {
        case .fernpartien: return L10n.t("games.fach.fernpartien")
        case .amTisch: return L10n.t("games.fach.amtisch")
        case .festeFragen: return L10n.t("games.fach.festefragen")
        case .aushang, .spielbuch: return ""
        }
    }

    /// Spoken header: „{Fach}, {n} gespielte Partien" — the dotted leader
    /// stays silent, the honest number does not. Cardinal plural via the
    /// count API: „1 gespielte Partie", never „1 gespielte Partien". A
    /// lower-bound aggregate speaks „mindestens {n}" (Befund 6), the same
    /// honesty the visible „{n}+" carries.
    private func fachA11yLabel(_ fach: KartenschrankFach) -> String {
        fachTitel(fach) + ", "
            + L10n.t(fachUntergrenze ? "games.fach.partien.a11y.floor"
                                     : "games.fach.partien.a11y",
                     count: fachPartien(fach))
    }

    /// The zone label strip, nacht-first: a narrow night strip whose
    /// label glows in lamplight — the section divider of the dark hub.
    private func categoryTab(title: String) -> some View {
        HStack(spacing: Space.s) {
            Text(title)
                .font(Typo.caption)
                .foregroundStyle(Licht.lampengold)
            Spacer(minLength: 0)
        }
        .nightCard(padding: .compact, grain: false)
    }

    // MARK: Zone 4 — Spielbuch (the register at the bottom)

    /// Turnier · Siegerliste · Wiederholungen · Anleitungen as the SAME
    /// A1 register anatomy as the drawer headers. Every number is an
    /// existing honest statistic: season games this month, finished
    /// matches on record and replayable rounds from the WHOLE-history
    /// `GET /api/games/stats` aggregate (the 50-item page lied from game
    /// 51 on; the list stays only as the pre-stats-server fallback), and
    /// the tutorial library count. An aggregate seeded from an already-
    /// capped store is an honest FLOOR — the Siegerliste row then reads
    /// „{n}+" (Befund 6). Replay stays exact: it counts what is still
    /// stored, and only stored rounds can be replayed at all.
    private var spielbuchZeilen: some View {
        VStack(spacing: LayoutMetrics.s(10)) {
            SpielbuchZeile(titel: L10n.t("games.season.title"),
                           zahl: currentSeasonTable?.games ?? 0) {
                path.append(.season)
            }
            SpielbuchZeile(titel: L10n.t("games.card.record.title"),
                           // Fix4 Befund 4: the Bilanz row counts what its
                           // destination SHOWS. GamesRecordView keeps only
                           // rounds with a verdict — `total` also counts
                           // scoreless played rounds, so the row read „1"
                           // over an empty scoreboard. Rule + pin live in
                           // `PlayHubCuration.bilanzPartien`; the „{n}+"
                           // floor marker stays whenever the aggregate is
                           // one.
                           zahl: gamesStats.map {
                               PlayHubCuration.bilanzPartien(decided: $0.decided,
                                                             draws: $0.draws)
                           } ?? bilanzFallback,
                           untergrenze: fachUntergrenze) {
                path.append(.record)
            }
            SpielbuchZeile(titel: L10n.t("games.replay.title"),
                           zahl: gamesStats?.replayable
                               ?? pastGames.filter { !$0.moves.isEmpty && $0.kind != nil }.count) {
                path.append(.replay)
            }
            SpielbuchZeile(titel: L10n.t("games.tutorial.library.title"),
                           zahl: GameTutorialCatalog.library.count) {
                path.append(.tutorials)
            }
        }
    }

    // MARK: Destination mapping

    @ViewBuilder
    private func gameView(for destination: GameDestination) -> some View {
        switch destination {
        case .wordle:
            WordleView()
        case .quiz:
            QuizGameView(engine: coordinator.engine(for: .quiz))
        case .thisorthat:
            ChoiceGamesView(engine: coordinator.engine(for: .thisorthat), kind: .thisorthat)
        case .wouldyourather:
            ChoiceGamesView(engine: coordinator.engine(for: .wouldyourather), kind: .wouldyourather)
        case .truthordare:
            TruthOrDareView(engine: coordinator.engine(for: .truthordare))
        case .questions36:
            Questions36View()
        case .emojiriddle:
            EmojiRiddleView(engine: coordinator.engine(for: .emojiriddle))
        case .connectfour:
            ConnectFourView(engine: coordinator.engine(for: .connectfour))
        case .photomemory:
            PhotoMemoryView(engine: coordinator.engine(for: .photomemory))
        case .quizduel:
            QuizDuelView(engine: coordinator.engine(for: .quizduel))
        case .battleship:
            BattleshipView(engine: coordinator.engine(for: .battleship))
        case .pictionary:
            PictionaryView(engine: coordinator.engine(for: .pictionary))
        case .kniffel:
            KniffelView(engine: coordinator.engine(for: .kniffel))
        case .movieroulette:
            MovieRouletteView(engine: coordinator.engine(for: .movieroulette))
        case .stadtlandfluss:
            StadtLandFlussView(engine: coordinator.engine(for: .stadtlandfluss))
        case .twotruths:
            TwoTruthsView(engine: coordinator.engine(for: .twotruths))
        case .dailyquests:
            DailyQuestsView(engine: coordinator.engine(for: .dailyquests))
        case .wordchain:
            WordChainView(engine: coordinator.engine(for: .wordchain))
        case .hangman:
            HangmanView(engine: coordinator.engine(for: .hangman))
        case .bingo:
            CoupleBingoView(engine: coordinator.engine(for: .bingo))
        case .wordleduo:
            WordleDuoView(engine: coordinator.engine(for: .wordleduo))
        case .rps:
            RockPaperScissorsView(engine: coordinator.engine(for: .rps))
        case .story:
            StoryRelayView(engine: coordinator.engine(for: .story))
        case .dame:
            DameView(engine: coordinator.engine(for: .dame))
        case .reversi:
            ReversiView(engine: coordinator.engine(for: .reversi))
        case .kaesekaestchen:
            KaesekaestchenView(engine: coordinator.engine(for: .kaesekaestchen))
        case .gomoku:
            GomokuView(engine: coordinator.engine(for: .gomoku))
        case .mancala:
            MancalaView(engine: coordinator.engine(for: .mancala))
        case .memoryduo:
            MemoryDuoView(engine: coordinator.engine(for: .memoryduo))
        case .tutorials:
            GameTutorialLibraryView()
        case .dateideas:
            DateIdeasView()
        case .season:
            TournamentView()
        case .replay:
            ReplayHubView()
        case .record:
            GamesRecordView()
        }
    }

    /// Hub destination for a game type (all v3.0 types have a UI now).
    private func destination(for kind: GameKind) -> GameDestination? {
        switch kind {
        case .quiz: return .quiz
        case .thisorthat: return .thisorthat
        case .wouldyourather: return .wouldyourather
        case .truthordare: return .truthordare
        case .questions36: return .questions36
        case .emojiriddle: return .emojiriddle
        case .connectfour: return .connectfour
        case .photomemory: return .photomemory
        case .quizduel: return .quizduel
        case .battleship: return .battleship
        case .pictionary: return .pictionary
        case .kniffel: return .kniffel
        case .movieroulette: return .movieroulette
        case .stadtlandfluss: return .stadtlandfluss
        case .twotruths: return .twotruths
        case .dailyquests: return .dailyquests
        case .wordchain: return .wordchain
        case .hangman: return .hangman
        case .bingo: return .bingo
        case .wordleduo: return .wordleduo
        case .rps: return .rps
        case .story: return .story
        case .dame: return .dame
        case .reversi: return .reversi
        case .kaesekaestchen: return .kaesekaestchen
        case .gomoku: return .gomoku
        case .mancala: return .mancala
        case .memoryduo: return .memoryduo
        }
    }

    /// Localized display name of a game type.
    static func gameTitle(for kind: GameKind) -> String {
        L10n.t("games.card.\(kind.rawValue).title")
    }

    /// SF-Symbol icon of a game type — COMPLETE since the glyph pass:
    /// every tile, banner and row renders a symbol; emoji stays reserved
    /// for game CONTENT (riddles, boards, avatars) and plain-text shares.
    static func gameSymbol(for kind: GameKind) -> String {
        switch kind {
        case .quiz: return "brain.head.profile"
        case .thisorthat: return "bolt.fill"
        case .wouldyourather: return "arrow.triangle.branch"
        case .truthordare: return "theatermasks.fill"
        case .questions36: return "bubble.left.and.bubble.right.fill"
        case .emojiriddle: return "puzzlepiece.fill"
        case .connectfour: return "circle.grid.2x2.fill"
        case .photomemory: return "photo.on.rectangle.angled"
        case .quizduel: return "stopwatch.fill"
        case .battleship: return "sailboat.fill"
        case .pictionary: return "paintbrush.pointed.fill"
        case .kniffel: return "dice.fill"
        case .movieroulette: return "popcorn.fill"
        case .stadtlandfluss: return "map.fill"
        case .twotruths: return "person.fill.questionmark"
        case .dailyquests: return "target"
        case .wordchain: return "link"
        case .hangman: return "textformat.abc"
        case .bingo: return "heart.text.square.fill"
        case .wordleduo: return "square.grid.3x3.fill"
        case .rps: return "scissors"
        case .story: return "book.fill"
        case .dame: return "checkerboard.rectangle"
        case .reversi: return "circle.lefthalf.filled"
        case .kaesekaestchen: return "squareshape.split.3x3"
        case .gomoku: return "circle.grid.3x3.fill"
        case .mancala: return "circlebadge.2.fill"
        case .memoryduo: return "square.on.square"
        }
    }

    /// Hub emoji of a game type (banners, turn hints, replay rows).
    /// Symbol-first types (see `gameSymbol`) only surface this in plain-text
    /// contexts like the chat share line — the neutral die, no new emoji.
    static func gameEmoji(for kind: GameKind) -> String {
        switch kind {
        case .quiz: return "🧠"
        case .thisorthat: return "⚡️"
        case .wouldyourather: return "🤯"
        case .truthordare: return "🎭"
        case .questions36: return "💫"
        case .emojiriddle: return "🧩"
        case .connectfour: return "🔴"
        case .photomemory: return "🖼️"
        case .quizduel: return "⚡️"
        case .battleship: return "🚢"
        case .pictionary: return "🎨"
        case .kniffel: return "🎲"
        case .movieroulette: return "🍿"
        case .stadtlandfluss: return "🗺️"
        case .twotruths: return "🤥"
        case .dailyquests: return "⚔️"
        case .wordchain: return "🔗"
        case .hangman: return "🌸"
        case .bingo: return "💞"
        case .wordleduo, .rps, .story,
             .dame, .reversi, .kaesekaestchen, .gomoku, .mancala, .memoryduo:
            return "🎲"
        }
    }
}

// MARK: - Game-kind glyph (icon for banners, replay rows, record rows)

/// One shared icon per game type: the SF-Symbol glyph for the symbol-first
/// types, the established hub emoji for the older ones. `size` matches the
/// emoji point size the surrounding row was designed around.
struct GameKindGlyph: View {
    let kind: GameKind?
    var size: Double = 22
    var tint: Color = Theme.textPrimary

    var body: some View {
        // Symbol-only since the glyph pass — unknown types get the die.
        Image(systemName: kind.map(PlayHubView.gameSymbol(for:)) ?? "dice.fill")
            .font(.scaled(size * 0.82, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
    }
}

// MARK: - Briefmarken-Inset (the hero stamp)

/// The classic stamp perforation: the rectangle's edge runs in small
/// triangular teeth (Zacken) toward the inside. Pure Path in token
/// colors — corners stay on the outer line so the stamp reads upright.
private struct BriefmarkenZacken: Shape {
    var zahn: CGFloat

    func path(in rect: CGRect) -> Path {
        let ecken = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
        ]
        var punkte: [CGPoint] = []
        for index in ecken.indices {
            let a = ecken[index]
            let b = ecken[(index + 1) % ecken.count]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let laenge = max(hypot(dx, dy), 1)
            // Even step count so both corners land on the outer line;
            // odd steps dip inward by one tooth (clockwise traversal →
            // the inward normal is (-dy, dx)).
            let paare = max(Int((laenge / (zahn * 2)).rounded()), 1)
            let schritte = paare * 2
            let einwaerts = CGPoint(x: -dy / laenge * zahn, y: dx / laenge * zahn)
            for schritt in 0..<schritte {
                let t = CGFloat(schritt) / CGFloat(schritte)
                var p = CGPoint(x: a.x + dx * t, y: a.y + dy * t)
                if schritt % 2 == 1 {
                    p.x += einwaerts.x
                    p.y += einwaerts.y
                }
                punkte.append(p)
            }
        }
        var path = Path()
        guard let erster = punkte.first else { return path }
        path.move(to: erster)
        for punkt in punkte.dropFirst() {
            path.addLine(to: punkt)
        }
        path.closeSubpath()
        return path
    }
}

/// Stamp-sized bright paper inset around a glyph — its OWN tiny artifact
/// with the perforated Briefmarken edge instead of borrowing the Polaroid
/// mechanic (a Polaroid means "photo", a Briefmarke means "postage").
/// Deliberately LOCAL to the Spieltisch: letter paper + edge tokens only,
/// no new material, no Glass change — the Postfach may copy it verbatim.
struct BriefmarkenInset<Content: View>: View {
    @ViewBuilder var content: Content

    private var zacken: BriefmarkenZacken {
        BriefmarkenZacken(zahn: LayoutMetrics.s(2.5))
    }

    var body: some View {
        content
            .padding(LayoutMetrics.s(8))
            .background(zacken.fill(Papier.brief))
            .overlay(zacken.stroke(Papier.kante, lineWidth: Theme.hairlineWidth))
    }
}

// MARK: - Shared multiplayer scaffolding

/// Empty state when the couple is not complete yet — the realtime games
/// need both partners. Chrome, not artifact: a night card with the
/// shared night-ink empty state.
struct GameNeedsPartnerView: View {
    var body: some View {
        EmptyStateView(systemImage: "person.2.fill",
                       title: L10n.t("games.needPartner.title"),
                       subtitle: L10n.t("games.needPartner.body"))
            .nightCard(padding: .compact)
            .padding(LayoutMetrics.s(16))
            .contentColumn(.reading)
    }
}

/// Lobby state inside a game view: either "waiting for partner to join"
/// (I created the session) or a big join button (partner invited me).
struct GameLobbyView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint

    let engine: GameEngine
    /// LEGACY: the glass-era accent — on paper every lobby reads in the
    /// couple ink; kept so the twelve call sites stay untouched.
    let accent: Color

    var body: some View {
        VStack(spacing: LayoutMetrics.s(14)) {
            if isMine {
                waitingContent
            } else {
                joinContent
            }
        }
        .frame(maxWidth: .infinity)
        .nightCard(padding: .hero)
        // Every realtime lobby reads in a column on regular width — the
        // one shared edit instead of twelve per-game ones (roadmap 22).
        .contentColumn(.reading)
    }

    private var isMine: Bool {
        engine.session?.createdBy == appState.memberId
    }

    private var waitingContent: some View {
        VStack(spacing: LayoutMetrics.s(14)) {
            EmojiAvatarView(emoji: appState.partner?.avatar,
                            colorHex: appState.partner?.color,
                            size: LayoutMetrics.s(64),
                            online: appState.partner?.online ?? false)
            Text(L10n.t("games.waitingFor", ["name": appState.partnerName]))
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Papier.aufNacht)
                .multilineTextAlignment(.center)
            Text(waitingHint)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            ProgressView()
                .tint(Nacht.sekundaer)
            Button {
                Task { await engine.end(api: appState.api, result: nil) }
            } label: {
                Text(L10n.t("games.invite.cancel"))
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(Nacht.tertiaer)
            }
            .buttonStyle(.plain)
            .disabled(engine.busy)
        }
    }

    private var waitingHint: String {
        if appState.partner?.online == true {
            return L10n.t("games.invite.waitingBody", ["name": appState.partnerName])
        }
        return L10n.t("games.invite.offline", ["name": appState.partnerName])
    }

    private var joinContent: some View {
        VStack(spacing: LayoutMetrics.s(14)) {
            Image(systemName: "envelope.open.fill")
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                // The partner's invitation keeps the couple identity —
                // blend is the sanctioned non-text accent on night.
                .foregroundStyle(coupleTint.blend)
                .accessibilityHidden(true)
            Text(L10n.t("games.lobby.joinTitle", ["name": appState.partnerName]))
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(Papier.aufNacht)
                .multilineTextAlignment(.center)
            Text(L10n.t("games.lobby.joinBody"))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
                .multilineTextAlignment(.center)
            Button {
                Task {
                    if await engine.join(api: appState.api) {
                        SoundEngine.shared.play(.pop)
                        Haptics.shared.success()
                    }
                }
            } label: {
                Text(L10n.t("games.invite.join"))
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(engine.busy)
            // Declining is allowed (28#5) — an invitation should never sit
            // there as silent pressure until the creator gives up.
            Button {
                Task { await engine.end(api: appState.api, result: nil) }
            } label: {
                Text(L10n.t("games.invite.decline"))
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(Nacht.tertiaer)
            }
            .buttonStyle(.plain)
            .disabled(engine.busy)
        }
    }
}

// MARK: - Spectator input gate (canAct)

/// False while THIS device spectates its member's running session (another
/// own device holds the input lease). Injected by `GameForfeitToolbar`;
/// every game surface reads it through `.gameActGated()` so spectator
/// devices see the SAME table but with all inputs visibly locked instead
/// of controls that silently bounce off the server.
private struct GameCanActKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var gameCanAct: Bool {
        get { self[GameCanActKey.self] }
        set { self[GameCanActKey.self] = newValue }
    }
}

/// Locks a game surface for spectator devices: disabled AND visibly dimmed
/// / desaturated, so „Nur zuschauen" is true for the hands, not only for
/// the banner. Applied INSIDE scroll containers — watching stays scrollable.
private struct GameActGate: ViewModifier {
    @Environment(\.gameCanAct) private var canAct

    func body(content: Content) -> some View {
        content
            .disabled(!canAct)
            .opacity(canAct ? 1 : 0.55)
            .saturation(canAct ? 1 : 0.5)
    }
}

extension View {
    /// Dims + disables this game surface while the device only spectates
    /// (input lease held by another own device, see `gameForfeitToolbar`).
    func gameActGated() -> some View {
        modifier(GameActGate())
    }
}

// MARK: - Forfeit (28#3) + spectator banner (roadmap 25)

/// Shared chrome every session game carries: the "Aufgeben" toolbar item
/// with its confirmation (server `{forfeit:true}` contract — the partner
/// takes the win, no zombie sessions), and since roadmap 25 the input-lease
/// SPECTATOR BANNER: when another of MY OWN devices drives this session,
/// the table turns read-only (server-enforced) and this banner names the
/// driving device and offers the explicit takeover. The banner's takeover
/// LOCKS during commit-reveal phases whose sealed secret lives only on the
/// driving device (GameSecretRules) — pulling the lease here would strand
/// the reveal.
private struct GameForfeitToolbar: ViewModifier {
    @Environment(AppState.self) private var appState

    let engine: GameEngine
    /// Cooperative checklist games (daily quests) carry the spectator
    /// chrome without a forfeit affordance — nobody "surrenders" a
    /// shared to-do list.
    var showsForfeit = true

    @State private var confirmForfeit = false

    /// The foreign lease this device spectates, nil when it may play.
    /// Fails open on unknown identity / old servers (GameLeaseRules).
    /// Reads the engine's EFFECTIVE lease — a `game_lease_held` refusal
    /// (`refusedLease`, the newest server truth) outranks the session's
    /// possibly-stale lease map, so a bounced move locks the table
    /// immediately instead of leaving controls that silently fail.
    private var spectatedLease: GameLease? {
        let lease = engine.effectiveLease(myMemberId: appState.memberId)
        guard GameLeaseRules.showsSpectatorBanner(
            state: engine.session?.state, lease: lease,
            ownSessionId: appState.sessionId
        ) else { return nil }
        return lease
    }

    /// True while my member's sealed commit (fleet, answers, lie, word)
    /// is still unrevealed — it lives in the DRIVING device's vault, so a
    /// takeover onto this device would hang the reveal phase.
    private var takeoverBlocked: Bool {
        guard let session = engine.session, let memberId = appState.memberId else { return false }
        return GameSecretRules.holdsSealedSecret(
            gameType: session.type, state: session.state, memberId: memberId,
            createdBy: session.createdBy,
            payloadCarriesCommit: session.payload?["commit"]?.stringValue != nil,
            moves: engine.orderedMoves.map {
                GameSecretMoveSummary(memberId: $0.memberId,
                                      kind: $0.data["kind"]?.stringValue,
                                      round: $0.data["round"]?.intValue,
                                      carriesCommit: $0.data["commit"]?.stringValue != nil)
            }
        )
    }

    func body(content: Content) -> some View {
        content
            .environment(\.gameCanAct, spectatedLease == nil)
            .toolbar {
                if showsForfeit, engine.session?.state == "active" {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            confirmForfeit = true
                        } label: {
                            Image(systemName: "flag.fill")
                        }
                        .accessibilityLabel(L10n.t("games.forfeit.button"))
                        .disabled(engine.busy)
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                if let lease = spectatedLease {
                    spectatorBanner(lease)
                }
            }
            .confirmationDialog(L10n.t("games.forfeit.confirmTitle"),
                                isPresented: $confirmForfeit, titleVisibility: .visible) {
                Button(L10n.t("games.forfeit.confirm"), role: .destructive) {
                    Task {
                        if await engine.forfeit(api: appState.api) {
                            appState.showToast(
                                L10n.t("games.forfeit.doneToast",
                                       ["name": appState.partnerName]),
                                style: .info
                            )
                        }
                    }
                }
                Button(L10n.t("common.cancel"), role: .cancel) {}
            } message: {
                Text(L10n.t("games.forfeit.confirmBody", ["name": appState.partnerName]))
            }
    }

    /// „Nur zuschauen — {Gerät} spielt gerade." Floating labeled chrome →
    /// standalone `.glass` capsule (never inside a GlassGroup, see
    /// UI/Glass.swift). The takeover is the banner's ONE action — and it
    /// locks with an honest device hint while a sealed commit binds the
    /// member to the driving device.
    private func spectatorBanner(_ lease: GameLease) -> some View {
        let deviceName = GameLeaseRules.bannerDeviceName(lease)
            ?? L10n.t(GameLeaseRules.unknownDeviceKey)
        let blocked = takeoverBlocked
        return VStack(spacing: Space.xs) {
            HStack(spacing: Space.s) {
                Image(systemName: "eye.fill")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text(L10n.t("games.lease.banner", ["device": deviceName]))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Button {
                    Haptics.shared.tap()
                    Task {
                        if await engine.takeover(api: appState.api) {
                            GamesA11y.announce(L10n.t("games.lease.takeoverDone"))
                        }
                    }
                } label: {
                    Text(L10n.t("games.lease.takeover"))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(blocked ? Theme.textTertiary : Theme.textPrimary)
                }
                .buttonStyle(.plain)
                .disabled(engine.busy || blocked)
            }
            if blocked {
                Text(L10n.t("games.lease.sealed.hint", ["device": deviceName]))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Space.xs)
        .padding(.horizontal, Space.m)
        .glass(.chrome, in: Capsule())
        .padding(.top, Space.xs)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

extension View {
    /// Adds the shared game chrome: the "Aufgeben" toolbar item for an
    /// active session plus the input-lease spectator banner (roadmap 25).
    /// `showsForfeit: false` keeps only the lease chrome (banner +
    /// `gameCanAct` gate) — for cooperative checklists like daily quests.
    func gameForfeitToolbar(engine: GameEngine, showsForfeit: Bool = true) -> some View {
        modifier(GameForfeitToolbar(engine: engine, showsForfeit: showsForfeit))
    }
}

// MARK: - Shared end ceremony (28#11 + roadmap 24)

/// In a couple app one partner's defeat is the other's win — the loser
/// shares a warm moment (sympathetic sigh, a few hearts) instead of the
/// error-style warning buzzer the views used to fire.
///
/// Since roadmap 24 every ceremony runs through GameDelightRules: match
/// wins carry the victory motif (double heartbeat → shared ta-daa) and a
/// rolling BIG budget keeps epics rare enough to stay epic. The budget is
/// the ONE persisted app-wide DelightArbiterStore ledger — a game epic and
/// a level-up epic spend from the same purse at runtime, not just in the
/// rules layer.
@MainActor
enum GameEndCelebration {
    /// How the visual half renders: `.delight` fires the full-screen
    /// DelightCenter overlay; `.localHearts` means the view draws its own
    /// themed FloatingHearts and only sound + motif come from here.
    enum Visual { case delight, localHearts }

    static func win(theme: DelightTheme = .confetti, visual: Visual = .delight) {
        fire(event: .matchWon, theme: theme, visual: visual)
        // What sighted players SEE end (confetti, verdict panel) VoiceOver
        // players get spoken — every ceremony announces its outcome.
        GamesA11y.announce(L10n.t("games.a11y.end.win"))
    }

    static func tie(visual: Visual = .delight) {
        fire(event: .matchTied, theme: .hearts, visual: visual)
        GamesA11y.announce(L10n.t("games.a11y.end.tie"))
    }

    /// Mid-match lift (a round won, a streak landed): success cue only,
    /// never an overlay — rounds must stay smaller than matches.
    static func roundWon() {
        fire(event: .roundWon, theme: .hearts, visual: .localHearts)
    }

    static func loss(visual: Visual = .delight) {
        fire(event: .matchLost, theme: .hearts, visual: visual)
        GamesA11y.announce(L10n.t("games.a11y.end.loss"))
    }

    /// Rare season-scale moments (weekly quest boards, season wraps) —
    /// big when the budget allows, and they SHARE the match-win budget.
    static func seasonMilestone(theme: DelightTheme = .stars, visual: Visual = .delight) {
        fire(event: .seasonMilestone, theme: theme, visual: visual)
    }

    private static func fire(event: GameCeremonyEvent, theme: DelightTheme, visual: Visual) {
        let tier = DelightArbiterStore.requestGame(event)
        let spec = GameDelightRules.spec(event: event, tier: tier)
        if let fanfare = spec.fanfare {
            CueKit.play(fanfare, hapticOverride: spec.victoryMotif)
        }
        if visual == .delight, let overlay = spec.overlay {
            // Papier & Licht (FullRelease N2-C): delight levels 1–2
            // celebrate with the Lichtschein bloom instead of the
            // full-screen confetti overlay; only `epic` keeps its
            // particles (Direction §5). The DelightArbiter budget above
            // is untouched — the glow spends from the same purse.
            if overlay == .epic {
                DelightCenter.shared.fire(DelightMoment(intensity: overlay, theme: theme))
            } else {
                GameLichtscheinCenter.shared.fire()
            }
        }
    }
}

/// Small caption shown while waiting for the partner's move; mentions when
/// the partner is offline so nobody stares at a frozen screen. Board games
/// show it on the night table (default inks); word/party games place it
/// INSIDE a paper card and pass `onPaper` for readable Tinte.
struct GameWaitingHint: View {
    var onPaper = false

    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                ProgressView()
                    .tint(onPaper ? coupleTint.tinte : coupleTint.blend)
                Text(L10n.t("games.waitingFor", ["name": appState.partnerName]))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(onPaper ? Tinte.sekundaer : Theme.textSecondary)
            }
            if appState.partner?.online != true {
                Text(L10n.t("games.partnerOffline", ["name": appState.partnerName]))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(onPaper ? Tinte.tertiaer : Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

/// Thin rounded progress bar used in the game headers. On paper the
/// track is the sanctioned inner fill and the bar reads in an ink; night
/// contexts pass their own pair explicitly. Wraps a native
/// `ProgressView(value:)` so the system carries semantics and the VoiceOver
/// value announcement — the capsule look lives in the style below.
struct GameProgressBar: View {
    let progress: Double
    var tint: Color = Tinte.sekundaer
    var track: Color = Papier.innenFill

    var body: some View {
        ProgressView(value: min(max(progress, 0), 1))
            .progressViewStyle(GameCapsuleProgressStyle(tint: tint, track: track))
            .animation(Theme.Motion.settle, value: progress)
    }
}

/// The capsule painting of `GameProgressBar`, unchanged from the hand-built
/// bar: paper track, ink fill, 7-pt height, an 8-pt minimum so tiny
/// fractions still read as "started".
private struct GameCapsuleProgressStyle: ProgressViewStyle {
    let tint: Color
    let track: Color

    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(track)
                Capsule()
                    .fill(tint)
                    .frame(width: max(8, proxy.size.width
                        * (configuration.fractionCompleted ?? 0)))
            }
        }
        .frame(height: 7)
    }
}
