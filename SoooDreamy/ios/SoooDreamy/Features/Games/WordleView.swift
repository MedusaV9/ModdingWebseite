import SwiftUI
import Combine

// MARK: - Daily word logic + persistence

/// Tile / key evaluation. Raw values are ordered so a key on the on-screen
/// keyboard always shows its best-known state (correct beats present beats
/// absent).
enum WordleMark: Int {
    case absent = 0
    case present = 1
    case correct = 2
}

/// Pure logic + storage for the daily Liebes-Wordle so the hub card and the
/// game screen read exactly the same state.
enum WordleDaily {
    static let maxGuesses = 6
    static let wordLength = 5

    static func words(lang: String) -> [String] {
        lang == "de" ? ContentPack.wordleWordsDE : ContentPack.wordleWordsEN
    }

    /// Allowed-guess dictionary (the solution pool doubles as dictionary).
    static func dictionary(lang: String) -> Set<String> {
        lang == "de" ? dictionaryDE : dictionaryEN
    }

    private static let dictionaryDE = Set(ContentPack.wordleWordsDE)
    private static let dictionaryEN = Set(ContentPack.wordleWordsEN)

    /// Deterministic daily solution — same DJB2-style hash as
    /// `ContentPack.dailyQuestion(dateKey:coupleId:)`, so both partners
    /// derive the identical word for the day.
    static func solution(coupleId: String, dateKey: String, lang: String) -> String {
        let list = words(lang: lang)
        guard !list.isEmpty else { return lang == "de" ? "LIEBE" : "HEART" }
        let seed = (dateKey + coupleId).unicodeScalars.reduce(5381 as UInt64) {
            ($0 << 5) &+ $0 &+ UInt64($1.value)
        }
        return list[Int(seed % UInt64(list.count))]
    }

    // MARK: Scoring (standard Wordle two-pass algorithm)

    /// Pass 1 marks exact-position greens and counts the solution's leftover
    /// letters; pass 2 hands out yellows limited by those remaining counts,
    /// so duplicate letters are never over-rewarded.
    static func score(guess: String, solution: String) -> [WordleMark] {
        let guessChars = Array(guess)
        let solutionChars = Array(solution)
        var marks = [WordleMark](repeating: .absent, count: guessChars.count)
        guard guessChars.count == solutionChars.count else { return marks }
        var remaining: [Character: Int] = [:]
        for index in 0..<guessChars.count {
            if guessChars[index] == solutionChars[index] {
                marks[index] = .correct
            } else {
                remaining[solutionChars[index], default: 0] += 1
            }
        }
        for index in 0..<guessChars.count where marks[index] != .correct {
            let letter = guessChars[index]
            if let available = remaining[letter], available > 0 {
                marks[index] = .present
                remaining[letter] = available - 1
            }
        }
        return marks
    }

    /// Outcome of a completed duel day — the verdict rule of the daily duel:
    /// a win beats a loss, two wins are ranked by row count. Equal wins and
    /// shared defeats both land on `.tie` (that's how the record counts them).
    enum DuelOutcome {
        case meWin, partnerWin, tie
    }

    static func duelOutcome(mine: WordleResult, partner: WordleResult) -> DuelOutcome {
        if mine.win && !partner.win { return .meWin }
        if partner.win && !mine.win { return .partnerWin }
        if mine.win && partner.win {
            if mine.rows < partner.rows { return .meWin }
            if mine.rows > partner.rows { return .partnerWin }
        }
        return .tie
    }

    /// Spoiler-free 🟩🟨⬛ rows for a full board — used for chat sharing and
    /// as the duel `grid` payload (also for boards restored from storage).
    static func emojiGrid(guesses: [String], solution: String) -> String {
        guesses.map { guess in
            score(guess: guess, solution: solution).map { mark -> String in
                switch mark {
                case .correct: return "🟩"
                case .present: return "🟨"
                case .absent: return "⬛"
                }
            }
            .joined()
        }
        .joined(separator: "\n")
    }

    // MARK: Board persistence (per couple + day + language)

    static func storageKey(coupleId: String, dateKey: String, lang: String) -> String {
        "sooodreamy.wordle.\(coupleId).\(dateKey).\(lang)"
    }

