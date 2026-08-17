// V4/G64 — Level-up recap cinematic player (PLAN4 §E block G64 + §C-SYS2) —
// the DOM/audio DRIVER half. All timing/selection math lives in
// recapOverlay.logic.js (node-tested); this module owns:
//   · the fullscreen takeover overlay (400 ms white-fade entry, HUD hidden,
//     input limited to the skip affordance — §C-SYS2.1),
//   · the recap track on a DEDICATED MediaElement (radio ducked via
//     radioPlayer.duck(true,'recap'), medley via musicDirector.setSuppressed
//     — the §C-SYS1 suppressor contract; element volume replicates the §B2.2
//     bus math and live-follows the sliders + the airtight music mute),
//   · cue consumption of G55's recapDirector.buildTimeline() output: intro
//     title card → 8 even-bar vignette cuts → beat-synced stat-text pops
//     (pop 0.8→1.05→1.0 over 2 beats + counter roll-up, EN+DE) → end card
//     („Level X!" ring + coin recap + next unlock + confetti + Weiter),
//   · the §C-SYS2.2 skip affordance (subtle, from t = 10 s, 300 ms cut),
//   · G63's 3D vignettes (src/recap/vignettes.js, feature-detected via glob;
//     scene id 'recap' registers when present) with a colored-backdrop DOM
//     fallback so this module ships independently,
//   · the §B5.2 atomic completion write (completeRecap in ONE store.update —
//     the ONLY path that clears recap.pendingLevel),
//   · trigger wiring: pendingLevel → plays on the NEXT home enter (poll +
//     'recapChanged'; never mid-gameplay — canAutoStart guard),
//   · dev-panel card 15 playback (previewRecap/replayRecap — G58's probe
//     shape) and the beat-debug overlay honoring G58's exported toggle
//     (getRecapBeatDebug + 'recapBeatDebugChanged').
//
// Clock rule (§C-SYS2.6): the rAF wall clock re-anchors to el.currentTime on
// every bar crossing (advanceClock — ±80 ms §A2). No-audio contexts (VM/
// muted/autoplay-refused) run the same timeline on the wall clock.

import { RECAP, selectLines, diff, completeRecap } from '../systems/recap.js';
import { buildTimeline } from '../systems/recapDirector.js';
import { getTracks, trackById } from '../systems/musicRegistry.js';
import radioPlayer, { trackUrl } from '../audio/radioPlayer.js';
import musicDirector from '../audio/musicDirector.js';
import { nextUnlock } from '../systems/leveling.js';
import { burstConfettiDom } from '../gfx/particles.js';
import { tween, easings } from '../gfx/tween.js'; // POLISH-J: coin roll-up
import { t, getLang } from '../data/strings.js';
import { now } from '../core/clock.js';
import { markRecapHeard } from '../systems/radioQueue.logic.js'; // POLISH-H
// V4/FIX-JUICE: the return-to-home leg rides the AC-3 cozy veil (mode 'home')
// instead of dropping the white fade straight onto a still-settling room.
import { initLoadingVeil, veil } from './loadingVeil.js';
// POLISH-J: end-card polish strings (local tx() fallback — G52 pattern)
import { EN as R2_EN, DE as R2_DE } from '../data/strings/v4-recap2.js';
import {
  OVERLAY, biomeBackdrop, recapSeed, chooseRecapTrack, elementVolume,
  advanceClock, barIndexAt, beatIndexAt, createCueScheduler, cutSpans, spanAt,
  nextSpanAt, popDurations, skipAllowed, displayMilestone, rewardCoins,
  replayRewardFrom, canAutoStart, createOffsetRecorder,
  endCardHighlights, // POLISH-J
  rotatedFrame, shouldRotate, createRotationGuard, // V6/B1 landscape
} from './recapOverlay.logic.js';
// V6/B1: the same OS reduced-motion predicate every effect gate uses (AC-9)
import { prefersReducedMotion } from './ui.js';
// V6/D3: the logic layer emits icon NAMES; this view maps them to SVG here.
import { icon } from './icons.js';

const DEV = !!import.meta.env?.DEV;

// G63's Team-RECAP modules land in the same wave (§E0.1-11): transform-time
// globs keep this module bootable while they're absent — the cinematic then
// uses the DOM colored-backdrop fallback.
const vignetteModules = import.meta.glob('../recap/vignettes.js');
const recapAssetModules = import.meta.glob('../recap/recapAssets.js');

/** @type {{store: object, ui: object, audio: object, sceneManager: object, assets: object}|null} */
let deps = null;
/** @type {object|null} G63's vignettes module once probed (null = fallback). */
let vignettesMod = null;
/** @type {object|null} the active playback session (one at a time). */
let sess = null;
/** Last completed session's offset summary (CDP/eval evidence surface). */
let lastSummary = null;

// ---------------------------------------------------------------------------
// G63 vignette scene ('recap' — §E1; sceneManager renders, session drives)
// ---------------------------------------------------------------------------

/**
 * §E1 factory for the shared recap scene: ONE vignette live at a time (G63
 * contract), the NEXT one PRE-ROLLED hidden PRE_ROLL_SEC before its cut —
 * build + shader compile land off-beat, the on-beat swap is a visibility
 * flip (§C-SYS2.6 „camera pre-rolls so the cut lands exactly on the
 * downbeat"). The dolly runs off the session's master beat clock.
 * @param {{assets: object, renderer?: object}} ctx
 */
