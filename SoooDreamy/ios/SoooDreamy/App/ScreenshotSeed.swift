import Foundation

/// Welle 7 [29]: the persisted half of the in-app demo mode („Erst mal
/// ansehen"). The flag below is THE ONLY thing demo mode ever persists —
/// every visible prop is re-staged from `ScreenshotSeed.stageDemoMode` on
/// launch and evaporates completely on exit.
enum DemoMode {
    static let flagKey = "demo.active"

    static var persistedActive: Bool {
        UserDefaults.standard.bool(forKey: flagKey)
    }
}

/// The staged demo state behind the CI screenshot matrix (workflow job
/// "simulator-screenshots"). One place decides WHAT each screenshot mode
/// shows, so every shot tells exactly one coherent story (EVAL P0-2):
///
/// - `Main`:     freshly created couple, waiting for the partner (pairing).
/// - `Paired`:   everyday dashboard of a paired couple WITH their own
///               palette — the couple colors (aurora, brand titles, blend
///               milestone pane) are the point of this shot.
/// - `Chat`:     a short real conversation incl. a reaction and the
///               partner-colored typing indicator.
/// - `Chat` + `-SoooDreamyScreenshotComposer`: same staging plus a
///               prefilled draft — the exposed composer chrome and the
///               tinted send capsule are the shot's subject.
/// - `Reveal`:   both answered today's question, seal unbroken — the gold
///               sealed card with its glow.
/// - `Play`:     the play hub catalog.
/// - `Settings`: the settings information architecture.
/// - `Memories`: the Us hub — on the iPad leg this shows the Welle-5
///               split layout (section sidebar + detail pane).
///
/// The demo couple deliberately does NOT wear stock pink/purple: blue +
/// mint prove visually that `coupleTint` carries the app, not the old
/// template ramp.
@MainActor
enum ScreenshotSeed {
    /// "Who am I" for the staged couple — `AppState.memberId` falls back
    /// to this in paired demo modes (there is no server profile).
    static var demoMemberId: String? {
        ScreenshotMode.pairedDemo ? myId : nil
    }

    /// The staged chat transcript — non-nil only in chat screenshot mode
    /// (`ChatModel.configure` short-circuits its server load with it).
    static var chatTranscript: [Message]? {
        ScreenshotMode.chat ? transcript : nil
    }

    /// Extra flag ON TOP of chat mode, not a `ScreenshotMode` of its own:
    /// the composer variant reuses the full chat staging (transcript, tab,
    /// palette) and only adds composer state here.
    private static let composerVariant = ProcessInfo.processInfo.arguments
        .contains("-SoooDreamyScreenshotComposer")

    /// Draft staged into the chat composer — non-nil only in the composer
    /// shot (chat mode + composer flag). A filled field makes the tinted
    /// send capsule appear; `ChatView` additionally focuses the field so
    /// the keyboard lifts and the composer chrome is fully exposed.
    static var composerDraft: String? {
        guard ScreenshotMode.chat, composerVariant else { return nil }
        return de("Und danach Eis am Kanal?",
                  "And ice cream by the canal after?")
    }

    // FullRelease N1-A: `prefilledTabs` died with the custom dock. The old
    // ZStack panes materialized in `onAppear` — a first-frame race that
    // shipped a blank `paired-de.png` on a cold CI simulator. MainTabView's
    // pane guard now renders the SELECTED tab directly, so `stage(_:)`
    // setting `activeTab` is enough for the staged pane to exist in the
    // very first frame.

    /// W8D + Kino-Bugjagd: frozen playhead for the cinema shots. Like the
    /// composer flag this is staging ON TOP of a normal launch, not a
    /// `ScreenshotMode` of its own: the welcome phase reaches the intro
    /// anyway (`CinematicIntroGate.shouldPlay` always plays under a
    /// freeze, whatever an earlier launch persisted). Two knobs, one pure
    /// rule (`CinematicScript.freezeTime`):
    ///   * `-SoooDreamyScreenshotCinematic` pins the classic single shot
    ///     (43 s — wax-seal act, heart embossed, score silent),
    ///   * the `SoooDreamyCinematicFreeze=<seconds>` launch environment
    ///     parametrizes the playhead so CI shoots a whole FRAME SERIES
    ///     across every chapter type (video chapters render their
    ///     procedural poster still — the simulator ships no videos, the
    ///     poster path IS the visual proof). Values clamp into the
    ///     timeline; garbage falls back to the flag.
    /// `nonisolated`: the gate reads it outside the main actor.
    nonisolated static let cinematicFreezeTime: Double? = CinematicScript.freezeTime(
        argument: ProcessInfo.processInfo.arguments
            .contains("-SoooDreamyScreenshotCinematic"),
        environment: ProcessInfo.processInfo.environment["SoooDreamyCinematicFreeze"])

