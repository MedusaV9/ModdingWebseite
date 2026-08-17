# Stilrichtung „Observatorium" — Designer A

Die Weiterentwicklung der Nachthimmel-DNA in ein präzises, poetisches Instrument der
Zweisamkeit: Sternwarte statt Traumnebel. Das Paar ist ein **Doppelstern** — zwei Sterne, ein
Schwerpunkt — und die App ist das Instrument, durch das beide einander beobachten.

Alle Aussagen unten sind gegen den Ist-Stand geschrieben: `Theme.swift`/`Glass.swift`
(Token-System, `CoupleTint`, `CouplePaletteRules` mit 4,5:1-Boden gegen den Nachtgrund),
`LiquidTabBar.swift` (entfällt), `AppIconKit` (10 prozedurale Paletten), DESIGN.md (15 Gebote,
Ratchets). Nichts hier widerspricht der Charta; wo ein Token sich ändert, steht es explizit.

---

## 1. Manifest

Jede Couple-App auf dem Markt ist ein rosa Kissen — SoooDreamy wird ein Instrument, und ein
Instrument, das man für genau einen Menschen gebaut hat, ist das intimste Geschenk, das es
gibt. Das Observatorium behält den Nachthimmel, den die App schon besitzt, hört aber auf, ihn
zu träumen, und beginnt, ihn zu **vermessen**: Skalenstriche, Okularkreise, Messing-Fassungen,
Logbucheinträge. Die Paar-Farben sind keine Deko mehr, sondern die zwei Sterne des Systems —
alles Warme in der App ist von den beiden, alles Präzise ist vom Instrument, und diese
Arbeitsteilung macht den Look unverwechselbar. Es fühlt sich an wie eine Nacht auf der
Sternwartenkuppel zu zweit: kaltes, klares Glas unter den Fingern, warmes Messing, und in der
Mitte des Okulars genau ein Stern pro Person. Apple-only ist dabei kein Kompromiss, sondern
das Material selbst: echtes Liquid Glass ist die Teleskop-Optik, die native TabView ist die
Instrumentenleiste, SF Pro ist die Gravur.

---

## 2. Farbsystem

### Basis-Nacht (ersetzt `bgTop`/`bgBottom`)

| Token | Hex | Rolle |
|---|---|---|
| `nightZenith` | `#0A0920` | Zenit — fast schwarzes Indigoviolett, oberer Gradient-Stop |
| `nightHorizon` | `#1E1247` | Horizont — hier überlebt die violette DNA von heute (`#2B0F4A`) |
| `panel` | `#151233` | **Opake** Instrumententafel (matte Karten, s. Abschnitt 4) |

Der Grund wird dunkler als heute (`#17062A` → `#0A0920`). Konsequenz für die Kontrastmathematik:
`CouplePaletteRules.darkBackground` wird auf `#0A0920` neu verankert und die komplette
Verdict-Matrix (`PersonalizationLogicTests`) neu gerechnet. Da die Luminanz des Grundes sinkt,
**steigen** alle Akzent-auf-Grund-Kontraste — kein einziges bestehendes Verdict kann kippen,
nur die `onLight`/`onWax`-Pfade (helle Flächen) bleiben unverändert zu prüfen.

### Instrument-Akzente (Chrome-Farben, NIE Emotionsträger)

| Token | Hex | Kontrast auf `#0A0920` | Einsatz |
|---|---|---|---|
| `brass` | `#D9A96A` | ≈ 8,3:1 | Fassungen: Okular-Ringe, Skalenstriche, Hairline-Gravuren. Nur Linien und Ticks, **nie Flächenfüllung, nie Text-Ink** |
| `phosphor` | `#9FE3C4` | ≈ 12:1 | Lebende Messwerte: „Partner online"-Punkt, Sichtungslinie im Chat, aktive Countdown-Ziffern |
| `starline` | `#EAF0FA` (mit Opacity-Leiter wie heute `hairline`) | — | Konstellationslinien, gravierte Trennlinien; ersetzt die rohen `white.opacity`-Hairlines semantisch |

