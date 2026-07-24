// V6/E2 — Funkelpark signature coaster: the scene/view (PLAN6 Wave E/E2).
// Renders the PURE simulation in coasterRide.logic.js 1:1 — an interactive
// cinematic park attraction on the single-coaster ruling (NOT an arcade
// game: no fail/score/payout/cover/game-count pin). E1's parkScene.js calls
// the FROZEN export startCoasterRide(ctx) — see
// /tmp/gooby-v6-handoffs/E2-exports-for-E1.txt.
//
// Build (budget: ≤90 draw calls, ≤60k tris — dev HUD proof via
// ?coasterhud=1): one InstancedMesh per (piece-type × submesh) for the 28
// toy-car-kit track pieces, instanced support columns/clamps auto-placed
// under elevated track, a vertex-gradient sky dome + one ground disc + one
// instanced tree-silhouette ring, two procedural rounded carts with Gooby
// (sitDrive clip) in front, and the committed gate GLBs as station arch +
// photo gantry.
//
// Sequencing: SELF-DRIVEN (justified in coasterRide.logic.js — the ride is
// one continuous spline camera move the cutscene director's op vocabulary
// cannot express without editing A1's owned file). The overlay mirrors
// cutsceneView.js chrome semantics: caption bar, hold-to-skip ring
// (COASTER.HOLD_SKIP_SEC = CUTSCENE.HOLD_SKIP_SEC), watchdog force-finish
// in the logic. Reduced motion rides static exterior shots (never the loop
// POV). Audio is existing sfxMap ids only + the 'arcade' medley context.

import * as THREE from 'three';
import { t, getLang } from '../data/strings.js';
// V6/E2: strings.js is frozen — E1 commits the v6-park import pair; until
// then park.coaster.* keys resolve through the local tx() fallback (E3's
// parkStall.js pattern; the caption block already lives in v6-park.js).
import { EN as PARK_EN, DE as PARK_DE } from '../data/strings/v6-park.js';
import { createGooby } from '../character/gooby.js';
import { applyEquippedOutfits } from '../character/outfitAttach.js';
import { createParticles } from '../gfx/particles.js';
import { prefersReducedMotion } from '../ui/ui.js';
import musicDirector from '../audio/musicDirector.js';
import * as photoStore from '../core/photoStore.js';
import { mirrorSlice } from '../systems/gallery.logic.js';
import { now } from '../core/clock.js';
import {
  COASTER,
  createRide,
  stepRide,
  skipRide,
  cartPoseAt,
  cameraPose,
} from './coasterRide.logic.js';
import {
  TRACK_PIECES,
  SUPPORTS,
  PIECE_MODEL_KEYS,
  DIRS,
  ROAD_Y_OFFSET,
  computeSupports,
  pointAt,
} from './trackPieces.js';

const S = COASTER.WORLD_SCALE; // track units → world meters

/** Preload keys (sceneManager preloads between factory and enter — §E1). */
export const COASTER_ASSET_KEYS = Object.freeze([
  ...PIECE_MODEL_KEYS,
  'toy-car-kit/gate',
  'toy-car-kit/gate-finish',
]);

/** t() first, then the owned v6-park EN/DE table (parkStall tx() pattern). */
function tx(key) {
  const v = t(key);
  if (v !== key) return v;
  return (getLang() === 'de' ? PARK_DE : PARK_EN)[key] ?? key;
}

/** Cue id → sfxMap id (existing ids only — verified against sfxMap.js). */
const CUE_SFX = Object.freeze({
  board: 'gooby.squeakHappy',
  drop: 'gooby.gasp',
  loop: 'whoosh',
  hills: 'gooby.squeakHappy',
  brake: 'whoosh',
});

/** View-only pacing/looks (§E0.1-2: frozen here). */
const VIEW = Object.freeze({
  FOV_BASE: 58,
  FOV_KICK: 8, //             + at VMAX (speed rush)
  CAPTION_SEC: 3,
  HINT_SEC: 2.6,
  CLANK_EVERY_SEC: 0.55, //   chain-lift clank cadence
  WIND_EVERY_SEC: 0.9, //     air-rush cadence above WIND_MIN_V
  WIND_MIN_V: 5.5,
  DONE_HOLD_SEC: 1.6, //      arrival caption dwell before onDone
  ARMS_UP_RAD: 1.3, //        extra arm raise when hands are up
  ARMS_LERP: 6,
  CART_COLORS: Object.freeze([0xf2668b, 0x6fb7e8]),
  SKY_TOP: 0x7ec8f2,
  SKY_HORIZON: 0xffe8cf,
  GROUND: 0xa8d98a,
  TREE_RING: 46,
});