function createRecapVignetteScene(ctx) {
  const scene = new THREE.Scene();
  scene.background = new THREE.Color('#fff6ec');
  const camera = new THREE.PerspectiveCamera(46, innerWidth / innerHeight, 0.1, 120);
  camera.position.set(0, 1.5, 8);
  recapCam = camera; // V6/B1: the landscape assert retargets THIS aspect
  /** @type {{group: object, dispose: Function, update: Function}|null} live */
  let handle = null;
  let liveIdx = -1;
  /** @type {{handle: object, idx: number, bg: object}|null} pre-rolled next */
  let staged = null;
  /** tiny offscreen target for the pre-roll warm render (never shown) */
  let warmRT = null;
  // §A2 low-end guard: software rasterizers (SwiftShader VMs) spend 100–250 ms
  // PER FRAME at native res — those main-thread stalls are what pushes cues
  // past the ±80 ms budget. Cost ≈ pixels, so slow frames (sustained EMA > 75
  // ms, or one > 150 ms spike) step the render buffer down. Real GPUs (~16 ms
  // frames) never trip this; the ratio is restored in dispose().
  const basePR = ctx.renderer?.getPixelRatio?.() ?? 1;
  const PR_STEPS = [1, 0.6, 0.45, 0.3];
  let prStep = 0;
  let emaDt = 0;
  return {
    scene,
    camera,
    async enter() {
      await vignettesMod?.preloadBackdrops?.().catch?.(() => {});
    },
    update(dt) {
      const s = sess;
      if (!s || !vignettesMod) return;
      // Fire due cues BEFORE this frame's (expensive) render — the overlay's
      // own rAF callback runs after sceneManager's render and would tax every
      // cue with the frame's raster time.
      s.step?.(performance.now());
      emaDt = emaDt === 0 ? dt : emaDt * 0.85 + dt * 0.15;
      if ((emaDt > 0.075 || dt > 0.15) && prStep < PR_STEPS.length - 1) {
        prStep += 1;
        emaDt = 0;
        try {
          ctx.renderer.setPixelRatio(basePR * PR_STEPS[prStep]);
        } catch { /* renderer without setPixelRatio — keep native */ }
        if (DEV) console.log(`[recap] slow frames — render scale ×${PR_STEPS[prStep]}`);
      }
      s.renderScale = PR_STEPS[prStep];
      const next = s.nextSpan;
      // Pre-roll phase 1: build the upcoming vignette hidden. Phase 2 (the
      // NEXT frame): one warm render into a tiny offscreen target — forces
      // SwiftShader program compiles AND texture uploads early (renderer
      // .compile alone skips uploads). Split across two frames so the two
      // stalls never stack; both land right after the preceding text pop
      // (PRE_ROLL_SEC), so the on-beat swap is just a visibility flip.
      if (next && next.vignette !== liveIdx && staged?.idx !== next.vignette) {
        if (staged) staged.handle.dispose();
        staged = null;
        const savedBg = scene.background;
        try {
          const h = vignettesMod.buildVignette(next.id, scene, ctx.assets, { camera });
          const stagedBg = scene.background; // the builder set the biome bg
          scene.background = savedBg; // restore until the cut lands
          h.update(0, 0); // pose the dolly at progress 0
          if (h.group) h.group.visible = false;
          staged = { handle: h, idx: next.vignette, bg: stagedBg, warmed: false };
        } catch (err) {
          console.warn(`[recap] pre-roll of '${next.id}' failed:`, err);
          scene.background = savedBg;
        }
      } else if (staged && !staged.warmed) {
        staged.warmed = true;
        const savedBg = scene.background;
        if (staged.handle.group) staged.handle.group.visible = true;
        scene.background = staged.bg;
        try {
          warmRT = warmRT ?? new THREE.WebGLRenderTarget(16, 16);
          ctx.renderer.setRenderTarget(warmRT);
          ctx.renderer.render(scene, camera);
        } catch { /* warm render is best-effort */ } finally {
          try { ctx.renderer.setRenderTarget(null); } catch { /* noop */ }
        }
        if (staged.handle.group) staged.handle.group.visible = false;
        scene.background = savedBg;
      }
      // V6/FIX4 (Sol P1-2): the pre-roll build + warm render above are the
      // recap's biggest deliberate main-thread stalls (SwiftShader compiles/
      // uploads) — re-run the dispatcher so a cue that came due DURING them
      // fires before this frame's raster, not a whole stalled frame later.
      // step() is idempotent per timestamp, so healthy frames pay nothing.
      s.step?.(performance.now());
      const span = s.liveSpan;
      // The cut: swap ON the beat (cheap when the pre-roll landed). The old
      // vignette only HIDES here — its dispose (dozens of geometry/material
      // frees, easily a 50–150 ms software-GL stall) is deferred off-beat.
      if (span && span.id && span.vignette !== liveIdx) {
        if (handle) {
          const old = handle;
          if (old.group) old.group.visible = false;
          setTimeout(() => { try { old.dispose(); } catch { /* noop */ } }, 400);
        }
        handle = null;
        if (staged?.idx === span.vignette) {
          handle = staged.handle;
          if (handle.group) handle.group.visible = true;
          scene.background = staged.bg;
          staged = null;
        } else {
          try {
            handle = vignettesMod.buildVignette(span.id, scene, ctx.assets, { camera });
          } catch (err) {
            console.warn(`[recap] vignette '${span.id}' failed to build:`, err);
          }
        }
        liveIdx = span.vignette;
      }
      // After the end cue span is null — the last vignette idles at p = 1.
      handle?.update(dt, span ? span.progress : 1);
    },
    dispose() {
      staged?.handle.dispose();
      staged = null;
      handle?.dispose();
      handle = null;
      liveIdx = -1;
      warmRT?.dispose();
      warmRT = null;
      try {
        ctx.renderer?.setPixelRatio?.(basePR);
      } catch { /* noop */ }
      // V6/B1: the scene leaving IS an exit path (any switch away from
      // 'recap', including failed switches) — restore the portrait renderer
      // size/aspect + classes here too. Idempotent: finishRecap's own restore
      // (behind the exit white) already ran on the normal path.
      if (recapCam === camera) {
        if (sess) restoreLandscape(sess);
        recapCam = null;
      }
    },
  };
}

// THREE is only touched when G63's module resolved (it imports three itself,
// so the chunk is already paid for) — lazy holder keeps the import graph slim.
let THREE = null;

// ---------------------------------------------------------------------------
// DOM helpers
// ---------------------------------------------------------------------------

/** @param {string} cls @param {HTMLElement} [parent] @returns {HTMLDivElement} */
function div(cls, parent) {
  const el = document.createElement('div');
  el.className = cls;
  parent?.appendChild(el);
  return el;
}

/**
 * Localized stat-line text through strings/v4-recap.js (`recap.line.<id>`,
 * `.one` singular) with the director's baked textDe/textEn as fallback.
 * @param {{lineId: string, textDe: string, textEn: string}} cue
 * @param {number} n the (possibly mid-roll-up) display value
 * @returns {string}
 */
function lineText(cue, n) {
  const key = `recap.line.${cue.lineId}`;
  if (n === 1) {
    const one = t(`${key}.one`);
    if (one !== `${key}.one`) return one;
  }
  const s = t(key, { n });
  if (s !== key) return s;
  return getLang() === 'de' ? cue.textDe : cue.textEn;
}

// POLISH-J: same-wave i18n fallback for strings/v4-recap2.js (the G52 tx
// pattern — strings.js is frozen) until a later sweep spreads the keys.
function tx(key, vars) {
  const global = t(key, vars);
  if (global !== key) return global;
  let text = (getLang() === 'de' ? R2_DE : R2_EN)[key] ?? key;
  if (vars) {
    for (const [name, value] of Object.entries(vars)) {
      text = text.replaceAll(`{${name}}`, String(value));
    }
  }
  return text;
}

/** Fade a fullscreen white layer to `target` opacity over `ms`. */
function fadeWhite(el, target, ms) {
  return new Promise((resolve) => {
    el.style.transition = `opacity ${ms}ms ease`;
    // Force a style flush so the transition always runs from the current value.
    void el.offsetWidth;
    el.style.opacity = String(target);
    setTimeout(resolve, ms + 30);
  });
}

// ---------------------------------------------------------------------------
// V6/B1 — landscape presentation (PLAN6 Wave B/B1): the cinematic plays as a
// LANDSCAPE movie on the portrait-locked phone. Technique: rotate(90deg) on
// the recap DOM layer AND the #scene canvas with JS-computed px sizes (the
// pure math is recapOverlay.logic.js rotatedFrame — never 100vw/vh), plus
// renderer.setSize(innerHeight, innerWidth) + camera-aspect swap INSIDE the
// recap scene only. Everything happens behind the white entry/exit fades and
// EVERY exit path restores through ONE idempotent guard (createRotationGuard):
// finish, skip→finish, startCinematic error, scene dispose — with resize/
// visibilitychange re-asserts while active so sceneManager's own onResize
// (which re-applies portrait sizes) can never stick mid-recap.
// ---------------------------------------------------------------------------

