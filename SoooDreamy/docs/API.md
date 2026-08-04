# SoooDreamy Server — API Spec (v1.2)

Self-hosted Node.js server for the SoooDreamy couple app. One server can host many couples.
Base URL example: `http://192.168.1.20:4321` (the app lets you add/switch servers in Settings).

Server version `1.7.0` (reported by `GET /api/health`).
v1.1 added photo thumbnails, canvas stroke delete (undo), mood history, the daily journal list, and sealed letters (`openWhen`).
v1.2 adds message reactions, the Wordle duel, photo favorites, and love coupons.
v1.2.1 makes Wordle results language-specific (per `dateKey` AND `lang`), restricts Wordle submits to server-today ±1 day, and broadcasts `coupon_deleted` for coupons evicted by the cap.
v1.3 adds the Wordle history list (`GET /api/wordle`).
v1.4 adds the shared soundtrack (`/api/songs`).
v1.5 adds the widget snapshot (`GET /api/widget-snapshot`) and an optional `?limit` on `GET /api/canvas`.
v1.6 adds coupon expiry (`expiresAt`), the inbox digest (`GET /api/inbox`), photo albums + `PATCH /api/photos/:id`, message delete, read receipts (`POST /api/messages/read`, `lastReadAt` on members), the games history list (`GET /api/games`), and the `emojiriddle` game type.
v1.7 adds photo messages: `POST /api/messages` accepts `type:"photo"` + `photoId` (must reference an existing gallery photo of the couple), and every message serializes a `photoId` field (null for non-photo messages).
All releases are backward compatible: a pre-v1.7 `store.json` loads unchanged and missing fields/structures default to `null`/empty on read (v1.2.0 wordle buckets are normalized lazily).

- All request/response bodies are JSON (`camelCase` keys) unless stated otherwise (media uploads are raw bodies).
- Auth: `Authorization: Bearer <token>` header. Media `GET` endpoints also accept `?token=<token>` (for AVPlayer/AsyncImage).
- Timestamps: ISO-8601 UTC with milliseconds (e.g. `2026-08-03T18:00:00.123Z`). Calendar dates (anniversary, events, dateKey) are plain `YYYY-MM-DD` strings.
- Errors: `{ "error": "<machine_code>", "message": "<human text>" }` with proper HTTP status (400, 401, 403, 404, 409, 413, 500).
- `401 invalid_token` whenever the token is unknown (e.g. couple dissolved).

## Models

