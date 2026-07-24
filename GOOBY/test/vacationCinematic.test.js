// V6/D1 — vacation cinematic suite (PLAN6 Wave D/D1): the PURE decision
// logic behind the airport set pieces (script selection per explicit user
// action, the mutation-then-present atomicity contract, the never-replay-
// on-boot trigger rule, refused/failed-presentation fallthrough) plus the
// DATA-MIRROR validation of the three authored scripts in data/cutscenes.js
// — same technique as test/cutscene.test.js: every clip/emotion/sfx/particle
// id resolves in the real registries, every caption key ships EN+DE in the
// owned strings/v6-vacation-scenes.js module, and every prop model key maps
// to a committed GLB on disk. Headless per §B — pure modules only (the view
// presenter src/vacation/vacationCinematic.js imports the three.js graph, so
// its call-site guarantees are checked by SOURCE SCAN, the onboarding
// sfx-scan pattern).

import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

import {
  VAC_CINE_IDS,
  CINE_TRIGGERS,
  scriptForTrigger,
  runMomentFlow,
  harnessKickFor,
} from '../src/vacation/vacationCinematic.logic.js';
import { CUTSCENE_IDS, getCutscene } from '../src/data/cutscenes.js';
import {
  CUTSCENE,
  OP_KINDS,
  CUTSCENE_PARTICLE_TYPES,
  compileScript,
} from '../src/systems/cutscene.js';
import { EN as VAC_EN, DE as VAC_DE } from '../src/data/strings/v6-vacation-scenes.js';
import { CLIP_IDS } from '../src/character/goobyAnims.js';
import { EMOTION_IDS } from '../src/character/emotions.js';
import { SFX_MAP } from '../src/audio/sfxMap.js';
import { VACATION } from '../src/systems/vacation.js';
import { getModelUrl } from '../src/core/assets.js';
import { HARNESS_PARAM_GROUPS, allHarnessParams } from '../src/data/harnessParams.js';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');

/** The three authored ids, in one place. */
const IDS = [VAC_CINE_IDS.departure, VAC_CINE_IDS.reunionOnTime, VAC_CINE_IDS.reunionTaxi];

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
// script selection — explicit user actions map to the right script
// ---------------------------------------------------------------------------

test('selection: book/pickup/taxi map to departure/on-time/taxi scripts', () => {
  assert.equal(scriptForTrigger('book', { ok: true }), 'vacDeparture');
  assert.equal(scriptForTrigger('pickup', { ok: true }), 'vacReunionOnTime');
  assert.equal(scriptForTrigger('taxi', { ok: true }), 'vacReunionTaxi');
  // the trigger table itself is frozen and covers exactly the three actions
  assert.ok(Object.isFrozen(CINE_TRIGGERS));
  assert.deepEqual(Object.keys(CINE_TRIGGERS).sort(), ['book', 'pickup', 'taxi']);
});

test('selection: non-ok / junk results never present', () => {
  for (const trigger of Object.keys(CINE_TRIGGERS)) {
    assert.equal(scriptForTrigger(trigger, { ok: false }), null);
    assert.equal(scriptForTrigger(trigger, { ok: 'yes' }), null, 'truthy-but-not-true refused');
    assert.equal(scriptForTrigger(trigger, {}), null);
    assert.equal(scriptForTrigger(trigger, null), null);
    assert.equal(scriptForTrigger(trigger, undefined), null);
    assert.equal(scriptForTrigger(trigger, 'ok'), null);
  }
});

test('selection (never-replay-on-boot): phase/boot observations are NOT triggers', () => {
  // Anything a phase observer, boot catch-up or offline walker could invent
  // must fail CLOSED — the departure can never replay from state observation.
  const nonTriggers = [
    'boot', 'offline', 'phase', 'vacationChanged', 'vacationEvent',
    'returnReady', 'overdue', 'away', 'postcard', 'tick', '', null, undefined, 42,
  ];
  for (const trigger of nonTriggers) {
    assert.equal(scriptForTrigger(trigger, { ok: true }), null, `'${trigger}' must not present`);
  }
});

