import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple } from './helpers.js';
import { monthsBackSameDay, distanceFromMonths } from '../src/memories.js';
import { todayKey } from '../src/util.js';

// ---------------------------------------------------------------------------
// pure month math (mirrored by ios Content/MemoriesLogic.swift)

test('monthsBackSameDay matches only the exact day-of-month', () => {
  assert.equal(monthsBackSameDay('2026-07-13', '2026-08-13'), 1);
  assert.equal(monthsBackSameDay('2025-08-13', '2026-08-13'), 12);
  assert.equal(monthsBackSameDay('2024-02-29', '2026-08-13'), null); // different day
  assert.equal(monthsBackSameDay('2024-02-29', '2028-02-29'), 48);   // leap → leap
  assert.equal(monthsBackSameDay('2026-08-13', '2026-08-13'), null); // same day = no memory
  assert.equal(monthsBackSameDay('2026-09-13', '2026-08-13'), null); // future
  // Jan 31 → there IS no Feb 31: honest gap instead of fuzzy matching.
  assert.equal(monthsBackSameDay('2026-01-31', '2026-02-28'), null);
  assert.equal(monthsBackSameDay('2026-01-31', '2026-03-31'), 2);
});

test('distanceFromMonths collapses whole years', () => {
  assert.deepEqual(distanceFromMonths(1), { unit: 'months', n: 1 });
  assert.deepEqual(distanceFromMonths(11), { unit: 'months', n: 11 });
  assert.deepEqual(distanceFromMonths(12), { unit: 'years', n: 1 });
  assert.deepEqual(distanceFromMonths(30), { unit: 'months', n: 30 });
  assert.deepEqual(distanceFromMonths(24), { unit: 'years', n: 2 });
});

// ---------------------------------------------------------------------------
// GET /api/on-this-day

/** Shifts a dateKey by whole months keeping the day (test data is chosen so the day exists). */
function monthsAgoKey(months, from = todayKey()) {
  let year = Number(from.slice(0, 4));
  let month = Number(from.slice(5, 7)) - months;
  while (month < 1) { month += 12; year -= 1; }
  return `${year}-${String(month).padStart(2, '0')}-${from.slice(8)}`;
}

test('on-this-day surfaces backdated photos and dailies with correct distances', async (t) => {
  const { app, baseUrl } = await makeApp(t);
  const { coupleId, a, b } = await setupCouple(baseUrl);
  const today = todayKey();
  const oneMonthAgo = monthsAgoKey(1);
  const oneYearAgo = monthsAgoKey(12);

  // Fresh couple: empty but valid.
  const empty = await a.api.get('/api/on-this-day');
  assert.equal(empty.status, 200);
  assert.deepEqual(empty.body.items, []);
  assert.equal(empty.body.dateKey, today);
  assert.equal(empty.body.monthiversary, null);

  // Backdate store content (no API can create the past).
  const couple = app.store.data.couples[coupleId];
  couple.photos.push({
    id: 'p_old1', uploaderId: a.memberId, caption: 'Picknick 🌼',
    url: '/api/photos/p_old1/raw', thumbUrl: null, width: null, height: null,
    album: null, createdAt: `${oneYearAgo}T12:00:00.000Z`, favorites: [],
  });
  couple.photos.push({
    id: 'p_old2', uploaderId: b.memberId, caption: null,
    url: '/api/photos/p_old2/raw', thumbUrl: null, width: null, height: null,
    album: null, createdAt: `${oneMonthAgo}T09:30:00.000Z`, favorites: [b.memberId],
  });
  couple.daily[oneMonthAgo] = {
    questionId: 7,
    answers: {
      [a.memberId]: { text: 'Dein Lachen', answeredAt: `${oneMonthAgo}T20:00:00.000Z` },
      [b.memberId]: { text: 'Unser Spaziergang', answeredAt: `${oneMonthAgo}T21:00:00.000Z` },
    },
  };
  // A HALF-answered daily must stay private — never a shared memory.
  couple.daily[oneYearAgo] = {
    questionId: 9,
    answers: { [a.memberId]: { text: 'Geheim', answeredAt: `${oneYearAgo}T20:00:00.000Z` } },
  };
  app.store.markDirty();
  await app.store.flush();

  const res = await a.api.get('/api/on-this-day');
  assert.equal(res.status, 200);
  assert.equal(res.body.items.length, 3);
  // Closest first; photo before daily on the same distance.
  assert.equal(res.body.items[0].kind, 'photo');
  assert.equal(res.body.items[0].photo.id, 'p_old2');
  assert.deepEqual(res.body.items[0].distance, { unit: 'months', n: 1 });
  assert.equal(res.body.items[1].kind, 'daily');
  assert.equal(res.body.items[1].dateKey, oneMonthAgo);
  assert.equal(res.body.items[1].answers[a.memberId], 'Dein Lachen');
  assert.equal(res.body.items[2].kind, 'photo');
  assert.deepEqual(res.body.items[2].distance, { unit: 'years', n: 1 });
  // Both partners see the identical deterministic list.
  const forB = await b.api.get('/api/on-this-day');
  assert.deepEqual(forB.body.items, res.body.items);
});

test('on-this-day validates the date parameter and reports monthiversaries', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  const today = todayKey();

  assert.equal((await a.api.get('/api/on-this-day?date=13.08.2026')).status, 400);
  const future = await a.api.get('/api/on-this-day?date=2999-01-01');
  assert.equal(future.status, 400);
  assert.equal(future.body.error, 'bad_date');

  // Anniversary exactly 6 months before an explicitly requested day.
  const anniversary = monthsAgoKey(6, today);
  await a.api.patch('/api/couple', { json: { anniversary } });
  const res = await a.api.get(`/api/on-this-day?date=${today}`);
  assert.equal(res.status, 200);
  assert.deepEqual(res.body.monthiversary, { unit: 'months', n: 6 });
  assert.ok(res.body.daysTogether > 0);
});

