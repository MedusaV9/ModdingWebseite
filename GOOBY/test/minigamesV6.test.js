// V6/C3 — the 6.0 minigame wave (PLAN6 Wave C): Snail Mail („Schneckenpost",
// C2) + Star Lantern („Sternenlaterne", C1). Pins the two data-spine rows
// verbatim (coin/unlock/target/meta/strings — the minigamesV5.test.js shape)
// and smoke-checks both pure logic modules headlessly against the frozen §G5.3
// contract (applyDifficulty family + deterministic certification bots — the
// deep mechanics units live in C1/C2's lanternFloat.test.js/snailMail.test.js;
// the §G5.4 acceptance itself runs in difficultyCertification.test.js).
// C1/C2 merge CONCURRENTLY (PLAN6 Wave C): while a logic module is missing its
// smoke tests report TODO, never fail (difficultyCertification.test.js
// pattern), then auto-arm on merge.
import test from 'node:test';
import assert from 'node:assert/strict';

import { MINIGAME_IDS, MINIGAMES_BY_ID, computeCoins } from '../src/data/minigames.js';
import { COIN_TABLE, UNLOCKS } from '../src/data/constants.js';
import { TARGETS } from '../src/data/difficultyTargets.js';
import { EN, DE } from '../src/data/strings.js';
import { EN as V6_GAMES_EN, DE as V6_GAMES_DE } from '../src/data/strings/v6-games.js';

/** @type {Record<string, object|null>} gameId → logic module (null = pending C1/C2 merge) */
const logic = { lanternFloat: null, snailMail: null };
for (const id of Object.keys(logic)) {
  try {
    logic[id] = await import(`../src/minigames/games/${id}.logic.js`);
  } catch {
    logic[id] = null;
  }
}

// --------------------------------------------------------- Wave-C data spine

test('V6/C3: the two 6.0 coin rows and gates are verbatim', () => {
  assert.deepEqual({ ...COIN_TABLE.snailMail }, { divisor: 4, min: 4, max: 25 });
  assert.deepEqual({ ...COIN_TABLE.lanternFloat }, { divisor: 4, min: 4, max: 24 });
  assert.equal(UNLOCKS.MINIGAMES.snailMail, 6);
  assert.equal(UNLOCKS.MINIGAMES.lanternFloat, 7);
  // §G5.4 rows: capScore = divisor × rowMax, target ≈ 80 % of cap.
  assert.deepEqual({ ...TARGETS.snailMail }, { capScore: 100, target: 80, endless: '3 splashed (wet) deliveries' });
  assert.deepEqual({ ...TARGETS.lanternFloat }, { capScore: 96, target: 75, endless: '3 cloud bumps' });
});

test('V6/C3: metadata rows carry titleKey/minLevel/energy/icon + EN/DE titles', () => {
  for (const [id, level] of [['snailMail', 6], ['lanternFloat', 7]]) {
    assert.ok(MINIGAME_IDS.includes(id), `${id} in MINIGAME_IDS`);
    const m = MINIGAMES_BY_ID[id];
    assert.equal(m.titleKey, `mg.title.${id}`);
    assert.equal(m.minLevel, level, `${id} minLevel`);
    assert.equal(m.energyCost, 8, `${id} energy (§C6 default)`);
    assert.ok(typeof m.icon === 'string' && m.icon.length > 0, `${id} icon`);
    assert.equal(m.dev, undefined, `${id} is a shipping game`);
    assert.ok(EN[m.titleKey]?.length > 0, `${id} EN title`);
    assert.ok(DE[m.titleKey]?.length > 0, `${id} DE title`);
  }
  assert.equal(DE['mg.title.snailMail'], 'Schneckenpost');
  assert.equal(DE['mg.title.lanternFloat'], 'Sternenlaterne');
});

