// V6/F4 — Funkelpark Riesenrad (PLAN6 Wave F/F4): headless checks on
// park/ferrisWheel.js. The CLASSIC ferris-wheel bug is pinned here: pure
// gondolaTransform(theta, i) must counter-rotate every cabin so it stays
// UPRIGHT (world rotation identity) for every wheel angle and NEVER swings
// through a spoke — proven closed-form AND by sampled point-to-segment
// distance (plus a counterexample showing the buggy rigid transform WOULD
// collide, so the assertion has teeth). Also: gondola spacing determinism,
// the ~45 s ride timeline (apex beat timing, tap-to-end-early after 10 s,
// watchdog), reduced-motion compile, the mount/dispose leak model, and the
// ≤6-draw-call instanced-batch budget (A3's pure-ledger pattern).
//
// three.js imports fine under node (r170, no DOM at module scope), so the
// mount/dispose test builds the REAL wheel graph headlessly.
import test from 'node:test';
import assert from 'node:assert/strict';
import * as THREE from 'three';

import {
  WHEEL,
  WHEEL_RIDE,
  WHEEL_BATCHES,
  GONDOLA_COLORS,
  GONDOLA_ROOFS,
  RIDER_SCALE,
  gondolaTransform,
  spokeAngles,
  spokeClearance,
  wheelDrawCalls,
  createWheelLedger,
  createWheelRide,
  stepWheelRide,
  mountFerrisWheel,
} from '../src/park/ferrisWheel.js';

const TAU = Math.PI * 2;
const DT = 1 / 60;
/** wrap into (−π, π] */
const wrapPi = (a) => {
  let x = a % TAU;
  if (x <= -Math.PI) x += TAU;
  if (x > Math.PI) x -= TAU;
  return x;
};

/** run a ride to completion; returns { events: [{type, t}], total, ride } */
function runRide(opts = {}, tapPlan = () => false, maxSec = 200) {
  const ride = createWheelRide(opts);
  const events = [];
  let t = 0;
  while (!ride.done && t < maxSec) {
    const out = stepWheelRide(ride, DT, { tapped: tapPlan(ride, t) });
    t += DT;
    for (const e of out) events.push({ type: e.type, t });
  }
  return { events, total: t, ride };
}

// ─────────────────────────────────────────────── model pins (PLAN6 F4 spec)

test('model pins: 8 gondolas, alternating pastel pairs, ≤6 draw-call batches', () => {
  assert.equal(WHEEL.GONDOLAS, 8); // spec: 8-10 gondolas
  assert.ok(WHEEL.GONDOLAS >= 8 && WHEEL.GONDOLAS <= 10);
  assert.equal(GONDOLA_COLORS.length, 4); // i % 4 alternation
  assert.equal(GONDOLA_ROOFS.length, GONDOLA_COLORS.length);
  assert.ok(RIDER_SCALE > 0 && RIDER_SCALE < 1);
  // budget: one instanced batch per row, ≤6 total (the pure A3-style ledger)
  assert.ok(wheelDrawCalls() <= 6, `${wheelDrawCalls()} batches > 6`);
  assert.equal(wheelDrawCalls(), WHEEL_BATCHES.length);
  for (const b of WHEEL_BATCHES) assert.ok(b.instances >= 1, `${b.id} empty`);
  const cabins = WHEEL_BATCHES.find((b) => b.id === 'cabins');
  assert.equal(cabins.instances, WHEEL.GONDOLAS);
  assert.equal(WHEEL_BATCHES.find((b) => b.id === 'roofs').instances, WHEEL.GONDOLAS);
});

// ─────────────────────────────── gondola spacing + transform determinism

test('gondolaTransform: even 2π/n spacing on the rim, deterministic', () => {
  for (const theta of [0, 0.37, 2.9, -4.2, 7 * Math.PI]) {
    for (let i = 0; i < WHEEL.GONDOLAS; i++) {
      const g = gondolaTransform(theta, i);
      // pivot rides the rim circle exactly
      assert.ok(Math.abs(Math.hypot(g.px, g.py) - WHEEL.RADIUS) < 1e-9);
      // even spacing: neighbor is exactly one bay (2π/n) further
      const next = gondolaTransform(theta, (i + 1) % WHEEL.GONDOLAS);
      const bay = wrapPi(next.angle - g.angle);
      assert.ok(
        Math.abs(wrapPi(bay - TAU / WHEEL.GONDOLAS)) < 1e-9,
        `bay ${i} at theta ${theta} is ${bay}`
      );
      // deterministic: same inputs, byte-identical outputs
      assert.deepEqual(g, gondolaTransform(theta, i));
    }
  }
});

