// V5/G06 — the 5.0 minigame wave (PLAN5 §V5): Tea Party („Teestube", §V5.1)
// + Hide & Seek („Guck-guck-Garten", §V5.2). Pins the two data-spine rows
// verbatim (coin/unlock/target/meta/strings) and unit-tests both pure logic
// modules headlessly (§B rule): band rolls, pour rating, streak cadence,
// wave ramps, hider draws, difficulty families and the deterministic
// certification bots (the §G5.4 acceptance itself runs in
// difficultyCertification.test.js — these are the mechanics-level checks).
import test from 'node:test';
import assert from 'node:assert/strict';

import { MINIGAME_IDS, MINIGAMES_BY_ID, computeCoins } from '../src/data/minigames.js';
import { COIN_TABLE, UNLOCKS } from '../src/data/constants.js';
import { TARGETS } from '../src/data/difficultyTargets.js';
import { EN, DE } from '../src/data/strings.js';
import {
  TEA,
  applyDifficulty as teaDifficulty,
  rollBand,
  fillAfter,
  pourResult,
  streakBonusAt,
  serveIntervalAt,
  applyScore as teaScore,
  endlessShouldEnd as teaEndlessEnd,
  simulateTeaAutoplay,
} from '../src/minigames/games/teaParty.logic.js';
import {
  SEEK,
  applyDifficulty as seekDifficulty,
  spotCount,
  hidersForWave,
  waveSecFor,
  rollHiders,
  applyScore as seekScore,
  endlessShouldEnd as seekEndlessEnd,
  simulateSeekAutoplay,
} from '../src/minigames/games/hideSeek.logic.js';

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

// --------------------------------------------------------- §V5 data spine

test('§V5: the two 5.0 coin rows and gates are verbatim', () => {
  assert.deepEqual({ ...COIN_TABLE.teaParty }, { divisor: 4, min: 4, max: 26 });
  assert.deepEqual({ ...COIN_TABLE.hideSeek }, { divisor: 5, min: 4, max: 20 });
  assert.equal(UNLOCKS.MINIGAMES.hideSeek, 2);
  assert.equal(UNLOCKS.MINIGAMES.teaParty, 3);
  // §G5.4 rows: capScore = divisor × rowMax, target ≈ 80 % of cap.
  assert.deepEqual({ ...TARGETS.teaParty }, { capScore: 104, target: 85, endless: '3 spilled/missed cups' });
  assert.deepEqual({ ...TARGETS.hideSeek }, { capScore: 100, target: 80, endless: '3 expired (uncleared) waves' });
});

