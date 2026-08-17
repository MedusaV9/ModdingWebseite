import Foundation

// MARK: - Games Wave II pure rules and text packs

enum WordChainValidation: Equatable {
    case valid
    case empty
    case unknown
    case repeated
    case wrongLetter(Character)
}

enum WordChainRules {
    static let dictionaries: [String: Set<String>] = [
        "de": Set("""
        abend abenteuer achtsamkeit anfang apfel arm band berg bild blume boot brief
        brücke buch café dach date danke diamant duft eis elefant engel erinnerung
        essen fahrrad familie feder feuer film fluss foto freude frühling fuß garten
        geborgenheit geschenk glück gold hand harmonika haus herz himmel humor insel
        jahrestag jahr kamera kerze kino kleeblatt koffer konzert kuss lachen lampe
        leben leuchtturm liebe lied luft meer mensch moment mond morgen musik mut
        nacht nähe nest oase ort partner pause picknick planet platz puzzle regen
        reise ring roman rose schatz schokolade see sonne sonnenblume spiel stern
        strand tag tandem tanz tasse team theater traum tür ufer umarmung urlaub
        vertrauen vogel wärme wasser weg welt wiese wolke wort wunsch zeit zelt ziel
        zuhause zukunft maßfuß
        """.split(separator: " ").map(String.init)),
        "en": Set("""
        adventure affection apple arm beach beginning bicycle bird blanket blossom
        boat book bridge candle camera care chocolate cinema cloud coffee concert
        courage dance date day delight diamond dream evening family feather fire
        flower forest friend future garden gift glow gold hand harmony heart holiday
        home hope hug humor island journey joy kindness kiss lake lamp laughter letter
        lighthouse love luck memory moment moon morning movie music night ocean park
        partner pause picnic place planet promise puzzle rain rainbow river road rose
        sea smile song sparkle star story summer sun surprise team theater time
        together touch travel tree trust umbrella vacation warmth water way wish word
        world year yesterday zest
        """.split(separator: " ").map(String.init)),
    ]

    static func normalized(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "de_DE"))
            .replacingOccurrences(of: "ß", with: "ss")
    }

    static func validate(_ candidate: String, after previous: String?,
                         used: [String], language: String) -> WordChainValidation {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2,
              trimmed.unicodeScalars.allSatisfy(CharacterSet.letters.contains) else {
            return .empty
        }
        let dictionaryWord = trimmed.lowercased(with: Locale(identifier: "de_DE"))
        guard dictionaries[language == "en" ? "en" : "de"]?.contains(dictionaryWord) == true else {
            return .unknown
        }
        let normalizedCandidate = normalized(trimmed)
        guard !used.contains(where: { normalized($0) == normalizedCandidate }) else {
            return .repeated
        }
        if let previous, let required = normalized(previous).last,
           normalizedCandidate.first != required {
            return .wrongLetter(required)
        }
        return .valid
    }
}

struct HangmanGuess: Hashable {
    let letter: Character
    let positions: [Int]?
}

struct HangmanBoardState: Equatable {
    let revealed: Set<Int>
    let wrong: Int
    let pending: Character?
    let solved: Bool
    let lost: Bool
}

enum HangmanRules {
    static let maxWrong = 10

    static func reduce(length: Int, guesses: [HangmanGuess]) -> HangmanBoardState {
        var revealed: Set<Int> = []
        var wrong = 0
        var pending: Character?
        for guess in guesses {
            guard pending == nil else { break }
            guard let positions = guess.positions else {
                pending = guess.letter
                continue
            }
            if positions.isEmpty {
                wrong += 1
            } else {
                revealed.formUnion(positions.filter { 0..<length ~= $0 })
            }
        }
        return HangmanBoardState(
            revealed: revealed,
            wrong: wrong,
            pending: pending,
            solved: length >= 3 && revealed.count >= length,
            lost: wrong >= maxWrong
        )
    }

    static func positions(of letter: Character, in word: String) -> [Int] {
        let target = String(letter).lowercased(with: Locale(identifier: "de_DE"))
        return word.lowercased(with: Locale(identifier: "de_DE")).enumerated().compactMap {
            String($0.element) == target ? $0.offset : nil
        }
    }

