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
} from './util.js';

const TOUCH_TYPES = ['heartbeat', 'kiss', 'hug', 'missyou', 'tickle', 'thinking'];
const MESSAGE_TYPES = ['text', 'letter'];
const GAME_TYPES = ['quiz', 'thisorthat', 'wouldyourather', 'truthordare', 'questions36'];
const WORDLE_LANGS = ['de', 'en'];

const LIMITS = {
  media: 15 * 1024 * 1024, // photo & voice bodies
  thumb: 2 * 1024 * 1024, // photo thumbnail bodies
  json: 1024 * 1024,
  text: 5000,
  openWhen: 64,
  reactionEmoji: 16,
  strokePoints: 2000,
  strokes: 8000,
  messages: 5000,
  touches: 500,
  games: 100,
  moodHistory: 60, // per member
  wordleGrid: 160,
  wordleDays: 60, // dateKeys kept per couple
  coupons: 200,
  couponTitle: 80,
  couponEmoji: 16,
  couponNote: 200,
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

// ---------------------------------------------------------------------------
// serialization (spec model shapes)

function serializeMember(couple, member, realtime) {
  return {
    id: member.id,
    name: member.name,
    avatar: member.avatar,
    color: member.color,
    mood: member.mood,
    moodNote: member.moodNote,
    moodUpdatedAt: member.moodUpdatedAt,
    online: realtime.isOnline(couple.id, member.id),
    lastSeenAt: member.lastSeenAt,
    joinedAt: member.joinedAt,
  };
}

function serializeCouple(couple, realtime) {
  return {
    id: couple.id,
    code: couple.code,
    name: couple.name,
    anniversary: couple.anniversary,
    createdAt: couple.createdAt,
    members: couple.members.map((m) => serializeMember(couple, m, realtime)),
  };
}

function partnerOf(couple, memberId) {
  return couple.members.find((m) => m.id !== memberId) ?? null;
}

/** Pre-v1.2 stores lack `openWhen`/`reactions` on messages — default them on the way out. */
function serializeMessage(message) {
  return { ...message, openWhen: message.openWhen ?? null, reactions: message.reactions ?? null };
}

/** Pre-v1.2 stores lack `thumbUrl`/`favorites` on photos — default them on the way out. */
function serializePhoto(photo) {
  return { ...photo, thumbUrl: photo.thumbUrl ?? null, favorites: photo.favorites ?? [] };
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

// ---------------------------------------------------------------------------
// couple/member factories

function newMember({ name, avatar, color }) {
  return {
    id: id('m'),
    name: asString(name, 'name', { max: 100 }),
    avatar: avatar === undefined ? '💞' : asString(avatar, 'avatar', { max: 32 }),
    color: color === undefined ? '#FF5C8A' : asString(color, 'color', { max: 32 }),
    mood: null,
    moodNote: null,
    moodUpdatedAt: null,
    lastSeenAt: null,
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
    createdAt: nowIso(),
    members: [],
    touches: [],
    messages: [],
    photos: [],
    events: [],
    bucket: [],
    strokes: [],
    daily: {},
    games: [],
    moodHistory: {},
    wordle: {},
    coupons: [],
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
    myAnswer,
    partnerAnswer: bothAnswered ? partnerAnswer : null,
    bothAnswered,
    streak: computeStreak(couple),
  };
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

function serializeGame(game) {
  return {
    id: game.id,
    type: game.type,
    state: game.state,
    createdBy: game.createdBy,
    payload: game.payload,
    result: game.result,
    moves: game.moves,
    createdAt: game.createdAt,
  };
}

function finishGame(couple, game) {
  if (game.state === 'active') couple.counters.gamesPlayed += 1;
  game.state = 'ended';
}

function findGame(couple, gameId) {
  const game = couple.games.find((g) => g.id === gameId);
  if (!game) throw httpError(404, 'not_found', 'Unknown game');
  return game;
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

route('GET', '/api/health', { auth: false }, (c) => {
  sendJson(c.res, 200, { ok: true, name: c.config.name, version: c.config.version, serverTime: nowIso() });
});

route('POST', '/api/couples', { auth: false }, async (c) => {
  const body = await readJsonObject(c.req);
  const couple = newCouple(c.store);
  const member = newMember(body);
  couple.members.push(member);
  c.store.data.couples[couple.id] = couple;
  const token = newToken();
  c.store.data.tokens[token] = { coupleId: couple.id, memberId: member.id };
  c.store.markDirty();
  sendJson(c.res, 201, {
    token,
    coupleId: couple.id,
    memberId: member.id,
    couple: serializeCouple(couple, c.realtime),
  });
});

route('POST', '/api/couples/join', { auth: false }, async (c) => {
  const body = await readJsonObject(c.req);
  const code = asString(body.code, 'code', { max: 12 }).trim().toUpperCase();
  const couple = Object.values(c.store.data.couples).find((cp) => cp.code === code);
  if (!couple) throw httpError(404, 'unknown_code', 'No couple with this code');
  if (couple.members.length >= 2) throw httpError(409, 'couple_full', 'This couple already has two members');
  const member = newMember(body);
  couple.members.push(member);
  const token = newToken();
  c.store.data.tokens[token] = { coupleId: couple.id, memberId: member.id };
  c.store.markDirty();
  c.realtime.broadcastCouple(couple.id, 'partner_joined', { member: serializeMember(couple, member, c.realtime) });
  sendJson(c.res, 200, {
    token,
    coupleId: couple.id,
    memberId: member.id,
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
  c.store.markDirty();
  const serialized = serializeCouple(couple, c.realtime);
  c.realtime.broadcastCouple(couple.id, 'couple_updated', { couple: serialized });
  sendJson(c.res, 200, { couple: serialized });
});

route('DELETE', '/api/couple', { auth: true }, async (c) => {
  const couple = c.auth.couple;
  c.realtime.broadcastCouple(couple.id, 'couple_dissolved', {});
  for (const photo of couple.photos) {
    await c.store.deleteMedia('photos', `${photo.id}.jpg`);
    await c.store.deleteMedia('photos', `${photo.id}.thumb.jpg`);
  }
  for (const msg of couple.messages) {
    if (msg.type === 'voice') await c.store.deleteMedia('voice', `${msg.id}.m4a`);
  }
  for (const [token, auth] of Object.entries(c.store.data.tokens)) {
    if (auth.coupleId === couple.id) delete c.store.data.tokens[token];
  }
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
  const touch = { id: id('t'), type, senderId: c.auth.memberId, createdAt: nowIso() };
  c.auth.couple.touches.push(touch);
  capList(c.auth.couple.touches, LIMITS.touches);
  const counter = touchCounter(c.auth.couple, c.auth.memberId);
  counter.total += 1;
  counter.byType[type] = (counter.byType[type] ?? 0) + 1;
  c.store.markDirty();
  c.realtime.broadcastPartner(c.auth.coupleId, c.auth.memberId, 'touch', { touch });
  sendJson(c.res, 201, { touch });
});

route('GET', '/api/touches/recent', { auth: true }, (c) => {
  const limit = queryInt(c.url, 'limit', 30, 1, LIMITS.touches);
  const touches = c.auth.couple.touches.slice(-limit).reverse();
  sendJson(c.res, 200, { touches });
});

// --- messages & voice ---------------------------------------------------------

route('GET', '/api/messages', { auth: true }, (c) => {
  const limit = queryInt(c.url, 'limit', 50, 1, 200);
  const before = c.url.searchParams.get('before');
  const list = c.auth.couple.messages;
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
  const dropped = capList(couple.messages, LIMITS.messages);
  for (const old of dropped) {
    if (old.type === 'voice') c.store.deleteMedia('voice', `${old.id}.m4a`);
  }
  c.store.markDirty();
  c.realtime.broadcastCouple(couple.id, 'message', { message: serializeMessage(message) });
}

route('POST', '/api/messages', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
  const type = asEnum(body.type, 'type', MESSAGE_TYPES);
  const text = asText(body.text, 'text');
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
  const message = {
    id: id('msg'),
    senderId: c.auth.memberId,
    type,
    text,
    title,
    openWhen,
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
  // Pruned (capped) messages are gone from the list → same 404 as unknown ids.
  const message = c.auth.couple.messages.find((m) => m.id === c.params.id);
  if (!message) throw httpError(404, 'not_found', 'Unknown message');
  if (!message.reactions) message.reactions = {};
  const members = message.reactions[emoji] ?? (message.reactions[emoji] = []);
  const at = members.indexOf(c.auth.memberId);
  if (at === -1) members.push(c.auth.memberId);
  else members.splice(at, 1);
  if (members.length === 0) delete message.reactions[emoji];
  if (Object.keys(message.reactions).length === 0) delete message.reactions;
  c.store.markDirty();
  const serialized = serializeMessage(message);
  c.realtime.broadcastCouple(c.auth.coupleId, 'message_updated', { message: serialized });
  sendJson(c.res, 200, { message: serialized });
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

route('GET', '/api/voice/:id/raw', { auth: true, queryToken: true }, async (c) => {
  const msg = c.auth.couple.messages.find((m) => m.id === c.params.id && m.type === 'voice');
  if (!msg) throw httpError(404, 'not_found', 'Unknown voice message');
  await serveFile(c.req, c.res, c.store.mediaPath('voice', `${msg.id}.m4a`), 'audio/mp4');
});

// --- photos --------------------------------------------------------------------

route('POST', '/api/photos', { auth: true }, async (c) => {
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
  const photoId = id('ph');
  await c.store.saveMedia('photos', `${photoId}.jpg`, buf);
  const photo = {
    id: photoId,
    uploaderId: c.auth.memberId,
    caption,
    url: `/api/photos/${photoId}/raw`,
    thumbUrl: null,
    width: Number.isFinite(width) && width > 0 ? width : null,
    height: Number.isFinite(height) && height > 0 ? height : null,
    createdAt: nowIso(),
  };
  c.auth.couple.photos.push(photo);
  c.store.markDirty();
  const serialized = serializePhoto(photo);
  c.realtime.broadcastCouple(c.auth.coupleId, 'photo_added', { photo: serialized });
  sendJson(c.res, 201, { photo: serialized });
});

route('GET', '/api/photos', { auth: true }, (c) => {
  sendJson(c.res, 200, { photos: c.auth.couple.photos.slice().reverse().map(serializePhoto) });
});

route('GET', '/api/photos/:id/raw', { auth: true, queryToken: true }, async (c) => {
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

route('GET', '/api/photos/:id/thumb/raw', { auth: true, queryToken: true }, async (c) => {
  const photo = c.auth.couple.photos.find((p) => p.id === c.params.id);
  if (!photo) throw httpError(404, 'not_found', 'Unknown photo');
  if (!photo.thumbUrl) throw httpError(404, 'no_thumb', 'This photo has no thumbnail');
  await serveFile(c.req, c.res, c.store.mediaPath('photos', `${photo.id}.thumb.jpg`), 'image/jpeg');
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

// --- events ----------------------------------------------------------------------

route('GET', '/api/events', { auth: true }, (c) => {
  sendJson(c.res, 200, { events: c.auth.couple.events });
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
  };
  c.auth.couple.events.push(event);
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'event_added', { event });
  sendJson(c.res, 201, { event });
});

route('PATCH', '/api/events/:id', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
  const event = c.auth.couple.events.find((e) => e.id === c.params.id);
  if (!event) throw httpError(404, 'not_found', 'Unknown event');
  if ('title' in body) event.title = asString(body.title, 'title', { max: 200 });
  if ('emoji' in body) event.emoji = body.emoji === null ? null : asString(body.emoji, 'emoji', { max: 32 });
  if ('date' in body) event.date = asDateKey(body.date, 'date');
  if ('repeatsYearly' in body) event.repeatsYearly = Boolean(body.repeatsYearly);
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'event_updated', { event });
  sendJson(c.res, 200, { event });
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
  sendJson(c.res, 200, { coupons: couponsOf(c.auth.couple).slice().reverse() });
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
    createdAt: nowIso(),
  };
  const list = couponsOf(c.auth.couple);
  list.push(coupon);
  const evicted = pruneCoupons(list, LIMITS.coupons);
  c.store.markDirty();
  // Evictions first, so clients applying frames in order never exceed the cap.
  for (const old of evicted) c.realtime.broadcastCouple(c.auth.coupleId, 'coupon_deleted', { id: old.id });
  c.realtime.broadcastCouple(c.auth.coupleId, 'coupon_added', { coupon });
  sendJson(c.res, 201, { coupon });
});

route('POST', '/api/coupons/:id/redeem', { auth: true }, (c) => {
  const coupon = findCoupon(c.auth.couple, c.params.id);
  if (coupon.forMember !== c.auth.memberId) {
    throw httpError(403, 'not_yours', 'Only the receiving member may redeem this coupon');
  }
  if (coupon.redeemedAt) throw httpError(409, 'already_redeemed', 'This coupon was already redeemed');
  coupon.redeemedAt = nowIso();
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'coupon_redeemed', { coupon });
  sendJson(c.res, 200, { coupon });
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
  const body = await readJsonObject(c.req);
  if (!Number.isInteger(body.questionId)) throw httpError(400, 'invalid_request', '"questionId" must be an integer');
  const text = asText(body.text, 'text');
  const couple = c.auth.couple;
  if (!couple.daily[dateKey]) couple.daily[dateKey] = { questionId: body.questionId, answers: {} };
  const rec = couple.daily[dateKey];
  if (rec.questionId == null) rec.questionId = body.questionId;
  rec.answers[c.auth.memberId] = { text, answeredAt: nowIso() };
  c.store.markDirty();
  for (const member of couple.members) {
    c.realtime.sendToMember(couple.id, member.id, 'daily_answer', dailyEntryFor(couple, dateKey, member.id));
  }
  sendJson(c.res, 200, dailyEntryFor(couple, dateKey, c.auth.memberId));
});

// --- wordle duel ---------------------------------------------------------------------

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

route('GET', '/api/canvas', { auth: true }, (c) => {
  sendJson(c.res, 200, { strokes: c.auth.couple.strokes });
});

route('POST', '/api/canvas/strokes', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
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
  c.realtime.broadcastCouple(c.auth.coupleId, 'canvas_stroke', { stroke });
  sendJson(c.res, 201, { stroke });
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
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'canvas_clear', {});
  sendJson(c.res, 200, { ok: true });
});

// --- games ---------------------------------------------------------------------------------

route('POST', '/api/games', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
  const type = asEnum(body.type, 'type', GAME_TYPES);
  const couple = c.auth.couple;
  for (const g of couple.games) {
    if (g.state !== 'ended') finishGame(couple, g);
  }
  const game = {
    id: id('g'),
    type,
    state: 'lobby',
    createdBy: c.auth.memberId,
    payload: body.payload != null && typeof body.payload === 'object' && !Array.isArray(body.payload) ? body.payload : {},
    result: null,
    moves: [],
    createdAt: nowIso(),
  };
  couple.games.push(game);
  capList(couple.games, LIMITS.games);
  c.store.markDirty();
  c.realtime.broadcastCouple(couple.id, 'game_created', { game: serializeGame(game) });
  sendJson(c.res, 201, { game: serializeGame(game) });
});

route('POST', '/api/games/:id/join', { auth: true }, (c) => {
  const game = findGame(c.auth.couple, c.params.id);
  if (game.state === 'ended') throw httpError(409, 'game_ended', 'This game has already ended');
  if (game.state === 'lobby') {
    game.state = 'active';
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'game_started', { game: serializeGame(game) });
  }
  sendJson(c.res, 200, { game: serializeGame(game) });
});

route('POST', '/api/games/:id/move', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req);
  const game = findGame(c.auth.couple, c.params.id);
  if (game.state !== 'active') throw httpError(409, 'game_not_active', 'Moves are only allowed in an active game');
  const move = {
    id: id('mv'),
    memberId: c.auth.memberId,
    data: body.data != null && typeof body.data === 'object' && !Array.isArray(body.data) ? body.data : {},
    createdAt: nowIso(),
  };
  game.moves.push(move);
  c.store.markDirty();
  c.realtime.broadcastCouple(c.auth.coupleId, 'game_move', { gameId: game.id, move });
  sendJson(c.res, 201, { move });
});

route('POST', '/api/games/:id/end', { auth: true }, async (c) => {
  const body = await readJsonObject(c.req).catch((err) => {
    // Allow an empty body for "just end it".
    if (err instanceof HttpError && err.code === 'invalid_json') return {};
    throw err;
  });
  const game = findGame(c.auth.couple, c.params.id);
  const alreadyEnded = game.state === 'ended';
  if ('result' in body) game.result = body.result ?? null;
  if (!alreadyEnded) {
    finishGame(c.auth.couple, game);
    c.realtime.broadcastCouple(c.auth.coupleId, 'game_ended', { game: serializeGame(game) });
  }
  c.store.markDirty();
  sendJson(c.res, 200, { game: serializeGame(game) });
});

route('GET', '/api/games/active', { auth: true }, (c) => {
  const games = c.auth.couple.games;
  for (let i = games.length - 1; i >= 0; i--) {
    if (games[i].state === 'lobby' || games[i].state === 'active') {
      sendJson(c.res, 200, { game: serializeGame(games[i]) });
      return;
    }
  }
  sendJson(c.res, 200, { game: null });
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
    bucketDone: couple.bucket.filter((b) => b.done).length,
    bucketTotal: couple.bucket.length,
    dailyStreak: computeStreak(couple),
    dailyAnswered: Object.values(couple.daily).filter((rec) => rec.answers[me]?.text != null).length,
    gamesPlayed: couple.counters.gamesPlayed,
  });
});

