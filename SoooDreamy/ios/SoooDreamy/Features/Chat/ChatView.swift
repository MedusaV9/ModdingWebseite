import SwiftUI
import Combine
import UIKit

/// Chat tab: day-grouped message list, typing indicator, input bar with
/// voice notes and love letters.
struct ChatView: View {
    @Environment(AppState.self) private var appState

    @State private var model = ChatModel()
    @State private var draft = ""
    @State private var showVoiceRecorder = false
    @State private var showLetterComposer = false
    /// My text/letter message currently being edited (drives the edit sheet).
    @State private var editingMessage: Message?
    /// Letter being forwarded — opens the composer pre-filled with its
    /// title/text so it can be sent again as a brand-new letter (v1.5.2).
    @State private var forwardingLetter: Message?
    /// Tracks whether the bottom anchor is on screen (LazyVStack keeps it
    /// alive near the fold, so this flips only after real scrolling) —
    /// drives the "jump to latest" floating button.
    @State private var nearBottom = true
    @State private var searchActive = false
    @State private var searchQuery = ""
    @FocusState private var inputFocused: Bool
    @FocusState private var searchFocused: Bool

    private static let bottomAnchorID = "chat.bottomAnchor"

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground()
                VStack(spacing: 0) {
                    header
                    searchBar
                    messageArea
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { inputBar }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            model.configure(appState)
            appState.markChatRead()
            Task { await model.loadInitial() }
        }
        .onDisappear {
            model.stopTyping()
        }
        .onChange(of: appState.servers.activeProfileID) {
            // Switching servers switches the whole couple context.
            model.reset()
            Task { await model.loadInitial() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent else { return }
            model.handle(event)
        }
        .sheet(isPresented: $showVoiceRecorder) {
            VoiceRecorderSheet { message in
                model.acceptSent(message)
            }
        }
        .sheet(isPresented: $showLetterComposer) {
            LetterComposeView { message in
                model.acceptSent(message)
            }
        }
        .sheet(item: $editingMessage) { message in
            MessageEditSheet(message: message) { newText in
                model.editMessage(message, newText: newText)
            }
        }
        .sheet(item: $forwardingLetter) { letter in
            LetterComposeView(initialTitle: letter.title ?? "",
                              initialText: letter.text ?? "") { message in
                model.acceptSent(message)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: LayoutMetrics.s(12)) {
            EmojiAvatarView(emoji: appState.partner?.avatar,
                            colorHex: appState.partner?.color,
                            size: LayoutMetrics.s(42),
                            online: appState.partner?.online ?? false)
            VStack(alignment: .leading, spacing: 1) {
                Text(appState.partnerName)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                headerStatus
            }
            Spacer()
            searchToggleButton
            ConnectionBanner(state: appState.socket.state)
        }
        .padding(.horizontal, LayoutMetrics.s(16))
        .padding(.vertical, LayoutMetrics.s(10))
    }

    // MARK: Search

    /// Trimmed query — filtering only kicks in with a non-empty search.
    private var searchText: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isFiltering: Bool {
        searchActive && !searchText.isEmpty
    }

    /// Day sections narrowed to messages matching the query (text or letter
    /// title, case-insensitive) — empty days disappear entirely.
    private var displaySections: [ChatDaySection] {
        guard isFiltering else { return model.sections }
        let query = searchText
        return model.sections.compactMap { section in
            let matches = section.messages.filter { message in
                (message.text?.localizedCaseInsensitiveContains(query) ?? false)
                    || (message.title?.localizedCaseInsensitiveContains(query) ?? false)
            }
            return matches.isEmpty ? nil : ChatDaySection(id: section.id, messages: matches)
        }
    }

    private var searchToggleButton: some View {
        Button {
            Haptics.shared.tap()
            withAnimation(.spring(response: 0.3)) {
                searchActive.toggle()
            }
            if searchActive {
                searchFocused = true
            } else {
                searchQuery = ""
            }
        } label: {
            Image(systemName: searchActive ? "xmark" : "magnifyingglass")
                .font(.scaled(13, weight: .bold))
                .foregroundStyle(searchActive ? Theme.pink : Theme.textSecondary)
                .frame(width: LayoutMetrics.s(32), height: LayoutMetrics.s(32))
                .background(
                    Circle()
                        .fill(Color.white.opacity(searchActive ? 0.14 : 0.08))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t("chat.searchA11y"))
    }

    @ViewBuilder private var searchBar: some View {
        if searchActive {
            HStack(spacing: 8) {
                TextField(L10n.t("chat.searchPlaceholder"),
                          text: $searchQuery,
                          prompt: Text(L10n.t("chat.searchPlaceholder")).foregroundStyle(Theme.textTertiary))
                    .textFieldStyle(DreamyFieldStyle())
                    .focused($searchFocused)
                    .submitLabel(.search)
                if !searchQuery.isEmpty {
                    Button {
                        Haptics.shared.tap()
                        searchQuery = ""
                        searchFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.scaled(16, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("common.delete"))
                }
            }
            .padding(.horizontal, LayoutMetrics.s(16))
            .padding(.bottom, LayoutMetrics.s(8))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var searchEmptyState: some View {
        VStack {
            Spacer()
            EmptyStateView(emoji: "🔍",
                           title: L10n.t("chat.searchNoResults.title"),
                           subtitle: L10n.t("chat.searchNoResults.subtitle", ["query": searchText]))
            Spacer()
        }
    }

    @ViewBuilder private var headerStatus: some View {
        if appState.partnerTyping {
            Text(L10n.t("chat.statusTyping"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.pink)
        } else if appState.partner?.online == true {
            Text(L10n.t("chat.online"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.mint)
        } else {
            Text(L10n.t("chat.offline"))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: Message area

    @ViewBuilder private var messageArea: some View {
        if model.initialLoading {
            LoadingView()
        } else if model.messages.isEmpty {
            emptyState
        } else if isFiltering && displaySections.isEmpty {
            searchEmptyState
        } else {
            messageList
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            EmptyStateView(emoji: "💬",
                           title: L10n.t("chat.emptyTitle"),
                           subtitle: L10n.t("chat.emptySubtitle", ["name": appState.partnerName]))
            Spacer()
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: LayoutMetrics.s(10), pinnedViews: [.sectionHeaders]) {
                    ForEach(displaySections) { section in
                        Section {
                            ForEach(section.messages) { message in
                                ChatMessageRow(message: message,
                                               isMine: message.senderId == appState.memberId,
                                               partner: appState.partner,
                                               onReact: { emoji in
                                                   model.toggleReaction(on: message, emoji: emoji)
                                               },
                                               onEdit: {
                                                   editingMessage = message
                                               },
                                               onDelete: {
                                                   model.deleteMessage(message)
                                               },
                                               onForward: {
                                                   forwardingLetter = message
                                               })
                            }
                        } header: {
                            ChatDateChip(day: section.id)
                        }
                    }
                    if appState.partnerTyping && !isFiltering {
                        ChatTypingRow(name: appState.partnerName, partner: appState.partner)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchorID)
                        .onAppear {
                            withAnimation(.spring(response: 0.3)) { nearBottom = true }
                        }
                        .onDisappear {
                            withAnimation(.spring(response: 0.3)) { nearBottom = false }
                        }
                }
                .padding(.horizontal, LayoutMetrics.s(14))
                .padding(.top, 2)
                .padding(.bottom, 6)
                .animation(.spring(response: 0.35), value: model.messages)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await model.loadOlder() }
            .overlay(alignment: .bottomTrailing) {
                if !nearBottom && !isFiltering {
                    jumpToLatestButton(proxy)
                }
            }
            .onChange(of: model.messages.last?.id) {
                // Stay put while reading history (the FAB signals the way
                // down) — unless the newest message is my own send.
                if nearBottom || model.messages.last?.senderId == appState.memberId {
                    scrollToBottom(proxy)
                }
            }
            .onChange(of: appState.partnerTyping) {
                if appState.partnerTyping && nearBottom { scrollToBottom(proxy) }
            }
            .onChange(of: inputFocused) {
                if inputFocused { scrollToBottom(proxy) }
            }
        }
    }

    /// Floating "jump to latest" button, shown while scrolled up in history.
    private func jumpToLatestButton(_ proxy: ScrollViewProxy) -> some View {
        Button {
            Haptics.shared.tap()
            scrollToBottom(proxy)
        } label: {
            Image(systemName: "chevron.down")
                .font(.scaled(15, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: LayoutMetrics.s(40), height: LayoutMetrics.s(40))
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t("chat.jumpLatest"))
        .padding(.trailing, LayoutMetrics.s(14))
        .padding(.bottom, LayoutMetrics.s(10))
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.spring(response: 0.35)) {
            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
        }
    }

    // MARK: Input bar

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            accessoryButton(icon: "envelope.fill", a11yKey: "chat.letterA11y") {
                showLetterComposer = true
            }
            accessoryButton(icon: "mic.fill", a11yKey: "chat.micA11y") {
                showVoiceRecorder = true
            }
            messageField
            sendButton
        }
        .padding(.horizontal, LayoutMetrics.s(12))
        .padding(.top, LayoutMetrics.s(10))
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private var messageField: some View {
        TextField(L10n.t("chat.inputPlaceholder"),
                  text: $draft,
                  prompt: Text(L10n.t("chat.inputPlaceholder")).foregroundStyle(Theme.textTertiary),
                  axis: .vertical)
            .lineLimit(1...5)
            .textFieldStyle(DreamyFieldStyle())
            .focused($inputFocused)
            .onChange(of: draft) {
                if draft.isEmpty {
                    model.stopTyping()
                } else {
                    model.noteTyping()
                }
            }
    }

    private var sendButton: some View {
        Button {
            sendDraft()
        } label: {
            Image(systemName: "paperplane.fill")
                .font(.scaled(16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: LayoutMetrics.s(40), height: LayoutMetrics.s(40))
                .background(
                    Circle().fill(trimmedDraft.isEmpty
                                  ? AnyShapeStyle(Color.white.opacity(0.10))
                                  : AnyShapeStyle(Theme.heroGradient))
                )
                .shadow(color: trimmedDraft.isEmpty ? .clear : Theme.pink.opacity(0.45), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(trimmedDraft.isEmpty)
        .accessibilityLabel(L10n.t("chat.sendA11y"))
        .padding(.bottom, 3)
    }

    private func accessoryButton(icon: String, a11yKey: String,
                                 action: @escaping () -> Void) -> some View {
        Button {
            Haptics.shared.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.scaled(16, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: LayoutMetrics.s(40), height: LayoutMetrics.s(40))
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t(a11yKey))
        .padding(.bottom, 3)
    }

    private func sendDraft() {
        let text = trimmedDraft
        guard !text.isEmpty else { return }
        draft = ""
        Haptics.shared.tap()
        Task {
            let ok = await model.sendText(text)
            if !ok && draft.isEmpty {
                draft = text
            }
        }
    }
}

// MARK: - Message row

struct ChatMessageRow: View {
    @Environment(AppState.self) private var appState
    let message: Message
    let isMine: Bool
    let partner: Member?
    let onReact: (String) -> Void
    /// Wired only for messages the current member may edit (their own text/letter).
    var onEdit: (() -> Void)? = nil
    /// Wired only for messages the current member may delete (their own).
    var onDelete: (() -> Void)? = nil
    /// Wired for letters — opens the composer pre-filled to send the letter
    /// again as a new one (v1.5.2).
    var onForward: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMine {
                Spacer(minLength: 44)
                bubbleColumn
            } else {
                EmojiAvatarView(emoji: partner?.avatar, colorHex: partner?.color, size: LayoutMetrics.s(28))
                bubbleColumn
                Spacer(minLength: 44)
            }
        }
        .id(message.id)
    }

    /// Delete is only offered on my own, server-confirmed messages.
    private var deleteAction: (() -> Void)? {
        guard isMine, !message.id.hasPrefix("local-") else { return nil }
        return onDelete
    }

    /// Edit is only offered on my own, server-confirmed text/letter messages
    /// (v1.8 — voice and photo messages are not editable).
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
            if !isSealedLetter {
                ChatReactionChips(message: message,
                                  myMemberId: appState.memberId,
                                  onToggle: onReact)
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
            ChatTextBubble(message: message, isMine: isMine, onReact: onReact,
                           onEdit: editAction, onDelete: deleteAction)
        case .voice:
            ChatVoiceBubble(message: message, isMine: isMine, onReact: onReact,
                            onDelete: deleteAction)
        case .letter:
            ChatLetterBubble(message: message, isMine: isMine, onReact: onReact,
                             onEdit: editAction, onDelete: deleteAction,
                             onForward: forwardAction)
        case .photo:
            ChatPhotoBubble(message: message, isMine: isMine, onReact: onReact,
                            onDelete: deleteAction)
        }
    }
}

// MARK: - Photo bubble (v1.7)

/// A shared gallery photo in the chat (`message.photoId`). Tries the photo's
/// small grid thumbnail first and falls back to the full image when there is
/// none; tapping opens a fullscreen viewer. The referenced photo has its own
/// lifetime — if it was deleted from the gallery, the media 404s and the
/// bubble shows an error placeholder.
struct ChatPhotoBubble: View {
    @Environment(AppState.self) private var appState
    let message: Message
    let isMine: Bool
    let onReact: (String) -> Void
    var onDelete: (() -> Void)? = nil

    /// Set when the thumbnail fails (e.g. none was ever uploaded) —
    /// switches the bubble to the full-resolution URL.
    @State private var thumbFailed = false
    @State private var showViewer = false

    private var side: CGFloat { LayoutMetrics.s(210) }

    private var imageURL: URL? {
        guard let api = appState.api, let photoId = message.photoId else { return nil }
        let path = thumbFailed ? "/api/photos/\(photoId)/raw" : "/api/photos/\(photoId)/thumb/raw"
        return api.mediaURL(path)
    }

    var body: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 6) {
            photoArea
            if let caption = message.text, !caption.isEmpty {
                Text(caption)
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(isMine ? .trailing : .leading)
            }
            ChatTimestampText(date: message.createdAt, isMine: isMine,
                              read: chatReadReceipt(for: message, isMine: isMine,
                                                    partner: appState.partner))
        }
        .padding(LayoutMetrics.s(8))
        .background(ChatBubbleBackground(isMine: isMine))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture(count: 2) {
            onReact(ChatReactions.quick)
        }
        .onTapGesture {
            Haptics.shared.tap()
            showViewer = true
        }
        .contextMenu {
            ChatReactMenu(onReact: onReact)
            if let onDelete {
                ChatDeleteButton(onDelete: onDelete)
            }
        }
        .accessibilityLabel(L10n.t("chat.photoMessage"))
        .fullScreenCover(isPresented: $showViewer) {
            ChatPhotoViewer(message: message)
        }
    }

    @ViewBuilder private var photoArea: some View {
        Group {
            if let url = imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        if thumbFailed {
                            photoPlaceholder(icon: "photo.badge.exclamationmark")
                        } else {
                            // No thumbnail on the server — retry with the full image.
                            photoPlaceholder(icon: nil)
                                .onAppear { thumbFailed = true }
                        }
                    default:
                        photoPlaceholder(icon: nil)
                    }
                }
            } else {
                photoPlaceholder(icon: "photo")
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func photoPlaceholder(icon: String?) -> some View {
        ZStack {
            LinearGradient(colors: [Theme.purple.opacity(0.25), Theme.indigo.opacity(0.2)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if let icon {
                Image(systemName: icon)
                    .font(.scaled(26))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                ProgressView()
                    .tint(Theme.textTertiary)
            }
        }
    }
}

/// Fullscreen viewer for one photo message (full-resolution image + caption).
struct ChatPhotoViewer: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let message: Message

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            imageArea
            VStack {
                HStack {
                    closeButton
                    Spacer()
                }
                .padding(.horizontal, LayoutMetrics.s(16))
                .padding(.top, 8)
                Spacer()
                if let caption = message.text, !caption.isEmpty {
                    Text(caption)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(LayoutMetrics.s(14))
                        .glassCard(padding: 12)
                        .padding(.horizontal, LayoutMetrics.s(16))
                        .padding(.bottom, LayoutMetrics.s(24))
                }
            }
        }
    }

    @ViewBuilder private var imageArea: some View {
        if let photoId = message.photoId,
           let url = appState.api?.mediaURL("/api/photos/\(photoId)/raw") {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                case .failure:
                    failurePlaceholder
                default:
                    ProgressView()
                        .tint(.white)
                }
            }
        } else {
            failurePlaceholder
        }
    }

    private var failurePlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.scaled(40))
                .foregroundStyle(Theme.textTertiary)
            Text(L10n.t("chat.photoFailed"))
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var closeButton: some View {
        Button {
            Haptics.shared.tap()
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.scaled(15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: LayoutMetrics.s(38), height: LayoutMetrics.s(38))
                .background(Circle().fill(Color.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t("chat.readerClose"))
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

/// WhatsApp-style checkmarks: one = sent, two (mint) = read by the partner.
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
        .font(.scaled(9, weight: .bold))
        .foregroundStyle(read ? Theme.mint : Color.white.opacity(0.65))
        .padding(.trailing, read ? LayoutMetrics.s(4) : 0)
        .accessibilityLabel(L10n.t(read ? "chat.receipt.read" : "chat.receipt.sent"))
    }
}

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

// MARK: - Message edit sheet (v1.8)

/// Small sheet for rewriting one of MY text/letter messages. Saving PATCHes
/// the server, which sets `editedAt` and echoes `message_updated`.
struct MessageEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let message: Message
    let onSave: (String) -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    private var trimmed: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Saving is only enabled for a non-empty text that actually changed.
    private var canSave: Bool {
        !trimmed.isEmpty && trimmed != (message.text ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                VStack(alignment: .leading, spacing: LayoutMetrics.s(12)) {
                    TextField(L10n.t("chat.inputPlaceholder"),
                              text: $draft,
                              prompt: Text(L10n.t("chat.inputPlaceholder")).foregroundStyle(Theme.textTertiary),
                              axis: .vertical)
                        .lineLimit(3...10)
                        .textFieldStyle(DreamyFieldStyle())
                        .focused($focused)
                    Text(L10n.t("chat.editHint"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                }
                .padding(LayoutMetrics.s(16))
            }
            .navigationTitle(L10n.t("chat.editTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                        .tint(Theme.pink)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("common.save")) {
                        Haptics.shared.tap()
                        dismiss()
                        onSave(draft)
                    }
                    .tint(Theme.pink)
                    .disabled(!canSave)
                }
            }
            .onAppear {
                draft = message.text ?? ""
                focused = true
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Bubble background

/// Mine: hero-gradient fill. Partner: glass card look.
struct ChatBubbleBackground: View {
    let isMine: Bool
    var cornerRadius: CGFloat = 20

    var body: some View {
        if isMine {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.heroGradient)
                .shadow(color: Theme.purple.opacity(0.30), radius: 8, y: 3)
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Theme.cardBorder, lineWidth: 1)
                )
        }
    }
}

// MARK: - Text bubble

struct ChatTextBubble: View {
    @Environment(AppState.self) private var appState
    let message: Message
    let isMine: Bool
    let onReact: (String) -> Void
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
            Text(message.text ?? "")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(isMine ? .trailing : .leading)
            ChatTimestampText(date: message.createdAt, isMine: isMine,
                              read: chatReadReceipt(for: message, isMine: isMine,
                                                    partner: appState.partner),
                              edited: message.editedAt != nil)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, LayoutMetrics.s(13))
        .background(ChatBubbleBackground(isMine: isMine))
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
            if let onEdit {
                ChatEditButton(onEdit: onEdit)
            }
            if let onDelete {
                ChatDeleteButton(onDelete: onDelete)
            }
        }
    }
}

