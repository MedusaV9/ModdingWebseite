// GAME-JUICE / V6 Wave C / C4 (PLAN6): the measured bottom-six arcade games
// (memoryMatch, goobySays, pipeFlow, miniGolf, cityDrive+deliveryRush,
// veggieChop) got a feel/juice pass. These tests pin the hard constraints:
//   (a) every frozen scoring table is byte-identical (exact value pins),
//   (b) every NEW shake/flash site is reduced-motion gated (source scan),
//   (c) the drive pair gained NO camera shake (PLAN4 §C7.2/§G4.8 ruling),
//   (d) every audio.play('<id>') literal in the six games is mapped in
//       sfxMap.js (mirrors test/audioCoverage.test.js's literal scan),
//   (e) each game actually gained its named *_JUICE block + the audit's
//       concrete feedback call sites (floats/particles/sfx),
//   (f) the v6-juice strings module has EN/DE parity and every key is used.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { MEMORY, MEMORY_JUICE, memoryScore, timeBonus as memoryTimeBonus } from '../src/minigames/games/memoryMatch.logic.js';
import { SAYS, SAYS_JUICE, roundScore, speedBonus, giggleRound } from '../src/minigames/games/goobySays.logic.js';
import { PIPE, pipeScore } from '../src/minigames/games/pipeFlow.logic.js';
import { GOLF, holeScore } from '../src/minigames/games/miniGolf.logic.js';
import { DELIVERY, applyDrop, applyCrash, timeBonus as deliveryTimeBonus } from '../src/minigames/games/deliveryRush.logic.js';
import { CHOP, chopPoints } from '../src/minigames/games/veggieChop.logic.js';
import { getSfxDef } from '../src/audio/sfxMap.js';
import { EN as JUICE_EN, DE as JUICE_DE } from '../src/data/strings/v6-juice.js';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const GAMES = path.join(ROOT, 'src', 'minigames', 'games');
const read = (name) => fs.readFileSync(path.join(GAMES, name), 'utf8');

/** The nine game files this pass owns (views + the two owned logic files). */
const SRC = {
  memoryMatch: read('memoryMatch.js'),
  goobySays: read('goobySays.js'),
  pipeFlow: read('pipeFlow.js'),
  miniGolf: read('miniGolf.js'),
  cityDrive: read('cityDrive.js'),
  deliveryRush: read('deliveryRush.js'),
  veggieChop: read('veggieChop.js'),
};

/** assert `needle` exists in a game source (named-call-pattern presence). */
function has(game, needle) {
  assert.ok(SRC[game].includes(needle), `${game}.js must contain: ${needle}`);
}

/** assert the reduced-motion gate appears BEFORE the gated juice site. */
function gatedBefore(game, gate, site) {
  const src = SRC[game];
  const gateIdx = src.indexOf(gate);
  const siteIdx = src.indexOf(site);
  assert.ok(gateIdx >= 0, `${game}.js: missing gate '${gate}'`);
  assert.ok(siteIdx >= 0, `${game}.js: missing juice site '${site}'`);
  assert.ok(gateIdx < siteIdx, `${game}.js: '${site}' must sit behind '${gate}'`);
}

// ---------------------------------------------------------------------------
// (a) frozen scoring tables: exact current values, byte-for-byte semantics
// ---------------------------------------------------------------------------

test('GP6 memory: §C6.1 20−misses+bonus(0–8)+20 clear stays pinned', () => {
  assert.deepEqual(
    [MEMORY.SCORE_BASE, MEMORY.TIME_BONUS_MAX, MEMORY.TIME_BONUS_STEP_SEC, MEMORY.CLEAR_BONUS, MEMORY.PEEK_EARN_MATCHES],
    [20, 8, 5, 20, 3]
  );
  assert.equal(memoryTimeBonus(0, { pairs: 8 }), 8);
  assert.equal(memoryScore(0, 0, { pairs: 8 }), 48); // 20 − 0 + 8 + 20
  assert.equal(memoryScore(4, 60, { pairs: 8 }), 20 + 20 - 4 + memoryTimeBonus(60, { pairs: 8 }));
});

test('GP6 says: §C1.2 10·rounds + speedBonus(0–8) stays pinned', () => {
  assert.deepEqual([SAYS.ROUND_POINTS, SAYS.SPEED_BONUS_MAX, SAYS.REACTION_FULL_MS], [10, 8, 500]);
  assert.equal(speedBonus(400), 8);
  assert.equal(roundScore(3, 400), 38); // 10·3 + 8
  assert.equal(roundScore(0, 5000), 0);
});

