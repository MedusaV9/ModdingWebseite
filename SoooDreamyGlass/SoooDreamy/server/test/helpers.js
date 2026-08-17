import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import WebSocket from 'ws';
import { createApp } from '../src/app.js';

/** Starts the app on an ephemeral port with a temp DATA_DIR; auto-cleans via t.after. */
export async function makeApp(t, { dataDir, ...options } = {}) {
  const dir = dataDir ?? (await mkdtemp(path.join(os.tmpdir(), 'sooodreamy-test-')));
  const app = await createApp({ dataDir: dir, allowInsecurePrivateLAN: true, ...options });
  await new Promise((resolve) => app.server.listen(0, '127.0.0.1', resolve));
  const { port } = app.server.address();
  const ctx = {
    app,
    dataDir: dir,
    baseUrl: `http://127.0.0.1:${port}`,
    close: () => app.close(),
  };
  if (t) {
    t.after(async () => {
      await app.close();
      if (!dataDir) await rm(dir, { recursive: true, force: true });
    });
  }
  return ctx;
}

/** Minimal fetch wrapper. Returns {status, body, headers}; body is parsed JSON or a Buffer. */
export function client(baseUrl, token) {
  async function req(method, pathname, { json, body, headers: extra } = {}) {
    const headers = { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(extra ?? {}) };
    let payload = body;
    if (json !== undefined) {
      headers['content-type'] = 'application/json';
      payload = JSON.stringify(json);
    }
    const res = await fetch(baseUrl + pathname, { method, headers, body: payload });
    const contentType = res.headers.get('content-type') ?? '';
    const data = contentType.includes('application/json')
      ? await res.json()
      : Buffer.from(await res.arrayBuffer());
    return { status: res.status, body: data, headers: res.headers };
  }
  return {
    get: (p, o) => req('GET', p, o),
    post: (p, o) => req('POST', p, o),
    put: (p, o) => req('PUT', p, o),
    patch: (p, o) => req('PATCH', p, o),
    del: (p, o) => req('DELETE', p, o),
  };
}

/** Creates a full couple (Mia creates, Ben joins). */
export async function setupCouple(baseUrl) {
  const anon = client(baseUrl);
  const created = await anon.post('/api/couples', { json: { name: 'Mia', avatar: '🦊', color: '#FF5C8A' } });
  if (created.status !== 201) throw new Error(`couple create failed: ${JSON.stringify(created.body)}`);
  const code = created.body.couple.code;
  const joined = await anon.post('/api/couples/join', { json: { code, name: 'Ben', avatar: '🐻', color: '#4A90D9' } });
  if (joined.status !== 200) throw new Error(`couple join failed: ${JSON.stringify(joined.body)}`);
  return {
    code,
    coupleId: created.body.coupleId,
    a: { token: created.body.token, memberId: created.body.memberId, api: client(baseUrl, created.body.token) },
    b: { token: joined.body.token, memberId: joined.body.memberId, api: client(baseUrl, joined.body.token) },
  };
}

/**
 * Opens a WebSocket test client. `waitFor(type)` consumes frames (each frame is
 * delivered to exactly one waiter), `assertNone(type)` checks nothing of that
 * type arrived un-consumed.
 */
export async function wsOpen(baseUrl, token, t) {
  const ws = new WebSocket(`${baseUrl.replace(/^http/, 'ws')}/ws`, {
    headers: { authorization: `Bearer ${token}` },
  });
  const unconsumed = [];
  const waiters = [];
  ws.on('message', (data) => {
    let msg;
    try {
      msg = JSON.parse(data.toString());
    } catch {
      return;
    }
    const i = waiters.findIndex((w) => w.match(msg));
    if (i !== -1) waiters.splice(i, 1)[0].resolve(msg);
    else unconsumed.push(msg);
  });
  await new Promise((resolve, reject) => {
    ws.once('open', resolve);
    ws.once('error', reject);
  });
  const conn = {
    ws,
    unconsumed,
    waitFor(type, pred = () => true, timeoutMs = 3000) {
      const match = (m) => m.type === type && pred(m);
      const idx = unconsumed.findIndex(match);
      if (idx !== -1) return Promise.resolve(unconsumed.splice(idx, 1)[0]);
      return new Promise((resolve, reject) => {
        const waiter = { match, resolve: (m) => { clearTimeout(timer); resolve(m); } };
        const timer = setTimeout(() => {
          const at = waiters.indexOf(waiter);
          if (at !== -1) waiters.splice(at, 1);
          const seen = unconsumed.map((m) => m.type).join(', ') || 'nothing';
          reject(new Error(`timed out waiting for WS "${type}" (unconsumed: ${seen})`));
        }, timeoutMs);
        waiters.push(waiter);
      });
    },
    async assertNone(type, settleMs = 200) {
      await new Promise((r) => setTimeout(r, settleMs));
      const hit = unconsumed.find((m) => m.type === type);
      if (hit) throw new Error(`expected no WS "${type}" frame but got ${JSON.stringify(hit)}`);
    },
    send(frame) {
      ws.send(JSON.stringify(frame));
    },
    close() {
      if (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING) ws.close();
    },
    closed() {
      return new Promise((resolve) => (ws.readyState === WebSocket.CLOSED ? resolve() : ws.once('close', resolve)));
    },
  };
  if (t) t.after(() => conn.close());
  return conn;
}

export function dateKeyDaysAgo(days) {
  return new Date(Date.now() - days * 86_400_000).toISOString().slice(0, 10);
}
