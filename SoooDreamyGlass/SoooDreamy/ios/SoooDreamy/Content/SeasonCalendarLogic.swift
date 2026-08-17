import Foundation

enum SeasonCalendarKind: String, Codable, CaseIterable, Identifiable {
    case advent, birthday, anniversary, countdown
    var id: String { rawValue }
    var titleKey: String { "seasoncalendar.kind.\(rawValue)" }
}

enum SeasonDoorPayloadKind: String, Codable, CaseIterable {
    case prompt, quest, letter, game
}

struct SeasonDoorDraft: Codable, Hashable {
    let unlockAt: Date
    let kind: SeasonDoorPayloadKind
    let text: String
}

enum SeasonCalendarPlan {
    static func doorDates(
        startingAt start: Date,
        count: Int,
        calendar: Calendar = .current
    ) -> [Date] {
        guard count > 0 else { return [] }
        let normalized = calendar.startOfDay(for: start)
        return (0..<min(count, 31)).compactMap {
            calendar.date(byAdding: .day, value: $0, to: normalized)
        }
    }
}

enum SeasonalEvent: String, CaseIterable {
    case valentine, halloween, newYear, anniversary

    static func active(
        on date: Date,
        anniversary: Date? = nil,
        calendar: Calendar = .current
    ) -> [SeasonalEvent] {
        let components = calendar.dateComponents([.month, .day], from: date)
        var events: [SeasonalEvent] = []
        if components.month == 2 && components.day == 14 { events.append(.valentine) }
        if components.month == 10 && components.day == 31 { events.append(.halloween) }
        if (components.month == 12 && components.day == 31)
            || (components.month == 1 && components.day == 1) {
            events.append(.newYear)
        }
        if let anniversary {
            let anniversaryComponents = calendar.dateComponents([.month, .day], from: anniversary)
            if anniversaryComponents.month == components.month
                && anniversaryComponents.day == components.day {
                events.append(.anniversary)
            }
        }
        return events
    }

    var titleKey: String { "seasonalevent.\(rawValue).title" }
    var suggestedWidgetSkin: String {
        switch self {
        case .valentine: return "blush"
        case .halloween: return "sunset"
        case .newYear, .anniversary: return "gold"
        }
    }
}

// MARK: - Next-door dashboard visibility (FX-O #8)

// The dashboard card needs to answer "what is the next door and when?"
// without the API models (they live outside the logic target) — so the
// selection works on value-only summaries the card maps into.

/// One un-opened door addressed to me, reduced to what the Home card shows.
struct SeasonDoorSummary: Equatable {
    let number: Int
    let unlockAt: Date
    let opened: Bool
}

struct SeasonCalendarDoorFeed: Equatable {
    /// Doors are only "next" for their recipient — the creator already
    /// knows what's inside.
    let forMe: Bool
    let doors: [SeasonDoorSummary]
}

/// What the countdown line renders. `ready` beats any countdown.
enum SeasonDoorCountdown: Equatable {
    case ready
    case days(Int)
    case hoursMinutes(Int, Int)
    case minutes(Int)
    case soon
}

enum SeasonDoorDashboard {
    /// The single next door across all calendars addressed to me: an already
    /// unlockable door wins (earliest first); otherwise the door that
    /// unlocks soonest carries the countdown.
    static func nextDoor(
        in calendars: [SeasonCalendarDoorFeed],
        now: Date = Date()
    ) -> SeasonDoorSummary? {
        let waiting = calendars
            .filter(\.forMe)
            .flatMap(\.doors)
            .filter { !$0.opened }
            .sorted { $0.unlockAt < $1.unlockAt }
        return waiting.first { $0.unlockAt <= now } ?? waiting.first
    }

