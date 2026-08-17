/**
 * Batch renderer for the v2 "EarlyV2" trailers (1080x1920 @ 60fps).
 *
 * Usage:
 *   node scripts/render-v2.mjs                    → render all registered V2 IDs
 *   node scripts/render-v2.mjs --only 1,5,7       → only these style numbers
 *   node scripts/render-v2.mjs --force            → re-render existing files too
 *   node scripts/render-v2.mjs --crf 22           → h264 quality (default 22)
 *   node scripts/render-v2.mjs --scale 2          → 2160x3840 4K finals (adds _4k suffix)
 *
 * Output: ../trailers/v2/early_v2_{NN}_{slug}_9x16_60[_4k].mp4
 * Per-trailer logs: ../trailers/v2/logs/<basename>.log
 *
 * Resumable BY DEFAULT: finished files are skipped unless --force is given.
 * Renders go to a *.partial.mp4 first and are renamed on success, so
 * interrupted renders never count as done; failures don't stop the batch
 * (summary + exit code 1 at the end).
 */
import {spawnSync} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const remotionRoot = path.resolve(__dirname, '..');
const outDir = path.resolve(remotionRoot, '..', 'trailers', 'v2');
const logDir = path.join(outDir, 'logs');
const remotionBin = path.join(remotionRoot, 'node_modules', '.bin', 'remotion');

// --- CLI args ---------------------------------------------------------------
const args = process.argv.slice(2);
const getFlagValue = (name, fallback) => {
  const eq = args.find((a) => a.startsWith(`${name}=`));
  if (eq) return eq.slice(name.length + 1);
  const i = args.indexOf(name);
  if (i !== -1 && i + 1 < args.length && !args[i + 1].startsWith('--')) return args[i + 1];
  return fallback;
};

const only = getFlagValue('--only', null);
// Resume-friendly default: skip finished files. --force re-renders everything;
// --skip-existing is accepted for backwards compatibility (already default).
const skipExisting = !args.includes('--force');
const crf = parseInt(getFlagValue('--crf', '22'), 10);
const scale = parseInt(getFlagValue('--scale', '1'), 10);

if (![1, 2].includes(scale)) {
  console.error(`--scale must be 1 or 2 (got ${scale})`);
  process.exit(1);
}
if (!Number.isInteger(crf) || crf < 1 || crf > 51) {
  console.error(`--crf must be 1..51 (got ${crf})`);
  process.exit(1);
}
const onlyIds = only
  ? only
      .split(',')
      .map((s) => parseInt(s.trim(), 10))
      .filter((n) => Number.isInteger(n))
  : null;

// --- Discover registered V2 compositions ------------------------------------
console.log('[render-v2] Syncing assets…');
const sync = spawnSync(process.execPath, [path.join(__dirname, 'sync-assets.mjs')], {
  cwd: remotionRoot,
  stdio: 'inherit',
});
if (sync.status !== 0) process.exit(sync.status ?? 1);

console.log('[render-v2] Discovering compositions…');
const list = spawnSync(remotionBin, ['compositions', '-q'], {
  cwd: remotionRoot,
  encoding: 'utf8',
});
if (list.status !== 0) {
  console.error('[render-v2] "remotion compositions" failed:');
  console.error(list.stdout || '');
  console.error(list.stderr || '');
  process.exit(list.status ?? 1);
}

// Composition IDs: EarlyV2-{NN}-{slug-with-dashes}
const V2_ID = /^EarlyV2-(\d{2})-([a-z0-9-]+)$/;
const targets = (list.stdout || '')
  .split(/\s+/)
  .map((id) => id.trim())
  .filter((id) => V2_ID.test(id))
  .map((id) => {
    const [, nn, dashSlug] = id.match(V2_ID);
    const slug = dashSlug.replace(/-/g, '_');
    const basename = `early_v2_${nn}_${slug}_9x16_60${scale === 2 ? '_4k' : ''}`;
    return {id, num: parseInt(nn, 10), basename, outFile: path.join(outDir, `${basename}.mp4`)};
  })
  .sort((a, b) => a.num - b.num);