test('GP6 pipe: §C1.2 #9 25·solved + bonus(≤10) − 5·leaks stays pinned', () => {
  assert.deepEqual([PIPE.SOLVE_POINTS, PIPE.BONUS_MAX, PIPE.LEAK_PENALTY], [25, 10, 5]);
  assert.equal(pipeScore(2, 10, 10), 25 * 2 + PIPE.BONUS_MAX); // optimal taps → full bonus
});

test('GP6 golf: §C1.2 #6 per-hole 30/20/12/6 stays pinned', () => {
  assert.deepEqual(
    [GOLF.SCORE_ACE, GOLF.SCORE_PAR, GOLF.SCORE_BOGEY, GOLF.SCORE_OTHER],
    [30, 20, 12, 6]
  );
  assert.equal(holeScore(1, 3), 30);
  assert.equal(holeScore(3, 3), 20);
  assert.equal(holeScore(4, 3), 12);
  assert.equal(holeScore(9, 3), 6);
});

test('GP6 delivery: §C1.2 #5 +50/−5(floor 0)/120s bonus/fragile 20|15 stays pinned', () => {
  assert.deepEqual(
    [DELIVERY.DROP_POINTS, DELIVERY.CRASH_PENALTY, DELIVERY.TIME_BONUS_FROM_SEC,
      DELIVERY.FRAGILE_CRASH_PENALTY, DELIVERY.FRAGILE_CLEAN_BONUS, DELIVERY.COIN_POINTS],
    [50, 5, 120, 20, 15, 3]
  );
  assert.equal(applyDrop(0), 50);
  assert.equal(applyCrash(3), 0); // floor 0, never negative
  assert.equal(applyCrash(10), 5);
  assert.equal(deliveryTimeBonus(100, DELIVERY), 20);
});

test('GP6 chop: §C1.2 #4 +2/+1 combo/−3 junk/3 misses stays pinned', () => {
  assert.deepEqual(
    [CHOP.CHOP_PTS, CHOP.COMBO_BONUS, CHOP.JUNK_PTS, CHOP.STUN_SEC, CHOP.MAX_MISSES],
    [2, 1, -3, 0.5, 3]
  );
  assert.equal(chopPoints(1), 2);
  assert.equal(chopPoints(2), 3);
});

test('GP6 cityDrive: coin pickup still scores exactly +1 (no .logic file — source pin)', () => {
  // the arcade/trip coin loop keeps `ctx.onScore(1)` — the only score call
  // this juice pass sits next to (floats/sfx were added AROUND it)
  has('cityDrive', 'ctx.onScore(1);');
});

// ---------------------------------------------------------------------------
// *_JUICE blocks: frozen, numeric, audiovisual-only (GP-1…4 invariant)
// ---------------------------------------------------------------------------

test('GP6: owned-logic *_JUICE blocks are frozen plain-number tables', () => {
  for (const [name, block] of Object.entries({ MEMORY_JUICE, SAYS_JUICE })) {
    assert.equal(Object.isFrozen(block), true, `${name} must be frozen`);
    for (const [key, value] of Object.entries(block)) {
      assert.equal(typeof value, 'number', `${name}.${key} must be a plain number`);
      assert.equal(Number.isFinite(value), true, `${name}.${key} must be finite`);
    }
  }
});

test('GP6: *_JUICE blocks share no keys with their frozen gameplay tables', () => {
  for (const key of Object.keys(MEMORY_JUICE)) {
    assert.equal(key in MEMORY, false, `MEMORY_JUICE.${key} must not shadow MEMORY`);
  }
  for (const key of Object.keys(SAYS_JUICE)) {
    assert.equal(key in SAYS, false, `SAYS_JUICE.${key} must not shadow SAYS`);
  }
});

test('GP6: view-module *_JUICE6 blocks exist and are frozen (source scan — the views import three/DOM)', () => {
  const blocks = {
    pipeFlow: 'export const PIPE_JUICE6 = Object.freeze({',
    miniGolf: 'export const GOLF_JUICE6 = Object.freeze({',
    cityDrive: 'export const DRIVE_JUICE6 = Object.freeze({',
    deliveryRush: 'export const DELIVERY_JUICE6 = Object.freeze({',
    veggieChop: 'export const CHOP_JUICE6 = Object.freeze({',
  };
  for (const [game, decl] of Object.entries(blocks)) has(game, decl);
});

