# MONKEY MONEY — Ideen-Agent 12/20: Kategorien-Taxonomie & Content-Architektur

> Reine Ideation, keine Code-Änderungen. Thema: Wie werden Fragen in MONKEY MONEY
> organisiert, kalibriert, gespeichert, importiert und kuratiert?
>
> Grundmodell: **OBER-Kategorie → UNTER-Kategorie → Schwierigkeit
> (Leicht / Mittel / Schwer / ULTRAHARD)**, plus Region-Achse
> (**DE-Fokus vs. global**) als orthogonales Filter-Flag — NICHT als eigene
> Kategorie-Ebene (Ausnahme: Ober-Kategorie „Deutschland-Spezial", die per
> Definition DE-only ist).

---

## (a) Vollständige Ober-Kategorien-Liste (14 Stück)

Legende Region: 🌍 = global, 🇩🇪 = DE-Fokus, 🌍/🇩🇪 = beides vorhanden (per
Fragen-Flag getrennt). Farbcodes als Hex, gedacht für Kategorie-Kacheln,
Buzzer-LEDs und Ergebnis-Charts — bewusst alle unterscheidbar auf dunklem
TV-Hintergrund.

### 1. 🎮 Gaming — `#7C4DFF` (Violett)
Icon-Idee: Retro-Gamepad mit Bananen-D-Pad (Monkey-Branding!).

| Unter-Kategorie | Region | Notiz |
|---|---|---|
| League of Legends | 🌍 | Champions, Lore, E-Sport (Worlds, Faker) |
| Pokémon | 🌍 | Spiele + Anime + Sammelkarten getrennt taggen |
| Minecraft | 🌍 | Crafting-Rezepte als Bild-Fragen ideal |
| Fortnite | 🌍 | Skins, Kollabs, Map-Geschichte — hoher Verfalls-Anteil! |
| Nintendo-Universum | 🌍 | Mario, Zelda, Kirby, Konsolen-Historie |
| Retro & Arcade | 🌍 | Pac-Man bis PS1; Pixel-Bild-Fragen |
| E-Sport & Gaming-Kultur | 🌍/🇩🇪 | Twitch, Speedruns, Gamescom (DE) |
| Deutsche Gaming-Szene | 🇩🇪 | Gronkh, Rocket Beans, HandOfBlood, Piet Smiet |

### 2. 🎬 Filme & Serien — `#E53935` (Rot)
Icon-Idee: Filmklappe mit Affenpfoten-Abdruck.

| Unter-Kategorie | Region |
|---|---|
| Blockbuster & Hollywood | 🌍 |
| Animationsfilme (Pixar, Disney, Ghibli) | 🌍 |
| Streaming-Serien-Hits | 🌍 |
| Anime | 🌍 |
| Sci-Fi & Fantasy (Star Wars, HdR, Marvel) | 🌍 |
| Filmzitate & Szenen erkennen | 🌍/🇩🇪 (Bild/Audio-Typ) |
| Deutsche Filme & Serien | 🇩🇪 (Tatort, Fack ju Göhte, Dark, Stromberg) |
| Klassiker vor 2000 | 🌍 |

### 3. 🎵 Musik — `#FF9800` (Orange)
Icon-Idee: Kopfhörer-tragender Affe / Banane als Note.

| Unter-Kategorie | Region |
|---|---|
| Pop international | 🌍 |
| Rock & Metal | 🌍 |
| Deutschrap & Hip-Hop | 🇩🇪 (Capital Bra bis Fanta 4) |
| Charts & One-Hit-Wonder | 🌍/🇩🇪 |
| Schlager & Volksmusik | 🇩🇪 (Helene Fischer als Leicht-Anker) |
| Eurovision Song Contest | 🌍/🇩🇪 |
| Klassik & Filmmusik | 🌍 |
| Intro erkennen (Audio) | 🌍/🇩🇪 — Vorzeige-Kategorie für Audio-Typ |