/** Scoped overlay chrome (own v6co- prefix — cutsceneView CSS precedent). */
const OVERLAY_CSS = `
.v6co-root{position:fixed;inset:0;z-index:60;pointer-events:auto;font-family:inherit;user-select:none;-webkit-user-select:none;touch-action:none;}
.v6co-caption{position:absolute;left:50%;bottom:calc(var(--safe-bottom, 0px) + 3.4rem);transform:translateX(-50%) translateY(0.375rem);max-width:24rem;padding:0 1rem;color:#FFF7EE;font-size:1rem;font-weight:800;line-height:1.35;text-align:center;text-shadow:0 2px 8px rgba(0,0,0,.45);opacity:0;transition:opacity .25s ease,transform .25s ease;}
.v6co-caption.v6co-in{opacity:1;transform:translateX(-50%);}
.v6co-hint{position:absolute;left:50%;bottom:calc(var(--safe-bottom, 0px) + 1.1rem);transform:translateX(-50%);padding:0.375rem 0.875rem;border-radius:999px;background:rgba(23,18,16,.6);color:#FFF7EE;font-size:0.75rem;font-weight:800;white-space:nowrap;opacity:0;transition:opacity .3s ease;}
.v6co-hint.v6co-in{opacity:1;}
.v6co-skip{position:absolute;top:calc(var(--safe-top, 0px) + 0.5rem);right:max(0.75rem, var(--safe-right, 0px));min-width:44px;min-height:44px;display:inline-flex;align-items:center;gap:0.5rem;padding:0.375rem 0.75rem;border:none;border-radius:999px;background:rgba(23,18,16,.72);color:#FFF7EE;font-family:inherit;font-size:0.75rem;font-weight:800;cursor:pointer;-webkit-tap-highlight-color:transparent;}
.v6co-skip:active{transform:scale(.96);}
.v6co-skip-ring{width:1rem;height:1rem;border-radius:50%;background:conic-gradient(var(--pink, #FF7BA9) 0deg, rgba(255,247,238,.28) 0deg);flex:none;}
.v6co-flash{position:absolute;inset:0;background:#fff;opacity:0;pointer-events:none;transition:opacity .5s ease-out;}
.v6co-flash.v6co-on{transition:none;opacity:1;}
.v6co-hud{position:absolute;top:calc(var(--safe-top, 0px) + 0.5rem);left:0.75rem;padding:0.25rem 0.5rem;background:rgba(0,0,0,.55);color:#9CF29C;font:11px/1.5 ui-monospace,monospace;border-radius:0.375rem;white-space:pre;pointer-events:none;}
@media (prefers-reduced-motion: reduce){.v6co-caption,.v6co-hint,.v6co-flash{transition:none;}}
`;

/** Deterministic 0…1 hash for silhouette scatter (visual only, seeded). */
function hash01(i) {
  const x = Math.sin(i * 127.1 + 311.7) * 43758.5453;
  return x - Math.floor(x);
}

/**
 * §E1 scene factory — registered by startCoasterRide under 'coasterRide'.
 * @param {{renderer: object, assets: object, audio: object, store: object,
 *   ui: object}} ctx sceneManager switch context
 */
