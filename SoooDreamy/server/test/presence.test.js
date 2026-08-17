import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { makeApp, setupCouple, client, wsOpen } from './helpers.js';
import { PRESENCE_LIMITS } from '../src/presence.js';

// ---------------------------------------------------------------------------
// presence mode (focus / sleep)

test('presence mode: validation', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);

  const badMode = await a.api.put('/api/presence', { json: { mode: 'party' } });
  assert.equal(badMode.status, 400);
  assert.equal(badMode.body.error, 'invalid_type');

  const badMinutes = await a.api.put('/api/presence', { json: { mode: 'focus', minutes: 2 } });
  assert.equal(badMinutes.status, 400);
  assert.equal(badMinutes.body.error, 'bad_minutes');

  const tooLong = await a.api.put('/api/presence', {
    json: { mode: 'focus', minutes: PRESENCE_LIMITS.maxMinutes + 1 },
  });
  assert.equal(tooLong.status, 400);

  const fractional = await a.api.put('/api/presence', { json: { mode: 'sleep', minutes: 7.5 } });
  assert.equal(fractional.status, 400);

  const noteTooLong = await a.api.put('/api/presence', {
    json: { mode: 'focus', note: 'x'.repeat(PRESENCE_LIMITS.note + 1) },
  });
  assert.equal(noteTooLong.status, 400);

  const unauthed = await client(baseUrl).put('/api/presence', { json: { mode: 'focus' } });
  assert.equal(unauthed.status, 401);
});

test('presence mode: partner sees it on the couple and live via WS', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const wsB = await wsOpen(baseUrl, b.token, t);

  const set = await a.api.put('/api/presence', {
    json: { mode: 'focus', note: 'Deep Work bis 17 Uhr', minutes: 90 },
  });
  assert.equal(set.status, 200);
  assert.equal(set.body.presence.mode, 'focus');
  assert.equal(set.body.presence.note, 'Deep Work bis 17 Uhr');
  assert.ok(set.body.presence.until, 'minutes → until timestamp');
  assert.ok(set.body.presence.setAt);

  const frame = await wsB.waitFor('presence_mode', (m) => m.payload.memberId === a.memberId);
  assert.equal(frame.payload.presence.mode, 'focus');

  const couple = await b.api.get('/api/couple');
  const partnerA = couple.body.couple.members.find((m) => m.id === a.memberId);
  assert.equal(partnerA.presence.mode, 'focus');
  assert.equal(partnerA.presence.note, 'Deep Work bis 17 Uhr');

  // Without minutes, the mode stays until cleared.
  const openEnd = await a.api.put('/api/presence', { json: { mode: 'sleep' } });
  assert.equal(openEnd.status, 200);
  assert.equal(openEnd.body.presence.until, null);
  assert.equal(openEnd.body.presence.note, null);

  const cleared = await a.api.del('/api/presence');
  assert.equal(cleared.status, 200);
  const clearFrame = await wsB.waitFor('presence_mode',
    (m) => m.payload.memberId === a.memberId && m.payload.presence === null);
  assert.equal(clearFrame.payload.presence, null);

  const after = await b.api.get('/api/couple');
  assert.equal(after.body.couple.members.find((m) => m.id === a.memberId).presence, null);
});

test('presence mode: lazily expires once `until` passed', async (t) => {
  const { app, baseUrl } = await makeApp(t);
  const { coupleId, a, b } = await setupCouple(baseUrl);

  await a.api.put('/api/presence', { json: { mode: 'sleep', minutes: 30 } });

  // Rewind the expiry into the past — no timers involved, the read decides.
  const couple = app.store.data.couples[coupleId];
  const memberA = couple.members.find((m) => m.id === a.memberId);
  memberA.presence.until = new Date(Date.now() - 1000).toISOString();
  app.store.markDirty();

  const view = await b.api.get('/api/couple');
  assert.equal(view.body.couple.members.find((m) => m.id === a.memberId).presence, null);
});

// ---------------------------------------------------------------------------
// thinking-of-you pulses

test('pulses: send → partner feels it live and finds it queued', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const wsA = await wsOpen(baseUrl, a.token, t);
  const wsB = await wsOpen(baseUrl, b.token, t);

  const badKind = await a.api.post('/api/pulses', { json: { kind: 'poke' } });
  assert.equal(badKind.status, 400);

  const sent = await a.api.post('/api/pulses', { json: { kind: 'thinking' } });
  assert.equal(sent.status, 201);
  assert.equal(sent.body.pulse.kind, 'thinking');
  assert.equal(sent.body.pulse.senderId, a.memberId);
  assert.equal(sent.body.pulse.feltAt, null);

  // Partner gets the live frame; the sender must NOT (no echo).
  const frame = await wsB.waitFor('pulse', (m) => m.payload.pulse.id === sent.body.pulse.id);
  assert.equal(frame.payload.pulse.kind, 'thinking');
  await wsA.assertNone('pulse');

  // Queued for the partner, invisible to the sender (it is FOR the partner).
  const forB = await b.api.get('/api/pulses');
  assert.equal(forB.body.pulses.length, 1);
  assert.equal(forB.body.pulses[0].id, sent.body.pulse.id);
  const forA = await a.api.get('/api/pulses');
  assert.equal(forA.body.pulses.length, 0);
});

