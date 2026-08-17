// V6/F2 — transient garden bird visitor + petal-wipe helpers (PLAN6 Wave F).
// Pure node:test: the clock-hashed visit schedule, room/band/weather gates
// and the flight/hop/peck pose sampler from src/home/ambientLife.data.js,
// the petal-wipe pure math from src/ui/loadingVeil.js (field + stamp poses +
// variant selection), and source-scan invariants pinning the mount-side
// seams (ambientVisitors.js despawn/dispose rules, homeScene.js wiring) —
// the three.js mount files themselves never load under node, per AGENTS.md.

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  VISITOR,
  visitorCycleSpec,
  visitAt,
  visitorGate,
  activeVisit,
  visitPhase,
  visitorPose,
  WATCH,
} from '../src/home/ambientLife.data.js';
import {
  VEIL,
  PETAL,
  veilWipeVariant,
  petalField,
  petalStampPose,
} from '../src/ui/loadingVeil.js';
import { BANDS } from '../src/systems/dayNight.js';
import { WEATHER } from '../src/systems/weather.js';
import { ROOM as GARDEN } from '../src/home/rooms/garden.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = (rel) => fs.readFileSync(path.join(ROOT, ...rel.split('/')), 'utf8');

const BAND_IDS = BANDS.map((b) => b.id);
const PERCH = [-0.8, 0.62, -1.9]; // rooms/garden.js gardenFenceBird (checked below)

/** first scheduled visit at/after cycle 0 (the schedule is dense enough) */
function firstVisit() {
  for (let c = 0; c < 64; c += 1) {
    const spec = visitorCycleSpec(c);
    if (spec) return spec;
  }
  assert.fail('no visit in the first 64 cycles — VISIT_CHANCE broke');
  return null;
}

// ---------------------------------------------------------------------------
// VISITOR table
// ---------------------------------------------------------------------------

test('F2 VISITOR table: gates reference real rooms/bands/weather, anchor exists', () => {
  assert.ok(Object.isFrozen(VISITOR));
  assert.equal(VISITOR.ROOM, GARDEN.id, 'visitor lives in the garden');
  for (const b of VISITOR.BANDS) assert.ok(BAND_IDS.includes(b), `unknown band '${b}'`);
  assert.ok(!VISITOR.BANDS.includes('night'), 'birds sleep at night');
  for (const w of VISITOR.WEATHER) assert.ok(WEATHER.STATES.includes(w), `unknown weather '${w}'`);
  assert.ok(!VISITOR.WEATHER.includes('rain'), 'never during rain');
  // the E4 perch anchor is a real garden anchor — and our PERCH mirror is it
  assert.ok(VISITOR.ANCHOR in GARDEN.anchors, `garden lacks anchor '${VISITOR.ANCHOR}'`);
  assert.deepEqual([...GARDEN.anchors[VISITOR.ANCHOR]], PERCH, 'test PERCH mirror drifted');
  // envelope sanity
  assert.ok(VISITOR.STAY_MIN_SEC >= 10 && VISITOR.STAY_MAX_SEC <= 20, 'plan: hops/pecks ~10-20s');
  assert.ok(VISITOR.FLY_IN_SEC > 0 && VISITOR.FLY_OUT_SEC > 0);
  assert.ok(VISITOR.VISIT_CHANCE > 0 && VISITOR.VISIT_CHANCE < 1);
  // PLAN6 F2 budget: the bird adds at most 2 transient draw calls
  assert.ok(VISITOR.MAX_DRAW_CALLS <= 2);
  // the bird is worth a longer look than the default watch radii, and its
  // own radii keep the enter<exit hysteresis invariant
  assert.ok(VISITOR.WATCH_ENTER_RADIUS > WATCH.ENTER_RADIUS);
  assert.ok(VISITOR.WATCH_EXIT_RADIUS > VISITOR.WATCH_ENTER_RADIUS);
});

// ---------------------------------------------------------------------------
// Schedule (clock-hashed — deterministic, no saves)
// ---------------------------------------------------------------------------

