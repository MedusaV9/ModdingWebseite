# Ideen-Agent 9/20 — Art-Direction & Bühnen-/Screen-Design für MONKEY MONEY

> Thema: Wie MONKEY MONEY AUSSIEHT und sich ANFÜHLT — Art-Style, Bühne auf dem
> Bildschirm (iPad/PC), Handy-Screens (hochkant), Technik-Empfehlung fürs
> Rendering und die Pipeline für generierte Bilder. 25 Ideen.
> Aufwand: S/M/L (Implementierungs-/Produktionsumfang), Prio: MUST / SHOULD / COULD.
> Konsistenz mit den Nachbar-Agents: Währung „MM", 1 Schein = 50 MM (Agent 14),
> Handy-Client < 200 KB gzipped, Rollen Spieler/Bildschirm/Show-Master (Agent 17).

---

## Vorab-Analyse: Was macht den Jackbox-Look aus?

Bevor wir den MONKEY-MONEY-Stil definieren, die Zutatenliste des Vorbilds:

1. **Flache, kräftige Formen mit dicken Outlines.** Fast alles ist 2D-Vektor
   mit fetten, leicht unregelmäßigen Konturen. Kein Realismus, keine feinen
   Verläufe — Lesbarkeit auf 3 m Wohnzimmer-Distanz ist König.
2. **Exzentrische, laute Typografie.** Jede Show hat eine eigene
   Display-Schrift mit Charakter (schräg gestellt, gestaucht, mit Schatten),
   dazu eine ruhige UI-Schrift für Fließtext. Text wird ANIMIERT (Wackeln,
   Einstempeln, Buchstaben-für-Buchstabe).
3. **Studio-Glow und Bühnen-Dramaturgie.** Dunkler Studio-Hintergrund,
   Spotkegel, Vignette, Lens-Flare-Andeutungen — das Licht sagt „Fernsehshow",
   obwohl alles flach gerendert ist.
4. **Wenige Dinge auf einmal, aber die GROSS.** Eine Frage füllt den halben
   Bildschirm. Punktestände sind Events mit eigener Kamera, nicht Dauer-HUD.
