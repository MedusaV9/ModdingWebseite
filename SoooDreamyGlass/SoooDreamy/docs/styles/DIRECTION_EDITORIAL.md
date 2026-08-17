# Stilrichtung E — „Editorial: Das Magazin über euch"

> Designer E · Stil-Wettbewerb SooDreamy · iOS 26 · Liquid Glass · Zwei-Personen-App
>
> Prämisse: SoooDreamy ist kein Dashboard mit Karten, sondern **eine fortlaufende
> Zeitschrift, deren einziges Thema diese eine Beziehung ist** — gesetzt wie von einer
> Redaktion, die nur zwei Leser hat. Typografie IST der Stil. Liquid Glass ist das
> Interface-Chrom, das über dem „Papier" schwebt: echtes System-Glas nur dort, wo
> etwas schwebt, nie als Deko auf dem Satzspiegel.

---

## 1. Manifest

Jeder Tag mit euch ist eine Ausgabe, und diese App ist die Redaktion, die sie setzt.
Große New-York-Schlagzeilen erzählen, was heute zwischen euch passiert ist; eure
eigenen Worte werden als Pull-Quotes gewürdigt statt als Chatblasen verbraucht.
Weißraum — hier: Nachtraum — ist kein leerer Platz, sondern die Ehrerbietung des
Layouts vor dem Inhalt, denn ein Magazin drängt sich nicht auf, es lädt zum Blättern
ein. Die Paarfarben sind nicht das Papier, sondern der Markierstift der Redaktion:
sie unterstreichen, setzen Initialen und signieren Bylines, während die Schrift in
Papierweiß auf Druck-Nacht souverän bleibt. Was Apple News+ für die Welt ist, ist
SoooDreamy für genau zwei Menschen — dieselbe Sorgfalt im Satz, aber jede Zeile
handelt von euch.

---

## 2. Farbsystem — „Druckerei bei Nacht"

Dark-only bleibt Markengesetz (DESIGN.md d). Die Editorial-Richtung tauscht den
violetten Nachthimmel gegen eine **wärmere, neutralere Druck-Nacht** — Papier, das
im Dunkeln liegt, nicht Aurora. Die Aurora-Blobs entfallen auf Lese-Screens
(nur noch als leises Echo auf der Titelseite, `blobIntensity ≤ 0.35`).

### Grundtöne (neue/geänderte `Theme`-Tokens)

| Token (Vorschlag) | Hex | Rolle |
|---|---|---|
| `paperNight` | `#120D18` | Seitengrund — warm-neutrales Tiefschwarz mit Pflaumen-Rest (Familienähnlichkeit zu `#17062A`) |
| `paperNightDeep` | `#0B0810` | Cover, Scrims, Bund-Schatten zwischen „Seiten" |
| `inkWhite` | `#F4EFE9` | Primärtext — warmes Papierweiß statt hartem `#FFFFFF` (≈17:1 auf `paperNight`) |
| `inkSoft` | `#C9C2CE` | Sekundärtext / Ledes (≈10:1) |
| `agate` | `#A79FB0` | Metadaten, Bildunterschriften, Folio-Zeilen (≈7:1 — ersetzt `textTertiary`-Opacity durch Vollton, damit Kontrast REGARDLESS der Unterlage messbar ist) |
| `rubricRed` | `#FF6B4A` | Redaktionsrot (Zinnober) — Kapitelmarken, „HEUTE"-Dachzeilen, das eine laute Element pro Seite (≈6:1) |
| `hairlineInk` | `#F4EFE9` @ 0.14 | Linien/Rules (Nicht-Text, 3:1-Pflicht erst ab Increased Contrast → dann 0.38) |
| `Theme.gold` | `#FFD166` (bestehend) | bleibt Zeremonien-Gold: „Jubiläums-Ausgaben", Siegel |