test('F2 schedule: deterministic per cycle, visit rate tracks VISIT_CHANCE', () => {
  let visits = 0;
  for (let c = 0; c < 400; c += 1) {
    const a = visitorCycleSpec(c);
    const b = visitorCycleSpec(c);
    assert.deepEqual(a, b, `cycle ${c} not deterministic`);
    if (a) visits += 1;
  }
  // hash-rolled 60 % chance: allow a generous ±12 % band over 400 cycles
  const rate = visits / 400;
  assert.ok(Math.abs(rate - VISITOR.VISIT_CHANCE) < 0.12, `rate ${rate}`);
  // hostile cycles are quiet, never throw
  for (const junk of [-1, NaN, Infinity, 'x']) {
    assert.equal(visitorCycleSpec(junk), null, String(junk));
  }
});

test('F2 schedule: every visit fits inside its own cycle window', () => {
  for (let c = 0; c < 400; c += 1) {
    const spec = visitorCycleSpec(c);
    if (!spec) continue;
    const cycleStartMs = c * VISITOR.CYCLE_SEC * 1000;
    const cycleEndMs = (c + 1) * VISITOR.CYCLE_SEC * 1000;
    assert.ok(spec.startMs >= cycleStartMs, `cycle ${c}: starts early`);
    assert.ok(spec.endMs <= cycleEndMs, `cycle ${c}: spills into the next cycle`);
    assert.ok(spec.staySec >= VISITOR.STAY_MIN_SEC && spec.staySec <= VISITOR.STAY_MAX_SEC);
    assert.ok(
      Math.abs(spec.totalSec - (VISITOR.FLY_IN_SEC + spec.staySec + VISITOR.FLY_OUT_SEC)) < 1e-9
    );
    assert.ok(spec.side === -1 || spec.side === 1);
    assert.ok(spec.seed >= 0 && spec.seed < 1);
  }
  // worst-case visit always leaves slack (the slackSec > 0 invariant)
  assert.ok(
    VISITOR.FLY_IN_SEC + VISITOR.STAY_MAX_SEC + VISITOR.FLY_OUT_SEC < VISITOR.CYCLE_SEC,
    'longest possible visit must fit a cycle'
  );
});

test('F2 visitAt: live inside the window, null outside, hostile-safe', () => {
  const spec = firstVisit();
  assert.deepEqual(visitAt(spec.startMs), spec);
  assert.deepEqual(visitAt((spec.startMs + spec.endMs) / 2), spec);
  assert.equal(visitAt(spec.endMs), null, 'endMs is exclusive');
  assert.equal(visitAt(spec.startMs - 1), null);
  for (const junk of [NaN, -5, Infinity, 'x', undefined]) {
    assert.equal(visitAt(junk), null, String(junk));
  }
});

test('F2 gates: garden + daytime + dry only (the A3 row-gating pattern)', () => {
  const spec = firstVisit();
  const ms = spec.startMs + 1000;
  for (const band of VISITOR.BANDS) {
    for (const wx of VISITOR.WEATHER) {
      assert.equal(visitorGate('garden', band, wx), true, `${band}/${wx}`);
      assert.deepEqual(activeVisit('garden', band, wx, ms), spec);
    }
  }
  // wrong room / night / rain all fail closed
  for (const room of ['living', 'kitchen', 'bedroom', 'bathroom', null]) {
    assert.equal(visitorGate(room, 'day', 'clear'), false, String(room));
  }
  for (const band of BAND_IDS.filter((b) => !VISITOR.BANDS.includes(b))) {
    assert.equal(visitorGate('garden', band, 'clear'), false, band);
  }
  assert.equal(visitorGate('garden', 'day', 'rain'), false, 'rain');
  assert.equal(activeVisit('garden', 'day', 'rain', ms), null);
});

// ---------------------------------------------------------------------------
// Phases + pose sampler
// ---------------------------------------------------------------------------

