import {
  HttpError,
  httpError,
  id,
  nowIso,
  todayKey,
  prevDateKey,
  nextDateKey,
  sendJson,
  readJsonObject,
} from './util.js';
import { emitAppEvent } from './events.js';

/**
 * SoooDreamy 5.0 — „Worte & Wärme" (Alltags-Wertschätzung).
 *
 * Registers the v5.0 everyday-warmth routes on the shared route table:
 *   - „3 gute Dinge"-Abendritual        (/api/goodthings)
 *   - Danke-Funken                      (/api/thanks)
 *   - „Ich vermisse dich"-Stufen        (/api/missyou)
 *   - Insider-Wörterbuch                (/api/dictionary)
 *   - Erste-Male-Sammlung               (/api/firsts)
 *
 * Lives in its own module (registered from router.js) following the v3.0
 * rituals.js pattern; all stores are lazily defaulted so pre-5.0 data files
 * keep working unchanged.
 */

const WARMTH_LIMITS = {
  goodthingsDays: 120,
  goodthingsItem: 160,
  thanks: 500,
  thanksText: 120,
  missyou: 200,
  missyouNote: 120,
  dictionary: 300,
  dictTerm: 60,
  dictDefinition: 300,
  dictStory: 300,
  firsts: 200,
  firstTitle: 120,
  firstNote: 300,
};

export const THANKS_CATEGORIES = ['listening', 'help', 'cooking', 'patience', 'surprise', 'being_you', 'custom'];

// ---------------------------------------------------------------------------
// store accessors (all lazily defaulted — pre-v5.0 stores lack them)

/** „3 gute Dinge": `{ [dateKey]: { [memberId]: { items: [{text, aboutPartner}], createdAt } } }`. */
function goodthingsOf(couple) {
  if (!couple.goodthings) couple.goodthings = {};
  return couple.goodthings;
}

/** Danke-Funken: `[{id, category, text, senderId, forMember, createdAt}]`. */
function thanksOf(couple) {
  if (!couple.thanks) couple.thanks = [];
  return couple.thanks;
}

/** Vermiss-Stufen: `[{id, level, note, senderId, forMember, createdAt, ackAt, ackNote}]`. */
function missyouOf(couple) {
  if (!couple.missyou) couple.missyou = [];
  return couple.missyou;
}

/** Insider-Wörterbuch: `[{id, term, definition, story, emoji, createdBy, createdAt, confirmedBy, confirmedAt}]`. */
function dictionaryOf(couple) {
  if (!couple.dictionary) couple.dictionary = [];
  return couple.dictionary;
}

/** Erste Male: `[{id, title, emoji, dateKey, note, photoId, createdBy, createdAt}]`. */
function firstsOf(couple) {
  if (!couple.firsts) couple.firsts = [];
  return couple.firsts;
}

// ---------------------------------------------------------------------------
// good-things helpers (reveal + streak semantics like the daily question)

function bothSharedOn(couple, dateKey) {
  const day = goodthingsOf(couple)[dateKey];
  if (!day || couple.members.length < 2) return false;
  return couple.members.every((member) => day[member.id] != null);
}

/** Consecutive both-shared days ending today (or yesterday if today is open). */
function goodthingsStreak(couple) {
  const today = todayKey();
  let cursor = null;
  if (bothSharedOn(couple, today)) cursor = today;
  else if (bothSharedOn(couple, prevDateKey(today))) cursor = prevDateKey(today);
  if (!cursor) return 0;
  let streak = 0;
  while (bothSharedOn(couple, cursor)) {
    streak += 1;
    cursor = prevDateKey(cursor);
  }
  return streak;
}

/**
 * Per-member view of one evening. Anti-spoiler like the daily question:
 * the partner's three good things only become readable once the viewer
 * shared their own for that day; `partnerShared` is always truthful.
 */
function goodthingsViewFor(couple, dateKey, viewerId, partnerOf) {
  const day = goodthingsOf(couple)[dateKey] ?? {};
  const partner = partnerOf(couple, viewerId);
  const mine = day[viewerId] ?? null;
  const theirs = partner ? (day[partner.id] ?? null) : null;
  return {
    dateKey,
    mine: mine ? mine.items : null,
    partner: mine && theirs ? theirs.items : null,
    partnerShared: Boolean(theirs),
    bothShared: bothSharedOn(couple, dateKey),
    streak: goodthingsStreak(couple),
  };
}

