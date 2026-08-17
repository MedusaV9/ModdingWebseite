import { sendJson, nowIso, prevDateKey } from './util.js';
import { appEventsOf } from './events.js';

/**
 * Beziehungs-Level & Abzeichen (v3.0, Agent C) — the gamification layer.
 *
 * DESIGN
 * ──────
 * XP is aggregated DETERMINISTICALLY from data the server already stores
 * (yearreview pattern) — retroactively fair for existing couples: the day
 * 3.0 ships, every couple already has the level their history earned.
 * Everything rewards SHARED activity (both-partner bonuses); XP is never
 * lost (lifetime counters where available, capped lists otherwise — the
 * honest limits are documented in docs/API.md).
 *
 * The v3.0 app-event log (src/events.js, emitted by the rituals/games
 * features) is consumed INCREMENTALLY: its ring buffer only keeps the last
 * 500 events, so XP earned from app events is persisted in
 * `couple.gamification.eventXp` and a cursor remembers what was counted.
 *
 * LEVEL CURVE
 * ───────────
 * Threshold for level n (1-based): T(n) = 100 · (n−1) · n / 2  — triangular
 * numbers × 100. L1=0, L2=100, L3=300, L4=600, L5=1000, L6=1500, L7=2100,
 * L8=2800, L9=3600, L10=4500, then +100·n per further level (unbounded).
 * Titles never clamp: past level 10 the ten stems replay as prestige
 * chapters — "Frisch verliebt · Kapitel II" at 11, and so on.
 *
 * LIVE EVENTS
 * ───────────
 * After every successful authenticated write request the router calls
 * `maybeAdvanceGamification`. It compares the freshly computed level/badges
 * with the persisted snapshot and broadcasts `level_up { level, xp, … }`
 * and `badge_unlocked { badge }`. The FIRST computation for a couple
 * adopts the retroactive state silently (no ceremony spam for old couples).
 */

// ---------------------------------------------------------------------------
// XP table (documented in docs/API.md — keep both in sync)

const XP = {
  perMessage: 2, // lifetime counter
  perTouch: 1, // lifetime counters (both members)
  perGamePlayed: 15, // lifetime counter
  perPhoto: 10,
  perVideo: 10,
  perDailyDayAny: 5, // ≥1 member answered that day
  perDailyDayBoth: 25, // BOTH answered (together bonus)
  perCheckinDayBoth: 15,
  perWordleDay: 8, // ≥1 result that day
  perWordleDayBoth: 12, // both finished (any shared language) — bonus
  perPotdDayAny: 5,
  perPotdDayBoth: 10, // bonus
  perHugOpened: 8,
  perCouponRedeemed: 12,
  perBucketDone: 15,
  perSong: 3,
  perEventCreated: 5,
  perHapticPattern: 5,
  perHapticSend: 1,
  perCanvasChunk: 5, // per 25 strokes
  questBonus: 150, // onboarding quest finale
};

/**
 * XP per consumed app event (src/events.js); unknown types get the default.
 * v3.0.1: every emitted type has an EXPLICIT, reviewable value (documented in
 * docs/API.md) — the generic default only covers future additions.
 */
const APP_EVENT_XP = {
  daymemo_first: 10,
  daymemo_both: 20,
  capsule_sealed: 10,
  capsule_opened: 15,
  need_sent: 3,
  goal_created: 10,
  goal_milestone: 10,
  goal_reached: 40,
  weekplan_slot_created: 5,
  magazine_seen_both: 15,
  movie_match: 15, // both swiped right (server-verified, once per card)
  quest_done: 10, // first check per (day, quest) — duplicates never re-emit
  icon_gift_sent: 10,
  datenight_planned: 10,
  // v5.0 „Worte & Wärme" — small, shared-moment weighted (both > solo)
  goodthings_both: 20, // once per evening both shared their 3 good things
  thanks_sent: 3, // capped by intent, not by farming: sparks are tiny
  missyou_sent: 3,
  dictionary_confirmed: 15, // only fires when the PARTNER co-signs
  first_logged: 10, // deduped per first — edits never re-emit
  season_calendar_created: 5,
  season_calendar_door_opened: 8,
  // v7.0 weekly review — shared-moment weighted, once per week each
  week_highlight_both: 20,
  week_review_both: 15,
  default: 5,
};