// The landscape rules ship as an INJECTED sheet (the shop/profile/cutscene
// pattern) so styles.css stays untouched this wave (B3 owns it). The rotated
// layer is sized by --g64-rw/--g64-rh (JS px) and the PHYSICAL safe insets
// arrive re-mapped as --rsafe-* (notch → rotated LEFT — the player holds the
// phone turned counter-clockwise, home indicator right).
const LANDSCAPE_CSS = `
/* V6/B1 RECAP-LANDSCAPE (injected by recapOverlay.js) */
.g64-root.g64-landscape {
  inset: auto;
  top: 0;
  left: 0;
  width: var(--g64-rw, 100vh);
  height: var(--g64-rh, 100vw);
  transform: rotate(90deg) translateY(-100%);
  transform-origin: top left;
}
#scene.g64-landscape-canvas,
canvas.g64-landscape-canvas {
  position: fixed;
  inset: auto;
  top: 0;
  left: 0;
  transform: rotate(90deg) translateY(-100%);
  transform-origin: top left;
}
/* rotated-layer safe areas: vh/vw would still measure the PORTRAIT viewport
   inside the rotated box, so every offset below is %/rem/--rsafe-* only. */
.g64-root.g64-landscape .g64-stage {
  padding: max(1.25rem, calc(var(--rsafe-top, 0px) + 0.75rem))
    max(1rem, var(--rsafe-right, 0px)) 1rem max(1rem, var(--rsafe-left, 0px));
}
.g64-root.g64-landscape .g64-intro { margin-top: 6%; }
.g64-root.g64-landscape .g64-pops {
  top: 13%;
  left: max(0.75rem, var(--rsafe-left, 0px));
  right: max(0.75rem, var(--rsafe-right, 0px));
}
.g64-root.g64-landscape .g64-bar { height: 9%; }
.g64-root.g64-landscape .g64-skip {
  right: max(0.5rem, var(--rsafe-right, 0px));
  bottom: max(0.75rem, var(--rsafe-bottom, 0px));
}
.g64-root.g64-landscape .g64-biome {
  bottom: max(3.25rem, calc(var(--rsafe-bottom, 0px) + 2.5rem));
}
.g64-root.g64-landscape .g64-debug {
  left: max(0.5rem, var(--rsafe-left, 0px));
  bottom: max(0.5rem, var(--rsafe-bottom, 0px));
}
/* V6/D3: authored SVG chips (logic emits names; icon() renders them here). */
.g64-hl-icon svg { display: block; }
.g64-end-coins svg { display: block; color: var(--yellow-dark, #E0B04A); }
`;

/** Inject the landscape stylesheet once (idempotent — loadingVeil pattern). */
function ensureLandscapeStyles() {
  if (document.querySelector('style[data-owner="v6-b1-recap-landscape"]')) return;
  const style = document.createElement('style');
  style.dataset.owner = 'v6-b1-recap-landscape';
  style.textContent = LANDSCAPE_CSS;
  document.head.appendChild(style);
}

/** The live recap scene camera (set by createRecapVignetteScene, cleared on
 * its dispose) — the rotation assert retargets ITS aspect, never another
 * scene's. @type {object|null} */
let recapCam = null;

/** Read the LIVE --safe-* px values off <html> (env() insets or the ?notch=1
 * fake-notch inline override — both land in the computed style). */
function readSafeInsets() {
  try {
    const cs = window.getComputedStyle(document.documentElement);
    const px = (name) => parseFloat(cs.getPropertyValue(name)) || 0;
    return {
      top: px('--safe-top'),
      right: px('--safe-right'),
      bottom: px('--safe-bottom'),
      left: px('--safe-left'),
    };
  } catch {
    return { top: 0, right: 0, bottom: 0, left: 0 };
  }
}

/**
 * (Re-)assert the rotated frame from the LIVE viewport: rotated-layer px
 * vars + mapped --rsafe-* insets on the recap root, the rotation classes,
 * and — in scene mode — the swapped renderer size + recap camera aspect.
 * Runs on apply and again on resize/visibilitychange while active, because
 * sceneManager.onResize re-applies portrait sizes on every window resize.
 * @param {object} s the live session
 */
function assertLandscapeFrame(s) {
  if (!s.rotGuard?.active() || !s.dom.root) return;
  const { rw, rh, rsafe } = rotatedFrame({
    width: window.innerWidth,
    height: window.innerHeight,
    insets: readSafeInsets(),
  });
  const st = s.dom.root.style;
  st.setProperty('--g64-rw', `${rw}px`);
  st.setProperty('--g64-rh', `${rh}px`);
  st.setProperty('--rsafe-top', `${rsafe.top}px`);
  st.setProperty('--rsafe-right', `${rsafe.right}px`);
  st.setProperty('--rsafe-bottom', `${rsafe.bottom}px`);
  st.setProperty('--rsafe-left', `${rsafe.left}px`);
  s.dom.root.classList.add('g64-landscape');
  if (!s.sceneMode) return;
  const renderer = deps?.sceneManager?.renderer;
  renderer?.domElement?.classList?.add('g64-landscape-canvas');
  try {
    renderer?.setSize?.(rw, rh); // the rotate(90deg) swap: rw = innerHeight
  } catch { /* renderer without setSize — DOM layers still rotate */ }
  if (recapCam?.isPerspectiveCamera) {
    recapCam.aspect = rw / Math.max(1, rh);
    recapCam.updateProjectionMatrix();
  }
}

/**
 * Apply the landscape presentation (idempotent via the session's guard).
 * Called behind the entry white fade AFTER scene-mode resolution; no-op when
 * the session decided not to rotate (reduced motion / already-landscape).
 * @param {object} s the live session
 */
function applyLandscape(s) {
  if (!s.rotate || !s.rotGuard.apply()) return;
  ensureLandscapeStyles();
  assertLandscapeFrame(s);
  const reassert = () => assertLandscapeFrame(s);
  window.addEventListener('resize', reassert);
  document.addEventListener('visibilitychange', reassert);
  s.rotOff = () => {
    window.removeEventListener('resize', reassert);
    document.removeEventListener('visibilitychange', reassert);
  };
}

/**
 * Restore the portrait presentation (idempotent via the guard) — remove the
 * rotation classes/vars, unhook the re-asserts and hand the renderer/camera
 * back their portrait size/aspect. EVERY teardown path routes through here:
 * finishRecap (behind the exit white), the recap scene's dispose (any scene
 * switch away — including failed switches) and startCinematic's error path.
 * @param {object} s the session being torn down
 */
function restoreLandscape(s) {
  if (!s?.rotGuard?.restore()) return;
  s.rotOff?.();
  s.rotOff = null;
  if (s.dom.root) {
    const st = s.dom.root.style;
    for (const name of ['--g64-rw', '--g64-rh', '--rsafe-top', '--rsafe-right', '--rsafe-bottom', '--rsafe-left']) {
      st.removeProperty(name);
    }
    s.dom.root.classList.remove('g64-landscape');
  }
  const renderer = deps?.sceneManager?.renderer;
  renderer?.domElement?.classList?.remove('g64-landscape-canvas');
  if (s.sceneMode) {
    try {
      renderer?.setSize?.(window.innerWidth, window.innerHeight);
    } catch { /* noop */ }
    if (recapCam?.isPerspectiveCamera) {
      recapCam.aspect = window.innerWidth / Math.max(1, window.innerHeight);
      recapCam.updateProjectionMatrix();
    }
  }
}

// ---------------------------------------------------------------------------
// Playback session
// ---------------------------------------------------------------------------

