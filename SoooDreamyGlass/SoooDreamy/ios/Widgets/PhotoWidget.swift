import WidgetKit
import SwiftUI
import UIKit
import AppIntents

// MARK: - Timeline

struct PhotoEntry: TimelineEntry {
    let date: Date
    let image: UIImage?
    let filmstripImages: [UIImage]
    let caption: String?
    let palette: WidgetPalette
    let snapshotUpdatedAt: Date?
    /// Frame style ("polaroid" | "filmstrip" | "scrapbook"); nil = full-bleed.
    var frame: String?
}

struct PhotoProvider: AppIntentTimelineProvider {
    private func palette(for configuration: PhotoWidgetConfigIntent) -> WidgetPalette {
        WidgetPalette.resolve(kind: WidgetKindID.photo,
                              intentThemeId: configuration.theme.themeId)
    }

    /// Effective frame: per-widget intent override → studio config → none.
    private func frame(for configuration: PhotoWidgetConfigIntent) -> String? {
        if configuration.frame != .studio { return configuration.frame.frameId }
        return SharedStore.readStudioConfig().config(for: WidgetKindID.photo).photoFrame
    }

    func placeholder(in context: Context) -> PhotoEntry {
        let cached = Self.cachedImage()
        return PhotoEntry(date: Date(), image: cached, filmstripImages: [cached].compactMap { $0 },
                          caption: nil, palette: WidgetPalette.resolve(kind: WidgetKindID.photo),
                          snapshotUpdatedAt: SharedStore.readSnapshot()?.updatedAt)
    }

    func snapshot(for configuration: PhotoWidgetConfigIntent, in context: Context) async -> PhotoEntry {
        // Gallery preview: no network fetch — show the last cached photo
        // instead of a blank gradient whenever one exists.
        let snapshot = WidgetDiagnostics.renderableSnapshot
        let cached = Self.cachedImage()
        return PhotoEntry(date: Date(), image: cached, filmstripImages: [cached].compactMap { $0 },
                          caption: snapshot?.photoCaption,
                          palette: palette(for: configuration),
                          snapshotUpdatedAt: snapshot?.updatedAt,
                          frame: frame(for: configuration))
    }

    func timeline(for configuration: PhotoWidgetConfigIntent, in context: Context) async -> Timeline<PhotoEntry> {
        let snapshot = WidgetDiagnostics.renderableSnapshot
        let refresh = Date().addingTimeInterval(30 * 60)
        let palette = palette(for: configuration)

        // Which photo? The studio/app showcase by default; the per-widget
        // intent can force favorite/newest via a direct server lookup.
        var urlString = snapshot?.photoURLString
        var caption = snapshot?.photoCaption
        let studioSource = SharedStore.readStudioConfig()
            .config(for: WidgetKindID.photo).photoSource
        let effectiveSource: String? = {
            switch configuration.source {
            case .studio: return studioSource
            case .favorite: return "favorite"
            case .newest: return "newest"
            }
        }()
        if let source = effectiveSource, source == "favorite" || source == "newest",
           let picked = await Self.pickPhotos(source: source, limit: 1).first {
            urlString = picked.url
            caption = picked.caption
        }

        let frame = frame(for: configuration)
        let stripLimit = frame == "photobooth" ? 4 : 3
        let stripPhotos = (frame == "filmstrip" || frame == "photobooth")
            ? await Self.pickPhotos(source: effectiveSource ?? "favorite", limit: stripLimit)
            : []
        guard let urlString, let url = URL(string: urlString) else {
            // No showcase photo (e.g. gallery emptied) — genuine empty state.
            return Timeline(entries: [PhotoEntry(date: Date(), image: nil,
                                                 filmstripImages: [], caption: nil,
                                                 palette: palette,
                                                 snapshotUpdatedAt: snapshot?.updatedAt,
                                                 frame: frame)],
                            policy: .after(refresh))
        }
        var filmstripImages: [UIImage] = []
        if let credentials = SharedStore.readServerCredentials(),
           let token = SharedKeychain.activeToken(profileID: credentials.profileID) {
            for item in stripPhotos {
                guard let stripURL = URL(string: item.url),
                      let data = await Self.fetchData(from: stripURL, token: token),
                      let image = WidgetImages.decode(data, maxDimension: 500) else { continue }
                filmstripImages.append(image)
            }
        }
        let image: UIImage?
        if let credentials = SharedStore.readServerCredentials(),
           let token = SharedKeychain.activeToken(profileID: credentials.profileID),
           let data = await Self.fetchData(from: url, token: token),
           let fetched = WidgetImages.decode(data, maxDimension: 800) {
            // Remember the bytes so the widget survives the server napping.
            SharedStore.writeCachedPhotoJPEG(data)
            image = fetched
        } else {
            // Offline / server asleep: fall back to the last good photo.
            image = Self.cachedImage()
        }
        if filmstripImages.isEmpty, let image { filmstripImages = [image] }
        let entry = PhotoEntry(date: Date(), image: image, filmstripImages: filmstripImages,
                               caption: caption, palette: palette,
                               snapshotUpdatedAt: snapshot?.updatedAt, frame: frame)
        return Timeline(entries: [entry], policy: .after(refresh))
    }

