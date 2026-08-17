// V6/A3 — batched home ambient life: pure-side tests (PLAN6 Wave A / A3).
// Imports PURE modules only (no three.js/DOM): the row table + gating +
// home samplers + disposal ledger from src/home/ambientLife.data.js, the
// reused recap samplers from src/recap/vignettes.logic.js, and the
// headless-importable room/band/weather sources the rows must stay in sync
// with (rooms/*.js defs, systems/dayNight.js, systems/weather.js).
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  AMBIENT_ROWS,
  AMBIENT_ROOM_IDS,
  AMBIENT_BAND_IDS,
  AMBIENT_WEATHER_IDS,
  MAX_AMBIENT_BATCHES_PER_ROOM,
  activeRows,
  roomBatchCount,
  fireflyPose,
  twinklePose,
  createDisposalLedger,
  // V6/F2: living-world pure logic (watch head-tracking + hum schedule)
  WATCH,
  createWatchState,
  watchTarget,
  HUM,
  isHummingMood,
  humDelaySec,
  humNoteCount,
} from '../src/home/ambientLife.data.js';
import { EMOTION_IDS } from '../src/character/emotions.js';
import { flutterPose, driftPose } from '../src/recap/vignettes.logic.js';
import { BANDS } from '../src/systems/dayNight.js';
import { WEATHER } from '../src/systems/weather.js';
import { ROOMS } from '../src/data/constants.js';
import { ROOM as KITCHEN } from '../src/home/rooms/kitchen.js';
import { ROOM as LIVING } from '../src/home/rooms/living.js';
import { ROOM as BATHROOM } from '../src/home/rooms/bathroom.js';
import { ROOM as BEDROOM } from '../src/home/rooms/bedroom.js';
import { ROOM as GARDEN } from '../src/home/rooms/garden.js';

const ROOM_DEFS = [KITCHEN, LIVING, BATHROOM, BEDROOM, GARDEN];
const BAND_IDS = BANDS.map((b) => b.id);
const KINDS = ['flutter', 'drift', 'twinkle', 'fireflies'];

/**
 * Static anchors a room registers (mirrors roomManager: entry.anchor +
 * entry.slot + Object.keys(def.anchors)) — headless-importable resolve list.
 */
function staticAnchorsOf(def) {
  const names = new Set(Object.keys(def.anchors));
  for (const entry of def.furniture) {
    if (entry.anchor) names.add(entry.anchor);
    if (entry.slot) names.add(entry.slot);
  }
  return names;
}

const isFiniteTriple = (v) =>
  Array.isArray(v) && v.length === 3 && v.every((n) => Number.isFinite(n));

// ---------------------------------------------------------------------------
// Row-table validation
// ---------------------------------------------------------------------------

test('ambient id mirrors match the engine sources (rooms/bands/weather)', () => {
  assert.deepEqual([...AMBIENT_ROOM_IDS], [...ROOMS.ORDER, GARDEN.id]);
  assert.deepEqual([...AMBIENT_BAND_IDS].sort(), [...BAND_IDS].sort());
  assert.deepEqual([...AMBIENT_WEATHER_IDS], [...WEATHER.STATES]);
});

test('every row validates: ids, rooms, kinds, gates, anchors, positions', () => {
  const ids = new Set();
  const roomIds = new Set(ROOM_DEFS.map((d) => d.id));
  for (const row of AMBIENT_ROWS) {
    assert.equal(typeof row.id, 'string', 'row id');
    assert.ok(!ids.has(row.id), `duplicate row id ${row.id}`);
    ids.add(row.id);
    assert.ok(roomIds.has(row.room), `${row.id}: unknown room '${row.room}'`);
    assert.ok(KINDS.includes(row.kind), `${row.id}: unknown kind '${row.kind}'`);

    assert.ok(row.bands.length > 0, `${row.id}: empty band gate`);
    for (const b of row.bands) {
      assert.ok(BAND_IDS.includes(b), `${row.id}: unknown band '${b}'`);
    }
    assert.ok(row.weather.length > 0, `${row.id}: empty weather gate`);
    for (const w of row.weather) {
      assert.ok(WEATHER.STATES.includes(w), `${row.id}: unknown weather '${w}'`);
    }

    assert.ok(isFiniteTriple(row.at), `${row.id}: at must be [x,y,z]`);
    if (row.anchor != null) {
      const def = ROOM_DEFS.find((d) => d.id === row.room);
      assert.ok(
        staticAnchorsOf(def).has(row.anchor),
        `${row.id}: anchor '${row.anchor}' not registered by rooms/${row.room}.js`
      );
    }
    assert.equal(typeof row.tex, 'string', `${row.id}: tex`);
  }
});

