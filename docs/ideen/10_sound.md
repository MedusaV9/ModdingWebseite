# MONKEY MONEY — Ideen-Agent 10/20: Sound-Design & Musik-Dramaturgie

Kontext: Jackbox/Buzz-artige Quiz-Show-Party-App. Der Bildschirm (TV/Beamer) ist
die Klangquelle, Handys optional leise. Thema: Money + Affen. Harte Vorgabe:
**KEINE synthetischen/selbst-generierten Sounds** — ausschließlich echte,
CC-lizenzierte Sounds aus dem Internet, lückenlos in CREDITS dokumentiert.

Legende: Aufwand S/M/L · Prio MUST/SHOULD/COULD.
Alle Quellenangaben in Abschnitt C wurden per Web-Recherche (Stand 2026-08)
verifiziert; Lizenz vor dem Commit trotzdem immer auf der Asset-Seite gegenprüfen.

---

## A. SOUND-INVENTAR der Show (Ideen 1–11)

### Idee 1 — Buzzer-Familie: ein unterscheidbarer Buzzer pro Spieler `[M · MUST]`
**Charakter:** Jeder Spieler bekommt bei Join einen festen Buzzer-Klang aus einer
kuratierten Familie — gleiche Länge (~400 ms), gleiche Lautheit, aber klar
unterscheidbares Timbre: z. B. Hupe, Glocke, Boing, Quäk, Holzblock, Gong,
Fahrradklingel, Trillerpfeife. Regel: Unterscheidbarkeit über **Klangfarbe UND
Tonhöhe** (nicht nur Pitch-Shift derselben Datei), damit auch bei Partylärm klar
ist, WER gebuzzert hat. Farbe des Spielers wird auf dem Screen synchron zum
Buzzer geblitzt (Audio+Visual-Kopplung).
**Wo im Flow:** Buzzer-Runden (Schnellraterunde); außerdem als „Identitäts-Sound"
beim Join in der Lobby (einmal kurz anspielen = Sound-Check + Wiedererkennung).
**Quelle:** Kenney „Digital Audio"/„Interface Sounds" (CC0) für die Basis;
OpenGameArt-Suche `horn`, `honk`, `bell`, `boing` (CC0-Filter); Pixabay
`bicycle bell`, `air horn`, `duck quack`.

### Idee 2 — Richtig/Falsch-Stinger-Paar `[S · MUST]`
**Charakter:** RICHTIG = heller, kurzer Aufwärts-Dreiklang oder Glocken-„Ding"
mit Geld-Schimmer (Münzklimpern im Ausklang) — belohnend, max. 1 s. FALSCH =
tiefes, trockenes „Buzz"/Fehlhorn — komisch, nie bestrafend-hart, max. 0,8 s.
Beide müssen als Paar „verwandt" klingen (gleiche Raumtiefe), damit die Show wie
aus einem Guss wirkt.
**Wo im Flow:** Unmittelbar bei Antwort-Auflösung jeder Frage; FALSCH auch beim
Buzzer-Fehlversuch (Spieler buzzert, antwortet falsch → Frage geht weiter).
**Quelle:** OpenGameArt „Point bell" (Brandon75689, OGA-BY 3.0) als
Richtig-Glocke; Kenney „Music Jingles" (CC0) enthält kurze Win/Lose-Jingles;
Pixabay `wrong answer buzzer`.

### Idee 3 — Countdown-Ticker mit Beschleunigung `[M · MUST]`
**Charakter:** Dreiphasig aus EINER Tick-Datei + einer Tock-Datei gebaut
(abspielseitig sequenziert, nicht als lange Datei): Phase 1 (Restzeit > 50 %):
ruhiges Tick alle 1 s. Phase 2 (< 50 %): Tick-Tock alle 0,5 s, leicht höher
gepitcht (+2 Halbtöne). Phase 3 (< 5 s): Doppeltempo + jede Sekunde ein
Herzschlag-Wumms darunter. Bei 0: kurzer Gong/„Zeit-um"-Horn. Wichtig: Ticker
ist ein eigener Audio-Bus, damit er beim Vorlesen der Frage geduckt werden kann
(→ Idee 21).
**Wo im Flow:** Jede zeitbegrenzte Antwortphase; Phase-3-Panik nur in Runden, wo
Hektik gewollt ist (im Finale ggf. schon ab 10 s).
**Quelle:** Pixabay `clock tick`, `timer ticking`; OpenGameArt-Suche `tick`;
BigSoundBank `clock`/`metronome` (CC0). Herzschlag: Pixabay `heartbeat`.