test('counter-rotation invariant: cabins stay UPRIGHT for every wheel angle', () => {
  for (let s = 0; s <= 720; s++) {
    const theta = (s / 720) * 2 * TAU - TAU; // sweep −2π … +2π
    for (let i = 0; i < WHEEL.GONDOLAS; i++) {
      const g = gondolaTransform(theta, i);
      // the classic bug: rim rotation must be EXACTLY cancelled by the cabin
      assert.equal(g.rimRot, theta);
      assert.equal(g.cabinRot, -theta);
      assert.ok(Math.abs(g.rimRot + g.cabinRot) < 1e-12, 'cabin world rotation != identity');
      // upright: the cabin hangs STRAIGHT DOWN from its pivot, always
      assert.equal(g.cx, g.px);
      assert.ok(Math.abs(g.py - g.cy - WHEEL.GONDOLA_DROP) < 1e-12);
    }
  }
});

// ─────────────────────────────── spokes: the geometric never-intersect proof

test('spokes sit half a bay off the pivots (closed-form swept-disc clearance)', () => {
  const halfBay = Math.PI / WHEEL.GONDOLAS;
  const angles = spokeAngles(0.83);
  assert.equal(angles.length, WHEEL.GONDOLAS);
  const g0 = gondolaTransform(0.83, 0);
  assert.ok(Math.abs(wrapPi(angles[0] - g0.angle) - halfBay) < 1e-12);
  // closed form: the swept disc around a pivot (drop + cabin radius) must fit
  // inside the spoke-free wedge — R·sin(π/n) > DROP + GONDOLA_R + SPOKE_R
  const wedge = WHEEL.RADIUS * Math.sin(halfBay);
  const swept = WHEEL.GONDOLA_DROP + WHEEL.GONDOLA_R + WHEEL.SPOKE_R;
  assert.ok(wedge > swept, `wedge ${wedge.toFixed(3)} ≤ swept ${swept.toFixed(3)}`);
  // …and the swept disc clears the hub cap on the inside too
  assert.ok(WHEEL.RADIUS - WHEEL.GONDOLA_DROP - WHEEL.GONDOLA_R > WHEEL.HUB_R);
});

test('sampled sweep: no cabin ever touches a spoke line (720 angles × all cabins)', () => {
  let minClear = Infinity;
  for (let s = 0; s < 720; s++) {
    const theta = (s / 720) * TAU;
    for (let i = 0; i < WHEEL.GONDOLAS; i++) {
      minClear = Math.min(minClear, spokeClearance(theta, i));
    }
  }
  assert.ok(minClear > 0, `cabin/spoke clearance went to ${minClear.toFixed(4)} m`);
});

test('the assertions have teeth: the classic bugs are actually caught', () => {
  // (a) cabin welded to the rim (no counter-rotation): the hang direction
  // rotates with theta → cabins end up ABOVE their pivot = upside down.
  // The correct transform NEVER does (py − cy === DROP, pinned above).
  let upsideDown = false;
  for (let s = 0; s < 720; s++) {
    const theta = (s / 720) * TAU;
    const g = gondolaTransform(theta, 0);
    const buggyCy = g.py - Math.cos(theta) * WHEEL.GONDOLA_DROP; // welded offset
    if (buggyCy > g.py + 1e-9) upsideDown = true;
  }
  assert.ok(upsideDown, 'the welded cabin should flip upside down somewhere');
  // (b) the sweep catches BAD geometry: a tighter wheel (16 gondolas on the
  // same rim → half-bay wedge 0.78 m < swept disc 1.23 m) must fail the
  // clearance the shipping 8-gondola layout passes.
  let worst = Infinity;
  for (let s = 0; s < 720; s++) {
    const theta = (s / 720) * TAU;
    for (let i = 0; i < 16; i++) worst = Math.min(worst, spokeClearance(theta, i, 16));
  }
  assert.ok(worst < 0, 'a too-tight wheel should intersect spokes somewhere');
});