    /// Coarse, calm countdown: whole days from 48 h out, hours+minutes
    /// under that, minutes under an hour — never a ticking seconds clock.
    static func countdown(until unlockAt: Date, now: Date = Date()) -> SeasonDoorCountdown {
        let remaining = unlockAt.timeIntervalSince(now)
        guard remaining > 0 else { return .ready }
        if remaining < 60 { return .soon }
        let minutes = Int((remaining / 60).rounded(.up))
        if minutes < 60 { return .minutes(minutes) }
        let hours = minutes / 60
        if hours < 48 { return .hoursMinutes(hours, minutes % 60) }
        // Nearest whole day: 49 h honestly reads "2 days", 71 h "3 days".
        return .days(max(2, Int((remaining / 86_400).rounded())))
    }
}

struct SeasonDoorTemplate: Hashable {
    let kind: SeasonDoorPayloadKind
    let de: String
    let en: String

    func text(language: String) -> String {
        language == "de" ? de : en
    }
}

enum SeasonDoorTemplates {
    static let all: [SeasonDoorTemplate] = prompts + quests + letters + games

    static let prompts: [SeasonDoorTemplate] = [
        .init(kind: .prompt, de: "Was hat dich diese Woche lächeln lassen?", en: "What made you smile this week?"),
        .init(kind: .prompt, de: "Welchen Moment mit uns würdest du gern wiederholen?", en: "Which moment of ours would you repeat?"),
        .init(kind: .prompt, de: "Wofür bist du heute dankbar?", en: "What are you grateful for today?"),
        .init(kind: .prompt, de: "Welche kleine Geste bedeutet dir besonders viel?", en: "Which small gesture means the most to you?"),
        .init(kind: .prompt, de: "Was möchtest du im nächsten Jahr gemeinsam lernen?", en: "What would you like us to learn next year?"),
        .init(kind: .prompt, de: "Wann fühlst du dich mir besonders nah?", en: "When do you feel especially close to me?"),
        .init(kind: .prompt, de: "Welches Lied klingt gerade nach uns?", en: "Which song sounds like us right now?"),
        .init(kind: .prompt, de: "Welche Tradition sollen wir beginnen?", en: "Which tradition should we start?"),
        .init(kind: .prompt, de: "Was macht unser Zuhause zu unserem Zuhause?", en: "What makes our home feel like ours?"),
        .init(kind: .prompt, de: "Welcher Insider bringt dich sofort zum Lachen?", en: "Which inside joke makes you laugh instantly?"),
        .init(kind: .prompt, de: "Was war unser mutigster gemeinsamer Moment?", en: "What was our bravest shared moment?"),
        .init(kind: .prompt, de: "Wo sollen wir einmal zusammen aufwachen?", en: "Where should we wake up together someday?"),
        .init(kind: .prompt, de: "Welche Eigenschaft an mir überrascht dich noch?", en: "Which quality of mine still surprises you?"),
        .init(kind: .prompt, de: "Wie sieht ein perfekter langsamer Sonntag aus?", en: "What does a perfect slow Sunday look like?"),
        .init(kind: .prompt, de: "Was möchtest du mir heute unbedingt sagen?", en: "What do you really want to tell me today?"),
        // Herbst & Winter zuerst — die Saison nach dem August-Release.
        .init(kind: .prompt, de: "Was macht einen kalten Tag mit mir warm?", en: "What makes a cold day warm when I'm around?"),
        .init(kind: .prompt, de: "Welcher Duft gehört für dich zu dieser Jahreszeit — und zu uns?", en: "Which scent belongs to this season — and to us?"),
        .init(kind: .prompt, de: "Woran denkst du, wenn es abends früher dunkel wird?", en: "What do you think about when the dark comes early?"),
        .init(kind: .prompt, de: "Welchen Wintermoment willst du dieses Jahr zum ersten Mal mit mir erleben?", en: "Which winter moment do you want to share with me for the first time this year?"),
        .init(kind: .prompt, de: "Welche Erinnerung an uns wärmt dich gerade am meisten?", en: "Which memory of us warms you the most right now?"),
        // Feiertage & Anlässe — DE + international.
        .init(kind: .prompt, de: "Welche kleine Überraschung würdest du gern in einem Stiefel vor der Tür finden?", en: "What small surprise would you love to find in a boot by the door?"),
        .init(kind: .prompt, de: "Welchen Moment von uns nimmst du mit ins neue Jahr?", en: "Which moment of ours are you taking into the new year?"),
        .init(kind: .prompt, de: "Wie würdest du uns einem Fremden am Valentinstag in einem Satz beschreiben?", en: "How would you describe us to a stranger on Valentine's Day, in one sentence?"),
    ]