    // Setter suggestions and the local practice mode. The server never picks
    // the secret; it stores only the setter's SHA-256 commitment.
    static let words: [String: [String]] = [
        "de": """
        Abenteuer Abendbrot Achtsamkeit Album Ananas Anker Apfelbaum Ausflug
        Badesee Balkon Ballon Bandana Barfuß Baumhaus Bergsee Bilderbuch Blume
        Bootsfahrt Briefkasten Brücke Café Camping Chaosmoment Dachterrasse Date
        Decke Diamant Duftkerze Eisbecher Elefant Erinnerung Fahrrad Familie Feder
        Fenster Feuerwerk Filmabend Flussufer Fotoalbum Freundschaft Frühstück
        Garten Geborgenheit Geschenk Glitzer Glücksmoment Goldregen Handhalten
        Harmonie Haustür Herzklopfen Himmel Hochzeitsreise Hoffnung Humor Insel
        Jahrestag Jahrmarkt Kamera Kamin Katze Kerzenschein Kino Kirschblüte
        Kleeblatt Koffer Kompliment Konzert Kuss Lachen Lagerfeuer Lampe Lieblingslied
        Leuchtturm Liebe Luftballon Meerblick Mensch Moment Mondlicht Morgenkaffee
        Musik Nachtzug Nähe Nest Oase Ohrwurm Partner Pause Picknick Planet
        Polaroid Pusteblume Puzzle Regenbogen Reise Ring Roman Rose Schatz
        Schokolade See Seestern Sofa Sommernacht Sonne Sonnenblume Spiel Stern
        Sternbild Strand Spaziergang Tag Tandem Tanz Tasse Team Theater Traum
        Überraschung Ufer Umarmung Urlaub Vertrauen Vogel Wärmflasche Wasserfall
        Weg Weltreise Wiese Wolke Wort Wundertüte Wunsch Zeit Zelt Ziel Zuhause
        Zukunft Zimtschnecke Zugfahrt Zweisamkeit Abendsonne Abenteuerlust Ankommen
        Apfelkuchen Augenblick Baumkrone Berghütte Blumenstrauß Bücherregal
        Dankbarkeit Draußen Dreisatz Einladung Erdbeere Feierabend Fernweh
        Filmzitat Flaschenpost Frühlingsluft Geburtstagskuchen Geheimnis Gewitter
        Glückskeks Goldstück Handabdruck Herzbrief Hinterhof Inseltraum Kakaotasse
        Kissenburg Lieblingsort Liebesbrief Luftschloss Meeresrauschen Mitternacht
        Monatsfoto Morgenrot Mutprobe Nachtisch Nordlicht Papierschiff Regenjacke
        Reisefieber Schatzkarte Schneeflocke Seifenblase Sommerregen Sternschnuppe
        Strandkorb Teelicht Traumziel Überraschungspaket Verabredung Winterabend
        Wochenendtrip Wunschliste Zeitkapsel Abendwind Abenteuerbuch Apfelblüte
        Baumallee Bergpanorama Blumenwiese Dankesbrief Dämmerlicht Lieblingsmensch
        Lieblingsplatz Mondschein Nachtwanderung Picknickdecke Regenpause Reisekarte
        Rosenblatt Seeblick Sommerwind Sonnenaufgang Sternenhimmel Strandspaziergang
        Teepause Traumreise Waldweg Wintersonne Wochenplan Wunschmoment
        """.split(separator: " ").map(String.init),
        "en": """
        Adventure Affection Airplane Album Anchor Apple Autumn Balcony Balloon
        Barefoot Beach Bicycle Blanket Blossom Boat Bookstore Breakfast Bridge
        Candle Camping Cat Celebration Chocolate Cinema Cloud Coffee Comfort
        Compliment Concert Courage Dance Date Daydream Delight Diamond Dinner
        Dream Evening Family Feather Fireplace Fireworks Flower Forest Friendship
        Future Garden Gift Glitter Glow Gold Gratitude Handholding Harbor Harmony
        Heartbeat Holiday Home Hope Hug Humor Island Journey Joy Kindness Kiss
        Lake Laughter Letter Lighthouse Love Luck Memory Midnight Moment Moonlight
        Morning Mountain Movie Music Night Ocean Partner Pause Picnic Place Planet
        Polaroid Promise Puzzle Rainbow Rain Road Rose Seaside Secret Smile
        Snowflake Sofa Song Sparkle Star Stargazing Story Summer Sun Surprise
        Team Theater Time Together Touch Train Travel Tree Trust Umbrella Vacation
        Warmth Waterfall Way Weekend Window Wish World Year Yesterday Adventuretime
        Afterglow Applepie Arrival Backyard Beachwalk Bedtime Birdsong Bookcase
        Bouquet Campfire Candlelight Citytrip Cloudburst Cozycorner Daylight
        Dreamland Earthlight Eveningstar Fairground Favoriteplace Ferriswheel
        Filmnight Firefly Flowerfield Footprint Forestpath Giftwrap Goldenhour
        Goodmorning Heartletter Hideaway Honeymoon Housekey Insidejoke Islanddream
        Keepsake Kindword KitchenDance Lantern Lightness Loveletter Lovestory
        Memorybox Moonbeam Nighttrain Northstar Oceanbreeze Paperboat Parkbench
        Pillowfort Postcard Raindrop Roadtrip Seaglass Seashell Shootingstar
        SlowSunday Snowfall Songbird Starlight Sunrise Sunset Teacup Tenderness
        Togetherness Treasure Trustfall Warmblanket Watercolor Weeknight Wildflower
        Winterevening Wishlist Wonder Yearbook Anniversary Apricot Blueberry
        Butterfly Carousel Cheesecake Daytrip Evergreen Firelight Gardenpath
        Heartstring Homecoming Honeybee Keepsake Lighthouseview Marshmallow
        Moonrise Nightwalk Orangeblossom Peppermint Raincoat Riverbank Sandcastle
        Seasidewalk Storybook Sunflower Sweetheart Thunderstorm Timecapsule
        Twinkle Waterlily Weekendtrip Windchime
        """.split(separator: " ").map(String.init),
    ]
}

