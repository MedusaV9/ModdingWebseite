// Test-Infrastruktur: echter Server auf Port 0 (127.0.0.1, keine Netzwerk-Flakes),
// Temp-Datenverzeichnis pro Test, kleiner WS-Client mit request/await-Semantik.

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import WebSocket from 'ws';
import { createServer } from '../server.js';

export async function startServer({ env = {}, cfg = {}, clock } = {}) {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'gooby-test-'));
  const fullEnv = { DATA_DIR: dataDir, ...env };
  const srv = createServer(fullEnv, { cfg, clock, flushMs: 60_000 });
  const port = await srv.listen(0, '127.0.0.1');
  return {
    srv,
    ctx: srv.ctx,
    port,
    dataDir,
    url: `http://127.0.0.1:${port}`,
    wsUrl: `ws://127.0.0.1:${port}/ws`,
    async stop() {
      await srv.stop();
      fs.rmSync(dataDir, { recursive: true, force: true });
    },
  };
}

export function newIdentity(name = 'Tester', goobyName = 'Gooby') {
  return {
    deviceId: `gd-${crypto.randomBytes(8).toString('hex')}`,
    deviceSecret: crypto.randomBytes(32).toString('hex'),
    name,
    goobyName,
  };
}

export function bearer(identity) {
  return `Bearer ${identity.deviceId}:${identity.deviceSecret}`;
}

export class WsClient {
  constructor(ws) {
    this.ws = ws;
    this.seq = 0;
    this.inbox = [];
    this.waiters = [];
    this.closed = false;
    ws.on('message', (raw) => {
      const msg = JSON.parse(raw.toString('utf8'));
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

  static connect(wsUrl) {
    return new Promise((resolve, reject) => {
      const ws = new WebSocket(wsUrl);
      ws.once('open', () => resolve(new WsClient(ws)));
      ws.once('error', reject);
    });
  }

  sendRaw(text) {
    this.ws.send(text);
  }

  send(t, d = {}) {
    const seq = ++this.seq;
    this.ws.send(JSON.stringify({ v: 1, t, seq, ts: Date.now(), d }));
    return seq;
  }

  // Wartet auf die nächste Message, die filter erfüllt (String = Typ-Match).
  next(filter, timeoutMs = 3000) {
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

  // Request/Response über re-Korrelation.
  async request(t, d = {}, timeoutMs = 3000) {
    const seq = this.send(t, d);
    return this.next((m) => m.re === seq, timeoutMs);
  }

  async hello(identity, extra = {}) {
    return this.request('HELLO', { ...identity, ...extra });
  }

  async waitClose(timeoutMs = 3000) {
    if (this.closed) return;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('timeout waiting for close')), timeoutMs);
      this.ws.once('close', () => {
        clearTimeout(timer);
        resolve();
      });
    });
  }

  close() {
    this.ws.close();
  }
}

// Zwei verbundene + befreundete Clients (Standard-Fixture vieler Tests).
export async function twoFriends(t, opts = {}) {
  const server = await startServer(opts);
  t.after(() => server.stop());
  const idA = newIdentity('Anna', 'Flausch');
  const idB = newIdentity('Ben', 'Knöpfchen');
  const a = await WsClient.connect(server.wsUrl);
  const b = await WsClient.connect(server.wsUrl);
  const welcomeA = await a.hello(idA);
  const welcomeB = await b.hello(idB);
  const codeA = welcomeA.d.friendCode;
  const codeB = welcomeB.d.friendCode;
  await a.request('FRIEND_REQUEST', { target: codeB });
  await b.next('FRIEND_REQUEST_INCOMING');
  await b.request('FRIEND_ACCEPT', { target: codeA });
  await a.next('FRIEND_ADDED');
  await b.next('FRIEND_ADDED');
  t.after(() => {
    a.close();
    b.close();
  });
  return { server, a, b, idA, idB, codeA, codeB };
}
