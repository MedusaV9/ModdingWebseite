import SwiftUI

/// „Geräte" — the device manager of MY member: every session (iPhone,
/// iPad, …) with a "this device" marker, per-session revoke, and the
/// add-device hand-off — a one-time link code as QR + tappable text with
/// a live TTL countdown. The partner never appears here: device
/// management is a per-member concern (docs/API.md „Multi-device
/// sessions & fanout").
struct DeviceManagerSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint

    @State private var sessions: [DeviceSession] = []
    @State private var loading = true
    @State private var loadFailed = false

    @State private var linkCode: LinkCodeResponse?
    @State private var minting = false
    @State private var copied = false

    @State private var revokeTarget: DeviceSession?
    @State private var confirmRevoke = false
    @State private var revokingIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showBlobs: false)
                ScrollView {
                    VStack(spacing: LayoutMetrics.s(16)) {
                        addDeviceCard
                        sessionsCard
                    }
                    .padding(LayoutMetrics.s(16))
                    .contentColumn(.reading)
                }
            }
            .navigationTitle(L10n.t("devices.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("common.done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent else { return }
            switch event.type {
            case .deviceLinked:
                // The minted code was just redeemed — the QR did its job.
                withAnimation(Theme.Motion.settle) { linkCode = nil }
                Task { await load() }
            case .sessionsChanged:
                // A device seat of MY member changed (linked, revoked,
                // expired — contract v11): the list reloads itself, no
                // matter which device caused it. Old servers never send
                // this frame; `device_linked` keeps covering them.
                if event.decode(SessionsChangedPayload.self)?.memberId == appState.memberId {
                    Task { await load() }
                }
            default:
                break
            }
        }
        .confirmationDialog(L10n.t("devices.revokeConfirm"),
                            isPresented: $confirmRevoke, titleVisibility: .visible,
                            presenting: revokeTarget) { session in
            Button(L10n.t("devices.revoke"), role: .destructive) {
                Task { await revoke(session) }
            }
            Button(L10n.t("common.cancel"), role: .cancel) {}
        } message: { session in
            Text(session.deviceName ?? L10n.t("devices.fallbackName"))
        }
    }

    private var phase: SurfacePhase {
        SurfaceState.resolve(
            loading: loading,
            hasContent: !sessions.isEmpty,
            connected: appState.socket.state == .connected,
            requestFailed: loadFailed
        )
    }

    // MARK: Add device (link code + QR + countdown)

    private var addDeviceCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(14)) {
            SectionHeader(title: L10n.t("devices.add"), systemImage: "plus.viewfinder")

            if let linkCode {
                mintedCodeContent(linkCode)
            } else {
                Text(L10n.t("devices.add.hint"))
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Haptics.shared.tap()
                    Task { await mintCode() }
                } label: {
                    Label(L10n.t(minting ? "devices.add.minting" : "devices.add.action"),
                          systemImage: "qrcode")
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(minting)
            }
        }
        .nightCard(grain: false)
    }

    /// QR + tappable code + live countdown — everything the NEW device
    /// needs, on one card. When the TTL runs out the card says so honestly
    /// and offers a fresh code instead of a dead QR.
    @ViewBuilder
    private func mintedCodeContent(_ minted: LinkCodeResponse) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let remaining = RecoveryKit.replaceCodeRemaining(
                expiresAt: minted.expiresAt, now: context.date) {
                VStack(spacing: LayoutMetrics.s(12)) {
                    if let qr = QRGenerator.image(for: deepLinkPayload(minted)) {
                        Image(uiImage: qr)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: LayoutMetrics.s(180), height: LayoutMetrics.s(180))
                            .padding(LayoutMetrics.s(10))
                            .background(
                                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                    .fill(.white)
                            )
                            .accessibilityLabel(L10n.t("devices.add.qrA11y"))
                    }

                    Button {
                        UIPasteboard.general.string = minted.linkCode
                        copied = true
                        Haptics.shared.success()
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            copied = false
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(minted.linkCode.map(String.init).joined(separator: " "))
                                .font(.system(.title2, design: .monospaced).weight(.heavy))
                                .foregroundStyle(Licht.lampengold)
                            Text(L10n.t(copied ? "common.copied" : "devices.add.tapToCopy"))
                                .font(.system(.caption2, design: .rounded))
                                .foregroundStyle(Nacht.tertiaer)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("devices.add.codeA11y",
                                               ["code": minted.linkCode.map(String.init).joined(separator: ", ")]))

                    PillTag(text: L10n.t("devices.add.expires",
                                         ["time": RecoveryKit.countdownLabel(remaining)]),
                            tint: coupleTint.blend)

                    Text(L10n.t("devices.add.scanHint"))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Nacht.tertiaer)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: LayoutMetrics.s(10)) {
                    Text(L10n.t("devices.add.expired"))
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .foregroundStyle(Nacht.sekundaer)
                    Button {
                        Haptics.shared.tap()
                        Task { await mintCode() }
                    } label: {
                        Label(L10n.t(minting ? "devices.add.minting" : "devices.add.again"),
                              systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(minting)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// The QR payload — the server-built deep link when present, otherwise
    /// the same `sooodreamy://link?…` built locally (identical content, so
    /// the QR never depends on the optional response field).
    private func deepLinkPayload(_ minted: LinkCodeResponse) -> String {
        if let deepLink = minted.deepLink { return deepLink }
        let server = minted.server ?? appState.servers.activeProfile?.urlString
        return DeviceLinkURL(server: server, code: minted.linkCode).url?.absoluteString
            ?? minted.linkCode
    }

    // MARK: Sessions list

    private var sessionsCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(12)) {
            SectionHeader(title: L10n.t("devices.section.list"),
                          systemImage: "ipad.and.iphone")

            switch phase {
            case .loading:
                VStack(spacing: LayoutMetrics.s(10)) {
                    PaperSkeleton(kind: .line(width: nil), onNacht: true)
                    PaperSkeleton(kind: .line(width: LayoutMetrics.s(200)), onNacht: true)
                    PaperSkeleton(kind: .line(width: LayoutMetrics.s(150)), onNacht: true)
                }
            case .content:
                let active = sessions.filter { !$0.isRevoked }
                Text(L10n.t("devices.count",
                            ["count": String(active.count),
                             "max": String(MultiDeviceRules.maxSessionsPerMember)]))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Nacht.tertiaer)
                ForEach(sessions) { session in
                    sessionRow(session)
                    if session.id != sessions.last?.id {
                        Divider().overlay(Nacht.naht)
                    }
                }
            case .empty:
                StateNoticeView(kind: .empty,
                                title: L10n.t("devices.empty.title"),
                                message: L10n.t("devices.empty.message"))
            case .offline:
                StateNoticeView(kind: .offline,
                                title: L10n.t("devices.offline.title"),
                                message: L10n.t("devices.offline.message")) {
                    Task { await load() }
                }
            case .failed:
                StateNoticeView(kind: .failed,
                                title: L10n.t("devices.failed.title"),
                                message: L10n.t("devices.failed.message")) {
                    Task { await load() }
                }
            }
        }
        .nightCard(grain: false)
    }

    private func sessionRow(_ session: DeviceSession) -> some View {
        let isThisDevice = session.isThisDevice(ownSessionId: appState.sessionId)
        return HStack(spacing: LayoutMetrics.s(12)) {
            Image(systemName: MultiDeviceRules.deviceIcon(name: session.deviceName))
                .font(.system(.body, design: .rounded).weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(session.isRevoked ? Nacht.tertiaer : coupleTint.blend)
                .frame(width: LayoutMetrics.s(34))
            VStack(alignment: .leading, spacing: 2) {
                Text(session.deviceName ?? L10n.t("devices.fallbackName"))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(session.isRevoked ? Nacht.tertiaer : Papier.aufNacht)
                Text(sessionSubline(session))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
            }
            Spacer()
            if isThisDevice {
                PillTag(text: L10n.t("devices.thisDevice"), tint: coupleTint.blend)
            } else if session.isRevoked {
                PillTag(text: L10n.t("devices.revokedTag"), tint: Nacht.tertiaer)
            } else {
                Button {
                    revokeTarget = session
                    confirmRevoke = true
                } label: {
                    Text(L10n.t(revokingIDs.contains(session.id)
                                ? "devices.revoking" : "devices.revoke"))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.energyRed)
                }
                .buttonStyle(.plain)
                .disabled(revokingIDs.contains(session.id))
                .minimumHitTarget()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func sessionSubline(_ session: DeviceSession) -> String {
        if let lastUsedAt = session.lastUsedAt {
            return L10n.t("devices.lastUsed", ["time": L10n.relativeShort(lastUsedAt)])
        }
        if let createdAt = session.createdAt {
            return L10n.t("devices.linkedAt", ["time": L10n.relativeShort(createdAt)])
        }
        return L10n.t("devices.fallbackName")
    }

    // MARK: Actions

    private func load() async {
        guard let api = appState.api else {
            loading = false
            loadFailed = true
            return
        }
        loading = sessions.isEmpty
        do {
            let list = try await api.sessions()
            // Live seats first, then dead-but-retained records; within a
            // group the newest device on top.
            sessions = list.sorted { a, b in
                if a.isRevoked != b.isRevoked { return !a.isRevoked }
                return (a.createdAt ?? .distantPast) > (b.createdAt ?? .distantPast)
            }
            loadFailed = false
        } catch {
            // A dead transport while the socket is down is the offline
            // state, not a broken screen.
            if case APIError.transport = error, appState.socket.state != .connected {
                loadFailed = false
            } else {
                loadFailed = true
            }
        }
        loading = false
    }

    private func mintCode() async {
        guard let api = appState.api else { return }
        minting = true
        defer { minting = false }
        do {
            let minted = try await api.createDeviceLinkCode(
                server: appState.servers.activeProfile?.urlString)
            withAnimation(Theme.Motion.arrive) { linkCode = minted }
            Haptics.shared.success()
        } catch {
            // 413 too_many_sessions → the mapped toast tells the person to
            // revoke a seat — and the list to do that in is right below.
            appState.showDeviceLinkError(error)
        }
    }

    private func revoke(_ session: DeviceSession) async {
        guard let api = appState.api else { return }
        revokingIDs.insert(session.id)
        defer { revokingIDs.remove(session.id) }
        do {
            try await api.revokeSession(id: session.id)
            Haptics.shared.success()
            appState.showToast(L10n.t("devices.revokedToast",
                                      ["name": session.deviceName ?? L10n.t("devices.fallbackName")]),
                               style: .success)
            await load()
        } catch {
            appState.handleAPIError(error)
        }
    }
}
