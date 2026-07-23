// V6/A1 — cutscene director suite: the PURE sequencer (compile validation,
// reduced-motion collapse, deterministic sequence/parallel/wait advancement,
// tapWait timeout fallback, watchdog force-finish, first-view hold-skip vs
// replay tap-skip, keepOnSkip application), the bounded `cutscenes` save
// slice, and the DATA-MIRROR test: every op/clip/emotion/sample id and EN/DE
// caption key referenced by data/cutscenes.js is validated against the real
// registries (the onboarding source scanner cannot see data-driven ids).
// Headless per §B — pure modules only (gfx/particles.js imports three, so
// its TYPES table is mirrored via a source scan like onboarding's sfx scan).

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

import {
  CUTSCENE,
  CUTSCENE_PARTICLE_TYPES,
  compileScript,
  createCutscenePlayer,
  defaultSlice,
  sliceOf,
  markSeenSlice,
  hasSeen,
} from '../src/systems/cutscene.js';
import { CUTSCENE_IDS, getCutscene } from '../src/data/cutscenes.js';
import { EN as CUT_EN, DE as CUT_DE } from '../src/data/strings/v6-cutscenes.js';
import { CLIP_IDS } from '../src/character/goobyAnims.js';
import { EMOTION_IDS } from '../src/character/emotions.js';
import { SFX_MAP } from '../src/audio/sfxMap.js';
import { HARNESS_PARAM_GROUPS, allHarnessParams } from '../src/data/harnessParams.js';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

/** @param {object[]} steps @returns {object} minimal valid script */
function script(steps) {
  return { id: 'testScript', steps };
}

/**
 * Player harness: compiled script + a hook log of every applied op.
 * @param {object[]} steps
 * @param {{replay?: boolean, reducedMotion?: boolean}} [opts]
 */
function rig(steps, opts = {}) {
  const compiled = compileScript(script(steps), { reducedMotion: opts.reducedMotion === true });
  /** @type {{op: string, id: string|undefined, skipped: boolean}[]} */
  const log = [];
  const player = createCutscenePlayer(compiled, {
    apply(op, info) {
      log.push({
        op: op.op,
        id: op.clip ?? op.emotion ?? op.sfx ?? op.key ?? op.type,
        skipped: info.skipped,
      });
    },
  }, { replay: opts.replay === true });
  return { compiled, player, log };
}

/** tick in watchdog-safe chunks (player clamps dt at 0.25 s per call) */
function tickBy(player, seconds) {
  let left = seconds;
  while (left > 1e-9) {
    const dt = Math.min(0.25, left);
    player.tick(dt);
    left -= dt;
  }
}

/** Recursively collect leaf steps of a raw script. @returns {object[]} */
function leafSteps(steps) {
  const out = [];
  for (const s of steps) {
    if (Array.isArray(s.steps)) out.push(...leafSteps(s.steps));
    else out.push(s);
  }
  return out;
}

// ---------------------------------------------------------------------------
// compile — validation + clamping
// ---------------------------------------------------------------------------

test('compile: the demo script compiles and reports a bounded duration', () => {
  const compiled = compileScript(getCutscene('demo'));
  assert.equal(compiled.id, 'demo');
  assert.ok(compiled.steps.length > 0);
  assert.ok(compiled.totalSec > 0);
  assert.ok(compiled.totalSec < CUTSCENE.WATCHDOG_SEC, 'demo must outrun the watchdog');
  assert.ok(Object.isFrozen(compiled) && Object.isFrozen(compiled.steps));
});

