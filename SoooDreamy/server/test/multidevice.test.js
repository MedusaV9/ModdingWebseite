// Multi-device (Welle 1B): device link codes, the `origin` frame marker, and
// the touch/haptic self-echo to a member's OTHER devices. Contract lives in
// docs/API.md ("Multi-device sessions & fanout").
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { rm } from 'node:fs/promises';
import { RateLimiter } from '../src/security.js';
import { client, makeApp, setupCouple, wsOpen } from './helpers.js';

const LINK_CODE_RE = /^[A-HJ-NP-Z2-9]{8}$/;

/** Couple with explicit device identities so origin markers are assertable. */
async function setupDeviceCouple(baseUrl) {
  const anon = client(baseUrl);
  const created = await anon.post('/api/couples', {
    json: { name: 'Mia', avatar: '🦊', color: '#FF5C8A', deviceId: 'mia-iphone-0001', deviceName: 'Mias iPhone' },
  });
  assert.equal(created.status, 201);
  const joined = await anon.post('/api/couples/join', {
    json: { code: created.body.couple.code, name: 'Ben', avatar: '🐻', color: '#4A90D9', deviceId: 'ben-iphone-0001', deviceName: 'Bens iPhone' },
  });
  assert.equal(joined.status, 200);
  return {
    code: created.body.couple.code,
    coupleId: created.body.coupleId,
    a: {
      token: created.body.token,
      memberId: created.body.memberId,
      sessionId: created.body.sessionId,
      recoveryKey: created.body.recoveryKey,
      api: client(baseUrl, created.body.token),
    },
    b: {
      token: joined.body.token,
      memberId: joined.body.memberId,
      sessionId: joined.body.sessionId,
      api: client(baseUrl, joined.body.token),
    },
  };
}

/** Issues a link code as `who` and redeems it as a fresh device. */
async function linkDevice(baseUrl, who, deviceName, deviceId) {
  const issued = await who.api.post('/api/sessions/link-code');
  assert.equal(issued.status, 201);
  const linked = await client(baseUrl).post('/api/couples/link', {
    json: { code: issued.body.linkCode, deviceName, deviceId },
  });
  return { issued, linked };
}

test('link code happy path: second own device attaches, sessions list + device_linked converge', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const pair = await setupDeviceCouple(baseUrl);
  const iphoneSock = await wsOpen(baseUrl, pair.a.token, t);
  const partnerSock = await wsOpen(baseUrl, pair.b.token, t);
  await iphoneSock.waitFor('welcome');
  await partnerSock.waitFor('welcome');

  const issued = await pair.a.api.post('/api/sessions/link-code');
  assert.equal(issued.status, 201);
  assert.match(issued.body.linkCode, LINK_CODE_RE);
  assert.equal(issued.body.memberId, pair.a.memberId);
  const ttlMs = Date.parse(issued.body.expiresAt) - Date.parse(issued.body.createdAt);
  assert.ok(ttlMs > 9 * 60 * 1000 && ttlMs <= 10 * 60 * 1000, `unexpected TTL ${ttlMs}`);

  // Stored hashed like every other proof — the plaintext never enters the store.
  assert.ok(Object.keys(app.store.data.linkCodes).every((key) => /^[0-9a-f]{64}$/.test(key)));
  assert.equal(JSON.stringify(app.store.data).includes(issued.body.linkCode), false);

  const linked = await client(baseUrl).post('/api/couples/link', {
    json: { code: issued.body.linkCode.toLowerCase(), deviceName: 'Mias iPad', deviceId: 'mia-ipad-0001' },
  });
  assert.equal(linked.status, 200, JSON.stringify(linked.body));
  assert.equal(linked.body.linked, true);
  assert.equal(linked.body.memberId, pair.a.memberId, 'must land on the SAME member slot');
  assert.equal(linked.body.coupleId, pair.coupleId);
  assert.notEqual(linked.body.sessionId, pair.a.sessionId);
  assert.equal(linked.body.couple.members.length, 2, 'no third member is created');
  assert.equal(JSON.stringify(linked.body).includes('recoveryKey'), false, 'linking never rotates or leaks the recovery key');

  // The fresh token is a fully working device session of the same member.
  const iPad = client(baseUrl, linked.body.token);
  const me = await iPad.get('/api/couple');
  assert.equal(me.status, 200);
  assert.equal(me.body.me, pair.a.memberId);

  // The member's FIRST device hears about the newcomer (with origin of the
  // new session); the partner deliberately does not.
  const frame = await iphoneSock.waitFor('device_linked');
  assert.equal(frame.payload.memberId, pair.a.memberId);
  assert.equal(frame.payload.deviceName, 'Mias iPad');
  assert.equal(frame.payload.deviceId, 'mia-ipad-0001');
  assert.equal(frame.payload.sessionId, linked.body.sessionId);
  assert.ok(frame.payload.linkedAt);
  assert.deepEqual(frame.origin, {
    memberId: pair.a.memberId,
    deviceId: 'mia-ipad-0001',
    sessionSuffix: linked.body.sessionId.slice(-8),
  });
  await partnerSock.assertNone('device_linked');

  // The sessions list shows both devices, flags only the caller as current.
  const sessions = await pair.a.api.get('/api/sessions');
  assert.equal(sessions.status, 200);
  const byDevice = Object.fromEntries(sessions.body.sessions.map((s) => [s.deviceId, s]));
  assert.equal(sessions.body.sessions.length, 2);
  assert.equal(byDevice['mia-iphone-0001'].current, true);
  assert.equal(byDevice['mia-ipad-0001'].current, false);
  assert.equal(byDevice['mia-ipad-0001'].deviceName, 'Mias iPad');
});

