// GAME-POLISH-5 (cityDrive/deliveryRush/toyRacer/shoppingSurf/goobyWelt
// juice pass): pure-logic tests for the new cosmetic helpers. Every cue here
// is STRICTLY audiovisual — the assertions pin that the near-miss tracker,
// the parcel-pop arc and the software-GL probe cannot drift into the frozen
// scoring/crash tables (§C4.5 / §C1.2 #5 / §G6).
import test from 'node:test';
import assert from 'node:assert/strict';

import { NEAR_MISS, stepNearMiss } from '../src/city/traffic.js';
import { DELIVERY_FX, parcelArcPos, DELIVERY, applyDrop, applyCrash } from '../src/minigames/games/deliveryRush.logic.js';
import { isSoftwareRenderer } from '../src/minigames/games/goobyWelt.logic.js';
import { EN as GP5_EN, DE as GP5_DE } from '../src/data/strings/v4-gpgroup5.js';

// ---------------------------------------------------------------------------
// traffic.js — near-miss tracker
// ---------------------------------------------------------------------------

test('GAME-POLISH-5 traffic: NEAR_MISS tuning is frozen and sane', () => {
  assert.equal(Object.isFrozen(NEAR_MISS), true);
  assert.ok(NEAR_MISS.MARGIN_M > 0 && NEAR_MISS.MARGIN_M < 3);
  assert.ok(NEAR_MISS.MIN_SPEED_MS > 0);
  assert.ok(NEAR_MISS.COOLDOWN_SEC > 0);
});

test('GAME-POLISH-5 traffic: clean fast pass fires exactly once on exit', () => {
  const s = { inside: false, dirty: false };
  assert.equal(stepNearMiss(s, false, false, true), false); // approaching
  assert.equal(stepNearMiss(s, true, false, true), false); //  entering
  assert.equal(stepNearMiss(s, true, false, true), false); //  inside
  assert.equal(stepNearMiss(s, false, false, true), true); //  exit → fire
  assert.equal(stepNearMiss(s, false, false, true), false); // no re-fire
});

test('GAME-POLISH-5 traffic: a slow frame anywhere in the window voids the pass', () => {
  const s = { inside: false, dirty: false };
  stepNearMiss(s, true, false, true);
  stepNearMiss(s, true, false, false); // slowed down mid-pass
  assert.equal(stepNearMiss(s, false, false, true), false);
  // entering already slow also voids
  stepNearMiss(s, true, false, false);
  assert.equal(stepNearMiss(s, false, false, true), false);
});

test('GAME-POLISH-5 traffic: a collision voids the pass (crash path untouched)', () => {
  const s = { inside: false, dirty: false };
  stepNearMiss(s, true, false, true);
  assert.equal(stepNearMiss(s, true, true, true), false); // checkHit fired
  assert.equal(stepNearMiss(s, false, false, true), false); // no fire on exit
});

test('GAME-POLISH-5 traffic: tracker re-arms — a later clean pass fires again', () => {
  const s = { inside: false, dirty: false };
  stepNearMiss(s, true, false, true);
  assert.equal(stepNearMiss(s, false, false, true), true);
  stepNearMiss(s, true, false, true);
  assert.equal(stepNearMiss(s, false, false, true), true);
});

// ---------------------------------------------------------------------------
// deliveryRush.logic.js — parcel-pop arc (cosmetic only)
// ---------------------------------------------------------------------------

test('GAME-POLISH-5 delivery: DELIVERY_FX is frozen and cosmetic-shaped', () => {
  assert.equal(Object.isFrozen(DELIVERY_FX), true);
  assert.ok(DELIVERY_FX.POP_SEC > 0 && DELIVERY_FX.POP_SEC < 2);
  assert.ok(DELIVERY_FX.POP_LIFT_M > 0);
  assert.ok(Array.isArray(DELIVERY_FX.STREAK_RATE) && DELIVERY_FX.STREAK_RATE.length >= 2);
  // the streak band tops out at the van's 13 m/s §C4 ramp ceiling
  assert.equal(DELIVERY_FX.STREAK_RATE[DELIVERY_FX.STREAK_RATE.length - 1][0], 13);
});

