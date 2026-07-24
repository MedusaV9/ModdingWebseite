// V5/VACATION — vacation/airport engine (PLAN5 idea IDEA-01): the pure state
// machine behind "Gooby flies away for a few days". PURE module — no
// three.js/DOM imports; node:test drives it directly (test/vacation.test.js).
// Same architecture as systems/modifierEngine.js: a defensive defaultSlice()
// factory (NO SAVE.VERSION bump — save.js mergeDefaults passes unknown
// top-level keys through verbatim), a pure tick(state, nowMs) that returns
// `{changes, events}` and never mutates, and all exact numbers FROZEN HERE
// per the §E0.1-2 owning-module rule.
//
// The user fantasy (binding shape):
//   1. book a destination at the airport (economy.bookVacation pays) →
//      Gooby is AWAY for the destination's 3–4 REAL days. While away his
//      stats/health/weight are FROZEN (the resort takes care of him — see
//      the marked V5/VACATION block in core/timeEngine.js) and home care /
//      arcade are gated ('vacation.blocked' toast).
//   2. one postcard per full day away (except the travel-home day) —
//      tick events {type:'postcard'} → HUD toast.
//   3. at returnAt the phase flips to RETURN_READY: Gooby waits at the
//      airport for PICKUP_WINDOW_MS (24 h). Free pickup = reunion confetti,
//      full stats, coin souvenir (economy.pickupVacation).
//   4. missed the window → OVERDUE: Gooby needs the TAXI_FEE taxi home
//      (economy.payTaxiReturn) — same reunion, minus the fee.
//
// Store event contract (mirrors 'modifierChanged'): whoever assigns the
// slice emits 'vacationChanged' {phase, destId}; the timeEngine block also
// re-emits every tick event as 'vacationEvent' (payload: the event object).
// Consumers: the HUD chip + toasts (ui/hud.js marked block), Gooby
// visibility + care gates (home/interactions.js), the airport panel
// (ui/airportScreen.js).
//
// V6/D2 (PLAN6 Wave D): postcards additionally persist as KEEPSAKES — the
// slice gains `archive` (capped entry list) + `lastPostcardDayProcessed`
// (per-trip bookkeeping); all archive math lives in the pure sibling
// systems/postcards.js and generation happens inside tick(), so the live
// ticker and the offline catch-up produce identical archives for free.
// `postcards` (the count) keeps its V5 semantics untouched — it stays the
// toast counter; the archive is parallel bookkeeping.

import { getVacation, VACATION_IDS } from '../data/vacations.js';
// V6/D2 (PLAN6 Wave D): postcard-archive engine (pure sibling — this module
// stays the only writer of the slice; postcards.js owns the archive math).
import { normalizeArchive, processPostcardsUpTo } from './postcards.js';

/** Vacation phases (frozen). 'none' = Gooby is home. */
export const VACATION_PHASE = Object.freeze({
  NONE: 'none',
  AWAY: 'away',
  RETURN_READY: 'returnReady',
  OVERDUE: 'overdue',
});

/** §E0.1-2: the binding vacation numbers — frozen in the owning module. */
export const VACATION = Object.freeze({
  /** One vacation "day" in REAL ms (destination days count in these). */
  MS_PER_DAY: 86400000,
  /** Pickup window after returnAt before the taxi is needed (24 h). */
  PICKUP_WINDOW_MS: 24 * 3600000,
  /** Taxi fee for an overdue pickup (economy.payTaxiReturn). */
  TAXI_FEE: 60,
  /** All four stats fill to this on the reunion (clamped by stats.js). */
  PICKUP_STAT_FILL: 100,
});

