// V4/GAME-POLISH-2 (group 2: burgerBuild, pancakeTower, veggieChop,
// purblePlace, memoryMatch, goobySays): string-module parity + the pure-logic
// beats the new juice hangs off (triple-chop combo, pancake milestones).

import test from 'node:test';
import assert from 'node:assert/strict';

import { EN as GP2_EN, DE as GP2_DE } from '../src/data/strings/v4-gpgroup2.js';
import { chopPoints, comboAfterHit } from '../src/minigames/games/veggieChop.logic.js';

// ---------------------------------------------------------------------------
// v4-gpgroup2 strings: EN/DE parity + placeholder integrity
// ---------------------------------------------------------------------------

test('GAME-POLISH-2 strings: EN and DE cover identical keys with matching {vars}', () => {
  assert.deepEqual(Object.keys(GP2_EN).sort(), Object.keys(GP2_DE).sort());
  for (const key of Object.keys(GP2_EN)) {
    const vars = (text) => (text.match(/\{[a-z]+\}/g) ?? []).sort();
    assert.deepEqual(vars(GP2_EN[key]), vars(GP2_DE[key]), `placeholder mismatch in ${key}`);
    assert.ok(GP2_EN[key].length > 0 && GP2_DE[key].length > 0);
    assert.ok(key.startsWith('gp2.'), `${key} must live in the gp2.* namespace`);
  }
});

// ---------------------------------------------------------------------------
// veggieChop: the triple-chop juice beat rides the same-swipe combo counter
// ---------------------------------------------------------------------------

test('GAME-POLISH-2 veggieChop: a third same-swipe chop is reachable and pays more', () => {
  let combo = 0;
  combo = comboAfterHit(combo, 'veggie');
  combo = comboAfterHit(combo, 'veggie');
  combo = comboAfterHit(combo, 'veggie');
  assert.equal(combo, 3, 'three clean chops in one stroke reach combo 3');
  assert.ok(chopPoints(3) > chopPoints(1), 'combo chops outscore the first chop');
});

test('GAME-POLISH-2 veggieChop: junk resets the swipe combo (no triple after a splash)', () => {
  const combo = comboAfterHit(2, 'junk');
  assert.equal(combo, 0);
});
