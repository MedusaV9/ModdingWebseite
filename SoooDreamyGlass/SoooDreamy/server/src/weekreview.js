import { httpError, nowIso, sendJson, readJsonObject, todayKey } from './util.js';
import { emitAppEvent, appEventsOf } from './events.js';
import { allMessagesOf } from './message-archive.js';

/**
 * „Eure Woche" — weekly review ritual (v7.0).
 *
 * One deterministic weekly issue (magazine-style, ISO week Mon–Sun in UTC —
 * the same clock all dateKeys use) plus a small mutual ritual on top:
 * each partner shares their personal highlight of the week, and the
 * partner's pick stays hidden until BOTH shared (daily-question semantics).
 *
 * Endpoints (registered from router.js):
 *   GET  /api/week-review?week=YYYY-Www   aggregated stats + quote + highlight state
 *   PUT  /api/week-review/:week/highlight { text, photoId? } (current/previous week only)
 *   POST /api/week-review/:week/seen      read receipt (completed weeks only)
 *
 * App events: `week_highlight_both` (both shared a highlight for a week) and
 * `week_review_both` (both read a completed week) — each exactly once per week.
 */

const WEEK_LIMITS = {
  highlightText: 300,
  weeksKept: 26, // highlight + seen entries kept per couple
  lookbackWeeks: 104, // how far back GET may ask
  highlightArchive: 104, // compact text-only archive: 2 members × 52 weeks
};

// An answer with at least this many trimmed chars counts as a "complete"
// sentence for the quote pick — below it lives "Ja ❤️"/"ok" territory.
const QUOTE_MIN_ANSWER = 12;

const WEEK_RE = /^\d{4}-W(0[1-9]|[1-4]\d|5[0-3])$/;
const DAY_MS = 86_400_000;

// ---------------------------------------------------------------------------
// ISO week math (pure, UTC — mirrored bit-for-bit by WeekReviewLogic.swift)

/** '2026-08-13' → '2026-W33' (ISO 8601 week, UTC). */
export function weekKeyOf(dateKey) {
  const date = new Date(`${dateKey}T00:00:00Z`);
  if (Number.isNaN(date.getTime())) throw httpError(400, 'bad_datekey', 'Invalid dateKey');
  // Shift to the Thursday of this ISO week — its calendar year IS the ISO year.
  const thursday = new Date(date.getTime());
  const weekday = (thursday.getUTCDay() + 6) % 7; // Mon=0 … Sun=6
  thursday.setUTCDate(thursday.getUTCDate() - weekday + 3);
  const isoYear = thursday.getUTCFullYear();
  const yearStart = Date.UTC(isoYear, 0, 1);
  const week = Math.ceil(((thursday.getTime() - yearStart) / DAY_MS + 1) / 7);
  return `${isoYear}-W${String(week).padStart(2, '0')}`;
}

/** '2026-W33' → '2026-08-10' (the week's Monday). Throws on malformed keys. */
export function weekStartDateKey(weekKey) {
  if (typeof weekKey !== 'string' || !WEEK_RE.test(weekKey)) {
    throw httpError(400, 'bad_week', '"week" must be a YYYY-Www ISO week key');
  }
  const year = Number.parseInt(weekKey.slice(0, 4), 10);
  const week = Number.parseInt(weekKey.slice(6), 10);
  // Jan 4 is always inside ISO week 1.
  const jan4 = new Date(Date.UTC(year, 0, 4));
  const jan4Weekday = (jan4.getUTCDay() + 6) % 7;
  const monday = new Date(jan4.getTime() - jan4Weekday * DAY_MS + (week - 1) * 7 * DAY_MS);
  const key = monday.toISOString().slice(0, 10);
  // Reject week numbers past the year's last ISO week (e.g. 2026-W53).
  if (weekKeyOf(key) !== weekKey) {
    throw httpError(400, 'bad_week', `${weekKey} is not a valid ISO week`);
  }
  return key;
}

/** All seven dateKeys (Mon…Sun) of an ISO week. */
export function weekDateKeys(weekKey) {
  const start = new Date(`${weekStartDateKey(weekKey)}T00:00:00Z`);
  return Array.from({ length: 7 }, (_, i) =>
    new Date(start.getTime() + i * DAY_MS).toISOString().slice(0, 10));
}

