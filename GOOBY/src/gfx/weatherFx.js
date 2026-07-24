// V2/G26: Weather FX (§C11.2/§A2.3) — the ANIMATED weather layer on top of
// G19's static sky painters (gfx/sky.js):
//
//   mountGardenRain(group)   → instanced rain streaks + ground splash rings —
//       ONE draw call total (§A2.3: pool 300, instanced quads, GPU-animated
//       via a uTime uniform so the CPU cost is a single uniform write/frame).
//       Fades in/out over ~1 s; mesh.visible false when fully faded (zero
//       draw calls while it isn't raining).
//   mountGardenClouds(group) → soft cloud sprites drifting across the garden
//       dome while the weather is 'cloudy' (ONE InstancedMesh draw call;
//       V4/POLISH-C: 4-variant hi-res atlas, per-instance scale/opacity/roll,
//       camera-facing billboards composed into the instance matrices).
//   windowRainTexture(band)  → shared ANIMATED CanvasTexture for the indoor
//       window panes during rain: streak trails + occasional droplet runs
//       painted over the static sky base (zero extra draw calls — it swaps
//       into the existing window-sky material via roomManager.setAmbience).
//   mountPondRipples(scene, opts) → cosmetic rain ripple rings for the
//       fishingPond water surface (§C11.2; ONE draw call, camera-facing
//       squashed rings).
//   updateWeatherFx(dt)      → drives every mounted garden effect + the
//       window texture (homeScene calls this from its update loop).
//
// Band/weather decisions live with the callers (homeScene subscribes to
// G20's 'dayBandChanged'/'weatherChanged' ticker events); this module only
// renders. All geometry is procedural — no assets, no textures beyond two
// procedural CanvasTextures (the cloud atlas + the window-rain overlay).

import * as THREE from 'three';
import { WEATHER } from '../data/constants.js';
import { windowTexture } from './sky.js';

/** Rain/cloud tuning (§A2.3 pool 300 = streaks + splash rings, 1 draw call). */
export const WEATHER_FX = Object.freeze({
  /** Total instanced rain quads (§A2.3/§C11.2: pool 300). */
  RAIN_POOL: WEATHER.RAIN_POOL,
  /** Of the pool, how many are ground splash rings (§C11.2). */
  SPLASH_COUNT: 44,
  /** Rain fade in/out time constant (s). */
  FADE_SEC: 1.1,
  /** Garden rain volume half-extents + ceiling (room-local, §C2.1 5×4 m). */
  AREA_X: 2.45,
  AREA_Z: 1.95,
  TOP_Y: 4.6,
  /** Drifting cloud sprite count (cloudy — §C11.2; V4/POLISH-C: 8 → 10). */
  CLOUD_COUNT: 10,
  /** Pond ripple ring instances (fishingPond §C11.2). */
  POND_RINGS: 26,
  /** Window rain canvas size / repaint interval (s). */
  WINDOW_SIZE: 128,
  WINDOW_REPAINT_SEC: 0.09,
});

/** @type {Set<{update: (dt: number) => void}>} handles updateWeatherFx drives */
const liveHandles = new Set();

// ---------------------------------------------------------------------------
// Shared rain shader (streaks kind=0 + flat splash rings kind=1)
// ---------------------------------------------------------------------------

