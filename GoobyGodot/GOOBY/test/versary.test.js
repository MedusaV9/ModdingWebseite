// V6.1/G3 (FINAL-WAVE B5) — Gooby-versary suite: the pure versaryDue()
// selector (30/365-day boundaries, junk/future createdAt, both-overdue
// ordering, seen-map suppression via the EXISTING cutscene slice — no new
// save keys), the G3 fallback dictionary contracts, and the quiet-home poll
// driver (initVersary) under node:test mock timers — gate refusals (wrong
// scene / switching / asleep / screen open / other cutscene), the director-
// refusal retry path, month-before-year hand-off and the both-seen
// stand-down. Headless per §B — ui/versary.js keeps its module root pure
// (whatsNew.js layering).

import test from 'node:test';
import assert from 'node:assert/strict';

import {
  VERSARY,
  versaryDue,
  VERSARY_EN,
  VERSARY_DE,
  initVersary,
} from '../src/ui/versary.js';
import { markSeenSlice } from '../src/systems/cutscene.js';
import { CUTSCENE_IDS } from '../src/data/cutscenes.js';

const T0 = Date.UTC(2026, 0, 10, 12, 0, 0);
const DAY = VERSARY.DAY_MS;

/** now() for a save (createdAt = T0) aged `ageDays` full days */
const nowAt = (ageDays) => T0 + ageDays * DAY;

/** a cutscenes slice with the given ids seen */
const seen = (...ids) => ids.reduce((slice, id) => markSeenSlice(slice, id), undefined);

// ---------------------------------------------------------------------------
// frozen numbers + data wiring
// ---------------------------------------------------------------------------

test('VERSARY frozen numbers: 30/365-day milestones on the fixed 24 h day', () => {
  assert.ok(Object.isFrozen(VERSARY));
  assert.equal(VERSARY.DAY_MS, 86400000, 'fixed real day (postcards.js convention)');
  assert.equal(VERSARY.MONTH_DAYS, 30);
  assert.equal(VERSARY.YEAR_DAYS, 365);
  assert.ok(VERSARY.POLL_MS > 400, 'poll slower than whatsNew (400 ms) — panels win the quiet slot');
});

test('both versary ids are REAL authored cutscenes (bounded seen map)', () => {
  assert.ok(CUTSCENE_IDS.includes('versaryMonth'));
  assert.ok(CUTSCENE_IDS.includes('versaryYear'));
});

test('G3 fallback dicts: EN/DE parity, non-empty, no raw emoji, heart slot', () => {
  assert.deepEqual(Object.keys(VERSARY_EN).sort(), Object.keys(VERSARY_DE).sort());
  for (const [key, value] of Object.entries(VERSARY_EN)) {
    for (const [lang, v] of [['EN', value], ['DE', VERSARY_DE[key]]]) {
      assert.ok(typeof v === 'string' && v.trim(), `${lang} '${key}' empty`);
      assert.ok(!/[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}]/u.test(v),
        `${lang} '${key}' must not carry raw emoji (game-rendered text)`);
    }
  }
  // the B1 love note keeps its {heart} placeholder (settingsScreen renders
  // the authored icons.js glyph there — no raw glyph in the table)
  assert.ok(VERSARY_EN['settings.loveNote'].includes('{heart}'));
  assert.ok(VERSARY_DE['settings.loveNote'].includes('{heart}'));
  // B6/B8 keys exist for the album chip + night apex line
  assert.equal(VERSARY_EN['gallery.frame.park'], 'Funkelpark');
  assert.equal(VERSARY_DE['gallery.frame.park'], 'Funkelpark');
  assert.ok(VERSARY_EN['park.wheel.apexNight'] && VERSARY_DE['park.wheel.apexNight']);
});

// ---------------------------------------------------------------------------
// versaryDue — boundaries, junk, ordering, suppression
// ---------------------------------------------------------------------------

test('versaryDue: 29/30 and 364/365 day boundaries are exact (≥ semantics)', () => {
  const s = { createdAt: T0 };
  assert.equal(versaryDue(s, nowAt(29)), null, '29 days: not yet');
  assert.equal(versaryDue(s, nowAt(30) - 1), null, 'one ms before day 30: not yet');
  assert.equal(versaryDue(s, nowAt(30)), 'versaryMonth', 'exactly 30 days: month due');
  const monthSeen = { createdAt: T0, cutscenes: seen('versaryMonth') };
  assert.equal(versaryDue(monthSeen, nowAt(364)), null, '364 days (month seen): nothing');
  assert.equal(versaryDue(monthSeen, nowAt(365) - 1), null, 'one ms before day 365: nothing');
  assert.equal(versaryDue(monthSeen, nowAt(365)), 'versaryYear', 'exactly 365 days: year due');
});

test('versaryDue: junk and future createdAt NEVER fire', () => {
  const nowMs = nowAt(1000);
  for (const junk of [undefined, null, NaN, 'junk', 0, -5, {}, []]) {
    assert.equal(versaryDue({ createdAt: junk }, nowMs), null, `createdAt=${String(junk)}`);
  }
  assert.equal(versaryDue(null, nowMs), null, 'null state');
  assert.equal(versaryDue({}, nowMs), null, 'missing createdAt');
  // future createdAt (hostile save / clock rollback): negative age — no fire
  assert.equal(versaryDue({ createdAt: nowMs + DAY }, nowMs), null, 'future createdAt');
  assert.equal(versaryDue({ createdAt: T0 }, NaN), null, 'junk now');
});

