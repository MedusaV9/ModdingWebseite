#!/usr/bin/env node
// 10-second self-test: boots the app against the REAL data dir on an
// ephemeral localhost port, fetches /api/health, shuts down cleanly.
// Exit 0 = the server would start fine; exit 1 = something is broken.
// Used as the gatekeeper phase of `npm run update` — run it any time with
// `node scripts/smoke.js`. STOP the running server first (same data dir).
import { createApp, DEFAULT_DATA_DIR } from '../src/app.js';

const args = process.argv.slice(2);
const at = args.indexOf('--data-dir');
const dataDir = at !== -1 && args[at + 1] ? args[at + 1] : process.env.DATA_DIR || DEFAULT_DATA_DIR;

try {
  const app = await createApp({
    dataDir,
    backupIntervalMinutes: 0, // probe run: no side jobs
    weekReviewPushIntervalMinutes: 0,
  });
  await new Promise((resolve, reject) => {
    app.server.once('error', reject);
    app.server.listen(0, '127.0.0.1', resolve);
  });
  const { port } = app.server.address();
  const res = await fetch(`http://127.0.0.1:${port}/api/health`);
  const body = await res.json();
  await app.close();
  if (res.status !== 200 || body.ok !== true) {
    throw new Error(`health answered ${res.status} ${JSON.stringify(body).slice(0, 200)}`);
  }
  console.log(`[smoke] ✓ boots, /api/health ok (v${body.version}, data: ${dataDir})`);
  process.exit(0);
} catch (err) {
  console.error(`[smoke] ✗ ${err.message}`);
  process.exit(1);
}
