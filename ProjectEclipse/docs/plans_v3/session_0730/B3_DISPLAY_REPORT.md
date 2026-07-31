# B3 — BlockDisplay-Nachzügler (Welle 13, Zensus §4/§7-B3)

Team B3. Besitz-Dateien (exklusiv, alle unter `src/main/java/dev/projecteclipse/eclipse/`):
`worldgen/end/EndShatterSequence.java`, `worldgen/end/EndIslandCrashFx.java`,
`worldgen/stage/StructureFlightFx.java`, `worldgen/stage/ExpansionBorderFx.java`,
`sequence/FloatingDecor.java`. Keine fremden Registrar-/Cue-Dateien angefasst.

Referenz-Implementierungen (W12, NICHT angefasst): `stormfx.StormSiege`,
`sequence.StormDebrisFx` (Sediment-Gesetz + Fern-Band + MSPT-Guard),
`ferryman.finale.DayRiftOrbits.paramsFor` (Masse→Parameter-Ableitung),
`ferryman.finale.PortalFormation` (Golden-Hash-Stagger der P3-Ribs).

## Plan (konkrete Zahlen)

### 1. EndShatterSequence (Potenzial HOCH)

**Masse-Gesetz auf das FIN-2-Debris-Feld** (Feld-Welle + Crack-Fontänen):

- Scale wird ZUERST gerollt (Feld: 0.55–1.45 mit pow-1.6-Bias wie W12; Bursts:
  0.35–1.05), daraus `mass01 = (scale − MIN) / (MAX − MIN)` geklemmt auf [0,1].
- **3 Klassen**: leicht `mass < 1/3`, mittel `1/3 ≤ mass < 2/3`, schwer `mass ≥ 2/3`.
  Klassengrenzen steuern die Ableitung, kleine Jitter (±0.06 auf Geschwindigkeit,
  ±1.2 Blöcke auf Spawn-Höhe) halten die Korrelation von der Treppe.
- **Schwere Platten tief + langsam**: Spawn-Anker `+3.5` (leicht) … `−2.5` (schwer)
  Blöcke relativ zur Bruchkante; Drift-Speed ×(1.35 − 0.7·mass) ≈ leicht ×1.35 …
  schwer ×0.65; Aufwärts-Launch `vy0` Feld 0.10 → 0.03, Burst 0.52 → 0.24;
  Spin 1.6°/t (leicht) → 0.6°/t (schwer) — Ableitung statt unabhängiger Rolls.
- **Keystones ×2.4**: ~1 von 12 Feld-Chunks wird Keystone — `scale = 2.4`
  (übers Feld-Maximum 1.45 hinaus), mass fest 1.0, KEIN Band-Jitter, tiefster
  Anker (−2.5), langsamste Drift, Spin fest 0.5°/t.
- **Sub-Volleys statt Einmal-Burst**: jede Crack-Flash-Fontäne (22 Chunks) zündet
  in 3 Volleys 8/7/7 mit +0/+6/+12 t Verzögerung; Carve-Stinger-Fontänen (8) in
  2 Volleys 4/4 mit +0/+8 t. Mechanik: `PendingSpawn` bekommt `dueGameTime`;
  `drainPending` stoppt am nicht-fälligen Kopf (FIFO bleibt, Verzögerung ≤ 12 t).
- **MSPT-Guard** (StormSiege/StormDebris-Hebel, Hysterese): alle 20 t
  `getAverageTickTimeNanos()`; > 45 ms → degraded (Spawn-Drain pausiert, Push-Fenster
  4 t → 8 t), Erholung < 38 ms. Nie ein Cut — nur langsamere Interpolation.
- **Budgets** (W12-Größenordnung, Guard vorhanden): Feld-Cap 260 → 320,
  Hard-Cap 420 → 520, Spawn-Budget bleibt 20/t.

### 2. EndIslandCrashFx (Potenzial mittel)

