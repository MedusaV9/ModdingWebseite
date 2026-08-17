# Stilrichtung „Neon-Duett" — Designer D

**Wettbewerbsbeitrag** für den SoooDreamy-Makeover (SwiftUI, iOS 26, Liquid Glass, sideloaded
Zwei-Personen-App). Diese Richtung ersetzt den Aurora-Nachthimmel durch eine andere Nacht:
**die Stadt, spät, zu zweit.** Late-Night-Jazzbar trifft Apple Design — schwarzer Samt, zwei
Neonröhren (ihre Farbe, seine Farbe), und Liquid Glass ist keine Dekoration mehr, sondern das,
was Glas nachts wirklich ist: eine beschlagene Scheibe, hinter der die Stadt leuchtet.

Bezugspunkte im Code: `UI/Theme.swift` (Tokens, `CoupleTint`, Kontrast-Verdicts),
`UI/Glass.swift` (`GlassLevel`, `Elevation`, `GlassGroup`), `Content/PersonalizationLogic.swift`
(`CouplePaletteRules`, `minimumContrast = 4.5`), `Features/Settings/IconGiftView.swift`
(`AppIconKit`, 9 Paletten-Varianten + classic), `Features/Onboarding/CinematicIntroView.swift`
(prozedurale Kinematik, stoppbare Haptik-Partitur). Alles hier Vorgeschlagene bleibt innerhalb
der DESIGN.md-Charta: Rohwerte nur in der UI-Schicht, 4,5:1 ohne Ausnahme, kein Verlauf auf
Text, drei Erlebnispfade pro magischem Moment.

---

## 1. Manifest

Neon-Duett ist die App als gemeinsame Nacht in der Stadt: zwei Menschen, zwei Lichter, eine
Scheibe zwischen ihnen und dem Rest der Welt. Der Grund ist schwarzer Samt — nie totes
Schwarz, sondern Stoff mit Flor, der Licht schluckt statt es zurückzuwerfen — und alles, was
leuchtet, leuchtet, weil es die beiden sind. Es gibt genau zwei Neonröhren im ganzen System,
und sie tragen die Paarfarben; die App selbst besitzt keine eigene Leuchtfarbe mehr, nur
Messing, Glas und Dunkelheit. Liquid Glass wird vom Baumaterial zum Fensterglas
zurückgestuft: eine beschlagene Scheibe für das Dock und ein Schaufenster pro Screen, sonst
matter Samt — was selten ist, wirkt. Und weil echte Neonröhren flackern, wenn sie sterben,
gilt hier das strengste Bewegungsgesetz der App: **Licht glimmt auf, Licht zieht Spuren,
Licht flackert niemals.**

---

## 2. Farbsystem

### 2.1 Samt-Schwarztöne (ersetzen `bgTop`/`bgBottom`)

Samt ist nie neutralgrau und nie #000000 — er hat einen kalten Violett-Blau-Stich (der Flor
reflektiert das Neon minimal). Der Hintergrund-Verlauf wird fast unsichtbar flach: kein
Aurora-Spektakel mehr, nur Lichtabfall nach unten wie in einer Lounge.

