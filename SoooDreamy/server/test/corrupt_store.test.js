import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readdir, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { Store } from '../src/store.js';
import { client, makeApp, setupCouple } from './helpers.js';

// NOTE: node:test runs after-hooks in registration order — tests that boot an
// app with makeApp(t, {dataDir}) must register this rm AFTER makeApp so the
// app is closed before its data dir disappears.
async function tempDir(t, prefix = 'sooodreamy-corrupt-') {
  const dir = await mkdtemp(path.join(os.tmpdir(), prefix));
  if (t) t.after(() => rm(dir, { recursive: true, force: true }));
  return dir;
}

function segmentFile(dataDir, coupleId) {
  return path.join(dataDir, 'segments', `${encodeURIComponent(coupleId)}.json`);
}

async function quarantineFiles(dataDir) {
  try {
    return await readdir(path.join(dataDir, 'quarantine'));
  } catch (err) {
    if (err.code === 'ENOENT') return [];
    throw err;
  }
}

test('segments are written atomically with checksum envelope and a .bak generation', async (t) => {
  const dataDir = await tempDir(t);
  const store = await new Store({ dataDir }).init();
  store.data.couples.c_env = { id: 'c_env', messages: [{ id: 'm1', text: 'gen one' }] };
  store.markDirty();
  await store.flush();

  const raw = JSON.parse(await readFile(segmentFile(dataDir, 'c_env'), 'utf8'));
  assert.equal(raw.format, 'segment-v2');
  assert.match(raw.sha256, /^[0-9a-f]{64}$/);
  assert.equal(raw.couple.messages[0].text, 'gen one');

  store.data.couples.c_env.messages.push({ id: 'm2', text: 'gen two' });
  store.markDirty();
  await store.flush();
  await store.close();

  const bak = JSON.parse(await readFile(`${segmentFile(dataDir, 'c_env')}.bak`, 'utf8'));
  assert.equal(bak.couple.messages.length, 1, '.bak keeps the previous good generation');
});

test('a torn segment write falls back to the last good .bak and quarantines the wreck', async (t) => {
  const dataDir = await tempDir(t);
  const store = await new Store({ dataDir }).init();
  store.data.couples.c_torn = { id: 'c_torn', messages: [{ id: 'm1', text: 'safe' }] };
  store.markDirty();
  await store.flush();
  store.data.couples.c_torn.messages.push({ id: 'm2', text: 'newest' });
  store.markDirty();
  await store.close();

  // Simulate a truncated write (power loss mid-flush without the atomic rename).
  const file = segmentFile(dataDir, 'c_torn');
  const full = await readFile(file, 'utf8');
  await writeFile(file, full.slice(0, Math.floor(full.length / 2)), 'utf8');

  const reopened = await new Store({ dataDir }).init();
  assert.deepEqual(
    reopened.data.couples.c_torn.messages.map((m) => m.id),
    ['m1', 'm2'],
    'the previous segment plus durable WAL restore the newest generation',
  );
  assert.equal(reopened.quarantinedCoupleIds.size, 0);
  const quarantined = await quarantineFiles(dataDir);
  assert.equal(quarantined.length, 1);
  assert.match(quarantined[0], /c_torn/);

  // The recovery is persisted: after a flush the main segment is valid again.
  await reopened.flush();
  await reopened.close();
  const rewritten = await new Store({ dataDir }).init();
  assert.deepEqual(rewritten.data.couples.c_torn.messages.map((m) => m.id), ['m1', 'm2']);
  await rewritten.close();
});

test('checksum mismatches and invalid UTF-8 are detected as corruption', async (t) => {
  const dataDir = await tempDir(t);
  const store = await new Store({ dataDir }).init();
  store.data.couples.c_sum = { id: 'c_sum', name: 'original' };
  store.data.couples.c_utf = { id: 'c_utf', name: 'bytes' };
  store.markDirty();
  await store.close();

  // Tamper c_sum but keep the stale checksum; write raw garbage bytes to c_utf.
  const sumFile = segmentFile(dataDir, 'c_sum');
  const tampered = JSON.parse(await readFile(sumFile, 'utf8'));
  tampered.couple.name = 'evil edit';
  await writeFile(sumFile, JSON.stringify(tampered), 'utf8');
  await writeFile(segmentFile(dataDir, 'c_utf'), Buffer.from([0xff, 0xfe, 0x00, 0x99, 0x7b]));

  const reopened = await new Store({ dataDir }).init();
  assert.equal(reopened.data.couples.c_sum.name, 'original');
  assert.equal(reopened.data.couples.c_utf.name, 'bytes');
  assert.deepEqual([...reopened.quarantinedCoupleIds], []);
  assert.equal((await quarantineFiles(dataDir)).length, 2);
  await reopened.close();
});

