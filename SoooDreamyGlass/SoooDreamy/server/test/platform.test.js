import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple, wsOpen, client } from './helpers.js';

// ---------------------------------------------------------------------------
// app-icon gifts (v3.0 Agent C)

test('icon gift: send → partner (and only partner) gets it, unwrap notifies the sender', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await aSock.waitFor('welcome');
  await bSock.waitFor('welcome');

  const sent = await a.api.post('/api/icongift', { json: { icon: 'sunset', note: 'für dich 🧡' } });
  assert.equal(sent.status, 201);
  assert.equal(sent.body.gift.icon, 'sunset');
  assert.equal(sent.body.gift.fromMemberId, a.memberId);
  assert.equal(sent.body.gift.openedAt, null);

  // Recipient is told live; the sender's own sockets stay quiet.
  const frame = await bSock.waitFor('icon_gift');
  assert.equal(frame.payload.gift.icon, 'sunset');
  await aSock.assertNone('icon_gift');

  // Pending gift is only visible to the recipient.
  assert.equal((await b.api.get('/api/icongift')).body.gift.icon, 'sunset');
  assert.equal((await a.api.get('/api/icongift')).body.gift, null);

  // Unwrap ceremony: marks opened, clears the pending slot, tells the sender.
  const opened = await b.api.post('/api/icongift/open');
  assert.equal(opened.status, 200);
  assert.ok(opened.body.gift.openedAt);
  const ack = await aSock.waitFor('icon_gift_opened');
  assert.equal(ack.payload.gift.icon, 'sunset');
  assert.equal((await b.api.get('/api/icongift')).body.gift, null);
  assert.equal((await b.api.post('/api/icongift/open')).status, 404);
});

test('icon gift: newest surprise wins; unlocks the secret icon_gifted badge', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  await a.api.post('/api/icongift', { json: { icon: 'mint' } });
  await a.api.post('/api/icongift', { json: { icon: 'midnight' } });
  assert.equal((await b.api.get('/api/icongift')).body.gift.icon, 'midnight');

  const badges = (await a.api.get('/api/badges')).body.badges;
  const badge = badges.find((x) => x.id === 'icon_gifted');
  assert.equal(badge.unlocked, true);
  assert.equal(badge.secret, true);
});

test('icon gift: v10 "aurora" completes the ten-icon family and is giftable', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  const sent = await a.api.post('/api/icongift', { json: { icon: 'aurora' } });
  assert.equal(sent.status, 201);
  assert.equal(sent.body.gift.icon, 'aurora');
  assert.equal((await b.api.get('/api/icongift')).body.gift.icon, 'aurora');
});

test('icon gift: validation — unknown icon 400, solo couple 409, auth required', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  assert.equal((await a.api.post('/api/icongift', { json: { icon: 'comic-sans' } })).status, 400);

  const anon = client(baseUrl);
  const solo = await anon.post('/api/couples', { json: { name: 'Solo', avatar: '🦄', color: '#AA66FF' } });
  const soloApi = client(baseUrl, solo.body.token);
  assert.equal((await soloApi.post('/api/icongift', { json: { icon: 'sunset' } })).status, 409);

  assert.equal((await anon.get('/api/icongift')).status, 401);
});

// ---------------------------------------------------------------------------
// haptic duet + live heartbeat

test('duet: start broadcasts duet_start with a future server-time startAt to BOTH phones', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await aSock.waitFor('welcome');
  await bSock.waitFor('welcome');

  const events = [
    { t: 0, i: 0.9, s: 0.4, d: 0 },
    { t: 0.4, i: 0.6, s: 0.6, d: 0.5 },
  ];
  const res = await a.api.post('/api/duet', { json: { name: 'Herzschlag', events } });
  assert.equal(res.status, 201);
  assert.equal(res.body.duet.startedBy, a.memberId);
  assert.ok(res.body.duet.startAtMs > res.body.duet.serverNowMs);
  assert.ok(res.body.duet.startAtMs - res.body.duet.serverNowMs >= 1000); // lead-in for sync

  const aFrame = await aSock.waitFor('duet_start');
  const bFrame = await bSock.waitFor('duet_start');
  assert.deepEqual(aFrame.payload.duet.events, events);
  assert.equal(aFrame.payload.duet.startAtMs, bFrame.payload.duet.startAtMs); // same instant

  // Playing a duet unlocks the secret duet_partners badge.
  const badges = (await b.api.get('/api/badges')).body.badges;
  assert.equal(badges.find((x) => x.id === 'duet_partners').unlocked, true);
});

