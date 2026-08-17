import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Store } from '../src/store.js';
import { createBackup, listBackups, pruneBackups, restoreBackup, verifyBackup } from '../src/backup.js';
import { client, makeApp, setupCouple } from './helpers.js';

const run = promisify(execFile);
const serverRoot = fileURLToPath(new URL('..', import.meta.url));

async function tempDir(prefix = 'sooodreamy-backup-') {
  return mkdtemp(path.join(os.tmpdir(), prefix));
}

test('createBackup snapshots the JSON state with per-file checksums', async (t) => {
  const dataDir = await tempDir();
  t.after(() => rm(dataDir, { recursive: true, force: true }));

  assert.equal(await createBackup({ dataDir }), null, 'nothing to back up in an empty dir');

  const store = await new Store({ dataDir }).init();
  store.data.couples.c_bk = { id: 'c_bk', messages: [{ id: 'm1', text: 'precious' }] };
  store.data.tokens.digest = { coupleId: 'c_bk', memberId: 'm_x' };
  await store.saveMedia('photos', 'precious.jpg', Buffer.from('photo bytes'));
  store.markDirty();
  await store.close();

  const result = await createBackup({ dataDir, reason: 'unit test!' });
  assert.match(result.id, /^\d{8}-\d{6}-[0-9a-f]{12}-unit-test$/);
  assert.equal(result.files, 3); // store.json + one segment + media by default
  assert.equal(result.includesMedia, true);

  const backups = await listBackups(dataDir);
  assert.equal(backups.length, 1);
  assert.equal(backups[0].reason, 'unit test!');

  const verified = await verifyBackup(dataDir, result.id);
  assert.equal(verified.ok, true);
  const manifest = JSON.parse(
    await readFile(path.join(dataDir, 'backups', result.id, 'backup.json'), 'utf8'),
  );
  assert.deepEqual(
    Object.keys(manifest.files).sort(),
    ['media/photos/precious.jpg', 'segments/c_bk.json', 'store.json'],
  );
  for (const file of Object.values(manifest.files)) assert.match(file.sha256, /^[0-9a-f]{64}$/);
});

test('same-timestamp backups get exclusive unique IDs and never overwrite', async (t) => {
  const dataDir = await tempDir();
  t.after(() => rm(dataDir, { recursive: true, force: true }));
  const store = await new Store({ dataDir }).init();
  store.data.couples.c_unique = { id: 'c_unique', messages: [{ id: 'm1', text: 'first' }] };
  store.markDirty();
  await store.close();

  const now = new Date('2026-08-14T04:22:33.000Z');
  const first = await createBackup({ dataDir, reason: 'auto', now });
  const second = await createBackup({ dataDir, reason: 'auto', now });
  assert.notEqual(first.id, second.id);
  assert.match(first.id, /^20260814-042233-[0-9a-f]{12}-auto$/);
  assert.equal((await listBackups(dataDir)).length, 2);
  assert.equal((await verifyBackup(dataDir, first.id)).ok, true);
  assert.equal((await verifyBackup(dataDir, second.id)).ok, true);
});

test('external backup refuses to race a running DATA_DIR writer', async (t) => {
  const dataDir = await tempDir();
  t.after(() => rm(dataDir, { recursive: true, force: true }));
  const store = await new Store({ dataDir }).init();
  store.data.couples.c_locked = { id: 'c_locked', messages: [] };
  store.markDirty();
  await assert.rejects(
    run('node', ['scripts/backup.js', '--data-dir', dataDir], { cwd: serverRoot }),
    (err) => err.code === 1 && /DATA_DIR is already locked/u.test(err.stderr),
  );
  await store.close();
});

test('restore refuses tampered backups but round-trips intact ones (with safety backup)', async (t) => {
  const dataDir = await tempDir();
  t.after(() => rm(dataDir, { recursive: true, force: true }));

  // State A → backup.
  const store = await new Store({ dataDir }).init();
  store.data.couples.c_rt = { id: 'c_rt', messages: [{ id: 'm1', text: 'state A' }] };
  store.markDirty();
  await store.close();
  const backupA = await createBackup({ dataDir, reason: 'state-a', now: new Date(Date.now() - 60_000) });

  // Mutate to state B.
  const storeB = await new Store({ dataDir }).init();
  storeB.data.couples.c_rt.messages.push({ id: 'm2', text: 'state B' });
  storeB.data.couples.c_new = { id: 'c_new', messages: [] };
  storeB.markDirty();
  await storeB.close();

  // A tampered COPY of the backup must be refused.
  const tamperDir = path.join(dataDir, 'backups', backupA.id, 'segments', 'c_rt.json');
  const original = await readFile(tamperDir, 'utf8');
  await writeFile(tamperDir, original.replace('state A', 'state Ä'), 'utf8');
  await assert.rejects(
    restoreBackup({ dataDir, id: backupA.id }),
    /refusing to restore .*checksum mismatch/,
  );
  await writeFile(tamperDir, original, 'utf8'); // repair the backup again

  // Intact restore brings state A back and keeps state B as pre-restore backup.
  const result = await restoreBackup({ dataDir, id: backupA.id });
  assert.equal(result.safetyBackupId !== null, true);
  const restored = await new Store({ dataDir }).init();
  assert.deepEqual(restored.data.couples.c_rt.messages.map((m) => m.id), ['m1']);
  assert.equal(restored.data.couples.c_new, undefined, 'state B couple is gone after restore');
  await restored.close();

  const backups = await listBackups(dataDir);
  const safety = backups.find((b) => b.id === result.safetyBackupId);
  assert.equal(safety.reason, 'pre-restore');
});

