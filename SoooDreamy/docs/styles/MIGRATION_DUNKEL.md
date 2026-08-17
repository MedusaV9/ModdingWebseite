# MIGRATION_DUNKEL.md — Nacht-first: Die verbindlichen Wellen-Regeln der Dunkel-Migration (P1-A)

**Status: verbindlich.** Ergänzt `MIGRATION_PAPIER.md` (die dort dokumentierten Alt→Neu-Regeln
gelten weiter); dieses Dokument regelt die BALANCE-Korrektur nach dem User-Feedback:
Der Artstil war „viel zu hell" — Home/Chat/Settings waren von großen CREME-Flächen dominiert
(`Papier.brief` #F7F1E4 als Standard-Karte), das Wachssiegel wirkte blass-pfirsich (Gradient
startete mit `Theme.gold` == Lampengold), die Herz-Prägung fast schwarz (Kino-Freeze-Beweisfall).

**Die Richtung „Papier & Licht" bleibt. Die Balance kippt zur Nacht:** Das Zimmer ist späte
Nacht mit EINER Lampe. Die Standard-Inhaltsfläche ist dunkles, warmes **Karton-bei-Nacht**
(`Papier.nachtkarton`). Helles Papier ist EXKLUSIV der Hero-/Artefakt-Moment: Briefe,
Tagesfrage-Briefbogen, Polaroid-Rahmen, Zeitpost-Umschlag, Empfangs-Zettel — Papier ist etwas
Besonderes im dunklen Zimmer, keine Tapete.

Quelle der Wahrheit für Werte: `Content/PaperRules.swift`; für Pins:
`LogicTests/PaperRulesTests.swift` + `LogicTests/PersonalizationLogicTests.swift`.

---

## 1. Hex-Tabelle Alt → Neu (Fundament P1-A, bereits umgesetzt)

| Token | Alt | Neu | Rolle / Messwerte (gepinnt) |
|---|---|---|---|
| `Papier.zimmerOben` (`PaperRules.zimmerObenHex`, `CouplePaletteRules.darkBackground`) | `#201613` | **`#1A100B`** | NACHT-Anker, eine Stufe dunkler. aufNacht 15,7:1 · lampengold 11,9:1 · glut 7,0:1 · energyRed 6,8:1 |
| `Papier.zimmerUnten` (`PaperRules.zimmerUntenHex`) | `#33241B` | **`#2A1B12`** | unterer Zimmer-Rand; der alte Bodenton wurde zur Karte |
| `Papier.nachtkarton` (`PaperRules.nachtkartonHex`) | — (NEU) | **`#33241C`** | STANDARD-Inhaltsfläche, DRITTER Kontrast-Anker. aufNacht 12,5:1 · Nacht.sekundaer 8,1:1 · Nacht.tertiaer 6,0:1 · lampengold 9,5:1 · glut 5,6:1 |
| `Papier.nachtLichtkante` (`PaperRules.nachtLichtkanteHex`) | — (NEU) | **`#664C30`** (abgeleitet: nachtkarton → lampengold @ 0.25) | warme 1-pt-Lichtkante oben-links auf Nacht-Karten; DEKOR (1,9:1 auf der Karte, bewusst unter dem Boden gepinnt) |
| `Papier.nachtInnenFill` | — (NEU) | `aufNacht @ 0.05` | Innenflächen AUF Nacht-Karten (+ `Nacht.naht`-Hairline); `Papier.innenFill` (Tinte @ 0.05) ist dort unsichtbar |
| `Wachs.dunkel` (`PaperRules.wachsDunkelHex`) | — (NEU) | **`#7E2429`** | tiefes, sattes Siegelwachs — Start-Stop des WachsSiegel-Gradients. aufNacht prägt 8,1:1; auf Nacht Material (1,9:1) |
| `coupleTint.wachsTief` | — (NEU) | `waxDeepened(blend)` — blend Richtung Nacht-Tinte in Zwölftelschritten, bis aufNacht ≥ 4,5:1 (Worst-Pair 4,55:1, Matrix gepinnt) | zweiter Stop des Siegel-Gradients: das Paar-Wachs, satt statt blass |
| `coupleTint.aufWachs` | — (NEU) | `#F3EAD9` (aufNacht; Verdict-Fallback) | HELLE Herz-Prägung auf dem tiefen Wachs — ≥ 4,5:1 auf BEIDEN Stops, jede Paarung (gepinnt) |
| WachsSiegel-Gradient | `[Theme.gold → coupleTint.wachs]` (blass-pfirsich) | **`[Wachs.dunkel → coupleTint.wachsTief]`** | Prägung `coupleTint.onWax` (fast schwarz) → **`coupleTint.aufWachs`** (hell); Glanzpunkt 0.22 → 0.14 (subtil) |
| `LampenkegelView` Umbra | 0.35 / 0.16, aus bei 0.72 | **0.30 / 0.12, aus bei 0.62** | „späte Nacht, eine Lampe" statt „goldene Stunde"; Hotspot-Garantie: aufNacht ≥ 11:1, Tertiär ≥ 5,5:1 |
| `LampenkegelView` Gold-Kern | 0.10 / 0.04, aus bei 0.75 | **0.08 / 0.03, aus bei 0.66** | s. o. |
| Widgets `WidgetPaperHex.zimmerOben/zimmerUnten` | `201613` / `33241B` | **`1A100B` / `2A1B12`** | „Zimmer bei Nacht"-Theme + Live-Activity-Tints spiegeln den dunkleren Look (Spiegel-Pin in `WidgetThemesTests`) |

