// V4/ORIENT — rotation is allowed ONLY at the right moments:
//   • the app behaves as PORTRAIT everywhere (home, menus, portrait games);
//     landscape is offered ONLY while a LANDSCAPE-flagged minigame is active
//   • the „Bitte dreh dein Handy" gate shows ONLY for landscape games and
//     ONLY while the viewport is still portrait — portrait games NEVER gate
//   • ending a landscape game (results/quit/teleport) funnels through exit(),
//     which tears the gate down, re-locks portrait and resets the run flag
//   • the EXACT landscape-game set is pinned — flagging a game landscape (or
//     unflagging one) is a conscious, tested change
//   • the pure decision matrix is exercised across the iPhone resolutions the
//     CDP smoke drives (320×568 / 375×667 / 390×844 / 430×932)
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  normalizeOrientation,
  needsRotateGate,
  orientationForGame,
  shouldShowRotateGate,
  orientationLockFor,
} from '../src/minigames/framework.logic.js';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const GAMES_DIR = path.join(ROOT, 'src', 'minigames', 'games');

// ── V4/ORIENT: THE landscape set. Adding/removing a game's landscape flag
// must update this list on purpose — the exact-set test below enforces it. ──
const LANDSCAPE_GAMES = Object.freeze(['goalieGooby', 'harborHopper', 'runner', 'toyRacer']);

/** Game entry modules only (`.logic.`/`.paths.` companions never own the flag). */
function gameEntryFiles() {
  return fs.readdirSync(GAMES_DIR)
    .filter((f) => f.endsWith('.js') && !f.includes('.logic.') && !f.includes('.paths.'))
    .sort();
}

test('V4/ORIENT: the EXACT set of landscape-flagged games is pinned', () => {
  const landscape = [];
  for (const file of gameEntryFiles()) {
    const src = fs.readFileSync(path.join(GAMES_DIR, file), 'utf8');
    const m = src.match(/^export const orientation = '([^']*)';/m);
    if (!m) continue; // no export → portrait by contract (normalizeOrientation)
    // only the two known literals may ever be exported
    assert.ok(['landscape', 'portrait'].includes(m[1]), `${file}: unknown orientation '${m[1]}'`);
    if (m[1] === 'landscape') landscape.push(file.replace(/\.js$/, ''));
  }
  assert.deepEqual(landscape.sort(), [...LANDSCAPE_GAMES],
    'landscape-game set changed — update LANDSCAPE_GAMES consciously');
});

test('V4/ORIENT orientationForGame: reads the module export, defaults portrait', () => {
  assert.equal(orientationForGame({ orientation: 'landscape' }), 'landscape');
  assert.equal(orientationForGame({ orientation: 'portrait' }), 'portrait');
  // absent/unknown/hostile module shapes all mean portrait
  for (const mod of [{}, null, undefined, { orientation: 'LANDSCAPE' }, { orientation: 1 }]) {
    assert.equal(orientationForGame(mod), 'portrait', JSON.stringify(mod));
  }
  // consistent with normalizeOrientation (the single normalizer)
  assert.equal(orientationForGame({ orientation: 'wide' }), normalizeOrientation('wide'));
});

test('V4/ORIENT shouldShowRotateGate: only landscape game + portrait viewport', () => {
  // the ONLY combination that gates
  assert.equal(shouldShowRotateGate('landscape', false), true);
  // already-landscape viewport → no gate
  assert.equal(shouldShowRotateGate('landscape', true), false);
  // portrait games NEVER gate, whatever the viewport reports
  assert.equal(shouldShowRotateGate('portrait', false), false);
  assert.equal(shouldShowRotateGate('portrait', true), false);
  // unknown flags normalize to portrait → never gate
  for (const junk of [undefined, null, 'LANDSCAPE', 'wide', 1, {}]) {
    assert.equal(shouldShowRotateGate(junk, false), false, String(junk));
  }
  // a non-boolean viewport answer counts as "not landscape yet" (safe default)
  assert.equal(shouldShowRotateGate('landscape', undefined), true);
});

test('V4/ORIENT: needsRotateGate delegates to shouldShowRotateGate (no drift)', () => {
  // same decision through both surfaces, for both flags and both aspects
  for (const [w, h] of [[390, 844], [844, 390], [500, 500]]) {
    for (const flag of ['landscape', 'portrait']) {
      assert.equal(
        needsRotateGate(flag, w, h),
        shouldShowRotateGate(flag, w > h),
        `${flag} @ ${w}x${h}`
      );
    }
  }
});

// ── iPhone resolution matrix (the sizes the CDP smoke drives) ──────────────
const IPHONE_SIZES = Object.freeze([
  [320, 568], //  iPhone SE (1st gen) / 5s
  [375, 667], //  iPhone SE (2nd/3rd gen) / 8
  [390, 844], //  iPhone 12–14 (the CSS baseline)
  [430, 932], //  iPhone 14/15 Pro Max
]);

test('V4/ORIENT matrix: portrait games never gate at ANY iPhone size', () => {
  for (const [w, h] of IPHONE_SIZES) {
    assert.equal(needsRotateGate('portrait', w, h), false, `portrait ${w}x${h}`);
    assert.equal(needsRotateGate('portrait', h, w), false, `portrait ${h}x${w} (rotated)`);
  }
});