/**
 * The vacation save slice at its defaults (defensive factory — the engine
 * self-heals a missing slice through this, so no SAVE.VERSION bump).
 *
 * V6/D2 (PLAN6 Wave D): two ADDITIVE fields — `archive` (the postcard
 * keepsakes, `{destId, dayIndex, variant, atMs}` entries capped at
 * POSTCARDS.MAX_ARCHIVE by systems/postcards.js) and
 * `lastPostcardDayProcessed` (per-trip generation bookkeeping — monotonic,
 * reset on book/pickup). Both are wired through defaultSlice(), sliceOf()
 * AND the carried-transition helpers bookSlice()/pickupSlice() per the
 * whitelist-strip rule (sliceOf strips unknown fields silently).
 *
 * V6.1/C3 (FINAL-WAVE G1): one more ADDITIVE field — `visited`, the
 * Reiseziele-Sammelpass truth: a `{destId: true}` map latched by
 * pickupSlice() when a trip COMPLETES (booking alone never marks it).
 * Bounded by construction: sliceOf() keeps only the nine VACATION_IDS whose
 * value is strictly `true`, so junk saves can never grow it. Lifetime like
 * `archive` — both carried transitions preserve it. No SAVE.VERSION bump
 * (mergeDefaults passes the slice through; sliceOf self-heals).
 * @returns {{phase: string, destId: string, bookedAt: number,
 *   returnAt: number, pickupBy: number, postcards: number, trips: number,
 *   archive: import('./postcards.js').PostcardEntry[],
 *   lastPostcardDayProcessed: number, visited: Record<string, true>}}
 */
export function defaultSlice() {
  return {
    phase: VACATION_PHASE.NONE,
    destId: '',
    bookedAt: 0,
    returnAt: 0,
    pickupBy: 0,
    postcards: 0,
    trips: 0,
    // V6/D2: postcard archive + per-trip day bookkeeping (additive)
    archive: [],
    lastPostcardDayProcessed: 0,
    // V6.1/C3: destinations completed at least once (additive, lifetime)
    visited: {},
  };
}

/**
 * Read the vacation slice off a save state, normalized through the factory
 * (never mutates `state`; junk leaves fall back to the defaults).
 * @param {object} state save state (or any {vacation?} shape)
 * @returns {ReturnType<typeof defaultSlice>}
 */
export function sliceOf(state) {
  const raw = state?.vacation;
  const d = defaultSlice();
  if (raw == null || typeof raw !== 'object') return d;
  const num = (v) => (Number.isFinite(Number(v)) ? Number(v) : 0);
  const phase = Object.values(VACATION_PHASE).includes(raw.phase) ? raw.phase : d.phase;
  return {
    phase,
    destId: typeof raw.destId === 'string' ? raw.destId : '',
    bookedAt: num(raw.bookedAt),
    returnAt: num(raw.returnAt),
    pickupBy: num(raw.pickupBy),
    postcards: Math.max(0, Math.floor(num(raw.postcards))),
    trips: Math.max(0, Math.floor(num(raw.trips))),
    // V6/D2: junk archives normalize (drop/dedupe/sort/cap) in postcards.js
    archive: normalizeArchive(raw.archive),
    lastPostcardDayProcessed: Math.max(0, Math.floor(num(raw.lastPostcardDayProcessed))),
    // V6.1/C3: whitelist-normalize the Sammelpass map — only the nine
    // catalog ids survive, and only when strictly `true` (unknown ids and
    // truthy junk drop silently; the map is naturally capped at 9 keys).
    visited: normalizeVisited(raw.visited),
  };
}

/**
 * V6.1/C3 — normalize a raw `visited` map: known VACATION_IDS with a value
 * of strictly `true` only (catalog order; everything else drops).
 * @param {unknown} raw
 * @returns {Record<string, true>}
 */
function normalizeVisited(raw) {
  if (raw == null || typeof raw !== 'object' || Array.isArray(raw)) return {};
  /** @type {Record<string, true>} */
  const out = {};
  for (const id of VACATION_IDS) {
    if (raw[id] === true) out[id] = true;
  }
  return out;
}

/**
 * Is Gooby physically NOT home right now (any active phase — away at the
 * resort OR waiting at the airport)? The single gate predicate for care/
 * arcade/trip surfaces and the home-scene visibility sync.
 * @param {object} state save state
 * @returns {boolean}
 */
