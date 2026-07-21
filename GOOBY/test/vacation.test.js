// V5/VACATION — vacation/airport suite: the data/vacations.js catalog +
// v5-vacation string parity, the pure systems/vacation.js machine
// (phaseAt/postcardsDue/tick idempotence), the economy money paths
// (bookVacation / pickupVacation / payTaxiReturn incl. the capped-fee
// no-soft-lock rule), the timeEngine decay FREEZE while away, and the
// offline.js catch-up (frozen stats + vacation events). Headless per §B —
// only pure modules are imported.
import test from 'node:test';
import assert from 'node:assert/strict';

import { VACATIONS, VACATION_IDS, getVacation } from '../src/data/vacations.js';
import { EN as VAC_EN, DE as VAC_DE } from '../src/data/strings/v5-vacation.js';
import {
  VACATION,
  VACATION_PHASE,
  defaultSlice,
  sliceOf,
  isAway,
  phaseAt,
  postcardsDue,
  bookSlice,
  pickupSlice,
  tick,
  remainingMs,
  formatCountdown,
} from '../src/systems/vacation.js';
import {
  bookVacation,
  pickupVacation,
  payTaxiReturn,
  healthReady,
} from '../src/systems/economy.js';
import { simulateOffline, offlineToastVars } from '../src/systems/offline.js';
import { STATS } from '../src/data/constants.js';
import { iconNames } from '../src/ui/icons.js';
import { defaultState } from '../src/core/save.js';
import { createStore } from '../src/core/store.js';
import { createTimeEngine } from '../src/core/timeEngine.js';
import * as clock from '../src/core/clock.js';

const DAY = VACATION.MS_PER_DAY;
const HOUR = 3600000;
const T0 = Date.UTC(2026, 6, 16, 12, 0, 0);
const pin = (ms) => clock.configure({ now: ms });
const makeStore = (s = defaultState()) => createStore(s, { autosave: false });
// clock.now() flows in real time from the pin — ms-scale drift is expected
const near = (a, b, msg, tol = 5000) =>
  assert.ok(Math.abs(a - b) < tol, `${msg}: ${a} ≉ ${b}`);

// ------------------------------------------------------------- catalog data

test('catalog: exactly the 4 destinations at the ruled prices/days', () => {
  assert.deepEqual(VACATION_IDS, ['beach', 'meadowTrip', 'bigCity', 'space']);
  assert.deepEqual(VACATIONS.map((d) => d.price), [180, 220, 280, 350]);
  for (const d of VACATIONS) {
    assert.ok(d.days === 3 || d.days === 4, `${d.id}: days 3 or 4`);
    assert.ok(d.souvenirCoins > 0 && d.souvenirCoins < d.price,
      `${d.id}: souvenir must stay below the price (no arbitrage loop)`);
    assert.ok(Object.isFrozen(d), `${d.id}: row frozen`);
    assert.ok(iconNames().includes(d.icon), `${d.id}: '${d.icon}' is an authored glyph`);
  }
  assert.ok(Object.isFrozen(VACATIONS));
  assert.equal(getVacation('beach'), VACATIONS[0]);
  assert.equal(getVacation('nope'), undefined);
});

test('strings: EN/DE parity + every destination has name/sub/postcard keys', () => {
  assert.deepEqual(Object.keys(VAC_DE).sort(), Object.keys(VAC_EN).sort(),
    'v5-vacation: EN/DE key sets differ');
  for (const id of VACATION_IDS) {
    for (const key of [`vacation.dest.${id}.name`, `vacation.dest.${id}.sub`, `vacation.postcard.${id}`]) {
      assert.ok(VAC_EN[key], `EN missing ${key}`);
      assert.ok(VAC_DE[key], `DE missing ${key}`);
    }
  }
});

test('frozen numbers: 24 h pickup window, taxi fee, full-stat reunion', () => {
  assert.ok(Object.isFrozen(VACATION));
  assert.equal(VACATION.PICKUP_WINDOW_MS, 24 * HOUR);
  assert.equal(VACATION.MS_PER_DAY, 24 * HOUR);
  assert.ok(VACATION.TAXI_FEE > 0);
  assert.equal(VACATION.PICKUP_STAT_FILL, STATS.MAX);
});

// ----------------------------------------------------------- slice + phases

