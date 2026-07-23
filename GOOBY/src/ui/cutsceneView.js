// V6/A1 — cutscene view driver (PLAN6 Wave A/A1): binds the PURE sequencer
// (systems/cutscene.js) to the real systems — home camera dollies via
// gfx/tween.js under a strict camera lease, Gooby clips/emotions, pooled
// particle bursts, prop spawns (assets.getModel), a letterboxed caption bar
// with tap-to-continue + skip chrome, music pushContext/popContext, gyro
// parallax suspension and HUD/input blocking. EVERY acquired resource is
// released through ONE idempotent cleanup that runs in `finally` on finish,
// skip, error and hard-abort paths alike (risk #5: a stuck overlay must
// never soft-lock the game — the pure player's 45 s watchdog + mandatory
// tapWait timeouts bound playback, and this module bounds the resources).
//
// Camera lease contract (PLAN6 A1 acceptance): the camera position/rotation
// snapshot is taken BEFORE the first op and restored in cleanup; playback
// REFUSES to start while roomManager.isPanning(), while the sleep flow owns
// the scene (systems/sleep.js isSleeping), while sceneManager.isSwitching(),
// outside the home scene, or while any §E6 screen is open — refusal returns
// false and callers skip silently (PLAN6 D1 contract).

import { t, getLang } from '../data/strings.js';
import { EN as CUT_EN, DE as CUT_DE } from '../data/strings/v6-cutscenes.js';
import { tween, easings } from '../gfx/tween.js';
import { createParticles } from '../gfx/particles.js';
import { prefersReducedMotion } from './ui.js';
import { getCutscene } from '../data/cutscenes.js';
import {
  compileScript,
  createCutscenePlayer,
  hasSeen,
  markSeenSlice,
} from '../systems/cutscene.js';
import { getCamera, getGooby, getRoomManager } from '../home/homeScene.js';
import { isSleeping } from '../systems/sleep.js';
import { setGyroSceneActive } from '../systems/gyroParallax.js';
import * as musicDirector from '../audio/musicDirector.js';

// §E0.1-2: view-local presentation numbers — frozen in the owning module.
const VIEW = Object.freeze({
  /** Fraction of the lease→Gooby distance a pushIn dollies. */
  PUSH_FRACTION: 0.35,
  /** Fraction a pullBack retreats (negative push). */
  PULL_FRACTION: 0.2,
  /** Camera focus height above Gooby's root (metres). */
  FOCUS_LIFT: 0.35,
  /** Particle bursts default to this height above Gooby's root. */
  BURST_LIFT: 0.9,
  /** Dedicated particle pool for cutscene bursts (small + disposable). */
  PARTICLE_POOL: 48,
  /** ms the overlay lingers for its exit animation before removal. */
  EXIT_MS: 450,
  /** ms the dev ?cutscene= kick waits after the home enter resolves. */
  DEV_KICK_DELAY_MS: 900,
  /** Kick retries while the scene is busy (SwiftShader fades are slow). */
  DEV_KICK_RETRIES: 20,
  /** Music context held (push/pop balanced) during playback. */
  MUSIC_CONTEXT: 'home',
});

