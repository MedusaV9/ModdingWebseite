# Stilrichtung „Gezeitenbecken" — Designer C

> Liquid Glass, wörtlich genommen: Die App ist ein nächtliches Gezeitenbecken.
> Zwei Strömungen (ihr beide) mischen sich zu einem gemeinsamen Wasser; Inhalte
> liegen als Kiesel und Perlen unter klarem Wasser; UI-Ebenen sind Wassertiefen.
> Alles prozedural (Canvas/TimelineView, Metal-frei), echtes System-Glass als
> oberste Wasseroberfläche.

---

## 1. Manifest

Liquid Glass ist bei Apple eine Material-Metapher — wir nehmen sie beim Wort und
bauen den Ort, aus dem das Material kommt: ein stilles, nächtliches Gezeitenbecken,
in dem das Licht von oben einfällt und sich am Grund als Kaustik bricht. Jede
UI-Ebene ist eine Wassertiefe: das System-Glass der Chrome-Elemente ist die
Wasseroberfläche, Content-Karten sind klare Sichtfenster ins Wasser, ihre Inhalte
sind Kiesel und Perlen auf dem Grund. Die zwei Paar-Farben sind zwei Strömungen,
die im Becken aufeinandertreffen; wo sie sich mischen, entsteht die Konfluenz —
die gemeinsame Farbe, die jede Feier, jeden Titel und die Tab-Auswahl trägt.
Bewegung bedeutet hier nie Dekoration, sondern Physik: Berührungen erzeugen
Wellenringe, Ankommendes taucht auf, Tiefe erzeugt Parallaxe — und unter Reduce
Motion wird das Becken ein Gemälde, nie ein schwarzes Loch. Wasser darf alles —
außer Lesbarkeit kosten: Der 4,5:1-Boden der Charta gilt ohne Ausnahme, Kaustiken
sind gedeckelt und Fließtext steht immer auf stillem Wasser.

---

## 2. Farbsystem

### 2.1 Tiefen-Skala (Hintergrund, Oberfläche → Grund)

Ersetzt `Theme.bgTop`/`Theme.bgBottom` (das Violett weicht einem tiefen
Petrol-Wasser). Der Screen-Hintergrund ist ein Vertikal-Verlauf T0 → T3; T4 ist
die neue Nacht-Tinte (Scrim-Ink, `onBlend`-Dunkelwert).

| Token | Hex | Rolle | Weiß-Kontrast (gemessen) |
|---|---|---|---|
| `T0 lichtfilm` | `#135664` | NUR oberster Gradient-Stop / Lichteinfall an der Bildoberkante — nie alleiniger Textgrund | ≈ 8,3:1 |
| `T1 flachwasser` | `#0D3E4C` | obere Screen-Zone, „nah an der Oberfläche"-Bereiche | ≈ 11:1 |
| `T2 freiwasser` | `#082B38` | Haupt-Screengrund (Referenzgrund aller Kontrastmessungen) | ≈ 14,9:1 |
| `T3 tiefwasser` | `#05202B` | untere Screen-Zone, tiefe Bereiche (Spielen-Hub unten) | ≈ 16,8:1 |
| `T4 grund` | `#031319` | Nacht-Tinte: Scrims, `onBlend`/`onGradient`-Dunkelwert, Icon-Tiefe | ≈ 18,9:1 |

### 2.2 Biolumineszenz-Akzente (Kontrast gegen `T2 freiwasser`)

