// GOOBY V6 Wave C / C2 — Schneckenpost ('snailMail') mechanics tests (§B
// rule: pure logic only). Covers: seeded generation is ALWAYS solvable,
// spline-toolkit resampling determinism + arc-length properties, follow
// kinematics (arc monotone, speed ceiling/floor), puddle-corridor edge math,
// the frozen 4/+2/+1 scoring contract, Endlos 3-wet-deliveries termination,
// §G5.3 difficulty directions with the 0.55–2.05 guardrail, deterministic
// certification-bot plausibility (mirrors difficultyCertification's gates so
// C3's ADAPTERS row lands green) and the view module's dispose/controls
// contract via source analysis (view imports three.js — not importable here).
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  SNAIL,
  SNAIL_DIFFICULTY,
  applyDifficulty,
  puddlesForRound,
  doorOf,
  puddleEffR,
  puddleHitAt,
  pathClear,
  smoothPath,
  speedAt,
  advanceArc,
  followInto,
  followAt,
  flowersOnPath,
  startsAtPost,
  endHouse,
  deliveryPoints,
  applyScore,
  endlessShouldEnd,
  autoRoute,
  generateLevel,
  simulateSnailAutoplay,
} from '../src/minigames/games/snailMail.logic.js';
// Toolkit reuse gate: these MUST come from goobyWelt.logic.js (imported, not
// copied) — the logic module re-exports them, and a source pin below checks
// the import statement itself.
import { catmullRom, dist3, buildTrack } from '../src/minigames/games/snailMail.logic.js';

const ROOT = fileURLToPath(new URL('..', import.meta.url));
const read = (rel) => fs.readFileSync(path.join(ROOT, rel), 'utf8');

/** Deterministic mulberry32 rng (the suite-wide pattern). */
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

// -------------------------------------------------------- contract pins

test('snailMail: frozen tune pins the V6 interface contract', () => {
  assert.equal(SNAIL.DURATION_SEC, 60);
  assert.equal(SNAIL.DELIVER_PTS, 4);
  assert.equal(SNAIL.DRY_BONUS, 2);
  assert.equal(SNAIL.FLOWER_PTS, 1);
  assert.equal(SNAIL.ENDLESS_MAX_SPLASHES, 3);
  assert.equal(SNAIL.RETREAT_SEC, 2);
  assert.equal(SNAIL.ENDLESS, false);
  assert.ok(Object.isFrozen(SNAIL) && Object.isFrozen(SNAIL_DIFFICULTY));
});

test('snailMail: spline toolkit is imported from goobyWelt.logic.js, not copied', () => {
  const src = read('src/minigames/games/snailMail.logic.js');
  assert.match(
    src,
    /import \{ catmullRom, dist3, buildTrack \} from '\.\/goobyWelt\.logic\.js';/,
    'toolkit import statement'
  );
  // and the re-exported symbols behave like the toolkit (basic sanity)
  assert.equal(dist3([0, 0, 0], [3, 4, 0]), 5);
  const mid = catmullRom([0, 0, 0], [0, 0, 0], [2, 0, 0], [2, 0, 0], 0.5);
  assert.ok(Math.abs(mid[0] - 1) < 1e-9);
  const track = buildTrack({ waypoints: [[0, 0, 0], [1, 0, 0]], corridor: [1] });
  assert.ok(Math.abs(track.length - 1) < 1e-6);
});

// -------------------------------------------------------- difficulty (§G5.3)

