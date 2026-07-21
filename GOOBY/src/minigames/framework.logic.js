// V4/G56 — framework 2.0 pure logic (PLAN4-GAMES §G5, PLAN4 §C-SYS7.1,
// §E0.1-2): difficulty/endless launch validation, the §G5.2 coin-multiplier
// math (fallback shim + assertion oracle — economy.awardMinigame is the ONE
// runtime payout site once G54's v4 economy lands), the sick-gate predicate
// and defensive readers for G53's §G5.5 save slice. PURE module: no three.js/
// DOM imports — node:test hits this file directly.

import { isSurfTravel } from '../systems/shopTrip.js';

/** §G5.2 — the four modes. `normal` is the default (live numbers). */
export const DIFFICULTY_MODES = Object.freeze(['easy', 'normal', 'hard', 'endless']);

/**
 * §G5.2 coin multipliers (frozen here per §E0.1-2 owning-module rule; G54's
 * economy implements the SAME numbers at the single payout site — this table
 * is the shared oracle for tests and the pre-G54 fallback shim).
 */
export const DIFFICULTY_COIN_MULT = Object.freeze({ easy: 0.7, normal: 1, hard: 1.3 });

/** §G5.2 — Endlos pays a flat 5 c per run (daily ×2 still applies after). */
export const ENDLESS_FLAT_COINS = 5;

/** §G5.5 — ENDLOS pill needs `beaten[id].hard` AND level ≥ 10. */
export const ENDLESS_MIN_LEVEL = 10;

/**
 * §G5.1 exclusions: cityDrive rides trip/§C4 semantics (single difficulty),
 * goobyWelt is the §G6 chill special. Trips are excluded by mode (see
 * effectiveDifficulty); dev games (`_smoke`) by meta.dev.
 */
export const DIFFICULTY_EXCLUDED_GAMES = Object.freeze(['cityDrive', 'goobyWelt']);

/**
 * Normalize a requested difficulty to a known mode id.
 * @param {*} mode
 * @returns {'easy'|'normal'|'hard'|'endless'}
 */
export function normalizeDifficulty(mode) {
  return DIFFICULTY_MODES.includes(mode) ? mode : 'normal';
}

/**
 * Is the difficulty system enabled for this game at all (§G5.1)?
 * @param {string} gameId
 * @param {{dev?: boolean}|undefined} [meta] data/minigames.js row
 * @returns {boolean}
 */
export function difficultyEnabled(gameId, meta) {
  if (DIFFICULTY_EXCLUDED_GAMES.includes(gameId)) return false;
  if (meta?.dev === true) return false;
  return true;
}

/**
 * The difficulty a launch actually runs at (§G5.1/§G5.7-1): trip/travel
 * launches (shopTrip drive, vet drive, surf „Laufen") and excluded games are
 * always 'normal'; everything else normalizes `params.difficulty`.
 * @param {string} gameId
 * @param {{difficulty?: string, mode?: string}} [params] framework launch params
 * @param {{dev?: boolean}|undefined} [meta]
 * @returns {'easy'|'normal'|'hard'|'endless'}
 */
export function effectiveDifficulty(gameId, params = {}, meta) {
  if (params.mode != null) return 'normal'; // trips/travel never take difficulty
  if (!difficultyEnabled(gameId, meta)) return 'normal';
  return normalizeDifficulty(params.difficulty);
}

/**
 * §E0.1-2 / §G5.2 base-coin math (BEFORE the daily ×2 / code buff / doppelGold
 * steps — those stay economy-side): `base = min(row.max, max(row.min,
 * round(rowClamp(score) × difficultyMult)))`. The row-min floor is §G5.2's
 * Leicht rule („floor: row min"); ×1 reproduces rowClamp bit-identically.
 * Endless does NOT use this (flat ENDLESS_FLAT_COINS override).
 * @param {{divisor?: number, min?: number, max: number}} coinTable §C6 row
 * @param {number} score final round score
 * @param {'easy'|'normal'|'hard'} mode
 * @returns {number} integer base coins
 */
export function applyDifficultyCoinBase(coinTable, score, mode) {
  const s = Math.max(0, Math.floor(Number(score) || 0));
  const rowClamp = Math.min(
    coinTable.max,
    Math.max(coinTable.min ?? 0, Math.floor(s / (coinTable.divisor ?? 1)))
  );
  const mult = DIFFICULTY_COIN_MULT[mode] ?? 1;
  return Math.min(coinTable.max, Math.max(coinTable.min ?? 0, Math.round(rowClamp * mult)));
}

