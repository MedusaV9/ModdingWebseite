// V6/A3 — Home ambient-life rows + pure logic (PLAN6 Wave A / A3). PURE
// module: no three.js/DOM imports so node:test runs it headlessly
// (test/ambientLife.test.js). The three.js mount side lives in
// src/home/ambientLife.js and consumes these rows verbatim.
//
// The proven motion samplers are NOT duplicated here: flutterPose/driftPose
// are imported straight from src/recap/vignettes.logic.js (exported, pure).
// This module adds only the two home-specific samplers (fireflyPose for the
// instanced night swarm, twinklePose for the bedroom window star), the
// band/weather gating, the per-room draw-batch budget math and the pure
// disposal-ledger model the mount side uses for leak-proof teardown.
//
// ── Row shape ────────────────────────────────────────────────────────────────
// Every row is ONE draw batch when active (a single THREE.Sprite, or one
// InstancedMesh for `fireflies`). Rows are gated by day band + weather:
//   { id, room, kind: 'flutter'|'drift'|'twinkle'|'fireflies',
//     bands:   subset of systems/dayNight.js BANDS ids (night|dawn|day|dusk),
//     weather: subset of systems/weather.js WEATHER.STATES (clear|cloudy|rain),
//     anchor:  roomManager anchor name (room-scoped) or null,
//     at:      [x,y,z] — offset from the anchor, or absolute room-local
//              meters when anchor is null (positions from rooms/*.js consts),
//     tex:     ambientLife.js canvas-texture painter id,
//     color/scale/opacity + per-kind motion params (see AMBIENT_ROWS) }
//
// flutter rows reuse vignettes.logic.js flutterPose (center/radius/bob/speed/
// flapHz/phase — center is filled in by the mount from anchor+at); drift rows
// reuse driftPose (origin/rise/sway/speed/phase/opacity). Palette is the
// GOOBY pastel set (§D3: #FF7BA9 pink, #FFD166 gold, #9B8CFF lavender …).

/** Per-room hard cap of ambient draw batches active at once (PLAN6 §A3). */
export const MAX_AMBIENT_BATCHES_PER_ROOM = 4;

/** The 5 home room ids (mirrors roomManager NAV_ORDER — locked by tests). */
export const AMBIENT_ROOM_IDS = Object.freeze([
  'kitchen', 'living', 'bathroom', 'bedroom', 'garden',
]);

/** Gate id mirrors (validated against dayNight/weather in the test suite). */
export const AMBIENT_BAND_IDS = Object.freeze(['night', 'dawn', 'day', 'dusk']);
export const AMBIENT_WEATHER_IDS = Object.freeze(['clear', 'cloudy', 'rain']);

const ALL_BANDS = AMBIENT_BAND_IDS;
const ALL_WEATHER = AMBIENT_WEATHER_IDS;
const DRY = Object.freeze(['clear', 'cloudy']);

/**
 * All ambient rows, one flat table (filter with activeRows()).
 * @type {ReadonlyArray<object>}
 */
