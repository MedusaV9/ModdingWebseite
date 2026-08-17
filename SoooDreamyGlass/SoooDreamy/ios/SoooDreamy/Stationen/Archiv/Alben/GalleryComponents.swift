import SwiftUI
import UIKit

// Gallery building blocks (W9A component split from the 1 900-line
// GalleryView): filter model, grid cell, retry-card thumbnail and the
// caption sheet. Chrome speaks SF Symbols; matte fills inside cards.

// MARK: - Filter

/// Grid filter: everything, favorites, or one named album (dynamic —
/// album chips are derived from the photos themselves).
enum GalleryFilter: Hashable {
    case all, favorites
    case album(String)

    var title: String {
        switch self {
        case .all: return L10n.t("memories.gallery.filterAll")
        case .favorites: return L10n.t("memories.gallery.filterFavorites")
        case .album(let name): return name
        }
    }

    /// Albums carry a folder glyph in chips — an SF Symbol, not a 📁.
    var isAlbum: Bool {
        if case .album = self { return true }
        return false
    }

    func matches(_ photo: Photo) -> Bool {
        switch self {
        case .all: return true
        case .favorites: return !(photo.favorites ?? []).isEmpty
        case .album(let name): return photo.album == name
        }
    }
}

// MARK: - Pending upload

struct GalleryPendingUpload: Identifiable {
    let id = UUID()
    let jpeg: Data
    let image: UIImage
    /// EXIF capture time from the ORIGINAL bytes — the re-encoded `jpeg`
    /// no longer carries it.
    let takenAt: Date?
}

/// Small thumbnail for a retry card — bytes come off disk and are decoded
/// off the main thread (they can be a full 2048px JPEG).
struct PendingMediaThumbnail: View {
    let entryID: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            // The retry Zettel is a night card now (nacht-first P2) —
            // its inner well is the night wash.
            Papier.nachtInnenFill
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
            }
        }
        .task(id: entryID) {
            let id = entryID
            image = await Task.detached(priority: .utility) {
                guard let data = PendingMediaStore.shared.jpegData(id: id) else { return nil }
                return BoundedImageDecoder.image(data: data, maxPixelSize: 256)
            }.value
        }
    }
}

// MARK: - Grid cell (polaroid)

/// One photo of the album as a POLAROID: the print sits in a
/// `Papier.polaroid` frame (`Radius.polaroid`), the frame widens at the
/// bottom the way real instant film does, and the bottom strip carries
/// the caption as the couple's handwriting (`Typo.voice`) in dark ink
/// with the author's ink dot. Badges (selection, "Neu") stay scrim chrome
/// over the print — the paper never carries chrome.
struct GalleryCell: View {
    let photo: Photo
    let api: API?
    let memberId: String?

    @Environment(\.coupleTint) private var coupleTint
    /// nil = multi-select off; true/false = this cell's selection state.
    var selected: Bool? = nil
    /// Arrived from the partner since the last visit and not opened yet.
    var isNew = false
    /// Big tiles have room for the handwritten caption line; classic
    /// density keeps the bare polaroid strip.
    var showsCaption = false
    /// Uploader's member color — becomes the author's ink dot through the
    /// `inkOnPaper` ladder (≥ 4.5:1 on every paper tone, pinned).
    var authorColorHex: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(thumbnail)
                .clipShape(RoundedRectangle(cornerRadius: Radius.polaroid,
                                            style: .continuous))
                .overlay(alignment: .bottomLeading) { selectionBadge }
                .overlay(alignment: .topLeading) { newBadge }
            captionStrip
        }
        .padding(.top, Space.xs)
        .padding(.horizontal, Space.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.polaroid, style: .continuous)
                .fill(Papier.polaroid)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.polaroid, style: .continuous)
                        .strokeBorder(selected == true
                                      ? AnyShapeStyle(coupleTint.tinte)
                                      : AnyShapeStyle(PaperLightEdge.gradient),
                                      lineWidth: selected == true
                                      ? 2 : Theme.hairlineWidth)
                )
                .elevation(.resting)
        )
    }

    /// The wide bottom of the instant print: handwriting (couple caption,
    /// serif voice on paper), the author's ink dot and the favorite heart
    /// in readable ink.
    private var captionStrip: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            if let authorColorHex {
                Circle()
                    .fill(Color(hex: CouplePaletteRules.inkOnPaper(authorColorHex)))
                    .frame(width: LayoutMetrics.s(6), height: LayoutMetrics.s(6))
                    .accessibilityHidden(true)
            }
            if showsCaption, let caption = photo.caption, !caption.isEmpty {
                Text(caption)
                    .font(Typo.voice)
                    .foregroundStyle(Tinte.dunkel)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            favoriteBadge
        }
        .padding(.vertical, Space.xs)
        .frame(minHeight: LayoutMetrics.s(showsCaption ? 24 : 14))
    }

    /// Glow pill in the couple's shared color: the partner added this
    /// while you were away.
    @ViewBuilder
    private var newBadge: some View {
        if isNew {
            Text(L10n.t("memories.gallery.newBadge"))
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(coupleTint.onBlend)
                .padding(.vertical, 2)
                .padding(.horizontal, Space.s)
                .background(Capsule().fill(coupleTint.blend))
                .shadow(color: coupleTint.blend.opacity(0.65), radius: 6)
                .padding(5)
        }
    }

    /// Selection circle in multi-select mode (filled with the couple color
    /// when selected).
    @ViewBuilder
    private var selectionBadge: some View {
        if let selected {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(selected ? coupleTint.blend : Papier.aufNacht)
                .padding(4)
                .background(Circle().fill(Color.black.opacity(0.35)))
                .padding(5)
        }
    }

    /// Ink heart on the polaroid strip: couple ink when I favorited,
    /// faded ink when only the partner did.
    @ViewBuilder
    private var favoriteBadge: some View {
        if !(photo.favorites ?? []).isEmpty {
            Image(systemName: "heart.fill")
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .foregroundStyle(photo.isFavorite(of: memberId)
                                 ? coupleTint.tinte : Tinte.sekundaer)
                .accessibilityLabel(L10n.t("memories.gallery.filterFavorites"))
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if api != nil {
            AuthenticatedAsyncImage(api: api, path: photo.thumbUrl ?? photo.url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    placeholder(icon: "photo.badge.exclamationmark")
                default:
                    placeholder(icon: nil)
                }
            }
        } else {
            placeholder(icon: "photo")
        }
    }

    private func placeholder(icon: String?) -> some View {
        ZStack {
            Papier.innenFill
            if let icon {
                Image(systemName: icon)
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(Tinte.tertiaer)
            } else {
                // Skeleton, not spinner (commandment 7): the light sweep
                // fills the whole tile; the cell's clip crops the overflow.
                PaperSkeleton(kind: .tile(height: 200))
            }
        }
    }
}

