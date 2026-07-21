// GOOBY V5/FIX-UI — click-outside dismissal for panel backdrops / overlay
// scrims (owned by the V5 UI-fix agent; consumed by ui.js + albumScreen.js).
//
// THE BUG this replaces: overlays used to close on `pointerdown` on the
// backdrop. Closing synchronously flips the leaving element to
// pointer-events:none (ui.js animateOut / element.remove()), so when the
// browser dispatched the gesture's synthetic `click` at pointerup a moment
// later, hit-testing skipped the now-inert backdrop and the click landed on
// whatever UI sat underneath — classic click-through (a shop row under the
// panel scrim, a sticker slot under the detail sheet, …).
//
// THE PATTERN: ARM on a pointerdown whose target is the backdrop ITSELF;
// DISARM on pointercancel (OS scroll/gesture takeover); DISMISS only when the
// following `click` fires while still armed AND its target is again the
// backdrop itself. A press that starts on panel content never arms, a
// cancelled gesture never dismisses, and because dismissal now rides the
// gesture-completing `click`, no later synthetic event is left to fall
// through onto lower UI.
//
// The state machine + target predicate are pure (node:test —
// test/uiBackdropDismiss.test.js); attachBackdropDismiss() is the thin DOM
// wiring shared by every backdrop consumer.

/**
 * True when the event hit `el` ITSELF — not a child. Null-safe so the pure
 * tests can feed plain `{ target }` objects (or nothing at all).
 * @param {{target?: EventTarget|null}|null|undefined} event
 * @param {EventTarget|null|undefined} el
 * @returns {boolean}
 */
export function isDirectTarget(event, el) {
  return !!el && event?.target === el;
}

/**
 * Pure arming state machine for one backdrop. Feed it "was the event on the
 * backdrop itself" booleans; it answers whether the click should dismiss.
 * @returns {{
 *   isArmed: () => boolean,
 *   pointerDown: (onBackdrop: boolean) => boolean,
 *   pointerCancel: () => void,
 *   click: (onBackdrop: boolean) => boolean,
 * }}
 */
export function createDismissArming() {
  let armed = false;
  return {
    /** @returns {boolean} current armed state (test/debug surface) */
    isArmed() {
      return armed;
    },
    /**
     * pointerdown: arm only when the press began on the backdrop itself.
     * @param {boolean} onBackdrop @returns {boolean} armed state after
     */
    pointerDown(onBackdrop) {
      armed = onBackdrop === true;
      return armed;
    },
    /** pointercancel: the gesture was taken over — never dismiss from it. */
    pointerCancel() {
      armed = false;
    },
    /**
     * click: dismiss only if armed AND the click landed on the backdrop
     * itself. Always consumes the arming (one dismissal per press).
     * @param {boolean} onBackdrop @returns {boolean} true → dismiss now
     */
    click(onBackdrop) {
      const dismiss = armed && onBackdrop === true;
      armed = false;
      return dismiss;
    },
  };
}

/**
 * Wire the armed pointerdown→click dismissal onto a backdrop element.
 * @param {EventTarget} backdrop the scrim element (dismiss target)
 * @param {(event: Event) => void} onDismiss called on a confirmed
 *   click-outside — the caller owns what "close" means (sfx, closePanel, …)
 * @returns {ReturnType<typeof createDismissArming>} the arming state
 *   machine (exposed for tests/diagnostics)
 */
export function attachBackdropDismiss(backdrop, onDismiss) {
  const arming = createDismissArming();
  backdrop.addEventListener('pointerdown', (e) => {
    arming.pointerDown(isDirectTarget(e, backdrop));
  });
  backdrop.addEventListener('pointercancel', () => {
    arming.pointerCancel();
  });
  backdrop.addEventListener('click', (e) => {
    if (arming.click(isDirectTarget(e, backdrop))) onDismiss(e);
  });
  return arming;
}
