// GvZ-Netz-PvP (G7): Einladungs-Handshake (nur Freunde, Seiten gooby/zombie),
// Start-Handshake (BEIDE senden GVZ_START_REQ → GVZ_START mit Server-Seed),
// Lockstep-Input-Relay (Ordnung!), Desync-Wächter, Peer-Down/Up OHNE
// Rejoin-Snapshot und idempotentes Ergebnis mit Münz-Reward (pending + ACK).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { WsClient, twoFriends, newIdentity } from './helpers.js';

// Standard-Fixture: zwei Freunde mit fertiger Session (Raum gejoint).
// Einladender = a (Seite gooby), Annehmender = b (Seite zombie).
async function startPvp(t, opts) {
  const fixture = await twoFriends(t, opts);
  const { a, b, codeA, codeB } = fixture;
  assert.equal((await a.request('GVZ_INVITE', { target: codeB })).t, 'OK');
  const invited = await b.next('GVZ_INVITED');
  assert.equal(invited.d.from, codeA);
  const readyB = await b.request('GVZ_ACCEPT', { from: codeA });
  assert.equal(readyB.t, 'GVZ_READY');
  const readyA = await a.next('GVZ_READY');
  assert.equal(readyA.d.room, readyB.d.room);
  const room = readyA.d.room;
  assert.ok(room.startsWith('gvz:'));
  await a.request('ROOM_JOIN', { room });
  await b.request('ROOM_JOIN', { room });
  await a.next('ROOM_PEER_JOINED');
  return { ...fixture, room, ready: readyA.d };
}

// Beide melden Start-Wunsch → GVZ_START mit Server-Seed an beide.
async function startMatch(a, b, room) {
  assert.equal((await a.request('GVZ_START_REQ', { room })).t, 'OK');
  assert.equal((await b.request('GVZ_START_REQ', { room })).t, 'OK');
  const startA = await a.next('GVZ_START');
  const startB = await b.next('GVZ_START');
  assert.deepEqual(startA.d.seed, startB.d.seed, 'ein gemeinsamer Server-Seed');
  return startA.d;
}

test('Handshake: Einladender = gooby, Annehmender = zombie; Start erst wenn BEIDE anfragen', async (t) => {
  const { a, b, room, ready, codeA, codeB } = await startPvp(t);
  const sideOf = Object.fromEntries(ready.players.map((p) => [p.friendCode, p.side]));
  assert.equal(sideOf[codeA], 'gooby', 'der Einladende verteidigt');
  assert.equal(sideOf[codeB], 'zombie', 'der Annehmende schickt die Wellen');
  assert.equal(ready.inputDelay, 4, 'Input-Delay-Fenster 3–5 Ticks');
  assert.equal(ready.hashEveryTicks, 60);

  // Vor dem Start: kein Input-Relay, kein Ergebnis (Phase lobby).
  const early = await a.request('ROOM_MSG', {
    room,
    kind: 'GP_INPUT',
    body: { n: 1, upTo: 6, a: [] },
  });
  assert.equal(early.d.code, 'NOT_RUNNING');
  assert.equal(
    (await a.request('GVZ_RESULT', { room, winner: 'gooby', tick: 0 })).d.code,
    'NOT_RUNNING'
  );

  // Nur EIN Start-Wunsch startet noch nicht.
  const reqA = await a.request('GVZ_START_REQ', { room });
  assert.equal(reqA.t, 'OK');
  assert.equal(reqA.d.waiting, true, 'wartet auf den Partner');
  assert.equal(a.inbox.filter((m) => m.t === 'GVZ_START').length, 0, 'noch kein Start');
  // B zieht nach → Start mit Server-Seed an beide, Seiten im Payload.
  assert.equal((await b.request('GVZ_START_REQ', { room })).t, 'OK');
  const startA = await a.next('GVZ_START');
  const startB = await b.next('GVZ_START');
  assert.equal(typeof startA.d.seed, 'number', 'Seed vergibt der SERVER');
  assert.equal(startA.d.seed, startB.d.seed);
  assert.equal(startA.d.inputDelay, 4);
  assert.equal(startA.d.hashEveryTicks, 60);
  const startSides = Object.fromEntries(startA.d.players.map((p) => [p.friendCode, p.side]));
  assert.deepEqual(startSides, { [codeA]: 'gooby', [codeB]: 'zombie' });
  // Während des Laufs ist der Start-Handshake zu.
  assert.equal((await a.request('GVZ_START_REQ', { room })).d.code, 'GAME_RUNNING');
});