test('sliceOf: defensive against missing/junk slices (no SAVE.VERSION bump)', () => {
  assert.deepEqual(sliceOf({}), defaultSlice());
  assert.deepEqual(sliceOf(undefined), defaultSlice());
  assert.deepEqual(sliceOf({ vacation: 'junk' }), defaultSlice());
  const healed = sliceOf({ vacation: { phase: 'bogus', returnAt: 'NaN', trips: -3 } });
  assert.equal(healed.phase, VACATION_PHASE.NONE);
  assert.equal(healed.returnAt, 0);
  assert.equal(healed.trips, 0);
  assert.equal(isAway({}), false);
});

test('phaseAt: away < returnAt ≤ returnReady < pickupBy ≤ overdue', () => {
  const v = bookSlice(null, 'beach', T0); // 3 days
  assert.equal(v.returnAt, T0 + 3 * DAY);
  assert.equal(v.pickupBy, T0 + 3 * DAY + VACATION.PICKUP_WINDOW_MS);
  assert.equal(phaseAt(v, T0), VACATION_PHASE.AWAY);
  assert.equal(phaseAt(v, T0 + 3 * DAY - 1), VACATION_PHASE.AWAY);
  assert.equal(phaseAt(v, T0 + 3 * DAY), VACATION_PHASE.RETURN_READY);
  assert.equal(phaseAt(v, v.pickupBy - 1), VACATION_PHASE.RETURN_READY);
  assert.equal(phaseAt(v, v.pickupBy), VACATION_PHASE.OVERDUE);
  assert.equal(phaseAt(defaultSlice(), T0), VACATION_PHASE.NONE);
});

test('postcardsDue: one per full day away, none on the travel-home day', () => {
  const v = bookSlice(null, 'beach', T0); // 3 days → max 2 postcards
  assert.equal(postcardsDue(v, T0), 0);
  assert.equal(postcardsDue(v, T0 + DAY - 1), 0);
  assert.equal(postcardsDue(v, T0 + DAY), 1);
  assert.equal(postcardsDue(v, T0 + 2 * DAY), 2);
  assert.equal(postcardsDue(v, T0 + 3 * DAY), 2, 'capped at days − 1');
  assert.equal(postcardsDue(v, T0 + 30 * DAY), 2, 'cap holds after the trip');
  const space = bookSlice(null, 'space', T0); // 4 days → max 3
  assert.equal(postcardsDue(space, T0 + 10 * DAY), 3);
});

test('bookSlice/pickupSlice: trips counter carries over and bumps', () => {
  const first = bookSlice(null, 'beach', T0);
  assert.equal(first.trips, 0);
  const done = pickupSlice(first);
  assert.equal(done.phase, VACATION_PHASE.NONE);
  assert.equal(done.trips, 1);
  const second = bookSlice(done, 'space', T0);
  assert.equal(second.trips, 1, 'booking keeps the lifetime counter');
});

// -------------------------------------------------------------- engine tick

test('tick: postcards then returnReady then overdue — in order, once each', () => {
  let state = { vacation: bookSlice(null, 'beach', T0) };
  // day 1: one postcard
  let r = tick(state, T0 + DAY + 1);
  assert.deepEqual(r.events, [{ type: 'postcard', destId: 'beach', n: 1 }]);
  state = { vacation: r.changes };
  // jump straight past pickupBy: postcard 2 + returnReady + overdue together
  r = tick(state, T0 + 3 * DAY + VACATION.PICKUP_WINDOW_MS + 1);
  assert.deepEqual(r.events.map((e) => e.type), ['postcard', 'returnReady', 'overdue']);
  assert.equal(r.changes.phase, VACATION_PHASE.OVERDUE);
  state = { vacation: r.changes };
  // idempotent: same clock again → no changes, no events
  r = tick(state, T0 + 3 * DAY + VACATION.PICKUP_WINDOW_MS + 1);
  assert.equal(r.changes, null);
  assert.deepEqual(r.events, []);
});

test('tick: inactive slice is silent; missing slice self-heals once', () => {
  const healed = tick({}, T0);
  assert.deepEqual(healed.changes, defaultSlice());
  assert.deepEqual(healed.events, []);
  const silent = tick({ vacation: defaultSlice() }, T0);
  assert.equal(silent.changes, null);
  assert.deepEqual(silent.events, []);
});