// ---------------------------------------------------------------------------
// atomicity — mutation completes BEFORE presentation; cinema is optional
// ---------------------------------------------------------------------------

test('atomicity: mutate runs to completion strictly before present', async () => {
  const calls = [];
  const { result, presented } = await runMomentFlow({
    mutate: () => {
      calls.push('mutate:start');
      calls.push('mutate:done'); // synchronous completion — atomic
      return { ok: true, souvenir: 30 };
    },
    present: (res) => {
      calls.push('present');
      assert.deepEqual(res, { ok: true, souvenir: 30 }, 'present sees the committed result');
      return true;
    },
  });
  assert.deepEqual(calls, ['mutate:start', 'mutate:done', 'present']);
  assert.deepEqual(result, { ok: true, souvenir: 30 });
  assert.equal(presented, true);
});

test('atomicity: a failed mutation never presents', async () => {
  let presentCalls = 0;
  for (const bad of [{ ok: false, reason: 'coins' }, {}, null, undefined]) {
    const { result, presented } = await runMomentFlow({
      mutate: () => bad,
      present: () => {
        presentCalls += 1;
        return true;
      },
    });
    assert.equal(presented, false);
    assert.deepEqual(result, bad ?? null, 'mutation result passes through verbatim');
  }
  assert.equal(presentCalls, 0, 'present never ran for a non-ok mutation');
});

test('fallthrough: present() returning false leaves the flow state identical', async () => {
  // Pure flow-state model: the mutation writes the state; a refused
  // presentation must change NOTHING about it (and mutate never re-runs).
  const state = { coins: 500, vacation: { phase: 'none', trips: 0 } };
  let mutateRuns = 0;
  const mutate = () => {
    mutateRuns += 1;
    state.coins -= 180;
    state.vacation = { phase: 'away', trips: 0 };
    return { ok: true, total: 180 };
  };
  const afterMutate = () => JSON.parse(JSON.stringify(state));

  const refused = await runMomentFlow({ mutate, present: () => false });
  const snapshot = afterMutate();
  assert.equal(refused.presented, false);
  assert.deepEqual(refused.result, { ok: true, total: 180 }, 'refusal never voids the transaction');
  assert.equal(mutateRuns, 1);
  assert.deepEqual(afterMutate(), snapshot, 'state untouched by the refusal');
});

test('fallthrough: a THROWING presentation is contained (flow continues silently)', async () => {
  const { result, presented } = await runMomentFlow({
    mutate: () => ({ ok: true, destId: 'beach' }),
    present: () => {
      throw new Error('camera lease refused');
    },
  });
  assert.equal(presented, false);
  assert.deepEqual(result, { ok: true, destId: 'beach' });
  // async rejection path too
  const rejected = await runMomentFlow({
    mutate: () => ({ ok: true }),
    present: () => Promise.reject(new Error('mid-pan')),
  });
  assert.equal(rejected.presented, false);
  assert.deepEqual(rejected.result, { ok: true });
});

// ---------------------------------------------------------------------------
// never-replay-on-boot — source-scan the presenter + its ONLY call sites
// ---------------------------------------------------------------------------

