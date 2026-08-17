import { createReadStream } from 'node:fs';
import { stat } from 'node:fs/promises';
import {
  HttpError,
  httpError,
  id,
  newToken,
  newCoupleCode,
  nowIso,
  todayKey,
  prevDateKey,
  nextDateKey,
  isValidDateKey,
  daysBetween,
  sendJson,
  readBody,
  readJsonObject,
  sha256Hex,
  newSeed,
} from './util.js';
import { emitAppEvent } from './events.js';
import { listBackups } from './backup.js';
import { registerRitualRoutes, freshEnergy, needsOf, topGoalView, deleteRitualMedia } from './rituals.js';
import { registerWeekReviewRoutes, weekHighlightsForYear } from './weekreview.js';
import {
  registerDailyQuestionRoutes,
  snapshotCustomQuestion,
  customQuestionView,
} from './dailyquestions.js';
import { registerMemoryRoutes } from './memories.js';
import { registerPresenceRoutes, freshPresence } from './presence.js';
import { registerPostRoutes } from './post.js';
import { registerWarmthRoutes } from './warmth.js';
import { registerRepairRoutes } from './repair.js';
import { registerSeasonalRoutes } from './seasonal.js';
import { registerMigrationRoutes } from './migration.js';
import { registerPairingRoutes, issueRecoveryKey } from './pairing.js';
import { registerGamificationRoutes, levelSnapshot, maybeAdvanceGamification } from './gamification.js';
import { registerPlatformRoutes } from './platform.js';
import { aggregateSeason } from './season.js';
import { allMessagesOf, archiveMessageOverflow } from './message-archive.js';
import {
  authenticateToken,
  createSession,
  invalidateLinkCodes,
  isSessionLive,
  requestKey,
  requireSecureTransport,
  revokeSession,
  rotateSession,
  sessionOrigin,
  sessionView,
} from './security.js';
import {
  blockingGameLease,
  canonicalGameResult,
  claimGameLease,
  ensureGamesAggregate,
  finalizeGamePayload,
  forfeitResult,
  GAME_TYPES,
  gameLeaseView,
  gameLeasesView,
  gamePayloadView,
  gameTurnMemberId,
  GAMES_LIST_LIMIT,
  isPlayedGame,
  prepareGamePayload,
  recordGameEnd,
  takeoverGameLease,
  validateGameMove,
} from './game-rules.js';
import { CURRENT_GAME_RULES_VERSION } from './game-migrations.js';

// 'stolz' + 'haltedurch' are FullRelease P6-B additions — old clients ignore
// unknown kinds in the fanout (lossy touch decoding on the client side).
const TOUCH_TYPES = ['heartbeat', 'kiss', 'hug', 'missyou', 'tickle', 'thinking', 'stolz', 'haltedurch'];
const MESSAGE_TYPES = ['text', 'letter', 'photo', 'sticker'];
// Chat send-effects play fullscreen ONCE on the partner's device,
// then a subtle badge on the bubble. 'invisible' = scratch-to-reveal ink.
const MESSAGE_EFFECTS = ['hearts', 'snow', 'sparkle', 'fireworks', 'slam', 'invisible'];
const MESSAGE_EFFECT_COOLDOWN_MS = 12_000;
const STICKER_SHAPES = ['heart', 'cloud', 'burst', 'seal'];
const MONOGRAM_STYLES = ['seal', 'ribbon', 'minimal'];
const WORDLE_LANGS = ['de', 'en'];

const LIMITS = {
  media: 15 * 1024 * 1024, // photo & voice bodies
  video: 100 * 1024 * 1024, // compressed video bodies (client transcodes first)
  videos: 60, // videos kept per couple (storage management)
  photos: 2000, // photos kept per couple — at 15 MB each an uncapped gallery is a disk-full risk
  thumb: 2 * 1024 * 1024, // photo & video thumbnail bodies
  json: 1024 * 1024,
  text: 5000,
  openWhen: 64,
  reactionEmoji: 16,
  strokePoints: 2000,
  strokes: 8000,
  messages: 5000,
  touches: 500,
  // Shared with the aggregate seed's lower-bound mark (game-rules.js):
  // a games list AT this cap seeds `gamesAggregate.seededFromCapped`.
  games: GAMES_LIST_LIMIT,
  moodHistory: 60, // per member
  wordleGrid: 160,
  wordleDays: 60, // dateKeys kept per couple
  coupons: 200,
  couponTitle: 80,
  couponEmoji: 16,
  couponNote: 200,
  songs: 300,
  songTitle: 120,
  songArtist: 120,
  songNote: 300,
  songLink: 500,
  dailyQuestionText: 300, // per language (de/en) of the pinned question text
  photoAlbum: 40,
  inboxTeaser: 80,
  vaultItem: 60 * 1024 * 1024, // encrypted vault blobs (photos/videos/notes)
  vaultItems: 120, // vault items kept per couple
  vaultConfigField: 2048, // base64 salt / verifier strings
  hapticPatterns: 60, // saved haptic patterns per couple
  hapticEvents: 128, // timeline events per haptic pattern
  hapticName: 60,
  hapticSends: 100, // relayed haptic history kept per couple
  checkinDays: 120, // check-in days kept per couple
  lists: 20, // shared lists per couple
  listName: 60,
  listItems: 200, // items per shared list
  listItemText: 200,
  hugs: 100, // queued/opened hugs kept per couple
  hugNote: 200,
  potdDays: 60, // photo-of-the-day days kept per couple
  nowPlayingField: 120, // title/artist of the now-playing status
  maxCouples: 10_000,
  openGames: 20,
  movesPerGame: 4_096,
};

// ---------------------------------------------------------------------------
// validation helpers

function asString(value, field, { max = 200, nonEmpty = true, code = 'invalid_request' } = {}) {
  if (typeof value !== 'string') throw httpError(400, 'invalid_request', `"${field}" must be a string`);
  if (nonEmpty && value.trim().length === 0) throw httpError(400, 'invalid_request', `"${field}" must not be empty`);
  if (value.length > max) throw httpError(400, code, `"${field}" must be at most ${max} characters`);
  return value;
}

function asText(value, field) {
  return asString(value, field, { max: LIMITS.text, code: 'text_too_long' });
}

function asDateKey(value, field) {
  if (!isValidDateKey(value)) throw httpError(400, 'invalid_date', `"${field}" must be a valid YYYY-MM-DD date`);
  return value;
}

function asEnum(value, field, allowed) {
  if (!allowed.includes(value)) {
    throw httpError(400, 'invalid_type', `"${field}" must be one of: ${allowed.join(', ')}`);
  }
  return value;
}

function asTimezone(value) {
  const name = asString(value, 'timezone', { max: 64 });
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: name });
  } catch {
    throw httpError(400, 'bad_timezone', '"timezone" must be a valid IANA timezone name (e.g. Europe/Berlin)');
  }
  return name;
}

function asHexColor(value, field) {
  const color = asString(value, field, { max: 7 }).toUpperCase();
  if (!/^#[0-9A-F]{6}$/.test(color)) {
    throw httpError(400, 'bad_color', `"${field}" must be a #RRGGBB color`);
  }
  return color;
}

function colorLuminance(hex) {
  const channels = [1, 3, 5].map((offset) => Number.parseInt(hex.slice(offset, offset + 2), 16) / 255);
  const [red, green, blue] = channels.map((value) => (
    value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4
  ));
  return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
}

function contrastRatio(first, second) {
  const a = colorLuminance(first);
  const b = colorLuminance(second);
  return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
}

function asCouplePalette(value) {
  if (value === null) return null;
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw httpError(400, 'bad_palette', '"palette" must be an object or null');
  }
  const palette = {
    primary: asHexColor(value.primary, 'palette.primary'),
    secondary: asHexColor(value.secondary, 'palette.secondary'),
    accent: asHexColor(value.accent, 'palette.accent'),
    onAccent: asHexColor(value.onAccent, 'palette.onAccent'),
  };
  if (contrastRatio(palette.accent, '#17062A') < 4.5
      || contrastRatio(palette.accent, palette.onAccent) < 4.5) {
    throw httpError(400, 'low_contrast', 'Palette accent must keep 4.5:1 contrast');
  }
  return palette;
}

function queryInt(url, name, fallback, min, max) {
  const raw = url.searchParams.get(name);
  if (raw === null || raw === '') return fallback;
  const n = Number(raw);
  if (!Number.isInteger(n)) throw httpError(400, 'invalid_request', `"${name}" must be an integer`);
  return Math.min(max, Math.max(min, n));
}

/** Removes the oldest entries so the list is at most `max` long; returns dropped entries. */
function capList(list, max) {
  return list.length > max ? list.splice(0, list.length - max) : [];
}

// Sync contract a: dedup entries are retained for at least 24 h (pruned on
// write only after that window). Within the window a remembered operation is
// a PROMISE — eviction may only ever drop EXPIRED entries. The old 2 000 soft
// cap evicted still-valid entries under load (a retry after 2 000 fresh ops
// answered 201 instead of the duplicate), so the only size bound left is an
// emergency valve far beyond any real outbox burst: 20 000 valid ops per
// couple per 24 h. Only past THAT do the oldest valid entries get sacrificed.
const CLIENT_OPERATIONS_HARD_LIMIT = 20_000;
const CLIENT_OPERATIONS_TTL_MS = 24 * 60 * 60 * 1000;

function clientOperationId(body) {
  return body.clientOperationId == null
    ? null
    : asString(body.clientOperationId, 'clientOperationId', { max: 128 });
}

function operationKey(c, kind, target, operationId) {
  return operationId ? `${c.auth.memberId}|${kind}|${target}|${operationId}` : null;
}

/** Timestamp of one stored entry — legacy entries are bare ISO strings. */
function operationEntryAt(entry) {
  return typeof entry === 'string' ? entry : entry.at;
}

function hasClientOperation(couple, key) {
  return key !== null && couple.clientOperations?.[key] !== undefined;
}

/**
 * The resource snapshot stored with a remembered operation (touch/pulse/hug
 * idempotency — the duplicate response returns the ORIGINAL resource even
 * after the capped source list rolled it off). `undefined` when the key is
 * unknown; `null` when the entry predates resource snapshots.
 */
function getClientOperation(couple, key) {
  if (key === null) return undefined;
  const entry = couple.clientOperations?.[key];
  if (entry === undefined) return undefined;
  return typeof entry === 'string' ? null : (entry.resource ?? null);
}

function rememberClientOperation(couple, key, resource) {
  if (key === null) return;
  if (!couple.clientOperations) couple.clientOperations = {};
  couple.clientOperations[key] = resource === undefined
    ? nowIso()
    : { at: nowIso(), resource };
  const ops = couple.clientOperations;
  const expiredBefore = new Date(Date.now() - CLIENT_OPERATIONS_TTL_MS).toISOString();
  for (const candidate of Object.keys(ops)) {
    if (operationEntryAt(ops[candidate]) < expiredBefore) delete ops[candidate];
  }
  const keys = Object.keys(ops);
  if (keys.length <= CLIENT_OPERATIONS_HARD_LIMIT) return;
  keys.sort((a, b) => operationEntryAt(ops[a]).localeCompare(operationEntryAt(ops[b])));
  for (const old of keys.slice(0, keys.length - CLIENT_OPERATIONS_HARD_LIMIT)) {
    delete ops[old];
  }
}

// ---------------------------------------------------------------------------
// serialization (spec model shapes)

function serializeMember(couple, member, realtime) {
  return {
    id: member.id,
    name: member.name,
    avatar: member.avatar,
    color: member.color,
    petName: member.petName ?? null, // v5.0; pre-5.0 stores lack it
    mood: member.mood,
    moodNote: member.moodNote,
    moodUpdatedAt: member.moodUpdatedAt,
    online: realtime.isOnline(couple.id, member.id),
    lastSeenAt: member.lastSeenAt,
    lastReadAt: member.lastReadAt ?? null, // pre-v1.6 stores lack it
    nowPlaying: freshNowPlaying(member), // v2.0; null when unset or older than 60 min
    energy: freshEnergy(member), // v3.0; null when unset or older than 12 h
    presence: freshPresence(member), // v9.0; null when unset or past `until`
    joinedAt: member.joinedAt,
  };
}

function serializeCouple(couple, realtime) {
  return {
    id: couple.id,
    code: couple.code,
    name: couple.name,
    anniversary: couple.anniversary,
    palette: couple.palette ?? null,
    monogramStyle: couple.monogramStyle ?? 'seal',
    timezone: couple.timezone ?? null, // IANA name; null = server-local time
    createdAt: couple.createdAt,
    members: couple.members.map((m) => serializeMember(couple, m, realtime)),
  };
}

function partnerOf(couple, memberId) {
  return couple.members.find((m) => m.id !== memberId) ?? null;
}

function queuePartnerPush(c, { type, title, body, link }) {
  void c.push.notifyPartner({
    store: c.store,
    couple: c.auth.couple,
    senderMemberId: c.auth.memberId,
    type,
    title,
    body,
    link,
  }).catch((error) => {
    c.log('push: unexpected delivery failure', error?.code ?? error?.message ?? 'unknown');
  });
}

/** Push to ONE member's devices — the turn push may target the mover (extra move). */
function queueMemberPush(c, memberId, { type, title, body, link }) {
  void c.push.notifyMember({
    store: c.store,
    couple: c.auth.couple,
    memberId,
    type,
    title,
    body,
    link,
  }).catch((error) => {
    c.log('push: unexpected delivery failure', error?.code ?? error?.message ?? 'unknown');
  });
}

/**
 * Pre-v1.2 stores lack `openWhen`/`reactions`, pre-v1.7 stores lack `photoId`,
 * pre-v1.8 stores lack `editedAt` — default them on the way out.
 */
function serializeMessage(message) {
  return {
    ...message,
    openWhen: message.openWhen ?? null,
    reactions: message.reactions ?? null,
    photoId: message.photoId ?? null,
    editedAt: message.editedAt ?? null,
    effect: message.effect ?? null, // v5.0; pre-5.0 stores lack it
    sticker: message.sticker ?? null, // v5.3 procedural sticker recipe
  };
}

/**
 * Pre-v1.2 stores lack `thumbUrl`/`favorites`, pre-v1.6 stores lack `album`,
 * older stores lack `takenAt` — default them on the way out.
 */
function serializePhoto(photo) {
  return {
    ...photo,
    url: photo.url ?? `/api/photos/${photo.id}/raw`,
    thumbUrl: photo.thumbUrl ?? null,
    favorites: photo.favorites ?? [],
    album: photo.album ?? null,
    takenAt: photo.takenAt ?? null,
  };
}

/** Video list; pre-v2.0 stores lack the structure. */
function videosOf(couple) {
  if (!couple.videos) couple.videos = [];
  return couple.videos;
}

function serializeVideo(video) {
  return { ...video, thumbUrl: video.thumbUrl ?? null, favorites: video.favorites ?? [] };
}

/**
 * Spicy Vault (v2.0) — end-to-end encrypted couple storage. The server NEVER
 * sees plaintext: items are AES-GCM blobs sealed on-device with a key both
 * partners derive from their shared vault PIN (PBKDF2 + the couple's salt).
 * `config` only holds public KDF parameters and a verifier blob so clients
 * can check the PIN locally. Pre-v2.0 stores lack the structure entirely.
 */
function vaultOf(couple) {
  if (!couple.vault) couple.vault = { config: null, items: [] };
  if (!couple.vault.items) couple.vault.items = [];
  return couple.vault;
}

const VAULT_KINDS = ['photo', 'video', 'note'];

/** Couple-shared haptic library + relay history (v2.0) — pre-v2.0 stores lack both. */
function hapticsOf(couple) {
  if (!couple.haptics) couple.haptics = { patterns: [], sends: [] };
  if (!couple.haptics.patterns) couple.haptics.patterns = [];
  if (!couple.haptics.sends) couple.haptics.sends = [];
  return couple.haptics;
}

const HAPTIC_MAX_SECONDS = 15;

/**
 * Validates + normalizes a recorded vibration timeline. Each event:
 * t = start (seconds), i = intensity 0..1, s = sharpness 0..1, d = duration
 * in seconds (0 = transient tap). Values are rounded to milliseconds and the
 * list is sorted by start so clients can map it 1:1 to CoreHaptics/AHAP.
 */
function asHapticEvents(value) {
  if (!Array.isArray(value) || value.length === 0) {
    throw httpError(400, 'invalid_pattern', '"events" must be a non-empty array');
  }
  if (value.length > LIMITS.hapticEvents) {
    throw httpError(400, 'pattern_too_long', `"events" must have at most ${LIMITS.hapticEvents} entries`);
  }
  const num = (v, idx, field, min, max) => {
    const n = Number(v);
    if (!Number.isFinite(n) || n < min || n > max) {
      throw httpError(400, 'invalid_pattern', `events[${idx}].${field} must be a number between ${min} and ${max}`);
    }
    return Math.round(n * 1000) / 1000;
  };
  const clean = value.map((ev, idx) => ({
    t: num(ev?.t, idx, 't', 0, HAPTIC_MAX_SECONDS),
    i: num(ev?.i ?? 0.7, idx, 'i', 0, 1),
    s: num(ev?.s ?? 0.5, idx, 's', 0, 1),
    d: num(ev?.d ?? 0, idx, 'd', 0, HAPTIC_MAX_SECONDS),
  }));
  clean.sort((a, b) => a.t - b.t);
  return clean;
}

/** Optional emoji tag shared by the haptic endpoints. */
function asHapticEmoji(value) {
  return value == null ? null : asString(value, 'emoji', { max: 16 });
}

// ---------------------------------------------------------------------------
// v2.0 couple features — store accessors (pre-v2.0 stores lack all of these)

/** Check-in days: `{ [dateKey]: { morning: {memberId: iso}, night: {memberId: iso} } }`. */
function checkinsOf(couple) {
  if (!couple.checkins) couple.checkins = {};
  return couple.checkins;
}

const CHECKIN_KINDS = ['morning', 'night'];

function checkinDayView(couple, dateKey) {
  const rec = checkinsOf(couple)[dateKey] ?? {};
  return { dateKey, morning: rec.morning ?? {}, night: rec.night ?? {} };
}

function bothCheckedInOn(couple, dateKey) {
  const rec = checkinsOf(couple)[dateKey];
  if (!rec || couple.members.length < 2) return false;
  return couple.members.every((m) => rec.morning?.[m.id] != null || rec.night?.[m.id] != null);
}

/** Consecutive days (ending today or yesterday) on which BOTH members checked in. */
function checkinStreak(couple) {
  const today = todayKey();
  let cursor = null;
  if (bothCheckedInOn(couple, today)) cursor = today;
  else if (bothCheckedInOn(couple, prevDateKey(today))) cursor = prevDateKey(today);
  if (!cursor) return 0;
  let streak = 0;
  while (bothCheckedInOn(couple, cursor)) {
    streak += 1;
    cursor = prevDateKey(cursor);
  }
  return streak;
}

/** Shared lists (shopping, movies, …): `[{id, name, emoji, items: [...]}]`. */
function listsOf(couple) {
  if (!couple.lists) couple.lists = [];
  return couple.lists;
}

function findList(couple, listId) {
  const list = listsOf(couple).find((l) => l.id === listId);
  if (!list) throw httpError(404, 'not_found', 'Unknown list');
  return list;
}

/** Hug queue for long-distance timezones: `[{id, from, to, note, emoji, createdAt, openedAt}]`. */
function hugsOf(couple) {
  if (!couple.hugs) couple.hugs = [];
  return couple.hugs;
}

/** Photo of the day: `{ [dateKey]: { [memberId]: {photoId, submittedAt} } }`. */
function potdOf(couple) {
  if (!couple.potd) couple.potd = {};
  return couple.potd;
}

function potdDayView(couple, dateKey) {
  return { dateKey, entries: potdOf(couple)[dateKey] ?? {} };
}

/** A member's now-playing status; hidden once older than 60 minutes. */
const NOW_PLAYING_FRESH_MS = 60 * 60 * 1000;

function freshNowPlaying(member) {
  const np = member.nowPlaying;
  if (!np) return null;
  if (Date.now() - Date.parse(np.setAt) > NOW_PLAYING_FRESH_MS) return null;
  return np;
}

/** Pre-v1.6 stores lack `expiresAt` on coupons — default it on the way out. */
function serializeCoupon(coupon) {
  return { ...coupon, expiresAt: coupon.expiresAt ?? null };
}

/** Per-member mood history lives on the couple; v1.0 stores lack it entirely. */
function moodHistoryOf(couple, memberId) {
  if (!couple.moodHistory) couple.moodHistory = {};
  if (!couple.moodHistory[memberId]) couple.moodHistory[memberId] = [];
  return couple.moodHistory[memberId];
}

/** Wordle results per dateKey per member; pre-v1.2 stores lack the structure. */
function wordleOf(couple) {
  if (!couple.wordle) couple.wordle = {};
  return couple.wordle;
}

