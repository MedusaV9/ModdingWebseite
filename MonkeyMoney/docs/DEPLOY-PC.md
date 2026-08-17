# DEPLOY: PC-Quickstart + Cloudflare-Tunnel (Hosting-Pfad B)

Der schnellste Weg zur Party: MONKEY MONEY läuft auf einem normalen PC/Laptop
im Wohnzimmer, iPad und Handys hängen im selben WLAN. Optional macht ein
Cloudflare-Tunnel den Server unter einer öffentlichen `https://`-URL
erreichbar (dann funktionieren auch alle Secure-Context-Features — es ist
derselbe Build, TECH-SPEC §1 „Ein Build, zwei Transport-Welten").

## Quickstart (LAN)

Voraussetzung: **Node ≥ 20** ([nodejs.org](https://nodejs.org)).

```bash
# ACHTUNG: -b cursor/monkey-money ist Pflicht — der Default-Branch des Repos
# enthält ein ANDERES Projekt (Minecraft-Mod).
git clone -b cursor/monkey-money --single-branch <repo-url> monkey-money && cd monkey-money
npm ci
npm run build     # Vite-Clients → client/dist + Server-Bundle → server/dist
npm start         # Server auf http://localhost:8080
```

Andere Ports/Pfade per Env: `PORT=3000 npm start`, Daten liegen unter
`DATA_DIR` (Default `./data`).

### Geräte verbinden

1. LAN-IP des PCs herausfinden:
   - Windows: `ipconfig` → „IPv4-Adresse" (z. B. `192.168.1.20`)
   - macOS/Linux: `ip addr` bzw. `ifconfig` → Adresse im `192.168.x.x`/`10.x.x.x`-Bereich
2. **iPad/Beamer-PC** (Bildschirm): `http://<lan-ip>:8080/` öffnen →
   „Bildschirm" wählen → Raum-Code, QR-Code und GM-PIN erscheinen.
3. **iPhones/Handys** (Spieler): im **selben WLAN** den QR scannen (oder
   `http://<lan-ip>:8080/join/CODE` tippen) → Name + Farbe → Lobby.
4. **Show-Master**: `http://<lan-ip>:8080/gm` → Raum-Code + GM-PIN (steht auf
   dem Bildschirm).

### Firewall-Hinweis

Beim ersten `npm start` fragt die Windows-Firewall nach — **„Zugriff
zulassen" für private Netzwerke** wählen, sonst erreichen die Handys den
Server nicht. Nachträglich: Windows-Sicherheit → Firewall → „Zugriff von App
durch Firewall zulassen" → Node.js für private Netze freigeben. Linux mit
ufw: `sudo ufw allow 8080/tcp`. macOS fragt ebenfalls beim ersten Start —
„Erlauben".

Wenn Geräte den Server trotzdem nicht sehen: manche Gast-/Mesh-WLANs haben
**Client-Isolation** („AP Isolation") aktiv — im Router abschalten oder das
normale WLAN nutzen.

### Grenzen des LAN-Pfads

`http://<lan-ip>` ist kein Secure Context — die App zeigt den
LAN-Modus-Badge und nutzt Fallbacks (NoSleep-Video statt Wake Lock, QR statt
Clipboard). Volle Feature-Matrix: `docs/TECH-SPEC.md` §4. Alle Features gibt
es über den Tunnel:

## Cloudflare-Tunnel (öffentliche https-URL)

Ein **Quick Tunnel** macht den lokalen Server ohne Registrierung unter einer
zufälligen `https://….trycloudflare.com`-URL erreichbar — praktisch, wenn
Mitspieler nicht im WLAN sind, und für Secure-Context-Features.

### Weg A: direkt aus der App-UI (empfohlen)

Seit Welle 4 startet der Server den Tunnel selbst — kein zweites Terminal:

1. **Screen-Lobby**: neben dem LAN-QR sitzt der Bereich **„🌐 Internet-Link"**
   → **„Link erstellen"** tippen → nach ein paar Sekunden erscheinen die
   öffentliche URL groß, ein eigener QR-Code für den Internet-Link und ein
   „Link kopieren"-Knopf. Der LAN-QR bleibt parallel bestehen — Gäste im
   WLAN nehmen weiter den kurzen Weg.
2. **GM-Cockpit**: dieselbe Steuerung als Tunnel-Karte in der Zone
   **„🎤 Show & Publikum"** (Start/Stop, Status, URL) — nur das aktive
   Cockpit und der Bildschirm des Raums dürfen starten/stoppen.
3. Ist `cloudflared` nicht installiert, zeigt die App **keine Fehlermeldung,
   sondern den passenden Install-Einzeiler** für dein OS (siehe unten) —
   danach einfach „Nochmal prüfen" tippen.

Ehrlichkeit & Sicherheit:

- **Jeder mit dem Link kann beitreten** — der 4-stellige Raum-Code bleibt
  zusätzlich nötig (steht im Warnhinweis der UI).
- Der Tunnel **endet mit dem Server-Stopp** (und per „Link beenden"-Knopf);
  Quick-URLs sind flüchtig — neuer Lauf = neue URL.
- **iPad-Standalone** (iPad = Server, docs/IPAD-SETUP.md): `cloudflared`
  läuft **nicht** auf iOS — die Lobby zeigt dort einen ehrlichen Hinweis
  statt des Knopfs. Internet-Links gibt es nur am PC/AMP-Server.

### cloudflared installieren

- **macOS:** `brew install cloudflared`
- **Windows:** `winget install Cloudflare.cloudflared`
- **Debian/Ubuntu:**

  ```bash
  curl -fL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o /tmp/cloudflared.deb
  sudo dpkg -i /tmp/cloudflared.deb
  ```

### Weg B: Tunnel im Terminal starten

Server laufen lassen (`npm start`), dann in einem zweiten Terminal:

```bash
bash tools/tunnel/start.sh          # Wrapper: hebt die Tunnel-URL deutlich hervor
# oder direkt:
cloudflared tunnel --url http://localhost:8080
```

Im Log erscheint nach wenigen Sekunden die zugewiesene URL, z. B.
`https://beispiel-affe-quiz.trycloudflare.com` — der Wrapper druckt sie in
einem gut sichtbaren Kasten. **Diese URL auf dem Bildschirm-Gerät öffnen**:
Der QR-Code in der Lobby basiert auf der Origin des Bildschirms (TECH-SPEC
§7.2) und zeigt den Mitspielern damit automatisch die richtige Tunnel-URL.

Hinweise:

- Quick-Tunnel-URLs sind **flüchtig** (neuer Lauf = neue URL) und ohne SLA —
  für den Spieleabend gedacht, nicht für Dauerbetrieb.
- Für Stammrunden: **benannten Tunnel** mit fester Domain einrichten
  (Cloudflare Zero Trust → Networks → Tunnels), dann bleibt die URL stabil.
- socket.io läuft durch den Tunnel via WebSocket, mit
  Long-Polling-Fallback — keine Extra-Konfiguration nötig.

## Entwicklung

```bash
npm run dev        # Server via tsx mit Watch (serviert client/dist — vorher 1× bauen)
npm test           # Vitest
npm run lint       # Prettier-Check + ESLint
npm run bots -- --players 3 --seed 42 --modus quick   # Bots spielen ein Match
```
