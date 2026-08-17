#!/usr/bin/env bash
# Cloudflare-Quick-Tunnel-Wrapper (TECH-SPEC §4/§8.4, docs/DEPLOY-PC.md):
# macht den lokalen MONKEY-MONEY-Server unter einer öffentlichen https://-URL
# erreichbar (Secure Context ⇒ Wake Lock, Gamepad etc. funktionieren).
#
#   bash tools/tunnel/start.sh            # Tunnel auf http://localhost:8080
#   PORT=3000 bash tools/tunnel/start.sh  # anderer lokaler Port
#
# Voraussetzung: der Server läuft bereits (npm start) und cloudflared ist
# installiert. Der Wrapper hebt die trycloudflare.com-URL deutlich hervor —
# diese URL (oder ihr QR auf dem Bildschirm) teilst du mit den Mitspielern.
# ACHTUNG: Quick-Tunnel-URLs sind flüchtig (neuer Lauf = neue URL, kein SLA).
# Für Stammrunden: benannten Tunnel mit fester Domain einrichten (Cloudflare
# Zero Trust → Networks → Tunnels).
set -euo pipefail

PORT="${PORT:-8080}"
LOKAL="http://localhost:${PORT}"

if ! command -v cloudflared >/dev/null 2>&1; then
  echo "FEHLER: cloudflared ist nicht installiert." >&2
  echo "" >&2
  echo "Installation:" >&2
  echo "  macOS:    brew install cloudflared" >&2
  echo "  Windows:  winget install Cloudflare.cloudflared" >&2
  echo "  Debian/Ubuntu:" >&2
  echo "    curl -fL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o /tmp/cloudflared.deb" >&2
  echo "    sudo dpkg -i /tmp/cloudflared.deb" >&2
  exit 1
fi

if ! curl -fsS "${LOKAL}/healthz" >/dev/null 2>&1; then
  echo "WARNUNG: Unter ${LOKAL} antwortet kein MONKEY-MONEY-Server (/healthz)." >&2
  echo "         Erst 'npm start' laufen lassen (oder PORT=... setzen)." >&2
fi

echo "Starte Cloudflare-Quick-Tunnel für ${LOKAL} …"
echo "(Beenden mit Strg+C — die URL verfällt dann.)"
echo ""

# cloudflared loggt die zugewiesene URL auf stderr; wir heben sie im Vorbeigehen
# hervor, der volle Log bleibt sichtbar (Fehlerdiagnose).
cloudflared tunnel --url "${LOKAL}" 2>&1 | while IFS= read -r zeile; do
  echo "$zeile"
  if [[ "$zeile" =~ (https://[a-z0-9-]+\.trycloudflare\.com) ]]; then
    url="${BASH_REMATCH[1]}"
    echo ""
    echo "=============================================================="
    echo "  TUNNEL STEHT:  ${url}"
    echo ""
    echo "  → Diese URL auf dem Bildschirm-Gerät öffnen — der QR-Code"
    echo "    in der Lobby zeigt dann automatisch die Tunnel-URL"
    echo "    (QR-Quelle ist die Screen-Origin, TECH-SPEC §7.2)."
    echo "=============================================================="
    echo ""
  fi
done
