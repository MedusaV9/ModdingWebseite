// UI layer (§E6): DOM overlay #ui above the canvas. Full screens
// (showScreen), bottom-sheet panels (openPanel), toasts, closeAll. Screens and
// panels are plain modules exporting { mount(el, params), unmount() } and are
// registered here by their owning agents. While a screen/panel is open its DOM
// sits over the canvas with pointer-events enabled, which blocks canvas input
// (input listeners live on the canvas element — §E5).

import { t } from '../data/strings.js';
import { registerCreditsScreen } from './creditsScreen.js'; // V4/G81: §C-SYS12.4 feature-detected settings row
import { attachBackdropDismiss } from './backdropDismiss.js'; // V5/FIX-UI: armed click-outside (no click-through)

/** @typedef {{mount: (el: HTMLElement, params?: object) => void, unmount: () => void}} UiModule */
/** @typedef {{onTap?: () => void}} ToastOptions */

const TOAST_MS = 2500;

// V3/FIX-D (E20 P1-1): while a fullscreen modal panel (whatsNew) is open,
// non-critical toasts are HELD in a queue instead of stacking over the panel;
// they flush (deduped, lightly staggered) once the panel closes. Panels opt
// in via ui.holdToasts()/ui.releaseToasts() from their mount/unmount hooks.
const TOAST_FLUSH_STAGGER_MS = 400;

// ---- POLISH-D: screen/panel EXIT animations (§E6 polish) ----
// Modules still unmount() synchronously (state/listener cleanup semantics are
// unchanged); only the ELEMENT lingers with an exit class and is removed when
// its exit animation ends. A matched timeout guarantees removal even when
// animationend never fires (hidden tab, interrupted animation), and both the
// listener and the timeout clean each other up — no leaks either way.
// prefers-reduced-motion skips the animation and removes immediately.
const EXIT_ANIM_MS = 200; // keep in sync with the POLISH-D block in styles.css
const EXIT_TIMEOUT_PAD_MS = 100;

/**
 * @returns {boolean} true when the OS asks for reduced motion
 * V4/AC-9: exported — ui/juice.js reuses THIS predicate for every effect
 * gate instead of duplicating it; the typeof-window guard keeps the module
 * importable under node:test.
 */
export function prefersReducedMotion() {
  return typeof window !== 'undefined'
    && typeof window.matchMedia === 'function'
    && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
}

/**
 * Add `exitClass` to `el`, then remove the element once its exit animation
 * ends (or after the matched timeout). Pointer events are disabled up front
 * so a leaving screen/panel can never swallow taps meant for what's below.
 * @param {HTMLElement} el
 * @param {string} exitClass
 */
function animateOut(el, exitClass) {
  if (!el.isConnected) return;
  if (prefersReducedMotion()) {
    el.remove();
    return;
  }
  el.style.pointerEvents = 'none';
  el.classList.add(exitClass);
  let timer = 0;
  const finish = () => {
    clearTimeout(timer);
    el.removeEventListener('animationend', onEnd);
    el.remove();
  };
  const onEnd = (event) => {
    // Only the element's OWN exit animation counts — finite child animations
    // bubbling up must not cut the exit short.
    if (event.target !== el) return;
    finish();
  };
  el.addEventListener('animationend', onEnd);
  timer = setTimeout(finish, EXIT_ANIM_MS + EXIT_TIMEOUT_PAD_MS);
}
// ---- end POLISH-D exit helper ----

// ---- V6/UI-LAYERS: pure panel-layer policy (PLAN6 Wave A/A4) ----
// The layering DECISIONS live outside createUi() so node:test can import them
// headlessly (test/uiLayerPolicy.test.js): duplicate-open rejection, the
// per-panel backdropDismiss opt-out, and the top-of-stack rule that lets a
// confirmed backdrop tap close only the topmost sheet.

/**
 * Duplicate guard: a panel id may open only while NOT already in the stack.
 * Without this, openPanel('x') twice mounted two identical sheets and
 * closePanel('x') removed only the first match, orphaning the duplicate.
 * Callers that want re-open-to-front must closePanel(id) explicitly first.
 * @param {string[]} openIds panel ids currently open (bottom → top)
 * @param {string} id candidate panel id
 * @returns {boolean} true when opening is allowed
 */
export function canOpenPanel(openIds, id) {
  return !openIds.includes(id);
}

/**
 * Per-panel opt-out: openPanel(id, params, {backdropDismiss: false}) makes a
 * sheet button-only — claim-gated popups (dailyBonus) and one-time tours
 * (whatsNew) must never be lost to an accidental scrim tap. Default: true.
 * @param {{backdropDismiss?: boolean}|null} [options] openPanel options bag
 * @returns {boolean} true when a backdrop tap may close the panel
 */
export function isBackdropDismissable(options) {
  return options?.backdropDismiss !== false;
}

/**
 * @param {string[]} openIds panel ids currently open (bottom → top)
 * @returns {string|null} id of the topmost open panel
 */
