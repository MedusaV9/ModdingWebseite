import SwiftUI

// Zone „Spindel" — das Reaktions-System: Palette, Recents, Sticker-
// Overlay, Kontextmenü und VoiceOver-Chips. Reiner Struktur-Umzug aus
// ChatView.swift (N3-Zerlegung, ENTSCHEID §4.2).

// MARK: - Reactions

/// The fixed reaction palette; double-tap sends the quick heart.
enum ChatReactions {
    static let palette = ["❤️", "😂", "😮", "🥺", "🔥", "👍"]
    static let quick = "❤️"
}

/// Most recently used reaction emojis (persisted) — the fixed palette
/// reorders so favorites sit first in every react menu.
enum ChatReactionRecents {
    private static let key = "sooodreamy.chatReactionRecents"

    static func record(_ emoji: String) {
        var list = UserDefaults.standard.stringArray(forKey: key) ?? []
        list.removeAll { $0 == emoji }
        list.insert(emoji, at: 0)
        UserDefaults.standard.set(Array(list.prefix(3)), forKey: key)
    }

    /// Palette with the last-used emojis pulled to the front (no duplicates,
    /// unknown entries dropped — the palette stays the single source).
    static func orderedPalette() -> [String] {
        let recents = (UserDefaults.standard.stringArray(forKey: key) ?? [])
            .filter { ChatReactions.palette.contains($0) }
        return recents + ChatReactions.palette.filter { !recents.contains($0) }
    }
}

/// One aggregated reaction on a message — shared by the sticker overlay and
/// the a11y chips so both render the exact same state.
struct ChatReactionEntry: Identifiable, Equatable {
    let emoji: String
    let count: Int
    let mine: Bool
    var id: String { emoji }
}

/// Aggregates the reactions dict into stable, palette-ordered entries.
func chatReactionEntries(message: Message, myMemberId: String?) -> [ChatReactionEntry] {
    guard let reactions = message.reactions else { return [] }
    return reactions
        .filter { !$0.value.isEmpty }
        .sorted { a, b in
            let ia = ChatReactions.palette.firstIndex(of: a.key) ?? Int.max
            let ib = ChatReactions.palette.firstIndex(of: b.key) ?? Int.max
            if ia != ib { return ia < ib }
            return a.key < b.key
        }
        .map { emoji, ids in
            ChatReactionEntry(emoji: emoji,
                              count: ids.count,
                              mine: myMemberId.map { ids.contains($0) } ?? false)
        }
}

/// Stable FNV-1a hash — `String.hashValue` is randomized per process, but
/// the reaction-sticker layout must match on both partners' devices.
func chatStableSeed(_ text: String) -> Int {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in text.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x0000_0100_0000_01b3
    }
    return Int(truncatingIfNeeded: hash)
}

/// Reaction emojis that LAND on the message and stay stuck to the bubble's
/// lower edge like slightly crooked stickers. Position and rotation are
/// seeded from message id + emoji, so both partners see the identical
/// arrangement without any new server field.
struct ChatReactionStickerOverlay: View {
    let message: Message
    let myMemberId: String?
    let onToggle: (String) -> Void

    private var entries: [ChatReactionEntry] {
        chatReactionEntries(message: message, myMemberId: myMemberId)
    }

    var body: some View {
        GeometryReader { proxy in
            ForEach(entries) { entry in
                sticker(entry, size: proxy.size)
            }
        }
        .animation(Theme.Motion.playful, value: entries)
    }

    private func sticker(_ entry: ChatReactionEntry, size: CGSize) -> some View {
        var generator = SeededGenerator(seed: chatStableSeed(message.id + entry.emoji))
        let xFraction = 0.18 + Double(generator.int(upTo: 65)) / 100
        let rotation = Double(generator.int(upTo: 29)) - 14
        return Button {
            onToggle(entry.emoji)
        } label: {
            Text(entry.emoji)
                .font(.system(.title3))
                .scaleEffect(entry.count > 1 ? 1.25 : 1)
                .rotationEffect(.degrees(rotation))
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .position(x: xFraction * size.width, y: size.height)
        .transition(.scale(scale: 2.4).combined(with: .opacity))
        .accessibilityLabel(L10n.t("chat.reactWith", ["emoji": entry.emoji]))
    }
}

/// "Reagieren …" submenu for bubble context menus — recents first.
struct ChatReactMenu: View {
    let onReact: (String) -> Void

    var body: some View {
        Menu {
            ForEach(ChatReactionRecents.orderedPalette(), id: \.self) { emoji in
                Button {
                    onReact(emoji)
                } label: {
                    Text(emoji)
                }
                .accessibilityLabel(L10n.t("chat.reactWith", ["emoji": emoji]))
            }
        } label: {
            Label(L10n.t("chat.react"), systemImage: "face.smiling")
        }
    }
}

/// Capsule chips under a bubble showing existing reactions; tapping a chip
/// toggles that emoji for me. VoiceOver fallback for the sticker overlay.
struct ChatReactionChips: View {
    let message: Message
    let myMemberId: String?
    let onToggle: (String) -> Void

    @Environment(\.coupleTint) private var coupleTint

    private var entries: [ChatReactionEntry] {
        chatReactionEntries(message: message, myMemberId: myMemberId)
    }

    @ViewBuilder var body: some View {
        if !entries.isEmpty {
            HStack(spacing: 5) {
                ForEach(entries) { entry in
                    chip(entry)
                }
            }
        }
    }

    private func chip(_ entry: ChatReactionEntry) -> some View {
        Button {
            onToggle(entry.emoji)
        } label: {
            HStack(spacing: 3) {
                Text(entry.emoji)
                    .font(.system(.footnote))
                if entry.count > 1 {
                    // Nacht-first (P2-B): the chips are night chips — the
                    // bubbles keep ALL the paper. Counts speak night ink;
                    // MY reaction speaks lamplight (accent-TEXT rule §4),
                    // the ring stays the couple blend (non-text, ≥3:1).
                    Text("\(entry.count)")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(entry.mine ? Licht.lampengold : Nacht.sekundaer)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 7)
            .background(
                Capsule()
                    .fill(Papier.nachtkarton)
                    .overlay(
                        Capsule().strokeBorder(entry.mine ? AnyShapeStyle(coupleTint.blend)
                                                          : AnyShapeStyle(Nacht.naht),
                                               lineWidth: entry.mine ? 1.5 : Theme.hairlineWidth)
                    )
                    .elevation(.resting)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t("chat.reactWith", ["emoji": entry.emoji]))
    }
}
