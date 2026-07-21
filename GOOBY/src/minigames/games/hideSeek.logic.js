// Hide & Seek (Guck-guck-Garten) — pure wave/peek/scoring logic (PLAN5
// §V5.2, agent V5/G06). No three.js/DOM imports so `node --test` runs this
// headlessly (§B rule); the game module (hideSeek.js) imports from here.
// Mechanic: a cozy observation game — critters hide behind a 3×4 grid of
// bushes/crates/pots and periodically PEEK out; tap the right hiding spot to
// find them (+2). Clearing a whole wave before its timer pays a +3 bonus;
// expired waves simply re-hide (timed) or count toward the Endlos end (3).
// Coin row (§V5.2): divisor 5, min 4, max 20 — capScore 100, Schwer-Ziel 80,
// typical raw ≈ 70 → ~14c.

/** Binding §V5.2 numbers + G06 tuning (grid, waves, peek cadence, bot). */
export const SEEK = Object.freeze({
  /** Round length (s). */
  DURATION_SEC: 60,
  /** Hiding-spot grid (portrait): 3 columns × 4 rows. */
  COLS: 3,
  ROWS: 4,
  /** Hiders per wave ramp start → max across WAVE_RAMP_WAVES. */
  WAVE_HIDERS_START: 3,
  WAVE_HIDERS_MAX: 5,
  WAVE_RAMP_WAVES: 4,
  /** Points per found critter and per fully cleared wave. */
  FIND_PTS: 2,
  WAVE_BONUS: 3,
  /** Wave timer ramp start → end across WAVE_RAMP_WAVES (s). */
  WAVE_SEC_START: 13,
  WAVE_SEC_END: 9,
  /** Serve gap between waves (re-hide shuffle animation, s). */
  SERVE_SEC: 1,
  /** Each hidden critter peeks out periodically (s). */
  PEEK_EVERY_SEC: 2.4,
  PEEK_DURATION_SEC: 0.75,
  /** V5 §G5 run flags. */
  ENDLESS: false,
  /** §G5.4 Endlos end-condition: 3 expired (uncleared) waves. */
  ENDLESS_MAX_EXPIRED: 3,
  /** Autoplay: taps every TAP_SEC; each tap finds a hider with FIND_RATE. */
  AUTOPLAY_TAP_SEC: 1.2,
  AUTOPLAY_FIND_RATE: 0.9,
});

/** V5 timed-arena mode rows (§G5.3 family: window/cadence/duration). */
export const SEEK_DIFFICULTY = Object.freeze({
  easy: Object.freeze({ waveSecMult: 1.25, peekDurMult: 1.3, peekEveryMult: 1, durationMult: 1.2, botRate: 0.97 }),
  hard: Object.freeze({ waveSecMult: 0.8, peekDurMult: 0.8, peekEveryMult: 1.25, durationMult: 1, botRate: 0.82 }),
  endless: Object.freeze({ waveSecMult: 0.8, peekDurMult: 0.8, peekEveryMult: 1.25, durationMult: 1, botRate: 0.82 }),
});

/** Derive a frozen tune; normal returns the exact Mittel object (§G5.3). */
export function applyDifficulty(tune = SEEK, mode = 'normal') {
  if (mode === 'normal' || !Object.hasOwn(SEEK_DIFFICULTY, mode)) return tune;
  const row = SEEK_DIFFICULTY[mode];
  return Object.freeze({
    ...tune,
    DURATION_SEC: tune.DURATION_SEC * row.durationMult,
    WAVE_SEC_START: tune.WAVE_SEC_START * row.waveSecMult,
    WAVE_SEC_END: tune.WAVE_SEC_END * row.waveSecMult,
    PEEK_DURATION_SEC: tune.PEEK_DURATION_SEC * row.peekDurMult,
    PEEK_EVERY_SEC: tune.PEEK_EVERY_SEC * row.peekEveryMult,
    AUTOPLAY_FIND_RATE: row.botRate,
    ENDLESS: mode === 'endless',
  });
}

/** Total hiding spots on the grid. */
export function spotCount(tune = SEEK) {
  return tune.COLS * tune.ROWS;
}

/**
 * Hiders for the 0-based wave index (ramps start → max, then stays).
 * @param {number} wave
 * @param {object} [tune]
 * @returns {number}
 */
export function hidersForWave(wave, tune = SEEK) {
  const t = Math.min(1, Math.max(0, wave / tune.WAVE_RAMP_WAVES));
  return Math.round(tune.WAVE_HIDERS_START + (tune.WAVE_HIDERS_MAX - tune.WAVE_HIDERS_START) * t);
}

/**
 * Wave timer for the 0-based wave index (ramps start → end, then stays).
 * @param {number} wave
 * @param {object} [tune]
 * @returns {number} seconds
 */
export function waveSecFor(wave, tune = SEEK) {
  const t = Math.min(1, Math.max(0, wave / tune.WAVE_RAMP_WAVES));
  return tune.WAVE_SEC_START + (tune.WAVE_SEC_END - tune.WAVE_SEC_START) * t;
}

/**
 * Roll the hidden spot indices for a wave: unique, uniform over the grid.
 * @param {() => number} rng 0..1
 * @param {number} wave 0-based wave index
 * @param {object} [tune]
 * @returns {number[]} spot indices (0..spotCount-1), ascending
 */
export function rollHiders(rng, wave, tune = SEEK) {
  const n = Math.min(hidersForWave(wave, tune), spotCount(tune));
  const pool = Array.from({ length: spotCount(tune) }, (_, i) => i);
  // Partial Fisher–Yates: draw n unique spots deterministically from rng.
  for (let i = 0; i < n; i += 1) {
    const j = i + Math.floor(rng() * (pool.length - i));
    [pool[i], pool[j]] = [pool[j], pool[i]];
  }
  return pool.slice(0, n).sort((x, y) => x - y);
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

/** §G5.4 Endlos ends on the third expired (uncleared) wave. */
export function endlessShouldEnd(expired, tune = SEEK) {
  return tune.ENDLESS === true && expired >= tune.ENDLESS_MAX_EXPIRED;
}

/** Deterministic tune-driven certification for the shipped seeker bot. */
export function simulateSeekAutoplay(mode = 'normal', seed = 1) {
  const tune = applyDifficulty(SEEK, mode);
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
  let wave = 0;
  let expired = 0;
  let found = 0;
  const limit = tune.ENDLESS ? 600 : tune.DURATION_SEC;
  while (elapsed < limit && !endlessShouldEnd(expired, tune)) {
    let left = rollHiders(rng, wave, tune).length;
    const waveSec = waveSecFor(wave, tune);
    let waveT = 0;
    while (left > 0 && waveT < waveSec && elapsed + waveT < limit) {
      waveT += tune.AUTOPLAY_TAP_SEC;
      if (rng() < tune.AUTOPLAY_FIND_RATE) {
        left -= 1;
        found += 1;
        score = applyScore(score, tune.FIND_PTS);
      }
    }
    if (left === 0) {
      score = applyScore(score, tune.WAVE_BONUS);
    } else if (waveT >= waveSec) {
      expired += 1;
    }
    elapsed += waveT + tune.SERVE_SEC;
    wave += 1;
  }
  return Object.freeze({ seed, mode, score, waves: wave, found, expired, elapsed });
}
