import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { ApnsProvider } from '../src/apns.js';
import { PushService } from '../src/push.js';
import { makeApp, setupCouple } from './helpers.js';

const TOKEN_A = 'aa'.repeat(32);
const TOKEN_B = 'bb'.repeat(32);

async function waitFor(check) {
  for (let attempt = 0; attempt < 50; attempt += 1) {
    if (check()) return;
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
  assert.fail('timed out waiting for asynchronous push delivery');
}

test('push registration is session-device scoped, bounded, and token-redacted', async (t) => {
  const { baseUrl, app } = await makeApp(t, { pushProvider: null });
  const { a } = await setupCouple(baseUrl);

  const bad = await a.api.post('/api/push-devices/current', {
    json: {
      apnsToken: 'not-a-token',
      environment: 'development',
      bundleId: 'app.sooodreamy.ios',
      language: 'de',
      deviceId: 'spoofed-device',
    },
  });
  assert.equal(bad.status, 400);
  assert.equal(bad.body.error, 'bad_apns_token');

  const registered = await a.api.post('/api/push-devices/current', {
    json: {
      apnsToken: TOKEN_A,
      environment: 'development',
      bundleId: 'app.sooodreamy.ios',
      language: 'de',
      deviceId: 'spoofed-device',
    },
  });
  assert.equal(registered.status, 200);
  assert.equal(registered.body.deliveryAvailable, false);
  assert.equal(registered.body.registration.language, 'de');
  assert.equal('apnsToken' in registered.body.registration, false);
  assert.notEqual(registered.body.registration.deviceId, 'spoofed-device');

  const listed = await a.api.get('/api/push-devices');
  assert.equal(listed.status, 200);
  assert.equal(listed.body.registrations.length, 1);
  assert.equal(JSON.stringify(listed.body).includes(TOKEN_A), false);

  const removed = await a.api.del('/api/push-devices/current');
  assert.equal(removed.status, 200);
  assert.equal(removed.body.removed, true);

  const couple = Object.values(app.store.data.couples)[0];
  const store = { markDirty() {} };
  const service = new PushService();
  for (let index = 0; index < 10; index += 1) {
    service.register({
      store,
      couple,
      memberId: a.memberId,
      deviceId: `device-${index}`,
      apnsToken: index.toString(16).padStart(64, '0'),
      environment: 'development',
      bundleId: 'app.sooodreamy.ios',
      language: 'en',
    });
  }
  assert.equal(service.registrations(couple, a.memberId).length, 8);
});

test('partner actions deliver localized privacy-safe APNs payloads', async (t) => {
  const deliveries = [];
  const provider = {
    async send(request) {
      deliveries.push(request);
    },
  };
  const { baseUrl } = await makeApp(t, { pushProvider: provider });
  const { a, b } = await setupCouple(baseUrl);
  const registration = await b.api.post('/api/push-devices/current', {
    json: {
      apnsToken: TOKEN_B,
      environment: 'production',
      bundleId: 'app.sooodreamy.ios',
      language: 'de',
    },
  });
  assert.equal(registration.body.deliveryAvailable, true);

  const secretText = 'private message body must not enter APNs';
  const sent = await a.api.post('/api/messages', {
    json: { type: 'text', text: secretText, clientMessageId: 'push-test-message' },
  });
  assert.equal(sent.status, 201);
  await waitFor(() => deliveries.length === 1);

  assert.equal(deliveries[0].token, TOKEN_B);
  assert.equal(deliveries[0].environment, 'production');
  assert.equal(deliveries[0].bundleId, 'app.sooodreamy.ios');
  assert.equal(deliveries[0].payload.type, 'message');
  assert.equal(deliveries[0].payload.link, 'sooodreamy://tab/chat');
  assert.match(deliveries[0].payload.aps.alert.title, /^Nachricht von /);
  assert.equal(deliveries[0].payload.aps.alert.body, 'Neue Nachricht');
  assert.equal(JSON.stringify(deliveries[0].payload).includes(secretText), false);
  assert.match(deliveries[0].idempotencyKey, /^[0-9a-f-]{36}$/u);
});

test('transient push failures survive restart and retry with one idempotency key', async (t) => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), 'sooodreamy-push-outbox-'));
  let first = null;
  let second = null;
  t.after(async () => {
    await second?.close();
    await first?.close();
    await rm(dataDir, { recursive: true, force: true });
  });

  const failedAttempts = [];
  first = await makeApp(null, {
    dataDir,
    pushRetryIntervalMs: 0,
    pushRetryBaseMs: 1,
    pushProvider: {
      async send(request) {
        failedAttempts.push(request);
        throw new Error('provider temporarily unavailable');
      },
    },
  });
  const pair = await setupCouple(first.baseUrl);
  await pair.b.api.post('/api/push-devices/current', {
    json: {
      apnsToken: TOKEN_B,
      environment: 'production',
      bundleId: 'app.sooodreamy.ios',
      language: 'en',
    },
  });
  assert.equal((await pair.a.api.post('/api/messages', {
    json: { type: 'text', text: 'persist this notification' },
  })).status, 201);
  const couple = first.app.store.data.couples[pair.coupleId];
  await waitFor(() => couple.pushOutbox?.[0]?.attempts === 1);
  assert.equal(couple.pushOutbox[0].status, 'pending');
  const key = couple.pushOutbox[0].idempotencyKey;
  assert.equal(failedAttempts[0].idempotencyKey, key);

  await first.close();
  first = null;
  const delivered = [];
  second = await makeApp(null, {
    dataDir,
    pushRetryIntervalMs: 1,
    pushRetryBaseMs: 1,
    pushProvider: { async send(request) { delivered.push(request); } },
  });
  await waitFor(() => delivered.length === 1);
  const recoveredCouple = second.app.store.data.couples[pair.coupleId];
  assert.equal(delivered[0].idempotencyKey, key);
  assert.equal(recoveredCouple.pushOutbox[0].status, 'delivered');
  assert.equal(recoveredCouple.pushOutbox[0].attempts, 2);
});

