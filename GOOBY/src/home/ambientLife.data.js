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
// V6/F2 appends the living-world PURE sections at the bottom of this file:
// the WATCH head-tracking decision logic (watchTarget — hysteresis so
// Gooby's gaze never jitters), the HUM happy-idle schedule, and the
// transient garden bird VISITOR (clock-hashed schedule + flight/hop/peck
// pose sampler). Mount sides: homeScene.js (watch/hum wiring) and the new
// src/home/ambientVisitors.js (bird). Tested in test/ambientLife.test.js
// (watch/hum) and test/ambientVisitors.test.js (visitor).
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

// V6/F2: the committed §B4 clock-hash recipe (fixed-vector locked in
// test/weather.test.js) — the bird visitor schedule derives from it so every
// player sees the same visit at the same wall-clock time, zero storage.
import { hash32 } from '../systems/weather.js';

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

// ============================================================================
// V6/F2 — Gooby watches the ambient life (PLAN6 Wave F / F2).
// Pure decision logic for the clamped-lookAt head tracking: homeScene.js
// feeds it Gooby's head position + the live watchable sprite positions
// (ambientLife.js flutter batches + the ambientVisitors.js bird) every
// decision tick and drives gooby.lookAt() from the returned target. All
// hysteresis/cadence numbers live here so the behavior is headless-provable.
// ============================================================================

/** Watch tuning (meters/seconds — garden-scale: see AMBIENT_ROWS orbits). */
export const WATCH = Object.freeze({
  /** A sprite must come this close to Gooby's head to catch his eye. */
  ENTER_RADIUS: 2.4,
  /** …but keeps his attention until it drifts past THIS (hysteresis). */
  EXIT_RADIUS: 2.9,
  /** Gooby never stares longer than this per acquisition. */
  MAX_WATCH_SEC: 7,
  /** Pause after a full watch before the next acquisition. */
  COOLDOWN_SEC: 5,
  /** Shorter breather when the target escaped mid-watch (anti-jitter). */
  LOST_COOLDOWN_SEC: 2.5,
  /** Happy blink / ear-twitch cadence while a watch is running. */
  TWITCH_EVERY_SEC: 2.6,
});

/** @returns {{id: string|null, heldSec: number, cooldownSec: number}} */
export function createWatchState() {
  return { id: null, heldSec: 0, cooldownSec: 0 };
}

/** {x,y,z} | [x,y,z] → x/y/z reads (no allocation for the object case). */
const posX = (p) => (Array.isArray(p) ? p[0] : p.x);
const posY = (p) => (Array.isArray(p) ? p[1] : p.y);
const posZ = (p) => (Array.isArray(p) ? p[2] : p.z);

/** Euclidean distance between two {x,y,z}/[x,y,z] points. */
function posDist(a, b) {
  const dx = posX(a) - posX(b);
  const dy = posY(a) - posY(b);
  const dz = posZ(a) - posZ(b);
  return Math.sqrt(dx * dx + dy * dy + dz * dz);
}

/**
 * Pure watch decision step (hysteresis so the gaze never flip-flops):
 *  - cooldown counts down first — no acquisitions while it runs;
 *  - a held target is kept while it stays inside its EXIT radius and the
 *    watch is younger than MAX_WATCH_SEC (then: full COOLDOWN_SEC);
 *  - a target that escaped mid-watch costs LOST_COOLDOWN_SEC;
 *  - otherwise the NEAREST sprite inside its ENTER radius is acquired.
 * Sprites may override the radii per entry (the fence bird is worth a
 * longer look than a flowerbed butterfly): {enterRadius, exitRadius}.
 * `twitched` flips true exactly when heldSec crosses a TWITCH_EVERY_SEC
 * boundary — the caller's cue for the happy blink / ear twitch.
 * Never mutates its inputs; same inputs → same outputs.
 *
 * @param {{x:number,y:number,z:number}|number[]} goobyPos head position
 * @param {Array<{id: string, pos: {x:number,y:number,z:number}|number[],
 *   enterRadius?: number, exitRadius?: number}>} sprites live candidates
 * @param {{id: string|null, heldSec: number, cooldownSec: number}} state
 * @param {number} dt seconds since the previous decision step
 * @returns {{state: {id: string|null, heldSec: number, cooldownSec: number},
 *   target: {id: string, pos: object}|null, twitched: boolean}}
 */
