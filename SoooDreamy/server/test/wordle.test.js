import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple, wsOpen, dateKeyDaysAgo } from './helpers.js';

const GRID_A = '🟩🟩🟨⬛⬛\n🟩🟩🟩🟩🟩';
const GRID_B = '⬛⬛⬛⬛⬛\n🟨🟨⬛⬛⬛\n🟩🟩🟩🟩🟩';

test('wordle duel: anti-spoiler views + tailored wordle_result broadcasts for both members', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await aSock.waitFor('welcome');
  await bSock.waitFor('welcome');
  const today = dateKeyDaysAgo(0);

  // Before anything: empty views for both.
  assert.deepEqual((await a.api.get(`/api/wordle/${today}`)).body, {
    dateKey: today,
    mine: null,
    partner: null,
    partnerFinished: false,
  });

  // A submits.
  const aRes = await a.api.post(`/api/wordle/${today}`, { json: { rows: 2, win: true, grid: GRID_A, lang: 'de' } });
  assert.equal(aRes.status, 200);
  assert.deepEqual(aRes.body.mine, {
    memberId: a.memberId,
    rows: 2,
    win: true,
    grid: GRID_A,
    lang: 'de',
    finishedAt: aRes.body.mine.finishedAt,
  });
  assert.ok(aRes.body.mine.finishedAt);
  assert.equal(aRes.body.partner, null);
  assert.equal(aRes.body.partnerFinished, false);

  // Tailored broadcasts: A sees their own result; B only learns "partner finished" — NO grid.
  const aFrame = await aSock.waitFor('wordle_result', (m) => m.payload.dateKey === today);
  assert.deepEqual(aFrame.payload.mine, aRes.body.mine);
  assert.equal(aFrame.payload.partnerFinished, false);
  const bFrame = await bSock.waitFor('wordle_result', (m) => m.payload.dateKey === today);
  assert.equal(bFrame.payload.mine, null);
  assert.equal(bFrame.payload.partner, null); // anti-spoiler
  assert.equal(bFrame.payload.partnerFinished, true); // but truthful

  // B's GET view before submitting: partner hidden, partnerFinished true.
  const bBefore = await b.api.get(`/api/wordle/${today}`);
  assert.equal(bBefore.body.mine, null);
  assert.equal(bBefore.body.partner, null);
  assert.equal(bBefore.body.partnerFinished, true);

  // B submits → both sides now see everything.
  const bRes = await b.api.post(`/api/wordle/${today}`, { json: { rows: 3, win: true, grid: GRID_B, lang: 'de' } });
  assert.equal(bRes.body.mine.rows, 3);
  assert.deepEqual(bRes.body.partner, aRes.body.mine);
  assert.equal(bRes.body.partnerFinished, true);

  const aFrame2 = await aSock.waitFor('wordle_result', (m) => m.payload.dateKey === today && m.payload.partnerFinished);
  assert.deepEqual(aFrame2.payload.mine, aRes.body.mine);
  assert.deepEqual(aFrame2.payload.partner, bRes.body.mine);
  const bFrame2 = await bSock.waitFor('wordle_result', (m) => m.payload.dateKey === today && m.payload.mine !== null);
  assert.deepEqual(bFrame2.payload.partner, aRes.body.mine);

  const aAfter = await a.api.get(`/api/wordle/${today}`);
  assert.deepEqual(aAfter.body.partner, bRes.body.mine);
});

test('wordle resubmit is idempotent (no overwrite, no extra broadcast)', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');
  const today = dateKeyDaysAgo(0);

  const first = await a.api.post(`/api/wordle/${today}`, { json: { rows: 4, win: false, grid: GRID_A, lang: 'en' } });
  await bSock.waitFor('wordle_result');

  const again = await a.api.post(`/api/wordle/${today}`, { json: { rows: 1, win: true, grid: 'different', lang: 'de' } });
  assert.equal(again.status, 200);
  assert.deepEqual(again.body.mine, first.body.mine); // stored result untouched
  await bSock.assertNone('wordle_result'); // nothing changed → nothing broadcast
});

test('wordle validation: rows, win, grid, lang, dateKey → 400', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  const today = dateKeyDaysAgo(0);
  const ok = { rows: 3, win: true, grid: GRID_A, lang: 'en' };

  assert.equal((await a.api.post('/api/wordle/not-a-date', { json: ok })).status, 400);
  assert.equal((await a.api.get('/api/wordle/2026-13-99')).status, 400);
  for (const bad of [
    { ...ok, rows: 0 },
    { ...ok, rows: 7 },
    { ...ok, rows: 2.5 },
    { ...ok, rows: '3' },
    { ...ok, win: 'yes' },
    { ...ok, grid: 'x'.repeat(161) },
    { ...ok, grid: 42 },
    { ...ok, lang: 'fr' },
  ]) {
    const res = await a.api.post(`/api/wordle/${today}`, { json: bad });
    assert.equal(res.status, 400, `expected 400 for ${JSON.stringify(bad)}`);
  }
  // Nothing was stored by the failed attempts.
  assert.equal((await a.api.get(`/api/wordle/${today}`)).body.mine, null);
});

test('wordle keeps at most 60 dateKeys per couple (oldest pruned)', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);

  for (let days = 60; days >= 0; days--) {
    const res = await a.api.post(`/api/wordle/${dateKeyDaysAgo(days)}`, {
      json: { rows: 3, win: true, grid: 'g', lang: 'en' },
    });
    assert.equal(res.status, 200);
  }

  // 61 days submitted → the oldest one fell off.
  assert.equal((await a.api.get(`/api/wordle/${dateKeyDaysAgo(60)}`)).body.mine, null);
  assert.ok((await a.api.get(`/api/wordle/${dateKeyDaysAgo(59)}`)).body.mine);
  assert.ok((await a.api.get(`/api/wordle/${dateKeyDaysAgo(0)}`)).body.mine);
});