export function createCoasterRideScene(ctx) {
  const { renderer, assets, audio, store } = ctx;
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(VIEW.FOV_BASE, innerWidth / innerHeight, 0.1, 700);

  /** @type {THREE.BufferGeometry[]} */
  const ownedGeos = [];
  /** @type {THREE.Material[]} */
  const ownedMats = [];
  const own = (mesh) => {
    if (mesh.geometry) ownedGeos.push(mesh.geometry);
    for (const m of Array.isArray(mesh.material) ? mesh.material : [mesh.material]) {
      if (m) ownedMats.push(m);
    }
    return mesh;
  };

  const self = {
    scene,
    camera,
    ride: null,
    params: null,
    gooby: null,
    particles: null,
    train: [],
    overlay: null,
    styleEl: null,
    captionEl: null,
    hintEl: null,
    skipEl: null,
    ringEl: null,
    flashEl: null,
    hudEl: null,
    holding: false,
    skipHolding: false,
    skipHoldT: 0,
    armsUpK: 0,
    clankT: 0,
    windT: 0,
    captionT: 0,
    hintT: 0,
    hudT: 0,
    doneT: -1,
    doneFired: false,
    musicPushed: false,
    disposed: false,
    listeners: [],

    enter(params = {}) {
      this.params = params;
      const reducedMotion = params.reducedMotion ?? prefersReducedMotion();
      this.ride = createRide({ reducedMotion });

      // ---- sky: vertex-gradient dome (1 draw) + fog + light ----
      scene.fog = new THREE.Fog(VIEW.SKY_HORIZON, 120, 420);
      const skyGeo = new THREE.SphereGeometry(320, 24, 12);
      const top = new THREE.Color(VIEW.SKY_TOP);
      const horizon = new THREE.Color(VIEW.SKY_HORIZON);
      const pos = skyGeo.getAttribute('position');
      const colors = new Float32Array(pos.count * 3);
      const mix = new THREE.Color();
      for (let i = 0; i < pos.count; i += 1) {
        const k = Math.min(1, Math.max(0, pos.getY(i) / 320));
        mix.copy(horizon).lerp(top, Math.pow(k, 0.55));
        colors[i * 3] = mix.r;
        colors[i * 3 + 1] = mix.g;
        colors[i * 3 + 2] = mix.b;
      }
      skyGeo.setAttribute('color', new THREE.BufferAttribute(colors, 3));
      const sky = own(new THREE.Mesh(
        skyGeo,
        new THREE.MeshBasicMaterial({ vertexColors: true, side: THREE.BackSide, fog: false })
      ));
      scene.add(sky);
      scene.add(new THREE.HemisphereLight(0xfff7ea, 0xb9d9a4, 1.05));
      const sun = new THREE.DirectionalLight(0xfff2dd, 0.85);
      sun.position.set(40, 90, -60);
      scene.add(sun);

      // ---- ground disc + distant park silhouettes (3 draws) ----
      const ground = own(new THREE.Mesh(
        new THREE.CircleGeometry(360, 40),
        new THREE.MeshStandardMaterial({ color: VIEW.GROUND, roughness: 1 })
      ));
      ground.rotation.x = -Math.PI / 2;
      ground.position.y = -0.02;
      scene.add(ground);

      const treeGeo = new THREE.ConeGeometry(2.6, 7, 7);
      const treeMat = new THREE.MeshStandardMaterial({ color: 0x7cc19a, roughness: 1 });
      ownedGeos.push(treeGeo);
      ownedMats.push(treeMat);
      const trees = new THREE.InstancedMesh(treeGeo, treeMat, VIEW.TREE_RING);
      const m4 = new THREE.Matrix4();
      // ring around the track's rough center (the walk spans x −36…0, z −6…24)
      const cx = -18 * S;
      const cz = 9 * S;
      for (let i = 0; i < VIEW.TREE_RING; i += 1) {
        const ang = (i / VIEW.TREE_RING) * Math.PI * 2;
        const rad = (95 + hash01(i) * 60);
        const sc = 0.8 + hash01(i + 99) * 1.4;
        m4.makeScale(sc, sc * (0.8 + hash01(i + 7) * 0.6), sc);
        m4.setPosition(cx + Math.cos(ang) * rad, 3.4 * sc, cz + Math.sin(ang) * rad);
        trees.setMatrixAt(i, m4);
      }
      trees.instanceMatrix.needsUpdate = true;
      trees.frustumCulled = false;
      scene.add(trees);
      this.trees = trees;

      // ---- the track: InstancedMesh per (piece type × submesh) ----
      const assembly = this.ride.assembly;
      const byType = new Map();
      for (const piece of assembly.pieces) {
        if (!byType.has(piece.type)) byType.set(piece.type, []);
        byType.get(piece.type).push(piece);
      }
      const pieceMatrix = (piece) => {
        const d = DIRS[piece.dir];
        const off = piece.originOffset ?? 0;
        const m = new THREE.Matrix4();
        m.compose(
          new THREE.Vector3(
            (piece.x + d[0] * off) * S,
            (piece.y + ROAD_Y_OFFSET) * S,
            (piece.z + d[1] * off) * S
          ),
          new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 1, 0), piece.rotY),
          new THREE.Vector3(S, S, S)
        );
        return m;
      };
      this.trackMeshes = [];
      for (const [type, pieces] of byType) {
        const def = TRACK_PIECES[type];
        const model = assets.getModel(`toy-car-kit/${def.model}`);
        model.updateMatrixWorld(true);
        const subs = [];
        model.traverse((obj) => {
          if (obj.isMesh) subs.push(obj);
        });
        for (const sub of subs) {
          // geometry/material are shared asset-cache masters — never disposed
          const inst = new THREE.InstancedMesh(sub.geometry, sub.material, pieces.length);
          for (let i = 0; i < pieces.length; i += 1) {
            const m = pieceMatrix(pieces[i]).multiply(sub.matrixWorld);
            inst.setMatrixAt(i, m);
          }
          inst.instanceMatrix.needsUpdate = true;
          inst.frustumCulled = false;
          scene.add(inst);
          this.trackMeshes.push(inst);
        }
      }

      // ---- supports: instanced columns + clamps under elevated track ----
      const supports = computeSupports(assembly);
      const placeSupportSet = (key, place) => {
        const model = assets.getModel(`toy-car-kit/${key}`);
        model.updateMatrixWorld(true);
        const subs = [];
        model.traverse((obj) => {
          if (obj.isMesh) subs.push(obj);
        });
        for (const sub of subs) {
          const inst = new THREE.InstancedMesh(sub.geometry, sub.material, supports.length);
          for (let i = 0; i < supports.length; i += 1) {
            inst.setMatrixAt(i, place(supports[i]).multiply(sub.matrixWorld));
          }
          inst.instanceMatrix.needsUpdate = true;
          inst.frustumCulled = false;
          scene.add(inst);
          this.trackMeshes.push(inst);
        }
      };
      // column: 1×1×1 base-origin block stretched to just under the rails
      placeSupportSet(SUPPORTS.column, (sup) => new THREE.Matrix4().compose(
        new THREE.Vector3(sup.p[0] * S, 0, sup.p[2] * S),
        new THREE.Quaternion(),
        new THREE.Vector3(0.55 * S, Math.max(0.05, sup.h - 0.28) * S, 0.55 * S)
      ));
      // clamp: cradles the track underside, aligned to the rail heading
      placeSupportSet(SUPPORTS.clamp, (sup) => {
        const smp = nearestTangent(assembly, sup);
        return new THREE.Matrix4().compose(
          new THREE.Vector3(sup.p[0] * S, (sup.h - 0.28) * S, sup.p[2] * S),
          new THREE.Quaternion().setFromAxisAngle(
            new THREE.Vector3(0, 1, 0),
            Math.atan2(smp[0], smp[1])
          ),
          new THREE.Vector3(S, S, S)
        );
      });

      // ---- station arch + photo gantry (committed gate GLBs) ----
      const placeGate = (key, s, scale) => {
        const smp = pointAt(assembly, s);
        const gate = assets.getModel(`toy-car-kit/${key}`);
        gate.position.set(smp.p[0] * S, smp.p[1] * S, smp.p[2] * S);
        gate.rotation.y = Math.atan2(smp.t[0], smp.t[2]);
        gate.scale.setScalar(S * scale);
        scene.add(gate);
        return gate;
      };
      this.gates = [
        placeGate('gate', 2, 0.82),
        placeGate('gate-finish', this.ride.photoS, 0.82),
      ];
      // station platform slab beside the boarding straight
      const stationPose = pointAt(assembly, 2);
      const platform = own(new THREE.Mesh(
        new THREE.BoxGeometry(1.4 * S, 0.24 * S, 4 * S),
        new THREE.MeshStandardMaterial({ color: 0xf2c14e, roughness: 0.9 })
      ));
      platform.position.set(
        (stationPose.p[0] + 1.15) * S,
        0.12 * S,
        stationPose.p[2] * S
      );
      scene.add(platform);
      this.platform = platform;

      // ---- the 2-cart train + Gooby up front (sitDrive) ----
      const wheelGeo = new THREE.SphereGeometry(0.09 * S, 10, 8);
      const wheelMat = new THREE.MeshStandardMaterial({ color: 0x4a3b36, roughness: 0.6 });
      ownedGeos.push(wheelGeo);
      ownedMats.push(wheelMat);
      for (let c = 0; c < 2; c += 1) {
        const cart = new THREE.Group();
        const hull = own(new THREE.Mesh(
          new THREE.SphereGeometry(0.5 * S, 20, 14),
          new THREE.MeshStandardMaterial({ color: VIEW.CART_COLORS[c], roughness: 0.45 })
        ));
        hull.scale.set(0.74, 0.5, 1.05);
        hull.position.y = 0.22 * S;
        cart.add(hull);
        const inset = own(new THREE.Mesh(
          new THREE.BoxGeometry(0.5 * S, 0.16 * S, 0.72 * S),
          new THREE.MeshStandardMaterial({ color: 0x4a3b36, roughness: 0.8 })
        ));
        inset.position.y = 0.34 * S;
        cart.add(inset);
        const wheels = new THREE.InstancedMesh(wheelGeo, wheelMat, 4);
        const wm = new THREE.Matrix4();
        const corners = [[-0.3, 0.35], [0.3, 0.35], [-0.3, -0.35], [0.3, -0.35]];
        for (let i = 0; i < 4; i += 1) {
          wm.makeTranslation(corners[i][0] * S, 0.05 * S, corners[i][1] * S);
          wheels.setMatrixAt(i, wm);
        }
        wheels.instanceMatrix.needsUpdate = true;
        cart.add(wheels);
        scene.add(cart);
        this.train.push(cart);
      }
      this.gooby = createGooby();
      applyEquippedOutfits(this.gooby);
      this.gooby.group.scale.setScalar(0.62);
      this.gooby.group.position.set(0, 0.3 * S, -0.08 * S);
      this.gooby.setEmotion('happy');
      this.gooby.play?.('wave')?.catch?.(() => {});
      this.train[0].add(this.gooby.group);
      this.armGrpL = this.gooby.group.getObjectByName('armGrpL') ?? null;
      this.armGrpR = this.gooby.group.getObjectByName('armGrpR') ?? null;

      this.particles = createParticles(scene);

      // ---- overlay chrome (caption / hint / hold-to-skip / flash / HUD) ----
      this.styleEl = document.createElement('style');
      this.styleEl.textContent = OVERLAY_CSS;
      document.head.appendChild(this.styleEl);
      const overlay = document.createElement('div');
      overlay.className = 'v6co-root';
      overlay.innerHTML = `
        <div class="v6co-caption"></div>
        <div class="v6co-hint"></div>
        <button class="v6co-skip" type="button">
          <span class="v6co-skip-ring"></span><span class="v6co-skip-label"></span>
        </button>
        <div class="v6co-flash"></div>`;
      document.body.appendChild(overlay);
      this.overlay = overlay;
      this.captionEl = overlay.querySelector('.v6co-caption');
      this.hintEl = overlay.querySelector('.v6co-hint');
      this.skipEl = overlay.querySelector('.v6co-skip');
      this.ringEl = overlay.querySelector('.v6co-skip-ring');
      this.flashEl = overlay.querySelector('.v6co-flash');
      this.skipEl.querySelector('.v6co-skip-label').textContent = tx('cutscene.skipHold');
      this.hintEl.textContent = tx('park.coaster.handsUpHint');

      const listen = (target, ev, fn, opts) => {
        target.addEventListener(ev, fn, opts);
        this.listeners.push(() => target.removeEventListener(ev, fn, opts));
      };
      // hold anywhere = hands up (the skip button holds the skip ring instead)
      listen(overlay, 'pointerdown', (e) => {
        if (e.target === this.skipEl || this.skipEl.contains(e.target)) return;
        this.holding = true;
      });
      listen(this.skipEl, 'pointerdown', (e) => {
        e.preventDefault();
        this.skipHolding = true;
      });
      listen(window, 'pointerup', () => {
        this.holding = false;
        this.skipHolding = false;
      });
      listen(window, 'pointercancel', () => {
        this.holding = false;
        this.skipHolding = false;
      });

      // dev draw-call HUD (?coasterhud=1 — the ≤90-calls budget proof)
      if (import.meta.env.DEV && params.hud) {
        this.hudEl = document.createElement('div');
        this.hudEl.className = 'v6co-hud';
        overlay.appendChild(this.hudEl);
      }

      // funfair energy from the existing medley (no new audio assets)
      try {
        musicDirector.pushContext('arcade');
        this.musicPushed = true;
      } catch { /* music is optional */ }

      // park scale: place the camera before the first render (no origin pop)
      this.applyCamera(cameraPose(this.ride));

      // dev probe (the __roadtest/__recapPreview precedent — CDP evidence)
      if (import.meta.env.DEV) window.__coaster = this;
    },

    /** Per-frame camera drive from the pure pose model. */
    applyCamera(pose) {
      camera.position.set(pose.p[0] * S, pose.p[1] * S, pose.p[2] * S);
      camera.up.set(pose.up[0], pose.up[1], pose.up[2]);
      camera.lookAt(pose.look[0] * S, pose.look[1] * S, pose.look[2] * S);
      const fov = VIEW.FOV_BASE + VIEW.FOV_KICK * pose.fov01 * pose.fov01;
      if (Math.abs(fov - camera.fov) > 0.05) {
        camera.fov = fov;
        camera.updateProjectionMatrix();
      }
    },

    /** Show a caption via tx() with the standard auto-clear dwell. */
    showCaption(key) {
      this.captionEl.textContent = tx(key);
      this.captionEl.classList.add('v6co-in');
      this.captionT = VIEW.CAPTION_SEC;
    },

    /** The classic ride photo: gantry-POV captureFrame → photo gallery. */
    async takeSouvenir() {
      audio?.play?.('photo.shutter');
      this.flashEl.classList.add('v6co-on');
      requestAnimationFrame(() => this.flashEl?.classList.remove('v6co-on'));
      const sm = this.params?.sceneManager;
      if (!sm?.captureFrame) return;
      try {
        // one frame from the photo gantry looking back at the train (the
        // RAF loop restores the chase cam right after — invisible blip)
        const pose = cartPoseAt(this.ride.assembly, this.ride.s);
        camera.position.set(
          (pose.p[0] + pose.t[0] * 4.2) * S,
          (pose.p[1] + 1.15) * S,
          (pose.p[2] + pose.t[2] * 4.2) * S
        );
        camera.up.set(0, 1, 0);
        camera.lookAt(pose.p[0] * S, (pose.p[1] + 0.5) * S, pose.p[2] * S);
        const blob = await sm.captureFrame();
        if (!blob) return;
        const res = await photoStore.add(blob, {
          at: now(),
          w: renderer?.domElement?.width ?? innerWidth,
          h: renderer?.domElement?.height ?? innerHeight,
          frame: 'coasterRide',
        });
        if (res.ok && store) {
          // mirror the gallery slice exactly like photoMode's persist path
          const total = await photoStore.count();
          store.update((state) => {
            const g = state.gallery ?? { count: 0, lastAddedAt: 0, hintShown: false };
            state.gallery = { hintShown: g.hintShown === true, ...mirrorSlice(total, res.meta.at) };
          });
          store.emit?.('galleryChanged', { id: res.id });
          this.showCaption('park.coaster.photoSaved');
        }
      } catch (err) {
        console.warn('[coasterRide] souvenir failed:', err?.message);
      }
    },

    /** Route one pure ride event to chrome/audio/particles. */
    handleEvent(event) {
      switch (event.type) {
        case 'cue':
          this.showCaption(event.captionKey);
          if (CUE_SFX[event.id]) audio?.play?.(CUE_SFX[event.id]);
          break;
        case 'depart':
          audio?.play?.('pipe.rotate'); // restraint clunk
          this.gooby?.play?.('sitDrive')?.catch?.(() => {});
          break;
        case 'photo':
          this.takeSouvenir();
          break;
        case 'windowEnter':
          this.hintEl.classList.add('v6co-in');
          this.hintT = VIEW.HINT_SEC;
          break;
        case 'windowExit':
          this.hintEl.classList.remove('v6co-in');
          this.hintT = 0;
          break;
        case 'sparkle': {
          const pose = cartPoseAt(this.ride.assembly, this.ride.s);
          this.particles?.emit('sparkles', {
            x: (pose.p[0] + pose.up[0] * 0.6) * S,
            y: (pose.p[1] + pose.up[1] * 0.6) * S,
            z: (pose.p[2] + pose.up[2] * 0.6) * S,
          }, { count: 2 });
          break;
        }
        case 'wheee':
          audio?.play?.('gooby.squeakHappy');
          break;
        case 'skipped':
          this.flashEl.classList.add('v6co-on');
          requestAnimationFrame(() => this.flashEl?.classList.remove('v6co-on'));
          break;
        case 'arrived':
          audio?.play?.('jingle.arrival');
          this.gooby?.play?.('happyBounce')?.catch?.(() => {});
          this.doneT = VIEW.DONE_HOLD_SEC;
          break;
        default:
          break;
      }
    },

    /** onDone(ctx) exactly once (default: back home). */
    finish() {
      if (this.doneFired) return;
      this.doneFired = true;
      const { onDone, sceneManager } = this.params ?? {};
      const done = () => {
        if (typeof onDone === 'function') {
          return onDone({ sceneManager, store, ui: ctx.ui });
        }
        return sceneManager?.switchTo?.('home');
      };
      Promise.resolve()
        .then(done)
        .catch((err) => console.error('[coasterRide] onDone failed:', err));
    },

    update(dt) {
      if (!this.ride || this.disposed) return;
      const ride = this.ride;

      // ---- pure sim step + event routing ----
      const holdingHands = this.holding && !this.skipHolding;
      for (const event of stepRide(ride, dt, { holding: holdingHands })) {
        this.handleEvent(event);
      }

      // ---- hold-to-skip ring (CUTSCENE.HOLD_SKIP_SEC semantics) ----
      if (ride.phase !== 'done' && !ride.skipped) {
        if (this.skipHolding) this.skipHoldT += dt;
        else this.skipHoldT = Math.max(0, this.skipHoldT - dt * 2);
        const frac = Math.min(1, this.skipHoldT / COASTER.HOLD_SKIP_SEC);
        this.ringEl.style.background =
          `conic-gradient(var(--pink, #FF7BA9) ${frac * 360}deg, rgba(255,247,238,.28) 0deg)`;
        if (frac >= 1) {
          this.skipHoldT = 0;
          this.skipHolding = false;
          for (const event of skipRide(ride)) this.handleEvent(event);
        }
      } else {
        this.skipEl.style.display = 'none';
      }

      // ---- zone sound beds: lift clank + air rush ----
      if (ride.phase === 'riding') {
        const inLift = ride.s >= ride.zones.lift.s0 && ride.s < ride.zones.crest.s1;
        if (inLift) {
          this.clankT += dt;
          if (this.clankT >= VIEW.CLANK_EVERY_SEC) {
            this.clankT -= VIEW.CLANK_EVERY_SEC;
            audio?.play?.('pipe.rotate');
          }
        }
        if (ride.v > VIEW.WIND_MIN_V) {
          this.windT += dt;
          if (this.windT >= VIEW.WIND_EVERY_SEC) {
            this.windT -= VIEW.WIND_EVERY_SEC;
            audio?.play?.('rocket.wind');
          }
        }
      }

      // ---- chrome timers ----
      if (this.captionT > 0) {
        this.captionT -= dt;
        if (this.captionT <= 0) this.captionEl.classList.remove('v6co-in');
      }
      if (this.hintT > 0) {
        this.hintT -= dt;
        if (this.hintT <= 0) this.hintEl.classList.remove('v6co-in');
      }

      // ---- train + Gooby ----
      const basis = new THREE.Matrix4();
      const xAxis = new THREE.Vector3();
      const yAxis = new THREE.Vector3();
      const zAxis = new THREE.Vector3();
      for (let c = 0; c < this.train.length; c += 1) {
        // negative s wraps behind the station joint (pointAt wraps) — the
        // rear cart trails the front one across the closure seam too
        const sCart = ride.s - c * COASTER.CART_GAP;
        const pose = cartPoseAt(ride.assembly, sCart);
        zAxis.set(pose.t[0], pose.t[1], pose.t[2]);
        yAxis.set(pose.up[0], pose.up[1], pose.up[2]);
        xAxis.crossVectors(yAxis, zAxis).normalize();
        basis.makeBasis(xAxis, yAxis, zAxis);
        const cart = this.train[c];
        cart.quaternion.setFromRotationMatrix(basis);
        cart.position.set(
          (pose.p[0] + pose.up[0] * 0.05) * S,
          (pose.p[1] + pose.up[1] * 0.05) * S,
          (pose.p[2] + pose.up[2] * 0.05) * S
        );
      }
      this.gooby?.update(dt);
      // hands-up on top of the seated clip (post-update arm override)
      const wantArms = holdingHands && ride.activeWindow != null ? 1 : 0;
      this.armsUpK += (wantArms - this.armsUpK) * Math.min(1, dt * VIEW.ARMS_LERP);
      if (this.armGrpL && this.armsUpK > 0.01) {
        this.armGrpL.rotation.x -= this.armsUpK * VIEW.ARMS_UP_RAD;
        this.armGrpR.rotation.x -= this.armsUpK * VIEW.ARMS_UP_RAD;
        this.armGrpL.rotation.z -= this.armsUpK * 0.35;
        this.armGrpR.rotation.z += this.armsUpK * 0.35;
      }
      this.particles?.update(dt);

      // ---- camera (chase with clamped roll / reduced-motion static shots) ----
      this.applyCamera(cameraPose(ride));

      // ---- dev draw-call HUD ----
      if (this.hudEl) {
        this.hudT += dt;
        if (this.hudT >= 0.5) {
          this.hudT = 0;
          const info = renderer?.info?.render;
          this.hudEl.textContent =
            `calls ${info?.calls ?? '?'}\ntris  ${info?.triangles ?? '?'}\nv ${ride.v.toFixed(1)} s ${ride.s.toFixed(0)}/${ride.assembly.totalLen.toFixed(0)}`;
        }
      }

      // ---- arrival → onDone handoff ----
      if (this.doneT > 0) {
        this.doneT -= dt;
        if (this.doneT <= 0) this.finish();
      }
    },

    exit() {
      // sceneManager calls dispose() right after — nothing extra here
    },

    dispose() {
      this.disposed = true;
      if (import.meta.env.DEV && window.__coaster === this) delete window.__coaster;
      for (const off of this.listeners.splice(0)) off();
      this.overlay?.remove();
      this.styleEl?.remove();
      this.overlay = null;
      this.styleEl = null;
      this.hudEl = null;
      try {
        this.gooby?.dispose();
      } catch { /* gooby own-resource release only */ }
      this.gooby = null;
      try {
        this.particles?.dispose();
      } catch { /* pool release */ }
      this.particles = null;
      for (const geo of ownedGeos.splice(0)) geo.dispose?.();
      for (const mat of ownedMats.splice(0)) {
        mat.map?.dispose?.();
        mat.dispose?.();
      }
      // InstancedMesh instance attributes (shared masters stay untouched —
      // the sceneManager sweep skips assets.isCachedResource resources)
      for (const inst of this.trackMeshes ?? []) inst.dispose?.();
      this.trackMeshes = null;
      if (this.musicPushed) {
        try {
          musicDirector.popContext('arcade');
        } catch { /* already popped */ }
        this.musicPushed = false;
      }
    },
  };

  return self;
}