test('snailMail: difficulty directions — Leicht slower/longer/forgiving, Schwer faster/tighter', () => {
  const easy = applyDifficulty(SNAIL, 'easy');
  const hard = applyDifficulty(SNAIL, 'hard');
  const endless = applyDifficulty(SNAIL, 'endless');
  assert.equal(applyDifficulty(SNAIL, 'normal'), SNAIL, 'Mittel returns the exact base object');
  assert.equal(applyDifficulty(SNAIL, 'banana'), SNAIL, 'unknown mode normalizes to Mittel');
  // easy: slower cadence, +20 % time, more forgiving puddle edges
  assert.ok(easy.SPEED < SNAIL.SPEED);
  assert.ok(Math.abs(easy.DURATION_SEC - SNAIL.DURATION_SEC * 1.2) < 1e-9, '+20 % time');
  assert.ok(easy.PUDDLE_EDGE < SNAIL.PUDDLE_EDGE);
  // hard: faster deliveries, tighter margins
  assert.ok(hard.SPEED > SNAIL.SPEED);
  assert.equal(hard.DURATION_SEC, SNAIL.DURATION_SEC);
  assert.ok(hard.PUDDLE_EDGE > SNAIL.PUDDLE_EDGE);
  // endless: hard tuning + the run flag
  assert.equal(endless.SPEED, hard.SPEED);
  assert.equal(endless.PUDDLE_EDGE, hard.PUDDLE_EDGE);
  assert.equal(endless.ENDLESS, true);
  assert.equal(hard.ENDLESS, false);
  assert.ok(Object.isFrozen(easy) && Object.isFrozen(hard) && Object.isFrozen(endless));
});

test('snailMail: difficulty guardrail — every multiplier within 0.55–2.05', () => {
  for (const row of Object.values(SNAIL_DIFFICULTY)) {
    for (const mult of [row.speedMult, row.durationMult, row.puddleEdge]) {
      assert.ok(mult >= 0.55 && mult <= 2.05, `multiplier ${mult} inside the §G5.3 guardrail`);
    }
  }
});

// -------------------------------------------------------- generation solvable

test('snailMail: generation is ALWAYS solvable across seeds, rounds and modes', () => {
  for (const mode of ['easy', 'normal', 'hard']) {
    const tune = applyDifficulty(SNAIL, mode);
    for (let seed = 1; seed <= 20; seed += 1) {
      const rng = rngOf(seed * 101);
      for (const round of [0, 2, 5, 9]) {
        const level = generateLevel(rng, round, tune);
        assert.equal(level.houses.length, 3, 'three candidate houses');
        assert.ok(level.targetIdx >= 0 && level.targetIdx < 3);
        assert.ok(level.puddles.length <= puddlesForRound(round, tune));
        for (const p of level.puddles) {
          assert.ok(p.r >= tune.PUDDLE_R_MIN && p.r <= tune.PUDDLE_R_MAX);
          assert.ok(Math.abs(p.x) <= tune.FIELD_HALF_W, 'puddle inside the field');
          assert.ok(
            Math.hypot(p.x - level.post.x, p.y - level.post.y) >= p.r + tune.PUDDLE_KEEPOUT - 1e-9,
            'puddle clear of the post box'
          );
        }
        for (const f of level.flowers) {
          assert.equal(puddleHitAt(f.x, f.y, level.puddles, tune), -1, 'flower not in a puddle');
        }
        // THE solvability gate: a smoothed, clear route to the target exists
        const route = autoRoute(level, tune);
        assert.ok(route.ok, `seed ${seed} round ${round} ${mode}: route exists`);
        assert.ok(pathClear(route.smooth.pts, level.puddles, tune), 'smoothed route clear');
        assert.ok(startsAtPost(route.smooth.pts[0], tune), 'route starts at the post box');
        assert.equal(endHouse(route.smooth, level, tune), level.targetIdx, 'route ends on the target door');
      }
    }
  }
});

test('snailMail: puddle ramp 2 → 5 over delivered rounds', () => {
  assert.equal(puddlesForRound(0), SNAIL.PUDDLES_START);
  assert.equal(puddlesForRound(1), SNAIL.PUDDLES_START);
  assert.equal(puddlesForRound(2), SNAIL.PUDDLES_START + 1);
  assert.equal(puddlesForRound(99), SNAIL.PUDDLES_MAX);
});

// -------------------------------------------------------- resampling

