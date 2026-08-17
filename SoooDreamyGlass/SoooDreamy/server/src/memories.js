import { httpError, isValidDateKey, sendJson, todayKey, daysBetween } from './util.js';
import { allMessagesOf } from './message-archive.js';

/**
 * „Erinnerungen" (v8.0) — read-only memory aggregations.
 *
 *   GET /api/on-this-day?date=YYYY-MM-DD   deterministic "on this day n months/years ago"
 *   GET /api/story                          „Unsere Geschichte" milestone timeline
 *
 * Both routes only READ the store (no markDirty, no WS events): the same
 * couple state always produces the same memories on both phones.
 *
 * Honesty notes (also in docs/API.md):
 * - "On this day" matches the exact day-of-month. Months without that day
 *   (e.g. Feb 31) simply have no month-memory — no fuzzy "closest day" magic.
 * - Message history is archival and retains literal first messages. Touches
 *   (500) and games (1000) remain capped lower-bound sources.
 */

const MEMORY_LIMITS = {
  onThisDayItems: 20,
  storyEntries: 300,
  teaser: 80,
};

// ---------------------------------------------------------------------------
// pure month math (mirrored bit-for-bit by ios Content/MemoriesLogic.swift)

/**
 * Whole months from `pastKey` to `todayKey` when both share the SAME
 * day-of-month, else null. Returns n >= 1 only for genuinely past dates.
 */
export function monthsBackSameDay(pastKey, nowKey) {
  const py = Number(pastKey.slice(0, 4));
  const pm = Number(pastKey.slice(5, 7));
  const pd = Number(pastKey.slice(8, 10));
  const ny = Number(nowKey.slice(0, 4));
  const nm = Number(nowKey.slice(5, 7));
  const nd = Number(nowKey.slice(8, 10));
  if (pd !== nd) return null;
  const months = (ny * 12 + nm) - (py * 12 + pm);
  return months >= 1 ? months : null;
}

/** `{unit: 'months'|'years', n}` — whole years collapse (24 → 2 years). */
export function distanceFromMonths(months) {
  return months % 12 === 0
    ? { unit: 'years', n: months / 12 }
    : { unit: 'months', n: months };
}

const dateKeyOf = (iso) => (typeof iso === 'string' ? iso.slice(0, 10) : null);

// ---------------------------------------------------------------------------
// on this day

function buildOnThisDay(couple, nowKey) {
  const items = [];

  for (const photo of couple.photos ?? []) {
    const key = dateKeyOf(photo.createdAt);
    const months = key ? monthsBackSameDay(key, nowKey) : null;
    if (months == null) continue;
    items.push({
      kind: 'photo',
      dateKey: key,
      distance: distanceFromMonths(months),
      photo: {
        id: photo.id,
        url: photo.url,
        thumbUrl: photo.thumbUrl ?? null,
        caption: photo.caption ?? null,
        favorites: photo.favorites ?? [],
      },
    });
  }

  for (const [dateKey, rec] of Object.entries(couple.daily ?? {})) {
    const months = monthsBackSameDay(dateKey, nowKey);
    if (months == null) continue;
    // Only mutually revealed dailies can be relived together.
    const answered = couple.members.filter((m) => rec.answers?.[m.id]?.text != null);
    if (couple.members.length < 2 || answered.length !== couple.members.length) continue;
    const answers = {};
    for (const member of couple.members) answers[member.id] = rec.answers[member.id].text;
    items.push({
      kind: 'daily',
      dateKey,
      distance: distanceFromMonths(months),
      questionId: rec.questionId ?? null,
      customText: rec.customQuestion?.text ?? null,
      answers,
    });
  }

  // Closest memories first; photos before dailies on the same day; then the
  // photo id as a stable tie-breaker so both phones agree on the order.
  items.sort((x, y) => {
    const xm = x.distance.unit === 'years' ? x.distance.n * 12 : x.distance.n;
    const ym = y.distance.unit === 'years' ? y.distance.n * 12 : y.distance.n;
    if (xm !== ym) return xm - ym;
    if (x.kind !== y.kind) return x.kind === 'photo' ? -1 : 1;
    return (x.photo?.id ?? x.dateKey) < (y.photo?.id ?? y.dateKey) ? -1 : 1;
  });

  const sinceKey = couple.anniversary ?? couple.createdAt.slice(0, 10);
  const anniversaryMonths = couple.anniversary
    ? monthsBackSameDay(couple.anniversary, nowKey)
    : null;

  return {
    dateKey: nowKey,
    daysTogether: daysBetween(sinceKey),
    // Whole-month "monthiversary" of the couple's own start date (if set).
    monthiversary: anniversaryMonths != null ? distanceFromMonths(anniversaryMonths) : null,
    items: items.slice(0, MEMORY_LIMITS.onThisDayItems),
  };
}

// ---------------------------------------------------------------------------
// story timeline

const teaserOf = (text) => {
  if (typeof text !== 'string') return null;
  const trimmed = text.trim();
  if (trimmed.length === 0) return null;
  return trimmed.length > MEMORY_LIMITS.teaser
    ? `${trimmed.slice(0, MEMORY_LIMITS.teaser - 1)}…`
    : trimmed;
};

function firstOf(list, predicate = () => true) {
  for (const item of list ?? []) if (predicate(item)) return item;
  return null;
}

