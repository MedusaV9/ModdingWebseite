// RW-6 Zwei-Client-Smoke (DoD-Beleg): startet den ECHTEN Server als eigenen
// Prozess (node server.js) und fährt mit zwei WebSocket-Clients den kompletten
// Ranch-Multiplayer-Pfad ab:
//
//   1. HELLO + Freundschaft (Anna ↔ Ben)
//   2. Ranch-Besuch: Meta-Upload, Einladung, Pose-Relay, Gesten (streicheln/Herz)
//   3. Rennen auf der Grasbahn: Lobby → MG_READY → Countdown → ehrliche Fahrt
//      (10-Hz-Posen, plausible Geschwindigkeit) → Checkpoints → Ziel → Ergebnis
//   4. Verbindungsabbruch: Ben reißt mitten im Rennen ab (Socket-Kill),
//      Anna sieht MG_PEER_DOWN, Ben rejoint (MG_RESUME + Snapshot) und
//      fährt zu Ende — Ergebnis wird normal zugestellt
//   5. Revanche: beide RMP_REMATCH → frisches Match, komplett gefahren
//   6. Bestenliste + Ghost-Ablage per REST geprüft
//
// Aufruf: node tools/smoke-rmp.mjs   (aus GOOBY-SERVER/, beendet sich selbst)
// Exit-Code 0 = alles bestanden. Ausgabe ist das Smoke-Log (Beleg).

import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { WsClient, newIdentity, bearer } from '../test/helpers.js';
import { KURSE, kursHash } from '../src/ranchmp.js';

const ROOT = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const T0 = Date.now();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function log(wer, text) {
  const t = ((Date.now() - T0) / 1000).toFixed(2).padStart(6);
  console.log(`[${t}s] [${wer}] ${text}`);
}

// ---- Server als echter Kind-Prozess --------------------------------------