test('Ablehnen: GVZ_DECLINE räumt die Einladung, Einladender bekommt GVZ_DECLINED', async (t) => {
  const { a, b, codeA, codeB } = await twoFriends(t);
  assert.equal((await a.request('GVZ_INVITE', { target: codeB })).t, 'OK');
  await b.next('GVZ_INVITED');
  assert.equal((await b.request('GVZ_DECLINE', { from: codeA })).t, 'OK');
  const declined = await a.next('GVZ_DECLINED');
  assert.equal(declined.d.from, codeB);
  // Die Einladung ist weg — ein nachträgliches Annehmen scheitert.
  assert.equal((await b.request('GVZ_ACCEPT', { from: codeA })).d.code, 'NOT_FOUND');
});

test('Fremde abgelehnt: NOT_FRIENDS bei Invite, BAD_ROOM beim Raum-Join', async (t) => {
  const { server, a, b, room, codeA } = await startPvp(t);
  const stranger = await WsClient.connect(server.wsUrl);
  const hello = await stranger.hello(newIdentity('Zed', 'Fremdling'));
  t.after(() => stranger.close());
  // Fremder lädt A ein → NOT_FRIENDS.
  assert.equal((await stranger.request('GVZ_INVITE', { target: codeA })).d.code, 'NOT_FRIENDS');
  // Fremder will in den PvP-Raum → BAD_ROOM (Join-Guard).
  assert.equal((await stranger.request('ROOM_JOIN', { room })).d.code, 'BAD_ROOM');
  // Und A kann den Fremden nicht einladen (keine Freunde).
  assert.equal(
    (await a.request('GVZ_INVITE', { target: hello.d.friendCode })).d.code,
    'NOT_FRIENDS'
  );
  // b bleibt unbehelligt (keine Invited-Push-Leiche im Posteingang).
  assert.equal(b.inbox.filter((m) => m.t === 'GVZ_INVITED').length, 0);
});

test('Input-Relay: Frames reisen geordnet, n muss strikt monoton sein', async (t) => {
  const { a, b, room } = await startPvp(t);
  await startMatch(a, b, room);
  // 3 Frames der Gooby-Seite — Frame 2 pflanzt eine Schnarch-Knolle.
  for (let n = 1; n <= 3; n += 1) {
    a.send('ROOM_MSG', {
      room,
      kind: 'GP_INPUT',
      body: {
        n,
        upTo: n * 6,
        a: n === 2 ? [{ t: 10, do: 'place', type: 'schnarch_knolle', lane: 2, col: 1 }] : [],
      },
    });
  }
  const got = [];
  for (let i = 0; i < 3; i += 1) {
    const msg = await b.next((m) => m.t === 'ROOM_MSG' && m.d.kind === 'GP_INPUT');
    got.push(msg.d.body.n);
    if (msg.d.body.n === 2) {
      assert.deepEqual(msg.d.body.a, [
        { t: 10, do: 'place', type: 'schnarch_knolle', lane: 2, col: 1 },
      ]);
    }
  }
  assert.deepEqual(got, [1, 2, 3], 'Relay-Ordnung = Sende-Ordnung');
  // Zombie-Seite beschwört — reist genauso (spawn-Aktion).
  b.send('ROOM_MSG', {
    room,
    kind: 'GP_INPUT',
    body: { n: 1, upTo: 8, a: [{ t: 12, do: 'spawn', type: 'schlurfi', lane: 0 }] },
  });
  const spawned = await a.next((m) => m.t === 'ROOM_MSG' && m.d.kind === 'GP_INPUT');
  assert.equal(spawned.d.body.a[0].do, 'spawn');
  // Doppelte/rückwärts laufende Frame-Nummern → BAD_TURN_N.
  const dupe = await a.request('ROOM_MSG', {
    room,
    kind: 'GP_INPUT',
    body: { n: 3, upTo: 30, a: [] },
  });
  assert.equal(dupe.d.code, 'BAD_TURN_N');
  // Kaputte Aktionen → BAD_MESSAGE (t negativ / fremdes do).
  const badTick = await a.request('ROOM_MSG', {
    room,
    kind: 'GP_INPUT',
    body: { n: 4, upTo: 30, a: [{ t: -1, do: 'place', type: 'x', lane: 0, col: 0 }] },
  });
  assert.equal(badTick.d.code, 'BAD_MESSAGE');
  const badDo = await a.request('ROOM_MSG', {
    room,
    kind: 'GP_INPUT',
    body: { n: 4, upTo: 30, a: [{ t: 5, do: 'cut', id: 1 }] },
  });
  assert.equal(badDo.d.code, 'BAD_MESSAGE', 'GOB-NOM-Aktionen haben hier nichts verloren');
});

