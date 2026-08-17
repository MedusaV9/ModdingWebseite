# DESIGN.md — Die SoooDreamy-Qualitätscharta

Verbindlich. Jede Änderung an SoooDreamy wird gegen dieses Dokument geprüft — von Menschen im
Review und von Werkzeugen in CI (`tools/charter_lint.sh`, Ratchet-Prinzip: die Slop-Zähler
dürfen nur sinken). Wer eine View anfasst, liest vorher dieses Dokument. Wer eine neue Farbe,
Feder oder Transparenz braucht, benennt sie zuerst im Token-System (Abschnitt D), dann benutzt
er sie.

---

## (a) Die 15 Gebote der SoooDreamy-Qualität

**1. Kein Emoji ist ein Icon.**
Emoji gehören dem Paar (Avatare, Nachrichten, Partikel-Themes) — sobald sie UI-Chrome werden
(Section-Header, Buttons, Platzhalter-Glyphen), sieht die App aus wie ein Prototyp aus einem
Prompt. Icons sind SF Symbols oder eigene Assets, die auf Gewicht, Baseline und Tint der
Typografie antworten — ein 34-pt-💭 tut das nie.
*Ratchet:* `emoji_as_text`. Review-Frage: „Wenn ich dieses Emoji durch ein SF Symbol ersetze —
wird die View besser? Dann war es ein Icon."

**2. Emotion steht im Satz, nicht am Satzende.**
„Ihr seid wieder verbunden. 💜" ist die Textsorte, die der Owner „AI-Slop" nennt: Das Emoji
soll Wärme liefern, die der Satz nicht hat. Ein guter Satz braucht keinen Anhänger.
*Ratchet:* `emoji_in_de_copy`. Review-Frage: „Streiche das Emoji. Fehlt etwas? Wenn ja: den
Satz umschreiben, nicht das Emoji zurückholen."

**3. Jede Aktion hat hörbares ODER fühlbares Feedback — nie keins, selten beides laut.**
`Haptics`/`SoundEngine` existieren genau dafür; eine Berührung ohne jede Antwort fühlt sich tot
an, eine mit Klick UND Klang UND Pop wie ein Spielautomat. Primäre Aktionen haptisch leise
(`tap`), Höhepunkte dürfen Klang tragen — beides laut nur bei den ~3 Momenten pro Feature, die
es verdient haben.
Review-Frage pro neuem `Button`: „Welche Zeile antwortet dem Finger?"

**4. Eine Feier pro Bildschirm-Sitzung — und `epic` ist verdient, nicht Default.**
13 Aufrufstellen feuern `.epic`, fast jedes Spielende ist „episch", also ist nichts mehr
episch. Milestone-Entscheidungen gehören in `DelightRules` (pur, testbar), nie in die View;
pro Screen-Session maximal eine Celebration, `epic` nur für Ereignisse, die pro Monat
einstellig vorkommen.
*Ratchet:* `epic_celebrations`. Review-Frage: „Wie oft pro Woche sieht ein aktives Paar diese
Feier? Öfter als 1× → eine Stufe runter."

**5. Jeder Fehlertext nennt einen Ausweg.**
`state.failed.body` macht es vor („Eure Daten sind nicht weg. Prüft die Verbindung und versucht
es erneut.") — `common.error` („Ups, das hat nicht geklappt") macht es kaputt. Ein Fehlertext
ohne nächsten Schritt ist kein Text, sondern ein Achselzucken. Drei Bestandteile: Was ist
passiert · Was ist NICHT passiert (Daten sicher?) · Was tue ich jetzt.
Review-Frage: „Steht im Fehlertext ein Verb im Imperativ?"

**6. Kein Fehler verschwindet stumm.**
Jedes `try? await` ist eine Stelle, an der ein Netzwerkfehler wie ein leerer Zustand aussieht —
emotional das Gegenteil der Wahrheit. `try?` ist nur erlaubt, wenn der Fallback in derselben
Zeile sichtbar und semantisch korrekt ist (Cache, deterministischer Default); sonst Toast,
StateCard oder Retry.
*Ratchet:* `try_await_api` — gemessen werden echte API-/IO-Aufrufe; `try? await Task.sleep`
ist eine Choreografie-Pause und zählt bewusst nicht (sonst versteckt das Rauschen die echten
verschluckten Fehler). Review-Frage: „Wenn dieser Call fehlschlägt: Sieht der Screen
dann aus wie ‚es gibt nichts' oder wie ‚es ging nicht'?"