// ---------------------------------------------------------------------------
// route registration (called once from router.js)

/**
 * @param {(method: string, pattern: string, opts: object, handler: Function) => void} route
 * @param {{ asString: Function, asEnum: Function, asDateKey: Function, queryInt: Function,
 *           capList: Function, partnerOf: Function, notifyPartner: Function }} h
 */
export function registerWarmthRoutes(route, h) {
  const { asString, asEnum, asDateKey, queryInt, capList, partnerOf, notifyPartner } = h;

  /** dateKey within server-today ±1 (same rule as check-ins/daymemos). */
  const assertNearToday = (dateKey) => {
    const today = todayKey();
    if (dateKey !== today && dateKey !== prevDateKey(today) && dateKey !== nextDateKey(today)) {
      throw httpError(400, 'bad_datekey', `"dateKey" must be within one day of the server date (${today})`);
    }
  };

  const emptyBodyOk = (req) =>
    readJsonObject(req).catch((err) => {
      if (err instanceof HttpError && err.code === 'invalid_json') return {};
      throw err;
    });

  // --- „3 gute Dinge" (v5.0) ---------------------------------------------------------------
  //
  // The evidence-based evening gratitude ritual as a couple moment: each
  // member logs 1–3 tiny good moments of the day; the partner's list is
  // revealed only after sharing your own (daily-question pattern), with its
  // own 🔥 streak. Items can be flagged "my partner was part of this" —
  // those feed the "you in my good things" mentions feed.

  route('GET', '/api/goodthings', { auth: true }, (c) => {
    const limit = queryInt(c.url, 'limit', 30, 1, WARMTH_LIMITS.goodthingsDays);
    const couple = c.auth.couple;
    const dateKeys = Object.keys(goodthingsOf(couple)).sort().reverse().slice(0, limit);
    sendJson(c.res, 200, {
      days: dateKeys.map((key) => goodthingsViewFor(couple, key, c.auth.memberId, partnerOf)),
      streak: goodthingsStreak(couple),
    });
  });

  route('GET', '/api/goodthings/mentions', { auth: true }, (c) => {
    const couple = c.auth.couple;
    const partner = partnerOf(couple, c.auth.memberId);
    const store = goodthingsOf(couple);
    const mentions = [];
    for (const dateKey of Object.keys(store).sort().reverse()) {
      // Anti-spoiler holds here too: mentions only from days the viewer
      // shared as well (otherwise the feed would leak the partner's items).
      if (!partner || !store[dateKey][c.auth.memberId] || !store[dateKey][partner.id]) continue;
      const texts = store[dateKey][partner.id].items
        .filter((item) => item.aboutPartner)
        .map((item) => item.text);
      if (texts.length > 0) mentions.push({ dateKey, texts });
    }
    sendJson(c.res, 200, { mentions });
  });

  route('GET', '/api/goodthings/:dateKey', { auth: true }, (c) => {
    const dateKey = asDateKey(c.params.dateKey, 'dateKey');
    sendJson(c.res, 200, goodthingsViewFor(c.auth.couple, dateKey, c.auth.memberId, partnerOf));
  });

  route('POST', '/api/goodthings/:dateKey', { auth: true }, async (c) => {
    const dateKey = asDateKey(c.params.dateKey, 'dateKey');
    assertNearToday(dateKey);
    const body = await readJsonObject(c.req);
    if (!Array.isArray(body.items) || body.items.length < 1 || body.items.length > 3) {
      throw httpError(400, 'bad_items', '"items" must be an array of 1–3 good things');
    }
    const items = body.items.map((item) => ({
      text: asString(item?.text, 'text', { max: WARMTH_LIMITS.goodthingsItem }),
      aboutPartner: item?.aboutPartner === true,
    }));
    const couple = c.auth.couple;
    const store = goodthingsOf(couple);
    const wasBoth = bothSharedOn(couple, dateKey);
    if (!store[dateKey]) store[dateKey] = {};
    // Re-sharing replaces your own list for that day (like day memos).
    store[dateKey][c.auth.memberId] = { items, createdAt: nowIso() };
    const keys = Object.keys(store);
    if (keys.length > WARMTH_LIMITS.goodthingsDays) {
      keys.sort();
      for (const old of keys.slice(0, keys.length - WARMTH_LIMITS.goodthingsDays)) delete store[old];
    }
    c.store.markDirty();
    for (const member of couple.members) {
      c.realtime.sendToMember(couple.id, member.id, 'goodthings',
        goodthingsViewFor(couple, dateKey, member.id, partnerOf));
    }
    if (!wasBoth && bothSharedOn(couple, dateKey)) {
      emitAppEvent({ store: c.store, realtime: c.realtime, couple, type: 'goodthings_both',
                     memberId: null, data: { dateKey }, dedupeKey: dateKey });
    }
    sendJson(c.res, 201, goodthingsViewFor(couple, dateKey, c.auth.memberId, partnerOf));
  });

  // --- Danke-Funken (v5.0) -------------------------------------------------------------------
  //
  // One-tap appreciation sparks: gratitude never fails on intent, only on
  // friction. A spark is a category (+ optional note) that lands as a
  // glitter moment on the partner's phone; the weekly summary shows how
  // often — and for what — you thanked each other.

  route('GET', '/api/thanks', { auth: true }, (c) => {
    const limit = queryInt(c.url, 'limit', 30, 1, WARMTH_LIMITS.thanks);
    sendJson(c.res, 200, { thanks: thanksOf(c.auth.couple).slice(-limit).reverse() });
  });

  route('GET', '/api/thanks/summary', { auth: true }, (c) => {
    // Rolling 7-day window ending today (inclusive).
    let cursor = todayKey();
    const window = new Set();
    for (let day = 0; day < 7; day += 1) {
      window.add(cursor);
      cursor = prevDateKey(cursor);
    }
    const inWindow = thanksOf(c.auth.couple).filter((spark) => window.has(spark.createdAt.slice(0, 10)));
    const byCategory = {};
    const byMember = {};
    for (const spark of inWindow) {
      byCategory[spark.category] = (byCategory[spark.category] ?? 0) + 1;
      byMember[spark.senderId] = (byMember[spark.senderId] ?? 0) + 1;
    }
    const top = Object.entries(byCategory).sort((a, b) => b[1] - a[1])[0] ?? null;
    sendJson(c.res, 200, {
      days: 7,
      total: inWindow.length,
      byCategory,
      byMember,
      topCategory: top ? top[0] : null,
    });
  });

  route('POST', '/api/thanks', { auth: true }, async (c) => {
    const body = await readJsonObject(c.req);
    const partner = partnerOf(c.auth.couple, c.auth.memberId);
    if (!partner) throw httpError(409, 'no_partner', 'Thanks need a partner to receive them');
    const category = asEnum(body.category, 'category', THANKS_CATEGORIES);
    const text = body.text == null
      ? null
      : asString(body.text, 'text', { max: WARMTH_LIMITS.thanksText, nonEmpty: false }).trim() || null;
    if (category === 'custom' && !text) {
      throw httpError(400, 'bad_text', 'A custom thanks needs a note');
    }
    const spark = {
      id: id('th'),
      category,
      text,
      senderId: c.auth.memberId,
      forMember: partner.id,
      createdAt: nowIso(),
    };
    const list = thanksOf(c.auth.couple);
    list.push(spark);
    capList(list, WARMTH_LIMITS.thanks);
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'thanks', { spark });
    emitAppEvent({ store: c.store, realtime: c.realtime, couple: c.auth.couple, type: 'thanks_sent',
                   memberId: c.auth.memberId, data: { thanksId: spark.id, category } });
    notifyPartner(c, {
      type: 'thanks',
      title: { de: `${c.auth.member.name} sagt Danke ✨`, en: `${c.auth.member.name} says thank you ✨` },
      body: { de: 'Ein kleiner Danke-Funken ist für dich gelandet.', en: 'A little thank-you spark landed for you.' },
      link: 'sooodreamy://thanks',
    });
    sendJson(c.res, 201, { spark });
  });

  // --- „Ich vermisse dich"-Stufen (v5.0) -------------------------------------------------------
  //
  // Missing someone gets three honest, conflict-free levels: 1 = a soft glow
  // ("thinking of you"), 2 = a real pang ("missing you a lot right now"),
  // 3 = "I need your voice today — call when you can", answerable with one
  // tap ("Bin um 21 Uhr da ❤️"). Codified, never accusatory.

  route('GET', '/api/missyou', { auth: true }, (c) => {
    const limit = queryInt(c.url, 'limit', 30, 1, WARMTH_LIMITS.missyou);
    sendJson(c.res, 200, { missyou: missyouOf(c.auth.couple).slice(-limit).reverse() });
  });

  route('POST', '/api/missyou', { auth: true }, async (c) => {
    const body = await readJsonObject(c.req);
    const partner = partnerOf(c.auth.couple, c.auth.memberId);
    if (!partner) throw httpError(409, 'no_partner', 'Missing needs a partner to land with');
    const level = body.level;
    if (![1, 2, 3].includes(level)) {
      throw httpError(400, 'bad_level', '"level" must be 1, 2 or 3');
    }
    const note = body.note == null
      ? null
      : asString(body.note, 'note', { max: WARMTH_LIMITS.missyouNote, nonEmpty: false }).trim() || null;
    const signal = {
      id: id('my'),
      level,
      note,
      senderId: c.auth.memberId,
      forMember: partner.id,
      createdAt: nowIso(),
      ackAt: null,
      ackNote: null,
    };
    const list = missyouOf(c.auth.couple);
    list.push(signal);
    capList(list, WARMTH_LIMITS.missyou);
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'missyou', { signal });
    emitAppEvent({ store: c.store, realtime: c.realtime, couple: c.auth.couple, type: 'missyou_sent',
                   memberId: c.auth.memberId, data: { missyouId: signal.id, level } });
    notifyPartner(c, {
      type: 'missyou',
      title: level >= 3
        ? { de: `${c.auth.member.name} braucht heute deine Stimme`, en: `${c.auth.member.name} needs your voice today` }
        : { de: `${c.auth.member.name} vermisst dich`, en: `${c.auth.member.name} misses you` },
      body: level >= 3
        ? { de: 'Ruf an, sobald du kannst 📞', en: 'Call as soon as you can 📞' }
        : { de: 'Ein Vermiss-Signal ist für dich gelandet 🥺', en: 'A missing-you signal landed for you 🥺' },
      link: 'sooodreamy://missyou',
    });
    sendJson(c.res, 201, { signal });
  });

  // "Bin gleich da ❤️" — one tap back from the partner.
  route('POST', '/api/missyou/:id/ack', { auth: true }, async (c) => {
    const body = await emptyBodyOk(c.req);
    const signal = missyouOf(c.auth.couple).find((entry) => entry.id === c.params.id);
    if (!signal) throw httpError(404, 'not_found', 'Unknown missing-you signal');
    if (signal.forMember !== c.auth.memberId) {
      throw httpError(403, 'wrong_actor', 'Only the recipient may answer this signal');
    }
    if (signal.ackAt) throw httpError(409, 'already_acked', 'This signal was already answered');
    signal.ackAt = nowIso();
    signal.ackNote = body.note == null
      ? null
      : asString(body.note, 'note', { max: WARMTH_LIMITS.missyouNote, nonEmpty: false }).trim() || null;
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'missyou_ack', { signal });
    sendJson(c.res, 200, { signal });
  });

  // --- Insider-Wörterbuch (v5.0) ---------------------------------------------------------------
  //
  // The private language of a couple is its greatest treasure — and nobody
  // ever writes it down. Entries (term, definition, origin story, emoji) are
  // proposed by one member and CONFIRMED by the other (co-sign); editing a
  // confirmed entry resets the confirmation, keeping definitions honest.

  route('GET', '/api/dictionary', { auth: true }, (c) => {
    sendJson(c.res, 200, { entries: dictionaryOf(c.auth.couple).slice().reverse() });
  });

  route('POST', '/api/dictionary', { auth: true }, async (c) => {
    const body = await readJsonObject(c.req);
    const entry = {
      id: id('dx'),
      term: asString(body.term, 'term', { max: WARMTH_LIMITS.dictTerm }),
      definition: asString(body.definition, 'definition', { max: WARMTH_LIMITS.dictDefinition }),
      story: body.story == null
        ? null
        : asString(body.story, 'story', { max: WARMTH_LIMITS.dictStory, nonEmpty: false }).trim() || null,
      emoji: body.emoji == null ? null : asString(body.emoji, 'emoji', { max: 16 }),
      createdBy: c.auth.memberId,
      createdAt: nowIso(),
      confirmedBy: null,
      confirmedAt: null,
    };
    const list = dictionaryOf(c.auth.couple);
    list.push(entry);
    capList(list, WARMTH_LIMITS.dictionary);
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'dictionary_changed', { entry });
    sendJson(c.res, 201, { entry });
  });

  route('POST', '/api/dictionary/:id/confirm', { auth: true }, (c) => {
    const entry = dictionaryOf(c.auth.couple).find((candidate) => candidate.id === c.params.id);
    if (!entry) throw httpError(404, 'not_found', 'Unknown dictionary entry');
    if (entry.createdBy === c.auth.memberId) {
      throw httpError(403, 'wrong_actor', 'Only the partner may confirm a definition');
    }
    if (entry.confirmedAt) throw httpError(409, 'already_confirmed', 'This definition is already confirmed');
    entry.confirmedBy = c.auth.memberId;
    entry.confirmedAt = nowIso();
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'dictionary_changed', { entry });
    emitAppEvent({ store: c.store, realtime: c.realtime, couple: c.auth.couple, type: 'dictionary_confirmed',
                   memberId: c.auth.memberId, data: { entryId: entry.id }, dedupeKey: entry.id });
    sendJson(c.res, 200, { entry });
  });

  route('PATCH', '/api/dictionary/:id', { auth: true }, async (c) => {
    const body = await readJsonObject(c.req);
    const entry = dictionaryOf(c.auth.couple).find((candidate) => candidate.id === c.params.id);
    if (!entry) throw httpError(404, 'not_found', 'Unknown dictionary entry');
    if (entry.createdBy !== c.auth.memberId) {
      throw httpError(403, 'wrong_actor', 'Only the author may edit a definition');
    }
    if ('term' in body) entry.term = asString(body.term, 'term', { max: WARMTH_LIMITS.dictTerm });
    if ('definition' in body) {
      entry.definition = asString(body.definition, 'definition', { max: WARMTH_LIMITS.dictDefinition });
    }
    if ('story' in body) {
      entry.story = body.story == null
        ? null
        : asString(body.story, 'story', { max: WARMTH_LIMITS.dictStory, nonEmpty: false }).trim() || null;
    }
    if ('emoji' in body) entry.emoji = body.emoji == null ? null : asString(body.emoji, 'emoji', { max: 16 });
    // Content changed under the partner's signature — they re-confirm.
    entry.confirmedBy = null;
    entry.confirmedAt = null;
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'dictionary_changed', { entry });
    sendJson(c.res, 200, { entry });
  });

  route('DELETE', '/api/dictionary/:id', { auth: true }, (c) => {
    const list = dictionaryOf(c.auth.couple);
    const index = list.findIndex((candidate) => candidate.id === c.params.id);
    if (index === -1) throw httpError(404, 'not_found', 'Unknown dictionary entry');
    if (list[index].createdBy !== c.auth.memberId) {
      throw httpError(403, 'wrong_actor', 'Only the author may delete a definition');
    }
    const [removed] = list.splice(index, 1);
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'dictionary_deleted', { id: removed.id });
    sendJson(c.res, 200, { ok: true });
  });

  // --- Erste-Male-Sammlung (v5.0) ----------------------------------------------------------------
  //
  // A log of every "first": first kiss, first trip, first shared furniture —
  // with date, optional photo and one sentence. The app suggests missing
  // classics client-side (content pack) and the anniversary of each first
  // can become a moment.

  route('GET', '/api/firsts', { auth: true }, (c) => {
    const firsts = firstsOf(c.auth.couple)
      .slice()
      .sort((a, b) => (a.dateKey === b.dateKey ? (a.createdAt < b.createdAt ? -1 : 1) : (a.dateKey < b.dateKey ? -1 : 1)));
    sendJson(c.res, 200, { firsts });
  });

  route('POST', '/api/firsts', { auth: true }, async (c) => {
    const body = await readJsonObject(c.req);
    const dateKey = asDateKey(body.dateKey, 'dateKey');
    if (dateKey > todayKey()) throw httpError(400, 'bad_datekey', 'A first can only lie in the past');
    let photoId = null;
    if (body.photoId != null) {
      const photo = c.auth.couple.photos.find((candidate) => candidate.id === body.photoId);
      if (!photo) throw httpError(404, 'unknown_photo', 'No photo with this id in your gallery');
      photoId = photo.id;
    }
    const first = {
      id: id('fm'),
      title: asString(body.title, 'title', { max: WARMTH_LIMITS.firstTitle }),
      emoji: body.emoji == null ? null : asString(body.emoji, 'emoji', { max: 16 }),
      dateKey,
      note: body.note == null
        ? null
        : asString(body.note, 'note', { max: WARMTH_LIMITS.firstNote, nonEmpty: false }).trim() || null,
      photoId,
      createdBy: c.auth.memberId,
      createdAt: nowIso(),
    };
    const list = firstsOf(c.auth.couple);
    if (list.length >= WARMTH_LIMITS.firsts) {
      throw httpError(429, 'too_many_firsts', `At most ${WARMTH_LIMITS.firsts} firsts can be kept`);
    }
    list.push(first);
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'first_changed', { first });
    emitAppEvent({ store: c.store, realtime: c.realtime, couple: c.auth.couple, type: 'first_logged',
                   memberId: c.auth.memberId, data: { firstId: first.id, dateKey }, dedupeKey: first.id });
    sendJson(c.res, 201, { first });
  });

  route('PATCH', '/api/firsts/:id', { auth: true }, async (c) => {
    const body = await readJsonObject(c.req);
    const first = firstsOf(c.auth.couple).find((candidate) => candidate.id === c.params.id);
    if (!first) throw httpError(404, 'not_found', 'Unknown first');
    if (first.createdBy !== c.auth.memberId) {
      throw httpError(403, 'wrong_actor', 'Only the author may edit this first');
    }
    if ('title' in body) first.title = asString(body.title, 'title', { max: WARMTH_LIMITS.firstTitle });
    if ('emoji' in body) first.emoji = body.emoji == null ? null : asString(body.emoji, 'emoji', { max: 16 });
    if ('dateKey' in body) {
      const dateKey = asDateKey(body.dateKey, 'dateKey');
      if (dateKey > todayKey()) throw httpError(400, 'bad_datekey', 'A first can only lie in the past');
      first.dateKey = dateKey;
    }
    if ('note' in body) {
      first.note = body.note == null
        ? null
        : asString(body.note, 'note', { max: WARMTH_LIMITS.firstNote, nonEmpty: false }).trim() || null;
    }
    if ('photoId' in body) {
      if (body.photoId == null) first.photoId = null;
      else {
        const photo = c.auth.couple.photos.find((candidate) => candidate.id === body.photoId);
        if (!photo) throw httpError(404, 'unknown_photo', 'No photo with this id in your gallery');
        first.photoId = photo.id;
      }
    }
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'first_changed', { first });
    sendJson(c.res, 200, { first });
  });

  route('DELETE', '/api/firsts/:id', { auth: true }, (c) => {
    const list = firstsOf(c.auth.couple);
    const index = list.findIndex((candidate) => candidate.id === c.params.id);
    if (index === -1) throw httpError(404, 'not_found', 'Unknown first');
    if (list[index].createdBy !== c.auth.memberId) {
      throw httpError(403, 'wrong_actor', 'Only the author may delete this first');
    }
    const [removed] = list.splice(index, 1);
    c.store.markDirty();
    c.realtime.broadcastCouple(c.auth.coupleId, 'first_deleted', { id: removed.id });
    sendJson(c.res, 200, { ok: true });
  });
}
