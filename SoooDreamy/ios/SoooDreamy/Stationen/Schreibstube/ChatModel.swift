import Foundation
import Observation

/// One day worth of chat messages (used for the sticky date chips).
struct ChatDaySection: Identifiable {
    /// Start of day for all contained messages.
    let id: Date
    let messages: [Message]
}

/// The reconciliation law (`ChatVersoehnung`, LogicTest-pinned) sees
/// messages through this lens; it also provides `chatRowID` — the stable
/// transcript-row identity that survives the local→server id swap.
extension Message: VersoehnbarerZettel {}

/// View model for the chat screen: initial load, pagination via `before`,
/// optimistic sends, realtime inserts with de-duplication.
@MainActor
@Observable
final class ChatModel {
    private(set) var messages: [Message] = []
    private(set) var initialLoading = false
    private(set) var loadingOlder = false
    private(set) var canLoadOlder = false
    private(set) var loaded = false
    /// True after a failed initial history load — the chat shows an honest
    /// error/retry state instead of merely LOOKING empty (SurfaceState).
    private(set) var loadFailed = false
    /// Spindelstich (§4.2): id of the own Zettel that was JUST sent. It
    /// FOLLOWS the Zettel through the local→server id swap, so the ink
    /// dot stays on exactly this message — never on `messages.last`,
    /// which any incoming Zettel could steal mid-moment.
    private(set) var spindelstichID: String?
    /// The `chatRowID` of that send's optimistic insert: the one-time
    /// Legen slot of the send frame binds here. Because the row identity
    /// SURVIVES the local→server id swap (ChatVersoehnung), the slot
    /// keeps pointing at the same — never remounted — row until the
    /// landing window clears it.
    private(set) var sendLegenID: String?

    private static let pageSize = 50

    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private var typingActive = false
    @ObservationIgnored private var lastTypingSentAt = Date.distantPast
    @ObservationIgnored private var typingStopTask: Task<Void, Never>?
    @ObservationIgnored private var sendLegenClearTask: Task<Void, Never>?
    @ObservationIgnored private let outbox = OfflineOutboxStore.shared

    /// Must be called once before use (the view owns the model via @State).
    func configure(_ appState: AppState) {
        self.appState = appState
        // CI screenshot mode and the in-app demo (Welle 7 [29]): the staged
        // transcript replaces the server load — `loaded` short-circuits
        // `loadInitial()`.
        if appState.demoActive {
            messages = ScreenshotSeed.demoModeTranscript
            loaded = true
            return
        }
        if let staged = ScreenshotSeed.chatTranscript {
            messages = staged
            loaded = true
            return
        }
        hydratePendingMessages()
        Task { await flushOutbox() }
    }

    /// Wipe everything (e.g. after switching to another server — each server
    /// is a completely separate couple context).
    func reset() {
        messages = []
        loaded = false
        canLoadOlder = false
        initialLoading = false
        loadingOlder = false
        loadFailed = false
        spindelstichID = nil
        sendLegenID = nil
        stopTyping()
        hydratePendingMessages()
        Task { await flushOutbox() }
    }