Unverändert: alle Papier-/Tinten-Töne (`brief`/`karton`/`kante`/`polaroid`, `Tinte.*`),
`lampengold`/`glut`/`ablauf`, `wachsRot`/`wachsGelb`, `aufNacht`, `energyRed`, die
Nacht-Stufen-Opacities (0.78/0.64), Korn-Deckel (± 2 %), `lichtkante` (Papier-Kante),
`inkOnPaper`-/`accentOnLight`-Leitern, Kitsch-Budgets.

## 2. Kontrast-Anker: jetzt DREI (Gesetz)

1. **Nacht** `#1A100B` (`CouplePaletteRules.darkBackground`) — alle Akzent-auf-Nacht-Verdicts
   (`acceptsAccent`, `derived`, Scrim-Leiter) rechnen gegen den dunkleren Anker. Da der Anker
   DUNKLER wurde, brauchen Blends gleich viel oder weniger Aufhellung — kein Paar fällt unter
   den Boden (Matrix neu gepinnt).
2. **Papier** `#F7F1E4` — unverändert, `inkOnPaper` gegen alle vier Papiertöne; `Tinte.*`
   bleibt die Sprache der Hero-Papiere.
3. **Nachtkarton** `#33241C` (NEU) — die `aufNacht`-Tintenfamilie muss hier ≥ 4,5:1 halten
   (gepinnt: aufNacht 12,5:1, Sekundär-Komposit 8,1:1, Tertiär-Komposit 6,0:1 — geprüft, keine
   Justierung von `aufNacht` nötig). `Tinte.dunkel` ist auf nachtkarton UNTER dem Boden gepinnt
   (dunkel auf dunkel) — Papier-Tinte wandert NIE auf die Nacht-Karte.

## 3. Die Karten-API für P2 (Entscheidung)

**Gewählt: `nightCard()` als zweiter Modifier + `PaperLevel.nachtkarton`; der
`paperCard()`-Default bleibt `.brief`.** Begründung: Ein Default-Flip hätte alle ~300
bestehenden `paperCard()`-Callsites AUF EINMAL dunkel gestellt, während ihre `Tinte.*`-Texte
noch Papier-Tinten sind → app-weit dunkel-auf-dunkel. Mit `nightCard()` flippt P2 Karte und
Tinten in EINEM Edit pro Callsite (ein Token-Tausch + Tinten-Mapping), und ungewanderte
Screens bleiben bis dahin konsistent lesbar.