    static func cachedImage() -> UIImage? {
        guard let data = SharedStore.readCachedPhotoJPEG() else { return nil }
        return WidgetImages.decode(data, maxDimension: 800)
    }

    private static func fetchData(from url: URL, token: String) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return nil
        }
        return data.isEmpty ? nil : data
    }

    /// Direct server lookup for the per-widget photo source override.
    /// Uses the app-group-mirrored credentials; nil on any failure.
    private static func pickPhotos(
        source: String,
        limit: Int
    ) async -> [(url: String, caption: String?)] {
        guard let creds = SharedStore.readServerCredentials(),
              let token = SharedKeychain.activeToken(profileID: creds.profileID),
              let base = URL(string: creds.baseURLString) else { return [] }
        var request = URLRequest(url: base.appendingPathComponent("api/photos"),
                                 timeoutInterval: 12)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let photos = json["photos"] as? [[String: Any]], !photos.isEmpty else { return [] }
        let formatter = ISO8601DateFormatter()
        var byID: [String: [String: Any]] = [:]
        let candidates = photos.compactMap { photo -> FilmstripPhotoCandidate? in
            guard let id = photo["id"] as? String else { return nil }
            byID[id] = photo
            let createdAt = (photo["createdAt"] as? String).flatMap(formatter.date) ?? .distantPast
            let favorite = source == "favorite"
                && !(photo["favorites"] as? [String] ?? []).isEmpty
            return FilmstripPhotoCandidate(id: id, createdAt: createdAt, isFavorite: favorite)
        }
        return FilmstripSelection.select(from: candidates, limit: limit).compactMap { candidate in
            guard let chosen = byID[candidate.id],
                  let path = (chosen["thumbUrl"] as? String) ?? (chosen["url"] as? String),
                  let absolute = URL(string: path, relativeTo: base)?.absoluteURL.absoluteString else {
                return nil
            }
            return (url: absolute, caption: chosen["caption"] as? String)
        }
    }
}

// MARK: - Views

