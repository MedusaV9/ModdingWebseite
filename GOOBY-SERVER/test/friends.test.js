// Freunde-Flow komplett: Request (Code + Name), Accept/Decline, Liste, Presence, Coins-Cache.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { startServer, newIdentity, WsClient, twoFriends } from './helpers.js';

test('Friends-Flow: Request per friendCode → Accept → beidseitige Liste', async (t) => {
  const { a, b, codeA, codeB } = await twoFriends(t);
  const stateA = await a.request('FRIENDS_LIST');
  assert.equal(stateA.t, 'FRIENDS_STATE');
  assert.equal(stateA.d.friends.length, 1);
  assert.equal(stateA.d.friends[0].friendCode, codeB);
  assert.equal(stateA.d.friends[0].online, true);
  const stateB = await b.request('FRIENDS_LIST');
  assert.equal(stateB.d.friends[0].friendCode, codeA);
});

test('Request per Name: eindeutig ok, mehrdeutig → AMBIGUOUS, unbekannt → NOT_FOUND', async (t) => {
  const server = await startServer();
  t.after(() => server.stop());
  const lena = await WsClient.connect(server.wsUrl);
  await lena.hello(newIdentity('Lena'));
  const lena2 = await WsClient.connect(server.wsUrl);
  await lena2.hello(newIdentity('Lena'));
  const max = await WsClient.connect(server.wsUrl);
  await max.hello(newIdentity('Max'));
  t.after(() => [lena, lena2, max].forEach((c) => c.close()));

  const amb = await max.request('FRIEND_REQUEST', { targetName: 'lena' });
  assert.equal(amb.d.code, 'AMBIGUOUS');
  const nf = await max.request('FRIEND_REQUEST', { targetName: 'Unbekannt' });
  assert.equal(nf.d.code, 'NOT_FOUND');
  const ok = await lena.request('FRIEND_REQUEST', { targetName: 'Max' });
  assert.equal(ok.t, 'OK');
  const incoming = await max.next('FRIEND_REQUEST_INCOMING');
  assert.equal(incoming.d.name, 'Lena');
});

test('Fehlfälle: SELF, DUPLICATE, ALREADY_FRIENDS, Decline bleibt leise', async (t) => {
  const server = await startServer();
  t.after(() => server.stop());
  const a = await WsClient.connect(server.wsUrl);
  const wa = await a.hello(newIdentity('Anna'));
  const b = await WsClient.connect(server.wsUrl);
  const wb = await b.hello(newIdentity('Ben'));
  t.after(() => [a, b].forEach((c) => c.close()));
  const codeA = wa.d.friendCode;
  const codeB = wb.d.friendCode;

  assert.equal((await a.request('FRIEND_REQUEST', { target: codeA })).d.code, 'SELF');
  assert.equal((await a.request('FRIEND_REQUEST', { target: codeB })).t, 'OK');
  assert.equal((await a.request('FRIEND_REQUEST', { target: codeB })).d.code, 'DUPLICATE');
  // Decline: Requester bekommt KEINEN Push, Request ist weg.
  assert.equal((await b.request('FRIEND_DECLINE', { target: codeA })).t, 'OK');
  const state = await b.request('FRIENDS_LIST');
  assert.equal(state.d.requests.length, 0);
  // Nochmal Request → Accept → ALREADY_FRIENDS bei erneutem Request.
  await a.request('FRIEND_REQUEST', { target: codeB });
  await b.next('FRIEND_REQUEST_INCOMING');
  await b.request('FRIEND_ACCEPT', { target: codeA });
  await a.next('FRIEND_ADDED');
  await b.next('FRIEND_ADDED');
  assert.equal((await a.request('FRIEND_REQUEST', { target: codeB })).d.code, 'ALREADY_FRIENDS');
});

test('Gegenläufige Requests → Auto-Accept', async (t) => {
  const server = await startServer();
  t.after(() => server.stop());
  const a = await WsClient.connect(server.wsUrl);
  const wa = await a.hello(newIdentity('Anna'));
  const b = await WsClient.connect(server.wsUrl);
  const wb = await b.hello(newIdentity('Ben'));
  t.after(() => [a, b].forEach((c) => c.close()));
  await a.request('FRIEND_REQUEST', { target: wb.d.friendCode });
  const res = await b.request('FRIEND_REQUEST', { target: wa.d.friendCode });
  assert.equal(res.d.autoAccepted, true);
  await a.next('FRIEND_ADDED');
  await b.next('FRIEND_ADDED');
});

test('Presence: Status-String → Server baut deutsches Label, Push an Freunde; SYNC cached Coins', async (t) => {
  const { a, b } = await twoFriends(t);
  a.send('PRESENCE_SET', { kind: 'park' });
  const push = await b.next('FRIEND_PRESENCE');
  assert.equal(push.d.online, true);
  assert.equal(push.d.activity.kind, 'park');
  assert.equal(push.d.activity.label, 'ist gerade mit Flausch im Park');

  a.send('SYNC', { coins: 1234 });
  // Coins-Cache taucht in der Freundesliste des anderen auf.
  for (let i = 0; i < 20; i++) {
    const state = await b.request('FRIENDS_LIST');
    if (state.d.friends[0].coins === 1234) return;
    await new Promise((r) => setTimeout(r, 25));
  }
  assert.fail('Coins-Cache nicht angekommen');
});

test('Offline-Broadcast + Requests warten im WELCOME (Boot-Pull)', async (t) => {
  const { server, a, b, codeA, idB } = await twoFriends(t);
  // B geht offline → A sieht FRIEND_PRESENCE online:false.
  b.close();
  const push = await a.next('FRIEND_PRESENCE');
  assert.equal(push.d.online, false);
  // Dritter Spieler schickt B (offline) einen Request → B sieht ihn beim nächsten HELLO.
  const c = await WsClient.connect(server.wsUrl);
  await c.hello(newIdentity('Cleo'));
  await c.request('FRIEND_REQUEST', { target: (await a.request('FRIENDS_LIST')).d.friends[0].friendCode });
  const b2 = await WsClient.connect(server.wsUrl);
  const welcome = await b2.hello(idB);
  assert.equal(welcome.d.friendRequests.length, 1);
  assert.equal(welcome.d.friendRequests[0].name, 'Cleo');
  assert.equal(welcome.d.friendRequests[0].from !== codeA, true);
  c.close();
  b2.close();
});

test('FRIEND_REMOVE: Kante weg, beide informiert', async (t) => {
  const { a, b, codeB } = await twoFriends(t);
  await a.request('FRIEND_REMOVE', { target: codeB });
  const gone = await b.next('FRIEND_REMOVED');
  assert.equal(typeof gone.d.friendCode, 'string');
  const state = await a.request('FRIENDS_LIST');
  assert.equal(state.d.friends.length, 0);
});
