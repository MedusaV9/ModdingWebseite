// RW-6 Bandbreiten-Messlauf (DoD-Beleg für RANCH-DLC-IDEAS-4 §2.5): startet den
// ECHTEN Server als eigenen Prozess und fährt ein VOLLES Vierer-Rennen auf der
// Grasbahn. Jeder Client sendet 10 Hz MG_POSE (Doc-Empfehlung), der Server
// relayt an die drei Peers. Wir zählen die WAHREN Wire-Bytes (UTF-8-Payload je
// Frame + WS-Rahmen-Overhead) getrennt nach Richtung und Nachrichtentyp und
// rechnen daraus die Netto-Bitrate je Client hoch.
//
// Aufruf:  node tools/bandwidth-rmp.mjs   (aus GOOBY-SERVER/, beendet sich selbst)
// Exit 0 = im Budget (24 kbit/s hoch, 80 kbit/s runter je Vierer-Client).

import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import WebSocket from 'ws';
import { newIdentity } from '../test/helpers.js';
import { KURSE, kursHash } from '../src/ranchmp.js';

const ROOT = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const T0 = Date.now();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const POSE_HZ = 10; // Doc §2.3: 10 Hz Pose-Frequenz
const MESS_SEKUNDEN = 12; // Messfenster im Lauf
const SPIELER = 4; // Voller Vierer (worst case fürs Budget)

function log(wer, text) {
  const t = ((Date.now() - T0) / 1000).toFixed(2).padStart(6);
  console.log(`[${t}s] [${wer}] ${text}`);
}

// WS-Rahmen-Overhead (RFC 6455): 2 Byte Basis + 4 Byte Masking-Key (Client→
// Server IMMER maskiert). Nutzlast < 126 B → keine erweiterte Länge. Peer-Posen
// liegen darüber (kein Masking Server→Client), aber < 126 B. Wir rechnen den
// Overhead richtungsabhängig: Upstream 6 B, Downstream 2 B pro Frame.
const FRAME_UP = 6;
const FRAME_DOWN = 2;

// Ein Messклиент: zählt Bytes/Frames je Typ und Richtung direkt am Socket.
class MessClient {
  constructor(ws) {
    this.ws = ws;
    this.seq = 0;
    this.inbox = [];
    this.waiters = [];
    this.closed = false;
    this.messenAktiv = false;
    this.up = new Map(); // typ -> { frames, bytes }
    this.down = new Map();
    ws.on('message', (raw) => {
      const text = raw.toString('utf8');
      const msg = JSON.parse(text);
      if (this.messenAktiv) this._zaehle(this.down, msg.t, Buffer.byteLength(text, 'utf8') + FRAME_DOWN);
      const idx = this.waiters.findIndex((w) => w.filter(msg));
      if (idx >= 0) {
        const [waiter] = this.waiters.splice(idx, 1);
        clearTimeout(waiter.timer);
        waiter.resolve(msg);
      } else {
        this.inbox.push(msg);
      }
    });
    ws.on('close', () => {
      this.closed = true;
      for (const w of this.waiters.splice(0)) {
        clearTimeout(w.timer);
        w.reject(new Error('socket closed while waiting'));
      }
    });
  }

  _zaehle(map, typ, bytes) {
    const e = map.get(typ) || { frames: 0, bytes: 0 };
    e.frames += 1;
    e.bytes += bytes;
    map.set(typ, e);
  }

