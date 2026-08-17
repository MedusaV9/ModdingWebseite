import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple, client, dateKeyDaysAgo } from './helpers.js';

test('stats reflect touches, messages, photos, bucket, daily and games', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  await a.api.patch('/api/couple', { json: { anniversary: '2023-11-07' } });

  await a.api.post('/api/touches', { json: { type: 'kiss' } });
  await a.api.post('/api/touches', { json: { type: 'hug' } });
  await b.api.post('/api/touches', { json: { type: 'kiss' } });

  await a.api.post('/api/messages', { json: { type: 'text', text: 'hey' } });
  await b.api.post('/api/voice', { body: Buffer.from('audio'), headers: { 'content-type': 'audio/mp4' } });

  await a.api.post('/api/photos', { body: Buffer.from('jpg'), headers: { 'content-type': 'image/jpeg' } });

  await a.api.post('/api/bucket', { json: { text: 'Do a thing' } });
  const item2 = (await a.api.post('/api/bucket', { json: { text: 'Do another thing' } })).body.item;
  await b.api.patch(`/api/bucket/${item2.id}`, { json: { done: true } });

  const today = dateKeyDaysAgo(0);
  await a.api.post(`/api/daily/${today}`, { json: { questionId: 7, text: 'mine' } });
  await b.api.post(`/api/daily/${today}`, { json: { questionId: 7, text: 'yours' } });

  const game = (await a.api.post('/api/games', { json: { type: 'quiz' } })).body.game;
  await b.api.post(`/api/games/${game.id}/join`, { json: {} });
  await a.api.post(`/api/games/${game.id}/end`, { json: { forfeit: true } });

  const res = await a.api.get('/api/stats');
  assert.equal(res.status, 200);
  const stats = res.body;

  const expectedDays = Math.floor((Date.now() - Date.parse('2023-11-07T00:00:00.000Z')) / 86_400_000);
  assert.ok(Math.abs(stats.daysTogether - expectedDays) <= 1, `daysTogether ${stats.daysTogether} ≉ ${expectedDays}`);

  assert.deepEqual(stats.touchesSent, { total: 2, byType: { kiss: 1, hug: 1 } });
  assert.deepEqual(stats.touchesReceived, { total: 1, byType: { kiss: 1 } });
  assert.equal(stats.messages, 2);
  assert.equal(stats.photos, 1);
  assert.equal(stats.bucketDone, 1);
  assert.equal(stats.bucketTotal, 2);
  assert.equal(stats.dailyStreak, 1);
  assert.equal(stats.dailyAnswered, 1);
  assert.equal(stats.gamesPlayed, 1);

  // B's view mirrors touches.
  const bStats = (await b.api.get('/api/stats')).body;
  assert.deepEqual(bStats.touchesSent, { total: 1, byType: { kiss: 1 } });
  assert.deepEqual(bStats.touchesReceived, { total: 2, byType: { kiss: 1, hug: 1 } });
});

test('stats for a fresh couple are all zeros', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  const stats = (await a.api.get('/api/stats')).body;
  assert.equal(stats.daysTogether, 0);
  assert.deepEqual(stats.touchesSent, { total: 0, byType: {} });
  assert.equal(stats.messages, 0);
  assert.equal(stats.photos, 0);
  assert.equal(stats.bucketTotal, 0);
  assert.equal(stats.dailyStreak, 0);
  assert.equal(stats.gamesPlayed, 0);
});

