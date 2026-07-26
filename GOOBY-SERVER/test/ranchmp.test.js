// Ranch-Multiplayer (RW-6): Einladungen, Räume (mg: bis 4, visit: bleibt 2),
// Pose-Relay, Match-Lifecycle (Lobby→Start→Checkpoints→Ergebnis), Rejoin/DNF,
// Revanche, Fangen-Tag-Validierung, REST (Ranch-Meta, Score, Bestenliste,
// Ghost inkl. Größenlimit + Prune) und idempotente Ergebnis-Zustellung.

import test from 'node:test';
import assert from 'node:assert/strict';
import {
  startServer,
  newIdentity,
  bearer,
  WsClient,
  twoFriends,
} from './helpers.js';
import { kursHash, KURSE } from '../src/ranchmp.js';
import { loadConfig } from '../src/config.js';

const FAST = { rmpRejoinMs: 300, rmpFangenMs: 1200, rmpCountdownMs: 50 };

// Match sofort in die run-Phase zwingen (Countdown-Abkürzung für Tests,
// die keine Fangen-Uhr brauchen).
function forceRun(server, room) {
  const session = server.ctx.ranchSessions.get(room);
  session.match.startAt = Date.now() - 10;
  session.match.phase = 'run';
  return session;
}

async function acceptInvite(a, b, mode, targetCode, invite = {}) {
  await a.request('RANCH_INVITE', { target: targetCode, mode, ...invite });
  const invited = await b.next('RANCH_INVITED');
  const ready = await b.request('RANCH_ACCEPT', { from: invited.d.from });
  assert.equal(ready.t, 'RANCH_READY');
  const readyA = await a.next('RANCH_READY');
  assert.equal(readyA.d.room, ready.d.room);
  await a.request('ROOM_JOIN', { room: ready.d.room });
  await b.request('ROOM_JOIN', { room: ready.d.room });
  await a.next('ROOM_PEER_JOINED');
  return ready.d;
}

async function startRennen(server, a, b, codeB) {
  const ready = await acceptInvite(a, b, 'rennen', codeB);
  const hash = kursHash('grasbahn');
  await a.request('MG_READY', { room: ready.room, kursHash: hash });
  await b.request('MG_READY', { room: ready.room, kursHash: hash });
  const startA = await a.next('MG_START');
  const startB = await b.next('MG_START');
  assert.equal(startA.d.seed, startB.d.seed);
  assert.ok(startA.d.startAt > startA.d.serverNow, 'Countdown liegt in der Zukunft');
  forceRun(server, ready.room);
  return ready;
}

function pose(client, room, x, z, poseSeq, extra = {}) {
  client.send('MG_POSE', {
    room,
    p: [x, 0, z],
    yaw: 0,
    speed: 8,
    gait: 2,
    anim: 'trab',
    jump: false,
    poseSeq,
    ...extra,
  });
}

// Alle Checkpoints des Kurses der Reihe nach melden. mitPosen=false lässt
// die Pose weg (ehrliche Läufe im Testtempo würden sonst als Teleport gelten).
async function durchfahren(client, room, kurs = 'grasbahn', baseSeq = 100, mitPosen = true) {
  const cps = KURSE[kurs].checkpoints;
  for (let i = 0; i < cps.length; i++) {
    if (mitPosen) pose(client, room, cps[i][0], cps[i][1], baseSeq + i);
    const res = await client.request('MG_EVENT', { room, kind: 'checkpoint', idx: i });
    assert.equal(res.t, 'OK', `Checkpoint ${i} akzeptiert`);
  }
}

