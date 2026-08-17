import CloudKit
import SwiftUI
import UniformTypeIdentifiers

/// iCloud & backup: CloudKit backup of servers + settings into the
/// user's private database, iCloud-Drive/file export of a readable snapshot,
/// restore from either. Detects at runtime whether the iCloud entitlements
/// survived signing (sideload often strips them) and degrades honestly.
struct ICloudSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint

    /// nil = still checking; .available etc. afterwards. `unusable` (no
    /// entitlement / check failed) is modeled as `.couldNotDetermine`.
    @State private var ckStatus: CKAccountStatus?
    @State private var ckChecked = false
    @State private var driveAvailable = UbiquityDrive.identityAvailable

    @State private var busy = false
    @State private var lastBackupAt = CloudKitBackup.lastBackupAt
    @State private var confirmRestore = false
    @State private var pendingFilePayload: AppBackupPayload?
    @State private var pendingEncryptedFile: Data?
    @State private var confirmFileRestore = false
    @State private var exportURL: URL?
    @State private var showImporter = false
    @State private var exportPassphrase = ""
    @State private var exportPassphraseConfirmation = ""
    @State private var importPassphrase = ""
    @State private var askForImportPassphrase = false
    @State private var includeServerProfiles = true
    @State private var includeDeviceSettings = true
    @State private var includeAppGroupSettings = true
    @State private var includeCoupleSnapshot = true
    @State private var restoreServerProfiles = true
    @State private var restoreDeviceSettings = true
    @State private var restoreAppGroupSettings = true

    private static let exportContentType = UTType(filenameExtension: "sooodreamy") ?? .data

    private var cloudKitUsable: Bool {
        ckChecked && ckStatus == .available
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showBlobs: false)
                // Native grouped Form (system semantics, spacing, focus
                // order); the rows sit as night cartons over the
                // DreamyBackground — same content, same order.
                Form {
                    statusSection
                    backupSection
                    exportSection
                    restoreOptionsSection
                    hintSection
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .contentColumn(.reading)
            }
            .navigationTitle(L10n.t("icloud.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("common.done")) { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await checkStatus() }
        .confirmationDialog(L10n.t("icloud.restoreConfirmTitle"),
                            isPresented: $confirmRestore, titleVisibility: .visible) {
            Button(L10n.t("icloud.restore"), role: .destructive) { restoreFromCloud() }
            Button(L10n.t("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("icloud.restoreConfirmMessage"))
        }
        .confirmationDialog(L10n.t("icloud.restoreConfirmTitle"),
                            isPresented: $confirmFileRestore, titleVisibility: .visible) {
            Button(L10n.t("icloud.restore"), role: .destructive) { restoreFromFile() }
            Button(L10n.t("common.cancel"), role: .cancel) { pendingFilePayload = nil }
        } message: {
            Text(L10n.t("icloud.restoreConfirmMessage"))
        }
        .alert(L10n.t("icloud.importPasswordTitle"), isPresented: $askForImportPassphrase) {
            SecureField(L10n.t("icloud.password"), text: $importPassphrase)
            Button(L10n.t("icloud.decrypt")) { decryptImportedFile() }
                .disabled(importPassphrase.count < 12)
            Button(L10n.t("common.cancel"), role: .cancel) {
                pendingEncryptedFile = nil
                importPassphrase = ""
            }
        } message: {
            Text(L10n.t("icloud.importPasswordHint"))
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [Self.exportContentType, .data]) { result in
            handleImport(result)
        }
    }

    // MARK: Status

    private var statusSection: some View {
        Section {
            statusRow(name: L10n.t("icloud.statusCloudKit"),
                      ok: cloudKitUsable,
                      detail: cloudKitDetail)
            statusRow(name: L10n.t("icloud.statusDrive"),
                      ok: driveAvailable,
                      detail: driveAvailable
                          ? L10n.t("icloud.available")
                          : L10n.t("icloud.unavailable"))
        } header: {
            Text(L10n.t("icloud.status"))
        }
        .listRowBackground(Papier.nachtkarton)
    }

    private var cloudKitDetail: String {
        guard ckChecked else { return "…" }
        switch ckStatus {
        case .available: return L10n.t("icloud.available")
        case .noAccount: return L10n.t("icloud.noAccount")
        case .restricted, .temporarilyUnavailable: return L10n.t("icloud.restricted")
        default: return L10n.t("icloud.unavailable")
        }
    }

    private func statusRow(name: String, ok: Bool, detail: String) -> some View {
        HStack(spacing: LayoutMetrics.s(10)) {
            Circle()
                .fill(ok ? coupleTint.blend : Theme.energyRed)
                .frame(width: 9, height: 9)
            Text(name)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Papier.aufNacht)
            Spacer()
            Text(detail)
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
        }
    }

    // MARK: CloudKit backup

    private var backupSection: some View {
        Section {
            Text(L10n.t("icloud.whatsIn"))
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(L10n.t("icloud.lastBackup"))
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(Nacht.sekundaer)
                Spacer()
                Text(lastBackupAt.map { L10n.relativeShort($0) } ?? L10n.t("icloud.never"))
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
            }
            if busy {
                BusySpinner(tint: coupleTint.blend)
                    .frame(maxWidth: .infinity)
            } else {
                Button(L10n.t("icloud.backupNow")) {
                    Haptics.shared.tap()
                    backupNow()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!cloudKitUsable)
                Button(L10n.t("icloud.restore")) {
                    Haptics.shared.tap()
                    confirmRestore = true
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!cloudKitUsable)
            }
        } header: {
            Text(L10n.t("icloud.backup"))
        }
        .listRowBackground(Papier.nachtkarton)
        .opacity(cloudKitUsable || !ckChecked ? 1 : 0.55)
    }

    // MARK: File export / import

    private var exportSection: some View {
        Section {
            Text(L10n.t("icloud.exportHint"))
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
                .fixedSize(horizontal: false, vertical: true)
            Group {
                Toggle(L10n.t("icloud.scope.servers"), isOn: $includeServerProfiles)
                Toggle(L10n.t("icloud.scope.device"), isOn: $includeDeviceSettings)
                Toggle(L10n.t("icloud.scope.appgroup"), isOn: $includeAppGroupSettings)
                Toggle(L10n.t("icloud.scope.couple"), isOn: $includeCoupleSnapshot)
            }
            .tint(coupleTint.blend)
            SecureField(L10n.t("icloud.password"), text: $exportPassphrase)
                .textContentType(.newPassword)
                .textFieldStyle(DreamyFieldStyle())
            SecureField(L10n.t("icloud.passwordConfirm"), text: $exportPassphraseConfirmation)
                .textContentType(.newPassword)
                .textFieldStyle(DreamyFieldStyle())
            Text(exportPasswordHint)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(exportPasswordReady ? Licht.lampengold : Theme.energyRed)
                .fixedSize(horizontal: false, vertical: true)
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label(L10n.t("icloud.exportShare"), systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Button(L10n.t("icloud.exportCreate")) {
                    Haptics.shared.tap()
                    createExport()
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(busy || !exportPasswordReady || !hasExportSelection)
            }
            if driveAvailable {
                Button(L10n.t("icloud.exportToDrive")) {
                    Haptics.shared.tap()
                    exportToDrive()
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(busy || !exportPasswordReady || !hasExportSelection)
            }
            Button(L10n.t("icloud.importFile")) {
                Haptics.shared.tap()
                showImporter = true
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(busy)
        } header: {
            Text(L10n.t("icloud.export"))
        }
        .listRowBackground(Papier.nachtkarton)
    }

    private var exportPasswordReady: Bool {
        exportPassphrase.count >= 12 && exportPassphrase == exportPassphraseConfirmation
    }

    private var hasExportSelection: Bool {
        includeServerProfiles || includeDeviceSettings
            || includeAppGroupSettings || includeCoupleSnapshot
    }

    private var exportPasswordHint: String {
        if exportPassphrase.count < 12 {
            return L10n.t("icloud.passwordTooShort")
        }
        if exportPassphrase != exportPassphraseConfirmation {
            return L10n.t("icloud.passwordMismatch")
        }
        return L10n.t("icloud.passwordWarning")
    }

    // MARK: Honest sideload hint

    private var restoreOptionsSection: some View {
        Section {
            Toggle(L10n.t("icloud.scope.servers"), isOn: $restoreServerProfiles)
            Toggle(L10n.t("icloud.scope.device"), isOn: $restoreDeviceSettings)
            Toggle(L10n.t("icloud.scope.appgroup"), isOn: $restoreAppGroupSettings)
            Text(L10n.t("icloud.scope.coupleReadOnly"))
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
        } header: {
            Text(L10n.t("icloud.restoreOptions"))
        }
        .tint(coupleTint.blend)
        .listRowBackground(Papier.nachtkarton)
    }

    private var hintSection: some View {
        Section {
            VStack(alignment: .leading, spacing: LayoutMetrics.s(8)) {
                Label(L10n.t("icloud.hintTitle"), systemImage: "info.circle")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Nacht.sekundaer)
                Text(L10n.t("icloud.sideloadHint"))
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .listRowBackground(Papier.nachtkarton)
    }

    // MARK: Actions

    private func checkStatus() async {
        driveAvailable = UbiquityDrive.identityAvailable
        ckStatus = await CloudKitBackup.accountStatus()
        ckChecked = true
    }

    private func backupNow() {
        busy = true
        Task {
            let payload = await BackupService.makePayload(appState: appState,
                                                          includeLightData: false)
            do {
                try await CloudKitBackup.save(payload)
                lastBackupAt = CloudKitBackup.lastBackupAt
                Haptics.shared.success()
                appState.showToast(L10n.t("icloud.backupDone"), style: .success)
            } catch {
                appState.showToast(L10n.t("icloud.backupFailed"), style: .error)
            }
            busy = false
        }
    }

    private func restoreFromCloud() {
        busy = true
        Task {
            do {
                guard let payload = try await CloudKitBackup.fetch() else {
                    appState.showToast(L10n.t("icloud.noBackup"), style: .info)
                    busy = false
                    return
                }
                applyRestore(payload)
            } catch {
                appState.showToast(L10n.t("icloud.restoreFailed"), style: .error)
            }
            busy = false
        }
    }

    private func applyRestore(_ payload: AppBackupPayload) {
        let count = BackupService.restore(
            payload,
            appState: appState,
            options: BackupRestoreOptions(
                deviceSettings: restoreDeviceSettings,
                appGroupSettings: restoreAppGroupSettings,
                serverProfiles: restoreServerProfiles
            )
        )
        Haptics.shared.success()
        appState.showToast(L10n.t("icloud.restoreDone", ["n": String(count)]), style: .love)
        Task {
            await appState.reloadAfterRestore()
        }
        dismiss()
    }

    private func createExport() {
        busy = true
        Task {
            let payload = await BackupService.makePayload(appState: appState,
                                                          includeLightData: includeCoupleSnapshot,
                                                          includeServerProfiles: includeServerProfiles,
                                                          includeDeviceSettings: includeDeviceSettings,
                                                          includeAppGroupSettings: includeAppGroupSettings)
            do {
                let data = try BackupService.encodeEncrypted(payload, passphrase: exportPassphrase)
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("SoooDreamy-Backup.sooodreamy")
                try data.write(to: url, options: .atomic)
                exportURL = url
            } catch {
                appState.showToast(L10n.t("icloud.exportFailed"), style: .error)
            }
            busy = false
        }
    }

    private func exportToDrive() {
        busy = true
        Task {
            let payload = await BackupService.makePayload(appState: appState,
                                                          includeLightData: includeCoupleSnapshot,
                                                          includeServerProfiles: includeServerProfiles,
                                                          includeDeviceSettings: includeDeviceSettings,
                                                          includeAppGroupSettings: includeAppGroupSettings)
            do {
                let data = try BackupService.encodeEncrypted(payload, passphrase: exportPassphrase)
                _ = try await UbiquityDrive.writeExport(data)
                Haptics.shared.success()
                appState.showToast(L10n.t("icloud.exportDone"), style: .success)
            } catch {
                appState.showToast(L10n.t("icloud.exportFailed"), style: .error)
            }
            busy = false
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        do {
            pendingEncryptedFile = try Data(contentsOf: url)
            importPassphrase = ""
            askForImportPassphrase = true
        } catch {
            appState.showToast(L10n.t("icloud.importFailed"), style: .error)
        }
    }

    private func decryptImportedFile() {
        guard let data = pendingEncryptedFile else { return }
        do {
            pendingFilePayload = try BackupService.decodeEncrypted(data, passphrase: importPassphrase)
            pendingEncryptedFile = nil
            importPassphrase = ""
            confirmFileRestore = true
        } catch {
            appState.showToast(L10n.t("icloud.importPasswordFailed"), style: .error)
        }
    }

    private func restoreFromFile() {
        guard let payload = pendingFilePayload else { return }
        pendingFilePayload = nil
        applyRestore(payload)
    }
}
