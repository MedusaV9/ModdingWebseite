// GOB-NOM-Netz-Coop (W15): Einladungs-Handshake (nur Freunde, Seiten a/b),
// Level-Handshake → Start-Seed, Lockstep-Input-Relay (Ordnung!), Desync-
// Wächter, Rejoin-Replay (120-s-Fenster wie Battleship) und idempotentes
// Ergebnis (pending + ACK).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { WsClient, twoFriends, newIdentity } from './helpers.js';

// Standard-Fixture: zwei Freunde mit fertiger Session (Raum gejoint).
async function startCoop(t, opts) {
  const fixture = await twoFriends(t, opts);
  const { a, b, codeA, codeB } = fixture;
  assert.equal((await a.request('GOBNOM_INVITE', { target: codeB })).t, 'OK');
  const invited = await b.next('GOBNOM_INVITED');
  assert.equal(invited.d.from, codeA);
  const readyB = await b.request('GOBNOM_ACCEPT', { from: codeA });
  assert.equal(readyB.t, 'GOBNOM_READY');
  const readyA = await a.next('GOBNOM_READY');
  assert.equal(readyA.d.room, readyB.d.room);
  const room = readyA.d.room;
  assert.ok(room.startsWith('gobnom:'));
  await a.request('ROOM_JOIN', { room });
  await b.request('ROOM_JOIN', { room });
  await a.next('ROOM_PEER_JOINED');
  return { ...fixture, room, ready: readyA.d };
}

// Beide bestätigen dasselbe Level → GOBNOM_START mit Server-Seed.
async function startLevel(a, b, room, level = 3) {
  assert.equal((await a.request('GOBNOM_LEVEL', { room, level })).t, 'OK');
  await b.next('GOBNOM_LEVEL_STATE');
  assert.equal((await b.request('GOBNOM_LEVEL', { room, level })).t, 'OK');
  const startA = await a.next('GOBNOM_START');
  const startB = await b.next('GOBNOM_START');
  assert.deepEqual(startA.d.seed, startB.d.seed, 'ein gemeinsamer Server-Seed');
  return startA.d;
}

test('Handshake: Einladender = Seite a, Annehmender = b; Level-Handshake liefert Start-Seed', async (t) => {
  const { a, b, room, ready, codeA, codeB } = await startCoop(t);
  const sideOf = Object.fromEntries(ready.players.map((p) => [p.friendCode, p.side]));
  assert.equal(sideOf[codeA], 'a', 'der Einladende spielt links/oben');
  assert.equal(sideOf[codeB], 'b');
  assert.equal(ready.inputDelay, 4, 'Input-Delay-Fenster 3–5 Ticks');
  assert.equal(ready.hashEveryTicks, 60);

  // Unterschiedliche Level-Wünsche starten NICHT.
  assert.equal((await a.request('GOBNOM_LEVEL', { room, level: 2 })).t, 'OK');
  await b.next('GOBNOM_LEVEL_STATE');
  const voteB = await b.request('GOBNOM_LEVEL', { room, level: 5 });
  assert.deepEqual(voteB.d.votes, { [codeA]: 2, [codeB]: 5 });
  await a.next('GOBNOM_LEVEL_STATE');
  // Ungültiges Level wird abgelehnt.
  assert.equal((await a.request('GOBNOM_LEVEL', { room, level: 11 })).d.code, 'BAD_LEVEL');
  // B zieht nach → Start mit Seed + Level.
  assert.equal((await b.request('GOBNOM_LEVEL', { room, level: 2 })).t, 'OK');
  const startA = await a.next('GOBNOM_START');
  const startB = await b.next('GOBNOM_START');
  assert.equal(startA.d.level, 2);
  assert.equal(typeof startA.d.seed, 'number');
  assert.equal(startA.d.seed, startB.d.seed);
  // Während des Laufs ist der Level-Handshake zu.
  assert.equal((await a.request('GOBNOM_LEVEL', { room, level: 2 })).d.code, 'GAME_RUNNING');
});

