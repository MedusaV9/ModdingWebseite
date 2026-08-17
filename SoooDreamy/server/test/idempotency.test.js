// Sync contract a (FX-S) — moment senders are exactly-once: POST /api/touches,
// POST /api/pulses and POST /api/hugs accept a stable `clientOperationId`
// (outbox retry id). The dedup runs per couple+member BEFORE persistence/
// broadcast/push (for pulses: BEFORE the cooldown check) and the duplicate
// answer is `200 {duplicate:true}` with the ORIGINAL resource — retained for
// 24 h, independent of the capped source lists.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple, wsOpen } from './helpers.js';

test('EVAL repro: double POST /api/touches with the same clientOperationId creates ONE touch', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const first = await a.api.post('/api/touches', { json: { type: 'heartbeat', clientOperationId: 'op-touch-1' } });
  assert.equal(first.status, 201);
  await bSock.waitFor('touch');

  // The outbox retry (response lost) — same operation id, NOT a second moment.
  const retry = await a.api.post('/api/touches', { json: { type: 'heartbeat', clientOperationId: 'op-touch-1' } });
  assert.equal(retry.status, 200);
  assert.equal(retry.body.duplicate, true);
  assert.deepEqual(retry.body.touch, first.body.touch);

  const recent = await a.api.get('/api/touches/recent');
  assert.equal(recent.body.touches.length, 1);
  // Neither a second broadcast nor a second counter bump happened.
  await bSock.assertNone('touch');
  const stats = await a.api.get('/api/stats');
  assert.equal(stats.body.touchesSent.total, 1);
});

test('touches without clientOperationId keep the old behavior (two posts, two moments)', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  assert.equal((await a.api.post('/api/touches', { json: { type: 'kiss' } })).status, 201);
  assert.equal((await a.api.post('/api/touches', { json: { type: 'kiss' } })).status, 201);
  assert.equal((await a.api.get('/api/touches/recent')).body.touches.length, 2);
});

test('touch dedup is per member: the partner may reuse the same operation id', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  assert.equal((await a.api.post('/api/touches', { json: { type: 'hug', clientOperationId: 'shared-op' } })).status, 201);
  assert.equal((await b.api.post('/api/touches', { json: { type: 'hug', clientOperationId: 'shared-op' } })).status, 201);
  assert.equal((await a.api.get('/api/touches/recent')).body.touches.length, 2);
});

test('touch duplicate returns the ORIGINAL resource even after the capped list rolled it off', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  const first = await a.api.post('/api/touches', { json: { type: 'tickle', clientOperationId: 'op-rolled-off' } });
  assert.equal(first.status, 201);
  // Simulate the 500-cap having evicted the touch from the history.
  const couple = Object.values(app.store.data.couples)[0];
  couple.touches = [];
  const retry = await a.api.post('/api/touches', { json: { type: 'tickle', clientOperationId: 'op-rolled-off' } });
  assert.equal(retry.status, 200);
  assert.equal(retry.body.duplicate, true);
  assert.deepEqual(retry.body.touch, first.body.touch);
});

test('EVAL repro: pulse retry dedups BEFORE the cooldown — no misleading 429 too_soon', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  const first = await a.api.post('/api/pulses', { json: { kind: 'thinking', clientOperationId: 'op-pulse-1' } });
  assert.equal(first.status, 201);

  // Retry within the 30 s cooldown window: WITHOUT the dedup this answered
  // 429 too_soon (or worse, created a second pulse after the window).
  const retry = await a.api.post('/api/pulses', { json: { kind: 'thinking', clientOperationId: 'op-pulse-1' } });
  assert.equal(retry.status, 200);
  assert.equal(retry.body.duplicate, true);
  assert.deepEqual(retry.body.pulse, first.body.pulse);

  // The partner still has exactly ONE unfelt pulse.
  assert.equal((await b.api.get('/api/pulses')).body.pulses.length, 1);

  // A genuinely NEW pulse inside the cooldown still earns the honest 429.
  const fresh = await a.api.post('/api/pulses', { json: { kind: 'heartbeat', clientOperationId: 'op-pulse-2' } });
  assert.equal(fresh.status, 429);
  assert.equal(fresh.body.error, 'too_soon');
});

