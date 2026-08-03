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
    @FocusState private var inputFocused: Bool

    private static let bottomAnchorID = "chat.bottomAnchor"

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground()
                VStack(spacing: 0) {
                    header
                    messageArea
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { inputBar }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            model.configure(appState)
            appState.unreadChat = 0
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
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            EmojiAvatarView(emoji: appState.partner?.avatar,
                            colorHex: appState.partner?.color,
                            size: 42,
                            online: appState.partner?.online ?? false)
            VStack(alignment: .leading, spacing: 1) {
                Text(appState.partnerName)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                headerStatus
            }
            Spacer()
            ConnectionBanner(state: appState.socket.state)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
                LazyVStack(spacing: 10, pinnedViews: [.sectionHeaders]) {
                    ForEach(model.sections) { section in
                        Section {
                            ForEach(section.messages) { message in
                                ChatMessageRow(message: message,
                                               isMine: message.senderId == appState.memberId,
                                               partner: appState.partner) { emoji in
                                    model.toggleReaction(on: message, emoji: emoji)
                                }
                            }
                        } header: {
                            ChatDateChip(day: section.id)
                        }
                    }
                    if appState.partnerTyping {
                        ChatTypingRow(name: appState.partnerName, partner: appState.partner)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchorID)
                }
                .padding(.horizontal, 14)
                .padding(.top, 2)
                .padding(.bottom, 6)
                .animation(.spring(response: 0.35), value: model.messages)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await model.loadOlder() }
            .onChange(of: model.messages.last?.id) {
                scrollToBottom(proxy)
            }
            .onChange(of: appState.partnerTyping) {
                if appState.partnerTyping { scrollToBottom(proxy) }
            }
            .onChange(of: inputFocused) {
                if inputFocused { scrollToBottom(proxy) }
            }
        }
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
        .padding(.horizontal, 12)
        .padding(.top, 10)
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
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
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
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 40, height: 40)
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

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMine {
                Spacer(minLength: 44)
                bubbleColumn
            } else {
                EmojiAvatarView(emoji: partner?.avatar, colorHex: partner?.color, size: 28)
                bubbleColumn
                Spacer(minLength: 44)
            }
        }
        .id(message.id)
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
            ChatTextBubble(message: message, isMine: isMine, onReact: onReact)
        case .voice:
            ChatVoiceBubble(message: message, isMine: isMine, onReact: onReact)
        case .letter:
            ChatLetterBubble(message: message, isMine: isMine, onReact: onReact)
        }
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

    var body: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
            Text(message.text ?? "")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(isMine ? .trailing : .leading)
            ChatTimestampText(date: message.createdAt, isMine: isMine)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 13)
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
        }
    }
}

// MARK: - Love letter bubble

struct ChatLetterBubble: View {
    @Environment(AppState.self) private var appState
    let message: Message
    let isMine: Bool
    let onReact: (String) -> Void

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
                ChatTimestampText(date: message.createdAt, isMine: isMine)
            }
        }
        .padding(15)
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
                    .font(.system(size: 10))
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

    var body: some View {
        Text(date.formatted(date: .omitted, time: .shortened))
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(isMine ? Color.white.opacity(0.72) : Theme.textTertiary)
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
            .padding(.horizontal, 12)
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
            EmojiAvatarView(emoji: partner?.avatar, colorHex: partner?.color, size: 28)
            HStack(spacing: 8) {
                ChatTypingDots()
                Text(L10n.t("chat.typing", ["name": name]))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 13)
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
                    .font(.system(size: 12))
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
