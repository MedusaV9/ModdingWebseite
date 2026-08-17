import SwiftUI
import Combine
import UIKit

// Die Schreibstube nach ENTSCHEID §4.2 — Brett → Spindel → Pult. Diese
// Datei hält nur noch den gemeinsamen Zustand und die Komposition; die
// Zonen leben in fokussierten Nachbardateien (N3-Zerlegung):
//   ChatKopf.swift     — Toolbar-Identität + iPad-Rail (Brett)
//   ChatSpindel.swift  — Transkript, Suche, Zustände, Scroll, Drag&Drop
//   ChatPult.swift     — Eingabeleiste, Drafts, Senden, Siegelpresse
//   ChatZettel.swift   — Zettel-Reihe, Papier-Hintergrund, Spindelstich
//   ChatTextZettel/ChatBriefe/ChatFotoZettel/ChatReaktionen — Zettelarten
//   MessageEditSheet.swift — Bearbeiten-Sheet
// Verhalten, a11y-IDs (`chat.*`) und die `.searchable`-Naht sind identisch.

/// Chat tab: day-grouped message list, typing indicator, input bar with
/// voice notes and love letters.
struct ChatView: View {
    @Environment(AppState.self) var appState
    @Environment(\.coupleTint) var coupleTint
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State var model = ChatModel()
    @State var draft = ""
    @State var showVoiceRecorder = false
    @State var showLetterComposer = false
    @State var showStickerWorkshop = false
    @State var selectedEffect: MessageEffect?
    /// Debounces the per-profile draft mirror (~0.5 s after the last edit).
    @State var draftSaveTask: Task<Void, Never>?
    /// Profile the composer content currently belongs to — the active id has
    /// already flipped by the time the profile-switch `onChange` fires, so
    /// flushing the old draft needs its own memory.
    @State var composerProfileID: String?
    /// Recently sent stickers — quick re-send straight from the wand menu.
    @State var recentStickers: [StickerRecipe] = []
    /// Effect being previewed right after picking it in the menu (Nr. 26) —
    /// what "Wumms" does should be visible before the cooldown-limited send.
    @State var previewedEffect: MessageEffect?
    @State var effectPreviewTask: Task<Void, Never>?
    /// My text/letter message currently being edited (drives the edit sheet).
    @State var editingMessage: Message?
    /// Letter being forwarded — opens the composer pre-filled with its
    /// title/text so it can be sent again as a brand-new letter.
    @State var forwardingLetter: Message?
    /// Tracks whether the bottom anchor is on screen (LazyVStack keeps it
    /// alive near the fold, so this flips only after real scrolling) —
    /// drives the "jump to latest" floating button.
    @State var nearBottom = true
    /// Query of the NATIVE `.searchable` field (FullRelease R1-A) — the
    /// hand-built search capsule and its header toggle are gone; the
    /// filter below is driven by this text alone.
    @State var searchQuery = ""
    /// UI-test seam: pins the search drawer visible (see `.searchable`).
    static let uiTestSearchAlways = ProcessInfo.processInfo.arguments
        .contains("-SoooDreamyUITestSearchAlways")
    /// Message id the pinned banner asked to scroll to — consumed
    /// by the message list's ScrollViewReader, then reset to nil.
    @State var pinnedJumpTarget: String?
    /// Bumped only for sends that SPEAK heart (explicit heart effect or
    /// heart content, re-eval 2 Befund 5) — fires the little heart burst
    /// on the send button and lets its paperplane bounce. Everyday sends
    /// stay quiet: Legen + Stich + Tick.
    @State var sendBurst = 0
    /// An image drag hovers over the conversation (iPad drag & drop).
    @State var dropTargeted = false
    /// Legen entrance (N2-A): message-id → stagger slot for the newest
    /// Zettel, captured ONCE when the transcript first renders. Cleared
    /// after the landing so recycled LazyVStack rows never replay it.
    @State var legenSlots: [String: Int] = [:]
    @State var legenArmed = false
    /// Signature „Spindelstich" (ENTSCHEID §4.2): armed in the send frame,
    /// marks the freshly landed own Zettel with the 6-pt ink dot, then
    /// disarms after its moment (see `ChatPult.armSpindelstich`).
    @State var spindelstichArmed = false
    @State var spindelstichTask: Task<Void, Never>?
    /// Mirror of this layout pass' `useRail` for the zone extensions:
    /// banner, transcript and Pult widen to the thread column
    /// (`ChatThreadSpalte`) next to the trailing rail without threading a
    /// parameter through every zone file.
    @State var railAktiv = false
    /// Chosen Siegelpresse destination — drives the bundled entry sheet.
    @State var siegelpresseZiel: ChatSiegelpresseZiel?
    /// The Siegelpresse explains itself exactly once (heart-hint pattern)
    /// — afterwards the seal glyph simply presses. Marked done on the
    /// FIRST display (re-eval 2, Befund 4): one visit gets the hint,
    /// every later visit starts without it.
    @AppStorage("chat.siegelpresseHintDone") var siegelpresseHintDone = false
    /// Session-local visibility of that one first showing: the hint stays
    /// readable for THIS visit even though the persistent flag already
    /// says "seen"; interaction (press used / waved away) hides it early.
    @State var siegelpresseHintSichtbar = false
    @FocusState var inputFocused: Bool

