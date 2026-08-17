import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple, wsOpen } from './helpers.js';

const HEARTBEAT = [
  { t: 0, i: 1, s: 0.3, d: 0 },
  { t: 0.18, i: 0.65, s: 0.2, d: 0 },
  { t: 0.75, i: 1, s: 0.3, d: 0 },
  { t: 0.93, i: 0.65, s: 0.2, d: 0.4 },
];

test('haptic pattern: save → library lists it newest-first, WS to both', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await aSock.waitFor('welcome');
  await bSock.waitFor('welcome');

  const res = await a.api.post('/api/haptics', {
    json: { name: 'Mein Herzschlag', emoji: '💓', events: HEARTBEAT },
  });
  assert.equal(res.status, 201);
  assert.match(res.body.pattern.id, /^hp_/);
  assert.equal(res.body.pattern.name, 'Mein Herzschlag');
  assert.equal(res.body.pattern.createdBy, a.memberId);
  assert.equal(res.body.pattern.sentCount, 0);
  assert.equal(res.body.pattern.events.length, 4);

  // Library is shared — both see it (creator gets the WS frame too).
  await aSock.waitFor('haptic_pattern_added');
  await bSock.waitFor('haptic_pattern_added');
  const second = await b.api.post('/api/haptics', {
    json: { name: 'Kicher-Tickle', events: [{ t: 0, i: 0.4, s: 0.9 }] },
  });
  assert.equal(second.status, 201);
  assert.equal(second.body.pattern.emoji, null);

  const list = await a.api.get('/api/haptics');
  assert.equal(list.status, 200);
  assert.deepEqual(
    list.body.patterns.map((p) => p.name),
    ['Kicher-Tickle', 'Mein Herzschlag'],
  );
});

test('haptic events are normalized: sorted by t, defaults filled, rounded to ms', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  const res = await a.api.post('/api/haptics', {
    json: {
      name: 'Unsortiert',
      events: [
        { t: 0.5004, i: 0.123456 },
        { t: 0.1, d: 1.25 },
      ],
    },
  });
  assert.equal(res.status, 201);
  const [first, second] = res.body.pattern.events;
  assert.equal(first.t, 0.1);
  assert.equal(first.i, 0.7); // default intensity
  assert.equal(first.s, 0.5); // default sharpness
  assert.equal(first.d, 1.25);
  assert.equal(second.t, 0.5); // rounded to ms
  assert.equal(second.i, 0.123);
});

test('haptic pattern validation: bad events / name / limits → 400', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);

  const empty = await a.api.post('/api/haptics', { json: { name: 'X', events: [] } });
  assert.equal(empty.status, 400);
  assert.equal(empty.body.error, 'invalid_pattern');

  const outOfRange = await a.api.post('/api/haptics', {
    json: { name: 'X', events: [{ t: 0, i: 1.5 }] },
  });
  assert.equal(outOfRange.status, 400);
  assert.equal(outOfRange.body.error, 'invalid_pattern');

  const tooLate = await a.api.post('/api/haptics', {
    json: { name: 'X', events: [{ t: 99 }] },
  });
  assert.equal(tooLate.status, 400);

  const tooMany = await a.api.post('/api/haptics', {
    json: { name: 'X', events: Array.from({ length: 129 }, (_, k) => ({ t: k * 0.01 })) },
  });
  assert.equal(tooMany.status, 400);
  assert.equal(tooMany.body.error, 'pattern_too_long');

  const noName = await a.api.post('/api/haptics', { json: { events: HEARTBEAT } });
  assert.equal(noName.status, 400);
});