export function watchTarget(goobyPos, sprites, state, dt) {
  const s = state ?? createWatchState();
  const step = Math.max(0, Number(dt) || 0);
  const list = Array.isArray(sprites) ? sprites : [];

  if (s.cooldownSec > 0) {
    return {
      state: { id: null, heldSec: 0, cooldownSec: Math.max(0, s.cooldownSec - step) },
      target: null,
      twitched: false,
    };
  }

  if (s.id != null) {
    const cur = list.find((sp) => sp.id === s.id);
    if (cur && posDist(goobyPos, cur.pos) <= (cur.exitRadius ?? WATCH.EXIT_RADIUS)) {
      const held = s.heldSec + step;
      if (held >= WATCH.MAX_WATCH_SEC) {
        return {
          state: { id: null, heldSec: 0, cooldownSec: WATCH.COOLDOWN_SEC },
          target: null,
          twitched: false,
        };
      }
      const twitched =
        Math.floor(held / WATCH.TWITCH_EVERY_SEC) > Math.floor(s.heldSec / WATCH.TWITCH_EVERY_SEC);
      return { state: { id: s.id, heldSec: held, cooldownSec: 0 }, target: cur, twitched };
    }
    // target escaped / despawned — short breather so a sprite hovering on
    // the boundary can't strobe the head on/off
    return {
      state: { id: null, heldSec: 0, cooldownSec: WATCH.LOST_COOLDOWN_SEC },
      target: null,
      twitched: false,
    };
  }

  let best = null;
  let bestDist = Infinity;
  for (const sp of list) {
    const d = posDist(goobyPos, sp.pos);
    if (d <= (sp.enterRadius ?? WATCH.ENTER_RADIUS) && d < bestDist) {
      best = sp;
      bestDist = d;
    }
  }
  if (!best) return { state: { id: null, heldSec: 0, cooldownSec: 0 }, target: null, twitched: false };
  return { state: { id: best.id, heldSec: 0, cooldownSec: 0 }, target: best, twitched: false };
}

// ============================================================================
// V6/F2 — Humming micro-idle schedule (happy + idle at home → a soft hum
// with 2–3 authored note particles). Pure: the caller supplies rand.
// ============================================================================

/** Hum tuning. */
export const HUM = Object.freeze({
  /** Delay range between hums while the happy idle holds. */
  DELAY_MIN_SEC: 20,
  DELAY_MAX_SEC: 36,
  /** The FIRST hum after turning happy comes sooner (delay × this). */
  FIRST_FRAC: 0.45,
  /** Note sprites per hum (gfx/particles.js 'notes' type). */
  NOTES_MIN: 2,
  NOTES_MAX: 3,
  /** One note per "beat" — spacing of the staggered emits. */
  NOTE_SPACING_SEC: 0.32,
  /** Emotions that count as "happy enough to hum" (§D2.5 mood bands). */
  MOODS: Object.freeze(['happy', 'ecstatic']),
});

/**
 * Whether the current emotion id is a humming mood (mood-band happy or
 * ecstatic — the §C1 moodEmotion output, incl. matching contexts).
 * @param {string} emotionId
 * @returns {boolean}
 */
export function isHummingMood(emotionId) {
  return HUM.MOODS.includes(emotionId);
}

/**
 * Seconds until the next hum. Deterministic given rand.
 * @param {() => number} rand 0..1 source (caller-seeded in tests)
 * @param {{first?: boolean}} [opts] first hum after turning happy → sooner
 * @returns {number}
 */
export function humDelaySec(rand, { first = false } = {}) {
  const base = HUM.DELAY_MIN_SEC + rand() * (HUM.DELAY_MAX_SEC - HUM.DELAY_MIN_SEC);
  return first ? base * HUM.FIRST_FRAC : base;
}

/**
 * Notes per hum: NOTES_MIN … NOTES_MAX inclusive.
 * @param {() => number} rand
 * @returns {number}
 */
