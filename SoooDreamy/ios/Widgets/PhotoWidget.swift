import WidgetKit
import SwiftUI
import UIKit

// MARK: - Timeline

struct PhotoEntry: TimelineEntry {
    let date: Date
    let image: UIImage?
    let caption: String?
}

struct PhotoProvider: TimelineProvider {
    func placeholder(in context: Context) -> PhotoEntry {
        PhotoEntry(date: Date(), image: Self.cachedImage(), caption: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (PhotoEntry) -> Void) {
        // Gallery preview: no network fetch — show the last cached photo
        // instead of a blank gradient whenever one exists.
        completion(PhotoEntry(date: Date(), image: Self.cachedImage(),
                              caption: SharedStore.readSnapshot()?.photoCaption))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PhotoEntry>) -> Void) {
        let snapshot = SharedStore.readSnapshot()
        let refresh = Date().addingTimeInterval(30 * 60)
        guard let urlString = snapshot?.photoURLString, let url = URL(string: urlString) else {
            // No showcase photo (e.g. gallery emptied) — genuine empty state.
            completion(Timeline(entries: [PhotoEntry(date: Date(), image: nil, caption: nil)],
                                policy: .after(refresh)))
            return
        }
        Task {
            // The URL is already authenticated (token as query param) — plain GET.
            let image: UIImage?
            if let data = await Self.fetchImageData(from: url),
               let fetched = WidgetImages.decode(data, maxDimension: 800) {
                // Remember the bytes so the widget survives the server napping.
                SharedStore.writeCachedPhotoJPEG(data)
                image = fetched
            } else {
                // Offline / server asleep: fall back to the last good photo.
                image = Self.cachedImage()
            }
            let entry = PhotoEntry(date: Date(), image: image, caption: snapshot?.photoCaption)
            completion(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }

    static func cachedImage() -> UIImage? {
        guard let data = SharedStore.readCachedPhotoJPEG() else { return nil }
        return WidgetImages.decode(data, maxDimension: 800)
    }

    private static func fetchImageData(from url: URL) async -> Data? {
        let request = URLRequest(url: url, timeoutInterval: 15)
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return nil
        }
        return data.isEmpty ? nil : data
    }
}

// MARK: - Views

struct PhotoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PhotoEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular: rectangular
            default: photoOrEmpty
            }
        }
        .containerBackground(for: .widget) { background }
        .widgetURL(URL(string: "sooodreamy://tab/memories"))
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
        if family != .accessoryRectangular, let image = entry.image {
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                bottomScrim
            }
        } else {
            WidgetChromeBackground(photoFriendly: true)
        }
    }

    private var bottomScrim: some View {
        LinearGradient(
            colors: [.clear, .clear, Color.black.opacity(0.55)],
            startPoint: .top, endPoint: .bottom)
    }

    private var captionOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 6) {
                if let caption = entry.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(family == .systemLarge ? 3 : 2)
                        .minimumScaleFactor(0.8)
                        .shadow(color: .black.opacity(0.6), radius: 2)
                }
                Spacer(minLength: 0)
                Text("💜")
                    .font(.system(size: 13))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("📸")
                .font(.system(size: family == .systemSmall ? 30 : 40))
            Text(WText.t("Noch kein Foto", "No photo yet"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(WTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            Text("📸")
                .font(.system(size: 24))
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

// MARK: - Widget

struct PhotoWidget: Widget {
    let kind = "SoooDreamy.Photo"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PhotoProvider()) { entry in
            PhotoWidgetView(entry: entry)
        }
        .configurationDisplayName(WText.t("Euer Foto", "Your photo"))
        .description(WText.t("Zeigt euer schönstes gemeinsames Foto.",
                             "Shows your favorite photo together."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}
