// V6.1/G3 (FINAL-WAVE B6 + A4) — the UI-charm suite: ride-photo polaroid
// helpers (frame classifier + bounded alternating ride tilt, incl. the
// NEGATIVE unknown-frame cases), the albumScreen grid/viewer wiring seams
// (class, „Funkelpark" chin strip, localized viewer chip), the styles.css
// keepsake rules (scoped to .g3-ph-ride ONLY — ordinary polaroids stay
// pixel-semantically untouched), the A4 viewport-fixed toast anchor, and the
// main.js versary/strings marked-block wiring. Node-only: pure helpers +
// static source seams (the DOM render is covered by the CDP screenshots in
// the G3 report — v4SettingsUi.test.js precedent).

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  polaroidJitter,
  isParkRideFrame,
  ridePolaroidTilt,
} from '../src/ui/albumScreen.js';
import { VERSARY_EN, VERSARY_DE } from '../src/ui/versary.js';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const source = (rel) => readFileSync(join(ROOT, rel), 'utf8');

// ---------------------------------------------------------------------------
// B6 — pure helpers
// ---------------------------------------------------------------------------

test('isParkRideFrame: ONLY the two persisted ride frames qualify', () => {
  assert.equal(isParkRideFrame('coasterRide'), true);
  assert.equal(isParkRideFrame('ferrisWheel'), true);
  // negative/unknown-frame cases — ordinary photo-mode shots, legacy
  // records without a frame, junk and near-miss spellings all stay plain
  for (const junk of [
    'photoMode', 'unknownFrame', 'CoasterRide', 'FERRISWHEEL', 'coaster',
    '', null, undefined, 0, 42, {}, [], true,
  ]) {
    assert.equal(isParkRideFrame(junk), false, `frame=${String(junk)}`);
  }
});

test('ridePolaroidTilt: deterministic, bounded, alternating — 1.6× the wall tilt', () => {
  for (let i = 0; i < 24; i += 1) {
    const tilt = ridePolaroidTilt(i);
    assert.equal(tilt, ridePolaroidTilt(i), `index ${i}: deterministic`);
    assert.ok(Math.abs(tilt) <= 3.6, `index ${i}: |${tilt}| ≤ 3.6°`);
    assert.ok(Math.abs(tilt) >= 1.2, `index ${i}: still visibly tilted`);
    assert.equal(Math.sign(tilt), Math.sign(polaroidJitter(i)),
      `index ${i}: same alternation as the plain wall`);
    assert.equal(tilt, Math.round(tilt * 10) / 10, `index ${i}: one decimal`);
  }
  // even indices lean one way, odd the other (hand-pinned wall read)
  assert.ok(ridePolaroidTilt(0) < 0 && ridePolaroidTilt(1) > 0);
  // junk degrades finite, like the base helper
  for (const junk of [undefined, null, NaN, 'x', -3, 2.7]) {
    assert.ok(Number.isFinite(ridePolaroidTilt(junk)), `junk ${String(junk)}`);
  }
});

// ---------------------------------------------------------------------------
// B6 — albumScreen wiring seams (grid + viewer)
// ---------------------------------------------------------------------------

test('B6 grid: ride cells gain the ADDITIVE class + ride tilt + Funkelpark strip', () => {
  const src = source('src/ui/albumScreen.js');
  // additive layering: the base polaroid lines stay verbatim (pinned by
  // screenThemeDetails.test.js) and the ride treatment adds on top
  assert.ok(src.includes("cell.classList.add('g3-ph-ride')"),
    'ride cells must add the g3-ph-ride class');
  assert.ok(src.includes('const ride = isParkRideFrame(m.frame)'),
    'the classifier must gate on the persisted frame metadata');
  assert.ok(src.includes("setProperty('--b3-tilt', `${ridePolaroidTilt(idx)}deg`)"),
    'ride cells must override the tilt with the bounded ride helper');
  assert.ok(src.includes("strip.className = 'g3-ph-ride-strip'"),
    'the chin strip element must exist');
  assert.match(src, /strip\.textContent = tG\('gallery\.frame\.park'\)/,
    'the strip text must resolve through the localized gallery seam');
});

test('B6 viewer: the localized park chip is added AND removed per photo', () => {
  const src = source('src/ui/albumScreen.js');
  assert.ok(src.includes("parkChip.className = 'g3-vw-park'"), 'chip element');
  assert.match(src, /parkChip\.textContent = tG\('gallery\.frame\.park'\)/,
    'chip text must be localized');
  assert.match(src, /isParkRideFrame\(meta\?\.frame\)/,
    'chip must gate on the open photo\u2019s frame');
  assert.match(src, /parkChip\?\.remove\(\)/,
    'swiping to a non-ride photo must REMOVE the chip');
});

