import AVFoundation
import AVKit
import Combine
import PhotosUI
import SwiftUI
import UIKit

/// Shared video gallery: grid of clips with duration badges,
/// PhotosPicker upload with client-side H.264 compression, poster thumbnails,
/// and a fullscreen AVPlayer (server streams with Range support).
struct VideoGalleryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint

    @State private var videos: [Video] = []
    @State private var loading = true
    @State private var pickerItem: PhotosPickerItem?
    @State private var pendingUpload: PendingVideoUpload?
    /// nil = idle, otherwise the current phase label under the spinner.
    @State private var processingPhase: String?
    /// The running read/estimate/transcode task — the pill's cancel button
    /// stops it cooperatively (no half-imported video ever shows up).
    @State private var prepareTask: Task<Void, Never>?
    @State private var playerTarget: Video?
    @State private var favoritesOnly = false
    /// The empty state's own way into the video picker.
    @State private var emptyStatePicker = false

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: Space.s),
         GridItem(.flexible(), spacing: Space.s)]
    }

    var body: some View {
        ZStack {
            DreamyBackground(showStars: false)
            content
            floatingAddButton
        }
        .navigationTitle(L10n.t("memories.videos.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                favoritesToggle
            }
        }
        .task { await loadVideos() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            prepareTask = Task { await prepareVideo(item) }
        }
        .sheet(item: $pendingUpload) { pending in
            VideoCaptionSheet(pending: pending) { caption in
                upload(pending, caption: caption)
            }
        }
        .fullScreenCover(item: $playerTarget) { video in
            VideoPlayerScreen(videos: $videos, startId: video.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent else { return }
            handleServerEvent(event)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if loading {
            LoadingView()
        } else if videos.isEmpty {
            emptyState
        } else if favoritesOnly && displayedVideos.isEmpty {
            VStack {
                Spacer()
                EmptyStateView(systemImage: "heart",
                               title: L10n.t("memories.gallery.favEmpty.title"),
                               subtitle: L10n.t("memories.videos.favEmpty.subtitle"),
                               actionTitle: L10n.t("memories.videos.favEmpty.action"),
                               action: {
                                   Haptics.shared.tap()
                                   withAnimation(Theme.Motion.settle) { favoritesOnly = false }
                               })
                Spacer()
            }
        } else {
            grid
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            EmptyStateView(systemImage: "film",
                           title: L10n.t("memories.videos.empty.title"),
                           subtitle: L10n.t("memories.videos.empty.subtitle"),
                           actionTitle: L10n.t("memories.videos.empty.action"),
                           action: {
                               Haptics.shared.tap()
                               emptyStatePicker = true
                           })
            Spacer()
        }
        .photosPicker(isPresented: $emptyStatePicker, selection: $pickerItem,
                      matching: .videos, photoLibrary: .shared())
    }

    private var displayedVideos: [Video] {
        favoritesOnly ? videos.filter { !($0.favorites ?? []).isEmpty } : videos
    }

    private var favoritesToggle: some View {
        Button {
            Haptics.shared.tap()
            withAnimation(Theme.Motion.settle) { favoritesOnly.toggle() }
        } label: {
            Image(systemName: favoritesOnly ? "heart.fill" : "heart")
                .foregroundStyle(coupleTint.blend)
        }
        .accessibilityLabel(L10n.t("memories.gallery.filterFavorites"))
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Space.s) {
                ForEach(displayedVideos) { video in
                    Button {
                        Haptics.shared.tap()
                        playerTarget = video
                    } label: {
                        VideoCell(video: video, api: appState.api, memberId: appState.memberId)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Space.m)
            .padding(.top, Space.m)
            .padding(.bottom, LayoutMetrics.s(96))
        }
        .refreshable { await loadVideos() }
    }

    private var floatingAddButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                PhotosPicker(selection: $pickerItem, matching: .videos, photoLibrary: .shared()) {
                    ZStack {
                        // Computed ink + platter: white read only 2.94:1 on
                        // the static brand gradient (Schlussrunde 5).
                        Theme.heroPlatter(in: Circle())
                            .frame(width: LayoutMetrics.s(60), height: LayoutMetrics.s(60))
                            .shadow(color: coupleTint.blend.opacity(0.5), radius: 14, y: 6)
                        if processingPhase != nil {
                            BusySpinner(tint: Theme.onHero)
                        } else {
                            Image(systemName: "video.badge.plus")
                                .font(.system(.title3, design: .rounded).weight(.bold))
                                .foregroundStyle(Theme.onHero)
                        }
                    }
                }
                .disabled(processingPhase != nil)
                .accessibilityLabel(L10n.t("memories.videos.add"))
                .padding(.trailing, Space.xl)
                .padding(.bottom, Space.xl)
            }
        }
        .overlay(alignment: .bottom) {
            if let phase = processingPhase {
                HStack(spacing: Space.s) {
                    Text(phase)
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Button {
                        Haptics.shared.tap()
                        prepareTask?.cancel()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("common.cancel"))
                }
                .padding(.vertical, Space.s)
                .padding(.horizontal, Space.l)
                .glass(.chrome, in: Capsule())
                .padding(.bottom, LayoutMetrics.s(96))
                .transition(.opacity)
            }
        }
    }

    // MARK: Data

    private func loadVideos() async {
        guard let api = appState.api else { return }
        do {
            let list = try await api.videos()
            videos = list.sorted { $0.createdAt > $1.createdAt }
        } catch {
            appState.handleAPIError(error)
        }
        loading = false
    }

    private func apply(_ video: Video) {
        if let idx = videos.firstIndex(where: { $0.id == video.id }) {
            videos[idx] = video
        } else {
            videos.append(video)
            videos.sort { $0.createdAt > $1.createdAt }
        }
    }

    // MARK: Upload flow

    /// Copy the picked movie into a temp file, estimate the output size
    /// (BEFORE the expensive transcode — 41#7), compress at the first preset
    /// that fits, grab a poster frame — then hand off to the caption sheet.
    /// Cooperatively cancelable via the pill's cancel button.
    private func prepareVideo(_ item: PhotosPickerItem) async {
        withAnimation { processingPhase = L10n.t("memories.videos.reading") }
        defer { withAnimation { processingPhase = nil } }
        do {
            guard let picked = try await item.loadTransferable(type: PickedVideo.self) else {
                appState.showToast(L10n.t("memories.videos.readFailed"), style: .error)
                return
            }
            defer { try? FileManager.default.removeItem(at: picked.url) }

            // Pre-flight: no preset fits → honest rejection in seconds, not
            // after minutes of pointless transcoding.
            guard let estimate = await VideoTranscoder.estimate(
                sourceURL: picked.url, maxBytes: 100 * 1024 * 1024) else {
                appState.showToast(L10n.t("memories.videos.tooBigEstimate"), style: .error)
                return
            }
            try Task.checkCancellation()

            withAnimation { processingPhase = L10n.t("memories.videos.compressing") }
            let result = try await VideoTranscoder.compress(sourceURL: picked.url,
                                                            preset: estimate.preset)
            guard result.data.count <= 100 * 1024 * 1024 else {
                appState.showToast(L10n.t("memories.videos.tooBig"), style: .error)
                try? FileManager.default.removeItem(at: result.fileURL)
                return
            }
            try Task.checkCancellation()
            pendingUpload = PendingVideoUpload(mp4: result.data,
                                               fileURL: result.fileURL,
                                               poster: result.poster,
                                               width: result.width,
                                               height: result.height,
                                               duration: result.duration)
        } catch is CancellationError {
            // The couple changed their mind — no error theater.
        } catch {
            appState.showToast(L10n.t("memories.videos.readFailed"), style: .error)
        }
    }

    private func upload(_ pending: PendingVideoUpload, caption: String) {
        guard let api = appState.api else { return }
        withAnimation { processingPhase = L10n.t("memories.videos.uploading") }
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let video = try await api.uploadVideo(mp4: pending.mp4,
                                                      caption: trimmed.isEmpty ? nil : trimmed,
                                                      width: pending.width,
                                                      height: pending.height,
                                                      duration: pending.duration)
                apply(video)
                SoundEngine.shared.play(.sparkle)
                Haptics.shared.success()
                appState.showToast(L10n.t("memories.videos.uploaded"), style: .love)
                // Poster thumbnail is best effort — the grid falls back to a
                // film placeholder until (and unless) it lands.
                if let poster = pending.poster,
                   let jpeg = poster.jpegData(compressionQuality: 0.7),
                   let updated = try? await api.uploadVideoThumb(videoId: video.id, jpeg: jpeg) {
                    apply(updated)
                }
            } catch {
                appState.handleAPIError(error)
            }
            try? FileManager.default.removeItem(at: pending.fileURL)
            withAnimation { processingPhase = nil }
        }
    }

    // MARK: Realtime

    private func handleServerEvent(_ event: ServerEvent) {
        switch event.type {
        case .videoAdded:
            guard let video = event.decode(VideoResponse.self)?.video else { return }
            let isNew = !videos.contains(where: { $0.id == video.id })
            apply(video)
            if isNew && video.uploaderId != appState.memberId {
                SoundEngine.shared.play(.pop)
            }
        case .videoUpdated:
            guard let video = event.decode(VideoResponse.self)?.video else { return }
            apply(video)
        case .videoDeleted:
            guard let id = event.decode(IdPayload.self)?.id else { return }
            videos.removeAll { $0.id == id }
        default:
            break
        }
    }
}