- **Einschlags-Staffelung nach Masse**: `lag` (Anteil des Falls, den ein Fragment
  hinterherhängt) wird aus der Masse ABGELEITET statt unabhängig gerollt:
  leicht landet zuerst (`lag ≈ 0.30`), schwer zuletzt (`lag ≈ 0.04`), Jitter ±0.04 —
  der Einschlag liest als Trommelwirbel leicht→schwer statt als ein Klumpen.
- **Keystones**: ~1 von 9 Fragmenten (mind. 2 pro Cluster erzwungen über die
  deterministischen Hashes) → `scale = 6.8` (≈ ×2.4 des Band-Mittels 2.8;
  Normal-Band 1.6–5.2 bleibt), `lag = 0` — sie schlagen exakt auf dem Haupt-Beat ein.
- **Boden-Schockring-Cue pro Keystone** (nur bestehende Cues): beim visuellen
  Touchdown eines Keystones `FxPayloads.FX_SHOCKWAVE` (a = 0.5, b = 24 t) +
  `FxCues.CUE_STRUCTURE_SLAM` (a = scale ≈ 6.8 → kleiner Staubpilz) an der
  Einschlagssäule, Cooldown 5 t zwischen zwei Keystone-Rings.
- Cluster 34 → 42 Fragmente, Hard-Cap 160 → 190; **MSPT-Guard**: > 45 ms →
  Push-Fenster 4 t → 8 t (Hysterese 38 ms, geteilt über alle Cluster).

### 3. StructureFlightFx (Potenzial HOCH)

- **Per-Piece-Stagger via Golden-Ratio-Hash** (P3-Rib-Muster): statt EINER Uhr pro
  28er-Batch bekommt jedes Teil `launchTick = batchBase + ⌊frac(i·φ)·7⌋` mit
  φ = 0.6180339887 — die Starts verschmieren gleichverteilt über +0…+6 t, die
  Spiral-/Band-Ordnung bleibt, kein Tick spawnt mehr als vorher.
- **Masse-Stratifikation** (Explosion-Resistance als Proxy, wie der Landing-Dust):
  `mass01 = min(resistance, 9)/9` (Wolle 0.09, Planken 0.33, Stein 0.67,
  Obsidian 1.0). Ableitungen: Flugzeit 30–36 t (leicht) → 52–60 t (schwer);
  Hover-Dwell 18–26 t (leicht) → 10–14 t (schwer, plumpst früher); Spin 2 Umdrehungen
  (leicht) → 1 (schwer); Bezier-Kontrollpunkt-Hub 6–14 Blöcke ×(1 − 0.45·mass)
  (schwere Teile fliegen flacher).
- **Landing-Slam-Staub pro schwerem Teil**: Teile mit `mass ≥ 0.55` feuern am
  Touchdown-Seam zusätzlich `CUE_STRUCTURE_SLAM` (a = 5 → kleiner Pilz) +
  `FX_SHOCKWAVE` (a = 0.30, b = 16), eigener Cooldown 8 t (der normale
  Thud/Shake-Limiter bleibt unangetastet; der Dust skaliert weiter per Masse).

### 4. FloatingDecor (Potenzial mittel)

- **Masse-Gesetz aufs Intro-Orbit-Feld** (rein deterministisch über `hash01`):
  Scale zuerst (0.3–1.6, pow 1.3 bleibt), `mass01` daraus; Höhe im Band wird
  ABGELEITET: schwer → Unterseite (vertical ≈ 0.05–0.35), leicht → oben
  (0.6–1.0), Jitter ±0.08; Spin 1.0°/t (leicht) → 0.2°/t (schwer);
  Bob-Amplitude 0.25 (leicht) → 0.07 (schwer), Bob-Periode 80 t → 200 t.
- **Keystone-Akzente**: `hash01(index, 17) < 0.10` (≈ 3 von 28) → `scale = 2.4`
  (Bandmax 1.6 ×1.5 — die ×2.4-Akzent-Stufe relativ zum Feld-Mittel ~1.0),
  mass 1.0, kein Jitter, tiefster Slot, langsamster Spin — die Anker-Brocken
  unter der Insel.
