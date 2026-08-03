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
        guard let image = UIImage(data: data) else { return nil }
        return downscaled(image, maxDimension: 800)
    }

    /// Defensive downscale so the widget stays within its memory budget.
    private static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let factor = maxDimension / longest
        let target = CGSize(width: size.width * factor, height: size.height * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
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