test('Desync-Wächter: gleicher Tick, verschiedene Hashes → GVZ_DESYNC an beide', async (t) => {
  const { a, b, room } = await startPvp(t);
  await startMatch(a, b, room);
  // Tick 60: identisch → kein Alarm (Hash wird trotzdem relayt).
  a.send('ROOM_MSG', { room, kind: 'GP_HASH', body: { t: 60, h: 'h-60' } });
  const relay = await b.next((m) => m.t === 'ROOM_MSG' && m.d.kind === 'GP_HASH');
  assert.equal(relay.d.body.h, 'h-60');
  b.send('ROOM_MSG', { room, kind: 'GP_HASH', body: { t: 60, h: 'h-60' } });
  await a.next((m) => m.t === 'ROOM_MSG' && m.d.kind === 'GP_HASH');
  assert.equal(a.inbox.filter((m) => m.t === 'GVZ_DESYNC').length, 0);
  // Tick 120: divergent → höflicher Abbruch statt Weiterspielen.
  a.send('ROOM_MSG', { room, kind: 'GP_HASH', body: { t: 120, h: 'h-a' } });
  b.send('ROOM_MSG', { room, kind: 'GP_HASH', body: { t: 120, h: 'h-b' } });
  const desyncA = await a.next('GVZ_DESYNC');
  const desyncB = await b.next('GVZ_DESYNC');
  assert.equal(desyncA.d.tick, 120);
  assert.equal(desyncB.d.tick, 120);
  // Danach nimmt der Server keine Inputs mehr an.
  const rejected = await a.request('ROOM_MSG', {
    room,
    kind: 'GP_INPUT',
    body: { n: 1, upTo: 6, a: [] },
  });
  assert.equal(rejected.d.code, 'NOT_RUNNING');
});

test('Ergebnis: idempotent (ein Push pro Spieler, stabile rewardId, Münzen je Seite)', async (t) => {
  const { a, b, room, codeA, codeB } = await startPvp(t);
  await startMatch(a, b, room);
  // Zombie-Sieg gemeldet von der Gooby-Seite (Verlierer meldet zuerst).
  const resA = await a.request('GVZ_RESULT', { room, winner: 'zombie', tick: 480 });
  assert.equal(resA.t, 'OK');
  assert.equal(resA.d.winner, 'zombie');
  assert.equal(resA.d.rewardId, `gvz-${room.slice(4, 12)}-${codeA}`);
  assert.equal(resA.d.side, 'gooby');
  assert.equal(resA.d.won, false);
  assert.equal(resA.d.coins, 10, 'Trost-Münzen für den Verlierer');
  const pushA = await a.next('GVZ_RESULT');
  const pushB = await b.next('GVZ_RESULT');
  assert.equal(pushA.d.tick, 480);
  assert.equal(pushA.d.coins, 10);
  assert.equal(pushB.d.rewardId, `gvz-${room.slice(4, 12)}-${codeB}`);
  assert.equal(pushB.d.won, true);
  assert.equal(pushB.d.coins, 30, 'Sieger-Münzen für die Zombie-Seite');
  // Zweiter Report (vom Partner, sogar mit anderem Inhalt) ändert NICHTS.
  const resB = await b.request('GVZ_RESULT', { room, winner: 'gooby', tick: 999 });
  assert.equal(resB.d.winner, 'zombie', 'erster Report friert das Ergebnis ein');
  assert.equal(resB.d.tick, 480);
  assert.equal(resB.d.coins, 30, 'keine Doppel-Münzen, gleicher Betrag');
  assert.equal(resB.d.rewardId, pushB.d.rewardId, 'stabile rewardId');
  assert.equal(a.inbox.filter((m) => m.t === 'GVZ_RESULT').length, 0, 'kein Doppel-Push');
  // Pending bis ACK (Crash-sicher wie GoobyPal).
  assert.equal((await a.request('GVZ_RESULT_ACK', { rewardId: pushA.d.rewardId })).t, 'OK');
});

