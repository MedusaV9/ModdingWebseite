import SwiftUI
import UIKit

// Canvas export flow (W9A component split from the 1 400-line CanvasView):
// share / save / upload options for an exported canvas bitmap, the photo
// library saver it relies on and the feature-local strings.

// MARK: - Export sheet

/// Identifiable wrapper so `.sheet(item:)` re-renders per export.
struct CanvasExportItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Share / save / upload options for an exported canvas bitmap.
struct CanvasExportSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let image: UIImage

    @State private var savingToPhotos = false
    @State private var savedToPhotos = false
    @State private var uploading = false
    @State private var uploaded = false

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                ScrollView {
                    VStack(spacing: Space.l) {
                        preview
                        actions
                    }
                    .padding(Space.l)
                }
            }
            .navigationTitle(CanvasExportStrings.t("export.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.close")) { dismiss() }
                }
            }
        }
    }

    /// The bitmap IS a sheet of paper (the board renders in Papier.brief)
    /// — the preview frames it like one: paper radius, light edge, raised.
    private var preview: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: Radius.papier, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                .strokeBorder(PaperLightEdge.gradient, lineWidth: Theme.hairlineWidth))
            .elevation(.raised)
            .frame(maxHeight: LayoutMetrics.s(400))
    }

    private var actions: some View {
        VStack(spacing: Space.m) {
            ShareLink(item: Image(uiImage: image),
                      preview: SharePreview(CanvasExportStrings.t("export.previewTitle"),
                                            image: Image(uiImage: image))) {
                Label(CanvasExportStrings.t("export.share"), systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())

            Button(action: saveToPhotos) {
                HStack(spacing: Space.s) {
                    if savingToPhotos {
                        BusySpinner(tint: Theme.textPrimary)
                    } else {
                        Label(CanvasExportStrings.t(savedToPhotos
                                                    ? "export.savedToPhotos"
                                                    : "export.saveToPhotos"),
                              systemImage: savedToPhotos ? "checkmark" : "photo.on.rectangle.angled")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(savingToPhotos || savedToPhotos)

            if appState.api != nil {
                Button(action: uploadToGallery) {
                    HStack(spacing: Space.s) {
                        if uploading {
                            BusySpinner(tint: Theme.textPrimary)
                        } else {
                            Label(CanvasExportStrings.t(uploaded
                                                        ? "export.uploaded"
                                                        : "export.upload"),
                                  systemImage: uploaded ? "checkmark" : "photo.stack")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(uploading || uploaded)
            }
        }
    }

    /// Add-only photo library write — covered by NSPhotoLibraryAddUsageDescription.
    private func saveToPhotos() {
        guard !savingToPhotos, !savedToPhotos else { return }
        savingToPhotos = true
        Haptics.shared.tap()
        CanvasImageSaver.save(image) { ok in
            savingToPhotos = false
            if ok {
                savedToPhotos = true
                SoundEngine.shared.play(.chime)
                Haptics.shared.success()
                appState.showToast(CanvasExportStrings.t("export.savedToast"), style: .success)
            } else {
                appState.showToast(CanvasExportStrings.t("export.saveFailed"), style: .error)
            }
        }
    }

    /// Uploads the artwork into the shared couple gallery (same flow as a
    /// gallery upload: full JPEG + best-effort grid thumbnail).
    private func uploadToGallery() {
        guard let api = appState.api, !uploading, !uploaded else { return }
        guard let jpeg = image.jpegData(compressionQuality: 0.85) else {
            appState.showToast(CanvasExportStrings.t("export.uploadFailed"), style: .error)
            return
        }
        uploading = true
        Haptics.shared.tap()
        Task {
            do {
                let photo = try await api.uploadPhoto(jpeg: jpeg,
                                                      caption: CanvasExportStrings.t("export.caption"),
                                                      width: Int(image.size.width),
                                                      height: Int(image.size.height))
                let thumb = GalleryView.downscaled(image, maxDimension: 320)
                if let thumbJpeg = thumb.jpegData(compressionQuality: 0.7) {
                    _ = try? await api.uploadPhotoThumb(photoId: photo.id, jpeg: thumbJpeg)
                }
                uploaded = true
                SoundEngine.shared.play(.sparkle)
                Haptics.shared.success()
                appState.showToast(CanvasExportStrings.t("export.uploadedToast"), style: .love)
            } catch {
                appState.handleAPIError(error)
            }
            uploading = false
        }
    }
}

// MARK: - Photo library saver

/// UIImageWriteToSavedPhotosAlbum needs an Obj-C completion target;
/// instances keep themselves alive until the callback fires.
final class CanvasImageSaver: NSObject {
    private static var active: [CanvasImageSaver] = []
    private var completion: ((Bool) -> Void)?

    static func save(_ image: UIImage, completion: @escaping (Bool) -> Void) {
        let saver = CanvasImageSaver()
        saver.completion = completion
        active.append(saver)
        UIImageWriteToSavedPhotosAlbum(image, saver,
                                       #selector(CanvasImageSaver.image(_:didFinishSavingWithError:contextInfo:)), nil)
    }

    @objc private func image(_ image: UIImage,
                             didFinishSavingWithError error: Error?,
                             contextInfo: UnsafeRawPointer) {
        let ok = error == nil
        DispatchQueue.main.async {
            self.completion?(ok)
            Self.active.removeAll { $0 === self }
        }
    }
}

// MARK: - Export strings

/// Feature-local strings for the export flow — deliberately NOT part of
/// MemoriesL10n (kept local to the canvas), resolved via the same LText type.
enum CanvasExportStrings {
    static let table: [String: LText] = [
        "export.title": LText(de: "Kunstwerk exportieren", en: "Export artwork"),
        "export.previewTitle": LText(de: "Kritzel-Leinwand", en: "Doodle canvas"),
        "export.share": LText(de: "Teilen…", en: "Share…"),
        "export.saveToPhotos": LText(de: "In Fotos sichern", en: "Save to Photos"),
        "export.savedToPhotos": LText(de: "In Fotos gesichert ✓", en: "Saved to Photos ✓"),
        "export.savedToast": LText(de: "In deiner Fotomediathek gesichert",
                                   en: "Saved to your photo library"),
        "export.saveFailed": LText(de: "Sichern fehlgeschlagen", en: "Couldn't save the image"),
        "export.upload": LText(de: "In eure Galerie hochladen", en: "Upload to your gallery"),
        "export.uploaded": LText(de: "In eurer Galerie ✓", en: "In your gallery ✓"),
        "export.uploadedToast": LText(de: "In eurer Galerie gespeichert",
                                      en: "Added to your gallery"),
        "export.uploadFailed": LText(de: "Upload fehlgeschlagen", en: "Upload failed"),
        "export.caption": LText(de: "Kritzel-Leinwand", en: "Doodle canvas"),
        "export.renderFailed": LText(de: "Export fehlgeschlagen — versuch es nochmal.",
                                     en: "Export failed — try again.")
    ]

    static func t(_ key: String) -> String {
        table[key]?.resolved(L10n.lang) ?? key
    }
}
