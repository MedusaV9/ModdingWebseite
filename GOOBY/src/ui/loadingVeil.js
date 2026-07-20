// V4/AC-3: reusable cozy LOADING VEIL — the cute transition INTO and OUT of
// minigames (and the shop/vet-trip return teleports). A full-screen cream
// curtain (AC-1's --pattern-leaf tile) with a centered cover-art card,
// bouncing Gooby motif, progress bar and rotating flavor tips; entry/exit is
// an iris (clip-path) wipe that degrades to a plain fade under
// prefers-reduced-motion.
//
// WHY: before AC-3 the IN loading card hid the moment a game's enter()
// resolved — textures/GLBs still streaming → visible pop-in — and the OUT
// paths (results → home, shopTrip returns) were a bare black fade with the
// same pop-in on the room. The veil fixes both by revealing ONLY when the
// target scene is really ready: hide() waits for the sceneManager's V4/AC-3
// afterEnter() hook (fires right after the next scene enter() resolves),
// then ≥ ENTER_SETTLE_FRAMES (2) animation frames + FADE_CLEAR_MS (the §E1
// 150 ms black fade underneath must lift first), and never reveals before
// minShownMs of total veil time. The 9999 black scene fade is NOT touched —
// headless screenshot determinism depends on its timer-stepped fade; the
// veil simply covers it at --z-loading (10000).
//
// NEVER DEADLOCKS: hide() force-reveals after HARD_TIMEOUT_MS even when the
// scene never settles, the 2-rAF settle is raced against a timer (rAF stalls
// in hidden tabs / virtual-time captures), and a show() watchdog force-hides
// after WATCHDOG_MS without progress activity if hide() never arrives —
// a stuck scene can never trap the player behind the curtain.
//
// MODES: 'game' (framework launches — the POLISH-D themed card is ADOPTED
// into the curtain via show({content}), so its cover/progress/motif markup
// keeps living in framework.js), 'home' (return to the house — cozy room
// art) and 'trip' (shop/vet travel — same art, travel lines). Strings:
// game mode reuses POLISH-D's v4-ui2.js tip keys (imported); home/trip
// lines live in strings/v4-acui-loading.js — both resolved through the
// local tx() fallback (G52 pattern; strings.js frozen per §E0.1-8). Every
// <img> gets an onerror-remove fallback (§G7.1 — a missing file never
// breaks the veil, the accent gradient stays).
//
// CSS is injected as <style data-owner="loadingveil"> from the VEIL_CSS
// template literal below — px-audit gates it (§B3: rem-only in the audited
// props). Pure helpers are exported for test/loadingVeil.test.js; importing
// this module under node is safe (no top-level DOM access).

import { t, getLang } from '../data/strings.js';
import { EN as ACUI_EN, DE as ACUI_DE } from '../data/strings/v4-acui-loading.js';
import { EN as UI2_EN, DE as UI2_DE } from '../data/strings/v4-ui2.js';

// ---------------------------------------------------------------------------
// Frozen tuning consts (§E0.1-2 — engine numbers live in the owning module)
// ---------------------------------------------------------------------------

export const VEIL = Object.freeze({
  /** Minimum total veil time — a flash-frame curtain reads as a glitch. */
  MIN_SHOWN_MS: 600,
  /** Animation frames to wait AFTER the target scene enter() resolved, so
   *  first-render asset pop-in happens behind the curtain (the AC-3 core). */
  ENTER_SETTLE_FRAMES: 2,
  /** Extra hold after enter() so the §E1 150 ms black fade fully lifts
   *  underneath — the reveal must never expose a half-black stage. */
  FADE_CLEAR_MS: 200,
  /** hide() hard ceiling: force-reveal even if the scene never settles. */
  HARD_TIMEOUT_MS: 8000,
  /** show() watchdog: force-hide when no hide()/progress activity arrives. */
  WATCHDOG_MS: 30000,
  /** Timer race for the rAF settle — rAF stalls in hidden/virtual-time tabs. */
  FRAME_FALLBACK_MS: 400,
  /** Rotating-tip cadence. */
  TIP_ROTATE_MS: 2600,
  /** Iris wipe durations (must match the VEIL_CSS keyframes below). */
  IRIS_IN_MS: 320,
  IRIS_OUT_MS: 340,
  /** hide() poll cadence while waiting for the scene switch to settle. */
  POLL_MS: 50,
});