test('Ergebnis überlebt den Abriss: gvzPending kommt im WELCOME nach, ACK räumt', async (t) => {
  const { server, a, b, room, idB } = await startPvp(t);
  await startMatch(a, b, room);
  b.ws.terminate();
  await a.next('GVZ_PEER_DOWN');
  await a.request('GVZ_RESULT', { room, winner: 'gooby', tick: 4200 });
  await a.next('GVZ_RESULT');
  const b2 = await WsClient.connect(server.wsUrl);
  const welcome = await b2.hello(idB);
  t.after(() => b2.close());
  assert.equal(welcome.d.gvzPending.length, 1);
  assert.equal(welcome.d.gvzPending[0].winner, 'gooby');
  assert.equal(welcome.d.gvzPending[0].won, false, 'B war die Zombie-Seite');
  assert.equal(welcome.d.gvzPending[0].coins, 10);
  const rewardId = welcome.d.gvzPending[0].rewardId;
  assert.equal((await b2.request('GVZ_RESULT_ACK', { rewardId })).t, 'OK');
  const b3 = await WsClient.connect(server.wsUrl);
  const welcome3 = await b3.hello(idB);
  t.after(() => b3.close());
  assert.equal(welcome3.d.gvzPending.length, 0, 'ACK räumt pending');
});

test('Peer-Down/Up: Abriss meldet Frist, Rückkehr per ROOM_JOIN meldet GVZ_PEER_UP', async (t) => {
  const { server, a, b, room, idB } = await startPvp(t);
  await startMatch(a, b, room);
  a.send('ROOM_MSG', { room, kind: 'GP_INPUT', body: { n: 1, upTo: 6, a: [] } });
  await b.next((m) => m.t === 'ROOM_MSG' && m.d.kind === 'GP_INPUT');
  // B reißt ab → A erfährt es sofort (inkl. Wartefenster).
  b.ws.terminate();
  const down = await a.next('GVZ_PEER_DOWN');
  assert.equal(down.d.room, room);
  assert.equal(down.d.waitMs, 120_000, 'Warte-Frist wie Brettspiel/GOB-NOM');
  // B kommt zurück: ROOM_JOIN reicht — KEIN Snapshot (bewusst, Matches kurz).
  const b2 = await WsClient.connect(server.wsUrl);
  await b2.hello(idB);
  t.after(() => b2.close());
  assert.equal((await b2.request('ROOM_JOIN', { room })).t, 'OK');
  const up = await a.next('GVZ_PEER_UP');
  assert.equal(up.d.room, room);
  assert.equal(b2.inbox.filter((m) => m.t.startsWith('GVZ_')).length, 0, 'kein Snapshot-Push');
  // Weiterspielen: Frame-Zähler der Seite läuft NACH der Rückkehr weiter.
  b2.send('ROOM_MSG', { room, kind: 'GP_INPUT', body: { n: 1, upTo: 8, a: [] } });
  const relayed = await a.next((m) => m.t === 'ROOM_MSG' && m.d.kind === 'GP_INPUT');
  assert.equal(relayed.d.body.n, 1);
});

test('Warte-Frist abgelaufen → GVZ_ABORTED (timeout) beim Partner', async (t) => {
  const { a, b, room } = await startPvp(t, { env: { GOOBY_BOARD_REJOIN_MS: '60' } });
  await startMatch(a, b, room);
  b.ws.terminate();
  await a.next('GVZ_PEER_DOWN');
  const aborted = await a.next('GVZ_ABORTED');
  assert.equal(aborted.d.room, room);
  assert.equal(aborted.d.reason, 'timeout');
});

test('Bewusstes Verlassen → GVZ_ABORTED (left), kein Forfeit-Sieger', async (t) => {
  const { a, b, room } = await startPvp(t);
  await startMatch(a, b, room);
  await b.request('ROOM_LEAVE', { room });
  const aborted = await a.next('GVZ_ABORTED');
  assert.equal(aborted.d.reason, 'left');
});

test('Doppel-Session verhindert: wer schon spielt, kann nicht neu einladen/annehmen', async (t) => {
  const { a, b, codeA, codeB } = await startPvp(t);
  assert.equal((await a.request('GVZ_INVITE', { target: codeB })).d.code, 'GAME_RUNNING');
  assert.equal((await b.request('GVZ_INVITE', { target: codeA })).d.code, 'GAME_RUNNING');
});