test('Fremde abgelehnt: NOT_FRIENDS bei Invite, BAD_ROOM beim Raum-Join', async (t) => {
  const { server, a, b, room, codeA } = await startCoop(t);
  const stranger = await WsClient.connect(server.wsUrl);
  const hello = await stranger.hello(newIdentity('Zed', 'Fremdling'));
  t.after(() => stranger.close());
  // Fremder lädt A ein → NOT_FRIENDS.
  assert.equal(
    (await stranger.request('GOBNOM_INVITE', { target: codeA })).d.code,
    'NOT_FRIENDS'
  );
  // Fremder will in den Coop-Raum → BAD_ROOM (Join-Guard).
  assert.equal((await stranger.request('ROOM_JOIN', { room })).d.code, 'BAD_ROOM');
  // Und A kann den Fremden nicht einladen (keine Freunde).
  assert.equal(
    (await a.request('GOBNOM_INVITE', { target: hello.d.friendCode })).d.code,
    'NOT_FRIENDS'
  );
  // b bleibt unbehelligt (keine Invited-Push-Leiche im Posteingang).
  assert.equal(b.inbox.filter((m) => m.t === 'GOBNOM_INVITED').length, 0);
});

test('Input-Relay: Frames reisen geordnet, n muss strikt monoton sein', async (t) => {
  const { a, b, room } = await startCoop(t);
  await startLevel(a, b, room);
  // Vor dem Start abgelehnte Richtung: läuft — jetzt 3 Frames von A.
  for (let n = 1; n <= 3; n += 1) {
    a.send('ROOM_MSG', {
      room,
      kind: 'GN_INPUT',
      body: { n, upTo: n * 6, a: n === 2 ? [{ t: 10, do: 'cut', id: 0 }] : [] },
    });
  }
  const got = [];
  for (let i = 0; i < 3; i += 1) {
    const msg = await b.next((m) => m.t === 'ROOM_MSG' && m.d.kind === 'GN_INPUT');
    got.push(msg.d.body.n);
    if (msg.d.body.n === 2) {
      assert.deepEqual(msg.d.body.a, [{ t: 10, do: 'cut', id: 0 }]);
    }
  }
  assert.deepEqual(got, [1, 2, 3], 'Relay-Ordnung = Sende-Ordnung');
  // Doppelte/rückwärts laufende Frame-Nummern → BAD_TURN_N.
  const dupe = await a.request('ROOM_MSG', {
    room,
    kind: 'GN_INPUT',
    body: { n: 3, upTo: 30, a: [] },
  });
  assert.equal(dupe.d.code, 'BAD_TURN_N');
  // Kaputte Aktionen → BAD_MESSAGE.
  const bad = await a.request('ROOM_MSG', {
    room,
    kind: 'GN_INPUT',
    body: { n: 4, upTo: 30, a: [{ t: -1, do: 'cut', id: 0 }] },
  });
  assert.equal(bad.d.code, 'BAD_MESSAGE');
});