test('RANCH_INVITE: nur Freunde, nur online, gültiger Modus/Kurs', async (t) => {
  const { server, a, b, codeA, codeB } = await twoFriends(t);
  const bad = await a.request('RANCH_INVITE', { target: codeB, mode: 'quatsch' });
  assert.equal(bad.d.code, 'BAD_MODE');
  const badKurs = await a.request('RANCH_INVITE', { target: codeB, mode: 'rennen', kurs: 'nix' });
  assert.equal(badKurs.d.code, 'BAD_KURS');
  const self = await a.request('RANCH_INVITE', { target: codeA, mode: 'besuch' });
  assert.equal(self.d.code, 'SELF');

  // Fremder (nicht befreundet):
  const c = await WsClient.connect(server.wsUrl);
  t.after(() => c.close());
  const welcomeC = await c.hello(newIdentity('Cleo', 'Flocke'));
  const stranger = await a.request('RANCH_INVITE', { target: welcomeC.d.friendCode, mode: 'besuch' });
  assert.equal(stranger.d.code, 'NOT_FRIENDS');

  const ok = await a.request('RANCH_INVITE', { target: codeB, mode: 'besuch' });
  assert.equal(ok.t, 'OK');
  const invited = await b.next('RANCH_INVITED');
  assert.equal(invited.d.mode, 'besuch');
  assert.equal(invited.d.expiresInMs, 30000);
});

test('Besuch: Accept → RANCH_READY mit Ranch-rev, POS/GESTE-Relay, Ende bei Leave', async (t) => {
  const { server, a, b, idA, codeA, codeB } = await twoFriends(t);
  // Host lädt vorher seine Ranch-Metadaten hoch.
  const put = await fetch(`${server.url}/api/ranch`, {
    method: 'PUT',
    headers: { authorization: bearer(idA), 'content-type': 'application/json' },
    body: JSON.stringify({
      ausbau: { stall: 2 },
      pferde: [{ name: 'Puschel', rasse: 'haflinger', level: 3 }],
    }),
  });
  assert.equal((await put.json()).rev, 1);

  const ready = await acceptInvite(a, b, 'besuch', codeB);
  assert.equal(ready.rev, 1);
  assert.equal(ready.host, codeA);

  // Pose-Relay über MG_POSE (Gast sieht Host).
  pose(a, ready.room, 1, 2, 1);
  const peer = await b.next('MG_PEER_POSE');
  assert.equal(peer.d.from, codeA);
  assert.deepEqual(peer.d.p, [1, 0, 2]);

  // Geste (streicheln/füttern/Herz) läuft als generisches ROOM_MSG-Relay.
  b.send('ROOM_MSG', { room: ready.room, kind: 'GESTE', body: { art: 'streicheln', ziel: 'Puschel' } });
  const geste = await a.next('ROOM_MSG');
  assert.equal(geste.d.kind, 'GESTE');
  assert.equal(geste.d.body.art, 'streicheln');

  // Gast geht → Besuch endet für den Host.
  await b.request('ROOM_LEAVE', { room: ready.room });
  const ended = await a.next('RANCH_ENDED');
  assert.equal(ended.d.by, codeB);
  assert.equal(server.ctx.ranchSessions.size, 0);
});

test('Ranch-Meta REST: Auth Pflicht, nur Freunde, Größenlimit', async (t) => {
  const { server, idA, codeA } = await twoFriends(t);
  const noAuth = await fetch(`${server.url}/api/ranch/${codeA}`);
  assert.equal(noAuth.status, 401);

  const idC = newIdentity('Cleo');
  const c = await WsClient.connect(server.wsUrl);
  t.after(() => c.close());
  await c.hello(idC);
  await fetch(`${server.url}/api/ranch`, {
    method: 'PUT',
    headers: { authorization: bearer(idA), 'content-type': 'application/json' },
    body: JSON.stringify({ ausbau: { stall: 1 } }),
  });
  const foreign = await fetch(`${server.url}/api/ranch/${codeA}`, {
    headers: { authorization: bearer(idC) },
  });
  assert.equal(foreign.status, 403);

  const tooBig = await fetch(`${server.url}/api/ranch`, {
    method: 'PUT',
    headers: { authorization: bearer(idA), 'content-type': 'application/json' },
    body: JSON.stringify({ blob: 'x'.repeat(17 * 1024) }),
  });
  assert.equal(tooBig.status, 413, 'Größenlimit greift');
});

