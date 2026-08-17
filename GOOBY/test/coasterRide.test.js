// V6/E2 (PLAN6 Wave E) — Funkelpark coaster contract tests: socket joins
// ≤ 1 mm across the whole authored layout (the plan's HARD acceptance) +
// circuit closure, center-line spline continuity (position/tangent, no
// kinks at piece boundaries), the deterministic physics-lite speed profile
// (never stalls, never exceeds VMAX, 40–60 s circuit), cart/camera pose
// continuity (no teleports; roll clamped outside the loop, inverted inside),
// hands-up window determinism, the reduced-motion static-shot compile (the
// POV never rides the loop), skip/watchdog semantics, auto-placed supports,
// and the view module's dispose/export contract via source scan (the
// particles.js TYPES-mirror precedent — the view imports three and must
// stay out of headless import chains).

import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  TRACK_PIECES,
  SUPPORTS,
  PIECE_MODEL_KEYS,
  localSockets,
  assembleTrack,
  pointAt,
  computeSupports,
} from '../src/park/trackPieces.js';
import {
  COASTER,
  LAYOUT,
  ROLES,
  zonesOf,
  loopSpanOf,
  rollBlendAt,
  handsUpWindows,
  staticShots,
  shotAt,
  createRide,
  stepRide,
  skipRide,
  cartPoseAt,
  cameraPose,
  simulateRide,
} from '../src/park/coasterRide.logic.js';
import { EN as PARK_EN, DE as PARK_DE } from '../src/data/strings/v6-park.js';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');

/** PLAN6 E2 hard acceptance: 1 mm in world meters, in track units. */
const MM = 0.001 / COASTER.WORLD_SCALE;

const dist3 = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]);
const dot3 = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];

// ---------------------------------------------------------------------------
// Catalog + layout basics
// ---------------------------------------------------------------------------

test('coaster: layout/roles parity and catalog integrity', () => {
  assert.equal(LAYOUT.length, ROLES.length);
  for (const type of LAYOUT) {
    assert.ok(TRACK_PIECES[type], `unknown piece type '${type}' in LAYOUT`);
  }
  // every catalog + support GLB is actually committed on disk
  for (const key of PIECE_MODEL_KEYS) {
    const file = path.join(ROOT, 'public/assets/kenney', `${key.replace('toy-car-kit/', 'toy-car-kit/')}.glb`);
    assert.ok(existsSync(file), `missing GLB for ${key}`);
  }
  // local sockets exist for every type and keep turns in {0, 1}
  for (const type of Object.keys(TRACK_PIECES)) {
    const sock = localSockets(type);
    assert.ok(Number.isFinite(sock.fwd) && sock.fwd > 0);
    assert.ok(sock.turn === 0 || sock.turn === 1);
  }
});

// ---------------------------------------------------------------------------
// Socket joins ≤ 1 mm (the plan's hard acceptance) + closure
// ---------------------------------------------------------------------------

test('coaster: every exit socket meets the next entry within 1 mm, circuit closes', () => {
  const asm = assembleTrack(LAYOUT);
  assert.equal(asm.pieces.length, LAYOUT.length);
  for (let i = 0; i < asm.pieces.length; i += 1) {
    const a = asm.pieces[i];
    const b = asm.pieces[(i + 1) % asm.pieces.length];
    const gap = dist3(a.exit, b.entry);
    assert.ok(gap <= MM, `socket join ${i}→${(i + 1) % asm.pieces.length} gap ${gap} > 1 mm`);
    assert.equal(a.exitDir, b.entryDir, `heading mismatch at joint ${i}`);
  }
  assert.ok(asm.closed, `circuit not closed (error ${asm.closeError})`);
  assert.ok(asm.closeError <= MM);
});

