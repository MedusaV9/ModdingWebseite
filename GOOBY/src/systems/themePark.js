// V6/E1 — Funkelpark compact state (PLAN6 Wave E/E1): the defensive save
// slice behind the park day trip. PURE module — no three.js/DOM imports;
// node:test drives it directly (test/themePark.test.js). Same architecture
// as systems/vacation.js: a defaultSlice() factory (NO SAVE.VERSION bump —
// save.js mergeDefaults passes unknown top-level keys through verbatim), a
// whitelist-normalizing sliceOf(state), and small pure record* transition
// helpers that always return a NORMALIZED slice (risk row 7: every additive
// field lands in defaultSlice/sliceOf/transition helpers; counters are
// restricted to known ids only).
//
// What it tracks (the F1 sticker surface — pure reads of this slice):
//   visits        plaza entries (a coaster return to the plaza is NOT a new
//                 visit — parkScene passes {from:'coaster'} and skips it)
//   nightVisit    latched true once Gooby stood in the plaza during the
//                 dayNight 'night' band (never unlatches)
//   rides         rides ridden, keyed by KNOWN ids only (['coaster'] —
//                 F4's ferris wheel adds its id HERE when it lands)
//   handsUp       hands-up moments booked from the coaster (E2's ride has
//                 no store writes of its own — E1's onDone/F1 may call
//                 recordHandsUp; 0 until someone does)
//   candyBought   Candy Alley purchases — E3's parkStall buys through the
//                 existing economy.buyFood (reason 'shop', no new economy
//                 event), so parkScene observes 'inventoryChanged' diffs of
//                 the three park foods while the plaza is active and books
//                 them here.
//
// Writer contract: parkScene.js (and shopTrip's park handoff) are the only
// writers; everyone else reads. Slice assignment happens inside store.update
// so the coalesced 'change' event reaches the sticker book for free.

/** Known ride ids (frozen — unknown ids are DROPPED by the normalizer). */
export const PARK_RIDE_IDS = Object.freeze(['coaster']);

/** §E0.1-2: binding park-state numbers live in the owning module. */
export const THEME_PARK = Object.freeze({
  /** Hard ceiling for every counter (defensive clamp — junk saves). */
  MAX_COUNT: 99999,
});

/** @typedef {{visits: number, nightVisit: boolean,
 *   rides: Record<string, number>, handsUp: number, candyBought: number}}
 *   ThemeParkSlice */

/** Clamp a junk value to a whole 0..MAX_COUNT counter. */
function clampCount(v) {
  const n = Number(v);
  if (!Number.isFinite(n)) return 0;
  return Math.max(0, Math.min(THEME_PARK.MAX_COUNT, Math.floor(n)));
}

/**
 * The themePark save slice at its defaults (defensive factory — consumers
 * self-heal a missing slice through this, so no SAVE.VERSION bump).
 * @returns {ThemeParkSlice}
 */
export function defaultSlice() {
  return {
    visits: 0,
    nightVisit: false,
    rides: Object.fromEntries(PARK_RIDE_IDS.map((id) => [id, 0])),
    handsUp: 0,
    candyBought: 0,
  };
}

/**
 * Read the themePark slice off a save state, normalized through the factory
 * (never mutates `state`; junk leaves fall back to the defaults; ride
 * counters are whitelisted to PARK_RIDE_IDS — unknown ids drop silently).
 * @param {object} [state] save state (or any {themePark?} shape)
 * @returns {ThemeParkSlice}
 */
export function sliceOf(state) {
  const raw = state?.themePark;
  const d = defaultSlice();
  if (raw == null || typeof raw !== 'object' || Array.isArray(raw)) return d;
  const rawRides = raw.rides != null && typeof raw.rides === 'object' && !Array.isArray(raw.rides)
    ? raw.rides
    : {};
  return {
    visits: clampCount(raw.visits),
    nightVisit: raw.nightVisit === true,
    rides: Object.fromEntries(PARK_RIDE_IDS.map((id) => [id, clampCount(rawRides[id])])),
    handsUp: clampCount(raw.handsUp),
    candyBought: clampCount(raw.candyBought),
  };
}

// ---------------------------------------------------------------------------
// Pure transition helpers (each takes ANY slice-ish input and returns a new
// normalized slice — callers assign the result inside store.update).
// ---------------------------------------------------------------------------

/**
 * Book one plaza visit (§E1: parkScene enter, unless returning from the
 * coaster). `night` latches the nightVisit flag; it never unlatches.
 * @param {object} [slice] current themePark slice (junk-tolerant)
 * @param {{night?: boolean}} [opts]
 * @returns {ThemeParkSlice}
 */
export function recordVisit(slice, { night = false } = {}) {
  const s = sliceOf({ themePark: slice });
  s.visits = clampCount(s.visits + 1);
  if (night) s.nightVisit = true;
  return s;
}

/**
 * Latch the nightVisit flag without a new visit (the band can flip to
 * 'night' WHILE Gooby stands in the plaza — parkScene's band subscription).
 * @param {object} [slice]
 * @returns {ThemeParkSlice}
 */
export function recordNight(slice) {
  const s = sliceOf({ themePark: slice });
  s.nightVisit = true;
  return s;
}

/**
 * Book one finished ride. Unknown ride ids are a normalized no-op (the
 * counter set stays restricted to PARK_RIDE_IDS — risk row 7).
 * @param {object} [slice]
 * @param {string} rideId one of PARK_RIDE_IDS ('coaster')
 * @returns {ThemeParkSlice}
 */
export function recordRide(slice, rideId) {
  const s = sliceOf({ themePark: slice });
  if (PARK_RIDE_IDS.includes(rideId)) {
    s.rides[rideId] = clampCount(s.rides[rideId] + 1);
  }
  return s;
}

/**
 * Book Candy Alley purchases (parkScene's inventoryChanged diff of the park
 * foods while the plaza is active). Non-positive/junk counts are a no-op.
 * @param {object} [slice]
 * @param {number} [count] items bought (whole, ≥ 1)
 * @returns {ThemeParkSlice}
 */
export function recordCandy(slice, count = 1) {
  const s = sliceOf({ themePark: slice });
  const n = clampCount(count);
  s.candyBought = clampCount(s.candyBought + n);
  return s;
}

/**
 * Book hands-up moments from the coaster (E2's ride bumps no slice of its
 * own — the wire is E1's onDone / a later F1 hook). Junk counts no-op.
 * @param {object} [slice]
 * @param {number} [count] hands-up windows hit (whole, ≥ 1)
 * @returns {ThemeParkSlice}
 */
export function recordHandsUp(slice, count = 1) {
  const s = sliceOf({ themePark: slice });
  s.handsUp = clampCount(s.handsUp + clampCount(count));
  return s;
}
