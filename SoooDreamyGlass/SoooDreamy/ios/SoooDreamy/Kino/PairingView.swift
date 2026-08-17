import SwiftUI

/// Create or join a couple on the active server (incl. profile setup + QR).
/// v10 adds the third path: REJOIN — re-attach your own slot of a full
/// couple with the recovery key (or a partner-approved replace code).
/// The multi-device wave adds the fourth: LINK — „Ich habe schon ein
/// Gerät": attach THIS device to the member's existing account with a
/// link code / QR from the signed-in device (no profile setup needed).
struct PairingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint

    enum Mode: Hashable { case create, join, rejoin, link }

    /// The reconnect screen shows exactly TWO choices (scan / type) —
    /// the manual fields only appear after the person picks typing.
    enum RejoinEntry: Hashable { case options, manual }

    @State private var mode: Mode = .create
    @State private var name = ""
    @State private var avatar = Theme.avatarEmojis[0]
    /// FullRelease N3-Kino: the ink chosen in the first-launch cinema
    /// carries through — the color you picked at the ink wells is the
    /// color offered here (still freely changeable).
    @State private var colorHex = CinematicIntroGate.pickedInkHex
        ?? Theme.memberColors[0]
    @State private var code = ""
    @State private var busy = false
    @State private var showScanner = false
    @State private var showServerPicker = false

    // Device link (multi-device)
    @State private var linkCodeInput = ""

    // Rejoin (v10)
    @State private var rejoinEntry: RejoinEntry = .options
    @State private var recoveryKeyInput = ""
    @State private var useReplaceCode = false
    @State private var replaceCodeInput = ""

    var body: some View {
        ZStack {
            DreamyBackground()
            ScrollView {
                VStack(spacing: LayoutMetrics.s(20)) {
                    header

                    // Mode switch
                    HStack(spacing: LayoutMetrics.s(10)) {
                        modeButton(.create, label: L10n.t("pairing.create"), icon: "plus.heart.fill")
                        modeButton(.join, label: L10n.t("pairing.join"), icon: "link")
                        modeButton(.rejoin, label: L10n.t("pairing.rejoin"), icon: "key.horizontal.fill")
                    }

                    // Fourth path, deliberately quieter than the big three:
                    // this person already has the app running elsewhere.
                    linkModeRow

                    if mode == .rejoin {
                        rejoinContent
                    } else if mode == .link {
                        linkContent
                    } else {
                        profileCard

                        // Join: code entry + QR scan — a STANDARD surface
                        // (Nacht-first P2-B): the code is a key, not an
                        // artifact; only the profile briefbogen stays paper.
                        if mode == .join {
                            VStack(spacing: LayoutMetrics.s(12)) {
                                TextField(L10n.t("pairing.codePlaceholder"), text: $code)
                                    .textFieldStyle(DreamyFieldStyle())
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled()
                                    .accessibilityLabel(L10n.t("pairing.codeFieldA11y"))
                                    .accessibilityHint(L10n.t("pairing.codeFieldHintA11y"))
                                    .accessibilityIdentifier("pairing.codeField")
                                    .onChange(of: code) { _, newValue in
                                        code = RecoveryKit.normalizedCode(
                                            newValue, length: RecoveryKit.pairingCodeLength)
                                    }
                                Button {
                                    // Quiet tap-frame feedback (F6) — the
                                    // scanner sheet arrives a beat later.
                                    AppCue.click.play()
                                    showScanner = true
                                } label: {
                                    Label(L10n.t("pairing.scanQR"), systemImage: "qrcode.viewfinder")
                                }
                                .buttonStyle(SecondaryButtonStyle())
                            }
                            .nightCard()
                        }
                    }

                    // Primary action — hidden while the reconnect screen
                    // only shows its two entry choices (nothing to submit).
                    if !(mode == .rejoin && rejoinEntry == .options && !hasKeychainShortcut) {
                        Button {
                            Task { await submit() }
                        } label: {
                            if busy {
                                // The spinner rides the PrimaryButtonStyle
                                // gradient platter — same computed ink as
                                // the label it replaces, hard white read
                                // 2.94:1 on the fallback stops
                                // (Schlussrunde 5).
                                ProgressView().tint(coupleTint.onGradient)
                            } else {
                                Text(primaryLabel)
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(busy || !isValid)
                        .accessibilityIdentifier("pairing.submit")
                    }
                }
                .padding(LayoutMetrics.s(20))
                .contentColumn(.reading)
            }
        }
        .sheet(isPresented: $showScanner) {
            NavigationStack {
                QRCodeScanner { text in
                    handleScan(text)
                }
                .ignoresSafeArea()
                .navigationTitle(L10n.t("pairing.scanQR"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.t("common.cancel")) { showScanner = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showServerPicker) {
            ServerListSheet()
        }
        .onAppear { prefillRejoin() }
        // A rejoin link may arrive while this screen is already open
        // (URL scheme, notification) — take it over immediately.
        .onChange(of: appState.pendingRejoin) { _, link in
            if link != nil { consumePendingRejoin() }
        }
        // Same for a device link that could not auto-complete.
        .onChange(of: appState.pendingDeviceLink) { _, link in
            if link != nil { consumePendingDeviceLink() }
        }
    }

    private var headerEmoji: String {
        switch mode {
        case .rejoin: return "🗝️"
        case .link: return "📲"
        default: return "💞"
        }
    }

    private var headerTitleKey: String {
        switch mode {
        case .rejoin: return "pairing.rejoin.title"
        case .link: return "pairing.link.title"
        default: return "pairing.title"
        }
    }

    private var headerSubtitleKey: String {
        switch mode {
        case .rejoin: return "pairing.rejoin.subtitle"
        case .link: return "pairing.link.subtitle"
        default: return "pairing.subtitle"
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(headerEmoji)
                .font(.scaled(56))
                .accessibilityHidden(true)
            Text(L10n.t(headerTitleKey))
                .font(Typo.hero)
                .foregroundStyle(Theme.textPrimary)
            Text(L10n.t(headerSubtitleKey))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            if let profile = appState.servers.activeProfile {
                Button {
                    showServerPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "server.rack")
                            .font(Typo.caption)
                        Text(profile.name)
                            .font(Typo.caption)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(Typo.caption)
                    }
                    // Nacht-first (P2-B): the server chip is quiet night
                    // chrome, not a paper slip — bright paper stays with
                    // the ONE briefbogen hero below (MIGRATION_DUNKEL §3).
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, LayoutMetrics.s(12))
                    .background(
                        Capsule().fill(Papier.nachtInnenFill)
                            .overlay(Capsule().strokeBorder(
                                Nacht.naht, lineWidth: Theme.hairlineWidth))
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .accessibilityLabel(L10n.t("pairing.serverA11y", ["name": profile.name]))
                .accessibilityHint(L10n.t("pairing.serverHintA11y"))
            }
        }
        .padding(.top, LayoutMetrics.s(12))
    }

    /// The profile card is the screen's ONE briefbogen hero — who you
    /// are, written in ink on the letter paper.
    private var profileCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(14)) {
            Text(L10n.t("pairing.profileTitle"))
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(Tinte.dunkel)

            HStack(spacing: LayoutMetrics.s(14)) {
                // Mirrors the picker selections below — decorative for VoiceOver.
                EmojiAvatarView(emoji: avatar, colorHex: colorHex, size: LayoutMetrics.s(64))
                    .accessibilityHidden(true)
                TextField(L10n.t("pairing.yourName"), text: $name)
                    .paperField()
                    .accessibilityLabel(L10n.t("pairing.yourName"))
                    .accessibilityIdentifier("pairing.nameField")
            }

            Text(L10n.t("pairing.avatar"))
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(Tinte.sekundaer)
            EmojiPickerGrid(emojis: Theme.avatarEmojis, selection: $avatar)

            Text(L10n.t("pairing.color"))
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(Tinte.sekundaer)
            MemberColorPicker(selection: $colorHex)
        }
        .paperCard(.briefbogen)
    }

    // MARK: Device link („Ich habe schon ein Gerät")

    /// Entry row below the three big paths — visually quieter, because it
    /// only applies to people who already run the app on another device.
    private var linkModeRow: some View {
        Button {
            withAnimation(Theme.Motion.settle) { mode = .link }
            Haptics.shared.tap()
        } label: {
            HStack(spacing: LayoutMetrics.s(12)) {
                Image(systemName: "ipad.and.iphone")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("pairing.link"))
                        .font(.system(.footnote, design: .rounded).weight(.bold))
                    Text(L10n.t("pairing.link.sub"))
                        .font(.system(.caption2, design: .rounded))
                        // No free-hand dimming on the platter: 0.85 pushed
                        // the computed ink back under the 4.5:1 floor —
                        // the smaller caption2 carries the hierarchy alone
                        // (Schlussrunde 5).
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(.caption, design: .rounded).weight(.bold))
            }
            // Computed ink + platter on the selected state: white read only
            // 2.94:1 on the static brand gradient (Schlussrunde 5). The
            // resting row is a quiet night chip (Nacht-first P2-B) — it's
            // deliberately the QUIETEST of the four paths.
            .foregroundStyle(mode == .link ? Theme.onHero : Theme.textSecondary)
            .padding(.vertical, LayoutMetrics.s(12))
            .padding(.horizontal, LayoutMetrics.s(14))
            .frame(maxWidth: .infinity)
            .background {
                if mode == .link {
                    Theme.heroPlatter(in: RoundedRectangle(cornerRadius: Radius.control,
                                                           style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(Papier.nachtInnenFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.control,
                                             style: .continuous)
                                .strokeBorder(Nacht.naht,
                                              lineWidth: Theme.hairlineWidth)
                        )
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(mode == .link ? [.isSelected] : [])
    }

    /// Code entry + QR scan for the device hand-off. No profile fields:
    /// the member already exists — this device just joins their seats.
    private var linkContent: some View {
        // Nacht-first (P2-B): the device hand-off is plumbing, not an
        // artifact — night card + night inks (MIGRATION_DUNKEL §4).
        VStack(alignment: .leading, spacing: LayoutMetrics.s(14)) {
            Text(L10n.t("pairing.link.reassure"))
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
                .fixedSize(horizontal: false, vertical: true)

            TextField(L10n.t("pairing.link.codePlaceholder"), text: $linkCodeInput)
                .textFieldStyle(DreamyFieldStyle(font: .system(.body, design: .monospaced)))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .accessibilityLabel(L10n.t("pairing.link.codeA11y"))
                .onChange(of: linkCodeInput) { _, newValue in
                    linkCodeInput = DeviceLinkCode.normalized(newValue)
                }

            Button {
                AppCue.click.play()
                showScanner = true
            } label: {
                Label(L10n.t("pairing.scanQR"), systemImage: "qrcode.viewfinder")
            }
            .buttonStyle(SecondaryButtonStyle())

            Text(L10n.t("pairing.link.help"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Nacht.tertiaer)
                .fixedSize(horizontal: false, vertical: true)
        }
        .nightCard()
    }

    /// A device link that could not auto-complete (unknown server, failed
    /// redemption) — take over its code so nothing is typed twice.
    private func consumePendingDeviceLink() {
        guard let link = appState.pendingDeviceLink else { return }
        appState.pendingDeviceLink = nil
        withAnimation(Theme.Motion.settle) {
            mode = .link
            linkCodeInput = link.code
        }
    }

    // MARK: Rejoin (radically simple)

    /// The whole reconnect area: a soft reassurance line, then AT MOST two
    /// visible choices (scan / type). The keychain shortcut replaces both
    /// when this device still holds its recovery key.
    @ViewBuilder
    private var rejoinContent: some View {
        Text(L10n.t("pairing.rejoin.reassure"))
            .font(.system(.footnote, design: .rounded))
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, LayoutMetrics.s(8))

        if hasKeychainShortcut {
            keychainShortcutCard
        } else if rejoinEntry == .options {
            rejoinOptionButton(icon: "qrcode.viewfinder",
                               titleKey: "pairing.rejoin.scan",
                               subtitleKey: "pairing.rejoin.scan.sub",
                               hero: true) {
                showScanner = true
            }
            rejoinOptionButton(icon: "keyboard",
                               titleKey: "pairing.rejoin.type",
                               subtitleKey: "pairing.rejoin.type.sub",
                               hero: false) {
                withAnimation(Theme.Motion.settle) { rejoinEntry = .manual }
            }
        } else {
            rejoinManualCard
        }
    }

    /// This device still knows its recovery key — one tap and you're back.
    /// Nacht-first (P2-B): a reassuring night card — the key icon speaks
    /// in lamplight (accent TEXT/icon rule, MIGRATION_DUNKEL §4).
    private var keychainShortcutCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(12)) {
            HStack(spacing: LayoutMetrics.s(10)) {
                Image(systemName: "key.icloud.fill")
                    .foregroundStyle(Licht.lampengold)
                Text(L10n.t("pairing.rejoin.keyFound"))
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(Papier.aufNacht)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(LayoutMetrics.s(12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Papier.nachtInnenFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .strokeBorder(Nacht.naht,
                                          lineWidth: Theme.hairlineWidth)
                    )
            )

            Button {
                AppCue.click.play()
                showScanner = true
            } label: {
                Label(L10n.t("pairing.rejoin.scanInstead"), systemImage: "qrcode.viewfinder")
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(Nacht.sekundaer)
            }
            .buttonStyle(.plain)
        }
        .nightCard()
    }

    /// One of the two big reconnect choices.
    private func rejoinOptionButton(icon: String, titleKey: String,
                                    subtitleKey: String, hero: Bool,
                                    action: @escaping () -> Void) -> some View {
        Button {
            Haptics.shared.tap()
            action()
        } label: {
            HStack(spacing: LayoutMetrics.s(14)) {
                Image(systemName: icon)
                    .font(Typo.title)
                    // Computed ink + platter on the hero circle
                    // (Schlussrunde 5); the quiet circle sits in night.
                    .foregroundStyle(hero ? Theme.onHero : Papier.aufNacht)
                    .frame(width: LayoutMetrics.s(52), height: LayoutMetrics.s(52))
                    .background {
                        if hero {
                            Theme.heroPlatter(in: Circle())
                        } else {
                            Circle().fill(Papier.nachtInnenFill)
                        }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.t(titleKey))
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Papier.aufNacht)
                    Text(L10n.t(subtitleKey))
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Nacht.sekundaer)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Typo.caption)
                    .foregroundStyle(Nacht.tertiaer)
            }
        }
        .buttonStyle(.plain)
        // Nacht-first (P2-B): the reconnect choices are doors, not
        // artifacts — night cards; the hero circle still carries the
        // couple platter as the one bright accent.
        .nightCard()
    }

    /// Manual entry — only after „Code eintippen" was chosen.
    /// Nacht-first (P2-B): a standard night card with matte night wells
    /// (paperField → DreamyFieldStyle, MIGRATION_DUNKEL §4).
    private var rejoinManualCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(14)) {
            TextField(L10n.t("pairing.codePlaceholder"), text: $code)
                .textFieldStyle(DreamyFieldStyle())
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .accessibilityLabel(L10n.t("pairing.codeFieldA11y"))
                .accessibilityHint(L10n.t("pairing.codeFieldHintA11y"))
                .onChange(of: code) { _, newValue in
                    code = RecoveryKit.normalizedCode(newValue, length: RecoveryKit.pairingCodeLength)
                }

            if useReplaceCode {
                TextField(L10n.t("pairing.rejoin.replacePlaceholder"), text: $replaceCodeInput)
                    .textFieldStyle(DreamyFieldStyle())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onChange(of: replaceCodeInput) { _, newValue in
                        // Custom replace codes — uppercase + cap only,
                        // inner characters stay untouched.
                        replaceCodeInput = RecoveryKit.normalizedFlexibleCode(newValue)
                    }
            } else {
                TextField(L10n.t("pairing.rejoin.keyPlaceholder"), text: $recoveryKeyInput)
                    .textFieldStyle(DreamyFieldStyle(font: .system(.footnote, design: .monospaced)))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Toggle(isOn: $useReplaceCode.animation(Theme.Motion.settle)) {
                Text(L10n.t("pairing.rejoin.replaceToggle"))
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(Nacht.sekundaer)
            }
            // Toggle fill is non-text — blend stays legal on night
            // (icons/fills ≥ 3:1, MIGRATION_DUNKEL §4).
            .tint(coupleTint.blend)

            Text(L10n.t("pairing.rejoin.help"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Nacht.tertiaer)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                withAnimation(Theme.Motion.settle) { rejoinEntry = .options }
            } label: {
                Label(L10n.t("pairing.rejoin.backToOptions"), systemImage: "chevron.left")
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(Nacht.sekundaer)
            }
            .buttonStyle(.plain)
        }
        .nightCard()
    }

    /// True when this device can reconnect with a single tap (remembered
    /// couple code + recovery key in the keychain, no manual overrides).
    private var hasKeychainShortcut: Bool {
        keychainRecoveryKey != nil && recoveryKeyInput.isEmpty && !useReplaceCode
            && !code.isEmpty
    }

    private var keychainRecoveryKey: String? {
        guard let profile = appState.servers.activeProfile else { return nil }
        return SharedKeychain.recoveryKey(profileID: profile.id)
    }

    /// Prefill code + key so a rejoin after session loss is one tap.
    private func prefillRejoin() {
        guard let profile = appState.servers.activeProfile else { return }
        if code.isEmpty, let remembered = profile.coupleCode {
            code = remembered
        }
        // A remembered code + keychain key means this device was in the
        // couple before — start on the rejoin tab, not on "create".
        if profile.coupleCode != nil && keychainRecoveryKey != nil {
            mode = .rejoin
        }
        // A page-1 invite scan parked the couple code — the scan IS the
        // decision: land in join mode with the code already in place
        // (explicit action, so it outranks the rejoin auto-detection).
        if let invite = PendingInvite.consume() {
            mode = .join
            code = RecoveryKit.normalizedCode(invite,
                                              length: RecoveryKit.pairingCodeLength)
        }
        consumePendingRejoin()
        consumePendingDeviceLink()
    }

    /// An opened/scanned rejoin link that could not auto-complete —
    /// take over whatever it carried so nothing is typed twice.
    private func consumePendingRejoin() {
        guard let link = appState.pendingRejoin else { return }
        appState.pendingRejoin = nil
        withAnimation(Theme.Motion.settle) {
            mode = .rejoin
            if let linkCode = link.code { code = linkCode }
            if let replace = link.replaceCode {
                useReplaceCode = true
                replaceCodeInput = RecoveryKit.normalizedFlexibleCode(replace)
                rejoinEntry = .manual
            } else if let key = link.recoveryKey {
                useReplaceCode = false
                recoveryKeyInput = key
                rejoinEntry = .manual
            }
        }
    }

    private func modeButton(_ m: Mode, label: String, icon: String) -> some View {
        Button {
            withAnimation(Theme.Motion.settle) { mode = m }
            Haptics.shared.tap()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(Typo.title)
                Text(label)
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }
            // Computed ink + platter on the selected tab (Schlussrunde 5);
            // Nacht-first (P2-B): the resting tabs are quiet night chips —
            // bright paper stays with the profile briefbogen hero.
            .foregroundStyle(mode == m ? Theme.onHero : Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, LayoutMetrics.s(16))
            .background {
                if mode == m {
                    Theme.heroPlatter(in: RoundedRectangle(cornerRadius: Radius.control,
                                                           style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(Papier.nachtInnenFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.control,
                                             style: .continuous)
                                .strokeBorder(Nacht.naht,
                                              lineWidth: Theme.hairlineWidth)
                        )
                }
            }
        }
        .buttonStyle(.plain)
        // VoiceOver hears which of the three paths is active (P2-9).
        .accessibilityAddTraits(mode == m ? [.isSelected] : [])
        .accessibilityIdentifier(modeIdentifier(m))
    }

    /// Stable UI-test handles for the three big paths (P1-D list).
    private func modeIdentifier(_ m: Mode) -> String {
        switch m {
        case .create: return "pairing.mode.create"
        case .join: return "pairing.mode.join"
        case .rejoin: return "pairing.mode.rejoin"
        case .link: return "pairing.mode.link"
        }
    }

    private var primaryLabel: String {
        switch mode {
        case .create: return L10n.t("pairing.create")
        case .join: return L10n.t("pairing.join")
        case .rejoin: return L10n.t("pairing.rejoin")
        case .link: return L10n.t("pairing.link.action")
        }
    }

    private var isValid: Bool {
        let nameOK = !name.trimmingCharacters(in: .whitespaces).isEmpty
        switch mode {
        case .create:
            return nameOK
        case .join:
            return nameOK && code.count == RecoveryKit.pairingCodeLength
        case .rejoin:
            guard code.count == RecoveryKit.pairingCodeLength else { return false }
            if useReplaceCode {
                // Standard 8-char AND custom codes (server-flexible, v10.1).
                return RecoveryKit.looksLikeReplaceCode(replaceCodeInput)
            }
            if keychainRecoveryKey != nil && recoveryKeyInput.isEmpty { return true }
            return RecoveryKit.looksLikeRecoveryKey(recoveryKeyInput)
        case .link:
            // No profile fields — the member already exists; only the
            // complete 8-char device code gates the button.
            return DeviceLinkCode.isComplete(linkCodeInput)
        }
    }

    private func handleScan(_ text: String) {
        showScanner = false
        // Device hand-off QR (sooodreamy://link) from a signed-in device —
        // server + one-time code in one; redeems without further typing.
        if let link = DeviceLinkURL.parse(text) {
            Haptics.shared.success()
            appState.applyDeviceLink(link)
            return
        }
        // Rejoin QR (admin panel / partner's phone) — carries server
        // plus proof; a complete one reconnects WITHOUT any further input.
        if let link = RejoinLink.parse(text) {
            Haptics.shared.success()
            appState.applyRejoinLink(link)
            return
        }
        if let payload = PairQRPayload.decode(text) {
            // Server + code in one: add/activate that server, then prefill code.
            if let normalized = ServerProfile.normalize(payload.server) {
                if let existing = appState.servers.profiles.first(where: { $0.urlString == normalized }) {
                    appState.servers.setActive(id: existing.id)
                } else if let profile = appState.servers.add(name: normalized, urlString: normalized) {
                    appState.servers.setActive(id: profile.id)
                }
            }
            code = payload.code.uppercased()
            mode = .join
        } else if mode == .link {
            // A bare device code scanned on the link screen stays there.
            linkCodeInput = DeviceLinkCode.normalized(text)
        } else if mode == .rejoin {
            // A bare couple code scanned on the reconnect screen stays there.
            code = RecoveryKit.normalizedCode(text, length: RecoveryKit.pairingCodeLength)
            rejoinEntry = .manual
        } else {
            code = RecoveryKit.normalizedCode(text, length: RecoveryKit.pairingCodeLength)
            mode = .join
        }
        Haptics.shared.success()
    }

    private func submit() async {
        guard let profile = appState.servers.activeProfile,
              let url = profile.baseURL else { return }
        busy = true
        defer { busy = false }
        // Device link: no profile fields (the member already exists), and
        // performDeviceLink owns the whole success/error surface — sound,
        // completeAuth and every toast from the docs/API.md error catalog.
        if mode == .link {
            await appState.performDeviceLink(code: linkCodeInput,
                                             profileID: profile.id, baseURL: url)
            return
        }
        let api = API(baseURL: url, token: nil)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        do {
            let auth: AuthResponse
            switch mode {
            case .create:
                auth = try await api.createCouple(name: trimmedName, avatar: avatar, color: "#" + colorHex)
            case .join:
                auth = try await api.joinCouple(code: code, name: trimmedName, avatar: avatar, color: "#" + colorHex)
            case .rejoin:
                if useReplaceCode {
                    // Keep the slot's existing name/avatar/color — the member
                    // is the same person, just on a new device. Outer
                    // whitespace goes, inner characters stay (custom codes).
                    let replaceCode = replaceCodeInput
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    auth = try await api.rejoin(code: code,
                                                replaceCode: replaceCode,
                                                name: nil, avatar: nil, color: nil)
                } else {
                    let key = recoveryKeyInput.isEmpty
                        ? (keychainRecoveryKey ?? "")
                        : RecoveryKit.normalizedRecoveryKey(recoveryKeyInput)
                    auth = try await api.rejoin(code: code, recoveryKey: key)
                }
            case .link:
                return // handled above — kept for exhaustiveness
            }
            // Welle 7 [30]: a join that completes the couple hands the whole
            // arrival to the color-merge ceremony (ONE cue — one-channel
            // rule); rejoin is a repair and keeps the familiar tada. Only
            // when no ceremony took over does the tada speak here.
            appState.completeAuth(profileID: profile.id, auth: auth,
                                  arrival: mode == .rejoin ? nil : .paired)
            if appState.pairingCeremony == nil {
                SoundEngine.shared.play(.tada)
                Haptics.shared.success()
            }
        } catch let error as APIError {
            handleSubmitError(error)
        } catch {
            appState.showToast(error.localizedDescription, style: .error)
            Haptics.shared.warning()
        }
    }

    private func handleSubmitError(_ error: APIError) {
        if case .http(let status, let codeStr, _, _) = error {
            switch (status, codeStr) {
            case (404, _), (_, "unknown_code"):
                appState.showToast(L10n.t("pairing.unknownCode"), style: .error)
            case (409, "couple_full"), (409, .none):
                // Both slots taken — that's exactly what rejoin is for.
                appState.showToast(L10n.t("pairing.coupleFullRejoin"), style: .info)
                withAnimation(Theme.Motion.settle) { mode = .rejoin }
            case (403, "bad_recovery_key"):
                appState.showToast(L10n.t("pairing.rejoin.badKey"), style: .error)
            case (403, "bad_replace_code"):
                appState.showToast(L10n.t("pairing.rejoin.badReplace"), style: .error)
            case (403, "session_revoked"):
                appState.showToast(L10n.t("pairing.rejoin.revoked"), style: .error)
            default:
                appState.showToast(error.localizedDescription, style: .error)
            }
        } else {
            appState.showToast(error.localizedDescription, style: .error)
        }
        Haptics.shared.warning()
    }
}