| Token (neu in `Theme`) | Hex | Rolle |
|---|---|---|
| `Velvet.ink` | `#0A090F` | DER Grundton. Neue Kontrast-Referenz für `CouplePaletteRules` (heute `#17062A`). |
| `Velvet.deep` | `#060509` | Unterer Verlaufsstopp (2-Stopp-Regel bleibt), Sheet-Hintergründe, Scrims. |
| `Velvet.card` | `#12101A` | **Opake** Samt-Karte (ersetzt `Theme.card` = white 7 %). Deckend aus Prinzip, s. §4. |
| `Velvet.pile` | `#1B1826` | Matte Innenflächen in Karten (ersetzt `Theme.innerFill` auf Samt), gedrückte Zustände. |
| `Velvet.seam` | `white @ 0.10` | Haarlinie („Naht") auf Samtkarten — bleibt der eine erlaubte Weiß-Alpha-Wert. |
| `brass` | `#E4B368` | Das Messing der Bar: Zeremonien, Siegel, Medaillen. Ersetzt visuell `Theme.gold`, gleiche Rolle. |
| `textPrimary` | `#F5F2FA` | Warm-Weiß statt Voll-Weiß — Voll-Weiß auf Samt blendet. 18,9:1 auf `Velvet.ink`. |
| `textSecondary` | `#F5F2FA @ 0.76` | wie heute, gegen `Velvet.ink` gemessen. |
| `textTertiary` | `#F5F2FA @ 0.62` | dito; Increased-Contrast-Varianten wie in `Theme.Contrast` heute. |

### 2.2 Die zwei Neonröhren = CoupleTint

**Es gibt keine App-Neonfarbe.** `coupleTint.primary` ist Röhre A, `coupleTint.secondary`
Röhre B, `coupleTint.blend` ist das Mischlicht, das entsteht, wo sich ihre Halos überlagern —
physikalisch erzählt und exakt das, was `CouplePaletteRules.derived` heute schon rechnet.
Vor dem Pairing leuchtet nur EINE Röhre (neutrales Rosé `#FF5C8A`, der heutige Fallback);
die zweite Röhre hängt sichtbar dunkel daneben — das Pairing ist der Moment, in dem sie
angeht. Das ist Paar-Wärme als Systemzustand, nicht als Deko.

Jede Röhre wird in drei abgeleiteten Schichten gerendert (neue pure Funktionen in
`CouplePaletteRules`, testbar wie `accentOnLight`):

| Schicht | Ableitung | Einsatz |
|---|---|---|
| `neonCore(hex)` | Mitgliedsfarbe 82 % Richtung Weiß gemischt | Der weißglühende Röhrenkern: Strichzeichnungen, Glyphen-Farbe leuchtender Labels. ≥ 13:1 auf `Velvet.ink` für alle 8 `memberColors`. |
| `neonGas(hex)` | Mitgliedsfarbe pur | Der sichtbare Farbkörper: Unterstriche, Ringe, Akzent-Icons. Schwächste Farbe (`#A855F7`) misst 5,0:1 auf `Velvet.ink` — alle 8 liegen über 4,5:1, per LogicTest gepinnt. |
| `neonHalo(hex)` | Mitgliedsfarbe als Schatten/Blur, Opacity-Budget s. 2.3 | Der Glow. Ist **nie** Träger von Information, nur Atmosphäre. |

### 2.3 Glow ohne Kontrastverlust — der Röhrentrick

Der physikalische Grund, warum echte Leuchtreklame lesbar ist: **der Kern ist weißglühend,
die Farbe steckt im Gas drumherum.** Genau so glüht Text hier:

1. **Glyphen sind immer Vollton** (`textPrimary` oder `neonCore`) — nie Verlauf (Charta),
   nie die pure Tint-Farbe unter Titelgröße.
2. **Der Glow ist ein Schatten, keine Füllung:** `shadow(color: neonHalo, radius: 12–28)`
   hinter dem Vollton-Glyph. Der Halo hellt den lokalen Hintergrund auf — deshalb gilt er
   als Hintergrund und wird mitgemessen.
3. **Halo-Deckel (das neue Gesetz):** Innerhalb der Glyphen-Bounding-Box darf die effektive
   Halo-Opacity **0,22 nicht überschreiten**. Worst Case (hellste Mitgliedsfarben Gold
   `#FFD166` / Mint `#6EE7B7`): komposituierter Grund ≈ L 0,14 → `neonCore` dagegen ≥ 5,2:1.
   Typische Farben liegen bei 7–15:1. Ein `neonHaloVerdict(hex)` in `CouplePaletteRules`
   rechnet das pro Palette und drosselt die Opacity, bis 4,5:1 steht — dieselbe Maschinerie
   wie `gradientForegroundVerdict`, kein neues Prinzip.
4. **Glow-Budget:** max. **2** gleichzeitig glühende Elemente pro Viewport (Marquee-Titel +
   ein Akzent). Fließtext, Labels, Captions glühen **nie**.
5. **Bokeh-Stadt statt Aurora:** Hinter der Scheibe liegen 5–7 unscharfe Lichtscheiben
   (Canvas, wie `AuroraBlobsView`): 2× Röhre A, 2× Röhre B, 1–2× Straßenlaterne
   `#E4B368 @ 0.10`, 1× kaltes Fensterlicht `#8FA8D9 @ 0.08`. Gesamthelligkeit unter Karten
   gedeckelt wie heute (`blobIntensity`-Mechanik bleibt).

---

## 3. Typografie (Systemfonts only)

Grundsatz: **Kondensiert ist die Leuchtschrift, Normal ist das Gespräch, Rounded ist das
Lächeln, Serif bleibt heilig.** Alles via `Font.system` + `fontWidth(_:)` — kein Custom-Font,
Dynamic Type bleibt durchgängig semantisch (Gebot 12).

| Rolle (in `Typo`) | Definition | Einsatz |
|---|---|---|
| `marquee` **(neu)** | `.title2`, SF Pro, `.fontWidth(.condensed)`, `.heavy`, VERSALIEN, `tracking(1.4)` | Die eine Leuchtschrift pro Screen: Screen-Titel/Sektions-Schild. Trägt den Neon-Unterstrich (§4). **AX-Fallback:** ab `isAccessibilitySize` normale Breite, gemischte Schreibung, Tracking 0 — kondensierte Versalien sind bei AX5 unleserlich. |
| `hero` | `.largeTitle`, `.condensed`, `.heavy` | max. 1×/Screen, nur Zeremonien/Reveals. |
| `title` | `.title3`, Normalbreite, `.semibold` | Karten-Titel. Nicht mehr rounded — die Bar ist erwachsen. |
| `body` | `.body`, SF Pro regular | Fließtext. |
| `label` | `.subheadline`, `.semibold` | Controls, Zeilen-Labels. |
| `caption` | `.caption`, `.semibold`, `tracking(0.8)`, Versalien nur für Meta („HEUTE ABEND") | Metadaten, Zeitstempel. |
| `number` | `.title2`, `.condensed`, `.bold`, `monospacedDigit` | Anzeigetafel der Bar: Streak, Stats, Timer. |
| `warm` **(neu)** | `.subheadline`, `design: .rounded`, `.bold` | NUR: Namen der beiden, „137 gemeinsame Tage", Avatare-Beschriftung. Rounded wird vom Default zur Zärtlichkeit. |
| `voice` | unverändert Serif italic | Worte, die die beiden selbst geschrieben haben. Unantastbar. |

`brandTitle(_:)` bleibt die eine Titel-Behandlung, wechselt aber auf `marquee`-Typo in
Vollton `coupleTint.blend` + Halo nach §2.3 — weiterhin ein benannter Stil, kein Freihand.

---

## 4. Form & Material

### 4.1 Radien — unverändert, bewusst

`Radius.pane = 28 · card = 22 · control = 14 · Capsule` und die Konzentrizitäts-Regel bleiben
exakt bestehen. Die Richtung gewinnt ihre Identität aus Licht und Material, nicht aus neuen
Eckenwerten — das hält den Umbau klein und die Charta ungebrochen.

### 4.2 Wo echtes System-Liquid-Glass (die beschlagene Scheibe)

Glas wird **rationiert**, dadurch kostbar:

- **Das Dock** (native TabView, §6) und schwebende Chrome-Buttons: `GlassLevel.chrome`,
  unverändert echtes `glassEffect`. Das ist die beschlagene Scheibe, hinter der die
  Bokeh-Stadt liegt — der Look entsteht dadurch, was das Glas **bricht**, nicht durch Malen
  auf dem Glas (Verbot bleibt).
- **Ein „Schaufenster" pro Screen:** die eine Hero-Card = `GlassLevel.tinted(coupleTint.blend)`.
  Das einzige Content-Glas. Ihr farbiger Glow-Schatten ist der eine erlaubte farbige Schatten
  (Charta-Regel existiert schon).
- **Sonst: kein Glas.** `GlassLevel.surface` für Standard-Karten entfällt.

### 4.3 Samt-Karten (der neue Default)

Content-Karten werden **opak**: `Velvet.card`-Füllung, `Radius.card`, `Velvet.seam`-Haarlinie,
neutrale `Elevation.resting`. Drei Gewinne: (1) Text-Kontrast ist deterministisch — kein
Bokeh-Hotspot frisst je wieder in die 4,5:1; (2) Reduce Transparency ist fast ein No-Op,
weil die App schon opak ist; (3) das seltene Glas (Dock, Schaufenster) wirkt endlich wie
ein Ereignis. Innenflächen: `Velvet.pile`, wie gehabt matt-in-matt, nie Material-in-Material.

### 4.4 Signatur-Elemente

- **Der Neon-Unterstrich (die Röhre):** Unter jedem `marquee`-Titel eine 3-pt-Kapsel,
  Breite = Textbreite × 0,6, linksbündig. Füllung `neonGas(blend)`, 1-pt-Kern-Highlight
  `neonCore(blend)` obenauf, Halo `neonHalo` radius 10. Er ist DER Sektionsmarker der App
  und ersetzt jede Icon-Dekoration neben Überschriften.
- **Die Reflexkante:** Samt-Karten tragen oben eine 1-pt-Innenkante in
  `coupleTint.blend @ 0.16` (statt Weiß) — der Widerschein der Leuchtreklame über der Bar.
  Die 10-Uhr-Lichtlogik bleibt (Kante oben-links hell, `Elevation`-Schatten unten-rechts);
  nur die **Farbe** des Lichts gehört jetzt dem Paar.
- **Doppelknoten-Divider:** Wo heute Trennlinien stehen: eine Haarlinie, die in der Mitte zu
  zwei nebeneinanderliegenden 4-pt-Punkten in `primary`/`secondary` verdichtet — das Duett
  als Interpunktion, subtiler als jedes Herz.

---

## 5. Motion-Signatur

Drei benannte Bewegungen (neue Kurven werden gemäß Gebot 11 in `Theme.Motion` benannt), plus
ein hartes Gesetz. Alle Parameter sind Startwerte für die Token-Definition.

**Gesetz zuerst — das Flacker-Verbot:** Eine echte Neonröhre flackert nur, wenn sie stirbt.
In dieser App existiert **kein einziges Flackern**: Jede Leuchtdichte-Änderung ist monoton
und dauert ≥ 350 ms; nie mehr als eine Helligkeits-Richtungsänderung pro Sekunde pro Element;
keine Frequenzen im WCAG-2.3.1-Risikoband (> 3 Blitze/s) — nicht als Grenzwert, sondern als
Null-Toleranz. Eine pure `NeonRules.flickerFree(timeline:)`-Funktion (Foundation-only,
LogicTest) prüft jede neue Licht-Choreografie in CI.

| Bewegung | Was passiert | Parameter | Reduce Motion |
|---|---|---|---|
| **Aufglimmen** | Leuchtelemente schalten nicht an, sie werden warm: Kern-Opacity 0 → 1, Halo-Radius 4 → 12, Halo-Opacity läuft dem Kern 80 ms hinterher (Gas zündet nach dem Draht). | `Theme.Motion.arrive` (spring 0.5/0.8) treibt einen `glowIntensity`-Wert; Gesamtdauer ≈ 600 ms, monoton (kein Overshoot in der Leuchtdichte — Federn nur auf Geometrie). | Element erscheint **fertig leuchtend** — ein Gemälde einer brennenden Röhre, kein Ramp. |
| **Lichtspur** | Bewegte Auswahl (Segment-Wechsel, Toggle-Knopf, Fokus-Ring) zieht eine nachziehende Spur: eine Kapsel in `neonGas @ 0.30 → 0`, gestreckt entlang des Wegs, Zerfall 140 ms nach Ankunft. | Träger-Animation `Theme.Motion.settle`; Spur-Zerfall als neue benannte Kurve `Motion.trail` = `easeOut(0.14)`. | Keine Spur; Auswahl wechselt als Crossfade (Opacity-Step), Position springt. |
| **Nachleuchten** | Jeder Tap auf ein leuchtfähiges Control lässt den Halo 400 ms nachglühen und abklingen — Feedback im selben Frame (Gebot 14), Wärme statt Pop. | Halo-Opacity +0,10 im Tap-Frame, Zerfall `Motion.trail`-artig über 400 ms; gekoppelt an `Haptics.tap()`. | Einmaliger stiller Opacity-Step (an/aus), kein Zerfalls-Verlauf. |

Ambient bleibt eines: die Bokeh-Stadt atmet in Gegenphase — Röhre-A-Scheiben und
Röhre-B-Scheiben schwellen abwechselnd über `Motion.drift(9)` (±8 % Opacity). Zwei Lichter,
die einander antworten: die leiseste Form des Duetts. Gedrosselt wie heute (Reduce Motion,
Low Power, Hintergrund → Standbild).

---

## 6. Die NATIVE iOS-26-TabView

Die `LiquidTabBar` fällt ersatzlos; `MainTabView` wird eine echte `TabView` mit
`Tab`-Buildern. **Man stylt die native Bar nicht — man stylt die Welt, die sie bricht.**
Innerhalb der nativen Grenzen prägt Neon-Duett die Bar so:

- **Tint = Mischlicht:** `.tint(coupleTint.blend)` — die Systemauswahl färbt Symbol + Label
  im gemeinsamen Neon. Mehr Farbeingriff braucht es nicht; das System sichert selbst die
  Lesbarkeit auf dem Glas.
- **Der Untergrund ist der Look:** Direkt unter der Bar-Zone liegt der dichteste Teil der
  Bokeh-Stadt (zwei Lichtscheiben parken dort dauerhaft). Das native Glas verflüssigt sie
  beim Scrollen — die beschlagene Scheibe entsteht gratis und systemecht.
- **`tabBarMinimizeBehavior(.onScrollDown)`:** Die Bar duckt sich beim Lesen weg wie eine
  Reklame, die dimmt, wenn man sich ins Gespräch lehnt; beim Hochscrollen glimmt sie zurück
  (das Wieder-Erscheinen ist das eine systemgetriebene „Aufglimmen", das wir geschenkt
  bekommen).
- **`tabViewBottomAccessory` = die Anwesenheits-Leiste:** eine schmale native Accessory-Zeile
  „Lena ist da" in `Typo.warm`, mit 2-pt-Röhrchen in der Partnerfarbe als führender Glyphe
  (statt Punkt-Badge). Sie kollabiert systemkonform in die minimierte Bar. Der heutige
  abgesetzte „?"-Hilfe-Button zieht in die Toolbar der Screens um (natives Placement).
- **Symbole:** unverändert SF Symbols mit outline/fill-Paar; `.symbolEffect(.bounce,
  options: .nonRepeating)` beim Aktivieren bleibt — native Geste, kein Eigenbau-Wiggle.
- **Badges:** native `.badge(count)` in Systemrot bleiben Systemrot — Apple-Nativität schlägt
  hier Farbwunsch; Anwesenheit läuft ohnehin über das Accessory, Zähler sind selten.
- **AX/Verhalten gratis:** Icon-only bei AX-Größen, Keyboard-Shortcuts, Re-Tap-to-Top,
  Reduce Transparency — alles Systemverhalten; die drei Spezial-Codepfade der alten Bar
  (Keyboard-Ausweichen, AX5-Breitenvertrag, Scroll-Walk) werden gelöscht, nicht portiert.

---

## 7. Logo-Konzept: „Das offene Herz aus zwei Röhren"

**Motiv:** Zwei Neonröhren, je eine Herzhälfte — Röhre A zeichnet den linken Bogen, Röhre B
den rechten. Sie berühren sich **nie**: an der Herzbucht oben und an der Spitze unten bleibt
je eine Lücke von genau einer Strichbreite. Geschlossen wird die Form allein vom Licht — an
beiden Lücken überlappen die Halos und mischen sich zu `blend`. *Das Herz ist nie
gezeichnet vollständig; erst das Leuchten der beiden macht es ganz.* Das ist in einer Zeile
erzählbar, als Silhouette einzigartig und bei 29 pt noch lesbar.

**Geometrie:** Icon-Kante = 1024. Herz in stehender Achse, Breite 58 % der Kante, optisches
Zentrum 4 % über Mitte. Strichbreite = 1/14 der Kante, Röhren als Kapsel-Strokes mit runden
Enden; Lückenmaß = Strichbreite. Keine Neigung, keine Perspektive — frontal wie ein Schild.

**Die 4 Ebenen** (prozedural in `GenerateIcon.swift`, gerendert pro Variante wie heute):

1. **Samt-Grund:** Radialer Verlauf aus den drei `bg`-Hexwerten der `AppIconKit`-Variante
   (dunkelste Ecke unten), plus Vignette −12 % an den Kanten. Die bestehenden 10 Paletten
   (classic, sunset, midnight, mint, rose, ocean, gold, lavender, blossom, aurora) bleiben
   unverändert die Daten-Quelle.
2. **Bokeh-Stadt:** 6 unscharfe Kreise (Radius 6–14 %, Opacity 0,06–0,12) aus `bg[2]` und
   `heart`-Farbe, seeded pro Variante (deterministisch, CI-reproduzierbar) — die Stadt hinter
   der Scheibe, pro Variante ein anderes Viertel.
3. **Die Scheibe:** Ein diagonales Reflexband (weiß @ 0,05, Breite 22 %, 24° Neigung) über
   der unteren Ebenen-Hälfte + hauchdünner Kanten-Reflex am Icon-Rand — das Fensterglas,
   angedeutet statt gemalt, damit die iOS-26-Glas-Varianten (s. u.) nicht doppeln.
4. **Das Neon-Duett:** Röhre A = `neonCore(heart)` als Kern-Stroke auf `heart` als
   Gas-Stroke (Kern 40 % der Strichbreite); Röhre B = dieselbe Konstruktion in der
   abgeleiteten Duett-Farbe `duet(heart)` = Hue +36°, Sättigung −12 % (pure Funktion, damit
   jede der 9 Varianten automatisch ein Zweiklang wird). An beiden Lücken je ein
   Misch-Glow-Punkt (`blend` der beiden, Opacity 0,5, Blur 3 % der Kante).

**Funktion über die Varianten:** Ebene 1+2 nehmen die Varianten-Palette, Ebene 3 ist
konstant, Ebene 4 leitet beide Röhrenfarben aus dem einen `heart`-Hex ab — eine Variante =
ein Hex-Tripel + ein Herz-Hex, exakt die heutige Datenstruktur, kein neues Asset-Format.
**iOS-Erscheinungsbilder:** Dark = identisch (die App ist die Nacht); Tinted/Clear = nur
Ebene 4 als Mono-Strokes auf transparentem Grund — das offene Herz bleibt auch einfarbig
unverwechselbar. In-App-Preview (`IconVariantPreview`) zeichnet dieselben 4 Ebenen live nach,
Repo bleibt binärfrei.

---

## 8. Screen-Blueprints

### 8.1 Home (DashboardView)

1. Kein Nav-Bar-Titel: oben links das Marquee-Schild „EUER ABEND" (`Typo.marquee` +
   Neon-Unterstrich in `blend`) — tageszeitabhängig via `DayPhase` („EUER MORGEN" etc.).
2. Rechts daneben, klein: der Anwesenheits-Doppelpunkt — zwei 6-pt-Röhrenpunkte, der eigene
   leuchtet immer, der des Partners glimmt bei Aktivität auf (Aufglimmen, nie Blink).
3. Hero-Slot = **das Schaufenster:** die eine `tinted`-Glass-Card (Tagesfrage / Reveal-Termin
   / Check-in — Priorisierung wie heute `DashboardPriority`), farbiger Glow-Schatten erlaubt.
4. Darunter Samt-Karten (`Velvet.card`, opak) im heutigen Karten-Budget: Momente, Rituale,
   Spiele — jede mit Reflexkante in `blend @ 0.16`, Titel in `Typo.title`, kein Glas.
5. Sektionen trennt der Doppelknoten-Divider statt Zwischenüberschriften, wo möglich.
6. Streak-Zeile: „137 gemeinsame Tage" in `Typo.warm` + Zahl in `Typo.number` — Biografie,
   kein Spielstand (Gebot 15), ohne Glow.
7. Herz-Coda unten: das offene Logo-Herz klein (24 pt), statisch; tippt man es, Nachleuchten
   + Haptik — der leise Gruß, keine Feier.
8. Bokeh-Stadt: dichteste Scheiben hinter Hero und Dock-Zone, unter den Samtkarten fast
   schwarz — Karten definieren ihre Umgebung nicht mit.
9. Leerer Zustand (frisch gepairt): nur das Schaufenster + ein Satz „Stellt euch die erste
   Frage." mit Primär-Button — eine Bar vor der Eröffnung, nicht ein leeres Regal.

### 8.2 Chat

1. Kopf: Partnername in `Typo.warm`, darunter `Typo.caption`-Status; KEIN Marquee — der Chat
   ist das Gespräch an der Bar, die Leuchtschrift hängt draußen.
2. Nachrichtenliste auf purem `Velvet.ink`-Grund, Bokeh auf `blobIntensity 0.4` gedimmt —
   Lesbarkeit vor Atmosphäre.
3. Eigene Bubbles: `Velvet.card` mit 1-pt-Kante in `neonGas(eigene Farbe) @ 0.5`; Partner-
   Bubbles: Kante in Partnerfarbe. **Füllungen bleiben Samt** — Farbe sitzt in der Kante,
   dadurch bleibt jeder Text auf identischem Grund bei vollem Kontrast.
4. Neue eingehende Nachricht: Kanten-Aufglimmen (600 ms) statt Einflieg-Pop; Reduce Motion:
   erscheint fertig.
5. `voice`-Momente (Briefe, Siegel) unverändert Serif — auf Samt wirken sie wie Handschrift
   unter der Tischlampe; Wachs-Siegel wechselt von Gold auf `brass`.
6. Composer: die eine Chrome-Glas-Kapsel des Screens (beschlagene Scheibe unten), Senden-
   Button trägt Nachleuchten.
7. Tippt der Partner, pulst der Doppelknoten-Divider über dem Composer in seiner Farbe
   (drift-Atmung, kein Blinken).
8. Datums-Trenner: `Typo.caption`-Versalien mittig im Doppelknoten-Divider — „GESTERN ABEND".
9. Fehlerzustand: Samt-StateCard mit Ausweg-Satz (Gebot 5); nie ein leerer Verlauf.

### 8.3 Spielen-Hub (PlayHubView)

1. Marquee-Schild „SPIELBAR" mit Neon-Unterstrich — die Bar in der Bar, der eine Ort, wo die
   Leuchtschrift zwinkern darf (einmaliges Aufglimmen beim Betreten, danach Ruhe).
2. „Du bist dran"-Reihe zuoberst als Schaufenster (`tinted`-Card): wartende Züge mit
   Partner-Avatar, Zug-Zahl in `Typo.number`.
3. Spiel-Kacheln als Samt-Karten im Grid (`hubTileMin`-Raster bleibt): SF-Symbol in
   `neonGas(blend)`, Titel `Typo.title`, letzte-Runde-Zeile `Typo.caption`.
4. Auswahl einer Kachel: Lichtspur vom Kachelrand zum aufgehenden Sheet (Reduce Motion:
   Crossfade) — Navigation bleibt `settle`, nie `playful`.
5. Serien/Rekorde sprechen Biografie: „Ihr spielt seit 9 Wochen jeden Sonntag" in
   `Typo.warm` — keine Flammen, kein Rot.
6. Sieg-Moment im Spiel: EINE Feier — das offene Herz schließt sich für 1,5 s per
   Licht-Brücke an beiden Lücken (Misch-Glow schwillt), `brass`-Medaille, dann Ruhe;
   `epic` bleibt Monats-Ereignissen vorbehalten (Gebot 4).
7. Badge „wartet auf dich" an Kacheln: 2-pt-Röhrchen an der Kachel-Oberkante in
   Partnerfarbe, glimmt einmal beim Erscheinen — kein Zähler-Punkt.
8. Leerer Zustand: dunkle Spielkacheln („Röhren aus") mit einem Satz + Verb: „Fordert euch.
   Wählt ein Spiel." — die Einladung ist die Handlung.

---

## 9. First-Launch-Kino: „Zwei Schilder" (45–60 s)

Prozedural wie die bestehende Kinematik (TimelineView + stoppbare Haptik-Partitur aus
`CinematicIntroView` wird wiederverwendet), Skip ab Szene 2 sichtbar, VoiceOver erhält pro
Szene eine Ansage, Reduce Motion s. u.

1. **Die Wahl (0 s, hält an):** Schwarzer Samt. Zwei dunkle Glasschilder hängen
   nebeneinander: „DEUTSCH" / „ENGLISH" (`Typo.marquee`, unlit: `textTertiary`). Kein Timer
   — die Szene wartet. Berührt man eines, **glimmt es auf** (600 ms, Haptik: ein warmer
   Continuous-Swell), das andere bleibt höflich dunkel und sinkt ins Schwarz. Die Sprachwahl
   ist die erste Berührung der App und zugleich die Lehrstunde ihrer Physik: Berühren macht
   Licht.
2. **Das Fenster (bis ~12 s):** Kamera-Parallaxe zieht zurück — das gewählte Schild hängt in
   einem Fenster; hinter der Scheibe erwacht die Bokeh-Stadt Scheibe für Scheibe (gestaffelte
   Aufglimm-Kaskade, je ≥ 350 ms, nie synchron).
3. **Röhre A (bis ~20 s):** Am linken Rand zündet eine rosé Röhre (Fallback-Farbe), summt
   links im Stereo-Bild (SoundEngine-Synth), pulst im eigenen langsamen Herzschlag-Haptik-
   Muster.
4. **Röhre B (bis ~28 s):** Rechts antwortet die violette Röhre — eigener Ton, eigener Puls,
   Gegenphase. Zwei Lichter, die einander noch nicht kennen.
5. **Die Zeichnung (bis ~40 s):** Beide Röhren biegen sich aufeinander zu und zeichnen mit
   Lichtspur je ihre Herzhälfte. Die Lücken bleiben. Die Halos berühren sich zuerst — an der
   Berührung entsteht sichtbar die Mischfarbe.
6. **Das Schild (bis ~50 s):** Unter dem offenen Herzen glimmt Buchstabe für Buchstabe
   „SOOODREAMY" auf (Marquee, monotone Kaskade, ausdrücklich kein Buchstaben-Flackern —
   der Klischee-Moment wird verweigert). Haptik: das Pairing-Motiv, einmal, auf beiden
   Kanälen — der einzige laute Moment.
7. **Der Eintritt (bis ~58 s):** Das Schild schrumpft an die Position des Dashboard-Marquees,
   die Bokeh-Stadt sortiert sich in die Home-Anordnung, die native Glas-TabView schiebt sich
   von unten ein: Das Intro war die App. Eine Zeile Copy: „Zwei Lichter. Eine Stadt. Eure
   Nacht." — dann der Primär-Button.

**Reduce Motion:** Sieben Standbilder (alles bereits leuchtend) mit Crossfades; Haptik-Puls
und Ansagen tragen die Dramaturgie (Gebot 13). **Sprachwahl bleibt interaktiv** — sie ist
Funktion, nicht Schmuck.

---

## 10. Risiken & A11y

- **Glow vs. Lesbarkeit:** Größtes Risiko der Richtung. Antwort ist §2.3 als *Maschinerie*,
  nicht als Absicht: `neonHaloVerdict` rechnet pro Paar-Palette, LogicTests pinnen den Worst
  Case (Gold/Mint-Halo), Glow-Budget 2/Viewport, Fließtext glüht nie. Wenn ein Halo den
  Verdict nicht schafft, verliert der Halo, nie der Text.
- **Epilepsie/Flacker:** Null-Toleranz statt Grenzwert (§5): monotone Ramps ≥ 350 ms, keine
  Blink-Zyklen, `NeonRules.flickerFree` in CI. Das kulturell erwartete „Neonschild-Flackern"
  ist bewusst der eine Reiz, den diese Richtung **verweigert** — das ist ihre Disziplin.
- **Reduce Transparency:** Strukturvorteil: Standard-Karten sind opaker Samt, betroffen sind
  nur Dock + Schaufenster (System tauscht sein Glas selbst) und die Bokeh-Stadt — die unter
  Reduce Transparency zu einem statischen, dunkleren Samt-Verlauf wird (`MotionGate.scrim`-
  Mechanik existiert).
- **AX5:** Kondensierte Versalien sind die Achillesferse — deshalb der harte Marquee-Fallback
  (Normalbreite, gemischte Schreibung) ab AX-Größen, gepinnt über den bestehenden
  `paired-ax5-de.png`-CI-Shot. Neon-Unterstrich und Reflexkante sind rein dekorativ und
  skalieren nicht mit; Hit-Targets, Grid-Kollaps und `prefersVerticalLayout` bleiben
  unangetastet. Native TabView erledigt das Dock-AX-Kapitel komplett systemseitig.
- **Kitsch-Grenze (Bann-Liste, Review-fähig):** kein Grid-Horizont, kein Retro-Chrome, keine
  Scanlines, keine Schreibschrift-„Neon-Cursive", keine Palmen/Sonnenuntergänge, kein
  Lens-Flare, max. EIN Marquee pro Screen, Bokeh ≤ 7 Scheiben, Glow-Budget 2. Prüffrage im
  Review: „Sieht das nach Miami 1986 aus oder nach einer Bar, in die man heute Abend gehen
  würde?" Im Zweifel: Licht raus.
- **Dark-only bleibt Gesetz:** Neon-Duett verstärkt die Marken-Entscheidung sogar — es gibt
  keine Stadt-Nacht bei Tageslicht. Kontrast wird künftig gegen `Velvet.ink` `#0A090F`
  gerechnet; die Umstellung der Referenz in `CouplePaletteRules` ist EIN Konstanten-Wechsel
  plus Test-Update, alle Verdicts rechnen weiter.
- **OLED/Batterie:** Near-Black-Flächen und gefrorene Bokeh unter Low Power (Drossel-Pfad
  existiert) machen die Richtung sparsamer als die heutige Voll-Aurora.
- **Ehrliche Kosten:** Der Wechsel `surface`-Glas → Samt-Karten berührt viele Views (der
  `glassCard()`-Modifier ist die eine Umbaustelle) und die Bubble-Kanten-Sprache im Chat ist
  neu zu bauen; dafür entfallen die drei Sonderpfade der alten Tab-Bar vollständig.

---

*Designer D — „Neon-Duett": Die App besitzt kein eigenes Licht. Alles, was leuchtet, sind
die beiden.*