test('snailMail: smoothPath is deterministic and preserves endpoints', () => {
  const raw = [
    { x: 0, y: -2.35 }, { x: 0.3, y: -1.6 }, { x: 0.1, y: -0.8 },
    { x: -0.4, y: 0.1 }, { x: -0.2, y: 1.0 }, { x: 0.4, y: 1.9 },
  ];
  const a = smoothPath(raw);
  const b = smoothPath(raw.map((p) => ({ ...p })));
  assert.deepEqual(a, b, 'identical input → identical path');
  assert.ok(Math.abs(a.pts[0].x - raw[0].x) < 1e-9 && Math.abs(a.pts[0].y - raw[0].y) < 1e-9, 'start preserved');
  const tip = a.pts[a.pts.length - 1];
  const last = raw[raw.length - 1];
  assert.ok(Math.hypot(tip.x - last.x, tip.y - last.y) < 1e-9, 'end preserved');
});

test('snailMail: smoothPath resamples at ~uniform arc steps with monotone cum', () => {
  const raw = [
    { x: 0, y: -2.3 }, { x: 0.9, y: -1.2 }, { x: -0.6, y: 0.4 }, { x: 0.2, y: 2.0 },
  ];
  const p = smoothPath(raw);
  assert.ok(p.length > 0);
  assert.equal(p.cum[0], 0);
  for (let i = 1; i < p.cum.length; i += 1) {
    const step = p.cum[i] - p.cum[i - 1];
    assert.ok(step > 0, 'cum strictly increasing');
    assert.ok(step <= SNAIL.RESAMPLE_STEP * 1.5, `step ${step} near the resample step`);
  }
  assert.ok(Math.abs(p.cum[p.cum.length - 1] - p.length) < 1e-9, 'length == last cum');
});

test('snailMail: smoothPath filters jitter, caps points and rejects dots', () => {
  // sub-spacing jitter collapses to a 2-point path
  const jitter = Array.from({ length: 30 }, (_, i) => ({ x: i * 0.004, y: 0 }));
  const collapsed = smoothPath(jitter);
  assert.ok(collapsed === null || collapsed.length < 0.2, 'jitter cloud is no path');
  assert.equal(smoothPath([{ x: 1, y: 1 }]), null, 'single point → null');
  assert.equal(smoothPath([]), null, 'empty → null');
  // a hostile mega-stroke is capped, not O(n²)-exploded
  const mega = Array.from({ length: 5000 }, (_, i) => ({ x: (i % 100) * 0.05, y: Math.floor(i / 100) * 0.2 }));
  const capped = smoothPath(mega);
  assert.ok(capped !== null && Number.isFinite(capped.length));
});

// -------------------------------------------------------- follow kinematics

test('snailMail: speedAt never exceeds cruise, never stalls, eases at both ends', () => {
  const length = 5;
  for (let s = 0; s <= length; s += 0.05) {
    const v = speedAt(s, length);
    assert.ok(v <= SNAIL.SPEED + 1e-9, 'speed ceiling = cruise');
    assert.ok(v >= SNAIL.SPEED * SNAIL.SPEED_MIN_FRAC - 1e-9, 'speed floor');
  }
  assert.ok(speedAt(0, length) < speedAt(length / 2, length), 'ease-in');
  assert.ok(speedAt(length, length) < speedAt(length / 2, length), 'ease-out');
  assert.ok(Math.abs(speedAt(length / 2, length) - SNAIL.SPEED) < 1e-9, 'cruise mid-path');
});