export const AMBIENT_ROWS = Object.freeze([
  // ── garden · day: two pastel butterflies + one bee working the flower bed
  // (recap `meadow` tuning: speed 0.11–0.16 orbits/s, flapHz 8–10; hidden in
  // rain, the bee flaps faster on a tighter orbit) ──────────────────────────
  Object.freeze({
    id: 'gardenButterflyGold', room: 'garden', kind: 'flutter',
    bands: Object.freeze(['dawn', 'day']), weather: DRY,
    anchor: 'flowerBed', at: Object.freeze([0.15, 1.0, 0.55]),
    tex: 'butterfly', color: '#FFD166', scale: 0.2,
    radius: 0.85, bob: 0.28, speed: 0.13, flapHz: 8, phase: 0,
  }),
  Object.freeze({
    id: 'gardenButterflyPink', room: 'garden', kind: 'flutter',
    bands: Object.freeze(['dawn', 'day']), weather: DRY,
    anchor: 'flowerBed', at: Object.freeze([-0.3, 0.85, 0.85]),
    tex: 'butterfly', color: '#FF7BA9', scale: 0.17,
    radius: 0.68, bob: 0.24, speed: 0.11, flapHz: 9, phase: 2.1,
  }),
  Object.freeze({
    id: 'gardenBee', room: 'garden', kind: 'flutter',
    bands: Object.freeze(['dawn', 'day']), weather: DRY,
    anchor: 'flowerBed', at: Object.freeze([0.55, 0.55, 0.4]),
    tex: 'bee', color: '#FFFFFF', scale: 0.11,
    radius: 0.42, bob: 0.16, speed: 0.2, flapHz: 14, phase: 4.2,
  }),
  // ── garden · night: one InstancedMesh firefly swarm (24 instances, exactly
  // 1 draw call — the big "alive at night" read for the cheapest cost) ──────
  Object.freeze({
    id: 'gardenFireflies', room: 'garden', kind: 'fireflies',
    bands: Object.freeze(['night']), weather: DRY,
    anchor: null, at: Object.freeze([0, 0, 0]),
    tex: 'glowDot', color: '#D9FFA6', count: 24,
    area: Object.freeze({
      x: Object.freeze([-2.1, 2.1]),
      y: Object.freeze([0.25, 1.7]),
      z: Object.freeze([-1.5, 1.2]),
    }),
    wander: 0.32, size: Object.freeze([0.05, 0.09]),
    blinkHz: Object.freeze([0.22, 0.55]),
  }),

  // ── kitchen: steam wisps above the stove pot (recap `bakery` drift tuning
  // transferred + rescaled to room meters; always on — the kitchen simmers).
  // No stove anchor exists in rooms/kitchen.js, so positions come from its
  // constants (stove x 0.72 / pot [0.68, 0.698, −1.18], counter top ≈ 0.70) ─
  Object.freeze({
    id: 'kitchenSteamA', room: 'kitchen', kind: 'drift',
    bands: ALL_BANDS, weather: ALL_WEATHER,
    anchor: null, at: Object.freeze([0.66, 0.86, -1.02]),
    tex: 'puff', color: '#FFF4E6', opacity: 0.5, scale: 0.16,
    rise: 0.52, sway: 0.07, speed: 0.16, phase: 0.15,
  }),
  Object.freeze({
    id: 'kitchenSteamB', room: 'kitchen', kind: 'drift',
    bands: ALL_BANDS, weather: ALL_WEATHER,
    anchor: null, at: Object.freeze([0.79, 0.83, -0.98]),
    tex: 'puff', color: '#FFEEDE', opacity: 0.42, scale: 0.13,
    rise: 0.64, sway: 0.09, speed: 0.13, phase: 0.55,
  }),
  Object.freeze({
    id: 'kitchenSteamC', room: 'kitchen', kind: 'drift',
    bands: ALL_BANDS, weather: ALL_WEATHER,
    anchor: null, at: Object.freeze([0.6, 0.82, -0.94]),
    tex: 'puff', color: '#FFF7EC', opacity: 0.36, scale: 0.11,
    rise: 0.56, sway: 0.06, speed: 0.18, phase: 0.85,
  }),

  // ── living: warm dust motes floating in the daylight shaft (recap
  // `toyRoom` dust-mote rows, opacity ≤ 0.35 so it reads subliminal; no
  // window prop exists in rooms/living.js, so the shaft angles from the
  // ceiling-lamp spot [0, 2.7, −0.18] toward the rug) ───────────────────────
  Object.freeze({
    id: 'livingMoteA', room: 'living', kind: 'drift',
    bands: Object.freeze(['dawn', 'day']), weather: DRY,
    anchor: null, at: Object.freeze([0.16, 1.05, -0.35]),
    tex: 'glowDot', color: '#FFD166', opacity: 0.32, scale: 0.055,
    rise: 0.5, sway: 0.12, speed: 0.1, phase: 0,
  }),
  Object.freeze({
    id: 'livingMoteB', room: 'living', kind: 'drift',
    bands: Object.freeze(['dawn', 'day']), weather: DRY,
    anchor: null, at: Object.freeze([0.44, 0.85, -0.18]),
    tex: 'glowDot', color: '#FFE6AE', opacity: 0.26, scale: 0.045,
    rise: 0.62, sway: 0.1, speed: 0.13, phase: 0.4,
  }),
  Object.freeze({
    id: 'livingMoteC', room: 'living', kind: 'drift',
    bands: Object.freeze(['dawn', 'day']), weather: DRY,
    anchor: null, at: Object.freeze([-0.1, 1.28, -0.5]),
    tex: 'glowDot', color: '#FFDF98', opacity: 0.3, scale: 0.06,
    rise: 0.44, sway: 0.14, speed: 0.08, phase: 0.7,
  }),

  // ── bathroom: occasional soap bubbles over the tub — slow rise, fading
  // out at the top of each loop (the "pop"). Tub sits at [−0.72, 0, −0.6],
  // rim ≈ 0.5 m (rooms/bathroom.js) ─────────────────────────────────────────
  Object.freeze({
    id: 'bathBubbleA', room: 'bathroom', kind: 'drift',
    bands: ALL_BANDS, weather: ALL_WEATHER,
    anchor: 'bathtub', at: Object.freeze([-0.22, 0.58, 0.18]),
    tex: 'bubble', color: '#FFFFFF', opacity: 0.6, scale: 0.085,
    rise: 0.85, sway: 0.09, speed: 0.08, phase: 0.1,
  }),
  Object.freeze({
    id: 'bathBubbleB', room: 'bathroom', kind: 'drift',
    bands: ALL_BANDS, weather: ALL_WEATHER,
    anchor: 'bathtub', at: Object.freeze([0.18, 0.54, 0.3]),
    tex: 'bubble', color: '#DFF1FF', opacity: 0.5, scale: 0.065,
    rise: 0.68, sway: 0.07, speed: 0.1, phase: 0.5,
  }),
  Object.freeze({
    id: 'bathBubbleC', room: 'bathroom', kind: 'drift',
    bands: ALL_BANDS, weather: ALL_WEATHER,
    anchor: 'bathtub', at: Object.freeze([-0.05, 0.6, -0.12]),
    tex: 'bubble', color: '#F3FBFF', opacity: 0.55, scale: 0.11,
    rise: 0.95, sway: 0.1, speed: 0.065, phase: 0.8,
  }),

  // ── bedroom: a tiny twinkling star pair at the window on clear nights
  // (window anchor [0.22, 1.9, −1.49], pane 0.98×0.98 — offsets stay on the
  // glass, +z keeps the sprites just in front of the pane plane) ────────────
  Object.freeze({
    id: 'bedroomStarGold', room: 'bedroom', kind: 'twinkle',
    bands: Object.freeze(['night']), weather: Object.freeze(['clear']),
    anchor: 'window', at: Object.freeze([-0.24, 0.26, 0.09]),
    tex: 'star4', color: '#FFE9A8', scale: 0.09,
    baseOpacity: 0.75, amp: 0.25, period: 3.7, phase: 0,
  }),
  Object.freeze({
    id: 'bedroomStarBlue', room: 'bedroom', kind: 'twinkle',
    bands: Object.freeze(['night']), weather: Object.freeze(['clear']),
    anchor: 'window', at: Object.freeze([0.28, 0.1, 0.09]),
    tex: 'star4', color: '#CFE4FF', scale: 0.06,
    baseOpacity: 0.6, amp: 0.35, period: 5.3, phase: 2.0,
  }),
]);

