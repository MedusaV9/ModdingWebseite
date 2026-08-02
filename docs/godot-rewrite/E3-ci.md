# E3 — Test-/CI-Integrität (GOOBY-Godot-Mega-Eval)

Branch `cursor/gooby-godot-rewrite-d1d8` (historisch; heute: `MedusaV9/ModdingWebseite` @ `cursor/bubble-shield-loop`) @ `8cfc20e0`. Godot 4.4.1.stable.official (identisch zu CI-Pin).
Alle Läufe in einer /tmp-Kopie (`/tmp/gooby-godot/proj`, `.godot` gelöscht = CI-frischer Checkout);
Repo unangetastet (`git status` clean vor/nach). Logs: `/tmp/gooby-godot/eval/E3-*.log`.

## Verdict: PASS — CI ist ehrlich, deterministisch, Fails werden ROT. Keine P0/P1.

---

## (1) Flakiness — beide Runner 3× hintereinander

| Runner | Lauf 1 | Lauf 2 | Lauf 3 | Ergebnis |
|---|---|---|---|---|
| `tests/run_tests.gd` | 43,5 s | 44,3 s | 49,5 s | 3× `tests=438, failed=0`, exit 0 |
| `tests/unit/run_w1c_tests.gd` | 3,4 s | 4,5 s | 3,4 s | 3× `checks: 2705, failed: 0`, exit 0 |

- PASS/FAIL/SKIP-Zeilen aller Läufe per `diff` verglichen: **byte-identisch** (beide Runner sortieren
  die Dateiliste → deterministische Reihenfolge). Keine Hänger. Zeit-Jitter ~14 % (harmlos).
- 7 `test_ui_*.gd` werden vom Haupt-Runner bewusst geSKIPpt (nicht `TestCase`) und vom W1c-Runner
  als eigener CI-Schritt ausgeführt — keine Datei fällt durchs Raster.

Repro: `cd /tmp/gooby-godot/proj && godot --headless --path . --script res://tests/run_tests.gd`

## (2) Import-Analyse (frisch, ohne `.godot` — wie CI)

`--import`: 23,3 s, **exit 0**, 2742 Log-Zeilen (`E3-import-fresh.log`). Kategorien:

| Klasse | Anzahl | Bewertung |
|---|---|---|
| `ERROR: Parameter "t" is null` @ `texture_2d_get` (dummy/texture_storage.h:107) | 140 | Headless-**Dummy-Renderer**-Artefakt, je 1× pro GLB-Szenen-Import (strawberry.glb, taco.glb, …). Bekanntes Godot-Verhalten, nicht projektverschuldet, nicht fatal. |
| `WARNING: ObjectDB instances leaked at exit` | 1 | s. u. |
| `ERROR: 72 resources still in use at exit` + 2× `PagedAllocator` | 3 | Folge des Leaks |

**Wer leakt** (`--verbose`, `E3-import-fresh-verbose.log`): 147 Instanzen = **75 GDScript + 67
GDScriptNativeClass + 2 SceneState + 2 PackedScene + 1 Shader**. Die GDScripts sind Projekt-Skripte
(Autoloads `boot_guard.gd`, `audio_director.gd`, `theme_service.gd`, `i18n.gd`, kompletter
`scripts/net/`-Stack, `panel_sheet.tscn`, `reise_cutscene.tscn`, `wallpaper_drift.gdshader`) —
typisches Muster zyklischer `preload`/const-Referenzen + `class_name`-Registrierung beim
Editor-Import-Exit. Exit-Code bleibt 0; Boot-Smoke (`--quit`) ist dagegen **leak-frei** (Log nur
Versions-Banner). Auch der Test-Runner-Exit zeigt die ObjectDB-WARNING (Script-Mode, gleiche Ursache).

## (3) Runner-Exit-Codes + CI-YAML

- **Code-Lektüre:** `run_tests.gd` → `quit(1 if failed > 0 else 0)`; W1c → `quit(0 if all_failures.is_empty() else 1)`.
- **Empirisch (nur /tmp-Kopie, danach gelöscht):** kaputter `TestCase`-Test → `tests=439, failed=1`,
  **exit 1**; kaputter W1c-Test → `failed: 1`, **exit 1** (`E3-*-broken.log`).
- **P5-Watchdog empirisch:** Hänger-Test (`await`-Signal, das nie feuert) mit auf 5 s reduziertem
  `TEST_TIMEOUT_MS` → `FAIL … TIMEOUT nach 5000 ms`, Lauf **läuft weiter**, exit 1 (`E3-run_tests-hang.log`). ✔
