// HELLO/WELCOME, TOFU-Auth-Fehlfälle, PING/PONG, Protokoll-Fehler — über echten WS-Server.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { startServer, newIdentity, WsClient } from './helpers.js';

test('HELLO → WELCOME mit friendCode; Reconnect behält Identität', async (t) => {
  const server = await startServer();
  t.after(() => server.stop());
  const id = newIdentity('Sonic0810', 'Herr Flauschig');

  const c1 = await WsClient.connect(server.wsUrl);
  const welcome = await c1.hello(id);
  assert.equal(welcome.t, 'WELCOME');
  assert.match(welcome.d.friendCode, /^GOOBY-[A-HJ-NP-Z2-9]{4}$/);
  assert.equal(welcome.d.heartbeatSec, 20);
  assert.ok(Array.isArray(welcome.d.features) && welcome.d.features.includes('pal'));
  assert.ok(Array.isArray(welcome.d.pendingEvents));
  // deviceSecret liegt NUR als Hash im Storage (TOFU).
  const stored = server.ctx.players[id.deviceId];
  assert.match(stored.secretHash, /^sha256:[0-9a-f]{64}$/);
  assert.ok(!JSON.stringify(stored).includes(id.deviceSecret));
  c1.close();
  await c1.waitClose();

  const c2 = await WsClient.connect(server.wsUrl);
  const welcome2 = await c2.hello(id);
  assert.equal(welcome2.d.friendCode, welcome.d.friendCode, 'gleicher Account');
  c2.close();
});

test('HELLO-Fehlfälle: falsches Secret, kaputte Felder, fehlender Name', async (t) => {
  const server = await startServer();
  t.after(() => server.stop());
  const id = newIdentity();
  const c1 = await WsClient.connect(server.wsUrl);
  await c1.hello(id);

  // Falsches Secret für existierendes Gerät → AUTH_FAIL + Close.
  const evil = await WsClient.connect(server.wsUrl);
  const err = await evil.hello({ ...id, deviceSecret: 'f'.repeat(64) });
  assert.equal(err.t, 'ERROR');
  assert.equal(err.d.code, 'AUTH_FAIL');
  await evil.waitClose();

  // Ungültiges Secret-Format → AUTH_FAIL.
  const bad = await WsClient.connect(server.wsUrl);
  const err2 = await bad.hello({ ...newIdentity(), deviceSecret: 'kurz' });
  assert.equal(err2.d.code, 'AUTH_FAIL');
  await bad.waitClose();

  // Neues Gerät ohne Namen → BAD_MESSAGE.
  const noName = await WsClient.connect(server.wsUrl);
  const err3 = await noName.hello({ ...newIdentity(), name: undefined });
  assert.equal(err3.d.code, 'BAD_MESSAGE');
  await noName.waitClose();
  c1.close();
});

test('Ohne HELLO: erste andere Message → HELLO_REQUIRED + Close', async (t) => {
  const server = await startServer();
  t.after(() => server.stop());
  const c = await WsClient.connect(server.wsUrl);
  c.send('PING');
  const err = await c.next('ERROR');
  assert.equal(err.d.code, 'HELLO_REQUIRED');
  await c.waitClose();
});

test('Protokollversion: v=2 → ERROR PROTO_VERSION {min,max} + Close', async (t) => {
  const server = await startServer();
  t.after(() => server.stop());
  const c = await WsClient.connect(server.wsUrl);
  c.sendRaw(JSON.stringify({ v: 2, t: 'HELLO', seq: 1, d: {} }));
  const err = await c.next('ERROR');
  assert.equal(err.d.code, 'PROTO_VERSION');
  assert.equal(err.d.min, 1);
  assert.equal(err.d.max, 1);
  await c.waitClose();
});

test('PING → PONG mit serverTime; unbekannter Typ → UNKNOWN_TYPE ohne Disconnect', async (t) => {
  const server = await startServer();
  t.after(() => server.stop());
  const c = await WsClient.connect(server.wsUrl);
  await c.hello(newIdentity());
  const pong = await c.request('PING');
  assert.equal(pong.t, 'PONG');
  assert.equal(typeof pong.d.serverTime, 'number');
  const unknown = await c.request('GIBTS_NICHT');
  assert.equal(unknown.d.code, 'UNKNOWN_TYPE');
  const pong2 = await c.request('PING');
  assert.equal(pong2.t, 'PONG', 'Verbindung lebt noch');
  c.close();
});

test('Zweite Verbindung desselben Geräts verdrängt die alte (GOING_DOWN REPLACED)', async (t) => {
  const server = await startServer();
  t.after(() => server.stop());
  const id = newIdentity();
  const c1 = await WsClient.connect(server.wsUrl);
  await c1.hello(id);
  const c2 = await WsClient.connect(server.wsUrl);
  await c2.hello(id);
  const down = await c1.next('GOING_DOWN');
  assert.equal(down.d.reason, 'REPLACED');
  await c1.waitClose();
  const pong = await c2.request('PING');
  assert.equal(pong.t, 'PONG');
  c2.close();
});

test('Übergroße Frames und Binary-Frames → Fehler, kein Crash', async (t) => {
  const server = await startServer();
  t.after(() => server.stop());
  const c = await WsClient.connect(server.wsUrl);
  await c.hello(newIdentity());
  c.sendRaw(JSON.stringify({ v: 1, t: 'PING', d: { pad: 'x'.repeat(20_000) } }));
  const err = await c.next('ERROR');
  assert.equal(err.d.code, 'PAYLOAD_TOO_LARGE');
  c.ws.send(Buffer.from([1, 2, 3]), { binary: true });
  const err2 = await c.next('ERROR');
  assert.equal(err2.d.code, 'BAD_MESSAGE');
  c.close();
});

test('HELLO-Rate-Limit: 5/min pro IP', async (t) => {
  const server = await startServer();
  t.after(() => server.stop());
  // 5 erlaubte HELLOs verbrauchen …
  for (let i = 0; i < 5; i++) {
    const c = await WsClient.connect(server.wsUrl);
    await c.hello(newIdentity(`Spieler${i}`));
    c.close();
    await c.waitClose();
  }
  // … das sechste wird abgelehnt.
  const c6 = await WsClient.connect(server.wsUrl);
  const err = await c6.hello(newIdentity('Zuviel'));
  assert.equal(err.d.code, 'RATE_LIMIT');
  await c6.waitClose();
});
