import SwiftUI
import Combine

// MARK: - Umarmungs-Warteschlange 🫂
//
// For long-distance timezones: queue a hug while your partner sleeps; they
// open it like a little present when they wake up. Opening notifies the
// sender (`hug_opened`).

/// Dashboard card: pending-hug badge + entry into the queue sheet.
struct HugQueueCard: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint

    @State private var hugs: [Hug] = []
    @State private var showSheet = false

    private var pendingForMe: [Hug] {
        hugs.filter { $0.to == appState.memberId && $0.openedAt == nil }
    }

    var body: some View {
        Button {
            showSheet = true
        } label: {
            HStack(spacing: LayoutMetrics.s(14)) {
                ZStack(alignment: .topTrailing) {
                    Image(icon: .hug)
                        .font(.system(.largeTitle).weight(.medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(coupleTint.blend)
                        .accessibilityHidden(true)
                    if !pendingForMe.isEmpty {
                        Text("\(pendingForMe.count)")
                            .font(.system(.caption2, design: .rounded).weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(coupleTint.onBlend)
                            .padding(5)
                            .background(Circle().fill(coupleTint.blend))
                            .offset(x: 8, y: -6)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.t("hug.card.title"))
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Papier.aufNacht)
                    Text(pendingForMe.isEmpty
                         ? L10n.t("hug.card.teaser")
                         : L10n.t("hug.card.pending", count: pendingForMe.count))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(pendingForMe.isEmpty ? Nacht.sekundaer : Licht.lampengold)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .foregroundStyle(Nacht.tertiaer)
            }
            .nightCard()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSheet) {
            HugQueueSheet(hugs: $hugs)
        }
        .task(id: appState.couple?.id) {
            await reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent else { return }
            switch event.type {
            case .hugQueued, .hugOpened:
                if let hug = event.decode(HugResponse.self)?.hug {
                    upsert(hug)
                }
            default:
                break
            }
        }
    }

    private func reload() async {
        guard let api = appState.api else { return }
        if let loaded = try? await api.hugs() {
            hugs = loaded
        }
    }

    private func upsert(_ hug: Hug) {
        if let idx = hugs.firstIndex(where: { $0.id == hug.id }) {
            hugs[idx] = hug
        } else {
            hugs.insert(hug, at: 0)
        }
    }
}

// MARK: - Queue sheet

struct HugQueueSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.dismiss) private var dismiss
    /// Fix2-A №7 (same law as WaitingForPartnerCard): the endless
    /// hourglass pulse is ornamental and runs through the motion gate.
    @Environment(\.motionGate) private var motionGate

    @Binding var hugs: [Hug]

    @State private var note = ""
    @State private var sending = false
    @State private var openingId: String?
    @State private var burstId: String?

    private var pendingForMe: [Hug] {
        hugs.filter { $0.to == appState.memberId && $0.openedAt == nil }
    }

    private var queuedByMe: [Hug] {
        hugs.filter { $0.from == appState.memberId && $0.openedAt == nil }
    }

    private var history: [Hug] {
        Array(hugs.filter { $0.openedAt != nil }.prefix(10))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground()
                ScrollView {
                    VStack(spacing: LayoutMetrics.s(16)) {
                        composeCard
                        if !pendingForMe.isEmpty {
                            pendingCard
                        }
                        if !queuedByMe.isEmpty {
                            queuedCard
                        }
                        if !history.isEmpty {
                            historyCard
                        }
                    }
                    .padding(LayoutMetrics.s(16))
                }
                if burstId != nil {
                    FloatingHeartsView(emojis: ["🫂", "💞", "💗", "✨"], count: 24)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
            .navigationTitle(L10n.t("hug.card.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("common.done")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Compose

    private var composeCard: some View {
        VStack(spacing: LayoutMetrics.s(12)) {
            Image(icon: .hug)
                .font(.system(.largeTitle).weight(.medium))
                .imageScale(.large)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(coupleTint.blend)
                .accessibilityHidden(true)
            Text(L10n.t("hug.compose.body", ["name": appState.partnerName]))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            // Night-chrome input on the night card — paperField stays a
            // paper-surface control (MIGRATION_DUNKEL §4).
            TextField(L10n.t("hug.compose.placeholder"), text: $note, axis: .vertical)
                .textFieldStyle(DreamyFieldStyle())
                .lineLimit(1...3)
            Button {
                queue()
            } label: {
                if sending {
                    BusySpinner()
                } else {
                    Text(L10n.t("hug.compose.send"))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(sending || appState.partner == nil)
        }
        .nightCard()
    }

    private func queue() {
        guard let api = appState.api, !sending else { return }
        sending = true
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let hug = try await api.queueHug(note: text.isEmpty ? nil : text, emoji: nil)
                hugs.insert(hug, at: 0)
                note = ""
                SoundEngine.shared.play(.pop)
                Haptics.shared.success()
                appState.showToast(L10n.t("hug.compose.sentToast", ["name": appState.partnerName]),
                                   style: .love)
            } catch {
                appState.handleAPIError(error)
            }
            sending = false
        }
    }

    // MARK: Pending (for me — the presents)

    private var pendingCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
            Text(L10n.t("hug.pending.title", ["n": String(pendingForMe.count)]))
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Papier.aufNacht)
            ForEach(pendingForMe) { hug in
                pendingRow(hug)
            }
        }
        .nightCard()
    }

    private func pendingRow(_ hug: Hug) -> some View {
        HStack(spacing: LayoutMetrics.s(12)) {
            Image(icon: .gift)
                .font(.system(.title).weight(.medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(coupleTint.blend)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("hug.pending.from", ["name": appState.partnerName]))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Papier.aufNacht)
                Text(L10n.relativeShort(hug.createdAt))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
            }
            Spacer()
            Button {
                open(hug)
            } label: {
                if openingId == hug.id {
                    BusySpinner(tint: Licht.lampengold)
                } else {
                    Text(L10n.t("hug.pending.open"))
                        .font(.system(.footnote, design: .rounded).weight(.bold))
                        // Computed ink on the couple gradient (round 3) —
                        // plus the night-ink scrim for palettes where no
                        // ink alone clears 4.5:1 on both stops.
                        .foregroundStyle(coupleTint.onGradient)
                        .padding(.horizontal, LayoutMetrics.s(14))
                        .padding(.vertical, LayoutMetrics.s(8))
                        .background(
                            Capsule().fill(coupleTint.heroGradient)
                                .overlay(Capsule().fill(coupleTint.gradientTextScrim ?? .clear))
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(openingId != nil)
        }
        .padding(LayoutMetrics.s(10))
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(coupleTint.blend.opacity(0.1))
        )
    }

    private func open(_ hug: Hug) {
        guard let api = appState.api, openingId == nil else { return }
        openingId = hug.id
        Task {
            do {
                let opened = try await api.openHug(id: hug.id)
                if let idx = hugs.firstIndex(where: { $0.id == opened.id }) {
                    hugs[idx] = opened
                }
                burstId = opened.id
                SoundEngine.shared.play(.tada)
                Haptics.shared.play(.hug)
                if let note = opened.note, !note.isEmpty {
                    appState.showToast(note, style: .love)
                }
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if burstId == opened.id { burstId = nil }
            } catch {
                appState.handleAPIError(error)
            }
            openingId = nil
        }
    }

    // MARK: Queued by me

    private var queuedCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
            Text(L10n.t("hug.queued.title", ["name": appState.partnerName]))
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Papier.aufNacht)
            ForEach(queuedByMe) { hug in
                HStack(spacing: LayoutMetrics.s(10)) {
                    Text(hug.emoji)
                        .font(.system(.title2))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hug.note ?? L10n.t("hug.queued.plain"))
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Papier.aufNacht)
                            .lineLimit(2)
                        Text(L10n.relativeShort(hug.createdAt))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Nacht.tertiaer)
                    }
                    Spacer()
                    Image(systemName: "hourglass")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Nacht.tertiaer)
                        // Gated repeat (Fix2-A №7): under Reduce Motion
                        // the hourglass rests instead of pulsing forever.
                        .symbolEffect(.pulse, options: .repeating,
                                      isActive: motionGate.particlesEnabled)
                        .accessibilityHidden(true)
                }
            }
            Text(L10n.t("hug.queued.hint", ["name": appState.partnerName]))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Nacht.tertiaer)
        }
        .nightCard()
    }

    // MARK: History

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
            Text(L10n.t("hug.history.title"))
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Papier.aufNacht)
            ForEach(history) { hug in
                HStack(spacing: LayoutMetrics.s(10)) {
                    Image(systemName: hug.from == appState.memberId
                          ? "arrow.up.right" : "arrow.down.left")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(Nacht.tertiaer)
                        .accessibilityHidden(true)
                    Text(hug.note ?? L10n.t("hug.queued.plain"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Nacht.sekundaer)
                        .lineLimit(1)
                    Spacer()
                    if let openedAt = hug.openedAt {
                        Text(L10n.relativeShort(openedAt))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Nacht.tertiaer)
                    }
                }
            }
        }
        .nightCard()
    }
}