// ---------------------------------------------------------------------------
// Pure helpers (exported for test/loadingVeil.test.js — keep them DOM-free)
// ---------------------------------------------------------------------------

/**
 * Canonical veil mode. Unknown/missing values degrade to the gentlest look
 * ('home') instead of throwing — a stale caller can never break a transition.
 * @param {string|undefined} mode
 * @returns {'game'|'home'|'trip'}
 */
export function normalizeVeilMode(mode) {
  return mode === 'game' || mode === 'trip' ? mode : 'home';
}

/**
 * Progress-bar percentage clamp: null keeps the intentional indeterminate
 * sweep (games without loadPct never show a frozen empty bar — POLISH-D rule).
 * @param {unknown} pct
 * @returns {number|null} 0 < pct ≤ 100, or null for "stay indeterminate"
 */
export function clampProgressPct(pct) {
  const n = Number(pct);
  if (!Number.isFinite(n) || n <= 0) return null;
  return Math.min(100, n);
}

/**
 * Earliest allowed reveal timestamp (the anti-pop-in contract, minus the
 * frame-settle part which needs a live rAF): the veil stays up for at least
 * minShownMs total AND until fadeClearMs after the target scene's enter()
 * resolved. enterAt 0 means "no scene switch involved" (teleport cutscene).
 * @param {number} shownAt show() timestamp (ms)
 * @param {number} minShownMs minimum total veil time
 * @param {number} enterAt enter()-resolved timestamp (0 = none)
 * @param {number} fadeClearMs §E1 fade allowance after enterAt
 * @returns {number} timestamp before which reveal must not start
 */
export function revealNotBefore(shownAt, minShownMs, enterAt, fadeClearMs) {
  const base = (Number(shownAt) || 0) + Math.max(0, Number(minShownMs) || 0);
  const entered = Number(enterAt) || 0;
  const settled = entered > 0 ? entered + Math.max(0, Number(fadeClearMs) || 0) : 0;
  return Math.max(base, settled);
}

/**
 * Rotating-tip index step (wraps; hostile counters land on 0).
 * @param {number} index current tip index
 * @param {number} count tip count (≥ 1)
 * @returns {number} next index in [0, count)
 */
export function nextTipIndex(index, count) {
  const c = Math.max(1, Math.floor(Number(count) || 1));
  const i = Math.floor(Number(index) || 0) + 1;
  return ((i % c) + c) % c;
}

/**
 * Per-mode string keys. Game mode reuses POLISH-D's v4-ui2.js keys (titleKey
 * null — the framework card carries the game's own title); home/trip use the
 * v4-acui-loading.js lines.
 * @param {'game'|'home'|'trip'} mode
 * @returns {{titleKey: string|null, readyKey: string, labelKey: string,
 *   tipKeys: string[]}}
 */
export function veilStrings(mode) {
  const m = normalizeVeilMode(mode);
  if (m === 'game') {
    return {
      titleKey: null,
      readyKey: 'ui2.loading.getReady',
      labelKey: 'acui.loading.label',
      tipKeys: ['ui2.loading.tip1', 'ui2.loading.tip2', 'ui2.loading.tip3'],
    };
  }
  if (m === 'trip') {
    return {
      titleKey: 'acui.loading.tripTitle',
      readyKey: 'acui.loading.tripReady',
      labelKey: 'acui.loading.label',
      tipKeys: ['acui.loading.tipTrip1', 'acui.loading.tipTrip2', 'acui.loading.tipTrip3'],
    };
  }
  return {
    titleKey: 'acui.loading.homeTitle',
    readyKey: 'acui.loading.homeReady',
    labelKey: 'acui.loading.label',
    tipKeys: ['acui.loading.tipHome1', 'acui.loading.tipHome2', 'acui.loading.tipHome3'],
  };
}

/**
 * Per-mode veil art (relative URLs like every other UI asset). Game mode's
 * cover comes from the caller's meta (coverUrl helper in framework.js) —
 * only the motif has a default here.
 * @param {'game'|'home'|'trip'} mode
 * @returns {{cover: string|null, motif: string}}
 */
export function veilArt(mode) {
  const m = normalizeVeilMode(mode);
  if (m === 'game') {
    return { cover: null, motif: 'assets/ui/gooby_loading_motif.png' };
  }
  return { cover: 'assets/acui/veil_home_cover.png', motif: 'assets/acui/motif_gooby_wave.png' };
}

