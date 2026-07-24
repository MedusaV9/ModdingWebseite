// V6/D2 — postcard-archive suite (PLAN6 Wave D §D2): the pure
// systems/postcards.js engine — deterministic mulberry32 variant picks
// (live vs offline replays yield IDENTICAL cards), fixed-ms day-boundary
// math (DST-safe by construction: day k = bookedAt + k·86400000, never
// calendar days), the 36-entry FIFO archive cap, junk normalization, the
// shared processPostcardsUpTo() processor both catch-up paths reach through
// vacation.tick(), and EN/DE pool parity for strings/v6-vacation-content.js
// (3 variants × 9 destinations). Headless per §B — pure modules only.
import test from 'node:test';
import assert from 'node:assert/strict';

import {
  POSTCARDS,
  tripSeed,
  variantOf,
  postcardTextKey,
  normalizeEntry,
  normalizeArchive,
  processPostcardsUpTo,
  archiveOf,
} from '../src/systems/postcards.js';
import {
  VACATION,
  bookSlice,
  pickupSlice,
  sliceOf,
  tick,
} from '../src/systems/vacation.js';
import { VACATION_IDS } from '../src/data/vacations.js';
import { EN as CONTENT_EN, DE as CONTENT_DE } from '../src/data/strings/v6-vacation-content.js';
import { EN as ALL_EN, DE as ALL_DE } from '../src/data/strings.js';

const DAY = POSTCARDS.MS_PER_DAY;
const HOUR = 3600000;
const T0 = Date.UTC(2026, 6, 16, 12, 0, 0);

/** A well-formed entry factory for normalization tests. */
const entry = (over = {}) => ({
  destId: 'beach', dayIndex: 1, variant: 1, atMs: T0 + DAY, ...over,
});

// ------------------------------------------------------------ frozen numbers

test('POSTCARDS frozen: cap 36 (PLAN6 §5), day pinned to VACATION.MS_PER_DAY', () => {
  assert.ok(Object.isFrozen(POSTCARDS));
  assert.equal(POSTCARDS.MAX_ARCHIVE, 36, 'PLAN6 hard guardrail: archive cap 36');
  assert.equal(POSTCARDS.MS_PER_DAY, VACATION.MS_PER_DAY,
    'postcards.js duplicates the day length to stay import-cycle-free — MUST stay pinned');
  assert.ok(POSTCARDS.VARIANTS >= 3, '3+ text variants per destination');
});

// -------------------------------------------------------------- determinism

test('tripSeed/variantOf: fully deterministic — same inputs, same outputs, forever', () => {
  for (const id of VACATION_IDS) {
    assert.equal(tripSeed(id, T0), tripSeed(id, T0), `${id}: seed stable`);
    for (let k = 1; k <= 4; k += 1) {
      const a = variantOf(id, T0, k);
      const b = variantOf(id, T0, k);
      assert.equal(a, b, `${id} day ${k}: pick stable`);
      assert.ok(a >= 1 && a <= POSTCARDS.VARIANTS, `${id} day ${k}: in pool`);
      assert.equal(a, Math.floor(a), `${id} day ${k}: integer`);
    }
  }
});

test('variantOf: different trips/days actually vary (anti-constant guard)', () => {
  const picks = new Set();
  for (const id of VACATION_IDS) {
    for (let k = 1; k <= 4; k += 1) picks.add(variantOf(id, T0, k));
    picks.add(variantOf(id, T0 + 12345678, 1));
  }
  assert.ok(picks.size >= 2, 'the PRNG must not collapse to one variant');
});

test('variantOf: junk dayIndex clamps to day 1 deterministically', () => {
  const one = variantOf('beach', T0, 1);
  for (const junk of [0, -3, NaN, 'x', null, undefined]) {
    assert.equal(variantOf('beach', T0, junk), one, `dayIndex=${junk}`);
  }
});

// ------------------------------------------------------------ text-key pool

test('postcardTextKey: pooled key shape + junk-variant clamp into 1..VARIANTS', () => {
  assert.equal(postcardTextKey(entry()), 'vacation.postcard.beach.1');
  assert.equal(postcardTextKey(entry({ variant: POSTCARDS.VARIANTS })),
    `vacation.postcard.beach.${POSTCARDS.VARIANTS}`);
  // junk/out-of-pool variants clamp (render-time defense, entry preserved)
  assert.equal(postcardTextKey(entry({ variant: 99 })),
    `vacation.postcard.beach.${POSTCARDS.VARIANTS}`);
  assert.equal(postcardTextKey(entry({ variant: 0 })), 'vacation.postcard.beach.1');
  assert.equal(postcardTextKey(entry({ variant: 'junk' })), 'vacation.postcard.beach.1');
});

