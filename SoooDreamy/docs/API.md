# SoooDreamy Server — API Spec (v16.0.0)

Self-hosted Node.js server for the SoooDreamy couple app. One server can host many couples.
Base URL example: `http://192.168.1.20:4321` (the app lets you add/switch servers in Settings).

Server version `16.0.0` (reported by `GET /api/health`).
v12.0 adds true multi-device seats per member: self-service device link codes
(`POST /api/sessions/link-code` → `POST /api/couples/link`, `device_linked`
fanout to the member's own devices), an `origin` marker on realtime frames for
self-echo dedup, and the per-game input lease with explicit takeover
(`POST /api/games/:id/takeover`, `409 game_lease_held`).
v11.0 hardens the JSON store with a durable write-ahead journal, one-writer
`DATA_DIR` locking, non-destructive recovery, single-use login QR nonces,
message archives, media-complete backups, and a persistent push outbox.
v5.2 migrates the JSON store to atomic per-couple segments, reports bounded storage/media statistics, and accepts stable client operation ids for offline reaction, daily-answer, quest-check, and rating retries.
v5.1 ships the iOS surfaces and stricter authority contract for `wordchain` and `hangman`, plus weekly event-driven `bingo`. The server validates the chain dictionary/date, audits Hangman through commit-reveal, and is the only actor allowed to check Bingo tiles.
v1.1 added photo thumbnails, canvas stroke delete (undo), mood history, the daily journal list, and sealed letters (`openWhen`).
v1.2 adds message reactions, the Wordle duel, photo favorites, and love coupons.
v1.2.1 makes Wordle results language-specific (per `dateKey` AND `lang`), restricts Wordle submits to server-today ±1 day, and broadcasts `coupon_deleted` for coupons evicted by the cap.
v1.3 adds the Wordle history list (`GET /api/wordle`).
v1.4 adds the shared soundtrack (`/api/songs`).
v1.5 adds the widget snapshot (`GET /api/widget-snapshot`) and an optional `?limit` on `GET /api/canvas`.
v1.6 adds coupon expiry (`expiresAt`), the inbox digest (`GET /api/inbox`), photo albums + `PATCH /api/photos/:id`, message delete, read receipts (`POST /api/messages/read`, `lastReadAt` on members), the games history list (`GET /api/games`), and the `emojiriddle` game type.
v1.7 adds photo messages: `POST /api/messages` accepts `type:"photo"` + `photoId` (must reference an existing gallery photo of the couple), and every message serializes a `photoId` field (null for non-photo messages).
v1.8 adds message editing: `PATCH /api/messages/:id` (sender-only, text/letter only) rewrites `text` and sets `editedAt`; every message serializes an `editedAt` field (null until first edited).
v2.0 adds gallery videos (`/api/videos` with Range streaming), the end-to-end encrypted vault (`/api/vault`), the haptics composer (`/api/haptics`), three new realtime game types (`connectfour`, `photomemory`, `quizduel`), and six couple features: check-ins (`/api/checkins`), shared lists (`/api/lists`), the hug queue (`/api/hugs`), photo of the day (`/api/potd`), the now-playing status (`/api/nowplaying`) and the year review (`/api/yearreview`).
All releases are backward compatible: a recognized legacy inline `store.json` is losslessly compacted into the current manifest plus checksummed `segments/*.json` during startup, and missing fields/structures default to `null`/empty on read (v1.2.0 wordle buckets are normalized lazily).

- All request/response bodies are JSON (`camelCase` keys) unless stated otherwise (media uploads are raw bodies).
- Transport has three explicit modes: default HTTP/WS (intended for a trusted private setup; no transport encryption), `ALLOW_HTTP_PRIVATE_LAN=1` (HTTP/WS only from loopback/private/Tailscale source addresses), and `REQUIRE_HTTPS=1` (reject all direct HTTP/WS; use HTTPS/WSS through a trusted reverse proxy with `TRUST_PROXY=1`).
- Auth: `Authorization: Bearer <token>` header. Query credentials (`?token=`/`?access_token=`) are rejected on every route, including media and WebSockets.
- Sessions are per device, expire after 90 days, and can be listed, rotated, or revoked through `/api/sessions`. An expired bearer is accepted as rejoin proof for at most 24 hours, then permanently removed; long-term recovery uses the separate recovery key. Sessions are cleaned at startup/periodically and capped at 8 per member; when the ceiling forces an eviction, retained dead records (revoked/expired) go before the oldest live session. The store contains SHA-256 token digests, never raw bearer tokens. A member's ADDITIONAL devices attach via self-service device link codes (`POST /api/sessions/link-code` → `POST /api/couples/link`) — see [Multi-device](#multi-device-sessions--fanout).
- Killed-app push is optional and externally gated: APNs registrations work only with an iOS Push-capable provisioning profile and server-side Apple credentials. The status response says `deliveryAvailable:false` when that gate is closed. APNs device tokens (not bearer credentials) remain in couple storage so the server can address Apple; list/mutation responses never expose them. Transient delivery failures enter a bounded persistent outbox and retry with exponential backoff and a stable idempotency key; permanent/exhausted failures become dead letters visible in health warnings.
- Timestamps: ISO-8601 UTC with milliseconds (e.g. `2026-08-03T18:00:00.123Z`). Calendar dates (anniversary, events, dateKey) are plain `YYYY-MM-DD` strings.
- Errors: `{ "error": "<machine_code>", "message": "<human text>" }` with proper HTTP status (400, 401, 403, 404, 409, 413, 426, 429, 500, 503, 507). The `error` code is the machine contract — build client behavior on it, never on `message` (which is a debugging aid and may change). Some refusals additionally carry a structured `details` object (documented per code, e.g. `game_lease_held` attaches the holding device); absent everywhere else. Complete list: [Error code catalog](#error-code-catalog).
- `401 invalid_token` whenever the token is unknown (e.g. couple dissolved).
- Time-boxed `429` responses carry a `retry-after` header (integer seconds until the action is allowed again): `rate_limited`, `effect_cooldown`, `too_soon`. Capacity-style `429`s (`too_many_open_games`, `too_many_firsts`) have no `retry-after` — free a slot instead of waiting.

## Models

```jsonc
// Member (lastReadAt: read receipt set via POST /api/messages/read, null until first used;
// petName: v5.3 pet name — how the partner's app addresses this member, null until set)
{ "id": "m_…", "name": "Mia", "avatar": "🦊", "color": "#FF5C8A", "petName": "Schnuffel",
  "mood": "🥰", "moodNote": "miss you", "moodUpdatedAt": "…",
  "online": true, "lastSeenAt": "…", "lastReadAt": "…", "joinedAt": "…" }

// Couple
{ "id": "c_…", "code": "H4XK9P", "name": "Mia & Ben", "anniversary": "2023-11-07",
  "palette": { "primary": "#FF5C8A", "secondary": "#60A5FA", "accent": "#FFA5C0", "onAccent": "#09040D" },
  "monogramStyle": "seal",
  "createdAt": "…", "members": [Member, Member] }

// Message  (type: "text" | "letter" | "voice" | "photo" | "sticker")
// openWhen: sealed-letter hint ("open when …"); letters only, null when absent (always null for text/voice/photo)
// reactions: { "<emoji>": [memberId, …] } — null when nobody reacted (works on all message types)
// photoId: photo messages only — id of the referenced gallery photo (null otherwise); the photo
// and the message have independent lifetimes: deleting either leaves the other in place (a photo
// message whose photo was deleted keeps its photoId; the media then 404s like any deleted photo).
// For photo messages `text` is an optional caption (trimmed, blank → null).
// editedAt: set by PATCH /api/messages/:id (sender-only, text/letter only); null until first edited.
// effect: v5.3 send-effect ("hearts" | "snow" | "sparkle" | "fireworks" | "slam" | "invisible"), null when sent plainly —
// plays fullscreen ONCE on the partner's device, then a subtle badge on the bubble ("invisible" =
// tap-to-reveal ink). Optional on every POST-able message type, immutable after send.
// sticker: procedural recipe {shape:"heart"|"cloud"|"burst"|"seal", color, seed, label?}; null otherwise.
// clientMessageId: optional stable sender-generated id used to deduplicate lost-response retries.
{ "id": "msg_…", "senderId": "m_…", "type": "text", "text": "hi", "title": null,
  "openWhen": null, "reactions": { "❤️": ["m_…"] }, "photoId": null, "clientMessageId": "offline-…",
  "editedAt": null, "effect": null,
  "audioUrl": "/api/voice/msg_…/raw", "durationSec": 12.4, "createdAt": "…" }

// Photo  (thumbUrl: null until a thumbnail is uploaded; favorites: memberIds who favorited, default [];
// album: free-form group name ≤ 40 chars set via PATCH, trimmed, null when unset;
// takenAt: EXIF capture time from X-Taken-At; null when missing/invalid or more than 24 h in the future)
{ "id": "ph_…", "uploaderId": "m_…", "caption": "Sunset 🌇", "url": "/api/photos/ph_…/raw",
  "thumbUrl": "/api/photos/ph_…/thumb/raw", "favorites": ["m_…"], "album": "Italy 2026",
  "width": 1920, "height": 1080, "takenAt": "…", "createdAt": "…" }

// Video (v2.0 — thumbUrl: null until a poster thumbnail is uploaded; favorites like Photo;
// duration in seconds rounded to 0.1, bytes = stored file size; streamed with Range support)
{ "id": "vd_…", "uploaderId": "m_…", "caption": "Beach day 🏖️", "url": "/api/videos/vd_…/raw",
  "thumbUrl": "/api/videos/vd_…/thumb/raw", "favorites": [], "width": 1280, "height": 720,
  "duration": 12.3, "bytes": 1048576, "createdAt": "…" }

// VaultConfig (v2.0 — PUBLIC KDF parameters for the end-to-end encrypted vault; contains
// no secrets. verifier: AES-GCM sealed known plaintext, only openable with the PIN-derived key)
{ "kdf": "pbkdf2-sha256", "iterations": 210000, "salt": "<base64>", "verifier": "<base64>",
  "createdBy": "m_…", "createdAt": "…" }

// VaultItem (v2.0 — an opaque AES-GCM blob; caption/poster/content are INSIDE the ciphertext.
// kind is a coarse client hint only: "photo" | "video" | "note")
{ "id": "vt_…", "uploaderId": "m_…", "kind": "photo", "url": "/api/vault/vt_…/raw",
  "bytes": 4096, "createdAt": "…" }

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

// Touch (type: "heartbeat" | "kiss" | "hug" | "missyou" | "tickle" | "thinking"
//        | "stolz" | "haltedurch" (FullRelease P6-B))
// P6-B additions are ADDITIVE fields only — plain sends stay lean, echoes carry
// echo/echoOf, Zeitpost deliveries carry viaPost/postId. Old clients must
// ignore unknown fields AND skip touches with unknown types (lossy decoding),
// never fail the whole list.
{ "id": "t_…", "type": "kiss", "senderId": "m_…", "createdAt": "…",
  "echo": true, "echoOf": "t_…",        // only on echo replies
  "viaPost": true, "postId": "zp_…" }   // only on delivered Zeitpost touches

// ScheduledPost (Zeitpost — kind: "touch" | "pulse" | "note"; exactly one of
// type/pulseKind/note is set, the other two are null)
{ "id": "zp_…", "kind": "touch", "type": "kiss", "pulseKind": null, "note": null,
  "deliverAt": "…", "senderId": "m_…", "createdAt": "…" }

// PostJournalEntry (kind: "touch" | "pulse" | "note" — all fields always present)
{ "id": "t_…", "kind": "touch", "type": "kiss", "pulseKind": null, "note": null,
  "senderId": "m_…", "createdAt": "…", "echo": false, "echoOf": null, "viaPost": false }

// GameSession (type: "quiz" | "thisorthat" | "wouldyourather" | "truthordare" | "questions36" | "emojiriddle"
//              | "connectfour" | "photomemory" | "quizduel" (v2.0)
//              | "battleship" | "pictionary" | "kniffel" | "movieroulette" | "stadtlandfluss"
//              | "twotruths" | "dailyquests" (v3.0)
//              | "wordleduo" | "hangman" | "rps" | "story" | "wordchain"
//              | "bingo" (v5.1)
//              | "dame" | "reversi" | "kaesekaestchen" | "gomoku" | "mancala"
//              | "memoryduo" (W8C board & duel games))
// turnMemberId (sync contract c): server-authoritative "whose move is it" for EVERY type —
// null when the game is not active (lobby/ended) or no single member is up (simultaneous
// phases like quiz answers or RPS commits, live Pictionary rounds, checklist types like
// dailyquests/bingo/questions36). Extra moves (Mancala store landing, Käsekästchen box,
// memoryduo match) keep it with the SAME member. Clients must prefer this over deriving
// the turn from the last move.
{ "id": "g_…", "type": "quiz", "state": "lobby" | "active" | "ended",
  "createdBy": "m_…", "payload": { }, "result": null, "turnMemberId": "m_…" | null,
  "moves": [ { "id": "mv_…", "memberId": "m_…", "data": { }, "createdAt": "…" } ],
  "createdAt": "…" }

// Inbox ("what happened since I last looked"; see GET /api/inbox)
// Counts cover items created strictly after `since`. EVERY bucket is PARTNER-ONLY:
// the caller's own messages/touches/photos/songs/strokes never count ("5 missed
// messages" must never mean your own texts). couponsForMe additionally filters by
// receiver (forMember == me && createdBy != me). messages.last / touches.last are the
// newest PARTNER items; messages.last is a teaser: `kind` is the message type and
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
  "games": { "count": 1, "awaitingMe": [ { "gameId": "g_…", "type": "battleship" } ] },
  "serverTime": "…" }

// DailyEntry (per member view; partnerAnswer hidden until bothAnswered)
// questionText: the bilingual text stored with the pin (null when the pinning client sent
// none) — lets a client render the pinned question even when its pool doesn't know the id.
{ "dateKey": "2026-08-03", "questionId": 42, "questionText": { "de": "…", "en": "…" },
  "myAnswer": "…", "partnerAnswer": null, "bothAnswered": false, "streak": 5 }

// Stats
{ "daysTogether": 1002, "touchesSent": { "total": 10, "byType": {"kiss": 4} },
  "touchesReceived": { "total": 8, "byType": {} }, "messages": 120, "photos": 33, "videos": 4,
  "bucketDone": 3, "bucketTotal": 9, "dailyStreak": 5, "dailyAnswered": 40, "gamesPlayed": 7 }

// WidgetSnapshot (one-call payload for home-screen widgets; see GET /api/widget-snapshot)
// partner: null on a single-member couple. latestPhoto: newest favorited photo, else newest
// overall, null when no photos. nextEvent: soonest upcoming event — its `date` is the resolved
// next occurrence (a passed repeatsYearly event wraps into the next year), null when nothing
// is upcoming. daysTogether counts from the anniversary (couple createdAt when unset), like Stats.
// streak/bothAnsweredToday follow the daily-question semantics; dailyAnsweredByMe is caller-specific.
// dailyQuestionId: the id pinned by the day's FIRST answer (null before it) — widgets on every
// device must render this question instead of deriving their own (pool-growth race).
// dailyDateKey: the server-UTC day the pin belongs to — clients apply the pin only when it
// matches their LOCAL day (midnight/timezone straddle). dailyQuestion: the bilingual text
// stored with the pin (null without one), for clients whose pool doesn't know the id.
{ "partner": { "id": "m_…", "name": "Ben", "avatar": "🐻", "color": "#4A90D9",
    "mood": "🥰", "moodNote": "miss you", "moodUpdatedAt": "…",
    "online": true, "lastSeenAt": "…" },
  "me": { "id": "m_…", "name": "Mia", "avatar": "🦊", "color": "#FF5C8A" },
  "couple": { "id": "c_…", "name": "Mia & Ben", "anniversary": "2023-11-07" },
  "daysTogether": 1002, "streak": 5, "bothAnsweredToday": false, "dailyAnsweredByMe": true,
  "dailyQuestionId": 42, "dailyDateKey": "2026-08-03", "dailyQuestion": { "de": "…", "en": "…" },
  "latestPhoto": { "id": "ph_…", "url": "/api/photos/ph_…/raw",
    "thumbUrl": "/api/photos/ph_…/thumb/raw", "caption": "Sunset 🌇", "favorites": ["m_…"] },
  "nextEvent": { "id": "ev_…", "title": "Anniversary", "emoji": "💍", "date": "2026-11-07",
    "repeatsYearly": true },
  "canvasStrokeCount": 42, "canvasUpdatedAt": "…", "serverTime": "…" }
```

## REST endpoints

| Method & path | Auth | Body / params | Returns | WS broadcast |
|---|---|---|---|---|
| `GET /api/health` | no | – | `{ok:true, name:"SoooDreamy", version, serverTime, uptimeSeconds, nodeVersion, storage, disk, lastBackup, quarantinedCouples, pushOutbox, warnings}` — `storage` reports format, couple/segment counts, JSON/media bytes, file count, configured media quota/use, quarantine stats (`{files, bytes, couples}`) and last compaction; `disk` is `{freeBytes, totalBytes, warn}` of the data-dir filesystem (null where `statfs` is unavailable); `lastBackup` is `{id, createdAt, ageMinutes, includesMedia}` or null; `pushOutbox` is `{pending, deadLetter}`; warnings include `disk_low`, `disk_full`, `backup_never`, `backup_old`, `backup_media_unprotected`, `push_dead_letter`, and `quarantine` | – |
| `POST /api/couples` | no | `{name, avatar, color, deviceId?, deviceName?}` | `201 {token, sessionId, expiresAt, coupleId, memberId, recoveryKey, couple}` (couple gets 6-char code from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`; store the one-time `recoveryKey` in the keychain — see Pairing recovery) | – |
| `POST /api/couples/join` | no | `{code, name, avatar, color, deviceId?, deviceName?}` | `{token, sessionId, expiresAt, coupleId, memberId, recoveryKey, couple}`; `404 unknown_code`; `409 couple_full` (the message points existing members at `/api/couples/rejoin`) | `partner_joined {member}` |
| `POST /api/couples/rejoin` | no | exactly one proof: `{code, recoveryKey}` \| `{token}` (active or expired by no more than 24 h) \| `{code, replaceCode}`; optional `name/avatar/color` (replace only) + `deviceId?/deviceName?` | `{token, sessionId, expiresAt, coupleId, memberId, couple, rejoined:true, method}` where `method` is exactly `recoveryKey`, `token`, or `replaceCode`; re-attaches the caller's OWN member slot of a **full** couple; proofs are type-separated and replace codes are atomically single-use; `403 bad_recovery_key`/`unknown_session`/`session_revoked`/`bad_replace_code`; `400 missing_proof`; rate-limited per IP | `partner_rejoined {member}` (recovery/token) or `partner_replaced {member}` (replace) → partner only; plus `sessions_changed` to the member's own devices: `reason:"rejoined"` (recovery/token), or for replace `reason:"revoked"` per cut-off old session (their sockets then close with code `4001`) followed by `reason:"replaced"` for the fresh session |
| `GET /api/recovery-key` | yes | – | `{configured, createdAt}` — whether the caller has a recovery key (plaintext is never retrievable) | – |
| `POST /api/recovery-key` | yes | – | `{recoveryKey, createdAt, rotated}` — issues (or rotates) the caller's recovery key; shown exactly once, stored server-side only as a SHA-256 digest | – |
| `POST /api/couples/replace-partner` | yes | – | `201 {replaceCode, expiresAt, target}` — remaining partner approves replacing the OTHER slot's devices: single-use 8-char code, 15-min TTL; using it revokes all sessions + the recovery key of the replaced slot (history stays); `409 no_partner` / `replace_already_pending` | – |
| `DELETE /api/couples/replace-partner` | yes | – | `{ok:true, cancelled}` — cancels a pending replace code | – |
| `GET /api/couple` | yes | – | `{couple, me}` (`me` = my memberId; members include `online`/`lastSeenAt`) | – |
| `PATCH /api/me` | yes | any of `{name, avatar, color, petName, mood, moodNote}` (`mood:null` clears; `petName`: trimmed ≤ 40 chars, `null`/blank clears) | `{member}`; a non-null `mood` also appends a MoodEntry to the mood history (clearing does not) | `member_updated {member}` |
| `GET /api/moods?limit=80` | yes | – | `{moods}` — both members' MoodEntries merged, newest first (`limit` capped at 200) | – |
| `PATCH /api/couple` | yes | any of `{name, anniversary, palette, monogramStyle, timezone}`; palette colors are `#RRGGBB` and `accent` must retain 4.5:1 contrast against the night background and `onAccent`; monogram style is `seal`, `ribbon`, or `minimal`; `timezone` is an IANA name (e.g. `Europe/Berlin`, invalid → `400 bad_timezone`, `null` clears) driving couple-local rituals like the Sunday week-review arrival push — without one the server's local clock applies | `{couple}`; invalid color → `400 bad_color`, insufficient contrast → `400 low_contrast` | `couple_updated {couple}` |
| `GET /api/migration/export` | yes | – | `{bundle}` in `sooodreamy-couple-v1`; contains complete logical couple JSON, `schemaVersion`, source version, SHA-256 digest, and an explicit `media.included:false` notice | – |
| `POST /api/migration/import` | yes | `{confirm:"IMPORT", sourceMemberId, bundle}` on a newly created single-member couple (≤ 16 MB JSON) | `{coupleId, memberId, code, requiresPartnerRepair, digest}`; sessions/tokens never migrate; partner must join the new code; rejects tampering, future schema, and non-empty destination | – |
| `GET /api/sessions` | yes | – | `{sessions}` — current member's bounded device-session views, no bearer values | – |
| `POST /api/sessions/current/rotate` | yes | – | `{token, sessionId, expiresAt}`; old bearer stops working | `sessions_changed {memberId, reason:"rotated", sessionId:<successor>, deviceName}` → all of the member's devices, THEN the old session's sockets close with code `4001` |
| `POST /api/sessions/:id/revoke` | yes | – | `{ok:true}`; member may revoke only own session; linked push registration is removed | `sessions_changed {memberId, reason:"revoked", sessionId, deviceName}` → all of the member's devices (incl. the dying one), THEN the revoked session's sockets close with code `4001` |
| `POST /api/sessions/link-code` | yes | optional `{server?}` (only with `?format=qr`: http(s) base URL for the deep link, defaults to the request host; invalid → `400 bad_server_url`) | `201 {linkCode, expiresAt, createdAt, memberId}` — one-time 8-char device link code (10-min TTL, single-use, stored only as SHA-256 digest, rate-limited per IP); issuing replaces any previous unconsumed code of the caller. With `?format=qr` additionally `{deepLink, svg, server}` (`sooodreamy://link?server=…&code=…` rendered as SVG — admin rejoin-QR pattern). `413 too_many_sessions` when the member already has 8 active sessions | – |
| `POST /api/couples/link` | no | `{code, deviceId?, deviceName?}` — redeems a device link code for a fresh session of the SAME member (no recovery-key ceremony, recovery key is NOT rotated); rate-limited per IP | `{token, sessionId, expiresAt, coupleId, memberId, couple, linked:true}`; `403 bad_link_code` (unknown) / `link_code_expired`; `409 link_code_consumed` (single-use); `404 unknown_couple` (slot gone); `413 too_many_sessions` (cap 8 — the code is NOT burned, revoke a session and retry) | `device_linked {memberId, sessionId, deviceId, deviceName, linkedAt}` → all of the member's OWN devices only (with `origin` of the new session), plus `sessions_changed {memberId, reason:"linked", sessionId, deviceName}` (the generic lifecycle frame — `device_linked` stays for old clients) |
| `GET /api/push-devices` | yes | – | `{deliveryAvailable, registrations}` — own devices only, no APNs token values | – |
| `POST /api/push-devices/current` | yes | `{apnsToken, environment:"development"\|"production", bundleId, language:"de"\|"en"}` | `{deliveryAvailable, registration}`; device identity comes from bearer session, max 8/member | – |
| `DELETE /api/push-devices/current` | yes | – | `{ok:true, removed}` idempotently unregisters current session device | – |
| `DELETE /api/couple` | yes | – | `{ok:true}` (wipes all couple data + media, invalidates both tokens) | `couple_dissolved {}` |
| `POST /api/touches` | yes | `{type, clientOperationId?}` — a stable `clientOperationId` (string ≤ 64, outbox retry id) makes lost-response retries exactly-once: the dedup runs per couple+member BEFORE persistence/broadcast/push, entries are retained 24 h. Retention is TIME-based only: eviction removes nothing but expired (>24 h) entries, so a retry inside the window stays exactly-once regardless of how many operations followed it (no size-based displacement); a 20 000-entries-per-couple emergency valve is the sole exception and sacrifices oldest-valid entries first | `201 {touch}`; duplicate retry `200 {touch, duplicate:true}` with the ORIGINAL touch (no second broadcast, push, or counter bump) | `touch {touch}` → partner only (once) |
| `GET /api/touches/recent?limit=30` | yes | – | `{touches}` (newest first) | – |
| `GET /api/messages?limit=50&before=<msgId>` | yes | – | `{messages}` ascending `createdAt`; `before` pages older across both the mutable hot set and append-only archive chunks | – |
| `POST /api/messages` | yes | `{type:"text"\|"letter"\|"photo"\|"sticker", text?, title?, openWhen?, photoId?, sticker?, effect?, clientMessageId?}`. A stable `clientMessageId` deduplicates lost-response retries. Effects are `"hearts"\|"snow"\|"sparkle"\|"fireworks"\|"slam"\|"invisible"` and are limited to one per member per 12 seconds (`429 effect_cooldown`). A sticker requires a procedural `{shape,color,seed,label?}` recipe; no image upload is implied. Photo messages require an existing couple `photoId`; their `text` is an optional caption. | `201 {message}`; duplicate retry `200 {message, duplicate:true}` | `message {message}` once |
| `POST /api/messages/:id/reactions` | yes | `{emoji, clientOperationId?}` (emoji trimmed, 1–16 chars → `400 bad_emoji`) — toggles the caller in `reactions[emoji]`; retrying the same stable id returns `{duplicate:true}` without toggling again; archived messages are immutable | `{message, duplicate?}` | `message_updated {message}` once |
| `PATCH /api/messages/:id` | yes (sender only, else `403 not_yours`) | `{text}` (non-empty, ≤ 5000 chars → `400 text_too_long`) — rewrites a hot-set `text`/`letter` message and sets `editedAt`; voice/photo messages → `400 not_editable`; archived messages are immutable; `title`/`openWhen`/`reactions`/`createdAt` stay untouched | `{message}` with `editedAt` set | `message_updated {message}` |
| `DELETE /api/messages/:id` | yes (sender only, else `403 not_yours`) | – | `{ok:true}` for hot-set messages; archived history is immutable; deleting a hot voice message also deletes its media (`counters.messages` stays a lifetime total) | `message_deleted {id}` |
| `POST /api/messages/read` | yes | optional `{at?}` (ISO timestamp, normalized; invalid → `400 bad_at`; empty body / omitted → server now) — sets MY `lastReadAt` read receipt | `{memberId, at}` | `message_read {memberId, at}` |
| `POST /api/voice` | yes | raw `audio/mp4` body; headers `X-Duration-Sec` | `201 {message}` (type `voice`) | `message {message}` |
| `GET /api/voice/:id/raw` | Bearer header only | – | audio bytes | – |
| `POST /api/photos` | yes | raw `image/jpeg` body; headers `X-Caption` (URI-encoded), `X-Width`, `X-Height`, `X-Taken-At` (ISO-8601 EXIF capture time — unparseable values or values over server time + 24 h are ignored, so `takenAt` stays null) | `201 {photo, galleryCount, galleryLimit}` (count/limit let clients warn before the cap); `413 too_many_photos` past the 2000-per-couple cap | `photo_added {photo}` + partner push (type `photo`, deep link `sooodreamy://photos`) |
| `GET /api/photos` | yes | – | `{photos, limit}` newest first; `limit` is the per-couple photo cap | – |
| `GET /api/photos/:id/raw` | Bearer header only | – | image bytes | – |
| `POST /api/photos/:id/thumb` | yes (uploader only, else `403 not_yours`) | raw `image/jpeg` body ≤ 2 MB | `{photo}` with `thumbUrl` set; `404 not_found` for unknown photo | `photo_updated {photo}` |
| `GET /api/photos/:id/thumb/raw` | Bearer header only | – | thumbnail bytes; `404 no_thumb` when none uploaded | – |
| `POST /api/photos/:id/favorite` | yes | – (toggles the caller in `favorites`) | `{photo}`; `404 not_found` unknown | `photo_updated {photo}` |
| `PATCH /api/photos/:id` | yes | partial `{caption?, album?}` — `null` clears either; `album` trimmed, empty → `null`, > 40 chars → `400 album_too_long`. The gallery is shared: BOTH partners may edit, like delete. | `{photo}`; `404 not_found` unknown | `photo_updated {photo}` |
| `DELETE /api/photos/:id` | yes | – | `{ok}` (also deletes the thumb file, if any). The gallery is shared: BOTH partners may delete any photo, by design — deletion is not restricted to the uploader. | `photo_deleted {id}` |
| `POST /api/videos` | yes | raw `video/mp4` body ≤ 100 MB; headers `X-Caption` (URI-encoded), `X-Width`, `X-Height`, `X-Duration` (seconds) | `201 {video}`; `413 too_many_videos` past the 60-per-couple cap | `video_added {video}` + partner push (type `video`, deep link `sooodreamy://videos`) — same courtesy as photos |
| `GET /api/videos` | yes | – | `{videos}` newest first | – |
| `GET /api/videos/:id/raw` | Bearer header only | – | video bytes — supports `Range` (`206 Partial Content` / `416`), which AVPlayer needs for seeking | – |
| `POST /api/videos/:id/thumb` | yes (uploader only, else `403 not_yours`) | raw `image/jpeg` body ≤ 2 MB | `{video}` with `thumbUrl` set; `404 not_found` unknown | `video_updated {video}` |
| `GET /api/videos/:id/thumb/raw` | Bearer header only | – | thumbnail bytes; `404 no_thumb` when none uploaded | – |
| `POST /api/videos/:id/favorite` | yes | – (toggles the caller in `favorites`) | `{video}`; `404 not_found` unknown | `video_updated {video}` |
| `PATCH /api/videos/:id` | yes | `{caption?}` — `null` clears. Shared gallery: BOTH partners may edit. | `{video}`; `404 not_found` unknown | `video_updated {video}` |
| `DELETE /api/videos/:id` | yes | – | `{ok}` (also deletes the thumb file, if any). BOTH partners may delete any video. | `video_deleted {id}` |
| `GET /api/vault/config` | yes | – | `{config}` or `{config:null}` | – |
| `PUT /api/vault/config` | yes | `{kdf:"pbkdf2-sha256", iterations (10k–10M int, else `400 bad_iterations`), salt, verifier}` (strings ≤ 2048). Replaceable while the vault is EMPTY; with items → `409 vault_locked_in` (a new key would corrupt them) | `{config}` | `vault_config_set {config}` |
| `GET /api/vault` | yes | – | `{items}` newest first | – |
| `POST /api/vault/items` | yes | raw encrypted blob ≤ 60 MB; header `X-Vault-Kind` (`photo`\|`video`\|`note`, else `400`); no config yet → `409 vault_not_configured`; > 120 items → `413 too_many_items` | `201 {item}` | `vault_item_added {item}` |
| `GET /api/vault/:id/raw` | Bearer header only | – | encrypted bytes (Range supported) — decryption happens on-device | – |
| `DELETE /api/vault/:id` | yes | – (vault is shared: BOTH partners may delete) | `{ok}` | `vault_item_deleted {id}` |
| `DELETE /api/vault` | yes | – (forgotten-PIN escape hatch: wipes config + every item + files) | `{ok}` | `vault_reset {}` |
| `GET /api/haptics` | yes | – | `{patterns}` newest first (couple-shared library) | – |
| `POST /api/haptics` | yes | `{name (≤60), emoji? (≤16), events}` — `events` is a timeline of `{t (start s, 0–15), i (intensity 0–1, default 0.7), s (sharpness 0–1, default 0.5), d (duration s, 0 = transient tap)}`; ≤ 128 entries (`400 pattern_too_long`), values normalized (sorted by `t`, rounded to ms); invalid → `400 invalid_pattern`; > 60 patterns → `413 too_many_patterns` | `201 {pattern}` (with `sentCount:0`) | `haptic_pattern_added {pattern}` |
| `PATCH /api/haptics/:id` | yes | `{name?, emoji?}` (`emoji:null` clears; library is shared — BOTH partners may edit) | `{pattern}`; `404 not_found` unknown | `haptic_pattern_updated {pattern}` |
| `DELETE /api/haptics/:id` | yes | – (BOTH partners may delete) | `{ok}`; `404 not_found` unknown | `haptic_pattern_deleted {id}` |
| `POST /api/haptics/:id/send` | yes | – (relays a saved pattern; bumps its `sentCount`) | `201 {haptic, pattern}`; `404 not_found` unknown | `haptic {haptic}` → partner only |
| `POST /api/haptics/send` | yes | `{name?, emoji?, events}` (same `events` validation) — ad-hoc send without saving | `201 {haptic}` (`patternId:null`) | `haptic {haptic}` → partner only |
| `GET /api/haptics/recent?limit=30` | yes | – | `{haptics}` newest first — relay history (both directions, capped at 100) so an offline partner can replay missed vibes | – |
| `GET /api/events` | yes | – | `{events}` — every event carries `rev` (int, starts at 1, +1 per mutation; pre-contract events default to 1) | – |
| `POST /api/events` | yes | `{title, emoji, date, repeatsYearly}` | `201 {event}` with `rev:1` | `event_added {event}` |
| `PATCH /api/events/:id` | yes | partial, plus optional `ifRev` (int ≥ 1, else `400 invalid_request`) for optimistic concurrency: on mismatch NOTHING is applied and the answer is `409 {error:"conflict", current:<event>}` — merge with `current`, retry with its `rev`. Without `ifRev` last-write-wins stays (backward compatible) | `{event}` with bumped `rev` | `event_updated {event}` |
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
| `POST /api/daily/:dateKey` | yes | `{questionId, text, questionText?, clientOperationId?}`; dateKey must be server-today ±1 day (`400 bad_datekey`); a stable operation id makes lost-response retries exactly once. `questionText` = `{de, en}` of the rendered question (both non-empty trimmed strings ≤ 300, else `400 invalid_request`) — stored ONLY by the pinning first answer, never rewritten. An answer may be edited before reveal (`editedAt` is retained internally), but once both answered the revealed texts are immutable (`409 daily_revealed`). | `DailyEntry` (my view; duplicate retry also carries `duplicate:true`) | `daily_answer` → per-member tailored `DailyEntry` once. Partner push differentiates the roles: FIRST answer → type `daily`, „{Name} hat geantwortet — deine fehlt noch 🤫"; SECOND answer (both answered) → type `daily_reveal`, „Ihr habt beide geantwortet. Bereit zum Aufdecken? ✨" (deep link `sooodreamy://daily`; answer text never enters the push) |
| `GET /api/wordle?limit=30&lang=de` | yes | `lang` REQUIRED (`"de"`\|`"en"`, else `400 bad_lang`); `limit` default 30, capped at 60 | `{days}` — one day view (same shape as the single-day endpoint) per stored dateKey with ≥ 1 result in that language from either member, `dateKey` descending; the per-day anti-spoiler applies | – |
| `GET /api/wordle/:dateKey?lang=de` | yes | `lang` REQUIRED (`"de"`\|`"en"`, else `400 bad_lang`); any dateKey may be browsed | Wordle day view for that language (per member, anti-spoiler) | – |
| `POST /api/wordle/:dateKey` | yes | `{rows (int 1–6), win (bool), grid (string ≤ 160), lang ("de"\|"en")}` — dateKey must be within ±1 day of server-today (UTC), else `400 bad_datekey`; one result per member per (dateKey, lang); a resubmit returns the stored result unchanged (idempotent, no broadcast) | Wordle day view (my view, incl. `lang`) | `wordle_result` → per-member tailored day view (incl. `lang`) |
| `GET /api/canvas?limit=N` | yes | `limit` optional (default all, capped at 500) | `{strokes, generation}` — the **last** `limit` strokes, still ascending; `generation` is the board counter (int, starts at 1, +1 per clear) | – |
| `POST /api/canvas/strokes` | yes | `{color, width, tool, points, generation?}` — clients tag outbox strokes with the board `generation` they were drawn on (int ≥ 1, else `400 invalid_request`); a stale one (the partner cleared in between) → `409 {error:"stale_generation", generation:<current>}` and NOTHING is stored — drop the retry instead of resurrecting dead ink. Without `generation` the old always-commit behavior stays | `201 {stroke, generation}` | `canvas_stroke {stroke, generation}` |
| `DELETE /api/canvas/strokes/:id` | yes (author only, else `403 not_yours`) | – | `{ok:true}`; `404 not_found` for unknown stroke | `canvas_stroke_deleted {id}` |
| `DELETE /api/canvas` | yes | – | `{ok, generation}` (the NEW generation after the +1 bump) | `canvas_clear {by, generation}` (`by` = member who wiped the board, for clear attribution; `generation` lets clients drop in-flight strokes of the wiped board) |
| `POST /api/games` | yes | `{type, payload?}` — v3.0 **parallel sessions**: only a previous non-ended game of the SAME `type` is auto-ended (one open session per type); other types keep running side by side. The server **always generates `payload.seed`** and discards a client seed. `dailyquests` and `wordchain` validate `payload.dateKey` (server-today ±1 day). `bingo` ignores client board fields and generates a weekly 4×4 `cardIndexes` board from its server seed. `memoryduo` never serializes its `payload.seed` (hidden deck — see "W8C board & duel games"). Queues an **invitation push** to the partner (type `game`, deep link `sooodreamy://game/<id>`) for every type except `dailyquests`. | `201 {game}` | `game_created {game}` + partner push |
| `POST /api/games/:id/join` | yes | – | `{game}` (state → active); pre-3.0.1 lobbies without `payload.seedServer` are re-seeded once here (migration — safe, no moves exist yet) | `game_started {game}` |
| `POST /api/games/:id/move` | yes | `{data, clientMoveId?}` — a stable id deduplicates offline quest checks/ratings and any other move. **Commit-reveal helper** (v3.0): a move whose `data` carries `{reveal:"<string>", salt:"<string>"}` is annotated with `data.verified` (bool) before storing/broadcasting: `true` iff `sha256hex(reveal + salt)` equals the sender's own earlier `{commit:"<hex>"}` move (latest one, or the one addressed via `data.commitId`). Moves without `reveal`+`salt` pass through untouched. **Input lease** (Welle 6): only ONE device per member may move — a live foreign lease answers `409 game_lease_held` with `details: {gameId, lease}`; see [Input lease & spectator devices](#input-lease--spectator-devices-welle-6). **Turn push** (sync contract c): the recipient is the server-authoritative `turnMemberId` after the move — an extra move (Mancala store landing, Käsekästchen box, memoryduo match) therefore pushes the SAME member ("Extrazug!"), a handover pushes the other one. Never on the finishing move, never when the awaited member was already awaited before someone else's move, never for types without turns, throttled to one push per game/recipient/hour (type `game`, deep link `sooodreamy://game/<id>`). Move data never enters the push payload. **Retry contract** (sync contract b): the `clientMoveId` duplicate search runs BEFORE the state check — retrying a FINAL move on the meanwhile-ended game returns the stored duplicate instead of `409 game_not_active`. | `201 {move, turnMemberId}` (`{move, game, turnMemberId}` when this move ended the game — then `turnMemberId` is `null`); duplicate retry `200 {move, game, duplicate:true, turnMemberId}` — also on ended games | `game_move {gameId, move, turnMemberId}` once (+ turn push per contract c) — `turnMemberId` is the post-move holder per contract c: an extra move names the SAME member, a decisive move an explicit `null`; clients fall back to local derivation ONLY when the field is missing (old server) |
| `POST /api/games/:id/takeover` | yes | – (rate scope `gameMove`) — moves the caller's member-lease onto THIS device (explicit "continue here" from a spectator device); idempotent for the holder, allowed in the lobby (pre-claim), `409 game_ended` on ended games. See [Input lease & spectator devices](#input-lease--spectator-devices-welle-6). | `200 {gameId, memberId, lease}` (the frame payload minus `reason`) | `game_lease {gameId, memberId, lease, reason:"takeover"}` to the member's own devices (only when the holder changed) |
| `POST /api/games/:id/end` | yes | `{result?, forfeit?, complete?}` — **lobby**: the creator cancels (`result: {cancelled:true, by}`); the invited partner may **decline** the invitation instead (`result: {declined:true, by}`) — a lobby never sticks until the creator gives up. **Active game**: when the server-derived state is complete the canonical result is stored (a client `result` is ignored); otherwise `forfeit:true` ends the game as a **surrender** — the partner wins with `result: {scores:{me:0, partner:1}, winner:<partnerId>, forfeitBy:<callerId>}`; `questions36` additionally accepts `complete:true` (`result:{completedBy}` — it has no server-derivable end state). Anything else → `409 game_incomplete`. Ending an already-ended game is idempotent (`200 {game}`). Clients: an "Aufgeben" button MUST send `{forfeit:true}` — a bare `/end` on an unfinished game earns the 409. | `{game}` (state → ended) | `game_ended {game}` |
| `GET /api/games/active` | yes | – | `{game}` or `{game:null}` (latest lobby/active — legacy, pre-v3.0 clients) | – |
| `GET /api/games/open` | yes | – | `{games}` — ALL non-ended sessions (lobby/active), newest first (v3.0) | – |
| `GET /api/games/season?month=YYYY-MM` | yes | optional month filter; invalid → `400 bad_month` | `{month,matches,months,total}` — canonical retained season ledger across every ended game and both Wordle languages; co-op games count as shared scores | – |
| `GET /api/games/catalog` | yes | – | `{types}` — the canonical machine-readable game-type manifest (28 entries, server order; see [Game manifest](#game-manifest-sync-contract-h)). Clients pin their local `GameKind` enums against this list instead of hard-coding it | – |
| `GET /api/games/:id` | yes | – | `{game}` — one session in any state (replay deep-links, spectator refresh); `404 not_found` unknown (v3.0) | – |
| `GET /api/games?limit=30&cursor=0` | yes | `limit` default 30, clamped to 1–200; `cursor` is the zero-based history offset | `{games,nextCursor,total}` — paginated sessions (any state, incl. `result`), newest first | – |
| `GET /api/stats` | yes | – | `Stats` | – |
| `GET /api/widget-snapshot` | Bearer header only | `dateKey?` — the CALLER's local day for the daily block (`bothAnsweredToday`, `dailyAnsweredByMe`, `dailyQuestionId`, `dailyDateKey`, `dailyQuestion`); server-today ±1 like every daily write (else `400 bad_datekey`), defaults to the server day | `WidgetSnapshot` — everything a home-screen widget needs in one call | – |
| `GET /api/inbox?since=ISO` | yes | `since` REQUIRED (ISO timestamp, normalized; missing/invalid → `400 bad_since`) | `Inbox` — PARTNER-ONLY counts + last teasers of everything created strictly after `since` (the caller's own items never count, see the `Inbox` shape). The `games` bucket (v3.0) is CURRENT-state (not since-filtered): open sessions where the caller should act — a lobby invitation from the partner, or an active game whose server-authoritative `turnMemberId` is the caller (sync contract c — extra moves keep the badge with the mover instead of flipping it to the partner) | – |
| `GET /api/checkins?limit=30` | yes | `limit` default 30, capped at 120 | `{days, streak}` — days newest first (`{dateKey, morning:{memberId:ISO}, night:{…}}`); `streak` = consecutive days on which BOTH members checked in | – |
| `POST /api/checkins` | yes | `{kind:"morning"\|"night", dateKey?}` (`dateKey` defaults to server-today, must be within ±1 day → `400 bad_datekey`) — first tap wins, re-check-ins are idempotent (no re-broadcast) | `{day, streak}` | `checkin {memberId, kind, day, streak}` (first tap only) |
| `GET /api/lists` | yes | – | `{lists}` — each `{id, name, emoji, createdBy, createdAt, rev, items:[{id, text, done, doneAt, createdBy, createdAt}]}`; `rev` is a LIST-level revision (int, starts at 1, +1 per mutation incl. every item add/edit/delete; pre-contract lists default to 1) | – |
| `POST /api/lists` | yes | `{name (≤60), emoji? (≤16)}`; > 20 lists → `413 too_many_lists` | `201 {list}` with `rev:1` | `list_added {list}` |
| `PATCH /api/lists/:id` | yes | partial `{name?, emoji?}` (`emoji:null` clears; lists are shared — BOTH partners may edit), plus optional `ifRev` against the LIST revision: mismatch → `409 {error:"conflict", current:<list>}`, nothing applied. Without `ifRev` last-write-wins stays | `{list}` with bumped `rev`; `404 not_found` unknown | `list_updated {list}` |
| `DELETE /api/lists/:id` | yes | – (BOTH partners may delete) | `{ok}`; `404 not_found` unknown | `list_deleted {id}` |
| `POST /api/lists/:id/items` | yes | `{text (≤200), ifRev?}`; > 200 items → `413 too_many_items`; `ifRev` mismatch → `409 conflict` with `current` list | `201 {item, list}` (bumped `rev`) | `list_updated {list}` (whole list — keeps both clients consistent) |
| `PATCH /api/lists/:id/items/:itemId` | yes | partial `{text?, done?, ifRev?}` (`done:true` sets `doneAt` once, `done:false` clears it); `ifRev` mismatch → `409 conflict` with `current` list | `{item, list}` (bumped `rev`); `404 not_found` unknown | `list_updated {list}` |
| `DELETE /api/lists/:id/items/:itemId` | yes | – | `{ok}` (list `rev` bumps); `404 not_found` unknown | `list_updated {list}` |
| `GET /api/hugs` | yes | – | `{hugs}` newest first — `{id, from, to, note, emoji, createdAt, openedAt}` | – |
| `POST /api/hugs` | yes | `{note? (≤200), emoji? (≤16, default 🫂), clientOperationId?}`; single-member couple → `409 no_partner`; a stable `clientOperationId` (string ≤ 64) deduplicates lost-response retries like `POST /api/touches` | `201 {hug}` (receiver is always the partner); duplicate retry `200 {hug, duplicate:true}` | `hug_queued {hug}` (once) |
| `POST /api/hugs/:id/open` | yes (receiver only, else `403 not_yours`) | – | `{hug}` with `openedAt` set; `409 already_opened` on a second open; `404 not_found` unknown | `hug_opened {hug}` (this is how the sender learns it was opened) |
| `GET /api/potd?limit=30` | yes | `limit` default 30, capped at 60 | `{days}` newest first — `{dateKey, entries:{memberId:{photoId, submittedAt}}}` | – |
| `POST /api/potd/:dateKey` | yes | `{photoId}` — must be an existing gallery photo (`404 not_found`); dateKey within ±1 day of server-today (`400 bad_datekey`); resubmitting replaces YOUR pick for that day | `{day}` | `potd_submitted {dateKey, memberId, photoId, day}` |
| `PUT /api/nowplaying` | yes | `{title (≤120), artist? (≤120)}` | `{nowPlaying}` (`{title, artist, setAt}`) — also lives on the member object; serialized as `null` once older than 60 min | `now_playing {memberId, nowPlaying}` |
| `DELETE /api/nowplaying` | yes | – | `{ok}` | `now_playing {memberId, nowPlaying:null}` |
| `GET /api/yearreview?year=2026` | yes | `year` optional (default: current UTC year, clamped 2000–2100) | `YearReview` — aggregated counts for that calendar year (photos/videos/messages/touches + top touch type per member, games & wins, wordle, daily both-answered, check-in days & best streak, hugs sent/opened, coupons redeemed, songs, bucket done, events created, potd days) plus `weekHighlights: [{week, memberId, text}]` — „Eure Highlights des Jahres", merged from the compact highlight archive and still-live weeks (oldest first). Counts are **lower bounds** for early months — capped lists roll off; the weekly highlight TEXTS survive the cap via the archive | – |

Limits: photo body ≤ 15 MB (`413 too_large`), voice ≤ 15 MB, video body ≤ 100 MB (client transcodes to 720p H.264 first), 60 videos per couple (`409 too_many_videos`), 2000 photos per couple (`413 too_many_photos` — uploads carry `galleryCount`/`galleryLimit` so clients can warn before the wall), thumbnail ≤ 2 MB, `text` ≤ 5000 chars, `openWhen` ≤ 64 chars (after trim), photo `album` ≤ 40 chars (after trim), reaction emoji ≤ 16 chars (after trim), Wordle `grid` ≤ 160 chars, stroke ≤ 2000 points. Canvas keeps at most 8000 strokes (oldest dropped). The mutable message hot set stays below 5000 by moving old entries to immutable 500-message archive chunks; archives and voice files remain paginable and are not deleted. Touch history stays capped at 500. Mood history keeps the last 60 entries per member. Wordle keeps the last 60 dateKeys per couple (each dateKey bucket holds up to 2 languages). Coupons cap at 200 per couple (oldest redeemed pruned first, then oldest overall; evictions are broadcast as `coupon_deleted`). Songs cap at 300 per couple (oldest evicted; evictions are broadcast as `song_deleted`). v2.0 couple features: 120 check-in days, 20 lists × 200 items (list name ≤ 60, item text ≤ 200), 100 hugs (hug note ≤ 200), 60 potd days, now-playing title/artist ≤ 120 — oldest entries roll off silently.

## Rituale & Beziehung (v3.0 — Agent A)

All routes require bearer-header auth. Anti-spoiler is enforced
SERVER-side: withheld content is never sent to the client.

| Route | Body / query | Response | WS broadcast |
|---|---|---|---|
| `GET /api/daymemos?limit=30` | `limit` default 30, capped at 60 | `{days, streak}` — per-viewer day views `{dateKey, mine, partner, partnerRecorded, bothRecorded, streak}`; `partner` stays `null` until YOU recorded that day (anti-spoiler) | – |
| `GET /api/daymemos/:dateKey` | – | one tailored day view | – |
| `POST /api/daymemos/:dateKey` | raw audio body (≤ 15 MB, `X-Duration-Sec` header), dateKey within ±1 day (`400 bad_datekey`); re-recording replaces YOUR memo | `{…day view}` | `daymemo {…}` — **per-member tailored** day view; on the reveal (both recorded) `daymemo_first`/`daymemo_both` app events fire |
| `GET /api/daymemos/:id/raw` | bearer header | audio bytes | – |
| `GET /api/capsules` | – | `{capsules}` — recipient sees `text`/`photoId` as `null` until opened (`unlocked` flags openability) | – |
| `POST /api/capsules` | `{text (≤5000), unlockAt (future ISO), title? (≤120), emoji? (≤16), photoId?}` — recipient is always the partner (`409 no_partner`) | `201 {capsule}` | `capsule_sealed` — per-member tailored (recipient gets the redacted view) + `capsule_sealed` app event |
| `POST /api/capsules/:id/open` | recipient only (`403 not_yours`), after `unlockAt` (409 `still_locked`), once (`409 already_opened`) | `{capsule}` with content | `capsule_opened {capsule}` (full content to both) + `capsule_opened` app event |
| `DELETE /api/capsules/:id` | creator only, unopened only | `{ok}` | `capsule_deleted {id}` |
| `GET /api/needs?limit=30` | `limit` default 30, capped at 100 | `{needs}` newest first | – |
| `POST /api/needs` | `{type: space\|comfort\|distraction\|closeness\|listen, note? (≤200)}` (`409 no_partner`) | `201 {need}` | `need {need}` + `need_sent` app event |
| `POST /api/needs/:id/ack` | receiver only (`403 not_yours`), once (`409 already_acked`); `{note?}` | `{need}` with `ackAt` | `need_acked {need}` |
| `GET /api/goals` | – | `{goals}` — each with server-computed `total` and `percent` (0–100 clamped) | – |
| `POST /api/goals` | `{title (≤120), targetValue (0 < v ≤ 1e12), emoji?, unit? (≤20), targetDate? (dateKey)}` | `201 {goal}` | `goal_added {goal}` + `goal_created` app event |
| `POST /api/goals/:id/contributions` | `{amount (≠ 0, negative = correction), note? (≤200)}` | `201 {contribution, goal, milestone}` — `milestone` = highest of 25/50/75/100 crossed by THIS booking, else `null`; 100 % sets `completedAt` | `goal_updated {goal, milestone}` + `goal_milestone`/`goal_reached` app events |
| `PATCH /api/goals/:id` | partial `{title?, emoji?, targetValue?, unit?, targetDate?}` (both partners may edit) | `{goal}` | `goal_updated {goal, milestone:null}` |
| `DELETE /api/goals/:id` | both partners may delete | `{ok}` | `goal_deleted {id}` |
| `GET /api/weekplan?start&days=7` | `start` optional dateKey (default today, ≥ yesterday), `days` 1–14 | `{start, days, slots}` — days carry `availability {memberId: {status, setAt}}`, matching `slots` (one-off `dateKey` + recurring `weekday`) and `overlap` (both marked, neither `busy`) | – |
| `PUT /api/weekplan/:dateKey/availability` | `{status: free\|busy\|call\|date\|null}` (`null` clears; dateKey ≥ yesterday, ≤ 27 days ahead) | `{day}` | `weekplan_availability {dateKey, memberId, status, day}` |
| `POST /api/weekplan/slots` | `{title (≤80), kind?: call\|movie\|date\|custom, emoji?, time? ("HH:MM"), dateKey? XOR weekday? (0=So…6=Sa, UTC)}` | `201 {slot}` | `weekplan_slot_added {slot}` + `weekplan_slot_created` app event |
| `PATCH /api/weekplan/slots/:id` | partial (both may edit; `dateKey`/`weekday` stay mutually exclusive) | `{slot}` | `weekplan_slot_updated {slot}` |
| `DELETE /api/weekplan/slots/:id` | both may delete | `{ok}` | `weekplan_slot_deleted {id}` |
| `PUT /api/energy` | `{level: green\|yellow\|red, note? (≤120)}` | `{energy}` (`{level, note, setAt}`) — lives on the member object, serialized `null` once older than **12 h** (now-playing pattern) | `energy {memberId, energy}` |
| `DELETE /api/energy` | – | `{ok}` | `energy {memberId, energy:null}` |
| `GET /api/magazine/months` | – | `{months}` — `"YYYY-MM"` keys (newest first) that have data, current month included | – |
| `GET /api/magazine/:month` | month ≤ current (`400 bad_month`) | `MagazineIssue` — deterministic on-demand aggregate: top-5 photos (favorites first), quote of the month (longest both-answered daily entry), song of the month (most hearts), 12-counter stats spread, `seen` receipts. Counts are lower bounds for old months (capped lists roll off) | – |
| `POST /api/magazine/:month/seen` | idempotent read receipt | `{month, seen}` | `magazine_seen {month, memberId, seen}` (first time only) |
| `GET /api/app-events?limit=100&type=…` | `limit` capped at 500, `type` optional filter | `{events}` newest first — the shared milestone log (see `server/src/events.js`) | – |

Ritual limits: 60 day-memo days, 100 capsules, 200 needs, 50 goals × 500 contributions,
40 availability dateKeys + 60 slots, 24 magazine seen-months, 500 app events — oldest roll off.
Extra surfaces: member objects carry `energy`; `GET /api/widget-snapshot` gains
`partner.energy` + top-level `goal` (`{title, emoji, percent, total, targetValue, unit}` of the
closest-to-done active goal — for Agent C's widgets); `GET /api/inbox` gains a `needsForMe`
bucket (`{count, openNeed}` — newest unacknowledged signal for app-open, since there is no push).
Couple dissolve also deletes day-memo audio files.

**App-Event-Log (`server/src/events.js`, interface for Agent C):** `emitAppEvent()` appends
`{id, type, memberId, data, createdAt}` to the couple's capped log, persists and broadcasts
`app_event {event}`. Optional `dedupeKey` (v3.0.1): the same (type, key) emits exactly once —
persisted per couple, replay-safe across restarts. The canonical type registry is
`APP_EVENT_TYPES` in `events.js` (checked against this document by
`server/test/events_contract.test.js`).

<!-- APP_EVENT_TYPES:START -->
Canonical app-event types: `daymemo_first`, `daymemo_both`, `capsule_sealed`,
`capsule_opened`, `need_sent`, `goal_created`, `goal_milestone`, `goal_reached`,
`weekplan_slot_created`, `magazine_seen_both`, `movie_match`, `quest_done`,
`icon_gift_sent`, `datenight_planned`, `goodthings_both`, `thanks_sent`,
`missyou_sent`, `dictionary_confirmed`, `first_logged`, `season_calendar_created`,
`season_calendar_door_opened`, `week_highlight_both`, `week_review_both`.
<!-- APP_EVENT_TYPES:END -->

The first ten are relationship events, `movie_match` and `quest_done` are
server-derived game events, `icon_gift_sent` and `datenight_planned` are platform events,
the next five are warmth events, the following two are seasonal-calendar events, and the
final two are weekly-review events (v7.0: both shared a week highlight / both read a
completed week — each emitted exactly once per ISO week).

## Game conventions (v3.0)

The relay stays rule-agnostic; these conventions make all game types interoperable:

- **Seed im Payload:** ALL randomness in a game (shuffles, dice, card order) derives from
  `payload.seed` via the shared deterministic PRNG (`SeededGenerator`, SplitMix64) — never from
  the OS clock or `randomize()`. v3.0.1: the server ALWAYS generates the `seed` at
  `POST /api/games` and discards any client-provided value — no client can pick its own
  shuffle or know the Kniffel dice in advance (pre-3.0.1 lobbies are re-seeded once on join).
  Both clients reduce the identical game state from `payload` (incl. seed) + the ordered move
  list; invalid/duplicate moves are skipped defensively, never errors. Per-player/per-turn dice
  use `seed` combined with the player index and turn/roll counters (see `CoupleGamesLogic.swift`).
- **Commit-Reveal (hidden information):** secrets (ship layouts, the lie index, chosen letters)
  are sent as `{commit: sha256hex(secret + salt)}` first and `{reveal: secret, salt: salt}` at the
  end; `secret` and `salt` are strings, the hash is lowercase-hex SHA-256 over the UTF-8
  concatenation `secret + salt`. The relay annotates reveal moves with `verified` (see
  `POST /api/games/:id/move`); clients additionally verify locally.
- **Move ordering:** where speed matters (buzzers, races), the SERVER order of the move list
  decides — clients sort by `createdAt`, ties by move `id`.
- **`turnMemberId` (sync contract c):** every serialized game carries the server-authoritative
  "whose move is it" — derived by replaying the REAL rules state, never from the last mover.
  `null` when the game is not active or no single member is up (simultaneous phases where both
  still must act, live Pictionary rounds, checklist types). Extra moves (Mancala store landing,
  Käsekästchen box, memoryduo match, Kniffel re-rolls within a turn) keep it with the SAME
  member. The turn push and the inbox `games` bucket are driven by this field; clients should
  render "Du bist dran" from it instead of deriving turns locally. The live `game_move` frame
  (and the `POST …/move` response) carries the post-move `turnMemberId` too — an explicit
  `null` there means "nobody is up" (decisive move; `game_ended` follows). Clients must
  distinguish that explicit `null` from the field being ABSENT (pre-contract server): only a
  missing field permits the local last-mover fallback.
- **Film-Roulette → Wochenplan-Hook:** the relay derives `movie_match` SERVER-SIDE (v3.0.1):
  when the stored moves prove that BOTH members sent `{kind:"swipe", index, like:true}` for the
  same index, it emits ONE `movie_match` app event per (game, cardIndex) via the shared event
  log (`server/src/events.js`, WS `app_event`). A client `match: {cardIndex, title}` annotation
  is no longer a trigger — it only contributes the cosmetic `title` (the relay does not know
  the seeded deck). The app turns the match into a movie night: the match overlay and the end
  screen offer a 1-tap "Filmabend planen" CTA that creates a real week-plan slot via
  `POST /api/weekplan/slots` (`{title, emoji:"🍿", kind:"movie", dateKey}`), and the week-plan
  screen shows a banner for recent unplanned `movie_match` events.
- **Tagesquests → Plattform-Hook:** completing a daily quest sends a
  `{kind:"quest_done", questIndex}` move on the couple's `dailyquests` session of the day
  (payload `{dateKey}`, validated at create). The relay emits a `quest_done` app event
  (events.js) for the FIRST valid check per (dateKey, questIndex) — re-checking or replaying
  the move (even in a fresh same-day session) never re-emits, so quest XP cannot be farmed.
  The finished day is ended with `result: {done: <n>, total: 3, dateKey}`. XP/level systems
  consume the app events or read finished `dailyquests` sessions from `GET /api/games`.
- **Turnier-Modus / Saison:** `GET /api/games/season` derives one canonical retained ledger
  server-side from ended sessions plus DE/EN Wordle duels. Competitive scores are preserved;
  completed co-op sessions count as shared 1:1 results. The iOS client computes its 3/1 season
  table and one-time local ceremony from that complete ledger instead of the old last-100 window.
- **Replay & Zuschauer-Modus:** a replay is the persisted `moves` list of
  `GET /api/games/:id` played back in `createdAt` order (ties by move id) through the same
  deterministic reducer; live spectating works because `game_move`/`game_ended` broadcast to
  ALL sockets of the couple — a second device renders the feed read-only. Since Welle 6 the
  read-only role of a member's additional devices is ENFORCED server-side by the input lease
  (next section) instead of being a client convention.

### Game manifest (sync contract h)

The canonical game-type list has exactly **28** entries. The single source of truth is
`GAME_TYPES` in `server/src/game-rules.js`, exported machine-readable as
`GET /api/games/catalog` → `{types:[…]}` (server order, auth required). Clients pin their
local enums (`GameKind` on iOS, the Play-Hub cards) against this list — a client that knows
fewer types must render unknown ones as "update the app", never crash, and never offer them
for creation. The list below is DRIFT-WATCHED: `server/test/games_catalog.test.js` fails
whenever `GAME_TYPES` and this block diverge, so the documented list can never rot.

```gametypes
quiz
thisorthat
wouldyourather
truthordare
questions36
emojiriddle
connectfour
photomemory
quizduel
battleship
pictionary
kniffel
movieroulette
stadtlandfluss
twotruths
dailyquests
wordleduo
hangman
rps
story
wordchain
bingo
dame
reversi
kaesekaestchen
gomoku
mancala
memoryduo
```

### Input lease & spectator devices (Welle 6)

One member on several devices must not double-drive a game (two half-played turns, duplicated
taps, confusion about "who moved"). Per game session the server therefore leases move
submission to ONE device per member:

- **Acquire (implicit):** the first device whose move VALIDATES holds the member's lease for
  that game (`inputLeases[memberId]` in the store; an invalid move never grabs it). No
  endpoint needed — playing is claiming.
- **Refuse:** a move from another device of the same member answers `409 game_lease_held`
  with `details: {gameId, lease}` naming the holder. Exception: a `clientMoveId` retry of an
  ALREADY-STORED move returns the stored duplicate (`200 {move, duplicate:true}`) — idempotent
  retries never bounce off the lease.
- **Takeover (explicit):** `POST /api/games/:id/takeover` moves the lease onto the calling
  device unconditionally (that is the spectator banner's "hier weiterspielen" action) —
  fairness is not at risk because both devices belong to the SAME member. Idempotent for the
  current holder (no fanout); allowed in the lobby as a pre-claim; `409 game_ended` afterwards.
- **Lease death:** the lease dies lazily with its session — a holder whose session was
  revoked, expired, or evicted never blocks; the next mover inherits silently (fresh
  `acquired` fanout). Nothing to clean up on revoke.
- **Fanout:** lease changes go to the member's OWN devices only, as
  `game_lease {gameId, memberId, lease, reason: "acquired"|"takeover"}` (the partner has no
  use for which of my devices is driving). `lease` is `{deviceId, deviceName, sessionSuffix,
  acquiredAt}` — the 8-char suffix matches the `origin` marker convention, the full session id
  never appears. `serializeGame` carries the same views as `game.leases[memberId]` for
  reconnect/refresh, identical for every couple device.
- **Scope:** ONLY `POST /api/games/:id/move` is leased. `join`, `end` (forfeit/cancel/decline)
  and all reads stay member-level actions — any own device may end a game, exactly like it may
  revoke a session.
- **Client contract:** a device is a spectator for a game iff
  `game.leases[myMemberId].sessionSuffix` exists and differs from its own session suffix.
  Spectator devices render the live feed read-only behind a banner and offer the takeover.

**Spoiler matrix (commit-reveal × spectator devices).** Audit result of every frame family a
spectator device can receive — the commit-reveal fairness does not tilt, because the relay
NEVER holds a secret the owner has not sent yet:

| Channel | What a spectator device sees | Spoiler risk |
| --- | --- | --- |
| `game_move` (couple broadcast) | Exactly the stored move: `{commit}` digests until the OWNER submits `{reveal, salt}` — the plaintext never exists server-side before that. | none — the relay cannot leak what it does not have |
| `game_created`/`game_started`/`game_ended`, `GET /api/games/:id` (serialized game) | `payload` (server seed, decks, options — same for both members by design; `memoryduo` strips its deck seed from EVERY view, see "W8C board & duel games") + stored moves + `leases`. Byte-identical for every device of the couple; nothing is tailored per session. | none — identical view for holder and spectator |
| `game_lease` (member-only) | Device metadata of the member's own devices (`deviceId`, `deviceName`, suffix). | none — no game state at all |
| Per-member tailored frames (`daily_answer`, `wordle_result`, …) | The SAME tailored view as every other device of that member (anti-spoiler applies per member, not per device). Not game-session frames. | none — a member's own devices are equally informed on purpose |
| Local-only secrets (uncommitted picks typed into the holder device) | Nothing — they live in the holder's UI until the commit move is posted. | none — never on the wire |

The one real risk the lease closes: a second device REVEALING (or committing) on the member's
behalf out of sync with the holder's local secret state — that move now bounces off the lease
before any validation runs.

## Level, Abzeichen & Plattform (v3.0 — Agent C)

All routes require auth. Sources: `server/src/gamification.js` (level/badges/quest) and
`server/src/platform.js` (icon gifts, haptic duet, date night).

### Relationship level

XP is aggregated **deterministically from data the server already stores** (yearreview
pattern) — retroactively fair: the day 3.0 ships every couple already has the level their
history earned. Everything rewards shared activity; XP never decreases (lifetime counters
where available; capped lists are honest lower bounds). The capped app-event log
(`events.js`, 500 entries) is consumed **incrementally**: earned XP is persisted in
`couple.gamification.eventXp` with an `{id, at}` cursor, so nothing is lost when old
events roll off.

**XP table** (keep in sync with `gamification.js`): message 2 · touch 1 · game played 15 ·
photo/video 10 · daily day 5 (+25 when BOTH answered) · check-in day (both) 15 ·
wordle day 8 (+12 both) · PotD day 5 (+10 both) · hug opened 8 · coupon redeemed 12 ·
bucket done 15 · song 3 · event 5 · haptic pattern 5 / send 1 · 25 canvas strokes 5 ·
quest finale +150. **App-event XP** (`APP_EVENT_XP`, every emitted type explicit since
3.0.1): daymemo_first 10 · daymemo_both 20 · capsule_sealed 10 · capsule_opened 15 ·
need_sent 3 · goal_created 10 · goal_milestone 10 · goal_reached 40 ·
weekplan_slot_created 5 · magazine_seen_both 15 · movie_match 15 · quest_done 10 ·
icon_gift_sent 10 · datenight_planned 10 · v5.0: goodthings_both 20 · thanks_sent 3 ·
missyou_sent 3 · dictionary_confirmed 15 · first_logged 10 · season_calendar_created 5 ·
season_calendar_door_opened 8 · v7.0: week_highlight_both 20 · week_review_both 15 ·
unknown future types 5.

**Level curve:** threshold for level n is `T(n) = 100·(n−1)·n/2` (triangular × 100):
L1=0, L2=100, L3=300, L4=600, L5=1000, L6=1500, L7=2100, L8=2800, L9=3600, L10=4500,
then +100·n per further level — unbounded, titles clamp at level 10 („Legendäres Duo").
Titles (DE): Frisch verliebt → Turteltauben → Händchenhalter → Träumer-Duo →
Eingespieltes Team → Herzensbande → Sternenpaar → Unzertrennlich → Seelenverwandte →
Legendäres Duo. The client mirrors the curve in `ios/SoooDreamy/Core/LevelMath.swift`
(Linux-tested) so widgets can render rings without a round-trip.

**Live ceremonies:** after every successful authenticated non-GET request the router calls
`maybeAdvanceGamification` — level gains broadcast `level_up {level, title, xp}`, fresh
unlocks broadcast `badge_unlocked {badge}`. The FIRST computation for a legacy couple
(older than 7 days) adopts the retroactive state **silently** (no ceremony spam on
upgrade); fresh couples celebrate from action one.

| Route | Body / query | Response | WS broadcast |
|---|---|---|---|
| `GET /api/level` | – | `{xp, level, title:{de,en}, levelXp, nextLevelXp, progress (0–1), maxTitleLevel, breakdown, serverTime}` — reads adopt the baseline silently, never ceremonize | – |
| `GET /api/badges` | – | `{badges}` — `{id, secret, unlocked, unlockedAt, progress:{current,target}}`; unlocks are **persisted** and never re-lock (broken streaks, deleted photos). Names/art live client-side; `secret` badges render as „???" until unlocked | – |
| `GET /api/quest` | – | `{steps:[{id,done}×7], done, completedAt, isNewCouple (≤30 days), bonusXp}` — steps: touch, message, daily (both), photo, canvas, checkin (both), game; all derived from existing data, no extra writes. First completion persists `questCompletedAt` (+150 XP) | `quest_completed {quest}` + possible `level_up` |

### Icon gifts, haptic duet, date night

| Route | Body / query | Response | WS broadcast |
|---|---|---|---|
| `POST /api/icongift` | `{icon: classic\|sunset\|midnight\|mint\|rose\|ocean\|gold\|lavender\|blossom, note? (≤200)}` (`409 no_partner`); a still-unopened gift is overwritten (newest surprise wins) | `201 {gift}` (`{id, icon, note, fromMemberId, sentAt, openedAt:null}`) | `icon_gift {gift}` → **recipient only** + `icon_gift_sent` app event |
| `GET /api/icongift` | – | `{gift}` — MY pending gift, `null` when none | – |
| `POST /api/icongift/open` | – (`404 no_gift`) | `{gift}` with `openedAt`; the client then switches the alternate icon | `icon_gift_opened {gift}` → **sender only** |
| `POST /api/duet` | `{events: 1..64 × {t (0–30 s), i (0–1), s (0–1), d (0–10 s)}, name? (≤80)}` | `201 {duet}` (`{id, name, events, startedBy, startAtMs, serverNowMs}`) — `startAtMs` = server now + 2 s lead-in; each client converts via its WS clock offset so the pattern hits both wrists in the same instant | `duet_start {duet}` → both |
| `POST /api/datenight` | `{startsAt (ISO, ≤30 days ahead), title? (≤80), emoji? (≤16)}` — replaces the current plan | `201 {dateNight}` (`{id, title, emoji, startsAt, phase, createdBy, createdAt, phaseChangedAt}`); `phase` starts `anticipation` (or `live` when `startsAt` is past) | `datenight_update {dateNight}` + `datenight_planned` app event |
| `GET /api/datenight` | – | `{dateNight}` or `{dateNight: null}` | – |
| `POST /api/datenight/phase` | `{phase: anticipation\|live\|afterglow}` (`404 no_datenight`) — either partner; also hit by the Live-Activity intent button | `{dateNight}` | `datenight_update {dateNight}` |
| `DELETE /api/datenight` | – (`404 no_datenight`) | `{ok}` | `datenight_update {dateNight: null}` |

Extra surfaces: `GET /api/widget-snapshot` gains a top-level `level`
(`{level, title:{de,en}, progress, xp}` — the widget level ring). Icon-gift/duet lifetime
counters (`iconGiftsSent`, `duetsPlayed`) feed the secret badges `icon_gifted` and
`duet_partners`. Agent C emits app events: `icon_gift_sent`, `datenight_planned`.

## Worte & Wärme (v5.0)

Everyday appreciation, in `server/src/warmth.js`. All routes require bearer auth;
anti-spoiler is enforced server-side (rituals pattern).

| Route | Body / query | Response | WS broadcast |
|---|---|---|---|
| `GET /api/goodthings?limit=30` | `limit` default 30, capped at 120 | `{days, streak}` — per-viewer day views `{dateKey, mine, partner, partnerShared, bothShared, streak}`; `partner` items stay `null` until YOU shared that day (anti-spoiler; `partnerShared` is always truthful) | – |
| `GET /api/goodthings/mentions` | – | `{mentions}` — `{dateKey, texts}` of partner items flagged `aboutPartner` („you in my good things"), only from days the viewer shared too | – |
| `GET /api/goodthings/:dateKey` | – | one tailored day view | – |
| `POST /api/goodthings/:dateKey` | `{items: 1–3 × {text (≤160), aboutPartner?:bool}}` (`400 bad_items`); dateKey within ±1 day (`400 bad_datekey`); re-sharing replaces YOUR list | `201 {…day view}` | `goodthings {…}` — **per-member tailored**; on the reveal a `goodthings_both` app event fires once per day |
| `GET /api/thanks?limit=30` | `limit` default 30, capped at 500 | `{thanks}` newest first — `{id, category, text, senderId, forMember, createdAt}` | – |
| `GET /api/thanks/summary` | – | `{days:7, total, byCategory, byMember, topCategory}` — rolling 7-day window ending today | – |
| `POST /api/thanks` | `{category: listening\|help\|cooking\|patience\|surprise\|being_you\|custom, text? (≤120)}` — `custom` requires `text` (`400 bad_text`); `409 no_partner` solo | `201 {spark}` | `thanks {spark}` + `thanks_sent` app event + push |
| `GET /api/missyou?limit=30` | `limit` default 30, capped at 200 | `{missyou}` newest first — `{id, level, note, senderId, forMember, createdAt, ackAt, ackNote}` | – |
| `POST /api/missyou` | `{level: 1\|2\|3, note? (≤120)}` (`400 bad_level`; `409 no_partner`) — 1 soft glow, 2 real pang, 3 „I need your voice today" | `201 {signal}` | `missyou {signal}` + `missyou_sent` app event + push (level-3 wording asks for a call) |
| `POST /api/missyou/:id/ack` | recipient only (`403 wrong_actor`), once (`409 already_acked`); optional `{note? (≤120)}` („Bin um 21 Uhr da ❤️") | `{signal}` with `ackAt`/`ackNote` | `missyou_ack {signal}` |
| `GET /api/dictionary` | – | `{entries}` newest first — `{id, term, definition, story, emoji, createdBy, createdAt, confirmedBy, confirmedAt}` | – |
| `POST /api/dictionary` | `{term (≤60), definition (≤300), story? (≤300), emoji? (≤16)}` | `201 {entry}` (unconfirmed) | `dictionary_changed {entry}` |
| `POST /api/dictionary/:id/confirm` | partner only — the author cannot co-sign (`403 wrong_actor`), once (`409 already_confirmed`) | `{entry}` with `confirmedBy`/`confirmedAt` | `dictionary_changed {entry}` + `dictionary_confirmed` app event (deduped per entry) |
| `PATCH /api/dictionary/:id` | author only (`403 wrong_actor`); partial `{term?, definition?, story?, emoji?}` — any edit RESETS the confirmation (content changed under the partner's signature) | `{entry}` | `dictionary_changed {entry}` |
| `DELETE /api/dictionary/:id` | author only | `{ok}` | `dictionary_deleted {id}` |
| `GET /api/firsts` | – | `{firsts}` sorted by the first's date (oldest first) — `{id, title, emoji, dateKey, note, photoId, createdBy, createdAt}` | – |
| `POST /api/firsts` | `{title (≤120), dateKey (past/today only, else `400 bad_datekey`), emoji? (≤16), note? (≤300), photoId? (gallery photo, else `404 unknown_photo`)}`; > 200 firsts → `429 too_many_firsts` | `201 {first}` | `first_changed {first}` + `first_logged` app event (deduped per first — edits never re-emit) |
| `PATCH /api/firsts/:id` | author only; partial `{title?, emoji?, dateKey?, note?, photoId?}` (same validations) | `{first}` | `first_changed {first}` |
| `DELETE /api/firsts/:id` | author only | `{ok}` | `first_deleted {id}` |

Warmth limits: 120 good-things days, 500 thanks, 200 missyou signals, 300 dictionary
entries, 200 firsts — oldest roll off (firsts hard-cap instead of rolling: they are a
curated collection). **App events (v5.0):** `goodthings_both` (once per both-shared
evening), `thanks_sent`, `missyou_sent`, `dictionary_confirmed` (only when the partner
co-signs), `first_logged`.

## Repair & consideration (v4.8)

All routes require bearer auth. A repair session is visible only to its couple.
Consideration text is encrypted by the iOS Vault key before upload; the server
accepts and stores only an opaque base64 envelope plus expiry/visibility metadata.

| Route | Body / query | Response | WS broadcast |
|---|---|---|---|
| `GET /api/repair` | – | `{sessions}` newest first, each with server-derived `expected` actor/kind | – |
| `POST /api/repair` | `{promptId (≤80)}`; requires a partner | `201 {session}` at step 0 | `repair_changed {session}` |
| `GET /api/repair/:id` | – | `{session}` | – |
| `POST /api/repair/:id/turn` | `{kind: feeling\|mirror\|agreement, text (≤1000)}`; only the expected actor and kind are accepted | `{session}`; step 6 completes it | `repair_changed {session}` |
| `POST /api/repair/:id/cooldown` | `{minutes: 1…60}` | `{session}` with server deadline | `repair_changed {session}` |
| `GET /api/consideration` | – | `{hints}` active, unexpired hints newest first | – |
| `POST /api/consideration` | `{ciphertext (base64, ≤8192), visibility: gentle\|detail, hours: 1…72}`; plaintext-like fields are rejected (`400 plaintext_forbidden`) | `201 {hint}` | `consideration_changed {hint}` |
| `DELETE /api/consideration/:id` | sender only; immediately pauses the hint | `{hint}` with `pausedAt` | `consideration_changed {hint}` |

Repair sequence: creator feeling → partner mirror → partner feeling → creator
mirror → creator agreement → partner agreement. Consideration has deliberately
no app event, XP, streak, or badge linkage.

## Season calendars (v5.0)

All routes require bearer auth. The author can prepare an Advent, birthday,
anniversary, or custom countdown calendar for the partner. The server redacts
each payload for the recipient until that specific door has been opened.

| Route | Body | Response / rules |
|---|---|---|
| `GET /api/season-calendars` | – | `{calendars}` newest first, tailored to the viewer |
| `GET /api/season-calendars/:id` | – | `{calendar}` |
| `POST /api/season-calendars` | `{title, emoji?, kind, doors: 1…31 × {unlockAt, payload:{kind:prompt\|quest\|letter\|game,text}}}` | `201 {calendar}`; recipient is always the partner; payloads are server-redacted |
| `PATCH /api/season-calendars/:id` | author-only `{title?, emoji?}` | `{calendar}` |
| `POST /api/season-calendars/:id/open` | recipient-only `{doorId}` | `409 door_still_locked` before the server deadline; otherwise reveals exactly that door and emits `season_calendar_door_opened` once |
| `DELETE /api/season-calendars/:id` | – | author-only; calendars with opened doors stay in the shared archive |

Create/open/edit/delete broadcasts `season_calendar_changed` with a
per-member-tailored calendar. Creation emits `season_calendar_created`.

### v5.0 game conventions (word & party games)

All five use the v3.0 relay conventions (server-generated seed, commit-reveal,
server-authoritative results via `canonicalGameResult`):

- **`wordleduo`** — coop Wordle on ONE shared 6-row board, alternating guessers (creator
  starts). Payload `{dateKey (±1 day, `400 bad_datekey`), lang: de|en, maxRows: 6}`; both
  clients derive the same daily target from (coupleId, dateKey, lang). Moves: creator seals
  `{kind:"target", commit}` (SHA-256 hex), then alternating `{kind:"guess", row, text}` (5
  letters), finally the creator's `{kind:"reveal", reveal, salt}` (server-verified). The
  reveal is accepted only once the board is DONE — a guess matched the (commit-verified)
  target or all `maxRows` rows are used; earlier reveals answer `409 wrong_phase`. Result:
  `{solved, rows, target, dateKey, lang}` — a dishonest reveal is `verified:false` and clients
  treat the board as void.
- **`hangman`** — „Unser Wort": the creator seals a personal word either in the create payload
  `{commit, len (3–24), hint? (≤60), lang}` or with `{kind:"setup", commit, len, hint?}` for
  legacy clients. The partner picks letters (`{kind:"letter", letter}`), the setter
  answers each with `{kind:"positions", letter, positions:[indexes]}` (empty = wrong; a heart
  flower wilts, 10 wrong = lost). After win/loss the setter reveals; the server REPLAYS every
  position answer against the revealed word — any dishonest answer voids the win
  (`integrity:false`, winner `null`; battleship pattern). Result: `{scores, winner, integrity,
  word, wrong, solved}`.
- **`rps`** — Schere-Stein-Papier best-of (payload `{target: 1–10, default 4}`). Per round
  both send `{kind:"commit", round, commit}`, then `{kind:"reveal", round, reveal:
  rock|paper|scissors, salt}` — the server verifies each reveal against that member's OWN
  round commit (`409 reveal_mismatch`), so nobody can wait for the partner's choice. Ties
  replay; result `{scores, winner, rounds}`.
- **`story`** — Fortsetzungsgeschichte, purely cooperative. Payload `{genre (0–7),
  sentences (6–40, default 20), lang}`; alternating `{kind:"sentence", index, text (≤200)}`
  (creator starts). Result: `{sentences:[…], genre, lang}` — the finished story is the prize.
- **`wordchain`** — Wortkette-Blitz, one daily cooperative chain (`payload {dateKey, lang}`):
  each word must be in the bundled DE/EN dictionary and start with the last letter of the
  previous one (ß folds to ss, case-insensitive, no repeats, letters-only ≥ 2).
  Moves `{kind:"word", index, text (≤40)}` alternating; the member whose turn it is may end
  with `{kind:"finish"}`. Wrong initial letter → `409 wrong_letter`; unknown dictionary word
  → `409 unknown_word`. Result: `{length, longestWord, dateKey}`.
- **`bingo`** — weekly 4×4 Couple Bingo. The server generates sixteen distinct action/event
  mappings. Clients cannot submit checks (`409 auto_checked_only`). `emitAppEvent` turns only
  canonical validated app events into synthetic `{kind:"auto_check", cardIndex, appEventId}`
  moves. The first row, column, or diagonal ends the session with
  `{bingo:true, line:[…], checked, weekKey, scores}` and broadcasts `game_ended` to both phones.

### W8C board & duel games

Six strictly alternating two-player games on the v3.0/v4 relay conventions (server seed,
server-authoritative results, input lease). Board indexes are always `index = row * size +
col` with **row 0 = the CREATOR's back row**; the creator always moves first. All six are
replayable from the persisted move list; forfeit/decline/cancel work exactly like the older
types.

- **`dame`** — checkers on 8×8 dark squares (`(row+col) % 2 === 1`), international
  simplified: men step diagonally forward, kings step in all four diagonals (no flying
  kings), captures jump two diagonal squares in ANY direction (men included). Capturing is
  MANDATORY (`409 capture_required` — also when a jump sequence stops while it could
  continue); multi-jumps travel in ONE move as a square path. A man promotes only when the
  move ENDS on the far row. Payload `{size: 8, drawPlies (10–100, default 40)}`; move
  `{kind:"move", path:[from, …, to]}` (2–13 squares) — stored normalized as `{kind, path,
  captures:[victim squares], promoted}`. Result after the win (opponent has no pieces or no
  legal move) or the capture-free-plies draw: `{scores (1/0), winner, draw, pieces}`.
- **`reversi`** — Othello 8×8. Initial discs: creator on 28/35, partner on 27/36. Move
  `{kind:"place", index}` must flip at least one disc (`409 no_flip`; occupied → `409
  duplicate_move`); the stored move carries the server-derived `flips` array.
  `{kind:"pass"}` is legal ONLY without a legal placement (`409 pass_not_allowed`). Ends
  when the board is full or both pass back-to-back; result `{scores: disc counts, winner,
  draw}`.
- **`kaesekaestchen`** — Dots & Boxes with `size`×`size` boxes (payload `{size: 2–6,
  default 5}`). Edge indexes: horizontal first (`row * size + col`, row 0..size), then
  vertical (`size*(size+1) + row * (size+1) + col`, col 0..size); `2*size*(size+1)` edges
  total. Move `{kind:"edge", edge}` — stored with the server-derived `boxes` it closed;
  closing ≥ 1 box scores each and grants ANOTHER turn. Ends when every edge is drawn;
  result `{scores: boxes, winner, draw, boxes: size²}`.
- **`gomoku`** — five in a row on 15×15 (payload `{size: 15, winLength: 5}`). Move
  `{kind:"place", index 0–224}` on an empty intersection (occupied → `409
  duplicate_move`). EXACTLY five contiguous stones win — an overline of six or more does
  not (both colors). Full board without a winner is a draw; result `{scores (1/0), winner,
  draw}`.
- **`mancala`** — Kalaha with 6 pits + one store per member (payload `{pits: 6, stones:
  3–6 per pit, default 4}`). Move `{kind:"sow", pit 0–5}` from an own non-empty pit
  (`409 empty_pit`) sows counter-clockwise over the 13-cell track (own pits ascending, own
  store, opponent pits ascending — the opponent store is skipped). Last stone in the own
  store → extra turn; last stone in an own empty pit captures it plus the opposite pit
  (`5 - pit`) when that holds stones. Stored move carries the derived `{extraTurn,
  captured}`. When either row is empty after a move the other side sweeps its remaining
  stones; result `{scores: store counts, winner, draw}`.
- **`memoryduo`** — pair memory on 6×6 (payload view `{pairs: 18, size: 6}`). The 36-card
  deck (face values 0–17, two cards each) is shuffled from the server seed, and that seed
  is a **server-only field**: `serializeGame` strips it from EVERY memoryduo view
  (create/join/fetch/broadcast, also after the game ended), so hidden cards are unknowable
  until flipped — the server-side counterpart of the commit-reveal pattern. A turn is two
  `{kind:"flip", index}` moves; the server injects the card's `face` into each stored move
  (second flips also carry `{first, match}`), so everything once flipped stays visible to
  both members via the move list — remembering is the game, and one device per member is
  enforced by the input lease. A match scores and keeps the turn (`already_matched` guards
  finished cards); when all pairs are matched the result is `{scores: pairs, winner, draw,
  pairs: 18}`.

## Eure Woche & eigene Tagesfragen (v7.0)

All routes require bearer auth. Weeks are ISO 8601 weeks (`YYYY-Www`, Monday–Sunday,
UTC — the same clock every dateKey uses). Code: `server/src/weekreview.js` and
`server/src/dailyquestions.js`.

| Route | Body / query | Response / rules |
|---|---|---|
| `GET /api/week-review?week=YYYY-Www` | `week` optional (default: current week); future weeks and > 104 weeks back → `400 bad_week` | Deterministic weekly issue: `{week, startDateKey, endDateKey, current, stats, quote, topPhoto, highlight, seen}`. `stats` counts messages, touches, hugs, photos, videos, ended games, wordle days, both-answered dailies, both-checked-in days, day-memo days, quests done and `perfectDays` (daily both-answered AND both checked in). `quote` is the both-answered daily that reads best out loud: complete exchanges (both answers ≥ 12 trimmed chars) beat incomplete ones, question-mark-free days beat counter-question days, and among complete days the SHORTEST combined text wins (among incomplete days the longest); ties break toward the newer day (with `customText` when it was a couple question). `highlight.partner` stays `null` until BOTH shared (anti-spoiler). |
| `PUT /api/week-review/:week/highlight` | `{text (≤300), photoId?}` — current or previous week only (`409 week_closed`); unknown photo → `404 photo_not_found`; re-sharing replaces YOUR highlight | Full review view. WS `week_highlight` goes out **per-member tailored**; once both shared, the `week_highlight_both` app event fires exactly once per week. Only 26 weeks stay live — but evicted highlight TEXTS are rescued into a compact archive (104 entries) that `GET /api/yearreview` serves as `weekHighlights`. |
| `POST /api/week-review/:week/seen` | completed weeks only (`409 week_not_over`) | `{week, seen}` read receipts. WS `week_review_seen {week, seen}`; when both read a week the `week_review_both` app event fires exactly once. |

**Sunday-evening arrival push:** a server scheduler (every 5 min, `WEEKREVIEW_PUSH_INTERVAL_MINUTES`
env overrides, `0` disables) sends BOTH partners the same push — „Eure Woche ist fertig ✨" /
"Your week is ready ✨" (type `weekreview`, deep link `sooodreamy://weekreview`) — once the
couple-local clock passes **Sunday 19:00**. Couple-local means `couple.timezone`
(`PATCH /api/couple`), falling back to the server's local clock. Deduped once per couple and
ISO week; simultaneous arrival on both phones is the point (shared ritual, not two solo checks).
| `GET /api/daily-questions` | – | `{questions, poolSize}` — **only the caller's own questions** (the partner must not be able to look authorship up before the reveal); `poolSize` counts the whole couple pool. |
| `POST /api/daily-questions` | `{text (≤240)}`; > 200 pool entries → `413 too_many_questions` | `201 {question, poolSize}`. |
| `DELETE /api/daily-questions/:id` | author only (`403 not_yours`) | `{ok, poolSize}`. |

**Custom days:** roughly every third day (deterministic per couple + dateKey) the daily
question is replaced by one entry of the couple pool — only questions created BEFORE that
day are eligible, so a fresh question never exposes its author on the same day. Every
daily-entry view then carries `customQuestion: {id, text, authorId}`; `authorId` is `null`
for the partner until BOTH answered (the classic reveal — the author always recognizes
their own question). The first answer of a day pins the pick onto the record, so later
pool edits never change an already-asked question. Pre-7.0 clients ignore the field and
keep showing the built-in pack question; custom days only exist once someone on 7.0+
added questions.

## Erinnerungen (v8.0)

Read-only aggregations over existing couple data — no writes, no WS events, no new
storage: the same couple state always produces the same memories on both phones.
Code: `server/src/memories.js`.

| Route | Body / query | Response / rules |
|---|---|---|
| `GET /api/on-this-day?date=YYYY-MM-DD` | `date` optional (default: server-today); malformed or future → `400 bad_date` | `{dateKey, daysTogether, monthiversary, items}` — photos and BOTH-answered dailies from exactly n ≥ 1 whole months back on the **same day-of-month** (no fuzzy matching: Jan 31 has no Feb match). `distance` is `{unit:"months"\|"years", n}` (whole years collapse: 24 months → 2 years). Sorted closest-first, photo before daily on ties, capped at 20. `monthiversary` is the anniversary's whole-month distance (or `null`). |
| `GET /api/story` | – | `{sinceKey, daysTogether, entries}` — the couple's milestone timeline, ascending by date, capped at 300: pairing day, anniversary, firsts (message/photo/video/game/daily/day-memo/capsule/hug/goal), count milestones (photos 10/25/50/…, dailies 10/50/…, messages 100/500/… — message milestones only while nothing rotated out of the 5000 cap), and unlocked badges. Unknown future `kind`s must be rendered generically, not dropped. |

**Honesty contract:** "firsts" are the earliest RETAINED entries — messages (cap 5000),
touches (500) and games (1000) rotate, so a very active couple's literal first message
may be gone; the timeline then simply starts later instead of inventing dates. Half-
answered dailies never appear (the anti-spoiler rule outlives the day itself).

## Nähe trotz Distanz (v9.0)

Presence modes (🎯 focus / 😴 sleep) and thinking-of-you **pulses** — tiny signals with
a haptic signature the partner physically feels. Code: `server/src/presence.js`.

| Route | Body / query | Response / rules |
|---|---|---|
| `PUT /api/presence` | `{mode:"focus"\|"sleep", note?(≤80), minutes?(int 5…720)}` — bad minutes → `400 bad_minutes` | `200 {presence:{mode, note, until, setAt}}`. `minutes` sets `until` (auto-expiry); without it the mode holds until cleared. Overwrites any previous mode. Broadcast `presence_mode {memberId, presence}` to the couple. |
| `DELETE /api/presence` | – | `{ok}` — back to "available" (presence is `null` again). Broadcasts `presence_mode {memberId, presence:null}`. |
| `POST /api/pulses` | `{kind:"thinking"\|"goodnight"\|"heartbeat"\|"hug", clientOperationId?}` — a stable `clientOperationId` (string ≤ 64) makes lost-response retries exactly-once; the dedup runs BEFORE the cooldown check, so a retried ACCEPTED pulse returns the original instead of a misleading 429 | `201 {pulse:{id, kind, senderId, createdAt, feltAt:null}}`; duplicate retry `200 {pulse, duplicate:true}`. One NEW pulse per sender per **30 s** → `429 too_soon`. Relayed live to the **partner only** as `pulse {pulse}` + push; queue capped at 100/couple (oldest dropped). |
| `GET /api/pulses` | – | `{pulses}` — MY unfelt pulses (partner-sent, `feltAt:null`), oldest first. The client replays the newest on launch so missed pulses are FELT, not just read. |
| `POST /api/pulses/seen` | – | `{ok, count}` — marks all my unfelt pulses felt; the sender gets `pulse_felt {memberId, ids}` (the "reached a heart" receipt). |

Presence expiry is **lazy**: no timers — every read (couple serialization included)
treats a passed `until` as cleared, deterministic on both phones and across restarts.
`GET /api/couple` members carry `presence` next to `energy`/`nowPlaying` (`null` when
unset/expired; pre-9.0 clients ignore the field). **Deliberately no XP/app-events**:
presence and pulses must stay a soft signal, not a grind. **Honesty:** an unsigned
sideload build cannot vibrate a killed app — offline pulses buzz on the NEXT app open
(the push banner arrives immediately if notifications are set up).

## Post & Sendungen (FullRelease P6-B)

Sending becomes a little post office: **Zeitpost** (a touch, a pulse or a short note
scheduled 5 min to 7 days ahead, delivered by the server clock), **echo replies**
(send a received touch back once, within 10 minutes, no cooldown) and the shared
**journal** ("Posteingang der Zärtlichkeiten"). Code: `server/src/post.js`.

| Route | Body / query | Response / rules |
|---|---|---|
| `POST /api/post/schedule` | `{kind:"touch"\|"pulse"\|"note", type?, pulseKind?, note?(≤120), deliverAt, clientOperationId?}` — `type` (touch kinds) with `kind:"touch"`, `pulseKind` (pulse kinds) with `kind:"pulse"`, `note` with `kind:"note"`. `deliverAt` is strict RFC-3339/ISO-8601 **with timezone** (`2026-08-18T14:00:00Z` or `…+02:00`; RFC-1123 dates and zone-less local times are refused — R1-C), judged against **server time**, ≥ 5 min (30 s clock-skew grace) and ≤ 7 days ahead, otherwise `400 bad_deliver_at`. Max **5 open posts per person** → `409 post_limit`. The dedup runs BEFORE the `deliverAt` check: a lost-response retry of an ACCEPTED schedule returns the original post even when its lead time has meanwhile slipped — only a schedule the server never saw gets `bad_deliver_at` on replay (the outbox treats that 400 as a giveUp poison pill) | `201 {post}` (ScheduledPost); duplicate retry `200 {post, duplicate:true}`. WS `post_scheduled {post}` → the sender's **other own devices only** — the partner NEVER learns something is pending (surprise contract) |
| `GET /api/post/scheduled` | – | `{posts}` — the caller's OWN open posts, soonest `deliverAt` first. The partner's pending posts are never listed |
| `DELETE /api/post/scheduled/:id` | – | `{ok}`; WS `post_canceled {id}` → sender's other own devices. Unknown ids AND the partner's posts both answer `404 not_found` — a probe cannot tell "not mine" from "not there" |
| `POST /api/touches/:id/echo` | `{clientOperationId?}` — `:id` is a RECEIVED touch. Once per original → `409 echo_taken`; within 10 min of its `createdAt` → otherwise `409 echo_expired`; echoing your OWN touch → `400 invalid_request`. **No cooldown** (the once-per-original rule bounds it harder). Echoing an ECHO → `409 echo_taken` too (R1-C: one bounce per touch — the client never offered a counter-echo anywhere, so ping-pong chains were never reachable; the server now enforces the same truth). Dedup runs BEFORE the window check (a retried ACCEPTED echo returns the original, never `echo_expired`) | `201 {touch}` — a normal touch of the SAME `type` with `echo:true` + `echoOf`; duplicate retry `200 {touch, duplicate:true}`. Travels the normal `touch` fanout (partner + sender's other devices) + push |
| `GET /api/post/journal?limit=` | `limit` 1–300 (default 100) | `{entries}` (PostJournalEntry) — the last **30 days** of touches, pulses and DELIVERED Zeitpost notes of BOTH partners, newest first (ties break on id, deterministic — mirrored by `PostRules.swift`). An echo points at its original via `echoOf` (max one bounce per touch — R1-C); Zeitpost deliveries carry `viaPost:true`. Undelivered scheduled posts are NEVER included |

**Delivery:** a store-wide sweep (default every 30 s, `POST_DELIVERY_INTERVAL_SECONDS`,
`0` disables — same scheduler pattern as the week-review arrival push) turns due posts
into the NORMAL artifact: touches join `couple.touches` + counters, pulses join the
unfelt queue (an offline partner replays them like live ones), notes land in a capped
notes list (200/couple). Fanout on delivery: `touch`/`pulse`/`post_note` frames to
**all devices of both members** (`broadcastCouple` — there is no calling session to
exclude) + one push to the **partner only** (Zeitpost copy; note TEXT stays out of the
banner — lock-screen privacy).

**Delivery guarantee (FullRelease R1-C, honest version):** each delivery is a durable
outbox transition: (1) remove the post from the open list AND mint the artifact under a
**stable, post-derived id** (`t_<postId>` / `pl_<postId>` / `pn_<postId>`) in one
synchronous state change, (2) commit it to the fsynced write-ahead journal
(`store.markDirty()`), (3) only THEN WS fanout + push. The artifact is therefore
**exactly-once**: a crash before the commit leaves the post open and the sweep
re-attempts the whole delivery after restart; if a re-sweep ever finds the stable
artifact id already minted, it only redoes the fanout — never a duplicate artifact or
double counter bump. The notification is **at-least-once** in that crash-retry case
(the partner may see the same delivery pushed twice). One accepted gap: a crash AFTER
the commit but BEFORE the push loses that one push/WS fanout — the artifact is durable
and every device converges via its normal fetches (journal, `/api/touches/recent`,
`/api/pulses`) on the next app open. Open posts persist in the couple's store segment —
restart-safe by construction.

**New touch kinds (P6-B):** `stolz` ("Stolz auf dich" ⭐) and `haltedurch` ("Halt
durch" ✊) are first-class `TOUCH_TYPES` everywhere (`POST /api/touches`, schedule,
echo, stats). Old clients must tolerate unknown kinds in the fanout and in
`GET /api/touches/recent` (skip the entry, keep the list).

## WebSocket

`GET /ws` with `Authorization: Bearer <token>` (WS in either HTTP mode, WSS behind HTTPS). Frames are JSON: `{ "type": "<event>", "payload": { … }, "ts": "<ISO>" }` — member-caused frames additionally carry a top-level `"origin": { "memberId", "deviceId", "sessionSuffix" }` marker (see [Multi-device](#multi-device-sessions--fanout); old clients ignore the unknown field, payload shapes are unchanged).

- On connect the server sends `welcome {memberId, coupleId, partnerOnline}` and broadcasts `presence {memberId, online:true}` to the partner. On last socket close: `presence {memberId, online:false, lastSeenAt}`.
- Server→client event types: `welcome, presence, touch, message, message_updated, message_deleted, message_read, member_updated, couple_updated, couple_dissolved, partner_joined, partner_rejoined, partner_replaced, daily_answer, wordle_result, canvas_stroke, canvas_stroke_deleted, canvas_clear, photo_added, photo_updated, photo_deleted, video_added, video_updated, video_deleted, vault_config_set, vault_item_added, vault_item_deleted, vault_reset, haptic, haptic_pattern_added, haptic_pattern_updated, haptic_pattern_deleted, event_added, event_updated, event_deleted, bucket_added, bucket_updated, bucket_deleted, coupon_added, coupon_redeemed, coupon_deleted, song_added, song_updated, song_deleted, game_created, game_started, game_move, game_ended, checkin, list_added, list_updated, list_deleted, hug_queued, hug_opened, potd_submitted, now_playing, typing, pong` — plus v3.0 rituals: `daymemo, capsule_sealed, capsule_opened, capsule_deleted, need, need_acked, goal_added, goal_updated, goal_deleted, weekplan_availability, weekplan_slot_added, weekplan_slot_updated, weekplan_slot_deleted, energy, magazine_seen, app_event`. `daymemo` and `capsule_sealed` send **per-member tailored** frames (anti-spoiler applies, like `daily_answer`). Plus v3.0 level & platform (Agent C): `level_up, badge_unlocked, quest_completed, icon_gift, icon_gift_opened, duet_start, datenight_update, heartbeat_tap` — `icon_gift` goes to the recipient only, `icon_gift_opened` to the sender only. Plus v4.8 support: `repair_changed, consideration_changed`. Plus v5.0 warmth: `goodthings` (**per-member tailored**, anti-spoiler), `thanks, missyou, missyou_ack, dictionary_changed, dictionary_deleted, first_changed, first_deleted`; seasonal calendars add per-member-tailored `season_calendar_changed`. Plus v7.0 „Eure Woche": per-member-tailored `week_highlight` (full review view, anti-spoiler) and broadcast `week_review_seen {week, seen}`. Plus v9.0 „Nähe trotz Distanz": `presence_mode {memberId, presence}` (couple broadcast), `pulse {pulse}` (**partner only**), `pulse_felt {memberId, ids}` (**partner only** — the sender's felt receipt). Plus FullRelease P6-B „Post & Sendungen": `post_scheduled {post}` and `post_canceled {id}` (**sender's other own devices only** — the partner must never learn a delivery is pending), `post_note {note}` (couple broadcast on Zeitpost note delivery; delivered touches/pulses reuse the normal `touch`/`pulse` frames with `viaPost:true`, sent to ALL devices of both members since the sweep has no calling session). Plus multi-device: `device_linked {memberId, sessionId, deviceId, deviceName, linkedAt}` → **all of the linking member's own devices only** (the partner is not notified; device management is a per-member concern), and the generic session-lifecycle frame `sessions_changed {memberId, reason, sessionId, deviceName}` → **all devices of the AFFECTED member only** with `reason` exactly one of `"linked" | "rejoined" | "replaced" | "rotated" | "revoked"` — sent on device link (in addition to `device_linked`), rejoin (recovery key / token / admin QR), partner replace (one `revoked` per cut-off session, then `replaced` for the fresh one), session rotate (`sessionId` names the successor), and revoke (single and revoke-all, incl. admin). Clients refresh their device manager (`GET /api/sessions`) on any `sessions_changed`.
- **Terminal close code `4001`:** sockets of a rotated/revoked session are closed with WS code `4001` — the ONLY close code that means "this session is dead for good: forget the bearer, do NOT reconnect" (rejoin/relink instead). Every other close (network, server restart, idle timeout, `1000` on couple dissolve) may be retried with backoff. The `sessions_changed` frame is sent BEFORE the `4001` close, so the dying device learns why.
- Client→server: `{"type":"ping"}` → `pong`; `{"type":"typing","payload":{"isTyping":true}}` → forwarded to partner as `typing {memberId, isTyping}`; `{"type":"heartbeat_tap","payload":{"intensity":0..1}}` → relayed to the **partner** as `heartbeat_tap {memberId, intensity}` (live heartbeat on the 3D heart, v3.0 Agent C); `{"type":"canvas_live","payload":{phase, color, width, tool, points}}` → relayed to the **partner** as `canvas_live {memberId, phase, color, width, tool, points, generation}` (ephemeral live co-drawing on the shared canvas; `phase` is `hello`/`draw`/`end`/`bye`, `points` capped at 400 pairs, never persisted — the committed stroke still arrives via `POST /api/canvas/strokes`, which converges all devices; `generation` is the CURRENT board generation stamped by the server, so receivers drop live ink that raced a clear — sync contract f). All three relayed frames carry the sending socket's `origin`, so a partner typing/drawing on two devices at once can be tracked per device.
- Clock sync (v3.0, for the haptic duet): `ping` accepts an optional `{"payload":{"echo":"<id>"}}`; the `pong` echoes it back as `{echo}` and every frame carries the server-time `ts` — an NTP-light offset estimate (`ios/SoooDreamy/Core/ClockSync.swift` keeps the best-RTT sample).
- REST-triggered broadcasts go to **all sockets of the couple** (sender's other devices included). `touch` and `haptic` are relayed to the **partner** plus — multi-device — to the sender's **other own devices** (the calling session is excluded: that device already rendered the action locally). `typing` stays **partner only** (an own second device has no use for a "you are typing" echo). `daily_answer` sends a per-member tailored `DailyEntry`; `wordle_result` sends a per-member tailored Wordle day view (anti-spoiler applies).
- Server pings sockets every 30 s and terminates dead ones. A member is `online` if they have ≥ 1 open socket. Upgrades are rate-limited and connections are capped globally/per IP/per session/per member; frames are limited to 64 KiB and excessive buffered backpressure closes the socket.

## Multi-device sessions & fanout

One member, several devices (iPhone + iPad + …) on the same "account": sessions were
always per device (cap 8 per member, each with its own bearer, WS sockets, and push
registration) — this section defines the semantics that make simultaneous devices
first-class.

### Presence & fanout semantics

- **Presence is member-level:** `online` means "≥ 1 open socket on ANY device". The
  `presence {memberId, online}` frame fires only on the FIRST socket opening / the LAST
  socket closing; it carries no `origin` (which device did it is irrelevant).
- **Fanout audit** (who receives what, per frame family):

| Frames | Partner devices | Sender's OTHER devices | Sender's calling session |
|---|---|---|---|
| default REST broadcasts (`message`, `photo_added`, `game_move`, `app_event`, …) | ✓ | ✓ | ✓ (idempotent — clients reconcile by entity id) |
| `touch`, `haptic` | ✓ | ✓ (multi-device self-echo) | – (already rendered locally) |
| `typing` (WS relay) | ✓ | – (no use for a "you are typing" echo) | – |
| `heartbeat_tap`, `canvas_live` (WS relays) | ✓ | – (ephemeral; committed canvas strokes converge via `canvas_stroke`) | – |
| `pulse` / `icon_gift` | recipient's devices only | – (no sent-pulse surface; `pulse_felt` / `icon_gift_opened` return to ALL sender devices) | – / – |
| `daily_answer`, `wordle_result`, `daymemo`, `goodthings`, `week_highlight`, `capsule_sealed`, `season_calendar_changed` | per-member **tailored** frame to every device of each member (anti-spoiler applies per member, not per device) | ✓ (same tailored frame) | ✓ |
| `partner_rejoined` / `partner_replaced` | ✓ (partner only) | – (own devices see the change in `GET /api/sessions`) | n/a (unauthenticated flow) |
| `device_linked` | – | ✓ (all of the member's devices) | n/a (the new device has no socket yet) |
| `sessions_changed` (link/rejoin/replace/rotate/revoke) | – (device management is a per-member concern) | ✓ (all of the AFFECTED member's devices — the open device manager refreshes live) | ✓ where a socket exists (rotate/revoke: the frame lands BEFORE the `4001` close) |
| `game_lease` (input lease, Welle 6) | – (which of my devices drives is not the partner's business) | ✓ (spectator banner flips) | ✓ (idempotent confirmation — same frame as the siblings) |

### The `origin` frame marker

Every broadcast caused by an authenticated REST request — and the relayed client frames
`typing`/`heartbeat_tap`/`canvas_live` — carries a top-level frame field:

```jsonc
{ "type": "touch", "payload": { … }, "ts": "…",
  "origin": { "memberId": "m_…", "deviceId": "device_…", "sessionSuffix": "1a2b3c4d" } }
```

- `memberId`/`deviceId` identify who acted on which device (device ids are already
  couple-visible concepts; they are the pairing-time client identifiers, not secrets).
- `sessionSuffix` is the LAST 8 characters of the acting session id — enough for a client
  to recognize "this is me" (it knows its own `sessionId` from the pairing response),
  useless for anything else. Frames never contain tokens or digests.
- Clients use `origin` to (a) drop/de-dupe their own echoes (`origin.sessionSuffix ==`
  own suffix), (b) attribute partner events per device (e.g. per-device typing state),
  and (c) reconcile optimistic UI. System frames (`welcome`, `pong`, `presence`,
  scheduler-driven pushes) carry no `origin`. Old clients ignore the field.

### Linking a second own device (link codes)

Self-service flow — no recovery-key ceremony, no partner approval, the recovery key is
NOT rotated (it stays valid on the first device):

```text
iPhone (signed in)                        Server                      iPad (new)
  │ POST /api/sessions/link-code?format=qr │                             │
  │──────────────────────────────────────▶│ mint 8-char code, 10-min    │
  │ 201 {linkCode, expiresAt, deepLink,    │ TTL, single-use, stored as  │
  │      svg, server}                      │ SHA-256 digest              │
  │◀──────────────────────────────────────│                             │
  │ shows QR / code                        │      POST /api/couples/link │
  │                                        │◀────{code, deviceName}──────│
  │                                        │ same member, fresh session  │
  │   WS device_linked {deviceName, …}     │────{token, sessionId, …}───▶│
  │◀──────────────────────────────────────│                             │
  │ GET /api/sessions now lists the iPad   │        iPad connects /ws    │
```

- **QR payload:** the deep link `sooodreamy://link?server=<url-encoded base URL>&code=<code>`
  (rendered as `svg` by the server when `?format=qr` is requested — same `qrcode`
  machinery as the admin rejoin QR). Manual entry uses the 8-char code (alphabet
  `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`, case-insensitive).
- **Lifecycle:** issuing a new code replaces the member's previous unconsumed one; codes
  die on use, after 10 minutes, on partner replace and admin revoke-all (any
  "cut off this member's devices" intent), and with the couple.
- **Cap:** the 8-sessions-per-member ceiling is enforced with an honest
  `413 too_many_sessions` on BOTH issue and redeem (the code is not burned by a cap
  failure); ceiling evictions elsewhere prefer retained dead records over live sessions.
- The new session is a completely normal device session afterwards: it registers its own
  push device, shows up in `GET /api/sessions` (and the admin panel), and can be revoked
  individually.

## Pairing recovery (v6.1)

A full couple must never become permanently unjoinable. When a device loses its
session (app reinstall, new phone, expired token), the member re-attaches to
their OWN slot via `POST /api/couples/rejoin` with one of three proofs, in
descending strength:

1. **Recovery key** (`{code, recoveryKey}`) — every pairing response returns a
   one-time `recoveryKey` (`rec_…`); the app keeps it in the (iCloud) keychain
   so it survives reinstalls. Legacy members call `POST /api/recovery-key`
   once after updating. The server stores only a SHA-256 digest.
2. **Recent bearer** (`{token}`) — an active session or one expired no more
   than 24 hours ago proves the device owned the slot. After that grace the
   record is permanently discarded; use the recovery key. Deliberately
   **revoked** sessions are refused (`403 session_revoked`).
3. **Replace code** (`{code, replaceCode}`) — the remaining partner explicitly
   approves a device replacement via `POST /api/couples/replace-partner`
   (single-use, 15-minute TTL). Using it revokes every old session, push
   registration and the old recovery key of the replaced slot; the member id
   and all shared history stay.

Rejoin never creates a third member, never resets history, and notifies the
partner (`partner_rejoined` / `partner_replaced`). The member's OWN other
devices additionally receive `sessions_changed` frames (sync contract d:
`reason:"rejoined"` for recovery/token proofs; for a replace, one
`reason:"revoked"` per cut-off old session — whose sockets then close with
code `4001` — followed by `reason:"replaced"` for the fresh session).
Genuine third parties still get `409 couple_full` on `/api/couples/join`.
Recovery digests and pending replace codes never leave the server (they are
stripped from migration exports, `GET /api/couple`, and every member
serialization).

## Admin panel (v10.1)

The server process also serves an operator web panel at `GET /admin` (SPA, vanilla JS/CSS from `server/src/admin/public/`). Full guide: [`../../docs/ADMIN-PANEL.md`](../../docs/ADMIN-PANEL.md).

- **Auth**: `POST /admin/api/login {password}` with the per-boot console password (4 words from a 256-word list, printed only to the console, never persisted — the server keeps a SHA-256 digest in memory). Success sets an httpOnly `SameSite=Lax` cookie (`sooodreamy_admin`, `Path=/admin`, `Secure` over HTTPS); the session lives in memory with a 12 h sliding TTL and dies with the process. Login is rate-limited (10/IP and 100 global per 15 min → `429 rate_limited`). Wrong password → `403 admin_bad_password`. Every other `/admin/api/*` route requires the cookie (`401 admin_unauthorized`); state-changing browser requests that carry `Origin` verify it against the request host (`403 admin_bad_origin`), while `SameSite=Lax` is the primary browser-CSRF boundary.
- **Routes** (all JSON): `POST /admin/api/logout`, `GET /admin/api/me`, `GET /admin/api/state` (server stats incl. storage + latest backup, all couples with members/online/last-active/app-versions/data-counts/segment-bytes/health `ok|recovered`, plus fully `quarantined` couples), `GET /admin/api/couples/:coupleId/sessions` (device sessions with `live` flag and `kind: device|adminQr`), `POST /admin/api/couples/:coupleId/invite-code/reset` → `{code}`, `POST …/members/:memberId/recovery-key/reset` → `{recoveryKey}`, `POST …/members/:memberId/replace-code/reset` → `{replaceCode}` (each reset invalidates all previous codes of that kind), `POST /admin/api/sessions/:sessionId/revoke` and `POST …/members/:memberId/sessions/revoke-all` (immediate: WebSockets closed, push registrations removed, token → 401), `GET|POST /admin/api/backups` (list / "backup now" with rotation), `GET /admin/api/logs` (last 200 log lines), `GET /admin/api/audit` (last 200 audit entries).
- **Login QR**: `POST /admin/api/couples/:coupleId/members/:memberId/rejoin-qr {server?}` creates a random 30-minute, single-use nonce fixed to that member slot and returns `{deepLink, svg, server, expiresAt, nonceId, memberId}`. The nonce is never a bearer token; `POST /api/couples/rejoin {token}` atomically checks expiry/use and consumes it before issuing a normal session. Replay and expired QR proofs fail. `server` defaults to the panel's own base URL and can be overridden with any http(s) URL.
- **Audit**: every admin action is appended as JSONL to `DATA_DIR/admin-audit.log` (`at`, `action`, `ip`, context ids — never the secrets themselves). The file rotates daily or at 5 MiB and retains 30 rotated files by default (`AUDIT_MAX_BYTES`, `AUDIT_RETENTION_FILES`).

## Error code catalog

Every error response is `{ "error": "<code>", "message": "<text>" }` (plus a structured
`details` object on the few codes that document one). This section is the authoritative
list of all codes the server emits — the iOS client builds its error mapping from this table. Rules of thumb:

- **400** — the request itself is malformed. Retrying unchanged will fail again; fix the payload (usually a client bug or stale app version).
- **401** — credentials are missing/dead. Re-authenticate (rejoin flow) or, for the admin panel, log in again.
- **403** — authenticated, but this actor may not do that. Not retryable.
- **404** — the route or entity does not exist (anymore). Refresh local state.
- **409** — the request is well-formed but conflicts with current state (wrong turn, already done, week closed …). Refresh state, then decide.
- **413** — a size/quota cap. Delete something or shrink the payload.
- **426 / upgrade** — transport policy, see code.
- **429** — throttled. With `retry-after`: wait that many seconds. Without: a capacity cap, free a slot.
- **5xx** — server-side condition; safe to retry later. `couple_data_quarantined` and `disk_full` need operator action.

### 400 — malformed request

| Code | Where / meaning |
| --- | --- |
| `album_too_long` | `PATCH /api/photos/:id` — album name exceeds the length cap. |
| `bad_apns_token` | `POST /api/push/register` — device token is not 32–200 hex chars. |
| `bad_bundle_id` | `POST /api/push/register` — bundle id malformed. |
| `bad_ciphertext` | Vault / consideration hints — ciphertext must be a non-empty base64 envelope. |
| `bad_color` | Member color is not a `#RRGGBB` hex color. |
| `bad_date` | A calendar date is not `YYYY-MM-DD` (events, anniversary, …). |
| `bad_datekey` | `dateKey` is not `YYYY-MM-DD` or outside the allowed window (daily, wordle, day-bound games). |
| `bad_deliver_at` | `POST /api/post/schedule` — `deliverAt` is not a strict RFC-3339/ISO-8601 timestamp **with timezone** (RFC-1123 and zone-less local times are refused — R1-C), less than 5 min (minus 30 s grace) or more than 7 days ahead. On outbox replay of a never-accepted schedule: giveUp poison pill (do not retry). |
| `bad_door`, `bad_doors` | Countdown calendar — door entry / door list malformed. |
| `bad_emoji` | Value is not a single emoji (mood, reactions, hug kinds …). |
| `bad_expiry` | Coupon `expiresAt` is not ISO-8601 or `null`. |
| `bad_hours` | Consideration timer `hours` outside 1–72. |
| `bad_items` | Gratitude `items` is not an array of 1–3 entries. |
| `bad_iterations` | Vault KDF `iterations` outside 10k–10M. |
| `bad_lang` | `lang` is not `de` or `en`. |
| `bad_level` | Signal/hug `level` is not 1, 2 or 3. |
| `bad_minutes` | A `minutes` field is outside its range (repair pause, presence session). |
| `bad_month` | `month` is not `YYYY-MM` (magazine additionally rejects future months). |
| `bad_palette` | Couple palette is not an object or `null`. |
| `bad_payload` | Countdown calendar door payload missing/malformed. |
| `bad_photo` | `photoId` missing or not a string. |
| `bad_request` | Request body could not be read. |
| `bad_server_url` | Admin rejoin-QR / device-link QR `server` override is not an http(s) URL. |
| `bad_since` | `since` query param missing or not ISO-8601. |
| `bad_slot` | Week-plan slot needs exactly one of `dateKey` / `weekday` (0–6). |
| `bad_sticker` | Sticker is not a procedural recipe object. |
| `bad_text` | A required text field is missing or has the wrong type. |
| `bad_time` | `time` is not an `HH:MM` 24-hour string. |
| `bad_timezone` | `PATCH /api/couple` — `timezone` is not a valid IANA zone id. |
| `bad_title` | Title missing or too long. |
| `bad_unlock` | `unlockAt` is not ISO-8601 or not in the future. |
| `bad_value` | A numeric field is out of range (goals, savings amounts, …). |
| `bad_week` | `week` is not a `YYYY-Www` ISO week key. |
| `empty_body` | Required JSON body missing or empty. |
| `invalid_date` | Event date malformed. |
| `invalid_game_move` | Game move fails the type-specific shape/rule check (see `message`). |
| `invalid_json` | Body is not parseable JSON. |
| `invalid_migration` | Migration bundle malformed. |
| `invalid_pattern` | Haptic pattern malformed. |
| `invalid_points` | Canvas stroke points malformed. |
| `invalid_request` | Generic field validation failure (see `message`). |
| `invalid_type` | Unsupported enum value (game type, message type, …). |
| `low_contrast` | Palette accent fails the 4.5:1 contrast requirement. |
| `migration_confirmation_required` | Import needs `confirm:true`. |
| `migration_digest_mismatch` | Migration bundle checksum mismatch. |
| `missing_proof` | Pairing recovery lacks a `recoveryKey`/`replaceCode` proof. |
| `not_editable` | Only text and letter messages can be edited. |
| `openwhen_too_long` | Sealed-letter `openWhen` label too long. |
| `pattern_too_long` | Haptic pattern exceeds the limits. |
| `plaintext_forbidden` | Endpoint accepts only device-encrypted content (vault, consideration hints). |
| `query_token_forbidden` | Bearer token sent as query param — use the `Authorization` header. |
| `too_long` | A text exceeds its cap. |
| `too_many_points` | Canvas stroke has too many points. |
| `unknown_source_member` | Migration import references a member not contained in the bundle. |

### 401 — authenticate (again)

| Code | Where / meaning |
| --- | --- |
| `invalid_token` | Bearer token unknown, expired, or couple dissolved — run the rejoin flow. |
| `admin_unauthorized` | Admin panel cookie missing or expired — log in again. |

### 403 — forbidden for this actor

| Code | Where / meaning |
| --- | --- |
| `admin_bad_origin` | Admin panel: `Origin` header does not match the request host. |
| `admin_bad_password` | Admin panel login: wrong console password. |
| `bad_link_code` | Device link: the code is unknown (codes are 8 chars, case-insensitive). |
| `bad_recovery_key` | Pairing recovery: recovery key does not match. |
| `bad_replace_code` | Pairing recovery: replace code does not match. |
| `link_code_expired` | Device link: the code's 10-minute TTL ran out — mint a new one on the signed-in device. |
| `not_for_you` | Countdown calendar: only the recipient can open this door. |
| `not_revealed` | Voice memo: record your own memo for this day first. |
| `not_yours` | The resource belongs to the partner or another couple. |
| `qr_expired` | Admin login QR nonce expired before it was redeemed — ask the operator for a new QR. |
| `session_expired` | Rejoin bearer expired beyond the 24-hour grace — use the separate recovery key or a replace code. |
| `session_revoked` | This device session was revoked — ask the partner for a replace code. |
| `unknown_session` | Rejoin token was never issued by this server. |
| `wrong_actor` | Game/ritual action reserved for the other member (artist, teller, subject …). |

### 404 — not found

| Code | Where / meaning |
| --- | --- |
| `not_found` | Generic: unknown route or unknown entity id. |
| `no_datenight` | No date night is planned. |
| `no_gift` | No pending icon gift. |
| `no_thumb` | This photo/video has no thumbnail. |
| `photo_not_found` | Referenced `photoId` does not exist in the couple gallery. |
| `unknown_code` | No couple with this invite code. |
| `unknown_couple` | Admin panel / QR rejoin / device link: the couple (or member slot) no longer exists. |
| `unknown_member` | Member id does not exist. |
| `unknown_photo` | Photo id does not exist. |

### 409 — state conflict (refresh, then decide)

| Code | Where / meaning |
| --- | --- |
| `already_acked` | Signal/need was already answered. |
| `already_completed` | Repair conversation already complete. |
| `already_confirmed` | Definition already confirmed. |
| `already_matched` | Photo memory: matched tiles cannot be flipped again. |
| `already_opened` | Sealed letter / calendar already opened. |
| `already_redeemed` | Coupon already redeemed. |
| `auto_checked_only` | Bingo tiles are checked only by validated app events, never by direct moves. |
| `capture_required` | Dame: a capture is available and must be taken (or the jump sequence must continue). |
| `column_full` | Connect Four: that column is full. |
| `conflict` | Optimistic-concurrency mismatch (sync contract e): the request's `ifRev` is not the resource's current `rev` — the response carries the winning resource as `current`; merge and retry with its `rev`. Calendar events and shared lists. |
| `cooldown_active` | Repair: the shared cooldown is still active. |
| `couple_full` | Join: this couple already has two members. |
| `daily_revealed` | Both daily answers were revealed and are now immutable. |
| `door_still_locked` | Countdown calendar: door not yet unlockable. |
| `duplicate_move` | This member already made that move / the slot is taken. |
| `echo_expired` | `POST /api/touches/:id/echo` — the 10-minute echo window has closed. Not retryable. |
| `echo_taken` | `POST /api/touches/:id/echo` — this touch was already sent back once (max 1 echo per original), OR the touch is itself an echo (R1-C: one bounce per touch, no chains). Not retryable. |
| `empty_pit` | Mancala: sowing from an empty pit. |
| `expired` | Coupon has expired. |
| `game_complete` | All rounds/board complete — no more moves. |
| `game_ended` | This game already ended. |
| `game_in_progress` | An open session of this type already exists. |
| `game_incomplete` | `POST /api/games/:id/end` without `forfeit` — server-derived state is not complete. |
| `game_lease_held` | Another device of THIS member drives the session (input lease); carries `details: {gameId, lease}` with the holder — take over via `POST /api/games/:id/takeover`. |
| `game_not_active` | Moves are only allowed in an active game. |
| `invalid_fleet` | Battleship: revealed fleet layout is invalid. |
| `invalid_quest` | Daily quests: that quest is not part of this day. |
| `invalid_word` | Duo Wordle/Hangman: revealed word does not match the sealed commitment. |
| `link_code_consumed` | Device link codes are single-use; this one was already redeemed. |
| `migration_destination_not_empty` | Import refused: destination server already has data. |
| `no_flip` | Reversi: a placement must flip at least one disc. |
| `no_partner` | Action requires a partner in the couple (invite still open). |
| `no_realtime_actions` | 36 Questions has no server game actions. |
| `not_enough_photos` | Photo memory requires 2–8 gallery photos. |
| `partner_required` | This game requires exactly two members. |
| `pass_not_allowed` | Reversi: passing is only allowed without a legal placement. |
| `post_limit` | `POST /api/post/schedule` — at most 5 open scheduled posts per person; deliver or cancel one first. |
| `qr_consumed` | Admin login QR nonce was already redeemed; QR proofs are single-use. |
| `replace_target_missing` | Pairing replace: the member slot no longer exists. |
| `replace_already_pending` | A partner-replacement code is already pending; concurrent replacement lost the CAS. |
| `reveal_mismatch` | Commit-reveal: reveal does not match this member's commitment. |
| `roll_quota` | Kniffel: a turn allows at most three rolls. |
| `daily_question_mismatch` | `POST /api/daily/:dateKey`: the day's question is already pinned by the first answer and the submitted `questionId` differs (pool-growth race between devices) — `details.questionId` carries the authoritative id and `details.questionText` the stored `{de, en}` text (null when the pinning client sent none); re-render the pinned question and resubmit. The refused `clientOperationId` is NOT remembered (a retry stays refused instead of turning `duplicate:true`), and the `message` is actionable on purpose: clients too old to adopt the details surface it raw as their update guidance — a deliberate trade-off, since silently re-filing the answer under the pinned question (the pre-fix behavior) corrupted the couple's reveal. |
| `stale_generation` | `POST /api/canvas/strokes` (sync contract f): the stroke's `generation` predates a clear — the response carries the current `generation`; drop the retry instead of resurrecting dead ink. |
| `unknown_word` | Wordchain: word not in the validated dictionary. |
| `unsupported_migration` | Migration bundle from an unsupported version. |
| `vault_locked_in` | Vault already configured — reset before changing the key. |
| `vault_not_configured` | Set the vault key first (`PUT /api/vault/config`). |
| `week_closed` | Highlights only for the current or previous week. |
| `week_not_over` | A week can be marked read once it is over. |
| `wrong_card` | Movie roulette: not the next card index. |
| `wrong_letter` | Wordchain: word must start with the required letter. |
| `wrong_phase` | Game/ritual is in a different phase than this action expects. |
| `wrong_round` | Move targets a round other than the active one. |
| `wrong_step` | Repair flow: a different step kind is expected. |
| `wrong_turn` | It is the other member's turn. |

### 413 — too large / quota

| Code | Where / meaning |
| --- | --- |
| `too_large` | Request body exceeds the byte limit. |
| `game_move_quota` | A game stores at most its per-game move cap. |
| `too_many_contributions` | Savings goal contribution cap reached. |
| `too_many_goals` | Goal cap per couple reached. |
| `too_many_items` | List/collection item cap reached. |
| `too_many_lists` | Shared list cap reached. |
| `too_many_patterns` | Haptic pattern cap reached. |
| `too_many_photos` | Photo cap per couple reached. |
| `too_many_questions` | Custom daily question cap reached. |
| `too_many_sessions` | Device link: the member already has 8 active device sessions — revoke one first. |
| `too_many_slots` | Week-plan slot cap reached. |
| `too_many_videos` | Video cap per couple reached. |

### 426 / 429 — transport & throttling

| Code | Status | Where / meaning |
| --- | --- | --- |
| `https_required` | 426 | HTTP/WS rejected by `REQUIRE_HTTPS=1`, or a non-private source attempted the `ALLOW_HTTP_PRIVATE_LAN=1` mode. |
| `rate_limited` | 429 | Per-IP/global request limiter. Has `retry-after`. |
| `effect_cooldown` | 429 | Message effects have a per-member cooldown. Has `retry-after`. |
| `too_soon` | 429 | Presence pulse: one per 30 s. Has `retry-after`. |
| `too_many_open_games` | 429 | Open-games cap — finish or end a game (no `retry-after`). |
| `too_many_firsts` | 429 | Firsts cap — delete one before adding (no `retry-after`). |

### 5xx — server side

| Code | Status | Where / meaning |
| --- | --- | --- |
| `internal_error` | 500 | Unhandled server error (logged server-side). Safe to retry later. |
| `couple_data_quarantined` | 503 | This couple's data segment failed integrity checks and was quarantined — operator must restore from backup. REST **and** WS. |
| `server_capacity` | 503 | Configured couple quota (`MAX_COUPLES`) reached. |
| `disk_full` | 507 | Media upload refused: server disk is below its reserve. Existing data is safe; operator must free space. |
| `media_quota_exceeded` | 507 | Media upload would exceed `MEDIA_QUOTA_BYTES`; remove media or increase the operator-configured quota. |

## Storage & runtime

- Plain Node.js ≥ 20, npm dependencies: `ws` + `qrcode` (admin login-QR and device-link QR rendering). Entry: `server/src/server.js` (`npm start`), app factory `createApp()` in `server/src/app.js` (used by tests; `PORT=0` for ephemeral).
- Env: `PORT` (default `4321`), `HOST` (default `0.0.0.0`), `DATA_DIR` (default `server/data`). Transport precedence: `REQUIRE_HTTPS=1` is strict; otherwise `ALLOW_HTTP_PRIVATE_LAN=1` restricts HTTP to private sources; with neither, HTTP is allowed by default for the intended trusted private setup. `TRUST_PROXY=1` honors `X-Forwarded-Proto` only behind a trusted proxy. `MAX_COUPLES` defaults to 10,000. Backup rotation: `BACKUP_INTERVAL_MINUTES` (default 60, `0` disables), `BACKUP_KEEP_LAST`/`BACKUP_KEEP_HOURLY`/`BACKUP_KEEP_DAILY` (10/48/14); media is included by default and `BACKUP_INCLUDE_MEDIA=0` is the explicit metadata-only opt-out — see [`BACKUP.md`](BACKUP.md).
- Persistence: every acknowledged mutation first appends a checksummed snapshot delta to `DATA_DIR/store.wal` and `fsync`s both the journal file and parent directory before the 2xx response. The ~500 ms debounce only compacts into checksummed per-couple `segments/*.json` plus `store.json`. One process-wide exclusive `DATA_DIR` lock prevents double writers and also coordinates restore/migration/CLI backup. Media files live under `DATA_DIR/media/`; file writes and atomic renames also sync the file and parent directory.
- Corruption hardening (v6.1): segments are SHA-256 checksum envelopes (`{format:"segment-v2", sha256, couple}`); every atomic write keeps the previous good generation as `<file>.bak` and loads fall back to it automatically; unrecoverable files are moved to `DATA_DIR/quarantine/` (never deleted, never crash the boot) and clients of a quarantined couple receive an honest `503 couple_data_quarantined` (REST **and** WS) instead of a misleading 401; a lost manifest is rebuilt from the segment files (sessions are gone then — members re-attach via `/api/couples/rejoin`).
- Operator tooling: stop the server before external `npm run backup`, restore, or migration; the shared `DATA_DIR` lock refuses a live race. Commands: `npm run backup` / `npm run restore -- --list|--verify <id>|--restore <id>` and `npm run migrate [-- --dry-run]`.
- Backward compatibility: any pre-2.0 `store.json` loads without migration — missing structures (`moodHistory`, `wordle`, `coupons`, `songs`, `thumbUrl`, `favorites`, `openWhen`, `reactions`, `album`, `expiresAt`, `lastReadAt`, `photoId`, `editedAt`, and the v2.0 buckets `videos`, `vault`, `hapticPatterns`, `checkins`, `lists`, `hugs`, `potd`, `nowPlaying`) are defaulted lazily on read (`null`/empty). v1.2.0 wordle day buckets (`{memberId: WordleResult}`) are normalized lazily to the per-language shape (`{lang: {memberId: WordleResult}}`) when a day is accessed, using each stored result's own `lang`.
- CORS: permissive (`*`) — the server is self-hosted for exactly one couple (or a few friends).
- Streak: number of consecutive days ending today (or yesterday if today unanswered) where **both** members answered the daily question.
