import Foundation

enum DashboardGroup: String, CaseIterable, Codable {
    case rituals
    case games
    case moments
}

struct DashboardPriorityContext: Equatable {
    var hasOpenNeed: Bool
    var hasUnlockableCapsule: Bool
    var gamesAwaitingMe: Int
    var dailyOpen: Bool
    var hasUpcomingMoment: Bool
}

enum DashboardPriority {
    static func score(_ group: DashboardGroup, context: DashboardPriorityContext) -> Int {
        switch group {
        case .rituals:
            return (context.hasOpenNeed ? 1_000 : 0)
                + (context.hasUnlockableCapsule ? 700 : 0)
                + (context.dailyOpen ? 250 : 0)
                + 100
        case .games:
            return min(context.gamesAwaitingMe, 99) * 300 + 80
        case .moments:
            return (context.hasUpcomingMoment ? 400 : 0) + 60
        }
    }

    static func orderedGroups(
        context: DashboardPriorityContext,
        pinnedFirst: DashboardGroup? = nil,
        hidden: Set<DashboardGroup> = []
    ) -> [DashboardGroup] {
        DashboardGroup.allCases
            .filter { !hidden.contains($0) }
            .sorted { lhs, rhs in
                if lhs == pinnedFirst { return true }
                if rhs == pinnedFirst { return false }
                let left = score(lhs, context: context)
                let right = score(rhs, context: context)
                return left == right ? lhs.rawValue < rhs.rawValue : left > right
            }
    }
}

enum WhatsNewGate {
    static func shouldPresent(currentVersion: String, lastPresentedVersion: String?) -> Bool {
        !currentVersion.isEmpty && currentVersion != lastPresentedVersion
    }
}

// MARK: - Hero slot + card budget (Dossier 23 #1/#2/#7/#22)
//
// Neubau N2: the coarse `DayPhase` became the `Zustellrunde` (see
// Content/ZustellrundenLogic.swift) — same discipline ("computed once per
// activation, never mid-look"), same boundaries, postal names. The old
// evening/night pair collapsed into `nachtpost` without behavior change:
// both phases only ever drove the night-checkin suggestion.

/// Every distinct dashboard card. `resting` and `firstMoment` are hero-only —
/// the reward state when everything is shared today, and the one focused
/// stage a brand-new couple sees before its very first shared moment.
enum DashboardCard: String, CaseIterable, Codable {
    case firstMoment
    case daily
    case checkin
    case resting
    case touches
    case rituals
    case quest
    case moments
    case dateNight
    case hugQueue
    case level
    /// The season-calendar door as its OWN ranked card (FXC-4 #9) — a
    /// ready door is a waiting surprise, not the seventh unit inside the
    /// rituals block.
    case seasonDoor

    /// Edit-sheet compatibility: pin/hide still speak the old group
    /// language; every card belongs to at most one group.
    var group: DashboardGroup? {
        switch self {
        case .quest: return .games
        case .moments: return .moments
        case .checkin, .touches, .rituals, .dateNight, .hugQueue, .level,
             .seasonDoor:
            return .rituals
        case .daily, .resting, .firstMoment: return nil
        }
    }
}

struct DashboardCardContext: Equatable {
    var runde: Zustellrunde
    var morningCheckinDone: Bool
    var nightCheckinDone: Bool
    var myDailyAnswered: Bool
    var bothAnswered: Bool
    /// Both answered but the seal is unbroken on this device (K-03).
    var revealPending: Bool
    var hasOpenNeed: Bool
    var gamesAwaitingMe: Int
    var hasMemoryToday: Bool
    var hasUpcomingMoment: Bool
    /// Fresh couple that hasn't shared its very first moment yet — computed
    /// via `DashboardPriority.firstMomentPending`. Defaults to false so
    /// established couples never see the welcome stage.
    var firstMomentPending: Bool = false
    /// A season-calendar door addressed to me is unlockable right now —
    /// the standalone door card must climb into the visible budget instead
    /// of waiting in the fold while the surprise waits (FX-O #8, FXC-4 #9).
    var seasonDoorReady: Bool = false
}

/// The dashboard's whole above-the-fold story: ONE hero, at most
/// `DashboardPriority.cardBudget` cards below it, everything else folded
/// behind a single "more" group.
struct DashboardLayout: Equatable {
    var hero: DashboardCard
    var visible: [DashboardCard]
    var more: [DashboardCard]
}

extension DashboardPriority {
    /// Hard budget below the hero — the cure for "8–10 competing units
    /// before the first scroll".
    static let cardBudget = 3

