# Migrating an old SoooDreamy server (v1.x, e.g. 1.5.4) to the current version

> **Deutsch (Kurzfassung):** Server stoppen → `git pull && npm install` →
> `npm run migrate -- --dry-run` (zeigt nur den Plan) → `npm run migrate`
> (legt automatisch ein verifiziertes Backup inklusive Medien an) → Env prüfen
> (HTTP ist für das private Standard-Setup aktiv; optional Private-LAN-Filter
> oder HTTPS-Proxy, Node ≥ 20) → `npm start`. Alle Paare, Nachrichten, Fotos
> und **Logins bleiben erhalten**. Danach die aktuelle App aus dem rollenden
> Release sideloaden — sehr alte App-Builds (1.x) können mit dem neuen Server
> nicht mehr sprechen (Header-/API-Vertrag).

## TL;DR

```bash
# on the server box, inside SoooDreamy/server
# Stop the foreground server with Ctrl-C first.
# systemd: sudo systemctl stop sooodreamy
# Docker:  docker stop sooodreamy
git pull && npm install            # get the current code (Node.js ≥ 20)
npm run migrate -- --dry-run       # read-only: shows what WOULD happen
npm run migrate                    # backup + migrate (idempotent)
npm start                          # default private-setup HTTP mode
```

Everything is preserved: couples, members, messages, letters, voice notes,
photos, events, bucket list, daily answers, wordle history, coupons, songs,
stats — **and existing app sign-ins** (old bearer tokens keep working).

## What actually changed between 1.5.4 and now

| Area | v1.5.4 | current | migration handling |
|---|---|---|---|
| Data layout | one inline `store.json` (`{version:1, couples, tokens}`) | small `store.json` manifest + one checksummed segment file per couple (`segments/*.json`) | `npm run migrate` compacts losslessly (the same code path every server boot runs) |
| Sessions | raw bearer tokens as store keys, no expiry | SHA-256 digests, per-device session records, 90-day expiry, 24-hour rejoin grace, rotation/revocation | tokens are upgraded in place — users **stay signed in**; sessions get a fresh 90-day expiry |
| Games | client-authoritative relay | server-validated rules (v4+) | open pre-v4 sessions are replayed under current rules or explicitly invalidated (never silently continued); ended games stay readable as `legacy-client` |
| Transport | plain HTTP accepted | three explicit modes: default HTTP, private-source-only HTTP, or strict HTTPS | optional operator hardening — see below |
| Query tokens | `?token=` worked | rejected everywhere (Authorization header only) | old iOS builds must update |
| Node.js | ≥ 18 worked | **≥ 20 required** (`package.json` engines) | operator action |

## Operator checklist

### 1. Stop the server, update the code

For a foreground `npm start`, press **Ctrl-C** and wait for “Data flushed”.
For managed installs use the real service/container command, for example
`sudo systemctl stop sooodreamy` or `docker stop sooodreamy`. There is no
`npm stop` script.

```bash
git pull
npm install     # dependencies: `ws` + `qrcode`
node --version  # must be ≥ 20
```

### 2. Run the migration

```bash
npm run migrate -- --dry-run   # inspect + plan, writes nothing
npm run migrate                # applies; add --data-dir <path> for a custom DATA_DIR
```

The script is **idempotent** — running it on an already-migrated data dir
prints `already up to date` and changes nothing. Before any change it takes a
verified `pre-migration` backup you can always return to:

```bash
npm run restore -- --list                       # find the pre-migration backup id
npm run restore -- --restore <id>               # roll everything back
```

(If you skip `npm run migrate`, the server still migrates the layout lazily on
its next boot — the script exists so you get the backup, the plan, the token
upgrade and a clear report *before* going live.)

### 3. Review config / env

| Env var | v1.5.4 | now |
|---|---|---|
| `PORT` / `HOST` / `DATA_DIR` | same | same |
| `ALLOW_HTTP_PRIVATE_LAN` | n/a (HTTP always on) | optional `1`: accept HTTP only from loopback/private/Tailscale sources |
| `REQUIRE_HTTPS` | n/a | optional `1`: reject direct HTTP/WS; highest precedence |
| `TRUST_PROXY` | n/a | set `1` only behind your TLS reverse proxy (Caddy/nginx) |
| `MAX_COUPLES`, `MEDIA_QUOTA_BYTES` | n/a | optional quotas |
| `BACKUP_INTERVAL_MINUTES` etc. | n/a | rotating full backups including media (default hourly); `BACKUP_INCLUDE_MEDIA=0` explicitly opts out — [`BACKUP.md`](BACKUP.md) |
| `APNS_*` | n/a | optional killed-app push (externally gated) |
| `SOOODREAMY_DEV_COCKPIT` | n/a | dev-only QA cockpit |

Without a transport flag, HTTP/WS is accepted for the intended trusted private
setup and is **not encrypted**. `ALLOW_HTTP_PRIVATE_LAN=1` narrows cleartext to
private source addresses. Publicly reachable deployments should terminate
HTTPS/WSS in Caddy/nginx, set `TRUST_PROXY=1`, and set `REQUIRE_HTTPS=1`.

### 4. Start & verify

```bash
npm start
curl http://<server>:4321/api/health   # → current version, storage stats incl. quarantine
```

### 5. Update the phones

Old 1.x app builds cannot talk to the current server (ATS/HTTPS rules, header
auth). Sideload the current IPA from the rolling release. Existing sign-ins
survive the migration; if a device lost its pairing anyway, the member
re-attaches via the **rejoin flow** (recovery key / old token / partner
replace code — see the "Pairing recovery" section of [`API.md`](API.md)).

## Media files

`DATA_DIR/media/**` (photos, voice notes, videos, vault blobs) is untouched by
the migration — the paths and file names are unchanged since 1.x.

## Corrupt legacy files

If the old `store.json` is unreadable, `npm run migrate` refuses and points
you at the recovery options. The current server quarantines broken files at
boot (`DATA_DIR/quarantine/`), falls back to `.bak` generations where
possible, and keeps every other couple running — see the "Storage & runtime"
section of [`API.md`](API.md).

## Server-to-server moves

Moving one couple to a *different* server is a separate, end-user feature:
`GET /api/migration/export` / `POST /api/migration/import` (encrypted bundle,
digest-checked, sessions never migrate). This document is about upgrading one
server's data directory in place.
