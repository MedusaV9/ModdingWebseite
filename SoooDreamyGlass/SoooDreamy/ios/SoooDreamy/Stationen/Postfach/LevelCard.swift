import SwiftUI

// Relationship level: dashboard card with the level ring,
// title and XP progress; tapping opens the trophy shelf (badges + details).

struct LevelCard: View {
    @Environment(AppState.self) private var appState
    @State private var showShelf = false

    var body: some View {
        if let level = appState.levelState {
            Button {
                Haptics.shared.tap()
                showShelf = true
            } label: {
                HStack(spacing: LayoutMetrics.s(14)) {
                    LevelRing(level: level.level, progress: level.progress,
                              size: LayoutMetrics.s(58))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("level.card.title"))
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(Nacht.tertiaer)
                        // Accent TEXT on the night card speaks lamplight —
                        // couple ink stays a paper color (MIGRATION_DUNKEL §4).
                        Text(level.title.resolved)
                            .font(.system(.headline, design: .rounded).weight(.heavy))
                            .foregroundStyle(Licht.lampengold)
                        Text(progressLine(level))
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundStyle(Nacht.sekundaer)
                    }

                    Spacer(minLength: 0)

                    VStack(spacing: 4) {
                        let unlocked = appState.badges.filter(\.unlocked).count
                        if unlocked > 0 {
                            Image(icon: .medal)
                                .font(Typo.title)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Licht.glut)
                            Text("\(unlocked)")
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .foregroundStyle(Licht.glut)
                                .monospacedDigit()
                        } else {
                            Image(systemName: "chevron.right")
                                .font(Typo.caption)
                                .foregroundStyle(Nacht.tertiaer)
                        }
                    }
                }
                .nightCard()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                L10n.t("level.card.level", ["n": String(level.level)]) + ", " + level.title.resolved)
            .sheet(isPresented: $showShelf) {
                BadgeShelfView()
            }
        }
    }

    private func progressLine(_ level: LevelState) -> String {
        // Prestige chapters: progression never dead-ends anymore — there
        // is always a next level (the title itself carries the chapter).
        let remaining = max(0, level.nextLevelXp - level.levelXp)
        return L10n.t("level.card.toNext", ["xp": String(remaining), "n": String(level.level + 1)])
    }
}

// MARK: - Level-up ceremony (full-screen, epic)
// (`LevelRing` itself lives in UI/GlassMedal.swift — design-system painting.)

struct LevelUpCeremonyView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.motionGate) private var motionGate
    let ceremony: LevelUpPayload

    @State private var appeared = false

    var body: some View {
        ZStack {
            // Reduce Transparency: opaque night ink instead of a
            // translucent dim layer (MotionGate.scrim).
            motionGate.scrim(0.72)
                .ignoresSafeArea()

            VStack(spacing: LayoutMetrics.s(18)) {
                LevelRing(level: ceremony.level, progress: 1, size: LayoutMetrics.s(130))
                    .scaleEffect(appeared ? 1 : 0.4)
                    // Lichtschein instead of confetti: the lamplight blooms
                    // behind the ring and stays (Reduce Motion: static glow).
                    .background(LichtscheinGlow(size: LayoutMetrics.s(130)))
                    .shadow(color: coupleTint.blend.opacity(0.8), radius: 40)

                // Solid celebration gold — no gradient on text (DESIGN.md d).
                Text(L10n.t("level.up.title"))
                    .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                    .foregroundStyle(Theme.gold)

                Text(L10n.t("level.up.subtitle", ["n": String(ceremony.level)]))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)

                Text(ceremony.title.resolved)
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .foregroundStyle(Theme.gold)
                    .padding(.vertical, 8)
                    .padding(.horizontal, LayoutMetrics.s(18))
                    .background(Capsule().fill(Theme.gold.opacity(0.16))
                        .overlay(Capsule().strokeBorder(Theme.gold.opacity(0.5), lineWidth: 1)))

                // Badges that arrived in the same breath (DelightArbiter
                // coalescing) ride along as a medal stack — one ceremony.
                if !appState.celebrationBadgeStack.isEmpty {
                    CoalescedBadgeStackRow(badges: appState.celebrationBadgeStack)
                }

                Button(L10n.t("level.up.continue")) {
                    // Immediate quiet feedback in the tap frame (F6) — the
                    // dismissal animation alone left the tap feeling dead.
                    AppCue.click.play()
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 8)
                .padding(.horizontal, LayoutMetrics.s(44))
            }
            .padding(LayoutMetrics.s(30))
            .contentColumn(.reading)
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .onAppear {
            withAnimation(Theme.Motion.playful) { appeared = true }
        }
    }

    private func dismiss() {
        withAnimation(Theme.Motion.settle) {
            appState.dismissActiveCelebration()
        }
    }
}

// MARK: - Coalesced badge stack (DelightArbiter)

/// Medals that were coalesced INTO the ceremony on stage: a level-up and
/// its badges from one server write celebrate as ONE moment with stacked
/// content instead of a chain of equal fanfares.
private struct CoalescedBadgeStackRow: View {
    let badges: [BadgeState]

    var body: some View {
        VStack(spacing: Space.s) {
            HStack(spacing: LayoutMetrics.s(10)) {
                ForEach(badges) { badge in
                    GlassMedalView(badge: badge, revealSecret: true,
                                   size: LayoutMetrics.s(44))
                }
            }
            Text(badges.count == 1
                 ? L10n.t("badges.stack.one", ["name": BadgeCatalog.name(badges[0].id)])
                 : L10n.t("badges.stack.many", ["n": String(badges.count)]))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.gold)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Badge award ceremony

struct BadgeCeremonyView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint
    @Environment(\.motionGate) private var motionGate
    let badge: BadgeState

    @State private var appeared = false

    var body: some View {
        ZStack {
            // Reduce Transparency: opaque night ink (MotionGate.scrim).
            motionGate.scrim(0.72)
                .ignoresSafeArea()

            VStack(spacing: LayoutMetrics.s(16)) {
                GlassMedalView(badge: badge, revealSecret: true, size: LayoutMetrics.s(140))
                    .scaleEffect(appeared ? 1 : 0.3)
                    .rotationEffect(.degrees(appeared ? 0 : -18))
                    // Lichtschein instead of confetti (Reduce Motion: static).
                    .background(LichtscheinGlow(size: LayoutMetrics.s(140)))
                    .shadow(color: Theme.gold.opacity(0.7), radius: 34)

                Text(L10n.t("badges.awarded.title"))
                    .font(.system(.title, design: .rounded).weight(.heavy))
                    .foregroundStyle(Theme.gold)

                Text(BadgeCatalog.name(badge.id))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)

                Text(BadgeCatalog.desc(badge.id))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

                if badge.secret {
                    HStack(spacing: Space.xs) {
                        Image(icon: .secret)
                            .symbolRenderingMode(.hierarchical)
                        Text(L10n.t("badges.secret"))
                    }
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(coupleTint.blend)
                }

                if !appState.celebrationBadgeStack.isEmpty {
                    CoalescedBadgeStackRow(badges: appState.celebrationBadgeStack)
                }

                Button(L10n.t("level.up.continue")) {
                    AppCue.click.play()
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 6)
                .padding(.horizontal, LayoutMetrics.s(44))
            }
            .padding(LayoutMetrics.s(30))
            .contentColumn(.reading)
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .onAppear {
            withAnimation(Theme.Motion.playful) { appeared = true }
        }
    }

    private func dismiss() {
        withAnimation(Theme.Motion.settle) {
            appState.dismissActiveCelebration()
        }
    }
}