test('per-kind motion params are present and sane', () => {
  for (const row of AMBIENT_ROWS) {
    if (row.kind === 'flutter') {
      for (const k of ['radius', 'bob', 'speed', 'flapHz', 'phase', 'scale']) {
        assert.ok(Number.isFinite(row[k]), `${row.id}: flutter needs ${k}`);
      }
      assert.ok(row.speed > 0 && row.speed <= 0.3, `${row.id}: cozy orbit speed`);
    } else if (row.kind === 'drift') {
      for (const k of ['rise', 'sway', 'speed', 'phase', 'opacity', 'scale']) {
        assert.ok(Number.isFinite(row[k]), `${row.id}: drift needs ${k}`);
      }
      assert.ok(row.opacity > 0 && row.opacity <= 0.6, `${row.id}: subtle opacity`);
    } else if (row.kind === 'twinkle') {
      for (const k of ['baseOpacity', 'amp', 'period', 'phase', 'scale']) {
        assert.ok(Number.isFinite(row[k]), `${row.id}: twinkle needs ${k}`);
      }
      assert.ok(row.period >= 3, `${row.id}: decorative loops stay slow (≥3 s)`);
    } else if (row.kind === 'fireflies') {
      assert.ok(Number.isInteger(row.count) && row.count > 0 && row.count <= 32,
        `${row.id}: instanced count bounded`);
      for (const axis of ['x', 'y', 'z']) {
        const [lo, hi] = row.area[axis];
        assert.ok(Number.isFinite(lo) && Number.isFinite(hi) && lo < hi,
          `${row.id}: area.${axis}`);
      }
      assert.ok(row.wander > 0 && row.wander < 1, `${row.id}: wander bounded`);
      assert.ok(row.blinkHz[0] > 0 && row.blinkHz[1] >= row.blinkHz[0],
        `${row.id}: blinkHz range`);
      assert.ok(row.size[0] > 0 && row.size[1] >= row.size[0], `${row.id}: size range`);
    }
  }
});

test('every room has at least one ambient row somewhere in its gate space', () => {
  for (const roomId of AMBIENT_ROOM_IDS) {
    assert.ok(
      AMBIENT_ROWS.some((r) => r.room === roomId),
      `room '${roomId}' has no ambient life`
    );
  }
});

// ---------------------------------------------------------------------------
// Band/weather gating (pure activeRows)
// ---------------------------------------------------------------------------

test('garden: butterflies+bee by day, one instanced firefly batch at night, nothing in rain', () => {
  const day = activeRows('garden', 'day', 'clear').map((r) => r.id);
  assert.deepEqual(day, ['gardenButterflyGold', 'gardenButterflyPink', 'gardenBee']);
  const night = activeRows('garden', 'night', 'clear');
  assert.deepEqual(night.map((r) => r.id), ['gardenFireflies']);
  assert.equal(night[0].kind, 'fireflies'); // 24 instances, exactly 1 draw batch
  assert.deepEqual(activeRows('garden', 'day', 'rain'), []);
  assert.deepEqual(activeRows('garden', 'night', 'rain'), []);
  assert.deepEqual(activeRows('garden', 'dusk', 'clear'), []);
});

test('kitchen steam is always on; living motes are daylight-only', () => {
  for (const band of BAND_IDS) {
    for (const wx of WEATHER.STATES) {
      assert.equal(roomBatchCount('kitchen', band, wx), 3, `kitchen ${band}/${wx}`);
    }
  }
  assert.equal(roomBatchCount('living', 'day', 'clear'), 3);
  assert.equal(roomBatchCount('living', 'dawn', 'cloudy'), 3);
  assert.equal(roomBatchCount('living', 'day', 'rain'), 0);
  assert.equal(roomBatchCount('living', 'night', 'clear'), 0);
});

test('bathroom bubbles always drift; bedroom stars only on clear nights', () => {
  for (const band of BAND_IDS) {
    for (const wx of WEATHER.STATES) {
      assert.equal(roomBatchCount('bathroom', band, wx), 3, `bathroom ${band}/${wx}`);
    }
  }
  assert.equal(roomBatchCount('bedroom', 'night', 'clear'), 2);
  assert.equal(roomBatchCount('bedroom', 'night', 'cloudy'), 0);
  assert.equal(roomBatchCount('bedroom', 'day', 'clear'), 0);
});