    static func loadGuesses(coupleId: String, dateKey: String, lang: String) -> [String] {
        let key = storageKey(coupleId: coupleId, dateKey: dateKey, lang: lang)
        return UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func saveGuesses(_ guesses: [String], coupleId: String, dateKey: String, lang: String) {
        let key = storageKey(coupleId: coupleId, dateKey: dateKey, lang: lang)
        UserDefaults.standard.set(guesses, forKey: key)
    }

    /// True once today's puzzle is solved or all six guesses are used —
    /// the hub card reads this for its ✓ overlay.
    static func isFinished(coupleId: String, dateKey: String, lang: String) -> Bool {
        let guesses = loadGuesses(coupleId: coupleId, dateKey: dateKey, lang: lang)
        guard !guesses.isEmpty else { return false }
        if guesses.count >= maxGuesses { return true }
        return guesses.last == solution(coupleId: coupleId, dateKey: dateKey, lang: lang)
    }

    // MARK: Duel submission flag (server is idempotent; this just avoids re-sends)

    private static func submittedKey(coupleId: String, dateKey: String, lang: String) -> String {
        "sooodreamy.wordle.submitted.\(coupleId).\(dateKey).\(lang)"
    }

    static func isSubmitted(coupleId: String, dateKey: String, lang: String) -> Bool {
        UserDefaults.standard.bool(forKey: submittedKey(coupleId: coupleId, dateKey: dateKey, lang: lang))
    }

    static func markSubmitted(coupleId: String, dateKey: String, lang: String) {
        UserDefaults.standard.set(true, forKey: submittedKey(coupleId: coupleId, dateKey: dateKey, lang: lang))
    }

    // MARK: Simple local stats (no streaks, just counters)

    private static let playedKey = "sooodreamy.wordle.stats.played"
    private static let wonKey = "sooodreamy.wordle.stats.won"

    static var gamesPlayed: Int {
        UserDefaults.standard.integer(forKey: playedKey)
    }

    static var gamesWon: Int {
        UserDefaults.standard.integer(forKey: wonKey)
    }

    static func recordFinish(won: Bool) {
        UserDefaults.standard.set(gamesPlayed + 1, forKey: playedKey)
        if won {
            UserDefaults.standard.set(gamesWon + 1, forKey: wonKey)
        }
    }
}

// MARK: - Screen

struct WordleView: View {
    @Environment(AppState.self) private var appState

    @State private var guesses: [String] = []
    @State private var currentGuess = ""
    @State private var flippedRows: Set<Int> = []
    @State private var shakePhase: CGFloat = 0
    @State private var endVisible = false
    @State private var celebrate = false
    @State private var bounceRow: Int?
    @State private var sendingShare = false
    @State private var shared = false
    @State private var restored = false
    @State private var dateKey = SharedDates.todayKey()
    @State private var day: WordleDayResponse?
    @State private var submitFailed = false

    // MARK: Derived state

    private var lang: String { L10n.lang }

    private var coupleId: String { appState.couple?.id ?? "" }

    private var solution: String {
        WordleDaily.solution(coupleId: coupleId, dateKey: dateKey, lang: lang)
    }

    private var didWin: Bool {
        guesses.last == solution
    }

    private var finished: Bool {
        didWin || guesses.count >= WordleDaily.maxGuesses
    }

    /// Best-known state per keyboard letter across all submitted guesses.
    private var keyMarks: [String: WordleMark] {
        var marks: [String: WordleMark] = [:]
        for guess in guesses {
            let rowMarks = WordleDaily.score(guess: guess, solution: solution)
            for (index, character) in guess.enumerated() {
                let key = String(character)
                let mark = rowMarks[index]
                if let existing = marks[key], existing.rawValue >= mark.rawValue { continue }
                marks[key] = mark
            }
        }
        return marks
    }

    // MARK: Body

