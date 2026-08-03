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

/// Central app state: active server session, couple data, socket events.
@MainActor
@Observable
final class AppState {
    let servers = ServerStore()
    let socket = SocketClient()

    // Session data (per active server)
    var couple: Couple?
    var events: [EventItem] = []
    var dailyEntry: DailyEntry?
    var stats: Stats?
    var sessionLoading = false
    /// Showcase photo for the photo widget (newest favorite, else newest).
    var widgetPhoto: Photo?

    /// Stroke count last mirrored to the widgets (see refreshWidgetCanvas).
    @ObservationIgnored private var widgetCanvasStrokeCount = 0
    /// Photo id whose bytes are currently in the shared widget cache.
    @ObservationIgnored private var cachedWidgetPhotoId: String?

    // UI state
    var activeTab: AppTab = .home
    var toast: Toast?
    var incomingTouch: Touch?
    var partnerTyping = false
    var unreadChat = 0
    var celebrate = false
    var uiRefresh = 0

    /// Last touch received from the partner — feeds widgets & live activities.
    /// Seeded from the shared snapshot so it survives app relaunches.
    var lastTouchType: String?
    var lastTouchAt: Date?

    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var touchTask: Task<Void, Never>?
    @ObservationIgnored private var typingTask: Task<Void, Never>?
    @ObservationIgnored private var eventObserver: NSObjectProtocol?
    /// Rate limit for "partner is online" alerts (max once per 10 min).
    @ObservationIgnored private var lastOnlineAlertAt: Date?

    init() {
        let snapshot = SharedStore.readSnapshot()
        lastTouchType = snapshot?.lastTouchType
        lastTouchAt = snapshot?.lastTouchAt
        eventObserver = NotificationCenter.default.addObserver(
            forName: .serverEvent, object: nil, queue: .main
        ) { [weak self] note in
            guard let event = note.object as? ServerEvent else { return }
            Task { @MainActor [weak self] in
                self?.handle(event)
            }
        }
    }

    // MARK: Derived state

    var phase: AppPhase {
        guard let profile = servers.activeProfile else { return .welcome }
        return profile.isPaired ? .main : .pairing
    }

    var memberId: String? { servers.activeProfile?.memberId }

    var api: API? {
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

    var partnerName: String { partner?.name ?? L10n.t("misc.partnerDefault") }

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
        await refreshAll()
        connectSocket()
        CouplePulseController.startIfEnabled(from: self)
    }

    /// Switch to another saved server (its own pairing/session context).
    func activateProfile(_ id: UUID) async {
        guard id != servers.activeProfileID else { return }
        socket.disconnect()
        couple = nil
        events = []
        dailyEntry = nil
        stats = nil
        unreadChat = 0
        servers.setActive(id: id)
        if let profile = servers.activeProfile {
            showToast(L10n.t("server.switched", ["name": profile.name]), style: .success)
        }
        if phase == .main {
            await refreshAll()
            connectSocket()
            CouplePulseController.startIfEnabled(from: self)
        }
    }

    /// Called after successful create/join on a profile.
    func completeAuth(profileID: UUID, auth: AuthResponse) {
        servers.attachSession(profileID: profileID, token: auth.token,
                              coupleId: auth.coupleId, memberId: auth.memberId)
        servers.setActive(id: profileID)
        couple = auth.couple
        connectSocket()
        celebrateNow()
        Task {
            await refreshAll()
            CouplePulseController.startIfEnabled(from: self)
        }
    }

    func connectSocket() {
        guard let profile = servers.activeProfile,
              let url = profile.baseURL,
              let token = profile.token else { return }
        socket.connect(baseURL: url, token: token)
    }

    // MARK: Data refresh

    func refreshAll() async {
        sessionLoading = couple == nil
        defer { sessionLoading = false }
        await refreshCouple()
        async let e: Void = refreshEvents()
        async let d: Void = refreshDaily()
        async let s: Void = refreshStats()
        async let p: Void = refreshWidgetPhoto()
        async let c: Void = refreshWidgetCanvas()
        _ = await (e, d, s, p, c)
        updateWidgetSnapshot()
    }

    func refreshWidgetPhoto() async {
        guard let api else { return }
        if let photos = try? await api.photos() {
            widgetPhoto = photos.first { !($0.favorites ?? []).isEmpty } ?? photos.first
            await cacheWidgetPhotoBytes()
        }
    }

