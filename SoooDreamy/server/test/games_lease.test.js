// Input lease + spectator mode (Welle 6): per game session only ONE device of
// the moving member may submit moves — the first mover holds the lease, other
// own devices are read-only spectators until an explicit takeover, and a
// lease dies lazily with its session (revoke/expiry). Contract lives in
// docs/API.md ("Input lease & spectator devices").
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { client, makeApp, wsOpen } from './helpers.js';

const sha256 = (text) => createHash('sha256').update(text, 'utf8').digest('hex');

/** Couple with explicit device identities so lease views are assertable. */
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
    coupleId: created.body.coupleId,
    a: {
      token: created.body.token,
      memberId: created.body.memberId,
      sessionId: created.body.sessionId,
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

/** Attaches a second device to `who` via link code; returns its session. */
async function linkDevice(baseUrl, who, deviceName, deviceId) {
  const issued = await who.api.post('/api/sessions/link-code');
  assert.equal(issued.status, 201);
  const linked = await client(baseUrl).post('/api/couples/link', {
    json: { code: issued.body.linkCode, deviceName, deviceId },
  });
  assert.equal(linked.status, 200, JSON.stringify(linked.body));
  return {
    token: linked.body.token,
    sessionId: linked.body.sessionId,
    api: client(baseUrl, linked.body.token),
  };
}

test('lease: first mover acquires, second device is refused with the holder, takeover flips it', async (t) => {
  const { baseUrl } = await makeApp(t);
  const pair = await setupDeviceCouple(baseUrl);
  const ipad = await linkDevice(baseUrl, pair.a, 'Mias iPad', 'mia-ipad-0001');

  const iphoneSock = await wsOpen(baseUrl, pair.a.token, t);
  const ipadSock = await wsOpen(baseUrl, ipad.token, t);
  const benSock = await wsOpen(baseUrl, pair.b.token, t);
  await iphoneSock.waitFor('welcome');
  await ipadSock.waitFor('welcome');
  await benSock.waitFor('welcome');

  const game = (await pair.a.api.post('/api/games', { json: { type: 'connectfour' } })).body.game;
  assert.deepEqual(game.leases, {}, 'a fresh game carries no leases');
  await pair.b.api.post(`/api/games/${game.id}/join`, { json: {} });

  // First VALID move from the iPhone grabs the lease; the member's own
  // devices hear about it (frame precedes the move frame), the partner not.
  const moved = await pair.a.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'drop', column: 3 } },
  });
  assert.equal(moved.status, 201);
  let expectedLease = null;
  for (const sock of [iphoneSock, ipadSock]) {
    const frame = await sock.waitFor('game_lease');
    assert.equal(frame.payload.gameId, game.id);
    assert.equal(frame.payload.memberId, pair.a.memberId);
    assert.equal(frame.payload.reason, 'acquired');
    assert.equal(frame.payload.lease.deviceId, 'mia-iphone-0001');
    assert.equal(frame.payload.lease.deviceName, 'Mias iPhone');
    assert.equal(frame.payload.lease.sessionSuffix, pair.a.sessionId.slice(-8));
    assert.ok(Number.isFinite(Date.parse(frame.payload.lease.acquiredAt)));
    assert.deepEqual(
      Object.keys(frame.payload.lease).sort(),
      ['acquiredAt', 'deviceId', 'deviceName', 'sessionSuffix'],
      'the lease view must never grow surprise fields (e.g. the session id)',
    );
    expectedLease = frame.payload.lease;
    assert.deepEqual(frame.origin, {
      memberId: pair.a.memberId,
      deviceId: 'mia-iphone-0001',
      sessionSuffix: pair.a.sessionId.slice(-8),
    });
    await sock.waitFor('game_move');
  }
  await benSock.waitFor('game_move');
  await benSock.assertNone('game_lease');

  // The iPad is a spectator now: its move bounces with the holding device
  // attached, and nothing is stored.
  const refused = await ipad.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'drop', column: 4 } },
  });
  assert.equal(refused.status, 409);
  assert.equal(refused.body.error, 'game_lease_held');
  assert.match(refused.body.message, /takeover/);
  assert.deepEqual(refused.body.details, { gameId: game.id, lease: expectedLease });
  assert.equal((await pair.a.api.get(`/api/games/${game.id}`)).body.game.moves.length, 1);

  // The lease is PER MEMBER: Ben's first move acquires his own lease and
  // never touches Mia's.
  assert.equal((await pair.b.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'drop', column: 4 } },
  })).status, 201);
  const benLease = await benSock.waitFor('game_lease');
  assert.equal(benLease.payload.memberId, pair.b.memberId);
  await iphoneSock.assertNone('game_lease');
  await ipadSock.assertNone('game_lease');

  // Spectator parity: both of Mia's devices read the IDENTICAL game — the
  // lease view carries only the 8-char session suffix, never the session id.
  const fromIphone = await pair.a.api.get(`/api/games/${game.id}`);
  const fromIpad = await ipad.api.get(`/api/games/${game.id}`);
  assert.deepEqual(fromIpad.body, fromIphone.body);
  assert.deepEqual(fromIpad.body.game.leases[pair.a.memberId], expectedLease);
  assert.equal(JSON.stringify(fromIpad.body).includes(pair.a.sessionId), false);
  assert.equal(JSON.stringify(fromIpad.body).includes(ipad.sessionId), false);

  // Explicit takeover moves the lease onto the iPad …
  const takeover = await ipad.api.post(`/api/games/${game.id}/takeover`);
  assert.equal(takeover.status, 200);
  assert.equal(takeover.body.gameId, game.id);
  assert.equal(takeover.body.memberId, pair.a.memberId);
  assert.equal(takeover.body.lease.deviceId, 'mia-ipad-0001');
  assert.equal(takeover.body.lease.sessionSuffix, ipad.sessionId.slice(-8));
  for (const sock of [iphoneSock, ipadSock]) {
    const frame = await sock.waitFor('game_lease');
    assert.equal(frame.payload.reason, 'takeover');
    assert.equal(frame.payload.lease.deviceId, 'mia-ipad-0001');
  }
  await benSock.assertNone('game_lease');

  // … so the roles swap: iPhone bounces, iPad moves.
  const bounced = await pair.a.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'drop', column: 3 } },
  });
  assert.equal(bounced.status, 409);
  assert.equal(bounced.body.details.lease.deviceId, 'mia-ipad-0001');
  assert.equal((await ipad.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'drop', column: 3 } },
  })).status, 201);
  await ipadSock.waitFor('game_move');

  // A repeated takeover by the holder is idempotent — no extra fanout.
  assert.equal((await ipad.api.post(`/api/games/${game.id}/takeover`)).status, 200);
  await iphoneSock.assertNone('game_lease');
  await ipadSock.assertNone('game_lease');
});

