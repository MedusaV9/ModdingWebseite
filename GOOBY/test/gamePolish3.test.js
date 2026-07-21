// GAME-POLISH-3 (runner/bunnyHop/starHopper/harborHopper/trampoline/
// basketBounce juice pass): pure-logic tests for the new celebration-beat
// helpers. These cues are STRICTLY audiovisual — the assertions here pin that
// they cannot drift into the frozen §C6.1 scoring/physics tables.
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  RUNNER_JUICE,
  crossedRunnerMilestone,
} from '../src/minigames/games/runner.logic.js';
import {
  HOP,
  HOP_JUICE,
  gapAtGate,
  gapNarrowsAtGate,
} from '../src/minigames/games/bunnyHop.logic.js';
import { HOPPER_JUICE } from '../src/minigames/games/starHopper.logic.js';
import { HARBOR_JUICE } from '../src/minigames/games/harborHopper.logic.js';
import { TRAMP_JUICE } from '../src/minigames/games/trampoline.logic.js';
import {
  BASKET,
  BASKET_JUICE,
  isOnFire,
  scoreShot,
} from '../src/minigames/games/basketBounce.logic.js';
import { EN as GP3_EN, DE as GP3_DE } from '../src/data/strings/v4-gpgroup3.js';

// ---------------------------------------------------------------------------
// runner
// ---------------------------------------------------------------------------

test('GP3 runner: crossedRunnerMilestone fires once per 100 m boundary', () => {
  assert.equal(RUNNER_JUICE.MILESTONE_EVERY_M, 100);
  assert.equal(crossedRunnerMilestone(0, 12.4), 0);
  assert.equal(crossedRunnerMilestone(98.2, 100.1), 100);
  assert.equal(crossedRunnerMilestone(100.1, 101.3), 0, 'no double fire');
  assert.equal(crossedRunnerMilestone(199.4, 201.0), 200);
  // a huge frame skip still reports the LATEST milestone crossed
  assert.equal(crossedRunnerMilestone(95, 315), 300);
  // never fires backwards / on negative input
  assert.equal(crossedRunnerMilestone(-5, 5), 0);
});

test('GP3 runner: juice knobs are frozen + visual-only', () => {
  assert.ok(Object.isFrozen(RUNNER_JUICE));
  assert.ok(RUNNER_JUICE.LANDING_PUFF_COUNT > 0);
});

// ---------------------------------------------------------------------------
// bunnyHop
// ---------------------------------------------------------------------------

test('GP3 bunnyHop: gapNarrowsAtGate matches the §C6.1 every-10-gates ramp', () => {
  // GAP_BASE 2.15 − 0.16/step floors at GAP_MIN 1.5 after gate 50
  for (const g of [10, 20, 30, 40, 50]) {
    assert.equal(gapNarrowsAtGate(g), true, `gate ${g} narrows`);
  }
  for (const g of [0, 1, 5, 11, 25, 49]) {
    assert.equal(gapNarrowsAtGate(g), false, `gate ${g} must not warn`);
  }
  // once GAP_MIN holds, the warning must never lie again
  for (const g of [60, 70, 120]) {
    assert.equal(gapAtGate(g), HOP.GAP_MIN);
    assert.equal(gapNarrowsAtGate(g), false, `gate ${g} is already at GAP_MIN`);
  }
});

test('GP3 bunnyHop: juice knobs are frozen + gameplay tables untouched', () => {
  assert.ok(Object.isFrozen(HOP_JUICE));
  assert.ok(HOP_JUICE.HOP_PUFF_COUNT > 0);
  // the banner helper reads — never writes — the frozen HOP table
  assert.equal(HOP.GAP_NARROW_EVERY_GATES, 10);
  assert.equal(HOP.GAP_MIN, 1.5);
});

// ---------------------------------------------------------------------------
// starHopper / harborHopper / trampoline — knob-only juice (frozen)
// ---------------------------------------------------------------------------

test('GP3 starHopper/harborHopper/trampoline: juice knobs frozen + sane', () => {
  for (const [name, knobs] of [
    ['HOPPER_JUICE', HOPPER_JUICE],
    ['HARBOR_JUICE', HARBOR_JUICE],
    ['TRAMP_JUICE', TRAMP_JUICE],
  ]) {
    assert.ok(Object.isFrozen(knobs), `${name} frozen`);
    for (const [k, v] of Object.entries(knobs)) {
      assert.ok(Number.isFinite(v) && v > 0, `${name}.${k} positive number`);
    }
  }
  // tween lengths stay sub-second so celebrations never block gameplay reads
  assert.ok(HOPPER_JUICE.BARREL_ROLL_SEC < 1);
  assert.ok(HOPPER_JUICE.POP_SEC < 1);
  assert.ok(HARBOR_JUICE.CRATE_POP_SEC < 1);
  assert.ok(TRAMP_JUICE.SHOCKWAVE_SEC < 1);
});

// ---------------------------------------------------------------------------
// basketBounce
// ---------------------------------------------------------------------------

test('GP3 basketBounce: isOnFire lights at 3+ consecutive swishes', () => {
  assert.equal(BASKET_JUICE.ON_FIRE_FROM, 3);
  assert.equal(isOnFire(0), false);
  assert.equal(isOnFire(1), false);
  assert.equal(isOnFire(2), false);
  assert.equal(isOnFire(3), true);
  assert.equal(isOnFire(7), true);
});

test('GP3 basketBounce: on-fire beat is juice-only — scoreShot stays §C6.1', () => {
  // walk a 4-swish streak through the REAL scorer: the on-fire banner at
  // streak 3 must not add points beyond the frozen swish-streak extra
  let streak = 0;
  const paid = [];
  for (let i = 0; i < 4; i += 1) {
    const r = scoreShot({ basket: true, bank: false, swish: true }, streak, false);
    streak = r.swishStreak;
    paid.push(r.points);
  }
  assert.deepEqual(paid, [
    BASKET.POINTS_BASKET,
    BASKET.POINTS_BASKET + BASKET.POINTS_SWISH_EXTRA,
    BASKET.POINTS_BASKET + BASKET.POINTS_SWISH_EXTRA,
    BASKET.POINTS_BASKET + BASKET.POINTS_SWISH_EXTRA,
  ]);
  assert.equal(streak, 4);
});

// ---------------------------------------------------------------------------
// strings module (EN + DE parity — project i18n rule)
// ---------------------------------------------------------------------------

test('GP3 strings: v4-gpgroup3.js keeps EN/DE key parity', () => {
  assert.deepEqual(Object.keys(GP3_EN).sort(), Object.keys(GP3_DE).sort());
  for (const key of Object.keys(GP3_EN)) {
    assert.ok(key.startsWith('gp3.'), `${key} namespaced`);
    assert.ok(GP3_EN[key].length > 0 && GP3_DE[key].length > 0, `${key} non-empty`);
  }
});
