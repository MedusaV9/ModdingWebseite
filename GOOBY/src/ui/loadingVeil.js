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
//
// V6/F2 — PETAL WIPE: home↔scene transitions now default to a petal/leaf
// sweep instead of the circle iris: the curtain edge becomes a slanted
// left→right clip-path sweep (450 ms, same show/hide API and reveal-safety
// windows) and a transient full-screen canvas stamps 2 pre-painted petal
// sprites (rotating, swaying) along the moving frontier so the seam reads as
// a drift of petals. The iris keyframes REMAIN as the no-canvas fallback
// (veilWipeVariant), and prefers-reduced-motion keeps the plain fade exactly
// as before (the petal class is never added, and the CSS media block also
// overrides it as belt-and-braces). The petal field/pose math is pure and
// exported (petalField/petalStampPose — test/ambientVisitors.test.js).
// DEV capture aid: `?veilslow=N` (DEV builds only) multiplies the wipe +
// canvas durations so a mid-transition frame can be screenshotted; guarded
// by import.meta.env.DEV, inert in production.

import { t, getLang } from '../data/strings.js';
import { prefersReducedMotion } from './ui.js'; // V6/F2: petal variant gate
import { iconTinted, stripRawGlyphs } from './icons.js'; // V6/D3: authored ready-line accents + label glyph strip
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
// V6/F2: petal wipe tuning + pure math (exported, node-tested)
// ---------------------------------------------------------------------------

export const PETAL = Object.freeze({
  /** Sweep duration (must match the acui-veil-sweep-* keyframes below).
   *  Fits inside both reveal fallback windows: IRIS_IN_MS/IRIS_OUT_MS + 150. */
  WIPE_MS: 450,
  /** Stamped petals per wipe. */
  COUNT: 26,
  /** Frontier slant (top edge leads — matches the sweep clip polygons). */
  SLANT: 0.15,
  /** Stamp size range (fraction of the viewport's shorter side). */
  SIZE_MIN: 0.035,
  SIZE_MAX: 0.06,
});

/**
 * Which wipe a veil transition uses (V6/F2 variant selection — same call
 * sites, the choice lives entirely inside this module):
 *  - reduced motion → the plain fade (CSS media block does it; the petal
 *    class is simply never added);
 *  - no 2D canvas (headless edge cases) → the classic circle iris;
 *  - otherwise → the petal sweep, for every home↔scene transition the veil
 *    covers (game launches included — they are home→minigame switches).
 * @param {'game'|'home'|'trip'} mode veil mode (kept for future per-mode art)
 * @param {{reducedMotion?: boolean, canvasOk?: boolean}} [env]
 * @returns {'fade'|'iris'|'petal'}
 */
export function veilWipeVariant(mode, { reducedMotion = false, canvasOk = true } = {}) {
  normalizeVeilMode(mode); // canonicalize (junk modes still pick a variant)
  if (reducedMotion) return 'fade';
  if (!canvasOk) return 'iris';
  return 'petal';
}

/**
 * Deterministic petal descriptor field (tiny LCG — same seed, same drift on
 * every run/device; no Math.random so tests can pin it).
 * @param {number} [count]
 * @param {number} [seed]
 * @returns {Array<{lane: number, ahead: number, size: number, spin: number,
 *   phase: number, sway: number, sprite: 0|1}>}
 */
export function petalField(count = PETAL.COUNT, seed = 7) {
  let s = (Math.floor(Number(seed)) >>> 0) || 1;
  const rand = () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 4294967296;
  };
  const n = Math.max(1, Math.floor(Number(count)) || 1);
  const petals = [];
  for (let i = 0; i < n; i += 1) {
    petals.push({
      /** vertical lane 0..1 — even spread + jitter so no row gaps */
      lane: Math.min(1, (i + rand() * 0.9) / n),
      /** signed offset from the frontier (some lead, some trail) */
      ahead: (rand() - 0.35) * 0.16,
      size: PETAL.SIZE_MIN + rand() * (PETAL.SIZE_MAX - PETAL.SIZE_MIN),
      /** radians of rotation across the whole sweep */
      spin: (rand() - 0.5) * 9,
      phase: rand() * Math.PI * 2,
      sway: 0.02 + rand() * 0.03,
      /** sprite index: mostly pink petals, some green leaves */
      sprite: rand() < 0.72 ? 0 : 1,
    });
  }
  return petals;
}

