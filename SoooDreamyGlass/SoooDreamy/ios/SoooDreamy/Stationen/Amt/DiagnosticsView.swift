import SwiftUI

// Verbindungs-Doktor (W8, Linse 12 #7) — a self-hosted server plus sideloaded
// app means troubleshooting belongs INTO the app, not into the couple's chat.
// Four sequential checks with traffic lights, each red step names a concrete
// way out; the summary is copyable so one partner can send it to the other.

/// One diagnostic step with its traffic-light verdict.
private struct DoctorCheck: Identifiable {
    enum Verdict {
        case pending, good, warn, bad, skipped
    }

    let id: String
    let titleKey: String
    var verdict: Verdict = .pending
    /// Already-localized detail line (built with values like latency).
    var detail: String = ""
}

struct DiagnosticsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint

    @State private var checks: [DoctorCheck] = []
    @State private var running = false
    @State private var finishedOnce = false

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showBlobs: false)
                ScrollView {
                    VStack(alignment: .leading, spacing: LayoutMetrics.s(16)) {
                        Text(L10n.t("doctor.intro"))
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(spacing: LayoutMetrics.s(12)) {
                            ForEach(checks) { check in
                                checkRow(check)
                            }
                        }
                        .nightCard(grain: false)

                        Button {
                            Haptics.shared.tap()
                            Task { await runCheckup() }
                        } label: {
                            Label(L10n.t(running ? "settings.doctor.checking"
                                                 : (finishedOnce ? "doctor.rerun" : "doctor.run")),
                                  systemImage: "stethoscope")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(running)

                        if finishedOnce {
                            Button {
                                UIPasteboard.general.string = reportText
                                Haptics.shared.success()
                                appState.showToast(L10n.t("doctor.copied"), style: .success)
                            } label: {
                                Label(L10n.t("doctor.copy"), systemImage: "doc.on.doc")
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }
                    .padding(LayoutMetrics.s(16))
                    .contentColumn(.reading)
                }
            }
            .navigationTitle(L10n.t("doctor.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("common.done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            resetChecks()
            await runCheckup()
        }
    }

    // MARK: Rows

    private func checkRow(_ check: DoctorCheck) -> some View {
        HStack(alignment: .top, spacing: LayoutMetrics.s(12)) {
            lamp(check.verdict)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t(check.titleKey))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Papier.aufNacht)
                Text(check.detail.isEmpty ? L10n.t("doctor.pending") : check.detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func lamp(_ verdict: DoctorCheck.Verdict) -> some View {
        // Ink lamps: the traffic light keeps its semantics, but every
        // dot wears a kante ring so it stays visible on light cardboard.
        switch verdict {
        case .pending:
            lampDot(Papier.nachtInnenFill)
        case .good:
            lampDot(coupleTint.blend)
        case .warn:
            lampDot(Theme.gold)
        case .bad:
            lampDot(Theme.energyRed)
        case .skipped:
            Circle().strokeBorder(Nacht.tertiaer, lineWidth: 1.5)
                .frame(width: 12, height: 12)
        }
    }

    private func lampDot(_ fill: Color) -> some View {
        Circle().fill(fill)
            .overlay(Circle().strokeBorder(Nacht.naht, lineWidth: Theme.hairlineWidth))
            .frame(width: 12, height: 12)
    }

    // MARK: Checkup

    private func resetChecks() {
        checks = [
            DoctorCheck(id: "reach", titleKey: "doctor.check.reach"),
            DoctorCheck(id: "version", titleKey: "doctor.check.version"),
            DoctorCheck(id: "session", titleKey: "doctor.check.session"),
            DoctorCheck(id: "socket", titleKey: "doctor.check.socket"),
        ]
    }

    private func set(_ id: String, _ verdict: DoctorCheck.Verdict, _ detail: String) {
        guard let index = checks.firstIndex(where: { $0.id == id }) else { return }
        checks[index].verdict = verdict
        checks[index].detail = detail
    }

    private func runCheckup() async {
        guard !running else { return }
        running = true
        defer {
            running = false
            finishedOnce = true
        }
        resetChecks()

        guard let api = appState.api else {
            let note = L10n.t("doctor.noServer")
            set("reach", .bad, note)
            set("version", .skipped, L10n.t("doctor.skipped"))
            set("session", .skipped, L10n.t("doctor.skipped"))
            set("socket", .skipped, L10n.t("doctor.skipped"))
            return
        }

        // 1) Reachability + latency (unauthenticated /api/health)
        let clock = ContinuousClock()
        let start = clock.now
        let health: HealthResponse?
        do {
            health = try await api.health()
        } catch {
            health = nil
        }
        let latencyMs = Int((clock.now - start) / .milliseconds(1))

        if let health {
            let reachKey = latencyMs > 1500 ? "doctor.reach.slow" : "doctor.reach.ok"
            set("reach", latencyMs > 1500 ? .warn : .good,
                L10n.t(reachKey, ["ms": String(latencyMs)]))
            set("version", .good, L10n.t("doctor.version.ok", ["version": health.version]))
        } else {
            set("reach", .bad, L10n.t("doctor.reach.fail"))
            set("version", .skipped, L10n.t("doctor.skipped"))
            set("session", .skipped, L10n.t("doctor.skipped"))
            set("socket", .skipped, L10n.t("doctor.skipped"))
            return
        }

        // 2) Session validity (an authorized, read-only call)
        do {
            _ = try await api.getCouple()
            set("session", .good, L10n.t("doctor.session.ok"))
        } catch {
            set("session", .bad, L10n.t("doctor.session.fail"))
        }

        // 3) Live socket
        switch appState.socket.state {
        case .connected:
            set("socket", .good, L10n.t("doctor.socket.ok"))
        case .connecting:
            set("socket", .warn, L10n.t("doctor.socket.connecting"))
        case .disconnected:
            set("socket", .bad, L10n.t("doctor.socket.fail"))
        }
    }

    /// Plain-text summary for the clipboard — safe to share, contains no token.
    private var reportText: String {
        var lines = [L10n.t("doctor.title")]
        if let profile = appState.servers.activeProfile {
            lines.append(profile.urlString)
        }
        for check in checks {
            let symbol: String
            switch check.verdict {
            case .good: symbol = "OK"
            case .warn: symbol = "~"
            case .bad: symbol = "X"
            case .skipped, .pending: symbol = "–"
            }
            lines.append("[\(symbol)] \(L10n.t(check.titleKey)): \(check.detail)")
        }
        return lines.joined(separator: "\n")
    }
}
