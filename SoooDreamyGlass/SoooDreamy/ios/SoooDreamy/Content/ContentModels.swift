import Foundation

/// A localized string (German / English). The app is fully bilingual.
/// Codable because the wire now carries LText-shaped `{de, en}` pairs for
/// the pinned daily question (entry `questionText`, snapshot `dailyQuestion`,
/// 409 `daily_question_mismatch` details — Schlussrunde 5).
struct LText: Hashable, Codable {
    let de: String
    let en: String

    /// Resolve for the given language code ("de" or "en").
    func resolved(_ lang: String) -> String { lang == "de" ? de : en }

    /// Replace the `{partner}` placeholder with the partner's name.
    func filled(partner: String, lang: String) -> String {
        resolved(lang).replacingOccurrences(of: "{partner}", with: partner)
    }
}

/// Editorial depth of a daily question. The cycle uses it to keep the mix
/// gentle: light check-ins carry the everyday, close ones build intimacy,
/// deep ones want a calm evening — and never land three days in a row
/// (see `ContentPack.dailyQuestionCycle`).
enum QuestionDepth: String, Hashable {
    /// leicht — everyday, playful, answerable in one breath.
    case light
    /// nah — relational, warm, a little self-disclosure.
    case close
    /// tief — vulnerable, big feelings, needs time and softness.
    case deep
}

/// How much battery a quest or date idea asks for. `quick` fits into twenty
/// tired minutes; `normal` wants a real block of time and some energy.
enum ContentEnergy: String, Hashable {
    case quick
    case normal
}

/// Question of the day — both partners answer, answers reveal once both answered.
struct DailyQuestion: Identifiable, Hashable {
    let id: Int
    let text: LText
    /// Defaults to `.light` so out-of-pack constructions stay valid; the
    /// bundled pool tags every question explicitly.
    var depth: QuestionDepth = .light
}

/// "Who knows who better?" quiz question about the partner.
/// Texts use the `{partner}` placeholder, e.g. "Was ist {partner}s Lieblingsessen?"
struct QuizQuestion: Identifiable, Hashable {
    let id: Int
    let text: LText
}

/// A pair of options — used by both "This or That" and "Would You Rather".
struct ChoicePair: Identifiable, Hashable {
    let id: Int
    let a: LText
    let b: LText
}

/// Truth-or-Dare card. `spice`: 1 = sweet, 2 = flirty, 3 = spicy (tasteful).
struct TruthOrDareItem: Identifiable, Hashable {
    let id: Int
    let isDare: Bool
    let spice: Int
    let text: LText
}

/// The classic "36 questions to fall in love" (Arthur Aron), in 3 sets of 12.
struct Question36: Identifiable, Hashable {
    let id: Int
    let set: Int
    let text: LText
}

/// Emoji riddle: guess the movie/song/place/… from an emoji sequence.
/// `category`: "movie" | "song" | "place" | "food" | "couple" | "activity".
struct EmojiRiddle: Identifiable, Hashable {
    let id: Int
    let emojis: String
    let answer: LText
    let category: String
}

/// Speed-duel trivia question (Liebes-Quiz-Duell) — exactly one correct
/// option; whoever buzzes the right answer first scores double.
struct DuelQuestion: Identifiable, Hashable {
    let id: Int
    let text: LText
    let options: [LText]
    let correct: Int
}

/// Date idea for the generator. `budget`: 0 = free … 3 = splurge.
struct DateIdea: Identifiable, Hashable {
    let id: Int
    let emoji: String
    let title: LText
    let details: LText
    let indoor: Bool
    let budget: Int
    let tags: [String]
    /// `.quick` marks ideas that work in ≤ 20 exhausted minutes; everything
    /// else defaults to `.normal`.
    var energy: ContentEnergy = .normal
}