test('strings: EN/DE parity + full 3-variant pool for all 9 destinations', () => {
  assert.deepEqual(Object.keys(CONTENT_DE).sort(), Object.keys(CONTENT_EN).sort(),
    'v6-vacation-content: EN/DE key sets differ');
  for (const id of VACATION_IDS) {
    for (let k = 1; k <= POSTCARDS.VARIANTS; k += 1) {
      const key = `vacation.postcard.${id}.${k}`;
      assert.ok(CONTENT_EN[key], `EN missing ${key}`);
      assert.ok(CONTENT_DE[key], `DE missing ${key}`);
      // pooled lines are rendered by the game (rack) — NO raw emoji (D4 gate)
      assert.ok(!/[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}]/u.test(CONTENT_EN[key]),
        `${key} EN must not carry raw emoji (rendered in the rack)`);
      assert.ok(!/[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}]/u.test(CONTENT_DE[key]),
        `${key} DE must not carry raw emoji (rendered in the rack)`);
    }
  }
  // rack labels + the two notification copy pairs (ids 9/10)
  for (const key of [
    'vacation.rack.title', 'vacation.rack.day', 'vacation.rack.empty',
    'notify.vacReturn.title', 'notify.vacReturn.body',
    'notify.vacLastCall.title', 'notify.vacLastCall.body',
  ]) {
    assert.ok(CONTENT_EN[key], `EN missing ${key}`);
    assert.ok(CONTENT_DE[key], `DE missing ${key}`);
  }
  // the module is spread into the merged table (strings.js import committed)
  assert.equal(ALL_EN['vacation.postcard.beach.1'], CONTENT_EN['vacation.postcard.beach.1']);
  assert.equal(ALL_DE['notify.vacReturn.title'], CONTENT_DE['notify.vacReturn.title']);
});

// ------------------------------------------------------------- normalization

test('normalizeEntry: junk → null; valid entries floor their numbers', () => {
  assert.equal(normalizeEntry(null), null);
  assert.equal(normalizeEntry('junk'), null);
  assert.equal(normalizeEntry(42), null);
  assert.equal(normalizeEntry({}), null);
  assert.equal(normalizeEntry(entry({ destId: 'atlantis' })), null, 'unknown catalog id');
  assert.equal(normalizeEntry(entry({ destId: 7 })), null);
  assert.equal(normalizeEntry(entry({ dayIndex: 0 })), null);
  assert.equal(normalizeEntry(entry({ dayIndex: -2 })), null);
  assert.equal(normalizeEntry(entry({ dayIndex: NaN })), null);
  assert.equal(normalizeEntry(entry({ variant: 0 })), null);
  assert.equal(normalizeEntry(entry({ variant: 'x' })), null);
  assert.equal(normalizeEntry(entry({ atMs: -1 })), null);
  assert.equal(normalizeEntry(entry({ atMs: Infinity })), null);
  assert.deepEqual(
    normalizeEntry({ destId: 'space', dayIndex: 2.9, variant: 1.7, atMs: T0 + 0.5 }),
    { destId: 'space', dayIndex: 2, variant: 1, atMs: T0 + 0.5 },
    'fractional indices floor; atMs stays exact'
  );
});

test('normalizeArchive: junk drops, dupes collapse, chronological sort, pure', () => {
  assert.deepEqual(normalizeArchive(undefined), []);
  assert.deepEqual(normalizeArchive('junk'), []);
  assert.deepEqual(normalizeArchive({}), []);
  const dupe = entry();
  const raw = [
    'junk',
    entry({ destId: 'space', atMs: T0 + 3 * DAY, dayIndex: 3 }),
    null,
    dupe,
    { ...dupe }, // duplicate (same destId+atMs+dayIndex) → collapses
    entry({ destId: 'atlantis' }),
    entry({ destId: 'harbor', atMs: T0 + 2 * DAY, dayIndex: 2 }),
  ];
  const snapshot = JSON.stringify(raw);
  const clean = normalizeArchive(raw);
  assert.deepEqual(clean.map((e) => [e.destId, e.atMs]), [
    ['beach', T0 + DAY],
    ['harbor', T0 + 2 * DAY],
    ['space', T0 + 3 * DAY],
  ], 'sorted by atMs, junk + dupes gone');
  assert.equal(JSON.stringify(raw), snapshot, 'input untouched');
});

