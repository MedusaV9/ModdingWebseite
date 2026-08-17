import SwiftUI
import UniformTypeIdentifiers

struct MigrationAssistantView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint

    @State private var exportPassphrase = ""
    @State private var exportConfirmation = ""
    @State private var exportURL: URL?
    @State private var showImporter = false
    @State private var encryptedImport: Data?
    @State private var importPassphrase = ""
    @State private var pendingTransfer: MigrationTransferFile?
    @State private var result: MigrationImportResponse?
    @State private var showImportConfirmation = false
    @State private var busy = false
    @State private var errorMessage: String?

    private var exportReady: Bool {
        exportPassphrase.count >= 12 && exportPassphrase == exportConfirmation
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LayoutMetrics.s(14)) {
                    introCard
                    exportCard
                    destinationCard
                    importCard
                    if let result { completionCard(result) }
                }
                .padding()
            }
            .background(DreamyBackground(showBlobs: false).ignoresSafeArea())
            .navigationTitle(L10n.t("migration.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("common.done")) { dismiss() }
                }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data]) { outcome in
            do {
                let url = try outcome.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                encryptedImport = try Data(contentsOf: url)
                pendingTransfer = nil
                result = nil
                errorMessage = nil
            } catch {
                errorMessage = L10n.t("migration.fileReadFailed")
            }
        }
        .alert(L10n.t("migration.confirmTitle"), isPresented: $showImportConfirmation) {
            Button(L10n.t("common.cancel"), role: .cancel) {}
            Button(L10n.t("migration.importNow"), role: .destructive) {
                importIntoActiveServer()
            }
        } message: {
            Text(L10n.t("migration.confirmBody"))
        }
        .preferredColorScheme(.dark)
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
            Label(L10n.t("migration.introTitle"), systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)
                .foregroundStyle(Papier.aufNacht)
            Text(L10n.t("migration.introBody"))
                .font(.subheadline)
                .foregroundStyle(Nacht.sekundaer)
            Label(L10n.t("migration.mediaLimit"), systemImage: "externaldrive.badge.exclamationmark")
                .font(.caption)
                .foregroundStyle(Theme.energyRed)
        }
        .nightCard(grain: false)
    }

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(12)) {
            Label(L10n.t("migration.stepExport"), systemImage: "square.and.arrow.up")
                .font(.headline)
                .foregroundStyle(Papier.aufNacht)
            Text(L10n.t("migration.exportHint"))
                .font(.caption)
                .foregroundStyle(Nacht.sekundaer)
            SecureField(L10n.t("migration.passphrase"), text: $exportPassphrase)
                .textContentType(.newPassword)
                .textFieldStyle(DreamyFieldStyle())
            SecureField(L10n.t("migration.passphraseAgain"), text: $exportConfirmation)
                .textContentType(.newPassword)
                .textFieldStyle(DreamyFieldStyle())

            if let exportURL {
                ShareLink(item: exportURL) {
                    Label(L10n.t("migration.shareFile"), systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Button {
                    createExport()
                } label: {
                    Label(L10n.t("migration.createFile"), systemImage: "lock.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!exportReady || busy || appState.api == nil)
            }
        }
        .nightCard(grain: false)
    }

    private var destinationCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(9)) {
            Label(L10n.t("migration.stepDestination"), systemImage: "server.rack")
                .font(.headline)
                .foregroundStyle(Papier.aufNacht)
            Text(L10n.t("migration.destinationBody"))
                .font(.subheadline)
                .foregroundStyle(Nacht.sekundaer)
            Label(L10n.t("migration.sessionsReset"), systemImage: "person.2.badge.key")
                .font(.caption)
                .foregroundStyle(Theme.energyRed)
        }
        .nightCard(grain: false)
    }

    private var importCard: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(12)) {
            Label(L10n.t("migration.stepImport"), systemImage: "square.and.arrow.down")
                .font(.headline)
                .foregroundStyle(Papier.aufNacht)
            Button {
                showImporter = true
            } label: {
                Label(L10n.t("migration.chooseFile"), systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())

            if encryptedImport != nil {
                SecureField(L10n.t("migration.passphrase"), text: $importPassphrase)
                    .textContentType(.password)
                    .textFieldStyle(DreamyFieldStyle())
                Button(L10n.t("migration.unlockReview")) { unlockImport() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(importPassphrase.count < 12 || busy)
            }

            if let transfer = pendingTransfer {
                Divider().overlay(Nacht.naht)
                Text(L10n.t("migration.review", [
                    "version": transfer.bundle.sourceVersion,
                    "digest": String(transfer.bundle.digest.prefix(12)),
                ]))
                .font(.caption.monospaced())
                .foregroundStyle(Nacht.sekundaer)
                Button(L10n.t("migration.importNow"), role: .destructive) {
                    showImportConfirmation = true
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy || appState.api == nil)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.energyRed)
            }
        }
        .nightCard(grain: false)
    }

    private func completionCard(_ result: MigrationImportResponse) -> some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.s(10)) {
            Label(L10n.t("migration.completeTitle"), systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(Licht.lampengold)
            Text(L10n.t("migration.completeBody"))
                .font(.subheadline)
                .foregroundStyle(Nacht.sekundaer)
            Text(result.code)
                .font(.system(.title, design: .monospaced).bold())
                .foregroundStyle(Papier.aufNacht)
                .textSelection(.enabled)
            Text(L10n.t("migration.digest", ["digest": String(result.digest.prefix(12))]))
                .font(.caption.monospaced())
                .foregroundStyle(Nacht.tertiaer)
        }
        .nightCard(grain: false)
    }

    private func createExport() {
        guard exportReady, let api = appState.api else { return }
        busy = true
        errorMessage = nil
        Task {
            do {
                let response = try await api.exportMigration()
                let transfer = MigrationTransferFile(
                    bundle: response.bundle,
                    sourceMemberId: response.me
                )
                let encrypted = try MigrationFileService.encode(
                    transfer,
                    passphrase: exportPassphrase
                )
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("SoooDreamy-Couple-Migration.sooodreamy-migration")
                try encrypted.write(to: url, options: .atomic)
                exportURL = url
                Haptics.shared.success()
            } catch {
                errorMessage = L10n.t("migration.exportFailed")
                Haptics.shared.warning()
            }
            busy = false
        }
    }

    private func unlockImport() {
        guard let encryptedImport else { return }
        do {
            pendingTransfer = try MigrationFileService.decode(
                encryptedImport,
                passphrase: importPassphrase
            )
            errorMessage = nil
            Haptics.shared.success()
        } catch {
            pendingTransfer = nil
            errorMessage = L10n.t("migration.unlockFailed")
            Haptics.shared.warning()
        }
    }

    private func importIntoActiveServer() {
        guard let transfer = pendingTransfer, let api = appState.api else { return }
        busy = true
        errorMessage = nil
        Task {
            do {
                let imported = try await api.importMigration(transfer)
                if var profile = appState.servers.activeProfile {
                    profile.coupleId = imported.coupleId
                    profile.memberId = imported.memberId
                    appState.servers.update(profile)
                }
                result = imported
                await appState.reloadAfterRestore()
                Haptics.shared.success()
            } catch {
                errorMessage = error.localizedDescription
                Haptics.shared.warning()
            }
            busy = false
        }
    }
}