**7. Warten sieht aus wie „gleich da", nicht wie „vielleicht nie".**
Nackte `ProgressView()` kommunizieren Stillstand; Skeletons in der Form des kommenden Inhalts
kommunizieren Ankunft. Spinner sind nur in Buttons für Sub-Sekunden-Aktionen erlaubt; Listen
und Karten bekommen `GlassSkeleton`-Platzhalter.
*Ratchet:* `bare_progressview`. Review-Frage: „Weiß der Nutzer während des Ladens schon, WAS
gleich da sein wird?"

**8. Jede Oberfläche kennt ihre fünf Zustände.**
`PolishAudit.swift` ist der Vertrag: loading/empty/content/offline/failure, und keine
Oberfläche darf Netzwerkfehler still in Leere verwandeln. Jede neue View wird erst gemerged,
wenn sie in `AuditedSurface` eingetragen ist und alle fünf Zustände designed sind — der leere
Zustand ist eine Einladung mit Handlung, kein grauer Satz.
Review-Frage: „Zeig mir Screenshot oder Preview aller fünf Zustände."

**9. Deutsch klingt wie geschrieben, nicht wie übersetzt.**
Deutsch ist die Erstsprache, nicht das Übersetzungsziel — ganze Satz-Templates in L10n
(`{name} ist da`), nie String-Konkatenation, konsistente Anrede (das Paar ist „ihr", der
Einzelne „du", die App sagt nie „wir" über sich selbst). Jeder Satz muss den Vorlese-Test
bestehen.
Review-Frage: „Würde ein Mensch das seinem Partner so schreiben?"

**10. Ausrufezeichen sind Feiertage.**
Wenn alles ruft, hört man nichts mehr. Ausrufezeichen sind reserviert für die 2–3 echten
Höhepunkte (Partner gepairt, Jahrestag); Bestätigungen, Toasts und Settings sprechen im
Aussagesatz.
*Ratchet:* `bang_strings_de`. Review-Frage: „Ist dieser Moment wichtiger als ‚ihr habt euch
gefunden'? Nein → Punkt statt Ausrufezeichen."

**11. Motion, Farbe und Transparenz sind Tokens, keine Freihandwerte.**
Jede neue Animation und jede neue Fläche referenziert einen benannten Token (`Theme.Motion.*`,
`Theme.innerFill`, `Theme.hairline`, `Space.*`, `Radius.*`, `Elevation`); ein neuer Wert wird
zuerst im Theme benannt, dann benutzt. Rohwerte dürfen ausschließlich in der
Design-System-Schicht (`ios/SoooDreamy/UI/`) existieren — kontrastkritische Hexwerte konsumiert
das Theme aus der Foundation-Gesetzestafel (`PaperRules`, `CouplePaletteRules`), damit die
Logic-Tests exakt das pinnen, was rendert. Seit „Papier & Licht" wachsen die Token-Familien um
`Papier.*`, `Tinte.*`, `Licht.*`, `Wachs.*`, `PaperLevel`, `Radius.papier`/`polaroid`,
`PaperTilt` und `TornEdgeShape`.
*Ratchets:* `spring_literals`, `easing_literals`, `bare_white_opacity`, `raw_corner_radius`,
`hardcoded_pink_purple_features`, `ultrathin_material_features`, `surface_glass_features`,
`raw_rotation_features`, `smallcaps_features` (+ Deckel `torn_edge_uses`). Review-Frage: „Wie
heißt dieser Wert im Theme?"

**12. Text skaliert mit dem Nutzer.**
`Font.scaled(fixe Punktzahl)` ignoriert Dynamic Type — für eine App, die täglich gelesen wird,
ist das keine Politur-Lücke, sondern eine Barriere. Fließtext und Labels nutzen die
semantischen Rollen aus `Typo` (bauen auf `.body`/`.headline`/… auf); `Font.scaled` ist nur für
Hero-Zahlen und dekorative Glyphen legitim.
*Ratchets:* `fixed_font_sizes`, `system_size_fonts`. Review-Frage: „Screenshot bei
AX5-Schriftgröße: Ist alles lesbar und nichts abgeschnitten?" — CI beantwortet sie mit dem
`paired-ax5-de.png`-Shot der Screenshot-Matrix.

