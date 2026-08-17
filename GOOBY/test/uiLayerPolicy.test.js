// GOOBY V6/UI-LAYERS (PLAN6 Wave A/A4) — pure panel-layer policy tests.
// Pure node:test (no DOM/three, per AGENTS.md): ui.js exports the layering
// DECISIONS (canOpenPanel duplicate guard, isBackdropDismissable opt-out,
// topPanelId/shouldBackdropClose top-of-stack rule) headlessly; a tiny stack
// model composes them with the V5 armed pointerdown→click machine exactly
// like openPanel() does. dailyBonusPopup.js exports its auto-show decision
// (shouldOfferDailyBonus) — the claim is the ONLY latch, no session shownDay.
// Source-scan invariants prove the consumers actually wire the policy.

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  canOpenPanel,
  isBackdropDismissable,
  topPanelId,
  shouldBackdropClose,
} from '../src/ui/ui.js';
import { createDismissArming } from '../src/ui/backdropDismiss.js';
import { shouldOfferDailyBonus } from '../src/ui/dailyBonusPopup.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = (rel) => fs.readFileSync(path.join(ROOT, ...rel.split('/')), 'utf8');

/**
 * Minimal panel-stack model composing the SAME pure pieces openPanel() wires:
 * duplicate guard on open, per-panel arming machine, and the policy check on
 * the confirmed backdrop click. No DOM — ids in an array, bottom → top.
 */
function panelStackModel() {
  /** @type {Array<{id: string, dismissable: boolean,
   *   arming: ReturnType<typeof createDismissArming>}>} */
  const stack = [];
  return {
    /** openPanel(): duplicate-guarded push. @returns {boolean} opened? */
    open(id, options) {
      if (!canOpenPanel(stack.map((p) => p.id), id)) return false;
      stack.push({
        id,
        dismissable: isBackdropDismissable(options),
        arming: createDismissArming(),
      });
      return true;
    },
    /** closePanel(): remove the first id match. @returns {boolean} closed? */
    close(id) {
      const i = stack.findIndex((p) => p.id === id);
      if (i < 0) return false;
      stack.splice(i, 1);
      return true;
    },
    /**
     * A full clean tap (down + click, both on the scrim itself) on the given
     * panel's backdrop, run through arming AND the layer policy.
     * @returns {boolean} did the tap close the panel?
     */
    backdropTap(id) {
      const entry = stack.find((p) => p.id === id);
      if (!entry) return false;
      entry.arming.pointerDown(true);
      if (!entry.arming.click(true)) return false;
      if (!shouldBackdropClose(stack.map((p) => p.id), id, entry.dismissable)) return false;
      return this.close(id);
    },
    /**
     * A drag that starts on the panel's CONTENT and releases over the scrim
     * (browser click targets the backdrop) — must never arm, never close.
     * @returns {boolean} did it close?
     */
    childDrag(id) {
      const entry = stack.find((p) => p.id === id);
      if (!entry) return false;
      entry.arming.pointerDown(false);
      if (!entry.arming.click(true)) return false;
      if (!shouldBackdropClose(stack.map((p) => p.id), id, entry.dismissable)) return false;
      return this.close(id);
    },
    /**
     * A gesture on the scrim the OS cancels (scroll/system swipe takeover).
     * @returns {boolean} did it close?
     */
    cancelledTap(id) {
      const entry = stack.find((p) => p.id === id);
      if (!entry) return false;
      entry.arming.pointerDown(true);
      entry.arming.pointerCancel();
      if (!entry.arming.click(true)) return false;
      return this.close(id);
    },
    ids() {
      return stack.map((p) => p.id);
    },
  };
}

// ---------------------------------------------------------------------------
// canOpenPanel — the duplicate-id guard
// ---------------------------------------------------------------------------

test('canOpenPanel: allowed into an empty stack and for new ids', () => {
  assert.equal(canOpenPanel([], 'careSheet'), true);
  assert.equal(canOpenPanel(['careSheet'], 'foodTray'), true);
});

test('canOpenPanel: rejects an id already anywhere in the stack', () => {
  assert.equal(canOpenPanel(['careSheet'], 'careSheet'), false);
  assert.equal(canOpenPanel(['careSheet', 'foodTray'], 'careSheet'), false, 'not only the top');
});

