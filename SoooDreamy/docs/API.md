# SoooDreamy Server — API Spec (v1)

Self-hosted Node.js server for the SoooDreamy couple app. One server can host many couples.
Base URL example: `http://192.168.1.20:4321` (the app lets you add/switch servers in Settings).

- All request/response bodies are JSON (`camelCase` keys) unless stated otherwise (media uploads are raw bodies).
- Auth: `Authorization: Bearer <token>` header. Media `GET` endpoints also accept `?token=<token>` (for AVPlayer/AsyncImage).
- Timestamps: ISO-8601 UTC with milliseconds (e.g. `2026-08-03T18:00:00.123Z`). Calendar dates (anniversary, events, dateKey) are plain `YYYY-MM-DD` strings.
- Errors: `{ "error": "<machine_code>", "message": "<human text>" }` with proper HTTP status (400, 401, 403, 404, 409, 413, 500).
- `401 invalid_token` whenever the token is unknown (e.g. couple dissolved).

## Models

```jsonc
// Member
{ "id": "m_…", "name": "Mia", "avatar": "🦊", "color": "#FF5C8A",
  "mood": "🥰", "moodNote": "miss you", "moodUpdatedAt": "…",
  "online": true, "lastSeenAt": "…", "joinedAt": "…" }

// Couple
{ "id": "c_…", "code": "H4XK9P", "name": "Mia & Ben", "anniversary": "2023-11-07",
  "createdAt": "…", "members": [Member, Member] }

// Message  (type: "text" | "letter" | "voice")
{ "id": "msg_…", "senderId": "m_…", "type": "text", "text": "hi", "title": null,
  "audioUrl": "/api/voice/msg_…/raw", "durationSec": 12.4, "createdAt": "…" }

// Photo
{ "id": "ph_…", "uploaderId": "m_…", "caption": "Sunset 🌇", "url": "/api/photos/ph_…/raw",
  "width": 1920, "height": 1080, "createdAt": "…" }

// EventItem
{ "id": "ev_…", "title": "Anniversary", "emoji": "💍", "date": "2026-11-07",
  "repeatsYearly": true, "createdBy": "m_…", "createdAt": "…" }

// BucketItem
{ "id": "b_…", "text": "See the northern lights", "emoji": "🌌", "done": false,
  "doneAt": null, "createdBy": "m_…", "createdAt": "…" }

// CanvasStroke (points normalized 0..1)
{ "id": "s_…", "memberId": "m_…", "color": "#FFFFFF", "width": 4.0, "tool": "pen",
  "points": [[0.1,0.2],[0.11,0.22]], "createdAt": "…" }

// Touch (type: "heartbeat" | "kiss" | "hug" | "missyou" | "tickle" | "thinking")
{ "id": "t_…", "type": "kiss", "senderId": "m_…", "createdAt": "…" }

// GameSession (type: "quiz" | "thisorthat" | "wouldyourather" | "truthordare" | "questions36")
{ "id": "g_…", "type": "quiz", "state": "lobby" | "active" | "ended",
  "createdBy": "m_…", "payload": { }, "result": null,
  "moves": [ { "id": "mv_…", "memberId": "m_…", "data": { }, "createdAt": "…" } ],
  "createdAt": "…" }

// DailyEntry (per member view; partnerAnswer hidden until bothAnswered)
{ "dateKey": "2026-08-03", "questionId": 42, "myAnswer": "…", "partnerAnswer": null,
  "bothAnswered": false, "streak": 5 }

// Stats
{ "daysTogether": 1002, "touchesSent": { "total": 10, "byType": {"kiss": 4} },
  "touchesReceived": { "total": 8, "byType": {} }, "messages": 120, "photos": 33,
  "bucketDone": 3, "bucketTotal": 9, "dailyStreak": 5, "dailyAnswered": 40, "gamesPlayed": 7 }
```

## REST endpoints