// ──────────────────────────────────────────────── ride timeline (~45 s real)

test('full ride: ~45 s, events in order, apex beat at the half-revolution', () => {
  const { events, total, ride } = runRide({ theta0: 0.3 });
  const order = events.map((e) => e.type);
  // hintReady unlocks 10 s into the ride — BEFORE the ~20 s apex beat
  assert.deepEqual(order, ['board', 'depart', 'hintReady', 'apex', 'arrived', 'done']);
  assert.ok(total >= 42 && total <= 50, `ride took ${total.toFixed(1)} s (want ~45)`);
  const at = (type) => events.find((e) => e.type === type).t;
  const apexFromDepart = at('apex') - at('depart');
  // half a revolution at 1.5 rpm ≈ 20 s (+ spin-up slack)
  assert.ok(
    apexFromDepart >= 17 && apexFromDepart <= 23,
    `apex ${apexFromDepart.toFixed(1)} s after depart`
  );
  assert.equal(ride.rideAngle, TAU); // exactly one full revolution
  assert.equal(ride.phase, 'done');
});

test('theta is continuous: no jump ever exceeds the return-speed step', () => {
  const ride = createWheelRide({ theta0: 2.4 });
  let prev = ride.theta;
  const maxStep = (WHEEL_RIDE.RETURN_RPM * TAU * DT) / 60 + WHEEL_RIDE.ALIGN_RATE * DT + 1e-6;
  let t = 0;
  while (!ride.done && t < 200) {
    stepWheelRide(ride, DT, { tapped: t > 20 }); // includes an early-end path
    assert.ok(Math.abs(ride.theta - prev) <= maxStep, `theta jumped at t=${t.toFixed(2)}`);
    prev = ride.theta;
    t += DT;
  }
});

test('align: boards the NEAREST gondola (≤ half a bay) and parks it at the bottom', () => {
  for (const theta0 of [0, 0.31, 1.7, -2.6, 5.9]) {
    const ride = createWheelRide({ theta0 });
    assert.ok(Math.abs(ride.alignLeft) <= Math.PI / WHEEL.GONDOLAS + 1e-9);
    let t = 0;
    while (ride.phase === 'align' && t < 10) {
      stepWheelRide(ride, DT);
      t += DT;
    }
    assert.equal(ride.phase, 'board');
    const g = gondolaTransform(ride.theta, ride.boardIndex);
    assert.ok(
      Math.abs(wrapPi(g.angle - -Math.PI / 2)) < 1e-6,
      `boarded gondola not at the bottom (theta0 ${theta0})`
    );
  }
});

test('tap-to-end-early: ignored before 10 s, graceful return after', () => {
  // tap constantly from the very start: must NOT end before EARLY_TAP_SEC
  const tapped = runRide({ theta0: 0 }, () => true);
  const types = tapped.events.map((e) => e.type);
  assert.ok(types.includes('returnStarted'), 'early tap never accepted');
  assert.deepEqual(
    types,
    ['board', 'depart', 'hintReady', 'returnStarted', 'apex', 'arrived', 'done']
  );
  const returnAt = tapped.events.find((e) => e.type === 'returnStarted').t;
  const departAt = tapped.events.find((e) => e.type === 'depart').t;
  assert.ok(returnAt - departAt >= WHEEL_RIDE.EARLY_TAP_SEC - 1e-6, 'accepted too early');
  // the tapped ride is meaningfully shorter, but still a complete calm ride
  const full = runRide({ theta0: 0 });
  assert.ok(tapped.total < full.total - 5, 'early end saved no time');
  assert.equal(tapped.ride.rideAngle, TAU); // still rolls to the exit, no cut
  // exactly one of each beat — never doubled
  for (const type of ['board', 'depart', 'apex', 'arrived', 'done']) {
    assert.equal(types.filter((x) => x === type).length, 1, `${type} fired twice`);
  }
});

test('determinism: identical inputs → identical event logs', () => {
  const plan = (ride, t) => t > 14 && t < 14.4;
  const a = runRide({ theta0: 1.234 }, plan);
  const b = runRide({ theta0: 1.234 }, plan);
  assert.deepEqual(a.events, b.events);
  assert.equal(a.total, b.total);
});

