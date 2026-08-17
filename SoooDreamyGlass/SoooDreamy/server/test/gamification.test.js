import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple, wsOpen, client, dateKeyDaysAgo } from './helpers.js';
import { titleForLevel, chapterForLevel, romanNumeral, levelForXP } from '../src/gamification.js';

// ---------------------------------------------------------------------------
// level system (v3.0 Agent C): XP aggregation, curve, level_up ceremony

test('level: fresh couple starts at level 1 with 0 XP and DE/EN title', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);

  const res = await a.api.get('/api/level');
  assert.equal(res.status, 200);
  assert.equal(res.body.level, 1);
  assert.equal(res.body.xp, 0);
  assert.equal(res.body.levelXp, 0);
  assert.equal(res.body.nextLevelXp, 100); // L2 needs 100 XP
  assert.equal(res.body.progress, 0);
  assert.deepEqual(res.body.title, { de: 'Frisch verliebt', en: 'Freshly in love' });
  assert.equal(res.body.maxTitleLevel, 10);
  assert.ok(res.body.breakdown);
});

test('level: XP is deterministic and grows with shared actions (breakdown)', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  await a.api.post('/api/messages', { json: { type: 'text', text: 'hi ❤️' } });
  await b.api.post('/api/messages', { json: { type: 'text', text: 'hi back' } });
  await a.api.post('/api/touches', { json: { type: 'kiss' } });
  await a.api.post('/api/songs', { json: { title: 'Our song', artist: 'Us' } });

  const first = await a.api.get('/api/level');
  assert.equal(first.body.breakdown.messages, 4); // 2 msgs × 2 XP
  assert.equal(first.body.breakdown.touches, 1); // 1 touch × 1 XP
  assert.equal(first.body.breakdown.songs, 3); // 1 song × 3 XP
  assert.equal(first.body.xp, 8);

  // Reading twice never changes anything.
  const second = await b.api.get('/api/level');
  assert.equal(second.body.xp, first.body.xp);
  assert.equal(second.body.level, first.body.level);
});

test('level: crossing 100 XP broadcasts level_up (with title) to both partners', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await aSock.waitFor('welcome');
  await bSock.waitFor('welcome');

  // 7 done bucket items × 15 XP = 105 XP → level 2 (threshold 100).
  for (let i = 0; i < 7; i++) {
    const created = await a.api.post('/api/bucket', { json: { text: `dream ${i}` } });
    assert.equal(created.status, 201);
    const done = await a.api.patch(`/api/bucket/${created.body.item.id}`, { json: { done: true } });
    assert.equal(done.status, 200);
  }

  const aUp = await aSock.waitFor('level_up');
  const bUp = await bSock.waitFor('level_up');
  assert.equal(aUp.payload.level, 2);
  assert.deepEqual(aUp.payload.title, { de: 'Turteltauben', en: 'Lovebirds' });
  assert.ok(aUp.payload.xp >= 100);
  assert.equal(bUp.payload.level, 2);

  const level = await a.api.get('/api/level');
  assert.equal(level.body.level, 2);
  assert.equal(level.body.xp, 105);
  assert.equal(level.body.levelXp, 5); // 105 − 100
  assert.equal(level.body.nextLevelXp, 200); // L3 at 300 total
});

test('level: legacy couples (old + history) adopt their level silently on first contact', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a, coupleId } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  await aSock.waitFor('welcome');

  // Simulate a pre-3.0 couple: created a year ago, plenty of history,
  // no gamification state yet.
  const couple = app.store.data.couples[coupleId];
  couple.createdAt = new Date(Date.now() - 365 * 86_400_000).toISOString();
  couple.counters.messages = 500; // 1000 XP → level 5 retroactively

  // First 3.0 write: XP jumps 0 → >1000, but NO ceremony spam.
  await a.api.post('/api/touches', { json: { type: 'heartbeat' } });
  await aSock.assertNone('level_up');
  await aSock.assertNone('badge_unlocked');

  const level = await a.api.get('/api/level');
  assert.ok(level.body.level >= 5);

  // From now on advancement ceremonies fire normally again: more history
  // lands (600 XP worth of games) and the next write crosses into level 6.
  couple.counters.gamesPlayed = 40;
  await a.api.post('/api/touches', { json: { type: 'kiss' } });
  const up = await aSock.waitFor('level_up');
  assert.ok(up.payload.level >= 6);
});