test('draw-batch budget: ≤4 batches per room for EVERY band/weather combo', () => {
  assert.equal(MAX_AMBIENT_BATCHES_PER_ROOM, 4); // PLAN6 §A3 guardrail
  for (const roomId of AMBIENT_ROOM_IDS) {
    for (const band of BAND_IDS) {
      for (const wx of WEATHER.STATES) {
        const n = roomBatchCount(roomId, band, wx);
        assert.ok(
          n <= MAX_AMBIENT_BATCHES_PER_ROOM,
          `${roomId} ${band}/${wx}: ${n} batches > ${MAX_AMBIENT_BATCHES_PER_ROOM}`
        );
        assert.equal(n, activeRows(roomId, band, wx).length);
      }
    }
  }
});

// ---------------------------------------------------------------------------
// Sampler determinism + bounds (recap samplers reused, home samplers new)
// ---------------------------------------------------------------------------

test('flutter rows stay bounded around their center through the recap sampler', () => {
  for (const row of AMBIENT_ROWS.filter((r) => r.kind === 'flutter')) {
    const sRow = { ...row, center: [1, 1.2, 0.5] };
    for (let t = 0; t <= 60; t += 0.37) {
      const pose = flutterPose(sRow, t);
      assert.ok(Math.abs(pose.position[0] - 1) <= row.radius + 1e-9, `${row.id} x`);
      assert.ok(Math.abs(pose.position[1] - 1.2) <= row.bob + 1e-9, `${row.id} y`);
      assert.ok(Math.abs(pose.position[2] - 0.5) <= row.radius * 0.7 + 1e-9, `${row.id} z`);
      assert.ok(pose.flap >= 0 && pose.flap <= 1, `${row.id} flap`);
    }
    // deterministic: same (row, t) → same pose
    assert.deepEqual(flutterPose(sRow, 12.34), flutterPose(sRow, 12.34));
  }
});

test('drift rows are periodic (loop period 1/speed) and fade to 0 at the seam', () => {
  for (const row of AMBIENT_ROWS.filter((r) => r.kind === 'drift')) {
    const sRow = { ...row, origin: [0, 1, 0] };
    const period = 1 / row.speed;
    for (const t of [0.5, 3.1, 7.7]) {
      const a = driftPose(sRow, t);
      const b = driftPose(sRow, t + period);
      for (let k = 0; k < 3; k += 1) {
        assert.ok(Math.abs(a.position[k] - b.position[k]) < 1e-6, `${row.id} periodic pos`);
      }
      assert.ok(Math.abs(a.opacity - b.opacity) < 1e-6, `${row.id} periodic opacity`);
      assert.ok(a.opacity >= 0 && a.opacity <= row.opacity + 1e-9, `${row.id} opacity bound`);
      // rise stays within [0, rise]; sway within ±sway
      assert.ok(a.position[1] >= 1 - 1e-9 && a.position[1] <= 1 + row.rise + 1e-9, `${row.id} rise`);
      assert.ok(Math.abs(a.position[0]) <= row.sway + 1e-9, `${row.id} sway`);
    }
    // loop-seam fade: u = 0 → opacity 0 (the bubble "pop" / wisp respawn)
    const seamT = (1 - row.phase) / row.speed;
    assert.ok(driftPose(sRow, seamT).opacity < 1e-6, `${row.id} seam fade`);
  }
});

test('fireflyPose: deterministic, area-bounded, blink/size in range', () => {
  const row = AMBIENT_ROWS.find((r) => r.id === 'gardenFireflies');
  const margin = row.wander * 1.5 + 1e-9;
  for (let i = 0; i < row.count; i += 1) {
    for (const t of [0, 1.3, 17.9, 240.5]) {
      const pose = fireflyPose(row, i, t);
      assert.deepEqual(pose, fireflyPose(row, i, t), 'deterministic');
      const [x, y, z] = pose.position;
      assert.ok(x >= row.area.x[0] - margin && x <= row.area.x[1] + margin, `i${i} x`);
      assert.ok(y >= row.area.y[0] - margin && y <= row.area.y[1] + margin, `i${i} y`);
      assert.ok(z >= row.area.z[0] - margin && z <= row.area.z[1] + margin, `i${i} z`);
      assert.ok(pose.blink >= 0 && pose.blink <= 1, `i${i} blink`);
      assert.ok(pose.size >= row.size[0] && pose.size <= row.size[1], `i${i} size`);
    }
  }
  // instances are spread out, not stacked on one spot
  const xs = new Set();
  for (let i = 0; i < row.count; i += 1) {
    xs.add(Math.round(fireflyPose(row, i, 0).position[0] * 10));
  }
  assert.ok(xs.size >= row.count / 2, 'instances spread across the area');
});