/** The week key immediately before `weekKey`. */
export function previousWeekKey(weekKey) {
  const start = new Date(`${weekStartDateKey(weekKey)}T00:00:00Z`);
  return weekKeyOf(new Date(start.getTime() - 7 * DAY_MS).toISOString().slice(0, 10));
}

// ---------------------------------------------------------------------------
// store accessor

/** `{ highlights: { [week]: { [memberId]: {text, photoId, setAt} } }, seen: { [week]: { [memberId]: iso } } }` */
function weekReviewOf(couple) {
  if (!couple.weekReview) couple.weekReview = { highlights: {}, seen: {} };
  if (!couple.weekReview.highlights) couple.weekReview.highlights = {};
  if (!couple.weekReview.seen) couple.weekReview.seen = {};
  return couple.weekReview;
}

function capWeeks(bucket) {
  const keys = Object.keys(bucket);
  if (keys.length > WEEK_LIMITS.weeksKept) {
    keys.sort();
    for (const old of keys.slice(0, keys.length - WEEK_LIMITS.weeksKept)) delete bucket[old];
  }
}

/**
 * Capping the highlights bucket must not destroy the most personal texts the
 * couple ever wrote — evicted weeks are first copied (text only, compact)
 * into `review.highlightArchive: [{week, memberId, text}]`, oldest first,
 * itself capped to a full year of entries. The year review reads from it.
 */
function capHighlightsWithArchive(review) {
  const keys = Object.keys(review.highlights);
  if (keys.length <= WEEK_LIMITS.weeksKept) return;
  keys.sort();
  if (!Array.isArray(review.highlightArchive)) review.highlightArchive = [];
  for (const old of keys.slice(0, keys.length - WEEK_LIMITS.weeksKept)) {
    for (const [memberId, highlight] of Object.entries(review.highlights[old])) {
      if (highlight?.text) review.highlightArchive.push({ week: old, memberId, text: highlight.text });
    }
    delete review.highlights[old];
  }
  if (review.highlightArchive.length > WEEK_LIMITS.highlightArchive) {
    review.highlightArchive.splice(0, review.highlightArchive.length - WEEK_LIMITS.highlightArchive);
  }
}

/**
 * All highlights of a calendar (ISO) year, archived AND still-live ones,
 * oldest week first — the year review's „Eure Highlights des Jahres" chapter.
 */
export function weekHighlightsForYear(couple, year) {
  const review = weekReviewOf(couple);
  const prefix = `${year}-W`;
  const entries = (review.highlightArchive ?? []).filter((entry) => entry.week.startsWith(prefix));
  const archivedWeeks = new Set(entries.map((entry) => entry.week));
  for (const [week, byMember] of Object.entries(review.highlights)) {
    if (!week.startsWith(prefix) || archivedWeeks.has(week)) continue;
    for (const [memberId, highlight] of Object.entries(byMember)) {
      if (highlight?.text) entries.push({ week, memberId, text: highlight.text });
    }
  }
  entries.sort((a, b) => (a.week < b.week ? -1 : a.week > b.week ? 1 : 0));
  return entries;
}

// ---------------------------------------------------------------------------
// Sunday-evening arrival push — the ritual needs an arrival moment. Both
// partners get the SAME push at the same instant (couple-local Sunday from
// 19:00), so opening the review becomes a shared ritual instead of two
// separate discoveries. Deduped once per couple and ISO week.

const ARRIVAL_HOUR = 19; // couple-local hour from which the push may fire
const ARRIVAL_PUSH = {
  type: 'weekreview',
  title: { de: 'Eure Woche ist fertig ✨', en: 'Your week is ready ✨' },
  body: {
    de: 'Euer gemeinsamer Wochen-Rückblick wartet — schaut ihn zusammen an.',
    en: 'Your shared week review is waiting — open it together.',
  },
  link: 'sooodreamy://weekreview',
};

/** Weekday/hour/dateKey of `now` on the wall clock of an IANA timezone. */
function localClock(now, timezone) {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat('en-US', {
      timeZone: timezone,
      weekday: 'short',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: 'numeric',
      hourCycle: 'h23',
    })
      .formatToParts(now)
      .map((part) => [part.type, part.value]),
  );
  return {
    dateKey: `${parts.year}-${parts.month}-${parts.day}`,
    weekday: parts.weekday,
    hour: Number.parseInt(parts.hour, 10),
  };
}