test('one broken couple is restored from WAL without taking the server down', async (t) => {
  const dataDir = await tempDir(null);
  const first = await makeApp(null, { dataDir });
  const pairA = await setupCouple(first.baseUrl);
  const pairB = await setupCouple(first.baseUrl);
  await client(first.baseUrl, pairB.a.token).post('/api/messages', {
    json: { type: 'text', text: 'still here' },
  });
  await first.close();

  // Couple A's segment rots on disk (no .bak yet — single write generation).
  await writeFile(segmentFile(dataDir, pairA.coupleId), '{"format":"segment-v2","sha256":"00', 'utf8');

  const { baseUrl, app } = await makeApp(t, { dataDir });
  t.after(() => rm(dataDir, { recursive: true, force: true }));
  // Couple B is untouched.
  const okB = await client(baseUrl, pairB.a.token).get('/api/messages');
  assert.equal(okB.status, 200);
  assert.equal(okB.body.messages.at(-1).text, 'still here');
  // Couple A's acknowledged state is restored from the durable journal.
  const recoveredA = await client(baseUrl, pairA.a.token).get('/api/couple');
  assert.equal(recoveredA.status, 200);
  // Health retains the forensic file but reports no unrecoverable couple.
  const health = await fetch(`${baseUrl}/api/health`).then((r) => r.json());
  assert.equal(health.storage.quarantine.couples, 0);
  assert.ok(health.storage.quarantine.files >= 1);
  assert.equal(app.store.quarantinedCoupleIds.has(pairA.coupleId), false);
});

test('a corrupt manifest recovers from store.json.bak with sessions intact', async (t) => {
  const dataDir = await tempDir(null);
  const first = await makeApp(null, { dataDir });
  const pair = await setupCouple(first.baseUrl);
  await first.close();
  // Second boot + write → store.json.bak generation exists.
  const second = await makeApp(null, { dataDir });
  await client(second.baseUrl, pair.a.token).post('/api/messages', { json: { type: 'text', text: 'bak me' } });
  await second.close();

  await writeFile(path.join(dataDir, 'store.json'), 'not json at all {{{', 'utf8');

  const { baseUrl } = await makeApp(t, { dataDir });
  t.after(() => rm(dataDir, { recursive: true, force: true }));
  const res = await client(baseUrl, pair.a.token).get('/api/couple');
  assert.equal(res.status, 200, 'old bearer still works — tokens came from the .bak manifest');
  assert.ok((await quarantineFiles(dataDir)).some((f) => f.includes('store.json')));
});

test('manifest AND .bak lost: couples are rebuilt from segments, members re-attach via rejoin', async (t) => {
  const dataDir = await tempDir(null);
  const first = await makeApp(null, { dataDir });
  const anon = client(first.baseUrl);
  const created = await anon.post('/api/couples', { json: { name: 'Mia' } });
  const joined = await anon.post('/api/couples/join', {
    json: { code: created.body.couple.code, name: 'Ben' },
  });
  await client(first.baseUrl, created.body.token).post('/api/messages', {
    json: { type: 'text', text: 'survives even this' },
  });
  await first.close();

  await writeFile(path.join(dataDir, 'store.json'), '\u0000garbage', 'utf8');
  await rm(path.join(dataDir, 'store.json.bak'), { force: true });

  const { baseUrl } = await makeApp(t, { dataDir });
  t.after(() => rm(dataDir, { recursive: true, force: true }));
  // Retained WAL history restores both sessions and couple data.
  assert.equal((await client(baseUrl, created.body.token).get('/api/couple')).status, 200);
  // The recovery key remains a valid independent recovery path.
  const rejoined = await client(baseUrl).post('/api/couples/rejoin', {
    json: { code: created.body.couple.code, recoveryKey: created.body.recoveryKey },
  });
  assert.equal(rejoined.status, 200);
  assert.equal(rejoined.body.memberId, created.body.memberId);
  const messages = await client(baseUrl, rejoined.body.token).get('/api/messages');
  assert.equal(messages.body.messages.at(-1).text, 'survives even this');
  assert.equal(rejoined.body.couple.members.length, 2);
  void joined;
});