test('hugs (same moment-sender class) dedup on clientOperationId too', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  const first = await a.api.post('/api/hugs', { json: { note: 'gute nacht', clientOperationId: 'op-hug-1' } });
  assert.equal(first.status, 201);
  const retry = await a.api.post('/api/hugs', { json: { note: 'gute nacht', clientOperationId: 'op-hug-1' } });
  assert.equal(retry.status, 200);
  assert.equal(retry.body.duplicate, true);
  assert.deepEqual(retry.body.hug, first.body.hug);
  assert.equal((await a.api.get('/api/hugs')).body.hugs.length, 1);
});

test('EVAL repro: >2000 valid ops never evict a fresh entry — retry stays a duplicate', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);

  // The first (oldest) remembered operation — the one the old 2000 soft cap
  // used to sacrifice first.
  const first = await a.api.post('/api/touches', { json: { type: 'kiss', clientOperationId: 'op-stress-0' } });
  assert.equal(first.status, 201);

  // Simulate a stress burst well past the old cap: 2 200 remembered VALID
  // entries, all inside the 24 h window (seeded directly — 2 200 real HTTP
  // posts would only test the rate limiter). Timestamps are strictly newer
  // than op-stress-0 so IT is the eviction candidate.
  const couple = Object.values(app.store.data.couples)[0];
  const memberId = Object.keys(couple.clientOperations)[0].split('|')[0];
  const base = Date.now() - 60 * 60 * 1000;
  for (let i = 1; i <= 2_200; i++) {
    couple.clientOperations[`${memberId}|touch|touch|op-stress-${i}`] = new Date(base + i).toISOString();
  }

  // One more real write triggers remember()'s pruning pass …
  assert.equal((await a.api.post('/api/touches', { json: { type: 'hug', clientOperationId: 'op-stress-live' } })).status, 201);
  assert.ok(Object.keys(couple.clientOperations).length > 2_000,
    'valid entries beyond the old 2000 cap must survive');

  // … and the retry of the OLDEST valid operation still answers duplicate,
  // not 201 (the exactly-once promise holds for every entry in the window).
  const retry = await a.api.post('/api/touches', { json: { type: 'kiss', clientOperationId: 'op-stress-0' } });
  assert.equal(retry.status, 200);
  assert.equal(retry.body.duplicate, true);
  assert.deepEqual(retry.body.touch, first.body.touch);
});

test('emergency valve: only past 20000 entries are the oldest VALID ones sacrificed', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  assert.equal((await a.api.post('/api/touches', { json: { type: 'kiss', clientOperationId: 'op-oldest' } })).status, 201);

  const couple = Object.values(app.store.data.couples)[0];
  const memberId = Object.keys(couple.clientOperations)[0].split('|')[0];
  const oldestKey = Object.keys(couple.clientOperations).find((k) => k.endsWith('|op-oldest'));
  // Age the oldest entry (still valid, 2 h old) below 20 100 newer ones.
  couple.clientOperations[oldestKey].at = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString();
  const base = Date.now() - 60 * 60 * 1000;
  for (let i = 1; i <= 20_100; i++) {
    couple.clientOperations[`${memberId}|touch|touch|op-flood-${i}`] = new Date(base + i).toISOString();
  }

  assert.equal((await a.api.post('/api/touches', { json: { type: 'hug', clientOperationId: 'op-flood-live' } })).status, 201);
  const size = Object.keys(couple.clientOperations).length;
  assert.ok(size <= 20_000, `the hard limit must bound the map (got ${size})`);
  // The oldest valid entry was the sacrifice — the newest ones survived.
  assert.equal(couple.clientOperations[oldestKey], undefined);
  assert.ok(Object.keys(couple.clientOperations).some((k) => k.endsWith('|op-flood-live')));
});

test('dedup entries live 24 h — expired ones are pruned and stop deduplicating', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  assert.equal((await a.api.post('/api/touches', { json: { type: 'kiss', clientOperationId: 'op-old' } })).status, 201);

  // Rewind the stored entry beyond the 24 h retention window.
  const couple = Object.values(app.store.data.couples)[0];
  const key = Object.keys(couple.clientOperations).find((k) => k.endsWith('|op-old'));
  assert.ok(key, 'the operation must be remembered');
  couple.clientOperations[key].at = new Date(Date.now() - 25 * 60 * 60 * 1000).toISOString();

  // Any later remember() prunes the expired entry …
  assert.equal((await a.api.post('/api/touches', { json: { type: 'missyou', clientOperationId: 'op-new' } })).status, 201);
  assert.equal(couple.clientOperations[key], undefined);

  // … so the ancient id creates a NEW touch (retention is 24 h, not forever).
  assert.equal((await a.api.post('/api/touches', { json: { type: 'kiss', clientOperationId: 'op-old' } })).status, 201);
});
