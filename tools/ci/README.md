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
- `run_playtest.sh` — startet EINEN Lauf der Playtest-Harness
  (`GOOBY-GODOT/tests/tools/playtest_harness.gd`, Doku im Datei-Kopf dort):
  echtes Spiel unter xvfb/llvmpipe, Screenshot pro Schritt, Report als
  Markdown. Der xvfb-Screen wird IMMER exakt auf das angefragte Fenster-
  format (`[BxH]`, Default 2868x1320) gestellt — der xvfb-Default
  1280x1024 wäre kleiner als das Fenster und erzeugte Phantom-Safe-Insets
  (Befund B6 W18: alle Zentrierungen in Screenshots verschoben).
  **Geräte-Metriken sind DEFAULT AN (W20/D4):** jeder Lauf simuliert das
  Leitgerät iPhone 17 Pro Max (Retina-`screen_scale` 3.0 + Dynamic-Island-
  Safe-Insets, Werte wie `fb3_ui_audit.SIZES`) — Screenshots und Proben
  zeigen damit die ECHTE Geräte-Enge (UiScale-f ≈ 1,64 statt 1,0; ohne die
  Simulation war die UI in allen Playtest-Screenshots ~40 % kleiner und
  randnäher als auf dem Gerät). Für Vergleiche mit alten Läufen:
  `PLAYTEST_DEVICE_METRICS=0 tools/ci/run_playtest.sh <flow>`.

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

## FB3-UI-Audit (Screens × Geräteformate, seit W20/P4 mit Dauer-Gates)

`GOOBY-GODOT/tests/unit/fb3_ui_audit.gd` bootet das echte Spiel, öffnet
34+ Screens/Overlays in 6 Geräteformaten (Leitformat iPhone 17 Pro Max
quer zuerst) MIT simulierten Geräte-Metriken und prüft safe_area, tap,
overlap, offscreen und content_mitte. **Seit W20/P4 zusätzlich** (Checks
in `tests/unit/fb3_audit_extra.gd`): `falz` (Unter-der-Falz-Wache — jedes
Bedienelement sichtbar ODER scrollbar), `stretch` (Vollbreite-Balken
> 85 % Canvas ohne Inhaltsspalte; Cover-Verzerrung ≠ Quell-Aspekt),
`kombi_overlap` (provozierte Kombinationen Toast×Topbar und Gooby-
Blase×Dock, Stationen 23/24) sowie die **Leerflächen-Metrik** als
Report-Abschnitt (kein Gate). Braucht einen echten Renderer:

```bash
FB3_OUT=/tmp/gooby-godot/artifacts/FB3/audit \
  flock /tmp/gooby_godot.lock tools/ci/run_godot_isolated.sh \
  xvfb-run -a -s "-screen 0 2868x2868x24" godot --path GOOBY-GODOT \
  --rendering-method gl_compatibility --rendering-driver opengl3 \
  --audio-driver Dummy --script res://tests/unit/fb3_ui_audit.gd
```

Befunde → `FB3_OUT/befunde.md` (+ `.json`) mit Screenshot pro Station.
`FB3_FORMATS=quer_2868x1320,hoch_1320x2868` prüft nur ein Format-Subset
(schnelle Nach-Fix-Verifikation, ~6 min statt Voll-Lauf). NICHT in
`preflight.sh`/CI eingehängt (Werkzeug wie das Leak-Gate — der
Orchestrator entscheidet, wann Voll-Läufe laufen).

## Orientierungs-Audit (Asset-Ausrichtung, W18)

`GOOBY-GODOT/tools/audit/orientation_audit.gd` mountet alle Welt-Szenen
headless (alle Platzierungen entstehen prozedural — Fix-Ort ist immer das
Builder-Skript, nie die .tscn) und prüft jeden sichtbaren Node3D auf
Spiegelung/negative Scale/NaN, Kipp-Winkel gegen +Y (Aufrecht-Kategorien
per Namens-Heuristik, Ausnahmeliste für absichtlich Gekipptes),
Gebäude-Yaw-Raster (15°) und Boden-Kontakt (Stütz-AABBs bzw.
`RanchGelaende.hoehe`; Stadt-Fahrzeuge gegen `CityCarFeel.ROAD_Y`).

```bash
bash tools/ci/run_godot_isolated.sh godot --headless --audio-driver Dummy \
  --path GOOBY-GODOT --script res://tools/audit/orientation_audit.gd
```

Env: `GOOBY_AUDIT_OUT` (Ziel-Markdown, Default
`/tmp/gooby-godot/artifacts/orientation_findings.md`; daneben immer ein
`.json`), `GOOBY_AUDIT_SCENES` (Komma-Liste von Szenen-Id-Substrings, z. B.
`ranch,city`; leer = alle Szenen). Befunde in drei Graden
(SICHER/WAHRSCHEINLICH/PRÜFEN) mit Ist-Transform + Fix-Vorschlag; Exit-Code
immer 0 (Report-Werkzeug, kein Gate). Max. EINE Godot-Instanz, kein
`godot --import` parallel (AGENTS.md). MultiMesh-Instanzen sind headless
nicht rücklesbar (nur gezählt); Details im Datei-Kopf des Skripts.

## Konventionen für neue Tests (alle Wellen)

- Datei `GOOBY-GODOT/tests/unit/test_<thema>.gd`, erbt von `TestCase`,
  Methoden `test_*` (async/await erlaubt — der Runner awaitet).
- Der Runner `tests/run_tests.gd` + `tests/test_case.gd` gehören W1a:
  NIE editieren, nur eigene Testdateien anlegen (Auto-Discovery).
- Szenen-Smoke-Muster: siehe `tests/unit/test_boot_smoke.gd`.