test('compile: malformed scripts are rejected', () => {
  assert.throws(() => compileScript(null), /script/);
  assert.throws(() => compileScript([]), /script/);
  assert.throws(() => compileScript({ steps: [{ op: 'wait', duration: 1 }] }), /id/);
  assert.throws(() => compileScript(script([])), /steps/);
  assert.throws(() => compileScript(script(['nope'])), /object/);
  assert.throws(() => compileScript(script([{ op: 'teleport' }])), /unknown op/);
  assert.throws(() => compileScript(script([{ op: 'wait' }])), /duration/);
  assert.throws(() => compileScript(script([{ op: 'wait', duration: -2 }])), /duration/);
  assert.throws(() => compileScript(script([{ op: 'caption' }])), /caption/);
  assert.throws(() => compileScript(script([{ op: 'clip' }])), /clip/);
  assert.throws(() => compileScript(script([{ op: 'emotion', emotion: 7 }])), /emotion/);
  assert.throws(() => compileScript(script([{ op: 'sfx' }])), /sfx/);
  assert.throws(() => compileScript(script([{ op: 'camera', move: 'barrelRoll' }])), /camera move/);
  assert.throws(() => compileScript(script([{ op: 'particles', type: 'lasers' }])), /particle type/);
  assert.throws(() => compileScript(script([{ op: 'sequence', steps: [] }])), /steps/);
  assert.throws(() => compileScript(script([{ op: 'prop', action: 'spawn', propId: 'x' }])), /model/);
  assert.throws(() => compileScript(script([{ op: 'prop', action: 'yeet', propId: 'x' }])), /prop action/);
  assert.throws(
    () => compileScript(script([{
      op: 'prop', action: 'spawn', propId: 'x', model: 'm', offset: [1, 2],
    }])),
    /offset/,
  );
});

test('compile: nesting depth and op count are bounded', () => {
  let nested = { op: 'wait', duration: 1 };
  for (let i = 0; i <= CUTSCENE.MAX_DEPTH; i += 1) {
    nested = { op: 'sequence', steps: [nested] };
  }
  assert.throws(() => compileScript(script([nested])), /nested/);
  const many = Array.from({ length: CUTSCENE.MAX_OPS + 1 }, () => ({ op: 'captionClear' }));
  assert.throws(() => compileScript(script(many)), /ops/);
});

test('compile: durations clamp; tapWait ALWAYS gets a timeout fallback', () => {
  const compiled = compileScript(script([
    { op: 'wait', duration: 999 },
    { op: 'camera', move: 'pushIn', duration: 999 },
    { op: 'tapWait' }, // no timeout given
    { op: 'tapWait', timeout: 'junk' },
    { op: 'tapWait', timeout: 999 },
    { op: 'tapWait', timeout: 0.01 },
    { op: 'particles', type: 'sparkles', count: 9999 },
  ]));
  assert.equal(compiled.steps[0].duration, CUTSCENE.MAX_STEP_SEC);
  assert.equal(compiled.steps[1].duration, CUTSCENE.MAX_STEP_SEC);
  assert.equal(compiled.steps[2].timeout, CUTSCENE.TAPWAIT_DEFAULT_SEC);
  assert.equal(compiled.steps[3].timeout, CUTSCENE.TAPWAIT_DEFAULT_SEC);
  assert.equal(compiled.steps[4].timeout, CUTSCENE.TAPWAIT_MAX_SEC);
  assert.equal(compiled.steps[5].timeout, CUTSCENE.TAPWAIT_MIN_SEC);
  assert.equal(compiled.steps[6].count, CUTSCENE.MAX_PARTICLE_COUNT);
});

test('compile: reduced motion collapses camera moves and shortens waits', () => {
  const steps = [
    { op: 'camera', move: 'pushIn', duration: 2 },
    { op: 'wait', duration: 5 },
    { op: 'wait', duration: 0.2 },
  ];
  const normal = compileScript(script(steps));
  assert.equal(normal.steps[0].duration, 2);
  assert.equal(normal.steps[1].duration, 5);
  const reduced = compileScript(script(steps), { reducedMotion: true });
  assert.equal(reduced.steps[0].duration, 0, 'camera collapses to a cut');
  assert.equal(reduced.steps[1].duration, CUTSCENE.REDUCED_WAIT_MAX_SEC);
  assert.equal(reduced.steps[2].duration, 0.2, 'short waits stay');
  assert.ok(reduced.totalSec < normal.totalSec);
});

// ---------------------------------------------------------------------------
// player — deterministic advancement
// ---------------------------------------------------------------------------

test('player: sequence advances deterministically through waits + instant ops', () => {
  const { player, log } = rig([
    { op: 'wait', duration: 1 },
    { op: 'sfx', sfx: 'ui.tap' },
    { op: 'caption', key: 'cutscene.demo.hello' },
    { op: 'wait', duration: 1 },
  ]);
  player.start();
  assert.equal(player.getState(), 'playing');
  tickBy(player, 0.5);
  assert.deepEqual(log.map((e) => e.op), ['wait'], 'only the first wait started');
  tickBy(player, 0.5); // wait 1 completes; instant ops chain; wait 2 blocks
  assert.deepEqual(log.map((e) => e.op), ['wait', 'sfx', 'caption', 'wait']);
  assert.equal(player.getState(), 'playing');
  assert.ok(player.getProgress() > 0.4 && player.getProgress() < 0.7);
  tickBy(player, 1.0);
  assert.equal(player.getState(), 'done');
  assert.equal(player.getFinishReason(), 'completed');
  assert.equal(player.getProgress(), 1);
});