/** Love coupons list; pre-v1.2 stores lack the structure. */
function couponsOf(couple) {
  if (!couple.coupons) couple.coupons = [];
  return couple.coupons;
}

/** Shared soundtrack list; pre-v1.4 stores lack the structure. */
function songsOf(couple) {
  if (!couple.songs) couple.songs = [];
  return couple.songs;
}

/** Song title: trimmed, non-empty, ≤ 120 chars — all violations are `bad_title`. */
function asSongTitle(value) {
  if (typeof value !== 'string') throw httpError(400, 'bad_title', '"title" must be a string');
  const title = value.trim();
  if (title.length === 0 || title.length > LIMITS.songTitle) {
    throw httpError(400, 'bad_title', `"title" must be 1-${LIMITS.songTitle} characters after trimming`);
  }
  return title;
}

/** Optional song field: null stays null, strings are trimmed (empty → null), length-capped. */
function asSongField(value, field, max) {
  if (value == null) return null;
  if (typeof value !== 'string') throw httpError(400, 'invalid_request', `"${field}" must be a string`);
  const trimmed = value.trim();
  if (trimmed.length > max) throw httpError(400, 'too_long', `"${field}" must be at most ${max} characters`);
  return trimmed.length === 0 ? null : trimmed;
}

/** Optional coupon expiry: null stays null, date strings are normalized to ISO — else `bad_expiry`. */
function asExpiresAt(value) {
  if (value == null) return null;
  if (typeof value !== 'string' || !Number.isFinite(Date.parse(value))) {
    throw httpError(400, 'bad_expiry', '"expiresAt" must be an ISO-8601 date string or null');
  }
  return new Date(Date.parse(value)).toISOString();
}

/** Optional photo album: null stays null, strings are trimmed (empty → null), ≤ 40 chars → `album_too_long`. */
function asPhotoAlbum(value) {
  if (value == null) return null;
  if (typeof value !== 'string') throw httpError(400, 'invalid_request', '"album" must be a string');
  const trimmed = value.trim();
  if (trimmed.length > LIMITS.photoAlbum) {
    throw httpError(400, 'album_too_long', `"album" must be at most ${LIMITS.photoAlbum} characters`);
  }
  return trimmed.length === 0 ? null : trimmed;
}

/** Optional ISO timestamp (e.g. `at`, `since`): normalized to ISO — else the given error code. */
function asIsoTimestamp(value, field, code) {
  if (typeof value !== 'string' || !Number.isFinite(Date.parse(value))) {
    throw httpError(400, code, `"${field}" must be an ISO-8601 timestamp`);
  }
  return new Date(Date.parse(value)).toISOString();
}

// ---------------------------------------------------------------------------
// couple/member factories

function newMember({ name, avatar, color }) {
  return {
    id: id('m'),
    name: asString(name, 'name', { max: 100 }),
    avatar: avatar === undefined ? '💞' : asString(avatar, 'avatar', { max: 32 }),
    color: color === undefined ? '#FF5C8A' : asString(color, 'color', { max: 32 }),
    petName: null, // how the app (and the partner's phone) addresses this member
    lastMessageEffectAt: null,
    mood: null,
    moodNote: null,
    moodUpdatedAt: null,
    lastSeenAt: null,
    lastReadAt: null,
    joinedAt: nowIso(),
  };
}

function newCouple(store) {
  let code = newCoupleCode();
  const taken = new Set(Object.values(store.data.couples).map((c) => c.code));
  while (taken.has(code)) code = newCoupleCode();
  return {
    id: id('c'),
    code,
    name: null,
    anniversary: null,
    palette: null,
    monogramStyle: 'seal',
    createdAt: nowIso(),
    members: [],
    touches: [],
    messages: [],
    photos: [],
    videos: [],
    events: [],
    bucket: [],
    strokes: [],
    daily: {},
    games: [],
    // Whole-life played-game counts (re-eval 2, Befund 9): written forward
    // on every finish, immune to the LIMITS.games eviction below.
    gamesAggregate: { total: 0, perKind: {} },
    moodHistory: {},
    wordle: {},
    coupons: [],
    songs: [],
    counters: { messages: 0, gamesPlayed: 0, touches: {} },
  };
}

function touchCounter(couple, memberId) {
  const counters = couple.counters.touches;
  if (!counters[memberId]) counters[memberId] = { total: 0, byType: {} };
  return counters[memberId];
}

// ---------------------------------------------------------------------------
// daily question helpers

function bothAnsweredOn(couple, dateKey) {
  const rec = couple.daily[dateKey];
  if (!rec || couple.members.length < 2) return false;
  return couple.members.every((m) => rec.answers[m.id]?.text != null);
}

/** Consecutive both-answered days ending today (or yesterday if today is unanswered). */
function computeStreak(couple) {
  const today = todayKey();
  let cursor = null;
  if (bothAnsweredOn(couple, today)) cursor = today;
  else if (bothAnsweredOn(couple, prevDateKey(today))) cursor = prevDateKey(today);
  if (!cursor) return 0;
  let streak = 0;
  while (bothAnsweredOn(couple, cursor)) {
    streak += 1;
    cursor = prevDateKey(cursor);
  }
  return streak;
}

/** DailyEntry as seen by one member; partnerAnswer stays hidden until both answered. */
function dailyEntryFor(couple, dateKey, memberId) {
  const rec = couple.daily[dateKey];
  const partner = partnerOf(couple, memberId);
  const myAnswer = rec?.answers[memberId]?.text ?? null;
  const partnerAnswer = partner ? (rec?.answers[partner.id]?.text ?? null) : null;
  const bothAnswered = bothAnsweredOn(couple, dateKey);
  return {
    dateKey,
    questionId: rec?.questionId ?? null,
    // Schlussrunde 5: the bilingual text stored with the pin — lets a
    // client whose bundled pool does not know the pinned id render the
    // SAME question instead of deriving a different one (which the pin
    // guard would refuse forever: mixed-version lockout).
    questionText: rec?.questionText ?? null,
    myAnswer,
    partnerAnswer: bothAnswered ? partnerAnswer : null,
    bothAnswered,
    streak: computeStreak(couple),
    // v7.0: on "custom days" the couple's own pool overrides the pack
    // question; who wrote it is revealed only once both answered.
    customQuestion: customQuestionView(couple, dateKey, memberId, bothAnswered),
  };
}

/**
 * Optional `questionText` of a daily answer: `{de, en}` — both non-empty
 * trimmed strings of at most LIMITS.dailyQuestionText characters. Absent /
 * null (old clients) passes through as null; anything malformed is a 400,
 * never a silently stored fragment.
 */
function asDailyQuestionText(raw) {
  if (raw == null) return null;
  if (typeof raw !== 'object' || Array.isArray(raw)) {
    throw httpError(400, 'invalid_request', '"questionText" must be an object with "de" and "en" strings');
  }
  const de = typeof raw.de === 'string' ? raw.de.trim() : '';
  const en = typeof raw.en === 'string' ? raw.en.trim() : '';
  if (!de || !en || de.length > LIMITS.dailyQuestionText || en.length > LIMITS.dailyQuestionText) {
    throw httpError(
      400,
      'invalid_request',
      `"questionText.de"/"questionText.en" must be non-empty strings of at most ${LIMITS.dailyQuestionText} characters`,
    );
  }
  return { de, en };
}

// ---------------------------------------------------------------------------
// wordle duel helpers

/**
 * Lazily migrates a v1.2.0 day bucket ({memberId: WordleResult}) to the
 * v1.2.1 shape ({lang: {memberId: WordleResult}}), taking the lang from each
 * stored result. New-shape (and empty) buckets pass through untouched.
 */
function normalizeWordleDay(day) {
  if (!day || Object.keys(day).every((key) => WORDLE_LANGS.includes(key))) return day;
  const byLang = {};
  for (const result of Object.values(day)) {
    const lang = WORDLE_LANGS.includes(result?.lang) ? result.lang : 'en';
    (byLang[lang] ??= {})[result.memberId] = result;
  }
  return byLang;
}

/** Normalized day bucket for a dateKey (undefined when the day has no results). */
function wordleDay(couple, dateKey) {
  const raw = couple.wordle?.[dateKey];
  if (!raw) return undefined;
  const normalized = normalizeWordleDay(raw);
  if (normalized !== raw) couple.wordle[dateKey] = normalized;
  return normalized;
}

/**
 * Per-member view of one (dateKey, lang). Anti-spoiler: the partner's result
 * (grid/rows) is only revealed once the viewer submitted their own for that
 * language; `partnerFinished` is always truthful.
 */
function wordleViewFor(couple, dateKey, lang, memberId) {
  const byMember = wordleDay(couple, dateKey)?.[lang] ?? {};
  const partner = partnerOf(couple, memberId);
  const mine = byMember[memberId] ?? null;
  const theirs = partner ? (byMember[partner.id] ?? null) : null;
  return {
    dateKey,
    lang,
    mine,
    partner: mine && theirs ? theirs : null,
    partnerFinished: Boolean(theirs),
  };
}

// ---------------------------------------------------------------------------
// games helpers

function serializeGame(game, couple) {
  return {
    id: game.id,
    type: game.type,
    state: game.state,
    createdBy: game.createdBy,
    // W8C: the view strips server-only payload fields (memoryduo hides its
    // deck seed — faces are learned only through accepted flip moves).
    payload: gamePayloadView(game),
    result: game.result,
    // Sync contract c: server-authoritative "whose move is it" for EVERY
    // type — null when ended, in the lobby, or not applicable (simultaneous
    // phase, checklist types). Extra moves keep it with the same member.
    turnMemberId: gameTurnMemberId(game, couple),
    rulesVersion: game.rulesVersion ?? 3,
    resultAuthority: game.resultAuthority
      ?? (game.rulesVersion === CURRENT_GAME_RULES_VERSION ? 'server' : 'legacy-client'),
    moves: game.moves,
    createdAt: game.createdAt,
    // Input leases (Welle 6): which device of each member currently drives
    // this session. Identical for every couple device on purpose — the view
    // never carries the full session id (see gameLeaseView). Old clients
    // ignore the unknown key.
    leases: gameLeasesView(game),
  };
}

/** Lease identity of the calling device session (input lease, Welle 6). */
function leaseIdentity(c) {
  return {
    memberId: c.auth.memberId,
    sessionId: c.auth.record.sessionId,
    deviceId: c.auth.record.deviceId,
    deviceName: c.auth.record.deviceName,
  };
}

/**
 * `game_lease` fanout goes to the member's OWN devices only: the partner
 * has no use for which of my devices is driving, and the spectator banner
 * is a per-member affair. The calling device converges from the same frame
 * (idempotent), so no `exceptSessionId` — unlike the touch self-echo there
 * is nothing that would double-render.
 */
function broadcastLease(c, game, reason, lease) {
  c.realtime.sendToMember(c.auth.coupleId, c.auth.memberId, 'game_lease', {
    gameId: game.id,
    memberId: c.auth.memberId,
    lease: gameLeaseView(lease),
    reason,
  });
}

function finishGame(couple, game) {
  // Shared end path (game-rules.js): flips the state, keeps the legacy
  // counters.gamesPlayed, and writes the persistent games aggregate
  // forward for PLAYED games (isPlayedGame — cancelled/declined out).
  recordGameEnd(couple, game);
}

function findGame(couple, gameId) {
  const game = couple.games.find((g) => g.id === gameId);
  if (!game) throw httpError(404, 'not_found', 'Unknown game');
  return game;
}

/** All non-ended sessions (lobby or active), oldest first (store order). */
function openGames(couple) {
  return couple.games.filter((g) => g.state === 'lobby' || g.state === 'active');
}

/**
 * v3.0 commit-reveal helper: when a move carries `{reveal: "<string>",
 * salt: "<string>"}`, the relay annotates it with `verified` by hashing
 * `reveal + salt` (SHA-256, lowercase hex) against the sender's OWN earlier
 * `{commit: "<hex>"}` move — the latest one, or the one addressed via
 * `commitId`. The server never learns the secret before the reveal; it only
 * certifies afterwards that the reveal matches what was committed, so the
 * partner's client does not have to trust the sender.
 */
function annotateReveal(game, memberId, data) {
  if (typeof data.reveal !== 'string' || typeof data.salt !== 'string') return;
  let commit = null;
  if (typeof data.commitId === 'string') {
    const ref = game.moves.find((m) => m.id === data.commitId && m.memberId === memberId);
    if (typeof ref?.data?.commit === 'string') commit = ref.data.commit;
  } else {
    for (let i = game.moves.length - 1; i >= 0; i--) {
      const m = game.moves[i];
      if (m.memberId === memberId && typeof m.data?.commit === 'string') {
        commit = m.data.commit;
        break;
      }
    }
  }
  data.verified = commit !== null && sha256Hex(data.reveal + data.salt) === commit.toLowerCase();
}

/**
 * v3.0 hooks into the shared app-event log (events.js): game moments become
 * `app_event`s that the ritual/platform layers consume.
 *
 * v3.0.1 hardening (EVAL-3.0 P0): events are derived SERVER-SIDE from the
 * stored moves — the relay no longer trusts client claims, so no forged
 * event can mint XP:
 *
 *   movie_match — emitted only when the persisted moves prove that BOTH
 *   members liked the same card index. A client `match` annotation is no
 *   longer a trigger; it is only mined for the cosmetic deck title (the
 *   relay does not know the seeded deck). Idempotent per (game, cardIndex).
 *
 *   quest_done — emitted for the FIRST valid `quest_done` move per
 *   (dateKey, questIndex); re-checking the same box (or replaying the move
 *   in a fresh session of the same day) never re-emits.
 */
const QUEST_INDEX_MAX = 999;

function maybeEmitGameAppEvent(c, game, move) {
  const data = move.data;
  const couple = c.auth.couple;
  if (game.type === 'movieroulette' && data.kind === 'swipe' && data.like === true && Number.isInteger(data.index)) {
    const likedBy = new Set(
      game.moves
        .filter((m) => m.data?.kind === 'swipe' && m.data.like === true && m.data.index === data.index)
        .map((m) => m.memberId),
    );
    const bothLiked = couple.members.length >= 2 && couple.members.every((m) => likedBy.has(m.id));
    if (bothLiked) {
      const title = typeof data.match?.title === 'string' ? data.match.title.slice(0, 200) : null;
      emitAppEvent({
        store: c.store,
        realtime: c.realtime,
        couple,
        type: 'movie_match',
        memberId: null, // a match belongs to both partners
        data: { gameId: game.id, cardIndex: data.index, title },
        dedupeKey: `${game.id}:${data.index}`,
      });
    }
  }
  if (
    game.type === 'dailyquests' &&
    data.kind === 'quest_done' &&
    Number.isInteger(data.questIndex) &&
    data.questIndex >= 0 &&
    data.questIndex <= QUEST_INDEX_MAX
  ) {
    // dateKey is validated at create time (see POST /api/games), so the
    // couple-level dedupe key cannot be dodged by inventing date strings.
    const dateKey = typeof game.payload?.dateKey === 'string' ? game.payload.dateKey : null;
    emitAppEvent({
      store: c.store,
      realtime: c.realtime,
      couple,
      type: 'quest_done',
      memberId: move.memberId,
      data: { gameId: game.id, dateKey, questIndex: data.questIndex },
      dedupeKey: `${dateKey ?? game.id}:${data.questIndex}`,
    });
  }
}

/**
 * "You're up" push after a move (sync contract c): the recipient is the
 * SERVER-AUTHORITATIVE `turnMemberId` — never the "last mover" heuristic,
 * which flipped the wrong way on extra moves (Mancala store landing,
 * Käsekästchen box, Memory match). An extra move therefore pushes the SAME
 * member ("you're up again"); a handover pushes the other one. Never fires
 * on the finishing move, never when the awaited member was already awaited
 * before someone else's move, and at most once per game/recipient/hour —
 * chatty realtime games (Pictionary strokes) must not turn into a push storm.
 */
const GAME_TURN_PUSH_THROTTLE_MS = 60 * 60 * 1000;

function maybeQueueTurnPush(c, game, previousTurnMemberId, complete) {
  if (complete) return;
  const next = gameTurnMemberId(game, c.auth.couple);
  if (next === null) return; // simultaneous phase / checklist — nobody specific is up
  // Someone else moved while `next` was ALREADY awaited → nothing new to say.
  if (next === previousTurnMemberId && next !== c.auth.memberId) return;
  if (!game.turnPushAt) game.turnPushAt = {};
  const last = Date.parse(game.turnPushAt[next] ?? '');
  if (Number.isFinite(last) && Date.now() - last < GAME_TURN_PUSH_THROTTLE_MS) return;
  game.turnPushAt[next] = nowIso();
  c.store.markDirty();
  const extraMove = next === c.auth.memberId;
  queueMemberPush(c, next, {
    type: 'game',
    title: { de: 'Du bist dran 🎲', en: 'Your turn 🎲' },
    body: extraMove
      ? { de: 'Extrazug! Du bist gleich nochmal dran.', en: 'Extra move! You are up again.' }
      : {
          de: `${c.auth.member.name} hat gezogen — jetzt du.`,
          en: `${c.auth.member.name} made a move — your turn.`,
        },
    link: `sooodreamy://game/${game.id}`,
  });
}

/**
 * "You're up!" digest entries: open games where the caller is expected to
 * act — a lobby invitation from the partner, or an active game whose
 * server-authoritative `turnMemberId` is the caller (sync contract c; the
 * old last-mover heuristic misattributed extra moves).
 */
function gamesAwaiting(couple, memberId) {
  return openGames(couple).filter((g) => {
    if (g.state === 'lobby') return g.createdBy !== memberId;
    return gameTurnMemberId(g, couple) === memberId;
  });
}

// ---------------------------------------------------------------------------
// media serving (supports Range for AVPlayer)

async function serveFile(req, res, filePath, contentType) {
  let info;
  try {
    info = await stat(filePath);
  } catch {
    throw httpError(404, 'not_found', 'Media file missing');
  }
  const size = info.size;
  let start = 0;
  let end = size - 1;
  let status = 200;
  const headers = {
    'content-type': contentType,
    'accept-ranges': 'bytes',
    'cache-control': 'private, max-age=31536000, immutable',
  };
  const range = req.headers.range;
  if (range) {
    const m = /^bytes=(\d*)-(\d*)$/.exec(range);
    if (m && (m[1] !== '' || m[2] !== '')) {
      if (m[1] === '') start = Math.max(0, size - Number(m[2]));
      else {
        start = Number(m[1]);
        if (m[2] !== '') end = Math.min(end, Number(m[2]));
      }
      if (start > end || start >= size) {
        res.writeHead(416, { 'content-range': `bytes */${size}` });
        res.end();
        return;
      }
      status = 206;
      headers['content-range'] = `bytes ${start}-${end}/${size}`;
    }
  }
  headers['content-length'] = end - start + 1;
  res.writeHead(status, headers);
  const stream = createReadStream(filePath, { start, end });
  stream.pipe(res);
  stream.on('error', () => res.destroy());
}

// ---------------------------------------------------------------------------
// route table

const routes = [];

function route(method, pattern, opts, handler) {
  routes.push({ method, segments: pattern.split('/').filter(Boolean), ...opts, handler });
}

function matchRoute(method, pathname) {
  const parts = pathname.split('/').filter(Boolean);
  for (const r of routes) {
    if (r.method !== method || r.segments.length !== parts.length) continue;
    const params = {};
    let ok = true;
    for (let i = 0; i < parts.length; i++) {
      const seg = r.segments[i];
      if (seg.startsWith(':')) params[seg.slice(1)] = parts[i];
      else if (seg !== parts[i]) {
        ok = false;
        break;
      }
    }
    if (ok) return { route: r, params };
  }
  return null;
}

// --- public / pairing -------------------------------------------------------

const LANDING_PAGE = Buffer.from(`<!doctype html>
<html lang="de">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>SoooDreamy Server</title>
  <style>
    :root { color-scheme: light dark; font-family: system-ui, sans-serif; }
    body { min-height: 100vh; margin: 0; display: grid; place-items: center; background: #fff5f8; color: #40252f; }
    main { max-width: 34rem; margin: 1.5rem; padding: 2rem; border-radius: 1.5rem; background: white; box-shadow: 0 1rem 3rem #a44b6b22; text-align: center; }
    h1 { margin-top: 0; }
    code { display: block; margin: 1rem 0; padding: .8rem; border-radius: .7rem; background: #f8e9ef; overflow-wrap: anywhere; }
    button { border: 0; border-radius: 999px; padding: .8rem 1.2rem; background: #d94f7d; color: white; font: inherit; cursor: pointer; }
    small { display: block; margin-top: 1.2rem; opacity: .7; }
    @media (prefers-color-scheme: dark) { body { background: #21171b; color: #ffeef4; } main { background: #34242b; } code { background: #4a303b; } }
  </style>
</head>
<body>
  <main>
    <h1>💌 Euer SoooDreamy-Server läuft</h1>
    <p>Diese Adresse in der App unter <strong>Einstellungen → Server</strong> eintragen.</p>
    <code id="address">Server-Adresse</code>
    <button id="copy" type="button">Adresse kopieren</button>
    <small>Your SoooDreamy server is ready. Enter this address in Settings → Server.</small>
  </main>
  <script>
    const address = location.origin;
    document.querySelector('#address').textContent = address;
    document.querySelector('#copy').addEventListener('click', async (event) => {
      try {
        if (navigator.clipboard) await navigator.clipboard.writeText(address);
        else {
          const field = document.createElement('textarea');
          field.value = address;
          document.body.append(field);
          field.select();
          document.execCommand('copy');
          field.remove();
        }
        event.currentTarget.textContent = 'Kopiert ✓';
      } catch {
        event.currentTarget.textContent = 'Adresse oben kopieren';
      }
    });
  </script>
</body>
</html>`);

