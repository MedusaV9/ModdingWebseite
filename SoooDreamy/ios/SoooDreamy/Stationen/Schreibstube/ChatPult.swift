import SwiftUI
import UIKit

// Zone „Pult" (ENTSCHEID §4.2) — die Eingabeleiste als Chrome-Glas-Cluster
// mit den drei nativen Toolbar-Einstiegen: Rohrpost (`waveform`) ·
// Briefpapier (`square.and.pencil`) · Siegelpresse-Menü (`seal`, bündelt
// Zeitpost/Kapsel/Türchen — die Ziel-Sheets existieren, hier liegen nur die
// Einstiege). Composer-Verhalten (Draft-Persistenz, Effekte, Senden,
// `chat.composer`/`chat.send`-IDs) unverändert aus ChatView.swift gezogen.

/// Composer draft + armed effect per server profile: a text typed for
/// partner A must never surface in couple context B, and a process kill
/// must not eat a half-written message.
enum ChatComposerDrafts {
    private static func draftKey(_ profileID: String) -> String {
        "sooodreamy.chatDraft.\(profileID)"
    }

    private static func effectKey(_ profileID: String) -> String {
        "sooodreamy.chatEffect.selected.\(profileID)"
    }

    static func loadDraft(profileID: String) -> String {
        UserDefaults.standard.string(forKey: draftKey(profileID)) ?? ""
    }

    static func loadEffect(profileID: String) -> MessageEffect? {
        UserDefaults.standard.string(forKey: effectKey(profileID))
            .flatMap(MessageEffect.init(rawValue:))
    }

    static func save(draft: String, profileID: String) {
        if draft.isEmpty {
            UserDefaults.standard.removeObject(forKey: draftKey(profileID))
        } else {
            UserDefaults.standard.set(draft, forKey: draftKey(profileID))
        }
    }

    static func save(effect: MessageEffect?, profileID: String) {
        if let effect {
            UserDefaults.standard.set(effect.rawValue, forKey: effectKey(profileID))
        } else {
            UserDefaults.standard.removeObject(forKey: effectKey(profileID))
        }
    }
}

/// The couple-wide 12-s effect cooldown, readable at any time so the UI can
/// show honest remaining seconds instead of silently dropping the effect.
enum MessageEffectCooldown {
    private static let key = "sooodreamy.chatEffect.lastSent"

    static func remainingSeconds(now: Date = Date()) -> Int {
        guard let last = UserDefaults.standard.object(forKey: key) as? Date else { return 0 }
        let remaining = MessageEffectPolicy.cooldown - now.timeIntervalSince(last)
        return remaining > 0 ? Int(remaining.rounded(.up)) : 0
    }

    static func canSend(now: Date = Date()) -> Bool {
        MessageEffectPolicy.canSend(
            lastSentAt: UserDefaults.standard.object(forKey: key) as? Date,
            now: now
        )
    }

    static func markSent(now: Date = Date()) {
        UserDefaults.standard.set(now, forKey: key)
    }
}

/// Signature „Spindelstich" (ENTSCHEID §4.2), lokale Parameter — Theme
/// gehört nicht zur N3-Hoheit, die Werte leben deshalb bei der Station.
enum ChatSpindelstich {
    /// The 6-pt ink dot on the top edge of the freshly spindled Zettel.
    static let punktDurchmesser: CGFloat = 6
    /// Soft → rigid double haptic in the send frame: the `.sent` breath of
    /// air first, then the dry stitch of the spindle pin. Rides the ONE
    /// cue lane via `hapticOverride` — scheduling and quiet hours stay
    /// exactly the `.sent` cue's (still exactly one feedback per send).
    static let haptik = [
        HapticEventSpec(t: 0.00, i: 0.30, s: 0.25, d: 0.14),
        HapticEventSpec(t: 0.12, i: 0.85, s: 0.90)
    ]
    /// How long the dot stays visible after the landing (then it fades
    /// with `settle` — the spindle mark is a moment, not a badge).
    static let punktDauer: TimeInterval = 2.6
    /// The dry spindle TICK instead of the generic `.sent` swish: the
    /// `.chip` catalog cue's click sample rides as `soundOverride` on the
    /// `.sent` cue — scheduling, coalescing and quiet hours stay the
    /// `.sent` cue's, and no new asset enters the house.
    static let klang: AppCue = .chip
    /// One-time Legen window of a freshly SENT Zettel (slot 0, no
    /// stagger): the legen spring plus a settle beat, then the model
    /// clears the slot so a recycled row can never replay the landing.
    static let legenFenster: TimeInterval = 1.0
}

