import SwiftUI
import Combine

/// Shared implementation for "This or That" AND "Would You Rather" —
/// both are 12 quick rounds where both partners pick option a or b at the
/// same time; every completed round reveals both picks (match animation!).
/// Would-You-Rather additionally shows the "Would you rather…" prefix and
/// a discuss prompt after each reveal.
///
/// This-or-That additionally offers a COUCH MODE (Welle 7 [W6-Rest]): local
/// pass-and-play on one phone, no server session — the TruthOrDare-solo
/// pattern, reduced over `ThisOrThatCouch` in Content/CoupleGamesLogic.swift.
///
/// Move protocol (live mode):
/// - `{"kind": "pick", "round": r, "value": "a" | "b"}` (both members)
struct ChoiceGamesView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let engine: GameEngine
    let kind: GameKind          // .thisorthat or .wouldyourather

    /// Local view cursor: which round this client is looking at. Never
    /// runs ahead of the reducer (only advances past completed rounds).
    @State private var cursor = 0
    @State private var sending = false
    @State private var didSendEnd = false
    @State private var heartsVisible = false
    @State private var endCelebrated = false
    @State private var heartsTask: Task<Void, Never>?
    @State private var sharing = false
    @State private var shared = false

    /// Non-nil while the local couch game runs (takes over the screen).
    @State private var couch: ThisOrThatCouchState?
    /// Deck seed of the running couch game (rolled at start).
    @State private var couchSeed = 0

    private static let defaultRounds = 12

    private enum RevealState: Equatable {
        case none, match, different
    }

    var body: some View {
        ZStack {
            DreamyBackground()
            content
            if heartsVisible && !reduceMotion {
                FloatingHeartsView(emojis: ["💞", "💖", "✨", "💜"], count: 16)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle(L10n.t("games.card.\(kind.rawValue).title"))
        .navigationBarTitleDisplayMode(.inline)
        .gameForfeitToolbar(engine: engine)
        .toolbar {
            // Couch games have no server session to forfeit — the restart
            // arrow (ToD-local pattern) is the way back to the setup.
            if couch != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        exitCouch()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundStyle(accent)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            if let event = note.object as? ServerEvent {
                engine.handle(event)
            }
        }
        .task {
            engine.onError = { [weak appState] error in
                appState?.handleAPIError(error)
            }
            if engine.session == nil {
                await engine.resume(api: appState.api)
            }
            syncCursor()
        }
        .onChange(of: engine.session?.id) { _, _ in
            resetLocalState()
            syncCursor()
        }
        .onChange(of: revealState) { _, new in
            handleReveal(new)
        }
        .onDisappear {
            heartsTask?.cancel()
        }
    }

    // MARK: Derived state (pure reducer over payload + moves)

    private var session: GameSession? {
        guard let current = engine.session, current.kind == kind else { return nil }
        return current
    }

    private var isWouldYouRather: Bool { kind == .wouldyourather }

    private var totalRounds: Int {
        engine.payloadInt("rounds", default: Self.defaultRounds)
    }

    private var sortedMemberIds: [String] {
        (appState.couple?.members.map(\.id) ?? []).sorted()
    }

    private var pairs: [ChoicePair] {
        let source = isWouldYouRather ? ContentPack.wouldYouRather : ContentPack.thisOrThat
        return Array(source.seededShuffled(seed: engine.seed).prefix(totalRounds))
    }

    /// memberId → "a"/"b" for one round (first pick per member wins).
    private func picks(round: Int) -> [String: String] {
        engine.movesByMember(round: round, kind: "pick")
            .compactMapValues { $0.data["value"]?.stringValue }
    }

    private func complete(round: Int) -> Bool {
        guard sortedMemberIds.count == 2 else { return false }
        let current = picks(round: round)
        return sortedMemberIds.allSatisfy { current[$0] != nil }
    }

    private var firstOpenRound: Int {
        guard session != nil else { return 0 }
        for round in 0..<totalRounds where !complete(round: round) {
            return round
        }
        return totalRounds
    }

    private var allComplete: Bool {
        session != nil && totalRounds > 0 && firstOpenRound >= totalRounds
    }

    private var matchCount: Int {
        guard sortedMemberIds.count == 2 else { return 0 }
        var count = 0
        for round in 0..<totalRounds {
            let current = picks(round: round)
            guard let first = current[sortedMemberIds[0]],
                  let second = current[sortedMemberIds[1]] else { continue }
            if first == second { count += 1 }
        }
        return count
    }

    private var revealState: RevealState {
        guard session?.state == "active" || session?.state == "ended",
              cursor < totalRounds,
              complete(round: cursor),
              sortedMemberIds.count == 2 else { return .none }
        let current = picks(round: cursor)
        let first = current[sortedMemberIds[0]]
        let second = current[sortedMemberIds[1]]
        return first == second ? .match : .different
    }

    private var showEndScreen: Bool {
        guard let session, allComplete else { return false }
        return cursor >= totalRounds || session.state == "ended"
    }

    private var myPickForCursor: String? {
        guard let myId = appState.memberId else { return nil }
        return picks(round: cursor)[myId]
    }

    // MARK: Content switch

    @ViewBuilder
    private var content: some View {
        if appState.partner == nil {
            GameNeedsPartnerView()
        } else if let couch {
            couchContent(couch)
        } else if let session {
            if session.state == "lobby" {
                ScrollView {
                    GameLobbyView(engine: engine, accent: accent)
                        .padding(LayoutMetrics.s(16))
                }
            } else if showEndScreen {
                endScreen
            } else if session.state == "active" {
                playScreen
            } else {
                setupScreen
            }
        } else {
            setupScreen
        }
    }

    private var accent: Color {
        isWouldYouRather ? Theme.indigo : coupleTint.blend
    }

    // MARK: Setup

    private var setupScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                Image(systemName: isWouldYouRather ? "arrow.triangle.branch" : "bolt.fill")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(coupleTint.blend)
                    .accessibilityHidden(true)
                Text(L10n.t("games.card.\(kind.rawValue).title"))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                Text(L10n.t(isWouldYouRather
                            ? "games.choice.howto.wouldyourather"
                            : "games.choice.howto.thisorthat"))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    startGame()
                } label: {
                    Text(L10n.t("games.start"))
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(engine.busy)
                if kind == .thisorthat {
                    Button {
                        startCouch()
                    } label: {
                        Text(L10n.t("games.choice.couch.start"))
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .nightCard(padding: .hero)
            .padding(LayoutMetrics.s(16))
            .contentColumn(.reading)
        }
    }

    private func startGame() {
        guard !engine.busy else { return }
        Task {
            resetLocalState()
            let payload = GameEngine.makePayload(options: ["rounds": Self.defaultRounds])
            if await engine.create(api: appState.api, type: kind, payload: payload) {
                SoundEngine.shared.play(.pop)
                Haptics.shared.tap()
            }
        }
    }

    private func resetLocalState() {
        cursor = 0
        sending = false
        didSendEnd = false
        endCelebrated = false
        heartsVisible = false
        sharing = false
        shared = false
        couch = nil     // a (new) live session always takes over the screen
    }

    private func syncCursor() {
        cursor = firstOpenRound
    }

    // MARK: Play

    private var playScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(14)) {
                playHeader
                GameProgressBar(progress: Double(min(cursor, totalRounds)) / Double(max(totalRounds, 1)),
                                tint: coupleTint.blend,
                                track: Papier.nachtInnenFill)
                roundCard
            }
            .gameActGated()
            .padding(LayoutMetrics.s(16))
            .contentColumn(.reading)
        }
    }

    private var playHeader: some View {
        roundHeader(round: cursor, total: totalRounds, matches: matchCount)
    }

    /// Round + match pills — one header for live AND couch play screens.
    private func roundHeader(round: Int, total: Int, matches: Int) -> some View {
        HStack {
            PillTag(text: L10n.t("games.round",
                                 ["n": String(min(round + 1, total)),
                                  "total": String(total)]),
                    tint: accent)
            Spacer()
            PillTag(text: L10n.t("games.choice.matches", ["n": String(matches)]),
                    tint: coupleTint.blend)
        }
    }

    @ViewBuilder
    private var roundCard: some View {
        if cursor < totalRounds, cursor < pairs.count {
            let pair = pairs[cursor]
            VStack(spacing: LayoutMetrics.s(14)) {
                if isWouldYouRather {
                    Text(L10n.t("games.wyr.prefix"))
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Wachs.rot)
                }
                optionCard(option: "a", text: pair.a.resolved(L10n.lang))
                Text(L10n.t("games.choice.or"))
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .foregroundStyle(Tinte.tertiaer)
                optionCard(option: "b", text: pair.b.resolved(L10n.lang))
                footerForRound
            }
            .frame(maxWidth: .infinity)
            .paperCard()
        }
    }

    @ViewBuilder
    private var footerForRound: some View {
        switch revealState {
        case .none:
            if myPickForCursor != nil {
                GameWaitingHint(onPaper: true)
            }
        case .match, .different:
            revealFooter
        }
    }

    private var revealFooter: some View {
        VStack(spacing: LayoutMetrics.s(10)) {
            // Mint/gold fail the 4.5:1 floor on paper — the match verdict
            // wears the couple ink, the miss plain secondary ink.
            Text(revealState == .match
                 ? L10n.t("games.choice.match")
                 : L10n.t("games.choice.noMatch"))
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(revealState == .match ? coupleTint.tinte : Tinte.sekundaer)
            if isWouldYouRather {
                Text(L10n.t("games.wyr.discuss"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Tinte.sekundaer)
            }
            Button {
                advance()
            } label: {
                Text(L10n.t("games.next"))
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.top, 4)
    }

    private func optionCard(option: String, text: String) -> some View {
        let myPick = myPickForCursor
        let isMine = myPick == option
        let revealed = revealState != .none
        return Button {
            pick(option)
        } label: {
            VStack(spacing: 8) {
                Text(text)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Tinte.dunkel)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if revealed {
                    revealChips(option: option)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LayoutMetrics.s(18))
            .padding(.horizontal, LayoutMetrics.s(14))
            .background(
                RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                    .fill(isMine ? coupleTint.tinte.opacity(0.16) : Papier.innenFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                    .strokeBorder(isMine ? coupleTint.tinte : Papier.kante,
                                  lineWidth: isMine ? 1.5 : Theme.hairlineWidth)
            )
            .scaleEffect(isMine && !reduceMotion ? 1.02 : 1)
            .animation(reduceMotion ? nil : Theme.Motion.settle, value: isMine)
        }
        .buttonStyle(.plain)
        .disabled(myPick != nil || sending || revealed)
        .accessibilityValue(optionA11yValue(option: option))
        .accessibilityAddTraits(isMine ? [.isSelected] : [])
    }

    /// Spoken pick state of an option: before the reveal only my own pick
    /// is named, afterwards everyone who chose it.
    private func optionA11yValue(option: String) -> String {
        guard revealState != .none else {
            return myPickForCursor == option ? L10n.t("games.choice.a11y.myPick") : ""
        }
        let current = picks(round: cursor)
        let names = (appState.couple?.members ?? [])
            .filter { current[$0.id] == option }
            .map { $0.id == appState.memberId ? L10n.t("common.you") : $0.name }
        guard !names.isEmpty else { return "" }
        return L10n.t("games.choice.a11y.pickedBy",
                      ["names": names.joined(separator: ", ")])
    }

    /// Avatar chips of everyone who picked this option (shown on reveal).
    @ViewBuilder
    private func revealChips(option: String) -> some View {
        let current = picks(round: cursor)
        let members = (appState.couple?.members ?? []).filter { current[$0.id] == option }
        if !members.isEmpty {
            HStack(spacing: 6) {
                ForEach(members) { member in
                    HStack(spacing: 4) {
                        EmojiAvatarView(emoji: member.avatar, colorHex: member.color, size: 22)
                        Text(member.id == appState.memberId
                             ? L10n.t("common.you")
                             : member.name)
                            .font(.system(.caption2, design: .rounded).weight(.bold))
                            .foregroundStyle(Tinte.sekundaer)
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    .background(
                        Capsule().fill(Papier.brief)
                            .overlay(Capsule().strokeBorder(Papier.kante,
                                                            lineWidth: Theme.hairlineWidth))
                    )
                }
            }
        }
    }

    // MARK: Actions

    private func pick(_ option: String) {
        guard myPickForCursor == nil, !sending, cursor < totalRounds else { return }
        sending = true
        Haptics.shared.tap()
        Task {
            let data = GameEngine.moveData(kind: "pick", round: cursor, value: option)
            _ = await engine.sendMove(api: appState.api, data: data)
            sending = false
        }
    }

    private func advance() {
        guard complete(round: cursor) else { return }
        withAnimation(reduceMotion ? nil : Theme.Motion.settle) {
            cursor += 1
        }
        if cursor >= totalRounds {
            maybeFinish()
        }
    }

    private func handleReveal(_ state: RevealState) {
        switch state {
        case .match:
            SoundEngine.shared.play(.sparkle)
            Haptics.shared.success()
            GamesA11y.announce(L10n.t("games.choice.match"))
            flashHearts()
        case .different:
            SoundEngine.shared.play(.pop)
            Haptics.shared.tap()
            GamesA11y.announce(L10n.t("games.choice.noMatch"))
        case .none:
            break
        }
    }

    private func flashHearts() {
        guard !reduceMotion else { return }
        heartsVisible = true
        heartsTask?.cancel()
        heartsTask = Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if !Task.isCancelled {
                heartsVisible = false
            }
        }
    }

    private func maybeFinish() {
        guard allComplete, let current = session, current.state == "active", !didSendEnd else { return }
        didSendEnd = true
        Task {
            let result = JSONValue.object([
                "matches": .number(Double(matchCount)),
                "rounds": .number(Double(totalRounds))
            ])
            await engine.end(api: appState.api, result: result)
        }
    }

    // MARK: Couch mode (Welle 7 [W6-Rest] — pass-and-play on one phone)

    /// Deck of the running couch game — own seed, engine untouched.
    private var couchPairs: [ChoicePair] {
        let source = isWouldYouRather ? ContentPack.wouldYouRather : ContentPack.thisOrThat
        return Array(source.seededShuffled(seed: couchSeed).prefix(couch?.totalRounds ?? 0))
    }

    /// Couch player 0 is me, player 1 the partner (ToD-local convention).
    private func couchMember(_ player: Int) -> Member? {
        player == 0 ? appState.me : appState.partner
    }

    private func couchName(_ player: Int) -> String {
        player == 0 ? (appState.me?.name ?? L10n.t("common.you")) : appState.partnerName
    }

    @ViewBuilder
    private func couchContent(_ state: ThisOrThatCouchState) -> some View {
        switch state.phase {
        case .finished:
            couchEndScreen(state)
        case .handoff:
            couchHandoffScreen(state)
        case .firstPick, .secondPick, .reveal:
            couchPlayScreen(state)
        }
    }

    private func couchPlayScreen(_ state: ThisOrThatCouchState) -> some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(14)) {
                roundHeader(round: state.round, total: state.totalRounds,
                            matches: state.matches)
                GameProgressBar(progress: Double(min(state.round, state.totalRounds))
                                / Double(max(state.totalRounds, 1)),
                                tint: coupleTint.blend,
                                track: Papier.nachtInnenFill)
                couchRoundCard(state)
            }
            .padding(LayoutMetrics.s(16))
            .contentColumn(.reading)
        }
    }

    @ViewBuilder
    private func couchRoundCard(_ state: ThisOrThatCouchState) -> some View {
        if state.round < couchPairs.count {
            let pair = couchPairs[state.round]
            VStack(spacing: LayoutMetrics.s(14)) {
                if let picker = ThisOrThatCouch.currentPicker(state) {
                    couchTurnHeader(picker)
                }
                if isWouldYouRather {
                    Text(L10n.t("games.wyr.prefix"))
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Wachs.rot)
                }
                couchOptionCard(state, option: "a", text: pair.a.resolved(L10n.lang))
                Text(L10n.t("games.choice.or"))
                    .font(.system(.caption, design: .rounded).weight(.heavy))
                    .foregroundStyle(Tinte.tertiaer)
                couchOptionCard(state, option: "b", text: pair.b.resolved(L10n.lang))
                couchFooter(state)
            }
            .frame(maxWidth: .infinity)
            .paperCard()
        }
    }

    /// Whose secret pick is asked for right now — avatar + name, so the
    /// phone knows who should be holding it.
    private func couchTurnHeader(_ player: Int) -> some View {
        HStack(spacing: LayoutMetrics.s(10)) {
            EmojiAvatarView(emoji: couchMember(player)?.avatar,
                            colorHex: couchMember(player)?.color,
                            size: LayoutMetrics.s(30))
            Text(L10n.t("games.choice.couch.turn", ["name": couchName(player)]))
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Tinte.dunkel)
                .multilineTextAlignment(.center)
        }
    }

    /// Option card in couch mode: while picking, NOTHING is highlighted
    /// (the pick stays secret until the reveal); on the reveal both
    /// players' chips appear on their choices.
    private func couchOptionCard(_ state: ThisOrThatCouchState,
                                 option: String, text: String) -> some View {
        let revealed = state.phase == .reveal
        let pickedBy = revealed
            ? [0, 1].filter { ThisOrThatCouch.pick(of: $0, in: state) == option }
            : []
        return Button {
            couchPick(option)
        } label: {
            VStack(spacing: 8) {
                Text(text)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Tinte.dunkel)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if !pickedBy.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(pickedBy, id: \.self) { player in
                            HStack(spacing: 4) {
                                EmojiAvatarView(emoji: couchMember(player)?.avatar,
                                                colorHex: couchMember(player)?.color,
                                                size: 22)
                                Text(couchName(player))
                                    .font(.system(.caption2, design: .rounded).weight(.bold))
                                    .foregroundStyle(Tinte.sekundaer)
                            }
                            .padding(.vertical, 3)
                            .padding(.horizontal, 8)
                            .background(
                                Capsule().fill(Papier.brief)
                                    .overlay(Capsule().strokeBorder(Papier.kante,
                                                                    lineWidth: Theme.hairlineWidth))
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LayoutMetrics.s(18))
            .padding(.horizontal, LayoutMetrics.s(14))
            .background(
                RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                    .fill(!pickedBy.isEmpty ? coupleTint.tinte.opacity(0.16) : Papier.innenFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                    .strokeBorder(!pickedBy.isEmpty ? coupleTint.tinte : Papier.kante,
                                  lineWidth: !pickedBy.isEmpty ? 1.5 : Theme.hairlineWidth)
            )
        }
        .buttonStyle(.plain)
        .disabled(revealed)
        .accessibilityValue(pickedBy.isEmpty ? ""
                            : L10n.t("games.choice.a11y.pickedBy",
                                     ["names": pickedBy.map(couchName).joined(separator: ", ")]))
    }

    @ViewBuilder
    private func couchFooter(_ state: ThisOrThatCouchState) -> some View {
        if state.phase == .reveal {
            VStack(spacing: LayoutMetrics.s(10)) {
                Text(ThisOrThatCouch.isMatch(state)
                     ? L10n.t("games.choice.match")
                     : L10n.t("games.choice.noMatch"))
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .foregroundStyle(ThisOrThatCouch.isMatch(state)
                                     ? coupleTint.tinte : Tinte.sekundaer)
                if isWouldYouRather {
                    Text(L10n.t("games.wyr.discuss"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Tinte.sekundaer)
                }
                Button {
                    couchAdvance()
                } label: {
                    Text(L10n.t("games.next"))
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.top, 4)
        }
    }

    /// The screen that keeps the secret while the phone changes hands —
    /// the receiving player's avatar is the hero.
    private func couchHandoffScreen(_ state: ThisOrThatCouchState) -> some View {
        let receiver = 1 - ThisOrThatCouch.firstPicker(state)
        return ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                EmojiAvatarView(emoji: couchMember(receiver)?.avatar,
                                colorHex: couchMember(receiver)?.color,
                                size: LayoutMetrics.s(62))
                Text(L10n.t("games.choice.couch.handoff.title"))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                Text(L10n.t("games.choice.couch.handoff.body",
                            ["name": couchName(receiver)]))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    couchConfirmHandoff()
                } label: {
                    Text(L10n.t("games.choice.couch.handoff.cta",
                                ["name": couchName(receiver)]))
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .frame(maxWidth: .infinity)
            .nightCard(padding: .hero)
            .padding(LayoutMetrics.s(16))
            .contentColumn(.reading)
        }
    }

    private func couchEndScreen(_ state: ThisOrThatCouchState) -> some View {
        endContent(matches: state.matches, rounds: state.totalRounds) {
            startCouch()
        }
        .onAppear {
            celebrateEnd(matches: state.matches, rounds: state.totalRounds)
        }
    }

    // MARK: Couch actions

    private func startCouch() {
        couchSeed = Int.random(in: 0..<1_000_000)
        endCelebrated = false
        heartsVisible = false
        sharing = false
        shared = false
        withAnimation(reduceMotion ? nil : Theme.Motion.settle) {
            couch = ThisOrThatCouch.start(rounds: Self.defaultRounds,
                                          startingPlayer: Int.random(in: 0...1))
        }
        SoundEngine.shared.play(.pop)
        Haptics.shared.tap()
    }

    private func exitCouch() {
        withAnimation(reduceMotion ? nil : Theme.Motion.settle) {
            couch = nil
        }
    }

    private func couchPick(_ option: String) {
        guard let state = couch, ThisOrThatCouch.currentPicker(state) != nil else { return }
        let next = ThisOrThatCouch.pick(state, option: option)
        withAnimation(reduceMotion ? nil : Theme.Motion.settle) {
            couch = next
        }
        if next.phase == .reveal {
            // Second pick lands = the round's reveal — same cues as live.
            handleReveal(ThisOrThatCouch.isMatch(next) ? .match : .different)
        } else {
            Haptics.shared.tap()
        }
    }

    private func couchConfirmHandoff() {
        guard let state = couch else { return }
        withAnimation(reduceMotion ? nil : Theme.Motion.settle) {
            couch = ThisOrThatCouch.confirmHandoff(state)
        }
        Haptics.shared.tap()
    }

    private func couchAdvance() {
        guard let state = couch else { return }
        withAnimation(reduceMotion ? nil : Theme.Motion.settle) {
            couch = ThisOrThatCouch.advance(state)
        }
    }

    // MARK: End screen (shared by live and couch mode)

    private static func percent(matches: Int, rounds: Int) -> Int {
        guard rounds > 0 else { return 0 }
        return Int((Double(matches) / Double(rounds) * 100).rounded())
    }

    private static func flavor(percent: Int) -> String {
        if percent >= 90 { return L10n.t("games.choice.end.soulmates") }
        if percent >= 65 { return L10n.t("games.choice.end.great") }
        if percent >= 40 { return L10n.t("games.choice.end.ok") }
        return L10n.t("games.choice.end.spicy")
    }

    private var endScreen: some View {
        endContent(matches: matchCount, rounds: totalRounds) {
            startGame()
        }
        .onAppear {
            maybeFinish()
            celebrateEnd(matches: matchCount, rounds: totalRounds)
        }
    }

    private func endContent(matches: Int, rounds: Int,
                            rematch: @escaping () -> Void) -> some View {
        let percent = Self.percent(matches: matches, rounds: rounds)
        return ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                Image(systemName: percent >= 65 ? "heart.circle.fill" : "hands.clap.fill")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(percent >= 65 ? Licht.lampengold : coupleTint.blend)
                    .background(percent >= 65 ? VerdictLampenschein() : nil)
                    .accessibilityHidden(true)
                Text(L10n.t("games.choice.end.title"))
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(Papier.aufNacht)
                // The hero percentage glows in the lamp gold — the night
                // panel's one warm anchor.
                Text("\(percent)%")
                    .font(Typo.hero)
                    .foregroundStyle(Licht.lampengold)
                Text(L10n.t("games.choice.end.summary",
                            ["n": String(matches), "total": String(rounds)]))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Nacht.sekundaer)
                Text(Self.flavor(percent: percent))
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Licht.glut)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                shareButton(matches: matches, rounds: rounds)
                Button {
                    rematch()
                } label: {
                    Text(L10n.t("games.rematch"))
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(engine.busy)
            }
            .frame(maxWidth: .infinity)
            .nightCard(padding: .hero)
            .padding(LayoutMetrics.s(16))
            .contentColumn(.reading)
        }
    }

    // MARK: Share to chat

    @ViewBuilder
    private func shareButton(matches: Int, rounds: Int) -> some View {
        if appState.api != nil {
            Button {
                shareToChat(matches: matches, rounds: rounds)
            } label: {
                if sharing {
                    ProgressView()
                        .tint(Nacht.sekundaer)
                } else {
                    Label(L10n.t(shared ? "games.sharedToChat" : "games.shareToChat"),
                          systemImage: shared ? "checkmark" : "paperplane.fill")
                }
            }
            .buttonStyle(.plain)
            .font(.system(.footnote, design: .rounded).weight(.bold))
            .foregroundStyle(Licht.lampengold)
            .disabled(sharing || shared)
        }
    }

    /// Posts the match result into the couple chat (Wordle/ToD pattern).
    private func shareText(matches: Int, rounds: Int) -> String {
        let game = (isWouldYouRather ? "🤯 " : "⚡️ ") + L10n.t("games.card.\(kind.rawValue).title")
        let header = L10n.t("games.share.header", ["game": game])
        let percent = Self.percent(matches: matches, rounds: rounds)
        let summary = "\(percent)% · " + L10n.t("games.choice.end.summary",
                                                ["n": String(matches),
                                                 "total": String(rounds)])
        return header + "\n" + summary + "\n" + Self.flavor(percent: percent)
    }

    private func shareToChat(matches: Int, rounds: Int) {
        guard let api = appState.api, !sharing, !shared else { return }
        sharing = true
        Haptics.shared.tap()
        let text = shareText(matches: matches, rounds: rounds)
        Task {
            do {
                try await api.sendMessage(type: .text, text: text)
                shared = true
                SoundEngine.shared.play(.pop)
                Haptics.shared.success()
                appState.showToast(L10n.t("games.sharedToChat"), style: .success)
            } catch {
                appState.handleAPIError(error)
            }
            sharing = false
        }
    }

    private func celebrateEnd(matches: Int, rounds: Int) {
        guard !endCelebrated else { return }
        endCelebrated = true
        // No winner here — the shared completion is the normal-tier moment.
        GameEndCelebration.tie(visual: .localHearts)
        let percent = Self.percent(matches: matches, rounds: rounds)
        GamesA11y.announce(L10n.t("games.choice.end.summary",
                                  ["n": String(matches), "total": String(rounds)])
                           + ". " + Self.flavor(percent: percent))
        flashHearts()
    }
}
