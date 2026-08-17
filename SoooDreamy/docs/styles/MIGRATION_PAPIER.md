# MIGRATION_PAPIER.md — Die verbindliche Alt→Neu-Token-Tabelle der Papier-Wellen

**Status: verbindlich.** Fundament-Welle „FullRelease N1-B" — dieses Dokument ist der
Vertrag zwischen dem Design-System (`UI/Theme.swift`, `UI/Glass.swift`,
`Content/PaperRules.swift`, `Content/PersonalizationLogic.swift`) und den kommenden
Screen-Wellen. Quelle der Wahrheit für die Werte: `docs/styles/STYLE_DECISION.md`
Abschnitt 3 (Art Direction v2); Quelle der Wahrheit für die Pins:
`LogicTests/PaperRulesTests.swift` + `LogicTests/PersonalizationLogicTests.swift`.

Alle LEGACY-Namen sind FUNKTIONAL geblieben und zeigen bereits auf die neuen Werte —
kein Screen ist durch die Fundament-Welle gebrochen. Die Screen-Wellen ersetzen die
LEGACY-Namen durch die Zielnamen und bauen dabei Karte für Karte von Glas auf Papier um.

---

## 1. Farbtokens: LEGACY → Ziel

| LEGACY (bleibt funktional) | Wert heute (nach Fundament-Welle) | Ziel-Token (Screen-Wellen) | Hex | Rolle |
|---|---|---|---|---|
| `Theme.bgTop` | `#201613` | `Papier.zimmerOben` | `#201613` | dunkles Sepia-Umbra, oberer Rand; NACHT-Kontrast-Anker |
| `Theme.bgBottom` | `#33241B` | `Papier.zimmerUnten` | `#33241B` | warme Kastanie, unterer Rand |
| — (Aurora-Blobs) | — | `Papier.lichtkegel` | `#4A3320` | EIN radialer Lampenschein von 10 Uhr, Opacity 0.35 → 0 |
| `Theme.card` | `Papier.brief` | `Papier.brief` | `#F7F1E4` | Standard-Kartenfläche (opak); PAPIER-Kontrast-Anker |
| — | — | `Papier.karton` | `#EFE6D2` | Sekundär-Karten, Partner-Zettel, Innenflächen |
| `Theme.cardBorder` | `Papier.kante` | `Papier.kante` | `#E3D6BC` | Stapelkante, Rückseiten, Trennlinien — NIE Textgrund |
| — | — | `Papier.polaroid` | `#FAF6EC` | Polaroid-Rahmen (nur Fotos) |
| `Theme.textPrimary` | `Papier.aufNacht` | auf Nacht: `Papier.aufNacht` · auf Papier: `Tinte.dunkel` | `#F3EAD9` / `#2E2318` | Kompat-Property dient dem Nacht-Kontext des Bestands; auf Papier wechseln die Wellen auf die Tinte |
| `Theme.textSecondary` | `Papier.aufNacht @ 0.78` | auf Papier: `Tinte.sekundaer` | `#5A4A38` | Sekundärtext (7,5:1 auf brief) |
| `Theme.textTertiary` | `Papier.aufNacht @ 0.64` | auf Papier: `Tinte.tertiaer` | `#6E5C46` | Timestamps/Fußnoten — nie unter `.caption` (5,7:1 auf brief) |
| `Theme.gold` / `Theme.goldHex` | `#FFC46B` | `Licht.lampengold` | `#FFC46B` | Zeremonien-Akzent, Glows auf Nacht (11,3:1) — NIE Text auf Papier (1,4:1) |
| `Theme.blue` / `Theme.mint` / `Theme.indigo` | `Licht.glut` | `Licht.glut` | `#E8845E` | zweiter warmer Akzent, aktive Zustände auf Nacht (6,7:1) |
| — | — | `Wachs.rot` | `#B33A3A` | Siegel/Stempelkissen — Material, NIE Text auf Nacht (3,0:1) |
| `Theme.energyRed` | `#F87171` (unverändert) | bleibt `Theme.energyRed` | `#F87171` | Verletzlichkeits-Rot, neu gegen `#201613` gepinnt (6,4:1); nie im Paar-Farbkanal |
| `Theme.hairline` | `Nacht.naht` | `Nacht.naht` | `aufNacht @ 0.12` | Hairlines auf Nacht (Increased Contrast: 0.38 via `Theme.Contrast.hairline`) |
| `Theme.innerFill` | `aufNacht @ 0.05` | auf Glas: bleibt · auf Papier: `Papier.innenFill` | `Tinte.dunkel @ 0.05` | Innenflächen auf Papier tragen zusätzlich `Papier.kante`-Hairline |
| — | — | `Papier.lichtkante` | `#FCFAF5` (abgeleitet: brief + 8 % Luminanz) | 1-pt-Lichtkante oben-links auf jeder Papierkarte |
| `Theme.pink` / `purple` / `rose` | unverändert | unverändert (heroGradient-Fallback-Stops) | `#FF5C8A` / `#A855F7` / `#FF8FAB` | `PrimaryButtonStyle` bleibt unverändert — Buttons sind Chrome |