test('lease: an INVALID move never grabs the lease', async (t) => {
  const { baseUrl } = await makeApp(t);
  const pair = await setupDeviceCouple(baseUrl);
  const ipad = await linkDevice(baseUrl, pair.a, 'Mias iPad', 'mia-ipad-0001');

  const game = (await pair.a.api.post('/api/games', { json: { type: 'connectfour' } })).body.game;
  await pair.b.api.post(`/api/games/${game.id}/join`, { json: {} });

  // Column 7 does not exist — the move is rejected AND the lease stays free …
  const invalid = await pair.a.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'drop', column: 7 } },
  });
  assert.equal(invalid.status, 400);
  assert.deepEqual((await pair.a.api.get(`/api/games/${game.id}`)).body.game.leases, {});

  // … so the iPad can still become the first mover.
  assert.equal((await ipad.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'drop', column: 3 } },
  })).status, 201);
  const leases = (await pair.a.api.get(`/api/games/${game.id}`)).body.game.leases;
  assert.equal(leases[pair.a.memberId].deviceId, 'mia-ipad-0001');
});

test('lease: dies with a revoked session and is inherited silently by the next mover', async (t) => {
  const { baseUrl } = await makeApp(t);
  const pair = await setupDeviceCouple(baseUrl);
  const ipad = await linkDevice(baseUrl, pair.a, 'Mias iPad', 'mia-ipad-0001');

  const game = (await pair.a.api.post('/api/games', { json: { type: 'connectfour' } })).body.game;
  await pair.b.api.post(`/api/games/${game.id}/join`, { json: {} });

  // The iPhone plays and holds the lease; the iPad is locked out.
  assert.equal((await pair.a.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'drop', column: 0 } },
  })).status, 201);
  assert.equal((await ipad.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'drop', column: 1 } },
  })).status, 409);

  // Mia revokes the iPhone session from the iPad (lost device flow) — after
  // Ben's interleaved turn the iPad inherits WITHOUT a takeover call.
  assert.equal((await ipad.api.post(`/api/sessions/${pair.a.sessionId}/revoke`)).status, 200);
  assert.equal((await pair.b.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'drop', column: 4 } },
  })).status, 201);
  const ipadSock = await wsOpen(baseUrl, ipad.token, t);
  await ipadSock.waitFor('welcome');
  const inherited = await ipad.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'drop', column: 1 } },
  });
  assert.equal(inherited.status, 201, JSON.stringify(inherited.body));
  const frame = await ipadSock.waitFor('game_lease');
  assert.equal(frame.payload.reason, 'acquired');
  assert.equal(frame.payload.lease.deviceId, 'mia-ipad-0001');
  const leases = (await ipad.api.get(`/api/games/${game.id}`)).body.game.leases;
  assert.equal(leases[pair.a.memberId].deviceId, 'mia-ipad-0001');

  // The revoked session's token is dead for game routes too, of course.
  assert.equal((await pair.a.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'drop', column: 0 } },
  })).status, 401);
});