test('reduced motion compiles: static apex shot, caption beats, tap ends it', () => {
  // auto-finish after the hold
  const rm = runRide({ reducedMotion: true, theta0: 0.7 });
  assert.deepEqual(rm.events.map((e) => e.type), ['board', 'apex', 'arrived', 'done']);
  assert.ok(rm.total <= WHEEL_RIDE.RM_HOLD_SEC + 1, `rm hold ran ${rm.total.toFixed(1)} s`);
  // the boarded gondola is parked at the very TOP for the static shot
  const g = gondolaTransform(rm.ride.theta, rm.ride.boardIndex);
  assert.ok(Math.abs(wrapPi(g.angle - Math.PI / 2)) < 1e-9, 'rm gondola not at apex');
  // a tap ends the hold immediately (calm accessibility — no minimum dwell)
  const rmTap = runRide({ reducedMotion: true }, (ride, t) => t > 1);
  assert.ok(rmTap.total < 2);
  assert.deepEqual(rmTap.events.map((e) => e.type), ['board', 'apex', 'arrived', 'done']);
});

test('watchdog: a stuck ride force-finishes (risk-row-5 discipline)', () => {
  const ride = createWheelRide({ theta0: 0 });
  ride.totalT = WHEEL_RIDE.WATCHDOG_SEC + 1; // simulate a wedged phase
  const out = stepWheelRide(ride, DT);
  assert.deepEqual(out.map((e) => e.type), ['arrived', 'done']);
  assert.equal(ride.done, true);
  assert.deepEqual(stepWheelRide(ride, DT), []); // done rides stay silent
});

// ───────────────────────────────────── mount / dispose / draw-call budget

test('disposal ledger: everything tracked is disposed exactly once', () => {
  const ledger = createWheelLedger();
  let disposed = 0;
  const res = () => ({ dispose: () => (disposed += 1) });
  ledger.track(res(), 'geometry');
  ledger.track(res(), 'geometry');
  ledger.track(res(), 'material');
  assert.equal(ledger.outstanding(), 3);
  assert.deepEqual(ledger.byKind(), { geometry: 2, material: 1 });
  assert.equal(ledger.disposeAll(), 3);
  assert.equal(disposed, 3);
  assert.equal(ledger.outstanding(), 0);
  assert.equal(ledger.disposeAll(), 0); // idempotent
});

test('mounted wheel: exactly one mesh per WHEEL_BATCHES row (≤6 draw calls)', () => {
  const parent = new THREE.Group();
  const anchor = { x: -12, z: -15, rotY: Math.atan2(12, 15) };
  const wheel = mountFerrisWheel(parent, anchor, {});
  let meshes = 0;
  let instanced = 0;
  wheel.group.traverse((o) => {
    if (o.isInstancedMesh) {
      instanced += 1;
      meshes += 1;
    } else if (o.isMesh) {
      meshes += 1;
    }
  });
  assert.equal(meshes, WHEEL_BATCHES.length, 'view drifted from the batch ledger');
  assert.ok(meshes <= 6, `${meshes} wheel draw calls > 6`);
  assert.equal(instanced, WHEEL_BATCHES.filter((b) => b.instances > 1).length);
  assert.equal(wheel.group.position.x, -12);
  assert.equal(wheel.group.position.z, -15);
  wheel.dispose();
});

test('mount update: ambient ~1 rpm spin; frozen under reduced motion; leak-free dispose', () => {
  const parent = new THREE.Group();
  const anchor = { x: 0, z: 0, rotY: 0 };
  const wheel = mountFerrisWheel(parent, anchor, {});
  const t0 = wheel.getTheta();
  for (let i = 0; i < 60; i++) wheel.update(DT); // one simulated second
  const spun = wheel.getTheta() - t0;
  assert.ok(Math.abs(spun - TAU / 60) < 1e-6, `ambient spin ${spun} rad/s`);
  assert.equal(wheel.isRiding(), false);
  wheel.setBand('night'); // rim glow hook — must not throw headlessly
  wheel.dispose();
  assert.equal(wheel.group.parent, null, 'wheel left in the scene after dispose');

  const still = mountFerrisWheel(parent, anchor, { reducedMotion: true });
  const s0 = still.getTheta();
  for (let i = 0; i < 60; i++) still.update(DT);
  assert.equal(still.getTheta(), s0, 'reduced motion must freeze the ambient spin');
  still.dispose();
  assert.equal(parent.children.length, 0);
});