test('model: duplicate open returns false and mounts nothing', () => {
  const stack = panelStackModel();
  assert.equal(stack.open('careSheet'), true);
  assert.equal(stack.open('careSheet'), false, 'second open of the same id must fail');
  assert.deepEqual(stack.ids(), ['careSheet'], 'no orphaned duplicate sheet');
});

test('model: explicit close + open is the sanctioned re-open-to-front recipe', () => {
  const stack = panelStackModel();
  stack.open('foodTray');
  stack.open('careSheet');
  assert.equal(stack.open('foodTray'), false, 're-open while buried still fails');
  assert.equal(stack.close('foodTray'), true);
  assert.equal(stack.open('foodTray'), true, 'closed ids may open again');
  assert.deepEqual(stack.ids(), ['careSheet', 'foodTray'], 'now on top');
});

// ---------------------------------------------------------------------------
// isBackdropDismissable — the backdropDismiss:false opt-out
// ---------------------------------------------------------------------------

test('isBackdropDismissable: default is dismissable', () => {
  assert.equal(isBackdropDismissable(), true);
  assert.equal(isBackdropDismissable(undefined), true);
  assert.equal(isBackdropDismissable(null), true);
  assert.equal(isBackdropDismissable({}), true);
  assert.equal(isBackdropDismissable({ backdropDismiss: true }), true);
});

test('isBackdropDismissable: only an explicit false opts out', () => {
  assert.equal(isBackdropDismissable({ backdropDismiss: false }), false);
  assert.equal(isBackdropDismissable({ backdropDismiss: 0 }), true, 'no truthiness coercion');
});

// ---------------------------------------------------------------------------
// topPanelId + shouldBackdropClose — top-of-stack resolution
// ---------------------------------------------------------------------------

test('topPanelId: null when empty, last id otherwise', () => {
  assert.equal(topPanelId([]), null);
  assert.equal(topPanelId(['a']), 'a');
  assert.equal(topPanelId(['a', 'b', 'c']), 'c');
});

test('shouldBackdropClose: only a dismissable panel at stack top closes', () => {
  assert.equal(shouldBackdropClose(['a', 'b'], 'b', true), true);
  assert.equal(shouldBackdropClose(['a', 'b'], 'a', true), false, 'buried panel never closes');
  assert.equal(shouldBackdropClose(['a', 'b'], 'b', false), false, 'non-dismissable never closes');
  assert.equal(shouldBackdropClose([], 'a', true), false, 'gone from the stack');
});

test('model: stacked panels close strictly top-first', () => {
  const stack = panelStackModel();
  stack.open('a');
  stack.open('b');
  stack.open('c');
  assert.equal(stack.backdropTap('a'), false, 'tap on a buried backdrop is ignored');
  assert.equal(stack.backdropTap('b'), false);
  assert.deepEqual(stack.ids(), ['a', 'b', 'c']);
  assert.equal(stack.backdropTap('c'), true, 'only the top panel closes');
  assert.equal(stack.backdropTap('b'), true, 'then the next one is the top');
  assert.equal(stack.backdropTap('a'), true);
  assert.deepEqual(stack.ids(), []);
});

test('model: non-dismissable top ignores the scrim; a sheet above it still works', () => {
  const stack = panelStackModel();
  stack.open('dailyBonus', { backdropDismiss: false });
  assert.equal(stack.backdropTap('dailyBonus'), false, 'claim-gated popup survives the tap');
  stack.open('careSheet'); // a dismissable sheet stacked on top
  assert.equal(stack.backdropTap('careSheet'), true, 'the top sheet still dismisses');
  assert.equal(stack.backdropTap('dailyBonus'), false, 'back on top, still button-only');
  assert.deepEqual(stack.ids(), ['dailyBonus'], 'must be closed via its own button');
});

test('model: child drag and cancelled gestures never dismiss the top panel', () => {
  const stack = panelStackModel();
  stack.open('foodTray');
  assert.equal(stack.childDrag('foodTray'), false, 'drag off the sheet content stays open');
  assert.equal(stack.cancelledTap('foodTray'), false, 'OS-cancelled gesture stays open');
  assert.deepEqual(stack.ids(), ['foodTray']);
  assert.equal(stack.backdropTap('foodTray'), true, 'a clean tap afterwards still works');
});

