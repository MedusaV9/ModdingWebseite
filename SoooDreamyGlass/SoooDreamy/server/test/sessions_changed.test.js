// Sync contract d + g (FX-S) — the eval battery's find: rejoin/replace/
// rotate/revoke only informed the PARTNER, so the member's own open device
// manager went stale. Every session lifecycle event now also sends a
// `sessions_changed` WS frame to ALL devices of the AFFECTED member:
//   {memberId, reason: linked|rejoined|replaced|rotated|revoked, sessionId,
//    deviceName}
// and revoked sessions close their sockets with the UNIQUE terminal code
// 4001 (frame first, close second — the dying device hears why).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { client, makeApp, setupCouple, wsOpen } from './helpers.js';

/** Couple where the raw pairing responses (incl. recovery keys) are kept. */
async function setupRecoverableCouple(baseUrl) {
  const anon = client(baseUrl);
  const created = await anon.post('/api/couples', { json: { name: 'Mia', avatar: '🦊', color: '#FF5C8A' } });
  assert.equal(created.status, 201);
  const code = created.body.couple.code;
  const joined = await anon.post('/api/couples/join', { json: { code, name: 'Ben', avatar: '🐻', color: '#4A90D9' } });
  assert.equal(joined.status, 200);
  return {
    code,
    a: {
      ...created.body,
      memberId: created.body.memberId,
      api: client(baseUrl, created.body.token),
    },
    b: {
      ...joined.body,
      memberId: joined.body.memberId,
      api: client(baseUrl, joined.body.token),
    },
  };
}

async function linkDevice(baseUrl, who, deviceName, deviceId) {
  const issued = await who.api.post('/api/sessions/link-code');
  assert.equal(issued.status, 201);
  const linked = await client(baseUrl).post('/api/couples/link', {
    json: { code: issued.body.linkCode, deviceName, deviceId },
  });
  assert.equal(linked.status, 200, JSON.stringify(linked.body));
  return linked.body;
}

/** Resolves with the WS close code of one open test socket. */
function closeCodeOf(conn) {
  return new Promise((resolve) => conn.ws.once('close', (code) => resolve(code)));
}

test('linking a device sends sessions_changed(linked) to the member (partner hears nothing)', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const phoneSock = await wsOpen(baseUrl, a.token, t);
  const partnerSock = await wsOpen(baseUrl, b.token, t);
  await phoneSock.waitFor('welcome');
  await partnerSock.waitFor('welcome');

  const linked = await linkDevice(baseUrl, a, 'Mias iPad', 'mia-ipad-0001');

  // The richer device_linked stays for old clients — the generic lifecycle
  // frame arrives IN ADDITION.
  await phoneSock.waitFor('device_linked');
  const frame = await phoneSock.waitFor('sessions_changed');
  assert.deepEqual(frame.payload, {
    memberId: a.memberId,
    reason: 'linked',
    sessionId: linked.sessionId,
    deviceName: 'Mias iPad',
  });

  // Device management is a per-member concern — the partner stays out.
  await partnerSock.assertNone('sessions_changed');
});

test('rotating a session tells all devices — and the old session closes with 4001', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  const ipad = await linkDevice(baseUrl, a, 'Mias iPad', 'mia-ipad-0001');
  const ipadSock = await wsOpen(baseUrl, ipad.token, t);
  const phoneSock = await wsOpen(baseUrl, a.token, t);
  await ipadSock.waitFor('welcome');
  await phoneSock.waitFor('welcome');
  const phoneClosed = closeCodeOf(phoneSock);

  const rotated = await a.api.post('/api/sessions/current/rotate');
  assert.equal(rotated.status, 200);

  // The OTHER device refreshes its manager; sessionId names the successor.
  const frame = await ipadSock.waitFor('sessions_changed');
  assert.equal(frame.payload.memberId, a.memberId);
  assert.equal(frame.payload.reason, 'rotated');
  assert.equal(frame.payload.sessionId, rotated.body.sessionId);

  // The rotating device's old socket hears the frame too, then dies with the
  // unique terminal code (its token is void — it must re-auth with the new one).
  await phoneSock.waitFor('sessions_changed');
  assert.equal(await phoneClosed, 4001);
});