    var body: some View {
        ZStack {
            DreamyBackground()
            ScrollView {
                VStack(spacing: 16) {
                    headerHint
                    grid
                    if finished && endVisible {
                        endCard
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    } else {
                        keyboard
                    }
                    duelSection
                    recordLink
                }
                .padding(16)
                .padding(.bottom, 12)
            }
            if celebrate {
                FloatingHeartsView(emojis: ["💘", "💚", "💛", "✨", "💞"])
                    .allowsHitTesting(false)
            }
        }
        .navigationTitle(L10n.t("games.wordle.title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            restore()
            // A board finished late yesterday may still be waiting for its submit.
            submitOrphanedYesterday()
            // Retries a today-submit that failed earlier.
            submitResultIfNeeded()
            loadDay()
        }
        .onReceive(NotificationCenter.default.publisher(for: .serverEvent)) { note in
            guard let event = note.object as? ServerEvent else { return }
            receiveDuelEvent(event)
        }
    }

    private func restore() {
        guard !restored else { return }
        restored = true
        dateKey = SharedDates.todayKey()
        guesses = WordleDaily.loadGuesses(coupleId: coupleId, dateKey: dateKey, lang: lang)
        flippedRows = Set(0..<guesses.count)
        endVisible = finished
    }

    // MARK: Header

    @ViewBuilder
    private var headerHint: some View {
        if !finished, appState.partner != nil {
            HStack(spacing: 8) {
                Text("💘")
                Text(L10n.t("games.wordle.sameWordHint", ["name": appState.partnerName]))
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(padding: 12)
        }
    }

    // MARK: Grid

    private var grid: some View {
        VStack(spacing: 6) {
            ForEach(0..<WordleDaily.maxGuesses, id: \.self) { row in
                gridRow(row)
            }
        }
    }

    @ViewBuilder
    private func gridRow(_ row: Int) -> some View {
        if row < guesses.count {
            submittedRow(row)
        } else if row == guesses.count && !finished {
            activeRow
        } else {
            placeholderRow
        }
    }

    private func submittedRow(_ row: Int) -> some View {
        let letters = Array(guesses[row])
        let marks = WordleDaily.score(guess: guesses[row], solution: solution)
        let revealed = flippedRows.contains(row)
        return HStack(spacing: 6) {
            ForEach(0..<WordleDaily.wordLength, id: \.self) { column in
                WordleTileView(letter: String(letters[column]),
                               mark: marks[column],
                               revealed: revealed,
                               delay: Double(column) * 0.18)
            }
        }
        .scaleEffect(bounceRow == row ? 1.08 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.35), value: bounceRow)
    }

    private var activeRow: some View {
        let letters = Array(currentGuess)
        return HStack(spacing: 6) {
            ForEach(0..<WordleDaily.wordLength, id: \.self) { column in
                WordleTileView(letter: column < letters.count ? String(letters[column]) : "",
                               mark: nil,
                               revealed: false,
                               delay: 0)
            }
        }
        .modifier(WordleShakeEffect(animatableData: shakePhase))
    }

    private var placeholderRow: some View {
        HStack(spacing: 6) {
            ForEach(0..<WordleDaily.wordLength, id: \.self) { _ in
                WordleTileView(letter: "", mark: nil, revealed: false, delay: 0)
            }
        }
    }

    // MARK: Keyboard

    private var keyboardRows: [[String]] {
        if lang == "de" {
            return [["Q", "W", "E", "R", "T", "Z", "U", "I", "O", "P"],
                    ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
                    ["Y", "X", "C", "V", "B", "N", "M"]]
        }
        return [["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
                ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
                ["Z", "X", "C", "V", "B", "N", "M"]]
    }

    private var keyboard: some View {
        VStack(spacing: 7) {
            keyRow(keyboardRows[0])
            keyRow(keyboardRows[1])
                .padding(.horizontal, 16)
            HStack(spacing: 5) {
                enterKey
                keyRow(keyboardRows[2])
                backspaceKey
            }
        }
        .padding(.top, 6)
    }

    private func keyRow(_ letters: [String]) -> some View {
        HStack(spacing: 5) {
            ForEach(letters, id: \.self) { letter in
                letterKey(letter)
            }
        }
    }

    private func letterKey(_ letter: String) -> some View {
        let mark = keyMarks[letter]
        return Button {
            tapLetter(letter)
        } label: {
            Text(letter)
                .font(.system(.callout, design: .rounded).weight(.bold))
                .foregroundStyle(keyTextColor(mark))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(keyFillColor(mark))
                )
        }
        .buttonStyle(.plain)
    }

    private var enterKey: some View {
        Button(action: submitGuess) {
            Image(systemName: "return")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 46, height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.pink.opacity(0.45))
                )
        }
        .buttonStyle(.plain)
    }

