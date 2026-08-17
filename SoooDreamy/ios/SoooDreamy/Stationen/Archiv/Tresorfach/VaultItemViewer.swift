import AVKit
import SwiftUI

// Fullscreen vault viewer (W9A component split from the 850-line
// VaultView): decrypts one item in memory and shows it on the shared
// MediaLightbox shell — zoomable photo, temp-file video or note text.

// MARK: - Fullscreen viewer

struct VaultItemViewer: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let vault: VaultSession
    let item: VaultItem

    @State private var decrypted: DecryptedVaultItem?
    @State private var player: AVPlayer?
    @State private var tempVideoURL: URL?
    @State private var confirmDelete = false
    @State private var busy = false
    @State private var zoomed = false
    @State private var chromeVisible = true

    /// Drag-down dismiss only where no other gesture owns vertical pans:
    /// photos at 1× — the video player and the scrolling note keep theirs.
    private var dragDismissEnabled: Bool {
        decrypted?.meta.kind == "photo" && !zoomed
    }

    var body: some View {
        MediaLightboxShell(dragDismissEnabled: dragDismissEnabled,
                           onDismiss: { dismiss() }) {
            content
        } chrome: {
            if chromeVisible {
                controls
            }
        }
        .task { await load() }
        .onDisappear { cleanupVideo() }
        .confirmationDialog(L10n.t("vault.deleteConfirm"),
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L10n.t("common.delete"), role: .destructive) { deleteItem() }
            Button(L10n.t("common.cancel"), role: .cancel) {}
        }
    }

    @ViewBuilder
    private var content: some View {
        if let decrypted {
            switch decrypted.meta.kind {
            case "photo":
                if let image = decrypted.image {
                    // Same zoom engine as gallery and chat (B-31) — the vault
                    // photo is decrypted in memory, so it feeds the scroll
                    // view directly instead of going through the pipeline.
                    ZoomableImageView(image: image,
                                      onZoomedChange: { zoomed = $0 },
                                      onSingleTap: {
                                          withAnimation(Theme.Motion.settle) {
                                              chromeVisible.toggle()
                                          }
                                      })
                }
            case "video":
                if let player {
                    VideoPlayer(player: player)
                } else {
                    BusySpinner()
                }
            default:
                noteView(decrypted)
            }
        } else {
            VStack(spacing: Space.m) {
                BusySpinner()
                Text(L10n.t("vault.decrypting"))
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func noteView(_ decrypted: DecryptedVaultItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.m) {
                if let title = decrypted.meta.caption, !title.isEmpty {
                    Text(title)
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .foregroundStyle(Theme.textPrimary)
                }
                Text(decrypted.noteText ?? "")
                    .font(Typo.body)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.xl)
            .padding(.top, LayoutMetrics.s(60))
        }
    }

    private var controls: some View {
        VStack {
            HStack(spacing: Space.l) {
                Button {
                    Haptics.shared.tap()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: LayoutMetrics.s(38), height: LayoutMetrics.s(38))
                        .background(Circle().fill(Theme.hairline))
                }
                .buttonStyle(.plain)
                Spacer()
                if busy {
                    BusySpinner()
                } else {
                    Button {
                        Haptics.shared.tap()
                        confirmDelete = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: LayoutMetrics.s(38), height: LayoutMetrics.s(38))
                            .background(Circle().fill(Theme.hairline))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.s)
            Spacer()
        }
    }

    private func load() async {
        decrypted = await vault.decrypt(item, api: appState.api)
        guard let decrypted, decrypted.meta.kind == "video" else { return }
        // AVPlayer needs a file — short-lived, protected, deleted on close.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-play-\(item.id).mp4")
        do {
            try decrypted.content.write(to: url, options: [.atomic, .completeFileProtection])
            tempVideoURL = url
            let avPlayer = AVPlayer(url: url)
            player = avPlayer
            avPlayer.play()
        } catch {
            appState.showToast(L10n.t("vault.decryptFailed"), style: .error)
        }
    }

    private func cleanupVideo() {
        player?.pause()
        player = nil
        if let tempVideoURL {
            try? FileManager.default.removeItem(at: tempVideoURL)
        }
        tempVideoURL = nil
    }

    private func deleteItem() {
        busy = true
        Task {
            do {
                try await vault.delete(item, api: appState.api)
                appState.showToast(L10n.t("vault.deleted"), style: .info)
                dismiss()
            } catch {
                appState.handleAPIError(error)
            }
            busy = false
        }
    }
}