test('twinklePose: bounded 0..1 opacity, periodic, subtle pulse', () => {
  for (const row of AMBIENT_ROWS.filter((r) => r.kind === 'twinkle')) {
    for (let t = 0; t <= 40; t += 0.29) {
      const pose = twinklePose(row, t);
      assert.ok(pose.opacity >= 0 && pose.opacity <= 1, `${row.id} opacity`);
      assert.ok(pose.pulse >= 0.9 && pose.pulse <= 1.1, `${row.id} pulse subtle`);
    }
    const a = twinklePose(row, 2.2);
    const b = twinklePose(row, 2.2 + row.period);
    assert.ok(Math.abs(a.opacity - b.opacity) < 1e-6, `${row.id} periodic`);
    assert.deepEqual(twinklePose(row, 5.5), twinklePose(row, 5.5), 'deterministic');
  }
});

// ---------------------------------------------------------------------------
// Disposal ledger (pure registry model the mount side wraps its resources in)
// ---------------------------------------------------------------------------

test('disposal ledger: tracks, disposes exactly once each, then reads empty', () => {
  const ledger = createDisposalLedger();
  const calls = [];
  const res = (name) => ({ name, dispose: () => calls.push(name) });
  const a = ledger.track(res('geoA'), 'geometry');
  ledger.track(res('matA'), 'material');
  ledger.track(res('matB'), 'material');
  ledger.track(res('texA'), 'texture');
  assert.equal(a.name, 'geoA'); // track() passes the resource through
  assert.equal(ledger.outstanding(), 4);
  assert.deepEqual(ledger.byKind(), { geometry: 1, material: 2, texture: 1 });

  assert.equal(ledger.disposeAll(), 4);
  assert.deepEqual(calls.sort(), ['geoA', 'matA', 'matB', 'texA']);
  assert.equal(ledger.outstanding(), 0);
  assert.deepEqual(ledger.byKind(), {});
  assert.equal(ledger.disposeAll(), 0, 'idempotent — nothing disposed twice');
  assert.deepEqual(calls.length, 4);
});

test('disposal ledger: a throwing dispose never strands later resources', () => {
  const ledger = createDisposalLedger();
  const calls = [];
  ledger.track({ dispose: () => { throw new Error('boom'); } }, 'material');
  ledger.track({ dispose: () => calls.push('ok') }, 'texture');
  ledger.track({}, 'no-dispose-fn'); // dispose-less entries are tolerated
  assert.equal(ledger.disposeAll(), 3);
  assert.deepEqual(calls, ['ok']);
  assert.equal(ledger.outstanding(), 0);
});

// ---------------------------------------------------------------------------
// Mount/swap/dispose bookkeeping model (pure mirror of ambientLife.js)
// ---------------------------------------------------------------------------

test('mount/swap ledger model: every band/weather swap frees the old batch set', () => {
  // Pure simulation of ambientLife.js's remount flow: one material per row
  // (+1 geometry+material for fireflies) tracked per mount, disposed on swap.
  const mountResources = (roomId, band, wx) => {
    const ledger = createDisposalLedger();
    for (const row of activeRows(roomId, band, wx)) {
      ledger.track({ dispose: () => {} }, 'material');
      if (row.kind === 'fireflies') ledger.track({ dispose: () => {} }, 'geometry');
    }
    return ledger;
  };
  for (const roomId of AMBIENT_ROOM_IDS) {
    let ledger = null;
    for (const [band, wx] of [
      ['day', 'clear'], ['dusk', 'clear'], ['night', 'clear'],
      ['night', 'rain'], ['dawn', 'cloudy'],
    ]) {
      if (ledger) {
        ledger.disposeAll();
        assert.equal(ledger.outstanding(), 0, `${roomId}: swap leaked`);
      }
      ledger = mountResources(roomId, band, wx);
      const rows = activeRows(roomId, band, wx);
      const wantMats = rows.length;
      const wantGeos = rows.filter((r) => r.kind === 'fireflies').length;
      assert.deepEqual(
        ledger.byKind(),
        {
          ...(wantMats ? { material: wantMats } : {}),
          ...(wantGeos ? { geometry: wantGeos } : {}),
        },
        `${roomId} ${band}/${wx} resource shape`
      );
    }
    ledger?.disposeAll();
    assert.equal(ledger.outstanding(), 0);
  }
});

