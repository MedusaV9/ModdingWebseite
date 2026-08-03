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
        "chat.letterSent": LText(de: "Dein Brief ist unterwegs 💌", en: "Your letter is on its way 💌"),

        // Context menus & reader
        "chat.you": LText(de: "Du", en: "You"),
        "chat.copy": LText(de: "Kopieren", en: "Copy"),
        "chat.copied": LText(de: "Kopiert!", en: "Copied!"),
        "chat.read": LText(de: "Lesen", en: "Read"),
        "chat.react": LText(de: "Reagieren …", en: "React …"),
        "chat.reactWith": LText(de: "Mit {emoji} reagieren", en: "React with {emoji}"),
        "chat.readerClose": LText(de: "Schließen", en: "Close"),
        "chat.readerFrom": LText(de: "Von {name}", en: "From {name}"),

        // "Öffnen wenn …" seals — chip labels
        "chat.sealPickerTitle": LText(de: "Versiegeln — öffnen, wenn …", en: "Seal it — open when …"),
        "chat.sealNone": LText(de: "Ohne Siegel", en: "No seal"),
        "chat.sealCustom": LText(de: "Eigenes …", en: "Custom …"),
        "chat.sealCustomPlaceholder": LText(de: "Dein Moment, z. B. „wenn du Kuchen isst“",
                                            en: "Your moment, e.g. “when you're eating cake”"),
        "chat.seal.sad": LText(de: "Traurig", en: "Sad"),
        "chat.seal.missme": LText(de: "Sehnsucht", en: "Missing me"),
        "chat.seal.happy": LText(de: "Freude", en: "Celebrating"),
        "chat.seal.badday": LText(de: "Mieser Tag", en: "Bad day"),
        "chat.seal.night": LText(de: "Schlaflos", en: "Sleepless"),
        "chat.seal.anniversary": LText(de: "Jahrestag", en: "Anniversary"),

        // Seal sentences (on the sealed envelope & seal chips)
        "chat.sealLine.sad": LText(de: "Öffne mich, wenn du traurig bist",
                                   en: "Open me when you're feeling sad"),
        "chat.sealLine.missme": LText(de: "Öffne mich, wenn du mich vermisst",
                                      en: "Open me when you're missing me"),
        "chat.sealLine.happy": LText(de: "Öffne mich, wenn du etwas zu feiern hast",
                                     en: "Open me when you've got something to celebrate"),
        "chat.sealLine.badday": LText(de: "Öffne mich nach einem richtig miesen Tag",
                                      en: "Open me after a really rough day"),
        "chat.sealLine.night": LText(de: "Öffne mich, wenn du nachts nicht schlafen kannst",
                                     en: "Open me when you can't sleep at night"),
        "chat.sealLine.anniversary": LText(de: "Öffne mich an unserem Jahrestag",
                                           en: "Open me on our anniversary"),
        "chat.sealLine.custom": LText(de: "Öffne mich: „{text}“", en: "Open me: “{text}”"),
        "chat.sealLine.generic": LText(de: "Öffne mich im richtigen Moment",
                                       en: "Open me when the moment is right"),

        // Sealed envelope card
        "chat.sealedTitle": LText(de: "Ein versiegelter Liebesbrief", en: "A sealed love letter"),
        "chat.sealedOpen": LText(de: "Öffnen", en: "Open")
    ]
}
