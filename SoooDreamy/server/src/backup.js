import crypto from 'node:crypto';
import { mkdir, open, readdir, readFile, writeFile, rename, rm, stat, unlink } from 'node:fs/promises';
import path from 'node:path';
import { acquireDataDirLock } from './data-lock.js';

/** Lowercase hex SHA-256 of raw file bytes. */
function sha256Bytes(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

// ---------------------------------------------------------------------------
// v6.1 rotating on-server backups.
//
// A backup is a folder under <dataDir>/backups/<id>/ containing a copy of
// store.json + segments/*.json (and optionally media/) plus a `backup.json`
// manifest with a SHA-256 for every file. Backups are staged in a temp folder
// and atomically renamed into place; restore refuses when any hash mismatches.
//
// Retention (prune): keep the newest `keepLast` backups unconditionally, plus
// the newest backup of every hour bucket for `keepHourly` hours, plus the
// newest backup of every day bucket for `keepDaily` days.
// ---------------------------------------------------------------------------

const BACKUP_MANIFEST = 'backup.json';

export function backupsDir(dataDir) {
  return path.join(dataDir, 'backups');
}

function backupId(reason, now = new Date()) {
  const stamp = now.toISOString().replace(/[-:]/g, '').replace(/\..+$/, '').replace('T', '-');
  const safeReason = String(reason).toLowerCase()
    .replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 32) || 'manual';
  return `${stamp}-${crypto.randomBytes(6).toString('hex')}-${safeReason}`;
}

/** All JSON-state files worth backing up, as data-dir-relative paths. */
async function collectStateFiles(dataDir, { includeMedia = false } = {}) {
  const files = [];
  const addIfFile = async (rel) => {
    try {
      if ((await stat(path.join(dataDir, rel))).isFile()) files.push(rel);
    } catch {
      /* missing → skip */
    }
  };
  await addIfFile('store.json');
  try {
    for (const entry of await readdir(path.join(dataDir, 'segments'), { withFileTypes: true })) {
      if (!entry.isFile() || !entry.name.endsWith('.json')) continue; // live segments only
      files.push(path.join('segments', entry.name).replaceAll('\\', '/'));
    }
  } catch {
    /* no segments dir yet */
  }
  if (includeMedia) {
    const walk = async (rel) => {
      let entries;
      try {
        entries = await readdir(path.join(dataDir, rel), { withFileTypes: true });
      } catch {
        return;
      }
      for (const entry of entries) {
        const childRel = path.join(rel, entry.name).replaceAll('\\', '/');
        if (entry.isDirectory()) await walk(childRel);
        else if (entry.isFile()) files.push(childRel);
      }
    };
    await walk('media');
  }
  return files;
}

/**
 * Creates one verified backup. Returns the summary (or null when there is no
 * state to back up yet). The caller is responsible for flushing the store
 * first so the files on disk are current.
 */
export async function createBackup({
  dataDir,
  reason = 'manual',
  includeMedia = true,
  now = new Date(),
  log = () => {},
}) {
  const files = await collectStateFiles(dataDir, { includeMedia });
  if (files.length === 0) return null;
  const id = backupId(reason, now);
  const root = backupsDir(dataDir);
  const staging = path.join(root, `.tmp-${id}-${process.pid}-${crypto.randomBytes(4).toString('hex')}`);
  const target = path.join(root, id);
  const claimFile = path.join(root, `.claim-${id}`);
  await mkdir(root, { recursive: true });
  const claim = await open(claimFile, 'wx', 0o600);

  const manifestFiles = {};
  let bytes = 0;
  try {
    await mkdir(staging);
    for (const rel of files) {
      const content = await readFile(path.join(dataDir, rel));
      const dest = path.join(staging, rel);
      await mkdir(path.dirname(dest), { recursive: true });
      await writeFile(dest, content);
      // Verify what actually landed on disk, not what we had in memory.
      const written = await readFile(dest);
      const digest = sha256Bytes(written);
      if (digest !== sha256Bytes(content)) {
        throw new Error(`backup verification failed for ${rel}`);
      }
      manifestFiles[rel] = { sha256: digest, bytes: written.length };
      bytes += written.length;
    }
    const manifest = {
      format: 'sooodreamy-backup-v1',
      id,
      createdAt: now.toISOString(),
      reason,
      includesMedia: includeMedia,
      files: manifestFiles,
    };
    await writeFile(path.join(staging, BACKUP_MANIFEST), JSON.stringify(manifest, null, 2), 'utf8');
    try {
      await stat(target);
      throw new Error(`refusing to overwrite existing backup ${id}`);
    } catch (err) {
      if (err.code !== 'ENOENT') throw err;
    }
    await rename(staging, target);
    log(`backup: created ${id} (${files.length} files, ${bytes} bytes${includeMedia ? ', incl. media' : ''})`);
    return {
      id,
      path: target,
      files: files.length,
      bytes,
      createdAt: manifest.createdAt,
      reason,
      includesMedia: includeMedia,
    };
  } catch (err) {
    await rm(staging, { recursive: true, force: true });
    throw err;
  } finally {
    await claim.close();
    await unlink(claimFile).catch(() => {});
  }
}

