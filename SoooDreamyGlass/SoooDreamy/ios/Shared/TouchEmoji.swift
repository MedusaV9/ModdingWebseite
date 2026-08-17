import Foundation

/// Raw touch type → emoji, for the widget extension. Mirrors the app's
/// `TouchKind.emoji` (the app models are deliberately not compiled into the
/// widgets, so live activities map the plain string instead).
enum TouchEmoji {
    static func map(_ type: String) -> String {
        switch type {
        case "heartbeat": return "💓"
        case "kiss": return "😘"
        case "hug": return "🫂"
        case "missyou": return "🥺"
        case "tickle": return "🪶"
        case "thinking": return "💭"
        // Thinking-of-you pulses feed the same "last touch" line (37#23).
        case "goodnight": return "🌙"
        default: return "💞"
        }
    }
}
