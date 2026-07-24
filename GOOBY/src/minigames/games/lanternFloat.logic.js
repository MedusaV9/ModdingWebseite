// Star Lantern („Sternenlaterne") — pure rules (PLAN5 §3 / PLAN6 Wave C/C1,
// agent V6/C1). No three.js/DOM imports so `node --test` runs this headlessly
// (§B rule); the view module (lanternFloat.js) imports from here. Mechanic:
// a chill vertical drifter — a paper lantern auto-rises through the night sky
// over the garden while a horizontal drag steers it through star rings
// (+2, golden every 5th +5), past curious fireflies (+1), telegraphed wind
// gusts that push it sideways and soft cloud bumps (timed: −3 comfy penalty;
// Endlos: 3 bumps end the run). Coin row (frozen C1 contract): divisor 4,
// min 4, max 24 — capScore 96, Schwer-Ziel 75, typical raw ≈ 65 → ~16c.

/** Binding C1 contract numbers + V6 tuning (world, cadence, gusts, bot). */
export const LANTERN = Object.freeze({
  /** Round length (s). */
  DURATION_SEC: 60,
  /** Horizontal playfield half-width at the lantern plane (wu). */
  HALF_W: 3.1,
  /** Rings/clouds keep this margin from the playfield edge (wu). */
  RING_MARGIN: 0.45,
  /** Drag target over-reach so nx ±1 covers the full width (§G3.1-c rule). */
  STEER_OVERREACH: 1.25,
  /** Auto-rise speed (wu/s) — the world scrolls down past the lantern. */
  RISE_SPEED: 2.6,
  /** Vertical gap between consecutive star rings (wu) — cadence ramps. */
  RING_SPACING_START: 4.4,
  RING_SPACING_END: 3.4,
  /** Ring catch half-window (wu): |lanternX − ringX| ≤ radius scores. */
  RING_RADIUS: 0.56,
  /** Every Nth ring is golden. */
  GOLD_EVERY: 5,
  /** Points per passed ring / golden ring / collected firefly. */
  RING_PTS: 2,
  GOLD_PTS: 5,
  FIREFLY_PTS: 1,
  /** Chance of a firefly appearing in a ring gap; its catch radius (wu). */
  FIREFLY_CHANCE: 0.45,
  FIREFLY_RADIUS: 0.55,
  /** Gust schedule (s): first start, cadence, telegraph lead, push window. */
  GUST_FIRST_SEC: 7,
  GUST_EVERY_SEC: 9,
  GUST_TELEGRAPH_SEC: 1.1,
  GUST_DURATION_SEC: 1.4,
  /** Lateral push while a gust blows (wu/s). */
  GUST_FORCE: 1.9,
  /** Chance of a cloud in a ring gap (from CLOUD_MIN_INDEX on); half-width. */
  CLOUD_CHANCE: 0.22,
  CLOUD_MIN_INDEX: 3,
  CLOUD_HALF_W: 0.85,
  /** Cloud bump: comfy timed-mode penalty + invulnerability window (s). */
  BUMP_PENALTY: 3,
  BUMP_INVULN_SEC: 1.2,
  /** V6 §G5 run flags. */
  ENDLESS: false,
  /** §G5.4 Endlos end-condition: the 3rd cloud bump ends the run. */
  ENDLESS_MAX_BUMPS: 3,
  /** Certification-bot knobs (§G5.4 — exempt from the guardrail band). */
  AUTOPLAY_AIM_ERR: 0.9,
  AUTOPLAY_GUST_DRIFT: 0.35,
  AUTOPLAY_FIREFLY_RATE: 0.8,
  AUTOPLAY_BUMP_CHANCE: 0.18,
});

/**
 * V6 runner/steer mode rows (§G5.3 family — frozen C1 contract: Leicht =
 * ring radius ×1.25, rise ×0.8, +20 % time · Schwer = rings ×0.8, rise ×1.2 ·
 * Endlos = Schwer tuning + the 3-bump end). The bot error stays IDENTICAL
 * across modes so the difficulty direction is measurable under the same bot.
 */
export const LANTERN_DIFFICULTY = Object.freeze({
  easy: Object.freeze({ ringMult: 1.25, riseMult: 0.8, durationMult: 1.2 }),
  hard: Object.freeze({ ringMult: 0.8, riseMult: 1.2, durationMult: 1 }),
  endless: Object.freeze({ ringMult: 0.8, riseMult: 1.2, durationMult: 1 }),
});