test('V6/C3: v6-games.js has full EN/DE parity and lands in the merged dicts', () => {
  const enKeys = Object.keys(V6_GAMES_EN).sort();
  const deKeys = Object.keys(V6_GAMES_DE).sort();
  assert.deepEqual(enKeys, deKeys, 'every v6-games key ships EN + DE');
  for (const key of enKeys) {
    assert.ok(V6_GAMES_EN[key].length > 0, `EN ${key} non-empty`);
    assert.ok(V6_GAMES_DE[key].length > 0, `DE ${key} non-empty`);
    assert.equal(EN[key], V6_GAMES_EN[key], `EN ${key} survives the strings.js spread`);
    assert.equal(DE[key], V6_GAMES_DE[key], `DE ${key} survives the strings.js spread`);
  }
});

test('V6/C3: typical raw ≈ 65 pays ~16c on both coin rows; clamps + daily ×2', () => {
  assert.equal(computeCoins(COIN_TABLE.snailMail, 65, false), 16);
  assert.equal(computeCoins(COIN_TABLE.lanternFloat, 65, false), 16);
  // clamps: score 0 → min, huge → max, daily ×2 after the clamp
  assert.equal(computeCoins(COIN_TABLE.snailMail, 0, false), 4);
  assert.equal(computeCoins(COIN_TABLE.lanternFloat, 0, false), 4);
  assert.equal(computeCoins(COIN_TABLE.snailMail, 9999, false), 25);
  assert.equal(computeCoins(COIN_TABLE.lanternFloat, 9999, false), 24);
  assert.equal(computeCoins(COIN_TABLE.snailMail, 9999, true), 50);
  assert.equal(computeCoins(COIN_TABLE.lanternFloat, 9999, true), 48);
});

// ---------------------------------------------- §G5.3 logic-module smoke
// (thin registry-level checks — deep mechanics live in C1/C2's own suites)

const SIMS = Object.freeze({
  lanternFloat: 'simulateLanternAutoplay',
  snailMail: 'simulateSnailAutoplay',
});

for (const id of Object.keys(logic)) {
  test(`V6/C3: ${id} difficulty family follows the §G5.3 contract`, (t) => {
    const mod = logic[id];
    if (!mod) {
      t.todo('TODO: logic module not merged yet (concurrent C1/C2 batch)');
      return;
    }
    assert.equal(typeof mod.applyDifficulty, 'function', `${id} exports applyDifficulty`);
    const base = mod.applyDifficulty(undefined, 'normal');
    assert.ok(Object.isFrozen(base), `${id} base tune frozen`);
    assert.equal(mod.applyDifficulty(undefined, 'banana'), base, 'unknown mode normalizes to Mittel');
    const easy = mod.applyDifficulty(undefined, 'easy');
    const hard = mod.applyDifficulty(undefined, 'hard');
    assert.ok(Object.isFrozen(easy) && Object.isFrozen(hard), 'derived tunes frozen');
    assert.notEqual(easy, base, 'Leicht derives a new tune');
    assert.notEqual(hard, base, 'Schwer derives a new tune');
    const endless = mod.applyDifficulty(undefined, 'endless');
    assert.equal(endless.ENDLESS, true, 'Endlos carries the end-condition flag');
    assert.equal(typeof mod.endlessShouldEnd, 'function', `${id} exports endlessShouldEnd`);
    assert.equal(typeof mod.applyScore, 'function', `${id} exports applyScore`);
    assert.equal(mod.applyScore(0, -5), 0, 'score floors at 0');
  });

  test(`V6/C3: ${id} certification bot is deterministic and terminates in Endlos`, (t) => {
    const mod = logic[id];
    if (!mod) {
      t.todo('TODO: logic module not merged yet (concurrent C1/C2 batch)');
      return;
    }
    const sim = mod[SIMS[id]];
    assert.equal(typeof sim, 'function', `${id} exports ${SIMS[id]} (frozen interface contract)`);
    const a = sim('hard', 42);
    const b = sim('hard', 42);
    assert.deepEqual(a, b, 'same seed + mode → same result');
    assert.ok(Number.isFinite(a.score) && a.score >= 0, 'finite score ≥ 0');
    const endless = sim('endless', 42);
    assert.ok(Number.isFinite(endless.score) && endless.score >= 0, 'Endlos terminates with a finite score');
  });
}
