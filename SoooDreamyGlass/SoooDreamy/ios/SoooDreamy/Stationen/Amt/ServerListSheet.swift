import SwiftUI

/// Manage servers: add, edit, test, switch active, remove.
/// Every server keeps its own pairing session — switching is instant.
struct ServerListSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint

    @State private var showAdd = false
    @State private var editing: ServerProfile?
    @State private var deleting: ServerProfile?
    @State private var health: [UUID: Bool] = [:]

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showBlobs: false)
                ScrollView {
                    VStack(spacing: LayoutMetrics.s(12)) {
                        ForEach(appState.servers.profiles) { profile in
                            serverRow(profile)
                        }

                        Button {
                            showAdd = true
                        } label: {
                            Label(L10n.t("server.add"), systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .padding(.top, 6)

                        Text(L10n.t("server.hint"))
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                    .padding(LayoutMetrics.s(16))
                    .contentColumn(.reading)
                }
            }
            .navigationTitle(L10n.t("server.manage"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("common.done")) { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            ServerSetupSheet()
        }
        .sheet(item: $editing) { profile in
            ServerSetupSheet(existing: profile)
        }
        .confirmationDialog(
            L10n.t("server.deleteConfirm", ["name": deleting?.name ?? ""]),
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button(L10n.t("server.delete"), role: .destructive) {
                if let profile = deleting {
                    remove(profile)
                }
                deleting = nil
            }
            Button(L10n.t("common.cancel"), role: .cancel) { deleting = nil }
        }
        .task { await checkHealth() }
        .onChange(of: appState.servers.profiles.count) {
            Task { await checkHealth() }
        }
    }

    private func serverRow(_ profile: ServerProfile) -> some View {
        let isActive = appState.servers.activeProfileID == profile.id
        return VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
            HStack(spacing: LayoutMetrics.s(12)) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "server.rack")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isActive ? coupleTint.blend : Nacht.sekundaer)
                        .frame(width: LayoutMetrics.s(42), height: LayoutMetrics.s(42))
                        .background(Circle().fill(Papier.nachtInnenFill))
                    Circle()
                        .fill(healthColor(profile))
                        .frame(width: 11, height: 11)
                        .overlay(Circle().strokeBorder(Papier.nachtkarton, lineWidth: 2))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.name)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Papier.aufNacht)
                        .lineLimit(1)
                    Text(profile.urlString)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Nacht.sekundaer)
                        .lineLimit(1)
                    Text(L10n.t(profile.isPaired ? "server.paired" : "server.notPaired"))
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(profile.isPaired ? Licht.lampengold : Nacht.tertiaer)
                }
                Spacer()
                if isActive {
                    PillTag(text: L10n.t("server.active"), tint: coupleTint.blend)
                }
            }

            if !isActive {
                Button {
                    Task { await appState.activateProfile(profile.id) }
                } label: {
                    Label(L10n.t("server.switch"), systemImage: "arrow.left.arrow.right")
                        .font(.system(.footnote, design: .rounded).weight(.bold))
                        .foregroundStyle(Licht.lampengold)
                }
                .buttonStyle(.plain)
            }
        }
        .nightCard(grain: false)
        .contextMenu {
            Button {
                editing = profile
            } label: {
                Label(L10n.t("common.edit"), systemImage: "pencil")
            }
            Button(role: .destructive) {
                deleting = profile
            } label: {
                Label(L10n.t("server.delete"), systemImage: "trash")
            }
        }
    }

    private func healthColor(_ profile: ServerProfile) -> Color {
        // Traffic light on the night carton: couple blend = reachable,
        // energy red = down, neutral night ink = still checking.
        switch health[profile.id] {
        case .some(true): return coupleTint.blend
        case .some(false): return Theme.energyRed
        case .none: return Nacht.tertiaer.opacity(0.6)
        }
    }

    private func checkHealth() async {
        await withTaskGroup(of: (UUID, Bool).self) { group in
            for profile in appState.servers.profiles {
                guard let url = profile.baseURL else { continue }
                group.addTask {
                    let ok = (try? await API(baseURL: url, token: nil).health().ok) ?? false
                    return (profile.id, ok)
                }
            }
            for await (id, ok) in group {
                health[id] = ok
            }
        }
    }

    private func remove(_ profile: ServerProfile) {
        let wasActive = appState.servers.activeProfileID == profile.id
        if wasActive {
            appState.socket.disconnect()
            appState.couple = nil
        }
        appState.servers.remove(id: profile.id)
        if wasActive, appState.phase == .main {
            Task { await appState.refreshAll(); appState.connectSocket() }
        }
    }
}
