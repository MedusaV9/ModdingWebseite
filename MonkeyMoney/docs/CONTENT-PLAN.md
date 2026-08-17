# MONKEY MONEY — CONTENT-PLAN (verbindlich)

> Konsolidiert aus den Ideen-Katalogen 12 (Kategorien), 13 (Frage-Formate/Medien),
> 15 (Analytics/Fragen-Gesundheit), 19 (Übungsmodus/Erklärungen) sowie 01/02
> (Show-Formate → benötigte Frage-Typen), 10 (CC0-Audio-Quellen) und 14
> (Money-Ökonomie → Tipp-Kosten). Dieser Plan ist ENTSCHIEDEN — Abweichungen
> nur per expliziter Plan-Änderung, nicht ad hoc in der Produktion.
>
> Stand: 2026-08-14 · Schema-Version: 1

---

## 1. Kategorien-Taxonomie FINAL

**Entscheidung:** 14 Ober-Kategorien, **90 Unter-Kategorien** (Katalog 12 hatte 96;
6 Zusammenlegungen, siehe Änderungsprotokoll unten). Grundsätze:

- **Unter-Kategorien sind die Buchungs-Einheit** — jede Frage hängt an genau
  EINER Unter-Kategorie. Ober-Kategorien sind reine Anzeige-/Auswahl-Bündel
  (Umhängen später ohne Fragen-Migration möglich).
- **Region ist ein Flag pro FRAGE** (`de` | `global`), nicht pro Kategorie.
  Die Region-Spalte unten gibt nur die ERWARTETE Mischung an (reine
  Autoren-Orientierung). Ausnahme: `deutschland_spezial` ist per Definition
  komplett `de`.
- DE-Fokus-Modus filtert `region in [de, global]` mit 60/40-DE-Gewichtung;
  Global-Modus schließt `region == de` hart aus.

### 1.1 Ober-Kategorien (IDs, Farben, Icons)

| # | ID (Slug) | Name | Farbe | Icon-Idee |
|---|---|---|---|---|
| 1 | `gaming` | 🎮 Gaming | `#7C4DFF` Violett | Retro-Gamepad mit Bananen-D-Pad |
| 2 | `filme_serien` | 🎬 Filme & Serien | `#E53935` Rot | Filmklappe mit Affenpfoten-Abdruck |
| 3 | `musik` | 🎵 Musik | `#FF9800` Orange | Banane als Note / Kopfhörer-Affe |
| 4 | `sport` | ⚽ Sport | `#4CAF50` Grün | Fußball mit Bananenschale |
| 5 | `wissenschaft` | 🔬 Wissenschaft | `#00BCD4` Cyan | Reagenzglas mit Banane |
| 6 | `geschichte` | 🏛️ Geschichte | `#795548` Braun | Antike Säule mit sitzendem Affen |
| 7 | `geographie` | 🌍 Geographie | `#3F51B5` Indigo | Globus mit Bananen-Äquator |
| 8 | `essen_trinken` | 🍕 Essen & Trinken | `#FFC107` Amber | Banane im Burger |
| 9 | `internet_memes` | 😂 Internet & Memes | `#FF4081` Pink | Affe mit Sonnenbrille |
| 10 | `deutschland_spezial` | 🇩🇪 Deutschland-Spezial | `#111111` + Gold `#FFCC00` | Adler mit Banane |
| 11 | `tiere_natur` | 🦁 Tiere & Natur | `#8BC34A` Hellgrün | Affenkopf im Blätterkranz |
| 12 | `kunst_literatur` | 🎨 Kunst & Literatur | `#9C27B0` Lila | Pinsel malt Banane |
| 13 | `technik_autos` | 🚗 Technik & Autos | `#607D8B` Blaugrau | Zahnrad mit Bananen-Zähnen |
| 14 | `kurioses_mixed` | 🎲 Kurioses & Mixed | `#009688` Teal | Würfel mit Banane als Sechs |

### 1.2 Unter-Kategorien FINAL (vollständige Tabelle, 90 Stück)

Region-Legende: `global` = weltweit beantwortbar · `de` = setzt DE-Sozialisation
voraus · `mix` = beide Region-Flags kommen vor. `KERN` = erste Produktions-Welle
(siehe Abschnitt 4).

