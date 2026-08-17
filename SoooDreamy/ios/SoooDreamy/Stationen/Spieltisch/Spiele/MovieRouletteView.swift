import SwiftUI
import Combine

// Film-Roulette 🍿 — both partners swipe the same seeded movie deck; a card
// you BOTH like becomes a match. The relay derives the `movie_match` app
// event SERVER-SIDE from the stored likes — the completing swipe's
// `match: {cardIndex, title}` annotation only contributes the deck title.
// The match overlay and end screen turn matches into REAL week-plan slots
// via the 1-tap "Filmabend planen" CTA (MovieNightLogic.swift).
// Reducer: Content/MovieRouletteLogic.swift.
struct MovieRouletteView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint

    let engine: GameEngine

    @State private var customTitles: [String] = []
    @State private var customInput = ""
    @State private var dragOffset: CGSize = .zero
    @State private var sending = false
    @State private var didSendEnd = false
    @State private var celebrated = false
    @State private var seenMatches = 0
    @State private var matchBanner: String?
    @State private var matchBannerTask: Task<Void, Never>?
    /// Film→Wochenplan: titles already turned into a week-plan slot
    /// this session (drives the "geplant ✓" state) + in-flight guard.
    @State private var plannedTitles: Set<String> = []
    @State private var planningTitle: String?

    var body: some View {
        ZStack {
            DreamyBackground()
            content
            if let banner = matchBanner {
                matchOverlay(title: banner)
            }
        }
        .navigationTitle(L10n.t("games.card.movieroulette.title"))
        .navigationBarTitleDisplayMode(.inline)
        .gameForfeitToolbar(engine: engine)
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
            seenMatches = gameState.matches.count
        }
        .onChange(of: engine.session?.id) { _, _ in
            resetLocalState()
            seenMatches = gameState.matches.count
        }
        .onChange(of: gameState.matches.count) { old, new in
            if new > old, let index = gameState.matches.last {
                announceMatch(index: index)
            }
            seenMatches = new
        }
        .onChange(of: finished) { _, isDone in
            if isDone { handleFinish() }
        }
        .onAppear {
            if finished { handleFinish() }
        }
    }

    // MARK: Derived state

    private var session: GameSession? {
        guard let current = engine.session, current.kind == .movieroulette else { return nil }
        return current
    }

    private var starterId: String { session?.createdBy ?? "" }

    private var otherId: String {
        appState.couple?.members.map(\.id).first { $0 != starterId } ?? ""
    }

    private var myId: String { appState.memberId ?? "" }

    private var theirId: String { myId == starterId ? otherId : starterId }

    private var payloadCustom: [String] {
        session?.payload?["custom"]?.arrayValue?.compactMap(\.stringValue) ?? []
    }

    private var deck: [MovieCard] {
        MovieRoulette.deck(seed: engine.seed,
                           size: engine.payloadInt("size", default: MovieRoulette.defaultDeckSize),
                           custom: payloadCustom)
    }

    private var events: [MovieRouletteEvent] {
        engine.orderedMoves.compactMap { move in
            guard move.data["kind"]?.stringValue == "swipe",
                  let index = move.data["index"]?.intValue,
                  let like = move.data["like"]?.boolValue else { return nil }
            return .swipe(member: move.memberId, index: index, like: like)
        }
    }

    private var gameState: MovieRouletteState {
        MovieRoulette.reduce(events: events, deckSize: deck.count)
    }

    private var finished: Bool {
        guard session?.state == "active" || session?.state == "ended" else { return false }
        return gameState.finished(deckSize: deck.count, members: [starterId, otherId])
    }

    // MARK: Content switch

    @ViewBuilder
    private var content: some View {
        if appState.partner == nil {
            GameNeedsPartnerView()
        } else if let session {
            if session.state == "lobby" {
                ScrollView {
                    GameLobbyView(engine: engine, accent: coupleTint.blend)
                        .padding(LayoutMetrics.s(16))
                }
            } else if finished {
                endScreen
            } else if session.state == "active" {
                swipeScreen
            } else {
                setupScreen
            }
        } else {
            setupScreen
        }
    }

    // MARK: Setup (custom entries live here)

    private var setupScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                Image(systemName: "popcorn.fill")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(coupleTint.blend)
                    .accessibilityHidden(true)
                Text(L10n.t("games.card.movieroulette.teaser"))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                    .multilineTextAlignment(.center)
                Text(L10n.t("games.mr.setup.body"))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                customEntryEditor
                Button {
                    startGame()
                } label: {
                    Text(L10n.t("games.start"))
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(engine.busy)
            }
            .nightCard(padding: .hero)
            .padding(LayoutMetrics.s(16))
            .contentColumn(.reading)
        }
    }

    private var customEntryEditor: some View {
        VStack(spacing: LayoutMetrics.s(10)) {
            HStack(spacing: LayoutMetrics.s(8)) {
                TextField(L10n.t("games.mr.custom.placeholder"), text: $customInput)
                    .textFieldStyle(.plain)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Papier.aufNacht)
                    .submitLabel(.done)
                    .onSubmit(addCustomTitle)
                Button {
                    addCustomTitle()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(.title3, design: .rounded))
                        .foregroundStyle(coupleTint.blend)
                }
                .buttonStyle(.plain)
                .disabled(customInput.trimmingCharacters(in: .whitespaces).isEmpty
                          || customTitles.count >= 5)
            }
            .padding(.horizontal, LayoutMetrics.s(12))
            .padding(.vertical, LayoutMetrics.s(8))
            .background(
                RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                    .fill(Papier.nachtInnenFill)
                    .overlay(RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                        .strokeBorder(Nacht.naht, lineWidth: Theme.hairlineWidth))
            )
            if !customTitles.isEmpty {
                FlexibleChips(titles: customTitles) { title in
                    customTitles.removeAll { $0 == title }
                }
            }
            Text(L10n.t("games.mr.custom.hint"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Nacht.tertiaer)
                .multilineTextAlignment(.center)
        }
    }

    private func addCustomTitle() {
        let title = customInput.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, customTitles.count < 5, !customTitles.contains(title) else { return }
        customTitles.append(title)
        customInput = ""
        Haptics.shared.tap()
    }

    private func startGame() {
        guard !engine.busy else { return }
        let custom = customTitles
        Task {
            resetLocalState()
            // The seed comes from the server (fairness contract).
            var payload: [String: JSONValue] = [
                "size": .number(Double(MovieRoulette.defaultDeckSize))
            ]
            if !custom.isEmpty {
                payload["custom"] = .array(custom.map { .string($0) })
            }
            if await engine.create(api: appState.api, type: .movieroulette,
                                   payload: .object(payload)) {
                SoundEngine.shared.play(.pop)
                Haptics.shared.tap()
            }
        }
    }

    private func resetLocalState() {
        dragOffset = .zero
        sending = false
        didSendEnd = false
        celebrated = false
        matchBanner = nil
        matchBannerTask?.cancel()
        matchBannerTask = nil
        plannedTitles = []
        planningTitle = nil
    }

    // MARK: Swiping

    private var swipeScreen: some View {
        VStack(spacing: LayoutMetrics.s(14)) {
            progressHeader
            if let index = gameState.nextIndex(of: myId, deckSize: deck.count) {
                cardStack(topIndex: index)
                swipeButtons(index: index)
            } else {
                doneWaitingCard
            }
            Spacer(minLength: 0)
        }
        .gameActGated()
        .padding(LayoutMetrics.s(16))
        .contentColumn(.reading)
    }

    private var progressHeader: some View {
        HStack(spacing: LayoutMetrics.s(10)) {
            Image(systemName: "popcorn.fill")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Licht.lampengold)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.t("games.mr.progress",
                            ["n": "\(gameState.swipeCount(of: myId))", "total": "\(deck.count)"]))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                Text(L10n.t("games.mr.partnerProgress",
                            ["name": appState.partnerName,
                             "n": "\(gameState.swipeCount(of: theirId))",
                             "total": "\(deck.count)"]))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
            }
            Spacer(minLength: 0)
            PillTag(text: L10n.t("games.mr.matches", ["n": "\(gameState.matches.count)"]),
                    tint: coupleTint.blend)
        }
        .nightCard(grain: false)
    }

    private func cardStack(topIndex: Int) -> some View {
        ZStack {
            // A peek of the next card underneath.
            if topIndex + 1 < deck.count {
                movieCardView(deck[topIndex + 1])
                    .scaleEffect(0.94)
                    .offset(y: LayoutMetrics.s(12))
                    .opacity(0.6)
            }
            movieCardView(deck[topIndex])
                .offset(dragOffset)
                .rotationEffect(.degrees(Double(dragOffset.width) / 18))
                .overlay(swipeHintOverlay)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation
                        }
                        .onEnded { value in
                            if value.translation.width > 90 {
                                swipe(index: topIndex, like: true)
                            } else if value.translation.width < -90 {
                                swipe(index: topIndex, like: false)
                            } else {
                                withAnimation(Theme.Motion.settle) {
                                    dragOffset = .zero
                                }
                            }
                        }
                )
        }
        .animation(Theme.Motion.settle, value: dragOffset == .zero)
    }

    /// Like/pass stamps pressed onto the paper card while dragging — the
    /// approval in couple ink, the pass in plain ink.
    @ViewBuilder
    private var swipeHintOverlay: some View {
        if dragOffset.width > 40 {
            swipeStamp(symbol: "heart.fill", tint: coupleTint.tinte, angle: -12)
        } else if dragOffset.width < -40 {
            swipeStamp(symbol: "hand.wave.fill", tint: Tinte.sekundaer, angle: 12)
        }
    }

    private func swipeStamp(symbol: String, tint: Color, angle: Double) -> some View {
        Image(systemName: symbol)
            .font(.system(.largeTitle, design: .rounded).weight(.semibold))
            .foregroundStyle(tint)
            .padding(LayoutMetrics.s(12))
            .background(Circle().fill(tint.opacity(0.25)))
            .rotationEffect(.degrees(angle))
            .allowsHitTesting(false)
    }

    private func movieCardView(_ card: MovieCard) -> some View {
        VStack(spacing: LayoutMetrics.s(16)) {
            Spacer(minLength: 0)
            Text(card.emoji)
                .font(.system(.largeTitle, design: .rounded))
            Text(card.title(lang: L10n.lang))
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .foregroundStyle(Tinte.dunkel)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
            PaperTag(text: L10n.t("games.mr.genre.\(card.genre)"), ink: coupleTint.tinte)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: LayoutMetrics.s(320))
        .paperCard(padding: .hero)
    }

    private func swipeButtons(index: Int) -> some View {
        HStack(spacing: LayoutMetrics.s(40)) {
            Button {
                swipe(index: index, like: false)
            } label: {
                Image(systemName: "hand.wave.fill")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundStyle(Nacht.sekundaer)
                    .frame(width: LayoutMetrics.s(64), height: LayoutMetrics.s(64))
                    .background(Circle().fill(Papier.nachtInnenFill))
            }
            .buttonStyle(.plain)
            Button {
                swipe(index: index, like: true)
            } label: {
                Image(systemName: "heart.fill")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .foregroundStyle(coupleTint.onBlend)
                    .frame(width: LayoutMetrics.s(64), height: LayoutMetrics.s(64))
                    .background(Circle().fill(coupleTint.blend))
            }
            .buttonStyle(.plain)
        }
        .disabled(sending)
    }

    private var doneWaitingCard: some View {
        VStack(spacing: LayoutMetrics.s(12)) {
            Image(systemName: "film.fill")
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(coupleTint.blend)
                .accessibilityHidden(true)
            Text(L10n.t("games.mr.doneWaiting", ["name": appState.partnerName]))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
                .multilineTextAlignment(.center)
            ProgressView()
                .tint(Nacht.sekundaer)
        }
        .frame(maxWidth: .infinity)
        .nightCard(padding: .hero)
    }

    private func swipe(index: Int, like: Bool) {
        guard !sending else { return }
        sending = true
        withAnimation(Theme.Motion.settle) {
            dragOffset = CGSize(width: like ? 500 : -500, height: -40)
        }
        SoundEngine.shared.play(like ? .pop : .click)
        Haptics.shared.tap()
        let completes = like && MovieRoulette.completesMatch(state: gameState,
                                                             index: index, partner: theirId)
        Task {
            var data: [String: JSONValue] = [
                "kind": .string("swipe"),
                "index": .number(Double(index)),
                "like": .bool(like)
            ]
            if completes, deck.indices.contains(index) {
                // The completing client annotates the match → the relay
                // emits the movie_match app event (weekly-plan hook).
                data["match"] = .object([
                    "cardIndex": .number(Double(index)),
                    "title": .string(deck[index].title(lang: L10n.lang))
                ])
            }
            _ = await engine.sendMove(api: appState.api, data: .object(data))
            dragOffset = .zero
            sending = false
        }
    }

    // MARK: Match announcement

    private func announceMatch(index: Int) {
        guard deck.indices.contains(index) else { return }
        matchBanner = deck[index].title(lang: L10n.lang)
        // R1-D: the match moment blooms in the app-wide Lichtschein
        // instead of confetti; the fanfare stays the ear's half.
        AppCue.fanfareMedium.play()
        LichtscheinCenter.shared.fire()
        // Auto-dismiss after a while unless the couple is using the CTA.
        matchBannerTask?.cancel()
        matchBannerTask = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            withAnimation(Theme.Motion.settle) {
                matchBanner = nil
            }
        }
    }

    private func dismissMatchBanner() {
        matchBannerTask?.cancel()
        matchBannerTask = nil
        withAnimation(Theme.Motion.settle) {
            matchBanner = nil
        }
    }

    /// The match celebration with a REAL "plan movie night" CTA:
    /// one tap creates a week-plan slot — "saved" only appears after the
    /// server confirmed it.
    private func matchOverlay(title: String) -> some View {
        VStack(spacing: LayoutMetrics.s(10)) {
            Image(systemName: "popcorn.fill")
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Licht.lampengold)
                .background(VerdictLampenschein())
                .accessibilityHidden(true)
            Text(L10n.t("games.mr.match.banner"))
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(Papier.aufNacht)
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Licht.lampengold)
            if plannedTitles.contains(title) {
                PillTag(text: L10n.t("games.mr.plan.done"), tint: Licht.glut)
            } else {
                Button {
                    planMovieNight(title: title)
                } label: {
                    if planningTitle == title {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(L10n.t("games.mr.plan.cta"))
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(planningTitle != nil)
            }
            Button(L10n.t("games.mr.plan.later")) {
                dismissMatchBanner()
            }
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(Nacht.tertiaer)
        }
        .padding(LayoutMetrics.s(24))
        .frame(maxWidth: LayoutMetrics.s(320))
        .glass(.chrome, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: Film → Wochenplan (EVAL-3.0 P0-3)

    /// 1-tap movie night: creates a REAL week-plan slot (kind `movie`) on the
    /// first day both have time (else next Saturday). Success is only shown
    /// AFTER the server confirmed the slot.
    private func planMovieNight(title: String) {
        guard let api = appState.api, planningTitle == nil else { return }
        planningTitle = title
        Haptics.shared.tap()
        Task {
            defer { planningTitle = nil }
            do {
                let overlapDays = (try? await api.weekplan())?.days
                    .filter(\.overlap).map(\.dateKey) ?? []
                let dateKey = MovieNight.slotDateKey(overlapDateKeys: overlapDays)
                _ = try await api.addWeekplanSlot(title: title, emoji: "🍿", kind: "movie",
                                                  dateKey: dateKey, weekday: nil, time: nil)
                plannedTitles.insert(title)
                SoundEngine.shared.play(.sparkle)
                Haptics.shared.success()
                appState.showToast(L10n.t("games.mr.plan.toast", ["day": Self.dayLabel(dateKey)]),
                                   style: .success)
                dismissMatchBanner()
            } catch {
                appState.handleAPIError(error)
            }
        }
    }

    /// "Sa, 15.8." — how the plan toast names the chosen day.
    private static func dayLabel(_ dateKey: String) -> String {
        guard let date = SharedDates.parse(dateKey) else { return dateKey }
        let weekday = SharedDates.calendar.component(.weekday, from: date) - 1 // L10n keys: 0=Su…6=Sa
        let shortDate = AppFormatters.dateTemplate(date, template: "d.M.", language: L10n.lang)
        return L10n.t("weekday.\(weekday)") + ", " + shortDate
    }

    // MARK: Finish

    private func handleFinish() {
        guard session != nil else { return }
        if !celebrated {
            celebrated = true
            if gameState.matches.isEmpty {
                SoundEngine.shared.play(.chime)
            } else {
                // A found movie night is the couple's shared match win.
                GameEndCelebration.win(theme: .hearts)
            }
        }
        guard let current = session, current.state == "active", !didSendEnd else { return }
        didSendEnd = true
        Task {
            let titles = gameState.matches.compactMap { index in
                deck.indices.contains(index) ? deck[index].title(lang: L10n.lang) : nil
            }
            await engine.end(api: appState.api, result: .object([
                "matches": .array(titles.map { .string($0) })
            ]))
        }
    }

    private var endScreen: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.s(16)) {
                Image(systemName: gameState.matches.isEmpty
                      ? "questionmark.circle.fill" : "popcorn.fill")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(gameState.matches.isEmpty ? Nacht.sekundaer : Licht.lampengold)
                    .background(gameState.matches.isEmpty ? nil : VerdictLampenschein())
                    .accessibilityHidden(true)
                Text(gameState.matches.isEmpty
                     ? L10n.t("games.mr.end.none")
                     : L10n.t("games.mr.end.some", count: gameState.matches.count))
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(Papier.aufNacht)
                    .multilineTextAlignment(.center)
                if !gameState.matches.isEmpty {
                    matchList
                    Text(L10n.t("games.mr.end.planHint"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Nacht.tertiaer)
                        .multilineTextAlignment(.center)
                }
                Button {
                    startGame()
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

    private var matchList: some View {
        VStack(spacing: LayoutMetrics.s(8)) {
            ForEach(gameState.matches, id: \.self) { index in
                if deck.indices.contains(index) {
                    let title = deck[index].title(lang: L10n.lang)
                    HStack(spacing: LayoutMetrics.s(10)) {
                        Text(deck[index].emoji)
                            .font(.system(.title2, design: .rounded))
                        Text(title)
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(Papier.aufNacht)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                        if plannedTitles.contains(title) {
                            PillTag(text: L10n.t("games.mr.plan.done"),
                                    tint: coupleTint.blend)
                        } else if planningTitle == title {
                            ProgressView()
                                .tint(Nacht.sekundaer)
                        } else {
                            // 1-tap week-plan slot for THIS match.
                            Button {
                                planMovieNight(title: title)
                            } label: {
                                Label(L10n.t("games.mr.plan.short"), systemImage: "calendar.badge.plus")
                                    .font(.system(.caption, design: .rounded).weight(.bold))
                                    .foregroundStyle(Licht.lampengold)
                                    .padding(.horizontal, LayoutMetrics.s(10))
                                    .padding(.vertical, LayoutMetrics.s(6))
                                    .background(Capsule().fill(Licht.lampengold.opacity(0.14)))
                            }
                            .buttonStyle(.plain)
                            .disabled(planningTitle != nil)
                        }
                    }
                    .padding(.horizontal, LayoutMetrics.s(12))
                    .padding(.vertical, LayoutMetrics.s(8))
                    .background(
                        RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                            .fill(Papier.nachtInnenFill)
                    )
                }
            }
        }
    }
}

// MARK: - Chip flow layout (custom titles)

/// Simple wrapping chip row for the custom movie titles.
private struct FlexibleChips: View {
    let titles: [String]
    let onRemove: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: LayoutMetrics.s(110)), spacing: 6)],
                  spacing: 6) {
            ForEach(titles, id: \.self) { title in
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(Papier.aufNacht)
                        .lineLimit(1)
                    Button {
                        onRemove(title)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Nacht.tertiaer)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, LayoutMetrics.s(10))
                .padding(.vertical, LayoutMetrics.s(6))
                .background(
                    Capsule().fill(Papier.nachtInnenFill)
                        .overlay(Capsule().strokeBorder(Nacht.naht,
                                                        lineWidth: Theme.hairlineWidth))
                )
            }
        }
    }
}
