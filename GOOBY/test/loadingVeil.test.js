// GOOBY V4/AC-3 — loading-veil contract tests (cute IN/OUT transition).
// Pure node:test: the veil's exported tuning consts + pure helpers
// (mode/progress/reveal-timing/tip math, per-mode string+art tables),
// strings/v4-acui-loading.js EN/DE parity + collision safety with the other
// framework-tx dictionaries, the committed acui veil art, and source-scan
// invariants for the sceneManager afterEnter hook, the framework IN/OUT
// wiring and the shopTrip travel curtain (the DOM flows themselves are
// proven via the AC-3 CDP evidence — no DOM/three in node:test, per
// AGENTS.md).

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  VEIL,
  normalizeVeilMode,
  clampProgressPct,
  revealNotBefore,
  nextTipIndex,
  veilStrings,
  veilArt,
  veil,
} from '../src/ui/loadingVeil.js';
import { EN as ACUI_EN, DE as ACUI_DE } from '../src/data/strings/v4-acui-loading.js';
import { EN as UI2_EN } from '../src/data/strings/v4-ui2.js';
import { EN as DIFF_EN } from '../src/data/strings/v4-difficulty.js';
import { EN as ARC2_EN } from '../src/data/strings/v4-arcade2.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = (rel) => fs.readFileSync(path.join(ROOT, ...rel.split('/')), 'utf8');

// ---------------------------------------------------------------------------
// Tuning consts + API surface
// ---------------------------------------------------------------------------

test('AC-3 VEIL consts: anti-pop-in numbers are sane and frozen', () => {
  assert.ok(Object.isFrozen(VEIL));
  assert.equal(VEIL.ENTER_SETTLE_FRAMES, 2, 'reveal waits 2 frames after enter()');
  assert.equal(VEIL.MIN_SHOWN_MS, 600, 'default minShownMs contract');
  // the §E1 black fade (150 ms) must fully lift under the veil pre-reveal
  assert.ok(VEIL.FADE_CLEAR_MS >= 150, 'FADE_CLEAR_MS covers the 150 ms scene fade');
  // deadlock safety: a hard hide ceiling + a show watchdog both exist
  assert.ok(VEIL.HARD_TIMEOUT_MS >= 3000 && VEIL.HARD_TIMEOUT_MS <= 30000);
  assert.ok(VEIL.WATCHDOG_MS > VEIL.HARD_TIMEOUT_MS, 'watchdog outlasts a pending hide');
  // the rAF settle is raced against a timer (rAF stalls in hidden tabs)
  assert.ok(VEIL.FRAME_FALLBACK_MS > 0);
});

test('AC-3 veil API: show/progress/hide/isShown/whenHidden handle (node-safe no-ops)', () => {
  for (const fn of ['show', 'progress', 'hide', 'isShown', 'whenHidden']) {
    assert.equal(typeof veil[fn], 'function', `veil.${fn} missing`);
  }
  // without a DOM the veil is inert — never throws, never "shown"
  assert.equal(veil.isShown(), false);
  assert.doesNotThrow(() => veil.progress(50));
});

test('V6.1/A7 whenHidden: resolves immediately when nothing covers the screen', async () => {
  // node has no document → the veil can never be shown → both the bare and
  // the grace-window calls must resolve promptly (never hang the airport)
  const timeout = new Promise((_, reject) => {
    const t = setTimeout(() => reject(new Error('whenHidden hung')), 2000);
    t.unref?.();
  });
  await Promise.race([veil.whenHidden(), timeout]);
  await Promise.race([veil.whenHidden({ graceMs: 1500 }), timeout]);
  assert.ok(veil.whenHidden() instanceof Promise, 'always a Promise');
});

test('V6.1/A7 whenHidden: bounded wait + every reveal path (source scan)', () => {
  const lv = source('src/ui/loadingVeil.js');
  // the wait polls the module's single source of truth (`el`) — riding the
  // normal hide, the watchdog force-hide AND the hard-timeout force-reveal
  // for free (all three end in reveal() dropping `el`)
  assert.match(lv, /while \(!el && nowMs\(\) < graceUntil\) await sleep\(VEIL\.POLL_MS\);/);
  assert.match(lv, /while \(el && nowMs\(\) < hardAt\) await sleep\(VEIL\.POLL_MS\);/);
  // belt-and-braces cap: the wait is bounded even against a pathological
  // show() loop (watchdog + hard timeout + slack)
  assert.match(lv, /VEIL\.WATCHDOG_MS \+ VEIL\.HARD_TIMEOUT_MS \+ 2000/);
});

