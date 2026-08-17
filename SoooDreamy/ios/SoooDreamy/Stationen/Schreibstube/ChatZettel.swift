import SwiftUI
import UIKit

// Zone „Spindel" — der einzelne Zettel: Reihenlayout, Gruppierung,
// Papier-Hintergrund mit Tintenkante, Zeitstempel und Quittungen.
// Reiner Struktur-Umzug aus ChatView.swift (N3-Zerlegung, ENTSCHEID §4.2).

// MARK: - Message row

/// Where a message sits inside its sender group (~2-minute clusters of one
/// voice) — drives avatar visibility, the meta row and the tightened
/// bubble corners at the grouped edges.
struct ChatGroupPosition: Equatable {
    var isStart = true
    var isEnd = true
}

/// Two neighboring messages chain into one sender group when the same
/// person sent both within two minutes — love letters always stand alone
/// (a letter is a small ceremony, not a chat line).
func chatGroupChains(_ earlier: Message, _ later: Message) -> Bool {
    earlier.senderId == later.senderId
        && earlier.type != .letter && later.type != .letter
        && later.createdAt.timeIntervalSince(earlier.createdAt) < 120
}

struct ChatMessageRow: View {
    @Environment(AppState.self) private var appState
    /// With VoiceOver the reactions render as focusable chips below the
    /// bubble instead of free-floating stickers on its edge.
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.coupleTint) private var coupleTint
    let message: Message
    let isMine: Bool
    let partner: Member?
    var group = ChatGroupPosition()
    /// Signature „Spindelstich" (ENTSCHEID §4.2): true only on the own
    /// Zettel that was JUST sent — renders the 6-pt ink dot on its top
    /// edge. The haptic half fires in the send frame (ChatView.sendDraft).
    var spindled = false
    let onReact: (String) -> Void
    /// Wired only for messages the current member may edit (their own text/letter).
    var onEdit: (() -> Void)? = nil
    /// Wired only for messages the current member may delete (their own).
    var onDelete: (() -> Void)? = nil
    /// Wired for letters — opens the composer pre-filled to send the letter
    /// again as a new one.
    var onForward: (() -> Void)? = nil

    /// Live displacement of the leading swipe-to-react gesture on the
    /// partner's bubble (0 while resting or on my own bubbles).
    @State private var swipeOffset: CGFloat = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMine {
                Spacer(minLength: 44)
                bubbleColumn
            } else {
                // The avatar appears once per sender group, at its foot —
                // grouped messages keep the rail width so bubbles align.
                if group.isEnd {
                    EmojiAvatarView(emoji: partner?.avatar, colorHex: partner?.color, size: LayoutMetrics.s(28))
                } else {
                    Color.clear
                        .frame(width: LayoutMetrics.s(28), height: LayoutMetrics.s(28))
                }
                bubbleColumn
                    .offset(x: swipeOffset)
                    .background(alignment: .leading) { swipeHeart }
                    .gesture(swipeToReact)
                Spacer(minLength: 44)
            }
        }
        // Row identity = the STABLE `chatRowID` (Fix-Runde 3, S2): a bare
        // `message.id` remounted the whole subtree on the local→server id
        // swap of an ACK — Spindelstich restarted via onAppear even though
        // the ForEach id survived. Scroll anchors (pin jumps, bottom
        // follow) address rows by the same id.
        .id(message.chatRowID)
    }

    // MARK: Swipe to react (leading swipe on the partner's bubble)

    // DECISION (eval find 7, documented): the app has NO reply/quote
    // feature — messages carry no reply field and the server has no such
    // endpoint. The ChatGPT-style leading swipe therefore arms the
    // EXISTING quick reaction (the same ❤️ the double-tap sends) instead
    // of inventing a reply system. Sealed letters stay untouched — they
    // expose no reaction affordances until opened.

    /// Past this displacement, releasing fires the quick reaction.
    private var swipeTriggerDistance: CGFloat { LayoutMetrics.s(48) }

    /// 0…1 progress toward the trigger — drives the heart's arrival.
    private var swipeProgress: CGFloat {
        min(swipeOffset / swipeTriggerDistance, 1)
    }

    private var swipeToReact: some Gesture {
        DragGesture(minimumDistance: LayoutMetrics.s(24))
            .onChanged { value in
                guard !isSealedLetter else { return }
                let dx = value.translation.width
                // Horizontal-dominant drags to the RIGHT only — vertical
                // movement stays the scroll view's, trailing swipes are
                // not a gesture here.
                guard dx > 0, dx > abs(value.translation.height) else { return }
                // Damped pull with a soft cap — the bubble follows the
                // finger, but never sails across the pane.
                swipeOffset = min(dx * 0.55, swipeTriggerDistance * 1.25)
            }
            .onEnded { _ in
                if swipeOffset >= swipeTriggerDistance {
                    Haptics.shared.tap()
                    onReact(ChatReactions.quick)
                }
                withAnimation(reduceMotion ? nil : Theme.Motion.settle) {
                    swipeOffset = 0
                }
            }
    }

    /// The heart growing into the gap the sliding bubble reveals — purely
    /// visual chrome (the reaction itself lands as the usual sticker).
    @ViewBuilder private var swipeHeart: some View {
        if swipeOffset > 0 {
            Image(systemName: swipeProgress >= 1 ? "heart.fill" : "heart")
                .font(.system(.callout, design: .rounded).weight(.bold))
                // The couple's own blend, not stock pink (Gebot 11) — the
                // arriving heart wears the same signature as the reaction.
                .foregroundStyle(coupleTint.blend)
                .opacity(Double(swipeProgress))
                .scaleEffect(0.6 + 0.4 * swipeProgress)
                .frame(width: max(swipeOffset, 1))
                .accessibilityHidden(true)
        }
    }

    /// Delete is only offered on my own, server-confirmed messages.
    private var deleteAction: (() -> Void)? {
        guard isMine, !message.id.hasPrefix("local-") else { return nil }
        return onDelete
    }

    /// Edit is only offered on my own, server-confirmed text/letter messages
    /// (voice and photo messages are not editable).
    private var editAction: (() -> Void)? {
        guard isMine, !message.id.hasPrefix("local-"),
              message.type == .text || message.type == .letter else { return nil }
        return onEdit
    }

    /// Forward is offered on any server-confirmed letter (mine or my
    /// partner's) — sealed received letters expose no menu until opened.
    private var forwardAction: (() -> Void)? {
        guard message.type == .letter, !message.id.hasPrefix("local-") else { return nil }
        return onForward
    }

    private var bubbleColumn: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
            bubble
                .overlay {
                    if !isSealedLetter && !voiceOverEnabled {
                        ChatReactionStickerOverlay(message: message,
                                                   myMemberId: appState.memberId,
                                                   onToggle: onReact)
                    }
                }
                .overlay(alignment: .top) {
                    if spindled {
                        ChatSpindelstichPunkt()
                    }
                }
            if !isSealedLetter && voiceOverEnabled {
                ChatReactionChips(message: message,
                                  myMemberId: appState.memberId,
                                  onToggle: onReact)
            }
            if message.id.hasPrefix("local-") {
                Label(L10n.t("chat.queued"), systemImage: "clock.arrow.circlepath")
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(Licht.lampengold)
                    .accessibilityLabel(L10n.t("chat.queuedA11y"))
            }
        }
    }

    /// Received sealed letters get no reaction affordances until opened.
    private var isSealedLetter: Bool {
        guard message.type == .letter, !isMine, message.openWhen != nil else { return false }
        return !OpenedLettersStore.shared.isOpened(message.id, coupleId: appState.couple?.id)
    }

    @ViewBuilder private var bubble: some View {
        switch message.type {
        case .text:
            ChatTextBubble(message: message, isMine: isMine, group: group,
                           onReact: onReact,
                           onEdit: editAction, onDelete: deleteAction)
        case .voice:
            ChatVoiceBubble(message: message, isMine: isMine, group: group,
                            onReact: onReact,
                            onDelete: deleteAction)
        case .letter:
            ChatLetterBubble(message: message, isMine: isMine, onReact: onReact,
                             onEdit: editAction, onDelete: deleteAction,
                             onForward: forwardAction)
        case .photo:
            ChatPhotoBubble(message: message, isMine: isMine, group: group,
                            onReact: onReact,
                            onDelete: deleteAction)
        case .sticker:
            ChatStickerBubble(message: message, isMine: isMine, group: group,
                              onReact: onReact,
                              onDelete: deleteAction)
        }
    }
}

