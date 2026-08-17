// GOOBY V5/FIX-UI — backdrop click-outside dismissal (src/ui/backdropDismiss.js).
// Pure node:test (no DOM/three, per AGENTS.md): the target predicate, the
// arm/disarm/dismiss state machine, the attach wiring driven by a fake
// EventTarget, and source-scan invariants proving ui.js + albumScreen.js no
// longer close overlays on pointerdown (the click-through bug: closing on
// pointerdown flipped the backdrop to pointer-events:none before the
// browser's synthetic click, which then re-targeted the UI underneath).

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  isDirectTarget,
  createDismissArming,
  attachBackdropDismiss,
} from '../src/ui/backdropDismiss.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = (rel) => fs.readFileSync(path.join(ROOT, ...rel.split('/')), 'utf8');

/** Minimal EventTarget stand-in: records listeners, dispatches synchronously. */
function fakeBackdrop() {
  /** @type {Map<string, Array<(e: object) => void>>} */
  const listeners = new Map();
  return {
    addEventListener(type, fn) {
      if (!listeners.has(type)) listeners.set(type, []);
      listeners.get(type).push(fn);
    },
    dispatch(type, event = {}) {
      for (const fn of listeners.get(type) ?? []) fn(event);
    },
    listenerTypes() {
      return [...listeners.keys()].sort();
    },
  };
}

// ---------------------------------------------------------------------------
// isDirectTarget — the "on the backdrop ITSELF, not a child" predicate
// ---------------------------------------------------------------------------

test('isDirectTarget: true only for the element itself', () => {
  const el = {};
  const child = {};
  assert.equal(isDirectTarget({ target: el }, el), true);
  assert.equal(isDirectTarget({ target: child }, el), false);
});

test('isDirectTarget: null-safe on event, target and element', () => {
  const el = {};
  assert.equal(isDirectTarget(null, el), false);
  assert.equal(isDirectTarget(undefined, el), false);
  assert.equal(isDirectTarget({}, el), false);
  assert.equal(isDirectTarget({ target: null }, el), false);
  assert.equal(isDirectTarget({ target: el }, null), false);
  assert.equal(isDirectTarget({ target: undefined }, undefined), false);
});

// ---------------------------------------------------------------------------
// createDismissArming — pure state machine
// ---------------------------------------------------------------------------

test('arming: down-on-backdrop then click-on-backdrop dismisses', () => {
  const arming = createDismissArming();
  assert.equal(arming.isArmed(), false);
  assert.equal(arming.pointerDown(true), true);
  assert.equal(arming.isArmed(), true);
  assert.equal(arming.click(true), true);
  assert.equal(arming.isArmed(), false, 'click consumes the arming');
});

test('arming: pointerDown NEVER dismisses by itself (the original bug)', () => {
  const arming = createDismissArming();
  // pointerDown only reports the armed state — dismissal is exclusively the
  // click()'s decision, so nothing can close mid-gesture anymore.
  assert.equal(arming.pointerDown(true), true);
  assert.equal(arming.isArmed(), true, 'still only ARMED after pointerdown');
});

test('arming: press starting on panel content never arms', () => {
  const arming = createDismissArming();
  assert.equal(arming.pointerDown(false), false);
  assert.equal(arming.click(true), false, 'click-outside without arming is ignored');
});

test('arming: click landing on content does not dismiss (drag onto panel)', () => {
  const arming = createDismissArming();
  arming.pointerDown(true);
  assert.equal(arming.click(false), false);
  assert.equal(arming.isArmed(), false, 'arming is still consumed');
});

test('arming: pointercancel disarms (OS gesture/scroll takeover)', () => {
  const arming = createDismissArming();
  arming.pointerDown(true);
  arming.pointerCancel();
  assert.equal(arming.isArmed(), false);
  assert.equal(arming.click(true), false);
});

test('arming: one dismissal per press — stray second click is ignored', () => {
  const arming = createDismissArming();
  arming.pointerDown(true);
  assert.equal(arming.click(true), true);
  assert.equal(arming.click(true), false, 'no re-dismiss without a new pointerdown');
});

test('arming: a new press on content clears a stale earlier arming', () => {
  const arming = createDismissArming();
  arming.pointerDown(true); // press 1 on backdrop, click never delivered
  arming.pointerDown(false); // press 2 starts on the panel card
  assert.equal(arming.click(true), false);
});

// ---------------------------------------------------------------------------
// attachBackdropDismiss — DOM wiring against a fake EventTarget
// ---------------------------------------------------------------------------

test('attach: wires exactly pointerdown + pointercancel + click', () => {
  const backdrop = fakeBackdrop();
  attachBackdropDismiss(backdrop, () => {});
  assert.deepEqual(backdrop.listenerTypes(), ['click', 'pointercancel', 'pointerdown']);
});

test('attach: full tap on the backdrop dismisses once, on the click', () => {
  const backdrop = fakeBackdrop();
  const dismissed = [];
  attachBackdropDismiss(backdrop, (e) => dismissed.push(e));
  backdrop.dispatch('pointerdown', { target: backdrop });
  assert.equal(dismissed.length, 0, 'REGRESSION: must NOT close on pointerdown');
  const clickEvent = { target: backdrop };
  backdrop.dispatch('click', clickEvent);
  assert.equal(dismissed.length, 1);
  assert.equal(dismissed[0], clickEvent, 'onDismiss receives the click event');
});