### Idee 4 — Money-Kassen-Kling, skalierend mit Betrag `[S · MUST]`
**Charakter:** Das akustische Markenzeichen der Show („Cha-Ching!").
Drei Ausbaustufen je nach Gewinnhöhe: klein = einzelner Münz-Pling; mittel =
Kassenlade + 2–3 Münzen; groß = Kassenlade + Münzregen (~1,5 s) + kurzer
Jackpot-Glitzer. Der Kling läuft synchron zum hochzählenden Kontostand auf dem
Screen (Zähler-Animation endet exakt mit letztem Münz-Impact).
**Wo im Flow:** Punkte-/Geldvergabe nach jeder Frage; Rundenende-Kontostand;
Jackpot-Momente am Rad.
**Quelle:** Kenney „Casino Audio" (CC0: Chips, Münzen, Karten — Kernpack für das
Money-Thema!); BigSoundBank `cash register` (CC0, ohne Account); Pixabay
`cash register kaching`, `coins drop`.

### Idee 5 — Klau-Sound (Steal) `[M · SHOULD]`
**Charakter:** Frech, schnell, comic-haft: kurzes „Whoosh" (Zugreifen) + Zipper/
Snatch + freches Affen-Keckern hinterher (~1,2 s gesamt). Beim BEKLAUTEN
Spieler-Handy optional ein leiser trauriger Mini-Plopp (persönliches Feedback,
Screen bleibt beim frechen Klau-Sound). Der Klau-Sound darf sich vom
Falsch-Stinger deutlich unterscheiden: Klauen ist Spielmechanik, kein Versagen.
**Wo im Flow:** Klau-/Steal-Mechanik (Punkteklau nach falscher Antwort des
Gegners, Klau-Joker, Finale-Raubzug).
**Quelle:** Whoosh: Pixabay `whoosh snatch`, Kenney „Impact Sounds" (CC0);
Keckern: Pixabay `monkey chatter`/`chimpanzee` (echte Tieraufnahmen);
Wikimedia-Commons-Kategorie zu Affenlauten prüfen.

### Idee 6 — Rad-Ticker (Glücksrad) `[M · SHOULD]`
**Charakter:** Mechanischer Klacker (Zunge schlägt gegen Stifte), pro
Rad-Segment ein Tick — Abspielrate an die Radgeschwindigkeit gekoppelt
(physikbasiert langsamer werdend), die letzten 3–4 Ticks deutlich einzeln
hörbar, dann 0,5 s Stille, dann Ergebnis-Stinger (Kassen-Kling bei Geld,
Posaune bei Niete, Riser bei Sonderfeld). Der ausklingende Ticker ist selbst
das Spannungsinstrument — keine Musik darüberlegen!
**Wo im Flow:** Bonus-Rad zwischen Runden, Kategorien-Rad am Rundenstart,
Bestrafungs-Rad.
**Quelle:** Eine einzelne saubere Klack-Datei reicht (Rate steuert die Engine):
Kenney „UI Audio"/„Interface Sounds" Klicks (CC0); BigSoundBank `ratchet`,
`click` (CC0); Pixabay `wheel of fortune spin`.

