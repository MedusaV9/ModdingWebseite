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

# 3) Test-Runner (Exit-Code 0 = grün; entdeckt tests/**/test_*.gd)
godot --headless --path GOOBY-GODOT --script res://tests/run_tests.gd

# 4) Lint + Format-Check — AUS GOOBY-GODOT/ heraus aufrufen, damit die
#    .gdlintrc dort gefunden wird (gdlint sucht ab CWD aufwärts)
cd GOOBY-GODOT
git ls-files -z -- "*.gd" | xargs -0 gdlint
git ls-files -z -- "*.gd" | xargs -0 gdformat --check

# 5) Boot-Smoke (bootet die Main-Szene und beendet sich)
godot --headless --path GOOBY-GODOT --quit
```

Formatieren (statt nur checken): `gdformat <dateien>` — Godot-Stil = Tabs,
Zeilenlänge 100 (siehe `.editorconfig` + `.gdlintrc` in `GOOBY-GODOT/`).

## Dateien

- `install_godot.sh` — lädt Godot 4.4.1 (Linux x86_64) nach
  `~/.cache/godot-bin` (im CI via actions/cache persistiert) und verlinkt es
  als `godot`. Env-Overrides: `GODOT_VERSION`, `GODOT_CACHE_DIR`.

## Workflow `.github/workflows/gooby-godot.yml`

- Triggert NUR auf `GOOBY-GODOT/**`, `tools/ci/**` und sich selbst.
  Der alte Web-Workflow `gooby-ios.yml` (triggert auf `GOOBY/**`) bleibt
  unberührt.
- Job **linux-checks**: Godot cachen/installieren → gdtoolkit → `--import` →
  Test-Runner → gdlint → `gdformat --check` → Boot-Smoke.
- Job **ios-ipa-skeleton**: dokumentiertes Gerüst, per `if: false`
  deaktiviert. Es fehlt `GOOBY-GODOT/export_presets.cfg` mit einem
  "iOS"-Preset (Owner: W2b) — erst dann können Export + `xcodebuild`
  (unsigned, Sideload) laufen. Scharfschalten: `if: false` entfernen und die
  TODO-Steps (Projekt-/Scheme-Name) an den echten Export anpassen.

## Konventionen für neue Tests (alle Wellen)

- Datei `GOOBY-GODOT/tests/unit/test_<thema>.gd`, erbt von `TestCase`,
  Methoden `test_*` (async/await erlaubt — der Runner awaitet).
- Der Runner `tests/run_tests.gd` + `tests/test_case.gd` gehören W1a:
  NIE editieren, nur eigene Testdateien anlegen (Auto-Discovery).
- Szenen-Smoke-Muster: siehe `tests/unit/test_boot_smoke.gd`.