test('B6 strings: gallery.frame.park is EN+DE (proper noun, both langs)', () => {
  assert.equal(VERSARY_EN['gallery.frame.park'], 'Funkelpark');
  assert.equal(VERSARY_DE['gallery.frame.park'], 'Funkelpark');
});

test('B6 styles: keepsake rules are scoped to .g3-ph-ride ONLY (others untouched)', () => {
  const css = source('src/ui/styles.css');
  // every new B6 grid rule targets the ride class explicitly
  assert.match(css, /\.g59-ph-cell\.b3-polaroid\.g3-ph-ride \{/);
  assert.match(css, /\.g59-ph-cell\.b3-polaroid\.g3-ph-ride::before \{/);
  assert.match(css, /\.g3-ph-ride \.g3-ph-ride-strip \{/);
  assert.match(css, /\.g59-vw-top \.g3-vw-park \{/);
  // the base polaroid rules survive verbatim (pixel-semantic no-change proof
  // for ordinary frames — also pinned by screenThemeDetails.test.js)
  assert.match(css, /\.screen-album \.g59-ph-cell\.b3-polaroid \{\r?\n {2}background: #fdfbf5;/);
  // strips/chips never eat taps
  const strip = css.slice(css.indexOf('.g3-ph-ride .g3-ph-ride-strip'));
  assert.match(strip.slice(0, 600), /pointer-events: none;/);
});

// ---------------------------------------------------------------------------
// A4 — the viewport-fixed toast anchor
// ---------------------------------------------------------------------------

test('A4 toast: viewport-FIXED with the safe-bottom base offset', () => {
  const css = source('src/ui/styles.css');
  const toast = css.slice(css.indexOf('.toast {'), css.indexOf('.toast::before'));
  assert.match(toast, /position: fixed;/, '.toast must be viewport-fixed');
  assert.match(toast, /bottom: calc\(4\.75rem \+ var\(--safe-bottom\)\);/,
    'base offset honors --safe-bottom');
  assert.match(toast, /max-width: min\(86vw, 22rem\);/, '320px width cap survives');
});

test('A4 toast: the three anchor rules are mutually exclusive (sheet/screen/dock)', () => {
  const css = source('src/ui/styles.css');
  // NEW: full screen up (no sheet) → safe bottom edge, off the content rows
  // the 4.75rem home offset / dock lift used to cover. NO dock qualifier:
  // hud.js keeps .g5-hud un-hidden under screens on the home scene, so the
  // screen must win over the dock outright.
  assert.match(
    css,
    /#ui:has\(\.screen\):not\(:has\(\.panel-backdrop\)\) \.toast \{\r?\n {2}bottom: max\(0\.75rem, calc\(var\(--safe-bottom\) \+ 0\.375rem\)\);/,
  );
  // the home-dock lift + its uiScale-130 variant now stand down under screens
  // (:not(:has(.screen))) — offsets preserved verbatim
  assert.match(css, /#ui:has\(\.g5-hud:not\(\.g5-hud-hidden\)\):not\(:has\(\.panel-backdrop\)\):not\(:has\(\.screen\)\) \.toast \{\r?\n {2}bottom: calc\(max\(2\.75rem, calc\(var\(--safe-bottom\) \+ 2rem\)\) \+ 7\.625rem\);/);
  assert.match(css, /:root\[data-ui-scale='130'\] #ui:has\(\.g5-hud:not\(\.g5-hud-hidden\)\):not\(:has\(\.panel-backdrop\)\):not\(:has\(\.screen\)\) \.toast \{\r?\n {2}bottom: calc\(max\(2\.75rem, calc\(var\(--safe-bottom\) \+ 2rem\)\) \+ 5rem\);/);
});

// ---------------------------------------------------------------------------
// main.js — the single V6.1/G3 marked block
// ---------------------------------------------------------------------------

test('main.js: ONE marked V6.1/G3 block — additive dict merge + versary poll', () => {
  const src = source('src/main.js');
  assert.equal(src.match(/---- V6\.1\/G3: Gooby-versary/g)?.length, 1,
    'exactly one V6.1/G3 marked block');
  assert.match(src, /---- end V6\.1\/G3 block ----/);
  const block = src.slice(src.indexOf('---- V6.1/G3'), src.indexOf('---- end V6.1/G3'));
  assert.match(block, /import\('\.\/ui\/versary\.js'\)/, 'lazy import (guarded boot)');
  assert.match(block, /if \(!\(key in globalDict\)\) globalDict\[key\] = value;/,
    'ADDITIVE merge — existing (G1 canonical) keys always win');
  assert.match(block, /versaryMod\.initVersary\(\{ store, ui, sceneManager, playCutscene, isCutsceneActive \}\)/,
    'the poll receives the director handles');
  assert.match(block, /console\.warn\('\[boot\] V6\.1\/G3/, 'guarded — a broken chunk never kills boot');
});