test('V6.1/A7 wiring: the airport dev/return open gates on the veil, not a timer', () => {
  const air = source('src/ui/airportScreen.js');
  // the fixed 800 ms race (P2-24) is gone for good…
  assert.ok(!/setTimeout\([^)]*800\)/.test(air), 'no fixed 800 ms open timer left');
  // …replaced by the settled signal, with the boot-order grace window
  assert.match(air, /import \{ whenHidden \} from '\.\/loadingVeil\.js'/);
  assert.match(
    air,
    /whenHidden\(\{ graceMs: 1500 \}\)\.then\(\(\) => ui\.openPanel\('airport'\)\)/,
    'panel opens only after the veil settles'
  );
});

// ---------------------------------------------------------------------------
// Pure helpers
// ---------------------------------------------------------------------------

test('AC-3 normalizeVeilMode: game/trip pass through, junk degrades to home', () => {
  assert.equal(normalizeVeilMode('game'), 'game');
  assert.equal(normalizeVeilMode('trip'), 'trip');
  assert.equal(normalizeVeilMode('home'), 'home');
  for (const junk of [undefined, null, 'GAME', 'shop', 42, {}, true]) {
    assert.equal(normalizeVeilMode(junk), 'home', String(junk));
  }
});

test('AC-3 clampProgressPct: null keeps the indeterminate sweep, clamps to 100', () => {
  for (const junk of [undefined, null, NaN, 'junk', 0, -5, -0.1, Infinity]) {
    assert.equal(clampProgressPct(junk), null, String(junk));
  }
  assert.equal(clampProgressPct(1), 1);
  assert.equal(clampProgressPct(37.5), 37.5);
  assert.equal(clampProgressPct('42'), 42);
  assert.equal(clampProgressPct(100), 100);
  assert.equal(clampProgressPct(250), 100);
});

test('AC-3 revealNotBefore: max(minShown since show, fade-clear since enter)', () => {
  // no scene switch involved (teleport cutscene): only minShown counts
  assert.equal(revealNotBefore(1000, 600, 0, 200), 1600);
  // fast enter: minShown dominates
  assert.equal(revealNotBefore(1000, 600, 1100, 200), 1600);
  // slow enter (streaming assets): enter + fade-clear dominates → no pop-in
  assert.equal(revealNotBefore(1000, 600, 5000, 200), 5200);
  // hostile inputs never NaN
  assert.equal(revealNotBefore(NaN, NaN, NaN, NaN), 0);
});

test('AC-3 nextTipIndex: wraps forward, hostile counters land in range', () => {
  assert.equal(nextTipIndex(0, 3), 1);
  assert.equal(nextTipIndex(1, 3), 2);
  assert.equal(nextTipIndex(2, 3), 0);
  assert.equal(nextTipIndex(NaN, 3), 1);
  assert.equal(nextTipIndex(-7, 3), 0);
  assert.equal(nextTipIndex(5, 0), 0); // count floor of 1
});

test('AC-3 veilStrings: every mode resolves to existing EN+DE keys', () => {
  for (const mode of ['game', 'home', 'trip']) {
    const s = veilStrings(mode);
    const keys = [s.readyKey, s.labelKey, ...(s.titleKey ? [s.titleKey] : []), ...s.tipKeys];
    assert.ok(s.tipKeys.length >= 3, `${mode}: needs ≥3 rotating tips`);
    for (const key of keys) {
      const en = ACUI_EN[key] ?? UI2_EN[key];
      assert.ok(typeof en === 'string' && en.length > 0, `${mode}: EN missing ${key}`);
    }
  }
  // game mode REUSES POLISH-D's tips (imported, not duplicated)
  assert.deepEqual(
    veilStrings('game').tipKeys,
    ['ui2.loading.tip1', 'ui2.loading.tip2', 'ui2.loading.tip3']
  );
  // the framework card carries the game title itself
  assert.equal(veilStrings('game').titleKey, null);
});