test('link codes are single-use, expire after their TTL, and unknown codes are refused', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const pair = await setupDeviceCouple(baseUrl);

  const unknown = await client(baseUrl).post('/api/couples/link', { json: { code: 'AAAA2222' } });
  assert.equal(unknown.status, 403);
  assert.equal(unknown.body.error, 'bad_link_code');

  const { issued, linked } = await linkDevice(baseUrl, pair.a, 'Mias iPad', 'mia-ipad-0001');
  assert.equal(linked.status, 200);
  const replay = await client(baseUrl).post('/api/couples/link', {
    json: { code: issued.body.linkCode, deviceName: 'Eves Phone' },
  });
  assert.equal(replay.status, 409);
  assert.equal(replay.body.error, 'link_code_consumed');

  const expiring = await pair.a.api.post('/api/sessions/link-code');
  assert.equal(expiring.status, 201);
  for (const record of Object.values(app.store.data.linkCodes)) {
    if (!record.consumedAt) record.expiresAt = new Date(Date.now() - 1000).toISOString();
  }
  const expired = await client(baseUrl).post('/api/couples/link', {
    json: { code: expiring.body.linkCode },
  });
  assert.equal(expired.status, 403);
  assert.equal(expired.body.error, 'link_code_expired');
});

test('issuing a new link code replaces the previous unconsumed one', async (t) => {
  const { baseUrl } = await makeApp(t);
  const pair = await setupDeviceCouple(baseUrl);

  const first = await pair.a.api.post('/api/sessions/link-code');
  const second = await pair.a.api.post('/api/sessions/link-code');
  assert.equal(first.status, 201);
  assert.equal(second.status, 201);

  const staleRedeem = await client(baseUrl).post('/api/couples/link', {
    json: { code: first.body.linkCode },
  });
  assert.equal(staleRedeem.status, 403);
  assert.equal(staleRedeem.body.error, 'bad_link_code');

  const freshRedeem = await client(baseUrl).post('/api/couples/link', {
    json: { code: second.body.linkCode, deviceName: 'Mias iPad' },
  });
  assert.equal(freshRedeem.status, 200);
});

test('the 8-session cap answers 413 on issue AND redeem without burning the code', async (t) => {
  const { baseUrl } = await makeApp(t);
  const pair = await setupDeviceCouple(baseUrl);

  // Fill Mia's slot: 1 pairing session + 7 linked devices = 8 active.
  const linkedSessions = [];
  for (let i = 0; i < 7; i += 1) {
    const { linked } = await linkDevice(baseUrl, pair.a, `Gerät ${i}`, `mia-extra-${i}`);
    assert.equal(linked.status, 200, JSON.stringify(linked.body));
    linkedSessions.push(linked.body.sessionId);
  }

  const atCap = await pair.a.api.post('/api/sessions/link-code');
  assert.equal(atCap.status, 413);
  assert.equal(atCap.body.error, 'too_many_sessions');

  // Free one slot, mint a code, then refill the slot via recovery-key rejoin
  // (which has no cap gate) so the REDEEM hits a full member.
  assert.equal((await pair.a.api.post(`/api/sessions/${linkedSessions[0]}/revoke`)).status, 200);
  const code = await pair.a.api.post('/api/sessions/link-code');
  assert.equal(code.status, 201);
  const rejoined = await client(baseUrl).post('/api/couples/rejoin', {
    json: { code: pair.code, recoveryKey: pair.a.recoveryKey, deviceId: 'mia-rejoin-0001' },
  });
  assert.equal(rejoined.status, 200);

  const fullRedeem = await client(baseUrl).post('/api/couples/link', {
    json: { code: code.body.linkCode, deviceName: 'Einer zu viel' },
  });
  assert.equal(fullRedeem.status, 413);
  assert.equal(fullRedeem.body.error, 'too_many_sessions');

  // The cap failure did NOT consume the code: revoke a session and retry.
  assert.equal((await pair.a.api.post(`/api/sessions/${linkedSessions[1]}/revoke`)).status, 200);
  const retry = await client(baseUrl).post('/api/couples/link', {
    json: { code: code.body.linkCode, deviceName: 'Jetzt passt es' },
  });
  assert.equal(retry.status, 200, JSON.stringify(retry.body));

  // The pairing session survived every ceiling eviction: retained dead
  // records must be evicted before live sessions.
  assert.equal((await pair.a.api.get('/api/couple')).status, 200);
});

