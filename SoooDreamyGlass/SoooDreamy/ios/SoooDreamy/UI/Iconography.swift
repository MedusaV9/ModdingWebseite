import SwiftUI

// The sanctioned icon facade (DESIGN.md, commandment 1): UI chrome renders
// SF Symbols — never emoji. Features name WHAT they mean (`Icon.sendLove`);
// this file decides which symbol carries it, so the whole app speaks one
// icon language and a symbol swap is a one-line change.
//
// Content emoji are NOT icons and stay text: the couple's chosen reactions,
// avatars, moods, and the touch/pulse signatures (💓 😘 🫂 🥺 🪶 💭) are
// things the couple picked and sends — chrome around them uses `Icon`.

/// Semantic UI icon names.
enum Icon: String {
    // Affection & touches (chrome around the content signatures)
    case sendLove = "heart.fill"
    case heartbeat = "waveform.path.ecg"
    case hug = "figure.2.arms.open"
    case gift = "gift.fill"

    // Memories & story
    case memory = "sparkles"
    case flashback = "photo.on.rectangle.angled"
    case quest = "map.fill"

    // App areas (quest steps, shortcuts)
    case chat = "bubble.left.and.bubble.right.fill"
    case dailyQuestion = "questionmark.circle.fill"
    case photo = "camera.fill"
    case canvas = "paintpalette.fill"
    case checkin = "cloud.sun.fill"
    case games = "dice.fill"

    // Rituals & day phases
    case night = "moon.stars.fill"
    case morning = "sun.max.fill"

    // Progress & rewards
    case medal = "medal.fill"
    case secret = "lock.fill"
    case levelUp = "arrow.up.circle.fill"
}

extension Image {
    /// Semantic icon lookup — `Image(icon: .sendLove)`.
    init(icon: Icon) {
        self.init(systemName: icon.rawValue)
    }
}

/// The standard hierarchical icon treatment for UI chrome: quiet by
/// default (`textSecondary`), accent roles opt into the couple's color.
/// On paper the same roles switch to ink (`Tinte.sekundaer` /
/// `coupleTint.tinte`) so badges keep their contrast on the bright fill.
struct IconBadge: View {
    let icon: Icon
    /// Accented badges carry the couple's shared color; quiet ones frame.
    var accented: Bool = false
    var font: Font = Typo.title
    /// True when the badge sits on a paper card instead of the night.
    var onPaper: Bool = false

    @Environment(\.coupleTint) private var coupleTint

    var body: some View {
        Image(icon: icon)
            .font(font)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(fill)
            .accessibilityHidden(true)
    }

    private var fill: AnyShapeStyle {
        if onPaper {
            return AnyShapeStyle(accented ? coupleTint.tinte : Tinte.sekundaer)
        }
        return accented ? AnyShapeStyle(coupleTint.blend)
                        : AnyShapeStyle(Theme.textSecondary)
    }
}