test('player: parallel lanes run together and finish on the slowest', () => {
  const { player, log } = rig([
    {
      op: 'parallel',
      steps: [
        { op: 'wait', duration: 1 },
        { op: 'wait', duration: 2 },
        { op: 'emotion', emotion: 'happy' },
      ],
    },
    { op: 'sfx', sfx: 'ui.tap' },
  ]);
  player.start();
  tickBy(player, 0.25); // all lanes start on the first tick
  assert.deepEqual(log.map((e) => e.op), ['wait', 'wait', 'emotion']);
  tickBy(player, 1.0);
  assert.equal(player.getState(), 'playing', 'slow lane still running');
  assert.ok(Math.abs(player.getProgress() - (1.25 / 2)) < 0.15);
  tickBy(player, 1.0);
  assert.equal(player.getState(), 'done');
  assert.equal(log.at(-1).op, 'sfx', 'follow-up ran after the group');
});

test('player: tapWait advances on tap()', () => {
  const { player } = rig([{ op: 'tapWait', timeout: 8 }, { op: 'wait', duration: 1 }]);
  player.start();
  tickBy(player, 0.25);
  assert.equal(player.isAwaitingTap(), true);
  assert.equal(player.tap(), true, 'tap consumed by the tapWait');
  tickBy(player, 0.01);
  assert.equal(player.isAwaitingTap(), false);
  assert.equal(player.getState(), 'playing', 'moved on to the wait');
  assert.equal(player.tap(), false, 'no tapWait active anymore');
});

test('player: tapWait falls through on its timeout (never blocks forever)', () => {
  const { player } = rig([{ op: 'tapWait', timeout: 2 }]);
  player.start();
  tickBy(player, 1.9);
  assert.equal(player.getState(), 'playing');
  tickBy(player, 0.2);
  assert.equal(player.getState(), 'done');
  assert.equal(player.getFinishReason(), 'completed');
});

test('player: the 45 s watchdog force-finishes and applies keepOnSkip ops', () => {
  const waits = Array.from({ length: 6 }, () => ({ op: 'wait', duration: 10 }));
  const { player, log } = rig([
    ...waits, // 60 s of script — longer than the watchdog
    { op: 'emotion', emotion: 'happy', keepOnSkip: true },
  ]);
  player.start();
  tickBy(player, CUTSCENE.WATCHDOG_SEC - 0.1);
  assert.equal(player.getState(), 'playing');
  tickBy(player, 0.25);
  assert.equal(player.getState(), 'done');
  assert.equal(player.getFinishReason(), 'watchdog');
  const finalOp = log.at(-1);
  assert.deepEqual({ op: finalOp.op, skipped: finalOp.skipped }, { op: 'emotion', skipped: true });
});

test('player: tick clamps runaway dt (one huge frame cannot leap the watchdog)', () => {
  const { player } = rig([{ op: 'wait', duration: 10 }, { op: 'wait', duration: 10 }]);
  player.start();
  player.tick(9999); // clamped to 0.25 s internally
  assert.equal(player.getState(), 'playing');
  assert.ok(player.getProgress() < 0.1);
});

test('player: first view requires the HOLD gesture (tap-skip refused)', () => {
  const { player, log } = rig([
    { op: 'wait', duration: 10 },
    { op: 'sfx', sfx: 'jingle.short', keepOnSkip: true },
    { op: 'caption', key: 'cutscene.demo.bye' }, // NOT keepOnSkip
  ], { replay: false });
  player.start();
  tickBy(player, 0.25);
  assert.equal(player.skipTap(), false, 'first view: tap-skip refused');
  assert.equal(player.getState(), 'playing');

  // Hold halfway, release — progress decays back instead of latching.
  player.skipHoldStart();
  tickBy(player, CUTSCENE.HOLD_SKIP_SEC / 2);
  assert.ok(player.getHoldProgress() > 0.3 && player.getHoldProgress() < 0.9);
  player.skipHoldEnd();
  tickBy(player, CUTSCENE.HOLD_SKIP_SEC);
  assert.equal(player.getHoldProgress(), 0, 'released hold decays to zero');
  assert.equal(player.getState(), 'playing');

  // Full hold crosses the threshold and skips.
  player.skipHoldStart();
  tickBy(player, CUTSCENE.HOLD_SKIP_SEC + 0.05);
  assert.equal(player.getState(), 'done');
  assert.equal(player.getFinishReason(), 'skipped');
  const applied = log.map((e) => `${e.op}:${e.skipped ? 1 : 0}`);
  assert.ok(applied.includes('sfx:1'), 'keepOnSkip op applied on skip');
  assert.ok(!applied.some((s) => s.startsWith('caption')), 'non-keep op NOT applied');
});

