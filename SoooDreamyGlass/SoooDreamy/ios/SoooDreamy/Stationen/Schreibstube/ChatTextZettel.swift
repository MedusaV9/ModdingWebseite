import SwiftUI
import UIKit

// Zone „Spindel" — der Text-Zettel samt Übersetzung, dazu Poststempel-
// Tagestrenner und Tipp-Indikator. Reiner Struktur-Umzug aus
// ChatView.swift (N3-Zerlegung, ENTSCHEID §4.2).

// MARK: - Text bubble

struct ChatTextBubble: View {
    @Environment(AppState.self) private var appState
    let message: Message
    let isMine: Bool
    var group = ChatGroupPosition()
    let onReact: (String) -> Void
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    @State private var revealed = false

    private var hidesText: Bool {
        message.effect == .invisible && !isMine && !revealed
    }

    private var translationCenter: ChatTranslationCenter { ChatTranslationCenter.shared }

    var body: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
            Text(message.text ?? "")
                .font(.system(.body, design: .rounded))
                // BOTH Zettel are opaque paper since R1-A — dark ink on
                // polaroid AND brief (≥13:1, the N2-A contrast anchor). The
                // computed-ink-on-gradient machinery left the chat with the
                // gradient bubble; authorship lives in the Tintenkante.
                .foregroundStyle(Tinte.dunkel)
                .multilineTextAlignment(isMine ? .trailing : .leading)
                .blur(radius: hidesText ? 8 : 0)
                .overlay {
                    if hidesText {
                        // Invisible ink exists only on the partner side —
                        // the chip sits ON paper: opaque dark-ink capsule,
                        // warm paper white on top (≈13:1).
                        Text(L10n.t("chat.effect.reveal"))
                            .font(.system(.caption, design: .rounded).weight(.bold))
                            .foregroundStyle(Papier.aufNacht)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Tinte.dunkel))
                    }
                }
                .onTapGesture {
                    if hidesText {
                        withAnimation(Theme.Motion.settle) { revealed = true }
                        Haptics.shared.tap()
                    }
                }
            translationBlock
            // The meta line appears once per sender group (discreet, at its
            // foot) — and always when it carries real information (effect
            // name, edited hint).
            if group.isEnd || message.effect != nil || message.editedAt != nil {
                HStack(spacing: 6) {
                    MessageEffectBadge(effect: message.effect)
                    ChatTimestampText(date: message.createdAt, isMine: isMine,
                                      read: chatReadReceipt(for: message, isMine: isMine,
                                                            partner: appState.partner),
                                      edited: message.editedAt != nil)
                }
            }
        }
        // Bubble density (P2-B UX polish): a hair less cream per Zettel —
        // the room around the correspondence breathes instead.
        .padding(.vertical, 8)
        .padding(.horizontal, LayoutMetrics.s(12))
        .background(ChatBubbleBackground(isMine: isMine,
                                         groupedTop: !group.isStart,
                                         groupedBottom: !group.isEnd))
        // Glitch-Pass (P2-B): the translation block declares a transition,
        // but the center mutates from async tasks with no withAnimation —
        // the block popped in and grew the Zettel with a hard jump.
        .animation(Theme.Motion.settle,
                   value: translationCenter.visibleState(for: message.id))
        .onTapGesture(count: 2) {
            onReact(ChatReactions.quick)
        }
        .contextMenu {
            ChatReactMenu(onReact: onReact)
            Button {
                UIPasteboard.general.string = message.text ?? ""
                Haptics.shared.tap()
                appState.showToast(L10n.t("chat.copied"), style: .success)
            } label: {
                Label(L10n.t("chat.copy"), systemImage: "doc.on.doc")
            }
            translationMenuItems
            ChatPinButton(message: message)
            if let onEdit {
                ChatEditButton(onEdit: onEdit)
            }
            if let onDelete {
                ChatDeleteButton(onDelete: onDelete)
            }
        }
    }

    // MARK: On-device translation (Welle 7 [27])

    /// The translation lives UNDER the original — the original text is
    /// sacred and never replaced. Secondary type + a micro-label keep it
    /// clearly marked as machine output. Partner Zettel are paper —
    /// divider and copy wear kante and the quiet inks (N2-A).
    @ViewBuilder private var translationBlock: some View {
        if !isMine, let state = translationCenter.visibleState(for: message.id) {
            VStack(alignment: .leading, spacing: 4) {
                Rectangle()
                    .fill(Papier.kante)
                    .frame(height: Theme.hairlineWidth)
                switch state {
                case .translating:
                    HStack(spacing: 6) {
                        ChatTypingDots(tint: Tinte.tertiaer)
                        Text(L10n.t("chat.translate.working"))
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Tinte.tertiaer)
                    }
                case .translated(let text):
                    Text(text)
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(Tinte.sekundaer)
                        .multilineTextAlignment(.leading)
                    // caption2 sits below the Tinte.tertiaer size floor
                    // (never under .caption) — the micro-label takes the
                    // secondary ink instead.
                    Label(L10n.t("chat.translate.label"), systemImage: "translate")
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(Tinte.sekundaer)
                case .failed(let key):
                    Text(L10n.t(key))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Tinte.tertiaer)
                }
            }
            .padding(.top, 2)
            .transition(.opacity)
        }
    }

    /// Offer / re-show / retry / hide — the offer itself is gated by the
    /// Foundation-only rules (partner message, real prose, not already in
    /// the app language).
    @ViewBuilder private var translationMenuItems: some View {
        if translationCenter.isShowingFailure(message.id) {
            Button {
                translationCenter.requestTranslation(messageId: message.id,
                                                     text: message.text ?? "")
            } label: {
                Label(L10n.t("chat.translate.retry"), systemImage: "arrow.counterclockwise")
            }
        }
        if translationCenter.isShowing(message.id) {
            Button {
                translationCenter.hideTranslation(for: message.id)
            } label: {
                Label(L10n.t("chat.translate.hide"), systemImage: "eye.slash")
            }
        } else if ChatTranslationRules.offersTranslation(text: message.text,
                                                         isMine: isMine,
                                                         appLanguage: L10n.lang) {
            Button {
                Haptics.shared.tap()
                translationCenter.requestTranslation(messageId: message.id,
                                                     text: message.text ?? "")
            } label: {
                Label(L10n.t("chat.translate.action"), systemImage: "translate")
            }
        }
    }
}

