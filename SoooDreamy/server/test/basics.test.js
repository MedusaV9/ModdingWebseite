import { test } from 'node:test';
import assert from 'node:assert/strict';
import WebSocket from 'ws';
import { makeApp, client, setupCouple, wsOpen } from './helpers.js';

test('health endpoint', async (t) => {
  const { baseUrl } = await makeApp(t);
  const res = await client(baseUrl).get('/api/health');
  assert.equal(res.status, 200);
  assert.equal(res.body.ok, true);
  assert.equal(res.body.name, 'SoooDreamy');
  assert.match(res.body.version, /^\d+\.\d+\.\d+$/);
  assert.match(res.body.serverTime, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/);
});

test('root serves a friendly camera-QR landing page', async (t) => {
  const { baseUrl } = await makeApp(t);
  const response = await fetch(`${baseUrl}/`);
  assert.equal(response.status, 200);
  assert.match(response.headers.get('content-type'), /^text\/html/u);
  const html = await response.text();
  assert.match(html, /Euer SoooDreamy-Server läuft/u);
  assert.match(html, /Einstellungen → Server/u);
  assert.match(html, /Adresse kopieren/u);
});

test('create couple returns 201 with a well-formed code and token', async (t) => {
  const { baseUrl } = await makeApp(t);
  const res = await client(baseUrl).post('/api/couples', { json: { name: 'Mia', avatar: '🦊', color: '#FF5C8A' } });
  assert.equal(res.status, 201);
  assert.match(res.body.token, /^tok_[0-9a-f]{48}$/);
  assert.match(res.body.couple.code, /^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$/);
  assert.equal(res.body.couple.members.length, 1);
  assert.equal(res.body.couple.members[0].id, res.body.memberId);
  assert.equal(res.body.couple.members[0].name, 'Mia');
  assert.equal(res.body.couple.members[0].online, false);
});

test('join: success, unknown_code 404, couple_full 409', async (t) => {
  const { baseUrl } = await makeApp(t);
  const anon = client(baseUrl);
  const created = await anon.post('/api/couples', { json: { name: 'Mia', avatar: '🦊', color: '#FF5C8A' } });
  const code = created.body.couple.code;

  const unknown = await anon.post('/api/couples/join', { json: { code: 'ZZZZZZ', name: 'Ben' } });
  assert.equal(unknown.status, 404);
  assert.equal(unknown.body.error, 'unknown_code');

  const joined = await anon.post('/api/couples/join', { json: { code, name: 'Ben', avatar: '🐻', color: '#4A90D9' } });
  assert.equal(joined.status, 200);
  assert.equal(joined.body.coupleId, created.body.coupleId);
  assert.equal(joined.body.couple.members.length, 2);

  const full = await anon.post('/api/couples/join', { json: { code, name: 'Eve' } });
  assert.equal(full.status, 409);
  assert.equal(full.body.error, 'couple_full');
});

test('auth failures: missing and bogus tokens are 401 invalid_token', async (t) => {
  const { baseUrl } = await makeApp(t);
  const noToken = await client(baseUrl).get('/api/couple');
  assert.equal(noToken.status, 401);
  assert.equal(noToken.body.error, 'invalid_token');

  const badToken = await client(baseUrl, 'tok_bogus').get('/api/couple');
  assert.equal(badToken.status, 401);
  assert.equal(badToken.body.error, 'invalid_token');
});

test('unknown route → 404, invalid JSON → 400, CORS preflight → 204', async (t) => {
  const { baseUrl } = await makeApp(t);
  const missing = await client(baseUrl).get('/api/nope');
  assert.equal(missing.status, 404);
  assert.equal(missing.body.error, 'not_found');

  const invalid = await fetch(`${baseUrl}/api/couples`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: '{not json',
  });
  assert.equal(invalid.status, 400);
  assert.equal((await invalid.json()).error, 'invalid_json');

  const preflight = await fetch(`${baseUrl}/api/couple`, { method: 'OPTIONS' });
  assert.equal(preflight.status, 204);
  assert.equal(preflight.headers.get('access-control-allow-origin'), '*');
  const getRes = await fetch(`${baseUrl}/api/health`);
  assert.equal(getRes.headers.get('access-control-allow-origin'), '*');
});

test('websocket with a bad token is rejected during the handshake', async (t) => {
  const { baseUrl } = await makeApp(t);
  const ws = new WebSocket(`${baseUrl.replace(/^http/, 'ws')}/ws`, {
    headers: { authorization: 'Bearer tok_bogus_not_a_valid_token' },
  });
  const err = await new Promise((resolve) => {
    ws.once('error', resolve);
    ws.once('open', () => resolve(null));
  });
  assert.ok(err, 'expected the connection to fail');
  assert.match(err.message, /401/);
});

test('joining broadcasts partner_joined to the waiting member', async (t) => {
  const { baseUrl } = await makeApp(t);
  const anon = client(baseUrl);
  const created = await anon.post('/api/couples', { json: { name: 'Mia' } });
  const aSock = await wsOpen(baseUrl, created.body.token, t);
  await aSock.waitFor('welcome');

  const joined = await anon.post('/api/couples/join', { json: { code: created.body.couple.code, name: 'Ben' } });
  const frame = await aSock.waitFor('partner_joined');
  assert.equal(frame.payload.member.id, joined.body.memberId);
  assert.equal(frame.payload.member.name, 'Ben');
});

test('welcome frame and ping→pong', async (t) => {
  const { baseUrl } = await makeApp(t);
  const couple = await setupCouple(baseUrl);
  const a = await wsOpen(baseUrl, couple.a.token, t);
  const welcome = await a.waitFor('welcome');
  assert.equal(welcome.payload.memberId, couple.a.memberId);
  assert.equal(welcome.payload.coupleId, couple.coupleId);
  assert.equal(welcome.payload.partnerOnline, false);
  assert.ok(welcome.ts);

  a.send({ type: 'ping' });
  await a.waitFor('pong');
});