/**
 * Pure band/weather gate: the rows that should be mounted for a room under
 * the given ambience. Every returned row costs exactly one draw batch.
 * @param {string} roomId
 * @param {'night'|'dawn'|'day'|'dusk'} band
 * @param {'clear'|'cloudy'|'rain'} weather
 * @returns {object[]}
 */
export function activeRows(roomId, band, weather) {
  return AMBIENT_ROWS.filter(
    (row) => row.room === roomId
      && row.bands.includes(band)
      && row.weather.includes(weather)
  );
}

/**
 * Draw batches a room's ambient layer adds under the given ambience — the
 * machine-provable ≤ MAX_AMBIENT_BATCHES_PER_ROOM budget number
 * (ambientLife.js getDebugStats() reports the live mounted equivalent).
 * @param {string} roomId @param {string} band @param {string} weather
 * @returns {number}
 */
export function roomBatchCount(roomId, band, weather) {
  return activeRows(roomId, band, weather).length;
}

// ---------------------------------------------------------------------------
// Home-specific pure samplers (flutterPose/driftPose come from
// src/recap/vignettes.logic.js — reused, not copied)
// ---------------------------------------------------------------------------

/** Deterministic [0,1) hash of a float (classic fract-sin — no RNG state). */
function fract01(n) {
  const x = Math.sin(n * 127.1 + 311.7) * 43758.5453;
  return x - Math.floor(x);
}

