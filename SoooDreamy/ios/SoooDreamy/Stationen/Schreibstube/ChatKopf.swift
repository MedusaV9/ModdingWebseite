import SwiftUI

// Zone „Kopf/Brett" — die Toolbar-Identität im Systembalken und das
// iPad-Rail (Briefe, Pins, Foto-Momente). Reiner Struktur-Umzug aus
// ChatView.swift (N3-Zerlegung, ENTSCHEID §4.2); Zugriff auf den
// gemeinsamen Zustand über die ChatView-Extension.

extension ChatView {

    // MARK: Header

    /// Staged CI screenshots and the in-app demo have no server — like the
    /// dashboard, the chat header presents a healthy connection instead of
    /// a red failure pill (see `ScreenshotMode` / `ScreenshotSeed`). Real
    /// launches always show the honest socket state.
    var connectionState: SocketState {
        (ScreenshotMode.stagesMainUI || appState.demoActive)
            ? .connected : appState.socket.displayState
    }

    /// The chat identity as the toolbar's principal item (R3): compact
    /// avatar + name + live status in the SYSTEM bar — the same pattern
    /// Messages uses, and the reason the minimized search chrome has a
    /// host again. One combined VoiceOver element.
    var toolbarIdentity: some View {
        HStack(spacing: LayoutMetrics.s(8)) {
            EmojiAvatarView(emoji: appState.partner?.avatar,
                            colorHex: appState.partner?.color,
                            size: LayoutMetrics.s(30),
                            online: appState.partner?.online ?? false)
            VStack(alignment: .leading, spacing: 0) {
                Text(appState.partnerName)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                headerStatus
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// True while the transcript-near Tipp-Zettel (`ChatTypingRow`) is
    /// actually on screen: the list is showing (loaded, not empty), no
    /// search filter, and the couple sits at the fold (`nearBottom` — the
    /// row lives directly above the bottom anchor). ONE typing signal at a
    /// time (Fix-Runde 3, Befund 4): only when the Zettel is out of sight
    /// does the toolbar status take over.
    var tippZettelSichtbar: Bool {
        appState.partnerTyping && !isFiltering && nearBottom
            && !model.initialLoading && !model.messages.isEmpty
    }

    @ViewBuilder private var headerStatus: some View {
        if appState.partnerTyping && !tippZettelSichtbar {
            // Typing is a partner signal — it glows in the partner's own
            // palette color, not stock pink (EVAL P1-2). Shown ONLY while
            // the transcript's own Tipp-Zettel is not visible — never both
            // at once (Fix-Runde 3, Befund 4).
            Text(L10n.t("chat.statusTyping"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(coupleTint.primary)
        } else if appState.partner?.online == true {
            Text(L10n.t("chat.online"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Licht.glut)
        } else {
            Text(L10n.t("chat.offline"))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: Trailing rail (regular width)

    /// EVAL iPad: a 640-pt conversation next to ~700 pt of emptiness. On
    /// genuinely wide panes (LayoutRules.chatUsesRail) that margin becomes
    /// the chat's own places: letters, pins and photo moments — every row
    /// only LINKS existing features (letter composer, pin jump, gallery
    /// lightbox). Compact widths never see the rail. §4.2 (S2 fix): the
    /// conversation LEADS, the board parks trailing — and an empty board
    /// (no pins, no photo moments) hugs its three link rows at the top
    /// instead of parking a window-high glass pane of placeholders.
    @ViewBuilder var chatRail: some View {
        Group {
            if railHasContent {
                ScrollView(showsIndicators: false) {
                    railInhalt
                }
                .glass(.chrome, in: RoundedRectangle(cornerRadius: Radius.pane,
                                                     style: .continuous))
            } else {
                VStack(spacing: 0) {
                    railInhalt
                        .glass(.chrome, in: RoundedRectangle(cornerRadius: Radius.pane,
                                                             style: .continuous))
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(width: CGFloat(LayoutRules.chatRailWidth))
        .padding(.trailing, Space.m)
        .padding(.vertical, Space.m)
    }

    /// The board's three sections — shared by the scrolling full board
    /// and the compact empty board.
    private var railInhalt: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            railLettersSection
            railPinnedSection
            railPhotosSection
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// True while the board carries REAL content (pins or photo moments)
    /// — otherwise it is the letters entry plus two quiet empty hints and
    /// renders compact.
    private var railHasContent: Bool {
        !railPinnedEntries.isEmpty || !railPhotoMessages.isEmpty
    }

    private func railHeading(_ text: String) -> some View {
        Text(text)
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .foregroundStyle(Theme.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }

    /// Letters entry — the same sheet the composer's envelope opens.
    private var railLettersSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            railHeading(L10n.t("chat.rail.letters"))
            Button {
                Haptics.shared.tap()
                showLetterComposer = true
            } label: {
                HStack(spacing: Space.m) {
                    Image(systemName: "envelope.fill")
                        .font(Typo.label)
                        .foregroundStyle(Licht.lampengold)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L10n.t("chat.letterA11y"))
                            .font(Typo.label)
                            .foregroundStyle(Theme.textPrimary)
                        Text(L10n.t("chat.rail.letters.hint"))
                            .font(Typo.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Space.s)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(Theme.innerFill)
                )
                .contentShape(RoundedRectangle(cornerRadius: Radius.control,
                                               style: .continuous))
            }
            .buttonStyle(.plain)
            .hoverEffect(.highlight)
        }
    }

    /// The full pin ribbon (the banner above the transcript only carries
    /// the newest pin) — tapping jumps into the conversation.
    private var railPinnedSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            railHeading(L10n.t("chat.pinnedBadge"))
            let pins = railPinnedEntries
            if pins.isEmpty {
                Text(L10n.t("chat.rail.pinned.empty"))
                    .font(Typo.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(pins) { entry in
                    railPinRow(entry)
                }
            }
        }
    }

    /// Newest pins first — the rail is a glanceable ribbon, capped small.
    private var railPinnedEntries: [PinnedMessageEntry] {
        Array(PinnedMessagesStore.shared.entries(coupleId: appState.couple?.id)
            .reversed().prefix(5))
    }

    private func railPinRow(_ entry: PinnedMessageEntry) -> some View {
        Button {
            jumpToPinned(entry.id)
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: railPinIcon(entry))
                    .font(Typo.caption)
                    .foregroundStyle(Licht.lampengold)
                    .frame(width: LayoutMetrics.s(18))
                    .accessibilityHidden(true)
                Text(railPinText(entry))
                    .font(Typo.caption)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.vertical, Space.xs)
            .padding(.horizontal, Space.s)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Theme.innerFill)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.control,
                                           style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityHint(L10n.t("chat.pinnedJumpA11y"))
    }

    private func railPinIcon(_ entry: PinnedMessageEntry) -> String {
        switch entry.kind {
        case MessageKind.voice.rawValue: return "mic.fill"
        case MessageKind.photo.rawValue: return "photo.fill"
        case MessageKind.letter.rawValue: return "envelope.fill"
        default: return "pin.fill"
        }
    }

    private func railPinText(_ entry: PinnedMessageEntry) -> String {
        switch entry.kind {
        case MessageKind.voice.rawValue:
            return L10n.t("chat.voiceMessage")
        case MessageKind.photo.rawValue:
            return entry.preview.isEmpty ? L10n.t("chat.photoMessage") : entry.preview
        case MessageKind.letter.rawValue:
            return entry.preview.isEmpty ? L10n.t("chat.letterBadge") : entry.preview
        default:
            return entry.preview
        }
    }

    /// The conversation's newest shared photos as a mini grid — each tile
    /// opens the real thing: the gallery lightbox on exactly this photo
    /// (the same path as the bubble's "view in album").
    private var railPhotosSection: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            railHeading(L10n.t("chat.rail.photos"))
            let moments = railPhotoMessages
            if moments.isEmpty {
                Text(L10n.t("chat.rail.photos.empty"))
                    .font(Typo.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: LayoutMetrics.s(72)),
                                             spacing: Space.s)],
                          spacing: Space.s) {
                    ForEach(moments) { message in
                        railPhotoTile(message)
                    }
                }
            }
        }
    }

    /// Newest photo messages first, capped to a small grid.
    private var railPhotoMessages: [Message] {
        Array(model.messages.filter { $0.type == .photo && $0.photoId != nil }
            .suffix(6).reversed())
    }

    private func railPhotoTile(_ message: Message) -> some View {
        Button {
            Haptics.shared.tap()
            if let photoId = message.photoId {
                appState.openGalleryPhoto(photoId)
            }
        } label: {
            AuthenticatedAsyncImage(api: appState.api,
                                    path: "/api/photos/\(message.photoId ?? "")/thumb/raw") { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Theme.innerFill
                }
            }
            .frame(minWidth: LayoutMetrics.s(72), minHeight: LayoutMetrics.s(72))
            .aspectRatio(1, contentMode: .fill)
            .clipShape(RoundedRectangle(cornerRadius: Radius.control,
                                        style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.control,
                                           style: .continuous))
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .accessibilityLabel(L10n.t("chat.photoShowInAlbum"))
    }
}