export function humNoteCount(rand) {
  return HUM.NOTES_MIN + Math.floor(rand() * (HUM.NOTES_MAX - HUM.NOTES_MIN + 1));
}

// ============================================================================
// V6/F2 — Transient garden bird visitor (PLAN6 Wave F / F2). The MOVING
// counterpart to E4's static bench bird: occasionally flies in to the
// gardenFenceBird anchor, hops/pecks for 10–20 s, flies off. The schedule
// is a pure hash of the wall clock (weather.js hash32 recipe) — every
// player sees the same visit, NOTHING is saved. Gated by room/band/weather
// exactly like the AMBIENT_ROWS (the A3 row-gating pattern).
// ============================================================================

/** Visitor tuning (times in seconds, offsets in room-local meters). */
export const VISITOR = Object.freeze({
  /** Only the garden hosts the visitor. */
  ROOM: 'garden',
  /** Daytime only (mirrors the garden butterfly gate). */
  BANDS: Object.freeze(['dawn', 'day']),
  /** Never during rain. */
  WEATHER: DRY,
  /** rooms/garden.js perch anchor (E4 contract — fence gate's LEFT post). */
  ANCHOR: 'gardenFenceBird',
  /** Scheduling cycle: at most one visit per cycle. */
  CYCLE_SEC: 180,
  /** Chance a given cycle hosts a visit (hash-rolled per cycle index). */
  VISIT_CHANCE: 0.6,
  /** Flight envelope. */
  FLY_IN_SEC: 2.4,
  FLY_OUT_SEC: 2.2,
  /** Perch dwell (hop/peck) range. */
  STAY_MIN_SEC: 10,
  STAY_MAX_SEC: 20,
  /** Hop cadence/height while perched. */
  HOP_PERIOD_SEC: 1.7,
  HOP_FRAC: 0.3,
  HOP_HEIGHT: 0.055,
  /** Perch shuffle bound (per-hop deterministic sidestep, ±half). */
  SHUFFLE_RANGE: 0.14,
  /** Peck cadence: one head-dip per period, in the first PECK_FRAC of it. */
  PECK_PERIOD_SEC: 4.3,
  PECK_FRAC: 0.22,
  PECK_PITCH: 0.55,
  /** Flight entry/exit offset from the perch (x mirrored by visit side). */
  ENTRY_OFFSET: Object.freeze([2.6, 1.5, 0.9]),
  /** The visitor is worth a longer look than a flowerbed butterfly. */
  WATCH_ENTER_RADIUS: 4.2,
  WATCH_EXIT_RADIUS: 4.8,
  /** Transient draw-call allowance (PLAN6 F2: the bird adds ≤2 calls). */
  MAX_DRAW_CALLS: 2,
});

/**
 * @typedef {Object} VisitSpec
 * @property {number} cycle    scheduling cycle index (ms / CYCLE_SEC)
 * @property {number} startMs  epoch ms the fly-in starts
 * @property {number} endMs    epoch ms the fly-out finishes
 * @property {number} staySec  perch dwell for THIS visit (10–20 s)
 * @property {number} totalSec fly-in + stay + fly-out
 * @property {-1|1}   side     which side of the garden the bird arrives from
 * @property {number} seed     0..1 per-visit flavor hash (shuffle/gaze)
 */

/**
 * The visit a scheduling cycle hosts, or null for a quiet cycle. Pure hash
 * of the cycle index (`bird:*` keys through the committed hash32 recipe) —
 * no state, no save writes, stable across reloads/devices.
 * @param {number} cycle
 * @returns {VisitSpec|null}
 */