const RAIN_VERT = /* glsl */ `
  attribute float aSeed;
  attribute float aKind;
  uniform float uTime;
  uniform float uIntensity;
  uniform vec3 uArea; // x/z half-extents, y = fall ceiling
  varying vec2 vUv;
  varying float vKind;
  varying float vAlpha;
  float h(float n) { return fract(sin(n * 127.1) * 43758.5453); }
  void main() {
    vUv = uv;
    vKind = aKind;
    vec3 p;
    if (aKind < 0.5) {
      // falling streak: seeded column, loops from the ceiling to the ground
      float x = (h(aSeed) * 2.0 - 1.0) * uArea.x;
      float z = (h(aSeed + 7.0) * 2.0 - 1.0) * uArea.z;
      float speed = 6.5 + h(aSeed + 13.0) * 3.5;
      float y = uArea.y - mod(uTime * speed + h(aSeed + 3.0) * uArea.y, uArea.y);
      // V6/FIX4 (P2-2): shorter per-seed length, thinner core and a slight
      // per-seed slant so the fall reads as soft drizzle sheets instead of
      // long uniform white slashes (was a fixed 0.36 m × 0.030 m quad).
      float len = 0.22 + h(aSeed + 9.0) * 0.10;
      float slant = (h(aSeed + 11.0) - 0.5) * 0.16;
      // cylindrical billboard: offset along the camera-right axis
      vec3 right = vec3(modelViewMatrix[0][0], modelViewMatrix[1][0], modelViewMatrix[2][0]);
      p = vec3(x, y, z) + right * (position.x * 0.024 + slant * position.y * len)
        + vec3(0.0, position.y * len, 0.0);
      vAlpha = uIntensity * (0.32 + h(aSeed + 5.0) * 0.42);
    } else {
      // ground splash ring: seeded spot, expanding + fading on its own phase
      float x = (h(aSeed + 21.0) * 2.0 - 1.0) * (uArea.x - 0.1);
      float z = (h(aSeed + 33.0) * 2.0 - 1.0) * (uArea.z - 0.1);
      float phase = fract(uTime * (0.9 + h(aSeed + 41.0) * 0.7) + h(aSeed + 47.0));
      float r = 0.045 + phase * 0.19;
      p = vec3(x + position.x * 2.0 * r, 0.025, z - position.y * 2.0 * r);
      vAlpha = uIntensity * (1.0 - phase) * 0.5;
    }
    gl_Position = projectionMatrix * modelViewMatrix * vec4(p, 1.0);
  }
`;

// Pond variant (§C11.2 fishingPond): rings only, camera-facing in the x/y
// plane, squashed vertically so they read as surface ripples side-on.
const POND_VERT = /* glsl */ `
  attribute float aSeed;
  uniform float uTime;
  uniform float uIntensity;
  uniform vec3 uPond; // x = half-width, y = surface y, z = ring plane z
  varying vec2 vUv;
  varying float vKind;
  varying float vAlpha;
  float h(float n) { return fract(sin(n * 127.1) * 43758.5453); }
  void main() {
    vUv = uv;
    vKind = 1.0;
    float x = (h(aSeed) * 2.0 - 1.0) * uPond.x;
    float phase = fract(uTime * (0.8 + h(aSeed + 41.0) * 0.6) + h(aSeed + 47.0));
    float r = 0.05 + phase * 0.34;
    vec3 p = vec3(x + position.x * 2.0 * r, uPond.y + position.y * 2.0 * r * 0.26, uPond.z);
    vAlpha = uIntensity * (1.0 - phase) * 0.75;
    gl_Position = projectionMatrix * modelViewMatrix * vec4(p, 1.0);
  }
`;

const RAIN_FRAG = /* glsl */ `
  varying vec2 vUv;
  varying float vKind;
  varying float vAlpha;
  void main() {
    float a;
    if (vKind < 0.5) {
      // V6/FIX4 (P2-2): thin bright core with a wide soft falloff plus a
      // full head-to-tail alpha gradient — the old 0.3 alpha floor kept the
      // whole quad lit, which read as a solid white slash
      float across = 1.0 - smoothstep(0.04, 0.5, abs(vUv.x - 0.5));
      float along = smoothstep(0.0, 0.45, vUv.y) * (1.0 - smoothstep(0.5, 1.0, vUv.y));
      a = across * along;
    } else {
      // thin ring band
      float d = length(vUv - 0.5) * 2.0;
      a = smoothstep(0.55, 0.8, d) * (1.0 - smoothstep(0.84, 1.0, d));
    }
    a *= vAlpha;
    if (a < 0.01) discard;
    gl_FragColor = vec4(0.78, 0.86, 0.97, a);
  }
`;