| Token | Hex | Rolle | Kontrast auf T2 |
|---|---|---|---|
| `perlmutt` | `#F2F7F4` | Text primär (ersetzt hartes Weiß; Sekundär/Tertiär bleiben 0.78 / 0.64 Opacity davon) | ≈ 13,7:1 |
| `algenlicht` | `#63F2C5` | Erfolg, „lebendig"-Bestätigungen, positives Leuchten (Nachfolger von `mint`) | ≈ 10,6:1 |
| `quallenblau` | `#7BC8F5` | Information, Links, sekundäre Akzente (Nachfolger von `blue`) | ≈ 8,1:1 |
| `bernstein` | `#FFC96B` | Zeremonien-Gold: Reveal, Level-Up, Siegel (Bernstein = Meeres-Gold; `Theme.gold` bleibt hex-adressierbar für `onWax`) | ≈ 9,8:1 |
| `korallenglut` | `#FF8F79` | die warme Verletzlichkeits-Farbe (Energie-Batterie, „läuft leer") — bewusst NICHT paar-farben-nah, Gebot aus Dossier 32 bleibt | ≈ 6,7:1 |

Alle fünf Akzente liegen mit Marge über dem 4,5:1-Boden — auch auf T0, dem
hellsten möglichen Grund.

### 2.3 CoupleTint-Integration: zwei Strömungen

- `coupleTint.primary` / `.secondary` = **Strömung A / Strömung B**. Sie ersetzen
  die Aurora-Blobs 1:1: zwei gebogene Strömungsbänder im Becken-Canvas, gerendert
  mit denselben festen Deckwerten wie heute (0.30 / 0.26 — `AuroraBlobsView`
  bleibt die Referenz-Implementierung, nur die Geometrie wird Band statt Blob).
- `coupleTint.blend` = **Konfluenz** — sie entsteht sichtbar dort, wo sich die
  Bänder überlagern (radiale Verläufe addieren sich optisch von selbst, kein
  neuer Blend-Mode nötig). Konfluenz bleibt DIE Signatur: `.brandTitle`,
  Tab-Auswahl-Tint, Meilensteine, die eine tinted Hero-Card.
- Die gesamte `CouplePaletteRules`-Maschinerie (Verdicts, Scrims, `onLight`,
  `onWax`, `accentOnLight`-Leiter) bleibt unangetastet — nur die
  Referenz-Hintergründe werden von `#17062A` auf `T4/T2` umgepinnt. Da die
  T-Skala DUNKLER ist als das heutige Violett, steigen alle Ratios; die
  LogicTests werden einmalig neu gebaselined, kein Verdict kippt nach unten.

### 2.4 Kontrastregeln — „Wasser zahlt nie mit Lesbarkeit"

1. **4,5:1 ohne Ausnahme** (Charta-Gesetz): jede Textfarbe wird via
   `CouplePaletteRules` gegen den hellsten Grund geprüft, auf dem sie stehen
   kann — für frei stehenden Text ist das `T0 lichtfilm` (weiß dort ≈ 8,3:1,
   also Marge).
2. **Kaustik-Deckel:** Kaustik-Bänder global ≤ 0.12 Opacity; unter Karten
   ohnehin irrelevant (das Karten-Glas liegt ÜBER dem Canvas und wäscht sie
   aus). Frei stehender Text (Section-Header, Nameplates) bekommt eine
   Stillwasser-Zone: Der Becken-Canvas maskiert Kaustik unter Textrahmen ganz
   aus (ein rechteckiges Clip-Out pro Header, kein Blur).
3. **Fließtext steht nie direkt auf Kaustik** — Body-Copy existiert nur auf
   Karten (`GlassLevel.surface`) oder Sediment-Fills, nie nackt auf dem Becken.
4. Strömungsbänder tragen nie Text; sie sind Hintergrund-Physik wie heute die
   Aurora.

---

## 3. Typografie

Systemfonts only, die bestehenden `Typo`-Rollen bleiben die einzige Wahrheit —
das Gezeitenbecken ändert nicht die Rollen, sondern ihre Erzählung:

| Rolle | Definition (unverändert semantisch, Dynamic Type) | Erzählung im Becken |
|---|---|---|
| `hero` | `.largeTitle` rounded **heavy**, max. 1×/Screen | der große Findling — vom Wasser rund geschliffen |
| `title` | `.title3` rounded bold | Kiesel-Überschriften |
| `body` | `.body` rounded | ruhiges Wasser, Perlmutt |
| `label` | `.subheadline` rounded semibold | Uferbeschriftung |
| `caption` | `.caption` rounded semibold | Sedimentschrift, immer ≥ `textTertiary`-Kontrast |
| `number` | `.title2` rounded bold `monospacedDigit` | **Pegelstände** — gemeinsame Tage, Punktestände; Ziffern wandern nie |
| `voice` | `.title3` serif italic | **Flaschenpost** — ausschließlich Worte, die die Partner selbst geschrieben haben (Wochen-Zitat, Journal, Kapseln) |

Regeln: Rounded = „die App spricht", Serif = „von euch geschrieben" (bleibt).
Kein Verlauf auf Text — nirgends (Charta-Gesetz); Titel tragen `.brandTitle` in
Vollton-Konfluenz. `Font.scaled` nur für Hero-Zahlen und dekorative Glyphen.

---

## 4. Form & Material

### 4.1 Radii — die Kiesel-Sprache

Die drei Token bleiben (`pane 28 / card 22 / control 14`, Chips = `Capsule()`),
konzentrisch via `Radius.concentric`. Die Kiesel-Sprache entsteht nicht durch
neue Zahlen, sondern durch Konsequenz: **jede interaktive Fläche ist ein
`RoundedRectangle(style: .continuous)` oder eine Kapsel** — die weiche
Superellipse liest das Auge als wassergeschliffen. Organische, asymmetrische
Kiesel-Konturen gibt es NUR dekorativ (Empty-States, Logo, Illustrationen im
Canvas), nie als Hit-Target — Vorhersagbarkeit schlägt Poesie.

### 4.2 Wo echtes System-Liquid-Glass, wo Tiefen-Karten

| Ebene | Material | Einsatz |
|---|---|---|
| **Wasseroberfläche** | echtes `glassEffect` (`GlassLevel.chrome`) | native TabView-Bar + Bottom-Accessory, Toolbars, Composer/Input-Bars, runde Buttons, Sheet-Chrome. Es wird NICHTS darauf gemalt — das System rendert Refraktion selbst (Verbotsregel bleibt). |
| **Sichtfenster** | `GlassLevel.surface` | Content-Cards: das Glas IST das klare Wasser über dem Karteninhalt. Genau EINE `GlassLevel.tinted(Konfluenz)`-Hero pro Screen — **die Perle**. |
| **Tiefen-Karten (Sediment)** | matte Fills | alles IN Karten: `innerFill`/`hairline` werden auf Perlmutt-Basis umgestellt (`perlmutt.opacity(0.05)` / `0.12`) — Glas-auf-Glas bleibt verboten. |
| **Der Grund** | Becken-Canvas | Tiefenverlauf + Strömungen + Kaustik + Meeresschnee, eine Canvas-Pass-Schicht, ersetzt `DreamyBackground` mit identischer Drossel-Logik (Reduce Motion / Szene inaktiv / Low Power ⇒ Standbild). |

### 4.3 Signatur-Elemente

- **Wellenring (DIE Signatur):** jede primäre Berührung antwortet mit 2
  konzentrischen Ringen am Touch-Punkt (Parameter in §5). Ein Element, überall
  wiedererkennbar — vom Tab-Wechsel bis zum Siegelbruch.
- **Luftblasen-Badges:** ungelesene Zähler sind kleine Blasen (Kapsel-Badge mit
  einem Specular-Punkt oben links, 10-Uhr-Licht-Regel); beim ersten Erscheinen
  steigt die Blase einmal 6 pt auf und pendelt aus (Reduce Motion: erscheint
  still).
- **Wasserlinien:** Trenner sind keine grauen Hairlines, sondern die bestehende
  `hairline` mit einem 1-pt-Lichtfilm-Schimmer (`T0`, 0.2 Opacity) darüber —
  eine Zeile Code, großer Wiedererkennungswert.
- **Elevation = Wassertiefe:** die drei Schatten-Stufen (`resting/raised/
  floating`) bleiben wörtlich erhalten — je näher an der Oberfläche, desto
  weicher der Schatten. Das 10-Uhr-Licht wird zum Mondlicht über dem Becken.

---

## 5. Motion-Signatur

Drei Bewegungen, alle über die bestehenden `Theme.Motion`-Token bzw. genau EINE
neue benannte Kurve (`Motion.ripple`), niemals Freihand:

1. **Wellenausbreitung** (Berührung → Antwort): 2 Ringe ab Touch-Punkt,
   Radius 0 → 88 pt in 0,62 s (`Motion.ripple = easeOut(0.62)`, im Theme
   benannt), Linienstärke 2 → 0,5 pt, Opacity 0,35 → 0, Ring 2 startet 0,12 s
   versetzt. Gezeichnet in einem screenweiten, hit-test-freien Canvas-Overlay —
   ein Overlay pro Screen, nicht pro Button. Haptik: der bestehende leise `tap`.
2. **Auftauchen** (Ankommen von Inhalt): Karte startet bei Opacity 0,
   `offset(y: +12)`, `scale 0.97`, dazu 2–3 kleine Blasen, die 20 pt aufsteigen
   und zerplatzen; Kurve = bestehendes `Motion.arrive` (spring 0.5/0.8). Einmal
   pro Karte und Sichtung, nie beim Zurück-Scrollen erneut.
3. **Strömungs-Parallax** (Tiefe fühlbar machen): der Becken-Canvas koppelt an
   den Scroll-Offset — Kaustik-Schicht folgt mit Faktor 0,85, Strömungsbänder
   mit 0,92, Meeresschnee mit 0,80; zusätzlich ambienter Drift wie heute
   (`Motion.drift(9)`, TimelineView bei 12 Hz). Amplituden-Deckel: max. 8 pt
   Eigenbewegung, Periode nie unter 8 s (Seekrankheits-Regel, §10).

**Ruhe-Fassung (Reduce Motion, via `motionGate`):** das Becken wird ein
Gemälde — Canvas friert bei t = 0 ein (exakt das `StarFieldView`-Muster);
Wellenringe werden EIN statischer Glow-Puls, der einmal erscheint und ausblendet;
Auftauchen wird reiner Crossfade; Parallax aus, Blasen aus. Kein Pfad ist
„nichts" — jeder ist die leise Version (Gebot 13).

---

## 6. Die NATIVE TabView: die Bar als Wasseroberfläche

Die `LiquidTabBar` fällt; es kommt die echte iOS-26-`TabView` mit `Tab`-Builder.
Die Metapher trägt das nativ perfekt — die Bar ist wörtlich die Oberfläche des
Beckens, und wir malen **nichts** auf sie:

- **Material:** unangetastetes System-Glass. Der Becken-Canvas mit Kaustik und
  Strömungen liegt dahinter — die Bar bricht ihn von selbst (das ist der ganze
  Trick: Refraktion geschieht, wir liefern nur das Wasser darunter).
- **Tint:** `.tint(coupleTint.blend)` — die Auswahl leuchtet in Konfluenz. Der
  bestehende `MainTabView`-Tint-Mechanismus wandert 1:1 mit.
- **Abtauchen:** `.tabBarMinimizeBehavior(.onScrollDown)` — beim Hinabscrollen
  zieht sich die Oberfläche zusammen; wer in den Inhalt taucht, lässt die
  Oberfläche über sich. Konzept und System-API meinen hier dasselbe.
- **Bottom-Accessory = Treibholz:** `.tabViewBottomAccessory` trägt den
  Pulse-Schnellsender („Ich denk an dich") — der bisherige `PulseFan`-FAB des
  Dashboards wird damit von JEDEM Tab aus erreichbar und minimiert nativ mit
  der Bar zur Inline-Fassung. Ein echter Funktionsgewinn, kein Umbau-Zwang.
- **Badges = Luftblasen:** natives `.badge(count)` für Chat-Ungelesen und
  „Du bist dran" — System-Rendering, VoiceOver-Zählung inklusive (die
  bestehenden A11y-Labels ziehen um).
- **Tab-Wechsel-Antwort:** die Bar selbst bleibt System; der Wellenring feuert
  in der CONTENT-Ebene von der Unterkante aus (Signatur §4.3), dazu das
  bestehende `sensoryFeedback(.selection)`.
- **Scroll-Kante:** `scrollEdgeEffectStyle(.soft)` bleibt — Inhalt läuft weich
  unter die Oberfläche, keine harte Wasserkante.
- **iPad:** `.tabViewStyle(.sidebarAdaptable)`; der Handbuch-„?"-Button verliert
  seinen Sonderplatz neben der Bar und wandert als Toolbar-Item in die Screens.
- **Grenzen respektieren:** kein Selection-Lens-Nachbau, kein Wiggle-Easteregg
  in der Bar, keine eigene Icon-Skalierung — was die System-Bar nicht anbietet,
  bietet diese Richtung nicht an. Die Persönlichkeit lebt im Wasser darunter.

---

## 7. Logo-Konzept: „Konfluenz" (mehrschichtig, prozedural)

Vier Ebenen, gerendert wie bisher rein prozedural über `GenerateIcon.swift`
(AppIconKit); die Geometrie ist über alle Varianten konstant, NUR die
Paletten-Slots wechseln — die bestehende `Palette`-Struct (`bg / aurora / glow /
pane / caustic / rim`) wird ohne Feldänderung wiederverwendet:

| Ebene | Motiv | Geometrie | Paletten-Slot |
|---|---|---|---|
| 1 — Grund | Tiefenverlauf + Kiesel-Bokeh + Meeresschnee | 3-Stopp-Radialverlauf von unten, 40–60 weiche Partikel | `bg` (3 Stops) |
| 2 — Strömungen | zwei S-förmige Strömungsbänder, die von links oben und rechts oben aufeinander zulaufen | zwei Bezier-Bänder, Überlappungszone mittig-unten | `aurora` (Band A, Band B, Mischzone) |
| 3 — Kieselpaar + Perle | zwei rund geschliffene Kiesel, die sich aneinanderlehnen; der Negativraum zwischen ihnen formt ein Herz; in der Kerbe sitzt eine kleine Perle | zwei Superellipsen 12° / −8° geneigt, Perle = Kreis mit Specular-Punkt | `pane` (Kiesel-Verläufe), `glow` (Perlen-Glanz) |
| 4 — Wasseroberfläche | Glasfilm über allem: Specular-Lobe oben links (10-Uhr-Licht), EIN Wellenring um die Perle, Lichtpfütze unten | bestehende Gloss-Sweep-/Rim-Technik des 2.0-Icons | `caustic` (Lichtpfütze), `rim` (Ringlicht) |

**Funktion über die 9 Varianten:** Die Metapher absorbiert jede Palette als
anderes Gewässer — `sunset` = Abendrot-Lagune, `midnight` = Tiefsee, `mint` =
Lagune, `rose` = Korallenbecken, `ocean` = offenes Meer, `gold` = Bernsteinsee,
`lavender` = Dämmerungsbucht, `blossom` = Kirschblütenteich, `aurora` =
Polarmeer. Kieselpaar, Herz-Negativraum und Perle bleiben in jeder Variante
identisch lesbar (Familien-Regel des bestehenden Renderers). Der CI-Aufruf
(`swift ios/scripts/GenerateIcon.swift <out> <variant>`) und die
`WidgetStudio`-Paletten-Spiegelung funktionieren unverändert weiter.

---

## 8. Drei Screen-Blueprints

### 8.1 Home — „Das Becken"

1. Hintergrund: Becken-Canvas (T0→T3-Verlauf, Strömungsbänder in Paar-Farben,
   6–8 Kaustik-Bänder, Meeresschnee) — ersetzt `DreamyBackground` 1:1 samt
   Drossel-Logik (Reduce Motion / Szene / Low Power).
2. Header: die zwei Avatare als Kiesel am Beckenrand; die Strömungen laufen
   sichtbar hinter ihnen zusammen; „137 gemeinsame Tage" als Pegelstand
   (`Typo.number`, Perlmutt) — Biografie, kein Spielstand.
3. Tagesfrage = **die Perle**: die EINE tinted Hero-Card
   (`GlassLevel.tinted(Konfluenz)`); solange unbeantwortet, trägt sie einen
   leisen Perlglanz-Puls (unter Reduce Motion: einmalig, dann stehend).
4. „Während du weg warst" (MissedInbox) = **Angespült**: eine Strandgut-Reihe
   auf Sediment-Fill — Fundstücke, die die Flut gebracht hat.
5. Karten tauchen beim ersten Sichtbarwerden auf (Auftauchen, §5.2), maximal
   drei Karten + „mehr"-Falte wie heute — die Dramaturgie bleibt.
6. Strömungs-Parallax an den Scroll-Offset gekoppelt (§5.3).
7. Der Pulse-Sender wohnt jetzt im TabView-Accessory (§6) — der schwebende FAB
   entfällt ersatzlos; das Dashboard endet ruhiger.
8. Herz-Coda unten: das Herz antwortet auf Berührung mit einem Wellenring statt
   Partikelregen.
9. Fünf Zustände: leer = stilles Becken mit Einladung („Stellt euch die erste
   Frage"), offline = die Oberfläche friert ein + StateCard mit Ausweg.

### 8.2 Chat — „Der Kanal"

1. Nachrichtenliste = zwei Ufer: eigene Nachrichten rechts auf Sediment in
   Strömung-A-Tönung, Partner links in Strömung-B — matte Fills
   (`innerFill`-Familie), bewusst KEINE Glas-Bubbles (Glas-auf-Glas-Verbot;
   Lesbarkeit vor Effekt).
2. Tagestrenner = Wasserlinien (§4.3) mit dem Datum in `Typo.caption`.
3. Tippt-Indikator: drei kleine aufsteigende Luftblasen statt drei Punkte —
   gleiche Größe, gleiche Stelle, nur die Metapher wechselt.
4. Neue Nachricht kommt an = Auftauchen + Wellenring am Einschlagpunkt der
   Bubble; Haptik bleibt der leise `tap`.
5. Voice Notes: die Wellenform wird als konzentrische Ringsegmente um den
   Play-Button gelegt; Abspielen zieht einen Lichtring durch die Segmente.
6. Love Letters = **Flaschenpost**: der versiegelte Brief taucht als Silhouette
   auf, der Siegelbruch (LetterSeals) feuert den größten Wellenring des Screens
   — der eine Moment dieser View.
7. Composer: Chrome-Glas an der Unterkante = Wasseroberfläche; hebt sich mit
   der Tastatur (bestehende Keyboard-Choreografie bleibt).
8. Effekt-Nachrichten: Biolumineszenz-Schauer (Algenlicht-Partikel) statt
   Konfetti; Reduce Motion: ein stehender Glow um die Nachricht.
9. Fünf Zustände: leer = „Werft die erste Flaschenpost ein" mit Composer-Fokus
   als Handlung; Fehler nennt den Ausweg (Charta-Gebot 5).

### 8.3 Spielen-Hub — „Das Riff"

1. Tiefenzonen statt Sektionen: Täglich = Flachwasser (T1-Zone), Async/Live =
   Freiwasser (T2), Brett- & Duellspiele = Tiefe (T3) — der Becken-Canvas
   dunkelt mit dem Scroll-Offset nach unten ab (ein Farb-Lerp, kein Filter).
2. Hero-Card („heute empfohlen") = **Anglerlicht**: ein einzelnes
   Biolumineszenz-Leuchten (Algenlicht) zieht den Blick — die eine tinted
   Hero-Fläche des Screens.
3. Season-Row = **Gezeitenkalender**: eine Ebbe/Flut-Linie zeigt den
   Monatsfortschritt als Pegel, `Typo.number` für Stände.
4. Spielkarten = Kiesel-Grid: matte Sediment-Tiles im 2er-Grid
   (`hubTileMin`-adaptiv), Icon in der Akzentfarbe seiner Tiefenzone.
5. „Du bist dran"-Banner tragen Luftblasen-Badges; die Blase steigt beim
   Erscheinen einmal auf (§4.3).
6. Einklappen einer Gruppe = Absinken: die Karten sinken 8 pt und blenden aus
   (`Motion.settle`; Reduce Motion: reiner Fade).
7. „Zuletzt gespielt" = Treibgut-Reihe, horizontal scrollend auf Sediment.
8. Fünf Zustände: leer = „Taucht zusammen ab — sucht euch ein erstes Spiel aus"
   mit direktem Spielstart als Verb.

---

## 9. First-Launch-Kino: „Der erste Tropfen" (~55 s, 7 Szenen)

Baut auf der bestehenden `CinematicIntroView`-Architektur auf: prozedural, ein
TimelineView-Playhead, synthetisierter Sound + stoppbare Haptik-Partitur,
jederzeit überspringbar. Neu: die Sprachwahl ist Szene 0 und zugleich der
Auslöser des Films.

| Szene | Zeit | Bild / Ton / Haptik |
|---|---|---|
| 0 — Zwei Tropfen | 0:00–0:08 (wartet beliebig) | Fast-Schwarz (T4), kaum sichtbarer Raum. Zwei leuchtende Tropfen hängen nebeneinander: **„Deutsch"** / **„English"** (Perlmutt, je ≥ 4,5:1). Berühren lässt den gewählten Tropfen fallen. Kein Countdown — die Szene wartet. VoiceOver: beide Tropfen als Buttons fokussierbar, Wahl wird angesagt. |
| 1 — Der Einschlag | 0:08–0:16 | Der Tropfen trifft die unsichtbare Oberfläche: der erste Wellenring zeichnet die Wasseroberfläche ins Bild. Ein einzelner Transient (Haptik + Tropfen-Klang) — der erste Herzschlag der App. |
| 2 — Abtauchen | 0:16–0:26 | Die Kamera sinkt unter die Oberfläche: Vertikal-Parallax der Ebenen, Verlauf T0 → T2 baut sich auf, Meeresschnee beginnt zu treiben. Leises Aurora-Bett im Sound. |
| 3 — Zwei Strömungen | 0:26–0:36 | Von links und rechts fließen zwei Farbbänder aufeinander zu (neutrale Fallback-Paar-Farben — das echte Paar färbt sie nach dem Pairing um). Erste Berührung der Bänder: die Kaustiken zünden. Stereo: jedes Band summt auf seiner Seite. |
| 4 — Konfluenz | 0:36–0:44 | Die Bänder umschlingen sich; im Zentrum verdichtet sich eine Perle. Das `.pairing`-Haptik-Motiv + Sub-Swell — der einzige Moment, in dem beide Event-Kanäle gleichzeitig sprechen (Charta-Regel bleibt). |
| 5 — Die Perle wird App | 0:44–0:52 | Aus der Perle tauchen drei Karten-Silhouetten auf (Auftauchen-Motion), unten bildet sich die Glas-Oberfläche der Tab-Bar. Titel **„SoooDreamy"** in Konfluenz-Vollton (`.brandTitle`, kein Text-Verlauf). |
| 6 — Eintauchen | 0:52–0:58 | Button „Eintauchen" / „Dive in" taucht auf. Das Becken bleibt STEHEN und wird nahtlos der Onboarding-Hintergrund — kein Schnitt, die App war schon die ganze Zeit da. |

Reduce Motion: Standbild-Fassung — jede Szene ist ein Gemälde, Übergänge sind
Crossfades, die Partitur läuft weiter (der Film bleibt mit geschlossenen Augen
erlebbar: Ansagen + Haptik, Gebot 13). Skip beendet Sound und Haptik sofort
(bestehende Advanced-Player-Architektur).

---

## 10. Risiken & A11y

- **Seekrankheit (größtes Motion-Risiko dieser Richtung):** kontinuierliche
  Undulation ist verboten. Harte Deckel: Ambient-Amplitude ≤ 8 pt, Periode
  ≥ 8 s, keine Oszillation von CONTENT (nur der Hintergrund-Canvas driftet,
  Karten und Text liegen still), Wellenringe nur ereignisgetrieben. Parallax
  koppelt ausschließlich an Nutzer-Scroll (selbstverursachte Bewegung macht
  nicht seekrank). Reduce Motion friert alles via `motionGate` ein.
- **Reduce Transparency:** System-Glass tauscht sich selbst gegen opake Platten
  (Systemvertrag, wie heute). Handgemaltes Wasser ist UNSERE Pflicht: der
  Becken-Canvas degradiert zum flachen T2-Grund ohne Kaustik/Strömungen
  (analog `MotionGate.scrim`), Sediment-Fills sind matt und bleiben.
- **Performance der Wasser-Optik:** ein einziger Canvas-Pass pro Screen (wie
  `AuroraBlobsView` heute), 12-Hz-TimelineView-Deckel, Kaustik als 6–8
  Sinus-Bänder statt Pixel-Simulation, radiale Verläufe statt Blur-Filter,
  Freeze bei Szene-inaktiv/Low-Power. Kein Metal, keine Shader-Dateien, kein
  Offscreen-Rendering. Budget: der Becken-Canvas darf nicht teurer sein als die
  heutige Aurora + Sternfeld zusammen — sonst fliegt zuerst der Meeresschnee.
- **AX5:** Tiefenzonen-Grids kollabieren über die bestehende
  `AccessibilityBudget`-Schiene (Spalten sinken, bevor Labels zerspringen);
  Kaustik wird unter AX-Schriftgrößen zusätzlich global auf 0.06 gedeckelt,
  weil mehr Textfläche auf dem Becken liegt; die Stillwasser-Masken wachsen mit
  den Textrahmen automatisch mit. Native TabView-Badges und -Labels skalieren
  systemseitig — ein Risiko der alten Eigenbau-Bar verschwindet.
- **Farbfehlsichtigkeit:** die zwei Strömungen dürfen sich nie NUR im Farbton
  unterscheiden — Regel: ΔL ≥ 20 Helligkeitsabstand zwischen Band A und B (bei
  gleichen Paar-Farben erzwingt die bestehende Paletten-Ableitung ohnehin
  Distanz); Ufer-Zuordnung im Chat trägt zusätzlich die Ausrichtung
  (links/rechts) als redundanten Kanal.
- **Blau-Monotonie / emotionale Kälte:** Wasser kann kühl wirken — die warmen
  Gegengewichte (`bernstein`, `korallenglut`, die Paar-Farben selbst) sind
  fest verplant: Zeremonien sind Bernstein, die Perle ist Konfluenz, und die
  Strömungen tragen IMMER die Farben des Paares, nie ein Stock-Petrol.
- **Re-Pinning-Aufwand:** `CouplePaletteRules`-Referenzgrund und die
  LogicTest-Baselines müssen einmalig auf die T-Skala umgestellt werden (alle
  Ratios steigen, kein Verdict kippt — trotzdem ist es ein bewusster
  Test-Commit, kein Nebeneffekt). Die Ratchet-Zähler (`bare_white_opacity`
  usw.) bleiben unberührt, weil alle neuen Werte als Token in der UI-Schicht
  geboren werden.

---

## Anhang: Umsetzungs-Landkarte (Machbarkeit)

| Baustein | Ort | Aufwand |
|---|---|---|
| T-Skala + Akzente | `UI/Theme.swift` (Token-Tausch: `bgTop/bgBottom` → T-Verlauf, `mint/blue/gold/energyRed` → Nachfolger) | Token-Umbenennung + Re-Pinning |
| Becken-Canvas | neue `TidalPoolBackground` als Drop-in für `DreamyBackground` (gleiche Props: `showStars` → `showSnow`, `blobIntensity` → `causticIntensity`, gleiche Drosseln) | eine Datei, Aurora-Muster kopieren |
| Wellenring-Overlay | ein View-Modifier + Canvas-Overlay in der UI-Schicht, `Motion.ripple` als fünfte benannte Kurve (mit Begründung im PR, Charta-Prozess) | klein, einmal zentral |
| Native TabView | `RootView.swift`/`MainTabView` — `LiquidTabBar` raus, `Tab`-Builder + Accessory rein; Keep-Alive-Panes können bleiben oder der System-Lifecycle übernimmt | mittlerer Eingriff, ein File |
| Logo | `ios/scripts/GenerateIcon.swift` — neue Geometrie-Funktionen, `Palette`-Struct unverändert | eine Datei, CI-Aufruf identisch |
| Kino | `CinematicIntroView` + `CinematicScript` — Szenenliste tauschen, Sprachwahl-Gate vor den Playhead | bestehende Architektur trägt alles |