const lerp = (a, b, u) => a + (b - a) * u;

/**
 * Firefly instance sampler: each instance idles around a hash-seeded home
 * spot inside row.area with two incommensurate sine wanders and a slow
 * phase-offset blink. Pure — same (row, i, t) → same pose.
 * @param {{area: {x: number[], y: number[], z: number[]}, wander: number,
 *   size: number[], blinkHz: number[]}} row
 * @param {number} i instance index (0 … row.count−1)
 * @param {number} t seconds
 * @returns {{position: number[], blink: number, size: number}} blink 0..1
 */
export function fireflyPose(row, i, t) {
  const tt = Math.max(0, Number(t) || 0);
  const r1 = fract01(i + 1);
  const r2 = fract01((i + 1) * 2.37);
  const r3 = fract01((i + 1) * 5.91);
  const w = row.wander;
  const position = [
    lerp(row.area.x[0], row.area.x[1], r1)
      + Math.sin(tt * 0.31 + r1 * Math.PI * 2) * w
      + Math.sin(tt * 0.113 + r2 * Math.PI * 2) * w * 0.5,
    lerp(row.area.y[0], row.area.y[1], r2)
      + Math.sin(tt * 0.23 + r3 * Math.PI * 2) * w * 0.6,
    lerp(row.area.z[0], row.area.z[1], r3)
      + Math.sin(tt * 0.17 + r1 * Math.PI * 2) * w * 0.5,
  ];
  const blinkHz = lerp(row.blinkHz[0], row.blinkHz[1], r3);
  const blink = 0.5 + 0.5 * Math.sin(tt * blinkHz * Math.PI * 2 + r1 * 20);
  return { position, blink, size: lerp(row.size[0], row.size[1], r2) };
}

/**
 * Twinkle sampler for the bedroom window star: slow sine opacity shimmer +
 * a subtle incommensurate scale pulse. Pure and bounded (opacity 0..1).
 * @param {{baseOpacity: number, amp: number, period: number, phase: number}} row
 * @param {number} t seconds
 * @returns {{opacity: number, pulse: number}}
 */
export function twinklePose(row, t) {
  const tt = Math.max(0, Number(t) || 0);
  const raw = row.baseOpacity + row.amp * Math.sin((tt / row.period) * Math.PI * 2 + row.phase);
  return {
    opacity: Math.min(1, Math.max(0, raw)),
    pulse: 1 + 0.06 * Math.sin((tt / (row.period * 1.7)) * Math.PI * 2 + row.phase),
  };
}

// ---------------------------------------------------------------------------
// Disposal ledger — pure bookkeeping model the mount side wraps around every
// geometry/material/texture it creates, so teardown is provable in node:test
// without three.js (test: track → disposeAll → outstanding() === 0).
// ---------------------------------------------------------------------------

/**
 * @returns {{
 *   track: <T extends {dispose?: Function}>(res: T, kind?: string) => T,
 *   disposeAll: () => number,
 *   outstanding: () => number,
 *   byKind: () => Record<string, number>,
 * }}
 */
export function createDisposalLedger() {
  /** @type {Array<{res: {dispose?: Function}, kind: string}>} */
  let entries = [];
  return {
    track(res, kind = 'resource') {
      entries.push({ res, kind });
      return res;
    },
    disposeAll() {
      const n = entries.length;
      for (const { res } of entries) {
        try {
          res.dispose?.();
        } catch (err) {
          console.error('[ambientLife] dispose error:', err);
        }
      }
      entries = [];
      return n;
    },
    outstanding() {
      return entries.length;
    },
    byKind() {
      /** @type {Record<string, number>} */
      const out = {};
      for (const { kind } of entries) out[kind] = (out[kind] ?? 0) + 1;
      return out;
    },
  };
}
