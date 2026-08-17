// V5/VACATION — vacation/airport suite: the data/vacations.js catalog +
// v5-vacation string parity, the pure systems/vacation.js machine
// (phaseAt/postcardsDue/tick idempotence), the economy money paths
// (bookVacation / pickupVacation / payTaxiReturn incl. the capped-fee
// no-soft-lock rule), the timeEngine decay FREEZE while away, and the
// offline.js catch-up (frozen stats + vacation events). Headless per §B —
// only pure modules are imported.
//
// V6/B2 (PLAN6 Wave B): the catalog contract moves 4 → 9 (the canonical
// nine-destination travel board): unique ids + unique recap biomes (beach
// stays the bonus NON-recap ninth — biome null; harbor is its own row),
// exact recap.lastRecapLevel gates 15/25/30/35/40 on the five new rows
// (old four stay ungated), the 180–350 price band with souvenirCoins ≪
// price on every row, the pure isVacationUnlocked lock decision, and
// EN/DE parity for the strings/v6-vacations.js module.
//
// V6/D2 (PLAN6 Wave D): the two ADDITIVE slice fields — `archive` (postcard
// keepsakes) + `lastPostcardDayProcessed` (per-trip bookkeeping) — round-trip
// through defaultSlice/sliceOf AND the carried transitions bookSlice/
// pickupSlice (the verified whitelist-strip trap), junk heals, tick()
// generates archive entries on both the live and money paths, and the
// archive survives a full store-driven reunion. The deep archive math
// (determinism, cap, DST edges, live/offline parity) lives in
// test/postcards.test.js.
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  VACATIONS,
  VACATION_IDS,
  getVacation,
  isVacationUnlocked,
} from '../src/data/vacations.js';
import { EN as VAC_EN, DE as VAC_DE } from '../src/data/strings/v5-vacation.js';
import { EN as VAC6_EN, DE as VAC6_DE } from '../src/data/strings/v6-vacations.js';
import { DEFAULT_BIOMES } from '../src/systems/recapDirector.js';
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

