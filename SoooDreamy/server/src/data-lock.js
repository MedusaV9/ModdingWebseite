import crypto from 'node:crypto';
import { mkdir, open, readFile, rename, stat, unlink } from 'node:fs/promises';
import path from 'node:path';

const LOCK_NAME = '.sooodreamy.lock';
const MALFORMED_STALE_MS = 1_000;

export class DataDirLockedError extends Error {
  constructor(dataDir, owner = null) {
    const detail = owner?.pid
      ? ` by PID ${owner.pid} since ${owner.acquiredAt ?? 'an unknown time'}`
      : '';
    super(
      `DATA_DIR is already locked${detail}: ${dataDir}. `
      + 'Stop the other SoooDreamy server, restore, or migration process before retrying.',
    );
    this.name = 'DataDirLockedError';
    this.code = 'DATA_DIR_LOCKED';
    this.dataDir = dataDir;
    this.owner = owner;
  }
}

/**
 * Acquires the process-wide DATA_DIR writer lock using atomic O_EXCL creation.
 * A clean close removes it; after SIGKILL, a later process verifies that the
 * recorded PID is gone before atomically moving the stale lock aside.
 */
export async function acquireDataDirLock(dataDir, { log = () => {} } = {}) {
  const resolved = path.resolve(dataDir);
  const lockFile = path.join(resolved, LOCK_NAME);
  await mkdir(resolved, { recursive: true });

  for (let attempt = 0; attempt < 5; attempt += 1) {
    let handle;
    try {
      handle = await open(lockFile, 'wx', 0o600);
    } catch (err) {
      if (err.code !== 'EEXIST') throw err;
      const owner = await readOwner(lockFile);
      if (owner && processIsAlive(owner.pid)) throw new DataDirLockedError(resolved, owner);
      if (!owner) {
        const age = await lockAge(lockFile);
        if (age < MALFORMED_STALE_MS) {
          await new Promise((resolve) => setTimeout(resolve, MALFORMED_STALE_MS - age));
          continue;
        }
      }
      const stale = `${lockFile}.stale-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`;
      try {
        await rename(lockFile, stale);
        await fsyncDirectory(resolved);
        await unlink(stale).catch(() => {});
        log(`store: recovered stale DATA_DIR lock${owner?.pid ? ` from PID ${owner.pid}` : ''}`);
      } catch (moveError) {
        if (moveError.code !== 'ENOENT') throw new DataDirLockedError(resolved, owner);
      }
      continue;
    }

    const owner = {
      pid: process.pid,
      nonce: crypto.randomBytes(16).toString('hex'),
      acquiredAt: new Date().toISOString(),
    };
    try {
      await handle.writeFile(`${JSON.stringify(owner)}\n`, 'utf8');
      await handle.sync();
      await fsyncDirectory(resolved);
    } catch (err) {
      await handle.close().catch(() => {});
      await unlink(lockFile).catch(() => {});
      throw err;
    }
    return new DataDirLock({ dataDir: resolved, lockFile, handle, owner });
  }

  throw new DataDirLockedError(resolved, await readOwner(lockFile));
}

class DataDirLock {
  constructor({ dataDir, lockFile, handle, owner }) {
    this.dataDir = dataDir;
    this.lockFile = lockFile;
    this.handle = handle;
    this.owner = owner;
    this.released = false;
  }

  async release() {
    if (this.released) return;
    this.released = true;
    const current = await readOwner(this.lockFile);
    await this.handle.close();
    if (current?.nonce !== this.owner.nonce) return;
    try {
      await unlink(this.lockFile);
      await fsyncDirectory(this.dataDir);
    } catch (err) {
      if (err.code !== 'ENOENT') throw err;
    }
  }
}

async function readOwner(lockFile) {
  try {
    const parsed = JSON.parse(await readFile(lockFile, 'utf8'));
    if (!parsed || typeof parsed !== 'object' || !Number.isSafeInteger(parsed.pid)
      || parsed.pid <= 0 || typeof parsed.nonce !== 'string') return null;
    return parsed;
  } catch {
    return null;
  }
}

function processIsAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (err) {
    return err.code === 'EPERM';
  }
}

async function lockAge(lockFile) {
  try {
    const info = await stat(lockFile);
    return Math.max(0, Date.now() - info.mtimeMs);
  } catch {
    return Number.POSITIVE_INFINITY;
  }
}

async function fsyncDirectory(directory) {
  const handle = await open(directory, 'r');
  try {
    await handle.sync();
  } finally {
    await handle.close();
  }
}