// ---------------------------------------------------------------------------
// V6/F2 — WATCH: Gooby's head-tracking decision logic (hysteresis)
// ---------------------------------------------------------------------------

const GOOBY_AT = { x: 0, y: 0.5, z: 0 };
/** sprite factory at a given distance along +x from GOOBY_AT */
const spriteAt = (id, dist, extra = {}) => ({
  id, pos: { x: dist, y: 0.5, z: 0 }, ...extra,
});

test('F2 WATCH consts: hysteresis gap, positive cadences, lost < full cooldown', () => {
  assert.ok(Object.isFrozen(WATCH));
  assert.ok(WATCH.EXIT_RADIUS > WATCH.ENTER_RADIUS, 'exit > enter (hysteresis)');
  assert.ok(WATCH.MAX_WATCH_SEC > 0 && WATCH.COOLDOWN_SEC > 0);
  assert.ok(WATCH.LOST_COOLDOWN_SEC < WATCH.COOLDOWN_SEC, 'lost breather is shorter');
  assert.ok(WATCH.TWITCH_EVERY_SEC > 0 && WATCH.TWITCH_EVERY_SEC < WATCH.MAX_WATCH_SEC);
});

test('F2 watchTarget: acquires the NEAREST sprite inside its enter radius', () => {
  const sprites = [
    spriteAt('far', WATCH.ENTER_RADIUS + 0.1), // outside — never a candidate
    spriteAt('near', 1.0),
    spriteAt('nearer', 0.6),
  ];
  const r = watchTarget(GOOBY_AT, sprites, createWatchState(), 0.25);
  assert.equal(r.target?.id, 'nearer');
  assert.equal(r.state.id, 'nearer');
  assert.equal(r.twitched, false, 'no twitch on acquisition');
});

test('F2 watchTarget: holds through the enter/exit hysteresis band (no jitter)', () => {
  // acquire at 1.0, then the sprite drifts BEYOND enter but INSIDE exit —
  // a stateless nearest-inside-enter pick would drop it (jitter); ours holds.
  let state = watchTarget(GOOBY_AT, [spriteAt('b', 1.0)], createWatchState(), 0.25).state;
  const between = (WATCH.ENTER_RADIUS + WATCH.EXIT_RADIUS) / 2;
  const r = watchTarget(GOOBY_AT, [spriteAt('b', between)], state, 0.25);
  assert.equal(r.target?.id, 'b', 'held inside the hysteresis band');
  // …but past the exit radius the hold breaks with the SHORT lost cooldown
  const r2 = watchTarget(GOOBY_AT, [spriteAt('b', WATCH.EXIT_RADIUS + 0.05)], r.state, 0.25);
  assert.equal(r2.target, null);
  assert.equal(r2.state.cooldownSec, WATCH.LOST_COOLDOWN_SEC);
});

test('F2 watchTarget: full watch ends at MAX_WATCH_SEC with the full cooldown', () => {
  let state = watchTarget(GOOBY_AT, [spriteAt('b', 1)], createWatchState(), 0.25).state;
  let target = null;
  let steps = 0;
  for (; steps < 200; steps += 1) {
    const r = watchTarget(GOOBY_AT, [spriteAt('b', 1)], state, 0.25);
    state = r.state;
    target = r.target;
    if (!target) break;
  }
  assert.equal(target, null, 'watch released');
  assert.ok(steps * 0.25 <= WATCH.MAX_WATCH_SEC + 0.5, 'released near MAX_WATCH_SEC');
  assert.equal(state.cooldownSec, WATCH.COOLDOWN_SEC, 'full cooldown after a full watch');
  // cooldown blocks re-acquisition and counts down monotonically
  const blocked = watchTarget(GOOBY_AT, [spriteAt('b', 1)], state, 0.25);
  assert.equal(blocked.target, null);
  assert.ok(blocked.state.cooldownSec < state.cooldownSec);
});