test('Rejoin ≤ Fenster: Snapshot mit komplettem Frame-Replay, PEER_DOWN/UP', async (t) => {
  const { server, a, b, room, idB } = await startCoop(t);
  await startLevel(a, b, room);
  a.send('ROOM_MSG', { room, kind: 'GN_INPUT', body: { n: 1, upTo: 6, a: [] } });
  a.send('ROOM_MSG', {
    room,
    kind: 'GN_INPUT',
    body: { n: 2, upTo: 12, a: [{ t: 9, do: 'pop', id: 1 }] },
  });
  await b.next((m) => m.t === 'ROOM_MSG' && m.d.body?.n === 2);
  b.send('ROOM_MSG', { room, kind: 'GN_INPUT', body: { n: 1, upTo: 8, a: [] } });
  await a.next((m) => m.t === 'ROOM_MSG' && m.d.kind === 'GN_INPUT');
  // B reißt ab → A erfährt es sofort (inkl. Wartefenster).
  b.ws.terminate();
  const down = await a.next('GOBNOM_PEER_DOWN');
  assert.equal(down.d.waitMs, 120_000, '120-s-Fenster wie Battleship');
  // B kommt zurück: ROOM_JOIN reicht, Snapshot kommt automatisch.
  const b2 = await WsClient.connect(server.wsUrl);
  await b2.hello(idB);
  t.after(() => b2.close());
  await b2.request('ROOM_JOIN', { room });
  const snap = await b2.next('GOBNOM_SNAPSHOT');
  assert.equal(snap.d.phase, 'run');
  assert.equal(snap.d.level, 3);
  assert.equal(typeof snap.d.seed, 'number');
  assert.deepEqual(
    snap.d.frames.a.map((f) => f.n),
    [1, 2],
    'Frame-Puffer Seite a vollständig'
  );
  assert.deepEqual(snap.d.frames.a[1].a, [{ t: 9, do: 'pop', id: 1 }]);
  assert.deepEqual(
    snap.d.frames.b.map((f) => f.n),
    [1]
  );
  await a.next('GOBNOM_PEER_UP');
  // Weiterspielen: Frame 2 von B (n läuft NACH Rejoin weiter).
  b2.send('ROOM_MSG', { room, kind: 'GN_INPUT', body: { n: 2, upTo: 14, a: [] } });
  const relayed = await a.next((m) => m.t === 'ROOM_MSG' && m.d.kind === 'GN_INPUT');
  assert.equal(relayed.d.body.n, 2);
});

test('Rejoin-Fenster abgelaufen → GOBNOM_ABORTED (timeout) beim Partner', async (t) => {
  const { a, b, room } = await startCoop(t, { env: { GOOBY_BOARD_REJOIN_MS: '60' } });
  await startLevel(a, b, room);
  b.ws.terminate();
  await a.next('GOBNOM_PEER_DOWN');
  const aborted = await a.next('GOBNOM_ABORTED');
  assert.equal(aborted.d.room, room);
  assert.equal(aborted.d.reason, 'timeout');
});

test('Bewusstes Verlassen → GOBNOM_ABORTED (left), kein Forfeit-Sieger', async (t) => {
  const { a, b, room } = await startCoop(t);
  await startLevel(a, b, room);
  await b.request('ROOM_LEAVE', { room });
  const aborted = await a.next('GOBNOM_ABORTED');
  assert.equal(aborted.d.reason, 'left');
});

test('Desync-Wächter: gleicher Tick, verschiedene Hashes → GOBNOM_DESYNC an beide', async (t) => {
  const { a, b, room } = await startCoop(t);
  await startLevel(a, b, room);
  // Tick 60: identisch → kein Alarm (Hash wird trotzdem relayt).
  a.send('ROOM_MSG', { room, kind: 'GN_HASH', body: { t: 60, h: 'h-60' } });
  const relay = await b.next((m) => m.t === 'ROOM_MSG' && m.d.kind === 'GN_HASH');
  assert.equal(relay.d.body.h, 'h-60');
  b.send('ROOM_MSG', { room, kind: 'GN_HASH', body: { t: 60, h: 'h-60' } });
  await a.next((m) => m.t === 'ROOM_MSG' && m.d.kind === 'GN_HASH');
  assert.equal(a.inbox.filter((m) => m.t === 'GOBNOM_DESYNC').length, 0);
  // Tick 120: divergent → höflicher Abbruch statt Weiterspielen.
  a.send('ROOM_MSG', { room, kind: 'GN_HASH', body: { t: 120, h: 'h-a' } });
  b.send('ROOM_MSG', { room, kind: 'GN_HASH', body: { t: 120, h: 'h-b' } });
  const desyncA = await a.next('GOBNOM_DESYNC');
  const desyncB = await b.next('GOBNOM_DESYNC');
  assert.equal(desyncA.d.tick, 120);
  assert.equal(desyncB.d.tick, 120);
  // Danach nimmt der Server keine Inputs mehr an.
  const rejected = await a.request('ROOM_MSG', {
    room,
    kind: 'GN_INPUT',
    body: { n: 1, upTo: 6, a: [] },
  });
  assert.equal(rejected.d.code, 'NOT_RUNNING');
});

