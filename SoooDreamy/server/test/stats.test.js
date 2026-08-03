import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple, dateKeyDaysAgo } from './helpers.js';

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
  await a.api.post(`/api/games/${game.id}/end`, { json: { result: { winner: null } } });

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