test('link endpoints are rate-limited per IP', async (t) => {
  const issueLimited = await makeApp(t, {
    rateLimiter: new RateLimiter({ policies: { linkCodeCreate: { limit: 1, windowMs: 60_000 } } }),
  });
  const pairA = await setupDeviceCouple(issueLimited.baseUrl);
  assert.equal((await pairA.a.api.post('/api/sessions/link-code')).status, 201);
  const throttledIssue = await pairA.a.api.post('/api/sessions/link-code');
  assert.equal(throttledIssue.status, 429);
  assert.equal(throttledIssue.body.error, 'rate_limited');
  assert.equal(throttledIssue.headers.get('retry-after'), '60');

  const redeemLimited = await makeApp(t, {
    rateLimiter: new RateLimiter({ policies: { coupleLink: { limit: 1, windowMs: 60_000 } } }),
  });
  await setupDeviceCouple(redeemLimited.baseUrl);
  const anon = client(redeemLimited.baseUrl);
  assert.equal((await anon.post('/api/couples/link', { json: { code: 'AAAA2222' } })).status, 403);
  const throttledRedeem = await anon.post('/api/couples/link', { json: { code: 'AAAA2222' } });
  assert.equal(throttledRedeem.status, 429);
  assert.equal(throttledRedeem.body.error, 'rate_limited');
});

test('?format=qr renders the sooodreamy://link deep link as SVG (server override validated)', async (t) => {
  const { baseUrl } = await makeApp(t);
  const pair = await setupDeviceCouple(baseUrl);

  const qr = await pair.a.api.post('/api/sessions/link-code?format=qr', {
    json: { server: 'https://couple.example.net/' },
  });
  assert.equal(qr.status, 201);
  assert.equal(qr.body.server, 'https://couple.example.net');
  assert.equal(
    qr.body.deepLink,
    `sooodreamy://link?server=${encodeURIComponent('https://couple.example.net')}&code=${encodeURIComponent(qr.body.linkCode)}`,
  );
  assert.match(qr.body.svg, /^<svg /);

  // Without an override the request host is used.
  const defaulted = await pair.a.api.post('/api/sessions/link-code?format=qr');
  assert.equal(defaulted.status, 201);
  assert.equal(defaulted.body.server, baseUrl);

  const badServer = await pair.a.api.post('/api/sessions/link-code?format=qr', {
    json: { server: 'ftp://nope' },
  });
  assert.equal(badServer.status, 400);
  assert.equal(badServer.body.error, 'bad_server_url');

  // Without ?format=qr no QR material is produced.
  const plain = await pair.a.api.post('/api/sessions/link-code');
  assert.equal(plain.status, 201);
  assert.equal(plain.body.svg, undefined);
  assert.equal(plain.body.deepLink, undefined);
});

test('link codes survive a restart (hashed in the manifest) and die with a partner replace', async (t) => {
  // Restart round-trip: the digest index persists and still redeems.
  const first = await makeApp(null);
  const pair = await setupDeviceCouple(first.baseUrl);
  const issued = await pair.a.api.post('/api/sessions/link-code');
  assert.equal(issued.status, 201);
  await first.close();

  const reopened = await makeApp(t, { dataDir: first.dataDir });
  t.after(() => rm(first.dataDir, { recursive: true, force: true }));
  const linked = await client(reopened.baseUrl).post('/api/couples/link', {
    json: { code: issued.body.linkCode, deviceName: 'Nach dem Neustart' },
  });
  assert.equal(linked.status, 200, JSON.stringify(linked.body));

  // Partner replace voids the replaced slot's pending link code.
  const second = await makeApp(t);
  const couple = await setupDeviceCouple(second.baseUrl);
  const pending = await couple.b.api.post('/api/sessions/link-code');
  assert.equal(pending.status, 201);
  const replace = await couple.a.api.post('/api/couples/replace-partner');
  assert.equal(replace.status, 201);
  const replaced = await client(second.baseUrl).post('/api/couples/rejoin', {
    json: { code: couple.code, replaceCode: replace.body.replaceCode, deviceId: 'ben-new-phone' },
  });
  assert.equal(replaced.status, 200);
  const dead = await client(second.baseUrl).post('/api/couples/link', {
    json: { code: pending.body.linkCode },
  });
  assert.equal(dead.status, 403);
  assert.equal(dead.body.error, 'bad_link_code');
});