/** Horizontal tangent (x, z) of the spline point nearest a support foot. */
function nearestTangent(assembly, sup) {
  let best = [0, 1];
  let bestD = Infinity;
  for (let s = 0; s < assembly.totalLen; s += SUPPORTS.SPACING / 2) {
    const smp = pointAt(assembly, s);
    const d = Math.hypot(smp.p[0] - sup.p[0], smp.p[2] - sup.p[2]);
    if (d < bestD) {
      bestD = d;
      best = [smp.t[0], smp.t[2]];
    }
  }
  return best;
}

/**
 * FROZEN E1 integration export (PLAN6 Wave E integration contract — see
 * /tmp/gooby-v6-handoffs/E2-exports-for-E1.txt). Registers the 'coasterRide'
 * scene (idempotent) and switches into it; the ride calls ctx.onDone exactly
 * once when the train is back in the station (default: switchTo('home')).
 * @param {{sceneManager: object, store?: object, audio?: object,
 *   assets?: object, ui?: object, onDone?: (ctx: object) => void|Promise,
 *   reducedMotion?: boolean, hud?: boolean}} ctx
 * @returns {Promise<boolean>} true when the switch into the ride completed
 */
export async function startCoasterRide(ctx) {
  const sm = ctx?.sceneManager;
  if (!sm || typeof sm.register !== 'function' || typeof sm.switchTo !== 'function') {
    console.warn('[coasterRide] startCoasterRide needs ctx.sceneManager');
    return false;
  }
  if (sm.isSwitching?.()) return false;
  if (!(sm.has?.('coasterRide'))) {
    sm.register('coasterRide', createCoasterRideScene, [...COASTER_ASSET_KEYS]);
  }
  try {
    await sm.switchTo('coasterRide', {
      onDone: ctx.onDone,
      reducedMotion: ctx.reducedMotion,
      hud: ctx.hud === true,
      sceneManager: sm,
    });
    return true;
  } catch (err) {
    console.error('[coasterRide] failed to start:', err);
    return false;
  }
}