/**
 * §C-SYS7.1 sick gate (the one-line class change): while sick, BOTH shop
 * travel methods (drive `shopTrip` AND Shopping Surf `surfTravel`/`travel`)
 * plus the vet drive may launch; pure arcade launches stay blocked with
 * `toast.tooSick`.
 * @param {string|undefined} mode framework launch `params.mode`
 * @returns {boolean} true when the launch is allowed while sick
 */
export function allowsWhileSick(mode) {
  return mode === 'vetTrip' || mode === 'shopTrip' || isSurfTravel(mode);
}

/**
 * Defensive §G5.5 slice reader (G53 lands the save-v4 shape in the same wave
 * — every field falls back to the empty default until then, and hostile /
 * missing containers can never throw).
 * @param {object} state full save state (or any {minigames, level} shape)
 * @param {string} gameId
 * @returns {{selected: 'easy'|'normal'|'hard', beaten: {easy?: boolean,
 *   normal?: boolean, hard?: boolean}, bestByDiff: {easy?: number,
 *   hard?: number}, best: number, endlessBest: number}}
 */
export function difficultySliceOf(state, gameId) {
  const mg = state?.minigames ?? {};
  const selRaw = mg.difficulty?.[gameId];
  const selected = selRaw === 'easy' || selRaw === 'hard' ? selRaw : 'normal';
  const beatenRow = mg.beaten?.[gameId];
  const beaten = beatenRow && typeof beatenRow === 'object' ? beatenRow : {};
  const bbdRow = mg.bestByDiff?.[gameId];
  const bestByDiff = bbdRow && typeof bbdRow === 'object' ? bbdRow : {};
  return {
    selected,
    beaten,
    bestByDiff,
    best: Math.max(0, Math.floor(Number(mg.best?.[gameId]) || 0)),
    endlessBest: Math.max(0, Math.floor(Number(mg.endlessBest?.[gameId]) || 0)),
  };
}

/**
 * §G5.5 endless lock: enabled iff `beaten[id].hard === true` AND level ≥ 10.
 * Defensive against the missing v4 slice (locked by default).
 * @param {object} state full save state
 * @param {string} gameId
 * @returns {boolean}
 */
export function endlessUnlocked(state, gameId) {
  const level = Math.max(1, Math.floor(Number(state?.level) || 1));
  return difficultySliceOf(state, gameId).beaten.hard === true && level >= ENDLESS_MIN_LEVEL;
}

/**
 * Per-mode best for the results/pre-game boards (§G5.5: `best` stays the
 * Mittel board; Leicht/Schwer live in `bestByDiff`, Endlos in `endlessBest`).
 * @param {object} state full save state
 * @param {string} gameId
 * @param {'easy'|'normal'|'hard'|'endless'} mode
 * @returns {number}
 */
export function bestForMode(state, gameId, mode) {
  const slice = difficultySliceOf(state, gameId);
  if (mode === 'endless') return slice.endlessBest;
  if (mode === 'easy' || mode === 'hard') {
    return Math.max(0, Math.floor(Number(slice.bestByDiff[mode]) || 0));
  }
  return slice.best;
}

// ════════════════════════════════════════════════════════════════ POLISH-E ═
// Shared 3-strikes → teleport-to-loading + landscape-mode helpers. PURE
// (node-tested in test/framework2.test.js); the DOM/cutscene side lives in
// framework.js. Frozen consts stay here per the §E0.1-2 owning-module rule.

/**
 * POLISH-E: strikes before the framework teleports the player out — mirrors
 * cityDrive's `DRIVE.CRASHES_FOR_TOW: 3` (the „towed after 3 crashes" rule
 * the shared API generalizes; framework2.test.js pins the mirror).
 */
export const STRIKES_FOR_TELEPORT = 3;

/**
 * POLISH-E: the pure strike decision — increment the per-run counter and
 * answer „does THIS strike trigger the teleport?". Defensive against
 * hostile counters (non-numeric/negative → treated as 0). `teleport` turns
 * true ON the strike that reaches the limit and stays true past it —
 * framework.js guards re-entry while the cutscene runs, so the cutscene
 * still starts exactly once.
 * @param {number} strikes strikes recorded so far this run
 * @returns {{strikes: number, teleport: boolean}} the updated counter +
 *   whether the teleport cutscene starts now
 */
export function applyStrike(strikes) {
  const n = Math.max(0, Math.floor(Number(strikes) || 0)) + 1;
  return { strikes: n, teleport: n >= STRIKES_FOR_TELEPORT };
}

/**
 * POLISH-E: normalize a game module's optional `export const orientation`
 * (read via the framework's namespace glob, like G57's `controls`) to a
 * known value. Anything but the literal 'landscape' means portrait — the
 * CSS baseline (390×844) every game was built against.
 * @param {*} value the module-level export (usually undefined)
 * @returns {'portrait'|'landscape'}
 */