export function visitorCycleSpec(cycle) {
  const c = Math.floor(Number(cycle));
  if (!Number.isFinite(c) || c < 0) return null;
  if (hash32(`bird:${c}`) >= VISITOR.VISIT_CHANCE) return null;
  const staySec = VISITOR.STAY_MIN_SEC
    + hash32(`bird-stay:${c}`) * (VISITOR.STAY_MAX_SEC - VISITOR.STAY_MIN_SEC);
  const totalSec = VISITOR.FLY_IN_SEC + staySec + VISITOR.FLY_OUT_SEC;
  const slackSec = VISITOR.CYCLE_SEC - totalSec; // always > 0 (locked by test)
  const startSec = c * VISITOR.CYCLE_SEC + hash32(`bird-at:${c}`) * slackSec;
  return {
    cycle: c,
    startMs: startSec * 1000,
    endMs: (startSec + totalSec) * 1000,
    staySec,
    totalSec,
    side: hash32(`bird-side:${c}`) < 0.5 ? -1 : 1,
    seed: hash32(`bird-seed:${c}`),
  };
}

/**
 * The visit in progress at a timestamp, or null. Stateless: arbitrary
 * clock jumps (hidden tabs, ?now= pins, ?fast=) resolve instantly with no
 * catch-up work.
 * @param {number} ms epoch milliseconds (callers pass clock.now())
 * @returns {VisitSpec|null}
 */
export function visitAt(ms) {
  const t = Number(ms);
  if (!Number.isFinite(t) || t < 0) return null;
  const spec = visitorCycleSpec(Math.floor(t / (VISITOR.CYCLE_SEC * 1000)));
  if (!spec || t < spec.startMs || t >= spec.endMs) return null;
  return spec;
}

/**
 * Pure room/band/weather gate — the A3 row-gating pattern applied to the
 * visitor (garden + dawn/day + dry only).
 * @param {string} roomId @param {string} band @param {string} weather
 * @returns {boolean}
 */
export function visitorGate(roomId, band, weather) {
  return roomId === VISITOR.ROOM
    && VISITOR.BANDS.includes(band)
    && VISITOR.WEATHER.includes(weather);
}

/**
 * Gate + schedule in one read — what the mount side polls every frame.
 * @param {string} roomId @param {string} band @param {string} weather
 * @param {number} ms
 * @returns {VisitSpec|null}
 */
export function activeVisit(roomId, band, weather, ms) {
  return visitorGate(roomId, band, weather) ? visitAt(ms) : null;
}

/**
 * Phase of a visit at a timestamp: fly-'in' → 'stay' → fly-'out'.
 * @param {VisitSpec} visit
 * @param {number} ms
 * @returns {{phase: 'in'|'stay'|'out', u: number, tSec: number}} u ∈ [0,1]
 */
export function visitPhase(visit, ms) {
  const tSec = Math.min(visit.totalSec, Math.max(0, (Number(ms) - visit.startMs) / 1000));
  if (tSec < VISITOR.FLY_IN_SEC) {
    return { phase: 'in', u: tSec / VISITOR.FLY_IN_SEC, tSec };
  }
  if (tSec < VISITOR.FLY_IN_SEC + visit.staySec) {
    return { phase: 'stay', u: (tSec - VISITOR.FLY_IN_SEC) / visit.staySec, tSec };
  }
  return {
    phase: 'out',
    u: Math.min(1, (tSec - VISITOR.FLY_IN_SEC - visit.staySec) / VISITOR.FLY_OUT_SEC),
    tSec,
  };
}

/** Quadratic bezier + derivative (scalar, per-axis). */
const bez = (a, c, b, u) => (1 - u) * (1 - u) * a + 2 * (1 - u) * u * c + u * u * b;
const bezD = (a, c, b, u) => 2 * (1 - u) * (c - a) + 2 * u * (b - c);
const easeOutQuad = (u) => 1 - (1 - u) * (1 - u);
const easeInQuad = (u) => u * u;

/** Per-hop deterministic perch sidestep (±SHUFFLE_RANGE/2, seed-flavored). */
function shuffleAt(visit, hopIdx) {
  return (fract01(visit.cycle * 13.7 + visit.seed * 91 + hopIdx * 1.61) - 0.5)
    * VISITOR.SHUFFLE_RANGE;
}

/**
 * Full visitor pose sampler — position (room-local meters), yaw (three.js
 * Y-rotation; the bird GLB faces +Z) and pitch (X-rotation; + = head down).
 * Pure and continuous inside each phase: bezier arcs in/out (with a touch
 * of flutter-bob on approach), hop + sidestep + peck on the perch.
 * @param {VisitSpec} visit
 * @param {number} ms epoch milliseconds
 * @param {number[]} perch room-local [x,y,z] of the gardenFenceBird anchor
 * @returns {{position: number[], yaw: number, pitch: number,
 *   phase: 'in'|'stay'|'out'}}
 */