/**
 * One sweep over all couples; queues the arrival push where it is due.
 * Timezone-fair: each couple's own `timezone` (IANA, set via PATCH
 * /api/couple) decides when ITS Sunday evening is; without one the server's
 * local clock applies (self-hosters usually run in the couple's home zone).
 * Returns the number of couples for which a push was queued.
 */
export function weekReviewArrivalSweep({ store, push, log = () => {}, now = new Date(), defaultTimezone }) {
  const fallback = defaultTimezone ?? Intl.DateTimeFormat().resolvedOptions().timeZone;
  let queued = 0;
  for (const couple of Object.values(store.data.couples ?? {})) {
    if ((couple.members ?? []).length < 2) continue; // solo: no shared ritual yet
    let clock;
    try {
      clock = localClock(now, couple.timezone ?? fallback);
    } catch {
      clock = localClock(now, 'UTC'); // corrupt stored zone must not kill the sweep
    }
    if (clock.weekday !== 'Sun' || clock.hour < ARRIVAL_HOUR) continue;
    const weekKey = weekKeyOf(clock.dateKey);
    const review = weekReviewOf(couple);
    if (!review.arrivalPush) review.arrivalPush = {};
    if (review.arrivalPush[weekKey]) continue; // already announced this week
    review.arrivalPush[weekKey] = nowIso();
    capWeeks(review.arrivalPush);
    store.markDirty();
    queued += 1;
    void push
      .notifyCouple({ store, couple, ...ARRIVAL_PUSH })
      .catch((error) => log('weekreview: arrival push failed', error?.message ?? error));
  }
  return queued;
}

/** Interval wrapper (5 min default, like the backup scheduler). 0 disables. */
export function startWeekReviewArrivalScheduler({
  store,
  push,
  log = () => {},
  intervalMinutes = 5,
  defaultTimezone,
}) {
  if (!Number.isFinite(intervalMinutes) || intervalMinutes <= 0) return () => {};
  const timer = setInterval(() => {
    try {
      weekReviewArrivalSweep({ store, push, log, defaultTimezone });
    } catch (err) {
      log('weekreview: arrival sweep failed', err);
    }
  }, intervalMinutes * 60_000);
  timer.unref?.();
  return () => clearInterval(timer);
}

// ---------------------------------------------------------------------------
// aggregation (magazine-style: deterministic, capped lists = lower bounds)

