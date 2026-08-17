// V6/E1 — Funkelpark plaza hub (PLAN6 Wave E/E1): the §E1-contract scene
// behind the park day trip. Builds the plaza from park/parkBuilder.js's PURE
// layout, mounts E3's Candy Alley dressing (mountParkDressing + setBand) and
// wires the three plaza tap anchors of the frozen integration contract:
//   coaster kiosk → E2's startCoasterRide(ctx) (onDone returns to the plaza
//                   and books themePark.recordRide('coaster')),
//   stall counters → E3's openParkStall(ui, stallId, { store, audio }),
//   entrance gate  → 'parkLeaveConfirm' sheet → the runtime store event
//                   'parkLeaveRequested' (systems/shopTrip.js goHome()); a
//                   bare switchTo('home') fallback covers unwired boots.
// The reserved `ferrisWheel` anchor stays a named, deliberately CLEAR
// footprint for F4. Day/night rides the systems/dayNight.js band (scene rig
// swap + E3's setBand + themePark.recordNight). Gooby strolls a fixed loop
// around the fountain (home-room energy — pannable camera, no free walk).
//
// State writes (the ONLY themePark writers, see systems/themePark.js):
// recordVisit on every plaza enter except coaster returns ({from:'coaster'}),
// recordNight when the band is/turns night while in the plaza, recordRide in
// the coaster onDone AND the wheel onDone (V6.1/C1 — completed rides only),
// recordCandy from the 'inventoryChanged' diff of the
// three park foods while the plaza is active (E3's stall buys through the
// plain economy.buyFood — no new economy event exists, so the scene observes
// the inventory delta instead of editing E3's module).
//
// Hub budget (PLAN6 guardrail): ≤ 120 draw calls / ≤ 75k tris INCLUDING the
// dressing — proven with the ?parkhud=1 dev overlay (day + night).

import * as THREE from 'three';
import { DAYNIGHT } from '../data/constants.js';
import { DRIVE_TUNING } from '../data/constants.js';
import { t } from '../data/strings.js';
import { bandAt } from '../systems/dayNight.js';
import { now } from '../core/clock.js';
import { createGooby } from '../character/gooby.js';
import { applyEquippedOutfits } from '../character/outfitAttach.js';
import { prefersReducedMotion } from '../ui/ui.js';
import { generateParkLayout, PARK_ASSET_KEYS } from './parkBuilder.js';
// E3's frozen exports (PLAN6 Wave E integration contract)
import { mountParkDressing, setBand as setDressingBand, PARK_STALLS } from './parkDressing.js';
// E2's frozen export (PLAN6 Wave E integration contract)
import { startCoasterRide } from './coasterRide.js';
// V6/F4: the Riesenrad — procedural build + the calm in-scene ride
import { mountFerrisWheel, startWheelRide } from './ferrisWheel.js';
import { openParkStall, initParkStall } from '../ui/parkStall.js';
import { recordVisit, recordNight, recordRide, recordCandy } from '../systems/themePark.js';

export { PARK_ASSET_KEYS };

// ── plaza band rig (frozen module-local, §E0.1-2 — the CITY_BANDS recipe
// tuned for the smaller plaza; DAYNIGHT supplies the shared light colors) ──
export const PARK_BANDS = Object.freeze({
  // fog starts BEYOND the ~58 m camera→fountain distance of the overview
  // framing below, so the plaza reads crisp and only the coaster silhouette
  // (~95 m) picks up atmospheric depth.
  day: Object.freeze({ sky: '#cfe8ff', hemiIntensity: 0.95, dirIntensity: 1.05, fogFrom: 75, fogTo: 170 }),
  dawn: Object.freeze({ sky: '#f7ddb9', hemiIntensity: 0.85, dirIntensity: 0.9, fogFrom: 75, fogTo: 165 }),
  dusk: Object.freeze({ sky: '#eeb493', hemiIntensity: 0.78, dirIntensity: 0.7, fogFrom: 70, fogTo: 160 }),
  night: Object.freeze({ sky: '#1D2440', hemiIntensity: 0.58, dirIntensity: 0.2, fogFrom: 62, fogTo: 140 }),
});

/** The three park food ids whose inventory delta books recordCandy. */
const PARK_FOOD_IDS = Object.freeze(PARK_STALLS.map((s) => s.foodId));

/** Gooby's stroll speed (m/s) and hop bounce height (m). */
const STROLL = Object.freeze({ SPEED: 1.15, BOUNCE: 0.16, MOVE_SEC: 7, PAUSE_SEC: 3.2 });

/** V6 fix P1-4: overview framing — lower + closer than the V6.0 (0,24,52)
 * rig so the visible horizon sits in the top quarter (with the backdrop
 * ring below) and Gooby reads ~30% bigger. LOOK lifts the aim point so the
 * plaza heart stays centered. */
const FRAME = Object.freeze({
  CAM_Y: 17.5,
  CAM_Z: 41,
  LOOK_Y: 1.0,
  LOOK_Z: -11,
  PAN_LOOK: 0.45,
  /** Gooby's plaza presence scale — at the ~40 m hub distance a 1.05 m
   * Gooby is a speck; the toy-scale bump keeps him readable (the wheel
   * ride snapshots/restores whatever base scale it finds). */
  GOOBY_SCALE: 1.3,
});

/** V6 fix P1-5: night dressing numbers (lamp glow, pools, moon, stars). */
const NIGHT_FX = Object.freeze({
  LAMP_GLOW_COLOR: '#FFD9A0',
  LAMP_GLOW_R: 0.26,
  POOL_COLOR: '#FFC98A',
  POOL_R: 2.6,
  POOL_OPACITY: 0.5,
  FOUNTAIN_COLOR: '#9FDCFF',
  FOUNTAIN_R: 3.4,
  FOUNTAIN_OPACITY: 0.55,
  STAR_COUNT: 130,
  STAR_COLOR: '#FFE9A8', //  gfx/sky.js paintSky star tint (garden match)
  MOON_COLOR: '#F4EFD9', //  gfx/sky.js paintSky moon tint (garden match)
});

