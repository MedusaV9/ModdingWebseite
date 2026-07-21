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

import { getVacation } from '../data/vacations.js';

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
 * @returns {{phase: string, destId: string, bookedAt: number,
 *   returnAt: number, pickupBy: number, postcards: number, trips: number}}
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
  };
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
  return {
    ...defaultSlice(),
    phase: VACATION_PHASE.AWAY,
    destId,
    bookedAt: nowMs,
    returnAt,
    pickupBy: returnAt + VACATION.PICKUP_WINDOW_MS,
    trips: sliceOf({ vacation: prev }).trips,
  };
}

/**
 * The slice after a completed pickup/taxi reunion: back to defaults with the
 * lifetime trips counter bumped.
 * @param {object|null|undefined} prev vacation slice being completed
 * @returns {ReturnType<typeof defaultSlice>}
 */
export function pickupSlice(prev) {
  return { ...defaultSlice(), trips: sliceOf({ vacation: prev }).trips + 1 };
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