function buildWeekReview(couple, weekKey, memberId, h) {
  const days = weekDateKeys(weekKey);
  const daySet = new Set(days);
  const inWeek = (iso) => typeof iso === 'string' && daySet.has(iso.slice(0, 10));
  const today = todayKey();
  const currentWeek = weekKeyOf(today);

  const endedGames = (couple.games ?? []).filter((g) => inWeek(g.createdAt) && g.state === 'ended');
  const daymemos = couple.daymemos ?? {};
  const dailyBoth = days.filter((key) => h.bothAnsweredOn(couple, key));
  const checkinBoth = days.filter((key) => h.bothCheckedInOn(couple, key));
  const perfectDays = days.filter(
    (key) => h.bothAnsweredOn(couple, key) && h.bothCheckedInOn(couple, key));

  const stats = {
    messages: allMessagesOf(couple).filter((m) => inWeek(m.createdAt)).length,
    touches: (couple.touches ?? []).filter((t) => inWeek(t.createdAt)).length,
    hugsSent: (couple.hugs ?? []).filter((hug) => inWeek(hug.createdAt)).length,
    photosAdded: (couple.photos ?? []).filter((p) => inWeek(p.createdAt)).length,
    videosAdded: (couple.videos ?? []).filter((v) => inWeek(v.createdAt)).length,
    gamesPlayed: endedGames.length,
    wordleDays: Object.keys(couple.wordle ?? {}).filter((key) => daySet.has(key)).length,
    dailyBothAnswered: dailyBoth.length,
    checkinDaysBoth: checkinBoth.length,
    daymemoDays: Object.keys(daymemos).filter(
      (key) => daySet.has(key) && Object.keys(daymemos[key]).length > 0).length,
    questsDone: appEventsOf(couple).filter(
      (event) => event.type === 'quest_done' && inWeek(event.createdAt)).length,
    perfectDays: perfectDays.length,
  };

  // Quote of the week — the both-answered daily that reads best out loud
  // (deterministic; both answered ⇒ mutually revealed already). Ranking:
  //   1. complete exchanges (BOTH answers ≥ QUOTE_MIN_ANSWER trimmed chars)
  //      beat incomplete ones — "Ja ❤️" is sweet but not quotable,
  //   2. within a tier, days where neither answer contains a question mark
  //      beat counter-question days ("Was meinst du?" is not an answer),
  //   3. among complete days the SHORTEST combined text wins (a crisp quote
  //      beats an essay); among incomplete days the longest is the least bad.
  // Ties break toward the newer day.
  let quote = null;
  let best = null;
  for (const dateKey of dailyBoth) {
    const rec = couple.daily?.[dateKey];
    if (!rec) continue;
    const answers = {};
    const trimmed = [];
    for (const member of couple.members) {
      const text = rec.answers[member.id]?.text ?? '';
      answers[member.id] = text;
      trimmed.push(text.trim());
    }
    const len = trimmed.reduce((sum, text) => sum + text.length, 0);
    const complete = trimmed.every((text) => text.length >= QUOTE_MIN_ANSWER);
    const clean = trimmed.every((text) => !text.includes('?') && !text.includes('？'));
    const tier = (complete ? 2 : 0) + (clean ? 1 : 0);
    const wins = best === null
      || tier > best.tier
      || (tier === best.tier && (complete ? len < best.len : len > best.len))
      || (tier === best.tier && len === best.len && dateKey > best.dateKey);
    if (wins) {
      best = { tier, len, dateKey };
      quote = {
        dateKey,
        questionId: rec.questionId ?? null,
        customText: rec.customQuestion?.text ?? null,
        answers,
      };
    }
  }

  // Top photo of the week: favorites first, then newest.
  const weekPhotos = (couple.photos ?? []).filter((p) => inWeek(p.createdAt));
  weekPhotos.sort((x, y) => {
    const xFav = (x.favorites ?? []).length > 0 ? 1 : 0;
    const yFav = (y.favorites ?? []).length > 0 ? 1 : 0;
    if (xFav !== yFav) return yFav - xFav;
    return x.createdAt < y.createdAt ? 1 : -1;
  });
  const top = weekPhotos[0] ?? null;

  const review = weekReviewOf(couple);
  const highlights = review.highlights[weekKey] ?? {};
  const mine = highlights[memberId] ?? null;
  const partner = h.partnerOf(couple, memberId);
  const partnerHighlight = partner ? (highlights[partner.id] ?? null) : null;
  const bothShared = couple.members.length >= 2
    && couple.members.every((m) => highlights[m.id] != null);

  return {
    week: weekKey,
    startDateKey: days[0],
    endDateKey: days[6],
    current: weekKey === currentWeek,
    stats,
    quote,
    topPhoto: top
      ? { id: top.id, url: top.url, thumbUrl: top.thumbUrl ?? null, caption: top.caption ?? null }
      : null,
    highlight: {
      mine,
      // Classic reveal: the partner's pick appears only once both shared.
      partner: bothShared ? partnerHighlight : null,
      bothShared,
    },
    seen: review.seen[weekKey] ?? {},
  };
}

// ---------------------------------------------------------------------------
// routes

