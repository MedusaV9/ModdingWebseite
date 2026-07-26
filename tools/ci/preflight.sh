#!/usr/bin/env bash
# Preflight (FB-6/CI): prueft lokal ALLES, was die CI in gooby-godot.yml
# prueft — VOR jedem Push laufen lassen (AGENTS.md-Pflicht). Haelt beim
# ersten Fehler mit klarer Meldung + Fix-Hinweis an.
#
# Spiegelt exakt die CI-Jobs:
#   [1/6] gdformat --check   (lint-Job)      — gleiche Dateiliste: git ls-files
#   [2/6] gdlint             (lint-Job)
#   [3/6] Import bis vollstaendig + check_imports.py   (linux-checks/ios-ipa)
#   [4/6] tests/run_tests.gd                 (linux-checks)
#   [5/6] tests/unit/run_w1c_tests.gd        (linux-checks)
#   [6/6] Boot-Smoke --quit                  (linux-checks)
#
# Aufruf (Repo-Wurzel):  bash tools/ci/preflight.sh
#   --lint-only   nur Schritte 1–2 (schnell, z. B. nach reinen Text-Edits)
#   --no-tests    Schritte 1–3 (wenn ein Testlauf gerade separat laeuft)
set -uo pipefail

cd "$(dirname "$0")/../.."
PROJECT="GOOBY-GODOT"
LINT_ONLY=0
NO_TESTS=0
for arg in "$@"; do
  case "$arg" in
    --lint-only) LINT_ONLY=1 ;;
    --no-tests) NO_TESTS=1 ;;
    *) echo "Unbekannte Option: $arg (erlaubt: --lint-only, --no-tests)"; exit 2 ;;
  esac
done

fail() {
  echo ""
  echo "PREFLIGHT ROT: $1"
  echo "HINWEIS: $2"
  exit 1
}

step() { echo ""; echo "== [$1] $2 =="; }

command -v gdformat >/dev/null || fail "gdformat fehlt" 'pip install "gdtoolkit==4.*"'
command -v gdlint >/dev/null || fail "gdlint fehlt" 'pip install "gdtoolkit==4.*"'

# [1/6] gdformat --check — exakt das CI-Kommando (nur git-getrackte .gd;
# untracked Probe-Skripte brechen die CI NICHT, wohl aber vergessene Edits).
step "1/6" "gdformat --check (CI: lint)"
(
  cd "$PROJECT"
  git ls-files -z -- "*.gd" | xargs -0 --no-run-if-empty gdformat --check
) || fail "unformatierte .gd-Dateien (CI-lint wird rot)" \
  "cd $PROJECT && git ls-files -z -- '*.gd' | xargs -0 gdformat   # formatiert alles"

# [2/6] gdlint — faengt u. a. Dateilaengen-Verstoesse (max-file-lines).
step "2/6" "gdlint (CI: lint)"
(
  cd "$PROJECT"
  git ls-files -z -- "*.gd" | xargs -0 --no-run-if-empty gdlint
) || fail "gdlint-Verstoesse (CI-lint wird rot)" \
  "Meldungen oben beheben; Dateilaengen-Fehler: Datei aufteilen (kein Disable)."

if [ "$LINT_ONLY" = "1" ]; then
  echo ""; echo "PREFLIGHT (lint-only) GRUEN."; exit 0
fi

command -v godot >/dev/null || fail "godot fehlt im PATH" \
  "bash tools/ci/install_godot.sh   # laedt Godot 4.4.1 und verlinkt es"

# [3/6] Import bis vollstaendig — ein Einzeldurchlauf laesst abhaengige
# Ressourcen (Font-Varianten, SVGs) offen; deshalb Schleife + Fakten-Gate
# (dest_files existieren) statt Log-Grep. Identisch zur CI.
step "3/6" "Ressourcen importieren, bis alle Ziele existieren (CI: linux-checks/ios-ipa)"
IMPORT_OK=0
for i in 1 2 3 4; do
  echo "--- Import-Durchlauf $i ---"
  godot --headless --path "$PROJECT" --import >/dev/null 2>&1 || true
  if python3 tools/ci/check_imports.py "$PROJECT"; then
    IMPORT_OK=1
    break
  fi
done
[ "$IMPORT_OK" = "1" ] || fail "Import nach 4 Durchlaeufen unvollstaendig" \
  "Fehlende Ziele oben; kaputte/gitignorte Quelldatei? .import ohne Quelle geloescht?"

if [ "$NO_TESTS" = "1" ]; then
  echo ""; echo "PREFLIGHT (ohne Tests) GRUEN."; exit 0
fi

# [4/6 + 5/6] Beide Test-Runner — exakt die CI-Kommandos.
step "4/6" "Test-Runner (CI: linux-checks)"
godot --headless --path "$PROJECT" --script res://tests/run_tests.gd \
  || fail "Tests rot (res://tests/run_tests.gd)" "FAIL-Zeilen oben beheben, dann erneut."

step "5/6" "W1c-UI-Test-Runner (CI: linux-checks)"
godot --headless --path "$PROJECT" --script res://tests/unit/run_w1c_tests.gd \
  || fail "UI-Tests rot (res://tests/unit/run_w1c_tests.gd)" "FAIL-Zeilen oben beheben, dann erneut."

# [6/6] Boot-Smoke — Projekt bootet headless ohne Skriptfehler.
step "6/6" "Boot-Smoke (CI: linux-checks)"
godot --headless --path "$PROJECT" --quit \
  || fail "Projekt bootet nicht (headless --quit)" "Parse-/Autoload-Fehler oben beheben."

echo ""
echo "PREFLIGHT GRUEN — alle CI-Pruefungen lokal bestanden. Push ist sicher."
