# WAVE9-B — Tooling-Gates, Cutscene-Harness & Scorch-Zähler (Polish-Welle 9, Team B)

**Auftrag:** `docs/plans_v3/eval2/EVAL2-B_photon_displays.md` — H-1, P-1, P-2, P-4, P-3
(Runde 1 des Baseline-Burndowns). **Regeln eingehalten:** keine git-Operationen, keine
Refactorings, Regenerate nur für die eigenen Bausteine, Datei-Scope strikt
(`tools/**`, `WandTickService.java`, die kurierten `boss/`-Assets).

## Geänderte Dateien

| Datei | Baustein |
|---|---|
| `tools/photon/sig_fx.py` | H-1 (Alpha-Stop 0.45 → 0.28 synchronisiert) |
| `tools/repass_cutscenes.py` | P-1 (Glob statt 9er-Liste, dynamische Meldung) |
| `src/main/java/dev/projecteclipse/eclipse/wand/WandTickService.java` | P-2 (`onDrop`-Hook) |
| `tools/photon/fxlib.py` | P-4 (Byte-Diff-Gate `gendiff`/`--gen-diff` + Read-Path-Enum-Whitelist) |
| `tools/photon/boss_b_fx.py`, `tools/photon/fx_boss_herald_ferryman.py` | P-3 (Kurven-Kur) |
| `src/main/resources/assets/eclipse/fx/boss/{tyrant_blind_burst,roar_shockwave}.fx` (+ `.fxproj`-Siblings) | P-3 (Regenerat) |
| `tools/photon/lint_baseline.txt` | P-3 (−4 Einträge, 27 → 23) |

---

## H-1 — `sig_fx.py`-Alpha-Drift behoben (Anti-Revert)