test('mg:-Räume erlauben 4 Mitglieder, Nachladen in offene Gruppe, dann ROOM_FULL', async (t) => {
  const server = await startServer();
  t.after(() => server.stop());
  const clients = [];
  const codes = [];
  for (const name of ['Anna', 'Ben', 'Cleo', 'Dino', 'Emil']) {
    const c = await WsClient.connect(server.wsUrl);
    t.after(() => c.close());
    const w = await c.hello(newIdentity(name));
    clients.push(c);
    codes.push(w.d.friendCode);
  }
  // Alle mit Anna befreunden.
  for (let i = 1; i < clients.length; i++) {
    await clients[0].request('FRIEND_REQUEST', { target: codes[i] });
    await clients[i].next('FRIEND_REQUEST_INCOMING');
    await clients[i].request('FRIEND_ACCEPT', { target: codes[0] });
    await clients[0].next('FRIEND_ADDED');
  }
  // Ausritt: Anna lädt B, C, D ein → 4 im Raum; E scheitert an ROOM_FULL.
  await clients[0].request('RANCH_INVITE', { target: codes[1], mode: 'ausritt' });
  const inv = await clients[1].next('RANCH_INVITED');
  const ready = await clients[1].request('RANCH_ACCEPT', { from: inv.d.from });
  const room = ready.d.room;
  await clients[0].next('RANCH_READY');
  await clients[0].request('ROOM_JOIN', { room });
  await clients[1].request('ROOM_JOIN', { room });
  for (const i of [2, 3]) {
    await clients[0].request('RANCH_INVITE', { target: codes[i], mode: 'ausritt' });
    const invI = await clients[i].next('RANCH_INVITED');
    const readyI = await clients[i].request('RANCH_ACCEPT', { from: invI.d.from });
    assert.equal(readyI.d.room, room, 'Nachlader landen im selben Raum');
    await clients[i].request('ROOM_JOIN', { room });
  }
  assert.equal(server.ctx.rooms.get(room).members.size, 4);
  const full = await clients[0].request('RANCH_INVITE', { target: codes[4], mode: 'ausritt' });
  assert.equal(full.d.code, 'ROOM_FULL');
});

test('MG_POSE: Relay an alle Peers, poseSeq monoton, Fremde still verworfen', async (t) => {
  const { server, a, b, codeB } = await twoFriends(t);
  const ready = await acceptInvite(a, b, 'ausritt', codeB);
  pose(a, ready.room, 5, 5, 10);
  const first = await b.next('MG_PEER_POSE');
  assert.equal(first.d.poseSeq, 10);
  // Veraltete Sequenz → still verworfen.
  pose(a, ready.room, 6, 6, 9);
  pose(a, ready.room, 7, 7, 11);
  const second = await b.next('MG_PEER_POSE');
  assert.equal(second.d.poseSeq, 11, 'poseSeq 9 wurde übersprungen');

  // Nicht-Mitglied: kein Relay, keine Antwort (silent drop).
  const c = await WsClient.connect(server.wsUrl);
  t.after(() => c.close());
  await c.hello(newIdentity('Cleo'));
  pose(c, ready.room, 1, 1, 1);
  pose(a, ready.room, 8, 8, 12);
  const third = await b.next('MG_PEER_POSE');
  assert.equal(third.d.poseSeq, 12, 'Fremd-Pose kam nie an');
});