/** Soft radial falloff sprite (glow pools / fountain glow / moon halo). */
function makeGlowTexture(size = 128) {
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = size;
  const g = canvas.getContext('2d');
  const grad = g.createRadialGradient(size / 2, size / 2, 0, size / 2, size / 2, size / 2);
  grad.addColorStop(0, 'rgba(255,255,255,1)');
  grad.addColorStop(0.45, 'rgba(255,255,255,0.55)');
  grad.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = grad;
  g.fillRect(0, 0, size, size);
  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

/** @param {string} name @returns {string|null} dev-only URL param */
function devParam(name) {
  if (!import.meta.env?.DEV || typeof location === 'undefined') return null;
  return new URLSearchParams(location.search).get(name);
}

/** Sum of the park-food counts in an inventory map (candy-diff observer). */
function parkFoodCount(inventory) {
  let n = 0;
  for (const id of PARK_FOOD_IDS) n += Math.max(0, Math.floor(Number(inventory?.[id]) || 0));
  return n;
}

/**
 * Render every transform of a (possibly multi-mesh) GLB as InstancedMesh —
 * one draw call per (geometry, material) pair (§E10; cityDrive's recipe).
 */
function addInstanced(model, transforms, parent) {
  if (transforms.length === 0) return;
  model.updateMatrixWorld(true);
  const tmp = new THREE.Matrix4();
  model.traverse((o) => {
    if (!o.isMesh) return;
    const im = new THREE.InstancedMesh(o.geometry, o.material, transforms.length);
    for (let i = 0; i < transforms.length; i++) {
      tmp.multiplyMatrices(transforms[i], o.matrixWorld);
      im.setMatrixAt(i, tmp);
    }
    im.instanceMatrix.needsUpdate = true;
    parent.add(im);
  });
}

/** Compose a Matrix4 from x/z, rotY, uniform scale (ground y = 0). */
function composeAt(x, z, rotY, scale) {
  const m = new THREE.Matrix4();
  m.compose(
    new THREE.Vector3(x, 0, z),
    new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 1, 0), rotY ?? 0),
    new THREE.Vector3(scale, scale, scale)
  );
  return m;
}

/**
 * The park scene factory (§E1 lifecycle). `ctx` is the sceneManager factory
 * context PLUS sceneManager itself (closed over by initParkScene's wrapper —
 * the coaster handoff and the leave fallback need it).
 * @param {{renderer: object, assets: object, input: object, audio: object,
 *   store: object, ui: object, sceneManager: object}} ctx
 */