test('F2 visitPhase: in → stay → out at the right boundaries, u in [0,1]', () => {
  const spec = firstVisit();
  const at = (sec) => visitPhase(spec, spec.startMs + sec * 1000);
  assert.equal(at(0).phase, 'in');
  assert.equal(at(VISITOR.FLY_IN_SEC - 0.01).phase, 'in');
  assert.equal(at(VISITOR.FLY_IN_SEC + 0.01).phase, 'stay');
  assert.equal(at(VISITOR.FLY_IN_SEC + spec.staySec + 0.01).phase, 'out');
  assert.equal(at(spec.totalSec + 99).phase, 'out', 'clamped past the end');
  for (const sec of [0, 1, VISITOR.FLY_IN_SEC + 2, spec.totalSec - 0.5, spec.totalSec]) {
    const p = at(sec);
    assert.ok(p.u >= 0 && p.u <= 1, `${sec}s: u=${p.u}`);
  }
});

test('F2 visitorPose: flight arcs land on the perch, stay hops around it', () => {
  const spec = firstVisit();
  const poseAt = (sec) => visitorPose(spec, spec.startMs + sec * 1000, PERCH);
  const [ox, oy, oz] = VISITOR.ENTRY_OFFSET;

  // fly-in starts at the entry offset on the visit's side…
  const start = poseAt(0);
  assert.equal(start.phase, 'in');
  assert.deepEqual(start.position, [PERCH[0] + spec.side * ox, PERCH[1] + oy, PERCH[2] + oz]);
  // …and converges to the perch by the end of the arc
  const landed = poseAt(VISITOR.FLY_IN_SEC - 0.001);
  for (let axis = 0; axis < 3; axis += 1) {
    assert.ok(Math.abs(landed.position[axis] - PERCH[axis]) < 0.01, `axis ${axis}`);
  }

  // perch dwell: never strays past hop height / shuffle bound / peck nudge
  for (let sec = VISITOR.FLY_IN_SEC; sec < VISITOR.FLY_IN_SEC + spec.staySec; sec += 0.1) {
    const p = poseAt(sec);
    assert.equal(p.phase, 'stay');
    assert.ok(Math.abs(p.position[0] - PERCH[0]) <= VISITOR.SHUFFLE_RANGE / 2 + 1e-9);
    assert.ok(p.position[1] >= PERCH[1] - 1e-9);
    assert.ok(p.position[1] <= PERCH[1] + VISITOR.HOP_HEIGHT + 1e-9);
    assert.ok(Math.abs(p.pitch) <= VISITOR.PECK_PITCH + 1e-9);
  }
  // it actually hops (some airtime) and pecks (some head-dip) during the stay
  const stays = [];
  for (let sec = VISITOR.FLY_IN_SEC; sec < VISITOR.FLY_IN_SEC + spec.staySec; sec += 0.05) {
    stays.push(poseAt(sec));
  }
  assert.ok(stays.some((p) => p.position[1] > PERCH[1] + VISITOR.HOP_HEIGHT * 0.5), 'no hop seen');
  assert.ok(stays.some((p) => p.pitch > VISITOR.PECK_PITCH * 0.5), 'no peck seen');

  // fly-out leaves toward the OPPOSITE side, climbing past the perch height
  const out = poseAt(spec.totalSec);
  assert.equal(out.phase, 'out');
  const awayX = (out.position[0] - PERCH[0]) * spec.side;
  assert.ok(awayX < 0, 'exits on the opposite side of the entry');
  assert.ok(out.position[1] > PERCH[1] + oy, 'climbs on the way out');

  // every sampled pose is finite with clamped flight pitch
  for (let sec = 0; sec <= spec.totalSec; sec += 0.25) {
    const p = poseAt(sec);
    assert.ok(p.position.every(Number.isFinite), `${sec}s: non-finite position`);
    assert.ok(Number.isFinite(p.yaw) && Number.isFinite(p.pitch), `${sec}s`);
    if (p.phase !== 'stay') assert.ok(Math.abs(p.pitch) <= 0.45 + 1e-9, `${sec}s flight pitch`);
  }

  // deterministic: the same timestamp always samples the same pose
  assert.deepEqual(poseAt(3.21), poseAt(3.21));
});