export const LEVEL_TITLES = [
  { de: 'Frisch verliebt', en: 'Freshly in love' },
  { de: 'Turteltauben', en: 'Lovebirds' },
  { de: 'Händchenhalter', en: 'Hand-holders' },
  { de: 'Träumer-Duo', en: 'Dreamy duo' },
  { de: 'Eingespieltes Team', en: 'In perfect sync' },
  { de: 'Herzensbande', en: 'Heart-bonded' },
  { de: 'Sternenpaar', en: 'Starlit pair' },
  { de: 'Unzertrennlich', en: 'Inseparable' },
  { de: 'Seelenverwandte', en: 'Soulmates' },
  { de: 'Legendäres Duo', en: 'Legendary duo' },
];

/** Cumulative XP needed to REACH level n (1-based). */
export function xpForLevel(level) {
  const n = Math.max(1, Math.floor(level));
  return (100 * (n - 1) * n) / 2;
}

/** 1-based level for a total XP amount (unbounded). */
export function levelForXP(xp) {
  let level = 1;
  while (xpForLevel(level + 1) <= xp) level += 1;
  return level;
}

/** Roman numeral for prestige chapters ("II", "III", …) — the iOS client
 *  mirrors this in Core/LevelMath.swift; keep both sides identical. */
export function romanNumeral(chapter) {
  const values = [
    [1000, 'M'], [900, 'CM'], [500, 'D'], [400, 'CD'],
    [100, 'C'], [90, 'XC'], [50, 'L'], [40, 'XL'],
    [10, 'X'], [9, 'IX'], [5, 'V'], [4, 'IV'], [1, 'I'],
  ];
  let rest = Math.max(1, Math.floor(chapter));
  let out = '';
  for (const [value, symbol] of values) {
    while (rest >= value) {
      out += symbol;
      rest -= value;
    }
  }
  return out;
}

/** 1-based prestige chapter: levels 1–10 are chapter I, 11–20 II, … */
export function chapterForLevel(level) {
  const n = Math.max(1, Math.floor(level));
  return Math.floor((n - 1) / LEVEL_TITLES.length) + 1;
}

/**
 * Prestige chapters: instead of clamping at "Legendäres Duo" forever, the
 * ten title stems replay per chapter — level 11 is "Frisch verliebt ·
 * Kapitel II", level 20 "Legendäres Duo · Kapitel II", and so on without
 * end. Chapter I keeps the plain stems (nothing changes below level 11).
 */
export function titleForLevel(level) {
  const n = Math.max(1, Math.floor(level));
  const stem = LEVEL_TITLES[(n - 1) % LEVEL_TITLES.length];
  const chapter = chapterForLevel(n);
  if (chapter <= 1) return stem;
  const numeral = romanNumeral(chapter);
  return { de: `${stem.de} · Kapitel ${numeral}`, en: `${stem.en} · Chapter ${numeral}` };
}

// ---------------------------------------------------------------------------
// read-only store accessors (mirror router.js semantics, but never mutate)

const listOf = (couple, key) => couple[key] ?? [];
const mapOf = (couple, key) => couple[key] ?? {};

function bothDidOn(couple, record, extract) {
  if (!record || couple.members.length < 2) return false;
  return couple.members.every((m) => extract(record, m.id));
}

function bothAnsweredOn(couple, dateKey) {
  return bothDidOn(couple, mapOf(couple, 'daily')[dateKey], (rec, mid) => rec.answers?.[mid]?.text != null);
}

function bothCheckedInOn(couple, dateKey) {
  return bothDidOn(
    couple,
    mapOf(couple, 'checkins')[dateKey],
    (rec, mid) => rec.morning?.[mid] != null || rec.night?.[mid] != null,
  );
}

/** Consecutive both-days ending today or yesterday (same walk as router.js). */
function streakOf(couple, bothOn, now = new Date()) {
  const today = now.toISOString().slice(0, 10);
  let cursor = null;
  if (bothOn(couple, today)) cursor = today;
  else if (bothOn(couple, prevDateKey(today))) cursor = prevDateKey(today);
  if (!cursor) return 0;
  let streak = 0;
  while (bothOn(couple, cursor)) {
    streak += 1;
    cursor = prevDateKey(cursor);
  }
  return streak;
}

