// V6/E1 — Funkelpark compact state (PLAN6 Wave E/E1): defaultSlice/sliceOf
// normalization + the pure record* transition helpers, incl. the risk-row-7
// junk drills (whitelisted ride ids, clamped counters, no SAVE.VERSION bump
// needed — the slice self-heals through defaultSlice()).
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  PARK_RIDE_IDS,
  THEME_PARK,
  defaultSlice,
  sliceOf,
  recordVisit,
  recordNight,
  recordRide,
  recordCandy,
  recordHandsUp,
} from '../src/systems/themePark.js';
import { defaultState } from '../src/core/save.js';
import { SAVE } from '../src/data/constants.js';

// ----------------------------------------------------------------- defaults

test('defaultSlice: zeroed counters, known ride ids only, night unlatched', () => {
  const d = defaultSlice();
  assert.deepEqual(d, {
    visits: 0,
    nightVisit: false,
    rides: { coaster: 0, wheel: 0 },
    handsUp: 0,
    candyBought: 0,
  });
  // V6.1/C1 pin: the catalog is EXACTLY ['coaster', 'wheel'] — the Riesenrad
  // fills the slot the V6 header comment reserved for it.
  assert.deepEqual([...PARK_RIDE_IDS], ['coaster', 'wheel']);
  assert.deepEqual(Object.keys(d.rides), [...PARK_RIDE_IDS]);
  // fresh object each call (no shared mutable default)
  assert.notEqual(defaultSlice().rides, d.rides);
});

test('no SAVE.VERSION bump: fresh saves have no themePark slice — sliceOf self-heals', () => {
  const state = defaultState();
  assert.equal(state.themePark, undefined); // additive slice, no migration
  assert.deepEqual(sliceOf(state), defaultSlice());
  assert.equal(typeof SAVE.VERSION, 'number'); // pin: the version exists…
  // …and this suite compiles against whatever it is — no bump required.
});

// ------------------------------------------------------------ sliceOf junk

test('sliceOf: junk containers fall back to the defaults', () => {
  for (const junk of [undefined, null, 42, 'park', [], { themePark: 'x' }]) {
    assert.deepEqual(sliceOf(junk), defaultSlice());
  }
  assert.deepEqual(sliceOf({ themePark: null }), defaultSlice());
  assert.deepEqual(sliceOf({ themePark: [1, 2] }), defaultSlice());
});

test('sliceOf: junk leaves normalize (NaN/negative/fractional/strings)', () => {
  const s = sliceOf({
    themePark: {
      visits: -3,
      nightVisit: 'yes', // truthy but not true → false (strict latch)
      rides: { coaster: 2.9, wheel: '4', ghostTrain: 7 }, // unknown id must DROP
      handsUp: NaN,
      candyBought: '12',
    },
  });
  assert.deepEqual(s, {
    visits: 0,
    nightVisit: false,
    rides: { coaster: 2, wheel: 4 },
    handsUp: 0,
    candyBought: 12,
  });
});

test('sliceOf: counters clamp at the MAX_COUNT ceiling', () => {
  const s = sliceOf({ themePark: { visits: 1e9, rides: { coaster: Infinity } } });
  assert.equal(s.visits, THEME_PARK.MAX_COUNT);
  assert.equal(s.rides.coaster, 0); // Infinity is junk → 0 (not clamped up)
});

test('sliceOf never mutates its input', () => {
  const raw = { themePark: { visits: 3, rides: { coaster: 1, junk: 5 } } };
  const frozen = JSON.stringify(raw);
  sliceOf(raw);
  assert.equal(JSON.stringify(raw), frozen);
});

// --------------------------------------------------------------- transitions

test('recordVisit: +1 visit; night option latches nightVisit', () => {
  let s = recordVisit(undefined);
  assert.equal(s.visits, 1);
  assert.equal(s.nightVisit, false);
  s = recordVisit(s, { night: true });
  assert.deepEqual([s.visits, s.nightVisit], [2, true]);
  // the latch never unlatches on a later day visit
  s = recordVisit(s, { night: false });
  assert.deepEqual([s.visits, s.nightVisit], [3, true]);
});

test('recordNight: latches without a new visit', () => {
  const s = recordNight({ visits: 4 });
  assert.deepEqual([s.visits, s.nightVisit], [4, true]);
});

test('recordRide: known id bumps; unknown id is a normalized no-op', () => {
  let s = recordRide(undefined, 'coaster');
  assert.equal(s.rides.coaster, 1);
  s = recordRide(s, 'coaster');
  assert.equal(s.rides.coaster, 2);
  const before = JSON.stringify(s);
  s = recordRide(s, 'ghostTrain'); // not in PARK_RIDE_IDS
  assert.equal(JSON.stringify(s), before);
  assert.ok(!('ghostTrain' in s.rides));
});

test('V6.1/C1 recordRide: wheel bumps independently of the coaster', () => {
  let s = recordRide(undefined, 'wheel');
  assert.deepEqual(s.rides, { coaster: 0, wheel: 1 });
  s = recordRide(s, 'wheel');
  s = recordRide(s, 'coaster');
  assert.deepEqual(s.rides, { coaster: 1, wheel: 2 });
});

test('recordCandy / recordHandsUp: defensive counts', () => {
  let s = recordCandy(undefined); // default 1
  assert.equal(s.candyBought, 1);
  s = recordCandy(s, 3);
  assert.equal(s.candyBought, 4);
  s = recordCandy(s, -5); // junk → no-op
  assert.equal(s.candyBought, 4);
  s = recordCandy(s, 2.9); // floors
  assert.equal(s.candyBought, 6);
  s = recordHandsUp(s);
  s = recordHandsUp(s, 2);
  s = recordHandsUp(s, NaN);
  assert.equal(s.handsUp, 3);
});

test('transitions always return a fully-normalized slice from junk input', () => {
  const s = recordVisit({ visits: 'x', rides: { junk: 9 }, extraField: true });
  assert.deepEqual(s, {
    visits: 1,
    nightVisit: false,
    rides: { coaster: 0, wheel: 0 },
    handsUp: 0,
    candyBought: 0,
  });
  assert.ok(!('extraField' in s)); // whitelist strip (risk row 7)
});

// ------------------------------------------------ save round-trip (offline)

test('slice survives a JSON save round-trip verbatim (additive top-level key)', () => {
  const state = defaultState();
  state.themePark = recordCandy(
    recordRide(recordRide(recordVisit(undefined, { night: true }), 'coaster'), 'wheel'),
    2,
  );
  const revived = JSON.parse(JSON.stringify(state));
  assert.deepEqual(sliceOf(revived), {
    visits: 1,
    nightVisit: true,
    rides: { coaster: 1, wheel: 1 },
    handsUp: 0,
    candyBought: 2,
  });
});