test('remainingMs/formatCountdown: next milestone per phase', () => {
  const v = bookSlice(null, 'beach', T0);
  assert.equal(remainingMs({ vacation: v }, T0), 3 * DAY);
  const ready = { ...v, phase: VACATION_PHASE.RETURN_READY };
  assert.equal(remainingMs({ vacation: ready }, v.returnAt), VACATION.PICKUP_WINDOW_MS);
  const over = { ...v, phase: VACATION_PHASE.OVERDUE };
  assert.equal(remainingMs({ vacation: over }, v.pickupBy), 0);
  assert.equal(formatCountdown(2 * DAY + 5 * HOUR), '2d 5h');
  assert.equal(formatCountdown(3 * HOUR + 12 * 60000), '3:12');
  assert.equal(formatCountdown(-5), '0:00');
});

// ------------------------------------------------------------- money paths

test('bookVacation: pays the price, sets the away slice', async () => {
  await healthReady;
  pin(T0);
  const store = makeStore();
  store.update((s) => { s.coins = 500; });
  const res = bookVacation(store, 'meadowTrip');
  assert.deepEqual(res, { ok: true, total: 220 });
  assert.equal(store.get('coins'), 280);
  const v = store.get('vacation');
  assert.equal(v.phase, VACATION_PHASE.AWAY);
  assert.equal(v.destId, 'meadowTrip');
  near(v.returnAt, T0 + 3 * DAY, 'returnAt = booking + 3 days');
  assert.equal(store.get('profile.coinsSpent'), 220);
});

test('bookVacation: refuses unknown/sleeping/already-away/broke — atomic', () => {
  pin(T0);
  const store = makeStore();
  store.update((s) => { s.coins = 500; });
  assert.deepEqual(bookVacation(store, 'atlantis'), { ok: false, reason: 'unknown' });
  store.update((s) => { s.sleep = { sleeping: true, startedAt: T0, wakeAt: T0 + HOUR }; });
  assert.deepEqual(bookVacation(store, 'beach'), { ok: false, reason: 'sleeping' });
  store.update((s) => { s.sleep = { sleeping: false, startedAt: 0, wakeAt: 0 }; });
  assert.ok(bookVacation(store, 'beach').ok);
  assert.deepEqual(bookVacation(store, 'space'), { ok: false, reason: 'away' });
  const broke = makeStore();
  broke.update((s) => { s.coins = 100; });
  assert.deepEqual(bookVacation(broke, 'beach'), { ok: false, reason: 'coins' });
  assert.equal(broke.get('coins'), 100, 'nothing charged on refusal');
});

test('pickupVacation: refuses while away, reunites in the window', () => {
  pin(T0);
  const store = makeStore();
  store.update((s) => { s.coins = 500; });
  assert.deepEqual(pickupVacation(store), { ok: false, reason: 'none' });
  bookVacation(store, 'beach');
  assert.deepEqual(pickupVacation(store), { ok: false, reason: 'away' });
  // land: advance the machine into the pickup window
  const landed = tick(store.get(), T0 + 3 * DAY + HOUR);
  store.update((s) => { s.vacation = landed.changes; });
  store.update((s) => { s.stats = { hunger: 12, energy: 30, hygiene: 8, fun: 5 }; });
  const coinsBefore = store.get('coins');
  const res = pickupVacation(store);
  assert.equal(res.ok, true);
  assert.equal(res.destId, 'beach');
  assert.equal(res.souvenir, 30, 'beach coin souvenir');
  assert.equal(store.get('coins'), coinsBefore + 30);
  for (const k of STATS.KEYS) {
    assert.equal(store.get(`stats.${k}`), STATS.MAX, `${k} filled on reunion`);
  }
  const v = store.get('vacation');
  assert.equal(v.phase, VACATION_PHASE.NONE);
  assert.equal(v.trips, 1);
});

test('payTaxiReturn: only when overdue; fee capped at the balance (no soft-lock)', () => {
  pin(T0);
  const store = makeStore();
  store.update((s) => { s.coins = 500; });
  bookVacation(store, 'beach');
  assert.deepEqual(payTaxiReturn(store), { ok: false, reason: 'none' }, 'not while away');
  const overdue = tick(store.get(), T0 + 3 * DAY + VACATION.PICKUP_WINDOW_MS + HOUR);
  store.update((s) => { s.vacation = overdue.changes; });
  assert.deepEqual(pickupVacation(store), { ok: false, reason: 'overdue' }, 'free pickup closed');
  // broke player: the driver takes what's there
  store.update((s) => { s.coins = 10; });
  const res = payTaxiReturn(store);
  assert.equal(res.ok, true);
  assert.equal(res.total, 10, 'fee capped at the balance');
  assert.equal(store.get('coins'), 30, '0 left after the taxi + 30 souvenir');
  assert.equal(store.get('vacation.phase'), VACATION_PHASE.NONE);
  assert.equal(store.get('vacation.trips'), 1);
});