export function visitorPose(visit, ms, perch) {
  const { phase, u, tSec } = visitPhase(visit, ms);
  const [px, py, pz] = perch;
  const [ox, oy, oz] = VISITOR.ENTRY_OFFSET;
  const side = visit.side;

  if (phase === 'in') {
    const e = easeOutQuad(u);
    const A = [px + side * ox, py + oy, pz + oz];
    const C = [px + side * ox * 0.42, py + oy * 0.72, pz + oz * 0.55];
    const position = [
      bez(A[0], C[0], px, e),
      bez(A[1], C[1], py, e) + Math.sin(u * Math.PI * 4) * 0.03 * (1 - e),
      bez(A[2], C[2], pz, e),
    ];
    const vx = bezD(A[0], C[0], px, e);
    const vy = bezD(A[1], C[1], py, e);
    const vz = bezD(A[2], C[2], pz, e);
    return {
      position,
      yaw: Math.atan2(vx, vz),
      pitch: Math.max(-0.45, Math.min(0.45, Math.atan2(-vy, Math.hypot(vx, vz)) * 0.6)),
      phase,
    };
  }

  if (phase === 'stay') {
    const tStay = tSec - VISITOR.FLY_IN_SEC;
    const hopIdx = Math.floor(tStay / VISITOR.HOP_PERIOD_SEC);
    const hp = (tStay % VISITOR.HOP_PERIOD_SEC) / VISITOR.HOP_PERIOD_SEC;
    const hopK = hp < VISITOR.HOP_FRAC ? hp / VISITOR.HOP_FRAC : 1;
    const hopY = hp < VISITOR.HOP_FRAC ? Math.sin(hopK * Math.PI) * VISITOR.HOP_HEIGHT : 0;
    // sidestep lands during the hop: previous spot → this hop's spot
    const xOff = shuffleAt(visit, hopIdx - 1)
      + (shuffleAt(visit, hopIdx) - shuffleAt(visit, hopIdx - 1)) * Math.min(1, hopK);
    // peck: one head dip per PECK_PERIOD, in its first PECK_FRAC
    const pk = (tStay % VISITOR.PECK_PERIOD_SEC) / VISITOR.PECK_PERIOD_SEC;
    const pitch = pk < VISITOR.PECK_FRAC
      ? Math.sin((pk / VISITOR.PECK_FRAC) * Math.PI) * VISITOR.PECK_PITCH
      : 0;
    // gaze wanders slowly; blends out of the landing yaw over the first 0.5 s
    const stayYaw = side * 0.3 + Math.sin(tStay * 0.37 + visit.seed * 6.1) * 0.35;
    const landYaw = Math.atan2(side * ox * -0.84, oz * -1.1); // fly-in end direction
    const blend = Math.min(1, tStay / 0.5);
    return {
      position: [px + xOff, py + hopY, pz + pitch * 0.02],
      yaw: landYaw + (stayYaw - landYaw) * blend,
      pitch,
      phase,
    };
  }

  // fly out — off to the OPPOSITE side, climbing
  const e = easeInQuad(u);
  const B = [px - side * ox, py + oy * 1.15, pz + oz];
  const C2 = [px - side * ox * 0.35, py + oy * 0.55, pz + oz * 0.5];
  const position = [
    bez(px, C2[0], B[0], e),
    bez(py, C2[1], B[1], e),
    bez(pz, C2[2], B[2], e),
  ];
  const vx = bezD(px, C2[0], B[0], e);
  const vy = bezD(py, C2[1], B[1], e);
  const vz = bezD(pz, C2[2], B[2], e);
  return {
    position,
    yaw: Math.atan2(vx, vz),
    pitch: Math.max(-0.45, Math.min(0.45, Math.atan2(-vy, Math.hypot(vx, vz)) * 0.6)),
    phase: 'out',
  };
}