- **gooby-godot.yml:** alle 4 Godot-Steps setzen explizit `set -o pipefail` vor der `| tee`-Kette —
  korrekt, denn GitHubs Default-Shell (`bash -e {0}` ohne pipefail) würde sonst den tee-Exit nehmen.
  Test-Fail ⇒ Job ROT. `test-reports`-Upload mit `if: always()` ✔. Job-Timeouts 15/30 min ✔.
- **Cache-Keys:** `godot-4.4.1-linux-x86_64` @ `~/.cache/godot-bin` — identisch in gooby-godot.yml
  und gooby-packs.yml (Cache geteilt ✔), Pfad deckungsgleich mit `tools/ci/install_godot.sh`.
- **ios-Skeleton:** `if: false` ⇒ Job wird geskippt, `needs:` bricht nichts — wirklich inert ✔.
  `gooby-ios.yml` triggert nur `GOOBY/**` — keine Kollision ✔.
- **Action-Versionen:** `checkout@v7` (Jun 2026), `upload-artifact@v7` (Feb 2026) existieren (Web-Check) ✔.
- **gooby-packs.yml Dispatch-Simulation** (komplett in /tmp, `E3-packs-build.log`): Presets
  `pack-{core,balance,events,cosmetics,stickers,codes}` in `export_presets.cfg` vorhanden, ids/Versionen
  aus `content/*/pack.json` stimmen; alle 6 .pck gebaut + per `verify_pack_cli.gd` real geladen,
  `config.json` kopiert, `manifest.json` (7 Packs) erzeugt — **exit 0**. Artefakt-Pfade im YAML matchen.
- **Lint wie CI:** `git ls-files … | xargs -0 gdlint` → exit 0; `gdformat --check` → exit 0.

## (4) Test-Abdeckungs-Ehrlichkeit

- `assert_true(true` / `check(true,` / `assert_false(false`: **0 Treffer**.
- Leere `test_`-Methoden (nur `pass`/`return`): **0**.
- Skript-Scan über alle `tests/**/test_*.gd`: **0 test_-Methoden ohne assert/check/fail_test**.
- 438 Methoden (Haupt-Runner) + 2705 Checks (W1c) — Zählwerte plausibel und stabil.

## (5) Screenshot-Skripte / xvfb

- 13 `tests/unit/screenshot_*.gd` — Präfix matcht **keine** Discovery (`begins_with("test_")` bzw.
  `test_ui_`); empirisch: 0 „screenshot“-Vorkommen in allen Runner-Logs. CI ruft sie nie auf.
- Alle CI-Steps laufen `--headless` ⇒ kein xvfb nötig; kein Discovery-Hänger möglich.

---

## Findings (priorisiert)

- **P0:** — keine.
- **P1:** — keine.
- **P2-1:** `run_w1c_tests.gd` hat **keinen Watchdog** (blankes `await case.call(...)`). Ein hängender
  `test_ui_*`-Test hängt den Step bis zum 30-min-Job-Timeout (Job wird trotzdem ROT, Reports werden
  via `if: always()` hochgeladen — aber 30 min verbrannt statt 120 s). Repro: Hänger-Test in Kopie → Runner steht.
- **P2-2:** 147 ObjectDB-Leaks bei `--import`-Exit (75 eigene GDScripts, s. o.) — zyklische
  preload-Referenzen im Autoload-/Net-/UI-Stack. Kosmetisch für CI (exit 0), verrauscht aber jedes
  Import-/Test-Log und kann echte Warnungen maskieren. Repro: `rm -rf .godot && godot --headless --verbose --path . --import`.
- **P3-1:** Hard-Runtime-Error in async Testmethode bricht die Coroutine ab ⇒ `done` wird nie gesetzt ⇒
  Fail erst nach 120 s Watchdog **pro Methode** (langsames Rot; >12 solcher Fälle ≈ Job-Timeout).
- **P3-2:** `--import` liefert exit 0 auch bei Import-Fehlern (Godot-Verhalten) — der Import-Step kann
  praktisch nur durch Crash rot werden; kaputte Assets fallen erst in Tests/Boot-Smoke auf.
- **P3-3:** `pip install "gdtoolkit==4.*"` (floating) — ein neues 4.x-Release kann Lint über Nacht
  röten; Pin auf exakte Version wäre robuster.
- **P3-4:** `build_packs.sh` schluckt `--export-pack`-Fehler per `|| true` (dokumentiert wegen
  bekanntem Leer-Pfad-ERROR) — Mitigation über Größen-Check + echtes Pack-Laden ist vorhanden und
  greift (verifiziert), bleibt aber eine bewusste Schwachstelle.
- **P3-5:** 140× Dummy-Renderer-`Parameter "t" is null` bei jedem CI-Import-Log (kein .godot-Cache in
  CI) — bekannt/harmlos, aber 140 ERROR-Zeilen im Artefakt irritieren beim Triage.