### Idee 7 — Auflösungs-Dreiklang: Riser → Stille → Fanfare `[M · MUST]`
**Charakter:** Das dramaturgische Herzstück. (1) Dramatik-Riser: 2–4 s
ansteigender Streicher-/Snare-Roll („Und die richtige Antwort ist…"), (2)
harter Cut in 0,5–1 s ECHTE Stille (kein Bett, kein Ticker — Godot: alle
Musik-Busse muten), (3) Auflösung: Fanfare bei Highlight-Momenten bzw. direkt
der Richtig/Falsch-Stinger bei normalen Fragen. Riser in 2 Längen (2 s Standard,
4 s Finale) vorhalten.
**Wo im Flow:** Vor jeder Auflösung; die lange Variante nur im Finale und bei
„Alle-oder-niemand"-Momenten, sonst nutzt sie sich ab.
**Quelle:** Pixabay `drum roll` + `riser` (dort gibt es ganze
Riser/Hit-Sammlungen, z. B. „Riser Hit sfx"-Serien); Wikimedia-Suche
`drum roll`; Fanfare: OpenGameArt-Suche `fanfare` (CC0-Filter), Kenney
„Music Jingles".

### Idee 8 — Sieger-Jingle & Bestrafungs-Posaune (Sad Trombone) `[S · MUST]`
**Charakter:** Sieger-Jingle: 3–5 s Mini-Hymne mit Money-Flair (Fanfare +
Münzregen-Ausklang), NUR für Runden-/Spielsieg — nie für einzelne Fragen
(Abnutzung!). Bestrafungs-Posaune: das klassische „Wah-wah-wah-waaah" für
Verlierer-Momente, Nieten, 0-Punkte-Runden — Comedy statt Häme; dazu passt
Publikums-Lacher (Idee 10). Beide sind die Meme-Anker der Show.
**Wo im Flow:** Rundensieg/Spielsieg (Jingle); Bestrafungsfeld am Rad, letzter
Platz der Zwischenwertung, verpatzter Klau (Posaune).
**Quelle:** Jingle: Kenney „Music Jingles" (CC0) oder OpenGameArt „Win Jingle"
(Fupi, CC0, viele Instrument-Varianten + MIDI). Posaune: Pixabay
`sad trombone` (ohne Login); der bekannte CC0-Klassiker „fail game over wah wah
sad trombone" von TaranP liegt auf Freesound (Login nötig → nur nutzen, wenn
über login-freien Mirror verfügbar, sonst Pixabay-Variante).

### Idee 9 — Affen-Reaktions-Set (echte Tieraufnahmen) `[M · SHOULD]`
**Charakter:** 5–8 kurze ECHTE Affenlaute als Kommentar-Ebene des „Studio-Affen"
(Maskottchen): Jubel-Kreischen (großer Gewinn), enttäuschtes „Uh-uh" (Fehler),
freches Keckern (Klau), neugieriges „Huh?" (Skurril-Antwort), Brüll-Gorilla
(Finale-Einzug). Wichtig gegen Nerv-Faktor: Affen-Reaktionen sind SELTEN
(max. 1–2 pro Runde, → Idee 23) und immer an Maskottchen-Animation gekoppelt.
**Wo im Flow:** Als Zweitkommentar NACH dem Primär-Stinger (Stinger informiert,
Affe kommentiert), bei Rundenübergängen, im Idle der Lobby ganz vereinzelt.
**Quelle:** Pixabay `monkey`, `chimpanzee scream`, `gorilla` (echte Aufnahmen,
ohne Login); Wikimedia Commons Kategorien zu Primaten-Lauten (PD/CC-BY);
BigSoundBank Tier-Sektion. KEINE Cartoon-Imitate nötig — echte Tiere sind
lustiger und lizenzsauber dokumentierbar.

### Idee 10 — Publikums-Bett: Applaus, Raunen, Lachen, Crickets `[M · SHOULD]`
**Charakter:** Virtuelles Studiopublikum in 3 Applaus-Stufen (höflich ~3 s /
ordentlich ~6 s / Jubel-Sturm ~10 s mit Pfiffen), dazu: Raunen/„Ooooh"
(knappe Fehlentscheidung), Lacher (Posaunen-Momente, witzige Antwort-Optionen),
und als Spezial-Gag „Crickets"-Grillenzirpen bei 0 richtigen Antworten oder
ganz schlechten Scherzen des Hosts. Applaus-Stufe an Leistungsgröße koppeln
(Punkte-Delta), nicht zufällig.
**Wo im Flow:** Rundenenden, Zwischenwertung, Finale-Einzug, Siegerehrung;
Raunen bei Auflösungen mit Überraschungswert (Favorit lag falsch).
**Quelle (Top-Fund):** Wikimedia Commons „Applause i.ogg" (17 s) &
„Applause ii.ogg" (11 s, Auditorium ~500 Personen) — beide Public Domain
(PDSounds), direkt wget-bar; Kategorie „Audio files of applause" (29 Dateien)
und „Sounds of laughing" (29 Dateien, inkl. Laugh-track-Unterkategorie,
„Lachkonserve 1.ogg"!); OpenGameArt „Well Done" (qubodup, seit 2024 CC0,
Applaus+Erfolgs-Mix) und „Free Crowd Cheering Sounds" (Gregor Quendel, 11
Cheering-Varianten). Crickets: Pixabay/BigSoundBank `crickets`.