test('prune keeps newest-per-hour/day plus the newest N and deletes the rest', async (t) => {
  const dataDir = await tempDir();
  t.after(() => rm(dataDir, { recursive: true, force: true }));
  const now = new Date('2026-08-13T12:00:00.000Z');

  // Fabricate 30 backups: every 30 min over the last 15 h.
  await mkdir(path.join(dataDir, 'backups'), { recursive: true });
  for (let i = 0; i < 30; i++) {
    const at = new Date(now.getTime() - i * 30 * 60_000);
    const id = `fabricated-${String(i).padStart(2, '0')}`;
    await mkdir(path.join(dataDir, 'backups', id), { recursive: true });
    await writeFile(
      path.join(dataDir, 'backups', id, 'backup.json'),
      JSON.stringify({ format: 'sooodreamy-backup-v1', id, createdAt: at.toISOString(), reason: 'auto', files: {} }),
      'utf8',
    );
  }

  const { kept, deleted } = await pruneBackups({ dataDir, keepLast: 4, keepHourly: 48, keepDaily: 14, now });
  // 15 h of half-hourly backups → ~16 hour buckets + newest 4 (overlapping).
  assert.ok(kept.length >= 15 && kept.length <= 20, `kept ${kept.length}`);
  assert.equal(kept.length + deleted.length, 30);
  // The newest 4 must survive; the oldest same-hour sibling must not.
  for (const id of ['fabricated-00', 'fabricated-01', 'fabricated-02', 'fabricated-03']) {
    assert.ok(kept.includes(id), `${id} must be kept`);
  }
  assert.equal((await listBackups(dataDir)).length, kept.length);
});

test('backup + restore CLI work end-to-end against a real data dir', async (t) => {
  const dataDir = await tempDir();
  const app = await makeApp(null, { dataDir });
  const pair = await setupCouple(app.baseUrl);
  await pair.a.api.post('/api/messages', { json: { type: 'text', text: 'CLI test' } });
  await pair.a.api.post('/api/photos', {
    body: Buffer.from('backup-media'),
    headers: { 'content-type': 'image/jpeg' },
  });
  await app.close();
  t.after(() => rm(dataDir, { recursive: true, force: true }));

  const created = await run('node', ['scripts/backup.js', '--data-dir', dataDir, '--reason', 'cli'], { cwd: serverRoot });
  assert.match(created.stdout, /created \d{8}-\d{6}-[0-9a-f]{12}-cli/);

  const listed = await run('node', ['scripts/restore.js', '--list', '--data-dir', dataDir], { cwd: serverRoot });
  assert.match(listed.stdout, /reason=cli/);
  assert.match(listed.stdout, /\+media/);
  const id = listed.stdout.match(/(\d{8}-\d{6}-[0-9a-f]{12}-cli)/)[1];

  const verified = await run('node', ['scripts/restore.js', '--verify', id, '--data-dir', dataDir], { cwd: serverRoot });
  assert.match(verified.stdout, /is intact/);

  // Damage the live store, then restore via CLI and boot the app again.
  await writeFile(path.join(dataDir, 'store.json'), 'garbage', 'utf8');
  await rm(path.join(dataDir, 'store.json.bak'), { force: true });
  const restored = await run('node', ['scripts/restore.js', '--restore', id, '--data-dir', dataDir], { cwd: serverRoot });
  assert.match(restored.stdout, /files restored/);

  const revived = await makeApp(t, { dataDir });
  const messages = await client(revived.baseUrl, pair.a.token).get('/api/messages');
  assert.equal(messages.status, 200);
  assert.equal(messages.body.messages.at(-1).text, 'CLI test');
});

test('the auto-backup scheduler produces verified backups on its interval', async (t) => {
  const dataDir = await tempDir();
  const app = await makeApp(null, { dataDir, backupIntervalMinutes: 0.002 }); // ≈120 ms
  t.after(async () => {
    await app.close();
    await rm(dataDir, { recursive: true, force: true });
  });
  await setupCouple(app.baseUrl);
  // Poll instead of a fixed sleep: on a loaded CI runner the ≈120 ms
  // interval timer can fire late (run 31904755259 flaked at 400 ms).
  let backups = [];
  for (let attempt = 0; attempt < 30 && backups.length === 0; attempt += 1) {
    await new Promise((resolve) => setTimeout(resolve, 100));
    backups = await listBackups(dataDir);
  }
  await app.close();
  backups = await listBackups(dataDir);
  assert.ok(backups.length >= 1, 'at least one auto backup');
  assert.equal(backups[0].reason, 'auto');
  assert.equal((await verifyBackup(dataDir, backups[0].id)).ok, true);
});
