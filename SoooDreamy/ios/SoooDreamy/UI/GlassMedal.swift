import SwiftUI

// Procedural glass medal — every medal is drawn in SwiftUI (gradients,
// rim light, specular), zero binary assets. Lives in UI/ because it is a
// reusable piece of design-system painting: the specular/rim light values
// below are this component's raw material, like the aurora's blob colors.

/// Client-side display metadata per badge id. Names/descriptions live in
/// PlatformL10n; unknown ids (future server versions) degrade gracefully.
/// A `nil` tint means "the couple's own shared color" — love milestones
/// wear the couple's signature, not stock pink (DESIGN.md, commandment 11).
enum BadgeCatalog {
    struct Meta {
        let emoji: String
        /// Fixed accent — `nil` resolves to `coupleTint.blend` at render time.
        let tint: Color?
    }

    static let metas: [String: Meta] = [
        "first_touch": Meta(emoji: "💓", tint: nil),
        "touches_500": Meta(emoji: "⚡️", tint: Theme.gold),
        "hundred_kisses": Meta(emoji: "💋", tint: nil),
        "hug_marathon": Meta(emoji: "🫂", tint: nil),
        "streak_week": Meta(emoji: "🔥", tint: Theme.gold),
        "streak_month": Meta(emoji: "🌋", tint: nil),
        "checkin_month": Meta(emoji: "☀️", tint: Theme.gold),
        "wordle_ten": Meta(emoji: "🔤", tint: Theme.mint),
        "gamer_25": Meta(emoji: "🎲", tint: Theme.indigo),
        "photographers": Meta(emoji: "📸", tint: Theme.blue),
        "picasso": Meta(emoji: "🎨", tint: Theme.indigo),
        "bucket_10": Meta(emoji: "🪄", tint: Theme.mint),
        "songbirds": Meta(emoji: "🎶", tint: Theme.blue),
        "level_5": Meta(emoji: "🌟", tint: Theme.gold),
        "level_10": Meta(emoji: "👑", tint: Theme.gold),
        "night_owls": Meta(emoji: "🦉", tint: Theme.indigo),
        "early_birds": Meta(emoji: "🐦", tint: Theme.mint),
        "icon_gifted": Meta(emoji: "🎁", tint: nil),
        "duet_partners": Meta(emoji: "🫀", tint: nil),
        "quest_complete": Meta(emoji: "🗺️", tint: Theme.indigo),
        // Long-arc streak medals (90/180/365 daily-question days) — each
        // with its own face, continuing the week/month fire arc instead of
        // all three falling back to the generic gold medal.
        "streak_quarter": Meta(emoji: "☄️", tint: Theme.indigo),
        "streak_half_year": Meta(emoji: "🌠", tint: Theme.blue),
        "streak_year": Meta(emoji: "🪐", tint: nil),
    ]

    static func meta(_ id: String) -> Meta {
        metas[id] ?? Meta(emoji: "🏅", tint: Theme.gold)
    }

    static func name(_ id: String) -> String {
        let key = "badge.name.\(id)"
        let text = L10n.t(key)
        return text == key ? id : text
    }

    static func desc(_ id: String) -> String {
        let key = "badge.desc.\(id)"
        let text = L10n.t(key)
        return text == key ? "" : text
    }
}

/// The Siegel-Medaille (Papier & Licht): a poured WAX medallion with a
/// paper sticker rim — same circle, same size, same lock/secret states as
/// the old glass medal, only the material changed. The wax is opaque (it
/// lies on paper shelves now), the rim is `Papier.brief` like a pressed
/// sticker edge, and locked medals become quiet `Papier.kante` slots.
struct GlassMedalView: View {
    let badge: BadgeState
    var revealSecret = false
    var size: CGFloat = 74

    @Environment(\.coupleTint) private var coupleTint