```swift
// Die neue Standard-Karte (dunkel, warmes Korn, warme Lampenkante):
.nightCard()                          // == .paperCard(.nachtkarton)
.nightCard(padding: .compact)         // Dichte-Tokens wie gehabt
.nightCard(grain: false)              // Karte von Kleintext dominiert

// Hero-/Artefakt-Papier — API unverändert:
.paperCard()                          // Brief-Papier (Hero-Momente)
.paperCard(.briefbogen)               // der EINE Briefbogen pro Screen
.paperCard(.polaroid)                 // Foto-Rahmen
```

**Alt→Neu-Grundregel: „Standard-Karte → nachtkarton, Hero/Artefakt → brief wie gehabt."**

| Karte ist … | P2-Ziel |
|---|---|
| Standard-Inhaltskarte (Listen, Hubs, Settings-Gruppen, Stats, Spiel-Lobbys, Sheets-Inhalt) | `.nightCard()` + Tinten-Mapping (§4) |
| Brief/Letter (Composer, Reader), Tagesfrage-Briefbogen, Zeitpost-Umschlag, Empfangs-/Chat-Zettel, Polaroid | bleibt `.paperCard(...)` mit `Tinte.*` |
| Sekundär-Fläche INNERHALB eines Papier-Heros | bleibt `.karton` |
| `paperCard(.karton)` als eigenständige Standard-Karte | `.nightCard()` |

## 4. Tinten-Mapping auf dunklen Karten (Gesetz für jede P2-Welle)

| Auf `brief`/`karton` (Hero-Papier, unverändert) | Auf `nachtkarton` (Standard-Karte) |
|---|---|
| `Tinte.dunkel` | `Papier.aufNacht` |
| `Tinte.sekundaer` | `Nacht.sekundaer` (== `Theme.textSecondary`) |
| `Tinte.tertiaer` | `Nacht.tertiaer` (== `Theme.textTertiary`) |
| `Tinte.erfolg` | `Licht.lampengold` (Erfolg spricht auf Nacht im Lampenlicht — Papier-only-Pin) |
| `Wachs.gelb` (Deadline-Tinte auf Papier) | `Licht.ablauf` (== glut; Nacht-Regel gilt) |
| `Papier.innenFill` + `Papier.kante`-Hairline | `Papier.nachtInnenFill` + `Nacht.naht`-Hairline |
| `coupleTint.tinte`/`tintePrimary`/`tinteSecondary` (Identitäts-TINTE) | Akzent-TEXT: `Licht.lampengold`/`Licht.glut` (9,5:1/5,6:1 gepinnt). `coupleTint.blend` NUR für Nicht-Text (Icons ≥ 3:1, Füllungen, Ringe) — blend ist gegen das Zimmer gesichert, auf der helleren Karte kann Text-Kontrast unter 4,5 fallen (Worst-Case ≈ 3,6:1) |
| `paperField()` (Input auf Papier) | `DreamyFieldStyle` (Nacht-Chrome-Input) |
| Serif (`Typo.voice`/`brief`/`anschrift`) | VERBOTEN — Serif nur auf Papier; nachtkarton spricht rounded |
| `SectionHeader(..., onPaper: true)` / `PillTag(..., onPaper: true)` | `onPaper: false` (Nacht-Familie ist deren Default) |

**Charter-Hinweis (keine Zählerregression):** „bare white" auf dunklen Karten ist jetzt als
`Papier.aufNacht`/`Nacht.*` LEGAL — aber IMMER als Token, nie als `white.opacity(0.x)`-Rohwert:
der `bare_white_opacity`-Zähler (Features + Widgets, Baseline 12) darf nicht steigen. Die
Baseline wurde in P1-A NICHT angefasst (alle Zähler unverändert, Ratchet grün).

## 5. Wachs-Regeln (Siegel vs. Chips)

- **`WachsSiegel`** (UI-Baustein, überall automatisch): gießt jetzt `Wachs.dunkel →
  coupleTint.wachsTief`, prägt HELL mit `coupleTint.aufWachs` (Schatten-Lippe oben, Licht-Lippe
  unten = eingedrückt auf dunklem Material), Glanzpunkt subtil (0.14). Chat-Siegel
  (`ChatWaxSealView`) und Kino-Zeremonie delegieren bereits hierher — der Freeze-Beweisfall ist
  damit behoben, ohne Feature-Diff.