test('coaster: piece arc ranges tile the circuit exactly', () => {
  const asm = assembleTrack(LAYOUT);
  assert.equal(asm.pieces[0].s0, 0);
  for (let i = 1; i < asm.pieces.length; i += 1) {
    assert.equal(asm.pieces[i].s0, asm.pieces[i - 1].s1);
    assert.ok(asm.pieces[i].s1 > asm.pieces[i].s0);
  }
  assert.equal(asm.pieces[asm.pieces.length - 1].s1, asm.totalLen);
});

// ---------------------------------------------------------------------------
// Spline continuity (position + tangent — no kinks at piece boundaries)
// ---------------------------------------------------------------------------

test('coaster: center-line spline is position- and tangent-continuous', () => {
  const asm = assembleTrack(LAYOUT);
  const step = 0.05;
  let prev = pointAt(asm, 0);
  for (let s = step; s <= asm.totalLen + step; s += step) {
    const cur = pointAt(asm, s);
    const d = dist3(cur.p, prev.p);
    assert.ok(d <= step * 1.35 + 1e-6, `position jump ${d} at s=${s.toFixed(2)}`);
    assert.ok(dot3(cur.t, prev.t) >= 0.99, `tangent kink at s=${s.toFixed(2)}`);
    const upLen = Math.hypot(cur.up[0], cur.up[1], cur.up[2]);
    assert.ok(Math.abs(upLen - 1) < 1e-6, 'up not normalized');
    prev = cur;
  }
});

// ---------------------------------------------------------------------------
// Supports (auto-placed under elevated track)
// ---------------------------------------------------------------------------

test('coaster: supports stand on the ground under elevated track, never inside the loop', () => {
  const asm = assembleTrack(LAYOUT);
  const span = loopSpanOf(asm);
  const supports = computeSupports(asm);
  assert.ok(supports.length >= 8, 'lift + crest + drop need columns');
  for (const sup of supports) {
    assert.equal(sup.p[1], 0);
    assert.ok(sup.h > SUPPORTS.MIN_Y);
    // no column foot may sit under the loop circle's footprint
    const loopPieces = asm.pieces.filter((piece) => piece.type === 'loop');
    for (const piece of loopPieces) {
      const mid = pointAt(asm, (piece.s0 + piece.s1) / 2);
      assert.ok(
        Math.hypot(sup.p[0] - mid.p[0], sup.p[2] - mid.p[2]) > 1,
        'support under the loop'
      );
    }
    assert.ok(span.s1 > span.s0); // sanity: the loop span exists
  }
});

// ---------------------------------------------------------------------------
// Zones, windows, cues
// ---------------------------------------------------------------------------

test('coaster: zones are contiguous; hands-up windows are ordered and disjoint', () => {
  const asm = assembleTrack(LAYOUT);
  const zones = zonesOf(asm); // throws on non-contiguous roles
  for (const role of ['station', 'lift', 'crest', 'drop', 'boost', 'loop', 'photo', 'hills', 'brake', 'home']) {
    assert.ok(zones[role], `missing zone '${role}'`);
    assert.ok(zones[role].s1 > zones[role].s0);
  }
  const windows = handsUpWindows(zones);
  assert.equal(windows.length, 3);
  let lastEnd = -1;
  for (const win of windows) {
    assert.ok(win.s0 > lastEnd, 'windows overlap');
    assert.ok(win.s1 > win.s0 && win.s1 <= asm.totalLen);
    lastEnd = win.s1;
  }
});

test('coaster: caption cue keys exist in the v6-park EN and DE dictionaries', () => {
  const ride = createRide();
  const keys = [...ride.cues.map((cue) => cue.captionKey), 'park.coaster.board', 'park.coaster.done'];
  for (const key of keys) {
    assert.ok(typeof PARK_EN[key] === 'string' && PARK_EN[key].length > 0, `EN missing ${key}`);
    assert.ok(typeof PARK_DE[key] === 'string' && PARK_DE[key].length > 0, `DE missing ${key}`);
  }
  // cues are sorted and inside the circuit
  for (let i = 1; i < ride.cues.length; i += 1) {
    assert.ok(ride.cues[i].s > ride.cues[i - 1].s);
  }
  assert.ok(ride.cues[0].s >= 0 && ride.cues[ride.cues.length - 1].s < ride.assembly.totalLen);
});