| Ober-Kat | Unter-Kat (Slug) | Name | Region | Notiz |
|---|---|---|---|---|
| gaming | `league_of_legends` | League of Legends | global | Champions, Lore, E-Sport |
| gaming | `pokemon` | Pokémon | global | Spiele/Anime/Karten per Tags trennen |
| gaming | `minecraft` | Minecraft | global | KERN · Crafting als Bild-Fragen ideal |
| gaming | `fortnite_battle_royale` | Fortnite & Battle Royale | global | hoher Verfalls-Anteil → Verfallsdaten! |
| gaming | `nintendo_universum` | Nintendo-Universum | global | KERN · Mario, Zelda, Kirby, Konsolen |
| gaming | `retro_arcade` | Retro & Arcade | global | Pac-Man bis PS1, Pixel-Bilder |
| gaming | `esport_gaming_kultur` | E-Sport & Gaming-Kultur | mix | Twitch, Speedruns, Gamescom (de) |
| gaming | `deutsche_gaming_szene` | Deutsche Gaming-Szene | de | Gronkh, Rocket Beans, HandOfBlood |
| filme_serien | `blockbuster_hollywood` | Blockbuster & Hollywood | global | KERN · inkl. Klassiker vor 2000 (Merge) |
| filme_serien | `animationsfilme` | Animationsfilme | global | KERN · Pixar, Disney, Ghibli |
| filme_serien | `streaming_serien` | Streaming-Serien-Hits | global | Verfallsdaten bei „neueste Staffel" |
| filme_serien | `anime` | Anime | global | |
| filme_serien | `scifi_fantasy` | Sci-Fi & Fantasy | global | Star Wars, HdR, Marvel |
| filme_serien | `filmzitate_emoji` | Filmzitate & Emoji-Rätsel | mix | KERN · Heimat des `emoji`-Typs |
| filme_serien | `deutsche_filme_serien` | Deutsche Filme & Serien | de | Tatort, Fack ju Göhte, Dark, Stromberg |
| musik | `pop_international` | Pop international | global | |
| musik | `rock_metal` | Rock & Metal | global | |
| musik | `deutschrap_hiphop` | Deutschrap & Hip-Hop | de | Capital Bra bis Fanta 4 |
| musik | `charts_onehit_esc` | Charts, One-Hit-Wonder & ESC | mix | KERN · Merge aus 2 Katalog-Kats |
| musik | `schlager_volksmusik` | Schlager & Volksmusik | de | Helene Fischer als Leicht-Anker |
| musik | `klassik_filmmusik` | Klassik & Filmmusik | global | |
| musik | `intro_erkennen` | Intro erkennen (Audio) | mix | v1 KLEIN: nur PD-Klassik/Eigenaufnahme (7.4) |
| sport | `bundesliga` | Bundesliga | de | KERN · Pflicht-Highlight |
| sport | `dfb_nationalelf` | DFB & Nationalelf | de | Sommermärchen, WM-Titel |
| sport | `fussball_international` | Fußball international | global | WM/EM/CL, Messi/Ronaldo |
| sport | `olympia_wintersport` | Olympia & Wintersport | mix | Merge; Wintersport DE-lean |
| sport | `us_sport` | US-Sport (NBA, NFL, MLB) | global | |
| sport | `motorsport_formel1` | Motorsport & Formel 1 | mix | Schumacher, Vettel |
| sport | `sport_rekorde_kurioses` | Sport-Rekorde & Kurioses | global | ideal für Schätzfragen |
| wissenschaft | `physik_chemie` | Physik & Chemie | global | |
| wissenschaft | `biologie_koerper` | Biologie & menschlicher Körper | global | |
| wissenschaft | `weltraum_astronomie` | Weltraum & Astronomie | global | |
| wissenschaft | `mathe_logik` | Mathe & Logik | global | Schätz-Typ passt perfekt |
| wissenschaft | `erfindungen_entdeckungen` | Erfindungen & Entdeckungen | mix | deutsche Erfinder als DE-Slice |
| wissenschaft | `alltagswissenschaft` | Alltags-Wissenschaft | global | KERN · „Warum ist der Himmel blau?" |
| geschichte | `antike` | Antike | global | Ägypten, Rom, Griechenland |
| geschichte | `mittelalter_ritter` | Mittelalter & Ritter | global | |
| geschichte | `zwanzigstes_jahrhundert` | 20. Jahrhundert & Weltkriege | mix | |
| geschichte | `deutsche_geschichte` | Deutsche Geschichte | de | |
| geschichte | `ddr_wiedervereinigung` | DDR & Wiedervereinigung | de | bei Ü40-Runden Gold wert |
| geschichte | `persoenlichkeiten_entdecker` | Persönlichkeiten & Entdecker | global | Merge aus 2 Katalog-Kats |
| geographie | `laender_hauptstaedte` | Länder & Hauptstädte | global | KERN |
| geographie | `flaggen_erkennen` | Flaggen erkennen | global | KERN · Bild-Typ, Flaggen = PD (7.5) |
| geographie | `deutschland_geographie` | Deutschland-Geographie | de | Bundesländer, „Wo liegt Bielefeld?" |
| geographie | `europa` | Europa | mix | |
| geographie | `erd_rekorde` | Rekorde der Erde | global | Schätz-Typ |
| geographie | `staedte_wahrzeichen` | Städte & Wahrzeichen | global | Bild-Typ (Skylines) |
| essen_trinken | `deutsche_kueche` | Deutsche Küche | de | Spätzle-Geographie, Döner-Geschichte |
| essen_trinken | `internationale_kueche` | Internationale Küche | global | |
| essen_trinken | `suessigkeiten_snacks` | Süßigkeiten & Snack-Marken | mix | KERN · DE-lean (Haribo, Milka, Kinder) |
| essen_trinken | `bier_wein_getraenke` | Bier, Wein & Getränke | mix | Alkohol-Fragen → `ab18` (Abschnitt 5.8) |
| essen_trinken | `fastfood_marken` | Fast Food & Marken-Logos | global | Bild-Typ |
| essen_trinken | `kochen_zutaten` | Kochen & Zutaten | global | |
| internet_memes | `meme_klassiker` | Meme-Klassiker | global | Bild-Typ (Rechte je Meme prüfen!) |
| internet_memes | `deutsche_internet_kultur` | Deutsche Internet-Kultur | de | YouTube-DE-Historie, Vong-Sprache |
| internet_memes | `youtuber_streamer` | YouTuber & Streamer | mix | |
| internet_memes | `internet_geschichte` | Internet-Geschichte | global | ICQ bis KI-Boom |
| internet_memes | `virale_trends` | Virale Trends & Fails | mix | Merge (TikTok+Fails); höchster Verfall der App |
| deutschland_spezial | `politik_bundestag` | Politik & Bundestag | de | NUR Fakten, keine Meinungen (5.8) |
| deutschland_spezial | `tv_shows` | Deutsches TV & Shows | de | KERN · Wetten dass, GZSZ, Löwen |
| deutschland_spezial | `promis_boulevard` | Promis & Boulevard | de | Dschungelcamp = ULTRAHARD-Fundgrube |
| deutschland_spezial | `alltag_buerokratie` | Alltag & Bürokratie | de | Mülltrennung, Amts-Deutsch |
| deutschland_spezial | `dialekte_sprache` | Dialekte & Sprache | de | „Was heißt ‚Bemme'?" |
| deutschland_spezial | `werbung_slogans` | Werbung & Marken-Slogans | de | KERN · „Wohnst du noch oder…" |
| deutschland_spezial | `feiertage_traditionen` | Feiertage & Traditionen | de | |
| deutschland_spezial | `made_in_germany` | Made in Germany | de | Autobahn, Bahn, Exportschlager |
| tiere_natur | `saeugetiere_haustiere` | Säugetiere & Haustiere | global | Merge aus 2 Katalog-Kats |
| tiere_natur | `ozean_meerestiere` | Ozean & Meerestiere | global | |
| tiere_natur | `insekten_krabbeltiere` | Insekten & Krabbeltiere | global | |
| tiere_natur | `heimische_tiere_wald` | Heimische Tiere & Wald | de | |
| tiere_natur | `pflanzen_baeume` | Pflanzen & Bäume | mix | |
| tiere_natur | `tier_rekorde` | Tier-Rekorde | global | KERN · Schätz-Typ + Audio (Tierstimmen) |
| kunst_literatur | `gemaelde_erkennen` | Berühmte Gemälde erkennen | global | Bild-Typ; gemeinfreie Kunst (7.3) |
| kunst_literatur | `weltliteratur` | Weltliteratur | global | |
| kunst_literatur | `deutsche_literatur` | Deutsche Literatur & Dichter | de | Goethe skaliert Leicht→ULTRAHARD |
| kunst_literatur | `architektur_bauwerke` | Architektur & Bauwerke | mix | |
| kunst_literatur | `comics_graphic_novels` | Comics & Graphic Novels | global | |
| kunst_literatur | `theater_musical` | Theater & Musical | mix | |
| technik_autos | `autos_marken` | Autos & Marken | mix | DE-lean (VW/BMW/Mercedes) |
| technik_autos | `smartphones_gadgets` | Smartphones & Gadgets | global | |
| technik_autos | `computer_internet_technik` | Computer & Internet-Technik | global | |
| technik_autos | `ki_zukunftstechnik` | KI & Zukunftstechnik | global | Verfallsdaten Pflicht-Kandidat |
| technik_autos | `raumfahrt_technik` | Raumfahrt-Technik | global | |
| technik_autos | `bahn_verkehr_mobilitaet` | Bahn, Verkehr & Mobilität | de | DB-Fragen = garantierte Lacher |
| kurioses_mixed | `schaetzmeister` | Schätzmeister | mix | KERN · reine Schätzfragen quer durch alles |
| kurioses_mixed | `stimmts_oder_quatsch` | Stimmt's oder Quatsch? | mix | KERN · Heimat des `wahr_falsch`-Typs |
| kurioses_mixed | `verrueckte_gesetze` | Verrückte Gesetze weltweit | global | |
| kurioses_mixed | `rekorde_superlative` | Rekorde & Superlative | global | |
| kurioses_mixed | `wer_bin_ich` | Wer bin ich? | mix | Personen-Rätsel, lebt von den 3 Tipps |
| kurioses_mixed | `buchstaben_woerter` | Buchstaben & Wörter | de | Sprach-Spielereien |

### 1.3 Änderungsprotokoll gegenüber Katalog 12 (96 → 90)

| Merge | Begründung |
|---|---|
| „Klassiker vor 2000" → `blockbuster_hollywood` | Ära ist Schwierigkeits-/Tag-Dimension, keine eigene Buchungs-Einheit |
| „Charts & One-Hit-Wonder" + „ESC" → `charts_onehit_esc` | gleiche Autoren-Kompetenz, gleiche Zielgruppe |
| „Olympia" + „Wintersport" → `olympia_wintersport` | Wintersport allein zu schmal für 4 Schwierigkeits-Stufen |
| „Berühmte Persönlichkeiten" + „Entdecker & Kolonialzeit" → `persoenlichkeiten_entdecker` | starke Überlappung |
| „TikTok & aktuelle Trends" + „Virale Momente & Fails" → `virale_trends` | beide = Hoch-Verfalls-Content, ein Wartungs-Topf |
| „Säugetiere" + „Haustiere" → `saeugetiere_haustiere` | Haustiere sind fast vollständig Säugetiere-Teilmenge |

---

## 2. Fragen-Schema FINAL

### 2.1 Grundsatz-Entscheidungen

1. **Ein JSON-File pro Unter-Kategorie** (siehe Abschnitt 6), Fragen als Array.
2. **`korrekt` als Index, nie als Text-Duplikat** — App mischt Anzeige-Reihenfolge
   clientseitig (Seed injizierbar, RNG-als-Parameter-Regel).
3. **KEINE Laufzeit-Felder in Autoren-Dateien.** `stats`, `fehlerhaft_flag`,
   `fehlerhaft_meldungen` leben in der Runtime-DB (SQLite-Event-Log, Katalog 15
   Idee 23), verknüpft über die Frage-`id`. Autoren-Dateien bleiben diffbar
   und review-bar.
4. **`erklaerung` ist PFLICHT** (Katalog 19, Idee 8: „Warum"-Karte im
   Übungsmodus). Nachrüsten über tausende Fragen wäre unbezahlbar — deshalb ab
   Frage 1.
5. **8 Typen, fix:** `choice` · `wahr_falsch` · `schaetz` · `sortier` ·
   `bild_pixel` · `audio` · `emoji` · `mehrfach`. Neue Typen nur per
   Schema-Version-Erhöhung.
