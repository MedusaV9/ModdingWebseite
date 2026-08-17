# STYLE_DECISION.md — Das Jury-Urteil des Stil-Wettbewerbs

**Status: verbindlich.** Dieses Dokument entscheidet den Stil-Wettbewerb der fünf
Richtungen (`DIRECTION_OBSERVATORIUM`, `DIRECTION_PAPIER_LICHT`, `DIRECTION_GEZEITENBECKEN`,
`DIRECTION_NEON_DUETT`, `DIRECTION_EDITORIAL`) und legt in Abschnitt 3 die **Art Direction v2**
fest, nach der die gesamte App reworked wird. Die Bau-Wellen setzen dieses Dokument wörtlich um.

Bewertungsgrundlage: die fünf Dossiers in `docs/styles/`, die bestehende Charta
`SoooDreamy/DESIGN.md` (15 Gebote, Ratchets, `tools/charter_baseline.json`), der Ist-Stand in
`ios/SoooDreamy/UI/Theme.swift` / `UI/Glass.swift` / `UI/LiquidTabBar.swift` /
`ios/scripts/GenerateIcon.swift` (379 Swift-Dateien; 323 `glassCard`-Aufrufe in 101 Dateien;
`CouplePaletteRules.darkBackground = #17062A`), `docs/styles/RECON_NATIVE_IOS26.md` als
Machbarkeits-Referenz für die native TabView-Migration (API-Inventar, Migrations-Plan,
Layered-Icon-Pipeline) sowie `docs/styles/RECON_REMOTION_PIPELINE.md` für die
Kino-Machbarkeit. Wo ein Dossier und die Recon kollidieren, gewinnt die Recon — sie ist
gegen SDK und Apple-Doku geschrieben.

---

## 1. Bewertungsmatrix

Skala 1–10. Kriterien: (a) Einzigartigkeit/Unverwechselbarkeit · (b) Apple-Nativität ·
(c) Machbarkeit im Bestand · (d) Paar-Wärme/Intimität · (e) A11y-Robustheit ·
(f) Skalierbarkeit über alle Flächen.

| Richtung | (a) | (b) | (c) | (d) | (e) | (f) | **Σ** |
|---|---|---|---|---|---|---|---|
| Observatorium (A) | 7 | 8 | 9 | 7 | 8 | 8 | **47** |
| **Papier & Licht (B)** | **9** | **8** | **7** | **10** | **9** | **9** | **52** |
| Gezeitenbecken (C) | 7 | 9 | 8 | 7 | 7 | 8 | **46** |
| Neon-Duett (D) | 9 | 7 | 6 | 8 | 7 | 8 | **45** |
| Editorial (E) | 8 | 9 | 5 | 6 | 8 | 8 | **44** |

### Begründungen — Observatorium (A)

- **(a) 7** — „Doppelstern im Okular" und die Messing/Phosphor-Sprache sind eigen, aber die
  Richtung „behält den Nachthimmel, den die App schon besitzt" (§1) — es ist die Präzisierung
  genau des Looks, den der User als „nicht unique" empfindet, nicht sein Ersatz.