test('player: replays skip instantly on a single tap', () => {
  const { player, log } = rig([
    { op: 'wait', duration: 10 },
    { op: 'emotion', emotion: 'happy', keepOnSkip: true },
  ], { replay: true });
  player.start();
  tickBy(player, 0.25);
  assert.equal(player.skipTap(), true);
  assert.equal(player.getState(), 'done');
  assert.equal(player.getFinishReason(), 'skipped');
  assert.deepEqual(log.at(-1), { op: 'emotion', id: 'happy', skipped: true });
});

test('player: cancel() hard-aborts WITHOUT keepOnSkip application', () => {
  const { player, log } = rig([
    { op: 'wait', duration: 10 },
    { op: 'sfx', sfx: 'jingle.short', keepOnSkip: true },
  ]);
  player.start();
  tickBy(player, 0.25);
  player.cancel();
  assert.equal(player.getState(), 'done');
  assert.equal(player.getFinishReason(), 'cancelled');
  assert.ok(!log.some((e) => e.op === 'sfx'), 'no keepOnSkip on hard abort');
});

test('player: a throwing driver hook never wedges playback', () => {
  const compiled = compileScript(script([
    { op: 'sfx', sfx: 'ui.tap' },
    { op: 'wait', duration: 0.5 },
  ]));
  const player = createCutscenePlayer(compiled, {
    apply() {
      throw new Error('driver exploded');
    },
  });
  player.start();
  tickBy(player, 1.0);
  assert.equal(player.getState(), 'done');
  assert.equal(player.getFinishReason(), 'completed');
});

test('player: onFinish fires exactly once with the reason', () => {
  const { player } = rig([{ op: 'wait', duration: 0.5 }]);
  const reasons = [];
  player.onFinish((r) => reasons.push(r));
  player.start();
  tickBy(player, 1.0);
  player.skip(); // already done — must not re-fire
  assert.deepEqual(reasons, ['completed']);
});

// ---------------------------------------------------------------------------
// seen-map save slice (additive, bounded — vacation.js pattern)
// ---------------------------------------------------------------------------

test('slice: defaults, junk normalization and the known-ids bound', () => {
  assert.deepEqual(defaultSlice(), { seen: {} });
  assert.deepEqual(sliceOf(null), { seen: {} });
  assert.deepEqual(sliceOf({}), { seen: {} });
  assert.deepEqual(sliceOf({ cutscenes: 'junk' }), { seen: {} });
  assert.deepEqual(sliceOf({ cutscenes: { seen: [1, 2] } }), { seen: {} });
  const junk = {
    cutscenes: {
      seen: {
        demo: 1, // truthy but not true → dropped
        ghostId: true, // unknown id → dropped (bounded map)
        __proto__x: true,
      },
    },
  };
  assert.deepEqual(sliceOf(junk), { seen: {} });
  const good = { cutscenes: { seen: { demo: true, ghostId: true } } };
  assert.deepEqual(sliceOf(good), { seen: { demo: true } });
});

test('slice: markSeenSlice/hasSeen round-trip and refuse unknown ids', () => {
  const first = markSeenSlice(undefined, 'demo');
  assert.deepEqual(first, { seen: { demo: true } });
  assert.equal(hasSeen({ cutscenes: first }, 'demo'), true);
  assert.equal(hasSeen({ cutscenes: first }, 'ghostId'), false);
  const unknown = markSeenSlice(first, 'ghostId');
  assert.deepEqual(unknown, first, 'unknown ids never enter the map');
  // JSON round-trip survives (offline/save pipeline shape).
  const rt = sliceOf(JSON.parse(JSON.stringify({ cutscenes: first })));
  assert.deepEqual(rt, first);
});