test('Rennen: Checkpoint-Reihenfolge strikt, Testtempo → unranked, Pending+ACK', async (t) => {
  const { server, a, b, idA, codeB } = await twoFriends(t);
  const ready = await startRennen(server, a, b, codeB);

  // Falsche Reihenfolge wird abgelehnt.
  const wrong = await a.request('MG_EVENT', { room: ready.room, kind: 'checkpoint', idx: 3 });
  assert.equal(wrong.d.code, 'BAD_CHECKPOINT');
  // Ziel ohne Checkpoints ebenso.
  const early = await a.request('MG_EVENT', { room: ready.room, kind: 'finish' });
  assert.equal(early.d.code, 'BAD_CHECKPOINT');

  await durchfahren(a, ready.room);
  const finA = await a.request('MG_EVENT', { room: ready.room, kind: 'finish' });
  assert.equal(finA.d.rank, 1);
  assert.ok(finA.d.timeMs > 0);

  await durchfahren(b, ready.room, 'grasbahn', 500);
  const finB = await b.request('MG_EVENT', { room: ready.room, kind: 'finish' });
  assert.equal(finB.d.rank, 2);

  const resultA = await a.next('MG_RESULT');
  assert.equal(resultA.d.rank, 1);
  assert.equal(resultA.d.ranked, false, 'Segmentzeit unterschritten → unranked (Testtempo)');
  assert.ok(resultA.d.rewardId.startsWith('rmp-'));
  assert.equal(resultA.d.results.length, 2);

  // ACK räumt Pending ab; WELCOME liefert es vorher erneut (Reconnect).
  const again = await WsClient.connect(server.wsUrl);
  t.after(() => again.close());
  const welcome = await again.hello(idA);
  assert.equal(welcome.d.rmpPending.length, 1);
  assert.equal(welcome.d.rmpPending[0].rewardId, resultA.d.rewardId);
  await again.request('MG_RESULT_ACK', { rewardId: resultA.d.rewardId });
  const again2 = await WsClient.connect(server.wsUrl);
  t.after(() => again2.close());
  const welcome2 = await again2.hello(idA);
  assert.equal(welcome2.d.rmpPending.length, 0, 'ACK ist persistiert');
});

test('Rennen ehrlich gefahren: ranked-Ergebnis (Serverzeit) + Score in Bestenliste', async (t) => {
  const { server, a, b, idA, codeA, codeB } = await twoFriends(t);
  const ready = await startRennen(server, a, b, codeB);
  const session = server.ctx.ranchSessions.get(ready.room);
  // Startzeit weit zurückstellen (simulierter langer Lauf) + Segmentzeit
  // für das Testtempo neutralisieren. Poses lassen wir weg (ein ehrlicher
  // Läufer im Zeitraffer sähe sonst wie ein Teleporter aus).
  session.match.startAt = Date.now() - 60_000;
  const orig = KURSE.grasbahn.minSegmentMs;
  KURSE.grasbahn.minSegmentMs = 0;
  t.after(() => {
    KURSE.grasbahn.minSegmentMs = orig;
  });

  await durchfahren(a, ready.room, 'grasbahn', 100, false);
  await a.request('MG_EVENT', { room: ready.room, kind: 'finish' });
  await durchfahren(b, ready.room, 'grasbahn', 500, false);
  await b.request('MG_EVENT', { room: ready.room, kind: 'finish' });
  const resultA = await a.next('MG_RESULT');
  assert.equal(resultA.d.ranked, true);
  assert.ok(resultA.d.zeitMs >= 60_000, 'Zielzeit ist Serverzeit seit startAt');

  const lb = await fetch(`${server.url}/api/rmp/leaderboard/grasbahn`, {
    headers: { authorization: bearer(idA) },
  });
  const lbData = await lb.json();
  assert.equal(lbData.entries.length, 2);
  assert.equal(lbData.entries[0].friendCode, codeA);
});

test('Pose-Plausibilität: Teleport im Rennen macht den Lauf unranked', async (t) => {
  const { server, a, b, codeA, codeB } = await twoFriends(t);
  const ready = await startRennen(server, a, b, codeB);
  pose(a, ready.room, 0, 0, 1);
  await new Promise((r) => setTimeout(r, 60));
  pose(a, ready.room, 500, 0, 2); // 500 m in ~60 ms
  await new Promise((r) => setTimeout(r, 50));
  const session = server.ctx.ranchSessions.get(ready.room);
  assert.ok(session.match.unranked.has(codeA));
});