route('GET', '/', { auth: false }, (c) => {
  c.res.writeHead(200, {
    'content-type': 'text/html; charset=utf-8',
    'content-length': LANDING_PAGE.length,
    'cache-control': 'no-store',
    'content-security-policy': "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'",
    'x-content-type-options': 'nosniff',
  });
  c.res.end(LANDING_PAGE);
});

// Operational vital signs — the "send me your health output" endpoint for
// remote helpers, the admin panel, and the docker-compose healthcheck. The
// two silent disasters (full disk, stale/never backups) surface in `warnings`.
route('GET', '/api/health', { auth: false }, async (c) => {
  const disk = await c.store.diskStatus();
  const lastBackup = (await listBackups(c.store.dataDir))[0] ?? null;
  const backupAgeMinutes = lastBackup?.createdAt
    ? Math.max(0, Math.round((Date.now() - Date.parse(lastBackup.createdAt)) / 60_000))
    : null;
  const pushOutbox = Object.values(c.store.data.couples ?? {})
    .flatMap((couple) => Array.isArray(couple.pushOutbox) ? couple.pushOutbox : []);
  const pendingPushes = pushOutbox.filter((entry) => entry.status === 'pending').length;
  const deadLetterPushes = pushOutbox.filter((entry) => entry.status === 'dead_letter').length;
  const warnings = [];
  if (disk?.warn) warnings.push('disk_low');
  if (disk?.stop) warnings.push('disk_full');
  if (!lastBackup) warnings.push('backup_never');
  else if (backupAgeMinutes == null || backupAgeMinutes > 24 * 60) warnings.push('backup_old');
  if (lastBackup && !lastBackup.includesMedia) warnings.push('backup_media_unprotected');
  if (deadLetterPushes > 0) warnings.push('push_dead_letter');
  if (c.store.quarantinedCoupleIds.size > 0) warnings.push('quarantine');
  sendJson(c.res, 200, {
    ok: true,
    name: c.config.name,
    version: c.config.version,
    serverTime: nowIso(),
    uptimeSeconds: Math.round(process.uptime()),
    nodeVersion: process.version,
    storage: await c.store.storageStats(),
    disk: disk ? { freeBytes: disk.freeBytes, totalBytes: disk.totalBytes, warn: disk.warn } : null,
    lastBackup: lastBackup
      ? {
          id: lastBackup.id,
          createdAt: lastBackup.createdAt,
          ageMinutes: backupAgeMinutes,
          includesMedia: lastBackup.includesMedia,
        }
      : null,
    quarantinedCouples: c.store.quarantinedCoupleIds.size,
    pushOutbox: { pending: pendingPushes, deadLetter: deadLetterPushes },
    warnings,
  });
});

route('POST', '/api/couples', { auth: false }, async (c) => {
  c.rateLimiter.consume('coupleCreate', requestKey(c.req));
  if (Object.keys(c.store.data.couples).length >= (c.config.maxCouples ?? LIMITS.maxCouples)) {
    throw httpError(503, 'server_capacity', 'This server has reached its configured couple quota');
  }
  const body = await readJsonObject(c.req);
  const couple = newCouple(c.store);
  const member = newMember(body);
  // v6.1: every member gets a recovery key at pairing time so a lost session
  // can always be re-attached later (POST /api/couples/rejoin).
  const recoveryKey = issueRecoveryKey(member);
  couple.members.push(member);
  c.store.data.couples[couple.id] = couple;
  const { token, record } = createSession(c.store, {
    coupleId: couple.id,
    memberId: member.id,
    deviceId: body.deviceId,
    deviceName: body.deviceName,
  });
  c.store.markDirty();
  sendJson(c.res, 201, {
    token,
    sessionId: record.sessionId,
    expiresAt: record.expiresAt,
    coupleId: couple.id,
    memberId: member.id,
    recoveryKey,
    couple: serializeCouple(couple, c.realtime),
  });
});

route('POST', '/api/couples/join', { auth: false }, async (c) => {
  c.rateLimiter.consume('coupleJoin', requestKey(c.req));
  const body = await readJsonObject(c.req);
  const code = asString(body.code, 'code', { max: 12 }).trim().toUpperCase();
  const couple = Object.values(c.store.data.couples).find((cp) => cp.code === code);
  if (!couple) throw httpError(404, 'unknown_code', 'No couple with this code');
  if (couple.members.length >= 2) {
    // Not a dead end: an existing member re-attaches via POST
    // /api/couples/rejoin (recovery key / old token / partner-approved
    // replace code) — see docs/API.md "Pairing recovery".
    throw httpError(409, 'couple_full',
      'This couple already has two members. If one of them is you, re-attach via '
      + '/api/couples/rejoin with your recovery key or previous token — or ask your '
      + 'partner for a replace code.');
  }
  const pending = couple.pendingMigrationPartner;
  const member = pending
    ? {
        ...pending,
        name: body.name === undefined ? pending.name : asString(body.name, 'name', { max: 100 }),
        avatar: body.avatar === undefined ? pending.avatar : asString(body.avatar, 'avatar', { max: 32 }),
        color: body.color === undefined ? pending.color : asString(body.color, 'color', { max: 32 }),
        lastSeenAt: null,
        lastReadAt: null,
      }
    : newMember(body);
  const recoveryKey = issueRecoveryKey(member);
  couple.members.push(member);
  if (pending) {
    delete couple.pendingMigrationPartner;
    couple.migration = {
      ...couple.migration,
      requiresPartnerRepair: false,
      partnerRepairedAt: nowIso(),
    };
  }
  const { token, record } = createSession(c.store, {
    coupleId: couple.id,
    memberId: member.id,
    deviceId: body.deviceId,
    deviceName: body.deviceName,
  });
  c.store.markDirty();
  c.realtime.broadcastCouple(couple.id, 'partner_joined', { member: serializeMember(couple, member, c.realtime) });
  sendJson(c.res, 200, {
    token,
    sessionId: record.sessionId,
    expiresAt: record.expiresAt,
    coupleId: couple.id,
    memberId: member.id,
    recoveryKey,
    couple: serializeCouple(couple, c.realtime),
  });
});

// --- couple & profile -------------------------------------------------------

route('GET', '/api/couple', { auth: true }, (c) => {
  sendJson(c.res, 200, { couple: serializeCouple(c.auth.couple, c.realtime), me: c.auth.memberId });
});

route('PATCH', '/api/me', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
  const member = c.auth.member;
  if ('name' in body) member.name = asString(body.name, 'name', { max: 100 });
  if ('avatar' in body) member.avatar = asString(body.avatar, 'avatar', { max: 32 });
  if ('color' in body) member.color = asString(body.color, 'color', { max: 32 });
  if ('petName' in body) {
    // v5.0 Kosename — how the app addresses you („Guten Morgen, Schnuffel ☀️").
    member.petName = body.petName === null
      ? null
      : asString(body.petName, 'petName', { max: 40, nonEmpty: false }).trim() || null;
  }
  if ('mood' in body) {
    if (body.mood === null) {
      member.mood = null;
      member.moodNote = null;
      member.moodUpdatedAt = null;
    } else {
      member.mood = asString(body.mood, 'mood', { max: 32 });
      member.moodUpdatedAt = nowIso();
    }
  }
  if ('moodNote' in body && body.moodNote !== undefined && !(body.mood === null)) {
    member.moodNote = body.moodNote === null ? null : asString(body.moodNote, 'moodNote', { max: 500, nonEmpty: false });
    if (!('mood' in body)) member.moodUpdatedAt = nowIso();
  }
  if ('mood' in body && body.mood !== null) {
    // Setting a (non-null) mood appends to the per-member history. The entry
    // carries the note only when it was set in the same request.
    const history = moodHistoryOf(c.auth.couple, member.id);
    history.push({
      id: id('md'),
      memberId: member.id,
      mood: member.mood,
      moodNote: 'moodNote' in body && body.moodNote != null ? member.moodNote : null,
      createdAt: nowIso(),
    });
    capList(history, LIMITS.moodHistory);
  }
  c.store.markDirty();
  const serialized = serializeMember(c.auth.couple, member, c.realtime);
  c.realtime.broadcastCouple(c.auth.coupleId, 'member_updated', { member: serialized });
  sendJson(c.res, 200, { member: serialized });
});

route('PATCH', '/api/couple', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
  const couple = c.auth.couple;
  if ('name' in body) couple.name = body.name === null ? null : asString(body.name, 'name', { max: 100 });
  if ('anniversary' in body) {
    couple.anniversary = body.anniversary === null ? null : asDateKey(body.anniversary, 'anniversary');
  }
  if ('palette' in body) couple.palette = asCouplePalette(body.palette);
  if ('monogramStyle' in body) {
    couple.monogramStyle = asEnum(body.monogramStyle, 'monogramStyle', MONOGRAM_STYLES);
  }
  if ('timezone' in body) {
    // IANA zone for couple-local rituals (Sunday-evening week-review push).
    // null falls back to the server's local clock.
    couple.timezone = body.timezone === null ? null : asTimezone(body.timezone);
  }
  c.store.markDirty();
  const serialized = serializeCouple(couple, c.realtime);
  c.realtime.broadcastCouple(couple.id, 'couple_updated', { couple: serialized });
  sendJson(c.res, 200, { couple: serialized });
});

// Per-device sessions: tokens expire, can be reviewed/revoked, and rotate
// without recreating the couple. Raw bearer values are never returned by the
// list endpoint and are stored server-side only as SHA-256 digests.
route('GET', '/api/sessions', { auth: true }, (c) => {
  const sessions = Object.values(c.store.data.tokens)
    .filter((record) => record.coupleId === c.auth.coupleId && record.memberId === c.auth.memberId)
    .sort((a, b) => String(b.lastUsedAt).localeCompare(String(a.lastUsedAt)))
    .slice(0, 50)
    .map((record) => sessionView(record, c.auth.record.sessionId));
  sendJson(c.res, 200, { sessions });
});

route('POST', '/api/sessions/current/rotate', { auth: true }, (c) => {
  const rotated = rotateSession(c.store, c.auth.token);
  // Sync contract d: the member's OTHER devices refresh their device manager
  // (sent before the close so the rotating device's sockets still hear it).
  c.realtime.sendToMember(c.auth.coupleId, c.auth.memberId, 'sessions_changed', {
    memberId: c.auth.memberId,
    reason: 'rotated',
    sessionId: rotated.record.sessionId,
    deviceName: rotated.record.deviceName ?? null,
  });
  c.realtime.closeSession(c.auth.record.sessionId, 'session rotated');
  sendJson(c.res, 200, {
    token: rotated.token,
    sessionId: rotated.record.sessionId,
    expiresAt: rotated.record.expiresAt,
  });
});

route('POST', '/api/sessions/:id/revoke', { auth: true }, (c) => {
  const target = Object.values(c.store.data.tokens).find(
    (record) => record.sessionId === c.params.id && record.memberId === c.auth.memberId,
  );
  if (!revokeSession(c.store, c.params.id, c.auth.memberId)) {
    throw httpError(404, 'not_found', 'Unknown device session');
  }
  if (target) {
    c.push.unregisterDevice({
      store: c.store,
      couple: c.auth.couple,
      memberId: c.auth.memberId,
      deviceId: target.deviceId,
    });
  }
  // Sync contract d: all of the member's devices refresh their device
  // manager (sent before the close so the revoked device also hears it —
  // its sockets then die with code 4001).
  c.realtime.sendToMember(c.auth.coupleId, c.auth.memberId, 'sessions_changed', {
    memberId: c.auth.memberId,
    reason: 'revoked',
    sessionId: c.params.id,
    deviceName: target?.deviceName ?? null,
  });
  c.realtime.closeSession(c.params.id, 'session revoked');
  sendJson(c.res, 200, { ok: true });
});

// APNs registrations belong to the authenticated session's device id. Clients
// cannot register or remove a token for a different device/member.
route('GET', '/api/push-devices', { auth: true }, (c) => {
  sendJson(c.res, 200, {
    deliveryAvailable: c.push.available,
    registrations: c.push.registrations(c.auth.couple, c.auth.memberId),
  });
});

route('POST', '/api/push-devices/current', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
  const apnsToken = asString(body.apnsToken, 'apnsToken', { max: 400 }).trim().toLowerCase();
  if (apnsToken.length < 32 || apnsToken.length % 2 !== 0 || !/^[0-9a-f]+$/.test(apnsToken)) {
    throw httpError(400, 'bad_apns_token', '"apnsToken" must be an even-length hexadecimal APNs token');
  }
  const environment = asEnum(body.environment, 'environment', ['development', 'production']);
  const bundleId = asString(body.bundleId, 'bundleId', { max: 200 }).trim();
  if (!/^[A-Za-z0-9.-]{3,200}$/.test(bundleId)) {
    throw httpError(400, 'bad_bundle_id', '"bundleId" must be an Apple bundle identifier');
  }
  const language = asEnum(body.language, 'language', ['de', 'en']);
  const registration = c.push.register({
    store: c.store,
    couple: c.auth.couple,
    memberId: c.auth.memberId,
    deviceId: c.auth.record.deviceId,
    apnsToken,
    environment,
    bundleId,
    language,
  });
  sendJson(c.res, 200, { deliveryAvailable: c.push.available, registration });
});

route('DELETE', '/api/push-devices/current', { auth: true }, (c) => {
  const removed = c.push.unregisterDevice({
    store: c.store,
    couple: c.auth.couple,
    memberId: c.auth.memberId,
    deviceId: c.auth.record.deviceId,
  });
  sendJson(c.res, 200, { ok: true, removed });
});

route('DELETE', '/api/couple', { auth: true }, async (c) => {
  const couple = c.auth.couple;
  c.realtime.broadcastCouple(couple.id, 'couple_dissolved', {});
  for (const photo of couple.photos) {
    await c.store.deleteMedia('photos', `${photo.id}.jpg`);
    await c.store.deleteMedia('photos', `${photo.id}.thumb.jpg`);
  }
  for (const video of videosOf(couple)) {
    await c.store.deleteMedia('videos', `${video.id}.mp4`);
    await c.store.deleteMedia('videos', `${video.id}.thumb.jpg`);
  }
  for (const item of vaultOf(couple).items) {
    await c.store.deleteMedia('vault', `${item.id}.bin`);
  }
  for (const msg of allMessagesOf(couple)) {
    if (msg.type === 'voice') await c.store.deleteMedia('voice', `${msg.id}.m4a`);
  }
  await deleteRitualMedia(c.store, couple); // v3.0 day-memo audio
  for (const [token, auth] of Object.entries(c.store.data.tokens)) {
    if (auth.coupleId === couple.id) delete c.store.data.tokens[token];
  }
  invalidateLinkCodes(c.store, { coupleId: couple.id });
  delete c.store.data.couples[couple.id];
  c.store.markDirty();
  c.realtime.closeCouple(couple.id);
  sendJson(c.res, 200, { ok: true });
});

// --- mood history ------------------------------------------------------------

route('GET', '/api/moods', { auth: true }, (c) => {
  const limit = queryInt(c.url, 'limit', 80, 1, 200);
  const merged = [];
  for (const list of Object.values(c.auth.couple.moodHistory ?? {})) {
    for (let i = list.length - 1; i >= 0; i--) merged.push(list[i]); // newest first per member
  }
  // Stable sort keeps each member's newest-first order for same-ms entries.
  merged.sort((x, y) => (x.createdAt < y.createdAt ? 1 : x.createdAt > y.createdAt ? -1 : 0));
  sendJson(c.res, 200, { moods: merged.slice(0, limit) });
});

// --- touches -----------------------------------------------------------------

route('POST', '/api/touches', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
  const type = asEnum(body.type, 'type', TOUCH_TYPES);
  // Sync contract a: a stable clientOperationId makes lost-response retries
  // exactly-once — the dedup runs BEFORE persistence/broadcast/push and the
  // duplicate answer returns the ORIGINAL touch (kept 24 h, independent of
  // the capped touch history).
  const opKey = operationKey(c, 'touch', '-', clientOperationId(body));
  if (hasClientOperation(c.auth.couple, opKey)) {
    sendJson(c.res, 200, { touch: getClientOperation(c.auth.couple, opKey), duplicate: true });
    return;
  }
  const touch = { id: id('t'), type, senderId: c.auth.memberId, createdAt: nowIso() };
  rememberClientOperation(c.auth.couple, opKey, touch);
  c.auth.couple.touches.push(touch);
  capList(c.auth.couple.touches, LIMITS.touches);
  const counter = touchCounter(c.auth.couple, c.auth.memberId);
  counter.total += 1;
  counter.byType[type] = (counter.byType[type] ?? 0) + 1;
  c.store.markDirty();
  c.realtime.broadcastPartner(c.auth.coupleId, c.auth.memberId, 'touch', { touch });
  // Multi-device: the sender's OTHER devices converge too (the calling
  // session already rendered the touch locally, so it is excluded).
  c.realtime.sendToMember(c.auth.coupleId, c.auth.memberId, 'touch', { touch }, {
    exceptSessionId: c.auth.record.sessionId,
  });
  queuePartnerPush(c, {
    type: 'touch',
    title: { de: `Von ${c.auth.member.name}`, en: `From ${c.auth.member.name}` },
    body: { de: 'Dein Schatz hat dir Liebe geschickt.', en: 'Your sweetheart sent you some love.' },
    link: 'sooodreamy://tab/home',
  });
  sendJson(c.res, 201, { touch });
});

route('GET', '/api/touches/recent', { auth: true }, (c) => {
  const limit = queryInt(c.url, 'limit', 30, 1, LIMITS.touches);
  const touches = c.auth.couple.touches.slice(-limit).reverse();
  sendJson(c.res, 200, { touches });
});

// --- haptic patterns (v2.0) ---------------------------------------------------
// Couple-shared library of recorded vibration patterns. Events are a compact
// timeline (t/i/s/d) that clients turn into CoreHaptics/AHAP patterns. Sends
// are relayed live via WS *and* kept in a capped history so an offline
// partner can still replay what they missed.

/** Persists + relays one haptic send; returns the serialized send record. */
function relayHaptic(c, { patternId, name, emoji, events }) {
  const haptics = hapticsOf(c.auth.couple);
  const haptic = {
    id: id('h'),
    patternId: patternId ?? null,
    name: name ?? null,
    emoji: emoji ?? null,
    events,
    senderId: c.auth.memberId,
    createdAt: nowIso(),
  };
  haptics.sends.push(haptic);
  capList(haptics.sends, LIMITS.hapticSends);
  c.store.markDirty();
  c.realtime.broadcastPartner(c.auth.coupleId, c.auth.memberId, 'haptic', { haptic });
  // Multi-device: the sender's OTHER devices see (and can replay) the send;
  // the calling session is excluded — it already played the vibe.
  c.realtime.sendToMember(c.auth.coupleId, c.auth.memberId, 'haptic', { haptic }, {
    exceptSessionId: c.auth.record.sessionId,
  });
  return haptic;
}

route('GET', '/api/haptics', { auth: true }, (c) => {
  sendJson(c.res, 200, { patterns: hapticsOf(c.auth.couple).patterns.slice().reverse() });
});

route('GET', '/api/haptics/recent', { auth: true }, (c) => {
  const limit = queryInt(c.url, 'limit', 30, 1, LIMITS.hapticSends);
  sendJson(c.res, 200, { haptics: hapticsOf(c.auth.couple).sends.slice(-limit).reverse() });
});

route('POST', '/api/haptics', { auth: true }, async (c) => {
  const haptics = hapticsOf(c.auth.couple);
  if (haptics.patterns.length >= LIMITS.hapticPatterns) {
    throw httpError(413, 'too_many_patterns', `At most ${LIMITS.hapticPatterns} saved patterns — delete some first`);
  }
  const body = await readJsonObject(c.req);
  const pattern = {
    id: id('hp'),
    name: asString(body.name, 'name', { max: LIMITS.hapticName }),
    emoji: asHapticEmoji(body.emoji),
    events: asHapticEvents(body.events),
    createdBy: c.auth.memberId,
    createdAt: nowIso(),
    sentCount: 0,
  };
  haptics.patterns.push(pattern);
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'haptic_pattern_added', { pattern });
  sendJson(c.res, 201, { pattern });
});

