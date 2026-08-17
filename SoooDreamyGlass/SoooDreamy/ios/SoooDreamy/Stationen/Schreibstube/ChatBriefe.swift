import SwiftUI
import UIKit

// Zone „Spindel" — Liebesbrief- und Sticker-Zettel. Reiner
// Struktur-Umzug aus ChatView.swift (N3-Zerlegung, ENTSCHEID §4.2).

// MARK: - Love letter bubble

struct ChatLetterBubble: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    let message: Message
    let isMine: Bool
    let onReact: (String) -> Void
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onForward: (() -> Void)? = nil

    @State private var unsealing = false
    @State private var celebrating = false
    @State private var showReader = false

    /// Received sealed letters stay closed until opened once on this device.
    private var isSealed: Bool {
        guard !isMine, message.openWhen != nil else { return false }
        return !OpenedLettersStore.shared.isOpened(message.id, coupleId: appState.couple?.id)
    }

    var body: some View {
        Group {
            if isSealed {
                sealedCard
                    .transition(.scale(scale: 1.15).combined(with: .opacity))
            } else {
                openCard
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .overlay(celebrationOverlay)
        .sheet(isPresented: $showReader) {
            LetterReaderView(message: message, senderName: senderName)
        }
    }

    private var senderName: String {
        if isMine { return appState.me?.name ?? L10n.t("chat.you") }
        return appState.partnerName
    }

    // MARK: Sealed state

    private var sealedCard: some View {
        SealedLetterCard(message: message, unsealing: unsealing, onOpen: unseal)
            .scaleEffect(unsealing ? 1.08 : 1)
            .rotation3DEffect(.degrees(unsealing ? 360 : 0), axis: (x: 0, y: 1, z: 0))
            .animation(Theme.Motion.drift(0.65), value: unsealing)
    }

    private func unseal() {
        guard !unsealing else { return }
        unsealing = true
        celebrating = true
        // Paper tears, then the reveal shimmer — plus the pulling haptic.
        AppCue.unseal.play()
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            withAnimation(Theme.Motion.arrive) {
                OpenedLettersStore.shared.markOpened(message.id, coupleId: appState.couple?.id)
            }
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            // Glitch-Pass (P2-B): the hearts overlay declares a fade
            // transition — without a driver the celebration CUT off hard
            // after its 2.2 s instead of fading with the ceremony.
            withAnimation(Theme.Motion.settle) { celebrating = false }
            unsealing = false
        }
    }

    @ViewBuilder private var celebrationOverlay: some View {
        if celebrating {
            FloatingHeartsView(emojis: ["💌", "💖", "✨", "💜"], count: 12)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    // MARK: Open state

    private var openCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            badge
            sealChip
            if let title = message.title, !title.isEmpty {
                // The address line is the couple's own wording — the serif
                // voice in the couple's shared ink (identity accent on
                // paper, never running text).
                Text(title)
                    .font(Typo.voice)
                    .foregroundStyle(coupleTint.tinte)
            }
            // Letter prose is the couple's own words — the upright serif
            // reading voice in dark ink, exactly like the reader.
            Text(message.text ?? "")
                .font(Typo.brief)
                .foregroundStyle(Tinte.dunkel)
            HStack {
                Spacer()
                ChatTimestampText(date: message.createdAt, isMine: isMine,
                                  read: chatReadReceipt(for: message, isMine: isMine,
                                                        partner: appState.partner),
                                  edited: message.editedAt != nil)
            }
        }
        .padding(LayoutMetrics.s(15))
        .background(letterBackground)
        .contentShape(RoundedRectangle(cornerRadius: Radius.papier, style: .continuous))
        .onTapGesture(count: 2) {
            onReact(ChatReactions.quick)
        }
        .onTapGesture {
            Haptics.shared.tap()
            showReader = true
        }
        .contextMenu {
            ChatReactMenu(onReact: onReact)
            copyButton
            readButton
            ChatPinButton(message: message)
            if let onForward {
                forwardButton(onForward)
            }
            if let onEdit {
                ChatEditButton(onEdit: onEdit)
            }
            if let onDelete {
                ChatDeleteButton(onDelete: onDelete)
            }
        }
    }

    private var badge: some View {
        HStack(spacing: 6) {
            if let members = appState.couple?.members, members.count >= 2 {
                CoupleMonogramView(
                    firstName: members[0].name,
                    secondName: members[1].name,
                    palette: appState.couple?.palette,
                    style: appState.couple?.monogramStyle ?? .seal,
                    size: 24
                )
            } else {
                // Gold is banned as ink on paper (1.4:1) — the badge wears
                // the couple's shared ink instead (identity accent).
                Image(systemName: "envelope.open.fill")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(coupleTint.tinte)
                    .accessibilityHidden(true)
            }
            Text(L10n.t("chat.letterBadge"))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(coupleTint.tinte)
        }
    }

    /// Small seal hint on own sealed letters (and on opened received ones)
    /// — wax red is the stamp-pad material: 5.2:1 on paper (pinned), and
    /// it never appears on night.
    @ViewBuilder private var sealChip: some View {
        if let token = message.openWhen {
            HStack(spacing: 5) {
                Image(systemName: "lock.fill")
                    .font(.system(.caption2, design: .rounded))
                    .accessibilityHidden(true)
                Text(LetterSeal.sentence(for: token))
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .lineLimit(2)
            }
            .foregroundStyle(Wachs.rot)
            .padding(.vertical, 4)
            .padding(.horizontal, 9)
            .background(Capsule().fill(Wachs.rot.opacity(0.10)))
        }
    }

    private var copyButton: some View {
        Button {
            let parts = [message.title, message.text].compactMap { $0 }.filter { !$0.isEmpty }
            UIPasteboard.general.string = parts.joined(separator: "\n\n")
            Haptics.shared.tap()
            appState.showToast(L10n.t("chat.copied"), style: .success)
        } label: {
            Label(L10n.t("chat.copy"), systemImage: "doc.on.doc")
        }
    }

    private var readButton: some View {
        Button {
            showReader = true
        } label: {
            Label(L10n.t("chat.read"), systemImage: "book.fill")
        }
    }

    private func forwardButton(_ onForward: @escaping () -> Void) -> some View {
        Button {
            Haptics.shared.tap()
            onForward()
        } label: {
            Label(L10n.t("chat.forwardLetter"), systemImage: "arrowshape.turn.up.right")
        }
    }

    /// The letter lies in the list as a letter-paper Zettel with the wax
    /// seal chip (Korrespondenz 8.2) — the glass-era couple wash and the
    /// gold stroke died with the paper wave (gold reads 1.4:1 on paper).
    /// Authorship shows in the ink edge, doubly coded with the side.
    private var letterBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
        return ZStack(alignment: .leading) {
            shape.fill(Papier.brief)
            if colorSchemeContrast != .increased {
                PaperGrainView()
            }
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

// MARK: - Procedural sticker bubble

struct ChatStickerBubble: View {
    @Environment(AppState.self) private var appState
    let message: Message
    let isMine: Bool
    var group = ChatGroupPosition()
    let onReact: (String) -> Void
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
            if let sticker = message.sticker {
                ProceduralStickerView(recipe: sticker, size: LayoutMetrics.s(132))
            }
            if group.isEnd || message.effect != nil {
                HStack(spacing: 6) {
                    MessageEffectBadge(effect: message.effect)
                    ChatTimestampText(
                        date: message.createdAt,
                        isMine: isMine,
                        read: chatReadReceipt(for: message, isMine: isMine, partner: appState.partner)
                    )
                }
            }
        }
        .padding(8)
        .background(ChatBubbleBackground(isMine: isMine,
                                         groupedTop: !group.isStart,
                                         groupedBottom: !group.isEnd))
        .onTapGesture(count: 2) { onReact(ChatReactions.quick) }
        .contextMenu {
            ChatReactMenu(onReact: onReact)
            ChatPinButton(message: message)
            if let onDelete {
                ChatDeleteButton(onDelete: onDelete)
            }
        }
    }
}