// MARK: - Spindelstich (Signature, ENTSCHEID §4.2)

/// The 6-pt ink dot on the top edge of the own Zettel that was JUST
/// spindled — the visible half of the Spindelstich (the haptic half fires
/// in the send frame, see `ChatView.sendDraft`). The dot wears the
/// couple's `tintePrimary` (identity accent on paper, never text). Reduce
/// Motion: ONLY opacity animates — the scale stays pinned at 1 (no
/// transform, but no hard pop to full presence either).
struct ChatSpindelstichPunkt: View {
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var eingestochen = false

    var body: some View {
        Circle()
            .fill(coupleTint.tintePrimary)
            .frame(width: ChatSpindelstich.punktDurchmesser,
                   height: ChatSpindelstich.punktDurchmesser)
            .scaleEffect(reduceMotion ? 1 : (eingestochen ? 1 : 0.2))
            .opacity(eingestochen ? 1 : 0)
            // Centered ON the top edge, like a pin pushed through paper.
            .offset(y: -ChatSpindelstich.punktDurchmesser / 2)
            .onAppear {
                // Both worlds ANIMATE the arrival — Reduce Motion swaps
                // the stitch scale-in for a pure opacity fade instead of
                // jumping to full opacity (S2 fix).
                withAnimation(reduceMotion ? Theme.Motion.settle
                                           : Theme.Motion.arrive) {
                    eingestochen = true
                }
            }
            .allowsHitTesting(false)
            // Decorative — the send itself is already announced by the
            // arriving message; the dot carries no extra information.
            .accessibilityHidden(true)
    }
}

