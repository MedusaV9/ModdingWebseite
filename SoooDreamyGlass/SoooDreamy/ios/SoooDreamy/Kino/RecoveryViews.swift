import SwiftUI

// v10 „Der große Runde" — the recovery-key UX. Three pieces:
//   1. RecoveryKeyCeremonySheet — right after pairing: show the one-time key,
//      explain where it lives, offer copy. Presented from RootView.
//   2. RecoverySheet — Settings → „Sicherheitsnetz": key status, reveal/copy,
//      rotate, and the partner-replace approval flow.
//   3. Small shared bits (key display card).

/// Monospaced, grouped display of a recovery key — the key IS a paper
/// slip (Papier & Licht): dark ink on letter paper, readable on the
/// night desk and inside a paper card alike.
struct RecoveryKeyCard: View {
    let recoveryKey: String
    @State private var copied = false

    var body: some View {
        VStack(spacing: LayoutMetrics.s(10)) {
            Text(RecoveryKit.grouped(recoveryKey))
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .foregroundStyle(Tinte.dunkel)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .padding(LayoutMetrics.s(14))
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                        .fill(Papier.brief)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                                .strokeBorder(PaperLightEdge.gradient,
                                              lineWidth: Theme.hairlineWidth)
                        )
                        .elevation(.resting)
                )

            Button {
                UIPasteboard.general.string = recoveryKey
                copied = true
                Haptics.shared.success()
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    copied = false
                }
            } label: {
                Label(L10n.t(copied ? "recovery.copied" : "recovery.copy"),
                      systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }
}