// ---------------------------------------------------------------------------
// Speed profile: deterministic, bounded, 40–60 s, never stalls
// ---------------------------------------------------------------------------

test('coaster: full ride arrives in 40–60 s, v within [floor, VMAX], photo fires', () => {
  const sim = simulateRide();
  assert.ok(sim.arrived, 'ride must arrive');
  assert.ok(sim.durationSec >= 40 && sim.durationSec <= 60, `duration ${sim.durationSec}`);
  assert.ok(sim.maxV <= COASTER.VMAX + 1e-9, `maxV ${sim.maxV}`);
  assert.ok(sim.minVRiding >= COASTER.END_MIN_V - 1e-9, `stalled: ${sim.minVRiding}`);
  assert.ok(sim.photoFired);
  assert.equal(sim.events.filter((e) => e.type === 'photo').length, 1);
  assert.equal(sim.events.filter((e) => e.type === 'arrived').length, 1);
  assert.equal(sim.events.filter((e) => e.type === 'watchdog').length, 0);
  const cueIds = sim.events.filter((e) => e.type === 'cue').map((e) => e.id);
  assert.deepEqual(cueIds, ['board', 'lift', 'drop', 'loop', 'photo', 'hills', 'brake', 'done']);
});

test('coaster: mid-circuit speed never crawls below 1 unit/s (no perceived stall)', () => {
  const ride = createRide();
  const dt = 1 / 60;
  let minV = Infinity;
  while (ride.phase !== 'done' && ride.t < 120) {
    stepRide(ride, dt, {});
    if (ride.phase === 'riding' && ride.s > 8 && ride.s < ride.assembly.totalLen - COASTER.END_EASE_LEN) {
      minV = Math.min(minV, ride.v);
    }
  }
  assert.ok(minV >= 1, `mid-circuit crawl: ${minV}`);
});

test('coaster: identical inputs give bit-identical rides (determinism)', () => {
  const dts = [1 / 60, 1 / 30, 1 / 90, 1 / 60, 1 / 144];
  const run = () => {
    const ride = createRide();
    const events = [];
    let i = 0;
    while (ride.phase !== 'done' && ride.t < 120) {
      const holding = ride.activeWindow != null; // deterministic hold policy
      events.push(...stepRide(ride, dts[i % dts.length], { holding }));
      i += 1;
    }
    return { s: ride.s, v: ride.v, t: ride.t, trace: events.map((e) => `${e.type}:${e.id ?? ''}`).join('|') };
  };
  const a = run();
  const b = run();
  assert.equal(a.s, b.s);
  assert.equal(a.v, b.v);
  assert.equal(a.t, b.t);
  assert.equal(a.trace, b.trace);
});

// ---------------------------------------------------------------------------
// Hands-up windows: deterministic enter/exit/sparkle/wheee
// ---------------------------------------------------------------------------

test('coaster: holding through every window earns sparkles and a wheee each', () => {
  const sim = simulateRide({ holdPolicy: (ride) => ride.activeWindow != null });
  const enters = sim.events.filter((e) => e.type === 'windowEnter').map((e) => e.id);
  const exits = sim.events.filter((e) => e.type === 'windowExit').map((e) => e.id);
  const wheees = sim.events.filter((e) => e.type === 'wheee').map((e) => e.id);
  assert.deepEqual(enters, ['drop', 'loop', 'hills']);
  assert.deepEqual(exits, ['drop', 'loop', 'hills']);
  assert.deepEqual(wheees, ['drop', 'loop', 'hills']);
  assert.ok(sim.events.filter((e) => e.type === 'sparkle').length >= 10);
});

