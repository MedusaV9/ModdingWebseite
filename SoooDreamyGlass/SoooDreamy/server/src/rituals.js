import {
  HttpError,
  httpError,
  id,
  nowIso,
  todayKey,
  prevDateKey,
  nextDateKey,
  sendJson,
  readBody,
  readJsonObject,
} from './util.js';
import { APP_ERROR_CODES, appEventsOf, emitAppEvent } from './events.js';
import { allMessagesOf } from './message-archive.js';

/**
 * SoooDreamy 3.0 — „Rituale & Beziehung" (Agent A).
 *
 * Registers all v3.0 relationship-ritual routes on the shared route table:
 *   - Audio-Check-in „Wie war dein Tag?"  (/api/daymemos)
 *   - Zeitkapsel-Briefe                   (/api/capsules)
 *   - Bedürfnis-Knopf                     (/api/needs)
 *   - Gemeinsame Ziele & Sparziele        (/api/goals)
 *   - „Unsere Woche"-Wochenplan           (/api/weekplan)
 *   - Energie-Ampel                       (/api/energy)
 *   - „Unser Monat"-Magazin               (/api/magazine)
 *   - App-Event-Log (Meilensteine)        (/api/app-events, see events.js)
 *
 * Lives in its own module (registered from router.js) so the three 3.0
 * agents don't collide inside one giant file.
 */

const RITUAL_LIMITS = {
  memoAudio: 15 * 1024 * 1024, // like voice messages
  memoDays: 60,
  capsules: 100,
  capsuleTitle: 120,
  capsuleEmoji: 16,
  capsuleText: 5000,
  needs: 200,
  needNote: 200,
  goals: 50,
  goalTitle: 120,
  goalEmoji: 16,
  goalUnit: 20,
  goalNote: 200,
  goalContributions: 500,
  goalValue: 1e12,
  weekplanDays: 40, // availability dateKeys kept
  weekplanWindow: 27, // planning horizon in days (plus one day back)
  weekplanSlots: 60,
  slotTitle: 80,
  slotEmoji: 16,
  energyNote: 120,
  magazinePhotos: 5,
  magazineSeenMonths: 24,
  appEvents: 500,
};

const NEED_TYPES = ['space', 'comfort', 'distraction', 'closeness', 'listen'];
const SLOT_KINDS = ['call', 'movie', 'date', 'custom'];
const AVAILABILITY_STATUSES = ['free', 'busy', 'call', 'date'];
const ENERGY_LEVELS = ['green', 'yellow', 'red'];
const GOAL_MILESTONES = [25, 50, 75, 100];
const TIME_RE = /^([01]\d|2[0-3]):[0-5]\d$/;
const MONTH_RE = /^\d{4}-(0[1-9]|1[0-2])$/;

/** Energy traffic light stays visible for 12 h (like now-playing's 60 min). */
const ENERGY_FRESH_MS = 12 * 60 * 60 * 1000;

// ---------------------------------------------------------------------------
// store accessors (all lazily defaulted — pre-v3.0 stores lack them)

/** Audio check-ins: `{ [dateKey]: { [memberId]: {id, durationSec, recordedAt} } }`. */
function daymemosOf(couple) {
  if (!couple.daymemos) couple.daymemos = {};
  return couple.daymemos;
}

/** Time capsules: `[{id, title, emoji, text, photoId, unlockAt, createdBy, forMember, createdAt, openedAt}]`. */
function capsulesOf(couple) {
  if (!couple.capsules) couple.capsules = [];
  return couple.capsules;
}

/** Need signals: `[{id, type, note, senderId, forMember, createdAt, ackAt, ackNote}]`. */
export function needsOf(couple) {
  if (!couple.needs) couple.needs = [];
  return couple.needs;
}

/** Shared goals: `[{id, title, emoji, targetValue, unit, targetDate, createdBy, createdAt, completedAt, contributions}]`. */
function goalsOf(couple) {
  if (!couple.goals) couple.goals = [];
  return couple.goals;
}

/** Week plan: `{ availability: { [dateKey]: { [memberId]: {status, setAt} } }, slots: [...] }`. */
function weekplanOf(couple) {
  if (!couple.weekplan) couple.weekplan = { availability: {}, slots: [] };
  if (!couple.weekplan.availability) couple.weekplan.availability = {};
  if (!couple.weekplan.slots) couple.weekplan.slots = [];
  return couple.weekplan;
}

/** Magazine read receipts: `{ [month]: { [memberId]: iso } }`. */
function magazineSeenOf(couple) {
  if (!couple.magazineSeen) couple.magazineSeen = {};
  return couple.magazineSeen;
}

/** A member's energy traffic light; hidden once older than 12 hours. */
export function freshEnergy(member) {
  const energy = member.energy;
  if (!energy) return null;
  if (Date.now() - Date.parse(energy.setAt) > ENERGY_FRESH_MS) return null;
  return energy;
}

/** Deletes all ritual media (day-memo audio) of a couple — used on dissolve. */
export async function deleteRitualMedia(store, couple) {
  for (const day of Object.values(couple.daymemos ?? {})) {
    for (const memo of Object.values(day)) {
      await store.deleteMedia('voice', `${memo.id}.m4a`);
    }
  }
}

// ---------------------------------------------------------------------------
// day-memo helpers (reveal + streak semantics like the daily question)

function bothRecordedOn(couple, dateKey) {
  const day = daymemosOf(couple)[dateKey];
  if (!day || couple.members.length < 2) return false;
  return couple.members.every((m) => day[m.id] != null);
}

/** Consecutive both-recorded days ending today (or yesterday if today is open). */
function daymemoStreak(couple) {
  const today = todayKey();
  let cursor = null;
  if (bothRecordedOn(couple, today)) cursor = today;
  else if (bothRecordedOn(couple, prevDateKey(today))) cursor = prevDateKey(today);
  if (!cursor) return 0;
  let streak = 0;
  while (bothRecordedOn(couple, cursor)) {
    streak += 1;
    cursor = prevDateKey(cursor);
  }
  return streak;
}