    static let quests: [SeasonDoorTemplate] = [
        .init(kind: .quest, de: "Schickt euch ein Foto von eurem Blick gerade.", en: "Send each other a photo of your view right now."),
        .init(kind: .quest, de: "Plant heute zehn Minuten nur für euch.", en: "Plan ten minutes just for you two today."),
        .init(kind: .quest, de: "Macht dem anderen ein ehrliches Kompliment.", en: "Give each other one sincere compliment."),
        .init(kind: .quest, de: "Hört gemeinsam euer Lied.", en: "Listen to your song together."),
        .init(kind: .quest, de: "Kocht oder bestellt etwas, das ihr beide liebt.", en: "Cook or order something you both love."),
        .init(kind: .quest, de: "Geht eine kleine Runde ohne Handys.", en: "Take a short walk without your phones."),
        .init(kind: .quest, de: "Schreibt je einen Wunsch für das nächste Jahr auf.", en: "Write down one wish each for next year."),
        .init(kind: .quest, de: "Erzählt euch eine Erinnerung vom Anfang.", en: "Tell each other one memory from the beginning."),
        .init(kind: .quest, de: "Tanzt für ein Lied in der Küche.", en: "Dance to one song in the kitchen."),
        .init(kind: .quest, de: "Schickt euch drei Herzklopfen über den Tag.", en: "Send three heartbeats throughout the day."),
        .init(kind: .quest, de: "Findet einen Film für euren nächsten Abend.", en: "Pick a film for your next night together."),
        .init(kind: .quest, de: "Räumt gemeinsam eine kleine Ecke gemütlich auf.", en: "Make one small corner cozy together."),
        .init(kind: .quest, de: "Fragt euch gegenseitig: Lust auf eine Zehn-Sekunden-Umarmung?", en: "Ask each other: up for a ten-second hug?"),
        .init(kind: .quest, de: "Legt eine gemeinsame Mini-Playlist an.", en: "Make a tiny shared playlist."),
        .init(kind: .quest, de: "Sagt euch vor dem Schlafen eine gute Sache vom Tag.", en: "Share one good thing from the day before sleep."),
        // Herbst & Winter zuerst.
        .init(kind: .quest, de: "Macht einen Zehn-Minuten-Spaziergang durch fallendes Laub.", en: "Take a ten-minute walk through falling leaves."),
        .init(kind: .quest, de: "Teilt euch heute eine Decke, ein Buch oder einen Podcast.", en: "Share a blanket, a book, or a podcast today."),
        .init(kind: .quest, de: "Schickt euch ein Foto vom schönsten Herbstblatt eures Tages.", en: "Send a photo of the prettiest autumn leaf of your day."),
        .init(kind: .quest, de: "Plant euren ersten Weihnachtsmarkt- oder Lichter-Spaziergang.", en: "Plan your first Christmas-market or fairy-light walk."),
        .init(kind: .quest, de: "Kalte Hände? Fragt kurz nach — und wärmt sie euch gegenseitig, wenn ihr beide mögt.", en: "Cold hands? Check in first — then warm each other's hands, if you're both up for it."),
        // Feiertage & Anlässe.
        .init(kind: .quest, de: "Schreibt zusammen einen Neujahrswunsch auf und versteckt ihn bis nächsten Silvester.", en: "Write one shared New Year's wish and hide it until next New Year's Eve."),
        .init(kind: .quest, de: "Heute ist Tag der Umarmung: Verschenkt eine extra lange — wenn ihr beide mögt.", en: "It's Hug Day: give one extra-long hug — if you're both in the mood."),
        .init(kind: .quest, de: "Versteckt füreinander je eine Mini-Überraschung in der Wohnung — Ostereier-Prinzip, ganzjährig erlaubt.", en: "Hide one mini surprise for each other around your home — Easter-egg rules, valid all year."),
    ]