test('coaster: never holding gives zero sparkles and zero wheees (optional, no fail)', () => {
  const sim = simulateRide();
  assert.equal(sim.events.filter((e) => e.type === 'sparkle').length, 0);
  assert.equal(sim.events.filter((e) => e.type === 'wheee').length, 0);
  assert.ok(sim.arrived); // the ride completes exactly the same
});

// ---------------------------------------------------------------------------
// Pose continuity: no teleports; roll clamped outside the loop only
// ---------------------------------------------------------------------------

test('coaster: cart and camera move continuously (no frame teleports)', () => {
  const ride = createRide();
  const dt = 1 / 60;
  let prevCam = null;
  let prevCart = null;
  let sawInvertedCart = false;
  while (ride.phase !== 'done' && ride.t < 120) {
    stepRide(ride, dt, {});
    const cam = cameraPose(ride);
    const cart = cartPoseAt(ride.assembly, ride.s);
    if (prevCam) {
      assert.ok(dist3(cam.p, prevCam) <= 0.5, `camera teleport at s=${ride.s.toFixed(1)}`);
      assert.ok(dist3(cart.p, prevCart) <= COASTER.VMAX * dt + 0.02, 'cart teleport');
    }
    // roll clamp: the CAMERA never inverts anywhere — the loop plays out on
    // the train, watched from the exterior vantage (see COASTER.LOOP_TRACK_LERP)
    assert.ok(cam.up[1] >= 0.999, `camera rolled at s=${ride.s.toFixed(1)}`);
    // deep inside the loop span the camera must stand OUTSIDE the riding
    // circle (an interior POV is a full-frame track ribbon at this scale)
    if (rollBlendAt(ride.loopSpan, ride.s) === 1) {
      const horiz = Math.hypot(cam.p[0] - cart.p[0], cam.p[2] - cart.p[2]);
      assert.ok(horiz > TRACK_PIECES.loop.r * 2, `camera inside the loop at s=${ride.s.toFixed(1)}`);
    }
    if (cart.up[1] < 0) sawInvertedCart = true;
    prevCam = cam.p;
    prevCart = cart.p;
  }
  assert.ok(sawInvertedCart, 'the TRAIN must fully invert through the loop (the point!)');
});

test('coaster: rollBlendAt is 0 outside and 1 deep inside the loop span', () => {
  const asm = assembleTrack(LAYOUT);
  const span = loopSpanOf(asm);
  assert.equal(rollBlendAt(span, span.s0 - COASTER.ROLL_BLEND_LEN - 1), 0);
  assert.equal(rollBlendAt(span, span.s1 + COASTER.ROLL_BLEND_LEN + 1), 0);
  assert.equal(rollBlendAt(span, (span.s0 + span.s1) / 2), 1);
});

// ---------------------------------------------------------------------------
// Reduced motion: static-shot compile — the POV never rides the loop
// ---------------------------------------------------------------------------

test('coaster: reduced-motion shots tile the circuit; camera is static per shot', () => {
  const asm = assembleTrack(LAYOUT);
  const shots = staticShots(asm);
  assert.equal(shots[0].s0, 0);
  for (let i = 1; i < shots.length; i += 1) {
    assert.equal(shots[i].s0, shots[i - 1].s1, 'shot coverage gap');
  }
  assert.equal(shots[shots.length - 1].s1, asm.totalLen);
  // the loop span falls entirely inside ONE exterior shot…
  const span = loopSpanOf(asm);
  const shot = shotAt(shots, (span.s0 + span.s1) / 2);
  assert.equal(shotAt(shots, span.s0).id, shot.id);
  assert.equal(shotAt(shots, span.s1 - 1e-6).id, shot.id);
  // …whose camera stands OUTSIDE the loop circle (exterior view, no POV roll)
  const mid = pointAt(asm, (span.s0 + span.s1) / 2);
  assert.ok(Math.hypot(shot.cam[0] - mid.p[0], shot.cam[2] - mid.p[2]) > TRACK_PIECES.loop.r * 2);
});

