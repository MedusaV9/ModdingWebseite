// GAME-POLISH-4 (goalieGooby/miniGolf/rocketRescue/danceParty/pipeFlow juice
// pass): pure-logic tests pinning that the new *_JUICE presentation blocks
// are (a) frozen, sane numbers and (b) STRICTLY audiovisual — none of the
// frozen gameplay/scoring tables moved. danceParty additionally re-asserts
// the §D6/G14 seed/BPM contract surface stayed byte-identical in spirit:
// same seed → same chart, windows/points untouched.
import test from 'node:test';
import assert from 'node:assert/strict';

import { GOALIE, GOALIE_JUICE } from '../src/minigames/games/goalieGooby.logic.js';
import { GOLF, GOLF_JUICE, holeScore } from '../src/minigames/games/miniGolf.logic.js';
import { ROCKET, ROCKET_JUICE, roundScore } from '../src/minigames/games/rocketRescue.logic.js';
import { DANCE_TUNING, DANCE_JUICE, generatePattern } from '../src/minigames/games/danceParty.logic.js';
import { DANCE } from '../src/data/constants.js';
import { PIPE, PIPE_JUICE, pipeScore, tapEfficiencyBonus } from '../src/minigames/games/pipeFlow.logic.js';
import { EN as GP4_EN, DE as GP4_DE } from '../src/data/strings/v4-gpgroup4.js';

// ---------------------------------------------------------------------------
// juice blocks: frozen + plausible ranges (guards accidental gameplay reach)
// ---------------------------------------------------------------------------

test('GAME-POLISH-4: every *_JUICE block is frozen', () => {
  for (const [name, block] of Object.entries({ GOALIE_JUICE, GOLF_JUICE, ROCKET_JUICE, DANCE_JUICE, PIPE_JUICE })) {
    assert.equal(Object.isFrozen(block), true, `${name} must be frozen`);
    for (const [key, value] of Object.entries(block)) {
      assert.equal(typeof value, 'number', `${name}.${key} must be a plain number`);
      assert.equal(Number.isFinite(value), true, `${name}.${key} must be finite`);
    }
  }
});

test('GAME-POLISH-4: juice timings are sub-second one-shots (no slow-mo drift)', () => {
  for (const sec of [
    GOALIE_JUICE.RING_LIFE_SEC, GOLF_JUICE.RING_LIFE_SEC, GOLF_JUICE.PUTT_SQUASH_SEC,
    GOLF_JUICE.FLAG_POP_SEC, ROCKET_JUICE.TOUCH_SQUASH_SEC, ROCKET_JUICE.BEACON_POP_SEC,
    DANCE_JUICE.BURST_LIFE_SEC, DANCE_JUICE.BALL_POP_SEC, PIPE_JUICE.TILE_POP_SEC,
    PIPE_JUICE.HANDLE_SPIN_SEC,
  ]) {
    assert.ok(sec > 0 && sec <= 1, `juice timing ${sec} must be in (0, 1] s`);
  }
});

test('GAME-POLISH-4: squash/pop scales recover toward 1 (never collapse/explode)', () => {
  assert.ok(GOLF_JUICE.PUTT_SQUASH > 0.4 && GOLF_JUICE.PUTT_SQUASH < 1);
  assert.ok(ROCKET_JUICE.TOUCH_SQUASH > 0.4 && ROCKET_JUICE.TOUCH_SQUASH < 1);
  for (const pop of [GOLF_JUICE.FLAG_POP_SCALE, ROCKET_JUICE.BEACON_POP_SCALE,
    DANCE_JUICE.BALL_POP_SCALE, PIPE_JUICE.TILE_POP_SCALE, GOALIE_JUICE.GLOVE_PUNCH_SCALE,
    GOALIE_JUICE.PIP_POP_SCALE]) {
    assert.ok(pop > 1 && pop <= 3, `pop scale ${pop} must be in (1, 3]`);
  }
});

// ---------------------------------------------------------------------------
// goalieGooby: landscape framing constants stay coherent with gameplay lanes
// ---------------------------------------------------------------------------

test('GAME-POLISH-4 goalie: landscape framing pulls in and widens vs. portrait', () => {
  assert.ok(GOALIE_JUICE.CAM_Z_LANDSCAPE < GOALIE_JUICE.CAM_Z_PORTRAIT);
  assert.ok(GOALIE_JUICE.GOAL_HALF_W_LANDSCAPE > GOALIE_JUICE.GOAL_HALF_W_PORTRAIT);
  // gameplay surface untouched: 5 lanes, frozen §C table
  assert.equal(GOALIE.LANES, 5);
  assert.equal(Object.isFrozen(GOALIE), true);
});

