# Stilrichtung „Papier & Licht" — Direction-Papier (Designer B)

> Analoge Intimität, digital veredelt: Die App ist der gemeinsame Schreibtisch des Paares am
> Abend — Briefpapier, Polaroids, Wachssiegel, ein warmer Lampenkegel. Alles prozedural
> (keine Bitmap-Texturen), alles auf echten iOS-26-Systemkomponenten, alles innerhalb der
> bestehenden Charta (DESIGN.md). Liquid Glass wird nicht abgeschafft, sondern präzisiert:
> **Glas ist der Rahmen über den Erinnerungen — Papier ist die Erinnerung selbst.**

---

## 1. Manifest

Ein Liebesbrief ist das intimste Interface, das je erfunden wurde — SoooDreamy wird seine
digitale Fortsetzung. Alles, was das Paar geschrieben, fotografiert und gespielt hat, liegt
als Papier auf einem dunklen Schreibtisch im warmen Kegel einer Lampe; alles, was die App
selbst ist (Navigation, Werkzeuge, Chrome), schwebt als echtes System-Glas darüber wie eine
Glasplatte über einem Erinnerungsalbum. Die Trennung ist das Stilgesetz: Papier ist opak,
warm und ruht — Glas ist transparent, kühl und schwebt; nichts ist beides. Die Paarfarben
sind nicht Dekor, sondern Material: zwei Tinten, ein gemeinsames Wachssiegel, ein Band, das
die wichtigste Karte jedes Screens umschlingt. Und weil Briefe abends gelesen werden, bleibt
die App dunkel — aber ihr Dunkel ist kein Weltall mehr, sondern ein Zimmer, in dem jemand
für dich das Licht angelassen hat.

---

## 2. Farbsystem

### 2.1 Entscheidung: Dark-first bleibt — als „Lampenlicht-first"

Die Richtung ist **Dark-first**, bewusst kein Light Mode und kein adaptives Doppel-System:

1. **Die Charta hat recht, nur die Metapher wechselt.** DESIGN.md begründet Dark-only mit
   den Abend-Ritualen (Reveal, Check-in, Pulse) und der Token-Ökonomie (kein verdoppeltes
   Elevation-/Kontrast-System). Beides gilt für „Papier & Licht" unverändert — Briefe liest
   man bei Lampenlicht, nicht in der Mittagssonne.
2. **Hell-warm kommt trotzdem — als Inhalt, nicht als Modus.** Die Papierflächen sind helle,
   warme Inseln (L* ≈ 94) im dunklen Zimmer. Der Nutzer bekommt das „helle warme Gefühl" auf
   60–70 % der Content-Fläche, ohne dass ein einziger Token dupliziert wird. Helles Papier im
   dunklen Raum ist zugleich der markanteste Look der fünf Richtungen: maximaler
   Flächenkontrast statt noch einer dunklen Glas-App.
3. **A11y-Dividende:** Opakes Papier ist von Natur aus Reduce-Transparency-fest und liefert
   Tinte-auf-Papier-Kontraste von 7:1 bis 13:1 — deutlich über dem, was Text auf Glas über
   einer Aurora je erreicht.

### 2.2 Nachttöne (das Zimmer) — ersetzen `bgTop`/`bgBottom`

| Token | Hex | Rolle |
|---|---|---|
| `Papier.zimmerOben` | `#201613` | dunkles Sepia-Umbra, oberer Screen-Rand |
| `Papier.zimmerUnten` | `#33241B` | warme Kastanie, unterer Rand — der Raum wird zum Licht hin wärmer |
| `Papier.lichtkegel` | `#4A3320` | radialer Lampenschein-Gradient (Zentrum oben-links, 10-Uhr-Position), Opacity 0.35 → 0 |

Der Hintergrund ist wie heute EIN Canvas-Pass: linearer Zimmer-Gradient + EIN radialer
Lichtkegel von 10 Uhr (ersetzt die drei Aurora-Blobs) + **Staubkörner im Lichtkegel** statt
Sterne (≈ 40 Partikel, nur innerhalb des Kegels, driften mit `Theme.Motion.drift(9)`,
frieren unter Reduce Motion / Low Power / Background exakt wie heute `StarFieldView` zum
Gemälde ein). Kein neues Performance-Budget nötig.