/**
 * Instanced quad geometry with per-instance seed/kind attributes.
 * @param {number} count total instances
 * @param {number} splashFrom instances ≥ this index are splash rings (kind 1)
 * @returns {THREE.InstancedBufferGeometry}
 */
function makeInstancedQuads(count, splashFrom) {
  const base = new THREE.PlaneGeometry(1, 1);
  const geo = new THREE.InstancedBufferGeometry();
  geo.index = base.index;
  geo.setAttribute('position', base.attributes.position);
  geo.setAttribute('uv', base.attributes.uv);
  geo.instanceCount = count;
  const seeds = new Float32Array(count);
  const kinds = new Float32Array(count);
  for (let i = 0; i < count; i += 1) {
    seeds[i] = i + 1;
    kinds[i] = i >= splashFrom ? 1 : 0;
  }
  geo.setAttribute('aSeed', new THREE.InstancedBufferAttribute(seeds, 1));
  geo.setAttribute('aKind', new THREE.InstancedBufferAttribute(kinds, 1));
  return geo;
}

/**
 * @typedef {Object} WeatherFxHandle
 * @property {THREE.Mesh|THREE.InstancedMesh} mesh
 * @property {(on: boolean) => void} setActive fade the effect in/out
 * @property {() => boolean} isActive
 * @property {(dt: number) => void} update
 * @property {() => void} dispose
 */

/**
 * Garden rain (§C11.2): 300 instanced quads — falling streaks + ground splash
 * rings — as ONE mesh = ONE extra draw call while raining (§A2.3). Add to the
 * garden room group (room-local coordinates); visibility follows the group
 * plus the fade (invisible ⇒ zero draw calls).
 * @param {THREE.Group} group the garden room group (roomManager.getRoomGroup)
 * @returns {WeatherFxHandle}
 */
export function mountGardenRain(group) {
  const geo = makeInstancedQuads(WEATHER_FX.RAIN_POOL, WEATHER_FX.RAIN_POOL - WEATHER_FX.SPLASH_COUNT);
  const mat = new THREE.ShaderMaterial({
    vertexShader: RAIN_VERT,
    fragmentShader: RAIN_FRAG,
    uniforms: {
      uTime: { value: 0 },
      uIntensity: { value: 0 },
      // uArea packs (halfX, ceilingY, halfZ) — see the vertex shader
      uArea: { value: new THREE.Vector3(WEATHER_FX.AREA_X, WEATHER_FX.TOP_Y, WEATHER_FX.AREA_Z) },
    },
    transparent: true,
    depthWrite: false,
    side: THREE.DoubleSide,
  });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.name = 'gardenRain';
  mesh.frustumCulled = false; // instances are positioned in the shader
  mesh.renderOrder = 12; // after the dome + room props
  mesh.visible = false;
  group.add(mesh);

  let target = 0;
  let cur = 0;
  const handle = {
    mesh,
    setActive(on) {
      target = on ? 1 : 0;
      if (on) mesh.visible = true;
    },
    isActive: () => target > 0,
    update(dt) {
      mat.uniforms.uTime.value += dt;
      if (cur !== target) {
        cur += Math.sign(target - cur) * Math.min(Math.abs(target - cur), dt / WEATHER_FX.FADE_SEC);
        mat.uniforms.uIntensity.value = cur;
        if (cur <= 0.004 && target === 0) mesh.visible = false;
      }
    },
    dispose() {
      liveHandles.delete(handle);
      group.remove(mesh);
      geo.dispose();
      mat.dispose();
    },
  };
  liveHandles.add(handle);
  return handle;
}

// ---------------------------------------------------------------------------
// Drifting clouds (cloudy — §C11.2)
// ---------------------------------------------------------------------------

