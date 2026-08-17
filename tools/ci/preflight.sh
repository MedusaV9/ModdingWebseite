#!/usr/bin/env bash
# Preflight (FB-6/CI): prueft lokal ALLES, was die CI in gooby-godot.yml
# prueft — VOR jedem Push laufen lassen (AGENTS.md-Pflicht). Haelt beim
# ersten Fehler mit klarer Meldung + Fix-Hinweis an.
#
# Spiegelt exakt die CI-Jobs:
#   [1/8] gdformat --check   (lint-Job)      — gleiche Dateiliste: git ls-files
#   [2/8] gdlint             (lint-Job)
#   [3/8] GOOBY-SERVER npm ci                (linux-checks)
#   [4/8] Import bis vollstaendig + check_imports.py   (linux-checks/ios-ipa)
#   [5/8] GOOBY-SERVER Node-Suite            (linux-checks)
#   [6/8] tests/run_tests.gd inkl. echter Node-Netzintegration (linux-checks)
#   [7/8] tests/unit/run_w1c_tests.gd        (linux-checks)
#   [8/8] Boot-Smoke --quit                  (linux-checks)
#
# Aufruf (Repo-Wurzel):  bash tools/ci/preflight.sh
#   --lint-only   nur Schritte 1–2 (schnell, z. B. nach reinen Text-Edits)
#   --no-tests    Schritte 1–3 (wenn ein Testlauf gerade separat laeuft)
set -uo pipefail

cd "$(dirname "$0")/../.."
PROJECT="GOOBY-GODOT"
ISOLATED_GODOT="tools/ci/run_godot_isolated.sh"
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

# [1/8] gdformat --check — exakt das CI-Kommando (nur git-getrackte .gd;
# untracked Probe-Skripte brechen die CI NICHT, wohl aber vergessene Edits).
step "1/8" "gdformat --check (CI: lint)"
(
  cd "$PROJECT"
  git ls-files -z -- "*.gd" | xargs -0 --no-run-if-empty gdformat --check
) || fail "unformatierte .gd-Dateien (CI-lint wird rot)" \
  "cd $PROJECT && git ls-files -z -- '*.gd' | xargs -0 gdformat   # formatiert alles"

# [2/8] gdlint — faengt u. a. Dateilaengen-Verstoesse (max-file-lines).
step "2/8" "gdlint (CI: lint)"
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
command -v node >/dev/null || fail "node fehlt im PATH" \
  "Node.js >= 18 installieren (CI verwendet Node 22)."
command -v npm >/dev/null || fail "npm fehlt im PATH" \
  "npm passend zur Node-Installation bereitstellen."

# Release-Metadaten gelten auch für normale Branch-Builds: project.godot muss
# striktes Semver tragen; in CI werden Tag/Dispatch zusätzlich exakt verglichen.
python3 tools/ci/test_check_release_version.py \
  || fail "Release-Versionswächter-Selbsttest rot" "tools/ci/check_release_version.py prüfen."
python3 tools/ci/check_release_version.py \
  || fail "Release-Version inkonsistent" "Tag/Dispatch und GOOBY-GODOT/project.godot angleichen."
python3 tools/ci/test_configure_release_endpoint.py \
  || fail "Release-WSS-Wächter-Selbsttest rot" \
  "tools/ci/configure_release_endpoint.py prüfen."
python3 tools/ci/configure_release_endpoint.py \
  || fail "Release-WSS-Endpunkt fehlt/ist unsicher" \
  "Für Releases GOOBY_RELEASE_WSS_URL=wss://<öffentlicher-host>/ws setzen."

# [3/8] Reproduzierbare Server-Abhängigkeiten. Die Godot-Integration startet
# den ECHTEN Server; fehlende express/ws-Pakete dürfen nie als Skip grün werden.
step "3/8" "GOOBY-SERVER Dependencies installieren (CI: linux-checks)"
npm ci --prefix GOOBY-SERVER \
  || fail "Server-Dependencies konnten nicht installiert werden" \
  "GOOBY-SERVER/package-lock.json und npm-Zugriff prüfen."

# [4/8] Import bis vollstaendig — ein Einzeldurchlauf laesst abhaengige
# Ressourcen (Font-Varianten, SVGs) offen; deshalb Schleife + Fakten-Gate
# (dest_files existieren) statt Log-Grep. Identisch zur CI.
step "4/8" "Ressourcen importieren, bis alle Ziele existieren (CI: linux-checks/ios-ipa)"
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

# [5/8] Node-Suite plus [6/8 + 7/8] beide Godot-Test-Runner — exakt die
# CI-Kommandos. Das frische
# user:// verhindert, dass lokale AppSettings Erststart-UI verstecken, die
# ein frischer CI-Runner rendert (z. B. hints.hud_actions_seen).
step "5/8" "Node-Server-Suite (CI: linux-checks)"
npm test --prefix GOOBY-SERVER \
  || fail "Node-Server-Suite rot" "Fehler oben beheben, dann erneut."
python3 tools/ci/test_check_godot_log.py \
  || fail "Godot-Log-Gate-Selbsttest rot" "tools/ci/check_godot_log.py prüfen."

step "6/8" "Test-Runner inkl. echter Godot↔Node-Netzintegration (CI: linux-checks)"
GODOT_LOG_ALLOWLIST=tools/ci/godot-log-allowlist.txt \
  bash tools/ci/run_godot_checked.sh test-reports/run_tests.log -- \
  bash "$ISOLATED_GODOT" \
  godot --headless --path "$PROJECT" --script res://tests/run_tests.gd \
  || fail "Tests rot (res://tests/run_tests.gd)" "FAIL-Zeilen oben beheben, dann erneut."

step "7/8" "W1c-UI-Test-Runner (CI: linux-checks)"
bash tools/ci/run_godot_checked.sh test-reports/run_w1c_tests.log -- \
  bash "$ISOLATED_GODOT" \
  godot --headless --path "$PROJECT" --script res://tests/unit/run_w1c_tests.gd \
  || fail "UI-Tests rot (res://tests/unit/run_w1c_tests.gd)" "FAIL-Zeilen oben beheben, dann erneut."

# [8/8] Boot-Smoke — Projekt bootet headless ohne Skriptfehler.
step "8/8" "Boot-Smoke (CI: linux-checks)"
bash tools/ci/run_godot_checked.sh test-reports/boot_smoke.log -- \
  bash "$ISOLATED_GODOT" godot --headless --path "$PROJECT" --quit \
  || fail "Projekt bootet nicht (headless --quit)" "Parse-/Autoload-Fehler oben beheben."

echo ""
echo "PREFLIGHT GRUEN — alle CI-Pruefungen lokal bestanden. Push ist sicher."
