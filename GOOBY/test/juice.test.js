// V4/AC-9 — interaction-juice pure math (src/ui/juice.js): pool index +
// free-slot picking, coin-count clamp, quadratic coin-arc interpolation and
// keyframe generation, pop particle vectors (injectable rand), the
// concurrency/reduced-motion effect gate, and the no-DOM safety contract
// (initJuice/flyCoins no-op headlessly). Pure node:test — no DOM/three.js;
// the delegated press/pop/coin DOM wiring is CDP-verified per §E.
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  poolIndex,
  nextFreeIndex,
  clampCoinCount,
  arcLift,
  arcPoint,
  arcKeyframes,
  popVectors,
  createEffectGate,
  initJuice,
  flyCoins,
} from '../src/ui/juice.js';
import { prefersReducedMotion } from '../src/ui/ui.js';

// ---------------------------------------------------------------------------
// pool index math
// ---------------------------------------------------------------------------

test('AC-9: poolIndex wraps a monotonic counter round-robin into [0, size)', () => {
  assert.equal(poolIndex(0, 4), 0);
  assert.equal(poolIndex(3, 4), 3);
  assert.equal(poolIndex(4, 4), 0);
  assert.equal(poolIndex(11, 4), 3);
  assert.equal(poolIndex(6, 6), 0);
});

test('AC-9: poolIndex survives garbage (negative/NaN counters, size floor 1)', () => {
  assert.equal(poolIndex(-1, 4), 3); // still in range
  assert.equal(poolIndex(NaN, 4), 0);
  assert.equal(poolIndex(5, 1), 0);
  assert.equal(poolIndex(5, 0), 0); // size floored to 1
});

test('AC-9: nextFreeIndex picks the first idle pop group, -1 when jammed', () => {
  assert.equal(nextFreeIndex([false, false]), 0);
  assert.equal(nextFreeIndex([true, false, true]), 1);
  assert.equal(nextFreeIndex([true, true, true]), -1);
  assert.equal(nextFreeIndex([]), -1);
});

// ---------------------------------------------------------------------------
// coin count clamp (3–6 sprite contract)
// ---------------------------------------------------------------------------

test('AC-9: clampCoinCount keeps the 3–6 sprite contract', () => {
  assert.equal(clampCoinCount(3), 3);
  assert.equal(clampCoinCount(6), 6);
  assert.equal(clampCoinCount(1), 3);
  assert.equal(clampCoinCount(0), 3);
  assert.equal(clampCoinCount(50), 6);
  assert.equal(clampCoinCount(4.6), 5); // rounds
});

test('AC-9: clampCoinCount defaults garbage to 4 coins', () => {
  assert.equal(clampCoinCount(undefined), 4);
  assert.equal(clampCoinCount(NaN), 4);
  assert.equal(clampCoinCount('leaf'), 4);
  assert.equal(clampCoinCount(Infinity), 4);
});

// ---------------------------------------------------------------------------
// coin arc interpolation
// ---------------------------------------------------------------------------

const FROM = { x: 200, y: 600 };
const TO = { x: 72, y: 90 };

test('AC-9: arcPoint hits both endpoints exactly (t=0 / t=1)', () => {
  assert.deepEqual(arcPoint(FROM, TO, 120, 0), FROM);
  assert.deepEqual(arcPoint(FROM, TO, 120, 1), TO);
});

test('AC-9: arcPoint mid-flight rises above the straight chord (the arc)', () => {
  const lift = 120;
  const mid = arcPoint(FROM, TO, lift, 0.5);
  const chordMidY = (FROM.y + TO.y) / 2;
  assert.ok(mid.y < chordMidY, `mid.y ${mid.y} must sit above chord mid ${chordMidY}`);
  // quadratic bezier at t=0.5: y = y0/4 + cy/2 + y1/4 with cy = min(y0,y1) - lift
  const expected = FROM.y / 4 + (Math.min(FROM.y, TO.y) - lift) / 2 + TO.y / 4;
  assert.ok(Math.abs(mid.y - expected) < 1e-9);
  assert.ok(Math.abs(mid.x - (FROM.x + TO.x) / 2) < 1e-9); // control sits over the mid x
});

test('AC-9: arcLift scales with distance and clamps to [50, 180]', () => {
  assert.equal(arcLift({ x: 0, y: 0 }, { x: 10, y: 0 }), 50); // short hop floor
  assert.equal(arcLift({ x: 0, y: 0 }, { x: 2000, y: 0 }), 180); // cross-screen cap
  const mid = arcLift({ x: 0, y: 0 }, { x: 300, y: 0 });
  assert.ok(Math.abs(mid - 105) < 1e-9); // 300 * 0.35 between the clamps
});

test('AC-9: arcKeyframes emits steps+1 frames with monotonic 0→1 offsets', () => {
  const frames = arcKeyframes(FROM, TO, 120, 8);
  assert.equal(frames.length, 9);
  assert.equal(frames[0].offset, 0);
  assert.equal(frames[frames.length - 1].offset, 1);
  for (let i = 1; i < frames.length; i += 1) {
    assert.ok(frames[i].offset > frames[i - 1].offset);
  }
});