- **(b) 8** — Native TabView pur inklusive `.tabBarMinimizeBehavior` und ehrlicher
  Streichliste („Was stirbt, ehrlich benannt", §6); SF Pro + Small Caps sind systemnah. Ein
  Punkt Abzug: Ringe, Ticks und Gravuren sind Eigenbau-Ornamentik neben dem System-Material.
- **(c) 9** — Explizit gegen den Ist-Stand geschrieben: der Grund wird dunkler, „kein einziges
  bestehendes Verdict kann kippen" (§2), und `GlassLevel.surface` bleibt („der Bestand muss
  nicht migrieren", §4) — die kleinste Diff aller fünf Einreichungen.
- **(d) 7** — Doppelstern und Logbuch sind intim, aber die Richtung muss ihre eigene Kälte
  strukturell einhegen („Ein Instrument ohne Wärme ist ein Dashboard", §10) — Wärme ist hier
  Gegenmittel, nicht Kern.
- **(e) 8** — Kontraste steigen durchweg (`phosphor` ≈ 12:1, `brass` ≈ 8:1, §2), der
  Small-Caps-AX-Fallback ist definiert (§10); Rest-Risiko bleibt die OLED-Dunkelheit des
  neuen Zenits, das Dossier benennt es selbst.
- **(f) 8** — Skalen, Ringe und Gravur tragen Spiele, Chat und Kino; aber „`brass` existiert
  nur als Linie ≤ 2 pt" (§10) begrenzt die Ausdrucksbreite auf Feier- und Hero-Flächen.

### Begründungen — Papier & Licht (B)

- **(a) 9** — Helles, warmes Papier im dunklen Zimmer ist „maximaler Flächenkontrast statt
  noch einer dunklen Glas-App" (§2.1): in jedem einzelnen Screenshot sofort als SoooDreamy
  erkennbar, und keine Couple-App am Markt sieht so aus.
- **(b) 8** — Die native TabView ist hier nicht Pflicht, sondern Kernbild: „weil der
  Materialkontrast (System-Glas über Papier) ihr Kernbild ist" (§6); System-Glass bleibt
  exklusiv echtem Chrome vorbehalten. Ein Punkt Abzug: Papier ist viel Custom-Fläche an
  Stellen, wo andere Richtungen das System zeigen.
- **(c) 7** — Der Umbau ist groß (`PaperLevel` ersetzt `GlassLevel.surface`/`.tinted`, §4.1),
  aber zentralisiert: `glassCard()` ist der eine Choke-Point (323 Aufrufstellen in 101 Dateien
  hängen an EINEM Modifier in `Theme.swift`), und die Wachs-/Verdict-Maschinerie „existiert
  schon" (§2.6: `onWax`, `LetterSeals`, `CouplePaletteRules`).
- **(d) 10** — Liebesbrief, Wachssiegel in der Paarfarbe, „als hätte euer Lieblingsmensch das
  Licht angelassen" (Schlusszeile): kein anderes Dossier erzählt die Zwei-Personen-Intimität
  so direkt im Material selbst — die App IST der Briefwechsel, den sie verwaltet.
- **(e) 9** — Opakes Papier liefert Tinte-Kontraste „von 7:1 bis 13:1" (§2.1), Reduce
  Transparency ist „strukturell besser als heute" (§10), und alle Artefakte sind
  Overlay-Dekor ohne Layout-Beitrag (AX5-sicher per Konstruktion).
- **(f) 9** — Spielbrett auf Papier-Bogen, Zettelwechsel-Chat, Polaroid-Erinnerungen,
  Heute-Zettel im TabView-Accessory, versiegeltes Polaroid-Icon über alle 9+1 Paletten (§7):
  die Metapher hat für jede Fläche ein eigenes, natives Wort.

### Begründungen — Gezeitenbecken (C)

- **(a) 7** — „Liquid Glass, wörtlich genommen" (Kopfzeile) ist das cleverste
  Konzept-Statement des Wettbewerbs, aber Petrol-Wasser plus Biolumineszenz ist eine bekannte
  Wellness-Ästhetik; die Unverwechselbarkeit hängt allein an den Paar-Strömungen.
- **(b) 9** — Die stärkste native Erzählung: „die Bar ist wörtlich die Oberfläche des Beckens,
  und wir malen **nichts** auf sie" (§6); Abtauchen und `.tabBarMinimizeBehavior(.onScrollDown)`
  meinen dasselbe — Konzept und System-API decken sich eins zu eins.
- **(c) 8** — Einzige Einreichung mit Umsetzungs-Landkarte (Anhang): `TidalPoolBackground` als
  Drop-in, „`Palette`-Struct ohne Feldänderung" (§7), Content-Karten bleiben Glas. Abzug:
  Stillwasser-Masken und Kaustik-Deckel sind dauerhafte Sonderpflege in jeder neuen View.
- **(d) 7** — Konfluenz und Flaschenpost sind schöne Bilder, aber die Richtung muss ihre
  eigene Kühle aktiv ausgleichen („Blau-Monotonie / emotionale Kälte", §10) — Wasser bleibt
  ein kühles Element, das Wärme importieren muss.
- **(e) 7** — Seekrankheits-Deckel, Stillwasser-Zonen und ΔL ≥ 20 sind sauber definiert
  (§10), aber es ist die Richtung mit der meisten zu polizierenden Ambient-Bewegung — jede
  neue Fläche erbt die Kaustik-Frage.
- **(f) 8** — Tiefenzonen tragen den Spiele-Hub, der Gezeitenkalender die Seasons (§8.3);
  Widgets und Kino sind gut abbildbar; nur Feiern bleiben im Wasser leiser als Wachs es kann.

### Begründungen — Neon-Duett (D)

- **(a) 9** — „Die App besitzt kein eigenes Licht. Alles, was leuchtet, sind die beiden"
  (Schlusszeile) ist das schärfste Marken-Statement des Wettbewerbs; das offene Herz aus zwei
  Röhren ist als Silhouette einzigartig und „bei 29 pt noch lesbar" (§7).
- **(b) 7** — Die native Bar ist korrekt behandelt („Man stylt die native Bar nicht — man
  stylt die Welt, die sie bricht", §6), aber Marquee-Versalien, Halos und Glow-Budget sind
  viel handgemalte Atmosphäre neben dem System-Material.
- **(c) 6** — Samt-Karten ersetzen `surface`-Glas app-weit plus neue Bubble-Kanten-Sprache im
  Chat; das Dossier nennt es selbst „Ehrliche Kosten" (§10); dazu drei neue
  Verdict-Funktionen (`neonCore/Gas/Halo`) und die `NeonRules.flickerFree`-CI-Maschinerie.
- **(d) 8** — „das Pairing ist der Moment, in dem sie angeht" (§2.2) ist das stärkste
  einzelne Paar-Bild aller Dossiers; die Nacht in der Stadt ist aber Date-Romantik, nicht
  Zuhause-Intimität — Rounded wird bewusst auf `Typo.warm` rationiert (§3).
- **(e) 7** — Glow gegen Kontrast bleibt ein permanent zu verteidigender Konflikt („Wenn ein
  Halo den Verdict nicht schafft, verliert der Halo", §10); die Flacker-Nulltoleranz (§5) ist
  vorbildlich, kondensierte Versalien brauchen den harten AX-Fallback.
- **(f) 8** — Das Schild-System skaliert auf Spiele („SPIELBAR") und Kino hervorragend; in
  Widget-Größen und auf kleinen Flächen wird Glühen physisch eng (Glow-Budget 2/Viewport, §2.3).

### Begründungen — Editorial (E)

- **(a) 8** — „keine Couple-App sieht wie ein gesetztes Magazin aus" (Jury-Kurzfassung)
  stimmt; als Genre-Ästhetik ist Editorial-Dark aus Lese-Apps (Apple News+) jedoch vertraut —
  einzigartig im Couple-Genre, nicht im App Store.
- **(b) 9** — New York + SF Pro, Rules statt Panes, und die ehrliche Grenze „Tab-Labels
  bleiben SF Pro … genau das meint ‚Apple-only'" (§6): die HIG-treueste Einreichung.
- **(c) 5** — Invasivster Umbau: neue Radius-Skala (card 22 → 10, control 14 → 8), Chips
  werden Rechtecke, Karten weichen Rules (§4) — das ist Re-Layout pro Screen, nicht Re-Skin;
  dazu ein komplett neues Typo-Rollenbuch und „Rounded wird per Ratchet auf 0 gefahren" (§10).
- **(d) 6** — Pull-Quotes aus echten Worten und „Ausgabe = gemeinsame Tage" sind warm, aber
  die Redaktion ist eine Distanz-Instanz („Steifheits-Gefahr — Editorial kann kühl/museal
  kippen", §10): Wärme wird hier als Gegenmaßnahme verwaltet, nicht als Kern erzählt.
- **(e) 8** — Das Markierstift-Prinzip entkoppelt Paarfarben strukturell vom Textkontrast
  (§2, „der 4,5:1-Floor kann nicht brechen"), Serifen-Untergrenze und AX-Regeln sind präzise;
  der Affordanz-Verlust der Rules („was ist tappbar?", §10) bleibt ein echtes Risiko.
- **(f) 8** — Das Rubriken-System benennt jede Fläche („Rätselseite", „Sonderausgabe"), aber
  Live-/Party-Spiele und Widgets zwängen sich in die Zeitungs-Metapher.

**K.-o.-Feststellung zu Editorial**, unabhängig von der Punktsumme: „Die Paarfarben färben
**nie den Text** und **nie das Papier**" (E §2) degradiert `CoupleTint` vom Hauptdarsteller
zum Textmarker. Nach der Wettbewerbsregel — jede Richtung, die die Paarfarben entmachtet,
verliert — ist Editorial damit vom Sieg ausgeschlossen.

---

## 2. Der Entscheid

**Gewinner ist „Papier & Licht" (Designer B).** Die Klage des Users lautet „alles sieht
irgendwie nicht unique aus", und die ehrliche Diagnose ist: jede dunkle Glas-App sieht aus wie
jede andere dunkle Glas-App — Papier & Licht ist die einzige Richtung, die dieses
Genre-Problem an der Wurzel löst, weil helles, warmes Papier im dunklen Zimmer in jedem
einzelnen Screenshot unverwechselbar ist. Observatorium und Gezeitenbecken sind hervorragende
Weiterentwicklungen desselben dunklen Glas-Genres; sie wären schöner, aber nicht anders.
Neon-Duett ist konzeptionell brillant, verliert aber im Dauerbetrieb: Glow steht strukturell
im Krieg mit dem 4,5:1-Gesetz, und Neon altert als Ästhetik schneller, als eine App altern
darf, die ein Paar über Jahre begleiten soll. Editorial scheitert an der Wettbewerbsregel,
weil es die Paarfarben zum Textmarker degradiert. Papier & Licht tut das Gegenteil — es
befördert die Paarfarben von Deko zu **Material**: deine Tinte, meine Tinte, euer Wachs, euer
Band; das Siegel in `blend` ist präsenter als jede heutige tinted-Glas-Fläche. Zur
Apple-Nativität: Diese Richtung braucht die native iOS-26-TabView nicht nur, sie **erzählt**
sie — die Glasplatte über dem Erinnerungsalbum ist wörtlich
`.tabBarMinimizeBehavior(.onScrollDown)` über opakem Content, und System-Liquid-Glass bleibt
exklusiv dem Chrome vorbehalten, exakt so, wie die HIG das Material meint: Navigationsschicht,
nicht Content-Deko. A11y ist keine Nacharbeit, sondern Dividende: opakes Papier liefert
7:1–13:1-Tinte-Kontraste und macht Reduce Transparency strukturell fast zum No-Op. Die
Machbarkeit ist die drittbeste des Feldes, aber die Migrationskosten sind zentralisiert:
`glassCard()` ist der eine Choke-Point, die Wachs-/Verdict-Maschinerie existiert bereits, und
die Kontrast-Verdicts wechseln nur ihren Anker. Über Jahre trägt der Stil, weil seine Metapher
mit dem Inhalt identisch ist: Diese App ist tatsächlich ein Archiv aus Briefen, Fotos und
Ritualen zweier Menschen — Papier ist hier nicht Thema, sondern Wahrheit. Der
Skeuomorphismus-Kitsch ist das benannte Hauptrisiko, und die Leitplanken des Dossiers sind ab
heute Gesetz (Artefakt-Budget 3, eine gerissene Kante, eine Rotation pro Screen, kein
Skript-Font, kein Vergilbungsfilter, keine Bitmap-Texturen).

**Die eine Akzent-Anleihe:** Papier & Licht übernimmt aus `DIRECTION_EDITORIAL` genau EINE
Anleihe — die **Ausgaben-Logik** („Die Ausgabennummer IST der Tage-Zähler des Paares",
E §4 „Folio"). Bei uns materialisiert sie sich im bestehenden Signatur-Element Poststempel:
jeder Poststempel trägt neben dem Datum die Prägezeile **„TAG 137"**. Diese Anleihe ist
bewusst Inhalt, nicht Optik — sie bringt Gebot 15 (Biografie, kein Spielstand) in ein
Signatur-Element, ohne die Magazin-Formsprache zu importieren. Alles andere aus den vier
unterlegenen Dossiers wird NICHT übernommen — kein Kaustik-Schimmer, kein Glow-Halo, keine
Messing-Ringe, keine Rubriken-Namen: ein Stil, ganz.

---

## 3. Art Direction v2 — das verbindliche Bau-Dokument

### 3.1 Farbtokens (Migrationsziel; Rohwerte leben NUR in `UI/Theme.swift`)

**Nachttöne — das Zimmer** (Hintergrund-Canvas, ersetzt Aurora + Sternfeld):

| Heute | Wert heute | Neu | Hex neu | Rolle |
|---|---|---|---|---|
| `Theme.bgTop` | `#17062A` | `Papier.zimmerOben` | `#201613` | dunkles Sepia-Umbra, oberer Rand |
| `Theme.bgBottom` | `#2B0F4A` | `Papier.zimmerUnten` | `#33241B` | warme Kastanie, unterer Rand |
| — (Aurora-Blobs) | — | `Papier.lichtkegel` | `#4A3320` | EIN radialer Lampenschein von 10 Uhr, Opacity 0.35 → 0 |

Der Hintergrund bleibt EIN Canvas-Pass: Zimmer-Gradient + Lichtkegel + ~40 Staubkörner im
Kegel (`Theme.Motion.drift(9)`, Freeze unter Reduce Motion / Low Power / Background wie heute
`StarFieldView`). **Jury-Präzisierung (Paarfarben im Ambient):** die Staubkörner sind
**Tintenstaub** — die eine Hälfte trägt `coupleTint.primary`, die andere `secondary`, je bei
0.5 Opacity innerhalb des Kegels. Damit bleibt der Paar-Farb-Anteil des heutigen
Aurora-Hintergrunds erhalten, ohne die Zimmer-Metapher zu brechen.

**Papiertöne — die Inhalte** (opak, ersetzen die Glas-Karten):

| Heute | Wert heute | Neu | Hex neu | Rolle |
|---|---|---|---|---|
| `Theme.card` | `white @ 0.07` | `Papier.brief` | `#F7F1E4` | Standard-Kartenfläche |
| — | — | `Papier.karton` | `#EFE6D2` | Sekundär-Karten, Partner-Zettel, Innenflächen |
| `Theme.cardBorder` | `white @ 0.12` | `Papier.kante` | `#E3D6BC` | Stapelkante, Rückseiten, Trennlinien auf Papier |
| — | — | `Papier.polaroid` | `#FAF6EC` | Polaroid-Rahmen (nur Fotos) |

**Tinten — Text auf Papier** (gemessen gegen `#F7F1E4`):

| Heute | Neu | Hex | Kontrast | Rolle |
|---|---|---|---|---|
| `Theme.textPrimary` (auf Papier) | `Tinte.dunkel` | `#2E2318` | 13,6:1 | Primärtext, Überschriften auf Papier |
| `Theme.textSecondary` (auf Papier) | `Tinte.sekundaer` | `#5A4A38` | 7,6:1 | Sekundärtext |
| `Theme.textTertiary` (auf Papier) | `Tinte.tertiaer` | `#6E5C46` | 5,7:1 | Timestamps, Fußnoten — nie unter `.caption` |

**Lampenlicht — Akzente auf Nacht** (gemessen gegen `#201613`; NIE als Text auf Papier):

| Heute | Neu | Hex | Kontrast | Rolle |
|---|---|---|---|---|
| `Theme.gold` `#FFD166` | `Licht.lampengold` | `#FFC46B` | 11,3:1 | Zeremonien-Akzent, Glows auf Nacht |
| `Theme.blue`/`mint`/`indigo` (Chrome-Rollen) | `Licht.glut` | `#E8845E` | 6,7:1 | zweiter warmer Akzent, aktive Zustände auf Nacht |
| — | `Wachs.rot` | `#B33A3A` | Material | Siegel/Stempelkissen — nie Text auf Nacht |
| `Theme.textPrimary` (auf Nacht) | `Papier.aufNacht` | `#F3EAD9` | 14,8:1 | Text direkt auf dem Zimmer |
| `Theme.hairline` (auf Nacht) | `Nacht.naht` | `Papier.aufNacht @ 0.12` | Nicht-Text | Hairlines auf Nacht (Increased Contrast: 0.38) |
| `Theme.energyRed` `#F87171` | bleibt | `#F87171` | neu pinnen | Verletzlichkeits-Rot, weiterhin nie im Paar-Farbkanal |

**CoupleTint — die Hauptdarsteller-Regel:** `primary`/`secondary` = zwei Tinten,
`blend` = das Wachs, `heroGradient` = das 6-pt-Band der Hero-Karte. Auf Papier laufen
Paarfarben durch die neue Verdikt-Leiter **`CouplePaletteRules.inkOnPaper(hex)`** (Mechanik
identisch `accentOnLight`, Anker `#F7F1E4`, ≥ 4,5:1 maschinell) — Einsatz: 4-pt-Tintenkante,
Unterschrift-Linien, Avatarringe, `brandTitle` auf Papier. Fließtext bleibt IMMER
`Tinte.dunkel`. `CouplePaletteRules.darkBackground` wechselt im selben Commit von `#17062A`
auf `#201613`; die komplette Verdict-Matrix (`PersonalizationLogicTests`) wird neu gepinnt.
`PrimaryButtonStyle` (Paar-Verlauf-Kapsel, Verdict-gesichert) bleibt unverändert — Buttons
sind Werkzeug und gehören zur Chrome-Welt.

### 3.2 Typografie-Rollenbuch (Systemfonts only)

Gesetz: **Rounded = „die App spricht" (gedruckt), New York = „von euch geschrieben"
(Feder). Serifen erscheinen AUSSCHLIESSLICH auf Papierflächen** — nie auf Glas, nie auf Nacht.

| Rolle | Font | Definition | Einsatz |
|---|---|---|---|
| `Typo.hero` | SF Rounded | `.largeTitle` heavy | unverändert, max. 1×/Screen; auf Nacht `Papier.aufNacht`, auf Papier via `brandTitle` |
| `Typo.title` | SF Rounded | `.title3` bold | Karten-Titel (gedruckte Etiketten) |
| `Typo.body` | SF Rounded | `.body` | UI-Fließtext, Buttons |
| `Typo.label` | SF Rounded | `.subheadline` semibold | Controls, Zeilen-Labels |
| `Typo.caption` | SF Rounded | `.caption` semibold | Metadaten |
| `Typo.number` | SF Rounded | `.title2` bold `monospacedDigit` | Stats — gedruckte Zahlen, nie Serif |
| `Typo.voice` | New York | `.title3` italic | UNVERÄNDERT heilig: NUR Worte der Partner (Zitat, Journal, Kapseln) |
| `Typo.brief` **(neu)** | New York | `.body` regular | Brief-KÖRPER beim Lesen (LetterComposer/Reader, Journal-Volltext) |
| `Typo.anschrift` **(neu)** | New York | `.caption` semibold `.smallCaps()` | Poststempel, Datumszeilen auf Papier, „Für dich"-Zeilen — der EINZIGE Kapitälchen-Einsatz der App |

Regeln: `brandTitle(_:)` bleibt die eine Titel-Behandlung (Vollton `blend`; auf Papier
`inkOnPaper(blend)`). Alle Rollen bauen auf semantischen Styles auf (Dynamic Type inkl. AX5);
ab `isAccessibilitySize` verliert `anschrift` Small Caps und Tracking. `Font.scaled` bleibt
Hero-Zahlen und Deko-Glyphen vorbehalten (Ratchets `fixed_font_sizes`/`system_size_fonts`
gelten weiter). Kein Verlauf auf Text — nirgends.

### 3.3 Material-Regeln (Zwei-Materialien-Gesetz)

| Material | Was | Verhalten |
|---|---|---|
| **System-Glas** (`GlassLevel.chrome`, echt, unverändert) | ALLES was schwebt: native TabView, Toolbar-Buttons, FAB/PulseFan, Chat-Eingabeleiste, Sheet-Chrome, Toasts | `glassEffect(.regular)`; das System rendert Refraktion/Kante; Inhalte scrollen darunter durch |
| **Papier** (neu: `PaperLevel`, ersetzt `GlassLevel.surface` + `.tinted`) | ALLES was liegt: Content-Karten, Chat-Zettel, Spielkarten, Polaroids, Listen | opak, matt, `Elevation`-Schatten, warme Lichtkante |

`PaperLevel`-Stufen: `.brief` (Standard, ersetzt `glassCard()`-Default) · `.karton`
(Sekundär/Partner) · `.polaroid` (Fotos) · `.briefbogen` (Hero: `Papier.brief` + Band +
Wachssiegel — genau EINE pro Screen, erbt die Hero-Regel der Charta).

Verbote: **Glas-auf-Glas bleibt verboten. Neu: Papier-auf-Glas ist verboten** (Papier liegt
immer UNTER dem Chrome). Innenflächen auf Papier sind `Tinte.dunkel @ 0.05`-Fills mit
`Papier.kante`-Hairline — nie ein zweites Material. `Elevation` (resting/raised/floating)
bleibt wörtlich; die 10-Uhr-Lichtquelle IST jetzt die Lampe: jede Papierkarte trägt oben-links
eine 1-pt-Lichtkante (`Papier.brief` +8 % Luminanz) und wirft den Schatten nach unten-rechts.
**Papierkorn**: statischer Metal-`colorEffect`-Shader, Hash-Noise, Luminanz ±2 %, KEINE
Animation, unter Increased Contrast aus, unter Text < `.subheadline` nicht gerendert.

### 3.4 Radii & Formen

- `Radius.pane = 28` · `Radius.card = 22` · `Radius.control = 14` · Chips = `Capsule()`:
  unverändert für Glas, Sheets und Controls.
- **`Radius.papier = 10` (neu):** alle Papierkarten — geschnittenes Papier ist schärfer als
  Glas. **`Radius.polaroid = 4` (neu):** Fotorahmen. Innen weiterhin
  `Radius.concentric(parent:padding:)`.
- Kanten-Formen: **Gestanzt** (glattes `RoundedRectangle`, 90 % aller Karten) ·
  **Gerissen** (`TornEdgeShape` in `UI/`: EINE Kante, seeded Jitter, Amplitude 2,5 pt,
  Periode 10–14 pt, Seed = stabile Item-ID; max. 1 pro Screen) · **Coupon-Scallop**
  (Gutscheine). Rotationen NUR über das seeded Token `PaperTilt(seed:)` der UI-Schicht,
  Bereich −6°…+6°, max. 1 rotiertes Element pro Screen.

### 3.5 Die 3 Motion-Signaturen (alle auf den vier bestehenden Kurven — keine fünfte)

| Name | Bewegung | Parameter | Reduce Motion |
|---|---|---|---|
| **Blättern** (Screen-/Hero-Einstieg) | Karte rotiert um die führende Kante herein: `rotation3DEffect` −12° → 0°, `anchor: .leading`, `perspective: 0.3`; Elevation-Schatten wandert synchron `x: −4 → +1` | `Theme.Motion.arrive` (spring 0.5/0.8) | reiner Crossfade |
| **Legen** (Elemente erscheinen) | Zettel landet: Scale 1.04 → 1.0, Schatten-Radius 24 → 14, y-Offset 6 → 0, Rotation seeded ±1,5° → ±0,8°; Stagger 40 ms, max. 6 Elemente | `Theme.Motion.settle` (0.35/0.85) | Fade ohne Transform |
| **Lichtschein** (Feier-/Ankunftsmoment) | radialer `Licht.lampengold`-Glow blüht hinter dem Element: Opacity 0 → 0.35 → 0.22, Radius 0 → 1,4 × Elementgröße, bleibt danach stehen; ersetzt Konfetti auf Delight-Stufe 1–2, `epic` behält Partikel | `Theme.Motion.drift(1.2)` | statischer End-Glow erscheint sofort |

Alle drei laufen durch den bestehenden `motionGate` (Gebot 13). Neue Haptik: Papier-`tap`
beim Legen einer Nachricht; Siegelbruch bleibt der eine laute Moment (Haptik + Klang).

### 3.6 Signatur-Elemente pro Screen-Typ (Budget: max. 3 Artefakte pro Screen)

- **Global, genau drei Artefakt-Typen:** (1) **Wachssiegel** — Kreis Ø 44 pt in
  `blend`-Wachs, `onWax`-Prägung (Herz/Monogramm), seeded Rotation −4°…+4°; (2)
  **Klebeecke** — 2 Pergament-Dreiecke (`Papier.kante @ 0.85`) diagonal, nie alle vier;
  (3) **Poststempel** — gestrichelter Doppelkreis Ø 56 pt, `Typo.anschrift`, Rotation −8°,
  `Tinte.sekundaer @ 0.7`, mit der Prägezeile **„TAG {n}"** (Editorial-Anleihe, Abschnitt 2).
- **Dashboard/Hubs:** Briefbogen-Hero (Band + Siegel), Stapelkante (2 pt versetzte
  `Papier.kante`-Rückseite) an Inbox-Stapeln, „Mehr"-Fold als umgeschlagene Papierecke statt
  Chevron. Einstieg: 1× Blättern (Hero), Legen gestaffelt (Rest).
- **Chat/Listen:** eigene Zettel `Papier.brief`, Partner `Papier.karton`; 4-pt-**Tintenkante**
  in `inkOnPaper(primary/secondary)` an der Außenkante (doppelt kodiert mit Seitenlage);
  Tagestrenner = Poststempel-Medaillon; Sticker/Fotos als Mini-Polaroids mit EINER Klebeecke;
  Liebesbriefe versiegelt in `blend`-Wachs, Siegelbruch beim Öffnen.
- **Spiele:** Spielbretter auf einem großen Papier-Bogen im Lichtkegel; laufende Partien als
  Spielkarten-Stapel mit 2°-Fächerung; Season-Zeile als Zettelstreifen mit Monats-Poststempel;
  Siege feiern mit Lichtschein (Stufe 1–2), `epic` nur Monats-Ereignisse.
- **Zeremonien (Reveal/Meilenstein/Jahrestag):** das Wachssiegel ist der Kern — gießen,
  prägen, brechen; Meilenstein-Titel in `Typo.voice`-Familie nur, wenn die Worte vom Paar sind.
- **Widgets:** ein Widget = EIN Zettel (`Papier.brief`, Tintenkante, Radius `papier`), keine
  Artefakt-Stapelung, kein Korn — Lesbarkeit vor Charme auf kleinster Fläche.
- **Settings/Formulare:** `Papier.karton`-Listen, KEINE Artefakte — Werkzeug-Räume bleiben still.

### 3.7 Native-TabView-Prägung (`MainTabView` wird echte iOS-26-`TabView`)

Umsetzung strikt nach `RECON_NATIVE_IOS26.md` §2 (Migrations-Plan, Reihenfolge §2.9);
hier nur die Stil-Entscheidungen der Richtung innerhalb der nativen Grenzen:

- **Struktur:** `Tab`-Builder mit fünf Tabs, Selektionstyp bleibt `AppTab`. Symbole:
  `lamp.desk` (Home), `envelope` (Chat), `dice` (Spielen),
  `photo.on.rectangle.angled` (Wir), `ellipsis.circle` (Mehr) — nur outline; den
  Selektions-Fill rendert das System selbst (Recon §2.2). Entschieden: **kein**
  `Tab(role: .search)` — die Erinnerungs-Suche wird `.searchable` im Memories-Stack
  (Recon-Sweep #4/#5), der Wir-Tab bleibt regulär.
- **Tint:** `.tint(coupleTint.blend)` — die Auswahlfarbe der Bar IST die gemeinsame Farbe.
  Sonst KEIN Eingriff in die Bar-Optik: keine Overlays, keine Materialien, kein
  Lens-Nachbau, keine Custom-Badge-Kapsel (Badges nativ via `.badge`, „99+"-Deckel über
  `TabBarLogic.badgeText` als String-Badge).
- **Verhalten:** `.tabBarMinimizeBehavior(.onScrollDown)` + `.scrollEdgeEffectStyle(.soft)`
  auf jeder Tab-Root-ScrollView — Papier scrollt sichtbar UNTER dem Glas durch.
  **iPad: Default-Stil (`.automatic`)** — `sidebarAdaptable` ist bewusst NICHT Teil von v2
  (Recon §2.7: Doppel-Sidebar-Risiko mit dem Memories-Split, State-Verlust-Berichte);
  Re-Tap-to-Top läuft über das reselect-aware Binding + bestehenden Scroll-Walk (Recon §2.6);
  Keyboard-Ausweichen und AX5-Dock-Vertrag entfallen ersatzlos (Systemleistung).
- **`tabViewBottomAccessory` = der Heute-Zettel:** volle-Breite-Kapsel über der Bar mit dem
  Tagesritual-Status (Frage beantwortet? Siegel wartet?), tappbar zum Reveal — die EINE
  Stelle, an der Papier das Chrome berührt. Pflicht: beide Placements bedienen
  (`.expanded` = Zettel mit Text, `.inline` = nur Siegel-Punkt + Kurzstatus, Recon §1.2).
  Der PulseFan-FAB bleibt als rundes Chrome-Glas erhalten (Werkzeug, nicht Erinnerung);
  der abgesetzte „?"-Hilfe-Knopf zieht in die per-Screen-Header (Recon §2.5).
- **Löschungen:** `UI/LiquidTabBar.swift` komplett (Linse, Wiggle, Badge-Kapsel);
  in `Content/TabBarLogic.swift` die Dock-Breiten-Mathe und `wiggleKeyframes`
  (`badgeText`/`shouldScrollToTop` bleiben samt Tests); `visitedTabs`/`tabPane`-Mechanik,
  Keyboard-Notifications und `LayoutMetrics.dockMax` (Recon §2.9).

### 3.8 Logo-Ebenen-Spec: „Das versiegelte Polaroid" (AppIconKit, 9+1 Paletten)

Vier Ebenen, prozedural in `ios/scripts/GenerateIcon.swift` (CI-Aufruf
`swift ios/scripts/GenerateIcon.swift <out> <variant>` bleibt identisch); die
`Palette`-Struct behält alle Felder — die neue Geometrie liest sie so:

| Ebene (hinten → vorn) | Inhalt | Geometrie | Paletten-Slot |
|---|---|---|---|
| **L1 Zimmer** | Varianten-Verlauf + radialer Lichtkegel von 10 Uhr | vollflächig | `bg` (3 Stops); Kegel-Farbe aus `glow` |
| **L2 Papier** | `Papier.brief`-Blatt, `Radius.polaroid`, unten `TornEdgeShape`-Riss | Rotation −6°, 78 % Icon-Breite, optisches Zentrum leicht über Mitte | invariant (Papier ist die Marke); Kantenlicht aus `rim` |
| **L3 Licht** | weicher radialer Lampenglow über der Papier-Oberkante | Zentrum 10-Uhr-Ecke | `glow`; im Tinted-Modus trägt diese Ebene den System-Tint |
| **L4 Siegel** | Wachssiegel mit Herz-Prägung, Prägetinte via `onWax`-Regel | Ø 34 % Icon-Breite, auf dem Riss sitzend, Rotation +3° | `pane`-Verlauf (3 Stops = Wachs); Lichtpfütze an der Siegel-Unterkante aus `caustic` |

`aurora` wird von der neuen Geometrie nicht mehr gelesen (Daten bleiben, kein Struct-Umbau).
**Funktion über die 9+1 Varianten** (classic, sunset, midnight, mint, rose, ocean, gold,
lavender, blossom, aurora): L1/L4 nehmen die Varianten-Farben, L2/L3 sind invariant — Papier
und Lampenlicht sind die Marke, die Palette ist das Geschenk. iOS-Erscheinungsbilder:
Dark = Verlauf 20 % dunkler, Kegel 20 % stärker; Tinted = System-Tint auf L3;
Clear = L2 nur als Kontur-Glasrelief, L4 als Mono-Prägung. In-App spiegelt
`IconVariantPreview` (`AppIconKit.Variant`: `bg` → L1, `heart` → L4-Wachs) dieselben vier
Ebenen live nach; die `WidgetStudio`-Paletten-Spiegelung bleibt funktionsgleich. Repo bleibt
binärfrei — Icons rendert weiterhin CI.

**Pipeline-Entscheid (nach `RECON_NATIVE_IOS26.md` §4, Option B):** Ziel ist das echte
Layered-`.icon`-Package — `GenerateIcon.swift` rendert die Ebenen getrennt (L4 bewusst matt,
Specular macht die Engine), ein Emitter schreibt pro Palette das `icon.json`, CI-Gate ist der
headless `ictool`-Render aller 10 Icons. Das ist eine EIGENE Bau-Welle NACH der
TabView-Migration; bis dahin bleibt der flache PNG-Pfad (Option A) mit dem neuen
Polaroid-Motiv korrekt verdrahtet.

### 3.9 Kino-Dramaturgie (First Launch, ~60 s; Reduce Motion ~30 s)

Sieben Szenen; **Sprachwahl ist Szene 1 und wartet beliebig**. Skip ab Szene 2. Jede Szene
hat VoiceOver-Announcement und Reduce-Motion-Standbild. Hybrid-Regel aus
`RECON_REMOTION_PIPELINE.md` §3.7, wörtlich übernommen: **„Video = Kino (zuschauen),
prozedural = Bühne (fühlen)."** Alles Interaktive, alles mit Laufzeit-Paarfarben und die
Übergabe in die echte UI bleiben prozedural (`CinematicIntroView`/`CinematicScript`);
deterministische Schau-Szenen dürfen als Remotion-HEVC-Prolog vorgerendert werden
(`--codec=h265 --color-space=bt709 --muted`, textfrei — Text als SwiftUI-Overlay aus dem
`captions`-Manifest, Haptik aus dem `beats`-Manifest via `addBoundaryTimeObserver`;
Budget-Gate ≤ 40 MB; fehlende Videos sind legal → prozeduraler Fallback existiert für JEDE Szene).

| # | Zeit | Szene | Renderpfad |
|---|---|---|---|
| 1 | 0–8 s (wartet) | **Lampenklick.** Der Lichtkegel blendet auf und beleuchtet zwei Zettel: „Deutsch" / „English" (`Typo.brief`). Antippen wählt; der andere gleitet aus dem Licht. Haptik: `tap` beim Klick. | **prozedural-interaktiv** (Sprachwahl ist Funktion) |
| 2 | 8–16 s | Ein Umschlag schiebt sich in den Kegel, Anschrift „Für euch beide" (`Typo.anschrift`); der Poststempel stempelt sich auf — Prägung „TAG 1" (rigid-Haptik aus dem Manifest). | **Remotion-Video** (deterministisch, keine Laufzeitfarben) |
| 3 | 16–26 s | Das neutrale Wachssiegel bricht (bestehende Reveal-Klangwelt), der Brief entfaltet sich mit Blättern: „Ein Ort für zwei. Alles hier gehört nur euch." | **Remotion-Video** (Text als Overlay, Sound/Haptik aus SoundEngine + Manifest) |
| 4 | 26–38 s | **Zwei Tintenfässer:** „Wähl deine Farbe" — Tintentropfen fällt, zieht einen Strich; der Partner-Strich erscheint als Platzhalter-Schimmer; beide laufen aufeinander zu und mischen sich zum `blend`. | **prozedural-interaktiv** (Farbwahl + Live-Blend) |
| 5 | 38–46 s | Aus dem Blend gießt sich das **Wachssiegel** und prägt das Herz — „Das ist eure Farbe. Nur ihr zwei habt sie." (VoiceOver identisch). Der `.pairing`-Haptik-Moment. | **prozedural** (Laufzeit-`blend`, eine Clock für Bild+Haptik+Synth) |
| 6 | 46–54 s | Ein leeres Polaroid entwickelt sich von Weiß zu `Papier.polaroid` und bleibt leer: „Eure erste Erinnerung fehlt noch." | **Remotion-Video** (deterministisch; Reduce-Motion-Still via `posterTime`) |
| 7 | 54–60 s | Das Papier **legt** sich in den Home-Screen, die Glas-TabView gleitet von unten herauf — das Kino endet exakt in der echten UI, kein Schnitt. Pairing-Code folgt als erster Zettel. | **prozedural** (Übergabe in die Live-Hierarchie) |

Lite-Build bleibt prozedural-only (Videos per `excludes` ausgeschlossen, RECON §2.6).

### 3.10 Do / Don't

**Do (10):**
1. Jede Content-Karte ist opakes Papier (`Papier.brief`/`karton`) — nie transluzent.
2. Serifen (`voice`/`brief`/`anschrift`) erscheinen nur auf Papierflächen.
3. Paarfarben als Material einsetzen: Tintenkante, Wachssiegel, Band — immer durch
   `inkOnPaper`-/`onWax`-Verdicts.
4. Genau EINE Briefbogen-Karte (Band + Siegel) pro Screen — sie ist der Hero.
5. Lichtkante oben-links (+8 % Luminanz), `Elevation`-Schatten unten-rechts — die Lampe ist
   die eine Lichtquelle.
6. Jede Rotation und jeder Riss ist seeded mit stabiler Item-ID — nichts flackert zwischen
   Renders.
7. Natives TabView-System pur nutzen: `tint`, Minimize, Accessory, Badges — nichts auf die
   Bar malen.
8. Der Siegelbruch ist der eine laute Moment (Haptik + Klang) — alles andere bleibt leise.
9. Leere Zustände als Einladung auf Papier erzählen (leeres Polaroid, Verb + Button).
10. Papierkorn nur als statischer Shader ≤ 2 % Luminanz; unter Increased Contrast aus.

**Don't (10):**
1. Keine Bitmap-Texturen — Papier, Korn und Risse sind ausschließlich prozedural.
2. Keine Fake-Handschrift, keine Skript-Fonts — Intimität kommt aus New York, nicht aus
   Kalligrafie-Imitat.
3. Kein Vergilbungs-/Sepia-Filter auf Fotos oder Papier.
4. Nie mehr als 3 Papier-Artefakte pro Screen (Siegel, Klebeecke, Stempel zählen).
5. Nie mehr als 1 gerissene Kante und 1 Rotation pro Screen.
6. `Licht.lampengold` nie als Text auf Papier (1,4:1) — nur als Glow hinter Kanten.
7. `Wachs.rot` nie als Text auf Nacht (3,0:1) — Wachs ist Material, kein Ink.
8. Kein Papier auf Glas — Papier liegt immer unter dem Chrome.
9. Kein Glas mehr an Content-Karten — `GlassLevel.surface`/`.tinted` sterben ersatzlos.
10. Keine vier Klebeecken, keine Stempel-Inflation — jede Karte muss auch ohne alle
    Artefakte funktionieren.

### 3.11 Die 5 größten Migrations-Brocken im Bestand

1. **`UI/Theme.swift` + `UI/Glass.swift` — der Material-Tausch.** `glassCard()` ist der
   Choke-Point: 323 Aufrufstellen in 101 Dateien wechseln über EINEN Modifier auf
   `paperCard(_:)`; `GlassLevel.surface`/`.tinted` entfallen, `PaperLevel` (brief/karton/
   polaroid/briefbogen) entsteht; neue Token-Familien Papier/Tinte/Licht/Wachs; `Radius.papier`
   und `Radius.polaroid`; `DreamyBackground` → Zimmer-Canvas (Drop-in: gleiche Props- und
   Drossel-Signatur, `showStars` → Tintenstaub).
2. **`Content/PersonalizationLogic.swift` — die Verdict-Verankerung.**
   `darkBackground` `#17062A` → `#201613`; neue Leiter `inkOnPaper(hex)` gegen `#F7F1E4`;
   die komplette LogicTest-Matrix (Verdicts, Scrim-Rungs, `accentOnLight`, `onWax`) wird
   einmalig neu gebaselined — ein bewusster Test-Commit, kein Nebeneffekt.
3. **`MainTabView`/`RootView` + `UI/LiquidTabBar.swift` + `Content/TabBarLogic.swift` — die
   native Bar.** `LiquidTabBar.swift` wird gelöscht (Linse, Wiggle, Badge-Kapsel, nicht
   portiert); `visitedTabs`/`tabPane`, Keyboard-Notifications und `dockMax` entfallen;
   `TabBarLogic` schrumpft auf `badgeText`/`shouldScrollToTop` (Tests bleiben für genau
   diese); echte `TabView` mit `Tab`-Buildern, `.tint(blend)`, Minimize-Behavior,
   Heute-Zettel-Accessory — Reihenfolge und SDK-Verifikationsliste aus
   `RECON_NATIVE_IOS26.md` §2.9/§1.5 sind bindend.
4. **`Features/Chat/` — der Zettelwechsel.** Bubble-Chat wird Briefwechsel: brief/karton-Zettel
   mit Tintenkante, Poststempel-Tagestrenner, versiegelte Briefe mit Siegelbruch,
   Mini-Polaroid-Sticker — der größte Feature-Einzelumbau der Migration (Eingabeleiste bleibt
   Chrome-Glas).
5. **`ios/scripts/GenerateIcon.swift` + `AppIconKit`/`IconGiftView` + Kino-Pipeline.** Neues
   4-Ebenen-Motiv „versiegeltes Polaroid" über alle 9+1 Paletten (Palette-Struct-Felder
   bleiben, `aurora` ungenutzt); `IconVariantPreview` zeichnet die Ebenen live nach;
   `CinematicScript`/`CinematicIntroView` bekommen die 7-Szenen-Dramaturgie plus den
   Remotion-Prolog (`SoooDreamy/remotion/`, `render-videos`-CI-Job, Manifest-Observer,
   prozeduraler Fallback) gemäß `RECON_REMOTION_PIPELINE.md`.

---

## 4. Ratchet-Fortschreibung (DESIGN.md)

### Bleibt wörtlich in Kraft

- **Gebote 1–10, 12, 13, 14, 15** — unverändert. Insbesondere: Emoji-Gesetze, Fehler-Auswege,
  fünf Zustände, Feier-Budget, Frame-Antwort, Biografie-Zahlen (die Poststempel-Prägung
  „TAG 137" ist deren Materialisierung, kein neues Gesetz).
- **Glas-auf-Glas-Verbot, Text-Verlauf-Verbot, `brandTitle` als einzige Titel-Behandlung,
  Noble-Test, `motionGate`, 4er-Raster (`Space`), Konzentrizitätsregel.**
- **Dark-only bleibt Marken-Gesetz** — neu erzählt als „Lampenlicht-first": Briefe liest man
  bei Lampenlicht; das helle, warme Gefühl liefert das Papier als Inhalt, nicht ein Light Mode.
- **`voice`-Heiligkeit** — Serif italic bleibt exklusiv für Worte der Partner.

### Wird präzisiert

- **Gebot 11 (Tokens):** Die Token-Familien wachsen um `Papier.*`, `Tinte.*`, `Licht.*`,
  `Wachs.*`, `PaperLevel`, `Radius.papier/polaroid`, `PaperTilt`, `TornEdgeShape` — Rohwerte
  weiterhin NUR in `ios/SoooDreamy/UI/`.
- **Glas-Stufen-Tabelle (d):** `chrome` bleibt; `surface`/`tinted` werden durch `PaperLevel`
  ersetzt; neues Verbot **„Papier-auf-Glas"** tritt neben „Glas-auf-Glas".
- **10-Uhr-Licht:** Regel identisch, Erzählung neu — die Lampe ist die Lichtquelle; die
  1-pt-Lichtkante wird benanntes Token.
- **Typo-Abschnitt:** `brief` und `anschrift` kommen dazu; neues Gesetz **„Serif nur auf
  Papier"**; `anschrift` ist der einzige Kapitälchen-Einsatz.
- **Kontrast-Abschnitt:** Der 4,5:1-Boden bekommt ZWEI Anker — `#201613` (Nacht, via
  `darkBackground`) und `#F7F1E4` (Papier, via `inkOnPaper`); beide maschinell, nie geschätzt.

### Neue CI-prüfbare Regeln

1. **`surface_glass_features` (neuer Ratchet):** Vorkommen von `glassCard(` /
   `GlassLevel.surface` / `GlassLevel.tinted` in Features. Baseline = Ist-Stand beim
   Migrationsstart, Ziel 0 — der Zähler macht den Papier-Fortschritt der Bau-Wellen messbar.
2. **`raw_rotation_features` (neuer Ratchet):** freihändige `.rotationEffect(` in Features —
   Rotation existiert nur über das seeded `PaperTilt`-Token der UI-Schicht.
3. **`smallcaps_features` (neuer Ratchet, auf 0 gepinnt):** `.smallCaps()` außerhalb `UI/` —
   `Typo.anschrift` ist der einzige legale Kapitälchen-Einsatz.
4. **`torn_edge_uses` (Deckel):** `TornEdgeShape`-Verwendungen app-weit ≤ 6 — ein Deckel,
   kein sinkender Zähler; Risse sind Ausnahme, nicht Rhythmus.
5. **Korn-Deckel als LogicTest:** `PaperRules.grainLuminance == 0.02` gepinnt (Konstante in
   der Foundation-Schicht); Test bricht bei jeder Erhöhung; unter Increased Contrast 0.
6. **`inkOnPaper`-Verdict-Matrix als LogicTest gepinnt:** alle 8 `memberColors` × 4
   Papiertöne ≥ 4,5:1, plus 3 Tinten × 4 Papiere — dieselbe Pin-Disziplin wie die bestehende
   `PersonalizationLogic`-Matrix, gegen den neuen Doppel-Anker.
7. **Kino-Gates (aus `RECON_REMOTION_PIPELINE.md`):** Video-Budget ≤ 40 MB fail-closed,
   Determinismus-Hash-Test (Doppel-Render, SHA-256), Manifest-Kreuz-Check (`beats`/`cues`/
   `captions` < `durationSec`, Cue-IDs im AppCue-Katalog).

### Erwartete Bewegung der bestehenden Zähler

`bare_white_opacity` (69) und `raw_corner_radius` (57) sinken strukturell durch die
Token-Migration; `hardcoded_pink_purple_features` (5) geht auf 0 (Stock-Rosa verliert seine
letzten Chrome-Rollen an `Licht.*` und `CoupleTint`); `ultrathin_material_features` bleibt
auf 0 gepinnt. Bewusst NICHT automatisiert (Review-Ritual, neue Noble-Test-Frage 11
**„Artefakt-Inventur"**): max. 3 Papier-Artefakte, max. 1 Riss, max. 1 Rotation pro Screen —
Geschmack bleibt Handarbeit, sonst entsteht regelkonforme Seelenlosigkeit.

---

*Jury-Vorsitz, Stil-Wettbewerb SoooDreamy. Ein Gewinner, eine Anleihe, ein Bau-Dokument —
kein Stil-Brei. Die Bau-Wellen setzen Abschnitt 3 wörtlich um; Abschnitt 4 wandert bei der
ersten Bau-Welle in DESIGN.md und `tools/charter_baseline.json`.*