/**
 * Build + run one cinematic. Exactly one session at a time.
 * @param {object} opts
 * @param {number} opts.level milestone headline („Level {X}!")
 * @param {Array<{id: string, value: number}>} opts.lines stat lines to show
 * @param {number} opts.fromLevel reward base (coins recap = Σ 25×l above it)
 * @param {number} opts.atMs seed input (baselineAt / history row `at`)
 * @param {boolean} [opts.commit] write §B5.2 completeRecap on finish/skip
 * @param {boolean} [opts.noScene] force the DOM backdrop fallback (CDP knob)
 * @returns {Promise<boolean>} started?
 */
async function startCinematic({ level, lines, fromLevel, atMs, commit = false, noScene = false }) {
  if (!deps || sess) return false;
  const { store, ui, sceneManager } = deps;

  const seed = recapSeed(level, atMs);
  const pick = chooseRecapTrack(getTracks(), seed, store.get('radio')?.trims);
  const track = pick.id ? trackById(pick.id) : null;

  const s = {
    level,
    lines,
    fromLevel,
    commit,
    trackId: track?.id ?? null,
    trackFallback: pick.fallback,
    timeline: null,
    scheduler: null,
    spans: [],
    liveSpan: null,
    clock: { t: 0, anchorBar: -1 },
    lastFrame: 0,
    raf: 0,
    el: null,
    audioLive: false,
    sceneMode: false,
    returnScene: null,
    recorder: createOffsetRecorder(),
    offs: [],
    dom: {},
    skipVisible: false,
    ended: false,
    finishing: false,
    beatDebug: false,
    startedAt: now(),
    // V6/B1 landscape: decided ONCE at start — reduced motion keeps today's
    // portrait letterboxed presentation, an already-landscape viewport
    // (desktop/tablet) must never double-rotate.
    rotate: shouldRotate({
      reducedMotion: prefersReducedMotion(),
      width: window.innerWidth,
      height: window.innerHeight,
    }),
    rotGuard: createRotationGuard(),
    rotOff: null,
    pinnedT: null, // dev __recap.pin() freeze-frame (capture evidence hook)
  };
  sess = s;

  // §C-SYS1 suppressor: dedicated playback ducks the radio + mutes the medley
  // for the whole cinematic; both restored in teardown (reasons stack).
  radioPlayer.duck(true, 'recap');
  musicDirector.setSuppressed(true);
  document.body.classList.add('g64-recap');

  // Overlay skeleton (above the sceneManager fade so the takeover stays WHITE).
  // 'g64-boot' keeps the stage invisible until the entry fade covers the home
  // scene — the title/backdrops only exist behind/after the white.
  const root = div('g64-root g64-boot');
  const bgA = div('g64-bg', root);
  const bgB = div('g64-bg', root);
  // POLISH-J: cinematic letterbox bars — slide in with the first cut
  // (.g64-cine on the root), slide back out for the end card.
  div('g64-bar g64-bar-top', root);
  div('g64-bar g64-bar-bottom', root);
  const stage = div('g64-stage', root);
  const intro = div('g64-intro', stage);
  intro.innerHTML = `
    <div class="g64-title">${t('recap.title', { n: level })}</div>
    <div class="g64-subtitle">${t('recap.subtitle')}</div>`;
  const popHost = div('g64-pops', stage);
  const skipEl = div('g64-skip', root);
  skipEl.textContent = t('recap.skip');
  const debugEl = div('g64-debug', root);
  const white = div('g64-white', root);
  white.style.opacity = '0';
  document.body.appendChild(root);
  s.dom = { root, bgA, bgB, stage, intro, popHost, skipEl, debugEl, white };

  // Beat-debug overlay honors G58's exported toggle (dev card 15) — read the
  // current flag AND live-follow the runtime event.
  import('./devPanel.js')
    .then((m) => { s.beatDebug = m.getRecapBeatDebug?.() === true; })
    .catch(() => {});
  s.offs.push(store.on('recapBeatDebugChanged', ({ on }) => { s.beatDebug = on === true; }));

  // §C-SYS2.1 entry: 400 ms white-fade takeover.
  await fadeWhite(white, 1, OVERLAY.WHITE_FADE_MS);
  root.classList.remove('g64-boot');
  ui.closeAll();

  // Timeline: committed beats manifest (the manifest row already points at
  // the override file when one exists — §B5.3 precedence baked by G51).
  let beats = null;
  if (track?.beats) {
    try {
      const res = await fetch(trackUrl(track.beats));
      if (res.ok) beats = await res.json();
    } catch { /* default grid (§B5.3) */ }
  }
  s.timeline = buildTimeline({
    beats,
    durationSec: track?.durationSec ?? 100,
    lines,
    level,
    trackId: s.trackId ?? '',
  });
  s.scheduler = createCueScheduler(s.timeline.cues);
  s.spans = cutSpans(s.timeline);

  // 3D vignettes (G63) when present — else warm the DOM backdrop images.
  s.sceneMode = !noScene && vignettesMod != null && sceneManager.has('recap');
  if (s.sceneMode) {
    try {
      s.returnScene = sceneManager.currentId() ?? 'home';
      // V6/B1: switchTo is SWALLOWED (warn + resolve) while another switch
      // is in flight — the framework's launch-retry pattern (§F6/RE5).
      // sceneMode=true must never stand over a foreign live scene: the
      // landscape swap below rotates the #scene canvas, so an ignored
      // switch would rotate home/minigame. Re-issue until the recap scene
      // truly settled, else fall through to the opaque DOM backdrops.
      const settled = () =>
        sceneManager.currentId() === 'recap' && sceneManager.isSwitching?.() !== true;
      await sceneManager.switchTo('recap');
      const retryUntil = performance.now() + OVERLAY.SCENE_SETTLE_MAX_MS;
      while (!settled() && performance.now() < retryUntil) {
        await new Promise((r) => setTimeout(r, OVERLAY.SCENE_SETTLE_POLL_MS));
        if (settled()) break;
        if (sceneManager.isSwitching?.() === true) continue; // still fading
        await sceneManager.switchTo('recap');
      }
      if (!settled()) throw new Error('recap switch swallowed (switch in flight)');
    } catch (err) {
      console.warn('[recap] scene switch failed — DOM fallback:', err);
      s.sceneMode = false;
      s.returnScene = null;
    }
  }
  if (!s.sceneMode) {
    for (const span of s.spans) {
      const bd = biomeBackdrop(span.id);
      if (bd.img) new Image().src = trackUrl(bd.img);
    }
    bgA.style.background = 'linear-gradient(180deg,#ffe9f2,#ffd9e4)';
    bgA.style.opacity = '1';
  }

  // V6/B1: turn the presentation landscape — AFTER scene-mode resolution
  // (the renderer/camera swap only happens when the 3D scene is live) and
  // BEHIND the still-opaque entry white, so the swap is never visible. The
  // rest of the start sequence is guarded: any throw below restores the
  // rotation before propagating (the 'error' exit path).
  applyLandscape(s);
  try {
    // Dedicated MediaElement (§C-SYS2.6): element volume replicates the §B2.2
    // bus math; play() rejection (no gesture/VM) → wall-clock mode, same cues.
    if (track) {
      const el = new Audio(trackUrl(track.file));
      el.preload = 'auto';
      s.el = el;
      const applyVolume = () => {
        const st = store.get();
        const vols = st?.settings?.volumes ?? {};
        el.volume = elementVolume({
          gainTrim: track.gainTrim,
          trimVol: st?.radio?.trims?.[track.id]?.vol ?? 100,
          master: vols.master ?? 80,
          music: vols.music ?? 70,
          musicEnabled: st?.settings?.music !== false,
        });
        // §B2.4 airtight music mute: pause the element (zero streaming), the
        // grid continues on the wall clock; re-enable resumes at el time.
        if (st?.settings?.music === false) {
          if (!el.paused) el.pause();
        } else if (el.paused && !el.ended && s.audioLive && !s.finishing) {
          // never auto-restart a naturally-ENDED track (grid is done by then)
          el.play().catch(() => {});
        }
      };
      applyVolume();
      s.offs.push(store.on('change', applyVolume));
      try {
        await el.play();
        s.audioLive = true;
      } catch {
        s.audioLive = false; // autoplay refused → wall clock (visuals identical)
      }
    }

    // Skip + Weiter input (§C-SYS2.2: overlay eats ALL taps; before t = 10 s
    // they do nothing, after they cut to the end card).
    root.addEventListener('click', (ev) => {
      if (s.ended || s.finishing) return;
      if (!s.skipVisible || !skipAllowed(s.clock.t, s.timeline.skipAfterSec)) return;
      ev.stopPropagation();
      doSkip();
    });

    if (DEV) console.log(`[recap] start L${level} track=${s.trackId} fallbackTrack=${pick.fallback} scene=${s.sceneMode} audio=${s.audioLive} landscape=${s.rotGuard.active()} bpm=${s.timeline.bpm} cues=${s.timeline.cues.length}`);

    // Master loop (V6/FIX4 Sol P1-2): cue dispatch is RAF/render-driven — the
    // recap scene calls step() BEFORE each render (s.step below), this
    // module's own rAF re-runs it after, and step() itself fires every cue
    // due within the observed frame interval (bounded lookahead, see the
    // scheduler.advance call). The 25 ms timer is only a BACKSTOP for
    // throttled rAF (hidden tab); it starves during raster stalls exactly
    // like rAF does, so it must never be the primary dispatcher. step() is
    // idempotent per timestamp.
    s.lastFrame = performance.now();
    const step = (nowMs) => {
      if (sess !== s || s.finishing) return;
      const dtSec = Math.min(0.25, Math.max(0, (nowMs - s.lastFrame) / 1000));
      if (dtSec <= 0) return;
      s.lastFrame = nowMs;
      const elT = s.audioLive && s.el && !s.el.paused && Number.isFinite(s.el.currentTime)
        ? s.el.currentTime : null;
      // V6/B1 dev freeze-frame: __recap.pin() holds the master clock at a
      // chosen biome/progress (audio paused) so CDP can capture deterministic
      // framing evidence — per-frame dt still ticks the vignette's ambience.
      s.clock = s.pinnedT != null
        ? { t: s.pinnedT, anchorBar: barIndexAt(s.timeline, s.pinnedT) }
        : advanceClock(s.clock, { dtSec, elT, grid: s.timeline });
      // Re-assert the medley suppressor: any audio.music(id) call resets it
      // (audio.js §C3.4 line) — scene hooks firing mid-cinematic must not
      // resurrect the medley under the recap track.
      if (musicDirector.getStats().suppressed !== true) musicDirector.setSuppressed(true);
      if (!s.ended) {
        // V6/FIX4 (Sol P1-2): frame-interval lookahead — a cue due DURING the
        // coming frame fires now (≤ one observed frame early, capped under
        // the ±80 ms budget) instead of a whole stalled frame late. The EMA
        // tracks the real inter-dispatch cadence: ~16 ms on healthy devices,
        // frame-length on SwiftShader where raster blocks rAF AND the timer.
        s.emaStepSec = s.emaStepSec > 0 ? s.emaStepSec * 0.8 + dtSec * 0.2 : dtSec;
        const lookahead = s.pinnedT != null
          ? 0 : Math.min(s.emaStepSec, OVERLAY.CUE_LOOKAHEAD_MAX_SEC);
        for (const cue of s.scheduler.advance(s.clock.t + lookahead)) fireCue(cue);
        s.liveSpan = spanAt(s.spans, s.clock.t);
        s.nextSpan = nextSpanAt(s.spans, s.clock.t);
        updatePops();
        updateSkip();
      }
      updateDebug();
    };
    const frame = (nowMs) => {
      if (sess !== s || s.finishing) return;
      step(nowMs);
      s.raf = requestAnimationFrame(frame);
    };
    s.raf = requestAnimationFrame(frame);
    s.tick = setInterval(() => step(performance.now()), 25);
    // The recap scene calls this BEFORE each render (§A2: sceneManager's rAF
    // runs before this module's, so without it every cue pays the raster time).
    s.step = step;

    // Reveal (intro cue at t = 0 fired on the first frame above).
    await fadeWhite(white, 0, OVERLAY.WHITE_FADE_MS);
    return true;
  } catch (err) {
    // V6/B1 'error' exit path: the rotation must never outlive a failed start.
    restoreLandscape(s);
    throw err;
  }
}