### Idee 11 — UI-Klick-Familie + Rollenverteilung Screen/Handy `[S · MUST]`
**Charakter:** Eine konsistente Klick-Familie: Auswahl-Tap (neutraler Klick),
Bestätigen (Klick mit Aufwärts-Blip), Zurück (Abwärts-Blip), Einloggen der
Antwort (satter „Lock-in"-Thunk — wichtigster UI-Sound der Show!), Join-Plopp
in der Lobby. Rollenteilung: Handys spielen NUR die leisen taktilen Klicks
(oder nichts, Setting), der Screen spielt den Lock-in-Thunk pro Spieler
öffentlich — „Spieler 3 hat geantwortet!" hörbar für alle, das treibt die
Langsamen an.
**Wo im Flow:** Alle Menüs/Handy-Interaktionen; Lock-in-Thunks während jeder
Antwortphase auf dem Screen.
**Quelle:** Kenney „UI Audio" (50 Sounds) + „Interface Sounds" (100 Sounds),
beide CC0 — deckt die komplette Familie ab, ein Download, eine CREDITS-Zeile.

---

## B. MUSIK-EBENEN (Ideen 12–15)

### Idee 12 — Lobby-Loop: „Monkeys Spinning Monkeys" als Signatur `[S · MUST]`
**Charakter:** Fröhlich-hibbelig, funky, nicht drängend — läuft, während Spieler
joinen und der Host erklärt. Perfekter Kandidat (thematischer Volltreffer!):
**„Monkeys Spinning Monkeys" von Kevin MacLeod** (incompetech.com, CC-BY 3.0,
144 bpm, 2:05, explizit loopable, Flöten + Pizzicato-Streicher, direkt als MP3
wget-bar). Alternativ/zusätzlich „Happy Happy Game Show" (ders., 230 bpm) als
Aufwärm-/Zwischenrunden-Loop. Lobby-Loop bei −12 LUFS-Offset unter Sprache,
Ducking bei Host-Ansagen.
**Wo im Flow:** Lobby/Join-Screen, Regelerklärung, Pausenbild.
**Aufwand:** S (Download + Loop-Punkt setzen + CREDITS-Eintrag).

