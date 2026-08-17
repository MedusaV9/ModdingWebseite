import SwiftUI
import Combine

// The Postfach root (Neubau §4.1) tells ONE story per delivery round:
// Kopf (header + Dienstlicht) → Zustellfach (Stempelzeile, seam, the ONE
// Briefbogen hero, ≤ 3 night delivery cards) → Ablage (the fold as
// Ablagekorb + heart coda). The heavy sections live in their own
// component files (W8A component split):
//   DashboardHeaderView  — avatars, shared days, mood/now-playing ambience
//   MissedInboxCard      — "while you were away" dramaturgy
//   DailyQuestionCard    — answer choreography + reveal ceremony launch
//   TelegrammLeiste      — send-love row (SF-symbol telegram strip)
//   PulseFan             — 💭 quick action + signature fan (in-flow row)
//   FlashbackCard        — memory of the day
//   WaitingForPartnerCard, MoodPickerSheet, TouchReceivedOverlay

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.coupleTint) private var coupleTint
    /// Regular width (iPad windows) lays the story cards out in two
    /// columns; compact keeps the phone's single column.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// AX composition (re-eval №9): at accessibility sizes the anniversary
    /// banner sorts behind the day hero and the pairing stage keeps its
    /// natural flow instead of the centering air.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var heartBurst = 0
    /// Scroll-visibility of the heart coda: starts false, so the SceneKit
    /// loop never runs before the coda was actually scrolled into view;
    /// leaving pauses it, re-entry reactivates (energy gate).
    @State private var heartCodaVisible = false
    @State private var showWhatsNew = false
    @State private var flashback: FlashbackItem?
    /// Today's deterministic "on this day" memories from the server.
    @State private var onThisDay: OnThisDayResponse?
    /// Today's check-in record — feeds the hero slot (morning ritual done?)
    /// and the resting state. Kept fresh via the `checkin` socket event.
    @State private var checkinToday: CheckinDay?
    /// Season-calendar doors addressed to us, kept as raw feeds (not a
    /// precomputed Bool) so the minute tick can re-ask "unlockable NOW?"
    /// without another network round-trip — a door flipping to ready
    /// mid-session climbs out of the fold on the next tick (FXC-4 #9).
    @State private var seasonDoorFeeds: [SeasonCalendarDoorFeed] = []
    /// Runden-Mengen-Modell (§4.6, Fix2-A №6): "{dateKey}#morgenpost,…" —
    /// ALL rounds already staged today, so a clock rollback never replays
    /// one (the set forgets nothing; ZustellrundenLogic owns the format).
    /// Controls ONLY Briefschlitz + Stempelzeile; the card ranking stays
    /// `DashboardPriority.layout`.
    @AppStorage("postfach.letzteInszenierung") private var letzteInszenierung = ""
    /// Amt → Zustelldienst → „Zustellrunden inszenieren" (§4.6, default on;
    /// off = static entry, the round stamp only reads "TAG {n}"). The flag
    /// already governs the stage here; the visible switch ships with the
    /// wave that owns the Amt files.
    @AppStorage("zustelldienst.rundenInszenieren") private var rundenInszenieren = true

    @AppStorage("dashboard.pinnedGroup") private var pinnedGroupRaw = ""
    @AppStorage("dashboard.hide.rituals") private var hideRituals = false
    @AppStorage("dashboard.hide.games") private var hideGames = false
    @AppStorage("dashboard.hide.moments") private var hideMoments = false
    @AppStorage("dashboard.expanded.more") private var moreExpanded = false
    /// The heart explains itself exactly once — afterwards it just beats.
    @AppStorage("home.heartHintDone") private var heartHintDone = false
    @AppStorage("whatsNew.lastPresentedVersion") private var lastPresentedVersion = ""

    var body: some View {
        NavigationStack {
            ZStack {
                // Redesign wave 1 (REDESIGN.md §2.1): the living room —
                // same room, same lamp, same dust, plus the Atemglühen
                // breathing in the couple's colors under the cone.
                AnimatedBackground()
                // Seasonal particles decorate ONLY the resting state — motion
                // must mean "something is here today", and when everything is
                // shared, calm may shimmer (Dossier 23, ideas 14/22).
                if SeasonSettings.particlesEnabled, let season = SeasonSettings.activeSeason,
                   isRestingToday {
                    SeasonParticlesView(season: season)
                }
                ScrollView {
                    VStack(spacing: Space.l) {
                        DashboardHeaderView()

                        if let inbox = appState.missedInbox, !inbox.isEmpty {
                            MissedInboxCard(inbox: inbox)
                        } else if appState.dismissedInbox != nil {
                            MissedUndoRow()
                        }

                        // AX sizes sort the anniversary banner BEHIND the
                        // day hero (DashboardPriority rule) — the grown
                        // head must not eat the first screen (re-eval №9).
                        if let milestone = monthiversary,
                           !DashboardPriority.jubilaeumHinterHero(
                               isAccessibilitySize: dynamicTypeSize.isAccessibilitySize) {
                            monthiversaryCard(milestone)
                        }

                        if appState.couple == nil {
                            sessionStateCard
                        } else if appState.partner == nil {
                            // Die tote Mitte (re-eval №4): a proportional
                            // breath of air lifts the sealed Sendung toward
                            // the pane's calm middle — a spacer, never a
                            // fixed frame, so grown type and the unfolded
                            // QR only push down instead of clipping. AX
                            // sizes keep the natural flow.
                            if !dynamicTypeSize.isAccessibilitySize {
                                Color.clear
                                    .containerRelativeFrame(.vertical) { length, _ in
                                        length * LayoutRules.sendungLuftAnteil
                                    }
                                    .accessibilityHidden(true)
                            }
                            WaitingForPartnerCard()
                        } else {
                            // Minute cadence: the door card's countdown
                            // already ticks — the RANK moves with it, so a
                            // door that becomes unlockable mid-session climbs
                            // into the visible budget on the next tick.
                            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                                VStack(spacing: Space.l) {
                                    pairedCards(now: timeline.date)
                                }
                            }
                        }
                    }
                    .padding(Space.l)
                    .contentColumn(.hub)
                }
                // Resting clearance above the bottom chrome, coupled to
                // the REAL chrome height (Fix2-A №2/№4): the 💭 pulse row
                // rides in the flow now, so only the glass matters — and
                // at AX sizes the accessory is unmounted, so grown type
                // gets that share back. While scrolling, content still
                // runs under the glass (system behavior).
                .contentMargins(
                    .bottom,
                    CGFloat(LayoutRules.postfachBottomClearance(
                        isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)),
                    for: .scrollContent)
                // Cards blur and dim softly under the bottom chrome
                // instead of cutting off hard — `.soft` is the deliberate
                // choice over the aurora (a hard line would slice the sky).
                .scrollEdgeEffectStyle(.soft, for: .bottom)
                .refreshable {
                    await appState.refreshAll()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView(version: appVersion)
        }
        .task(id: appState.couple?.id) {
            await loadMemories()
            await loadCheckinState()
            await loadSeasonDoorState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent else { return }
            if event.type == .seasonCalendarChanged {
                Task { await loadSeasonDoorState() }
                return
            }
            guard event.type == .checkin,
                  let payload = event.decode(CheckinEventPayload.self),
                  payload.day.dateKey == SharedDates.todayKey() else { return }
            checkinToday = payload.day
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // Foreground refresh: doors may have unlocked (or been opened on
            // the other device) while the app slept — the rank must know.
            // The Zustellrunde needs no reset here anymore: it derives from
            // the minute tick's `now` (re-eval №1), so foreground re-entry
            // and a round change in the visible tab share one honest path.
            Task { await loadSeasonDoorState() }
        }
        .onChange(of: RevealCeremony.shared.version) {
            // The seal just broke (or a ceremony was presented) — widgets
            // and the pulse activity must drop their gold seal right away.
            appState.updateWidgetSnapshot()
            CouplePulseController.updateFrom(appState)
        }
        .onChange(of: appState.pendingRevealRequest) {
            consumePendingRevealRequest()
        }
        .onChange(of: appState.dailyEntry?.bothAnswered) {
            // Cold start from a widget tap: the link arrives before the
            // daily entry — present as soon as the data lands.
            consumePendingRevealRequest()
        }
        .onAppear {
            consumePendingRevealRequest()
            // Demo mode (Welle 7 [29]): never burn the one-time What's-New
            // moment on staged content — it belongs to the real first run.
            guard !appState.demoActive,
                  !WhatsNewCatalog.entries(for: appVersion).isEmpty,
                  WhatsNewGate.shouldPresent(
                    currentVersion: appVersion,
                    lastPresentedVersion: lastPresentedVersion
                  ) else { return }
            lastPresentedVersion = appVersion
            showWhatsNew = true
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    // MARK: Hero slot + card budget (Dossier 23 #1/#2/#7/#22)

    private var hiddenGroups: Set<DashboardGroup> {
        Set(
            [(DashboardGroup.rituals, hideRituals),
             (.games, hideGames),
             (.moments, hideMoments)]
                .compactMap { $0.1 ? $0.0 : nil }
        )
    }

    /// A door addressed to me is unlockable at `now` — evaluated per
    /// minute-tick so the standalone door card's rank stays honest.
    private func seasonDoorReady(now: Date) -> Bool {
        SeasonDoorDashboard.nextDoor(in: seasonDoorFeeds, now: now)
            .map { $0.unlockAt <= now } ?? false
    }

    /// The Zustellrunde at `now` — a pure derivation from the minute
    /// tick's date (device-local hour, honesty contract documented in
    /// ZustellrundenLogic). Feeding the TimelineView date instead of a
    /// once-per-activation @State means a round change in the VISIBLE
    /// tab re-ranks and re-stages within a minute (re-eval №1) — the
    /// stage may change mid-look now, because that IS the delivery.
    private func runde(now: Date) -> Zustellrunde {
        Zustellrunde.from(hour: Calendar.current.component(.hour, from: now))
    }

    /// The whole page story: ONE hero, at most three cards, one "more" fold.
    private func dashboardLayout(now: Date) -> DashboardLayout {
        // Reading `version` re-ranks the page the instant a seal breaks.
        _ = RevealCeremony.shared.version
        let entry = appState.dailyEntry
        let quest = appState.quest
        let context = DashboardCardContext(
            runde: runde(now: now),
            morningCheckinDone: checkinToday?.checkedIn(appState.memberId, kind: "morning") ?? false,
            nightCheckinDone: checkinToday?.checkedIn(appState.memberId, kind: "night") ?? false,
            myDailyAnswered: entry?.myAnswer != nil,
            bothAnswered: entry?.bothAnswered == true,
            revealPending: DailyRevealLauncher.revealPending(appState: appState),
            hasOpenNeed: (appState.missedInbox?.needsCount ?? 0) > 0,
            gamesAwaitingMe: appState.gamesAwaitingMe.count,
            hasMemoryToday: (onThisDay?.items.isEmpty == false) || flashback != nil,
            hasUpcomingMoment: appState.nextEvent != nil,
            firstMomentPending: DashboardPriority.firstMomentPending(
                isNewCouple: quest?.isNewCouple ?? false,
                questDone: quest?.done ?? true,
                dailyStepDone: quest?.steps.first { $0.id == "daily" }?.done ?? false,
                touchStepDone: quest?.steps.first { $0.id == "touch" }?.done ?? false,
                myDailyAnswered: entry?.myAnswer != nil
            ),
            seasonDoorReady: seasonDoorReady(now: now)
        )
        return DashboardPriority.layout(
            context: context,
            pinned: DashboardGroup(rawValue: pinnedGroupRaw),
            hidden: hiddenGroups
        )
    }

    /// Everything shared today — lets the particles shimmer over the calm.
    private var isRestingToday: Bool {
        appState.couple != nil && appState.partner != nil
            && dashboardLayout(now: Date()).hero == .resting
    }

    // MARK: Zustellrunden-Bühne (Briefschlitz + Stempelzeile, §4.6)

    /// True exactly while the given round still has its one staging open
    /// on this device. Reading it never consumes the mark —
    /// BriefschlitzEntry writes it the moment the choreography plays.
    private func briefschlitzOffen(runde: Zustellrunde, now: Date) -> Bool {
        rundenInszenieren && ZustellrundenLogic.sollInszenieren(
            runde: runde,
            dateKey: SharedDates.todayKey(now),
            zuletzt: letzteInszenierung.isEmpty ? nil : letzteInszenierung)
    }

    /// The stamp line ON the hero paper: "MORGENPOST · TAG 137" while the
    /// rounds stage (the screen's ONE postal word rides here); before the
    /// shared-days count exists the round name stands alone. Rounds off:
    /// nil — the circular Poststempel keeps carrying "TAG {n}" as before.
    private func stempelzeile(runde: Zustellrunde) -> String? {
        guard rundenInszenieren else { return nil }
        guard let days = appState.daysTogether, days > 0 else {
            return L10n.t(runde.titleKey)
        }
        return L10n.t(runde.titleKey) + " · "
            + L10n.t("home.stamp.day", ["n": String(days)])
    }

    /// Whole VoiceOver sentence for the staging (§4.6):
    /// "Tagespost ist da: Frage des Tages."
    private func briefschlitzAnsage(_ hero: DashboardCard,
                                    runde: Zustellrunde) -> String {
        let titel = hero == .resting
            ? L10n.t("home.resting.title")
            : L10n.t("home.dailyQuestion")
        return L10n.t("postfach.briefschlitz.a11y",
                      ["runde": L10n.t(runde.titleKey), "titel": titel])
    }

    @ViewBuilder
    private func pairedCards(now: Date) -> some View {
        let layout = dashboardLayout(now: now)
        let runde = runde(now: now)
        let marke = ZustellrundenLogic.marke(dateKey: SharedDates.todayKey(now),
                                             runde: runde)
        // The hero arrives under the Zustellfach seam: ONCE per round it
        // glides through the Briefschlitz (§4.1 signature), every other
        // appearance keeps the Blättern entry (Reduce Motion: crossfade /
        // static Lichtschein). The choreography is BOUND to the round
        // mark (re-eval №1): a new round in the visible tab re-stages,
        // and the mark is written exactly when the staging plays — as
        // the day's WHOLE round set (`naechsteMarke`, Fix2-A №6), so a
        // clock rollback never replays an already-played round. The
        // story cards below land staggered (Legen). Nacht-first stage:
        // the ONE bright sheet gets extra air below — the dark night
        // cards keep their distance from the lamp-lit hero. The
        // first-moment stage stays its own ceremony and is never
        // re-staged by a delivery round.
        heroView(layout.hero, runde: runde)
            .briefschlitzEntry(
                marke: marke,
                inszeniert: briefschlitzOffen(runde: runde, now: now)
                    && layout.hero != .firstMoment,
                ansage: briefschlitzAnsage(layout.hero, runde: runde),
                onGespielt: {
                    letzteInszenierung = ZustellrundenLogic.naechsteMarke(
                        runde: runde,
                        dateKey: SharedDates.todayKey(now),
                        zuletzt: letzteInszenierung.isEmpty
                            ? nil : letzteInszenierung)
                })
            .padding(.bottom, Space.s)
        // AX sizes: the anniversary banner celebrates BEHIND the day
        // hero (DashboardPriority.jubilaeumHinterHero, re-eval №9).
        if let milestone = monthiversary,
           DashboardPriority.jubilaeumHinterHero(
               isAccessibilitySize: dynamicTypeSize.isAccessibilitySize) {
            monthiversaryCard(milestone)
        }
        if horizontalSizeClass == .regular, layout.visible.count > 1 {
            // Regular width: the story cards sit side by side — the hero
            // keeps the full column above them (its rank IS its width).
            // Two INDEPENDENT columns instead of a LazyVGrid: a grid row is
            // as tall as its tallest card, which carved ~200 pt holes under
            // short neighbors (iPad eval). Round 3 (FXD-2 #9): the height-
            // weighted split alone still left the right column ~330 pt
            // short when the rituals mega-block held one side — light
            // cards from the "more" fold now move up into the shorter
            // column until the heights genuinely meet; the fold keeps the
            // rest. Compact (phone) layouts are untouched below.
            let balanced = DashboardPriority.balancedColumns(
                visible: layout.visible,
                more: layout.more
            )
            HStack(alignment: .top, spacing: Space.l) {
                LazyVStack(spacing: Space.l) {
                    ForEach(Array(balanced.left.enumerated()), id: \.element) { index, card in
                        cardView(card)
                            .frame(maxWidth: .infinity)
                            .legenEntry(index: index)
                    }
                }
                LazyVStack(spacing: Space.l) {
                    ForEach(Array(balanced.right.enumerated()), id: \.element) { index, card in
                        cardView(card)
                            .frame(maxWidth: .infinity)
                            .legenEntry(index: index)
                    }
                }
            }
            if !balanced.more.isEmpty {
                moreGroup(balanced.more)
            }
        } else {
            ForEach(Array(layout.visible.enumerated()), id: \.element) { index, card in
                cardView(card)
                    .legenEntry(index: index)
            }
            if !layout.more.isEmpty {
                moreGroup(layout.more)
            }
        }
        // Fix2-A №2: the 💭 pulse quick action rides IN the flow — a
        // trailing row under the last card, above the heart coda —
        // instead of floating over the scroll content, where it covered
        // interactive elements in every seed (AX5: the plus chip;
        // reveal/demo: the haptic-studio chevron). The unfolded fan now
        // grows the row instead of overlaying cards.
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            PulseFan()
        }
        heartCoda
    }

    /// The hero slot: the day hero (FirstMoment/DailyQuestion) is THE
    /// Briefbogen of the screen — band, wax, and (while the rounds stage)
    /// the Stempelzeile "MORGENPOST · TAG 137" as its printed head. Since
    /// re-eval №2 the day letter is ALWAYS the stamped hero of a paired
    /// screen (the check-in became the first dark card below), so the
    /// stamp line rides the paper in every pair state — the resting
    /// reward stays the one stamp-free hero (night card, paper-only law).
    @ViewBuilder
    private func heroView(_ card: DashboardCard, runde: Zustellrunde) -> some View {
        switch card {
        case .firstMoment:
            FirstMomentCard(rundenStempel: stempelzeile(runde: runde))
        case .daily:
            DailyQuestionCard(hero: true, rundenStempel: stempelzeile(runde: runde))
        default: cardView(card)
        }
    }

    @ViewBuilder
    private func cardView(_ card: DashboardCard) -> some View {
        switch card {
        case .firstMoment: FirstMomentCard()
        case .daily: DailyQuestionCard()
        case .checkin: CheckinCard()
        case .resting: restingCard
        case .touches: TelegrammLeiste()
        case .rituals: RitualsDashboardSection()
        case .quest: QuestCard()
        case .moments: momentsCard
        case .dateNight: DateNightCard()
        case .hugQueue: HugQueueCard()
        case .level: LevelCard()
        case .seasonDoor: SeasonCalendarSupportCard()
        }
    }

    /// The deterministic "on this day" memory wins; the random flashback
    /// stays as the fallback.
    @ViewBuilder
    private var momentsCard: some View {
        if let onThisDay, !onThisDay.items.isEmpty {
            OnThisDayCard(response: onThisDay)
        } else if let flashback {
            FlashbackCard(item: flashback)
        }
    }

    /// The single fold below the budget, told as the Ablagekorb of the
    /// station (§4.1 zone 3) — replaces the three old DisclosureGroups
    /// (Dossier 23, ideas 7/8). Quiet label: hierarchical tray icon,
    /// couple-tint affordance, honest badge.
    private func moreGroup(_ cards: [DashboardCard]) -> some View {
        DisclosureGroup(
            isExpanded: $moreExpanded,
            content: {
                VStack(spacing: LayoutMetrics.s(14)) {
                    ForEach(cards, id: \.self) { card in
                        cardView(card)
                    }
                }
                .padding(.top, Space.m)
            },
            label: {
                HStack(spacing: LayoutMetrics.s(10)) {
                    Image(systemName: "tray")
                        .font(.system(.body).weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Nacht.sekundaer)
                    Text(L10n.t("postfach.ablage.titel"))
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Papier.aufNacht)
                    Spacer()
                    let badge = moreBadge(cards)
                    if badge > 0 {
                        dashboardBadge(badge)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(L10n.t("postfach.ablage.titel"))
                .accessibilityValue(moreBadge(cards) > 0
                                    ? L10n.t("dashboard.a11y.pending", count: moreBadge(cards))
                                    : L10n.t("dashboard.a11y.none"))
            }
        )
        // The fold is night cardboard under the cards; the chevron
        // affordance speaks lamplight — couple ink stays a paper color.
        .tint(Licht.lampengold)
        .nightCard()
    }

    /// Badge honesty: the fold only counts things that genuinely wait.
    private func moreBadge(_ cards: [DashboardCard]) -> Int {
        (cards.contains(.rituals) ? (appState.missedInbox?.needsCount ?? 0) : 0)
            + (cards.contains(.quest) ? appState.gamesAwaitingMe.count : 0)
    }

    private func dashboardBadge(_ badge: Int) -> some View {
        Text("\(badge)")
            .font(.system(.caption, design: .rounded).weight(.heavy))
            .monospacedDigit()
            .foregroundStyle(coupleTint.onBlend)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(coupleTint.blend))
    }

    /// "Everything shared today" — being done is the most beautiful state
    /// of the screen, not an empty list (Dossier 23, idea 22).
    private var restingCard: some View {
        VStack(spacing: Space.m) {
            // On the night card, success speaks in lamplight — wax stays
            // material and would drown on the dark ground (3.2:1).
            Image(systemName: "heart.circle.fill")
                .font(.system(.largeTitle).weight(.semibold))
                .foregroundStyle(Licht.lampengold)
            Text(L10n.t("home.resting.title"))
                .font(Typo.title)
                .foregroundStyle(Papier.aufNacht)
            Text(L10n.t("home.resting.line"))
                .font(Typo.label)
                .foregroundStyle(Nacht.sekundaer)
                .multilineTextAlignment(.center)
            if appState.partner?.online != true, let lastSeen = appState.partner?.lastSeenAt {
                Text(L10n.t("home.resting.lastHere",
                            ["name": appState.partnerName,
                             "time": L10n.relativeShort(lastSeen)]))
                    .font(Typo.caption)
                    .foregroundStyle(Nacht.tertiaer)
            }
        }
        .frame(maxWidth: .infinity)
        .nightCard(padding: .hero)
        .accessibilityElement(children: .combine)
    }

    /// Quiet prefetch for the hero context — a failure only means the hero
    /// falls back to the time-of-day suggestion, never worth a toast.
    private func loadCheckinState() async {
        guard appState.partner != nil, let api = appState.api else { return }
        do {
            let response = try await api.checkins(limit: 1)
            checkinToday = response.days.first { $0.dateKey == SharedDates.todayKey() }
        } catch {}
    }

    /// Quiet prefetch for the door-card rank — a failure only means the door
    /// card keeps its normal place, never worth a toast.
    private func loadSeasonDoorState() async {
        guard let api = appState.api, let me = appState.memberId else { return }
        let calendars: [CoupleSeasonCalendar]
        do {
            calendars = try await api.seasonCalendars()
        } catch { return }
        seasonDoorFeeds = calendars.map { calendar in
            SeasonCalendarDoorFeed(
                forMe: calendar.recipientId == me,
                doors: calendar.doors.map {
                    SeasonDoorSummary(number: $0.number,
                                      unlockAt: $0.unlockAt,
                                      opened: $0.openedAt != nil)
                }
            )
        }
    }

    // MARK: Flashback ("memory of the day")

    /// Prefers the server's deterministic "on this day" memories; the
    /// random local flashback only fills in when today has none (or the
    /// server predates the /api/on-this-day route).
    private func loadMemories() async {
        onThisDay = nil
        if appState.api != nil, appState.couple != nil {
            onThisDay = try? await appState.api?.onThisDay()
        }
        if onThisDay?.items.isEmpty ?? true {
            await loadFlashback()
        }
    }

    private func loadFlashback() async {
        // Reset on every (re-)run — the task id changes with the couple, so a
        // server/couple switch must never show the previous couple's memory.
        flashback = nil
        guard let api = appState.api, let couple = appState.couple else { return }
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        var candidates: [FlashbackItem] = []
        if let photos = try? await api.photos() {
            for photo in photos where photo.createdAt < cutoff {
                let days = Int(Date().timeIntervalSince(photo.createdAt) / 86400)
                candidates.append(.photo(photo, daysAgo: days))
            }
        }
        if let entries = try? await api.dailyHistory(limit: 120) {
            for entry in entries where entry.bothAnswered {
                if let date = SharedDates.parse(entry.dateKey), date < cutoff {
                    let question = ContentPack.dailyQuestions.first { $0.id == entry.questionId }
                        ?? ContentPack.dailyQuestion(dateKey: entry.dateKey, coupleId: couple.id)
                    let days = Int(Date().timeIntervalSince(date) / 86400)
                    candidates.append(.daily(entry, question, daysAgo: days))
                }
            }
        }
        flashback = candidates.randomElement()
    }

    // MARK: Monthiversary (exactly X months / years together today)

    private var monthiversary: (count: Int, years: Bool)? {
        // No celebration before the relationship exists in the app: a user
        // who sets the anniversary while still waiting for the partner must
        // not see the stage cheer for someone who isn't there (EVAL P0-2).
        guard appState.partner != nil,
              let key = appState.couple?.anniversary,
              let start = SharedDates.parse(key) else { return nil }
        let cal = SharedDates.calendar
        let startDay = cal.startOfDay(for: start)
        let today = cal.startOfDay(for: Date())
        guard today > startDay else { return nil }
        let comps = cal.dateComponents([.month, .day], from: startDay, to: today)
        guard let months = comps.month, months >= 1, comps.day == 0 else { return nil }
        if months % 12 == 0 { return (months / 12, true) }
        return (months, false)
    }

    private func monthiversaryCard(_ milestone: (count: Int, years: Bool)) -> some View {
        let text: String
        if milestone.years {
            text = milestone.count == 1
                ? L10n.t("home.anniversaryOneYear")
                : L10n.t("home.anniversaryYears", ["n": String(milestone.count)])
        } else {
            text = milestone.count == 1
                ? L10n.t("home.monthiversaryOne")
                : L10n.t("home.monthiversary", ["n": String(milestone.count)])
        }
        // Nacht-Banderole (nacht-first UX): a QUIET dark strip wrapped by
        // the couple's band — compact, so the bright hero below keeps the
        // stage; the celebration light is the Lichtschein glow BEHIND the
        // strip (levels 1–2 celebrate with light, not confetti; Reduce
        // Motion gets the static end glow).
        return HStack(spacing: Space.m) {
            Image(systemName: milestone.years ? "seal.fill" : "heart.circle.fill")
                .font(.system(.title3).weight(.semibold))
                .foregroundStyle(Licht.lampengold)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Papier.aufNacht)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 36)
        .nightCard(padding: .compact)
        .overlay(alignment: .leading) {
            // The banderole: the couple band wraps the strip vertically.
            Rectangle()
                .fill(coupleTint.band)
                .frame(width: Papier.bandBreite)
                .padding(.vertical, Radius.papier)
                .accessibilityHidden(true)
        }
        .background(alignment: .center) {
            LichtscheinGlow(size: LayoutMetrics.s(160))
        }
        // Extra air below the strip: the banderole steps back, the hero
        // sheet gets its stage (nacht-first hierarchy polish).
        .padding(.bottom, Space.xs)
        .accessibilityElement(children: .combine)
    }

    // MARK: Session loading / retry (cold start without network)

    /// Cold start waits in the shape of the coming page — skeleton lines
    /// in the night washes on the night card, never an anonymous spinner
    /// center (commandment 7).
    private var sessionStateCard: some View {
        VStack(spacing: Space.m) {
            if appState.sessionLoading {
                VStack(alignment: .leading, spacing: Space.m) {
                    PaperSkeleton(kind: .line(width: LayoutMetrics.s(180)), onNacht: true)
                    PaperSkeleton(kind: .line(), onNacht: true)
                    PaperSkeleton(kind: .tile(height: 72), onNacht: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.t("common.loading"))
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(.largeTitle).weight(.semibold))
                    .foregroundStyle(Nacht.sekundaer)
                Text(L10n.t("error.network"))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Nacht.sekundaer)
                    .multilineTextAlignment(.center)
                Button(L10n.t("common.retry")) {
                    Task {
                        await appState.refreshAll()
                        appState.connectSocket()
                    }
                }
                .buttonStyle(SecondaryButtonStyle(fullWidth: false))
            }
        }
        .frame(maxWidth: .infinity)
        .nightCard(padding: .hero)
    }

    // MARK: Heart coda

    /// The 3D heart as the page's closing note instead of a 250 pt center
    /// piece — and the ONE canonical heartbeat sender (Dossier 23, ideas
    /// 13/26): the grid button is gone, the FAB stays the thinking pulse.
    private var heartCoda: some View {
        VStack(spacing: 4) {
            Heart3DView(burstTrigger: heartBurst, isVisible: heartCodaVisible)
                .frame(height: LayoutMetrics.s(150))
                .onScrollVisibilityChange(threshold: 0.2) { visible in
                    heartCodaVisible = visible
                }
                // Initial-fire hardening (P1-F edge case): on tall windows
                // the coda already lies in the FIRST viewport — should the
                // scroll callback miss its initial fire, this geometry
                // check switches the heart ON (same 0.2 threshold; it only
                // ever activates — deactivation stays with the scroll
                // callback, so the two sources never fight).
                .onGeometryChange(for: Bool.self) { proxy in
                    guard let viewport = proxy.bounds(of: .scrollView) else {
                        return false
                    }
                    let frame = CGRect(origin: .zero, size: proxy.size)
                    let overlap = frame.intersection(viewport)
                    return frame.height > 0
                        && overlap.height >= frame.height * 0.2
                } action: { inViewport in
                    if inViewport && !heartCodaVisible {
                        heartCodaVisible = true
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    heartBurst += 1
                    heartHintDone = true
                    appState.sendTouch(.heartbeat)
                }
                .accessibilityElement()
                .accessibilityLabel(L10n.t("home.heartTapHint"))
                .accessibilityAddTraits(.isButton)

            if !heartHintDone {
                Text(L10n.t("home.heartTapHint"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.bottom, 8)
            }
        }
    }

    // MARK: Reveal deep link

    /// W7-Rest: a widget/island seal tap (`sooodreamy://reveal`) waits in
    /// `AppState.pendingRevealRequest` until the dashboard can honor it.
    /// The flag survives until the daily entry is loaded (cold start), then
    /// resolves exactly once — into the ceremony when the seal is intact,
    /// silently when the moment passed (already revealed elsewhere).
    private func consumePendingRevealRequest() {
        guard appState.pendingRevealRequest, appState.dailyEntry != nil else { return }
        appState.pendingRevealRequest = false
        guard DailyRevealLauncher.revealPending(appState: appState) else { return }
        DailyRevealLauncher.present(appState: appState)
    }
}
