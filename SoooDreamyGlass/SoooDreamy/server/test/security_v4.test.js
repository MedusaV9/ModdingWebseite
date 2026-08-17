import assert from 'node:assert/strict';
import { rm } from 'node:fs/promises';
import test from 'node:test';
import WebSocket from 'ws';
import { transportSecurityFromEnv } from '../src/app.js';
import { RateLimiter, requireSecureTransport, tokenDigest } from '../src/security.js';
import { client, makeApp, setupCouple, wsOpen } from './helpers.js';

test('transport has distinct default HTTP, private-only HTTP, and HTTPS-required modes', async (t) => {
  assert.deepEqual(transportSecurityFromEnv({}), {
    allowInsecureHttp: true,
    allowInsecurePrivateLAN: false,
    mode: 'http-default',
  });
  assert.equal(transportSecurityFromEnv({ ALLOW_HTTP_PRIVATE_LAN: '1' }).mode, 'private-http');
  assert.equal(transportSecurityFromEnv({
    ALLOW_HTTP_PRIVATE_LAN: '1',
    REQUIRE_HTTPS: '1',
  }).mode, 'https-required');

  const open = await makeApp(t, { allowInsecurePrivateLAN: false, allowInsecureHttp: true });
  assert.equal((await client(open.baseUrl).get('/api/health')).status, 200);

  const privateOnly = await makeApp(t, { allowInsecurePrivateLAN: true, allowInsecureHttp: false });
  assert.equal((await client(privateOnly.baseUrl).get('/api/health')).status, 200);
  assert.throws(
    () => requireSecureTransport({
      headers: {},
      socket: { encrypted: false, remoteAddress: '203.0.113.10' },
    }, { allowInsecurePrivateLAN: true, allowInsecureHttp: false }),
    (error) => error.status === 426 && error.code === 'https_required',
  );

  const blocked = await makeApp(t, { allowInsecurePrivateLAN: false, allowInsecureHttp: false });
  const response = await client(blocked.baseUrl).get('/api/health');
  assert.equal(response.status, 426);
  assert.equal(response.body.error, 'https_required');
});

test('trusted HTTPS proxy is accepted while untrusted forwarded headers are ignored', async (t) => {
  const trusted = await makeApp(t, {
    allowInsecurePrivateLAN: false,
    allowInsecureHttp: false,
    trustProxy: true,
  });
  const accepted = await client(trusted.baseUrl).get('/api/health', {
    headers: { 'x-forwarded-proto': 'https' },
  });
  assert.equal(accepted.status, 200);

  const untrusted = await makeApp(t, {
    allowInsecurePrivateLAN: false,
    allowInsecureHttp: false,
    trustProxy: false,
  });
  const rejected = await client(untrusted.baseUrl).get('/api/health', {
    headers: { 'x-forwarded-proto': 'https' },
  });
  assert.equal(rejected.status, 426);
});

test('query bearer tokens are rejected globally, including media and WebSockets', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);

  const rest = await client(baseUrl).get(`/api/health?token=${a.token}`);
  assert.equal(rest.status, 400);
  assert.equal(rest.body.error, 'query_token_forbidden');

  const ws = new WebSocket(`${baseUrl.replace(/^http/, 'ws')}/ws?access_token=${a.token}`);
  const status = await new Promise((resolve) => {
    ws.once('unexpected-response', (_request, response) => resolve(response.statusCode));
    ws.once('error', () => resolve(null));
  });
  assert.equal(status, 400);
});

test('WebSockets enforce per-session caps and a 64 KiB payload ceiling', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  const open = [];
  for (let index = 0; index < 4; index += 1) {
    const connection = await wsOpen(baseUrl, a.token, t);
    await connection.waitFor('welcome');
    open.push(connection);
  }

  const excess = new WebSocket(baseUrl.replace(/^http/u, 'ws') + '/ws', {
    headers: { authorization: `Bearer ${a.token}` },
  });
  const excessStatus = await new Promise((resolve) => {
    excess.once('unexpected-response', (_request, response) => resolve(response.statusCode));
    excess.once('error', () => resolve(null));
  });
  assert.equal(excessStatus, 429);

  const closeCode = new Promise((resolve) => open[0].ws.once('close', resolve));
  open[0].ws.send(Buffer.alloc(64 * 1024 + 1));
  assert.equal(await closeCode, 1009);
});

