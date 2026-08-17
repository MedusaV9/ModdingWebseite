import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readdir, readFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { createDailyLogWriter } from '../src/logfile.js';
import { createBackup } from '../src/backup.js';
import { makeApp, setupCouple, client } from './helpers.js';

// Operational polish (Linse 38): extended /api/health vital signs, the
// disk-full upload guard, and built-in daily log rotation.

test('/api/health reports uptime, disk, backup age and quarantine state', async (t) => {
  const { baseUrl, dataDir, app } = await makeApp(t);
  const anon = client(baseUrl);

  const before = await anon.get('/api/health');
  assert.equal(before.status, 200);
  assert.equal(before.body.ok, true);
  assert.ok(before.body.uptimeSeconds >= 0);
  assert.equal(before.body.nodeVersion, process.version);
  assert.ok(before.body.disk.totalBytes > 0);
  assert.ok(before.body.disk.freeBytes > 0);
  assert.equal(typeof before.body.disk.warn, 'boolean');
  assert.equal(before.body.lastBackup, null);
  assert.ok(before.body.warnings.includes('backup_never'));
  assert.equal(before.body.quarantinedCouples, 0);

  // After a verified backup the age shows up and the warning disappears.
  await setupCouple(baseUrl);
  await app.store.flush(); // a backup needs a store.json on disk
  await createBackup({ dataDir, reason: 'test' });
  const after = await anon.get('/api/health');
  assert.ok(after.body.lastBackup, 'backup listed');
  assert.match(after.body.lastBackup.id, /-test$/);
  assert.ok(after.body.lastBackup.ageMinutes <= 1);
  assert.equal(after.body.warnings.includes('backup_never'), false);
  assert.equal(after.body.warnings.includes('backup_old'), false);
});

test('media uploads are refused with 507 disk_full before the disk runs out', async (t) => {
  // An absurdly high stop threshold makes every real disk look "full".
  process.env.DISK_STOP_MB = String(Number.MAX_SAFE_INTEGER);
  let app;
  try {
    app = await makeApp(t);
  } finally {
    delete process.env.DISK_STOP_MB;
  }
  const { a } = await setupCouple(app.baseUrl);
  const res = await a.api.post('/api/photos', {
    body: Buffer.from('jpeg'),
    headers: { 'content-type': 'image/jpeg' },
  });
  assert.equal(res.status, 507);
  assert.equal(res.body.error, 'disk_full');
  assert.match(res.body.message, /MB free/);

  // Health mirrors the paused state so remote helpers see it instantly.
  const health = await client(app.baseUrl).get('/api/health');
  assert.ok(health.body.warnings.includes('disk_full'));
});

test('daily log writer rotates per day and keeps only the newest files', async (t) => {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'sooodreamy-logs-'));
  t.after(() => rm(dir, { recursive: true, force: true }));

  let day = 1;
  const writer = createDailyLogWriter({
    dir,
    keep: 3,
    now: () => new Date(Date.UTC(2026, 0, day)),
  });

  writer.write('first line of day 1');
  writer.write('second line of day 1');
  assert.equal(
    await readFile(path.join(dir, 'server-2026-01-01.log'), 'utf8'),
    'first line of day 1\nsecond line of day 1\n',
  );

  for (day = 2; day <= 5; day += 1) writer.write(`hello day ${day}`);
  const files = (await readdir(dir)).sort();
  assert.deepEqual(files, ['server-2026-01-03.log', 'server-2026-01-04.log', 'server-2026-01-05.log']);
  assert.equal(await readFile(path.join(dir, 'server-2026-01-05.log'), 'utf8'), 'hello day 5\n');
});
