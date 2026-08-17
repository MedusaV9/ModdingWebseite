# Siri, Shortcuts & Automationen — SoooDreamy überall

> **Deutsch (Kurzfassung):** Der Sideload-Build hat kein APNs — Shortcuts-
> Automationen sind deshalb der einzige verlässliche Kanal, auf dem sich die
> App „von selbst meldet". Diese Seite listet die Siri-Sätze und die fünf
> kopierfertigen Automations-Rezepte (Wecker, Ankunft, NFC, Ladegerät,
> Fokus-Filter). Alles läuft lokal auf dem iPhone — keine Cloud, kein
> Standort-Tracking in der App.

## Siri phrases (App Shortcuts)

After installing (and opening the app once so Siri learns the partner's
name), these work hands-free. `[Name]` is your partner's real name —
zero configuration, there is exactly one person it could be:

| Say | What happens |
|---|---|
| „Schick **[Name]** ein Herz mit SoooDreamy" | sends a heartbeat touch |
| „Schick **einen Kuss** mit SoooDreamy" | touch type directly in the phrase (Kuss, Umarmung, Kitzeln, …) |
| „**Gute Nacht** mit SoooDreamy" | the whole evening ritual: sleep presence (8 h) + goodnight pulse + night check-in, and the pulse card on the lock screen says goodbye with the day's summary |
| „**Guten Morgen** mit SoooDreamy" | ends sleep mode, sets the morning check-in and tells you how your partner is doing |
| „**Wie geht es [Name]** in SoooDreamy" | mood + energy + presence + online in one sentence |
| „Schick **Gute Nacht** mit SoooDreamy" (Puls) | a thinking-of-you pulse — a felt haptic pattern, not a notification |
| „**Setz mich auf Schlafen** in SoooDreamy" / „**Ich bin wieder da** in SoooDreamy" | presence building blocks for your own automations |

Siri only learns `[Name]` after the app ran once post-pairing (the app
re-donates the shortcut parameters whenever the name changes).

## Automation recipes (Kurzbefehle app → Automation tab)

Automations replace the pushes a sideload can never receive. All of these
run **without confirmation** when you toggle „Sofort ausführen" / "Run
Immediately".

### 1. Wecker aus → Guten Morgen (the missing morning push)

*Neue Automation → „Wecker" → „Wird gestoppt" → App: SoooDreamy →
„Guten Morgen"*. When you stop your alarm, the morning check-in is done
and Siri tells you whether your partner is already awake.

### 2. Ankunft zuhause → Bin-daheim-Puls

*Neue Automation → „Ankommen" → your home → App: SoooDreamy → „Puls senden"
(Herzschlag)*. The classic commuter ritual — the location trigger runs
locally on your phone; the app itself never sees your location.

### 3. NFC-Tag am Nachttisch → Gute Nacht

*Neue Automation → „NFC" → scan any 30-cent NFC sticker → App: SoooDreamy →
„Gute Nacht"*. A physical good-night button on the nightstand. Works
best as a pair of tags — one on each bedside table.

### 4. Ladegerät nach 21 Uhr → Gute Nacht

*Neue Automation → „Ladegerät" → „Wird angeschlossen" → Kurzbefehl mit
„Wenn"-Baustein (aktuelle Uhrzeit ≥ 21:00) → „Gute Nacht"*. Catches
everyone who doesn't use an alarm or NFC tag: plugging in at night IS the
good-night moment. (The time filter lives inside the shortcut — automations
can't filter by hour themselves.)

### 5. Schlafen-Fokus → Presence (kein Kurzbefehl nötig!)

The zero-config option: *Einstellungen → Fokus → Schlafen → Filter
hinzufügen → SoooDreamy → Presence: „Schlafen"*. From then on iOS itself
sets your couple presence with every focus change — no shortcut, no
automation, no forgetting. Works for the Arbeits-Fokus too (Presence:
„Fokus"). Turning the focus off clears only what the filter set — a
manually chosen presence survives.

## Control Center / Lock Screen / Action Button

The app ships controls (iOS 18+ style, add via Control Center „+" or
replace a lock-screen button): Herzklopfen, Denk an dich, Date-Night,
Bedürfnis-Knopf — and new in W7:

- **Gute Nacht** — the whole evening ritual in one tap, right next to
  where the flashlight used to be.
- **Schlafmodus** — the only toggle with real state: it shows whether
  sleep mode is actually on and flips it directly.

## Honesty notes

- Every intent needs the app-group-mirrored credentials — after a sign-out
  the dialogs say so instead of failing silently.
- Pulse sends respect the server's 30-second limit; the „too soon" answer
  is friendly, not an error.
- The good-night ritual reports partial success honestly („Fast geschafft:
  Schlafmodus an … der Rest hat nicht geklappt") and always names a way out.