test('normalizeArchive: FIFO cap keeps the NEWEST 36', () => {
  const raw = [];
  for (let k = 1; k <= 40; k += 1) {
    raw.push(entry({ dayIndex: 1, atMs: T0 + k * DAY }));
  }
  const clean = normalizeArchive(raw);
  assert.equal(clean.length, POSTCARDS.MAX_ARCHIVE);
  assert.equal(clean[0].atMs, T0 + 5 * DAY, 'oldest 4 dropped');
  assert.equal(clean[clean.length - 1].atMs, T0 + 40 * DAY, 'newest kept');
});

// -------------------------------------------------- the shared processor

test('processPostcardsUpTo: exact fixed-ms day boundaries (DST-safe math)', () => {
  const v = bookSlice(null, 'beach', T0); // 3 days → max 2 cards
  // one ms before the day-1 boundary: nothing
  let r = processPostcardsUpTo(v, T0 + DAY - 1);
  assert.equal(r.added, 0);
  assert.deepEqual(r.archive, []);
  // exactly at the boundary: day 1 arrives, stamped bookedAt + 1·day
  r = processPostcardsUpTo(v, T0 + DAY);
  assert.equal(r.added, 1);
  assert.deepEqual(r.archive[0], {
    destId: 'beach',
    dayIndex: 1,
    variant: variantOf('beach', T0, 1),
    atMs: T0 + DAY,
  });
  assert.equal(r.lastPostcardDayProcessed, 1);
  // far past the trip: capped at days − 1 (travel-home day writes nothing),
  // entries stamped at their fixed boundaries, NOT the observation clock
  r = processPostcardsUpTo(v, T0 + 30 * DAY);
  assert.equal(r.archive.length, 2);
  assert.deepEqual(r.archive.map((e) => e.atMs), [T0 + DAY, T0 + 2 * DAY]);
});

test('processPostcardsUpTo: day math is pure ms — wall-clock/calendar independent', () => {
  // A trip booked at an "awkward" local time (23:30-ish in any zone) still
  // counts days as exact 86400000-ms steps: a DST hour lost or gained can
  // never add, drop or shift a card because no calendar API is consulted.
  const lateNight = Date.UTC(2026, 2, 28, 22, 30, 0); // spans EU DST 2026-03-29
  const v = bookSlice(null, 'space', lateNight); // 4 days → 3 cards
  const r = processPostcardsUpTo(v, lateNight + 10 * DAY);
  assert.equal(r.archive.length, 3);
  assert.deepEqual(
    r.archive.map((e) => e.atMs - lateNight),
    [DAY, 2 * DAY, 3 * DAY],
    'boundaries exactly k·86400000 ms after booking'
  );
  // 23h/25h "days" around the boundary change nothing at the k·day edges
  assert.equal(processPostcardsUpTo(v, lateNight + DAY - 1).added, 0);
  assert.equal(processPostcardsUpTo(v, lateNight + DAY).added, 1);
});

test('processPostcardsUpTo: idempotent + monotonic (no dupes, backwards-clock-safe)', () => {
  const v = bookSlice(null, 'space', T0);
  const day2 = processPostcardsUpTo(v, T0 + 2 * DAY + HOUR);
  assert.equal(day2.added, 2);
  const carried = { ...v, archive: day2.archive, lastPostcardDayProcessed: day2.lastPostcardDayProcessed };
  // same clock again: nothing new
  const again = processPostcardsUpTo(carried, T0 + 2 * DAY + HOUR);
  assert.equal(again.added, 0);
  assert.deepEqual(again.archive, day2.archive);
  // BACKWARDS device-clock jump: generates nothing, never re-writes
  const back = processPostcardsUpTo(carried, T0 + DAY);
  assert.equal(back.added, 0);
  assert.equal(back.lastPostcardDayProcessed, 2, 'bookkeeping stays monotonic');
  assert.deepEqual(back.archive, day2.archive);
});

test('processPostcardsUpTo: junk/inactive slices are a safe no-op', () => {
  for (const junk of [
    null,
    undefined,
    {},
    { destId: 'atlantis', bookedAt: T0, returnAt: T0 + 3 * DAY },
    { destId: 'beach', bookedAt: 0, returnAt: T0 },
    { destId: 'beach', bookedAt: T0, returnAt: T0 }, // no positive trip span
    pickupSlice(bookSlice(null, 'beach', T0)), // reset timestamps after reunion
  ]) {
    const r = processPostcardsUpTo(junk, T0 + 10 * DAY);
    assert.equal(r.added, 0, `no-op for ${JSON.stringify(junk)}`);
  }
});