// ---- TEMPORARY dev kick — E1: delete this block when the park hub lands ----
// Until E1's parkScene + harness row exist, nothing imports this module. Dev
// test flow (documented in the E2 handoff): load
//   http://127.0.0.1:5173/?coaster=1[&rm=1][&coasterhud=1]
// then dynamic-import once from the console/CDP:
//   await import('/src/park/coasterRide.js')
// The kick below waits for the harness handle and rides immediately.
if (import.meta.env.DEV && typeof window !== 'undefined'
  && new URLSearchParams(location.search).get('coaster') === '1') {
  const q = new URLSearchParams(location.search);
  let kickTries = 0;
  const arm = () => {
    const g = window.__gooby;
    // startCoasterRide refuses while the boot home-switch is still in
    // flight — keep retrying until the manager is idle (bounded)
    if (!g?.sceneManager || g.sceneManager.isSwitching?.()) {
      kickTries += 1;
      if (kickTries < 100) setTimeout(arm, 300);
      return;
    }
    startCoasterRide({
      sceneManager: g.sceneManager,
      store: g.store,
      ui: g.ui,
      reducedMotion: q.get('rm') === '1' ? true : undefined,
      hud: q.get('coasterhud') === '1',
    }).then((ok) => {
      if (!ok) {
        kickTries += 1;
        if (kickTries < 100) setTimeout(arm, 300);
        else console.warn('[coasterRide] dev kick: ride refused to start');
      }
    });
  };
  arm();
}
// ---- end TEMPORARY dev kick ----