// ── cue application ──────────────────────────────────────────────────────────

/** @param {object} cue a director cue due at the master clock */
function fireCue(cue) {
  const s = sess;
  if (!s) return;
  s.recorder.record(cue.kind, cue.bar, cue.t, s.clock.t);
  if (cue.kind === 'cut') {
    if (cue.vignette === 0) {
      s.dom.intro.classList.add('g64-gone');
      s.dom.root.classList.add('g64-cine'); // POLISH-J: letterbox in
    }
    s.liveSpan = {
      vignette: cue.vignette,
      id: cue.biome?.id ?? '',
      biome: cue.biome,
      progress: 0,
    };
    clearPop();
    showBiomeChip(cue.biome); // POLISH-J: biome name rides the cut cue
    if (!s.sceneMode) crossfadeBackdrop(cue.biome?.id ?? '');
  } else if (cue.kind === 'text') {
    spawnPop(cue);
  } else if (cue.kind === 'end') {
    showEndCard();
  }
}

/** DOM-fallback backdrop crossfade (colored gradient + committed AI PNG). */
function crossfadeBackdrop(biomeId) {
  const s = sess;
  if (!s) return;
  const bd = biomeBackdrop(biomeId);
  const [showEl, hideEl] = s.dom.bgFlip
    ? [s.dom.bgA, s.dom.bgB] : [s.dom.bgB, s.dom.bgA];
  s.dom.bgFlip = !s.dom.bgFlip;
  const grad = `linear-gradient(180deg, ${bd.from}, ${bd.to})`;
  showEl.style.background = grad;
  if (bd.img) {
    // Committed ART-GATE-2 PNG over the tint (tint shows while it streams in).
    showEl.style.backgroundImage = `url("${trackUrl(bd.img)}"), ${grad}`;
    showEl.style.backgroundSize = 'cover, cover';
    showEl.style.backgroundPosition = 'center, center';
  }
  showEl.style.opacity = '1';
  hideEl.style.opacity = '0';
}

/** POLISH-J: per-cut biome-name chip (the §C-SYS2.3 labels G55's cut cues
 * already carry — purely visual, self-removing; timing untouched). */
function showBiomeChip(biome) {
  const s = sess;
  const label = getLang() === 'de' ? biome?.labelDe : biome?.labelEn;
  if (!s || !label) return;
  s.dom.biomeEl?.remove();
  const el = div('g64-biome', s.dom.root);
  el.textContent = label;
  s.dom.biomeEl = el;
  // matches the g64biome keyframes' 3.2 s fade-in/hold/fade-out
  setTimeout(() => {
    if (s.dom.biomeEl === el) s.dom.biomeEl = null;
    el.remove();
  }, 3300);
}