export function normalizeOrientation(value) {
  return value === 'landscape' ? 'landscape' : 'portrait';
}

/**
 * POLISH-E: should the „Bitte dreh dein Handy" gate show before the
 * countdown? Only landscape-flagged games gate, and only while the viewport
 * is still portrait (a square viewport counts as portrait — the game wants
 * width). `forced` (dev `?rotategate=1`) shows it regardless so the overlay
 * can be previewed on landscape-locked environments (VM/desktop).
 * @param {'portrait'|'landscape'} orientation the game's declared orientation
 * @param {number} viewportW css px
 * @param {number} viewportH css px
 * @param {boolean} [forced] dev-harness override
 * @returns {boolean}
 */
export function needsRotateGate(orientation, viewportW, viewportH, forced = false) {
  if (orientation !== 'landscape') return false;
  if (forced) return true;
  const w = Number(viewportW) || 0;
  const h = Number(viewportH) || 0;
  return shouldShowRotateGate(orientation, w > h);
}
// ════════════════════════════════════════════════════════════ end POLISH-E ═

// ═══════════════════════════════════════════════════════════════ V4/ORIENT ═
// Rotation is allowed ONLY while a LANDSCAPE-flagged minigame is active. The
// app-wide baseline is PORTRAIT (home, menus, every screen, portrait games) —
// iOS' Info.plist lists landscapeLeft/Right solely so a landscape game's
// viewport CAN rotate mid-round. These pure helpers make the policy testable;
// framework.js owns the DOM side (rotate overlay + best-effort lock/unlock).

/**
 * V4/ORIENT: a game module's effective orientation — its module-level
 * `export const orientation` normalized. Absent/unknown exports (the vast
 * majority of games) mean portrait, the CSS baseline every game targets.
 * @param {{orientation?: *}|null|undefined} gameModule module namespace object
 * @returns {'portrait'|'landscape'}
 */
export function orientationForGame(gameModule) {
  return normalizeOrientation(gameModule?.orientation);
}

/**
 * V4/ORIENT: THE gate decision (needsRotateGate's viewport branch delegates
 * here so the two can never drift): show the „Bitte dreh dein Handy" overlay
 * ONLY for a landscape-flagged game while the viewport is NOT yet landscape.
 * Portrait games NEVER gate — whatever the viewport reports.
 * @param {*} orientationFlag the game's declared orientation export
 * @param {boolean} viewportIsLandscape `w > h` (square counts as portrait)
 * @returns {boolean}
 */
export function shouldShowRotateGate(orientationFlag, viewportIsLandscape) {
  if (normalizeOrientation(orientationFlag) !== 'landscape') return false;
  return viewportIsLandscape !== true;
}

/**
 * V4/ORIENT: which Screen-Orientation state the framework applies for a run.
 * Landscape games UNLOCK rotation for their round (the OS may rotate; the
 * gate prompts for it) — everything else (re-)locks portrait. exit() always
 * returns 'portrait': quitting/results/teleport restore the app baseline.
 * @param {*} gameOrientation the game's declared orientation
 * @returns {'portrait'|'unlock'}
 */
export function orientationLockFor(gameOrientation) {
  return normalizeOrientation(gameOrientation) === 'landscape' ? 'unlock' : 'portrait';
}
// ═══════════════════════════════════════════════════════════ end V4/ORIENT ═

// ═══════════════════════════════════════════════════════════════ V4/FIX-FW ═
// Failed-launch cleanup decision. framework.js consumes a modifier play
// BEFORE the scene switch (§C-SYS4.4 consume-on-launch); when the launch
// never lands on the minigame scene the reservation must be released right
// there — otherwise the armed refund latch goes stale: the consumed play is
// silently lost and a LATER unrelated quit-before-countdown refunds the
// wrong (stale) snapshot. Pure so node:test can pin the decision matrix.

/**
 * V4/FIX-FW: should a finished launch attempt release (refund + disarm) the
 * modifier play consumed at launch? Only when the launch truly FAILED — it
 * never settled on the minigame scene AND the minigame scene is not current
 * either. A SLOW launch that outlasts the retry budget while the minigame
 * scene is still entering keeps its reservation: the scene's own countdown
 * (disarm) / exit() (refund) owns the latch from there. Mirrors launchInner's
 * stranded-veil drop condition so the two cleanups can never drift.
 * @param {boolean} landed whether the launch settled on the minigame scene
 *   within the retry budget
 * @param {string|null|undefined} currentSceneId sceneManager.currentId()
 * @returns {boolean} true → release the reservation now
 */
export function shouldReleaseFailedLaunch(landed, currentSceneId) {
  return landed !== true && currentSceneId !== 'minigame';
}
// ═══════════════════════════════════════════════════════════ end V4/FIX-FW ═
