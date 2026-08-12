import SwiftUI

/// First launch: welcome → add your server. Pairing follows via `phase`.
struct OnboardingFlowView: View {
    @Environment(AppState.self) private var appState
    @State private var showServerSetup = false

    var body: some View {
        ZStack {
            DreamyBackground()
            FloatingHeartsView(emojis: ["💜", "💖", "✨"], count: 10)
                .opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Text("💜")
                    .font(.scaled(84))
                    .shadow(color: Theme.pink.opacity(0.8), radius: 30)
                    .padding(.bottom, LayoutMetrics.s(18))

                Text(L10n.t("onboarding.title"))
                    .font(.scaled(44, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.75)
                    .lineLimit(2)
                    .foregroundStyle(
                        LinearGradient(colors: [Theme.rose, Theme.pink, Theme.purple],
                                       startPoint: .leading, endPoint: .trailing)
                    )

                Text(L10n.t("onboarding.tagline"))
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, LayoutMetrics.s(36))
                    .padding(.top, LayoutMetrics.s(10))

                VStack(alignment: .leading, spacing: LayoutMetrics.s(14)) {
                    featureRow("heart.fill", "onboarding.feature1", Theme.pink)
                    featureRow("bubble.left.and.bubble.right.fill", "onboarding.feature2", Theme.blue)
                    featureRow("gamecontroller.fill", "onboarding.feature3", Theme.purple)
                    featureRow("sparkles", "onboarding.feature4", Theme.gold)
                }
                .glassCard(padding: 20)
                .padding(.horizontal, LayoutMetrics.s(24))
                .padding(.top, LayoutMetrics.s(30))

                Spacer()

                languagePicker
                    .padding(.bottom, LayoutMetrics.s(14))

                Button(L10n.t("onboarding.start")) {
                    Haptics.shared.tap()
                    SoundEngine.shared.play(.chime)
                    showServerSetup = true
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, LayoutMetrics.s(24))
                .padding(.bottom, LayoutMetrics.s(30))
            }
        }
        .sheet(isPresented: $showServerSetup) {
            ServerSetupSheet(isOnboarding: true)
        }
    }

    private func featureRow(_ icon: String, _ key: String, _ tint: Color) -> some View {
        HStack(spacing: LayoutMetrics.s(12)) {
            Image(systemName: icon)
                .font(.scaled(16, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: LayoutMetrics.s(34), height: LayoutMetrics.s(34))
                .background(Circle().fill(tint.opacity(0.18)))
            Text(L10n.t(key))
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var languagePicker: some View {
        HStack(spacing: 8) {
            ForEach(AppLanguage.allCases) { lang in
                Button {
                    L10n.language = lang
                    appState.uiRefresh += 1
                } label: {
                    Text(L10n.t(lang.displayNameKey))
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(L10n.language == lang ? .white : Theme.textSecondary)
                        .padding(.vertical, 7)
                        .padding(.horizontal, LayoutMetrics.s(14))
                        .background(
                            Capsule().fill(L10n.language == lang ? Theme.purple.opacity(0.6) : Color.white.opacity(0.07))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Add/edit a server with live connection testing.
/// Used from onboarding and from Settings → Manage servers.
struct ServerSetupSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var isOnboarding = false
    var existing: ServerProfile? = nil

    @State private var name = ""
    @State private var urlString = ""
    @State private var testing = false
    @State private var testResult: (ok: Bool, text: String)? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                ScrollView {
                    VStack(alignment: .leading, spacing: LayoutMetrics.s(18)) {
                        Text(L10n.t("server.setupSubtitle"))
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(spacing: LayoutMetrics.s(12)) {
                            TextField(L10n.t("server.name"), text: $name)
                                .textFieldStyle(DreamyFieldStyle())
                            TextField(L10n.t("server.url"), text: $urlString)
                                .textFieldStyle(DreamyFieldStyle())
                                .keyboardType(.URL)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }

                        if let result = testResult {
                            HStack(spacing: 8) {
                                Image(systemName: result.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(result.ok ? Theme.mint : Color(hex: "F87171"))
                                Text(result.text)
                                    .font(.system(.footnote, design: .rounded))
                                    .foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .glassCard(padding: 12)
                        }

                        Button {
                            Task { await test() }
                        } label: {
                            if testing {
                                ProgressView().tint(.white)
                            } else {
                                Label(L10n.t("server.test"), systemImage: "bolt.horizontal.fill")
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(testing || normalized == nil)

                        Button(isOnboarding ? L10n.t("server.continue") : L10n.t("common.save")) {
                            save()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(normalized == nil)

                        Text(L10n.t("server.buildBadge", ["version": appVersionLabel]))
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(Theme.mint)
                            .padding(.top, 4)

                        Text(L10n.t("server.hint"))
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(LayoutMetrics.s(20))
                }
            }
            .navigationTitle(L10n.t(existing == nil ? "server.add" : "common.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear {
            if let existing {
                name = existing.name
                urlString = existing.urlString
            }
        }
    }

    private var appVersionLabel: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private var normalized: String? {
        ServerProfile.normalize(urlString)
    }

    private func test() async {
        guard let normalized, let url = URL(string: normalized) else {
            testResult = (false, L10n.t("server.invalidURL"))
            return
        }
        testing = true
        defer { testing = false }
        do {
            let health = try await API(baseURL: url, token: nil).health()
            testResult = (true, L10n.t("server.testOK", ["name": health.name, "version": health.version]))
            Haptics.shared.success()
        } catch {
            let raw = error.localizedDescription
            let looksLikeATS = raw.localizedCaseInsensitiveContains("App Transport Security")
                || raw.localizedCaseInsensitiveContains("secure connection")
            if looksLikeATS {
                testResult = (false, L10n.t("server.testFailATS"))
            } else {
                testResult = (false, L10n.t("server.testFail", ["error": raw]))
            }
            Haptics.shared.warning()
        }
    }

    private func save() {
        guard let normalized else { return }
        if var existing {
            existing.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? normalized : name
            existing.urlString = normalized
            appState.servers.update(existing)
        } else if let profile = appState.servers.add(name: name, urlString: normalized) {
            appState.servers.setActive(id: profile.id)
        }
        Haptics.shared.success()
        dismiss()
    }
}

struct DreamyFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(.body, design: .rounded))
            .foregroundStyle(Theme.textPrimary)
            .padding(.vertical, LayoutMetrics.s(13))
            .padding(.horizontal, LayoutMetrics.s(16))
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )
            )
    }
}
