// Tea Party (Teestube) — pure pour/scoring logic (PLAN5 §V5.1, agent V5/G06).
// No three.js/DOM imports so `node --test` runs this headlessly (§B rule);
// the game module (teaParty.js) imports from here. Mechanic: a HOLD-to-pour
// precision game — cups slide in with a marked target band, holding pours
// tea, releasing inside the band scores (perfect +6 / good +3), releasing
// outside (or overflowing past the rim) spills. Every 3 perfects in a row
// pay a streak bonus. Coin row (§V5.1): divisor 4, min 4, max 26 —
// capScore 104, Schwer-Ziel 85, typical raw ≈ 70 → ~17c.

/** Binding §V5.1 numbers + G06 tuning (fill physics, cadence, bot). */
export const TEA = Object.freeze({
  /** Round length (s). */
  DURATION_SEC: 60,
  /** Fill speed while holding (cup fraction per second). */
  FILL_RATE: 0.5,
  /** Target band center is rolled inside this fraction range per cup. */
  BAND_CENTER_MIN: 0.55,
  BAND_CENTER_MAX: 0.85,
  /** Half-widths (cup fraction): outer "good" band and inner "perfect" zone. */
  BAND_HALF_W: 0.075,
  PERFECT_HALF_W: 0.028,
  /** Points per released cup. */
  PERFECT_PTS: 6,
  GOOD_PTS: 3,
  /** Every 3rd consecutive perfect pays a +2 streak bonus. */
  STREAK_EVERY: 3,
  STREAK_BONUS: 2,
  /** Cup swap animation time (s) — tightens across the round. */
  SERVE_SEC_START: 1.7,
  SERVE_SEC_END: 1.1,
  /** Fill level that counts as an overflow spill (cup fraction). */
  OVERFLOW_LEVEL: 1,
  /** V5 §G5 run flags. */
  ENDLESS: false,
  /** §G5.4 Endlos end-condition: 3 spilled/missed cups. */
  ENDLESS_MAX_SPILLS: 3,
  /** Autoplay release error (uniform ± cup fraction) — human-ish. */
  AUTOPLAY_AIM_ERR: 0.06,
});

/** V5 timed-arena mode rows (§G5.3 family: window/speed/duration). */
export const TEA_DIFFICULTY = Object.freeze({
  easy: Object.freeze({ fillMult: 0.8, bandMult: 1.25, durationMult: 1.2, serveMult: 1, botErr: 0.05 }),
  hard: Object.freeze({ fillMult: 1.2, bandMult: 0.8, durationMult: 1, serveMult: 0.85, botErr: 0.068 }),
  endless: Object.freeze({ fillMult: 1.2, bandMult: 0.8, durationMult: 1, serveMult: 0.85, botErr: 0.068 }),
});

/** Derive a frozen tune; normal returns the exact Mittel object (§G5.3). */
export function applyDifficulty(tune = TEA, mode = 'normal') {
  if (mode === 'normal' || !Object.hasOwn(TEA_DIFFICULTY, mode)) return tune;
  const row = TEA_DIFFICULTY[mode];
  return Object.freeze({
    ...tune,
    DURATION_SEC: tune.DURATION_SEC * row.durationMult,
    FILL_RATE: tune.FILL_RATE * row.fillMult,
    BAND_HALF_W: tune.BAND_HALF_W * row.bandMult,
    PERFECT_HALF_W: tune.PERFECT_HALF_W * row.bandMult,
    SERVE_SEC_START: tune.SERVE_SEC_START * row.serveMult,
    SERVE_SEC_END: tune.SERVE_SEC_END * row.serveMult,
    AUTOPLAY_AIM_ERR: row.botErr,
    ENDLESS: mode === 'endless',
  });
}

/**
 * Roll a fresh cup's target band (center inside the §TEA range).
 * @param {() => number} rng 0..1
 * @param {object} [tune]
 * @returns {{center: number, half: number, perfectHalf: number}}
 */