test('REST broadcasts carry the caller origin {memberId, deviceId, sessionSuffix}', async (t) => {
  const { baseUrl } = await makeApp(t);
  const pair = await setupDeviceCouple(baseUrl);
  const partnerSock = await wsOpen(baseUrl, pair.b.token, t);
  await partnerSock.waitFor('welcome');

  const sent = await pair.a.api.post('/api/messages', { json: { type: 'text', text: 'origin check' } });
  assert.equal(sent.status, 201);
  const message = await partnerSock.waitFor('message');
  assert.deepEqual(message.origin, {
    memberId: pair.a.memberId,
    deviceId: 'mia-iphone-0001',
    sessionSuffix: pair.a.sessionId.slice(-8),
  });
  assert.equal(JSON.stringify(message).includes(pair.a.token), false, 'origin must never leak bearer material');

  // System frames stay unmarked.
  const welcomeless = await wsOpen(baseUrl, pair.a.token, t);
  const welcome = await welcomeless.waitFor('welcome');
  assert.equal(welcome.origin, undefined);
});

test('typing relay stays partner-only but carries the per-device origin', async (t) => {
  const { baseUrl } = await makeApp(t);
  const pair = await setupDeviceCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, pair.a.token, t);
  const bSock = await wsOpen(baseUrl, pair.b.token, t);
  await aSock.waitFor('welcome');
  await bSock.waitFor('welcome');

  aSock.send({ type: 'typing', payload: { isTyping: true } });
  const frame = await bSock.waitFor('typing');
  assert.deepEqual(frame.payload, { memberId: pair.a.memberId, isTyping: true });
  assert.deepEqual(frame.origin, {
    memberId: pair.a.memberId,
    deviceId: 'mia-iphone-0001',
    sessionSuffix: pair.a.sessionId.slice(-8),
  });
  await aSock.assertNone('typing');
});

test('touch and haptic self-echo: partner + own OTHER device converge, calling session stays silent', async (t) => {
  const { baseUrl } = await makeApp(t);
  const pair = await setupDeviceCouple(baseUrl);
  const { linked } = await linkDevice(baseUrl, pair.a, 'Mias iPad', 'mia-ipad-0001');
  assert.equal(linked.status, 200);

  const iphoneSock = await wsOpen(baseUrl, pair.a.token, t); // calling session
  const ipadSock = await wsOpen(baseUrl, linked.body.token, t); // own second device
  const partnerSock = await wsOpen(baseUrl, pair.b.token, t);
  await iphoneSock.waitFor('welcome');
  await ipadSock.waitFor('welcome');
  await partnerSock.waitFor('welcome');

  const touch = await pair.a.api.post('/api/touches', { json: { type: 'kiss' } });
  assert.equal(touch.status, 201);
  const expectedOrigin = {
    memberId: pair.a.memberId,
    deviceId: 'mia-iphone-0001',
    sessionSuffix: pair.a.sessionId.slice(-8),
  };
  const partnerTouch = await partnerSock.waitFor('touch');
  assert.deepEqual(partnerTouch.payload.touch, touch.body.touch);
  assert.deepEqual(partnerTouch.origin, expectedOrigin);
  const ipadTouch = await ipadSock.waitFor('touch');
  assert.deepEqual(ipadTouch.payload.touch, touch.body.touch);
  assert.deepEqual(ipadTouch.origin, expectedOrigin);
  await iphoneSock.assertNone('touch');

  const haptic = await pair.a.api.post('/api/haptics/send', {
    json: { name: 'Puls', events: [{ t: 0, i: 0.8 }] },
  });
  assert.equal(haptic.status, 201);
  const partnerHaptic = await partnerSock.waitFor('haptic');
  assert.deepEqual(partnerHaptic.payload.haptic, haptic.body.haptic);
  assert.deepEqual(partnerHaptic.origin, expectedOrigin);
  const ipadHaptic = await ipadSock.waitFor('haptic');
  assert.deepEqual(ipadHaptic.payload.haptic, haptic.body.haptic);
  assert.deepEqual(ipadHaptic.origin, expectedOrigin);
  await iphoneSock.assertNone('haptic');

  // The iPad acting makes the roles swap: now the iPhone gets the echo.
  const iPadApi = client(baseUrl, linked.body.token);
  const fromIpad = await iPadApi.post('/api/touches', { json: { type: 'hug' } });
  assert.equal(fromIpad.status, 201);
  const echoed = await iphoneSock.waitFor('touch');
  assert.deepEqual(echoed.origin, {
    memberId: pair.a.memberId,
    deviceId: 'mia-ipad-0001',
    sessionSuffix: linked.body.sessionId.slice(-8),
  });
  await partnerSock.waitFor('touch');
  await ipadSock.assertNone('touch');
});