function serializeMemo(memo) {
  if (!memo) return null;
  return {
    id: memo.id,
    url: `/api/daymemos/${memo.id}/raw`,
    durationSec: memo.durationSec,
    recordedAt: memo.recordedAt,
  };
}

/**
 * Per-member view of one day. Anti-spoiler like the daily question: the
 * partner's memo only becomes playable once the viewer recorded their own
 * for that day; `partnerRecorded` is always truthful.
 */
function daymemoViewFor(couple, dateKey, viewerId, partnerOf) {
  const day = daymemosOf(couple)[dateKey] ?? {};
  const partner = partnerOf(couple, viewerId);
  const mine = day[viewerId] ?? null;
  const theirs = partner ? (day[partner.id] ?? null) : null;
  return {
    dateKey,
    mine: serializeMemo(mine),
    partner: mine && theirs ? serializeMemo(theirs) : null,
    partnerRecorded: Boolean(theirs),
    bothRecorded: bothRecordedOn(couple, dateKey),
    streak: daymemoStreak(couple),
  };
}

// ---------------------------------------------------------------------------
// capsule helpers

/**
 * Per-viewer serialization — the SERVER holds the content back: `text` and
 * `photoId` stay null for the recipient until the capsule was opened (the
 * creator always sees their own words). `unlocked` = unlockAt has passed,
 * i.e. the recipient MAY open now.
 */
function serializeCapsule(capsule, viewerId) {
  const revealed = capsule.openedAt != null || viewerId === capsule.createdBy;
  return {
    id: capsule.id,
    title: capsule.title,
    emoji: capsule.emoji,
    unlockAt: capsule.unlockAt,
    createdBy: capsule.createdBy,
    forMember: capsule.forMember,
    createdAt: capsule.createdAt,
    openedAt: capsule.openedAt,
    unlocked: Date.parse(capsule.unlockAt) <= Date.now(),
    text: revealed ? capsule.text : null,
    photoId: revealed ? capsule.photoId : null,
  };
}

/** Keeps the list at `max`: oldest OPENED capsules go first, then oldest overall. */
function pruneCapsules(list, max) {
  const evicted = [];
  while (list.length > max) {
    const openedIdx = list.findIndex((cap) => cap.openedAt); // list is chronological
    evicted.push(...list.splice(openedIdx === -1 ? 0 : openedIdx, 1));
  }
  return evicted;
}

// ---------------------------------------------------------------------------
// goal helpers

function goalTotal(goal) {
  const sum = goal.contributions.reduce((acc, cn) => acc + cn.amount, 0);
  return Math.round(sum * 100) / 100;
}

function goalPercent(goal, total = goalTotal(goal)) {
  if (!(goal.targetValue > 0)) return 0;
  const raw = (total / goal.targetValue) * 100;
  return Math.max(0, Math.min(100, Math.round(raw * 10) / 10));
}

function serializeGoal(goal) {
  const total = goalTotal(goal);
  return { ...goal, total, percent: goalPercent(goal, total) };
}

function asGoalValue(value, field) {
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0 || n > RITUAL_LIMITS.goalValue) {
    throw httpError(400, 'bad_value', `"${field}" must be a positive number up to ${RITUAL_LIMITS.goalValue}`);
  }
  return Math.round(n * 100) / 100;
}

function findGoal(couple, goalId) {
  const goal = goalsOf(couple).find((g) => g.id === goalId);
  if (!goal) throw httpError(404, 'not_found', 'Unknown goal');
  return goal;
}

/**
 * Widget-snapshot teaser for Agent C: the active (uncompleted) goal with the
 * most recent activity (last contribution, else creation), compact shape.
 */
export function topGoalView(couple) {
  const active = goalsOf(couple).filter((g) => !g.completedAt);
  if (active.length === 0) return null;
  const lastActivity = (g) =>
    g.contributions.length > 0 ? g.contributions[g.contributions.length - 1].createdAt : g.createdAt;
  active.sort((x, y) => (lastActivity(x) < lastActivity(y) ? 1 : -1));
  const goal = active[0];
  const total = goalTotal(goal);
  return {
    id: goal.id,
    title: goal.title,
    emoji: goal.emoji,
    targetValue: goal.targetValue,
    unit: goal.unit,
    targetDate: goal.targetDate,
    total,
    percent: goalPercent(goal, total),
  };
}

// ---------------------------------------------------------------------------
// week-plan helpers

/** dateKey must be inside the planning window: [today-1 … today+27]. */
function assertPlannableDateKey(dateKey) {
  const today = todayKey();
  const diffDays = Math.round((Date.parse(`${dateKey}T00:00:00.000Z`) - Date.parse(`${today}T00:00:00.000Z`)) / 86_400_000);
  if (diffDays < -1 || diffDays > RITUAL_LIMITS.weekplanWindow) {
    throw httpError(400, 'bad_datekey', `"dateKey" must be between yesterday and ${RITUAL_LIMITS.weekplanWindow} days ahead`);
  }
}

/** 0 = Sunday … 6 = Saturday (UTC), matching JS `getUTCDay()`. */
function weekdayOf(dateKey) {
  return new Date(`${dateKey}T00:00:00.000Z`).getUTCDay();
}

function asSlotTime(value) {
  if (value == null) return null;
  if (typeof value !== 'string' || !TIME_RE.test(value)) {
    throw httpError(400, 'bad_time', '"time" must be an "HH:MM" string (24 h) or null');
  }
  return value;
}

function findSlot(couple, slotId) {
  const slot = weekplanOf(couple).slots.find((s) => s.id === slotId);
  if (!slot) throw httpError(404, 'not_found', 'Unknown week-plan slot');
  return slot;
}