// ---------------------------------------------------------------------------
// data mirror — every id in data/cutscenes.js resolves in the real registries
// ---------------------------------------------------------------------------

test('data mirror: every script compiles (normal AND reduced motion)', () => {
  assert.ok(CUTSCENE_IDS.length > 0);
  assert.ok(CUTSCENE_IDS.includes('demo'), 'the harness demo must exist');
  for (const id of CUTSCENE_IDS) {
    const scriptDef = getCutscene(id);
    assert.equal(scriptDef.id, id, `${id}: id field mismatch`);
    for (const reducedMotion of [false, true]) {
      const compiled = compileScript(scriptDef, { reducedMotion });
      assert.ok(
        compiled.totalSec < CUTSCENE.WATCHDOG_SEC,
        `${id}: worst-case duration ${compiled.totalSec}s must beat the ${CUTSCENE.WATCHDOG_SEC}s watchdog`,
      );
    }
  }
  assert.equal(getCutscene('nope'), null);
});

test('data mirror: clips, emotions, sfx and particle ids are all real', () => {
  for (const id of CUTSCENE_IDS) {
    for (const stepDef of leafSteps(getCutscene(id).steps)) {
      if (stepDef.op === 'clip') {
        assert.ok(CLIP_IDS.includes(stepDef.clip), `${id}: unknown clip '${stepDef.clip}'`);
      }
      if (stepDef.op === 'emotion') {
        assert.ok(EMOTION_IDS.includes(stepDef.emotion), `${id}: unknown emotion '${stepDef.emotion}'`);
      }
      if (stepDef.op === 'sfx') {
        assert.ok(stepDef.sfx in SFX_MAP, `${id}: unmapped sfx '${stepDef.sfx}' (sfxMap.js)`);
      }
      if (stepDef.op === 'particles') {
        assert.ok(
          CUTSCENE_PARTICLE_TYPES.includes(stepDef.type),
          `${id}: particle type '${stepDef.type}' not in the cutscene whitelist`,
        );
      }
    }
  }
});

test('data mirror: cutscene particle whitelist mirrors gfx/particles.js TYPES', () => {
  // particles.js imports three (not headless-importable) — scan its TYPES
  // table source instead, the onboarding.test.js sfx-scan pattern.
  const src = readFileSync(path.join(ROOT, 'src/gfx/particles.js'), 'utf8');
  const typesBlock = src.slice(src.indexOf('const TYPES = {'));
  for (const type of CUTSCENE_PARTICLE_TYPES) {
    assert.match(
      typesBlock,
      new RegExp(`^  ${type}: \\{`, 'm'),
      `particle type '${type}' missing from gfx/particles.js TYPES`,
    );
  }
});

test('data mirror: every caption key + the chrome keys exist in EN AND DE', () => {
  const chromeKeys = ['cutscene.tapContinue', 'cutscene.skipHold', 'cutscene.skipTap'];
  const used = new Set(chromeKeys);
  for (const id of CUTSCENE_IDS) {
    for (const stepDef of leafSteps(getCutscene(id).steps)) {
      if (stepDef.op === 'caption') used.add(stepDef.key);
    }
  }
  for (const key of used) {
    assert.ok(typeof CUT_EN[key] === 'string' && CUT_EN[key].trim(), `EN missing '${key}'`);
    assert.ok(typeof CUT_DE[key] === 'string' && CUT_DE[key].trim(), `DE missing '${key}'`);
  }
  // full module parity + namespace hygiene (v5-vacation precedent)
  assert.deepEqual(Object.keys(CUT_EN).sort(), Object.keys(CUT_DE).sort());
  for (const key of Object.keys(CUT_EN)) {
    assert.match(key, /^cutscene\./, `foreign namespace key '${key}'`);
  }
});

test('data mirror: the ?cutscene harness row exists and follows conventions', () => {
  const row = allHarnessParams().find((r) => r.param === 'cutscene');
  assert.ok(row, 'harnessParams.js row for ?cutscene missing');
  assert.equal(row.example, '?cutscene=demo');
  assert.ok(row.en.trim() && row.de.trim());
  const group = HARNESS_PARAM_GROUPS.find((g) => g.rows.some((r) => r.param === 'cutscene'));
  assert.equal(group.id, 'v6');
});
