import SwiftUI

// "While you were away" — the missed-inbox dramaturgy (Dossier 40),
// extracted from the old 2 300-line DashboardView (W8A component split).
// One hero celebrated alone, the rest bundled into a sentence, chips as a
// checklist that checks itself off when places are visited.

struct MissedInboxCard: View {
    @Environment(AppState.self) private var appState
    @Environment(\.coupleTint) private var coupleTint

    let inbox: InboxResponse

    /// Missed-inbox checklist unfolded (Dossier 40, idea 2).
    @State private var expanded = false
    /// The 1.5 s "all caught up" beat is running — don't schedule it twice.
    @State private var dissolving = false
    /// Missed heartbeats are being replayed as haptics right now.
    @State private var replaying = false
    /// Bumps once per replayed heartbeat so the card visibly beats along.
    @State private var beat = 0
    /// The open-need hero's ack request is in flight.
    @State private var ackingNeed = false

    /// Counts mapped into the pure logic's snapshot. The letter flag rides
    /// the message teaser's `kind`; the need flag rides the open signal.
    private var snapshot: MissedInboxLogic.Snapshot {
        MissedInboxLogic.Snapshot(
            messages: inbox.messageCount,
            touches: inbox.touchCount,
            photos: inbox.photoCount,
            coupons: inbox.couponCount,
            songs: inbox.songCount,
            canvas: inbox.canvasCount,
            lastMessageIsLetter: inbox.messages?.last?.kind == "letter",
            hasOpenNeed: inbox.needsForMe?.openNeed != nil
        )
    }