Rohwerte leben weiterhin NUR in der Design-System-Schicht; kontrastkritische Hexes
konsumiert `Theme` aus `PaperRules`/`CouplePaletteRules` (heroGradient-Stop-Präzedenz),
damit die Logic-Tests exakt das pinnen, was rendert.

## 2. Kontrast-Doppel-Anker (Gesetz)

- **Nacht:** `CouplePaletteRules.darkBackground` = `#201613` (war `#17062A`). Alle
  Akzent-auf-Nacht-Verdicts (`acceptsAccent`, `derived`, Scrim-Leiter) rechnen gegen den
  neuen Anker; die Verdict-Matrix über alle memberColor-Paare ist neu gepinnt.
- **Papier:** `CouplePaletteRules.inkOnPaper(hex)` — Leiter-Mechanik identisch
  `accentOnLight` (konsolidiert auf EINE private Leiter), verankert gegen die
  Papierfamilie: gerechnet wird gegen ALLE vier Papiertöne, die dunkelste Fläche
  (`Papier.kante`) bindet. Ein Autor = EINE Tinte auf jedem Zettel, ≥ 4,5:1 überall
  (gepinnt: 8 memberColors × 4 Papiere).
- `Tinte.dunkel`/`sekundaer`: ≥ 4,5:1 auf allen vier Papieren. `Tinte.tertiaer`:
  ≥ 4,5:1 auf den drei TEXT-Papieren (brief/karton/polaroid); auf `kante` bewusst
  UNTER dem Boden gepinnt (4,45:1) — kante trägt nie Text.

## 3. Material & API: Was die Screen-Wellen benutzen

| Alt (deprecated, funktional) | Neu (Ziel-API) |
|---|---|
| `glassCard(_ padding:)` | `paperCard(_ level:padding:grain:)` — Level `.brief`-Default |
| `GlassLevel.surface` | `PaperLevel.brief` / `.karton` |
| `GlassLevel.tinted(Color)` | `PaperLevel.briefbogen` (Papier + `coupleTint.band` + Wachssiegel, genau EINE pro Screen) |
| `Radius.card` (22, an Content-Karten) | `Radius.papier` (10) · Fotos: `Radius.polaroid` (4) |
| freihändige `.rotationEffect(...)` | `paperTilt(seed:)` / `PaperTilt(seed:)` — seeded −6°…+6°, max. 1/Screen |
| Bubble-/Chip-Deko-Rotationen | `TornEdgeShape(seed:edge:)` — max. 1/Screen, app-weit ≤ 6 (Deckel) |
| `coupleTint.blend` als Fläche/Wash | `coupleTint.tinte` (Titel auf Papier), `tintePrimary`/`tinteSecondary` (Tintenkante, Ringe), `wachs` (Siegel), `band` (6-pt-Band, `Papier.bandBreite`) |
| `brandTitle` auf Papier | trägt `coupleTint.tinte` (= `inkOnPaper(blend)`) statt Vollton-`blend` |
| Konfetti Delight 1–2 | `Theme.Motion.lichtschein` + `Signature.lichtschein*`-Parameter (`epic` behält Partikel) |
| Einblendungen | `Theme.Motion.blaettern` (Hero/Screen) · `Theme.Motion.legen` (Elemente, Stagger 40 ms, max. 6) |
| Serif nur `Typo.voice` | + `Typo.brief` (Brief-Körper) · `Typo.anschrift(isAccessibilitySize:)` (Poststempel/Datumszeilen; einziger Kapitälchen-Einsatz) — Serif NUR auf Papier |

