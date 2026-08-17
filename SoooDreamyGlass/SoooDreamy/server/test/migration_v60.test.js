import { test } from 'node:test';
import assert from 'node:assert/strict';
import { client, makeApp, setupCouple } from './helpers.js';

function logicalCouple(snapshot) {
  const logical = structuredClone(snapshot);
  delete logical.id;
  delete logical.code;
  return logical;
}

test('server A export → server B import preserves logical content and requires re-pairing', async (t) => {
  const source = await makeApp(t);
  const sourceCouple = await setupCouple(source.baseUrl);
  await sourceCouple.a.api.patch('/api/couple', {
    json: { name: 'Mia & Ben', anniversary: '2024-02-14' },
  });
  await sourceCouple.a.api.post('/api/messages', {
    json: { type: 'text', text: 'Unsere erste migrierte Nachricht' },
  });
  await sourceCouple.b.api.post('/api/bucket', { json: { text: 'Sterne anschauen' } });
  await sourceCouple.a.api.post('/api/events', {
    json: { title: 'Jahrestag', date: '2027-02-14', repeatsYearly: true },
  });

  const exported = await sourceCouple.a.api.get('/api/migration/export');
  assert.equal(exported.status, 200);
  assert.equal(exported.body.bundle.format, 'sooodreamy-couple-v1');
  assert.equal(exported.body.bundle.schemaVersion, 1);
  assert.equal(exported.body.bundle.media.included, false);
  assert.match(exported.body.bundle.digest, /^[0-9a-f]{64}$/);

  const destination = await makeApp(t);
  const created = await client(destination.baseUrl).post('/api/couples', {
    json: { name: 'Mia', avatar: '🦊', color: '#FF5C8A' },
  });
  const destinationAPI = client(destination.baseUrl, created.body.token);

  const withoutConfirmation = await destinationAPI.post('/api/migration/import', {
    json: {
      sourceMemberId: sourceCouple.a.memberId,
      bundle: exported.body.bundle,
    },
  });
  assert.equal(withoutConfirmation.status, 400);
  assert.equal(withoutConfirmation.body.error, 'migration_confirmation_required');

  const imported = await destinationAPI.post('/api/migration/import', {
    json: {
      confirm: 'IMPORT',
      sourceMemberId: sourceCouple.a.memberId,
      bundle: exported.body.bundle,
    },
  });
  assert.equal(imported.status, 200);
  assert.equal(imported.body.memberId, sourceCouple.a.memberId);
  assert.equal(imported.body.requiresPartnerRepair, true);
  assert.equal(imported.body.digest, exported.body.bundle.digest);

  const reExported = await destinationAPI.get('/api/migration/export');
  assert.equal(reExported.status, 200);
  assert.deepEqual(
    logicalCouple(reExported.body.bundle.couple),
    logicalCouple(exported.body.bundle.couple),
  );

  const oldPartnerToken = await client(destination.baseUrl, sourceCouple.b.token).get('/api/couple');
  assert.equal(oldPartnerToken.status, 401, 'source sessions must never migrate');

  const repaired = await client(destination.baseUrl).post('/api/couples/join', {
    json: {
      code: imported.body.code,
      name: 'Ben',
      avatar: '🐻',
      color: '#4A90D9',
    },
  });
  assert.equal(repaired.status, 200);
  assert.equal(repaired.body.memberId, sourceCouple.b.memberId);
  assert.equal(repaired.body.couple.members.length, 2);

  const afterRepair = await client(destination.baseUrl, repaired.body.token)
    .get('/api/migration/export');
  assert.equal(afterRepair.status, 200);
  assert.deepEqual(
    logicalCouple(afterRepair.body.bundle.couple),
    logicalCouple(exported.body.bundle.couple),
  );
});

test('migration rejects tampering, unsupported schemas, and non-empty destinations', async (t) => {
  const source = await makeApp(t);
  const sourceCouple = await setupCouple(source.baseUrl);
  const exported = (await sourceCouple.a.api.get('/api/migration/export')).body.bundle;

  const destination = await makeApp(t);
  const created = await client(destination.baseUrl).post('/api/couples', {
    json: { name: 'Mia' },
  });
  const api = client(destination.baseUrl, created.body.token);

  const tampered = structuredClone(exported);
  tampered.couple.name = 'Mallory';
  const badDigest = await api.post('/api/migration/import', {
    json: {
      confirm: 'IMPORT',
      sourceMemberId: sourceCouple.a.memberId,
      bundle: tampered,
    },
  });
  assert.equal(badDigest.status, 400);
  assert.equal(badDigest.body.error, 'migration_digest_mismatch');

  const future = structuredClone(exported);
  future.schemaVersion = 999;
  const unsupported = await api.post('/api/migration/import', {
    json: {
      confirm: 'IMPORT',
      sourceMemberId: sourceCouple.a.memberId,
      bundle: future,
    },
  });
  assert.equal(unsupported.status, 409);
  assert.equal(unsupported.body.error, 'unsupported_migration');

  const activity = await api.post('/api/bucket', { json: { text: 'not fresh' } });
  assert.equal(activity.status, 201);
  const notEmpty = await api.post('/api/migration/import', {
    json: {
      confirm: 'IMPORT',
      sourceMemberId: sourceCouple.a.memberId,
      bundle: exported,
    },
  });
  assert.equal(notEmpty.status, 409);
  assert.equal(notEmpty.body.error, 'migration_destination_not_empty');
});