test('AC-9: arcKeyframes starts at rest and lands on the target delta', () => {
  const frames = arcKeyframes(FROM, TO, 120, 8);
  assert.match(frames[0].transform, /^translate\(0\.0px, 0\.0px\)/);
  const last = frames[frames.length - 1].transform;
  assert.ok(last.includes(`translate(${(TO.x - FROM.x).toFixed(1)}px, ${(TO.y - FROM.y).toFixed(1)}px)`), last);
});

test('AC-9: arcKeyframes grows the coin mid-air and shrinks it into the chip', () => {
  const frames = arcKeyframes(FROM, TO, 120, 8);
  const scaleOf = (f) => Number(/scale\(([\d.]+)\)/.exec(f.transform)[1]);
  const midScale = scaleOf(frames[4]); // t = 0.5
  assert.ok(midScale > 1, `mid-air scale ${midScale} > 1`);
  const endScale = scaleOf(frames[frames.length - 1]);
  assert.ok(endScale < 0.7, `landing scale ${endScale} < 0.7`);
});

test('AC-9: arcKeyframes floors degenerate step counts at 2 segments', () => {
  assert.equal(arcKeyframes(FROM, TO, 120, 0).length, 3);
  assert.equal(arcKeyframes(FROM, TO, 120, 1).length, 3);
});

// ---------------------------------------------------------------------------
// pop particle vectors
// ---------------------------------------------------------------------------

test('AC-9: popVectors is deterministic with an injected rand', () => {
  const a = popVectors(6, 34, () => 0.5);
  const b = popVectors(6, 34, () => 0.5);
  assert.equal(a.length, 6);
  assert.deepEqual(a, b);
});

test('AC-9: popVectors spreads within the radius envelope', () => {
  const radius = 34;
  for (const v of popVectors(8, radius, () => 0.99)) {
    // max dist = radius * 1.2 (+ the upward bias on dy)
    assert.ok(Math.hypot(v.dx, v.dy + radius * 0.2) <= radius * 1.2 + 1e-9);
  }
  for (const v of popVectors(8, radius, () => 0)) {
    assert.ok(Math.hypot(v.dx, v.dy + radius * 0.2) >= radius * 0.65 - 1e-9);
  }
});

test('AC-9: popVectors biases upward (a happy poof, not an explosion)', () => {
  const vs = popVectors(12, 34, () => 0.5); // symmetric angles → bias dominates
  const meanDy = vs.reduce((s, v) => s + v.dy, 0) / vs.length;
  assert.ok(meanDy < 0, `mean dy ${meanDy} should drift upward`);
});

test('AC-9: popVectors particle scales stay in the readable 0.7–1.3 band', () => {
  for (const v of popVectors(10, 34, () => 0.999)) assert.ok(v.scale <= 1.3 + 1e-9);
  for (const v of popVectors(10, 34, () => 0)) assert.ok(v.scale >= 0.7 - 1e-9);
});

// ---------------------------------------------------------------------------
// effect gate (concurrency cap + reduced-motion wiring)
// ---------------------------------------------------------------------------

test('AC-9: effect gate caps concurrent effects at 4 (the pop pool contract)', () => {
  const gate = createEffectGate({ cap: 4 });
  for (let i = 0; i < 4; i += 1) assert.equal(gate.tryAcquire(), true);
  assert.equal(gate.tryAcquire(), false); // 5th concurrent pop refused
  assert.equal(gate.active(), 4);
  gate.release();
  assert.equal(gate.tryAcquire(), true); // slot freed → reusable
});

test('AC-9: effect gate consults the reduced-motion predicate on EVERY acquire', () => {
  let reduce = false;
  const gate = createEffectGate({ cap: 4, reducedMotion: () => reduce });
  assert.equal(gate.tryAcquire(), true);
  reduce = true; // user flips the OS toggle mid-session
  assert.equal(gate.tryAcquire(), false);
  assert.equal(gate.active(), 1); // refused acquire doesn't leak a slot
  reduce = false;
  assert.equal(gate.tryAcquire(), true);
});

test('AC-9: effect gate release never underflows below zero', () => {
  const gate = createEffectGate({ cap: 2 });
  gate.release();
  gate.release();
  assert.equal(gate.active(), 0);
  assert.equal(gate.tryAcquire(), true);
});

// ---------------------------------------------------------------------------
// headless safety contract (no DOM in node:test)
// ---------------------------------------------------------------------------

test('AC-9: prefersReducedMotion (ui.js export) is node-safe and false headlessly', () => {
  assert.equal(prefersReducedMotion(), false);
});

test('AC-9: initJuice no-ops without a DOM (returns null, throws nothing)', () => {
  assert.equal(initJuice({}), null);
});

test('AC-9: flyCoins before init is a safe no-op returning 0 coins', () => {
  assert.equal(flyCoins({ x: 100, y: 100 }, 5), 0);
  assert.equal(flyCoins(null, undefined), 0);
});