5. **Charakter durch Unperfektion.** Leicht schiefe Formen, handgemachtes
   Wobbeln (2-Frame-„boiling lines"), absurde Details. Das nimmt der
   Geometrie die Sterilität.
6. **Harte TV-Schnitte statt Kamerafahrten.** Jackbox „schneidet" zwischen
   Vollbild-Layouts (Frage → Antworten-Grid → Wertung) wie eine
   Fernsehregie — kaum weiche Fahrten, dafür knallige Übergangs-Bumper.

**Der MONKEY-MONEY-Stilkern in einem Satz:** *„Eine 70er-Jahre-Gameshow, die
mitten im Dschungel aufgebaut wurde und deren Preisgeld von Affen bewacht
wird"* — Casino-Gold + Studio-Glow trifft Blattgrün + Bananengelb, alles in
flachem Vektor-Look mit dicken warm-schwarzen Outlines.

---

## (a) ART-STYLE-DEFINITION

### A-01 · Stil-Bibel „Jungle-Casino-TV" (1 Seite, verbindlich) — **MUST · S**
Eine einzige Markdown/PNG-Seite, die ALLE späteren Assets bindet: die 6
Jackbox-Zutaten oben, übersetzt auf MONKEY MONEY. Kernregeln:
- Outline-Stärke: 4–6 px bei 1080p-Referenz, Farbe IMMER Warm-Schwarz
  `#1A1208` (nie reines Schwarz — wirkt sonst wie Clipart).
- Max. 2 Verläufe pro Screen, beide nur radial (Spotlight, Gold-Schimmer).
  Alles andere: Flächen.
- Formen 2–3° aus der Achse gedreht („wonky"), Ecken gerundet, nichts
  perfekt parallel.
- Licht kommt IMMER von oben-mitte (Studio-Rig) — gilt auch für generierte
  Bilder (in den Prompt schreiben, A-24).
Diese Seite entsteht ZUERST und hängt als `docs/art/stilbibel.md` im Repo.

### A-02 · Farbpalette „Banana Vault" (12 Festfarben, Hex) — **MUST · S**
Feste 12er-Palette als CSS-Custom-Properties und als Post-Processing-Ziel für
generierte Bilder (A-25). Vorschlag:

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

Dazu die Outline-Farbe `#1A1208` (Warm-Schwarz) als 13. Konstante.
Spielerfarben (bis 8 Spieler) werden AUS der Palette abgeleitet plus 4
Zusatztöne (Orange `#F97316`, Violett `#8B5CF6`, Blau `#3B82F6`,
Pink `#F472B6`) — alle gegen `#0E2A1F` UND `#FFF6E3` kontrastgeprüft
(WCAG ≥ 3:1 für große Flächen).

### A-03 · Typografie-Trio (frei lizenziert, lokal bundelbar) — **MUST · S**
Drei Rollen, alle OFL/Apache-lizenziert → dürfen als WOFF2 ins Repo (wichtig:
AMP-Server ist HTTP-only, kein Google-Fonts-CDN einplanen):
1. **Display/Logo: „Luckiest Guy"** (Apache 2.0) — fett, rund, leicht
   trashig, perfekt für „MONKEY MONEY!!" und Runden-Titel. Alternative mit
   mehr Casino-Charakter: **„Bungee Shade"** (OFL, eingebaute
   3D-Schatten-Ebene — sieht aus wie eine Leuchtreklame).
2. **UI/Fließtext: „Nunito"** (OFL) — runde Terminals passen zur
   Formensprache, sehr gute Lesbarkeit auf Handys, variable Font = 1 Datei.
3. **Zahlen/Money: „Rubik"** (OFL) mit `font-variant-numeric: tabular-nums`
   — Kontostände zappeln beim Hochzählen nicht in der Breite. Für den
   „Kontoauszug-Look" (Agent 14, Zins-Einblendungen) optional
   **„Chivo Mono"** (OFL) als Vierte im Bunde.
Regel: Display-Font NIE unter 32 px und NIE für mehr als 6 Wörter am Stück.

### A-04 · Formensprache „Sticker aufs Studio geklebt" — **MUST · S**
Alle UI-Elemente (Buttons, Namensschilder, Frage-Karten) sind „Sticker":
Fläche + dicke Outline + 2 px versetzter, harter Schlagschatten in
`#1A1208` bei 40 % — KEIN weicher Blur-Schatten (weiche Schatten brechen den
Flat-Look und kosten auf Low-End-Handys Repaint-Leistung). Interaktion =
Squash & Stretch per CSS-`transform: scale()` (Compositor-only, billig):
Idle 100 %, Pressed 92 % + 2° Rotation, Erfolg 108 % Bounce. Diese eine
Regel macht DOM-UI sofort „gamig", ohne ein einziges Bild-Asset.

### A-05 · Logo: Wortmarke mit Bananen-Dollar und Affenschwanz — **SHOULD · M**
„MONKEY MONEY" zweizeilig in Luckiest Guy, beide Wörter 3° gegeneinander
verkippt. Die beiden **O in „MONEY" sind Goldmünzen** (mit Affenkopf-Prägung,
siehe A-06), das **Y läuft in einen geringelten Affenschwanz** aus, der die
ganze Wortmarke unterstreicht. Über dem Schriftzug ein kleines Emblem:
**Banane, um die sich ein $-Balkenpaar wickelt** („Bananen-Dollar" — das
Sekundär-Logo/App-Icon für kleine Flächen). Farbfassung: Banana-Gelb auf
Jungle Night mit Vault-Gold-Kontur; einfarbige Variante (nur `#1A1208`)
für Stempel/Wasserzeichen von Anfang an mitdenken. Produktion: 2–3
generierte Entwürfe als Moodboard (A-23), finale Marke als SVG nachbauen
(skaliert verlustfrei, färbbar per CSS).

### A-06 · Money-Bill-Design: der „Banana Buck" (1 Schein = 50 MM) — **MUST · M**
DAS Signature-Asset, überall wiederverwendet (Stapel, Regen, Klau, Handy):
- Querformat 2:1, Bill Green `#85BB65` mit Ticket-Paper-Rand und
  Guilloche-Andeutung (3–4 geschwungene Linien reichen im Flat-Look).
