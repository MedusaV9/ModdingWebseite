#!/usr/bin/env node
// One-command update with a safety net (docs/AUTOSTART.md, docs/MIGRATION.md):
//
//   npm stop / Ctrl-C          # STOP the server first (npm ci swaps node_modules)
//   npm run update             # Backup → Pull → Install → Migrate → Smoke boot
//
// Every phase prints ✓/✗. If ANY phase after the git pull fails, everything is
// rolled back: git back to the previous commit, npm ci again, and the
// before-update backup (incl. media) restored — "Alles zurückgedreht, nichts
// kaputt." Exit code 0 only when the update fully succeeded.
import { spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createBackup, restoreBackup } from '../src/backup.js';

const SERVER_DIR = fileURLToPath(new URL('..', import.meta.url));

/** Runs a command, streaming output; resolves stdout, throws on non-zero exit. */
export function execStep(cmd, args, { cwd, capture = false } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, {
      cwd,
      stdio: capture ? ['ignore', 'pipe', 'inherit'] : 'inherit',
      shell: process.platform === 'win32', // npm/git are .cmd shims on Windows
    });
    let out = '';
    if (capture) child.stdout.on('data', (chunk) => { out += chunk; });
    child.on('error', reject);
    child.on('exit', (code) => {
      if (code === 0) resolve(out.trim());
      else reject(new Error(`${cmd} ${args.join(' ')} exited with code ${code}`));
    });
  });
}

/**
 * The update pipeline, dependency-injected so tests can drive it without
 * touching git or npm. `run(cmd, args, opts)` must throw on failure.
 */
export async function runUpdate({
  serverDir = SERVER_DIR,
  dataDir,
  run = execStep,
  createBackupFn = createBackup,
  restoreBackupFn = restoreBackup,
  log = console.log,
} = {}) {
  const phase = (name) => log(`[update] → ${name}`);
  const done = (name) => log(`[update] ✓ ${name}`);

  phase('remember current version');
  const oldSha = await run('git', ['rev-parse', 'HEAD'], { cwd: serverDir, capture: true });
  done(`current version ${String(oldSha).slice(0, 10)}`);

  phase('backup (before-update, incl. media)');
  const backup = await createBackupFn({ dataDir, reason: 'before-update', includeMedia: true, log });
  done(backup ? `backup ${backup.id}` : 'nothing to back up yet (fresh data dir)');

  phase('git pull --ff-only');
  await run('git', ['pull', '--ff-only'], { cwd: serverDir });
  done('pulled');

  try {
    phase('npm ci --omit=dev');
    await run('npm', ['ci', '--omit=dev'], { cwd: serverDir });
    done('dependencies installed');

    phase('npm run migrate');
    await run('npm', ['run', 'migrate'], { cwd: serverDir });
    done('data migrated');

    phase('smoke boot (scripts/smoke.js)');
    await run('node', [path.join('scripts', 'smoke.js')], { cwd: serverDir });
    done('server boots and answers /api/health');

    log('[update] ✓ update complete — start the server again with: npm start');
    return { ok: true, oldSha, backupId: backup?.id ?? null };
  } catch (err) {
    log(`[update] ✗ ${err.message}`);
    log('[update] rolling back — nothing will be left half-updated…');
    await run('git', ['reset', '--hard', oldSha], { cwd: serverDir });
    await run('npm', ['ci', '--omit=dev'], { cwd: serverDir });
    if (backup) await restoreBackupFn({ dataDir, id: backup.id, log });
    log('[update] ✓ Alles zurückgedreht, nichts kaputt — der alte Stand läuft wieder.');
    log('[update]   (Everything rolled back — the previous version is intact.)');
    throw err;
  }
}

// CLI entry (skipped when imported by tests).
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const args = process.argv.slice(2);
  const at = args.indexOf('--data-dir');
  const dataDir = at !== -1 && args[at + 1]
    ? args[at + 1]
    : process.env.DATA_DIR || fileURLToPath(new URL('../data', import.meta.url));
  try {
    await runUpdate({ dataDir });
  } catch {
    process.exit(1);
  }
}
