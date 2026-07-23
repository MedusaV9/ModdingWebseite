// V6/A3 — Batched home ambient life (PLAN6 Wave A / A3): low-cost decorative
// motion in all 5 rooms with day-band/weather switching. This is the
// three.js MOUNT side only — every row, gate, budget number and home-specific
// sampler lives in the pure sibling src/home/ambientLife.data.js, and the
// proven motion samplers are imported from src/recap/vignettes.logic.js
// (flutterPose/driftPose — reused, not copied). node tests therefore never
// import this file.
//
// Contract (homeScene.js owns the lifecycle via marked V6/A3 blocks):
//   const ambient = createAmbientLife({ rm });   // after createRoomManager
//   ambient.setConditions(band, weather);        // inside applyAmbienceNow()
//   ambient.update(dt);                          // beside updateWeatherFx(dt)
//   ambient.dispose();                           // homeScene dispose()
//
// Behavior:
// - Mounts only the ACTIVE room's rows (roomManager 'roomChanged' hook) into
//   rm.getRoomGroup(roomId) — room-local coordinates, so anchors resolve via
//   the V6/A3 rm.getAnchorLocal() helper.
// - One draw batch per row: a single THREE.Sprite per flutter/drift/twinkle
//   row, one InstancedMesh for the firefly swarm — ≤ 4 added draw calls per
//   room for every {band, weather} combination (machine-proved in
//   test/ambientLife.test.js against MAX_AMBIENT_BATCHES_PER_ROOM, and
//   reported live by getDebugStats()).
// - Band/weather swaps remount idempotently (keyed on room|band|weather).
// - No-op under prefersReducedMotion() (ui/ui.js predicate): nothing mounts.
// - Rides homeScene.update(dt) → pauses automatically with the RAF loop.
// - Never intercepts taps: every object gets a no-op raycast (roomManager
//   only raycasts its own hitboxes + Gooby anyway — this is belt & braces).
// - Leak-friendly teardown: every geometry/material/texture is tracked in
//   the pure disposal ledger and disposed on unmount/dispose.

import * as THREE from 'three';
import { prefersReducedMotion } from '../ui/ui.js';
import { flutterPose, driftPose } from '../recap/vignettes.logic.js';
import {
  activeRows,
  fireflyPose,
  twinklePose,
  createDisposalLedger,
} from './ambientLife.data.js';

const TEX_SIZE = 64;

/** Shared no-op raycast so ambient decor can never swallow a tap:* raycast. */
const NO_RAYCAST = () => {};

// ---------------------------------------------------------------------------
// Canvas texture painters (all tintable via material color unless the id
// paints its own colors, e.g. the bee). One 64 px canvas per id per instance.
// ---------------------------------------------------------------------------

/** @param {CanvasRenderingContext2D} g @param {number} s */
function paintButterfly(g, s) {
  // two round wing lobes per side + dark body (recap's proven silhouette)
  g.fillStyle = '#ffffff';
  g.beginPath();
  g.ellipse(s * 0.32, s * 0.38, s * 0.2, s * 0.26, -0.5, 0, Math.PI * 2);
  g.ellipse(s * 0.68, s * 0.38, s * 0.2, s * 0.26, 0.5, 0, Math.PI * 2);
  g.ellipse(s * 0.36, s * 0.66, s * 0.13, s * 0.17, -0.7, 0, Math.PI * 2);
  g.ellipse(s * 0.64, s * 0.66, s * 0.13, s * 0.17, 0.7, 0, Math.PI * 2);
  g.fill();
  g.fillStyle = 'rgba(60,45,40,0.85)';
  g.beginPath();
  g.ellipse(s * 0.5, s * 0.5, s * 0.05, s * 0.2, 0, 0, Math.PI * 2);
  g.fill();
}