function gamificationOf(couple) {
  if (!couple.gamification) {
    couple.gamification = { level: null, badges: {}, eventXp: 0, eventCursor: null, questCompletedAt: null };
  }
  if (!couple.gamification.badges) couple.gamification.badges = {};
  return couple.gamification;
}

// ---------------------------------------------------------------------------
// XP aggregation

/**
 * Consumes NEW app events (src/events.js ring buffer) into the persisted
 * XP accumulator. Idempotent per event via a {id, at} cursor; when the
 * cursor's event rolled off the buffer, `createdAt` decides what is new.
 */
function consumeAppEvents(couple, store) {
  const state = gamificationOf(couple);
  const events = appEventsOf(couple);
  if (events.length === 0) return state.eventXp;
  let startIdx = 0;
  if (state.eventCursor) {
    const at = events.findIndex((ev) => ev.id === state.eventCursor.id);
    if (at !== -1) startIdx = at + 1;
    else startIdx = events.findIndex((ev) => ev.createdAt > state.eventCursor.at);
    if (startIdx === -1) startIdx = events.length;
  }
  let gained = 0;
  for (let i = startIdx; i < events.length; i++) {
    gained += APP_EVENT_XP[events[i].type] ?? APP_EVENT_XP.default;
  }
  if (gained > 0 || !state.eventCursor) {
    state.eventXp = (state.eventXp ?? 0) + gained;
    const last = events[events.length - 1];
    state.eventCursor = { id: last.id, at: last.createdAt };
    if (store) store.markDirty();
  }
  return state.eventXp ?? 0;
}

/** Full deterministic XP breakdown for a couple. */
export function computeXP(couple, { store = null, now = new Date() } = {}) {
  const counters = couple.counters ?? { messages: 0, gamesPlayed: 0, touches: {} };
  const touchesTotal = Object.values(counters.touches ?? {}).reduce((sum, t) => sum + (t.total ?? 0), 0);

  const daily = mapOf(couple, 'daily');
  const dailyDays = Object.keys(daily).filter((key) =>
    Object.values(daily[key]?.answers ?? {}).some((a) => a?.text != null),
  );
  const dailyBothDays = dailyDays.filter((key) => bothAnsweredOn(couple, key));

  const checkins = mapOf(couple, 'checkins');
  const checkinBothDays = Object.keys(checkins).filter((key) => bothCheckedInOn(couple, key));

  const wordle = mapOf(couple, 'wordle');
  const wordleDays = Object.keys(wordle);
  const wordleBothDays = wordleDays.filter((key) => {
    const day = wordle[key] ?? {};
    // v1.2.1 shape: {lang: {memberId: result}} — both finished any shared language.
    return Object.values(day).some(
      (byMember) => byMember && typeof byMember === 'object' && couple.members.every((m) => byMember[m.id]),
    );
  });

  const potd = mapOf(couple, 'potd');
  const potdDays = Object.keys(potd).filter((key) => Object.keys(potd[key] ?? {}).length > 0);
  const potdBothDays = potdDays.filter((key) => couple.members.every((m) => potd[key]?.[m.id]));

  const haptics = couple.haptics ?? {};

  const breakdown = {
    messages: (counters.messages ?? 0) * XP.perMessage,
    touches: touchesTotal * XP.perTouch,
    games: (counters.gamesPlayed ?? 0) * XP.perGamePlayed,
    photos: listOf(couple, 'photos').length * XP.perPhoto,
    videos: listOf(couple, 'videos').length * XP.perVideo,
    daily: dailyDays.length * XP.perDailyDayAny + dailyBothDays.length * XP.perDailyDayBoth,
    checkins: checkinBothDays.length * XP.perCheckinDayBoth,
    wordle: wordleDays.length * XP.perWordleDay + wordleBothDays.length * XP.perWordleDayBoth,
    potd: potdDays.length * XP.perPotdDayAny + potdBothDays.length * XP.perPotdDayBoth,
    hugs: listOf(couple, 'hugs').filter((h) => h.openedAt).length * XP.perHugOpened,
    coupons: listOf(couple, 'coupons').filter((cp) => cp.redeemedAt).length * XP.perCouponRedeemed,
    bucket: listOf(couple, 'bucket').filter((b) => b.done).length * XP.perBucketDone,
    songs: listOf(couple, 'songs').length * XP.perSong,
    events: listOf(couple, 'events').length * XP.perEventCreated,
    haptics:
      (haptics.patterns?.length ?? 0) * XP.perHapticPattern + (haptics.sends?.length ?? 0) * XP.perHapticSend,
    canvas: Math.floor(listOf(couple, 'strokes').length / 25) * XP.perCanvasChunk,
    appEvents: consumeAppEvents(couple, store),
    quest: gamificationOf(couple).questCompletedAt ? XP.questBonus : 0,
  };
  void now;
  const xp = Object.values(breakdown).reduce((sum, v) => sum + v, 0);
  return { xp, breakdown };
}

