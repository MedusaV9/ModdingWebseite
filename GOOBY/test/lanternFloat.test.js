// V6/C1 — Star Lantern („Sternenlaterne", PLAN6 Wave C/C1): mechanics-level
// unit tests for the pure logic module (§B rule — headless, no three/DOM)
// plus source-text contract pins on the view module (invertible export,
// dispose hygiene). The verbatim data-spine pins (coin row 4/4/24, gate L7,
// target 96/75) belong to C3's test/minigamesV6.test.js; the §G5.4
// certification acceptance itself runs in difficultyCertification.test.js
// once C3 wires the ['simulateLanternAutoplay', 'ms'] adapter row — the
// same gates are mirrored here so this file guards them mid-wave.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join, dirname } from 'node:path';

import { invertPayload } from '../src/core/inputInvert.js';
import {
  LANTERN,
  LANTERN_DIFFICULTY,
  applyDifficulty,
  steerTargetFrom,
  clampLanternX,
  ringSpacingAt,
  rollRing,
  ringHit,
  gustAt,
  gustPhaseAt,
  rollCloud,
  cloudHit,
  applyScore,
  endlessShouldEnd,
  simulateLanternAutoplay,
} from '../src/minigames/games/lanternFloat.logic.js';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const viewSrc = readFileSync(join(root, 'src/minigames/games/lanternFloat.js'), 'utf8');

/** Deterministic mulberry32 rng for draw tests. */
function rngOf(seed) {
  let a = seed >>> 0;
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let x = Math.imul(a ^ (a >>> 15), 1 | a);
    x = (x + Math.imul(x ^ (x >>> 7), 61 | x)) | 0;
    return ((x ^ (x >>> 14)) >>> 0) / 4294967296;
  };
}

// ------------------------------------------------ steering / invert contract

test('lanternFloat: steerTargetFrom mirrors exactly at the one input boundary', () => {
  assert.equal(steerTargetFrom(0), 0, 'center is a fixed point');
  for (const nx of [0.1, 0.33, 0.5, 0.87, 1]) {
    assert.equal(steerTargetFrom(-nx), -steerTargetFrom(nx), `f(−${nx}) === −f(${nx})`);
  }
  // screen-true chirality: drag right (nx +1) → world +x (renders screen right)
  assert.ok(steerTargetFrom(1) > 0);
  // §G3.1-c over-reach: full drag range covers the whole playfield
  assert.equal(steerTargetFrom(1), LANTERN.HALF_W * LANTERN.STEER_OVERREACH);
  // out-of-range nx clamps, junk coerces to center
  assert.equal(steerTargetFrom(5), steerTargetFrom(1));
  assert.equal(steerTargetFrom(-5), steerTargetFrom(-1));
  assert.equal(steerTargetFrom(NaN), 0);
});

test('lanternFloat: the §G3.3 framework invert proxy mirrors the steer target (both directions)', () => {
  // The framework wraps ctx.input and negates p.nx BEFORE the game's one
  // boundary — steering the inverted payload must mirror the raw payload.
  for (const nx of [0.6, -0.25, 1]) {
    const inverted = invertPayload('drag', { nx, ny: 0.2, dx: 4, dy: 0 }, { x: true });
    assert.equal(steerTargetFrom(inverted.nx), -steerTargetFrom(nx), `invertX mirrors nx ${nx}`);
    const untouched = invertPayload('drag', { nx, ny: 0.2 }, {});
    assert.equal(steerTargetFrom(untouched.nx), steerTargetFrom(nx), `no flag passes through nx ${nx}`);
  }
});