/** Derive a frozen tune; normal/unknown returns the exact Mittel object (§G5.3). */
export function applyDifficulty(tune = LANTERN, mode = 'normal') {
  if (mode === 'normal' || !Object.hasOwn(LANTERN_DIFFICULTY, mode)) return tune;
  const row = LANTERN_DIFFICULTY[mode];
  return Object.freeze({
    ...tune,
    DURATION_SEC: tune.DURATION_SEC * row.durationMult,
    RISE_SPEED: tune.RISE_SPEED * row.riseMult,
    RING_RADIUS: tune.RING_RADIUS * row.ringMult,
    ENDLESS: mode === 'endless',
  });
}

/**
 * THE steer mapping — the ONE input boundary (§G2.1 rule 1 / §G3.1-c,
 * harborHopper dragX pattern). The lantern camera sits at +z looking at the
 * origin, so world +x renders SCREEN RIGHT — the screen-true mapping needs
 * no chirality flip here (harborHopper's chase cam looks down +z and does).
 * The framework's §G3.3 invert proxy negates p.nx BEFORE this boundary, so
 * the global „Steuerung invertieren" toggle mirrors exactly once.
 * @param {number} nx normalized drag x (−1..1, possibly framework-inverted)
 * @param {object} [tune]
 * @returns {number} steer target in world x (over-reached for full range)
 */
export function steerTargetFrom(nx, tune = LANTERN) {
  const n = Math.max(-1, Math.min(1, Number(nx) || 0));
  return n * tune.HALF_W * tune.STEER_OVERREACH;
}

/** Clamp a lantern x into the playfield. */
export function clampLanternX(x, tune = LANTERN) {
  return Math.max(-tune.HALF_W, Math.min(tune.HALF_W, x));
}

/**
 * Ring spacing at a moment of the round (cadence tightens linearly over the
 * tune's own duration; endless keeps the end value past the ramp).
 * @param {number} elapsed seconds
 * @param {object} [tune]
 * @returns {number} wu to the next ring
 */
export function ringSpacingAt(elapsed, tune = LANTERN) {
  const t = Math.min(1, Math.max(0, elapsed / tune.DURATION_SEC));
  return tune.RING_SPACING_START + (tune.RING_SPACING_END - tune.RING_SPACING_START) * t;
}

/**
 * Roll the n-th star ring: lateral center inside the margins, golden every
 * GOLD_EVERY-th (deterministic cadence — the golden beat is learnable).
 * @param {() => number} rng 0..1
 * @param {number} index 0-based ring index
 * @param {object} [tune]
 * @returns {{index: number, x: number, gold: boolean, points: number}}
 */
export function rollRing(rng, index, tune = LANTERN) {
  const x = (rng() * 2 - 1) * (tune.HALF_W - tune.RING_MARGIN);
  const gold = (index + 1) % tune.GOLD_EVERY === 0;
  return Object.freeze({ index, x, gold, points: gold ? tune.GOLD_PTS : tune.RING_PTS });
}

/**
 * Did the lantern fly through a ring? Pure lateral overlap window.
 * @param {number} lanternX
 * @param {{x: number}} ring
 * @param {object} [tune]
 * @returns {boolean}
 */
export function ringHit(lanternX, ring, tune = LANTERN) {
  return Math.abs(lanternX - ring.x) <= tune.RING_RADIUS;
}

/**
 * The n-th wind gust of a run — a fully deterministic schedule row (start,
 * telegraph→push windows, push direction from an integer hash) shared by the
 * view and the certification sim.
 * @param {number} index 0-based gust index
 * @param {object} [tune]
 * @returns {{index: number, startSec: number, pushSec: number, endSec: number, dir: 1|-1}}
 */
export function gustAt(index, tune = LANTERN) {
  const startSec = tune.GUST_FIRST_SEC + index * tune.GUST_EVERY_SEC;
  const pushSec = startSec + tune.GUST_TELEGRAPH_SEC;
  const h = Math.imul(index + 1, 2654435761) >>> 0;
  return Object.freeze({
    index,
    startSec,
    pushSec,
    endSec: pushSec + tune.GUST_DURATION_SEC,
    dir: (h & 2) === 0 ? 1 : -1,
  });
}

/**
 * Which gust matters at a moment, and which phase it is in.
 * Phases: 'idle' (before the telegraph) · 'telegraph' (leaves drift in,
 * warning) · 'push' (the lantern is shoved sideways).
 * @param {number} elapsed seconds
 * @param {object} [tune]
 * @returns {{gust: ReturnType<typeof gustAt>, phase: 'idle'|'telegraph'|'push'}}
 */