/** @param {object} cue text cue → beat-synced pop with counter roll-up */
function spawnPop(cue) {
  const s = sess;
  if (!s) return;
  clearPop();
  const { popSec, rollSec } = popDurations(cue, s.timeline);
  const el = div('g64-pop', s.dom.popHost);
  el.style.animationDuration = `${Math.round(popSec * 1000)}ms`;
  el.textContent = lineText(cue, cue.value === 1 ? 1 : 0);
  s.pop = { cue, el, bornT: s.clock.t, popSec, rollSec, done: false };
}

/** Per-frame counter roll-up (§C-SYS2.6: 0→n over rollupBeats AFTER the pop). */
function updatePops() {
  const s = sess;
  const p = s?.pop;
  if (!p || p.done) return;
  const dt = s.clock.t - p.bornT;
  let n;
  if (dt <= p.popSec) n = p.cue.value === 1 ? 1 : 0;
  else if (dt >= p.popSec + p.rollSec) {
    n = p.cue.value;
    p.done = true;
  } else n = Math.round(((dt - p.popSec) / p.rollSec) * p.cue.value);
  p.el.textContent = lineText(p.cue, n);
}

function clearPop() {
  const s = sess;
  if (s?.pop?.el) {
    const old = s.pop.el;
    old.classList.add('g64-pop-out');
    setTimeout(() => old.remove(), 350);
  }
  if (s) s.pop = null;
}

/** §C-SYS2.2: subtle affordance fades in from t = skipAfterSec. */
function updateSkip() {
  const s = sess;
  if (!s || s.skipVisible) return;
  if (skipAllowed(s.clock.t, s.timeline.skipAfterSec)) {
    s.skipVisible = true;
    s.dom.skipEl.classList.add('g64-skip-in');
  }
}

/** §C-SYS2.2 skip: 300 ms cut to the end card (audio jumps with the clock). */
function doSkip() {
  const s = sess;
  if (!s || s.ended || s.finishing) return;
  if (DEV) console.log(`[recap] skip at t=${s.clock.t.toFixed(2)} → end card t=${s.timeline.endCard.t.toFixed(2)}`);
  s.dom.root.classList.add('g64-cut');
  setTimeout(() => s.dom.root.classList.remove('g64-cut'), OVERLAY.SKIP_CUT_MS + 60);
  const endT = s.timeline.endCard.t;
  s.scheduler.skipTo(endT);
  s.clock = { t: endT, anchorBar: barIndexAt(s.timeline, endT) };
  if (s.el && s.audioLive) {
    try {
      s.el.currentTime = endT;
    } catch { /* not seekable yet — wall clock carries on */ }
  }
  clearPop();
  for (const cue of s.scheduler.advance(endT)) fireCue(cue); // fires 'end'
}

/** §C-SYS2.7 end card: headline ring, coin recap, next unlock, confetti.
 * POLISH-J visual upgrade: highlight chips (top played stat lines), a coin
 * roll-up (gfx/tween.js), the played-song credit and a staged second
 * confetti wave — completion logic and the track-pick contract untouched. */
function showEndCard() {
  const s = sess;
  if (!s || s.ended) return;
  s.ended = true;
  s.liveSpan = null;
  clearPop();
  s.dom.intro.classList.add('g64-gone');
  s.dom.skipEl.classList.remove('g64-skip-in');
  s.dom.root.classList.remove('g64-cine'); // POLISH-J: letterbox out
  s.dom.biomeEl?.remove();
  s.dom.biomeEl = null;

  const coins = rewardCoins(s.level, s.fromLevel);
  const playerLevel = s.commit
    ? Math.max(s.level, Math.floor(Number(deps.store.get('level')) || 1))
    : s.level;
  const next = nextUnlock(playerLevel);
  let nextLine = t('recap.endcard.all');
  if (next) {
    const name = t(next.nameKey);
    nextLine = name !== next.nameKey
      ? t('recap.endcard.next', { name, n: next.level })
      : '';
  }
  // POLISH-J: top-3 played stat lines as highlight chips + song credit
  const highlights = endCardHighlights(s.lines, 3);
  const chips = highlights.map((h, i) => `
      <div class="g64-hl-chip" style="animation-delay: ${420 + i * 150}ms">
        <span class="g64-hl-icon">${icon(h.icon, 20)}</span>
        <span class="g64-hl-n">${h.value}</span>
        <span class="g64-hl-label">${tx(`recap2.stat.${h.id}`)}</span>
      </div>`).join('');
  const played = s.trackId ? trackById(s.trackId) : null;
  const songLine = played?.title ? tx('recap2.endcard.song', { name: played.title }) : '';
  const R = 26;
  const C = (2 * Math.PI * R).toFixed(2);
  const card = div('g64-endcard', s.dom.root);
  card.innerHTML = `
    <div class="g64-ring">
      <svg viewBox="0 0 64 64" width="100%" height="100%">
        <circle class="g64-ring-bg" cx="32" cy="32" r="${R}"></circle>
        <circle class="g64-ring-fg" cx="32" cy="32" r="${R}"
          stroke-dasharray="${C}" stroke-dashoffset="${C}"></circle>
      </svg>
      <span class="g64-ring-n">${s.level}</span>
    </div>
    <div class="g64-end-title">${t('recap.title', { n: s.level })}</div>
    ${coins > 0 ? `<div class="g64-end-coins">${icon('coin', 16)} <span data-coins>${t('recap.endcard.rewards', { n: 0 })}</span></div>` : ''}
    ${chips ? `<div class="g64-hl-title">${tx('recap2.endcard.highlights')}</div><div class="g64-hl">${chips}</div>` : ''}
    ${nextLine ? `<div class="g64-end-line g64-end-next">${nextLine}</div>` : ''}
    ${songLine ? `<div class="g64-end-song">${songLine}</div>` : ''}
    <button class="btn btn-pink g64-continue">${t('recap.continue')}</button>`;
  requestAnimationFrame(() => {
    const fg = card.querySelector('.g64-ring-fg');
    if (fg) fg.style.strokeDashoffset = '0';
  });
  // POLISH-J: coin roll-up — display only, eased on gfx/tween.js
  const coinEl = card.querySelector('[data-coins]');
  if (coinEl && coins > 0) {
    s.coinTween = tween({
      from: 0, to: coins, duration: 1.1, delay: 0.35, ease: easings.easeOutCubic,
      onUpdate: (v) => {
        coinEl.textContent = t('recap.endcard.rewards', { n: Math.round(v) });
      },
    });
  }
  card.querySelector('.g64-continue')?.addEventListener('click', (ev) => {
    ev.stopPropagation();
    finishRecap();
  });
  burstConfettiDom(s.dom.root, { count: 56 });
  // POLISH-J: second, lighter wave as the ring completes
  setTimeout(() => {
    if (sess === s && !s.finishing) burstConfettiDom(s.dom.root, { count: 30 });
  }, 900);
  deps.audio.play('jingle.levelUp');
  if (DEV) console.log(`[recap] end card: L${s.level} coins=${coins} next=${next?.nameKey ?? 'all'} summary=${JSON.stringify(s.recorder.summary())}`);
}