// ---------------------------------------------------------------------------
// prestige chapters (post-level-10): titles never dead-end anymore

test('level: prestige chapters replay the title stems past level 10', () => {
  // Chapter I stays exactly as before — nothing changes below level 11.
  assert.deepEqual(titleForLevel(1), { de: 'Frisch verliebt', en: 'Freshly in love' });
  assert.deepEqual(titleForLevel(10), { de: 'Legendäres Duo', en: 'Legendary duo' });
  // Chapter II replays the stems with the chapter suffix.
  assert.deepEqual(titleForLevel(11), {
    de: 'Frisch verliebt · Kapitel II',
    en: 'Freshly in love · Chapter II',
  });
  assert.deepEqual(titleForLevel(20), {
    de: 'Legendäres Duo · Kapitel II',
    en: 'Legendary duo · Chapter II',
  });
  assert.deepEqual(titleForLevel(24), {
    de: 'Träumer-Duo · Kapitel III',
    en: 'Dreamy duo · Chapter III',
  });
  // Unbounded: any level resolves to a real title, never a clamp.
  assert.equal(chapterForLevel(10), 1);
  assert.equal(chapterForLevel(11), 2);
  assert.equal(chapterForLevel(37), 4);
  assert.equal(romanNumeral(2), 'II');
  assert.equal(romanNumeral(4), 'IV');
  assert.equal(romanNumeral(9), 'IX');
  assert.equal(romanNumeral(14), 'XIV');
  // The curve itself is untouched by prestige.
  assert.equal(levelForXP(4500), 10);
  assert.equal(levelForXP(5500), 11);
});

// ---------------------------------------------------------------------------
// badges

test('badges: catalog shape — 23 badges with progress, secrets flagged', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);

  const res = await a.api.get('/api/badges');
  assert.equal(res.status, 200);
  assert.equal(res.body.badges.length, 23);
  for (const badge of res.body.badges) {
    assert.equal(typeof badge.id, 'string');
    assert.equal(typeof badge.secret, 'boolean');
    assert.equal(badge.unlocked, false);
    assert.equal(badge.unlockedAt, null);
    assert.ok(badge.progress.target >= 1);
    assert.ok(badge.progress.current >= 0);
  }
  const secrets = res.body.badges.filter((b) => b.secret).map((b) => b.id);
  assert.deepEqual(secrets.sort(), ['duet_partners', 'early_birds', 'icon_gifted', 'night_owls']);
  // Long-arc streak badges (90/180/365 days) carry the reward economy
  // past the first weeks.
  const ids = res.body.badges.map((b) => b.id);
  for (const id of ['streak_quarter', 'streak_half_year', 'streak_year']) {
    assert.ok(ids.includes(id), `missing long-arc badge ${id}`);
  }
});

test('badges: first touch unlocks first_touch with badge_unlocked broadcast', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  await a.api.post('/api/touches', { json: { type: 'heartbeat' } });

  const frame = await bSock.waitFor('badge_unlocked', (m) => m.payload.badge.id === 'first_touch');
  assert.equal(frame.payload.badge.unlocked, true);
  assert.ok(frame.payload.badge.unlockedAt);

  const res = await a.api.get('/api/badges');
  const badge = res.body.badges.find((x) => x.id === 'first_touch');
  assert.equal(badge.unlocked, true);
  assert.deepEqual(badge.progress, { current: 1, target: 1 });
});

test('badges: never re-lock when the underlying value drops again', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);

  // Unlock bucket_10 (10 done items), then un-done them all.
  const ids = [];
  for (let i = 0; i < 10; i++) {
    const created = await a.api.post('/api/bucket', { json: { text: `item ${i}` } });
    ids.push(created.body.item.id);
    await a.api.patch(`/api/bucket/${created.body.item.id}`, { json: { done: true } });
  }
  let res = await a.api.get('/api/badges');
  assert.equal(res.body.badges.find((x) => x.id === 'bucket_10').unlocked, true);

  for (const id of ids) await a.api.patch(`/api/bucket/${id}`, { json: { done: false } });
  res = await a.api.get('/api/badges');
  const badge = res.body.badges.find((x) => x.id === 'bucket_10');
  assert.equal(badge.unlocked, true); // stays unlocked
  assert.equal(badge.progress.current, 0); // progress is honest though
});

// ---------------------------------------------------------------------------
// app-event XP (consumes src/events.js emissions from Agents A/B)