    private var backspaceKey: some View {
        Button(action: tapBackspace) {
            Image(systemName: "delete.left")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 46, height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }

    private func keyFillColor(_ mark: WordleMark?) -> Color {
        switch mark {
        case .correct: return Theme.mint
        case .present: return Theme.gold
        case .absent: return Color.black.opacity(0.4)
        case nil: return Color.white.opacity(0.12)
        }
    }

    private func keyTextColor(_ mark: WordleMark?) -> Color {
        switch mark {
        case .correct, .present: return Theme.bgTop
        case .absent: return Color.white.opacity(0.4)
        case nil: return Theme.textPrimary
        }
    }

    // MARK: Input

    private func tapLetter(_ letter: String) {
        guard !finished, currentGuess.count < WordleDaily.wordLength else { return }
        currentGuess += letter
        Haptics.shared.tap()
    }

    private func tapBackspace() {
        guard !finished, !currentGuess.isEmpty else { return }
        currentGuess.removeLast()
        Haptics.shared.tap()
    }

    private func submitGuess() {
        guard !finished else { return }
        guard currentGuess.count == WordleDaily.wordLength else {
            rejectGuess(messageKey: "games.wordle.tooShort")
            return
        }
        guard WordleDaily.dictionary(lang: lang).contains(currentGuess) else {
            rejectGuess(messageKey: "games.wordle.notInList")
            return
        }
        let guess = currentGuess
        currentGuess = ""
        let row = guesses.count
        guesses.append(guess)
        WordleDaily.saveGuesses(guesses, coupleId: coupleId, dateKey: dateKey, lang: lang)
        flippedRows.insert(row)
        Haptics.shared.tap()
        if guess == solution {
            finishGame(won: true, row: row)
        } else if guesses.count >= WordleDaily.maxGuesses {
            finishGame(won: false, row: row)
        } else {
            SoundEngine.shared.play(.pop)
        }
    }

    private func rejectGuess(messageKey: String) {
        Haptics.shared.warning()
        appState.showToast(L10n.t(messageKey), style: .info)
        withAnimation(.linear(duration: 0.45)) {
            shakePhase += 1
        }
    }

    private func finishGame(won: Bool, row: Int) {
        WordleDaily.recordFinish(won: won)
        submitResultIfNeeded()
        Task {
            // Let the row finish its flip reveal first.
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            withAnimation(.spring(response: 0.4)) {
                endVisible = true
            }
            if won {
                celebrate = true
                SoundEngine.shared.play(.tada)
                Haptics.shared.success()
                bounceRow = row
                try? await Task.sleep(nanoseconds: 700_000_000)
                bounceRow = nil
                try? await Task.sleep(nanoseconds: 3_800_000_000)
                withAnimation(.easeOut(duration: 0.6)) {
                    celebrate = false
                }
            } else {
                SoundEngine.shared.play(.chime)
            }
        }
    }

    // MARK: End card

    private var endCard: some View {
        VStack(spacing: 12) {
            Text(didWin ? "💘" : "🫂")
                .font(.system(size: 48))
            Text(didWin ? praiseText : L10n.t("games.wordle.lossTitle"))
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(Theme.textPrimary)
            if !didWin {
                solutionReveal
                Text(L10n.t("games.wordle.lossBody"))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(statsLine)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            shareButton
            Text(L10n.t("games.wordle.newWord"))
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .glassCard(padding: 20)
    }

    private var praiseText: String {
        L10n.t("games.wordle.praise\(min(max(guesses.count, 1), 6))")
    }

    private var solutionReveal: some View {
        VStack(spacing: 4) {
            Text(L10n.t("games.wordle.solutionLabel"))
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            Text(solution)
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .foregroundStyle(Theme.gold)
                .kerning(4)
        }
        .padding(.vertical, 4)
    }

    private var statsLine: String {
        L10n.t("games.wordle.stats", ["played": String(WordleDaily.gamesPlayed),
                                      "won": String(WordleDaily.gamesWon)])
    }

    // MARK: Share to chat

    private var shareButton: some View {
        Button(action: shareToChat) {
            HStack(spacing: 8) {
                if sendingShare {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: shared ? "checkmark" : "paperplane.fill")
                    Text(shared
                         ? L10n.t("games.wordle.sharedDone")
                         : L10n.t("games.wordle.share", ["name": appState.partnerName]))
                }
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(sendingShare || shared || appState.api == nil)
    }

    /// Spoiler-free 🟩🟨⬛ rows — sent to chat and submitted as the duel grid.
    private var emojiGrid: String {
        WordleDaily.emojiGrid(guesses: guesses, solution: solution)
    }

    /// Classic emoji summary — header + result grid for the chat.
    private var shareText: String {
        let scoreText = didWin ? "\(guesses.count)/6" : "X/6"
        let header = L10n.t("games.wordle.shareTitle",
                            ["date": displayDate, "score": scoreText])
        return header + "\n" + emojiGrid
    }

    private var displayDate: String {
        let parts = dateKey.split(separator: "-")
        guard parts.count == 3 else { return dateKey }
        if lang == "de" {
            return "\(parts[2]).\(parts[1])."
        }
        return "\(parts[1])/\(parts[2])"
    }

    private func shareToChat() {
        guard let api = appState.api, !sendingShare else { return }
        let text = shareText
        sendingShare = true
        Task {
            do {
                _ = try await api.sendMessage(type: .text, text: text)
                shared = true
                SoundEngine.shared.play(.chime)
                Haptics.shared.success()
                appState.showToast(L10n.t("games.wordle.shared", ["name": appState.partnerName]),
                                   style: .love)
            } catch {
                appState.handleAPIError(error)
            }
            sendingShare = false
        }
    }

    // MARK: Duel networking

    private func loadDay() {
        guard let api = appState.api else { return }
        let requestedDateKey = dateKey
        let requestedLang = lang
        Task {
            guard let response = try? await api.wordleDay(dateKey: requestedDateKey,
                                                          lang: requestedLang) else { return }
            applyDay(response)
        }
    }

    /// Single choke point for `day` updates: drops responses for other
    /// days/languages and never lets a stale fetch regress a state that
    /// already knows my own result (e.g. a slow GET finishing after the
    /// submit round-trip already delivered `mine`).
    @discardableResult
    private func applyDay(_ response: WordleDayResponse) -> Bool {
        guard response.dateKey == dateKey else { return false }
        if let responseLang = response.lang, responseLang != lang { return false }
        if day?.mine != nil && response.mine == nil { return false }
        day = response
        return true
    }

    /// Fire-and-forget submission of the finished board for today. On failure
    /// the local flag stays unset (next `onAppear` or the retry button tries
    /// again); a `bad_datekey` rejection is terminal, so we mark it submitted
    /// to stop retrying. The server is idempotent — a duplicate submit just
    /// echoes the stored result.
    private func submitResultIfNeeded() {
        guard finished, !guesses.isEmpty else { return }
        guard let api = appState.api else { return }
        guard !WordleDaily.isSubmitted(coupleId: coupleId, dateKey: dateKey, lang: lang) else { return }
        submitFailed = false
        let submittedDateKey = dateKey
        let rows = guesses.count
        let win = didWin
        let grid = emojiGrid
        let submittedLang = lang
        let submittedCoupleId = coupleId
        Task {
            do {
                let response = try await api.submitWordle(dateKey: submittedDateKey,
                                                          rows: rows,
                                                          win: win,
                                                          grid: grid,
                                                          lang: submittedLang)
                WordleDaily.markSubmitted(coupleId: submittedCoupleId,
                                          dateKey: submittedDateKey,
                                          lang: submittedLang)
                applyDay(response)
            } catch {
                if Self.isBadDateKey(error) {
                    WordleDaily.markSubmitted(coupleId: submittedCoupleId,
                                              dateKey: submittedDateKey,
                                              lang: submittedLang)
                } else {
                    submitFailed = true
                }
            }
        }
    }

    /// A board finished late yesterday but never submitted (app killed,
    /// offline, …) would be orphaned because `restore()` targets today.
    /// Checks yesterday's storage for both languages and submits with THAT
    /// dateKey — the server accepts ±1 day.
    private func submitOrphanedYesterday() {
        guard let api = appState.api else { return }
        guard let yesterday = yesterdayKey() else { return }
        for boardLang in ["de", "en"] {
            submitStoredBoard(api: api, dateKey: yesterday, lang: boardLang)
        }
    }

    private func submitStoredBoard(api: API, dateKey boardDateKey: String, lang boardLang: String) {
        let boardCoupleId = coupleId
        guard !WordleDaily.isSubmitted(coupleId: boardCoupleId,
                                       dateKey: boardDateKey,
                                       lang: boardLang) else { return }
        let boardGuesses = WordleDaily.loadGuesses(coupleId: boardCoupleId,
                                                   dateKey: boardDateKey,
                                                   lang: boardLang)
        guard !boardGuesses.isEmpty else { return }
        let boardSolution = WordleDaily.solution(coupleId: boardCoupleId,
                                                 dateKey: boardDateKey,
                                                 lang: boardLang)
        let won = boardGuesses.last == boardSolution
        guard won || boardGuesses.count >= WordleDaily.maxGuesses else { return }
        let grid = WordleDaily.emojiGrid(guesses: boardGuesses, solution: boardSolution)
        Task {
            do {
                _ = try await api.submitWordle(dateKey: boardDateKey,
                                               rows: boardGuesses.count,
                                               win: won,
                                               grid: grid,
                                               lang: boardLang)
                WordleDaily.markSubmitted(coupleId: boardCoupleId,
                                          dateKey: boardDateKey,
                                          lang: boardLang)
            } catch {
                // Too old by now — stop retrying forever. Other errors stay
                // unmarked and get another chance on the next appear.
                if Self.isBadDateKey(error) {
                    WordleDaily.markSubmitted(coupleId: boardCoupleId,
                                              dateKey: boardDateKey,
                                              lang: boardLang)
                }
            }
        }
    }

    private func yesterdayKey() -> String? {
        guard let date = SharedDates.calendar.date(byAdding: .day, value: -1, to: Date()) else {
            return nil
        }
        return SharedDates.todayKey(date)
    }

    private static func isBadDateKey(_ error: Error) -> Bool {
        if case APIError.http(_, let code, _) = error, code == "bad_datekey" {
            return true
        }
        return false
    }

    private func receiveDuelEvent(_ event: ServerEvent) {
        guard event.type == .wordleResult,
              let response = event.decode(WordleDayResponse.self) else { return }
        let partnerWasFinished = day?.partnerFinished ?? false
        guard applyDay(response) else { return }
        if !partnerWasFinished && response.partnerFinished {
            SoundEngine.shared.play(.chime)
            Haptics.shared.tap()
        }
    }

    // MARK: Duel section

    @ViewBuilder
    private var duelSection: some View {
        if appState.partner != nil, let day,
           day.dateKey == dateKey, (day.lang ?? lang) == lang {
            if let mine = day.mine, let partnerResult = day.partner {
                duelCard(mine: mine, partner: partnerResult)
            } else if !day.partnerFinished {
                stillSolvingCard
            } else if !finished {
                teaserCard
            } else if submitFailed {
                // My submit failed — offer a retry instead of an eternal spinner.
                retryCard
            } else {
                // I just finished, partner too — my submit round-trip is in flight.
                revealingCard
            }
        }
    }

    /// Small always-available entry into the running duel record —
    /// `WordleView` sits in PlayHub's NavigationStack, so a plain link pushes.
    private var recordLink: some View {
        NavigationLink {
            WordleRecordView()
        } label: {
            HStack(spacing: 8) {
                Text("📊")
                    .font(.system(size: 16))
                Text(L10n.t("games.wordle.record.button"))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .glassCard(padding: 12)
        }
        .buttonStyle(.plain)
    }

    private var retryCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Theme.gold)
            Text(L10n.t("games.wordle.duel.sendFailed"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: submitResultIfNeeded) {
                Text(L10n.t("games.wordle.duel.retry"))
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.bgTop)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
                    .background(Capsule().fill(Theme.gold))
            }
            .buttonStyle(.plain)
        }
        .glassCard(padding: 12)
    }

    private var stillSolvingCard: some View {
        HStack(spacing: 8) {
            Text("🥊")
                .font(.system(size: 20))
            Text(L10n.t("games.wordle.duel.stillSolving", ["name": appState.partnerName]))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            WordleDuelDots()
            Spacer(minLength: 0)
        }
        .glassCard(padding: 12)
    }

    private var teaserCard: some View {
        HStack(spacing: 8) {
            Text("🥊")
                .font(.system(size: 20))
            Text(L10n.t("games.wordle.duel.teaser", ["name": appState.partnerName]))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .glassCard(padding: 12)
    }

    private var revealingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(Theme.pink)
            Text(L10n.t("games.wordle.duel.revealing"))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
        .glassCard(padding: 12)
    }

    private func duelCard(mine: WordleResult, partner: WordleResult) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Text("🥊")
                Text(L10n.t("games.wordle.duel.title"))
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            HStack(alignment: .top, spacing: 14) {
                duelColumn(name: appState.me?.name ?? L10n.t("common.you"), result: mine)
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 1)
                duelColumn(name: appState.partnerName, result: partner)
            }
            Text(verdictText(mine: mine, partner: partner))
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.gold)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .glassCard(padding: 16)
    }

    private func duelColumn(name: String, result: WordleResult) -> some View {
        VStack(spacing: 6) {
            Text(name)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            emojiGridView(result.grid)
            Text(result.win ? "\(result.rows)/6" : "X/6")
                .font(.system(.caption, design: .rounded).weight(.heavy))
                .foregroundStyle(result.win ? Theme.mint : Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func emojiGridView(_ grid: String) -> some View {
        VStack(spacing: 2) {
            ForEach(Array(grid.split(separator: "\n").enumerated()), id: \.offset) { _, line in
                Text(String(line))
                    .font(.system(size: 13))
                    .kerning(1)
            }
        }
    }

    /// Duel verdict: a win always beats a loss; two wins are ranked by row
    /// count (fewer wins, equal is a tie); two losses share the blame.
    private func verdictText(mine: WordleResult, partner: WordleResult) -> String {
        if mine.win && !partner.win {
            return L10n.t("games.wordle.duel.iWin")
        }
        if partner.win && !mine.win {
            return L10n.t("games.wordle.duel.partnerWins", ["name": appState.partnerName])
        }
        if mine.win && partner.win {
            if mine.rows < partner.rows {
                return L10n.t("games.wordle.duel.iWin")
            }
            if mine.rows > partner.rows {
                return L10n.t("games.wordle.duel.partnerWins", ["name": appState.partnerName])
            }
            return L10n.t("games.wordle.duel.tie")
        }
        return L10n.t("games.wordle.duel.bothLost")
    }
}

// MARK: - Subtle "…" typing dots for the waiting state

private struct WordleDuelDots: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Theme.textSecondary)
                    .frame(width: 4, height: 4)
                    .opacity(animating ? 1 : 0.25)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.2), value: animating)
            }
        }
        .onAppear {
            animating = true
        }
    }
}