test('never-replay: the presenter modules subscribe to NO store events', () => {
  // The presenter must be driven exclusively by explicit call sites — a
  // store subscription ('vacationChanged'/'vacationEvent'/tick) inside it
  // would be phase observation, the exact replay-on-boot failure mode.
  for (const file of ['src/vacation/vacationCinematic.js', 'src/vacation/vacationCinematic.logic.js']) {
    const src = readFileSync(path.join(ROOT, file), 'utf8');
    assert.ok(!/\bstore\s*\.\s*on\s*\(/.test(src), `${file}: must not subscribe to store events`);
    assert.ok(!src.includes("on('vacation"), `${file}: must not observe vacation events`);
  }
});

test('never-replay: presentVacationCinematic is called with user-action triggers only', () => {
  // Every browser call site in src/ passes one of the three explicit
  // user-action triggers — combined with the pure trigger table above this
  // pins the rule end to end.
  const files = ['src/ui/airportScreen.js', 'src/vacation/vacationCinematic.js'];
  let callSites = 0;
  for (const file of files) {
    const src = readFileSync(path.join(ROOT, file), 'utf8');
    for (const m of src.matchAll(/presentVacationCinematic\s*\([^)]*\)/g)) {
      // skip the export declaration itself (function presentVacationCinematic(…))
      if (src.slice(Math.max(0, m.index - 12), m.index).includes('function')) continue;
      callSites += 1;
      assert.match(
        m[0],
        /'(book|pickup|taxi)'|kick\.trigger/,
        `${file}: unexpected trigger in ${m[0]}`,
      );
    }
  }
  assert.equal(callSites, 4, 'three airport call sites + the dev-harness kick');
  // and no OTHER module calls the presenter at all (hud/timeEngine/offline
  // walkers must never stage a departure)
  const airportSrc = readFileSync(path.join(ROOT, 'src/ui/hud.js'), 'utf8');
  assert.ok(!airportSrc.includes('presentVacationCinematic'), 'hud.js must not call the presenter');
  const timeSrc = readFileSync(path.join(ROOT, 'src/core/timeEngine.js'), 'utf8');
  assert.ok(!timeSrc.includes('presentVacationCinematic'), 'timeEngine.js must not call the presenter');
});

// ---------------------------------------------------------------------------
// data mirror — the three scripts against the real registries
// ---------------------------------------------------------------------------

test('data mirror: all three scripts exist and compile (normal AND reduced motion)', () => {
  for (const id of IDS) {
    assert.ok(CUTSCENE_IDS.includes(id), `${id} registered in data/cutscenes.js`);
    const scriptDef = getCutscene(id);
    assert.equal(scriptDef.id, id);
    for (const reducedMotion of [false, true]) {
      const compiled = compileScript(scriptDef, { reducedMotion });
      assert.ok(
        compiled.totalSec < CUTSCENE.WATCHDOG_SEC,
        `${id}: worst-case ${compiled.totalSec}s must beat the ${CUTSCENE.WATCHDOG_SEC}s watchdog`,
      );
      if (reducedMotion) {
        for (const step of leafSteps(compiled.steps)) {
          if (step.op === 'camera') assert.equal(step.duration, 0, `${id}: reduced camera collapses`);
          if (step.op === 'wait') {
            assert.ok(step.duration <= CUTSCENE.REDUCED_WAIT_MAX_SEC, `${id}: reduced waits shorten`);
          }
        }
      }
    }
  }
});

test('data mirror: clips, emotions, sfx, particles and ops are all real', () => {
  for (const id of IDS) {
    for (const stepDef of leafSteps(getCutscene(id).steps)) {
      assert.ok(OP_KINDS.includes(stepDef.op), `${id}: unknown op '${stepDef.op}'`);
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
          `${id}: particle type '${stepDef.type}' not whitelisted`,
        );
      }
    }
  }
});

