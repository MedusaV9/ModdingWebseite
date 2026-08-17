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
  /** V6 fix P0-1: boarding plays in ≤3 s of real time (the logic's
   * BOARD_SEC clock is scaled in update() — physics/timeline untouched). */
  BOARD_SEC_VIEW: 3,
  HOP_START_SEC: 0.25, //     Gooby waits a beat on the platform…
  HOP_SEC: 0.85, //           …then hops into the front cart (arc)
  HOP_ARC_M: 0.8,
  BOUNCE_SEC: 1.2, //         damped cart bounce after the landing
  BOUNCE_AMP_M: 0.085,
  /** V6 fix P0-1: portrait boarding shot (track units) — the logic's SHOT_*
   * station frame is landscape-composed and clips the cart on a 390-wide
   * portrait view; this VIEW pose centers the cart + Gooby's hop and blends
   * into cameraPose()'s own station→chase move after departure. */
  BOARD_CAM_SIDE: 2.9, //     platform side (cart-local +x = up × tangent)
  BOARD_CAM_AHEAD: 1.35,
  BOARD_CAM_UP: 1.05,
  BOARD_LOOK_SIDE: 0.3, //    look bias toward the hop midpoint
  BOARD_LOOK_UP: 0.55,
  /** V6 fix P0-1 palette: game pastels — dusty-rose/mint carts with a cream
   * rim (the wheel's F2A7BE/FBF3E4 family), plaza-tone ground, soft sky. */
  CART_COLORS: Object.freeze([0xf2a7be, 0xa9dcc6]),
  CART_RIM: 0xfbf3e4,
  SKY_TOP: 0x9ecdf2,
  SKY_HORIZON: 0xfff1dc,
  GROUND: 0x8fc76d, //        parkScene grass tone
  PLAZA: 0xe8d9c3, //         parkScene pave tone (station apron)
  TREE_RING: 46,
  /** Dense support struts (the trackPieces catalog probes every 2.5 u and
   * skips anything below 0.3 — the eval read that as floating track). */
  SUPPORT_SPACING: 1.3,
  SUPPORT_MIN_Y: 0.18,
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

// ---------------------------------------------------------------------------
// V6 fix P0-1: pastel palette pass on the toy-car-kit colormap
// ---------------------------------------------------------------------------

/** rgb 0–255 → [h 0–360, s 0–1, l 0–1] */
function rgbToHsl(r, g, b) {
  const rn = r / 255;
  const gn = g / 255;
  const bn = b / 255;
  const max = Math.max(rn, gn, bn);
  const min = Math.min(rn, gn, bn);
  const l = (max + min) / 2;
  if (max === min) return [0, 0, l];
  const d = max - min;
  const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  let h;
  if (max === rn) h = ((gn - bn) / d + (gn < bn ? 6 : 0)) * 60;
  else if (max === gn) h = ((bn - rn) / d + 2) * 60;
  else h = ((rn - gn) / d + 4) * 60;
  return [h, s, l];
}

/** [h 0–360, s 0–1, l 0–1] → rgb 0–255 */
function hslToRgb(h, s, l) {
  const hn = ((h % 360) + 360) % 360 / 360;
  if (s === 0) {
    const v = Math.round(l * 255);
    return [v, v, v];
  }
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  const p = 2 * l - q;
  const f = (t) => {
    let tn = t;
    if (tn < 0) tn += 1;
    if (tn > 1) tn -= 1;
    if (tn < 1 / 6) return p + (q - p) * 6 * tn;
    if (tn < 1 / 2) return q;
    if (tn < 2 / 3) return p + (q - p) * (2 / 3 - tn) * 6;
    return p;
  };
  return [Math.round(f(hn + 1 / 3) * 255), Math.round(f(hn) * 255), Math.round(f(hn - 1 / 3) * 255)];
}

/**
 * Remap one colormap pixel into the Funkelpark pastels: oranges/reds →
 * dusty rose (the wheel-rim family), yellows → warm cream, blues (support
 * steel) → cream, greens → soft mint; neutrals warm up, deep darks stay a
 * warm chocolate so wheels/shadows keep contrast.
 * @param {number} r @param {number} g @param {number} b
 * @returns {[number, number, number]}
 */