const CSS = `
/* ── V6/A1: cutscene overlay (injected — styles.css is A2's this wave) ── */
.v6cs-root{position:absolute;inset:0;z-index:950;pointer-events:auto;touch-action:none;user-select:none;-webkit-user-select:none;-webkit-tap-highlight-color:transparent;}
.v6cs-bar{position:absolute;left:0;right:0;height:0;background:#171210;transition:height .45s cubic-bezier(.22,.9,.32,1);overflow:hidden;}
.v6cs-bar-top{top:0;}
.v6cs-bar-bot{bottom:0;display:flex;align-items:center;justify-content:center;padding:0 1rem;}
.v6cs-root.v6cs-in .v6cs-bar-top{height:calc(3.25rem + var(--safe-top, 0px));}
.v6cs-root.v6cs-in .v6cs-bar-bot{height:calc(4.75rem + var(--safe-bottom, 0px));}
.v6cs-caption{max-width:24rem;margin-bottom:var(--safe-bottom, 0px);color:#FFF7EE;font-size:1rem;font-weight:800;line-height:1.35;text-align:center;text-shadow:0 2px 8px rgba(0,0,0,.35);opacity:0;transform:translateY(0.375rem);transition:opacity .25s ease,transform .25s ease;}
.v6cs-caption.v6cs-caption-in{opacity:1;transform:none;}
.v6cs-hint{position:absolute;left:50%;bottom:calc(5.25rem + var(--safe-bottom, 0px));transform:translateX(-50%);padding:0.375rem 0.875rem;border-radius:999px;background:rgba(23,18,16,.72);color:#FFF7EE;font-size:0.75rem;font-weight:800;letter-spacing:.02em;opacity:0;transition:opacity .25s ease;pointer-events:none;animation:v6cs-hint-bob 1.6s ease-in-out infinite;}
.v6cs-hint.v6cs-hint-on{opacity:1;}
@keyframes v6cs-hint-bob{0%,100%{transform:translateX(-50%) translateY(0);}50%{transform:translateX(-50%) translateY(-0.25rem);}}
.v6cs-skip{position:absolute;top:calc(var(--safe-top, 0px) + 0.5rem);right:max(0.75rem, var(--safe-right, 0px));min-width:44px;min-height:44px;display:inline-flex;align-items:center;gap:0.5rem;padding:0.375rem 0.75rem;border:none;border-radius:999px;background:rgba(23,18,16,.72);color:#FFF7EE;font-family:inherit;font-size:0.75rem;font-weight:800;cursor:pointer;-webkit-tap-highlight-color:transparent;}
.v6cs-skip:active{transform:scale(.96);}
.v6cs-skip-ring{width:1rem;height:1rem;border-radius:50%;background:conic-gradient(var(--pink, #FF7BA9) 0deg, rgba(255,247,238,.28) 0deg);flex:none;}
.v6cs-root.v6cs-replay .v6cs-skip-ring{display:none;}
.v6cs-progress{position:absolute;left:0;bottom:0;height:2px;width:100%;background:rgba(255,247,238,.18);}
.v6cs-progress-fill{height:100%;width:0;background:var(--pink, #FF7BA9);}
.v6cs-root.v6cs-out{pointer-events:none;}
.v6cs-root.v6cs-out .v6cs-bar{height:0;}
.v6cs-root.v6cs-out .v6cs-hint,.v6cs-root.v6cs-out .v6cs-skip,.v6cs-root.v6cs-out .v6cs-caption{opacity:0;}
/* HUD hides (CSS-only — hud.js untouched) while a cutscene plays. */
#ui.v6cs-active .g5-hud{opacity:0;pointer-events:none;transition:opacity .3s ease;}
@media (prefers-reduced-motion: reduce){
  .v6cs-bar,.v6cs-caption,.v6cs-hint{transition:none;}
  .v6cs-hint{animation:none;}
}
/* ── end V6/A1 ── */
`;

/** Dev-only breadcrumbs (recapOverlay.js pattern) — stripped from prod builds. */
const DEV = !!import.meta.env?.DEV;

/** @type {{store: object, ui: object, audio: object, sceneManager: object, assets: object}|null} */
let deps = null;

/** @type {{cleanup: () => void}|null} the single active run (one at a time) */
let activeRun = null;

/**
 * t() with the module-local fallback (G52 pattern) — A2 commits the
 * strings.js import pair for v6-cutscenes.js, so keys resolve through t()
 * once merged and through the owned dictionaries until then.
 * @param {string} key
 * @returns {string}
 */
function tx(key) {
  const v = t(key);
  if (v !== key) return v;
  const local = getLang() === 'de' ? CUT_DE : CUT_EN;
  return local[key] ?? key;
}

function injectCss() {
  if (document.querySelector('style[data-owner="v6-cutscene"]')) return;
  const style = document.createElement('style');
  style.dataset.owner = 'v6-cutscene';
  style.textContent = CSS;
  document.head.appendChild(style);
}

/** @returns {boolean} a cutscene is currently on screen */
export function isCutsceneActive() {
  return activeRun != null;
}

/**
 * Play an authored cutscene over the live home scene.
 * Resolves `true` after a completed/skipped playback (resources restored),
 * `false` when playback was REFUSED (unknown id, wrong scene, camera busy,
 * sleep flow, open screen, another cutscene) — callers skip silently.
 * @param {string} id data/cutscenes.js id
 * @param {{replay?: boolean}} [opts] force replay skip semantics (defaults
 *   to the persisted seen map: first view = hold-to-skip, replay = tap-skip)
 * @returns {Promise<boolean>}
 */