test('AC-3 veilArt: home/trip use the committed acui art, game keeps the D motif', () => {
  for (const mode of ['home', 'trip']) {
    assert.deepEqual(veilArt(mode), {
      cover: 'assets/acui/veil_home_cover.png',
      motif: 'assets/acui/motif_gooby_wave.png',
    });
  }
  assert.deepEqual(veilArt('game'), { cover: null, motif: 'assets/ui/gooby_loading_motif.png' });
});

// ---------------------------------------------------------------------------
// strings/v4-acui-loading.js
// ---------------------------------------------------------------------------

test('AC-3: strings/v4-acui-loading.js EN and DE key sets are identical', () => {
  assert.deepEqual(Object.keys(ACUI_EN).sort(), Object.keys(ACUI_DE).sort());
  for (const [key, value] of [...Object.entries(ACUI_EN), ...Object.entries(ACUI_DE)]) {
    assert.ok(typeof value === 'string' && value.length > 0, `${key}: empty`);
    assert.ok(key.startsWith('acui.loading.'), `${key}: outside the module namespace`);
  }
});

test('AC-3: acui keys never shadow the other framework-tx dictionaries', () => {
  // loadingVeil.js resolves t() → ACUI table → UI2 table; framework.js has
  // its own DIFF/UI2/ARC2 chains — a duplicate key would silently mask one.
  for (const key of Object.keys(ACUI_EN)) {
    assert.ok(!(key in UI2_EN), `${key} defined in both v4-acui-loading and v4-ui2`);
    assert.ok(!(key in DIFF_EN), `${key} defined in both v4-acui-loading and v4-difficulty`);
    assert.ok(!(key in ARC2_EN), `${key} defined in both v4-acui-loading and v4-arcade2`);
  }
});

// ---------------------------------------------------------------------------
// Committed veil art (public/assets/acui/ — §D budget-friendly palette PNGs)
// ---------------------------------------------------------------------------