/** Full level state (used by GET /api/level and the widget snapshot). */
export function levelState(couple, { store = null, now = new Date() } = {}) {
  const { xp, breakdown } = computeXP(couple, { store, now });
  const level = levelForXP(xp);
  const current = xpForLevel(level);
  const next = xpForLevel(level + 1);
  return {
    xp,
    level,
    title: titleForLevel(level),
    levelXp: xp - current,
    nextLevelXp: next - current,
    progress: Math.min(1, (xp - current) / (next - current)),
    maxTitleLevel: LEVEL_TITLES.length,
    breakdown,
  };
}

/** Compact level view for the widget snapshot (level ring on the homescreen). */
export function levelSnapshot(couple, { store = null } = {}) {
  const state = levelState(couple, { store });
  return { level: state.level, title: state.title, progress: state.progress, xp: state.xp };
}

// ---------------------------------------------------------------------------
// badges

/**
 * Badge catalog: id + deterministic unlock condition (+ progress for the
 * shelf UI). `secret` badges are only revealed once unlocked (the client
 * shows "???" otherwise). Names/emoji/artwork live client-side (L10n).
 */
const BADGES = [
  { id: 'first_touch', secret: false, target: 1, value: (agg) => agg.touchesTotal },
  { id: 'touches_500', secret: false, target: 500, value: (agg) => agg.touchesTotal },
  { id: 'hundred_kisses', secret: false, target: 100, value: (agg) => agg.kisses },
  { id: 'hug_marathon', secret: false, target: 25, value: (agg) => agg.hugsOpened },
  { id: 'streak_week', secret: false, target: 7, value: (agg) => agg.dailyStreak },
  { id: 'streak_month', secret: false, target: 30, value: (agg) => agg.dailyStreak },
  // Long-arc streaks — the reward economy has to carry MONTHS, not weeks.
  { id: 'streak_quarter', secret: false, target: 90, value: (agg) => agg.dailyStreak },
  { id: 'streak_half_year', secret: false, target: 180, value: (agg) => agg.dailyStreak },
  { id: 'streak_year', secret: false, target: 365, value: (agg) => agg.dailyStreak },
  { id: 'checkin_month', secret: false, target: 30, value: (agg) => agg.checkinBothDays },
  { id: 'wordle_ten', secret: false, target: 10, value: (agg) => agg.wordleDays },
  { id: 'gamer_25', secret: false, target: 25, value: (agg) => agg.gamesPlayed },
  { id: 'photographers', secret: false, target: 50, value: (agg) => agg.mediaCount },
  { id: 'picasso', secret: false, target: 500, value: (agg) => agg.strokes },
  { id: 'bucket_10', secret: false, target: 10, value: (agg) => agg.bucketDone },
  { id: 'songbirds', secret: false, target: 25, value: (agg) => agg.songs },
  { id: 'level_5', secret: false, target: 5, value: (agg) => agg.level },
  { id: 'level_10', secret: false, target: 10, value: (agg) => agg.level },
  { id: 'night_owls', secret: true, target: 10, value: (agg) => agg.nightMessages },
  { id: 'early_birds', secret: true, target: 10, value: (agg) => agg.earlyCheckins },
  { id: 'icon_gifted', secret: true, target: 1, value: (agg) => agg.iconGiftsSent },
  { id: 'duet_partners', secret: true, target: 1, value: (agg) => agg.duetsPlayed },
  { id: 'quest_complete', secret: false, target: 1, value: (agg) => (agg.questDone ? 1 : 0) },
];