test('Verbindungsabriss im Rennen: PEER_DOWN, Rejoin-Fenster, DNF, faires Ergebnis', async (t) => {
  const { server, a, b, codeB } = await twoFriends(t, { cfg: FAST });
  const ready = await startRennen(server, a, b, codeB);

  // B reißt ab (harter Socket-Kill = disconnect).
  b.ws.terminate();
  const down = await a.next('MG_PEER_DOWN');
  assert.equal(down.d.friendCode, codeB);
  assert.equal(down.d.waitMs, FAST.rmpRejoinMs);

  // A fährt fertig — Match wartet auf das Rejoin-Fenster von B.
  await durchfahren(a, ready.room);
  await a.request('MG_EVENT', { room: ready.room, kind: 'finish' });

  // Fenster läuft ab → B ist DNF, Ergebnis kommt trotzdem (fair gewertet).
  const dnfState = await a.next((m) => m.t === 'MG_STATE' && m.d.dnf, 3000);
  assert.equal(dnfState.d.dnf.friendCode, codeB);
  const result = await a.next('MG_RESULT');
  assert.equal(result.d.rank, 1);
  const rowB = result.d.results.find((r) => r.friendCode === codeB);
  assert.equal(rowB.dnf, true);
  assert.equal(rowB.ranked, false);
});

test('Rejoin innerhalb des Fensters: MG_RESUME + Snapshot, Spiel läuft weiter', async (t) => {
  const { server, a, b, idB, codeA, codeB } = await twoFriends(t, {
    cfg: { rmpRejoinMs: 5000 },
  });
  const ready = await startRennen(server, a, b, codeB);
  await durchfahren(a, ready.room, 'grasbahn', 100);

  b.ws.terminate();
  await a.next('MG_PEER_DOWN');

  const b2 = await WsClient.connect(server.wsUrl);
  t.after(() => b2.close());
  await b2.hello(idB);
  const snap = await b2.request('MG_RESUME', { room: ready.room });
  assert.equal(snap.t, 'MG_SNAPSHOT');
  assert.equal(snap.d.phase, 'run');
  assert.equal(snap.d.progress[codeA], KURSE.grasbahn.checkpoints.length);
  await b2.request('ROOM_JOIN', { room: ready.room });
  const up = await a.next('MG_PEER_UP');
  assert.equal(up.d.friendCode, codeB);

  // B kann weiterspielen und normal finishen.
  await durchfahren(b2, ready.room, 'grasbahn', 900);
  const finB = await b2.request('MG_EVENT', { room: ready.room, kind: 'finish' });
  assert.equal(finB.t, 'OK');
});

test('Revanche: beide wollen → frisches Match, einer geht → DECLINED', async (t) => {
  const { server, a, b, codeA, codeB } = await twoFriends(t);
  const ready = await startRennen(server, a, b, codeB);
  const session = server.ctx.ranchSessions.get(ready.room);
  session.match.startAt = Date.now() - 30_000;
  await durchfahren(a, ready.room);
  await a.request('MG_EVENT', { room: ready.room, kind: 'finish' });
  await durchfahren(b, ready.room, 'grasbahn', 500);
  await b.request('MG_EVENT', { room: ready.room, kind: 'finish' });
  await a.next('MG_RESULT');
  await b.next('MG_RESULT');

  const wait = await a.request('RMP_REMATCH', { room: ready.room });
  assert.equal(wait.d.waiting, true);
  const waitPush = await b.next('RMP_REMATCH_WAIT');
  assert.equal(waitPush.d.friendCode, codeA);
  const readyB = await b.request('RMP_REMATCH', { room: ready.room });
  assert.equal(readyB.t, 'RANCH_READY');
  assert.notEqual(readyB.d.room, ready.room, 'Revanche = frischer Raum');
  assert.equal(readyB.d.rematch, true);
  const readyA = await a.next('RANCH_READY');
  assert.equal(readyA.d.room, readyB.d.room);
  assert.equal(server.ctx.ranchSessions.has(ready.room), false, 'alter Raum aufgeräumt');

  // Zweites Match: einer wünscht Revanche, der andere verlässt den Raum.
  const room2 = readyB.d.room;
  await a.request('ROOM_JOIN', { room: room2 });
  await b.request('ROOM_JOIN', { room: room2 });
  const hash = kursHash('grasbahn');
  await a.request('MG_READY', { room: room2, kursHash: hash });
  await b.request('MG_READY', { room: room2, kursHash: hash });
  await a.next('MG_START');
  forceRun(server, room2);
  const s2 = server.ctx.ranchSessions.get(room2);
  s2.match.startAt = Date.now() - 30_000;
  await durchfahren(a, room2);
  await a.request('MG_EVENT', { room: room2, kind: 'finish' });
  await durchfahren(b, room2, 'grasbahn', 500);
  await b.request('MG_EVENT', { room: room2, kind: 'finish' });
  await a.next('MG_RESULT');
  await a.request('RMP_REMATCH', { room: room2 });
  await b.next('RMP_REMATCH_WAIT');
  await b.request('ROOM_LEAVE', { room: room2 });
  const declined = await a.next('RMP_REMATCH_DECLINED');
  assert.equal(declined.d.friendCode, codeB);
});