// Send an ad-hoc recording without saving it to the library first.
route('POST', '/api/haptics/send', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
  const haptic = relayHaptic(c, {
    name: body.name == null ? null : asString(body.name, 'name', { max: LIMITS.hapticName }),
    emoji: asHapticEmoji(body.emoji),
    events: asHapticEvents(body.events),
  });
  sendJson(c.res, 201, { haptic });
});

// The library is shared: BOTH partners may rename/retag any pattern.
route('PATCH', '/api/haptics/:id', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
  const pattern = hapticsOf(c.auth.couple).patterns.find((p) => p.id === c.params.id);
  if (!pattern) throw httpError(404, 'not_found', 'Unknown haptic pattern');
  if ('name' in body) pattern.name = asString(body.name, 'name', { max: LIMITS.hapticName });
  if ('emoji' in body) pattern.emoji = asHapticEmoji(body.emoji);
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'haptic_pattern_updated', { pattern });
  sendJson(c.res, 200, { pattern });
});

route('DELETE', '/api/haptics/:id', { auth: true }, (c) => {
  const patterns = hapticsOf(c.auth.couple).patterns;
  const idx = patterns.findIndex((p) => p.id === c.params.id);
  if (idx === -1) throw httpError(404, 'not_found', 'Unknown haptic pattern');
  const [pattern] = patterns.splice(idx, 1);
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'haptic_pattern_deleted', { id: pattern.id });
  sendJson(c.res, 200, { ok: true });
});

route('POST', '/api/haptics/:id/send', { auth: true }, (c) => {
  const pattern = hapticsOf(c.auth.couple).patterns.find((p) => p.id === c.params.id);
  if (!pattern) throw httpError(404, 'not_found', 'Unknown haptic pattern');
  pattern.sentCount = (pattern.sentCount ?? 0) + 1;
  const haptic = relayHaptic(c, {
    patternId: pattern.id,
    name: pattern.name,
    emoji: pattern.emoji,
    events: pattern.events,
  });
  sendJson(c.res, 201, { haptic, pattern });
});

// --- messages & voice ---------------------------------------------------------

route('GET', '/api/messages', { auth: true }, (c) => {
  const limit = queryInt(c.url, 'limit', 50, 1, 200);
  const before = c.url.searchParams.get('before');
  const list = allMessagesOf(c.auth.couple);
  let endIdx = list.length;
  if (before) {
    endIdx = list.findIndex((m) => m.id === before);
    if (endIdx === -1) throw httpError(404, 'not_found', 'Unknown "before" message id');
  }
  const startIdx = Math.max(0, endIdx - limit);
  sendJson(c.res, 200, { messages: list.slice(startIdx, endIdx).map(serializeMessage) });
});

function pushMessage(c, message) {
  const couple = c.auth.couple;
  couple.messages.push(message);
  couple.counters.messages += 1;
  archiveMessageOverflow(couple, LIMITS.messages);
  c.store.markDirty();
  c.realtime.broadcastCouple(couple.id, 'message', { message: serializeMessage(message) });
  queuePartnerPush(c, {
    type: 'message',
    title: { de: `Nachricht von ${c.auth.member.name}`, en: `Message from ${c.auth.member.name}` },
    body: message.type === 'voice'
      ? { de: 'Neue Sprachnachricht', en: 'New voice message' }
      : { de: 'Neue Nachricht', en: 'New message' },
    link: 'sooodreamy://tab/chat',
  });
}

route('POST', '/api/messages', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
  const clientMessageId = body.clientMessageId == null
    ? null
    : asString(body.clientMessageId, 'clientMessageId', { max: 128 });
  if (clientMessageId) {
    const existing = allMessagesOf(c.auth.couple).find(
      (message) => message.senderId === c.auth.memberId && message.clientMessageId === clientMessageId,
    );
    if (existing) {
      sendJson(c.res, 200, { message: serializeMessage(existing), duplicate: true });
      return;
    }
  }
  const type = asEnum(body.type, 'type', MESSAGE_TYPES);
  // Send effect (optional, any message type). Backward-compatible: null.
  const effect = body.effect == null ? null : asEnum(body.effect, 'effect', MESSAGE_EFFECTS);
  // Photo messages reference an existing gallery photo (either member's);
  // their "text" is an optional caption (blank → null). Other types require text.
  let text;
  let photoId = null;
  let sticker = null;
  if (type === 'photo') {
    if (typeof body.photoId !== 'string' || body.photoId.length === 0) {
      throw httpError(400, 'bad_photo', '"photoId" must be a non-empty string');
    }
    const photo = c.auth.couple.photos.find((p) => p.id === body.photoId);
    if (!photo) throw httpError(404, 'unknown_photo', 'No photo with this id in your gallery');
    photoId = photo.id;
    text =
      body.text == null
        ? null
        : asString(body.text, 'text', { max: LIMITS.text, nonEmpty: false, code: 'text_too_long' }).trim() || null;
  } else if (type === 'sticker') {
    if (!body.sticker || typeof body.sticker !== 'object' || Array.isArray(body.sticker)) {
      throw httpError(400, 'bad_sticker', '"sticker" must be a procedural recipe object');
    }
    if (!Number.isSafeInteger(body.sticker.seed) || body.sticker.seed < 0) {
      throw httpError(400, 'bad_sticker', '"sticker.seed" must be a non-negative safe integer');
    }
    sticker = {
      shape: asEnum(body.sticker.shape, 'sticker.shape', STICKER_SHAPES),
      color: asHexColor(body.sticker.color, 'sticker.color'),
      seed: body.sticker.seed,
      label: body.sticker.label == null
        ? null
        : asString(body.sticker.label, 'sticker.label', { max: 24, nonEmpty: false }).trim() || null,
    };
    text = null;
  } else {
    text = asText(body.text, 'text');
  }
  const title =
    type === 'letter' && body.title != null ? asString(body.title, 'title', { max: 200, nonEmpty: false }) : null;
  // "Sealed letter" hint — stored for letters only, silently ignored otherwise.
  let openWhen = null;
  if (type === 'letter' && body.openWhen != null) {
    const trimmed = asString(body.openWhen, 'openWhen', { nonEmpty: false, max: LIMITS.text }).trim();
    if (trimmed.length > LIMITS.openWhen) {
      throw httpError(400, 'openwhen_too_long', `"openWhen" must be at most ${LIMITS.openWhen} characters`);
    }
    if (trimmed.length > 0) openWhen = trimmed;
  }
  if (effect) {
    const lastEffectAt = Date.parse(c.auth.member.lastMessageEffectAt ?? '');
    if (Number.isFinite(lastEffectAt) && Date.now() - lastEffectAt < MESSAGE_EFFECT_COOLDOWN_MS) {
      const err = httpError(429, 'effect_cooldown', 'Wait briefly before sending another effect');
      // retry-after lets clients show a countdown instead of an error.
      err.retryAfter = Math.max(1, Math.ceil((lastEffectAt + MESSAGE_EFFECT_COOLDOWN_MS - Date.now()) / 1000));
      throw err;
    }
    c.auth.member.lastMessageEffectAt = nowIso();
  }
  const message = {
    id: id('msg'),
    senderId: c.auth.memberId,
    type,
    text,
    title,
    openWhen,
    photoId,
    sticker,
    effect,
    clientMessageId,
    audioUrl: null,
    durationSec: null,
    createdAt: nowIso(),
  };
  pushMessage(c, message);
  sendJson(c.res, 201, { message: serializeMessage(message) });
});

route('POST', '/api/messages/:id/reactions', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
  if (typeof body.emoji !== 'string') throw httpError(400, 'bad_emoji', '"emoji" must be a string');
  const emoji = body.emoji.trim();
  if (emoji.length === 0 || emoji.length > LIMITS.reactionEmoji) {
    throw httpError(400, 'bad_emoji', `"emoji" must be 1-${LIMITS.reactionEmoji} characters after trimming`);
  }
  // Archived chunks are immutable; only messages in the mutable hot set can react.
  const message = c.auth.couple.messages.find((m) => m.id === c.params.id);
  if (!message) throw httpError(404, 'not_found', 'Unknown message');
  const opKey = operationKey(c, 'reaction', `${message.id}|${emoji}`, clientOperationId(body));
  if (hasClientOperation(c.auth.couple, opKey)) {
    sendJson(c.res, 200, { message: serializeMessage(message), duplicate: true });
    return;
  }
  if (!message.reactions) message.reactions = {};
  const members = message.reactions[emoji] ?? (message.reactions[emoji] = []);
  const at = members.indexOf(c.auth.memberId);
  if (at === -1) members.push(c.auth.memberId);
  else members.splice(at, 1);
  if (members.length === 0) delete message.reactions[emoji];
  if (Object.keys(message.reactions).length === 0) delete message.reactions;
  rememberClientOperation(c.auth.couple, opKey);
  c.store.markDirty();
  const serialized = serializeMessage(message);
  c.realtime.broadcastCouple(c.auth.coupleId, 'message_updated', { message: serialized });
  sendJson(c.res, 200, { message: serialized });
});

// Message edit (v1.8): the sender may rewrite the text of their own text or
// letter messages. Voice and photo messages are not editable (a photo
// message's `text` is a caption tied to the send, not free-standing prose).
route('PATCH', '/api/messages/:id', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
  const text = asText(body.text, 'text');
  // Archived chunks are immutable; only messages in the mutable hot set can be edited.
  const message = c.auth.couple.messages.find((m) => m.id === c.params.id);
  if (!message) throw httpError(404, 'not_found', 'Unknown message');
  if (message.senderId !== c.auth.memberId) {
    throw httpError(403, 'not_yours', 'Only the sender may edit a message');
  }
  if (message.type !== 'text' && message.type !== 'letter') {
    throw httpError(400, 'not_editable', 'Only text and letter messages can be edited');
  }
  message.text = text;
  message.editedAt = nowIso();
  c.store.markDirty();
  const serialized = serializeMessage(message);
  c.realtime.broadcastCouple(c.auth.coupleId, 'message_updated', { message: serialized });
  sendJson(c.res, 200, { message: serialized });
});

route('DELETE', '/api/messages/:id', { auth: true }, async (c) => {
  const list = c.auth.couple.messages;
  const idx = list.findIndex((m) => m.id === c.params.id);
  if (idx === -1) throw httpError(404, 'not_found', 'Unknown message');
  if (list[idx].senderId !== c.auth.memberId) {
    throw httpError(403, 'not_yours', 'Only the sender may delete a message');
  }
  const [message] = list.splice(idx, 1);
  if (message.type === 'voice') await c.store.deleteMedia('voice', `${message.id}.m4a`);
  // counters.messages is a lifetime total and intentionally stays untouched.
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'message_deleted', { id: message.id });
  sendJson(c.res, 200, { ok: true });
});

// Read receipt: marks everything up to `at` (default: now) as read by me.
route('POST', '/api/messages/read', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req).catch((err) => {
    // Allow an empty body for "read right now".
    if (err instanceof HttpError && err.code === 'invalid_json') return {};
    throw err;
  });
  const at = body.at == null ? nowIso() : asIsoTimestamp(body.at, 'at', 'bad_at');
  c.auth.member.lastReadAt = at;
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'message_read', { memberId: c.auth.memberId, at });
  sendJson(c.res, 200, { memberId: c.auth.memberId, at });
});

route('POST', '/api/voice', { auth: true }, async (c) => {
  const buf = await readBody(c.req, LIMITS.media);
  if (buf.length === 0) throw httpError(400, 'empty_body', 'Voice upload body is empty');
  const duration = Number.parseFloat(c.req.headers['x-duration-sec']);
  const msgId = id('msg');
  await c.store.saveMedia('voice', `${msgId}.m4a`, buf);
  const message = {
    id: msgId,
    senderId: c.auth.memberId,
    type: 'voice',
    text: null,
    title: null,
    openWhen: null,
    audioUrl: `/api/voice/${msgId}/raw`,
    durationSec: Number.isFinite(duration) ? duration : null,
    createdAt: nowIso(),
  };
  pushMessage(c, message);
  sendJson(c.res, 201, { message: serializeMessage(message) });
});

route('GET', '/api/voice/:id/raw', { auth: true }, async (c) => {
  const msg = allMessagesOf(c.auth.couple).find((m) => m.id === c.params.id && m.type === 'voice');
  if (!msg) throw httpError(404, 'not_found', 'Unknown voice message');
  await serveFile(c.req, c.res, c.store.mediaPath('voice', `${msg.id}.m4a`), 'audio/mp4');
});

// --- photos --------------------------------------------------------------------

route('POST', '/api/photos', { auth: true }, async (c) => {
  if (c.auth.couple.photos.length >= LIMITS.photos) {
    throw httpError(413, 'too_many_photos', `At most ${LIMITS.photos} photos per couple — delete some first`);
  }
  const buf = await readBody(c.req, LIMITS.media);
  if (buf.length === 0) throw httpError(400, 'empty_body', 'Photo upload body is empty');
  let caption = null;
  const rawCaption = c.req.headers['x-caption'];
  if (typeof rawCaption === 'string' && rawCaption !== '') {
    try {
      caption = decodeURIComponent(rawCaption);
    } catch {
      caption = rawCaption;
    }
  }
  const width = Number.parseInt(c.req.headers['x-width'], 10);
  const height = Number.parseInt(c.req.headers['x-height'], 10);
  // EXIF capture date, read by the client BEFORE re-encoding strips metadata.
  // Lenient like width/height: a bad value must not fail a photo upload.
  const takenAtMs = Date.parse(c.req.headers['x-taken-at'] ?? '');
  const acceptedTakenAt = Number.isFinite(takenAtMs) && takenAtMs <= Date.now() + 24 * 60 * 60_000
    ? new Date(takenAtMs).toISOString()
    : null;
  const photoId = id('ph');
  const reservation = c.store.reserveMedia({
    bytes: buf.length,
    coupleId: c.auth.coupleId,
    collection: 'photos',
    currentCount: c.auth.couple.photos.length,
    limit: LIMITS.photos,
    limitCode: 'too_many_photos',
    limitMessage: `At most ${LIMITS.photos} photos per couple — delete some first`,
  });
  let serialized;
  try {
    await c.store.saveMedia('photos', `${photoId}.jpg`, buf, reservation);
    const photo = {
      id: photoId,
      uploaderId: c.auth.memberId,
      caption,
      url: `/api/photos/${photoId}/raw`,
      thumbUrl: null,
      width: Number.isFinite(width) && width > 0 ? width : null,
      height: Number.isFinite(height) && height > 0 ? height : null,
      album: null,
      takenAt: acceptedTakenAt,
      createdAt: nowIso(),
    };
    c.auth.couple.photos.push(photo);
    c.store.markDirty();
    serialized = serializePhoto(photo);
  } finally {
    reservation.release();
  }
  c.realtime.broadcastCouple(c.auth.coupleId, 'photo_added', { photo: serialized });
  queuePartnerPush(c, {
    type: 'photo',
    title: { de: `Foto von ${c.auth.member.name}`, en: `Photo from ${c.auth.member.name}` },
    body: { de: 'Ein neuer gemeinsamer Moment wartet.', en: 'A new shared moment is waiting.' },
    link: 'sooodreamy://photos',
  });
  // count/limit ride along so clients can warn BEFORE the 413 wall is hit.
  sendJson(c.res, 201, { photo: serialized, galleryCount: c.auth.couple.photos.length, galleryLimit: LIMITS.photos });
});

route('GET', '/api/photos', { auth: true }, (c) => {
  sendJson(c.res, 200, {
    photos: c.auth.couple.photos.slice().reverse().map(serializePhoto),
    limit: LIMITS.photos,
  });
});

route('GET', '/api/photos/:id/raw', { auth: true }, async (c) => {
  const photo = c.auth.couple.photos.find((p) => p.id === c.params.id);
  if (!photo) throw httpError(404, 'not_found', 'Unknown photo');
  await serveFile(c.req, c.res, c.store.mediaPath('photos', `${photo.id}.jpg`), 'image/jpeg');
});

route('POST', '/api/photos/:id/thumb', { auth: true }, async (c) => {
  const photo = c.auth.couple.photos.find((p) => p.id === c.params.id);
  if (!photo) throw httpError(404, 'not_found', 'Unknown photo');
  if (photo.uploaderId !== c.auth.memberId) {
    throw httpError(403, 'not_yours', 'Only the uploader may add a thumbnail');
  }
  const buf = await readBody(c.req, LIMITS.thumb);
  if (buf.length === 0) throw httpError(400, 'empty_body', 'Thumbnail upload body is empty');
  await c.store.saveMedia('photos', `${photo.id}.thumb.jpg`, buf);
  photo.thumbUrl = `/api/photos/${photo.id}/thumb/raw`;
  c.store.markDirty();
  const serialized = serializePhoto(photo);
  c.realtime.broadcastCouple(c.auth.coupleId, 'photo_updated', { photo: serialized });
  sendJson(c.res, 200, { photo: serialized });
});

route('POST', '/api/photos/:id/favorite', { auth: true }, (c) => {
  const photo = c.auth.couple.photos.find((p) => p.id === c.params.id);
  if (!photo) throw httpError(404, 'not_found', 'Unknown photo');
  if (!photo.favorites) photo.favorites = [];
  const at = photo.favorites.indexOf(c.auth.memberId);
  if (at === -1) photo.favorites.push(c.auth.memberId);
  else photo.favorites.splice(at, 1);
  if (photo.favorites.length === 0) delete photo.favorites;
  c.store.markDirty();
  const serialized = serializePhoto(photo);
  c.realtime.broadcastCouple(c.auth.coupleId, 'photo_updated', { photo: serialized });
  sendJson(c.res, 200, { photo: serialized });
});

route('GET', '/api/photos/:id/thumb/raw', { auth: true }, async (c) => {
  const photo = c.auth.couple.photos.find((p) => p.id === c.params.id);
  if (!photo) throw httpError(404, 'not_found', 'Unknown photo');
  if (!photo.thumbUrl) throw httpError(404, 'no_thumb', 'This photo has no thumbnail');
  await serveFile(c.req, c.res, c.store.mediaPath('photos', `${photo.id}.thumb.jpg`), 'image/jpeg');
});

// The gallery is shared: like delete, BOTH partners may edit caption/album.
route('PATCH', '/api/photos/:id', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
  const photo = c.auth.couple.photos.find((p) => p.id === c.params.id);
  if (!photo) throw httpError(404, 'not_found', 'Unknown photo');
  if ('caption' in body) {
    photo.caption = body.caption === null ? null : asString(body.caption, 'caption', { max: LIMITS.text, nonEmpty: false });
  }
  if ('album' in body) photo.album = asPhotoAlbum(body.album);
  c.store.markDirty();
  const serialized = serializePhoto(photo);
  c.realtime.broadcastCouple(c.auth.coupleId, 'photo_updated', { photo: serialized });
  sendJson(c.res, 200, { photo: serialized });
});

route('DELETE', '/api/photos/:id', { auth: true }, async (c) => {
  const idx = c.auth.couple.photos.findIndex((p) => p.id === c.params.id);
  if (idx === -1) throw httpError(404, 'not_found', 'Unknown photo');
  const [photo] = c.auth.couple.photos.splice(idx, 1);
  await c.store.deleteMedia('photos', `${photo.id}.jpg`);
  await c.store.deleteMedia('photos', `${photo.id}.thumb.jpg`);
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'photo_deleted', { id: photo.id });
  sendJson(c.res, 200, { ok: true });
});

// --- videos --------------------------------------------------------------------
// Clients transcode/compress before uploading (AVAssetExportSession on iOS);
// the server stores the MP4 as-is and streams it back with Range support.