test('versaryDue: both overdue → month FIRST, year after month is seen', () => {
  const both = { createdAt: T0 };
  assert.equal(versaryDue(both, nowAt(400)), 'versaryMonth', 'month wins the first slot');
  const afterMonth = { createdAt: T0, cutscenes: seen('versaryMonth') };
  assert.equal(versaryDue(afterMonth, nowAt(400)), 'versaryYear', 'year on a later poll');
  const afterBoth = { createdAt: T0, cutscenes: seen('versaryMonth', 'versaryYear') };
  assert.equal(versaryDue(afterBoth, nowAt(400)), null, 'each id at most once ever');
});

test('versaryDue: seen suppression is permanent (once ever, no re-arm)', () => {
  const monthSeen = { createdAt: T0, cutscenes: seen('versaryMonth') };
  assert.equal(versaryDue(monthSeen, nowAt(31)), null);
  assert.equal(versaryDue(monthSeen, nowAt(200)), null);
  assert.equal(versaryDue(monthSeen, nowAt(364)), null, 'quiet gap until the year milestone');
  // junk seen shapes fall back to unseen (bounded sliceOf semantics)
  assert.equal(versaryDue({ createdAt: T0, cutscenes: 'junk' }, nowAt(31)), 'versaryMonth');
});

// ---------------------------------------------------------------------------
// initVersary — the quiet-home poll driver (mock timers)
// ---------------------------------------------------------------------------

/** microtask flush helper (playCutscene resolution → inFlight release) */
const flush = async () => {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
};

test('initVersary: quiet-home gate, busy refusal retry, month→year, stand-down', async (t) => {
  t.mock.timers.enable({ apis: ['setInterval'] });

  /** mutable world the injected deps read */
  const world = {
    scene: 'park',
    switching: false,
    screen: null,
    cutsceneActive: false,
    refuse: true, // director refusal (busy camera etc.)
    state: { createdAt: T0, sleep: { sleeping: false } },
  };
  /** @type {string[]} */
  const played = [];
  const deps = {
    store: { get: () => world.state },
    ui: { activeScreenId: () => world.screen },
    sceneManager: {
      currentId: () => world.scene,
      isSwitching: () => world.switching,
    },
    isCutsceneActive: () => world.cutsceneActive,
    playCutscene: (id) => {
      played.push(id);
      if (world.refuse) return Promise.resolve(false);
      // the real playCutscene latches seen BEFORE playback — mirror that
      world.state = {
        ...world.state,
        cutscenes: markSeenSlice(world.state.cutscenes, id),
      };
      return Promise.resolve(true);
    },
    nowFn: () => nowAt(400), // both milestones overdue
  };
  const stop = initVersary(deps);

  const tickOnce = async () => {
    t.mock.timers.tick(VERSARY.POLL_MS);
    await flush();
  };

  // gate refusals — each blocked poll must NOT reach playCutscene
  await tickOnce();
  assert.equal(played.length, 0, 'not on the home scene');
  world.scene = 'home';
  world.switching = true;
  await tickOnce();
  assert.equal(played.length, 0, 'scene switch in flight');
  world.switching = false;
  world.state = { ...world.state, sleep: { sleeping: true } };
  await tickOnce();
  assert.equal(played.length, 0, 'asleep');
  world.state = { ...world.state, sleep: { sleeping: false } };
  world.screen = 'album';
  await tickOnce();
  assert.equal(played.length, 0, 'a screen is open');
  world.screen = null;
  world.cutsceneActive = true;
  await tickOnce();
  assert.equal(played.length, 0, 'another cutscene is active');
  world.cutsceneActive = false;

  // director refusal (returns false): no seen latch — the SAME id retries
  await tickOnce();
  assert.deepEqual(played, ['versaryMonth'], 'quiet home: month first');
  await tickOnce();
  assert.deepEqual(played, ['versaryMonth', 'versaryMonth'], 'refused start retries later');

  // success path: month plays (seen latches), year takes the NEXT quiet slot
  world.refuse = false;
  await tickOnce();
  assert.deepEqual(played.slice(2), ['versaryMonth'], 'month again, now accepted');
  await tickOnce();
  assert.deepEqual(played.slice(2), ['versaryMonth', 'versaryYear'], 'year on the next poll');

  // both seen: the poll stands down — no further calls ever
  await tickOnce();
  await tickOnce();
  assert.equal(played.length, 4, 'stand-down after both moments are seen');
  stop();
});

test('initVersary: fresh save never fires; stop() halts the poll', async (t) => {
  t.mock.timers.enable({ apis: ['setInterval'] });
  const played = [];
  const stop = initVersary({
    store: { get: () => ({ createdAt: T0, sleep: { sleeping: false } }) },
    ui: { activeScreenId: () => null },
    sceneManager: { currentId: () => 'home', isSwitching: () => false },
    isCutsceneActive: () => false,
    playCutscene: (id) => {
      played.push(id);
      return Promise.resolve(true);
    },
    nowFn: () => nowAt(3), // three-day-old save
  });
  t.mock.timers.tick(VERSARY.POLL_MS * 5);
  await flush();
  assert.equal(played.length, 0, 'nothing due — nothing plays');
  stop();
  t.mock.timers.tick(VERSARY.POLL_MS * 5);
  await flush();
  assert.equal(played.length, 0);
});