export function gustPhaseAt(elapsed, tune = LANTERN) {
  const idx = Math.max(0, Math.floor((elapsed - tune.GUST_FIRST_SEC) / tune.GUST_EVERY_SEC));
  let gust = gustAt(idx, tune);
  if (elapsed >= gust.endSec) gust = gustAt(idx + 1, tune);
  const phase = elapsed < gust.startSec ? 'idle'
    : elapsed < gust.pushSec ? 'telegraph'
      : elapsed < gust.endSec ? 'push' : 'idle';
  return { gust, phase };
}

/**
 * Roll the cloud slot of the n-th ring gap. Always consumes exactly TWO rng
 * draws (presence + x) so a caller's stream stays aligned either way.
 * @param {() => number} rng 0..1
 * @param {number} index 0-based ring-gap index
 * @param {object} [tune]
 * @returns {{present: boolean, x: number}}
 */
export function rollCloud(rng, index, tune = LANTERN) {
  const present = rng() < tune.CLOUD_CHANCE && index >= tune.CLOUD_MIN_INDEX;
  const x = (rng() * 2 - 1) * (tune.HALF_W - tune.RING_MARGIN);
  return Object.freeze({ present, x });
}

/** Lateral cloud overlap — a bump when the lantern drifts into the puff. */
export function cloudHit(lanternX, cloud, tune = LANTERN) {
  return Math.abs(lanternX - cloud.x) <= tune.CLOUD_HALF_W;
}

/**
 * Apply a delta to the score, floored at 0 (bumps never go negative — comfy).
 * @param {number} score
 * @param {number} delta
 * @returns {number}
 */
export function applyScore(score, delta) {
  return Math.max(0, score + delta);
}

/** §G5.4 Endlos ends on the third cloud bump. */
export function endlessShouldEnd(bumps, tune = LANTERN) {
  return tune.ENDLESS === true && bumps >= tune.ENDLESS_MAX_BUMPS;
}

/**
 * Deterministic tune-driven certification bot ('ms' adapter signature —
 * §G5.4). Event-per-ring simulation: the bot aims at each ring center with
 * a uniform error, drifts extra while a gust pushes, collects most fireflies
 * and dodges most clouds. Same seed + mode → identical frozen result.
 * @param {'easy'|'normal'|'hard'|'endless'} [mode]
 * @param {number} [seed]
 */
export function simulateLanternAutoplay(mode = 'normal', seed = 1) {
  const tune = applyDifficulty(LANTERN, mode);
  let a = seed >>> 0;
  const rng = () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let x = Math.imul(a ^ (a >>> 15), 1 | a);
    x = (x + Math.imul(x ^ (x >>> 7), 61 | x)) | 0;
    return ((x ^ (x >>> 14)) >>> 0) / 4294967296;
  };
  let elapsed = 0;
  let score = 0;
  let hits = 0;
  let golds = 0;
  let fireflies = 0;
  let bumps = 0;
  let index = 0;
  const limit = tune.ENDLESS ? 600 : tune.DURATION_SEC;
  while (!endlessShouldEnd(bumps, tune)) {
    elapsed += ringSpacingAt(elapsed, tune) / tune.RISE_SPEED;
    if (elapsed >= limit) break;
    const ring = rollRing(rng, index, tune);
    const { gust, phase } = gustPhaseAt(elapsed, tune);
    const drift = phase === 'push' ? gust.dir * tune.AUTOPLAY_GUST_DRIFT : 0;
    const aim = ring.x + (rng() * 2 - 1) * tune.AUTOPLAY_AIM_ERR + drift;
    if (ringHit(clampLanternX(aim, tune), ring, tune)) {
      hits += 1;
      if (ring.gold) golds += 1;
      score = applyScore(score, ring.points);
    }
    if (rng() < tune.FIREFLY_CHANCE && rng() < tune.AUTOPLAY_FIREFLY_RATE) {
      fireflies += 1;
      score = applyScore(score, tune.FIREFLY_PTS);
    }
    const cloud = rollCloud(rng, index, tune);
    if (cloud.present && rng() < tune.AUTOPLAY_BUMP_CHANCE) {
      bumps += 1;
      if (!tune.ENDLESS) score = applyScore(score, -tune.BUMP_PENALTY);
    }
    index += 1;
  }
  return Object.freeze({ seed, mode, score, rings: index, hits, golds, fireflies, bumps, elapsed });
}
