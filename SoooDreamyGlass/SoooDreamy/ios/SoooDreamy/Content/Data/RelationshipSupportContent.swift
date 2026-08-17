import Foundation

/// Carefully neutral prompts for the opt-in relationship-support tools.
/// These are conversation aids, never diagnostic or therapeutic advice.
struct RelationshipSupportPrompt: Identifiable, Hashable {
    let id: String
    let text: LText
}

enum RelationshipSupportContent {
    static let repairPrompts: [RelationshipSupportPrompt] = make(
        prefix: "repair",
        pairs: [
            ("Was möchtest du heute ruhig aussprechen?", "What would you like to say calmly today?"),
            ("In welchem Moment hast du dich nicht gesehen gefühlt?", "When did you feel unseen?"),
            ("Was hat dich verletzt, ohne dass du Schuld verteilen möchtest?", "What hurt you, without assigning blame?"),
            ("Was brauchst du, damit Zuhören heute leichter wird?", "What do you need to make listening easier today?"),
            ("Welche Annahme möchtest du gemeinsam überprüfen?", "Which assumption would you like to check together?"),
            ("Was ist hinter deinem Ärger noch zu spüren?", "What feeling sits underneath your frustration?"),
            ("Welcher kleine Moment ist größer geworden als gedacht?", "Which small moment became bigger than expected?"),
            ("Was wolltest du sagen, hast aber keinen ruhigen Zeitpunkt gefunden?", "What did you want to say but never found a calm moment for?"),
            ("Welche Absicht von dir kam anders an?", "Which intention of yours landed differently?"),
            ("Was möchtest du an der Sicht deines Schatzes besser verstehen?", "What would you like to understand better about your partner’s view?"),
            ("Wobei wünschst du dir mehr Verlässlichkeit?", "Where would you like more reliability?"),
            ("Wo braucht ihr gerade eine freundlichere Grenze?", "Where do you need a kinder boundary right now?"),
            ("Welche Bitte kannst du konkret und machbar formulieren?", "What request can you make concrete and manageable?"),
            ("Was würde dir nach diesem Gespräch Sicherheit geben?", "What would help you feel safe after this conversation?"),
            ("Was soll dein Schatz über deine Reaktion wissen?", "What should your partner know about your reaction?"),
            ("Welche alte Sorge wurde in diesem Moment berührt?", "Which old worry did this moment touch?"),
            ("Was kannst du anerkennen, obwohl ihr nicht einer Meinung seid?", "What can you acknowledge even if you disagree?"),
            ("Welche Worte möchtest du heute langsamer sagen?", "Which words would you like to say more slowly today?"),
            ("Was war dir in diesem Konflikt besonders wichtig?", "What mattered most to you in this conflict?"),
            ("Wo habt ihr aneinander vorbeigeredet?", "Where did you talk past each other?"),
            ("Welche Wirkung hatte der Moment auf dich?", "What impact did the moment have on you?"),
            ("Was möchtest du zuerst gehört wissen, bevor ihr Lösungen sucht?", "What do you want heard before you look for solutions?"),
            ("Welche kleine Wiedergutmachung würde sich stimmig anfühlen?", "What small repair would feel meaningful?"),
            ("Was kannst du selbst zum nächsten ruhigen Schritt beitragen?", "What can you contribute to the next calm step?"),
            ("Welche Gemeinsamkeit soll euch durch dieses Gespräch tragen?", "Which shared value should carry you through this conversation?"),
            ("Was möchtest du ohne Übertreibung und ohne Verkleinerung beschreiben?", "What would you like to describe without exaggerating or minimizing it?"),
            ("Woran würdest du merken, dass ihr euch wieder näher seid?", "How would you notice that you feel closer again?"),
            ("Welche Pause oder welches Tempo braucht dieses Thema?", "What pause or pace does this topic need?"),
            ("Was soll bei eurer kleinen Vereinbarung unbedingt realistisch bleiben?", "What must stay realistic in your small agreement?"),
            ("Was schätzt du an euch, auch während dieses schwierigen Moments?", "What do you value about the two of you, even in this difficult moment?"),
        ]
    )