/** G58's beat-debug overlay: bar/beat/clock + per-cue offset readout (§A2). */
function updateDebug() {
  const s = sess;
  if (!s) return;
  const el = s.dom.debugEl;
  if (!s.beatDebug) {
    if (el.style.display !== 'none') el.style.display = 'none';
    return;
  }
  el.style.display = 'block';
  const bar = barIndexAt(s.timeline, s.clock.t);
  const beat = beatIndexAt(s.timeline, s.clock.t);
  const rows = s.recorder.rows().slice(-3)
    .map((r) => `${r.kind}@${r.bar} ${r.offsetMs >= 0 ? '+' : ''}${r.offsetMs}ms`)
    .join(' · ');
  const sum = s.recorder.summary();
  // V6/B1: live draw calls (previous frame's renderer.info) + rotation state
  // — the landscape ≤150-per-vignette budget evidence rides this HUD.
  const dc = s.sceneMode ? deps?.sceneManager?.renderer?.info?.render?.calls : null;
  const extra = `${dc != null ? ` · dc ${dc}` : ''}${s.rotGuard?.active() ? ' · landscape' : ''}`;
  el.textContent = `t ${s.clock.t.toFixed(2)}/${s.timeline.totalSec.toFixed(0)}s · bar ${bar} · beat ${beat} · bpm ${s.timeline.bpm}${extra}`
    + ` | ${rows || '—'} | max ${sum.maxAbsMs}ms mean ${sum.meanAbsMs}ms (${sum.within}/${sum.n} ≤ ${sum.budgetMs}ms)`;
}

// ── completion + teardown ────────────────────────────────────────────────────

/** „Weiter" path: §B5.2 atomic completion (commit mode) + 500 ms fade home. */
async function finishRecap() {
  const s = sess;
  if (!s || s.finishing) return;
  s.finishing = true;
  s.coinTween?.cancel(); // POLISH-J: stop the roll-up before teardown
  const { store, audio, sceneManager } = deps;
  audio.play('ui.confirmBig');
  lastSummary = {
    level: s.level,
    trackId: s.trackId,
    audioLive: s.audioLive,
    sceneMode: s.sceneMode,
    ...s.recorder.summary(),
  };

  if (s.commit) {
    // §B5.2: ONE store.update — history row + lastRecapLevel advance +
    // baseline re-snapshot + pendingLevel cleared, with the PLAYED lines.
    let payload = null;
    store.update((state) => {
      const res = completeRecap(state, now(), s.lines);
      state.recap = res.recap;
      // V6.1/C1: recapsSeen finally gets its writer — the storyTeller
      // sticker (recapsSeen ≥ 3) reads it; save.js has carried the default
      // since V6 with no writer. This is the SINGLE committed completion
      // seam (normal finish AND the completing skip both land in
      // finishRecap); previews/replays run with commit:false and never
      // reach this block.
      const counters = state.achievements?.counters;
      if (counters) {
        counters.recapsSeen = Math.floor(Number(counters.recapsSeen) || 0) + 1;
      }
      // POLISH-H: persist the recap's PLAYED song as heard — the radio only
      // unlocks Recap-category tracks after a real recap featured them.
      const played = s.trackId ? trackById(s.trackId) : null;
      if (played) {
        const r = state.radio && typeof state.radio === 'object' ? state.radio : {};
        const heard = markRecapHeard(r.recapHeard, played, now());
        if (heard !== r.recapHeard) state.radio = { ...r, recapHeard: heard };
      }
      payload = { pendingLevel: 0, lastRecapLevel: res.recap.lastRecapLevel };
    });
    if (payload) store.emit('recapChanged', payload);
    store.flush();
  }

  // §C-SYS2.1 exit: end card → 500 ms white fade, then the AC-3 home veil
  // covers the scene switch (V4/FIX-JUICE — no more white-drop pop-in);
  // audio fades like the radio's §B2.3 transitions.
  cancelAnimationFrame(s.raf);
  if (s.tick != null) clearInterval(s.tick);
  if (s.el) {
    const el = s.el;
    const v0 = el.volume;
    const steps = 6;
    for (let i = 1; i <= steps; i += 1) {
      setTimeout(() => { el.volume = Math.max(0, v0 * (1 - i / steps)); },
        (OVERLAY.AUDIO_FADE_MS / steps) * i);
    }
    setTimeout(() => {
      el.pause();
      el.removeAttribute('src');
      el.load?.();
    }, OVERLAY.AUDIO_FADE_MS + 50);
  }
  await fadeWhite(s.dom.white, 1, OVERLAY.EXIT_FADE_MS);
  // V6/B1: un-rotate BEHIND the now-opaque exit white (the player never sees
  // the swap) and BEFORE the return scene switch, so home builds against the
  // restored portrait renderer size/aspect.
  restoreLandscape(s);
  // V4/FIX-JUICE: when a real scene switch is involved, raise the AC-3 home
  // veil UNDER the white takeover (veil z-loading 10000 < recap z 10010) so
  // dropping the overlay reveals the cozy curtain, and the veil's own timing
  // (afterEnter + settle frames + hard timeout) reveals the room only when
  // it is really ready — no pop-in, and a stuck scene can never trap the
  // player (HARD_TIMEOUT_MS/watchdog). The white ENTRY fade and every cue
  // timing above are untouched (beat-sync contract). Any veil failure falls
  // back to the old white fade-out.
  let veilCovered = null;
  if (s.sceneMode && s.returnScene) {
    try {
      initLoadingVeil({ sceneManager }); // idempotent (framework wired it at boot)
      veilCovered = veil.show({ mode: 'home' }); // BEFORE the switch — arms afterEnter
    } catch (err) {
      console.warn('[recap] home veil unavailable — white-fade fallback:', err);
    }
    try {
      await sceneManager.switchTo(s.returnScene);
    } catch (err) {
      console.warn('[recap] return scene switch failed:', err);
    }
  }
  for (const off of s.offs) off?.();
  radioPlayer.duck(false, 'recap');
  musicDirector.setSuppressed(false);
  document.body.classList.remove('g64-recap');
  if (veilCovered && veil.isShown()) {
    await veilCovered; // curtain fully covers before the takeover drops
    s.dom.root.remove();
    if (sess === s) sess = null;
    await veil.hide();
  } else {
    await fadeWhite(s.dom.white, 0, OVERLAY.WHITE_FADE_MS);
    s.dom.root.remove();
    if (sess === s) sess = null;
  }
}

// ---------------------------------------------------------------------------
// Public API (§E block G64 + G58's dev-card-15 probe shape)
// ---------------------------------------------------------------------------

/**
 * Dev card 15 „Preview": plays the cinematic at `level` from the CURRENT
 * diff — §C-SYS6 rule: NO state writes (pendingLevel/history untouched).
 * @param {{level: number}} opts
 */
export function previewRecap(opts = {}) {
  if (!deps) throw new Error('[recap] not initialized');
  const store = deps.store;
  const state = store.get();
  const level = Math.max(RECAP.FIRST_MILESTONE,
    Math.min(RECAP.LAST_MILESTONE, Math.floor(Number(opts.level) || RECAP.FIRST_MILESTONE)));
  const recap = state.recap ?? {};
  const lines = selectLines(diff(recap.baseline ?? {}, state, now()));
  startCinematic({
    level,
    lines,
    fromLevel: replayRewardFrom(recap.history, { level, at: 0 }),
    atMs: Number(recap.baselineAt) || now(),
    commit: false,
    noScene: opts.noScene === true,
  }).catch((err) => console.error('[recap] preview failed:', err));
}

/**
 * §C-SYS2.8 replay (profile row + dev card 15): plays from the STORED stats
 * — no re-snapshot, reward text reproduced from the history context.
 * @param {{level: number, at?: number, stats?: Array<{id: string, value: number}>}} opts
 */