route('POST', '/api/videos', { auth: true }, async (c) => {
  const videos = videosOf(c.auth.couple);
  if (videos.length >= LIMITS.videos) {
    throw httpError(413, 'too_many_videos', `At most ${LIMITS.videos} videos per couple — delete some first`);
  }
  const buf = await readBody(c.req, LIMITS.video);
  if (buf.length === 0) throw httpError(400, 'empty_body', 'Video upload body is empty');
  let caption = null;
  const rawCaption = c.req.headers['x-caption'];
  if (typeof rawCaption === 'string' && rawCaption !== '') {
    try {
      caption = decodeURIComponent(rawCaption);
    } catch {
      caption = rawCaption;
    }
  }
  const width = Number.parseInt(c.req.headers['x-width'], 10);
  const height = Number.parseInt(c.req.headers['x-height'], 10);
  const duration = Number.parseFloat(c.req.headers['x-duration']);
  const videoId = id('vd');
  const reservation = c.store.reserveMedia({
    bytes: buf.length,
    coupleId: c.auth.coupleId,
    collection: 'videos',
    currentCount: videos.length,
    limit: LIMITS.videos,
    limitCode: 'too_many_videos',
    limitMessage: `At most ${LIMITS.videos} videos per couple — delete some first`,
  });
  let serialized;
  try {
    await c.store.saveMedia('videos', `${videoId}.mp4`, buf, reservation);
    const video = {
      id: videoId,
      uploaderId: c.auth.memberId,
      caption,
      url: `/api/videos/${videoId}/raw`,
      thumbUrl: null,
      width: Number.isFinite(width) && width > 0 ? width : null,
      height: Number.isFinite(height) && height > 0 ? height : null,
      duration: Number.isFinite(duration) && duration > 0 ? Math.round(duration * 10) / 10 : null,
      bytes: buf.length,
      createdAt: nowIso(),
    };
    videos.push(video);
    c.store.markDirty();
    serialized = serializeVideo(video);
  } finally {
    reservation.release();
  }
  c.realtime.broadcastCouple(c.auth.coupleId, 'video_added', { video: serialized });
  // Same courtesy as photos: without a push the partner only ever learns about
  // a new video if the gallery happens to be open when the socket event lands.
  queuePartnerPush(c, {
    type: 'video',
    title: { de: `Video von ${c.auth.member.name} 🎬`, en: `Video from ${c.auth.member.name} 🎬` },
    body: { de: 'Ein neuer gemeinsamer Moment wartet.', en: 'A new shared moment is waiting.' },
    link: 'sooodreamy://videos',
  });
  sendJson(c.res, 201, { video: serialized });
});

route('GET', '/api/videos', { auth: true }, (c) => {
  sendJson(c.res, 200, { videos: videosOf(c.auth.couple).slice().reverse().map(serializeVideo) });
});

// Streaming endpoint — serveFile handles Range requests (206/416), which is
// what AVPlayer needs for seeking without downloading the whole file.
route('GET', '/api/videos/:id/raw', { auth: true }, async (c) => {
  const video = videosOf(c.auth.couple).find((v) => v.id === c.params.id);
  if (!video) throw httpError(404, 'not_found', 'Unknown video');
  await serveFile(c.req, c.res, c.store.mediaPath('videos', `${video.id}.mp4`), 'video/mp4');
});

route('POST', '/api/videos/:id/thumb', { auth: true }, async (c) => {
  const video = videosOf(c.auth.couple).find((v) => v.id === c.params.id);
  if (!video) throw httpError(404, 'not_found', 'Unknown video');
  if (video.uploaderId !== c.auth.memberId) {
    throw httpError(403, 'not_yours', 'Only the uploader may add a thumbnail');
  }
  const buf = await readBody(c.req, LIMITS.thumb);
  if (buf.length === 0) throw httpError(400, 'empty_body', 'Thumbnail upload body is empty');
  await c.store.saveMedia('videos', `${video.id}.thumb.jpg`, buf);
  video.thumbUrl = `/api/videos/${video.id}/thumb/raw`;
  c.store.markDirty();
  const serialized = serializeVideo(video);
  c.realtime.broadcastCouple(c.auth.coupleId, 'video_updated', { video: serialized });
  sendJson(c.res, 200, { video: serialized });
});

route('GET', '/api/videos/:id/thumb/raw', { auth: true }, async (c) => {
  const video = videosOf(c.auth.couple).find((v) => v.id === c.params.id);
  if (!video) throw httpError(404, 'not_found', 'Unknown video');
  if (!video.thumbUrl) throw httpError(404, 'no_thumb', 'This video has no thumbnail');
  await serveFile(c.req, c.res, c.store.mediaPath('videos', `${video.id}.thumb.jpg`), 'image/jpeg');
});

route('POST', '/api/videos/:id/favorite', { auth: true }, (c) => {
  const video = videosOf(c.auth.couple).find((v) => v.id === c.params.id);
  if (!video) throw httpError(404, 'not_found', 'Unknown video');
  if (!video.favorites) video.favorites = [];
  const at = video.favorites.indexOf(c.auth.memberId);
  if (at === -1) video.favorites.push(c.auth.memberId);
  else video.favorites.splice(at, 1);
  if (video.favorites.length === 0) delete video.favorites;
  c.store.markDirty();
  const serialized = serializeVideo(video);
  c.realtime.broadcastCouple(c.auth.coupleId, 'video_updated', { video: serialized });
  sendJson(c.res, 200, { video: serialized });
});

// The gallery is shared: BOTH partners may edit the caption or delete.
route('PATCH', '/api/videos/:id', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
  const video = videosOf(c.auth.couple).find((v) => v.id === c.params.id);
  if (!video) throw httpError(404, 'not_found', 'Unknown video');
  if ('caption' in body) {
    video.caption = body.caption === null ? null : asString(body.caption, 'caption', { max: LIMITS.text, nonEmpty: false });
  }
  c.store.markDirty();
  const serialized = serializeVideo(video);
  c.realtime.broadcastCouple(c.auth.coupleId, 'video_updated', { video: serialized });
  sendJson(c.res, 200, { video: serialized });
});

route('DELETE', '/api/videos/:id', { auth: true }, async (c) => {
  const videos = videosOf(c.auth.couple);
  const idx = videos.findIndex((v) => v.id === c.params.id);
  if (idx === -1) throw httpError(404, 'not_found', 'Unknown video');
  const [video] = videos.splice(idx, 1);
  await c.store.deleteMedia('videos', `${video.id}.mp4`);
  await c.store.deleteMedia('videos', `${video.id}.thumb.jpg`);
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'video_deleted', { id: video.id });
  sendJson(c.res, 200, { ok: true });
});

// --- spicy vault (v2.0) ----------------------------------------------------------
// End-to-end encrypted: every body here is an opaque AES-GCM blob sealed on
// the clients. The server stores bytes + a public KDF config, nothing more.
// Vault items NEVER appear in stats, the inbox or the widget snapshot.

route('GET', '/api/vault/config', { auth: true }, (c) => {
  sendJson(c.res, 200, { config: vaultOf(c.auth.couple).config });
});

// Sets the KDF parameters + PIN verifier. To protect existing items from a
// key mismatch, overwriting an existing config requires an empty vault
// (reset first) — first write wins otherwise.
route('PUT', '/api/vault/config', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
  const vault = vaultOf(c.auth.couple);
  if (vault.config && vault.items.length > 0) {
    throw httpError(409, 'vault_locked_in', 'Vault already configured — reset it before changing the key');
  }
  const config = {
    kdf: asEnum(body.kdf ?? 'pbkdf2-sha256', 'kdf', ['pbkdf2-sha256']),
    iterations: Number.isInteger(body.iterations) && body.iterations >= 10000 && body.iterations <= 10000000
      ? body.iterations
      : (() => { throw httpError(400, 'bad_iterations', '"iterations" must be an integer between 10k and 10M'); })(),
    salt: asString(body.salt, 'salt', { max: LIMITS.vaultConfigField }),
    verifier: asString(body.verifier, 'verifier', { max: LIMITS.vaultConfigField }),
    createdBy: c.auth.memberId,
    createdAt: nowIso(),
  };
  vault.config = config;
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'vault_config_set', { config });
  sendJson(c.res, 200, { config });
});

route('GET', '/api/vault', { auth: true }, (c) => {
  sendJson(c.res, 200, { items: vaultOf(c.auth.couple).items.slice().reverse() });
});

route('POST', '/api/vault/items', { auth: true }, async (c) => {
  const vault = vaultOf(c.auth.couple);
  if (!vault.config) throw httpError(409, 'vault_not_configured', 'Set the vault key first (PUT /api/vault/config)');
  if (vault.items.length >= LIMITS.vaultItems) {
    throw httpError(413, 'too_many_items', `At most ${LIMITS.vaultItems} vault items per couple — delete some first`);
  }
  const kind = asEnum(c.req.headers['x-vault-kind'] ?? 'photo', 'X-Vault-Kind', VAULT_KINDS);
  const buf = await readBody(c.req, LIMITS.vaultItem);
  if (buf.length === 0) throw httpError(400, 'empty_body', 'Vault upload body is empty');
  const itemId = id('vt');
  const reservation = c.store.reserveMedia({
    bytes: buf.length,
    coupleId: c.auth.coupleId,
    collection: 'vault',
    currentCount: vault.items.length,
    limit: LIMITS.vaultItems,
    limitCode: 'too_many_items',
    limitMessage: `At most ${LIMITS.vaultItems} vault items per couple — delete some first`,
  });
  let item;
  try {
    await c.store.saveMedia('vault', `${itemId}.bin`, buf, reservation);
    item = {
      id: itemId,
      uploaderId: c.auth.memberId,
      kind,
      url: `/api/vault/${itemId}/raw`,
      bytes: buf.length,
      createdAt: nowIso(),
    };
    vault.items.push(item);
    c.store.markDirty();
  } finally {
    reservation.release();
  }
  c.realtime.broadcastCouple(c.auth.coupleId, 'vault_item_added', { item });
  sendJson(c.res, 201, { item });
});

route('GET', '/api/vault/:id/raw', { auth: true }, async (c) => {
  const item = vaultOf(c.auth.couple).items.find((v) => v.id === c.params.id);
  if (!item) throw httpError(404, 'not_found', 'Unknown vault item');
  await serveFile(c.req, c.res, c.store.mediaPath('vault', `${item.id}.bin`), 'application/octet-stream');
});

// The vault is shared: BOTH partners may delete any item.
route('DELETE', '/api/vault/:id', { auth: true }, async (c) => {
  const vault = vaultOf(c.auth.couple);
  const idx = vault.items.findIndex((v) => v.id === c.params.id);
  if (idx === -1) throw httpError(404, 'not_found', 'Unknown vault item');
  const [item] = vault.items.splice(idx, 1);
  await c.store.deleteMedia('vault', `${item.id}.bin`);
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'vault_item_deleted', { id: item.id });
  sendJson(c.res, 200, { ok: true });
});

// Nuclear option for a forgotten PIN: wipes config + every item.
route('DELETE', '/api/vault', { auth: true }, async (c) => {
  const vault = vaultOf(c.auth.couple);
  for (const item of vault.items) {
    await c.store.deleteMedia('vault', `${item.id}.bin`);
  }
  vault.items = [];
  vault.config = null;
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'vault_reset', {});
  sendJson(c.res, 200, { ok: true });
});

// --- events ----------------------------------------------------------------------

// Sync contract e: calendar events carry a revision counter `rev` (starts at
// 1, +1 per mutation). Mutations may send `ifRev` for optimistic concurrency
// — a mismatch answers 409 conflict WITH the current resource, so two
// offline edits no longer overwrite each other silently. Without `ifRev`
// the old last-write-wins behavior stays (backward compatible).

/** Pre-contract stores lack `rev` — default it on the way out. */
function eventView(event) {
  return { ...event, rev: event.rev ?? 1 };
}

/**
 * Validates an optional `ifRev` body field against the resource's current
 * revision. Returns `true` when the mutation may proceed; on a mismatch the
 * 409 conflict answer (with the CURRENT resource) has already been sent.
 */
function checkIfRev(c, body, currentRev, currentResource) {
  if (body.ifRev === undefined || body.ifRev === null) return true;
  if (!Number.isInteger(body.ifRev) || body.ifRev < 1) {
    throw httpError(400, 'invalid_request', '"ifRev" must be a positive integer');
  }
  if (body.ifRev === currentRev) return true;
  sendJson(c.res, 409, {
    error: 'conflict',
    message: `The resource is at rev ${currentRev} — merge with "current" and retry`,
    current: currentResource,
  });
  return false;
}

route('GET', '/api/events', { auth: true }, (c) => {
  sendJson(c.res, 200, { events: c.auth.couple.events.map(eventView) });
});

route('POST', '/api/events', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
  const event = {
    id: id('ev'),
    title: asString(body.title, 'title', { max: 200 }),
    emoji: body.emoji == null ? null : asString(body.emoji, 'emoji', { max: 32 }),
    date: asDateKey(body.date, 'date'),
    repeatsYearly: Boolean(body.repeatsYearly),
    createdBy: c.auth.memberId,
    createdAt: nowIso(),
    rev: 1,
  };
  c.auth.couple.events.push(event);
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'event_added', { event: eventView(event) });
  sendJson(c.res, 201, { event: eventView(event) });
});

route('PATCH', '/api/events/:id', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
  const event = c.auth.couple.events.find((e) => e.id === c.params.id);
  if (!event) throw httpError(404, 'not_found', 'Unknown event');
  if (!checkIfRev(c, body, event.rev ?? 1, eventView(event))) return;
  if ('title' in body) event.title = asString(body.title, 'title', { max: 200 });
  if ('emoji' in body) event.emoji = body.emoji === null ? null : asString(body.emoji, 'emoji', { max: 32 });
  if ('date' in body) event.date = asDateKey(body.date, 'date');
  if ('repeatsYearly' in body) event.repeatsYearly = Boolean(body.repeatsYearly);
  event.rev = (event.rev ?? 1) + 1;
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'event_updated', { event: eventView(event) });
  sendJson(c.res, 200, { event: eventView(event) });
});

route('DELETE', '/api/events/:id', { auth: true }, (c) => {
  const idx = c.auth.couple.events.findIndex((e) => e.id === c.params.id);
  if (idx === -1) throw httpError(404, 'not_found', 'Unknown event');
  const [event] = c.auth.couple.events.splice(idx, 1);
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'event_deleted', { id: event.id });
  sendJson(c.res, 200, { ok: true });
});

// --- bucket list -------------------------------------------------------------------

route('GET', '/api/bucket', { auth: true }, (c) => {
  sendJson(c.res, 200, { items: c.auth.couple.bucket });
});

route('POST', '/api/bucket', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
  const item = {
    id: id('b'),
    text: asText(body.text, 'text'),
    emoji: body.emoji == null ? null : asString(body.emoji, 'emoji', { max: 32 }),
    done: false,
    doneAt: null,
    createdBy: c.auth.memberId,
    createdAt: nowIso(),
  };
  c.auth.couple.bucket.push(item);
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'bucket_added', { item });
  sendJson(c.res, 201, { item });
});

route('PATCH', '/api/bucket/:id', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
  const item = c.auth.couple.bucket.find((b) => b.id === c.params.id);
  if (!item) throw httpError(404, 'not_found', 'Unknown bucket item');
  if ('text' in body) item.text = asText(body.text, 'text');
  if ('emoji' in body) item.emoji = body.emoji === null ? null : asString(body.emoji, 'emoji', { max: 32 });
  if ('done' in body) {
    const done = Boolean(body.done);
    item.done = done;
    item.doneAt = done ? (item.doneAt ?? nowIso()) : null;
  }
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'bucket_updated', { item });
  sendJson(c.res, 200, { item });
});

route('DELETE', '/api/bucket/:id', { auth: true }, (c) => {
  const idx = c.auth.couple.bucket.findIndex((b) => b.id === c.params.id);
  if (idx === -1) throw httpError(404, 'not_found', 'Unknown bucket item');
  const [item] = c.auth.couple.bucket.splice(idx, 1);
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'bucket_deleted', { id: item.id });
  sendJson(c.res, 200, { ok: true });
});

// --- love coupons ------------------------------------------------------------------

/** Keeps the list at `max`: oldest REDEEMED coupons go first, then oldest overall. Returns the evicted ones. */
function pruneCoupons(list, max) {
  const evicted = [];
  while (list.length > max) {
    const redeemedIdx = list.findIndex((cp) => cp.redeemedAt); // list is chronological
    evicted.push(...list.splice(redeemedIdx === -1 ? 0 : redeemedIdx, 1));
  }
  return evicted;
}

function findCoupon(couple, couponId) {
  const coupon = couponsOf(couple).find((cp) => cp.id === couponId);
  if (!coupon) throw httpError(404, 'not_found', 'Unknown coupon');
  return coupon;
}

route('GET', '/api/coupons', { auth: true }, (c) => {
  sendJson(c.res, 200, { coupons: couponsOf(c.auth.couple).slice().reverse().map(serializeCoupon) });
});

route('POST', '/api/coupons', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
  const partner = partnerOf(c.auth.couple, c.auth.memberId);
  if (!partner) throw httpError(409, 'no_partner', 'Coupons need a partner to receive them');
  const coupon = {
    id: id('cp'),
    title: asString(body.title, 'title', { max: LIMITS.couponTitle }),
    emoji: asString(body.emoji, 'emoji', { max: LIMITS.couponEmoji }),
    note: body.note == null ? null : asString(body.note, 'note', { max: LIMITS.couponNote, nonEmpty: false }),
    createdBy: c.auth.memberId,
    forMember: partner.id,
    redeemedAt: null,
    expiresAt: asExpiresAt(body.expiresAt),
    createdAt: nowIso(),
  };
  const list = couponsOf(c.auth.couple);
  list.push(coupon);
  const evicted = pruneCoupons(list, LIMITS.coupons);
  c.store.markDirty();
  // Evictions first, so clients applying frames in order never exceed the cap.
  for (const old of evicted) c.realtime.broadcastCouple(c.auth.coupleId, 'coupon_deleted', { id: old.id });
  const serialized = serializeCoupon(coupon);
  c.realtime.broadcastCouple(c.auth.coupleId, 'coupon_added', { coupon: serialized });
  queuePartnerPush(c, {
    type: 'coupon',
    title: { de: `Gutschein von ${c.auth.member.name}`, en: `Coupon from ${c.auth.member.name}` },
    body: { de: 'Ein neuer Liebesgutschein wartet.', en: 'A new love coupon is waiting.' },
    link: 'sooodreamy://coupons',
  });
  sendJson(c.res, 201, { coupon: serialized });
});

route('POST', '/api/coupons/:id/redeem', { auth: true }, (c) => {
  const coupon = findCoupon(c.auth.couple, c.params.id);
  if (coupon.forMember !== c.auth.memberId) {
    throw httpError(403, 'not_yours', 'Only the receiving member may redeem this coupon');
  }
  if (coupon.redeemedAt) throw httpError(409, 'already_redeemed', 'This coupon was already redeemed');
  if (coupon.expiresAt && Date.parse(coupon.expiresAt) < Date.now()) {
    throw httpError(409, 'expired', 'This coupon has expired');
  }
  coupon.redeemedAt = nowIso();
  c.store.markDirty();
  const serialized = serializeCoupon(coupon);
  c.realtime.broadcastCouple(c.auth.coupleId, 'coupon_redeemed', { coupon: serialized });
  sendJson(c.res, 200, { coupon: serialized });
});

route('DELETE', '/api/coupons/:id', { auth: true }, (c) => {
  const list = couponsOf(c.auth.couple);
  const coupon = findCoupon(c.auth.couple, c.params.id);
  if (coupon.createdBy !== c.auth.memberId) {
    throw httpError(403, 'not_yours', 'Only the creator may delete a coupon');
  }
  if (coupon.redeemedAt) throw httpError(409, 'already_redeemed', 'Redeemed coupons cannot be deleted');
  list.splice(list.indexOf(coupon), 1);
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'coupon_deleted', { id: coupon.id });
  sendJson(c.res, 200, { ok: true });
});

// --- shared soundtrack (songs) -------------------------------------------------------

function findSong(couple, songId) {
  const song = songsOf(couple).find((s) => s.id === songId);
  if (!song) throw httpError(404, 'not_found', 'Unknown song');
  return song;
}

route('GET', '/api/songs', { auth: true }, (c) => {
  sendJson(c.res, 200, { songs: songsOf(c.auth.couple).slice().reverse() });
});

route('POST', '/api/songs', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
  const song = {
    id: id('sg'),
    title: asSongTitle(body.title),
    artist: asSongField(body.artist, 'artist', LIMITS.songArtist),
    note: asSongField(body.note, 'note', LIMITS.songNote),
    link: asSongField(body.link, 'link', LIMITS.songLink),
    addedBy: c.auth.memberId,
    heartedBy: [],
    createdAt: nowIso(),
  };
  const list = songsOf(c.auth.couple);
  list.push(song);
  const evicted = capList(list, LIMITS.songs);
  c.store.markDirty();
  // Evictions first, so clients applying frames in order never exceed the cap.
  for (const old of evicted) c.realtime.broadcastCouple(c.auth.coupleId, 'song_deleted', { id: old.id });
  c.realtime.broadcastCouple(c.auth.coupleId, 'song_added', { song });
  sendJson(c.res, 201, { song });
});

route('PATCH', '/api/songs/:id', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
  const song = findSong(c.auth.couple, c.params.id);
  if (song.addedBy !== c.auth.memberId) {
    throw httpError(403, 'not_yours', 'Only the member who added a song may edit it');
  }
  if ('title' in body) song.title = asSongTitle(body.title); // title can never be cleared
  if ('artist' in body) song.artist = asSongField(body.artist, 'artist', LIMITS.songArtist);
  if ('note' in body) song.note = asSongField(body.note, 'note', LIMITS.songNote);
  if ('link' in body) song.link = asSongField(body.link, 'link', LIMITS.songLink);
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'song_updated', { song });
  sendJson(c.res, 200, { song });
});