// ---------------------------------------------------------------------------
// Petal wipe pure helpers (src/ui/loadingVeil.js — V6/F2)
// ---------------------------------------------------------------------------

test('F2 PETAL consts: the 450 ms sweep + sane stamp tuning', () => {
  assert.ok(Object.isFrozen(PETAL));
  assert.equal(PETAL.WIPE_MS, 450, 'PLAN6 F2: same 450 ms window');
  // the reveal/cover fallbacks take max(iris, petal)+150 — the petal sweep
  // can therefore never outlive its own safety timers, but it must still
  // finish close to the iris windows so transitions feel identical
  assert.ok(PETAL.WIPE_MS <= Math.max(VEIL.IRIS_IN_MS, VEIL.IRIS_OUT_MS) + 150);
  assert.ok(PETAL.COUNT > 0);
  assert.ok(PETAL.SIZE_MAX > PETAL.SIZE_MIN && PETAL.SIZE_MIN > 0);
  assert.ok(PETAL.SLANT >= 0 && PETAL.SLANT < 0.5);
});

test('F2 veilWipeVariant: petal by default, iris without canvas, fade reduced', () => {
  for (const mode of ['home', 'trip', 'game', 'junk']) {
    assert.equal(veilWipeVariant(mode), 'petal', mode);
    assert.equal(veilWipeVariant(mode, { reducedMotion: true }), 'fade', mode);
    assert.equal(veilWipeVariant(mode, { canvasOk: false }), 'iris', mode);
    // reduced motion outranks the canvas probe
    assert.equal(veilWipeVariant(mode, { reducedMotion: true, canvasOk: false }), 'fade');
  }
});

test('F2 petalField: deterministic, in-range descriptors, both sprites used', () => {
  const a = petalField();
  const b = petalField();
  assert.deepEqual(a, b, 'same seed, same field');
  assert.equal(a.length, PETAL.COUNT);
  assert.notDeepEqual(petalField(PETAL.COUNT, 8), a, 'different seed, different field');
  for (const p of a) {
    assert.ok(p.lane >= 0 && p.lane <= 1);
    assert.ok(p.size >= PETAL.SIZE_MIN && p.size <= PETAL.SIZE_MAX);
    assert.ok(p.sprite === 0 || p.sprite === 1);
    assert.ok(Number.isFinite(p.ahead) && Number.isFinite(p.spin));
  }
  assert.ok(a.some((p) => p.sprite === 0) && a.some((p) => p.sprite === 1), 'both sprites');
  // hostile args floor at one petal
  assert.equal(petalField(0).length, 1);
  assert.equal(petalField(NaN, NaN).length, 1);
});

test('F2 petalStampPose: sweeps left→right, fades at both ends, stays finite', () => {
  const field = petalField();
  for (const petal of field) {
    // alpha ramps: invisible at the ends, opaque mid-sweep
    assert.equal(petalStampPose(petal, 0).alpha, 0);
    assert.equal(petalStampPose(petal, 1).alpha, 0);
    assert.equal(petalStampPose(petal, 0.5).alpha, 1);
    // x progresses with u (the sway is far smaller than the sweep speed)
    assert.ok(petalStampPose(petal, 0.8).x > petalStampPose(petal, 0.2).x, 'sweeps rightward');
    // y hugs the petal's lane
    assert.ok(Math.abs(petalStampPose(petal, 0.5).y - petal.lane) < 0.05);
    for (const u of [0, 0.25, 0.5, 0.75, 1, NaN, -3, 42]) {
      const pose = petalStampPose(petal, u);
      for (const v of [pose.x, pose.y, pose.rot, pose.alpha]) assert.ok(Number.isFinite(v));
      assert.ok(pose.alpha >= 0 && pose.alpha <= 1);
    }
  }
});

// ---------------------------------------------------------------------------
// Source-scan wiring invariants (the mount sides import three/DOM — pin the
// seams at source level; runtime proof is the F2 CDP screenshot set)
// ---------------------------------------------------------------------------