test('widget snapshot aggregates partner, daily, photo, event and canvas state', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  await a.api.patch('/api/couple', { json: { name: 'Mia & Ben', anniversary: '2023-11-07' } });
  await b.api.patch('/api/me', { json: { mood: '🥰', moodNote: 'miss you' } });

  const today = dateKeyDaysAgo(0);
  await a.api.post(`/api/daily/${today}`, { json: { questionId: 7, text: 'mine' } });

  const oldPhoto = (await a.api.post('/api/photos', {
    body: Buffer.from('old'), headers: { 'content-type': 'image/jpeg', 'x-caption': 'Old' },
  })).body.photo;
  const newPhoto = (await a.api.post('/api/photos', {
    body: Buffer.from('new'), headers: { 'content-type': 'image/jpeg', 'x-caption': 'New' },
  })).body.photo;

  const pastEvent = (await a.api.post('/api/events', {
    json: { title: 'One-off, over', date: dateKeyDaysAgo(10), repeatsYearly: false },
  })).body.event;
  const yearlyEvent = (await a.api.post('/api/events', {
    json: { title: 'Anniversary', emoji: '💍', date: dateKeyDaysAgo(30), repeatsYearly: true },
  })).body.event;
  const soonEvent = (await a.api.post('/api/events', {
    json: { title: 'Dinner date', emoji: '🍝', date: dateKeyDaysAgo(-5), repeatsYearly: false },
  })).body.event;

  const stroke1 = (await a.api.post('/api/canvas/strokes', { json: { points: [[0.1, 0.2]] } })).body.stroke;
  const stroke2 = (await b.api.post('/api/canvas/strokes', { json: { points: [[0.3, 0.4]] } })).body.stroke;
  assert.ok(stroke1 && stroke2);

  const res = await a.api.get('/api/widget-snapshot');
  assert.equal(res.status, 200);
  const snap = res.body;

  assert.deepEqual(snap.me, { id: a.memberId, name: 'Mia', avatar: '🦊', color: '#FF5C8A' });
  assert.equal(snap.partner.id, b.memberId);
  assert.equal(snap.partner.name, 'Ben');
  assert.equal(snap.partner.mood, '🥰');
  assert.equal(snap.partner.moodNote, 'miss you');
  assert.equal(snap.partner.online, false);
  assert.equal(snap.couple.name, 'Mia & Ben');
  assert.equal(snap.couple.anniversary, '2023-11-07');

  const expectedDays = Math.floor((Date.now() - Date.parse('2023-11-07T00:00:00.000Z')) / 86_400_000);
  assert.ok(Math.abs(snap.daysTogether - expectedDays) <= 1, `daysTogether ${snap.daysTogether} ≉ ${expectedDays}`);

  assert.equal(snap.streak, 0); // only A answered so far
  assert.equal(snap.bothAnsweredToday, false);
  assert.equal(snap.dailyAnsweredByMe, true);
  assert.equal((await b.api.get('/api/widget-snapshot')).body.dailyAnsweredByMe, false);

  // No favorites yet → newest photo overall.
  assert.equal(snap.latestPhoto.id, newPhoto.id);
  assert.equal(snap.latestPhoto.caption, 'New');

  // Soonest upcoming event wins; the expired one-off is skipped.
  assert.equal(snap.nextEvent.id, soonEvent.id);
  assert.equal(snap.nextEvent.date, soonEvent.date);
  assert.ok(pastEvent && yearlyEvent);

  assert.equal(snap.canvasStrokeCount, 2);
  assert.equal(snap.canvasUpdatedAt, stroke2.createdAt);
  assert.ok(snap.serverTime);

  // Favoriting the older photo promotes it over the newer one.
  await b.api.post(`/api/photos/${oldPhoto.id}/favorite`, { json: {} });
  const favored = (await a.api.get('/api/widget-snapshot')).body.latestPhoto;
  assert.equal(favored.id, oldPhoto.id);
  assert.deepEqual(favored.favorites, [b.memberId]);

  // Once the soon event is gone, the passed yearly event wraps to its next occurrence.
  await a.api.del(`/api/events/${soonEvent.id}`);
  const monthDay = yearlyEvent.date.slice(4);
  const thisYear = today.slice(0, 4) + monthDay;
  const expectedWrap = thisYear >= today ? thisYear : `${Number(today.slice(0, 4)) + 1}${monthDay}`;
  const wrapped = (await a.api.get('/api/widget-snapshot')).body.nextEvent;
  assert.equal(wrapped.id, yearlyEvent.id);
  assert.equal(wrapped.date, expectedWrap);
  assert.equal(wrapped.repeatsYearly, true);

  // B answers today → streak & bothAnsweredToday flip.
  await b.api.post(`/api/daily/${today}`, { json: { questionId: 7, text: 'yours' } });
  const after = (await b.api.get('/api/widget-snapshot')).body;
  assert.equal(after.streak, 1);
  assert.equal(after.bothAnsweredToday, true);
  assert.equal(after.dailyAnsweredByMe, true);
});

test('widget snapshot: bearer auth, and nulls/zeros for a fresh single-member couple', async (t) => {
  const { baseUrl } = await makeApp(t);
  const anon = client(baseUrl);
  const created = await anon.post('/api/couples', { json: { name: 'Mia', avatar: '🦊', color: '#FF5C8A' } });
  assert.equal(created.status, 201);

  assert.equal((await anon.get('/api/widget-snapshot')).status, 401);

  const queryDenied = await anon.get(`/api/widget-snapshot?token=${encodeURIComponent(created.body.token)}`);
  assert.equal(queryDenied.status, 400);
  assert.equal(queryDenied.body.error, 'query_token_forbidden');

  const res = await client(baseUrl, created.body.token).get('/api/widget-snapshot');
  assert.equal(res.status, 200);
  const snap = res.body;
  assert.equal(snap.partner, null);
  assert.equal(snap.me.id, created.body.memberId);
  assert.equal(snap.couple.anniversary, null);
  assert.equal(snap.daysTogether, 0); // falls back to the couple's createdAt
  assert.equal(snap.streak, 0);
  assert.equal(snap.bothAnsweredToday, false);
  assert.equal(snap.dailyAnsweredByMe, false);
  assert.equal(snap.latestPhoto, null);
  assert.equal(snap.nextEvent, null);
  assert.equal(snap.canvasStrokeCount, 0);
  assert.equal(snap.canvasUpdatedAt, null);
  assert.ok(snap.serverTime);
});