test('AC-3: the veil art is committed as indexed-palette PNGs (acui budget)', () => {
  for (const [rel, capKb] of [
    ['public/assets/acui/veil_home_cover.png', 160],
    ['public/assets/acui/motif_gooby_wave.png', 64],
  ]) {
    const file = path.join(ROOT, ...rel.split('/'));
    assert.ok(fs.existsSync(file), `missing ${rel}`);
    const buf = fs.readFileSync(file);
    assert.deepEqual(
      [...buf.subarray(0, 8)],
      [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
      `${rel}: invalid PNG signature`
    );
    assert.equal(buf[25], 3, `${rel}: must stay an indexed-palette PNG (size budget)`);
    assert.ok(buf.length <= capKb * 1024, `${rel}: ${buf.length} B exceeds ${capKb} KiB`);
  }
});

// ---------------------------------------------------------------------------
// Source-scan wiring invariants (framework.js/sceneManager.js/shopTrip.js
// import three/DOM at runtime — pin the seams at source level; runtime
// proof is the AC-3 CDP round-trip video)
// ---------------------------------------------------------------------------

test('AC-3 wiring: sceneManager gains the additive afterEnter hook', () => {
  const sm = source('src/core/sceneManager.js');
  assert.match(sm, /afterEnter\(cb\) \{\s*\r?\n\s*afterEnterCbs\.push\(cb\);/);
  // one-shot flush right after enter() resolves, BEFORE the fade lifts
  assert.match(sm, /await instance\.enter\?\.\(params\);[\s\S]{0,400}?afterEnterCbs\.splice\(0\)[\s\S]{0,400}?await fadeTo\(0\)/);
  // the deterministic timer-stepped black fade is untouched (AC-3 must not
  // replace it — headless screenshot determinism depends on it)
  assert.match(sm, /fadeEl\.style\.cssText = 'position:fixed;inset:0;background:#000/);
});

test('AC-3 wiring: framework IN — veil up pre-switch, card adopted, reveal gates the countdown', () => {
  const fw = source('src/minigames/framework.js');
  assert.match(fw, /import \{ initLoadingVeil, veil \} from '\.\.\/ui\/loadingVeil\.js'/);
  assert.match(fw, /initLoadingVeil\(\{ sceneManager \}\)/);
  // curtain rises BEFORE switchTo('minigame') — launches never black-flash
  assert.match(fw, /await veil\.show\(\{\s*\r?\n\s*mode: 'game',[\s\S]{0,300}?\}\);[\s\S]{0,600}?await sceneManager\.switchTo\('minigame'/);
  // the POLISH-D card is ADOPTED (content:), not rebuilt in the veil
  assert.match(fw, /veil\.show\(\{ mode: 'game', content: loadingEl \}\)/);
  // loadPct polling feeds the veil bar
  assert.match(fw, /veil\.progress\(Number\(game\?\.loadPct\)\)/);
  // hideLoading defers to the veil's safe reveal…
  assert.match(fw, /return veil\.hide\(\);/);
  // …and the countdown waits for it (still before the POLISH-E rotate gate)
  assert.match(fw, /const revealed = hideLoading\(\);/);
  assert.match(fw, /await revealed;[\s\S]*?await rotateGate\(\);[\s\S]*?await countdown\(\)/);
  // a failed launch never strands the curtain (slow launches that DID reach
  // the minigame scene keep it — the enter-side hideLoading owns those)
  assert.match(fw, /if \(!landed && sceneManager\.currentId\?\.\(\) !== 'minigame'\) veil\.hide\(\{ minShownMs: 0 \}\)/);
});

test('AC-3 wiring: framework OUT — home veil rises before switchTo(home)', () => {
  const fw = source('src/minigames/framework.js');
  assert.match(
    fw,
    /veil\.show\(\{ mode: 'home' \}\)[\s\S]{0,200}?switchTo\('home'\)/,
    'exitToHome shows the home veil before the switch'
  );
});

test('AC-3 wiring: shopTrip returns ride the travel curtain (lazy, injected)', () => {
  const st = source('src/systems/shopTrip.js');
  // browser-only dependency stays LAZY (miscQuality forbids static ../ui/
  // imports here) and degrades to the bare fade while unresolved
  assert.match(st, /import\('\.\.\/ui\/loadingVeil\.js'\)/);
  assert.match(st, /initLoadingVeil\(\{ sceneManager \}\)/);
  // BOTH return paths (goHome + cancelled onExit) show mode 'trip' first
  const tripShows = st.match(/tripVeil\?\.show\(\{ mode: 'trip' \}\)[\s\S]{0,200}?switchTo\('home', \{ room: 'living' \}\)/g) ?? [];
  assert.equal(tripShows.length, 2, 'goHome AND onExit cancel path are veiled');
});

test('AC-3 veil module: injected CSS owner tag, iris + reduced-motion fade, onerror art fallbacks', () => {
  const lv = source('src/ui/loadingVeil.js');
  assert.match(lv, /data-owner="loadingveil"/);
  assert.match(lv, /style\.dataset\.owner = 'loadingveil'/);
  // iris wipe keyframes + the reduced-motion plain-fade downgrade
  assert.match(lv, /@keyframes acui-veil-iris-in/);
  assert.match(lv, /@keyframes acui-veil-iris-out/);
  assert.match(lv, /@media \(prefers-reduced-motion: reduce\)/);
  assert.match(lv, /acui-veil-fade-in/);
  // §G7.1 rule: every veil <img> gets an onerror-remove fallback
  assert.match(lv, /coverImgEl\.addEventListener\('error', \(\) => coverImgEl\.remove\(\)\)/);
  assert.match(lv, /motifEl\.addEventListener\('error', \(\) => motifEl\.remove\(\)\)/);
  // deadlock safeguards: hard hide ceiling + show watchdog + rAF timer race
  assert.match(lv, /HARD_TIMEOUT_MS/);
  assert.match(lv, /WATCHDOG_MS/);
  assert.match(lv, /setTimeout\(finish, VEIL\.FRAME_FALLBACK_MS\)/);
});
