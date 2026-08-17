import SwiftUI
import Combine

// MARK: - Gemeinsame Listen 📝
//
// Shopping, movies, travel ideas … every mutation is broadcast as
// `list_added` / `list_updated` (whole list) / `list_deleted`, so both
// phones stay in sync while ticking things off together.

struct SharedListsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint

    @State private var lists: [SharedList] = []
    @State private var loading = true
    @State private var loadFailed = false
    @State private var newName = ""
    @State private var newEmoji = ""
    @State private var creating = false
    @State private var deleteCandidate: SharedList?

    private static let emojis = ["🛒", "🎬", "✈️", "🎁", "🍽️", "🏡", "🎵", "📚"]

    var body: some View {
        ZStack {
            DreamyBackground(showStars: false)
            content
        }
        .navigationTitle(L10n.t("lists.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent else { return }
            handleServerEvent(event)
        }
        .confirmationDialog(L10n.t("lists.deleteConfirm"),
                            isPresented: Binding(get: { deleteCandidate != nil },
                                                 set: { if !$0 { deleteCandidate = nil } }),
                            titleVisibility: .visible) {
            Button(L10n.t("common.delete"), role: .destructive) {
                if let list = deleteCandidate {
                    delete(list)
                }
            }
        }
    }

    /// Loading / content / empty / offline / failed — the shared precedence
    /// table, so a failed fetch shows an honest retry state instead of a
    /// screen that merely LOOKS empty (PolishAudit pattern).
    private var phase: SurfacePhase {
        SurfaceState.resolve(
            loading: loading,
            hasContent: !lists.isEmpty,
            connected: appState.socket.state == .connected,
            requestFailed: loadFailed
        )
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ScrollView {
                VStack(spacing: Space.l) {
                    PaperSkeleton(kind: .card(height: 110), onNacht: true)
                    ForEach(0..<3, id: \.self) { _ in
                        PaperSkeleton(kind: .card(height: 72), onNacht: true)
                    }
                }
                .padding(Space.l)
            }
        case .failed:
            StateNoticeView(kind: .failed,
                            title: L10n.t("lists.failed.title"),
                            message: L10n.t("lists.failed.message")) {
                Task { await load() }
            }
        case .offline:
            StateNoticeView(kind: .offline,
                            title: L10n.t("lists.offline.title"),
                            message: L10n.t("lists.offline.message")) {
                Task { await load() }
            }
        case .content, .empty:
            ScrollView {
                VStack(spacing: Space.l) {
                    composeCard
                    if lists.isEmpty {
                        EmptyStateView(systemImage: "checklist",
                                       title: L10n.t("lists.empty.title"),
                                       subtitle: L10n.t("lists.empty.subtitle"))
                            .padding(.top, Space.xxl)
                    } else {
                        ForEach(lists) { list in
                            NavigationLink {
                                SharedListDetailView(listId: list.id, lists: $lists)
                            } label: {
                                listRow(list)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(Space.l)
            }
        }
    }

    // MARK: Compose

    private var composeCard: some View {
        VStack(spacing: Space.m) {
            HStack(spacing: Space.s) {
                ForEach(Self.emojis, id: \.self) { emoji in
                    Button {
                        Haptics.shared.tap()
                        newEmoji = newEmoji == emoji ? "" : emoji
                    } label: {
                        Text(emoji)
                            .font(.system(.title3))
                            .frame(width: LayoutMetrics.s(36), height: LayoutMetrics.s(36))
                            .background(
                                // Inner wells ON the night card are aufNacht
                                // washes with a naht hairline — never a
                                // second material.
                                Circle().fill(newEmoji == emoji
                                              ? coupleTint.blend.opacity(0.16)
                                              : Papier.nachtInnenFill)
                            )
                            .overlay(
                                Circle().strokeBorder(newEmoji == emoji
                                                      ? coupleTint.blend : Nacht.naht,
                                                      lineWidth: newEmoji == emoji
                                                      ? 1.5 : Theme.hairlineWidth)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(newEmoji == emoji ? [.isSelected] : [])
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: Space.m) {
                TextField(L10n.t("lists.new.placeholder"), text: $newName)
                    .textFieldStyle(DreamyFieldStyle())
                    .submitLabel(.done)
                    .onSubmit { create() }
                Button {
                    create()
                } label: {
                    if creating {
                        BusySpinner(tint: Theme.onHero)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(.body, design: .rounded).weight(.bold))
                            .foregroundStyle(Theme.onHero)
                    }
                }
                .frame(width: LayoutMetrics.s(46), height: LayoutMetrics.s(46))
                // Computed ink + platter: white read only 2.94:1 on the
                // static brand gradient (Schlussrunde 5).
                .background(Theme.heroPlatter(in: Circle()))
                .disabled(creating || newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .nightCard()
    }

    private func create() {
        guard let api = appState.api, !creating else { return }
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        creating = true
        Task {
            do {
                let list = try await api.addSharedList(name: name,
                                                       emoji: newEmoji.isEmpty ? nil : newEmoji)
                upsert(list)
                newName = ""
                newEmoji = ""
                SoundEngine.shared.play(.pop)
                Haptics.shared.success()
            } catch {
                appState.handleAPIError(error)
            }
            creating = false
        }
    }

    // MARK: Rows

    /// One list as a night card on the desk — name in aufNacht, the
    /// "all done" state glowing in lamp gold (success speaks lampengold
    /// on night).
    private func listRow(_ list: SharedList) -> some View {
        HStack(spacing: Space.m) {
            Text(list.emoji ?? "📝")
                .font(.system(.title))
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(list.name)
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                    .lineLimit(1)
                Text(teaser(for: list))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(list.items.isEmpty || list.openCount > 0
                                     ? Nacht.sekundaer : Licht.lampengold)
            }
            Spacer()
            if !list.items.isEmpty {
                ListProgressRing(done: list.items.count - list.openCount,
                                 total: list.items.count)
            }
            Image(systemName: "chevron.right")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Nacht.tertiaer)
        }
        .nightCard()
        .contextMenu {
            Button(role: .destructive) {
                deleteCandidate = list
            } label: {
                Label(L10n.t("common.delete"), systemImage: "trash")
            }
        }
    }

    private func teaser(for list: SharedList) -> String {
        if list.items.isEmpty { return L10n.t("lists.itemsEmpty") }
        if list.openCount == 0 { return L10n.t("lists.allDone") }
        return L10n.t("lists.itemsOpen", ["open": String(list.openCount),
                                          "total": String(list.items.count)])
    }

    // MARK: Data

    private func load() async {
        guard let api = appState.api else { return }
        loading = lists.isEmpty
        do {
            lists = try await api.sharedLists()
            loadFailed = false
        } catch {
            // A dead transport while the socket is down is the offline
            // state, not a broken screen (device-manager rule).
            if case APIError.transport = error, appState.socket.state != .connected {
                loadFailed = false
            } else {
                loadFailed = true
            }
        }
        loading = false
    }

    private func upsert(_ list: SharedList) {
        if let idx = lists.firstIndex(where: { $0.id == list.id }) {
            lists[idx] = list
        } else {
            lists.insert(list, at: 0)
        }
    }

    private func delete(_ list: SharedList) {
        guard let api = appState.api else { return }
        Task {
            do {
                try await api.deleteSharedList(id: list.id)
                lists.removeAll { $0.id == list.id }
                Haptics.shared.tap()
            } catch {
                appState.handleAPIError(error)
            }
        }
    }

    private func handleServerEvent(_ event: ServerEvent) {
        switch event.type {
        case .listAdded, .listUpdated:
            if let list = event.decode(SharedListResponse.self)?.list {
                upsert(list)
            }
        case .listDeleted:
            if let payload = event.decode(IdPayload.self) {
                lists.removeAll { $0.id == payload.id }
            }
        case .welcome:
            // Socket (re)connected — list fanouts eaten by the gap never
            // return; reload wholesale while mounted (welcome catch-up).
            Task { await load() }
        default:
            break
        }
    }
}

// MARK: - Progress ring

/// Native `Gauge` under the hood (system semantics + VoiceOver value from
/// the done/total range); the paper-ring painting lives in the style below.
private struct ListProgressRing: View {
    @Environment(\.coupleTint) private var coupleTint

    let done: Int
    let total: Int

    var body: some View {
        Gauge(value: Double(done), in: 0...Double(max(total, 1))) {
            Text(L10n.t("lists.section.done"))
        } currentValueLabel: {
            Text("\(done)")
        }
        .gaugeStyle(ListPaperRingGaugeStyle(tint: coupleTint.blend))
        .frame(width: 30, height: 30)
        .animation(Theme.Motion.settle, value: done)
    }
}

/// The old hand-built ring, verbatim as a `GaugeStyle`: naht track, the
/// couple's blend as arc (non-text), done-count in night secondary at
/// the center — the ring rides the night list row now.
private struct ListPaperRingGaugeStyle: GaugeStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Circle()
                .stroke(Nacht.naht, lineWidth: 4)
            Circle()
                .trim(from: 0, to: configuration.value)
                // Shape-level rotation: the ring starts at 12 o'clock —
                // geometry, not paper motion.
                .rotation(.degrees(-90))
                .stroke(tint,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
            configuration.currentValueLabel
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(Nacht.sekundaer)
                .monospacedDigit()
        }
    }
}

// MARK: - Detail (one list, checkable items)

struct SharedListDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint

    let listId: String
    @Binding var lists: [SharedList]

    @State private var newItemText = ""
    @State private var adding = false
    @State private var showRename = false
    @State private var renameText = ""

    private var list: SharedList? {
        lists.first { $0.id == listId }
    }

    var body: some View {
        ZStack {
            DreamyBackground(showStars: false)
            if let list {
                ScrollView {
                    VStack(spacing: Space.l) {
                        addItemCard
                        itemsCard(list)
                    }
                    .padding(Space.l)
                }
            }
        }
        .navigationTitle("\(list?.emoji ?? "📝") \(list?.name ?? "")")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    renameText = list?.name ?? ""
                    showRename = true
                } label: {
                    Image(systemName: "pencil")
                }
            }
        }
        .alert(L10n.t("lists.rename.title"), isPresented: $showRename) {
            TextField(L10n.t("lists.new.placeholder"), text: $renameText)
            Button(L10n.t("common.save")) { rename() }
            Button(L10n.t("common.cancel"), role: .cancel) {}
        }
        .onChange(of: list == nil) { _, gone in
            // The partner deleted this list while we had it open.
            if gone { dismiss() }
        }
    }

    // MARK: Add item

    private var addItemCard: some View {
        HStack(spacing: Space.m) {
            TextField(L10n.t("lists.item.placeholder"), text: $newItemText)
                .textFieldStyle(DreamyFieldStyle())
                .submitLabel(.done)
                .onSubmit { addItem() }
            Button {
                addItem()
            } label: {
                if adding {
                    BusySpinner(tint: Theme.onHero)
                } else {
                    Image(systemName: "plus")
                        .font(.system(.body, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.onHero)
                }
            }
            .frame(width: LayoutMetrics.s(46), height: LayoutMetrics.s(46))
            // Computed ink + platter (Schlussrunde 5).
            .background(Theme.heroPlatter(in: Circle()))
            .disabled(adding || newItemText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .nightCard()
    }

    private func addItem() {
        guard let api = appState.api, !adding else { return }
        let text = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        adding = true
        Task {
            do {
                let updated = try await api.addListItem(listId: listId, text: text)
                upsert(updated)
                newItemText = ""
                SoundEngine.shared.play(.click)
                Haptics.shared.tap()
            } catch {
                appState.handleAPIError(error)
            }
            adding = false
        }
    }

    // MARK: Items

    @ViewBuilder
    private func itemsCard(_ list: SharedList) -> some View {
        let open = list.items.filter { !$0.done }
        let done = list.items.filter(\.done)
        if list.items.isEmpty {
            EmptyStateView(systemImage: "checklist",
                           title: L10n.t("lists.itemsEmpty"),
                           subtitle: L10n.t("lists.item.placeholder"))
                .padding(.top, Space.xl)
        } else {
            // The shopping Zettel: one sheet of letter paper, torn off at
            // the bottom (the screen's single torn edge), items ticked
            // with ink hooks.
            VStack(alignment: .leading, spacing: Space.m) {
                if !open.isEmpty {
                    sectionLabel(L10n.t("lists.section.open"), count: open.count)
                    ForEach(open) { item in
                        itemRow(item)
                    }
                }
                if !done.isEmpty {
                    sectionLabel(L10n.t("lists.section.done"), count: done.count)
                        .padding(.top, open.isEmpty ? 0 : Space.s)
                    ForEach(done) { item in
                        itemRow(item)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.l)
            // Torn edges keep their safety distance to the text block.
            .padding(.bottom, Space.m)
            .background(
                TornEdgeShape(seed: memoriesPaperSeed(listId), edge: .bottom)
                    .fill(Papier.brief)
                    .overlay(
                        TornEdgeShape(seed: memoriesPaperSeed(listId), edge: .bottom)
                            .stroke(PaperLightEdge.gradient,
                                    lineWidth: Theme.hairlineWidth))
                    .elevation(.resting)
            )
        }
    }

    private func sectionLabel(_ text: String, count: Int) -> some View {
        Text("\(text) · \(count)")
            .font(.system(.caption, design: .rounded).weight(.bold))
            .foregroundStyle(Tinte.tertiaer)
    }

    /// One line of the shopping Zettel — the checkbox is an ink hook in
    /// the couple's shared ink, done lines fade to tertiary ink.
    private func itemRow(_ item: SharedListItem) -> some View {
        HStack(spacing: Space.m) {
            Button {
                toggle(item)
            } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(.title3))
                    .foregroundStyle(item.done ? coupleTint.tinte : Tinte.tertiaer)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.text)
            .accessibilityValue(item.done
                                ? L10n.t("lists.section.done")
                                : L10n.t("lists.section.open"))
            Text(item.text)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(item.done ? Tinte.tertiaer : Tinte.dunkel)
                .strikethrough(item.done, color: Tinte.tertiaer)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                deleteItem(item)
            } label: {
                Image(systemName: "trash")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Tinte.tertiaer)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("common.delete"))
        }
        .padding(.vertical, Space.xs)
        .contentShape(Rectangle())
        .onTapGesture { toggle(item) }
    }

    // MARK: Mutations

    private func upsert(_ updated: SharedList) {
        if let idx = lists.firstIndex(where: { $0.id == updated.id }) {
            lists[idx] = updated
        } else {
            lists.insert(updated, at: 0)
        }
    }

    private func toggle(_ item: SharedListItem) {
        guard let api = appState.api else { return }
        let newDone = !item.done
        Task {
            do {
                let updated = try await api.setListItemDone(listId: listId, itemId: item.id,
                                                            done: newDone, ifRev: list?.rev)
                upsert(updated)
                if newDone {
                    SoundEngine.shared.play(.success)
                    Haptics.shared.success()
                    if updated.openCount == 0 {
                        SoundEngine.shared.play(.tada)
                    }
                } else {
                    Haptics.shared.tap()
                }
            } catch {
                handleMutationError(error)
            }
        }
    }

    private func deleteItem(_ item: SharedListItem) {
        guard let api = appState.api else { return }
        Task {
            do {
                try await api.deleteListItem(listId: listId, itemId: item.id)
                if let idx = lists.firstIndex(where: { $0.id == listId }) {
                    lists[idx].items.removeAll { $0.id == item.id }
                }
                Haptics.shared.tap()
            } catch {
                appState.handleAPIError(error)
            }
        }
    }

    private func rename() {
        guard let api = appState.api else { return }
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let list, name != list.name else { return }
        Task {
            do {
                // Contract v11: only the changed field travels (the emoji
                // stays untouched server-side), guarded by the list's rev.
                let updated = try await api.renameSharedList(id: list.id, name: name,
                                                             ifRev: list.rev)
                upsert(updated)
                Haptics.shared.success()
            } catch {
                handleMutationError(error)
            }
        }
    }

    /// 409 `conflict {current}` on a rev-guarded mutation: the list changed
    /// on the other device first. Adopt the server's current version and
    /// say so honestly — the tap/rename can then be repeated against fresh
    /// truth. No silent overwrite in either direction.
    private func handleMutationError(_ error: Error) {
        guard (error as? APIError)?.serverCode == "conflict" else {
            appState.handleAPIError(error)
            return
        }
        if let current = (error as? APIError)?.details?
            .currentResource(SharedList.self) {
            upsert(current)
        }
        // Without typed details the next `list_updated` fanout converges
        // the row — the hint alone keeps the moment honest.
        appState.showToast(L10n.t("lists.conflict"), style: .info)
        Haptics.shared.warning()
    }
}