test('Fangen: Server validiert Tag (Distanz, Immunität), Rundenende wertet fair', async (t) => {
  const { server, a, b, codeA, codeB } = await twoFriends(t, { cfg: FAST });
  const ready = await acceptInvite(a, b, 'fangen', codeB);
  const hash = kursHash('weide_fangen');
  await a.request('MG_READY', { room: ready.room, kursHash: hash });
  await b.request('MG_READY', { room: ready.room, kursHash: hash });
  const start = await a.next('MG_START');
  assert.ok(start.d.it === codeA || start.d.it === codeB);
  assert.ok(start.d.endsAt > start.d.startAt);
  // Countdown (50 ms) verstreichen lassen → run-Phase.
  await new Promise((r) => setTimeout(r, 120));
  const it = start.d.it;
  const itClient = it === codeA ? a : b;
  const other = it === codeA ? b : a;
  const otherCode = it === codeA ? codeB : codeA;

  // Zu weit weg → TAG_WEIT.
  pose(itClient, ready.room, -380, 90, 1);
  pose(other, ready.room, -300, 90, 1);
  await new Promise((r) => setTimeout(r, 30));
  const far = await itClient.request('MG_EVENT', { room: ready.room, kind: 'tag', target: otherCode });
  assert.equal(far.d.code, 'TAG_WEIT');
  // Nicht-Fänger darf nie taggen.
  const notIt = await other.request('MG_EVENT', { room: ready.room, kind: 'tag', target: it });
  assert.equal(notIt.d.code, 'NOT_IT');

  // Nah dran → Tag klappt, Immunität blockt den Rückschlag.
  pose(other, ready.room, -381, 91, 2);
  await new Promise((r) => setTimeout(r, 30));
  const hit = await itClient.request('MG_EVENT', { room: ready.room, kind: 'tag', target: otherCode });
  assert.equal(hit.t, 'OK');
  const state = await other.next((m) => m.t === 'MG_STATE' && m.d.tag);
  assert.equal(state.d.tag.it, otherCode);
  const back = await other.request('MG_EVENT', { room: ready.room, kind: 'tag', target: it });
  assert.equal(back.d.code, 'TAG_IMMUN');

  // Runde endet per Timer → faires Ergebnis für beide.
  const result = await a.next('MG_RESULT', 4000);
  assert.equal(result.d.results.length, 2);
  assert.ok(result.d.results.every((r) => r.rewardId));
  const winner = result.d.results.find((r) => r.rank === 1);
  assert.equal(winner.friendCode, it, 'wer kürzer Fänger war, gewinnt');
});

test('Parcours: Strafsekunden (max 1 je Tor) fließen in die Zielzeit', async (t) => {
  const { server, a, b, codeB } = await twoFriends(t);
  const ready = await acceptInvite(a, b, 'parcours', codeB);
  const hash = kursHash('hof_parcours');
  await a.request('MG_READY', { room: ready.room, kursHash: hash });
  await b.request('MG_READY', { room: ready.room, kursHash: hash });
  await a.next('MG_START');
  forceRun(server, ready.room);
  const session = server.ctx.ranchSessions.get(ready.room);
  session.match.startAt = Date.now() - 20_000;

  const s1 = await a.request('MG_EVENT', { room: ready.room, kind: 'strafe', gate: 2 });
  assert.equal(s1.d.strafenMs, 2000);
  const s2 = await a.request('MG_EVENT', { room: ready.room, kind: 'strafe', gate: 2 });
  assert.equal(s2.d.strafenMs, 2000, 'gleiches Tor zählt nur einmal');
  await durchfahren(a, ready.room, 'hof_parcours');
  const fin = await a.request('MG_EVENT', { room: ready.room, kind: 'finish' });
  assert.ok(fin.d.timeMs >= 22_000, 'Strafzeit steckt in der Zielzeit');
});