// ---------------------------------------------------------------------------
// Injected CSS (px-audit gated — §B3 rem-only in the checked props)
// ---------------------------------------------------------------------------

const VEIL_CSS = `
.acui-veil {
  position: fixed;
  inset: 0;
  z-index: var(--z-loading);
  background: var(--pattern-leaf) left top / 24rem 24rem repeat var(--paper, #fffaf2);
  pointer-events: auto; /* swallow blind taps while the curtain covers */
  clip-path: circle(141% at 50% 44%);
}
.acui-veil.acui-veil-in {
  animation: acui-veil-iris-in 320ms ease-out both;
}
.acui-veil.acui-veil-out {
  animation: acui-veil-iris-out 340ms ease-in both;
  pointer-events: none;
}
@keyframes acui-veil-iris-in {
  from { clip-path: circle(0% at 50% 44%); }
  to { clip-path: circle(141% at 50% 44%); }
}
@keyframes acui-veil-iris-out {
  from { clip-path: circle(141% at 50% 44%); }
  to { clip-path: circle(0% at 50% 44%); }
}
/* the adopted/self-built POLISH-D card wrapper centers INSIDE the veil —
   absolute (not its own fixed layer) so the iris clip carries it along */
.acui-veil .mg-loading {
  position: absolute;
  inset: 0;
}
/* bouncing Gooby motif — a springier bounce than POLISH-D's gentle bob
   while the sticker lives inside the veil */
.acui-veil .mg-loading-motif {
  animation: acui-veil-bounce 1.3s cubic-bezier(0.45, 0, 0.55, 1) infinite;
}
@keyframes acui-veil-bounce {
  0%, 100% { transform: translateY(0) scale(1, 1); }
  32% { transform: translateY(-0.75rem) scale(0.94, 1.08); }
  52% { transform: translateY(0.0625rem) scale(1.08, 0.9); }
  70% { transform: translateY(-0.3125rem) scale(0.98, 1.03); }
  84% { transform: translateY(0) scale(1.02, 0.98); }
}
/* rotating tips cross-fade */
.acui-veil .mg-loading-tip {
  transition: opacity 200ms ease;
}
/* cozy mode accents on the ready line */
.acui-veil[data-mode='home'] .mg-loading-ready::before { content: '🏡 '; }
.acui-veil[data-mode='trip'] .mg-loading-ready::before { content: '🧳 '; }
/* reduced motion: plain fade instead of the iris, decorative loops off */
@media (prefers-reduced-motion: reduce) {
  .acui-veil.acui-veil-in { animation: acui-veil-fade-in 160ms ease-out both; }
  .acui-veil.acui-veil-out { animation: acui-veil-fade-out 160ms ease-out both; }
  .acui-veil .mg-loading-motif { animation: none; }
  .acui-veil .mg-loading-tip { transition: none; }
}
@keyframes acui-veil-fade-in {
  from { opacity: 0; }
  to { opacity: 1; }
}
@keyframes acui-veil-fade-out {
  from { opacity: 1; }
  to { opacity: 0; }
}
`;

// ---------------------------------------------------------------------------
// Runtime state (module singleton — one veil per app, like the scene fade)
// ---------------------------------------------------------------------------

/** @type {{sceneManager: {afterEnter?: Function, isSwitching?: Function}|null}} */
const deps = { sceneManager: null };

/**
 * Wire the veil's sceneManager handle (idempotent — the framework and the
 * shop-trip flow both call this with the same instance at boot).
 * @param {{sceneManager: object}} wiring
 */
export function initLoadingVeil({ sceneManager } = {}) {
  if (sceneManager) deps.sceneManager = sceneManager;
}

/** @type {HTMLElement|null} */
let el = null;
/** @type {'game'|'home'|'trip'} */
let mode = 'home';
let shownAt = 0;
/** Timestamp the target scene's enter() resolved (0 = not yet / none). */
let enterAt = 0;
/** Supersede token: a newer show() invalidates pending hide/afterEnter work. */
let token = 0;
let tipTimer = 0;
let watchdogTimer = 0;
let lastActivityAt = 0;
/** @type {number|null} */
let lastPct = null;
/** @type {Promise<void>|null} */
let hidePromise = null;
/** @type {Promise<void>|null} resolves once the entry wipe fully covers */
let coveredPromise = null;