test('GP6: juice timings are sub-second one-shots (no slow-mo drift)', () => {
  for (const sec of [
    MEMORY_JUICE.CLEAR_HOP_SEC, SAYS_JUICE.PRESS_DIP_SEC, SAYS_JUICE.FAIL_SHAKE_SEC,
  ]) {
    assert.ok(sec > 0 && sec <= 1, `juice timing ${sec} must be in (0, 1] s`);
  }
  assert.ok(giggleRound(5) && giggleRound(10) && !giggleRound(4) && !giggleRound(0));
});

// ---------------------------------------------------------------------------
// (b) reduced-motion gates sit in front of every NEW shake/flash site
// ---------------------------------------------------------------------------

test('GP6 gating: memoryMatch board-clear cascade is RM-gated', () => {
  has('memoryMatch', "import { prefersReducedMotion }");
  gatedBefore('memoryMatch', 'if (!prefersReducedMotion()) {', 'MEMORY_JUICE.CLEAR_HOP_SEC');
});

test('GP6 gating: goobySays fail micro-shake is RM-gated', () => {
  has('goobySays', "import { prefersReducedMotion }");
  gatedBefore('goobySays', 'if (!prefersReducedMotion()) {', 'SAYS_JUICE.FAIL_SHAKE_SEC');
});

test('GP6 gating: pipeFlow tap pop + connection shimmer are RM-gated', () => {
  gatedBefore('pipeFlow', 'if (!prefersReducedMotion()) {', 'PIPE_JUICE6.TAP_POP_SEC');
  gatedBefore('pipeFlow', 'if (!prefersReducedMotion()) {', 'PIPE_JUICE6.SHIMMER_SEC');
});

test('GP6 gating: miniGolf bank-flash ring is RM-gated (early return)', () => {
  gatedBefore('miniGolf', 'if (prefersReducedMotion()) return;', 'GOLF_JUICE6.BANK_RING_SEC');
});

test('GP6 gating: veggieChop junk shake + frenzy tint + half pop are RM-gated', () => {
  gatedBefore('veggieChop', 'if (!prefersReducedMotion()) {', 'CHOP_JUICE6.JUNK_SHAKE_SEC');
  gatedBefore('veggieChop', 'if (!prefersReducedMotion()) {', 'CHOP_JUICE6.FRENZY_TINT_SEC');
  gatedBefore('veggieChop', 'if (!prefersReducedMotion()) {', 'CHOP_JUICE6.HALF_POP_SEC');
});

test('GP6 gating: drive-pair passenger lean + door glow respect this.reduceMotion', () => {
  has('cityDrive', 'const leanTarget = this.reduceMotion');
  has('deliveryRush', 'if (this.reduceMotion || !this.doorGlow) return;');
});

// ---------------------------------------------------------------------------
// (c) drive pair: NO added camera shake (PLAN4 §C7.2/§G4.8 ruling)
// ---------------------------------------------------------------------------

test('GP6 no-shake: cityDrive/deliveryRush keep exactly the ONE legacy crash shake', () => {
  for (const game of ['cityDrive', 'deliveryRush']) {
    const src = SRC[game];
    const writes = src.match(/this\.shake = /g) ?? [];
    // init (= 0), crash (= 1), per-frame decay — and nothing else
    assert.equal(writes.length, 3, `${game}.js: this.shake write sites must stay at 3`);
    assert.equal((src.match(/this\.shake = 1/g) ?? []).length, 1,
      `${game}.js: only the legacy crash() may pump the shake`);
    // the V6 juice blocks explicitly re-state the ruling
    assert.ok(src.includes('NO camera shake'), `${game}.js: §C7.2 ruling comment present`);
  }
});

// ---------------------------------------------------------------------------
// (d) every audio.play literal in the six games is mapped in sfxMap.js
// ---------------------------------------------------------------------------

test('GP6 audio: zero unmapped audio.play ids across the six juiced games', () => {
  const unmapped = [];
  for (const [game, src] of Object.entries(SRC)) {
    for (const m of src.matchAll(/audio(?:\??\.)play\(\s*'([^']+)'/g)) {
      if (!getSfxDef(m[1])) unmapped.push(`${game}: ${m[1]}`);
    }
  }
  assert.deepEqual(unmapped, [], `unmapped sfx ids: ${unmapped.join(', ')}`);
});

test('GP6 audio: the ids this pass newly leans on are sample/voice-backed', () => {
  for (const id of ['combo.up', 'gooby.gasp', 'gooby.giggle', 'garden.harvestReady', 'ui.count', 'coin.get']) {
    assert.ok(getSfxDef(id), `${id} must be mapped in sfxMap.js`);
  }
});

// ---------------------------------------------------------------------------
// (e) each game gained the audit's concrete feedback call sites
// ---------------------------------------------------------------------------

