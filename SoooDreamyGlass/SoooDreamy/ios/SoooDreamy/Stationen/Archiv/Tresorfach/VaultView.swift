import AVKit
import PhotosUI
import SwiftUI
import UIKit

// Spicy Vault 🔒 — a separately locked, end-to-end encrypted space
// for private couple content (photos, videos, notes).
//
// Security properties (see VaultCrypto.swift for the format):
// - Own PIN, independent of the app lock; Face ID as convenience unlock.
// - Every blob is AES-GCM sealed ON-DEVICE; the server stores ciphertext.
// - Decrypted bytes live in memory only and are wiped on lock. (Exception:
//   video playback needs a short-lived temp file — written with complete
//   file protection and deleted the moment the player closes.)
// - Vault content NEVER appears in widgets, the shared snapshot, notifications
//   or the iCloud/file backup (those code paths simply don't know the vault).
// - Panic hide: shaking the device instantly locks the vault (optional).

struct VaultView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase

    @State private var vault = VaultSession()

    var body: some View {
        ZStack {
            DreamyBackground(showStars: false)
            switch vault.phase {
            case .loading:
                LoadingView()
            case .needsSetup:
                VaultSetupView(vault: vault)
            case .locked:
                VaultLockView(vault: vault)
            case .unlocked:
                VaultGridView(vault: vault)
            }
        }
        .navigationTitle(L10n.t("vault.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await vault.loadConfig(api: appState.api) }
        .onChange(of: scenePhase) { _, phase in
            // Leaving the app always relocks — no spicy content in the
            // app switcher or after handing the phone over.
            if phase != .active { vault.lock() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
            if UserDefaults.standard.object(forKey: "sooodreamy.vault.panicShake") as? Bool ?? true {
                vault.lock()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent else { return }
            vault.handle(event)
        }
    }
}

// MARK: - Setup

private struct VaultSetupView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    let vault: VaultSession

    @State private var pin = ""
    @State private var confirm = ""
    @State private var working = false
    @State private var mismatch = false

    var body: some View {
        ScrollView {
            VStack(spacing: Space.l) {
                Image(icon: .secret)
                    .font(Typo.hero)
                    .foregroundStyle(coupleTint.blend)
                    .symbolRenderingMode(.hierarchical)
                    .padding(.top, Space.xl)
                Text(L10n.t("vault.setup.title"))
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(Theme.textPrimary)
                Text(L10n.t("vault.setup.explain"))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                // The vault form is a sober NIGHT card (Schließfach-Ernst):
                // no grain, no tilt — and the error line is the night
                // error red (6.8:1 on night), never wax ink.
                VStack(spacing: Space.m) {
                    SecureField(L10n.t("vault.setup.pinField"), text: $pin)
                        .textFieldStyle(DreamyFieldStyle())
                        .keyboardType(.numberPad)
                    SecureField(L10n.t("vault.setup.confirmField"), text: $confirm)
                        .textFieldStyle(DreamyFieldStyle())
                        .keyboardType(.numberPad)
                    if mismatch {
                        Text(L10n.t("vault.setup.mismatch"))
                            .font(.system(.footnote, design: .rounded).weight(.semibold))
                            .foregroundStyle(Theme.energyRed)
                    }
                    if working {
                        BusySpinner(tint: coupleTint.blend)
                    } else {
                        Button(L10n.t("vault.setup.create")) {
                            createVault()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(pin.count < 4)
                    }
                }
                .nightCard(grain: false)
                Text(L10n.t("vault.setup.shareHint"))
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.l)
        }
    }

    private func createVault() {
        guard pin == confirm else {
            mismatch = true
            Haptics.shared.warning()
            return
        }
        mismatch = false
        working = true
        Task {
            let ok = await vault.setup(pin: pin, api: appState.api)
            if ok {
                Haptics.shared.success()
                SoundEngine.shared.play(.sparkle)
            } else {
                appState.showToast(vault.errorMessage ?? L10n.t("vault.setup.failed"),
                                   style: .error)
            }
            working = false
        }
    }
}

// MARK: - Lock screen

private struct VaultLockView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    let vault: VaultSession

    @State private var pin = ""
    @State private var working = false
    @State private var wrongPin = false
    @State private var confirmReset = false

    var body: some View {
        VStack(spacing: Space.l) {
            Spacer()
            // Blurred teaser grid — hints that something is inside without
            // revealing anything (the real content isn't even downloaded).
            blurredTeaser
            Text(L10n.t("vault.locked.title"))
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(Theme.textPrimary)
            // Sober night lock form — see the setup card.
            VStack(spacing: Space.m) {
                SecureField(L10n.t("vault.locked.pinField"), text: $pin)
                    .textFieldStyle(DreamyFieldStyle())
                    .keyboardType(.numberPad)
                    .onSubmit { unlockWithPin() }
                if wrongPin {
                    Text(L10n.t("vault.locked.wrongPin"))
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.energyRed)
                }
                if working {
                    BusySpinner(tint: coupleTint.blend)
                } else {
                    Button(L10n.t("vault.locked.unlock")) {
                        unlockWithPin()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(pin.count < 4)
                    if vault.biometricsAvailable {
                        Button {
                            unlockWithBiometrics()
                        } label: {
                            Label(L10n.t("vault.locked.faceId"), systemImage: "faceid")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
            .nightCard(grain: false)
            Button(L10n.t("vault.locked.forgot")) {
                confirmReset = true
            }
            .font(.system(.footnote, design: .rounded).weight(.semibold))
            .foregroundStyle(Theme.textTertiary)
            Spacer()
        }
        .padding(Space.l)
        .task {
            // Offer Face ID right away when a stored key exists.
            if vault.biometricsAvailable {
                unlockWithBiometrics()
            }
        }
        .confirmationDialog(L10n.t("vault.reset.title"),
                            isPresented: $confirmReset, titleVisibility: .visible) {
            Button(L10n.t("vault.reset.confirm"), role: .destructive) { resetVault() }
            Button(L10n.t("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("vault.reset.message"))
        }
    }

    private var blurredTeaser: some View {
        HStack(spacing: Space.s) {
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(LinearGradient(colors: [coupleTint.primary.opacity(0.45),
                                                  coupleTint.secondary.opacity(0.4)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: LayoutMetrics.s(58), height: LayoutMetrics.s(58))
                    .overlay(
                        Text(["🔥", "💋", "🌶️", "💦"][i])
                            .font(.system(.title3))
                    )
                    .blur(radius: 7)
                    .overlay(
                        Image(systemName: "lock.fill")
                            .font(.system(.footnote, design: .rounded).weight(.bold))
                            .foregroundStyle(Theme.textPrimary.opacity(0.85))
                    )
            }
        }
    }

    private func unlockWithPin() {
        guard pin.count >= 4, !working else { return }
        working = true
        wrongPin = false
        Task {
            let ok = await vault.unlock(pin: pin, api: appState.api)
            if ok {
                AppCue.unlock.play()
            } else {
                wrongPin = true
                pin = ""
                Haptics.shared.warning()
            }
            working = false
        }
    }

    private func unlockWithBiometrics() {
        guard !working else { return }
        working = true
        Task {
            let ok = await vault.unlockWithBiometrics(api: appState.api)
            if ok {
                AppCue.unlock.play()
            }
            working = false
        }
    }

    private func resetVault() {
        working = true
        Task {
            do {
                try await vault.reset(api: appState.api)
                appState.showToast(L10n.t("vault.reset.done"), style: .info)
            } catch {
                appState.handleAPIError(error)
            }
            working = false
        }
    }
}

// MARK: - Unlocked grid

private struct VaultGridView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    let vault: VaultSession

    @State private var photoItem: PhotosPickerItem?
    @State private var videoItem: PhotosPickerItem?
    @State private var showNoteComposer = false
    @State private var showPhotoPicker = false
    @State private var showVideoPicker = false
    @State private var processing: String?
    @State private var viewerTarget: VaultItem?

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        ZStack {
            content
            addButton
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Haptics.shared.tap()
                    vault.lock()
                } label: {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(coupleTint.blend)
                }
                .accessibilityLabel(L10n.t("vault.lockNow"))
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task { await addPhoto(item) }
        }
        .onChange(of: videoItem) { _, item in
            guard let item else { return }
            videoItem = nil
            Task { await addVideo(item) }
        }
        .sheet(isPresented: $showNoteComposer) {
            VaultNoteComposer { title, text in
                addNote(title: title, text: text)
            }
        }
        .fullScreenCover(item: $viewerTarget) { item in
            VaultItemViewer(vault: vault, item: item)
        }
    }

    @ViewBuilder
    private var content: some View {
        if vault.items.isEmpty {
            VStack {
                Spacer()
                EmptyStateView(systemImage: "flame",
                               title: L10n.t("vault.empty.title"),
                               subtitle: L10n.t("vault.empty.subtitle"),
                               actionTitle: L10n.t("vault.empty.action"),
                               action: {
                                   Haptics.shared.tap()
                                   showNoteComposer = true
                               })
                Spacer()
            }
        } else {
            ScrollView {
                Text(L10n.t("vault.shakeHint"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, Space.s)
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(vault.items) { item in
                        Button {
                            Haptics.shared.tap()
                            viewerTarget = item
                        } label: {
                            VaultItemCell(vault: vault, item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Space.m)
                .padding(.top, Space.xs)
                .padding(.bottom, LayoutMetrics.s(96))
            }
            .refreshable {
                if let api = appState.api { await vault.refreshItems(api: api) }
            }
        }
    }

    private var addButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Menu {
                    // PhotosPicker can't live inside Menu — route via flags.
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label(L10n.t("vault.add.photo"), systemImage: "photo")
                    }
                    Button {
                        showVideoPicker = true
                    } label: {
                        Label(L10n.t("vault.add.video"), systemImage: "video")
                    }
                    Button {
                        showNoteComposer = true
                    } label: {
                        Label(L10n.t("vault.add.note"), systemImage: "note.text")
                    }
                } label: {
                    ZStack {
                        // Computed ink + platter: white read only 2.94:1 on
                        // the static brand gradient (Schlussrunde 5).
                        Theme.heroPlatter(in: Circle())
                            .frame(width: LayoutMetrics.s(60), height: LayoutMetrics.s(60))
                            .shadow(color: coupleTint.blend.opacity(0.5), radius: 14, y: 6)
                        if processing != nil {
                            BusySpinner(tint: Theme.onHero)
                        } else {
                            Image(systemName: "plus")
                                .font(.system(.title2, design: .rounded).weight(.bold))
                                .foregroundStyle(Theme.onHero)
                        }
                    }
                }
                .disabled(processing != nil)
                .padding(.trailing, Space.xl)
                .padding(.bottom, Space.xl)
            }
        }
        .overlay(alignment: .bottom) {
            if let processing {
                Text(processing)
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, Space.s)
                    .padding(.horizontal, Space.l)
                    .glass(.chrome, in: Capsule())
                    .padding(.bottom, LayoutMetrics.s(96))
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .photosPicker(isPresented: $showVideoPicker, selection: $videoItem, matching: .videos)
    }

    // MARK: Add flows

    private func addPhoto(_ item: PhotosPickerItem) async {
        processing = L10n.t("vault.encrypting")
        defer { processing = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            appState.showToast(L10n.t("memories.gallery.readFailed"), style: .error)
            return
        }
        let scaled = GalleryView.downscaled(image, maxDimension: 2048)
        guard let jpeg = scaled.jpegData(compressionQuality: 0.85) else { return }
        let poster = GalleryView.downscaled(image, maxDimension: 240)
            .jpegData(compressionQuality: 0.5)
        let meta = VaultMeta(kind: "photo", caption: nil, poster: poster,
                             duration: nil,
                             width: Int(scaled.size.width), height: Int(scaled.size.height))
        await sealAndUpload(meta: meta, content: jpeg)
    }

    private func addVideo(_ item: PhotosPickerItem) async {
        processing = L10n.t("memories.videos.compressing")
        defer { processing = nil }
        do {
            guard let picked = try await item.loadTransferable(type: PickedVaultVideo.self) else {
                appState.showToast(L10n.t("memories.videos.readFailed"), style: .error)
                return
            }
            let result = try await VideoTranscoder.compress(sourceURL: picked.url)
            try? FileManager.default.removeItem(at: picked.url)
            defer { try? FileManager.default.removeItem(at: result.fileURL) }
            guard result.data.count <= 55 * 1024 * 1024 else {
                appState.showToast(L10n.t("vault.tooBig"), style: .error)
                return
            }
            processing = L10n.t("vault.encrypting")
            let poster = result.poster.flatMap {
                GalleryView.downscaled($0, maxDimension: 240).jpegData(compressionQuality: 0.5)
            }
            let meta = VaultMeta(kind: "video", caption: nil, poster: poster,
                                 duration: result.duration,
                                 width: result.width, height: result.height)
            await sealAndUpload(meta: meta, content: result.data)
        } catch {
            appState.showToast(L10n.t("memories.videos.readFailed"), style: .error)
        }
    }

    private func addNote(title: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        processing = L10n.t("vault.encrypting")
        let meta = VaultMeta(kind: "note",
                             caption: title.trimmingCharacters(in: .whitespacesAndNewlines),
                             poster: nil, duration: nil, width: nil, height: nil)
        Task {
            await sealAndUpload(meta: meta, content: Data(trimmed.utf8))
            processing = nil
        }
    }

    private func sealAndUpload(meta: VaultMeta, content: Data) async {
        do {
            processing = L10n.t("vault.uploading")
            _ = try await vault.upload(meta: meta, content: content, api: appState.api)
            Haptics.shared.success()
            SoundEngine.shared.play(.sparkle)
            appState.showToast(L10n.t("vault.uploaded"), style: .love)
        } catch {
            appState.handleAPIError(error)
        }
    }
}

/// Vault-private movie transfer (same tmp-copy trick as the gallery's).
private struct PickedVaultVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("vault-picked-\(UUID().uuidString).mov")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedVaultVideo(url: dest)
        }
    }
}

// MARK: - Grid cell

private struct VaultItemCell: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    let vault: VaultSession
    let item: VaultItem

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(preview)
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: Theme.hairlineWidth)
            )
            .overlay(alignment: .bottomTrailing) { kindBadge }
            .task(id: item.id) {
                // Fetch + decrypt lazily; the tiny poster inside the meta
                // makes this cheap even for videos.
                if vault.cached(item.id) == nil {
                    _ = await vault.decrypt(item, api: appState.api)
                }
            }
    }

    @ViewBuilder
    private var preview: some View {
        let _ = vault.cacheVersion // observe cache updates
        if let decrypted = vault.cached(item.id) {
            if let poster = decrypted.posterImage ?? decrypted.image {
                Image(uiImage: poster)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let note = decrypted.noteText {
                notePreview(title: decrypted.meta.caption, text: note)
            } else {
                placeholder
            }
        } else {
            placeholder
        }
    }

    private func notePreview(title: String?, text: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(Typo.caption)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            Text(text)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(4)
            Spacer(minLength: 0)
        }
        .padding(Space.s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(colors: [coupleTint.secondary.opacity(0.35),
                                    coupleTint.primary.opacity(0.3)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [coupleTint.primary.opacity(0.28),
                                    coupleTint.secondary.opacity(0.24)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            BusySpinner(tint: Theme.textTertiary)
        }
    }

    @ViewBuilder
    private var kindBadge: some View {
        let icon = switch item.kind {
        case "video": "video.fill"
        case "note": "note.text"
        default: "photo.fill"
        }
        Image(systemName: icon)
            .font(.system(.caption2, design: .rounded).weight(.bold))
            .foregroundStyle(Theme.textPrimary.opacity(0.9))
            .padding(Space.xs)
            .background(Circle().fill(Color.black.opacity(0.4)))
            .padding(Space.xs)
    }
}

// MARK: - Note composer

private struct VaultNoteComposer: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint
    let onSave: (String, String) -> Void

    @State private var title = ""
    @State private var text = ""

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                VStack(spacing: Space.m) {
                    // Writing happens on paper — free-standing slips on
                    // the night canvas (dark ink, readable).
                    TextField(L10n.t("vault.note.titleField"), text: $title)
                        .textFieldStyle(ChatPaperFieldStyle())
                    TextField(L10n.t("vault.note.textField"), text: $text, axis: .vertical)
                        .textFieldStyle(ChatPaperFieldStyle(font: Typo.brief))
                        .lineLimit(6...14)
                    Button(L10n.t("vault.note.save")) {
                        Haptics.shared.tap()
                        dismiss()
                        onSave(title, text)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                }
                .padding(Space.l)
            }
            .navigationTitle(L10n.t("vault.add.note"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                        .tint(coupleTint.blend)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Shake detection (panic hide)

extension Notification.Name {
    /// Posted by UIWindow when the user shakes the device.
    static let deviceDidShake = Notification.Name("sooodreamy.deviceDidShake")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
    }
}