    private var unlockedOrRevealed: Bool { badge.unlocked || revealSecret }
    private var disguised: Bool { badge.secret && !unlockedOrRevealed }
    private var meta: BadgeCatalog.Meta { BadgeCatalog.meta(badge.id) }
    private var tint: Color {
        disguised ? Wachs.rot : (meta.tint ?? coupleTint.wachs)
    }

    var body: some View {
        ZStack {
            // Pane: poured wax (opaque), a quiet paper slot when locked.
            Circle()
                .fill(unlockedOrRevealed
                      ? AnyShapeStyle(LinearGradient(
                            colors: [tint, tint.opacity(0.88)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                      : AnyShapeStyle(Papier.kante))

            // Molded wax rim — the pour thickens toward the edge.
            if unlockedOrRevealed {
                Circle()
                    .fill(RadialGradient(
                        colors: [.clear, .clear, Tinte.dunkel.opacity(0.22)],
                        center: .center, startRadius: 0, endRadius: size * 0.5))
            }

            // Paper sticker rim (replaces the glass depth ring — same
            // width, same inset, so the geometry stays untouched).
            Circle()
                .strokeBorder(unlockedOrRevealed ? Papier.brief : Papier.polaroid,
                              lineWidth: size * 0.045)
                .padding(size * 0.005)

            // Lamplight catching the wax dome (kept from the glass era —
            // the 10-o'clock light source shines on wax too).
            Ellipse()
                .fill(
                    LinearGradient(colors: [Color.white.opacity(unlockedOrRevealed ? 0.30 : 0.10),
                                            .clear],
                                   startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.66, height: size * 0.34)
                .offset(y: -size * 0.26)

            // The badge motif embossed into the wax.
            if disguised {
                Text("?")
                    .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
                    .foregroundStyle(Papier.brief.opacity(0.85))
            } else {
                Text(meta.emoji)
                    .font(.system(size: size * 0.42))
                    .saturation(badge.unlocked || revealSecret ? 1 : 0)
                    .opacity(badge.unlocked || revealSecret ? 1 : 0.35)
            }

            // Warm light pooling at the seal's lower edge when earned.
            if unlockedOrRevealed {
                Circle()
                    .fill(
                        RadialGradient(colors: [Licht.lampengold.opacity(0.25), .clear],
                                       center: .bottom, startRadius: 0, endRadius: size * 0.55))
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if !badge.unlocked && !revealSecret {
                Image(systemName: "lock.fill")
                    .font(.system(size: size * 0.16, weight: .bold))
                    .foregroundStyle(Papier.brief)
                    .padding(size * 0.06)
                    .background(Circle().fill(Tinte.sekundaer))
            }
        }
        .accessibilityLabel(disguised ? L10n.t("badges.secret") : BadgeCatalog.name(badge.id))
    }
}

// MARK: - Chapter keepsake (prestige souvenirs, FXC-4 #11)

/// A prestige-chapter keepsake: the same wax-seal painting as the badge
/// medal, but the motif embossed into the wax is the chapter's Roman
/// numeral. Purely client-side — derived from `LevelMath.chapter`, the
/// server never stores a byte of it.
struct GlassChapterMedalView: View {
    let chapter: Int
    /// The chapter currently being written renders as a quiet paper slot
    /// with the numeral ghosting through — the shelf shows what comes next.
    var completed = true
    var size: CGFloat = 68

    var body: some View {
        ZStack {
            // Pane: golden wax for earned keepsakes, a paper slot otherwise.
            Circle()
                .fill(completed
                      ? AnyShapeStyle(LinearGradient(
                            colors: [Theme.gold, Theme.gold.opacity(0.85)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                      : AnyShapeStyle(Papier.kante))

            // Molded wax rim — the pour thickens toward the edge.
            if completed {
                Circle()
                    .fill(RadialGradient(
                        colors: [.clear, .clear, Tinte.dunkel.opacity(0.18)],
                        center: .center, startRadius: 0, endRadius: size * 0.5))
            }

            // Paper sticker rim (same width/inset as the badge medal).
            Circle()
                .strokeBorder(completed ? Papier.brief : Papier.polaroid,
                              lineWidth: size * 0.045)
                .padding(size * 0.005)

            // Lamplight catching the wax dome.
            Ellipse()
                .fill(
                    LinearGradient(colors: [Color.white.opacity(completed ? 0.30 : 0.10),
                                            .clear],
                                   startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.66, height: size * 0.34)
                .offset(y: -size * 0.26)

            // The chapter numeral embossed into the wax — serif like a
            // minted coin, scaled down for long numerals (XVIII …). Dark
            // stamp on light wax (the onWax rule made literal).
            Text(LevelMath.chapterNumeral(chapter))
                .font(.system(size: size * 0.34, weight: .heavy, design: .serif))
                .foregroundStyle(completed ? Tinte.dunkel : Tinte.tertiaer)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.horizontal, size * 0.14)

            // Warm light pooling at the seal's lower edge when earned.
            if completed {
                Circle()
                    .fill(
                        RadialGradient(colors: [Licht.lampengold.opacity(0.25), .clear],
                                       center: .bottom, startRadius: 0,
                                       endRadius: size * 0.55))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(L10n.t(
            completed ? "badges.chapter.completed" : "badges.chapter.current",
            ["numeral": LevelMath.chapterNumeral(chapter)]))
    }
}

// MARK: - Level ring

/// Circular XP progress ring with the level number in the middle — the
/// couple's shared colors sweep the arc. Native `Gauge` under the hood
/// (system semantics + VoiceOver announces level and progress); the painting
/// lives in `LevelRingGaugeStyle` with font sizes proportional to the ring
/// diameter (design-system painting, like the medal above), so the same
/// primitive serves the compact dashboard card and the full-screen ceremony.
struct LevelRing: View {
    let level: Int
    let progress: Double
    var size: CGFloat = 58
    /// True when the ring sits on a paper card: number and track switch
    /// to the ink family, the arc becomes the couple's two INKS (the raw
    /// member colors stay night material).
    var onPaper: Bool = false

    @Environment(\.coupleTint) private var coupleTint

    var body: some View {
        Gauge(value: min(max(progress, 0), 1)) {
            Text(verbatim: "LVL")
        } currentValueLabel: {
            Text("\(level)")
        }
        .gaugeStyle(LevelRingGaugeStyle(size: size, onPaper: onPaper,
                                        coupleTint: coupleTint))
        .frame(width: size, height: size)
        .animation(Theme.Motion.settle, value: progress)
    }
}

/// The old hand-built XP ring, verbatim as a `GaugeStyle`: track in kante/
/// hairline, the couple's angular sweep, level number over the "LVL" label.
/// The 0.02 trim floor keeps a freshly started level visible as a seed dot.
private struct LevelRingGaugeStyle: GaugeStyle {
    let size: CGFloat
    let onPaper: Bool
    let coupleTint: CoupleTint

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Circle()
                .stroke(onPaper ? Papier.kante : Theme.hairline,
                        lineWidth: size * 0.10)
            Circle()
                .trim(from: 0, to: max(0.02, configuration.value))
                .stroke(
                    AngularGradient(colors: onPaper
                        ? [coupleTint.tintePrimary, coupleTint.tinteSecondary,
                           coupleTint.tintePrimary]
                        : [coupleTint.primary, coupleTint.secondary,
                           coupleTint.primary],
                                    center: .center),
                    style: StrokeStyle(lineWidth: size * 0.10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: -2) {
                configuration.currentValueLabel
                    .font(.system(size: size * 0.38, weight: .heavy, design: .rounded))
                    .foregroundStyle(onPaper ? Tinte.dunkel : Theme.textPrimary)
                    .monospacedDigit()
                configuration.label
                    .font(.system(size: size * 0.16, weight: .bold, design: .rounded))
                    .foregroundStyle(onPaper ? Tinte.tertiaer : Theme.textTertiary)
            }
        }
    }
}