test('EVAL repro: revoking one session updates every device manager and closes the victim with 4001', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  const ipad = await linkDevice(baseUrl, a, 'Mias iPad', 'mia-ipad-0001');
  const ipadSock = await wsOpen(baseUrl, ipad.token, t);
  const phoneSock = await wsOpen(baseUrl, a.token, t);
  await ipadSock.waitFor('welcome');
  await phoneSock.waitFor('welcome');
  const ipadClosed = closeCodeOf(ipadSock);

  assert.equal((await a.api.post(`/api/sessions/${ipad.sessionId}/revoke`)).status, 200);

  // BOTH devices hear it — the revoker's open device manager updates live
  // (this is the eval find: before the fix nobody but the partner was told).
  const onPhone = await phoneSock.waitFor('sessions_changed');
  assert.deepEqual(onPhone.payload, {
    memberId: a.memberId,
    reason: 'revoked',
    sessionId: ipad.sessionId,
    deviceName: 'Mias iPad',
  });
  const onIpad = await ipadSock.waitFor('sessions_changed');
  assert.equal(onIpad.payload.reason, 'revoked');

  // Contract g: the revoked socket dies with the UNIQUE terminal code 4001
  // (client contract: forget the token, do NOT retry).
  assert.equal(await ipadClosed, 4001);
  assert.equal(phoneSock.ws.readyState, phoneSock.ws.OPEN, 'the surviving device stays connected');
});

test('a recovery-key rejoin sends sessions_changed(rejoined) to the member’s other devices', async (t) => {
  const { baseUrl } = await makeApp(t);
  const pair = await setupRecoverableCouple(baseUrl);
  const ipad = await linkDevice(baseUrl, pair.a, 'Mias iPad', 'mia-ipad-0001');
  const ipadSock = await wsOpen(baseUrl, ipad.token, t);
  await ipadSock.waitFor('welcome');

  // Mia's reinstalled phone re-attaches to her own slot via recovery key.
  const rejoined = await client(baseUrl).post('/api/couples/rejoin', {
    json: { code: pair.code, recoveryKey: pair.a.recoveryKey, deviceName: 'Mias neues iPhone' },
  });
  assert.equal(rejoined.status, 200, JSON.stringify(rejoined.body));

  const frame = await ipadSock.waitFor('sessions_changed');
  assert.deepEqual(frame.payload, {
    memberId: pair.a.memberId,
    reason: 'rejoined',
    sessionId: rejoined.body.sessionId,
    deviceName: 'Mias neues iPhone',
  });
});

test('a partner replace revokes the old slot: sessions_changed(revoked) first, then the 4001 close', async (t) => {
  const { baseUrl } = await makeApp(t);
  const pair = await setupRecoverableCouple(baseUrl);
  const benSock = await wsOpen(baseUrl, pair.b.token, t);
  await benSock.waitFor('welcome');
  const benClosed = closeCodeOf(benSock);

  const replace = await pair.a.api.post('/api/couples/replace-partner');
  assert.equal(replace.status, 201);
  const replaced = await client(baseUrl).post('/api/couples/rejoin', {
    json: { code: pair.code, replaceCode: replace.body.replaceCode, deviceName: 'Neues Handy' },
  });
  assert.equal(replaced.status, 200, JSON.stringify(replaced.body));

  // Ben's cut-off device learns WHY before the socket dies terminally.
  const frame = await benSock.waitFor('sessions_changed');
  assert.equal(frame.payload.memberId, pair.b.memberId);
  assert.equal(frame.payload.reason, 'revoked');
  assert.equal(await benClosed, 4001);
});