test('GAME-POLISH-5 delivery: parcelArcPos hits both endpoints exactly', () => {
  const from = { x: 4, y: 3, z: -2 };
  const to = { x: 10, y: 0.3, z: 6 };
  assert.deepEqual(parcelArcPos(from, to, 0), from);
  assert.deepEqual(parcelArcPos(from, to, 1), to);
  // clamped outside 0..1
  assert.deepEqual(parcelArcPos(from, to, -0.5), from);
  assert.deepEqual(parcelArcPos(from, to, 1.5), to);
});

test('GAME-POLISH-5 delivery: parcelArcPos apex lifts by POP_LIFT_M at t=0.5', () => {
  const from = { x: 0, y: 2, z: 0 };
  const to = { x: 8, y: 0, z: 8 };
  const mid = parcelArcPos(from, to, 0.5);
  assert.equal(mid.x, 4);
  assert.equal(mid.z, 4);
  assert.ok(Math.abs(mid.y - (1 + DELIVERY_FX.POP_LIFT_M)) < 1e-9);
  const lifted = parcelArcPos(from, to, 0.5, 1.25);
  assert.ok(Math.abs(lifted.y - 2.25) < 1e-9);
});

test('GAME-POLISH-5 delivery: pop juice cannot drift into §C1.2 #5 scoring', () => {
  // the frozen table + score steps are byte-identical to the certified rules
  assert.equal(DELIVERY.DROP_POINTS, 50);
  assert.equal(DELIVERY.CRASH_PENALTY, 5);
  assert.equal(applyDrop(0), 50);
  assert.equal(applyCrash(3), 0); // floor at 0
});

// ---------------------------------------------------------------------------
// goobyWelt.logic.js — software-GL probe
// ---------------------------------------------------------------------------

test('GAME-POLISH-5 welt: isSoftwareRenderer flags software rasterizers', () => {
  assert.equal(isSoftwareRenderer('Google SwiftShader'), true);
  assert.equal(
    isSoftwareRenderer('ANGLE (Google, Vulkan 1.1.0 (SwiftShader Device (Subzero) (0x0000C0DE)), SwiftShader driver)'),
    true
  );
  assert.equal(isSoftwareRenderer('llvmpipe (LLVM 12.0.0, 256 bits)'), true);
  assert.equal(isSoftwareRenderer('Microsoft Basic Render Driver'), true);
  assert.equal(isSoftwareRenderer('Mesa/X.org softpipe'), true);
});

test('GAME-POLISH-5 welt: isSoftwareRenderer keeps real GPUs on the splat path', () => {
  assert.equal(isSoftwareRenderer('ANGLE (NVIDIA, NVIDIA GeForce RTX 3080 Direct3D11 vs_5_0 ps_5_0, D3D11)'), false);
  assert.equal(isSoftwareRenderer('Apple M1'), false);
  assert.equal(isSoftwareRenderer('Mali-G78 MP20'), false);
  assert.equal(isSoftwareRenderer('Adreno (TM) 650'), false);
  assert.equal(isSoftwareRenderer(''), false);
  assert.equal(isSoftwareRenderer(undefined), false);
  assert.equal(isSoftwareRenderer(null), false);
});

// ---------------------------------------------------------------------------
// v4-gpgroup5.js — EN/DE parity
// ---------------------------------------------------------------------------

test('GAME-POLISH-5 strings: v4-gpgroup5 EN/DE key parity, all non-empty', () => {
  assert.deepEqual(Object.keys(GP5_EN).sort(), Object.keys(GP5_DE).sort());
  for (const [key, value] of [...Object.entries(GP5_EN), ...Object.entries(GP5_DE)]) {
    assert.ok(typeof value === 'string' && value.length > 0, key);
    assert.ok(key.startsWith('gp5.'), key);
  }
});