struct CoupleBingoAction: Identifiable, Hashable {
    let id: String
    let eventType: String
    let text: LText
}

enum CoupleBingo {
    static let lines = [
        [0, 1, 2, 3], [4, 5, 6, 7], [8, 9, 10, 11], [12, 13, 14, 15],
        [0, 4, 8, 12], [1, 5, 9, 13], [2, 6, 10, 14], [3, 7, 11, 15],
        [0, 5, 10, 15], [3, 6, 9, 12],
    ]

    static func completedLine(checked: Set<Int>) -> [Int]? {
        lines.first { Set($0).isSubset(of: checked) }
    }

    static let actions: [CoupleBingoAction] = [
        action("heartbeat", "thanks_sent", "Schick ein warmes Danke", "Send a warm thank-you"),
        action("compliment", "thanks_sent", "Mach ein ehrliches Kompliment", "Give a sincere compliment"),
        action("miss_you", "missyou_sent", "Sag: Du fehlst mir", "Say: I miss you"),
        action("tiny_thanks", "thanks_sent", "Danke für eine Kleinigkeit", "Thank them for one small thing"),
        action("open_capsule", "capsule_opened", "Öffnet eine Zeitkapsel", "Open a time capsule"),
        action("seal_capsule", "capsule_sealed", "Versiegle eine Erinnerung", "Seal a memory"),
        action("share_need", "need_sent", "Teile ein Bedürfnis", "Share a need"),
        action("create_goal", "goal_created", "Setzt ein gemeinsames Ziel", "Set a shared goal"),
        action("goal_step", "goal_milestone", "Erreicht einen Ziel-Schritt", "Reach a goal milestone"),
        action("finish_goal", "goal_reached", "Schließt ein Ziel ab", "Finish a goal"),
        action("plan_time", "weekplan_slot_created", "Plant Zeit zu zweit", "Plan time together"),
        action("read_magazine", "magazine_seen_both", "Lest euer Magazin", "Read your magazine"),
        action("movie_match", "movie_match", "Findet euren Film", "Find your movie match"),
        action("daily_quest", "quest_done", "Erledigt eine Tagesquest", "Complete a daily quest"),
        action("gift_icon", "icon_gift_sent", "Verschenke ein App-Icon", "Gift an app icon"),
        action("plan_date", "datenight_planned", "Plant eine Date-Night", "Plan a date night"),
        action("three_good_things", "goodthings_both", "Teilt drei gute Dinge", "Share three good things"),
        action("confirm_inside_word", "dictionary_confirmed", "Bestätigt euer Insiderwort", "Confirm an inside word"),
        action("log_first", "first_logged", "Haltet ein erstes Mal fest", "Log a first"),
        action("make_calendar", "season_calendar_created", "Baut einen Türchen-Kalender", "Make a countdown calendar"),
        action("open_door", "season_calendar_door_opened", "Öffnet ein Türchen", "Open a calendar door"),
        action("kind_message", "thanks_sent", "Schick einen lieben Satz", "Send one kind sentence"),
        action("warm_ping", "missyou_sent", "Schick einen Nähe-Ping", "Send a closeness ping"),
        action("listen_need", "need_sent", "Fragt: Was brauchst du?", "Ask: what do you need?"),
        action("dream_goal", "goal_created", "Notiert einen gemeinsamen Traum", "Write down a shared dream"),
        action("quarter_goal", "goal_milestone", "Feiert 25 Prozent", "Celebrate 25 percent"),
        action("shared_win", "goal_reached", "Feiert einen gemeinsamen Erfolg", "Celebrate a shared win"),
        action("call_slot", "weekplan_slot_created", "Reserviert einen Anruf", "Reserve a call"),
        action("month_memory", "magazine_seen_both", "Blättert durch euren Monat", "Browse your month"),
        action("pick_film", "movie_match", "Wählt einen Film zu zweit", "Choose a film together"),
        action("quest_together", "quest_done", "Hakt eine Mission ab", "Check off a mission"),
        action("surprise_icon", "icon_gift_sent", "Überrasche mit einem Icon", "Surprise them with an icon"),
        action("date_night", "datenight_planned", "Setzt einen Date-Abend", "Schedule a date evening"),
        action("gratitude_evening", "goodthings_both", "Macht euren Dankbarkeitsabend", "Have a gratitude evening"),
        action("our_word", "dictionary_confirmed", "Ergänzt euer Wörterbuch", "Add to your dictionary"),
        action("first_memory", "first_logged", "Speichert einen Anfangsmoment", "Save a beginning memory"),
        action("countdown", "season_calendar_created", "Startet einen Countdown", "Start a countdown"),
        action("door_surprise", "season_calendar_door_opened", "Entdeckt eine Überraschung", "Discover a surprise"),
        action("say_thanks", "thanks_sent", "Sag heute bewusst Danke", "Say thank you deliberately"),
        action("thinking_of_you", "missyou_sent", "Sag: Ich denke an dich", "Say: I'm thinking of you"),
        action("ask_gently", "need_sent", "Teile, was heute hilft", "Share what would help today"),
        action("shared_plan", "goal_created", "Beginnt einen kleinen Plan", "Start a small shared plan"),
        action("celebrate_progress", "goal_milestone", "Feiert euren Fortschritt", "Celebrate your progress"),
        action("goal_confetti", "goal_reached", "Bringt ein Ziel ins Ziel", "Bring a goal home"),
        action("reserve_evening", "weekplan_slot_created", "Haltet einen Abend frei", "Keep an evening free"),
        action("read_together", "magazine_seen_both", "Lest etwas gemeinsam", "Read something together"),
        action("film_evening", "movie_match", "Findet euren Filmabend", "Find your movie night"),
        action("micro_quest", "quest_done", "Erledigt eine Mini-Mission", "Complete a mini mission"),
        action("icon_present", "icon_gift_sent", "Packt ein Icon-Geschenk", "Wrap an icon gift"),
        action("countdown_date", "datenight_planned", "Startet Date-Vorfreude", "Start a date countdown"),
        action("three_bright_spots", "goodthings_both", "Nennt drei Lichtblicke", "Name three bright spots"),
        action("inside_joke", "dictionary_confirmed", "Sichert einen Insider", "Save an inside joke"),
        action("remember_beginning", "first_logged", "Erinnert euch an den Anfang", "Remember the beginning"),
        action("calendar_for_you", "season_calendar_created", "Schenk einen Kalender", "Gift a calendar"),
        action("unwrap_door", "season_calendar_door_opened", "Packt ein Türchen aus", "Unwrap a door"),
        action("specific_praise", "thanks_sent", "Lobt etwas ganz konkret", "Praise something specific"),
        action("distance_hug", "missyou_sent", "Schickt eine Distanz-Umarmung", "Send a distance hug"),
        action("make_space", "need_sent", "Macht Raum für ein Gefühl", "Make room for a feeling"),
        action("next_adventure", "goal_created", "Plant euer nächstes Abenteuer", "Plan your next adventure"),
        action("small_milestone", "goal_milestone", "Markiert einen kleinen Meilenstein", "Mark a small milestone"),
    ]