  static connect(wsUrl) {
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(wsUrl);
      ws.once('open', () => resolve(new MessClient(ws)));
      ws.once('error', reject);
    });
  }

  send(t, d = {}) {
    const seq = ++this.seq;
    const text = JSON.stringify({ v: 1, t, seq, ts: Date.now(), d });
    if (this.messenAktiv) this._zaehle(this.up, t, Buffer.byteLength(text, 'utf8') + FRAME_UP);
    this.ws.send(text);
    return seq;
  }

  next(filter, timeoutMs = 15_000) {
    const fn = typeof filter === 'string' ? (m) => m.t === filter : filter;
    const idx = this.inbox.findIndex(fn);
    if (idx >= 0) return Promise.resolve(this.inbox.splice(idx, 1)[0]);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(
        () => reject(new Error(`timeout waiting for ${typeof filter === 'string' ? filter : 'filter'}`)),
        timeoutMs
      );
      this.waiters.push({ filter: fn, resolve, reject, timer });
    });
  }

  async request(t, d = {}, timeoutMs = 15_000) {
    const seq = this.send(t, d);
    return this.next((m) => m.re === seq, timeoutMs);
  }

  async hello(identity) {
    return this.request('HELLO', identity);
  }

  close() {
    this.ws.close();
  }
}