// ---------------------------------------------------------------------------
// shouldOfferDailyBonus — claim is the ONLY latch (no shownDay session flag)
// ---------------------------------------------------------------------------

/** Baseline quiet-home claimable snapshot for the poll decision. */
const OFFER = Object.freeze({
  claimable: true,
  onboardingDone: true,
  atHome: true,
  screenOpen: false,
  panelOpen: false,
});

test('dailyBonus offer: quiet claimable home → show', () => {
  assert.equal(shouldOfferDailyBonus({ ...OFFER }), true);
});

test('dailyBonus offer: each poll guard blocks on its own', () => {
  assert.equal(shouldOfferDailyBonus({ ...OFFER, claimable: false }), false, 'already claimed');
  assert.equal(shouldOfferDailyBonus({ ...OFFER, onboardingDone: false }), false, 'mid-tutorial');
  assert.equal(shouldOfferDailyBonus({ ...OFFER, atHome: false }), false, 'not home yet');
  assert.equal(shouldOfferDailyBonus({ ...OFFER, screenOpen: true }), false, 'screen up');
  assert.equal(shouldOfferDailyBonus({ ...OFFER, panelOpen: true }), false, 'sheet up (incl. itself)');
});

test('dailyBonus offer: undefined onboarding flag stays permissive (legacy)', () => {
  // The old poll only blocked on an EXPLICIT false — saves without the flag
  // (pre-onboarding schema) must keep getting their popup.
  assert.equal(shouldOfferDailyBonus({ ...OFFER, onboardingDone: undefined }), true);
});

test('dailyBonus offer: unclaimed dismissal re-offers; claiming ends it', () => {
  // The decision is STATELESS — the popup closed without a claim (closeAll,
  // app kill) leaves claimable true, so the very next quiet tick re-offers.
  assert.equal(shouldOfferDailyBonus({ ...OFFER }), true);
  assert.equal(shouldOfferDailyBonus({ ...OFFER }), true, 'no session latch between ticks');
  // claim() records daily.lastClaimDay → isClaimable() false → never again today
  assert.equal(shouldOfferDailyBonus({ ...OFFER, claimable: false }), false);
});

// ---------------------------------------------------------------------------
// Source-scan invariants — the consumers actually wire the policy
// ---------------------------------------------------------------------------

test('ui.js: openPanel takes options, guards duplicates, checks the policy', () => {
  const src = source('src/ui/ui.js');
  assert.match(src, /openPanel\(id, params = \{\}, options = \{\}\)/);
  assert.match(
    src,
    /if \(!canOpenPanel\(activePanels\.map\(\(p\) => p\.id\), id\)\) \{\r?\n\s*console\.warn\([^)]*\);\r?\n\s*return false;/,
    'duplicate open must warn and return false',
  );
  assert.match(src, /const dismissable = isBackdropDismissable\(options\);/);
  assert.match(src, /shouldBackdropClose\(activePanels\.map\(\(p\) => p\.id\), id, dismissable\)/);
});

test('dailyBonusPopup.js: button-only popup, claim flow intact, no shownDay latch', () => {
  const src = source('src/ui/dailyBonusPopup.js');
  assert.match(src, /ui\.openPanel\('dailyBonus', \{\}, \{ backdropDismiss: false \}\)/);
  // Comments may still NAME the removed latch (history); CODE may not use it.
  const code = src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\r\n]*/g, '');
  assert.doesNotMatch(code, /shownDay/, 'the pre-claim session latch must stay gone');
  assert.match(src, /shouldOfferDailyBonus\(\{/, 'the poll must use the pure decision');
  assert.match(src, /const result = claim\(store\.get\(\)\);/, 'claim/economy flow unchanged');
});

test('whatsNew.js: one-time tour is button-only, seen still latches on mount', () => {
  const src = source('src/ui/whatsNew.js');
  assert.match(src, /ui\.openPanel\('whatsNew', \{ version \}, \{ backdropDismiss: false \}\)/);
  assert.match(
    src,
    /store\.set\(`onboarding\.whatsNew\$\{version\}Seen`, true\);/,
    'once-only mount latch stays (survives app kill mid-view)',
  );
});