    static let letters: [SeasonDoorTemplate] = [
        .init(kind: .letter, de: "Eine Sache, die ich an dir bewundere …", en: "One thing I admire about you …"),
        .init(kind: .letter, de: "Mit dir fühlt sich Alltag so an …", en: "Everyday life with you feels like …"),
        .init(kind: .letter, de: "Danke, dass du …", en: "Thank you for …"),
        .init(kind: .letter, de: "Mein Lieblingsmoment dieses Monats war …", en: "My favorite moment this month was …"),
        .init(kind: .letter, de: "Wenn du das liest, sollst du wissen …", en: "When you read this, I want you to know …"),
        .init(kind: .letter, de: "Ich freue mich mit dir auf …", en: "With you, I look forward to …"),
        .init(kind: .letter, de: "Du machst mich mutiger, weil …", en: "You make me braver because …"),
        .init(kind: .letter, de: "Unser schönster Zufall war …", en: "Our loveliest coincidence was …"),
        .init(kind: .letter, de: "Ich sehe, wie viel du …", en: "I notice how much you …"),
        .init(kind: .letter, de: "Eine Eigenschaft, die uns stark macht …", en: "One quality that makes us strong …"),
        .init(kind: .letter, de: "Mein Wunsch für deinen heutigen Tag …", en: "My wish for your day today …"),
        .init(kind: .letter, de: "Das würde ich gern öfter mit dir tun …", en: "I would love to do this with you more often …"),
        .init(kind: .letter, de: "Du bist mein sicherer Ort, wenn …", en: "You are my safe place when …"),
        .init(kind: .letter, de: "An unserem ersten Tag dachte ich …", en: "On our first day, I thought …"),
        .init(kind: .letter, de: "Für unser nächstes Kapitel wünsche ich …", en: "For our next chapter, I hope …"),
        // Brief-Impulse in den drei Tönen der App — zärtlich:
        .init(kind: .letter, de: "Wenn du frierst, möchte ich …", en: "When you're cold, I want to …"),
        .init(kind: .letter, de: "Dein Lachen klingt für mich wie …", en: "To me, your laugh sounds like …"),
        .init(kind: .letter, de: "Am liebsten halte ich dich, wenn …", en: "I love holding you most when …"),
        .init(kind: .letter, de: "Heute Abend wünsche ich dir …", en: "Tonight I wish for you …"),
        .init(kind: .letter, de: "In deiner Nähe wird mein Tag …", en: "Near you, my day turns …"),
        // — verspielt:
        .init(kind: .letter, de: "Wenn wir beide ein Wetter wären, dann …", en: "If the two of us were a kind of weather, we'd be …"),
        .init(kind: .letter, de: "Mein Lieblingsblödsinn mit dir ist …", en: "My favorite nonsense with you is …"),
        .init(kind: .letter, de: "Ich gestehe: Ich habe heimlich …", en: "Confession: I've secretly been …"),
        .init(kind: .letter, de: "Unser nächstes Abenteuer braucht unbedingt …", en: "Our next adventure absolutely needs …"),
        .init(kind: .letter, de: "Du bist der einzige Mensch, mit dem ich …", en: "You're the only person I would ever …"),
        // — tief:
        .init(kind: .letter, de: "Seit dir verstehe ich besser, dass …", en: "Since you, I understand better that …"),
        .init(kind: .letter, de: "Was ich nie laut sage, aber denke: …", en: "What I never say out loud but think: …"),
        .init(kind: .letter, de: "Du hast mich verändert, weil …", en: "You have changed me, because …"),
        .init(kind: .letter, de: "Wenn ich an unsere Zukunft denke, halte ich fest an …", en: "When I think of our future, I hold on to …"),
        .init(kind: .letter, de: "Das Schwerste und Schönste an Liebe ist für mich …", en: "For me, the hardest and loveliest thing about love is …"),
        // Feiertage & Anlässe.
        .init(kind: .letter, de: "Mein Neujahrsvorsatz mit dir ist …", en: "My New Year's resolution with you is …"),
        .init(kind: .letter, de: "Mein Valentinsgruß mitten im Jahr: …", en: "My valentine to you, any day of the year: …"),
        .init(kind: .letter, de: "Dieses Jahr hat mir mit dir geschenkt: …", en: "This year, with you, has given me: …"),
    ]

