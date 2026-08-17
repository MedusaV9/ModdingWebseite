import SwiftUI
import Combine

/// Bedürfnis-Verlauf: the full history of "I need right now…"
/// signals plus a composer with an optional note — the dashboard card
/// stays one-tap, this screen is for the words when you have them.
struct NeedsHistoryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint

    @State private var needs: [NeedSignal] = []
    @State private var loading = true
    @State private var loadFailed = false
    @State private var selectedType: NeedType?
    @State private var note = ""
    @State private var busy = false

    var body: some View {
        ZStack {
            DreamyBackground()
            ScrollView {
                VStack(spacing: Space.l) {
                    Text(L10n.t("needs.subtitle"))
                        .font(Typo.label)
                        .foregroundStyle(Theme.textSecondary)
                    composer
                    if needs.isEmpty && !loading {
                        if loadFailed {
                            RitualsLoadFailedNotice(connected: appState.socket.state == .connected) {
                                Task { await reload() }
                            }
                        } else {
                            EmptyStateView(systemImage: "hands.sparkles",
                                           title: L10n.t("needs.empty.title"),
                                           subtitle: L10n.t("needs.empty.subtitle"))
                        }
                    }
                    ForEach(needs) { need in
                        NeedHistoryRow(need: need, onAck: { acknowledge(need) })
                    }
                }
                .padding(Space.l)
            }
        }
        .navigationTitle(L10n.t("needs.history"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: appState.couple?.id) {
            await reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent else { return }
            switch event.type {
            case .need, .needAcked:
                if let need = event.decode(NeedEventPayload.self)?.need {
                    apply(need)
                }
            default:
                break
            }
        }
    }

    private func apply(_ need: NeedSignal) {
        if let idx = needs.firstIndex(where: { $0.id == need.id }) {
            needs[idx] = need
        } else {
            needs.insert(need, at: 0)
        }
    }

    private func reload() async {
        guard let api = appState.api else { return }
        loading = true
        do {
            needs = try await api.needs(limit: 50)
            loadFailed = false
        } catch {
            loadFailed = true
        }
        loading = false
    }

    // MARK: Composer with optional note

    private var composer: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(L10n.t("needs.title"))
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Papier.aufNacht)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s) {
                    ForEach(NeedType.allCases) { type in
                        typeChip(type)
                    }
                }
            }
            if selectedType != nil {
                TextField(L10n.t("needs.noteField"), text: $note)
                    .textFieldStyle(DreamyFieldStyle())
                Button(L10n.t("needs.send")) {
                    send()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy || appState.partner == nil)
            }
        }
        .nightCard()
    }

    private func typeChip(_ type: NeedType) -> some View {
        let selected = selectedType == type
        return Button {
            Haptics.shared.tap()
            withAnimation(Theme.Motion.settle) {
                selectedType = selected ? nil : type
            }
        } label: {
            HStack(spacing: Space.s) {
                Text(type.emoji)
                    .font(.system(.body))
                Text(L10n.t(type.titleKey))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                    .lineLimit(1)
            }
            .padding(.vertical, Space.s)
            .padding(.horizontal, Space.m)
            .background(Capsule().fill(selected ? coupleTint.blend.opacity(0.15) : Papier.nachtInnenFill))
            .overlay(Capsule().strokeBorder(selected ? coupleTint.blend : Nacht.naht,
                                            lineWidth: selected ? 1.5 : Theme.hairlineWidth))
        }
        .buttonStyle(.plain)
    }

    private func send() {
        guard let api = appState.api, let type = selectedType, !busy else { return }
        busy = true
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let need = try await api.sendNeed(type: type, note: trimmed.isEmpty ? nil : trimmed)
                apply(need)
                SoundEngine.shared.play(.pop)
                Haptics.shared.success()
                appState.showToast(L10n.t("needs.sentToast", ["name": appState.partnerName]),
                                   style: .love)
                selectedType = nil
                note = ""
            } catch {
                appState.handleAPIError(error)
            }
            busy = false
        }
    }

    private func acknowledge(_ need: NeedSignal) {
        guard let api = appState.api, !busy else { return }
        busy = true
        Task {
            do {
                let updated = try await api.ackNeed(id: need.id)
                apply(updated)
                Haptics.shared.success()
                SoundEngine.shared.play(.sparkle)
            } catch {
                appState.handleAPIError(error)
            }
            busy = false
        }
    }
}

// MARK: - One signal in the history

private struct NeedHistoryRow: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    let need: NeedSignal
    let onAck: () -> Void

    private var mine: Bool { need.senderId == appState.memberId }

    /// The author's RAW color for the edge on night — the paper ink
    /// ladder (`tintePrimary/Secondary`) is paper-only and too dark here.
    private var senderTint: Color {
        mine ? coupleTint.primary : coupleTint.secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.m) {
                Text(need.needType?.emoji ?? "🤍")
                    .font(.system(.title2))
                VStack(alignment: .leading, spacing: 1) {
                    Text(senderLine)
                        .font(Typo.caption)
                        .foregroundStyle(Nacht.sekundaer)
                    Text(need.needType.map { L10n.t($0.titleKey) } ?? need.type)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Papier.aufNacht)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: Space.xs) {
                    Text(L10n.relativeShort(need.createdAt))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Nacht.tertiaer)
                    if need.ackAt != nil {
                        PillTag(text: L10n.t("needs.acked"), tint: Licht.glut)
                    }
                }
            }
            if let text = need.note, !text.isEmpty {
                // The couple's own words — nachtkarton speaks rounded
                // (serif is paper-only), the italic keeps the pen voice.
                Text("„\(text)“")
                    .font(.system(.subheadline, design: .rounded).italic())
                    .foregroundStyle(Papier.aufNacht)
            }
            if !mine && need.ackAt == nil {
                Button(L10n.t("needs.ack")) {
                    onAck()
                }
                .buttonStyle(SecondaryButtonStyle(fullWidth: false))
            }
        }
        .nightCard()
        .overlay(alignment: .leading) {
            // Author ink edge (Papier.tintenkante) instead of a full tinted
            // border — the Zettel signature from the chat wave.
            RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                .fill(senderTint)
                .frame(width: Papier.tintenkante)
                .padding(.vertical, Space.m)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var senderLine: String {
        let sender = appState.couple?.members.first { $0.id == need.senderId }
        let avatar = sender?.avatar ?? "💜"
        if mine { return "\(avatar) \(L10n.t("common.you"))" }
        return "\(avatar) \(sender?.name ?? appState.partnerName)"
    }
}