/**
 * V4/POLISH-C cloud-sprite tuning (§C11.2 "soft cloud sprites drift"): a
 * 4-variant edge-safe soft-alpha atlas + per-instance scale/opacity/roll
 * variation, spherically billboarded toward the camera each frame — still
 * ONE InstancedMesh (§A2.3: only the instance matrices change; 1 draw call).
 */
const CLOUD_FX = Object.freeze({
  /** Atlas canvas size (pow-2; 2×2 cells of 512×256 → hi-res sprites). */
  ATLAS_W: 1024,
  ATLAS_H: 512,
  /** Atlas grid: COLS×ROWS = 4 distinct cloud shape variants. */
  COLS: 2,
  ROWS: 2,
  /** Cell-edge padding fraction — puff extents never reach the cell edge. */
  PAD: 0.1,
  /** Per-instance width range (m); height ≈ width × H_FACTOR ± H_JITTER. */
  W_MIN: 2.1,
  W_RANGE: 2.3,
  H_FACTOR: 0.5,
  H_JITTER: 0.24,
  /** Per-instance opacity range (multiplied by the global fade). */
  ALPHA_MIN: 0.52,
  ALPHA_RANGE: 0.36,
  /** Max per-instance roll (rad) so the billboards don't look stamped. */
  ROLL_MAX: 0.09,
  /** Drift volume (room-local): x wrap extent, y band, z depth band. */
  X_WRAP: 9.5,
  Y_MIN: 2.9,
  Y_RANGE: 2.3,
  Z_MIN: -8.6,
  Z_RANGE: 3.0,
  /** Drift speed range (m/s) — larger clouds get the slower end. */
  SPEED_MIN: 0.1,
  SPEED_RANGE: 0.16,
  /** Gentle vertical bob amplitude (m) / angular frequency (rad/s). */
  BOB_AMP: 0.06,
  BOB_FREQ: 0.35,
});

/** deterministic decorrelated hash → [0,1) (same recipe as gfx/sky.js) */
const cloudHash = (i, salt) => {
  const s = Math.sin(i * 127.1 + salt * 311.7) * 43758.5453;
  return s - Math.floor(s);
};

/** @type {THREE.CanvasTexture|null} shared 4-variant cloud atlas texture */
let cloudTex = null;

/**
 * The shared cloud sprite atlas (V4/POLISH-C): CLOUD_FX.COLS×ROWS soft cloud
 * variants on one pow-2 canvas. Every puff keeps center ± radius inside its
 * padded cell so no sprite ever clips flat at an edge (the old 128×64 canvas
 * cut its puffs at v = 0/1), and the radial falloff reaches alpha 0 well
 * before the rim. A source-atop blue-grey base shade gives the puffs depth.
 * Deterministic (hash-seeded) — no Math.random.
 * @returns {THREE.CanvasTexture}
 */