    static let games: [SeasonDoorTemplate] = [
        .init(kind: .game, de: "60 Sekunden Blickkontakt — wer zuerst lacht, schuldet ein Kompliment.", en: "Sixty seconds of eye contact — first to laugh owes a compliment."),
        .init(kind: .game, de: "Erratet abwechselnd einen Song nur durch Summen.", en: "Take turns guessing a song from humming only."),
        .init(kind: .game, de: "Wer findet zuerst drei herzförmige Dinge?", en: "Who can find three heart-shaped things first?"),
        .init(kind: .game, de: "Spielt eine Runde Liebes-Wordle.", en: "Play one round of Love Wordle."),
        .init(kind: .game, de: "Nennt abwechselnd Date-Ideen, bis jemand stockt.", en: "Alternate date ideas until someone gets stuck."),
        .init(kind: .game, de: "Zeichnet euch in 60 Sekunden gegenseitig.", en: "Draw each other in sixty seconds."),
        .init(kind: .game, de: "Drei Aussagen, eine davon erfunden.", en: "Three statements, one made up."),
        .init(kind: .game, de: "Wer kennt die Lieblingssnacks des anderen besser?", en: "Who knows the other's favorite snacks better?"),
        .init(kind: .game, de: "Macht ein Foto-Memory mit vier Bildern.", en: "Play a four-photo memory challenge."),
        .init(kind: .game, de: "Erfindet gemeinsam die längste Wortkette.", en: "Build the longest word chain together."),
        .init(kind: .game, de: "Wählt blind je einen Film und lost aus.", en: "Each pick a film blindly, then draw one."),
        .init(kind: .game, de: "Beschreibt euren ersten Kuss mit drei Emojis.", en: "Describe your first kiss with three emoji."),
        .init(kind: .game, de: "Wer findet den ältesten gemeinsamen Chat-Moment?", en: "Who can find your oldest shared chat moment?"),
        .init(kind: .game, de: "Stellt euch abwechselnd eine Blitzfrage.", en: "Take turns asking one lightning question."),
        .init(kind: .game, de: "Würfelt euer nächstes Mini-Date aus.", en: "Roll the dice for your next mini date."),
        // Herbst & Winter zuerst.
        .init(kind: .game, de: "Wer errät mehr Wintersongs nur vom Summen?", en: "Who guesses more winter songs from humming alone?"),
        .init(kind: .game, de: "Baut in 60 Sekunden die gemütlichste Ecke des Zimmers.", en: "Build the coziest corner of the room in sixty seconds."),
        .init(kind: .game, de: "Beschreibt eine gemeinsame Erinnerung mit genau drei Wörtern — wer errät sie?", en: "Describe a shared memory in exactly three words — who guesses it?"),
        .init(kind: .game, de: "Wer findet zuerst etwas Goldenes, etwas Weiches, etwas Warmes?", en: "Who first finds something golden, something soft, something warm?"),
        .init(kind: .game, de: "Stapelt abwechselnd Kissen — wer den Turm kippt, kocht den Kakao.", en: "Take turns stacking pillows — whoever topples the tower makes the cocoa."),
        // Feiertage & Anlässe.
        .init(kind: .game, de: "Sagt euch je drei Vorhersagen fürs nächste Jahr — die geheime vierte wird aufgeschrieben.", en: "Trade three predictions for next year — the secret fourth gets written down."),
        .init(kind: .game, de: "Errate den Feiertag: Einer stellt ihn stumm dar, der andere rät.", en: "Guess the holiday: one acts it out in silence, the other guesses."),
        .init(kind: .game, de: "Eier-Lauf mit Löffeln quer durchs Wohnzimmer — etwas Eiförmiges findet sich immer.", en: "Egg-and-spoon race across the living room — something egg-shaped can always be found."),
    ]
}