test('attach: press starting on the panel card never dismisses', () => {
  const backdrop = fakeBackdrop();
  const card = {};
  let dismissed = 0;
  attachBackdropDismiss(backdrop, () => { dismissed += 1; });
  backdrop.dispatch('pointerdown', { target: card }); // bubbled from the card
  backdrop.dispatch('click', { target: backdrop }); // finger slid off the card
  assert.equal(dismissed, 0);
});

test('attach: cancelled gesture never dismisses', () => {
  const backdrop = fakeBackdrop();
  let dismissed = 0;
  attachBackdropDismiss(backdrop, () => { dismissed += 1; });
  backdrop.dispatch('pointerdown', { target: backdrop });
  backdrop.dispatch('pointercancel', { target: backdrop });
  backdrop.dispatch('click', { target: backdrop });
  assert.equal(dismissed, 0);
});

test('attach: click bubbling up from panel content is ignored', () => {
  const backdrop = fakeBackdrop();
  const card = {};
  let dismissed = 0;
  attachBackdropDismiss(backdrop, () => { dismissed += 1; });
  backdrop.dispatch('pointerdown', { target: backdrop });
  backdrop.dispatch('click', { target: card });
  assert.equal(dismissed, 0);
});

test('attach: consecutive taps each dismiss independently', () => {
  const backdrop = fakeBackdrop();
  let dismissed = 0;
  attachBackdropDismiss(backdrop, () => { dismissed += 1; });
  for (let i = 0; i < 3; i += 1) {
    backdrop.dispatch('pointerdown', { target: backdrop });
    backdrop.dispatch('click', { target: backdrop });
  }
  assert.equal(dismissed, 3);
});

// V6/UI-LAYERS (A4): lock the child drag/cancel non-dismissal explicitly —
// panels host draggable content (sliders, scrollers); neither an escaped
// child drag nor an OS-cancelled gesture may ever close the sheet.

test('attach: child drag escaping onto the scrim never dismisses (either way)', () => {
  const backdrop = fakeBackdrop();
  const child = {};
  let dismissed = 0;
  attachBackdropDismiss(backdrop, () => { dismissed += 1; });
  // drag starts on the sheet content, finger releases over the scrim
  backdrop.dispatch('pointerdown', { target: child });
  backdrop.dispatch('click', { target: backdrop });
  // and the reverse: press on the scrim, release back over the content
  backdrop.dispatch('pointerdown', { target: backdrop });
  backdrop.dispatch('click', { target: child });
  assert.equal(dismissed, 0);
});

test('attach: cancelled drag re-arms cleanly — a later full tap dismisses once', () => {
  const backdrop = fakeBackdrop();
  let dismissed = 0;
  attachBackdropDismiss(backdrop, () => { dismissed += 1; });
  // gesture begins on the scrim but the OS takes it over (scroll/system swipe)
  backdrop.dispatch('pointerdown', { target: backdrop });
  backdrop.dispatch('pointercancel', { target: backdrop });
  backdrop.dispatch('click', { target: backdrop });
  assert.equal(dismissed, 0, 'cancelled gesture must not dismiss');
  backdrop.dispatch('pointerdown', { target: backdrop });
  backdrop.dispatch('click', { target: backdrop });
  assert.equal(dismissed, 1, 'the machine is not stuck after a cancel');
});

// ---------------------------------------------------------------------------
// Source-scan invariants — the consumers actually use the pattern
// ---------------------------------------------------------------------------

test('ui.js: panel backdrop uses attachBackdropDismiss, not pointerdown-close', () => {
  const src = source('src/ui/ui.js');
  // V6/UI-LAYERS: the confirmed click-outside now consults the pure layer
  // policy (dismissable flag + top-of-stack) before ui.closePanel(id).
  assert.match(src, /attachBackdropDismiss\(backdrop, \(\) => \{/);
  assert.match(
    src,
    /shouldBackdropClose\(activePanels\.map\(\(p\) => p\.id\), id, dismissable\)/,
    'the dismiss callback must consult the stack top + dismissable flag',
  );
  assert.doesNotMatch(
    src,
    /backdrop\.addEventListener\(\s*['"]pointerdown['"]/,
    'openPanel must not close on pointerdown (click-through bug)',
  );
});

test('albumScreen.js: sheet/secret/delete-confirm overlays use the helper', () => {
  const src = source('src/ui/albumScreen.js');
  const attaches = src.match(/attachBackdropDismiss\(/g) ?? [];
  assert.equal(attaches.length, 3, 'sticker sheet + secret sheet + delete confirm');
  assert.doesNotMatch(
    src,
    /sheetEl\.addEventListener\(\s*['"]pointerdown['"]/,
    'sticker sheets must not close on pointerdown',
  );
  assert.doesNotMatch(
    src,
    /c\.addEventListener\(\s*['"]pointerdown['"]/,
    'photo delete confirm must not close on pointerdown',
  );
  // The photo viewer's swipe tracker legitimately keeps its own pointerdown.
  assert.match(src, /stage\.addEventListener\('pointerdown'/);
});