### 2.3 Papiertöne (die Inhalte)

| Token | Hex | Rolle |
|---|---|---|
| `Papier.brief` | `#F7F1E4` | Briefpapier — Standard-Kartenfläche (heutiges `glassCard()`-Pendant) |
| `Papier.karton` | `#EFE6D2` | Karton — Sekundär-Karten, Partner-Chat-Zettel, Innenflächen |
| `Papier.kante` | `#E3D6BC` | gestapelte Kante / Rückseite / Trennlinien auf Papier |
| `Papier.polaroid` | `#FAF6EC` | Polaroid-Rahmen (nur Fotos) |

### 2.4 Tinten (Text auf Papier) — gemessen gegen `Papier.brief`

| Token | Hex | Kontrast auf `#F7F1E4` | Rolle |
|---|---|---|---|
| `Tinte.dunkel` | `#2E2318` | **13,6:1** | Primärtext, Überschriften auf Papier |
| `Tinte.sekundaer` | `#5A4A38` | **7,6:1** | Sekundärtext (verblasste Tinte) |
| `Tinte.tertiaer` | `#6E5C46` | **5,7:1** | Timestamps, Fußnoten — hart am Boden, nie kleiner als `.caption` |

### 2.5 Lampenlicht-Akzente (auf Nacht, nie auf Papier)

| Token | Hex | Kontrast auf `#201613` | Rolle |
|---|---|---|---|
| `Licht.lampengold` | `#FFC46B` | **11,3:1** | Akzent-Icons/Glows auf dem Zimmer-Dunkel; ersetzt `Theme.gold` als Zeremonien-Farbe |
| `Licht.glut` | `#E8845E` | **6,7:1** | zweiter warmer Akzent (aktive Zustände auf Nacht) |
| `Wachs.rot` | `#B33A3A` | 3,0:1 (Nacht) / 5,2:1 (Papier) | **Materialfarbe, nie Text auf Nacht** — Siegel, Stempelkissen |
| `Papier.aufNacht` | `#F3EAD9` | **14,8:1** | Text direkt auf dem Zimmer (Titel außerhalb von Karten) |

### 2.6 CoupleTint-Integration: Tinte, Wachs, Band

Die Paarfarben werden **Schreibmaterial** — die bestehende `CoupleTint`-Maschinerie bleibt,
bekommt aber Papier-Rollen:

- **Zwei Tinten:** `primary`/`secondary` sind „deine Tinte / meine Tinte". Auf Papier laufen
  sie durch eine neue Verdikt-Leiter `CouplePaletteRules.inkOnPaper(hex)` (identische
  Mechanik wie das bestehende `accentOnLight`, nur gegen `#F7F1E4` statt Weiß verankert):
  helle Mitglieder-Farben (Mint, Gold, Himmelblau) werden zur lesbaren dunklen Tinte
  abgedunkelt, ≥ 4,5:1 bleibt maschinell garantiert. Verwendung: 4-pt-Autorenkante an
  Chat-Zetteln, Unterschrift-Linien, Avatarringe — **nie Fließtext** (der bleibt
  `Tinte.dunkel`, Lesbarkeit vor Identität).
- **Ein Wachs:** `blend` ist die Siegelfarbe des Paares. Die komplette Präge-Logik existiert
  schon (`CoupleTint.onWax`, `LetterSeals`) — Meilensteine, Reveal-Zeremonie und die eine
  Hero-Karte pro Screen tragen das Blend-Wachssiegel statt des heutigen tinted-Glas-Panes.
- **Ein Band:** `heroGradient` (primary→secondary, zwei Stops wie von der Charta verlangt)
  wird als 6-pt-**Band** eingesetzt, das die Hero-Karte horizontal umschlingt (unter dem
  Siegel gekreuzt) — der Verlauf verlässt damit die Fläche und wird Objekt.
- **Re-Verankerung:** `CouplePaletteRules.darkBackground` wechselt von `#17062A` auf
  `#201613`; die bestehenden Verdikte (`gradientForegroundVerdict`, Scrim-Leiter) rechnen
  automatisch gegen den neuen Anker. Kein neues Kontrast-System — derselbe Code, neuer Fixpunkt.

