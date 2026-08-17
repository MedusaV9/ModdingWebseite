import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { makeApp, client, setupCouple } from './helpers.js';
import { weekKeyOf, weekStartDateKey, weekDateKeys, previousWeekKey } from '../src/weekreview.js';
import { todayKey } from '../src/util.js';

// ---------------------------------------------------------------------------
// pure ISO week math (mirrored by ios Content/WeekReviewLogic.swift)

test('weekKeyOf follows ISO 8601 week rules', () => {
  assert.equal(weekKeyOf('2026-01-01'), '2026-W01'); // Thursday
  assert.equal(weekKeyOf('2026-08-10'), '2026-W33'); // Monday
  assert.equal(weekKeyOf('2026-08-16'), '2026-W33'); // Sunday of the same week
  assert.equal(weekKeyOf('2026-08-17'), '2026-W34');
  // Year boundaries: Jan 1–3 can belong to the previous ISO year …
  assert.equal(weekKeyOf('2027-01-01'), '2026-W53'); // Friday → previous ISO year
  assert.equal(weekKeyOf('2025-12-29'), '2026-W01'); // Monday → next ISO year
  // … and a Wednesday Dec 31 belongs to the NEXT ISO year's week 1.
  assert.equal(weekKeyOf('2024-12-31'), '2025-W01');
});

test('weekStartDateKey inverts weekKeyOf and validates keys', () => {
  assert.equal(weekStartDateKey('2026-W33'), '2026-08-10');
  assert.equal(weekStartDateKey('2026-W01'), '2025-12-29');
  assert.equal(weekStartDateKey('2026-W53'), '2026-12-28');
  for (const dateKey of ['2026-08-13', '2025-01-01', '2024-02-29', '2027-01-01']) {
    const week = weekKeyOf(dateKey);
    const days = weekDateKeys(week);
    assert.equal(days.length, 7);
    assert.ok(days.includes(dateKey), `${dateKey} must be inside its own week ${week}`);
    for (const day of days) assert.equal(weekKeyOf(day), week);
  }
  assert.throws(() => weekStartDateKey('2026-W54'), /YYYY-Www/);
  assert.throws(() => weekStartDateKey('2025-W53'), /valid ISO week/); // 2025 has 52 weeks
  assert.throws(() => weekStartDateKey('not-a-week'), /YYYY-Www/);
});

test('previousWeekKey walks backwards across year boundaries', () => {
  assert.equal(previousWeekKey('2026-W33'), '2026-W32');
  assert.equal(previousWeekKey('2026-W01'), '2025-W52');
});

// ---------------------------------------------------------------------------
// aggregation + the mutual highlight ritual