// MARK: - Caption sheet

struct GalleryCaptionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.coupleTint) private var coupleTint
    let pending: GalleryPendingUpload
    let albumSuggestions: [String]
    let onUpload: (String, String) -> Void
    /// Fired when the sheet goes away WITHOUT the upload button (cancel or
    /// swipe-down) — the caller stashes photo + caption instead of
    /// discarding them (Linse 41: dismiss never destroys prepared work).
    let onDismissWithoutUpload: (String, String) -> Void

    @State private var caption = ""
    @State private var album = ""
    @State private var choseUpload = false

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                ScrollView {
                    VStack(spacing: Theme.sectionSpacing) {
                        // The fresh print develops inside its polaroid
                        // frame — the caption written below becomes its
                        // handwriting in the grid.
                        Image(uiImage: pending.image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: LayoutMetrics.s(300))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.polaroid,
                                                        style: .continuous))
                            .padding(.top, Space.s)
                            .padding(.horizontal, Space.s)
                            .padding(.bottom, Space.xl)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.polaroid,
                                                 style: .continuous)
                                    .fill(Papier.polaroid)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Radius.polaroid,
                                                         style: .continuous)
                                            .strokeBorder(PaperLightEdge.gradient,
                                                          lineWidth: Theme.hairlineWidth))
                                    .elevation(.raised)
                            )
                        TextField(L10n.t("memories.gallery.captionPlaceholder"), text: $caption, axis: .vertical)
                            .textFieldStyle(ChatPaperFieldStyle(font: Typo.voice))
                            .lineLimit(1...3)
                        albumField
                        Button(L10n.t("memories.gallery.upload")) {
                            Haptics.shared.tap()
                            choseUpload = true
                            dismiss()
                            onUpload(caption, album)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        Spacer()
                    }
                    .padding(Space.l)
                }
            }
            .navigationTitle(L10n.t("memories.gallery.captionTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.cancel")) { dismiss() }
                        .tint(coupleTint.blend)
                }
            }
        }
        .presentationDetents([.large])
        .onDisappear {
            if !choseUpload { onDismissWithoutUpload(caption, album) }
        }
    }

    private var albumField: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            // Filing chrome, not handwriting on the print — night field.
            TextField(L10n.t("memories.gallery.albumField"), text: $album)
                .textFieldStyle(DreamyFieldStyle())
                .submitLabel(.done)
            if !albumSuggestions.isEmpty {
                // Albums are paper pockets — their suggestions read as the
                // register tabs the grid filters already wear.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Space.s) {
                        ForEach(albumSuggestions, id: \.self) { name in
                            Button {
                                Haptics.shared.tap()
                                album = name
                            } label: {
                                PapierRegisterTab(title: name,
                                                  systemImage: "folder",
                                                  selected: album == name)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(album == name ? [.isSelected] : [])
                        }
                    }
                    .padding(.bottom, Space.xs)
                }
            }
        }
    }
}
