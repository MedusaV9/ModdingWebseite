#!/usr/bin/env node
// Creates one verified backup of the JSON state (and optionally media), then
// applies the retention rules. The DATA_DIR lock deliberately requires the
// server to be stopped so every acknowledged write is in the snapshot.
//
//   npm run backup
//   npm run backup -- --reason before-update
//   npm run backup -- --no-media   # metadata-only, explicitly unprotected media
//   npm run backup -- --data-dir /srv/sooodreamy/data --no-prune
import { fileURLToPath } from 'node:url';
import { createBackup, listBackups, pruneBackups } from '../src/backup.js';
import { acquireDataDirLock } from '../src/data-lock.js';

const args = process.argv.slice(2);
function flag(name) {
  return args.includes(name);
}
function option(name, fallback) {
  const at = args.indexOf(name);
  return at !== -1 && args[at + 1] !== undefined ? args[at + 1] : fallback;
}

const dataDir = option('--data-dir', process.env.DATA_DIR || fileURLToPath(new URL('../data', import.meta.url)));
const log = (...values) => console.log('[backup]', ...values);

let dataDirLock;
try {
  dataDirLock = await acquireDataDirLock(dataDir, { log });
  const result = await createBackup({
    dataDir,
    reason: option('--reason', 'manual'),
    includeMedia: !flag('--no-media') && process.env.BACKUP_INCLUDE_MEDIA !== '0',
    log,
  });
  if (result === null) {
    console.log(`[backup] nothing to back up yet in ${dataDir} (no store.json / segments)`);
  } else {
    if (!flag('--no-prune')) {
      await pruneBackups({
        dataDir,
        keepLast: Number(process.env.BACKUP_KEEP_LAST) > 0 ? Number(process.env.BACKUP_KEEP_LAST) : 10,
        keepHourly: Number(process.env.BACKUP_KEEP_HOURLY) > 0 ? Number(process.env.BACKUP_KEEP_HOURLY) : 48,
        keepDaily: Number(process.env.BACKUP_KEEP_DAILY) > 0 ? Number(process.env.BACKUP_KEEP_DAILY) : 14,
        log,
      });
    }
    const all = await listBackups(dataDir);
    console.log(`[backup] done — ${result.id} (${result.files} files, ${result.bytes} bytes); ${all.length} backup(s) kept in ${dataDir}/backups`);
  }
} catch (err) {
  console.error(`[backup] ${err.message}`);
  process.exitCode = 1;
} finally {
  await dataDirLock?.release().catch(() => {});
}
