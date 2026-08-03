import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple, wsOpen, dateKeyDaysAgo } from './helpers.js';

test('daily answers: hidden partner answer, tailored WS payloads, streak over two days', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await aSock.waitFor('welcome');
  await bSock.waitFor('welcome');

  const yesterday = dateKeyDaysAgo(1);
  const today = dateKeyDaysAgo(0);

  // Nothing answered yet.
  const empty = await a.api.get(`/api/daily/${today}`);
  assert.deepEqual(empty.body, {
    dateKey: today,
    questionId: null,
    myAnswer: null,
    partnerAnswer: null,
    bothAnswered: false,
    streak: 0,
  });

  // Both answer YESTERDAY → streak becomes 1 (consecutive run ends yesterday).
  await a.api.post(`/api/daily/${yesterday}`, { json: { questionId: 41, text: 'the beach day' } });
  const yEntry = await b.api.post(`/api/daily/${yesterday}`, { json: { questionId: 41, text: 'our first trip' } });
  assert.equal(yEntry.body.bothAnswered, true);
  assert.equal(yEntry.body.streak, 1);
  // drain yesterday's daily_answer frames so today's assertions are clean
  await aSock.waitFor('daily_answer', (m) => m.payload.dateKey === yesterday);
  await aSock.waitFor('daily_answer', (m) => m.payload.dateKey === yesterday);
  await bSock.waitFor('daily_answer', (m) => m.payload.dateKey === yesterday);
  await bSock.waitFor('daily_answer', (m) => m.payload.dateKey === yesterday);

  // A answers TODAY: partner answer stays hidden, streak still 1.
  const aFirst = await a.api.post(`/api/daily/${today}`, { json: { questionId: 42, text: 'pancakes 🥞' } });
  assert.equal(aFirst.status, 200);
  assert.deepEqual(aFirst.body, {
    dateKey: today,
    questionId: 42,
    myAnswer: 'pancakes 🥞',
    partnerAnswer: null,
    bothAnswered: false,
    streak: 1,
  });

  // Tailored WS frames: A sees their own answer, B sees myAnswer:null and no partner answer yet.
  const aFrame1 = await aSock.waitFor('daily_answer', (m) => m.payload.dateKey === today);
  assert.equal(aFrame1.payload.myAnswer, 'pancakes 🥞');
  assert.equal(aFrame1.payload.partnerAnswer, null);
  const bFrame1 = await bSock.waitFor('daily_answer', (m) => m.payload.dateKey === today);
  assert.equal(bFrame1.payload.myAnswer, null);
  assert.equal(bFrame1.payload.partnerAnswer, null);
  assert.equal(bFrame1.payload.bothAnswered, false);

  // B answers TODAY → both see both answers, bothAnswered true, streak 2.
  const bAnswer = await b.api.post(`/api/daily/${today}`, { json: { questionId: 42, text: 'waffles 🧇' } });
  assert.deepEqual(bAnswer.body, {
    dateKey: today,
    questionId: 42,
    myAnswer: 'waffles 🧇',
    partnerAnswer: 'pancakes 🥞',
    bothAnswered: true,
    streak: 2,
  });

  const aFrame2 = await aSock.waitFor('daily_answer', (m) => m.payload.dateKey === today && m.payload.bothAnswered);
  assert.equal(aFrame2.payload.myAnswer, 'pancakes 🥞');
  assert.equal(aFrame2.payload.partnerAnswer, 'waffles 🧇');
  assert.equal(aFrame2.payload.streak, 2);
  const bFrame2 = await bSock.waitFor('daily_answer', (m) => m.payload.dateKey === today && m.payload.bothAnswered);
  assert.equal(bFrame2.payload.myAnswer, 'waffles 🧇');
  assert.equal(bFrame2.payload.partnerAnswer, 'pancakes 🥞');

  // GET view for A agrees.
  const aView = await a.api.get(`/api/daily/${today}`);
  assert.equal(aView.body.partnerAnswer, 'waffles 🧇');
  assert.equal(aView.body.streak, 2);
});

test('streak is 0 when the chain is broken (only a day 3 days ago answered)', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const old = dateKeyDaysAgo(3);
  await a.api.post(`/api/daily/${old}`, { json: { questionId: 1, text: 'a' } });
  await b.api.post(`/api/daily/${old}`, { json: { questionId: 1, text: 'b' } });
  const res = await a.api.get(`/api/daily/${dateKeyDaysAgo(0)}`);
  assert.equal(res.body.streak, 0);
});

test('daily validation: bad dateKey, missing questionId, missing text', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  assert.equal((await a.api.get('/api/daily/not-a-date')).status, 400);
  assert.equal((await a.api.post('/api/daily/2026-08-03', { json: { text: 'x' } })).status, 400);
  assert.equal((await a.api.post('/api/daily/2026-08-03', { json: { questionId: 1 } })).status, 400);
});