test('coaster: reduced-motion cameraPose cuts between fixed shots, zero roll/fov kick', () => {
  const ride = createRide({ reducedMotion: true });
  const dt = 1 / 60;
  let lastByShot = new Map();
  while (ride.phase !== 'done' && ride.t < 120) {
    stepRide(ride, dt, {});
    const cam = cameraPose(ride);
    assert.deepEqual(cam.up, [0, 1, 0]);
    assert.equal(cam.fov01, 0);
    const shot = shotAt(ride.shots, ride.s);
    const prev = lastByShot.get(shot.id);
    if (prev) assert.deepEqual(cam.p, prev, 'static shot camera moved');
    lastByShot.set(shot.id, cam.p);
  }
  assert.ok(lastByShot.size >= 4, 'the ride should pass through several shots');
});

// ---------------------------------------------------------------------------
// Skip + watchdog (self-driven sequencer mirrors the director's semantics)
// ---------------------------------------------------------------------------

test('coaster: skip jumps to the brake run, drops the photo, still arrives', () => {
  const ride = createRide();
  stepRide(ride, COASTER.BOARD_SEC + 1, {}); // departs
  while (ride.s < ride.zones.lift.s0 + 2 && ride.t < 60) stepRide(ride, 1 / 60, {});
  const events = skipRide(ride);
  assert.ok(events.some((e) => e.type === 'skipped'));
  assert.equal(ride.s, ride.zones.brake.s0);
  assert.equal(ride.photoFired, true);
  const rest = [];
  while (ride.phase !== 'done' && ride.t < 120) rest.push(...stepRide(ride, 1 / 60, {}));
  assert.ok(rest.some((e) => e.type === 'arrived'));
  assert.ok(!rest.some((e) => e.type === 'photo'));
  // skipping again after arrival is a no-op
  assert.deepEqual(skipRide(ride), []);
});

test('coaster: skip inside the brake run is a no-op', () => {
  const ride = createRide();
  stepRide(ride, COASTER.BOARD_SEC + 1, {});
  ride.s = ride.zones.brake.s0 + 1;
  assert.deepEqual(skipRide(ride), []);
});

test('coaster: the watchdog force-finishes a stuck ride', () => {
  const ride = createRide();
  stepRide(ride, COASTER.BOARD_SEC + 1, {}); // riding
  ride.t = COASTER.WATCHDOG_SEC; // simulate a pathological stall
  const events = stepRide(ride, 1 / 60, {});
  assert.ok(events.some((e) => e.type === 'watchdog'));
  assert.ok(events.some((e) => e.type === 'arrived'));
  assert.equal(ride.phase, 'done');
});

// ---------------------------------------------------------------------------
// View-module contract (source scan — coasterRide.js imports three and must
// never enter this headless import chain; the particles.js TYPES precedent)
// ---------------------------------------------------------------------------

test('coaster: view module keeps the frozen export + dispose contract (source scan)', () => {
  const src = readFileSync(path.join(ROOT, 'src/park/coasterRide.js'), 'utf8');
  // frozen E1 integration export + scene id + preload keys
  assert.match(src, /export async function startCoasterRide\(/);
  assert.match(src, /export const COASTER_ASSET_KEYS/);
  assert.match(src, /'coasterRide'/);
  // onDone fires exactly once (single-fire guard)
  assert.match(src, /doneFired/);
  // full dispose: overlay + style teardown, gooby/particles release, music pop
  assert.match(src, /dispose\(\)/);
  assert.match(src, /popContext/);
  assert.match(src, /\.remove\(\)/);
  assert.match(src, /gooby\??\.dispose/);
  assert.match(src, /particles\??\.dispose/);
  // reduced motion honored + no arcade-framework surface (single-coaster ruling)
  assert.match(src, /prefersReducedMotion/);
  assert.ok(!src.includes('framework.launch'), 'the coaster is NOT an arcade game');
  assert.ok(!src.includes('runScore'), 'no score surface');
});