export function registerWeekReviewRoutes(route, h) {
  const { asString, partnerOf, bothAnsweredOn, bothCheckedInOn, notifyPartner } = h;
  const helpers = { partnerOf, bothAnsweredOn, bothCheckedInOn };

  const assertNotFuture = (weekKey) => {
    const start = weekStartDateKey(weekKey);
    const currentStart = weekStartDateKey(weekKeyOf(todayKey()));
    if (start > currentStart) {
      throw httpError(400, 'bad_week', 'The week review can only look back, not ahead');
    }
    // Bound the lookback so a bogus year-0 key cannot walk the whole store.
    const horizon = new Date(Date.now() - WEEK_LIMITS.lookbackWeeks * 7 * DAY_MS)
      .toISOString().slice(0, 10);
    if (start < horizon) {
      throw httpError(400, 'bad_week', `"week" may look back at most ${WEEK_LIMITS.lookbackWeeks} weeks`);
    }
  };

  route('GET', '/api/week-review', { auth: true }, (c) => {
    const requested = c.url.searchParams.get('week');
    const weekKey = requested ?? weekKeyOf(todayKey());
    assertNotFuture(weekKey);
    sendJson(c.res, 200, buildWeekReview(c.auth.couple, weekKey, c.auth.memberId, helpers));
  });

  route('PUT', '/api/week-review/:week/highlight', { auth: true }, async (c) => {
    const weekKey = c.params.week;
    assertNotFuture(weekKey);
    // The highlight ritual is fresh by design: this week, or last week
    // (Sunday-evening ritual often spills into Monday).
    const current = weekKeyOf(todayKey());
    if (weekKey !== current && weekKey !== previousWeekKey(current)) {
      throw httpError(409, 'week_closed', 'Highlights can only be shared for the current or previous week');
    }
    const body = await readJsonObject(c.req);
    const text = asString(body.text, 'text', { max: WEEK_LIMITS.highlightText });
    let photoId = null;
    if (body.photoId != null) {
      photoId = asString(body.photoId, 'photoId', { max: 64 });
      if (!(c.auth.couple.photos ?? []).some((p) => p.id === photoId)) {
        throw httpError(404, 'photo_not_found', 'Unknown photoId');
      }
    }
    const couple = c.auth.couple;
    const review = weekReviewOf(couple);
    if (!review.highlights[weekKey]) review.highlights[weekKey] = {};
    review.highlights[weekKey][c.auth.memberId] = { text, photoId, setAt: nowIso() };
    capHighlightsWithArchive(review); // evicted weeks land in highlightArchive
    c.store.markDirty();
    // Per-member views (anti-spoiler): each side only ever gets its own
    // allowed slice, exactly like the daily-question reveal.
    for (const member of couple.members) {
      c.realtime.sendToMember(couple.id, member.id, 'week_highlight',
        buildWeekReview(couple, weekKey, member.id, helpers));
    }
    const bothShared = couple.members.length >= 2
      && couple.members.every((m) => review.highlights[weekKey][m.id] != null);
    if (bothShared) {
      emitAppEvent({
        store: c.store, realtime: c.realtime, couple,
        type: 'week_highlight_both', data: { week: weekKey }, dedupeKey: weekKey,
      });
    } else {
      notifyPartner(c, {
        type: 'daily',
        title: { de: 'Eure Woche', en: 'Your week' },
        body: {
          de: `${c.auth.member.name} hat ein Wochen-Highlight geteilt.`,
          en: `${c.auth.member.name} shared a weekly highlight.`,
        },
        link: 'sooodreamy://tab/home',
      });
    }
    sendJson(c.res, 200, buildWeekReview(couple, weekKey, c.auth.memberId, helpers));
  });

  route('POST', '/api/week-review/:week/seen', { auth: true }, (c) => {
    const weekKey = c.params.week;
    assertNotFuture(weekKey);
    if (weekKey === weekKeyOf(todayKey())) {
      throw httpError(409, 'week_not_over', 'A week can be marked read once it is over');
    }
    const couple = c.auth.couple;
    const review = weekReviewOf(couple);
    if (!review.seen[weekKey]) review.seen[weekKey] = {};
    if (!review.seen[weekKey][c.auth.memberId]) {
      review.seen[weekKey][c.auth.memberId] = nowIso();
      capWeeks(review.seen);
      c.store.markDirty();
      c.realtime.broadcastCouple(couple.id, 'week_review_seen', {
        week: weekKey,
        seen: review.seen[weekKey],
      });
      const bothSeen = couple.members.length >= 2
        && couple.members.every((m) => review.seen[weekKey][m.id] != null);
      if (bothSeen) {
        emitAppEvent({
          store: c.store, realtime: c.realtime, couple,
          type: 'week_review_both', data: { week: weekKey }, dedupeKey: weekKey,
        });
      }
    }
    sendJson(c.res, 200, { week: weekKey, seen: review.seen[weekKey] });
  });
}