test('spectator devices get no spoilers: commit-reveal stays sealed until the holder reveals', async (t) => {
  const { baseUrl } = await makeApp(t);
  const pair = await setupDeviceCouple(baseUrl);
  const ipad = await linkDevice(baseUrl, pair.a, 'Mias iPad', 'mia-ipad-0001');
  const ipadSock = await wsOpen(baseUrl, ipad.token, t);
  await ipadSock.waitFor('welcome');

  const categories = ['Stadt', 'Land', 'Fluss'];
  const game = (await pair.a.api.post('/api/games', {
    json: { type: 'stadtlandfluss', payload: { rounds: 1, categories } },
  })).body.game;
  await pair.b.api.post(`/api/games/${game.id}/join`, { json: {} });
  const move = (who, data) => who.api.post(`/api/games/${game.id}/move`, { json: { data } });

  // Mia seals her answers on the iPhone. The spectator iPad receives ONLY
  // the digest — the plaintext answers exist nowhere on the relay yet.
  const secret = 'Aachen\u001fAlbanien\u001fAmper';
  const salt = 'salz-1';
  const committed = await move(pair.a, { kind: 'commit', round: 0, commit: sha256(secret + salt) });
  assert.equal(committed.status, 201);
  await ipadSock.waitFor('game_lease');
  const commitFrame = await ipadSock.waitFor('game_move');
  assert.equal(commitFrame.payload.move.data.kind, 'commit');
  assert.equal(commitFrame.payload.move.data.reveal, undefined);
  assert.equal(JSON.stringify(commitFrame).includes('Aachen'), false);
  const spectatorView = await ipad.api.get(`/api/games/${game.id}`);
  assert.equal(JSON.stringify(spectatorView.body).includes('Aachen'), false);

  // The spectator cannot push a reveal past the lease — the refusal comes
  // BEFORE any reveal processing, so nothing is stored or broadcast.
  const sneaked = await move(ipad, { kind: 'reveal', round: 0, reveal: secret, salt });
  assert.equal(sneaked.status, 409);
  assert.equal(sneaked.body.error, 'game_lease_held');
  await ipadSock.assertNone('game_move');

  // Once Ben commits and MIA'S HOLDING DEVICE reveals, every couple device
  // receives the verified plaintext — now it is fair game.
  assert.equal((await move(pair.b, { kind: 'commit', round: 0, commit: sha256('B\u001fB\u001fB' + 's2') })).status, 201);
  await ipadSock.waitFor('game_move', (m) => m.payload.move.memberId === pair.b.memberId);
  const revealed = await move(pair.a, { kind: 'reveal', round: 0, reveal: secret, salt });
  assert.equal(revealed.status, 201);
  assert.equal(revealed.body.move.data.verified, true);
  const revealFrame = await ipadSock.waitFor('game_move', (m) => m.payload.move.data.kind === 'reveal');
  assert.equal(revealFrame.payload.move.data.reveal, secret);
});

