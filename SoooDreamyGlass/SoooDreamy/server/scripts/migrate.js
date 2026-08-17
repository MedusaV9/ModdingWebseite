#!/usr/bin/env node
// Migrates a legacy (v1.x, e.g. 1.5.4) data directory to the current layout.
// Idempotent — running it again on a migrated dir changes nothing.
//
//   npm run migrate                     # migrate ./data
//   npm run migrate -- --dry-run        # only report what WOULD happen
//   npm run migrate -- --data-dir /srv/sooodreamy/data
//
// A verified `pre-migration` backup is always taken before anything changes.
// Full operator guide (env vars, HTTPS opt-ins, app update): docs/MIGRATION.md
import { fileURLToPath } from 'node:url';
import { inspectDataDir, migrateDataDir, needsMigration } from '../src/legacy-migration.js';

const args = process.argv.slice(2);
function option(name, fallback) {
  const at = args.indexOf(name);
  return at !== -1 && args[at + 1] !== undefined ? args[at + 1] : fallback;
}
const dryRun = args.includes('--dry-run');
const dataDir = option('--data-dir', process.env.DATA_DIR || fileURLToPath(new URL('../data', import.meta.url)));
const log = (...values) => console.log('[migrate]', ...values);

console.log(`[migrate] inspecting ${dataDir} …`);
const inspection = await inspectDataDir(dataDir);
console.log(`[migrate]   state:          ${inspection.state} (${inspection.detail})`);
console.log(`[migrate]   couples:        ${inspection.couples}`);
console.log(`[migrate]   legacy tokens:  ${inspection.legacyTokens}`);
console.log(`[migrate]   stale games:    ${inspection.staleGames}`);

if (inspection.state === 'empty') {
  console.log('[migrate] nothing to do — data dir is empty/fresh.');
  process.exit(0);
}
if (inspection.state === 'unreadable') {
  console.error(`[migrate] ${inspection.detail}`);
  process.exit(1);
}
if (!needsMigration(inspection)) {
  console.log('[migrate] already up to date — nothing to do. ✓');
  process.exit(0);
}

const steps = [];
if (inspection.state === 'legacy-v1') {
  steps.push('compact the inline v1 store.json into segments/*.json (lossless, checksummed)');
}
if (inspection.legacyTokens > 0) {
  steps.push(`upgrade ${inspection.legacyTokens} raw bearer token(s) to hashed per-device sessions (users stay signed in)`);
}
if (inspection.staleGames > 0) {
  steps.push(`replay/invalidate ${inspection.staleGames} open pre-v4 game session(s) under the current rules`);
}
steps.unshift('take a verified pre-migration backup (restorable via npm run restore)');

console.log(`[migrate] plan${dryRun ? ' (DRY RUN — nothing will be written)' : ''}:`);
for (const [index, step] of steps.entries()) console.log(`[migrate]   ${index + 1}. ${step}`);

if (dryRun) {
  console.log('[migrate] dry run complete — re-run without --dry-run to apply.');
  process.exit(0);
}

console.log('[migrate] ⚠️  make sure the server is STOPPED, then migrating now …');
const result = await migrateDataDir({ dataDir, log });
console.log('[migrate] done ✓');
console.log(`[migrate]   backup:            ${result.backupId}`);
console.log(`[migrate]   couples migrated:  ${result.couples}${result.quarantinedCouples > 0 ? ` (${result.quarantinedCouples} quarantined — see data/quarantine/)` : ''}`);
console.log(`[migrate]   tokens upgraded:   ${result.tokensUpgraded}`);
console.log(`[migrate]   games: upgraded ${result.games.upgraded}, invalidated ${result.games.invalidated}, legacy-ended ${result.games.legacyEnded}`);
console.log('[migrate] next steps: review the env changes in docs/MIGRATION.md');
console.log('[migrate]   - default HTTP is for trusted private setups; use ALLOW_HTTP_PRIVATE_LAN=1 to filter or REQUIRE_HTTPS=1 behind TLS');
console.log('[migrate]   - Node.js ≥ 20 is required; then: npm install && npm start');
