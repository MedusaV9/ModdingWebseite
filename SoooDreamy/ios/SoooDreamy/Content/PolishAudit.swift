import Foundation

/// The five canonical states of a server-backed surface (DESIGN.md,
/// commandment 8): none of them may silently look like another one.
enum PolishState: String, CaseIterable, Hashable {
    case loading
    case empty
    case content
    case offline
    case failure
}

/// Surfaces under the commandment-8 contract. A new surface ships only
/// once it has a case here AND a hand-written inventory row below —
/// `PolishAuditTests` fails until both exist.
enum AuditedSurface: String, CaseIterable, Hashable {
    case dashboard
    case chat
    case playHub
    case memories
    case settings
    case replay
    case tournament
    case repairConversation
    case seasonCalendar
    case personalization
    case widgets
    case handbook
    case deviceManager
    case intelligenceConsent
    case letterWorkshop
    case dailySpark
    case demoMode
    case cinematicIntro
    // Neubau N2/N3 (Nachtpostamt): die neuen Flächen der Stationen.
    case zustellkarte
    case dienstlicht
    case siegelpresse
    case kartenschrank
    case spielbuch
    // Neubau N4: die Schrankfront des Archivs (sechs Fächer).
    case schrankfront
}

/// How one surface answers one of the five states.
enum StateCoverage: Hashable {
    /// Designed and in the code — the string names where it renders, so a
    /// reviewer can jump straight there.
    case implemented(String)
    /// The state cannot occur on this surface — the string says why
    /// (e.g. bundled local content has no offline path).
    case notApplicable(String)
    /// Honest, known debt: the state exists but has no designed answer
    /// yet. Closing a gap means replacing this case with `.implemented`;
    /// opening one means writing it down here — never silence.
    case gap(String)
}

/// Commandment 8's executable half — a hand-maintained inventory.
///
/// The previous version of this file DERIVED `statesBySurface` from
/// `requiredStates` for every surface, which made the audit a tautology
/// that could never fail. Every row below is now written by hand, from
/// reading the actual view code, and the test enforces exactly what a
/// static file CAN enforce: every surface has a row, every row answers
/// all five states, and known gaps are named instead of implied.
///
/// What no code here can prove is whether a view REALLY renders its
/// skeleton — that stays the commandment-8 review ritual: whenever a row
/// changes, show the five states as previews or screenshots in review.
enum PolishAudit {
    static let requiredStates = Set(PolishState.allCases)