function getCloudTexture() {
  if (cloudTex) return cloudTex;
  const canvas = document.createElement('canvas');
  canvas.width = CLOUD_FX.ATLAS_W;
  canvas.height = CLOUD_FX.ATLAS_H;
  const g = canvas.getContext('2d');
  const cw = CLOUD_FX.ATLAS_W / CLOUD_FX.COLS;
  const ch = CLOUD_FX.ATLAS_H / CLOUD_FX.ROWS;
  for (let v = 0; v < CLOUD_FX.COLS * CLOUD_FX.ROWS; v += 1) {
    const x0 = (v % CLOUD_FX.COLS) * cw;
    const y0 = Math.floor(v / CLOUD_FX.COLS) * ch;
    const padX = cw * CLOUD_FX.PAD;
    const padY = ch * CLOUD_FX.PAD;
    // large base puffs along an arced center line + smaller top bumps
    const puffs = 8 + (v % 3) * 2;
    for (let k = 0; k < puffs; k += 1) {
      const t = k / (puffs - 1);
      const mid = 1 - Math.abs(t - 0.5) * 2; // 0 at the ends, 1 in the middle
      const top = k % 2 === 1;
      const r = ch * (0.15 + 0.17 * mid) * (0.75 + cloudHash(k, v * 7 + 1) * 0.5) * (top ? 0.7 : 1);
      // clamp centers so cx ± r / cy ± r stay inside the padded cell
      const spanX = Math.max(0, cw - 2 * padX - 2 * r);
      const tx = Math.min(1, Math.max(0, t + (cloudHash(k, v * 7 + 2) - 0.5) * 0.12));
      const cx = x0 + padX + r + spanX * tx;
      const rawY = y0 + ch * (top ? 0.42 : 0.6) + (cloudHash(k, v * 7 + 3) - 0.5) * ch * 0.12;
      const cy = Math.min(y0 + ch - padY - r, Math.max(y0 + padY + r, rawY));
      const grad = g.createRadialGradient(cx, cy, r * 0.08, cx, cy, r);
      grad.addColorStop(0, 'rgba(255,255,255,0.92)');
      grad.addColorStop(0.55, 'rgba(255,255,255,0.5)');
      grad.addColorStop(0.85, 'rgba(255,255,255,0.14)');
      grad.addColorStop(1, 'rgba(255,255,255,0)');
      g.fillStyle = grad;
      g.fillRect(x0, y0, cw, ch);
    }
    // subtle blue-grey base shading (alpha-preserving) for a rounded read
    const shade = g.createLinearGradient(0, y0 + ch * 0.35, 0, y0 + ch);
    shade.addColorStop(0, 'rgba(178,196,222,0)');
    shade.addColorStop(1, 'rgba(178,196,222,0.4)');
    g.globalCompositeOperation = 'source-atop';
    g.fillStyle = shade;
    g.fillRect(x0, y0, cw, ch);
    g.globalCompositeOperation = 'source-over';
  }
  cloudTex = new THREE.CanvasTexture(canvas);
  cloudTex.colorSpace = THREE.SRGBColorSpace;
  return cloudTex;
}

// Cloud shader: instanceMatrix billboard transform + per-instance atlas cell
// and opacity — MeshBasicMaterial can't vary UV/alpha per instance, so this
// tiny ShaderMaterial keeps the variation inside the ONE draw call (§A2.3).
const CLOUD_VERT = /* glsl */ `
  attribute vec2 aCell;   // atlas cell UV origin (bottom-left)
  attribute float aAlpha; // per-instance opacity
  uniform vec2 uCellSize; // atlas cell UV extent
  varying vec2 vUv;
  varying float vAlpha;
  void main() {
    vUv = aCell + uv * uCellSize;
    vAlpha = aAlpha;
    gl_Position = projectionMatrix * modelViewMatrix * instanceMatrix * vec4(position, 1.0);
  }
`;

const CLOUD_FRAG = /* glsl */ `
  uniform sampler2D uMap;
  uniform float uOpacity;
  varying vec2 vUv;
  varying float vAlpha;
  void main() {
    vec4 c = texture2D(uMap, vUv);
    float a = c.a * vAlpha * uOpacity;
    if (a < 0.01) discard;
    gl_FragColor = vec4(c.rgb, a);
  }
`;

/**
 * Soft cloud sprites drifting across the garden dome while cloudy (§C11.2).
 * ONE InstancedMesh = one draw call. V4/POLISH-C: each instance picks one of
 * 4 atlas variants with its own scale/opacity/roll, and every frame the
 * camera-facing rotation is composed into the instance matrices
 * (onBeforeRender receives the rendering camera — no API change), so the
 * sprites read as soft volumes instead of parallel cardboard cutouts.
 * @param {THREE.Group} group the garden room group
 * @returns {WeatherFxHandle}
 */
