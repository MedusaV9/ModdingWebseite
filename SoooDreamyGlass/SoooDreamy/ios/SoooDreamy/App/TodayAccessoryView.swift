import SwiftUI

/// Neubau N2: the „Zustellzettel" (ENTSCHEID §2.1 chrome renames) —
/// persistent couple status riding the native tab bar's bottom accessory
/// (Recon §2.8): partner presence (online dot + name/mood) on the left,
/// the delivery round + today's status ("Nachtpost · Siegel wartet") on
/// the right. The system re-hosts this one view in BOTH accessory
/// placements: `.expanded` (capsule above the full bar, with subline) and
/// `.inline` (single compact line inside the minimized bar).
///
/// FullRelease N2-B (Papier & Licht): this view lies ON the bar's system
/// glass — chrome, not content — so NIGHT rules hold: no paper fill, no
/// serif, no small caps (both live on paper only, Gebot 11). The wave
/// only firms up the today note's weight in the couple ink accent.
struct TodayAccessoryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Environment(\.coupleTint) private var coupleTint

    var body: some View {
        // Fix2-A №3: the Zettel gets its own minute tick — a plain
        // `Date()` read only at render time froze the round at the last
        // re-render, so at a round change the note still said
        // „Morgenpost" while the hero already wore „Tagespost". The
        // periodic `now` is passed down into every line, same honesty
        // path as the dashboard's TimelineView.
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            Button {
                Haptics.shared.tap()
                // There is no dedicated partner-profile screen — the dashboard
                // header IS the partner profile (avatars, mood, presence), so
                // the tap lands on Home.
                appState.activeTab = .home
            } label: {
                content(now: timeline.date)
            }
            .buttonStyle(.plain)
            // One combined VoiceOver sentence for the whole capsule instead of
            // three fragments (name / status / streak).
            .accessibilityLabel(a11yLabel(now: timeline.date))
            .accessibilityHint(L10n.t("accessory.a11yHint"))
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        switch placement {
        case .inline:
            inlineRow(now: now)
        default:
            expandedRow(now: now)
        }
    }

    /// `.inline`: the minimized bar offers one slim line — dot + name +
    /// today's note, nothing stacked.
    private func inlineRow(now: Date) -> some View {
        HStack(spacing: Space.xs) {
            presenceDot
            Text(inlineText(now: now))
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, LayoutMetrics.s(14))
        .frame(maxWidth: .infinity)
    }

    /// `.expanded`: avatar with the online dot, name/mood over the presence
    /// subline, today's note trailing in the couple tint.
    private func expandedRow(now: Date) -> some View {
        HStack(spacing: Space.s) {
            EmojiAvatarView(emoji: appState.partner?.avatar,
                            colorHex: appState.partner?.color,
                            size: LayoutMetrics.s(30),
                            online: appState.partner?.online ?? false)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Space.xs) {
                    Text(appState.partnerName)
                        .font(.system(.footnote, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    // The partner's mood emoji is couple DATA, not a deco
                    // glyph — same rule as the dashboard's mood badge.
                    if let mood = appState.partner?.mood, !mood.isEmpty {
                        Text(mood)
                            .font(.system(.footnote))
                    }
                }
                Text(presenceLine)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            .lineLimit(1)
            Spacer(minLength: Space.s)
            Text(todayLine(now: now))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(coupleTint.blend)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, LayoutMetrics.s(14))
        .frame(maxWidth: .infinity)
    }

    private var presenceDot: some View {
        Circle()
            .fill(appState.partner?.online == true ? Theme.mint : Theme.textTertiary)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }

    /// Presence beats plain online state: an active focus/sleep mode is the
    /// stronger signal ("no quick answer expected right now").
    private var presenceLine: String {
        if let kind = appState.partnerPresence?.kind {
            return L10n.t(kind.titleKey)
        }
        if appState.partner?.online == true { return L10n.t("home.online") }
        if let lastSeen = appState.partner?.lastSeenAt {
            return L10n.t("home.lastSeen", ["time": L10n.relativeShort(lastSeen)])
        }
        return L10n.t("home.offline")
    }

    /// The Zustellzettel note: "{Runde} · {Status}". The round derives
    /// from the minute tick's `now` (device-local hour, honesty contract
    /// documented in ZustellrundenLogic) — the accessory is chrome, never
    /// the stage, so no staging mark is consumed here. The streak stays
    /// readable one tap away (daily card pill → calendar); the Zettel
    /// tells what WAITS.
    private func todayLine(now: Date) -> String {
        let runde = Zustellrunde.from(hour: Calendar.current.component(.hour, from: now))
        return L10n.t(runde.titleKey) + " · " + tagesStatus
    }

    /// Seal waiting > open question > answered — the same spine the
    /// dashboard hero follows, told in two words. Fix3 №2: unpaired
    /// there IS no daily question yet — only „Sendung Nr. 1" waits, so
    /// the note must not promise "Frage offen" (honesty; the round name
    /// keeps standing left of the dot).
    private var tagesStatus: String {
        if appState.partner == nil {
            return L10n.t("postfach.zettel.sendung1")
        }
        if DailyRevealLauncher.revealPending(appState: appState) {
            return L10n.t("postfach.zettel.siegel")
        }
        if appState.dailyEntry?.myAnswer == nil {
            return L10n.t("postfach.zettel.offen")
        }
        return L10n.t("postfach.zettel.beantwortet")
    }

    private func inlineText(now: Date) -> String {
        "\(appState.partnerName) · \(todayLine(now: now))"
    }

    private func a11yLabel(now: Date) -> String {
        "\(appState.partnerName), \(presenceLine), \(todayLine(now: now))"
    }
}