test('week review aggregates the current week and hides highlights until both shared', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const today = todayKey();
  const week = weekKeyOf(today);

  await a.api.post('/api/messages', { json: { type: 'text', text: 'Hallo du 💜' } });
  await b.api.post('/api/messages', { json: { type: 'text', text: 'Na du 😘' } });
  await a.api.post('/api/touches', { json: { type: 'heartbeat' } });
  await a.api.post(`/api/daily/${today}`, { json: { questionId: 1, text: 'Unser Ausflug ans Meer' } });
  await b.api.post(`/api/daily/${today}`, { json: { questionId: 1, text: 'Dein Lachen heute früh' } });
  await a.api.post('/api/checkins', { json: { kind: 'morning' } });
  await b.api.post('/api/checkins', { json: { kind: 'night' } });

  const review = await a.api.get(`/api/week-review?week=${week}`);
  assert.equal(review.status, 200);
  assert.equal(review.body.week, week);
  assert.equal(review.body.current, true);
  assert.equal(review.body.startDateKey, weekStartDateKey(week));
  assert.equal(review.body.stats.messages, 2);
  assert.equal(review.body.stats.touches, 1);
  assert.equal(review.body.stats.dailyBothAnswered, 1);
  assert.equal(review.body.stats.checkinDaysBoth, 1);
  assert.equal(review.body.stats.perfectDays, 1);
  assert.ok(review.body.quote, 'the both-answered daily becomes the quote');
  assert.equal(review.body.quote.dateKey, today);
  assert.equal(review.body.quote.answers[a.memberId], 'Unser Ausflug ans Meer');

  // Default week (no query) is the current week.
  const noQuery = await a.api.get('/api/week-review');
  assert.equal(noQuery.body.week, week);

  // Highlight ritual: Mia shares → Ben must NOT see it yet.
  const aSet = await a.api.put(`/api/week-review/${week}/highlight`, {
    json: { text: 'Unser Picknick am Fluss 🧺' },
  });
  assert.equal(aSet.status, 200);
  assert.equal(aSet.body.highlight.mine.text, 'Unser Picknick am Fluss 🧺');
  assert.equal(aSet.body.highlight.bothShared, false);

  const bBefore = await b.api.get(`/api/week-review?week=${week}`);
  assert.equal(bBefore.body.highlight.partner, null, 'anti-spoiler: hidden until Ben shared');
  assert.equal(bBefore.body.highlight.bothShared, false);

  const bSet = await b.api.put(`/api/week-review/${week}/highlight`, {
    json: { text: 'Dass du mich abgeholt hast' },
  });
  assert.equal(bSet.status, 200);
  assert.equal(bSet.body.highlight.bothShared, true);
  assert.equal(bSet.body.highlight.partner.text, 'Unser Picknick am Fluss 🧺');

  const aAfter = await a.api.get(`/api/week-review?week=${week}`);
  assert.equal(aAfter.body.highlight.partner.text, 'Dass du mich abgeholt hast');

  // Both shared ⇒ exactly one week_highlight_both app event.
  const events = await a.api.get('/api/app-events?type=week_highlight_both');
  assert.equal(events.body.events.length, 1);
  assert.equal(events.body.events[0].data.week, week);

  // Re-sharing replaces the text but never re-emits the event.
  await a.api.put(`/api/week-review/${week}/highlight`, { json: { text: 'Doch das Frühstück!' } });
  const eventsAfter = await a.api.get('/api/app-events?type=week_highlight_both');
  assert.equal(eventsAfter.body.events.length, 1);
});

test('week quote: shortest complete question-mark-free exchange wins, honest fallbacks', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a, b, coupleId } = await setupCouple(baseUrl);
  const week = weekKeyOf(todayKey());
  const days = weekDateKeys(week);
  const couple = app.store.data.couples[coupleId];
  const set = (dateKey, mine, theirs) => {
    couple.daily[dateKey] = {
      questionId: 1,
      answers: {
        [a.memberId]: { text: mine, answeredAt: `${dateKey}T10:00:00.000Z` },
        [b.memberId]: { text: theirs, answeredAt: `${dateKey}T11:00:00.000Z` },
      },
    };
  };
  const quoteOf = async () => (await a.api.get(`/api/week-review?week=${week}`)).body.quote;

  // Mon: the pre-heuristic winner — a complete, clean essay (longest combined).
  set(days[0],
    'Unser allererster gemeinsamer Roadtrip durch den Süden, mit allen Umwegen',
    'Wie wir uns beim Kofferpacken kringelig gelacht haben und trotzdem losgefahren sind');
  // Tue: short but complete (both ≥ 12 trimmed chars) and question-mark-free.
  set(days[1], 'Dein Lachen heute früh', 'Unser Ausflug ans Meer');
  // Wed: complete but one side is a counter-question.
  set(days[2], 'Meinst du das ernst?', 'Unser Kuss im Regen');
  // Thu: shortest of all, but not complete — sweet, not quotable.
  set(days[3], 'Ja ❤️', 'Du.');

  const quote = await quoteOf();
  assert.equal(quote.dateKey, days[1], 'shortest COMPLETE clean exchange beats the essay');
  assert.equal(quote.answers[a.memberId], 'Dein Lachen heute früh');

  // Without the crisp day the complete essay still beats the counter-question.
  delete couple.daily[days[1]];
  assert.equal((await quoteOf()).dateKey, days[0]);

  // Only '?' and one-worders left → the complete counter-question is least bad.
  delete couple.daily[days[0]];
  assert.equal((await quoteOf()).dateKey, days[2]);

  // Only incomplete days left → the LONGEST combined text is the least bad,
  // and a lone "Ja ❤️" day still yields a quote rather than nothing.
  delete couple.daily[days[2]];
  set(days[4], 'Immer du', 'Na klar du');
  assert.equal((await quoteOf()).dateKey, days[4]);
  delete couple.daily[days[4]];
  assert.equal((await quoteOf()).dateKey, days[3]);

  // Deterministic tie-break: identical tier + combined length → newer day.
  set(days[5], 'Unser Abend auf dem Balkon', 'Deine Nachricht am Morgen');
  set(days[6], 'Deine Nachricht am Morgen', 'Unser Abend auf dem Balkon');
  assert.equal((await quoteOf()).dateKey, days[6]);
});

