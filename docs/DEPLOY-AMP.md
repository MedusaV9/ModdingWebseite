# DEPLOY: AMP-Server (Hosting-Pfad A, HTTP)

Schritt-für-Schritt-Anleitung für den Betrieb auf einem CubeCoders-AMP-Server
mit dem generischen Node-App-Runner. Dieser Pfad ist bewusst **NUR HTTP** —
was das für Browser-Features bedeutet, steht am Ende (und ausführlich in
`docs/TECH-SPEC.md` §4).

Grundsätze (TECH-SPEC §1.3/§8.4): **AMP sieht nie einen Build** — das
Deploy-Artefakt ist fertig gebaut. **Keine nativen Node-Module** — `npm ci`
kompiliert nichts, node-gyp kommt nie vor.

## 1. Deploy-Artefakt besorgen

Das Artefakt besteht aus diesen Pfaden (synchron zur `path:`-Liste des
`build`-Jobs in `.github/workflows/monkey-money.yml`):

| Pfad                | Inhalt                                                                                          |
| ------------------- | ----------------------------------------------------------------------------------------------- |
| `client/dist/`      | Gebaute Clients (Landing, Bühne, Spieler, GM, Standalone-Host)                                  |
| `server/dist/`      | Server-Bundle (`index.js`)                                                                      |
| `content/packs/`    | Fragen-Packs (JSON)                                                                             |
| `content/musik/`    | Song-Katalog + Snippets (`songs.json`, `media/`) → `/media-musik/*` — ohne sie 404en ALLE Songs |
| `assets/`           | Laufzeit-Medien → `/media/*`: Pixel-Bilder, Logo-Stinger, 21 Tutorial-Videos, Musik-Fixtures    |
| `package.json`      | Runtime-Dependencies                                                                            |
| `package-lock.json` | Lockfile für `npm ci --omit=dev`                                                                |

Wichtig: Der Server findet `assets/` und `content/musik/` **dist-relativ**
(`server/core/http.ts#findMediaRoot`/`findMusikMediaRoot` lösen
`server/dist/../../assets` bzw. `…/content/musik/media` auf) — beide Ordner
müssen also neben `server/dist/` im App-Root liegen, sonst liefern
Logo-Stinger, Pixel-Fragen, Tutorial-Videos und Songs nur 404.

**Variante A — aus der CI (empfohlen):** Jeder Push baut in GitHub Actions das
Artefakt `monkey-money-dist` (Workflow „MONKEY MONEY", Job `build`). Auf der
Actions-Seite des Laufs herunterladen und entpacken.

**Variante B — selbst bauen:** Auf einem Rechner mit Node ≥ 20:

```bash
# ACHTUNG: -b cursor/monkey-money ist Pflicht — der Default-Branch des Repos
# enthält ein ANDERES Projekt (Minecraft-Mod).
git clone -b cursor/monkey-money --single-branch <repo-url> monkey-money && cd monkey-money
npm ci
npm run build
# Deploy-Zip schnüren:
zip -r monkey-money-deploy.zip client/dist server/dist content/packs content/musik assets package.json package-lock.json
```

**Variante C — ganzes Repo per git:** Auch möglich (AMP-Instanz mit
git-Zugriff), dann muss der Build-Schritt (`npm ci && npm run build`) einmalig
im Update-Task der Instanz laufen. Varianten A/B sind schlanker.

## 2. AMP-Instanz anlegen

1. In AMP eine neue Instanz erstellen: **„Generic Module"** (Application
   Deployment) — der generische App-Runner, kein Spiel-Template.
2. Runtime: **Node.js** (Version ≥ 20 wählen, Ziel 22).
3. App-Verzeichnis: das entpackte Deploy-Artefakt hochladen (AMP-Dateimanager
   oder SFTP) — die Struktur `client/dist/`, `server/dist/`, `content/packs/`,
   `content/musik/`, `assets/`, `package.json`, `package-lock.json` muss im
   App-Root liegen (Medien-Ordner dist-relativ, siehe §1).

## 3. Installieren + Start-Kommando

Einmalig (und nach jedem Update mit geändertem Lockfile) als Update-/
Install-Task der Instanz:

```bash
npm ci --omit=dev
```

Start-Kommando der Instanz:

```bash
node server/dist/index.js
```

Ein Prozess, kein Cluster — 8 Spieler sind Grundrauschen.

## 4. Umgebungsvariablen (AMP-Panel)

| Variable    | Pflicht  | Bedeutung                                                                                                                     |
| ----------- | -------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `PORT`      | ja       | Der von AMP zugewiesene HTTP-Port — der Server respektiert strikt `process.env.PORT` (Default 8080)                           |
| `DATA_DIR`  | ja       | **Persistenter** Pfad für Saves/Event-Logs/Stats — ein Verzeichnis wählen, das AMP-Updates NICHT wegputzen (Default `./data`) |
| `MAX_ROOMS` | optional | Obergrenze gleichzeitiger Räume                                                                                               |

## 5. Port-Freigabe + Monitoring

1. Den `PORT` in der AMP-Portfreigabe (Port-Mapping der Instanz) als **TCP**
   öffnen — socket.io läuft über denselben HTTP-Port (WebSocket-Upgrade +
   Long-Polling-Fallback, kein zweiter Port nötig).
2. Health-Check für AMPs Monitoring: `GET /healthz` antwortet
   `{"ok":true,...}` — als HTTP-Check der Instanz eintragen.

Danach ist die Show unter `http://<server-ip>:<port>/` erreichbar: Bildschirm
auf iPad/PC öffnen, iPhones joinen per QR.

## 6. `data/`-Persistenz — wichtig

Unter `DATA_DIR` liegen Event-Logs (`events/*.jsonl`), Raum-Metadaten und
künftig Save-Slots/Profile. Zwei Regeln:

- `DATA_DIR` auf einen Pfad legen, der Updates überlebt (außerhalb des
  Verzeichnisses, das beim Artefakt-Austausch geleert wird).
- Backup = `DATA_DIR` zippen. Mehr braucht es nicht (JSON/JSONL-Dateien,
  atomar geschrieben).

## 7. Update-Prozedur

1. Neues `monkey-money-dist`-Artefakt aus der CI laden.
2. Instanz stoppen.
3. `client/dist/`, `server/dist/`, `content/packs/`, `content/musik/`,
   `assets/`, `package.json`, `package-lock.json` im App-Root ersetzen
   (gleiche Liste wie §1) — `DATA_DIR` NICHT anfassen.
4. Nur wenn sich `package-lock.json` geändert hat: `npm ci --omit=dev` erneut
   laufen lassen.
5. Instanz starten, `GET /healthz` prüfen — und einmal
   `GET /media/video/logo_stinger.webm` (muss 200 sein, sonst fehlen die
   Medien-Ordner aus §1).

## 8. HTTP-only-Wahrheiten (Erwartungsmanagement)

`http://<lan-ip>` ist kein Secure Context — die App zeigt dann den
**LAN-Modus-Badge** und blendet Secure-Context-Features sauber aus (Wake Lock
→ NoSleep-Video-Fallback, Clipboard → QR + Tipp-URL, Gamepad nur am
Host-PC/Tunnel). Details und die komplette Feature-Matrix: `docs/TECH-SPEC.md`
§4. Wer alle Features will, nimmt zusätzlich den Tunnel-Pfad
(`docs/DEPLOY-PC.md`, Abschnitt Cloudflare-Tunnel) — es ist derselbe Build.