// MARK: - Bubble background

/// Korrespondenz, completed (FullRelease R1-A, STYLE_DECISION §3.6):
/// BOTH sides are opaque paper Zettel now. My messages lie on
/// `Papier.polaroid` — one breath lighter than the partner's
/// `Papier.brief` — and the shiny couple-gradient messenger bubble is
/// gone: the couple gradient stays an OBJECT (band, send button), never
/// a surface for running text. Authorship is doubly coded: the 4-pt
/// Tintenkante sits on the OUTER edge in the author's own ink — mine =
/// `tinteSecondary` trailing, partner = `tintePrimary` leading (the
/// same assignment the letter Zettel established). Texts read in
/// `Tinte.dunkel`, meta in `Tinte.sekundaer`, on both sides. Corners
/// tighten where a sender group continues; cut paper uses
/// `Radius.papier` on both sides now.
struct ChatBubbleBackground: View {
    let isMine: Bool
    /// The bubble continues a group above / below (drives the tight corners).
    var groupedTop = false
    var groupedBottom = false
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    /// The Zettel radius — cut paper on BOTH sides since R1-A. Kept as a
    /// function of the side so callers that clip inner content (photo
    /// bubble) keep one rule with the background.
    static func radius(isMine: Bool) -> CGFloat {
        Radius.papier
    }

    private var baseRadius: CGFloat {
        Self.radius(isMine: isMine)
    }

    /// Tightened corner at a grouped edge — derived concentrically from the
    /// bubble radius (one Space.m step inside) instead of a free number.
    private var tightRadius: CGFloat {
        Radius.concentric(parent: baseRadius, padding: Space.m)
    }

