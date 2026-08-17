import Foundation

// Der app-weite Zeremonien-Schiedsrichter — die Verallgemeinerung des
// Spiele-Budgets aus GameDelightRules auf ALLE großen Momente der App.
// Vorher galt „höchstens zwei Epics pro zwanzig Minuten" nur für Spiele;
// Level-Ups, Abzeichen, Streak-Meilensteine, Reveal-Jackpots und
// Saison-Momente feuerten daran vorbei — und Jackpot+Streak konnten im
// selben Atemzug doppelt feuern. Jetzt beantragt jeder große Moment hier:
//
//   * EIN gemeinsames rollierendes Budget (DelightLedger) für alle Wege.
//   * Herabstufung statt Stille: ein abgelehnter Epic wird Medium —
//     der Moment bleibt gefeiert, nur die Inflation endet.
//   * Koaleszierung: Events, die im selben Schwung eintreffen (etwa
//     Level-Up + Level-Abzeichen aus demselben Server-Write), bündeln
//     sich zu EINER Zeremonie mit Stapel-Inhalt statt einer Kette
//     gleicher Fanfaren.
//
// Foundation-only und mit injizierter Zeit — die Budget-Mathematik läuft
// in den Linux-LogicTests. GameDelightRules delegiert seine Budget-Hälfte
// hierher (der Spiele-Tier-Katalog bleibt dort).

/// Rolling ledger of granted BIG ceremonies — the anti-inflation memory,
/// now shared across the whole app. Value type with injected time so the
/// budget math stays Linux-testable. (`GameCeremonyLedger` is a typealias
/// of this — same Codable shape, nothing re-learns.)
struct DelightLedger: Codable, Equatable {
    var bigMoments: [Date] = []

    init(bigMoments: [Date] = []) {
        self.bigMoments = bigMoments
    }
}

/// Every big moment the app knows, from every layer. Games route through
/// GameDelightRules (which delegates here); the rest call the arbiter
/// directly at their celebration entry points.
enum BigMoment: String, Codable, CaseIterable {
    case levelUp
    case badge
    case secretBadge
    case streakMilestone
    case revealJackpot
    case seasonMilestone
    case gameMatchWon
    /// A time capsule opened after months of waiting — rituals layer.
    case capsuleOpened
    /// A shared goal reached 100 % — rituals layer.
    case goalCompleted
}

enum DelightArbiter {
    // MARK: Budget (moved here from GameDelightRules — ONE budget, app-wide)

    /// Rolling window and cap for BIG ceremonies: at most two epics per
    /// twenty minutes — across games, level-ups, badges, jackpots alike.
    static let bigWindow: TimeInterval = 20 * 60
    static let maxBigPerWindow = 2

    /// How big a moment ASKS to be before the budget speaks. Regular
    /// badges are medium by design (the shelf adds the shine) — they
    /// never touch the budget.
    static func requestedIntensity(for moment: BigMoment) -> DelightIntensity {
        switch moment {
        case .badge: return .medium
        case .levelUp, .secretBadge, .streakMilestone,
             .revealJackpot, .seasonMilestone, .gameMatchWon,
             .capsuleOpened, .goalCompleted:
            return .epic
        }
    }

    /// Drops everything outside the rolling window. Entries slightly in
    /// the FUTURE are kept: near-simultaneous grants arrive out of order
    /// (parallel tasks stamp `now` before they are scheduled), and
    /// dropping them let a late low-stamp request overdraw the budget
    /// (flaky parallel test: 3 epics). Only absurdly-future entries —
    /// more than one window ahead, i.e. a device clock set back — clear.
    static func pruned(_ ledger: DelightLedger, now: Date) -> DelightLedger {
        var next = ledger
        next.bigMoments = next.bigMoments.filter {
            $0.timeIntervalSince(now) < bigWindow
                && now.timeIntervalSince($0) < bigWindow
        }
        return next
    }

    /// The raw budget question: may ONE more big ceremony play right now?
    /// Granted bigs are recorded in the returned ledger.
    static func requestBig(ledger: DelightLedger, now: Date)
        -> (granted: Bool, ledger: DelightLedger) {
        var next = pruned(ledger, now: now)
        guard next.bigMoments.count < maxBigPerWindow else { return (false, next) }
        next.bigMoments.append(now)
        return (true, next)
    }

    /// The full grant: requested intensity, budget applied, DEGRADATION
    /// instead of silence — an exhausted window turns epic into medium,
    /// never into nothing.
    static func grant(_ moment: BigMoment, ledger: DelightLedger, now: Date)
        -> (intensity: DelightIntensity, ledger: DelightLedger) {
        let requested = requestedIntensity(for: moment)
        guard requested == .epic else { return (requested, pruned(ledger, now: now)) }
        let result = requestBig(ledger: ledger, now: now)
        return (result.granted ? .epic : .medium, result.ledger)
    }

    // MARK: Coalescing — simultaneous events become ONE ceremony

    /// Events landing this close to a just-presented ceremony join it as
    /// stacked content (level-up + its level badge arrive in the same
    /// server write) instead of queuing a second full fanfare.
    static let coalesceWindow: TimeInterval = 2.5

    static func shouldCoalesce(lastPresentedAt: Date?, next: Date) -> Bool {
        guard let lastPresentedAt else { return false }
        let gap = next.timeIntervalSince(lastPresentedAt)
        return gap >= 0 && gap < coalesceWindow
    }
}

/// Runtime half: the ONE persisted app-wide ledger — for app moments AND
/// the games layer (GameEndCelebration delegates here; it used to keep a
/// separate in-memory ledger, so game epics and level-up epics never
/// actually shared the budget at runtime). `@MainActor`-isolated so every
/// `request` is one atomic load→grant→persist: unsynchronized parallel
/// callers used to race the read-modify-write and overdraw the window
/// (64 parallel requests → 34 epics). UserDefaults-backed so the budget
/// survives relaunches; injectable defaults keep it testable.
@MainActor
enum DelightArbiterStore {
    static let defaultsKey = "delight.arbiter.ledger"

    static func load(defaults: UserDefaults = .standard) -> DelightLedger {
        guard let data = defaults.data(forKey: defaultsKey),
              let ledger = try? JSONDecoder().decode(DelightLedger.self, from: data) else {
            return DelightLedger()
        }
        return ledger
    }

    static func save(_ ledger: DelightLedger, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    /// One-call request for the celebration paths: load → grant → persist,
    /// atomically (no suspension point between the three). Returns the
    /// intensity the moment may play at.
    @discardableResult
    static func request(_ moment: BigMoment, now: Date = Date(),
                        defaults: UserDefaults = .standard) -> DelightIntensity {
        let granted = DelightArbiter.grant(moment, ledger: load(defaults: defaults), now: now)
        save(granted.ledger, defaults: defaults)
        return granted.intensity
    }

    /// Game-facing twin of `request`: same persisted purse, game tiers.
    /// GameEndCelebration calls this instead of keeping its own ledger —
    /// a match-win epic and a level-up epic now truly spend from ONE
    /// budget at runtime, exactly as the rules layer always promised.
    @discardableResult
    static func requestGame(_ event: GameCeremonyEvent, now: Date = Date(),
                            defaults: UserDefaults = .standard) -> GameCeremonyTier {
        let granted = GameDelightRules.grant(event: event,
                                             ledger: load(defaults: defaults),
                                             now: now)
        save(granted.ledger, defaults: defaults)
        return granted.tier
    }
}
