import SwiftUI

// MARK: - Unser Jahr ✨
//
// Aggregated "year in review" from `GET /api/yearreview` — big numbers,
// per-member splits and a share-to-chat summary. Early-year counts can be
// lower bounds because capped server lists roll off.

struct YearReviewView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint

    @State private var review: YearReview?
    @State private var loading = true
    @State private var failed = false
    @State private var year = SharedDates.calendar.component(.year, from: Date())
    @State private var sharing = false
    @State private var shared = false

    private var earliestYear: Int {
        guard let created = appState.couple?.createdAt else { return year }
        return SharedDates.calendar.component(.year, from: created)
    }

    var body: some View {
        ZStack {
            DreamyBackground()
            content
        }
        .navigationTitle(L10n.t("yearreview.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: year) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            ScrollView {
                // The placeholders stand in for paper cards, so they wait
                // as paper — not as glass (screens pick skeletons by ground).
                VStack(spacing: Space.l) {
                    PaperSkeleton(kind: .card(height: 120), onNacht: true)
                    HStack(spacing: Space.m) {
                        PaperSkeleton(kind: .card(height: 96), onNacht: true)
                        PaperSkeleton(kind: .card(height: 96), onNacht: true)
                    }
                    HStack(spacing: Space.m) {
                        PaperSkeleton(kind: .card(height: 96), onNacht: true)
                        PaperSkeleton(kind: .card(height: 96), onNacht: true)
                    }
                }
                .padding(Space.l)
            }
        } else if failed {
            EmptyStateView(systemImage: "antenna.radiowaves.left.and.right.slash",
                           title: L10n.t("yearreview.loadError"),
                           subtitle: L10n.t("weekreview.error.subtitle"),
                           actionTitle: L10n.t("common.retry"),
                           action: { Task { await load() } })
        } else if let review {
            ScrollView {
                VStack(spacing: Space.l) {
                    header(review)
                    statGrid(review)
                    memberSplits(review)
                    footnote
                    shareButton(review)
                }
                .padding(Space.l)
                .padding(.bottom, Space.m)
            }
        }
    }

    // MARK: Header + year switcher

    // The one Briefbogen hero of this screen: the year cover sheet, banded
    // and sealed — the festive letterhead the album opens with.
    private func header(_ review: YearReview) -> some View {
        VStack(spacing: Space.s) {
            HStack(spacing: Space.l) {
                yearArrow(systemName: "chevron.left", enabled: year > earliestYear) {
                    year -= 1
                }
                Text(String(year))
                    .font(Typo.hero.monospacedDigit())
                    .foregroundStyle(coupleTint.tinte)
                yearArrow(systemName: "chevron.right",
                          enabled: year < SharedDates.calendar.component(.year, from: Date())) {
                    year += 1
                }
            }
            Text(L10n.t("yearreview.subtitle", ["year": String(year)]))
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Tinte.sekundaer)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .paperCard(.briefbogen)
        .briefbogenBand(seed: memoriesPaperSeed(appState.couple?.id ?? "yearreview"))
        .blaetternEintritt()
    }

    private func yearArrow(systemName: String, enabled: Bool,
                           action: @escaping () -> Void) -> some View {
        Button {
            Haptics.shared.tap()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(.body, design: .rounded).weight(.bold))
                .foregroundStyle(enabled ? coupleTint.tinte : Tinte.tertiaer.opacity(0.5))
                .frame(width: LayoutMetrics.s(38), height: LayoutMetrics.s(38))
                .background(
                    Circle().fill(Papier.innenFill)
                        .overlay(Circle().strokeBorder(Papier.kante,
                                                       lineWidth: Theme.hairlineWidth))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: Stat grid

    private func statGrid(_ review: YearReview) -> some View {
        let columns = [GridItem(.flexible(), spacing: Space.m), GridItem(.flexible(), spacing: Space.m)]
        // Tints are decorative accents (hairline border) — the numbers read
        // in aufNacht; couple colors stay raw non-text marks on night.
        return LazyVGrid(columns: columns, spacing: Space.m) {
            StatTile(emoji: "📸", value: review.photosAdded,
                     label: L10n.t("yearreview.stat.photos"), tint: coupleTint.blend)
            StatTile(emoji: "🎬", value: review.videosAdded,
                     label: L10n.t("yearreview.stat.videos"), tint: Theme.blue)
            StatTile(emoji: "💬", value: review.messagesByMember.values.reduce(0, +),
                     label: L10n.t("yearreview.stat.messages"), tint: coupleTint.primary)
            StatTile(emoji: "💓", value: review.touchesByMember.values.reduce(0, +),
                     label: L10n.t("yearreview.stat.touches"), tint: coupleTint.secondary)
            StatTile(emoji: "🎮", value: review.gamesPlayed,
                     label: L10n.t("yearreview.stat.games"), tint: Theme.mint)
            StatTile(emoji: "🟩", value: review.wordleDaysPlayed,
                     label: L10n.t("yearreview.stat.wordle"), tint: Theme.mint)
            StatTile(emoji: "❓", value: review.dailyBothAnswered,
                     label: L10n.t("yearreview.stat.daily"), tint: Theme.gold)
            StatTile(emoji: "☀️", value: review.checkinDaysBoth,
                     label: L10n.t("yearreview.stat.checkins"), tint: Theme.gold,
                     sub: review.checkinStreak > 1
                        ? L10n.t("yearreview.stat.checkinStreak", ["n": String(review.checkinStreak)])
                        : nil)
            StatTile(emoji: "🫂", value: review.hugsSent,
                     label: L10n.t("yearreview.stat.hugs"), tint: coupleTint.secondary,
                     sub: review.hugsOpened > 0
                        ? L10n.t("yearreview.stat.hugsOpened", ["n": String(review.hugsOpened)])
                        : nil)
            StatTile(emoji: "🎟️", value: review.couponsRedeemed,
                     label: L10n.t("yearreview.stat.coupons"), tint: Theme.gold)
            StatTile(emoji: "🎵", value: review.songsAdded,
                     label: L10n.t("yearreview.stat.songs"), tint: Theme.mint)
            StatTile(emoji: "🌌", value: review.bucketDone,
                     label: L10n.t("yearreview.stat.bucket"), tint: Theme.indigo)
            StatTile(emoji: "🗓️", value: review.eventsCreated,
                     label: L10n.t("yearreview.stat.events"), tint: Theme.gold)
            StatTile(emoji: "📷", value: review.potdDays,
                     label: L10n.t("yearreview.stat.potd"), tint: coupleTint.blend)
        }
    }

    // MARK: Per-member splits

    @ViewBuilder
    private func memberSplits(_ review: YearReview) -> some View {
        let members = appState.couple?.members ?? []
        if !members.isEmpty,
           review.touchesByMember.values.reduce(0, +) > 0
            || review.gamesPlayed > 0 || review.wordleDaysPlayed > 0 {
            VStack(alignment: .leading, spacing: Space.m) {
                ForEach(members) { member in
                    memberRow(member, review: review)
                }
            }
            .nightCard()
        }
    }

    private func memberRow(_ member: Member, review: YearReview) -> some View {
        // Identity lives in the avatar ring — the counts read in the
        // pinned night inks (touches in lamplight, messages secondary).
        HStack(spacing: Space.m) {
            EmojiAvatarView(emoji: member.avatar, colorHex: member.color,
                            size: LayoutMetrics.s(40), online: false)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(member.name)
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                HStack(spacing: Space.s) {
                    if let top = review.topTouchType[member.id] ?? nil,
                       let kind = TouchKind(rawValue: top) {
                        Text("\(L10n.t("yearreview.topTouch")): \(kind.emoji)")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Nacht.sekundaer)
                    }
                    let wins = (review.gameWins[member.id] ?? 0) + (review.wordleWins[member.id] ?? 0)
                    if wins > 0 {
                        HStack(spacing: Space.xs) {
                            Image(systemName: "trophy.fill")
                                .foregroundStyle(Nacht.sekundaer)
                            Text("\(wins) \(L10n.t("yearreview.wins"))")
                        }
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Nacht.sekundaer)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Space.xs) {
                HStack(spacing: Space.xs) {
                    Text("\(review.touchesByMember[member.id] ?? 0)")
                    Image(icon: .sendLove)
                }
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Licht.lampengold)
                HStack(spacing: Space.xs) {
                    Text("\(review.messagesByMember[member.id] ?? 0)")
                    Image(systemName: "bubble.left.fill")
                }
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(Nacht.sekundaer)
            }
            .monospacedDigit()
        }
    }

    // MARK: Footnote + share

    private var footnote: some View {
        Text(L10n.t("yearreview.footnote"))
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(Theme.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private func shareButton(_ review: YearReview) -> some View {
        Button {
            share(review)
        } label: {
            if sharing {
                BusySpinner()
            } else {
                Label(L10n.t(shared ? "yearreview.shareSent" : "yearreview.share"),
                      systemImage: shared ? "checkmark" : "paperplane.fill")
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(sharing || shared)
    }

    private func share(_ review: YearReview) {
        guard let api = appState.api, !sharing else { return }
        sharing = true
        Haptics.shared.tap()
        let lines = [
            L10n.t("yearreview.shareHeader", ["year": String(review.year)]),
            "📸 " + L10n.t("yearreview.shareLine.photos", ["n": String(review.photosAdded)]),
            "💬 " + L10n.t("yearreview.shareLine.messages",
                           ["n": String(review.messagesByMember.values.reduce(0, +))]),
            "💓 " + L10n.t("yearreview.shareLine.touches",
                           ["n": String(review.touchesByMember.values.reduce(0, +))]),
            "🎮 " + L10n.t("yearreview.shareLine.games", ["n": String(review.gamesPlayed)])
        ]
        Task {
            do {
                _ = try await api.sendMessage(type: .text, text: lines.joined(separator: "\n"))
                shared = true
                SoundEngine.shared.play(.pop)
                Haptics.shared.success()
                appState.showToast(L10n.t("yearreview.shareSent"), style: .success)
            } catch {
                appState.handleAPIError(error)
            }
            sharing = false
        }
    }

    // MARK: Data

    private func load() async {
        guard let api = appState.api else { return }
        loading = true
        failed = false
        shared = false
        do {
            review = try await api.yearReview(year: year)
        } catch {
            failed = true
        }
        loading = false
    }
}

// MARK: - Stat tile

private struct StatTile: View {
    let emoji: String
    let value: Int
    let label: String
    let tint: Color
    var sub: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text(emoji)
                    .font(.system(.title3))
                Spacer()
                // Numbers read as light ink; the tint stays a decorative
                // accent on the hairline (non-text on the night card).
                Text("\(value)")
                    .font(Typo.number)
                    .foregroundStyle(value > 0 ? Papier.aufNacht : Nacht.tertiaer)
                    .contentTransition(.numericText())
            }
            Text(label)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Nacht.sekundaer)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let sub {
                Text(sub)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Nacht.sekundaer)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightCard()
        .overlay(
            RoundedRectangle(cornerRadius: Radius.papier, style: .continuous)
                .strokeBorder(tint.opacity(0.25), lineWidth: Theme.hairlineWidth)
        )
    }
}