| Method & path | Auth | Body / params | Returns | WS broadcast |
|---|---|---|---|---|
| `GET /api/health` | no | – | `{ok:true, name:"SoooDreamy", version, serverTime}` | – |
| `POST /api/couples` | no | `{name, avatar, color}` | `201 {token, coupleId, memberId, couple}` (couple gets 6-char code from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`) | – |
| `POST /api/couples/join` | no | `{code, name, avatar, color}` | `{token, coupleId, memberId, couple}`; `404 unknown_code`; `409 couple_full` | `partner_joined {member}` |
| `GET /api/couple` | yes | – | `{couple, me}` (`me` = my memberId; members include `online`/`lastSeenAt`) | – |
| `PATCH /api/me` | yes | any of `{name, avatar, color, mood, moodNote}` (`mood:null` clears) | `{member}` | `member_updated {member}` |
| `PATCH /api/couple` | yes | any of `{name, anniversary}` | `{couple}` | `couple_updated {couple}` |
| `DELETE /api/couple` | yes | – | `{ok:true}` (wipes all couple data + media, invalidates both tokens) | `couple_dissolved {}` |
| `POST /api/touches` | yes | `{type}` | `201 {touch}` | `touch {touch}` → partner only |
| `GET /api/touches/recent?limit=30` | yes | – | `{touches}` (newest first) | – |
| `GET /api/messages?limit=50&before=<msgId>` | yes | – | `{messages}` ascending `createdAt`; `before` pages older | – |
| `POST /api/messages` | yes | `{type:"text"\|"letter", text, title?}` | `201 {message}` | `message {message}` |
| `POST /api/voice` | yes | raw `audio/mp4` body; headers `X-Duration-Sec` | `201 {message}` (type `voice`) | `message {message}` |
| `GET /api/voice/:id/raw` | yes/`?token` | – | audio bytes | – |
| `POST /api/photos` | yes | raw `image/jpeg` body; headers `X-Caption` (URI-encoded), `X-Width`, `X-Height` | `201 {photo}` | `photo_added {photo}` |
| `GET /api/photos` | yes | – | `{photos}` newest first | – |
| `GET /api/photos/:id/raw` | yes/`?token` | – | image bytes | – |
| `DELETE /api/photos/:id` | yes | – | `{ok}` | `photo_deleted {id}` |
| `GET /api/events` | yes | – | `{events}` | – |
| `POST /api/events` | yes | `{title, emoji, date, repeatsYearly}` | `201 {event}` | `event_added {event}` |
| `PATCH /api/events/:id` | yes | partial | `{event}` | `event_updated {event}` |
| `DELETE /api/events/:id` | yes | – | `{ok}` | `event_deleted {id}` |
| `GET /api/bucket` | yes | – | `{items}` | – |
| `POST /api/bucket` | yes | `{text, emoji?}` | `201 {item}` | `bucket_added {item}` |
| `PATCH /api/bucket/:id` | yes | `{text?, emoji?, done?}` (`done:true` sets `doneAt`) | `{item}` | `bucket_updated {item}` |
| `DELETE /api/bucket/:id` | yes | – | `{ok}` | `bucket_deleted {id}` |
| `GET /api/daily/:dateKey` | yes | – | `DailyEntry` | – |
| `POST /api/daily/:dateKey` | yes | `{questionId, text}` | `DailyEntry` (my view) | `daily_answer` → per-member tailored `DailyEntry` |
| `GET /api/canvas` | yes | – | `{strokes}` (ascending) | – |
| `POST /api/canvas/strokes` | yes | `{color, width, tool, points}` | `201 {stroke}` | `canvas_stroke {stroke}` |
| `DELETE /api/canvas` | yes | – | `{ok}` | `canvas_clear {}` |
| `POST /api/games` | yes | `{type, payload?}` (ends any previous non-ended game) | `201 {game}` | `game_created {game}` |
| `POST /api/games/:id/join` | yes | – | `{game}` (state → active) | `game_started {game}` |
| `POST /api/games/:id/move` | yes | `{data}` | `201 {move}` | `game_move {gameId, move}` |
| `POST /api/games/:id/end` | yes | `{result?}` | `{game}` (state → ended) | `game_ended {game}` |
| `GET /api/games/active` | yes | – | `{game}` or `{game:null}` (latest lobby/active) | – |
| `GET /api/stats` | yes | – | `Stats` | – |

Limits: photo body ≤ 15 MB (`413 too_large`), voice ≤ 15 MB, `text` ≤ 5000 chars, stroke ≤ 2000 points. Canvas keeps at most 8000 strokes (oldest dropped). Messages/touches history capped at 5000/500 entries.

## WebSocket

`GET /ws?token=<token>` (same HTTP server, upgrade). Frames are JSON: `{ "type": "<event>", "payload": { … }, "ts": "<ISO>" }`.

- On connect the server sends `welcome {memberId, coupleId, partnerOnline}` and broadcasts `presence {memberId, online:true}` to the partner. On last socket close: `presence {memberId, online:false, lastSeenAt}`.
- Server→client event types: `welcome, presence, touch, message, member_updated, couple_updated, couple_dissolved, partner_joined, daily_answer, canvas_stroke, canvas_clear, photo_added, photo_deleted, event_added, event_updated, event_deleted, bucket_added, bucket_updated, bucket_deleted, game_created, game_started, game_move, game_ended, typing, pong`.
- Client→server: `{"type":"ping"}` → `pong`; `{"type":"typing","payload":{"isTyping":true}}` → forwarded to partner as `typing {memberId, isTyping}`.
- REST-triggered broadcasts go to **all sockets of the couple** (sender's other devices included) except `touch` and `typing`, which go to the **partner only**. `daily_answer` sends a per-member tailored `DailyEntry`.
- Server pings sockets every 30 s and terminates dead ones. A member is `online` if they have ≥ 1 open socket.

## Storage & runtime

- Plain Node.js ≥ 20, only npm dependency: `ws`. Entry: `server/src/server.js` (`npm start`), app factory `createApp()` in `server/src/app.js` (used by tests; `PORT=0` for ephemeral).
- Env: `PORT` (default `4321`), `HOST` (default `0.0.0.0`), `DATA_DIR` (default `server/data`).
- Persistence: `DATA_DIR/store.json` (debounced atomic writes: tmp file + rename, flush on SIGINT/SIGTERM) + media files in `DATA_DIR/media/photos/`, `DATA_DIR/media/voice/`.
- CORS: permissive (`*`) — the server is self-hosted for exactly one couple (or a few friends).
- Streak: number of consecutive days ending today (or yesterday if today unanswered) where **both** members answered the daily question.