if (targets.length === 0) {
  console.error('[render-v2] No EarlyV2-* compositions registered. Add styles to src/v2/styles/.');
  process.exit(1);
}

const selected = onlyIds ? targets.filter((t) => onlyIds.includes(t.num)) : targets;
if (onlyIds) {
  const missing = onlyIds.filter((n) => !targets.some((t) => t.num === n));
  if (missing.length > 0) {
    console.warn(`[render-v2] WARN: no registered composition for style(s): ${missing.join(', ')}`);
  }
}
if (selected.length === 0) {
  console.error('[render-v2] Nothing to render after --only filtering.');
  process.exit(1);
}

fs.mkdirSync(outDir, {recursive: true});
fs.mkdirSync(logDir, {recursive: true});

// --- Render loop -------------------------------------------------------------
console.log(
  `[render-v2] ${selected.length}/${targets.length} trailer(s) | crf=${crf} scale=${scale}${skipExisting ? ' | skip-existing' : ''}\n`,
);

const results = [];
for (let i = 0; i < selected.length; i++) {
  const t = selected[i];
  const progress = `[${i + 1}/${selected.length}]`;

  if (skipExisting && fs.existsSync(t.outFile) && fs.statSync(t.outFile).size > 0) {
    console.log(`${progress} SKIP  ${t.id} → ${path.basename(t.outFile)} (exists)`);
    results.push({...t, status: 'skipped'});
    continue;
  }

  const partial = t.outFile.replace(/\.mp4$/, '.partial.mp4');
  const logFile = path.join(logDir, `${t.basename}.log`);
  console.log(`${progress} RENDER ${t.id} → ${path.basename(t.outFile)} (log: ${path.relative(process.cwd(), logFile)})`);

  const started = Date.now();
  const renderArgs = [
    'render',
    t.id,
    partial,
    '--codec=h264',
    `--crf=${crf}`,
    '--pixel-format=yuv420p',
  ];
  if (scale !== 1) renderArgs.push(`--scale=${scale}`);

  const result = spawnSync(remotionBin, renderArgs, {cwd: remotionRoot, encoding: 'utf8'});
  fs.writeFileSync(logFile, `${result.stdout || ''}\n${result.stderr || ''}`);

  const seconds = ((Date.now() - started) / 1000).toFixed(0);
  if (result.status === 0 && fs.existsSync(partial) && fs.statSync(partial).size > 0) {
    fs.renameSync(partial, t.outFile);
    const mb = (fs.statSync(t.outFile).size / 1024 / 1024).toFixed(1);
    console.log(`${progress} DONE  ${t.id} (${seconds}s, ${mb} MB)`);
    results.push({...t, status: 'done'});
  } else {
    if (fs.existsSync(partial)) fs.rmSync(partial);
    console.error(`${progress} FAIL  ${t.id} (exit ${result.status}) — see ${logFile}`);
    const tail = `${result.stdout || ''}\n${result.stderr || ''}`.trim().split('\n').slice(-12);
    for (const line of tail) console.error(`         ${line}`);
    results.push({...t, status: 'failed'});
  }
}

// --- Summary ------------------------------------------------------------------
const done = results.filter((r) => r.status === 'done').length;
const skipped = results.filter((r) => r.status === 'skipped').length;
const failed = results.filter((r) => r.status === 'failed');
console.log(`\n[render-v2] Summary: ${done} rendered, ${skipped} skipped, ${failed.length} failed. Output: ${outDir}`);
if (failed.length > 0) {
  console.error(`[render-v2] Failed: ${failed.map((f) => f.id).join(', ')}`);
  console.error('[render-v2] Re-run with --skip-existing to resume only the missing ones.');
  process.exit(1);
}