// MARK: - Picked video transfer

/// PhotosPicker hands movies over as files — copy into our tmp dir so the
/// data survives past the transfer callback.
private struct PickedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("picked-\(UUID().uuidString).mov")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedVideo(url: dest)
        }
    }
}

// MARK: - Transcoder

/// Client-side compression: 720p H.264/MP4 via AVAssetExportSession keeps
/// uploads well under the server's 100 MB cap. Also extracts dimensions,
/// duration and a poster frame (first ~0.5 s).
enum VideoTranscoder {
    struct Result {
        let data: Data
        let fileURL: URL
        let poster: UIImage?
        let width: Int?
        let height: Int?
        let duration: Double?
    }

    /// Adaptive preset ladder (41#7): quality first, then smaller frames.
    /// A long clip that would bust the cap at 720p often still fits at 540p.
    static let presetLadder = [AVAssetExportPreset1280x720,
                               AVAssetExportPreset960x540,
                               AVAssetExportPreset640x480]

    struct Estimate {
        let preset: String
        /// 0 = the container refused an estimate — transcode and re-check.
        let bytes: Int64
    }

    /// Cheap pre-flight WITHOUT transcoding: walks the preset ladder and
    /// returns the first one whose estimated output fits `maxBytes`.
    /// nil = even the smallest preset would bust the cap — say so BEFORE
    /// burning minutes of transcoding.
    static func estimate(sourceURL: URL, maxBytes: Int64) async -> Estimate? {
        let asset = AVURLAsset(url: sourceURL)
        for preset in presetLadder {
            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
                continue
            }
            session.shouldOptimizeForNetworkUse = true
            do {
                let bytes = try await session.estimatedOutputFileLengthInBytes
                if bytes <= 0 {
                    // No estimate available — proceed at this preset; the
                    // post-compress size check still guards the cap.
                    return Estimate(preset: preset, bytes: 0)
                }
                if bytes <= maxBytes {
                    return Estimate(preset: preset, bytes: bytes)
                }
            } catch {
                return Estimate(preset: preset, bytes: 0)
            }
        }
        return nil
    }

    static func compress(sourceURL: URL,
                         preset: String = AVAssetExportPreset1280x720) async throws -> Result {
        let asset = AVURLAsset(url: sourceURL)
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("upload-\(UUID().uuidString).mp4")

        guard let session = AVAssetExportSession(asset: asset,
                                                 presetName: preset) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        session.shouldOptimizeForNetworkUse = true
        try await session.export(to: outURL, as: .mp4)

        let data = try Data(contentsOf: outURL)
        let exported = AVURLAsset(url: outURL)
        let seconds = (try? await exported.load(.duration).seconds) ?? nil

        var width: Int?
        var height: Int?
        if let track = try? await exported.loadTracks(withMediaType: .video).first,
           let loaded = try? await track.load(.naturalSize, .preferredTransform) {
            let rect = CGRect(origin: .zero, size: loaded.0).applying(loaded.1)
            width = Int(abs(rect.width).rounded())
            height = Int(abs(rect.height).rounded())
        }

        let generator = AVAssetImageGenerator(asset: exported)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        let posterTime = CMTime(seconds: min(0.5, (seconds ?? 1) / 2), preferredTimescale: 600)
        let poster = (try? await generator.image(at: posterTime).image).map { UIImage(cgImage: $0) }

        return Result(data: data, fileURL: outURL, poster: poster,
                      width: width, height: height, duration: seconds)
    }
}