/**
 * Pose of one petal stamp at sweep progress u ∈ [0,1] (pure): position in
 * viewport fractions, rotation in radians, alpha fading at both wipe ends so
 * stamps never pop. The frontier sweeps left→right with the top edge leading
 * by PETAL.SLANT — the same slant the sweep clip polygons use.
 * @param {ReturnType<typeof petalField>[number]} petal
 * @param {number} u 0..1 sweep progress
 * @returns {{x: number, y: number, rot: number, alpha: number}}
 */
export function petalStampPose(petal, u) {
  const k = Math.max(0, Math.min(1, Number(u) || 0));
  const frontier = -0.25 + k * 1.45 + PETAL.SLANT * (1 - petal.lane);
  return {
    x: frontier + petal.ahead + Math.sin(k * Math.PI * 2 + petal.phase) * petal.sway,
    y: petal.lane + Math.sin(k * Math.PI * 3 + petal.phase) * petal.sway * 0.6,
    rot: petal.phase + k * petal.spin,
    alpha: Math.max(0, Math.min(1, Math.min(k, 1 - k) * 6)),
  };
}

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
/* V6/F2: petal-sweep variant (default for home↔scene transitions — the
   veilWipeVariant selection). The curtain edge is a slanted left→right
   sweep; the petal stamps ride a separate .acui-veil-petals canvas so they
   can lead AHEAD of the clip edge. 450 ms = PETAL.WIPE_MS. */
