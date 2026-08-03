import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { makeApp, setupCouple, wsOpen, client, dateKeyDaysAgo } from './helpers.js';

const GRID_A = '🟩🟩🟨⬛⬛\n🟩🟩🟩🟩🟩';
const GRID_B = '⬛⬛⬛⬛⬛\n🟨🟨⬛⬛⬛\n🟩🟩🟩🟩🟩';

/** Boots an app on a crafted store.json (two members m_a/m_b, tokens tok_a/tok_b). */
async function makeSeededApp(t, coupleExtras) {
  const at = '2024-01-02T00:00:00.000Z';
  const member = (id, name) => ({
    id, name, avatar: '💞', color: '#FF5C8A',
    mood: null, moodNote: null, moodUpdatedAt: null, lastSeenAt: null, joinedAt: at,
  });
  const store = {
    version: 1,
    couples: {
      c_seed: {
        id: 'c_seed', code: 'SEEDED', name: null, anniversary: null, createdAt: at,
        members: [member('m_a', 'Mia'), member('m_b', 'Ben')],
        touches: [], messages: [], photos: [], events: [], bucket: [], strokes: [],
        daily: {}, games: [], moodHistory: {}, wordle: {}, coupons: [],
        counters: { messages: 0, gamesPlayed: 0, touches: {} },
        ...coupleExtras,
      },
    },
    tokens: { tok_a: { coupleId: 'c_seed', memberId: 'm_a' }, tok_b: { coupleId: 'c_seed', memberId: 'm_b' } },
  };
  const dataDir = await mkdtemp(path.join(os.tmpdir(), 'sooodreamy-wordle-'));
  await writeFile(path.join(dataDir, 'store.json'), JSON.stringify(store), 'utf8');
  const { baseUrl } = await makeApp(t, { dataDir });
  return { baseUrl, a: client(baseUrl, 'tok_a'), b: client(baseUrl, 'tok_b') };
}

test('wordle duel: anti-spoiler views + tailored wordle_result broadcasts (per language)', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await aSock.waitFor('welcome');
  await bSock.waitFor('welcome');
  const today = dateKeyDaysAgo(0);

  // Before anything: empty view for the requested language.
  assert.deepEqual((await a.api.get(`/api/wordle/${today}?lang=de`)).body, {
    dateKey: today,
    lang: 'de',
    mine: null,
    partner: null,
    partnerFinished: false,
  });

  // A submits (DE).
  const aRes = await a.api.post(`/api/wordle/${today}`, { json: { rows: 2, win: true, grid: GRID_A, lang: 'de' } });
  assert.equal(aRes.status, 200);
  assert.equal(aRes.body.lang, 'de');
  assert.deepEqual(aRes.body.mine, {
    memberId: a.memberId,
    rows: 2,
    win: true,
    grid: GRID_A,
    lang: 'de',
    finishedAt: aRes.body.mine.finishedAt,
  });
  assert.equal(aRes.body.partner, null);
  assert.equal(aRes.body.partnerFinished, false);

  // Tailored broadcasts carry the lang; B only learns "partner finished" — NO grid.
  const aFrame = await aSock.waitFor('wordle_result', (m) => m.payload.dateKey === today);
  assert.equal(aFrame.payload.lang, 'de');
  assert.deepEqual(aFrame.payload.mine, aRes.body.mine);
  const bFrame = await bSock.waitFor('wordle_result', (m) => m.payload.dateKey === today);
  assert.equal(bFrame.payload.lang, 'de');
  assert.equal(bFrame.payload.mine, null);
  assert.equal(bFrame.payload.partner, null); // anti-spoiler
  assert.equal(bFrame.payload.partnerFinished, true); // but truthful

  // B's GET view (DE) before submitting: partner hidden, partnerFinished true.
  const bBefore = await b.api.get(`/api/wordle/${today}?lang=de`);
  assert.equal(bBefore.body.mine, null);
  assert.equal(bBefore.body.partner, null);
  assert.equal(bBefore.body.partnerFinished, true);

  // B submits (DE) → both sides now see everything for DE.
  const bRes = await b.api.post(`/api/wordle/${today}`, { json: { rows: 3, win: true, grid: GRID_B, lang: 'de' } });
  assert.equal(bRes.body.mine.rows, 3);
  assert.deepEqual(bRes.body.partner, aRes.body.mine);

  const aFrame2 = await aSock.waitFor('wordle_result', (m) => m.payload.dateKey === today && m.payload.partnerFinished);
  assert.deepEqual(aFrame2.payload.partner, bRes.body.mine);
  const bFrame2 = await bSock.waitFor('wordle_result', (m) => m.payload.dateKey === today && m.payload.mine !== null);
  assert.deepEqual(bFrame2.payload.partner, aRes.body.mine);

  const aAfter = await a.api.get(`/api/wordle/${today}?lang=de`);
  assert.deepEqual(aAfter.body.partner, bRes.body.mine);
});