test('push outbox remains bounded when every pending delivery fails', async () => {
  const couple = {
    id: 'couple-bounded',
    pushDevices: [{
      id: 'registration-b',
      memberId: 'member-b',
      deviceId: 'device-b',
      apnsToken: TOKEN_B,
      environment: 'development',
      bundleId: 'app.sooodreamy.ios',
      language: 'en',
      disabledAt: null,
    }],
  };
  const store = { markDirty() {} };
  const service = new PushService({
    maxOutboxEntries: 2,
    retryBaseMs: 60_000,
    provider: { async send() { throw new Error('offline'); } },
  });
  const notification = {
    store,
    couple,
    senderMemberId: 'member-a',
    type: 'message',
    title: 'Message',
    body: 'New message',
    link: 'sooodreamy://tab/chat',
  };
  await service.notifyPartner(notification);
  await service.notifyPartner(notification);
  const refused = await service.notifyPartner(notification);
  assert.equal(couple.pushOutbox.length, 2);
  assert.equal(refused.queued, 0);
});

test('permanent APNs rejection disables a registration and session revoke removes it', async (t) => {
  const provider = {
    async send() {
      const error = new Error('unregistered');
      error.code = 'Unregistered';
      error.permanent = true;
      throw error;
    },
  };
  const { baseUrl, app } = await makeApp(t, { pushProvider: provider });
  const { a, b } = await setupCouple(baseUrl);
  await b.api.post('/api/push-devices/current', {
    json: {
      apnsToken: TOKEN_B,
      environment: 'development',
      bundleId: 'app.sooodreamy.ios',
      language: 'en',
    },
  });

  assert.equal((await a.api.post('/api/touches', { json: { type: 'kiss' } })).status, 201);
  await waitFor(() => {
    const couple = Object.values(app.store.data.couples)[0];
    return couple.pushDevices?.[0]?.disabledAt != null;
  });
  const deadLetter = Object.values(app.store.data.couples)[0].pushOutbox[0];
  assert.equal(deadLetter.status, 'dead_letter');
  assert.equal(deadLetter.attempts, 1);
  const health = await b.api.get('/api/health');
  assert.equal(health.body.pushOutbox.deadLetter, 1);
  assert.ok(health.body.warnings.includes('push_dead_letter'));
  const disabled = await b.api.get('/api/push-devices');
  assert.ok(disabled.body.registrations[0].disabledAt);

  const sessions = await b.api.get('/api/sessions');
  const current = sessions.body.sessions.find((session) => session.current);
  assert.ok(current);
  assert.equal((await b.api.post(`/api/sessions/${current.id}/revoke`, { json: {} })).status, 200);
  const couple = Object.values(app.store.data.couples)[0];
  assert.equal(couple.pushDevices.length, 0);
});

test('APNs provider stays explicitly gated and caches signed provider JWTs', async () => {
  assert.equal(await ApnsProvider.fromEnvironment({ env: {} }), null);
  const logs = [];
  assert.equal(await ApnsProvider.fromEnvironment({
    env: { APNS_ENABLED: '1' },
    log: (...parts) => logs.push(parts.join(' ')),
  }), null);
  assert.match(logs[0], /APNS_TEAM_ID/);

  const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
  const provider = new ApnsProvider({
    teamId: 'TEAM123456',
    keyId: 'KEY1234567',
    privateKey,
  });
  const first = provider.providerToken(1_700_000_000_000);
  const second = provider.providerToken(1_700_000_001_000);
  assert.equal(first, second);
  assert.equal(first.split('.').length, 3);
  const claims = JSON.parse(Buffer.from(first.split('.')[1], 'base64url').toString('utf8'));
  assert.equal(claims.iss, 'TEAM123456');
  assert.equal(claims.iat, 1_700_000_000);
});