/** One pass over the store for everything the badge conditions need. */
function badgeAggregates(couple, now = new Date()) {
  const counters = couple.counters ?? { messages: 0, gamesPlayed: 0, touches: {} };
  const touchCounters = Object.values(counters.touches ?? {});
  const state = gamificationOf(couple);
  const checkins = mapOf(couple, 'checkins');
  // "Night owls": chat messages between midnight and 05:00 (server time,
  // documented honestly — the server has no idea of client timezones).
  const hourOf = (iso) => Number(iso.slice(11, 13));
  const nightMessages = listOf(couple, 'messages').filter((m) => hourOf(m.createdAt) < 5).length;
  let earlyCheckins = 0;
  for (const day of Object.values(checkins)) {
    for (const at of Object.values(day.morning ?? {})) {
      if (hourOf(at) < 7) earlyCheckins += 1;
    }
  }
  return {
    touchesTotal: touchCounters.reduce((sum, t) => sum + (t.total ?? 0), 0),
    kisses: touchCounters.reduce((sum, t) => sum + (t.byType?.kiss ?? 0), 0),
    hugsOpened: listOf(couple, 'hugs').filter((h) => h.openedAt).length,
    dailyStreak: streakOf(couple, bothAnsweredOn, now),
    checkinBothDays: Object.keys(checkins).filter((key) => bothCheckedInOn(couple, key)).length,
    wordleDays: Object.keys(mapOf(couple, 'wordle')).length,
    gamesPlayed: counters.gamesPlayed ?? 0,
    mediaCount: listOf(couple, 'photos').length + listOf(couple, 'videos').length,
    strokes: listOf(couple, 'strokes').length,
    bucketDone: listOf(couple, 'bucket').filter((b) => b.done).length,
    songs: listOf(couple, 'songs').length,
    level: levelForXP(computeXP(couple).xp),
    nightMessages,
    earlyCheckins,
    iconGiftsSent: couple.iconGiftsSent ?? 0, // lifetime counter (platform.js)
    duetsPlayed: couple.duetsPlayed ?? 0,
    questDone: Boolean(state.questCompletedAt),
  };
}

/**
 * Badge states. Unlocks are PERSISTED (couple.gamification.badges[id] =
 * unlockedAt) so a badge never re-locks when the underlying value later
 * drops (streak broken, photos deleted, …).
 */
export function computeBadges(couple, { store = null, now = new Date() } = {}) {
  const state = gamificationOf(couple);
  const agg = badgeAggregates(couple, now);
  let changed = false;
  const badges = BADGES.map((spec) => {
    const value = Math.max(0, Math.floor(spec.value(agg)));
    let unlockedAt = state.badges[spec.id] ?? null;
    if (!unlockedAt && value >= spec.target) {
      unlockedAt = nowIso();
      state.badges[spec.id] = unlockedAt;
      changed = true;
    }
    return {
      id: spec.id,
      secret: spec.secret,
      unlocked: Boolean(unlockedAt),
      unlockedAt,
      progress: { current: Math.min(value, spec.target), target: spec.target },
    };
  });
  if (changed && store) store.markDirty();
  return badges;
}

// ---------------------------------------------------------------------------
// quest (onboarding "first week")

const QUEST_MAX_AGE_DAYS = 30;

/** The 7 guided first-week steps, all derived from existing server data. */
export function questSteps(couple) {
  const counters = couple.counters ?? { messages: 0, gamesPlayed: 0, touches: {} };
  const touchesTotal = Object.values(counters.touches ?? {}).reduce((sum, t) => sum + (t.total ?? 0), 0);
  const daily = mapOf(couple, 'daily');
  const checkins = mapOf(couple, 'checkins');
  return [
    { id: 'touch', done: touchesTotal > 0 },
    { id: 'message', done: (counters.messages ?? 0) > 0 },
    { id: 'daily', done: Object.keys(daily).some((key) => bothAnsweredOn(couple, key)) },
    { id: 'photo', done: listOf(couple, 'photos').length > 0 },
    { id: 'canvas', done: listOf(couple, 'strokes').length > 0 },
    { id: 'checkin', done: Object.keys(checkins).some((key) => bothCheckedInOn(couple, key)) },
    {
      id: 'game',
      done: (counters.gamesPlayed ?? 0) > 0 || Object.keys(mapOf(couple, 'wordle')).length > 0,
    },
  ];
}