### 4. ⚽ Sport — `#4CAF50` (Grün)
Icon-Idee: Fußball mit Bananenschale daneben (Slapstick).

| Unter-Kategorie | Region |
|---|---|
| **Bundesliga** | 🇩🇪 — Pflicht-Highlight! Vereine, Rekorde, Trainer-Karussell |
| DFB & Nationalelf | 🇩🇪 (Sommermärchen, WM-Titel, EM-Dramen) |
| Fußball international | 🌍 (WM/EM/Champions League, Messi/Ronaldo) |
| Olympia | 🌍 |
| US-Sport (NBA, NFL, MLB) | 🌍 |
| Motorsport & Formel 1 | 🌍/🇩🇪 (Schumacher, Vettel) |
| Wintersport | 🇩🇪-lean (Biathlon, Skispringen — deutsches TV-Phänomen) |
| Sport-Rekorde & Kurioses | 🌍 — ideal für Schätzfragen |

### 5. 🔬 Wissenschaft — `#00BCD4` (Cyan)
Icon-Idee: Reagenzglas mit Banane drin.

| Unter-Kategorie | Region |
|---|---|
| Physik & Chemie | 🌍 |
| Biologie & menschlicher Körper | 🌍 |
| Weltraum & Astronomie | 🌍 |
| Mathe & Logik | 🌍 — Schätz-Typ passt perfekt |
| Erfindungen & Entdeckungen | 🌍/🇩🇪 (deutsche Erfinder als DE-Slice) |
| Alltags-Wissenschaft („Warum ist der Himmel blau?") | 🌍 |

### 6. 🏛️ Geschichte — `#795548` (Braun)
Icon-Idee: Antike Säule, auf der ein Affe sitzt.

| Unter-Kategorie | Region |
|---|---|
| Antike (Ägypten, Rom, Griechenland) | 🌍 |
| Mittelalter & Ritter | 🌍 |
| 20. Jahrhundert & Weltkriege | 🌍/🇩🇪 |
| Deutsche Geschichte | 🇩🇪 |
| DDR & Wiedervereinigung | 🇩🇪 — bei Ü40-Runden Gold wert |
| Berühmte Persönlichkeiten | 🌍 |
| Entdecker & Kolonialzeit | 🌍 |

### 7. 🌍 Geographie — `#3F51B5` (Indigo)
Icon-Idee: Globus mit Bananen-Äquator.

| Unter-Kategorie | Region |
|---|---|
| Länder & Hauptstädte | 🌍 |
| Flaggen erkennen | 🌍 (Bild-Typ) |
| Deutschland-Geographie | 🇩🇪 (Bundesländer, Flüsse, „Wo liegt Bielefeld?") |
| Europa | 🌍/🇩🇪 |
| Rekorde der Erde (höchster/tiefster/längster) | 🌍 — Schätz-Typ |
| Städte & Wahrzeichen (Skyline-Bilder) | 🌍 (Bild-Typ) |

### 8. 🍕 Essen & Trinken — `#FFC107` (Amber)
Icon-Idee: Banane im Burger.

| Unter-Kategorie | Region |
|---|---|
| Deutsche Küche | 🇩🇪 (Spätzle-Geographie, Döner-Geschichte) |
| Internationale Küche | 🌍 |
| Süßigkeiten & Snack-Marken | 🇩🇪-lean (Haribo, Milka, Kinder — hoher Wiedererkennungswert) |
| Bier, Wein & Getränke | 🇩🇪-lean (Reinheitsgebot als Klassiker) |
| Fast Food & Marken-Logos | 🌍 (Bild-Typ) |
| Kochen & Zutaten | 🌍 |

### 9. 😂 Internet & Memes — `#FF4081` (Pink)
Icon-Idee: Affe mit Sonnenbrille („Deal with it"-GIF-Stil).

| Unter-Kategorie | Region |
|---|---|
| Meme-Klassiker | 🌍 (Doge bis Distracted Boyfriend — Bild-Typ!) |
| Deutsche Internet-Kultur | 🇩🇪 (YouTube-Deutschland-Historie, Vong-Sprache) |
| TikTok & aktuelle Trends | 🌍/🇩🇪 — höchster Verfalls-Anteil der ganzen App |
| YouTuber & Streamer | 🌍/🇩🇪 |
| Internet-Geschichte (ICQ bis KI-Boom) | 🌍 |
| Virale Momente & Fails | 🌍/🇩🇪 |

### 10. 🇩🇪 Deutschland-Spezial — `#111111` mit Gold-Akzent `#FFCC00` (Schwarz-Rot-Gold-Thema)
Icon-Idee: Adler mit Banane in den Fängen. Per Definition komplett 🇩🇪.

| Unter-Kategorie |
|---|
| Politik & Bundestag (Kanzler-Reihenfolge, Wahlrecht, Länder-Kuriosa) |
| Deutsches TV & Shows (Wetten dass, GZSZ, Löwen, Traumschiff) |
| Promis & Boulevard (Dschungelcamp-Wissen als ULTRAHARD-Fundgrube) |
| Alltag & Bürokratie (Mülltrennung, Ruhezeiten, Amts-Deutsch) |
| Dialekte & Sprache („Was heißt ‚Bemme'?") |
| Werbung & Marken-Slogans („Wohnst du noch oder…") |
| Feiertage & Traditionen (Warum ist Karfreitag tanzfrei?) |
| Made in Germany (Autobahn, Bahn, Exportschlager) |

### 11. 🦁 Tiere & Natur — `#8BC34A` (Hellgrün)
Icon-Idee: Affenkopf im Blätterkranz (Selbstreferenz = Sympathie-Punkte).

| Unter-Kategorie | Region |
|---|---|
| Säugetiere | 🌍 |
| Ozean & Meerestiere | 🌍 |
| Insekten & Krabbeltiere | 🌍 |
| Heimische Tiere & Wald | 🇩🇪 |
| Pflanzen & Bäume | 🌍/🇩🇪 |
| Tier-Rekorde | 🌍 — Schätz-Typ |
| Haustiere | 🌍 |

### 12. 🎨 Kunst & Literatur — `#9C27B0` (Lila)
Icon-Idee: Pinsel, der eine Banane malt (Referenz auf das taped-banana-Kunstwerk).

| Unter-Kategorie | Region |
|---|---|
| Berühmte Gemälde erkennen | 🌍 (Bild-Typ) |
| Weltliteratur | 🌍 |
| Deutsche Literatur & Dichter | 🇩🇪 (Goethe-Zitate von Leicht bis ULTRAHARD skalierbar) |
| Architektur & Bauwerke | 🌍/🇩🇪 |
| Comics & Graphic Novels | 🌍 |
| Theater & Musical | 🌍/🇩🇪 |

### 13. 🚗 Technik & Autos — `#607D8B` (Blaugrau)
Icon-Idee: Zahnrad mit Bananen-Zähnen.

| Unter-Kategorie | Region |
|---|---|
| Autos & Marken | 🇩🇪-lean (VW/BMW/Mercedes-Historie) + 🌍 |
| Smartphones & Gadgets | 🌍 |
| Computer & Internet-Technik | 🌍 |
| KI & Zukunftstechnik | 🌍 — Verfallsdatum beachten |
| Raumfahrt-Technik | 🌍 |
| Bahn, Verkehr & Mobilität | 🇩🇪 (Deutsche-Bahn-Fragen = garantierte Lacher) |

### 14. 🎲 Kurioses & Mixed — `#009688` (Teal)
Icon-Idee: Würfel mit Fragezeichen und Banane als Sechs. Sammelbecken für
alles Quer-Kategoriale — wichtig als „Zufalls-Mix"-Ziel im Show-Flow.

| Unter-Kategorie | Region |
|---|---|
| Schätzmeister (reine Schätzfragen quer durch alles) | 🌍/🇩🇪 |
| Stimmt's oder Quatsch? (Wahr/Falsch-Kuriositäten) | 🌍/🇩🇪 |
| Verrückte Gesetze weltweit | 🌍 |
| Rekorde & Superlative | 🌍 |
| Wer bin ich? (Personen-Rätsel mit gestuften Tipps) | 🌍/🇩🇪 |
| Buchstaben & Wörter (Sprach-Spielereien) | 🇩🇪 |

**Taxonomie-Grundsätze:**
- Unter-Kategorien sind die BUCHUNGS-Einheit (Fragen hängen immer an genau
  einer Unter-Kategorie); Ober-Kategorien sind reine Anzeige-/Auswahl-Bündel.
  Das erlaubt späteres Umhängen ohne Fragen-Migration.
- Region ist ein Flag pro FRAGE (`de`/`global`), nicht pro Kategorie — der
  „Deutschland-Fokus-Modus" filtert dann `region in [de, global]` mit
  DE-Gewichtung (z. B. 60/40), der Global-Modus schließt reine DE-Insider aus.
- Ziel-Balance fürs Start-Datenset: pro Unter-Kategorie mindestens
  20 Leicht / 20 Mittel / 15 Schwer / 5 ULTRAHARD = 60 Fragen; 14×~6
  Unter-Kategorien × 60 ≈ **5.000 Fragen als v1-Ziel**.

---

## (b) Schwierigkeits-Definition: Leicht / Mittel / Schwer / ULTRAHARD

### Kalibrierungs-Anker (die Kernfrage: WER kann das beantworten?)

| Stufe | Anker-Persona | Erwartete Trefferquote (ohne Raten) | Bauch-Test |
|---|---|---|---|
| **Leicht** | „Oma UND der 12-jährige Cousin schaffen das." Allgemeinwissen ohne Hobby-Bezug. | 80–95 % | Wenn jemand falsch liegt, lacht die Runde ÜBER die Person (liebevoll). |
| **Mittel** | „Wer die Kategorie MAG, weiß es; wer nicht, kann klug raten." Gelegenheits-Interesse reicht. | 45–70 % | Zwei von vier Antwortoptionen wirken plausibel. |
| **Schwer** | „Nur Fans/Hobbyisten der Unter-Kategorie." Man muss sich aktiv damit beschäftigt haben. | 15–40 % | Der Kategorie-Fan am Tisch wird sichtbar ernst und konzentriert. |
| **ULTRAHARD** | „Selbst der Fan flucht." Experten-/Trivia-Nischenwissen; korrekte Antwort löst Jubel + Ungläubigkeit aus. | < 10 % | Richtig-Antworten fühlt sich wie ein Lottogewinn an — deshalb gehört hier der größte Money-Multiplikator drauf. |

Zusatzregeln für die Kalibrierung:
- **Distraktoren skalieren mit**: Bei Leicht sind 3 Antworten offensichtlich
  absurd (gern komisch!), bei ULTRAHARD sind alle 4 für Laien ununterscheidbar.
- **Schwierigkeit ist relativ zur Unter-Kategorie**, nicht absolut: Eine
  LoL-Leicht-Frage darf für Nicht-Gamer trotzdem unlösbar sein — der Host
  wählt ja die Kategorie bewusst.
- **Nachkalibrierung durch Telemetrie**: Ist die Live-Trefferquote einer Frage
  2 Stufen daneben (z. B. „Schwer" wird zu 85 % richtig beantwortet), wird sie
  automatisch zur Neu-Einstufung geflaggt (siehe Kuration).

### Beispiel-Fragen (3 Kategorien × 4 Stufen)

**Gaming → League of Legends** 🌍
- Leicht: „Wie heißt die Landkarte, auf der klassische 5-gegen-5-Matches in
  LoL stattfinden?" → *Kluft der Beschwörer* (Summoner's Rift)
- Mittel: „Welcher Champion ist ein Yordle?" → *Teemo* (neben Darius, Garen,
  Lee Sin)
- Schwer: „Welches Team gewann die allererste LoL-Weltmeisterschaft 2011?"
  → *Fnatic*
- ULTRAHARD: „Wie viele Skillpunkte kann ein Champion bis Level 18 maximal
  vergeben?" → *18* (klingt trivial, wird aber fast immer falsch geraten —
  perfekter ULTRAHARD-Trick: einfach klingende Detailfrage)

**Sport → Bundesliga** 🇩🇪
- Leicht: „Welcher Verein trägt seine Heimspiele in der Allianz Arena aus?"
  → *FC Bayern München*
- Mittel: „Welcher Verein gewann 2011 und 2012 zweimal in Folge die deutsche
  Meisterschaft?" → *Borussia Dortmund*
- Schwer: „Wer ist Rekord-Torschütze der Bundesliga-Geschichte?" → *Gerd
  Müller (365 Tore)*
- ULTRAHARD: „Welcher Verein war Gründungsmitglied der Bundesliga 1963,
  spielte aber nie wieder erstklassig, nachdem er 1965 abstieg — und kam aus
  Münster?" → *Preußen Münster* (Jahres-/Vereinsdetails = klassisches
  ULTRAHARD-Material)

**Deutschland-Spezial → TV & Shows** 🇩🇪
- Leicht: „Wie heißt die Quizshow mit Günther Jauch, in der man eine Million
  Euro gewinnen kann?" → *Wer wird Millionär?*
- Mittel: „In welcher Stadt spielt die Serie GZSZ?" → *Berlin*
- Schwer: „Wie hieß der erste Bachelor der deutschen RTL-Staffel 2003?"
  → *Marcel Maderitsch*
- ULTRAHARD: „Wie viele Ausgaben von ‚Wetten, dass..?' moderierte Thomas
  Gottschalk bis zu seinem endgültigen Abschied 2023 (offizielle
  ZDF-Zählung)?" → *154*

**Hinweis Tipps-Kopplung:** Die 2–3 gestuften Tipps (siehe Schema) sind bei
Leicht optional, bei Schwer/ULTRAHARD PFLICHT — sie sind das Ventil, das
ULTRAHARD party-tauglich macht (Tipp kaufen kostet Monkey Money → schöne
Ökonomie-Schnittstelle zu Agent 14).

---

## (c) Fragen-Schema (JSON)

```jsonc
{
  // Identität & Einordnung
  "id": "q_gaming_lol_000123",            // sprechendes Präfix + laufende Nr.; stabil, nie recyceln
  "schema_version": 1,                     // Migrationsfähigkeit von Tag 1
  "kategorie": "gaming",                   // Slug der Ober-Kategorie
  "unterkategorie": "league_of_legends",   // Slug; genau EINE (Buchungs-Einheit)
  "schwierigkeit": "schwer",               // leicht | mittel | schwer | ultrahard
  "region": "global",                      // de | global
  "typ": "text",                           // text | bild | audio | schaetz

  // Inhalt
  "text": "Welches Team gewann die allererste LoL-Weltmeisterschaft 2011?",
  "antworten": ["Fnatic", "SK Telecom T1", "Cloud9", "G2 Esports"],
  "korrekt": 0,                            // Index in antworten[]; Anzeige mischt clientseitig
  "tipps": [                               // 2–3 gestuft, vage → konkret
    "Das Team kommt aus Europa.",
    "Der Name klingt wie ein englisches Wort für ‚fanatisch'.",
    "Es beginnt mit F."
  ],

  // Typ-spezifische Erweiterungen (nur wenn typ != text)
  "medien": {                              // bei bild/audio
    "datei": "assets/fragen/lol_worlds_2011.jpg",
    "credit": "Riot Games Pressefoto",
    "spoiler_sicher": true                 // Bild verrät die Antwort nicht
  },
  "schaetz": {                             // nur bei typ == schaetz: ersetzt antworten/korrekt
    "richtwert": 365,
    "einheit": "Tore",
    "toleranz_prozent": 10,                // „nah dran"-Fenster für Teilpunkte
    "eingabe_min": 0,
    "eingabe_max": 1000
  },

  // Kuration & Herkunft
  "quelle": "https://lol.fandom.com/wiki/Season_1_World_Championship",
  "faktencheck_notiz": "Gegengecheckt mit Riot-Pressearchiv, Stand 2026-08.",
  "faktencheck_status": "geprueft",        // entwurf | geprueft | community
  "erstellt_von": "gm_medusa",             // User-/Autoren-Id oder Pack-Id
  "erstellt_am": "2026-08-14",
  "verfallsdatum": null,                   // ISO-Datum bei zeitgebundenen Fakten ("aktueller Trainer von…")
  "altersfreigabe": "ab0",                 // ab0 | ab12 | ab16  (16 = Alkohol/derber Humor)
  "fehlerhaft_flag": false,                // von Spielern meldbar; true ⇒ raus aus Rotation bis Review
  "fehlerhaft_meldungen": 0,               // Zähler für Auto-Quarantäne-Schwelle
  "tags": ["esport", "worlds", "geschichte"], // frei, für Suche/Specials ("Worlds-Themenabend")
  "stats": {                               // von der App gepflegt, nicht vom Autor
    "gestellt": 42,
    "korrekt_beantwortet": 11              // ⇒ Live-Trefferquote für Nachkalibrierung
  }
}
```

Schema-Entscheidungen (Begründung):
- **`korrekt` als Index statt Text-Duplikat** — keine Tippfehler-Divergenz;
  die App mischt die Anzeige-Reihenfolge pro Runde selbst (Seed injizierbar,
  passend zur Repo-Regel „RNG als Parameter").
- **`schaetz` ersetzt `antworten`** statt sie zu verbiegen — Schätzfragen sind
  strukturell anders (numerische Eingabe + Toleranzfenster), das gehört nicht
  in ein 4-Antworten-Korsett gepresst.
- **`stats` getrennt von Autorenfeldern** — Autoren-Datei bleibt diffbar/
  reviewbar, Laufzeit-Statistik lebt in lokalem Store und fließt nur für die
  Nachkalibrierung zurück.
- **Ein File pro Unter-Kategorie** (`fragen/gaming/league_of_legends.json` mit
  Fragen-Array + Header-Metadaten) — git-freundlich, Merge-Konflikte bleiben
  lokal, und „eigene Fragen super leicht addierbar" heißt konkret: eine Datei
  anfassen, fertig.

---

## (d) Eigene-Fragen-Pipeline

Vier Wege, aufsteigend nach Aufwand — alle münden ins selbe Schema + dieselbe
Validierung (ein gemeinsamer Import-Trichter, kein Sonderweg):

1. **GM-Editor im Spielleiter-Bereich (In-App)** — der Königsweg für die
   Party-Situation. Formular mit: Kategorie-Picker (Taxonomie aus (a) als
   Dropdown-Kaskade), 4 Antwortfelder mit Korrekt-Toggle,
   Schwierigkeits-Slider MIT eingeblendeten Anker-Personas aus (b)
   („Kann das deine Oma? → Leicht"), Tipp-Felder, Region-Schalter.
   Live-Vorschau im Show-Layout. Neue Fragen landen in einem lokalen
   „Haus-Pack" und sind SOFORT in der nächsten Runde spielbar — der
   „Ich schreib eine Frage über dich, Kevin!"-Moment ist ein Party-Feature,
   kein Verwaltungsakt.
2. **JSON-Import** — Datei im Schema aus (c) (einzelne Frage oder Array) per
   Datei-Dialog/AirDrop in den GM-Bereich ziehen. Für Power-User und für
   KI-generierte Fragen-Batches (Prompt-Vorlage mitliefern!). Validator zeigt
   Fehler MIT Zeilenkontext („Frage 17: nur 3 Antworten").
3. **CSV-Import** — für die „Ich hab 200 Fragen in Excel"-Zielgruppe (Lehrer,
   Vereinsfeiern!). Feste Spalten: `text; a1; a2; a3; a4; korrekt(1-4);
   schwierigkeit; kategorie; unterkategorie; region; tipp1; tipp2; tipp3;
   quelle`. Alles Weitere bekommt Defaults (typ=text, altersfreigabe=ab0,
   faktencheck_status=entwurf). Eine herunterladbare Beispiel-CSV ist Teil
   des Features, nicht der Doku.
4. **Community-Pack-Format `.mmpack`** — ZIP mit `manifest.json` (Pack-Name,
   Autor, Version, benötigte Schema-Version, Altersfreigabe-Maximum,
   Beschreibung, Cover-Emoji/-Bild), `fragen/*.json` und optional `assets/`
   (Bilder/Audio, mit Größen-Limit). Packs sind an-/abschaltbar wie DLCs im
   GM-Bereich, updatebar über Versionsnummer, und teilbar als eine Datei
   (Messenger-tauglich!). Eigene Fragen aus Weg 1–3 lassen sich als
   `.mmpack` EXPORTIEREN → so entsteht das Community-Ökosystem von selbst.

Gemeinsamer Import-Trichter (für alle 4 Wege identisch):
Schema-Validierung → Duplikat-Check gegen Bestand (siehe (e)) →
Altersfreigabe-/Region-Defaults setzen → Status `entwurf` bzw. `community`
(niemals automatisch `geprueft`) → in Pack einsortieren → Report anzeigen
(„194 importiert, 4 Duplikate übersprungen, 2 fehlerhaft").

---

## (e) Kurations-Regeln

1. **Fakten-Check-Stufen**: Jede Frage trägt `faktencheck_status`.
   Offizielles Datenset: nur `geprueft` (Quelle PFLICHT, Vier-Augen-Prinzip:
   Autor ≠ Prüfer, Prüf-Notiz + Datum ins Feld). Community/eigene Fragen
   laufen als `community`/`entwurf` und werden im Show-UI dezent markiert
   (kleines Pack-Icon statt Warnschild — kein Spielspaß-Killer).
2. **Altersfreigabe-Flags**: `ab0` (Default), `ab12` (Grusel, leichte
   Anzüglichkeit, Boulevard), `ab16` (Alkohol-Themen, derber Humor). Der GM
   setzt pro Session ein Maximum („Familienabend: ab0"); der Fragen-Pool wird
   hart gefiltert, nicht nur gewarnt. Kein `ab18` — was dafür nötig wäre,
   gehört nicht in eine Buzz-Party-App.
3. **Duplikat-Erkennung**, zweistufig: (1) exakter Match auf normalisiertem
   Fragetext (lowercase, ohne Satzzeichen/Artikel) → Import blockiert;
   (2) Fuzzy-Ähnlichkeit (Trigramm/Levenshtein ≥ ~85 %) ODER identisches Paar
   aus korrekter Antwort + Unter-Kategorie → Import-Warnung mit
   Nebeneinander-Ansicht („Behalten / Überspringen / Ersetzen"). Läuft beim
   Import UND als Batch-Werkzeug über den Bestand (wichtig, wenn mehrere
   Packs dieselben Klassiker enthalten — „Hauptstadt von Australien" existiert
   sonst fünfmal).
4. **Aktualitäts-Verfallsdatum**: Zeitgebundene Fakten (aktueller Trainer,
   „neuester Teil der Reihe", Rekord-Stände, TikTok-Trends) bekommen PFLICHT
   ein `verfallsdatum`. Abgelaufene Fragen fliegen automatisch aus der
   Rotation und landen in einer Review-Queue („aktualisieren oder
   archivieren"). Faustregel je Unter-Kategorie: Memes/Trends 6 Monate,
   Sport-Personalien 12 Monate, Charts 12 Monate, alles Historische ohne
   Verfall. Beim Autorisieren nudgen: Fragen möglichst verfallsfrei
   formulieren („Wer war 2014 Weltmeister?" statt „Wer ist amtierender…").
5. **Fehlerhaft-Meldung im Spiel**: Ein Knopf „Frage melden" für den GM (und
   optional Spieler) setzt `fehlerhaft_meldungen++`; ab Schwelle (z. B. 2)
   wird `fehlerhaft_flag=true` → Quarantäne bis Review. Meldegrund als Enum
   (falsche Antwort / veraltet / unverständlich / doppelt / unangemessen)
   macht die Review-Queue sortierbar.
6. **Telemetrie-Nachkalibrierung**: Trefferquote je Frage (aus `stats`) gegen
   die Anker-Bänder aus (b) prüfen; ab n ≥ 20 Stellungen und 2 Stufen
   Abweichung → Auto-Vorschlag zur Umstufung in der Review-Queue (nie
   stille Auto-Änderung — der Kurator entscheidet).

---

## Aufwand & Priorität je Baustein

| Baustein | Prio | Aufwand (technisch) | Begründung |
|---|---|---|---|
| Taxonomie festzurren (Slugs, 14 Ober- + ~80 Unter-Kategorien) | **P0** | Klein — reine Datendefinition + Review | Fundament; jede spätere Umbenennung kostet Migrationen. |
| Fragen-Schema v1 + Validator | **P0** | Klein–mittel — JSON-Schema + Lade-/Prüf-Logik | Alles andere (Editor, Importe, Kuration) baut darauf; `schema_version` ab Tag 1. |
| Schwierigkeits-Anker als Autoren-Doku + Beispielfragen | **P0** | Klein — Doku + ~50 Eich-Fragen | Ohne Kalibrierung driftet jedes Datenset sofort auseinander. |
| Start-Datenset (~5.000 Fragen, Kernkategorien zuerst) | **P1** | Groß — Content-Arbeit, KI-gestützt + Vier-Augen-Check | Reihenfolge: Deutschland-Spezial, Bundesliga, Gaming, Filme, Mixed — die Party-Bringer zuerst. |
| CSV- & JSON-Import (gemeinsamer Trichter) | **P1** | Mittel — Parser, Validierungs-Report, Defaults | Billigster Weg zu „riesiges Datenset": externe Zuarbeit sofort nutzbar. |
| Duplikat-Erkennung (exakt + fuzzy) | **P1** | Mittel — Normalisierung + Ähnlichkeitsmetrik | Muss VOR der großen Datenset-Welle stehen, sonst Aufräum-Schulden. |
| Verfallsdatum + Quarantäne + Review-Queue | **P2** | Mittel — Filterlogik + kleine Queue-UI | Wird erst mit Datenset-Größe/Alter wichtig, dann aber sehr. |
| GM-Editor In-App | **P2** | Mittel–groß — Formular-UI, Vorschau, Haus-Pack-Store | Größter UX-Aufwand; CSV/JSON überbrücken bis dahin. |
| `.mmpack` Community-Format inkl. Export | **P3** | Mittel — ZIP-Handling, Manifest, Pack-Verwaltung | Ökosystem-Hebel, aber erst sinnvoll, wenn Editor + Kuration stehen. |
| Telemetrie-Nachkalibrierung | **P3** | Mittel — Stats-Store + Schwellen-Logik | Braucht echte Spieldaten; Felder dafür (`stats`) aber ab v1 vorsehen. |

---

*Ende Ideen-Agent 12/20 — Kategorien-Taxonomie & Content-Architektur.*