export function createParkScene(ctx) {
  const { assets, input, audio, store, ui, sceneManager, renderer } = ctx;
  const scene = new THREE.Scene();
  // fov 58: on portrait phones (aspect ≈ 0.46) the horizontal fov is only
  // ~30°, and the overview framing below needs the full 44 m plaza width —
  // gate, Candy Alley, kiosk, fountain AND the coaster silhouette in frame.
  const camera = new THREE.PerspectiveCamera(58, innerWidth / innerHeight, 0.1, 400);

  /** geometries/materials created by THIS scene (disposed on dispose()). */
  const ownedGeos = [];
  const ownedMats = [];
  const geo = (g) => (ownedGeos.push(g), g);
  const mat = (m) => (ownedMats.push(m), m);

  const layout = generateParkLayout(DRIVE_TUNING.CITY_SEED);

  let gooby = null;
  let dressingHandle = null;
  // V6/F4: wheel mount handle + the riding lock (plaza modal while riding)
  let wheelHandle = null;
  let wheelRiding = false;
  let offWheelRide = null;
  let hemi = null;
  let dir = null;
  let nightFx = null; // V6 fix P1-5: lamp glow + pools + moon + stars group
  let band = 'day';
  let bandCheckT = 0;
  let offInventory = null;
  let lastCandyCount = 0;
  let strollCurve = null;
  let strollLen = 1;
  let strollS = 0;
  let strollPhase = 'move';
  let strollT = 0;
  const reduceMotion = prefersReducedMotion();
  /** camera pan (drag): target x slides along the south rim */
  let panX = 0;
  let panTargetX = 0;
  const tapTargets = [];
  // dev: ?alleycam=1 pins a close-up Candy Alley framing (dressing checks —
  // the ?parkhud=1 pattern; no effect outside dev builds)
  const alleyCam = devParam('alleycam') === '1';
  let hudEl = null;
  let hudT = 0;
  let logT = 0;
  let entered = false;

  // ---- plaza band rig ------------------------------------------------------
  function applyBand(next) {
    band = next;
    const cfg = PARK_BANDS[band] ?? PARK_BANDS.day;
    const light = DAYNIGHT[band] ?? DAYNIGHT.day;
    scene.background = new THREE.Color(cfg.sky);
    scene.fog = new THREE.Fog(cfg.sky, cfg.fogFrom, cfg.fogTo);
    if (hemi) {
      hemi.color.set(light.hemiSky);
      hemi.groundColor.set(light.hemiGround);
      hemi.intensity = cfg.hemiIntensity;
    }
    if (dir) {
      dir.color.set(light.dirColor);
      dir.intensity = cfg.dirIntensity;
    }
    setDressingBand(band); // E3's once-per-change material swap (≤2 calls)
    wheelHandle?.setBand(band); // V6/F4: rim fairy glow (emissive only, +0 calls)
    if (nightFx) nightFx.visible = band === 'night'; // V6 fix P1-5
  }

  /** Latch themePark.nightVisit (enter at night OR band flips while here). */
  function bookNightIfNight() {
    if (band !== 'night') return;
    store.update((s) => {
      s.themePark = recordNight(s.themePark);
    });
  }

  // ---- static plaza assembly ----------------------------------------------
  function buildPlaza() {
    const group = new THREE.Group();
    group.name = 'parkPlaza';

    // grass beyond the plaza + the paved plaza square
    const grass = new THREE.Mesh(
      geo(new THREE.PlaneGeometry(260, 260)),
      mat(new THREE.MeshStandardMaterial({ color: '#8fc76d', roughness: 1 }))
    );
    grass.rotation.x = -Math.PI / 2;
    group.add(grass);
    const pave = new THREE.Mesh(
      geo(new THREE.PlaneGeometry(layout.half * 2 + 2, layout.half * 2 + 2)),
      mat(new THREE.MeshStandardMaterial({ color: '#e8d9c3', roughness: 1 }))
    );
    pave.rotation.x = -Math.PI / 2;
    pave.position.y = 0.02;
    group.add(pave);

    // walk paths (flat ribbons — one shared material)
    const pathMat = mat(new THREE.MeshStandardMaterial({ color: '#d8b98f', roughness: 1 }));
    for (const path of layout.paths) {
      for (let i = 1; i < path.pts.length; i++) {
        const a = path.pts[i - 1];
        const b = path.pts[i];
        const len = Math.hypot(b.x - a.x, b.z - a.z);
        const seg = new THREE.Mesh(geo(new THREE.PlaneGeometry(path.width, len)), pathMat);
        seg.rotation.x = -Math.PI / 2;
        seg.rotation.z = -Math.atan2(b.x - a.x, b.z - a.z);
        seg.position.set((a.x + b.x) / 2, 0.035, (a.z + b.z) / 2);
        group.add(seg);
      }
    }

    // items instanced per GLB key (kiosk/alley/reserved build elsewhere)
    /** @type {Record<string, THREE.Matrix4[]>} */
    const byKey = {};
    for (const item of layout.items) {
      if (!item.key || item.kind === 'kiosk') continue;
      (byKey[item.key] ??= []).push(composeAt(item.x, item.z, item.rotY, item.scale));
    }
    for (const [key, transforms] of Object.entries(byKey)) {
      addInstanced(assets.getModel(key), transforms, group);
    }

    // lantern ground fix: street_lantern is authored with minY −0.2 — the
    // instanced transforms above sit at y 0, so nudge via a group offset is
    // NOT possible per-key; the 0.2·scale sink is visually a planted post.

    scene.add(group);
    return group;
  }

  // ---- the coaster entrance kiosk + background silhouette ------------------
  function buildKiosk(group) {
    const k = layout.anchors.coasterKiosk;
    const holder = new THREE.Group();
    holder.name = 'coasterKiosk';
    holder.position.set(k.x, 0, k.z);
    holder.rotation.y = k.rotY;

    const booth = assets.getModel(k.key);
    booth.scale.setScalar(k.scale);
    holder.add(booth);
    const awning = assets.getModel('city-kit-commercial/detail-awning-wide');
    awning.scale.setScalar(1.15);
    awning.position.set(0, 2.5, 0.75);
    holder.add(awning);

    // canvas sign: the ride name (E3's v6-park strings — E2's caption block)
    const canvas = document.createElement('canvas');
    canvas.width = 512;
    canvas.height = 128;
    const g = canvas.getContext('2d');
    g.fillStyle = '#7A5CC9';
    g.beginPath();
    g.roundRect(4, 8, 504, 112, 24);
    g.fill();
    g.font = '900 58px system-ui, sans-serif';
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    g.fillStyle = '#FFF6EC';
    g.fillText(t('park.coaster.name'), 256, 64);
    const tex = new THREE.CanvasTexture(canvas);
    tex.colorSpace = THREE.SRGBColorSpace;
    ownedMats.push({ dispose: () => tex.dispose() });
    const sign = new THREE.Mesh(
      geo(new THREE.PlaneGeometry(4.4, 1.1)),
      mat(new THREE.MeshBasicMaterial({ map: tex, transparent: true, side: THREE.DoubleSide }))
    );
    sign.position.set(0, 3.6, 0.2);
    holder.add(sign);
    group.add(holder);
  }

  /** Distant coaster silhouette north of the plaza (anticipation read —
   *  the REAL ride is E2's own scene; this is 3 cheap purple draw calls). */
  function buildCoasterSilhouette(group) {
    const silMat = mat(new THREE.MeshBasicMaterial({ color: '#8a79c9' }));
    const pts = [];
    const baseZ = -40;
    for (let i = 0; i <= 10; i++) {
      const x = -26 + i * 6.4;
      const y = 4 + Math.sin(i * 1.25) * 3.4 + (i % 3 === 0 ? 2.2 : 0);
      pts.push(new THREE.Vector3(x, Math.max(2.2, y), baseZ + Math.sin(i * 0.9) * 3));
    }
    const curve = new THREE.CatmullRomCurve3(pts);
    const track = new THREE.Mesh(geo(new THREE.TubeGeometry(curve, 48, 0.3, 5, false)), silMat);
    group.add(track);
    // the signature loop
    const loop = new THREE.Mesh(geo(new THREE.TorusGeometry(4.4, 0.3, 6, 22)), silMat);
    loop.position.set(12, 6.4, baseZ);
    group.add(loop);
    // support columns (one InstancedMesh)
    const colGeo = geo(new THREE.CylinderGeometry(0.22, 0.22, 1, 5));
    const cols = new THREE.InstancedMesh(colGeo, silMat, 6);
    const m = new THREE.Matrix4();
    for (let i = 0; i < 6; i++) {
      const p = curve.getPoint(i / 5);
      m.compose(
        new THREE.Vector3(p.x, p.y / 2, p.z),
        new THREE.Quaternion(),
        new THREE.Vector3(1, p.y, 1)
      );
      cols.setMatrixAt(i, m);
    }
    cols.instanceMatrix.needsUpdate = true;
    group.add(cols);
  }

  // ---- V6 fix P1-4: cheap backdrop ring -------------------------------------
  /** Pastel hills + 3 distant tent/flag silhouettes fill the empty band
   *  between the grass edge and the sky (4 draw calls; deterministic). */
  function buildBackdrop(group) {
    const hash = (i, salt) => {
      const s = Math.sin(i * 127.1 + salt * 311.7) * 43758.5453;
      return s - Math.floor(s);
    };
    // low hills: one InstancedMesh of squashed spheres on a north-facing arc
    const hillGeo = geo(new THREE.SphereGeometry(1, 14, 9));
    const hillMat = mat(new THREE.MeshStandardMaterial({ color: '#7fbf72', roughness: 1 }));
    const HILL_N = 11;
    const hills = new THREE.InstancedMesh(hillGeo, hillMat, HILL_N);
    const m = new THREE.Matrix4();
    for (let i = 0; i < HILL_N; i++) {
      const a = (-95 + (i / (HILL_N - 1)) * 190) * (Math.PI / 180); // az. from north
      const r = 104 + hash(i, 5) * 38;
      const sx = 22 + hash(i, 9) * 14;
      const sy = 7 + hash(i, 13) * 5.5;
      m.compose(
        new THREE.Vector3(Math.sin(a) * r, 0, -Math.cos(a) * r),
        new THREE.Quaternion(),
        new THREE.Vector3(sx, sy, sx * 0.8)
      );
      hills.setMatrixAt(i, m);
    }
    hills.instanceMatrix.needsUpdate = true;
    group.add(hills);

    // distant funfair tents (cones) + cream pennant flags above the tips
    const tentGeo = geo(new THREE.ConeGeometry(1, 1, 9));
    const tentMat = mat(new THREE.MeshStandardMaterial({ color: '#d99fb2', roughness: 0.9 }));
    // pennant flags: unlit cream (Standard shades them grey at this angle)
    const flagGeo = geo(new THREE.PlaneGeometry(2.2, 1.2));
    const flagMat = mat(new THREE.MeshBasicMaterial({
      color: '#fff3dd', side: THREE.DoubleSide,
    }));
    const TENTS = [
      { x: -40, z: -66, s: 10 },
      { x: 14, z: -78, s: 11 },
      { x: 44, z: -58, s: 8.5 },
    ];
    const tents = new THREE.InstancedMesh(tentGeo, tentMat, TENTS.length);
    const flags = new THREE.InstancedMesh(flagGeo, flagMat, TENTS.length);
    for (let i = 0; i < TENTS.length; i++) {
      const tnt = TENTS[i];
      m.compose(
        new THREE.Vector3(tnt.x, tnt.s * 0.45, tnt.z),
        new THREE.Quaternion(),
        new THREE.Vector3(tnt.s, tnt.s * 0.9, tnt.s)
      );
      tents.setMatrixAt(i, m);
      // pennant leans off the tip like a wind-caught banner
      m.compose(
        new THREE.Vector3(tnt.x + 1.1, tnt.s * 0.9 + 0.55, tnt.z),
        new THREE.Quaternion(),
        new THREE.Vector3(1, 1, 1)
      );
      flags.setMatrixAt(i, m);
    }
    tents.instanceMatrix.needsUpdate = true;
    flags.instanceMatrix.needsUpdate = true;
    group.add(tents, flags);
  }

  // ---- V6 fix P1-4: exit affordance -----------------------------------------
  /** Signpost beside the entry path: home glyph + the trip.goHome label —
   *  the gate now reads as THE exit (2 draw calls). */
  function buildGateSign(group) {
    const canvas = document.createElement('canvas');
    canvas.width = 512;
    canvas.height = 256;
    const g = canvas.getContext('2d');
    g.fillStyle = '#FFF6EC';
    g.beginPath();
    g.roundRect(6, 10, 500, 236, 30);
    g.fill();
    g.lineWidth = 10;
    g.strokeStyle = '#E8A9BE';
    g.stroke();
    // little house glyph (roof + body + door)
    g.fillStyle = '#7A5A48';
    g.beginPath();
    g.moveTo(96, 118);
    g.lineTo(160, 62);
    g.lineTo(224, 118);
    g.closePath();
    g.fill();
    g.fillRect(112, 118, 96, 76);
    g.fillStyle = '#FFF6EC';
    g.fillRect(146, 146, 28, 48);
    // label (maxWidth shrink-to-fit — 'Nach Hause' must fit too)
    g.fillStyle = '#7A5A48';
    g.font = '900 58px system-ui, sans-serif';
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    g.fillText(t('trip.goHome'), 366, 132, 244);
    const tex = new THREE.CanvasTexture(canvas);
    tex.colorSpace = THREE.SRGBColorSpace;
    ownedMats.push({ dispose: () => tex.dispose() });

    const pole = new THREE.Mesh(
      geo(new THREE.CylinderGeometry(0.09, 0.11, 2.6, 8)),
      mat(new THREE.MeshStandardMaterial({ color: '#8a6a52', roughness: 0.9 }))
    );
    pole.position.set(4.9, 1.3, 14.2); // clear of the castle, on the pave
    group.add(pole);
    const board = new THREE.Mesh(
      geo(new THREE.PlaneGeometry(2.9, 1.45)),
      mat(new THREE.MeshBasicMaterial({ map: tex, transparent: true, side: THREE.DoubleSide }))
    );
    board.position.set(4.9, 2.2, 14.28);
    board.rotation.y = -0.14; // jaunty tilt toward the entry spine
    group.add(board);
  }

  // ---- V6 fix P1-5: night dressing ------------------------------------------
  /** Lamp head glows + warm ground pools (batched: 1+1 calls), a lit
   *  fountain glow, and a garden-matched moon + sparse stars (fog: false so
   *  the night fog never swallows them). Visibility rides applyBand. */
  function buildNightFx(group) {
    nightFx = new THREE.Group();
    nightFx.name = 'parkNightFx';

    const lanterns = layout.items.filter((it) => it.kind === 'lantern');
    // lantern head height from the GLB itself (authored minY sinks −0.2)
    const lanternModel = assets.getModel('pretty-park/street_lantern');
    const box = new THREE.Box3().setFromObject(lanternModel);
    const headY = box.max.y * 1.1 - 0.12; // LANTERN_SCALE 1.1, head just below the cap
    const glowTex = makeGlowTexture();
    ownedMats.push({ dispose: () => glowTex.dispose() });

    // emissive head sprites (one InstancedMesh of unlit spheres)
    const headGeo = geo(new THREE.SphereGeometry(NIGHT_FX.LAMP_GLOW_R, 10, 8));
    const headMat = mat(new THREE.MeshBasicMaterial({ color: NIGHT_FX.LAMP_GLOW_COLOR }));
    const heads = new THREE.InstancedMesh(headGeo, headMat, lanterns.length);
    // warm ground pools (one InstancedMesh of radial-falloff discs)
    const poolGeo = geo(new THREE.CircleGeometry(1, 24));
    const poolMat = mat(new THREE.MeshBasicMaterial({
      map: glowTex,
      color: NIGHT_FX.POOL_COLOR,
      transparent: true,
      opacity: NIGHT_FX.POOL_OPACITY,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
    }));
    const pools = new THREE.InstancedMesh(poolGeo, poolMat, lanterns.length);
    const m = new THREE.Matrix4();
    const flat = new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(1, 0, 0), -Math.PI / 2);
    for (let i = 0; i < lanterns.length; i++) {
      const l = lanterns[i];
      m.compose(new THREE.Vector3(l.x, headY, l.z), new THREE.Quaternion(), new THREE.Vector3(1, 1, 1));
      heads.setMatrixAt(i, m);
      m.compose(
        new THREE.Vector3(l.x, 0.06, l.z),
        flat,
        new THREE.Vector3(NIGHT_FX.POOL_R, NIGHT_FX.POOL_R, 1)
      );
      pools.setMatrixAt(i, m);
    }
    heads.instanceMatrix.needsUpdate = true;
    pools.instanceMatrix.needsUpdate = true;
    nightFx.add(heads, pools);

    // lit fountain: one aqua pool under the basin
    const f = layout.anchors.fountain;
    const fountainGlow = new THREE.Mesh(poolGeo, mat(new THREE.MeshBasicMaterial({
      map: glowTex,
      color: NIGHT_FX.FOUNTAIN_COLOR,
      transparent: true,
      opacity: NIGHT_FX.FOUNTAIN_OPACITY,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
    })));
    fountainGlow.rotation.x = -Math.PI / 2;
    fountainGlow.scale.setScalar(NIGHT_FX.FOUNTAIN_R);
    fountainGlow.position.set(f.x, 0.08, f.z);
    nightFx.add(fountainGlow);

    // moon (paintSky's #F4EFD9 disc + crater shadows) low in the north sky —
    // the garden dome's moon sits at ~26° elevation, above this camera's top
    // of frame, so the park paints its own at ~5°
    const mc = document.createElement('canvas');
    mc.width = mc.height = 128;
    const mg = mc.getContext('2d');
    mg.fillStyle = NIGHT_FX.MOON_COLOR;
    mg.beginPath();
    mg.arc(64, 64, 56, 0, Math.PI * 2);
    mg.fill();
    mg.fillStyle = 'rgba(160,160,190,0.35)';
    for (const [dx, dy, rr] of [[-0.3, -0.15, 0.22], [0.25, 0.3, 0.16], [0.05, -0.4, 0.12]]) {
      mg.beginPath();
      mg.arc(64 + dx * 56, 64 + dy * 56, rr * 56, 0, Math.PI * 2);
      mg.fill();
    }
    const moonTex = new THREE.CanvasTexture(mc);
    moonTex.colorSpace = THREE.SRGBColorSpace;
    ownedMats.push({ dispose: () => moonTex.dispose() });
    const moon = new THREE.Mesh(
      geo(new THREE.PlaneGeometry(13, 13)),
      mat(new THREE.MeshBasicMaterial({ map: moonTex, transparent: true, fog: false, depthWrite: false }))
    );
    moon.position.set(29, 34, -150);
    nightFx.add(moon);

    // sparse stars (Points, garden #FFE9A8) across the visible north band
    const hash = (i, salt) => {
      const s = Math.sin(i * 127.1 + salt * 311.7) * 43758.5453;
      return s - Math.floor(s);
    };
    const starPos = new Float32Array(NIGHT_FX.STAR_COUNT * 3);
    for (let i = 0; i < NIGHT_FX.STAR_COUNT; i++) {
      const az = (-72 + hash(i, 3) * 144) * (Math.PI / 180);
      const elev = (2.5 + hash(i, 11) * 26) * (Math.PI / 180);
      const r = 165;
      starPos[i * 3] = Math.sin(az) * Math.cos(elev) * r;
      starPos[i * 3 + 1] = 20 + Math.sin(elev) * r;
      starPos[i * 3 + 2] = -Math.cos(az) * Math.cos(elev) * r;
    }
    const starGeo = geo(new THREE.BufferGeometry());
    starGeo.setAttribute('position', new THREE.BufferAttribute(starPos, 3));
    const stars = new THREE.Points(starGeo, mat(new THREE.PointsMaterial({
      color: NIGHT_FX.STAR_COLOR,
      size: 2.4,
      sizeAttenuation: false,
      transparent: true,
      opacity: 0.85,
      fog: false,
      depthWrite: false,
    })));
    nightFx.add(stars);

    nightFx.visible = band === 'night';
    group.add(nightFx);
  }

  // ---- tap anchors (invisible boxes — the roomManager hitbox recipe) -------
  function buildTapAnchors(group) {
    const hitMat = mat(new THREE.MeshBasicMaterial({ visible: false }));
    const addTap = (id, kind, x, z, w, h, d, extra = {}) => {
      const hit = new THREE.Mesh(geo(new THREE.BoxGeometry(w, h, d)), hitMat);
      hit.name = `parkTap-${id}`;
      hit.visible = false;
      hit.position.set(x, h / 2, z);
      hit.userData.parkTap = { id, kind, ...extra };
      group.add(hit);
      tapTargets.push(hit);
    };

    const a = layout.anchors;
    addTap('gate', 'gate', a.gate.x, a.gate.z, 7.4, 6, 6.6);
    addTap('coaster', 'coaster', a.coasterKiosk.x, a.coasterKiosk.z, 4.6, 4.4, 3.4);
    // V6/F4: the wheel is a tap target → confirm sheet → the calm ride
    addTap('wheel', 'wheel', a.ferrisWheel.x, a.ferrisWheel.z, 9.4, 9.6, 7);
    // stall counters: E3's row runs along the alley's local x (spacing 3.4 m,
    // stalls facing local +z = plaza east after the 90° anchor rotation)
    for (let i = 0; i < PARK_STALLS.length; i++) {
      const stall = PARK_STALLS[i];
      const localX = (i - (PARK_STALLS.length - 1) / 2) * 3.4;
      addTap(`stall-${stall.id}`, 'stall', a.candyAlley.x, a.candyAlley.z - localX, 3.4, 3.4, 3.3, {
        stallId: stall.id,
      });
    }
  }

  // ---- tap dispatch ---------------------------------------------------------
  let coasterStarting = false;
  async function kickCoaster() {
    if (coasterStarting || sceneManager.isSwitching?.()) return;
    coasterStarting = true;
    audio.play('ui.open');
    const ok = await startCoasterRide({
      sceneManager,
      store,
      audio,
      assets,
      ui,
      reducedMotion: reduceMotion || undefined,
      onDone: () => {
        // the ONE ride-counter write site (E2 bumps no slice of its own)
        store.update((s) => {
          s.themePark = recordRide(s.themePark, 'coaster');
        });
        return sceneManager.switchTo('park', { from: 'coaster' });
      },
    });
    coasterStarting = false;
    if (!ok) console.warn('[parkScene] coaster refused to start');
  }

  // ---- V6/F4: the Riesenrad ride kick (confirm sheet → startWheelRide) ----
  // Mirrors the coaster wire: a `wheelRiding` lock makes the plaza modal
  // (onTap ignores everything; update() pauses stroll + pan — the ride owns
  // Gooby and the camera and hands both back through onDone).
  async function kickWheelRide() {
    if (wheelRiding || coasterStarting || sceneManager.isSwitching?.()) return;
    wheelRiding = true;
    // V6.1/C1: 'wheel' finally records like the coaster does. F4's onDone
    // also fires on a FAILED start (its catch path finishes instantly,
    // BEFORE the await below resolves false) — this flag flips true only
    // after startWheelRide resolved ok, so refusal/cancel records nothing.
    let rideStarted = false;
    // V6 fix P1-6: the ride chrome mounts on <body>, but #ui is a fixed-
    // position stacking context — a body-level sibling at z 60 paints OVER
    // the §E6 sheets (--z-panel 200) no matter their z-index. Re-home the
    // overlay into #ui as soon as F4's ride creates it (listeners survive
    // appendChild; F4's own remove() cleanup is unaffected).
    const rehomeOverlay = () => {
      const el = document.querySelector('body > .v6fw-root');
      if (el) (document.getElementById('ui') ?? document.body).appendChild(el);
      else if (wheelRiding && entered) requestAnimationFrame(rehomeOverlay);
    };
    requestAnimationFrame(rehomeOverlay);
    const ok = await startWheelRide({
      wheel: wheelHandle,
      camera,
      gooby,
      audio,
      store,
      sceneManager,
      reducedMotion: reduceMotion || devParam('rm') === '1' || undefined,
      getRestorePose: () => ({
        pos: [panX, FRAME.CAM_Y, FRAME.CAM_Z],
        look: [panX * FRAME.PAN_LOOK, FRAME.LOOK_Y, FRAME.LOOK_Z],
      }),
      onDone: () => {
        wheelRiding = false;
        // scene already left/disposed — a cancelRide() onDone lands here
        // (exit() clears `entered` BEFORE cancelling), so an interrupted
        // ride never records (V6.1/C1 acceptance: cancel records nothing)
        if (!entered || !gooby) return;
        if (rideStarted) {
          // V6.1/C1: the ONE 'wheel' ride-counter write site (mirrors the
          // coaster onDone above).
          store.update((s) => {
            s.themePark = recordRide(s.themePark, 'wheel');
          });
        }
        // Gooby resumes his stroll exactly where the loop left off
        strollPhase = 'move';
        strollT = 0;
        placeGoobyAt(strollS);
        gooby.group.position.y = 0;
        gooby.play('idle');
      },
    });
    if (!ok) wheelRiding = false;
    else rideStarted = true; // V6.1/C1: onDone may now record the ride
  }
  // ---- end V6/F4 ride kick --------------------------------------------------

  function onTap(p) {
    if (wheelRiding) return; // V6/F4: the ride overlay owns input while riding
    const hit = input.pick(camera, tapTargets, p);
    if (!hit) return;
    let obj = hit.object;
    while (obj && !obj.userData?.parkTap) obj = obj.parent;
    const tap = obj?.userData?.parkTap;
    if (!tap) return;
    if (tap.kind === 'gate') {
      audio.play('ui.open');
      ui.openPanel('parkLeaveConfirm');
    } else if (tap.kind === 'coaster') {
      kickCoaster();
    } else if (tap.kind === 'wheel') {
      // V6/F4: confirm sheet first (park.wheel.confirm.* — panel registered
      // in initParkScene; its GO emits 'parkWheelRideRequested')
      audio.play('ui.open');
      ui.openPanel('parkWheelConfirm');
    } else if (tap.kind === 'stall') {
      audio.play('ui.open');
      openParkStall(ui, tap.stallId, { store, audio });
    }
  }

  // ---- Gooby stroll ---------------------------------------------------------
  function placeGoobyAt(s) {
    const u = (s % strollLen) / strollLen;
    const p = strollCurve.getPointAt(u);
    const tangent = strollCurve.getTangentAt(u);
    gooby.group.position.set(p.x, gooby.group.position.y, p.z);
    gooby.group.rotation.y = Math.atan2(tangent.x, tangent.z);
  }

  // ---- dev budget HUD (?parkhud=1 — the ≤120 calls/≤75k tris proof) --------
  function mountHud() {
    hudEl = document.createElement('div');
    hudEl.style.cssText =
      'position:fixed;top:calc(8px + var(--safe-top, 0px));left:8px;z-index:60;background:rgba(29,36,64,.82);' +
      'color:#fff;font:700 12px/1.5 monospace;padding:6px 9px;border-radius:8px;pointer-events:none;white-space:pre;';
    document.body.appendChild(hudEl);
  }

  return {
    scene,
    camera,

    async enter(params = {}) {
      const from = params.from ?? null;

      // lights first (applyBand mutates them)
      hemi = new THREE.HemisphereLight('#fff5e8', '#b8a898', 0.95);
      dir = new THREE.DirectionalLight('#ffffff', 1.05);
      dir.position.set(30, 50, -24);
      scene.add(hemi, dir);
      applyBand(bandAt(now()).band);

      const group = buildPlaza();
      buildKiosk(group);
      buildCoasterSilhouette(group);
      buildBackdrop(group); //   V6 fix P1-4: hills + tent silhouettes
      buildGateSign(group); //   V6 fix P1-4: home signpost at the gate
      buildNightFx(group); //    V6 fix P1-5: lamps/fountain/moon/stars
      buildTapAnchors(group);

      // ---- V6/F4: mount the Riesenrad at E1's reserved anchor -------------
      // (+6 draw calls — the WHEEL_BATCHES pure ledger; ambient ~1 rpm)
      wheelHandle = mountFerrisWheel(group, layout.anchors.ferrisWheel, {
        reducedMotion: reduceMotion,
      });
      wheelHandle.setBand(band);
      offWheelRide = store.on('parkWheelRideRequested', kickWheelRide);
      // ---- end V6/F4 mount --------------------------------------------------

      // E3's Candy Alley: position the anchor parent, let the dressing build
      // around its local origin (stalls facing local +z → plaza east)
      const alley = layout.anchors.candyAlley;
      const alleyParent = new THREE.Group();
      alleyParent.name = 'candyAlleyAnchor';
      alleyParent.position.set(alley.x, 0, alley.z);
      alleyParent.rotation.y = alley.rotY;
      scene.add(alleyParent);
      dressingHandle = await mountParkDressing(alleyParent, band);

      // stall sheet deps (idempotent; openParkStall then works bare forever)
      initParkStall({ store, ui, audio });

      // Gooby strolls the fountain loop
      gooby = createGooby();
      applyEquippedOutfits(gooby);
      gooby.group.scale.setScalar(FRAME.GOOBY_SCALE); // V6 fix P1-4
      strollCurve = new THREE.CatmullRomCurve3(
        layout.goobyPath.map((p) => new THREE.Vector3(p.x, 0, p.z)),
        true
      );
      strollLen = strollCurve.getLength();
      strollS = 0;
      const entry = layout.entry;
      gooby.group.position.set(entry.x, 0, entry.z);
      gooby.group.rotation.y = entry.rotY;
      gooby.setEmotion('happy');
      gooby.play('idle');
      scene.add(gooby.group);

      // camera: south overview (V6 fix P1-4 FRAME — horizon in the top
      // quarter, Gooby bigger); drag pans gently sideways to lean toward
      // the alley (west) or the kiosk (east).
      panX = panTargetX = 0;
      camera.position.set(0, FRAME.CAM_Y, FRAME.CAM_Z);
      camera.lookAt(0, FRAME.LOOK_Y, FRAME.LOOK_Z);
      if (alleyCam) {
        const a = layout.anchors.candyAlley;
        camera.position.set(a.x + 12.5, 3.6, a.z - 5.5);
        camera.lookAt(a.x, 1.5, a.z - 0.4);
      }
      input.on('tap', onTap);
      input.on('drag', (p) => {
        panTargetX = Math.max(-6, Math.min(6, panTargetX - p.dx * 0.03));
      });

      // park ambience: the city radio context (no park-specific track exists)
      audio.music('city');
      try {
        audio.radio?.playContext?.('location:city');
      } catch { /* no radio engine in this context */ }

      // ---- themePark slice writes (the compact V6/E1 state) ----
      if (from !== 'coaster') {
        store.update((s) => {
          s.themePark = recordVisit(s.themePark, { night: band === 'night' });
        });
      }
      bookNightIfNight();
      lastCandyCount = parkFoodCount(store.get('inventory'));
      offInventory = store.on('inventoryChanged', (inventory) => {
        const count = parkFoodCount(inventory);
        if (count > lastCandyCount) {
          store.update((s) => {
            s.themePark = recordCandy(s.themePark, count - lastCandyCount);
          });
        }
        lastCandyCount = count;
      });

      if (devParam('parkhud') === '1') mountHud();
      entered = true;
    },

    update(dt) {
      if (!entered) return;

      // day/night: re-read the band every few seconds (cheap; swap is gated)
      bandCheckT += dt;
      if (bandCheckT >= 5) {
        bandCheckT = 0;
        const next = bandAt(now()).band;
        if (next !== band) {
          applyBand(next);
          bookNightIfNight();
        }
      }

      // V6/F4: ambient wheel spin / the active ride drive (theta + cabins)
      wheelHandle?.update(dt);

      // Gooby: stroll → pause → stroll (reduced motion: slow glide, no hops)
      gooby.update(dt);
      // V6/F4 (wrap): while the wheel ride is on, it leases Gooby AND the
      // camera — the stroll and the pan glide pause and resume via onDone.
      if (!wheelRiding) {
        strollT += dt;
        if (strollPhase === 'move') {
          strollS += dt * (reduceMotion ? STROLL.SPEED * 0.7 : STROLL.SPEED);
          placeGoobyAt(strollS);
          gooby.group.position.y = reduceMotion
            ? 0
            : Math.abs(Math.sin(strollS * 3.4)) * STROLL.BOUNCE;
          if (strollT >= STROLL.MOVE_SEC) {
            strollPhase = 'pause';
            strollT = 0;
            gooby.group.position.y = 0;
            gooby.play(Math.random() < 0.5 ? 'lookAround' : 'happyBounce');
          }
        } else {
          if (strollT >= STROLL.PAUSE_SEC) {
            strollPhase = 'move';
            strollT = 0;
            gooby.play('idle');
          }
        }

        // camera pan glide (the alleycam dev framing pins the camera instead)
        if (!alleyCam) {
          panX += (panTargetX - panX) * Math.min(1, dt * 6);
          camera.position.set(panX, FRAME.CAM_Y, FRAME.CAM_Z);
          camera.lookAt(panX * FRAME.PAN_LOOK, FRAME.LOOK_Y, FRAME.LOOK_Z);
        }
      }

      // dev budget HUD + console ledger (§E10-style)
      if (import.meta.env?.DEV) {
        logT += dt;
        if (logT > 3) {
          logT = 0;
          const info = renderer?.info?.render;
          console.info(`[parkScene] draw calls: ${info?.calls ?? 0} (budget ≤ 120), tris: ${info?.triangles ?? 0} (≤ 75k), band: ${band}`);
        }
        if (hudEl) {
          hudT += dt;
          if (hudT > 0.5) {
            hudT = 0;
            const info = renderer?.info?.render;
            hudEl.textContent =
              `FUNKELPARK HUB\ncalls ${info?.calls ?? 0} / 120\ntris  ${info?.triangles ?? 0} / 75000\nband  ${band}`;
          }
        }
      }
    },

    exit() {
      entered = false;
      offInventory?.();
      offInventory = null;
      // V6/F4: never leave an in-flight ride behind (forced scene exits)
      offWheelRide?.();
      offWheelRide = null;
      wheelHandle?.cancelRide();
      wheelRiding = false;
      hudEl?.remove();
      hudEl = null;
    },

    dispose() {
      try {
        dressingHandle?.dispose();
      } catch { /* dressing-owned resources only */ }
      dressingHandle = null;
      try {
        wheelHandle?.dispose(); // V6/F4: wheel-owned geos/mats + ride overlay
      } catch { /* wheel-owned resources only */ }
      wheelHandle = null;
      try {
        gooby?.dispose();
      } catch { /* gooby-owned resources only */ }
      gooby = null;
      nightFx = null; // V6 fix P1-5 (geos/mats disposed via the owned lists)
      for (const g of ownedGeos.splice(0)) g.dispose?.();
      for (const m of ownedMats.splice(0)) m.dispose?.();
      tapTargets.length = 0;
    },
  };
}

