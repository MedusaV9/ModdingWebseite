import SwiftUI

// MARK: - Zeitpost 📮 (Post & Sendungen, FullRelease P6-B → R1-D)
//
// Post a touch, a pulse, or a short note INTO THE FUTURE: the server holds
// it and delivers 5 minutes to 7 days later, as the normal moment. The
// partner never sees that anything is pending — the surprise is the point.
// At most 5 open Sendungen per person (PostRules mirrors the server).
//
// R1-D: posting is a CEREMONY now, not a toast — the composed content
// folds into a little envelope, the postmark lands with the Kino-Manifest
// stamp beat (PostMomentScore.stamp: rigid 0.9/0.62 + the 0.32 s paper
// spring, `.sealed` as its voice), then the envelope glides away and the
// sheet closes. ~2.5 s, every tap skips ahead. Reduce Motion: the stamped
// envelope as a still (same haptic), then dismiss.

struct ZeitpostSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.motionGate) private var motionGate
    @Environment(\.dismiss) private var dismiss

    /// My own open Sendungen — soonest first, straight from the server.
    @State private var posts: [ScheduledPost] = []
    @State private var kind: PostKind = .touch
    @State private var touchKind: TouchKind = .kiss
    @State private var pulseKind: PulseKind = .thinking
    @State private var note = ""
    @State private var deliverAt = PostRules.earliestPickable()
    @State private var sending = false
    @State private var cancelingId: String?

    // R1-D send ceremony — phases of the envelope choreography.
    @State private var ceremonyActive = false
    @State private var ceremonyFolded = false
    @State private var ceremonyStamped = false
    @State private var ceremonyFlying = false
    @State private var ceremonyTask: Task<Void, Error>?
    /// S3 (robustness eval): true while the "arrival slipped too close —
    /// gently moved" hint shows under the DatePicker.
    @State private var nudgeHintVisible = false
    @State private var nudgeHintTask: Task<Void, Error>?

    private var slotsLeft: Int { PostRules.remainingSlots(openCount: posts.count) }

    private var canSend: Bool {
        guard !sending, PostRules.canScheduleMore(openCount: posts.count) else { return false }
        // S3: the verdict gate — a stale pick (sheet left open past its
        // own window) would be rejected server-side; the nudge task below
        // heals it, until then the button honestly refuses.
        guard PostRules.deliverAtVerdict(deliverAt) == .ok else { return false }
        if kind == .note { return PostRules.validatedNote(note) != nil }
        return true
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground()
                ScrollView {
                    VStack(spacing: LayoutMetrics.s(16)) {
                        composeCard
                        if !posts.isEmpty {
                            openCard
                        }
                    }
                    .padding(LayoutMetrics.s(16))
                    .contentColumn(.reading)
                }
                if ceremonyActive {
                    sendCeremony
                        .transition(.opacity)
                        .zIndex(2)
                }
            }
            .animation(Theme.Motion.arrive, value: ceremonyActive)
            .navigationTitle(L10n.t("post.zeitpost.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("common.done")) { dismiss() }
                        .accessibilityIdentifier("zeitpost.done")
                }
            }
        }
        .presentationDetents([.large])
        .task(id: appState.couple?.id) {
            await reload()
        }
        // S3: the long-open-composer healer — while the sheet sits, the
        // pickable window slides past the pick; this quiet loop nudges
        // `deliverAt` back onto `earliestPickable` (pure rule in
        // PostRules.nudgedDeliverAt) and shows the gentle hint.
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                nudgeDeliverAtIfStale()
            }
        }
        .onDisappear {
            ceremonyTask?.cancel()
            nudgeHintTask?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { notification in
            guard let event = notification.object as? ServerEvent else { return }
            switch event.type {
            case .postScheduled:
                // My OTHER device posted one — adopt it (sender-only frame).
                if let post = event.decode(PostScheduledPayload.self)?.post {
                    upsert(post)
                }
            case .postCanceled:
                if let id = event.decode(PostCanceledPayload.self)?.id {
                    posts.removeAll { $0.id == id }
                }
            case .touch, .pulse, .postNote:
                // A delivery just happened — the open list may have shrunk.
                Task { await reload() }
            default:
                break
            }
        }
    }

    // MARK: Compose

    private var composeCard: some View {
        VStack(spacing: LayoutMetrics.s(12)) {
            Image(systemName: "hourglass")
                .font(.system(.largeTitle).weight(.medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(coupleTint.blend)
                .accessibilityHidden(true)
            Text(L10n.t("post.zeitpost.body", ["name": appState.partnerName]))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            kindPicker
            contentPicker

            DatePicker(L10n.t("post.zeitpost.deliverAt"),
                       selection: $deliverAt,
                       in: PostRules.earliestPickable()...PostRules.latestPickable())
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Papier.aufNacht)
                .tint(Licht.lampengold)
                // Locale-Naht: der Picker spricht die App-Sprache, nicht
                // die Geräte-Locale (Amt-Muster, Re-Eval №9).
                .environment(\.locale, Locale(identifier: L10n.lang))
                .accessibilityIdentifier("zeitpost.deliverAt")

            if nudgeHintVisible {
                // The gentle S3 hint — on nachtkarton a deadline speaks
                // in the ember (`Licht.ablauf`), not the paper wax.
                Text(PostMomentStrings.t("post.zeitpost.nudged"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Licht.ablauf)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            Button {
                send()
            } label: {
                if sending {
                    BusySpinner()
                } else {
                    Text(L10n.t("post.zeitpost.send"))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canSend || appState.partner == nil)

            Text(slotsLeft == 0
                 ? L10n.t("post.zeitpost.limitHint")
                 : L10n.t("post.zeitpost.secretHint", ["name": appState.partnerName]))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Nacht.tertiaer)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .nightCard()
        // R1-D: every picker choice ticks — kind chips, gesture/pulse
        // chips and the arrival date all confirm the selection in the
        // hand (the system selection tick, same as the tab bar).
        .sensoryFeedback(.selection, trigger: kind)
        .sensoryFeedback(.selection, trigger: touchKind)
        .sensoryFeedback(.selection, trigger: pulseKind)
        .sensoryFeedback(.selection, trigger: deliverAt)
    }

    /// What the Sendung carries — three quiet chips.
    private var kindPicker: some View {
        HStack(spacing: LayoutMetrics.s(8)) {
            ForEach(PostKind.allCases) { candidate in
                chip(text: L10n.t("post.zeitpost.kind.\(candidate.rawValue)"),
                     selected: kind == candidate) {
                    kind = candidate
                }
                .accessibilityIdentifier("zeitpost.kind.\(candidate.rawValue)")
            }
        }
    }

    @ViewBuilder
    private var contentPicker: some View {
        switch kind {
        case .touch:
            // All eight gestures — Zeitpost may carry the heartbeat too
            // (the live grid reserves it for the 3D heart, a SEND-NOW rule).
            FlowChips(items: TouchKind.allCases.map { ($0.rawValue, "\($0.emoji) \(L10n.t($0.titleKey))") },
                      selectedId: touchKind.rawValue) { raw in
                if let picked = TouchKind(rawValue: raw) { touchKind = picked }
            }
        case .pulse:
            FlowChips(items: PulseKind.allCases.map { ($0.rawValue, "\($0.emoji) \(L10n.t($0.titleKey))") },
                      selectedId: pulseKind.rawValue) { raw in
                if let picked = PulseKind(rawValue: raw) { pulseKind = picked }
            }
        case .note:
            VStack(alignment: .trailing, spacing: 4) {
                TextField(L10n.t("post.zeitpost.notePlaceholder"), text: $note, axis: .vertical)
                    .textFieldStyle(DreamyFieldStyle())
                    .lineLimit(2...4)
                Text(L10n.t("post.zeitpost.noteCount",
                            ["n": String(note.count), "max": String(PostRules.noteMaxLength)]))
                    .font(.system(.caption2, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(note.count > PostRules.noteMaxLength
                                     ? Licht.glut : Nacht.tertiaer)
            }
        }
    }

    private func chip(text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(.footnote, design: .rounded).weight(.bold))
                .foregroundStyle(selected ? Licht.lampengold : Nacht.sekundaer)
                .frame(maxWidth: .infinity)
                .padding(.vertical, LayoutMetrics.s(8))
                .background(
                    Capsule()
                        .fill(selected ? Licht.lampengold.opacity(0.14) : Papier.nachtInnenFill)
                        .overlay(
                            Capsule().strokeBorder(selected ? Licht.lampengold : Nacht.naht,
                                                   lineWidth: Theme.hairlineWidth)
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func send() {
        // Last-instant staleness check (S3): a pick that went invalid
        // between nudge cycles is healed instead of sent-and-rejected —
        // the person confirms the moved time with a second tap.
        guard !nudgeDeliverAtIfStale() else { return }
        guard canSend else { return }
        sending = true
        Task {
            let accepted = await appState.schedulePost(
                touch: kind == .touch ? touchKind : nil,
                pulse: kind == .pulse ? pulseKind : nil,
                note: kind == .note ? PostRules.validatedNote(note) : nil,
                deliverAt: deliverAt)
            sending = false
            if accepted {
                note = ""
                deliverAt = PostRules.earliestPickable()
                beginCeremony()
                await reload()
            }
        }
    }

    // MARK: R1-D — the send ceremony (fold → stamp → fly → close)

    /// The composed content folds into the little envelope (a paper-
    /// rectangle morph over the dimmed sheet), the postmark lands on the
    /// stamp beat, the envelope glides up and away, the sheet closes.
    /// Every tap skips straight to the close.
    private var sendCeremony: some View {
        ZStack {
            motionGate.scrim(0.45)
                .ignoresSafeArea()
            PostEnvelopeView(sealed: true, stamped: ceremonyStamped)
                .scaleEffect(ceremonyFolded || motionGate.reduceMotion ? 1 : 2.1)
                .opacity(ceremonyFlying ? 0 : (ceremonyFolded ? 1 : 0))
                .offset(y: ceremonyFlying ? -LayoutMetrics.s(520) : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { finishCeremony() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("post.zeitpost.sentToast"))
        .accessibilityAction(named: PostMomentStrings.t("post.zeitpost.ceremony.skip")) {
            finishCeremony()
        }
    }

    private func beginCeremony() {
        ceremonyActive = true
        // VoiceOver hears what the ceremony shows — the old toast line,
        // now spoken over the envelope instead of banner-flashed.
        AccessibilityNotification.Announcement(L10n.t("post.zeitpost.sentToast")).post()
        if motionGate.reduceMotion {
            // The still: the stamped envelope, the same stamp beat.
            ceremonyFolded = true
            ceremonyStamped = true
            PostMomentScore.stamp()
            ceremonyTask = Task {
                try await Task.sleep(nanoseconds: 1_400_000_000)
                finishCeremony()
            }
            return
        }
        withAnimation(Theme.Motion.arrive) { ceremonyFolded = true }
        ceremonyTask = Task {
            // Beat plan (~2.5 s): fold 0–0.9, stamp 0.9 (haptic + cue),
            // lift-off 1.7, close 2.5 — cancellation (skip tap or sheet
            // teardown) throws out of the sequence at any beat.
            try await Task.sleep(nanoseconds: 900_000_000)
            withAnimation(Theme.Motion.settle) { ceremonyStamped = true }
            PostMomentScore.stamp()
            try await Task.sleep(nanoseconds: 800_000_000)
            withAnimation(Theme.Motion.arrive) { ceremonyFlying = true }
            try await Task.sleep(nanoseconds: 800_000_000)
            finishCeremony()
        }
    }

    private func finishCeremony() {
        ceremonyTask?.cancel()
        dismiss()
    }

    // MARK: S3 — the deliverAt nudge

    /// Applies `PostRules.nudgedDeliverAt` when the pick went stale and
    /// shows the gentle hint. Returns true when a nudge happened.
    @discardableResult
    private func nudgeDeliverAtIfStale() -> Bool {
        guard let nudged = PostRules.nudgedDeliverAt(deliverAt) else { return false }
        withAnimation(Theme.Motion.settle) {
            deliverAt = nudged
            nudgeHintVisible = true
        }
        nudgeHintTask?.cancel()
        nudgeHintTask = Task {
            try await Task.sleep(nanoseconds: 6_000_000_000)
            withAnimation(Theme.Motion.settle) { nudgeHintVisible = false }
        }
        return true
    }

    // MARK: Open Sendungen (mine only — the partner never sees these)

    private var openCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
            Text(L10n.t("post.zeitpost.open.title",
                        ["n": String(posts.count), "max": String(PostRules.maxOpen)]))
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Papier.aufNacht)
            ForEach(posts) { post in
                openRow(post)
            }
        }
        .nightCard()
    }

    private func openRow(_ post: ScheduledPost) -> some View {
        HStack(spacing: LayoutMetrics.s(10)) {
            Text(emoji(for: post))
                .font(.system(.title2))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: post))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Papier.aufNacht)
                    .lineLimit(2)
                Text(L10n.t("post.zeitpost.arrives",
                            ["date": AppFormatters.dateTemplate(
                                post.deliverAt, template: "EdMMM jm", language: L10n.lang)]))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
            }
            Spacer()
            Button {
                cancel(post)
            } label: {
                if cancelingId == post.id {
                    BusySpinner(tint: Licht.lampengold)
                } else {
                    Text(L10n.t("post.zeitpost.cancel"))
                        .font(.system(.footnote, design: .rounded).weight(.bold))
                        .foregroundStyle(Nacht.sekundaer)
                        .padding(.horizontal, LayoutMetrics.s(12))
                        .padding(.vertical, LayoutMetrics.s(7))
                        .background(
                            Capsule().strokeBorder(Nacht.naht,
                                                   lineWidth: Theme.hairlineWidth)
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(cancelingId != nil)
        }
        .padding(LayoutMetrics.s(10))
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Papier.nachtInnenFill)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(Nacht.naht, lineWidth: Theme.hairlineWidth)
                )
        )
    }

    // Raw-string tolerant: a newer server's future kinds still render.
    private func emoji(for post: ScheduledPost) -> String {
        if let touch = post.touchKind { return touch.emoji }
        if let pulse = post.pulse { return pulse.emoji }
        return "💌"
    }

    private func title(for post: ScheduledPost) -> String {
        if let touch = post.touchKind { return L10n.t(touch.titleKey) }
        if let pulse = post.pulse { return L10n.t(pulse.titleKey) }
        if let text = post.note, !text.isEmpty { return text }
        return L10n.t("post.journal.unknown")
    }

    private func reload() async {
        guard let api = appState.api else { return }
        do {
            posts = try await api.scheduledPosts()
        } catch {
            appState.handleAPIError(error)
        }
    }

    private func upsert(_ post: ScheduledPost) {
        if let idx = posts.firstIndex(where: { $0.id == post.id }) {
            posts[idx] = post
        } else {
            posts.append(post)
            posts.sort { $0.deliverAt < $1.deliverAt }
        }
    }

    private func cancel(_ post: ScheduledPost) {
        guard let api = appState.api, cancelingId == nil else { return }
        cancelingId = post.id
        Task {
            do {
                try await api.cancelScheduledPost(id: post.id)
                posts.removeAll { $0.id == post.id }
                Haptics.shared.tap()
                appState.showToast(L10n.t("post.zeitpost.canceledToast"), style: .info)
            } catch {
                appState.handleAPIError(error)
            }
            cancelingId = nil
        }
    }
}

// MARK: - Flow chips

/// A wrapping row of selectable chips (emoji + label) — small enough to
/// stay local to the Zeitpost composer.
struct FlowChips: View {
    let items: [(id: String, label: String)]
    let selectedId: String
    let onPick: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(items, id: \.id) { item in
                Button {
                    onPick(item.id)
                } label: {
                    Text(item.label)
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .foregroundStyle(item.id == selectedId ? Licht.lampengold : Nacht.sekundaer)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, LayoutMetrics.s(7))
                        .padding(.horizontal, LayoutMetrics.s(6))
                        .background(
                            Capsule()
                                .fill(item.id == selectedId
                                      ? Licht.lampengold.opacity(0.14) : Papier.nachtInnenFill)
                                .overlay(
                                    Capsule().strokeBorder(
                                        item.id == selectedId ? Licht.lampengold : Nacht.naht,
                                        lineWidth: Theme.hairlineWidth)
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(item.id == selectedId ? .isSelected : [])
            }
        }
    }
}
