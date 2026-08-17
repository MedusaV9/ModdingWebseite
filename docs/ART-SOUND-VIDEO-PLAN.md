# MONKEY MONEY — ART-SOUND-VIDEO-PLAN (verbindlich)

Konsolidiert aus den Ideen-Katalogen 08 (Charaktere), 09 (Art/Bühne), 10 (Sound),
11 (Cutscenes/Video), 20 (Polish) sowie den Bühnen-Anforderungen aus 01/02
(Show-Formate, Minispiel-Mechaniken). Dieses Dokument ENTSCHEIDET — wo die
Kataloge Optionen nennen, steht hier die finale Wahl mit Begründung.
Asset-Staging auf der VM: `/tmp/mm-sounds/` (7 Kenney-CC0-Packs, 559 OGGs),
`/tmp/mm-music/` (6 Kevin-MacLeod-Tracks, CC-BY), `/tmp/mm-crowd/`
(5 Wikimedia-Applaus-Dateien, PD/CC-BY).

Stilkern in einem Satz (aus Katalog 09, bestätigt):
**„Eine 70er-Jahre-Gameshow, die mitten im Dschungel aufgebaut wurde und deren
Preisgeld von Affen bewacht wird."** Casino-Gold + Studio-Glow trifft
Blattgrün + Bananengelb, alles in flachem Vektor-Look mit dicken
warm-schwarzen Outlines.

---

## 1. ART-STYLE-BIBEL

### 1.1 Finale Farbpalette „Banana Vault" (12 Farben + Outline-Konstante)

Übernommen aus Katalog 09/A-02, hiermit festgeschrieben. Als CSS-Custom-
Properties und als Palette-Clamp-Ziel für alle generierten Bilder.

| Rolle | Name | Hex |
|---|---|---|
| Studio-Dunkel (Hintergrund) | Jungle Night | `#0E2A1F` |
| Bühnen-Grün (Flächen) | Deep Palm | `#14532D` |
| Blatt-Grün (Deko, Erfolg) | Leaf | `#22A559` |
| Frisch-Lime (Akzent, Streaks) | Banana Leaf | `#8FE04B` |
| Geldschein-Grün | Bill Green | `#85BB65` |
| Casino-Gold (Money, Rahmen) | Vault Gold | `#F5B301` |
| Gold-Hell (Glanzkanten) | Coin Shine | `#FFDE6B` |
| Bananengelb (Logo, Maskottchen) | Banana | `#FFC93C` |
| Vorhang-Rot (Fehler, Drama) | Curtain | `#C2183B` |
| Show-Magenta (Spotlights, Buzzer) | Spotlight Pink | `#FF3E8E` |
| LED-Cyan (Screens, Timer) | Studio LED | `#29D9D5` |
| Papier-Creme (Karten, Text auf dunkel) | Ticket Paper | `#FFF6E3` |

13. Konstante: **Outline-Warm-Schwarz `#1A1208`** — NIE reines Schwarz.

**Die 5 Kern-Hex** (wenn nur fünf genannt werden dürfen): `#0E2A1F` Jungle
Night · `#F5B301` Vault Gold · `#FFC93C` Banana · `#22A559` Leaf ·
`#1A1208` Outline-Warm-Schwarz.

**Spielerfarben (bis 8):** aus der Palette abgeleitet + 4 Zusatztöne:
Orange `#F97316`, Violett `#8B5CF6`, Blau `#3B82F6`, Pink `#F472B6` —
alle gegen `#0E2A1F` UND `#FFF6E3` kontrastgeprüft (WCAG ≥ 3:1 für große
Flächen). Volle 8er-Reihe: Banana `#FFC93C`, Spotlight Pink `#FF3E8E`,
Studio LED `#29D9D5`, Banana Leaf `#8FE04B`, Orange, Violett, Blau, Pink.

### 1.2 Typografie — ENTSCHIEDEN: 2 Fonts, beide OFL, beide Google Fonts

| Rolle | Font | Lizenz | Begründung |
|---|---|---|---|
| **Display/Logo/Runden-Titel** | **Bungee** (+ Schwester-Schnitt **Bungee Shade** fürs Logo) | OFL 1.1 | Leuchtreklamen-/Casino-Marquee-Charakter passt exakt zum „Jungle-Casino-TV"-Kern; Bungee Shade liefert die 3D-Schatten-Ebene fürs Logo gratis (gleiche Metriken, gleiche Familie, eine Lizenz). Auf 3 m Wohnzimmer-Distanz maximal lesbar. |
| **Text/UI/Zahlen** | **Rubik** (Variable Font) | OFL 1.1 | Runde Ecken passen zur Formensprache, exzellente Handy-Lesbarkeit, unterstützt `font-variant-numeric: tabular-nums` — Kontostände zappeln beim Hochzählen nicht in der Breite. Eine WOFF2-Datei deckt Fließtext UND Money-Zahlen ab. |

Regeln: Display-Font NIE unter 32 px und NIE für mehr als 6 Wörter am Stück.
Beide Fonts als WOFF2 + OFL-Lizenztext ins Repo (`assets/fonts/LICENSES/`) —
kein CDN (HTTP-only-Server). Katalog-Alternative „Luckiest Guy" ist Apache
2.0, nicht OFL → verworfen zugunsten der reinen OFL-Vorgabe; „Nunito" bleibt
als benannter Fallback, falls Rubik im Handy-Test zu technisch wirkt.

### 1.3 Formen- & Outline-Regeln (die 6 Gesetze)

1. **Outlines:** 4–6 px bei 1080p-Referenz, IMMER `#1A1208`, leicht
   unregelmäßig (handgezeichnet, nicht geometrisch perfekt).
2. **Wonky-Regel:** Formen 2–3° aus der Achse gedreht, Ecken gerundet,
   nichts perfekt parallel. Perfekte Ausrichtung ist ein Stilbruch.
3. **Sticker-Prinzip:** Jedes UI-Element (Button, Namensschild, Frage-Karte)
   = Fläche + dicke Outline + 2 px versetzter HARTER Schlagschatten in
   `#1A1208` bei 40 % Deckung. KEINE weichen Blur-Schatten (Stilbruch +
   Repaint-Kosten auf Low-End-Handys).
4. **Verlaufs-Deckel:** Max. 2 Verläufe pro Screen, beide nur radial
   (Spotlight-Kegel, Gold-Schimmer). Alles andere: Flächen.
5. **Licht IMMER von oben-mitte** (Studio-Rig) — gilt auch für generierte
   Bilder (steht im Stil-Prompt, 1.6).
6. **Squash & Stretch** per `transform: scale()`: Idle 100 %, Pressed 92 %
   + 2° Rotation, Erfolg 108 % Bounce. Nur `transform`+`opacity` animieren.

### 1.4 Logo-Design „MONKEY MONEY" (Beschreibung für die Reinzeichnung)

- Wortmarke zweizeilig in **Bungee Shade**, „MONKEY" über „MONEY", beide
  Wörter 3° gegeneinander verkippt (Wonky-Regel).
- Die beiden **O in „MONEY" sind Goldmünzen** (Vault Gold `#F5B301` mit
  Coin-Shine-Glanzkante) mit **Affenkopf-Prägung** (derselbe Kopf wie auf
  dem Geldschein, 1.5).
- Das **Y läuft in einen geringelten Affenschwanz** aus, der die gesamte
  Wortmarke unterstreicht.
- Darüber als Emblem der **„Bananen-Dollar"**: eine Banane, um die sich ein
  $-Doppelbalken wickelt — zugleich Sekundär-Logo, App-Icon und
  Bumper-Wipe-Objekt (5.1).
- Farbfassung: Banana `#FFC93C` auf Jungle Night `#0E2A1F` mit
  Vault-Gold-Kontur; dazu von Anfang an eine einfarbige Variante (nur
  `#1A1208`) für Stempel/Wasserzeichen.
- Produktion: 2–3 generierte Entwürfe als Moodboard, finale Marke als
  **SVG nachgebaut** (verlustfrei skalierbar, per CSS umfärbbar). Die
  3D-Version entsteht in Blender (5.3) NACH Freeze der SVG-Marke.

### 1.5 Money-Schein-Design: der „Banana Buck" (1 Schein = 50 MM)

DAS Signature-Asset (Stapel, Regen, Klau, Handy-Mini-Stapel):
- Querformat 2:1, Bill Green `#85BB65`, Ticket-Paper-Rand, Guilloche-
  Andeutung aus 3–4 geschwungenen Linien (mehr nicht — Flat-Look).
- Mitte: **Oval-Portrait „Präsident Bananas"** — würdevoll blickender Affe
  mit Monokel und grüner Krawatte, Dreiviertel-Ansicht, dicke Outline.
- Ecken: „50" in Rubik (tabular). Banner unten:
  „BANANA BUCK — IN MONKEY WE TRUST".
- **Seriennummer = Spielername + Spielerfarbe als Farbbalken** — bei
  Klau-Animationen sieht man, WESSEN Scheine fliegen.