export function mountGardenClouds(group) {
  const N = WEATHER_FX.CLOUD_COUNT;
  const geo = new THREE.PlaneGeometry(1, 1);
  const cells = new Float32Array(N * 2);
  const alphas = new Float32Array(N);
  const mat = new THREE.ShaderMaterial({
    vertexShader: CLOUD_VERT,
    fragmentShader: CLOUD_FRAG,
    uniforms: {
      uMap: { value: getCloudTexture() },
      uCellSize: { value: new THREE.Vector2(1 / CLOUD_FX.COLS, 1 / CLOUD_FX.ROWS) },
      uOpacity: { value: 0 },
    },
    transparent: true,
    depthWrite: false,
  });
  const mesh = new THREE.InstancedMesh(geo, mat, N);
  mesh.name = 'gardenClouds';
  mesh.renderOrder = 2; // over the dome, under the rain
  mesh.frustumCulled = false;
  mesh.visible = false;
  group.add(mesh);

  // seeded drift lanes across the visible dome half (camera looks toward −z)
  const clouds = [];
  for (let i = 0; i < N; i += 1) {
    const sizeT = cloudHash(i, 4);
    const w = CLOUD_FX.W_MIN + CLOUD_FX.W_RANGE * sizeT;
    const variant = i % (CLOUD_FX.COLS * CLOUD_FX.ROWS);
    // atlas cell origin in UV space (canvas top row → v = 1 - 1/ROWS)
    cells[i * 2] = (variant % CLOUD_FX.COLS) / CLOUD_FX.COLS;
    cells[i * 2 + 1] = 1 - (Math.floor(variant / CLOUD_FX.COLS) + 1) / CLOUD_FX.ROWS;
    alphas[i] = CLOUD_FX.ALPHA_MIN + cloudHash(i, 6) * CLOUD_FX.ALPHA_RANGE;
    clouds.push({
      x: -CLOUD_FX.X_WRAP + cloudHash(i, 1) * 2 * CLOUD_FX.X_WRAP,
      y: CLOUD_FX.Y_MIN + cloudHash(i, 2) * CLOUD_FX.Y_RANGE,
      z: CLOUD_FX.Z_MIN + cloudHash(i, 3) * CLOUD_FX.Z_RANGE,
      w,
      h: w * CLOUD_FX.H_FACTOR * (1 - CLOUD_FX.H_JITTER / 2 + cloudHash(i, 5) * CLOUD_FX.H_JITTER),
      // §C11.2 "soft ... drift"; bigger clouds drift on the slower end
      speed: (CLOUD_FX.SPEED_MIN + CLOUD_FX.SPEED_RANGE * cloudHash(i, 7)) * (1.15 - 0.5 * sizeT),
      roll: (cloudHash(i, 8) - 0.5) * 2 * CLOUD_FX.ROLL_MAX,
      bobPhase: cloudHash(i, 10) * Math.PI * 2,
    });
  }
  geo.setAttribute('aCell', new THREE.InstancedBufferAttribute(cells, 2));
  geo.setAttribute('aAlpha', new THREE.InstancedBufferAttribute(alphas, 1));

  const m = new THREE.Matrix4();
  const pos = new THREE.Vector3();
  const scl = new THREE.Vector3();
  const q = new THREE.Quaternion();
  const camQ = new THREE.Quaternion();
  const meshQ = new THREE.Quaternion();
  const rollQ = new THREE.Quaternion();
  const Z_AXIS = new THREE.Vector3(0, 0, 1);
  let bob = 0; // shared bob clock (per-cloud phase offsets)

  // Billboard pass: rotation = meshWorldRot⁻¹ · camWorldRot · per-cloud roll,
  // composed into every instance matrix right before the mesh renders —
  // onBeforeRender hands us the actual rendering camera without widening the
  // updateWeatherFx(dt) contract, and the mesh stays ONE draw call (§A2.3).
  mesh.onBeforeRender = (renderer, scene, camera) => {
    camera.getWorldQuaternion(camQ);
    mesh.getWorldQuaternion(meshQ).invert();
    camQ.premultiply(meshQ);
    for (let i = 0; i < N; i += 1) {
      const c = clouds[i];
      rollQ.setFromAxisAngle(Z_AXIS, c.roll);
      q.copy(camQ).multiply(rollQ);
      pos.set(c.x, c.y + Math.sin(bob * CLOUD_FX.BOB_FREQ + c.bobPhase) * CLOUD_FX.BOB_AMP, c.z);
      scl.set(c.w, c.h, 1);
      m.compose(pos, q, scl);
      mesh.setMatrixAt(i, m);
    }
    mesh.instanceMatrix.needsUpdate = true;
  };

  let target = 0;
  let cur = 0;
  const handle = {
    mesh,
    setActive(on) {
      target = on ? 1 : 0;
      if (on) mesh.visible = true;
    },
    isActive: () => target > 0,
    update(dt) {
      if (!mesh.visible) return;
      bob += dt;
      for (const c of clouds) {
        c.x += c.speed * dt;
        if (c.x > CLOUD_FX.X_WRAP) c.x = -CLOUD_FX.X_WRAP; // wrap across the dome
      }
      if (cur !== target) {
        cur += Math.sign(target - cur) * Math.min(Math.abs(target - cur), dt / WEATHER_FX.FADE_SEC);
        mat.uniforms.uOpacity.value = cur;
        if (cur <= 0.004 && target === 0) mesh.visible = false;
      }
    },
    dispose() {
      liveHandles.delete(handle);
      group.remove(mesh);
      mesh.dispose(); // frees the instance buffers
      geo.dispose();
      mat.dispose(); // cloudTex stays cached
    },
  };
  liveHandles.add(handle);
  return handle;
}