/** Lists available backups, newest first. Unreadable entries are reported, not thrown. */
export async function listBackups(dataDir) {
  const root = backupsDir(dataDir);
  let entries;
  try {
    entries = await readdir(root, { withFileTypes: true });
  } catch (err) {
    if (err.code === 'ENOENT') return [];
    throw err;
  }
  const backups = [];
  for (const entry of entries) {
    if (!entry.isDirectory() || entry.name.startsWith('.tmp-')) continue;
    try {
      const manifest = JSON.parse(await readFile(path.join(root, entry.name, BACKUP_MANIFEST), 'utf8'));
      const bytes = Object.values(manifest.files ?? {}).reduce((sum, f) => sum + (f.bytes ?? 0), 0);
      backups.push({
        id: entry.name,
        createdAt: manifest.createdAt,
        reason: manifest.reason ?? 'unknown',
        files: Object.keys(manifest.files ?? {}).length,
        bytes,
        includesMedia: Boolean(manifest.includesMedia),
      });
    } catch {
      backups.push({ id: entry.name, createdAt: null, reason: 'unreadable-manifest', files: 0, bytes: 0 });
    }
  }
  return backups.sort((a, b) => String(b.createdAt ?? '').localeCompare(String(a.createdAt ?? '')));
}

/** Hash-checks every file of one backup. Returns {ok, problems: [string]}. */
export async function verifyBackup(dataDir, id) {
  const root = path.join(backupsDir(dataDir), path.basename(id));
  const problems = [];
  let manifest;
  try {
    manifest = JSON.parse(await readFile(path.join(root, BACKUP_MANIFEST), 'utf8'));
  } catch (err) {
    return { ok: false, problems: [`backup manifest unreadable: ${err.message}`] };
  }
  for (const [rel, expected] of Object.entries(manifest.files ?? {})) {
    try {
      const content = await readFile(path.join(root, rel));
      if (sha256Bytes(content) !== expected.sha256) {
        problems.push(`${rel}: checksum mismatch`);
      }
    } catch (err) {
      problems.push(`${rel}: ${err.message}`);
    }
  }
  return { ok: problems.length === 0, problems, manifest };
}

/**
 * Restores one backup into the data dir. The server must be STOPPED — a
 * running server would overwrite the restored state from memory.
 *
 * Refuses when the backup fails its integrity check. Takes a `pre-restore`
 * safety backup of the current state first, then replaces store.json and the
 * segments (stale .bak generations are removed so nothing old shadows the
 * restored files). Media is only touched when the backup includes media.
 */
export async function restoreBackup({
  dataDir,
  id,
  log = () => {},
  now = new Date(),
  dataDirLock = null,
}) {
  const lock = dataDirLock ?? await acquireDataDirLock(dataDir, { log });
  try {
    return await restoreBackupLocked({ dataDir, id, log, now });
  } finally {
    if (!dataDirLock) await lock.release();
  }
}