    /// Downloads the showcase photo's thumb bytes into the shared app-group
    /// cache so the widgets stay pretty when the server is unreachable.
    private func cacheWidgetPhotoBytes() async {
        guard let api, let photo = widgetPhoto else { return }
        guard photo.id != cachedWidgetPhotoId else { return }
        guard let url = api.mediaURL(photo.thumbUrl ?? photo.url) else { return }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
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
        do {
            let resp = try await api.getCouple()
            couple = resp.couple
        } catch {
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

    func refreshStats() async {
        guard let api else { return }
        stats = try? await api.stats()
    }

    func handleAPIError(_ error: Error) {
        if let apiErr = error as? APIError, apiErr.isUnauthorized {
            if let profile = servers.activeProfile {
                servers.clearSession(profileID: profile.id)
            }
            couple = nil
            socket.disconnect()
            showToast(L10n.t("error.unauthorized"), style: .error)
        } else {
            showToast(error.localizedDescription, style: .error)
        }
    }

    // MARK: Actions

    func sendTouch(_ kind: TouchKind) {
        guard let api else { return }
        Haptics.shared.play(kind)
        SoundEngine.shared.play(for: kind)
        Task {
            do {
                try await api.sendTouch(kind)
                showToast(L10n.t("home.touchSent", ["emoji": kind.emoji]), style: .love)
            } catch {
                handleAPIError(error)
            }
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
        socket.disconnect()
        servers.clearSession(profileID: profile.id)
        couple = nil
        events = []
        dailyEntry = nil
        stats = nil
        unreadChat = 0
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
        case .message:
            if let payload = event.decode(MessageResponse.self) {
                if payload.message.senderId != memberId {
                    if activeTab != .chat {
                        unreadChat += 1
                        notifyMessage(payload.message)
                    }
                    SoundEngine.shared.play(.pop)
                }
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
            if let payload = event.decode(MemberResponse.self) {
                Task { await refreshCouple() }
                showToast(L10n.t("misc.partnerJoinedToast", ["name": payload.member.name]), style: .love)
                SoundEngine.shared.play(.tada)
                Haptics.shared.success()
                celebrateNow()
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
                                   title: L10n.t("notif.photo.title"),
                                   body: L10n.t("notif.photo.body", ["name": partnerName]),
                                   link: "sooodreamy://tab/memories")
            }
            Task {
                await refreshWidgetPhoto()
                updateWidgetSnapshot()
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
                                   title: L10n.t("notif.coupon.title"),
                                   body: L10n.t("notif.coupon.body",
                                                ["name": partnerName, "title": coupon.title]),
                                   link: "sooodreamy://tab/memories")
            }
        case .couponRedeemed:
            if let coupon = event.decode(CouponResponse.self)?.coupon, coupon.createdBy == memberId {
                showToast(L10n.t("coupon.redeemedToast", ["title": coupon.title]), style: .love)
                SoundEngine.shared.play(.tada)
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
        default:
            break   // feature views observe .serverEvent themselves
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

    private func receiveTouch(_ touch: Touch) {
        incomingTouch = touch
        Haptics.shared.play(touch.type)
        SoundEngine.shared.play(for: touch.type)
        if touch.senderId != memberId {
            lastTouchType = touch.type.rawValue
            lastTouchAt = touch.createdAt
            CoupleNotify.alert(.touch,
                               title: "\(touch.type.emoji) \(L10n.t(touch.type.titleKey))",
                               body: L10n.t("touch.received.\(touch.type.rawValue)", ["name": partnerName]),
                               sound: NotificationPrefs.soundOverride(for: .touch)
                                   ?? .mapped(for: touch.type),
                               link: "sooodreamy://tab/home")
        }
        touchTask?.cancel()
        touchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_200_000_000)
            if !Task.isCancelled { self?.incomingTouch = nil }
        }
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

    private static func preview(of text: String, limit: Int = 120) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count <= limit ? trimmed : String(trimmed.prefix(limit)) + "…"
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
        case "daily":
            activeTab = .home
        case "action":
            if path == "sendlove" {
                let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
                let raw = comps?.queryItems?.first(where: { $0.name == "type" })?.value ?? "heartbeat"
                sendTouch(TouchKind(rawValue: raw) ?? .heartbeat)
            }
        default:
            break
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
        let daily = couple.map { ContentPack.dailyQuestion(dateKey: SharedDates.todayKey(), coupleId: $0.id) }
        var snapshot = WidgetSnapshot()
        snapshot.partnerName = partner?.name
        snapshot.partnerAvatar = partner?.avatar
        snapshot.partnerColorHex = partner?.color
        snapshot.partnerMood = partner?.mood
        snapshot.partnerMoodNote = partner?.moodNote
        snapshot.partnerMoodUpdatedAt = partner?.moodUpdatedAt
        snapshot.partnerOnline = partner?.online
        snapshot.lastTouchType = lastTouchType
        snapshot.lastTouchAt = lastTouchAt
        snapshot.myName = me?.name
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
        snapshot.canvasStrokeCount = widgetCanvasStrokeCount
        if let photo = widgetPhoto {
            snapshot.photoURLString = api?.mediaURL(photo.thumbUrl ?? photo.url)?.absoluteString
            snapshot.photoCaption = photo.caption
        }
        snapshot.updatedAt = Date()
        SharedStore.writeSnapshot(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
