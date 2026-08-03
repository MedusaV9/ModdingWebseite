import SwiftUI
import Combine

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
                                               partner: appState.partner)
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
    let message: Message
    let isMine: Bool
    let partner: Member?

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMine {
                Spacer(minLength: 44)
                bubble
            } else {
                EmojiAvatarView(emoji: partner?.avatar, colorHex: partner?.color, size: 28)
                bubble
                Spacer(minLength: 44)
            }
        }
        .id(message.id)
    }

    @ViewBuilder private var bubble: some View {
        switch message.type {
        case .text:
            ChatTextBubble(message: message, isMine: isMine)
        case .voice:
            ChatVoiceBubble(message: message, isMine: isMine)
        case .letter:
            ChatLetterBubble(message: message, isMine: isMine)
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
    let message: Message
    let isMine: Bool

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
    }
}

// MARK: - Love letter bubble

struct ChatLetterBubble: View {
    let message: Message
    let isMine: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            badge
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
    }

    private var badge: some View {
        HStack(spacing: 6) {
            Text("💌")
            Text(L10n.t("chat.letterBadge"))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.gold)
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