**Fix.** `sig_fx.py` (SIG_CROWN_VERDICT_HALO, `_color_module`-Alpha-Stops): Mid-Stop
`(0.55, 0.45)` → `(0.55, 0.28)` — exakt der committete F-108-Wert in
`assets/eclipse/quasar/emitters/sig_crown_verdict_halo.json` (`percent 0.55 / alpha 0.28`).
Anti-Revert-Kommentar direkt am Emitter („das Asset ist die Wahrheit"). Weitere
Abweichungen zwischen Generator und Asset gab es NICHT (Byte-Vergleich unten deckt alle
Felder ab).

**Beleg (Sandbox-Doppellauf, Audit-Methodik).** `tools/photon` + kompletter
`assets/eclipse`-Baum nach `/tmp/h1_sandbox` kopiert, `sig_fx.py` dort zweimal gelaufen,
SHA-256 über alle Outputs (5 `.fx` + 5 `.fxproj` + 6 Quasar-JSONs), dann gegen das Repo
verglichen:

```
=== run1 vs run2 (double-run determinism) ===
DOUBLE-RUN BYTE-IDENTICAL
=== sandbox regenerate vs committed repo ===
REGENERATE == COMMITTED (byte-identical)
```

Das committete Halo-Asset wurde dabei NICHT angefasst (es trug den Fix bereits; nur der
Generator wurde synchronisiert — `git diff` zeigt für die Quasar-JSONs 0 Änderungen).

**Restrisiko.** Keines für diesen Drift; die Fehlerklasse insgesamt ist ab jetzt durch das
P-4-Gate abgedeckt (siehe unten: `gendiff` über alle 52 Generatoren = 0 Drift).

---

## P-1 — `repass_cutscenes.py` auf Verzeichnis-Glob umgestellt

**Fix.** `main()` leitet die Prüfliste jetzt aus `sorted(CUT.glob("*.json"))` ab (statt
der hartkodierten 9er-ID-Liste); leerer Ordner bricht hart ab; die Erfolgsmeldung zählt
dynamisch („all N paths"). Jede künftige Cutscene-JSON bekommt das Gate automatisch.

**Beleg (Lauf, read-only).** Alle 10 Cutscenes werden geprüft — `end_arrival` (1000t,
längste Cutscene) ist jetzt drin:

```
=== end_arrival (1000t, catmullrom, anchor world) ===  ← NEU im Gate
…
--- validation problems ---
  none — all 10 paths pass the parse/i18n/grammar rules   (exit 0)
```

**Befunde zu `end_arrival`:** KEINE. Monotone Keyframes, nur
`easeInOutSine`/`easeInOutQuart`, FOV-Slopes ≤ 0.067°/t, keine Velocity-Jumps > 0.12 b/t,
0 Events (legitim — `EndArrivalSequence.java` treibt die Captions serverseitig, deckt sich
mit der manuellen Audit-Nachprüfung). Kein Cutscene-Fix nötig, kein Scope-Creep.

**Restrisiko.** Keines; das Skript bleibt read-only.

---

## P-2 — Scorch-Decal-Zähler drop-sicher (`WandTickService`)

**Fix (minimal, kein Refactoring).** Das im Audit beschriebene Fenster: entlädt die
Dimension zwischen `spawnScorchDecal` und Ablauf des Discard-Tasks, warf `tickTasks()` den
Task still weg — das Decrement von `liveScorchDecals` lief nie, der Cap (24) verhungerte
bis zum Reboot. Umsetzung des Audit-Vorschlags (Variante „Task um optionales `onDrop`
erweitern"):

- `Task` trägt ein optionales `onDrop`-Runnable (läuft NUR auf dem Unload-Drop-Pfad,
  anstelle von `action`; try/catch wie beim Action-Pfad).
- Neuer `schedule(level, delay, action, onDrop)`-Overload; der bestehende
  3-Arg-`schedule` delegiert mit `onDrop = null` — alle übrigen Aufrufer unverändert.
- `spawnScorchDecal` übergibt als `onDrop` das Zähler-Decrement. Das gestrandete Display
  selbst bleibt wie gehabt im gespeicherten Chunk und wird vom Boot-Sweep/`SCORCH_TAG`
  gefangen (unverändertes, im Audit als begrenzt eingestuftes Verhalten).

**Beleg.** `./gradlew compileJava` → `BUILD SUCCESSFUL` (WandTickService-Klassen frisch
kompiliert). Hinweis: ein zwischenzeitlicher Fehlversuch schlug mit 43 Fehlern in
`FerrymanEntity.java` u. a. fehl — das war der In-Flight-Stand von Team C (Entity-Scope),
nicht diese Änderung; der direkt folgende Lauf war grün.

**Restrisiko.** `onDrop` läuft bewusst NICHT bei `onServerStopped` (dort wird
`liveScorchDecals` ohnehin hart auf 0 gesetzt und `TASKS.clear()` gerufen) — kein Fenster.
Doppel-Abrechnung ist ausgeschlossen: pro Task läuft entweder `action` ODER `onDrop`,
und das Decrement clampt auf ≥ 0.

---

## P-4 — fxlib-Gates (Byte-Diff + Read-Path-Enum-Whitelist)

### (a) Byte-Diff-Gate `gendiff` / `validate --lint --gen-diff`

**Fix.** Neu in `fxlib.py`:

- `generator_scripts()` — alle Generator-Skripte unter `tools/photon`
  (`*_fx.py` / `fx_*.py` / `gen_*.py`, 52 Stück).
- `generator_drift(generators)` — kopiert `tools/photon` + `assets/eclipse` in eine
  `/tmp`-Sandbox, lässt die Generatoren DORT laufen und byte-vergleicht den Asset-Baum
  vorher/nachher (SHA-256): `changed` (= Drift, die H-1-Klasse), `added`
  (= Generator schreibt eine Datei, die das Repo nicht hat), `failed`. Der Working Tree
  wird nie berührt.
- CLI `fxlib.py gendiff [<gen.py>…]` (ohne Argumente: alle 52) und Integration in den
  bestehenden Lint-Flow („fxlib 0 NEW") als `validate --lint --gen-diff`: Gate läuft nach
  dem Lint, jede Abweichung ⇒ Exit 1. CLI-Doku im fxlib-Docstring ergänzt.

**Beleg 1 (fängt exakt die H-1-Klasse).** Nach der P-3-Kurven-Änderung in den Generatoren,
aber VOR dem Repo-Regenerat:

```
gendiff DRIFT fx/boss/roar_shockwave.fx: a regenerate would byte-change this committed asset
gendiff DRIFT fx/boss/roar_shockwave.fxproj: …
gendiff DRIFT fx/boss/tyrant_blind_burst.fx: …
gendiff DRIFT fx/boss/tyrant_blind_burst.fxproj: …
gendiff: 2 generator(s), 1453 asset file(s), 4 drift, 0 uncommitted, 0 failed → exit 1
```

**Beleg 2 (Voll-Lauf, integriert).** Nach Abschluss aller Bausteine:

```
lint: 293 file(s), 0 NEW error/warn, 23 grandfathered, 149 advisory info
gendiff: sandbox-regenerating via 52 generator scripts …
gendiff: 52 generator(s), 1453 asset file(s), 0 drift, 0 uncommitted, 0 failed
```

(`validate --lint --gen-diff`, Gesamtlaufzeit ~5,5 s — CI-tauglich.) Das ist zugleich der
Voll-Beweis, dass NACH H-1/P-3 sämtliche Generatoren mit sämtlichen committeten Assets
synchron sind.

### (b) Read-Path-Enum-Whitelist

**Fix.** `_READ_PATH_ENUMS` (`arcMode`, `renderMode`, `facingMode`, `vertexSortingMode`)
+ `_enum_whitelist_errors()` — ein Ganzbaum-Walk, der beim LESEN jeder `.fx` alle
Vorkommen dieser Schlüssel gegen die bekannten Photon-Enums prüft; eingehängt in
`validate_file()` und damit automatisch in `validate`, `validate --lint` und `selfcheck`.
Handeditierte Dateien mit Tippfehler-Enum (die `wizard_star_call`-NPE-Klasse) fallen jetzt
im Gate statt im Client. NumberFunction-`type`-Tags waren im Read-Pfad bereits über
`_validate_nf_wrappers` (unknown-registry-key-Error) abgedeckt.

**Beleg (Negativtest).** Committetes Asset kopiert, `renderMode` → `"Bilboard"` und
`arcMode` → `"Sprial"` verfälscht, nach `/tmp/corrupt_enum.fx` geschrieben:

```
FAIL /tmp/corrupt_enum.fx:
  - fx.fxData.fxObjects[0].data.config.renderer.renderMode: 'Bilboard' is not a known Photon enum …
  - fx.fxData.fxObjects[2].data.config.shape.shape.data.shapeArc.arcMode: 'Sprial' is not a known Photon enum …
  (exit 1)
```

**Beleg (kein False Positive).** Volltree `validate --lint`: 293 Dateien, 0 FAIL, 0 NEW —
identische Zählung wie vor der Änderung; `selfcheck PASSED`.

**Restrisiko.** Der Audit-Fix-Vorschlag nennt zusätzlich einen Pflichtschritt-Absatz in
`PHOTON-QUALITY.md` — Doku liegt außerhalb des Team-B-Datei-Scopes dieser Welle und ist
über die CLI-Doku im fxlib-Docstring abgedeckt; der Absatz kann in einer Doku-Welle
nachgezogen werden. Das Standalone-`gendiff` ohne Argumente prüft bewusst ALLE
Generatoren — läuft ein Parallel-Team gerade mit ungesyncten Generator-/Asset-Ständen,
schlägt das Gate für DEREN Dateien an (korrektes Verhalten, aber bei Mid-Wave-Läufen zu
beachten; gezielte Läufe: Generator-Pfade als Argumente).

---

## P-3 — Lint-Baseline-Burndown, Runde 1 (die 4 `boss/`-Einträge)

**Befundlage (Audit).** Alle 4 Einträge sind `LINT-LINEAR-CURVE` — „harte Größen-Pops
durch lineare Ein-Segment-Kurven":

```
boss/roar_shockwave.fx|LINT-LINEAR-CURVE|roar_column.sizeOverLifetime.size[0]
boss/tyrant_blind_burst.fx|LINT-LINEAR-CURVE|fog_shells.sizeOverLifetime.size[0]
boss/tyrant_blind_burst.fx|LINT-LINEAR-CURVE|fog_shells.sizeOverLifetime.size[1]
boss/tyrant_blind_burst.fx|LINT-LINEAR-CURVE|fog_shells.sizeOverLifetime.size[2]
```

**Kur (konservativ, etabliertes Mittel „Kurve → geschmeidiges House-Segment").**

- `fx_boss_herald_ferryman.py` / `roar_column` (Tyrant-Roar-Lichtsäule): X-Schrumpf
  war der Inline-Chord `SEG_LINEAR_DOWN`-Klon → jetzt `SEG_SMOOTH_DOWN`
  (Smoothstep-Fall, horizontale Tangenten).
- `boss_b_fx.py` / `fog_shells` (Blind-Burst-Nebelschalen): Wachstum war
  `SEG_LINEAR_UP` (zählt pro Achse dreifach) → jetzt `SEG_SMOOTH_UP`.

**Warum sich die visuelle Charakteristik nicht verschlechtert:** Envelope-Grenzen sind
UNVERÄNDERT (`roar_column` 1.0 → 0.1; `fog_shells` 1.0 → 2.2), ebenso Counts, Tints,
Alphas, Timings, HDR. Smoothstep hat identische Endpunkte wie die lineare Rampe und
weicht mid-life maximal ~9,6 % vom Chord ab — es entfernt genau die harten
Start/Stopp-Pops, die der Lint bemängelt. Keine weiteren Emitter angefasst; die
`SEG_LINEAR_UP`-Verwendungen in `frameOverTime`-Scans (uvAnimation, spec'd linear,
lint-suppressed) blieben unverändert.

**Beleg (Regenerat + Gates).**

1. Regenerat-Scope exakt: `git status` zeigt als einzige Asset-Änderungen
   `boss/{roar_shockwave,tyrant_blind_burst}.fx` + ihre `.fxproj`-Siblings (alle anderen
   Outputs beider Generatoren inkl. Texturen: byte-identisch rewritten).
2. Doppellauf-Byte-Identität: `gendiff boss_b_fx.py fx_boss_herald_ferryman.py sig_fx.py`
   nach dem Repo-Regenerat = `0 drift, 0 uncommitted, 0 failed` — der (zweite)
   Sandbox-Lauf reproduziert die frisch committeten Bytes exakt.
3. Lint bestätigt das echte Verschwinden (kein Baseline-Trick):
   ```
   lint: 4 baseline entr(ies) no longer fire — prune them from lint_baseline.txt: …
   ```
   → die 4 Zeilen aus `lint_baseline.txt` gelöscht.
4. Endstand: `lint: 293 file(s), 0 NEW error/warn, 23 grandfathered, 149 advisory info`
   (Baseline 27 → 23, exakt −4); die beiden kurierten Dateien einzeln:
   `0 NEW, 0 grandfathered, 0 advisory`.

**Restrisiko.** Kein Live-Client in dieser Umgebung — die Kur ist bewusst die minimalste
Interpolations-Glättung ohne Parameteränderung; eine Sichtprüfung im nächsten
Client-Smoke (Tyrant-Kampf: Roar + releaseSquall) ist der übliche Abnahme-Schritt.

---

## Gate-Zusammenfassung

| Gate | Ergebnis |
|---|---|
| `./gradlew compileJava` | `BUILD SUCCESSFUL` |
| `python3 tools/repass_cutscenes.py` | exit 0, „all **10** paths pass" (inkl. `end_arrival`, 0 Befunde) |
| `python3 tools/photon/fxlib.py validate --lint` | 293 Dateien, **0 NEW**, **23 grandfathered** (−4), 149 advisory |
| `python3 tools/photon/fxlib.py validate --lint --gen-diff` | zusätzlich: 52 Generatoren, 1453 Asset-Dateien, **0 drift / 0 uncommitted / 0 failed** (~5,5 s) |
| `python3 tools/photon/fxlib.py selfcheck` | PASSED |
| H-1-Sandbox-Doppellauf (`sig_fx.py`) | run1 == run2 == committete Assets (SHA-256, byte-identisch) |
| Enum-Gate-Negativtest | verfälschte `renderMode`/`arcMode` ⇒ `FAIL … exit 1` |

*WAVE9-B — Änderungen nur im Working Tree (keine git-Operationen), Datei-Scope eingehalten.*