    static let bottomAnchorID = "chat.bottomAnchor"

    var body: some View {
        NavigationStack {
            // Live-resize safe: the pane width is re-read every layout
            // pass, so dragging a Stage-Manager window across the rail
            // threshold swaps layouts mid-flight (same pattern as the
            // canvas' side rail).
            GeometryReader { geo in
                // AX text sizes collapse the rail (FXD-2 #4): giant type
                // needs the full pane for the conversation, and the fixed
                // 300-pt rail would truncate every row it holds. Nothing is
                // lost — the rail only LINKS existing features.
                let useRail = LayoutRules.chatUsesRail(
                    paneWidth: Double(geo.size.width),
                    isRegularWidth: horizontalSizeClass == .regular)
                    && !AccessibilityBudget.sideChromeCollapses(
                        accessibilityText: dynamicTypeSize.isAccessibilitySize)
                ZStack {
                    DreamyBackground()
                    // §4.2: the CONVERSATION leads — the rail is secondary
                    // chrome and parks trailing (S2 fix: it sat leading,
                    // pushing the thread off its resting edge).
                    // Fix-Runde 3, Befund 12 (iPad-Komposition): column and
                    // board are capped and centered as ONE ensemble — the
                    // rail aligns to the thread column instead of parking
                    // at the far window edge with a dead gap between them.
                    HStack(spacing: 0) {
                        conversationPane
                            .frame(maxWidth: .infinity)
                        if useRail {
                            chatRail
                        }
                    }
                    .frame(maxWidth: useRail ? ChatThreadSpalte.ensemble : .infinity)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: useRail, initial: true) { _, newValue in
                    railAktiv = newValue
                }
                // Roadmap 19: images dropped onto the conversation (from Photos,
                // Files, Split-View neighbors) ride the existing photo path —
                // upload into the shared gallery, then a photo message. No new
                // server endpoints.
                .dropDestination(for: Data.self) { payloads, _ in
                    sendDroppedImages(payloads)
                } isTargeted: { over in
                    withAnimation(Theme.Motion.settle) { dropTargeted = over }
                }
                .overlay { dropHint }
                .overlay {
                    if let effect = previewedEffect {
                        MessageEffectOverlay(effect: effect)
                            .transition(.opacity)
                    }
                }
                // One shared translation task for every bubble — the system
                // language-pack sheet anchors to the visible conversation.
                .chatTranslationHost()
            }
            // FullRelease R1-A (Nativität): the transcript search is the
            // SYSTEM search field now — presentation, focus, cancel and
            // VoiceOver come from the platform; iOS 26 minimizes it into
            // a toolbar button until the couple actually searches. The
            // filter wiring below (`displaySections`) is unchanged.
            // UI-test seam (same pattern as the ScreenshotSeed flags): the
            // minimized system button is SDK-owned chrome XCUITest cannot
            // address reliably (runs 31903489346/31906140012) — the flag
            // pins the drawer field visible so tests drive REAL search.
            .searchable(text: $searchQuery,
                        placement: ChatView.uiTestSearchAlways
                            ? .navigationBarDrawer(displayMode: .always)
                            : .automatic,
                        prompt: Text(L10n.t("chat.searchPlaceholder")))
            .searchToolbarBehavior(ChatView.uiTestSearchAlways ? .automatic : .minimize)
            // R3 (Nativität-Final-Eval S2): the hidden navigation bar left
            // the minimized search field without a host — unreachable. The
            // chat identity now lives IN the real toolbar (principal item,
            // the Messages pattern), help and connection ride trailing, and
            // the system bar hosts the search chrome. Background stays
            // hidden so the sepia room breathes through; the bar's scroll
            // edge effect keeps the items legible.
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) { toolbarIdentity }
                ToolbarItem(placement: .topBarTrailing) {
                    HandbookButton(anchor: "chat", style: .toolbar)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ConnectionBanner(state: connectionState)
                }
            }
        }
        .onAppear {
            model.configure(appState)
            appState.markChatRead()
            restoreComposerDraft()
            stageComposerScreenshot()
            VoiceTranscriptCenter.shared.configure(coupleId: appState.couple?.id)
            Task { await model.loadInitial() }
        }
        .onDisappear {
            model.stopTyping()
            flushComposerDraft()
        }
        .onChange(of: draft) {
            scheduleDraftSave()
        }
        .onChange(of: selectedEffect) {
            if let profileID = composerProfileID {
                ChatComposerDrafts.save(effect: selectedEffect, profileID: profileID)
            }
        }
        .onChange(of: scenePhase) {
            // Multitasking hardening (roadmap 20): leaving the foreground
            // flushes the debounced draft immediately — a Stage-Manager
            // window swap or an app kill inside the 0.5 s debounce window
            // must never eat a half-written message.
            if scenePhase != .active { flushComposerDraft() }
        }
        .onChange(of: appState.servers.activeProfileID) {
            // Switching servers switches the whole couple context — the
            // composer must never carry a text into the other couple,
            // and neither may a cached translation.
            model.reset()
            ChatTranslationCenter.shared.reset()
            flushComposerDraft()
            restoreComposerDraft()
            Task { await model.loadInitial() }
        }
        .onChange(of: appState.couple?.id) {
            // The transcript cache is couple-scoped — rebind when the
            // couple context (re)loads.
            VoiceTranscriptCenter.shared.configure(coupleId: appState.couple?.id)
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
        .sheet(isPresented: $showStickerWorkshop) {
            StickerWorkshopSheet { recipe in
                sendSticker(recipe)
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
        .sheet(item: $siegelpresseZiel) { ziel in
            siegelpresseSheet(for: ziel)
        }
    }

    // MARK: Conversation pane (Brett → Spindel → Pult)

    /// Header, transcript and composer — the composer bar is attached HERE
    /// (not to the whole window), so on rail widths it centers over the
    /// conversation column, never over rail + column. A real BAR (not a
    /// plain inset): the conversation scrolls through underneath the
    /// floating composer with the system's soft scroll-edge treatment, and
    /// the keyboard avoidance stays the system's job.
    private var conversationPane: some View {
        VStack(spacing: 0) {
            if !isFiltering {
                ChatPinnedBanner(messages: model.messages) { messageId in
                    jumpToPinned(messageId)
                }
                .chatThreadColumn(railAktiv: railAktiv)
            }
            messageArea
        }
        .safeAreaBar(edge: .bottom, spacing: 0) { inputBar }
    }
}

// MARK: - Thread column (Eval 6 + Fix-Runde 3, Befund 12)

/// Local column measure of the Schreibstube (Theme is not station
/// property): WITHOUT the rail the conversation keeps the house reading
/// column; NEXT TO the 300-pt trailing rail the thread stays a DIALOGUE
/// column of ~700 pt — wide enough for two voices, narrow enough that my
/// bubbles (right) and the partner's (left) still talk to each other
/// instead of clinging to opposite window edges around a dead hole.
enum ChatThreadSpalte {
    /// Measure beside the rail — a composed dialogue column (bubbles keep
    /// their own 44-pt opposite-side clearance) in the 680–720 band, not
    /// the pane's entire remainder.
    static let breit: CGFloat = 700
    /// The full composition on rail widths: thread column + board rail
    /// (incl. its trailing breath) — centered as ONE ensemble so the rail
    /// aligns to the conversation, never to the far window edge.
    static var ensemble: CGFloat {
        breit + CGFloat(LayoutRules.chatRailWidth) + Space.m
    }
}

/// Banner, transcript and Pult share exactly ONE measure, anchored at the
/// Pult: whatever width the composer takes, the thread above takes too.
/// The trailing flexible frame is the `contentColumn` mechanic — it
/// CENTERS the capped column inside whatever pane it sits in.
private struct ChatThreadColumnModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let railAktiv: Bool

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: horizontalSizeClass == .regular
                ? (railAktiv ? ChatThreadSpalte.breit : ColumnWidth.reading.max)
                : .infinity)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    /// The Schreibstube's shared conversation column — reading width
    /// standalone, `ChatThreadSpalte.breit` beside the trailing rail.
    func chatThreadColumn(railAktiv: Bool) -> some View {
        modifier(ChatThreadColumnModifier(railAktiv: railAktiv))
    }
}
