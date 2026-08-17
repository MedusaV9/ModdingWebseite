import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { runUpdate } from '../scripts/update.js';

const execFileAsync = promisify(execFile);
const SERVER_DIR = fileURLToPath(new URL('..', import.meta.url));

// `npm run update` = Backup → Pull → Install → Migrate → Smoke, with a full
// rollback (git reset + npm ci + backup restore) on ANY failure after the
// pull. The pipeline is dependency-injected; these tests drive it with a
// recording fake instead of touching git/npm.

function fakeRunner({ failOn } = {}) {
  const calls = [];
  const run = async (cmd, args) => {
    const line = `${cmd} ${args.join(' ')}`;
    calls.push(line);
    if (failOn && line.startsWith(failOn)) throw new Error(`boom at: ${line}`);
    if (line === 'git rev-parse HEAD') return 'abc123def456';
    return '';
  };
  return { calls, run };
}

test('update pipeline: happy path runs the phases in order and never restores', async () => {
  const { calls, run } = fakeRunner();
  const restores = [];
  const result = await runUpdate({
    dataDir: '/tmp/fake-data',
    run,
    createBackupFn: async ({ reason, includeMedia }) => {
      assert.equal(reason, 'before-update');
      assert.equal(includeMedia, true);
      return { id: '20260813-b1-before-update' };
    },
    restoreBackupFn: async (args) => { restores.push(args); },
    log: () => {},
  });
  assert.deepEqual(calls, [
    'git rev-parse HEAD',
    'git pull --ff-only',
    'npm ci --omit=dev',
    'npm run migrate',
    `node ${path.join('scripts', 'smoke.js')}`,
  ]);
  assert.deepEqual(restores, []);
  assert.deepEqual(result, { ok: true, oldSha: 'abc123def456', backupId: '20260813-b1-before-update' });
});

test('update pipeline: a failing migrate rolls back git, dependencies AND the backup', async () => {
  const { calls, run } = fakeRunner({ failOn: 'npm run migrate' });
  const restores = [];
  await assert.rejects(
    runUpdate({
      dataDir: '/tmp/fake-data',
      run,
      createBackupFn: async () => ({ id: 'b-before' }),
      restoreBackupFn: async (args) => { restores.push(args); },
      log: () => {},
    }),
    /boom at: npm run migrate/,
  );
  assert.deepEqual(calls, [
    'git rev-parse HEAD',
    'git pull --ff-only',
    'npm ci --omit=dev',
    'npm run migrate',
    // rollback:
    'git reset --hard abc123def456',
    'npm ci --omit=dev',
  ]);
  assert.equal(restores.length, 1);
  assert.equal(restores[0].id, 'b-before');
  assert.equal(restores[0].dataDir, '/tmp/fake-data');
});

test('update pipeline: a fresh data dir (no backup yet) still rolls back code, skips restore', async () => {
  const { calls, run } = fakeRunner({ failOn: 'npm ci' });
  const restores = [];
  await assert.rejects(
    runUpdate({
      dataDir: '/tmp/fake-data',
      run,
      createBackupFn: async () => null, // nothing to back up yet
      restoreBackupFn: async (args) => { restores.push(args); },
      log: () => {},
    }),
    /boom at: npm ci/,
  );
  assert.ok(calls.includes('git reset --hard abc123def456'));
  assert.deepEqual(restores, [], 'no backup — nothing to restore');
});

test('scripts/smoke.js boots the real app against a temp data dir and exits 0', async (t) => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), 'sooodreamy-smoke-'));
  t.after(() => rm(dataDir, { recursive: true, force: true }));
  const { stdout } = await execFileAsync(
    process.execPath,
    [path.join(SERVER_DIR, 'scripts', 'smoke.js'), '--data-dir', dataDir],
    { timeout: 30_000 },
  );
  assert.match(stdout, /\[smoke\] ✓ boots, \/api\/health ok/);
});