test('lease: a clientMoveId retry from another device returns the stored duplicate, not a refusal', async (t) => {
  const { baseUrl } = await makeApp(t);
  const pair = await setupDeviceCouple(baseUrl);
  const ipad = await linkDevice(baseUrl, pair.a, 'Mias iPad', 'mia-ipad-0001');

  const game = (await pair.a.api.post('/api/games', { json: { type: 'connectfour' } })).body.game;
  await pair.b.api.post(`/api/games/${game.id}/join`, { json: {} });

  const first = await pair.a.api.post(`/api/games/${game.id}/move`, {
    json: { clientMoveId: 'cm-1', data: { kind: 'drop', column: 2 } },
  });
  assert.equal(first.status, 201);

  // Same member + same clientMoveId from the other device: idempotency wins
  // over the lease (a retry must never bounce), the stored move comes back.
  const replay = await ipad.api.post(`/api/games/${game.id}/move`, {
    json: { clientMoveId: 'cm-1', data: { kind: 'drop', column: 2 } },
  });
  assert.equal(replay.status, 200);
  assert.equal(replay.body.duplicate, true);
  assert.deepEqual(replay.body.move, first.body.move);

  // A FRESH move id from the spectator device still bounces.
  const fresh = await ipad.api.post(`/api/games/${game.id}/move`, {
    json: { clientMoveId: 'cm-2', data: { kind: 'drop', column: 5 } },
  });
  assert.equal(fresh.status, 409);
  assert.equal(fresh.body.error, 'game_lease_held');
});

test('takeover: refused on ended games, works in the lobby (pre-claim)', async (t) => {
  const { baseUrl } = await makeApp(t);
  const pair = await setupDeviceCouple(baseUrl);
  const ipad = await linkDevice(baseUrl, pair.a, 'Mias iPad', 'mia-ipad-0001');

  const lobby = (await pair.a.api.post('/api/games', { json: { type: 'connectfour' } })).body.game;
  const preclaim = await ipad.api.post(`/api/games/${lobby.id}/takeover`);
  assert.equal(preclaim.status, 200);
  assert.equal(preclaim.body.lease.deviceId, 'mia-ipad-0001');

  // The pre-claimed lease binds once the game starts: the iPhone bounces.
  await pair.b.api.post(`/api/games/${lobby.id}/join`, { json: {} });
  assert.equal((await pair.a.api.post(`/api/games/${lobby.id}/move`, {
    json: { data: { kind: 'drop', column: 0 } },
  })).status, 409);

  await pair.a.api.post(`/api/games/${lobby.id}/end`, { json: { forfeit: true } });
  const late = await pair.a.api.post(`/api/games/${lobby.id}/takeover`);
  assert.equal(late.status, 409);
  assert.equal(late.body.error, 'game_ended');
});
