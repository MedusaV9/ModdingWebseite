# SoooDreamy Server 💌

Self-hosted backend for the **SoooDreamy** iOS couple app: pairing via 6-char code,
realtime WebSocket (presence, touches, typing, …), messages & love letters, voice
notes, photos, events, bucket list, daily question, shared canvas, games and stats.
One server can host many couples. The full API contract lives in
[`../docs/API.md`](../docs/API.md).

## Run it

```bash
cd server
npm install
npm start  # HTTP/WS by default for the intended trusted private setup
```

Requires Node.js ≥ 20. Dependencies: `ws` (WebSocket) and `qrcode`
(admin-panel login QR).

Or with Docker:

```bash
cd server
docker build -t sooodreamy-server .
docker run -d --name sooodreamy -p 4321:4321 -v sooodreamy-data:/app/data sooodreamy-server
```

| Env var | Default | Meaning |
|---|---|---|
| `PORT` | `4321` | HTTP + WebSocket port |
| `HOST` | `0.0.0.0` | Bind address |
| `DATA_DIR` | `server/data` | Where `store.json` + media files live |
| `ALLOW_HTTP_PRIVATE_LAN` | unset | `1`: restrict HTTP/WS to loopback/private/Tailscale source addresses |
| `REQUIRE_HTTPS` | unset | `1`: reject direct HTTP/WS (highest precedence; use a TLS proxy) |
| `TRUST_PROXY` | unset | Set to `1` only behind your trusted TLS reverse proxy |
| `MAX_COUPLES` | `10000` | Persistent couple quota |
| `BACKUP_INTERVAL_MINUTES` | `60` | Rotating on-server backups; `0` disables ([docs/BACKUP.md](../docs/BACKUP.md)) |
| `BACKUP_KEEP_LAST` / `BACKUP_KEEP_HOURLY` / `BACKUP_KEEP_DAILY` | `10`/`48`/`14` | Backup retention rules |
| `BACKUP_INCLUDE_MEDIA` | unset | Media is included by default; `0` explicitly opts into metadata-only backups |
| `SOOODREAMY_DEV_COCKPIT` | unset | Set to `1` only in development to serve the two-member QA cockpit at `/dev/cockpit` |
| `APNS_ENABLED` | unset | Set to `1` only after configuring all APNs values below |
| `APNS_TEAM_ID` | unset | Apple Developer Team ID |
| `APNS_KEY_ID` | unset | APNs token-signing key ID |
| `APNS_PRIVATE_KEY_FILE` | unset | Absolute path to the APNs `.p8` private-key file |

## Admin panel

The server also serves an operator web panel at `http://<host>:<port>/admin`
(same process, no extra port). The login password is **regenerated on every
server start** and printed only to the console, inside a framed banner next
to the URL. Features: couples overview (activity, app versions, data volume,
segment health incl. quarantine), code resets (invite / recovery / replace),
device session revocation, single-use login-QR generation
(`sooodreamy://rejoin?server=…&token=…`), backup status + "backup now", and a
read-only log/audit tail. Admin actions are appended to
`DATA_DIR/admin-audit.log`. Full guide:
[docs/ADMIN-PANEL.md](../../docs/ADMIN-PANEL.md).

## Killed-app push (optional, externally gated)

The server can register one APNs token per authenticated session device and
deliver privacy-safe partner alerts for messages, touches, photos, coupons,
daily answers and needs. It never returns APNs tokens from the API, limits each
member to eight registrations, removes registrations when their session is
revoked, and disables tokens APNs reports as permanently invalid.
Transient provider failures enter a persistent bounded outbox with a stable
idempotency key and exponential retry; exhausted/permanent failures become
health-visible dead letters.

No Apple credential is included in this repository. Delivery is available only
when all four `APNS_*` variables above are configured and the iOS build is
signed with a provisioning profile carrying the Push Notifications capability.
Keep the `.p8` outside the repository, readable only by the server account, and
restart after changing credentials. Free-profile/unsigned sideloads commonly
lack `aps-environment`; they retain local/WebSocket alerts but cannot be woken
after termination. `POST /api/push-devices/current` returns
`deliveryAvailable: false` while this external gate is closed.

## Reach it from the iOS app

The app asks for a server URL in **Settings → Server**. Options:

- **Default private setup:** `npm start`, then use the LAN URL (e.g.
  `http://192.168.1.20:4321`). HTTP works without a proxy, but traffic and
  bearer tokens are not encrypted; keep the service inside a trusted network.
- **Private-source filter:** add `ALLOW_HTTP_PRIVATE_LAN=1` to reject HTTP
  clients outside loopback/private/Tailscale ranges.
- **From anywhere:** forward the port on your router, or (much nicer) install
  [Tailscale](https://tailscale.com) on the server and both phones and use the
  server's Tailscale IP (`http://100.x.y.z:4321`).
- **Public Internet:** terminate HTTPS/WSS with Caddy or nginx and set
  `TRUST_PROXY=1 REQUIRE_HTTPS=1`. Do not expose default cleartext HTTP.

## Data & backups

Everything lives under `DATA_DIR`:

- `store.wal` — checksummed write-ahead journal; every acknowledged mutation
  is file + parent-directory `fsync`ed here before its 2xx response
- `store.json` — checksummed small manifest (sessions + couple index);
  the ~500 ms debounce is compaction only
- `segments/*.json` — one checksummed file per couple (messages, events, …);
  every write keeps the previous good generation as `*.bak`
- `media/photos/*.jpg` (+ `*.thumb.jpg` thumbnails), `media/voice/*.m4a`,
  `media/videos/*.mp4`, `media/vault/*.bin` — raw uploads
- `backups/` — rotating verified full backups including media (hourly by default)
- `quarantine/` — corrupt files are moved here (never deleted) and the rest
  of the server keeps running; affected couples get a clear
  `503 couple_data_quarantined` until you restore

The server holds an exclusive `DATA_DIR` lock for its lifetime. A second
server, external backup, migration, or restore fails clearly instead of
becoming a second writer.

```bash
npm run backup                          # full backup + prune; stop server first
npm run restore -- --list               # list backups (newest first)
npm run restore -- --restore <id>       # ⚠️ stop the server first
```

Details (retention rules, integrity checks, media): [docs/BACKUP.md](../docs/BACKUP.md).

## Upgrading from an old server (v1.x, e.g. 1.5.4)

```bash
npm run migrate -- --dry-run   # read-only plan
npm run migrate                # pre-migration backup + idempotent migration
```

Couples, media **and existing app sign-ins survive**. Full operator guide
(env changes, HTTPS opt-ins, app update): [docs/MIGRATION.md](../docs/MIGRATION.md).

## Lost sessions & "couple already full"

A full couple is never permanently unjoinable: a member who reinstalled the
app (or lost their phone) re-attaches to their OWN slot via
`POST /api/couples/rejoin` — proof is a recovery key (issued at pairing time),
an active/recently expired token (24-hour grace), or a partner-approved replace code
(`POST /api/couples/replace-partner`). See "Pairing recovery" in
[docs/API.md](../docs/API.md).

## Development

```bash
npm test           # node --test — full API/WS test suite, no extra deps
SOOODREAMY_DEV_COCKPIT=1 npm start
# Then open http://localhost:4321/dev/cockpit for two-member manual QA.
```

Tests spin up the real app on ephemeral ports with temp data dirs
(`createApp()` from `src/app.js`), so they never touch your live data.
