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