const nowMs = () => (typeof performance !== 'undefined' ? performance.now() : Date.now());
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, Math.max(0, ms)));

/**
 * Same-wave i18n fallback (the G52 tx pattern — strings.js stays frozen per
 * §E0.1-8): t() → v4-acui-loading → v4-ui2 module dictionaries.
 * @param {string} key
 * @returns {string}
 */
function tx(key) {
  const global = t(key);
  if (global !== key) return global;
  const de = getLang() === 'de';
  return (de ? ACUI_DE : ACUI_EN)[key] ?? (de ? UI2_DE : UI2_EN)[key] ?? key;
}

/** Inject the veil stylesheet once (idempotent, node-safe). */
function ensureStyles() {
  if (document.querySelector('style[data-owner="loadingveil"]')) return;
  const style = document.createElement('style');
  style.dataset.owner = 'loadingveil';
  style.textContent = VEIL_CSS;
  document.head.appendChild(style);
}

/**
 * Wait n animation frames, raced against a timer — rAF stalls in hidden tabs
 * and virtual-time captures, and the veil must NEVER deadlock on it.
 * @param {number} n
 * @returns {Promise<void>}
 */
function settleFrames(n) {
  return new Promise((resolve) => {
    let done = false;
    const finish = () => {
      if (!done) {
        done = true;
        resolve();
      }
    };
    setTimeout(finish, VEIL.FRAME_FALLBACK_MS);
    if (typeof requestAnimationFrame !== 'function') return finish();
    let left = Math.max(1, Math.floor(n) || 1);
    const step = () => {
      left -= 1;
      if (left <= 0) finish();
      else requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  });
}

/**
 * Build a themed card for the self-drawn modes (home/trip and the pre-switch
 * game placeholder). Reuses the POLISH-D .mg-loading-* classes so the look
 * matches the framework's adopted card 1:1. Every <img> follows the §G7.1
 * onerror-remove rule.
 * @param {'game'|'home'|'trip'} m
 * @param {{cover?: string, gradient?: string, title?: string}} [meta]
 * @returns {HTMLElement}
 */
function buildCard(m, meta = {}) {
  const s = veilStrings(m);
  const art = veilArt(m);
  const host = document.createElement('div');
  host.className = 'mg-loading mg-loading-themed';
  host.innerHTML = `
    <div class="mg-loading-card">
      <div class="mg-loading-cover">
        <img class="mg-loading-cover-img" alt="" decoding="async">
        <div class="mg-loading-cover-shade"></div>
        <div class="mg-loading-ready"></div>
        <img class="mg-loading-motif" alt="" decoding="async">
      </div>
      <div class="mg-loading-body">
        <div class="mg-loading-title"></div>
        <div class="mg-loading-bar mg-loading-bar-indet"
          role="progressbar" aria-valuemin="0" aria-valuemax="100">
          <div class="mg-loading-bar-fill"></div>
        </div>
        <div class="mg-loading-text">${tx(s.labelKey)} <span data-pct></span></div>
        <div class="mg-loading-tip"></div>
      </div>
    </div>`;
  host.querySelector('.mg-loading-cover').style.background =
    meta.gradient || 'linear-gradient(155deg, #fff6ec 0%, #ffe9c7 58%, #e8c896 100%)';
  const coverImgEl = host.querySelector('.mg-loading-cover-img');
  coverImgEl.addEventListener('error', () => coverImgEl.remove());
  const coverSrc = meta.cover || art.cover;
  if (coverSrc) coverImgEl.src = coverSrc;
  else coverImgEl.remove();
  const motifEl = host.querySelector('.mg-loading-motif');
  motifEl.addEventListener('error', () => motifEl.remove());
  motifEl.src = art.motif;
  host.querySelector('.mg-loading-ready').textContent = tx(s.readyKey);
  host.querySelector('.mg-loading-title').textContent =
    meta.title || (s.titleKey ? tx(s.titleKey) : '');
  const tipEl = host.querySelector('.mg-loading-tip');
  tipEl.textContent = tx(s.tipKeys[Math.floor(Math.random() * s.tipKeys.length)]);
  return host;
}

/** Swap the veil's card (adoption replaces the placeholder in place). */
function setCard(node) {
  if (!el) return;
  for (const old of el.querySelectorAll(':scope > .mg-loading')) old.remove();
  el.appendChild(node);
}

/** Register a one-shot enter listener for THIS show (token-guarded). */
function armEnterHook() {
  const myToken = token;
  const sm = deps.sceneManager;
  if (typeof sm?.afterEnter !== 'function') return;
  sm.afterEnter(() => {
    if (token === myToken) enterAt = nowMs();
  });
}

/** Rotating tips: cross-fade to the next mode tip every TIP_ROTATE_MS. */
function startTips() {
  clearInterval(tipTimer);
  const myToken = token;
  const keys = veilStrings(mode).tipKeys;
  let index = Math.floor(Math.random() * keys.length);
  tipTimer = setInterval(() => {
    if (token !== myToken || !el) {
      clearInterval(tipTimer);
      return;
    }
    const tipEl = el.querySelector('.mg-loading-tip');
    if (!tipEl) return;
    index = nextTipIndex(index, keys.length);
    const text = tx(keys[index]);
    tipEl.style.opacity = '0';
    setTimeout(() => {
      if (token !== myToken || !tipEl.isConnected) return;
      tipEl.textContent = text;
      tipEl.style.opacity = '1';
    }, 200);
  }, VEIL.TIP_ROTATE_MS);
}

/** show() watchdog: force-hide when hide()/progress never arrives. */
function armWatchdog() {
  clearInterval(watchdogTimer);
  const myToken = token;
  watchdogTimer = setInterval(() => {
    if (token !== myToken || !el) {
      clearInterval(watchdogTimer);
      return;
    }
    if (hidePromise) return; // a hide is in flight — its own hard timeout rules
    if (nowMs() - lastActivityAt > VEIL.WATCHDOG_MS) {
      console.warn(`[loadingVeil] watchdog: no hide() after ${VEIL.WATCHDOG_MS} ms — force-revealing`);
      hide({ minShownMs: 0 });
    }
  }, 1000);
}

/** Iris the veil out and drop it (animationend raced with a timer). */
function reveal(myToken) {
  return new Promise((resolve) => {
    if (token !== myToken || !el) return resolve();
    const node = el;
    el = null;
    hidePromise = null;
    coveredPromise = null;
    clearInterval(tipTimer);
    clearInterval(watchdogTimer);
    let done = false;
    const finish = () => {
      if (done) return;
      done = true;
      node.remove();
      resolve();
    };
    node.classList.remove('acui-veil-in');
    node.classList.add('acui-veil-out');
    // animationend BUBBLES from card children — only the root wipe counts
    node.addEventListener('animationend', (e) => {
      if (e.target === node) finish();
    });
    setTimeout(finish, VEIL.IRIS_OUT_MS + 150);
  });
}

/**
 * Show the veil (idempotent / re-entrant):
 *  - fresh: iris-in the curtain with a mode card (or the caller's `content`).
 *  - same mode while covering: swap the card in place (the framework adopting
 *    its POLISH-D card over the launch placeholder) — the transition timing
 *    keeps running; if a scene switch is in flight the enter hook re-arms so
 *    the reveal waits for THAT enter (launch-retry races).
 *  - different mode while covering: repurpose the curtain (failed init →
 *    home) with fresh timing.
 * @param {{mode?: 'game'|'home'|'trip', meta?: {cover?: string,
 *   gradient?: string, title?: string}, content?: HTMLElement|null}} [opts]
 * @returns {Promise<void>} resolves once the curtain fully covers the screen
 */
export function show({ mode: requested = 'game', meta = {}, content = null } = {}) {
  if (typeof document === 'undefined') return Promise.resolve();
  const nextMode = normalizeVeilMode(requested);
  ensureStyles();
  if (el && nextMode === mode) {
    if (content) setCard(content);
    if (deps.sceneManager?.isSwitching?.() === true) {
      // a switch is (still) in flight — the reveal must wait for ITS enter,
      // not a stale one from a previous switch (launch-retry race)
      enterAt = 0;
      armEnterHook();
    }
    lastActivityAt = nowMs();
    return coveredPromise ?? Promise.resolve();
  }
  if (el && nextMode !== mode) {
    // repurpose the covering curtain with fresh timing + card
    mode = nextMode;
    token += 1;
    shownAt = nowMs();
    enterAt = 0;
    lastActivityAt = shownAt;
    lastPct = null;
    hidePromise = null;
    el.dataset.mode = nextMode;
    setCard(content ?? buildCard(nextMode, meta));
    armEnterHook();
    armWatchdog();
    startTips();
    return coveredPromise ?? Promise.resolve();
  }
  // fresh show
  mode = nextMode;
  token += 1;
  shownAt = nowMs();
  enterAt = 0;
  lastActivityAt = shownAt;
  lastPct = null;
  hidePromise = null;
  el = document.createElement('div');
  el.className = 'acui-veil acui-veil-in';
  el.dataset.mode = nextMode;
  setCard(content ?? buildCard(nextMode, meta));
  document.body.appendChild(el);
  const node = el;
  coveredPromise = new Promise((resolve) => {
    let done = false;
    const finish = () => {
      if (!done) {
        done = true;
        resolve();
      }
    };
    // animationend BUBBLES from card children — only the root wipe counts
    node.addEventListener('animationend', (e) => {
      if (e.target === node) finish();
    });
    setTimeout(finish, VEIL.IRIS_IN_MS + 150);
  });
  armEnterHook();
  armWatchdog();
  startTips();
  return coveredPromise;
}

/**
 * Feed the determinate progress bar (0–100). Non-finite/≤0 values keep the
 * intentional indeterminate sweep. Also counts as watchdog activity — a
 * slowly-streaming goobyWelt load is progress, not a stall.
 * @param {unknown} pct
 */
export function progress(pct) {
  if (!el) return;
  const clamped = clampProgressPct(pct);
  if (clamped == null) return;
  if (clamped !== lastPct) {
    lastPct = clamped;
    lastActivityAt = nowMs();
  }
  const bar = el.querySelector('.mg-loading-bar');
  const fill = el.querySelector('.mg-loading-bar-fill');
  if (!bar || !fill) return;
  bar.classList.remove('mg-loading-bar-indet');
  bar.setAttribute('aria-valuenow', String(Math.round(clamped)));
  fill.style.width = `${clamped}%`;
  const pctEl = el.querySelector('[data-pct]');
  if (pctEl) pctEl.textContent = `${Math.round(clamped)}%`;
}

/**
 * Request the reveal. The veil comes down only when it is SAFE:
 *  1. total veil time ≥ minShownMs,
 *  2. if a scene switch is involved: the target scene's enter() resolved
 *     (V4/AC-3 afterEnter hook) + ENTER_SETTLE_FRAMES animation frames +
 *     FADE_CLEAR_MS (the §E1 black fade lifts underneath),
 *  3. hard ceiling HARD_TIMEOUT_MS — a stuck scene never traps the player.
 * Re-entrant: repeat calls share the same pending promise.
 * @param {{minShownMs?: number}} [opts]
 * @returns {Promise<void>} resolves once the curtain is fully gone
 */
export function hide({ minShownMs = VEIL.MIN_SHOWN_MS } = {}) {
  if (typeof document === 'undefined' || !el) return Promise.resolve();
  if (hidePromise) return hidePromise;
  const myToken = token;
  hidePromise = (async () => {
    const hardAt = nowMs() + VEIL.HARD_TIMEOUT_MS;
    await sleep(revealNotBefore(shownAt, minShownMs, 0, 0) - nowMs());
    while (token === myToken && nowMs() < hardAt) {
      if (enterAt > 0) {
        // scene ready — settle frames so the first real render (textures,
        // GLBs, splats) happens behind the curtain…
        await settleFrames(VEIL.ENTER_SETTLE_FRAMES);
        // …then let the §E1 black fade underneath fully lift: switchTo
        // flips isSwitching false right after its timer-stepped fadeTo(0)
        // resolves (slow devices stretch the 150 ms — poll, hard-capped),
        // with FADE_CLEAR_MS as an additional floor after enter.
        while (nowMs() < hardAt && token === myToken
          && deps.sceneManager?.isSwitching?.() === true) {
          await sleep(VEIL.POLL_MS);
        }
        await sleep(revealNotBefore(0, 0, enterAt, VEIL.FADE_CLEAR_MS) - nowMs());
        break;
      }
      if (deps.sceneManager?.isSwitching?.() !== true) break; // nothing pending (teleport / standalone)
      await sleep(VEIL.POLL_MS);
    }
    if (token !== myToken) return; // superseded by a newer show()
    await reveal(myToken);
  })();
  return hidePromise;
}

/** @returns {boolean} whether the veil is currently on screen */
export function isShown() {
  return el != null;
}

/** The AC-3 veil API (show/progress/hide/isShown) as one handle. */
export const veil = { show, progress, hide, isShown };
