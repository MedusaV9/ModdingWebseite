import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { access } from 'node:fs/promises';
import path from 'node:path';
import { makeApp, setupCouple, wsOpen } from './helpers.js';

// The server never sees plaintext — from its perspective a vault item is an
// opaque blob. Random bytes stand in for a real AES-GCM ciphertext.
const BLOB = randomBytes(4096);

const CONFIG = {
  kdf: 'pbkdf2-sha256',
  iterations: 210000,
  salt: Buffer.from('per-couple-salt-1234').toString('base64'),
  verifier: Buffer.from('sealed-known-plaintext').toString('base64'),
};

test('vault config: validation, first write, broadcast, lock-in with items', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  // Empty until configured.
  assert.equal((await a.api.get('/api/vault/config')).body.config, null);

  // Validation: iterations out of range, missing salt.
  const badIter = await a.api.put('/api/vault/config', { json: { ...CONFIG, iterations: 12 } });
  assert.equal(badIter.status, 400);
  assert.equal(badIter.body.error, 'bad_iterations');
  const noSalt = await a.api.put('/api/vault/config', { json: { ...CONFIG, salt: undefined } });
  assert.equal(noSalt.status, 400);

  // First write wins and is broadcast (partner devices adopt the KDF params).
  const set = await a.api.put('/api/vault/config', { json: CONFIG });
  assert.equal(set.status, 200);
  assert.equal(set.body.config.salt, CONFIG.salt);
  assert.equal(set.body.config.iterations, CONFIG.iterations);
  assert.equal(set.body.config.createdBy, a.memberId);
  const evt = await bSock.waitFor('vault_config_set');
  assert.equal(evt.payload.config.verifier, CONFIG.verifier);

  // Config CAN be replaced while the vault is empty (e.g. PIN typo directly
  // after setup) …
  const replace = await b.api.put('/api/vault/config', { json: { ...CONFIG, iterations: 300000 } });
  assert.equal(replace.status, 200);

  // … but NOT once items exist (a new key would corrupt them).
  await a.api.post('/api/vault/items', { body: BLOB, headers: { 'x-vault-kind': 'photo' } });
  const lockedIn = await b.api.put('/api/vault/config', { json: CONFIG });
  assert.equal(lockedIn.status, 409);
  assert.equal(lockedIn.body.error, 'vault_locked_in');
});

test('vault items: upload/list/raw roundtrip/delete, opaque blobs, ws broadcasts', async (t) => {
  const { baseUrl, dataDir } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  // Uploading before the key exists is rejected.
  const early = await a.api.post('/api/vault/items', { body: BLOB, headers: { 'x-vault-kind': 'photo' } });
  assert.equal(early.status, 409);
  assert.equal(early.body.error, 'vault_not_configured');

  await a.api.put('/api/vault/config', { json: CONFIG });
  await bSock.waitFor('vault_config_set');

  // Bad kind → 400; note/photo/video are the only hints the server knows.
  const badKind = await a.api.post('/api/vault/items', { body: BLOB, headers: { 'x-vault-kind': 'diary' } });
  assert.equal(badKind.status, 400);

  const up = await a.api.post('/api/vault/items', { body: BLOB, headers: { 'x-vault-kind': 'note' } });
  assert.equal(up.status, 201);
  const item = up.body.item;
  assert.equal(item.kind, 'note');
  assert.equal(item.bytes, BLOB.length);
  assert.equal(item.uploaderId, a.memberId);
  assert.equal(item.url, `/api/vault/${item.id}/raw`);
  const added = await bSock.waitFor('vault_item_added');
  assert.deepEqual(added.payload.item, item);
  await access(path.join(dataDir, 'media', 'vault', `${item.id}.bin`));

  // Raw roundtrip: the server hands back EXACTLY the ciphertext it received.
  const raw = await b.api.get(item.url);
  assert.equal(raw.status, 200);
  assert.deepEqual(raw.body, BLOB);

  // Range requests work (resumable downloads for big encrypted videos).
  const part = await b.api.get(item.url, { headers: { range: 'bytes=0-99' } });
  assert.equal(part.status, 206);
  assert.equal(part.body.length, 100);
  assert.deepEqual(part.body, BLOB.subarray(0, 100));

  // Newest first.
  await a.api.post('/api/vault/items', { body: BLOB, headers: { 'x-vault-kind': 'photo' } });
  const list = await b.api.get('/api/vault');
  assert.equal(list.body.items.length, 2);
  assert.equal(list.body.items[1].id, item.id);

  // Shared vault: the partner may delete the other's item.
  const del = await b.api.del(`/api/vault/${item.id}`);
  assert.equal(del.status, 200);
  const deleted = await bSock.waitFor('vault_item_deleted');
  assert.deepEqual(deleted.payload, { id: item.id });
  await assert.rejects(access(path.join(dataDir, 'media', 'vault', `${item.id}.bin`)));
  assert.equal((await a.api.get(item.url)).status, 404);
});

test('vault reset wipes items + config and allows a fresh key', async (t) => {
  const { baseUrl, dataDir } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  await aSock.waitFor('welcome');

  await a.api.put('/api/vault/config', { json: CONFIG });
  const up = await a.api.post('/api/vault/items', { body: BLOB, headers: { 'x-vault-kind': 'video' } });
  const item = up.body.item;

  // Partner resets (forgotten PIN escape hatch).
  const reset = await b.api.del('/api/vault');
  assert.equal(reset.status, 200);
  await aSock.waitFor('vault_reset');
  assert.equal((await a.api.get('/api/vault/config')).body.config, null);
  assert.deepEqual((await a.api.get('/api/vault')).body.items, []);
  await assert.rejects(access(path.join(dataDir, 'media', 'vault', `${item.id}.bin`)));

  // A brand-new key can be set afterwards.
  const again = await a.api.put('/api/vault/config', { json: { ...CONFIG, iterations: 250000 } });
  assert.equal(again.status, 200);
});

test('vault stays out of stats and inbox; dissolve deletes vault files', async (t) => {
  const { baseUrl, dataDir } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  const since = new Date(Date.now() - 60_000).toISOString();
  await a.api.put('/api/vault/config', { json: CONFIG });
  const up = await a.api.post('/api/vault/items', { body: BLOB, headers: { 'x-vault-kind': 'photo' } });
  const item = up.body.item;

  // Discretion: no vault trace in stats or the missed-activity inbox.
  const stats = await b.api.get('/api/stats');
  assert.equal(JSON.stringify(stats.body).includes('vault'), false);
  const inbox = await b.api.get(`/api/inbox?since=${encodeURIComponent(since)}`);
  assert.equal(JSON.stringify(inbox.body).includes('vault'), false);

  // Dissolving the couple removes the encrypted files from disk.
  await a.api.del('/api/couple');
  await assert.rejects(access(path.join(dataDir, 'media', 'vault', `${item.id}.bin`)));
});