function weekplanDayView(couple, dateKey) {
  const plan = weekplanOf(couple);
  const weekday = weekdayOf(dateKey);
  const availability = plan.availability[dateKey] ?? {};
  const slots = plan.slots.filter((s) => s.dateKey === dateKey || (s.dateKey == null && s.weekday === weekday));
  // Overlap ✨: both partners set a status and neither is "busy" that day.
  const overlap =
    couple.members.length === 2 &&
    couple.members.every((m) => {
      const status = availability[m.id]?.status;
      return status != null && status !== 'busy';
    });
  return { dateKey, weekday, availability, slots, overlap };
}

// ---------------------------------------------------------------------------
// magazine helpers

function assertMonth(value) {
  if (typeof value !== 'string' || !MONTH_RE.test(value)) {
    throw httpError(400, 'bad_month', '"month" must be a YYYY-MM string');
  }
  const current = todayKey().slice(0, 7);
  if (value > current) throw httpError(400, 'bad_month', 'The magazine can only look back, not ahead');
  return value;
}

/**
 * One deterministic monthly issue aggregated from data the server already
 * has (YearReview-style; capped lists make old months lower bounds).
 */
function buildMagazine(couple, month, { partnerOf, bothAnsweredOn, checkedInBothOn }) {
  const inMonth = (iso) => typeof iso === 'string' && iso.startsWith(month);

  // Top photos: favorites first, then newest — at most 5.
  const monthPhotos = couple.photos.filter((p) => inMonth(p.createdAt));
  monthPhotos.sort((x, y) => {
    const xFav = (x.favorites ?? []).length > 0 ? 1 : 0;
    const yFav = (y.favorites ?? []).length > 0 ? 1 : 0;
    if (xFav !== yFav) return yFav - xFav;
    return x.createdAt < y.createdAt ? 1 : -1;
  });
  const photos = monthPhotos.slice(0, RITUAL_LIMITS.magazinePhotos).map((p) => ({
    id: p.id,
    url: p.url,
    thumbUrl: p.thumbUrl ?? null,
    caption: p.caption ?? null,
    favorites: p.favorites ?? [],
  }));

  // Quote of the month: the both-answered daily entry with the most heart
  // (longest combined answers — deterministic, no RNG). Both answered ⇒
  // the answers are mutually revealed already, so this leaks nothing.
  let quote = null;
  let bestLen = -1;
  for (const dateKey of Object.keys(couple.daily ?? {})) {
    if (!dateKey.startsWith(month) || !bothAnsweredOn(couple, dateKey)) continue;
    const rec = couple.daily[dateKey];
    const answers = {};
    let len = 0;
    for (const member of couple.members) {
      const text = rec.answers[member.id]?.text ?? '';
      answers[member.id] = text;
      len += text.length;
    }
    if (len > bestLen || (len === bestLen && quote && dateKey > quote.dateKey)) {
      bestLen = len;
      quote = { dateKey, questionId: rec.questionId ?? null, answers };
    }
  }

  // Song of the month: added that month, most hearts, tie → newest.
  let song = null;
  for (const s of couple.songs ?? []) {
    if (!inMonth(s.createdAt)) continue;
    const hearts = (s.heartedBy ?? []).length;
    const currentHearts = song ? (song.heartedBy ?? []).length : -1;
    if (!song || hearts > currentHearts || (hearts === currentHearts && s.createdAt > song.createdAt)) {
      song = s;
    }
  }

  const games = (couple.games ?? []).filter((g) => inMonth(g.createdAt) && g.state === 'ended');
  const daymemos = daymemosOf(couple);
  const stats = {
    messages: allMessagesOf(couple).filter((m) => inMonth(m.createdAt)).length,
    touches: (couple.touches ?? []).filter((t) => inMonth(t.createdAt)).length,
    photosAdded: monthPhotos.length,
    videosAdded: (couple.videos ?? []).filter((v) => inMonth(v.createdAt)).length,
    gamesPlayed: games.length,
    wordleDays: Object.keys(couple.wordle ?? {}).filter((key) => key.startsWith(month)).length,
    dailyBothAnswered: Object.keys(couple.daily ?? {}).filter(
      (key) => key.startsWith(month) && bothAnsweredOn(couple, key),
    ).length,
    checkinDaysBoth: Object.keys(couple.checkins ?? {}).filter(
      (key) => key.startsWith(month) && checkedInBothOn(couple, key),
    ).length,
    daymemoDays: Object.keys(daymemos).filter(
      (key) => key.startsWith(month) && Object.keys(daymemos[key]).length > 0,
    ).length,
    hugsSent: (couple.hugs ?? []).filter((h) => inMonth(h.createdAt)).length,
    potdDays: Object.keys(couple.potd ?? {}).filter(
      (key) => key.startsWith(month) && Object.keys(couple.potd[key]).length > 0,
    ).length,
    goalsCompleted: goalsOf(couple).filter((g) => g.completedAt && inMonth(g.completedAt)).length,
  };

  return {
    month,
    generatedAt: nowIso(),
    photos,
    quote,
    song: song
      ? { id: song.id, title: song.title, artist: song.artist ?? null, heartedBy: song.heartedBy ?? [] }
      : null,
    stats,
    seen: magazineSeenOf(couple)[month] ?? {},
  };
}

/** Months (YYYY-MM, newest first) that hold at least some couple content. */
function magazineMonths(couple) {
  const months = new Set();
  const addIso = (iso) => {
    if (typeof iso === 'string' && iso.length >= 7) months.add(iso.slice(0, 7));
  };
  for (const p of couple.photos ?? []) addIso(p.createdAt);
  for (const v of couple.videos ?? []) addIso(v.createdAt);
  for (const m of allMessagesOf(couple)) addIso(m.createdAt);
  for (const h of couple.hugs ?? []) addIso(h.createdAt);
  for (const key of Object.keys(couple.daily ?? {})) addIso(key);
  for (const key of Object.keys(couple.potd ?? {})) addIso(key);
  for (const key of Object.keys(couple.checkins ?? {})) addIso(key);
  for (const key of Object.keys(couple.daymemos ?? {})) addIso(key);
  const current = todayKey().slice(0, 7);
  return [...months].filter((m) => m <= current).sort().reverse();
}

