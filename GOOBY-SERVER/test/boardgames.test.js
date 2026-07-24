// Schiffe versenken: Invite/Accept/Start, Turn-Ownership serverseitig, SHOT/SHOT_RESULT-
// Paare, Tomate 1×/Spieler/Runde (Server-Regel!), Emotes, Rejoin + Forfeit.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { WsClient, twoFriends, newIdentity } from './helpers.js';

async function startBattleship(t, opts) {
  const fixture = await twoFriends(t, opts);
  const { a, b, codeA, codeB } = fixture;
  assert.equal((await a.request('BOARD_INVITE', { target: codeB, game: 'battleship' })).t, 'OK');
  const invited = await b.next('BOARD_INVITED');
  assert.equal(invited.d.from, codeA);
  assert.equal(invited.d.game, 'battleship');
  const startB = await b.request('BOARD_ACCEPT', { from: codeA });
  assert.equal(startB.t, 'BOARD_START');
  const startA = await a.next('BOARD_START');
  assert.equal(startA.d.room, startB.d.room);
  assert.equal(startA.d.first, codeA, 'der Einladende beginnt');
  assert.equal(typeof startA.d.seed, 'number');
  const room = startA.d.room;
  await a.request('ROOM_JOIN', { room });
  await b.request('ROOM_JOIN', { room });
  await a.next('ROOM_PEER_JOINED');
  return { ...fixture, room };
}

// Ein kompletter Zug: Schütze schießt, Beschossener antwortet mit Ergebnis.
async function exchange(shooter, defender, room, n, cell, hit) {
  shooter.send('ROOM_MSG', { room, kind: 'SHOT', body: { n, cell } });
  const shot = await defender.next((m) => m.t === 'ROOM_MSG' && m.d.kind === 'SHOT');
  assert.equal(shot.d.body.n, n);
  defender.send('ROOM_MSG', { room, kind: 'SHOT_RESULT', body: { n, hit, sunk: false } });
  const result = await shooter.next((m) => m.t === 'ROOM_MSG' && m.d.kind === 'SHOT_RESULT');
  assert.equal(result.d.body.hit, hit);
}

test('Turn-Relay: Züge wechseln, falscher Spieler/falsches n wird abgelehnt', async (t) => {
  const { a, b, room } = await startBattleship(t);
  // B ist NICHT dran → NOT_YOUR_TURN.
  const notYourTurn = await b.request('ROOM_MSG', { room, kind: 'SHOT', body: { n: 1, cell: 'A1' } });
  assert.equal(notYourTurn.d.code, 'NOT_YOUR_TURN');
  // A mit falscher Zugnummer → BAD_TURN_N.
  const badN = await a.request('ROOM_MSG', { room, kind: 'SHOT', body: { n: 7, cell: 'A1' } });
  assert.equal(badN.d.code, 'BAD_TURN_N');
  // Regulärer Zug 1: A schießt, B antwortet.
  await exchange(a, b, room, 1, 'B4', true);
  // Jetzt ist B dran; A darf nicht nochmal.
  const again = await a.request('ROOM_MSG', { room, kind: 'SHOT', body: { n: 2, cell: 'C1' } });
  assert.equal(again.d.code, 'NOT_YOUR_TURN');
  await exchange(b, a, room, 2, 'D5', false);
  // Wieder A.
  await exchange(a, b, room, 3, 'B5', true);
});

test('SHOT_RESULT-Ownership: nur der Beschossene, nur in der result-Phase, n muss stimmen', async (t) => {
  const { a, b, room } = await startBattleship(t);
  // Ohne offenen Schuss darf niemand ein Ergebnis schicken.
  const early = await b.request('ROOM_MSG', { room, kind: 'SHOT_RESULT', body: { n: 1, hit: true } });
  assert.equal(early.d.code, 'NOT_YOUR_TURN');
  a.send('ROOM_MSG', { room, kind: 'SHOT', body: { n: 1, cell: 'A1' } });
  await b.next((m) => m.t === 'ROOM_MSG' && m.d.kind === 'SHOT');
  // Der Schütze selbst darf das Ergebnis nicht liefern.
  const cheat = await a.request('ROOM_MSG', { room, kind: 'SHOT_RESULT', body: { n: 1, hit: true } });
  assert.equal(cheat.d.code, 'NOT_YOUR_TURN');
  // Falsches n vom Beschossenen.
  const badN = await b.request('ROOM_MSG', { room, kind: 'SHOT_RESULT', body: { n: 9, hit: true } });
  assert.equal(badN.d.code, 'BAD_TURN_N');
});