/** @param {CanvasRenderingContext2D} g @param {number} s */
function paintBee(g, s) {
  // self-colored: translucent wings, gold body, two dark stripes
  g.fillStyle = 'rgba(230,240,255,0.75)';
  g.beginPath();
  g.ellipse(s * 0.38, s * 0.3, s * 0.14, s * 0.09, -0.6, 0, Math.PI * 2);
  g.ellipse(s * 0.62, s * 0.3, s * 0.14, s * 0.09, 0.6, 0, Math.PI * 2);
  g.fill();
  g.fillStyle = '#FFD166';
  g.beginPath();
  g.ellipse(s * 0.5, s * 0.58, s * 0.24, s * 0.18, 0, 0, Math.PI * 2);
  g.fill();
  g.save();
  g.beginPath();
  g.ellipse(s * 0.5, s * 0.58, s * 0.24, s * 0.18, 0, 0, Math.PI * 2);
  g.clip();
  g.fillStyle = '#4A3B36';
  g.fillRect(s * 0.4, s * 0.36, s * 0.08, s * 0.46);
  g.fillRect(s * 0.58, s * 0.36, s * 0.08, s * 0.46);
  g.restore();
}

/** soft radial puff (steam wisps) */
function paintPuff(g, s) {
  const grad = g.createRadialGradient(s / 2, s / 2, 2, s / 2, s / 2, s / 2);
  grad.addColorStop(0, 'rgba(255,255,255,0.9)');
  grad.addColorStop(0.55, 'rgba(255,255,255,0.3)');
  grad.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = grad;
  g.fillRect(0, 0, s, s);
}

/** soft round glow dot (dust motes + firefly instances) */
function paintGlowDot(g, s) {
  const grad = g.createRadialGradient(s / 2, s / 2, 1, s / 2, s / 2, s / 2);
  grad.addColorStop(0, 'rgba(255,255,255,1)');
  grad.addColorStop(0.4, 'rgba(255,255,255,0.85)');
  grad.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = grad;
  g.fillRect(0, 0, s, s);
}

/** soap bubble: thin rim + off-center highlight over a faint fill */
function paintBubble(g, s) {
  const c = s / 2;
  const r = s * 0.4;
  g.fillStyle = 'rgba(255,255,255,0.14)';
  g.beginPath();
  g.arc(c, c, r, 0, Math.PI * 2);
  g.fill();
  g.strokeStyle = 'rgba(255,255,255,0.9)';
  g.lineWidth = s * 0.05;
  g.beginPath();
  g.arc(c, c, r, 0, Math.PI * 2);
  g.stroke();
  g.fillStyle = 'rgba(255,255,255,0.85)';
  g.beginPath();
  g.arc(c - r * 0.38, c - r * 0.38, r * 0.2, 0, Math.PI * 2);
  g.fill();
}

/** 4-point twinkle star (bedroom window glint) */
function paintStar4(g, s) {
  const c = s / 2;
  const R = s * 0.46;
  const r = s * 0.09;
  g.fillStyle = '#FFFFFF';
  g.beginPath();
  g.moveTo(c, c - R);
  g.quadraticCurveTo(c + r, c - r, c + R, c);
  g.quadraticCurveTo(c + r, c + r, c, c + R);
  g.quadraticCurveTo(c - r, c + r, c - R, c);
  g.quadraticCurveTo(c - r, c - r, c, c - R);
  g.fill();
}

/** @type {Record<string, (g: CanvasRenderingContext2D, s: number) => void>} */
const PAINTERS = {
  butterfly: paintButterfly,
  bee: paintBee,
  puff: paintPuff,
  glowDot: paintGlowDot,
  bubble: paintBubble,
  star4: paintStar4,
};

/**
 * Batched ambient life for the home scene. Reduced motion → inert stub with
 * the same API (nothing mounts, all methods no-op).
 *
 * @param {{rm: {
 *   activeRoom: () => string,
 *   getRoomGroup: (roomId: string) => THREE.Group|null,
 *   getAnchorLocal?: (name: string, roomId?: string) => THREE.Vector3|null,
 *   on: (event: string, cb: Function) => () => void,
 * }}} deps
 */