route('POST', '/api/songs/:id/heart', { auth: true }, (c) => {
  const song = findSong(c.auth.couple, c.params.id);
  const at = song.heartedBy.indexOf(c.auth.memberId);
  if (at === -1) song.heartedBy.push(c.auth.memberId);
  else song.heartedBy.splice(at, 1);
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'song_updated', { song });
  sendJson(c.res, 200, { song });
});

route('DELETE', '/api/songs/:id', { auth: true }, (c) => {
  const list = songsOf(c.auth.couple);
  const song = findSong(c.auth.couple, c.params.id);
  if (song.addedBy !== c.auth.memberId) {
    throw httpError(403, 'not_yours', 'Only the member who added a song may delete it');
  }
  list.splice(list.indexOf(song), 1);
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'song_deleted', { id: song.id });
  sendJson(c.res, 200, { ok: true });
});

// --- daily question ------------------------------------------------------------------

// Journal list: every day where at least one member answered, newest first.
// The plain `/api/daily` path (2 segments) never clashes with `/api/daily/:dateKey` (3 segments).
route('GET', '/api/daily', { auth: true }, (c) => {
  const limit = queryInt(c.url, 'limit', 60, 1, 366);
  const couple = c.auth.couple;
  const dateKeys = Object.keys(couple.daily)
    .filter((key) => Object.values(couple.daily[key]?.answers ?? {}).some((a) => a?.text != null))
    .sort()
    .reverse()
    .slice(0, limit);
  sendJson(c.res, 200, { entries: dateKeys.map((key) => dailyEntryFor(couple, key, c.auth.memberId)) });
});

route('GET', '/api/daily/:dateKey', { auth: true }, (c) => {
  const dateKey = asDateKey(c.params.dateKey, 'dateKey');
  sendJson(c.res, 200, dailyEntryFor(c.auth.couple, dateKey, c.auth.memberId));
});

route('POST', '/api/daily/:dateKey', { auth: true }, async (c) => {
  const dateKey = asDateKey(c.params.dateKey, 'dateKey');
  const today = todayKey();
  if (dateKey !== today && dateKey !== prevDateKey(today) && dateKey !== nextDateKey(today)) {
    throw httpError(400, 'bad_datekey', 'Daily answers are accepted only for server-today ±1 day');
  }
  const body = await readJsonObject(c.req);
  if (!Number.isInteger(body.questionId)) throw httpError(400, 'invalid_request', '"questionId" must be an integer');
  const text = asText(body.text, 'text');
  const questionText = asDailyQuestionText(body.questionText);
  const couple = c.auth.couple;
  const opKey = operationKey(c, 'daily-answer', dateKey, clientOperationId(body));
  if (hasClientOperation(couple, opKey)) {
    sendJson(c.res, 200, { ...dailyEntryFor(couple, dateKey, c.auth.memberId), duplicate: true });
    return;
  }
  if (!couple.daily[dateKey]) couple.daily[dateKey] = { questionId: null, answers: {} };
  const rec = couple.daily[dateKey];
  if (bothAnsweredOn(couple, dateKey) && rec.answers[c.auth.memberId]) {
    throw httpError(409, 'daily_revealed', 'Revealed daily answers are immutable');
  }
  if (rec.questionId == null) {
    rec.questionId = body.questionId;
    // Schlussrunde 5: only the PINNING answer stores the rendered text —
    // later answers must agree on the id anyway, so a divergent text can
    // never rewrite what the couple actually saw.
    rec.questionText = questionText;
  }
  // Schlussrunde 4 (Bugs): the first answer pins the question — a follow-up
  // answer for a DIFFERENT question (pool-growth race between two devices)
  // must not be silently filed under the pinned one. 409 carries the
  // authoritative id (and stored text, Schlussrunde 5) so the loser can
  // re-render the pinned question even when its pool doesn't know the id.
  if (body.questionId !== rec.questionId) {
    // The message doubles as guidance for clients too old to adopt the
    // details (Schlussrunde 6): they surface it raw, so it must say WHAT
    // to do instead of describing internals.
    const err = httpError(
      409,
      'daily_question_mismatch',
      'The first answer already set today\'s question — pull to refresh and answer the shown question, or update the app if a different one keeps appearing',
    );
    err.details = { questionId: rec.questionId, questionText: rec.questionText ?? null };
    throw err;
  }
  // v7.0: pin the (deterministic) custom-day question onto the record with
  // the first answer, so later pool edits cannot change an asked question.
  snapshotCustomQuestion(couple, dateKey);
  const previous = rec.answers[c.auth.memberId];
  rec.answers[c.auth.memberId] = {
    text,
    answeredAt: previous?.answeredAt ?? nowIso(),
    ...(previous ? { editedAt: nowIso() } : {}),
  };
  rememberClientOperation(couple, opKey);
  c.store.markDirty();
  for (const member of couple.members) {
    c.realtime.sendToMember(couple.id, member.id, 'daily_answer', dailyEntryFor(couple, dateKey, member.id));
  }
  // The two answers are different events: the FIRST nudges the partner who
  // still owes theirs; the SECOND is the announcement that the reveal
  // ceremony can start. Answer text never enters the push (spoiler-safe).
  if (bothAnsweredOn(couple, dateKey)) {
    queuePartnerPush(c, {
      type: 'daily_reveal',
      title: { de: 'Frage des Tages', en: 'Question of the day' },
      body: {
        de: 'Ihr habt beide geantwortet. Bereit zum Aufdecken? ✨',
        en: 'You both answered. Ready to reveal? ✨',
      },
      link: 'sooodreamy://daily',
    });
  } else {
    queuePartnerPush(c, {
      type: 'daily',
      title: { de: 'Frage des Tages', en: 'Question of the day' },
      body: {
        de: `${c.auth.member.name} hat geantwortet — deine fehlt noch 🤫`,
        en: `${c.auth.member.name} answered — yours is still missing 🤫`,
      },
      link: 'sooodreamy://daily',
    });
  }
  sendJson(c.res, 200, dailyEntryFor(couple, dateKey, c.auth.memberId));
});

// --- wordle duel ---------------------------------------------------------------------

// History: one day view per stored dateKey that has at least one result in the
// requested language, newest first. The plain `/api/wordle` path (2 segments)
// never clashes with `/api/wordle/:dateKey` (3 segments).
route('GET', '/api/wordle', { auth: true }, (c) => {
  const lang = c.url.searchParams.get('lang');
  if (!WORDLE_LANGS.includes(lang)) {
    throw httpError(400, 'bad_lang', `"lang" query param is required and must be one of: ${WORDLE_LANGS.join(', ')}`);
  }
  const limit = queryInt(c.url, 'limit', 30, 1, 60);
  const couple = c.auth.couple;
  const dateKeys = Object.keys(couple.wordle ?? {})
    .filter((key) => Object.keys(wordleDay(couple, key)?.[lang] ?? {}).length > 0)
    .sort()
    .reverse()
    .slice(0, limit);
  sendJson(c.res, 200, { days: dateKeys.map((key) => wordleViewFor(couple, key, lang, c.auth.memberId)) });
});

route('GET', '/api/wordle/:dateKey', { auth: true }, (c) => {
  const dateKey = asDateKey(c.params.dateKey, 'dateKey');
  const lang = c.url.searchParams.get('lang');
  if (!WORDLE_LANGS.includes(lang)) {
    throw httpError(400, 'bad_lang', `"lang" query param is required and must be one of: ${WORDLE_LANGS.join(', ')}`);
  }
  sendJson(c.res, 200, wordleViewFor(c.auth.couple, dateKey, lang, c.auth.memberId));
});

route('POST', '/api/wordle/:dateKey', { auth: true }, async (c) => {
  const dateKey = asDateKey(c.params.dateKey, 'dateKey');
  // Submits are only accepted for server-today ±1 day (UTC) — timezones may
  // straddle midnight, but a week-old or far-future result is bogus.
  const today = todayKey();
  if (dateKey !== today && dateKey !== prevDateKey(today) && dateKey !== nextDateKey(today)) {
    throw httpError(400, 'bad_datekey', `"dateKey" must be within one day of the server date (${today})`);
  }
  const body = await readJsonObject(c.req);
  if (!Number.isInteger(body.rows) || body.rows < 1 || body.rows > 6) {
    throw httpError(400, 'invalid_request', '"rows" must be an integer between 1 and 6');
  }
  if (typeof body.win !== 'boolean') throw httpError(400, 'invalid_request', '"win" must be a boolean');
  const grid = asString(body.grid, 'grid', { max: LIMITS.wordleGrid });
  const lang = asEnum(body.lang, 'lang', WORDLE_LANGS);
  const couple = c.auth.couple;
  const wordle = wordleOf(couple);
  const day = wordleDay(couple, dateKey) ?? (wordle[dateKey] = {});
  const byMember = day[lang] ?? (day[lang] = {});
  if (!byMember[c.auth.memberId]) {
    // First submit per (member, dateKey, lang) wins — resubmits are idempotent and never overwrite.
    byMember[c.auth.memberId] = {
      memberId: c.auth.memberId,
      rows: body.rows,
      win: body.win,
      grid,
      lang,
      finishedAt: nowIso(),
    };
    const keys = Object.keys(wordle);
    if (keys.length > LIMITS.wordleDays) {
      keys.sort();
      for (const old of keys.slice(0, keys.length - LIMITS.wordleDays)) delete wordle[old];
    }
    c.store.markDirty();
    for (const member of couple.members) {
      c.realtime.sendToMember(couple.id, member.id, 'wordle_result', wordleViewFor(couple, dateKey, lang, member.id));
    }
  }
  sendJson(c.res, 200, wordleViewFor(couple, dateKey, lang, c.auth.memberId));
});

// --- canvas -----------------------------------------------------------------------------

// Sync contract f: the shared board carries a `generation` counter (starts
// at 1, +1 per clear). Stroke commits may send their generation — a stale
// one (the partner cleared while the stroke was in flight / queued for
// retry) answers 409 stale_generation instead of resurrecting dead ink.
// Without `generation` in the body the old behavior stays.

/** Pre-contract stores lack the counter — they are at generation 1. */
function canvasGenerationOf(couple) {
  return couple.canvasGeneration ?? 1;
}

route('GET', '/api/canvas', { auth: true }, (c) => {
  const limit = queryInt(c.url, 'limit', null, 1, 500);
  const strokes = c.auth.couple.strokes;
  sendJson(c.res, 200, {
    strokes: limit === null ? strokes : strokes.slice(-limit),
    generation: canvasGenerationOf(c.auth.couple),
  });
});

route('POST', '/api/canvas/strokes', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
  const generation = canvasGenerationOf(c.auth.couple);
  if (body.generation !== undefined && body.generation !== null) {
    if (!Number.isInteger(body.generation) || body.generation < 1) {
      throw httpError(400, 'invalid_request', '"generation" must be a positive integer');
    }
    if (body.generation !== generation) {
      sendJson(c.res, 409, {
        error: 'stale_generation',
        message: 'The board was cleared while this stroke was in flight — drop the retry',
        generation,
      });
      return;
    }
  }
  const points = body.points;
  if (!Array.isArray(points) || points.length === 0) {
    throw httpError(400, 'invalid_points', '"points" must be a non-empty array of [x, y] pairs');
  }
  if (points.length > LIMITS.strokePoints) {
    throw httpError(400, 'too_many_points', `A stroke may have at most ${LIMITS.strokePoints} points`);
  }
  for (const p of points) {
    if (!Array.isArray(p) || p.length !== 2 || !Number.isFinite(p[0]) || !Number.isFinite(p[1])) {
      throw httpError(400, 'invalid_points', 'Each point must be a [x, y] pair of numbers');
    }
  }
  const width = body.width === undefined ? 4 : body.width;
  if (!Number.isFinite(width) || width <= 0) throw httpError(400, 'invalid_request', '"width" must be a positive number');
  const stroke = {
    id: id('s'),
    memberId: c.auth.memberId,
    color: body.color === undefined ? '#FFFFFF' : asString(body.color, 'color', { max: 32 }),
    width,
    tool: body.tool === undefined ? 'pen' : asString(body.tool, 'tool', { max: 32 }),
    points,
    createdAt: nowIso(),
  };
  c.auth.couple.strokes.push(stroke);
  capList(c.auth.couple.strokes, LIMITS.strokes);
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'canvas_stroke', { stroke, generation });
  sendJson(c.res, 201, { stroke, generation });
});

route('DELETE', '/api/canvas/strokes/:id', { auth: true }, (c) => {
  const strokes = c.auth.couple.strokes;
  const idx = strokes.findIndex((s) => s.id === c.params.id);
  if (idx === -1) throw httpError(404, 'not_found', 'Unknown stroke');
  if (strokes[idx].memberId !== c.auth.memberId) {
    throw httpError(403, 'not_yours', 'Only the author may delete a stroke');
  }
  const [stroke] = strokes.splice(idx, 1);
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'canvas_stroke_deleted', { id: stroke.id });
  sendJson(c.res, 200, { ok: true });
});

route('DELETE', '/api/canvas', { auth: true }, (c) => {
  c.auth.couple.strokes = [];
  c.auth.couple.canvasGeneration = canvasGenerationOf(c.auth.couple) + 1;
  c.store.markDirty();
  // `by` = clear attribution: the partner's client can say WHO wiped the
  // shared board instead of it silently going blank. `generation` lets
  // clients drop in-flight/retried strokes of the wiped board.
  c.realtime.broadcastCouple(c.auth.coupleId, 'canvas_clear', {
    by: c.auth.memberId,
    generation: c.auth.couple.canvasGeneration,
  });
  sendJson(c.res, 200, { ok: true, generation: c.auth.couple.canvasGeneration });
});

// --- games ---------------------------------------------------------------------------------

route('POST', '/api/games', { auth: true }, async (c) => {
  c.rateLimiter.consume('gameCreate', c.auth.memberId);
  const body = await readJsonObject(c.req);
  const type = asEnum(body.type, 'type', GAME_TYPES);
  const couple = c.auth.couple;
  if (openGames(couple).length >= LIMITS.openGames) {
    throw httpError(429, 'too_many_open_games', `At most ${LIMITS.openGames} games may be open per couple`);
  }
  // Parallel sessions are allowed across types, but an active same-type
  // session cannot be silently destroyed by either client. A creator may
  // replace their own untouched lobby.
  for (const existing of couple.games) {
    if (existing.type !== type || existing.state === 'ended') continue;
    if (existing.state === 'active' || existing.createdBy !== c.auth.memberId) {
      throw httpError(409, 'game_in_progress', `An open ${type} session already exists`);
    }
    existing.result = { cancelled: true, replacedBy: c.auth.memberId };
    finishGame(couple, existing);
  }
  const payload = prepareGamePayload(type, body.payload, couple);
  // v3.0.1 server seed (EVAL-3.0 P0): EVERY session gets a server-generated
  // random seed — a client-provided seed is DISCARDED. A client choosing its
  // own seed knows the Kniffel dice / deck shuffle in advance; the 3.0
  // "keeps a client seed" behavior was a cheat vector, not a feature.
  // `seedServer` marks the seed as server-made (pre-3.0.1 lobbies without
  // the marker are re-seeded once on join — see the join route).
  payload.seed = newSeed();
  payload.seedServer = true;
  Object.assign(payload, finalizeGamePayload(type, payload));
  // Daily quests are keyed by day; the dateKey feeds the couple-level
  // quest_done dedupe, so it must be a real date near the server date
  // (mirrors the check-in window) — no XP farming via invented day strings.
  if (type === 'dailyquests') {
    const today = todayKey();
    const dateKey = payload.dateKey === undefined ? today : asDateKey(payload.dateKey, 'dateKey');
    if (dateKey !== today && dateKey !== prevDateKey(today) && dateKey !== nextDateKey(today)) {
      throw httpError(400, 'bad_datekey', `"dateKey" must be within one day of the server date (${today})`);
    }
    payload.dateKey = dateKey;
  }
  const game = {
    id: id('g'),
    type,
    state: 'lobby',
    createdBy: c.auth.memberId,
    payload,
    result: null,
    rulesVersion: CURRENT_GAME_RULES_VERSION,
    resultAuthority: 'server',
    moves: [],
    createdAt: nowIso(),
  };
  couple.games.push(game);
  // Evicting the oldest sessions is safe for the biography numbers:
  // finished games were already counted into the persistent
  // `couple.gamesAggregate` (recordGameEnd) before they can roll off here.
  capList(couple.games, LIMITS.games);
  c.store.markDirty();
  c.realtime.broadcastCouple(couple.id, 'game_created', { game: serializeGame(game, couple) });
  // Invitation push: without it the whole invite flow dies as soon as the
  // partner is offline (the socket broadcast reaches nobody). `dailyquests`
  // is a self-started shared checklist, not an invitation.
  if (type !== 'dailyquests' && partnerOf(couple, c.auth.memberId)) {
    queuePartnerPush(c, {
      type: 'game',
      title: {
        de: `Spiel-Einladung von ${c.auth.member.name} 🎮`,
        en: `Game invite from ${c.auth.member.name} 🎮`,
      },
      body: { de: 'Machst du mit?', en: 'Are you in?' },
      link: `sooodreamy://game/${game.id}`,
    });
  }
  sendJson(c.res, 201, { game: serializeGame(game, couple) });
});

route('POST', '/api/games/:id/join', { auth: true }, (c) => {
  const game = findGame(c.auth.couple, c.params.id);
  if (game.state === 'ended') throw httpError(409, 'game_ended', 'This game has already ended');
  if (game.state === 'lobby') {
    if (c.auth.couple.members.length !== 2) {
      throw httpError(409, 'partner_required', 'A second member is required to start this game');
    }
    if (game.type !== 'dailyquests' && game.createdBy === c.auth.memberId) {
      throw httpError(403, 'wrong_actor', 'The invited partner must start this session');
    }
    // v3.0.1 migration: lobbies created BEFORE the server-seed contract may
    // still carry a client-chosen seed. Moves only exist once a game is
    // active, so re-seeding here is always safe — nothing was derived yet.
    // Both clients adopt the fresh payload from the `game_started` frame.
    if (game.payload && !game.payload.seedServer) {
      game.payload.seed = newSeed();
      game.payload.seedServer = true;
    }
    game.state = 'active';
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'game_started', { game: serializeGame(game, c.auth.couple) });
  }
  sendJson(c.res, 200, { game: serializeGame(game, c.auth.couple) });
});

// Input lease takeover (Welle 6): unconditionally moves the member's lease
// onto the calling device — the explicit "continue on THIS device" action a
// spectator device offers. The previous holder flips to spectator via the
// `game_lease` fanout to the member's own devices. Deliberately allowed in
// the lobby too (pre-claiming before the first move is harmless).
route('POST', '/api/games/:id/takeover', { auth: true }, (c) => {
  c.rateLimiter.consume('gameMove', c.auth.memberId);
  const game = findGame(c.auth.couple, c.params.id);
  if (game.state === 'ended') throw httpError(409, 'game_ended', 'This game has already ended');
  const result = takeoverGameLease(game, leaseIdentity(c));
  if (result.changed) {
    c.store.markDirty();
    broadcastLease(c, game, 'takeover', result.lease);
  }
  // Mirrors the `game_lease` frame payload (minus `reason`) so clients
  // reuse one decoder for both.
  sendJson(c.res, 200, { gameId: game.id, memberId: c.auth.memberId, lease: gameLeaseView(result.lease) });
});