/// The three Siegelpresse destinations — one menu bundles the entry points
/// to sheets that already exist elsewhere in the house.
enum ChatSiegelpresseZiel: String, Identifiable {
    case zeitpost, kapsel, tuerchen
    var id: String { rawValue }
}

extension ChatView {

    // MARK: Input bar

    var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var inputBar: some View {
        // Every composer control is STANDALONE chrome glass — deliberately
        // NO `GlassGroup` around the cluster: inside a container the
        // consolidated glass pass dims the sibling foregrounds (field
        // text, accessory icons — the dock regressed exactly like that on
        // CI), and the tinted send capsule would rest at the field's
        // `Space.s` gap, permanently inside the blend distance. The old
        // full-width glass Rectangle behind the row stays gone — the
        // conversation scrolls through underneath the floating cluster
        // (soft scroll edge). See the group-usage rules on `GlassGroup`.
        VStack(spacing: Space.s) {
            siegelpresseHintRow
            effectChip
            HStack(alignment: .bottom, spacing: Space.s) {
                // ENTSCHEID §4.2 — the Pult toolbar, exactly the three
                // Pflicht items: Rohrpost · Briefpapier · Siegelpresse.
                // The wand moved INTO the field as its trailing accessory
                // (S3 fix: four abstract circles crowded the field until
                // the placeholder clipped).
                accessoryButton(icon: "waveform", a11yKey: "chat.micA11y") {
                    showVoiceRecorder = true
                }
                accessoryButton(icon: "square.and.pencil", a11yKey: "chat.letterA11y") {
                    showLetterComposer = true
                }
                siegelpresseMenu
                messageField
                if !trimmedDraft.isEmpty {
                    sendButton
                }
            }
        }
        .padding(.horizontal, LayoutMetrics.s(12))
        .padding(.top, LayoutMetrics.s(10))
        // FullRelease N1-A: the old hand-measured dock clearance died with
        // the custom dock — the native tab bar contributes a real safe-area
        // inset and manages its own keyboard relationship, so the slim
        // resting padding is all the composer needs in every state.
        .padding(.bottom, 8)
        // The controls follow the conversation column on iPad widths —
        // the Pult ANCHORS the thread measure (Eval 6): transcript and
        // banner take exactly the width the composer takes.
        .chatThreadColumn(railAktiv: railAktiv)
        // Hearts fly from where the send button lives — the overlay sits on
        // the bar so the burst survives the button's own morph-out after a
        // send clears the draft.
        .overlay(alignment: .bottomTrailing) {
            HeartBurstView(trigger: sendBurst)
                .frame(width: LayoutMetrics.s(110), height: LayoutMetrics.s(110))
        }
        // No sensoryFeedback here: the `.sent` cue in sendDraft is the ONE
        // sensory channel of a send (its haptic twin covers quiet hours).
        .animation(Theme.Motion.settle, value: selectedEffect)
        // The send button appearing/disappearing is a functional state
        // change — under Reduce Motion it switches instantly instead.
        .animation(reduceMotion ? nil : Theme.Motion.settle,
                   value: trimmedDraft.isEmpty)
        // Same rule for the one-time Siegelpresse hint leaving the Pult.
        .animation(reduceMotion ? nil : Theme.Motion.settle,
                   value: siegelpresseHintSichtbar)
        .onAppear(perform: armSiegelpresseHint)
    }

    /// The FIRST display already marks the hint as seen (re-eval 2,
    /// Befund 4): it stays readable for this one visit via the session
    /// flag, but the persistent flag flips immediately — the next visit
    /// starts without it, interaction or not.
    private func armSiegelpresseHint() {
        guard !siegelpresseHintDone else { return }
        siegelpresseHintSichtbar = true
        siegelpresseHintDone = true
    }

