# Autostart & running SoooDreamy as a service

> **Deutsch (Kurzfassung):** Damit der Server nach jedem Neustart (und nach
> einem Absturz) von selbst wieder läuft, gibt es vier kopierfertige Rezepte:
> **Docker Compose** (`docker compose up -d` — fertig), **Linux systemd**
> (`deploy/sooodreamy.service`), **Windows Task-Scheduler/NSSM** und
> **macOS launchd** (`deploy/com.sooodreamy.server.plist`). Für Dienste ohne
> sichtbares Terminal: `NO_QR=1` (kein ASCII-QR im Log) und `LOG_FILE=1`
> (Logs nach `DATA_DIR/logs/`, täglich rotiert, 14 Tage). Updates immer über
> `npm run update` — das macht Backup → Pull → Install → Migrate → Testboot
> und dreht bei jedem Fehler ALLES automatisch zurück.

All paths below assume the repo checkout lives at `~/SoooDreamy` — adjust to
taste. Every recipe ends with "how do I know it works": open
`http://<server>:4321/api/health` from a phone — `{"ok":true,…}` means yes.

Recommended env vars for any service (no visible terminal):

| Variable | Why |
|---|---|
| `NO_QR=1` | keeps the ASCII QR out of log files |
| `LOG_FILE=1` | logs to `DATA_DIR/logs/server-YYYY-MM-DD.log`, daily rotation, newest 14 kept |

The admin-panel password is regenerated on every start and printed **only** in
the log/console — with a service you read it via the platform's log command
(shown per recipe below).

## Docker Compose (any platform — easiest)

```sh
cd SoooDreamy/server
docker compose up -d        # build + start; survives reboots (restart: unless-stopped)
docker compose logs -f      # start banner: admin password (+ QR unless NO_QR=1)
```

The compose file maps port 4321, stores all data in the named volume
`sooodreamy-data`, and adds a `/api/health` healthcheck so Docker restarts a
hung container. Update: `git pull && docker compose build --pull && docker compose up -d`.

**Is it running?** `docker compose ps` shows `healthy`;
`curl http://localhost:4321/api/health` answers `{"ok":true,…}`.

## Linux (systemd)

```sh
cd SoooDreamy/server
sudo cp deploy/sooodreamy.service /etc/systemd/system/
sudo nano /etc/systemd/system/sooodreamy.service   # set User= and WorkingDirectory=
sudo systemctl daemon-reload
sudo systemctl enable --now sooodreamy
```

The unit uses `Restart=always` (crash → restart after 5 s) and starts after
the network is up. Logs (incl. the admin password) land in journald.

**Is it running?** `systemctl status sooodreamy` says `active (running)`;
logs: `journalctl -u sooodreamy -f`. With journald you do NOT need
`LOG_FILE=1` — journald rotates for you.

## Windows (Task Scheduler or NSSM)

**Task Scheduler** (built in, one line in an *administrator* PowerShell —
adjust the path):

```powershell
schtasks /create /tn "SoooDreamy" /sc onstart /ru SYSTEM ^
  /tr "cmd /c cd /d C:\SoooDreamy\server && set NO_QR=1&& set LOG_FILE=1&& npm start"
schtasks /run /tn "SoooDreamy"        # start it right now, without a reboot
```

**Is it running?** `schtasks /query /tn "SoooDreamy"` shows `Running`;
open `http://localhost:4321/api/health` in a browser. The admin password is in
`DATA_DIR\logs\server-<date>.log` (that's why `LOG_FILE=1` matters here).

**NSSM** (a real Windows service with restart-on-crash — nicer):
[nssm.cc](https://nssm.cc) → `nssm install SoooDreamy "C:\Program Files\nodejs\node.exe" src\server.js`,
set *Startup directory* to `C:\SoooDreamy\server`, add the two env vars under
*Environment*, then `nssm start SoooDreamy`. Manage with
`nssm status|restart|stop SoooDreamy`.

## macOS (launchd)

```sh
cd SoooDreamy/server
cp deploy/com.sooodreamy.server.plist ~/Library/LaunchAgents/
nano ~/Library/LaunchAgents/com.sooodreamy.server.plist   # set WorkingDirectory + node path (`which node`)
launchctl load -w ~/Library/LaunchAgents/com.sooodreamy.server.plist
```

`KeepAlive` restarts the server after crashes; `RunAtLoad` starts it at login.

**Is it running?** `launchctl list | grep sooodreamy` shows a PID;
logs (incl. admin password): `tail -f /tmp/sooodreamy.launchd.log`.

## Updating a service installation

Always the same, on every platform:

```sh
# 1. stop the service (systemctl stop / schtasks /end / launchctl unload / docker compose down)
cd SoooDreamy/server
npm run update     # Backup → git pull → npm ci → migrate → smoke boot; auto-rollback on ANY failure
# 2. start the service again
```

`npm run update` takes a verified `before-update` backup **including media**
first. If the pull, install, migration, or the final test boot fails, it
resets git to the previous commit, reinstalls the old dependencies, and
restores that backup — the previous version keeps running as if nothing
happened. A standalone health probe is available any time via `npm run smoke`.