// ---------------------------------------------------------------------------
// route registration (called once from router.js)

/**
 * @param {(method: string, pattern: string, opts: object, handler: Function) => void} route
 * @param {{ asString: Function, asEnum: Function, asDateKey: Function, queryInt: Function,
 *           capList: Function, partnerOf: Function, serveFile: Function,
 *           bothAnsweredOn: Function, bothCheckedInOn: Function,
 *           notifyPartner: Function }} h  router-internal helpers
 */
export function registerRitualRoutes(route, h) {
  const {
    asString,
    asEnum,
    asDateKey,
    queryInt,
    capList,
    partnerOf,
    serveFile,
    notifyPartner,
  } = h;

  /** Optional emoji field shared by several endpoints. */
  const asEmoji = (value, max = 16) => (value == null ? null : asString(value, 'emoji', { max }));

  /** dateKey within server-today ±1 (same rule as check-ins/potd/wordle). */
  const assertNearToday = (dateKey) => {
    const today = todayKey();
    if (dateKey !== today && dateKey !== prevDateKey(today) && dateKey !== nextDateKey(today)) {
      throw httpError(400, 'bad_datekey', `"dateKey" must be within one day of the server date (${today})`);
    }
  };

  // --- audio check-in „Wie war dein Tag?" (v3.0) -----------------------------------------
  //
  // Evening voice ritual on the daily-question reveal pattern: record ≤ 15 MB
  // of audio/mp4 per member per day; the partner's memo only becomes
  // audible once you recorded yours. Streak = consecutive both-recorded days.

  route('GET', '/api/daymemos', { auth: true }, (c) => {
    const limit = queryInt(c.url, 'limit', 30, 1, RITUAL_LIMITS.memoDays);
    const couple = c.auth.couple;
    const dateKeys = Object.keys(daymemosOf(couple)).sort().reverse().slice(0, limit);
    sendJson(c.res, 200, {
      days: dateKeys.map((key) => daymemoViewFor(couple, key, c.auth.memberId, partnerOf)),
      streak: daymemoStreak(couple),
    });
  });

  route('GET', '/api/daymemos/:dateKey', { auth: true }, (c) => {
    const dateKey = asDateKey(c.params.dateKey, 'dateKey');
    sendJson(c.res, 200, daymemoViewFor(c.auth.couple, dateKey, c.auth.memberId, partnerOf));
  });

  // Raw audio. Anti-spoiler is enforced HERE too: the partner's file only
  // streams once the caller recorded their own memo for that day.
  route('GET', '/api/daymemos/:id/raw', { auth: true }, async (c) => {
    const daymemos = daymemosOf(c.auth.couple);
    let found = null;
    for (const [dateKey, day] of Object.entries(daymemos)) {
      for (const [memberId, memo] of Object.entries(day)) {
        if (memo.id === c.params.id) found = { dateKey, memberId, memo };
      }
    }
    if (!found) throw httpError(404, 'not_found', 'Unknown day memo');
    if (found.memberId !== c.auth.memberId && !daymemos[found.dateKey]?.[c.auth.memberId]) {
      throw httpError(403, 'not_revealed', 'Record your own memo for this day first');
    }
    await serveFile(c.req, c.res, c.store.mediaPath('voice', `${found.memo.id}.m4a`), 'audio/mp4');
  });

  route('POST', '/api/daymemos/:dateKey', { auth: true }, async (c) => {
    const dateKey = asDateKey(c.params.dateKey, 'dateKey');
    assertNearToday(dateKey);
    const buf = await readBody(c.req, RITUAL_LIMITS.memoAudio);
    if (buf.length === 0) throw httpError(400, 'empty_body', 'Day-memo upload body is empty');
    const duration = Number.parseFloat(c.req.headers['x-duration-sec']);
    const couple = c.auth.couple;
    const daymemos = daymemosOf(couple);
    const isFirstEver = Object.keys(daymemos).every((key) => Object.keys(daymemos[key]).length === 0);
    const wasBoth = bothRecordedOn(couple, dateKey);
    if (!daymemos[dateKey]) daymemos[dateKey] = {};
    // Re-recording replaces your own memo (and its file) for that day.
    const previous = daymemos[dateKey][c.auth.memberId];
    if (previous) await c.store.deleteMedia('voice', `${previous.id}.m4a`);
    const memoId = id('dm');
    await c.store.saveMedia('voice', `${memoId}.m4a`, buf);
    daymemos[dateKey][c.auth.memberId] = {
      id: memoId,
      durationSec: Number.isFinite(duration) ? Math.round(duration * 100) / 100 : null,
      recordedAt: nowIso(),
    };
    // Cap the archive at 60 days — dropped days lose their audio files too.
    const keys = Object.keys(daymemos);
    if (keys.length > RITUAL_LIMITS.memoDays) {
      keys.sort();
      for (const old of keys.slice(0, keys.length - RITUAL_LIMITS.memoDays)) {
        for (const memo of Object.values(daymemos[old])) {
          await c.store.deleteMedia('voice', `${memo.id}.m4a`);
        }
        delete daymemos[old];
      }
    }
    c.store.markDirty();
    for (const member of couple.members) {
      c.realtime.sendToMember(couple.id, member.id, 'daymemo', daymemoViewFor(couple, dateKey, member.id, partnerOf));
    }
    if (isFirstEver) {
      emitAppEvent({ store: c.store, realtime: c.realtime, couple, type: 'daymemo_first',
                     memberId: c.auth.memberId, data: { dateKey } });
    }
    if (!wasBoth && bothRecordedOn(couple, dateKey)) {
      emitAppEvent({ store: c.store, realtime: c.realtime, couple, type: 'daymemo_both',
                     memberId: null, data: { dateKey } });
    }
    sendJson(c.res, 201, daymemoViewFor(couple, dateKey, c.auth.memberId, partnerOf));
  });

  // --- time capsules (v3.0) --------------------------------------------------------------
  //
  // Sealed letters with a hard server-side unlock date: the payload (text +
  // optional gallery photo ref) is WITHHELD from the recipient until they
  // open the capsule after `unlockAt` — no client-side cheating possible.

  route('GET', '/api/capsules', { auth: true }, (c) => {
    sendJson(c.res, 200, {
      capsules: capsulesOf(c.auth.couple).slice().reverse().map((cap) => serializeCapsule(cap, c.auth.memberId)),
    });
  });

  route('POST', '/api/capsules', { auth: true }, async (c) => {
    const body = await readJsonObject(c.req);
    const partner = partnerOf(c.auth.couple, c.auth.memberId);
    if (!partner) throw httpError(409, 'no_partner', 'Capsules need a partner to receive them');
    if (typeof body.unlockAt !== 'string' || !Number.isFinite(Date.parse(body.unlockAt))) {
      throw httpError(400, 'bad_unlock', '"unlockAt" must be an ISO-8601 timestamp');
    }
    const unlockAt = new Date(Date.parse(body.unlockAt)).toISOString();
    if (Date.parse(unlockAt) <= Date.now()) {
      throw httpError(400, 'bad_unlock', '"unlockAt" must be in the future');
    }
    let photoId = null;
    if (body.photoId != null) {
      const photo = c.auth.couple.photos.find((p) => p.id === body.photoId);
      if (!photo) throw httpError(404, 'unknown_photo', 'No photo with this id in your gallery');
      photoId = photo.id;
    }
    const capsule = {
      id: id('cap'),
      title: body.title == null ? null : asString(body.title, 'title', { max: RITUAL_LIMITS.capsuleTitle }),
      emoji: asEmoji(body.emoji, RITUAL_LIMITS.capsuleEmoji),
      text: asString(body.text, 'text', { max: RITUAL_LIMITS.capsuleText, code: 'text_too_long' }),
      photoId,
      unlockAt,
      createdBy: c.auth.memberId,
      forMember: partner.id,
      createdAt: nowIso(),
      openedAt: null,
    };
    const list = capsulesOf(c.auth.couple);
    list.push(capsule);
    const evicted = pruneCapsules(list, RITUAL_LIMITS.capsules);
    c.store.markDirty();
    for (const old of evicted) c.realtime.broadcastCouple(c.auth.coupleId, 'capsule_deleted', { id: old.id });
    // Tailored per member: the recipient's frame has text/photoId nulled.
    for (const member of c.auth.couple.members) {
      c.realtime.sendToMember(c.auth.coupleId, member.id, 'capsule_sealed', {
        capsule: serializeCapsule(capsule, member.id),
      });
    }
    emitAppEvent({ store: c.store, realtime: c.realtime, couple: c.auth.couple, type: 'capsule_sealed',
                   memberId: c.auth.memberId, data: { capsuleId: capsule.id, unlockAt } });
    sendJson(c.res, 201, { capsule: serializeCapsule(capsule, c.auth.memberId) });
  });

  route('POST', '/api/capsules/:id/open', { auth: true }, (c) => {
    const capsule = capsulesOf(c.auth.couple).find((cap) => cap.id === c.params.id);
    if (!capsule) throw httpError(404, 'not_found', 'Unknown capsule');
    if (capsule.forMember !== c.auth.memberId) {
      throw httpError(403, 'not_yours', 'Only the receiving member may open this capsule');
    }
    if (capsule.openedAt) throw httpError(409, 'already_opened', 'This capsule was already opened');
    if (Date.parse(capsule.unlockAt) > Date.now()) {
      throw httpError(409, APP_ERROR_CODES.capsuleStillLocked, `Sealed until ${capsule.unlockAt}`);
    }
    capsule.openedAt = nowIso();
    c.store.markDirty();
    // Opened ⇒ content is mutually visible; one broadcast fits both.
    c.realtime.broadcastCouple(c.auth.coupleId, 'capsule_opened', {
      capsule: serializeCapsule(capsule, c.auth.memberId),
    });
    emitAppEvent({ store: c.store, realtime: c.realtime, couple: c.auth.couple, type: 'capsule_opened',
                   memberId: c.auth.memberId, data: { capsuleId: capsule.id } });
    sendJson(c.res, 200, { capsule: serializeCapsule(capsule, c.auth.memberId) });
  });

  route('DELETE', '/api/capsules/:id', { auth: true }, (c) => {
    const list = capsulesOf(c.auth.couple);
    const capsule = list.find((cap) => cap.id === c.params.id);
    if (!capsule) throw httpError(404, 'not_found', 'Unknown capsule');
    if (capsule.createdBy !== c.auth.memberId) {
      throw httpError(403, 'not_yours', 'Only the creator may delete a capsule');
    }
    if (capsule.openedAt) throw httpError(409, 'already_opened', 'Opened capsules are part of your history');
    list.splice(list.indexOf(capsule), 1);
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'capsule_deleted', { id: capsule.id });
    sendJson(c.res, 200, { ok: true });
  });

  // --- need button „Ich brauche gerade…" (v3.0) --------------------------------------------
  //
  // One-tap, shame-free signals: space / comfort / distraction / closeness /
  // listen. The partner acknowledges with one tap; history is kept so the
  // pattern ("she needed space a lot this week") stays visible.

  route('GET', '/api/needs', { auth: true }, (c) => {
    const limit = queryInt(c.url, 'limit', 30, 1, RITUAL_LIMITS.needs);
    sendJson(c.res, 200, { needs: needsOf(c.auth.couple).slice(-limit).reverse() });
  });

  route('POST', '/api/needs', { auth: true }, async (c) => {
    const body = await readJsonObject(c.req);
    const partner = partnerOf(c.auth.couple, c.auth.memberId);
    if (!partner) throw httpError(409, 'no_partner', 'Needs need a partner to hear them');
    const need = {
      id: id('nd'),
      type: asEnum(body.type, 'type', NEED_TYPES),
      note: body.note == null ? null : asString(body.note, 'note', { max: RITUAL_LIMITS.needNote, nonEmpty: false }),
      senderId: c.auth.memberId,
      forMember: partner.id,
      createdAt: nowIso(),
      ackAt: null,
      ackNote: null,
    };
    const list = needsOf(c.auth.couple);
    list.push(need);
    capList(list, RITUAL_LIMITS.needs);
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'need', { need });
    emitAppEvent({ store: c.store, realtime: c.realtime, couple: c.auth.couple, type: 'need_sent',
                   memberId: c.auth.memberId, data: { needId: need.id, needType: need.type } });
    notifyPartner(c, {
      type: 'need',
      title: { de: `${c.auth.member.name} braucht dich`, en: `${c.auth.member.name} needs you` },
      body: {
        de: 'Ein persönliches Bedürfnis wartet auf deine Antwort.',
        en: 'A personal need is waiting for your response.',
      },
      link: 'sooodreamy://need',
    });
    sendJson(c.res, 201, { need });
  });

  // "Bin für dich da 🤍" — one tap back from the partner.
  route('POST', '/api/needs/:id/ack', { auth: true }, async (c) => {
    const body = await readJsonObject(c.req).catch((err) => {
      if (err instanceof HttpError && err.code === 'invalid_json') return {};
      throw err;
    });
    const need = needsOf(c.auth.couple).find((n) => n.id === c.params.id);
    if (!need) throw httpError(404, 'not_found', 'Unknown need');
    if (need.forMember !== c.auth.memberId) {
      throw httpError(403, 'not_yours', 'Only the receiving member may respond to this need');
    }
    if (need.ackAt) throw httpError(409, 'already_acked', 'This need was already answered');
    need.ackAt = nowIso();
    need.ackNote = body.note == null ? null : asString(body.note, 'note', { max: RITUAL_LIMITS.needNote, nonEmpty: false });
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'need_acked', { need });
    sendJson(c.res, 200, { need });
  });

  // --- shared goals & savings goals (v3.0) --------------------------------------------------

  route('GET', '/api/goals', { auth: true }, (c) => {
    sendJson(c.res, 200, { goals: goalsOf(c.auth.couple).slice().reverse().map(serializeGoal) });
  });

  route('POST', '/api/goals', { auth: true }, async (c) => {
    const body = await readJsonObject(c.req);
    const goals = goalsOf(c.auth.couple);
    if (goals.length >= RITUAL_LIMITS.goals) {
      throw httpError(413, 'too_many_goals', `At most ${RITUAL_LIMITS.goals} goals per couple — finish some first 😉`);
    }
    const goal = {
      id: id('gl'),
      title: asString(body.title, 'title', { max: RITUAL_LIMITS.goalTitle }),
      emoji: asEmoji(body.emoji, RITUAL_LIMITS.goalEmoji),
      targetValue: asGoalValue(body.targetValue, 'targetValue'),
      unit: body.unit == null ? null : asString(body.unit, 'unit', { max: RITUAL_LIMITS.goalUnit }),
      targetDate: body.targetDate == null ? null : asDateKey(body.targetDate, 'targetDate'),
      createdBy: c.auth.memberId,
      createdAt: nowIso(),
      completedAt: null,
      contributions: [],
    };
    goals.push(goal);
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'goal_added', { goal: serializeGoal(goal) });
    emitAppEvent({ store: c.store, realtime: c.realtime, couple: c.auth.couple, type: 'goal_created',
                   memberId: c.auth.memberId, data: { goalId: goal.id } });
    sendJson(c.res, 201, { goal: serializeGoal(goal) });
  });

  // Book progress in any increments (negative = correction). Milestone
  // crossings (25/50/75/100 %) ride along in the broadcast for confetti.
  route('POST', '/api/goals/:id/contributions', { auth: true }, async (c) => {
    const body = await readJsonObject(c.req);
    const goal = findGoal(c.auth.couple, c.params.id);
    if (goal.contributions.length >= RITUAL_LIMITS.goalContributions) {
      throw httpError(413, 'too_many_contributions',
        `At most ${RITUAL_LIMITS.goalContributions} contributions per goal`);
    }
    const n = Number(body.amount);
    if (!Number.isFinite(n) || n === 0 || Math.abs(n) > RITUAL_LIMITS.goalValue) {
      throw httpError(400, 'bad_value', '"amount" must be a non-zero number');
    }
    const before = (goalTotal(goal) / goal.targetValue) * 100;
    const contribution = {
      id: id('gc'),
      memberId: c.auth.memberId,
      amount: Math.round(n * 100) / 100,
      note: body.note == null ? null : asString(body.note, 'note', { max: RITUAL_LIMITS.goalNote, nonEmpty: false }),
      createdAt: nowIso(),
    };
    goal.contributions.push(contribution);
    const after = (goalTotal(goal) / goal.targetValue) * 100;
    const crossed = GOAL_MILESTONES.filter((m) => before < m && after >= m);
    const milestone = crossed.length > 0 ? crossed[crossed.length - 1] : null;
    // completedAt tracks the truth (corrections may re-open a goal).
    if (after >= 100 && !goal.completedAt) goal.completedAt = nowIso();
    else if (after < 100 && goal.completedAt) goal.completedAt = null;
    c.store.markDirty();
    const serialized = serializeGoal(goal);
    c.realtime.broadcastCouple(c.auth.coupleId, 'goal_updated', { goal: serialized, milestone });
    for (const m of crossed) {
      emitAppEvent({ store: c.store, realtime: c.realtime, couple: c.auth.couple,
                     type: m === 100 ? 'goal_reached' : 'goal_milestone',
                     memberId: c.auth.memberId,
                     data: m === 100 ? { goalId: goal.id } : { goalId: goal.id, percent: m } });
    }
    sendJson(c.res, 201, { contribution, goal: serialized, milestone });
  });

  // Goals are a joint project: BOTH partners may edit or delete any goal.
  route('PATCH', '/api/goals/:id', { auth: true }, async (c) => {
    const body = await readJsonObject(c.req);
    const goal = findGoal(c.auth.couple, c.params.id);
    if ('title' in body) goal.title = asString(body.title, 'title', { max: RITUAL_LIMITS.goalTitle });
    if ('emoji' in body) goal.emoji = asEmoji(body.emoji, RITUAL_LIMITS.goalEmoji);
    if ('targetValue' in body) goal.targetValue = asGoalValue(body.targetValue, 'targetValue');
    if ('unit' in body) goal.unit = body.unit == null ? null : asString(body.unit, 'unit', { max: RITUAL_LIMITS.goalUnit });
    if ('targetDate' in body) goal.targetDate = body.targetDate == null ? null : asDateKey(body.targetDate, 'targetDate');
    // A changed target may flip the completion state — keep it truthful.
    const percent = (goalTotal(goal) / goal.targetValue) * 100;
    if (percent >= 100 && !goal.completedAt) goal.completedAt = nowIso();
    else if (percent < 100 && goal.completedAt) goal.completedAt = null;
    c.store.markDirty();
    const serialized = serializeGoal(goal);
    c.realtime.broadcastCouple(c.auth.coupleId, 'goal_updated', { goal: serialized, milestone: null });
    sendJson(c.res, 200, { goal: serialized });
  });

  route('DELETE', '/api/goals/:id', { auth: true }, (c) => {
    const goals = goalsOf(c.auth.couple);
    const goal = findGoal(c.auth.couple, c.params.id);
    goals.splice(goals.indexOf(goal), 1);
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'goal_deleted', { id: goal.id });
    sendJson(c.res, 200, { ok: true });
  });

  // --- "Unsere Woche" week plan (v3.0) -------------------------------------------------------
  //
  // Deliberately NOT a calendar sync: each member marks days as free / busy /
  // call / date; shared slots (movie night, sunday call …) are one-off
  // (dateKey) or recurring (weekday 0–6, 0 = Sunday, UTC).

  route('GET', '/api/weekplan', { auth: true }, (c) => {
    const startRaw = c.url.searchParams.get('start');
    const start = startRaw == null || startRaw === '' ? todayKey() : asDateKey(startRaw, 'start');
    const days = queryInt(c.url, 'days', 7, 1, 14);
    const couple = c.auth.couple;
    const views = [];
    let cursor = start;
    for (let i = 0; i < days; i++) {
      views.push(weekplanDayView(couple, cursor));
      cursor = nextDateKey(cursor);
    }
    sendJson(c.res, 200, { start, days: views, slots: weekplanOf(couple).slots });
  });

  route('PUT', '/api/weekplan/:dateKey/availability', { auth: true }, async (c) => {
    const dateKey = asDateKey(c.params.dateKey, 'dateKey');
    assertPlannableDateKey(dateKey);
    const body = await readJsonObject(c.req);
    const status = body.status == null ? null : asEnum(body.status, 'status', AVAILABILITY_STATUSES);
    const plan = weekplanOf(c.auth.couple);
    if (status === null) {
      if (plan.availability[dateKey]) {
        delete plan.availability[dateKey][c.auth.memberId];
        if (Object.keys(plan.availability[dateKey]).length === 0) delete plan.availability[dateKey];
      }
    } else {
      if (!plan.availability[dateKey]) plan.availability[dateKey] = {};
      plan.availability[dateKey][c.auth.memberId] = { status, setAt: nowIso() };
      const keys = Object.keys(plan.availability);
      if (keys.length > RITUAL_LIMITS.weekplanDays) {
        keys.sort();
        for (const old of keys.slice(0, keys.length - RITUAL_LIMITS.weekplanDays)) delete plan.availability[old];
      }
    }
    c.store.markDirty();
    const day = weekplanDayView(c.auth.couple, dateKey);
    c.realtime.broadcastCouple(c.auth.coupleId, 'weekplan_availability', {
      dateKey,
      memberId: c.auth.memberId,
      status,
      day,
    });
    sendJson(c.res, 200, { day });
  });

  route('POST', '/api/weekplan/slots', { auth: true }, async (c) => {
    const body = await readJsonObject(c.req);
    const plan = weekplanOf(c.auth.couple);
    if (plan.slots.length >= RITUAL_LIMITS.weekplanSlots) {
      throw httpError(413, 'too_many_slots', `At most ${RITUAL_LIMITS.weekplanSlots} week-plan slots per couple`);
    }
    const hasDateKey = body.dateKey != null;
    const hasWeekday = body.weekday != null;
    if (hasDateKey === hasWeekday) {
      throw httpError(400, 'bad_slot', 'Provide exactly one of "dateKey" (one-off) or "weekday" (recurring, 0–6)');
    }
    if (hasWeekday && (!Number.isInteger(body.weekday) || body.weekday < 0 || body.weekday > 6)) {
      throw httpError(400, 'bad_slot', '"weekday" must be an integer 0 (Sunday) … 6 (Saturday)');
    }
    const slot = {
      id: id('ws'),
      title: asString(body.title, 'title', { max: RITUAL_LIMITS.slotTitle }),
      emoji: asEmoji(body.emoji, RITUAL_LIMITS.slotEmoji),
      kind: body.kind == null ? 'custom' : asEnum(body.kind, 'kind', SLOT_KINDS),
      dateKey: hasDateKey ? asDateKey(body.dateKey, 'dateKey') : null,
      weekday: hasWeekday ? body.weekday : null,
      time: asSlotTime(body.time),
      createdBy: c.auth.memberId,
      createdAt: nowIso(),
    };
    plan.slots.push(slot);
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'weekplan_slot_added', { slot });
    emitAppEvent({ store: c.store, realtime: c.realtime, couple: c.auth.couple, type: 'weekplan_slot_created',
                   memberId: c.auth.memberId, data: { slotId: slot.id, kind: slot.kind } });
    sendJson(c.res, 201, { slot });
  });

  // The plan is shared: BOTH partners may edit or delete any slot.
  route('PATCH', '/api/weekplan/slots/:id', { auth: true }, async (c) => {
    const body = await readJsonObject(c.req);
    const slot = findSlot(c.auth.couple, c.params.id);
    if ('title' in body) slot.title = asString(body.title, 'title', { max: RITUAL_LIMITS.slotTitle });
    if ('emoji' in body) slot.emoji = asEmoji(body.emoji, RITUAL_LIMITS.slotEmoji);
    if ('kind' in body) slot.kind = asEnum(body.kind, 'kind', SLOT_KINDS);
    if ('time' in body) slot.time = asSlotTime(body.time);
    // Switching between one-off and recurring keeps the invariant:
    // exactly one of dateKey / weekday is set.
    if ('dateKey' in body && body.dateKey != null) {
      slot.dateKey = asDateKey(body.dateKey, 'dateKey');
      slot.weekday = null;
    } else if ('weekday' in body && body.weekday != null) {
      if (!Number.isInteger(body.weekday) || body.weekday < 0 || body.weekday > 6) {
        throw httpError(400, 'bad_slot', '"weekday" must be an integer 0 (Sunday) … 6 (Saturday)');
      }
      slot.weekday = body.weekday;
      slot.dateKey = null;
    }
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'weekplan_slot_updated', { slot });
    sendJson(c.res, 200, { slot });
  });

  route('DELETE', '/api/weekplan/slots/:id', { auth: true }, (c) => {
    const plan = weekplanOf(c.auth.couple);
    const slot = findSlot(c.auth.couple, c.params.id);
    plan.slots.splice(plan.slots.indexOf(slot), 1);
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'weekplan_slot_deleted', { id: slot.id });
    sendJson(c.res, 200, { ok: true });
  });

  // --- energy traffic light (v3.0) -----------------------------------------------------------
  //
  // 🟢🟡🔴 after-work status with a 12 h TTL (now-playing mechanic): the
  // partner sees your battery BEFORE walking in / calling. Lives on the
  // member object (serialized as `energy`, null once stale).

  route('PUT', '/api/energy', { auth: true }, async (c) => {
    const body = await readJsonObject(c.req);
    const energy = {
      level: asEnum(body.level, 'level', ENERGY_LEVELS),
      note: body.note == null
        ? null
        : asString(body.note, 'note', { max: RITUAL_LIMITS.energyNote, nonEmpty: false }),
      setAt: nowIso(),
    };
    c.auth.member.energy = energy;
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'energy', { memberId: c.auth.memberId, energy });
    sendJson(c.res, 200, { energy });
  });

  route('DELETE', '/api/energy', { auth: true }, (c) => {
    c.auth.member.energy = null;
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'energy', { memberId: c.auth.memberId, energy: null });
    sendJson(c.res, 200, { ok: true });
  });

  // --- "Unser Monat" magazine (v3.0) ----------------------------------------------------------
  //
  // A deterministic monthly issue aggregated on demand (YearReview pattern):
  // top-5 photos, the "quote of the month" (longest both-answered daily
  // entry), song of the month, and a stats spread. `seen` receipts let both
  // clients celebrate the reveal together.

  route('GET', '/api/magazine/months', { auth: true }, (c) => {
    sendJson(c.res, 200, { months: magazineMonths(c.auth.couple) });
  });

  route('GET', '/api/magazine/:month', { auth: true }, (c) => {
    const month = assertMonth(c.params.month);
    sendJson(c.res, 200, buildMagazine(c.auth.couple, month, {
      partnerOf,
      bothAnsweredOn: h.bothAnsweredOn,
      checkedInBothOn: h.bothCheckedInOn,
    }));
  });

  route('POST', '/api/magazine/:month/seen', { auth: true }, (c) => {
    const month = assertMonth(c.params.month);
    const seen = magazineSeenOf(c.auth.couple);
    if (!seen[month]) seen[month] = {};
    const wasBoth = c.auth.couple.members.length === 2 &&
      c.auth.couple.members.every((m) => seen[month][m.id] != null);
    if (!seen[month][c.auth.memberId]) {
      seen[month][c.auth.memberId] = nowIso();
      const keys = Object.keys(seen);
      if (keys.length > RITUAL_LIMITS.magazineSeenMonths) {
        keys.sort();
        for (const old of keys.slice(0, keys.length - RITUAL_LIMITS.magazineSeenMonths)) delete seen[old];
      }
      c.store.markDirty();
      c.realtime.broadcastCouple(c.auth.coupleId, 'magazine_seen', {
        month,
        memberId: c.auth.memberId,
        seen: seen[month],
      });
      const isBothNow = c.auth.couple.members.length === 2 &&
        c.auth.couple.members.every((m) => seen[month][m.id] != null);
      if (!wasBoth && isBothNow) {
        emitAppEvent({ store: c.store, realtime: c.realtime, couple: c.auth.couple,
                       type: 'magazine_seen_both', memberId: null, data: { month } });
      }
    }
    sendJson(c.res, 200, { month, seen: seen[month] });
  });

  // --- app events (v3.0 milestone feed — see events.js for the contract) ----------------------

  route('GET', '/api/app-events', { auth: true }, (c) => {
    const limit = queryInt(c.url, 'limit', 100, 1, RITUAL_LIMITS.appEvents);
    const type = c.url.searchParams.get('type');
    let events = appEventsOf(c.auth.couple);
    if (type) events = events.filter((e) => e.type === type);
    sendJson(c.res, 200, { events: events.slice(-limit).reverse() });
  });
}
