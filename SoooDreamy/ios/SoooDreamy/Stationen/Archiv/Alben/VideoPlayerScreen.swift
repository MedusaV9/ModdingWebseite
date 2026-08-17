import AVFoundation
import AVKit
import SwiftUI
import UIKit

// Fullscreen video player (W9A component split from the 900-line
// VideoGalleryView): AVPlayer with authorized streaming, caption bar,
// favorite/caption/save/delete controls and the photo-library saver.

// MARK: - Fullscreen player

struct VideoPlayerScreen: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Binding var videos: [Video]
    let startId: String

    @State private var player: AVPlayer?
    @State private var confirmDelete = false
    @State private var editingCaption = false
    @State private var captionDraft = ""
    @State private var busy = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            playerArea
            overlayControls
        }
        .onAppear { startPlayback() }
        .onDisappear { player?.pause() }
        .confirmationDialog(L10n.t("memories.videos.deleteConfirm"),
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(L10n.t("common.delete"), role: .destructive) { deleteCurrent() }
            Button(L10n.t("common.cancel"), role: .cancel) {}
        }
        .alert(L10n.t("memories.gallery.editCaption"), isPresented: $editingCaption) {
            TextField(L10n.t("memories.gallery.captionPlaceholder"), text: $captionDraft)
            Button(L10n.t("common.save")) { saveCaption() }
            Button(L10n.t("common.cancel"), role: .cancel) {}
        }
        .onChange(of: currentVideo == nil) { _, gone in
            if gone { dismiss() }
        }
    }

    private var currentVideo: Video? {
        videos.first { $0.id == startId }
    }

    @ViewBuilder
    private var playerArea: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(aspectRatio, contentMode: .fit)
            } else {
                BusySpinner()
            }
            Spacer(minLength: 0)
            if let video = currentVideo {
                captionBar(video)
            }
        }
    }

    private var aspectRatio: CGFloat {
        guard let video = currentVideo,
              let width = video.width, let height = video.height,
              width > 0, height > 0 else { return 16 / 9 }
        return CGFloat(width) / CGFloat(height)
    }

    /// The clip's handwriting Zettel — polaroid paper with the couple's
    /// caption in serif voice and a postmark date line; the dark player
    /// around it deliberately stays immersive (lightbox exception).
    private func captionBar(_ video: Video) -> some View {
        HStack(alignment: .center, spacing: Space.m) {
            EmojiAvatarView(emoji: uploader(of: video)?.avatar,
                            colorHex: uploader(of: video)?.color,
                            size: LayoutMetrics.s(40))
            VStack(alignment: .leading, spacing: 2) {
                if let caption = video.caption, !caption.isEmpty {
                    Text(caption)
                        .font(Typo.voice)
                        .foregroundStyle(Tinte.dunkel)
                        .lineLimit(3)
                }
                Text(uploadInfo(video))
                    .font(Typo.anschrift(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize))
                    .foregroundStyle(Tinte.sekundaer)
            }
            Spacer()
        }
        .paperCard(.polaroid, padding: .compact)
        .padding(.horizontal, Space.l)
        .padding(.bottom, Space.xl)
    }

    private var overlayControls: some View {
        VStack {
            HStack(spacing: Space.l) {
                circleButton(icon: "xmark") { dismiss() }
                Spacer()
                if busy {
                    BusySpinner()
                        .padding(Space.m)
                } else {
                    favoriteButton
                    circleButton(icon: "pencil") {
                        captionDraft = currentVideo?.caption ?? ""
                        editingCaption = true
                    }
                    circleButton(icon: "square.and.arrow.down") { saveCurrent() }
                    if currentVideo?.uploaderId == appState.memberId {
                        circleButton(icon: "trash") { confirmDelete = true }
                    }
                }
            }
            .padding(.horizontal, Space.l)
            .padding(.top, Space.s)
            Spacer()
        }
    }

    private var currentIsFavorite: Bool {
        currentVideo?.isFavorite(of: appState.memberId) ?? false
    }

    private var favoriteButton: some View {
        circleButton(icon: currentIsFavorite ? "heart.fill" : "heart",
                     tint: currentIsFavorite ? coupleTint.blend : .white) {
            toggleFavorite()
        }
        .accessibilityLabel(L10n.t("memories.gallery.favorite"))
    }

    private func circleButton(icon: String, tint: Color = .white,
                              action: @escaping () -> Void) -> some View {
        Button {
            Haptics.shared.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(tint)
                .frame(width: LayoutMetrics.s(38), height: LayoutMetrics.s(38))
                .background(Circle().fill(Theme.hairline))
        }
        .buttonStyle(.plain)
    }

    private func uploader(of video: Video) -> Member? {
        appState.couple?.members.first { $0.id == video.uploaderId }
    }

    private func uploadInfo(_ video: Video) -> String {
        let name = video.uploaderId == appState.memberId
            ? L10n.t("common.you")
            : (uploader(of: video)?.name ?? appState.partnerName)
        let date = video.createdAt.formatted(date: .abbreviated, time: .shortened)
        var line = L10n.t("memories.gallery.by", ["name": name]) + " · " + date
        if let bytes = video.bytes, bytes > 0 {
            line += " · " + ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        }
        return line
    }

    // MARK: Actions

    private func startPlayback() {
        guard let video = currentVideo,
              let api = appState.api,
              let request = api.mediaRequest(video.url) else { return }
        let headers = request.allHTTPHeaderFields ?? [:]
        let asset = AVURLAsset(url: request.url!,
                               options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        let avPlayer = AVPlayer(playerItem: item)
        player = avPlayer
        avPlayer.play()
    }

    private func toggleFavorite() {
        guard let video = currentVideo, let api = appState.api else { return }
        Haptics.shared.success()
        Task {
            do {
                let updated = try await api.toggleVideoFavorite(id: video.id)
                merge(updated)
            } catch {
                appState.handleAPIError(error)
            }
        }
    }

    private func merge(_ video: Video) {
        guard let idx = videos.firstIndex(where: { $0.id == video.id }) else { return }
        videos[idx] = video
    }

    private func saveCaption() {
        guard let video = currentVideo, let api = appState.api else { return }
        let trimmed = captionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let target: String? = trimmed.isEmpty ? nil : trimmed
        guard (video.caption ?? "") != (target ?? "") else { return }
        busy = true
        Task {
            do {
                let updated = try await api.patchVideo(id: video.id, caption: .some(target))
                merge(updated)
                Haptics.shared.success()
                appState.showToast(L10n.t("memories.gallery.captionSaved"), style: .success)
            } catch {
                appState.handleAPIError(error)
            }
            busy = false
        }
    }

    private func deleteCurrent() {
        guard let video = currentVideo, let api = appState.api else { return }
        busy = true
        player?.pause()
        Task {
            do {
                try await api.deleteVideo(id: video.id)
                videos.removeAll { $0.id == video.id }
                appState.showToast(L10n.t("memories.videos.deleted"), style: .info)
                dismiss()
            } catch {
                appState.handleAPIError(error)
            }
            busy = false
        }
    }

    /// Download the MP4 to a temp file, then hand it to the photo library.
    private func saveCurrent() {
        guard let video = currentVideo,
              let request = appState.api?.mediaRequest(video.url) else { return }
        busy = true
        Task {
            do {
                let (tempURL, _) = try await URLSession.shared.download(for: request)
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("save-\(video.id).mp4")
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tempURL, to: dest)
                VideoSaver.save(path: dest.path) { ok in
                    try? FileManager.default.removeItem(at: dest)
                    if ok {
                        Haptics.shared.success()
                        appState.showToast(L10n.t("memories.videos.savedToLibrary"), style: .success)
                    } else {
                        appState.showToast(L10n.t("memories.videos.saveFailed"), style: .error)
                    }
                }
            } catch {
                appState.showToast(L10n.t("memories.videos.saveFailed"), style: .error)
            }
            busy = false
        }
    }
}

// MARK: - Photo library saver

/// UISaveVideoAtPathToSavedPhotosAlbum needs an Obj-C completion target;
/// instances keep themselves alive until the callback fires.
final class VideoSaver: NSObject {
    private static var active: [VideoSaver] = []
    private var completion: ((Bool) -> Void)?

    static func save(path: String, completion: @escaping (Bool) -> Void) {
        guard UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(path) else {
            completion(false)
            return
        }
        let saver = VideoSaver()
        saver.completion = completion
        active.append(saver)
        UISaveVideoAtPathToSavedPhotosAlbum(path, saver,
                                            #selector(VideoSaver.video(_:didFinishSavingWithError:contextInfo:)), nil)
    }

    @objc private func video(_ videoPath: String,
                             didFinishSavingWithError error: Error?,
                             contextInfo: UnsafeRawPointer) {
        let ok = error == nil
        DispatchQueue.main.async {
            self.completion?(ok)
            Self.active.removeAll { $0 === self }
        }
    }
}
