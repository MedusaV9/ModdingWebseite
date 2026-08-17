#!/usr/bin/env bash
# Lädt Godot 4.4.1 (Linux x86_64, headless-fähig) in einen Cache-Ordner und
# macht das Binary als `godot` verfügbar. Wird vom CI-Job linux-checks in
# .github/workflows/gooby-godot.yml benutzt (der Cache-Ordner ist dort per
# actions/cache persistiert); lokal ebenfalls nutzbar. Owner: W1a.
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.4.1}"
CACHE_DIR="${GODOT_CACHE_DIR:-$HOME/.cache/godot-bin}"
BIN="$CACHE_DIR/Godot_v${GODOT_VERSION}-stable_linux.x86_64"

if [ ! -x "$BIN" ]; then
  mkdir -p "$CACHE_DIR"
  URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
  echo "Lade $URL ..."
  curl -fL --retry 3 -o "$CACHE_DIR/godot.zip" "$URL"
  unzip -o -q "$CACHE_DIR/godot.zip" -d "$CACHE_DIR"
  rm -f "$CACHE_DIR/godot.zip"
  chmod +x "$BIN"
else
  echo "Godot ${GODOT_VERSION} bereits im Cache: $BIN"
fi

# Als `godot` verlinken: /usr/local/bin (CI-Runner, passwortloses sudo)
# oder ~/.local/bin als Fallback.
if sudo -n true 2>/dev/null; then
  sudo ln -sf "$BIN" /usr/local/bin/godot
elif [ -w /usr/local/bin ]; then
  ln -sf "$BIN" /usr/local/bin/godot
else
  mkdir -p "$HOME/.local/bin"
  ln -sf "$BIN" "$HOME/.local/bin/godot"
  echo "Hinweis: $HOME/.local/bin muss im PATH liegen."
fi

"$BIN" --version