test('Tomate: serverseitig max 1×/Spieler/Runde, nächste Runde wieder erlaubt', async (t) => {
  const { a, b, room } = await startBattleship(t);
  // Runde 0: A wirft eine Tomate — ok; zweite sofort → TOMATO_LIMIT.
  a.send('ROOM_MSG', { room, kind: 'TOMATO', body: {} });
  const splat = await b.next((m) => m.t === 'ROOM_MSG' && m.d.kind === 'TOMATO');
  assert.equal(splat.d.from.friendCode !== undefined, true);
  const spam = await a.request('ROOM_MSG', { room, kind: 'TOMATO', body: {} });
  assert.equal(spam.d.code, 'TOMATO_LIMIT');
  // B darf in Runde 0 auch genau einmal.
  b.send('ROOM_MSG', { room, kind: 'TOMATO', body: {} });
  await a.next((m) => m.t === 'ROOM_MSG' && m.d.kind === 'TOMATO');
  assert.equal((await b.request('ROOM_MSG', { room, kind: 'TOMATO', body: {} })).d.code, 'TOMATO_LIMIT');
  // Runde abschließen: beide Spieler je ein SHOT/SHOT_RESULT-Paar.
  await exchange(a, b, room, 1, 'A1', false);
  await exchange(b, a, room, 2, 'B2', true);
  // Runde 1: Tomate wieder erlaubt (genau 1×) — Erfolg = Relay kommt bei B an.
  a.send('ROOM_MSG', { room, kind: 'TOMATO', body: {} });
  await b.next((m) => m.t === 'ROOM_MSG' && m.d.kind === 'TOMATO');
  assert.equal((await a.request('ROOM_MSG', { room, kind: 'TOMATO', body: {} })).d.code, 'TOMATO_LIMIT');
});

test('Emotes werden frei relayt (inkl. History)', async (t) => {
  const { a, b, room } = await startBattleship(t);
  a.send('ROOM_MSG', { room, kind: 'EMOTE', body: { id: 'dance' } });
  const emote = await b.next((m) => m.t === 'ROOM_MSG' && m.d.kind === 'EMOTE');
  assert.equal(emote.d.body.id, 'dance');
});

test('Disconnect + Rejoin ≤ Fenster: BOARD_RESUME mit History, Spiel geht weiter', async (t) => {
  const { server, a, b, room, idB, codeB } = await startBattleship(t);
  await exchange(a, b, room, 1, 'A1', true);
  a.send('ROOM_MSG', { room, kind: 'EMOTE', body: { id: 'angry' } });
  await b.next((m) => m.t === 'ROOM_MSG' && m.d.kind === 'EMOTE');
  // B reißt die Verbindung ab (Disconnect, kein ROOM_LEAVE).
  b.ws.terminate();
  await a.next('ROOM_PEER_LEFT');
  // B kommt zurück, joint denselben Room → BOARD_RESUME.
  const b2 = await WsClient.connect(server.wsUrl);
  await b2.hello(idB);
  t.after(() => b2.close());
  await b2.request('ROOM_JOIN', { room });
  const resume = await b2.next('BOARD_RESUME');
  assert.equal(resume.d.game, 'battleship');
  assert.equal(resume.d.n, 2);
  assert.equal(resume.d.turn, codeB, 'B ist nach Zug 1 dran');
  assert.deepEqual(
    resume.d.history.map((h) => h.kind),
    ['SHOT', 'SHOT_RESULT', 'EMOTE']
  );
  // Spiel läuft weiter: B schießt Zug 2.
  await exchange(b2, a, room, 2, 'C3', false);
});

test('Rejoin-Fenster abgelaufen → BOARD_FORFEIT an den Verbliebenen', async (t) => {
  const { a, b, room, codeA } = await startBattleship(t, {
    env: { GOOBY_BOARD_REJOIN_MS: '60' },
  });
  b.ws.terminate();
  await a.next('ROOM_PEER_LEFT');
  const forfeit = await a.next('BOARD_FORFEIT');
  assert.equal(forfeit.d.room, room);
  assert.equal(forfeit.d.winner, codeA);
});

test('Bewusstes Verlassen → sofortiges Forfeit', async (t) => {
  const { a, b, room, codeA } = await startBattleship(t);
  await b.request('ROOM_LEAVE', { room });
  const forfeit = await a.next('BOARD_FORFEIT');
  assert.equal(forfeit.d.winner, codeA);
});

test('Fremde kommen nicht in board:-Rooms; Invite braucht Freundschaft', async (t) => {
  const { server, a, room } = await startBattleship(t);
  const c = await WsClient.connect(server.wsUrl);
  const wc = await c.hello(newIdentity('Cleo'));
  t.after(() => c.close());
  const denied = await c.request('ROOM_JOIN', { room });
  assert.equal(denied.d.code, 'BAD_ROOM');
  const invite = await a.request('BOARD_INVITE', { target: wc.d.friendCode, game: 'battleship' });
  assert.equal(invite.d.code, 'NOT_FRIENDS');
  const badGame = await a.request('BOARD_INVITE', { target: wc.d.friendCode, game: 'poker' });
  assert.equal(badGame.d.code, 'BAD_MESSAGE');
});
