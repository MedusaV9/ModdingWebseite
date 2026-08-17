import SwiftUI

// Badge collection shelf. The procedural medal itself lives in
// UI/GlassMedal.swift (design-system painting); this file is only the
// shelf: level header, grid and the detail card.

struct BadgeShelfView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.dismiss) private var dismiss

    @State private var selected: BadgeState?

    private var unlockedCount: Int { appState.badges.filter(\.unlocked).count }

    var body: some View {
        NavigationStack {
            ZStack {
                DreamyBackground(showStars: false)
                ScrollView {
                    VStack(spacing: Space.l) {
                        levelHeader
                        shelfGrid
                        if let selected {
                            detailCard(selected)
                        }
                        chapterKeepsakes
                    }
                    .padding(Space.l)
                }
            }
            .navigationTitle(L10n.t("badges.shelf.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("common.close")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .task {
            await appState.refreshGamification()
        }
    }

    // MARK: Level header

    @ViewBuilder
    private var levelHeader: some View {
        if let level = appState.levelState {
            VStack(spacing: LayoutMetrics.s(10)) {
                LevelRing(level: level.level, progress: level.progress,
                          size: LayoutMetrics.s(96))
                // Brand title on night: accent TEXT anchors to lampengold
                // (couple inks are paper-only).
                Text(level.title.resolved)
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .foregroundStyle(Licht.lampengold)
                Text(L10n.t("level.card.xp", ["xp": String(level.xp)]))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Nacht.sekundaer)
                // Prestige chapters: the ladder never ends — past level 10
                // the title stems replay per chapter, so the XP bar and
                // "to next level" line stay honest forever.
                if LevelMath.chapter(forLevel: level.level) > 1 {
                    // Gold stays MATERIAL (warm wash + edge); on night the
                    // numeral writes in the ember — wax is never ink here.
                    Text(L10n.t("level.chapter.badge",
                                ["numeral": LevelMath.chapterNumeral(
                                    LevelMath.chapter(forLevel: level.level))]))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(Licht.glut)
                        .padding(.vertical, 4)
                        .padding(.horizontal, LayoutMetrics.s(12))
                        .background(Capsule().fill(Theme.gold.opacity(0.14))
                            .overlay(Capsule().strokeBorder(Theme.gold.opacity(0.4),
                                                            lineWidth: Theme.hairlineWidth)))
                }
                // XP bar inside the current level — the fill is the
                // couple's own gradient, not the stock pink ramp.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Papier.nachtInnenFill)
                        Capsule()
                            .fill(coupleTint.heroGradient)
                            .frame(width: max(6, geo.size.width * level.progress))
                    }
                }
                .frame(height: 8)
                Text(L10n.t("level.card.toNext",
                            ["xp": String(max(0, level.nextLevelXp - level.levelXp)),
                             "n": String(level.level + 1)]))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
            }
            .frame(maxWidth: .infinity)
            .nightCard()
        }
    }

    // MARK: Shelf

    private var shelfGrid: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack {
                SectionHeader(title: L10n.t("badges.title"))
                Spacer()
                Text(L10n.t("badges.shelf.subtitle",
                            ["n": String(unlockedCount), "total": String(appState.badges.count)]))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Licht.glut)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                      spacing: LayoutMetrics.s(14)) {
                ForEach(appState.badges) { badge in
                    Button {
                        Haptics.shared.tap()
                        withAnimation(Theme.Motion.settle) {
                            selected = selected?.id == badge.id ? nil : badge
                        }
                    } label: {
                        GlassMedalView(badge: badge, size: LayoutMetrics.s(68))
                            .overlay(
                                Circle().strokeBorder(
                                    selected?.id == badge.id ? Licht.lampengold : .clear,
                                    lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .nightCard()
    }

    // MARK: Chapter keepsakes (prestige souvenirs, FXC-4 #11)

    /// One collectible keepsake per COMPLETED prestige chapter, derived
    /// purely from the level (`LevelMath.chapter`) — nothing to sync, the
    /// server never knows. Hidden while chapter I is still being written:
    /// the shelf never spoils a system the couple hasn't reached yet. The
    /// running chapter shows as a frosted slot — the NEXT keepsake.
    @ViewBuilder
    private var chapterKeepsakes: some View {
        if let level = appState.levelState {
            let chapter = LevelMath.chapter(forLevel: level.level)
            if chapter > 1 {
                VStack(alignment: .leading, spacing: Space.m) {
                    SectionHeader(title: L10n.t("badges.chapter.title"))
                    Text(L10n.t("badges.chapter.hint"))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Nacht.sekundaer)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12),
                                             count: 4),
                              spacing: LayoutMetrics.s(14)) {
                        ForEach(1...chapter, id: \.self) { n in
                            GlassChapterMedalView(chapter: n,
                                                  completed: n < chapter,
                                                  size: LayoutMetrics.s(68))
                        }
                    }
                }
                .nightCard()
            }
        }
    }

    // MARK: Detail

    private func detailCard(_ badge: BadgeState) -> some View {
        let disguised = badge.secret && !badge.unlocked
        return VStack(alignment: .leading, spacing: LayoutMetrics.s(8)) {
            HStack(spacing: Space.m) {
                GlassMedalView(badge: badge, size: LayoutMetrics.s(52))
                VStack(alignment: .leading, spacing: 2) {
                    Text(disguised ? L10n.t("badges.secret") : BadgeCatalog.name(badge.id))
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(Papier.aufNacht)
                    Text(disguised ? L10n.t("badges.secretHint") : BadgeCatalog.desc(badge.id))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Nacht.sekundaer)
                }
                Spacer(minLength: 0)
            }

            if badge.unlocked {
                if let date = badge.unlockedAt {
                    Text(L10n.t("badges.unlockedAt",
                                ["date": date.formatted(date: .abbreviated, time: .omitted)]))
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(Licht.lampengold)
                }
            } else if !disguised, badge.progress.target > 1 {
                // Progress toward the (non-secret) badge — on night the bar
                // fills in lamplight (gold reads perfectly on nachtkarton).
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Papier.nachtInnenFill)
                        Capsule()
                            .fill(Licht.lampengold)
                            .frame(width: max(4, geo.size.width
                                * CGFloat(badge.progress.current) / CGFloat(max(1, badge.progress.target))))
                    }
                }
                .frame(height: 6)
                Text("\(min(badge.progress.current, badge.progress.target))/\(badge.progress.target)")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(Nacht.tertiaer)
                    .monospacedDigit()
            } else if !badge.unlocked {
                Text(L10n.t("badges.locked"))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Nacht.tertiaer)
            }
        }
        .nightCard()
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}