test('GP6 memoryMatch: pair/streak floats + streak confetti + peek gasp landed', () => {
  has('memoryMatch', "tx('v6.juice.pair')");
  has('memoryMatch', "tx('v6.juice.streak'");
  has('memoryMatch', 'MEMORY_JUICE.STREAK_CONFETTI');
  has('memoryMatch', 'MEMORY_JUICE.TOKEN_PULSE_HZ');
  has('memoryMatch', "'gooby.gasp'");
  has('memoryMatch', 'this.floats.spawn');
});

test('GP6 goobySays: press dip + round float + conductor bounce + giggle landed', () => {
  has('goobySays', 'SAYS_JUICE.PRESS_DIP_Y');
  has('goobySays', 'SAYS_JUICE.CONDUCT_BOUNCE_THROTTLE_SEC');
  has('goobySays', 'giggleRound(this.round)');
  has('goobySays', "'gooby.giggle'");
  has('goobySays', 'this.floats.spawn');
});

test('GP6 pipeFlow: easeOutBack tap + shimmer + solve floats + bloom beat landed', () => {
  has('pipeFlow', 'ease: easings.easeOutBack');
  has('pipeFlow', 'PIPE_JUICE6.SHIMMER_STAGGER_SEC');
  has('pipeFlow', "tx('v6.juice.flow')");
  has('pipeFlow', "'garden.harvestReady'");
  has('pipeFlow', "'hopper.gold'");
  has('pipeFlow', 'PIPE_JUICE6.FLOWER_SPARKLES');
  has('pipeFlow', 'this.floats.spawn');
});

test('GP6 miniGolf: sink float + roll trail + power ticks + bank ring landed', () => {
  has('miniGolf', 'GOLF_JUICE6.TRAIL_MIN_SPEED');
  has('miniGolf', 'GOLF_JUICE6.POWER_TICK_THIRDS');
  has('miniGolf', "'ui.count'");
  has('miniGolf', 'flashBankRing(');
  has('miniGolf', 'this.floats.spawn');
});

test('GP6 cityDrive: coin float + arrival float + passenger lean landed', () => {
  has('cityDrive', "this.floats.spawn('+1'");
  has('cityDrive', "tx('v6.juice.arrived')");
  has('cityDrive', 'DRIVE_JUICE6.LEAN_MAX_RAD');
  has('cityDrive', 'createFloatTexts');
});

test('GP6 deliveryRush: delivered/tip floats + hearts + door glow landed', () => {
  has('deliveryRush', "tx('v6.juice.delivered')");
  has('deliveryRush', 'DELIVERY_JUICE6.DELIVER_HEARTS');
  has('deliveryRush', 'flashDoorGlow(');
  has('deliveryRush', "'coin.get'");
  has('deliveryRush', "'hearts'");
});

test('GP6 veggieChop: half pop + chop confetti + frenzy entrance + junk shake landed', () => {
  has('veggieChop', 'CHOP_JUICE6.HALF_POP_SCALE');
  has('veggieChop', 'CHOP_JUICE6.CHOP_CONFETTI');
  has('veggieChop', 'CHOP_JUICE6.FRENZY_CONFETTI');
  has('veggieChop', "tx('v6.juice.frenzy')");
  has('veggieChop', 'CHOP_JUICE6.JUNK_SHAKE_AMP');
});

// ---------------------------------------------------------------------------
// (f) v6-juice strings module: EN/DE parity, v6.juice.* keys, all keys used
// ---------------------------------------------------------------------------

test('GP6 strings: EN and DE cover identical v6.juice.* keys with matching {vars}', () => {
  assert.deepEqual(Object.keys(JUICE_EN).sort(), Object.keys(JUICE_DE).sort());
  assert.ok(Object.keys(JUICE_EN).length >= 6);
  for (const key of Object.keys(JUICE_EN)) {
    assert.match(key, /^v6\.juice\./, `${key} must be namespaced v6.juice.*`);
    const vars = (text) => (text.match(/\{[a-z]+\}/g) ?? []).sort();
    assert.deepEqual(vars(JUICE_EN[key]), vars(JUICE_DE[key]), `placeholder mismatch in ${key}`);
    assert.ok(JUICE_EN[key].length > 0 && JUICE_DE[key].length > 0);
  }
});

test('GP6 strings: every v6.juice.* key is actually consumed by a juiced game', () => {
  const all = Object.values(SRC).join('\n');
  for (const key of Object.keys(JUICE_EN)) {
    assert.ok(all.includes(`'${key}'`), `${key} is declared but never used`);
  }
});