test('data mirror: every prop model key resolves to a committed GLB on disk', () => {
  for (const id of IDS) {
    for (const stepDef of leafSteps(getCutscene(id).steps)) {
      if (stepDef.op !== 'prop' || stepDef.action !== 'spawn') continue;
      // V6/FIX2: 'cam:*' propIds are VIRTUAL camera-rig cuts — the view never
      // loads their model (authors write the sentinel 'virtual').
      if (stepDef.propId.startsWith('cam:')) {
        assert.equal(stepDef.model, 'virtual', `${id}: rig prop '${stepDef.propId}' must use the 'virtual' sentinel`);
        continue;
      }
      const url = getModelUrl(stepDef.model); // '/assets/<root>/<slug>/<file>.<ext>'
      const file = path.join(ROOT, 'public', url.replace(/^\//, ''));
      assert.ok(existsSync(file), `${id}: prop model '${stepDef.model}' missing on disk (${file})`);
    }
  }
});

// ---------------------------------------------------------------------------
// V6/FIX2 staging mirror — the restaged beats against the view capabilities
// ---------------------------------------------------------------------------

test('staging mirror (FIX2): every anchor resolves through a view capability', () => {
  // The view (ui/cutsceneView.js) resolves three anchor namespaces beyond
  // the rm registry: the 'cs:*' stage marks it computes itself, and
  // 'prop:<id>' live-prop tracking. Source-scan the view for the marks
  // (three.js graph — not headless-importable) and pin every script anchor
  // to a namespace the view implements.
  const viewSrc = readFileSync(path.join(ROOT, 'src/ui/cutsceneView.js'), 'utf8');
  const stageMarks = ['cs:doorway', 'cs:sky'];
  for (const mark of stageMarks) {
    assert.ok(viewSrc.includes(`'${mark}'`), `cutsceneView.js must implement stage mark '${mark}'`);
  }
  assert.ok(/anchor\.startsWith\('prop:'\)/.test(viewSrc), 'cutsceneView.js must implement prop: anchors');
  for (const id of IDS) {
    const spawned = new Set();
    for (const stepDef of leafSteps(getCutscene(id).steps)) {
      const anchor = stepDef.anchor;
      if (stepDef.op === 'prop' && stepDef.action === 'spawn') spawned.add(stepDef.propId);
      if (typeof anchor !== 'string') continue;
      if (anchor.startsWith('prop:')) {
        assert.ok(
          spawned.has(anchor.slice('prop:'.length)),
          `${id}: '${anchor}' must reference a prop spawned earlier in the script`,
        );
      } else {
        assert.ok(stageMarks.includes(anchor), `${id}: unknown staging anchor '${anchor}'`);
      }
    }
  }
});

test('staging mirror (FIX2): the beats SHOW what the captions narrate', () => {
  // P1-1 regression pins — the exact staging defects the eval found:
  // a taxi caption with the prop parked mid-room outside the portrait
  // frame, and an 'up, up and away' caption over an unchanged room.
  for (const id of IDS) {
    const steps = leafSteps(getCutscene(id).steps);
    // The taxi arrives AT the doorway mark (never a mid-room rug offset)…
    const taxi = steps.find((s) => s.op === 'prop' && s.action === 'spawn' && s.propId === 'vacTaxi');
    assert.equal(taxi.anchor, 'cs:doorway', `${id}: taxi must stage at the doorway mark`);
    // …under a door-focused camera frame with an audible arrival cue.
    const rig = steps.find((s) => s.op === 'prop' && s.action === 'spawn' && s.propId === 'cam:door');
    assert.ok(rig, `${id}: arrival beat needs the cam:door vignette`);
    assert.equal(rig.anchor, 'cs:doorway');
    assert.ok(
      steps.some((s) => s.op === 'sfx' && s.sfx === 'delivery.doorbell'),
      `${id}: arrival beat needs the doorbell cue`,
    );
    // Every rig cut is balanced by its return leg (the camera comes home).
    for (const prop of ['cam:door', 'cam:sky']) {
      const spawns = steps.filter((s) => s.op === 'prop' && s.propId === prop && s.action === 'spawn').length;
      const despawns = steps.filter((s) => s.op === 'prop' && s.propId === prop && s.action === 'despawn').length;
      assert.equal(spawns, despawns, `${id}: '${prop}' spawns must balance despawns`);
    }
  }
  // Departure only: the sky beat pairs its caption with a VISIBLE plane —
  // a tilt-up rig cut plus a spawn→glide pair that crosses the frame, with
  // the sparkle trail anchored to the gliding prop.
  const dep = leafSteps(getCutscene(VAC_CINE_IDS.departure).steps);
  const planeSpawns = dep.filter((s) => s.op === 'prop' && s.action === 'spawn' && s.propId === 'vacPlane');
  assert.equal(planeSpawns.length, 2, 'departure: plane needs a spawn + a glide re-spawn');
  assert.ok(planeSpawns.every((s) => s.anchor === 'cs:sky'), 'departure: plane rides the sky mark');
  assert.ok(
    planeSpawns[0].offset[0] < 0 && planeSpawns[1].offset[0] > 0,
    'departure: the glide must CROSS the frame (left → right)',
  );
  assert.ok(
    dep.some((s) => s.op === 'prop' && s.action === 'spawn' && s.propId === 'cam:sky'),
    'departure: the sky beat needs the tilt-up rig cut',
  );
  assert.ok(
    dep.some((s) => s.op === 'particles' && s.anchor === 'prop:vacPlane'),
    'departure: the sparkle trail must track the gliding plane',
  );
  // The suitcase beat lands center-low BY GOOBY (small gooby-relative
  // offset, no anchor) — the eval caught it half-clipped at the frame edge.
  const cases = dep.filter((s) => s.op === 'prop' && s.action === 'spawn' && s.propId === 'vacSuitcase');
  assert.equal(cases[0].anchor, undefined, 'departure: pack beat stages the case by Gooby');
  assert.ok(
    Math.abs(cases[0].offset[0]) <= 0.7 && cases[0].offset[2] > 0,
    'departure: the case lands center-low in the portrait frame',
  );
  assert.equal(cases[1]?.anchor, 'cs:doorway', 'departure: the case glides to the taxi');
});

// ---------------------------------------------------------------------------
// Sol P1-3 — the celebration presents ONCE, after the cinematic settles
// ---------------------------------------------------------------------------

test('celebration (FIX2): airport reunion tail runs once, AFTER the cinematic', () => {
  const src = readFileSync(path.join(ROOT, 'src/ui/airportScreen.js'), 'utf8');
  // The pickup/taxi handlers must chain the shared tail off the presenter's
  // settlement — never call it before (holdToasts swept the live toast and
  // releaseToasts respawned it: the same celebration twice).
  for (const trigger of ['pickup', 'taxi']) {
    assert.match(
      src,
      new RegExp(`presentVacationCinematic\\(\\{ store \\}, '${trigger}', res\\)\\s*\\r?\\n\\s*\\.then\\(\\(played\\) => celebrate\\(res, played\\)\\)`),
      `${trigger}: celebrate must chain off the settled presentation`,
    );
  }
  assert.ok(!/celebrate\(res\);/.test(src), 'no unconditional pre-cinematic celebrate() call remains');
  // A PLAYED cutscene owns the confetti/jingle beat (authored 18-confetti
  // ending) — only the toasts follow it; each fires exactly once. V6.1/B4
  // (FINAL-WAVE G1): the deterministic weather welcome-home line queues
  // sequentially after the welcomeBack toast, still BEFORE the played-branch
  // return (both reunion branches greet the weather).
  assert.match(
    src,
    /ui\.toast\('vacation\.welcomeBack',[^)]*\);[\s\S]{0,600}?ui\.toast\(`vacation\.home\.\$\{weatherAt\(now\(\)\)\.state\}`\);\s*\r?\n\s*if \(played\) return;/,
  );
  // The booked toast rides the same contract (it fed the identical
  // hold/release double before the departure cutscene).
  assert.match(src, /presentVacationCinematic\(\{ store \}, 'book', res\)\.then\(/);
});

test('data mirror: every caption key exists EN+DE in v6-vacation-scenes (owned module)', () => {
  const used = new Set();
  for (const id of IDS) {
    for (const stepDef of leafSteps(getCutscene(id).steps)) {
      if (stepDef.op === 'caption') used.add(stepDef.key);
    }
  }
  assert.ok(used.size >= 9, 'all three scripts carry caption beats');
  for (const key of used) {
    assert.ok(typeof VAC_EN[key] === 'string' && VAC_EN[key].trim(), `EN missing '${key}'`);
    assert.ok(typeof VAC_DE[key] === 'string' && VAC_DE[key].trim(), `DE missing '${key}'`);
  }
  // module parity + namespace hygiene + zero unused keys + no {vars} (the
  // caption op renders keys WITHOUT interpolation)
  assert.deepEqual(Object.keys(VAC_EN).sort(), Object.keys(VAC_DE).sort());
  for (const key of Object.keys(VAC_EN)) {
    assert.match(key, /^cutscene\.vac\./, `foreign namespace key '${key}'`);
    assert.ok(used.has(key), `orphaned strings key '${key}'`);
    assert.ok(!/\{\w+\}/.test(VAC_EN[key]) && !/\{\w+\}/.test(VAC_DE[key]),
      `'${key}' must not use {vars} (caption op cannot interpolate)`);
  }
});

// ---------------------------------------------------------------------------
// on-time vs taxi — presentation-only difference, frozen rewards
// ---------------------------------------------------------------------------

test('variants: on-time and taxi reunions differ in ACTING only (no reward surface)', () => {
  // The director's op vocabulary carries no economy/stat op at all — scripts
  // physically cannot change rewards. Pin that plus the frozen V5 numbers
  // the acceptance names (taxi fee, full-stat reunion fill).
  for (const op of OP_KINDS) {
    assert.ok(!/coin|award|spend|stat|economy/i.test(op), `economy-flavored op '${op}' in the vocabulary`);
  }
  assert.equal(VACATION.TAXI_FEE, 60, 'taxi fee frozen');
  assert.equal(VACATION.PICKUP_STAT_FILL, 100, 'full-stat reunion fill frozen');

  // Both reunions share the skeleton (taxi in → acting → hug beat →
  // souvenir caption → taxi out → restore) and both end on a warm
  // keepOnSkip happy emotion — the taxi variant is never punishing.
  const onTime = leafSteps(getCutscene('vacReunionOnTime').steps);
  const late = leafSteps(getCutscene('vacReunionTaxi').steps);
  for (const steps of [onTime, late]) {
    const final = steps.filter((s) => s.op === 'emotion').at(-1);
    assert.deepEqual(
      { emotion: final.emotion, keepOnSkip: final.keepOnSkip === true },
      { emotion: 'happy', keepOnSkip: true },
      'both variants land on a kept happy emotion',
    );
    assert.ok(steps.some((s) => s.op === 'particles' && s.type === 'hearts'), 'both keep a hearts beat');
    assert.ok(steps.some((s) => s.op === 'sfx' && s.sfx === 'coin.get'), 'both keep the souvenir beat');
    assert.ok(steps.some((s) => s.op === 'camera' && s.move === 'restore'), 'both restore the camera');
  }
  // …and the acting actually differs: droopy sleepy ears + tired stretch on
  // the late variant only, ecstatic jump on the punctual one only.
  assert.ok(late.some((s) => s.op === 'emotion' && s.emotion === 'sleepy'), 'late variant acts tired');
  assert.ok(late.some((s) => s.op === 'clip' && s.clip === 'stretch'), 'late variant stretches');
  assert.ok(!onTime.some((s) => s.op === 'emotion' && s.emotion === 'sleepy'), 'on-time never droops');
  assert.ok(onTime.some((s) => s.op === 'emotion' && s.emotion === 'ecstatic'), 'on-time beams');
  assert.ok(onTime.some((s) => s.op === 'clip' && s.clip === 'jump'), 'on-time hops out');
});

// ---------------------------------------------------------------------------
// dev harness — ?vacationcine= table + the harnessParams row
// ---------------------------------------------------------------------------

test('harness: kick table maps the three stage names and refuses junk', () => {
  assert.deepEqual(harnessKickFor('departure'), { trigger: 'book', seedAway: true });
  assert.deepEqual(harnessKickFor('reunionOnTime'), { trigger: 'pickup', seedAway: false });
  assert.deepEqual(harnessKickFor('reunionTaxi'), { trigger: 'taxi', seedAway: false });
  for (const junk of ['', 'demo', 'DEPARTURE', null, undefined, 7]) {
    assert.equal(harnessKickFor(junk), null);
  }
});

test('harness: the ?vacationcine row exists in the v6 group', () => {
  const row = allHarnessParams().find((r) => r.param === 'vacationcine');
  assert.ok(row, 'harnessParams.js row for ?vacationcine missing');
  assert.equal(row.example, '?vacationcine=departure');
  assert.ok(row.en.trim() && row.de.trim());
  const group = HARNESS_PARAM_GROUPS.find((g) => g.rows.some((r) => r.param === 'vacationcine'));
  assert.equal(group.id, 'v6');
});
