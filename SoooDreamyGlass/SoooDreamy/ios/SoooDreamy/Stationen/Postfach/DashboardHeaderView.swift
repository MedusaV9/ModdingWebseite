import SwiftUI

// The relationship header (Dossier 23, ideas 16/18), extracted from the
// old 2 300-line DashboardView (W8A component split): both avatars with
// presence glow, the shared-days line, mood and now-playing as atmosphere —
// never as another card. My own mood/presence controls live behind my
// avatar; the dashboard edit sheet behind the slider button.

struct DashboardHeaderView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    /// AX5 gate: at accessibility text sizes the header row cannot hold
    /// avatars + title + pill side by side — it stacks instead, and the
    /// title wraps freely instead of being scaled down (EVAL AX5).
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showMoodPicker = false
    @State private var showPresenceSheet = false
    /// My avatar opens mood + presence — the one place for "how am I
    /// showing up" (Dossier 23, idea 18).
    @State private var showProfileActions = false
    @State private var showDashboardEdit = false
    /// The Dienstlicht opens today's energy flow (Neubau §4.1 Kopf).
    @State private var showDienstlicht = false
    /// Partner mood line unfolded to the full note (Dossier 32, idea 23).
    @State private var moodLineExpanded = false
    /// The moodUpdatedAt stamp my "I see you" hug already answered — one
    /// soft ack per shared mood, not a button to spam.
    @State private var ackedMoodStamp: Date?

    // Same keys as DashboardView's layout storage — UserDefaults keeps the
    // edit sheet and the layout engine in sync across the two views.
    @AppStorage("dashboard.pinnedGroup") private var pinnedGroupRaw = ""
    @AppStorage("dashboard.hide.rituals") private var hideRituals = false
    @AppStorage("dashboard.hide.games") private var hideGames = false
    @AppStorage("dashboard.hide.moments") private var hideMoments = false

    /// CI screenshot runs and the in-app demo (Welle 7 [29]) have no
    /// server, so the socket would stamp a red failure pill onto the
    /// staged state. Both present the stubbed healthy connection (the demo
    /// badge names the situation); real launches always show the honest
    /// socket state.
    private var connectionState: SocketState {
        (ScreenshotMode.stagesMainUI || appState.demoActive)
            ? .connected : appState.socket.displayState
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if dynamicTypeSize.prefersVerticalLayout {
                accessibilityHeader
            } else {
                regularHeader
            }
            atmosphereLines
        }
        .padding(.top, 6)
        .sheet(isPresented: $showMoodPicker) {
            MoodPickerSheet()
        }
        .sheet(isPresented: $showPresenceSheet) {
            PresenceSheet()
        }
        .sheet(isPresented: $showDashboardEdit) {
            DashboardEditSheet(
                pinnedGroupRaw: $pinnedGroupRaw,
                hideRituals: $hideRituals,
                hideGames: $hideGames,
                hideMoments: $hideMoments
            )
        }
        .sheet(isPresented: $showDienstlicht) {
            DienstlichtSheet()
        }
        .confirmationDialog(L10n.t("home.me.menuTitle"),
                            isPresented: $showProfileActions,
                            titleVisibility: .visible) {
            Button(L10n.t("home.setMood")) { showMoodPicker = true }
            Button(L10n.t("presence.chip")) { showPresenceSheet = true }
        }
    }

    /// The regular one-row header: avatars, title/status, edit button and
    /// the connection pill share the line.
    private var regularHeader: some View {
        HStack(alignment: .center, spacing: Space.m) {
            if appState.partner != nil {
                avatarPair
            }
            VStack(alignment: .leading, spacing: 2) {
                greetingLine
                // Priority rule for tight widths: the title scales down
                // first; the status pill keeps its natural size and is
                // never truncated or wrapped (EVAL P0-1).
                titleText(compact: true)
                statusLine
            }
            Spacer()
            dienstlicht
            // FullRelease N1-A: help moved from the dock into the screen
            // headers — here it shares the row with the edit button.
            HandbookButton(anchor: "home")
            editButton
            ConnectionBanner(state: connectionState)
                .layoutPriority(1)
        }
    }

    /// AX5 header: the row unstacks — avatars + edit button first, then the
    /// title with room to WRAP (never `minimumScaleFactor`-shrunk), then
    /// status and connection each on their own line.
    private var accessibilityHeader: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .center, spacing: Space.m) {
                if appState.partner != nil {
                    avatarPair
                }
                Spacer()
                dienstlicht
                HandbookButton(anchor: "home")
                editButton
            }
            greetingLine
            titleText(compact: false)
            statusLine
            ConnectionBanner(state: connectionState)
        }
    }

    /// The greeting line (redesign wave 1, REDESIGN.md §2.1): the mailbox
    /// says hello before it counts days — morning/midday/evening from the
    /// Zustellrunde of the minute tick. Device-local hour, same honesty
    /// contract as the stamp line (ZustellrundenLogic); the LogicTests
    /// pin all three greeting keys against the PostfachL10n table.
    private var greetingLine: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let runde = Zustellrunde.from(
                hour: Calendar.current.component(.hour, from: timeline.date))
            Text(L10n.t(runde.greetingKey))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    /// "X days together" is a relationship prop — it exists only once the
    /// partner actually joined, not as soon as an anniversary date is on
    /// file (EVAL P0-2). Re-eval №10: ONE wording everywhere — the full
    /// sentence "{n} Tage zusammen" on iPhone and iPad alike. The old
    /// ViewThatFits measured the ideal width and fell back to the bare
    /// "608 Tage" almost always (device ≠ device wording). Compact rows
    /// keep the whole sentence by scaling the one line (never below 0.6);
    /// AX sizes wrap freely at full size — type never shrinks there.
    /// The now-unused short-form key stays parked in CoreStrings (Fix-C
    /// territory), noted in the handover.
    @ViewBuilder
    private func titleText(compact: Bool) -> some View {
        if appState.partner != nil, let days = appState.daysTogether, days > 0 {
            Text(L10n.t("home.daysTogether.full", ["n": String(days)]))
                .brandTitle(.system(.headline, design: .rounded).weight(.heavy))
                .lineLimit(compact ? 1 : nil)
                .minimumScaleFactor(compact ? 0.6 : 1)
                .contentTransition(.numericText())
                .animation(Theme.Motion.arrive, value: days)
        } else {
            Text("SoooDreamy")
                .brandTitle(.system(.headline, design: .rounded).weight(.heavy))
                .lineLimit(compact ? 1 : nil)
                .minimumScaleFactor(compact ? 0.7 : 1)
        }
    }

    // MARK: Dienstlicht (Neubau §4.1 Kopf)

    /// The duty light: both officers' energy as ONE lamp-glow dot —
    /// lampengold (full) → glut (low) → energyRed (empty), the weaker
    /// battery dims the lamp. Unset energy shows an UNLIT bulb outline in
    /// the ring instead of an empty circle (re-eval №11: the bare ring
    /// read as a radio button) — still honest: no light without a signal,
    /// and the a11y value says so in words. Tap opens today's energy flow
    /// — the battery moved OUT of the rituals block into the head.
    private var dienstlicht: some View {
        Button {
            Haptics.shared.tap()
            showDienstlicht = true
        } label: {
            Group {
                if let farbe = dienstlichtFarbe {
                    Circle()
                        .fill(farbe)
                        .overlay(Circle().strokeBorder(farbe, lineWidth: 1.5))
                        .frame(width: LayoutMetrics.s(12), height: LayoutMetrics.s(12))
                        // The lamp sheen — the dot GLOWS instead of growing,
                        // so the head row keeps its quiet 44-pt rhythm.
                        .shadow(color: farbe.opacity(0.7),
                                radius: LayoutMetrics.s(5))
                } else {
                    Image(systemName: "lightbulb")
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .foregroundStyle(Nacht.tertiaer)
                }
            }
            .frame(width: 44, height: 44)
            .background(Circle().fill(Theme.innerFill))
        }
        // Redesign wave 1: the chrome circle answers the finger visibly
        // (DS press response), not only through haptics.
        .buttonStyle(DSPressableStyle(compact: true))
        .accessibilityLabel(L10n.t("postfach.dienstlicht.a11y"))
        .accessibilityValue(dienstlichtA11yWert)
    }

    /// The weaker of the two set batteries carries the light's color —
    /// a couple's lamp is only as bright as the tired half. All three
    /// tones hold ≥ 3:1 against the night ground (token contract).
    private var dienstlichtFarbe: Color? {
        let levels = [appState.me?.energy?.level, appState.partner?.energy?.level]
            .compactMap { $0.flatMap(EnergyLevel.init(rawValue:)) }
        guard !levels.isEmpty else { return nil }
        if levels.contains(.red) { return Theme.energyRed }
        if levels.contains(.yellow) { return Licht.glut }
        return Licht.lampengold
    }

    /// VoiceOver reads the light as data, not decor: whose battery says
    /// what — and while neither half set an energy today, the value says
    /// exactly that instead of staying mute (honest empty state, №11).
    private var dienstlichtA11yWert: String {
        var teile: [String] = []
        if let mein = appState.me?.energy.flatMap({ EnergyLevel(rawValue: $0.level) }) {
            teile.append(L10n.t("energy.mine") + " " + L10n.t(mein.titleKey))
        }
        if let partner = appState.partner,
           let seins = partner.energy.flatMap({ EnergyLevel(rawValue: $0.level) }) {
            teile.append(L10n.t("energy.partnerLabel", ["name": partner.name])
                         + " " + L10n.t(seins.titleKey))
        }
        guard !teile.isEmpty else { return L10n.t("postfach.dienstlicht.leer") }
        return teile.joined(separator: ", ")
    }

    private var editButton: some View {
        Button {
            Haptics.shared.tap()
            showDashboardEdit = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(.footnote, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.innerFill))
        }
        .buttonStyle(DSPressableStyle(compact: true))
        .accessibilityLabel(L10n.t("dashboard.edit.title"))
    }

    /// My avatar (tap: mood + presence) leaning against the partner's —
    /// the couple is the first thing the eye lands on.
    private var avatarPair: some View {
        HStack(spacing: -LayoutMetrics.s(10)) {
            Button {
                Haptics.shared.tap()
                showProfileActions = true
            } label: {
                EmojiAvatarView(emoji: appState.me?.avatar,
                                colorHex: appState.me?.color,
                                size: LayoutMetrics.s(44))
                    .overlay(alignment: .bottomTrailing) {
                        moodBadge(appState.me?.mood,
                                  updatedAt: appState.me?.moodUpdatedAt)
                    }
                    .shadow(color: appState.myPresence != nil
                                ? PresenceStyle.color(for: appState.myPresence?.kind).opacity(0.7)
                                : .clear,
                            radius: 9)
            }
            // Redesign wave 1: every touch answers in the frame (comm. 14)
            // — the avatar breathes under the finger now.
            .buttonStyle(DSPressableStyle(compact: true))
            .accessibilityLabel(L10n.t("home.myAvatarA11y"))
            .zIndex(1)

            EmojiAvatarView(emoji: appState.partner?.avatar,
                            colorHex: appState.partner?.color,
                            size: LayoutMetrics.s(44),
                            online: appState.partner?.online ?? false)
                .overlay(alignment: .bottomTrailing) {
                    moodBadge(appState.partner?.mood,
                              updatedAt: appState.partner?.moodUpdatedAt)
                }
                // Soft status glow while the partner is in focus/sleep mode.
                .shadow(color: appState.partnerPresence != nil
                            ? PresenceStyle.color(for: appState.partnerPresence?.kind).opacity(0.75)
                            : .clear,
                        radius: 11)
                .accessibilityLabel(partnerA11y)
                // UI-test hook (P1-D list) — label behavior unchanged.
                .accessibilityIdentifier("home.partnerName")
        }
    }

    /// Tiny mood emoji floating at an avatar's corner — mood as an
    /// ambient detail instead of a pill stack. Older than a day it dims:
    /// Tuesday's mood must not look like now's (Dossier 32, idea 5).
    @ViewBuilder
    private func moodBadge(_ mood: String?, updatedAt: Date? = nil) -> some View {
        if let mood, !mood.isEmpty {
            Text(mood)
                .font(.system(.caption2))
                .padding(2)
                .background(Circle().fill(Theme.bgTop.opacity(0.85)))
                .offset(x: 4, y: 4)
                .opacity(moodIsStale(updatedAt) ? 0.5 : 1)
                .accessibilityHidden(true)
        }
    }

    /// A mood older than a day is memory, not presence.
    private func moodIsStale(_ updatedAt: Date?) -> Bool {
        guard let updatedAt else { return false }
        return Date().timeIntervalSince(updatedAt) > 24 * 3600
    }

    /// One quiet line under the shared-days counter: the partner's mode
    /// outranks online/offline; next the upcoming event as a footnote.
    /// AX composition (re-eval №9): at accessibility sizes the footnote
    /// condenses to the bare countdown — the grown head must not eat the
    /// first screen, and type NEVER shrinks to make room.
    @ViewBuilder
    private var statusLine: some View {
        if let presence = appState.partnerPresence {
            PartnerPresencePill(presence: presence)
        } else if let next = appState.nextEvent {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.system(.caption2).weight(.semibold))
                Text(dynamicTypeSize.isAccessibilitySize
                        ? nextEventCountdown(days: next.days)
                        : "\(next.event.title) · " + nextEventCountdown(days: next.days))
                    .lineLimit(1)
            }
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(next.days <= 1 ? Theme.gold : Theme.textSecondary)
            .contentShape(Rectangle())
            .onTapGesture { appState.activeTab = .memories }
        } else if appState.partner?.online == true {
            Text(L10n.t("home.online"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.mint)
        } else if let lastSeen = appState.partner?.lastSeenAt {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(.caption2).weight(.semibold))
                Text(L10n.t("home.lastSeen", ["time": L10n.relativeShort(lastSeen)]))
                    // Fix3 №3a: the status stays ONE line — at AX sizes
                    // every wrapped chrome line pushes the question under
                    // the tab bar (a stamp may truncate, never stack).
                    .lineLimit(1)
            }
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
        }
    }

    /// Fleeting partner details as atmosphere under the header: the mood
    /// line and the fresh now-playing song — only while they say something.
    /// At AX sizes the now-playing footnote steps back (№9: it is decor,
    /// and each grown line costs half the first screen); the mood line is
    /// content and stays — UNLESS it carries no note (Fix3 №3a): then it
    /// only repeats the avatar's mood badge plus a "gerade eben" stamp,
    /// a redundant grown line between title and question.
    @ViewBuilder
    private var atmosphereLines: some View {
        if let mood = appState.partner?.mood, !mood.isEmpty,
           !(dynamicTypeSize.isAccessibilitySize && partnerMoodNoteIsEmpty) {
            partnerMoodLine(mood)
        }
        if !dynamicTypeSize.isAccessibilitySize, let np = partnerNowPlaying {
            HStack(spacing: 5) {
                Image(systemName: "music.note")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                Text(np.artist.map { "\(np.title) · \($0)" } ?? np.title)
                    .lineLimit(1)
            }
            .font(.system(.caption, design: .rounded).weight(.semibold))
            .foregroundStyle(Theme.mint)
        }
    }

    /// True while the partner's mood carries no written note — then the
    /// mood line is pure repetition (emoji + age) at AX sizes (№3a).
    private var partnerMoodNoteIsEmpty: Bool {
        (appState.partner?.moodNote?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
    }

    /// Partner's now-playing status, only while still fresh (< 60 min) —
    /// mirrors the server's own expiry so a stale snapshot never lingers.
    private var partnerNowPlaying: NowPlaying? {
        guard let np = appState.partner?.nowPlaying,
              np.setAt > Date().addingTimeInterval(-3600) else { return nil }
        return np
    }

    /// The partner's mood with its honest age (Dossier 32, idea 5) — a day
    /// old it dims. Tap unfolds the full note (idea 23) and offers the
    /// one-tap "I see you" answer over the existing touch route (idea 4).
    private func partnerMoodLine(_ mood: String) -> some View {
        let updatedAt = appState.partner?.moodUpdatedAt
        let note = appState.partner?.moodNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: Space.xs) {
            Button {
                Haptics.shared.tap()
                withAnimation(Theme.Motion.settle) {
                    moodLineExpanded.toggle()
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(mood)
                    if let note, !note.isEmpty {
                        Text(note)
                            .lineLimit(moodLineExpanded ? nil : 1)
                            .multilineTextAlignment(.leading)
                    }
                    // AX sizes drop the age stamp from the visible line
                    // (Fix3 №3a — chrome, not content); VoiceOver keeps
                    // hearing it via partnerMoodA11y.
                    if let updatedAt, !dynamicTypeSize.isAccessibilitySize {
                        Text(L10n.relativeShort(updatedAt))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(partnerMoodA11y(mood, note: note, updatedAt: updatedAt))
            if moodLineExpanded {
                moodAckChip(updatedAt: updatedAt)
                    .transition(.opacity)
            }
        }
        .opacity(moodIsStale(updatedAt) ? 0.55 : 1)
    }

    /// "I see you" closes the loop that today ends in silence — a soft hug
    /// touch, no chat message needed. Redesign wave 1: the hand-built
    /// capsule became a DSChip — one chip vocabulary for the whole app,
    /// same states (inviting couple wash → quiet done-mint), plus the
    /// shared press response.
    private func moodAckChip(updatedAt: Date?) -> some View {
        let acked = ackedMoodStamp != nil && ackedMoodStamp == (updatedAt ?? .distantPast)
        return DSChip(
            icon: acked ? "checkmark" : "heart.fill",
            title: L10n.t(acked ? "home.mood.acked" : "home.mood.ack"),
            tint: acked ? Theme.mint : coupleTint.blend,
            prominence: acked ? .quiet : .filled
        ) {
            Haptics.shared.tap()
            appState.sendTouch(.hug)
            ackedMoodStamp = updatedAt ?? .distantPast
        }
        .disabled(acked)
    }

    private func partnerMoodA11y(_ mood: String, note: String?, updatedAt: Date?) -> String {
        var parts = [L10n.t("home.mood.partnerA11y", ["name": appState.partnerName]), mood]
        if let note, !note.isEmpty { parts.append(note) }
        if let updatedAt { parts.append(L10n.relativeShort(updatedAt)) }
        return parts.joined(separator: ", ")
    }

    private func nextEventCountdown(days: Int) -> String {
        days == 0 ? L10n.t("home.todayBang")
            : days == 1 ? L10n.t("home.tomorrow")
            : L10n.t("home.inDays", ["n": String(days)])
    }

    private var partnerA11y: String {
        var parts = [appState.partnerName]
        if appState.partner?.online == true { parts.append(L10n.t("home.online")) }
        if let mood = appState.partner?.mood { parts.append(mood) }
        return parts.joined(separator: ", ")
    }
}

/// The energy flow behind the Dienstlicht — the same battery card the
/// rituals block used to host (nothing lost, one tap closer): partner's
/// light, my three levels, the long-press note. Local sheet chrome only;
/// the card itself stays the shared `EnergyCard`.
private struct DienstlichtSheet: View {
    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                ScrollView {
                    EnergyCard()
                        .padding(Space.l)
                        .contentColumn(.hub)
                }
            }
            .navigationTitle(L10n.t("energy.title"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