**Pflicht-Folge:** `CouplePaletteRules.darkBackground` wird im selben Commit auf
`#120D18` umgestellt — die gesamte Verdict-Maschinerie (`acceptsAccent`,
`gradientForegroundVerdict`, Scrim-Rungs) rechnet dann gegen das neue Papier. Die
Logic-Tests pinnen die neuen Ratios.

### CoupleTint = Der Markierstift der Redaktion

Die Paarfarben färben **nie den Text** und **nie das Papier**. Sie erscheinen als:

1. **Markierstift:** Hervorhebungen laufen als Farbfläche HINTER dem Text
   (`coupleTint.blend` @ 0.30, Increased Contrast 0.45 — existierendes
   `Theme.Contrast.tintFill`), der Text darüber bleibt `inkWhite`. Kontrast damit
   mathematisch unabhängig von der Paarfarbe — der 4,5:1-Floor kann nicht brechen.
2. **Byline-Farben:** `primary`/`secondary` signieren, wer spricht — als 3-pt-Punkt
   vor der Byline und als Initialen-Farbe der Drop Caps. Für farbige GLYPHEN gilt
   `acceptsAccent` (≥4,5:1 auf `paperNight`), sonst greift die bestehende
   Abdunkel-Leiter.
3. **Rubrikfarbe der Ausgabe:** `blend` ist die Hausfarbe des Hefts — Unterstreichungs-
   Rule unter der Schlagzeile der Titelseite (2 pt, Nicht-Text), Tint der nativen
   TabView, Farbe des Ex-Libris-Monogramms im Logo.

### Kontrastgesetze (unverhandelbar)

- Text ≥ 4,5:1 auf `paperNight` — geprüft via `CouplePaletteRules`, nie geschätzt.
- Paarfarben tragen NIE Fließtext; als Solo-Glyphe nur nach `acceptsAccent`-Verdict.
- Rules/Hairlines sind Nicht-Text: Standard 0.14-Opacity, unter Increased Contrast
  automatisch `Theme.Contrast.hairline(increased:)` (0.38).
- `rubricRed` ist auf **eine Dachzeile bzw. Kapitelmarke pro Screen** rationiert —
  ein Magazin, das überall rot druckt, hat keine Meldung mehr.

---

## 3. Typografie — Systemfonts only, aber mit Rollenbuch

New York (`.serif`) und SF Pro (`.default`) teilen sich die Bühne nach einer klaren
Regel: **New York liest, SF Pro bedient.** Alles, was Inhalt über die Beziehung ist,
steht in New York; alles, was Knopf, Feld oder Systemchrom ist, in SF Pro. Rounded
verschwindet vollständig — die bisherige „App-Stimme" wird zur Redaktionsstimme.

### Rollen (ersetzt `Typo` in `UI/Theme.swift`)

