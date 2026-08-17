import Foundation

// Season themes — pure Foundation core so the mapping is
// unit-testable on Linux. Date is always injected; the UI passes Date().

/// The four seasonal looks. Raw values are stored in the user's preference
/// ("auto"/"off" are handled by SeasonPreference, not here).
enum Season: String, CaseIterable {
    case spring, summer, autumn, winter

    /// Meteorological seasons on clean month boundaries, shifted by six
    /// months for southern-hemisphere couples.
    static func current(
        for date: Date,
        hemisphere: Hemisphere = .northern,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Season {
        let northern: Season
        switch calendar.component(.month, from: date) {
        case 3...5: northern = .spring
        case 6...8: northern = .summer
        case 9...11: northern = .autumn
        default: northern = .winter
        }
        guard hemisphere == .southern else { return northern }
        switch northern {
        case .spring: return .autumn
        case .summer: return .winter
        case .autumn: return .spring
        case .winter: return .summer
        }
    }

    /// Particle motifs drifting over the dashboard.
    var particles: [String] {
        switch self {
        case .spring: return ["🌸", "🌷", "🦋"]
        case .summer: return ["✨", "🪲", "🌟"]   // fireflies & warm sparks
        case .autumn: return ["🍁", "🍂", "🍃"]
        case .winter: return ["❄️", "❅", "✳️"]
        }
    }

    /// Accent tint mixed into glass-card borders ("frost edges" etc.).
    /// Hex strings so this file stays SwiftUI-free (Linux target).
    var accentHex: String {
        switch self {
        case .spring: return "FFB7D5"   // cherry blossom
        case .summer: return "FFD166"   // firefly gold
        case .autumn: return "E8853D"   // maple orange
        case .winter: return "BFE3FF"   // frost blue
        }
    }

    var emoji: String {
        switch self {
        case .spring: return "🌸"
        case .summer: return "🌙"
        case .autumn: return "🍁"
        case .winter: return "❄️"
        }
    }

    /// L10n key for the picker label.
    var titleKey: String { "season.\(rawValue)" }
}

enum Hemisphere: String, CaseIterable {
    case northern, southern

    var titleKey: String { "season.hemisphere.\(rawValue)" }
}

/// The user's stored choice: automatic (follows the calendar), off, or a
/// fixed season. Stored as a plain string in UserDefaults.
enum SeasonPreference: String, CaseIterable {
    case auto, off
    case spring, summer, autumn, winter

    /// Effective season for a given date — nil means "no seasonal layer".
    func resolved(for date: Date, hemisphere: Hemisphere = .northern) -> Season? {
        switch self {
        case .off: return nil
        case .auto: return Season.current(for: date, hemisphere: hemisphere)
        case .spring: return .spring
        case .summer: return .summer
        case .autumn: return .autumn
        case .winter: return .winter
        }
    }

    var titleKey: String {
        switch self {
        case .auto: return "season.auto"
        case .off: return "season.off"
        case .spring, .summer, .autumn, .winter: return "season.\(rawValue)"
        }
    }
}