// ---------------------------------------------------------------------------
// Boot wiring (main.js V6/E1 marked block calls this once)
// ---------------------------------------------------------------------------

let wired = false;

/**
 * Register the 'park' scene (factory closes over sceneManager — the §E1
 * factory ctx does not carry it), the 'parkLeaveConfirm' §E6 panel and the
 * dev-harness kicks: ?park=1 jumps straight to the plaza, ?coaster=1 rides
 * E2's coaster through the OFFICIAL route (replacing E2's deleted temp
 * dev-kick; supports the same &rm=1 / &coasterhud=1 companions). Idempotent.
 * @param {{store: object, ui: object, audio: object, sceneManager: object,
 *   assets: object}} deps
 */
export function initParkScene({ store, ui, audio, sceneManager, assets }) {
  if (wired) return;
  wired = true;

  sceneManager.register(
    'park',
    (ctx) => createParkScene({ ...ctx, sceneManager }),
    [...PARK_ASSET_KEYS]
  );

  // gate → leave confirm → the shopTrip goHome flow (store event contract;
  // store.emit returns the listener count, so an unwired boot still gets a
  // clean bare ride home instead of a stuck plaza)
  ui.registerPanel('parkLeaveConfirm', {
    /** @param {HTMLElement} el */
    mount(el) {
      el.innerHTML = `
        <div style="text-align:center">
          <h2 class="perm-title">${t('park.leave.title')}</h2>
          <p class="perm-body">${t('park.leave.body')}</p>
          <div class="mg-btn-row">
            <button class="btn btn-teal park-leave-go">${t('trip.goHome')}</button>
            <button class="btn btn-ghost park-leave-stay">${t('ui.later')}</button>
          </div>
        </div>`;
      el.querySelector('.park-leave-go').addEventListener('click', () => {
        audio.play('ui.pick');
        ui.closePanel('parkLeaveConfirm');
        const listeners = store.emit('parkLeaveRequested');
        if (listeners === 0) {
          sceneManager
            .switchTo('home', { room: 'living' })
            .catch((err) => console.error('[parkScene] leave fallback failed:', err));
        }
      });
      el.querySelector('.park-leave-stay').addEventListener('click', () => ui.closePanel('parkLeaveConfirm'));
    },
    unmount() {},
  });

  // ---- V6/F4: wheel confirm sheet (the parkLeaveConfirm pattern) ------------
  // GO emits the runtime 'parkWheelRideRequested' event; the ACTIVE park
  // scene instance subscribes in enter() and runs kickWheelRide.
  ui.registerPanel('parkWheelConfirm', {
    /** @param {HTMLElement} el */
    mount(el) {
      el.innerHTML = `
        <div style="text-align:center">
          <h2 class="perm-title">${t('park.wheel.confirm.title')}</h2>
          <p class="perm-body">${t('park.wheel.confirm.body')}</p>
          <div class="mg-btn-row">
            <button class="btn btn-teal park-wheel-go">${t('park.wheel.confirm.go')}</button>
            <button class="btn btn-ghost park-wheel-stay">${t('ui.later')}</button>
          </div>
        </div>`;
      el.querySelector('.park-wheel-go').addEventListener('click', () => {
        audio.play('ui.pick');
        ui.closePanel('parkWheelConfirm');
        store.emit('parkWheelRideRequested');
      });
      el.querySelector('.park-wheel-stay').addEventListener('click', () => ui.closePanel('parkWheelConfirm'));
    },
    unmount() {},
  });
  // ---- end V6/F4 confirm sheet ----------------------------------------------

  // ---- dev harness kicks (§E9, dev builds only) ----------------------------
  if (!import.meta.env?.DEV || typeof location === 'undefined') return;
  const q = new URLSearchParams(location.search);
  const wantPark = q.get('park') === '1';
  const wantCoaster = q.get('coaster') === '1';
  if (!wantPark && !wantCoaster) return;
  let tries = 0;
  let busy = false;
  const kick = setInterval(async () => {
    tries += 1;
    if (tries > 100) return clearInterval(kick);
    // wait out the boot home-switch (the shopTrip dev-kick pattern)
    if (busy || sceneManager.isSwitching?.() || sceneManager.currentId?.() !== 'home') return;
    busy = true;
    let ok = false;
    try {
      if (wantPark) {
        await sceneManager.switchTo('park', { from: 'harness' });
        ok = sceneManager.currentId?.() === 'park';
        // V6/F4: `?park=1&wheel=1` auto-boards the Riesenrad (same &rm=1
        // companion as the coaster kick — kickWheelRide reads it)
        if (ok && q.get('wheel') === '1') {
          setTimeout(() => store.emit('parkWheelRideRequested'), 900);
        }
      } else {
        ok = await startCoasterRide({
          sceneManager,
          store,
          audio,
          assets,
          ui,
          reducedMotion: q.get('rm') === '1' ? true : undefined,
          hud: q.get('coasterhud') === '1',
          onDone: () => {
            store.update((s) => {
              s.themePark = recordRide(s.themePark, 'coaster');
            });
            return sceneManager.switchTo('park', { from: 'coaster' });
          },
        });
      }
    } catch (err) {
      console.warn('[parkScene] dev kick failed (retrying):', err);
    }
    busy = false;
    if (ok) clearInterval(kick);
  }, 400);
}