| Rolle | Font | Semantik-Basis | Gewicht | Tracking | Einsatz |
|---|---|---|---|---|---|
| `masthead` | New York | `.largeTitle` | `.black` | −1.5 % (relativ via `tracking`, nie fixe Punkte) | Titelkopf, max. 1×/App-Bereich |
| `headline` | New York | `.title` | `.bold` | −0.5 % | Schlagzeilen der Screens (max. 1×/Screen — erbt die Hero-Regel) |
| `deck` | New York | `.title3` | `.regular` italic | 0 | Unterzeile/Lede unter der Schlagzeile |
| `bodySerif` | New York | `.body` | `.regular` | 0 | Lese-Inhalte: Tagesfrage, Journal, Briefe, Memories-Texte |
| `bodyUI` | SF Pro | `.body` | `.regular` | 0 | Bedien-Copy: Settings, Formulare, Fehlertexte |
| `label` | SF Pro | `.subheadline` | `.semibold` | 0 | Buttons, Feldlabels, Chips |
| `caption` | SF Pro | `.caption` | `.medium`, `smallCaps()` | +6 % | Bildunterschriften, Folio-Zeilen („AUSGABE 214 · KAPITEL DREI") |
| `folioNumber` | New York | `.title2` | `.heavy`, `monospacedDigit()` | 0 | Kapitel-/Seitenzahlen, Statistiken |
| `voice` | New York | `.title3` | `.regular` **italic** | 0 | UNVERÄNDERT reserviert: Worte, die die Partner selbst geschrieben haben (Pull-Quotes, Zitate) |

**Auflösung des Charter-Konflikts:** Bisher galt „Serif = von euch geschrieben".
Da jetzt die ganze Redaktion in Serif spricht, wird die Unterscheidung schärfer,
nicht schwächer: *aufrechtes* New York = die Redaktion erzählt ÜBER euch;
*kursives* New York mit Zitat-Rules und Markierstift = ihr selbst. Kursiv +
Anführungs-Geviertstriche bleiben exklusiv für `voice` — nirgendwo sonst Italic
außer im `deck` (das als Lede nie Paar-Zitate trägt).

### Optische Größen & Dynamic Type

- Alle Rollen bauen auf semantischen Text-Styles auf → New Yorks optische Schnitte
  (Small/Medium/Large/Extra Large) wählt das System selbst; wir erzwingen nichts.
- **Serif-Untergrenze:** New York erscheint nie unterhalb `.footnote`. Alles
  Kleinere (Captions, Agate, Badges) ist SF Pro — Serifen zerbröseln bei 11 pt auf
  dunklem Grund.
- AX-Größen (AX1–AX5): `masthead` fällt auf `.title`-Basis zurück (die Schlagzeile
  darf umbrechen, nie schrumpfen — `minimumScaleFactor` bleibt verboten, EVAL AX5),
  Drop Caps und `smallCaps()` werden deaktiviert (Kapitälchen sind bei AX-Größen
  schwerer lesbar), Folio-Zeilen stapeln vertikal (`prefersVerticalLayout`).
- Tracking wird über `tracking()` relativ gesetzt, nie als fixe Punktzahl — es
  skaliert mit.

---

## 4. Form & Material — Papier, Rules, und wo das Glas wohnt

### Radien: spitzer, aber nicht feindlich

Magazinseiten haben Kanten. Neue `Radius`-Werte:

- `pane = 24` (Sheets/Screens — bleibt konzentrisch zur Gerätekante, das System
  diktiert die äußere Rundung, wir kämpfen nicht gegen die Hardware),
- `card = 10` („Seiten" und Artikel-Blöcke — deutlich spitzer, liest sich als
  beschnittenes Papier),
- `control = 8`,
- Chips werden **rechteckige Schlagwort-Tags** (`Radius = 4`) statt Kapseln —
  Kapseln bleiben ausschließlich System-Chrom (native TabView, Glass-Buttons).
- Konzentrizitätsregel (`Radius.concentric`) bleibt Gesetz.

### Rules & Linien als tragendes Gestaltungselement

Linien ersetzen einen Großteil der bisherigen Karten-Container:

- **Doppel-Rule** (2×1 pt, 3 pt Abstand) unter jedem Masthead — das Erkennungszeichen.
- **Einfach-Rule** (1 pt `hairlineInk`) trennt Artikel statt Card-Hintergründe:
  weniger Flächen, mehr Luft, Draw-Calls sinken.
- **Zitat-Rules:** Pull-Quotes stehen zwischen zwei kurzen zentrierten Rules
  (33 % Breite) — kein Kasten, kein Glas.
- **Spalten-Rule** auf Regular Width (iPad): 1-pt-Vertikale zwischen Lesespalte
  und Marginalienspalte.

### Wo echtes System-Glass bleibt

Glas = alles, was ÜBER dem Papier schwebt, exakt die `GlassLevel.chrome`-Definition:
native TabView (bringt ihr Glas selbst mit), Toolbar-Buttons, der Chat-Composer,
FAB/PulseFan, Toasts. Content-Cards verlieren ihr `surface`-Glas fast vollständig —
Artikel liegen matt auf dem Papier (Rules statt Panes). Die EINE Ausnahme pro
Screen: die **Titelblatt-Karte** als `GlassLevel.tinted(coupleTint.blend)` — das
Heft-Cover des Tages, und damit weiterhin charterkonform („genau EINE Hero-Card").
Glas-auf-Glas-Verbot, matte `innerFill`-Regel und 10-Uhr-Licht bleiben unangetastet.

### Signatur-Element: Folio + Kapitelmarke + Initial

1. **Folio-Zeile** am Kopf jedes Screens: `SOODREAMY · AUSGABE 214 · BRIEFE`
   (`caption`-Rolle, `agate`, Kapitälchen). Die Ausgabennummer IST der Tage-Zähler
   des Paares — Gebot 15: Biografie, kein Spielstand.
2. **Kapitelmarke:** jede Rubrik trägt eine große New-York-Ziffer (`folioNumber`,
   72 pt via `Font.scaled` — legitim: Hero-Zahl) in `rubricRed`, halb hinter der
   Schlagzeile versetzt.
3. **Initial (Drop Cap):** Der erste Buchstabe des Tagesartikels als 3-Zeilen-
   Versalie in der Farbe des Partners, der zuletzt geschrieben hat — die eine
   Stelle, an der die Paarfarbe Buchstabe sein darf (Verdict-geprüft, sonst
   `inkWhite` mit farbiger Unterlege).

---

## 5. Motion-Signatur — „Das Blatt legt sich"

Drei benannte Bewegungen, alle als neue/gemappte `Theme.Motion`-Tokens (Charter:
Kurven werden benannt, nie inline erfunden). Reduce Motion wird pro Bewegung
definiert, nicht global weggeschaltet.

1. **Seiten-Settle** (`Motion.pageSettle` — neu zu benennen, Begründung: „arrive"
   ist zu schwebend für Papier): Inhalte kommen als abgelegtes Blatt —
   `opacity 0→1` + `offset(y: 10→0)` + minimale Rotation `0.4°→0°`,
   `spring(response: 0.42, dampingFraction: 0.94)` — fast überdämpft, Papier
   federt nicht.
   *Reduce Motion:* reiner Crossfade (220 ms), kein Offset, keine Rotation.
2. **Pull-Quote-Reveal:** die beiden Zitat-Rules wachsen von der Mitte
   (`scaleEffect(x: 0→1)`, `Motion.settle` = 0.35/0.85), das Zitat folgt 80 ms
   später mit `opacity` + `blurRadius 4→0`. Haptik: ein einzelner leiser `tap`
   beim Einrasten der Rules — „der Stift setzt ab".
   *Reduce Motion:* Rules stehen sofort in voller Länge, Zitat blendet ein (Fade
   only, kein Blur).
3. **Kapitelwechsel** (Tab-/Rubrikwechsel): die Kapitelmarke zählt via
   `contentTransition(.numericText())`, die Folio-Zeile tauscht per Crossfade,
   der einlaufende Screen macht EINEN Seiten-Settle. Gesamtdauer ≤ 350 ms —
   Navigation nutzt nie `playful` (Charter).
   *Reduce Motion:* `numericText` entfällt (harter Ziffernwechsel), nur Crossfade.

Ambient bleibt bei `drift`: das Cover der Titelseite darf in 8-s-Perioden minimal
„atmen" (Skalierung 1.00→1.008) — unter Reduce Motion/Low Power ein Standbild,
wie es `DreamyBackground` heute schon vorlebt.

---

## 6. Die NATIVE iOS-26-TabView — Rubriken statt Tabs

`LiquidTabBar` fällt ersatzlos; `MainTabView` wird eine echte `TabView` mit
`Tab`-Buildern. Innerhalb der nativen Grenzen prägt die Richtung sie so:

- **Rubriken-Namen** statt Feature-Namen (L10n `tab.*` wird umgetextet):
  „Titelseite" (Home), „Briefe" (Chat), „Rätsel" (Spielen), „Archiv" (Wir),
  „Impressum" (Mehr). SF Symbols dazu: `newspaper`, `envelope`, `puzzlepiece`,
  `archivebox`, `info.circle` (+ `.fill`-Varianten übernimmt das System).
- **Tint = Markierstift:** `.tint(coupleTint.blend)` — die einzige Farbe im Chrom;
  das native Glas rendert Auswahl-Lens, Morphing und Reduce-Transparency selbst.
- **`.tabBarMinimizeBehavior(.onScrollDown)`:** beim Lesen zieht sich die Leiste
  zurück wie ein Heft, das man näher ans Gesicht hebt — Lese-Immersion als
  System-Feature statt Eigenbau.
- **`.tabViewBottomAccessory`:** die „Laufzeile" der Redaktion — eine Zeile Agate
  über der Tab-Bar mit dem Tagesstand („Die Frage des Tages wartet auf dich ·
  Antwort von Mia liegt bereit"). Sie minimiert sich nativ in die eingeklappte
  Bar. Ersetzt Badge-Gedränge; numerische Badges bleiben native `.badge(_:)`.
- **`Tab(role: .search)`** für das Archiv-Register: die abgesetzte Such-Rubrik
  („Register") durchsucht Memories/Briefe — das System gibt ihr die getrennte
  Glas-Insel gratis.
- **Ehrliche Grenze:** Tab-Labels bleiben SF Pro in Systemgröße — die Serifen
  wohnen IM Inhalt (Folio, Schlagzeile), nicht im Chrom. Kein Font-Hack auf
  UITabBar-Ebene; genau das meint „Apple-only".
- Keyboard-Shortcuts (⌘1–⌘5), Re-Tap-to-Top und Lazy-Pane-Lifecycle übernimmt
  die native TabView bzw. bleiben in `MainTabView` erhalten.

---

## 7. Logo-Konzept — „Ex Libris": das mehrschichtige Ampersand

Das Motiv: ein **„&"-Monogramm** — das typografische Zeichen für „ihr beide",
gesetzt wie ein Ex-Libris-Stempel (Bucheigner-Marke: „aus der Bibliothek von…").
Die Gegenform der oberen Schleife ist als **negatives Herz** konstruiert — auf den
zweiten Blick, nicht auf den ersten (die noble Version des Herz-Icons).

Vier Ebenen, gebaut für Icon Composer / prozedural in `GenerateIcon.swift`
(die Previews spiegelt `AppIconKit`/`IconVariantPreview` wie heute in SwiftUI):

1. **Papier-Ebene (Hintergrund):** vertikaler Verlauf aus den drei `bg`-Hexes der
   jeweiligen Variante (bestehende Datenstruktur bleibt) — Druck-Nacht statt
   Aurora-Nacht: dunkelste Stufe unten, „Lichtkante" oben.
2. **Rahmen-Ebene:** Ex-Libris-Doppelrahmen — zwei konzentrische Rules
   (außen 2 %, innen 1 % der Kantenlänge, `inkWhite` @ 0.55) mit vier kleinen
   Eckmarken (Passermarken der Druckerei). Geometrie: Rahmen-Inset 11 %,
   konzentrisch zum Icon-Radius.
3. **Monogramm-Ebene:** das „&" als fetter Serifen-Zug (parametrischer Pfad im
   NY-Duktus: Tropfen-Terminals, hohe Strichkontrast-Achse), gefüllt in der
   `heart`-Farbe der Variante, mit dem Herz-Counter in der oberen Schleife.
   Größe 52 % der Kante, optisch mittig (2 % über geometrischer Mitte).
4. **Glas-Ebene:** im Icon Composer die systemeigene Specular/Depth-Ebene auf
   Monogramm + Rahmen (Liquid-Glass-Icons rendern Licht selbst); im CI-Renderer
   der bestehende prozedurale Specular-Sweep.

**Funktion über die 9+1 Paletten:** Ebenen 2 ist konstant (Papierweiß), Ebene 1
konsumiert `bg[]`, Ebene 3 konsumiert `heart` — exakt die heutige
`AppIconKit.Variant`-Signatur, kein Datenmodell-Umbau. Classic = Druck-Nacht +
Zinnober-&; Midnight = blaues &, Gold = goldenes & usw. Dark/Tinted/Clear-Modi des
Systems funktionieren, weil das Monogramm als eigene Ebene vorliegt (Tinted färbt
nur Ebene 3, Clear lässt Rahmen + Monogramm als Glasrelief stehen).

---

## 8. Drei Screen-Blueprints

### Home — „Die Titelseite"

- Folio-Zeile oben: `SOODREAMY · AUSGABE 214 · TITELSEITE` (Ausgabe = gemeinsame Tage).
- Masthead „SoooDreamy" in `masthead`-NY, darunter die Doppel-Rule in `coupleTint.blend`.
- **Cover-Karte** (die eine `tinted`-Glass-Hero): Dachzeile in `rubricRed`
  („HEUTE ABEND"), Schlagzeile in NY-Bold über den Tagesstand — generiert aus
  Check-in/Frage-Status („Zwei Antworten, ein Abend"), Lede in `deck`.
- Darunter kein Karten-Stapel mehr, sondern **Artikel mit Rules getrennt**:
  Tagesfrage als „Leitartikel" mit Drop Cap, Missed-Inbox als Rubrik „Meldungen"
  (Agate-Liste mit Zeitstempeln), Flashback als „Aus dem Archiv" mit Bildunterschrift.
- Eine **Pull-Quote** aus der gestrigen Antwort des Partners (`voice`, Zitat-Rules,
  Markierstift-Unterlegung) — der emotionale Kern der Seite.
- PulseFan bleibt als Glas-FAB unten rechts (Chrom schwebt, Papier liegt).
- Leerer Zustand = „Ausgabe im Entstehen": die Schlagzeile lädt als Skeleton in
  Schlagzeilen-Form, mit Einladung als Verb („Beantwortet die erste Frage").

### Chat — „Die Korrespondenz"

- Folio: `AUSGABE 214 · BRIEFE`. Kein Bubble-Klassiker: Nachrichten stehen als
  **Korrespondenz-Spalte** — linksbündiger Satz in `bodySerif`, volle Lesebreite.
- Sprecherwechsel markiert eine **Byline-Zeile** statt Blasen-Farbe: 3-pt-Punkt in
  Partnerfarbe + Initiale + Uhrzeit in Agate-Kapitälchen; eigene Nachrichten
  bekommen eine dezente Markierstift-Kante (2 pt) am linken Rand statt Vollfläche.
- Tages-Trenner = zentrierte Rule mit Datum in Kapitälchen („MITTWOCH, 12. AUGUST").
- **Briefe** (LetterCompose) erscheinen als eingerückter Kasten mit Doppel-Rule
  oben/unten und Wachs-Siegel — die einzige „gerahmte" Textsorte der Spalte.
- Composer bleibt `chrome`-Glas (schwebt über dem Papier), Senden-Kapsel trägt den
  Paar-Verlauf wie heute (`PrimaryButtonStyle` unverändert, Verdict-gesichert).
- Effekte/Sticker unverändert; Voice-Notes als „Beilage" mit Wellenform-Rule.
- Reduce Motion: neue Nachrichten per Seiten-Settle-Fade, nie einfliegend.
- AX5: Byline und Zeitstempel stapeln über dem Text (`prefersVerticalLayout`).

### Spielen-Hub — „Die Rätselseite"

- Folio: `AUSGABE 214 · RÄTSEL`. Kapitelmarke „№"-Logik: jedes Spiel trägt eine
  laufende Nummer wie in der Zeitungs-Rätselecke — „Nr. 1 — Wordle · täglich",
  „Nr. 7 — Galgenmännchen".
- **Aufmacher:** das Tages-Rätsel (Wordle/Daily Quests) als Leitartikel mit
  NY-Schlagzeile, Status-Lede („Mia hat in vier Versuchen gelöst — du bist dran")
  und Markierstift auf dem entscheidenden Wort.
- Katalog als **zweispaltiges Register** (Regular Width; kompakt einspaltig) mit
  Rules statt Karten: Nummer in `folioNumber`, Name in NY-Semibold, Meta in Agate
  („zu zweit · live · 10 Min").
- Badge „Du bist dran" = Markierstift-Tag in `blend`, kein rotes Bubble-Badge.
- **Ergebnisse-Kasten** unten: „Ergebnisse" als Agate-Tabelle (monospacedDigit) —
  Sieger-Initialen in Partnerfarben, Serien als „ruht seit…" formuliert (Gebot 15).
- Turnier/Season = „Sonderausgabe" mit Gold-Dachzeile (`Theme.gold`).
- Leerer Zustand: „Die Rätselseite ist frisch gedruckt — Nr. 1 wartet" + Button.

---

## 9. First-Launch-Kino — „Zwei Ausgaben" (45–60 s)

Prozedural wie das bestehende `CinematicIntroView` (kein Video-Asset, ein
Playhead, Haptik-Score stoppbar), aber neu erzählt. Skip ab Sekunde 3.

1. **Szene 1 — Der Kiosk (0–8 s, interaktiv):** Auf Druck-Nacht liegen zwei
   Heft-Cover nebeneinander, leicht rotiert: „Deutsche Ausgabe" / „English
   Edition" — gleiche Gestaltung, anderer Titel. Die Sprachwahl IST die erste
   Szene: Tippen wählt die Ausgabe, das andere Cover sinkt ins Dunkel. Haptik:
   Papier-`tap` beim Aufnehmen.
2. **Szene 2 — Die Setzerei (8–18 s):** Ein leeres Blatt. Eine Schlagzeile setzt
   sich Buchstabe für Buchstabe („Ein Magazin über euch." / "A magazine about the
   two of you.") mit Letternschlag-Haptik (je Glyphe ein transienter Tick,
   Intensität 0.3).
3. **Szene 3 — Zwei Tinten (18–28 s):** Von beiden Blatträndern fließt je eine
   Tinte ein (Partnerfarben, hier noch die neutralen Fallbacks) und mischt sich im
   Bundsteg zur `blend`-Farbe — die Doppel-Rule entsteht aus der Mischlinie.
   Klang: das bestehende `.pairing`-Motiv, leise.
4. **Szene 4 — Die Ausgabe Nr. 1 (28–36 s):** Die Folio-Zeile schreibt sich:
   „AUSGABE 1 · EUER ERSTER TAG" — die Zahl tickt von 0 auf 1 (`numericText`).
5. **Szene 5 — Die Pull-Quote (36–44 s):** Zitat-Rules wachsen, dazwischen
   erscheint kursiv: „Hier stehen bald eure Worte." — das Versprechen der App in
   ihrer eigenen Typografie.
6. **Szene 6 — Das Ex Libris (44–52 s):** Das Blatt faltet sich zur Icon-Fläche,
   der &-Stempel drückt sich mit einem satten Continuous-Haptic (0.25 s) aufs
   Papier — Logo-Reveal.
7. **Szene 7 — Übergabe (52–58 s):** Der Stempel wird zur Titelseite des
   Onboardings; das Kino IST bereits die App (kein Trailer-Bruch).

*Reduce Motion:* Szenen werden Standbilder mit Crossfades, die Setzerei erscheint
zeilenweise statt buchstabenweise, Tinten-Mischung wird eine fertige Doppel-Rule
mit Farbverlaufs-Legende. *VoiceOver:* jede Szene eine `Announcement`-Zeile; die
Sprachwahl ist als erstes fokussierbares Element ein echter Button pro Ausgabe.

---

## 10. Risiken & A11y

| Risiko | Gegenmaßnahme |
|---|---|
| **Serifen klein unlesbar** (NY unter 13 pt auf dunklem Grund) | Harte Untergrenze: NY nie unter `.footnote`; Captions/Agate/Tags immer SF Pro; Logic-Test auf die `Typo`-Rollen. |
| **Steifheits-Gefahr** — Editorial kann kühl/museal kippen | Wärme ist Inhalt, nicht Ornament: Pull-Quotes aus ECHTEN Antworten sind Pflichtelement der Titelseite; Drop Caps in Partnerfarbe; Ausgabennummer = gemeinsame Tage; Redaktions-Copy im „ihr"-Ton (Gebot 9) — die Redaktion schreibt liebevoll, nie distanziert. Feiern (Delight-Engine, Siegel, Gold) bleiben vollständig erhalten. |
| **Rubrik-Namen zu clever** („Impressum" für Settings könnte verwirren) | A11y-Labels tragen zusätzlich die Funktionsnamen („Mehr — Einstellungen"); Erstnutzungs-Tooltip in der Laufzeile; im Zweifel fällt „Impressum" auf „Mehr" zurück — der Test ist der Vorlese-Test mit echten Nutzern. |
| **Weniger Karten = weniger Affordanz** (Rules statt Panes: was ist tappbar?) | Tappbare Artikel erhalten Chevron + `containerShape`-Highlight; Hit-Targets bleiben ≥44 pt (`minimumHitTarget`); Increased Contrast verstärkt Rules auf 0.38. |
| **Reduce Motion** | Jede der drei Signatur-Bewegungen hat eine definierte Fade-Fassung (Abschnitt 5); Kino wird Standbild-Folge; `motionGate` bleibt der eine Schalter. |
| **Reduce Transparency** | Papier ist ohnehin matt; nur Chrom ist Glas und das ersetzt das System selbst — die Richtung REDUZIERT die Transparenz-Abhängigkeit gegenüber heute. |
| **AX5 / große Displays** | Schlagzeilen brechen um statt zu schrumpfen (kein `minimumScaleFactor` auf Information); Drop Caps + Kapitälchen ab AX1 deaktiviert; Folio stapelt vertikal; Rätsel-Register kollabiert via `gridColumns(regular:)` auf eine Spalte; native TabView übernimmt das AX-Verhalten der Tab-Labels (kein Eigenbau-Dock mehr, das kaputtgehen kann). Screenshot-Gate `paired-ax5-de.png` bleibt der Beweis. |
| **Kontrast-Drift durch neues Papier** | `CouplePaletteRules.darkBackground → #120D18` im selben Commit wie `Theme.paperNight`; alle Verdicts/Tests laufen gegen den neuen Grund; Markierstift-Prinzip entkoppelt Paarfarben vom Textkontrast strukturell. |
| **Zwei Schriftfamilien = Inkonsistenz-Risiko** | Die Regel ist ein Satz („NY liest, SF bedient") und lebt als `Typo`-Rollenbuch; Ratchets `fixed_font_sizes`/`system_size_fonts` gelten unverändert; Rounded wird per Ratchet auf 0 gefahren. |

---

*Jury-Kurzfassung: Einzigartig, weil keine Couple-App wie ein gesetztes Magazin
aussieht; Apple-nativ, weil New York, SF Pro, native TabView, System-Glas und
Icon-Composer-Ebenen die einzigen Werkzeuge sind; machbar, weil jedes Element auf
bestehende Tokens, Verdicts und die AppIconKit-Datenstruktur abbildet; warm, weil
die eigenen Worte des Paares die Pull-Quotes sind und die Ausgabennummer ihre
gemeinsamen Tage zählt; barrierefrei, weil Serifen-Untergrenze, Markierstift-
Prinzip und die drei definierten Reduce-Motion-Fassungen von Anfang an Teil der
Richtung sind — nicht Nachträge.*
