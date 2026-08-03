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

    // UI state
    var activeTab: AppTab = .home
    var toast: Toast?
    var incomingTouch: Touch?
    var partnerTyping = false
    var unreadChat = 0
    var celebrate = false
    var uiRefresh = 0

    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var touchTask: Task<Void, Never>?
    @ObservationIgnored private var typingTask: Task<Void, Never>?
    @ObservationIgnored private var eventObserver: NSObjectProtocol?

    init() {
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
        Task { await refreshAll() }
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
        _ = await (e, d, s)
        updateWidgetSnapshot()
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
            }
        case .presence:
            if let p = event.decode(PresencePayload.self), p.memberId != memberId {
                setPartnerOnline(p.online, lastSeen: p.lastSeenAt)
            }
        case .touch:
            if let payload = event.decode(TouchResponse.self) {
                receiveTouch(payload.touch)
            }
        case .message:
            if let payload = event.decode(MessageResponse.self) {
                if payload.message.senderId != memberId {
                    if activeTab != .chat { unreadChat += 1 }
                    SoundEngine.shared.play(.pop)
                }
            }
        case .memberUpdated:
            if let payload = event.decode(MemberResponse.self) {
                applyMemberUpdate(payload.member)
                updateWidgetSnapshot()
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
                dailyEntry = entry
                if entry.bothAnswered { SoundEngine.shared.play(.sparkle) }
                updateWidgetSnapshot()
            }
        case .eventAdded, .eventUpdated, .eventDeleted:
            Task {
                await refreshEvents()
                updateWidgetSnapshot()
            }
        case .couponAdded:
            if let coupon = event.decode(CouponResponse.self)?.coupon, coupon.forMember == memberId {
                showToast(L10n.t("coupon.receivedToast"), style: .love)
                SoundEngine.shared.play(.sparkle)
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
        touchTask?.cancel()
        touchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_200_000_000)
            if !Task.isCancelled { self?.incomingTouch = nil }
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
        snapshot.updatedAt = Date()
        SharedStore.writeSnapshot(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
