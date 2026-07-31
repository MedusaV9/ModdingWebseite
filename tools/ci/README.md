# tools/ci — CI-Helfer & lokale Checks für GOOBY-GODOT (Owner: W1a)

## Lokal linten & testen (identisch zum CI-Job `linux-checks`)

Voraussetzungen: Godot **4.4.1** als `godot` im PATH (auf der VM vorhanden;
sonst `bash tools/ci/install_godot.sh`), Python + pip.

```bash
# 1) gdtoolkit (gdlint + gdformat — es gibt kein natives Godot-Lint)
pip install "gdtoolkit==4.*"

# 2) Import (PFLICHT nach frischem Checkout / gelöschtem .godot/ —
#    ohne Import-Cache schlagen load() von Szenen/Ressourcen fehl)
godot --headless --path GOOBY-GODOT --import

# 3) Beide Test-Runner mit frischem user:// (wie CI/Preflight)
bash tools/ci/run_godot_isolated.sh \
  godot --headless --path GOOBY-GODOT --script res://tests/run_tests.gd
bash tools/ci/run_godot_isolated.sh \
  godot --headless --path GOOBY-GODOT --script res://tests/unit/run_w1c_tests.gd

# 4) Lint + Format-Check — AUS GOOBY-GODOT/ heraus aufrufen, damit die
#    .gdlintrc dort gefunden wird (gdlint sucht ab CWD aufwärts)
cd GOOBY-GODOT
git ls-files -z -- "*.gd" | xargs -0 gdlint
git ls-files -z -- "*.gd" | xargs -0 gdformat --check

# 5) Boot-Smoke (bootet die Main-Szene mit frischem user:// und beendet sich)
bash tools/ci/run_godot_isolated.sh godot --headless --path GOOBY-GODOT --quit
```

Formatieren (statt nur checken): `gdformat <dateien>` — Godot-Stil = Tabs,
Zeilenlänge 100 (siehe `.editorconfig` + `.gdlintrc` in `GOOBY-GODOT/`).

## Dateien

- `install_godot.sh` — lädt Godot 4.4.1 (Linux x86_64) nach
  `~/.cache/godot-bin` (im CI via actions/cache persistiert) und verlinkt es
  als `godot`. Env-Overrides: `GODOT_VERSION`, `GODOT_CACHE_DIR`.
- `run_godot_isolated.sh` — führt einen Godot-Befehl mit temporärem `HOME`
  und frischen XDG-Verzeichnissen aus. Dadurch können lokale Einstellungen
  keine Erststart-UI unterdrücken, die ein frischer CI-Runner prüft.

## Workflow `.github/workflows/gooby-godot.yml`

- Triggert NUR auf `GOOBY-GODOT/**`, `tools/ci/**` und sich selbst.
  Der alte Web-Workflow `gooby-ios.yml` (triggert auf `GOOBY/**`) bleibt
  unberührt.
- Job **linux-checks**: Godot cachen/installieren → gdtoolkit → `--import` →
  beide isolierten Test-Runner → Boot-Smoke.
- Job **ios-ipa**: exportiert auf macOS ein Xcode-Projekt, baut unsigned und
  lädt `GOOBY-godot-unsigned-ipa` hoch. Er läuft auch nach roten Linux-Tests,
  damit ein testbares Build verfügbar bleibt; dieses Artefakt heißt dann klar
  `GOOBY-godot-unsigned-ipa-UNVERIFIED-linux-<status>`.

## Leak-Gate über alle Minigames (Preflight-fähig, W13C)

`GOOBY-GODOT/tests/tools/leak_gate.gd` startet jedes registrierte Minigame
regulär über den echten `MinigameHost` (Countdown 0, fester Seed), lässt es
2 s laufen, beendet über den Quit-Pfad und misst danach Waisen:
Orphan-Nodes (`Performance.OBJECT_ORPHAN_NODE_COUNT`), Node-Drift im Baum
(rekursive Zählung ab root) und — nur als Report — ObjectDB-Zuwachs
(`OBJECT_COUNT`/`OBJECT_RESOURCE_COUNT`; der Resource-Cache behält beim
ersten Laden eines Spiels dessen Assets legitim). Ein ungemessener
Warm-up-Lauf vor der ersten Baseline fängt lazy Framework-Zustand ab.

```bash
bash tools/ci/run_godot_isolated.sh \
  godot --headless --path GOOBY-GODOT --script res://tests/tools/leak_gate.gd
```

Gate: pro Spiel Orphan-Zuwachs == 0 UND Node-Drift == 0. Verstöße erscheinen
als `LEAK <spiel>: +n orphans, +m nodes`; Exit-Code 0 = dicht, 1 = Leck.
Laufzeit ~2 min (38 Spiele × ~3 s). NICHT automatisch in `preflight.sh`/CI
eingehängt — das entscheidet der Orchestrator.

## Konventionen für neue Tests (alle Wellen)

- Datei `GOOBY-GODOT/tests/unit/test_<thema>.gd`, erbt von `TestCase`,
  Methoden `test_*` (async/await erlaubt — der Runner awaitet).
- Der Runner `tests/run_tests.gd` + `tests/test_case.gd` gehören W1a:
  NIE editieren, nur eigene Testdateien anlegen (Auto-Discovery).
- Szenen-Smoke-Muster: siehe `tests/unit/test_boot_smoke.gd`.