### Idee 13 — Runden-Bett mit Intensitäts-Stufen (vertikales Layering) `[L · SHOULD]`
**Charakter:** Das Frage-Bett besteht aus 2–3 übereinanderliegenden, synchron
laufenden Loop-Spuren gleicher Länge/BPM: Stufe 1 = nur Bass+Percussion
(Frage wird gelesen), Stufe 2 = + Melodie-Layer (Antwortphase läuft), Stufe 3 =
+ treibende Hi-Hats/Shaker (Restzeit < 33 %, koppelt an Ticker-Phase 2/3 aus
Idee 3). Umsetzung in Godot: alle Layer als synchrone `AudioStreamPlayer` auf
eigenen Bussen starten, Intensität = Bus-Volumes tweenen (kein Neustart, kein
Versatz); Ogg-Loop-Punkte in den Import-Settings. Da wir nicht selbst
produzieren: aus CC-Quellen einen Track wählen, der als Stems/Varianten
vorliegt (OpenGameArt-Suche `loop stems`, `music pack loop`; Kenney „Music
Loops" CC0 bietet zusammenpassende kurze Loops), oder Stufen über
EQ-/Lautstärke-Varianten desselben Loops approximieren (S-Fallback).
**Wo im Flow:** Alle normalen Frage-Runden; Stufenwechsel hart an
Spielzustands-Events (nie zeitgesteuert-schwammig).

### Idee 14 — Finale-Spannung & Siegerehrung `[M · SHOULD]`
**Charakter:** Finale-Bett: dunkler, reduzierter, langsamer Puls (Herzschlag-
Charakter), deutlich leiser als das Runden-Bett — Spannung durch WENIGER, nicht
mehr; vor der letzten Auflösung komplett ausblenden (→ Stille, Idee 22).
Siegerehrung: pompöse, augenzwinkernde Gewinner-Hymne (~30–60 s, darf sich
nach „zu groß für den Anlass" anfühlen — das ist der Witz), darunter
Jubel-Publikum Stufe 3 + Münzregen. Klassik aus Public-Domain-Aufnahmen prüfen
(über Wikimedia „Category:Musopen", z. B. festliche Fanfaren/Märsche — PD ohne
Musopen-Account); Alternativ MacLeod-Katalog `Feel: Epic/Triumphant` (CC-BY).
**Wo im Flow:** Finalrunde (Bett), Sieger-Screen + Konfetti (Hymne).

### Idee 15 — Übergangs-Stinger als „Kapitelmarken" `[S · SHOULD]`
**Charakter:** Kurze musikalische Interpunktion (1–3 s) zwischen Show-Phasen:
Runden-Intro-Sting („Runde 2!"), Kategorien-Reveal-Sting, „Ab ins Finale"-Sting
(dramatischer), Zwischenwertungs-Sting. Diese Stinger geben der Show
TV-Show-Grammatik und erlauben, die Betten zwischen Phasen komplett zu stoppen
(Musik-Reset = Ohren-Erholung, → Idee 23). Alle Stinger aus derselben Quelle/
Klangwelt wählen, damit sie wie eine Show-Verpackung klingen.
**Wo im Flow:** Jeder Phasenwechsel Lobby→Runde→Wertung→Finale→Ehrung.
**Quelle:** Kenney „Music Jingles" (CC0, viele kurze Jingles in konsistenten
Stil-Familien — ideal genau hierfür); OpenGameArt-Suche `stinger`, `jingle`.

---

## C. QUELLEN-RECHERCHE — verifiziert, ohne Login, direkt ladbar (Ideen 16–21)

### Idee 16 — Kenney.nl als CC0-Grundausstattung `[S · MUST]`
**Lizenz:** ALLE Kenney-Audio-Packs sind CC0 (Public Domain), explizit auch
kommerziell, Attribution optional („Support us by crediting Kenney").
**Download-Weg:** kenney.nl → Asset-Seite → Download-Button, ZIP ohne Login;
wget-bar (ZIP-Direktlinks); Spiegel mit direktem Verzeichnis-Listing:
`gamesounds.xyz/?dir=Kenney's Sound Pack` (enthält readme.txt mit
CC0-Bestätigung). Für Godot existiert z. B. `github.com/Calinou/kenney-ui-audio`
(UI Audio als WAV, CC0).
**Was es liefert (Pack-Plan für MONKEY MONEY):**
- **UI Audio** (50): Klicks, Switches → Idee 11.
- **Interface Sounds** (100): Menü-Blips, Confirm/Deny → Idee 11, Buzzer-Basis.
- **Casino Audio**: Chips, Münzen, Karten, Würfel → Money-Kling (Idee 4), Rad.
- **Music Jingles**: kurze Win/Lose/Übergangs-Jingles → Ideen 2, 8, 15.
- **Music Loops**: Loop-Bausteine → Betten-Fallback (Idee 13).
- **Digital Audio** (60) + **Retro Sounds 1/2**: Beeps → Countdown, Buzzer.
- **Impact Sounds** (130): Thunks, Hits → Lock-in-Thunk, Klau-Impact.
- **Voiceover Pack**: englische Announcer-Schnipsel („3, 2, 1, Go!") → COULD.

### Idee 17 — OpenGameArt: Fundliste + Suchstrategie `[M · MUST]`
**Lizenz:** pro Asset ausgewiesen (CC0 / CC-BY 3.0/4.0 / OGA-BY 3.0); in der
Suche nach Lizenz filterbar.
**Download-Weg:** Dateien liegen unter `opengameart.org/sites/default/files/…`
— direkt wget-bar, KEIN Login für Downloads nötig.
**Verifizierte Treffer (Recherche 2026-08):**
1. **„Well Done"** (qubodup) — CC0 (2024 von CC-BY auf CC0 umgestellt) —
   Applaus + Erfolgssound, echte Hackathon-Aufnahme, FLAC 96 kHz + OGG.
2. **„Applause"** (Blender Foundation / Yo Frankie!, hochgeladen von LeeZH) —
   CC-BY — sauberer Applaus-Schnitt als WAV.
3. **„Free Crowd Cheering Sounds"** (Gregor Quendel) — 11 Varianten von
   „strong cheering" bis „soft cheering + chatter" — Lizenz auf Seite prüfen.
4. **„Point bell"** (Brandon75689) — OGA-BY 3.0 — perfekte
   Richtig-Antwort-Glocke.
5. **„Win Jingle"** (Fupi) — Sieg-Jingle mit vielen Instrument-Varianten im
   ZIP + MIDI.
6. **„512 Sound Effects (8-bit style)"** (Juhani Junkala / SubspaceAudio) —
   CC0 — Riesenfundus für Blips/Ticks/Buzzer-Varianten.
**Suchbegriffe, die hier tragen:** `buzzer`, `applause`, `crowd`, `cheer`,
`jingle`, `fanfare`, `coin`, `cash`, `drum roll`, `tick`, `stinger`,
`game show`, `slide whistle` — immer mit Lizenz-Filter CC0/CC-BY.

### Idee 18 — Wikimedia Commons für Publikum & PD-Klassik `[S · MUST]`
**Lizenz:** pro Datei ausgewiesen; die Applaus-/Lach-Klassiker sind Public
Domain (PDSounds-Import), Musopen-Uploads PD.
**Download-Weg:** komplett login-frei und stabil wget-bar über
`https://commons.wikimedia.org/wiki/Special:FilePath/<Dateiname>` (leitet auf
upload.wikimedia.org um) — die verlässlichste wget-Quelle in dieser Liste.
**Was es liefert:**
- **„Applause i.ogg"** (17 s, PD) und **„Applause ii.ogg"** (11 s, Auditorium
  mit ~500 Personen, PD) — sofort einsetzbare Publikums-Grundlage.
- **„Laughter.ogg"** (16 s, PD) + Kategorie „Sounds of laughing" (29 Dateien,
  darunter „Lachkonserve 1.ogg" und eine „Laugh track"-Unterkategorie).
- Kategorie **„Audio files of applause"** (29 Dateien, vom Kleintheater bis
  Concertgebouw — verschiedene Saalgrößen = Applaus-Stufen für Idee 10).
- Kategorie **„Musopen"**: Public-Domain-Klassikaufnahmen OHNE
  Musopen-Account (Musopen.org selbst verlangt Login + max. 5 Downloads/Tag —
  über Commons umgehen wir das sauber).

### Idee 19 — Incompetech (Kevin MacLeod) für alle Musik-Betten `[S · MUST]`
**Lizenz:** CC-BY 3.0/4.0 — Attribution PFLICHT, Credit-Formel wird pro Track
mitgeliefert („<Titel> Kevin MacLeod (incompetech.com), Licensed under Creative
Commons: By Attribution …") → 1:1 in CREDITS.md übernehmen.
**Download-Weg:** direkte MP3-URLs ohne Login, wget-bar, Muster:
`https://incompetech.com/music/royalty-free/mp3-royaltyfree/<Titel>.mp3`
(verifiziert für „Monkeys Spinning Monkeys").
**Was es liefert (Track-Shortlist):** „Monkeys Spinning Monkeys" (Lobby,
loopable, Affen-Thema!), „Happy Happy Game Show" (Blues-Funk, 230 bpm,
Aufwärmrunde; „uncompressed download comes with a perfectly loopable track"),
„Sneaky Snitch" (Klau-/Schleich-Phasen), Filter `Feel: Humorous/Epic` für
Posaunen-Momente und Finale. **Achtung Recherche-Fund:** FreePD.com (die
CC0-Schwesterseite) ist OFFIZIELL GESCHLOSSEN (Site Closed, 2026) — alte
Empfehlungslisten, die FreePD nennen, sind veraltet; Incompetech direkt nutzen.

### Idee 20 — Pixabay-Audio als Breiten-Fundus (mit Lizenz-Fußnote) `[S · SHOULD]`
**Lizenz:** „Pixabay Content License" — KEIN Creative Commons! Kostenlos, auch
kommerziell, keine Attribution nötig; ABER: keine Standalone-Redistribution
(Datei „as-is" weiterverteilen ist untersagt). Konsequenz für uns: Nutzung in
der App ist gedeckt; da unser Repo öffentlich Assets enthält, Pixabay-Dateien
bevorzugt für Kandidaten nutzen, die wir ohnehin schneiden/bearbeiten (Bearbeitung
= „creative effort", plus CREDITS-Vermerk „bearbeitet"). Im Zweifel CC0-Quelle
(Kenney/Wikimedia/BigSoundBank) vorziehen.
**Download-Weg:** Sound-Effects-Downloads (MP3) ohne Account über den
„Free Download"-Button (nur Foto/Video in Vollauflösung verlangen Login);
die CDN-URLs sind dynamisch → nicht stabil wget-bar, Download manuell, Datei
committen, Link zur Asset-Seite in CREDITS.
**Was es liefert:** 120.000+ SFX — die Lücken-Füller-Quelle: `sad trombone`,
`riser`, `whoosh`, `monkey scream`, `heartbeat`, `crickets`, `drum roll`,
`stadium crowd`, `kaching` — praktisch alles aus Abschnitt A ist hier als
Kandidat vorhanden.

### Idee 21 — BigSoundBank als CC0-Geheimtipp + Negativ-Liste `[S · SHOULD]`
**BigSoundBank.com** (Joseph Sardin): CC0/PD-äquivalent, FAQ bestätigt
ausdrücklich „without creating an account"; WAV/MP3-Direktlinks wget-bar;
liefert: Kassen/Supermarkt-Atmos, Klicks/Ratchets (Rad-Ticker), Glocken,
Menschenmengen, Tiere — professionell aufgenommen und UCS-kategorisiert.
**Negativ-Liste (Recherche-Ergebnis, spart anderen Agents Zeit):**
- **Freesound.org**: Login für JEDEN Download → raus (auch wenn dort bekannte
  CC0-Perlen liegen wie TaranP „sad trombone" oder Zott820 „cash register" —
  nur nutzbar, falls über login-freie Mirrors erreichbar).
- **Musopen.org**: Account + 5 Downloads/Tag → stattdessen Wikimedia-Kategorie
  „Musopen" (Idee 18).
- **FreePD.com**: offline/geschlossen.
- **ZapSplat/Uppbeat**: Login + eigene Lizenz mit Attribution im Free-Tier.
- **YouTube Audio Library**: Google-Konto + eigene Lizenz, nicht CC → raus.

---

## D. DRAMATURGIE-REGELN (Ideen 22–24)

### Idee 22 — Ducking-Hierarchie: Sprache > Stinger > Ticker > Musik `[M · MUST]`
**Regelwerk:** Feste Prioritätskette. Wenn die Frage vorgelesen wird (TTS oder
Host-Modus): Musik-Bett um ~9–12 dB ducken, Ticker um ~6 dB, Publikums-Betten
pausieren. Wenn ein Stinger feuert (richtig/falsch/Kassen-Kling): Bett kurz um
6 dB absenken (Sidechain-Gefühl), in 300 ms zurück. Umsetzung in Godot über
Bus-Architektur (Master → Music / SFX / Ticker / Voice) + Volume-Tweens auf
Events — kein echtes Sidechain nötig. Effekt: Die Show klingt „gemischt" wie
TV, nicht wie ein Soundboard, auf dem alles gleichzeitig hupt.
**Wo im Flow:** global, ab der ersten implementierten Runde.

### Idee 23 — Stille als Werkzeug (der Günther-Jauch-Moment) `[S · MUST]`
**Regelwerk:** Vor JEDER wichtigen Auflösung 0,5–1,5 s komplette Stille (alle
Busse), skaliert mit Fallhöhe: normale Frage 0,5 s, Rundenentscheidung 1 s,
Finale bis 2,5 s (plus Riser davor, Idee 7). Zusatzregeln: (a) Nach großen
Jubel-Momenten 2–3 s OHNE neue Musik — Raum fürs echte Wohnzimmer-Gelächter;
(b) Finale-Bett endet VOR der letzten Antwort, nicht erst bei der Auflösung;
(c) Stille niemals durch UI-Klicks verunreinigen (Eingaben in der Stille-Phase
stumm puffern). Stille ist der billigste (0 Assets!) und stärkste
Dramaturgie-Effekt der ganzen Liste.
**Wo im Flow:** Auflösungen, Zwischenwertungen, Sieger-Reveal.

### Idee 24 — Anti-Nerv-Paket: Sparsamkeit, Varianz, Rollen-Lautstärke `[M · MUST]`
**Regelwerk in vier Teilen:**
1. **Sound-Budget:** pro Ereignisklasse ein Cooldown (Affen-Reaktion max. alle
   90 s; Publikums-Lacher max. 1×/Frage; Sieger-Jingle NUR bei Runden-/
   Spielsieg). Faustregel: Jeder Sound, der öfter als ~20×/Abend erklingt
   (Klicks, Ticks), muss unauffällig sein; auffällige Sounds müssen selten sein.
2. **Varianz ohne Synthese:** häufige Sounds über Godots
   `AudioStreamRandomizer` mit ±3–5 % Random-Pitch/Volume abspielen (erlaubt —
   das ist Wiedergabe-Variation echter Aufnahmen, keine Sound-Generierung) und
   wo möglich 2–3 echte Aufnahme-Varianten round-robin rotieren.
3. **Lautstärke-Settings pro Rolle:** Screen/Host-Gerät = volle Mische mit
   getrennten Slidern für Musik / SFX / Publikum+Affen (persistiert);
   Handys = eigener Regler nur für UI-Feedback, Default LEISE + „Stumm auf
   Handys"-Toggle prominent in der Lobby („Bildschirm macht den Sound" ist
   Konzept-Kern); zusätzlich ein „Späti-Modus" (Nachtruhe): globale Absenkung
   −12 dB + Publikum/Posaune aus, Sprache/Stinger bleiben.
4. **Loudness-Hygiene:** alle Assets beim Einpflegen auf gemeinsames
   Lautheitsziel normalisieren (z. B. Stinger ≈ −16 LUFS, Betten ≈ −24 LUFS),
   damit kein CC-Fundstück aus der Reihe brüllt (einmalig per ffmpeg
   `loudnorm` beim Asset-Import ins Repo, nicht zur Laufzeit).

---

## E. CREDITS-SYSTEM (Idee 25)

### Idee 25 — CREDITS.md mit Manifest + wget-Skript + CI-Gate `[M · MUST]`
**Format (eine Zeile pro Datei, Tabelle in `GOOBY-GODOT/assets/audio/CREDITS.md`):**

```markdown
# Audio-Credits — MONKEY MONEY
Alle Sounds stammen aus externen CC-/PD-Quellen (keine Eigen-Synthese).
"Änderungen": geschnitten/normalisiert/gepitcht durch uns (CC-BY verlangt diesen Hinweis).

| Datei | Verwendung | Quelle | Autor | Lizenz | Link | Änderungen |
|---|---|---|---|---|---|---|
| sfx/applause_big.ogg | Publikum Stufe 3 | Wikimedia Commons | thore (PDSounds) | Public Domain | https://commons.wikimedia.org/wiki/File:Applause_ii.ogg | gekürzt, −16 LUFS |
| music/lobby_loop.mp3 | Lobby-Loop | incompetech.com | Kevin MacLeod | CC-BY 3.0 | https://incompetech.com/... | Loop-Punkt gesetzt |
| ui/click_soft.ogg | UI-Tap | Kenney UI Audio | Kenney | CC0 | https://kenney.nl/assets/ui-audio | keine |
```

**Dazu zwei Werkzeuge:**
1. **Manifest-getriebener Download:** `tools/audio/sound_manifest.json` mit
   `{ziel_datei, url, sha256, lizenz, autor, quelle_link}` pro Asset +
   `tools/audio/fetch_sounds.sh` (wget + sha256-Check). Reproduzierbar,
   review-bar, und die CREDITS.md kann daraus GENERIERT werden (eine Quelle der
   Wahrheit, kein Drift zwischen Datei und Credit). Für Quellen ohne stabile
   URL (Pixabay, Idee 20) wird die Datei committet und im Manifest
   `"url": "manual", "seite": <Asset-Link>` vermerkt.
2. **CI-Gate (in preflight.sh einhängbar):** Skript prüft (a) jede Audiodatei
   unter `assets/audio/` hat eine CREDITS-/Manifest-Zeile, (b) jede
   CREDITS-Zeile zeigt auf eine existierende Datei, (c) Lizenzfeld ∈
   {CC0, CC-BY 3.0, CC-BY 4.0, Public Domain, OGA-BY 3.0, Pixabay Content
   License}, (d) bei CC-BY/OGA-BY ist das Autor- und Link-Feld nicht leer.
   Damit ist die Kernvorgabe („alle Sounds echt + dokumentiert") technisch
   erzwungen statt nur vereinbart.

---

## Abschluss: Top-5 (interne Wertung)

1. **Idee 7 + 23 — Auflösungs-Dreiklang & Stille:** größter Show-Effekt,
   minimale Asset-Kosten; Stille kostet nichts und trägt die ganze Dramaturgie.
2. **Idee 25 — CREDITS-System mit Manifest + CI-Gate:** macht die harte
   Lizenz-Vorgabe erzwingbar und reproduzierbar statt hoffnungsbasiert.
3. **Idee 1 — Buzzer-Familie pro Spieler:** DAS Partyspiel-Feature; Timbre-
   statt Pitch-Unterscheidung ist die entscheidende Design-Regel.
4. **Idee 4 — skalierender Money-Kassen-Kling:** akustisches Markenzeichen,
   Kenney „Casino Audio" liefert es CC0 frei Haus.
5. **Idee 22 + 24 — Ducking-Hierarchie & Anti-Nerv-Paket:** der Unterschied
   zwischen „TV-Show-Mische" und „nervigem Soundboard" nach Abend 2.

**Die 3 besten Quellen:** Kenney.nl (CC0, 8+ passende Packs, ein Download);
Wikimedia Commons (PD-Applaus/Lachen/Klassik, stabilste wget-URLs via
Special:FilePath); Incompetech/Kevin MacLeod (CC-BY, direkte MP3-URLs, inkl.
thematischem Volltreffer „Monkeys Spinning Monkeys").
