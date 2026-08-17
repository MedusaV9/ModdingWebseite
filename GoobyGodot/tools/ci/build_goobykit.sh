#!/usr/bin/env bash
# GOOBY-WIDGETS: baut die statische Bibliothek des goobykit-iOS-Plugins
# (GOOBY-GODOT/ios/plugins/goobykit/goobykit.a) — laeuft im ios-ipa-Job auf
# macos VOR dem Godot-Export (der Export bindet die .a via goobykit.gdip ein,
# Preset-Schalter plugins/goobykit=true).
#
# Die lib ist bewusst godot-header-frei (nur Foundation): goobykit_init()
# reicht per NSClassFromString an die Swift-Klasse GoobyKitRuntime weiter,
# die tools/ci/inject_widgets.rb ins App-Target injiziert. Kompiliert als
# ObjC++ (.mm), damit das Symbol C++-gemangelt ist — exakt so ruft es der
# vom Godot-Exporter generierte Plugin-Initialisierungscode auf.
#
# Min-iOS wird aus export_presets.cfg ABGELEITET (gleiche Lehre wie
# verify_ipa.py: hart kodierte Erwartungen veralten).
set -euo pipefail

cd "$(dirname "$0")/../.."
PLUGIN_DIR="GOOBY-GODOT/ios/plugins/goobykit"
SRC="$PLUGIN_DIR/goobykit_bootstrap.mm"
OUT="$PLUGIN_DIR/goobykit.a"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "FEHLER: xcrun fehlt — dieses Skript laeuft nur auf macOS (CI: ios-ipa-Job)." >&2
  exit 1
fi
test -f "$SRC" || { echo "FEHLER: $SRC fehlt." >&2; exit 1; }

MIN_IOS="$(sed -n 's/^application\/min_ios_version="\(.*\)"$/\1/p' GOOBY-GODOT/export_presets.cfg | head -1)"
test -n "$MIN_IOS" || { echo "FEHLER: min_ios_version nicht im Preset gefunden." >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "goobykit.a bauen (arm64, min iOS $MIN_IOS) ..."
xcrun --sdk iphoneos clang++ -x objective-c++ -std=c++17 -fobjc-arc \
  -arch arm64 -miphoneos-version-min="$MIN_IOS" \
  -c "$SRC" -o "$WORK/goobykit_bootstrap.o"
xcrun --sdk iphoneos libtool -static -no_warning_for_no_symbols \
  -o "$OUT" "$WORK/goobykit_bootstrap.o"

# Beleg: das C++-gemangelte Init-Symbol muss exportiert sein, sonst reisst
# der Linker des Export-Projekts spaeter mit "undefined symbol" ab.
if ! xcrun nm -gU "$OUT" | grep -q "goobykit_init"; then
  echo "FEHLER: goobykit_init fehlt in $OUT — Symbolliste:" >&2
  xcrun nm -gU "$OUT" >&2
  exit 1
fi
echo "goobykit.a OK: $(du -h "$OUT" | cut -f1), Symbole:"
xcrun nm -gU "$OUT" | sed 's/^/  /'
