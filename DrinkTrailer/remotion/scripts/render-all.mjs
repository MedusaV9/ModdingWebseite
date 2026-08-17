/**
 * Renders the EARLY trailer compositions to ../trailers/early_{style}_{format}.mp4
 * (h264, crf 18, yuv420p).
 *
 * Usage:
 *   npm run render:all                         → renders all four trailers
 *   npm run render:one -- EarlyHypeTikTok      → renders a single composition
 *   node scripts/render-all.mjs <id> [<id>...] → renders the given IDs
 */
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const remotionRoot = path.resolve(__dirname, '..');
const trailersDir = path.resolve(remotionRoot, '..', 'trailers');

const TARGETS = {
  EarlyHypeTikTok: 'early_hype_tiktok.mp4',
  EarlyHypeLandscape: 'early_hype_landscape.mp4',
  EarlyCleanTikTok: 'early_clean_tiktok.mp4',
  EarlyCleanLandscape: 'early_clean_landscape.mp4',
};

const args = process.argv.slice(2);
const requireId = args.includes('--require-id');
const ids = args.filter((a) => !a.startsWith('--'));

if (requireId && ids.length === 0) {
  console.error('Usage: npm run render:one -- <compositionId>');
  console.error(`Known IDs: ${Object.keys(TARGETS).join(', ')}`);
  process.exit(1);
}

const unknown = ids.filter((id) => !(id in TARGETS));
if (unknown.length > 0) {
  console.error(`Unknown composition ID(s): ${unknown.join(', ')}`);
  console.error(`Known IDs: ${Object.keys(TARGETS).join(', ')}`);
  process.exit(1);
}

const toRender = ids.length > 0 ? ids : Object.keys(TARGETS);
fs.mkdirSync(trailersDir, {recursive: true});

const remotionBin = path.join(remotionRoot, 'node_modules', '.bin', 'remotion');

for (const id of toRender) {
  const outFile = path.join(trailersDir, TARGETS[id]);
  console.log(`\n[render] ${id} → ${outFile}`);
  const result = spawnSync(
    remotionBin,
    ['render', id, outFile, '--codec=h264', '--crf=18', '--pixel-format=yuv420p'],
    {cwd: remotionRoot, stdio: 'inherit'},
  );
  if (result.status !== 0) {
    console.error(`[render] ${id} failed with exit code ${result.status}`);
    process.exit(result.status ?? 1);
  }
}

console.log(`\n[render] Done. Output in ${trailersDir}`);
