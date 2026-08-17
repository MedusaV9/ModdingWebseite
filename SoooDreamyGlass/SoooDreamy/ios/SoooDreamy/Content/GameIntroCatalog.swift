import Foundation

// The intro wave for the W8C board games + the daily Liebes-Wordle: the
// tutorial library used to cover 19 of the hub's games — the six board
// duels and Wordle shipped without an intro. These seven follow the exact
// `GameTutorialCatalog` three-step pattern (rules → turn order → fair
// finish, plus a local practice prompt) and join the library through
// `GameTutorialCatalog.library`. Foundation-only; the Linux logic tests
// pin count, uniqueness and the three-step shape.

extension GameTutorialCatalog {
    /// Board-wave + Wordle intros — Dame leads with the capture duty and
    /// chain continuation, the two rules first games stumble over.
    static let boardWave: [GameTutorial] = [
        intro("dame", "🎲", "Dame", "Checkers",
              "Deine Steine ziehen diagonal vorwärts auf den dunklen Feldern.",
              "Your men step diagonally forward on the dark squares.",
              "Schlagen ist Pflicht — und eine Sprungkette führst du komplett zu Ende.",
              "Capturing is mandatory — and a jump chain must be finished completely.",
              "Die gegnerische Grundlinie krönt deinen Stein zur Dame.",
              "Reaching the far row crowns your man a king.",
              "Tippe einen leuchtenden Stein an und folge den markierten Zielen.",
              "Tap a highlighted piece and follow the marked targets."),
        intro("mancala", "🎲", "Mancala", "Mancala",
              "Leere eine eigene Mulde — die Steine wandern gegen den Uhrzeigersinn.",
              "Empty one of your pits — the stones travel counter-clockwise.",
              "Der letzte Stein im eigenen Speicher schenkt dir einen Extrazug.",
              "The last stone in your own store grants an extra turn.",
              "Landet er in einer leeren eigenen Mulde, fängst du die Mulde gegenüber.",
              "Landing in an empty pit of yours captures the pit across.",
              "Halte eine Mulde gedrückt und lies die Aussaat-Vorschau.",
              "Press and hold a pit to read the sowing preview."),
        intro("reversi", "🎲", "Reversi", "Reversi",
              "Lege so, dass du gegnerische Steine zwischen deinen einklemmst.",
              "Place so you trap enemy discs between two of yours.",
              "Alles Eingeklemmte kippt sofort zu deiner Farbe.",
              "Everything trapped flips to your color at once.",
              "Wer am vollen Brett mehr Steine zeigt, gewinnt.",
              "Whoever shows more discs on the full board wins.",
              "Suche ein Feld, das in zwei Richtungen gleichzeitig kippt.",
              "Find a square that flips in two directions at once."),
        intro("memoryduo", "🎲", "Memory-Duo", "Memory Duo",
              "Deckt abwechselnd zwei verdeckte Karten auf.",
              "Take turns flipping two hidden cards.",
              "Ein Paar bringt den Punkt und einen Extrazug.",
              "A pair scores the point and keeps your turn.",
              "Einmal Gesehenes bleibt für euch beide markiert — merkt es euch trotzdem.",
              "Once seen, a card stays marked for both of you — remember it anyway.",
              "Merke dir zwei Motive und finde sie im nächsten Zug wieder.",
              "Memorize two motifs and find them again next turn."),
        intro("kaesekaestchen", "🎲", "Käsekästchen", "Dots & Boxes",
              "Zieht abwechselnd genau eine Kante zwischen zwei Punkten.",
              "Take turns drawing exactly one edge between two dots.",
              "Die vierte Kante schließt das Kästchen für dich.",
              "The fourth edge closes the box for you.",
              "Ein geschlossenes Kästchen schenkt dir sofort einen Extrazug.",
              "A closed box immediately grants an extra turn.",
              "Zähle die dritten Kanten, bevor du eine verschenkst.",
              "Count the third edges before you give one away."),
        intro("gomoku", "🎲", "Gomoku", "Gomoku",
              "Setzt abwechselnd Steine auf freie Gitterpunkte.",
              "Take turns placing stones on free grid points.",
              "Genau fünf eigene Steine in einer Reihe gewinnen.",
              "Exactly five of your stones in a row win.",
              "Sechs oder mehr zählen nicht — plant die Reihe exakt.",
              "Six or more do not count — plan the row exactly.",
              "Baue eine offene Dreierreihe mit zwei freien Enden.",
              "Build an open row of three with both ends free."),
        intro("wordle", "💘", "Liebes-Wordle", "Love Wordle",
              "Ihr ratet dasselbe Tageswort in sechs Versuchen.",
              "You both guess the same daily word in six tries.",
              "Grün sitzt, Gelb steckt woanders im Wort, Grau fehlt ganz.",
              "Green is placed, yellow hides elsewhere in the word, gray is out.",
              "Ein Wort pro Tag — danach vergleicht ihr eure Versuche im Duell.",
              "One word per day — then compare your tries in the duel.",
              "Starte mit einem Wort voller verschiedener Vokale.",
              "Open with a word full of different vowels."),
    ]

    /// The complete intro library the hub links to: the 19 session-game
    /// intros plus the board wave and Wordle.
    static let library: [GameTutorial] = all + boardWave

    /// Library lookup — checks the board wave too (unlike `tutorial(for:)`,
    /// which predates it and only knows the original 19).
    static func intro(for id: String) -> GameTutorial? {
        library.first { $0.id == id }
    }

    private static func intro(
        _ id: String, _ emoji: String, _ de: String, _ en: String,
        _ de1: String, _ en1: String, _ de2: String, _ en2: String,
        _ de3: String, _ en3: String, _ practiceDE: String, _ practiceEN: String
    ) -> GameTutorial {
        GameTutorial(
            id: id,
            emoji: emoji,
            title: LText(de: de, en: en),
            steps: [LText(de: de1, en: en1), LText(de: de2, en: en2), LText(de: de3, en: en3)],
            practicePrompt: LText(de: practiceDE, en: practiceEN)
        )
    }
}