- Rückseite (für Flip-Animationen): Bananen-Dollar-Emblem groß.
- Produktion: 1 generiertes Referenz-Portrait (das Stil-Referenzbild für
  ALLE weiteren Generierungen, s. 1.7), Rest als SVG-Layout mit
  eingebettetem 256-px-Portrait.

### 1.6 Stil-Prompt-VORLAGE (der „Stil-Stempel" — an JEDEN Bild-Prompt anhängen)

```
[MOTIV, 1–2 Sätze, z. B. "a dignified cartoon monkey portrait wearing a
monocle and a green necktie, oval bust composition, facing three-quarter
left"]
STYLE LOCK: flat 2D vector cartoon in the style of a 1970s TV game show
poster, bold uneven dark warm-brown outlines (#1A1208), thick rounded
shapes tilted 2-3 degrees, saturated palette ONLY: jungle greens (#0E2A1F,
#14532D, #22A559), banana yellow (#FFC93C), casino gold (#F5B301), cream
paper (#FFF6E3), accents magenta (#FF3E8E) and cyan (#29D9D5). Lighting
implied from top-center studio spotlight. Subtle paper grain. NO gradients
except one soft radial glow. Flat colors, sticker-like.
NEGATIVE: no photorealism, no 3D render, no soft shadows, no text, no
watermark, no thin lines, no complex background.
```

