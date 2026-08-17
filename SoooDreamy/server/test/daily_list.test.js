import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple, dateKeyDaysAgo } from './helpers.js';

test('GET /api/daily lists answered days newest-first with per-member reveal semantics', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a, b, coupleId } = await setupCouple(baseUrl);

  const twoDaysAgo = dateKeyDaysAgo(2);
  const yesterday = dateKeyDaysAgo(1);
  const today = dateKeyDaysAgo(0);

  // Empty journal before anyone answers.
  assert.deepEqual((await a.api.get('/api/daily')).body, { entries: [] });

  // Historical records remain readable, but writes older than yesterday are
  // intentionally rejected. Seed that persisted history directly.
  app.store.data.couples[coupleId].daily[twoDaysAgo] = {
    questionId: 1,
    answers: {
      [a.memberId]: { text: 'A day1', answeredAt: new Date().toISOString() },
      [b.memberId]: { text: 'B day1', answeredAt: new Date().toISOString() },
    },
  };
  app.store.markDirty();
  // Yesterday: only A. Today: only B.
  await a.api.post(`/api/daily/${yesterday}`, { json: { questionId: 2, text: 'A day2' } });
  await b.api.post(`/api/daily/${today}`, { json: { questionId: 3, text: 'B day3' } });

  const aView = (await a.api.get('/api/daily')).body.entries;
  assert.deepEqual(aView.map((e) => e.dateKey), [today, yesterday, twoDaysAgo]); // dateKey descending

  // Today: A did not answer; B's answer stays hidden (not bothAnswered).
  assert.deepEqual(
    aView[0],
    { dateKey: today, questionId: 3, questionText: null, myAnswer: null, partnerAnswer: null,
      bothAnswered: false, streak: 0, customQuestion: null },
  );
  // Yesterday: A sees their own answer, partner hidden.
  assert.equal(aView[1].myAnswer, 'A day2');
  assert.equal(aView[1].partnerAnswer, null);
  assert.equal(aView[1].bothAnswered, false);
  // Two days ago: both answered → revealed.
  assert.equal(aView[2].myAnswer, 'A day1');
  assert.equal(aView[2].partnerAnswer, 'B day1');
  assert.equal(aView[2].bothAnswered, true);

  // B's view mirrors the reveal per member.
  const bView = (await b.api.get('/api/daily')).body.entries;
  assert.equal(bView[0].myAnswer, 'B day3');
  assert.equal(bView[1].myAnswer, null);
  assert.equal(bView[1].partnerAnswer, null);
  assert.equal(bView[2].myAnswer, 'B day1');
  assert.equal(bView[2].partnerAnswer, 'A day1');
});

test('GET /api/daily?limit trims to the newest days; bad limit → 400', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a, coupleId } = await setupCouple(baseUrl);

  for (let days = 0; days < 4; days++) {
    app.store.data.couples[coupleId].daily[dateKeyDaysAgo(days)] = {
      questionId: days,
      answers: {
        [a.memberId]: { text: `entry ${days}`, answeredAt: new Date().toISOString() },
      },
    };
  }
  app.store.markDirty();

  const limited = (await a.api.get('/api/daily?limit=2')).body.entries;
  assert.deepEqual(limited.map((e) => e.dateKey), [dateKeyDaysAgo(0), dateKeyDaysAgo(1)]);

  const all = (await a.api.get('/api/daily')).body.entries;
  assert.equal(all.length, 4);

  assert.equal((await a.api.get('/api/daily?limit=x')).status, 400);
});