// ---------------------------------------------------------------------------
// auth + top-level request handling

function authenticate(store, req, url, allowQueryToken) {
  let token = null;
  const header = req.headers.authorization;
  if (typeof header === 'string' && header.startsWith('Bearer ')) token = header.slice(7).trim();
  if (!token && allowQueryToken) token = url.searchParams.get('token');
  const rec = token ? store.data.tokens[token] : undefined;
  const couple = rec ? store.data.couples[rec.coupleId] : undefined;
  const member = couple?.members.find((m) => m.id === rec.memberId);
  if (!member) throw httpError(401, 'invalid_token', 'Unknown or expired token');
  return { token, coupleId: rec.coupleId, memberId: rec.memberId, couple, member };
}

export function createRouter({ store, realtime, config, log = () => {} }) {
  return async function handle(req, res) {
    res.setHeader('access-control-allow-origin', '*');
    res.setHeader('access-control-allow-methods', 'GET,POST,PATCH,DELETE,OPTIONS');
    res.setHeader('access-control-allow-headers', 'Authorization, Content-Type, X-Caption, X-Width, X-Height, X-Duration-Sec');
    try {
      if (req.method === 'OPTIONS') {
        res.writeHead(204, { 'access-control-max-age': '86400' });
        res.end();
        return;
      }
      let url;
      try {
        url = new URL(req.url, `http://${req.headers.host ?? 'localhost'}`);
      } catch {
        throw httpError(400, 'bad_request', 'Malformed request URL');
      }
      const match = matchRoute(req.method, url.pathname);
      if (!match) throw httpError(404, 'not_found', `No route for ${req.method} ${url.pathname}`);
      const auth = match.route.auth ? authenticate(store, req, url, Boolean(match.route.queryToken)) : null;
      await match.route.handler({ req, res, url, params: match.params, auth, store, realtime, config, log });
    } catch (err) {
      const status = err instanceof HttpError ? err.status : 500;
      const code = err instanceof HttpError ? err.code : 'internal_error';
      if (status === 500) log('http: unhandled error', err);
      if (!res.headersSent) {
        sendJson(res, status, { error: code, message: err?.message ?? 'Internal error' });
      } else {
        res.destroy();
      }
    }
  };
}