export function replayRecap(opts = {}) {
  if (!deps) throw new Error('[recap] not initialized');
  const history = deps.store.get('recap')?.history ?? [];
  const level = Math.max(RECAP.FIRST_MILESTONE, Math.floor(Number(opts.level) || 0));
  const row = {
    level,
    at: Number(opts.at) || 0,
    stats: Array.isArray(opts.stats) ? opts.stats : [],
  };
  startCinematic({
    level,
    lines: row.stats,
    fromLevel: replayRewardFrom(history, row),
    atMs: row.at || level, // deterministic per row → same §C-SYS2.6 pick
    commit: false,
    noScene: opts.noScene === true,
  }).catch((err) => console.error('[recap] replay failed:', err));
}

/** Generic entry (G58 probes previewRecap ?? preview ?? play). */
export function play(opts = {}) {
  if (opts.replay || Array.isArray(opts.stats)) replayRecap(opts);
  else previewRecap(opts);
}

/** @returns {boolean} a cinematic is on screen right now */
export function isPlaying() {
  return sess != null;
}

/**
 * V6/B1 dev freeze-frame (CDP evidence hook, DEV probe only): hold the live
 * cinematic at `biome` (span id or 0-based index) and `p` progress — the
 * master clock pins, audio pauses, the vignette's ambience keeps ticking so
 * captures stay alive. `pinRecap(null)` releases the pin (clock resumes on
 * the wall clock; the paused element re-anchors it if it plays again).
 * @param {string|number|null} biome span id ('city'…), index, or null=unpin
 * @param {number} [p] progress 0..1 within the span
 * @returns {{id: string, t: number}|null} the pinned span, null when unpinned
 */
function pinRecap(biome, p = 0.5) {
  const s = sess;
  if (!s || s.ended || s.finishing) return null;
  if (biome == null) {
    s.pinnedT = null;
    return null;
  }
  const span = typeof biome === 'number'
    ? s.spans[Math.floor(biome)]
    : s.spans.find((x) => x.id === biome);
  if (!span) return null;
  const prog = Math.min(1, Math.max(0, Number(p) || 0));
  const t = span.from + prog * Math.max(0, span.to - span.from);
  s.scheduler.skipTo(t); // consume pending cues before the pin (no refire)
  s.pinnedT = t;
  s.clock = { t, anchorBar: barIndexAt(s.timeline, t) };
  s.liveSpan = spanAt(s.spans, t);
  if (s.el && !s.el.paused) {
    try { s.el.pause(); } catch { /* wall clock is pinned anyway */ }
  }
  return { id: span.id, t };
}

/** Eval/CDP evidence surface: live session probe + last run's §A2 summary. */
export function getRecapStats() {
  const s = sess;
  const radio = radioPlayer.getStats();
  const medley = musicDirector.getStats();
  return {
    playing: s != null,
    level: s?.level ?? null,
    trackId: s?.trackId ?? null,
    t: s ? Math.round(s.clock.t * 100) / 100 : null,
    bar: s ? barIndexAt(s.timeline, s.clock.t) : null,
    audioLive: s?.audioLive ?? null,
    elementT: s?.el && Number.isFinite(s.el.currentTime) ? Math.round(s.el.currentTime * 100) / 100 : null,
    elementPaused: s?.el ? s.el.paused : null,
    sceneMode: s?.sceneMode ?? null,
    renderScale: s?.renderScale ?? null,
    ended: s?.ended ?? null,
    vignette: s?.liveSpan?.id ?? null,
    // V6/B1 landscape evidence: live rotation state + apply/restore balance
    // and the previous frame's draw calls (≤150-per-vignette budget).
    landscape: s?.rotGuard?.active() ?? false,
    rotationCounts: s?.rotGuard?.counts() ?? null,
    drawCalls: s?.sceneMode ? deps?.sceneManager?.renderer?.info?.render?.calls ?? null : null,
    pinnedT: s?.pinnedT ?? null,
    offsets: s ? s.recorder.rows() : [],
    summary: s ? s.recorder.summary() : null,
    lastSummary,
    // §C-SYS1 suppressor evidence: radio ducked + medley suppressed while live.
    radioDucked: radio.ducked,
    radioElementState: radio.elementState,
    radioWantPlaying: radio.wantPlaying,
    medleySuppressed: medley.suppressed,
    medleySources: medley.sourcesLive,
  };
}

/**
 * Boot wiring (ONE main.js marked block): §B5.2 plays-on-next-home-enter
 * hook (poll + 'recapChanged' — never mid-gameplay per canAutoStart), G63
 * scene registration (feature-detected) and the DEV CDP probe.
 * @param {{store: object, ui: object, audio: object, sceneManager: object,
 *   assets: object}} d
 */
export function initRecapOverlay(d) {
  deps = d;

  // G63's vignettes (same-wave §E0.1-11): probe + register scene id 'recap'.
  const loadVg = vignetteModules['../recap/vignettes.js'];
  const loadAm = recapAssetModules['../recap/recapAssets.js'];
  if (loadVg) {
    Promise.all([loadVg(), loadAm ? loadAm() : null, import('three')])
      .then(([vg, am, three]) => {
        if (typeof vg?.buildVignette !== 'function') return;
        vignettesMod = vg;
        THREE = three;
        if (!d.sceneManager.has('recap')) {
          d.sceneManager.register('recap', createRecapVignetteScene,
            [...(am?.RECAP_ASSET_KEYS ?? [])]);
        }
      })
      .catch((err) => console.warn('[recap] G63 vignettes unavailable — DOM backdrop fallback:', err));
  }

  // Trigger: recap.pendingLevel → next quiet home moment (§C-SYS2.1).
  const maybeAutoStart = () => {
    if (!deps || sess) return;
    const recap = deps.store.get('recap');
    if (!recap || typeof recap !== 'object') return;
    const ok = canAutoStart({
      pendingLevel: recap.pendingLevel,
      sceneId: deps.sceneManager.currentId(),
      switching: deps.sceneManager.isSwitching(),
      activeScreenId: deps.ui.activeScreenId(),
      playing: sess != null,
    });
    if (!ok) return;
    const state = deps.store.get();
    const level = displayMilestone(recap.pendingLevel, state.level);
    const lines = selectLines(diff(recap.baseline ?? {}, state, now()));
    startCinematic({
      level,
      lines,
      fromLevel: Math.max(0, Math.floor(Number(recap.lastRecapLevel) || 0)),
      atMs: Number(recap.baselineAt) || now(),
      commit: true,
    }).catch((err) => console.error('[recap] auto-start failed:', err));
  };
  setInterval(maybeAutoStart, OVERLAY.POLL_MS);
  d.store.on('recapChanged', () => setTimeout(maybeAutoStart, 60));

  if (DEV) {
    window.__recap = {
      stats: getRecapStats,
      isPlaying,
      preview: (level, o = {}) => previewRecap({ level, ...o }),
      replay: (row, o = {}) => replayRecap({ ...row, ...o }),
      skip: doSkip,
      finish: finishRecap,
      // V6/B1 capture hooks: freeze-frame a biome + toggle the debug HUD
      pin: pinRecap,
      debug: (on) => { if (sess) sess.beatDebug = on !== false; },
    };
  }
}

export default {
  initRecapOverlay, previewRecap, replayRecap, play, isPlaying, getRecapStats,
};
