import Foundation
import Observation

/// One day worth of chat messages (used for the sticky date chips).
struct ChatDaySection: Identifiable {
    /// Start of day for all contained messages.
    let id: Date
    let messages: [Message]
}

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

    private static let pageSize = 50

    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private var typingActive = false
    @ObservationIgnored private var lastTypingSentAt = Date.distantPast
    @ObservationIgnored private var typingStopTask: Task<Void, Never>?

    /// Must be called once before use (the view owns the model via @State).
    func configure(_ appState: AppState) {
        self.appState = appState
    }

    /// Wipe everything (e.g. after switching to another server — each server
    /// is a completely separate couple context).
    func reset() {
        messages = []
        loaded = false
        canLoadOlder = false
        initialLoading = false
        loadingOlder = false
        stopTyping()
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
        } catch {
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

    /// Optimistically appends, then reconciles with the server message.
    /// Returns false when the send failed (the caller may restore the draft).
    func sendText(_ raw: String) async -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let appState, let api = appState.api else { return false }
        stopTyping()
        let temp = Message(id: "local-\(UUID().uuidString)",
                           senderId: appState.memberId ?? "",
                           type: .text,
                           text: text,
                           title: nil,
                           audioUrl: nil,
                           durationSec: nil,
                           photoId: nil,
                           openWhen: nil,
                           reactions: nil,
                           createdAt: Date())
        insert(temp)
        do {
            let sent = try await api.sendMessage(type: .text, text: text)
            messages.removeAll { $0.id == temp.id }
            insert(sent)
            SoundEngine.shared.play(.pop)
            return true
        } catch {
            messages.removeAll { $0.id == temp.id }
            appState.handleAPIError(error)
            return false
        }
    }

    /// Insert a message that the server already accepted (letters, voice notes).
    func acceptSent(_ message: Message) {
        insert(message)
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
                if message.senderId == appState?.memberId {
                    removeMatchingPendingTemp(for: message)
                }
                insert(message)
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
                Task { await refreshLatest() }
            }
        default:
            break
        }
    }

    /// The couple-wide socket echo of my own message can arrive before the
    /// POST response removes the optimistic temp — drop one matching temp
    /// (same type + trimmed text) so both never render together.
    private func removeMatchingPendingTemp(for message: Message) {
        let incomingText = (message.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let idx = messages.firstIndex(where: { candidate in
            candidate.id.hasPrefix("local-")
                && candidate.type == message.type
                && (candidate.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == incomingText
        }) {
            messages.remove(at: idx)
        }
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
              let memberId = appState.memberId else { return }
        guard !message.id.hasPrefix("local-"),
              let idx = messages.firstIndex(where: { $0.id == message.id }) else { return }
        let adding = !(messages[idx].reactions?[emoji] ?? []).contains(memberId)
        messages[idx] = Self.togglingReaction(messages[idx], emoji: emoji, memberId: memberId)
        Haptics.shared.tap()
        if adding {
            SoundEngine.shared.play(.pop)
        }
        Task {
            do {
                let updated = try await api.toggleReaction(messageId: message.id, emoji: emoji)
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

    private func insert(_ message: Message) {
        guard !messages.contains(where: { $0.id == message.id }) else { return }
        messages.append(message)
        messages.sort { $0.createdAt < $1.createdAt }
    }

    /// Merge a fetched page: known ids are replaced with server truth
    /// (refreshing reactions etc.), unknown ones are inserted.
    private func mergeIn(_ page: [Message]) {
        for message in page {
            if let idx = messages.firstIndex(where: { $0.id == message.id }) {
                messages[idx] = message
            } else {
                messages.append(message)
            }
        }
        messages.sort { $0.createdAt < $1.createdAt }
    }
}