    /// Surface → hand-verified answer for each of the five states.
    static let inventory: [AuditedSurface: [PolishState: StateCoverage]] = [
        .dashboard: [
            .loading: .implemented("DashboardView.sessionStateCard — GlassSkeleton rows in the coming page's shape while the session restores"),
            .empty: .implemented("WaitingForPartnerCard — pairing code, copy/share and QR as the invitation"),
            .content: .implemented("DashboardView.pairedCards"),
            .offline: .implemented("ConnectionBanner pill in the header; cached cards stay on screen"),
            .failure: .implemented("DashboardView.sessionStateCard — error.network + retry after a failed cold start"),
        ],
        .chat: [
            .loading: .implemented("ChatView.messageArea — LoadingView skeleton while model.initialLoading"),
            .empty: .implemented("ChatView.emptyState — invitation with a focus-the-input action"),
            .content: .implemented("ChatView.messageList"),
            .offline: .implemented("ConnectionBanner in the chat header; sends queue via OfflineOutbox"),
            .failure: .implemented("ChatView.loadFailedState — StateNoticeView failed/offline with retry when the history load fails while the transcript is empty"),
        ],
        .playHub: [
            .loading: .notApplicable("the hub grid is a local catalog and renders instantly"),
            .empty: .implemented("GameNeedsPartnerView — realtime games need both partners"),
            .content: .implemented("PlayHubView game grid"),
            .offline: .gap("open-session badges come from the server and silently stay stale/absent offline"),
            .failure: .gap("GamesCoordinator swallows session-refresh errors with an optional try — the hub cannot tell 'no open games' from 'request failed'"),
        ],
        .memories: [
            .loading: .implemented("GalleryView skeleton tiles (GlassSkeleton .tile) while pages load"),
            .empty: .implemented("GalleryView/JournalView EmptyStateView invitations"),
            .content: .implemented("Archiv Schrankfront (six fach drawers) + gallery grid"),
            .offline: .gap("no dedicated offline notice on the hub; it leans on cached content and toasts"),
            .failure: .gap("load errors surface as a toast (handleAPIError) while the grid still looks empty"),
        ],
        .settings: [
            .loading: .notApplicable("settings rows are local state and render instantly"),
            .empty: .notApplicable("there is no empty settings screen — every section always has rows"),
            .content: .implemented("SettingsView — the six Amt form sections"),
            .offline: .implemented("server rows show honest values (\"Server-Version: nicht erreichbar\") and point to the Verbindungs-Doktor"),
            .failure: .implemented("DiagnosticsView — four traffic-light checks, each red step names the way out"),
        ],
        .replay: [
            .loading: .implemented("ReplayView phase .loading spinner"),
            .empty: .implemented("ReplayView EmptyStateView with a way back to the games"),
            .content: .implemented("ReplayView open-session + finished-game lists"),
            .offline: .implemented("ReplayView StateNoticeView(.offline) with retry (SurfaceState.resolve)"),
            .failure: .implemented("ReplayView StateNoticeView(.failed) with retry (SurfaceState.resolve)"),
        ],
        .tournament: [
            .loading: .implemented("TournamentView phase .loading spinner"),
            .empty: .implemented("TournamentView season table with the explicit empty-shelf line"),
            .content: .implemented("TournamentView season card + shelf"),
            .offline: .implemented("TournamentView StateNoticeView(.offline) with retry (SurfaceState.resolve)"),
            .failure: .implemented("TournamentView StateNoticeView(.failed) with retry (SurfaceState.resolve)"),
        ],
        .repairConversation: [
            .loading: .implemented("RepairConsiderationView — GlassSkeleton cards in the coming sections' shape while sessions/hints load"),
            .empty: .implemented("RepairConsiderationView renders its invitation/compose entry when no sessions exist"),
            .content: .implemented("RepairConsiderationView session + hints sections"),
            .offline: .implemented("RepairConsiderationView RitualsLoadFailedNotice(.offline) above the sections with retry (SurfaceState.resolve)"),
            .failure: .implemented("RepairConsiderationView RitualsLoadFailedNotice(.failed) above the sections with retry (SurfaceState.resolve)"),
        ],
        .seasonCalendar: [
            .loading: .implemented("SeasonCalendarView spinner while loading"),
            .empty: .implemented("SeasonCalendarView EmptyStateView under the create button"),
            .content: .implemented("SeasonCalendarView calendar cards"),
            .offline: .implemented("SeasonCalendarView RitualsLoadFailedNotice(.offline) with retry (SurfaceState.resolve)"),
            .failure: .implemented("SeasonCalendarView RitualsLoadFailedNotice(.failed) with retry (SurfaceState.resolve)"),
        ],
        .personalization: [
            .loading: .notApplicable("the editor works on the already-loaded couple state"),
            .empty: .notApplicable("the editor always shows the palette/monogram controls"),
            .content: .implemented("PersonalizationView preview + preset/custom/monogram/contrast sections"),
            .offline: .implemented("save failures surface via the error toast; the editor keeps its state"),
            .failure: .implemented("save button shows its in-flight state; errors toast via handleAPIError"),
        ],
        .widgets: [
            .loading: .implemented("placeholder timeline entries until the first snapshot exists"),
            .empty: .implemented("WidgetDiagnostics names the reason (signed out / app group missing / never opened) instead of an eternal placeholder"),
            .content: .implemented("StudioProvider snapshot rendering across families"),
            .offline: .implemented("SnapshotFreshness.stale(age:) — widgets stamp stale data instead of pretending it is live"),
            .failure: .implemented("WidgetDiagnostics.renderableSnapshot degrades to the honest diagnosis view"),
        ],
        .handbook: [
            .loading: .notApplicable("bundled markdown, parsed at open — no network wait"),
            .empty: .notApplicable("the handbook always has chapters; a broken parse is the failure case"),
            .content: .implemented("HandbookView chapter list + reader"),
            .offline: .notApplicable("local bundle resource — no offline path"),
            .failure: .implemented("HandbookView EmptyStateView when parsing/anchors fail"),
        ],
        .deviceManager: [
            .loading: .implemented("DeviceManagerSheet.sessionsCard — GlassSkeleton lines while GET /api/sessions runs"),
            .empty: .implemented("DeviceManagerSheet StateNoticeView(.empty) — in practice the own session always exists, but the state stays designed"),
            .content: .implemented("DeviceManagerSheet sessions list (this-device pill, revoke) + add-device card (QR, code, TTL countdown)"),
            .offline: .implemented("DeviceManagerSheet StateNoticeView(.offline) with retry — transport error while the socket is down (SurfaceState.resolve)"),
            .failure: .implemented("DeviceManagerSheet StateNoticeView(.failed) with retry (SurfaceState.resolve)"),
        ],
        // The three AI surfaces run on-device — "offline" cannot mean "no
        // network". The role of offline is played by "Apple Intelligence
        // unavailable" (capability absent, not an error): entry points
        // render only while the model reports available, and Settings
        // names the honest reason (ai.availability.*). FAILURE is a
        // generation that ran and went wrong (guardrail or error).
        .intelligenceConsent: [
            .loading: .notApplicable("the sheet renders local copy and a decision — nothing is fetched"),
            .empty: .notApplicable("the sheet always carries its three-sentence promise; there is no zero-data variant"),
            .content: .implemented("IntelligenceConsentSheet — three promise lines, on-device badge, grant/decline"),
            .offline: .notApplicable("consent is a device-local decision; the sheet only opens from entry points that already passed the availability gate"),
            .failure: .notApplicable("persisting the choice is a UserDefaults write; there is no failable operation on this surface"),
        ],
        .letterWorkshop: [
            .loading: .implemented("LetterWorkshopView skeletonLines / GlassSkeleton card — waiting in the shape of the coming suggestions"),
            .empty: .implemented("LetterWorkshopView.openersIdleContent — tone picker + invitation before the first generation"),
            .content: .implemented("LetterWorkshopView openersContent/softenContent — drafts adopted only via explicit tap"),
            .offline: .implemented("AI-unavailable plays the offline role: Intelligence.featureVisible hides the entry chips, Settings intelligenceBlock explains (ai.availability.*)"),
            .failure: .implemented("LetterWorkshopView.failedContent — guardrail/failed copy names that the letter is unchanged + retry"),
        ],
        .dailySpark: [
            .loading: .implemented("DailySparkCard .generating — one GlassSkeleton line where the question will appear"),
            .empty: .implemented("DailySparkCard.entryButton — the quiet invitation row before any generation"),
            .content: .implemented("DailySparkCard.sparkContent — the follow-up question + 'Andere Frage'"),
            .offline: .implemented("AI-unavailable plays the offline role: the card renders only while Intelligence.featureVisible; Settings carries the honest reason"),
            .failure: .implemented("DailySparkCard.failedContent — ai.spark.failed names that the answers are safe + retry"),
        ],
        // Welle 7 [29]: „Erst mal ansehen" — the staged, server-less demo.
        // Everything is in-memory by construction, so the classic
        // server-surface states cannot occur; the honest marker is the
        // permanent badge, and the exit is the surface's one real action.
        .demoMode: [
            .loading: .notApplicable("the demo couple is staged in memory before the first frame (AppState.init / enterDemo) — nothing is ever fetched"),
            .empty: .notApplicable("entering the demo always stages the full couple story (dashboard, chat transcript, open daily question)"),
            .content: .implemented("ScreenshotSeed.stageDemoMode staging + the permanent DemoBadge top bar naming the situation on every tab"),
            .offline: .notApplicable("no server by construction — the connection pill presents the stubbed healthy state, the badge carries the honesty"),
            .failure: .notApplicable("no failable operation: entering stages memory, leaving evaporates it (AppState.exitDemo), only the flag itself persists"),
        ],
        // W8D: the first-launch cinematic — a fully procedural stage
        // (CinematicScript + CinematicIntroView) with no server, no fetch
        // and no persisted state beyond the one seen-flag. The classic
        // server states cannot occur; the designed variants are the skip
        // path, the Reduce-Motion stills and the VoiceOver telling.
        .cinematicIntro: [
            .loading: .notApplicable("the stage is procedural (tokens, synth, CoreHaptics) — there is nothing to fetch before the first frame"),
            .empty: .notApplicable("the script is compiled in (CinematicScript.scenes); a zero-scene state cannot be built"),
            .content: .implemented("CinematicIntroView — five acts from CinematicScript, plus the Reduce-Motion still variant and the VoiceOver two-sentence telling with immediate skip"),
            .offline: .notApplicable("no network by construction — the intro plays identically in airplane mode"),
            .failure: .notApplicable("no failable operation: haptics/sound degrade silently per device capability (Haptics.deviceSupportsHaptics), the seen-flag is a UserDefaults write"),
        ],
        // Neubau N2: die „Heute vor …"-Zustellkarte mit Polaroid-Entwickeln
        // (A2). Die Karte ist eine Bühne über bereits geladenen Journal-
        // Daten — die Serverzustände trägt das Postfach (dashboard row).
        .zustellkarte: [
            .loading: .notApplicable("the card mounts only after the journal snapshot exists (OnThisDayCard renders from loaded state; the dashboard row owns the fetch states)"),
            .empty: .implemented("OnThisDayCard hides itself when no anniversary memory exists — absence is the designed empty state, no husk card"),
            .content: .implemented("OnThisDayCard + PolaroidEntwickeln — milky photo-paper veil, press-and-hold radial develop, once-per-dateKey persistence"),
            .offline: .notApplicable("develops over the already-cached memory; no fetch is triggered by the gesture"),
            .failure: .notApplicable("no failable operation: the develop is pure presentation over local state (Reduce Motion: instantly developed + announcement)"),
        ],
        // Neubau N2: das Dienstlicht im Postfach-Kopf — ein Spiegel der
        // Energie-Ampel beider, das Sheet zeigt die bestehende EnergyCard.
        .dienstlicht: [
            .loading: .notApplicable("the lamp dot derives from AppState energy already in memory — it never fetches"),
            .empty: .implemented("DashboardHeaderView — without any energy signal the ring rests dark (documented resting state, a11y value says so)"),
            .content: .implemented("DashboardHeaderView lamp dot (lampengold→glut→energyRed, weaker battery of both) + DienstlichtSheet around the unchanged EnergyCard"),
            .offline: .notApplicable("mirrors last known energy; the ConnectionBanner on the dashboard carries the offline honesty"),
            .failure: .notApplicable("no failable operation: setting energy goes through the existing EnergyCard path with its own error toasts"),
        ],
        // Neubau N3: die Siegelpresse — EIN Menü im Pult bündelt die drei
        // Absende-Zeremonien (Zeitpost/Kapsel/Türchen). Reines Routing.
        .siegelpresse: [
            .loading: .notApplicable("a native Menu over compiled entries — nothing to fetch"),
            .empty: .notApplicable("the three ceremonies are compiled in; a zero-entry press cannot be built"),
            .content: .implemented("ChatPult siegelpresse menu (chat.siegelpresse) → ZeitpostSheet / CapsulesView / SeasonCalendarView, each wrapped in SiegelpresseUmschlag with its own Fertig chrome"),
            .offline: .notApplicable("the target sheets own their offline honesty (Zeitpost queue, capsule save errors) — the press only routes"),
            .failure: .notApplicable("no failable operation in the press itself; failures live and speak inside the target ceremonies"),
        ],
        // Neubau N3: der Kartenschrank — der Spiele-Katalog als drei Fächer
        // aus KartenschrankRules (compiled content, kein Server).
        .kartenschrank: [
            .loading: .notApplicable("fach contents are compiled (KartenschrankRules.inhalt) — the shelf never fetches"),
            .empty: .notApplicable("coverage is total by pinned test (deckt(GameDestination.allCases)) — an empty fach cannot ship"),
            .content: .implemented("SpieltischKartenschrank — three fächer with Punktlinien chapter heads (A1), UmschlagKarte envelopes, Lasche-auf start ceremony"),
            .offline: .notApplicable("catalog is local; the opened game's session owns its own connection states"),
            .failure: .notApplicable("no failable operation: opening routes to the game's existing entry which carries its own errors"),
        ],
        // Neubau N3: das Spielbuch — Turnier/Siegerliste/Wiederholungen als
        // Kapitelzeilen mit echten Bestandszahlen aus der Spiele-Statistik.
        .spielbuch: [
            .loading: .implemented("PlayHubView spielbuch rows render with the hub's loaded stats; while the hub restores, the playHub row's skeleton covers the whole stage"),
            .empty: .implemented("Punktlinien rows show honest zeros before the first finished match — the number is the state"),
            .content: .implemented("PlayHubView spielbuch section — chapter lines with dotted leaders and real match counts (KartenschrankRules.gespieltePartien)"),
            .offline: .implemented("counts derive from the last loaded game history; the hub's ConnectionBanner names the staleness"),
            .failure: .implemented("a failed history refresh keeps the previous counts and surfaces through the hub's existing error path (playHub row)"),
        ],
        // Neubau N4: die Schrankfront — das Archiv als sechs Fächer aus
        // ArchivRules (compiled mapping, kein Server), Schubladenauszug
        // öffnet inline; die Ziel-Screens tragen ihre eigenen Zustände.
        .schrankfront: [
            .loading: .notApplicable("drawer fronts are compiled (ArchivRules.sectionIds) — the cabinet never fetches; badge counts mirror already-loaded hub state"),
            .empty: .notApplicable("coverage is total by pinned test (ArchivRulesTests — every MemoriesSection lies in exactly one fach); an empty drawer cannot ship"),
            .content: .implemented("MemoriesView schrankfront — six fach cards with Stapelkante, Schubladenauszug row glide (one soft detent, Reduce Motion: direct open) and count badges"),
            .offline: .notApplicable("the cabinet is local routing; the opened section screens own their offline honesty (memories row carries the hub's gaps)"),
            .failure: .notApplicable("no failable operation: pulling a drawer is pure presentation, destinations carry their own error paths"),
        ],
    ]