// MARK: - Tile

private struct WordleTileView: View {
    let letter: String
    let mark: WordleMark?
    let revealed: Bool
    let delay: Double

    private static let size: CGFloat = 50

    var body: some View {
        ZStack {
            unrevealedFace
                .rotation3DEffect(.degrees(revealed ? 180 : 0),
                                  axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                .opacity(revealed ? 0 : 1)
            revealedFace
                .rotation3DEffect(.degrees(revealed ? 0 : -180),
                                  axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                .opacity(revealed ? 1 : 0)
        }
        .frame(width: Self.size, height: Self.size)
        .animation(.easeInOut(duration: 0.5).delay(delay), value: revealed)
    }

    private var unrevealedFace: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(letter.isEmpty ? 0.04 : 0.1))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(letter.isEmpty ? 0.12 : 0.32),
                                  lineWidth: 1.5)
            )
            .overlay(
                Text(letter)
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(Theme.textPrimary)
            )
    }

    private var revealedFace: some View {
        let resolvedMark = mark ?? .absent
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(fillColor(resolvedMark))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(borderColor(resolvedMark), lineWidth: 1.5)
            )
            .overlay(
                Text(letter)
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(letterColor(resolvedMark))
            )
            .overlay(alignment: .topTrailing) {
                // Colorblind-friendly secondary cue on top of the colors.
                if let icon = cueIcon(resolvedMark) {
                    Image(systemName: icon)
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(letterColor(resolvedMark).opacity(0.75))
                        .padding(4)
                }
            }
    }

    private func fillColor(_ mark: WordleMark) -> Color {
        switch mark {
        case .correct: return Theme.mint
        case .present: return Theme.gold.opacity(0.9)
        case .absent: return Color.black.opacity(0.38)
        }
    }

    private func borderColor(_ mark: WordleMark) -> Color {
        switch mark {
        case .correct: return Theme.mint
        case .present: return Color.white.opacity(0.55)
        case .absent: return Color.white.opacity(0.08)
        }
    }

    private func letterColor(_ mark: WordleMark) -> Color {
        switch mark {
        case .correct, .present: return Theme.bgTop
        case .absent: return Color.white.opacity(0.55)
        }
    }

    private func cueIcon(_ mark: WordleMark) -> String? {
        switch mark {
        case .correct: return "checkmark"
        case .present: return "arrow.left.arrow.right"
        case .absent: return nil
        }
    }
}

// MARK: - Row shake (invalid guess)

private struct WordleShakeEffect: GeometryEffect {
    var travel: CGFloat = 7
    var shakes: Double = 4
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let angle = Double(animatableData) * .pi * shakes * 2
        let offset = travel * CGFloat(sin(angle))
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}