/** Quest state; completing it persists `questCompletedAt` (+150 XP bonus). */
export function questState(couple, { store = null, now = new Date() } = {}) {
  const state = gamificationOf(couple);
  const steps = questSteps(couple);
  const done = steps.every((s) => s.done);
  if (done && !state.questCompletedAt) {
    state.questCompletedAt = nowIso();
    if (store) store.markDirty();
  }
  const ageDays = (now.getTime() - Date.parse(couple.createdAt)) / 86_400_000;
  return {
    steps,
    done: Boolean(state.questCompletedAt),
    completedAt: state.questCompletedAt,
    isNewCouple: Number.isFinite(ageDays) ? ageDays <= QUEST_MAX_AGE_DAYS : false,
    bonusXp: XP.questBonus,
  };
}

// ---------------------------------------------------------------------------
// live progress check (called by the router after successful writes)

const LEGACY_AGE_DAYS = 7;

/**
 * Recomputes level + badges and broadcasts `level_up` / `badge_unlocked`
 * for every advancement since the persisted snapshot. The very first
 * computation for a LEGACY couple (older than 7 days, i.e. upgrading to
 * 3.0 with history) adopts the retroactive state silently — no seven
 * ceremonies at once. Fresh couples celebrate live from action one.
 */
export function maybeAdvanceGamification({ store, realtime, couple, now = new Date() }) {
  const state = gamificationOf(couple);
  const ageDays = (now.getTime() - Date.parse(couple.createdAt)) / 86_400_000;
  const silentBaseline = state.level == null && ageDays > LEGACY_AGE_DAYS;
  const prevLevel = state.level ?? 1;
  const previouslyUnlocked = new Set(Object.keys(state.badges));

  const level = levelState(couple, { store, now });
  const badges = computeBadges(couple, { store, now });

  if (state.level !== level.level) {
    if (!silentBaseline && level.level > prevLevel) {
      realtime.broadcastCouple(couple.id, 'level_up', {
        level: level.level,
        title: level.title,
        xp: level.xp,
      });
    }
    state.level = level.level;
    store.markDirty();
  }
  if (!silentBaseline) {
    for (const badge of badges) {
      if (badge.unlocked && !previouslyUnlocked.has(badge.id)) {
        realtime.broadcastCouple(couple.id, 'badge_unlocked', { badge });
      }
    }
  }
}

// ---------------------------------------------------------------------------
// routes

/** Registers the gamification endpoints on the router's route table. */
export function registerGamificationRoutes(route) {
  // Level state: XP, level, title (DE/EN), ring progress + breakdown.
  route('GET', '/api/level', { auth: true }, (c) => {
    const state = levelState(c.auth.couple, { store: c.store });
    const persisted = gamificationOf(c.auth.couple);
    if (persisted.level !== state.level) {
      persisted.level = state.level; // adopt baseline (reads never ceremonize)
      computeBadges(c.auth.couple, { store: c.store }); // keep badge baseline in sync
      c.store.markDirty();
    }
    sendJson(c.res, 200, { ...state, serverTime: nowIso() });
  });

  // Badge shelf: unlock states + progress (secret badges stay flagged).
  route('GET', '/api/badges', { auth: true }, (c) => {
    sendJson(c.res, 200, { badges: computeBadges(c.auth.couple, { store: c.store }) });
  });

  // Onboarding quest ("first week"): 7 derived steps + completion state.
  route('GET', '/api/quest', { auth: true }, (c) => {
    const before = gamificationOf(c.auth.couple).questCompletedAt;
    const state = questState(c.auth.couple, { store: c.store });
    if (!before && state.completedAt) {
      // Completing the quest is worth +150 XP — re-check for a level-up.
      maybeAdvanceGamification({ store: c.store, realtime: c.realtime, couple: c.auth.couple });
      c.realtime.broadcastCouple(c.auth.coupleId, 'quest_completed', { quest: state });
    }
    sendJson(c.res, 200, state);
  });
}