async function serverStarten() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'gooby-smoke-rw6-'));
  const child = spawn(process.execPath, ['server.js'], {
    cwd: ROOT,
    env: { ...process.env, PORT: '0', DATA_DIR: dataDir },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let port = null;
  child.stdout.on('data', (buf) => {
    for (const line of buf.toString('utf8').split('\n')) {
      if (!line.trim()) continue;
      log('server', line.trim());
      const m = line.match(/läuft auf Port (\d+)/);
      if (m) port = Number(m[1]);
    }
  });
  child.stderr.on('data', (buf) => log('server!', buf.toString('utf8').trim()));
  for (let i = 0; i < 100 && port === null; i++) await sleep(50);
  assert.ok(port, 'Server-Port aus dem Log gelesen');
  for (let i = 0; i < 100; i++) {
    try {
      const res = await fetch(`http://127.0.0.1:${port}/health`);
      if ((await res.json()).ok) break;
    } catch {
      await sleep(50);
    }
  }
  log('smoke', `Server läuft (separater Prozess, pid=${child.pid}, Port ${port})`);
  return { child, port, dataDir, url: `http://127.0.0.1:${port}`, wsUrl: `ws://127.0.0.1:${port}/ws` };
}

// ---- Ehrliche Fahrt: 10-Hz-Posen, ~14 m/s (Galopp), Checkpoints in Ordnung -

async function fahreKurs(client, wer, room, zaehler, { von = 0, bis = null, startPos = null } = {}) {
  const cps = KURSE.grasbahn.checkpoints;
  const ende = bis ?? cps.length;
  const speed = 14; // < 16*1.3 m/s Plausibilitätsgrenze
  let pos = startPos ?? [cps[0][0], cps[0][1] - 20];
  for (let i = von; i < ende; i++) {
    const ziel = cps[i];
    for (;;) {
      const dx = ziel[0] - pos[0];
      const dz = ziel[1] - pos[1];
      const dist = Math.hypot(dx, dz);
      const schritt = speed / 10;
      pos = dist <= schritt ? [ziel[0], ziel[1]] : [pos[0] + (dx / dist) * schritt, pos[1] + (dz / dist) * schritt];
      client.send('MG_POSE', {
        room,
        p: [pos[0], 0, pos[1]],
        yaw: Math.atan2(dx, dz),
        speed,
        gait: 3,
        anim: 'galopp',
        jump: false,
        poseSeq: ++zaehler.seq,
      });
      await sleep(100);
      if (dist <= schritt) break;
    }
    const res = await client.request('MG_EVENT', { room, kind: 'checkpoint', idx: i }, 5000);
    assert.equal(res.t, 'OK', `${wer}: Checkpoint ${i} akzeptiert`);
    log(wer, `Checkpoint ${i + 1}/${cps.length} genommen`);
  }
  return pos;
}

async function aufStartWarten(wer, client) {
  const start = await client.next('MG_START', 15_000);
  const warten = Math.max(0, start.d.startAt - start.d.serverNow) + 150;
  log(wer, `MG_START: seed=${start.d.seed}, Countdown ${warten} ms`);
  await sleep(warten);
  return start.d;
}

// ---- Szenario --------------------------------------------------------------

async function main() {
  const server = await serverStarten();
  const idA = newIdentity('Anna', 'Flausch');
  const idB = newIdentity('Ben', 'Knöpfchen');

  // -- 1. Verbinden + Freundschaft ------------------------------------------
  const a = await WsClient.connect(server.wsUrl);
  const b = await WsClient.connect(server.wsUrl);
  const wA = await a.hello(idA);
  const wB = await b.hello(idB);
  assert.ok(wA.d.features.includes('ranchmp'), 'WELCOME meldet ranchmp-Feature');
  const codeA = wA.d.friendCode;
  const codeB = wB.d.friendCode;
  log('A', `WELCOME als ${codeA} (features: ${wA.d.features.join(',')})`);
  log('B', `WELCOME als ${codeB}`);
  await a.request('FRIEND_REQUEST', { target: codeB });
  await b.next('FRIEND_REQUEST_INCOMING');
  await b.request('FRIEND_ACCEPT', { target: codeA });
  await a.next('FRIEND_ADDED');
  await b.next('FRIEND_ADDED');
  log('smoke', 'Anna und Ben sind befreundet');

  // -- 2. Ranch-Besuch --------------------------------------------------------
  const put = await fetch(`${server.url}/api/ranch`, {
    method: 'PUT',
    headers: { authorization: bearer(idA), 'content-type': 'application/json' },
    body: JSON.stringify({
      ausbau: { stall: 2, koppel: 1 },
      pferde: [
        { name: 'Puschel', rasse: 'haflinger', level: 4 },
        { name: 'Sturmwind', rasse: 'araber', level: 7 },
      ],
      trophaeen: ['rw5_rennen_gold'],
    }),
  });
  assert.equal((await put.json()).rev, 1);
  log('A', 'Ranch-Metadaten hochgeladen (rev 1)');

  await a.request('RANCH_INVITE', { target: codeB, mode: 'besuch' });
  const invited = await b.next('RANCH_INVITED');
  log('B', `RANCH_INVITED von ${invited.d.from} (mode=${invited.d.mode})`);
  const readyBesuch = await b.request('RANCH_ACCEPT', { from: invited.d.from });
  assert.equal(readyBesuch.t, 'RANCH_READY');
  await a.next('RANCH_READY');
  const besuchRoom = readyBesuch.d.room;
  await a.request('ROOM_JOIN', { room: besuchRoom });
  await b.request('ROOM_JOIN', { room: besuchRoom });
  log('smoke', `Besuch läuft in ${besuchRoom} (Ranch-rev ${readyBesuch.d.rev})`);

  const meta = await fetch(`${server.url}/api/ranch/${codeA}`, { headers: { authorization: bearer(idB) } });
  const metaData = await meta.json();
  assert.equal(metaData.meta.pferde.length, 2);
  log('B', `sieht Annas Ranch: ${metaData.meta.pferde.map((p) => p.name).join(' + ')}, Stall-Stufe ${metaData.meta.ausbau.stall}`);

  a.send('MG_POSE', { room: besuchRoom, p: [12, 0, -3], yaw: 1.2, speed: 0, gait: 0, anim: 'idle', jump: false, poseSeq: 1 });
  const peerPose = await b.next('MG_PEER_POSE');
  assert.equal(peerPose.d.from, codeA);
  log('B', `sieht Annas Gooby bei [${peerPose.d.p}] (Pose-Relay ok)`);

  b.send('ROOM_MSG', { room: besuchRoom, kind: 'GESTE', body: { art: 'streicheln', ziel: 'Puschel' } });
  const geste = await a.next('ROOM_MSG');
  assert.equal(geste.d.body.art, 'streicheln');
  log('A', `Gast streichelt ${geste.d.body.ziel} — Geste kam an`);
  b.send('ROOM_MSG', { room: besuchRoom, kind: 'GESTE', body: { art: 'herz' } });
  const herz = await a.next('ROOM_MSG');
  assert.equal(herz.d.body.art, 'herz');
  log('A', 'Herz-Reaktion vom Gast empfangen');

  await b.request('ROOM_LEAVE', { room: besuchRoom });
  const ended = await a.next('RANCH_ENDED');
  assert.equal(ended.d.by, codeB);
  log('smoke', 'Besuch sauber beendet (RANCH_ENDED)');

  // -- 3.+4. Rennen mit Verbindungsabbruch + Rejoin ---------------------------
  await a.request('RANCH_INVITE', { target: codeB, mode: 'rennen', kurs: 'grasbahn' });
  const invited2 = await b.next('RANCH_INVITED');
  const readyRennen = await b.request('RANCH_ACCEPT', { from: invited2.d.from });
  await a.next('RANCH_READY');
  const rennRoom = readyRennen.d.room;
  await a.request('ROOM_JOIN', { room: rennRoom });
  await b.request('ROOM_JOIN', { room: rennRoom });
  log('smoke', `Rennen-Lobby ${rennRoom} (Kurs grasbahn, ${KURSE.grasbahn.checkpoints.length} Checkpoints)`);

  const hash = kursHash('grasbahn');
  await a.request('MG_READY', { room: rennRoom, kursHash: hash });
  await b.request('MG_READY', { room: rennRoom, kursHash: hash });
  log('smoke', `beide MG_READY (kursHash=${hash})`);
  const [startA] = await Promise.all([aufStartWarten('A', a), aufStartWarten('B', b)]);

  const zA = { seq: 1000 };
  const zB = { seq: 1000 };
  const fahrtA = (async () => {
    await fahreKurs(a, 'A', rennRoom, zA);
    const fin = await a.request('MG_EVENT', { room: rennRoom, kind: 'finish' }, 5000);
    assert.equal(fin.d.rank, 1, 'Anna zuerst im Ziel');
    log('A', `ZIEL! Rang ${fin.d.rank}, Zeit ${fin.d.timeMs} ms`);
  })();

  const fahrtB = (async () => {
    const pos = await fahreKurs(b, 'B', rennRoom, zB, { bis: 2 });
    log('B', 'VERBINDUNGSABBRUCH (harter Socket-Kill mitten im Rennen)');
    b.ws.terminate();
    await sleep(2000); // offline-Phase
    const b2 = await WsClient.connect(server.wsUrl);
    await b2.hello(idB);
    const snap = await b2.request('MG_RESUME', { room: rennRoom }, 5000);
    assert.equal(snap.t, 'MG_SNAPSHOT');
    assert.equal(snap.d.phase, 'run');
    log('B', `Rejoin: MG_SNAPSHOT phase=${snap.d.phase}, Fortschritt=${JSON.stringify(snap.d.progress)}`);
    await b2.request('ROOM_JOIN', { room: rennRoom });
    await fahreKurs(b2, 'B', rennRoom, zB, { von: 2, startPos: pos });
    const fin = await b2.request('MG_EVENT', { room: rennRoom, kind: 'finish' }, 5000);
    assert.equal(fin.t, 'OK');
    log('B', `ZIEL nach Rejoin! Rang ${fin.d.rank}, Zeit ${fin.d.timeMs} ms`);
    return b2;
  })();

  const down = await a.next('MG_PEER_DOWN', 30_000);
  assert.equal(down.d.friendCode, codeB);
  log('A', `sieht MG_PEER_DOWN (${down.d.friendCode}, Rejoin-Fenster ${down.d.waitMs} ms)`);
  const up = await a.next('MG_PEER_UP', 30_000);
  log('A', `sieht MG_PEER_UP (${up.d.friendCode} ist zurück)`);

  await fahrtA;
  const b2 = await fahrtB;
  const resultA = await a.next('MG_RESULT', 10_000);
  const resultB = await b2.next('MG_RESULT', 10_000);
  assert.equal(resultA.d.results.length, 2);
  for (const r of resultA.d.results) {
    log('smoke', `Ergebnis: ${r.friendCode} Rang ${r.rank ?? '-'} zeit=${r.zeitMs ?? '-'}ms ranked=${r.ranked} dnf=${!!r.dnf}`);
  }
  await a.request('MG_RESULT_ACK', { rewardId: resultA.d.rewardId });
  await b2.request('MG_RESULT_ACK', { rewardId: resultB.d.rewardId });
  log('smoke', 'Rennen 1 fertig, Ergebnisse per ACK quittiert');

  // -- 5. Revanche ------------------------------------------------------------
  const wait = await a.request('RMP_REMATCH', { room: rennRoom });
  assert.equal(wait.d.waiting, true);
  await b2.next('RMP_REMATCH_WAIT');
  log('B', 'sieht RMP_REMATCH_WAIT — Anna will Revanche');
  const ready2 = await b2.request('RMP_REMATCH', { room: rennRoom });
  assert.equal(ready2.t, 'RANCH_READY');
  assert.notEqual(ready2.d.room, rennRoom, 'Revanche = frischer Raum');
  await a.next('RANCH_READY');
  const room2 = ready2.d.room;
  await a.request('ROOM_JOIN', { room: room2 });
  await b2.request('ROOM_JOIN', { room: room2 });
  log('smoke', `Revanche-Lobby ${room2}`);
  await a.request('MG_READY', { room: room2, kursHash: hash });
  await b2.request('MG_READY', { room: room2, kursHash: hash });
  await Promise.all([aufStartWarten('A', a), aufStartWarten('B', b2)]);

  const zA2 = { seq: 5000 };
  const zB2 = { seq: 5000 };
  await Promise.all([
    (async () => {
      await fahreKurs(a, 'A', room2, zA2);
      const fin = await a.request('MG_EVENT', { room: room2, kind: 'finish' }, 5000);
      log('A', `Revanche-Ziel: Rang ${fin.d.rank}, ${fin.d.timeMs} ms`);
    })(),
    (async () => {
      await fahreKurs(b2, 'B', room2, zB2);
      const fin = await b2.request('MG_EVENT', { room: room2, kind: 'finish' }, 5000);
      log('B', `Revanche-Ziel: Rang ${fin.d.rank}, ${fin.d.timeMs} ms`);
    })(),
  ]);
  const result2 = await a.next('MG_RESULT', 10_000);
  const result2B = await b2.next('MG_RESULT', 10_000);
  for (const r of result2.d.results) {
    log('smoke', `Revanche-Ergebnis: ${r.friendCode} Rang ${r.rank} zeit=${r.zeitMs}ms ranked=${r.ranked}`);
  }
  assert.ok(result2.d.results.every((r) => r.ranked === true), 'Revanche ehrlich gefahren → ranked');
  await a.request('MG_RESULT_ACK', { rewardId: result2.d.rewardId });
  await b2.request('MG_RESULT_ACK', { rewardId: result2B.d.rewardId });

  // -- 6. Bestenliste + Ghost -------------------------------------------------
  const lb = await fetch(`${server.url}/api/rmp/leaderboard/grasbahn`, { headers: { authorization: bearer(idA) } });
  const lbData = await lb.json();
  assert.ok(lbData.entries.length >= 2, 'beide stehen in der Bestenliste');
  for (const e of lbData.entries) log('smoke', `Bestenliste grasbahn: ${e.name} (${e.friendCode}) ${e.wert} ms`);

  const meineZeit = lbData.entries.find((e) => e.friendCode === codeA).wert;
  const ghostPut = await fetch(`${server.url}/api/rmp/ghost/grasbahn`, {
    method: 'PUT',
    headers: { authorization: bearer(idA), 'content-type': 'application/json' },
    body: JSON.stringify({
      wert: meineZeit,
      rateHz: 10,
      samples: KURSE.grasbahn.checkpoints.map(([x, z]) => [x, z]),
    }),
  });
  assert.equal((await ghostPut.json()).gespeichert, true);
  const ghostGet = await fetch(`${server.url}/api/rmp/ghost/grasbahn/${codeA}`, {
    headers: { authorization: bearer(idB) },
  });
  const ghostData = await ghostGet.json();
  assert.equal(ghostData.wert, meineZeit);
  log('smoke', `Ghost abgelegt + von Ben geladen (wert=${ghostData.wert} ms, ${ghostData.samples.length} Samples)`);

  // -- Aufräumen ---------------------------------------------------------------
  a.close();
  b2.close();
  server.child.kill('SIGTERM');
  await new Promise((r) => server.child.once('exit', r));
  fs.rmSync(server.dataDir, { recursive: true, force: true });
  log('smoke', 'SMOKE BESTANDEN: Besuch + Rennen + Verbindungsabbruch/Rejoin + Revanche + Bestenliste/Ghost');
}

main().catch((err) => {
  console.error('[smoke] FEHLGESCHLAGEN:', err);
  process.exit(1);
});