test('duet: validation — events required, ranges enforced, max 64 events', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);

  assert.equal((await a.api.post('/api/duet', { json: {} })).status, 400);
  assert.equal((await a.api.post('/api/duet', { json: { events: [] } })).status, 400);
  assert.equal((await a.api.post('/api/duet', { json: { events: [{ t: 0, i: 1.5, s: 0.5 }] } })).status, 400);
  assert.equal((await a.api.post('/api/duet', { json: { events: [{ t: -1, i: 0.5, s: 0.5 }] } })).status, 400);
  assert.equal((await a.api.post('/api/duet', { json: { events: [{ t: 0, i: 0.5, s: 'x' }] } })).status, 400);
  const tooMany = Array.from({ length: 65 }, (_, k) => ({ t: k * 0.1, i: 0.5, s: 0.5 }));
  assert.equal((await a.api.post('/api/duet', { json: { events: tooMany } })).status, 400);
});

test('live heartbeat: WS heartbeat_tap relays to the partner only, intensity clamped', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await aSock.waitFor('welcome');
  await bSock.waitFor('welcome');

  aSock.send({ type: 'heartbeat_tap', payload: { intensity: 0.8 } });
  const tap = await bSock.waitFor('heartbeat_tap');
  assert.equal(tap.payload.memberId, a.memberId);
  assert.equal(tap.payload.intensity, 0.8);
  await aSock.assertNone('heartbeat_tap'); // no echo to the tapper

  aSock.send({ type: 'heartbeat_tap', payload: { intensity: 42 } });
  assert.equal((await bSock.waitFor('heartbeat_tap')).payload.intensity, 1); // clamped

  aSock.send({ type: 'heartbeat_tap', payload: {} });
  assert.equal((await bSock.waitFor('heartbeat_tap')).payload.intensity, 0.7); // default
});

test('clock sync: pong echoes the ping marker and carries server time', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  await aSock.waitFor('welcome');

  aSock.send({ type: 'ping', payload: { echo: 'sync-77' } });
  const pong = await aSock.waitFor('pong', (m) => m.payload.echo === 'sync-77');
  assert.ok(Math.abs(Date.parse(pong.ts) - Date.now()) < 5000); // usable clock source
});

// ---------------------------------------------------------------------------
// date night

test('date night: plan → both get datenight_update; future starts in anticipation', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const startsAt = new Date(Date.now() + 3 * 3_600_000).toISOString();
  const res = await a.api.post('/api/datenight', { json: { title: 'Pasta & Film', emoji: '🍝', startsAt } });
  assert.equal(res.status, 201);
  assert.equal(res.body.dateNight.phase, 'anticipation');
  assert.equal(res.body.dateNight.startsAt, startsAt);

  const frame = await bSock.waitFor('datenight_update');
  assert.equal(frame.payload.dateNight.title, 'Pasta & Film');
  assert.equal((await b.api.get('/api/datenight')).body.dateNight.id, res.body.dateNight.id);

  // A start in the past begins live right away.
  const past = await a.api.post('/api/datenight', {
    json: { startsAt: new Date(Date.now() - 60_000).toISOString() },
  });
  assert.equal(past.body.dateNight.phase, 'live');
});

test('date night: phase switching (Vorfreude → Los → Ausklang) + teardown', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  await aSock.waitFor('welcome');

  assert.equal((await a.api.post('/api/datenight/phase', { json: { phase: 'live' } })).status, 404);
  assert.equal((await a.api.del('/api/datenight')).status, 404);

  await a.api.post('/api/datenight', {
    json: { startsAt: new Date(Date.now() + 3_600_000).toISOString() },
  });
  await aSock.waitFor('datenight_update', (m) => m.payload.dateNight?.phase === 'anticipation');

  // Either partner may advance the phase (Live-Activity button).
  const live = await b.api.post('/api/datenight/phase', { json: { phase: 'live' } });
  assert.equal(live.body.dateNight.phase, 'live');
  await aSock.waitFor('datenight_update', (m) => m.payload.dateNight?.phase === 'live');
  assert.equal((await b.api.post('/api/datenight/phase', { json: { phase: 'brunch' } })).status, 400);

  const gone = await a.api.del('/api/datenight');
  assert.equal(gone.status, 200);
  await aSock.waitFor('datenight_update', (m) => m.payload.dateNight === null);
  assert.equal((await a.api.get('/api/datenight')).body.dateNight, null);
});

test('date night: validation — startsAt required/ISO/≤30 days out', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);

  assert.equal((await a.api.post('/api/datenight', { json: {} })).status, 400);
  assert.equal((await a.api.post('/api/datenight', { json: { startsAt: 'tonight' } })).status, 400);
  const tooFar = new Date(Date.now() + 40 * 86_400_000).toISOString();
  assert.equal((await a.api.post('/api/datenight', { json: { startsAt: tooFar } })).status, 400);
});