// ---------------------------------------------------------------------------
// miniGolf: scoring table untouched by the juice pass
// ---------------------------------------------------------------------------

test('GAME-POLISH-4 golf: §C1.2 #6 per-hole scoring stays 30/20/12/6', () => {
  assert.equal(holeScore(1, 2), GOLF.SCORE_ACE);
  assert.equal(holeScore(2, 2), GOLF.SCORE_PAR);
  assert.equal(holeScore(3, 2), GOLF.SCORE_BOGEY);
  assert.equal(holeScore(9, 2), GOLF.SCORE_OTHER);
  assert.deepEqual(
    [GOLF.SCORE_ACE, GOLF.SCORE_PAR, GOLF.SCORE_BOGEY, GOLF.SCORE_OTHER],
    [30, 20, 12, 6]
  );
});

// ---------------------------------------------------------------------------
// rocketRescue: score formula untouched by the juice pass
// ---------------------------------------------------------------------------

test('GAME-POLISH-4 rocket: 30·rescued + fuel/2 + 5·soft stays intact', () => {
  assert.equal(roundScore(3, 40, 2), 30 * 3 + Math.floor(40 / ROCKET.FUEL_SCORE_DIVISOR) + 5 * 2);
  assert.equal(ROCKET.RESCUE_POINTS, 30);
  assert.equal(ROCKET.SOFT_LANDING_BONUS, 5);
});

// ---------------------------------------------------------------------------
// danceParty: the §D6/G14 contract surface is untouched (visual-only ruling)
// ---------------------------------------------------------------------------

test('GAME-POLISH-4 dance: PATTERN_SEED chart is bit-stable under the juice pass', () => {
  const a = generatePattern(DANCE.PATTERN_SEED, { durationSec: DANCE.DURATION_SEC });
  const b = generatePattern(DANCE.PATTERN_SEED, { durationSec: DANCE.DURATION_SEC });
  assert.deepEqual(a, b);
  assert.ok(a.length > 0);
  // frozen contract numbers referenced by the chart/judgment
  assert.equal(DANCE.BPM, 100);
  assert.equal(DANCE.PERFECT_MS, 70);
  assert.equal(DANCE.GOOD_MS, 140);
  assert.equal(Object.isFrozen(DANCE_TUNING), true);
});

test('GAME-POLISH-4 dance: DANCE_JUICE shares no keys with the tuning contract', () => {
  for (const key of Object.keys(DANCE_JUICE)) {
    assert.equal(key in DANCE_TUNING, false, `DANCE_JUICE.${key} must not shadow DANCE_TUNING`);
    assert.equal(key in DANCE, false, `DANCE_JUICE.${key} must not shadow DANCE`);
  }
});

// ---------------------------------------------------------------------------
// pipeFlow: bonus reveal is read-only — pipeScore stays the source of truth
// ---------------------------------------------------------------------------

test('GAME-POLISH-4 pipe: revealed bonus equals the pipeScore bonus term', () => {
  const solved = 3;
  const taps = 14;
  const optimal = 12;
  const bonus = tapEfficiencyBonus(taps, optimal);
  assert.equal(bonus, PIPE.BONUS_MAX); // extra 2 ≤ BONUS_FULL_EXTRA
  assert.equal(pipeScore(solved, taps, optimal), PIPE.SOLVE_POINTS * solved + bonus);
});

// ---------------------------------------------------------------------------
// v4-gpgroup4 strings: EN/DE parity + placeholder integrity
// ---------------------------------------------------------------------------

test('GAME-POLISH-4 strings: EN and DE cover identical keys with matching {vars}', () => {
  assert.deepEqual(Object.keys(GP4_EN).sort(), Object.keys(GP4_DE).sort());
  for (const key of Object.keys(GP4_EN)) {
    const vars = (text) => (text.match(/\{[a-z]+\}/g) ?? []).sort();
    assert.deepEqual(vars(GP4_EN[key]), vars(GP4_DE[key]), `placeholder mismatch in ${key}`);
    assert.ok(GP4_EN[key].length > 0 && GP4_DE[key].length > 0);
  }
});
