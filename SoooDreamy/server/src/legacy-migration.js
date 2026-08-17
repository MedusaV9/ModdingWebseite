import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { acquireDataDirLock } from './data-lock.js';
import { Store } from './store.js';
import { isDigestKey, upgradeLegacyTokens } from './security.js';
import { migrateGameStore, CURRENT_GAME_RULES_VERSION } from './game-migrations.js';
import { createBackup } from './backup.js';

// ---------------------------------------------------------------------------
// v6.1 operator migration for legacy (v1.x, e.g. 1.5.4) data directories.
// See docs/MIGRATION.md for the full story. The core of the actual data
// transformation is the very same production code every server boot runs:
//
//   - Store.init()          v1 inline store.json → segmented-v1 + segments/
//   - upgradeLegacyTokens() raw bearer keys → SHA-256 session records
//   - migrateGameStore()    pre-v4 relay games → replayed or invalidated
//
// This module adds detection, reporting, a mandatory pre-migration backup
// and a --dry-run mode around them, and is deliberately idempotent: running
// it on an already-current data dir changes nothing.
// ---------------------------------------------------------------------------

/**
 * Read-only inspection of a data dir. Never writes.
 *
 * @returns {Promise<{
 *   state: 'empty'|'unreadable'|'legacy-v1'|'current',
 *   couples: number,
 *   legacyTokens: number,
 *   staleGames: number,
 *   detail: string,
 * }>}
 */
export async function inspectDataDir(dataDir) {
  const result = { state: 'empty', couples: 0, legacyTokens: 0, staleGames: 0, detail: '' };
  let parsed;
  try {
    parsed = JSON.parse(await readFile(path.join(dataDir, 'store.json'), 'utf8'));
  } catch (err) {
    if (err.code === 'ENOENT') {
      result.detail = 'no store.json — nothing to migrate';
      return result;
    }
    result.state = 'unreadable';
    result.detail = `store.json is unreadable (${err.message}); the server quarantines + `
      + 'self-heals this at boot — or restore a backup (npm run restore)';
    return result;
  }

  const tokens = parsed.tokens ?? {};
  result.legacyTokens = Object.entries(tokens)
    .filter(([key, record]) => !isDigestKey(key) || !record?.sessionId).length;

  const countStaleGames = (couples) => {
    let stale = 0;
    for (const couple of Object.values(couples)) {
      for (const game of couple?.games ?? []) {
        if ((game.rulesVersion ?? 0) !== CURRENT_GAME_RULES_VERSION && game.state !== 'ended') stale += 1;
      }
    }
    return stale;
  };

  if (parsed.format === 'segmented-v1') {
    result.state = 'current';
    result.couples = Object.keys(parsed.couples ?? {}).length;
    // Games live in the segments — count without loading everything twice.
    let stale = 0;
    try {
      for (const entry of await readdir(path.join(dataDir, 'segments'), { withFileTypes: true })) {
        if (!entry.isFile() || !entry.name.endsWith('.json')) continue;
        try {
          const segment = JSON.parse(await readFile(path.join(dataDir, 'segments', entry.name), 'utf8'));
          const couple = segment?.format === 'segment-v2' ? segment.couple : segment;
          stale += countStaleGames({ one: couple });
        } catch {
          /* corrupt segments are the store's (quarantine) business, not ours */
        }
      }
    } catch {
      /* no segments dir */
    }
    result.staleGames = stale;
    result.detail = 'current segmented layout';
    return result;
  }

  // v1.x inline layout (every couple inside store.json) — 1.0.0 through 5.1.x.
  result.state = 'legacy-v1';
  result.couples = Object.keys(parsed.couples ?? {}).length;
  result.staleGames = countStaleGames(parsed.couples ?? {});
  result.detail = `legacy v1 inline store (store version ${parsed.version ?? 1})`;
  return result;
}

/** True when the inspection found any migration work at all. */
export function needsMigration(inspection) {
  return inspection.state === 'legacy-v1'
    || (inspection.state === 'current' && (inspection.legacyTokens > 0 || inspection.staleGames > 0));
}

/**
 * Runs the actual migration: pre-migration backup → segment compaction →
 * eager token upgrade → game-rules migration. Idempotent; safe to re-run.
 */
export async function migrateDataDir({ dataDir, log = () => {} }) {
  const dataDirLock = await acquireDataDirLock(dataDir, { log });
  let store;
  try {
    const backup = await createBackup({ dataDir, reason: 'pre-migration', log });
    store = await new Store({ dataDir, log, dataDirLock }).init();
    const tokensUpgraded = upgradeLegacyTokens(store);
    const games = migrateGameStore({ store, log });
    store.markDirty();
    await store.close(); // final flush → segmented layout on disk
    return {
      backupId: backup?.id ?? null,
      couples: Object.keys(store.data.couples).length,
      quarantinedCouples: store.quarantinedCoupleIds.size,
      tokensUpgraded,
      games,
    };
  } finally {
    await store?.close().catch(() => {});
    await dataDirLock.release();
  }
}