test('lanternFloat: view exports the invertible controls contract + consumes ctx.input drag', () => {
  assert.match(viewSrc, /export const controls = Object\.freeze\(\{ invertible: true \}\)/,
    'controls export (§G2.1 rule 4 — analog steer input)');
  assert.match(viewSrc, /ctx\.input\.on\('drag'/, 'steers through ctx.input (framework invert proxy)');
  assert.match(viewSrc, /ctx\.input\.on\('dragend'/, 'release coasts through ctx.input');
  assert.match(viewSrc, /steerTargetFrom\(/, 'the view maps drag → world at the shared boundary fn');
  assert.doesNotMatch(viewSrc, /export const orientation/, 'portrait game — no orientation export');
});

test('lanternFloat: clampLanternX keeps the lantern inside the playfield', () => {
  assert.equal(clampLanternX(0), 0);
  assert.equal(clampLanternX(99), LANTERN.HALF_W);
  assert.equal(clampLanternX(-99), -LANTERN.HALF_W);
});

// ------------------------------------------------------- rings / spacing math

test('lanternFloat: ring spacing ramps linearly and clamps past the round end', () => {
  assert.equal(ringSpacingAt(0), LANTERN.RING_SPACING_START);
  assert.equal(ringSpacingAt(LANTERN.DURATION_SEC), LANTERN.RING_SPACING_END);
  const mid = ringSpacingAt(LANTERN.DURATION_SEC / 2);
  assert.ok(mid < LANTERN.RING_SPACING_START && mid > LANTERN.RING_SPACING_END);
  assert.equal(ringSpacingAt(9999), LANTERN.RING_SPACING_END, 'clamped (endless keeps the end cadence)');
  assert.equal(ringSpacingAt(-5), LANTERN.RING_SPACING_START, 'clamped below');
});

test('lanternFloat: rollRing is deterministic, in bounds, golden every 5th', () => {
  const rng = rngOf(7);
  for (let i = 0; i < 200; i += 1) {
    const ring = rollRing(rng, i);
    assert.ok(Math.abs(ring.x) <= LANTERN.HALF_W - LANTERN.RING_MARGIN, `ring ${i} inside margins`);
    assert.equal(ring.gold, (i + 1) % LANTERN.GOLD_EVERY === 0, `gold cadence at ${i}`);
    assert.equal(ring.points, ring.gold ? LANTERN.GOLD_PTS : LANTERN.RING_PTS);
    assert.ok(Object.isFrozen(ring));
  }
  assert.deepEqual(rollRing(rngOf(5), 4), rollRing(rngOf(5), 4), 'deterministic per rng state');
});

test('lanternFloat: ringHit is a symmetric lateral window (boundary inclusive)', () => {
  const ring = { x: 1.2 };
  assert.equal(ringHit(1.2, ring), true);
  assert.equal(ringHit(1.2 + LANTERN.RING_RADIUS, ring), true, 'boundary inclusive');
  assert.equal(ringHit(1.2 - LANTERN.RING_RADIUS, ring), true, 'mirrored boundary');
  assert.equal(ringHit(1.2 + LANTERN.RING_RADIUS + 0.001, ring), false);
  // difficulty widens/narrows the window through the derived tune
  const easy = applyDifficulty(LANTERN, 'easy');
  const hard = applyDifficulty(LANTERN, 'hard');
  const nearMiss = 1.2 + LANTERN.RING_RADIUS + 0.05;
  assert.equal(ringHit(nearMiss, ring, easy), true, 'Leicht catches the near miss');
  assert.equal(ringHit(nearMiss, ring, hard), false, 'Schwer does not');
});

// -------------------------------------------------------------- gusts / clouds

test('lanternFloat: gustAt is a deterministic schedule with ordered windows', () => {
  for (let i = 0; i < 12; i += 1) {
    const g = gustAt(i);
    assert.deepEqual(g, gustAt(i), 'deterministic');
    assert.ok(Object.isFrozen(g));
    assert.ok(g.startSec < g.pushSec && g.pushSec < g.endSec, `windows ordered at ${i}`);
    assert.ok(g.dir === 1 || g.dir === -1, 'push direction is a unit sign');
    if (i > 0) assert.ok(g.startSec > gustAt(i - 1).endSec, 'gusts never overlap');
  }
  assert.equal(gustAt(0).startSec, LANTERN.GUST_FIRST_SEC);
  // both directions occur across a round's worth of gusts
  const dirs = new Set(Array.from({ length: 8 }, (_, i) => gustAt(i).dir));
  assert.deepEqual([...dirs].sort(), [-1, 1]);
});

test('lanternFloat: gustPhaseAt walks idle → telegraph → push → idle', () => {
  const g0 = gustAt(0);
  assert.equal(gustPhaseAt(0).phase, 'idle');
  assert.equal(gustPhaseAt(0).gust.index, 0, 'idle phase points at the UPCOMING gust');
  assert.equal(gustPhaseAt(g0.startSec + 0.01).phase, 'telegraph');
  assert.equal(gustPhaseAt(g0.pushSec + 0.01).phase, 'push');
  assert.equal(gustPhaseAt(g0.endSec + 0.01).phase, 'idle');
  assert.equal(gustPhaseAt(g0.endSec + 0.01).gust.index, 1, 'after the window the next gust is upcoming');
  const g3 = gustAt(3);
  assert.equal(gustPhaseAt(g3.pushSec + 0.1).gust.index, 3);
  assert.equal(gustPhaseAt(g3.pushSec + 0.1).phase, 'push');
});

test('lanternFloat: rollCloud consumes exactly two draws and honors the min index', () => {
  let draws = 0;
  const rng = () => {
    draws += 1;
    return 0.01; // always below CLOUD_CHANCE
  };
  const early = rollCloud(rng, 0);
  assert.equal(draws, 2, 'two draws even when the min index suppresses the cloud');
  assert.equal(early.present, false, 'no clouds before CLOUD_MIN_INDEX (friendly start)');
  const late = rollCloud(rng, LANTERN.CLOUD_MIN_INDEX);
  assert.equal(draws, 4, 'two draws again');
  assert.equal(late.present, true);
  assert.ok(Math.abs(late.x) <= LANTERN.HALF_W - LANTERN.RING_MARGIN);
  const never = rollCloud(() => 0.99, 20);
  assert.equal(never.present, false, 'chance gate');
});

test('lanternFloat: cloudHit is a symmetric soft-bump window', () => {
  const cloud = { x: -0.8 };
  assert.equal(cloudHit(-0.8, cloud), true);
  assert.equal(cloudHit(-0.8 + LANTERN.CLOUD_HALF_W, cloud), true);
  assert.equal(cloudHit(-0.8 - LANTERN.CLOUD_HALF_W - 0.001, cloud), false);
});

// ------------------------------------------------------ difficulty family §G5.3

test('lanternFloat: difficulty direction — Leicht wider/slower/longer, Schwer tighter/faster', () => {
  const easy = applyDifficulty(LANTERN, 'easy');
  const hard = applyDifficulty(LANTERN, 'hard');
  assert.equal(applyDifficulty(LANTERN, 'normal'), LANTERN, 'Mittel returns the exact base object');
  assert.equal(applyDifficulty(LANTERN, 'banana'), LANTERN, 'unknown mode normalizes to Mittel');
  assert.equal(applyDifficulty(undefined, 'normal'), LANTERN, 'default tune is the frozen base');
  // frozen C1 contract rows verbatim
  assert.equal(easy.RING_RADIUS, LANTERN.RING_RADIUS * 1.25);
  assert.equal(easy.RISE_SPEED, LANTERN.RISE_SPEED * 0.8);
  assert.equal(easy.DURATION_SEC, LANTERN.DURATION_SEC * 1.2);
  assert.equal(hard.RING_RADIUS, LANTERN.RING_RADIUS * 0.8);
  assert.equal(hard.RISE_SPEED, LANTERN.RISE_SPEED * 1.2);
  assert.equal(hard.DURATION_SEC, LANTERN.DURATION_SEC);
  assert.ok(Object.isFrozen(LANTERN) && Object.isFrozen(easy) && Object.isFrozen(hard));
  assert.ok(Object.isFrozen(LANTERN_DIFFICULTY));
});

test('lanternFloat: §G5.3 guardrail — every non-bot knob stays inside [0.55, 2.05]', () => {
  for (const mode of ['easy', 'hard', 'endless']) {
    const derived = applyDifficulty(LANTERN, mode);
    for (const key of Object.keys(LANTERN)) {
      if (/BOT|AUTOPLAY|DISTRACT/i.test(key)) continue;
      if (typeof LANTERN[key] !== 'number' || !(LANTERN[key] > 0)) continue;
      const ratio = derived[key] / LANTERN[key];
      assert.ok(ratio >= 0.549 && ratio <= 2.051, `${mode} ${key} ratio ${ratio.toFixed(3)}`);
    }
  }
});

test('lanternFloat: endless derives the Schwer tuning plus the ENDLESS flag', () => {
  const hard = applyDifficulty(LANTERN, 'hard');
  const endless = applyDifficulty(LANTERN, 'endless');
  assert.equal(endless.ENDLESS, true);
  assert.equal(hard.ENDLESS, false);
  for (const key of Object.keys(LANTERN)) {
    if (key === 'ENDLESS') continue;
    assert.equal(endless[key], hard[key], `endless keeps the Schwer ${key}`);
  }
});

// ------------------------------------------------------- scoring / endless end

test('lanternFloat: score floors at 0 — a bump can never go negative (comfy)', () => {
  assert.equal(applyScore(0, -LANTERN.BUMP_PENALTY), 0);
  assert.equal(applyScore(2, -LANTERN.BUMP_PENALTY), 0);
  assert.equal(applyScore(10, 5), 15);
});

test('lanternFloat: Endlos ends on exactly the 3rd cloud bump, timed never ends early', () => {
  assert.equal(endlessShouldEnd(99, LANTERN), false, 'timed runs never end on bumps');
  const endless = applyDifficulty(LANTERN, 'endless');
  assert.equal(endlessShouldEnd(0, endless), false);
  assert.equal(endlessShouldEnd(2, endless), false);
  assert.equal(endlessShouldEnd(3, endless), true);
  assert.equal(endlessShouldEnd(4, endless), true);
  assert.equal(endless.ENDLESS_MAX_BUMPS, 3, 'frozen C1 contract: 3 cloud bumps');
});

// --------------------------------------------------------- certification bot

test('lanternFloat: bot is deterministic per seed+mode across all modes', () => {
  for (const mode of ['easy', 'normal', 'hard', 'endless']) {
    const a = simulateLanternAutoplay(mode, 42);
    const b = simulateLanternAutoplay(mode, 42);
    assert.deepEqual(a, b, `${mode} deterministic`);
    assert.ok(Object.isFrozen(a));
    assert.ok(Number.isFinite(a.score) && a.score >= 0, `${mode} finite score`);
    assert.notDeepEqual(a, simulateLanternAutoplay(mode, 43), `${mode} seed matters`);
  }
});

test('lanternFloat: bot reaches plausible scores across modes and seeds', () => {
  // Timed runs land in a sane band (never zero, never past the perfect-play
  // ceiling); the certification narrative is typical raw ≈ 65 → ~16c.
  for (const seed of [1, 2, 3, 5, 8, 13, 21, 42]) {
    for (const mode of ['easy', 'normal', 'hard']) {
      const run = simulateLanternAutoplay(mode, seed);
      assert.ok(run.score >= 25 && run.score <= 140, `${mode}/${seed} score ${run.score} plausible`);
      assert.ok(run.rings > 20, `${mode}/${seed} saw a full round of rings`);
      assert.ok(run.hits <= run.rings, `${mode}/${seed} hits bounded`);
      assert.ok(run.elapsed <= applyDifficulty(LANTERN, mode).DURATION_SEC + 3, `${mode}/${seed} round length`);
    }
  }
});

test('lanternFloat: §G5.4 gates — Schwer beatable on the cert seeds, Leicht ≥ Mittel ≥ Schwer means', () => {
  // Mirrors difficultyCertification.test.js (HARD_SEEDS + MEAN_SEEDS) so the
  // gate is guarded here mid-wave, before C3 wires the adapter row.
  const target = 75; // frozen C1 contract (capScore 96)
  const hardHits = [11, 22, 33, 44, 55]
    .map((s) => simulateLanternAutoplay('hard', s).score)
    .filter((s) => s >= target).length;
  assert.ok(hardHits >= 1, `bot beats the Schwer-Ziel ${target} on ≥ 1 of 5 cert seeds (got ${hardHits})`);
  const MEAN_SEEDS = Array.from({ length: 10 }, (_, i) => (i + 1) * 7919);
  const mean = (mode) =>
    MEAN_SEEDS.reduce((a, s) => a + simulateLanternAutoplay(mode, s).score, 0) / MEAN_SEEDS.length;
  const easyMean = mean('easy');
  const normalMean = mean('normal');
  const hardMean = mean('hard');
  assert.ok(easyMean >= normalMean, `Leicht mean ${easyMean.toFixed(1)} ≥ Mittel ${normalMean.toFixed(1)} (same bot)`);
  assert.ok(hardMean <= normalMean, `Schwer mean ${hardMean.toFixed(1)} ≤ Mittel ${normalMean.toFixed(1)} (same bot)`);
});

test('lanternFloat: Endlos bot terminates through exactly 3 bumps', () => {
  for (const seed of [1, 2, 3, 4, 5, 42, 99, 1234]) {
    const run = simulateLanternAutoplay('endless', seed);
    assert.equal(run.bumps, 3, `endless/${seed} ended by the 3rd bump`);
    assert.ok(Number.isFinite(run.elapsed) && run.elapsed < 600, `endless/${seed} terminates`);
    assert.ok(run.score >= 0);
  }
});

// ------------------------------------------------------ view contract pins

test('lanternFloat: view dispose hygiene — listeners off, owned resources freed', () => {
  assert.match(viewSrc, /dispose\(\)/, 'dispose exists');
  assert.match(viewSrc, /this\.offDrag\?\.\(\)/, 'drag subscription released');
  assert.match(viewSrc, /this\.offDragEnd\?\.\(\)/, 'dragend subscription released');
  assert.match(viewSrc, /for \(const geo of this\.ownedGeos \?\? \[\]\) geo\.dispose\(\)/, 'owned geometries freed');
  assert.match(viewSrc, /for \(const mat of this\.ownedMats \?\? \[\]\) mat\.dispose\(\)/, 'owned materials freed');
  assert.match(viewSrc, /for \(const tex of this\.ownedTexs \?\? \[\]\) tex\.dispose\(\)/, 'owned textures freed');
  assert.match(viewSrc, /this\.floats\?\.dispose\(\)/, 'float texts freed');
  assert.match(viewSrc, /this\.particles\?\.dispose\(\)/, 'particles freed');
  assert.match(viewSrc, /this\.gooby\?\.dispose\(\)/, 'Gooby rig freed');
});

test('lanternFloat: view plays only sample-backed sfx ids from sfxMap.js', async () => {
  const { SFX_MAP } = await import('../src/audio/sfxMap.js');
  const ids = [...viewSrc.matchAll(/audio\.play\('([^']+)'\)/g)].map((m) => m[1]);
  assert.ok(ids.length >= 5, 'the view actually fires audio cues');
  for (const id of ids) {
    assert.ok(SFX_MAP[id] != null, `sfx id '${id}' exists in sfxMap.js`);
  }
  const warm = viewSrc.match(/sfx: \[([^\]]+)\]/)?.[1] ?? '';
  for (const id of [...warm.matchAll(/'([^']+)'/g)].map((m) => m[1])) {
    assert.ok(SFX_MAP[id] != null, `warm-list sfx id '${id}' exists in sfxMap.js`);
  }
});

test('lanternFloat: view respects reduced motion and avoids per-frame allocations', () => {
  assert.match(viewSrc, /prefersReducedMotion\(\)/, 'reduced-motion gate imported and used');
  assert.match(viewSrc, /this\.reduceMotion/, 'snapshot consumed in update paths');
  // pre-allocated scratch vector rule — update() must not clone per frame
  assert.match(viewSrc, /_v3 = new THREE\.Vector3\(\)/, 'pre-allocated scratch vector');
});