test('F2 wiring: ambientVisitors.js — reduced-motion no-op, despawn rules, no cache disposal', () => {
  const av = source('src/home/ambientVisitors.js');
  // reduced motion: inert (mount side never builds anything)
  assert.match(av, /prefersReducedMotion\(\)/);
  assert.match(av, /if \(disposed \|\| reducedMotion\) return;/);
  // room switch mid-visit despawns immediately via the rm event
  assert.match(av, /rm\.on\?\.\('roomChanged'/);
  assert.match(av, /if \(roomId !== VISITOR\.ROOM\) unmount\(\)/);
  // the clone must NEVER dispose shared cache masters — unmount drops refs
  // only (a `.dispose()` member call anywhere would evict master GPU buffers)
  assert.match(av, /bird\.parent\?\.remove\(bird\)/);
  const code = av.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
  assert.ok(!/\.dispose\(/.test(code), 'no resource .dispose() calls in ambientVisitors.js');
  // watch integration exposes the perch-phase bird only
  assert.match(av, /phase !== 'stay'\) return null/);
});

test('F2 wiring: homeScene.js — visitors + watch + hum ride the marked hooks', () => {
  const hs = source('src/home/homeScene.js');
  // lifecycle: create → setConditions → update → dispose (the A3 cadence)
  assert.match(hs, /visitors = createAmbientVisitors\(\{ rm \}\)/);
  assert.match(hs, /visitors\?\.setConditions\(amb\.band, amb\.weather\)/);
  assert.match(hs, /visitors\?\.update\(dt\)/);
  assert.match(hs, /visitors\?\.dispose\(\)/);
  // watch: pure decision on a fixed cadence, tap-look wins, candidates from
  // BOTH the A3 flutters and the F2 bird
  assert.match(hs, /watchTarget\(watchGoobyPos, watchCandidates, watchState, WATCH_TICK_SEC\)/);
  assert.match(hs, /lookTimer > 0/);
  assert.match(hs, /ambient\?\.getWatchables\(\)/);
  assert.match(hs, /visitors\?\.getWatchable\(\)/);
  // hum: mood-gated via the emotion machine, purr sfx, reduced-motion gate
  // on the note particles (motion), not on the sound
  assert.match(hs, /isHummingMood\(ambMachine\?\.get\?\.\(\) \?\? ''\)/);
  assert.match(hs, /ctx\.audio\?\.play\?\.\('gooby\.purr'\)/);
  assert.match(hs, /if \(!prefersReducedMotion\(\)\)/);
  assert.match(hs, /particles\.emit\('notes'/);
});

test('F2 wiring: particles.js gained the pooled vector-painted notes type', () => {
  const pj = source('src/gfx/particles.js');
  assert.match(pj, /notes: \{/);
  assert.match(pj, /getTexture\('note', drawNote\)/);
  // vector-painted (bezier head/stem/flag) — NOT a text glyph (emoji audit)
  assert.match(pj, /function drawNote\(/);
  assert.ok(!/fillText\('[^']*', s/.test(pj.slice(pj.indexOf('function drawNote'),
    pj.indexOf('function drawNote') + 1200)), 'note sprite must not be a text glyph');
});

test('F2 wiring: loadingVeil.js petal wipe — keyframes, reduced-motion fade, DEV slowdown guard', () => {
  const lv = source('src/ui/loadingVeil.js');
  assert.match(lv, /@keyframes acui-veil-sweep-in/);
  assert.match(lv, /@keyframes acui-veil-sweep-out/);
  // the classic iris keyframes REMAIN as the no-canvas fallback
  assert.match(lv, /@keyframes acui-veil-iris-in/);
  // reduced motion also outranks the petal class in CSS (belt-and-braces)
  assert.match(lv, /\.acui-veil\.acui-veil-petal\.acui-veil-in \{ animation: acui-veil-fade-in/);
  // the capture slowdown is DEV-guarded (inert in production builds)
  assert.match(lv, /if \(!import\.meta\.env\?\.DEV\) return 1;/);
  assert.match(lv, /veilslow/);
});