export function isAway(state) {
  return sliceOf(state).phase !== VACATION_PHASE.NONE;
}

/**
 * Derive the phase a booked slice SHOULD be in at `nowMs` (pure timestamp
 * math — the persisted `phase` field exists so gates/UI never need a clock;
 * tick() keeps the two aligned).
 * @param {ReturnType<typeof defaultSlice>} v
 * @param {number} nowMs
 * @returns {string} VACATION_PHASE value
 */
export function phaseAt(v, nowMs) {
  if (!v || v.phase === VACATION_PHASE.NONE || !(v.returnAt > 0)) return VACATION_PHASE.NONE;
  if (nowMs < v.returnAt) return VACATION_PHASE.AWAY;
  if (nowMs < v.pickupBy) return VACATION_PHASE.RETURN_READY;
  return VACATION_PHASE.OVERDUE;
}

/**
 * Postcards due by `nowMs`: one per FULL day away, capped at days − 1 (the
 * last day Gooby travels home instead of writing).
 * @param {ReturnType<typeof defaultSlice>} v
 * @param {number} nowMs
 * @returns {number}
 */
export function postcardsDue(v, nowMs) {
  if (!v || v.phase === VACATION_PHASE.NONE || !(v.bookedAt > 0) || !(v.returnAt > v.bookedAt)) return 0;
  const totalDays = Math.round((v.returnAt - v.bookedAt) / VACATION.MS_PER_DAY);
  const maxCards = Math.max(0, totalDays - 1);
  const fullDays = Math.floor((Math.min(nowMs, v.returnAt) - v.bookedAt) / VACATION.MS_PER_DAY);
  return Math.max(0, Math.min(fullDays, maxCards));
}

/**
 * A freshly booked slice (validation/payment is economy.bookVacation's job —
 * this is pure slice math). `prev` carries the lifetime trips counter over.
 * @param {object|null|undefined} prev previous vacation slice (or null)
 * @param {string} destId catalog id (must exist — caller validates)
 * @param {number} nowMs booking timestamp
 * @returns {ReturnType<typeof defaultSlice>}
 */
export function bookSlice(prev, destId, nowMs) {
  const dest = getVacation(destId);
  const days = dest ? dest.days : 3;
  const returnAt = nowMs + days * VACATION.MS_PER_DAY;
  // V6/D2: the archive is a LIFETIME keepsake shelf — it carries across the
  // booking; the per-trip day bookkeeping restarts at 0 (defaultSlice).
  // V6.1/C3: the Sammelpass map carries too — but booking NEVER latches the
  // new destination (only a completed pickup does, in pickupSlice below).
  const carried = sliceOf({ vacation: prev });
  return {
    ...defaultSlice(),
    phase: VACATION_PHASE.AWAY,
    destId,
    bookedAt: nowMs,
    returnAt,
    pickupBy: returnAt + VACATION.PICKUP_WINDOW_MS,
    trips: carried.trips,
    archive: carried.archive,
    visited: carried.visited,
  };
}

/**
 * The slice after a completed pickup/taxi reunion: back to defaults with the
 * lifetime trips counter bumped.
 * @param {object|null|undefined} prev vacation slice being completed
 * @returns {ReturnType<typeof defaultSlice>}
 */
export function pickupSlice(prev) {
  // V6/D2: postcards survive the reunion (travel artifacts, stored once);
  // the per-trip bookkeeping resets with the rest of the slice.
  // V6.1/C3: the reunion is the ONE Sammelpass latch — the just-completed
  // destination stamps `visited` (valid catalog ids only; both the on-time
  // pickup and the overdue taxi land here through economy.js).
  const carried = sliceOf({ vacation: prev });
  const visited = { ...carried.visited };
  if (getVacation(carried.destId)) visited[carried.destId] = true;
  return {
    ...defaultSlice(),
    trips: carried.trips + 1,
    archive: carried.archive,
    visited,
  };
}