test('week review validates weeks, photos and highlight windows', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  const week = weekKeyOf(todayKey());

  const future = await a.api.get('/api/week-review?week=2199-W01');
  assert.equal(future.status, 400);
  assert.equal(future.body.error, 'bad_week');

  const bogus = await a.api.get('/api/week-review?week=2026-W99');
  assert.equal(bogus.status, 400);

  const tooOld = await a.api.get('/api/week-review?week=2019-W02');
  assert.equal(tooOld.status, 400);

  // Highlights: only current or previous week.
  const closed = previousWeekKey(previousWeekKey(week));
  const closedSet = await a.api.put(`/api/week-review/${closed}/highlight`, {
    json: { text: 'Zu spät' },
  });
  assert.equal(closedSet.status, 409);
  assert.equal(closedSet.body.error, 'week_closed');

  const badPhoto = await a.api.put(`/api/week-review/${week}/highlight`, {
    json: { text: 'Mit Foto', photoId: 'ph_missing' },
  });
  assert.equal(badPhoto.status, 404);
  assert.equal(badPhoto.body.error, 'photo_not_found');
});

test('read receipts work for completed weeks only and emit week_review_both once', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const current = weekKeyOf(todayKey());
  const last = previousWeekKey(current);

  const notOver = await a.api.post(`/api/week-review/${current}/seen`);
  assert.equal(notOver.status, 409);
  assert.equal(notOver.body.error, 'week_not_over');

  const aSeen = await a.api.post(`/api/week-review/${last}/seen`);
  assert.equal(aSeen.status, 200);
  assert.ok(aSeen.body.seen[a.memberId]);
  assert.equal(aSeen.body.seen[b.memberId], undefined);

  // Idempotent: the first timestamp survives.
  const again = await a.api.post(`/api/week-review/${last}/seen`);
  assert.equal(again.body.seen[a.memberId], aSeen.body.seen[a.memberId]);

  await b.api.post(`/api/week-review/${last}/seen`);
  const events = await a.api.get('/api/app-events?type=week_review_both');
  assert.equal(events.body.events.length, 1);
  assert.equal(events.body.events[0].data.week, last);

  // Replays never re-emit.
  await b.api.post(`/api/week-review/${last}/seen`);
  const eventsAfter = await a.api.get('/api/app-events?type=week_review_both');
  assert.equal(eventsAfter.body.events.length, 1);
});