- Bestands-Displays alter Welten behalten ihren Entity-Anker (reconcile setzt nie
  um); nur NEU gespawnte Fragmente nutzen die Masse-Anker. Kein Migrationspfad
  nötig — der Reveal spawnt das Feld ohnehin frisch.

### 5. ExpansionBorderFx (Potenzial mittel)

- **Fern-Silhouetten-Band** (W12-StormDebris-Muster übersetzt auf Monolithen):
  zusätzlich zu den 12 Nah-Monolithen werden 6 FERN-Monolithe auf den
  nächst-besten Kandidaten-Slots (Ränge 13–18 der Attractor-Sortierung, also
  angular hinter dem Haupt-Cluster, innerhalb des 160-Block-Tracking-Horizonts
  der Rim-Watcher) gehoben: Größen-FLOOR 12–20 Blöcke (Nah-Band 6–14), halbe
  Quake-Amplitude & -Speed (×0.5 — das W12-`FAR_SPEED_FACTOR`-Gesetz), doppelte
  Rise-Dauer (36 t statt 18 t), dunklere Brightness (Block 2 statt 5), KEIN
  Raise-Shake/-Sound (Silhouetten erscheinen still hinter dem Vordergrund).
- **MSPT-Degrade**: > 45 ms avg → Pose-Update-Fenster 2 t → 4 t (Hysterese 38 ms).
  Peak ~18 Monolithe × 3–7 Slabs ≈ 60–100 Displays; mit Guard im W12-Rahmen.

## Ergebnis

`./gradlew compileJava` **grün** (nur vorbestehende Deprecation-Warnungen fremder
Dateien; die `StructureFlightFx`-Deprecation-Note existiert auch ohne diesen Diff).
Eine Polish-Iteration über den eigenen Diff ist gelaufen; dabei gefixt:
`FloatingDecor.poseAt` nutzte noch die alten unabhängigen Rolls (Keystones bekamen
ihre ×2.4 nie, Spin/Bob waren nicht masse-abgeleitet) — jetzt `scaleOf`/`massOf`
durchgezogen.

Finale Zahlen, wo die Implementierung vom Plan abweicht:

1. **EndShatterSequence** — wie geplant (Feld 0.55–1.45 pow-1.6, Burst 0.35–1.05
   pow-1.4, Keystone 1/12 ×2.4, Crack 3×6 t, Carve 2×8 t, Caps 320/520, Guard
   45/38 ms). Abweichung: schwerer Spawn-Anker −1.0 statt −2.5 Blöcke (−2.5 stieß
   sichtbar in die Bruchkante); Volley-Mechanik zählt gegen einen monotonen
   `drainClock` statt `gameTime` (pausierbar unterm MSPT-Guard, nie rückdatiert).
2. **EndIslandCrashFx** — wie geplant (42/190, lag 0.30→0.04±0.04, Keystone
   `i % 9 == 4` → 5 pro 42er-Cluster, scale 6.8, `FX_SHOCKWAVE` a=0.5 b=24 +
   `CUE_STRUCTURE_SLAM` a=scale, Ring-Cooldown 5 t, Guard 4 t→8 t). Landung eines
   Keystones = sein `span = fallTicks·(1 − lag)` — exakt der Tick, an dem seine
   Fall-Kurve klemmt. Push-Phasen werden mod 8 vergeben, damit die degradierte
   Kadenz gleichverteilt bleibt.
3. **StructureFlightFx** — wie geplant (Golden-Offset ⌊frac(i·0.618…)·7⌋,
   mass = min(resistance,9)/9, Arc-Flatten ×(1−0.45·mass), Heavy ≥ 0.55 →
   Slam a=5 + Shockwave 0.30/16, Cooldown 8 t). Präzisierung: Flugzeit leicht
   30–38 t (nicht 30–36), Hover leicht 22–26 t (nicht 18–26) — die Jitter-Fenster
   (9/5 t) liegen INNERHALB der Bänder, Klemmen an 60/10 t bleibt.