    /// A couple is "in its first moment" until either the daily question got
    /// its first answer or the first greeting went out. Quest steps come from
    /// the server; the live `myDailyAnswered` flag bridges socket latency so
    /// the stage retires the instant the answer is typed, not a refresh later.
    static func firstMomentPending(
        isNewCouple: Bool,
        questDone: Bool,
        dailyStepDone: Bool,
        touchStepDone: Bool,
        myDailyAnswered: Bool
    ) -> Bool {
        isNewCouple && !questDone && !dailyStepDone && !touchStepDone && !myDailyAnswered
    }

    /// True while the CURRENT round's check-in ritual is still open —
    /// morgenpost waits for the morning greeting, nachtpost (17–05) for
    /// the good-night one. The tagespost has no ritual of its own.
    static func rundenCheckinOffen(context c: DashboardCardContext) -> Bool {
        (c.runde == .morgenpost && !c.morningCheckinDone)
            || (c.runde == .nachtpost && !c.nightCheckinDone)
    }

    /// The one big thing right now — re-eval №2: the day LETTER
    /// (FirstMoment/DailyQuestion) is ALWAYS the stamped possession-hero
    /// of a paired screen; the round's check-in became the first dark
    /// delivery card BELOW it (see `score`), so the Stempelzeile prints
    /// on paper in every pair state. Resting stays the reward — but only
    /// once genuinely nothing waits, the round's ritual included.
    static func heroCard(context c: DashboardCardContext) -> DashboardCard {
        // 0. A brand-new couple gets ONE focused stage: their first moment.
        //    Nothing else on the page matters before the first shared thing.
        if c.firstMomentPending { return .firstMoment }
        // 1. The open question is the letter's own call.
        if !c.myDailyAnswered { return .daily }
        // 2. A waiting reveal keeps the sealed letter on stage.
        if c.revealPending { return .daily }
        // 3. Everything shared today — being done IS the reward. An open
        //    round check-in below would give "Alles geteilt" the lie, so
        //    the letter keeps the stage until the ritual is done too.
        if c.bothAnswered && c.gamesAwaitingMe == 0 && !c.hasOpenNeed
            && !rundenCheckinOffen(context: c) { return .resting }
        // 4. Otherwise the daily letter carries the "waiting for them" story.
        return .daily
    }

    static func score(_ card: DashboardCard, context c: DashboardCardContext) -> Int {
        switch card {
        case .daily:
            if !c.myDailyAnswered { return 900 }
            if c.revealPending { return 850 }
            return 200
        case .checkin:
            // Re-eval №2: the round's open ritual is the FIRST dark
            // delivery card under the stamped letter hero — above even an
            // open need (rituals 1 000). The morning greeting presses a
            // touch harder than the good-night one.
            if c.runde == .morgenpost && !c.morningCheckinDone { return 1_100 }
            if c.runde == .nachtpost && !c.nightCheckinDone { return 1_050 }
            return 90
        case .rituals:
            if c.hasOpenNeed { return 1_000 }
            return 120
        case .seasonDoor:
            // Its own ranked card now: a READY door outranks the evergreen
            // cards (touches 300, answered daily 200) — the surprise must
            // not hide in the fold. While it merely counts down, the card
            // waits quietly in the fold, countdown still ticking.
            return c.seasonDoorReady ? 520 : 50
        case .quest:
            return c.gamesAwaitingMe > 0 ? 600 + min(c.gamesAwaitingMe, 9) * 40 : 40
        case .touches:
            return 300
        case .moments:
            return c.hasMemoryToday ? 250 : 30
        case .dateNight:
            return c.hasUpcomingMoment ? 220 : 100
        case .hugQueue:
            return 80
        case .level:
            return 60
        case .resting, .firstMoment:
            return 0
        }
    }

