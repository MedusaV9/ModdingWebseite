import Foundation

enum WidgetFreshnessState: Equatable {
    case current
    case stale(age: TimeInterval)
    case unavailable
}

enum WidgetFreshness {
    static func maximumAge(for kind: String) -> TimeInterval {
        switch kind {
        case WidgetKindID.mood:
            return 13 * 60 * 60
        case WidgetKindID.daily, WidgetKindID.streak:
            return 26 * 60 * 60
        case WidgetKindID.countdown, WidgetKindID.canvas, WidgetKindID.sendLove:
            return 25 * 60 * 60
        case WidgetKindID.daysTogether, WidgetKindID.photo:
            return 49 * 60 * 60
        default:
            return 25 * 60 * 60
        }
    }

    static func state(
        updatedAt: Date?,
        now: Date = Date(),
        kind: String
    ) -> WidgetFreshnessState {
        guard let updatedAt else { return .unavailable }
        let age = max(0, now.timeIntervalSince(updatedAt))
        guard age > maximumAge(for: kind) else { return .current }
        return .stale(age: age)
    }
}

struct FilmstripPhotoCandidate: Equatable {
    let id: String
    let createdAt: Date
    let isFavorite: Bool
}

enum FilmstripSelection {
    /// Stable across devices: favorites first, then newest, with ID as the
    /// deterministic tie-breaker. The same photo can never occupy two frames.
    static func select(
        from candidates: [FilmstripPhotoCandidate],
        limit: Int
    ) -> [FilmstripPhotoCandidate] {
        guard limit > 0 else { return [] }
        var seen = Set<String>()
        return candidates
            .sorted {
                if $0.isFavorite != $1.isFavorite { return $0.isFavorite && !$1.isFavorite }
                if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                return $0.id < $1.id
            }
            .filter { seen.insert($0.id).inserted }
            .prefix(limit)
            .map { $0 }
    }
}

struct WidgetStudioPreset: Equatable, Identifiable {
    let id: String
    let nameDE: String
    let nameEN: String
    let themeID: String
    let layout: String?
    let photoFrame: String?

    func name(language: String) -> String {
        language == "de" ? nameDE : nameEN
    }
}

enum WidgetPresetCatalog {
    static func presets(for kind: String) -> [WidgetStudioPreset] {
        switch kind {
        case WidgetKindID.photo:
            return [
                WidgetStudioPreset(id: "photo-polaroid", nameDE: "Polaroid", nameEN: "Polaroid",
                                   themeID: "blush", layout: nil, photoFrame: "polaroid"),
                WidgetStudioPreset(id: "photo-film", nameDE: "Filmrolle", nameEN: "Film roll",
                                   themeID: "mono", layout: nil, photoFrame: "filmstrip"),
                WidgetStudioPreset(id: "photo-booth", nameDE: "Passbildautomat", nameEN: "Photo booth",
                                   themeID: "night", layout: nil, photoFrame: "photobooth"),
            ]
        default:
            return [
                WidgetStudioPreset(id: "\(kind)-calm", nameDE: "Ruhig", nameEN: "Calm",
                                   themeID: "ocean", layout: "minimal", photoFrame: nil),
                WidgetStudioPreset(id: "\(kind)-dreamy", nameDE: "Verträumt", nameEN: "Dreamy",
                                   themeID: "night", layout: "classic", photoFrame: nil),
                WidgetStudioPreset(id: "\(kind)-bold", nameDE: "Leuchtend", nameEN: "Bold",
                                   themeID: "sunset", layout: "hero", photoFrame: nil),
            ]
        }
    }

    static func apply(_ preset: WidgetStudioPreset, to config: inout WidgetKindConfig) {
        config.themeId = preset.themeID
        config.layout = preset.layout
        if let photoFrame = preset.photoFrame {
            config.photoFrame = photoFrame
        }
    }
}