### 2.7 Kontrastregeln (Gesetz, wie gehabt ≥ 4,5:1)

1. Text auf Papier: nur die drei Tinten + `inkOnPaper`-abgesicherte Paar-Tinten.
2. Text auf Nacht: `Papier.aufNacht`, `Licht.lampengold`, `Licht.glut` — alle gepinnt via
   LogicTests gegen `#201613` (Muster: bestehende `PersonalizationLogic`-Testmatrix).
3. `Licht.lampengold` auf Papier: 1,4:1 → **verboten als Text**, erlaubt nur als Glow hinter
   Papierkanten. `Wachs.rot` ist Material (Siegel), nie Text auf Nacht.
4. Verläufe: unverändert max. zwei Stops, auf Text weiterhin **kein** Verlauf —
   `.brandTitle(…)` bleibt Vollton `blend` (auf Papier: `inkOnPaper(blend)`).

---

## 3. Typografie (Systemfonts only)

Grundsatz bleibt der Charta-Satz, wird aber materialisiert: **Rounded = „die App spricht"
(gedruckt), New York Serif = „von euch geschrieben" (Feder).** Kein Custom-Font, keine
Fake-Handschrift — Intimität kommt aus der Serif-Kursive, nicht aus einem Skript-Font.

| Rolle | Font | Einsatz |
|---|---|---|
| `Typo.hero` | SF Rounded, `.largeTitle` **heavy** | unverändert, max. 1×/Screen, auf Nacht in `Papier.aufNacht`, auf Papier via `.brandTitle` |
| `Typo.title` | SF Rounded, `.title3` **bold** | Karten-Titel (gedruckte Etiketten) |
| `Typo.body` | SF Rounded, `.body` | UI-Fließtext, Buttons, Erklärungen |
| `Typo.label` / `caption` | SF Rounded, `.subheadline`/`.caption` **semibold** | unverändert |
| `Typo.number` | SF Rounded, monospacedDigit **bold** | Stats — gedruckte Zahlen, nie Serif |
| `Typo.voice` | **New York, `.title3` italic** | unverändert heilig: NUR Paar-Worte (Zitat, Journal, Kapseln) |
| `Typo.brief` **(neu)** | **New York, `.body` regular** | Brief-KÖRPER beim Lesen (LetterComposer/Reader, Journal-Volltext) — die aufrechte Lesestimme zur kursiven `voice` |
| `Typo.anschrift` **(neu)** | **New York, `.caption` semibold `.smallCaps()`** | Poststempel, Datumszeilen auf Papier, „Für dich"-Adresszeilen — der einzige Kapitälchen-Einsatz der App |

Regeln: Serif erscheint **ausschließlich auf Papierflächen** (nie auf Glas, nie auf Nacht) —
die Feder schreibt nur auf Papier. Alle Rollen bauen auf semantischen Styles auf (Dynamic
Type inklusive AX5 funktioniert weiter); `Font.scaled` bleibt Hero-Zahlen vorbehalten.

---

## 4. Form & Material

### 4.1 Die Zwei-Materialien-Regel

| Material | Was | Verhalten |
|---|---|---|
| **System-Glas** (`GlassLevel.chrome`, unverändert echt) | ALLES was schwebt: native TabView, Toolbar-Buttons, FAB/PulseFan, Chat-Eingabeleiste, Sheets-Grabber | `glassEffect(.regular)`, System rendert Refraktion/Kante; Inhalte scrollen darunter durch |
| **Papier** (neu: `PaperLevel`, ersetzt `GlassLevel.surface` + `.tinted`) | ALLES was liegt: Content-Karten, Chat-Zettel, Spielkarten, Polaroids | opak, matt, wirft `Elevation`-Schatten, hat eine warme Lichtkante |

Glas-auf-Glas bleibt verboten; neu dazu: **Papier-auf-Glas ist verboten** (Papier liegt
immer UNTER dem Chrome). Die tinted-Hero-Stufe wird zur **Briefbogen-Karte**: `Papier.brief`
+ Band (2.6) + Wachssiegel — eine pro Screen, wie bisher.

### 4.2 Radien (konzentrisch, bestehende Skala + zwei Papier-Töne)