test('Score-REST: Plausibilität (Mindestzeit), Best-Only, Bestenliste sortiert', async (t) => {
  const { server, idA, idB, codeA, codeB } = await twoFriends(t);
  const post = (id, body) =>
    fetch(`${server.url}/api/rmp/score`, {
      method: 'POST',
      headers: { authorization: bearer(id), 'content-type': 'application/json' },
      body: JSON.stringify(body),
    });
  const tooFast = await post(idA, { kurs: 'grasbahn', zeitMs: 100 });
  assert.equal(tooFast.status, 400);
  const badKurs = await post(idA, { kurs: 'weide_fangen', zeitMs: 60_000 });
  assert.equal(badKurs.status, 400);
  const dev = await (await post(idA, { kurs: 'grasbahn', zeitMs: 60_000, devSession: true })).json();
  assert.equal(dev.ranked, false);

  assert.equal((await (await post(idA, { kurs: 'grasbahn', zeitMs: 61_000 })).json()).verbessert, true);
  assert.equal(
    (await (await post(idA, { kurs: 'grasbahn', zeitMs: 65_000 })).json()).verbessert,
    false,
    'langsamer überschreibt nie'
  );
  assert.equal((await (await post(idB, { kurs: 'grasbahn', zeitMs: 59_000 })).json()).verbessert, true);

  const lb = await (
    await fetch(`${server.url}/api/rmp/leaderboard/grasbahn`, {
      headers: { authorization: bearer(idA) },
    })
  ).json();
  assert.deepEqual(
    lb.entries.map((e) => e.friendCode),
    [codeB, codeA],
    'aufsteigend nach Zeit'
  );
});

test('Ghost-REST: nur bester Lauf, Größen-/Formatlimit, Freunde-Zugriff, Prune', async (t) => {
  const limits = { ...loadConfig({}).limits, ghostsPerKurs: 2 };
  const { server, idA, idB, codeA } = await twoFriends(t, { cfg: { limits } });
  const put = (id, body) =>
    fetch(`${server.url}/api/rmp/ghost/grasbahn`, {
      method: 'PUT',
      headers: { authorization: bearer(id), 'content-type': 'application/json' },
      body: JSON.stringify(body),
    });
  const samples = Array.from({ length: 60 }, (_, i) => [i, i * 2, 0.5]);
  const bad = await put(idA, { zeitMs: 60_000, rateHz: 5, samples: 'nope' });
  assert.equal(bad.status, 400);
  const tooMany = await put(idA, {
    zeitMs: 60_000,
    rateHz: 5,
    samples: Array.from({ length: 1600 }, () => [0, 0]),
  });
  assert.equal(tooMany.status, 400);

  const first = await (await put(idA, { zeitMs: 60_000, rateHz: 5, samples })).json();
  assert.equal(first.gespeichert, true);
  const slower = await (await put(idA, { zeitMs: 70_000, rateHz: 5, samples })).json();
  assert.equal(slower.gespeichert, false, 'langsamerer Ghost ersetzt den besten nie');

  // Freund darf lesen, Fremder nicht.
  const get = await (
    await fetch(`${server.url}/api/rmp/ghost/grasbahn/${codeA}`, {
      headers: { authorization: bearer(idB) },
    })
  ).json();
  assert.equal(get.wert, 60_000);
  assert.equal(get.samples.length, 60);
  const idC = newIdentity('Cleo');
  const c = await WsClient.connect(server.wsUrl);
  t.after(() => c.close());
  await c.hello(idC);
  const foreign = await fetch(`${server.url}/api/rmp/ghost/grasbahn/${codeA}`, {
    headers: { authorization: bearer(idC) },
  });
  assert.equal(foreign.status, 403);

  // Prune: Cap 2 pro Kurs — der langsamste fliegt (inkl. Blob-Datei).
  await put(idB, { zeitMs: 50_000, rateHz: 5, samples });
  const putC = await put(idC, { zeitMs: 55_000, rateHz: 5, samples });
  assert.equal((await putC.json()).gespeichert, true);
  const ghosts = server.ctx.store.collection('ranchghosts').byKurs.grasbahn;
  assert.equal(Object.keys(ghosts).length, 2, 'Prune hält das Kurs-Cap');
  assert.ok(!ghosts[codeA], 'der langsamste (60 s) wurde entfernt');
});