- Mitte: **Oval-Portrait eines würdevoll blickenden Affen mit Monokel und
  Krawatte** („Präsident Bananas") — dicke Outline, Dreiviertel-Ansicht.
- Ecken: „50" in Rubik, Banner unten: „BANANA BUCK — IN MONKEY WE TRUST".
- **Seriennummer = Spielername + Spielerfarbe als kleiner Farbbalken** —
  dadurch sieht man bei Klau-Animationen (A-13), WESSEN Scheine da fliegen.
- Rückseite (nur für Flip-Animationen): das Bananen-Dollar-Emblem groß.
Produktion: 1 generiertes Referenzbild fürs Portrait, Rest als SVG-Layout →
Portrait als eingebettetes Bitmap (256 px reicht, wird nie größer als
¼ Bildschirm gezeigt). Varianten später: 500er-Bündel mit Gold-Banderole,
„Falschgeld"-Schein (grauer Affe, Prio COULD) für Trickfragen.

### A-07 · Affen-Avatar-Baukasten (Kopf-Silhouetten + Accessoires) — **SHOULD · M**
8 Basis-Affenköpfe als flache Vektor-Silhouetten (unterschiedliche
Ohren-/Haar-Silhouetten, damit sie auch klein unterscheidbar sind), Fell in
Spielerfarbe eingefärbt (1 Asset × 8 Farben statt 64 Assets). Dazu eine
Accessoire-Ebene (Zylinder, Sonnenbrille, Stirnband, Goldkette, Banane
hinterm Ohr …) als separate PNGs mit fixen Ankerpunkten. 3 Gesichtszustände
pro Kopf: neutral / Jubel (Augen zu, Mund auf) / entsetzt (für Klau-Opfer,
A-13). Mehr Mimik ist Luxus — 3 Zustände × Squash-&-Stretch (A-04) tragen
einen ganzen Abend.

### A-08 · Emote-/Sticker-Set fürs Publikum und die Handys — **COULD · S**
12 runde Sticker im Stil von A-04 (Banane hoch = „stark!", Affe mit
Popcorn, Geldsack, „GEKLAUT!"-Stempel, Zzz …), die Spieler vom Handy auf den
Bildschirm werfen können (Publikums-/Wartemoment-Feature, vgl. Agent 6).
Ein Sprite-Sheet, 12 × 128 px — bewusst klein halten.

---

## (b) BÜHNEN-DESIGN für den BILDSCHIRM (iPad/PC-Browser)

### A-09 · Studio-Set als 5-Ebenen-2.5D-Bühne — **MUST · M**
Die Bühne ist ein DOM-Baum aus 5 Ebenen (hinten → vorn), jede eine eigene
Compositor-Layer (`will-change: transform`):
1. **Backdrop:** Jungle-Night-Verlauf + Blattwerk-Silhouetten (1 generiertes
   Bild, 1920 px, WebP ~80 KB).
2. **LED-Wand** (A-11) mittig, leicht trapezförmig verzerrt
   (CSS `transform: perspective(...) rotateX(...)`) → „steht im Raum".
3. **Podien-Reihe** mit Avataren + Geldstapeln (A-10), 2–8 Podien, per
   Flexbox — Layout skaliert automatisch mit Spielerzahl.
4. **Bühnenboden:** Holzsteg-Textur mit Gold-Kante, Spotkegel (A-12) liegen
   als radiale Verläufe darauf.
5. **Vordergrund-Blätter** links/unten rechts, die bei „Kamera"-Bewegung
   (A-14) 1,3× schneller mitwandern → Parallaxe verkauft die Tiefe.
Alles reagiert auf EINE Variable `--stage-zoom`/`--stage-x` → die ganze
Tiefenwirkung ist ein einziger transformierter Wrapper. Kein WebGL nötig.

### A-10 · Podien mit Avatar, Namensschild und WACHSENDEM Geldstapel — **MUST · M**
Jedes Podium: Trapez-Pult in Spielerfarbe, vorn das Namensschild
(Sticker-Stil A-04), obendrauf der Avatar (A-07), daneben der Kontostand —
und zwar DOPPELT: als Zahl (Rubik, tabular) UND als **physischer
Scheinstapel**: 1 Schein-Sprite = 50 MM, ab 10 Scheinen wird gebündelt
(Banderole = 500 MM), ab 4 Bündeln ein Geldsack dahinter (2.000 MM). Bei
8.000–12.000 MM Zielendstand (Agent 14) endet der Sieger also mit Sack +
mehreren Bündeln — man SIEHT den Spielstand über die Distanz, ohne die Zahl
zu lesen. Zuwachs: Scheine fliegen einzeln im Bogen aufs Podium (max. 20
Stück pro Buchung, Rest „zählt" nur die Zahl hoch — Partikel-Deckel aus
A-22). Verlust: Stapel kippt/schrumpft mit kurzem rotem Blitz.

### A-11 · LED-Wand als Fragen-Display mit Fake-Screen-Shader — **SHOULD · S**
Fragen, Kategorien-Logos und Zwischenstände erscheinen auf der LED-Wand
(A-09, Ebene 2). Der „LED-Look" ist reines CSS: Studio-LED-Cyan-Glow
(`box-shadow` außen, statisch), eine halbtransparente Scanline-Kachel (8 px
`repeating-linear-gradient`) als Overlay, plus 2 % Flacker-Animation auf der
Helligkeit. Bonus-Gag: Beim Frage-Wechsel „zappt" die Wand 200 ms
Störbild-Rauschen (generiertes Noise-Tile). Ergebnis: fühlt sich wie
Studiotechnik an, kostet einen DOM-Knoten.

### A-12 · Licht-Dramaturgie: Spotkegel, Vignette, Blackout — **SHOULD · S**
Drei Lichtwerkzeuge, alle als DOM-Overlays mit `mix-blend-mode`/Opacity:
1. **Spotkegel** (radialer Verlauf, Spotlight Pink oder Coin Shine) über dem
   aktiven Podium — wandert bei Antwortvergabe per Transform.
2. **Vignette** (statisches PNG, 20 KB) macht den Studio-Glow: Ränder dunkel,
   Mitte warm.
3. **Blackout-Beat:** Vor großen Reveals (Finale, Jackpot) 400 ms alles auf
   5 % Helligkeit, nur ein Spot an — der billigste Drama-Trick der
   TV-Geschichte, im DOM eine einzige Klasse.

### A-13 · Money-Regen & Klau-Animation „Die Affenhand" — **MUST · M**
Die zwei Signature-Animationen des Spiels, beide auf EINEM
Vollbild-`<canvas>`-Overlay (Rendering-Architektur A-22):
- **Money-Regen** (Jackpot, Sieger-Zeremonie): 60–120 Banana-Buck-Sprites
  (A-06) taumeln mit Rotation + Sinus-Drift herab, Objekt-Pooling, danach
  „liegen" 20 davon 5 s als statisches Bild am Bühnenrand.
- **Klau-Animation:** Eine RIESIGE pelzige Affenhand (2 generierte Sprites:
  offen/gegriffen) schießt vom Bildschirmrand zum Opfer-Podium, grabscht
  sichtbar Scheine MIT der Seriennummern-Farbe des Opfers (A-06!), zieht
  sich zurück — die Scheine fliegen einzeln zum Dieb-Podium rüber. Opfer-
  Avatar wechselt auf „entsetzt" (A-07), Opfer-Handy blitzt rot (A-19).
  Dauer max. 2,5 s — Drama ja, Wartezeit nein.

### A-14 · TV-Regie: harte Schnitte, 4 Kamera-Presets, Bumper-Wipes — **MUST · M**
Statt Kamerafahrten schneidet MONKEY MONEY wie eine Fernsehregie zwischen
4 Presets (alle nur Transform + Klassenwechsel auf dem Bühnen-Wrapper A-09):
1. **TOTALE** — ganze Bühne (Standard, Rundenstart, Zwischenstand).
2. **FRAGE** — LED-Wand füllt 80 % (Podien ragen unten klein rein).
3. **CLOSE-UP** — Zoom auf EIN Podium (Antwort-Reveal, Buzzer-Gewinner:
   dazu 150 ms Wackel-Zoom, „Crash-Zoom" wie im Trash-TV).
4. **DUELL-SPLITSCREEN** — zwei Podien nebeneinander, Trennblitz in der
   Mitte, Rest abgedunkelt (für 1-gegen-1-Momente, vgl. Agent 2).
Zwischen Presets: harter Schnitt (kein Tween!) mit 2-Frame-Weißblitz — und
für Runden-/Phasenwechsel zwei **Bumper-Wipes**: (1) Das Bananen-Dollar-
Emblem (A-05) fliegt rein, füllt drehend den Bildschirm, dahinter ist schon
die neue Szene (`clip-path`-Masken-Animation); (2) roter Studio-Vorhang
(Curtain `#C2183B`, 2 generierte Vorhang-Hälften) schließt und öffnet sich
für Finale/Preisverleihung. Beide < 800 ms, beide mit Sound-Cue (Agent 10).
Die Regie-Logik ist datengetrieben: der Server-Event-Typ mappt auf ein
Preset (Agent 17: Clients sind dumme Renderer).

### A-15 · Jackpot-Tresor auf der Bühne — **SHOULD · S**
Der Jackpot-Topf (Agent 14: gefüttert aus Fehlbuzz-Strafen) steht als
**goldener Mini-Tresor mit Glasfront und Bananenschloss** seitlich auf der
Bühne; drin stapeln sich sichtbar die eingezahlten Scheine (gleiche
Stapel-Logik wie A-10). Bei jeder Einzahlung wackelt er und die Zahl darauf
tickt hoch; beim Jackpot-Gewinn sprengt er die Tür ab → Money-Regen (A-13).
Ein Asset, dauerhafter Spannungs-Anker im Bühnenbild.

### A-16 · Virtueller Co-Host „Don Bananas" (Figur der Show) — **COULD · L**
Da der Show-Master ein Mensch ist (Agent 17), braucht die Show keinen
sprechenden Host — aber eine stumme FIGUR gibt der Bühne Charakter: Don
Bananas (der Affe vom Geldschein A-06, jetzt in ganzer Gestalt mit Anzug)
steht neben der LED-Wand, hat 4–5 Pose-Sprites (präsentieren, lachen,
erschrocken, Geld zählen, schlafen bei langen Wartezeiten) und reagiert
per Pose-Wechsel auf Events. Kein Rigging, keine Lippen-Synchro — Posen
reichen im Flat-Look völlig. Später ausbaubar zum Announcer mit Sound.

---

## (c) HANDY-SCREEN-DESIGN (hochkant, Safari, Low-End-tauglich)

### A-17 · Daumen-Zonen-Layout: alles Wichtige ins untere Drittel — **MUST · S**
Festes Layout-Raster für ALLE Handy-Screens: oberes Drittel = Status
(eigener Avatar + Kontostand als Mini-Scheinstapel + Rundeninfo), Mitte =
Kontext (Frage-Echo, Timer), **unteres Drittel = Aktionen**, denn dort ist
der Daumen. Antwort-Buttons XXL: bei 4 Antworten ein 2×2-Grid, jede Kachel
min. 44 % Bildschirmbreite × 96 px hoch, Sticker-Stil (A-04), Buzzer als
EIN kreisrunder Riesen-Button (70 % Breite). `viewport-fit=cover` +
`safe-area-inset`-Padding gegen die Home-Bar; `touch-action: manipulation`
gegen den 300-ms-Tap-Delay und Doppeltipp-Zoom.

### A-18 · Persönliche Identität: „mein Handy = mein Podium" — **MUST · S**
Das Handy ist durchgehend in der Spielerfarbe gerahmt (4 px Rand +
eingefärbte Statusleiste via `theme-color`), oben immer der eigene Avatar.
Money-Buchungen laufen SYNCHRON zur Bühne: kriegt mein Podium Scheine,
fliegen auf meinem Handy dieselben Scheine in meinen Mini-Stapel (2–3
DOM-Sprites reichen). Effekt: „Das da vorne bin ICH" — die stärkste
Bindung zwischen Bildschirm und Controller, praktisch gratis, weil beide
dieselben Server-Events rendern (Agent 17).

### A-19 · Antwort-Feedback: Einloggen wie ein Geldschein-Stempel — **MUST · S**
Nach dem Antippen: Button rastet mit Squash (A-04) ein, ein Stempel
„EINGELOGGT ✓" knallt schräg über den Screen (Display-Font, 150 ms
Scale-Overshoot), alle anderen Buttons desaturieren. Richtig/falsch-Reveal:
Grün-Flash + Scheinchen-Konfetti bzw. Curtain-Rot + kurzes
`transform`-Schütteln des ganzen Screens. WICHTIG: iOS-Safari hat KEIN
`navigator.vibrate` — Haptik-Ersatz ist genau dieses Screen-Schütteln +
Sound vom Bildschirm (nicht vom Handy — Latenz/Autoplay-Fallen, Agent 10).
Bei Klau (A-13): Opfer-Handy blitzt 2× rot und der Mini-Stapel schrumpft.

### A-20 · Warte-Momente charmant: der Fidget-Affe — **SHOULD · M**
Warten ist bei Party-Games 40 % der Handy-Zeit — also bekommt der
Warte-Screen einen Job: Der eigene Avatar sitzt da und reagiert auf Tippen
(Banane werfen, Grimasse), ein dezenter Fortschritts-Text sagt ehrlich, was
passiert („3 von 6 haben geantwortet…"), und gelegentlich läuft ein
„Kontoauszug"-Ticker mit absurden Buchungen („−0 MM: Bananenschale,
Parkgebühr"). Optional (Anbindung A-08): 1 Emote-Wurf pro Wartephase frei.
Regel: NIE ein leerer Spinner — der Warte-Screen ist Teil der Show.

### A-21 · Geld anfassen: Einsatz-Slider als Scheine-Fächer — **SHOULD · M**
Überall, wo Spieler MM einsetzen (Wetten, Tipps kaufen — Agent 14), wird
Geld nicht über ein Zahlenfeld eingegeben, sondern **gefächert**: Ein
Daumen-Slider fächert Banana Bucks auf (jeder Rastpunkt = 1 Schein = 50 MM,
Bündel-Rastpunkte bei 500), der gewählte Betrag steht groß in Rubik
darüber. Bestätigen = **Swipe nach oben**, die Scheine fliegen „aus dem
Handy raus" — und landen 300 ms später sichtbar auf der Bühne (A-10).
Das ist DIE Geste, die aus „Betrag eingeben" ein Casino-Gefühl macht.

---

## (d) TECHNIK-EMPFEHLUNG: Womit wird gerendert?

### A-22 · Entscheidung: 2.5D-DOM/CSS-Bühne + EIN Canvas-Partikel-Overlay, KEIN Three.js im Kern — **MUST · M**
Bewertung der drei Kandidaten gegen die realen Constraints (4-Kern-VM ohne
GPU als Dev-/Test-Umgebung, iPad-Safari als Bildschirm, Low-End-iPhones als
Controller, Handy-Bundle < 200 KB):

| Kriterium | Three.js-3D | 2D-Canvas komplett | **DOM/CSS + Canvas-Overlay (Hybrid)** |
|---|---|---|---|
| Passt zum Jackbox-Flat-Look | ✗ 3D kämpft GEGEN den Stil (flache Shader nötig) | ✓ | ✓✓ Sticker-Look ist nativ CSS |
| iPad-Safari-Risiken | WebGL-Context-Loss bei Tab-Wechsel/Memory-Druck, Jitter | ✓ solide | ✓✓ Compositor-Transforms laufen mit ProMotion 120 Hz |
| Dev auf 4-Kern-VM ohne GPU | ✗ Headless-Screenshots nur via SwiftShader (langsam), schwer testbar | ○ Pixel-Tests möglich | ✓✓ DOM ist inspizier- und snapshot-testbar |
| Text/Layout (Fragen, 8 Podien, i18n) | ✗ Text in WebGL ist Schmerz | ✗ Layout von Hand | ✓✓ Flexbox macht die Podien-Reihe gratis |
| Bundle-Größe | ~170 KB gzipped nur die Lib | ✓ 0 KB | ✓ 0 KB Pflicht-Dependency |
| Tiefen-Gefühl | ✓✓ echt | ○ von Hand | ✓ Parallaxe + Perspective-Transform (A-09) reichen nachweislich (Jackbox ist auch 2D) |

**Konkret:** Bühne, Podien, LED-Wand, alle Handy-Screens = DOM/CSS
(Transforms + Klassen, zustands-getrieben aus Server-Snapshots). Darüber
liegt EIN transparentes Vollbild-`<canvas>` (2D-Context) ausschließlich für
Partikel: Money-Regen, fliegende Scheine, Konfetti, Affenhand-Klau (A-13).
Canvas deshalb, weil 100+ animierte DOM-Knoten Layout-Thrash erzeugen,
100 Sprites auf einem Canvas aber trivial sind. Three.js bleibt als
OPTIONALE, lazy-geladene Insel für GENAU EINE Szene denkbar (z. B.
3D-Tresor-Reveal im Finale) — aber erst, wenn der Rest steht (COULD, nicht
Teil des Kerns). Der Handy-Client bleibt 100 % DOM und hält so die
200-KB-Grenze aus Agent 17 locker.

**Dazu gehört ein festes Performance-Budget mit Degradations-Stufen:**
- **Partikel-Deckel:** max. 120 Sprites gleichzeitig (Bildschirm), 8
  (Handy); Objekt-Pooling, keine Allokationen im Frame.
- **Nur Compositor-Animationen:** ausschließlich `transform` + `opacity`
  animieren; `box-shadow`/`filter`-ANIMATIONEN sind verboten (Repaints) —
  statische Glows wie in A-11 sind okay.
- **Auto-Degradation:** misst der Bildschirm-Client < 45 fps über 3 s,
  schaltet er eine Stufe runter: Stufe 1 ohne Scanlines/Flacker (A-11),
  Stufe 2 halbiert Partikel, Stufe 3 ersetzt Money-Regen durch 3 große
  Scheine + Zahl. `prefers-reduced-motion` erzwingt Stufe 3.
- **Asset-Budget Bildschirm:** ≤ 2,5 MB Bilder gesamt (WebP), Preload beim
  Lobby-Screen, damit im Match NIE nachgeladen wird (Party-WLAN!).

---

## (e) PIPELINE FÜR GENERIERTE BILDER

### A-23 · Asset-Inventar + Konventionen: Was wird generiert, was wird gebaut? — **MUST · S**
Klare Trennung, damit Stil-Konsistenz beherrschbar bleibt:

**Generieren (Bitmap, einmalig):** Dschungel-Backdrop (A-09),
Vordergrund-Blätter (2×), Bühnenboden-Textur, Vorhang-Hälften (A-14),
Vignette (A-12), Affen-Portrait für den Schein (A-06), Affenhand
offen/zu (A-13), Tresor (A-15), Don-Bananas-Posen (A-16), 8 Avatar-Köpfe +
Accessoires (A-07), Emote-Sticker (A-08), Noise-Tile (A-11).
≈ 30–35 Einzelbilder — das ist der GESAMTE Bitmap-Bedarf des Spiels.

**Bauen (SVG/CSS/Fonts, parametrisch):** Logo-Reinzeichnung (A-05),
Geldschein-Layout (A-06, Portrait wird eingebettet), alle Buttons/Karten/
Namensschilder (A-04), LED-Wand-Rahmen, Spotkegel, sämtliche Typografie.
Regel: **Alles, was Text trägt oder in Spielerfarbe eingefärbt wird, ist
NIEMALS ein generiertes Bitmap** — sonst 8 Farbvarianten × jede Änderung.

**Konventionen:** WebP (Backdrops q80, Freisteller lossless), SVG für alles
Parametrische, Sprite-Sheets für Partikel (Scheine: 1 Sheet, 8
Rotationsframes); Größen: Backdrop 1920 w, Podium-Assets 512, Partikel 128,
Handy-Assets max. 256 (@2x). Ablage `assets/art/<familie>/<name>@<scale>.webp`
plus `manifest.json` (Name → Datei, Größe, Ankerpunkt) — der Preloader
(A-22) liest NUR das Manifest. Fonts als OFL/Apache-Kopie inkl. Lizenztext
ins Repo (`assets/fonts/LICENSES/`).

### A-24 · Master-Stil-Prompt-Vorlage (der „Stil-Stempel") — **MUST · S**
Jeder Generierungs-Prompt = Motiv-Satz + IMMER derselbe angehängte
Stil-Block. Vorlage (Englisch, weil Bildmodelle darauf am stabilsten
reagieren):

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

Zusatzregeln: Freisteller-Assets immer „on plain solid #FF00FF background"
anfordern (sauber ausstanzbar), Tiles (Noise, Boden) mit „seamless
tileable". Die Vorlage liegt als `docs/art/prompt_stempel.md` neben der
Stil-Bibel und wird bei JEDER Generierung unverändert angehängt — DAS ist
der Konsistenz-Hebel, nicht Nachbearbeitung.

### A-25 · Konsistenz-Workflow: Referenzbild → Batch → Palette-Clamp — **SHOULD · M**
Dreistufiger Workflow gegen den „10 Assets, 10 Stile"-Effekt:
1. **Referenz zuerst:** EIN Bild (Don-Bananas-Portrait A-06) so lange
   iterieren, bis es den Stil trifft → wird als Referenzbild jedem weiteren
   Prompt beigelegt („match the exact art style of the reference image").
2. **Batch pro Familie:** Zusammengehörige Assets (8 Avatar-Köpfe; 5
   Don-Posen) in EINER Session/einem Prompt als Gruppe anfordern
   („character sheet, 5 poses of the same monkey") — Modelle halten Stil
   INNERHALB eines Bildes viel besser als über Sessions hinweg.
3. **Palette-Clamp als Pflicht-Nachschritt:** Kleines Skript (Node +
   sharp/ImageMagick) mappt jedes Ergebnis auf die 13 Festfarben aus A-02
   (nearest-neighbor im Lab-Raum, Dithering aus) und setzt Outlines auf
   exakt `#1A1208`. Danach sehen selbst leicht abweichende Generate wie aus
   einem Guss aus. Flächige Einzelmotive (Blätter, Tresor) optional per
   Auto-Trace in SVG wandeln → verlustfrei skalierbar + winzig.
Für jede Asset-Familie eine `PROVENANCE.md` (Prompt, Datum, Modell) ablegen —
macht spätere Regenerierung im selben Stil reproduzierbar.

---

## Priorisierungs-Übersicht

| Prio | Ideen |
|---|---|
| **MUST** | A-01 Stil-Bibel · A-02 Palette · A-03 Typo-Trio · A-04 Sticker-Formensprache · A-06 Banana Buck · A-09 5-Ebenen-Bühne · A-10 Podien+Geldstapel · A-13 Money-Regen+Affenhand · A-14 TV-Regie+Bumper · A-17 Daumen-Layout · A-18 Handy=Podium · A-19 Stempel-Feedback · A-22 Hybrid-Rendering+Budget · A-23 Asset-Inventar · A-24 Prompt-Stempel |
| **SHOULD** | A-05 Logo · A-07 Avatar-Baukasten · A-11 LED-Wand · A-12 Licht-Dramaturgie · A-15 Jackpot-Tresor · A-20 Fidget-Warten · A-21 Scheine-Fächer · A-25 Konsistenz-Workflow |
| **COULD** | A-08 Emote-Sticker · A-16 Don Bananas (Figur) |

**Empfohlene Reihenfolge:** A-01/A-02/A-03/A-24 (Stil-Fundament, alles S) →
A-22 (Rendering-Grundsatzentscheidung) → A-04/A-17/A-19 (UI-Gefühl ohne ein
einziges Bild) → A-06 + A-09/A-10 (erste generierte Assets + Bühne) →
A-13/A-14 (Signature-Animationen + Regie) → Rest nach Prio.