async function restoreBackupLocked({ dataDir, id, log, now }) {
  const verified = await verifyBackup(dataDir, id);
  if (!verified.ok) {
    throw new Error(`refusing to restore ${id}: ${verified.problems.join('; ')}`);
  }
  const safety = await createBackup({ dataDir, reason: 'pre-restore', now, log });
  const root = path.join(backupsDir(dataDir), path.basename(id));
  const restored = [];

  // Remove current live state that could shadow the restored one.
  await rm(path.join(dataDir, 'store.json.bak'), { force: true });
  await rm(path.join(dataDir, 'store.wal'), { force: true });
  await rm(path.join(dataDir, 'store.wal.tmp'), { force: true });
  try {
    for (const entry of await readdir(path.join(dataDir, 'segments'), { withFileTypes: true })) {
      if (entry.isFile()) await unlink(path.join(dataDir, 'segments', entry.name));
    }
  } catch {
    /* no segments dir */
  }

  for (const rel of Object.keys(verified.manifest.files)) {
    const content = await readFile(path.join(root, rel));
    const dest = path.join(dataDir, rel);
    await mkdir(path.dirname(dest), { recursive: true });
    const tmp = `${dest}.tmp`;
    await writeFile(tmp, content);
    await rename(tmp, dest);
    restored.push(rel);
  }
  log(`backup: restored ${id} (${restored.length} files); previous state saved as ${safety?.id ?? 'n/a'}`);
  return { id, restored: restored.length, safetyBackupId: safety?.id ?? null };
}

/**
 * Applies the retention rules and deletes everything else.
 * Returns {kept: [id], deleted: [id]}.
 */
export async function pruneBackups({
  dataDir,
  keepLast = 10,
  keepHourly = 48,
  keepDaily = 14,
  now = new Date(),
  log = () => {},
}) {
  const backups = (await listBackups(dataDir)).filter((b) => b.createdAt !== null);
  const keep = new Set();
  for (const backup of backups.slice(0, keepLast)) keep.add(backup.id);

  const hourCutoff = now.getTime() - keepHourly * 3_600_000;
  const dayCutoff = now.getTime() - keepDaily * 86_400_000;
  const newestPerBucket = new Map();
  for (const backup of backups) {
    const at = Date.parse(backup.createdAt);
    if (Number.isNaN(at)) continue;
    if (at >= hourCutoff) {
      const bucket = `h${Math.floor(at / 3_600_000)}`;
      if (!newestPerBucket.has(bucket)) newestPerBucket.set(bucket, backup.id);
    }
    if (at >= dayCutoff) {
      const bucket = `d${Math.floor(at / 86_400_000)}`;
      if (!newestPerBucket.has(bucket)) newestPerBucket.set(bucket, backup.id);
    }
  }
  for (const id of newestPerBucket.values()) keep.add(id);

  const deleted = [];
  for (const backup of backups) {
    if (keep.has(backup.id)) continue;
    await rm(path.join(backupsDir(dataDir), backup.id), { recursive: true, force: true });
    deleted.push(backup.id);
  }
  if (deleted.length > 0) log(`backup: pruned ${deleted.length} old backup(s)`);
  return { kept: [...keep], deleted };
}

/**
 * Hourly auto-backup loop for the running server (interval configurable via
 * BACKUP_INTERVAL_MINUTES, 0 disables). Flushes the store before each run so
 * the on-disk files are current. Returns a stop() function.
 */
export function startBackupScheduler({
  store,
  dataDir,
  intervalMinutes = 60,
  keepLast = 10,
  keepHourly = 48,
  keepDaily = 14,
  includeMedia = true,
  log = () => {},
}) {
  if (!Number.isFinite(intervalMinutes) || intervalMinutes <= 0) return () => Promise.resolve();
  let stopped = false;
  let inFlight = null;
  const run = async () => {
    if (stopped) return;
    try {
      await store.flush();
      if (stopped) return;
      await createBackup({ dataDir, reason: 'auto', includeMedia, log });
      if (stopped) return;
      await pruneBackups({ dataDir, keepLast, keepHourly, keepDaily, log });
    } catch (err) {
      log('backup: scheduled backup failed', err);
    }
  };
  const timer = setInterval(() => {
    inFlight = run().finally(() => { inFlight = null; });
  }, intervalMinutes * 60_000);
  timer.unref?.();
  return async () => {
    stopped = true;
    clearInterval(timer);
    if (inFlight) await inFlight;
  };
}