- **`coupleTint.onWax` ist LEGACY** (Gold-Ära-Stempeltinte, gegen gold+blend gerechnet): bleibt
  funktional für die flachen `coupleTint.wachs`-Chips (`MissedInboxCard` Needs-Ack-Tropfen,
  `StreakCalendarView` Beide-Tage-Zelle) — dort trägt die blend-Fläche, und onWax cleart sie.
  **P2-Regel:** Chips auf `wachsTief` + `aufWachs` heben (satter Look, ein Wachs app-weit), dann
  `onWax` entfernen. Ebenso `WachsSiegelBadge` (Memories): flat `coupleTint.wachs`-Fill →
  `coupleTint.wachsTief`.

## 6. Zimmer & Lampe — Theme-Seite (umgesetzt) und Kino-Referenz (P1-B/P2)

`LampenkegelView` (Theme-Seite, global hinter jedem Screen) ist nachgezogen:
Umbra `0.30 → 0.12 → aus@0.62`, Gold-Kern `0.08 → 0.03 → aus@0.66`. Hotspot-Garantie
(zimmerOben + Kegel@0.30 + Gold@0.08 = `#392818`): aufNacht 11,8:1, Tertiär-Stufe 5,8:1.

**`CinematicRoomStage` (Features/Onboarding/CinematicChapterStages.swift — NICHT Teil von
P1-A) liest die Zimmer-/Lampen-FARBEN aus den Tokens (wird also automatisch dunkler), hat aber
EIGENE Intensitäts-Konstanten.** Ziel-Werte für P1-B/P2, proportional zur Theme-Absenkung
(× ≈ 0.85 Kegel, × ≈ 0.8 Gold), damit Kino und App dieselbe späte Nacht erzählen und der
`ambientSettle`-Handoff auf die neue `LampenkegelView` weich bleibt:

| Konstante (heute) | Ziel |
|---|---|
| Kegel `0.62 * k` / `0.30 * k` | **`0.52 * k` / `0.24 * k`** |
| Gold-Kern `0.34 * k` / `0.12 * k` | **`0.28 * k` / `0.10 * k`** |
| Glut-Boden `0.10 * k` | **`0.08 * k`** |
| Vignette `black 0.5` | **`black 0.55`** (die dunklere Nacht verträgt eine ruhigere Rand-Abdunklung) |

Remotion-Referenz (`remotion/src/look.tsx`): `zimmerOben`/`zimmerUnten` dort auf
`#1A100B`/`#2A1B12` nachziehen (P1-C/D-Territorium, Werte hier festgehalten).

## 7. PaperSkeleton & Warte-Flächen

`PaperSkeleton(kind:onNacht:)`: `onNacht: true` für Skeletons in `nightCard()`s
(nachtInnenFill-Wash, `Nacht.naht`-Hairline, warmer Lampen-Sweep in `nachtLichtkante`).
Default bleibt Papier — bestehende Callsites unverändert, bis ihre Karte flippt.

## 8. Die 10 häufigsten Callsite-Muster (Beispiel-Diffs für P2)

```diff
 1. Standard-Karte
-    .paperCard()
+    .nightCard()

 2. Sekundär-/Kompakt-Karte
-    .paperCard(.karton, padding: .compact)
+    .nightCard(padding: .compact)

 3. Titel/Body auf der Standard-Karte
-    .foregroundStyle(Tinte.dunkel)
+    .foregroundStyle(Papier.aufNacht)

 4. Sekundärtext
-    .foregroundStyle(Tinte.sekundaer)
+    .foregroundStyle(Nacht.sekundaer)

 5. Timestamps/Fußnoten
-    .foregroundStyle(Tinte.tertiaer)
+    .foregroundStyle(Nacht.tertiaer)

 6. Section-Header auf der Karte
-    SectionHeader(title: t, onPaper: true)
+    SectionHeader(title: t)

 7. Pill/Chip auf der Karte
-    PillTag(text: t, tint: Wachs.rot, onPaper: true)
+    PillTag(text: t, tint: Licht.glut)

 8. Innenfläche/Row-Wash in der Karte
-    .fill(Papier.innenFill) … .strokeBorder(Papier.kante, …)
+    .fill(Papier.nachtInnenFill) … .strokeBorder(Nacht.naht, …)

 9. Skeleton in der Karte
-    PaperSkeleton(kind: .card(height: 120))
+    PaperSkeleton(kind: .card(height: 120), onNacht: true)

10. Paar-Akzent als TEXT auf der Karte
-    .foregroundStyle(coupleTint.tinte)
+    .foregroundStyle(Licht.lampengold)   // Text: Lampenlicht
     // blend/tinte nur noch für Nicht-Text (Ringe, Icons, Füllungen)
```