    private var shape: UnevenRoundedRectangle {
        let top = groupedTop ? tightRadius : baseRadius
        let bottom = groupedBottom ? tightRadius : baseRadius
        return UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: isMine ? baseRadius : top,
                bottomLeading: isMine ? baseRadius : bottom,
                bottomTrailing: isMine ? bottom : baseRadius,
                topTrailing: isMine ? top : baseRadius),
            style: .continuous)
    }

    var body: some View {
        ZStack(alignment: isMine ? .trailing : .leading) {
            shape.fill(isMine ? Papier.polaroid : Papier.brief)
            // Grain is texture, not identity — off under Increased
            // Contrast (PaperRules law, same gate as paperCard).
            if colorSchemeContrast != .increased {
                PaperGrainView()
            }
            // The author's Tintenkante: their palette color through the
            // inkOnPaper ladder — identity accent, never text.
            Rectangle()
                .fill(isMine ? coupleTint.tinteSecondary : coupleTint.tintePrimary)
                .frame(width: Papier.tintenkante)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(PaperLightEdge.gradient,
                                    lineWidth: Theme.hairlineWidth))
        .elevation(.resting)
    }
}

// MARK: - Read receipts

/// nil → no receipt (partner's message or optimistic temp) · false → sent ·
/// true → partner's `lastReadAt` covers this message (they read it).
func chatReadReceipt(for message: Message, isMine: Bool, partner: Member?) -> Bool? {
    guard isMine, !message.id.hasPrefix("local-") else { return nil }
    guard let readAt = partner?.lastReadAt else { return false }
    return readAt >= message.createdAt
}

/// WhatsApp-style checkmarks: one = sent, two = read by the partner.
struct ChatReadReceiptMark: View {
    let read: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            Image(systemName: "checkmark")
            if read {
                Image(systemName: "checkmark")
                    .offset(x: LayoutMetrics.s(4))
            }
        }
        .font(.system(.caption2, design: .rounded).weight(.bold))
        // Receipts exist ONLY on own bubbles (see chatReadReceipt), which
        // are opaque paper Zettel since R1-A — the marks wear the quiet
        // secondary ink like the meta line next to them (7.5:1 on brief).
        // The one-vs-two checkmark count carries the state, not the color.
        .foregroundStyle(Tinte.sekundaer)
        .padding(.trailing, read ? LayoutMetrics.s(4) : 0)
        .accessibilityLabel(L10n.t(read ? "chat.receipt.read" : "chat.receipt.sent"))
    }
}

// MARK: - Timestamp

struct ChatTimestampText: View {
    let date: Date
    /// Kept for call-site stability — since R1-A EVERY bubble is a paper
    /// Zettel, so the side no longer changes the meta ink.
    let isMine: Bool
    /// Read receipt next to the time — nil hides the checkmarks entirely.
    var read: Bool? = nil
    /// Shows a small "(edited)" hint before the time.
    var edited: Bool = false

    /// Meta lines sit on opaque paper on BOTH sides (R1-A): the quiet
    /// secondary ink (caption2 sits below the tertiaer size floor, so
    /// tertiaer is off the table). The computed-ink-on-gradient branch
    /// died with the gradient bubble.
    private var foreground: Color { Tinte.sekundaer }

    var body: some View {
        HStack(spacing: 4) {
            if edited {
                Text(L10n.t("chat.edited"))
                    .font(.system(.caption2, design: .rounded).italic())
                    .foregroundStyle(foreground)
            }
            Text(date.formatted(date: .omitted, time: .shortened))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(foreground)
            if let read {
                ChatReadReceiptMark(read: read)
            }
        }
    }
}

// MARK: - Context-menu rows shared by all bubble types

/// "Delete my message" context-menu row (shared by all bubble types).
struct ChatDeleteButton: View {
    let onDelete: () -> Void

    var body: some View {
        Button(role: .destructive) {
            onDelete()
        } label: {
            Label(L10n.t("chat.deleteMessage"), systemImage: "trash")
        }
    }
}

/// "Edit my message" context-menu row (text & letter bubbles only, v1.8).
struct ChatEditButton: View {
    let onEdit: () -> Void

    var body: some View {
        Button {
            onEdit()
        } label: {
            Label(L10n.t("chat.editMessage"), systemImage: "pencil")
        }
    }
}