/// Deterministic, repeat-free content rotation shared by the daily question
/// and the daily quests.
///
/// The old draw — `hash(dateKey + coupleId) % poolSize` — sampled WITH
/// replacement: the first repeat arrived after ~20 days and a whole year of
/// questions only ever surfaced ~70 % of the pool. The cycle below walks a
/// pair-stable permutation instead, so every card appears exactly once per
/// pool pass before anything repeats.
///
/// Growth stability: an item's sort key depends only on (couple, item index),
/// never on the pool size. Growing the pool therefore weaves the new cards
/// into the cycle WITHOUT reordering the existing ones relative to each
/// other — no reshuffle, no sudden replays of recently seen cards.
///
/// Migration: leaving the modulo draw moves "today's" card once at rollout.
/// That one-time switch is unavoidable in this very release anyway — the old
/// formula changes its result whenever the pool size changes, and this
/// release grows every rotating pool. History is safe: answered days are
/// pinned by their stored question id (server pins it with the first
/// answer), and ids are never renumbered.
enum ContentCycle {
    /// djb2 over unicode scalars — the seed family the rest of the app uses.
    static func seed(_ text: String) -> UInt64 {
        text.unicodeScalars.reduce(5381 as UInt64) { ($0 << 5) &+ $0 &+ UInt64($1.value) }
    }