Erfolgs-/Warn-Sonderfall (Muster 3–5-Nachbar): `Tinte.erfolg` → `Licht.lampengold`,
`Wachs.gelb`-Deadline → `Licht.ablauf` — auf der Nacht-Karte gelten die NACHT-Regeln.

## 9. Bekannte Alt-Anker außerhalb P1-A (Wellen-Aufgaben, KEINE Fundament-Blocker)

- `Features/Settings/PersonalizationView.swift`: zeigt Kontrast gegen ein Hex-LITERAL an →
  auf `CouplePaletteRules.darkBackgroundHex` umstellen (Settings-Welle; galt schon in
  MIGRATION_PAPIER §5 für #17062A).
- `server/src/router.js`: validiert Akzente noch gegen `#17062A` → Server-Welle (P1-C) zieht
  auf `#1A100B` nach (Client-Leiter ist strenger, nichts Unlesbares rutscht durch).
- `DESIGN.md` §Farbwerte, `STYLE_DECISION.md` §3-Tabellen, `MIGRATION_PAPIER.md` §1-Tabelle,
  `docs/CHANGELOG.md`: nennen die alten Zimmer-Hexes als Prosa/Tabellen-Werte → Doku-Welle
  zieht die Zahlen nach (dieses Dokument ist bis dahin die Wahrheit für die neuen Werte).
- `CinematicRoomStage`-Intensitäten + `remotion/src/look.tsx`: §6.
- Icon-Paletten (`IconPaletteTable`) und statische Widget-Themes (sunset/ocean/…): bewusst
  EIGENSTÄNDIGE Spec-Daten, kein Token-Bruch — nur das „night"-Theme + Live-Activity-Tints
  spiegeln das Zimmer und sind nachgezogen.

## 10. Weiß-Audit: das geschärfte Artefakt-Kriterium (Gesetz)

User-Feedback vom Gerät („manche Sachen sind weiß hell"): Nach den P2-Wellen standen noch
GROSSE helle Flächen im Nacht-Zimmer, die keine Papier-Dinge sind — Navigations- und
Promo-Karten, die wie Fremdkörper leuchteten. Das Kriterium aus §3 wird deshalb geschärft:

**Helles Papier (`paperCard(.brief/.briefbogen/.karton/.polaroid)`) NUR für Dinge, die im
Fiktions-Sinn ein PAPIER-DING sind, das das Paar besitzt, beschreibt oder verschickt:**
Tagesfrage-/Steckbrief-Briefbogen, Chat-/Empfangs-Zettel, Briefe & Zeitpost-Umschläge,
Polaroids/Fotorahmen, Spielbretter und Spielkarten IM Spiel, Gutscheine, Sticker,
beschriebene Seiten (Journal, Magazin, Wochenrückblick, Handbuch-/Kapitelseiten),
der Recovery-Key-SLIP. **ALLES andere spricht Nacht** — Navigation, Menüs, Promos/Heroes,
Hub-Banner, Settings-Container, CTA-Flächen. Wo die Hierarchie einen Akzent braucht, trägt
die Nacht-Karte einen kleinen Papier-INSET („Briefmarke": 40–56 pt, `paperCard(.polaroid)`-
Mechanik, Symbol in `coupleTint.tinte`) statt einer Vollfläche. Ratchet:
`bright_paper_features` (charter_lint) zählt jede helle `.paperCard(`-Stelle in Features
und darf nur sinken (Start 71 → 70 nach diesem Audit).

### Inventar-Ergebnis (Audit über `paperCard|.brief|Papier.polaroid|briefbogen` in Features/ + App/)

| Fundstelle | Verdikt | Aktion |
|---|---|---|
| Memories/MemoriesHubComponents `MemoriesFeatureBanner(.hero)` („Unsere Geschichte", Wir-Tab) | **Chrome** (Navigations-Banner) | → `nightCard()` + Briefmarken-Inset; Paar-Band → 2-pt Tinten-Bikolor-Strich (primary/secondary, Dekor) |
| Games/PlayHubView `heroCard` („Heute für euch"-Promo) | **Chrome** (Promo/Hero) | → `nightCard(padding: .hero)` + Briefmarken-Inset um den Spiel-Glyph; Kicker `Licht.lampengold` (rounded — Serif bleibt Papier); Band raus |
| Onboarding/RecoveryViews `RecoverySheet.keyCard` (Settings-Container) | **Chrome** (Settings-Sektion) | → `nightCard()` + Nacht-Tinten; der Key-SLIP (`RecoveryKeyCard`) bleibt helles Papier-Artefakt darin (wie `replaceCard`) |
| Onboarding/CinematicChapterStages `CinematicInkStage.strokeStage` (Tintenwahl-Bogen) | **Artefakt**, aber leer-weiß | Proportion-Fix: statische Briefkopf-Zeilen (kante) + Schreiblinien (Tinte, niedrige Opazität) — bleibt Brief, kein leeres Rechteck |
| Home/DailyQuestionCard, Home/FirstMomentCard (Briefbogen) | Artefakt (Tagesfrage-Brief) | bleibt |
| Home/PostNoteOverlay (Zeitpost-Umschlag/Zettel) | Artefakt | bleibt |
| Chat/ChatView Zettel + Brief, Chat/VoiceNotes Recorder-Zettel, Memories/VaultView Notiz-Slips | Artefakt (Korrespondenz) | bleibt |
| Memories: GalleryComponents/GalleryPager/VideoGallery/VideoPlayer (Polaroids), CanvasView (Zeichenpapier), JournalView (Tagebuchseite), MagazineView (Heftseite), CouponsView (Gutschein), SharedListsView (Einkaufs-Zettel, TornEdge), StoryTimelineView-Titelseite (Briefbogen) | Artefakt | bleibt |
| Rituals: CapsulesView (Zeitpost-Briefbogen), WeekReviewView (Rückblick-Seiten/Polaroid), SeasonCalendarView (Türchen-Brief), GoalsView (nur 5-pt-Tick-Punkte, keine Fläche) | Artefakt | bleibt |
| Games/*: alle Bretter, Spielkarten, Wort-/Bingo-/Kniffel-Zettel, Riddle-/Quiz-/Movie-Karten (inkl. GamesWaveView, BoardDuelKit, GamesPaperKit) | Artefakt (Spielmaterial IM Spiel) | bleibt |
| Settings/HandbookView, Settings/VersionHistoryView (Serif-Leseseiten), Settings/IconGiftView (Polaroid im Icon-Render) | Artefakt (Buch-/Kapitelseiten, Icon-Motiv) | bleibt |
| Onboarding/PairingView `profileCard` (Steckbrief, wird beschrieben), RecoveryViews `RecoveryKeyCard`/Replace-Code-Slip | Artefakt | bleibt |
| Kino/OnboardingFlowView Feature-Briefbogen (Tour) | **Chrome** (N4-Verdikt: die Tour ERZÄHLT die App, sie ist kein Besitz-Papier des Paares) | → `nightCard(padding: .hero)`; jede Feature-Zeile trägt eine Briefmarke (Glyph in Paar-Tinte auf `paperCard(.polaroid)`-Inset) statt Vollfläche |
| Kino/CinematicIntroView Recap-/Caption-Zettel | **Artefakt** (N4-Verdikt: BESCHRIEBENER Zwischentitel im Stummfilm-Sinn, Inset-Maß, Serif-auf-Papier-Gesetz) | bleibt helles Papier (`paperCard(.brief, .compact)`) |