test('V4/ORIENT matrix: landscape games gate on portrait, pass on landscape', () => {
  for (const [w, h] of IPHONE_SIZES) {
    // portrait viewport → the gate holds before the countdown
    assert.equal(needsRotateGate('landscape', w, h), true, `landscape ${w}x${h}`);
    // rotated (landscape) viewport → straight into the countdown
    assert.equal(needsRotateGate('landscape', h, w), false, `landscape ${h}x${w} (rotated)`);
  }
});

test('V4/ORIENT orientationLockFor: unlock ONLY for landscape games', () => {
  assert.equal(orientationLockFor('landscape'), 'unlock');
  // everything else re-locks the app-wide portrait baseline
  for (const flag of ['portrait', undefined, null, 'LANDSCAPE', 'wide', 0]) {
    assert.equal(orientationLockFor(flag), 'portrait', String(flag));
  }
});

// ── source contracts: the framework WIRES the policy (enter/exit/teardown) ──

test('V4/ORIENT wiring: enter applies the lock target, exit restores portrait', () => {
  const src = fs.readFileSync(path.join(ROOT, 'src', 'minigames', 'framework.js'), 'utf8');
  // enter(): the pure lock-target helper decides, right after the flag is read
  assert.match(src, /gameOrientation = normalizeOrientation\(await orientationOf\(params\.gameId\)\);[\s\S]{0,400}?applyOrientationLock\(orientationLockFor\(gameOrientation\)\)/);
  // exit(): pending gate resolved, then portrait re-locked + run flag reset —
  // EVERY way out (results→home, pause-quit, teleport, failed init) runs this
  assert.match(src, /rotateGateCleanup\?\.\(\);[\s\S]*?applyOrientationLock\('portrait'\);\s*\r?\n\s*gameOrientation = 'portrait';/);
  // the lock is best-effort: rejection swallowed, try/catch around the API
  assert.match(src, /Promise\.resolve\(so\.lock\?\.\('portrait'\)\)\.catch\(\(\) => \{\}\)/);
});

test('V4/ORIENT wiring: a landscape run re-locks portrait BEFORE results mount (V4/FIX-FW)', () => {
  const src = fs.readFileSync(path.join(ROOT, 'src', 'minigames', 'framework.js'), 'utf8');
  // onEnd(): portrait re-locked + the per-run flag reset, THEN the results
  // screen mounts — exit()'s re-lock alone only fired when the scene later
  // left, so a landscape game's results rendered sideways until "Home".
  assert.match(src, /applyOrientationLock\('portrait'\);\s*\r?\n\s*gameOrientation = 'portrait';[\s\S]{0,700}?ui\.showScreen\('mgResults'\)/);
  // landscape is re-allowed only on the NEXT landscape game's enter()
  assert.match(src, /applyOrientationLock\(orientationLockFor\(gameOrientation\)\)/);
  // exit() keeps its own re-lock as the safety net for non-results exits
  // (pause-quit, failed init, direct scene switches)
  assert.match(src, /exit\(\) \{[\s\S]*?applyOrientationLock\('portrait'\);\s*\r?\n\s*gameOrientation = 'portrait';/);
});

test('V4/ORIENT wiring: the rotate gate cleans up listeners and never deadlocks', () => {
  const src = fs.readFileSync(path.join(ROOT, 'src', 'minigames', 'framework.js'), 'utf8');
  // single-settle finish(): timer cleared, BOTH viewport listeners removed,
  // overlay removed, cleanup slot nulled
  assert.match(src, /clearTimeout\(autoTimer\);\s*\r?\n\s*mql\?\.removeEventListener\?\.\('change', onViewportChange\);\s*\r?\n\s*window\.removeEventListener\('resize', onViewportChange\);\s*\r?\n\s*overlay\.remove\(\);\s*\r?\n\s*rotateGateCleanup = null;/);
  // no-deadlock fallbacks: tap-to-continue + the auto-continue timer
  assert.match(src, /overlay\.addEventListener\('click'/);
  assert.match(src, /setTimeout\(finish, ROTATE_GATE\.AUTO_CONTINUE_MS\)/);
  // exit() can always resolve a pending gate
  assert.match(src, /rotateGateCleanup = finish;/);
  // the gate only fires on the pure decision (portrait games skip instantly)
  assert.match(src, /needsRotateGate\(gameOrientation, innerWidth, innerHeight/);
});

test('V4/ORIENT: Info.plist allows portrait + landscape (landscape games rotate)', () => {
  const plist = fs.readFileSync(path.join(ROOT, 'ios', 'App', 'App', 'Info.plist'), 'utf8');
  // iOS must ALLOW landscape at the OS level so a landscape game's viewport
  // can rotate mid-round; the JS layer keeps everything else portrait.
  for (const o of ['UIInterfaceOrientationPortrait', 'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight']) {
    assert.ok(plist.includes(`<string>${o}</string>`), o);
  }
  // upside-down portrait stays OFF (notch-era iPhones never report it and the
  // UI was never designed for it)
  assert.ok(!plist.includes('UIInterfaceOrientationPortraitUpsideDown'));
  assert.match(plist, /<key>UIRequiresFullScreen<\/key>\s*<true\/>/);
});