test('level: app events (e.g. need_sent) feed XP exactly once via the cursor', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);

  const before = (await a.api.get('/api/level')).body;

  // Agent A's need button emits `need_sent` (3 XP as app event).
  const need = await a.api.post('/api/needs', { json: { type: 'closeness' } });
  assert.equal(need.status, 201);

  const after = (await a.api.get('/api/level')).body;
  assert.equal(after.breakdown.appEvents - before.breakdown.appEvents, 3);

  // Re-reading must not double-count.
  const again = (await a.api.get('/api/level')).body;
  assert.equal(again.breakdown.appEvents, after.breakdown.appEvents);
});

// ---------------------------------------------------------------------------
// widget snapshot

test('widget snapshot: carries the relationship level field', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);

  const res = await a.api.get('/api/widget-snapshot');
  assert.equal(res.status, 200);
  assert.equal(res.body.level.level, 1);
  assert.deepEqual(res.body.level.title, { de: 'Frisch verliebt', en: 'Freshly in love' });
  assert.equal(typeof res.body.level.progress, 'number');
  assert.equal(typeof res.body.level.xp, 'number');
});

// ---------------------------------------------------------------------------
// onboarding quest

test('quest: seven steps flip as the couple does its first-week actions; finale pays 150 XP', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  await aSock.waitFor('welcome');
  const today = dateKeyDaysAgo(0);

  let quest = (await a.api.get('/api/quest')).body;
  assert.equal(quest.done, false);
  assert.equal(quest.isNewCouple, true);
  assert.equal(quest.steps.length, 7);
  assert.ok(quest.steps.every((s) => s.done === false));
  assert.equal(quest.bonusXp, 150);

  // 1 touch, 2 message, 3 daily (both), 4 photo, 5 canvas, 6 check-in (both), 7 game (wordle).
  await a.api.post('/api/touches', { json: { type: 'kiss' } });
  await a.api.post('/api/messages', { json: { type: 'text', text: 'first week!' } });
  await a.api.post(`/api/daily/${today}`, { json: { questionId: 1, text: 'you' } });
  await b.api.post(`/api/daily/${today}`, { json: { questionId: 1, text: 'you too' } });
  await a.api.post('/api/photos', { body: Buffer.from('jpeg'), headers: { 'content-type': 'image/jpeg' } });
  await a.api.post('/api/canvas/strokes', { json: { points: [[0.5, 0.5]] } });
  await a.api.post('/api/checkins', { json: { kind: 'morning' } });
  await b.api.post('/api/checkins', { json: { kind: 'night' } });

  quest = (await a.api.get('/api/quest')).body;
  assert.equal(quest.done, false);
  assert.equal(quest.steps.filter((s) => s.done).length, 6); // game still missing

  const grid = '🟩🟩🟩🟩🟩';
  await a.api.post(`/api/wordle/${today}`, { json: { rows: 1, win: true, grid, lang: 'de' } });

  const before = (await a.api.get('/api/level')).body.xp;
  quest = (await a.api.get('/api/quest')).body;
  assert.equal(quest.done, true);
  assert.ok(quest.completedAt);
  assert.ok(quest.steps.every((s) => s.done));

  // Finale: quest_completed broadcast + 150 bonus XP + quest badge.
  const frame = await aSock.waitFor('quest_completed');
  assert.equal(frame.payload.quest.done, true);
  const after = (await a.api.get('/api/level')).body;
  assert.equal(after.breakdown.quest, 150);
  assert.ok(after.xp >= before + 150);
  const badges = (await a.api.get('/api/badges')).body.badges;
  assert.equal(badges.find((x) => x.id === 'quest_complete').unlocked, true);
});

test('quest: isNewCouple turns false for couples older than 30 days', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a, coupleId } = await setupCouple(baseUrl);

  app.store.data.couples[coupleId].createdAt = new Date(Date.now() - 45 * 86_400_000).toISOString();
  const quest = (await a.api.get('/api/quest')).body;
  assert.equal(quest.isNewCouple, false);
  assert.equal(quest.done, false); // still trackable, just not pushed in UI
});

test('level/badges/quest require auth', async (t) => {
  const { baseUrl } = await makeApp(t);
  const anon = client(baseUrl);
  assert.equal((await anon.get('/api/level')).status, 401);
  assert.equal((await anon.get('/api/badges')).status, 401);
  assert.equal((await anon.get('/api/quest')).status, 401);
});