// MARK: - Pending upload

private struct PendingVideoUpload: Identifiable {
    let id = UUID()
    let mp4: Data
    let fileURL: URL
    let poster: UIImage?
    let width: Int?
    let height: Int?
    let duration: Double?
}

// MARK: - Grid cell (polaroid)

/// A clip as a polaroid print, like the photo album next door: the frame
/// is `Papier.polaroid` with the wider instant-film bottom; play and
/// duration stay scrim chrome OVER the moving print, the favorite heart
/// signs the paper strip in ink.
private struct VideoCell: View {
    @Environment(\.coupleTint) private var coupleTint
    let video: Video
    let api: API?
    let memberId: String?

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(thumbnail)
                .clipShape(RoundedRectangle(cornerRadius: Radius.polaroid,
                                            style: .continuous))
                .overlay(alignment: .center) { playBadge }
                .overlay(alignment: .bottomTrailing) { durationBadge }
            captionStrip
        }
        .padding(.top, Space.xs)
        .padding(.horizontal, Space.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.polaroid, style: .continuous)
                .fill(Papier.polaroid)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.polaroid, style: .continuous)
                        .strokeBorder(PaperLightEdge.gradient,
                                      lineWidth: Theme.hairlineWidth)
                )
                .elevation(.resting)
        )
    }

    /// The wide polaroid bottom: caption handwriting when there is one,
    /// the favorite heart always in readable ink.
    private var captionStrip: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            if let caption = video.caption, !caption.isEmpty {
                Text(caption)
                    .font(Typo.voice)
                    .foregroundStyle(Tinte.dunkel)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            favoriteBadge
        }
        .padding(.vertical, Space.xs)
        .frame(minHeight: LayoutMetrics.s(20))
    }

    private var playBadge: some View {
        Image(systemName: "play.fill")
            .font(.system(.title3, design: .rounded).weight(.bold))
            .foregroundStyle(Papier.aufNacht.opacity(0.92))
            .padding(Space.m)
            .background(Circle().fill(Color.black.opacity(0.35)))
    }

    @ViewBuilder
    private var durationBadge: some View {
        if let label = video.durationLabel {
            Text(label)
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .foregroundStyle(Papier.aufNacht)
                .padding(.vertical, Space.xs)
                .padding(.horizontal, Space.s)
                .background(Capsule().fill(Color.black.opacity(0.45)))
                .padding(Space.xs)
        }
    }

    @ViewBuilder
    private var favoriteBadge: some View {
        if !(video.favorites ?? []).isEmpty {
            Image(systemName: "heart.fill")
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(video.isFavorite(of: memberId)
                                 ? coupleTint.tinte : Tinte.sekundaer)
                .accessibilityLabel(L10n.t("memories.gallery.filterFavorites"))
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let thumbUrl = video.thumbUrl, api != nil {
            AuthenticatedAsyncImage(api: api, path: thumbUrl) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    placeholder
                default:
                    ZStack {
                        placeholder
                        BusySpinner(tint: Theme.textTertiary)
                    }
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [coupleTint.secondary.opacity(0.30),
                                    coupleTint.primary.opacity(0.22)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "film")
                .font(.system(.title2))
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

// MARK: - Caption sheet

private struct VideoCaptionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint
    let pending: PendingVideoUpload
    let onUpload: (String) -> Void

    @State private var caption = ""

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                ScrollView {
                    VStack(spacing: Space.l) {
                        posterPreview
                        infoLine
                        TextField(L10n.t("memories.gallery.captionPlaceholder"),
                                  text: $caption, axis: .vertical)
                            .textFieldStyle(ChatPaperFieldStyle(font: Typo.voice))
                            .lineLimit(1...3)
                        Button(L10n.t("memories.gallery.upload")) {
                            Haptics.shared.tap()
                            dismiss()
                            onUpload(caption)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        Spacer()
                    }
                    .padding(Space.l)
                }
            }
            .navigationTitle(L10n.t("memories.videos.captionTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                        .tint(coupleTint.blend)
                }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var posterPreview: some View {
        // The fresh clip develops inside its polaroid frame — analog to
        // the photo caption sheet.
        if let poster = pending.poster {
            Image(uiImage: poster)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: LayoutMetrics.s(300))
                .clipShape(RoundedRectangle(cornerRadius: Radius.polaroid,
                                            style: .continuous))
                .overlay(
                    Image(systemName: "play.circle.fill")
                        .font(.system(.largeTitle))
                        .foregroundStyle(Papier.aufNacht.opacity(0.9))
                )
                .padding(.top, Space.s)
                .padding(.horizontal, Space.s)
                .padding(.bottom, Space.xl)
                .background(
                    RoundedRectangle(cornerRadius: Radius.polaroid, style: .continuous)
                        .fill(Papier.polaroid)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.polaroid,
                                             style: .continuous)
                                .strokeBorder(PaperLightEdge.gradient,
                                              lineWidth: Theme.hairlineWidth))
                        .elevation(.raised)
                )
        } else {
            RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                .fill(Papier.nachtkarton)
                .frame(height: LayoutMetrics.s(200))
                .overlay(
                    Image(systemName: "film")
                        .font(.system(.largeTitle))
                        .foregroundStyle(Nacht.tertiaer)
                )
                .elevation(.resting)
        }
    }

    private var infoLine: some View {
        HStack(spacing: Space.m) {
            if let duration = pending.duration, duration > 0 {
                let total = Int(duration.rounded())
                PillTag(text: String(format: "%d:%02d", total / 60, total % 60),
                        tint: Theme.blue)
            }
            PillTag(text: sizeLabel, tint: Theme.mint)
            Spacer()
        }
    }

    private var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(pending.mp4.count), countStyle: .file)
    }
}