    static func layout(
        context: DashboardCardContext,
        pinned: DashboardGroup? = nil,
        hidden: Set<DashboardGroup> = []
    ) -> DashboardLayout {
        var hero = heroCard(context: context)
        // The user hid the hero's group (e.g. rituals off ⇒ no check-in
        // hero) — fall back to the daily/resting spine, which has no group.
        if let group = hero.group, hidden.contains(group) {
            hero = context.bothAnswered && !context.revealPending && context.gamesAwaitingMe == 0
                ? .resting : .daily
        }
        let ranked = DashboardCard.allCases
            .filter { $0 != hero && $0 != .resting && $0 != .firstMoment }
            // The first-moment stage CONTAINS the daily question and the
            // greeting as its two calls — repeating those cards right below
            // would split the focus the stage exists to create.
            .filter { hero != .firstMoment || ($0 != .daily && $0 != .touches) }
            .filter { card in card.group.map { !hidden.contains($0) } ?? true }
            .sorted { lhs, rhs in
                let lhsPinned = lhs.group != nil && lhs.group == pinned
                let rhsPinned = rhs.group != nil && rhs.group == pinned
                if lhsPinned != rhsPinned { return lhsPinned }
                let left = score(lhs, context: context)
                let right = score(rhs, context: context)
                return left == right ? lhs.rawValue < rhs.rawValue : left > right
            }
        return DashboardLayout(
            hero: hero,
            visible: Array(ranked.prefix(cardBudget)),
            more: Array(ranked.dropFirst(cardBudget))
        )
    }

    /// AX composition (re-eval №9): at accessibility text sizes the grown
    /// header plus the anniversary banner ate the whole first screen —
    /// the banner sorts BEHIND the day hero there, so the letter stays
    /// the first thing after the head. Regular sizes keep the banner as
    /// the celebratory opener. Type never shrinks either way.
    static func jubilaeumHinterHero(isAccessibilitySize: Bool) -> Bool {
        isAccessibilitySize
    }

    /// Coarse height class per card for the two-column split, measured in
    /// "small card" units. The rituals block stacks several sub-cards, the
    /// touch grid carries rows of buttons — treating them like a one-line
    /// level card is what left the right column near-empty (FXC-4 #8).
    /// Round-3 calibration (FXD-2 #9): the RENDERED rituals block ended
    /// ~330 pt (≈3 small-card units) below what weight 3 promised — it
    /// really stacks up to seven sub-cards, so its honest weight is 6.
    static func columnWeight(_ card: DashboardCard) -> Int {
        switch card {
        case .rituals: return 6
        case .touches, .daily: return 2
        default: return 1
        }
    }

    /// Regular-width dashboards lay the story cards out in two INDEPENDENT
    /// columns. A `LazyVGrid` row is always as tall as its tallest card,
    /// which carved ~200 pt holes under short neighbors (iPad eval).
    /// Height-aware greedy distribution: every item lands in the currently
    /// SHORTER column (ties go left), so a heavy rituals block no longer
    /// hoards one side while the other stays near-empty. With uniform
    /// weights this degrades to the old alternating split — the ranking
    /// stays readable left-to-right.
    static func columnSplit<T>(
        _ items: [T],
        weight: (T) -> Int = { _ in 1 }
    ) -> (left: [T], right: [T]) {
        var left: [T] = []
        var right: [T] = []
        var leftHeight = 0
        var rightHeight = 0
        for item in items {
            if rightHeight < leftHeight {
                right.append(item)
                rightHeight += max(1, weight(item))
            } else {
                left.append(item)
                leftHeight += max(1, weight(item))
            }
        }
        return (left, right)
    }

    /// iPad balance, round 3 (FXD-2 #9): with only three budgeted cards no
    /// split can balance columns when the rituals block ALONE outweighs
    /// both neighbors together — the rendered right column ended ~330 pt
    /// early. Instead of padding with emptiness, LIGHT cards from the
    /// "more" fold move up into the SHORTER column (in their rank order)
    /// until the computed heights differ by at most one small-card unit or
    /// no folded card fits the remaining gap. Everything not pulled stays
    /// folded; compact (phone) layouts never call this.
    static func balancedColumns(
        visible: [DashboardCard],
        more: [DashboardCard]
    ) -> (left: [DashboardCard], right: [DashboardCard], more: [DashboardCard]) {
        var (left, right) = columnSplit(visible, weight: columnWeight)
        var leftHeight = left.map(columnWeight).reduce(0, +)
        var rightHeight = right.map(columnWeight).reduce(0, +)
        var folded = more
        while abs(leftHeight - rightHeight) >= 2 {
            let gap = abs(leftHeight - rightHeight)
            // The highest-ranked folded card that still fits the gap —
            // pulling a heavier card would overshoot past balanced.
            guard let index = folded.firstIndex(where: { columnWeight($0) <= gap })
            else { break }
            let card = folded.remove(at: index)
            if leftHeight < rightHeight {
                left.append(card)
                leftHeight += columnWeight(card)
            } else {
                right.append(card)
                rightHeight += columnWeight(card)
            }
        }
        return (left, right, folded)
    }
}
