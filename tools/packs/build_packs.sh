#!/usr/bin/env bash
# GOOBY Pack-Builder (W2b UPDATES; Doc B §5.1).
#
# Baut pro GOOBY-GODOT/content/<id>/ (mit pack.json) ein .pck über
# `godot --headless --export-pack "pack-<id>"` (Presets: GOOBY-GODOT/
# export_presets.cfg, data-only via exclude_filter), verifiziert jedes Pack
# durch echtes Laden (scripts/updates/verify_pack_cli.gd — fängt „JSON-Filter
# vergessen“-Fehler) und erzeugt am Ende manifest.json (build_manifest.mjs).
# Der config-„Pack“ ist KEIN PCK: data/config.json wird 1:1 kopiert.
#
# Aufruf:  tools/packs/build_packs.sh [pack_id|all]
# Env:     GODOT_BIN (default: godot)
#          PACKS_OUT (default: GOOBY-GODOT/build/packs — gitignored)
#          RELEASE_BASE_URL (z. B. https://github.com/OWNER/REPO/releases/download;
#                            leer = file://-URLs für lokale Tests)
#          RELEASE_TAG_MODE (single|per-pack, default single — s. docs/UPDATES.md §6)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT="$ROOT/GOOBY-GODOT"
OUT="${PACKS_OUT:-$PROJECT/build/packs}"
GODOT_BIN="${GODOT_BIN:-godot}"
ONLY="${1:-all}"

command -v "$GODOT_BIN" >/dev/null || { echo "FEHLER: godot nicht im PATH (GODOT_BIN setzen)."; exit 1; }
command -v node >/dev/null || { echo "FEHLER: node nicht im PATH."; exit 1; }

mkdir -p "$OUT"

echo "== Import (PNG→ctex etc.; Pflicht vor --export-pack, Doc B §7) =="
"$GODOT_BIN" --headless --path "$PROJECT" --import >"$OUT/import.log" 2>&1 \
  || { echo "FEHLER: --import fehlgeschlagen, siehe $OUT/import.log"; exit 1; }

built=0
for pack_json in "$PROJECT"/content/*/pack.json; do
  dir="$(dirname "$pack_json")"
  id="$(node -p "JSON.parse(require('fs').readFileSync('$pack_json','utf8')).id")"
  ver="$(node -p "JSON.parse(require('fs').readFileSync('$pack_json','utf8')).version")"
  if [ "$ONLY" != "all" ] && [ "$ONLY" != "$id" ]; then continue; fi

  if [ "$id" = "config" ]; then
    # config ist plain JSON (sofort wirksam, ohne Neustart — Doc B §1.1)
    cp "$dir/data/config.json" "$OUT/config.json"
    echo "OK  config v$ver -> $OUT/config.json"
    built=$((built + 1))
    continue
  fi

  out_pck="$OUT/$id-v$ver.pck"
  echo "== Baue $id v$ver -> $out_pck =="
  "$GODOT_BIN" --headless --path "$PROJECT" --export-pack "pack-$id" "$out_pck" \
    >"$OUT/$id.export.log" 2>&1 || true
  # --export-pack loggt einen bekannten, harmlosen Leer-Pfad-ERROR (s. docs/
  # UPDATES.md §8) — entscheidend ist: Datei da + Pack lädt + pack.json lesbar.
  [ -s "$out_pck" ] || { echo "FEHLER: $out_pck fehlt/leer, siehe $OUT/$id.export.log"; exit 1; }
  "$GODOT_BIN" --headless --path "$PROJECT" \
    --script res://scripts/updates/verify_pack_cli.gd -- \
    --pack="$out_pck" --id="$id" --expect-version="$ver" \
    || { echo "FEHLER: Smoketest für $id fehlgeschlagen."; exit 1; }
  echo "OK  $id v$ver ($(stat -c%s "$out_pck") Bytes)"
  built=$((built + 1))
done

[ "$built" -gt 0 ] || { echo "FEHLER: kein Pack gebaut (Filter '$ONLY'?)."; exit 1; }

echo "== manifest.json erzeugen =="
node "$ROOT/tools/packs/build_manifest.mjs" \
  --project "$PROJECT" --dir "$OUT" \
  --base-url "${RELEASE_BASE_URL:-}" --tag-mode "${RELEASE_TAG_MODE:-single}"

echo "== Fertig: $OUT =="
ls -la "$OUT" | grep -Ev "\.log$" || true