test('Ergebnis: idempotent (ein Push pro Spieler, stabile rewardId, pending bis ACK)', async (t) => {
  const { a, b, room, codeA } = await startCoop(t);
  await startLevel(a, b, room);
  const resA = await a.request('GOBNOM_RESULT', { room, outcome: 'won', jars: 2, tick: 480 });
  assert.equal(resA.t, 'OK');
  assert.equal(resA.d.outcome, 'won');
  assert.equal(resA.d.stars, 2);
  assert.equal(resA.d.rewardId, `gnom-${room.slice(7, 15)}-${codeA}`);
  const pushA = await a.next('GOBNOM_RESULT');
  const pushB = await b.next('GOBNOM_RESULT');
  assert.equal(pushA.d.jars, 2);
  assert.equal(pushB.d.level, 3);
  // Zweiter Report (vom Partner, sogar mit anderem Inhalt) ändert NICHTS.
  const resB = await b.request('GOBNOM_RESULT', { room, outcome: 'lost', jars: 0 });
  assert.equal(resB.d.outcome, 'won', 'erster Report friert das Ergebnis ein');
  assert.equal(a.inbox.filter((m) => m.t === 'GOBNOM_RESULT').length, 0, 'kein Doppel-Push');
  // Pending bis ACK (Crash-sicher wie GoobyPal).
  assert.equal((await a.request('GOBNOM_RESULT_ACK', { rewardId: pushA.d.rewardId })).t, 'OK');
});

test('Ergebnis überlebt den Abriss: pending kommt im WELCOME nach', async (t) => {
  const { server, a, b, room, idB } = await startCoop(t);
  await startLevel(a, b, room);
  b.ws.terminate();
  await a.next('GOBNOM_PEER_DOWN');
  await a.request('GOBNOM_RESULT', { room, outcome: 'won', jars: 3 });
  await a.next('GOBNOM_RESULT');
  const b2 = await WsClient.connect(server.wsUrl);
  const welcome = await b2.hello(idB);
  t.after(() => b2.close());
  assert.equal(welcome.d.gnomPending.length, 1);
  assert.equal(welcome.d.gnomPending[0].outcome, 'won');
  assert.equal(welcome.d.gnomPending[0].stars, 3);
  const rewardId = welcome.d.gnomPending[0].rewardId;
  assert.equal((await b2.request('GOBNOM_RESULT_ACK', { rewardId })).t, 'OK');
  const b3 = await WsClient.connect(server.wsUrl);
  const welcome3 = await b3.hello(idB);
  t.after(() => b3.close());
  assert.equal(welcome3.d.gnomPending.length, 0, 'ACK räumt pending');
});

test('Partner-Cursor wird relayt (flüchtig), kaputte Koordinaten still verworfen', async (t) => {
  const { a, b, room } = await startCoop(t);
  await startLevel(a, b, room);
  a.send('ROOM_MSG', { room, kind: 'GN_CURSOR', body: { x: 480, y: 270 } });
  const cursor = await b.next((m) => m.t === 'ROOM_MSG' && m.d.kind === 'GN_CURSOR');
  assert.equal(cursor.d.body.x, 480);
  a.send('ROOM_MSG', { room, kind: 'GN_CURSOR', body: { x: 'kaputt' } });
  a.send('ROOM_MSG', { room, kind: 'GN_CURSOR', body: { x: 1, y: 2 } });
  const next = await b.next((m) => m.t === 'ROOM_MSG' && m.d.kind === 'GN_CURSOR');
  assert.equal(next.d.body.x, 1, 'der kaputte Frame wurde übersprungen');
});

test('Doppel-Session verhindert: wer schon spielt, kann nicht neu einladen/annehmen', async (t) => {
  const { a, b, codeA, codeB } = await startCoop(t);
  assert.equal((await a.request('GOBNOM_INVITE', { target: codeB })).d.code, 'GAME_RUNNING');
  assert.equal((await b.request('GOBNOM_INVITE', { target: codeA })).d.code, 'GAME_RUNNING');
});