    /// Messages grouped by calendar day, ascending.
    var sections: [ChatDaySection] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: messages) { cal.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted().map { day in
            ChatDaySection(id: day, messages: grouped[day] ?? [])
        }
    }

    // MARK: Loading

    func loadInitial() async {
        guard !loaded, !initialLoading, let api = appState?.api else { return }
        initialLoading = messages.isEmpty
        defer { initialLoading = false }
        do {
            let page = try await api.messages(limit: Self.pageSize)
            mergeIn(page)
            canLoadOlder = page.count >= Self.pageSize
            loaded = true
            loadFailed = false
            await flushOutbox()
        } catch {
            // `loaded` stays false, so the retry button can call this again.
            loadFailed = true
            appState?.handleAPIError(error)
        }
    }

    /// Pull-to-refresh at the top loads the previous page (older messages).
    func loadOlder() async {
        guard canLoadOlder, !loadingOlder,
              let oldest = messages.first,
              let api = appState?.api else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        do {
            let page = try await api.messages(limit: Self.pageSize, before: oldest.id)
            mergeIn(page)
            canLoadOlder = page.count >= Self.pageSize
        } catch {
            appState?.handleAPIError(error)
        }
    }

    // MARK: Sending

    /// Persists before optimistic append, then reconciles with server truth.
    /// A transport failure remains visible and queued instead of restoring a
    /// fragile composer draft that would disappear on process termination.
    func sendText(_ raw: String, effect: MessageEffect? = nil) async -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let appState else { return false }
        stopTyping()
        // Demo mode (Welle 7 [29]): no server, no outbox — the send lands
        // as a purely local echo so the composer feels real, and it
        // evaporates together with the rest of the demo.
        if appState.demoActive {
            // No cue here: ChatView.sendDraft already played the ONE
            // immediate `.sent` cue in the tap frame (re-eval 2, F5).
            let echo = Self.demoEcho(text: text, effect: effect,
                                     senderID: appState.memberId ?? "")
            insert(echo)
            spindelstichID = echo.id
            armSendLegen(rowID: echo.chatRowID)
            return true
        }
        guard let scope = outboxScope else { return false }
        let entry = outbox.enqueue(text: text, effect: effect?.rawValue, scope: scope)
        let pending = pendingMessage(for: entry, senderID: appState.memberId ?? scope.memberID)
        insert(pending)
        spindelstichID = pending.id
        armSendLegen(rowID: pending.chatRowID)
        if let api = appState.api {
            // playSound false: the send already rang in ChatView.sendDraft —
            // a second cue on server confirm was the third feedback layer.
            _ = await transmit(entry, api: api, reportError: true, playSound: false)
        }
        return true
    }

    /// Stickers are first-class outbox citizens (same durable queue as text):
    /// a failed relay keeps the sticker visible and queued instead of
    /// toasting it into the void.
    func sendSticker(_ sticker: StickerRecipe, effect: MessageEffect? = nil) async -> Bool {
        guard let appState else { return false }
        stopTyping()
        if appState.demoActive {
            let echo = Self.demoEcho(text: "", effect: effect, sticker: sticker,
                                     senderID: appState.memberId ?? "")
            insert(echo)
            armSendLegen(rowID: echo.chatRowID)
            AppCue.sent.play()
            return true
        }
        guard let scope = outboxScope else { return false }
        let entry = outbox.enqueue(text: "", effect: effect?.rawValue, sticker: sticker,
                                   scope: scope)
        let pending = pendingMessage(for: entry, senderID: appState.memberId ?? scope.memberID)
        insert(pending)
        armSendLegen(rowID: pending.chatRowID)
        if let api = appState.api {
            _ = await transmit(entry, api: api, reportError: true, playSound: true)
        }
        return true
    }

    /// One send, one landing (S2 fix): the optimistic insert's ROW id
    /// becomes the one-time Legen slot the transcript binds to. After the
    /// landing window the slot clears itself, so a LazyVStack row recycled
    /// back on screen can never replay the entrance. The row identity
    /// survives the local→server id swap (ChatVersoehnung), so the slot
    /// keeps addressing the same — never remounted — row throughout.
    private func armSendLegen(rowID: String) {
        sendLegenID = rowID
        sendLegenClearTask?.cancel()
        sendLegenClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(ChatSpindelstich.legenFenster))
            guard !Task.isCancelled else { return }
            if self?.sendLegenID == rowID { self?.sendLegenID = nil }
        }
    }

    /// A demo-mode message: never enqueued, never sent — the "local-" id
    /// prefix keeps it out of edit/delete/reaction paths like any pending
    /// bubble, just without a queue behind it.
    private static func demoEcho(text: String, effect: MessageEffect?,
                                 sticker: StickerRecipe? = nil,
                                 senderID: String) -> Message {
        Message(id: "local-demo-\(UUID().uuidString)",
                senderId: senderID,
                clientMessageId: nil,
                type: sticker == nil ? .text : .sticker,
                text: text,
                title: nil,
                audioUrl: nil,
                durationSec: nil,
                photoId: nil,
                openWhen: nil,
                effect: effect,
                sticker: sticker,
                reactions: nil,
                editedAt: nil,
                createdAt: Date())
    }

    /// Insert a message that the server already accepted (letters, voice notes).
    func acceptSent(_ message: Message) {
        insert(message)
    }

    // MARK: Editing

    /// Rewrite the text of one of MY text/letter messages. The server
    /// response replaces the message in place; the `message_updated` socket
    /// echo is idempotent with that (same replace-by-id as reactions).
    func editMessage(_ message: Message, newText: String) {
        let text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != message.text,
              let appState, let api = appState.api,
              message.senderId == appState.memberId,
              message.type == .text || message.type == .letter,
              !message.id.hasPrefix("local-") else { return }
        Task {
            do {
                let updated = try await api.editMessage(id: message.id, text: text)
                update(updated)
                Haptics.shared.success()
                appState.showToast(L10n.t("chat.editSaved"), style: .success)
            } catch {
                appState.handleAPIError(error)
            }
        }
    }

    // MARK: Deleting

    /// Delete one of MY messages on the server, then drop it locally.
    /// The `message_deleted` socket echo is idempotent with the local removal.
    func deleteMessage(_ message: Message) {
        guard let appState, let api = appState.api,
              message.senderId == appState.memberId,
              !message.id.hasPrefix("local-") else { return }
        Task {
            do {
                try await api.deleteMessage(id: message.id)
                messages.removeAll { $0.id == message.id }
                Haptics.shared.tap()
                appState.showToast(L10n.t("chat.deleted"), style: .info)
            } catch {
                appState.handleAPIError(error)
            }
        }
    }

    // MARK: Realtime

    func handle(_ event: ServerEvent) {
        switch event.type {
        case .message:
            if let message = event.decode(MessageResponse.self)?.message {
                accept(message)
            }
        case .messageUpdated:
            // Reaction changes etc. — replace by id, order stays (createdAt fixed).
            if let message = event.decode(MessageResponse.self)?.message {
                update(message)
            }
        case .messageDeleted:
            // Either partner may have deleted their own message — drop it.
            if let payload = event.decode(IdPayload.self) {
                messages.removeAll { $0.id == payload.id }
            }
        case .welcome:
            // Socket (re)connected — pull anything missed while offline.
            if loaded {
                Task {
                    await refreshLatest()
                    await flushOutbox()
                }
            }
        default:
            break
        }
    }

    /// Folds one server-accepted message into the transcript through the
    /// PURE reconciliation law (`ChatVersoehnung.reconciled`, LogicTest-
    /// pinned): my own ACK replaces the optimistic temp IN PLACE — same
    /// array position, same `chatRowID` — so the row never remounts on the
    /// local→server id swap and Spindelstich/Legen can never replay
    /// (re-eval 2, Befund 1). Also clears the outbox entry and lets the
    /// ink dot FOLLOW the Zettel through the swap. Idempotent with the
    /// POST response, the socket echo and page merges.
    private func accept(_ message: Message) {
        if message.senderId == appState?.memberId {
            if let clientMessageId = message.clientMessageId {
                if let scope = outboxScope {
                    outbox.remove(clientMessageID: clientMessageId, scope: scope)
                }
                if spindelstichID == "local-\(clientMessageId)" {
                    spindelstichID = message.id
                }
            } else {
                // Pre-v4 server without a clientMessageId echo: match one
                // temp by type + trimmed text and replace it at its index
                // (no shared cmid — the row identity cannot survive here,
                // but position and count do).
                let incomingText = (message.text ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let idx = messages.firstIndex(where: { candidate in
                    candidate.id.hasPrefix("local-")
                        && candidate.type == message.type
                        && (candidate.text ?? "")
                            .trimmingCharacters(in: .whitespacesAndNewlines) == incomingText
                }) {
                    if spindelstichID == messages[idx].id {
                        spindelstichID = message.id
                    }
                    messages[idx] = message
                    return
                }
            }
        }
        messages = ChatVersoehnung.reconciled(messages, with: message)
    }

    /// After a reconnect, page backwards from the newest message until the
    /// fetched window overlaps the previously-newest cached message
    /// (bounded to 4 extra pages), so long offline stretches leave no
    /// invisible history hole and overlapping reactions get refreshed.
    private func refreshLatest() async {
        guard let api = appState?.api else { return }
        let previousNewestId = messages.last(where: { !$0.id.hasPrefix("local-") })?.id
        guard var page = try? await api.messages(limit: Self.pageSize) else { return }
        mergeIn(page)
        guard let previousNewestId else { return }
        var extraPages = 0
        while extraPages < 4,
              page.count >= Self.pageSize,
              !page.contains(where: { $0.id == previousNewestId }),
              let oldest = page.first {
            guard let older = try? await api.messages(limit: Self.pageSize, before: oldest.id),
                  !older.isEmpty else { return }
            mergeIn(older)
            page = older
            extraPages += 1
        }
    }

    // MARK: Reactions

    /// Toggle my `emoji` reaction on a message: optimistic local update,
    /// reconciled with the server response, resynced from the server on error.
    func toggleReaction(on message: Message, emoji: String) {
        guard let appState, let api = appState.api,
              let memberId = appState.memberId,
              let scope = outboxScope else { return }
        guard !message.id.hasPrefix("local-"),
              let idx = messages.firstIndex(where: { $0.id == message.id }) else { return }
        let operation = outbox.enqueue(
            kind: .reaction,
            payload: ["messageId": message.id, "emoji": emoji],
            scope: scope
        )
        let adding = !(messages[idx].reactions?[emoji] ?? []).contains(memberId)
        messages[idx] = Self.togglingReaction(messages[idx], emoji: emoji, memberId: memberId)
        Haptics.shared.tap()
        if adding {
            SoundEngine.shared.play(.pop)
        }
        Task {
            do {
                outbox.markOperationAttempt(id: operation.clientOperationID, scope: scope)
                let updated = try await api.toggleReaction(
                    messageId: message.id,
                    emoji: emoji,
                    clientOperationId: operation.clientOperationID
                )
                outbox.removeOperation(id: operation.clientOperationID, scope: scope)
                update(updated)
            } catch {
                // The outcome is unknown (the POST may have committed even
                // though the response was lost), so don't guess with a local
                // re-toggle — restore server truth for this message instead.
                await resyncMessage(id: message.id)
                appState.handleAPIError(error)
            }
        }
    }

    /// Re-fetches the newest page and replaces the given message with
    /// server truth when present. Leaves state untouched when the fetch
    /// fails too (the next `message_updated`/reconnect refresh fixes it).
    private func resyncMessage(id: String) async {
        guard let api = appState?.api else { return }
        guard let page = try? await api.messages(limit: Self.pageSize) else { return }
        if let fresh = page.first(where: { $0.id == id }) {
            update(fresh)
        }
    }

    private static func togglingReaction(_ message: Message, emoji: String,
                                         memberId: String) -> Message {
        var updated = message
        var reactions = updated.reactions ?? [:]
        var ids = reactions[emoji] ?? []
        if let existing = ids.firstIndex(of: memberId) {
            ids.remove(at: existing)
        } else {
            ids.append(memberId)
        }
        if ids.isEmpty {
            reactions.removeValue(forKey: emoji)
        } else {
            reactions[emoji] = ids
        }
        updated.reactions = reactions.isEmpty ? nil : reactions
        return updated
    }

    // MARK: Typing state (outgoing, debounced)

    /// Call on every draft edit: sends `true` at most every 2 s,
    /// automatically sends `false` 3 s after the last edit.
    func noteTyping() {
        guard let appState else { return }
        let now = Date()
        if now.timeIntervalSince(lastTypingSentAt) >= 2 {
            appState.socket.sendTyping(true)
            lastTypingSentAt = now
            typingActive = true
        }
        typingStopTask?.cancel()
        typingStopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.stopTyping()
        }
    }

    /// Call on send / clear / leave: immediately reports "not typing".
    func stopTyping() {
        typingStopTask?.cancel()
        typingStopTask = nil
        if typingActive {
            appState?.socket.sendTyping(false)
        }
        typingActive = false
        lastTypingSentAt = .distantPast
    }

    // MARK: Internals

    /// Replace an existing message in place (unknown ids are ignored).
    private func update(_ message: Message) {
        if let idx = messages.firstIndex(where: { $0.id == message.id }) {
            messages[idx] = message
        }
    }

    /// Every insert — optimistic temps included — flows through the SAME
    /// reconciliation law as realtime ACKs (Fix-Runde 4, S1): the old
    /// id-only dedup let the empirically proven ACK-before-insert race
    /// (socket echo first, delayed temp insert after) append a SECOND
    /// row with the same `chatRowID` — duplicate ForEach ids. The law
    /// lets existing (senderId, clientMessageId) server truth win: the
    /// late temp is consumed instead of appended.
    private func insert(_ message: Message) {
        messages = ChatVersoehnung.reconciled(messages, with: message)
    }

    /// Merge a fetched page through the same reconciliation law as realtime
    /// ACKs: known ids are replaced with server truth (refreshing reactions
    /// etc.), my own now-confirmed sends replace their optimistic temps IN
    /// PLACE, unknown messages are inserted chronologically.
    private func mergeIn(_ page: [Message]) {
        for message in page {
            accept(message)
        }
    }

    // MARK: Durable outbox

    private var outboxScope: OutboxScope? {
        guard let appState,
              let profile = appState.servers.activeProfile,
              let coupleID = profile.coupleId,
              let memberID = profile.memberId else { return nil }
        return OutboxScope(profileID: profile.id, coupleID: coupleID, memberID: memberID)
    }

    private func hydratePendingMessages() {
        guard let scope = outboxScope else { return }
        // Sender-scoped like the whole reconciliation (Fix-Runde 3, S1):
        // a PARTNER message that happens to carry the same cmid must not
        // suppress rehydrating my own queued Zettel.
        for entry in outbox.entries(for: scope)
        where !messages.contains(where: {
            $0.senderId == scope.memberID && $0.clientMessageId == entry.clientMessageID
        }) {
            insert(pendingMessage(for: entry, senderID: scope.memberID))
        }
    }

    /// Optimistic "local-…" bubble for a queued entry (text or sticker).
    private func pendingMessage(for entry: PendingChatText, senderID: String) -> Message {
        Message(id: "local-\(entry.clientMessageID)",
                senderId: senderID,
                clientMessageId: entry.clientMessageID,
                type: entry.sticker == nil ? .text : .sticker,
                text: entry.text,
                title: nil,
                audioUrl: nil,
                durationSec: nil,
                photoId: nil,
                openWhen: nil,
                effect: entry.effect.flatMap(MessageEffect.init(rawValue:)),
                sticker: entry.sticker,
                reactions: nil,
                editedAt: nil,
                createdAt: entry.createdAt)
    }

    // MARK: Failed shelf ("Konnte nicht gesendet werden")

    var failedEntries: [FailedOutboxEntry] {
        guard let scope = outboxScope else { return [] }
        return outbox.failedEntries(for: scope)
    }

    /// Human-requested retry: back into the queue, flushed right away.
    func retryFailed(clientMessageID: String) {
        guard let scope = outboxScope else { return }
        outbox.retryFailed(clientMessageID: clientMessageID, scope: scope)
        hydratePendingMessages()
        Task { await flushOutbox() }
    }

    func discardFailed(clientMessageID: String) {
        guard let scope = outboxScope else { return }
        outbox.discardFailed(clientMessageID: clientMessageID, scope: scope)
    }

    private enum TransmitOutcome {
        case sent
        /// Permanent rejection — entry moved to the failed shelf; the rest
        /// of the queue keeps flowing.
        case shelved
        /// Transient failure — stop the flush pass, FIFO order preserved.
        case blocked
    }

    private func flushOutbox() async {
        guard let scope = outboxScope, let api = appState?.api else { return }
        for entry in outbox.entries(for: scope) {
            let outcome = await transmit(entry, api: api, reportError: false, playSound: false)
            if outcome == .blocked { break } // FIFO: retry from here on next reconnect.
        }
        for operation in outbox.operations(for: scope, kinds: [.reaction]) {
            guard let messageID = operation.payload["messageId"],
                  let emoji = operation.payload["emoji"] else {
                outbox.removeOperation(id: operation.clientOperationID, scope: scope)
                continue
            }
            outbox.markOperationAttempt(id: operation.clientOperationID, scope: scope)
            do {
                let updated = try await api.toggleReaction(
                    messageId: messageID,
                    emoji: emoji,
                    clientOperationId: operation.clientOperationID
                )
                outbox.removeOperation(id: operation.clientOperationID, scope: scope)
                update(updated)
            } catch {
                let verdict = OutboxRetryPolicy.verdict(
                    failure: OutboxFailureKind(classifying: error),
                    attemptCount: operation.attemptCount + 1)
                if verdict == .giveUp {
                    // A permanently rejected reaction (message deleted etc.)
                    // must not dam up the queue — drop it and continue.
                    outbox.removeOperation(id: operation.clientOperationID, scope: scope)
                    continue
                }
                break // Keep FIFO and retry after the next successful refresh.
            }
        }
    }

    @discardableResult
    private func transmit(_ entry: PendingChatText, api: API,
                          reportError: Bool, playSound: Bool) async -> TransmitOutcome {
        outbox.markAttempt(clientMessageID: entry.clientMessageID, scope: entry.scope)
        do {
            let sent: Message
            if let sticker = entry.sticker {
                sent = try await api.sendSticker(
                    sticker,
                    effect: entry.effect.flatMap(MessageEffect.init(rawValue:)),
                    clientMessageId: entry.clientMessageID)
            } else {
                sent = try await api.sendMessage(
                    type: .text, text: entry.text,
                    clientMessageId: entry.clientMessageID,
                    effect: entry.effect.flatMap(MessageEffect.init(rawValue:)))
            }
            outbox.remove(clientMessageID: entry.clientMessageID, scope: entry.scope)
            // `accept` replaces the temp IN PLACE (ChatVersoehnung) and lets
            // the ink dot follow the Zettel through the id swap — the row is
            // never removed and re-inserted, so its identity survives.
            accept(sent)
            if playSound { AppCue.sent.play() }
            return .sent
        } catch {
            let verdict = OutboxRetryPolicy.verdict(
                failure: OutboxFailureKind(classifying: error),
                attemptCount: entry.attemptCount + 1)
            switch verdict {
            case .giveUp:
                // Poison pill: move aside so the rest of the queue can flow.
                // The content stays retrievable on the failed shelf.
                outbox.markFailed(clientMessageID: entry.clientMessageID,
                                  scope: entry.scope,
                                  reason: (error as? APIError)?.serverCode)
                messages.removeAll {
                    $0.id.hasPrefix("local-") && $0.clientMessageId == entry.clientMessageID
                }
                appState?.showToast(L10n.t("chat.sendShelved"), style: .error)
                return .shelved
            case .retryLater:
                // A 401 heals silently via the rejoin proofs — always worth
                // reporting so the repair actually starts.
                if reportError || (error as? APIError)?.isUnauthorized == true {
                    appState?.handleAPIError(error)
                }
                return .blocked
            }
        }
    }
}