    private static func action(_ id: String, _ event: String, _ de: String, _ en: String) -> CoupleBingoAction {
        CoupleBingoAction(id: id, eventType: event, text: LText(de: de, en: en))
    }
}

// MARK: - Three-step tutorials and local practice

struct GameTutorial: Identifiable, Hashable {
    let id: String
    let emoji: String
    let title: LText
    let steps: [LText]
    let practicePrompt: LText
}

struct TutorialProgress: Equatable {
    private(set) var step = 0
    private(set) var skipped = false

    mutating func advance(total: Int = 3) {
        step = min(step + 1, total)
    }

    mutating func skip(total: Int = 3) {
        step = total
        skipped = true
    }

    var complete: Bool { step >= 3 }
}

enum PracticeTurns {
    static func actor(turn: Int, members: [String], soloMember: String?) -> String? {
        if let soloMember { return soloMember }
        guard !members.isEmpty else { return nil }
        return members[turn % members.count]
    }
}

enum GameTutorialCatalog {
    // Exactly the 19 game-session kinds exposed in the 5.1 Play hub.
    static let all: [GameTutorial] = [
        tutorial("quiz", "🧠", "Paar-Quiz", "Couple quiz", "Antworte ehrlich.", "Answer honestly.", "Dein Schatz rät.", "Your partner guesses.", "Die Person entscheidet fair.", "The subject judges fairly.", "Formuliere eine Beispielantwort.", "Write a sample answer."),
        tutorial("thisorthat", "⚡️", "Dies oder Das", "This or That", "Beide sehen dasselbe Paar.", "You both see the same pair.", "Wählt ohne Absprechen.", "Pick without discussing.", "Vergleicht eure Matches.", "Compare your matches.", "Wähle spontan links oder rechts.", "Pick left or right on instinct."),
        tutorial("wouldyourather", "🤯", "Würdest du eher", "Would You Rather", "Lest das Dilemma.", "Read the dilemma.", "Wählt unabhängig.", "Choose independently.", "Erzählt euch danach warum.", "Then tell each other why.", "Begründe eine verrückte Wahl.", "Explain one wild choice."),
        tutorial("truthordare", "🎭", "Wahrheit oder Pflicht", "Truth or Dare", "Wählt eure Stufe.", "Choose your level.", "Die aktive Person zieht.", "The active person draws.", "Passen ist erlaubt.", "Skipping is always allowed.", "Probiere eine sanfte Karte.", "Try one gentle card."),
        tutorial("questions36", "💫", "36 Fragen", "36 Questions", "Nehmt euch Zeit.", "Take your time.", "Beide antworten.", "You both answer.", "Vier Minuten Blickkontakt sind optional.", "Four minutes of eye contact is optional.", "Lies eine Frage laut.", "Read one question aloud."),
        tutorial("emojiriddle", "🧩", "Emoji-Rätsel", "Emoji Riddle", "Deutet die Emojis.", "Interpret the emoji.", "Gebt euren Tipp ab.", "Submit your guess.", "Wertet ehrlich.", "Score honestly.", "Errate eine Übungsfolge.", "Guess a practice sequence."),
        tutorial("connectfour", "🔴", "4 Gewinnt", "Connect Four", "Ihr setzt abwechselnd.", "Take turns dropping discs.", "Vier in einer Linie gewinnen.", "Four in a line wins.", "Volle Spalten sind gesperrt.", "Full columns are locked.", "Plane zwei Züge voraus.", "Plan two moves ahead."),
        tutorial("photomemory", "🖼️", "Foto-Memory", "Photo Memory", "Deckt zwei Fotos auf.", "Flip two photos.", "Ein Paar bringt einen Punkt.", "A pair earns one point.", "Bei einem Treffer bleibst du dran.", "A match keeps your turn.", "Merke dir zwei Positionen.", "Memorize two positions."),
        tutorial("quizduel", "⚡️", "Quiz-Duell", "Quiz Duel", "Beide bekommen dieselbe Frage.", "You both get the same question.", "Schnell und richtig bringt zwei Punkte.", "Fast and correct earns two.", "Die zweite richtige Antwort zählt auch.", "The second correct answer still scores.", "Beantworte eine Blitzfrage.", "Answer one speed question."),
        tutorial("battleship", "🚢", "Schiffe versenken", "Battleship", "Versiegelt eure Flotten.", "Seal your fleets.", "Feuert abwechselnde Salven.", "Take turns firing salvos.", "Der Reveal beweist Fairness.", "The reveal proves fairness.", "Platziere eine Übungsflotte.", "Place a practice fleet."),
        tutorial("pictionary", "🎨", "Montagsmaler", "Pictionary", "Eine Person zeichnet.", "One person draws.", "Die andere rät gegen die Zeit.", "The other guesses against time.", "Dann wechseln die Rollen.", "Then swap roles.", "Skizziere einen Begriff.", "Sketch one prompt."),
        tutorial("kniffel", "🎲", "Kniffel", "Yahtzee", "Würfle bis zu dreimal.", "Roll up to three times.", "Halte passende Würfel.", "Hold useful dice.", "Jede Kategorie nur einmal.", "Use each category once.", "Wähle Haltewürfel.", "Choose which dice to hold."),
        tutorial("movieroulette", "🍿", "Film-Roulette", "Movie Roulette", "Beide wischen denselben Stapel.", "Swipe the same deck.", "Rechts heißt interessiert.", "Right means interested.", "Doppelte Likes ergeben ein Match.", "Two likes create a match.", "Bewerte drei Filmideen.", "Rate three movie ideas."),
        tutorial("stadtlandfluss", "🗺️", "Stadt Land Fluss", "Categories", "Beide versiegeln Antworten.", "Both seal answers.", "Dann wird gemeinsam enthüllt.", "Then reveal together.", "Bewertet fair nach Buchstaben.", "Score fairly by letter.", "Fülle eine Übungskategorie.", "Fill one practice category."),
        tutorial("twotruths", "🤥", "Zwei Wahrheiten", "Two Truths", "Schreibe drei Aussagen.", "Write three statements.", "Versiegle die Lüge.", "Seal which one is the lie.", "Der Tipp kommt vor dem Reveal.", "Guess before the reveal.", "Erfinde eine harmlose Lüge.", "Make up one harmless lie."),
        tutorial("dailyquests", "⚔️", "Tagesquests", "Daily Quests", "Drei Missionen gelten für beide.", "Three missions belong to both.", "Der erste Haken zählt.", "The first check counts.", "Der Server schützt die Serie.", "The server protects the streak.", "Wähle eine Mini-Mission.", "Choose one mini mission."),
        tutorial("wordchain", "🔗", "Wortkette-Blitz", "Word Chain Blitz", "Das nächste Wort beginnt mit dem letzten Buchstaben.", "Start with the previous final letter.", "Wörter dürfen nicht doppelt vorkommen.", "Words cannot repeat.", "Der Server prüft das Wörterbuch.", "The server checks the dictionary.", "Baue eine Kette aus drei Wörtern.", "Build a three-word chain."),
        tutorial("hangman", "🌸", "Galgenraten: Unser Wort", "Hangman: Our Word", "Eine Person versiegelt ein Wort.", "One person seals a word.", "Die andere rät Buchstaben.", "The other guesses letters.", "Zehn Fehlversuche und ein Fairness-Reveal.", "Ten misses and a fairness reveal.", "Errate ein liebevolles Übungswort.", "Guess a sweet practice word."),
        tutorial("bingo", "💞", "Paar-Bingo", "Couple Bingo", "Ihr bekommt 16 Mikro-Aktionen.", "You get 16 micro actions.", "Echte App-Momente haken Felder ab.", "Real app moments check tiles.", "Eine Reihe feiert auf beiden Handys.", "A line celebrates on both phones.", "Wähle eine Aktion für heute.", "Choose one action for today."),
    ]

    static func tutorial(for id: String) -> GameTutorial? {
        all.first { $0.id == id }
    }

    private static func tutorial(
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