export function pastelizePixel(r, g, b) {
  const [h, s, l] = rgbToHsl(r, g, b);
  if (s < 0.14) {
    if (l < 0.24) return hslToRgb(18, 0.24, 0.19); // warm chocolate darks
    return hslToRgb(38, 0.28, Math.min(0.93, l * 0.35 + 0.62)); // warm paper
  }
  if (h < 62 || h >= 300) {
    // oranges / reds / magentas → dusty rose, keep the light/dark structure
    return hslToRgb(341, 0.52, Math.min(0.88, l * 0.5 + 0.42));
  }
  if (h < 92) {
    return hslToRgb(40, 0.5, Math.min(0.94, l * 0.3 + 0.66)); // yellows → cream
  }
  if (h < 170) {
    return hslToRgb(152, 0.32, Math.min(0.9, l * 0.4 + 0.5)); // greens → mint
  }
  return hslToRgb(41, 0.36, Math.min(0.94, l * 0.3 + 0.62)); // blues → cream
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

      // ---- ground disc + plaza apron + distant park silhouettes ----
      const ground = own(new THREE.Mesh(
        new THREE.CircleGeometry(360, 40),
        new THREE.MeshStandardMaterial({ color: VIEW.GROUND, roughness: 1 })
      ));
      ground.rotation.x = -Math.PI / 2;
      ground.position.y = -0.02;
      scene.add(ground);
      // V6 fix P0-1: paved plaza-tone apron under the whole circuit footprint
      // (the walk spans x −36…0, z −6…24 track units) — kills the olive void
      const apron = own(new THREE.Mesh(
        new THREE.CircleGeometry(52, 36),
        new THREE.MeshStandardMaterial({ color: VIEW.PLAZA, roughness: 1 })
      ));
      apron.rotation.x = -Math.PI / 2;
      apron.position.set(-18 * S, -0.005, 9 * S);
      scene.add(apron);

      const treeGeo = new THREE.ConeGeometry(2.6, 7, 7);
      const treeMat = new THREE.MeshStandardMaterial({ color: 0x86cba4, roughness: 1 });
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

      // ---- V6 fix P0-1: ONE pastel override material for every kit GLB ----
      // The toy-car-kit pieces all sample a shared colormap atlas (mustard /
      // burnt-orange / steel-blue patches). Remap it ONCE into the game's
      // pastels (pastelizePixel) and render every track/support/gate mesh
      // with the same dusty-rose/cream material — zero extra draw calls.
      this.kitMat = null;
      {
        const probe = assets.getModel('toy-car-kit/track-narrow-straight');
        let srcMap = null;
        probe.traverse((obj) => {
          if (!srcMap && obj.isMesh && obj.material?.map?.image) srcMap = obj.material.map;
        });
        if (srcMap?.image?.width) {
          const cv = document.createElement('canvas');
          cv.width = srcMap.image.width;
          cv.height = srcMap.image.height;
          const g = cv.getContext('2d');
          g.drawImage(srcMap.image, 0, 0);
          const img = g.getImageData(0, 0, cv.width, cv.height);
          const d = img.data;
          for (let i = 0; i < d.length; i += 4) {
            const [pr, pg, pb] = pastelizePixel(d[i], d[i + 1], d[i + 2]);
            d[i] = pr;
            d[i + 1] = pg;
            d[i + 2] = pb;
          }
          g.putImageData(img, 0, 0);
          const tex = new THREE.CanvasTexture(cv);
          tex.colorSpace = srcMap.colorSpace;
          tex.flipY = srcMap.flipY;
          tex.wrapS = srcMap.wrapS;
          tex.wrapT = srcMap.wrapT;
          this.kitMat = new THREE.MeshStandardMaterial({
            map: tex,
            roughness: 0.85,
            metalness: 0,
            // V6.1/FIX5: the kit GLBs author their colormap material
            // doubleSided — the pastel override must keep that, or every
            // back-facing run is culled (visible ribbon gaps on descents,
            // the loop rings' lower band missing = "floating" loops).
            side: THREE.DoubleSide,
          });
          ownedMats.push(this.kitMat); // dispose() drops the map too
        }
      }
      const kitMaterial = (orig) => this.kitMat ?? orig;

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
          // geometry is a shared asset-cache master — never disposed; the
          // material is the scene-owned pastel override (P0-1 palette)
          const inst = new THREE.InstancedMesh(sub.geometry, kitMaterial(sub.material), pieces.length);
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
      // V6 fix P0-1: probe DENSER than the trackPieces default (2.5 u,
      // MIN_Y 0.3 read as floating track) — every 1.3 u down to 0.18 u
      // rail height, so nothing hovers. Same two draw calls.
      const supports = [];
      {
        const loopSpans = assembly.pieces
          .filter((piece) => piece.type === 'loop')
          .map((piece) => [piece.s0, piece.s1]);
        for (let s = 0; s < assembly.totalLen; s += VIEW.SUPPORT_SPACING) {
          if (loopSpans.some(([s0, s1]) => s >= s0 && s <= s1)) continue;
          const smp = pointAt(assembly, s);
          if (smp.p[1] > VIEW.SUPPORT_MIN_Y) {
            supports.push({ p: [smp.p[0], 0, smp.p[2]], h: smp.p[1] });
          }
        }
      }
      const placeSupportSet = (key, place) => {
        const model = assets.getModel(`toy-car-kit/${key}`);
        model.updateMatrixWorld(true);
        const subs = [];
        model.traverse((obj) => {
          if (obj.isMesh) subs.push(obj);
        });
        for (const sub of subs) {
          const inst = new THREE.InstancedMesh(sub.geometry, kitMaterial(sub.material), supports.length);
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

      // ---- V6 fix P0-1: loop braces — cream A-frame struts anchor both
      // loop rings to the ground (the rings read as hovering donuts before).
      // One InstancedMesh = one draw call.
      {
        const anchors = [];
        for (const piece of assembly.pieces) {
          if (piece.type !== 'loop') continue;
          const def = TRACK_PIECES.loop;
          const h = DIRS[piece.dir];
          const l = DIRS[(piece.dir + 1) % 4];
          const c0 = [piece.x + h[0] * def.entry, piece.y, piece.z + h[1] * def.entry];
          // ring side points (hub height r, fore + aft of the circle center,
          // corkscrew drift included — matches trackPieces emitPiece)
          for (const [side, driftK] of [[1, 0.25], [-1, 0.75]]) {
            anchors.push({
              x: c0[0] + h[0] * def.r * side + l[0] * def.shift * driftK,
              y: piece.y + def.r,
              z: c0[2] + h[1] * def.r * side + l[1] * def.shift * driftK,
              lx: l[0],
              lz: l[1],
            });
          }
        }
        const braceGeo = new THREE.BoxGeometry(0.13 * S, 1, 0.13 * S);
        const braceMat = new THREE.MeshStandardMaterial({ color: VIEW.CART_RIM, roughness: 0.9 });
        ownedGeos.push(braceGeo);
        ownedMats.push(braceMat);
        const braces = new THREE.InstancedMesh(braceGeo, braceMat, anchors.length * 2);
        const upV = new THREE.Vector3(0, 1, 0);
        const dirV = new THREE.Vector3();
        const midV = new THREE.Vector3();
        const q = new THREE.Quaternion();
        let bi = 0;
        for (const a of anchors) {
          for (const lat of [-0.62, 0.62]) {
            const foot = new THREE.Vector3((a.x + a.lx * lat) * S, 0, (a.z + a.lz * lat) * S);
            const top = new THREE.Vector3(a.x * S, a.y * S, a.z * S);
            dirV.subVectors(top, foot);
            const len = dirV.length();
            q.setFromUnitVectors(upV, dirV.normalize());
            midV.addVectors(foot, top).multiplyScalar(0.5);
            braces.setMatrixAt(bi, new THREE.Matrix4().compose(midV, q, new THREE.Vector3(1, len, 1)));
            bi += 1;
          }
        }
        braces.instanceMatrix.needsUpdate = true;
        braces.frustumCulled = false;
        scene.add(braces);
        this.trackMeshes.push(braces);
      }

      // ---- station arch + photo gantry (committed gate GLBs) ----
      const placeGate = (key, s, scale) => {
        const smp = pointAt(assembly, s);
        const gate = assets.getModel(`toy-car-kit/${key}`);
        // P0-1 palette: gate clones ride the same pastel-remapped material
        gate.traverse((obj) => {
          if (obj.isMesh && this.kitMat) obj.material = this.kitMat;
        });
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
      // station platform slab beside the boarding straight (P0-1: cream, not
      // mustard — the wheel-platform family)
      const stationPose = pointAt(assembly, 2);
      const platform = own(new THREE.Mesh(
        new THREE.BoxGeometry(1.4 * S, 0.24 * S, 4 * S),
        new THREE.MeshStandardMaterial({ color: VIEW.CART_RIM, roughness: 0.9 })
      ));
      platform.position.set(
        (stationPose.p[0] + 1.15) * S,
        0.12 * S,
        stationPose.p[2] * S
      );
      scene.add(platform);
      this.platform = platform;

      // ---- the 2-cart train + Gooby up front (sitDrive) ----
      // V6 fix P0-1: OPEN-TOP tubs (bottom hemisphere + cream rim) replace
      // the closed hull + dark lid that buried Gooby — head, ears and paws
      // now clearly read above the rim. Pastel pink + mint, wheel family.
      const wheelGeo = new THREE.SphereGeometry(0.09 * S, 10, 8);
      const wheelMat = new THREE.MeshStandardMaterial({ color: 0x4a3b36, roughness: 0.6 });
      const rimGeo = new THREE.TorusGeometry(0.5 * S, 0.05 * S, 8, 22);
      const rimMat = new THREE.MeshStandardMaterial({ color: VIEW.CART_RIM, roughness: 0.55 });
      const tubGeo = new THREE.SphereGeometry(0.5 * S, 20, 10, 0, Math.PI * 2, Math.PI / 2, Math.PI / 2);
      ownedGeos.push(wheelGeo, rimGeo, tubGeo);
      ownedMats.push(wheelMat, rimMat);
      const RIM_Y = 0.36 * S; //  open-tub rim plane (world: 0.72 m)
      for (let c = 0; c < 2; c += 1) {
        const cart = new THREE.Group();
        const tubMat = new THREE.MeshStandardMaterial({
          color: VIEW.CART_COLORS[c],
          roughness: 0.45,
          side: THREE.DoubleSide, // the open bowl shows its inside
        });
        ownedMats.push(tubMat);
        const tub = new THREE.Mesh(tubGeo, tubMat);
        tub.scale.set(0.74, 0.58, 1.05);
        tub.position.y = RIM_Y;
        cart.add(tub);
        const rim = new THREE.Mesh(rimGeo, rimMat);
        rim.rotation.x = Math.PI / 2;
        rim.scale.set(0.74, 1.05, 1);
        rim.position.y = RIM_Y;
        cart.add(rim);
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
      // full-size rider seated high: rim plane is 0.36·S — the seat puts the
      // head pivot (~0.45 world) clearly above it so head + ears + paws read
      this.gooby.group.scale.setScalar(1);
      this.goobySeat = new THREE.Vector3(0, 0.2 * S, -0.04 * S);
      // P0-1 boarding: Gooby starts ON the platform (cart-local +x) and hops
      // in during the ≤3 s boarding beat (reduced motion: seated from t0)
      this.goobyPerch = new THREE.Vector3(0.62 * S, 0.24 * S, -0.04 * S);
      this.boardFx = { t: 0, landed: reducedMotion, bounceT: 0 };
      this.gooby.group.position.copy(reducedMotion ? this.goobySeat : this.goobyPerch);
      this.gooby.setEmotion('happy');
      this.gooby.play?.(reducedMotion ? 'sitDrive' : 'happyBounce')?.catch?.(() => {});
      this.train[0].add(this.gooby.group);
      this.armGrpL = this.gooby.group.getObjectByName('armGrpL') ?? null;
      this.armGrpR = this.gooby.group.getObjectByName('armGrpR') ?? null;

      // V6 fix P0-1: portrait boarding shot from the station basis (cleared
      // once the post-departure blend completes — see composedPose()).
      const bp = pointAt(assembly, 0);
      const bs = [
        bp.up[1] * bp.t[2] - bp.up[2] * bp.t[1],
        bp.up[2] * bp.t[0] - bp.up[0] * bp.t[2],
        bp.up[0] * bp.t[1] - bp.up[1] * bp.t[0],
      ]; // cart-local +x (the platform side)
      this.boardShot = {
        p: [
          bp.p[0] + bs[0] * VIEW.BOARD_CAM_SIDE + bp.t[0] * VIEW.BOARD_CAM_AHEAD,
          bp.p[1] + VIEW.BOARD_CAM_UP,
          bp.p[2] + bs[2] * VIEW.BOARD_CAM_SIDE + bp.t[2] * VIEW.BOARD_CAM_AHEAD,
        ],
        look: [
          bp.p[0] + bs[0] * VIEW.BOARD_LOOK_SIDE,
          bp.p[1] + VIEW.BOARD_LOOK_UP,
          bp.p[2] + bs[2] * VIEW.BOARD_LOOK_SIDE,
        ],
        up: [0, 1, 0],
        fov01: 0,
      };

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
      // V6 fix P1-6: mount INSIDE #ui — #ui is position:fixed (a stacking
      // context), so a body-level sibling at z 60 painted OVER the §E6
      // sheets (z 200) no matter their z-index. As a #ui child the caption
      // chrome correctly stacks below --z-panel.
      (document.getElementById('ui') ?? document.body).appendChild(overlay);
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
      this.applyCamera(this.composedPose());

      // dev probe (the __roadtest/__recapPreview precedent — CDP evidence)
      if (import.meta.env.DEV) window.__coaster = this;
    },

    /** cameraPose() + the view's boarding-shot blend (V6 fix P0-1): hold the
     * portrait station frame through boarding, then ease into the logic's
     * own station→chase move over CAM_BLEND_SEC after departure. */
    composedPose() {
      const pose = cameraPose(this.ride);
      const shot = this.boardShot;
      if (!shot || this.ride.reducedMotion) return pose;
      const k = this.ride.phase === 'boarding'
        ? 0
        : Math.min(1, this.ride.rideT / COASTER.CAM_BLEND_SEC);
      if (k >= 1) {
        this.boardShot = null;
        return pose;
      }
      const e = k * k * (3 - 2 * k);
      const mix = (a, b) => [
        a[0] + (b[0] - a[0]) * e,
        a[1] + (b[1] - a[1]) * e,
        a[2] + (b[2] - a[2]) * e,
      ];
      return {
        p: mix(shot.p, pose.p),
        look: mix(shot.look, pose.look),
        up: pose.up,
        fov01: pose.fov01 * e,
      };
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
      // V6 fix P0-1: boarding plays out in BOARD_SEC_VIEW (3) real seconds —
      // ONLY the logic's boarding clock is stepped faster; riding physics
      // stay 1:1 with real time (tests/timeline untouched).
      const holdingHands = this.holding && !this.skipHolding;
      const simDt = ride.phase === 'boarding'
        ? dt * (COASTER.BOARD_SEC / VIEW.BOARD_SEC_VIEW)
        : dt;
      for (const event of stepRide(ride, simDt, { holding: holdingHands })) {
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
      // ---- V6 fix P0-1: boarding beat — hop-in arc + damped cart bounce ----
      if (!ride.reducedMotion && this.boardFx) {
        const fx = this.boardFx;
        if (ride.phase === 'boarding' || fx.bounceT > 0) {
          fx.t += dt;
          if (!fx.landed) {
            const k = Math.min(1, Math.max(0, (fx.t - VIEW.HOP_START_SEC) / VIEW.HOP_SEC));
            const e = k * k * (3 - 2 * k);
            this.gooby.group.position.lerpVectors(this.goobyPerch, this.goobySeat, e);
            this.gooby.group.position.y += Math.sin(e * Math.PI) * VIEW.HOP_ARC_M;
            if (k >= 1) {
              fx.landed = true;
              fx.bounceT = VIEW.BOUNCE_SEC;
              audio?.play?.('pipe.rotate'); // restraint clunk on landing
              this.gooby.play?.('sitDrive')?.catch?.(() => {});
            }
          } else if (fx.bounceT > 0) {
            fx.bounceT -= dt;
            const bt = VIEW.BOUNCE_SEC - fx.bounceT;
            const bounce = Math.exp(-bt * 3.4) * Math.sin(bt * 17) * VIEW.BOUNCE_AMP_M;
            this.train[0].position.y += bounce;
            this.train[1].position.y += bounce * 0.45;
          }
        }
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
      this.applyCamera(this.composedPose());

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

// V6/E1: E2's TEMPORARY dev-kick block (documented in the E2→E1 handoff)
// was deleted here — the official `?coaster=1` route now lives in
// park/parkScene.js initParkScene() (same &rm=1 / &coasterhud=1 companions),
// which supplies the full frozen ctx incl. audio/assets + the back-to-plaza
// onDone.
