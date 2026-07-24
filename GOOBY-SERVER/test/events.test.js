// Events: Panel-Trigger → Push an Online-Clients + Pull-Queue beim Boot (WELCOME),
// keine Doppel-Zustellung, expiresAt-Filter, Zielgruppen.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { startServer, newIdentity, WsClient } from './helpers.js';
import { triggerEvent } from '../src/events.js';

test('Online-Push: SERVER_EVENT sofort, deliveredTo gemerkt', async (t) => {
  const server = await startServer();
  t.after(() => server.stop());
  const c = await WsClient.connect(server.wsUrl);
  await c.hello(newIdentity());
  t.after(() => c.close());
  const res = triggerEvent(server.ctx, {
    type: 'WEATHER_RAIN',
    params: { durationMin: 60 },
    target: 'all',
    ttlMin: 60,
  });
  assert.equal(res.ok, true);
  assert.equal(res.pushed, 1);
  const evt = await c.next('SERVER_EVENT');
  assert.equal(evt.d.type, 'WEATHER_RAIN');
  assert.equal(evt.d.params.durationMin, 60);
  assert.equal(typeof evt.d.expiresAt, 'number');
});

test('Offline-Pull: Boot holt pendingEvents genau EINMAL ab', async (t) => {
  const server = await startServer();
  t.after(() => server.stop());
  const id = newIdentity();
  // Gerät registrieren, dann offline gehen.
  const c1 = await WsClient.connect(server.wsUrl);
  await c1.hello(id);
  c1.close();
  await c1.waitClose();
  triggerEvent(server.ctx, { type: 'DOUBLE_COINS', params: {}, target: 'all', ttlMin: 60 });

  const c2 = await WsClient.connect(server.wsUrl);
  const welcome = await c2.hello(id);
  assert.equal(welcome.d.pendingEvents.length, 1);
  assert.equal(welcome.d.pendingEvents[0].type, 'DOUBLE_COINS');
  c2.close();
  await c2.waitClose();
  // Zweiter Boot → nichts mehr (deliveredTo).
  const c3 = await WsClient.connect(server.wsUrl);
  const welcome3 = await c3.hello(id);
  assert.equal(welcome3.d.pendingEvents.length, 0);
  c3.close();
});

test('expiresAt: abgelaufene Events werden beim Boot NICHT zugestellt', async (t) => {
  let now = 1_000_000_000_000;
  const server = await startServer({ clock: { now: () => now } });
  t.after(() => server.stop());
  const id = newIdentity();
  const c1 = await WsClient.connect(server.wsUrl);
  await c1.hello(id);
  c1.close();
  await c1.waitClose();
  triggerEvent(server.ctx, { type: 'KURZ', params: {}, target: 'all', ttlMin: 1 });
  now += 2 * 60_000; // Event ist abgelaufen
  const c2 = await WsClient.connect(server.wsUrl);
  const welcome = await c2.hello(id);
  assert.equal(welcome.d.pendingEvents.length, 0);
  c2.close();
});

test('Zielgruppe: Event an einen FriendCode erreicht nur diesen', async (t) => {
  const server = await startServer();
  t.after(() => server.stop());
  const a = await WsClient.connect(server.wsUrl);
  const wa = await a.hello(newIdentity('Anna'));
  const b = await WsClient.connect(server.wsUrl);
  await b.hello(newIdentity('Ben'));
  t.after(() => [a, b].forEach((c) => c.close()));
  const res = triggerEvent(server.ctx, {
    type: 'ANNOUNCEMENT',
    params: { text: 'Nur für Anna' },
    target: wa.d.friendCode,
    ttlMin: 60,
  });
  assert.equal(res.pushed, 1);
  const evt = await a.next('SERVER_EVENT');
  assert.equal(evt.d.params.text, 'Nur für Anna');
  // Ben bekommt nichts: PING-Roundtrip als Synchronisationspunkt, Inbox muss leer sein.
  await b.request('PING');
  assert.equal(b.inbox.filter((m) => m.t === 'SERVER_EVENT').length, 0);
});

test('Validierung: kaputter Typ/Params abgelehnt', async (t) => {
  const server = await startServer();
  t.after(() => server.stop());
  assert.equal(triggerEvent(server.ctx, { type: 'kein typ!!', params: {} }).ok, false);
  assert.equal(triggerEvent(server.ctx, { type: 'OK_TYP', params: [1] }).ok, false);
});