route('POST', '/api/games/:id/move', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
  const game = findGame(c.auth.couple, c.params.id);
  // Sync contract b: the clientMoveId duplicate search runs BEFORE the state
  // check — a retried FINAL move (the response of the winning Gomoku stone
  // got lost, the game is 'ended' by now) must return the stored duplicate,
  // not a misleading 409 game_not_active.
  const clientMoveId = body.clientMoveId === undefined
    ? null
    : asString(body.clientMoveId, 'clientMoveId', { max: 128 });
  if (clientMoveId) {
    const existing = game.moves.find(
      (candidate) => candidate.memberId === c.auth.memberId && candidate.clientMoveId === clientMoveId,
    );
    if (existing) {
      sendJson(c.res, 200, {
        move: existing,
        game: serializeGame(game, c.auth.couple),
        duplicate: true,
        turnMemberId: gameTurnMemberId(game, c.auth.couple),
      });
      return;
    }
  }
  if (game.state !== 'active') throw httpError(409, 'game_not_active', 'Moves are only allowed in an active game');
  c.rateLimiter.consume('gameMove', c.auth.memberId);
  if (game.moves.length >= LIMITS.movesPerGame) {
    throw httpError(413, 'game_move_quota', `A game may store at most ${LIMITS.movesPerGame} moves`);
  }
  // Input lease (Welle 6): only ONE device of this member may drive the
  // session. A live foreign lease refuses with the holder attached (a dead
  // lease — session revoked/expired/evicted — never blocks). Checked AFTER
  // the clientMoveId dedupe on purpose: a retry of an already-stored move
  // must never bounce off the lease.
  const identity = leaseIdentity(c);
  const blocking = blockingGameLease(game, identity, (sessionId) =>
    isSessionLive(c.store, c.auth.memberId, sessionId));
  if (blocking) {
    const err = httpError(
      409,
      'game_lease_held',
      `Another device (${blocking.deviceName}) is playing this session — take over explicitly via POST /api/games/${game.id}/takeover`,
    );
    err.details = { gameId: game.id, lease: gameLeaseView(blocking) };
    throw err;
  }
  const data = validateGameMove({
    game,
    couple: c.auth.couple,
    memberId: c.auth.memberId,
    data: body.data,
  });
  annotateReveal(game, c.auth.memberId, data);
  // The lease is grabbed only by a VALID move (first move, or silent
  // inheritance from a dead session) — fanout to the member's own devices
  // precedes the move frame so spectators flip their banner first.
  const claim = claimGameLease(game, identity);
  if (claim.acquired) broadcastLease(c, game, 'acquired', claim.lease);
  const move = {
    id: id('mv'),
    memberId: c.auth.memberId,
    clientMoveId,
    data,
    createdAt: nowIso(),
  };
  // Whose move it was BEFORE this move applied — the turn push compares it
  // against the fresh derivation to spot handovers vs. extra moves.
  const previousTurnMemberId = gameTurnMemberId(game, c.auth.couple);
  game.moves.push(move);
  c.store.markDirty();
  // Sync contract c, live half: the move frame (and the 201) carry the
  // server-authoritative turn verdict AFTER this move — additive next to
  // gameId+move. Explicit null = nobody specific is up (finishing move,
  // simultaneous phase, checklist type). Without the field, clients fell
  // back to the "last mover" heuristic on every live move, which flips the
  // wrong way on extra moves (Mancala store landing, Käsekästchen box,
  // memoryduo match).
  const resolution = canonicalGameResult({ game, couple: c.auth.couple });
  const turnAfterMove = resolution.complete ? null : gameTurnMemberId(game, c.auth.couple);
  c.realtime.broadcastCouple(c.auth.coupleId, 'game_move', {
    gameId: game.id,
    move,
    turnMemberId: turnAfterMove,
  });
  maybeEmitGameAppEvent(c, game, move);
  if (resolution.complete) {
    game.result = resolution.result;
    finishGame(c.auth.couple, game);
    c.realtime.broadcastCouple(c.auth.coupleId, 'game_ended', { game: serializeGame(game, c.auth.couple) });
  }
  maybeQueueTurnPush(c, game, previousTurnMemberId, resolution.complete);
  sendJson(c.res, 201, {
    move,
    game: resolution.complete ? serializeGame(game, c.auth.couple) : undefined,
    turnMemberId: turnAfterMove,
  });
});

route('POST', '/api/games/:id/end', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req).catch((err) => {
    // Allow an empty body for "just end it".
    if (err instanceof HttpError && err.code === 'invalid_json') return {};
    throw err;
  });
  const game = findGame(c.auth.couple, c.params.id);
  if (game.state === 'ended') {
    sendJson(c.res, 200, { game: serializeGame(game, c.auth.couple) });
    return;
  }
  if (game.state === 'lobby') {
    // The invited partner may DECLINE an invitation (28#5) — a lobby no
    // longer sticks around until the creator gives up. Distinct results so
    // the creator's client can tell "I cancelled" from "they passed".
    game.result = game.createdBy === c.auth.memberId
      ? { cancelled: true, by: c.auth.memberId }
      : { declined: true, by: c.auth.memberId };
  } else {
    const resolution = canonicalGameResult({ game, couple: c.auth.couple });
    if (resolution.complete) {
      game.result = resolution.result;
    } else if (body.forfeit === true) {
      game.result = forfeitResult(game, c.auth.couple, c.auth.memberId);
    } else if (game.type === 'questions36' && body.complete === true) {
      game.result = { completedBy: c.auth.memberId };
    } else {
      throw httpError(409, 'game_incomplete', 'The server-derived game state is not complete');
    }
  }
  finishGame(c.auth.couple, game);
  c.realtime.broadcastCouple(c.auth.coupleId, 'game_ended', { game: serializeGame(game, c.auth.couple) });
  c.store.markDirty();
  sendJson(c.res, 200, { game: serializeGame(game, c.auth.couple) });
});

route('GET', '/api/games/active', { auth: true }, (c) => {
  const games = c.auth.couple.games;
  for (let i = games.length - 1; i >= 0; i--) {
    if (games[i].state === 'lobby' || games[i].state === 'active') {
      sendJson(c.res, 200, { game: serializeGame(games[i], c.auth.couple) });
      return;
    }
  }
  sendJson(c.res, 200, { game: null });
});

// v3.0 session list: every non-ended session (lobby/active), newest first —
// with parallel sessions per type, clients resume from this instead of the
// single `/active` (which stays for pre-v3.0 apps: latest open session).
route('GET', '/api/games/open', { auth: true }, (c) => {
  sendJson(c.res, 200, {
    games: openGames(c.auth.couple).slice().reverse().map((game) => serializeGame(game, c.auth.couple)),
  });
});

route('GET', '/api/games/season', { auth: true }, (c) => {
  const month = c.url.searchParams.get('month');
  if (month !== null && !/^\d{4}-(0[1-9]|1[0-2])$/.test(month)) {
    throw httpError(400, 'bad_month', '"month" must use YYYY-MM');
  }
  sendJson(c.res, 200, aggregateSeason(c.auth.couple, month));
});

// Machine-readable game manifest (sync contract h): the canonical type list
// clients pin their local GameKind enums against — the single source of
// truth is GAME_TYPES in game-rules.js (drift-watched against docs/API.md
// by test/games_catalog.test.js).
route('GET', '/api/games/catalog', { auth: true }, (c) => {
  sendJson(c.res, 200, { types: GAME_TYPES });
});

// Aggregated biography numbers (Spieltisch eval S2; re-eval 2 Befunde
// 8/9/14; Fix-Runde 3 Befunde 5/6). Every number counts PLAYED games only
// — the ONE shared `isPlayedGame` rule (game-rules.js, mirrored
// client-side by PlayHubCuration): ended WITH recorded moves or a real
// result; cancelled/declined lobbies, zero-move migration invalidations
// and empty `{}` results never inflate a couple's biography.
//   total   — played games EVER, read from the persistent
//             `couple.gamesAggregate` written forward on every finish and
//             seeded once from the stored history (game-migrations.js).
//             UNCAPPED: `capList(couple.games, LIMITS.games)` evicts the
//             oldest sessions past 1000, but evicted games stay counted
//             here — total is the honest whole-life number.
//   perKind — the same aggregate per type (feeds the drawer page numbers).
//   lowerBound — true when the aggregate was seeded from a list that was
//             already AT the cap (`gamesAggregate.seededFromCapped`): the
//             evicted history is unprovable, so total/perKind are honest
//             FLOORS then and clients render "{n}+" instead of "{n}".
//   decided — played games in the RETAINED window whose result.scores
//             name a winner.
//   draws   — retained played games whose result.scores tie.
//   replayable — retained played games with recorded moves.
// decided/draws/replayable are derived from the capped list (at most
// LIMITS.games sessions), so once a couple's history has been evicted
// they are honest LOWER bounds — unlike forward-written total/perKind.
route('GET', '/api/games/stats', { auth: true }, (c) => {
  const aggregate = ensureGamesAggregate(c.auth.couple);
  let decided = 0;
  let draws = 0;
  let replayable = 0;
  for (const game of c.auth.couple.games) {
    if (!isPlayedGame(game)) continue;
    // Array guard: a played verdict can come from the result alone —
    // a legacy entry without a moves array must not 500 the stats.
    if (Array.isArray(game.moves) && game.moves.length > 0) replayable += 1;
    const scores = game.result?.scores;
    if (scores && typeof scores === 'object') {
      const values = Object.values(scores).filter((v) => Number.isFinite(v));
      if (values.length < 2) continue;
      if (values.every((v) => v === values[0])) draws += 1;
      else decided += 1;
      continue;
    }
    // Match-Spiele (result.matches/rounds, z. B. This-or-That) stehen
    // auf der Bilanz-Seite — sie MÜSSEN hier mitzählen, sonst weicht
    // die Punktzeile von der Seite ab (Final-Eval R5). Gleichstand der
    // Übereinstimmungs-Hälften ist das Draw-Analogon.
    const matches = game.result?.matches;
    const rounds = game.result?.rounds;
    if (Number.isFinite(matches) && Number.isFinite(rounds) && rounds > 0) {
      if (matches * 2 === rounds) draws += 1;
      else decided += 1;
    }
  }
  sendJson(c.res, 200, {
    total: aggregate.total,
    perKind: aggregate.perKind,
    lowerBound: aggregate.seededFromCapped === true,
    decided,
    draws,
    replayable,
  });
});

// v3.0 single-session fetch (replay deep-links, spectator refresh). The
// literal `active`/`open`/`season`/`catalog`/`stats` routes are registered
// first, so they win.
route('GET', '/api/games/:id', { auth: true }, (c) => {
  sendJson(c.res, 200, { game: serializeGame(findGame(c.auth.couple, c.params.id), c.auth.couple) });
});

// History: recent games (any state, incl. result), newest first. The plain
// `/api/games` path (2 segments) never clashes with `/api/games/active` (3 segments).
route('GET', '/api/games', { auth: true }, (c) => {
  const limit = queryInt(c.url, 'limit', 30, 1, 200);
  const cursor = queryInt(c.url, 'cursor', 0, 0, LIMITS.games);
  const history = c.auth.couple.games.slice().reverse();
  const page = history.slice(cursor, cursor + limit);
  sendJson(c.res, 200, {
    games: page.map((game) => serializeGame(game, c.auth.couple)),
    nextCursor: cursor + page.length < history.length ? String(cursor + page.length) : null,
    total: history.length,
  });
});

// --- stats -----------------------------------------------------------------------------------

route('GET', '/api/stats', { auth: true }, (c) => {
  const couple = c.auth.couple;
  const me = c.auth.memberId;
  const partner = partnerOf(couple, me);
  const mine = couple.counters.touches[me] ?? { total: 0, byType: {} };
  const theirs = partner ? (couple.counters.touches[partner.id] ?? { total: 0, byType: {} }) : { total: 0, byType: {} };
  const sinceKey = couple.anniversary ?? couple.createdAt.slice(0, 10);
  sendJson(c.res, 200, {
    daysTogether: daysBetween(sinceKey),
    touchesSent: { total: mine.total, byType: mine.byType },
    touchesReceived: { total: theirs.total, byType: theirs.byType },
    messages: couple.counters.messages,
    photos: couple.photos.length,
    videos: videosOf(couple).length,
    bucketDone: couple.bucket.filter((b) => b.done).length,
    bucketTotal: couple.bucket.length,
    dailyStreak: computeStreak(couple),
    dailyAnswered: Object.values(couple.daily).filter((rec) => rec.answers[me]?.text != null).length,
    gamesPlayed: couple.counters.gamesPlayed,
  });
});

// --- widget snapshot ---------------------------------------------------------------------------

/** Next occurrence of an event on/after `today` (yearly events wrap into the next year); null when past. */
function nextEventOccurrence(event, today) {
  if (event.date >= today) return event.date;
  if (!event.repeatsYearly) return null;
  const monthDay = event.date.slice(4); // "-MM-DD"
  const thisYear = today.slice(0, 4) + monthDay;
  return thisYear >= today ? thisYear : `${Number(today.slice(0, 4)) + 1}${monthDay}`;
}

// One-call payload for home-screen widgets. Extensions use their shared
// Keychain bearer in the Authorization header.
route('GET', '/api/widget-snapshot', { auth: true }, (c) => {
  const couple = c.auth.couple;
  const me = c.auth.member;
  const partner = partnerOf(couple, me.id);
  // Schlussrunde 6: widgets ask for THEIR local day (`?dateKey=`) so the
  // daily block (pin, text, answered flags) matches what the caller's
  // clock shows — server-UTC "today" straddles midnight for half the
  // world. Same ±1 window as every daily write; without the param the
  // server day keeps the pre-6 behavior (old clients).
  const requested = c.url.searchParams.get('dateKey');
  const serverToday = todayKey();
  let today = serverToday;
  if (requested != null) {
    const dateKey = asDateKey(requested, 'dateKey');
    if (dateKey !== serverToday && dateKey !== prevDateKey(serverToday) && dateKey !== nextDateKey(serverToday)) {
      throw httpError(400, 'bad_datekey', `"dateKey" must be within one day of the server date (${serverToday})`);
    }
    today = dateKey;
  }
  // Newest favorited photo wins; otherwise the newest photo overall.
  const photos = couple.photos;
  let latestPhoto = photos.length > 0 ? photos[photos.length - 1] : null;
  for (let i = photos.length - 1; i >= 0; i--) {
    if ((photos[i].favorites ?? []).length > 0) {
      latestPhoto = photos[i];
      break;
    }
  }
  // Soonest upcoming event; a yearly event whose date passed wraps to its next occurrence.
  let nextEvent = null;
  let nextDate = null;
  for (const event of couple.events) {
    const occurrence = nextEventOccurrence(event, today);
    if (occurrence !== null && (nextDate === null || occurrence < nextDate)) {
      nextEvent = event;
      nextDate = occurrence;
    }
  }
  const lastStroke = couple.strokes.length > 0 ? couple.strokes[couple.strokes.length - 1] : null;
  sendJson(c.res, 200, {
    partner: partner
      ? {
          id: partner.id,
          name: partner.name,
          avatar: partner.avatar,
          color: partner.color,
          mood: partner.mood,
          moodNote: partner.moodNote,
          moodUpdatedAt: partner.moodUpdatedAt,
          online: c.realtime.isOnline(couple.id, partner.id),
          lastSeenAt: partner.lastSeenAt,
          energy: freshEnergy(partner), // v3.0 traffic light (null once stale)
        }
      : null,
    me: { id: me.id, name: me.name, avatar: me.avatar, color: me.color },
    couple: { id: couple.id, name: couple.name, anniversary: couple.anniversary },
    daysTogether: daysBetween(couple.anniversary ?? couple.createdAt.slice(0, 10)),
    streak: computeStreak(couple),
    bothAnsweredToday: bothAnsweredOn(couple, today),
    dailyAnsweredByMe: couple.daily[today]?.answers[me.id]?.text != null,
    // Pinned question of the day (null before the first answer): widgets
    // must render the SAME question as the app on every device.
    dailyQuestionId: couple.daily[today]?.questionId ?? null,
    // Schlussrunde 5: the day the pin belongs to (server-UTC). Clients
    // apply the pin only when this matches THEIR local day — around
    // midnight/timezone hops the two disagree and the pin must not leak
    // yesterday's question into today's widget.
    dailyDateKey: today,
    // Bilingual text stored with the pin (null without one) — lets a
    // client render the pinned question even when its pool doesn't know
    // the id (mixed-version couples).
    dailyQuestion: couple.daily[today]?.questionText ?? null,
    latestPhoto: latestPhoto
      ? {
          id: latestPhoto.id,
          url: latestPhoto.url,
          thumbUrl: latestPhoto.thumbUrl ?? null,
          caption: latestPhoto.caption,
          favorites: latestPhoto.favorites ?? [],
        }
      : null,
    nextEvent: nextEvent
      ? {
          id: nextEvent.id,
          title: nextEvent.title,
          emoji: nextEvent.emoji,
          date: nextDate,
          repeatsYearly: nextEvent.repeatsYearly,
        }
      : null,
    canvasStrokeCount: couple.strokes.length,
    canvasUpdatedAt: lastStroke ? lastStroke.createdAt : null,
    goal: topGoalView(couple), // v3.0: most recently active open goal (for Agent C's widget)
    level: levelSnapshot(couple, { store: c.store }), // v3.0 relationship level (Agent C)
    serverTime: nowIso(),
  });
});

// --- inbox -------------------------------------------------------------------------------------

// "What happened since I last looked": counts (and a last teaser where useful)
// of everything created strictly after `since`. EVERY bucket is partner-only:
// the caller's own items never count — otherwise sending five texts and
// closing the app yields "5 missed messages" for your own words the next
// morning. Archived messages remain part of this count.
route('GET', '/api/inbox', { auth: true }, (c) => {
  const raw = c.url.searchParams.get('since');
  if (!raw) throw httpError(400, 'bad_since', '"since" query param is required (ISO-8601 timestamp)');
  const since = asIsoTimestamp(raw, 'since', 'bad_since');
  const couple = c.auth.couple;
  const me = c.auth.memberId;
  const newerThan = (list, authorField) =>
    list.filter((item) => item.createdAt > since && item[authorField] !== me);

  const messages = newerThan(allMessagesOf(couple), 'senderId');
  const lastMessage = messages.length > 0 ? messages[messages.length - 1] : null;
  const touches = newerThan(couple.touches, 'senderId');
  const photos = newerThan(couple.photos, 'uploaderId');
  const lastPhoto = photos.length > 0 ? photos[photos.length - 1] : null;
  const couponsForMe = couponsOf(couple).filter(
    (cp) => cp.createdAt > since && cp.forMember === me && cp.createdBy !== me,
  );
  const partner = partnerOf(couple, me);
  const partnerAnswer = partner ? couple.daily[todayKey()]?.answers[partner.id] : undefined;
  const awaiting = gamesAwaiting(couple, me);

  sendJson(c.res, 200, {
    messages: {
      count: messages.length,
      last: lastMessage
        ? {
            id: lastMessage.id,
            senderId: lastMessage.senderId,
            kind: lastMessage.type,
            text: lastMessage.text == null ? null : lastMessage.text.slice(0, LIMITS.inboxTeaser),
            createdAt: lastMessage.createdAt,
          }
        : null,
    },
    touches: { count: touches.length, last: touches.length > 0 ? touches[touches.length - 1] : null },
    photos: { count: photos.length, last: lastPhoto ? { id: lastPhoto.id, caption: lastPhoto.caption } : null },
    couponsForMe: {
      count: couponsForMe.length,
      last: couponsForMe.length > 0 ? serializeCoupon(couponsForMe[couponsForMe.length - 1]) : null,
    },
    songs: { count: newerThan(songsOf(couple), 'addedBy').length },
    dailyPartnerAnswered: Boolean(partnerAnswer && partnerAnswer.answeredAt > since),
    canvasStrokes: { count: newerThan(couple.strokes, 'memberId').length },
    // v3.0 "you're up!" digest — CURRENT state (not since-filtered): open
    // games where the caller should act (partner invitation, or the partner
    // made the last move). Lets app-open show badges without push.
    games: { count: awaiting.length, awaitingMe: awaiting.map((g) => ({ gameId: g.id, type: g.type })) },
    // v3.0 need button: new signals for me since `since`, plus the newest
    // still-unacknowledged one so app-open can surface it without push.
    needsForMe: {
      count: needsOf(couple).filter((n) => n.createdAt > since && n.forMember === me).length,
      openNeed: needsOf(couple).filter((n) => n.forMember === me && !n.ackAt).slice(-1)[0] ?? null,
    },
    serverTime: nowIso(),
  });
});

// --- check-ins (v2.0) ----------------------------------------------------------------------
//
// Morning ☀️ / goodnight 🌙 taps. One tap per (member, kind, day); the streak
// counts consecutive days on which BOTH members checked in at least once.

route('GET', '/api/checkins', { auth: true }, (c) => {
  const limit = queryInt(c.url, 'limit', 30, 1, LIMITS.checkinDays);
  const couple = c.auth.couple;
  const dateKeys = Object.keys(checkinsOf(couple)).sort().reverse().slice(0, limit);
  sendJson(c.res, 200, {
    days: dateKeys.map((key) => checkinDayView(couple, key)),
    streak: checkinStreak(couple),
  });
});

