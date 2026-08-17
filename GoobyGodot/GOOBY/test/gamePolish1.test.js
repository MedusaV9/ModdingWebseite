// GAME-POLISH-1 (carrotCatch/carrotGuard/gardenRush/fishingPond/ghostHunt/
// bubblePop juice pass): pure-logic tests for the new celebration-milestone
// helpers. These cues are STRICTLY audiovisual — the assertions here pin that
// they cannot drift into the frozen §C6.1 scoring tables.
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  CATCH,
  COMBO_MILESTONE_EVERY,
  comboMilestone,
  applyCatchState,
} from '../src/minigames/games/carrotCatch.logic.js';
import {
  BUBBLE,
  MATCH_STREAK_EVERY,
  matchStreakMilestone,
  popResult,
} from '../src/minigames/games/bubblePop.logic.js';

test('GAME-POLISH-1 carrotCatch: comboMilestone fires exactly at ×5 streaks', () => {
  assert.equal(COMBO_MILESTONE_EVERY, 5);
  assert.equal(comboMilestone(0), false);
  for (let c = 1; c <= 30; c += 1) {
    assert.equal(comboMilestone(c), c % 5 === 0, `combo ${c}`);
  }
});

test('GAME-POLISH-1 carrotCatch: milestone is juice-only — scoring stays §C6.1', () => {
  // A 5-streak of +1 carrots pays exactly +5: no hidden milestone bonus.
  let state = { score: 0, combo: 0 };
  for (let i = 0; i < 5; i += 1) {
    state = applyCatchState(state, { kind: 'good', value: 1 });
  }
  assert.equal(state.combo, 5);
  assert.equal(comboMilestone(state.combo), true);
  assert.equal(state.score, 5);
  assert.equal(CATCH.DURATION_SEC, 60); // frozen table untouched
});

test('GAME-POLISH-1 bubblePop: matchStreakMilestone fires exactly at ×5 streaks', () => {
  assert.equal(MATCH_STREAK_EVERY, 5);
  assert.equal(matchStreakMilestone(0), false);
  for (let s = 1; s <= 30; s += 1) {
    assert.equal(matchStreakMilestone(s), s % 5 === 0, `streak ${s}`);
  }
});

test('GAME-POLISH-1 bubblePop: milestone is juice-only — pop deltas stay §C6.1', () => {
  // Five matches still pay 5 × MATCH_PTS with no milestone extra.
  let score = 0;
  for (let i = 0; i < 5; i += 1) {
    score += popResult({ kind: 'food', food: 'carrot' }, 'carrot').delta;
  }
  assert.equal(score, 5 * BUBBLE.MATCH_PTS);
  assert.equal(BUBBLE.MATCH_PTS, 2);
  assert.equal(BUBBLE.WRONG_PTS, -2);
  assert.equal(BUBBLE.SPIKY_PTS, -1);
});
