import Foundation

/// Chat feature strings (German du-form + English).
enum ChatL10n {
    static let table: [String: LText] = [
        // Screen & status
        "chat.online": LText(de: "online", en: "online"),
        "chat.offline": LText(de: "offline", en: "offline"),
        "chat.statusTyping": LText(de: "schreibt gerade …", en: "typing …"),
        "chat.typing": LText(de: "{name} schreibt", en: "{name} is typing"),
        "chat.today": LText(de: "Heute", en: "Today"),
        "chat.yesterday": LText(de: "Gestern", en: "Yesterday"),
        "chat.emptyTitle": LText(de: "Noch ist es still hier", en: "It's still quiet in here"),
        "chat.emptySubtitle": LText(de: "Schreib {name} die erste Nachricht — oder schick direkt einen Liebesbrief 💌",
                                    en: "Send {name} the first message — or go straight for a love letter 💌"),

        // Input bar
        "chat.inputPlaceholder": LText(de: "Schreib etwas Liebes …", en: "Write something sweet …"),
        "chat.sendA11y": LText(de: "Nachricht senden", en: "Send message"),
        "chat.micA11y": LText(de: "Sprachnachricht aufnehmen", en: "Record a voice note"),
        "chat.letterA11y": LText(de: "Liebesbrief schreiben", en: "Write a love letter"),
        "chat.cancel": LText(de: "Abbrechen", en: "Cancel"),

        // Voice notes
        "chat.voiceTitle": LText(de: "Sprachnachricht", en: "Voice note"),
        "chat.voiceMessage": LText(de: "Sprachnachricht", en: "Voice note"),
        "chat.voiceRecording": LText(de: "Aufnahme läuft …", en: "Recording …"),
        "chat.voiceReady": LText(de: "Fertig — bereit zum Senden", en: "Done — ready to send"),
        "chat.voiceStopSend": LText(de: "Stopp & Senden", en: "Stop & send"),
        "chat.voiceSend": LText(de: "Senden", en: "Send"),
        "chat.voiceSending": LText(de: "Wird gesendet …", en: "Sending …"),
        "chat.voiceRetry": LText(de: "Nochmal versuchen", en: "Try again"),
        "chat.voiceMaxHint": LText(de: "Maximal 2 Minuten", en: "2 minutes max"),
        "chat.voiceTooShort": LText(de: "Ein bisschen zu kurz — versuch's einfach nochmal 🙂",
                                    en: "A little too short — just try again 🙂"),
        "chat.voiceSent": LText(de: "Sprachnachricht verschickt 🎙️", en: "Voice note sent 🎙️"),
        "chat.voiceDeniedTitle": LText(de: "Kein Zugriff aufs Mikrofon", en: "No microphone access"),
        "chat.voiceDeniedSubtitle": LText(de: "Erlaube SoooDreamy in den iOS-Einstellungen den Zugriff aufs Mikrofon, dann kannst du hier deine Stimme verschicken.",
                                          en: "Allow SoooDreamy to use the microphone in iOS Settings so you can send your voice here."),
        "chat.voiceFailedTitle": LText(de: "Aufnahme fehlgeschlagen", en: "Recording failed"),
        "chat.voiceFailedSubtitle": LText(de: "Die Aufnahme konnte nicht gestartet werden. Versuch es gleich nochmal.",
                                          en: "The recording couldn't be started. Please try again in a moment."),

        // Love letters
        "chat.letterBadge": LText(de: "Liebesbrief", en: "Love letter"),
        "chat.letterTitle": LText(de: "Liebesbrief", en: "Love letter"),
        "chat.letterTitlePlaceholder": LText(de: "Titel, z. B. „Für dich“", en: "Title, e.g. “For you”"),
        "chat.letterPlaceholder": LText(de: "Schreib deinem Schatz, was dir am Herzen liegt …",
                                        en: "Tell your sweetheart what's in your heart …"),
        "chat.letterPreview": LText(de: "Vorschau", en: "Preview"),
        "chat.letterUntitled": LText(de: "Für dich", en: "For you"),
        "chat.letterPreviewEmpty": LText(de: "Hier erscheint dein Brief …", en: "Your letter will appear here …"),
        "chat.letterSend": LText(de: "Brief senden 💌", en: "Send letter 💌"),
        "chat.letterSending": LText(de: "Wird verschickt …", en: "Sending …"),
        "chat.letterSent": LText(de: "Dein Brief ist unterwegs 💌", en: "Your letter is on its way 💌")
    ]
}
