import SwiftUI

/// Manage servers: add, edit, test, switch active, remove.
/// Every server keeps its own pairing session — switching is instant.
struct ServerListSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var showAdd = false
    @State private var editing: ServerProfile?
    @State private var deleting: ServerProfile?
    @State private var health: [UUID: Bool] = [:]

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                ScrollView {
                    VStack(spacing: 12) {
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
                    .padding(20)
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
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isActive ? Theme.pink : Theme.textSecondary)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                    Circle()
                        .fill(healthColor(profile))
                        .frame(width: 11, height: 11)
                        .overlay(Circle().strokeBorder(Theme.bgTop, lineWidth: 2))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.name)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(profile.urlString)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                    Text(L10n.t(profile.isPaired ? "server.paired" : "server.notPaired"))
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(profile.isPaired ? Theme.mint : Theme.textTertiary)
                }
                Spacer()
                if isActive {
                    PillTag(text: L10n.t("server.active"), tint: Theme.pink)
                }
            }

            if !isActive {
                Button {
                    Task { await appState.activateProfile(profile.id) }
                } label: {
                    Label(L10n.t("server.switch"), systemImage: "arrow.left.arrow.right")
                        .font(.system(.footnote, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.pink)
                }
                .buttonStyle(.plain)
            }
        }
        .glassCard(padding: 14)
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
        switch health[profile.id] {
        case .some(true): return Theme.mint
        case .some(false): return Color(hex: "F87171")
        case .none: return Color.gray.opacity(0.6)
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
