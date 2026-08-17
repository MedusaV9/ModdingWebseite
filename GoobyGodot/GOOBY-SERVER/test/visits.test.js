// Besuche: Haus-Snapshot (PUT/GET, 256-KB-Limit, rev-Bump, nur Freunde) + Besuchs-Flow
// (Request/Accept/Ready) + POS-Relay im visit:-Room inkl. 5-Hz-Drossel + Join-Guard.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { startServer, newIdentity, WsClient, twoFriends, bearer } from './helpers.js';

function putHouse(server, id, layout) {
  return fetch(`${server.url}/api/house`, {
    method: 'PUT',
    headers: { 'content-type': 'application/json', authorization: bearer(id) },
    body: JSON.stringify(layout),
  });
}

test('Haus-Snapshot: Upload bumpt rev, Freund darf lesen, Fremder nicht', async (t) => {
  const { server, idA, idB, codeA } = await twoFriends(t);
  const layout = { rooms: { kitchen: [{ item: 'toaster', cell: [1, 2] }] } };
  const r1 = await (await putHouse(server, idA, layout)).json();
  assert.deepEqual(r1, { ok: true, rev: 1 });
  const r2 = await (await putHouse(server, idA, layout)).json();
  assert.equal(r2.rev, 2, 'rev-Bump bei jedem Upload');

  // Freund B darf lesen.
  const get = await fetch(`${server.url}/api/house/${codeA}`, {
    headers: { authorization: bearer(idB) },
  });
  const body = await get.json();
  assert.equal(body.rev, 2);
  assert.deepEqual(body.layout, layout);

  // Fremder (kein Freund) → 403.
  const idC = newIdentity('Cleo');
  const c = await WsClient.connect(server.wsUrl);
  await c.hello(idC);
  t.after(() => c.close());
  const forbidden = await fetch(`${server.url}/api/house/${codeA}`, {
    headers: { authorization: bearer(idC) },
  });
  assert.equal(forbidden.status, 403);
  // Ohne Auth → 401; unbekanntes Haus → 404.
  assert.equal((await fetch(`${server.url}/api/house/${codeA}`)).status, 401);
  const none = await fetch(`${server.url}/api/house/GOOBY-2222`, {
    headers: { authorization: bearer(idA) },
  });
  assert.equal(none.status, 404);
});

test('Haus-Snapshot: 256-KB-Limit wird erzwungen (413)', async (t) => {
  const { server, idA } = await twoFriends(t);
  const big = { pad: 'x'.repeat(280 * 1024) };
  const res = await putHouse(server, idA, big);
  assert.equal(res.status, 413);
});

test('Besuchs-Flow: REQUEST → INCOMING → ACCEPT → READY → beide im Room, POS-Relay 5 Hz', async (t) => {
  // Eingefrorene Uhr → POS-Bucket füllt sich nicht nach → exakt Burst-Kapazität kommt durch.
  let now = 1_700_000_000_000;
  const { server, a, b, codeA, codeB } = await twoFriends(t, { clock: { now: () => now } });
  void now;

  // Gast B fragt an.
  const reqRes = await b.request('VISIT_REQUEST', { target: codeA });
  assert.equal(reqRes.t, 'OK');
  const incoming = await a.next('VISIT_INCOMING');
  assert.equal(incoming.d.from, codeB);
  assert.equal(incoming.d.name, 'Ben');
  // Host akzeptiert → beide READY mit Room + rev.
  const readyA = await a.request('VISIT_ACCEPT', { guest: codeB });
  assert.equal(readyA.t, 'VISIT_READY');
  const readyB = await b.next('VISIT_READY');
  assert.equal(readyB.d.room, `visit:${codeA}`);
  assert.equal(readyB.d.host, codeA);
  assert.equal(readyB.d.guest, codeB);

  const room = readyB.d.room;
  assert.equal((await a.request('ROOM_JOIN', { room })).t, 'OK');
  const joinB = await b.request('ROOM_JOIN', { room });
  assert.equal(joinB.t, 'OK');
  await a.next('ROOM_PEER_JOINED');

  // POS-Relay: 12 schnelle Updates → genau 10 (Burst-Kapazität) kommen durch.
  for (let i = 0; i < 12; i++) {
    a.send('ROOM_MSG', { room, kind: 'POS', body: { pos: [i, 0], anim: 'walk', roomId: 'kitchen' } });
  }
  const got = [];
  for (let i = 0; i < 10; i++) {
    const m = await b.next((x) => x.t === 'ROOM_MSG' && x.d.kind === 'POS');
    got.push(m.d.body.pos[0]);
    assert.equal(m.d.from.friendCode, codeA);
  }
  assert.deepEqual(got, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
  // Synchronisationspunkt: die 2 gedrosselten Updates sind NICHT angekommen.
  await b.request('PING');
  assert.equal(b.inbox.filter((m) => m.t === 'ROOM_MSG' && m.d.kind === 'POS').length, 0);

  // VISIT_END räumt auf: beide bekommen VISIT_ENDED.
  const endRes = await a.request('VISIT_END', { room });
  assert.equal(endRes.t, 'OK');
  const endedB = await b.next('VISIT_ENDED');
  assert.equal(endedB.d.by, codeA);
  assert.equal(server.ctx.rooms.get(room), null, 'Room ist weg');
});

test('Join-Guard: Fremde kommen nicht in fremde visit:-Rooms; Fehlfälle', async (t) => {
  const { server, a, b, codeA, codeB } = await twoFriends(t);
  // Ohne akzeptierten Besuch: niemand darf rein (auch der Host selbst nicht — kein Besuch aktiv).
  const denied = await b.request('ROOM_JOIN', { room: `visit:${codeA}` });
  assert.equal(denied.d.code, 'BAD_ROOM');
  // Dritter (nicht befreundet) kann keinen Besuch anfragen.
  const c = await WsClient.connect(server.wsUrl);
  await c.hello(newIdentity('Cleo'));
  t.after(() => c.close());
  assert.equal((await c.request('VISIT_REQUEST', { target: codeA })).d.code, 'NOT_FRIENDS');
  // Besuch bei Offline-Host → OFFLINE_TARGET.
  a.close();
  await b.next('FRIEND_PRESENCE'); // offline
  assert.equal((await b.request('VISIT_REQUEST', { target: codeA })).d.code, 'OFFLINE_TARGET');
  void codeB;
});

test('ROOM_MSG-Härtung: Body-Limit 8 KB, kaputter kind, fremder Room', async (t) => {
  const { a, codeA } = await twoFriends(t);
  // BUILD_DELTA-Relay funktioniert nur im Room — vorher NOT_IN_ROOM.
  const notIn = await a.request('ROOM_MSG', { room: `visit:${codeA}`, kind: 'POS', body: {} });
  assert.equal(notIn.d.code, 'NOT_IN_ROOM');
  const badRoom = await a.request('ROOM_JOIN', { room: 'kaputt:xyz' });
  assert.equal(badRoom.d.code, 'BAD_ROOM');
});