**13. Jeder magische Moment ist ohne Augen und ohne Bewegung erlebbar.**
Jede Choreografie liefert drei Pfade ab Merge: visuell, haptisch+angesagt (VoiceOver mit
`AccessibilityNotification.Announcement`), reduziert (Reduce Motion — Glow statt Partikel).
Vorbild: `StarFieldView` wird unter Reduce Motion ein Gemälde, kein schwarzes Loch.
Review-Frage: „Erzähl mir diesen Moment mit geschlossenen Augen."

**14. Die UI antwortet sofort — der Server bestätigt nur.**
Ein Häkchen, das 300–800 ms auf die Server-Antwort wartet, ist der Haupteindruck von
„Lahmheit". Jeder Toggle und jede Klein-Aktion mutiert den lokalen Zustand im selben Frame,
der Request läuft hinterher, Fehler rollen sichtbar zurück.
Review-Frage pro neuem Toggle: „Was passiert im Frame des Taps?"

**15. Zahlen über die Beziehung sind Biografie, kein Spielstand.**
`🔥 137` ist Duolingo-Grammatik in einer Liebes-App. Zähler heißen „137 gemeinsame Tage",
verlieren nie (eine Serie „ruht", sie stirbt nicht), und kein Rot, kein leeres Flammen-Icon,
keine Verlust-Sprache erscheint je neben einer Zahl, die das Paar beschreibt.
Review-Frage: „Würde diese Formulierung auf einer Jubiläumskarte stehen können?"

---

## (b) Slop-Symptom-Katalog (Anti-Beispiele aus dem echten Code)

1. **Emoji als Section-Icon** — Dashboard-Gruppen mit „💞/🎮", `Text("💭").font(.scaled(34))`
   als Platzhalter-„Icon".
2. **🔥-Zahl als Beziehungsmaß** — `PillTag(text: "🔥 \(streak)")` im intimsten Ritual der App.
3. **Deko-💜 am Satzende** — „Willkommen zurück! Ihr seid wieder verbunden. 💜".
4. **Ausrufezeichen-plus-🎉-Inflation** — „HEUTE! 🎉", „Kopiert!": die App schreit bei
   Copy-to-Clipboard genauso laut wie beim Pairing.
5. **Epic-Konfetti als Normalfall** — jedes Spielende feiert episch, die Drei-Stufen-Sprache
   von `Delight` wird plattgedrückt.
6. **„Ups"-Fehler ohne Ausweg** — kein Was, kein Warum, kein Weiter.
7. **Stumm verschluckte Fehler** — `try? await` rendert Serverfehler als leeres Leben.
8. **Spinner-Wald** — der Kern-Screen wartet mit demselben anonymen Kreisel wie ein
   Formular-Upload.
9. **Freihand-Werte statt Tokens** — `spring(response: 0.3/0.35/0.4/0.8)` je nach Datei,
   `white.opacity(0.05…0.15)` dutzendfach quer durch die Features.
10. **Einheits-Tap** — fast jede Berührung fühlt sich exakt gleich an, die feinen Werkzeuge
    (`HapticPatternKit`) verhungern daneben.
11. **Fixe Punktgrößen überall** — `.scaled(<Zahl>)` ignoriert die Schriftgrößen-Einstellung
    des Nutzers vollständig.
12. **Versions-Graffiti** — `// v3.0 (Agent C)`-Kommentare erzählen die Entstehungsgeschichte
    statt des Warums; die sichtbarste AI-Slop-Signatur im Code.

---

## (c) Der Noble-Test: 11 Fragen an jede neue View

1. **Der eine Moment:** Welcher einzelne Moment dieser View soll sich besonders anfühlen — und
   sind alle anderen bewusst leise? (Keine Antwort = die View hat keinen Kern.)
2. **Der Streich-Test:** Was wurde beim Bauen weggelassen? Eine noble View ist definiert durch
   das, was sie nicht zeigt.
3. **Flugmodus an:** Was genau sehe ich? Gecachter Inhalt mit Hinweis, oder ein Loch, oder —
   schlimmer — ein falsches „hier ist nichts"?
4. **Erster Start, null Daten:** Lädt der leere Zustand zum ersten Schritt ein (mit Verb, mit
   Button), oder entschuldigt er sich nur?
5. **Vorlese-Test:** Jeden deutschen Satz der View laut lesen. Klingt einer nach Übersetzung,
   Bedienungsanleitung oder LinkedIn — umschreiben.
6. **Emoji-Inventur:** Ist jedes Emoji dieser View Inhalt des Paares — oder hat sich eines als
   Icon, Header-Schmuck oder Satz-Deko eingeschlichen?
7. **Token-Probe:** Stammen alle Farben, Transparenzen, Radien und Federkurven aus dem
   Token-System — oder stehen hier neue nackte Zahlen?
8. **Augen zu:** Lässt sich der Kern-Moment mit VoiceOver erleben (Ansage + Haptik)? Existiert
   ein Reduce-Motion-Pfad, der nicht „nichts" ist, sondern die leise Version?
9. **Frame-Antwort:** Reagiert jede Berührung im selben Frame sichtbar oder fühlbar — auch wenn
   der Server 800 ms braucht?
10. **Der Geschenk-Test:** Würde man diesen Screen dem eigenen Partner zeigen und sagen „das
    habe ich für uns gebaut" — oder erkennt das Auge ein Template für beliebige zwei Menschen?
11. **Artefakt-Inventur:** Zähle die Papier-Artefakte (Siegel, Klebeecken, Stempel), Risse und
    Rotationen dieses Screens: mehr als 3 / 1 / 1 — welches fliegt? Und funktioniert die Karte
    auch ganz ohne sie?

Jede PR-Beschreibung beantwortet Frage 1 („der eine Moment"), 2 („was wurde gestrichen") und
3 („Flugmodus") in je einem Satz.

---

## (d) Das Token-System (`ios/SoooDreamy/UI/`)

Die Design-System-Schicht ist der EINZIGE Ort für Rohwerte. Features referenzieren Namen.

### Das Zwei-Materialien-Gesetz (`Glass.swift`)

Die App besteht aus genau zwei Materialien — nichts ist beides:

| Material | Was | Verhalten |
|----------|-----|-----------|
| **System-Glas** (`GlassLevel.chrome`) | ALLES was schwebt: native TabView, Toolbar-Buttons, FAB/PulseFan, Chat-Eingabeleiste, Sheet-Chrome, Toasts | echtes `glassEffect(.regular)` + `Elevation.floating`; das System rendert Refraktion/Kante, Inhalte scrollen darunter durch |
| **Papier** (`PaperLevel`) | ALLES was liegt: Content-Karten, Chat-Zettel, Spielkarten, Polaroids, Listen | opak, matt, `Elevation`-Schatten unten-rechts, 1-pt-Lichtkante oben-links (`Papier.lichtkante`) |

`PaperLevel`-Stufen: `.brief` (Standard, `paperCard()`-Default) · `.karton` (Sekundär/Partner) ·
`.polaroid` (nur Fotos) · `.briefbogen` (Hero: `Papier.brief` + Paar-Band + Wachssiegel — genau
EINE pro Screen, erbt die Hero-Regel). Die alten Stufen `GlassLevel.surface`/`.tinted` sind
**deprecated**: funktional, solange die Screen-Wellen die `glassCard()`-Aufrufstellen migrieren
(Ratchet `surface_glass_features` zählt sie auf 0), aber in neuem Code tabu.

**Verbotsregeln:**
- **Glas auf Glas ist verboten.** Innere Flächen in einer Glass-Card sind matte Füllungen
  (`Theme.innerFill`), nie ein zweites Material.
- **Papier auf Glas ist verboten.** Papier liegt immer UNTER dem Chrome; die eine sanktionierte
  Berührung ist das System-TabView-Accessory (Heute-Zettel).
- **Kein Glas-Nachbau ÜBER echtem Glas.** Keine `ultraThinMaterial`-Schichten,
  Refraktions-Gradients oder Specular-Strokes auf `glassEffect` malen — das System rendert
  Refraktion, Kante und Adaptivität selbst (und besser).
- **Innenflächen auf Papier** sind `Papier.innenFill`-Washes (`Tinte.dunkel @ 0.05`) mit
  `Papier.kante`-Hairline — nie ein zweites Material.
- **Papierkorn** ist prozedural und statisch, Luminanz-Deckel `PaperRules.grainLuminance`
  (± 2 %, LogicTest-gepinnt); unter Increased Contrast aus, unter Text < `.subheadline` nicht
  gerendert. Keine Bitmap-Texturen — nirgends.
- **Farbige Glow-Schatten** gibt es nur für Hero-Panes und Stufe-3-Feiern; alles andere
  wirft neutrale `Elevation`-Schatten.

### Licht-Logik (10-Uhr-Regel — die Lampe)

Eine Lichtquelle, überall — und sie hat jetzt einen Namen: die Lampe. Licht kommt von der
10-Uhr-Position; jede Papierkarte trägt oben-links die benannte 1-pt-Lichtkante
(`Papier.lichtkante` = `Papier.brief` + 8 % Luminanz, LogicTest-gepinnt) und wirft den
`Elevation`-Schatten nach unten-rechts. Innenschatten (Panel-Dicke) unten. Jede Ebene weiter
vorn = hellere Kante + weicherer, größerer Schatten (`resting → raised → floating`).

### Radien (`Radius`, konzentrisch)

`pane = 28` (Screens/Sheets) · `card = 22` (Glas-Cards) · `control = 14` (Buttons/Felder in
Cards) · **`papier = 10`** (alle Papierkarten — geschnittenes Papier ist schärfer als Glas) ·
**`polaroid = 4`** (Fotorahmen) · Chips/Pills = `Capsule()`. Konzentrizität: innerer Radius =
äußerer Radius − Padding — `Radius.concentric(parent:padding:)`. Kanten-Formen: Gestanzt
(glattes `RoundedRectangle`, 90 % aller Karten) · Gerissen (`TornEdgeShape`: EINE Kante,
seeded, max. 1 pro Screen, app-weit ≤ 6) · Coupon-Scallop (Gutscheine). Rotation NUR über das
seeded `PaperTilt`-Token (−6°…+6°, max. 1 rotiertes Element pro Screen).

### Abstände (`Space`, 4er-Raster)

`xs = 4` · `s = 8` · `m = 12` · `l = 16` · `xl = 24` · `xxl = 32`. Keine `s(7)`/`s(13)`-Werte
mehr in View-Code — inkonsistenter Rhythmus liest das Auge als Billigkeit.

### Motion (`Theme.Motion`)

| Kurve | Einsatz |
|-------|---------|
| `settle` | Zustandswechsel, Auswahl, Toggles |
| `arrive` | Einblendungen, Sheets, Banner |
| `playful` | NUR Herz/Streak/Spiel-Momente — nie für Navigation |
| `drift(seconds)` | Ambient (Zimmer-Canvas, Staub, Partikel) |

Pro Interaktion genau eine Kurve. Eine fünfte Kurve gibt es nicht — wer eine braucht, benennt
sie hier und begründet es im PR. Die drei **Motion-Signaturen** von Papier & Licht sind
benannte Aliasse auf diesen Kurven (Parameter in `Theme.Motion.Signature`), jede mit
dokumentiertem Reduce-Motion-Pfad:

| Signatur | Kurve | Bewegung | Reduce Motion |
|----------|-------|----------|---------------|
| `blaettern` (Screen-/Hero-Einstieg) | `arrive` | Karte rotiert um die führende Kante herein (−12° → 0°, `anchor: .leading`, Perspektive 0.3); Schatten wandert x −4 → +1 | reiner Crossfade |
| `legen` (Elemente erscheinen) | `settle` | Zettel landet: Scale 1.04 → 1.0, y 6 → 0, Schatten 24 → 14; Stagger 40 ms, max. 6 Elemente | Fade ohne Transform |
| `lichtschein` (Feier-Moment, Delight 1–2) | `drift(1.2)` | radialer `Licht.lampengold`-Glow blüht (0 → 0.35 → 0.22, Radius 1.4×) und BLEIBT | statischer End-Glow sofort |

### Typo-Rollen (`Typo`)

`hero` (max. 1×/Screen) · `title` · `body` · `label` · `caption` · `number` (monospacedDigit —
Streak, Stats, Level; Zahlen sind Druckwerk, nie Serif) · **`voice`** (Serif italic — die
„Stimme der Beziehung": NUR für Worte, die die Partner selbst geschrieben haben: Wochen-Zitat,
Journal-/Kapsel-Texte, Jahrestags-Titel. Nirgendwo sonst) · **`brief`** (New York `.body` —
Brief-KÖRPER beim Lesen: LetterComposer/Reader, Journal-Volltext) · **`anschrift`** (New York
`.caption` semibold Kapitälchen — Poststempel, Datumszeilen auf Papier, „Für dich"-Zeilen; ab
Accessibility-Größen ohne Kapitälchen). Rounded = „die App spricht" (gedruckt), New York =
„von euch geschrieben" (Feder). **Serif erscheint AUSSCHLIESSLICH auf Papierflächen** — nie
auf Glas, nie auf Nacht. `anschrift` ist der EINZIGE Kapitälchen-Einsatz der App (Ratchet
`smallcaps_features`, auf 0 gepinnt).

### Farbe (`CoupleTint`, `@Environment(\.coupleTint)`)

Tints werden aus den Paar-Farben abgeleitet, nicht hartkodiert: `primary`/`secondary` (die
beiden Mitglieder), `blend` (die gemeinsame Farbe des Paares, kontrastgesichert — DIE Signatur
für Meilensteine und Herz-Features), `onBlend`, `heroGradient` (zwei Stops aus den
Paar-Farben). `Theme.heroGradient` ist die **„goldene Tinte"** — Lampengold → Kupfer aus der
PaperRules-Gesetzestafel (`heroGradientFirstHex`/`kupferHex`, LogicTest-gepinnt); sie trägt
das statische Brand-Chrome (aktiver Page-Dot, Hero-Platter) und den Vor-Pairing-Fallback des
CoupleTint (Wordmark = Vollton Lampengold). Der Pink→Purple-Verlauf der Generic-Ära ist
restlos Geschichte. Verläufe: max. zwei Farbstopps, auf Text gar kein Verlauf.

**Paarfarben als Material (Papier & Licht):** Auf Papier sind die Paarfarben Schreibmaterial,
nie Fließtext (der bleibt `Tinte.dunkel`): `coupleTint.tintePrimary`/`tinteSecondary` (deine
Tinte / meine Tinte, durch die `inkOnPaper`-Leiter ≥ 4,5:1 auf JEDEM Papierton), `tinte`
(die gemeinsame Tinte = `inkOnPaper(blend)` — trägt `brandTitle` auf Papier), `wachs` (= `blend`
als Siegelmaterial, Prägetinte bleibt `onWax`), `band` (= `heroGradient` als 6-pt-Objekt um die
eine Briefbogen-Karte — der Verlauf verlässt die Fläche und wird Ding). Einsatz der Tinten:
4-pt-Tintenkante an Chat-Zetteln, Unterschrift-Linien, Avatarringe.

**Kontrast-Doppel-Anker (Gesetz, maschinell, nie geschätzt):** Der 4,5:1-Boden hat ZWEI Anker —
**Nacht** `#201613` (`CouplePaletteRules.darkBackground`, das Zimmer-Sepia; löste das violette
`#17062A` ab) und **Papier** `#F7F1E4` (`CouplePaletteRules.inkOnPaper`, gerechnet gegen alle
vier Papiertöne — die dunkelste Fläche `Papier.kante` bindet). Beide Anker und die kompletten
Verdict-Matrizen (alle memberColor-Paare) sind in `PersonalizationLogicTests`/`PaperRulesTests`
gepinnt. `Licht.lampengold` ist nie Text auf Papier (1,4:1), `Wachs.rot` nie Text auf Nacht
(3,0:1), `Papier.kante` trägt nie Text (`Tinte.tertiaer` dort 4,45:1 — bewusst unter dem Boden
gepinnt).

**Text-Verlauf-Regel (verbindlich seit der Design-Eval):** Auf Text existiert KEIN Verlauf —
nirgendwo, auch nicht auf Hero-Zahlen. Marken- und Bereichs-Titel tragen den EINEN benannten
Stil `.brandTitle(…)` (UI-Schicht): rounded-heavy Typo in Vollton `coupleTint.blend`. Wer
einen Titel baut, ruft den Stil auf, statt Farben zu wählen — so ist die gemeinsame Farbe des
Paares die Signatur jedes Titels, und das fünffach kopierte 3-Stopp-Verlaufsmuster kann nicht
zurückkehren. Zeremonien-Gold (Reveal, Level-Up, Badges) ist ebenfalls Vollton (`Theme.gold`).

### Lampenlicht-first: Dark Mode only (bewusste Marken-Entscheidung)

SoooDreamy erzwingt `preferredColorScheme(.dark)` — es gibt KEINEN Light Mode, und das ist
Absicht, keine Auslassung: Die App ist das Zimmer des Paares am Abend — Briefe liest man bei
Lampenlicht, ihre intimen Momente (Reveal-Zeremonie, Abend-Check-in, Pulse) spielen abends.
Das helle, warme Gefühl liefert das PAPIER als Inhalt (60–70 % der Content-Fläche), nicht ein
Light Mode. Ein Light Mode würde das gesamte Token-System (Elevation-Schatten, Materialien,
`bare_white_opacity`-Budget) verdoppeln, ohne die eine Geschichte besser zu erzählen.
Konsequenz für Reviews: „sieht im Light Mode kaputt aus" ist kein Bug — es gibt keinen;
Kontrast wird ausschließlich gegen die beiden Anker geprüft (`CouplePaletteRules` sichert
4,5:1 für Akzente auf Nacht `#201613` und für Tinten auf Papier `#F7F1E4`).

### Kitsch-Leitplanken (Papier & Licht — Geschmack mit harten Zahlen)

Skeuomorphismus kippt schnell in Bastelladen; die Leitplanken sind Gesetz: **max. 3
Papier-Artefakte pro Screen** (Wachssiegel, Klebeecke, Poststempel zählen), **max. 1 gerissene
Kante** und **max. 1 Rotation** pro Screen (beide seeded mit stabiler Item-ID — nichts flackert
zwischen Renders), keine Fake-Handschrift/Skript-Fonts (Intimität kommt aus New York), kein
Vergilbungs-/Sepia-Filter auf Fotos oder Papier, keine Bitmap-Texturen, Korn ≤ 2 % Luminanz.
Nie alle vier Klebeecken, keine Stempel-Inflation — jede Karte muss auch ohne alle Artefakte
funktionieren. Die Budgets stehen als gepinnte Konstanten in `PaperRules`; die Inventur selbst
bleibt Review-Ritual (Noble-Test-Frage 11).

### Nativität: benannte Marken-Ausnahmen (FullRelease R1-E)

Native System-Controls gewinnen per Default (`.searchable`, `Form`/`.formStyle(.grouped)`,
`ProgressView`, `Gauge`, System-TabView) — Eigenbauten müssen sich hier als AUSNAHME benennen
lassen, sonst sind sie Slop. Die alte „Brand-Ausnahme" des Paarfarben-Verlaufs auf der
Primäraktion ist GESTRICHEN — der Brand spricht vollständig Papier & Licht. Es gibt genau
**zwei benannte Button-Ausnahmen**, beide in `UI/Theme.swift`: **`PrimaryButtonStyle` ist der
SIEGELLACK** — die Primäraktion ist ein Siegel aus tiefem Wachs (`Wachs.rot` → `Wachs.dunkel`,
die WachsSiegel-Richtung), beschriftet in `Papier.brief` (auf BEIDEN Stops ≥ 4,5:1,
LogicTest-gepinnt), mit der abgeleiteten Lichtkante an der Oberlippe
(`PaperRules.siegellackKanteHex`, dieselbe Ableitung wie die Nachtkarten-Kante); gedrückt ist
das Siegel „gesetzt": der Guss dunkelt zum Tiefwachs, das Licht verlässt die Lippe, die Kapsel
setzt sich (`Theme.Motion.settle`). Er ersetzt bewusst NICHT `.glassProminent`, weil Glas
nicht gießen kann — Wachs ist DAS Marken-Material der Primäraktion. **`SecondaryButtonStyle`**
liegt auf ECHTEM interaktivem System-Glas (`glassEffect(.regular.interactive())`) und ist nur
deshalb ein eigener Stil, weil er App-Typo und -Paddings trägt — Material, Press-Feder und
Reduce-Transparency-Verhalten sind die des Systems. Wer einen dritten eigenen Button-Stil
baut, benennt ihn hier mit Begründung — oder nimmt den Systemstil.

### iPad-Drag & Tab-Customization: dokumentierte Etappe (FullRelease R1-E)

**iPhone:** Nutzer-Drag an der Tab-Bar existiert plattformseitig NICHT (kein Reorder, kein
Herausziehen — Apple-Doku, RECON_NATIVE_IOS26 §1.4); „fehlender Bar-Drag" ist auf iPhone kein
Defekt, sondern Plattform-Realität. **iPad:** `.tabViewStyle(.sidebarAdaptable)` +
`tabViewCustomization` ist bewusst VERTAGT (RECON §2.7): die System-Sidebar würde eine zweite
Sidebar-Ebene über die handgebaute Memories-Split-Sidebar im Wir-Tab legen (Doppel-Sidebar-UX),
und fünf Top-Level-Tabs rechtfertigen keinen System-Katalog. Kriterium für die Folgewelle:
Erst wenn Inhalte als `TabSection`-Kataloge strukturiert werden (z. B. Spiele-Kategorien als
Sections) UND die Memories-Sidebar in dieses Modell überführt oder aufgelöst ist, kommt
`sidebarAdaptable` + `customizationID` je Tab + `@AppStorage`-`TabViewCustomization` — vorher
bleibt der Default-Stil (`.automatic`) die richtige native Antwort.

---

## (e) Die Ratchet: `tools/charter_lint.sh`

`tools/charter_baseline.json` hält die gemessenen Ist-Stände der Slop-Muster. Regel: **Jeder
Zähler darf sinken oder gleich bleiben, nie steigen** — steigt einer, bricht CI mit Muster und
verletztem Gebot. Wer eine Baseline senkt, committet die neue Zahl mit
(`bash tools/charter_lint.sh --update`) — so wird Aufräumen sichtbarer Fortschritt statt
unsichtbarer Fleiß.

Die 18 Metriken (Scope: App + Shared + Widgets, sofern nicht enger benannt):

| Metrik | misst |
|--------|-------|
| `emoji_as_text` | Emoji als Icon in `Text("…")` — auch HINTER String-Interpolationen (`"\(x) … 💞"` zählt) |
| `emoji_in_de_copy` | Deko-Emoji in deutschen L10n-Strings |
| `epic_celebrations` | `celebrate(.epic)`-Aufrufstellen |
| `try_await_api` | stumm verschluckte `try? await`-Fehler; `Task.sleep` zählt als Pause nicht mit |
| `bare_progressview` | nackte `ProgressView()` statt Skeleton |
| `bang_strings_de` | Ausrufezeichen-Strings in CoreStrings (DE) |
| `spring_literals` | Freihand-`spring(response:)` außerhalb `UI/Theme.swift` — inkl. Widgets |
| `easing_literals` | `easeIn/Out/InOut(duration:)` + `withAnimation(.linear…)` — dieselbe Freihand-Motion, andere Kurve |
| `bare_white_opacity` | `white.opacity(0.x)`-Freihandwerte in Features + Widgets |
| `raw_corner_radius` | rohe `cornerRadius:`-Zahlen in Features (Tokens `Radius.*` zählen nicht) |
| `hardcoded_pink_purple_features` | `Theme.pink/purple/rose` in Features — die Paar-Farben sind die Signatur, nicht Stock-Rosa |
| `ultrathin_material_features` | `ultraThinMaterial`-Glas-Nachbauten in Features — **auf 0 gepinnt** seit der `GlassLevel.chrome`-Migration |
| `surface_glass_features` | `glassCard(`/`GlassLevel.surface`/`.tinted` in Features — der Papier-Fortschritt der Bau-Wellen, Startwert = Ist-Stand beim Migrationsstart, **Richtung 0** |
| `raw_rotation_features` | freihändige `.rotationEffect(` in Features — Rotation existiert nur über das seeded `PaperTilt`-Token |
| `smallcaps_features` | `.smallCaps()` außerhalb `UI/` — `Typo.anschrift` ist der einzige Kapitälchen-Einsatz, **auf 0 gepinnt** |
| `fixed_font_sizes` | `Font.scaled(<Zahl>)` |
| `system_size_fonts` | `.system(size:)`-Fixgrößen in Features + Widgets |
| `version_graffiti` | Versions-/Agenten-Graffiti in Kommentaren — **auf 0 gebracht**, Kommentare erzählen das Warum |

Dazu ein **Deckel** (kein sinkender Zähler): `torn_edge_uses` — `TornEdgeShape`-Verwendungen in
Features + Shared + Widgets **≤ 6** (`PaperRules.tornEdgeAppCap`); Risse sind Ausnahme, nicht
Rhythmus. Der **Korn-Deckel** läuft als LogicTest statt als Grep:
`PaperRules.grainLuminance == 0.02` ist gepinnt, jede Erhöhung bricht `swift test`. Die
Kino-Gates (Video-Budget, Determinismus-Hash, Manifest-Kreuz-Check) leben im
Remotion-CI-Workflow, nicht in diesem Skript.

Lokal laufen lassen: `bash SoooDreamy/tools/charter_lint.sh` (braucht `rg` und `jq`).
Editor-Hinweise: `ios/.swiftlint.yml` enthält dieselben vier Regex-Regeln als Warnungen.

Bewusst NICHT automatisiert: Geschmack (Vorlese-Test, „der eine Moment", Artefakt-Inventur —
Noble-Test-Frage 11) — das bleibt Review-Ritual, sonst entsteht regelkonforme Seelenlosigkeit.