test('§V5: metadata rows carry titleKey/minLevel/energy/icon + EN/DE titles', () => {
  for (const [id, level] of [['teaParty', 3], ['hideSeek', 2]]) {
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
  assert.equal(DE['mg.title.teaParty'], 'Teestube');
  assert.equal(DE['mg.title.hideSeek'], 'Guck-guck-Garten');
});

test('§V5: in-game banner/floater strings have EN/DE parity', () => {
  const keys = [
    'mg.tea.perfect', 'mg.tea.good', 'mg.tea.overflow', 'mg.tea.miss',
    'mg.tea.streak', 'mg.tea.spills',
    'mg.seek.found', 'mg.seek.empty', 'mg.seek.waveClear', 'mg.seek.waveNew',
    'mg.seek.expired',
  ];
  for (const key of keys) {
    assert.ok(EN[key]?.length > 0, `EN ${key}`);
    assert.ok(DE[key]?.length > 0, `DE ${key}`);
  }
});

test('§V5.1: typical raw ≈ 70 pays ~17c; §V5.2 typical raw ≈ 70 pays ~14c', () => {
  assert.equal(computeCoins(COIN_TABLE.teaParty, 70, false), 17);
  assert.equal(computeCoins(COIN_TABLE.hideSeek, 70, false), 14);
  // clamps: score 0 → min, huge → max, daily ×2 after the clamp
  assert.equal(computeCoins(COIN_TABLE.teaParty, 0, false), 4);
  assert.equal(computeCoins(COIN_TABLE.hideSeek, 9999, false), 20);
  assert.equal(computeCoins(COIN_TABLE.teaParty, 9999, true), 52);
});

// --------------------------------------------------- teaParty pure logic

test('teaParty: rollBand stays inside the §V5.1 center range with tuned widths', () => {
  const rng = rngOf(7);
  for (let i = 0; i < 200; i += 1) {
    const band = rollBand(rng);
    assert.ok(band.center >= TEA.BAND_CENTER_MIN && band.center <= TEA.BAND_CENTER_MAX);
    assert.equal(band.half, TEA.BAND_HALF_W);
    assert.equal(band.perfectHalf, TEA.PERFECT_HALF_W);
    assert.ok(band.perfectHalf < band.half, 'perfect zone nests inside the band');
  }
});

test('teaParty: fillAfter integrates FILL_RATE and never goes negative', () => {
  assert.equal(fillAfter(0, 1), TEA.FILL_RATE);
  assert.equal(fillAfter(0.5, 0.5), 0.5 + TEA.FILL_RATE * 0.5);
  assert.equal(fillAfter(-1, 0), 0);
  assert.equal(fillAfter(0.3, -5), 0.3, 'hostile negative dt is ignored');
});

test('teaParty: pourResult rates perfect/good/miss/overflow per §V5.1', () => {
  const band = { center: 0.7, half: TEA.BAND_HALF_W, perfectHalf: TEA.PERFECT_HALF_W };
  assert.deepEqual(pourResult(0.7, band), { result: 'perfect', points: TEA.PERFECT_PTS, overflow: false });
  assert.deepEqual(pourResult(0.7 + TEA.PERFECT_HALF_W * 0.99, band), { result: 'perfect', points: 6, overflow: false });
  assert.deepEqual(pourResult(0.7 + TEA.BAND_HALF_W * 0.99, band), { result: 'good', points: TEA.GOOD_PTS, overflow: false });
  assert.deepEqual(pourResult(0.7 - TEA.BAND_HALF_W - 0.001, band), { result: 'miss', points: 0, overflow: false });
  // past the rim always spills — even when the band sits high
  const high = { center: 0.99, half: 0.075, perfectHalf: 0.028 };
  assert.deepEqual(pourResult(1.0, high), { result: 'miss', points: 0, overflow: true });
});

test('teaParty: every 3rd consecutive perfect pays the +2 streak bonus', () => {
  assert.equal(streakBonusAt(0), 0);
  assert.equal(streakBonusAt(1), 0);
  assert.equal(streakBonusAt(2), 0);
  assert.equal(streakBonusAt(3), TEA.STREAK_BONUS);
  assert.equal(streakBonusAt(4), 0);
  assert.equal(streakBonusAt(6), TEA.STREAK_BONUS);
});

test('teaParty: serve cadence tightens linearly from start to end', () => {
  assert.equal(serveIntervalAt(0), TEA.SERVE_SEC_START);
  assert.equal(serveIntervalAt(TEA.DURATION_SEC), TEA.SERVE_SEC_END);
  const mid = serveIntervalAt(TEA.DURATION_SEC / 2);
  assert.ok(mid < TEA.SERVE_SEC_START && mid > TEA.SERVE_SEC_END);
  assert.equal(serveIntervalAt(9999), TEA.SERVE_SEC_END, 'clamped past the end');
});

test('teaParty: score floors at 0; Endlos ends on the 3rd spill only in endless', () => {
  assert.equal(teaScore(0, -5), 0);
  assert.equal(teaScore(10, 6), 16);
  assert.equal(teaEndlessEnd(99, TEA), false, 'timed runs never end on spills');
  const endless = teaDifficulty(TEA, 'endless');
  assert.equal(teaEndlessEnd(2, endless), false);
  assert.equal(teaEndlessEnd(3, endless), true);
});

test('teaParty: difficulty family — Leicht wider/slower, Schwer narrower/faster', () => {
  const easy = teaDifficulty(TEA, 'easy');
  const hard = teaDifficulty(TEA, 'hard');
  assert.equal(teaDifficulty(TEA, 'normal'), TEA, 'Mittel returns the exact base object');
  assert.equal(teaDifficulty(TEA, 'banana'), TEA, 'unknown mode normalizes to Mittel');
  assert.ok(easy.BAND_HALF_W > TEA.BAND_HALF_W && hard.BAND_HALF_W < TEA.BAND_HALF_W);
  assert.ok(easy.FILL_RATE < TEA.FILL_RATE && hard.FILL_RATE > TEA.FILL_RATE);
  assert.ok(easy.DURATION_SEC > TEA.DURATION_SEC);
  assert.equal(teaDifficulty(TEA, 'endless').ENDLESS, true);
  assert.ok(Object.isFrozen(easy) && Object.isFrozen(hard));
});

test('teaParty: certification bot is deterministic and terminates in Endlos', () => {
  const a = simulateTeaAutoplay('hard', 42);
  const b = simulateTeaAutoplay('hard', 42);
  assert.deepEqual(a, b);
  const endless = simulateTeaAutoplay('endless', 42);
  assert.ok(endless.spills <= 3 && Number.isFinite(endless.score));
});

// --------------------------------------------------- hideSeek pure logic

test('hideSeek: 3×4 grid; hider count ramps 3 → 5; wave timer ramps 13 → 9', () => {
  assert.equal(spotCount(), SEEK.COLS * SEEK.ROWS);
  assert.equal(spotCount(), 12);
  assert.equal(hidersForWave(0), SEEK.WAVE_HIDERS_START);
  assert.equal(hidersForWave(SEEK.WAVE_RAMP_WAVES), SEEK.WAVE_HIDERS_MAX);
  assert.equal(hidersForWave(99), SEEK.WAVE_HIDERS_MAX, 'stays at max after the ramp');
  assert.equal(waveSecFor(0), SEEK.WAVE_SEC_START);
  assert.equal(waveSecFor(SEEK.WAVE_RAMP_WAVES), SEEK.WAVE_SEC_END);
  assert.ok(waveSecFor(2) < SEEK.WAVE_SEC_START && waveSecFor(2) > SEEK.WAVE_SEC_END);
});

test('hideSeek: rollHiders draws unique ascending spots, deterministic per rng', () => {
  for (let wave = 0; wave < 8; wave += 1) {
    const spots = rollHiders(rngOf(wave + 1), wave);
    assert.equal(spots.length, hidersForWave(wave));
    assert.equal(new Set(spots).size, spots.length, 'unique spots');
    for (const s of spots) assert.ok(s >= 0 && s < spotCount());
    assert.deepEqual(spots, [...spots].sort((x, y) => x - y), 'ascending');
  }
  assert.deepEqual(rollHiders(rngOf(5), 2), rollHiders(rngOf(5), 2), 'deterministic');
});

test('hideSeek: score floors at 0; Endlos ends on the 3rd expired wave only in endless', () => {
  assert.equal(seekScore(0, -3), 0);
  assert.equal(seekScore(4, 2), 6);
  assert.equal(seekEndlessEnd(99, SEEK), false, 'timed runs never end on expiry');
  const endless = seekDifficulty(SEEK, 'endless');
  assert.equal(seekEndlessEnd(2, endless), false);
  assert.equal(seekEndlessEnd(3, endless), true);
});

test('hideSeek: difficulty family — Leicht longer waves/peeks, Schwer shorter/rarer', () => {
  const easy = seekDifficulty(SEEK, 'easy');
  const hard = seekDifficulty(SEEK, 'hard');
  assert.equal(seekDifficulty(SEEK, 'normal'), SEEK, 'Mittel returns the exact base object');
  assert.equal(seekDifficulty(SEEK, 'banana'), SEEK, 'unknown mode normalizes to Mittel');
  assert.ok(easy.WAVE_SEC_START > SEEK.WAVE_SEC_START && hard.WAVE_SEC_START < SEEK.WAVE_SEC_START);
  assert.ok(easy.PEEK_DURATION_SEC > SEEK.PEEK_DURATION_SEC && hard.PEEK_DURATION_SEC < SEEK.PEEK_DURATION_SEC);
  assert.ok(hard.PEEK_EVERY_SEC > SEEK.PEEK_EVERY_SEC, 'Schwer peeks are rarer');
  assert.equal(seekDifficulty(SEEK, 'endless').ENDLESS, true);
  assert.ok(Object.isFrozen(easy) && Object.isFrozen(hard));
});

test('hideSeek: certification bot is deterministic and terminates in Endlos', () => {
  const a = simulateSeekAutoplay('hard', 42);
  const b = simulateSeekAutoplay('hard', 42);
  assert.deepEqual(a, b);
  const endless = simulateSeekAutoplay('endless', 42);
  assert.ok(endless.expired <= 3 && Number.isFinite(endless.score));
});