/**
 * The 1 s engine tick — PURE (modifierEngine.tick contract): returns a fresh
 * slice in `changes` only when something changed, plus the events that fired.
 * Idempotent across any gap (offline catch-up calls it once with the boot
 * clock and gets the same transitions a live ticker would have emitted).
 * Event shapes:
 *   {type: 'postcard', destId, n}   — nth postcard arrived
 *   {type: 'returnReady', destId}   — Gooby waits at the airport
 *   {type: 'overdue', destId}       — pickup window missed (taxi needed)
 * @param {object} state full save state (reads state.vacation only)
 * @param {number} nowMs clock.now()
 * @returns {{changes: ReturnType<typeof defaultSlice>|null,
 *   events: {type: string, destId: string, n?: number}[]}}
 */
export function tick(state, nowMs) {
  const base = state?.vacation ?? null;
  const v = sliceOf(state);
  /** @type {{type: string, destId: string, n?: number}[]} */
  const events = [];
  let changed = base == null;
  if (v.phase === VACATION_PHASE.NONE) {
    return { changes: changed ? v : null, events };
  }
  const due = postcardsDue(v, nowMs);
  if (due > v.postcards) {
    for (let n = v.postcards + 1; n <= due; n += 1) {
      events.push({ type: 'postcard', destId: v.destId, n });
    }
    v.postcards = due;
    changed = true;
  }
  // ── V6/D2: postcard ARCHIVE generation — the ONE shared pure processor
  // (systems/postcards.js) both catch-up paths reach through this tick
  // (core/timeEngine.js live 1 s ticker AND systems/offline.js boot sim),
  // so live and offline replays yield byte-identical archives. Entries are
  // stamped with their fixed-ms day boundary (bookedAt + k·day — DST-safe),
  // deterministic variants ride the trip seed, and the monotonic
  // `lastPostcardDayProcessed` bookkeeping forbids duplicates (a backwards
  // clock jump generates nothing). Cap 36 FIFO inside the processor.
  {
    const pc = processPostcardsUpTo(v, nowMs);
    if (pc.added > 0) {
      v.archive = pc.archive;
      v.lastPostcardDayProcessed = pc.lastPostcardDayProcessed;
      changed = true;
    }
  }
  // ── end V6/D2 ──
  const phase = phaseAt(v, nowMs);
  if (phase !== v.phase) {
    // Walk skipped stages so offline gaps still announce the airport wait
    // before the taxi call (event order: returnReady → overdue).
    if (v.phase === VACATION_PHASE.AWAY && phase !== VACATION_PHASE.AWAY) {
      events.push({ type: 'returnReady', destId: v.destId });
    }
    if (phase === VACATION_PHASE.OVERDUE) {
      events.push({ type: 'overdue', destId: v.destId });
    }
    v.phase = phase;
    changed = true;
  }
  return { changes: changed ? v : null, events };
}

/**
 * Countdown for the HUD chip / airport panel: ms until the NEXT milestone —
 * away → returnAt, returnReady → pickupBy (time left before the taxi),
 * overdue/none → 0.
 * @param {object} state save state
 * @param {number} nowMs
 * @returns {number} ms ≥ 0
 */
export function remainingMs(state, nowMs) {
  const v = sliceOf(state);
  if (v.phase === VACATION_PHASE.AWAY) return Math.max(0, v.returnAt - nowMs);
  if (v.phase === VACATION_PHASE.RETURN_READY) return Math.max(0, v.pickupBy - nowMs);
  return 0;
}

/**
 * Compact countdown label for chips/cards: '2d 5h' above a day, 'h:mm' below
 * (pure string math — locale-free by design, tested headlessly).
 * @param {number} ms
 * @returns {string}
 */
export function formatCountdown(ms) {
  const total = Math.max(0, Math.floor(Number(ms) || 0));
  const days = Math.floor(total / VACATION.MS_PER_DAY);
  const hours = Math.floor((total % VACATION.MS_PER_DAY) / 3600000);
  if (days > 0) return `${days}d ${hours}h`;
  const mins = Math.floor((total % 3600000) / 60000);
  return `${hours}:${String(mins).padStart(2, '0')}`;
}