    static let considerationHints: [RelationshipSupportPrompt] = make(
        prefix: "consideration",
        pairs: [
            ("Heute bitte besonders sanft mit mir sein 💜", "Please be extra gentle with me today 💜"),
            ("Meine Energie ist heute niedrig.", "My energy is low today."),
            ("Ich brauche heute mehr Ruhe als Lösungen.", "I need more quiet than solutions today."),
            ("Eine kleine Umarmung würde heute helfen.", "A small hug would help today."),
            ("Bitte frag kurz nach, bevor du Pläne machst.", "Please check in before making plans."),
            ("Ich bin empfindlicher als sonst, du bist nicht schuld.", "I’m more sensitive than usual; it isn’t your fault."),
            ("Heute hilft mir etwas mehr Geduld.", "A little extra patience would help today."),
            ("Ich brauche Nähe, aber wenig Worte.", "I need closeness, but not many words."),
            ("Bitte gib mir etwas Zeit zum Antworten.", "Please give me a little time to respond."),
            ("Ein Tee oder Wasser wäre heute eine liebe Geste.", "Tea or water would be a kind gesture today."),
            ("Meine Schmerzen kosten heute Kraft.", "Pain is taking a lot of my energy today."),
            ("Ich möchte heute lieber spontan als fest geplant sein.", "I’d prefer flexibility over firm plans today."),
            ("Bitte erinnere mich freundlich an Pausen.", "Please gently remind me to take breaks."),
            ("Ich kann heute weniger übernehmen als sonst.", "I can take on less than usual today."),
            ("Heute tut mir ein ruhiger Abend gut.", "A quiet evening would be good for me today."),
            ("Frag mich später noch einmal, falls ich gerade still bin.", "Check in again later if I’m quiet right now."),
            ("Ich freue mich heute über kleine Aufmerksamkeiten.", "Small gestures would mean a lot today."),
            ("Bitte nimm kurze Antworten heute nicht persönlich.", "Please don’t take short answers personally today."),
            ("Ich wünsche mir heute klare, sanfte Absprachen.", "I’d like clear, gentle agreements today."),
            ("Danke, dass ich diesen Hinweis jederzeit pausieren darf.", "Thank you for letting me pause this hint anytime."),
        ]
    )

    static let gratitudePrompts: [RelationshipSupportPrompt] = make(
        prefix: "gratitude",
        pairs: [
            ("Ein kleiner Moment, der heute gut war …", "One small moment that felt good today…"),
            ("Etwas, das mich heute zum Lächeln gebracht hat …", "Something that made me smile today…"),
            ("Heute war ich dankbar für …", "Today I felt grateful for…"),
            ("Etwas Schönes, das ich fast übersehen hätte …", "Something lovely I almost overlooked…"),
            ("Ein ruhiger Augenblick heute …", "One peaceful moment today…"),
            ("Etwas, das mein Körper heute geschafft hat …", "Something my body managed today…"),
            ("Eine Nachricht oder ein Satz, der gutgetan hat …", "A message or sentence that helped…"),
            ("Etwas Leckeres von heute …", "Something tasty from today…"),
            ("Ein Geräusch, Geruch oder Bild, das schön war …", "A sound, smell, or sight that was lovely…"),
            ("Etwas, das leichter war als erwartet …", "Something that was easier than expected…"),
            ("Ein Moment, in dem ich mich sicher gefühlt habe …", "A moment when I felt safe…"),
            ("Etwas, das ich heute gelernt habe …", "Something I learned today…"),
            ("Ein kleiner Erfolg von heute …", "One small win from today…"),
            ("Eine Person, die heute geholfen hat …", "Someone who helped today…"),
            ("Etwas an uns, das ich heute geschätzt habe …", "Something about us I appreciated today…"),
            ("Eine liebe Geste von dir …", "A kind gesture from you…"),
            ("Ein gemeinsamer Moment, den ich behalten möchte …", "A shared moment I want to remember…"),
            ("Etwas, worauf ich mich morgen freue …", "Something I’m looking forward to tomorrow…"),
            ("Ein Problem, das heute kleiner geworden ist …", "A problem that became smaller today…"),
            ("Etwas Vertrautes, das mir gutgetan hat …", "Something familiar that comforted me…"),
            ("Ein unerwartet schöner Moment …", "An unexpectedly lovely moment…"),
            ("Etwas, das ich mir heute selbst gegeben habe …", "Something I gave myself today…"),
            ("Ein Grund, heute kurz stolz zu sein …", "One reason to feel briefly proud today…"),
            ("Etwas, das ich nicht selbstverständlich nehmen möchte …", "Something I don’t want to take for granted…"),
            ("Der freundlichste Teil meines Tages …", "The kindest part of my day…"),
        ]
    )

    private static func make(
        prefix: String,
        pairs: [(String, String)]
    ) -> [RelationshipSupportPrompt] {
        pairs.enumerated().map { index, pair in
            RelationshipSupportPrompt(
                id: "\(prefix)-\(index + 1)",
                text: LText(de: pair.0, en: pair.1)
            )
        }
    }
}
