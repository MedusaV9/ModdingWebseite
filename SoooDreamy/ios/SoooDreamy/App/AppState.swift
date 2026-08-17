import Foundation
import Observation
import SwiftUI
import WidgetKit

enum AppPhase: Equatable {
    case welcome      // no server configured yet
    case pairing      // server active, but not paired into a couple
    case main         // paired
}

enum AppTab: String, Hashable {
    case home, chat, play, memories, settings
}

enum QueuedCelebration {
    case level(LevelUpPayload)
    case badge(BadgeState)
}

/// Central app state: active server session, couple data, socket events.
@MainActor
@Observable
final class AppState {
    let servers = ServerStore()
    let socket = SocketClient()

    // Session data (per active server)
    var couple: Couple? {
        didSet { syncNotificationDamping() }
    }
    var events: [EventItem] = []
    var dailyEntry: DailyEntry? {
        didSet {
            // Keep the "streak at risk" evening nudge in sync with every
            // change (fetch, own answer, partner's socket event, sign-out).
            // The staged demo entry must never schedule a real reminder —
            // demo mode passes nil, which also clears anything pending.
            let entry = demoActive ? nil : dailyEntry
            Task { await ReminderManager.syncStreakGuard(entry: entry) }
        }
    }
    var stats: Stats?
    var sessionLoading = false
    /// Showcase photo for the photo widget (newest favorite, else newest).
    var widgetPhoto: Photo?

    /// Stroke count last mirrored to the widgets (see refreshWidgetCanvas).
    @ObservationIgnored private var widgetCanvasStrokeCount = 0
    /// Photo id whose bytes are currently in the shared widget cache.
    @ObservationIgnored private var cachedWidgetPhotoId: String?
    /// Compact active goal from the authenticated widget endpoint.
    var widgetGoal: WidgetSnapshotResponse.GoalSummary?
    /// Today's "on this day" memories for the memory widget.
    var widgetMemory: OnThisDayResponse?

    // UI state
    var activeTab: AppTab = .home {
        didSet {
            if activeTab == .chat, oldValue != .chat {
                markChatRead()
                markMissedVisited(.messages)
            }
            if activeTab == .memories, oldValue != .memories {
                CoupleNotify.clearDelivered(.photo)
                CoupleNotify.clearDelivered(.coupon)
                // Seen = visited (Dossier 40, idea 6): being in the place
                // checks the matching missed-inbox chips off by itself.
                markMissedVisited(.photos, .coupons, .songs, .canvas)
            }
        }
    }
    var toast: Toast?
    var incomingTouch: Touch?
    /// Post & Sendungen (P6-B): original touch ids that already bounced
    /// back — mirrors the server's once-per-original rule so the
    /// "Zurückschicken" affordance disables the moment the echo leaves
    /// (any device: fanout `echoOf` markers land here too).
    var echoedTouchIds: Set<String> = []
    /// Custom vibration relayed by the partner — drives the full-screen
    /// haptic moment overlay (haptics composer).
    var incomingHaptic: HapticSend?
    /// FullRelease R1-D: a delivered Zeitpost note — drives the sealed-
    /// envelope moment overlay (PostNoteOverlay) instead of a toast. The
    /// overlay clears it itself (close gesture / 8 s after opening); the
    /// sealed state deliberately WAITS for the tap — the ritual is the
    /// point, so no arrival-side timer races the person here.
    var incomingPostNote: PostNote?
    var partnerTyping = false
    var incomingMessageEffect: MessageEffect?
    var unreadChat = 0 {
        didSet { persistUnreadChat() }
    }
    var celebrate = false
    /// Welle 7 [30]: non-nil drives the pairing-ceremony overlay — the
    /// signature moment after a completed pairing or device link.
    var pairingCeremony: PairingCeremonyMoment?
    /// Welle 7 [29]: „Erst mal ansehen" — the app explorable WITHOUT a
    /// server. All demo state is staged in memory (ScreenshotSeed); the
    /// UserDefaults flag is THE only thing that persists, so leaving the
    /// demo is a complete evaporation.
    private(set) var demoActive = false
    /// One-shot hand-over from the demo's „Eigenen Server verbinden" exit:
    /// OnboardingFlowView consumes it and opens the server sheet directly.
    var demoExitToSetup = false
    var uiRefresh = 0

    /// Aggregated activity missed since the last inbox check
    /// (`GET /api/inbox`) — non-nil drives the "While you were away" card
    /// on the dashboard. The card is a checklist (Dossier 40): categories
    /// get checked off in `missedVisited` and the card dissolves itself
    /// once everything was actually seen.
    var missedInbox: InboxResponse?
    /// Checked-off missed-inbox categories (`MissedInboxLogic.Category`
    /// raw values plus "need") since the current card appeared.
    var missedVisited: Set<String> = []
    /// Dismissed card parked for the 5-second undo window (Dossier 40,
    /// idea 15) — the since-window already advanced, so the X must not be
    /// final.
    var dismissedInbox: InboxResponse?
    private var dismissFinalizeTask: Task<Void, Error>?

    /// True after a `503 couple_data_quarantined` — the server moved damaged
    /// couple data into protective custody. Cleared by the next successful
    /// couple fetch, so the state ends the moment the operator repairs it.
    var coupleDataQuarantined = false

    /// "Du bist dran!" — open games awaiting my action (inbox `games`
    /// bucket, current state). Drives the Play-tab badge and the hub hint.
    var gamesAwaitingMe: [InboxResponse.GamesBucket.AwaitingGame] = []

    /// Last touch received from the partner — feeds widgets & live activities.
    /// Seeded from the shared snapshot so it survives app relaunches.
    var lastTouchType: String?
    var lastTouchAt: Date?

    // „Nähe trotz Distanz" — thinking-of-you pulses
    /// Pulse relayed live (or replayed right after launch) — drives the
    /// full-screen moment overlay while the haptic pattern plays.
    var incomingPulse: Pulse?
    /// >1 when a launch replay found several missed pulses ("+2 more").
    var incomingPulseCount = 0
    /// When I last sent a pulse — drives the 30 s cooldown ring in the UI
    /// (mirrors the server's throttle so buttons disable instead of 429ing).
    var lastPulseSentAt: Date?

    // v10 „Der große Runde" — pairing recovery client
    /// Set right after create/join: the one-time recovery key, presented in
    /// the "save your key" ceremony sheet, then nilled (keychain keeps it).
    var freshRecoveryKey: String?
    /// Onboarding-eval fix: while the pairing ceremony plays, the fresh key
    /// waits HERE instead of in `freshRecoveryKey` — otherwise RootView's
    /// sheet slides over the 3.6 s color merge the couple came for. The key
    /// moves on stage only after `endPairingCeremony()` + a 300 ms breath.
    @ObservationIgnored private var heldRecoveryKey: String?
    /// A scanned/opened `sooodreamy://rejoin` link that could not be
    /// completed automatically — PairingView consumes it to prefill fields.
    var pendingRejoin: RejoinLink?
    /// A `sooodreamy://link` device link that could not be completed
    /// automatically — PairingView consumes it to prefill the link path.
    var pendingDeviceLink: DeviceLinkURL?
    /// W7-Rest: a `sooodreamy://reveal` tap (widget seal / island pill)
    /// waiting for the dashboard — consumed once the daily entry is loaded,
    /// so a cold start still lands inside the ceremony.
    var pendingRevealRequest = false
    /// W6-Rest chat→album bridge: the photo the gallery should open its
    /// lightbox on. MemoriesView pushes the gallery while this is set; the
    /// gallery consumes it once its photo list is loaded.
    var pendingGalleryPhotoId: String?
    /// True while a silent 401 → rejoin repair runs (guards against loops).
    @ObservationIgnored private var sessionRecoveryInFlight = false
    /// Signature of the last snapshot handed to WidgetKit — used to skip
    /// redundant `reloadAllTimelines()` calls (v10 performance pass).
    @ObservationIgnored private var lastWidgetSnapshotSignature: Data?

    // Level, Badges & Platform — logic in AppStatePlatform.swift
    var levelState: LevelState?
    var badges: [BadgeState] = []
    var quest: QuestState?
    var pendingIconGift: IconGift?
    var dateNight: DateNight?
    /// Duet currently counting down / playing (full-screen overlay).
    var activeDuet: DuetSession?
    /// Level-up ceremony queued for full-screen presentation.
    var levelUpCeremony: LevelUpPayload?
    /// Freshly unlocked badge (award ceremony overlay).
    var badgeCeremony: BadgeState?
    /// Badges coalesced INTO the ceremony on stage (DelightArbiter): a
    /// level-up and its badges from the same server write become ONE
    /// ceremony with stacked medals instead of a chain of fanfares.
    var celebrationBadgeStack: [BadgeState] = []
    /// When the ceremony on stage was presented — the coalesce anchor.
    @ObservationIgnored var celebrationPresentedAt: Date?
    @ObservationIgnored var celebrationQueue = FIFOQueue<QueuedCelebration>()
    /// Last live heartbeat tap from the partner (3D heart + duet view pulse).
    var partnerHeartbeatTap: HeartbeatTapPayload?
    var partnerTapCount = 0
    @ObservationIgnored var duetPlayTask: Task<Void, Never>?

    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var touchTask: Task<Void, Never>?
    @ObservationIgnored private var hapticTask: Task<Void, Never>?
    @ObservationIgnored private var pulseTask: Task<Void, Never>?
    @ObservationIgnored private var messageEffectTask: Task<Void, Never>?
    @ObservationIgnored private var typingTask: Task<Void, Never>?
    @ObservationIgnored private var eventObserver: NSObjectProtocol?
    @ObservationIgnored private var revokeObserver: NSObjectProtocol?
    /// True while the offline outbox is being replayed — every entry point
    /// (foreground refresh, socket welcome) funnels through ONE flight.
    @ObservationIgnored private var outboxReplayInFlight = false
    /// Rate limit for "partner is online" alerts (max once per 10 min).
    @ObservationIgnored private var lastOnlineAlertAt: Date?