- `Radius.pane = 28`, `card = 22`, `control = 14`: unverändert für Glas/Sheets.
- **`Radius.papier = 10` (neu):** geschnittenes Papier ist schärfer als Glas — alle
  Papierkarten. **`Radius.polaroid = 4` (neu):** Fotorahmen. Innen weiter
  `Radius.concentric(parent:padding:)`.

### 4.3 Papierkanten — prozedural, nie Bitmap

- **Gestanzt (Standard):** glatter `RoundedRectangle(cornerRadius: Radius.papier)`. 90 % aller Karten.
- **Gerissen (`TornEdgeShape`, neu in `UI/`):** `Shape`, dessen EINE Kante (meist unten) aus
  seeded Jitter besteht — Amplitude 2,5 pt, Periode 10–14 pt, Seed = stabile Item-ID (der
  Riss eines Zettels flackert nie zwischen Renders). Einsatz sparsam: abgerissene
  Notizzettel (Chat-Schnellantworten, Flashback-Karte), max. 1 gerissene Kante pro Screen.
- **Gezackt/gestanzt-rund (Coupon-Kante):** Scallop-Pfad für Gutscheine — existiert als Motiv
  bereits (Coupons), wird formalisiert.
- **Papierkorn:** ein statischer Metal-`colorEffect`-Shader (Hash-Noise, Luminanz ±2 %,
  KEINE Animation) auf Papierflächen — unter Increased Contrast abgeschaltet. Kein Asset,
  ~10 Zeilen MSL.
- **Lichtkante (10-Uhr-Regel, wörtlich genommen):** jede Papierkarte trägt oben-links eine
  1-pt-Kante in `Papier.brief` +8 % Luminanz und wirft den bestehenden `Elevation`-Schatten
  nach unten-rechts. Die Lampe IST die 10-Uhr-Lichtquelle der Charta — die Regel bleibt, sie
  bekommt nur eine Erzählung.

### 4.4 Signatur-Elemente (genau drei, mehr nicht)

1. **Das Wachssiegel** (DIE Signatur): Kreis Ø 44 pt in `blend`-Wachs mit geprägtem
   Herz/Monogramm (`onWax`-Ink, Maschinerie existiert), leichte Rotation −4°…+4° (seeded).
   Erscheint: Hero-Karte, Meilensteine, ungeöffnete Reveals, App-Icon. 
2. **Die Klebeecke:** dreieckige, halbtransparente Pergament-Ecken (`Papier.kante` @ 0.85)
   an Polaroids/Erinnerungen — prozedural, 2 Ecken diagonal, nie alle vier.
3. **Der Poststempel:** gestrichelter Doppelkreis Ø 56 pt, `Typo.anschrift`-Datum, Rotation
   −8°, `Tinte.sekundaer` @ 0.7 — für Datums-/Orts-Metadaten (Journal, Kapseln, Jahrestage).

---

## 5. Motion-Signatur

Drei Choreografien, alle auf den **vier bestehenden Kurven** (keine fünfte Kurve nötig —
Charta-Gebot 11 bleibt unangetastet):

1. **Blättern** (Screen-/Karten-Einstieg): Karte rotiert um die führende Kante herein —
   `rotation3DEffect` von −12° → 0°, `anchor: .leading`, `perspective: 0.3`, gefahren von
   `Theme.Motion.arrive` (spring 0.5/0.8); der Elevation-Schatten wandert synchron von
   `x: −4` nach `x: +1` (das Licht streicht über die sich legende Seite). Reduce Motion:
   reiner Crossfade.
2. **Legen** (Elemente erscheinen im Bestand): Zettel „landet" auf dem Tisch — Scale
   1.04 → 1.0, Schatten-Radius 24 → 14, y-Offset 6 → 0, Rotation von seeded ±1,5° auf die
   Ruhelage ±0,8°, gefahren von `Theme.Motion.settle` (0.35/0.85). Chat-Nachrichten,
   Grid-Kacheln (gestaffelt, 40 ms Versatz, max. 6 Elemente). Reduce Motion: Fade ohne
   Transform.