    /// Preview of the newest missed message — only when the PARTNER sent it,
    /// and never for letters: a sealed letter is announced, not teased
    /// (Dossier 40, idea 10).
    private var teaser: String? {
        guard let last = inbox.messages?.last,
              last.senderId != appState.memberId,
              last.kind != "letter",
              let text = last.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    var body: some View {
        let snapshot = snapshot
        let hero = MissedInboxLogic.hero(snapshot)
        let chips = MissedInboxLogic.chips(snapshot, hero: hero)
        let caughtUp = MissedInboxLogic.caughtUp(snapshot, hero: hero,
                                                 visited: appState.missedVisited)
        return VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(.title3, design: .rounded))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Licht.lampengold)
                Text(L10n.t("home.missedTitle"))
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                Spacer(minLength: 0)
                Button {
                    Haptics.shared.tap()
                    withAnimation(Theme.Motion.settle) {
                        appState.dismissMissedInbox()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(Nacht.tertiaer)
                        .frame(width: LayoutMetrics.s(26), height: LayoutMetrics.s(26))
                        .background(Circle().fill(Papier.nachtInnenFill))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("common.close"))
            }
            if caughtUp {
                caughtUpRow
            } else {
                if let hero {
                    heroRow(hero)
                }
                if !chips.isEmpty {
                    restLine(chips, standalone: hero == nil)
                    if expanded || hero == nil {
                        checklist(chips)
                    }
                }
                if let teaser {
                    HStack(spacing: Space.xs) {
                        Image(systemName: "quote.opening")
                            .font(.system(.caption2, design: .rounded))
                            .foregroundStyle(Nacht.tertiaer)
                        Text(teaserLine(teaser))
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(Nacht.sekundaer)
                            .lineLimit(1)
                    }
                }
            }
        }
        .nightCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel(hero: hero, chips: chips, caughtUp: caughtUp))
        .accessibilityActions {
            // One card, one sentence, one action per destination — instead
            // of an eight-stop chip crawl (Dossier 40, idea 29).
            ForEach(chips, id: \.category) { chip in
                Button(phrase(chip)) { openCategory(chip.category) }
            }
            Button(L10n.t("common.close")) { appState.dismissMissedInbox() }
        }
        .onChange(of: caughtUp) { _, done in
            if done { finish() }
        }
        .onAppear {
            if caughtUp { finish() }
        }
    }

    /// "Du bist auf dem Laufenden" — catching up earns half a breath of
    /// reward before the card dissolves (Dossier 40, idea 28).
    private var caughtUpRow: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(Licht.lampengold)
            Text(L10n.t("home.missed.caughtUp"))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(Papier.aufNacht)
            Spacer(minLength: 0)
        }
        .transition(.opacity)
    }

    private func finish() {
        guard !dissolving else { return }
        dissolving = true
        Haptics.shared.success()
        SoundEngine.shared.play(.sparkle)
        Task {
            try await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(Theme.Motion.arrive) {
                appState.missedInbox = nil
                appState.missedVisited = []
            }
            dissolving = false
            expanded = false
        }
    }

    /// The single most important event, celebrated on its own line: an open
    /// need beats a sealed letter beats heartbeats beats photos.
    @ViewBuilder
    private func heroRow(_ hero: MissedInboxLogic.Hero) -> some View {
        switch hero {
        case .need:
            if let need = inbox.needsForMe?.openNeed {
                needHero(need)
            }
        case .letter:
            heroLine(icon: "envelope.fill", tint: Licht.glut,
                     title: L10n.t("home.missed.hero.letter",
                                   ["name": appState.partnerName]),
                     cta: L10n.t("home.missed.hero.letter.cta"),
                     done: appState.missedVisited.contains(
                         MissedInboxLogic.Category.messages.rawValue)) {
                appState.activeTab = .chat
            }
        case .touches(let count):
            heroLine(icon: "heart.fill", tint: coupleTint.blend,
                     title: L10n.t("home.missed.hero.touches", count: count),
                     cta: L10n.t("home.missed.hero.touches.cta"),
                     done: appState.missedVisited.contains(
                         MissedInboxLogic.Category.touches.rawValue),
                     beat: beat) {
                replayTouches(count)
            }
        case .photos(let count):
            heroLine(icon: "photo.on.rectangle.angled", tint: coupleTint.blend,
                     title: L10n.t("home.missed.hero.photos", count: count),
                     cta: L10n.t("home.missed.hero.photos.cta"),
                     done: appState.missedVisited.contains(
                         MissedInboxLogic.Category.photos.rawValue)) {
                appState.activeTab = .memories
            }
        }
    }

    /// An unanswered "I need you" is the unconditional hero (idea 9) —
    /// with the one-tap "I'm here" ack right on the card.
    private func needHero(_ need: NeedSignal) -> some View {
        let acked = appState.missedVisited.contains("need")
        return HStack(alignment: .center, spacing: Space.s) {
            Text(need.needType?.emoji ?? "🤍")
                .font(.system(.title3, design: .rounded))
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("home.missed.hero.need", ["name": appState.partnerName]))
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Papier.aufNacht)
                if let type = need.needType {
                    Text(L10n.t(type.titleKey))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Nacht.sekundaer)
                }
            }
            Spacer(minLength: 0)
            if acked {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(Licht.lampengold)
            } else {
                Button {
                    ackNeed(need)
                } label: {
                    // "I'm here" as a wax-drop chip — lifted to the DEEP
                    // couple wax with the light embossing ink (nacht-first
                    // §5: one wax app-wide, onWax retired here).
                    Text(L10n.t("needs.ack"))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(coupleTint.aufWachs)
                        .padding(.vertical, LayoutMetrics.s(6))
                        .padding(.horizontal, LayoutMetrics.s(12))
                        .background(Capsule().fill(coupleTint.wachsTief))
                }
                .buttonStyle(.plain)
                .disabled(ackingNeed)
            }
        }
        .padding(LayoutMetrics.s(10))
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Papier.nachtInnenFill)
                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(Nacht.naht, lineWidth: Theme.hairlineWidth))
        )
    }

    private func heroLine(icon: String, tint: Color, title: String,
                          cta: String, done: Bool, beat: Int = 0,
                          action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: Space.s) {
            Image(systemName: icon)
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(done ? Nacht.tertiaer : tint)
                .symbolEffect(.bounce, value: beat)
            Text(title)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(done ? Nacht.sekundaer : Papier.aufNacht)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(Licht.lampengold)
            } else {
                Button {
                    Haptics.shared.tap()
                    action()
                } label: {
                    Text(cta)
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(Papier.aufNacht)
                        .padding(.vertical, LayoutMetrics.s(6))
                        .padding(.horizontal, LayoutMetrics.s(12))
                        .background(Capsule().fill(tint.opacity(0.3)))
                }
                .buttonStyle(.plain)
                .disabled(replaying)
            }
        }
        .padding(LayoutMetrics.s(10))
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(tint.opacity(0.1))
        )
    }

    /// "Außerdem: 3 Nachrichten und ein Song · +2 mehr" — a message, not a
    /// data point (idea 2). Tapping unfolds the checklist.
    private func restLine(_ chips: [MissedInboxLogic.Chip], standalone: Bool) -> some View {
        Button {
            Haptics.shared.tap()
            withAnimation(Theme.Motion.settle) {
                expanded.toggle()
            }
        } label: {
            HStack(spacing: Space.xs) {
                Text(standalone
                     ? MissedInboxLogic.sentence(chips: chips)
                     : L10n.t("home.missed.rest",
                              ["sentence": MissedInboxLogic.sentence(chips: chips)]))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Nacht.sekundaer)
                    .multilineTextAlignment(.leading)
                if !standalone {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(Nacht.tertiaer)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .disabled(standalone)
    }

    /// The card is a checklist, not a one-shot (idea 7): every row has its
    /// own destination and keeps a ✓ once the place was visited.
    private func checklist(_ chips: [MissedInboxLogic.Chip]) -> some View {
        VStack(spacing: LayoutMetrics.s(6)) {
            ForEach(chips, id: \.category) { chip in
                let visited = appState.missedVisited.contains(chip.category.rawValue)
                Button {
                    openCategory(chip.category)
                } label: {
                    HStack(spacing: Space.s) {
                        Image(systemName: visited ? "checkmark.circle.fill"
                                                  : categoryIcon(chip.category))
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Licht.lampengold)
                            .frame(width: LayoutMetrics.s(20))
                        Text(phrase(chip))
                            .font(.system(.footnote, design: .rounded).weight(.semibold))
                            .foregroundStyle(visited ? Nacht.tertiaer : Papier.aufNacht)
                            .strikethrough(visited, color: Nacht.tertiaer)
                        Spacer(minLength: 0)
                        if !visited {
                            Image(systemName: chip.category == .touches
                                  ? "waveform.path.ecg" : "chevron.right")
                                .font(.system(.caption2, design: .rounded).weight(.bold))
                                .foregroundStyle(Nacht.tertiaer)
                        }
                    }
                    .padding(.vertical, LayoutMetrics.s(6))
                    .padding(.horizontal, LayoutMetrics.s(8))
                    .background(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(visited ? Papier.nachtInnenFill
                                          : coupleTint.blend.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
                .disabled(chip.category == .touches && replaying)
            }
        }
    }

    private func categoryIcon(_ category: MissedInboxLogic.Category) -> String {
        switch category {
        case .messages: return "bubble.left.fill"
        case .touches: return "heart.fill"
        case .photos: return "photo.on.rectangle.angled"
        case .coupons: return "ticket.fill"
        case .songs: return "music.note"
        case .canvas: return "paintbrush.pointed.fill"
        }
    }

    private func phrase(_ chip: MissedInboxLogic.Chip) -> String {
        L10n.t("home.missed.phrase.\(chip.category.rawValue)", count: chip.count)
    }

    /// Honest teaser (idea 24): the newest line plus "and N more" when the
    /// count says there is more behind it.
    private func teaserLine(_ teaser: String) -> String {
        let more = inbox.messageCount - 1
        guard more > 0 else { return "„\(teaser)“" }
        return "„\(teaser)“ · " + L10n.t("home.missed.teaser.more", ["count": String(more)])
    }

    /// Every chip leads somewhere real (idea 3): chat, the memories places,
    /// or — for heartbeats — a felt replay right on the card. Visiting marks
    /// the row done; the card never self-destructs on tap.
    private func openCategory(_ category: MissedInboxLogic.Category) {
        Haptics.shared.tap()
        switch category {
        case .messages:
            appState.activeTab = .chat
        case .touches:
            replayTouches(appState.missedInbox?.touchCount ?? 1)
        case .photos:
            appState.handleURL(URL(string: "sooodreamy://photos")!)
        case .coupons:
            appState.handleURL(URL(string: "sooodreamy://coupons")!)
        case .canvas:
            appState.handleURL(URL(string: "sooodreamy://canvas")!)
        case .songs:
            appState.markMissedVisited(.songs)
            appState.activeTab = .memories
        }
    }

    /// "FEEL what you missed" (idea 19): missed heartbeats replay as a short
    /// haptic sequence, the hero icon beats along, then the row checks off.
    private func replayTouches(_ count: Int) {
        guard !replaying else { return }
        replaying = true
        let beats = min(count, 5)
        SoundEngine.shared.play(for: .heartbeat)
        Task {
            for index in 0..<beats {
                Haptics.shared.play(TouchKind.heartbeat)
                withAnimation(Theme.Motion.playful) {
                    beat += 1
                }
                if index < beats - 1 {
                    try await Task.sleep(nanoseconds: 800_000_000)
                }
            }
            replaying = false
            withAnimation(Theme.Motion.settle) {
                appState.markMissedVisited(.touches)
            }
        }
    }

    private func ackNeed(_ need: NeedSignal) {
        guard let api = appState.api, !ackingNeed else { return }
        ackingNeed = true
        Task {
            do {
                _ = try await api.ackNeed(id: need.id)
                Haptics.shared.success()
                SoundEngine.shared.play(.sparkle)
                withAnimation(Theme.Motion.settle) {
                    appState.markMissedNeedVisited()
                }
            } catch {
                appState.handleAPIError(error)
            }
            ackingNeed = false
        }
    }

    /// The whole card reads as ONE VoiceOver element — a sentence, not an
    /// eight-stop chip crawl (idea 29).
    private func a11yLabel(hero: MissedInboxLogic.Hero?,
                           chips: [MissedInboxLogic.Chip],
                           caughtUp: Bool) -> String {
        if caughtUp {
            return L10n.t("home.missed.caughtUp")
        }
        var parts = [L10n.t("home.missedTitle")]
        switch hero {
        case .need:
            parts.append(L10n.t("home.missed.hero.need", ["name": appState.partnerName]))
        case .letter:
            parts.append(L10n.t("home.missed.hero.letter", ["name": appState.partnerName]))
        case .touches(let count):
            parts.append(L10n.t("home.missed.hero.touches", count: count))
        case .photos(let count):
            parts.append(L10n.t("home.missed.hero.photos", count: count))
        case nil:
            break
        }
        let sentence = MissedInboxLogic.sentence(chips: chips)
        if !sentence.isEmpty {
            parts.append(sentence)
        }
        return parts.joined(separator: ". ")
    }
}

/// Five seconds of "Rückgängig" after the X (idea 15) — the since-window
/// already advanced, so dismiss must never be final by accident.
struct MissedUndoRow: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "moon.zzz")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Nacht.tertiaer)
            Text(L10n.t("home.missed.undo.hidden"))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Nacht.sekundaer)
            Spacer(minLength: 0)
            Button {
                Haptics.shared.tap()
                withAnimation(Theme.Motion.settle) {
                    appState.undoMissedDismiss()
                }
            } label: {
                Text(L10n.t("home.missed.undo.cta"))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(Licht.lampengold)
            }
            .buttonStyle(.plain)
        }
        .nightCard(padding: .compact)
        .transition(.opacity)
    }
}