```jsonc
// Member (lastReadAt: read receipt set via POST /api/messages/read, null until first used)
{ "id": "m_…", "name": "Mia", "avatar": "🦊", "color": "#FF5C8A",
  "mood": "🥰", "moodNote": "miss you", "moodUpdatedAt": "…",
  "online": true, "lastSeenAt": "…", "lastReadAt": "…", "joinedAt": "…" }

// Couple
{ "id": "c_…", "code": "H4XK9P", "name": "Mia & Ben", "anniversary": "2023-11-07",
  "createdAt": "…", "members": [Member, Member] }

// Message  (type: "text" | "letter" | "voice" | "photo")
// openWhen: sealed-letter hint ("open when …"); letters only, null when absent (always null for text/voice/photo)
// reactions: { "<emoji>": [memberId, …] } — null when nobody reacted (works on all message types)
// photoId: photo messages only — id of the referenced gallery photo (null otherwise); the photo
// and the message have independent lifetimes: deleting either leaves the other in place (a photo
// message whose photo was deleted keeps its photoId; the media then 404s like any deleted photo).
// For photo messages `text` is an optional caption (trimmed, blank → null).
{ "id": "msg_…", "senderId": "m_…", "type": "text", "text": "hi", "title": null,
  "openWhen": null, "reactions": { "❤️": ["m_…"] }, "photoId": null,
  "audioUrl": "/api/voice/msg_…/raw", "durationSec": 12.4, "createdAt": "…" }

// Photo  (thumbUrl: null until a thumbnail is uploaded; favorites: memberIds who favorited, default [];
// album: free-form group name ≤ 40 chars set via PATCH, trimmed, null when unset)
{ "id": "ph_…", "uploaderId": "m_…", "caption": "Sunset 🌇", "url": "/api/photos/ph_…/raw",
  "thumbUrl": "/api/photos/ph_…/thumb/raw", "favorites": ["m_…"], "album": "Italy 2026",
  "width": 1920, "height": 1080, "createdAt": "…" }

// MoodEntry (appended whenever a member sets a non-null mood via PATCH /api/me;
// moodNote is the note set in the same request, else null)
{ "id": "md_…", "memberId": "m_…", "mood": "🥰", "moodNote": "miss you", "createdAt": "…" }

// WordleResult (one per member per dateKey per lang; first submit wins, resubmits are ignored)
{ "memberId": "m_…", "rows": 3, "win": true, "grid": "🟩🟨⬛…", "lang": "de", "finishedAt": "…" }

// Wordle day view (per member AND per language; anti-spoiler: `partner` stays null until
// `mine` exists for that (dateKey, lang), `partnerFinished` is always truthful per language)
{ "dateKey": "2026-08-03", "lang": "de", "mine": WordleResult|null, "partner": WordleResult|null,
  "partnerFinished": true }

// Coupon (love coupon 🎟 — forMember is always the creator's partner; expiresAt: optional
// expiry normalized to ISO, null when none — an expired coupon can no longer be redeemed)
{ "id": "cp_…", "title": "Breakfast in bed", "emoji": "🥞", "note": "on a lazy Sunday",
  "createdBy": "m_…", "forMember": "m_…", "redeemedAt": null, "expiresAt": null, "createdAt": "…" }

// Song (shared soundtrack 🎶 — title trimmed/required; artist/note/link optional, trimmed,
// null when absent; link is any string, no URL validation; heartedBy: memberIds who hearted)
{ "id": "sg_…", "title": "Sooo Dreamy", "artist": "The Couple", "note": "our song 💞",
  "link": "https://…", "addedBy": "m_…", "heartedBy": ["m_…"], "createdAt": "…" }

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

// GameSession (type: "quiz" | "thisorthat" | "wouldyourather" | "truthordare" | "questions36" | "emojiriddle")
{ "id": "g_…", "type": "quiz", "state": "lobby" | "active" | "ended",
  "createdBy": "m_…", "payload": { }, "result": null,
  "moves": [ { "id": "mv_…", "memberId": "m_…", "data": { }, "createdAt": "…" } ],
  "createdAt": "…" }

// Inbox ("what happened since I last looked"; see GET /api/inbox)
// Counts cover items created strictly after `since`. Only couponsForMe filters by receiver
// (forMember == me && createdBy != me) — other buckets include both members' items
// (senderId disambiguates). messages.last is a teaser: `kind` is the message type and
// `text` is truncated to 80 chars (null for voice and caption-less photo messages).
// dailyPartnerAnswered: the partner
// answered TODAY's daily question after `since`. Counts are limited by the capped lists.
{ "messages": { "count": 2, "last": { "id": "msg_…", "senderId": "m_…", "kind": "text",
    "text": "hi ❤️", "createdAt": "…" } },
  "touches": { "count": 1, "last": Touch|null },
  "photos": { "count": 1, "last": { "id": "ph_…", "caption": "Sunset 🌇" } },
  "couponsForMe": { "count": 1, "last": Coupon|null },
  "songs": { "count": 0 },
  "dailyPartnerAnswered": false,
  "canvasStrokes": { "count": 5 },
  "serverTime": "…" }

// DailyEntry (per member view; partnerAnswer hidden until bothAnswered)
{ "dateKey": "2026-08-03", "questionId": 42, "myAnswer": "…", "partnerAnswer": null,
  "bothAnswered": false, "streak": 5 }

// Stats
{ "daysTogether": 1002, "touchesSent": { "total": 10, "byType": {"kiss": 4} },
  "touchesReceived": { "total": 8, "byType": {} }, "messages": 120, "photos": 33,
  "bucketDone": 3, "bucketTotal": 9, "dailyStreak": 5, "dailyAnswered": 40, "gamesPlayed": 7 }

// WidgetSnapshot (one-call payload for home-screen widgets; see GET /api/widget-snapshot)
// partner: null on a single-member couple. latestPhoto: newest favorited photo, else newest
// overall, null when no photos. nextEvent: soonest upcoming event — its `date` is the resolved
// next occurrence (a passed repeatsYearly event wraps into the next year), null when nothing
// is upcoming. daysTogether counts from the anniversary (couple createdAt when unset), like Stats.
// streak/bothAnsweredToday follow the daily-question semantics; dailyAnsweredByMe is caller-specific.
{ "partner": { "id": "m_…", "name": "Ben", "avatar": "🐻", "color": "#4A90D9",
    "mood": "🥰", "moodNote": "miss you", "moodUpdatedAt": "…",
    "online": true, "lastSeenAt": "…" },
  "me": { "id": "m_…", "name": "Mia", "avatar": "🦊", "color": "#FF5C8A" },
  "couple": { "id": "c_…", "name": "Mia & Ben", "anniversary": "2023-11-07" },
  "daysTogether": 1002, "streak": 5, "bothAnsweredToday": false, "dailyAnsweredByMe": true,
  "latestPhoto": { "id": "ph_…", "url": "/api/photos/ph_…/raw",
    "thumbUrl": "/api/photos/ph_…/thumb/raw", "caption": "Sunset 🌇", "favorites": ["m_…"] },
  "nextEvent": { "id": "ev_…", "title": "Anniversary", "emoji": "💍", "date": "2026-11-07",
    "repeatsYearly": true },
  "canvasStrokeCount": 42, "canvasUpdatedAt": "…", "serverTime": "…" }
```