6. `choice` darf optional ein `medien`-Bild als Fragen-KONTEXT tragen
   („Welches dieser 4 Tiere…"); `bild_pixel` ist das dedizierte
   Enthüllungs-Format mit Jackpot-Verfall.

### 2.2 Das Schema (alle Felder)

```jsonc
{
  // ---- Identität & Einordnung (alle Typen, Pflicht) ----
  "id": "q_sport_bundesliga_000123",   // q_<oberkat>_<unterkat>_<6-stellige Nr.>; stabil, nie recyceln
  "schema_version": 1,
  "kategorie": "sport",                 // Slug Ober-Kategorie (aus 1.1)
  "unterkategorie": "bundesliga",       // Slug Unter-Kategorie (aus 1.2); genau EINE
  "schwierigkeit": "schwer",            // leicht | mittel | schwer | ultrahard
  "region": "de",                       // de | global
  "typ": "choice",                      // choice | wahr_falsch | schaetz | sortier | bild_pixel | audio | emoji | mehrfach
  "altersfreigabe": "ab0",              // ab0 | ab12 | ab18  (ab18 = Alkohol-Themen/derber Humor, s. 5.8)
  "tags": ["rekorde", "torjaeger"],     // frei; Pflicht-Tags s. Validierung

  // ---- Inhalt (typabhängig, s. 2.3) ----
  "text": "Wer ist Rekord-Torschütze der Bundesliga-Geschichte?",
  "antworten": ["Gerd Müller", "Robert Lewandowski", "Klaus Fischer", "Jupp Heynckes"],
  "korrekt": 0,

  // ---- Tipp-System (GENAU 3, s. 2.4; Ausnahme wahr_falsch: leer) ----
  "tipps": [
    "Der Rekord stammt aus einer Zeit, als es noch D-Mark gab.",
    "Der Spieler wurde ‚Bomber der Nation' genannt.",
    "Er spielte seine gesamte Bundesliga-Karriere beim FC Bayern."
  ],

  // ---- Lern-Layer (Pflicht) ----
  "erklaerung": "Gerd Müller erzielte 365 Bundesliga-Tore (1965–1979) — Lewandowski kam bis zu seinem Wechsel 2022 auf 312.",

  // ---- Medien (nur bild_pixel/audio Pflicht; choice optional) ----
  "medien": {
    "datei": "assets/bilder/bundesliga/q_sport_bundesliga_000123.webp",
    "quelle_art": "generiert",          // generiert | wikimedia | eigenaufnahme | cc_pack
    "lizenz": "eigen",                  // eigen | CC0 | Public Domain | CC-BY 3.0 | CC-BY 4.0 | OGA-BY 3.0
    "autor": "",                        // Pflicht bei CC-BY/OGA-BY
    "quelle_url": "",                   // Pflicht bei wikimedia/cc_pack
    "aenderungen": "",                  // z. B. "zugeschnitten, verpixelt" (CC-BY verlangt Hinweis)
    "spoiler_sicher": true,             // Bild/Dateiname verrät die Antwort nicht
    "farbkritisch": false               // true = Erkennung hängt an Rot-Grün-Kontrast (Farbenblind-Filter)
  },

  // ---- Kuration & Herkunft (Pflicht) ----
  "quelle": "https://www.bundesliga.com/de/bundesliga/news/rekordtorjaeger",
  "stand_datum": "2026-08-14",          // wann der Fakt zuletzt geprüft wurde
  "verfallsdatum": null,                // ISO-Datum bei zeitgebundenen Fakten, sonst null
  "faktencheck_status": "geprueft",     // entwurf | geprueft | community
  "faktencheck_notiz": "Gegengecheckt: kicker-Archiv + bundesliga.com, 2026-08.",
  "erstellt_von": "agent_sport_01",     // Autoren-/Agent-/Pack-Id
  "geprueft_von": "agent_review_03",    // MUSS != erstellt_von bei status geprueft
  "erstellt_am": "2026-08-14"
}
```

### 2.3 Typ-spezifische Felder & Regeln

| Typ | Inhalt-Felder | Regeln |
|---|---|---|
| `choice` | `text`, `antworten` (genau 4), `korrekt` (Index 0–3) | Brot-und-Butter; `medien` optional als Kontext-Bild |
| `wahr_falsch` | `text` (Aussage), `korrekt_bool` (true/false) | KEINE `antworten`; `tipps` = leeres Array (Blitz-Format, Engine-Joker statt Einzeltipps); immer als Serien-Material zu 5–8 denken |
| `schaetz` | `text`, `schaetz`-Objekt: `richtwert` (Zahl), `einheit` (String), `toleranz_prozent` (1–50), `eingabe_min`, `eingabe_max`, `skala` (`linear`\|`log`) | ersetzt `antworten`/`korrekt` komplett; min < richtwert < max; bei Jahreszahlen Toleranz ±5 % der Jahre seit Ereignis, min. ±1 (Katalog 13, Idee 24) |
| `sortier` | `text` (inkl. Kriterium!), `elemente` (genau 4 Strings), `korrekt_reihenfolge` (Permutation der Indizes 0–3), `aufloesung_werte` (4 Strings, z. B. Jahreszahlen) | Kriterium eindeutig formulieren („älteste zuerst"); Anzeige-Reihenfolge mischt die App |
| `bild_pixel` | `text` („Was ist das?"-Variante), `antworten` (4), `korrekt`, `medien` PFLICHT | Motiv: EIN Objekt, zentriert, neutraler Hintergrund (fair verpixelbar); `spoiler_sicher` und `farbkritisch` Pflicht-Angaben |
| `audio` | `text`, `antworten` (4), `korrekt`, `medien` PFLICHT (`.ogg`) | Sound läuft NUR über den Bildschirm; Datei ≤ 10 s Kern-Länge; Lizenz-Allowlist (7.4) |
| `emoji` | `text` (z. B. „Welcher Film ist das?"), `emojis` (String, 3–7 Emojis), `antworten` (4), `korrekt`, optional `freitext_akzeptanzen` (Array für Hard-Modus, inkl. Schreibvarianten) | Emojis erscheinen einzeln (1/s); keine Marken-Emojis; Antwort = offizieller deutscher Titel |
| `mehrfach` | `text` („Welche 2 …?"), `antworten` (genau 6), `korrekt_mehrfach` (genau 2 Indizes) | Teilpunkte macht die Engine (140/40/0); Frage MUSS „2 von 6" explizit nennen |

### 2.4 Tipp-System FINAL: GENAU 3 Stufen

**Content-Seite:** Jede Frage trägt GENAU 3 Text-Tipps (`tipps[0..2]`),
Ausnahme `wahr_falsch` (genau 0). Auch Leicht-Fragen bekommen 3 Tipps —
einheitliche Validierung, und der GM-Gnaden-Tipp (Katalog 13, Idee 23) braucht
sie ohnehin überall.

**Stufen-Dramaturgie (Schreibregel, Details in 5.5):**

| Stufe | Funktion | Beispiel (Frage: Rekord-Torschütze) |
|---|---|---|
| 1 — vage | aktiviert Vorwissen (Epoche/Raum/Genre) | „Der Rekord stammt aus einer Zeit, als es noch D-Mark gab." |
| 2 — eingrenzend | verkleinert den Suchraum deutlich | „Der Spieler wurde ‚Bomber der Nation' genannt." |
| 3 — fast Antwort | lässt genau EINEN Denk-Schritt übrig | „Er spielte seine gesamte Bundesliga-Karriere beim FC Bayern." |

**Money-Kosten-Regel (fix):** Tippkauf kostet **15 % / 35 % / 60 % des
MÖGLICHEN Gewinns dieser Frage** — nie vom Kontostand. Stufen sind nur
nacheinander kaufbar (kein Direktsprung); es gilt der höchste gekaufte Satz
(nicht additiv): wer bis Stufe 3 geht, hat maximal 40 % Restgewinn. Restwert
wird auf dem Handy live angezeigt. Die Engine DARF Stufe 2/3 je Frage-Typ
mechanisch statt textlich ausspielen (Option streichen, Slider-Korridor,
Element pinnen — Mapping aus Katalog 13, Teil A); die 3 Text-Tipps sind
trotzdem immer autorisiert (Fallback + Übungsmodus). Im Übungsmodus sind alle
Tipps gratis (Katalog 19, Idee 8).

### 2.5 Validierungsregeln (hartes Gate im Import-/CI-Tool)

Fehler (F) blockieren den Merge, Warnungen (W) brauchen Reviewer-Override:

1. (F) `id` matcht `^q_[a-z0-9_]+_[0-9]{6}$`, Präfix passt zu
   `kategorie`/`unterkategorie`, global eindeutig, nie recycelt.
2. (F) `kategorie`/`unterkategorie`-Slug existiert in Taxonomie 1.2;
   `schwierigkeit`, `region`, `typ`, `altersfreigabe`,
   `faktencheck_status` ∈ Enum.
3. (F) Typ-Pflichtfelder gemäß 2.3 vollständig; typfremde Felder verboten
   (z. B. `antworten` bei `schaetz`).
4. (F) **Längen-Gates** (Content-Gate aus Katalog 19, Idee 17 — lesbar in
   „Riesig" auf iPhone 11 UND TV aus 4 m): `text` ≤ 190 Zeichen ·
   Antwort ≤ 40 · Tipp ≤ 90 · `erklaerung` ≤ 220 · `emojis` 3–7 Emojis.
5. (F) `choice`/`bild_pixel`/`audio`/`emoji`: genau 4 paarweise verschiedene
   Antworten, `korrekt` ∈ 0–3. `mehrfach`: genau 6 Antworten, genau 2
   korrekte. `sortier`: genau 4 Elemente, `korrekt_reihenfolge` ist
   Permutation von 0–3.
6. (F) `tipps`: genau 3 (bzw. 0 bei `wahr_falsch`); die normalisierte
   korrekte Antwort (lowercase, ohne Satzzeichen/Artikel) darf in KEINEM
   Tipp als Teilstring vorkommen.
7. (F) `erklaerung` nicht leer.
8. (F) Bei `faktencheck_status == geprueft`: `quelle` (URL), `stand_datum`,
   `faktencheck_notiz`, `geprueft_von` gesetzt UND
   `geprueft_von != erstellt_von` (Vier-Augen).
9. (F) Verfalls-Heuristik: enthält `text` eines der Wörter
   „aktuell/derzeit/amtierend/neuest/zurzeit/momentan/dieses Jahr", MUSS
   `verfallsdatum` gesetzt sein.
10. (F) Medien: bei `bild_pixel`/`audio` existiert `medien.datei` physisch;
    `lizenz` ∈ Allowlist (7.2); bei CC-BY/OGA-BY sind `autor` und
    `quelle_url` nicht leer; `spoiler_sicher == true` Pflicht bei
    `bild_pixel`.
11. (F) Duplikat exakt: normalisierter `text` kollidiert mit Bestand →
    blockiert. (W) Fuzzy: Trigramm/Levenshtein-Ähnlichkeit ≥ 85 % ODER
    gleiches Paar (korrekte Antwort + Unterkategorie) → Warnung mit
    Nebeneinander-Ansicht (Behalten/Überspringen/Ersetzen).
12. (W) Antwortlängen-Balance: längste Antwort > 2× kürzeste.
13. (W) Verbots-Muster: „alle oben genannten", „keine der genannten",
    Doppel-Negation, Frage endet nicht mit „?" (außer Aussage-Typen).
14. (F) Datei ist valides UTF-8-JSON; Formatter (`format_content`)
    normalisiert Key-Reihenfolge und Einrückung — CI prüft
    Formatter-Idempotenz (gleiches Prinzip wie gdformat im Repo).

### 2.6 Beispiel-Fragen je Typ (Vorlage-Qualität, alle Felder gekürzt auf das Wesentliche)

**choice** — siehe Voll-Beispiel in 2.2 (Bundesliga/Gerd Müller, schwer/de).

**wahr_falsch** (`kurioses_mixed/stimmts_oder_quatsch`, leicht, global):
```jsonc
{
  "id": "q_kurioses_mixed_stimmts_oder_quatsch_000001",
  "typ": "wahr_falsch", "schwierigkeit": "leicht", "region": "global",
  "text": "Eine Banane ist botanisch gesehen eine Beere.",
  "korrekt_bool": true,
  "tipps": [],
  "erklaerung": "Botanisch ist die Banane eine Beere — die Erdbeere dagegen nicht (sie ist eine Sammelnussfrucht).",
  "quelle": "https://de.wikipedia.org/wiki/Banane", "stand_datum": "2026-08-14"
}
```

**schaetz** (`kurioses_mixed/schaetzmeister`, mittel, de):
```jsonc
{
  "id": "q_kurioses_mixed_schaetzmeister_000002",
  "typ": "schaetz", "schwierigkeit": "mittel", "region": "de",
  "text": "Wie hoch ist der Kölner Dom (Höhe der Türme) in Metern?",
  "schaetz": { "richtwert": 157, "einheit": "Meter", "toleranz_prozent": 10,
               "eingabe_min": 50, "eingabe_max": 300, "skala": "linear" },
  "tipps": [
    "Er war im 19. Jahrhundert kurzzeitig das höchste Gebäude der Welt.",
    "Höher als die Münchner Frauenkirche (99 m), niedriger als das Ulmer Münster (161 m).",
    "Zwischen 150 und 160 Metern."
  ],
  "erklaerung": "157 Meter — von 1880 bis 1884 war der Kölner Dom das höchste Bauwerk der Welt.",
  "quelle": "https://www.koelner-dom.de/", "stand_datum": "2026-08-14"
}
```

**sortier** (`gaming/retro_arcade`, mittel, global):
```jsonc
{
  "id": "q_gaming_retro_arcade_000003",
  "typ": "sortier", "schwierigkeit": "mittel", "region": "global",
  "text": "Ordne diese Spiele nach Erscheinungsjahr — das älteste zuerst.",
  "elemente": ["Super Mario Kart", "Pac-Man", "Minecraft", "Tetris"],
  "korrekt_reihenfolge": [1, 3, 0, 2],
  "aufloesung_werte": ["1980", "1984", "1992", "2011"],
  "tipps": [
    "Zwei der vier Spiele stammen noch aus der Arcade-/Heimcomputer-Ära vor 1990.",
    "Pac-Man fraß schon Punkte, als Tetris noch nicht erfunden war.",
    "Reihenfolge der Jahrzehnte: 80er, 80er, 90er, 2010er."
  ],
  "erklaerung": "Pac-Man (1980), Tetris (1984), Super Mario Kart (1992), Minecraft (2011).",
  "quelle": "https://de.wikipedia.org/wiki/Pac-Man", "stand_datum": "2026-08-14"
}
```

**bild_pixel** (`essen_trinken/deutsche_kueche`, leicht, de — generiertes Bild):
```jsonc
{
  "id": "q_essen_trinken_deutsche_kueche_000004",
  "typ": "bild_pixel", "schwierigkeit": "leicht", "region": "de",
  "text": "Was wird hier enthüllt?",
  "antworten": ["Brezel", "Croissant", "Bagel", "Donut"],
  "korrekt": 0,
  "medien": { "datei": "assets/bilder/deutsche_kueche/q_essen_trinken_deutsche_kueche_000004.webp",
              "quelle_art": "generiert", "lizenz": "eigen",
              "aenderungen": "Haus-Stil-Prompt v1 (7.1)",
              "spoiler_sicher": true, "farbkritisch": false },
  "tipps": [
    "Ein Gebäck.",
    "Besonders beliebt in Bayern und Schwaben — gern mit Butter.",
    "Die Form hat verschlungene ‚Arme'."
  ],
  "erklaerung": "Die Brezel — das Laugengebäck ist eines der bekanntesten Symbole deutscher Backkultur.",
  "quelle": "https://de.wikipedia.org/wiki/Brezel", "stand_datum": "2026-08-14"
}
```

**audio** (`tiere_natur/tier_rekorde`, mittel, global — CC0-Sound):
```jsonc
{
  "id": "q_tiere_natur_tier_rekorde_000005",
  "typ": "audio", "schwierigkeit": "mittel", "region": "global",
  "text": "Welches Tier hört ihr hier ‚lachen'?",
  "antworten": ["Jägerlieststar (Kookaburra)", "Tüpfelhyäne", "Schimpanse", "Graupapagei"],
  "korrekt": 0,
  "medien": { "datei": "assets/audio/tier_rekorde/q_tiere_natur_tier_rekorde_000005.ogg",
              "quelle_art": "cc_pack", "lizenz": "CC0", "autor": "BigSoundBank/Joseph Sardin",
              "quelle_url": "https://bigsoundbank.com/", "aenderungen": "gekürzt auf 8 s, -16 LUFS",
              "spoiler_sicher": true, "farbkritisch": false },
  "tipps": [
    "Es ist ein Vogel.",
    "Er lebt in Australien.",
    "Sein Spitzname ist ‚lachender Hans'."
  ],
  "erklaerung": "Der Kookaburra (Jägerliest) ist für seinen lachartigen Ruf berühmt — daher ‚lachender Hans'.",
  "quelle": "https://de.wikipedia.org/wiki/J%C3%A4gerliest", "stand_datum": "2026-08-14"
}
```

**emoji** (`filme_serien/filmzitate_emoji`, leicht, global):
```jsonc
{
  "id": "q_filme_serien_filmzitate_emoji_000006",
  "typ": "emoji", "schwierigkeit": "leicht", "region": "global",
  "text": "Welcher Film-Klassiker ist das?",
  "emojis": "🦈🏖️👮🌊",
  "antworten": ["Der weiße Hai", "Findet Nemo", "Sharknado", "Free Willy"],
  "korrekt": 0,
  "freitext_akzeptanzen": ["der weisse hai", "jaws"],
  "tipps": [
    "Ein Thriller aus den 1970er-Jahren.",
    "Regie führte Steven Spielberg.",
    "Die berühmte Filmmusik besteht aus zwei immer schneller werdenden Tönen."
  ],
  "erklaerung": "‚Der weiße Hai' (1975) — Spielbergs Thriller gilt als der erste moderne Sommer-Blockbuster.",
  "quelle": "https://de.wikipedia.org/wiki/Der_wei%C3%9Fe_Hai", "stand_datum": "2026-08-14"
}
```

**mehrfach** (`geographie/laender_hauptstaedte`, leicht, global):
```jsonc
{
  "id": "q_geographie_laender_hauptstaedte_000007",
  "typ": "mehrfach", "schwierigkeit": "leicht", "region": "global",
  "text": "Welche ZWEI dieser sechs Länder haben eine Landgrenze zu Deutschland?",
  "antworten": ["Dänemark", "Niederlande", "Italien", "Spanien", "Ukraine", "Portugal"],
  "korrekt_mehrfach": [0, 1],
  "tipps": [
    "Eines der beiden Länder liegt nördlich, eines westlich von Deutschland.",
    "Italien grenzt an Österreich und die Schweiz — nicht an Deutschland.",
    "Denkt an Windmühlen und an Smørrebrød."
  ],
  "erklaerung": "Deutschland grenzt an 9 Staaten — darunter Dänemark im Norden und die Niederlande im Westen. Italien, Spanien, die Ukraine und Portugal gehören nicht dazu.",
  "quelle": "https://de.wikipedia.org/wiki/Geographie_Deutschlands", "stand_datum": "2026-08-14"
}
```

---

## 3. Schwierigkeits-Kalibrierung

### 3.1 Die 4 Stufen mit messbaren Ankern

Schwierigkeit ist IMMER relativ zur Unter-Kategorie (eine LoL-Leicht-Frage darf
für Nicht-Gamer unlösbar sein — der Host wählt die Kategorie bewusst).

| Stufe | Anker-Persona (Bauch-Test beim Schreiben) | Ziel-Band: ratebereinigte Richtig-Quote | Distraktoren-Regel | Basis-Money (Katalog 02) |
|---|---|---|---|---|
| **Leicht** | „Oma UND der 12-jährige Cousin schaffen das." | 80–95 % | 3 Distraktoren offensichtlich falsch, max. 1 davon komisch | 100 MM |
| **Mittel** | „Wer die Kategorie MAG, weiß es; wer nicht, rät klug." | 45–70 % | 2 von 4 Optionen wirken plausibel | 200 MM |
| **Schwer** | „Nur Fans/Hobbyisten der Unter-Kategorie." | 15–40 % | 3 von 4 Optionen plausibel für Gelegenheits-Kenner | 400 MM |
| **ULTRAHARD** | „Selbst der Fan flucht — richtig = Lottogewinn-Jubel." | < 10 % | alle 4 für Laien ununterscheidbar | 800 MM |

**Ratebereinigung (damit Choice-Raten die Messung nicht verzerrt):**
`bereinigt = (roh − r) / (1 − r)` mit Ratebasis `r` je Typ
(choice/bild_pixel/audio/emoji: 0,25 · wahr_falsch: 0,5 · mehrfach: 1/15 ·
schaetz: Anteil im Toleranzfenster, r=0). Quoten werden je Spielmodus getrennt
erhoben (Buzzer-Modus rät niemand — Katalog 15, Idee 11).

### 3.2 Umstufungs-Regel aus Analytics (Richtig-Quote-Drift) — FINAL

1. Gemessen wird erst ab **n ≥ 20 Ausspielungen** im selben Modus
   (darunter: „zu wenig Daten", keine Aktion).
2. Liegt die ratebereinigte Quote im Band einer **NACHBAR-Stufe**
   (1 Stufe Drift) → automatischer **Umstufungs-Vorschlag** in der
   Review-Queue (mit Konfidenz, Annehmen/Ablehnen/Frage ansehen;
   Entscheidung wird geloggt, damit dieselbe Frage nicht wöchentlich
   wiederkommt — Katalog 15, Idee 19).
3. Liegt sie **2+ Stufen** daneben (z. B. „Schwer" wird zu 85 % gelöst) →
   **automatische Quarantäne** (raus aus der Rotation) + Pflicht-Review:
   das ist fast immer eine kaputte oder falsch verstandene Frage.
4. NIE stille Auto-Änderung — der Kurator entscheidet; angenommene
   Umstufung setzt `stand_datum` neu und wird im Git-Diff sichtbar.
5. Sonderfall 0-%-Quote bei n ≥ 10: Sofort-Quarantäne („Frage der Schande"
   ist fast immer ein Content-Bug).

### 3.3 Eich-Beispiele: 5 Unter-Kategorien × 4 Stufen

Diese 20 Fragen sind die EICH-FRAGEN — jeder Produktions-Agent liest sie vor
dem Schreiben (Kalibrierung gegen Drift zwischen parallelen Agents).

**sport/bundesliga (de)**
- Leicht: „Welcher Verein trägt seine Heimspiele in der Allianz Arena aus?" → *FC Bayern München*
- Mittel: „Welcher Verein wurde 2011 und 2012 zweimal in Folge Deutscher Meister?" → *Borussia Dortmund*
- Schwer: „Wer ist Rekord-Torschütze der Bundesliga-Geschichte?" → *Gerd Müller (365 Tore)*
- ULTRAHARD: „Welches Gründungsmitglied der Bundesliga von 1963 stieg nach der ersten Saison ab und kehrte nie in die Bundesliga zurück — und kommt aus Münster?" → *Preußen Münster* (Anmerkung: Katalog 12 nannte fälschlich „1965 abgestiegen"; korrekt ist der Abstieg 1964 nach der Saison 1963/64 — Beleg dafür, warum Fakten-Check Pflicht ist.)

**gaming/league_of_legends (global)**
- Leicht: „Wie heißt die Karte, auf der klassische 5-gegen-5-Matches stattfinden?" → *Kluft der Beschwörer (Summoner's Rift)*
- Mittel: „Welcher dieser Champions ist ein Yordle?" → *Teemo* (Distraktoren: Darius, Garen, Lee Sin)
- Schwer: „Welches Team gewann die allererste LoL-Weltmeisterschaft 2011?" → *Fnatic*
- ULTRAHARD: „Wie viele Skillpunkte kann ein Champion bis Level 18 maximal vergeben?" → *18* (einfach klingende Detailfrage = klassischer ULTRAHARD-Trick)

**deutschland_spezial/tv_shows (de)**
- Leicht: „Wie heißt die Quizshow mit Günther Jauch, in der man eine Million Euro gewinnen kann?" → *Wer wird Millionär?*
- Mittel: „In welcher Stadt spielt die Serie GZSZ?" → *Berlin*
- Schwer: „Wie hieß der erste Bachelor der deutschen RTL-Staffel 2003?" → *Marcel Maderitsch*
- ULTRAHARD: „Wie viele Ausgaben von ‚Wetten, dass..?' moderierte Thomas Gottschalk bis zu seinem Abschied 2023 (offizielle ZDF-Zählung)?" → *154*

**geographie/laender_hauptstaedte (global)**
- Leicht: „Wie heißt die Hauptstadt von Frankreich?" → *Paris*
- Mittel: „Welches Land hat Canberra als Hauptstadt?" → *Australien* (Falle: Sydney als Distraktor-Magnet)
- Schwer: „Wie heißt die Hauptstadt von Myanmar?" → *Naypyidaw*
- ULTRAHARD: „Wie hieß Kasachstans Hauptstadt Astana während der Umbenennung von 2019 bis 2022?" → *Nur-Sultan* (historischer Fakt, verfällt nicht)

**essen_trinken/suessigkeiten_snacks (de-lean)**
- Leicht: „Welche Firma stellt die ‚Goldbären' her?" → *Haribo*
- Mittel: „Wofür steht das ‚Ha' im Firmennamen Haribo?" → *Hans* (Hans Riegel, Bonn)
- Schwer: „In welchem Jahr wurde Haribo gegründet?" → *1920*
- ULTRAHARD: „In welchem Jahr kam das Kinder-Überraschungsei in Deutschland auf den Markt?" → *1974*

---

## 4. v1-CONTENT-SOLL (entschieden)

### 4.1 Die Kern-16 (erste Produktions-Welle)

Auswahl-Kriterien: Party-Bringer zuerst (DE-Spezial, Bundesliga, Filme, Mixed —
Katalog-12-Priorität), volle Abdeckung aller P1-Frage-Typen, breite
Altersgruppen. Die Kern-16:

| # | Unter-Kategorie | Warum Kern |
|---|---|---|
| 1 | `sport/bundesliga` | DE-Pflicht-Highlight, jede Runde |
| 2 | `deutschland_spezial/tv_shows` | größter gemeinsamer Nenner DE-Partys |
| 3 | `deutschland_spezial/werbung_slogans` | Instant-Lacher, Ü30-Gold |
| 4 | `kurioses_mixed/schaetzmeister` | füttert ALLE Schätz-Formate (B9 „Bananen-Tresor") |
| 5 | `kurioses_mixed/stimmts_oder_quatsch` | füttert Wahr/Falsch-Blitz (Serien-Bedarf!) |
| 6 | `gaming/nintendo_universum` | generationenübergreifend Gaming |
| 7 | `gaming/minecraft` | Kinder/Teens-Anker; Crafting = Bild-Fragen |
| 8 | `filme_serien/blockbuster_hollywood` | breitester Film-Topf |
| 9 | `filme_serien/filmzitate_emoji` | Heimat des Emoji-Typs (P1, rechtssicher) |
| 10 | `filme_serien/animationsfilme` | Familien-Anker |
| 11 | `musik/charts_onehit_esc` | Musik OHNE Audio-Rechte-Problem (Textfragen) |
| 12 | `geographie/laender_hauptstaedte` | Quiz-Klassiker, skaliert perfekt |
| 13 | `geographie/flaggen_erkennen` | Bild-Typ-Vorzeigekategorie, PD-Material |
| 14 | `essen_trinken/suessigkeiten_snacks` | DE-Wiedererkennung (Haribo/Milka/Kinder) |
| 15 | `wissenschaft/alltagswissenschaft` | „Warum…?"-Fragen, jeder kann mitreden |
| 16 | `tiere_natur/tier_rekorde` | Schätz+Audio-tauglich (Tierstimmen CC0) |

### 4.2 Mengen-Soll pro Unter-Kategorie × Schwierigkeit

| Klasse | Leicht | Mittel | Schwer | ULTRAHARD | Summe/Kat |
|---|---|---|---|---|---|
| **Kern-16** | 20 | 20 | 15 | 5 | **60** |
| **Standard-74** (Rest) | 10 | 10 | 6 | 2 | **28** |

- Kern: 16 × 60 = **960 Fragen**
- Standard: 74 × 28 = **2.072 Fragen**
- **v1-GESAMT-ZIEL: 3.000 geprüfte Fragen** (Launch-Gate: `faktencheck_status
  == geprueft`, Vier-Augen). Rechnerisch 3.032 — die 32 Reserve puffern
  Review-Ausschuss.
- **Welle 2 (Stretch, nach Launch): Ausbau auf 5.000** — Standard-Kategorien
  auf 40+, Kern auf 80+; Priorität nach Kategorie-Lücken-Report
  (Katalog 15, Idee 21: „Sport/Schwer: noch ~2 Abende Vorrat").
- Hoch-Verfalls-Kategorien (`virale_trends`, `fortnite_battle_royale`,
  `ki_zukunftstechnik`) bleiben bewusst auf Standard-Minimum: Pflege kostet
  mehr als Masse bringt.

### 4.3 Typ-Mix-Soll innerhalb der 3.000

| Typ | Anteil | Stück | Anmerkung |
|---|---|---|---|
| `choice` | 60 % | 1.800 | Brot-und-Butter, jedes Show-Format kann sie |
| `wahr_falsch` | 10 % | 300 | Blitz-Runden verbrauchen 5–8 pro Serie → Masse nötig |
| `schaetz` | 8 % | 250 | mind. 100 davon in `schaetzmeister`; jede Unter-Kat ≥ 2 |
| `bild_pixel` | ~7 % | 200 | **Bild-Fragen-Soll: 200 generierte Pixel-Bilder** (Haus-Stil 7.1); + ~50 `choice` mit Kontext-Bild (Flaggen [PD-Vektoren], gemeinfreie Gemälde, Wikimedia) → **250 Bild-Fragen gesamt** |
| `sortier` | 4 % | 120 | |
| `mehrfach` | 4 % | 120 | |
| `emoji` | ~4 % | 110 | davon ≥ 60 in `filmzitate_emoji` |
| `audio` | ~3 % | 100 | **Audio-Fragen-Soll: 100 — JA, aus CC0 machbar** (7.4): ~40 Tierstimmen, ~30 Alltagsgeräusche (eigenaufgenommen/CC0, auch rückwärts/verfremdet), ~10 Instrumente, ~20 gemeinfreie Klassik (PD-AUFNAHMEN via Wikimedia/Musopen). NICHT machbar: Chart-Song-Intros (Leistungsschutz der Aufnahmen) → `intro_erkennen` startet klein (~20 Fragen) und wächst nur mit sauberen Quellen |

### 4.4 Launch-Gates (hart)

1. 3.000 Fragen `geprueft` durch Validator (2.5) UND Vier-Augen.
2. Jede der 90 Unter-Kategorien hat ihr Soll erreicht (keine leeren Regale —
   der Kategorien-Picker darf keine toten Kacheln zeigen).
3. Jede Kern-16-Kategorie enthält ≥ 2 Nicht-Text-Typen (Show-Abwechslung).
4. Duplikat-Batch-Lauf über den Gesamtbestand ist grün („Hauptstadt von
   Australien" existiert genau 1×).
5. Medien-Manifest vollständig (jede Bild-/Audio-Datei hat Lizenz-Zeile,
   CI-Gate analog Katalog 10, Idee 25).

---

## 5. Produktions-Anleitung für die Fragen-Agents (KRITISCH)

Diese Anleitung ist der Vertrag für alle (10+) parallelen Produktions-Agents.
Wer davon abweicht, produziert Ausschuss.

### 5.1 Arbeitsauftrag & Kollisionsfreiheit

1. Jeder Agent bekommt **exklusive Slots**: `unterkategorie × schwierigkeit`
   plus einen **ID-Bereich** (z. B. `q_sport_bundesliga_000100`–`000199`).
   Niemals außerhalb des eigenen ID-Bereichs schreiben → keine Merge-Konflikte.
2. VOR dem Schreiben: die Eich-Beispiele (3.3) UND die Bestandsdatei der
   eigenen Unter-Kategorie lesen (Duplikat-Vermeidung beginnt im Kopf, nicht
   im Validator).
3. NACH dem Schreiben: Validator lokal laufen lassen; nur fehlerfreie Batches
   abgeben. Status IMMER `entwurf` — `geprueft` vergibt nur der Review-Agent
   (Vier-Augen, `geprueft_von != erstellt_von`).

### 5.2 Frage-Stil-Regeln (die 10 Gebote)

1. **Eindeutig:** Genau EINE Antwort ist korrekt und verteidigbar. Keine
   Trick-Doppeldeutigkeit, keine „kommt drauf an"-Fragen. Wenn eine
   Fußnote nötig wäre, ist die Frage falsch gebaut.
2. **Selbsttragend:** Die Frage enthält allen nötigen Kontext („in der
   Bundesliga", „botanisch gesehen", „im Film von 1975").
3. **Kurz:** Frage ≤ 190 Zeichen (Ziel: ≤ 120), Antworten ≤ 40 Zeichen
   (Ziel: ≤ 25). Es gibt ein hartes Content-Gate (2.5), aber schreibt
   von vornherein knapp.
4. **Antwort-Längen ähnlich:** Die korrekte Antwort darf nicht die längste/
   präziseste sein (klassisches Quiz-Leak). Faustregel: längste ≤ 2× kürzeste,
   alle in gleicher grammatischer Form (alle Nomen, alle mit/ohne Artikel).
5. **Distraktoren plausibel & artgleich:** Bei „Welcher Verein…" sind alle 4
   Vereine; bei Jahreszahlen alle im plausiblen Fenster. Distraktoren aus der
   NÄHE der Wahrheit wählen (gleiche Liga, gleiche Dekade, ähnlicher Name).
   Ausnahme Leicht: max. 1 bewusst komischer Distraktor ist erlaubt (Party!).
6. **Keine Verneinungs-Fallen:** „Welches ist KEIN…" nur wenn unvermeidbar,
   dann NICHT/KEIN in Großbuchstaben. Nie doppelte Verneinung.
7. **Keine Meta-Optionen:** „Alle oben genannten" / „Keine der genannten"
   sind verboten (Validator-Regel 13).
8. **Zahlen einheitlich:** deutsche Formate (1.000er-Punkt, Komma), Einheiten
   ausschreiben oder SI-Kürzel, Jahreszahlen 4-stellig.
9. **Verfallsfrei formulieren:** „Wer war 2014 Weltmeister?" statt „Wer ist
   amtierender Weltmeister?". Wenn zeitgebunden unvermeidbar →
   `verfallsdatum` PFLICHT (Faustregeln: Memes/Trends 6 Monate,
   Sport-Personalien 12, Charts 12, Historisches nie).
10. **Erklärung mitliefern:** 1–2 Sätze, die die Antwort BEGRÜNDEN und im
    Idealfall einen Aha-/Fun-Fact enthalten (wird im Übungsmodus als
    „Warum"-Karte und vom GM zum Vorlesen genutzt).

### 5.3 Fakten-Check-Pflicht

- **Nur verifizierbares Wissen.** Jede Frage braucht ≥ 1 belastbare `quelle`
  (URL); bei Zahlen/Rekorden 2 unabhängige Quellen in der
  `faktencheck_notiz` nennen.
- **`stand_datum` IMMER setzen** (Datum der Prüfung, nicht des Schreibens).
- **KEINE tagesaktuellen Fragen**, die schnell veralten (aktuelle Trainer,
  „neuester Teil", laufende Staffeln, Rekord-Stände die gerade wackeln) —
  außer die Unter-Kategorie lebt davon (`virale_trends`): dann kurzes
  `verfallsdatum` Pflicht.
- **Warnbeispiel aus diesem Plan:** Katalog 12 datierte den Abstieg von
  Preußen Münster auf 1965 — korrekt ist 1964. Genau solche Fehler fängt nur
  der Vier-Augen-Check mit Quelle. Autor ≠ Prüfer, immer.

### 5.4 ULTRAHARD-Definition (damit es nicht „unfair" wird)

ULTRAHARD heißt: **< 10 % Trefferquote, aber 100 % Auflösungs-Zufriedenheit.**
- Die Antwort muss nach der Auflösung ein „Stimmt! Wow!" auslösen — nie ein
  „Häh, das ist doch Auslegungssache".
- Beste Muster: einfach klingende Detailfrage (LoL-Skillpunkte: 18),
  Zähl-/Jahres-Detail eines bekannten Themas (Gottschalk: 154), Nischen-Fakt
  einer Mainstream-Marke (Ü-Ei: 1974).
- Verboten: obskure Streitfälle, Fragen die selbst Experten-Quellen
  unterschiedlich beantworten, reines Zufalls-Raten ohne Herleitbarkeit.
- Alle 3 Tipps sind bei ULTRAHARD besonders wichtig (sie sind das Ventil, das
  ULTRAHARD party-tauglich macht) — Stufe 3 muss die Lösbarkeit auf
  „konzentriert nachdenken reicht" heben.

### 5.5 Tipp-Stil-Regeln

- **Stufe 1 (vage):** aktiviert Vorwissen — Epoche, Region, Genre, Kategorie.
  Kein Eigenname der Lösungs-Nähe.
- **Stufe 2 (eingrenzend):** halbiert den Suchraum — Zeitfenster, Ausschluss
  eines Kandidaten, markantes Attribut.
- **Stufe 3 (fast Antwort):** lässt GENAU einen Denk-Schritt übrig —
  Anfangsbuchstabe, sehr starke Assoziation, Anagramm-artiger Hinweis.
- **NIE die Antwort nennen** — weder wörtlich noch als eindeutiges Synonym
  noch als Übersetzung. Der Validator prüft den normalisierten
  Antwort-String, aber Synonyme fängt nur euer Hirn.
- Tipps sind eigenständige Sätze ≤ 90 Zeichen, ohne „Tipp:"-Präfix.
- Negativ-Beispiel: „Es ist Fnatic" ❌ · „Beginnt mit F und endet mit
  ‚natic'" ❌ · „Der Name klingt wie das englische Wort für ‚fanatisch'" ✅

### 5.6 Schätzfragen-Sonderregeln

- `richtwert` mit Quelle UND Stand; bei schwankenden Werten (Einwohnerzahlen)
  auf Zehner/Tausender runden und `stand_datum` setzen.
- `eingabe_min`/`eingabe_max` so wählen, dass der Richtwert NICHT in der
  Mitte liegt (sonst gewinnt Mitte-Raten); Spanne mindestens Faktor 4.
- `toleranz_prozent` 10 als Default; 5 bei gut wissbaren Werten, 20–30 bei
  echten Absurd-Schätzungen.
- Bei großen Spannen `skala: "log"` setzen.

### 5.7 DE/global-Regeln

- `region: "de"` wenn die Beantwortung DE-Sozialisation voraussetzt
  (deutsches TV, Marken-Slogans, Bundesliga-Interna, Dialekte).
- `region: "global"` wenn ein Quiz-Fan in Wien, Zürich ODER (übersetzt)
  London die Frage fair beantworten könnte.
- Global-Fragen dürfen keine DE-only-Distraktoren tragen (verwirrt
  Nicht-DE-Runden); DE-Fragen dürfen globale Distraktoren nutzen.
- `deutschland_spezial/*` ist IMMER `de`. Im Zweifel: `de` wählen —
  falsch-globale Fragen fallen im Global-Modus unangenehm auf.

### 5.8 Verbots-Liste (hart)

1. **Nichts Verletzendes:** keine Fragen, die eine anwesende Person(engruppe)
   zur Pointe machen; keine Diskriminierung, keine Körper-/Krankheits-Häme.
2. **Keine Politik-MEINUNGEN:** Fakten sind ok (Kanzler-Reihenfolge,
   Wahlrecht, Länder-Kuriosa), Bewertungen/aktuelle Kontroversen/Parteien-
   Vergleiche sind tabu. Faustregel: Wenn zwei vernünftige Menschen über die
   „richtige" Antwort streiten könnten, ist es keine Quiz-Frage.
3. **Alkohol-Fragen nur mit `ab18`-Flag.** Konkret: Jede Frage, deren
   GEGENSTAND Alkohol/Rausch/Trinkkultur ist (Reinheitsgebot, Weinanbau,
   Cocktails), trägt `ab18`. Alkoholfreie Getränke-Fragen bleiben `ab0`.
   Der Session-Filter des GM filtert hart, nicht warnend.
4. `ab12`: Grusel, leichte Anzüglichkeit, Boulevard/Dschungelcamp.
5. Keine Gewaltverherrlichung, keine expliziten Sex-Inhalte, keine Drogen-
   Anleitungen — solche Fragen existieren gar nicht, auch nicht mit Flag.
6. Keine Fragen über reale Privatpersonen; Personen des öffentlichen Lebens
   nur in ihrer öffentlichen Rolle, ohne Boulevard-Spekulation (bestätigte
   Fakten ja, Gerüchte nie).
7. Keine tragischen Ereignisse als Punchline (Katastrophen, Todesfälle sind
   Geschichts-Fakten, kein Comedy-Material).

### 5.9 Selbst-Check vor Abgabe (jede Frage)

☐ Genau eine verteidigbare Antwort? ☐ Quelle geprüft + `stand_datum`?
☐ Längen-Gates eingehalten? ☐ Antwortlängen balanciert, Form einheitlich?
☐ Distraktoren artgleich + plausibel? ☐ 3 Tipps in Stufen-Dramaturgie, keiner
verrät die Antwort? ☐ Erklärung mit Begründung? ☐ Schwierigkeit gegen
Anker-Persona (3.1) gebaucht-testet? ☐ Region-Flag korrekt? ☐ Verbots-Liste
gecheckt, ggf. Altersflag? ☐ Verfallsdatum falls zeitgebunden? ☐ ID im
eigenen Bereich?

---

## 6. Datei-/Pack-Organisation

### 6.1 Verzeichnis-Layout (FINAL: ein File pro Unter-Kategorie)

```
content/
  schema/
    frage.schema.json            # JSON-Schema v1 (maschinenlesbar, Quelle: Abschnitt 2)
    beispiel_fragen/             # die 8 Typ-Beispiele + 20 Eich-Fragen
  packs/
    core/                        # offizielles Datenset (nur faktencheck_status=geprueft)
      gaming/
        league_of_legends.json   # { "pack_meta": {...}, "fragen": [...] }
        pokemon.json
        ...
      sport/
        bundesliga.json
        ...
      ...                        # 14 Ordner (Ober-Kat) × je Unter-Kat-Datei = 90 Dateien
    haus/                        # lokale eigene Fragen (GM-Editor), gleiche Struktur
  assets/
    bilder/<unterkategorie>/q_<id>.webp
    audio/<unterkategorie>/q_<id>.ogg
    MEDIEN-MANIFEST.csv          # Datei;Verwendung;Quelle;Autor;Lizenz;Link;Änderungen
tools/content/
  validate_content.py            # das Gate aus 2.5 (CI + lokal)
  format_content.py              # Formatter (Key-Reihenfolge, Einrückung; idempotent)
  merge_packs.py                 # Packs → ein Runtime-Bundle (deterministisch sortiert)
  dedupe_report.py               # exakt + fuzzy über Gesamtbestand
  import_csv.py                  # CSV → Schema-JSON (mit Defaults)
```

Begründung „ein File pro Unter-Kategorie": git-freundlich (Merge-Konflikte
bleiben lokal), 10+ parallele Agents kollidieren nicht (ein Agent = eigene
Dateien + eigener ID-Bereich), und „eigene Fragen super leicht addierbar"
heißt: eine Datei anfassen, Validator laufen lassen, fertig.

`pack_meta` je Datei: `{ name, oberkategorie, unterkategorie, schema_version,
sprache: "de", anzahl (vom Formatter gepflegt) }`.

### 6.2 Merge-/Validierungs-Tool-Anforderungen

1. `validate_content.py` implementiert ALLE Regeln aus 2.5 mit
   Zeilen-Kontext-Fehlern („bundesliga.json, Frage q_…_000117: nur 3
   Antworten") — Exit-Code ≠ 0 blockiert CI.
2. `merge_packs.py` baut aus aktivierten Packs ein Runtime-Bundle:
   deterministisch sortiert (nach id), Duplikate über Pack-Grenzen nach
   Priorität core > haus > community, Report („194 übernommen, 4 Duplikate
   übersprungen").
3. `dedupe_report.py` läuft beim Import UND als Batch über den Bestand
   (normalisierter Exakt-Match = Fehler; Fuzzy ≥ 85 % oder gleiches Paar
   Antwort+Unterkategorie = Warnung mit Gegenüberstellung).
4. Medien-Gate: jede Datei unter `content/assets/` braucht eine
   Manifest-Zeile, jede Manifest-Zeile eine existierende Datei, Lizenz aus
   Allowlist (7.2); bei CC-BY/OGA-BY Autor+Link nicht leer.
5. Alle Tools laufen offline und ohne Godot-Abhängigkeit (reines Python) —
   einhängbar in die bestehende Preflight-Kette.

### 6.3 Community-/Eigene-Fragen: Format + Import-Weg

Vier Wege, EIN gemeinsamer Import-Trichter (Schema-Validierung →
Duplikat-Check → Defaults setzen → Status `entwurf`/`community`, NIE
automatisch `geprueft` → einsortieren → Report):

1. **GM-Editor in-App (Königsweg):** Formular mit Kategorie-Dropdown-Kaskade
   (Taxonomie 1.2), Typ-Auswahl, 4 Antwortfelder + Korrekt-Toggle,
   **Schwierigkeits-Slider mit eingeblendeten Anker-Personas** („Kann das
   deine Oma? → Leicht"), GENAU 3 Tipp-Felder mit Stufen-Beschriftung
   (vage/eingrenzend/fast-Antwort), Erklärungs-Feld, Region-Schalter,
   Altersflag. Live-Vorschau im Show-Layout inkl. Längen-Gate-Anzeige
   (Zeichen-Zähler wird rot). Neue Fragen landen im Haus-Pack und sind
   SOFORT in der nächsten Runde spielbar („Ich schreib eine Frage über dich,
   Kevin!" ist ein Party-Feature).
2. **JSON-Import:** Datei im Schema (einzeln oder Array) per
   Datei-Dialog/AirDrop; Fehler-Report mit Zeilenkontext. Eine
   KI-Prompt-Vorlage (dieses Kapitel 5 als Prompt!) wird mitgeliefert.
3. **CSV-Import** (Lehrer/Vereins-Zielgruppe): feste Spalten
   `text; a1; a2; a3; a4; korrekt(1-4); schwierigkeit; kategorie;
   unterkategorie; region; tipp1; tipp2; tipp3; erklaerung; quelle`.
   Defaults: `typ=choice`, `altersfreigabe=ab0`,
   `faktencheck_status=entwurf`. Beispiel-CSV ist Teil des Features.
4. **`.mmpack` (Community-Format):** ZIP mit `manifest.json` (Pack-Name,
   Autor, Version, benötigte `schema_version`, Altersfreigabe-Maximum,
   Beschreibung, Cover-Emoji), `fragen/*.json`, optional `assets/`
   (Größen-Limit: 50 MB/Pack, Bild ≤ 1 MB, Audio ≤ 2 MB). Packs sind im
   GM-Bereich an-/abschaltbar wie DLCs, updatebar per Versionsnummer,
   teilbar als eine Datei. Haus-Pack-EXPORT als `.mmpack` ist Pflicht-Feature
   (so entsteht das Community-Ökosystem von selbst).

Community-Fragen werden im Show-UI dezent markiert (kleines Pack-Icon, kein
Warnschild). Laufzeit-Daten (Stats, Fehlerhaft-Flags) bleiben IMMER in der
Runtime-DB — auch für Community-Packs (Schlüssel: Frage-id + Pack-id).

---

## 7. Medien-Rechte-Regeln

### 7.1 Generierte Bilder (Haupt-Quelle für `bild_pixel`)

**Haus-Stil-Prompt-Vorlage v1 (wortwörtlich verwenden, nur MOTIV ersetzen):**

> „Sauberes, halb-realistisches Studio-Foto von **[MOTIV]**, ein einzelnes
> Objekt, exakt zentriert, komplett im Bild, weicher einfarbiger
> Verlaufs-Hintergrund (hellgrau nach weiß), gleichmäßiges weiches Licht,
> kein Text, keine Wasserzeichen, keine Logos oder Markenzeichen, keine
> Menschen, quadratisch 1024×1024."

Regeln:
1. EIN Stil für alle Pixel-Bilder — kein Stil-Mix innerhalb einer Runde
   (sonst raten Spieler den Stil statt das Motiv).
2. **Qualitäts-Gate Mensch:** Jedes Bild wird vor Aufnahme geprüft: Ist das
   Motiv eindeutig DAS, was die Antwort behauptet? (Halluzinations-Schutz —
   falsche Tier-Anatomie fliegt raus.)
3. **Verboten:** generierte Bilder realer Personen (Persönlichkeitsrechte),
   „im Stil von [lebender Künstler]"-Prompts, Marken/Logos/ikonische
   Figuren-Designs. Film-SITUATIONEN nur als generische Nachstellung ohne
   Schauspieler-Ähnlichkeit und ohne Kostüm-1:1 (im Zweifel: raus —
   Strichmännchen/Emoji-Variante ist witziger UND sicherer).
4. `medien.quelle_art = "generiert"`, `lizenz = "eigen"`,
   `aenderungen = "Haus-Stil-Prompt v1"`.

### 7.2 Lizenz-Allowlist (für ALLE Fremd-Medien, technisch erzwungen)

**Erlaubt:** CC0 · Public Domain · CC-BY 3.0/4.0 · OGA-BY 3.0.
**Verboten:** alle NC- (non-commercial) und ND- (no derivatives) Varianten
(App ist kommerziell, Verpixeln/Schneiden ist Bearbeitung). **CC-BY-SA** nur
per dokumentierter Einzelfreigabe im Review (Share-Alike-Kette am
Bild-Derivat — konservative Linie: im Zweifel weglassen).
Pixabay-Content-License: nur für Audio, nur bearbeitet, mit
„bearbeitet"-Vermerk (kein CC!; keine Standalone-Redistribution). Freesound:
raus (Login-Pflicht für Downloads).

### 7.3 Wikimedia Commons (Personen, Orte, Kunst)

- Pflichtfelder im Schema (`medien`): `lizenz`, `autor`, `quelle_url`,
  `aenderungen` — maschinenlesbares Lizenz-Manifest, vom Validator erzwungen.
- **Attribution doppelt:** (a) On-Screen dezent ERST IM AUFLÖSUNGS-Moment
  („Foto: <Autor>, CC-BY 4.0, Wikimedia Commons" als Bildunterschrift — nie
  vorher, der Credit würde die Antwort spoilern), (b) vollständige Liste mit
  Links im Credits-Screen der App.
- Gemeinfreie GEMÄLDE (Künstler > 70 Jahre tot, Foto-Reproduktion 2D) sind
  die sicherste Kunst-Quelle → `gemaelde_erkennen` baut komplett darauf.
- Personen-Fotos: nur Personen des öffentlichen Lebens in öffentlicher
  Rolle, saubere Lizenz, würdevoller Kontext.

### 7.4 Audio (CC0-Stack)

- **Quellen-Prioritäten:** (1) selbst aufnehmen (Alltagsgeräusche — ein
  Aufnahme-Nachmittag deckt Dutzende Fragen, 100 % eigene Rechte);
  (2) CC0-Packs: Kenney.nl (explizit kommerziell ok), BigSoundBank
  (login-frei), Wikimedia Commons PD (stabile `Special:FilePath`-URLs);
  (3) gemeinfreie Klassik NUR als nachweislich gemeinfreie/CC0-AUFNAHME
  (die Aufnahme hat eigene Leistungsschutzrechte — nie „irgendeine"
  Beethoven-Aufnahme!); (4) Pixabay nur bearbeitet (7.2).
- **Hart verboten:** Chart-Musik/Song-Intros aus echten Aufnahmen —
  deshalb ist `intro_erkennen` in v1 klein (PD-Klassik + Eigen-Einspielung)
  und die Audio-Masse liegt bei Geräusch-Fragen (Tiere, Alltag, Instrumente,
  verlangsamt/rückwärts-Verfremdungen gemeinfreier Musik).
- Jede Audio-Datei: Zeile im `MEDIEN-MANIFEST.csv` + `medien`-Felder im
  Fragen-Datensatz; CI-Gate prüft beides gegeneinander (Katalog 10, Idee 25).

### 7.5 Film-Content OHNE Rechte-Risiko (FINAL entschieden)

**KEINE urheberrechtlich geschützten Film-Clips. Punkt.** Stattdessen drei
Säulen:
1. **Text-Fragen** (risikoärmste Quelle): Plot-Paraphrasen in eigenen Worten,
   „Echter Film oder ausgedacht?", „Film nach 3 Begriffen" („Hai. Strand.
   Bürgermeister."), Titel/Jahr/Regie-Fakten — Fakten sind nicht
   schutzfähig. Kurz-ZITATE nur mit Quellenangabe und sparsam;
   Plot-Paraphrasen bevorzugen.
2. **Emoji-Rätsel** (`emoji`-Typ): Titel + Emojis = unkritisch, hoher
   Party-Faktor, deckt mit (1) zusammen 80 % des „Film-Abend"-Gefühls ab.
3. **Blender Open Movies** (Big Buck Bunny, Sintel, Tears of Steel,
   Elephants Dream, Cosmos Laundromat — CC-BY, Attribution an Blender
   Foundation): echte Clips für „Was passiert als Nächstes?",
   Standbild-Pixel-Raten, Szenen-Chronologie. Fragen so bauen, dass
   Filmkenntnis NICHT Voraussetzung ist (visuelle Logik reicht).
   Ergänzend: NASA-Material (PD) für Weltraum, Stummfilm-Klassiker vor 1929
   (Gemeinfreiheit je Titel einzeln prüfen).

**Sonderfall Flaggen** (`flaggen_erkennen`): Staatsflaggen sind als amtliche
Werke gemeinfrei — wir rendern eigene Vektor-Versionen aus PD-Vorlagen
(einheitlicher Look, keine Attribution nötig). Karten später aus Natural
Earth (Public Domain).

---

## Anhang: Offene Punkte (bewusst NICHT in diesem Plan entschieden)

- Konkrete Money-Werte pro Show-Format (gehört zum Ökonomie-Plan, Katalog 14).
- `.mmpack`-Signierung/Moderation für öffentliches Teilen (P3, erst wenn
  Editor + Kuration stehen).
- Mehrsprachigkeit (`sprache`-Feld ist vorbereitet, v1 ist komplett `de`).
- Karten-Frage-Typ (Katalog 13, Idee 11) — teuerstes Format, kommt frühestens
  mit Welle 2 und würde `typ: "karte"` + Schema-Version 2 bedeuten.