`Theme.gold` (`#FFD166`) bleibt unangetastet die **Zeremonien**-Farbe (Reveal-Siegel, Badges).
Abgrenzung als Regel: Messing ist Werkstatt, Gold ist Feiertag — die beiden treten nie im
selben Element auf.

### Integration mit `CoupleTint` — die Paarfarben bleiben Hauptdarsteller

- **Doppelstern-Prinzip:** `primary` und `secondary` sind die zwei Sterne, `blend` ist der
  Schwerpunkt (Baryzentrum). Jede emotionale Fläche — Hero-Pane (`GlassLevel.tinted`),
  `brandTitle`, Primär-Button-Gradient, Meilenstein-Karten — trägt weiterhin ausschließlich
  Paarfarben. Daran ändert das Observatorium **nichts**.
- **Instrument rahmt, Paar leuchtet:** Messing/Phosphor/Starline dürfen Paarfarben nur
  *fassen* (Ring um den Avatar, Skala unter dem Verlauf), nie ersetzen oder überstrahlen.
  Review-Regel: „Wenn ich die Paarfarben aus diesem Screen entferne, muss er sich anfühlen
  wie ein Teleskop ohne Stern — leer, nicht fertig."
- **Aurora → Sternkarte:** `DreamyBackground` behält die zwei Paar-Farb-Blobs, reduziert ihre
  Opacity um ~30 % und legt darüber eine gravierte Konstellationsebene (`starline` bei 0.05–0.08):
  wenige Linien, die die 60 bestehenden prozeduralen Sterne zu 3–4 Sternbildern verbinden.
  Gleiche Canvas-Technik, gleiche Ambience-Drossel (Reduce Motion / Low Power / Scene Phase).
- **Kontrastgesetz:** Der ≥4,5:1-Boden aus `CouplePaletteRules` (`minimumContrast = 4.5`,
  Scrim-Pfad ohne Ausnahme) bleibt wörtlich in Kraft, nur gegen den neuen Zenit verankert.
  Dark-first bleibt Dark-only — die Marken-Entscheidung aus DESIGN.md (d) gilt unverändert.

---

## 3. Typografie

Der mutigste Schnitt der Richtung: **SF Rounded wird pensioniert.** Rundungen erzählen
„freundliche App", das Observatorium erzählt „präzises Instrument, warm benutzt". Wärme kommt
aus Paarfarben, Serifen und Motion — nicht aus weichen Terminals.

| Rolle (`Typo`) | Font | Gewicht | Bemerkung |
|---|---|---|---|
| `hero` | SF Pro (`.default`) | `.semibold` | Nicht mehr `.heavy` — Präzision statt Lautstärke. Max. 1×/Screen, weiterhin Vollton `coupleTint.blend` via `brandTitle` |
| `title` | SF Pro | `.semibold` | |
| `body` | SF Pro | `.regular` | |
| `label` | SF Pro | `.medium` | |
| `caption` → **`engraving`** | SF Pro | `.medium`, `.smallCaps()` + `tracking(1.1)` | Die „Gravur": Section-Header, Achsen-Beschriftungen, Instrument-Labels. Immer `textTertiary`/`textSecondary`, nie Akzentfarbe |
| `number` → **`reading`** | SF Pro | `.semibold`, `.monospacedDigit()` | „Messwerte": gemeinsame Tage, Countdown, Spielstände — Ziffern zittern nie |
| `voice` | **New York** (`.serif`) | `.regular` italic | Bleibt exakt wie heute: NUR Worte, die die Partner selbst geschrieben haben. Neue Lesart: das ist das **Logbuch** der Beobachtung — Serife = Handschrift im Journal der Sternwarte |

Serifen zusätzlich erlaubt an genau einer neuen Stelle: Jahrestags-/Meilenstein-**Titel**
(New York `.semibold`, nicht kursiv) — Biografie-Momente lesen sich wie eine gedruckte
Jubiläumskarte (Gebot 15). Alles baut wie heute auf semantischen Stilen auf
(Dynamic Type intakt); `Font.scaled` bleibt auf Hero-Zahlen und Deko-Glyphen beschränkt.

---

## 4. Form & Material

### Leitregel: „Glas ist Optik, Matt ist Mechanik"