## REST endpoints

| Method & path | Auth | Body / params | Returns | WS broadcast |
|---|---|---|---|---|
| `GET /api/health` | no | – | `{ok:true, name:"SoooDreamy", version, serverTime}` | – |
| `POST /api/couples` | no | `{name, avatar, color}` | `201 {token, coupleId, memberId, couple}` (couple gets 6-char code from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`) | – |
| `POST /api/couples/join` | no | `{code, name, avatar, color}` | `{token, coupleId, memberId, couple}`; `404 unknown_code`; `409 couple_full` | `partner_joined {member}` |
| `GET /api/couple` | yes | – | `{couple, me}` (`me` = my memberId; members include `online`/`lastSeenAt`) | – |
| `PATCH /api/me` | yes | any of `{name, avatar, color, mood, moodNote}` (`mood:null` clears) | `{member}`; a non-null `mood` also appends a MoodEntry to the mood history (clearing does not) | `member_updated {member}` |
| `GET /api/moods?limit=80` | yes | – | `{moods}` — both members' MoodEntries merged, newest first (`limit` capped at 200) | – |
| `PATCH /api/couple` | yes | any of `{name, anniversary}` | `{couple}` | `couple_updated {couple}` |
| `DELETE /api/couple` | yes | – | `{ok:true}` (wipes all couple data + media, invalidates both tokens) | `couple_dissolved {}` |
| `POST /api/touches` | yes | `{type}` | `201 {touch}` | `touch {touch}` → partner only |
| `GET /api/touches/recent?limit=30` | yes | – | `{touches}` (newest first) | – |
| `GET /api/messages?limit=50&before=<msgId>` | yes | – | `{messages}` ascending `createdAt`; `before` pages older | – |
| `POST /api/messages` | yes | `{type:"text"\|"letter"\|"photo", text, title?, openWhen?, photoId?}` (`openWhen`: trimmed string ≤ 64 chars → `400 openwhen_too_long`; stored for letters only, silently ignored for other types). Photo messages: `photoId` REQUIRED, must be an existing gallery photo of the couple (missing/non-string → `400 bad_photo`, unknown → `404 unknown_photo`); `text` becomes an OPTIONAL caption (trimmed, blank/omitted → `null`, > 5000 chars → `400 text_too_long`) | `201 {message}` | `message {message}` |
| `POST /api/messages/:id/reactions` | yes | `{emoji}` (trimmed, 1–16 chars → `400 bad_emoji`) — toggles the caller in `reactions[emoji]`; works on all message types; `404 not_found` for unknown/pruned ids | `{message}` | `message_updated {message}` |
| `DELETE /api/messages/:id` | yes (sender only, else `403 not_yours`) | – | `{ok:true}`; `404 not_found` for unknown/pruned ids; a voice message's media file is deleted too (`counters.messages` stays untouched — it is a lifetime total) | `message_deleted {id}` |
| `POST /api/messages/read` | yes | optional `{at?}` (ISO timestamp, normalized; invalid → `400 bad_at`; empty body / omitted → server now) — sets MY `lastReadAt` read receipt | `{memberId, at}` | `message_read {memberId, at}` |
| `POST /api/voice` | yes | raw `audio/mp4` body; headers `X-Duration-Sec` | `201 {message}` (type `voice`) | `message {message}` |
| `GET /api/voice/:id/raw` | yes/`?token` | – | audio bytes | – |
| `POST /api/photos` | yes | raw `image/jpeg` body; headers `X-Caption` (URI-encoded), `X-Width`, `X-Height` | `201 {photo}` | `photo_added {photo}` |
| `GET /api/photos` | yes | – | `{photos}` newest first | – |
| `GET /api/photos/:id/raw` | yes/`?token` | – | image bytes | – |
| `POST /api/photos/:id/thumb` | yes (uploader only, else `403 not_yours`) | raw `image/jpeg` body ≤ 2 MB | `{photo}` with `thumbUrl` set; `404 not_found` for unknown photo | `photo_updated {photo}` |
| `GET /api/photos/:id/thumb/raw` | yes/`?token` | – | thumbnail bytes; `404 no_thumb` when none uploaded | – |
| `POST /api/photos/:id/favorite` | yes | – (toggles the caller in `favorites`) | `{photo}`; `404 not_found` unknown | `photo_updated {photo}` |
| `PATCH /api/photos/:id` | yes | partial `{caption?, album?}` — `null` clears either; `album` trimmed, empty → `null`, > 40 chars → `400 album_too_long`. The gallery is shared: BOTH partners may edit, like delete. | `{photo}`; `404 not_found` unknown | `photo_updated {photo}` |
| `DELETE /api/photos/:id` | yes | – | `{ok}` (also deletes the thumb file, if any). The gallery is shared: BOTH partners may delete any photo, by design — deletion is not restricted to the uploader. | `photo_deleted {id}` |
| `GET /api/events` | yes | – | `{events}` | – |
| `POST /api/events` | yes | `{title, emoji, date, repeatsYearly}` | `201 {event}` | `event_added {event}` |
| `PATCH /api/events/:id` | yes | partial | `{event}` | `event_updated {event}` |
| `DELETE /api/events/:id` | yes | – | `{ok}` | `event_deleted {id}` |
| `GET /api/bucket` | yes | – | `{items}` | – |
| `POST /api/bucket` | yes | `{text, emoji?}` | `201 {item}` | `bucket_added {item}` |
| `PATCH /api/bucket/:id` | yes | `{text?, emoji?, done?}` (`done:true` sets `doneAt`) | `{item}` | `bucket_updated {item}` |
| `DELETE /api/bucket/:id` | yes | – | `{ok}` | `bucket_deleted {id}` |
| `GET /api/coupons` | yes | – | `{coupons}` newest first | – |
| `POST /api/coupons` | yes | `{title (≤80), emoji (≤16), note? (≤200), expiresAt? (ISO date string or null, normalized; invalid → `400 bad_expiry`)}`; receiver `forMember` is always the partner (`409 no_partner` on a single-member couple) | `201 {coupon}` | `coupon_added {coupon}`; plus `coupon_deleted {id}` for each coupon evicted by the 200-cap (sent before `coupon_added`) |
| `POST /api/coupons/:id/redeem` | yes (receiver only, else `403 not_yours`) | – | `{coupon}` with `redeemedAt` set; `409 already_redeemed` on a second redeem; `409 expired` when `expiresAt` is in the past (expired coupons stay listed and deletable) | `coupon_redeemed {coupon}` |
| `DELETE /api/coupons/:id` | yes (creator only, else `403 not_yours`) | – | `{ok}`; `409 already_redeemed` once redeemed | `coupon_deleted {id}` |
| `GET /api/songs` | yes | – | `{songs}` newest first | – |
| `POST /api/songs` | yes | `{title (≤120, `400 bad_title` when empty/too long), artist? (≤120), note? (≤300), link? (≤500)}` — over-long optionals → `400 too_long` | `201 {song}` | `song_added {song}`; plus `song_deleted {id}` for each song evicted by the 300-cap (sent before `song_added`) |
| `PATCH /api/songs/:id` | yes (adder only, else `403 not_yours`) | partial `{title?, artist?, note?, link?}` — explicit `null` clears artist/note/link; title can never be cleared (`400 bad_title`) | `{song}` | `song_updated {song}` |
| `POST /api/songs/:id/heart` | yes | – (toggles the caller in `heartedBy`) | `{song}`; `404 not_found` unknown | `song_updated {song}` |
| `DELETE /api/songs/:id` | yes (adder only, else `403 not_yours`) | – | `{ok}` | `song_deleted {id}` |
| `GET /api/daily?limit=60` | yes | – | `{entries}` — journal of every day where at least one member answered, `dateKey` descending, same per-member reveal semantics as the single-day endpoint (`limit` capped at 366) | – |
| `GET /api/daily/:dateKey` | yes | – | `DailyEntry` | – |
| `POST /api/daily/:dateKey` | yes | `{questionId, text}` | `DailyEntry` (my view) | `daily_answer` → per-member tailored `DailyEntry` |
| `GET /api/wordle?limit=30&lang=de` | yes | `lang` REQUIRED (`"de"`\|`"en"`, else `400 bad_lang`); `limit` default 30, capped at 60 | `{days}` — one day view (same shape as the single-day endpoint) per stored dateKey with ≥ 1 result in that language from either member, `dateKey` descending; the per-day anti-spoiler applies | – |
| `GET /api/wordle/:dateKey?lang=de` | yes | `lang` REQUIRED (`"de"`\|`"en"`, else `400 bad_lang`); any dateKey may be browsed | Wordle day view for that language (per member, anti-spoiler) | – |
| `POST /api/wordle/:dateKey` | yes | `{rows (int 1–6), win (bool), grid (string ≤ 160), lang ("de"\|"en")}` — dateKey must be within ±1 day of server-today (UTC), else `400 bad_datekey`; one result per member per (dateKey, lang); a resubmit returns the stored result unchanged (idempotent, no broadcast) | Wordle day view (my view, incl. `lang`) | `wordle_result` → per-member tailored day view (incl. `lang`) |
| `GET /api/canvas?limit=N` | yes | `limit` optional (default all, capped at 500) | `{strokes}` — the **last** `limit` strokes, still ascending | – |
| `POST /api/canvas/strokes` | yes | `{color, width, tool, points}` | `201 {stroke}` | `canvas_stroke {stroke}` |
| `DELETE /api/canvas/strokes/:id` | yes (author only, else `403 not_yours`) | – | `{ok:true}`; `404 not_found` for unknown stroke | `canvas_stroke_deleted {id}` |
| `DELETE /api/canvas` | yes | – | `{ok}` | `canvas_clear {}` |
| `POST /api/games` | yes | `{type, payload?}` (ends any previous non-ended game) | `201 {game}` | `game_created {game}` |
| `POST /api/games/:id/join` | yes | – | `{game}` (state → active) | `game_started {game}` |
| `POST /api/games/:id/move` | yes | `{data}` | `201 {move}` | `game_move {gameId, move}` |
| `POST /api/games/:id/end` | yes | `{result?}` | `{game}` (state → ended) | `game_ended {game}` |
| `GET /api/games/active` | yes | – | `{game}` or `{game:null}` (latest lobby/active) | – |
| `GET /api/games?limit=30` | yes | `limit` default 30, clamped to 1–100 | `{games}` — recent games (any state, incl. `result`), newest first | – |
| `GET /api/stats` | yes | – | `Stats` | – |
| `GET /api/widget-snapshot` | yes/`?token` | – | `WidgetSnapshot` — everything a home-screen widget needs in one call | – |
| `GET /api/inbox?since=ISO` | yes | `since` REQUIRED (ISO timestamp, normalized; missing/invalid → `400 bad_since`) | `Inbox` — counts + last teasers of everything created strictly after `since` | – |

Limits: photo body ≤ 15 MB (`413 too_large`), voice ≤ 15 MB, thumbnail ≤ 2 MB, `text` ≤ 5000 chars, `openWhen` ≤ 64 chars (after trim), photo `album` ≤ 40 chars (after trim), reaction emoji ≤ 16 chars (after trim), Wordle `grid` ≤ 160 chars, stroke ≤ 2000 points. Canvas keeps at most 8000 strokes (oldest dropped). Messages/touches history capped at 5000/500 entries. Mood history keeps the last 60 entries per member. Wordle keeps the last 60 dateKeys per couple (each dateKey bucket holds up to 2 languages). Coupons cap at 200 per couple (oldest redeemed pruned first, then oldest overall; evictions are broadcast as `coupon_deleted`). Songs cap at 300 per couple (oldest evicted; evictions are broadcast as `song_deleted`).

## WebSocket

`GET /ws?token=<token>` (same HTTP server, upgrade). Frames are JSON: `{ "type": "<event>", "payload": { … }, "ts": "<ISO>" }`.

- On connect the server sends `welcome {memberId, coupleId, partnerOnline}` and broadcasts `presence {memberId, online:true}` to the partner. On last socket close: `presence {memberId, online:false, lastSeenAt}`.
- Server→client event types: `welcome, presence, touch, message, message_updated, message_deleted, message_read, member_updated, couple_updated, couple_dissolved, partner_joined, daily_answer, wordle_result, canvas_stroke, canvas_stroke_deleted, canvas_clear, photo_added, photo_updated, photo_deleted, event_added, event_updated, event_deleted, bucket_added, bucket_updated, bucket_deleted, coupon_added, coupon_redeemed, coupon_deleted, song_added, song_updated, song_deleted, game_created, game_started, game_move, game_ended, typing, pong`.
- Client→server: `{"type":"ping"}` → `pong`; `{"type":"typing","payload":{"isTyping":true}}` → forwarded to partner as `typing {memberId, isTyping}`.
- REST-triggered broadcasts go to **all sockets of the couple** (sender's other devices included) except `touch` and `typing`, which go to the **partner only**. `daily_answer` sends a per-member tailored `DailyEntry`; `wordle_result` sends a per-member tailored Wordle day view (anti-spoiler applies).
- Server pings sockets every 30 s and terminates dead ones. A member is `online` if they have ≥ 1 open socket.

## Storage & runtime

- Plain Node.js ≥ 20, only npm dependency: `ws`. Entry: `server/src/server.js` (`npm start`), app factory `createApp()` in `server/src/app.js` (used by tests; `PORT=0` for ephemeral).
- Env: `PORT` (default `4321`), `HOST` (default `0.0.0.0`), `DATA_DIR` (default `server/data`).
- Persistence: `DATA_DIR/store.json` (debounced atomic writes: tmp file + rename, flush on SIGINT/SIGTERM) + media files in `DATA_DIR/media/photos/`, `DATA_DIR/media/voice/`. Photo thumbnails live next to their photo as `DATA_DIR/media/photos/<id>.thumb.jpg` and are deleted together with the photo (and on couple dissolve).
- Backward compatibility: any pre-1.7 `store.json` loads without migration — missing structures (`moodHistory`, `wordle`, `coupons`, `songs`, `thumbUrl`, `favorites`, `openWhen`, `reactions`, `album`, `expiresAt`, `lastReadAt`, `photoId`) are defaulted on read (`null`/empty). v1.2.0 wordle day buckets (`{memberId: WordleResult}`) are normalized lazily to the per-language shape (`{lang: {memberId: WordleResult}}`) when a day is accessed, using each stored result's own `lang`.
- CORS: permissive (`*`) — the server is self-hosted for exactly one couple (or a few friends).
- Streak: number of consecutive days ending today (or yesterday if today unanswered) where **both** members answered the daily question.
