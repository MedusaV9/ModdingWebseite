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
npm start          # → http://0.0.0.0:4321
```

Requires Node.js ≥ 20. The only dependency is `ws`.

Or with Docker:

```bash
cd server
docker build -t sooodreamy-server .
docker run -d --name sooodreamy -p 4321:4321 -v sooodreamy-data:/app/data sooodreamy-server
```

| Env var    | Default          | Meaning                              |
|------------|------------------|--------------------------------------|
| `PORT`     | `4321`           | HTTP + WebSocket port                |
| `HOST`     | `0.0.0.0`        | Bind address                         |
| `DATA_DIR` | `server/data`    | Where `store.json` + media files live |

## Reach it from the iOS app

The app asks for a server URL in **Settings → Server**. Options:

- **Same Wi-Fi:** use the LAN URL the startup banner prints (e.g. `http://192.168.1.20:4321`).
- **From anywhere:** forward the port on your router, or (much nicer) install
  [Tailscale](https://tailscale.com) on the server and both phones and use the
  server's Tailscale IP (`http://100.x.y.z:4321`) — no open ports, encrypted.

## Data & backups

Everything lives under `DATA_DIR`:

- `store.json` — all couples, members, messages, events, … (single JSON file,
  written atomically with a ~500 ms debounce, flushed on SIGINT/SIGTERM)
- `media/photos/*.jpg`, `media/voice/*.m4a` — raw uploads

**Backup = copy the `data/` folder.** Restore = put it back and restart.

## Development

```bash
npm test           # node --test — full API/WS test suite, no extra deps
```

Tests spin up the real app on ephemeral ports with temp data dirs
(`createApp()` from `src/app.js`), so they never touch your live data.
