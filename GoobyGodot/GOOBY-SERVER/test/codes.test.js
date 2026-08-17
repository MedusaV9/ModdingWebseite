// Codes: Lifecycle (anlegen → einlösen → deaktivieren), Redeem GENAU 1× pro deviceId,
// maxUses, Gültigkeitsfenster, Rate-Limit.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { startServer, newIdentity, WsClient, bearer } from './helpers.js';
import { createCode, deactivateCode, redeem } from '../src/codes.js';

test('createCode: Validierung (Name, Reward, Duplikat)', async (t) => {
  const server = await startServer();
  t.after(() => server.stop());
  const ctx = server.ctx;
  assert.equal(createCode(ctx, { code: 'SOMMER26', reward: { coins: 500 } }).ok, true);
  assert.equal(createCode(ctx, { code: 'SOMMER26', reward: { coins: 1 } }).code, 'DUPLICATE');
  assert.equal(createCode(ctx, { code: 'x', reward: {} }).code, 'BAD_CODE');
  assert.equal(createCode(ctx, { code: 'GUT-123', reward: 'nope' }).code, 'BAD_REWARD');
  assert.equal(createCode(ctx, { code: 'klein!', reward: {} }).code, 'BAD_CODE');
});

test('Redeem-Regeln: 1×/Gerät, maxUses, Fenster, inaktiv', async (t) => {
  const server = await startServer();
  t.after(() => server.stop());
  const ctx = server.ctx;
  const now = 1_000_000_000;
  createCode(ctx, { code: 'EINMAL', reward: { coins: 10 }, maxUses: 2 });
  // Gerät A: ok, dann ALREADY_REDEEMED (Groß/Kleinschreibung egal).
  assert.equal(redeem(ctx, 'dev-a', 'einmal', now).ok, true);
  assert.equal(redeem(ctx, 'dev-a', 'EINMAL', now).code, 'ALREADY_REDEEMED');
  // Gerät B: ok → maxUses erschöpft → Gerät C: EXHAUSTED.
  assert.equal(redeem(ctx, 'dev-b', 'EINMAL', now).ok, true);
  assert.equal(redeem(ctx, 'dev-c', 'EINMAL', now).code, 'EXHAUSTED');
  // Unbekannt / inaktiv / Zeitfenster.
  assert.equal(redeem(ctx, 'dev-a', 'GIBTSNICHT', now).code, 'UNKNOWN');
  createCode(ctx, { code: 'SPAETER', reward: {}, validFrom: now + 1000 });
  assert.equal(redeem(ctx, 'dev-a', 'SPAETER', now).code, 'NOT_YET_VALID');
  createCode(ctx, { code: 'VORBEI', reward: {}, validUntil: now - 1000 });
  assert.equal(redeem(ctx, 'dev-a', 'VORBEI', now).code, 'EXPIRED');
  createCode(ctx, { code: 'AUS', reward: {} });
  deactivateCode(ctx, 'AUS');
  assert.equal(redeem(ctx, 'dev-a', 'AUS', now).code, 'INACTIVE');
});

test('REST /api/codes/redeem: Auth, Erfolg einmalig, Persistenz über Neustart-Flush', async (t) => {
  const server = await startServer();
  t.after(() => server.stop());
  createCode(server.ctx, { code: 'SOMMER26', reward: { coins: 500, sticker: 'sonne' } });
  const id = newIdentity();
  const c = await WsClient.connect(server.wsUrl);
  await c.hello(id);
  t.after(() => c.close());

  const post = (body, auth = bearer(id)) =>
    fetch(`${server.url}/api/codes/redeem`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', ...(auth ? { authorization: auth } : {}) },
      body: JSON.stringify(body),
    });

  assert.equal((await post({ code: 'SOMMER26' }, null)).status, 401);
  assert.equal((await post({ code: 'SOMMER26' }, `Bearer ${id.deviceId}:falsch`)).status, 401);

  const ok = await (await post({ code: 'SOMMER26' })).json();
  assert.equal(ok.ok, true);
  assert.deepEqual(ok.reward, { coins: 500, sticker: 'sonne' });
  const again = await (await post({ code: 'SOMMER26' })).json();
  assert.equal(again.ok, false);
  assert.equal(again.code, 'ALREADY_REDEEMED');

  // Einlösung landet persistiert in codes.json (Flush).
  server.ctx.store.flush();
  const { Storage } = await import('../src/storage.js');
  const reread = new Storage(server.dataDir, { flushMs: 60_000 });
  const codes = reread.collection('codes', { codes: {} }).codes;
  assert.equal(codes.SOMMER26.uses, 1);
  assert.equal(typeof codes.SOMMER26.redemptions[id.deviceId], 'number');
  reread.close();
});

test('Redeem-Rate-Limit: 5/15 min pro Gerät', async (t) => {
  const server = await startServer();
  t.after(() => server.stop());
  const id = newIdentity();
  const c = await WsClient.connect(server.wsUrl);
  await c.hello(id);
  t.after(() => c.close());
  const post = () =>
    fetch(`${server.url}/api/codes/redeem`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: bearer(id) },
      body: JSON.stringify({ code: 'GIBTSNICHT' }),
    });
  for (let i = 0; i < 5; i++) assert.equal((await post()).status, 200); // UNKNOWN, aber gezählt
  assert.equal((await post()).status, 429);
});