test('snailMail: advanceArc is monotone, clamps at the end and integrates plausibly', () => {
  const length = 4.2;
  let s = 0;
  let t = 0;
  let prev = 0;
  while (s < length && t < 30) {
    s = advanceArc(s, 1 / 60, length, SNAIL);
    assert.ok(s >= prev, 'arc position monotone');
    prev = s;
    t += 1 / 60;
  }
  assert.equal(s, length, 'reaches the end exactly (clamped)');
  const tMin = length / SNAIL.SPEED;
  const tMax = length / (SNAIL.SPEED * SNAIL.SPEED_MIN_FRAC);
  assert.ok(t >= tMin - 0.05 && t <= tMax + 0.05, `travel ${t}s within [${tMin}, ${tMax}]`);
  assert.equal(advanceArc(length, 1, length), length, 'no overshoot');
  assert.equal(advanceArc(1, -5, length), 1, 'hostile negative dt ignored');
});

test('snailMail: followInto/followAt interpolate position + heading on the path', () => {
  const p = smoothPath([{ x: 0, y: 0 }, { x: 2, y: 0 }]);
  const start = followAt(p, 0);
  assert.ok(Math.abs(start.x) < 1e-9 && Math.abs(start.y) < 1e-9);
  const end = followAt(p, p.length);
  assert.ok(Math.abs(end.x - 2) < 1e-9 && Math.abs(end.y) < 1e-9);
  const mid = followAt(p, p.length / 2);
  assert.ok(Math.abs(mid.x - 1) < 0.05, 'midpoint at half arc');
  assert.ok(Math.abs(mid.angle) < 1e-6, 'straight +x path → angle 0');
  // out-object form allocates nothing new
  const out = { x: 0, y: 0, angle: 0 };
  const ret = followInto(p, p.length / 2, out);
  assert.equal(ret, out, 'followInto returns the out object');
  assert.ok(Math.abs(out.x - mid.x) < 1e-9);
  // clamped outside the domain
  assert.ok(Math.abs(followAt(p, -5).x) < 1e-9);
  assert.ok(Math.abs(followAt(p, 999).x - 2) < 1e-9);
  // a vertical path reports a +y heading
  const up = smoothPath([{ x: 0, y: 0 }, { x: 0, y: 2 }]);
  assert.ok(Math.abs(followAt(up, up.length / 2).angle - Math.PI / 2) < 1e-6);
});

// -------------------------------------------------------- puddle corridor

test('snailMail: puddle edge math — strict inside hits, exact edge is safe', () => {
  const puddles = [{ x: 0, y: 0, r: 0.4 }];
  const effR = puddleEffR(puddles[0]);
  assert.ok(Math.abs(effR - (0.4 * SNAIL.PUDDLE_EDGE + SNAIL.SNAIL_RADIUS)) < 1e-12);
  assert.equal(puddleHitAt(0, 0, puddles), 0, 'center hits');
  assert.equal(puddleHitAt(effR - 1e-6, 0, puddles), 0, 'just inside hits');
  assert.equal(puddleHitAt(effR, 0, puddles), -1, 'exact edge is safe (strict <)');
  assert.equal(puddleHitAt(effR + 1e-6, 0, puddles), -1, 'outside safe');
  assert.equal(puddleHitAt(5, 5, []), -1, 'no puddles');
});

test('snailMail: puddle forgiveness direction — easy shrinks, hard grows the edge', () => {
  const p = { x: 0, y: 0, r: 0.4 };
  const easy = applyDifficulty(SNAIL, 'easy');
  const hard = applyDifficulty(SNAIL, 'hard');
  assert.ok(puddleEffR(p, easy) < puddleEffR(p, SNAIL));
  assert.ok(puddleEffR(p, hard) > puddleEffR(p, SNAIL));
  // a grazing point that is safe on easy but wet on hard
  const graze = puddleEffR(p, SNAIL) - 1e-6;
  assert.equal(puddleHitAt(graze, 0, [p], easy), -1, 'easy forgives the graze');
  assert.equal(puddleHitAt(graze, 0, [p], hard), 0, 'hard punishes the graze');
});

