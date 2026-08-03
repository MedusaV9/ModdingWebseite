import SwiftUI

/// Create or join a couple on the active server (incl. profile setup + QR).
struct PairingView: View {
    @Environment(AppState.self) private var appState

    enum Mode: Hashable { case create, join }

    @State private var mode: Mode = .create
    @State private var name = ""
    @State private var avatar = Theme.avatarEmojis[0]
    @State private var colorHex = Theme.memberColors[0]
    @State private var code = ""
    @State private var busy = false
    @State private var showScanner = false
    @State private var showServerPicker = false

    var body: some View {
        ZStack {
            DreamyBackground()
            ScrollView {
                VStack(spacing: 20) {
                    header

                    // Mode switch
                    HStack(spacing: 10) {
                        modeButton(.create, label: L10n.t("pairing.create"), icon: "plus.heart.fill")
                        modeButton(.join, label: L10n.t("pairing.join"), icon: "link")
                    }

                    // Profile
                    VStack(alignment: .leading, spacing: 14) {
                        Text(L10n.t("pairing.profileTitle"))
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundStyle(Theme.textPrimary)

                        HStack(spacing: 14) {
                            EmojiAvatarView(emoji: avatar, colorHex: colorHex, size: 64)
                            TextField(L10n.t("pairing.yourName"), text: $name)
                                .textFieldStyle(DreamyFieldStyle())
                        }

                        Text(L10n.t("pairing.avatar"))
                            .font(.system(.footnote, design: .rounded).weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                        EmojiPickerGrid(emojis: Theme.avatarEmojis, selection: $avatar)

                        Text(L10n.t("pairing.color"))
                            .font(.system(.footnote, design: .rounded).weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                        MemberColorPicker(selection: $colorHex)
                    }
                    .glassCard(padding: 18)

                    // Join: code entry + QR scan
                    if mode == .join {
                        VStack(spacing: 12) {
                            TextField(L10n.t("pairing.codePlaceholder"), text: $code)
                                .textFieldStyle(DreamyFieldStyle())
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .onChange(of: code) { _, newValue in
                                    code = String(newValue.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                                }
                            Button {
                                showScanner = true
                            } label: {
                                Label(L10n.t("pairing.scanQR"), systemImage: "qrcode.viewfinder")
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                        .glassCard(padding: 18)
                    }

                    // Primary action
                    Button {
                        Task { await submit() }
                    } label: {
                        if busy {
                            ProgressView().tint(.white)
                        } else {
                            Text(mode == .create ? L10n.t("pairing.create") : L10n.t("pairing.join"))
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(busy || !isValid)
                }
                .padding(20)
            }
        }
        .sheet(isPresented: $showScanner) {
            NavigationStack {
                QRScannerView { text in
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
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("💞")
                .font(.system(size: 56))
            Text(L10n.t("pairing.title"))
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .foregroundStyle(Theme.textPrimary)
            Text(L10n.t("pairing.subtitle"))
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            if let profile = appState.servers.activeProfile {
                Button {
                    showServerPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 11, weight: .bold))
                        Text(profile.name)
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(.top, 12)
    }

    private func modeButton(_ m: Mode, label: String, icon: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) { mode = m }
            Haptics.shared.tap()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                Text(label)
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(mode == m ? .white : Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(mode == m ? AnyShapeStyle(Theme.heroGradient) : AnyShapeStyle(Color.white.opacity(0.07)))
            )
        }
        .buttonStyle(.plain)
    }

    private var isValid: Bool {
        let nameOK = !name.trimmingCharacters(in: .whitespaces).isEmpty
        return mode == .create ? nameOK : (nameOK && code.count == 6)
    }

    private func handleScan(_ text: String) {
        showScanner = false
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
        } else {
            code = String(text.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
        }
        mode = .join
        Haptics.shared.success()
    }

    private func submit() async {
        guard let profile = appState.servers.activeProfile,
              let url = profile.baseURL else { return }
        busy = true
        defer { busy = false }
        let api = API(baseURL: url, token: nil)
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        do {
            let auth: AuthResponse
            if mode == .create {
                auth = try await api.createCouple(name: trimmedName, avatar: avatar, color: "#" + colorHex)
            } else {
                auth = try await api.joinCouple(code: code, name: trimmedName, avatar: avatar, color: "#" + colorHex)
            }
            SoundEngine.shared.play(.tada)
            Haptics.shared.success()
            appState.completeAuth(profileID: profile.id, auth: auth)
        } catch let error as APIError {
            if case .http(let status, let codeStr, _) = error {
                if status == 404 || codeStr == "unknown_code" {
                    appState.showToast(L10n.t("pairing.unknownCode"), style: .error)
                } else if status == 409 || codeStr == "couple_full" {
                    appState.showToast(L10n.t("pairing.coupleFull"), style: .error)
                } else {
                    appState.showToast(error.localizedDescription, style: .error)
                }
            } else {
                appState.showToast(error.localizedDescription, style: .error)
            }
            Haptics.shared.warning()
        } catch {
            appState.showToast(error.localizedDescription, style: .error)
            Haptics.shared.warning()
        }
    }
}