- **Echtes System-Liquid-Glass** überall, wo Licht *durchfällt*: native TabView (bringt ihr
  Glas selbst mit), Toolbar-Buttons (`.buttonStyle(.glass)`), FAB/Accessory, die EINE
  `GlassLevel.tinted`-Hero-Pane pro Screen, Sheets-Chrome. Unverändert: nie Glas auf Glas,
  nie Glas-Nachbau über `glassEffect` (Charta-Verbote gelten wörtlich).
- **Opake Instrumententafeln** (`panel #151233`) für alles, was *Messwerte und Archive* trägt:
  Statistik-Karten, Spielkarten-Grid, Logbuch/Journal, Settings-Listen. Matte Fläche,
  `starline`-Hairline, gravierte Small-Caps-Beschriftung. Das entlastet zugleich das
  Draw-Budget: weniger konkurrierende Glass-Panes pro Screen, das System-Glas der Hero-Pane
  und der TabView bekommt Raum zu glänzen.
- `GlassLevel.surface` (Standard-`glassCard`) bleibt für Story-Karten auf der Sternkarte —
  der Bestand muss nicht migrieren; neue „Instrument"-Oberflächen entstehen als Panels.

### Radii & Signatur-Form

- Radius-Token bleiben (`pane 28 / card 22 / control 14 / Capsule`, konzentrisch).
- **Signatur-Form: der Okular-Kreis.** Ein perfekter Kreis mit 1-pt-`brass`-Ring (Opacity 0.55)
  und einem 2-pt-Luftspalt zum Inhalt — wie eine Objektivfassung. Einsatzorte, sparsam:
  Avatare (Header, Chat, Nameplates), das Reveal-Siegel, der Pairing-QR, der Fokuspunkt des
  First-Launch-Kinos. Maximal **ein** Okular-Cluster pro View — sonst kippt es in Steampunk.
- **Skalenstriche** als zweites Erkennungszeichen: kurze 1-pt-Ticks (`brass` 0.35) an
  Fortschrittsleisten, Tages-Countdowns und dem Season-Almanach — 4er-Raster (`Space.xs`),
  nie mehr als eine Skala pro Karte.

---

## 5. Motion-Signatur

Drei charakteristische Bewegungen. Charta-Buchhaltung: `focus` **ersetzt** die Parameter von
`arrive` (keine fünfte Kurve), `pan` ist die EINE neu benannte Kurve der Richtung (hier
begründet: sie ist die Navigations-Signatur), der Orbit nutzt das bestehende `drift`.

| Name | Bewegung | Parameter | Reduce Motion |
|---|---|---|---|
| **Teleskopschwenk** (`Theme.Motion.pan`) | Bei Tab-/Screen-Wechsel schwenkt die Sternkarten-Ebene 8–12 pt gegenläufig zur Navigationsrichtung (Parallaxe), Inhalt steht sofort | `spring(response: 0.6, dampingFraction: 0.92)` | reiner Crossfade, Karte steht |
| **Fokusring** (`Theme.Motion.focus`, ersetzt `arrive`) | Karten kommen „scharfgestellt" an: Blur 6 → 0 zusammen mit Scale 1.02 → 1.0 — wie ein Fokuszug am Okular | `spring(response: 0.45, dampingFraction: 0.85)` | nur Opacity |
| **Doppelstern-Umlauf** | Ambient: die zwei Paar-Farb-Punkte umkreisen ihr Baryzentrum (Header-Ambience, Pairing, Warten auf Partner) | `Theme.Motion.drift(12)` — 12-s-Periode, Amplitude ≤ 6 pt | zwei stehende Sterne + Verbindungslinie (Gemälde, kein schwarzes Loch) |

`settle` und `playful` bleiben unverändert; alle drei Signaturen laufen durch den bestehenden
`motionGate` (Gebot 13).

---

## 6. Die native TabView

Die Custom-`LiquidTabBar` entfällt ersatzlos; `MainTabView` wird eine echte iOS-26-`TabView`
mit `Tab`-Buildern. Was die Richtung INNERHALB der nativen Grenzen prägt:

- **System-Verhalten pur:** `.tabBarMinimizeBehavior(.onScrollDown)` — die Bar wird beim
  Lesen zum schmalen Instrument und wächst beim Hochscrollen; `.tabViewStyle(.sidebarAdaptable)`
  gibt dem iPad die Sidebar. Kein eigener Lens-Slide, kein eigenes Keyboard-Ausweichen mehr —
  das System übernimmt beides (und die `visitedTabs`-Lazy-Lifecycle-Mechanik wird durch die
  native Pane-Verwaltung ersetzt).
- **Tint = Baryzentrum:** `.tint(coupleTint.blend)` auf der TabView — die Auswahlfarbe der
  Bar IST die gemeinsame Farbe des Paares. Kein weiterer Eingriff in die Bar-Optik; das
  native Liquid Glass bleibt unberührt (Reduce Transparency/Increased Contrast erledigt es
  selbst, exakt wie in `Glass.swift` dokumentiert).
- **SF-Symbole, Instrument-Gewicht:** Bestandssymbole bleiben semantisch (`house`,
  `bubble.left.and.bubble.right`, `gamecontroller`, `ellipsis.circle`), alle
  `.symbolRenderingMode(.hierarchical)` in `.regular`-Gewicht. Eine gezielte Umbesetzung:
  der „Wir"-Tab wird `moon.stars` / `moon.stars.fill` — das gemeinsame Archiv ist der
  Nachthimmel des Paares. Badges nativ via `.badge(_:)` (Chat-Unreads, „Du bist dran").
- **Accessory als Telemetrie-Leiste:** `.tabViewBottomAccessory` trägt die **Pulsleiste** —
  ein schmaler Streifen mit Phosphor-Präsenzpunkt + Partnername („{name} ist da" /
  „zuletzt {zeit}") links und dem Thinking-of-you-Puls als Okular-Knopf rechts. Damit zieht
  die Funktion des schwebenden `PulseFan`-FABs in natives Chrome um und minimiert sich mit
  der Bar. Inhalt der Leiste: matte Füllungen und Text — KEIN eigenes Glas (das Accessory
  sitzt bereits auf Systemglas; Glas-auf-Glas-Verbot).
- **Was stirbt, ehrlich benannt:** der Wiggle-Easteregg der Custom-Bar und der angedockte
  Hilfe-Kreis. Hilfe wandert als runder `.buttonStyle(.glass)`-Button in die Navigation-Bar
  der Tabs; das Re-Tap-Scroll-to-top liefert die native TabView selbst.

---

## 7. Logo-Konzept: „Der Doppelstern im Okular" (mehrschichtig)

Ein Icon-Composer-artiges Layered Icon, 4 Ebenen — prozedural weiterhin über
`AppIconKit`/`GenerateIcon` renderbar (jede Ebene ist Geometrie + Verlauf, kein Bitmap):

1. **Hintergrund — Nachtgrund mit Sternkarte:** radialer Verlauf aus dem Varianten-Trio
   (`variant.bg`, heute schon vorhanden), darüber 5–6 gravierte Konstellationslinien
   (`starline` bei 0.07) und ~12 Nadelstich-Sterne. Ruhig, fast schwarz an den Ecken.
2. **Mitte — die Messing-Fassung:** ein Okular-Ring (Kreis, Strichstärke ~4 % der Icon-Kante)
   in `brass` mit 12 feinen Skalenstrichen außen. Der Ring ist über alle Paletten-Varianten
   **konstant** — der Wiedererkennungs-Anker, egal welches Farbkleid das Paar trägt.
3. **Vordergrund — der Doppelstern:** zwei vierstrahlige Sterne im Ring, der größere in
   `variant.heart`, der kleinere in dessen aufgehellter Stufe (+25 % Luminanz, prozedural
   ableitbar). Ihre Umlaufbahn ist als feine Ellipsen-Linie angedeutet, und die beiden
   Bahnbögen kreuzen sich so, dass die Schnittfläche zwischen den Sternen eine **Herz-Silhouette**
   negativ formt — das Herz ist nicht mehr gemalt, es entsteht aus dem Umlauf. (Der bestehende
   parametrische `HeartGlyph` liefert die Kontrollpunkte für die Bogenführung.)
4. **Glanz:** Specular-Sweep von der 10-Uhr-Position über Ring und oberen Stern (bestehende
   Licht-Logik), plus ein winziger Beugungs-Kreuzblitz auf dem helleren Stern. Im Icon
   Composer bekommen Ebene 3/4 die stärkste Tiefe → der Tilt-Parallax lässt die Sterne vor
   der Fassung schweben.

**Funktion in den 9+1 Paletten:** `bg` und `heart` je Variante wie heute; `brass`-Ring und
`starline`-Gravur bleiben fix. Dunkle Varianten (midnight, ocean, aurora) tragen den Ring bei
voller Opacity, warme (sunset, gold) bei 0.8, damit Messing nicht mit dem warmen Grund
verschmilzt — eine Zeile Varianten-Metadaten in `AppIconKit.Variant`.

---

## 8. Drei Screen-Blueprints

### Home (DashboardView) — „Die Kuppel"

1. Sternkarten-Hintergrund (gedämpfte Paar-Blobs + Konstellationsgravur), Teleskopschwenk beim Tab-Eintritt.
2. Header wird das **Beobachtungsprotokoll**: links Datum + „Tag 137 gemeinsam" in `reading` (monospaced), darüber die Gravur-Zeile „BEOBACHTUNGSPROTOKOLL" in Small Caps `engraving`.
3. Rechts im Header die zwei Avatare in Okular-Ringen; zwischen ihnen der Doppelstern-Umlauf als Ambient (6-pt-Amplitude, drift(12)) — Präsenzpunkt in `phosphor`, wenn der Partner online ist.
4. Hero-Slot unverändert dramaturgisch (ein Hero, max. drei Karten, ein Fold): die Hero-Karte bleibt die EINE `GlassLevel.tinted`-Pane in Paarfarbe, kommt per Fokusring an.
5. Story-Karten (Daily, Check-in, Touch-Grid) bleiben `glassCard(.surface)`.
6. Mess-Karten (Level, Season-Standings, Quest-Fortschritt) wechseln auf opake Instrumententafeln mit Skalenstrichen an der Fortschrittsleiste.
7. Meilenstein-/Monatstag-Karte: Volltonfläche in `blend` wie heute, Titel neu in New York `.semibold` (Jubiläumskarten-Regel).
8. Der „mehr für heute"-Fold trägt statt `sparkles` einen gravierten Winkel-Chevron mit Tick-Linie.
9. Herz-Coda bleibt der kanonische Heartbeat-Sender, sitzt aber im Okular-Kreis: das 3D-Herz als das, was das Teleskop heute Nacht sieht.
10. Pulse-FAB entfällt — der Puls wohnt in der TabView-Accessory-Leiste (Abschnitt 6).

### Chat (ChatView) — „Das Logbuch"

1. Hintergrund wie Home, aber Blob-Intensität 0.7 — Lesbarkeit vor Ambiente.
2. Tagestrenner werden **Logbuch-Datumslinien**: Gravur-Datum in Small Caps, links und rechts je eine `starline`-Hairline mit drei Skalenstrichen.
3. Nachrichtenblasen: eigene = matte Füllung im eigenen Paarfarbton (Opacity-Stufe aus dem Token-System), Partner = seiner; Radius `control`, konzentrisch im Verlauf der Liste. Kein Glas an Blasen (Archiv = Mechanik).
4. **Sichtungslinie** als Signatur: eine 1-pt-`phosphor`-Linie mit dem Label „zuletzt gesichtet" (Small Caps) markiert die Ungelesen-Grenze und verglüht nach 3 s auf 0.3 Opacity.
5. Liebesbriefe und Zitate bleiben `voice` (New York italic) — im Observatorium sind sie die handschriftlichen Logbucheinträge; Briefkarten opak mit Messing-Hairline statt Glas.
6. Eingabeleiste: echtes Systemglas (`GlassLevel.chrome` wie heute), Senden-Button rund als Mini-Okular mit Ring in `blend`.
7. Typing-Indikator: drei Punkte werden zu einem kleinen Sternbild, das sich zeichnet (settle), Reduce Motion: statisch.
8. „Nach unten springen"-Knopf: runder `.buttonStyle(.glass)` mit `arrow.down`-Symbol, kein Eigenbau.
9. Effekt-Vorschau und Cooldown-Restsekunden in `reading` (monospaced) — der Cooldown ist ein Messwert, kein Drama.

### Spielen-Hub (PlayHubView) — „Die Instrumentenhalle"

1. Titel „Spielen" via `brandTitle` (jetzt SF Pro semibold, Vollton `blend`); das `dice.fill`-Ornament entfällt — Titel + Gravur-Unterzeile „19 INSTRUMENTE" tragen den Kopf.
2. Season-Status-Zeile wird der **Almanach**: opake Tafel, Monatsname in Small Caps, Punktestände beider in `reading`, dazwischen eine Skala mit Tick pro gespieltem Match.
3. Session-Banner („Du bist dran") behalten Systemglas + `phosphor`-Präsenzpunkt — sie sind live, also Optik.
4. Hero-Empfehlungskarte bleibt die EINE tinted Pane des Screens, kommt per Fokusring.
5. Spielkarten im Grid: opake Instrumententafeln, SF-Symbol graviert (hierarchical, `textSecondary`), Spielname `label`; wartet ein Zug auf mich, trägt die Kachel EINEN Messing-Tick oben rechts plus `.badge`-Zahl.
6. Kategorie-Folds (Async/Live/Party) mit Gravur-Headern statt SectionHeader-Bold.
7. „Zuletzt gespielt" als horizontale Reihe kleiner Okular-Medaillons (Spiel-Symbol im Ring, Ausgang farbcodiert in Paarfarben — nie rot, Gebot 15).
8. Sieg-Feiern unverändert über die Delight-Engine — die Halle selbst bleibt leise, damit der eine Moment (Match-Ende) etwas hat, worüber er hinausragen kann.
9. Rekord-/Replay-Karten am Fuß: Tafeln mit monospaced Bestwerten, Skalenstriche als Verlaufs-Sparkline.

---

## 9. First-Launch-Kino (45–60 s, Sprachwahl als erste Szene)

Weiterhin 100 % prozedural im bestehenden `CinematicIntroView`-Rahmen (Script = Timeline,
ein Playhead, Haptik-Score stoppbar, Skip ab Szene 2 jederzeit):

1. **Schwarz & Fokus (0–8 s, interaktiv):** Ein unscharfer Messing-Ring schwebt im Dunkel. Zwei Lichtpunkte darin tragen „Deutsch" und „English". Die Berührung stellt scharf — Blur zieht auf null (Fokusring-Motion), ein leiser Haptik-Klick wie ein einrastender Fokustrieb. Die Sprachwahl IST die erste Handlung am Instrument.
2. **Öffnung der Kuppel (8–16 s):** Über dem Ring schiebt sich ein Kuppelspalt auf (zwei dunkle Flächen weichen auseinander), dahinter der Nachtgrund mit Sternkarte. Erster Satz in der gewählten Sprache, Gravur-Small-Caps: „Da draußen sind Milliarden Sterne."
3. **Teleskopschwenk (16–26 s):** Die Sternkarte schwenkt langsam (pan-Feder, große Amplitude), Skalenstriche und Konstellationslinien ziehen vorbei; Stereo-Haptik wandert mit. Text: „Diese App sucht genau zwei davon."
4. **Erster Stern (26–34 s):** Ein Stern in `Theme.pink`-Fallback (bzw. später Paarfarbe) rastet im Fadenkreuz ein — Tick-Haptik, Phosphor-Aufglühen der Messmarke.
5. **Zweiter Stern & Umlauf (34–44 s):** Der zweite Stern erscheint auf der anderen Stereo-Seite, beide beginnen den Doppelstern-Umlauf; ihre Bahnen zeichnen sich als Linien nach, das Baryzentrum glimmt im Blend auf. Der Sound-Bogen erreicht hier den Merge-Bloom (bestehendes `.pairing`-Motiv).
6. **Das Siegel entsteht (44–52 s):** Die Bahnbögen schließen sich zur Herz-Silhouette, der Messing-Ring legt sich darum — das Logo aus Abschnitt 7 baut sich vor den Augen aus seinen Ebenen zusammen und setzt sich als App-Identität.
7. **Übergabe (52–58 s):** Der Ring schrumpft und wird nahtlos der Okular-Rahmen des ersten echten UI-Elements (Profil-Avatar im Onboarding). Titel „SoooDreamy" in SF Pro semibold, darunter in New York italic: „Euer Logbuch beginnt heute." Crossfade ins Setup — das Intro ist die App, kein Trailer.

Reduce Motion: jede Szene existiert als Standbild-Folge mit Crossfades; die Sprachwahl-Szene
funktioniert identisch (Fokus = Opacity statt Blur). VoiceOver: jede Szene eine Announcement-Zeile,
Skip-Button ab Szene 2 fokussierbar.

---

## 10. Risiken & A11y

**Was kippen kann — und die Gegenregel:**

- **Steampunk-Kitsch:** Messing in Flächen, Zahnräder, Vintage-Texturen würden die Richtung in
  ein Etsy-Regal kippen. Gesetz: `brass` existiert nur als Linie ≤ 2 pt (Ringe, Ticks,
  Hairlines), maximal ein Okular-Cluster und eine Skala pro View, keinerlei Texturen.
- **Kälte-Risiko:** Ein Instrument ohne Wärme ist ein Dashboard. Gegenmittel ist strukturell:
  ALLE emotionalen Flächen tragen ausschließlich Paarfarben, `voice`/New York bleibt exklusiv
  für die Worte der beiden, und die Copy-Regeln der Charta (Gebote 9/10/15) ändern sich nicht.
  Die Präzision gehört dem Rahmen, nie der Anrede.
- **Dunkelheits-Risiko:** Der Zenit wird dunkler; OLED-Smearing bei Scroll und „schwarzes
  Loch"-Wirkung auf Billig-Displays. Gegenmittel: `nightHorizon` hält das Violett sichtbar,
  die Konstellationsgravur gibt der Fläche Zeichnung, und die Kontrast-Verdicts werden gegen
  den neuen Grund per Test-Matrix neu gepinnt (nur Verbesserungen möglich, s. Abschnitt 2).
- **Small-Caps-Risiko:** Gravur-Labels in Small Caps + Tracking können bei AX-Größen zu
  Buchstabensalat werden. Regel: `engraving` baut auf `.caption`/`.subheadline` semantisch auf
  (skaliert mit), ab `isAccessibilitySize` fällt das Tracking auf 0 und Small Caps auf
  normale Groß-/Kleinschreibung zurück — Lesbarkeit schlägt Gravur.

**A11y-Zusagen (AX5, Reduce Motion, Reduce Transparency):**

- Alle drei Motion-Signaturen laufen durch den bestehenden `motionGate`: Schwenk → Crossfade,
  Fokus → Opacity, Umlauf → Gemälde (stehende Sterne + Linie). Kein neuer Ambient-Pfad umgeht
  die Drossel.
- Reduce Transparency: natives Glas (TabView, `.glass`-Buttons, Hero-Pane) tauscht sich
  selbst; die neuen Instrumententafeln sind bereits opak — die Richtung REDUZIERT die Menge
  handbemalter Transluzenz gegenüber heute.
- AX5: Okular-Ringe wachsen mit ihrem Inhalt (Ring = Overlay auf dem skalierten Kreis, Hit-
  Targets ≥ 44 pt fix); Skalenstriche sind rein dekorativ und `accessibilityHidden`; die
  native TabView übernimmt das AX-Verhalten der Bar (kein eigener Icon-Only-Sonderpfad mehr);
  der `paired-ax5-de.png`-Gate der Screenshot-Matrix bleibt das Prüfmittel.
- Kontrast: ≥4,5:1 ohne Ausnahme gegen `#0A0920`, `phosphor`/`brass` sind mit ≈12:1/≈8:1
  deutlich über dem Boden; `Theme.Contrast`-Varianten für Increased Contrast bekommen für
  `starline` und `engraving` je eine festere Stufe.

---

*Designer A — Richtung „Observatorium". Eine Datei, kein Code; alle Token-/API-Namen
referenzieren den Ist-Stand von `Theme.swift`, `Glass.swift`, `AppIconKit` und DESIGN.md.*