export function createAmbientLife({ rm }) {
  const reducedMotion = prefersReducedMotion();

  /** instance-lifetime texture cache (id → THREE.CanvasTexture) */
  const texCache = new Map();
  /** textures live for the instance; geometries/materials per mount */
  const texLedger = createDisposalLedger();
  const mountLedger = createDisposalLedger();

  let room = rm.activeRoom?.() ?? null;
  let band = null;
  let weather = null;
  let mountKey = null;
  /** @type {THREE.Group|null} */
  let group = null;
  /** @type {Array<object>} one entry per draw batch (sprite or instanced) */
  let performers = [];
  let t = 0;
  let disposed = false;

  // per-frame scratch (no allocations in update paths)
  const scratchMat4 = new THREE.Matrix4();
  const scratchPos = new THREE.Vector3();
  const scratchQuat = new THREE.Quaternion();
  const scratchScale = new THREE.Vector3();
  const scratchColor = new THREE.Color();

  function getTexture(id) {
    if (texCache.has(id)) return texCache.get(id);
    const canvas = document.createElement('canvas');
    canvas.width = canvas.height = TEX_SIZE;
    const g = canvas.getContext('2d');
    (PAINTERS[id] ?? paintGlowDot)(g, TEX_SIZE);
    const tex = new THREE.CanvasTexture(canvas);
    tex.colorSpace = THREE.SRGBColorSpace;
    texCache.set(id, tex);
    texLedger.track(tex, 'texture');
    return tex;
  }

  /** row-local base position: anchor + offset, or absolute at (data docs). */
  function basePosition(row) {
    if (row.anchor) {
      const local = rm.getAnchorLocal?.(row.anchor, room);
      if (local) {
        return [local.x + row.at[0], local.y + row.at[1], local.z + row.at[2]];
      }
    }
    return [row.at[0], row.at[1], row.at[2]];
  }

  function makeSprite(row, { additive = false, opacity = 1 } = {}) {
    const mat = mountLedger.track(new THREE.SpriteMaterial({
      map: getTexture(row.tex),
      transparent: true,
      opacity,
      depthWrite: false,
      ...(additive ? { blending: THREE.AdditiveBlending } : {}),
    }), 'material');
    if (row.color) mat.color.set(row.color);
    const sprite = new THREE.Sprite(mat);
    sprite.name = `ambient-${row.id}`;
    sprite.raycast = NO_RAYCAST;
    sprite.scale.set(row.scale, row.scale, 1);
    group.add(sprite);
    return sprite;
  }

  function buildRow(row) {
    const base = basePosition(row);
    if (row.kind === 'flutter') {
      // flutterPose reads row.center — derive a sampler row once at mount
      const sRow = { ...row, center: base };
      const sprite = makeSprite(row);
      performers.push({ kind: 'flutter', row: sRow, sprite });
    } else if (row.kind === 'drift') {
      const sRow = { ...row, origin: base };
      const sprite = makeSprite(row, { opacity: 0 });
      performers.push({ kind: 'drift', row: sRow, sprite });
    } else if (row.kind === 'twinkle') {
      const sprite = makeSprite(row, { additive: true, opacity: row.baseOpacity });
      sprite.position.set(base[0], base[1], base[2]);
      performers.push({ kind: 'twinkle', row, sprite });
    } else if (row.kind === 'fireflies') {
      const geo = mountLedger.track(new THREE.PlaneGeometry(1, 1), 'geometry');
      const mat = mountLedger.track(new THREE.MeshBasicMaterial({
        map: getTexture(row.tex),
        transparent: true,
        depthWrite: false,
        blending: THREE.AdditiveBlending,
        color: '#ffffff',
        toneMapped: false,
      }), 'material');
      const mesh = new THREE.InstancedMesh(geo, mat, row.count);
      mesh.name = `ambient-${row.id}`;
      mesh.raycast = NO_RAYCAST;
      mesh.frustumCulled = false; // instances wander past the unit-plane bounds
      mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
      scratchColor.set(row.color);
      for (let i = 0; i < row.count; i += 1) mesh.setColorAt(i, scratchColor);
      const baseColor = new THREE.Color(row.color);
      group.add(mesh);
      performers.push({ kind: 'fireflies', row, mesh, base, baseColor });
    }
  }

  function unmount() {
    if (!group) return;
    group.parent?.remove(group);
    mountLedger.disposeAll(); // geometries + materials (textures stay cached)
    group = null;
    performers = [];
    mountKey = null;
  }

  function mount() {
    if (disposed || reducedMotion) return;
    if (!room || !band || !weather) return;
    const key = `${room}|${band}|${weather}`;
    if (key === mountKey && group) return; // idempotent swap
    unmount();
    const roomGroup = rm.getRoomGroup?.(room);
    if (!roomGroup) return;
    const rows = activeRows(room, band, weather);
    mountKey = key;
    if (rows.length === 0) return;
    group = new THREE.Group();
    group.name = `ambient-life-${room}`;
    roomGroup.add(group);
    for (const row of rows) buildRow(row);
  }

  function tickFireflies(p) {
    const { row, mesh, base, baseColor } = p;
    for (let i = 0; i < row.count; i += 1) {
      const pose = fireflyPose(row, i, t);
      const s = pose.size * (0.7 + 0.5 * pose.blink);
      scratchPos.set(
        base[0] + pose.position[0],
        base[1] + pose.position[1],
        base[2] + pose.position[2]
      );
      scratchScale.set(s, s, s);
      scratchMat4.compose(scratchPos, scratchQuat, scratchScale);
      mesh.setMatrixAt(i, scratchMat4);
      scratchColor.copy(baseColor).multiplyScalar(0.3 + 0.7 * pose.blink);
      mesh.setColorAt(i, scratchColor);
    }
    mesh.instanceMatrix.needsUpdate = true;
    if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
  }

  // roomManager 'roomChanged' drives the per-room mount/dispose swap
  const offRoomChanged = reducedMotion
    ? null
    : rm.on?.('roomChanged', ({ roomId }) => {
      room = roomId;
      mount();
    }) ?? null;

  const api = {
    /**
     * Band/weather gate swap — homeScene calls this from applyAmbienceNow()
     * (marked V6/A3 hook), so it also runs once at enter() and on every
     * dayBandChanged/weatherChanged/sleepChanged/room switch.
     * @param {'night'|'dawn'|'day'|'dusk'} nextBand
     * @param {'clear'|'cloudy'|'rain'} nextWeather
     */
    setConditions(nextBand, nextWeather) {
      if (disposed || reducedMotion) return;
      band = nextBand;
      weather = nextWeather;
      room = rm.activeRoom?.() ?? room;
      mount();
    },

    /** Per-frame tick — rides homeScene.update(dt), pausing with the RAF loop. */
    update(dt) {
      if (disposed || reducedMotion || performers.length === 0) return;
      t += dt;
      for (const p of performers) {
        if (p.kind === 'flutter') {
          const pose = flutterPose(p.row, t);
          p.sprite.position.set(pose.position[0], pose.position[1], pose.position[2]);
          // wing flap: squeeze width against a steady height (recap recipe)
          p.sprite.scale.set(p.row.scale * (0.35 + 0.65 * pose.flap), p.row.scale, 1);
        } else if (p.kind === 'drift') {
          const pose = driftPose(p.row, t);
          p.sprite.position.set(pose.position[0], pose.position[1], pose.position[2]);
          p.sprite.material.opacity = pose.opacity;
          p.sprite.scale.set(p.row.scale * pose.grow, p.row.scale * pose.grow, 1);
        } else if (p.kind === 'twinkle') {
          const pose = twinklePose(p.row, t);
          p.sprite.material.opacity = pose.opacity;
          p.sprite.scale.set(p.row.scale * pose.pulse, p.row.scale * pose.pulse, 1);
        } else if (p.kind === 'fireflies') {
          tickFireflies(p);
        }
      }
    },

    /**
     * Live budget proof (PLAN6 §A3: ≤4 added draw calls per room):
     * `batches` is the number of mounted draw batches right now.
     * @returns {{reducedMotion: boolean, room: string|null, band: string|null,
     *   weather: string|null, batches: number, outstandingMountResources: number,
     *   textures: number}}
     */
    getDebugStats() {
      return {
        reducedMotion,
        room,
        band,
        weather,
        batches: performers.length,
        outstandingMountResources: mountLedger.outstanding(),
        textures: texLedger.outstanding(),
      };
    },

    /** Full teardown: unmount + dispose every tracked geometry/material/texture. */
    dispose() {
      if (disposed) return;
      disposed = true;
      offRoomChanged?.();
      unmount();
      texLedger.disposeAll();
      texCache.clear();
    },
  };

  // first mount happens when homeScene's applyAmbienceNow() pushes conditions
  return api;
}