    /// The armed effect as a visible chip above the input field — which
    /// effect is active, whether the cooldown still runs (honest countdown)
    /// and a one-tap way out. No more silently discarded magic.
    @ViewBuilder private var effectChip: some View {
        if let effect = selectedEffect {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let remaining = MessageEffectCooldown.remainingSeconds(now: timeline.date)
                HStack(spacing: Space.s) {
                    Image(systemName: remaining > 0 ? "hourglass" : effectSystemImage(effect))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(Licht.lampengold)
                    Text(remaining > 0
                         ? L10n.t("chat.effect.chipCooldown",
                                  ["name": L10n.t("chat.effect.\(effect.rawValue)"),
                                   "s": "\(remaining)"])
                         : L10n.t("chat.effect.chipReady",
                                  ["name": L10n.t("chat.effect.\(effect.rawValue)")]))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Button {
                        Haptics.shared.tap()
                        selectedEffect = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(Theme.textTertiary)
                            // 44-pt hit frame WITHOUT inflating the chip:
                            // the shape grows outward, the glyph stays put.
                            .contentShape(Rectangle().inset(by: -14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("chat.effect.clearA11y"))
                }
                .padding(.vertical, Space.xs)
                .padding(.horizontal, Space.m)
                // Floating chip = chrome glass (the bar behind it is gone);
                // the gold ring is the effect's STATE color, same pattern
                // as the toast's tint ring — not a specular rebuild.
                .glass(.chrome, in: Capsule())
                .overlay(Capsule().strokeBorder(Licht.lampengold.opacity(0.35),
                                                lineWidth: Theme.hairlineWidth))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var messageField: some View {
        TextField(L10n.t("chat.inputPlaceholder"),
                  text: $draft,
                  prompt: Text(L10n.t("chat.inputPlaceholder")).foregroundStyle(Theme.textTertiary),
                  axis: .vertical)
            .lineLimit(1...5)
            .font(.system(.body, design: .rounded))
            .foregroundStyle(Theme.textPrimary)
            .padding(.vertical, LayoutMetrics.s(13))
            .padding(.leading, LayoutMetrics.s(16))
            // Room for the wand accessory living INSIDE the capsule —
            // typed text never runs under the glyph.
            .padding(.trailing, LayoutMetrics.s(44))
            // The floating field IS chrome now — real glass instead of the
            // matte DreamyFieldStyle well (which belongs INSIDE glass
            // cards). Standalone, so the typed text stays crisp ON the
            // glass instead of dimming under a container pass.
            .glass(.chrome, in: Capsule())
            // The wand as the field's trailing accessory (S3 fix): effects
            // and stickers decorate WHAT is being written, so their entry
            // lives in the writing field — bottom-anchored so it stays at
            // the send line while the multiline field grows upward.
            .overlay(alignment: .bottomTrailing) { effectAccessory }
            // Focus ring in the couple's shared color — a STATE tint on the
            // capsule edge (same pattern as the effect chip's gold ring),
            // not a specular glass rebuild.
            .overlay(
                Capsule().strokeBorder(
                    coupleTint.blend.opacity(inputFocused ? 0.45 : 0),
                    lineWidth: Theme.hairlineWidth)
            )
            .animation(Theme.Motion.settle, value: inputFocused)
            .focused($inputFocused)
            .accessibilityIdentifier("chat.composer")
            .onChange(of: draft) {
                if draft.isEmpty {
                    model.stopTyping()
                } else {
                    model.noteTyping()
                }
            }
    }

    /// Appears only while there is something to send. Standalone tinted
    /// glass with a plain scale/fade transition — deliberately NOT a
    /// `glassEffectID` morph out of the field: that morph needs field and
    /// button in one `GlassEffectContainer`, which dims the field's text
    /// under the consolidated glass pass (the CI-verified dock regression)
    /// and parks tinted glass permanently inside the blend distance.
    /// Readability beats the morph. The couple-blend wash on real glass
    /// stays the chat screen's ONE tinted glass surface.
    private var sendButton: some View {
        Button {
            sendDraft()
        } label: {
            Image(systemName: "paperplane.fill")
                .font(.system(.callout, design: .rounded).weight(.bold))
                // Computed foreground on the blend-tinted capsule — hard
                // white washed out on light couple blends (Kontrast II).
                .foregroundStyle(coupleTint.onBlend)
                .symbolEffect(.bounce, options: .nonRepeating, value: sendBurst)
                .frame(width: LayoutMetrics.s(40), height: LayoutMetrics.s(40))
                .glass(.tinted(coupleTint.blend), in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        // HIG minimum: the glass circle stays 40 pt, the hit frame is 44.
        .minimumHitTarget()
        // Hardware keyboard (roadmap 19): ⌘↩ sends; plain ↩ keeps making
        // new lines in the multiline field. (⌘1…5 switch tabs — see
        // MainTabView; Esc closes sheets — system behavior.)
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityLabel(L10n.t("chat.sendA11y"))
        .accessibilityIdentifier("chat.send")
        .padding(.bottom, 3)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    private var effectAccessory: some View {
        Menu {
            // A Picker inside a Menu renders native checkmarks — the
            // current choice is finally visible where it is made.
            Picker(L10n.t("chat.effect.a11y"), selection: effectSelection) {
                Label(L10n.t("chat.effect.none"), systemImage: "paperplane")
                    .tag(MessageEffect?.none)
                ForEach(MessageEffect.allCases) { effect in
                    Label(
                        L10n.t("chat.effect.\(effect.rawValue)"),
                        systemImage: effectSystemImage(effect)
                    )
                    .tag(MessageEffect?.some(effect))
                }
            }
            Divider()
            ForEach(Array(recentStickers.enumerated()), id: \.offset) { _, recipe in
                Button {
                    sendSticker(recipe)
                } label: {
                    Label(L10n.t("chat.sticker.resend",
                                 ["label": recipe.label ?? L10n.t("chat.sticker")]),
                          systemImage: "arrow.counterclockwise")
                }
            }
            Button {
                showStickerWorkshop = true
            } label: {
                Label(L10n.t("chat.sticker.workshop"), systemImage: "scribble.variable")
            }
        } label: {
            Image(systemName: selectedEffect == nil ? "wand.and.stars" : "wand.and.stars.inverse")
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(selectedEffect == nil ? Theme.textSecondary : Licht.lampengold)
                // A FIELD accessory now, not a fourth Pult circle: no own
                // glass — the glyph sits inside the field's capsule.
                .frame(width: LayoutMetrics.s(40), height: LayoutMetrics.s(46))
        }
        // HIG minimum: the visible glyph region keeps a 44-pt hit frame.
        .minimumHitTarget()
        .accessibilityLabel(L10n.t("chat.effect.a11y"))
        .padding(.trailing, LayoutMetrics.s(4))
    }

    /// One-time native Siegelpresse explanation (S3 fix) — the repo's
    /// heart-hint pattern (quiet caption + AppStorage), no new framework:
    /// a plain glass row naming what the seal glyph bundles. Shown for
    /// exactly ONE visit (`armSiegelpresseHint` marks it seen on first
    /// display); using the press or waving it away hides it early.
    @ViewBuilder private var siegelpresseHintRow: some View {
        if siegelpresseHintSichtbar {
            HStack(spacing: Space.s) {
                Image(systemName: "seal")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Licht.lampengold)
                    .accessibilityHidden(true)
                Text(L10n.t("chat.siegelpresse.hint"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Haptics.shared.tap()
                    siegelpresseHintSichtbar = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .contentShape(Rectangle().inset(by: -14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("chat.siegelpresse.hint.dismissA11y"))
            }
            .padding(.vertical, Space.xs)
            .padding(.horizontal, Space.m)
            .glass(.chrome, in: Capsule())
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func accessoryButton(icon: String, a11yKey: String,
                                 action: @escaping () -> Void) -> some View {
        Button {
            Haptics.shared.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: LayoutMetrics.s(40), height: LayoutMetrics.s(40))
                // Chrome glass instead of the hand-painted matte circle —
                // the system material handles Reduce Transparency itself.
                .glass(.chrome, in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        // HIG minimum: the glass circle stays 40 pt, the hit frame is 44.
        .minimumHitTarget()
        .accessibilityLabel(L10n.t(a11yKey))
        .padding(.bottom, 3)
    }

    // MARK: Siegelpresse (ENTSCHEID §4.2)

    /// ONE menu bundles the three time-post entries — the target sheets
    /// exist elsewhere (Zeitpost, Kapsel-Briefe, Türchen-Kalender); the
    /// Pult only presses the seal on them.
    private var siegelpresseMenu: some View {
        Menu {
            Button {
                siegelpresseHintSichtbar = false
                siegelpresseZiel = .zeitpost
            } label: {
                Label(L10n.t("chat.siegelpresse.zeitpost"), systemImage: "hourglass")
            }
            Button {
                siegelpresseHintSichtbar = false
                siegelpresseZiel = .kapsel
            } label: {
                Label(L10n.t("chat.siegelpresse.kapsel"), systemImage: "envelope.badge.fill")
            }
            Button {
                siegelpresseHintSichtbar = false
                siegelpresseZiel = .tuerchen
            } label: {
                Label(L10n.t("chat.siegelpresse.tuerchen"), systemImage: "calendar.badge.plus")
            }
        } label: {
            Image(systemName: "seal")
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: LayoutMetrics.s(40), height: LayoutMetrics.s(40))
                // Chrome glass — part of the composer's glass cluster.
                .glass(.chrome, in: Circle(), interactive: true)
        }
        // HIG minimum: the glass circle stays 40 pt, the hit frame is 44.
        .minimumHitTarget()
        .accessibilityLabel(L10n.t("chat.siegelpresse.a11y"))
        .accessibilityIdentifier("chat.siegelpresse")
        .padding(.bottom, 3)
    }

    /// The chosen Siegelpresse destination as a sheet. Zeitpost brings its
    /// own NavigationStack + Done; the two Lagerfach views are normally
    /// PUSHED (Archiv), so as sheets they get the local stack + Done chrome.
    @ViewBuilder func siegelpresseSheet(for ziel: ChatSiegelpresseZiel) -> some View {
        switch ziel {
        case .zeitpost:
            ZeitpostSheet()
        case .kapsel:
            SiegelpresseUmschlag { CapsulesView() }
        case .tuerchen:
            SiegelpresseUmschlag { SeasonCalendarView() }
        }
    }

    /// Picker binding that additionally previews a freshly chosen effect —
    /// only explicit menu picks animate, not the silent restore on appear.
    private var effectSelection: Binding<MessageEffect?> {
        Binding(
            get: { selectedEffect },
            set: { newValue in
                let isNewChoice = newValue != selectedEffect
                selectedEffect = newValue
                if isNewChoice, let newValue, newValue != .invisible {
                    startEffectPreview(newValue)
                }
            }
        )
    }

    /// Plays the fullscreen effect burst once (~1.5 s) so "Wumms" is no
    /// longer a blind purchase against the cooldown (Nr. 26).
    private func startEffectPreview(_ effect: MessageEffect) {
        effectPreviewTask?.cancel()
        withAnimation(Theme.Motion.settle) { previewedEffect = effect }
        effectPreviewTask = Task {
            do {
                try await Task.sleep(nanoseconds: 1_500_000_000)
            } catch {
                return  // superseded by a newer pick
            }
            withAnimation(Theme.Motion.settle) { previewedEffect = nil }
        }
    }

    // MARK: Draft persistence (per server profile)

    /// Rebinds the composer to the active profile and restores its saved
    /// draft, armed effect and sticker recents.
    func restoreComposerDraft() {
        draftSaveTask?.cancel()
        composerProfileID = appState.servers.activeProfileID?.uuidString
        if let profileID = composerProfileID {
            draft = ChatComposerDrafts.loadDraft(profileID: profileID)
            selectedEffect = ChatComposerDrafts.loadEffect(profileID: profileID)
        } else {
            draft = ""
            selectedEffect = nil
        }
        recentStickers = StickerRecents.load(coupleId: appState.couple?.id)
    }

    /// CI composer shot (chat mode + `-SoooDreamyScreenshotComposer`): a
    /// staged draft makes the tinted send capsule appear, and focusing the
    /// field lifts the keyboard so the floating dock steps aside
    /// (`MainTabView` hides it while typing) — the composer chrome is the
    /// shot's subject, fully exposed. A no-op for real launches.
    func stageComposerScreenshot() {
        guard let staged = ScreenshotSeed.composerDraft else { return }
        draft = staged
        Task {
            // One settle pass for the staged transcript before the focus
            // raises the keyboard.
            try? await Task.sleep(nanoseconds: 800_000_000)
            inputFocused = true
        }
    }

    /// Debounced mirror of the draft text (~0.5 s after the last keystroke)
    /// — a process kill must not eat a half-written message.
    func scheduleDraftSave() {
        guard let profileID = composerProfileID else { return }
        let text = draft
        draftSaveTask?.cancel()
        draftSaveTask = Task {
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch {
                return  // superseded by a newer keystroke
            }
            ChatComposerDrafts.save(draft: text, profileID: profileID)
        }
    }

    /// Synchronous save of draft + effect for the profile the composer is
    /// still bound to — used on disappear and right before profile switches.
    func flushComposerDraft() {
        draftSaveTask?.cancel()
        guard let profileID = composerProfileID else { return }
        ChatComposerDrafts.save(draft: draft, profileID: profileID)
        ChatComposerDrafts.save(effect: selectedEffect, profileID: profileID)
    }

    // MARK: Sending

    func sendDraft() {
        let text = trimmedDraft
        guard !text.isEmpty else { return }
        let armedEffect = selectedEffect
        let secretEffect = isAnniversarySecret(text) ? MessageEffect.fireworks : armedEffect
        let effect = allowedEffect(secretEffect)
        draft = ""
        selectedEffect = nil
        // EXACTLY ONE sensory feedback per send, in the tap frame — the
        // `.sent` cue through the CueKit lane. Spindelstich (§4.2) swaps
        // BOTH generic halves for the stitch: the soft→rigid haptic via
        // `hapticOverride` and the dry spindle tick via `soundOverride`
        // (the `.sent` swish belonged to the messenger, not the desk);
        // scheduling and quiet hours stay the `.sent` cue's.
        CueKit.play(.sent, hapticOverride: ChatSpindelstich.haptik,
                    soundOverride: ChatSpindelstich.klang)
        // Kitsch budget (re-eval 2, Befund 5 — DESIGN.md): hearts fly ONLY
        // when the send actually speaks heart — the explicit heart effect
        // or visible heart content. An everyday text lands quietly as
        // Legen + Stich + Tick.
        if effect == .hearts || ChatSendeRegeln.traegtHerz(text) {
            sendBurst += 1
        }
        armSpindelstich()
        Task {
            let ok = await model.sendText(text, effect: effect)
            if !ok {
                // Nothing was queued (no couple scope) — restore both the
                // text and the carefully chosen effect (Nr. 33).
                if draft.isEmpty { draft = text }
                if selectedEffect == nil { selectedEffect = armedEffect }
            }
        }
    }

    /// Arms the Spindelstich dot for the landing Zettel, then lets it fade
    /// after its moment — the mark belongs to the send frame, not forever.
    private func armSpindelstich() {
        spindelstichTask?.cancel()
        spindelstichArmed = true
        spindelstichTask = Task {
            do {
                try await Task.sleep(for: .seconds(ChatSpindelstich.punktDauer))
            } catch {
                return  // superseded by a newer send
            }
            withAnimation(Theme.Motion.settle) { spindelstichArmed = false }
        }
    }

    func sendSticker(_ recipe: StickerRecipe) {
        let effect = allowedEffect(selectedEffect)
        selectedEffect = nil
        StickerRecents.record(recipe, coupleId: appState.couple?.id)
        recentStickers = StickerRecents.load(coupleId: appState.couple?.id)
        Task { _ = await model.sendSticker(recipe, effect: effect) }
    }

    private func allowedEffect(_ effect: MessageEffect?) -> MessageEffect? {
        guard let effect else { return nil }
        let remaining = MessageEffectCooldown.remainingSeconds()
        guard remaining == 0 else {
            // Honest countdown instead of "not possible right now" (Nr. 35).
            appState.showToast(L10n.t("chat.effect.cooldown", ["s": "\(remaining)"]),
                               style: .info)
            return nil
        }
        MessageEffectCooldown.markSent()
        return effect
    }

    private func isAnniversarySecret(_ text: String) -> Bool {
        guard let anniversary = appState.couple?.anniversary else { return false }
        let typedDigits = text.filter(\.isNumber)
        let anniversaryDigits = anniversary.filter(\.isNumber)
        guard typedDigits.count == 8 else { return false }
        let yearFirst = anniversaryDigits
        let dayFirst = String(anniversaryDigits.suffix(2))
            + String(anniversaryDigits.dropFirst(4).prefix(2))
            + String(anniversaryDigits.prefix(4))
        return typedDigits == yearFirst || typedDigits == dayFirst
    }

    func effectSystemImage(_ effect: MessageEffect) -> String {
        switch effect {
        case .hearts: "heart.fill"
        case .snow: "snowflake"
        case .sparkle: "sparkles"
        case .fireworks: "fireworks"
        case .slam: "exclamationmark.bubble.fill"
        case .invisible: "eye.slash.fill"
        }
    }
}

// MARK: - Siegelpresse sheet chrome

/// Local sheet wrapper for destinations that are normally PUSHED (the two
/// Lagerfach views bring `.navigationTitle` but no dismiss of their own) —
/// a NavigationStack plus the standard Done button, same pattern as
/// `PostJournalSheet`.
struct SiegelpresseUmschlag<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationStack {
            content()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.t("common.done")) {
                            Haptics.shared.tap()
                            dismiss()
                        }
                        .tint(coupleTint.blend)
                    }
                }
        }
    }
}