route('POST', '/api/checkins', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
  const kind = asEnum(body.kind, 'kind', CHECKIN_KINDS);
  const today = todayKey();
  const dateKey = body.dateKey === undefined ? today : asDateKey(body.dateKey, 'dateKey');
  if (dateKey !== today && dateKey !== prevDateKey(today) && dateKey !== nextDateKey(today)) {
    throw httpError(400, 'bad_datekey', `"dateKey" must be within one day of the server date (${today})`);
  }
  const couple = c.auth.couple;
  const checkins = checkinsOf(couple);
  if (!checkins[dateKey]) checkins[dateKey] = {};
  const day = checkins[dateKey];
  if (!day[kind]) day[kind] = {};
  // First tap wins — re-checking in is idempotent and keeps the original time.
  if (!day[kind][c.auth.memberId]) {
    day[kind][c.auth.memberId] = nowIso();
    const keys = Object.keys(checkins);
    if (keys.length > LIMITS.checkinDays) {
      keys.sort();
      for (const old of keys.slice(0, keys.length - LIMITS.checkinDays)) delete checkins[old];
    }
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'checkin', {
      memberId: c.auth.memberId,
      kind,
      day: checkinDayView(couple, dateKey),
      streak: checkinStreak(couple),
    });
  }
  sendJson(c.res, 200, { day: checkinDayView(couple, dateKey), streak: checkinStreak(couple) });
});

// --- shared lists (v2.0) --------------------------------------------------------------------
//
// Shopping, movies-to-watch, anything: lists with checkable items, live-synced.
// Item mutations broadcast the WHOLE list (`list_updated`) — simplest way to
// keep both clients consistent with ordering and caps.

// Sync contract e: like calendar events, every list carries a LIST-level
// `rev` (starts at 1) bumped by EVERY mutation (rename, item add/edit/
// delete). Item mutations may send `ifRev` against the list revision — a
// mismatch answers 409 conflict with the current list, so concurrent item
// edits stop silently overwriting each other. Without `ifRev` the old
// last-write-wins behavior stays.

/** Pre-contract stores lack `rev` — default it on the way out. */
function listView(list) {
  return { ...list, rev: list.rev ?? 1 };
}

function bumpListRev(list) {
  list.rev = (list.rev ?? 1) + 1;
}

route('GET', '/api/lists', { auth: true }, (c) => {
  sendJson(c.res, 200, { lists: listsOf(c.auth.couple).map(listView) });
});

route('POST', '/api/lists', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
  const lists = listsOf(c.auth.couple);
  if (lists.length >= LIMITS.lists) {
    throw httpError(413, 'too_many_lists', `At most ${LIMITS.lists} lists per couple — delete one first`);
  }
  const list = {
    id: id('l'),
    name: asString(body.name, 'name', { max: LIMITS.listName }),
    emoji: body.emoji == null ? null : asString(body.emoji, 'emoji', { max: 16 }),
    createdBy: c.auth.memberId,
    createdAt: nowIso(),
    items: [],
    rev: 1,
  };
  lists.push(list);
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'list_added', { list: listView(list) });
  sendJson(c.res, 201, { list: listView(list) });
});

route('PATCH', '/api/lists/:id', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
  const list = findList(c.auth.couple, c.params.id);
  if (!checkIfRev(c, body, list.rev ?? 1, listView(list))) return;
  if ('name' in body) list.name = asString(body.name, 'name', { max: LIMITS.listName });
  if ('emoji' in body) list.emoji = body.emoji === null ? null : asString(body.emoji, 'emoji', { max: 16 });
  bumpListRev(list);
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'list_updated', { list: listView(list) });
  sendJson(c.res, 200, { list: listView(list) });
});

route('DELETE', '/api/lists/:id', { auth: true }, (c) => {
  const lists = listsOf(c.auth.couple);
  const list = findList(c.auth.couple, c.params.id);
  lists.splice(lists.indexOf(list), 1);
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'list_deleted', { id: list.id });
  sendJson(c.res, 200, { ok: true });
});

route('POST', '/api/lists/:id/items', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
  const list = findList(c.auth.couple, c.params.id);
  if (!checkIfRev(c, body, list.rev ?? 1, listView(list))) return;
  if (list.items.length >= LIMITS.listItems) {
    throw httpError(413, 'too_many_items', `At most ${LIMITS.listItems} items per list`);
  }
  const item = {
    id: id('li'),
    text: asString(body.text, 'text', { max: LIMITS.listItemText }),
    done: false,
    doneAt: null,
    createdBy: c.auth.memberId,
    createdAt: nowIso(),
  };
  list.items.push(item);
  bumpListRev(list);
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'list_updated', { list: listView(list) });
  sendJson(c.res, 201, { item, list: listView(list) });
});

route('PATCH', '/api/lists/:id/items/:itemId', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
  const list = findList(c.auth.couple, c.params.id);
  const item = list.items.find((i) => i.id === c.params.itemId);
  if (!item) throw httpError(404, 'not_found', 'Unknown list item');
  if (!checkIfRev(c, body, list.rev ?? 1, listView(list))) return;
  if ('text' in body) item.text = asString(body.text, 'text', { max: LIMITS.listItemText });
  if ('done' in body) {
    const done = Boolean(body.done);
    item.done = done;
    item.doneAt = done ? (item.doneAt ?? nowIso()) : null;
  }
  bumpListRev(list);
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'list_updated', { list: listView(list) });
  sendJson(c.res, 200, { item, list: listView(list) });
});

route('DELETE', '/api/lists/:id/items/:itemId', { auth: true }, (c) => {
  const list = findList(c.auth.couple, c.params.id);
  const idx = list.items.findIndex((i) => i.id === c.params.itemId);
  if (idx === -1) throw httpError(404, 'not_found', 'Unknown list item');
  list.items.splice(idx, 1);
  bumpListRev(list);
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'list_updated', { list: listView(list) });
  sendJson(c.res, 200, { ok: true });
});

// --- hug queue (v2.0) -----------------------------------------------------------------------
//
// For long-distance timezones: queue a hug while the partner sleeps; they
// "open" it when they wake up (opening notifies the sender via `hug_opened`).

route('GET', '/api/hugs', { auth: true }, (c) => {
  sendJson(c.res, 200, { hugs: hugsOf(c.auth.couple).slice().reverse() });
});

route('POST', '/api/hugs', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
  const partner = partnerOf(c.auth.couple, c.auth.memberId);
  if (!partner) throw httpError(409, 'no_partner', 'Hugs need a partner to receive them');
  // Same "moment sender" class as touches/pulses (sync contract a): a stable
  // clientOperationId makes lost-response retries exactly-once.
  const opKey = operationKey(c, 'hug', '-', clientOperationId(body));
  if (hasClientOperation(c.auth.couple, opKey)) {
    sendJson(c.res, 200, { hug: getClientOperation(c.auth.couple, opKey), duplicate: true });
    return;
  }
  const hug = {
    id: id('h'),
    from: c.auth.memberId,
    to: partner.id,
    note: body.note == null ? null : asString(body.note, 'note', { max: LIMITS.hugNote, nonEmpty: false }),
    emoji: body.emoji == null ? '🫂' : asString(body.emoji, 'emoji', { max: 16 }),
    createdAt: nowIso(),
    openedAt: null,
  };
  const hugs = hugsOf(c.auth.couple);
  hugs.push(hug);
  capList(hugs, LIMITS.hugs);
  rememberClientOperation(c.auth.couple, opKey, hug);
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'hug_queued', { hug });
  sendJson(c.res, 201, { hug });
});

route('POST', '/api/hugs/:id/open', { auth: true }, (c) => {
  const hug = hugsOf(c.auth.couple).find((h) => h.id === c.params.id);
  if (!hug) throw httpError(404, 'not_found', 'Unknown hug');
  if (hug.to !== c.auth.memberId) throw httpError(403, 'not_yours', 'Only the receiving member may open this hug');
  if (hug.openedAt) throw httpError(409, 'already_opened', 'This hug was already opened');
  hug.openedAt = nowIso();
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'hug_opened', { hug });
  sendJson(c.res, 200, { hug });
});

// --- photo of the day (v2.0) ------------------------------------------------------------------
//
// The daily prompt itself is client-side (deterministic from the dateKey);
// the server stores which gallery photo each member submitted for a day.
// Resubmitting replaces your own pick for that day.

route('GET', '/api/potd', { auth: true }, (c) => {
  const limit = queryInt(c.url, 'limit', 30, 1, LIMITS.potdDays);
  const couple = c.auth.couple;
  const dateKeys = Object.keys(potdOf(couple)).sort().reverse().slice(0, limit);
  sendJson(c.res, 200, { days: dateKeys.map((key) => potdDayView(couple, key)) });
});

route('POST', '/api/potd/:dateKey', { auth: true }, async (c) => {
  const dateKey = asDateKey(c.params.dateKey, 'dateKey');
  const today = todayKey();
  if (dateKey !== today && dateKey !== prevDateKey(today) && dateKey !== nextDateKey(today)) {
    throw httpError(400, 'bad_datekey', `"dateKey" must be within one day of the server date (${today})`);
  }
  const body = await readJsonObject(c.req);
  const photoId = asString(body.photoId, 'photoId', { max: 64 });
  const couple = c.auth.couple;
  if (!couple.photos.some((p) => p.id === photoId)) {
    throw httpError(404, 'not_found', 'Unknown photo — upload it to the gallery first');
  }
  const potd = potdOf(couple);
  if (!potd[dateKey]) potd[dateKey] = {};
  potd[dateKey][c.auth.memberId] = { photoId, submittedAt: nowIso() };
  const keys = Object.keys(potd);
  if (keys.length > LIMITS.potdDays) {
    keys.sort();
    for (const old of keys.slice(0, keys.length - LIMITS.potdDays)) delete potd[old];
  }
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'potd_submitted', {
    dateKey,
    memberId: c.auth.memberId,
    photoId,
    day: potdDayView(couple, dateKey),
  });
  sendJson(c.res, 200, { day: potdDayView(couple, dateKey) });
});

// --- now playing (v2.0) ------------------------------------------------------------------------
//
// "Currently listening to …" status on the member. Auto-hides after 60
// minutes (serialized as null) so a forgotten status never goes stale.

route('PUT', '/api/nowplaying', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
  const nowPlaying = {
    title: asString(body.title, 'title', { max: LIMITS.nowPlayingField }),
    artist: body.artist == null ? null : asString(body.artist, 'artist', { max: LIMITS.nowPlayingField, nonEmpty: false }),
    setAt: nowIso(),
  };
  c.auth.member.nowPlaying = nowPlaying;
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'now_playing', { memberId: c.auth.memberId, nowPlaying });
  sendJson(c.res, 200, { nowPlaying });
});

route('DELETE', '/api/nowplaying', { auth: true }, (c) => {
  c.auth.member.nowPlaying = null;
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'now_playing', { memberId: c.auth.memberId, nowPlaying: null });
  sendJson(c.res, 200, { ok: true });
});

// --- year review (v2.0) -------------------------------------------------------------------------
//
// "Unser Jahr": everything the server still remembers about one calendar
// year. Counts are limited by the capped lists (messages/touches/… roll off),
// so early-year numbers may be lower bounds — documented in the API spec.

route('GET', '/api/yearreview', { auth: true }, (c) => {
  const year = queryInt(c.url, 'year', new Date().getUTCFullYear(), 2000, 2100);
  const prefix = String(year);
  const inYear = (iso) => typeof iso === 'string' && iso.startsWith(prefix);
  const couple = c.auth.couple;
  const memberIds = couple.members.map((m) => m.id);

  const touchesByMember = {};
  const topTouchType = {};
  for (const mid of memberIds) {
    const mine = couple.touches.filter((t) => t.senderId === mid && inYear(t.createdAt));
    touchesByMember[mid] = mine.length;
    const byType = {};
    for (const t of mine) byType[t.type] = (byType[t.type] ?? 0) + 1;
    topTouchType[mid] = Object.entries(byType).sort((a, b) => b[1] - a[1])[0]?.[0] ?? null;
  }

  const messagesByMember = {};
  for (const mid of memberIds) {
    messagesByMember[mid] = allMessagesOf(couple)
      .filter((m) => m.senderId === mid && inYear(m.createdAt)).length;
  }

  const games = couple.games.filter((g) => inYear(g.createdAt) && g.state === 'ended');
  const gameWins = {};
  for (const mid of memberIds) gameWins[mid] = 0;
  for (const game of games) {
    const scores = game.result?.scores;
    if (!scores) continue;
    const entries = memberIds.map((mid) => [mid, Number(scores[mid] ?? 0)]);
    entries.sort((a, b) => b[1] - a[1]);
    if (entries.length === 2 && entries[0][1] > entries[1][1]) gameWins[entries[0][0]] += 1;
  }

  const wordle = wordleOf(couple);
  const wordleDays = Object.keys(wordle).filter((key) => inYear(key));
  const wordleWins = {};
  for (const mid of memberIds) {
    wordleWins[mid] = wordleDays.filter((key) =>
      Object.values(wordle[key] ?? {}).some((byMember) => byMember?.[mid]?.win === true),
    ).length;
  }

  const dailyDays = Object.keys(couple.daily).filter((key) => inYear(key) && bothAnsweredOn(couple, key));
  const checkinDays = Object.keys(checkinsOf(couple)).filter((key) => inYear(key) && bothCheckedInOn(couple, key));
  const potdDays = Object.keys(potdOf(couple)).filter(
    (key) => inYear(key) && Object.keys(potdOf(couple)[key]).length > 0,
  );

  sendJson(c.res, 200, {
    year,
    generatedAt: nowIso(),
    photosAdded: couple.photos.filter((p) => inYear(p.createdAt)).length,
    videosAdded: videosOf(couple).filter((v) => inYear(v.createdAt)).length,
    messagesByMember,
    touchesByMember,
    topTouchType,
    gamesPlayed: games.length,
    gameWins,
    wordleDaysPlayed: wordleDays.length,
    wordleWins,
    dailyBothAnswered: dailyDays.length,
    checkinDaysBoth: checkinDays.length,
    checkinStreak: checkinStreak(couple),
    hugsSent: hugsOf(couple).filter((h) => inYear(h.createdAt)).length,
    hugsOpened: hugsOf(couple).filter((h) => h.openedAt && inYear(h.openedAt)).length,
    couponsRedeemed: couponsOf(couple).filter((cp) => cp.redeemedAt && inYear(cp.redeemedAt)).length,
    songsAdded: songsOf(couple).filter((s) => inYear(s.createdAt)).length,
    bucketDone: couple.bucket.filter((b) => b.doneAt && inYear(b.doneAt)).length,
    eventsCreated: couple.events.filter((e) => inYear(e.createdAt)).length,
    potdDays: potdDays.length,
    // „Eure Highlights des Jahres": weekly highlight texts survive the
    // 26-week cap via the compact archive (weekreview.js) — unlike the
    // rolled-off counts these are NOT lower bounds within the last year.
    weekHighlights: weekHighlightsForYear(couple, year),
  });
});

// --- v3.0 relationship rituals (Agent A) — routes live in rituals.js -------------------------

registerRitualRoutes(route, {
  asString,
  asEnum,
  asDateKey,
  queryInt,
  capList,
  partnerOf,
  serveFile,
  bothAnsweredOn,
  bothCheckedInOn,
  notifyPartner: queuePartnerPush,
});

// --- v3.0 level/badges/quest + platform delights (Agent C) — routes live in
// gamification.js / platform.js ------------------------------------------------

registerGamificationRoutes(route);
registerPlatformRoutes(route, { asString, asEnum, partnerOf });

// --- v7.0 „Eure Woche" weekly review + couple question pool — routes live in
// weekreview.js / dailyquestions.js ------------------------------------------

registerWeekReviewRoutes(route, {
  asString,
  partnerOf,
  bothAnsweredOn,
  bothCheckedInOn,
  notifyPartner: queuePartnerPush,
});

registerDailyQuestionRoutes(route, { asString });

// --- v8.0 „Erinnerungen" read-only memory aggregations — memories.js ---------

registerMemoryRoutes(route);

// --- v9.0 „Nähe trotz Distanz" presence modes + pulses — presence.js ---------

registerPresenceRoutes(route, {
  asString,
  asEnum,
  notifyPartner: queuePartnerPush,
  // Sync contract a: pulse idempotency reuses the shared dedup machinery.
  clientOperationId,
  operationKey,
  hasClientOperation,
  getClientOperation,
  rememberClientOperation,
});

// --- FullRelease P6-B „Post-Station" — Zeitpost, echoes + journal — post.js ---

registerPostRoutes(route, {
  asString,
  asEnum,
  queryInt,
  touchTypes: TOUCH_TYPES,
  notifyPartner: queuePartnerPush,
  // Sync contract a: schedule/echo idempotency reuses the shared dedup machinery.
  clientOperationId,
  operationKey,
  hasClientOperation,
  getClientOperation,
  rememberClientOperation,
});

// --- v5.0 „Worte & Wärme" (everyday appreciation) — routes live in warmth.js --

registerWarmthRoutes(route, {
  asString,
  asEnum,
  asDateKey,
  queryInt,
  capList,
  partnerOf,
  notifyPartner: queuePartnerPush,
});

// --- v4.8 guided repair + encrypted consideration radar --------------------

registerRepairRoutes(route, { asString, asEnum });

// --- v5.0 seasonal countdown calendars ------------------------------------

registerSeasonalRoutes(route, { asString, asEnum });

// --- v6.0 encrypted file migration assistant -------------------------------

registerMigrationRoutes(route);

// --- v6.1 pairing recovery (rejoin, recovery keys, partner replace) — routes
// live in pairing.js ---------------------------------------------------------

registerPairingRoutes(route, { asString, serializeMember, serializeCouple, partnerOf });

// ---------------------------------------------------------------------------
// auth + top-level request handling

function authenticate(store, req) {
  let token = null;
  const header = req.headers.authorization;
  if (typeof header === 'string' && header.startsWith('Bearer ')) token = header.slice(7).trim();
  const authenticated = token
    ? authenticateToken(store, token, { userAgent: req.headers['user-agent'] })
    : null;
  if (!authenticated) throw httpError(401, 'invalid_token', 'Unknown, revoked or expired token');
  const { record, couple, member } = authenticated;
  return { token, record, coupleId: record.coupleId, memberId: record.memberId, couple, member };
}

export function createRouter({ store, realtime, push, config, rateLimiter, admin = null, log = () => {} }) {
  return async function handle(req, res) {
    try {
      let url;
      try {
        url = new URL(req.url, `http://${req.headers.host ?? 'localhost'}`);
      } catch {
        throw httpError(400, 'bad_request', 'Malformed request URL');
      }
      const isAdminRequest = url.pathname === '/admin' || url.pathname.startsWith('/admin/');
      if (!isAdminRequest) {
        res.setHeader('access-control-allow-origin', '*');
        res.setHeader('access-control-allow-methods', 'GET,POST,PUT,PATCH,DELETE,OPTIONS');
        res.setHeader('access-control-allow-headers', 'Authorization, Content-Type, X-Caption, X-Width, X-Height, X-Duration-Sec');
      }
      requireSecureTransport(req, config);
      if (url.searchParams.has('token') || url.searchParams.has('access_token')) {
        throw httpError(400, 'query_token_forbidden', 'Bearer tokens must be sent in the Authorization header');
      }
      if (req.method === 'OPTIONS') {
        res.writeHead(204, { 'access-control-max-age': '86400' });
        res.end();
        return;
      }
      // v10.1 operator panel (pages + cookie-authenticated APIs) — admin.js.
      if (admin && isAdminRequest) {
        await admin.handle(req, res, url);
        return;
      }
      const match = matchRoute(req.method, url.pathname);
      if (!match) throw httpError(404, 'not_found', `No route for ${req.method} ${url.pathname}`);
      const auth = match.route.auth ? authenticate(store, req) : null;
      // Multi-device: broadcasts of an authenticated request carry the
      // caller's origin marker ({memberId, deviceId, sessionSuffix}) so every
      // device can tell its own events from partner (and sibling-device)
      // events. The facade injects it into all realtime helpers.
      const requestRealtime = auth ? realtime.withOrigin(sessionOrigin(auth.record)) : realtime;
      await match.route.handler({
        req,
        res,
        url,
        params: match.params,
        auth,
        store,
        realtime: requestRealtime,
        push,
        config,
        rateLimiter,
        log,
      });
      // v3.0 gamification (Agent C): any successful authenticated write may
      // have earned XP or unlocked badges — one central check instead of
      // hooks in every handler. Skips reads and dissolved couples.
      if (auth && req.method !== 'GET' && store.data.couples[auth.coupleId]) {
        try {
          maybeAdvanceGamification({ store, realtime: requestRealtime, couple: auth.couple });
        } catch (err) {
          log('gamification: advance failed', err);
        }
      }
    } catch (err) {
      const status = err instanceof HttpError ? err.status : 500;
      const code = err instanceof HttpError ? err.code : 'internal_error';
      if (status === 500) log('http: unhandled error', err);
      if (status === 429 && err.retryAfter) res.setHeader('retry-after', String(err.retryAfter));
      if (!res.headersSent) {
        const body = { error: code, message: err?.message ?? 'Internal error' };
        // Structured refusal context (e.g. game_lease_held carries the
        // holding device) — only ever attached to intentional HttpErrors.
        if (err instanceof HttpError && err.details !== undefined) body.details = err.details;
        sendJson(res, status, body);
      } else {
        res.destroy();
      }
    }
  };
}