// MARK: - Love letter bubble

struct ChatLetterBubble: View {
    @Environment(AppState.self) private var appState
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
            .animation(.easeInOut(duration: 0.65), value: unsealing)
    }

    private func unseal() {
        guard !unsealing else { return }
        unsealing = true
        celebrating = true
        Haptics.shared.success()
        SoundEngine.shared.play(.tada)
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            withAnimation(.spring(response: 0.55)) {
                OpenedLettersStore.shared.markOpened(message.id, coupleId: appState.couple?.id)
            }
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            celebrating = false
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
                Text(title)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.gold)
            }
            Text(message.text ?? "")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
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
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
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
            Text("💌")
            Text(L10n.t("chat.letterBadge"))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.gold)
        }
    }

    /// Small seal hint on own sealed letters (and on opened received ones).
    @ViewBuilder private var sealChip: some View {
        if let token = message.openWhen {
            HStack(spacing: 5) {
                Text("🔒")
                    .font(.scaled(10))
                Text(LetterSeal.sentence(for: token))
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .lineLimit(2)
            }
            .foregroundStyle(Theme.gold)
            .padding(.vertical, 4)
            .padding(.horizontal, 9)
            .background(Capsule().fill(Theme.gold.opacity(0.14)))
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

    private var letterBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(
                LinearGradient(colors: [Theme.purple.opacity(isMine ? 0.55 : 0.30),
                                        Theme.pink.opacity(isMine ? 0.45 : 0.22)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Theme.gold.opacity(0.55), lineWidth: 1.5)
            )
            .shadow(color: Theme.gold.opacity(0.20), radius: 10, y: 4)
    }
}

// MARK: - Timestamp

struct ChatTimestampText: View {
    let date: Date
    let isMine: Bool
    /// Read receipt next to the time — nil hides the checkmarks entirely.
    var read: Bool? = nil
    /// Shows a small "(edited)" hint before the time (v1.8).
    var edited: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if edited {
                Text(L10n.t("chat.edited"))
                    .font(.system(.caption2, design: .rounded).italic())
                    .foregroundStyle(isMine ? Color.white.opacity(0.6) : Theme.textTertiary)
            }
            Text(date.formatted(date: .omitted, time: .shortened))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(isMine ? Color.white.opacity(0.72) : Theme.textTertiary)
            if let read {
                ChatReadReceiptMark(read: read)
            }
        }
    }
}