    /// Frame-series CHOICE pins (Re-Eval Runde 2): the series proved
    /// chapters, never selections — t2 shot an unchosen gate, t30 froze
    /// `inkHex: nil`. Two SIMCTL_CHILD_ environment seeds stage the
    /// chosen states deterministically; both only matter under a freeze.
    ///
    /// `SoooDreamyCinematicLanguage=de|en`: the gate card stands CHOSEN
    /// (stamp point + lift) in the frozen frame. "system" is rejected —
    /// a staged pick must be concrete.
    nonisolated static let cinematicChosenLanguage: AppLanguage? = {
        guard let raw = ProcessInfo.processInfo
            .environment["SoooDreamyCinematicLanguage"],
              let language = AppLanguage(rawValue: raw),
              language != .system else { return nil }
        return language
    }()

    /// `SoooDreamyCinematicInk=RRGGBB`: the ink chapter freezes with the
    /// picked color — drop done, stroke drawn, approach mid-run (the
    /// offset rule lives in `CinematicScript.screenshotInkPickOffset`).
    /// Validated against the member palette; garbage stays nil = the
    /// waiting composition.
    nonisolated static let cinematicInkHex: String? = {
        guard let hex = ProcessInfo.processInfo
            .environment["SoooDreamyCinematicInk"],
              CouplePaletteRules.memberColorHexes.contains(hex) else { return nil }
        return hex
    }()

    /// `-sooodreamy.guidePage <n>` (NSArgumentDomain, the archiv-openFach
    /// mechanic): the guide starts on page n — the workflow shoots the
    /// closing page (5 stations) as `guide-ende-de`. The view clamps.
    static var guidePageIndex: Int? {
        guard UserDefaults.standard.object(forKey: "sooodreamy.guidePage") != nil
        else { return nil }
        return UserDefaults.standard.integer(forKey: "sooodreamy.guidePage")
    }

    /// `-sooodreamy.kapsel titel|ohnetitel` (NSArgumentDomain, the
    /// guide-page mechanic): a ripe, ALREADY-OPENED time capsule whose
    /// ceremony letter the archive presents straight away — the two CI
    /// proof shots of the stempelEinzug law (Fix4 Befund 10): WITH a
    /// title the headline clears the wax seal's corner, WITHOUT one the
    /// body itself indents. Garbage values stay nil = no staging; real
    /// launches carry no pin.
    static var stagedCapsule: TimeCapsule? {
        guard let variant = UserDefaults.standard.string(forKey: "sooodreamy.kapsel"),
              variant == "titel" || variant == "ohnetitel" else { return nil }
        return TimeCapsule(
            id: "demo-capsule-\(variant)",
            title: variant == "titel"
                ? de("Für unseren Jahrestag", "For our anniversary")
                : nil,
            emoji: "💌",
            unlockAt: Date().addingTimeInterval(-3_600),
            createdBy: partnerId,
            forMember: myId,
            createdAt: Date().addingTimeInterval(-14 * 86_400),
            openedAt: Date(),
            unlocked: true,
            text: de("""
                Wenn du das liest, sind zwei Wochen vergangen. Ich wollte \
                dir schreiben, dass ich an uns denke — an den Abend am \
                Kanal und an alles, was noch kommt.
                """,
                     """
                By the time you read this, two weeks will have passed. I \
                wanted to write that I am thinking of us — of the evening \
                by the canal and of everything still ahead.
                """),
            photoId: nil)
    }

    /// Stages the demo state matching the active screenshot mode.
    /// A no-op for real launches and the About shot.
    static func stage(_ appState: AppState) {
        if ScreenshotMode.main {
            // One coherent stage, not three stories at once (EVAL P0-2):
            // a freshly created couple waiting for the partner. No
            // anniversary and no unread badge — relationship props exist
            // only once someone joined — and a plausible six-digit
            // pairing code. The dashboard's connection pill reads
            // ScreenshotMode and stays quiet instead of flashing server
            // errors.
            appState.couple = Couple(
                id: coupleId, code: "482913", name: nil,
                anniversary: nil, palette: nil,
                monogramStyle: nil, createdAt: Date(), members: [])
            return
        }
        guard ScreenshotMode.pairedDemo else { return }

        // The reveal shot tells ONE story (the gold seal) — it gets an
        // ordinary day, not the monthiversary the paired-dashboard shot
        // stages to prove the blend-colored milestone pane.
        appState.couple = demoCouple(monthiversaryToday: !ScreenshotMode.reveal)
        if ScreenshotMode.chat {
            appState.activeTab = .chat
            appState.partnerTyping = true
        } else if ScreenshotMode.reveal {
            // Both answered, seal unbroken on this device → the dashboard
            // shows the sealed card with the gold glow (K-03).
            appState.dailyEntry = DailyEntry(
                dateKey: SharedDates.todayKey(), questionId: nil, questionText: nil,
                myAnswer: de("Als du mir Frühstück ans Bett gebracht hast.",
                             "When you brought me breakfast in bed."),
                partnerAnswer: de("Unser Spaziergang im Regen.",
                                  "Our walk in the rain."),
                bothAnswered: true, streak: 14, customQuestion: nil)
        } else if ScreenshotMode.play {
            appState.activeTab = .play
        } else if ScreenshotMode.settings {
            appState.activeTab = .settings
        } else if ScreenshotMode.memories {
            appState.activeTab = .memories
        } else {
            // Paired dashboard: today's question still open (the everyday
            // state), a small streak, and two unread messages matching
            // the staged chat transcript.
            appState.dailyEntry = DailyEntry(
                dateKey: SharedDates.todayKey(), questionId: nil, questionText: nil,
                myAnswer: nil, partnerAnswer: nil,
                bothAnswered: false, streak: 6, customQuestion: nil)
            appState.unreadChat = 2
        }
    }

