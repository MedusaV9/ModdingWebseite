import SwiftUI

// MARK: - Posteingang der Zärtlichkeiten 📖 (Post & Sendungen, P6-B)
//
// The shared 30-day chronology of everything the two sent each other:
// touches, pulses, delivered Zeitpost — newest first, in the server's
// deterministic order. Each Zettel wears its AUTHOR's ink edge
// (coupleTint.tintePrimary = mine, tinteSecondary = partner), echoes show
// their chain, Zeitpost arrivals their hourglass.

struct PostJournalSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [PostJournalEntry] = []
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground()
                ScrollView {
                    VStack(spacing: LayoutMetrics.s(16)) {
                        if entries.isEmpty && loaded {
                            emptyCard
                        } else if !entries.isEmpty {
                            journalCard
                        }
                    }
                    .padding(LayoutMetrics.s(16))
                    .contentColumn(.reading)
                }
            }
            .navigationTitle(L10n.t("post.journal.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("common.done")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .task(id: appState.couple?.id) {
            await reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { notification in
            guard let event = notification.object as? ServerEvent else { return }
            switch event.type {
            case .touch, .pulse, .postNote:
                // A new Sendung just landed — refetch instead of stitching:
                // the server's merge order stays the single source of truth.
                Task { await reload() }
            default:
                break
            }
        }
    }

    private var emptyCard: some View {
        VStack(spacing: LayoutMetrics.s(10)) {
            Image(systemName: "tray.full")
                .font(.system(.largeTitle).weight(.medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(coupleTint.blend)
                .accessibilityHidden(true)
            Text(L10n.t("post.journal.empty"))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .nightCard()
    }

    private var journalCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
            Text(L10n.t("post.journal.hint"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Nacht.tertiaer)
            ForEach(entries) { entry in
                journalRow(entry)
            }
        }
        .nightCard()
    }

    private func journalRow(_ entry: PostJournalEntry) -> some View {
        let mine = entry.senderId == appState.memberId
        // On the night card the author edge carries the RAW member color
        // (a fill, not text) — the paper inks would drown on dark ground.
        let ink = mine ? coupleTint.primary : coupleTint.secondary
        return HStack(alignment: .top, spacing: LayoutMetrics.s(10)) {
            Text(emoji(for: entry))
                .font(.system(.title3))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: entry))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Papier.aufNacht)
                    .lineLimit(3)
                HStack(spacing: LayoutMetrics.s(6)) {
                    // The "who" as quiet night copy — the edge next to it
                    // carries the author's color (text stays contrast-safe).
                    Text(mine ? L10n.t("post.journal.me") : appState.partnerName)
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(Nacht.sekundaer)
                    Text(L10n.relativeShort(entry.createdAt))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Nacht.tertiaer)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                if entry.isEcho {
                    badge(text: L10n.t("post.journal.echoBadge"),
                          systemImage: "arrow.uturn.left")
                }
                if entry.isZeitpost {
                    badge(text: L10n.t("post.journal.zeitpostBadge"),
                          systemImage: "hourglass")
                }
            }
        }
        .padding(LayoutMetrics.s(10))
        .padding(.leading, Papier.tintenkante)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Papier.nachtInnenFill)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(Nacht.naht, lineWidth: Theme.hairlineWidth)
                )
        )
        .overlay(alignment: .leading) {
            // Author ink edge (Papier.tintenkante) — the Zettel signature
            // from the chat wave: authorship as material, not as a wash.
            RoundedRectangle(cornerRadius: Papier.tintenkante / 2, style: .continuous)
                .fill(ink)
                .frame(width: Papier.tintenkante)
                .padding(.vertical, Space.s)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func badge(text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.system(.caption2, design: .rounded).weight(.bold))
            .foregroundStyle(Licht.lampengold)
            .padding(.horizontal, LayoutMetrics.s(8))
            .padding(.vertical, LayoutMetrics.s(3))
            .background(Capsule().fill(Licht.lampengold.opacity(0.12)))
    }

    // Raw-string tolerant: kinds a NEWER server invents still render as a
    // generic Sendung instead of breaking the list (old-client contract).
    private func emoji(for entry: PostJournalEntry) -> String {
        if let touch = entry.touchKind { return touch.emoji }
        if let pulse = entry.pulse { return pulse.emoji }
        if entry.postKind == .note { return "💌" }
        return "💌"
    }

    private func title(for entry: PostJournalEntry) -> String {
        if let text = entry.note, !text.isEmpty { return text }
        if let touch = entry.touchKind { return L10n.t(touch.titleKey) }
        if let pulse = entry.pulse { return L10n.t(pulse.titleKey) }
        return L10n.t("post.journal.unknown")
    }

    private func reload() async {
        guard let api = appState.api else { return }
        do {
            entries = try await api.postJournal()
        } catch {
            appState.handleAPIError(error)
        }
        loaded = true
    }
}