// ---------------------------------------------------------------------------
// GET /api/story

test('story timeline collects paired day, firsts, milestones and badges in order', async (t) => {
  const { app, baseUrl } = await makeApp(t);
  const { coupleId, a, b } = await setupCouple(baseUrl);
  const today = todayKey();

  // A fresh couple already has its pairing-day chapter.
  const fresh = await a.api.get('/api/story');
  assert.equal(fresh.status, 200);
  assert.equal(fresh.body.entries.length, 1);
  assert.equal(fresh.body.entries[0].kind, 'paired');

  await a.api.patch('/api/couple', { json: { anniversary: '2024-02-14' } });
  await a.api.post('/api/messages', { json: { type: 'text', text: 'Unser allererster Text 💜 und er ist ziemlich lang, damit der Teaser gekürzt werden muss — noch ein paar Worte extra.' } });
  await b.api.post('/api/messages', { json: { type: 'text', text: 'Antwort' } });
  await a.api.post(`/api/daily/${today}`, { json: { questionId: 3, text: 'Kaffee im Bett' } });
  await b.api.post(`/api/daily/${today}`, { json: { questionId: 3, text: 'Dein Blick' } });

  // Backdate a first photo + a couple of unlocked badges.
  const couple = app.store.data.couples[coupleId];
  couple.photos.push({
    id: 'p_first', uploaderId: a.memberId, caption: 'Tag eins',
    url: '/api/photos/p_first/raw', thumbUrl: null, width: null, height: null,
    album: null, createdAt: '2025-01-05T10:00:00.000Z', favorites: [],
  });
  couple.gamification = {
    level: null, eventXp: 0, eventCursor: null, questCompletedAt: null,
    badges: { first_touch: '2025-02-01T08:00:00.000Z' },
  };
  app.store.markDirty();
  await app.store.flush();

  const res = await a.api.get('/api/story');
  assert.equal(res.status, 200);
  const kinds = res.body.entries.map((e) => e.kind);
  assert.deepEqual(kinds.slice(0, 1), ['begin']); // anniversary opens the story
  assert.ok(kinds.includes('paired'));
  assert.ok(kinds.includes('first_message'));
  assert.ok(kinds.includes('first_photo'));
  assert.ok(kinds.includes('first_daily'));
  assert.ok(kinds.includes('badge'));
  // Ascending by dateKey throughout.
  const dateKeys = res.body.entries.map((e) => e.dateKey);
  assert.deepEqual(dateKeys, [...dateKeys].sort());
  // Teaser is capped and marked.
  const firstMessage = res.body.entries.find((e) => e.kind === 'first_message');
  assert.ok(firstMessage.teaser.length <= 80);
  assert.ok(firstMessage.teaser.endsWith('…'));
  assert.equal(res.body.sinceKey, '2024-02-14');
  // Deterministic for both members.
  const forB = await b.api.get('/api/story');
  assert.deepEqual(forB.body, res.body);
});

test('story milestones honor caps honestly (messages only while nothing rotated out)', async (t) => {
  const { app, baseUrl } = await makeApp(t);
  const { coupleId, a } = await setupCouple(baseUrl);

  const couple = app.store.data.couples[coupleId];
  // 10 backdated photos → the 10-photos milestone exists, 25 does not.
  for (let i = 0; i < 10; i++) {
    couple.photos.push({
      id: `p_${String(i).padStart(2, '0')}`, uploaderId: a.memberId, caption: null,
      url: `/api/photos/p_${i}/raw`, thumbUrl: null, width: null, height: null,
      album: null, createdAt: `2025-03-${String(i + 1).padStart(2, '0')}T10:00:00.000Z`,
      favorites: [],
    });
  }
  // Simulate rotation: the counter says 150 messages ever, but only 1 retained.
  couple.messages.push({
    id: 'm1', type: 'text', text: 'hi', senderId: a.memberId,
    createdAt: '2025-03-01T10:00:00.000Z',
  });
  couple.counters.messages = 150;
  app.store.markDirty();
  await app.store.flush();

  const res = await a.api.get('/api/story');
  const photoMilestones = res.body.entries.filter((e) => e.kind === 'photos_milestone');
  assert.deepEqual(photoMilestones.map((e) => e.n), [10]);
  assert.equal(photoMilestones[0].dateKey, '2025-03-10');
  assert.equal(res.body.entries.filter((e) => e.kind === 'messages_milestone').length, 0,
    'rotated-out history must not invent wrong milestone dates');
});

test('memory routes require auth and never leak across couples', async (t) => {
  const { app, baseUrl } = await makeApp(t);
  const first = await setupCouple(baseUrl);
  const second = await setupCouple(baseUrl);

  const anon = await fetch(`${baseUrl}/api/on-this-day`);
  assert.equal(anon.status, 401);

  const couple = app.store.data.couples[first.coupleId];
  couple.photos.push({
    id: 'p_secret', uploaderId: first.a.memberId, caption: 'nur für uns',
    url: '/api/photos/p_secret/raw', thumbUrl: null, width: null, height: null,
    album: null, createdAt: `${monthsAgoKey(2)}T10:00:00.000Z`, favorites: [],
  });
  app.store.markDirty();
  await app.store.flush();

  const mine = await first.a.api.get('/api/on-this-day');
  assert.equal(mine.body.items.length, 1);
  const theirs = await second.a.api.get('/api/on-this-day');
  assert.deepEqual(theirs.body.items, []);
});