test('payTaxiReturn: full fee when affordable', () => {
  pin(T0);
  const store = makeStore();
  store.update((s) => { s.coins = 500; });
  bookVacation(store, 'space'); // 350c, 4 days
  const overdue = tick(store.get(), T0 + 4 * DAY + VACATION.PICKUP_WINDOW_MS + HOUR);
  store.update((s) => { s.vacation = overdue.changes; });
  const before = store.get('coins');
  const res = payTaxiReturn(store);
  assert.equal(res.total, VACATION.TAXI_FEE);
  assert.equal(res.souvenir, 70);
  assert.equal(store.get('coins'), before - VACATION.TAXI_FEE + 70);
});

// ------------------------------------------------- timeEngine decay freeze

test('timeEngine: stats/health/weight FREEZE while away, real-time engines run', () => {
  pin(T0);
  const s0 = defaultState();
  s0.lastTickAt = T0;
  s0.stats = { hunger: 80, energy: 70, hygiene: 60, fun: 50 };
  s0.vacation = bookSlice(null, 'beach', T0);
  const store = makeStore(s0);
  const playtimeBefore = store.get('profile.playtimeMin') ?? 0;
  pin(T0 + 60 * 60000); // one hour later
  createTimeEngine(store).tick();
  const s = store.get();
  assert.deepEqual(s.stats, { hunger: 80, energy: 70, hygiene: 60, fun: 50 },
    'no decay while Gooby is away');
  near(s.lastTickAt, T0 + 60 * 60000, 'engine bookkeeping advanced');
  near(s.profile.playtimeMin, playtimeBefore + 60, 'playtime stays real-time', 1);
});

test('timeEngine: a tick crossing returnAt flips the phase to returnReady', () => {
  pin(T0);
  const s0 = defaultState();
  s0.lastTickAt = T0;
  s0.vacation = bookSlice(null, 'beach', T0);
  const store = makeStore(s0);
  pin(T0 + 3 * DAY + HOUR);
  createTimeEngine(store).tick();
  assert.equal(store.get('vacation.phase'), VACATION_PHASE.RETURN_READY);
  assert.equal(store.get('vacation.postcards'), 2, 'both postcards caught up');
});

// --------------------------------------------------------- offline catch-up

test('simulateOffline: away absence freezes stats and walks the phases', () => {
  const s0 = defaultState();
  s0.lastTickAt = T0;
  s0.stats = { hunger: 90, energy: 80, hygiene: 70, fun: 60 };
  s0.vacation = bookSlice(null, 'beach', T0);
  // closed for 3 days + 2 h — Gooby landed, still inside the pickup window
  const sim = simulateOffline(s0, T0 + 3 * DAY + 2 * HOUR);
  assert.deepEqual(sim.state.stats, s0.stats, 'stats frozen while away');
  assert.equal(sim.state.vacation.phase, VACATION_PHASE.RETURN_READY);
  assert.equal(sim.events.filter((e) => e === 'vacationPostcard').length, 2);
  assert.ok(sim.events.includes('vacationReturnReady'));
  assert.ok(!sim.events.includes('vacationOverdue'));
  const vars = offlineToastVars(s0.stats, sim);
  assert.ok(vars && vars.summary.length > 0, 'welcome-back summary mentions the landing');
});

test('simulateOffline: absence past the pickup window lands on overdue', () => {
  const s0 = defaultState();
  s0.lastTickAt = T0;
  s0.vacation = bookSlice(null, 'beach', T0);
  const sim = simulateOffline(s0, T0 + 3 * DAY + VACATION.PICKUP_WINDOW_MS + HOUR);
  assert.equal(sim.state.vacation.phase, VACATION_PHASE.OVERDUE);
  assert.ok(sim.events.includes('vacationReturnReady'));
  assert.ok(sim.events.includes('vacationOverdue'));
});

test('simulateOffline: no vacation → decay untouched (regression guard)', () => {
  const s0 = defaultState();
  s0.lastTickAt = T0;
  s0.stats = { hunger: 90, energy: 80, hygiene: 70, fun: 60 };
  const sim = simulateOffline(s0, T0 + 4 * HOUR);
  assert.ok(sim.state.stats.hunger < 90, 'awake decay still applies without a vacation');
  assert.equal(sim.state.vacation.phase, VACATION_PHASE.NONE, 'slice self-healed');
});