/// One-time ceremony after create/join: the key is already in the (iCloud)
/// keychain — this sheet exists so a paper backup can happen while the
/// plaintext is still on screen. Dismissing it drops the plaintext for good.
struct RecoveryKeyCeremonySheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let recoveryKey: String

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                ScrollView {
                    VStack(spacing: LayoutMetrics.s(18)) {
                        Image(systemName: "key.fill")
                            .font(Typo.hero)
                            .foregroundStyle(Theme.gold)
                            .shadow(color: Theme.gold.opacity(0.7),
                                    radius: LayoutMetrics.s(22))
                            .padding(.top, LayoutMetrics.s(8))
                            .accessibilityHidden(true)

                        Text(L10n.t("recovery.ceremony.title"))
                            .font(.system(.title2, design: .rounded).weight(.heavy))
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.center)

                        Text(L10n.t("recovery.ceremony.subtitle"))
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        RecoveryKeyCard(recoveryKey: recoveryKey)

                        VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
                            // Honest storage line: probe where the key REALLY
                            // ended up instead of promising iCloud. Sideload
                            // signatures can only write the local fallback —
                            // then the paper note carries the safety net.
                            // Nacht-first (P2-B): the notes card is night —
                            // accent icons speak lamplight, the local-only
                            // warning speaks glut (wax stays material on
                            // paper only, MIGRATION_DUNKEL §4/§5).
                            if keyIsSynchronizable {
                                ceremonyPoint("icloud.fill", "recovery.ceremony.point1", Licht.lampengold)
                            } else {
                                ceremonyPoint("iphone", "recovery.ceremony.point1.local", Licht.glut)
                            }
                            ceremonyPoint("pencil.and.list.clipboard", "recovery.ceremony.point2", Licht.lampengold)
                            ceremonyPoint("eye.slash.fill", "recovery.ceremony.point3", Licht.lampengold)
                        }
                        .nightCard()

                        Button(L10n.t("recovery.ceremony.done")) {
                            Haptics.shared.success()
                            dismiss()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("recovery.ceremony.done")
                    }
                    .padding(LayoutMetrics.s(20))
                }
            }
            .navigationTitle(L10n.t("recovery.title"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()   // no accidental swipe-away of the one-time key
        .onDisappear { appState.freshRecoveryKey = nil }
    }

    private var keyIsSynchronizable: Bool {
        guard let profile = appState.servers.activeProfile else { return false }
        return SharedKeychain.recoveryKeyStorage(profileID: profile.id) == .synchronizable
    }

    private func ceremonyPoint(_ icon: String, _ key: String, _ tint: Color) -> some View {
        HStack(alignment: .top, spacing: LayoutMetrics.s(10)) {
            Image(systemName: icon)
                .font(Typo.caption)
                .foregroundStyle(tint)
                .frame(width: LayoutMetrics.s(26))
            Text(L10n.t(key))
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Settings → „Sicherheitsnetz": everything about getting back in.
struct RecoverySheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint

    /// Server-side key status (nil while loading).
    @State private var status: RecoveryKeyStatus?
    @State private var revealed = false
    @State private var confirmRotate = false
    @State private var busy = false

    /// Active partner-replace code (created in this sheet).
    @State private var replace: ReplaceCodeResponse?

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                ScrollView {
                    VStack(alignment: .leading, spacing: LayoutMetrics.s(16)) {
                        Text(L10n.t("recovery.sheet.subtitle"))
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        keyCard
                        replaceCard
                        howItWorksCard
                    }
                    .padding(LayoutMetrics.s(20))
                }
            }
            .navigationTitle(L10n.t("recovery.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.done")) { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    // MARK: My recovery key

    /// Nacht-first (Weiß-Audit, MIGRATION_DUNKEL §10): the key SECTION is
    /// a Settings container and speaks night like the replace card below
    /// — only the key itself (`RecoveryKeyCard`) stays the bright paper
    /// slip inside, because THE KEY is the paper artifact.
    private var keyCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(12)) {
            SectionHeader(title: L10n.t("recovery.key.section"), systemImage: "key.fill",
                          onPaper: false)

            HStack(spacing: LayoutMetrics.s(10)) {
                // Accent icons on night: blend for the ok state (non-text),
                // glut for the warning — wax stays material on paper only
                // (MIGRATION_DUNKEL §4/§5).
                Image(systemName: stored != nil ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(stored != nil ? coupleTint.blend : Licht.glut)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(stored != nil ? "recovery.status.stored" : "recovery.status.missing"))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Papier.aufNacht)
                    // Real storage location (probed) — honest about whether
                    // iCloud can carry the key or the paper note has to.
                    if let storageKey {
                        Text(L10n.t(storageKey))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Nacht.tertiaer)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let createdAt = status?.createdAt {
                        Text(L10n.t("recovery.status.since",
                                    ["date": AppFormatters.date(createdAt, language: L10n.lang)]))
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Nacht.tertiaer)
                    }
                }
                Spacer()
            }

            if let key = stored {
                if revealed {
                    RecoveryKeyCard(recoveryKey: key)
                } else {
                    Text(RecoveryKit.masked(key))
                        .font(.system(.callout, design: .monospaced).weight(.semibold))
                        .foregroundStyle(Nacht.sekundaer)
                }
                Button {
                    revealed.toggle()
                    Haptics.shared.tap()
                } label: {
                    Label(L10n.t(revealed ? "recovery.hide" : "recovery.reveal"),
                          systemImage: revealed ? "eye.slash" : "eye")
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            Button {
                confirmRotate = true
            } label: {
                if busy {
                    ProgressView().tint(.white).frame(maxWidth: .infinity)
                } else {
                    Label(L10n.t(stored == nil ? "recovery.issue" : "recovery.rotate"),
                          systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(busy)
            .confirmationDialog(L10n.t("recovery.rotate.confirmTitle"),
                                isPresented: $confirmRotate, titleVisibility: .visible) {
                Button(L10n.t(stored == nil ? "recovery.issue" : "recovery.rotate"),
                       role: stored == nil ? nil : .destructive) {
                    Task { await rotate() }
                }
                Button(L10n.t("common.cancel"), role: .cancel) {}
            } message: {
                Text(L10n.t(stored == nil ? "recovery.issue.confirmBody" : "recovery.rotate.confirmBody"))
            }

            Text(L10n.t("recovery.key.hint"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Nacht.tertiaer)
                .fixedSize(horizontal: false, vertical: true)
        }
        .nightCard()
    }

    // MARK: Partner replace

    /// Nacht-first (P2-B): the replace flow is a STANDARD surface — like
    /// the key section above since the Weiß-Audit. The replace code
    /// itself stays a bright paper slip INSIDE the night card
    /// (wax ink needs paper — MIGRATION_DUNKEL §5).
    private var replaceCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(12)) {
            SectionHeader(title: L10n.t("recovery.replace.section"), systemImage: "person.2.fill",
                          onPaper: false)

            Text(L10n.t("recovery.replace.explain", ["name": appState.partnerName]))
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
                .fixedSize(horizontal: false, vertical: true)

            if let replace {
                VStack(spacing: LayoutMetrics.s(8)) {
                    // "Partner hilft": the QR carries server + couple
                    // code + replace code as a sooodreamy://rejoin link —
                    // the other device scans it and is back in ONE step.
                    if let qrImage = partnerHelpQR(replace) {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: LayoutMetrics.s(220))
                            .padding(LayoutMetrics.s(12))
                            .background(
                                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                    .fill(.white)
                            )
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel(L10n.t("recovery.replace.qrA11y"))

                        Text(L10n.t("recovery.replace.qrHint"))
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Nacht.sekundaer)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // The replace code wears stamp ink on a bright paper
                    // slip — Wachs.rot is material ON PAPER only, so the
                    // slip stays brief inside the night card (same law as
                    // RecoveryKeyCard).
                    Text(replace.replaceCode)
                        .font(.system(.title2, design: .monospaced).weight(.heavy))
                        .kerning(3)
                        .foregroundStyle(Wachs.rot)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, LayoutMetrics.s(12))
                        .background(
                            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                .fill(Papier.brief)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                        .strokeBorder(PaperLightEdge.gradient,
                                                      lineWidth: Theme.hairlineWidth)
                                )
                        )
                        .textSelection(.enabled)

                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if let remaining = RecoveryKit.replaceCodeRemaining(
                            expiresAt: replace.expiresAt, now: context.date) {
                            Text(L10n.t("recovery.replace.expires",
                                        ["time": RecoveryKit.countdownLabel(remaining)]))
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .foregroundStyle(Nacht.sekundaer)
                        } else {
                            // Expiry warning on night speaks glut — wax
                            // stays on paper (MIGRATION_DUNKEL §4).
                            Text(L10n.t("recovery.replace.expired"))
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .foregroundStyle(Licht.glut)
                        }
                    }

                    Button(L10n.t("recovery.replace.cancel"), role: .destructive) {
                        Task { await cancelReplace() }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            } else {
                Button {
                    Task { await createReplace() }
                } label: {
                    Label(L10n.t("recovery.replace.generate"), systemImage: "key.viewfinder")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(appState.partner == nil || busy)
            }

            Text(L10n.t("recovery.replace.hint"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Nacht.tertiaer)
                .fixedSize(horizontal: false, vertical: true)
        }
        .nightCard()
    }

    /// Nacht-first (P2-B): explainer card — standard surface, night inks.
    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
            SectionHeader(title: L10n.t("recovery.how.section"), systemImage: "lifepreserver",
                          onPaper: false)
            point("1.circle.fill", "recovery.how.point1")
            point("2.circle.fill", "recovery.how.point2")
            point("3.circle.fill", "recovery.how.point3")
        }
        .nightCard()
    }

    private func point(_ icon: String, _ key: String) -> some View {
        HStack(alignment: .top, spacing: LayoutMetrics.s(10)) {
            Image(systemName: icon)
                .font(Typo.caption)
                // Accent icons on night speak lamplight (§4).
                .foregroundStyle(Licht.lampengold)
            Text(L10n.t(key))
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Data

    private var stored: String? { appState.storedRecoveryKey }

    /// L10n key for the probed keychain location — nil when no key exists.
    private var storageKey: String? {
        guard let profile = appState.servers.activeProfile else { return nil }
        switch SharedKeychain.recoveryKeyStorage(profileID: profile.id) {
        case .synchronizable: return "recovery.storage.synced"
        case .localOnly: return "recovery.storage.local"
        case .missing: return nil
        }
    }

    /// QR payload = sooodreamy://rejoin deep link (docs/REJOIN-QR.md) so the
    /// partner's phone reconnects with a single scan.
    private func partnerHelpQR(_ replace: ReplaceCodeResponse) -> UIImage? {
        guard let profile = appState.servers.activeProfile,
              let coupleCode = appState.couple?.code ?? profile.coupleCode else { return nil }
        let link = RejoinLink.partnerHelp(server: profile.urlString,
                                          code: coupleCode,
                                          replaceCode: replace.replaceCode)
        guard let payload = link.url?.absoluteString else { return nil }
        return QRGenerator.image(for: payload)
    }

    private func load() async {
        guard let api = appState.api else { return }
        status = try? await api.recoveryKeyStatus()
    }

    private func rotate() async {
        guard let api = appState.api, let profile = appState.servers.activeProfile else { return }
        busy = true
        defer { busy = false }
        do {
            let issued = try await api.issueRecoveryKey()
            _ = SharedKeychain.setRecoveryKey(issued.recoveryKey, profileID: profile.id)
            status = RecoveryKeyStatus(configured: true, createdAt: issued.createdAt)
            revealed = true
            appState.showToast(L10n.t(issued.rotated ? "recovery.rotated" : "recovery.issued"),
                               style: .success)
            Haptics.shared.success()
        } catch {
            appState.handleAPIError(error)
        }
    }

    private func createReplace() async {
        guard let api = appState.api else { return }
        busy = true
        defer { busy = false }
        do {
            replace = try await api.createReplaceCode()
            Haptics.shared.success()
        } catch {
            appState.handleAPIError(error)
        }
    }

    private func cancelReplace() async {
        guard let api = appState.api else { return }
        do {
            try await api.cancelReplaceCode()
            replace = nil
            appState.showToast(L10n.t("recovery.replace.cancelled"), style: .info)
        } catch {
            appState.handleAPIError(error)
        }
    }
}