test('catalog: exactly the 9 destinations at the ruled prices/days (V6/B2)', () => {
  assert.deepEqual(VACATION_IDS, [
    'beach', 'meadowTrip', 'bigCity', 'space',
    'harbor', 'spookGarden', 'bakery', 'nightSky', 'toyRoom',
  ]);
  assert.deepEqual(
    VACATIONS.map((d) => d.price),
    [180, 220, 280, 350, 200, 240, 260, 300, 320],
  );
  for (const d of VACATIONS) {
    assert.ok(d.days === 3 || d.days === 4, `${d.id}: days 3 or 4`);
    assert.ok(d.price >= 180 && d.price <= 350,
      `${d.id}: price inside the coordinator's 180–350 band`);
    assert.ok(d.souvenirCoins > 0 && d.souvenirCoins < d.price,
      `${d.id}: souvenir must stay below the price (no arbitrage loop)`);
    assert.ok(d.souvenirCoins * 4 <= d.price,
      `${d.id}: souvenir ≪ price (≤ a quarter of the fare)`);
    assert.ok(Object.isFrozen(d), `${d.id}: row frozen`);
    assert.ok(iconNames().includes(d.icon), `${d.id}: '${d.icon}' is an authored glyph`);
    assert.match(d.color, /^#[0-9A-Fa-f]{6}$/, `${d.id}: color is a hex pastel`);
  }
  assert.ok(Object.isFrozen(VACATIONS));
  assert.equal(getVacation('beach'), VACATIONS[0]);
  assert.equal(getVacation('nope'), undefined);
});

test('catalog: the original four rows keep their V5 economy shape (regression pin)', () => {
  // V6.1/A2: the borrowed fish/sprout/car/moon icon pins retire ON PURPOSE —
  // every destination now carries its own authored glyph (pinned in the
  // dedicated nine-glyph test below). Prices/days/souvenirs stay frozen.
  const pins = [
    ['beach', 180, 3, 30],
    ['meadowTrip', 220, 3, 40],
    ['bigCity', 280, 4, 55],
    ['space', 350, 4, 70],
  ];
  for (const [id, price, days, souvenir] of pins) {
    const d = getVacation(id);
    assert.equal(d.price, price, `${id}: price unchanged`);
    assert.equal(d.days, days, `${id}: days unchanged`);
    assert.equal(d.souvenirCoins, souvenir, `${id}: souvenir unchanged`);
  }
});

test('V6.1/A2 catalog: all nine destinations map 1:1 onto their authored glyphs', () => {
  assert.deepEqual(
    Object.fromEntries(VACATIONS.map((d) => [d.id, d.icon])),
    {
      beach: 'sandcastle',
      meadowTrip: 'picnicBasket',
      bigCity: 'skyline',
      space: 'rocket',
      harbor: 'lighthouse',
      spookGarden: 'pumpkin',
      bakery: 'croissant',
      nightSky: 'shootingStar',
      toyRoom: 'toyBlock',
    },
  );
  // 1:1 means UNIQUE too — no two worlds share a glyph
  const icons = VACATIONS.map((d) => d.icon);
  assert.equal(new Set(icons).size, icons.length, 'glyph per destination is unique');
});

test('catalog: unique ids + unique biomes; the 8 recap biomes map 1:1, beach is the non-recap bonus', () => {
  const ids = VACATIONS.map((d) => d.id);
  assert.equal(new Set(ids).size, ids.length, 'ids unique');
  const biomes = VACATIONS.map((d) => d.biome).filter((b) => b != null);
  assert.equal(new Set(biomes).size, biomes.length, 'non-null biomes unique');
  // beach = the bonus NON-recap ninth destination (EVAL ruling: harbor is
  // its OWN destination, never collapsed into beach).
  assert.equal(getVacation('beach').biome, null, 'beach carries no recap biome');
  assert.equal(getVacation('harbor').biome, 'harbor', 'harbor is its own destination');
  // every recapDirector DEFAULT_BIOMES id is covered by exactly one row
  const biomeIds = DEFAULT_BIOMES.map((b) => b.id);
  assert.deepEqual([...biomes].sort(), [...biomeIds].sort(),
    'the 8 recap biomes map 1:1 onto the 8 recap destinations');
});

test('catalog: exact recap gates — old four ungated, new five at 15/25/30/35/40', () => {
  const gates = Object.fromEntries(VACATIONS.map((d) => [d.id, d.unlockRecapLevel]));
  assert.deepEqual(gates, {
    beach: 0,
    meadowTrip: 0,
    bigCity: 0,
    space: 0,
    harbor: 15,
    spookGarden: 25,
    bakery: 30,
    nightSky: 35,
    toyRoom: 40,
  });
  // gate order follows the recap milestone→vignette mapping (idea 09 §c:
  // milestone N discovers DEFAULT_BIOMES[N/5 − 1])
  for (const d of VACATIONS) {
    if (d.unlockRecapLevel === 0 || d.biome == null) continue;
    const vignetteIndex = DEFAULT_BIOMES.findIndex((b) => b.id === d.biome);
    assert.equal(d.unlockRecapLevel, (vignetteIndex + 1) * 5,
      `${d.id}: gate = its vignette's recap milestone`);
  }
});

test('isVacationUnlocked: pure lock decision — ungated always open, gated fails closed on junk', () => {
  const beach = getVacation('beach');
  const harbor = getVacation('harbor');
  const toyRoom = getVacation('toyRoom');
  // ungated rows are open at any (even junk) recap level
  assert.equal(isVacationUnlocked(beach, 0), true);
  assert.equal(isVacationUnlocked(beach, -5), true);
  assert.equal(isVacationUnlocked(beach, NaN), true);
  // gated rows: below < at ≤ above
  assert.equal(isVacationUnlocked(harbor, 0), false);
  assert.equal(isVacationUnlocked(harbor, 14), false);
  assert.equal(isVacationUnlocked(harbor, 15), true);
  assert.equal(isVacationUnlocked(harbor, 40), true);
  assert.equal(isVacationUnlocked(toyRoom, 35), false);
  assert.equal(isVacationUnlocked(toyRoom, 40), true);
  // junk recap levels fail CLOSED for gated rows (no early reveal)
  assert.equal(isVacationUnlocked(harbor, NaN), false);
  assert.equal(isVacationUnlocked(harbor, undefined), false);
  assert.equal(isVacationUnlocked(harbor, 'junk'), false);
  assert.equal(isVacationUnlocked(harbor, -1), false);
  // fractional levels floor (14.9 has not reached 15)
  assert.equal(isVacationUnlocked(harbor, 14.9), false);
  // missing row behaves as ungated (defensive default)
  assert.equal(isVacationUnlocked(undefined, 0), true);
});

test('strings: EN/DE parity + every destination has name/sub/postcard keys', () => {
  assert.deepEqual(Object.keys(VAC_DE).sort(), Object.keys(VAC_EN).sort(),
    'v5-vacation: EN/DE key sets differ');
  assert.deepEqual(Object.keys(VAC6_DE).sort(), Object.keys(VAC6_EN).sort(),
    'v6-vacations: EN/DE key sets differ');
  // the merged v5+v6 table covers all 9 destinations (v5 owns the original
  // four, v6-vacations owns the five new rows — no overlap)
  const EN_ALL = { ...VAC_EN, ...VAC6_EN };
  const DE_ALL = { ...VAC_DE, ...VAC6_DE };
  for (const id of VACATION_IDS) {
    for (const key of [`vacation.dest.${id}.name`, `vacation.dest.${id}.sub`, `vacation.postcard.${id}`]) {
      assert.ok(EN_ALL[key], `EN missing ${key}`);
      assert.ok(DE_ALL[key], `DE missing ${key}`);
    }
  }
  const v5Keys = new Set(Object.keys(VAC_EN));
  for (const key of Object.keys(VAC6_EN)) {
    assert.ok(!v5Keys.has(key), `v6-vacations must not shadow v5 key ${key}`);
  }
});

test('strings: locked mystery card discloses nothing (V6/B2)', () => {
  // the '???' presentation matches the V5 mystery-sticker language
  assert.equal(VAC6_EN['vacation.dest.locked.name'], '???');
  assert.equal(VAC6_DE['vacation.dest.locked.name'], '???');
  for (const dict of [VAC6_EN, VAC6_DE]) {
    assert.ok(dict['vacation.dest.locked.sub'], 'locked sub exists');
    assert.ok(dict['vacation.dest.locked.hint']?.includes('{level}'),
      'locked hint interpolates the unlock level');
  }
  // no locked-card string may leak a destination name
  const names = VACATION_IDS
    .map((id) => (VAC6_EN[`vacation.dest.${id}.name`] ?? VAC_EN[`vacation.dest.${id}.name`]))
    .filter(Boolean);
  for (const key of ['vacation.dest.locked.name', 'vacation.dest.locked.sub', 'vacation.dest.locked.hint']) {
    for (const dict of [VAC6_EN, VAC6_DE]) {
      for (const name of names) {
        assert.ok(!dict[key].includes(name), `${key} must not leak '${name}'`);
      }
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

// ------------------------------------------- V6/D2: archive slice wiring

test('V6/D2 sliceOf: archive + lastPostcardDayProcessed heal junk (round-trip)', () => {
  // defaults carry the new fields
  const d = defaultSlice();
  assert.deepEqual(d.archive, []);
  assert.equal(d.lastPostcardDayProcessed, 0);
  // junk shapes fall back
  const junky = sliceOf({ vacation: { archive: 'junk', lastPostcardDayProcessed: -4.7 } });
  assert.deepEqual(junky.archive, []);
  assert.equal(junky.lastPostcardDayProcessed, 0);
  // junk LEAVES inside a real archive drop; valid entries round-trip verbatim
  const good = { destId: 'beach', dayIndex: 1, variant: 2, atMs: T0 + DAY };
  const healed = sliceOf({
    vacation: {
      ...bookSlice(null, 'beach', T0),
      archive: [good, 'junk', { destId: 'atlantis', dayIndex: 1, variant: 1, atMs: T0 }, null],
      lastPostcardDayProcessed: 1.9,
    },
  });
  assert.deepEqual(healed.archive, [good], 'junk leaves stripped, keepsake kept');
  assert.equal(healed.lastPostcardDayProcessed, 1, 'bookkeeping floors');
  // a JSON round-trip (save/load) preserves both fields byte-for-byte
  const ticked = tick({ vacation: bookSlice(null, 'beach', T0) }, T0 + 2 * DAY).changes;
  const reloaded = sliceOf({ vacation: JSON.parse(JSON.stringify(ticked)) });
  assert.deepEqual(reloaded, ticked, 'sliceOf must not strip the V6/D2 fields (whitelist trap)');
});

test('V6/D2 tick: archive fills alongside the postcards counter (fixed-ms stamps)', () => {
  let state = { vacation: bookSlice(null, 'space', T0) }; // 4 days → 3 cards
  let r = tick(state, T0 + DAY + HOUR);
  assert.equal(r.changes.postcards, 1);
  assert.equal(r.changes.archive.length, 1);
  assert.deepEqual(r.changes.archive[0].atMs, T0 + DAY,
    'entry stamped at its fixed-ms day boundary, not the tick clock');
  assert.equal(r.changes.lastPostcardDayProcessed, 1);
  state = { vacation: r.changes };
  // jump past overdue: the remaining cards + phases land in one tick
  r = tick(state, T0 + 4 * DAY + VACATION.PICKUP_WINDOW_MS + HOUR);
  assert.equal(r.changes.archive.length, 3);
  assert.deepEqual(r.changes.archive.map((e) => e.dayIndex), [1, 2, 3]);
  assert.equal(r.changes.phase, VACATION_PHASE.OVERDUE);
  // idempotent: same clock again → no changes, no dupes
  assert.equal(tick({ vacation: r.changes }, T0 + 4 * DAY + VACATION.PICKUP_WINDOW_MS + HOUR).changes, null);
});

test('V6/D2 transitions: keepsakes survive book/pickup; bookkeeping resets', () => {
  const traveled = tick({ vacation: bookSlice(null, 'beach', T0) }, T0 + 3 * DAY).changes;
  assert.equal(traveled.archive.length, 2);
  const home = pickupSlice(traveled);
  assert.deepEqual(home.archive, traveled.archive, 'pickupSlice carries the archive');
  assert.equal(home.lastPostcardDayProcessed, 0, 'pickupSlice resets the day bookkeeping');
  const rebooked = bookSlice(home, 'space', T0 + 10 * DAY);
  assert.deepEqual(rebooked.archive, traveled.archive, 'bookSlice carries the archive');
  assert.equal(rebooked.lastPostcardDayProcessed, 0, 'bookSlice restarts the trip at day 0');
});

// ---------------------------------------- V6.1/C3: Reiseziele-Sammelpass

test('V6.1/C3 sliceOf: visited defaults empty; junk/unknown ids strip, cap is 9', () => {
  // defaults carry the new additive field (no SAVE.VERSION bump — the same
  // self-heal contract the D2 fields ride)
  assert.deepEqual(defaultSlice().visited, {});
  assert.deepEqual(sliceOf(defaultState()).visited, {});
  // junk containers fall back
  for (const junk of ['x', 42, null, [1, 2], true]) {
    assert.deepEqual(sliceOf({ vacation: { visited: junk } }).visited, {});
  }
  // unknown ids and non-strictly-true values DROP; the map is naturally
  // capped at the nine VACATION_IDS
  const healed = sliceOf({
    vacation: {
      visited: {
        beach: true,
        atlantis: true, // unknown id
        harbor: 1, // truthy junk — not strictly true
        space: 'true', // string junk
        toyRoom: true,
      },
    },
  });
  assert.deepEqual(healed.visited, { beach: true, toyRoom: true });
  const everything = Object.fromEntries(
    [...VACATION_IDS, 'mars', 'narnia'].map((id) => [id, true]),
  );
  const capped = sliceOf({ vacation: { visited: everything } });
  assert.equal(Object.keys(capped.visited).length, VACATION_IDS.length, 'capped at 9');
});

test('V6.1/C3: booking never latches; pickup latches the completed destination', () => {
  const away = bookSlice(null, 'beach', T0);
  assert.deepEqual(away.visited, {}, 'booking alone marks nothing');
  const home = pickupSlice(away);
  assert.deepEqual(home.visited, { beach: true }, 'the reunion is the ONE latch');
  // re-completing the same destination stays a single latched key
  assert.deepEqual(pickupSlice(bookSlice(home, 'beach', T0 + 10 * DAY)).visited,
    { beach: true });
});

test('V6.1/C3: visited carries book→pickup→book and JSON round-trips', () => {
  let v = pickupSlice(bookSlice(null, 'beach', T0));
  v = bookSlice(v, 'space', T0 + 10 * DAY);
  assert.deepEqual(v.visited, { beach: true }, 'bookSlice carries the pass');
  v = pickupSlice(v);
  assert.deepEqual(v.visited, { beach: true, space: true });
  const revived = sliceOf({ vacation: JSON.parse(JSON.stringify(v)) });
  assert.deepEqual(revived, v, 'sliceOf must not strip visited (whitelist trap)');
});

test('V6.1/C3: the overdue taxi latches too (money path through pickupSlice)', () => {
  pin(T0);
  const store = makeStore();
  store.update((s) => { s.coins = 500; });
  bookVacation(store, 'harbor');
  const overdue = tick(store.get(), T0 + 3 * DAY + VACATION.PICKUP_WINDOW_MS + HOUR);
  store.update((s) => { s.vacation = overdue.changes; });
  assert.equal(payTaxiReturn(store).ok, true);
  assert.deepEqual(store.get('vacation.visited'), { harbor: true });
});

test('V6.1/C3: all nine complete — and old saves grant nothing retroactively', () => {
  let v = null;
  for (const id of VACATION_IDS) {
    v = pickupSlice(bookSlice(v, id, T0));
  }
  assert.equal(Object.keys(v.visited).length, 9);
  assert.deepEqual(Object.keys(v.visited).sort(), [...VACATION_IDS].sort());
  // an old save with trips/archive but no visited map starts the pass at 0 —
  // NO retroactive archive-derived grants (plan ruling)
  const old = sliceOf({
    vacation: {
      trips: 12,
      archive: [{ destId: 'beach', dayIndex: 1, variant: 1, atMs: T0 }],
    },
  });
  assert.deepEqual(old.visited, {}, 'archive history never back-fills the pass');
});

test('V6/D2 money path: the archive survives a full store-driven reunion', () => {
  pin(T0);
  const store = makeStore();
  store.update((s) => { s.coins = 500; });
  bookVacation(store, 'beach');
  // land with both postcards written
  const landed = tick(store.get(), T0 + 3 * DAY + HOUR);
  store.update((s) => { s.vacation = landed.changes; });
  assert.equal(store.get('vacation.archive').length, 2, 'archive filled while away');
  const res = pickupVacation(store);
  assert.equal(res.ok, true);
  const v = store.get('vacation');
  assert.equal(v.phase, VACATION_PHASE.NONE);
  assert.equal(v.archive.length, 2, 'keepsakes survive economy.pickupVacation');
  assert.equal(v.lastPostcardDayProcessed, 0);
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

test('bookSlice: the five V6 destinations produce correct 3/4-day trips', () => {
  for (const id of ['harbor', 'spookGarden', 'bakery', 'nightSky', 'toyRoom']) {
    const dest = getVacation(id);
    const v = bookSlice(null, id, T0);
    assert.equal(v.destId, id);
    assert.equal(v.returnAt, T0 + dest.days * DAY, `${id}: returnAt = booking + days`);
    assert.equal(v.pickupBy, v.returnAt + VACATION.PICKUP_WINDOW_MS);
    assert.equal(postcardsDue(v, T0 + 10 * DAY), dest.days - 1,
      `${id}: one postcard per full day away`);
  }
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

test('bookVacation: a V6 destination books like the originals (harbor)', () => {
  pin(T0);
  const store = makeStore();
  store.update((s) => { s.coins = 500; });
  const res = bookVacation(store, 'harbor');
  assert.deepEqual(res, { ok: true, total: 200 });
  assert.equal(store.get('coins'), 300);
  const v = store.get('vacation');
  assert.equal(v.destId, 'harbor');
  near(v.returnAt, T0 + 3 * DAY, 'harbor is a 3-day trip');
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