export function rollBand(rng, tune = TEA) {
  const center = tune.BAND_CENTER_MIN + rng() * (tune.BAND_CENTER_MAX - tune.BAND_CENTER_MIN);
  return { center, half: tune.BAND_HALF_W, perfectHalf: tune.PERFECT_HALF_W };
}

/**
 * Integrate the fill level while pouring (uncapped — overflow is detected
 * against OVERFLOW_LEVEL by the caller).
 * @param {number} level current fill (cup fraction)
 * @param {number} dt seconds of pouring
 * @param {object} [tune]
 * @returns {number}
 */
export function fillAfter(level, dt, tune = TEA) {
  return Math.max(0, level) + tune.FILL_RATE * Math.max(0, dt);
}

/**
 * Evaluate a released (or overflowed) cup against its band.
 * @param {number} level fill at release (cup fraction)
 * @param {{center: number, half: number, perfectHalf: number}} band
 * @param {object} [tune]
 * @returns {{result: 'perfect'|'good'|'miss', points: number, overflow: boolean}}
 */
export function pourResult(level, band, tune = TEA) {
  const overflow = level >= tune.OVERFLOW_LEVEL;
  const dist = Math.abs(level - band.center);
  if (!overflow && dist <= band.perfectHalf) {
    return { result: 'perfect', points: tune.PERFECT_PTS, overflow: false };
  }
  if (!overflow && dist <= band.half) {
    return { result: 'good', points: tune.GOOD_PTS, overflow: false };
  }
  return { result: 'miss', points: 0, overflow };
}

/**
 * Streak bonus for the n-th CONSECUTIVE perfect (every 3rd pays +2).
 * @param {number} streak consecutive perfects incl. this one
 * @param {object} [tune]
 * @returns {number} bonus points (0 when the streak is off-beat)
 */
export function streakBonusAt(streak, tune = TEA) {
  return streak > 0 && streak % tune.STREAK_EVERY === 0 ? tune.STREAK_BONUS : 0;
}

/**
 * Cup swap time at a moment of the round (cadence tightens linearly).
 * @param {number} elapsed seconds
 * @param {number} [duration]
 * @param {object} [tune]
 * @returns {number}
 */
export function serveIntervalAt(elapsed, duration = TEA.DURATION_SEC, tune = TEA) {
  const t = Math.min(1, Math.max(0, elapsed / duration));
  return tune.SERVE_SEC_START + (tune.SERVE_SEC_END - tune.SERVE_SEC_START) * t;
}

/**
 * Apply a delta to the score, floored at 0.
 * @param {number} score
 * @param {number} delta
 * @returns {number}
 */
export function applyScore(score, delta) {
  return Math.max(0, score + delta);
}

/** §G5.4 Endlos ends on the third spilled/missed cup. */
export function endlessShouldEnd(spills, tune = TEA) {
  return tune.ENDLESS === true && spills >= tune.ENDLESS_MAX_SPILLS;
}

/** Deterministic tune-driven certification for the shipped release bot. */
export function simulateTeaAutoplay(mode = 'normal', seed = 1) {
  const tune = applyDifficulty(TEA, mode);
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
  let cups = 0;
  let spills = 0;
  let streak = 0;
  const limit = tune.ENDLESS ? 600 : tune.DURATION_SEC;
  while (elapsed < limit && !endlessShouldEnd(spills, tune)) {
    const band = rollBand(rng, tune);
    // The bot aims at the band center and releases with a uniform error.
    const level = band.center + (rng() * 2 - 1) * tune.AUTOPLAY_AIM_ERR;
    const res = pourResult(level, band, tune);
    score = applyScore(score, res.points);
    if (res.result === 'perfect') {
      streak += 1;
      score = applyScore(score, streakBonusAt(streak, tune));
    } else {
      streak = 0;
      if (res.result === 'miss') spills += 1;
    }
    cups += 1;
    // Time cost: pour up to the released level, then the serve swap.
    elapsed += level / tune.FILL_RATE + serveIntervalAt(elapsed, tune.DURATION_SEC, tune);
  }
  return Object.freeze({ seed, mode, score, cups, spills, elapsed });
}