export async function playCutscene(id, opts = {}) {
  /** @param {string} why @returns {false} dev-visible refusal breadcrumb */
  const refuse = (why) => {
    if (DEV) console.info(`[cutscene] '${id}' refused: ${why}`);
    return false;
  };
  if (!deps) return false;
  if (activeRun) return refuse('another cutscene is active');
  const { store, ui, audio, sceneManager, assets } = deps;
  const script = getCutscene(id);
  if (!script) {
    console.warn(`[cutscene] unknown cutscene '${id}'`);
    return false;
  }
  // ---- camera-lease refusals (PLAN6 A1 acceptance) ----
  if (sceneManager.currentId() !== 'home') return refuse('not on the home scene');
  if (sceneManager.isSwitching()) return refuse('scene switch in flight');
  const camera = getCamera();
  const gooby = getGooby();
  const rm = getRoomManager();
  // The live home scene graph: Gooby's group is a direct child of it
  // (sceneManager keeps its instances private — §E6 spirit).
  const scene = gooby?.group?.parent ?? null;
  if (!camera || !gooby || !rm || !scene) return refuse('home handles not live yet');
  if (rm.isPanning?.()) return refuse('room pan in flight (camera lease)');
  if (isSleeping(store.get())) return refuse('sleep flow owns the scene');
  if (ui.activeScreenId?.()) return refuse('a screen is open');

  /** @type {ReturnType<typeof compileScript>} */
  let compiled;
  try {
    compiled = compileScript(script, { reducedMotion: prefersReducedMotion() });
  } catch (err) {
    console.warn(`[cutscene] '${id}' failed to compile — refusing:`, err);
    return false;
  }

  const replay = typeof opts.replay === 'boolean' ? opts.replay : hasSeen(store.get(), id);
  if (DEV) {
    console.info(
      `[cutscene] '${id}' starting (replay=${replay}, reducedMotion=${compiled.reducedMotion}, `
      + `lease=${camera.position.x.toFixed(2)},${camera.position.y.toFixed(2)},${camera.position.z.toFixed(2)})`,
    );
  }
  // Latch seen BEFORE playback: an interrupted first view never re-arms the
  // hold-to-skip gate (additive slice — vacation.js pattern, no version bump).
  store.update((s) => {
    s.cutscenes = markSeenSlice(s.cutscenes, id);
  });

  // ---- resource acquisition (each with a guarded release below) ----
  const lease = {
    pos: { x: camera.position.x, y: camera.position.y, z: camera.position.z },
    quat: {
      x: camera.quaternion.x,
      y: camera.quaternion.y,
      z: camera.quaternion.z,
      w: camera.quaternion.w,
    },
  };
  /** @type {{cancel: () => void}|null} */
  let cameraTween = null;
  /** @type {Map<string, object>} propId → spawned Object3D */
  const props = new Map();
  /** @type {ReturnType<typeof createParticles>|null} */
  let particles = null;
  /** @type {HTMLElement|null} */
  let overlay = null;
  let rafId = 0;
  let cleaned = false;

  /** ONE idempotent cleanup — every exit path funnels through here. */
  function cleanup() {
    if (cleaned) return;
    cleaned = true;
    activeRun = null;
    const safe = (label, fn) => {
      try {
        fn();
      } catch (err) {
        console.warn(`[cutscene] cleanup '${label}' failed:`, err);
      }
    };
    safe('raf', () => cancelAnimationFrame(rafId));
    safe('cameraTween', () => cameraTween?.cancel());
    safe('cameraRestore', () => {
      camera.position.set(lease.pos.x, lease.pos.y, lease.pos.z);
      camera.quaternion.set(lease.quat.x, lease.quat.y, lease.quat.z, lease.quat.w);
    });
    safe('props', () => {
      for (const obj of props.values()) obj.parent?.remove(obj);
      props.clear();
    });
    safe('particles', () => particles?.dispose());
    safe('gyro', () => {
      // Re-arm only while home still owns the scene — homeScene.exit() has
      // already detached listeners on any other path.
      if (sceneManager.currentId() === 'home' && !sceneManager.isSwitching()) {
        setGyroSceneActive(true);
      }
    });
    safe('music', () => musicDirector.popContext(VIEW.MUSIC_CONTEXT));
    safe('toasts', () => ui.releaseToasts?.());
    safe('hud', () => ui.el?.classList?.remove('v6cs-active'));
    safe('overlay', () => {
      if (!overlay) return;
      const el = overlay;
      overlay = null;
      if (prefersReducedMotion()) {
        el.remove();
        return;
      }
      el.classList.add('v6cs-out'); // pointer-events off instantly (CSS)
      setTimeout(() => el.remove(), VIEW.EXIT_MS);
    });
    if (DEV) {
      console.info(
        `[cutscene] '${id}' cleanup done (camera back to `
        + `${camera.position.x.toFixed(2)},${camera.position.y.toFixed(2)},${camera.position.z.toFixed(2)})`,
      );
    }
  }

  try {
    injectCss();
    musicDirector.pushContext(VIEW.MUSIC_CONTEXT);
    setGyroSceneActive(false);
    ui.holdToasts?.();
    ui.el?.classList?.add('v6cs-active');
    particles = createParticles(scene, { poolSize: VIEW.PARTICLE_POOL });

    // ---- overlay DOM (letterbox + caption + hint + skip + progress) ----
    overlay = document.createElement('div');
    overlay.className = `v6cs-root${replay ? ' v6cs-replay' : ''}`;
    overlay.innerHTML = `
      <div class="v6cs-bar v6cs-bar-top">
        <div class="v6cs-progress"><div class="v6cs-progress-fill"></div></div>
      </div>
      <div class="v6cs-bar v6cs-bar-bot"><div class="v6cs-caption"></div></div>
      <div class="v6cs-hint"></div>
      <button class="v6cs-skip" type="button">
        <span class="v6cs-skip-ring"></span><span class="v6cs-skip-label"></span>
      </button>`;
    ui.el.appendChild(overlay);
    const captionEl = overlay.querySelector('.v6cs-caption');
    const hintEl = overlay.querySelector('.v6cs-hint');
    const skipEl = overlay.querySelector('.v6cs-skip');
    const ringEl = overlay.querySelector('.v6cs-skip-ring');
    const fillEl = overlay.querySelector('.v6cs-progress-fill');
    hintEl.textContent = tx('cutscene.tapContinue');
    skipEl.querySelector('.v6cs-skip-label').textContent = tx(replay ? 'cutscene.skipTap' : 'cutscene.skipHold');
    requestAnimationFrame(() => overlay?.classList.add('v6cs-in')); // bars slide in

    // ---- op binding ----
    /** @param {object} op */
    function startCameraMove(op) {
      cameraTween?.cancel();
      cameraTween = null;
      const from = { x: camera.position.x, y: camera.position.y, z: camera.position.z };
      /** @type {{x: number, y: number, z: number}} */
      let to;
      if (op.move === 'restore') {
        to = { ...lease.pos };
      } else {
        // Dolly from the LEASED base toward Gooby so repeated moves never
        // compound past the focus point.
        const g = gooby.group.position;
        const focus = { x: g.x, y: g.y + VIEW.FOCUS_LIFT, z: g.z };
        const f = op.move === 'pushIn' ? VIEW.PUSH_FRACTION : -VIEW.PULL_FRACTION;
        to = {
          x: lease.pos.x + (focus.x - lease.pos.x) * f,
          y: lease.pos.y + (focus.y - lease.pos.y) * f,
          z: lease.pos.z + (focus.z - lease.pos.z) * f,
        };
      }
      if (op.duration <= 0) {
        camera.position.set(to.x, to.y, to.z); // reduced-motion instant cut
        return;
      }
      cameraTween = tween({
        duration: op.duration,
        ease: easings.easeInOutQuad,
        onUpdate: (v) => {
          camera.position.set(
            from.x + (to.x - from.x) * v,
            from.y + (to.y - from.y) * v,
            from.z + (to.z - from.z) * v,
          );
        },
      });
    }

    /** @param {object} op @returns {{x:number,y:number,z:number}} */
    function opPosition(op) {
      const anchored = op.anchor ? rm.getAnchor(op.anchor) : null;
      if (anchored) return anchored;
      const g = gooby.group.position;
      return { x: g.x, y: g.y + VIEW.BURST_LIFT, z: g.z };
    }

    /** @param {object} op */
    function spawnProp(op) {
      if (props.has(op.propId)) return;
      const obj = assets.getModel(op.model);
      if (!obj) return;
      const base = (op.anchor ? rm.getAnchor(op.anchor) : null) ?? gooby.group.position;
      const off = op.offset ?? [0, 0, 0];
      obj.position.set(base.x + off[0], base.y + off[1], base.z + off[2]);
      if (op.scale) obj.scale.setScalar(op.scale);
      scene.add(obj);
      props.set(op.propId, obj);
    }

    /**
     * The driver hook: binds each pure op to the real systems. `skipped`
     * ops (keepOnSkip replays during a skip) suppress motion — only state
     * ops (emotion/prop/sfx/caption-clear) act.
     * @param {object} op @param {{skipped: boolean}} info
     */
    function applyOp(op, info) {
      switch (op.op) {
        case 'camera':
          if (!info.skipped) startCameraMove(op);
          break;
        case 'clip':
          if (!info.skipped) gooby.play?.(op.clip)?.catch?.(() => {});
          break;
        case 'emotion':
          gooby.setEmotion?.(op.emotion);
          break;
        case 'particles':
          if (!info.skipped) particles?.emit(op.type, opPosition(op), { count: op.count });
          break;
        case 'caption':
          if (info.skipped) break;
          captionEl.textContent = tx(op.key);
          captionEl.classList.add('v6cs-caption-in');
          break;
        case 'captionClear':
          captionEl.classList.remove('v6cs-caption-in');
          break;
        case 'sfx':
          audio.play?.(op.sfx);
          break;
        case 'prop':
          if (op.action === 'spawn') spawnProp(op);
          else {
            const obj = props.get(op.propId);
            if (obj) {
              obj.parent?.remove(obj);
              props.delete(op.propId);
            }
          }
          break;
        default:
          break; // wait/tapWait/groups are pure timing — no driver action
      }
    }

    const player = createCutscenePlayer(compiled, { apply: applyOp }, { replay });
    activeRun = { cleanup };

    // ---- input wiring (overlay blocks the canvas per §E5/§E6) ----
    overlay.addEventListener('pointerdown', (e) => {
      if (e.target === skipEl || skipEl.contains(e.target)) return;
      player.tap();
    });
    skipEl.addEventListener('pointerdown', (e) => {
      e.stopPropagation();
      if (replay) player.skipTap();
      else player.skipHoldStart();
    });
    const endHold = (e) => {
      e?.stopPropagation?.();
      player.skipHoldEnd();
    };
    skipEl.addEventListener('pointerup', endHold);
    skipEl.addEventListener('pointercancel', endHold);
    skipEl.addEventListener('pointerleave', endHold);

    // ---- playback ----
    const done = new Promise((resolve) => player.onFinish(resolve));
    player.start();
    let last = performance.now();
    const frame = (now) => {
      const dt = Math.min((now - last) / 1000, 0.1);
      last = now;
      // Belt-and-braces: if the scene changed under us (should be impossible
      // with input blocked), hard-abort — no keepOnSkip on a dead scene.
      if (sceneManager.currentId() !== 'home') {
        player.cancel();
        return;
      }
      player.tick(dt);
      particles?.update(dt);
      hintEl.classList.toggle('v6cs-hint-on', player.isAwaitingTap());
      fillEl.style.width = `${Math.round(player.getProgress() * 100)}%`;
      if (!replay) {
        const deg = Math.round(player.getHoldProgress() * 360);
        ringEl.style.background = `conic-gradient(var(--pink, #FF7BA9) ${deg}deg, rgba(255,247,238,.28) ${deg}deg)`;
      }
      if (player.getState() !== 'done') rafId = requestAnimationFrame(frame);
    };
    rafId = requestAnimationFrame(frame);

    const reason = await done;
    if (DEV) console.info(`[cutscene] '${id}' finished (${reason})`);
    return true;
  } finally {
    cleanup();
  }
}