test('RW-5-Bestenlisten: Punkte-Richtung, Zeit-Richtung, G5-Ghost als b64', async (t) => {
  const { server, idA, idB, codeA, codeB } = await twoFriends(t);
  const post = (id, body) =>
    fetch(`${server.url}/api/rmp/score`, {
      method: 'POST',
      headers: { authorization: bearer(id), 'content-type': 'application/json' },
      body: JSON.stringify(body),
    });

  // Punkte-Disziplin (auf): größerer Wert gewinnt, kleinerer überschreibt nie.
  assert.equal((await (await post(idA, { kurs: 'rw5_springen', wert: 80 })).json()).verbessert, true);
  assert.equal((await (await post(idA, { kurs: 'rw5_springen', wert: 60 })).json()).verbessert, false);
  assert.equal((await (await post(idB, { kurs: 'rw5_springen', wert: 95 })).json()).verbessert, true);
  const lbAuf = await (
    await fetch(`${server.url}/api/rmp/leaderboard/rw5_springen`, {
      headers: { authorization: bearer(idA) },
    })
  ).json();
  assert.equal(lbAuf.richtung, 'auf');
  assert.deepEqual(
    lbAuf.entries.map((e) => e.friendCode),
    [codeB, codeA],
    'Punkte absteigend'
  );

  // Zeit-Disziplin (ab): Plausibilität mind. 3 s.
  assert.equal((await post(idA, { kurs: 'rw5_tonnen', wert: 500 })).status, 400);
  assert.equal((await (await post(idA, { kurs: 'rw5_tonnen', wert: 42_000 })).json()).verbessert, true);

  // G5-Ghost (b64, Magic "G5"): kaputtes Magic → 400; echter Blob rund-trip.
  const putGhost = (id, kurs, body) =>
    fetch(`${server.url}/api/rmp/ghost/${kurs}`, {
      method: 'PUT',
      headers: { authorization: bearer(id), 'content-type': 'application/json' },
      body: JSON.stringify(body),
    });
  const badMagic = Buffer.alloc(24, 7).toString('base64');
  assert.equal((await putGhost(idA, 'rw5_tonnen', { wert: 42_000, b64: badMagic })).status, 400);
  const g5 = Buffer.alloc(24);
  g5[0] = 0x47;
  g5[1] = 0x35;
  g5[2] = 1;
  const b64 = g5.toString('base64');
  const saved = await (await putGhost(idA, 'rw5_tonnen', { wert: 42_000, b64 })).json();
  assert.equal(saved.gespeichert, true);
  const back = await (
    await fetch(`${server.url}/api/rmp/ghost/rw5_tonnen/${codeA}`, {
      headers: { authorization: bearer(idB) },
    })
  ).json();
  assert.equal(back.b64, b64);
  assert.equal(back.wert, 42_000);
});

test('kursHash ist stabil (Client-Sync-Kontrakt) und WELCOME meldet ranchmp', async (t) => {
  assert.equal(kursHash('grasbahn'), 'grasbahn:v1:8');
  assert.equal(kursHash('hof_parcours'), 'hof_parcours:v1:8');
  assert.equal(kursHash('weide_fangen'), 'weide_fangen:v1:0');
  const server = await startServer();
  t.after(() => server.stop());
  const c = await WsClient.connect(server.wsUrl);
  t.after(() => c.close());
  const welcome = await c.hello(newIdentity('Anna'));
  assert.ok(welcome.d.features.includes('ranchmp'));
  assert.deepEqual(welcome.d.rmpPending, []);
});