struct PhotoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PhotoEntry

    private var palette: WidgetPalette { entry.palette }

    /// Framed styles render the photo inset (frame around it); full-bleed
    /// uses the photo itself as the widget background.
    private var framed: Bool { entry.frame != nil && entry.image != nil }

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular: rectangular
            default:
                if framed, let image = entry.image, let style = entry.frame {
                    PhotoFrameView(image: image, caption: entry.caption,
                                   style: style, family: family,
                                   filmstripImages: entry.filmstripImages,
                                   date: entry.date)
                } else {
                    photoOrEmpty
                }
            }
        }
        .containerBackground(for: .widget) { background }
        .widgetFreshness(kind: WidgetKindID.photo,
                         updatedAt: entry.snapshotUpdatedAt,
                         now: entry.date, family: family, palette: palette)
        .widgetURL(URL(string: "sooodreamy://photos"))
    }

    @ViewBuilder
    private var photoOrEmpty: some View {
        if entry.image != nil {
            captionOverlay
        } else {
            emptyState
        }
    }

    @ViewBuilder
    private var background: some View {
        if family != .accessoryRectangular, !framed, let image = entry.image {
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                bottomScrim
            }
        } else {
            WidgetChromeBackground(palette: palette, photoFriendly: true)
        }
    }

    private var bottomScrim: some View {
        LinearGradient(
            colors: [.clear, Color.black.opacity(0.55)],
            startPoint: .center, endPoint: .bottom)
    }

    private var captionOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 6) {
                if let caption = entry.caption, !caption.isEmpty {
                    Text(caption)
                        // The two big canvases (large + iPad extra large)
                        // afford the full three-line caption.
                        .lineLimit(family == .systemLarge
                                   || family == .systemExtraLarge ? 3 : 2)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.8)
                        .shadow(color: .black.opacity(0.6), radius: 2)
                }
                Spacer(minLength: 0)
                WHeart(palette: palette, size: 13)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "photo.fill")
                .font(WidgetTypo.glyph(family == .systemSmall ? 26 : 34,
                                       weight: .semibold))
                .foregroundStyle(palette.accent)
            Text(WText.t("Noch kein Foto", "No photo yet"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.fill")
                .font(WidgetTypo.glyph(20, weight: .semibold))
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 1) {
                Text(WText.t("Euer Foto", "Your photo"))
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .lineLimit(1)
                    .widgetAccentable()
                if let caption = entry.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text(WText.t("Tippen zum Ansehen", "Tap to view"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - frame styles

/// Photo frames drawn purely in SwiftUI: Polaroid (white border, chin,
/// slight tilt), film strip (sprocket holes) and scrapbook (paper + washi
/// tape). No binary assets — everything is shapes and gradients.
struct PhotoFrameView: View {
    let image: UIImage
    let caption: String?
    let style: String
    let family: WidgetFamily
    let filmstripImages: [UIImage]
    let date: Date

    private var compact: Bool { family == .systemSmall }

    var body: some View {
        switch style {
        case "filmstrip": filmstrip
        case "photobooth": photoBooth
        case "scrapbook": scrapbook
        default: polaroid
        }
    }

    // MARK: Polaroid

    private var polaroid: some View {
        VStack(spacing: 0) {
            photo
                .padding(compact ? 5 : 8)
            HStack {
                if let caption, !caption.isEmpty {
                    // P6-C: the print caption writes in INK on the polaroid
                    // paper (was a violet-era #40334D on a generic cream).
                    Text(caption)
                        .font(WidgetTypo.print(compact ? 10 : 13))
                        .foregroundStyle(Color(hexString: WidgetPaperHex.tinteDunkel))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Image(systemName: "heart.fill")
                        .font(WidgetTypo.glyph(compact ? 9 : 12, weight: .semibold))
                        .foregroundStyle(WidgetPalette.wax)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, compact ? 7 : 10)
            .padding(.bottom, compact ? 6 : 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(hexString: WidgetPaperHex.polaroid))
                .shadow(color: .black.opacity(0.45), radius: 5, y: 3))
        .rotationEffect(.degrees(-2.2))
        .padding(compact ? 2 : 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Film strip

    private var filmstrip: some View {
        VStack(spacing: 0) {
            sprocketRow
            HStack(spacing: 2) {
                ForEach(Array(stripImages.prefix(3).enumerated()), id: \.offset) { _, image in
                    framedPhoto(image)
                        .overlay(alignment: .bottomTrailing) {
                            Text(date, format: .dateTime.day().month())
                                .font(WidgetTypo.print(compact ? 6 : 8, weight: .bold))
                                .foregroundStyle(.white)
                                .shadow(color: .black, radius: 2)
                                .padding(3)
                        }
                }
            }
            sprocketRow
        }
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.black.opacity(0.92)))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var photoBooth: some View {
        HStack(spacing: compact ? 3 : 5) {
            ForEach(0..<4, id: \.self) { index in
                framedPhoto(stripImages[index % stripImages.count])
                    .overlay(alignment: .bottomTrailing) {
                        Text("\(index + 1)")
                            .font(WidgetTypo.print(compact ? 7 : 9, weight: .black))
                            .foregroundStyle(.white)
                            .shadow(color: .black, radius: 2)
                            .padding(2)
                    }
            }
        }
        .padding(compact ? 4 : 7)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(hexString: WidgetPaperHex.brief)))
        .overlay(alignment: .bottomTrailing) {
            Text(date, format: .dateTime.day().month().year())
                .font(WidgetTypo.print(compact ? 6 : 8, design: .monospaced))
                .foregroundStyle(Color(hexString: WidgetPaperHex.tinteDunkel).opacity(0.7))
                .padding(4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sprocketRow: some View {
        HStack(spacing: compact ? 7 : 10) {
            ForEach(0..<(compact ? 6 : 9), id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1.6, style: .continuous)
                    .fill(Color.white.opacity(0.85))
                    .frame(width: compact ? 7 : 9, height: compact ? 5 : 7)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, compact ? 4 : 6)
    }

    // MARK: Scrapbook

    private var scrapbook: some View {
        ZStack(alignment: .bottom) {
            photo
                .padding(compact ? 6 : 9)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(hexString: WidgetPaperHex.karton))
                        .shadow(color: .black.opacity(0.4), radius: 4, y: 2))
                .overlay(alignment: .topLeading) { tape(rotation: -38) }
                .overlay(alignment: .topTrailing) { tape(rotation: 38) }

            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(WidgetTypo.print(compact ? 10 : 12, design: .serif).italic())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    .background(Capsule().fill(Color.black.opacity(0.5)))
                    .offset(y: compact ? 2 : 0)
            }
        }
        .padding(compact ? 3 : 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tape(rotation: Double) -> some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(Color(red: 1.0, green: 0.82, blue: 0.55).opacity(0.82))
            .frame(width: compact ? 26 : 36, height: compact ? 9 : 12)
            .rotationEffect(.degrees(rotation))
            .offset(x: rotation < 0 ? -6 : 6, y: -3)
    }

    // MARK: Shared photo pane

    private var photo: some View {
        framedPhoto(image)
    }

    private var stripImages: [UIImage] {
        filmstripImages.isEmpty ? [image] : filmstripImages
    }

    private func framedPhoto(_ image: UIImage) -> some View {
        // Medium and the iPad extra large are the two WIDE canvases —
        // framed photos take a landscape crop there, square everywhere else.
        let wide = family == .systemMedium || family == .systemExtraLarge
        return Color.clear
            .aspectRatio(wide ? 1.9 : 1.0, contentMode: .fit)
            .overlay(
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill())
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
    }
}

// MARK: - Widget

struct PhotoWidget: Widget {
    let kind = WidgetKindID.photo

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: PhotoWidgetConfigIntent.self,
                               provider: PhotoProvider()) { entry in
            PhotoWidgetView(entry: entry)
        }
        .configurationDisplayName(WText.t("Euer Foto", "Your photo"))
        .description(WText.t("Zeigt euer schönstes gemeinsames Foto.",
                             "Shows your favorite photo together."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
                            .accessoryRectangular])
    }
}
