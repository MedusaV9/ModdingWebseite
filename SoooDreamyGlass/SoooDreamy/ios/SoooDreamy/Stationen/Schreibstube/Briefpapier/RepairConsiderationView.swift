import CryptoKit
import SwiftUI
import Combine

struct RepairConsiderationView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint

    @State private var sessions: [RepairSession] = []
    @State private var hints: [ConsiderationHint] = []
    @State private var goodThingsDay: GoodThingsDay?
    @State private var repairText = ""
    @State private var hintText = ""
    @State private var goodThingTexts = ["", "", ""]
    @State private var repairPromptIndex = 0
    @State private var gratitudePromptIndex = 0
    @State private var decryptedHints: [String: String] = [:]
    @State private var loading = true
    @State private var loadFailed = false
    @State private var busy = false

    private var currentSession: RepairSession? {
        sessions.first { $0.status != "completed" } ?? sessions.first
    }

    var body: some View {
        ZStack {
            DreamyBackground()
            ScrollView {
                VStack(spacing: Space.l) {
                    if loading && sessions.isEmpty && hints.isEmpty && goodThingsDay == nil {
                        // Waiting in the shape of the coming sections —
                        // never sections popping in out of nowhere.
                        PaperSkeleton(kind: .card(height: 180))
                        PaperSkeleton(kind: .card(height: 220))
                        PaperSkeleton(kind: .card(height: 180))
                    } else {
                        if loadFailed {
                            // History may be missing — say so honestly above
                            // the compose entries instead of dressing the
                            // failure as an empty beginning.
                            RitualsLoadFailedNotice(connected: appState.socket.state == .connected) {
                                Task { await reload() }
                            }
                        }
                        repairSection
                        considerationSection
                        gratitudeSection
                    }
                }
                .padding(Space.l)
            }
        }
        .navigationTitle(L10n.t("repair.card.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: appState.couple?.id) { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent else { return }
            switch event.type {
            case .repairChanged, .considerationChanged, .goodthings:
                Task { await reload() }
            default:
                break
            }
        }
    }

    @ViewBuilder
    private var repairSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Label(L10n.t("repair.title"), systemImage: "quote.bubble.fill")
                .font(Typo.title)
                .foregroundStyle(Papier.aufNacht)
            Text(L10n.t("repair.subtitle"))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
                .fixedSize(horizontal: false, vertical: true)

            if let session = currentSession {
                repairSession(session)
            } else {
                promptCard(RelationshipSupportContent.repairPrompts[repairPromptIndex].text.resolved(L10n.lang))
                Button(L10n.t("repair.new")) { createRepair() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(busy)
                Button(L10n.t("repair.nextPrompt")) {
                    repairPromptIndex = (repairPromptIndex + 1)
                        % RelationshipSupportContent.repairPrompts.count
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .nightCard()
    }

    @ViewBuilder
    private func repairSession(_ session: RepairSession) -> some View {
        if let prompt = RelationshipSupportContent.repairPrompts.first(where: { $0.id == session.promptId }) {
            promptCard(prompt.text.resolved(L10n.lang))
        }
        if session.status == "completed" {
            Label(L10n.t("repair.completed"), systemImage: "checkmark.seal.fill")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(Licht.lampengold)
            Button(L10n.t("repair.new")) { createRepair() }
                .buttonStyle(SecondaryButtonStyle())
        } else {
            if let cooldown = session.cooldownUntil, cooldown > Date() {
                Text(L10n.t("repair.cooldownActive", [
                    "time": AppFormatters.date(
                        cooldown,
                        language: L10n.lang,
                        dateStyle: .none,
                        timeStyle: .short
                    )
                ]))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Licht.glut)
            } else if let expected = session.expected {
                let mine = expected.memberId == appState.memberId
                Text(mine
                     ? L10n.t("repair.yourTurn", ["kind": kindLabel(expected.kind)])
                     : L10n.t("repair.partnerTurn", ["name": appState.partnerName]))
                    .font(Typo.label)
                    .foregroundStyle(mine ? Licht.lampengold : Nacht.sekundaer)

                if mine {
                    // Explicit ink: on nachtkarton the editor writes in
                    // aufNacht with a lampengold caret.
                    TextEditor(text: $repairText)
                        .font(Typo.body)
                        .foregroundStyle(Papier.aufNacht)
                        .tint(Licht.lampengold)
                        .frame(minHeight: 90)
                        .padding(Space.s)
                        .scrollContentBackground(.hidden)
                        .background(RoundedRectangle(cornerRadius: Radius.control)
                            .fill(Papier.nachtInnenFill)
                            .overlay(RoundedRectangle(cornerRadius: Radius.control)
                                .strokeBorder(Nacht.naht, lineWidth: Theme.hairlineWidth)))
                        .accessibilityLabel(L10n.t("repair.placeholder"))
                    Button(L10n.t("repair.send")) {
                        submitRepair(session: session, kind: expected.kind)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(busy || repairText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Button(L10n.t("repair.cooldown")) { startCooldown(session) }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(busy)
        }

        if session.entries.isEmpty {
            Text(L10n.t("repair.empty"))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Nacht.tertiaer)
        } else {
            ForEach(session.entries) { entry in
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(kindLabel(entry.kind))
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(Licht.lampengold)
                    Text(entry.text)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Papier.aufNacht)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.m)
                .background(RoundedRectangle(cornerRadius: Radius.control).fill(Papier.nachtInnenFill))
            }
        }
    }

    private var considerationSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Label(L10n.t("consideration.title"), systemImage: "hand.raised.heart.fill")
                .font(Typo.title)
                .foregroundStyle(Papier.aufNacht)
            Text(L10n.t("consideration.subtitle"))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
                .fixedSize(horizontal: false, vertical: true)

            Text(L10n.t("consideration.templates"))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Nacht.sekundaer)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.s) {
                    ForEach(RelationshipSupportContent.considerationHints.prefix(6)) { prompt in
                        Button(prompt.text.resolved(L10n.lang)) {
                            hintText = prompt.text.resolved(L10n.lang)
                        }
                        .font(Typo.caption)
                        .foregroundStyle(Papier.aufNacht)
                        .padding(.horizontal, Space.m)
                        .frame(minHeight: 44)
                        .background(Capsule().fill(Papier.nachtInnenFill))
                    }
                }
            }
            TextField(L10n.t("consideration.placeholder"), text: $hintText, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(DreamyFieldStyle())
            Button(L10n.t("consideration.share")) { shareHint() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy || hintText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if hints.isEmpty {
                Text(L10n.t("consideration.none"))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
            } else {
                Button(L10n.t("consideration.unlock")) { unlockHints() }
                    .buttonStyle(SecondaryButtonStyle())
                ForEach(hints) { hint in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(Licht.lampengold)
                        Text(decryptedHints[hint.id] ?? "••••••••")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Papier.aufNacht)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if hint.senderId == appState.memberId {
                            Button(L10n.t("consideration.pause")) { pauseHint(hint) }
                                .font(Typo.caption)
                                .foregroundStyle(Licht.lampengold)
                        }
                    }
                    .padding(Space.m)
                    .background(RoundedRectangle(cornerRadius: Radius.control).fill(Papier.nachtInnenFill))
                }
            }
        }
        .nightCard()
    }

    private var gratitudeSection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Label(L10n.t("gratitude.title"), systemImage: "sparkles")
                .font(Typo.title)
                .foregroundStyle(Papier.aufNacht)
            Text(L10n.t("gratitude.subtitle"))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
                .fixedSize(horizontal: false, vertical: true)

            if let day = goodThingsDay, let mine = day.mine {
                goodThingsList(title: L10n.t("gratitude.mine"), items: mine)
                if let partner = day.partner {
                    goodThingsList(
                        title: L10n.t("gratitude.partner", ["name": appState.partnerName]),
                        items: partner
                    )
                    Text(L10n.t("gratitude.revealed"))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(Licht.lampengold)
                } else {
                    Text(L10n.t("gratitude.waiting", ["name": appState.partnerName]))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(Licht.glut)
                }
            } else {
                promptCard(
                    RelationshipSupportContent.gratitudePrompts[gratitudePromptIndex]
                        .text.resolved(L10n.lang),
                    titleKey: "gratitude.prompt"
                )
                ForEach(goodThingTexts.indices, id: \.self) { index in
                    TextField(
                        L10n.t("gratitude.item", ["n": String(index + 1)]),
                        text: $goodThingTexts[index],
                        axis: .vertical
                    )
                    .lineLimit(1...3)
                    .textFieldStyle(DreamyFieldStyle())
                }
                Button(L10n.t("gratitude.share")) { shareGoodThings() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(busy || goodThingTexts.contains {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    })
            }
        }
        .nightCard()
    }

    private func promptCard(_ text: String, titleKey: String = "repair.prompt") -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(L10n.t(titleKey))
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(Licht.lampengold)
            Text(text)
                .font(Typo.label)
                .foregroundStyle(Papier.aufNacht)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.m)
        .background(RoundedRectangle(cornerRadius: Radius.control).fill(coupleTint.blend.opacity(0.1)))
    }

    private func goodThingsList(title: String, items: [GoodThingItem]) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(title)
                .font(Typo.caption)
                .foregroundStyle(Nacht.sekundaer)
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Text("\(index + 1). \(item.text)")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Papier.aufNacht)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.m)
        .background(RoundedRectangle(cornerRadius: Radius.control).fill(Papier.nachtInnenFill))
    }

    private func kindLabel(_ kind: String) -> String {
        L10n.t("repair.kind.\(kind)")
    }

    private func replace(_ session: RepairSession) {
        sessions.removeAll { $0.id == session.id }
        sessions.insert(session, at: 0)
    }

    private func reload() async {
        guard let api = appState.api else { return }
        loading = sessions.isEmpty && hints.isEmpty && goodThingsDay == nil
        var failed = false
        do { sessions = try await api.repairSessions() } catch { failed = true }
        do { hints = try await api.considerationHints() } catch { failed = true }
        // The day record legitimately 404s before the first share — only
        // the two primary lists decide the honest failed/offline notice.
        goodThingsDay = try? await api.goodThings(dateKey: SharedDates.todayKey())
        loadFailed = failed
        loading = false
    }

    private func createRepair() {
        guard let api = appState.api, !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let prompt = RelationshipSupportContent.repairPrompts[repairPromptIndex]
                replace(try await api.createRepairSession(promptId: prompt.id))
                repairText = ""
            } catch { appState.handleAPIError(error) }
        }
    }

    private func submitRepair(session: RepairSession, kind: String) {
        guard let api = appState.api, !busy else { return }
        let text = repairText.trimmingCharacters(in: .whitespacesAndNewlines)
        busy = true
        Task {
            defer { busy = false }
            do {
                replace(try await api.submitRepairTurn(id: session.id, kind: kind, text: text))
                repairText = ""
                Haptics.shared.success()
            } catch { appState.handleAPIError(error) }
        }
    }

    private func startCooldown(_ session: RepairSession) {
        guard let api = appState.api, !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do { replace(try await api.startRepairCooldown(id: session.id, minutes: 10)) }
            catch { appState.handleAPIError(error) }
        }
    }

    private func loadVaultKey() async -> SymmetricKey? {
        let reason = L10n.t("consideration.unlock")
        return await Task.detached(priority: .userInitiated) {
            VaultKeychain.load(reason: reason)
        }.value
    }

    private func shareHint() {
        guard let api = appState.api, !busy else { return }
        let text = hintText.trimmingCharacters(in: .whitespacesAndNewlines)
        busy = true
        Task {
            defer { busy = false }
            guard let key = await loadVaultKey() else {
                appState.showToast(L10n.t("consideration.vaultNeeded"), style: .error)
                return
            }
            do {
                let meta = VaultMeta(kind: "note", caption: nil, poster: nil,
                                     duration: nil, width: nil, height: nil)
                let blob = try VaultCrypto.sealPackage(
                    meta: meta, content: Data(text.utf8), key: key)
                let hint = try await api.shareConsideration(
                    ciphertext: blob.base64EncodedString(), visibility: "gentle", hours: 24)
                hints.insert(hint, at: 0)
                decryptedHints[hint.id] = text
                hintText = ""
                Haptics.shared.success()
            } catch { appState.handleAPIError(error) }
        }
    }

    private func unlockHints() {
        Task {
            guard let key = await loadVaultKey() else {
                appState.showToast(L10n.t("consideration.vaultNeeded"), style: .error)
                return
            }
            for hint in hints {
                guard let blob = Data(base64Encoded: hint.ciphertext),
                      let opened = try? VaultCrypto.openPackage(blob, key: key),
                      let text = String(data: opened.content, encoding: .utf8) else { continue }
                decryptedHints[hint.id] = text
            }
        }
    }

    private func pauseHint(_ hint: ConsiderationHint) {
        guard let api = appState.api else { return }
        Task {
            do {
                _ = try await api.pauseConsideration(id: hint.id)
                hints.removeAll { $0.id == hint.id }
                decryptedHints[hint.id] = nil
            } catch { appState.handleAPIError(error) }
        }
    }

    private func shareGoodThings() {
        guard let api = appState.api, !busy else { return }
        let texts = goodThingTexts.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard texts.allSatisfy({ !$0.isEmpty }) else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                goodThingsDay = try await api.shareGoodThings(
                    dateKey: SharedDates.todayKey(),
                    texts: texts
                )
                goodThingTexts = ["", "", ""]
                gratitudePromptIndex = (gratitudePromptIndex + 1)
                    % RelationshipSupportContent.gratitudePrompts.count
                Haptics.shared.success()
            } catch {
                appState.handleAPIError(error)
            }
        }
    }
}
