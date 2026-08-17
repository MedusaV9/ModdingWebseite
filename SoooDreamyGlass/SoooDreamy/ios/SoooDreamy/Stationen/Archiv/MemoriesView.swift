import SwiftUI
import Combine

/// The six drawers ARE the sidebar groups on regular widths (Neubau N4,
/// ENTSCHEID §4.4) — the 4 → 6 recut is a pure mapping change; the
/// drawer model itself lives in `Content/ArchivRules.swift`, where
/// `ArchivRulesTests` pins that no section can ever be lost.
typealias MemoriesSidebarGroup = ArchivFach

extension ArchivFach {
    /// Ordered app sections of this drawer — the pure ENTSCHEID table
    /// resolved against the section enum.
    var sections: [MemoriesSection] {
        ArchivRules.sections(in: self).compactMap(MemoriesSection.init(rawValue:))
    }
}

/// Station 4 ARCHIV (`tab.us`) — the cabinet for everything the couple
/// keeps: on compact widths the SCHRANKFRONT (six named drawer cards
/// instead of the old 18-tile grid), on regular widths the hand-built
/// split whose sidebar groups are the same six drawers.
struct MemoriesView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.motionGate) private var motionGate

    /// Sidebar selection on regular widths (kept alive across tab switches).
    @State private var selectedSection: MemoriesSection = .gallery
    /// Overlay sidebar in the COLLAPSED regime (pane below the persistent
    /// threshold) — toggled from the toolbar, closed by scrim or selection.
    @State private var sidebarShown = false
    /// Collapsed sidebar groups, persisted across launches (comma-joined
    /// raw values). Default: everything expanded — the `ipad-memories`
    /// screenshot staging relies on the gallery row being visible.
    @AppStorage("memories.sidebar.collapsedGroups") private var collapsedGroupsRaw = ""

    /// The one open drawer of the Schrankfront (a real cabinet: you pull
    /// one drawer at a time). Persisted (Befund 5b): the cabinet re-opens
    /// on the drawer you worked in last — the archive stays faster than
    /// the old grid across visits, not just within one.
    @AppStorage("memories.schrank.openFach") private var openFachRaw = ""
    private var openFach: ArchivFach? {
        ArchivFach(rawValue: openFachRaw)
    }
    /// Archive search (Befund 5c): filters the sections of ALL drawers
    /// by title via the pure `ArchivRules` matching — hits open their
    /// drawer.
    @State private var searchText = ""
    /// The drawer END-detent in flight (Befund 6): held so a drawer
    /// switch CANCELS the previous haptic instead of letting a ghost
    /// detent fire over the wrong drawer.
    @State private var detentTask: Task<Void, Never>?
    /// Measured front width — drives the two-column cabinet (pure rule
    /// `LayoutRules.schrankfrontUsesTwoColumns`, iPad half-splits).
    @State private var frontWidth: Double = 0

    @State private var openCouponCount: Int?
    // Recent-activity strip: newest photo / song / coupon.
    @State private var latestPhoto: Photo?
    @State private var latestSong: Song?
    @State private var latestCoupon: Coupon?
    // Honest drawer badges: open items across shared lists, capsules
    // ready to open, active goals (plus coupons above).
    @State private var openListItems: Int?
    @State private var capsulesReady: Int?
    @State private var activeGoals: Int?
    /// W6-Rest chat→album bridge: pushed programmatically while
    /// `AppState.pendingGalleryPhotoId` waits for the gallery.
    @State private var galleryPushed = false
    /// Beweis-Shots (Fix4 Befund 10): the `-sooodreamy.kapsel` pin stages
    /// a ripe, already-opened capsule and presents its ceremony letter
    /// directly over the archive — the two stempelEinzug proofs (title /
    /// no title). Nil on every real launch; seeded in the task below
    /// (the guidePage mechanic — ScreenshotSeed is MainActor-isolated).
    @State private var stagedCeremonyCapsule: TimeCapsule?

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                splitHub
            } else {
                stackedHub
            }
        }
        .fullScreenCover(item: $stagedCeremonyCapsule) { capsule in
            CapsuleCeremonyView(capsule: capsule, startRevealed: true)
        }
        .task {
            stagedCeremonyCapsule = ScreenshotSeed.stagedCapsule
            openPendingGallery()
            await appState.refreshStats()
            await loadCouponTeaser()
            await loadSongTeaser()
            await loadLatestPhoto()
            await loadV2Teasers()
        }
        .onChange(of: appState.pendingGalleryPhotoId) {
            // Chat's "view in album": open the gallery, which then shows
            // its lightbox on the requested photo.
            openPendingGallery()
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent else { return }
            handleServerEvent(event)
        }
        .onDisappear {
            // Tab switch (Re-Eval Runde 2): a still-flying END-detent must
            // not knock over another station — cancel and drop it.
            detentTask?.cancel()
            detentTask = nil
        }
    }

    /// Compact widths: recent strip + Schrankfront — drawers expand
    /// inline, their section rows push the destinations. While the
    /// archive search is active (Befund 5c), the front shows exactly
    /// the drawers with hits, opened onto their matching rows.
    private var stackedHub: some View {
        NavigationStack {
            ZStack {
                DreamyBackground()
                ScrollView {
                    VStack(spacing: Theme.sectionSpacing) {
                        header
                        if searchActive {
                            searchResults
                        } else {
                            if latestPhoto != nil || latestSong != nil || latestCoupon != nil {
                                recentStrip
                            }
                            schrankfront
                        }
                    }
                    .padding(Space.l)
                    .contentColumn(.hub)
                }
                // Resting clearance above the bottom chrome — the last
                // drawer must not park inside the accessory/tab-bar
                // refraction band (glass mirrors resting text).
                .contentMargins(.bottom, LayoutMetrics.restingBottomClearance,
                                for: .scrollContent)
                // The cabinet runs softly under the floating dock instead
                // of cutting off hard (soft over the aurora, wave-2 decision).
                .scrollEdgeEffectStyle(.soft, for: .bottom)
                .refreshable {
                    await appState.refreshStats()
                    await appState.refreshEvents()
                    await loadCouponTeaser()
                    await loadSongTeaser()
                    await loadLatestPhoto()
                    await loadV2Teasers()
                }
            }
            // `.searchable` needs the navigation bar, so the bar stays
            // VISIBLE but glass-less (inline, no title, hidden
            // background) — the hand-lettered header below keeps being
            // the station's voice. Fix-Runde 3 (Archiv-Befund 9): the
            // drawer field used to stand ABOVE that header — search
            // before title, a hole in the upper third. The system
            // MINIMIZES the field into its toolbar button now (the
            // Schreibstube pattern): title first, search one tap away,
            // no hole.
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .searchable(text: $searchText,
                        prompt: L10n.t("archiv.search.prompt"))
            .searchToolbarBehavior(.minimize)
            .navigationDestination(isPresented: $galleryPushed) {
                GalleryView()
            }
        }
    }

    // MARK: Archive search (Befund 5c)

    /// True while a non-whitespace query filters the cabinet.
    private var searchActive: Bool {
        !ArchivRules.searchFold(searchText).isEmpty
    }

    /// Section id → BOTH language variants of its display title, handed
    /// to the PURE `ArchivRules` matching (the rule stays Foundation-
    /// only). Sprachunabhängig (Fix-Runde 3, Archiv-Befund 7): the fold
    /// index carries DE and EN of every title, so „tresor"/„listen"
    /// hit in the EN UI and "vault"/"lists" in the DE UI.
    private var sectionSearchTitles: [String: [String]] {
        var titles: [String: [String]] = [:]
        for fach in ArchivFach.allCases {
            for section in fach.sections {
                titles[section.rawValue] = searchTitleVariants(section)
            }
        }
        return titles
    }

    /// Both language variants of one section title — the year-review
    /// keeps its year suffix on every variant (matching what the rows
    /// display, so „2026" finds the review too).
    private func searchTitleVariants(_ section: MemoriesSection) -> [String] {
        let variants = MemoriesL10n.searchTitleVariants(section.titleKey)
        guard section == .yearReview else { return variants }
        let year = String(SharedDates.calendar.component(.year, from: Date()))
        return variants.map { "\($0) \(year)" }
    }

    /// Drawer → localized drawer name (both languages), the search
    /// index's third layer (Re-Eval Runde 2): „Alben"/„Chronik"/
    /// „Planfach" open their drawer even though no section title
    /// contains the word — since Fix-Runde 3 in the EN UI too.
    private var fachSearchTitles: [ArchivFach: [String]] {
        Dictionary(uniqueKeysWithValues: ArchivFach.allCases.map {
            ($0, MemoriesL10n.searchTitleVariants($0.titleKey))
        })
    }

    /// Hits open their drawer: the front shows exactly the drawers with
    /// matches, expanded onto only the matching rows.
    private var searchResults: some View {
        let titles = sectionSearchTitles
        let fachTitles = fachSearchTitles
        let hits = Set(ArchivRules.matchingSectionIds(query: searchText,
                                                      titles: titles,
                                                      fachTitles: fachTitles))
        let faecher = ArchivRules.matchingFaecher(query: searchText,
                                                  titles: titles,
                                                  fachTitles: fachTitles)
        return Group {
            if faecher.isEmpty {
                EmptyStateView(systemImage: "magnifyingglass",
                               title: L10n.t("archiv.search.empty.title"),
                               subtitle: L10n.t("archiv.search.empty.subtitle",
                                                ["query": searchText]))
            } else {
                VStack(spacing: Space.m) {
                    ForEach(faecher) { fach in
                        fachCard(fach,
                                 visibleSections: fach.sections.filter {
                                     hits.contains($0.rawValue)
                                 },
                                 forcedOpen: true)
                    }
                }
            }
        }
    }

    /// Chat's "view in album" bridge — sets BOTH layout targets; whichever
    /// hub variant is on screen reacts, the other state is harmless.
    private func openPendingGallery() {
        guard appState.pendingGalleryPhotoId != nil else { return }
        galleryPushed = true
        selectedSection = .gallery
    }

    // MARK: Schrankfront (ENTSCHEID §4.4, zone 2)

    /// The cabinet front: six drawer cards. One column on phones; two
    /// balanced, top-aligned columns once the pane genuinely holds two
    /// card widths (iPad half-splits that are still compact-width) —
    /// each column expands its drawers independently.
    private var schrankfront: some View {
        Group {
            if LayoutRules.schrankfrontUsesTwoColumns(paneWidth: frontWidth) {
                HStack(alignment: .top, spacing: Space.m) {
                    VStack(spacing: Space.m) {
                        ForEach(schrankColumn(0)) { fachCard($0) }
                    }
                    VStack(spacing: Space.m) {
                        ForEach(schrankColumn(1)) { fachCard($0) }
                    }
                }
            } else {
                VStack(spacing: Space.m) {
                    ForEach(ArchivFach.allCases) { fachCard($0) }
                }
            }
        }
        .onGeometryChange(for: Double.self) { proxy in
            proxy.size.width
        } action: { width in
            frontWidth = width
        }
    }

    /// Reading-order zig-zag: even drawers left, odd drawers right.
    private func schrankColumn(_ column: Int) -> [ArchivFach] {
        ArchivFach.allCases.enumerated()
            .filter { $0.offset % 2 == column }
            .map(\.element)
    }

    /// One drawer card: night card with a 2-pt stack edge below (the
    /// drawer body peeking out under the front), honest count badge,
    /// inline expansion on the Schubladenauszug signature.
    private func fachCard(_ fach: ArchivFach) -> some View {
        fachCard(fach, visibleSections: fach.sections, forcedOpen: nil)
    }

    /// The full drawer card. `forcedOpen` is the search regime (Befund
    /// 5c): the drawer stands open on `visibleSections` only and its
    /// front is a plain HEADER — a disabled button would make VoiceOver
    /// say „abgeblendet" about a front that was never broken (Re-Eval
    /// Runde 2); the rows are the destinations.
    private func fachCard(_ fach: ArchivFach,
                          visibleSections: [MemoriesSection],
                          forcedOpen: Bool?) -> some View {
        let open = forcedOpen ?? (openFach == fach)
        return VStack(alignment: .leading, spacing: 0) {
            if forcedOpen != nil {
                fachFront(fach, open: open, chevron: false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel(L10n.t(fach.titleKey))
                    .accessibilityValue(fachAccessibilityValue(fach, open: open))
            } else {
                Button {
                    toggleFach(fach)
                } label: {
                    fachFront(fach, open: open, chevron: true)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .accessibilityLabel(L10n.t(fach.titleKey))
                // Badge, size and state in ONE spoken value (Befund 8):
                // „5 neue, 6 Bereiche, eingeklappt".
                .accessibilityValue(fachAccessibilityValue(fach, open: open))
            }

            if open {
                VStack(spacing: 2) {
                    ForEach(Array(visibleSections.enumerated()),
                            id: \.element.id) { index, section in
                        fachRow(section, index: index)
                    }
                }
                .padding(.top, Space.m)
            }
        }
        .nightCard()
        .background(alignment: .bottom) { stapelkante }
        .accessibilityIdentifier("archiv.fach.\(fach.rawValue)")
    }

    /// The drawer front's face — shared between the tappable front and
    /// the search regime's static header. `chevron` only exists on the
    /// toggling front; a forced-open drawer cannot fold, so it shows no
    /// affordance it does not have.
    private func fachFront(_ fach: ArchivFach, open: Bool,
                           chevron: Bool) -> some View {
        let sections = fach.sections
        return HStack(spacing: Space.m) {
            MemoriesIconBadge(symbol: fach.symbol, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t(fach.titleKey))
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.t("archiv.fach.bereiche", count: sections.count))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Nacht.sekundaer)
                if !open {
                    // Closed drawers say WHAT is inside, not only
                    // how much (Befund 5a) — one preview line;
                    // truncation is fine, it is a preview.
                    Text(ArchivRules.previewLine(
                        titles: sections.map { sidebarTitle($0) }))
                        .font(Typo.caption)
                        .foregroundStyle(Nacht.tertiaer)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
            if let count = fachBadgeCount(fach), count > 0 {
                countBadge(count)
            }
            if chevron {
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(Nacht.tertiaer)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
        }
    }

    /// VO value of a drawer front (Befund 8): badge count via the
    /// count-API („1 neuer Eintrag"/„5 neue"), then the drawer size
    /// („ein Bereich"/„6 Bereiche"), then the fold state.
    private func fachAccessibilityValue(_ fach: ArchivFach, open: Bool) -> String {
        var parts: [String] = []
        if let badge = fachBadgeCount(fach), badge > 0 {
            parts.append(L10n.t("archiv.fach.neue", count: badge))
        }
        parts.append(L10n.t("archiv.fach.bereiche", count: fach.sections.count))
        parts.append(L10n.t(open ? "memories.sidebar.group.expanded"
                                 : "memories.sidebar.group.collapsed"))
        return parts.joined(separator: ", ")
    }

    /// One section row gliding out of the open drawer — pushes its screen
    /// (level 1; details live one push deeper).
    private func fachRow(_ section: MemoriesSection, index: Int) -> some View {
        NavigationLink {
            destination(for: section)
        } label: {
            HStack(spacing: Space.m) {
                Image(systemName: section.symbol)
                    .font(Typo.label)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Nacht.sekundaer)
                    .frame(width: LayoutMetrics.s(24))
                    .accessibilityHidden(true)
                Text(sidebarTitle(section))
                    .font(Typo.label)
                    .foregroundStyle(Papier.aufNacht)
                    // AX sizes wrap instead of truncating (AX5 contract).
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                sidebarBadge(section)
                Image(systemName: "chevron.right")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(Nacht.tertiaer)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, LayoutMetrics.s(9))
            .padding(.horizontal, LayoutMetrics.s(11))
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Papier.nachtInnenFill)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.control,
                                           style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .schubladenauszug(index: index)
    }

    /// The 2-pt stack edge under each drawer card: a second night sheet
    /// peeking out below the front — the cabinet holds more than it shows.
    private var stapelkante: some View {
        RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
            .fill(Papier.nachtkarton)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                    .strokeBorder(Nacht.naht, lineWidth: Theme.hairlineWidth)
            )
            .frame(height: LayoutMetrics.s(12))
            .padding(.horizontal, Space.m)
            .offset(y: LayoutMetrics.s(2))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Honest drawer badge — the sum of the live section badges inside.
    private func fachBadgeCount(_ fach: ArchivFach) -> Int? {
        let sum = fach.sections.reduce(0) { $0 + (sidebarBadgeCount($1) ?? 0) }
        return sum > 0 ? sum : nil
    }

    private func countBadge(_ count: Int) -> some View {
        Text(String(count))
            .font(Typo.caption)
            .foregroundStyle(Papier.aufNacht)
            .padding(.vertical, 2)
            .padding(.horizontal, Space.s)
            .background(
                Capsule().fill(Papier.nachtInnenFill)
                    .overlay(Capsule().strokeBorder(Nacht.naht,
                                                    lineWidth: Theme.hairlineWidth))
            )
    }

    /// Pulling a drawer: open INLINE on `settle` (Reduce Motion: direct),
    /// then ONE soft end-detent — soundless by design. Closing is a plain
    /// quiet tap; opening another drawer lets this one glide shut AND
    /// cancels its still-flying detent (Geister-Detent, Befund 6).
    private func toggleFach(_ fach: ArchivFach) {
        let opening = openFach != fach
        detentTask?.cancel()
        detentTask = nil
        withAnimation(reduceMotion ? nil : Theme.Motion.settle) {
            openFachRaw = opening ? fach.rawValue : ""
        }
        if opening {
            scheduleDrawerDetent(for: fach)
            announceDrawerOpened(fach)
        } else {
            Haptics.shared.tap()
        }
    }

    /// The signature's single END-detent: fires once when the last
    /// staggered row has settled (Reduce Motion opens directly, so the
    /// detent comes right away — it stays, per ENTSCHEID §4.4). The Task
    /// is HELD (Befund 6): a drawer switch cancels it, and even an
    /// uncancelled straggler re-checks that ITS drawer is still the open
    /// one before knocking.
    private func scheduleDrawerDetent(for fach: ArchivFach) {
        let ms = reduceMotion
            ? 80
            : 350 + Int(SchubladenauszugRow.staggerSeconds * 1000)
                * min(fach.sections.count, SchubladenauszugRow.maxStaggered)
        detentTask = Task {
            try? await Task.sleep(for: .milliseconds(ms))
            guard !Task.isCancelled else { return }
            // Only an UNCANCELLED task can still be the held one (every
            // replacement cancels first) — clear the reference on the way
            // out so nothing stale lingers after completion (Re-Eval
            // Runde 2).
            detentTask = nil
            guard openFach == fach else { return }
            Haptics.shared.play(events: [HapticEventSpec(t: 0, i: 0.35, s: 0.30)])
        }
    }

    /// VoiceOver hears the whole sentence: „{Fach}, {n} Bereiche,
    /// aufgeklappt." (ENTSCHEID §4.4 wording) — the Bereiche part goes
    /// through the count-API, so one section speaks „ein Bereich",
    /// never „1 Bereiche" (Befund 8).
    private func announceDrawerOpened(_ fach: ArchivFach) {
        let sentence = L10n.t("archiv.fach.openedA11y",
                              ["fach": L10n.t(fach.titleKey),
                               "bereiche": L10n.t("archiv.fach.bereiche",
                                                  count: fach.sections.count)])
        AccessibilityNotification.Announcement(sentence).post()
    }

    // MARK: Destinations (shared by drawers and split detail)

    /// The one destination builder: Schrankfront rows push it, the split
    /// detail hosts it — a11y-IDs of the target screens stay stable.
    @ViewBuilder private func destination(for section: MemoriesSection) -> some View {
        switch section {
        case .coupons: CouponsView()
        case .soundtrack: SoundtrackView()
        case .gallery: GalleryView()
        case .videos: VideoGalleryView()
        case .potd: PotdView()
        case .lists: SharedListsView()
        case .canvas: CanvasView()
        case .bucket: BucketListView()
        case .events: EventsView()
        case .stats: LoveStatsView()
        case .journal: JournalView()
        case .capsules: CapsulesView()
        case .goals: GoalsView()
        case .weekplan: WeekplanView()
        case .magazine: MagazineView()
        case .vault: VaultView()
        case .story: StoryTimelineView()
        case .yearReview: YearReviewView()
        case .weekReview: WeekReviewView()
        case .needsHistory: NeedsHistoryView()
        case .seasonCalendar: SeasonCalendarView()
        }
    }

    // MARK: Split hub (regular width)

    /// Regular widths (roadmap 17): a REAL HStack split over ONE shared
    /// aurora — sidebar column + detail column instead of stacked
    /// navigation. The old safe-area-inset trick centered detail content
    /// over the WHOLE window (EVAL iPad: empty state at window center,
    /// not in the column beside the sidebar); the explicit HStack hands
    /// the detail exactly the remaining width, so everything the detail
    /// centers lands in ITS column. The sidebar is persistent only while
    /// the pane genuinely holds both columns (`LayoutRules`, measured
    /// container-based like `canvasUsesSideRail`); narrower panes get a
    /// toolbar-toggled overlay sidebar instead of permanent chrome.
    private var splitHub: some View {
        GeometryReader { geo in
            // AX text sizes collapse the persistent sidebar (FXD-2 #4):
            // giant type needs the whole pane for the detail column, so
            // the sections move behind the toolbar-toggled overlay — one
            // tap away instead of a truncating fixed column.
            let persistent = LayoutRules.memoriesUsesPersistentSidebar(
                paneWidth: Double(geo.size.width), isRegularWidth: true)
                && !AccessibilityBudget.sideChromeCollapses(
                    accessibilityText: dynamicTypeSize.isAccessibilitySize)
            ZStack(alignment: .topLeading) {
                // THE one shared background — both columns ride the same sky.
                DreamyBackground()
                HStack(spacing: 0) {
                    if persistent {
                        sectionSidebar
                    }
                    detailColumn(persistent: persistent)
                        .frame(maxWidth: .infinity)
                }
                if !persistent, sidebarShown {
                    sidebarOverlay
                }
            }
            .onChange(of: persistent) {
                // Growing across the threshold: the sidebar is permanent
                // again, the overlay state must not linger underneath.
                if persistent { sidebarShown = false }
            }
        }
    }

    /// The detail column: its own NavigationStack, rebuilt per section.
    /// In the collapsed regime the detail's toolbar carries the sidebar
    /// toggle — the sections stay one tap away instead of disappearing.
    private func detailColumn(persistent: Bool) -> some View {
        NavigationStack {
            destination(for: selectedSection)
                .toolbar {
                    if !persistent {
                        ToolbarItem(placement: .topBarLeading) {
                            sidebarToggle
                        }
                    }
                }
        }
        // Selecting a section rebuilds the detail stack (drops pushed
        // children of the previous section); the sidebar sits OUTSIDE the
        // id-scope, so its scroll position survives.
        .id(selectedSection)
    }

    private var sidebarToggle: some View {
        Button {
            Haptics.shared.tap()
            withAnimation(reduceMotion ? nil : Theme.Motion.settle) {
                sidebarShown.toggle()
            }
        } label: {
            Image(systemName: "sidebar.leading")
        }
        .accessibilityLabel(L10n.t("memories.sidebar.toggle"))
    }

    /// Collapsed regime: the same sidebar as a leading overlay above a
    /// scrim — chrome on demand, never a third of a narrow pane.
    private var sidebarOverlay: some View {
        ZStack(alignment: .topLeading) {
            Button {
                withAnimation(reduceMotion ? nil : Theme.Motion.settle) {
                    sidebarShown = false
                }
            } label: {
                // Central scrim gate: Reduce Transparency swaps the
                // hand-painted translucency for the opaque night ink.
                motionGate.scrim(0.25)
            }
            .buttonStyle(.plain)
            .ignoresSafeArea()
            .accessibilityLabel(L10n.t("common.close"))
            sectionSidebar
                .transition(.move(edge: .leading).combined(with: .opacity))
        }
        .transition(.opacity)
    }

    /// The persistent sidebar as the album's REGISTER (nacht-first P2):
    /// a night-card column whose selected row is a lamplit night tab —
    /// the detail keeps its reading columns untouched. Sections live
    /// in the six drawer groups of the cabinet (ENTSCHEID §4.4: the
    /// Fächer ARE the sidebar groups); the collapse state survives
    /// launches.
    ///
    /// The register carries the ARCHIVE SEARCH on regular widths now
    /// (Fix-Runde 3, Archiv-Befund 6 — the iPad split had none): the
    /// sidebar column is its own navigation stack, so the NATIVE
    /// `.searchable` field lives at the top of the register; the same
    /// pure `ArchivRules` fold index filters, and hits open drawer and
    /// detail. The card tone fills the stack's root, so the system
    /// stack never paints its own background under the hidden bar.
    private var sectionSidebar: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.pane, style: .continuous)
        return NavigationStack {
            ZStack {
                Papier.nachtkarton.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        sidebarHeader
                            .padding(.horizontal, Space.s)
                            .padding(.bottom, Space.s)
                        sidebarSections
                    }
                    .padding(Space.m)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            // Fix4 Befund 9: the always-open drawer field stood ABOVE the
            // register's title block — search before title, like the hole
            // the compact front already fixed. Same cure here: the system
            // MINIMIZES the field into its toolbar button — title first,
            // search one tap away (the iPhone pattern).
            .searchable(text: $searchText,
                        prompt: L10n.t("archiv.search.prompt"))
            .searchToolbarBehavior(.minimize)
        }
        .frame(width: LayoutMetrics.sidebarWidth)
        .background(shape.fill(Papier.nachtkarton).elevation(.resting))
        .overlay(shape.strokeBorder(PaperLightEdge.nachtGradient,
                                    lineWidth: Theme.hairlineWidth))
        .clipShape(shape)
        .padding(.leading, Space.m)
        .padding(.vertical, Space.m)
    }

    /// The register's rows — or, while the archive search is active,
    /// exactly the drawers with hits, standing open on their matching
    /// rows (Fix-Runde 3, Archiv-Befund 6: same filter as the
    /// Schrankfront; picking a row opens the detail).
    @ViewBuilder private var sidebarSections: some View {
        if searchActive {
            let titles = sectionSearchTitles
            let fachTitles = fachSearchTitles
            let hits = Set(ArchivRules.matchingSectionIds(query: searchText,
                                                          titles: titles,
                                                          fachTitles: fachTitles))
            let faecher = ArchivRules.matchingFaecher(query: searchText,
                                                      titles: titles,
                                                      fachTitles: fachTitles)
            if faecher.isEmpty {
                EmptyStateView(systemImage: "magnifyingglass",
                               title: L10n.t("archiv.search.empty.title"),
                               subtitle: L10n.t("archiv.search.empty.subtitle",
                                                ["query": searchText]))
                    .padding(.top, Space.l)
            } else {
                ForEach(faecher) { group in
                    sidebarGroupSearchHeader(group, isFirst: group == faecher.first)
                    ForEach(group.sections.filter { hits.contains($0.rawValue) }) { section in
                        sidebarRow(section)
                    }
                }
            }
        } else {
            ForEach(MemoriesSidebarGroup.allCases) { group in
                sidebarGroupHeader(group)
                if !isCollapsed(group) {
                    ForEach(group.sections) { section in
                        sidebarRow(section)
                    }
                }
            }
        }
    }

    /// The header restyled for the register column: lamplight on the
    /// night card instead of the night-canvas brand title (the couple's
    /// identity ink stays non-text on night — text speaks lampengold).
    private var sidebarHeader: some View {
        HStack(alignment: .top, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.t("memories.title"))
                    .font(Typo.hero)
                    .foregroundStyle(Licht.lampengold)
                Text(L10n.t("memories.subtitle"))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Nacht.sekundaer)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HandbookButton(anchor: "us")
        }
        .padding(.top, 6)
    }

    // MARK: Sidebar groups

    private var collapsedGroups: Set<String> {
        Set(collapsedGroupsRaw.split(separator: ",").map(String.init))
    }

    private func isCollapsed(_ group: MemoriesSidebarGroup) -> Bool {
        collapsedGroups.contains(group.rawValue)
    }

    private func toggleGroup(_ group: MemoriesSidebarGroup) {
        var collapsed = collapsedGroups
        if collapsed.contains(group.rawValue) {
            collapsed.remove(group.rawValue)
        } else {
            collapsed.insert(group.rawValue)
        }
        collapsedGroupsRaw = collapsed.sorted().joined(separator: ",")
    }

    /// One tappable group header as a small DRAWER FACE (iPad-Eval S1:
    /// the register read like a stock Finder sidebar): the drawer's own
    /// symbol, an inner night fill with hairline seam and the cabinet's
    /// stack edge peeking below — nightCard building blocks only, no
    /// new material. While collapsed the summed badge keeps "something
    /// is waiting" visible.
    private func sidebarGroupHeader(_ group: MemoriesSidebarGroup) -> some View {
        let collapsed = isCollapsed(group)
        return Button {
            Haptics.shared.tap()
            withAnimation(reduceMotion ? nil : Theme.Motion.settle) {
                toggleGroup(group)
            }
        } label: {
            sidebarGroupFace(group, collapsed: collapsed, chevron: true)
        }
        .buttonStyle(.plain)
        .padding(.top, group == MemoriesSidebarGroup.allCases.first ? 0 : Space.s)
        .accessibilityLabel(L10n.t(group.titleKey))
        // Badge + size + state in one spoken value (Befund 8), same
        // sentence as the Schrankfront drawer fronts.
        .accessibilityValue(fachAccessibilityValue(group, open: !collapsed))
    }

    /// The search regime's STATIC group header (Fix-Runde 3, Archiv-
    /// Befund 6): a drawer forced open by hits cannot fold — a disabled
    /// button would make VoiceOver call an intact front dimmed (the
    /// Schrankfront lesson from Re-Eval Runde 2), so the face renders
    /// as a plain header without the affordance it does not have.
    private func sidebarGroupSearchHeader(_ group: MemoriesSidebarGroup,
                                          isFirst: Bool) -> some View {
        sidebarGroupFace(group, collapsed: false, chevron: false)
            .padding(.top, isFirst ? 0 : Space.s)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(L10n.t(group.titleKey))
            .accessibilityValue(fachAccessibilityValue(group, open: true))
    }

    /// The drawer face itself, shared by the tappable header and the
    /// search regime's static one — `chevron` only exists where the
    /// drawer can actually fold.
    private func sidebarGroupFace(_ group: MemoriesSidebarGroup,
                                  collapsed: Bool, chevron: Bool) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: group.symbol)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Nacht.sekundaer)
                .frame(width: LayoutMetrics.s(18))
                .accessibilityHidden(true)
            // Register dividers speak rounded on the night card —
            // the Anschrift serif is paper-only (MIGRATION_DUNKEL §4).
            Text(L10n.t(group.titleKey))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Nacht.sekundaer)
                // AX sizes wrap instead of truncating.
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
            if collapsed, let count = fachBadgeCount(group) {
                Text(String(count))
                    .font(Typo.caption)
                    .foregroundStyle(Papier.aufNacht)
                    .padding(.vertical, 1)
                    .padding(.horizontal, Space.xs)
                    .background(
                        Capsule().fill(Papier.nachtInnenFill)
                            .overlay(Capsule().strokeBorder(
                                Nacht.naht, lineWidth: Theme.hairlineWidth))
                    )
            }
            Spacer(minLength: 0)
            if chevron {
                Image(systemName: "chevron.down")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(Nacht.tertiaer)
                    .rotationEffect(.degrees(collapsed ? -90 : 0))
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, LayoutMetrics.s(8))
        .padding(.horizontal, LayoutMetrics.s(11))
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Papier.nachtInnenFill)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control,
                                     style: .continuous)
                        .strokeBorder(Nacht.naht,
                                      lineWidth: Theme.hairlineWidth)
                )
        )
        // The drawer body peeking out under the face — the same
        // Stapelkante voice as the Schrankfront cards.
        .background(alignment: .bottom) {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Papier.nachtInnenFill)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control,
                                     style: .continuous)
                        .strokeBorder(Nacht.naht,
                                      lineWidth: Theme.hairlineWidth)
                )
                .frame(height: LayoutMetrics.s(10))
                .padding(.horizontal, Space.s)
                .offset(y: LayoutMetrics.s(2))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }

    private func sidebarRow(_ section: MemoriesSection) -> some View {
        let selected = section == selectedSection
        return Button {
            // Collapsed regime: picking a section hands the pane back to
            // the detail (no-op while the sidebar is persistent).
            withAnimation(reduceMotion ? nil : Theme.Motion.settle) {
                sidebarShown = false
            }
            guard selectedSection != section else { return }
            selectedSection = section
            Haptics.shared.tap()
        } label: {
            HStack(spacing: Space.m) {
                Image(systemName: section.symbol)
                    .font(Typo.label)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(selected ? Papier.aufNacht : Nacht.sekundaer)
                    .frame(width: LayoutMetrics.s(24))
                    .accessibilityHidden(true)
                Text(sidebarTitle(section))
                    .font(Typo.label)
                    .foregroundStyle(selected ? Papier.aufNacht : Nacht.sekundaer)
                    // AX sizes wrap instead of truncating (AX5 contract:
                    // informative text is never forced onto one line).
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                sidebarBadge(section)
            }
            .padding(.vertical, LayoutMetrics.s(9))
            .padding(.horizontal, LayoutMetrics.s(11))
            .background(
                // The selected row is the lamplit pulled-out tab on the
                // night register; the others stay flush.
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(selected ? Papier.nachtInnenFill : Color.clear)
                    .overlay {
                        if selected {
                            RoundedRectangle(cornerRadius: Radius.control,
                                             style: .continuous)
                                .strokeBorder(PaperLightEdge.nachtGradient,
                                              lineWidth: Theme.hairlineWidth)
                        }
                    }
                    // The clear fill of unselected rows casts no shadow.
                    .elevation(.raised)
            )
            .overlay(alignment: .leading) {
                // The couple's shared color marks the open register tab —
                // identity as a non-text line (blend is night-secured).
                if selected {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(coupleTint.blend)
                        .frame(width: LayoutMetrics.s(3))
                        .padding(.vertical, LayoutMetrics.s(7))
                        .accessibilityHidden(true)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.control,
                                           style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func sidebarTitle(_ section: MemoriesSection) -> String {
        section == .yearReview
            ? L10n.t(section.titleKey) + " "
                + String(SharedDates.calendar.component(.year, from: Date()))
            : L10n.t(section.titleKey)
    }

    /// Live count chip where a section carries one — drawers and sidebar
    /// share the same loaded state, so "something is waiting" glances
    /// survive the recomposition.
    @ViewBuilder private func sidebarBadge(_ section: MemoriesSection) -> some View {
        if let count = sidebarBadgeCount(section), count > 0 {
            countBadge(count)
        }
    }

    private func sidebarBadgeCount(_ section: MemoriesSection) -> Int? {
        switch section {
        case .coupons: return openCouponCount
        case .lists: return openListItems
        case .capsules: return capsulesReady
        case .goals: return activeGoals
        default: return nil
        }
    }

    // MARK: Header

    private var header: some View {
        // FullRelease N1-A: help moved from the dock into the screen
        // headers — one instance, visible in whichever layout hosts the
        // header (plain hub or the split sidebar).
        HStack(alignment: .top, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.t("memories.title"))
                    .brandTitle()
                Text(L10n.t("memories.subtitle"))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HandbookButton(anchor: "us")
        }
        .padding(.top, 6)
    }

    // MARK: Recent activity strip („Zuletzt eingeordnet", zone 1)

    /// Horizontal "what's new between you two" ribbon under the header:
    /// the newest photo, song and coupon, each deep-linking to its screen.
    private var recentStrip: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(L10n.t("memories.recent.title"))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.m) {
                    if let photo = latestPhoto {
                        NavigationLink {
                            GalleryView()
                        } label: {
                            RecentActivityChip(kind: L10n.t("memories.recent.photo"),
                                               text: photoChipText(photo),
                                               time: L10n.relativeShort(photo.createdAt),
                                               tint: coupleTint.blend) {
                                photoChipThumb(photo)
                            }
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.lift)
                    }
                    if let song = latestSong {
                        NavigationLink {
                            SoundtrackView()
                        } label: {
                            RecentActivityChip(kind: L10n.t("memories.recent.song"),
                                               text: songChipText(song),
                                               time: L10n.relativeShort(song.createdAt),
                                               tint: Theme.mint) {
                                chipGlyph("music.note")
                            }
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.lift)
                    }
                    if let coupon = latestCoupon {
                        NavigationLink {
                            CouponsView()
                        } label: {
                            RecentActivityChip(kind: L10n.t("memories.recent.coupon"),
                                               text: coupon.title,
                                               time: L10n.relativeShort(coupon.createdAt),
                                               tint: Theme.gold) {
                                // The coupon's emoji is the giver's own pick —
                                // content, not chrome.
                                Text(coupon.emoji)
                                    .font(Typo.title)
                            }
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.lift)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chipGlyph(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(Typo.title)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(Nacht.sekundaer)
            .accessibilityHidden(true)
    }

    /// Caption when present, otherwise "by <uploader>".
    private func photoChipText(_ photo: Photo) -> String {
        if let caption = photo.caption, !caption.isEmpty { return caption }
        let uploader = appState.couple?.members.first { $0.id == photo.uploaderId }?.name
        return L10n.t("memories.gallery.by", ["name": uploader ?? L10n.t("common.partner")])
    }

    private func songChipText(_ song: Song) -> String {
        if let artist = song.artist, !artist.isEmpty { return "\(song.title) · \(artist)" }
        return song.title
    }

    @ViewBuilder
    private func photoChipThumb(_ photo: Photo) -> some View {
        if appState.api != nil {
            AuthenticatedAsyncImage(api: appState.api, path: photo.thumbUrl ?? photo.url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Papier.nachtInnenFill
                }
            }
            .frame(width: LayoutMetrics.s(38), height: LayoutMetrics.s(38))
            .clipShape(RoundedRectangle(cornerRadius: Radius.concentric(parent: Radius.control,
                                                                        padding: Space.xs),
                                        style: .continuous))
        } else {
            chipGlyph("photo.on.rectangle.angled")
        }
    }

    // MARK: Realtime teaser refresh

    private func loadCouponTeaser() async {
        guard let api = appState.api, let myId = appState.memberId else { return }
        if let list = try? await api.coupons() {
            openCouponCount = list.filter { $0.forMember == myId && $0.redeemedAt == nil }.count
            latestCoupon = list.max { $0.createdAt < $1.createdAt }
        }
    }

    private func loadSongTeaser() async {
        guard let api = appState.api else { return }
        if let list = try? await api.songs() {
            latestSong = list.max { $0.createdAt < $1.createdAt }
        }
    }

    /// Newest photo for the recent-activity strip.
    private func loadLatestPhoto() async {
        guard let api = appState.api else { return }
        if let list = try? await api.photos() {
            latestPhoto = list.max { $0.createdAt < $1.createdAt }
        }
    }

    /// Badges: open shared-list items + the ritual drawer counts.
    private func loadV2Teasers() async {
        guard let api = appState.api else { return }
        if let lists = try? await api.sharedLists() {
            openListItems = lists.reduce(0) { $0 + $1.openCount }
        }
        await loadRitualTeasers()
    }

    /// Ritual badges: openable capsules, active goals.
    private func loadRitualTeasers() async {
        guard let api = appState.api, let myId = appState.memberId else { return }
        if let capsules = try? await api.capsules() {
            capsulesReady = capsules
                .filter { $0.forMember == myId && $0.openedAt == nil && $0.unlocked }.count
        }
        if let goals = try? await api.goals() {
            activeGoals = goals.filter { $0.completedAt == nil }.count
        }
    }

    private func handleServerEvent(_ event: ServerEvent) {
        switch event.type {
        case .photoAdded, .photoDeleted:
            Task {
                await appState.refreshStats()
                await loadLatestPhoto()
            }
        case .videoAdded, .videoDeleted:
            Task { await appState.refreshStats() }
        case .bucketAdded, .bucketUpdated, .bucketDeleted:
            Task { await appState.refreshStats() }
        case .couponAdded, .couponRedeemed, .couponDeleted:
            Task { await loadCouponTeaser() }
        case .songAdded, .songDeleted:
            Task { await loadSongTeaser() }
        case .listAdded, .listUpdated, .listDeleted:
            Task { await loadV2Teasers() }
        case .capsuleSealed, .capsuleOpened, .capsuleDeleted,
             .goalAdded, .goalUpdated, .goalDeleted:
            Task { await loadRitualTeasers() }
        default:
            break
        }
    }
}