/**
 * Register the cutscene driver (main.js V6/A1 marked block). Also arms the
 * dev harness kick: `?cutscene=<id>` plays the script once the home scene
 * has entered (§E9 — the airportScreen ?vacation= pattern; unknown ids and
 * refused starts just warn). Exposed on window.__gooby via the debug handle
 * consumers already poke.
 * @param {{store: object, ui: object, audio: object, sceneManager: object, assets: object}} d
 */
export function initCutsceneView(d) {
  deps = d;
  injectCss();

  // Dev harness: ?cutscene=<id> (dev builds only, §E9 spirit).
  const param = DEV && typeof location !== 'undefined'
    ? new URLSearchParams(location.search).get('cutscene')
    : null;
  if (param) {
    deps.sceneManager.afterEnter((sceneId) => {
      if (sceneId !== 'home') return;
      if (!getCutscene(param)) {
        console.warn(`[cutscene] ?cutscene=${param} — unknown id`);
        return;
      }
      // Retry while the boot fade/pan settles (afterEnter fires before the
      // fade lifts, and SwiftShader VMs fade slowly — §E9 patience).
      let tries = 0;
      const attempt = () => {
        playCutscene(param).then((ok) => {
          if (ok) return;
          tries += 1;
          if (tries < VIEW.DEV_KICK_RETRIES) setTimeout(attempt, VIEW.DEV_KICK_DELAY_MS);
          else console.warn(`[cutscene] ?cutscene=${param} gave up after ${tries} busy retries`);
        });
      };
      setTimeout(attempt, VIEW.DEV_KICK_DELAY_MS);
    });
  }
}