Korn: `paperCard(grain:)` schaltet das Korn ab, wenn die Karte von Text < `.subheadline`
dominiert wird; unter Increased Contrast ist es automatisch aus. Der Korn-Backend-Tausch
(statischer Canvas-Pass → Metal-`colorEffect`-Shader laut Decision) ist ein
Implementierungsdetail OHNE Callsite-Änderung und gehört in eine Welle mit Xcode-Zugriff
(Shader-Ressource im App-Target); das Gesetz (prozedural, statisch, ± 2 %-Deckel) gilt
bereits und ist gepinnt.

## 4. Ratchets, die die Wellen bewegen

- `surface_glass_features` (Start 320, Richtung 0) — jeder `glassCard→paperCard`-Tausch
  senkt ihn; Baseline mit `--update` im selben Commit nachziehen.
- `raw_rotation_features` (Start 19, Richtung 0) — Rotationen auf `paperTilt(seed:)` heben.
- `smallcaps_features` (0 gepinnt) — Kapitälchen nur via `Typo.anschrift`.
- `torn_edge_uses` (Deckel ≤ 6) — Risse budgetieren, bevor gebaut wird.
- `bare_white_opacity`/`raw_corner_radius` sinken strukturell mit;
  `hardcoded_pink_purple_features` (5) geht auf 0 (Stock-Rosa verliert die letzten
  Chrome-Rollen an `Licht.*`/`CoupleTint`).

## 5. Bekannte Alt-Anker im Bestand (Wellen-Aufgaben, KEINE Fundament-Blocker)

- `Features/Settings/PersonalizationView.swift` zeigt den Kontrast-Wert gegen das
  Literal `"#17062A"` an → auf `CouplePaletteRules.darkBackgroundHex` umstellen
  (Settings-Welle).
- `Shared/WidgetStudio.swift` + `Features/Settings/LiveActivitySheet.swift` führen die
  alte Nacht-Palette (`17062A`/`2B0F4A`) als Widget-Spec-DATEN → Widget-Welle entscheidet
  Palette-Update (Spec-Hexes sind bewusst eigenständig, kein Token-Bruch).
- `server/src/router.js` validiert Akzente gegen `#17062A` → Server-Welle zieht auf
  `#201613` nach (Client-Leiter ist strenger als der alte Server-Check, es kann nichts
  Unlesbares durchrutschen).
- `DreamyBackground` rendert bereits das Sepia-Zimmer (Token-Durchgriff); der volle
  Zimmer-Canvas (Lichtkegel + Tintenstaub statt Blobs + Sterne, `showStars` → Staub,
  gleiche Drossel-Signatur) ist der Drop-in der ersten Screen-Welle.
- Das Layered-Icon (`GenerateIcon.swift`, 4 Ebenen „versiegeltes Polaroid") und die
  native TabView gehören N1-A/N1-C bzw. eigenen Wellen — Werte dafür stehen in
  `PaperRules` bereit.

## 6. Die fünf Regeln für jede Screen-Welle

1. **Material zuerst:** Jede Content-Karte wird `paperCard()` (opak); echtes Glas bleibt
   NUR am Schwebenden. Papier nie auf Glas, Glas nie auf Glas.
2. **Text-Farben nach Grund:** Auf Papier `Tinte.*` (+ `coupleTint.tinte*` für Identität,
   nie Fließtext); auf Nacht `Papier.aufNacht`/`Licht.*`. `Licht.lampengold` nie als Text
   auf Papier, `Wachs.rot` nie als Text auf Nacht, `Papier.kante` trägt nie Text.
3. **Serif nur auf Papier:** `voice` (Paar-Zitate, kursiv), `brief` (Brief-Körper),
   `anschrift` (Poststempel/Datum, einzige Kapitälchen) — nie auf Glas oder Nacht.
4. **Budgets sind Gesetz:** max. 3 Artefakte, 1 Riss, 1 Rotation pro Screen — alles
   seeded mit stabiler Item-ID (`paperTilt(seed:)`, `TornEdgeShape(seed:)`), genau EIN
   `briefbogen`-Hero pro Screen.
5. **Ratchets im selben Commit nachziehen:** Nach jeder Welle
   `bash SoooDreamy/tools/charter_lint.sh --update` + `swift test` — gesunkene Zähler
   werden eingerastet, die Kontrast-Matrizen bleiben grün.