    /// Surfaces declared in `AuditedSurface` that nobody has audited yet —
    /// adding a case without an inventory row keeps this non-empty and the
    /// test red until a human writes the row.
    static var unauditedSurfaces: [AuditedSurface] {
        AuditedSurface.allCases.filter { inventory[$0] == nil }
    }

    /// States a surface's row forgot to answer (implemented, notApplicable
    /// or gap — silence is the only wrong answer).
    static var unansweredStates: [AuditedSurface: Set<PolishState>] {
        Dictionary(
            uniqueKeysWithValues: AuditedSurface.allCases.compactMap { surface in
                guard let row = inventory[surface] else { return nil }
                let missing = requiredStates.subtracting(row.keys)
                return missing.isEmpty ? nil : (surface, missing)
            }
        )
    }

    /// The open debt, honestly enumerable — release notes and review can
    /// list it instead of pretending the audit passed everything.
    static var knownGaps: [(surface: AuditedSurface, state: PolishState, note: String)] {
        AuditedSurface.allCases.flatMap { surface in
            (inventory[surface] ?? [:]).compactMap { state, coverage in
                if case .gap(let note) = coverage {
                    return (surface, state, note)
                }
                return nil
            }
        }
        .sorted { ($0.surface.rawValue, $0.state.rawValue) < ($1.surface.rawValue, $1.state.rawValue) }
    }
}
