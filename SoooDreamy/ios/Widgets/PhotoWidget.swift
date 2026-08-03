import WidgetKit
import SwiftUI
import UIKit
import ImageIO

// MARK: - Timeline

struct PhotoEntry: TimelineEntry {
    let date: Date
    let image: UIImage?
    let caption: String?
}

struct PhotoProvider: TimelineProvider {
    func placeholder(in context: Context) -> PhotoEntry {
        PhotoEntry(date: Date(), image: nil, caption: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (PhotoEntry) -> Void) {
        // Gallery preview: no network fetch, just the graceful gradient state.
        completion(PhotoEntry(date: Date(), image: nil, caption: SharedStore.readSnapshot()?.photoCaption))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PhotoEntry>) -> Void) {
        let snapshot = SharedStore.readSnapshot()
        let refresh = Date().addingTimeInterval(30 * 60)
        guard let urlString = snapshot?.photoURLString, let url = URL(string: urlString) else {
            completion(Timeline(entries: [PhotoEntry(date: Date(), image: nil, caption: nil)],
                                policy: .after(refresh)))
            return
        }
        Task {
            // The URL is already authenticated (token as query param) — plain GET.
            let image = await Self.fetchImage(from: url)
            let entry = PhotoEntry(date: Date(), image: image, caption: snapshot?.photoCaption)
            completion(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }

    private static func fetchImage(from url: URL) async -> UIImage? {
        let request = URLRequest(url: url, timeoutInterval: 15)
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return nil
        }
        return thumbnail(from: data, maxDimension: 800)
    }

    /// Memory-safe decode: `CGImageSourceCreateThumbnailAtIndex` never
    /// materializes the full-resolution bitmap, so even a huge thumb-less
    /// photo stays within the widget's tight memory budget.
    private static func thumbnail(from data: Data, maxDimension: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let thumbOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Views

struct PhotoWidgetView: View {
    let entry: PhotoEntry

    var body: some View {
        Group {
            if entry.image != nil {
                captionOverlay
            } else {
                emptyState
            }
        }
        .containerBackground(for: .widget) { background }
        .widgetURL(URL(string: "sooodreamy://tab/memories"))
    }

    @ViewBuilder
    private var background: some View {
        if let image = entry.image {
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                bottomScrim
            }
        } else {
            WTheme.bgGradient
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
                        .lineLimit(2)
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
                .font(.system(size: 30))
            Text(WText.t("Noch kein Foto", "No photo yet"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(WTheme.textSecondary)
                .multilineTextAlignment(.center)
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
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