test('F2 watchTarget: twitch beats fire exactly on TWITCH_EVERY_SEC boundaries', () => {
  let state = watchTarget(GOOBY_AT, [spriteAt('b', 1)], createWatchState(), 0.25).state;
  const twitchTimes = [];
  for (let t = 0; t < WATCH.MAX_WATCH_SEC - 0.25; t += 0.25) {
    const r = watchTarget(GOOBY_AT, [spriteAt('b', 1)], state, 0.25);
    if (!r.target) break;
    if (r.twitched) twitchTimes.push(r.state.heldSec);
    state = r.state;
  }
  assert.ok(twitchTimes.length >= 2, `expected ≥2 twitch beats, got ${twitchTimes.length}`);
  for (const [i, at] of twitchTimes.entries()) {
    const boundary = (i + 1) * WATCH.TWITCH_EVERY_SEC;
    assert.ok(Math.abs(at - boundary) <= 0.25 + 1e-9, `beat ${i} at ${at}, boundary ${boundary}`);
  }
});

test('F2 watchTarget: per-sprite radius overrides (the fence bird) are honored', () => {
  const bird = spriteAt('bird', WATCH.ENTER_RADIUS + 1, {
    enterRadius: WATCH.ENTER_RADIUS + 2,
    exitRadius: WATCH.ENTER_RADIUS + 2.5,
  });
  const r = watchTarget(GOOBY_AT, [bird], createWatchState(), 0.25);
  assert.equal(r.target?.id, 'bird', 'bird acquired beyond the default radius');
});

test('F2 watchTarget: pure — never mutates state/sprites, arrays or objects for pos', () => {
  const state = createWatchState();
  const frozen = Object.freeze({ ...state });
  const sprites = [
    { id: 'a', pos: [1, 0.5, 0] }, // array-form positions must work too
    spriteAt('b', 0.4),
  ];
  const snapshot = JSON.stringify(sprites);
  const r1 = watchTarget([0, 0.5, 0], sprites, state, 0.25);
  const r2 = watchTarget([0, 0.5, 0], sprites, state, 0.25);
  assert.deepEqual(r1.state, r2.state, 'same inputs, same outputs');
  assert.equal(r1.target?.id, 'b');
  assert.deepEqual({ ...state }, { ...frozen }, 'input state untouched');
  assert.equal(JSON.stringify(sprites), snapshot, 'sprites untouched');
  // hostile inputs never throw
  assert.doesNotThrow(() => watchTarget(GOOBY_AT, null, null, NaN));
});

// ---------------------------------------------------------------------------
// V6/F2 — HUM: happy-idle humming schedule
// ---------------------------------------------------------------------------

test('F2 HUM consts: sane ranges, moods are real emotion ids', () => {
  assert.ok(Object.isFrozen(HUM));
  assert.ok(HUM.DELAY_MIN_SEC > 0 && HUM.DELAY_MAX_SEC > HUM.DELAY_MIN_SEC);
  assert.ok(HUM.FIRST_FRAC > 0 && HUM.FIRST_FRAC < 1);
  assert.ok(HUM.NOTES_MIN >= 1 && HUM.NOTES_MAX >= HUM.NOTES_MIN);
  assert.ok(HUM.NOTE_SPACING_SEC > 0);
  for (const mood of HUM.MOODS) {
    assert.ok(EMOTION_IDS.includes(mood), `HUM mood '${mood}' is not an emotion id`);
  }
  // sad/neutral/sleepy Goobys don't hum
  assert.equal(isHummingMood('happy'), true);
  assert.equal(isHummingMood('ecstatic'), true);
  for (const id of ['neutral', 'sad', 'sleepy', 'grumpy', 'sick', '']) {
    assert.equal(isHummingMood(id), false, id);
  }
});

test('F2 humDelaySec: bounded by the DELAY range, first hum comes sooner', () => {
  assert.equal(humDelaySec(() => 0), HUM.DELAY_MIN_SEC);
  assert.equal(humDelaySec(() => 1), HUM.DELAY_MAX_SEC);
  const mid = humDelaySec(() => 0.5);
  assert.ok(mid > HUM.DELAY_MIN_SEC && mid < HUM.DELAY_MAX_SEC);
  assert.equal(humDelaySec(() => 0.5, { first: true }), mid * HUM.FIRST_FRAC);
});

test('F2 humNoteCount: NOTES_MIN…NOTES_MAX inclusive, integer', () => {
  assert.equal(humNoteCount(() => 0), HUM.NOTES_MIN);
  assert.equal(humNoteCount(() => 0.999999), HUM.NOTES_MAX);
  for (const r of [0, 0.2, 0.4, 0.6, 0.8, 0.99]) {
    const n = humNoteCount(() => r);
    assert.ok(Number.isInteger(n) && n >= HUM.NOTES_MIN && n <= HUM.NOTES_MAX, String(r));
  }
});