4. **FloatingDecor** — Band-Höhen final: schwer 0.05–0.20 (nicht 0.35), leicht
   0.65–0.95, Band-Jitter ±0.15 (statt ±0.08 — 0.08 las noch als Treppe);
   Bob-Amplitude leicht 0.20–0.30 / schwer 0.04–0.06, Periode leicht 68–92 t /
   schwer 170–230 t (±15 % Jitter statt fester Enden). Keystones 10 % ×2.4,
   tiefster Slot 0.05–0.10, langsamster Spin.
5. **ExpansionBorderFx** — Fern-Band final: **10** Silhouetten (Ränge 13–22)
   statt 6 — 2 Slabs/Stück hält das Display-Budget trotzdem klein
   (12×3–7 + 10×2 ≤ 104); Höhe 12–24 (statt 12–20), Girth 0.26–0.42·h
   (Stelen, keine Boxen), Rise ×1.6 (≈ 29 t), Quake ×0.55 Amplitude / ×0.5 Tempo,
   Brightness 1/11 (statt 2), dunkle Palette (Deepslate-first). Statt „ganz still":
   ein leiser Fern-Knack (DEEPSLATE_BREAK 1.6/0.34) OHNE Shake — völlig lautlos
   las als Pop-in. Dazu Masse-Gesetz auch aufs Nah-Band (Rise ×1.0–1.5,
   Quake-Tempo ×1.0–0.62 nach Höhe) und der MSPT-Guard (2 t→4 t, Raises 2/t→1/t).
   Der Even-Spread-Fallback (keine Attraktoren) überspringt das Fern-Band —
   ein gleichverteilter Ring hat keinen „Nah-Cluster" zu verlängern.

### Empfohlene In-Game-Replays

- **EndShatterSequence + EndIslandCrashFx**: `/eclipse-worldgen end materialize`,
  dann `/eclipse-worldgen end crash` (F-047-Pfad startet das Shatter-Finale samt
  Islet-Crashes); `/eclipse-worldgen end status` für den Zustand.
- **StructureFlightFx**: `/eclipse-worldgen structures list` +
  `/eclipse-worldgen structures place <id>` (echte Flug-Lieferung);
  `/eclipsefx sequence expansion STRUCTURES` spielt nur die Cue-Seite lokal.
- **ExpansionBorderFx**: voller Pfad `/eclipsefx sequence expansion FLYOVER` →
  `GROWTH` (Arm + Hold + Release), headless `/eclipse stage set <n>`
  (Growth-Start-Listener hebt die Felsen ohne Arm).
- **FloatingDecor**: `/eclipsefx sequence intro REVEAL` (Reveal-Pfad ruft
  `FloatingDecor.ensure`); Bestandswelten rebuilden das Feld beim Reconcile.

### Cue-Patch-Snippets

**Keine nötig.** Beide Bedarfe (Boden-Schockring, Slam-Staub) sind mit den
bestehenden, eingefrorenen IDs `FxPayloads.FX_SHOCKWAVE` und
`FxCues.CUE_STRUCTURE_SLAM` abgedeckt — keine neuen Rows in fremden
Registrar-Klassen. Wünschenswert wäre langfristig ein dedizierter
`CUE_DEBRIS_IMPACT` (kleinerer Staubpilz ohne die Slam-Tönung); Patch-Snippet
für den Integrator, NICHT von B3 angewendet:

```java
// FxCues.java — Vorschlag (nur falls der Integrator einen eigenen Impact-Look will):
/** Keystone-Trümmer-Einschlag: Schockring + kleiner Staubpilz (W13-B3). */
public static final int CUE_DEBRIS_IMPACT = <nächste freie Row>;
```