    // MARK: - In-app demo mode (Welle 7 [29])

    /// The runtime demo („Erst mal ansehen") reuses this staging: the
    /// paired everyday dashboard — open daily question, a small streak,
    /// two unread messages — one coherent story to walk through. Entered
    /// by tap instead of launch argument, so it takes no ScreenshotMode.
    static func stageDemoMode(_ appState: AppState) {
        appState.couple = demoCouple(monthiversaryToday: false)
        appState.dailyEntry = DailyEntry(
            dateKey: SharedDates.todayKey(), questionId: nil, questionText: nil,
            myAnswer: nil, partnerAnswer: nil,
            bothAnswered: false, streak: 6, customQuestion: nil)
        appState.unreadChat = 2
    }

    /// "Who am I" inside the runtime demo (the CI twin is `demoMemberId`).
    static var demoModeMemberId: String { myId }

    /// The staged conversation for the runtime demo's chat tab.
    static var demoModeTranscript: [Message] { transcript }

    // MARK: - The demo couple

    private static let coupleId = "demo-couple"
    private static let myId = "demo-me"
    private static let partnerId = "demo-partner"

    private static func demoCouple(monthiversaryToday: Bool) -> Couple {
        let now = Date()
        // Exactly 20 whole months together stages the blend-colored
        // monthiversary pane — the strongest proof that milestones wear
        // the couple's OWN shared color. 500 days is a deliberately
        // unremarkable everyday distance.
        let anniversary = (monthiversaryToday
            ? SharedDates.calendar.date(byAdding: .month, value: -20, to: now)
            : SharedDates.calendar.date(byAdding: .day, value: -500, to: now))
            ?? now
        let me = Member(
            id: myId, name: "Mia", avatar: "🦊", color: "#60A5FA",
            petName: nil, mood: "🥰", moodNote: nil, moodUpdatedAt: now,
            online: true, lastSeenAt: now, lastReadAt: now,
            nowPlaying: nil, energy: nil, presence: nil,
            joinedAt: anniversary)
        let partner = Member(
            id: partnerId, name: "Ben", avatar: "🦝", color: "#6EE7B7",
            petName: nil, mood: "😌", moodNote: nil, moodUpdatedAt: now,
            online: true, lastSeenAt: now, lastReadAt: now,
            nowPlaying: nil, energy: nil, presence: nil,
            joinedAt: anniversary)
        return Couple(
            id: coupleId, code: "482913", name: "Mia & Ben",
            anniversary: SharedDates.todayKey(anniversary),
            palette: CouplePaletteRules.derived(first: me.color,
                                                second: partner.color),
            monogramStyle: nil, createdAt: anniversary,
            members: [me, partner])
    }

    // MARK: - The staged conversation

    private static var transcript: [Message] {
        let yesterday = Date().addingTimeInterval(-19 * 3600)
        let today = Date().addingTimeInterval(-42 * 60)
        return [
            message("demo-msg-1", from: partnerId, at: yesterday,
                    de("Ich hab uns Kinokarten für Freitag besorgt 🎬",
                       "Got us movie tickets for Friday 🎬")),
            message("demo-msg-2", from: myId,
                    at: yesterday.addingTimeInterval(4 * 60),
                    de("Im Ernst? Du bist der Beste.",
                       "Seriously? You're the best."),
                    reactions: ["💜": [partnerId]]),
            message("demo-msg-3", from: partnerId,
                    at: yesterday.addingTimeInterval(7 * 60),
                    de("Reihe acht, Mitte — unsere Plätze.",
                       "Row eight, center — our seats.")),
            message("demo-msg-4", from: myId, at: today,
                    de("Ich freu mich schon den ganzen Tag.",
                       "I've been looking forward to it all day.")),
            message("demo-msg-5", from: partnerId,
                    at: today.addingTimeInterval(3 * 60),
                    de("Ich auch. Bringst du die Decke mit?",
                       "Me too. Will you bring the blanket?")),
            message("demo-msg-6", from: myId,
                    at: today.addingTimeInterval(5 * 60),
                    de("Versprochen.", "Promised."),
                    reactions: ["💞": [partnerId]]),
        ]
    }

    private static func message(
        _ id: String, from senderId: String, at createdAt: Date,
        _ text: String, reactions: [String: [String]]? = nil
    ) -> Message {
        Message(id: id, senderId: senderId, clientMessageId: nil,
                type: .text, text: text, title: nil, audioUrl: nil,
                durationSec: nil, photoId: nil, openWhen: nil,
                effect: nil, sticker: nil, reactions: reactions,
                editedAt: nil, createdAt: createdAt)
    }

    private static func de(_ german: String, _ english: String) -> String {
        L10n.isGerman ? german : english
    }
}