test('processPostcardsUpTo: FIFO cap across a lifetime of trips (36 holds)', () => {
  // simulate many completed trips: 13 space trips × 3 cards = 39 entries
  let archive = [];
  for (let trip = 0; trip < 13; trip += 1) {
    const bookedAt = T0 + trip * 20 * DAY;
    const v = { ...bookSlice(null, 'space', bookedAt), archive };
    const r = processPostcardsUpTo(v, bookedAt + 10 * DAY);
    archive = r.archive;
    assert.ok(archive.length <= POSTCARDS.MAX_ARCHIVE, `cap holds after trip ${trip + 1}`);
  }
  assert.equal(archive.length, POSTCARDS.MAX_ARCHIVE);
  // the newest card is the last trip's day 3; the oldest surviving one is
  // 39 − 36 = 3 cards in (trip 1's day 1..3 dropped, trip 2 day 1 first kept)
  assert.equal(archive[archive.length - 1].atMs, T0 + 12 * 20 * DAY + 3 * DAY);
  assert.equal(archive[0].atMs, T0 + 1 * 20 * DAY + 1 * DAY);
});

// ------------------------------------------- live vs offline replay parity

test('live hourly ticking and one offline jump yield IDENTICAL archives', () => {
  // live: a 1 s engine would call tick() constantly — hourly stepping is a
  // superset of every boundary crossing and proves the incremental path.
  let live = { vacation: bookSlice(null, 'space', T0) };
  const end = T0 + 4 * DAY + VACATION.PICKUP_WINDOW_MS + HOUR; // past overdue
  for (let ts = T0; ts <= end; ts += HOUR) {
    const r = tick(live, ts);
    if (r.changes) live = { vacation: r.changes };
  }
  // offline: ONE catch-up tick at the boot clock (systems/offline.js path)
  const jump = tick({ vacation: bookSlice(null, 'space', T0) }, end);
  assert.deepEqual(live.vacation.archive, jump.changes.archive,
    'live and offline replays must agree byte-for-byte');
  assert.equal(live.vacation.archive.length, 3, 'space: 4 days → 3 cards');
  assert.deepEqual(
    live.vacation.archive.map((e) => e.variant),
    jump.changes.archive.map((e) => e.variant),
    'deterministic variants — same trip seed, same picks'
  );
  // and a re-boot replay of the SAME save changes nothing (no dupes)
  const again = tick({ vacation: jump.changes }, end + HOUR);
  assert.equal(again.changes, null);
});

// ---------------------------------------------------------------- archiveOf

test('archiveOf: normalized read API for UI/sticker consumers', () => {
  assert.deepEqual(archiveOf(undefined), []);
  assert.deepEqual(archiveOf({}), []);
  assert.deepEqual(archiveOf({ vacation: 'junk' }), []);
  const v = tick({ vacation: bookSlice(null, 'beach', T0) }, T0 + 2 * DAY).changes;
  const read = archiveOf({ vacation: v });
  assert.equal(read.length, 2);
  assert.deepEqual(read, v.archive);
  // junk leaves in a hand-broken save are healed on read
  const dirty = { vacation: { ...v, archive: [...v.archive, 'junk', entry({ destId: 'nope' })] } };
  assert.deepEqual(archiveOf(dirty), v.archive);
});

// ------------------------------------------------- slice wiring (the trap)

test('vacation slice: archive + bookkeeping survive sliceOf (whitelist trap)', () => {
  const v = tick({ vacation: bookSlice(null, 'beach', T0) }, T0 + 2 * DAY).changes;
  const healed = sliceOf({ vacation: JSON.parse(JSON.stringify(v)) });
  assert.deepEqual(healed.archive, v.archive, 'sliceOf must NOT strip the archive');
  assert.equal(healed.lastPostcardDayProcessed, 2, 'bookkeeping survives too');
});

test('vacation slice: archive carries across book and pickup transitions', () => {
  const first = tick({ vacation: bookSlice(null, 'beach', T0) }, T0 + 3 * DAY).changes;
  assert.equal(first.archive.length, 2);
  const home = pickupSlice(first);
  assert.deepEqual(home.archive, first.archive, 'keepsakes survive the reunion');
  assert.equal(home.lastPostcardDayProcessed, 0, 'per-trip bookkeeping resets');
  const second = bookSlice(home, 'space', T0 + 10 * DAY);
  assert.deepEqual(second.archive, first.archive, 'keepsakes survive the next booking');
  assert.equal(second.lastPostcardDayProcessed, 0, 'fresh trip starts at day 0');
  // the second trip appends AFTER the first trip's cards
  const both = tick({ vacation: second }, T0 + 20 * DAY).changes;
  assert.equal(both.archive.length, 2 + 3);
  assert.deepEqual(both.archive.map((e) => e.destId),
    ['beach', 'beach', 'space', 'space', 'space']);
});
