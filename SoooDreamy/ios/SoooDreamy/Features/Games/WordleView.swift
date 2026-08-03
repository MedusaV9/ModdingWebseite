import SwiftUI

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
        .onAppear(perform: restore)
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

    /// Classic emoji summary — spoiler-free result grid for the chat.
    private var shareText: String {
        let scoreText = didWin ? "\(guesses.count)/6" : "X/6"
        let header = L10n.t("games.wordle.shareTitle",
                            ["date": displayDate, "score": scoreText])
        let rows = guesses.map { guess in
            WordleDaily.score(guess: guess, solution: solution).map { mark -> String in
                switch mark {
                case .correct: return "🟩"
                case .present: return "🟨"
                case .absent: return "⬛"
                }
            }
            .joined()
        }
        return ([header] + rows).joined(separator: "\n")
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