Zusatzregeln: Freisteller immer „on plain solid #FF00FF background";
Kacheln (Noise, Boden) mit „seamless tileable". Konsistenz-Workflow:
(1) Referenzbild „Präsident Bananas" zuerst festnageln, dann jedem Prompt
beilegen („match the exact art style of the reference image");
(2) Asset-Familien in EINER Session als Gruppe generieren („character
sheet, 5 poses of the same monkey"); (3) Pflicht-Nachschritt
**Palette-Clamp**: Skript (Node + sharp) mappt jedes Ergebnis auf die 13
Festfarben (nearest-neighbor im Lab-Raum, Dithering aus) und setzt
Outlines auf exakt `#1A1208`. Pro Familie eine `PROVENANCE.md`
(Prompt, Datum, Modell).

---

## 2. CHARAKTER-ENSEMBLE FINAL

### 2.1 Die 8 Affen (ENTSCHIEDEN)

Aus den 12 Kandidaten von Katalog 08: die 4 MUSTs gesetzt, dazu 4 SHOULDs
nach maximalem Silhouetten-/Persönlichkeits-Kontrast (breit / gebückt /
hängend / Federkrone) und Feature-Synergie (Schorsch = AFK-Gag). Rico
Rendite, Professor Pavian, Klaus Kleingeld und Fiona Fifty-Fifty werden
Shop-Unlocks in Update 1+2 (füttert die All-time-Money-Ökonomie).

Grundregel bleibt: **Jeder Affe ist als schwarze Silhouette in 0,5 s
erkennbar** — genau EIN übertriebenes Silhouetten-Merkmal, Farben sind
Customization, die Silhouette nie.

| # | Name | Persönlichkeit | Silhouetten-Merkmal | Default-Farbe (Fell/Prop) | Reaktions-Set (Jubel / Frust / Sieg) | Buzzer-Sound-Charakter |
|---|---|---|---|---|---|---|
| 1 | **Don Bananas** (der Pate) | Schmieriger Affen-Pate; jede Antwort klingt wie ein Angebot, das man nicht ablehnen kann | Breite Schultern im Nadelstreifen-Sakko + Fedora, Bananen-Zigarre | Anthrazit-Sakko auf Schoko-Fell, Gold-Akzente `#F5B301` | Revers-Zupfer + Fingerschnippen, 1 Schein segelt herab / Zigarre langsam ausdrücken, Zeitlupen-Kopfschütteln / lehnt am offenen Geldkoffer, tippt an die Hutkrempe | Tiefer Kontrabass-Pizzicato-Plonk |
| 2 | **Gitti Giro** (die Buchhalterin) | Pedantisch, rechnet alles nach, blüht bei Fehlern ANDERER auf | Turmhohe Bienenkorb-Frisur mit Bleistift + Abakus | Aschgrau-Fell, Frisur mit Studio-LED-Cyan-Tönung `#29D9D5` | Karateschlag über 3 Abakus-Kugeln + zackiges Nicken / Brille beschlägt, hektisches Putzen / Riesen-„GEBUCHT"-Stempel, Quittungs-Konfetti | Kassen-Kaching (Chips-Klimpern) |
| 3 | **Kiki Krawall** (das Chaos-Äffchen) | Hyperaktiv, behandelt jede Runde wie ein Stadionfinale | Kleinster Charakter, riesige nachwippende Antennen-Wuschelfrisur | Flamingo-Rosa `#F472B6`, Frisur Orange `#F97316` | Dreifach-Salto, Frisur kreist nach / wirft sich bäuchlings aufs Podium, trommelt / Sprung an den „Bildschirmrand", hängt wie an einer Reckstange | Hoher Quäk/Kazoo-Kiekser |
| 4 | **Baron Bodo von Bananenstein** (der Adelige) | Verarmter Adel, tut als spiele er zum Zeitvertreib, braucht das Preisgeld verzweifelt | Zylinder + Stehkragen-Umhang + Monokel, Banane als Weinglas | Violett-Umhang `#8B5CF6` auf Gold-Blond-Fell | Ein-Finger-Klatschen, dann Zylinderwurf (darunter: zweiter Zylinder) / Monokel ploppt raus, baumelt / Umhang-Schwung, verbeugt sich vor sich selbst | Näselnder Cembalo-Sting + Monokel-Plopp |
| 5 | **Oma Zinseszins** (die Unterschätzte) | Lullt alle ein, gewinnt eiskalt die Finalrunde — sie hat Zeit mitgebracht | Gebückte Haltung, Kopftuch mit Knoten, Riesen-Handtasche, Strickzeug | Lavendel-Grau-Fell, Kopftuch Curtain-Rot `#C2183B` | Strickt blitzschnell „1. PLATZ"-Schal / strickt demonstrativ weiter, EINE Masche fällt (Zoom) / Handtasche auf: Goldbarren-Stapel, Zwinkern | Handtaschen-Verschluss schnappt zu |
| 6 | **Pumper-Paule** (der Gym-Gorilla) | Gutmütiger Kraftprotz: „Ich hab die Antwort GEDRÜCKT, also stimmt sie" | Massives V-Profil, winziger Kopf, Tanktop, Shaker — breiteste Silhouette | Schoko-Braun-Fell, Tanktop Blau `#3B82F6` | Doppel-Bizeps, Podium bekommt einen Riss / zerdrückt Shaker, Protein-Fontäne / stemmt sein Podium samt Namensschild über den Kopf | Dumpfer Hantel-Wumms |
| 7 | **Schnarch-Schorsch** (der Tiefenentspannte) | Nickt zwischen Fragen weg, buzzert trotzdem in letzter Sekunde | Hängende Schultern, halb geschlossene Lider, Zipfelmütze mit Nachschwing-Bommel | Blaugrau-Fell, Mütze Banana Leaf `#8FE04B` | Schlagartiges Erwachen, ein Armwurf, schläft im Stehen weiter / Schulterzucken + Gähnen, dreht sich weg / liegt quer auf dem Podium, Siegerkranz als Schlafmaske | Wecker-Rasseln |
| 8 | **Glitzer-Gina** (die Diva) | Überzeugt, dass die Show nach ihr benannt gehört; reklamiert jede Kamera | Hochgesteckte Federkrone + Federboa, Dauer-Pose-Hand überm Kopf | Gold-Blond-Fell `#FFDE6B`, Boa Spotlight Pink `#FF3E8E` | Spotlight schwenkt (unaufgefordert) auf sie, Glitzer, Kusshand / reißt der Boa eine Feder aus, pustet sie weg / Lichtkegel von oben, sie „badet" im Licht | Glöckchen-Schimmer + Vegas-Blip |

Roster-Dramaturgie: v1-Start-Auswahl auf dem Handy zeigt alle 8; die 4
MUSTs (1–4) sind die Default-Vorschläge für schnelle Lobbys. Alle 8 nutzen
das Slot-Datenmodell aus Katalog 08 (Kopf/Gesicht/Hand/Körper/Buzzer/
Sieg-Pose/Namensschild/Taunt) von Tag 1, auch wenn v1 nur Farbe+Hut
freischaltet.

### 2.2 Machart-ENTSCHEIDUNG: 2D-Vektor-Pappfiguren (SVG/Canvas im Browser)

**Gewählt: Option A — 2D-Cutout-Pappfiguren mit Gelenk-Animation,
„Kasperletheater deluxe".** Blender-Low-Poly-Sprite-Sheets und Live-Three.js
sind verworfen (Three.js komplett; Blender nur für 3 Nicht-Charakter-Assets,
s. 2.3).

Begründung (pragmatisch fürs Party-Spiel):
1. **Stil:** Der Jackbox-Look IST Cutout — Pappfiguren mit sichtbaren
   Niet-Gelenken sind kein Platzhalter, sondern ein valider Endstil. 3D
   kämpft gegen den Flat-Look (bräuchte Flat-Shader, um wieder wie 2D
   auszusehen).
2. **Technik-Risiko:** Live-Three.js bringt WebGL-Context-Loss auf
   iPad-Safari, ~170 KB gzip Grundgewicht und Text-Rendering-Schmerz; die
   DOM/CSS+Canvas-Bühne (3.1) läuft dagegen mit Compositor-Transforms auf
   ProMotion-120-Hz und ist auf der GPU-losen Dev-VM snapshot-testbar.
3. **Produktionskosten:** EIN Grundskelett (~10–14 Teile: Kopf, Kiefer,
   Torso, 2×Ober-/Unterarm, 2×Bein, Schwanz, Hut-Slot, Hand-Prop-Slot) für
   alle 8 Affen; Silhouetten-Merkmale sind ausgetauschte Teil-Sprites + 1–2
   Extra-Gelenke (Frisur, Bommel). Basis-Animationen (Idle, Jubel, Frust,
   Sieg, Schlafen, Buzz) werden EINMAL gebaut und geerbt; nur die
   Signature-Clips (Tabelle 2.1) sind pro Charakter. Blender-Sprite-Sheets
   würden pro Pose/Winkel/Charakter Render-Batches erzeugen — bei 8
   Charakteren × Reaktionen × Customization-Farben explodiert das.
4. **Customization gratis:** Fell-/Kleidungsfarben über Palette-Swap
   (Graustufen-Masken + Gradient-Map bzw. CSS-Filter auf SVG-Layern) — ein
   Asset-Satz bedient alle Farb-Unlocks. Mit Sprite-Sheets unmöglich ohne
   Duplikate.
5. **Handy-Seite:** Der Mini-Avatar auf dem Controller ist dieselbe
   geschichtete SVG-Figur mit CSS-Keyframes (nicken, zittern, jubeln) —
   wenige KB, läuft auf jedem Alt-Handy, hält das
   200-KB-Client-Budget.

Konsequenz für die Bühne: Podium-Reaktionen (richtig/falsch) werden 150 ms
versetzt abgespielt (Links→Rechts), damit der „Reaktions-Schwenk" als
wiederkehrender Show-Beat lesbar ist. Idle-Schicht: atmen/blinzeln +
Mikro-Gag alle 6–12 s (injizierter RNG — testbar).

### 2.3 Blender-Einsatz: GENAU 3 Assets (nicht mehr)

Blender lohnt nur, wo echtes 3D-Licht hundertfach wiederverwendet wird:
1. **Logo-3D-Stinger** (3–4 s WebM, VP9+Alpha): „MONKEY MONEY" dreht ein,
   Münzen prallen physikalisch von den Lettern, Gold-Shader, Lichtblitz.
   Genutzt in: Show-Opening Beat 1–2, Trailer Shot 1+9, Tutorial-Outro,
   Lade-/Reconnect-Screen. Drei Fassungen: Alpha / auf Studio-Hintergrund /
   1-s-Kurzfassung („Logo-Bumper").
2. **Trophäe „Die Goldene Banane"**: Banane auf Marmorsockel mit
   Gold-Shader — als 360°-Turntable (36 Frames → Sprite-Sheet) für die
   Siegerehrung + als Still fürs App-Icon/Store-Material.
3. **Riesen-Affenhand** (Klau-Animation + Szenen-Übergang): 2–3
   Griff-Posen (offen / gegriffen / zerknüllend) als Renders mit Alpha —
   pelzige Hand braucht Licht/Fell-Tiefe, die im Flat-Look von Hand teuer
   wäre. Wird per Palette-Clamp (1.6) in den Stil eingepasst.

Alles andere (Tresor, Vorhang, Backdrop, Podien, Avatare) ist generiertes
Bitmap oder SVG — kein Blender.

---

## 3. BÜHNEN-/SCREEN-BLAUPAUSEN

Rendering-Grundsatz (aus Katalog 09/A-22, festgeschrieben): Bildschirm =
**DOM/CSS-2.5D-Bühne + EIN transparentes Vollbild-Canvas** ausschließlich
für Partikel (Money-Regen, fliegende Scheine, Konfetti, Affenhand). Kein
Three.js im Kern. Partikel-Deckel 120 Sprites (Screen) / 8 (Handy),
Auto-Degradation bei < 45 fps, `prefers-reduced-motion` = Stufe 3.

### 3.1 Bildschirm: Studio-Layout in Zonen

5-Ebenen-Bühne (hinten→vorn: Backdrop → LED-Wand → Podien → Bühnenboden →
Vordergrund-Blätter), alles an EINEM Wrapper (`--stage-zoom`/`--stage-x`).

```
┌────────────────────────────────────────────────────────────────┐
│ [E] TITEL-/STATUS-LEISTE  Runde 2/6 · „Flinke Affenfinger"  🍌⏱ │  ← Timer-Banane
├────────────────────────────────────────────────────────────────┤
│  ░ Blattwerk ░   ┌──────────────────────────┐   ░ Blattwerk ░  │
│                  │  [A] LED-FRAGEN-WAND     │        [D]      │
│   (Backdrop:     │  Frage · Antworten ·     │   JACKPOT-      │
│   Jungle Night   │  Kategorien-Logo ·       │   TRESOR        │
│   + Silhouetten) │  Zwischenstand           │   (Zähler)      │
│                  └──────────────────────────┘                 │
│ ┌────┐  ┌────┐  ┌────┐  ┌────┐  ┌────┐  ┌────┐  ┌────┐ ┌────┐ │
│ │[B] │  │    │  │    │  │    │  │    │  │    │  │    │ │    │ │  ← Podien-Reihe
│ │🐒  │  │🐒  │  │🐒  │  │🐒  │  │🐒  │  │🐒  │  │🐒  │ │🐒  │ │    (2–8, Flexbox)
│ │💵📛│  │💵📛│  │💵📛│  │💵📛│  │💵📛│  │💵📛│  │💵📛│ │💵📛│ │  Avatar+Stapel+Schild
│ └────┘  └────┘  └────┘  └────┘  └────┘  └────┘  └────┘ └────┘ │
│  Bühnenboden: Holzsteg + Gold-Kante, Spotkegel als Radial-Grad.│
├────────────────────────────────────────────────────────────────┤
│ [C] TICKER  „+++ Anna: 4 der letzten 5 Musikfragen +++ …"      │
└────────────────────────────────────────────────────────────────┘
```

Zonen: **[A] LED-Fragen-Wand** (trapezförmig verzerrt, Scanline-Overlay,
2 % Flacker, 200 ms Störbild-Zap beim Fragenwechsel) · **[B] Podien**
(Trapez-Pult in Spielerfarbe, Namensschild im Sticker-Stil, Kontostand
DOPPELT: Zahl in Rubik-tabular + physischer Banana-Buck-Stapel — 1 Schein =
50 MM, 10 Scheine = Bündel mit Banderole, 4 Bündel = Geldsack) · **[C]
Ticker** (nur in Ruhephasen, max. 1 Häppchen/20 s) · **[D] Jackpot-Tresor**
(Dauer-Spannungs-Anker, wackelt bei Einzahlung) · **[E] Status/Timer**
(Timer = Banane, die von rechts „aufgegessen" wird — Anforderung aus
Katalog 02).

### 3.2 Die 5 Kamera-/Szenen-Zustände

TV-Regie-Prinzip: harte Schnitte (2-Frame-Weißblitz), keine Fahrten;
Phasenwechsel über Bumper-Wipes (Bananen-Wipe = neutral, Money-Wipe =
Auszahlung, Licht-Blende = Akt-Wechsel). Server-Event mappt auf Zustand —
Clients sind dumme Renderer.

| Zustand | Kamera/Layout | Was ist sichtbar | Licht/Sound-Signatur |
|---|---|---|---|
| **1 · LOBBY** | Totale, leicht zurückgezoomt | Podien füllen sich beim Join (Umzieh-Wirbel bei Customization), LED-Wand zeigt Raum-Code GROSS + Attract-Loop gedimmt, Ticker aus | Volles Studiolicht; Lobby-Loop „Monkeys Spinning Monkeys"; Join-Plopp pro Spieler |
| **2 · FRAGE** | LED-Wand füllt 80 %, Podien ragen unten klein rein | Frage + Antwort-Optionen, Timer-Banane, „hat geantwortet"-Mini-Affen (anonym), Ticker AUS | Leicht gedimmt, LED-Cyan-Glow; Runden-Bett + Countdown-Ticker (duckt bei Vorlesen) |
| **3 · AUFLÖSUNG** | Crash-Zoom/Close-up auf Podien, 150 ms Wackel-Zoom auf den Buzzer-Gewinner | Richtige Antwort leuchtet, Reaktions-Schwenk über alle Affen (150 ms versetzt), Scheine fliegen im Bogen auf Podien | Riser → 0,5–1 s ECHTE Stille → Stinger; Spotkegel auf Gewinner |
| **4 · ZWISCHENSTAND** | Totale mit Fokus-Schwenk aufs Podien-Regal | Stapel-Vergleich, Platzierungs-Pfeile, „Börsen-News"-Einspieler (Halbzeit), Blick-zum-Führenden-Gag | Applaus-Stufe nach Punkte-Delta; Zwischenstands-Sting; Ticker AN |
| **5 · FINALE** | Eigenes Bild: Licht aus → 2 Spotlights, Podien der Finalisten mittig, Rest wird „Publikum" | Lianen-Finale-Setup (Katalog 01/A8), Jackpot-Tresor fährt zentral, glühende Ziffern | Blackout-Beat (400 ms), Herzschlag-Puls, Finale-Bett leiser als Runden-Bett; vor letzter Auflösung: totale Stille bis 2,5 s |

### 3.3 Handy: die 6 Kern-Screens (hochkant, Daumen-Zonen-Raster)

Festes Raster für ALLE Screens: oberes Drittel = Status (Mini-Avatar +
Kontostand als Mini-Scheinstapel + Rundeninfo), Mitte = Kontext, unteres
Drittel = Aktionen (Daumen). Durchgehend 4-px-Rahmen in Spielerfarbe +
`theme-color`; `viewport-fit=cover`, `touch-action: manipulation`.

```
1 · JOIN                2 · LOBBY                3 · FRAGE/ANTWORT
┌──────────────┐        ┌──────────────┐        ┌──────────────┐
│  LOGO (SVG)  │        │ Mini-Avatar  │        │🐒 nervös · 💵│ ← Status
│              │        │  (groß, ani- │        │ Timer-Balken │
│ ┌──────────┐ │        │   miert)     │        ├──────────────┤
│ │RAUM-CODE │ │        ├──────────────┤        │  Frage-Echo  │ ← tickert synchron
│ │ [ABCD]   │ │        │ Customizing: │        │  (Wort f. W.)│
│ └──────────┘ │        │ Farbe·Hut·   │        ├──────────────┤
│ ┌──────────┐ │        │ Buzzer-Sound │        │ ┌────┐┌────┐ │
│ │DEIN NAME │ │        │ (Slots-Grid) │        │ │ 🍌 ││ 🥥 │ │ ← 2×2-Grid,
│ └──────────┘ │        ├──────────────┤        │ ├────┤├────┤ │   je ≥96 px,
│ [REIN DA!▸]  │        │ [BEREIT ✓]   │        │ │ 🐒 ││ 🌴 │ │   Sticker-Stil
│  (XXL-Btn)   │        │ „4/6 bereit" │        │ └────┘└────┘ │   (Buzzer-Runde:
└──────────────┘        └──────────────┘        └──────────────┘    EIN Riesen-Kreis 70 %)

4 · WARTEN              5 · ERGEBNIS             6 · SHOP
┌──────────────┐        ┌──────────────┐        ┌──────────────┐
│ „EINGELOGGT✓"│        │  RICHTIG! 🎉 │        │ All-time-MM  │
│  (Stempel)   │        │  +300 MM     │        │  + Kontostand│
├──────────────┤        │ (Grün-Flash/ │        ├──────────────┤
│ Fidget-Affe: │        │  Rot+Shake)  │        │ Raritäten-   │
│ kaut Banane, │        ├──────────────┤        │ Grid: Blech/ │
│ reagiert auf │        │ Scheine flie-│        │ Silber/Gold/ │
│ Tippen; Timer│        │ gen in deinen│        │ Diamant      │
│ steuert Hektik│       │ Mini-Stapel  │        │ (Hüte·Posen· │
├──────────────┤        ├──────────────┤        │ Buzzer·Affen)│
│ „3/6 haben   │        │ Platz 2 ▲1   │        ├──────────────┤
│ geantwortet…"│        │ [WEITER ▸]   │        │ [ANPROBIEREN]│
└──────────────┘        └──────────────┘        └──────────────┘
```

Kern-Interaktionen: Lock-in = **Münz-Einwurf** (Münze mit Daumen in den
Schlitz flippen, erst DAS versiegelt die Antwort; bei Wettfragen mehrere
Münzen = Einsatz); Einsätze = **Scheine-Fächer-Slider** (Rastpunkt = 1
Schein = 50 MM, bestätigen per Swipe-up, Scheine landen 300 ms später auf
der Bühne); Feedback = Stempel „EINGELOGGT ✓" + Screen-Shake statt
Vibration (iOS-Safari hat kein `navigator.vibrate`); NIE ein leerer
Spinner (Fidget-Affe + ehrlicher Fortschrittstext).

### 3.4 GM-iPad: Cockpit-Layout (Querformat)

```
┌───────────────────────────────────────────────────────────────┐
│ [A] SHOW-FLOW (oben, volle Breite)                            │
│  Lobby ▸ R1 ▸ R2 ▸ [R3 LÄUFT] ▸ R4 ▸ Finale   [⏸ PAUSE] [⏭]  │
├──────────────────────────────┬────────────────────────────────┤
│ [B] LIVE-BÜHNENMONITOR       │ [C] SPIELER-MATRIX             │
│  (Mini-Vorschau des Screens, │  8 Zeilen: Avatar·Name·MM·     │
│  read-only, zeigt aktuellen  │  Verbindungs-Ampel·Antwort-    │
│  Szenen-Zustand 1–5)         │  Status·[+/− MM]·[Kick]·[Mute] │
├──────────────────────────────┼────────────────────────────────┤
│ [D] FRAGEN-PANEL             │ [E] SHOW-KNÖPFE (Daumen-Reihe) │
│  Aktuelle Frage + Antwort    │  [RICHTIG] [FALSCH]  [Rad 🎡]  │
│  (nur GM sieht die Lösung),  │  [Psst…📨] [Applaus] [Skip ⏭]  │
│  nächste 3 in der Warte-     │  [Taunts stumm] [Späti-Modus]  │
│  schlange, Schwierigkeit     │                                │
└──────────────────────────────┴────────────────────────────────┘
```

Regeln: [E] enthält NUR Knöpfe mit Sofort-Wirkung (Buzzer-Urteil,
Rad-Trigger, Privat-Tipp „Psst…"-Umschlag, manueller Applaus, Cutscene-
Skip); alles Seltene (Spieler kicken, MM korrigieren) liegt in der Matrix
[C] hinter einem Tap auf die Spielerzeile. Pause schaltet den Screen ins
Timeout-Aquarium (Affen planschen in ihren eigenen Scheinen).

---

## 4. SOUND-MAPPING FINAL

Bus-Architektur (Grundlage aller Regeln): Master → Music / SFX / Ticker /
Voice / Crowd. Ducking-Kette: Sprache > Stinger > Ticker > Musik (Vorlesen:
Musik −9…−12 dB, Ticker −6 dB, Crowd pausiert; Stinger: Musik kurz −6 dB,
300 ms zurück). Vor jeder wichtigen Auflösung 0,5–2,5 s ECHTE Stille.
Loudness beim Import normalisieren (Stinger ≈ −16 LUFS, Betten ≈ −24 LUFS,
ffmpeg `loudnorm`, einmalig). Häufige Sounds ±3–5 % Random-Pitch + 2–3
Varianten round-robin.

### 4.1 Event → Datei-Mapping (Staging-Pfade gesichtet, Kandidaten konkret)

Konvention: Primär-Kandidat ist die Datei, mit der gebaut wird; „Varianten"
= Round-Robin-Pool; Fallback = zweite Wahl aus dem Staging. Zielpfad im
Repo: `assets/audio/<gruppe>/<event>.ogg`.

**UI & Lobby** (Basis: `/tmp/mm-sounds/interface-sounds/Audio/`, `/tmp/mm-sounds/ui-audio/Audio/`)

| Event | Primär-Kandidat | Varianten/Fallback |
|---|---|---|
| Handy-Tap (Auswahl) | `interface-sounds/Audio/click_001.ogg` | `click_002–005`; Fallback `ui-audio/Audio/click1.ogg` |
| Bestätigen (Handy leise) | `interface-sounds/Audio/confirmation_001.ogg` | `confirmation_002–004` |
| Zurück/Abbrechen | `interface-sounds/Audio/back_001.ogg` | `back_002–004` |
| Ungültig/Fehler-Tap | `interface-sounds/Audio/error_004.ogg` | `error_001–008` |
| Join-Plopp (Screen, Lobby) | `interface-sounds/Audio/drop_002.ogg` | `drop_001/003/004`, `pluck_001/002` |
| Lock-in-Thunk (Screen, öffentlich) | `impact-sounds/Audio/impactPlank_medium_000.ogg` | `impactPlank_medium_001–004`, `impactWood_medium_*` |
| Panel auf/zu (GM-Cockpit) | `interface-sounds/Audio/maximize_003.ogg` / `minimize_003.ogg` | jeweils `_001–009` |
| Ticker-Lauftext | `interface-sounds/Audio/scroll_001.ogg` (leise) | `scroll_002–005` |
| Toggle/Setting | `interface-sounds/Audio/switch_001.ogg` | `switch_002–007`, `ui-audio/Audio/switch1–38.ogg` |

**Frage-Dramaturgie**

| Event | Primär-Kandidat | Varianten/Fallback |
|---|---|---|
| Frage-Einblendung | `interface-sounds/Audio/question_001.ogg` | `question_002–004` |
| Frage-Karte „ausgeteilt" | `casino-audio/Audio/card-slide-1.ogg` | `card-slide-2–8`, `card-place-1–4` |
| Countdown-Tick (Phase 1/2) | `interface-sounds/Audio/tick_001.ogg` / `tick_002.ogg` | `tick_004.ogg` (Achtung: `tick_003` existiert im Pack NICHT), `ui-audio/Audio/click3.ogg` |
| Zeit-um-Gong | `impact-sounds/Audio/impactBell_heavy_000.ogg` | `impactBell_heavy_001–004`, `interface-sounds/Audio/bong_001.ogg` |
| RICHTIG-Stinger | `digital-audio/Audio/threeTone1.ogg` + Layer `casino-audio/Audio/chips-collide-1.ogg` (Münz-Schimmer im Ausklang) | `threeTone2`, `highUp.ogg`; Jingle-Variante `music-jingles/Audio/Pizzicato jingles/jingles_PIZZI01.ogg` |
| FALSCH-Stinger | `digital-audio/Audio/lowThreeTone.ogg` | `lowDown.ogg`, `interface-sounds/Audio/error_006.ogg` |
| Auflösungs-Reveal (Wand zappt) | `interface-sounds/Audio/glitch_002.ogg` | `glitch_001/003/004`, `sci-fi-sounds/Audio/computerNoise_000–003.ogg` |
| **Auflösungs-Spannung** (Dreiklang: Spannung → 0,65 s ECHTE Stille → Stinger; UMGESETZT in `regie.ts`) | `extern/trommelwirbel_kurz_ccby_macleod.ogg` ↔ `extern/riser_ccby_tritachyon.ogg` (Round-Robin, beide exakt 1,75 s) | Musik-Bett fährt via `duck(…, 0)` auf NULL; Fanfare kommt 2,4 s verzögert |
| Siegerehrungs-Trommelwirbel (4 s + 0,8 s Stille → Fanfare + Jubel) | `extern/trommelwirbel_lang_cc0_iwan.ogg` | — |
| Streak-Aura an/aus | `sci-fi-sounds/Audio/forceField_000.ogg` (an) / `digital-audio/Audio/phaserDown1.ogg` (Pfffft) | `forceField_001–004` |

**Money & Casino** (Kernpack: `/tmp/mm-sounds/casino-audio/Audio/`)

| Event | Primär-Kandidat | Varianten/Fallback |
|---|---|---|
| Money-Kling KLEIN (Pling, ≤ 100 MM) | `casino-audio/Audio/chip-lay-1.ogg` ↔ `chip-lay-2` ↔ `chip-lay-3` (Round-Robin) | `chips-collide-1–4` |
| Money-Kling MITTEL (Kassenlade! + Münzen) | `extern/kasse_kaching_pd_wikimedia.ogg` + Layer `casino-audio/Audio/chips-handle-3.ogg` — echte Kassenlade BESCHAFFT (4.3 ✓) | `chips-handle-1–6` |
| Money-Kling GROSS (Münzregen ~1,5 s) | Layer `casino-audio/Audio/chips-stack-4.ogg` + `chips-collide-2` + `chips-collide-3` | `chips-stack-1–6` |
| Schein-Landung (Money-Regen, pro Schein Tick) | `casino-audio/Audio/card-place-2.ogg` (leise) | `card-place-1/3/4` |
| Schein-Fächer (Einsatz-Slider) | `casino-audio/Audio/card-fan-1.ogg` | `card-fan-2.ogg` |
| Kartenmischen (Kategorien-Shuffle) | `casino-audio/Audio/card-shuffle.ogg` | `cards-pack-open-1/2.ogg` |
| Würfel (Zufalls-Event/Bot) | `casino-audio/Audio/dice-throw-1.ogg` | `dice-throw-2/3`, `die-throw-1–4`, `dice-shake-1–3` |
| Shop-Kauf/Unlock | `digital-audio/Audio/powerUp7.ogg` + `casino-audio/Audio/chips-stack-2.ogg` | `powerUp1–12` |
| Jackpot-Tresor-Einzahlung | `casino-audio/Audio/chip-lay-3.ogg` + `impact-sounds/Audio/impactMetal_light_000.ogg` (Wackeln) | `impactMetal_light_001–004` |
| Tresor öffnet (Finale) | `sci-fi-sounds/Audio/doorOpen_000.ogg` + `impact-sounds/Audio/impactMetal_heavy_000.ogg` | `doorOpen_001/002` |

**Show-Momente & Charaktere**

| Event | Primär-Kandidat | Varianten/Fallback |
|---|---|---|
| Buzzer-Familie (8 Spieler-Slots, BESCHAFFT — 4.3 ✓) | Slot 1 Hupe `extern/buzzer_hupe_cc0_bsb.ogg` · 2 Fahrradklingel `buzzer_klingel` · 3 Quietsch-Ente `buzzer_quaek` · 4 Rezeptions-Glocke `buzzer_glocke` · 5 Boing `buzzer_boing` · 6 Trillerpfeife `buzzer_pfeife` · 7 Wecker `buzzer_wecker` · 8 Airhorn `buzzer_airhorn` (alle CC0 BigSoundBank, −16 LUFS) | Familie ist zugleich Shop-wählbar (`SHOP_ITEMS`); gekaufter Buzzer überstimmt den Slot-Standard (`standardBuzzer()` in `sound-map.ts`) |
| Klau „Affenhand" (Whoosh+Snatch) | Interim: `digital-audio/Audio/phaserUp3.ogg` + `casino-audio/Audio/card-shove-2.ogg` (Grabschen) | echtes Whoosh + Affen-Keckern fehlt (Lücke 2) |
| Stinkbananen-Ticken | `interface-sounds/Audio/tick_002.ogg` (beschleunigend sequenziert) | — |
| Stinkbanane PLATZT (Matsch!) | `sci-fi-sounds/Audio/slime_000.ogg` | `slime_001.ogg`, `impact-sounds/Audio/impactSoft_heavy_000–004.ogg` |
| Matschbananen-Treffer (Pie-Fight) | `impact-sounds/Audio/impactSoft_medium_001.ogg` | `impactSoft_*`, `impactPunch_medium_*` |
| Podium-Riss (Pumper-Paule-Jubel) | `impact-sounds/Audio/impactWood_heavy_000.ogg` | `impactWood_heavy_001–004` |
| Rad-Ticker (1 Klack, ratengesteuert) | `impact-sounds/Audio/impactWood_light_000–002.ogg` (Round-Robin — echter Holz-Ratschen-Klack, geprüft GEGEN `click_002` [10 ms, zu dünn] und `tick_004`/`click4` [zu digital]) | die Engine steuert das Tempo, KEINE lange Datei |
| Rad-Ergebnis Geld / Niete | Geld: Money-Kling GROSS · Niete: FALSCH-Stinger | Sad Trombone fehlt (Lücke, s. 4.3) |
| Einlauf-Schritte (Kandidaten-Vorstellung) | `impact-sounds/Audio/footstep_wood_000–004.ogg` | `footstep_carpet_*` (Backstage-Gag) |
| AFK-Einschlafen / Aufwachen | einschlafen: `digital-audio/Audio/phaserDown2.ogg` (leise) / aufwachen: `digital-audio/Audio/powerUp2.ogg` | Schnarch-Loop fehlt (Lücke) |
| Phasen-Stinger („Runde 2!", Kapitelmarken) | `music-jingles/Audio/Hit jingles/jingles_HIT00–16.ogg` (kuratieren: 4 Stück eine Familie!) | `Steel jingles/jingles_STEEL*` als Zweit-Familie fürs Finale |
| Runden-Sieg-Jingle | `music-jingles/Audio/Sax jingles/jingles_SAX10.ogg` (Kandidat, beim Einbau kuratieren) | `jingles_SAX00–16`, `jingles_PIZZI*` |
| Spiel-Sieg-Fanfare (kurz) | `music-jingles/Audio/Hit jingles/jingles_HIT14.ogg` (Kandidat) | echte große Fanfare fehlt (s. 4.3) |
| Fehlbuzz/Sperre | `interface-sounds/Audio/error_007.ogg` | `scratch_001–005` (Kratzer-Gag) |
| Rekord-Kratzer (Breaking-News/„alle falsch") | `interface-sounds/Audio/scratch_003.ogg` | `scratch_001–005` |

**Publikum** (Basis: `/tmp/mm-crowd/` — Lizenz steckt im Dateinamen)

| Event | Datei | Einsatzregel |
|---|---|---|
| Applaus höflich (~3 s) | `/tmp/mm-crowd/applause_kurz_pd_thore.ogg` | kleine Punkte-Deltas, Einzel-Reveals |
| Applaus ordentlich (~6 s) | `/tmp/mm-crowd/applause_mittel_pd_thore.ogg` | Rundenende, gute Antworten-Serie |
| Applaus groß | `/tmp/mm-crowd/applause_gross_ccby_RHumphries.ogg` | Zwischenwertung Platz-1-Wechsel (CC-BY → Attribution!) |
| Jubel-Sturm | `/tmp/mm-crowd/applause_jubel_pd_starlite.ogg` | Finale-Einzug, Sieger-Reveal |
| Anlaufender Applaus | `/tmp/mm-crowd/applause_anlaufend_pd_stephan.ogg` | Kandidaten-Vorstellung (baut sich pro Spieler auf) |

Applaus-Stufe koppelt an Punkte-Delta, NIE zufällig. Lacher/Raunen/Crickets
fehlen komplett (Lücke 2, s. 4.3).

### 4.2 Musik-Zuordnung (6 MacLeod-Tracks, ENTSCHIEDEN)

| Show-Phase | Track (`/tmp/mm-music/`) | Begründung/Regel |
|---|---|---|
| **Lobby/Join + Pausen-Aquarium** | `MonkeysSpinningMonkeys.mp3` | Die Signatur der Show (thematischer Volltreffer, loopable). −12 dB unter Sprache, Ducking bei Host-Ansagen. |
| **Runden-Bett (normale Frage-Runden)** | `QuirkyDog.mp3` | Treibend-verspielter Swing, stört Denkphasen nicht; Stufen über Volume/EQ-Varianten (Stems gibt es nicht). |
| **Klau-/Wett-/Schleich-Runden** (Taschendieb, Alles-oder-Banane, Psst-Umschlag) | `SneakySnitch.mp3` | DER Schleich-Klassiker; koppelt Mechanik an Klangwelt — Wiedererkennung „gleich wird’s fies". |
| **Glücksrad + Bonus-/Chaos-Segmente** | `MerryGo.mp3` | Jahrmarkt-Karussell = Rad-Assoziation; startet mit dem Rad-Einspieler, endet HART vor dem Auslauf-Ticker (Ticker braucht Stille). |
| **Zwischenstand „Börsen-News" + Fake-Werbepause + Shop** | `LocalForecastElevator.mp3` | Fahrstuhl-/Nachrichten-Muzak — ironische News-Desk-Untermalung, perfekt für den Werbepausen-Gag. |
| **Tutorial/Onboarding + Warte-Momente** | `FluffingADuck.mp3` | Gutmütig-tapsig, nimmt Erklär-Momenten die Strenge. |
| **Finale-Bett** | — FEHLT (s. 4.3) | Bis dahin: KEINE Musik im Finale, nur Herzschlag + Ticker (Stille trägt) — das ist sogar die dramaturgisch sauberste v1-Lösung. |
| **Sieger-Hymne** | — FEHLT (s. 4.3) | Interim: `jingles_SAX10` + `applause_jubel_pd_starlite.ogg` + Money-Regen. |

### 4.3 Lücken-Liste (Stand nach der Audio-Feinschliff-Runde)

**GESCHLOSSEN (beschafft, normalisiert, gemappt — Attribution in CREDITS.md):**

| # | Lücke | Beschafft (alle in `assets/audio/extern/` + `client/public/audio/sfx/`) |
|---|---|---|
| **1 ✓** | **Trommelwirbel + Riser** (Auflösungs-Dreiklang) | 2 Trommelwirbel: `trommelwirbel_kurz_ccby_macleod.ogg` (Wikimedia, Kevin MacLeod „assorted rimshots", CC-BY 3.0, 1,75 s) + `trommelwirbel_lang_cc0_iwan.ogg` (Wikimedia „Drum Roll Intro", CC0, 4 s); 1 Riser: `riser_ccby_tritachyon.ogg` (OpenGameArt „Riser 42", Tri-Tachyon, CC-BY 4.0, auf 1,75 s geschnitten). Dreiklang in `regie.ts` verdrahtet: Spannung → 0,65 s ECHTE Stille (`duck(…, 0)`) → Stinger/Fanfare; Siegerehrung mit 4-s-Wirbel + 0,8 s Stille. Wikimedia-Kandidat „Paukenwirbel (Wiener Pauke)" wegen CC-BY-**SA** verworfen. |
| **3 ✓** | **Buzzer-Timbre-Familie** | 8 echte Timbres, alle CC0 BigSoundBank (Joseph SARDIN): Hupe #0258, Fahrradklingel #0275, Quietsch-Ente #0417, Rezeptions-Glocke #0479, Boing #2284, Trillerpfeife #1017, Wecker #2814, Airhorn #1829. Als Shop-Items wählbar UND als Slot-Standards (jeder Spieler-Slot automatisch ein ANDERES Timbre — `standardBuzzer()`). |
| — ✓ | **Kassenlade-Kaching** (war zweite Priorität) | `kasse_kaching_pd_wikimedia.ogg` (Wikimedia „Cash register.ogg", PD) — Money-Kling MITTEL ist jetzt Kassenlade+Münzen-Layer; BigSoundBank hatte nur Beep-/Supermarkt-Ambience. |

Hörbarkeits-Beweis: `node tools/audio/probe.mjs` prüft ALLE Mappings
(Existenz, Dauer > 0, dekodierbar, loudnorm-Familien-Check ± 6 dB) und
rendert `tools/audio/probe.html` (Event + Play-Button, 🆕-Markierung);
`tools/audio/sound-assets.test.ts` ist das schnelle CI-Netz in vitest.

**OFFEN bleibt:**

| # | Lücke | Warum kritisch | Konkrete Quelle (login-frei, wget-bar) |
|---|---|---|---|
| **2** | **Echte Affen-Laute + Publikums-Comedy** (Jubel-Kreischen, „Uh-uh", Keckern für den Klau; Lacher, Raunen/„Ooooh", Crickets) | Die komplette Kommentar-/Comedy-Ebene der Show fehlt; ohne Keckern bleibt die Klau-Animation stumm-steril | Pixabay `monkey chatter`, `chimpanzee scream`, `gorilla`, `crickets`; Wikimedia Kategorie „Sounds of laughing" (29 Dateien, u. a. „Lachkonserve 1.ogg", PD) + Primaten-Kategorien |

Weitere Lücken (zweite Priorität): **Sad Trombone** (Pixabay `sad trombone`) ·
**Herzschlag** fürs Finale (Pixabay `heartbeat`) · **Whoosh-Familie** für
Kamera-Swoosh/Klau (Pixabay `whoosh`, OpenGameArt CC0) · **Finale-Bett**
(incompetech.com, Filter Feel: Suspense — Kandidaten „Volatile Reaction",
„Spy Glass", CC-BY) · **Sieger-Hymne** (Wikimedia Kategorie „Musopen",
PD-Klassik — z. B. festlicher Marsch/„Pomp and Circumstance"-Aufnahme;
alternativ incompetech Feel: Epic/Triumphant) · **Schnarch-Loop** für den
AFK-Gag (Pixabay `snoring`). Negativ-Liste bleibt gültig: Freesound
(Login), Musopen.org direkt (Login+Limit), FreePD (offline), ZapSplat/
Uppbeat (Login), YouTube Audio Library (kein CC); NEU bestätigt:
CC-BY-**SA**-Dateien sind tabu (nicht in der Lizenz-Whitelist).

### 4.4 CREDITS.md-Vorlage (alle bisherigen Quellen korrekt attribuiert)

Ablage: `assets/audio/CREDITS.md`; eine Zeile pro Datei; generiert aus
`tools/audio/sound_manifest.json` (Ziel, URL, sha256, Lizenz, Autor);
CI-Gate prüft: jede Audio-Datei hat eine Zeile, jede Zeile eine Datei,
Lizenz ∈ {CC0, CC-BY 3.0, CC-BY 4.0, Public Domain, OGA-BY 3.0, Pixabay
Content License}, bei CC-BY sind Autor+Link gefüllt.

```markdown
# Audio-Credits — MONKEY MONEY
Alle Sounds stammen aus externen CC-/PD-Quellen (keine Eigen-Synthese).
„Änderungen": geschnitten/normalisiert/gepitcht durch uns (CC-BY verlangt diesen Hinweis).

| Datei | Verwendung | Quelle | Autor | Lizenz | Link | Änderungen |
|---|---|---|---|---|---|---|
| ui/* , sfx/* (aus Interface Sounds) | UI-Klicks, Ticks, Fehler, Frage-Sting | Kenney.nl „Interface Sounds" | Kenney Vleugels | CC0 | https://kenney.nl/assets/interface-sounds | Auswahl, −16 LUFS |
| ui/* (aus UI Audio) | Klick-/Switch-Fallbacks | Kenney.nl „UI Audio" | Kenney Vleugels | CC0 | https://kenney.nl/assets/ui-audio | Auswahl, −16 LUFS |
| sfx/money_* (aus Casino Audio) | Chips/Karten/Würfel = Money-Klang | Kenney.nl „Casino Audio" | Kenney Vleugels | CC0 | https://kenney.nl/assets/casino-audio | Auswahl, Layering, −16 LUFS |
| sfx/impact_* (aus Impact Sounds) | Lock-in-Thunk, Gong, Treffer | Kenney.nl „Impact Sounds" | Kenney Vleugels | CC0 | https://kenney.nl/assets/impact-sounds | Auswahl, −16 LUFS |
| sfx/stinger_*, jingle_* (aus Music Jingles) | Stinger, Runden-/Sieg-Jingles | Kenney.nl „Music Jingles" | Kenney Vleugels | CC0 | https://kenney.nl/assets/music-jingles | Auswahl, −16 LUFS |
| sfx/digital_* (aus Digital Audio) | Richtig/Falsch-Töne, PowerUps | Kenney.nl „Digital Audio" | Kenney Vleugels | CC0 | https://kenney.nl/assets/digital-audio | Auswahl, −16 LUFS |
| sfx/scifi_* (aus Sci-Fi Sounds) | Glitch, Tresor, Slime, Aura | Kenney.nl „Sci-Fi Sounds" | Kenney Vleugels | CC0 | https://kenney.nl/assets/sci-fi-sounds | Auswahl, −16 LUFS |
| music/lobby_loop.mp3 | Lobby/Pause | incompetech.com | Kevin MacLeod | CC-BY 3.0/4.0 | https://incompetech.com | Loop-Punkt gesetzt, −24 LUFS. Credit: „Monkeys Spinning Monkeys" Kevin MacLeod (incompetech.com), Licensed under Creative Commons: By Attribution |
| music/round_loop.mp3 | Runden-Bett | incompetech.com | Kevin MacLeod | CC-BY | s. o. | Credit: „Quirky Dog" … (Formel identisch) |
| music/sneaky_loop.mp3 | Klau-/Wettrunden | incompetech.com | Kevin MacLeod | CC-BY | s. o. | Credit: „Sneaky Snitch" … |
| music/wheel_loop.mp3 | Glücksrad | incompetech.com | Kevin MacLeod | CC-BY | s. o. | Credit: „Merry Go" … |
| music/news_loop.mp3 | Zwischenstand/Werbung/Shop | incompetech.com | Kevin MacLeod | CC-BY | s. o. | Credit: „Local Forecast - Elevator" … |
| music/tutorial_loop.mp3 | Tutorial/Warten | incompetech.com | Kevin MacLeod | CC-BY | s. o. | Credit: „Fluffing a Duck" … |
| crowd/applause_polite.ogg | Applaus Stufe 1 | Wikimedia Commons | thore (PDSounds) | Public Domain | https://commons.wikimedia.org/ (Dateiseite verlinken) | gekürzt, −16 LUFS |
| crowd/applause_medium.ogg | Applaus Stufe 2 | Wikimedia Commons | thore (PDSounds) | Public Domain | s. o. | gekürzt, −16 LUFS |
| crowd/applause_big.ogg | Applaus Stufe 3 | Wikimedia Commons | R. Humphries | **CC-BY** (Autor nennen!) | Dateiseite verlinken | gekürzt, −16 LUFS |
| crowd/applause_cheer.ogg | Jubel-Sturm | Wikimedia Commons | starlite (PDSounds) | Public Domain | s. o. | gekürzt, −16 LUFS |
| crowd/applause_buildup.ogg | Anlaufender Applaus | Wikimedia Commons | stephan (PDSounds) | Public Domain | s. o. | gekürzt, −16 LUFS |
```

Zusätzlich in die In-App-Credits (Show-Abspann + Einstellungen): Kenney
(freiwillig, aber wir tun es), Kevin MacLeod (PFLICHT), R. Humphries
(PFLICHT), Fonts: „Bungee & Bungee Shade (David Jonathan Ross), Rubik
(Hubert & Fischer et al.) — SIL Open Font License 1.1".

---

## 5. CUTSCENE-/VIDEO-PLAN

Drei-Schichten-Regel (festgeschrieben): **Steht ein Spielername drauf →
Echtzeit (Browser); ist es Marketing/Erklärung → Remotion (Build-Zeit,
nie Laufzeit); braucht es echtes 3D-Licht → Blender-Clip als Zutat für
beide.** Skip-Modelle: GM-Skip / Mehrheits-Skip (>50 %) /
Jeder-sofort-Skip; IMMER 1,5-s-Kein-Skip-Fenster (Stinger + Branding).

### 5.1 Echtzeit-Browser-Cutscenes v1 (drei Stück, als Canvas/DOM-Choreos)

**A · Show-Opening** (Gesamt 10–12 s; v1 komplett in Echtzeit, ab
Verfügbarkeit des Blender-Stingers werden Beat 1–2 durch das WebM ersetzt
— Hybrid-Muster mit gemeinsamer Clock):

| Beat | Dauer | Inhalt | Sound |
|---|---|---|---|
| 1 | 0–1,5 s | Schwarz → goldener Lichtpunkt | `chips-collide-1.ogg` (Münz-Klimpern) |
| 2 | 1,5–4 s | Logo-Wortmarke stempelt sich ein (SVG-Scale-Overshoot), Münzen prallen ab (Canvas-Partikel) | Logo-Sting: `jingles_HIT02.ogg` (Kandidat) |
| 3 | 4–8 s | „Kamerafahrt": Bühnen-Wrapper zoomt von Blattwerk-Totale auf die Podien, Parallaxe verkauft Tiefe | Anlaufender Applaus (`applause_anlaufend_pd_stephan.ogg`) |
| 4 | 8–10 s | Spotkegel schwenken auf die leeren Pulte, 1× Konfetti-Kanone | Konfetti-Pop: `impactSoft_heavy_001.ogg` |
| 5 | 10–12 s | Titel-Karte „HEUTE SPIELEN:" → Übergabe an Kandidaten-Vorstellung (pro Spieler 2,5 s: Spotlight + Einlauf-Variante + Namens-Banner; NIEMALS vorrendern — Laufzeit-Daten) | Drumroll (nach Beschaffung, Lücke 1) |

Skip: Kein-Skip-Fenster 1,5 s, danach **GM-Skip** (das Opening ist Ritual;
Einzelne sollen es nicht für alle killen). Jeder Spieler darf seine EIGENE
Vorstellung per Buzzer abkürzen (Gag: Vorhang fällt ihm auf den Kopf).

**B · Runden-Ankündigungs-Karte** (10–15 s; EIN Template, pro Minispiel nur
Daten: Name, Icon, Akzentfarbe, 3 Regel-Zeilen, Maskottchen-Pose):

| Beat | Dauer | Inhalt | Sound |
|---|---|---|---|
| 1 | 0–1,5 s | Bananen-Wipe rein; Format-Logo + Name stempeln sich ein | Format-Jingle (`jingles_HIT*`-Familie) |
| 2 | 1,5–9 s | Max. 3 Regel-Zeilen fliegen nacheinander ein + Mini-Demo-Loop (Handy-Mockup zeigt die Geste) | Karten-Slide: `card-slide-3.ogg` pro Zeile |
| 3 | 9–12 s | Einsatz-Anzeige („Pro Treffer: 200 MM · Letzter zahlt doppelt!") | Money-Kling KLEIN |
| 4 | variabel | „BEREIT?"-Prompt, Countdown 3-2-1 sobald alle (Timeout 10 s) | `tick_001.ogg` ×3 + Zeit-um-Gong |

Skip: erstes Auftreten des Formats **Mehrheits-Skip**; ab dem 2. Mal
**Jeder-sofort-Skip** + automatische Kurzfassung (nur Beat 1+4, ~4 s).

**C · Siegerehrung** (14–18 s + stehendes End-Bild):

| Beat | Dauer | Inhalt | Sound |
|---|---|---|---|
| 1 | 0–3 s | Drei Podeste fahren hoch; Platz 3 hüpft aufs Podest | Drumroll (Lücke 1); Interim `tick_002`-Beschleunigung |
| 2 | 3–6 s | Platz 2, mit „so knapp!"-Einblendung bei Abstand < 10 % | Applaus mittel |
| 3 | 6–10 s | Spannungspause: 2 Spotlights kreisen, Stille → Sieger knallt per Konfetti-Kanone aufs oberste Podest | 1,5 s STILLE → `jingles_SAX10.ogg` |
| 4 | 10–14 s | **Money-Regen zählbar**: exakt Gewinnsumme/50 Scheine fallen, Kontostand tickt pro Schein-Aufprall; Krone landet physikbasiert schief; Sieg-Pose des Charakters (Tabelle 2.1) | `card-place-*` pro Schein + `applause_jubel_pd_starlite.ogg` |
| 5 | ab 14 s | End-Tafel „Sieger-Poster" (alle Endstände, Blitzlichter) bleibt stehen; „Nochmal spielen?"-Prompt | Foto-Blitz: `click_005.ogg` |

Skip: **Mehrheits-Skip erst nach Beat 3** (der Sieger hat sich den Moment
verdient); der Sieger exklusiv bekommt einen „Zugabe!"-Button
(Money-Regen 1× wiederholen).

Übergangs-Vokabular (Echtzeit, 0,5–1,2 s, NIE skippbar, GM kann auf
„reduziert" schalten): **Bananen-Wipe** = Standard zwischen Fragen ·
**Money-Regen-Wipe** = Auszahlungs-Momente · **Studio-Licht-Blende**
(klack-klack-klack aus → Spots finden neue Szene) = Akt-Wechsel
Halbzeit/Finale.

### 5.2 Remotion v1 (Build-Zeit, `videos/`-Workspace, CI-Render)

Geteiltes Paket `show-ui` (Logo-, Karten-, Typo-Komponenten) wird von
Spiel-Frontend UND Remotion importiert — Corporate Design an einer Stelle.

**Trailer, 75 s, 16:9 + 9:16-Zweitfassung — finales 9-Shot-Storyboard:**

| # | Zeit | Shot | Inhalt |
|---|---|---|---|
| 1 | 0–4 s | Logo-Stinger | Blender-Logo-Render (5.3), Münz-Knall — Marke zuerst |
| 2 | 4–10 s | Problem-Hook | Illustrierte gelangweilte Sofa-Runde, Zapping; Text-Card „Spieleabend eingeschlafen?" |
| 3 | 10–18 s | Die Verwandlung | TV schaltet aufs MONKEY-MONEY-Studio, Show-Licht flutet das Wohnzimmer, Kamera-Swoosh ins Spiel |
| 4 | 18–26 s | So funktioniert’s | Split: TV oben, 3 Handys unten; Join per Raum-Code in 3 s (Screen-Capture im Mockup-Rahmen). Text: „Handy = Buzzer. Kein Download." |
| 5 | 26–38 s | Minispiel-Montage | 4 Gameplay-Ausschnitte à 3 s (Buzzer-Duell, Schätz-Liane, Glücksrad, Stinkbanane), je mit Format-Logo-Stempel |
| 6 | 38–46 s | Emotion-Peak | Money-Regen, Klau-Affenhand, Comeback-Rakete — die Show lacht MIT den Verlierern |
| 7 | 46–56 s | Das Finale | Tresor, Herzschlag, glühende Jackpot-Ziffern; Sieger, Podest + Konfetti + Goldene Banane |
| 8 | 56–66 s | Feature-Karten + Social Proof | 3 Karten „2–8 Spieler · Party, Familie, Büro · Jede Woche neue Fragen" + 1 Zitat-Karte („Der Affe hat meine Punkte GEKLAUT?!" — Lena, Platz 4) |
| 9 | 66–75 s | Call-to-Action | Logo-Bumper (1-s-Kurzfassung) + URL/QR + Claim: „MONKEY MONEY — Wer nicht spielt, zahlt." |

Bauregel: Shots 5–7 recyceln echtes Gameplay-Material → Trailer wird ERST
gebaut, wenn 3–4 Minispiele vorzeigbar sind (Schritt 8 der Reihenfolge).
Texte/Claims als Props (DE/EN = zweiter Render-Lauf).

**Tutorial-Template „HowToCard"** (EIN Template für ALLE
Minispiel-Tutorials, 15–20 s): Props = `title, icon, accentColor, steps[]
(max. 3 × {Text, Demo-Clip}), rewardLine, mascotPose`. Fester Ablauf:
Format-Logo-Stempel + Jingle (2 s) → 3 Schritte à 4 s (links Handy-Mockup
mit Demo-Clip, rechts Text, Maskottchen zeigt drauf) → Belohnungs-Zeile +
Logo-Bumper (3 s). Genutzt im Spiel („Regeln nochmal?"), als
Social-Snippet und im Lobby-Attract-Mode. Neues Minispiel = Props-Datei +
CI-Render.

### 5.3 Blender: die 3 Assets (identisch mit 2.3)

1. **Logo-3D-Stinger** — 3–4 s, Münz-Physik, Gold-Shader; Fassungen:
   Alpha-WebM / Studio-Hintergrund / 1-s-Bumper.
2. **Trophäe „Die Goldene Banane"** — Turntable-Sprite-Sheet (36 Frames) +
   Still für Icon/Store.
3. **Riesen-Affenhand** — 2–3 Griff-Posen mit Alpha für Klau-Animation und
   (später) Affen-Hand-Grab-Übergang.

Render-Skript (`blender --background --python …`) im Repo, Safari-Fallback
für WebM-Alpha: PNG-Sequenz/HEVC-Alpha prüfen.

---

## 6. PRODUKTIONS-REIHENFOLGE (mit Abnahme-Kriterien)

| # | Schritt | Liefert | Abnahme-Kriterium (messbar) |
|---|---|---|---|
| 1 | **Palette + Fonts + Stil-Stempel** | CSS-Custom-Properties (13 Farben), Bungee/Bungee Shade + Rubik als WOFF2 + OFL-Texte, `docs/art/stilbibel.md` + `prompt_stempel.md` | Eine Test-HTML-Seite zeigt Palette, beide Fonts, Sticker-Button mit Squash&Stretch; Fonts laden lokal ohne CDN; Prompt-Vorlage erzeugt 1 Testbild, das den Palette-Clamp übersteht |
| 2 | **Logo + Banana Buck** | Referenzbild „Präsident Bananas" (Stil-Anker!), Logo-SVG (2-farbig + einfarbig), Schein-SVG mit Portrait + Farbbalken-Slot | Logo bei 32 px (App-Icon) UND 1080p (Bühne) lesbar; Schein-Stapel-Render mit 8 Spielerfarb-Balken; Referenzbild von 2 weiteren Generierungen stilgleich reproduziert |
| 3 | **Handy-Screens (6 Kern-Screens)** | DOM/CSS-Umsetzung nach 3.3 inkl. Münz-Einwurf-Lock-in, Stempel-Feedback, Fidget-Warte-Screen | Auf echtem Alt-iPhone (Safari): alle 6 Screens < 200 KB gzip gesamt, Tap-Ziele ≥ 96 px, kein Layout-Shift, `safe-area` korrekt; Münz-Einwurf fühlbar in < 400 ms lokal |
| 4 | **Bühne (Screen-App)** | 5-Ebenen-Studio, Podien mit wachsendem Scheinstapel, LED-Wand, die 5 Szenen-Zustände als Klassenwechsel, Canvas-Partikel-Overlay | 8-Spieler-Lobby auf iPad-Safari ≥ 45 fps mit Money-Regen (120 Sprites); Szenen-Wechsel rein datengetrieben über Mock-Events; Auto-Degradation greift nachweislich |
| 5 | **Charaktere (8 Cutouts)** | Grundskelett + 8 Silhouetten-Sets, 6 Basis-Clips geerbt, 3 Signature-Clips pro Affe, Palette-Swap, Handy-Mini-Avatar | Silhouetten-Test: alle 8 als schwarze Flächen in 0,5 s benennbar (5 Testpersonen); Reaktions-Schwenk mit 150-ms-Staffelung läuft; Farb-Swap ohne Asset-Duplikate |
| 6 | **Sounds einbauen** | Bus-Architektur + Ducking, Mapping aus 4.1, Musik aus 4.2, Lücken-Beschaffung (4.3), `sound_manifest.json` + CREDITS-Generierung + CI-Gate | Kompletter Proberunden-Durchlauf klingt „gemischt" (kein Sound übersteuert, Stille-Momente sind still); CI-Gate rot bei fehlender Credit-Zeile; alle Dateien −16/−24 LUFS normalisiert |
| 7 | **Cutscenes (Echtzeit)** | Opening, Runden-Karte, Siegerehrung nach 5.1 + die 3 Übergänge; danach Blender-Assets (Stinger, Trophäe, Hand) einhängen | Jede Cutscene skippbar nach Regelwerk (inkl. 1,5-s-Fenster); Siegerehrung zeigt zählbaren Money-Regen synchron zum Kontostand; Hybrid-Skip bricht Video+Overlay gemeinsam ab |
| 8 | **Trailer + Tutorials (Remotion)** | `videos/`-Workspace, HowToCard-Template + 3–4 Tutorial-Renders, 75-s-Trailer 16:9 + 9:16 | `npx remotion render` läuft in CI und legt Artefakte ab; Trailer nutzt echtes Gameplay-Material in Shots 5–7; DE/EN-Render nur über Props |

Regel dahinter: Erst das Fundament, das ALLES bindet (Stil), dann die
Assets mit dem höchsten Wiederverwendungs-Faktor (Logo/Schein), dann die
Flächen, die Spieler ständig sehen (Handy vor Bühne — mehr Blickzeit pro
Person), dann Bewohner (Charaktere), dann Ohren (Sound macht aus Screens
eine Show), dann Klammern (Cutscenes), zuletzt Marketing (Trailer braucht
fertiges Material).
