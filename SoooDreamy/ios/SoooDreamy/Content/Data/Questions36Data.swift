// Questions36Data.swift
// The classic "36 questions to fall in love" (Arthur Aron et al., 1997),
// in 3 sets of 12. Standard English wording, faithful German translation.

import Foundation

extension ContentPack {
    static let questions36: [Question36] = [
        Question36(id: 1, set: 1, text: LText(de: "Wenn du dir irgendeinen Menschen auf der Welt aussuchen könntest: Wen würdest du gern zum Abendessen einladen?", en: "Given the choice of anyone in the world, whom would you want as a dinner guest?")),
        Question36(id: 2, set: 1, text: LText(de: "Würdest du gern berühmt sein? Auf welche Weise?", en: "Would you like to be famous? In what way?")),
        Question36(id: 3, set: 1, text: LText(de: "Übst du manchmal vorher, was du sagen willst, bevor du telefonierst? Warum?", en: "Before making a telephone call, do you ever rehearse what you are going to say? Why?")),
        Question36(id: 4, set: 1, text: LText(de: "Wie sieht ein „perfekter“ Tag für dich aus?", en: "What would constitute a \"perfect\" day for you?")),
        Question36(id: 5, set: 1, text: LText(de: "Wann hast du zuletzt für dich allein gesungen? Und wann für jemand anderen?", en: "When did you last sing to yourself? To someone else?")),
        Question36(id: 6, set: 1, text: LText(de: "Wenn du 90 Jahre alt werden könntest und für die letzten 60 Jahre deines Lebens entweder den Geist oder den Körper eines 30-Jährigen behalten dürftest: Was würdest du wählen?", en: "If you were able to live to the age of 90 and retain either the mind or body of a 30-year-old for the last 60 years of your life, which would you want?")),
        Question36(id: 7, set: 1, text: LText(de: "Hast du eine heimliche Ahnung, wie du sterben wirst?", en: "Do you have a secret hunch about how you will die?")),
        Question36(id: 8, set: 1, text: LText(de: "Nenne drei Dinge, die du und dein Partner offenbar gemeinsam habt.", en: "Name three things you and your partner appear to have in common.")),
        Question36(id: 9, set: 1, text: LText(de: "Wofür in deinem Leben bist du am dankbarsten?", en: "For what in your life do you feel most grateful?")),
        Question36(id: 10, set: 1, text: LText(de: "Wenn du irgendetwas daran ändern könntest, wie du aufgewachsen bist: Was wäre es?", en: "If you could change anything about the way you were raised, what would it be?")),
        Question36(id: 11, set: 1, text: LText(de: "Nimm dir vier Minuten Zeit und erzähle deinem Partner deine Lebensgeschichte so ausführlich wie möglich.", en: "Take four minutes and tell your partner your life story in as much detail as possible.")),
        Question36(id: 12, set: 1, text: LText(de: "Wenn du morgen mit einer neuen Eigenschaft oder Fähigkeit aufwachen könntest: Welche wäre das?", en: "If you could wake up tomorrow having gained any one quality or ability, what would it be?")),
        Question36(id: 13, set: 2, text: LText(de: "Wenn eine Kristallkugel dir die Wahrheit über dich selbst, dein Leben, die Zukunft oder irgendetwas anderes verraten könnte: Was würdest du wissen wollen?", en: "If a crystal ball could tell you the truth about yourself, your life, the future, or anything else, what would you want to know?")),
        Question36(id: 14, set: 2, text: LText(de: "Gibt es etwas, wovon du schon lange träumst? Warum hast du es noch nicht getan?", en: "Is there something that you've dreamed of doing for a long time? Why haven't you done it?")),
        Question36(id: 15, set: 2, text: LText(de: "Was ist die größte Errungenschaft deines Lebens?", en: "What is the greatest accomplishment of your life?")),
        Question36(id: 16, set: 2, text: LText(de: "Was schätzt du an einer Freundschaft am meisten?", en: "What do you value most in a friendship?")),
        Question36(id: 17, set: 2, text: LText(de: "Was ist deine kostbarste Erinnerung?", en: "What is your most treasured memory?")),
        Question36(id: 18, set: 2, text: LText(de: "Was ist deine schlimmste Erinnerung?", en: "What is your most terrible memory?")),
        Question36(id: 19, set: 2, text: LText(de: "Wenn du wüsstest, dass du in einem Jahr plötzlich sterben wirst: Würdest du irgendetwas an deinem jetzigen Leben ändern? Warum?", en: "If you knew that in one year you would die suddenly, would you change anything about the way you are now living? Why?")),
        Question36(id: 20, set: 2, text: LText(de: "Was bedeutet Freundschaft für dich?", en: "What does friendship mean to you?")),
        Question36(id: 21, set: 2, text: LText(de: "Welche Rolle spielen Liebe und Zuneigung in deinem Leben?", en: "What roles do love and affection play in your life?")),
        Question36(id: 22, set: 2, text: LText(de: "Nennt abwechselnd etwas, das ihr als positive Eigenschaft eures Partners betrachtet. Insgesamt fünf Dinge.", en: "Alternate sharing something you consider a positive characteristic of your partner. Share a total of five items.")),
        Question36(id: 23, set: 2, text: LText(de: "Wie eng und warmherzig ist deine Familie? Hast du das Gefühl, dass deine Kindheit glücklicher war als die der meisten anderen?", en: "How close and warm is your family? Do you feel your childhood was happier than most other people's?")),
        Question36(id: 24, set: 2, text: LText(de: "Wie empfindest du dein Verhältnis zu deiner Mutter?", en: "How do you feel about your relationship with your mother?")),
        Question36(id: 25, set: 3, text: LText(de: "Bildet jeweils drei wahre „Wir“-Sätze. Zum Beispiel: „Wir sind beide in diesem Raum und fühlen …“", en: "Make three true \"we\" statements each. For instance, \"We are both in this room feeling ...\"")),
        Question36(id: 26, set: 3, text: LText(de: "Vervollständige diesen Satz: „Ich wünschte, ich hätte jemanden, mit dem ich … teilen könnte.“", en: "Complete this sentence: \"I wish I had someone with whom I could share ...\"")),
        Question36(id: 27, set: 3, text: LText(de: "Wenn du mit deinem Partner eng befreundet werden wolltest: Was müsste er oder sie unbedingt über dich wissen?", en: "If you were going to become a close friend with your partner, please share what would be important for him or her to know.")),
        Question36(id: 28, set: 3, text: LText(de: "Sag deinem Partner, was du an ihm oder ihr magst. Sei diesmal ganz ehrlich und sag auch Dinge, die du jemandem, den du gerade erst kennengelernt hast, vielleicht nicht sagen würdest.", en: "Tell your partner what you like about them; be very honest this time, saying things that you might not say to someone you've just met.")),
        Question36(id: 29, set: 3, text: LText(de: "Erzähle deinem Partner von einem peinlichen Moment in deinem Leben.", en: "Share with your partner an embarrassing moment in your life.")),
        Question36(id: 30, set: 3, text: LText(de: "Wann hast du zuletzt vor einem anderen Menschen geweint? Und wann für dich allein?", en: "When did you last cry in front of another person? By yourself?")),
        Question36(id: 31, set: 3, text: LText(de: "Sag deinem Partner, was du jetzt schon an ihm oder ihr magst.", en: "Tell your partner something that you like about them already.")),
        Question36(id: 32, set: 3, text: LText(de: "Was — wenn überhaupt etwas — ist zu ernst, um darüber Witze zu machen?", en: "What, if anything, is too serious to be joked about?")),
        Question36(id: 33, set: 3, text: LText(de: "Wenn du heute Abend sterben würdest, ohne noch einmal mit jemandem sprechen zu können: Was würdest du am meisten bereuen, jemandem nicht gesagt zu haben? Warum hast du es dieser Person noch nicht gesagt?", en: "If you were to die this evening with no opportunity to communicate with anyone, what would you most regret not having told someone? Why haven't you told them yet?")),
        Question36(id: 34, set: 3, text: LText(de: "Dein Haus mit allem, was du besitzt, fängt Feuer. Nachdem du deine Liebsten und deine Haustiere gerettet hast, bleibt dir Zeit für einen letzten sicheren Gang, um ein einziges Ding zu retten. Was wäre es? Warum?", en: "Your house, containing everything you own, catches fire. After saving your loved ones and pets, you have time to safely make a final dash to save any one item. What would it be? Why?")),
        Question36(id: 35, set: 3, text: LText(de: "Der Tod welches Menschen aus deiner Familie würde dich am meisten erschüttern? Warum?", en: "Of all the people in your family, whose death would you find most disturbing? Why?")),
        Question36(id: 36, set: 3, text: LText(de: "Erzähle von einem persönlichen Problem und bitte deinen Partner um Rat, wie er oder sie damit umgehen würde. Frag deinen Partner außerdem, wie du in Bezug auf dieses Problem auf ihn oder sie wirkst.", en: "Share a personal problem and ask your partner's advice on how he or she might handle it. Also, ask your partner to reflect back to you how you seem to be feeling about the problem you have chosen."))
    ]
}
