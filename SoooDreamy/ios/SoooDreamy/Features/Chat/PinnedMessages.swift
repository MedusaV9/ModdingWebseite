import SwiftUI
import Observation

// MARK: - Pinned messages persistence (v1.5.3)

/// One locally pinned chat message. The preview is snapshotted at pin time
/// so the banner can render even when the message is outside the currently
/// loaded chat window (older pages are fetched lazily).
struct PinnedMessageEntry: Codable, Equatable, Identifiable {
    let id: String          // message id
    let kind: String        // MessageKind rawValue
    let preview: String     // trimmed text/title snapshot ("" when none)
    let pinnedAt: Date
}

/// Remembers which chat messages were pinned on this device, per couple
/// (UserDefaults key "sooodreamy.pinnedMessages.<coupleId>"), newest pin
/// last. Deliberately local-only: a pin is a personal bookmark — the
/// partner's device stays untouched and no server support is needed.
@MainActor
@Observable
final class PinnedMessagesStore {
    static let shared = PinnedMessagesStore()

    /// Keep the list small — it's a bookmark ribbon, not an archive.
    private static let cap = 30

    /// Bumped on every change so SwiftUI re-reads the accessors.
    private(set) var version = 0
    @ObservationIgnored private var cache: [String: [PinnedMessageEntry]] = [:]

    private init() {}

    func isPinned(_ messageId: String, coupleId: String?) -> Bool {
        _ = version
        guard let coupleId else { return false }
        return entries(coupleId: coupleId).contains { $0.id == messageId }
    }

    /// All pins in pin order (oldest first, newest pin last).
    func entries(coupleId: String?) -> [PinnedMessageEntry] {
        _ = version
        guard let coupleId else { return [] }
        if let cached = cache[coupleId] { return cached }
        let key = storageKey(coupleId)
        let stored: [PinnedMessageEntry]
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([PinnedMessageEntry].self, from: data) {
            stored = decoded
        } else {
            stored = []
        }
        cache[coupleId] = stored
        return stored
    }

    /// Pin ⇄ unpin. Pinning past the cap drops the oldest pin.
    func toggle(_ message: Message, coupleId: String?) {
        guard let coupleId else { return }
        var list = entries(coupleId: coupleId)
        if let idx = list.firstIndex(where: { $0.id == message.id }) {
            list.remove(at: idx)
        } else {
            let preview = (message.title?.isEmpty == false ? message.title : message.text) ?? ""
            list.append(PinnedMessageEntry(id: message.id,
                                           kind: message.type.rawValue,
                                           preview: preview.trimmingCharacters(in: .whitespacesAndNewlines),
                                           pinnedAt: Date()))
            if list.count > Self.cap {
                list.removeFirst(list.count - Self.cap)
            }
        }
        persist(list, coupleId: coupleId)
    }

    /// Remove one pin by message id (used by the banner's unpin button).
    func unpin(_ messageId: String, coupleId: String?) {
        guard let coupleId else { return }
        var list = entries(coupleId: coupleId)
        list.removeAll { $0.id == messageId }
        persist(list, coupleId: coupleId)
    }

    private func persist(_ list: [PinnedMessageEntry], coupleId: String) {
        cache[coupleId] = list
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: storageKey(coupleId))
        }
        version += 1
    }

    private func storageKey(_ coupleId: String) -> String {
        "sooodreamy.pinnedMessages.\(coupleId)"
    }
}

// MARK: - Pin/unpin context-menu row

/// "Anpinnen"/"Pin lösen" context-menu row shared by all bubble types —
/// only server-confirmed messages can be pinned (temp ids don't survive).
struct ChatPinButton: View {
    @Environment(AppState.self) private var appState
    let message: Message

    private var pinned: Bool {
        PinnedMessagesStore.shared.isPinned(message.id, coupleId: appState.couple?.id)
    }

    @ViewBuilder var body: some View {
        if !message.id.hasPrefix("local-") {
            Button {
                let wasPinned = pinned
                withAnimation(.spring(response: 0.35)) {
                    PinnedMessagesStore.shared.toggle(message, coupleId: appState.couple?.id)
                }
                Haptics.shared.tap()
                appState.showToast(L10n.t(wasPinned ? "chat.unpinnedToast" : "chat.pinnedToast"),
                                   style: wasPinned ? .info : .success)
            } label: {
                Label(L10n.t(pinned ? "chat.unpin" : "chat.pin"),
                      systemImage: pinned ? "pin.slash" : "pin")
            }
        }
    }
}

// MARK: - Pinned banner

/// Compact banner above the message list showing the most recent pin.
/// Tapping jumps to the bubble when it's loaded (otherwise hints how to
/// load older history); the pin button on the right unpins, revealing the
/// next-newest pin, if any.
struct ChatPinnedBanner: View {
    @Environment(AppState.self) private var appState
    let messages: [Message]
    let onJump: (String) -> Void

    /// Newest pin (snapshotted preview works even for unloaded messages).
    private var entry: PinnedMessageEntry? {
        PinnedMessagesStore.shared.entries(coupleId: appState.couple?.id).last
    }

    private var pinCount: Int {
        PinnedMessagesStore.shared.entries(coupleId: appState.couple?.id).count
    }

    @ViewBuilder var body: some View {
        if let entry {
            HStack(spacing: LayoutMetrics.s(10)) {
                Image(systemName: "pin.fill")
                    .font(.scaled(12, weight: .bold))
                    .foregroundStyle(Theme.gold)
                    .rotationEffect(.degrees(45))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(L10n.t("chat.pinnedBadge"))
                            .font(.system(.caption2, design: .rounded).weight(.bold))
                            .foregroundStyle(Theme.gold)
                        if pinCount > 1 {
                            Text(L10n.t("chat.pinnedMore", ["n": String(pinCount - 1)]))
                                .font(.system(.caption2, design: .rounded).weight(.semibold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    Text(displayText(entry))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button {
                    Haptics.shared.tap()
                    withAnimation(.spring(response: 0.35)) {
                        PinnedMessagesStore.shared.unpin(entry.id, coupleId: appState.couple?.id)
                    }
                } label: {
                    Image(systemName: "pin.slash")
                        .font(.scaled(11, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: LayoutMetrics.s(26), height: LayoutMetrics.s(26))
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("chat.unpin"))
            }
            .padding(.vertical, LayoutMetrics.s(8))
            .padding(.horizontal, LayoutMetrics.s(12))
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.gold.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Theme.gold.opacity(0.35), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onTapGesture {
                onJump(entry.id)
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(L10n.t("chat.pinnedJumpA11y"))
            .padding(.horizontal, LayoutMetrics.s(14))
            .padding(.bottom, LayoutMetrics.s(6))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// Preview line: snapshotted text, or a typed placeholder for media.
    private func displayText(_ entry: PinnedMessageEntry) -> String {
        switch entry.kind {
        case MessageKind.voice.rawValue:
            return "🎤 " + L10n.t("chat.voiceMessage")
        case MessageKind.photo.rawValue:
            return entry.preview.isEmpty ? "📸 " + L10n.t("chat.photoMessage") : "📸 " + entry.preview
        case MessageKind.letter.rawValue:
            return entry.preview.isEmpty ? "💌 " + L10n.t("chat.letterBadge") : "💌 " + entry.preview
        default:
            return entry.preview
        }
    }
}
