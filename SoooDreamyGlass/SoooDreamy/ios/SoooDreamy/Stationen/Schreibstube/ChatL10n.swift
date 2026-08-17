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
        "chat.emptySubtitle": LText(de: "Schreib {name} die erste Nachricht — oder schick direkt einen Liebesbrief",
                                    en: "Send {name} the first message — or go straight for a love letter"),
        "chat.empty.action": LText(de: "Erste Nachricht schreiben", en: "Write the first message"),

        // History load failed — an honest state instead of a fake-empty chat.
        "chat.history.failed.title": LText(de: "Verlauf konnte nicht laden",
                                           en: "Couldn't load the history"),
        "chat.history.failed.message": LText(de: "Das hat gerade nicht geklappt — versuch es gleich noch einmal.",
                                             en: "That didn't work just now — try again in a moment."),
        "chat.history.offline.title": LText(de: "Gerade keine Verbindung", en: "No connection right now"),
        "chat.history.offline.message": LText(de: "Eure Nachrichten kommen zurück, sobald euer Server wieder erreichbar ist.",
                                              en: "Your messages come back as soon as your server is reachable again."),

        // Input bar. Placeholder measured short (S3 fix): with the three
        // Pult circles plus the field's wand accessory, an iPhone-SE field
        // is ~150 pt — „Schreib etwas Liebes …" clipped to „Schreib etwas
        // Lie…". Both languages now fit unclipped on the smallest width
        // (UITest anchor `Schreib etwas` updated in the same diff).
        "chat.inputPlaceholder": LText(de: "Schreib etwas …", en: "Write something …"),
        "chat.sendA11y": LText(de: "Nachricht senden", en: "Send message"),
        "chat.micA11y": LText(de: "Sprachnachricht aufnehmen", en: "Record a voice note"),
        "chat.letterA11y": LText(de: "Liebesbrief schreiben", en: "Write a love letter"),
        "chat.cancel": LText(de: "Abbrechen", en: "Cancel"),
        "chat.queued": LText(de: "Wartet auf Verbindung", en: "Waiting for connection"),
        "chat.sendShelved": LText(
            de: "Eine Nachricht wurde vom Server abgelehnt — sie bleibt gespeichert und du kannst es später nochmal versuchen.",
            en: "The server rejected one message — it stays saved so you can try again later."
        ),
        "chat.queuedA11y": LText(de: "Nachricht sicher gespeichert und zum Senden vorgemerkt",
                                 en: "Message saved safely and queued to send"),

        // Siegelpresse — ONE menu bundling the timed-delivery entries
        // (ENTSCHEID §4.2). The target sheets exist elsewhere; these are
        // only the entry labels (max one Post word per line).
        "chat.siegelpresse.a11y": LText(de: "Siegelpresse", en: "Seal press"),
        "chat.siegelpresse.zeitpost": LText(de: "Zeitpost aufgeben", en: "Send a timed post"),
        "chat.siegelpresse.kapsel": LText(de: "Kapsel versiegeln", en: "Seal a time capsule"),
        "chat.siegelpresse.tuerchen": LText(de: "Türchen-Kalender bauen", en: "Build a countdown calendar"),
        // One-time explanation of the seal glyph (S3 fix, heart-hint
        // pattern): a quiet caption row until the press is used once.
        "chat.siegelpresse.hint": LText(
            de: "Die Siegelpresse bündelt Zeitpost, Kapsel und Türchen-Kalender.",
            en: "The seal press bundles timed post, capsule and countdown calendar."),
        "chat.siegelpresse.hint.dismissA11y": LText(de: "Hinweis ausblenden",
                                                    en: "Dismiss hint"),

        // Leading rail (regular width)
        "chat.rail.letters": LText(de: "Briefe", en: "Letters"),
        "chat.rail.letters.hint": LText(de: "Für die großen Worte zwischendurch",
                                        en: "For the big words in between"),
        "chat.rail.pinned.empty": LText(de: "Halte eine Nachricht gedrückt, um sie anzupinnen",
                                        en: "Long-press a message to pin it"),
        "chat.rail.photos": LText(de: "Foto-Momente", en: "Photo moments"),
        "chat.rail.photos.empty": LText(de: "Geteilte Fotos landen hier",
                                        en: "Shared photos land here"),

        // Drag & drop (iPad)
        "chat.drop.hint": LText(de: "Loslassen, um das Foto zu senden",
                                en: "Drop to send the photo"),
        "chat.drop.unreadable": LText(de: "Das ließ sich nicht als Bild lesen.",
                                      en: "That couldn't be read as an image."),
        "chat.drop.sending": LText(de: "Foto wird gesendet …", en: "Sending photo …"),
        "chat.effect.a11y": LText(de: "Sendeeffekt oder Sticker wählen", en: "Choose a send effect or sticker"),
        "chat.effect.none": LText(de: "Ohne Effekt", en: "No effect"),
        "chat.effect.hearts": LText(de: "Herzen", en: "Hearts"),
        "chat.effect.snow": LText(de: "Schnee", en: "Snow"),
        "chat.effect.sparkle": LText(de: "Funkelspur", en: "Sparkle trail"),
        "chat.effect.fireworks": LText(de: "Feuerwerk", en: "Fireworks"),
        "chat.effect.slam": LText(de: "Wumms", en: "Slam"),
        "chat.effect.invisible": LText(de: "Unsichtbare Tinte", en: "Invisible ink"),
        "chat.effect.cooldown": LText(
            de: "Effekte machen noch {s} s Pause — die Nachricht geht ohne Effekt raus.",
            en: "Effects need {s} s more — the message will send without one."
        ),
        "chat.effect.chipReady": LText(de: "Effekt: {name}", en: "Effect: {name}"),
        "chat.effect.chipCooldown": LText(de: "{name} — bereit in {s} s",
                                          en: "{name} — ready in {s} s"),
        "chat.effect.clearA11y": LText(de: "Effekt entfernen", en: "Remove effect"),
        "chat.effect.reveal": LText(de: "Antippen zum Enthüllen", en: "Tap to reveal"),
        "chat.sticker": LText(de: "Sticker", en: "Sticker"),
        "chat.sticker.workshop": LText(de: "Sticker-Werkstatt", en: "Sticker Workshop"),
        "chat.sticker.label": LText(de: "Kurzer Text (optional)", en: "Short label (optional)"),
        "chat.sticker.honesty": LText(
            de: "Deine Kritzelei bestimmt Form und Muster. Alles wird prozedural gezeichnet — ohne Foto-Freistellung oder KI.",
            en: "Your doodle determines the shape and pattern. Everything is drawn procedurally — no photo cutout or AI."
        ),
        "chat.sticker.send": LText(de: "Sticker senden", en: "Send sticker"),
        "chat.sticker.clear": LText(de: "Leeren", en: "Clear"),
        "chat.sticker.undo": LText(de: "Rückgängig", en: "Undo"),
        "chat.sticker.recent": LText(de: "Zuletzt gesendet", en: "Recently sent"),
        "chat.sticker.emptyHint": LText(de: "Erst kritzeln — dann senden.",
                                        en: "Scribble first — then send."),
        "chat.sticker.resend": LText(de: "Sticker „{label}“ nochmal senden",
                                     en: "Send sticker “{label}” again"),
        "chat.sticker.canvas.a11y": LText(de: "Zeichenfläche für den Sticker", en: "Sticker drawing canvas"),

        // Voice notes
        "chat.voiceTitle": LText(de: "Sprachnachricht", en: "Voice note"),
        "chat.voiceMessage": LText(de: "Sprachnachricht", en: "Voice note"),
        "chat.voiceRecording": LText(de: "Aufnahme läuft …", en: "Recording …"),
        "chat.voiceReady": LText(de: "Fertig — bereit zum Senden", en: "Done — ready to send"),
        "chat.voiceRecord": LText(de: "Aufnehmen", en: "Record"),
        "chat.voiceStop": LText(de: "Stopp", en: "Stop"),
        "chat.voiceArmedHint": LText(
            de: "Tippe aufs Mikro, wenn du bereit bist — die Aufnahme startet erst dann.",
            en: "Tap the mic when you're ready — recording only starts then."),
        "chat.voicePreview": LText(de: "Vorhören", en: "Preview"),
        "chat.voiceRerecord": LText(de: "Neu aufnehmen", en: "Re-record"),
        "chat.voiceDiscardConfirm": LText(de: "Diese Aufnahme verwerfen?",
                                          en: "Discard this recording?"),
        "chat.voiceDiscard": LText(de: "Verwerfen", en: "Discard"),
        "chat.voiceKeep": LText(de: "Behalten", en: "Keep"),
        "chat.voiceSend": LText(de: "Senden", en: "Send"),
        "chat.voiceSending": LText(de: "Wird gesendet …", en: "Sending …"),
        "chat.voiceRetry": LText(de: "Nochmal versuchen", en: "Try again"),
        "chat.voiceMaxHint": LText(de: "Maximal 2 Minuten", en: "2 minutes max"),
        "chat.voiceTooShort": LText(de: "Ein bisschen zu kurz — versuch's einfach nochmal",
                                    en: "A little too short — just try again"),
        "chat.voiceSent": LText(de: "Sprachnachricht verschickt", en: "Voice note sent"),
        "chat.voiceDeniedTitle": LText(de: "Kein Zugriff aufs Mikrofon", en: "No microphone access"),
        "chat.voiceDeniedSubtitle": LText(de: "Erlaube SoooDreamy in den Einstellungen den Zugriff aufs Mikrofon, dann kannst du hier deine Stimme verschicken.",
                                          en: "Allow SoooDreamy to use the microphone in Settings so you can send your voice here."),
        "chat.voiceScrubA11y": LText(de: "Wiedergabeposition", en: "Playback position"),
        "chat.voiceSpeedA11y": LText(de: "Ändert die Wiedergabegeschwindigkeit",
                                     en: "Changes the playback speed"),
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
        "chat.letterSend": LText(de: "Brief senden", en: "Send letter"),
        "chat.letterSending": LText(de: "Wird verschickt …", en: "Sending …"),
        "chat.letterSent": LText(de: "Dein Brief ist unterwegs", en: "Your letter is on its way"),

        // On-device translation (Welle 7 [27] — Translation framework)
        "chat.translate.action": LText(de: "Übersetzen", en: "Translate"),
        "chat.translate.retry": LText(de: "Nochmal übersetzen", en: "Translate again"),
        "chat.translate.hide": LText(de: "Übersetzung ausblenden", en: "Hide translation"),
        "chat.translate.working": LText(de: "Wird übersetzt …", en: "Translating …"),
        "chat.translate.label": LText(de: "übersetzt", en: "translated"),
        "chat.translate.failed": LText(
            de: "Übersetzen klappt gerade nicht — vielleicht fehlt das Sprachpaket oder die Sprache wird nicht unterstützt.",
            en: "Translation isn't possible right now — the language pack may be missing or the language isn't supported."
        ),

        // On-device voice transcripts (Welle 7 [28] — SpeechAnalyzer)
        "chat.transcript.show": LText(de: "Transkript anzeigen", en: "Show transcript"),
        "chat.transcript.hide": LText(de: "Transkript ausblenden", en: "Hide transcript"),
        "chat.transcript.retry": LText(de: "Nochmal transkribieren", en: "Transcribe again"),
        "chat.transcript.working": LText(de: "Wird transkribiert …", en: "Transcribing …"),
        "chat.transcript.label": LText(de: "automatisch transkribiert", en: "auto-transcribed"),
        "chat.transcript.failed": LText(
            de: "Transkription hat nicht geklappt — versuch es später nochmal.",
            en: "Transcription didn't work — please try again later."
        ),
        "chat.transcript.unsupported": LText(
            de: "Transkription ist für die App-Sprache auf diesem Gerät nicht verfügbar.",
            en: "Transcription isn't available for the app language on this device."
        ),
        "chat.transcript.empty": LText(
            de: "Keine Worte erkannt — vielleicht ist die Aufnahme zu leise.",
            en: "No words recognized — the recording may be too quiet."
        ),

        // Photo messages
        "chat.photoMessage": LText(de: "Foto", en: "Photo"),
        "chat.photoFailed": LText(de: "Foto konnte nicht geladen werden — vielleicht wurde es aus der Galerie gelöscht.",
                                  en: "Couldn't load the photo — it may have been deleted from the gallery."),
        "chat.photoShowInAlbum": LText(de: "Im Album ansehen", en: "View in album"),

        // Context menus & reader
        "chat.you": LText(de: "Du", en: "You"),
        "chat.copy": LText(de: "Kopieren", en: "Copy"),
        "chat.copied": LText(de: "Kopiert", en: "Copied"),
        "chat.deleteMessage": LText(de: "Nachricht löschen", en: "Delete message"),
        "chat.deleted": LText(de: "Nachricht gelöscht", en: "Message deleted"),

        // Letter forwarding (re-send a letter as a brand-new one)
        "chat.forwardLetter": LText(de: "Als neuen Brief senden", en: "Forward as new letter"),

        // Local message pins (personal bookmarks, this device only)
        "chat.pin": LText(de: "Nachricht anpinnen", en: "Pin message"),
        "chat.unpin": LText(de: "Pin lösen", en: "Unpin message"),
        "chat.pinnedBadge": LText(de: "Angepinnt", en: "Pinned"),
        "chat.pinnedMore": LText(de: "+{n} weitere", en: "+{n} more"),
        "chat.pinnedToast": LText(de: "Nachricht angepinnt", en: "Message pinned"),
        "chat.unpinnedToast": LText(de: "Pin gelöst", en: "Pin removed"),
        "chat.pinnedJumpA11y": LText(de: "Zur angepinnten Nachricht springen",
                                     en: "Jump to the pinned message"),
        "chat.pinnedNotLoaded": LText(de: "Die angepinnte Nachricht ist weiter oben — lade oben ältere Nachrichten nach.",
                                      en: "The pinned message is further up — pull down at the top to load older messages."),

        // Message edit (own text/letter messages only)
        "chat.editMessage": LText(de: "Nachricht bearbeiten", en: "Edit message"),
        "chat.editTitle": LText(de: "Nachricht bearbeiten", en: "Edit message"),
        "chat.editHint": LText(de: "Dein Schatz sieht ein kleines „(bearbeitet)“ an der Nachricht.",
                               en: "Your sweetheart will see a little “(edited)” on the message."),
        "chat.editSaved": LText(de: "Nachricht bearbeitet", en: "Message edited"),
        "chat.edited": LText(de: "(bearbeitet)", en: "(edited)"),

        // Search (filter over the loaded messages)
        "chat.searchA11y": LText(de: "Nachrichten durchsuchen", en: "Search messages"),
        "chat.searchPlaceholder": LText(de: "Nachrichten durchsuchen …", en: "Search messages …"),
        "chat.searchNoResults.title": LText(de: "Nichts gefunden", en: "No matches"),
        "chat.searchNoResults.subtitle": LText(de: "Kein Treffer für „{query}“ — ältere Nachrichten lädst du oben per Ziehen nach.",
                                               en: "Nothing found for “{query}” — pull down at the top to load older messages."),

        // Read receipts (a11y labels for the bubble checkmarks)
        "chat.receipt.sent": LText(de: "Gesendet", en: "Sent"),
        "chat.receipt.read": LText(de: "Gelesen", en: "Read"),
        "chat.jumpLatest": LText(de: "Zur neuesten Nachricht springen", en: "Jump to latest message"),
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