    /// SplitMix64 finalizer — turns (couple seed, index) into an
    /// independent-looking, stable sort key.
    private static func mix(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Day number of a "YYYY-MM-DD" key: days since 1970-01-01 as pure
    /// Gregorian integer math — no Calendar, no timezone, identical on both
    /// phones. Returns nil for malformed keys.
    static func dayNumber(of dateKey: String) -> Int? {
        let parts = dateKey.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        let shifted = month <= 2 ? year - 1 : year
        let era = (shifted >= 0 ? shifted : shifted - 399) / 400
        let yearOfEra = shifted - era * 400
        let dayOfYear = (153 * (month <= 2 ? month + 9 : month - 3) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// The couple's stable permutation of `0..<poolSize`: indexes sorted by
    /// their per-couple key. Appending items to the pool preserves the
    /// relative order of everything that was already there.
    static func order(poolSize: Int, coupleKey: String) -> [Int] {
        guard poolSize > 0 else { return [] }
        let base = seed(coupleKey)
        return (0..<poolSize).sorted { left, right in
            let a = mix(base ^ (UInt64(left) &* 0x2545_F491_4F6C_DD1D))
            let b = mix(base ^ (UInt64(right) &* 0x2545_F491_4F6C_DD1D))
            return a == b ? left < right : a < b
        }
    }
}

/// Persisted buffer of the most recently served daily-question ids, one list
/// per couple. `day % cycle.count` jumps to a different cycle position
/// whenever the pool grows (and the depth guard may reorder around it), so a
/// release that adds questions could otherwise replay a just-seen card the
/// very next morning. The buffer remembers the last `window` served
/// (dayNumber, questionId) pairs; `ContentPack.dailyQuestion` skips past any
/// candidate served within the window and records what it resolved.
enum DailyQuestionRecents {
    /// How many days back a served question blocks a replay.
    static let window = 30

    private static func storageKey(_ coupleId: String) -> String {
        "sooodreamy.dailyq.recent." + coupleId
    }

    /// Stored as ["<dayNumber>|<questionId>", …], newest last.
    static func load(coupleId: String) -> [(day: Int, id: Int)] {
        let raw = UserDefaults.standard.stringArray(forKey: storageKey(coupleId)) ?? []
        return raw.compactMap { entry in
            let parts = entry.split(separator: "|")
            guard parts.count == 2, let day = Int(parts[0]), let id = Int(parts[1]) else {
                return nil
            }
            return (day, id)
        }
    }

    /// Records a serve and trims the buffer to the newest `window` days.
    /// The first record for a day wins — later re-derivations (journal
    /// fallbacks for past dates) never overwrite what was actually shown.
    static func record(coupleId: String, day: Int, id: Int) {
        var entries = load(coupleId: coupleId)
        guard !entries.contains(where: { $0.day == day }) else { return }
        entries.append((day, id))
        entries.sort { $0.day < $1.day }
        if entries.count > window {
            entries.removeFirst(entries.count - window)
        }
        UserDefaults.standard.set(entries.map { "\($0.day)|\($0.id)" },
                                  forKey: storageKey(coupleId))
    }
}

/// Namespace for all bundled content packs.
/// The data lives in `Content/Data/*.swift` as extensions of this enum.
enum ContentPack {
    /// The couple's repeat-free question cycle with the depth guard applied:
    /// positions are pool indexes, one per day, wrapping after a full pass.
    static func dailyQuestionCycle(coupleId: String,
                                   pool: [DailyQuestion] = ContentPack.dailyQuestions) -> [Int] {
        var order = ContentCycle.order(poolSize: pool.count, coupleKey: "dailyq|" + coupleId)
        spreadDeepQuestions(&order, pool: pool)
        return order
    }

    /// Deterministic daily question for a given date & couple (same for both
    /// partners): the couple's cycle position for that day. Repeat-free for
    /// a full pool pass (410+ days), gently mixed by depth, and guarded
    /// against replays around pool-growth releases by the recents buffer.
    static func dailyQuestion(dateKey: String, coupleId: String) -> DailyQuestion {
        let recent = DailyQuestionRecents.load(coupleId: coupleId)
        let question = dailyQuestion(dateKey: dateKey, coupleId: coupleId,
                                     pool: ContentPack.dailyQuestions, recent: recent)
        if let day = ContentCycle.dayNumber(of: dateKey) {
            DailyQuestionRecents.record(coupleId: coupleId, day: day, id: question.id)
        }
        return question
    }

    /// Pair-authoritative variant for surfaces that hold a `DailyEntry`:
    /// the SERVER pins the day's question with the first answer
    /// (`DailyEntry.questionId`), and whenever an entry names a pool
    /// question, BOTH devices must show exactly it. The local cycle
    /// derivation is only a PROPOSAL while no entry exists — its recents
    /// buffer is device-local, so after a pool-growth release a fresh
    /// partner device and a long-lived one can derive DIFFERENT questions
    /// for the same day (documented eval repro: 140 vs 322). A pinned id
    /// the bundled pool does not know renders the server-stored
    /// `pinnedText` when one exists (Schlussrunde 5 — otherwise a
    /// mixed-version client shows a question the server refuses forever);
    /// only without both does it fall back to the derivation.
    static func dailyQuestion(dateKey: String, coupleId: String,
                              pinnedId: Int?, pinnedText: LText? = nil) -> DailyQuestion {
        if let pinned = pinnedDailyQuestion(pinnedId, pinnedText: pinnedText,
                                            pool: ContentPack.dailyQuestions) {
            // Record the pin like any serve, so the replay window blocks
            // the ACTUALLY shown question (first record per day wins).
            if let day = ContentCycle.dayNumber(of: dateKey) {
                DailyQuestionRecents.record(coupleId: coupleId, day: day, id: pinned.id)
            }
            return pinned
        }
        return dailyQuestion(dateKey: dateKey, coupleId: coupleId)
    }

    /// Pure rule behind the pin: a `questionId` the bundled pool knows
    /// resolves to the pool question (its text wins — the pool carries
    /// depth tags and copy fixes). An UNKNOWN id still resolves when the
    /// server stored the asked question's text with the pin (Schlussrunde
    /// 5): both devices then show the identical question even across
    /// content versions. Nil means "no pin" (no entry yet, entry without
    /// id from an old server, or an unknown id without stored text).
    static func pinnedDailyQuestion(_ pinnedId: Int?, pinnedText: LText? = nil,
                                    pool: [DailyQuestion]) -> DailyQuestion? {
        guard let pinnedId else { return nil }
        if let known = pool.first(where: { $0.id == pinnedId }) { return known }
        guard let pinnedText else { return nil }
        return DailyQuestion(id: pinnedId, text: pinnedText)
    }

    /// Pure resolver behind `dailyQuestion(dateKey:coupleId:)` — testable
    /// with a synthetic pool and recents list. `recent` holds the couple's
    /// last served (dayNumber, questionId) pairs: a candidate served within
    /// `DailyQuestionRecents.window` days BEFORE the requested day is
    /// skipped (walking forward through the cycle), so a pool-size change —
    /// which shifts `day % cycle.count` and may reshuffle the depth guard —
    /// never replays a question the couple has just seen. On ordinary days
    /// the natural candidate is fresh and no skip happens, keeping both
    /// partners' derivations identical.
    static func dailyQuestion(dateKey: String, coupleId: String,
                              pool: [DailyQuestion],
                              recent: [(day: Int, id: Int)]) -> DailyQuestion {
        let cycle = dailyQuestionCycle(coupleId: coupleId, pool: pool)
        let day = ContentCycle.dayNumber(of: dateKey)
            ?? Int(ContentCycle.seed(dateKey + coupleId) % UInt64(pool.count))
        let position = ((day % cycle.count) + cycle.count) % cycle.count
        let blocked = Set(recent.lazy
            .filter { $0.day < day && $0.day >= day - DailyQuestionRecents.window }
            .map(\.id))
        guard !blocked.isEmpty else { return pool[cycle[position]] }
        for offset in 0..<cycle.count {
            let candidate = pool[cycle[(position + offset) % cycle.count]]
            if !blocked.contains(candidate.id) {
                return candidate
            }
        }
        return pool[cycle[position]] // everything recent (tiny pool) — natural pick
    }

    /// Depth guard: wherever three deep questions would land on three
    /// consecutive days (cycle wrap included), the third one swaps forward
    /// to the next lighter card. Deterministic; a few sweeps settle all
    /// cascades because deep cards make up well under a third of the pool.
    private static func spreadDeepQuestions(_ order: inout [Int], pool: [DailyQuestion]) {
        let count = order.count
        guard count > 3 else { return }
        func isDeep(_ position: Int) -> Bool {
            pool[order[((position % count) + count) % count]].depth == .deep
        }
        for _ in 0..<4 {
            var changed = false
            for start in 0..<count {
                let third = (start + 2) % count
                guard isDeep(start), isDeep(start + 1), isDeep(third) else { continue }
                var offset = 1
                while offset < count - 2 {
                    let candidate = (third + offset) % count
                    if !isDeep(candidate) {
                        order.swapAt(third, candidate)
                        changed = true
                        break
                    }
                    offset += 1
                }
            }
            if !changed { break }
        }
    }
}

/// Pure deck derivation for the LIVE (two-phone) emoji riddle mode: both
/// clients turn the shared create payload (seed + category bitmask + round
/// count) into the IDENTICAL riddle deck. Kept UI-free here so the Linux
/// logic tests can pin the determinism the multiplayer protocol relies on.
enum EmojiRiddleDeck {
    /// Canonical category order — the payload's "cats" bitmask indexes into this.
    static let categories = ["movie", "song", "place", "food", "couple", "activity"]

    static func categoryMask(for selected: Set<String>) -> Int {
        var mask = 0
        for (index, category) in categories.enumerated() where selected.contains(category) {
            mask |= 1 << index
        }
        return mask
    }

    /// Bit i set = category i in play; 0 (or a mask matching nothing) = all.
    static func selectedCategories(mask: Int) -> Set<String> {
        guard mask > 0 else { return Set(categories) }
        var result: Set<String> = []
        for (index, category) in categories.enumerated() where mask & (1 << index) != 0 {
            result.insert(category)
        }
        return result.isEmpty ? Set(categories) : result
    }

    /// Deterministic session deck: filter by mask, seeded shuffle, cap at rounds.
    static func deck(seed: Int, mask: Int, rounds: Int) -> [EmojiRiddle] {
        let cats = selectedCategories(mask: mask)
        let pool = ContentPack.emojiRiddles.filter { cats.contains($0.category) }
        return Array(pool.seededShuffled(seed: seed).prefix(max(rounds, 1)))
    }
}