test('sessions are hashed at rest and can rotate then revoke', async (t) => {
  const { app, baseUrl } = await makeApp(t);
  const created = await client(baseUrl).post('/api/couples', {
    json: {
      name: 'Mia',
      deviceId: 'device-0001',
      deviceName: 'Mias iPhone',
    },
  });
  assert.equal(created.status, 201);
  assert.ok(created.body.sessionId);
  assert.ok(created.body.expiresAt);
  assert.equal(app.store.data.tokens[created.body.token], undefined);
  assert.equal(app.store.data.tokens[tokenDigest(created.body.token)].deviceId, 'device-0001');

  const api = client(baseUrl, created.body.token);
  const sessions = await api.get('/api/sessions');
  assert.equal(sessions.status, 200);
  assert.deepEqual(
    sessions.body.sessions.map((session) => ({
      id: session.id,
      deviceId: session.deviceId,
      current: session.current,
    })),
    [{ id: created.body.sessionId, deviceId: 'device-0001', current: true }],
  );
  assert.equal(JSON.stringify(sessions.body).includes(created.body.token), false);

  const socket = await wsOpen(baseUrl, created.body.token, t);
  const rotated = await api.post('/api/sessions/current/rotate', { json: {} });
  assert.equal(rotated.status, 200);
  assert.notEqual(rotated.body.token, created.body.token);
  await socket.closed();

  const oldToken = await api.get('/api/couple');
  assert.equal(oldToken.status, 401);
  const nextApi = client(baseUrl, rotated.body.token);
  assert.equal((await nextApi.get('/api/couple')).status, 200);

  const revoked = await nextApi.post(`/api/sessions/${rotated.body.sessionId}/revoke`, { json: {} });
  assert.equal(revoked.status, 200);
  assert.equal((await nextApi.get('/api/couple')).status, 401);
});

test('session records are capped per member and stale proofs are cleaned on startup', async (t) => {
  const first = await makeApp(null);
  const created = await client(first.baseUrl).post('/api/couples', {
    json: { name: 'Session cap', deviceId: 'session-cap-origin' },
  });
  for (let index = 0; index < 12; index += 1) {
    const rejoin = await client(first.baseUrl).post('/api/couples/rejoin', {
      json: {
        code: created.body.couple.code,
        recoveryKey: created.body.recoveryKey,
        deviceId: `session-cap-${index}`,
      },
    });
    assert.equal(rejoin.status, 200);
  }
  const memberRecords = Object.values(first.app.store.data.tokens)
    .filter((record) => record.memberId === created.body.memberId);
  assert.equal(memberRecords.length, 8);
  for (const record of memberRecords) {
    record.expiresAt = new Date(Date.now() - 2 * 24 * 60 * 60 * 1000).toISOString();
  }
  first.app.store.markDirty();
  await first.close();

  const reopened = await makeApp(t, { dataDir: first.dataDir });
  t.after(() => rm(first.dataDir, { recursive: true, force: true }));
  assert.equal(
    Object.values(reopened.app.store.data.tokens)
      .filter((record) => record.memberId === created.body.memberId).length,
    0,
  );
});

test('pairing rate limits and server capacity return bounded failures', async (t) => {
  const limiter = new RateLimiter({
    policies: {
      coupleCreate: { limit: 1, windowMs: 60_000 },
    },
  });
  const limited = await makeApp(t, { rateLimiter: limiter });
  const anon = client(limited.baseUrl);
  assert.equal((await anon.post('/api/couples', { json: { name: 'Mia' } })).status, 201);
  const throttled = await anon.post('/api/couples', { json: { name: 'Ben' } });
  assert.equal(throttled.status, 429);
  assert.equal(throttled.body.error, 'rate_limited');
  assert.equal(throttled.headers.get('retry-after'), '60');

  const capped = await makeApp(t, { maxCouples: 1 });
  const cappedAnon = client(capped.baseUrl);
  assert.equal((await cappedAnon.post('/api/couples', { json: { name: 'Mia' } })).status, 201);
  const full = await cappedAnon.post('/api/couples', { json: { name: 'Ben' } });
  assert.equal(full.status, 503);
  assert.equal(full.body.error, 'server_capacity');
});

test('security logging redacts bearer material and bounds each value', async (t) => {
  const entries = [];
  const { app } = await makeApp(t, { log: (...values) => entries.push(values) });
  app.realtime.log(
    'failed',
    `GET /x?token=top-secret Authorization: Bearer abc.DEF_123 ${'x'.repeat(4_000)}`,
  );
  assert.equal(entries.length, 1);
  const rendered = entries[0].join(' ');
  assert.equal(rendered.includes('top-secret'), false);
  assert.equal(rendered.includes('abc.DEF_123'), false);
  assert.ok(entries[0].every((value) => value.length <= 2_000));
});