test('snailMail: pathClear flags a waypoint inside a puddle', () => {
  const puddles = [{ x: 1, y: 0, r: 0.4 }];
  const through = smoothPath([{ x: 0, y: 0 }, { x: 2, y: 0 }]);
  assert.equal(pathClear(through.pts, puddles), false, 'straight-through path is wet');
  const around = smoothPath([{ x: 0, y: 0 }, { x: 1, y: 1.4 }, { x: 2, y: 0 }]);
  assert.equal(pathClear(around.pts, puddles), true, 'detour path is dry');
});

// -------------------------------------------------------- scoring / bonuses

test('snailMail: frozen scoring — delivery 4, dry +2, flower +1', () => {
  assert.equal(deliveryPoints(false, 0), 6, 'dry, no flowers: 4 + 2');
  assert.equal(deliveryPoints(true, 0), 4, 'wet: base only');
  assert.equal(deliveryPoints(false, 3), 9, 'dry + 3 flowers: 4 + 2 + 3');
  assert.equal(deliveryPoints(true, 2), 6, 'wet + 2 flowers: 4 + 2');
  assert.equal(deliveryPoints(true, -5), 4, 'hostile negative flower count clamped');
  assert.equal(applyScore(0, -5), 0, 'score floors at 0');
  assert.equal(applyScore(10, 6), 16);
});

test('snailMail: flowersOnPath picks by corridor radius, start/end checks work', () => {
  const p = smoothPath([{ x: 0, y: -2.35 }, { x: 0, y: 2 }]);
  const flowers = [
    { x: 0.2, y: 0 }, //  inside the corridor
    { x: 1.6, y: 0 }, //  far off
    { x: -SNAIL.FLOWER_PICK_RADIUS + 0.01, y: 1 }, // just inside
  ];
  assert.deepEqual(flowersOnPath(p, flowers), [0, 2]);
  assert.deepEqual(flowersOnPath(p, []), []);
  assert.ok(startsAtPost({ x: SNAIL.POST_X + 0.3, y: SNAIL.POST_Y - 0.2 }));
  assert.ok(!startsAtPost({ x: SNAIL.POST_X + 2, y: SNAIL.POST_Y }));
  // endHouse: nearest door within DELIVER_RADIUS, −1 in the open garden
  const level = {
    houses: [{ x: -1.5, y: 2.1 }, { x: 0, y: 2.3 }, { x: 1.5, y: 2.0 }],
  };
  // doorOf: the door sits DOOR_OFFSET_Y below the house anchor
  assert.deepEqual(doorOf(level.houses[1]), { x: 0, y: 2.3 - SNAIL.DOOR_OFFSET_Y });
  const toMid = smoothPath([{ x: 0, y: -2.35 }, { x: 0, y: 2.3 - SNAIL.DOOR_OFFSET_Y }]);
  assert.equal(endHouse(toMid, level), 1);
  const toNowhere = smoothPath([{ x: 0, y: -2.35 }, { x: 0, y: 0 }]);
  assert.equal(endHouse(toNowhere, level), -1);
});

// -------------------------------------------------------- endless termination

test('snailMail: Endlos ends on the 3rd wet delivery — only in endless', () => {
  assert.equal(endlessShouldEnd(99, SNAIL), false, 'timed runs never end on splashes');
  const endless = applyDifficulty(SNAIL, 'endless');
  assert.equal(endlessShouldEnd(0, endless), false);
  assert.equal(endlessShouldEnd(2, endless), false);
  assert.equal(endlessShouldEnd(3, endless), true);
  assert.equal(endlessShouldEnd(4, endless), true);
});

// -------------------------------------------------------- certification bot

test('snailMail: bot is deterministic per seed + mode', () => {
  const a = simulateSnailAutoplay('hard', 42);
  const b = simulateSnailAutoplay('hard', 42);
  assert.deepEqual(a, b);
  assert.notDeepEqual(simulateSnailAutoplay('hard', 43).score, undefined);
});

