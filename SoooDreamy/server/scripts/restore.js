#!/usr/bin/env node
// Lists, verifies and restores on-server backups (see docs/BACKUP.md).
//
//   npm run restore -- --list
//   npm run restore -- --verify 20260813-063000-auto
//   npm run restore -- --restore 20260813-063000-auto
//
// ⚠️ STOP the server before --restore: a running server would overwrite the
// restored files from its in-memory state on the next flush. A `pre-restore`
// safety backup of the current state is taken automatically.
import { fileURLToPath } from 'node:url';
import { listBackups, restoreBackup, verifyBackup } from '../src/backup.js';

const args = process.argv.slice(2);
function option(name, fallback) {
  const at = args.indexOf(name);
  return at !== -1 && args[at + 1] !== undefined ? args[at + 1] : fallback;
}

const dataDir = option('--data-dir', process.env.DATA_DIR || fileURLToPath(new URL('../data', import.meta.url)));
const log = (...values) => console.log('[restore]', ...values);

if (args.includes('--list')) {
  const backups = await listBackups(dataDir);
  if (backups.length === 0) {
    console.log(`[restore] no backups found in ${dataDir}/backups`);
    process.exit(0);
  }
  console.log(`[restore] ${backups.length} backup(s) in ${dataDir}/backups (newest first):\n`);
  for (const b of backups) {
    const size = b.bytes > 1024 * 1024 ? `${(b.bytes / 1024 / 1024).toFixed(1)} MB` : `${(b.bytes / 1024).toFixed(1)} kB`;
    console.log(`  ${b.id}  ${b.createdAt ?? '(unreadable)'}  reason=${b.reason}  ${b.files} files  ${size}${b.includesMedia ? '  +media' : ''}`);
  }
  console.log('\n  restore with: npm run restore -- --restore <id>   (stop the server first!)');
  process.exit(0);
}

const verifyId = option('--verify', null);
if (verifyId) {
  const { ok, problems } = await verifyBackup(dataDir, verifyId);
  if (ok) {
    console.log(`[restore] backup ${verifyId} is intact ✓`);
    process.exit(0);
  }
  console.error(`[restore] backup ${verifyId} FAILED verification:`);
  for (const problem of problems) console.error(`  - ${problem}`);
  process.exit(1);
}

const restoreId = option('--restore', null);
if (restoreId) {
  console.log(`[restore] ⚠️  make sure the server is STOPPED — restoring ${restoreId} into ${dataDir}`);
  try {
    const result = await restoreBackup({ dataDir, id: restoreId, log });
    console.log(`[restore] done — ${result.restored} files restored; previous state saved as ${result.safetyBackupId}`);
    console.log('[restore] start the server again with: npm start');
    process.exit(0);
  } catch (err) {
    console.error(`[restore] ${err.message}`);
    process.exit(1);
  }
}

console.log('Usage: npm run restore -- --list | --verify <id> | --restore <id> [--data-dir <path>]');
process.exit(2);