test('wordle languages are independent: DE results never leak into the EN view', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const today = dateKeyDaysAgo(0);

  // A plays DE, B plays EN.
  await a.api.post(`/api/wordle/${today}`, { json: { rows: 2, win: true, grid: GRID_A, lang: 'de' } });
  await b.api.post(`/api/wordle/${today}`, { json: { rows: 6, win: false, grid: GRID_B, lang: 'en' } });

  // A's EN view is completely empty (their DE result does not count for EN).
  const aEn = (await a.api.get(`/api/wordle/${today}?lang=en`)).body;
  assert.equal(aEn.lang, 'en');
  assert.equal(aEn.mine, null);
  assert.equal(aEn.partner, null);
  assert.equal(aEn.partnerFinished, true); // B finished EN

  // B's DE view: B has no DE result, A's DE grid stays hidden but partnerFinished is truthful.
  const bDe = (await b.api.get(`/api/wordle/${today}?lang=de`)).body;
  assert.equal(bDe.mine, null);
  assert.equal(bDe.partner, null);
  assert.equal(bDe.partnerFinished, true);

  // Idempotency is per (member, dateKey, lang): A may also play EN the same day.
  const aEnRes = await a.api.post(`/api/wordle/${today}`, { json: { rows: 5, win: true, grid: 'EN grid', lang: 'en' } });
  assert.equal(aEnRes.body.mine.rows, 5);
  assert.deepEqual(aEnRes.body.partner.rows, 6); // B's EN result revealed now
  // A's DE result is untouched.
  assert.equal((await a.api.get(`/api/wordle/${today}?lang=de`)).body.mine.rows, 2);
});

test('wordle resubmit (same lang) is idempotent — no overwrite, no extra broadcast', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');
  const today = dateKeyDaysAgo(0);

  const first = await a.api.post(`/api/wordle/${today}`, { json: { rows: 4, win: false, grid: GRID_A, lang: 'en' } });
  await bSock.waitFor('wordle_result');

  const again = await a.api.post(`/api/wordle/${today}`, { json: { rows: 1, win: true, grid: 'different', lang: 'en' } });
  assert.equal(again.status, 200);
  assert.deepEqual(again.body.mine, first.body.mine); // stored result untouched
  await bSock.assertNone('wordle_result'); // nothing changed → nothing broadcast
});

test('wordle validation: body values, bad_lang on GET, dateKey format → 400', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  const today = dateKeyDaysAgo(0);
  const ok = { rows: 3, win: true, grid: GRID_A, lang: 'en' };

  assert.equal((await a.api.post('/api/wordle/not-a-date', { json: ok })).status, 400);
  assert.equal((await a.api.get('/api/wordle/2026-13-99?lang=de')).status, 400);
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

  // GET requires the lang query param.
  const missing = await a.api.get(`/api/wordle/${today}`);
  assert.equal(missing.status, 400);
  assert.equal(missing.body.error, 'bad_lang');
  const bogus = await a.api.get(`/api/wordle/${today}?lang=fr`);
  assert.equal(bogus.status, 400);
  assert.equal(bogus.body.error, 'bad_lang');

  // Nothing was stored by the failed attempts.
  assert.equal((await a.api.get(`/api/wordle/${today}?lang=en`)).body.mine, null);
});