export function topPanelId(openIds) {
  return openIds.length > 0 ? openIds[openIds.length - 1] : null;
}

/**
 * Should a confirmed click-outside on THIS panel's backdrop close it? Only
 * when the panel is dismissable AND still the top of the stack — a stale
 * click on a lower sheet's backdrop must never close under the top one.
 * @param {string[]} openIds panel ids currently open (bottom → top)
 * @param {string} id the panel whose backdrop received the confirmed click
 * @param {boolean} dismissable the panel's isBackdropDismissable() flag
 * @returns {boolean} true → close the panel now
 */
export function shouldBackdropClose(openIds, id, dismissable) {
  return dismissable === true && topPanelId(openIds) === id;
}
// ---- end V6/UI-LAYERS policy helpers ----

export function createUi() {
  const root = document.getElementById('ui');

  /** @type {Map<string, UiModule>} */
  const screens = new Map();
  /** @type {Map<string, UiModule>} */
  const panels = new Map();
  /** @type {{id: string, el: HTMLElement, mod: UiModule}|null} */
  let activeScreen = null;
  /** @type {Array<{id: string, el: HTMLElement, mod: UiModule}>} */
  const activePanels = [];
  // V3/FIX-D (E20 P1-1): toast gate state — hold depth, held texts, live els.
  let toastHold = 0;
  /** @type {Array<{text: string, options?: ToastOptions}>} */
  const heldToasts = [];
  /** @type {Set<HTMLElement>} */
  const liveToasts = new Set();
  /** @type {WeakMap<HTMLElement, ToastOptions|undefined>} */
  const liveToastOptions = new WeakMap();

  /**
   * V3/FIX-D: render one toast element now (the pre-gate toast() body).
   * V4/G70b: an optional tap action turns the notice into an accessible,
   * one-shot button without changing passive toast behavior.
   * @param {string} text
   * @param {ToastOptions} [options]
   */
  function spawnToast(text, options) {
    const el = document.createElement('div');
    // V4/AC-9: .juice-toast opts into the springy enter/exit pair injected by
    // ui/juice.js (inert until initJuice runs — AC-1's toast-in then applies).
    // Queue/hold/flush/dedupe logic below is UNCHANGED.
    el.className = 'toast juice-toast';
    el.textContent = text;
    root.appendChild(el);
    liveToasts.add(el);
    liveToastOptions.set(el, options);

    const dismiss = () => {
      if (!el.isConnected || el.classList.contains('toast-out')) return;
      el.classList.add('toast-out');
      setTimeout(() => {
        liveToasts.delete(el);
        el.remove();
      }, 300);
    };
    const timer = setTimeout(dismiss, TOAST_MS);

    if (typeof options?.onTap === 'function') {
      el.classList.add('toast-action');
      el.setAttribute('role', 'button');
      el.tabIndex = 0;
      el.style.pointerEvents = 'auto';
      el.style.cursor = 'pointer';
      el.style.minHeight = '44px';
      let activated = false;
      const activate = () => {
        if (activated) return;
        activated = true;
        clearTimeout(timer);
        liveToasts.delete(el);
        el.remove();
        options.onTap();
      };
      el.addEventListener('click', activate, { once: true });
      el.addEventListener('keydown', (event) => {
        if (event.key !== 'Enter' && event.key !== ' ') return;
        event.preventDefault();
        activate();
      });
    }
  }

  /** V3/FIX-D: queue a toast while the gate is closed (deduped by text). */
  function holdToast(text, options) {
    const existing = heldToasts.find((entry) => entry.text === text);
    if (!existing) heldToasts.push({ text, options });
    else if (!existing.options?.onTap && options?.onTap) existing.options = options;
  }

  const ui = {
    /** The overlay root element — persistent layers (minigame HUD) attach here. */
    el: root,

    /**
     * Register a full-screen module (arcade, shop, results…).
     * @param {string} id @param {UiModule} mod
     */
    registerScreen(id, mod) {
      screens.set(id, mod);
    },

    /**
     * Register a sheet panel module (food tray, confirm, permission…).
     * @param {string} id @param {UiModule} mod
     */
    registerPanel(id, mod) {
      panels.set(id, mod);
    },

    /** @param {string} id @returns {boolean} */
    hasScreen(id) {
      return screens.has(id);
    },

    /**
     * Show a full screen (closes any open screen/panels first).
     * @param {string} id
     * @param {object} [params]
     * @returns {boolean} false when the screen is not registered (toasts a hint)
     */
    showScreen(id, params = {}) {
      const mod = screens.get(id);
      if (!mod) {
        console.warn(`[ui] unknown screen '${id}'`);
        ui.toast('toast.screenMissing');
        return false;
      }
      ui.closeAll();
      const el = document.createElement('div');
      el.className = `screen screen-${id}`;
      root.appendChild(el);
      activeScreen = { id, el, mod };
      mod.mount(el, params);
      return true;
    },

    /**
     * Open a bottom-sheet panel over the current view.
     * V6/UI-LAYERS: re-opening an id already in the stack returns false (see
     * canOpenPanel); `options.backdropDismiss: false` makes the sheet
     * button-only, and a confirmed backdrop tap closes ONLY the top panel.
     * @param {string} id
     * @param {object} [params]
     * @param {{backdropDismiss?: boolean}} [options]
     * @returns {boolean}
     */
    openPanel(id, params = {}, options = {}) {
      const mod = panels.get(id);
      if (!mod) {
        console.warn(`[ui] unknown panel '${id}'`);
        ui.toast('toast.screenMissing');
        return false;
      }
      if (!canOpenPanel(activePanels.map((p) => p.id), id)) {
        console.warn(`[ui] panel '${id}' is already open`);
        return false;
      }
      const backdrop = document.createElement('div');
      backdrop.className = `panel-backdrop panel-backdrop-${id}`;
      const el = document.createElement('div');
      el.className = `panel panel-${id}`;
      backdrop.appendChild(el);
      root.appendChild(backdrop);
      // V5/FIX-UI: dismiss on the gesture-completing CLICK, not on
      // pointerdown. Closing on pointerdown flipped the backdrop to
      // pointer-events:none (animateOut) BEFORE the browser dispatched the
      // synthetic click, so that click re-targeted the UI underneath the
      // scrim (click-through). Now: arm on backdrop-target pointerdown,
      // disarm on pointercancel, close only when the click also lands on
      // the backdrop itself — see src/ui/backdropDismiss.js.
      // V6/UI-LAYERS: the confirmed click additionally consults the pure
      // policy — close only a dismissable panel that is still stack-top.
      const dismissable = isBackdropDismissable(options);
      attachBackdropDismiss(backdrop, () => {
        if (shouldBackdropClose(activePanels.map((p) => p.id), id, dismissable)) {
          ui.closePanel(id);
        }
      });
      activePanels.push({ id, el: backdrop, mod });
      mod.mount(el, params);
      return true;
    },

    /** Close one panel by id (no-op when not open). @param {string} id */
    closePanel(id) {
      const i = activePanels.findIndex((p) => p.id === id);
      if (i < 0) return;
      const { el, mod } = activePanels[i];
      activePanels.splice(i, 1);
      try {
        mod.unmount();
      } catch (err) {
        console.error('[ui] panel unmount error:', err);
      }
      // POLISH-D: sheet slides down + backdrop fades before the element goes
      animateOut(el, 'panel-backdrop-out');
    },

    /** Close the active screen and every panel. */
    closeAll() {
      while (activePanels.length > 0) ui.closePanel(activePanels[activePanels.length - 1].id);
      if (activeScreen) {
        try {
          activeScreen.mod.unmount();
        } catch (err) {
          console.error('[ui] screen unmount error:', err);
        }
        // POLISH-D: fade/scale the leaving screen out (a replacement screen
        // mounted right after paints ABOVE it — later sibling, same z-index).
        animateOut(activeScreen.el, 'screen-out');
        activeScreen = null;
      }
    },

    /** @returns {string|null} id of the open full screen */
    activeScreenId() {
      return activeScreen?.id ?? null;
    },

    /**
     * Show a transient toast. Text goes through t() (§A: all user-facing text).
     * V3/FIX-D (E20 P1-1): held (queued, deduped) while the toast gate is
     * closed — see holdToasts()/releaseToasts().
     * @param {string} textKey strings.js key
     * @param {Record<string, string|number>} [vars]
     * @param {ToastOptions} [options]
     */
    toast(textKey, vars, options) {
      const text = t(textKey, vars);
      if (toastHold > 0) {
        holdToast(text, options);
        return;
      }
      spawnToast(text, options);
    },

    /**
     * V3/FIX-D (E20 P1-1): close the toast gate (re-entrant — one depth per
     * open modal). The FIRST hold also sweeps already-visible toasts into the
     * queue so a boot toast storm can't keep covering a panel that opened a
     * beat later (offline/achievement toasts race the whatsNew poll).
     */
    holdToasts() {
      toastHold += 1;
      if (toastHold > 1) return;
      for (const el of [...liveToasts]) {
        const text = el.textContent ?? '';
        if (text) holdToast(text, liveToastOptions.get(el));
        liveToasts.delete(el);
        el.remove();
      }
    },

    /**
     * V3/FIX-D (E20 P1-1): reopen the toast gate; when the last hold lifts,
     * flush the held toasts with a light stagger so they read one by one.
     */
    releaseToasts() {
      toastHold = Math.max(0, toastHold - 1);
      if (toastHold > 0) return;
      const pending = heldToasts.splice(0);
      pending.forEach((entry, i) => {
        setTimeout(() => {
          if (toastHold > 0) holdToast(entry.text, entry.options); // a new modal opened mid-flush
          else spawnToast(entry.text, entry.options);
        }, i * TOAST_FLUSH_STAGGER_MS);
      });
    },
  };

  registerCreditsScreen(ui); // V4/G81: static screen has no store dependency
  return ui;
}
