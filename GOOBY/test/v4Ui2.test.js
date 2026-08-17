// GOOBY V4/POLISH-D — UI transition + themed loading-screen contract tests.
// Pure node:test: strings/v4-ui2.js EN/DE parity + collision safety with the
// other framework-tx dictionary (v4-difficulty), the committed loading-motif
// asset, and source-scan invariants for the ui.js exit-animation contract and
// the framework.js themed loading card (the DOM modules themselves stay
// un-importable here — no DOM/three in node:test, per AGENTS.md).

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { EN as UI2_EN, DE as UI2_DE } from '../src/data/strings/v4-ui2.js';
import { EN as DIFF_EN } from '../src/data/strings/v4-difficulty.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = (rel) => fs.readFileSync(path.join(ROOT, ...rel.split('/')), 'utf8');

test('POLISH-D: strings/v4-ui2.js EN and DE key sets are identical', () => {
  assert.deepEqual(Object.keys(UI2_EN).sort(), Object.keys(UI2_DE).sort());
  for (const [key, value] of [...Object.entries(UI2_EN), ...Object.entries(UI2_DE)]) {
    assert.ok(typeof value === 'string' && value.length > 0, `${key}: empty`);
  }
});

test('POLISH-D: loading headline + the 3 rotating tips exist (framework txD contract)', () => {
  // framework.js picks `ui2.loading.tip${1 + rng*3}` — all three must exist.
  for (const key of ['ui2.loading.getReady', 'ui2.loading.tip1', 'ui2.loading.tip2', 'ui2.loading.tip3']) {
    assert.ok(key in UI2_EN, `EN missing ${key}`);
    assert.ok(key in UI2_DE, `DE missing ${key}`);
  }
});

test('POLISH-D: v4-ui2 keys never shadow the other framework-tx dictionary (v4-difficulty)', () => {
  // framework.js resolves t() → DIFF table → UI2 table; a duplicate key
  // would silently mask one copy.
  for (const key of Object.keys(UI2_EN)) {
    assert.ok(!(key in DIFF_EN), `${key} defined in both v4-ui2 and v4-difficulty`);
  }
});

test('POLISH-D: the loading motif is a committed palette PNG (ui/ budget-friendly)', () => {
  const file = path.join(ROOT, 'public', 'assets', 'ui', 'gooby_loading_motif.png');
  assert.ok(fs.existsSync(file), 'missing public/assets/ui/gooby_loading_motif.png');
  const buf = fs.readFileSync(file);
  assert.deepEqual(
    [...buf.subarray(0, 8)],
    [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
    'invalid PNG signature'
  );
  assert.equal(buf[25], 3, 'motif must stay an indexed-palette PNG (size budget)');
  assert.ok(buf.length <= 64 * 1024, `motif ${buf.length} B exceeds the 64 KiB budget`);
});

test('POLISH-D: ui.js exit-animation contract (exit class + animationend + matched timeout + reduced motion)', () => {
  const ui = source('src/ui/ui.js');
  // exit classes styles.css animates
  assert.match(ui, /animateOut\(el, 'panel-backdrop-out'\)/);
  assert.match(ui, /animateOut\(activeScreen\.el, 'screen-out'\)/);
  // unmount-after-animation without leaks: listener removed + timeout cleared
  assert.match(ui, /addEventListener\('animationend'/);
  assert.match(ui, /removeEventListener\('animationend'/);
  assert.match(ui, /clearTimeout\(timer\)/);
  // matched timeout fallback tied to the CSS duration
  assert.match(ui, /EXIT_ANIM_MS \+ EXIT_TIMEOUT_PAD_MS/);
  // reduced motion skips the exit delay entirely
  assert.match(ui, /prefers-reduced-motion: reduce/);
});

test('POLISH-D: framework.js themed loading card (cover art + progress + motif + tip)', () => {
  const fw = source('src/minigames/framework.js');
  // §G7.1 cover helpers, not a re-derived path
  assert.match(fw, /import \{ coverUrl, fallbackGradient \} from '\.\.\/ui\/arcadeUi\.logic\.js'/);
  assert.match(fw, /fallbackGradient\(meta\.id\)/);
  assert.match(fw, /coverUrl\(meta\.id\)/);
  // §G7.1 fallback rule — onerror swap, never a broken image
  assert.match(fw, /coverImg\.addEventListener\('error', \(\) => coverImg\.remove\(\)\)/);
  assert.match(fw, /motif\.addEventListener\('error', \(\) => motif\.remove\(\)\)/);
  assert.match(fw, /assets\/ui\/gooby_loading_motif\.png/);
  // determinate progress from the running init's loadPct, cleared on hide
  assert.match(fw, /game\?\.loadPct/);
  assert.match(fw, /clearInterval\(loadingPollTimer\)/);
  // the card covers the whole launch: shown before loadGame(...)
  assert.match(fw, /showLoading\(\);\s*\r?\n\s*const mod = await loadGame/);
});

test('POLISH-D: styles.css ships the transition blocks + reduced-motion guard', () => {
  const css = source('src/ui/styles.css');
  for (const needle of [
    '.screen.screen-out',
    '@keyframes polishd-screen-out',
    '.panel-backdrop.panel-backdrop-out .panel',
    '@keyframes polishd-panel-down',
    '@keyframes polishd-backdrop-in',
    '.mg-loading-themed .mg-loading-card',
    '.mg-loading-bar-indet .mg-loading-bar-fill',
    '@media (prefers-reduced-motion: reduce)',
  ]) {
    assert.ok(css.includes(needle), `styles.css missing '${needle}'`);
  }
  // the base V4/G56 card blocks weltPreview.js relies on stay present
  for (const needle of ['.mg-loading-card', '.mg-loading-dots span', '@keyframes g56dots']) {
    assert.ok(css.includes(needle), `styles.css lost the V4/G56 base block '${needle}'`);
  }
});
