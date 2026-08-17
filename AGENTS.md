# AGENTS.md

Arbeitsregeln für Agents in diesem Repo (GOOBY Godot-Rewrite).

## GOOBY-GODOT: Preflight-Pflicht vor jedem Push

- **Vor JEDEM Push, der `GOOBY-GODOT/**`, `tools/ci/**` oder
  `.github/workflows/gooby-godot.yml` berührt, MUSS `bash tools/ci/preflight.sh`
  lokal grün durchlaufen.** Das Skript spiegelt exakt die CI
  (gdformat --check, gdlint, Import-bis-vollständig via
  `tools/ci/check_imports.py`, beide Test-Runner, Boot-Smoke) und bricht mit
  klarem Fix-Hinweis ab. Hintergrund: 10 von 11 roten CI-Runs (W6/W7) waren
  vergessene `gdformat`-Läufe. Schnellvarianten: `--lint-only` (nur
  Format+Lint), `--no-tests` (bis inkl. Import-Gate).
- Temporäre Probe-/Debug-`.gd`-Skripte vor dem Push löschen oder formatieren —
  ALLES git-Getrackte unter `GOOBY-GODOT/` läuft durch gdlint/gdformat, auch
  `tests/` und `tools/`.
- Die `.ipa`-Verifikation (`tools/ci/verify_ipa.py`) leitet ihre Erwartungen
  (Orientierungen, Bundle-Id, Min-iOS, Device-Family) aus
  `GOOBY-GODOT/export_presets.cfg` ab — Preset-Änderungen brauchen KEINE
  Workflow-Anpassung mehr. Sie druckt am Ende
  „.ipa gebaut: X MB, Y Dateien im PCK" als Erfolgs-Beleg.
- Zeitabhängige Logik/Tests: Zeit und Zufall IMMER injizieren
  (`Clock`-Muster von `game_state.gd`, RNG als Parameter) — keine
  OS-Uhr/`randomize()` in testbarer Kernlogik.

## Cursor Cloud specific instructions

- **Toolchain (frische VM):** Godot 4.4.1 via `bash tools/ci/install_godot.sh`
  (nach `/usr/local/bin/godot`); gdtoolkit via `pip3 install --user "gdtoolkit==4.*"`
  (`~/.local/bin` in den PATH — non-interaktive Shells brauchen
  `export PATH="$HOME/.local/bin:$PATH"`); Server-Deps via `npm install` in
  `GOOBY-SERVER/` (sonst schlagen die 2 Netz-Integrationstests der Hauptsuite
  fehl: „Cannot find package 'express'"). Blender 4.0.2 via apt (nur für
  `tools/blender/`-Pipelines nötig).
- **Die VM hat wenige Kerne** — parallele Godot-Instanzen vermeiden; die volle
  Preflight (`bash tools/ci/preflight.sh`) dauert ~10–15 min (der Haupt-Runner
  allein ~12 min, nicht die ~30 s aus dem Runner-Kopf). Einzelne
  Testdateien laufen ohne den Runner über ein Wrapper-Skript nach dem Muster
  von `tests/run_tests.gd` (SceneTree-Skript per absolutem Pfad an
  `--script` übergeben; Aufruf immer über `tools/ci/run_godot_isolated.sh`).
  Arbeiten MEHRERE Subagents parallel im selben Worktree, JEDEN Godot-Aufruf
  mit `flock /tmp/gooby_godot.lock …` serialisieren (bewährt in W19; achtet
  darauf, dass kein hängender Runner den Lock dauerhaft hält).
- **Import-Cache-Gotcha:** Neue `class_name`-Skripte/Assets brauchen EINMAL
  `godot --headless --path GOOBY-GODOT --import`, sonst wirft der Test-Runner
  Parse-Errors (staler global_script_class_cache); erzeugte `.uid`/`.import`
  gehören MIT committet. Parallele `--import`-Läufe vermeiden (Cache-Race).
- **Repo-Umzug (W16) + Branch-Linie:** Das Projekt lebt im Repo
  `MedusaV9/MinecraftBubbleShieldMod`; aktueller Arbeits-Branch seit W19:
  `cursor/gooby-godot-loop-d1d8` (Linie: `cursor/gooby-godot-rewrite-d1d8`
  aus `MedusaV9/CustomServerPrivate` → `loop-2c10` → `loop-next` →
  `loop-d1d8`, jeweils voller Verlauf). `main` dieses Repos enthält ein
  ANDERES Projekt (Minecraft-Mod „Bubble Shield", Java/Gradle) — auf diesem
  Branch nicht anfassen. Der User schreibt live in `UserFeedback.md` (auch
  per Web-Commit, ggf. auf einem der ÄLTEREN gooby-Branches → vor dem Push
  alle gooby-Branches auf neue UserFeedback-Commits prüfen und übernehmen) —
  Datei vor und nach jeder Runde lesen, Erledigtes abhaken.
- **CI:** Jeder Push auf `GOOBY-GODOT/**` baut die unsignierte .ipa (Artefakt
  `GOOBY-godot-unsigned-ipa`, Job `ios-ipa` auf macos-15, ~10-12 min).
  Versionierte GitHub-Releases: Tag `ipa-v<semver>` pushen (Job `release`).
  `gh` nur lesend nutzen (`gh run list/view`).