3. **Lichtschein** (Feier-/Ankunftsmoment): hinter dem Element blüht ein radialer
   `Licht.lampengold`-Glow — Opacity 0 → 0.35 → 0.22, Radius 0 → 1,4 × Elementgröße,
   `Theme.Motion.drift(1.2)`, danach statisch stehend (der Moment „bleibt beleuchtet").
   Ersetzt Standard-Konfetti auf Stufe 1–2; `epic` behält Partikel. Reduce Motion: der
   statische End-Glow erscheint sofort — ein Gemälde, kein schwarzes Loch.

---

## 6. Die NATIVE iOS-26-TabView

Die Custom-`LiquidTabBar` weicht der echten `TabView` — und „Papier & Licht" ist die
Richtung, die davon am meisten profitiert, weil der Materialkontrast (System-Glas über
Papier) ihr Kernbild ist:

- **Struktur:** `Tab`-Builder mit den fünf Tabs (Home, Chat, Spielen, Wir, Mehr), Memories
  zusätzlich als `Tab(role: .search)`-Kandidat geprüft (die „Erinnerung suchen"-Lupe gehört
  nativ nach rechts). Badges (`.badge(unread)`) laufen über das System — der heutige
  Wachspunkt-Nachbau entfällt.
- **Minimize-on-scroll:** `.tabBarMinimizeBehavior(.onScrollDown)` — beim Lesen eines
  Briefes zieht sich die Glasplatte zurück und gibt das Papier frei; beim Hochscrollen
  kehrt sie zurück. Zusammen mit `.scrollEdgeEffectStyle(.soft)` scrollt Papier sichtbar
  UNTER dem Glas durch: der „Glasrahmen über Erinnerungen" ist wörtlich im System verankert.
- **Prägung in nativen Grenzen:** (a) `tint` der Selektion = `coupleTint.blend` — das Band
  des Paares markiert „hier seid ihr"; (b) Symbolwahl warm statt technisch:
  `lamp.desk`/(fill) für Home, `envelope`/(fill) für Chat, `dice` für Spielen,
  `photo.on.rectangle.angled` für Wir, `ellipsis.circle` für Mehr; (c) KEINE Overlays, keine
  Materialien, keine Lens-Nachbauten auf der Bar — das System rendert.
- **`TabViewBottomAccessory`:** der „Heute-Zettel" — eine schmale Papier-Miniatur über der
  Bar mit dem Tagesritual-Status (Frage beantwortet? Siegel wartet?), tappbar zum Reveal.
  Das Accessory ist die EINE Stelle, an der Papier das Chrome berührt — vom System
  verwaltet, minimiert sich mit.
- **iPad:** `.tabViewStyle(.sidebarAdaptable)` — die Sidebar wird das „Adressbuch":
  Memories-Gruppen (`MemoriesSidebarGroup`) als native Sections, Systemglas-Hintergrund,
  Papier-Inhalt rechts. Die bisherige handgebaute Split-Logik in `MemoriesView` schrumpft.
- **Gewinn nebenbei:** AX5-Verhalten, Reselect-to-top, Keyboard-Fokus und
  Reduce-Transparency der Bar sind ab dann Systemleistung — `TabBarLogic`-Dockmathe und der
  UIScrollView-Walk in `MainTabView` können ersatzlos fallen.

---

## 7. Logo-Konzept: „Das versiegelte Polaroid" (mehrschichtig)

Motiv: ein leicht gedrehtes Polaroid-Blatt (Briefpapier im Fotorahmen-Schnitt) mit
Wachssiegel-Herz, angestrahlt von 10-Uhr-Lampenlicht. Vier Ebenen für Icon Composer / Layered Icon, **prozedural via
AppIconKit** (neues kleines Target: SwiftUI-Layer → `ImageRenderer` → Layer-PNGs bzw.
`.icon`-Projekt; deterministisch aus der bestehenden `Variant`-Tabelle in `IconGiftView`):

| Ebene (hinten → vorn) | Inhalt | Geometrie | Verhalten |
|---|---|---|---|
| **L1 Zimmer** | Variant-`bg`-Verlauf (3 Stops der jeweiligen Palette) + radialer Lichtkegel von 10 Uhr | vollflächig | Dark-Variante: Verlauf 20 % dunkler, Kegel 20 % stärker |
| **L2 Papier** | `Papier.brief`-Rechteck, `Radius.polaroid`, unten `TornEdgeShape`-Riss | Rotation −6°, 78 % der Icon-Breite, optisches Zentrum leicht über Mitte | opak, Emboss-Schatten nach unten-rechts; Clear/Tinted-Modus: nur Kontur als Glas-Gravur |
| **L3 Licht** | weicher radialer Glow `Licht.lampengold` über der Papier-Oberkante | Zentrum 10-Uhr-Ecke | Translucency AN — hier spielt das System-Specular; im Tinted-Modus trägt diese Ebene den System-Tint |
| **L4 Siegel** | Wachssiegel mit Herz-Prägung in Variant-`heart`-Farbe, Prägetinte via `onWax`-Regel | Ø 34 % Icon-Breite, auf dem Riss sitzend, Rotation +3° | vorderste Ebene, bekommt Specular + Parallaxe/Tiefe des Layered Icons |

**Funktion über die 9 Paletten-Varianten** (sunset, midnight, mint, rose, ocean, gold,
lavender, blossom, aurora — exakt die bestehende Tabelle): L1 nimmt die drei `bg`-Hexwerte,
L4 die `heart`-Farbe der Variante; L2/L3 sind invariant (Papier und Lampenlicht sind die
Marke, die Palette ist das Geschenk). AppIconKit rendert alle 9 + classic in einem Lauf —
das Icon-Gifting-Feature behält seine Auswahl, bekommt aber erstmals ein konsistentes,
geschichtetes Markenmotiv statt zehn handgemalter Herzen.

---

## 8. Screen-Blueprints

### 8.1 Home — „Der Schreibtisch am Abend"

1. Hintergrund: Zimmer-Gradient, Lichtkegel von 10 Uhr, Staubkörner driften im Kegel.
2. Kopf ohne Karte, direkt auf Nacht: Avatare + „137 gemeinsame Tage" in `Papier.aufNacht`, Tagesphase-Zeile in `Licht.glut`.
3. Hero: die **Briefbogen-Karte** — Tagesfrage auf `Papier.brief`, Band in `heroGradient` quer, ungeöffnet trägt sie das `blend`-Wachssiegel; Antwort tippen = Siegel später brechen (bestehende Reveal-Zeremonie).
4. Darunter max. drei Papier-Karten (`Radius.papier`, Lichtkante, gestanzt): Missed-Inbox als „Während du weg warst"-Stapel (2 pt versetzte Rückseite in `Papier.kante` deutet den Stapel an), Touch-Grid, Flashback-Polaroid mit zwei Klebeecken und Poststempel des Original-Datums.
5. Flashback-Polaroid liegt seeded −2° gedreht — die einzige Rotation im Screen.
6. „Mehr"-Falte: als umgeschlagene Papierecke (Fold-Dreieck unten rechts an der letzten Karte) statt Chevron.
7. PulseFan-FAB bleibt echtes rundes Chrome-Glas — Werkzeug, nicht Erinnerung.
8. Einstieg der Karten: einmal **Blättern** für den Hero, **Legen** gestaffelt für den Rest.
9. Unten scrollt alles unter die native, sich minimierende Glass-TabView; Accessory zeigt den Heute-Zettel.

### 8.2 Chat — „Der Briefwechsel"

1. Kein Bubble-Chat mehr, ein Zettelwechsel: eigene Nachrichten auf `Papier.brief`, Partner-Nachrichten auf `Papier.karton` — beide `Radius.papier`, Text immer `Tinte.dunkel`.
2. Autorenschaft trägt die **Tintenkante**: 4-pt-Streifen an der Außenkante jedes Zettels in `inkOnPaper(primary/secondary)` — Farbcode statt Links/rechts-Raten, auch für Farbenblinde durch die Seitenlage doppelt kodiert.
3. Tagestrenner: Poststempel-Medaillon mittig (`Typo.anschrift`), kein Linien-Divider.
4. Liebesbriefe (LetterComposer) sind das Serif-Ritual: `Typo.brief` für den Körper, `Typo.voice` für die Anrede, versiegelt verschickt = Zettel mit `blend`-Wachssiegel in der Liste, Siegel bricht beim Öffnen (Haptik + Ansage, Pfad existiert).
5. Voice-Notes: Wellenform als Tinten-Strich auf einem schmalen Zettelstreifen.
6. Neue Nachricht landet mit **Legen** (settle) + leiser Papier-Haptik (`Haptics.tap`).
7. Eingabeleiste bleibt echtes Chrome-Glas (interactive) — der Stift gehört zur Glasplatte, nicht zum Papier; Effekt-Wand und Sticker unverändert dahinter.
8. Sticker/Fotos erscheinen als Mini-Polaroids mit einer Klebeecke.
9. Scroll läuft unter der minimierenden TabView durch — langes Lesen = maximales Papier.

### 8.3 Spielen-Hub — „Der Spieleabend"

1. Kopfzeile auf Nacht („Spieleabend?" in `Papier.aufNacht`), Season-Status als schmaler Zettelstreifen mit Poststempel des Monats.
2. Hero: „Heute dran"-Briefbogen — das eine Spiel, das die Heuristik vorschlägt, mit Band und Siegel, wenn der Partner bereits gezogen hat („Du bist dran" = Siegel wartet).
3. Session-Banner (laufende Partien) als **Spielkarten-Stapel**: Papier-Karten mit 2°-Fächerung, oben die aktuellste.
4. Katalog-Gruppen (Täglich/Rundenbasiert/Live/Party) als Karten-Grid auf `Papier.karton`, Icons in `Tinte.sekundaer`, ausgewählt in `blend`-Tinte.
5. Collapse-Falte je Gruppe: umgeschlagene Ecke statt Chevron (wie Home).
6. Siege/Statistiken in `Typo.number` (gedruckt) — nie Serif, Zahlen sind Druckwerk.
7. Ein Sieg feiert mit **Lichtschein** (Stufe 1–2), Turnier-Finale behält `epic`-Partikel.
8. Wordle/Brettspiele im Detail-Screen: Spielbrett auf einem großen Papier-Bogen, Steine werfen Elevation-Schatten — das Brett liegt im Lichtkegel.
9. Einstieg: Hero **Blättern**, Grid **Legen** gestaffelt.

---

## 9. First-Launch-Kino (45–60 s, überspringbar ab Szene 2)

| # | Zeit | Szene |
|---|---|---|
| 1 | 0–8 s | **Dunkles Zimmer. Ein Lampenklick** (Sound + `Haptics.tap`) — der Lichtkegel blendet auf und beleuchtet zwei Zettel auf dem Tisch: „Deutsch" / „English" in `Typo.brief`. Die Sprachwahl IST die erste Berührung: Zettel antippen, der andere gleitet aus dem Licht. |
| 2 | 8–16 s | Ein Umschlag schiebt sich in den Kegel, Anschrift in `Typo.anschrift`: „Für euch beide". Poststempel mit dem heutigen Datum stempelt sich auf (Stempel-Haptik `rigid`). |
| 3 | 16–26 s | Das neutrale Wachssiegel bricht (bestehende Reveal-Klangwelt), der Brief entfaltet sich mit **Blättern**: zwei Serif-Sätze, was SoooDreamy ist — „Ein Ort für zwei. Alles hier gehört nur euch." |
| 4 | 26–38 s | **Zwei Tintenfässer**: „Wähl deine Farbe" — der Nutzer wählt seine Mitgliedsfarbe, ein Tintentropfen fällt und zieht einen Strich; der Strich des Partners erscheint als Platzhalter-Schimmer. Beide Striche laufen aufeinander zu und mischen sich zum `blend`. |
| 5 | 38–46 s | Aus dem Blend gießt sich ein **Wachssiegel** und prägt das Herz — „Das ist eure Farbe. Nur ihr zwei habt sie." (VoiceOver-Ansage identisch). |
| 6 | 46–54 s | Ein leeres Polaroid entwickelt sich von Weiß zu `Papier.polaroid` — es bleibt leer: „Eure erste Erinnerung fehlt noch." (Einladung, kein Vorwurf — Gebot der leeren Zustände.) |
| 7 | 54–60 s | Das Papier legt sich in den Home-Screen (**Legen**), die Glas-TabView gleitet von unten herauf — das Kino endet exakt in der echten UI, kein Schnitt. Pairing-Code-Schritt folgt als erster Zettel auf dem Tisch. |

Reduce Motion: alle sieben Szenen als Crossfade-Standbilder mit identischen Ansagen;
Gesamtdauer sinkt auf ~30 s. Sound optional (Erststart respektiert Stummschalter).

---

## 10. Risiken & A11y

- **Kitsch-Gefahr (das Hauptrisiko der Richtung):** Skeuomorphismus kippt schnell in
  Bastelladen. Leitplanken: max. 3 Papier-Artefakte pro Screen (Siegel/Klebeecke/Stempel
  zählen), max. 1 gerissene Kante und max. 1 Rotation pro Screen, keine Fake-Handschrift
  (nur New York), kein Vergilbungs-Gradient, Korn ≤ 2 % Luminanz. Papier ist Trägermaterial,
  nicht Deko — jede Karte muss auch ohne alle Artefakte funktionieren.
- **Lesbarkeit auf Papiertönen:** neue Verdikt-Leiter `inkOnPaper` + gepinnte
  LogicTest-Matrix (alle 3 Tinten × 4 Papiere, alle 8 Mitgliedsfarben durch die Leiter);
  Korn-Shader wird unter Text < `.subheadline` nicht gerendert; `Tinte.tertiaer` nie unter
  `.caption`-Größe.
- **Reduce Transparency:** strukturell besser als heute — 60–70 % der Fläche (Papier) ist
  bereits opak; das verbleibende Chrome-Glas ersetzt das System selbst. Der Lichtkegel-Scrim
  läuft über den bestehenden `MotionGate.scrim`-Pfad (wird zu `Papier.zimmerOben` opak).
- **Reduce Motion:** alle drei Signatur-Bewegungen haben definierte stille Pfade (Crossfade,
  Fade, statischer Glow); Staubkörner frieren wie heute die Sterne zum Gemälde ein; das
  First-Launch-Kino hat einen kompletten Standbild-Schnitt.
- **AX5 / Dynamic Type:** Alle Artefakte (Kanten, Ecken, Stempel, Band) sind `overlay`-Dekor
  ohne Layout-Beitrag — Text verdrängt nie ein Siegel, ein Siegel nie Text. Poststempel
  cappen bei `accessibility1` (wie heute die Dock-Symbole); Polaroid-Grids kollabieren über
  die bestehende `AccessibilityBudget`-Spaltenregel; die native TabView bringt ihr
  AX5-Verhalten selbst mit. Torn-Edges behalten 4 pt Sicherheitsabstand zum Textblock.
- **Increased Contrast:** Korn aus, Lichtkanten → `Tinte.dunkel`-Hairline auf Papier,
  `Tinte.sekundaer/tertiaer` steigen auf die bestehende `Theme.Contrast`-Leiter.
- **VoiceOver:** Siegel-Momente sind bereits angesagt (Reveal-Pfad); neue Ansagen für
  „versiegelt/entsiegelt" als Zustands-Traits an Brief-Zetteln; Tintenkanten sind rein
  visuell redundant (Seitenlage + Name tragen die Information).
- **Performance:** Zimmer-Canvas ersetzt Aurora-Canvas 1:1 (ein Pass), Korn ist ein statischer
  Shader ohne Timeline, Papier ist billiger als Glas (kein Refraktions-Sampling) —
  Draw-Call-Budget sinkt eher.
- **Charta-Verträglichkeit (Machbarkeits-Nachweis):** kein neues Motion-Token, kein
  Text-Verlauf, Emoji-Regeln unberührt, `voice`-Heiligkeit gestärkt, Ratchets
  (`bare_white_opacity`, `raw_corner_radius`) sinken durch die Token-Migration. Die zwei
  echten Charta-Änderungen sind benannt: `darkBackground`-Anker (2.6) und die Ablösung von
  `GlassLevel.surface/tinted` durch `PaperLevel` (4.1) — beides zentrale, testgesicherte
  Umbauten in der UI-Schicht, keine Feature-Streuung.

---

*Designer B — „Papier & Licht": Die App, die sich anfühlt, als hätte euer Lieblingsmensch
das Licht angelassen.*
