import SwiftUI
import Combine

/// Shared couple bucket list — dreams to fulfill together.
struct BucketListView: View {
    @Environment(AppState.self) private var appState

    @State private var items: [BucketItem] = []
    @State private var loading = true
    @State private var newText = ""
    @State private var selectedEmoji = ""
    @State private var showEmojiPicker = false
    @State private var adding = false
    @State private var celebrationDate: Date?
    @State private var celebrationTask: Task<Void, Never>?

    private static let emojis = [
        "🌍", "✈️", "🏝️", "🎢", "🌌", "🏔️", "💃", "🍣",
        "🎡", "🛶", "🐘", "🌅", "🎪", "🏕️", "🚐", "💍"
    ]

    var body: some View {
        ZStack {
            DreamyBackground(showStars: false)
            content
            if let started = celebrationDate {
                FloatingHeartsView(emojis: ["✨", "🌠", "💜", "🎉", "💫"], count: 16, startedAt: started)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle(L10n.t("memories.bucket.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadItems() }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent else { return }
            handleServerEvent(event)
        }
    }

    private var openItems: [BucketItem] {
        items.filter { !$0.done }
    }

    private var doneItems: [BucketItem] {
        items.filter { $0.done }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if loading {
            LoadingView()
        } else {
            list
        }
    }

    private var list: some View {
        List {
            headerRows
            if items.isEmpty {
                emptyRow
            }
            if !openItems.isEmpty {
                Section {
                    ForEach(openItems) { item in
                        row(item)
                    }
                } header: {
                    SectionHeader(title: L10n.t("memories.bucket.openSection"))
                }
            }
            if !doneItems.isEmpty {
                Section {
                    ForEach(doneItems) { item in
                        row(item)
                    }
                } header: {
                    SectionHeader(title: L10n.t("memories.bucket.doneSection"))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 10)
        .refreshable { await loadItems() }
    }

    @ViewBuilder
    private var headerRows: some View {
        Group {
            progressCard
            addCard
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    private var emptyRow: some View {
        EmptyStateView(emoji: "🌠",
                       title: L10n.t("memories.bucket.empty.title"),
                       subtitle: L10n.t("memories.bucket.empty.subtitle"))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    // MARK: Progress header

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
            Text(progressText)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            progressBar
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var progressText: String {
        guard !items.isEmpty else { return L10n.t("memories.bucket.progressEmpty") }
        return L10n.t("memories.bucket.progress",
                      ["done": String(doneItems.count), "total": String(items.count)])
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [Theme.purple, Theme.pink],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * progressRatio)
                    .animation(.spring(response: 0.6), value: progressRatio)
            }
        }
        .frame(height: 10)
    }

    private var progressRatio: CGFloat {
        guard !items.isEmpty else { return 0 }
        return CGFloat(doneItems.count) / CGFloat(items.count)
    }

    // MARK: Add card

    private var addCard: some View {
        VStack(spacing: LayoutMetrics.s(10)) {
            HStack(spacing: LayoutMetrics.s(10)) {
                emojiButton
                TextField(L10n.t("memories.bucket.placeholder"), text: $newText)
                    .textFieldStyle(DreamyFieldStyle())
                    .submitLabel(.done)
                    .onSubmit { addItem() }
                addButton
            }
            if showEmojiPicker {
                EmojiPickerGrid(emojis: Self.emojis, selection: $selectedEmoji)
                    .onChange(of: selectedEmoji) { _, _ in
                        withAnimation(.spring(response: 0.3)) { showEmojiPicker = false }
                    }
            }
        }
        .glassCard(padding: 12)
    }

    private var emojiButton: some View {
        Button {
            Haptics.shared.tap()
            withAnimation(.spring(response: 0.3)) { showEmojiPicker.toggle() }
        } label: {
            Text(selectedEmoji.isEmpty ? "🌟" : selectedEmoji)
                .font(.scaled(22))
                .frame(width: LayoutMetrics.s(44), height: LayoutMetrics.s(44))
                .background(
                    Circle().fill(selectedEmoji.isEmpty ? Color.white.opacity(0.07) : Theme.purple.opacity(0.3))
                )
                .overlay(
                    Circle().strokeBorder(showEmojiPicker ? Theme.pink : Color.white.opacity(0.12), lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t("memories.bucket.pickEmoji"))
    }

    private var addButton: some View {
        Button {
            addItem()
        } label: {
            if adding {
                ProgressView()
                    .tint(.white)
                    .frame(width: LayoutMetrics.s(44), height: LayoutMetrics.s(44))
            } else {
                Image(systemName: "plus")
                    .font(.scaled(18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: LayoutMetrics.s(44), height: LayoutMetrics.s(44))
                    .background(Circle().fill(Theme.heroGradient))
            }
        }
        .buttonStyle(.plain)
        .disabled(adding || newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityLabel(L10n.t("common.add"))
    }

    // MARK: Row

    private func row(_ item: BucketItem) -> some View {
        HStack(spacing: LayoutMetrics.s(12)) {
            checkbox(item)
            VStack(alignment: .leading, spacing: 2) {
                Text(rowTitle(item))
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(item.done ? Theme.textTertiary : Theme.textPrimary)
                    .strikethrough(item.done, color: Theme.textTertiary)
                if item.done, let doneAt = item.doneAt {
                    Text(doneAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .glassCard(padding: 12)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteItem(item)
            } label: {
                Label(L10n.t("common.delete"), systemImage: "trash")
            }
        }
    }

    private func rowTitle(_ item: BucketItem) -> String {
        if let emoji = item.emoji, !emoji.isEmpty {
            return "\(emoji) \(item.text)"
        }
        return item.text
    }

    private func checkbox(_ item: BucketItem) -> some View {
        Button {
            toggle(item)
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(item.done ? Theme.mint : Color.white.opacity(0.3), lineWidth: 2)
                    .background(Circle().fill(item.done ? Theme.mint.opacity(0.25) : Color.clear))
                    .frame(width: LayoutMetrics.s(32), height: LayoutMetrics.s(32))
                if item.done {
                    Image(systemName: "checkmark")
                        .font(.scaled(14, weight: .heavy))
                        .foregroundStyle(Theme.mint)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func loadItems() async {
        guard let api = appState.api else { return }
        do {
            items = try await api.bucket()
        } catch {
            appState.handleAPIError(error)
        }
        loading = false
    }

    private func addItem() {
        let text = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let api = appState.api, !adding else { return }
        adding = true
        Haptics.shared.tap()
        let emoji = selectedEmoji.isEmpty ? nil : selectedEmoji
        Task {
            do {
                let item = try await api.addBucketItem(text: text, emoji: emoji)
                insert(item)
                newText = ""
                selectedEmoji = ""
                SoundEngine.shared.play(.pop)
            } catch {
                appState.handleAPIError(error)
            }
            adding = false
        }
    }

    private func toggle(_ item: BucketItem) {
        guard let api = appState.api else { return }
        let newDone = !item.done
        Haptics.shared.tap()
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].done = newDone
            items[idx].doneAt = newDone ? Date() : nil
        }
        if newDone { celebrateDone() }
        Task {
            do {
                let updated = try await api.updateBucketItem(id: item.id, done: newDone)
                apply(updated)
            } catch {
                if let idx = items.firstIndex(where: { $0.id == item.id }) {
                    items[idx].done = item.done
                    items[idx].doneAt = item.doneAt
                }
                appState.handleAPIError(error)
            }
        }
    }

    private func deleteItem(_ item: BucketItem) {
        guard let api = appState.api else { return }
        items.removeAll { $0.id == item.id }
        Task {
            do {
                try await api.deleteBucketItem(id: item.id)
            } catch {
                insert(item)
                appState.handleAPIError(error)
            }
        }
    }

    private func celebrateDone() {
        SoundEngine.shared.play(.tada)
        Haptics.shared.success()
        appState.showToast(L10n.t("memories.bucket.completed"), style: .love)
        celebrationDate = Date()
        celebrationTask?.cancel()
        celebrationTask = Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if !Task.isCancelled { celebrationDate = nil }
        }
    }

    // MARK: Realtime

    private func insert(_ item: BucketItem) {
        guard !items.contains(where: { $0.id == item.id }) else { return }
        items.append(item)
    }

    private func apply(_ item: BucketItem) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = item
        } else {
            items.append(item)
        }
    }

    private func handleServerEvent(_ event: ServerEvent) {
        switch event.type {
        case .bucketAdded:
            if let item = event.decode(BucketItemResponse.self)?.item {
                insert(item)
            }
        case .bucketUpdated:
            if let item = event.decode(BucketItemResponse.self)?.item {
                apply(item)
            }
        case .bucketDeleted:
            if let id = event.decode(IdPayload.self)?.id {
                items.removeAll { $0.id == id }
            }
        default:
            break
        }
    }
}