test('send saved pattern: partner gets WS haptic, sender does not, sentCount grows', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const saved = await a.api.post('/api/haptics', {
    json: { name: 'Herzschlag', emoji: '💓', events: HEARTBEAT },
  });
  const aSock = await wsOpen(baseUrl, a.token, t);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await aSock.waitFor('welcome');
  await bSock.waitFor('welcome');

  const sent = await a.api.post(`/api/haptics/${saved.body.pattern.id}/send`);
  assert.equal(sent.status, 201);
  assert.match(sent.body.haptic.id, /^h_/);
  assert.equal(sent.body.haptic.patternId, saved.body.pattern.id);
  assert.equal(sent.body.haptic.senderId, a.memberId);
  assert.deepEqual(sent.body.haptic.events, saved.body.pattern.events);
  assert.equal(sent.body.pattern.sentCount, 1);

  const frame = await bSock.waitFor('haptic');
  assert.deepEqual(frame.payload.haptic, sent.body.haptic);
  await aSock.assertNone('haptic');

  const missing = await a.api.post('/api/haptics/hp_missing/send');
  assert.equal(missing.status, 404);
});

test('ad-hoc send without saving: relayed + lands in recent history', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const sent = await a.api.post('/api/haptics/send', {
    json: { emoji: '🌧️', events: [{ t: 0, i: 0.3, s: 0.8 }, { t: 0.2, i: 0.4, s: 0.7 }] },
  });
  assert.equal(sent.status, 201);
  assert.equal(sent.body.haptic.patternId, null);
  assert.equal(sent.body.haptic.name, null);

  await bSock.waitFor('haptic', (m) => m.payload.haptic.id === sent.body.haptic.id);

  // The library stays empty — but the send shows up in the replay history.
  const list = await a.api.get('/api/haptics');
  assert.equal(list.body.patterns.length, 0);
  const recent = await b.api.get('/api/haptics/recent');
  assert.equal(recent.status, 200);
  assert.equal(recent.body.haptics.length, 1);
  assert.equal(recent.body.haptics[0].id, sent.body.haptic.id);
});

test('rename/retag + delete are shared; unknown id → 404', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const saved = await a.api.post('/api/haptics', {
    json: { name: 'Alt', events: HEARTBEAT },
  });
  const patternId = saved.body.pattern.id;
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  // Partner (not the creator) renames it.
  const renamed = await b.api.patch(`/api/haptics/${patternId}`, {
    json: { name: 'Neu', emoji: '✨' },
  });
  assert.equal(renamed.status, 200);
  assert.equal(renamed.body.pattern.name, 'Neu');
  assert.equal(renamed.body.pattern.emoji, '✨');
  await bSock.waitFor('haptic_pattern_updated');

  // Partner deletes it.
  const deleted = await b.api.del(`/api/haptics/${patternId}`);
  assert.equal(deleted.status, 200);
  await bSock.waitFor('haptic_pattern_deleted', (m) => m.payload.id === patternId);
  assert.equal((await a.api.get('/api/haptics')).body.patterns.length, 0);

  assert.equal((await a.api.patch('/api/haptics/hp_x', { json: { name: 'X' } })).status, 404);
  assert.equal((await a.api.del('/api/haptics/hp_x')).status, 404);
});

test('library cap: pattern 61 → 413 too_many_patterns', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  for (let k = 0; k < 60; k++) {
    const res = await a.api.post('/api/haptics', {
      json: { name: `P${k}`, events: [{ t: 0 }] },
    });
    assert.equal(res.status, 201);
  }
  const overflow = await a.api.post('/api/haptics', {
    json: { name: 'P60', events: [{ t: 0 }] },
  });
  assert.equal(overflow.status, 413);
  assert.equal(overflow.body.error, 'too_many_patterns');
});

test('haptics survive restart (persisted in the store)', async (t) => {
  const { baseUrl, dataDir, close } = await makeApp(null);
  const { a, b } = await setupCouple(baseUrl);
  await a.api.post('/api/haptics', { json: { name: 'Bleibt', emoji: '💜', events: HEARTBEAT } });
  await a.api.post('/api/haptics/send', { json: { events: [{ t: 0 }] } });
  await close();

  const second = await makeApp(t, { dataDir });
  const rejoined = (await import('./helpers.js')).client(second.baseUrl, a.token);
  const list = await rejoined.get('/api/haptics');
  assert.equal(list.body.patterns.length, 1);
  assert.equal(list.body.patterns[0].name, 'Bleibt');
  const recent = await rejoined.get('/api/haptics/recent');
  assert.equal(recent.body.haptics.length, 1);
  void b;
});
