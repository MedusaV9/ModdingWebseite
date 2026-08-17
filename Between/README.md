# Between

**Between** is a self-hosted, cross-platform game server management panel — think Pterodactyl or AMP, but a single lightweight Node.js process with **zero external dependencies**: no Docker, no database server, no native modules. It runs the game servers as plain child processes on **Linux and Windows** (macOS works too for most direct-download games).

```
┌───────────────────────────────────────────────────────────────┐
│  Between panel (one Node process)                             │
│  ├─ REST API + WebSocket hub          ├─ JSON document store  │
│  ├─ React web UI (served built-in)    ├─ Scheduler (cron)     │
│  ├─ Process manager (spawn/stop/kill) ├─ Backup service (zip) │
│  ├─ SteamCMD manager                  ├─ Metrics collector    │
│  └─ Installers (direct DL, resolvers) └─ Discord notifier     │
└───────────────────────────────────────────────────────────────┘
        │ spawns & supervises
        ▼
   Minecraft · Valheim · Palworld · Rust · CS2 · ARK · … (43 blueprints)
```

## Features

- **Game servers as processes** — start/stop/restart/kill with graceful stop chains (console command, signal, then kill-tree), crash detection, auto-restart with backoff + circuit breaker, per-process-tree CPU/RAM sampling (`/proc` on Linux, PowerShell CIM on Windows).
- **Installers** — SteamCMD (auto-installed, anonymous app installs + updates), direct downloads with progress + SHA256 verification, version resolvers for PaperMC (Fill v3), Vanilla Minecraft (piston-meta), Fabric, and safe zip/tar.gz extraction.
- **43 built-in blueprints** — Minecraft family (Paper/Purpur/Vanilla/Fabric/Bedrock/Velocity), Valheim, Palworld, Rust, ARK, CS2, TF2, Satisfactory, Factorio, Terraria, Project Zomboid, 7 Days to Die, and more (see [`docs/GAMES.md`](docs/GAMES.md)), plus `custom-steamcmd` and `custom-command` for anything else. Admins can create custom blueprints in the UI with live validation.
- **Live console** — ring-buffered scrollback, ANSI colors, stdin commands, search, ready-detection via regex.
- **Files** — sandboxed file manager (path-traversal-proof): browse, edit, upload with progress, download, rename, zip/unzip, tar.gz extract.
- **Backups** — zip snapshots with per-blueprint exclude globs, notes, locking, retention pruning, restore with optional wipe + safety backup.
- **Schedules** — hand-rolled 5-field cron (Vixie OR-semantics), task chains (power / console command / backup / wait), run-now, per-run history.
- **Users & permissions** — global admin/user roles plus per-server **subusers** with 12 granular permissions; TOTP 2FA; session management; **API keys** with scopes; full audit log.
- **Queries & monitoring** — Minecraft Server List Ping and Valve Source A2S (with challenge handshake) for live player counts; host CPU/RAM/disk/load metrics with history; Discord webhook notifications.
- **UI** — React 19 + Tailwind v4, 8 themes + accent colors, EN/DE i18n, live updates over one multiplexed WebSocket, responsive layout.

## Quickstart

Requirements: **Node.js 22+** (and Java 21/25 if you want Minecraft-family servers).

```bash
cd Between
npm install

# Development (backend :8484 + Vite web :5173 with proxy)
npm run dev

# Production (single process serving API + built UI on :8484)
npm run build
npm start
```

Open the panel, create the first admin account, and create your first server — the built-in **Demo Server** blueprint works instantly without downloading anything.

### Configuration

Environment variables (all optional):

| Variable | Default | Meaning |
|---|---|---|
| `BETWEEN_PORT` | `8484` | HTTP port |
| `BETWEEN_HOST` | `0.0.0.0` | Bind address |
| `BETWEEN_DATA` | `./data` | Where servers, backups, SteamCMD and the DB live |
| `BETWEEN_SESSION_TTL_DAYS` | `7` | Session lifetime |
| `BETWEEN_TRUST_PROXY` | `loopback` | Express `trust proxy` (`false`, `true`, hop count or CIDR). Keep the default when the panel sits behind a local reverse proxy; `false` when exposed directly |
| `BETWEEN_MAX_EXTRACT_GIB` | `64` | Max uncompressed size one archive extraction may produce (zip-bomb guard) |
| `BETWEEN_MAX_EXTRACT_ENTRIES` | `200000` | Max entries per extracted archive |
| `BETWEEN_SEED_ADMIN_USER` / `BETWEEN_SEED_ADMIN_PASS` | — | Seed an admin on first boot (for automation) |

## Development

```bash
npm test           # unit tests + full API integration journey (150+ tests)
npm run lint       # oxlint over server + web
npm run typecheck  # strict tsc for both workspaces
npm run validate   # validate all builtin blueprints against the schema
```

Layout:

- `server/` — Express + ws backend, TypeScript executed by `tsx` (no build step). Domain code lives in `src/servers` (process lifecycle), `src/install` (pipelines + resolvers), `src/steam`, `src/services` (backups/schedules/metrics/files/audit/notify), `src/api` (REST), `src/ws` (hub), `src/lib` (zip/tar/cron/totp/store/... all hand-rolled, zero deps).
- `web/` — React SPA (Vite). Pages in `src/pages`, live server state via `src/api/ws.ts` + `src/state/useServers.ts`.
- Blueprints are JSON documents validated by `server/src/blueprints/schema.ts` — see existing ones in `server/src/blueprints/builtin/` as reference.

## Platform notes

- **Linux**: SteamCMD needs 32-bit libs: `sudo apt install lib32gcc-s1 lib32stdc++6`.
- **Windows**: fully supported — process trees are killed via `taskkill`, resources sampled via PowerShell CIM, SteamCMD zip is fetched automatically. Blueprints declare their supported platforms and the UI filters accordingly.
- **Java games**: each Minecraft-family server has a `JAVA_BIN` variable so different servers can use different JDKs (MC ≤1.21.x → Java 21, MC 26.1+ → Java 25).

## Security model

Between runs game servers **as the same OS user as the panel** (that is the point: no containers, no root). Anyone with panel admin rights or server-level `server.config`/`server.files` permissions can effectively run arbitrary commands as that user — same trust model as WindowsGSM/LinuxGSM. Run the panel under a dedicated unprivileged user, keep it behind a reverse proxy with TLS, and only grant subuser permissions you actually mean.