// ---------------------------------------------------------------------------
// Animated window rain texture (indoor rooms — §C11.2)
// ---------------------------------------------------------------------------

/**
 * @type {{canvas: HTMLCanvasElement, g: CanvasRenderingContext2D,
 *   tex: THREE.CanvasTexture, band: string, accum: number,
 *   streaks: Array<{x: number, y: number, v: number, len: number}>,
 *   runs: Array<{x: number, y: number, v: number, r: number}>}|null}
 */
let winRain = null;

/**
 * The shared animated rain-window texture (§C11.2: streak overlay +
 * occasional droplet runs painted over the band's static rain sky).
 * roomManager.setAmbience swaps it into the window-sky material while
 * raining; updateWeatherFx(dt) animates it. Cached singleton — never dispose.
 * @param {'day'|'dawn'|'dusk'|'night'} band
 * @returns {THREE.CanvasTexture}
 */
export function windowRainTexture(band) {
  const S = WEATHER_FX.WINDOW_SIZE;
  if (!winRain) {
    const canvas = document.createElement('canvas');
    canvas.width = canvas.height = S;
    const g = canvas.getContext('2d');
    const tex = new THREE.CanvasTexture(canvas);
    tex.colorSpace = THREE.SRGBColorSpace;
    const rnd = Math.random;
    winRain = {
      canvas,
      g,
      tex,
      band: '',
      accum: 0,
      // fast diagonal streak trails
      streaks: Array.from({ length: 13 }, () => ({
        x: rnd() * S, y: rnd() * S, v: 55 + rnd() * 65, len: 9 + rnd() * 13,
      })),
      // slow fat droplet runs (the "occasional droplet run")
      runs: Array.from({ length: 3 }, () => ({
        x: rnd() * S, y: rnd() * S, v: 7 + rnd() * 9, r: 1.7 + rnd() * 1.2,
      })),
    };
  }
  if (winRain.band !== band) {
    winRain.band = band;
    paintWindowRain(0);
  }
  return winRain.tex;
}