test('wordle POST only accepts dateKeys within ±1 day of server-today (bad_datekey)', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  const ok = { rows: 3, win: true, grid: 'g', lang: 'en' };

  // A week-old and a far-future key are rejected.
  for (const dateKey of [dateKeyDaysAgo(7), dateKeyDaysAgo(-5)]) {
    const res = await a.api.post(`/api/wordle/${dateKey}`, { json: ok });
    assert.equal(res.status, 400, `expected 400 for ${dateKey}`);
    assert.equal(res.body.error, 'bad_datekey');
  }

  // Today, yesterday and tomorrow are all fine (timezone tolerance).
  for (const dateKey of [dateKeyDaysAgo(0), dateKeyDaysAgo(1), dateKeyDaysAgo(-1)]) {
    assert.equal((await a.api.post(`/api/wordle/${dateKey}`, { json: ok })).status, 200, dateKey);
  }

  // GET stays permissive for browsing history.
  assert.equal((await a.api.get(`/api/wordle/${dateKeyDaysAgo(30)}?lang=en`)).status, 200);
});

test('wordle keeps at most 60 dateKeys per couple (oldest pruned on submit)', async (t) => {
  // Old dateKeys can no longer be submitted via the API — seed 60 days directly.
  const wordle = {};
  for (let days = 100; days > 40; days--) {
    wordle[dateKeyDaysAgo(days)] = {
      en: { m_a: { memberId: 'm_a', rows: 3, win: true, grid: 'g', lang: 'en', finishedAt: '2024-01-02T00:00:00.000Z' } },
    };
  }
  const { a } = await makeSeededApp(t, { wordle });

  const res = await a.post(`/api/wordle/${dateKeyDaysAgo(0)}`, { json: { rows: 3, win: true, grid: 'g', lang: 'en' } });
  assert.equal(res.status, 200);

  // 61st dateKey → the oldest one fell off, the rest survived.
  assert.equal((await a.get(`/api/wordle/${dateKeyDaysAgo(100)}?lang=en`)).body.mine, null);
  assert.ok((await a.get(`/api/wordle/${dateKeyDaysAgo(99)}?lang=en`)).body.mine);
  assert.ok((await a.get(`/api/wordle/${dateKeyDaysAgo(0)}?lang=en`)).body.mine);
});

test('v1.2.0 wordle store shape (no lang buckets) is normalized lazily on read', async (t) => {
  const today = dateKeyDaysAgo(0);
  const finishedAt = '2024-01-02T00:00:00.000Z';
  const { a, b } = await makeSeededApp(t, {
    wordle: {
      // Old shape: dateKey → memberId → WordleResult (lang lives inside the result).
      [today]: {
        m_a: { memberId: 'm_a', rows: 2, win: true, grid: 'AAAA', lang: 'de', finishedAt },
        m_b: { memberId: 'm_b', rows: 5, win: false, grid: 'BBBB', lang: 'de', finishedAt },
      },
    },
  });

  // Both results land in the DE bucket; the full duel view works.
  const aDe = (await a.get(`/api/wordle/${today}?lang=de`)).body;
  assert.equal(aDe.mine.grid, 'AAAA');
  assert.equal(aDe.partner.grid, 'BBBB');
  assert.equal(aDe.partnerFinished, true);

  // The EN bucket of the same day is empty.
  const aEn = (await a.get(`/api/wordle/${today}?lang=en`)).body;
  assert.equal(aEn.mine, null);
  assert.equal(aEn.partnerFinished, false);

  // Submitting EN on the migrated day keeps the old DE results intact.
  const bEn = await b.post(`/api/wordle/${today}`, { json: { rows: 1, win: true, grid: 'NEW', lang: 'en' } });
  assert.equal(bEn.status, 200);
  assert.equal(bEn.body.mine.grid, 'NEW');
  assert.equal((await b.get(`/api/wordle/${today}?lang=de`)).body.mine.grid, 'BBBB');
});