function buildStory(couple) {
  const entries = [];
  const push = (kind, dateKey, data = {}) => {
    if (typeof dateKey === 'string' && dateKey.length === 10) {
      entries.push({ id: `${kind}:${dateKey}`, kind, dateKey, ...data });
    }
  };

  push('paired', couple.createdAt.slice(0, 10));
  if (couple.anniversary) push('begin', couple.anniversary);

  // Firsts — archive chunks and the hot set are both chronological.
  const messages = allMessagesOf(couple);
  const firstMessage = firstOf(messages);
  if (firstMessage) {
    push('first_message', dateKeyOf(firstMessage.createdAt), {
      teaser: firstMessage.type === 'text' ? teaserOf(firstMessage.text) : null,
    });
  }
  const firstPhoto = firstOf(couple.photos);
  if (firstPhoto) {
    push('first_photo', dateKeyOf(firstPhoto.createdAt), {
      photo: {
        id: firstPhoto.id,
        url: firstPhoto.url,
        thumbUrl: firstPhoto.thumbUrl ?? null,
        caption: firstPhoto.caption ?? null,
      },
    });
  }
  const firstVideo = firstOf(couple.videos);
  if (firstVideo) push('first_video', dateKeyOf(firstVideo.createdAt));
  const firstGame = firstOf(couple.games, (g) => g.state === 'ended');
  if (firstGame) push('first_game', dateKeyOf(firstGame.createdAt), { gameType: firstGame.type });

  const bothAnsweredDays = Object.entries(couple.daily ?? {})
    .filter(([, rec]) => couple.members.length >= 2
      && couple.members.every((m) => rec.answers?.[m.id]?.text != null))
    .map(([dateKey, rec]) => ({ dateKey, rec }))
    .sort((x, y) => (x.dateKey < y.dateKey ? -1 : 1));
  if (bothAnsweredDays.length > 0) {
    const { dateKey, rec } = bothAnsweredDays[0];
    push('first_daily', dateKey, {
      questionId: rec.questionId ?? null,
      customText: rec.customQuestion?.text ?? null,
    });
  }

  const bothMemoDays = Object.entries(couple.daymemos ?? {})
    .filter(([, day]) => couple.members.length >= 2
      && couple.members.every((m) => day[m.id] != null))
    .map(([dateKey]) => dateKey)
    .sort();
  if (bothMemoDays.length > 0) push('first_daymemo', bothMemoDays[0]);

  const firstCapsule = firstOf(
    [...(couple.capsules ?? [])].sort((x, y) => ((x.openedAt ?? '') < (y.openedAt ?? '') ? -1 : 1)),
    (cap) => cap.openedAt != null,
  );
  if (firstCapsule) push('first_capsule', dateKeyOf(firstCapsule.openedAt));

  const firstHug = firstOf(
    [...(couple.hugs ?? [])].sort((x, y) => ((x.openedAt ?? '') < (y.openedAt ?? '') ? -1 : 1)),
    (hug) => hug.openedAt != null,
  );
  if (firstHug) push('first_hug', dateKeyOf(firstHug.openedAt));

  const firstGoal = firstOf(
    [...(couple.goals ?? [])].sort((x, y) => ((x.completedAt ?? '') < (y.completedAt ?? '') ? -1 : 1)),
    (goal) => goal.completedAt != null,
  );
  if (firstGoal) {
    push('first_goal', dateKeyOf(firstGoal.completedAt),
      { title: firstGoal.title, emoji: firstGoal.emoji ?? null });
  }

  // Count milestones from retained data.
  for (const n of [10, 25, 50, 100, 250, 500, 1000]) {
    const photo = (couple.photos ?? [])[n - 1];
    if (photo) push('photos_milestone', dateKeyOf(photo.createdAt), { n });
  }
  // Explicit deletions keep the lifetime counter ahead of retained history;
  // only derive exact ordinal milestones while every sent message is present.
  if ((couple.counters?.messages ?? 0) === messages.length) {
    for (const n of [100, 500, 1000, 2500, 5000]) {
      const message = messages[n - 1];
      if (message) push('messages_milestone', dateKeyOf(message.createdAt), { n });
    }
  }
  for (const n of [10, 50, 100, 250, 500]) {
    const day = bothAnsweredDays[n - 1];
    if (day) push('daily_milestone', day.dateKey, { n });
  }

  // Unlocked badges (persisted with their unlock time in gamification state).
  for (const [badgeId, unlockedAt] of Object.entries(couple.gamification?.badges ?? {})) {
    push('badge', dateKeyOf(unlockedAt), { badgeId });
  }

  const rank = (kind) => (kind === 'begin' ? 0 : kind === 'paired' ? 1 : 2);
  entries.sort((x, y) => {
    if (x.dateKey !== y.dateKey) return x.dateKey < y.dateKey ? -1 : 1;
    if (rank(x.kind) !== rank(y.kind)) return rank(x.kind) - rank(y.kind);
    return x.id < y.id ? -1 : 1;
  });

  const sinceKey = couple.anniversary ?? couple.createdAt.slice(0, 10);
  return {
    sinceKey,
    daysTogether: daysBetween(sinceKey),
    entries: entries.slice(0, MEMORY_LIMITS.storyEntries),
  };
}

// ---------------------------------------------------------------------------
// routes

export function registerMemoryRoutes(route) {
  route('GET', '/api/on-this-day', { auth: true }, (c) => {
    const requested = c.url.searchParams.get('date');
    const nowKey = todayKey();
    let dateKey = nowKey;
    if (requested != null) {
      if (!isValidDateKey(requested)) {
        throw httpError(400, 'bad_date', '"date" must be YYYY-MM-DD');
      }
      if (requested > nowKey) {
        throw httpError(400, 'bad_date', 'Memories only look back, not ahead');
      }
      dateKey = requested;
    }
    sendJson(c.res, 200, buildOnThisDay(c.auth.couple, dateKey));
  });

  route('GET', '/api/story', { auth: true }, (c) => {
    sendJson(c.res, 200, buildStory(c.auth.couple));
  });
}