/** Repaint the window-rain canvas advanced by `dt` seconds. */
function paintWindowRain(dt) {
  const S = WEATHER_FX.WINDOW_SIZE;
  const { g } = winRain;
  // static base: the band's rain sky from G19's painter (cached canvas)
  const base = windowTexture(winRain.band || 'day', 'rain');
  g.clearRect(0, 0, S, S);
  g.drawImage(base.image, 0, 0, S, S);
  // streak trails
  g.strokeStyle = 'rgba(228,241,255,0.55)';
  g.lineWidth = 1.4;
  g.lineCap = 'round';
  for (const s of winRain.streaks) {
    s.y += s.v * dt;
    if (s.y - s.len > S) {
      s.y = -4;
      s.x = Math.random() * S;
    }
    g.beginPath();
    g.moveTo(s.x + 1.5, s.y - s.len);
    g.lineTo(s.x, s.y);
    g.stroke();
  }
  // droplet runs: bead head + thin wobbly trail
  for (const r of winRain.runs) {
    r.y += r.v * dt;
    if (r.y > S + 4) {
      r.y = -4;
      r.x = Math.random() * S;
      r.v = 7 + Math.random() * 9;
    }
    g.strokeStyle = 'rgba(228,241,255,0.35)';
    g.lineWidth = 1;
    g.beginPath();
    g.moveTo(r.x + Math.sin(r.y * 0.2) * 1.5, Math.max(0, r.y - 14));
    g.lineTo(r.x, r.y);
    g.stroke();
    g.fillStyle = 'rgba(238,247,255,0.8)';
    g.beginPath();
    g.arc(r.x, r.y, r.r, 0, Math.PI * 2);
    g.fill();
  }
  winRain.tex.needsUpdate = true;
}

// ---------------------------------------------------------------------------
// fishingPond ripple rings (§C11.2 — cosmetic, rain only)
// ---------------------------------------------------------------------------

/**
 * Rain ripple rings for the fishingPond surface (§C11.2): ONE instanced mesh
 * of camera-facing squashed rings popping along the water line. The pond
 * game drives update(dt)/dispose() itself (its scene, its loop).
 * @param {THREE.Scene} scene
 * @param {{surfaceY: number, halfW: number, z?: number}} opts
 * @returns {WeatherFxHandle}
 */
export function mountPondRipples(scene, { surfaceY, halfW, z = 0.55 }) {
  const geo = makeInstancedQuads(WEATHER_FX.POND_RINGS, 0); // all rings
  const mat = new THREE.ShaderMaterial({
    vertexShader: POND_VERT,
    fragmentShader: RAIN_FRAG,
    uniforms: {
      uTime: { value: 0 },
      uIntensity: { value: 1 },
      uPond: { value: new THREE.Vector3(halfW, surfaceY, z) },
    },
    transparent: true,
    depthWrite: false,
    side: THREE.DoubleSide,
  });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.name = 'pondRipples';
  mesh.frustumCulled = false;
  mesh.renderOrder = 6;
  scene.add(mesh);
  const handle = {
    mesh,
    setActive(on) {
      mesh.visible = !!on;
    },
    isActive: () => mesh.visible,
    update(dt) {
      mat.uniforms.uTime.value += dt;
    },
    dispose() {
      scene.remove(mesh);
      geo.dispose();
      mat.dispose();
    },
  };
  return handle;
}

// ---------------------------------------------------------------------------
// Orchestrator
// ---------------------------------------------------------------------------

/**
 * Advance every mounted garden effect + the animated window texture.
 * homeScene calls this once per frame (§C11.2). Cheap when idle: faded
 * effects early-out and the window canvas repaints at ~11 fps only while a
 * rain texture exists.
 * @param {number} dt seconds
 */
export function updateWeatherFx(dt) {
  for (const handle of liveHandles) handle.update(dt);
  if (winRain) {
    winRain.accum += dt;
    if (winRain.accum >= WEATHER_FX.WINDOW_REPAINT_SEC) {
      paintWindowRain(winRain.accum);
      winRain.accum = 0;
    }
  }
}