test('pulses: 30s cooldown per sender — partner can still answer instantly', async (t) => {
  const { app, baseUrl } = await makeApp(t);
  const { coupleId, a, b } = await setupCouple(baseUrl);

  const first = await a.api.post('/api/pulses', { json: { kind: 'heartbeat' } });
  assert.equal(first.status, 201);

  const tooSoon = await a.api.post('/api/pulses', { json: { kind: 'hug' } });
  assert.equal(tooSoon.status, 429);
  assert.equal(tooSoon.body.error, 'too_soon');

  // The PARTNER is not throttled by the sender's cooldown.
  const answer = await b.api.post('/api/pulses', { json: { kind: 'heartbeat' } });
  assert.equal(answer.status, 201);

  // Rewind the sender's last pulse → sending works again.
  const couple = app.store.data.couples[coupleId];
  const mine = couple.pulses.filter((p) => p.senderId === a.memberId);
  mine[mine.length - 1].createdAt = new Date(Date.now() - 31_000).toISOString();
  const again = await a.api.post('/api/pulses', { json: { kind: 'goodnight' } });
  assert.equal(again.status, 201);
});

test('pulses: seen marks all mine as felt and tells the sender', async (t) => {
  const { app, baseUrl } = await makeApp(t);
  const { coupleId, a, b } = await setupCouple(baseUrl);
  const wsA = await wsOpen(baseUrl, a.token, t);

  const p1 = await a.api.post('/api/pulses', { json: { kind: 'thinking' } });
  // Skip the cooldown for the second pulse.
  const couple = app.store.data.couples[coupleId];
  couple.pulses.find((p) => p.id === p1.body.pulse.id).createdAt =
    new Date(Date.now() - 60_000).toISOString();
  const p2 = await a.api.post('/api/pulses', { json: { kind: 'hug' } });
  assert.equal(p2.status, 201);

  const seen = await b.api.post('/api/pulses/seen');
  assert.equal(seen.status, 200);
  assert.equal(seen.body.count, 2);

  // Sender learns their pulses reached a heart.
  const felt = await wsA.waitFor('pulse_felt');
  assert.equal(felt.payload.ids.length, 2);
  assert.ok(felt.payload.ids.includes(p1.body.pulse.id));
  assert.ok(felt.payload.ids.includes(p2.body.pulse.id));

  // Queue is now empty; a second `seen` is a harmless no-op.
  const forB = await b.api.get('/api/pulses');
  assert.equal(forB.body.pulses.length, 0);
  const secondSeen = await b.api.post('/api/pulses/seen');
  assert.equal(secondSeen.body.count, 0);
});

test('pulses: queue is capped and couples are isolated', async (t) => {
  const { app, baseUrl } = await makeApp(t);
  const { coupleId, a, b } = await setupCouple(baseUrl);
  const other = await setupCouple(baseUrl);

  // Fill way past the cap by writing directly (the API would need cooldowns).
  const couple = app.store.data.couples[coupleId];
  couple.pulses = [];
  for (let i = 0; i < PRESENCE_LIMITS.pulsesKept + 10; i++) {
    couple.pulses.push({
      id: `pl_seed${i}`, kind: 'thinking', senderId: b.memberId,
      createdAt: new Date(Date.now() - (200 - i) * 60_000).toISOString(), feltAt: null,
    });
  }
  const sent = await b.api.post('/api/pulses', { json: { kind: 'hug' } });
  assert.equal(sent.status, 201);
  assert.equal(couple.pulses.length, PRESENCE_LIMITS.pulsesKept);
  // Oldest were dropped, the fresh one is last.
  assert.equal(couple.pulses[couple.pulses.length - 1].id, sent.body.pulse.id);
  assert.equal(couple.pulses[0].id, 'pl_seed11');

  // The other couple sees none of this.
  const foreign = await other.a.api.get('/api/pulses');
  assert.equal(foreign.body.pulses.length, 0);
});

// ---------------------------------------------------------------------------
// persistence

test('presence and unfelt pulses survive a restart with the same DATA_DIR', async (t) => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), 'sooodreamy-presence-'));

  const first = await makeApp(t, { dataDir });
  const { a, b } = await setupCouple(first.baseUrl);
  await a.api.put('/api/presence', { json: { mode: 'focus', note: 'Bleibt', minutes: 600 } });
  await a.api.post('/api/pulses', { json: { kind: 'goodnight' } });
  await first.close();

  const second = await makeApp(t, { dataDir });
  // Registered after makeApp so the rm runs after the app's close hook
  // (after-hooks are FIFO — see the note in corrupt_store.test.js).
  t.after(() => rm(dataDir, { recursive: true, force: true }));
  const bApi = client(second.baseUrl, b.token);
  const couple = await bApi.get('/api/couple');
  const memberA = couple.body.couple.members.find((m) => m.id === a.memberId);
  assert.equal(memberA.presence.mode, 'focus');
  assert.equal(memberA.presence.note, 'Bleibt');

  const pulses = await bApi.get('/api/pulses');
  assert.equal(pulses.body.pulses.length, 1);
  assert.equal(pulses.body.pulses[0].kind, 'goodnight');
});