    init() {
        let snapshot = SharedStore.readSnapshot()
        lastTouchType = snapshot?.lastTouchType
        lastTouchAt = snapshot?.lastTouchAt
        restoreCoreColdCache()
        eventObserver = NotificationCenter.default.addObserver(
            forName: .serverEvent, object: nil, queue: .main
        ) { [weak self] note in
            guard let event = note.object as? ServerEvent else { return }
            Task { @MainActor [weak self] in
                self?.handle(event)
            }
        }
        // The socket saw the terminal close (4001): this device's session
        // was revoked remotely — tear it down, honestly.
        revokeObserver = NotificationCenter.default.addObserver(
            forName: .sessionRevoked, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleRemoteSessionRevoked()
            }
        }
        // Welle 7 [29]: a previous run left the app in demo mode — re-stage
        // the demo couple before the first frame (the flag is the only bit
        // that survived; everything visible is rebuilt right here).
        if DemoMode.persistedActive {
            demoActive = true
            ScreenshotSeed.stageDemoMode(self)
        }
    }

    // MARK: Derived state

    var phase: AppPhase {
        if demoActive { return .main }   // Welle 7 [29]: the staged tour
        guard let profile = servers.activeProfile else { return .welcome }
        return profile.isPaired ? .main : .pairing
    }

    /// CI screenshot launches and the in-app demo have no server profile —
    /// the staged demo couple provides the "who am I" instead (nil outside
    /// those runs).
    var memberId: String? {
        if demoActive { return ScreenshotSeed.demoModeMemberId }
        return servers.activeProfile?.memberId ?? ScreenshotSeed.demoMemberId
    }

    /// THIS device's session id (Keychain, next to the token) — the anchor
    /// for echo detection and the "this device" row in the device manager.
    var sessionId: String? { servers.activeProfile?.sessionId }

    /// True when a WS frame was caused by THIS very session (own echo of an
    /// idempotent broadcast). UI decisions only — see MultiDeviceRules.
    func isOwnEcho(_ event: ServerEvent) -> Bool {
        MultiDeviceRules.isOwnEcho(origin: event.origin, sessionId: sessionId)
    }

    /// True when a WS frame was caused by MY member on ANOTHER device —
    /// "from me, other device", never a partner event.
    func isOwnOtherDevice(_ event: ServerEvent) -> Bool {
        MultiDeviceRules.isOwnOtherDevice(origin: event.origin,
                                          memberId: memberId, sessionId: sessionId)
    }

    /// Central partner-effect gate: true when a frame may drive
    /// partner-facing celebrations (toasts, sounds, notifications) — it was
    /// NOT caused by my member, neither this session's own echo nor my
    /// member on another device. Frames without an origin marker (old
    /// servers, system frames) pass — see MultiDeviceRules.
    func allowsPartnerEffects(_ event: ServerEvent) -> Bool {
        MultiDeviceRules.allowsPartnerEffects(origin: event.origin,
                                              memberId: memberId, sessionId: sessionId)
    }

    var api: API? {
        // Demo mode is a stubbed connection by contract — no server call
        // ever leaves the device, even when a profile happens to exist.
        guard !demoActive else { return nil }
        guard let profile = servers.activeProfile, let url = profile.baseURL else { return nil }
        return API(baseURL: url, token: profile.token)
    }

    var me: Member? {
        guard let couple, let memberId else { return nil }
        return couple.members.first { $0.id == memberId }
    }

    var partner: Member? {
        guard let couple, let memberId else { return nil }
        return couple.members.first { $0.id != memberId }
    }

    var partnerName: String {
        partner?.petName ?? partner?.name ?? L10n.t("misc.partnerDefault")
    }

    var daysTogether: Int? {
        guard let couple else { return nil }
        return SharedDates.daysSince(couple.anniversary) ?? SharedDates.daysSince(
            SharedDates.todayKey(couple.createdAt))
    }

    /// Next upcoming event (with days remaining).
    var nextEvent: (event: EventItem, days: Int)? {
        events
            .compactMap { ev -> (EventItem, Int)? in
                guard let d = SharedDates.daysUntil(ev.date, repeatsYearly: ev.repeatsYearly), d >= 0 else { return nil }
                return (ev, d)
            }
            .min { $0.1 < $1.1 }
            .map { (event: $0.0, days: $0.1) }
    }

    // MARK: Lifecycle

    func bootstrap() async {
        L10n.language = L10n.language          // trigger shared-language mirror
        Haptics.shared.prepare()
        SoundEngine.shared.prepare()
        guard phase == .main else { return }
        // Demo mode: everything was staged in init — no session restore, no
        // socket, no live activity, no recovery key. The tour is complete.
        guard !demoActive else { return }
        restoreUnreadChat()
        await refreshAll()
        connectSocket()
        CouplePulseController.startIfEnabled(from: self)
        await ensureRecoveryKey()
    }

    // MARK: Demo mode (Welle 7 [29])

    /// „Erst mal ansehen": stages the demo couple and walks straight into
    /// the main UI — no server, no account, nothing leaves the device.
    func enterDemo() {
        guard !demoActive else { return }
        // Choosing the demo replaces a scanned-invite setup intent — a
        // parked code must not resurface in a much later pairing flow.
        PendingInvite.clear()
        demoActive = true
        UserDefaults.standard.set(true, forKey: DemoMode.flagKey)
        ScreenshotSeed.stageDemoMode(self)
        activeTab = .home
        Haptics.shared.success()
    }

    /// The demo badge's exit: drop the flag, evaporate every staged prop
    /// and land back where a real start begins. `toServerSetup` carries
    /// the „Eigenen Server verbinden" intent into the welcome flow.
    func exitDemo(toServerSetup: Bool) {
        guard demoActive else { return }
        demoActive = false
        UserDefaults.standard.removeObject(forKey: DemoMode.flagKey)
        couple = nil
        events = []
        dailyEntry = nil
        stats = nil
        unreadChat = 0
        partnerTyping = false
        missedInbox = nil
        missedVisited = []
        dismissedInbox = nil
        gamesAwaitingMe = []
        activeTab = .home
        // Chat-language singletons survive the view teardown — a demo
        // translation/transcript must never surface in a real couple.
        ChatTranslationCenter.shared.reset()
        VoiceTranscriptCenter.shared.configure(coupleId: nil)
        demoExitToSetup = toServerSetup && servers.activeProfile == nil
    }

    // MARK: Pairing recovery (v10)

    /// The recovery key stored for the active profile (keychain only).
    var storedRecoveryKey: String? {
        guard let profile = servers.activeProfile else { return nil }
        return SharedKeychain.recoveryKey(profileID: profile.id)
    }

    /// Members paired before v10 have no key in the keychain (and legacy
    /// couples none on the server either) — issue one silently on launch so
    /// EVERYONE ends up rejoin-capable without lifting a finger.
    func ensureRecoveryKey() async {
        guard let api, let profile = servers.activeProfile else { return }
        guard SharedKeychain.recoveryKey(profileID: profile.id) == nil else { return }
        do {
            let issued = try await api.issueRecoveryKey()
            _ = SharedKeychain.setRecoveryKey(issued.recoveryKey, profileID: profile.id)
        } catch {
            // Non-fatal: retried on the next launch; rejoin-by-old-token
            // still works meanwhile.
        }
    }

    /// Silent session healing: an expired (never revoked) bearer is a valid
    /// rejoin proof — so a 401 becomes a background re-attach instead of the
    /// old "please pair again" logout. Returns true when the session was
    /// repaired.
    ///
    /// The recovery key is deliberately NOT an automatic proof anymore
    /// (Re-Eval Runde 2): revoke tombstones die server-side after 24 h, so a
    /// revoked device's old token eventually answers `unknown_session` — and
    /// the silent recovery-key fallback re-admitted exactly the device a
    /// human had kicked. `unknown_session` is therefore terminal like
    /// `session_revoked`; the recovery key stays a CONSCIOUS action in the
    /// pairing flow (`performRejoin` / PairingView).
    @discardableResult
    func recoverSession() async -> Bool {
        // A repair is already running — report success so concurrent 401
        // handlers don't race it into a logout; the running task decides.
        guard !sessionRecoveryInFlight else { return true }
        guard let profile = servers.activeProfile,
              let url = profile.baseURL else { return false }
        guard !Self.isAutoRecoveryBlocked(profileID: profile.id) else { return false }
        sessionRecoveryInFlight = true
        defer { sessionRecoveryInFlight = false }
        let api = API(baseURL: url, token: nil)

        // The ONLY automatic proof: the old bearer (server accepts expired
        // ones within the rejoin grace; revoked ones it refuses).
        guard let oldToken = profile.token else { return false }
        do {
            let auth = try await api.rejoin(oldToken: oldToken)
            completeAuth(profileID: profile.id, auth: auth, quiet: true)
            showToast(L10n.t("recovery.sessionHealed"), style: .success)
            return true
        } catch {
            // REVOKED — or a token this server no longer knows (revoke
            // tombstone pruned after 24 h): both are terminal. Any silent
            // fallback here would be the self-re-admission of a kicked
            // device that this guard exists to prevent.
            let code = (error as? APIError)?.serverCode
            if code == "session_revoked" || code == "unknown_session" {
                handleRemoteSessionRevoked()
            }
            return false
        }
    }

    // MARK: Terminal revocation (contract v11)

    /// UserDefaults key marking a profile whose session was explicitly
    /// revoked — automatic recovery proofs are refused until a conscious
    /// manual rejoin clears the block again.
    private static func revokedBlockKey(_ profileID: UUID) -> String {
        "session.revokedBlock.\(profileID.uuidString)"
    }

    static func isAutoRecoveryBlocked(profileID: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: revokedBlockKey(profileID))
    }

    static func blockAutoRecovery(profileID: UUID) {
        UserDefaults.standard.set(true, forKey: revokedBlockKey(profileID))
    }

    static func clearAutoRecoveryBlock(profileID: UUID) {
        UserDefaults.standard.removeObject(forKey: revokedBlockKey(profileID))
    }

    /// Terminal session revocation (WS close 4001 or a `session_revoked`
    /// API verdict): this device was signed out from another device. Token
    /// and session id leave the keychain (`clearSession` inside
    /// `leaveDevice`), the recovery proofs get locked, and the person sees
    /// the honest "signed out by another device" state — the app lands on
    /// the reconnect screen, where rejoining stays a CONSCIOUS choice.
    func handleRemoteSessionRevoked() {
        guard let profile = servers.activeProfile else { return }
        // Idempotent: 4001 close + 401 fallout may both land here.
        let alreadyHandled = Self.isAutoRecoveryBlocked(profileID: profile.id)
            && profile.token == nil
        Self.blockAutoRecovery(profileID: profile.id)
        guard !alreadyHandled else { return }
        leaveDevice()
        Haptics.shared.warning()
        showToast(L10n.t("devices.revokedRemote.notice"), style: .error)
    }

    /// Switch to another saved server (its own pairing/session context).
    func activateProfile(_ id: UUID) async {
        guard id != servers.activeProfileID else { return }
        socket.disconnect()
        couple = nil
        events = []
        dailyEntry = nil
        stats = nil
        widgetGoal = nil
        widgetMemory = nil
        missedInbox = nil
        missedVisited = []
        dismissedInbox = nil
        gamesAwaitingMe = []
        servers.setActive(id: id)
        restoreCoreColdCache()
        restoreUnreadChat()
        if let profile = servers.activeProfile {
            showToast(L10n.t("server.switched", ["name": profile.name]), style: .success)
        }
        if phase == .main {
            await refreshAll()
            connectSocket()
            CouplePulseController.startIfEnabled(from: self)
        }
    }

    /// Called after successful create/join/rejoin on a profile.
    /// `quiet` skips the celebration — used by the silent session healing.
    /// `arrival` picks the ceremony headline (device link vs. pairing);
    /// nil means "no ceremony" — a rejoin is a repair, not an arrival.
    func completeAuth(profileID: UUID, auth: AuthResponse, quiet: Bool = false,
                      arrival: PairingCeremonyMoment.Kind? = .paired) {
        // A real session always wins over the staged tour — evaporate the
        // demo before attaching (e.g. a rejoin/link QR scanned mid-demo).
        if demoActive { exitDemo(toServerSetup: false) }
        // A successful auth is always a conscious action (create/join/
        // rejoin/link) — it unlocks the automatic recovery proofs again.
        Self.clearAutoRecoveryBlock(profileID: profileID)
        // … and it settles any scanned-invite intent: a still-parked code
        // is either just consumed or superseded — never for later.
        PendingInvite.clear()
        servers.attachSession(profileID: profileID, token: auth.token,
                              coupleId: auth.coupleId, memberId: auth.memberId,
                              sessionId: auth.sessionId, expiresAt: auth.expiresAt)
        servers.setActive(id: profileID)
        couple = auth.couple
        servers.rememberCoupleCode(profileID: profileID, code: auth.couple.code)
        // v10: the one-time recovery key goes straight into the (iCloud)
        // keychain; the ceremony sheet then shows it once for paper backup.
        if let key = auth.recoveryKey {
            _ = SharedKeychain.setRecoveryKey(key, profileID: profileID)
            freshRecoveryKey = key
        }
        connectSocket()
        if !quiet {
            // Welle 7 [30]: with both members aboard, the color-merge
            // ceremony is THE arrival moment; a still-waiting solo
            // creator keeps the gentle hearts until the partner joins.
            if let arrival, couple?.members.count ?? 0 >= 2 {
                beginPairingCeremony(kind: arrival)
            } else {
                celebrateNow()
            }
        }
        Task {
            await refreshAll()
            CouplePulseController.startIfEnabled(from: self)
            if NotificationPrefs.enabled {
                _ = await RemotePushRegistration.requestIfAuthorized()
            }
        }
    }

    /// Welle 7 [30]: arms the pairing-ceremony overlay once the couple is
    /// whole on this device. One cue only (`.pairing` — two soft pulses
    /// merging into one beat): the visual, its sound and its haptic twin
    /// are ONE moment, no fanfare stacked on top (one-channel rule). By
    /// construction this fires once per pairing/link, far under any
    /// delight budget.
    func beginPairingCeremony(kind: PairingCeremonyMoment.Kind) {
        guard pairingCeremony == nil,
              let couple, couple.members.count >= 2,
              let myId = memberId,
              let mine = couple.members.first(where: { $0.id == myId }),
              let partner = couple.members.first(where: { $0.id != myId }) else { return }
        pairingCeremony = PairingCeremonyMoment(
            myName: mine.name, partnerName: partner.name,
            myColorHex: mine.color, partnerColorHex: partner.color,
            kind: kind)
        // The recovery-key sheet must never cover the merge: park the key
        // until the ceremony has fully played (strict sequencing, not luck).
        if let key = freshRecoveryKey {
            heldRecoveryKey = key
            freshRecoveryKey = nil
        }
        AppCue.pairing.play()
    }

    func endPairingCeremony() {
        pairingCeremony = nil
        releaseHeldRecoveryKey()
    }

    /// Second act of the arrival: the ceremony has ended — after a 300 ms
    /// exhale the parked recovery key takes the stage (RootView's existing
    /// sheet binding fires only now, because only now the key is set).
    private func releaseHeldRecoveryKey() {
        guard let key = heldRecoveryKey else { return }
        heldRecoveryKey = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            freshRecoveryKey = key
        }
    }

    func registerPushToken(_ token: String) async {
        guard NotificationPrefs.enabled,
              let api,
              let bundleId = Bundle.main.bundleIdentifier else { return }
        _ = try? await api.registerPushDevice(
            apnsToken: token,
            environment: RemotePushRegistration.environment,
            bundleId: bundleId,
            language: L10n.lang
        )
    }

    func unregisterPushDevice() async {
        guard let api else { return }
        try? await api.unregisterPushDevice()
    }

    func connectSocket() {
        guard let profile = servers.activeProfile,
              let url = profile.baseURL,
              let token = profile.token else { return }
        socket.connect(baseURL: url, token: token)
    }

    /// iCloud restore: the server list just got replaced — drop the
    /// old session state and reconnect to the (new) active profile.
    func reloadAfterRestore() async {
        socket.disconnect()
        couple = nil
        events = []
        dailyEntry = nil
        stats = nil
        widgetGoal = nil
        widgetMemory = nil
        missedInbox = nil
        missedVisited = []
        dismissedInbox = nil
        gamesAwaitingMe = []
        restoreCoreColdCache()
        restoreUnreadChat()
        if phase == .main {
            await refreshAll()
            connectSocket()
            CouplePulseController.startIfEnabled(from: self)
        }
    }

    // MARK: Data refresh

    func refreshAll() async {
        sessionLoading = couple == nil
        defer { sessionLoading = false }
        await refreshCouple()
        await replayOfflineOperations()
        async let e: Void = refreshEvents()
        async let d: Void = refreshDaily()
        async let s: Void = refreshStats()
        async let p: Void = refreshWidgetPhoto()
        async let c: Void = refreshWidgetCanvas()
        async let i: Void = refreshInbox()
        async let g: Void = refreshGamification()   // Level/badges/quest
        async let w: Void = refreshWidgetCore()
        _ = await (e, d, s, p, c, i, g, w)
        updateWidgetSnapshot()
    }

    private var offlineOutboxScope: OutboxScope? {
        guard let profile = servers.activeProfile,
              let coupleID = profile.coupleId,
              let memberID = profile.memberId else { return nil }
        return OutboxScope(profileID: profile.id, coupleID: coupleID, memberID: memberID)
    }

    func answerDailyOfflineFirst(dateKey: String, questionId: Int,
                                 text: String,
                                 questionText: LText? = nil) async throws -> DailyEntry {
        guard let api, let scope = offlineOutboxScope else {
            throw URLError(.notConnectedToInternet)
        }
        // Schlussrunde 5: the rendered question's bilingual text rides
        // along so the server can store it with the pin (mixed-version
        // couples render the pinned question from it).
        var payload = ["dateKey": dateKey, "questionId": String(questionId), "text": text]
        if let questionText {
            payload["questionTextDE"] = questionText.de
            payload["questionTextEN"] = questionText.en
        }
        let operation = OfflineOutboxStore.shared.enqueue(
            kind: .dailyAnswer,
            payload: payload,
            scope: scope
        )
        OfflineOutboxStore.shared.markOperationAttempt(
            id: operation.clientOperationID, scope: scope
        )
        do {
            let entry = try await api.answerDaily(
                dateKey: dateKey,
                questionId: questionId,
                text: text,
                questionText: questionText,
                clientOperationId: operation.clientOperationID
            )
            OfflineOutboxStore.shared.removeOperation(
                id: operation.clientOperationID, scope: scope
            )
            return entry
        } catch {
            // Schlussrunde 5: a pin mismatch is permanent — replaying the
            // same (wrong) questionId later could only 409 again, so the
            // queued copy goes now. The card adopts the pinned question
            // from the rethrown details and the user resubmits under it.
            if case APIError.httpDetailed(_, let code, _, _, _) = error,
               code == "daily_question_mismatch" {
                OfflineOutboxStore.shared.removeOperation(
                    id: operation.clientOperationID, scope: scope
                )
            }
            throw error
        }
    }

    /// Returns the FULL move response: a decisive (or replayed-final,
    /// `duplicate:true`) move carries the ended `game`, which the engine
    /// adopts so a retry on an already-ended session converges instead of
    /// erroring (contract v11).
    func sendGameMoveOfflineFirst(gameId: String, data: JSONValue,
                                  kind: OfflineOperationKind) async throws -> MoveResponse {
        precondition(kind == .questCheck || kind == .rating)
        guard let api, let scope = offlineOutboxScope else {
            throw URLError(.notConnectedToInternet)
        }
        let encoded = try JSONEncoder().encode(data).base64EncodedString()
        let operation = OfflineOutboxStore.shared.enqueue(
            kind: kind,
            payload: ["gameId": gameId, "data": encoded],
            scope: scope
        )
        OfflineOutboxStore.shared.markOperationAttempt(
            id: operation.clientOperationID, scope: scope
        )
        let response = try await api.sendMoveDetailed(
            gameId: gameId,
            data: data,
            clientMoveId: operation.clientOperationID
        )
        OfflineOutboxStore.shared.removeOperation(
            id: operation.clientOperationID, scope: scope
        )
        return response
    }

    private func replayOfflineOperations() async {
        // Single-flight: the foreground refresh and every socket `welcome`
        // both call this — concurrent replays would double-send (the
        // idempotency keys catch it server-side, but why bet on that).
        guard !outboxReplayInFlight else { return }
        outboxReplayInFlight = true
        defer { outboxReplayInFlight = false }
        guard let api, let scope = offlineOutboxScope else { return }
        let outbox = OfflineOutboxStore.shared
        for operation in outbox.operations(
            for: scope, kinds: [.dailyAnswer, .questCheck, .rating, .touch, .pulse,
                                .postSchedule, .touchEcho]
        ) {
            // Emotional moments expire — a replayed pulse from yesterday
            // would be strange rather than sweet.
            if OutboxFreshness.isExpired(kind: operation.kind, createdAt: operation.createdAt) {
                outbox.removeOperation(id: operation.clientOperationID, scope: scope)
                continue
            }
            outbox.markOperationAttempt(id: operation.clientOperationID, scope: scope)
            do {
                switch operation.kind {
                case .dailyAnswer:
                    guard let dateKey = operation.payload["dateKey"],
                          let rawQuestion = operation.payload["questionId"],
                          let questionID = Int(rawQuestion),
                          let text = operation.payload["text"] else {
                        outbox.removeOperation(id: operation.clientOperationID, scope: scope)
                        continue
                    }
                    // Schlussrunde 5: replay the question text the answer
                    // was written for, so an offline first answer still
                    // pins renderable text on the server.
                    var questionText: LText?
                    if let de = operation.payload["questionTextDE"],
                       let en = operation.payload["questionTextEN"] {
                        questionText = LText(de: de, en: en)
                    }
                    _ = try await api.answerDaily(
                        dateKey: dateKey,
                        questionId: questionID,
                        text: text,
                        questionText: questionText,
                        clientOperationId: operation.clientOperationID
                    )
                case .questCheck, .rating:
                    guard let gameID = operation.payload["gameId"],
                          let encoded = operation.payload["data"],
                          let bytes = Data(base64Encoded: encoded),
                          let data = try? JSONDecoder().decode(JSONValue.self, from: bytes) else {
                        outbox.removeOperation(id: operation.clientOperationID, scope: scope)
                        continue
                    }
                    _ = try await api.sendMove(
                        gameId: gameID,
                        data: data,
                        clientMoveId: operation.clientOperationID
                    )
                case .touch:
                    guard let raw = operation.payload["type"],
                          let kind = TouchKind(rawValue: raw) else {
                        outbox.removeOperation(id: operation.clientOperationID, scope: scope)
                        continue
                    }
                    // Same idempotency key as the original dispatch — a
                    // replay of an already-committed touch answers
                    // {duplicate:true}, which decodes as success.
                    try await api.sendTouch(kind,
                                            clientOperationId: operation.clientOperationID)
                case .pulse:
                    guard let raw = operation.payload["kind"],
                          let kind = PulseKind(rawValue: raw) else {
                        outbox.removeOperation(id: operation.clientOperationID, scope: scope)
                        continue
                    }
                    try await api.sendPulse(kind,
                                            clientOperationId: operation.clientOperationID)
                case .postSchedule:
                    // P6-B: a Zeitpost drafted offline replays with its
                    // original deliverAt — the SERVER judges whether the
                    // moment already passed (400 bad_deliver_at, below).
                    guard let kindRaw = operation.payload["kind"],
                          let kind = PostKind(rawValue: kindRaw),
                          let deliverRaw = operation.payload["deliverAt"],
                          let deliverAt = API.isoDate(deliverRaw) else {
                        outbox.removeOperation(id: operation.clientOperationID, scope: scope)
                        continue
                    }
                    _ = try await api.schedulePost(
                        touch: operation.payload["type"].flatMap(TouchKind.init(rawValue:)),
                        pulse: operation.payload["pulseKind"].flatMap(PulseKind.init(rawValue:)),
                        note: kind == .note ? operation.payload["note"] : nil,
                        deliverAt: deliverAt,
                        clientOperationId: operation.clientOperationID)
                case .touchEcho:
                    // Only replayed inside the 10-minute echo window (the
                    // freshness gate above dropped anything older).
                    guard let touchId = operation.payload["touchId"] else {
                        outbox.removeOperation(id: operation.clientOperationID, scope: scope)
                        continue
                    }
                    _ = try await api.echoTouch(id: touchId,
                                                clientOperationId: operation.clientOperationID)
                case .reaction:
                    continue // ChatModel reconciles message UI while replaying these.
                }
                outbox.removeOperation(id: operation.clientOperationID, scope: scope)
            } catch {
                // Schlussrunde 6: a daily answer that lost the pin race
                // mid-replay is salvaged, not silently dropped — the text
                // survives as the day's draft, the pinned question is
                // adopted, and the humanizer toast asks for a re-send.
                if operation.kind == .dailyAnswer,
                   case APIError.httpDetailed(_, let code, _, _, let details) = error,
                   code == "daily_question_mismatch" {
                    if let dateKey = operation.payload["dateKey"],
                       let text = operation.payload["text"] {
                        DailyAnswerDraftStore.save(
                            text,
                            profileID: servers.activeProfileID?.uuidString,
                            dateKey: dateKey)
                    }
                    outbox.removeOperation(id: operation.clientOperationID, scope: scope)
                    if let pinnedId = details.questionId {
                        await adoptPinnedDailyQuestion(questionId: pinnedId,
                                                       questionText: details.questionText)
                    }
                    handleAPIError(error)
                    continue
                }
                // P6-B: a Zeitpost whose deliverAt expired while queued is a
                // poison pill WITH a voice — the giveUp below would drop it
                // silently, but the sender deserves to know their moment
                // passed (humanizer key `error.code.bad_deliver_at`).
                if operation.kind == .postSchedule,
                   (error as? APIError)?.serverCode == "bad_deliver_at" {
                    outbox.removeOperation(id: operation.clientOperationID, scope: scope)
                    handleAPIError(error)
                    continue
                }
                // Poison pill: permanently rejected operations are dropped so
                // one bad entry can never dam up the whole replay queue.
                let verdict = OutboxRetryPolicy.verdict(
                    failure: OutboxFailureKind(classifying: error),
                    attemptCount: operation.attemptCount + 1)
                if verdict == .giveUp {
                    outbox.removeOperation(id: operation.clientOperationID, scope: scope)
                    continue
                }
                break // Preserve FIFO; network recovery will call refreshAll again.
            }
        }
    }

    func refreshWidgetCore() async {
        if let remote = try? await api?.widgetSnapshot() {
            widgetGoal = remote.goal
        }
        // Memory widget — independent try? so a pre-8.0 server (route
        // missing) still refreshes the goal above.
        widgetMemory = try? await api?.onThisDay()
    }

    // MARK: Missed inbox

    /// UserDefaults key for the last inbox check, scoped per couple so
    /// switching servers/couples never leaks another couple's window.
    private var lastInboxKey: String? {
        servers.activeProfile?.coupleId.map { "inbox.lastAt.\($0)" }
    }

    /// Fetch everything missed since the last check and surface it as the
    /// "While you were away" card. Best effort: pre-v1.6 servers 404 here,
    /// which stays silent; the window only advances after a successful fetch
    /// (or on the very first run, which just seeds the timestamp).
    func refreshInbox() async {
        guard let api, let key = lastInboxKey else { return }
        let defaults = UserDefaults.standard
        guard let stored = defaults.object(forKey: key) as? Double else {
            defaults.set(Date().timeIntervalSince1970, forKey: key)
            return
        }
        guard let inbox = try? await api.inbox(since: Date(timeIntervalSince1970: stored)) else {
            return
        }
        defaults.set(Date().timeIntervalSince1970, forKey: key)
        // The games bucket is current-state (not since-filtered) — always
        // mirror it so the Play-tab badge is fresh on every app open.
        gamesAwaitingMe = inbox.games?.awaitingMe ?? []
        applyInboxSideEffects(inbox)
        if !inbox.isEmpty {
            missedInbox = inbox
            missedVisited = []
        }
    }

    /// Missed messages and touches feed the SAME state the live socket
    /// events feed — the unread-chat badge and the "last touch" shown on
    /// widgets/live activities — so a WS gap can neither hide mail nor
    /// freeze the touch teaser. The merge rules keep an (older) inbox
    /// window from rewinding fresher local truth (see InboxMergeRules).
    private func applyInboxSideEffects(_ inbox: InboxResponse) {
        // An open chat reads everything the moment it renders — the badge
        // stays down, exactly like the live-message path.
        if activeTab != .chat {
            unreadChat = InboxMergeRules.mergedUnreadChat(
                localUnread: unreadChat,
                missedCount: inbox.messages?.count,
                newestMissedAt: inbox.messages?.last?.createdAt,
                myLastReadAt: me?.lastReadAt)
        }
        if let teaser = inbox.touches?.last,
           InboxMergeRules.adoptsTouchTeaser(teaserAt: teaser.createdAt,
                                             currentLastTouchAt: lastTouchAt) {
            if let type = teaser.type { lastTouchType = type }
            lastTouchAt = teaser.createdAt
            pushLiveActivityUpdates()
        }
    }

    /// Check missed-inbox categories off (Dossier 40, ideas 6/7): visiting
    /// the place counts, not dismissing the card. The card watches
    /// `missedVisited` and dissolves itself once everything was seen.
    func markMissedVisited(_ categories: MissedInboxLogic.Category...) {
        guard missedInbox != nil else { return }
        for category in categories {
            missedVisited.insert(category.rawValue)
        }
    }

    /// The open need was acknowledged from the card hero.
    func markMissedNeedVisited() {
        guard missedInbox != nil else { return }
        missedVisited.insert("need")
    }

    /// X on the card parks it for the undo window (Dossier 40, idea 15) —
    /// the since-window already advanced, so dismiss must not be final.
    func dismissMissedInbox() {
        guard let inbox = missedInbox else { return }
        missedInbox = nil
        dismissedInbox = inbox
        dismissFinalizeTask?.cancel()
        dismissFinalizeTask = Task {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            self.dismissedInbox = nil
        }
    }

    /// Bring the parked digest back before the undo window closes.
    func undoMissedDismiss() {
        dismissFinalizeTask?.cancel()
        dismissFinalizeTask = nil
        guard let inbox = dismissedInbox else { return }
        dismissedInbox = nil
        missedInbox = inbox
    }

    // MARK: Chat read state

    /// Zero the unread badge and tell the server the chat was read
    /// (read receipts). Older servers 404 the POST — silently ignored.
    func markChatRead() {
        unreadChat = 0
        // Seen in-app → stale message alerts leave the Notification Center.
        CoupleNotify.clearDelivered(.message)
        guard let api else { return }
        Task { _ = try? await api.markMessagesRead() }
    }

    /// The unread-chat badge survives app restarts (persisted per couple).
    private var unreadChatKey: String? {
        servers.activeProfile?.coupleId.map { "chat.unread.\($0)" }
    }

    private func persistUnreadChat() {
        guard let key = unreadChatKey else { return }
        UserDefaults.standard.set(unreadChat, forKey: key)
    }

    private func restoreUnreadChat() {
        guard let key = unreadChatKey else {
            unreadChat = 0
            return
        }
        unreadChat = UserDefaults.standard.integer(forKey: key)
    }

    func refreshWidgetPhoto() async {
        guard let api else { return }
        if let photos = try? await api.photos() {
            // The Widget Studio can pin the showcase to "newest" instead of
            // the default "newest favorite, else newest".
            let source = SharedStore.readStudioConfig()
                .config(for: WidgetKindID.photo).photoSource
            if source == "newest" {
                widgetPhoto = photos.first
            } else {
                widgetPhoto = photos.first { !($0.favorites ?? []).isEmpty } ?? photos.first
            }
            await cacheWidgetPhotoBytes()
        }
    }

    /// Downloads the showcase photo's thumb bytes into the shared app-group
    /// cache so the widgets stay pretty when the server is unreachable.
    private func cacheWidgetPhotoBytes() async {
        guard let api, let photo = widgetPhoto else { return }
        guard photo.id != cachedWidgetPhotoId else { return }
        guard let data = try? await api.mediaData(photo.thumbUrl ?? photo.url),
              !data.isEmpty else { return }
        SharedStore.writeCachedPhotoJPEG(data)
        cachedWidgetPhotoId = photo.id
    }

    /// Mirrors the shared canvas into the app group for the canvas widget:
    /// last 400 strokes, each downsampled to ≤ 80 points.
    func refreshWidgetCanvas() async {
        guard let api else { return }
        guard let strokes = try? await api.canvasStrokes() else { return }
        let compact = strokes.suffix(400).map { stroke in
            WidgetCanvasStroke(id: stroke.id,
                               color: stroke.color,
                               width: stroke.width,
                               tool: stroke.tool,
                               points: Self.downsample(stroke.points, maxCount: 80))
        }
        SharedStore.writeCanvasStrokes(compact)
        widgetCanvasStrokeCount = compact.count
    }

    /// Evenly-spaced point subsample that always keeps the first & last point.
    private static func downsample(_ points: [[Double]], maxCount: Int) -> [[Double]] {
        guard points.count > maxCount, maxCount >= 2 else { return points }
        let step = Double(points.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { points[Int((Double($0) * step).rounded())] }
    }

    func refreshCouple() async {
        guard let api else { return }
        // Request generation (Fix-Runde 3, Befund 9): a refresh started
        // BEFORE a server/profile switch answers into the then-active
        // context — capture the identity pair here, compare after the
        // await, and discard the whole response (and its errors) when
        // the context moved on. Just this one seam, no framework.
        let generation: (profileID: UUID?, coupleID: String?) =
            (servers.activeProfileID, couple?.id)
        do {
            let resp = try await api.getCouple()
            guard servers.activeProfileID == generation.profileID,
                  couple?.id == generation.coupleID else { return }
            couple = resp.couple
            coupleDataQuarantined = false
            // v10: keep the remembered pairing code fresh for the rejoin flow.
            if let profile = servers.activeProfile {
                servers.rememberCoupleCode(profileID: profile.id, code: resp.couple.code)
            }
        } catch {
            // A stale error (e.g. the OLD server's 401) must not disturb
            // the profile the user switched TO.
            guard servers.activeProfileID == generation.profileID,
                  couple?.id == generation.coupleID else { return }
            handleAPIError(error)
        }
    }

    func refreshEvents() async {
        guard let api else { return }
        if let list = try? await api.events() {
            events = list.sorted { $0.date < $1.date }
        }
    }

    func refreshDaily() async {
        guard let api else { return }
        dailyEntry = try? await api.daily(dateKey: SharedDates.todayKey())
    }

    /// Schlussrunde 5: a `daily_question_mismatch` names the question the
    /// partner's first answer pinned (id + stored text). Refetch the
    /// authoritative entry; should the refetch fail in the same breath as
    /// the 409 (radio gap), synthesize a minimal today-entry from the
    /// details so the card still flips to the pinned question. The draft
    /// answer stays untouched either way — only the question changes.
    func adoptPinnedDailyQuestion(questionId: Int, questionText: LText?) async {
        let previousStreak = dailyEntry?.streak ?? 0
        await refreshDaily()
        if dailyEntry == nil {
            dailyEntry = DailyEntry(dateKey: SharedDates.todayKey(),
                                    questionId: questionId,
                                    questionText: questionText,
                                    myAnswer: nil, partnerAnswer: nil,
                                    bothAnswered: false, streak: previousStreak,
                                    customQuestion: nil)
        }
        updateWidgetSnapshot()
    }

    func refreshStats() async {
        guard let api else { return }
        stats = try? await api.stats()
    }

    func handleAPIError(_ error: Error) {
        // Explicit revoke verdict from ANY call: terminal — never heal
        // silently, never fall back to the generic 401 logout toast.
        if let apiErr = error as? APIError, apiErr.serverCode == "session_revoked" {
            handleRemoteSessionRevoked()
            return
        }
        if let apiErr = error as? APIError, apiErr.isUnauthorized {
            // v10: try the rejoin proofs (old bearer / recovery key) before
            // giving up — an expired session heals silently in the background.
            Task {
                if await recoverSession() { return }
                if let profile = servers.activeProfile {
                    // recoverSession hit a terminal revoke itself — the
                    // honest revoke state already happened; a second
                    // "unauthorized" toast would only confuse.
                    if Self.isAutoRecoveryBlocked(profileID: profile.id) { return }
                    servers.clearSession(profileID: profile.id)
                }
                couple = nil
                socket.disconnect()
                showToast(L10n.t("error.unauthorized"), style: .error)
            }
            return
        }
        switch error {
        // `.httpDetailed` gets the same humanized sentence as `.http` —
        // detail-carrying codes (e.g. daily_question_mismatch) otherwise
        // fell through to the raw server message (Schlussrunde 5).
        case APIError.http(let status, let code, let message, let retryAfter),
             APIError.httpDetailed(let status, let code, let message, let retryAfter, _):
            let human = APIErrorHumanizer.humanize(status: status, code: code,
                                                   message: message, retryAfter: retryAfter)
            if human.isQuarantine {
                // The server put damaged couple data into protective custody —
                // an app state rather than a passing toast, so the UI can stay
                // honest until the operator resolves it.
                coupleDataQuarantined = true
            }
            showToast(human.text, style: .error)
        case APIError.transport(let underlying):
            showToast(APIErrorHumanizer.humanizeTransport(
                urlErrorCode: (underlying as? URLError)?.errorCode), style: .error)
        default:
            showToast(error.localizedDescription, style: .error)
        }
    }

    // MARK: Actions

    func sendTouch(_ kind: TouchKind) {
        guard let api, let scope = offlineOutboxScope else { return }
        Haptics.shared.play(kind)
        SoundEngine.shared.play(for: kind)
        // Durable moment: a radio hole delays the touch (within the freshness
        // window) instead of silently swallowing it.
        let operation = OfflineOutboxStore.shared.enqueue(
            kind: .touch, payload: ["type": kind.rawValue], scope: scope)
        Task {
            do {
                OfflineOutboxStore.shared.markOperationAttempt(
                    id: operation.clientOperationID, scope: scope)
                try await api.sendTouch(kind,
                                        clientOperationId: operation.clientOperationID)
                OfflineOutboxStore.shared.removeOperation(
                    id: operation.clientOperationID, scope: scope)
                showToast(L10n.t("home.touchSent", ["emoji": kind.emoji]), style: .love)
            } catch {
                resolveMomentSendFailure(error, operationID: operation.clientOperationID,
                                         scope: scope)
            }
        }
    }

    /// Post & Sendungen (P6-B): send a received touch back — same kind,
    /// marked `echo:true`, no cooldown, once per original (server-enforced;
    /// the local `echoedTouchIds` mirror hides the affordance right away).
    func echoTouch(_ original: Touch) {
        guard let api, let scope = offlineOutboxScope else { return }
        guard !echoedTouchIds.contains(original.id) else { return }
        echoedTouchIds.insert(original.id)
        Haptics.shared.play(original.type)
        SoundEngine.shared.play(for: original.type)
        // Durable like a touch — but the freshness window is the ECHO
        // window: a replay after 10 minutes could only collect a 409.
        let operation = OfflineOutboxStore.shared.enqueue(
            kind: .touchEcho, payload: ["touchId": original.id], scope: scope)
        Task {
            do {
                OfflineOutboxStore.shared.markOperationAttempt(
                    id: operation.clientOperationID, scope: scope)
                try await api.echoTouch(id: original.id,
                                        clientOperationId: operation.clientOperationID)
                OfflineOutboxStore.shared.removeOperation(
                    id: operation.clientOperationID, scope: scope)
                showToast(L10n.t("touch.echo.sent"), style: .love)
            } catch {
                resolveMomentSendFailure(error, operationID: operation.clientOperationID,
                                         scope: scope)
            }
        }
    }

    /// Post & Sendungen (P6-B): post a Zeitpost. Returns true when the
    /// Sendung is on its way — sent, or queued for the reconnect replay
    /// (the composer closes on both; only a server rejection keeps it open).
    func schedulePost(touch: TouchKind? = nil, pulse: PulseKind? = nil,
                      note: String? = nil, deliverAt: Date) async -> Bool {
        guard let api, let scope = offlineOutboxScope else { return false }
        var payload = ["deliverAt": API.isoString(deliverAt)]
        if let touch {
            payload["kind"] = PostKind.touch.rawValue
            payload["type"] = touch.rawValue
        } else if let pulse {
            payload["kind"] = PostKind.pulse.rawValue
            payload["pulseKind"] = pulse.rawValue
        } else {
            payload["kind"] = PostKind.note.rawValue
            payload["note"] = note ?? ""
        }
        let operation = OfflineOutboxStore.shared.enqueue(
            kind: .postSchedule, payload: payload, scope: scope)
        OfflineOutboxStore.shared.markOperationAttempt(
            id: operation.clientOperationID, scope: scope)
        do {
            _ = try await api.schedulePost(touch: touch, pulse: pulse, note: note,
                                           deliverAt: deliverAt,
                                           clientOperationId: operation.clientOperationID)
            OfflineOutboxStore.shared.removeOperation(
                id: operation.clientOperationID, scope: scope)
            // R1-D: no toast, no generic success here — the composer plays
            // the envelope ceremony (postmark beat + `.sealed` cue) on
            // `accepted`. Only the offline-queued path below still speaks.
            return true
        } catch {
            let verdict = OutboxRetryPolicy.verdict(
                failure: OutboxFailureKind(classifying: error), attemptCount: 1)
            if verdict == .giveUp {
                // Permanent (bad_deliver_at, post_limit, …): drop the queued
                // copy and let the humanizer explain — the composer stays
                // open so the moment can be re-picked.
                OfflineOutboxStore.shared.removeOperation(
                    id: operation.clientOperationID, scope: scope)
                handleAPIError(error)
                return false
            }
            if (error as? APIError)?.isUnauthorized == true {
                handleAPIError(error)   // triggers the silent session healing
            }
            showToast(L10n.t("post.zeitpost.queuedToast"), style: .info)
            return true
        }
    }

    /// Shared failure path for queued touch/pulse sends: transient errors
    /// keep the operation queued for the reconnect replay (with a gentle
    /// "will arrive later" note instead of a scary error), permanent
    /// rejections drop it and surface the real error.
    private func resolveMomentSendFailure(_ error: Error, operationID: String,
                                          scope: OutboxScope) {
        let verdict = OutboxRetryPolicy.verdict(
            failure: OutboxFailureKind(classifying: error), attemptCount: 1)
        if verdict == .giveUp {
            OfflineOutboxStore.shared.removeOperation(id: operationID, scope: scope)
            handleAPIError(error)
        } else if (error as? APIError)?.isUnauthorized == true {
            handleAPIError(error)   // triggers the silent session healing
        } else {
            showToast(L10n.t("outbox.momentQueued"), style: .info)
        }
    }

    func setMood(_ mood: String?, note: String?) {
        guard let api else { return }
        Task {
            do {
                let member = try await api.updateMe(mood: .some(mood), moodNote: .some(note))
                applyMemberUpdate(member)
                Haptics.shared.success()
                updateWidgetSnapshot()
            } catch {
                handleAPIError(error)
            }
        }
    }

    func leaveDevice() {
        guard let profile = servers.activeProfile else { return }
        if let api {
            Task { try? await api.unregisterPushDevice() }
        }
        socket.disconnect()
        CoreColdCacheStore.shared.remove(profileID: profile.id)
        servers.clearSession(profileID: profile.id)
        couple = nil
        events = []
        dailyEntry = nil
        stats = nil
        widgetGoal = nil
        widgetMemory = nil
        unreadChat = 0
        missedInbox = nil
        missedVisited = []
        dismissedInbox = nil
        gamesAwaitingMe = []
        freshRecoveryKey = nil
        heldRecoveryKey = nil
        resetPlatformState()   // Level/badges/platform
        CouplePulseController.stop()
        CountdownActivityController.stopAll()
        updateWidgetSnapshot()
    }

    func dissolveCouple() async {
        guard let api else { return }
        do {
            try await api.dissolveCouple()
            leaveDevice()
        } catch {
            handleAPIError(error)
        }
    }

    // MARK: Socket events

    private func handle(_ event: ServerEvent) {
        switch event.type {
        case .welcome:
            if let payload = event.decode(WelcomePayload.self) {
                setPartnerOnline(payload.partnerOnline, lastSeen: nil)
                pushLiveActivityUpdates()
                // Socket (re)connected — check what happened while offline.
                Task { await refreshInbox() }
                // Events changed while offline never re-announce themselves
                // (their add/update/delete fanouts are gone for good) —
                // refetch them centrally so countdowns/widgets reconcile;
                // mounted stores (lists, canvas) catch up on this same
                // welcome via the .serverEvent notification.
                Task {
                    await refreshEvents()
                    CountdownActivityController.stopIfEventMissing(events: events)
                    updateWidgetSnapshot()
                }
                // FEEL what you missed — replay queued pulses.
                Task { await replayMissedPulses() }
                // Flush moments queued during the gap (single-flight): a
                // WLAN blip with the app open must not park touches/pulses
                // until the foreground refresh — or their 15-min expiry.
                Task { await replayOfflineOperations() }
            }
        case .presence:
            if let p = event.decode(PresencePayload.self), p.memberId != memberId {
                let wasOnline = partner?.online ?? false
                setPartnerOnline(p.online, lastSeen: p.lastSeenAt)
                if p.online && !wasOnline { notifyPartnerOnline() }
                pushLiveActivityUpdates()
            }
        case .touch:
            if let payload = event.decode(TouchResponse.self) {
                receiveTouch(payload.touch)
                pushLiveActivityUpdates()
            }
        case .haptic:
            if let payload = event.decode(HapticSendResponse.self) {
                receiveHaptic(payload.haptic)
            }
        case .message:
            if let payload = event.decode(MessageResponse.self) {
                if payload.message.senderId != memberId {
                    if let effect = payload.message.effect {
                        receiveMessageEffect(effect)
                    }
                    if activeTab != .chat {
                        unreadChat += 1
                        notifyMessage(payload.message)
                    } else {
                        // Chat is on screen — the message is read right away.
                        markChatRead()
                    }
                    // Received cue: bursts ring once, an open chat only knocks.
                    AppCue.received.play(chatVisible: activeTab == .chat)
                }
            }
        case .messageRead:
            // Partner (or my other device) marked the chat as read — feeds
            // the read-receipt checkmarks on own bubbles.
            if let payload = event.decode(MessageReadPayload.self) {
                applyLastReadAt(memberId: payload.memberId, at: payload.at)
            }
        case .memberUpdated:
            if let payload = event.decode(MemberResponse.self) {
                applyMemberUpdate(payload.member)
                pushLiveActivityUpdates()
            }
        case .coupleUpdated:
            if let payload = event.decode(CoupleOnlyResponse.self) {
                couple = payload.couple
                updateWidgetSnapshot()
            }
        case .partnerJoined:
            if event.decode(MemberResponse.self) != nil {
                // Welle 7 [30]: the creator's side of the pairing moment —
                // the ceremony replaces the old toast+tada+hearts stack
                // (one-channel rule: the ceremony IS the announcement).
                Task {
                    await refreshCouple()
                    beginPairingCeremony(kind: .paired)
                }
            }
        case .coupleDissolved:
            leaveDevice()
            showToast(L10n.t("misc.dissolvedTitle"), style: .info)
        case .dailyAnswer:
            if let entry = event.decode(DailyEntry.self), entry.dateKey == SharedDates.todayKey() {
                let wasBothAnswered = dailyEntry?.bothAnswered ?? false
                dailyEntry = entry
                if entry.bothAnswered {
                    SoundEngine.shared.play(.sparkle)
                    if !wasBothAnswered {
                        CoupleNotify.alert(.dailyReveal,
                                           title: L10n.t("home.bothAnswered"),
                                           body: L10n.t("notif.daily.body"),
                                           link: "sooodreamy://daily")
                    }
                }
                pushLiveActivityUpdates()
            }
        case .eventAdded, .eventUpdated, .eventDeleted:
            Task {
                await refreshEvents()
                if event.type == .eventDeleted {
                    // A running countdown whose event vanished should end too.
                    CountdownActivityController.stopIfEventMissing(events: events)
                }
                updateWidgetSnapshot()
            }
        case .photoAdded, .photoUpdated, .photoDeleted:
            if event.type == .photoAdded,
               let photo = event.decode(PhotoResponse.self)?.photo,
               photo.uploaderId != memberId {
                CoupleNotify.alert(.photo,
                                   title: L10n.t("notif.photo.title", ["name": partnerName]),
                                   body: L10n.t("notif.photo.body", ["name": partnerName]),
                                   link: "sooodreamy://tab/memories")
            }
            Task {
                await refreshWidgetPhoto()
                updateWidgetSnapshot()
            }
        case .videoAdded:
            // Client half of B-26: partner videos alert like partner photos
            // (same media toggle in the notification settings).
            if let video = event.decode(VideoResponse.self)?.video,
               video.uploaderId != memberId {
                CoupleNotify.alert(.photo,
                                   title: L10n.t("notif.video.title", ["name": partnerName]),
                                   body: L10n.t("notif.video.body", ["name": partnerName]),
                                   link: "sooodreamy://tab/memories")
            }
        case .canvasStroke, .canvasStrokeDeleted, .canvasClear:
            // CanvasView keeps its own live copy; this mirrors the strokes
            // into the app group so the canvas widget stays current.
            Task {
                await refreshWidgetCanvas()
                updateWidgetSnapshot()
            }
        case .couponAdded:
            if let coupon = event.decode(CouponResponse.self)?.coupon, coupon.forMember == memberId {
                showToast(L10n.t("coupon.receivedToast"), style: .love)
                SoundEngine.shared.play(.sparkle)
                CoupleNotify.alert(.coupon,
                                   title: L10n.t("notif.coupon.title", ["name": partnerName]),
                                   body: L10n.t("notif.coupon.body",
                                                ["name": partnerName, "title": coupon.title]),
                                   link: "sooodreamy://tab/memories")
            }
        case .couponRedeemed:
            if let coupon = event.decode(CouponResponse.self)?.coupon, coupon.createdBy == memberId {
                showToast(L10n.t("coupon.redeemedToast", ["title": coupon.title]), style: .love)
                SoundEngine.shared.play(.tada)
            }
        case .checkin:
            if let payload = event.decode(CheckinEventPayload.self), payload.memberId != memberId {
                let key = payload.kind == "morning" ? "checkin.toast.morning" : "checkin.toast.night"
                showToast(L10n.t(key, ["name": partnerName]), style: .love)
                SoundEngine.shared.play(.pop)
            }
        case .hugQueued:
            if let hug = event.decode(HugResponse.self)?.hug, hug.to == memberId {
                showToast(L10n.t("hug.receivedToast", ["name": partnerName]), style: .love)
                SoundEngine.shared.play(.sparkle)
                CoupleNotify.alert(.touch,
                                   title: L10n.t("notif.hug.title", ["name": partnerName]),
                                   body: L10n.t("notif.hug.body", ["name": partnerName]),
                                   link: "sooodreamy://tab/home")
            }
        case .hugOpened:
            if let hug = event.decode(HugResponse.self)?.hug, hug.from == memberId {
                showToast(L10n.t("hug.openedToast", ["name": partnerName]), style: .love)
                SoundEngine.shared.play(.success)
                Haptics.shared.success()
            }
        case .nowPlayingChanged:
            if let payload = event.decode(NowPlayingEventPayload.self) {
                applyNowPlaying(memberId: payload.memberId, nowPlaying: payload.nowPlaying)
                if payload.memberId != memberId, let np = payload.nowPlaying {
                    showToast(L10n.t("nowplaying.toast", ["name": partnerName, "title": np.title]),
                              style: .info)
                }
            }
        case .potdSubmitted:
            if let payload = event.decode(PotdEventPayload.self), payload.memberId != memberId {
                showToast(L10n.t("potd.partnerToast", ["name": partnerName]), style: .love)
                SoundEngine.shared.play(.pop)
            }
        case .typing:
            if let p = event.decode(TypingPayload.self), p.memberId != memberId {
                partnerTyping = p.isTyping
                typingTask?.cancel()
                if p.isTyping {
                    typingTask = Task { [weak self] in
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        if !Task.isCancelled { self?.partnerTyping = false }
                    }
                }
            }
        // „Nähe trotz Distanz"
        case .presenceMode:
            if let payload = event.decode(PresenceModePayload.self) {
                applyPresence(payload.presence, memberId: payload.memberId)
                // Gentle hint, no sound: the partner just told us they're
                // heads-down/asleep — the point is NOT to demand attention.
                if payload.memberId != memberId, let kind = payload.presence?.kind {
                    showToast(L10n.t(kind.partnerHintKey, ["name": partnerName]), style: .info)
                }
            }
        case .pulse:
            if let payload = event.decode(PulseResponse.self) {
                receivePulse(payload.pulse)
            }
        case .pulseFelt:
            if let payload = event.decode(PulseFeltPayload.self), payload.memberId != memberId {
                // My pulse reached a heart — a quiet, warm receipt.
                showToast(L10n.t("pulse.feltToast", ["name": partnerName]), style: .love)
                Haptics.shared.tap()
            }
        // Post & Sendungen (P6-B)
        case .postNote:
            if let note = event.decode(PostNotePayload.self)?.note {
                receivePostNote(note)
            }
        case .postScheduled, .postCanceled:
            // My OTHER device posted/took back a Zeitpost — a pure sync
            // fact (the server only tells the sender's devices; the partner
            // must stay surprised). The Zeitpost sheet reconciles via the
            // .serverEvent notification itself; nothing to announce here.
            break
        case .deviceLinked:
            // A NEW device of MY member attached via link code (the server
            // notifies only my own devices, never the partner). The device
            // manager keeps its list fresh by observing .serverEvent itself.
            if let payload = event.decode(DeviceLinkedPayload.self), payload.memberId == memberId {
                let name = payload.deviceName ?? L10n.t("devices.fallbackName")
                showToast(L10n.t("devices.linkedToast", ["name": name]), style: .success)
                SoundEngine.shared.play(.pop)
                Haptics.shared.success()
            }
        case .need, .needAcked, .capsuleSealed, .capsuleOpened, .energy,
             .goalAdded, .goalUpdated, .goalDeleted, .daymemo:
            // Rituals — global toasts/notifications/confetti
            // live in RitualsAppState.swift; feature views keep their own state.
            handleRitualEvent(event)
        default:
            // Level/badges/platform events — remaining types
            // are consumed by feature views observing .serverEvent themselves.
            handlePlatformEvent(event)
        }
    }

    private func applyNowPlaying(memberId: String, nowPlaying: NowPlaying?) {
        guard var couple else { return }
        if let idx = couple.members.firstIndex(where: { $0.id == memberId }) {
            couple.members[idx].nowPlaying = nowPlaying
            self.couple = couple
        }
    }

    private func setPartnerOnline(_ online: Bool, lastSeen: Date?) {
        guard var couple, let memberId else { return }
        for i in couple.members.indices where couple.members[i].id != memberId {
            couple.members[i].online = online
            if let lastSeen { couple.members[i].lastSeenAt = lastSeen }
        }
        self.couple = couple
    }

    private func applyMemberUpdate(_ member: Member) {
        guard var couple else { return }
        if let idx = couple.members.firstIndex(where: { $0.id == member.id }) {
            let wasOnline = couple.members[idx].online
            couple.members[idx] = member
            couple.members[idx].online = member.online ?? wasOnline
        }
        self.couple = couple
    }

    /// Advance a member's `lastReadAt` (never backwards — events may race).
    private func applyLastReadAt(memberId id: String, at: Date) {
        guard var couple else { return }
        guard let idx = couple.members.firstIndex(where: { $0.id == id }) else { return }
        if let current = couple.members[idx].lastReadAt, current >= at { return }
        couple.members[idx].lastReadAt = at
        self.couple = couple
    }

    private func receiveTouch(_ touch: Touch) {
        // P6-B: any arriving touch that references an original closes that
        // original's echo window everywhere — no matter which member or
        // device sent it (once per original, mirrored from the fanout).
        if let echoOf = touch.echoOf {
            echoedTouchIds.insert(echoOf)
        }
        // Multi-device: my own touch, echoed from ANOTHER of my devices
        // (origin.memberId == me), is a sync fact — a quiet "went through"
        // tick instead of the partner moment (no overlay, no heart pulse).
        guard touch.senderId != memberId else {
            Haptics.shared.tap()
            return
        }
        incomingTouch = touch
        Haptics.shared.play(touch.type)
        SoundEngine.shared.play(for: touch.type)
        lastTouchType = touch.type.rawValue
        lastTouchAt = touch.createdAt
        CoupleNotify.alert(.touch,
                           title: "\(touch.type.emoji) \(partnerName)",
                           body: L10n.t("touch.received.\(touch.type.rawValue)", ["name": partnerName]),
                           sound: NotificationPrefs.soundOverride(for: .touch)
                               ?? .mapped(for: touch.type),
                           link: "sooodreamy://tab/home")
        touchTask?.cancel()
        touchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_200_000_000)
            if !Task.isCancelled { self?.incomingTouch = nil }
        }
    }

    /// Custom vibration from the partner: full-screen moment + the pattern
    /// itself. Auto-dismisses after the pattern finished playing.
    private func receiveHaptic(_ haptic: HapticSend) {
        // Multi-device self-echo: composed on my OTHER device — quiet tick,
        // never the full partner moment with pattern playback.
        guard haptic.senderId != memberId else {
            Haptics.shared.tap()
            return
        }
        incomingHaptic = haptic
        Haptics.shared.play(events: haptic.events)
        SoundEngine.shared.play(.vibe)
        CoupleNotify.alert(.touch,
                           title: "\(haptic.emoji ?? "💜") \(partnerName)",
                           body: L10n.t("haptic.received.body", ["name": partnerName]),
                           link: "sooodreamy://tab/home")
        let linger = HapticTimeline.duration(of: haptic.events) + 3.5
        hapticTask?.cancel()
        hapticTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(4.5, linger) * 1_000_000_000))
            if !Task.isCancelled { self?.incomingHaptic = nil }
        }
    }

    /// P6-B → R1-D: a scheduled note just arrived. The note is CONTENT and
    /// gets a MOMENT: the sealed-envelope overlay (PostNoteOverlay) shows
    /// it instead of a toast — the seal-break beat is the hand's channel
    /// there, so arrival itself only rings (one-channel rule). The
    /// lock-screen push (server-side) deliberately stays generic.
    private func receivePostNote(_ note: PostNote) {
        // Multi-device self-echo: my own delivered Zeitpost — quiet tick,
        // the surprise belongs to the partner.
        guard note.senderId != memberId else {
            Haptics.shared.tap()
            return
        }
        incomingPostNote = note
        SoundEngine.shared.play(.sparkle)
        CoupleNotify.alert(.touch,
                           title: "💌 \(partnerName)",
                           body: L10n.t("post.note.notifBody", ["name": partnerName]),
                           link: "sooodreamy://tab/home")
    }

    // MARK: Couple notifications

    private func notifyMessage(_ message: Message) {
        let body: String
        switch message.type {
        case .text:
            body = Self.preview(of: message.text ?? "")
        case .letter:
            body = L10n.t("notif.message.letter")
        case .voice:
            body = L10n.t("notif.message.voice")
        case .photo:
            body = L10n.t("notif.message.photo")
        case .sticker:
            body = L10n.t("notif.message.sticker")
        }
        guard !body.isEmpty else { return }
        CoupleNotify.alert(.message,
                           title: L10n.t("notif.message.title", ["name": partnerName]),
                           body: body,
                           link: "sooodreamy://tab/chat")
    }

    private func notifyPartnerOnline() {
        if let last = lastOnlineAlertAt, Date().timeIntervalSince(last) < 600 { return }
        lastOnlineAlertAt = Date()
        CoupleNotify.alert(.partnerOnline,
                           title: L10n.t("notif.online.title", ["name": partnerName]),
                           body: L10n.t("notif.online.body"),
                           link: "sooodreamy://tab/home")
    }

    // MARK: Presence & pulses („Nähe trotz Distanz")

    /// My own fresh presence mode (client-side expiry mirrors the server's).
    var myPresence: MemberPresence? {
        guard let presence = me?.presence,
              PresenceLogic.isActive(until: presence.until) else { return nil }
        return presence
    }

    /// Partner's fresh presence mode — drives the glow + gentle hint.
    var partnerPresence: MemberPresence? {
        guard let presence = partner?.presence,
              PresenceLogic.isActive(until: presence.until) else { return nil }
        return presence
    }

    func setPresence(_ mode: PresenceModeKind, note: String?, minutes: Int?) {
        guard let api else { return }
        Task {
            do {
                let presence = try await api.setPresence(mode: mode, note: note, minutes: minutes)
                if let memberId { applyPresence(presence, memberId: memberId) }
                Haptics.shared.tap()
            } catch {
                handleAPIError(error)
            }
        }
    }

    func clearPresence() {
        guard let api else { return }
        Task {
            do {
                try await api.clearPresence()
                if let memberId { applyPresence(nil, memberId: memberId) }
                Haptics.shared.tap()
            } catch {
                handleAPIError(error)
            }
        }
    }

    /// Sends a thinking-of-you pulse. The sender feels the same pattern the
    /// partner will feel — you know exactly what arrives on the other side.
    func sendPulse(_ kind: PulseKind) {
        guard let api, let scope = offlineOutboxScope else { return }
        guard PulseLogic.cooldownRemaining(lastSentAt: lastPulseSentAt) <= 0 else { return }
        lastPulseSentAt = Date()
        Haptics.shared.play(events: kind.timeline)
        let operation = OfflineOutboxStore.shared.enqueue(
            kind: .pulse, payload: ["kind": kind.rawValue], scope: scope)
        Task {
            do {
                OfflineOutboxStore.shared.markOperationAttempt(
                    id: operation.clientOperationID, scope: scope)
                try await api.sendPulse(kind,
                                        clientOperationId: operation.clientOperationID)
                OfflineOutboxStore.shared.removeOperation(
                    id: operation.clientOperationID, scope: scope)
                showToast(L10n.t("pulse.sentToast", ["emoji": kind.emoji]), style: .love)
            } catch {
                resolveMomentSendFailure(error, operationID: operation.clientOperationID,
                                         scope: scope)
            }
        }
    }

    private func applyPresence(_ presence: MemberPresence?, memberId id: String) {
        guard var couple else { return }
        guard let idx = couple.members.firstIndex(where: { $0.id == id }) else { return }
        couple.members[idx].presence = presence
        self.couple = couple
        pushLiveActivityUpdates()
    }

    /// Mirrors MY sleep window into the notification layer, so incoming
    /// alerts really go quiet (Linse 11) and the morning summary knows the
    /// partner's name. Runs on every couple change — cheap statics.
    private func syncNotificationDamping() {
        if let presence = myPresence, presence.kind == .sleep {
            CoupleNotify.sleepUntil = presence.until ?? .distantFuture
        } else {
            if CoupleNotify.sleepUntil != nil {
                // Sleep just ended while the app is live — the human is
                // provably awake in-app, no morning summary needed.
                SleepSummaryTracker.reset(cancelPending: true)
            }
            CoupleNotify.sleepUntil = nil
        }
        CoupleNotify.summaryPartnerName = partnerName
    }

    /// Incoming pulse (live via WS or replayed after launch): play the haptic
    /// signature, show the full-screen moment and confirm "felt" to the server
    /// so the sender gets their receipt.
    private func receivePulse(_ pulse: Pulse, moreCount: Int = 0) {
        guard pulse.senderId != memberId else { return }
        incomingPulse = pulse
        incomingPulseCount = 1 + moreCount
        let kind = pulse.pulseKind
        if let kind {
            Haptics.shared.play(events: kind.timeline)
            SoundEngine.shared.play(.vibe)
        }
        // W7 (37#23): the live activity learns about pulses too — a pulse IS
        // the lock screen's "last touch", without waiting for the next
        // snapshot refresh. Replays of old pulses never rewind a newer touch.
        if ActivityUpdateHygiene.isNewer(pulse.createdAt, than: lastTouchAt) {
            lastTouchType = pulse.kind
            lastTouchAt = pulse.createdAt
            pushLiveActivityUpdates()
        }
        CoupleNotify.alert(.touch,
                           title: "\(kind?.emoji ?? "💜") \(partnerName)",
                           body: L10n.t(kind?.receivedKey ?? "pulse.received.thinking",
                                        ["name": partnerName]),
                           link: "sooodreamy://tab/home")
        Task { _ = try? await api?.markPulsesSeen() }
        let linger = max(4.5, PulseLogic.timelineDuration(kind?.timeline ?? []) + 3.5)
        pulseTask?.cancel()
        pulseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(linger * 1_000_000_000))
            if !Task.isCancelled {
                self?.incomingPulse = nil
                self?.incomingPulseCount = 0
            }
        }
    }

    /// Launch/reconnect replay: pulses sent while the app was closed are
    /// queued server-side — play the newest one so the moment is FELT, not
    /// just read (the overlay shows "+n more" for the rest).
    private func replayMissedPulses() async {
        guard let api else { return }
        guard let pulses = try? await api.unfeltPulses(), !pulses.isEmpty else { return }
        receivePulse(pulses[pulses.count - 1], moreCount: pulses.count - 1)
    }

    private static func preview(of text: String, limit: Int = 120) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count <= limit ? trimmed : String(trimmed.prefix(limit)) + "…"
    }

    private func receiveMessageEffect(_ effect: MessageEffect) {
        incomingMessageEffect = effect
        messageEffectTask?.cancel()
        messageEffectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if !Task.isCancelled { self?.incomingMessageEffect = nil }
        }
    }

    private func celebrateNow() {
        celebrate = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            self?.celebrate = false
        }
    }

    // MARK: Toast

    func showToast(_ text: String, style: Toast.Style = .info) {
        withAnimation(.spring(response: 0.35)) {
            toast = Toast(text: text, style: style)
        }
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                self?.toast = nil
            }
        }
    }

    // MARK: Deep links (sooodreamy://…)

    func handleURL(_ url: URL) {
        guard url.scheme == "sooodreamy" else { return }
        let host = url.host() ?? ""
        let path = url.pathComponents.dropFirst().first ?? ""
        switch host {
        case "tab":
            if let tab = AppTab(rawValue: path) { activeTab = tab }
        case "daily", "streak":
            // Daily question & answer streak both live on the dashboard.
            activeTab = .home
        case "reveal":
            // W7-Rest: the widget's wax seal / island gold pill — land on
            // home AND open the ceremony (dashboard consumes the flag).
            activeTab = .home
            pendingRevealRequest = true
        case "need":
            // iOS-18 control: need button lives on the dashboard.
            activeTab = .home
        case "photos":
            // W6-Rest: `sooodreamy://photos/<photoId>` opens the gallery
            // lightbox ON that photo (chat's "view in album" bridge);
            // without a path the link keeps landing on the Us tab.
            if !path.isEmpty {
                openGalleryPhoto(path)
            } else {
                activeTab = .memories
            }
        case "coupons", "events", "canvas":
            // Feature-specific widget/notification links — these features live
            // in the "Us" tab. Kept as distinct hosts so future sub-navigation
            // can route deeper without touching the widgets again.
            activeTab = .memories
        case "action":
            if path == "sendlove" {
                let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let raw = comps?.queryItems?.first(where: { $0.name == "type" })?.value ?? "heartbeat"
                sendTouch(TouchKind(rawValue: raw) ?? .heartbeat)
            }
        case "rejoin":
            // "one scan and you're back": QR codes from the admin web
            // panel / the partner's phone carry this link (docs/REJOIN-QR.md).
            if let link = RejoinLink.parse(url.absoluteString) {
                applyRejoinLink(link)
            } else {
                showToast(L10n.t("rejoin.link.invalid"), style: .error)
            }
        case "link":
            // Multi-device hand-off: the QR/deep link a signed-in device
            // shows so THIS device attaches to the same member (one scan).
            if let link = DeviceLinkURL.parse(url.absoluteString) {
                applyDeviceLink(link)
            } else {
                showToast(L10n.t("devices.link.invalid"), style: .error)
            }
        default:
            break
        }
    }

    /// W6-Rest: chat photo → "view in album". Switches to the Us tab and
    /// leaves the target for MemoriesView (push gallery) and GalleryView
    /// (open the lightbox once its photo list is loaded).
    func openGalleryPhoto(_ photoId: String) {
        pendingGalleryPhotoId = photoId
        activeTab = .memories
    }

    // MARK: Rejoin links (QR-scan login)

    /// Applies a rejoin link: activates (or adds) the server it names, then
    /// re-attaches automatically when the link carries a complete proof.
    /// Incomplete links prefill the reconnect screen instead.
    func applyRejoinLink(_ link: RejoinLink) {
        // A rejoin link is a NEW explicit intent — it replaces any parked
        // invite code from an earlier, abandoned setup flow.
        PendingInvite.clear()
        var targetProfileID = servers.activeProfileID
        if let server = link.server {
            if let existing = servers.profiles.first(where: { $0.urlString == server }) {
                servers.setActive(id: existing.id)
                targetProfileID = existing.id
            } else if let profile = servers.add(name: server, urlString: server) {
                servers.setActive(id: profile.id)
                targetProfileID = profile.id
            }
        }
        guard let profileID = targetProfileID,
              let profile = servers.profiles.first(where: { $0.id == profileID }),
              let baseURL = profile.baseURL else {
            // No server known at all — keep the link for manual entry.
            pendingRejoin = link
            showToast(L10n.t("rejoin.link.prefilled"), style: .info)
            return
        }
        guard let proof = link.proof else {
            pendingRejoin = link
            showToast(L10n.t("rejoin.link.prefilled"), style: .info)
            return
        }
        Task { await performRejoin(proof: proof, profileID: profileID, baseURL: baseURL, link: link) }
    }

    private func performRejoin(proof: RejoinLink.Proof, profileID: UUID,
                               baseURL: URL, link: RejoinLink) async {
        showToast(L10n.t("rejoin.link.connecting"), style: .info)
        let api = API(baseURL: baseURL, token: nil)
        do {
            let auth: AuthResponse
            switch proof {
            case .recoveryKey(let code, let recoveryKey):
                // Scanned keys arrive exact — no client-side normalization.
                auth = try await api.rejoin(code: code, recoveryKey: recoveryKey)
            case .token(let token):
                auth = try await api.rejoin(oldToken: token)
            case .replaceCode(let code, let replaceCode):
                // Keep the slot's name/avatar/color — same person, new device.
                auth = try await api.rejoin(code: code, replaceCode: replaceCode,
                                            name: nil, avatar: nil, color: nil)
            }
            // Rejoin is a repair, not an arrival — no color-merge ceremony
            // (arrival: nil), the familiar tada+toast carry the relief.
            SoundEngine.shared.play(.tada)
            Haptics.shared.success()
            completeAuth(profileID: profileID, auth: auth, arrival: nil)
            showToast(L10n.t("rejoin.link.success"), style: .success)
        } catch {
            // Auto path failed → hand everything to the manual screen so
            // nothing has to be typed twice.
            pendingRejoin = link
            showRejoinError(error)
        }
    }

    private func showRejoinError(_ error: Error) {
        Haptics.shared.warning()
        guard case APIError.http(let status, let code, _, _) = error else {
            showToast(error.localizedDescription, style: .error)
            return
        }
        switch (status, code) {
        case (404, _), (_, "unknown_code"):
            showToast(L10n.t("pairing.unknownCode"), style: .error)
        case (403, "bad_recovery_key"):
            showToast(L10n.t("pairing.rejoin.badKey"), style: .error)
        case (403, "bad_replace_code"):
            showToast(L10n.t("pairing.rejoin.badReplace"), style: .error)
        case (403, "session_revoked"), (403, "unknown_session"):
            showToast(L10n.t("pairing.rejoin.revoked"), style: .error)
        default:
            showToast(error.localizedDescription, style: .error)
        }
    }

    // MARK: Device links (attach THIS device to my existing member)

    /// Applies a `sooodreamy://link` deep link / scanned QR: activates (or
    /// adds) the server it names, then redeems the code for a fresh session
    /// of the SAME member. An already-paired profile is left untouched —
    /// redeeming there would silently re-bind this device to whichever
    /// member minted the code.
    func applyDeviceLink(_ link: DeviceLinkURL) {
        var targetProfileID = servers.activeProfileID
        if let server = link.server {
            if let existing = servers.profiles.first(where: { $0.urlString == server }) {
                servers.setActive(id: existing.id)
                targetProfileID = existing.id
            } else if let profile = servers.add(name: server, urlString: server) {
                servers.setActive(id: profile.id)
                targetProfileID = profile.id
            }
        }
        guard let profileID = targetProfileID,
              let profile = servers.profiles.first(where: { $0.id == profileID }),
              let baseURL = profile.baseURL else {
            // No server known at all — PairingView prefills from this later.
            pendingDeviceLink = link
            showToast(L10n.t("devices.link.prefilled"), style: .info)
            return
        }
        guard !profile.isPaired else {
            showToast(L10n.t("devices.link.alreadyPaired"), style: .info)
            return
        }
        Task { await performDeviceLink(code: link.code, profileID: profileID,
                                       baseURL: baseURL, link: link) }
    }

    /// Redeems a device link code against a known server profile — shared by
    /// the deep-link path and PairingView's manual "I have a device" path.
    func performDeviceLink(code: String, profileID: UUID,
                           baseURL: URL, link: DeviceLinkURL? = nil) async {
        showToast(L10n.t("devices.link.connecting"), style: .info)
        let api = API(baseURL: baseURL, token: nil)
        do {
            let auth = try await api.linkDevice(code: code)
            // Welle 7 [30]: the ceremony (inside completeAuth) carries the
            // arrival — no tada/success stacked on top of the one cue. The
            // toast only speaks when the couple is still solo (no ceremony).
            completeAuth(profileID: profileID, auth: auth, arrival: .linked)
            if pairingCeremony == nil {
                showToast(L10n.t("devices.link.success"), style: .success)
            }
        } catch {
            if let link { pendingDeviceLink = link }
            showDeviceLinkError(error)
        }
    }

    /// Honest error surface for a failed link-code redemption — every code
    /// from the docs/API.md catalog gets its own sentence.
    func showDeviceLinkError(_ error: Error) {
        Haptics.shared.warning()
        guard case APIError.http(let status, let code, _, _) = error else {
            showToast(error.localizedDescription, style: .error)
            return
        }
        if let key = MultiDeviceRules.linkErrorKey(status: status, code: code) {
            showToast(L10n.t(key), style: .error)
        } else {
            handleAPIError(error)
        }
    }

    // MARK: Live Activities

    /// Pushes fresh couple context into widgets + all running live activities
    /// (countdown & couple pulse) — called on relevant socket events. Updates
    /// happen locally while the app is open; no APNs involved.
    private func pushLiveActivityUpdates() {
        updateWidgetSnapshot()
        CountdownActivityController.updateFromSnapshot()
        CouplePulseController.updateFrom(self)
    }

    // MARK: Widgets

    func updateWidgetSnapshot() {
        // Welle 7 [29]: the staged demo couple must never leak into the
        // shared widget snapshot — widgets keep whatever real state exists.
        guard !demoActive else { return }
        // Pinned id wins (Schlussrunde 4) — same rule as the in-app card,
        // date-gated (Schlussrunde 5): a stale entry from before midnight
        // must not pin yesterday's question onto today's widget.
        let pinnedId = DailyPinRules.applicablePin(pinnedId: dailyEntry?.questionId,
                                                   pinDateKey: dailyEntry?.dateKey,
                                                   localDateKey: SharedDates.todayKey())
        let daily = couple.map {
            ContentPack.dailyQuestion(dateKey: SharedDates.todayKey(),
                                      coupleId: $0.id,
                                      pinnedId: pinnedId,
                                      pinnedText: pinnedId == nil ? nil : dailyEntry?.questionText)
        }
        var snapshot = WidgetSnapshot()
        snapshot.partnerName = partner?.name
        snapshot.partnerAvatar = partner?.avatar
        snapshot.partnerColorHex = partner?.color
        snapshot.partnerMood = partner?.mood
        snapshot.partnerMoodNote = partner?.moodNote
        snapshot.partnerMoodUpdatedAt = partner?.moodUpdatedAt
        snapshot.partnerEnergyLevel = partner?.energy?.level
        snapshot.partnerEnergyNote = partner?.energy?.note
        snapshot.partnerEnergySetAt = partner?.energy?.setAt
        snapshot.partnerPresenceMode = partnerPresence?.mode
        snapshot.partnerPresenceUntil = partnerPresence?.until
        snapshot.partnerOnline = partner?.online
        snapshot.lastTouchType = lastTouchType
        snapshot.lastTouchAt = lastTouchAt
        snapshot.myName = me?.name
        // W7: my own presence mirrored for the sleep-toggle control's state.
        snapshot.myPresenceMode = myPresence?.mode
        snapshot.myPresenceUntil = myPresence?.until
        // W7 (43#1): Siri only learns the partner's name for "Schick Lea ein
        // Herz" when the shortcut parameters are re-donated after changes.
        PartnerShortcutSync.syncIfNeeded(partnerName: partner?.name)
        snapshot.couplePalettePrimary = couple?.palette?.primary
        snapshot.couplePaletteSecondary = couple?.palette?.secondary
        snapshot.couplePaletteAccent = couple?.palette?.accent
        snapshot.couplePaletteOnAccent = couple?.palette?.onAccent
        snapshot.anniversary = couple?.anniversary
        snapshot.daysTogether = daysTogether
        if let next = nextEvent {
            snapshot.nextEventTitle = next.event.title
            snapshot.nextEventEmoji = next.event.emoji
            snapshot.nextEventDate = next.event.date
        }
        snapshot.dailyQuestionDE = daily?.text.de
        snapshot.dailyQuestionEN = daily?.text.en
        snapshot.dailyAnsweredByMe = dailyEntry?.myAnswer != nil
        snapshot.dailyBothAnswered = dailyEntry?.bothAnswered ?? false
        snapshot.streak = dailyEntry?.streak ?? 0
        // Reveal seal for widgets/Live Activity: both answered today, but
        // the ceremony was not yet broken open on this device.
        snapshot.coupleId = couple?.id
        if let entry = dailyEntry, entry.dateKey == SharedDates.todayKey() {
            snapshot.dailyRevealDateKey = entry.dateKey
            snapshot.dailyRevealPending = RevealedDailyStore.sealPending(
                coupleId: couple?.id, dateKey: entry.dateKey,
                bothAnswered: entry.bothAnswered)
        }
        snapshot.canvasStrokeCount = widgetCanvasStrokeCount
        snapshot.goalTitle = widgetGoal?.title
        snapshot.goalEmoji = widgetGoal?.emoji
        snapshot.goalPercent = widgetGoal?.percent
        // All upcoming moments (soonest first) — the countdown widget can be
        // pinned to any of them via its edit-widget configuration.
        snapshot.allEvents = events
            .compactMap { ev -> (EventItem, Int)? in
                guard let d = SharedDates.daysUntil(ev.date, repeatsYearly: ev.repeatsYearly),
                      d >= 0 else { return nil }
                return (ev, d)
            }
            .sorted { $0.1 < $1.1 }
            .map { WidgetEventLite(id: $0.0.id, title: $0.0.title, emoji: $0.0.emoji,
                                   date: $0.0.date, repeatsYearly: $0.0.repeatsYearly) }
        if let photo = widgetPhoto {
            snapshot.photoURLString = api?.mediaURL(photo.thumbUrl ?? photo.url)?.absoluteString
            snapshot.photoCaption = photo.caption
        }
        // Relationship level — level ring on widgets.
        if let level = levelState {
            snapshot.levelNumber = level.level
            snapshot.levelTitleDE = level.title.de
            snapshot.levelTitleEN = level.title.en
            snapshot.levelProgress = level.progress
        }
        // „An diesem Tag": the closest memory for the memory widget.
        if let memory = widgetMemory, let item = memory.items.first {
            snapshot.memoryDateKey = memory.dateKey
            snapshot.memoryKind = item.kind
            snapshot.memoryDistanceUnit = item.distance.unit
            snapshot.memoryDistanceN = item.distance.n
            let lines = widgetMemoryLines(item)
            snapshot.memoryLineDE = lines.de
            snapshot.memoryLineEN = lines.en
            if let photo = item.photo {
                snapshot.memoryPhotoURLString = api?.mediaURL(photo.thumbUrl ?? photo.url)?.absoluteString
            }
            snapshot.memoryCount = memory.items.count
        }
        snapshot.updatedAt = Date()
        // v10 performance pass: every socket event funnels through here, but
        // WidgetKit budgets reloads harshly — skip the write + reload when
        // nothing the widgets can see actually changed.
        let signature = snapshot.contentSignature
        if signature == nil || signature != lastWidgetSnapshotSignature {
            lastWidgetSnapshotSignature = signature
            SharedStore.writeSnapshot(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
        }
        persistCoreColdCache()
    }

    /// Preview line of an "on this day" memory, resolved in BOTH languages so
    /// the widget can follow the app language without ContentPack access.
    private func widgetMemoryLines(_ item: OnThisDayItem) -> (de: String?, en: String?) {
        switch item.kind {
        case "photo":
            return (item.photo?.caption, item.photo?.caption)
        case "daily":
            if let custom = item.customText { return (custom, custom) }
            guard let id = item.questionId,
                  let question = ContentPack.dailyQuestions.first(where: { $0.id == id }) else {
                return (nil, nil)
            }
            return (question.text.filled(partner: partnerName, lang: "de"),
                    question.text.filled(partner: partnerName, lang: "en"))
        default:
            return (nil, nil)
        }
    }

    // MARK: Cold-start core cache

    /// Restores enough authenticated state to render the dashboard immediately
    /// while the first network refresh is in flight. Cache records never carry
    /// tokens and are accepted only for the active profile's exact couple id.
    private func restoreCoreColdCache() {
        guard let profile = servers.activeProfile, profile.isPaired,
              let coupleID = profile.coupleId,
              let record = CoreColdCacheStore.shared.record(profileID: profile.id,
                                                            coupleID: coupleID),
              let cachedCouple = try? API.decoder.decode(Couple.self, from: record.couple),
              cachedCouple.id == coupleID else { return }
        couple = cachedCouple
        events = (try? API.decoder.decode([EventItem].self, from: record.events)) ?? []
        dailyEntry = record.daily.flatMap { try? API.decoder.decode(DailyEntry.self, from: $0) }
        stats = record.stats.flatMap { try? API.decoder.decode(Stats.self, from: $0) }
        levelState = record.level.flatMap { try? API.decoder.decode(LevelState.self, from: $0) }
    }

    private func persistCoreColdCache() {
        guard let profile = servers.activeProfile, profile.isPaired,
              let coupleID = profile.coupleId, let couple,
              couple.id == coupleID,
              let coupleData = try? API.encoder.encode(couple),
              let eventsData = try? API.encoder.encode(events) else { return }
        CoreColdCacheStore.shared.save(
            CoreColdCacheRecord(
                profileID: profile.id,
                coupleID: coupleID,
                savedAt: Date(),
                couple: coupleData,
                events: eventsData,
                daily: dailyEntry.flatMap { try? API.encoder.encode($0) },
                stats: stats.flatMap { try? API.encoder.encode($0) },
                level: levelState.flatMap { try? API.encoder.encode($0) }))
    }
}