struct MessageEffectBadge: View {
    let effect: MessageEffect?

    var body: some View {
        if let effect {
            // Every bubble is a paper Zettel since R1-A: secondary ink on
            // both sides (caption2 sits below the tertiaer size floor).
            Text(L10n.t("chat.effect.\(effect.rawValue)"))
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(Tinte.sekundaer)
                .lineLimit(1)
        }
    }
}

// MARK: - Date chip (sticky section header)

struct ChatDateChip: View {
    let day: Date

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var label: String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return L10n.t("chat.today") }
        if cal.isDateInYesterday(day) { return L10n.t("chat.yesterday") }
        return day.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        // Poststempel, Nacht-first (P2-B): the date is WAYFINDING, not
        // correspondence — bright paper stays with the bubbles, the stamp
        // recedes into a dark nachtkarton capsule (MIGRATION_DUNKEL §3).
        // Night ink (Nacht.sekundaer, 8.1:1 pinned on nachtkarton) in the
        // rounded voice — serif/small-caps is paper-only (§4); the dashed
        // stamp contour glows in Licht.glut (wax is material on paper
        // only). Deliberately unrotated: the transcript's rotation budget
        // stays with the seeded reaction stickers.
        Text(label)
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .kerning(dynamicTypeSize.isAccessibilitySize ? 0 : 0.8)
            .foregroundStyle(Nacht.sekundaer)
            .padding(.vertical, 5)
            .padding(.horizontal, LayoutMetrics.s(14))
            .background(
                Capsule().fill(Papier.nachtkarton)
                    .overlay(
                        Capsule()
                            .strokeBorder(Licht.glut.opacity(0.45),
                                          style: StrokeStyle(lineWidth: Theme.hairlineWidth,
                                                             dash: [3, 3]))
                            .padding(2)
                    )
                    .elevation(.resting)
            )
            // Soft nachtkarton halo BEHIND the solid capsule (re-eval 2,
            // Befund 7): as a pinned header the stamp floats OVER bubbles
            // mid-scroll — the blurred outglow fades any glyph running
            // against the capsule edge instead of letting stamp and bubble
            // text collide pixel-hard.
            .background(
                Capsule()
                    .fill(Papier.nachtkarton.opacity(0.85))
                    .blur(radius: 6)
                    .padding(-5)
            )
            .frame(maxWidth: .infinity)
            // A full grid step of air above/below the pinned stamp so the
            // halo has room before the first bubble line (safe-area/nav
            // clearance stays the scroll view's own contentMargins).
            .padding(.vertical, Space.xs)
    }
}

// MARK: - Typing indicator

struct ChatTypingRow: View {
    let name: String
    let partner: Member?

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            EmojiAvatarView(emoji: partner?.avatar, colorHex: partner?.color, size: LayoutMetrics.s(28))
            HStack(spacing: 8) {
                // The typing Zettel is paper — dots and caption in the
                // quiet inks (N2-A, tertiaer floor: .caption is legal).
                ChatTypingDots(tint: Tinte.tertiaer)
                Text(L10n.t("chat.typing", ["name": name]))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Tinte.sekundaer)
            }
            .padding(.vertical, LayoutMetrics.s(10))
            .padding(.horizontal, LayoutMetrics.s(13))
            .background(ChatBubbleBackground(isMine: false))
            Spacer(minLength: 44)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

struct ChatTypingDots: View {
    /// Dot ink — default is the quiet Theme token (chrome surfaces); paper
    /// Zettel pass a Tinte. Since R1-A every chat bubble is paper, so no
    /// caller needs the gradient ink anymore.
    var tint: Color = Theme.textSecondary

    @Environment(\.motionGate) private var motionGate

    var body: some View {
        // Central motion gate (FXD-2 #5): under Reduce Motion the endless
        // wave never starts — the dots hold a calm resting pose, exactly
        // like particle canvases render a static glow instead of a
        // running timeline. The "…typing" caption still tells the story.
        if motionGate.particlesEnabled {
            TimelineView(.animation(minimumInterval: 0.08)) { timeline in
                dots(t: timeline.date.timeIntervalSinceReferenceDate)
            }
        } else {
            dots(t: 0)
        }
    }

    private func dots(t: TimeInterval) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                let wave = max(0, sin(t * 5.2 - Double(i) * 0.85))
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                    .offset(y: -4 * CGFloat(wave))
                    .opacity(0.45 + 0.55 * wave)
            }
        }
    }
}