.acui-veil.acui-veil-petal.acui-veil-in {
  animation: acui-veil-sweep-in 450ms ease-out both;
}
.acui-veil.acui-veil-petal.acui-veil-out {
  animation: acui-veil-sweep-out 450ms ease-in both;
  pointer-events: none;
}
@keyframes acui-veil-sweep-in {
  from { clip-path: polygon(0 0, 0% 0, -15% 100%, 0 100%); }
  to { clip-path: polygon(0 0, 115% 0, 100% 100%, 0 100%); }
}
@keyframes acui-veil-sweep-out {
  from { clip-path: polygon(0% 0, 100% 0, 100% 100%, -15% 100%); }
  to { clip-path: polygon(115% 0, 100% 0, 100% 100%, 100% 100%); }
}
.acui-veil-petals {
  position: fixed;
  inset: 0;
  z-index: calc(var(--z-loading) + 1);
  pointer-events: none;
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
/* cozy mode accents on the ready line — V6/D3: authored SVG (data-URI
   background; pseudo-elements have no cascade for inline SVG markup, and the
   ready line is white-on-photo so the tint is baked into the URI). */
.acui-veil .mg-loading-ready::before {
  content: '';
  display: inline-block;
  width: 1.1em;
  height: 1.1em;
  margin-right: 0.375em;
  vertical-align: -0.2em;
  background: center / contain no-repeat;
}
.acui-veil[data-mode='home'] .mg-loading-ready::before { background-image: url("data:image/svg+xml,${encodeURIComponent(iconTinted('cottage', 24, '#FFFFFF'))}"); }
.acui-veil[data-mode='trip'] .mg-loading-ready::before { background-image: url("data:image/svg+xml,${encodeURIComponent(iconTinted('suitcase', 24, '#FFFFFF'))}"); }
/* reduced motion: plain fade instead of the iris, decorative loops off.
   V6/F2: the petal selectors are repeated so the fade outranks the sweep
   even if the petal class were ever present (JS never adds it under
   reduced motion — this is belt-and-braces specificity). */
@media (prefers-reduced-motion: reduce) {
  .acui-veil.acui-veil-in,
  .acui-veil.acui-veil-petal.acui-veil-in { animation: acui-veil-fade-in 160ms ease-out both; }
  .acui-veil.acui-veil-out,
  .acui-veil.acui-veil-petal.acui-veil-out { animation: acui-veil-fade-out 160ms ease-out both; }
  .acui-veil .mg-loading-motif { animation: none; }
  .acui-veil .mg-loading-tip { transition: none; }
  .acui-veil-petals { display: none; }
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

// ---------------------------------------------------------------------------
// V6/F2: petal wipe runtime (canvas stamps along the sweep frontier)
// ---------------------------------------------------------------------------

/**
 * DEV-only capture aid: `?veilslow=N` multiplies the wipe + canvas durations
 * (clamped 1–20) so a mid-transition frame can be screenshotted reliably.
 * Guarded by import.meta.env.DEV — production builds always return 1.
 * @returns {number}
 */
function devWipeSlow() {
  if (!import.meta.env?.DEV) return 1;
  if (typeof location === 'undefined') return 1;
  const n = Number(new URLSearchParams(location.search).get('veilslow'));
  return Number.isFinite(n) && n > 1 ? Math.min(20, n) : 1;
}

/** Soft pink sakura petal (teardrop with a tip notch), pre-painted once. */
function paintPetalSprite(g, s) {
  const grad = g.createRadialGradient(s * 0.42, s * 0.4, s * 0.06, s * 0.5, s * 0.5, s * 0.52);
  grad.addColorStop(0, '#FFE1EB');
  grad.addColorStop(0.6, '#FFB9D0');
  grad.addColorStop(1, '#FF9EC0');
  g.fillStyle = grad;
  g.beginPath();
  g.moveTo(s * 0.5, s * 0.06); // stem tip
  g.bezierCurveTo(s * 0.92, s * 0.2, s * 0.94, s * 0.66, s * 0.62, s * 0.9);
  g.quadraticCurveTo(s * 0.5, s * 0.8, s * 0.38, s * 0.9); // tip notch
  g.bezierCurveTo(s * 0.06, s * 0.66, s * 0.08, s * 0.2, s * 0.5, s * 0.06);
  g.closePath();
  g.fill();
  g.strokeStyle = 'rgba(232,101,146,0.55)';
  g.lineWidth = s * 0.03;
  g.stroke();
}

/** Small fresh-green leaf with a center vein, pre-painted once. */
function paintLeafSprite(g, s) {
  const grad = g.createLinearGradient(s * 0.2, s * 0.2, s * 0.8, s * 0.85);
  grad.addColorStop(0, '#C9E9AE');
  grad.addColorStop(1, '#8CC978');
  g.fillStyle = grad;
  g.beginPath();
  g.moveTo(s * 0.5, s * 0.08);
  g.quadraticCurveTo(s * 0.94, s * 0.36, s * 0.5, s * 0.92);
  g.quadraticCurveTo(s * 0.06, s * 0.36, s * 0.5, s * 0.08);
  g.closePath();
  g.fill();
  g.strokeStyle = 'rgba(106,152,86,0.7)';
  g.lineWidth = s * 0.035;
  g.beginPath();
  g.moveTo(s * 0.5, s * 0.14);
  g.quadraticCurveTo(s * 0.56, s * 0.5, s * 0.5, s * 0.86);
  g.stroke();
}

/** @type {HTMLCanvasElement[]|null} the 2 pre-painted petal sprites */
let petalSprites = null;

/** Paint the 2 stamp sprites once per app (64 px offscreen canvases). */
function getPetalSprites() {
  if (petalSprites) return petalSprites;
  const S = 64;
  petalSprites = [paintPetalSprite, paintLeafSprite].map((paint) => {
    const c = document.createElement('canvas');
    c.width = c.height = S;
    const g = c.getContext('2d');
    if (g) paint(g, S);
    return c;
  });
  return petalSprites;
}

/**
 * Run one petal sweep on a transient full-screen canvas (self-removing).
 * Purely decorative: the clip-path sweep on the veil root is the functional
 * wipe — if rAF stalls (hidden tab) the safety timeout just removes the
 * canvas and the transition still completes via the root's own timers.
 * @param {number} durMs sweep duration (PETAL.WIPE_MS × DEV slowdown)
 */
function runPetalCanvas(durMs) {
  const canvas = document.createElement('canvas');
  canvas.className = 'acui-veil-petals';
  const g = canvas.getContext('2d');
  if (!g) return; // no 2D context → the clip sweep alone carries the wipe
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  const w = innerWidth;
  const h = innerHeight;
  canvas.width = Math.max(1, Math.round(w * dpr));
  canvas.height = Math.max(1, Math.round(h * dpr));
  g.scale(dpr, dpr);
  document.body.appendChild(canvas);
  const petals = petalField();
  const sprites = getPetalSprites();
  const unit = Math.min(w, h);
  const start = nowMs();
  let raf = 0;
  const cleanup = () => {
    cancelAnimationFrame(raf);
    canvas.remove();
  };
  const safety = setTimeout(cleanup, durMs + 500);
  const frame = () => {
    const u = (nowMs() - start) / durMs;
    if (u >= 1 || !canvas.isConnected) {
      clearTimeout(safety);
      cleanup();
      return;
    }
    g.clearRect(0, 0, w, h);
    for (const petal of petals) {
      const pose = petalStampPose(petal, u);
      if (pose.alpha <= 0) continue;
      const size = petal.size * unit;
      g.save();
      g.globalAlpha = pose.alpha;
      g.translate(pose.x * w, pose.y * h);
      g.rotate(pose.rot);
      g.drawImage(sprites[petal.sprite], -size / 2, -size / 2, size, size);
      g.restore();
    }
    raf = requestAnimationFrame(frame);
  };
  raf = requestAnimationFrame(frame);
}

/**
 * Apply the selected wipe variant to a veil root for one transition leg:
 * adds/removes the petal class, sets the DEV-slowed duration and launches
 * the stamp canvas. Fade (reduced motion) and iris need no extra work —
 * the base CSS handles them.
 * @param {HTMLElement} node veil root
 * @returns {number} the wipe's duration multiplier (DEV slowdown, ≥1)
 */
function applyWipeVariant(node) {
  const variant = veilWipeVariant(mode, {
    reducedMotion: prefersReducedMotion(),
    canvasOk: typeof document.createElement('canvas').getContext === 'function',
  });
  const slow = devWipeSlow();
  if (variant !== 'petal') {
    node.classList.remove('acui-veil-petal');
    return 1;
  }
  node.classList.add('acui-veil-petal');
  if (slow > 1) node.style.animationDuration = `${PETAL.WIPE_MS * slow}ms`;
  runPetalCanvas(PETAL.WIPE_MS * slow);
  return slow;
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
        <div class="mg-loading-text">${stripRawGlyphs(tx(s.labelKey))} <span data-pct></span></div>
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
    // V6/F2: re-apply the wipe variant for the OUT leg (petal sweep +
    // stamp canvas; iris/fade need nothing). slow > 1 only in DEV captures.
    const slow = applyWipeVariant(node);
    // animationend BUBBLES from card children — only the root wipe counts
    node.addEventListener('animationend', (e) => {
      if (e.target === node) finish();
    });
    // fallback covers the LONGER of the iris/petal wipes (× DEV slowdown)
    setTimeout(finish, (Math.max(VEIL.IRIS_OUT_MS, PETAL.WIPE_MS) + 150) * slow);
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
  // V6/F2: pick the wipe for the IN leg (petal sweep default; iris/fade
  // fallbacks) and launch the stamp canvas alongside the clip animation.
  const slowIn = applyWipeVariant(node);
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
    // fallback covers the LONGER of the iris/petal wipes (× DEV slowdown)
    setTimeout(finish, (Math.max(VEIL.IRIS_IN_MS, PETAL.WIPE_MS) + 150) * slowIn);
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