test('snailMail: bot completes every mode with finite scores and plausible ranges', () => {
  for (const mode of ['easy', 'normal', 'hard', 'endless']) {
    for (const seed of [11, 22, 33]) {
      const run = simulateSnailAutoplay(mode, seed);
      assert.ok(Number.isFinite(run.score) && run.score >= 0, `${mode}/${seed} finite score`);
      assert.ok(run.deliveries > 0, `${mode}/${seed} delivers at least once`);
      assert.ok(run.elapsed <= SNAIL.BOT_TIME_CAP_SEC + 30, `${mode}/${seed} terminates`);
    }
  }
});

test('snailMail: §G5.4 gates — Schwer target 80 beatable, Leicht mean ≥ Schwer mean', () => {
  // mirrors difficultyCertification.test.js so C3's ADAPTERS row lands green
  const HARD_SEEDS = [11, 22, 33, 44, 55];
  const MEAN_SEEDS = Array.from({ length: 10 }, (_, i) => (i + 1) * 7919);
  const hardHits = HARD_SEEDS.filter((s) => simulateSnailAutoplay('hard', s).score >= 80).length;
  assert.ok(hardHits >= 1, `hard bot reaches 80 in ≥ 1 of 5 seeds (got ${hardHits})`);
  const mean = (xs) => xs.reduce((x, y) => x + y, 0) / xs.length;
  const easyMean = mean(MEAN_SEEDS.map((s) => simulateSnailAutoplay('easy', s).score));
  const hardMean = mean(MEAN_SEEDS.map((s) => simulateSnailAutoplay('hard', s).score));
  assert.ok(easyMean >= hardMean, `monotone means: easy ${easyMean} ≥ hard ${hardMean}`);
});

test('snailMail: endless bot terminates through the 3-splash end-condition', () => {
  for (const seed of [11, 22, 33, 44, 55]) {
    const run = simulateSnailAutoplay('endless', seed);
    assert.ok(
      run.splashes <= SNAIL.ENDLESS_MAX_SPLASHES,
      `${seed}: splashes ${run.splashes} ≤ 3`
    );
    assert.ok(Number.isFinite(run.elapsed) && run.elapsed <= SNAIL.BOT_TIME_CAP_SEC + 30);
  }
});

// -------------------------------------------------------- view module contract

test('snailMail: view module pins §E8 plugin shape, controls export and dispose hygiene', () => {
  const src = read('src/minigames/games/snailMail.js');
  // §G2.1 rule 4 one-liner (controlsContract.test.js format — C3 adds the row)
  assert.match(src, /export const controls = Object\.freeze\(\{ invertible: false \}\);/);
  assert.equal(src.match(/export const controls =/g).length, 1, 'single declaration');
  assert.match(src, /id: 'snailMail'/, 'plugin id');
  // dispose hygiene: every registered canvas listener is removed and the
  // owned geometry/material pools are swept (teaParty/hideSeek model)
  assert.match(src, /removeEventListener\('pointerdown'/);
  assert.match(src, /removeEventListener\('pointermove'/);
  assert.match(src, /removeEventListener\('pointerup'/);
  assert.match(src, /removeEventListener\('pointercancel'/);
  assert.match(src, /for \(const geo of this\.ownedGeos \?\? \[\]\) geo\.dispose\(\);/);
  assert.match(src, /for \(const mat of this\.ownedMats \?\? \[\]\) mat\.dispose\(\);/);
  assert.match(src, /this\.ctx = null;/, 'ctx released');
  // reduced-motion gate + framework float clamp are wired
  assert.match(src, /prefersReducedMotion/);
  // audio: only ids that exist in sfxMap.js (audioCoverage complement)
  const sfxSrc = read('src/audio/sfxMap.js');
  const played = new Set([...src.matchAll(/audio\.play\('([^']+)'\)/g)].map((m) => m[1]));
  assert.ok(played.size >= 4, 'the view plays a real cue set');
  for (const id of played) {
    assert.ok(sfxSrc.includes(`'${id}'`), `sfx id '${id}' exists in sfxMap.js`);
  }
});
