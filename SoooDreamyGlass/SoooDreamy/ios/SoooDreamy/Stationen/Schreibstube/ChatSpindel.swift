import SwiftUI
import UIKit

// Zone „Spindel" — der Zettelwechsel: Tagesabschnitte, Suche, die vier
// ehrlichen Zustände, Legen-Einzug, Scroll-Mechanik und Drag&Drop.
// Reiner Struktur-Umzug aus ChatView.swift (N3-Zerlegung, ENTSCHEID
// §4.2); `defaultScrollAnchor(.bottom)` und der Bottom-Anchor bleiben
// wörtlich erhalten (test03-Naht).

extension ChatView {

    // MARK: Search

    /// Trimmed query — filtering only kicks in with a non-empty search.
    var searchText: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isFiltering: Bool {
        !searchText.isEmpty
    }

    /// Day sections narrowed to messages matching the query (text or letter
    /// title, case-insensitive) — empty days disappear entirely.
    var displaySections: [ChatDaySection] {
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

    var searchEmptyState: some View {
        VStack {
            Spacer()
            EmptyStateView(systemImage: "magnifyingglass",
                           title: L10n.t("chat.searchNoResults.title"),
                           subtitle: L10n.t("chat.searchNoResults.subtitle", ["query": searchText]),
                           actionTitle: L10n.t("common.clearSearch"),
                           action: {
                               Haptics.shared.tap()
                               searchQuery = ""
                           })
            Spacer()
        }
    }

    // MARK: Message area

    @ViewBuilder var messageArea: some View {
        if model.initialLoading {
            LoadingView()
        } else if model.messages.isEmpty && model.loadFailed {
            // A failed history load must not LOOK like an empty chat —
            // the shared precedence table separates offline from broken.
            loadFailedState
        } else if model.messages.isEmpty {
            emptyState
        } else if isFiltering && displaySections.isEmpty {
            searchEmptyState
        } else {
            messageList
        }
    }

    private var loadFailedState: some View {
        VStack {
            Spacer()
            // A dead transport while the socket is down is the offline
            // story; anything else is an honest "couldn't load" + retry.
            if appState.socket.state != .connected {
                StateNoticeView(kind: .offline,
                                title: L10n.t("chat.history.offline.title"),
                                message: L10n.t("chat.history.offline.message")) {
                    Task { await model.loadInitial() }
                }
            } else {
                StateNoticeView(kind: .failed,
                                title: L10n.t("chat.history.failed.title"),
                                message: L10n.t("chat.history.failed.message")) {
                    Task { await model.loadInitial() }
                }
            }
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            EmptyStateView(systemImage: "bubble.left.and.bubble.right",
                           title: L10n.t("chat.emptyTitle"),
                           subtitle: L10n.t("chat.emptySubtitle", ["name": appState.partnerName]),
                           actionTitle: L10n.t("chat.empty.action"),
                           action: {
                               Haptics.shared.tap()
                               inputFocused = true
                           })
            Spacer()
        }
    }

    var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Tight base rhythm: grouped bubbles of one sender sit almost
                // together; every group START adds a Space.s breath on top —
                // the conversation reads in voices, not in single lines.
                LazyVStack(spacing: LayoutMetrics.s(2), pinnedViews: [.sectionHeaders]) {
                    ForEach(displaySections) { section in
                        Section {
                            let messages = section.messages
                            // Row identity = `chatRowID` (ChatVersoehnung):
                            // keyed by the clientMessageId where one exists,
                            // so the local→server id swap of an ACK is a
                            // value UPDATE of the same row — never a
                            // remount, never a second Spindelstich/Legen.
                            ForEach(Array(messages.enumerated()),
                                    id: \.element.chatRowID) { index, message in
                                let position = ChatGroupPosition(
                                    isStart: index == 0
                                        || !chatGroupChains(messages[index - 1], message),
                                    isEnd: index == messages.count - 1
                                        || !chatGroupChains(message, messages[index + 1]))
                                ChatMessageRow(message: message,
                                               isMine: message.senderId == appState.memberId,
                                               partner: appState.partner,
                                               group: position,
                                               // Spindelstich (§4.2): the dot marks
                                               // EXACTLY the Zettel that was JUST
                                               // spindled — the model follows its id
                                               // through the local→server swap, so an
                                               // incoming Zettel can never steal the
                                               // mark (S2 fix: not `messages.last`).
                                               spindled: spindelstichArmed
                                                   && message.senderId == appState.memberId
                                                   && message.id == model.spindelstichID,
                                               onReact: { emoji in
                                                   ChatReactionRecents.record(emoji)
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
                                    // P2-B density polish: a full Space.m
                                    // breath between voice groups — more
                                    // ZIMMER between the paper stacks.
                                    .padding(.top, position.isStart ? Space.m : 0)
                                    // Legen (N2-A): the newest Zettel land on
                                    // the desk when the chat opens — and a
                                    // freshly SENT Zettel lands through its
                                    // one-time slot from the optimistic
                                    // insert (S2 fix: sends were mounting
                                    // without the scale/Y landing). Slots are
                                    // keyed by the STABLE row id, so the ACK
                                    // id swap can't orphan a landing mid-play.
                                    .modifier(ChatLegenEntrance(slot: legenSlots[message.chatRowID]
                                        ?? (message.chatRowID == model.sendLegenID ? 0 : nil)))
                            }
                        } header: {
                            ChatDateChip(day: section.id)
                        }
                    }
                    if appState.partnerTyping && !isFiltering {
                        ChatTypingRow(name: appState.partnerName, partner: appState.partner)
                            .padding(.top, Space.s)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(ChatView.bottomAnchorID)
                        .onAppear {
                            withAnimation(reduceMotion ? nil : Theme.Motion.settle) {
                                nearBottom = true
                            }
                        }
                        .onDisappear {
                            withAnimation(reduceMotion ? nil : Theme.Motion.settle) {
                                nearBottom = false
                            }
                        }
                }
                .padding(.horizontal, LayoutMetrics.s(14))
                .padding(.top, 2)
                .padding(.bottom, 6)
                // Readable conversation column: bubbles never span a full
                // iPad window — the dialogue stays a dialogue, not a
                // table. Beside the trailing rail the column widens to the
                // thread measure (Eval 6), anchored at the Pult below.
                .chatThreadColumn(railAktiv: railAktiv)
                // Insert/remove animation of the list, bound to the ROW-id
                // set (not the message VALUES): a server ACK swaps ids but
                // keeps every `chatRowID`, so it can no longer re-animate
                // the whole list (re-eval 2, Befund 1). Reduce Motion drops
                // the slide entirely — rows appear in place (Befund 2).
                .animation(reduceMotion ? nil : Theme.Motion.settle,
                           value: model.messages.map(\.chatRowID))
                // Glitch-Pass (P2-B): the typing row declares a transition,
                // but `partnerTyping` flips from the socket handler with no
                // withAnimation — without a bound driver the Zettel popped
                // in/out instead of sliding. One driver, same curve; none
                // under Reduce Motion.
                .animation(reduceMotion ? nil : Theme.Motion.settle,
                           value: appState.partnerTyping)
            }
            .defaultScrollAnchor(.bottom)
            .onAppear(perform: armLegenEntrance)
            .scrollDismissesKeyboard(.interactively)
            // Only the glass-edge BREATH here, not the full chrome
            // clearance: the composer safeAreaBar already reserves the
            // accessory/tab-bar space — this keeps the resting bubble
            // out of the composer glass' refraction band without
            // double-padding.
            .contentMargins(.bottom, LayoutMetrics.glassEdgeBreath,
                            for: .scrollContent)
            // Soft edge under the floating composer/dock: bubbles blur and
            // dim INTO the bar instead of cutting off hard. `.soft` (not
            // `.hard`) is the deliberate choice over the aurora — a hard
            // line would slice the night sky.
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .refreshable { await model.loadOlder() }
            .overlay(alignment: .bottomTrailing) {
                if !nearBottom && !isFiltering {
                    jumpToLatestButton(proxy)
                }
            }
            .onChange(of: model.messages.last?.chatRowID) {
                // Stay put while reading history (the FAB signals the way
                // down) — unless the newest message is my own send.
                // Observed on the STABLE row id (Fix-Runde 3, S2): the
                // ACK's local→server id swap keeps the chatRowID, so it no
                // longer fires a second scroll on the same send.
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
            .onChange(of: pinnedJumpTarget) {
                guard let target = pinnedJumpTarget else { return }
                // Reduce Motion: jump to the pinned bubble without the ride.
                withAnimation(reduceMotion ? nil : Theme.Motion.arrive) {
                    proxy.scrollTo(target, anchor: .center)
                }
                pinnedJumpTarget = nil
            }
        }
    }

    /// Arms the Legen entrance exactly once per chat visit: the newest
    /// `legenBudget` messages (chronological — the newest Zettel lands
    /// last) get their stagger slots; after the landing window the map is
    /// cleared so recycled rows and incoming sends render untouched.
    private func armLegenEntrance() {
        guard !legenArmed, !isFiltering else { return }
        legenArmed = true
        let budget = Theme.Motion.Signature.legenBudget
        let newest = model.messages.suffix(budget)
        // Keyed by the stable row id so a pending Zettel that gets ACKed
        // mid-landing keeps its slot through the id swap.
        legenSlots = Dictionary(uniqueKeysWithValues:
            newest.enumerated().map { ($0.element.chatRowID, $0.offset) })
        Task {
            // Full stagger plus a generous settle beat — then the map is
            // gone and the entrance can never replay on scroll recycle.
            let window = Double(budget) * Theme.Motion.Signature.legenStagger + 1.0
            try? await Task.sleep(for: .seconds(window))
            legenSlots = [:]
        }
    }

    /// Banner tap: scroll to the pinned bubble when it's in the loaded
    /// window, otherwise explain how to reach it (pull-to-refresh loads
    /// older pages). Pins store SERVER ids — the jump target maps onto
    /// the row's `chatRowID`, the id the transcript rows actually carry
    /// (Fix-Runde 3, S2).
    func jumpToPinned(_ messageId: String) {
        Haptics.shared.tap()
        if let message = model.messages.first(where: { $0.id == messageId }) {
            pinnedJumpTarget = message.chatRowID
        } else {
            appState.showToast(L10n.t("chat.pinnedNotLoaded"), style: .info)
        }
    }

    /// Floating "jump to latest" button, shown while scrolled up in history.
    /// System `.glass` button style (wave-2 adoption): platter, springy
    /// press response and the accessibility degradation all come from the
    /// system — nothing hand-rolled. Layout-safe here because the button
    /// floats in an overlay corner.
    private func jumpToLatestButton(_ proxy: ScrollViewProxy) -> some View {
        Button {
            Haptics.shared.tap()
            scrollToBottom(proxy)
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: LayoutMetrics.s(26), height: LayoutMetrics.s(26))
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(L10n.t("chat.jumpLatest"))
        .padding(.trailing, LayoutMetrics.s(14))
        .padding(.bottom, LayoutMetrics.s(10))
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    /// Reduce Motion arrives at the bottom instantly — no animated ride
    /// down the transcript (re-eval 2, Befund 2).
    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : Theme.Motion.settle) {
            proxy.scrollTo(ChatView.bottomAnchorID, anchor: .bottom)
        }
    }

    // MARK: Drag & drop (roadmap 19)

    /// Chrome hint while an image drag hovers over the conversation.
    @ViewBuilder var dropHint: some View {
        if dropTargeted {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.pane, style: .continuous)
                    .strokeBorder(coupleTint.blend.opacity(0.7), lineWidth: 2)
                    .padding(LayoutMetrics.s(10))
                Label(L10n.t("chat.drop.hint"), systemImage: "photo.badge.arrow.down")
                    .font(Typo.label)
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.vertical, Space.s)
                    .padding(.horizontal, Space.l)
                    .glass(.chrome, in: Capsule())
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    /// Accepts dropped image data: each image rides the EXISTING photo
    /// path — upload into the shared gallery, best-effort thumbnail, then
    /// a photo message into the conversation.
    func sendDroppedImages(_ payloads: [Data]) -> Bool {
        guard appState.api != nil, !payloads.isEmpty else { return false }
        Haptics.shared.tap()
        appState.showToast(L10n.t("chat.drop.sending"), style: .info)
        Task { await uploadDroppedImages(payloads) }
        return true
    }

    private func uploadDroppedImages(_ payloads: [Data]) async {
        guard let api = appState.api else { return }
        var sentAny = false
        for data in payloads {
            guard let image = BoundedImageDecoder.image(data: data, maxPixelSize: 2_048),
                  let jpeg = image.jpegData(compressionQuality: 0.85) else {
                appState.showToast(L10n.t("chat.drop.unreadable"), style: .error)
                continue
            }
            do {
                let photo = try await api.uploadPhoto(jpeg: jpeg, caption: nil,
                                                      width: Int(image.size.width),
                                                      height: Int(image.size.height),
                                                      takenAt: BoundedImageDecoder.takenAt(data: data))
                let thumb = GalleryView.downscaled(image, maxDimension: 320)
                if let thumbJpeg = thumb.jpegData(compressionQuality: 0.7) {
                    do {
                        _ = try await api.uploadPhotoThumb(photoId: photo.id, jpeg: thumbJpeg)
                    } catch {
                        // Thumbnail is best effort — the bubble falls back
                        // to the full image.
                    }
                }
                let message = try await api.sendPhotoMessage(photoId: photo.id)
                model.acceptSent(message)
                sentAny = true
            } catch {
                appState.handleAPIError(error)
            }
        }
        if sentAny {
            // Pop + success haptic are the drop's feedback; the heart burst
            // is reserved for heart sends (Kitsch budget, Befund 5).
            SoundEngine.shared.play(.pop)
            Haptics.shared.success()
        }
    }
}