test('week highlights survive a restart with the same DATA_DIR', async (t) => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), 'sooodreamy-week-'));
  t.after(() => rm(dataDir, { recursive: true, force: true }));
  const week = weekKeyOf(todayKey());

  const first = await makeApp(t, { dataDir });
  const { a } = await setupCouple(first.baseUrl);
  await a.api.put(`/api/week-review/${week}/highlight`, { json: { text: 'Bleibt gespeichert' } });
  await first.close();

  const second = await makeApp(t, { dataDir });
  const aApi = client(second.baseUrl, a.token);
  const review = await aApi.get(`/api/week-review?week=${week}`);
  assert.equal(review.status, 200);
  assert.equal(review.body.highlight.mine.text, 'Bleibt gespeichert');
});

// ---------------------------------------------------------------------------
// capWeeks data-rescue: evicted highlight texts survive in the year archive

test('capping highlights archives the evicted texts; the year review serves them', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a, b, coupleId } = await setupCouple(baseUrl);
  const couple = app.store.data.couples[coupleId];
  const currentWeek = weekKeyOf(todayKey());
  const seedYear = Number.parseInt(currentWeek.slice(0, 4), 10) - 1;

  // Seed a full half year of old highlights directly (the API only accepts
  // the current/previous week) — exactly at the 26-weeks-kept cap.
  couple.weekReview = { highlights: {}, seen: {} };
  for (let week = 1; week <= 26; week += 1) {
    const key = `${seedYear}-W${String(week).padStart(2, '0')}`;
    couple.weekReview.highlights[key] = {
      [a.memberId]: { text: `Mia ${key}`, photoId: null, setAt: '2025-01-01T00:00:00.000Z' },
      [b.memberId]: { text: `Ben ${key}`, photoId: null, setAt: '2025-01-01T00:00:00.000Z' },
    };
  }

  // The 27th week (a fresh share) evicts the oldest — into the archive, not
  // into the void.
  const put = await a.api.put(`/api/week-review/${currentWeek}/highlight`, { json: { text: 'Neu' } });
  assert.equal(put.status, 200);
  const review = couple.weekReview;
  assert.equal(`${seedYear}-W01` in review.highlights, false, 'oldest week evicted from the live bucket');
  assert.equal(Object.keys(review.highlights).length, 26);
  assert.deepEqual(review.highlightArchive, [
    { week: `${seedYear}-W01`, memberId: a.memberId, text: `Mia ${seedYear}-W01` },
    { week: `${seedYear}-W01`, memberId: b.memberId, text: `Ben ${seedYear}-W01` },
  ]);

  // The year review merges archived + still-live highlights of that year.
  const year = await a.api.get(`/api/yearreview?year=${seedYear}`);
  assert.equal(year.status, 200);
  const highlights = year.body.weekHighlights;
  assert.equal(highlights.length, 52); // 26 weeks × 2 members, archive + live
  assert.deepEqual(highlights[0], { week: `${seedYear}-W01`, memberId: a.memberId, text: `Mia ${seedYear}-W01` });
  assert.ok(highlights.some((e) => e.week === `${seedYear}-W26` && e.text === `Ben ${seedYear}-W26`));

  // The archive itself is bounded (104 = a year of two members): overflow
  // drops the OLDEST entries, never the freshly rescued ones.
  const dummies = Array.from({ length: 101 }, (_, i) => ({
    week: `${seedYear - 1}-W10`, memberId: a.memberId, text: `alt ${i}`,
  }));
  review.highlightArchive.push(...dummies); // 2 + 101 = 103
  const prevWeek = previousWeekKey(currentWeek);
  const put2 = await b.api.put(`/api/week-review/${prevWeek}/highlight`, { json: { text: 'Auch neu' } });
  assert.equal(put2.status, 200); // 27th key again → evicts seedYear-W02 (2 texts)
  assert.equal(review.highlightArchive.length, 104);
  assert.equal(review.highlightArchive[0].text, `Ben ${seedYear}-W01`, 'only the very oldest entry rolled off');
  assert.deepEqual(review.highlightArchive.at(-1), {
    week: `${seedYear}-W02`, memberId: b.memberId, text: `Ben ${seedYear}-W02`,
  });
});