async function serverStarten() {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'gooby-bw-rw6-'));
  const child = spawn(process.execPath, ['server.js'], {
    cwd: ROOT,
    env: { ...process.env, PORT: '0', DATA_DIR: dataDir },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let port = null;
  child.stdout.on('data', (buf) => {
    for (const line of buf.toString('utf8').split('\n')) {
      if (!line.trim()) continue;
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
  log('mess', `Server läuft (pid=${child.pid}, Port ${port})`);
  return { child, dataDir, wsUrl: `ws://127.0.0.1:${port}/ws` };
}

// Realistische Pose (Grasbahn-Koordinaten, Galopp): so groß wie im echten Lauf.
function poseNutzlast(room, i, seq) {
  const cp = KURSE.grasbahn.checkpoints[i % KURSE.grasbahn.checkpoints.length];
  return {
    room,
    p: [cp[0] + 0.37, 0.82, cp[1] - 1.19],
    yaw: 2.4137,
    speed: 13.6,
    gait: 3,
    anim: 'gallop',
    jump: false,
    poseSeq: seq,
  };
}

async function main() {
  const server = await serverStarten();
  const clients = [];
  const codes = [];
  const namen = ['Anna', 'Ben', 'Cara', 'Dora'];
  for (let i = 0; i < SPIELER; i++) {
    const c = await MessClient.connect(server.wsUrl);
    const w = await c.hello(newIdentity(namen[i], `Gooby${i}`));
    clients.push(c);
    codes.push(w.d.friendCode);
  }
  log('mess', `${SPIELER} Clients verbunden: ${codes.join(', ')}`);

  // Anna (0) befreundet sich mit allen anderen (Invite verlangt Freundschaft).
  for (let i = 1; i < SPIELER; i++) {
    await clients[0].request('FRIEND_REQUEST', { target: codes[i] });
    await clients[i].next('FRIEND_REQUEST_INCOMING');
    await clients[i].request('FRIEND_ACCEPT', { target: codes[0] });
    await clients[0].next('FRIEND_ADDED');
    await clients[i].next('FRIEND_ADDED');
  }
  log('mess', 'Anna ist mit Ben, Cara, Dora befreundet');

  // Anna lädt alle ins selbe Rennen (offene Lobby wird nachgeladen).
  let room = null;
  for (let i = 1; i < SPIELER; i++) {
    await clients[0].request('RANCH_INVITE', { target: codes[i], mode: 'rennen', kurs: 'grasbahn' });
    const inv = await clients[i].next('RANCH_INVITED');
    const ready = await clients[i].request('RANCH_ACCEPT', { from: inv.d.from });
    room = ready.d.room;
  }
  log('mess', `Rennen-Lobby ${room} mit vier Spielern`);

  for (const c of clients) await c.request('ROOM_JOIN', { room });
  const hash = kursHash('grasbahn');
  for (const c of clients) await c.request('MG_READY', { room, kursHash: hash });

  // Auf MG_START warten (kommt an alle) und Countdown abwarten.
  const start = await clients[0].next('MG_START');
  const warten = Math.max(0, start.d.startAt - start.d.serverNow) + 120;
  log('mess', `MG_START seed=${start.d.seed}, Countdown ${warten} ms → Messfenster ${MESS_SEKUNDEN}s @ ${POSE_HZ} Hz`);
  await sleep(warten);

  // -- Messfenster: alle vier senden synchron 10 Hz MG_POSE -----------------
  for (const c of clients) c.messenAktiv = true;
  const ticks = MESS_SEKUNDEN * POSE_HZ;
  const intervallMs = 1000 / POSE_HZ;
  for (let tick = 0; tick < ticks; tick++) {
    const rundenStart = Date.now();
    for (let i = 0; i < SPIELER; i++) {
      clients[i].send('MG_POSE', poseNutzlast(room, tick, tick + 1));
    }
    const rest = intervallMs - (Date.now() - rundenStart);
    if (rest > 0) await sleep(rest);
  }
  await sleep(300); // Relays einsammeln
  for (const c of clients) c.messenAktiv = false;

  // -- Auswertung -----------------------------------------------------------
  const richtungSumme = (map) => [...map.values()].reduce((a, e) => a + e.bytes, 0);
  // Ein repräsentativer Client (alle senden gleich; nimm den Median-Down).
  console.log('\n=== Gemessene Nachrichtengrößen (echte Wire-Bytes inkl. WS-Rahmen) ===');
  const beispiel = clients[0];
  const poseUp = beispiel.up.get('MG_POSE');
  const posePeer = beispiel.down.get('MG_PEER_POSE');
  console.log(
    `MG_POSE  (hoch):  ${(poseUp.bytes / poseUp.frames).toFixed(1)} B/Frame  ` +
      `× ${poseUp.frames} Frames`
  );
  console.log(
    `MG_PEER_POSE (runter): ${(posePeer.bytes / posePeer.frames).toFixed(1)} B/Frame  ` +
      `× ${posePeer.frames} Frames (3 Peers × ${POSE_HZ} Hz)`
  );

  let upSum = 0;
  let downSum = 0;
  for (const c of clients) {
    upSum += richtungSumme(c.up);
    downSum += richtungSumme(c.down);
  }
  const sek = MESS_SEKUNDEN;
  const upPro = richtungSumme(beispiel.up) / sek;
  const downPro = richtungSumme(beispiel.down) / sek;
  const kbit = (bytesProSek) => (bytesProSek * 8) / 1000;

  console.log('\n=== Bitrate je Vierer-Client (Netto, ohne TCP/IP-Header) ===');
  console.log(`hoch  (Client→Server): ${kbit(upPro).toFixed(1)} kbit/s   (Budget 24)`);
  console.log(`runter (Server→Client): ${kbit(downPro).toFixed(1)} kbit/s   (Budget 80)`);
  console.log(`Server-Egress gesamt (4 Clients): ${kbit(downSum / sek).toFixed(1)} kbit/s`);
  console.log(`Server-Ingress gesamt (4 Clients): ${kbit(upSum / sek).toFixed(1)} kbit/s`);

  const upOk = kbit(upPro) <= 24;
  const downOk = kbit(downPro) <= 80;
  console.log(`\nBudget hoch  ≤24: ${upOk ? 'OK' : 'ÜBERSCHRITTEN'}`);
  console.log(`Budget runter ≤80: ${downOk ? 'OK' : 'ÜBERSCHRITTEN'}`);

  for (const c of clients) c.close();
  server.child.kill('SIGTERM');
  await sleep(200);
  fs.rmSync(server.dataDir, { recursive: true, force: true });

  if (!upOk || !downOk) {
    console.error('\nFEHLER: Bandbreitenbudget überschritten.');
    process.exit(1);
  }
  console.log('\nAlles im Budget.');
  process.exit(0);
}

main().catch((err) => {
  console.error('BANDWIDTH-FEHLER:', err);
  process.exit(1);
});