// MARK: - Date chip (sticky section header)

struct ChatDateChip: View {
    let day: Date

    private var label: String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return L10n.t("chat.today") }
        if cal.isDateInYesterday(day) { return L10n.t("chat.yesterday") }
        return day.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        Text(label)
            .font(.system(.caption2, design: .rounded).weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.vertical, 5)
            .padding(.horizontal, LayoutMetrics.s(12))
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.35))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
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
                ChatTypingDots()
                Text(L10n.t("chat.typing", ["name": name]))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
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
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    let wave = max(0, sin(t * 5.2 - Double(i) * 0.85))
                    Circle()
                        .fill(Theme.textSecondary)
                        .frame(width: 6, height: 6)
                        .offset(y: -4 * CGFloat(wave))
                        .opacity(0.45 + 0.55 * wave)
                }
            }
        }
    }
}

// MARK: - Reactions

/// The fixed reaction palette; double-tap sends the quick heart.
enum ChatReactions {
    static let palette = ["❤️", "😂", "😮", "🥺", "🔥", "👍"]
    static let quick = "❤️"
}

/// "Reagieren …" submenu for bubble context menus.
struct ChatReactMenu: View {
    let onReact: (String) -> Void

    var body: some View {
        Menu {
            ForEach(ChatReactions.palette, id: \.self) { emoji in
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

/// Capsule chips under a bubble showing existing reactions;
/// tapping a chip toggles that emoji for me.
struct ChatReactionChips: View {
    let message: Message
    let myMemberId: String?
    let onToggle: (String) -> Void

    private struct Entry: Identifiable {
        let emoji: String
        let count: Int
        let mine: Bool
        var id: String { emoji }
    }

    private var entries: [Entry] {
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
                Entry(emoji: emoji,
                      count: ids.count,
                      mine: myMemberId.map { ids.contains($0) } ?? false)
            }
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

    private func chip(_ entry: Entry) -> some View {
        Button {
            onToggle(entry.emoji)
        } label: {
            HStack(spacing: 3) {
                Text(entry.emoji)
                    .font(.scaled(12))
                if entry.count > 1 {
                    Text("\(entry.count)")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(entry.mine ? Theme.pink : Theme.textSecondary)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 7)
            .background(
                Capsule()
                    .fill(entry.mine ? Theme.pink.opacity(0.22) : Color.white.opacity(0.08))
                    .overlay(
                        Capsule().strokeBorder(entry.mine ? Theme.pink.opacity(0.8) : Color.white.opacity(0.14),
                                               lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t("chat.reactWith", ["emoji": entry.emoji]))
    }
}
