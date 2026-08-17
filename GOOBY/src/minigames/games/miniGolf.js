// Mini Golf — „Minigolf" (PLAN2 §C1.2 #6, agent V2/G28): 6 seeded holes
// assembled from minigolf-kit tiles on floating pastel islands (§C1.3: THE
// pastel-sky look — no other game shares it). Drag back from the ball to aim
// (power = drag length, capped; dotted preview), release to putt; the ball
// rolls with friction 0.985/frame, banks off walls, dodges a bump dome,
// climbs a ramp, threads a rhythmically blocking windmill gate and a tunnel.
// Per-hole scoring 30/20/12/6 (hole-in-one/≤par/par+1/else), 10-stroke
// auto-advance; Gooby caddies and celebrates/facepalms. Score ≈ 80 → ~16c
// (§C1.1 row 5/4/28, energy 8). Meta: {strokes, holeInOnes} (§B3 — the
// holeInOne achievement rides meta.holeInOnes).
//
// Pure putt physics/course rules live in miniGolf.logic.js. Dev-only
// ?autoplay=1 aims at the cup (or the baked per-hole gap waypoint) with the
// rollDistance power table, times windmill putts to the open gate.

import * as THREE from 'three';
import { t } from '../../data/strings.js';
import { tween, easings } from '../../gfx/tween.js';
import { createParticles } from '../../gfx/particles.js';
import { prefersReducedMotion } from '../../ui/ui.js'; // V4/GAME-POLISH-4: gate new flash FX
import { clampFloatTextToView } from '../framework.js'; // V6/C4 (GAME-JUICE)
import { icon, stripRawGlyphs } from '../../ui/icons.js'; // V6/D3: authored flag chip
import { createGooby } from '../../character/gooby.js';
import { applyEquippedOutfits } from '../../character/outfitAttach.js';
import { buildNougatschleuse } from '../../home/nougatMesh.js';
import {
  GOLF,
  GOLF_JUICE, // V4/GAME-POLISH-4: cup-ring/flag-pop/putt-squash tuning
  applyDifficulty,
  createGolfEndlessState,
  recordGolfHole,
  holeScore,
  powerFromDrag,
  powerForDistance,
  rollTimeToDistance,
  windmillBlocked,
  isStopped,
  stepBall,
  generateCourse,
  createNougatLoopHole,
  qualifiesNougatLoop,
  nougatXAt,
  cellRoles,
  heightAt,
} from './miniGolf.logic.js';

/** World x spacing between the six floating hole islands. */
const HOLE_SPACING = 8;
/** Ball rest height over the tile floor. */
const BALL_Y = 0.075;
/** Windmill blade angular speed (rad/s). */
const OMEGA = Math.PI * 2 * GOLF.WINDMILL_RPS;

// ── V6/C4 (GAME-JUICE): golf-juice tuning — frozen module-local (§E0.1-3;
// miniGolf.logic.js is not owned by this pass). STRICTLY cosmetic: the frozen
// §C1.2 #6 GOLF scoring table (30/20/12/6) is untouched — pinned by
// test/gamePolish6.test.js.
export const GOLF_JUICE6 = Object.freeze({
  /** Roll trail: sparkles while the ball runs hot (power shots, §C.4 #2). */
  TRAIL_MIN_SPEED: 2.2,
  TRAIL_EVERY_SEC: 0.08,
  TRAIL_SPARKLES: 2, // halved under OS reduced motion
  /** Power ticks: ui.count as the drag crosses each third of MAX_POWER. */
  POWER_TICK_THIRDS: 3,
  /** Bank flash: pooled impact-ring ping at the ball on bank/bump (§C.4 #4). */
  BANK_RING_SCALE: 2.0,
  BANK_RING_SEC: 0.28,
});
// ── end V6/C4 ────────────────────────────────────────────────────────────────

/** V6/C4: tiny floating score text (teaParty.js recipe — self-disposing). */
function createFloatTexts(scene, camera) {
  const active = new Set();
  return {
    spawn(text, pos, color = '#4A3B36') {
      const canvas = document.createElement('canvas');
      canvas.width = 240;
      canvas.height = 80;
      const g = canvas.getContext('2d');
      g.font = '900 40px system-ui, sans-serif';
      g.textAlign = 'center';
      g.textBaseline = 'middle';
      g.lineWidth = 8;
      g.strokeStyle = 'rgba(255,255,255,0.92)';
      g.strokeText(text, 120, 40);
      g.fillStyle = color;
      g.fillText(text, 120, 40);
      const tex = new THREE.CanvasTexture(canvas);
      tex.colorSpace = THREE.SRGBColorSpace;
      const mat = new THREE.SpriteMaterial({ map: tex, transparent: true, depthWrite: false });
      const sprite = new THREE.Sprite(mat);
      sprite.scale.set(1.5, 0.5, 1);
      sprite.position.copy(clampFloatTextToView(pos.clone(), camera, { halfW: 0.75, halfH: 0.25 }));
      scene.add(sprite);
      active.add({ sprite, mat, tex, age: 0, life: 0.9 });
    },
    update(dt) {
      for (const f of active) {
        f.age += dt;
        f.sprite.position.y += dt * 1.1;
        f.mat.opacity = Math.max(0, 1 - (f.age / f.life) ** 2);
        if (f.age >= f.life) {
          f.sprite.parent?.remove(f.sprite);
          f.mat.dispose();
          f.tex.dispose();
          active.delete(f);
        }
      }
    },
    dispose() {
      for (const f of active) {
        f.sprite.parent?.remove(f.sprite);
        f.mat.dispose();
        f.tex.dispose();
      }
      active.clear();
    },
  };
}

/** Pastel sky gradient (§C1.3 binding look — pink → cream → mint). */
function makePastelSky() {
  const canvas = document.createElement('canvas');
  canvas.width = 64;
  canvas.height = 512;
  const g = canvas.getContext('2d');
  const grad = g.createLinearGradient(0, 0, 0, 512);
  grad.addColorStop(0, '#FFD9E8');
  grad.addColorStop(0.45, '#FFF3E0');
  grad.addColorStop(1, '#CDEFFF');
  g.fillStyle = grad;
  g.fillRect(0, 0, 64, 512);
  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

/** Soft white cloud puff sprite texture. */
function makeCloudTexture() {
  const canvas = document.createElement('canvas');
  canvas.width = 128;
  canvas.height = 64;
  const g = canvas.getContext('2d');
  for (const [x, y, r] of [[38, 40, 22], [64, 32, 26], [92, 42, 20], [64, 46, 30]]) {
    const grad = g.createRadialGradient(x, y, 2, x, y, r);
    grad.addColorStop(0, 'rgba(255,255,255,0.95)');
    grad.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = grad;
    g.fillRect(0, 0, 128, 64);
  }
  return new THREE.CanvasTexture(canvas);
}

/**
 * Tile rotY tables (minigolf-kit authoring, verified against the GLB walls):
 * start opens +z at rot 0; straight runs along z; corner opens {−x, −z} at
 * rot 0; hole-round opens −z at rot 0; ramp ascends +z at rot 0.
 */
function startRot(outDir) {
  if (!outDir) return 0;
  if (outDir[0] === 1) return Math.PI / 2;
  if (outDir[0] === -1) return -Math.PI / 2;
  return outDir[1] === -1 ? Math.PI : 0;
}
function straightRot(dir) {
  return dir && dir[0] !== 0 ? Math.PI / 2 : 0;
}
function cornerRot(inDir, outDir) {
  // openings = {entry side = −inDir, exit side = +outDir}
  const open = new Set([`${-inDir[0]},${-inDir[1]}`, `${outDir[0]},${outDir[1]}`]);
  if (open.has('-1,0') && open.has('0,-1')) return 0;
  if (open.has('-1,0') && open.has('0,1')) return Math.PI / 2;
  if (open.has('1,0') && open.has('0,1')) return Math.PI;
  return -Math.PI / 2; // {+x, −z}
}
function holeRot(inDir) {
  // hole-round opens −z at rot 0; entry side = −inDir
  if (inDir[0] === 1) return Math.PI / 2; // entered heading east → open −x… rotated
  if (inDir[0] === -1) return -Math.PI / 2;
  return inDir[1] === -1 ? Math.PI : 0;
}

/** @type {object} §E8 plugin */
export default {
  id: 'miniGolf',
  assetKeys: [
    'minigolf-kit/start',
    'minigolf-kit/straight',
    'minigolf-kit/corner',
    'minigolf-kit/hole-round',
    'minigolf-kit/ramp-low',
    'minigolf-kit/bump',
    'minigolf-kit/windmill',
    'minigolf-kit/tunnel-wide',
    'minigolf-kit/flag-red',
    'food-kit/chocolate',
  ],

  /** @param {object} ctx §E8 game context */
  init(ctx) {
    this.ctx = ctx;
    this.tune = applyDifficulty(GOLF, ctx.params?.difficulty ?? 'normal');
    this.endlessState = createGolfEndlessState(this.tune.ENDLESS_OVER_PAR_LIMIT);
    this.autoplay =
      import.meta.env?.DEV && new URLSearchParams(location.search).get('autoplay') === '1';

    this.course = generateCourse(ctx.rng, this.tune);
    this.holeIdx = 0;
    this.strokes = 0; // current hole
    this.totalStrokes = 0;
    this.score = 0;
    this.holeInOnes = 0;
    this.holeResults = [];
    this.bonusUnlocked = false;
    this.state = 'aim'; // 'aim' | 'rolling' | 'celebrate' | 'ending' | 'done'
    this.stateT = 0;
    this.theta = 0;
    this.botT = 0.9;
    this.wpIdx = 0;
    this.bankSoundT = 0;
    this.aiming = false;

    const scene = ctx.scene;
    /** @type {THREE.BufferGeometry[]} */
    this.ownedGeos = [];
    /** @type {THREE.Material[]} */
    this.ownedMats = [];
    /** @type {THREE.Texture[]} */
    this.ownedTexs = [];
    const own = (mesh) => {
      this.ownedGeos.push(mesh.geometry);
      this.ownedMats.push(mesh.material);
      return mesh;
    };
    this.own = own;
    this.resourceTrack = {
      geo: (geo) => {
        this.ownedGeos.push(geo);
        return geo;
      },
      mat: (mat) => {
        this.ownedMats.push(mat);
        return mat;
      },
    };

    this.skyTex = makePastelSky();
    this.ownedTexs.push(this.skyTex);
    scene.background = this.skyTex;

    // warm soft lighting over the pastel course
    scene.add(new THREE.HemisphereLight('#FFF6E8', '#F5C6D8', 0.95));
    const dir = new THREE.DirectionalLight('#FFFFFF', 0.85);
    dir.position.set(4, 9, 3);
    scene.add(dir);

    // drifting cloud sprites behind the islands
    this.cloudTex = makeCloudTexture();
    this.ownedTexs.push(this.cloudTex);
    this.clouds = [];
    const cloudMat = new THREE.SpriteMaterial({ map: this.cloudTex, transparent: true, opacity: 0.9, depthWrite: false });
    this.ownedMats.push(cloudMat);
    for (let i = 0; i < 5; i += 1) {
      const cloud = new THREE.Sprite(cloudMat);
      cloud.scale.set(4.2 + (i % 3), 1.8, 1);
      cloud.position.set(i * HOLE_SPACING * 1.3 - 4, 1.4 + (i % 3) * 1.1, -6 - (i % 2) * 3);
      scene.add(cloud);
      this.clouds.push(cloud);
    }

    // --- build the six floating islands ------------------------------------
    this.islandMat = new THREE.MeshStandardMaterial({ color: '#FFF3E0', roughness: 0.95 });
    this.ownedMats.push(this.islandMat);
    /** per-hole render extras: [{group, blades?}] */
    this.holeViews = [];
    this.course.forEach((hole, i) => this.buildHoleView(hole, i, own));

    // --- ball + aim preview --------------------------------------------------
    this.ball = { x: 0, z: 0, vx: 0, vz: 0, done: false };
    this.ballMesh = own(new THREE.Mesh(
      new THREE.SphereGeometry(GOLF.BALL_R, 18, 14),
      new THREE.MeshStandardMaterial({ color: '#FFFFFF', roughness: 0.35 })
    ));
    scene.add(this.ballMesh);

    this.dotGeo = new THREE.CircleGeometry(0.04, 10);
    this.dotGeo.rotateX(-Math.PI / 2);
    this.dotMat = new THREE.MeshBasicMaterial({ color: '#FF7BA9', transparent: true, opacity: 0.9, depthWrite: false });
    this.ownedGeos.push(this.dotGeo);
    this.ownedMats.push(this.dotMat);
    this.dots = [];
    for (let i = 0; i < 12; i += 1) {
      const dot = new THREE.Mesh(this.dotGeo, this.dotMat);
      dot.visible = false;
      scene.add(dot);
      this.dots.push(dot);
    }

    // --- V4/GAME-POLISH-4: pooled cup-impact rings (flat on the green) -------
    this.ringGeo = new THREE.RingGeometry(0.09, 0.13, 26);
    this.ringGeo.rotateX(-Math.PI / 2);
    this.ownedGeos.push(this.ringGeo);
    /** @type {Array<{mesh: THREE.Mesh, mat: THREE.MeshBasicMaterial, tween: object|null}>} */
    this.cupRings = [];
    for (let i = 0; i < 2; i += 1) {
      const mat = new THREE.MeshBasicMaterial({
        color: '#FFD166', transparent: true, opacity: 0, depthWrite: false,
        blending: THREE.AdditiveBlending, side: THREE.DoubleSide,
      });
      const mesh = new THREE.Mesh(this.ringGeo, mat);
      mesh.visible = false;
      this.ownedMats.push(mat);
      scene.add(mesh);
      this.cupRings.push({ mesh, mat, tween: null });
    }

    // --- V6/C4 (GAME-JUICE): pooled bank-impact rings + sink floats ----------
    // The kit tiles clone shared cached GLB materials, so a wall must never
    // flash in place (it would tint every wall) — a white ring ping at the
    // impact point carries the bank instead.
    /** @type {Array<{mesh: THREE.Mesh, mat: THREE.MeshBasicMaterial, tween: object|null}>} */
    this.bankRings = [];
    for (let i = 0; i < 2; i += 1) {
      const mat = new THREE.MeshBasicMaterial({
        color: '#FFFFFF', transparent: true, opacity: 0, depthWrite: false,
        blending: THREE.AdditiveBlending, side: THREE.DoubleSide,
      });
      const mesh = new THREE.Mesh(this.ringGeo, mat);
      mesh.visible = false;
      this.ownedMats.push(mat);
      scene.add(mesh);
      this.bankRings.push({ mesh, mat, tween: null });
    }
    this.floats = createFloatTexts(scene, ctx.camera);
    this.trailT = 0;
    this.powerThird = 0;

    // --- Gooby the caddy -----------------------------------------------------
    this.particles = createParticles(scene);
    this.gooby = createGooby({ particles: this.particles });
    applyEquippedOutfits(this.gooby);
    this.gooby.group.scale.setScalar(0.55);
    scene.add(this.gooby.group);
    this.gooby.setEmotion('happy');

    // --- hole chip (⛳ n/6 · Par p · strokes) --------------------------------
    this.chip = document.createElement('div');
    this.chip.className = 'mg-pill';
    this.chip.style.cssText =
      'position:absolute;top:calc(64px + var(--safe-top));left:50%;transform:translateX(-50%);z-index:35;white-space:nowrap;';
    (document.getElementById('ui') ?? document.body).appendChild(this.chip);

    // --- input: drag back from the ball to aim (§C1.2 #6) --------------------
    this.drag = null;
    this.offDragStart = ctx.input.on('dragstart', (p) => {
      if (this.autoplay || this.state !== 'aim') return;
      this.drag = { sx: p.x, sy: p.y, x: p.x, y: p.y };
      this.powerThird = 0; // V6/C4 juice: power ticks re-arm per drag
    });
    this.offDrag = ctx.input.on('drag', (p) => {
      if (!this.drag) return;
      this.drag.x = p.x;
      this.drag.y = p.y;
      this.updatePreview();
    });
    this.offDragEnd = ctx.input.on('dragend', (p) => {
      if (!this.drag) return;
      this.drag.x = p.x;
      this.drag.y = p.y;
      const aim = this.aimFromDrag();
      this.drag = null;
      this.hidePreview();
      if (aim && aim.power > 0.25 && this.state === 'aim') this.putt(aim.dx, aim.dz, aim.power);
    });

    this.setupHole(0, true);
    ctx.hud.setScore(0);
    ctx.hud.setTime(0);
  },

  /** World x offset of hole i's island. */
  offsetX(i) {
    return i * HOLE_SPACING;
  },

  /** Build one hole's island + tiles (+ flag, windmill blades, bump rails). */
  buildHoleView(hole, i, own) {
    const { scene, assets } = this.ctx;
    const group = new THREE.Group();
    group.name = `golfHole${i}`;
    const ox = this.offsetX(i);
    const view = { group, blades: null };

    // island slab under the cells
    let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
    for (const [x, z] of hole.cells) {
      minX = Math.min(minX, x); maxX = Math.max(maxX, x);
      minZ = Math.min(minZ, z); maxZ = Math.max(maxZ, z);
    }
    const slabGeo = new THREE.BoxGeometry(maxX - minX + 1.6, 0.55, maxZ - minZ + 1.6);
    this.ownedGeos.push(slabGeo);
    const slab = new THREE.Mesh(slabGeo, this.islandMat);
    slab.position.set((minX + maxX) / 2, -0.31, (minZ + maxZ) / 2);
    group.add(slab);

    // path tiles
    for (const cell of cellRoles(hole)) {
      const h = heightAt(hole, cell.x, cell.z);
      let key = 'straight';
      let rotY = straightRot(cell.outDir ?? cell.inDir);
      if (cell.role === 'start') {
        key = 'start';
        rotY = startRot(cell.outDir);
      } else if (cell.role === 'hole') {
        key = 'hole-round';
        rotY = holeRot(cell.inDir);
      } else if (cell.role === 'corner') {
        key = 'corner';
        rotY = cornerRot(cell.inDir, cell.outDir);
      } else if (cell.role === 'ramp') {
        key = 'ramp-low';
        rotY = 0;
      } else if (cell.role === 'windmill') {
        key = 'windmill';
        rotY = 0;
      } else if (cell.role === 'tunnel') {
        key = 'tunnel-wide';
        rotY = 0;
      } else if (cell.role === 'bump') {
        key = 'bump';
        rotY = 0;
      }
      const tile = assets.getModel(`minigolf-kit/${key}`);
      tile.position.set(cell.x, cell.role === 'ramp' ? 0 : h, cell.z);
      tile.rotation.y = rotY;
      group.add(tile);
      if (cell.role === 'windmill') view.blades = tile.getObjectByName('blades');
      if (cell.role === 'bump') {
        // the kit's bump tile has no side rails — add slim matching ones
        const railGeo = new THREE.BoxGeometry(0.07, 0.15, 1);
        this.ownedGeos.push(railGeo);
        for (const side of [-1, 1]) {
          const rail = new THREE.Mesh(railGeo, this.islandMat);
          rail.position.set(cell.x + side * 0.465, 0.075, cell.z);
          group.add(rail);
        }
      }
    }

    if (hole.loop) {
      const loop = own(new THREE.Mesh(
        new THREE.TorusGeometry(0.5, 0.075, 10, 36),
        new THREE.MeshStandardMaterial({
          color: '#FF7BA9', emissive: '#6F2148', roughness: 0.35, metalness: 0.25,
        })
      ));
      loop.name = 'nougat-loop';
      loop.position.set(hole.loop.x, 0.52, hole.loop.z);
      group.add(loop);
      view.loop = loop;
    }
    if (hole.nougat) {
      const machine = buildNougatschleuse(this.resourceTrack, assets);
      machine.name = 'golf-nougatschleuse';
      machine.scale.setScalar(1.35);
      machine.position.set(nougatXAt(hole, 0), 0.72, hole.nougat.z);
      machine.rotation.y = Math.PI;
      group.add(machine);
      view.nougat = machine;
    }

    // flag in the cup
    const flag = assets.getModel('minigolf-kit/flag-red');
    flag.position.set(hole.hole.x, heightAt(hole, hole.hole.x, hole.hole.z), hole.hole.z);
    group.add(flag);
    view.flag = flag;

    group.position.x = ox;
    scene.add(group);
    this.holeViews.push(view);
  },

  /** Current hole def. */
  hole() {
    return this.course[this.holeIdx];
  },

  /** Move ball/caddy/camera onto hole i and open the aim state. */
  setupHole(i, instant) {
    this.holeIdx = i;
    const hole = this.hole();
    this.strokes = 0;
    this.wpIdx = 0;
    this.state = 'aim';
    this.stateT = 0;
    this.botT = 1.1;
    this.ball = { x: hole.start.x, z: hole.start.z, vx: 0, vz: 0, done: false };
    this.ballMesh.visible = true;
    this.syncBall();
    this.holeViews[i].flag.visible = true;

    // caddy Gooby beside the tee
    const ox = this.offsetX(i);
    this.gooby.group.position.set(ox + hole.start.x + 0.72, 0, hole.start.z + 0.6);
    this.gooby.group.rotation.y = Math.PI; // face the camera
    this.gooby.play('idle');
    this.gooby.setEmotion('happy');

    // camera frames the island (tween between holes)
    const camera = this.ctx.camera;
    let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
    for (const [x, z] of hole.cells) {
      minX = Math.min(minX, x); maxX = Math.max(maxX, x);
      minZ = Math.min(minZ, z); maxZ = Math.max(maxZ, z);
    }
    const cx = ox + (minX + maxX) / 2;
    const cz = (minZ + maxZ) / 2;
    const len = Math.max(maxZ - minZ, maxX - minX);
    // lower pitch: keep the pastel-sky horizon in frame (§C1.3 floating look)
    const target = {
      px: cx,
      py: 3.7 + len * 0.5,
      pz: minZ - 3.1 - len * 0.3,
      lx: cx,
      lz: cz + 0.4,
    };
    if (instant) {
      camera.position.set(target.px, target.py, target.pz);
      camera.lookAt(target.lx, 0, target.lz);
      this.camLook = { x: target.lx, z: target.lz };
    } else {
      const from = {
        px: camera.position.x, py: camera.position.y, pz: camera.position.z,
        lx: this.camLook.x, lz: this.camLook.z,
      };
      tween({
        from: 0,
        to: 1,
        duration: 0.8,
        ease: easings.easeInOutQuad,
        onUpdate: (v) => {
          if (!this.ctx) return;
          camera.position.set(
            from.px + (target.px - from.px) * v,
            from.py + (target.py - from.py) * v,
            from.pz + (target.pz - from.pz) * v
          );
          this.camLook = { x: from.lx + (target.lx - from.lx) * v, z: from.lz + (target.lz - from.lz) * v };
          camera.lookAt(this.camLook.x, 0, this.camLook.z);
        },
      });
    }
    this.updateChip();
    if (this.autoplay) console.log(`[miniGolf] hole ${i + 1}/${GOLF.HOLE_COUNT} (${hole.id}, par ${hole.par})`);
  },

  updateChip() {
    if (!this.chip) return;
    const hole = this.hole();
    if (!hole) return;
    // V6/D3: authored flag glyph + glyph-stripped text ('mg.golf.hole' still
    // carries a raw flag emoji until D4's v2-games-e.js sweep lands).
    const text = stripRawGlyphs(`${t('mg.golf.hole', { n: this.holeIdx + 1, max: this.course.length, par: hole.par })} · ${t('mg.golf.strokes', { n: this.strokes })}`);
    this.chip.innerHTML = `<span style="display:inline-flex;align-items:center;gap:5px">${icon('golfFlag', 18)}<span>${text}</span></span>`;
  },

  /** Ball mesh ← physics state (world = island offset + local). */
  syncBall() {
    const hole = this.hole();
    if (!hole) return;
    this.ballMesh.position.set(
      this.offsetX(this.holeIdx) + this.ball.x,
      BALL_Y + heightAt(hole, this.ball.x, this.ball.z),
      this.ball.z
    );
  },

  /** Drag vector → world aim dir + power (drag BACK from the ball). */
  aimFromDrag() {
    if (!this.drag) return null;
    const dx = this.drag.sx - this.drag.x; // screen right drag → aim left
    const dy = this.drag.y - this.drag.sy; // screen down drag → aim up-course
    const len = Math.hypot(dx, dy);
    if (len < 4) return null;
    return { dx: dx / len, dz: dy / len, power: powerFromDrag(len, innerWidth, innerHeight) };
  },

  /** Dotted aim preview (§C1.2 #6) from the ball opposite the drag. */
  updatePreview() {
    const aim = this.aimFromDrag();
    if (!aim || this.state !== 'aim') {
      this.hidePreview();
      return;
    }
    const hole = this.hole();
    const ox = this.offsetX(this.holeIdx);
    // V6/C4 juice: power ticks — a low ui.count click as the drag crosses each
    // third of MAX_POWER (§C.4 #3); re-crossing after easing off ticks again.
    const third = Math.min(
      GOLF_JUICE6.POWER_TICK_THIRDS,
      Math.floor((aim.power / GOLF.MAX_POWER) * GOLF_JUICE6.POWER_TICK_THIRDS)
    );
    if (third > this.powerThird) this.ctx.audio.play('ui.count');
    this.powerThird = third;
    const len = 0.4 + (aim.power / GOLF.MAX_POWER) * 2.2;
    for (let i = 0; i < this.dots.length; i += 1) {
      const f = ((i + 1) / this.dots.length) * len;
      const x = this.ball.x + aim.dx * f;
      const z = this.ball.z + aim.dz * f;
      this.dots[i].visible = true;
      this.dots[i].position.set(ox + x, 0.09 + heightAt(hole, x, z), z);
    }
  },

  hidePreview() {
    for (const dot of this.dots) dot.visible = false;
  },

  /**
   * V4/GAME-POLISH-4: pooled ring pulse at the cup on a sink (gold) or ace
   * (bigger, pink). Skipped under OS reduced-motion — confetti/banner carry it.
   * @param {THREE.Vector3} pos world position (cup)
   * @param {boolean} ace hole-in-one
   */
  flashCupRing(pos, ace) {
    if (prefersReducedMotion()) return;
    const ring = this.cupRings.find((r) => !r.mesh.visible) ?? this.cupRings[0];
    ring.tween?.cancel();
    ring.mat.color.set(ace ? '#FF7BA9' : '#FFD166');
    ring.mesh.position.set(pos.x, 0.02 + heightAt(this.hole(), this.hole().hole.x, this.hole().hole.z), pos.z);
    ring.mesh.visible = true;
    const to = ace ? GOLF_JUICE.RING_SCALE_ACE : GOLF_JUICE.RING_SCALE_SINK;
    ring.tween = tween({
      from: 0, to: 1, duration: GOLF_JUICE.RING_LIFE_SEC, ease: easings.easeOutCubic,
      onUpdate: (v) => {
        ring.mesh.scale.setScalar(1 + (to - 1) * v);
        ring.mat.opacity = 0.9 * (1 - v);
      },
      onComplete: () => {
        ring.mesh.visible = false;
        ring.tween = null;
      },
    });
  },

  /**
   * V6/C4 juice: bank flash — pooled white ring ping where the ball banked
   * (§C.4 #4). The kit wall materials are shared GLB caches, so the flash
   * lives at the impact point instead of tinting every wall. RM-gated
   * (golf.bank/golf.bump audio still carries the hit).
   * @param {THREE.Vector3} pos world impact position (ball)
   */
  flashBankRing(pos) {
    if (prefersReducedMotion()) return;
    const ring = this.bankRings.find((r) => !r.mesh.visible) ?? this.bankRings[0];
    ring.tween?.cancel();
    ring.mesh.position.set(pos.x, pos.y + 0.02, pos.z);
    ring.mesh.visible = true;
    ring.tween = tween({
      from: 0, to: 1, duration: GOLF_JUICE6.BANK_RING_SEC, ease: easings.easeOutQuad,
      onUpdate: (v) => {
        ring.mesh.scale.setScalar(1 + (GOLF_JUICE6.BANK_RING_SCALE - 1) * v);
        ring.mat.opacity = 0.8 * (1 - v);
      },
      onComplete: () => {
        ring.mesh.visible = false;
        ring.tween = null;
      },
    });
  },

  /** Fire a putt (§C1.2 #6): stroke count + roll state. */
  putt(dx, dz, power) {
    this.strokes += 1;
    this.totalStrokes += 1;
    this.ball.vx = dx * power;
    this.ball.vz = dz * power;
    this.state = 'rolling';
    this.stateT = 0;
    this.ctx.audio.play('golf.putt');
    // V4/GAME-POLISH-4: contact squash sells the strike (recovers to 1)
    if (!prefersReducedMotion()) {
      tween({
        from: GOLF_JUICE.PUTT_SQUASH, to: 1, duration: GOLF_JUICE.PUTT_SQUASH_SEC,
        ease: easings.easeOutQuad,
        onUpdate: (s) => {
          if (this.ballMesh) this.ballMesh.scale.set(2 - s, s, 2 - s);
        },
        onComplete: () => this.ballMesh?.scale.setScalar(1),
      });
    }
    this.updateChip();
  },

  /** Ball holed (§C1.2 #6 scoring) or 10-stroke cap: score + caddy reaction. */
  finishHole(holed) {
    const hole = this.hole();
    const points = holed ? holeScore(this.strokes, hole.par, this.tune) : this.tune.SCORE_OTHER;
    const ace = holed && this.strokes === 1;
    this.holeResults.push({ strokes: this.strokes, par: hole.par, holed });
    if (ace) this.holeInOnes += 1;
    this.score += points;
    this.ctx.onScore(points);
    const cupPos = new THREE.Vector3(
      this.offsetX(this.holeIdx) + hole.hole.x, 0.4, hole.hole.z
    );
    // V6/C4 juice: sink float — the points finally land AT the cup (§C.4 #1;
    // the four banner variants live at the top of the screen). The 10-stroke
    // consolation floats at the ball instead (it never reached the cup).
    this.floats.spawn(
      `+${points}`,
      holed ? cupPos.clone().add(new THREE.Vector3(0, 0.2, 0)) : this.ballMesh.position.clone().setY(0.45),
      holed ? (ace ? '#FF7BA9' : '#D69A28') : '#8A7F78'
    );
    if (holed) {
      this.ballMesh.visible = false;
      this.ctx.audio.play(ace ? 'golf.ace' : 'golf.sink');
      this.particles.emit?.('confetti', cupPos, { count: ace ? 24 : 10 });
      // V4/GAME-POLISH-4: cup ring pulse + flag pop (ace showers sparkles too)
      this.flashCupRing(cupPos, ace);
      const flag = this.holeViews[this.holeIdx]?.flag;
      if (flag && !prefersReducedMotion()) {
        tween({
          from: GOLF_JUICE.FLAG_POP_SCALE, to: 1, duration: GOLF_JUICE.FLAG_POP_SEC,
          ease: easings.easeOutBack,
          onUpdate: (s) => flag.scale.set(1, s, 1),
        });
      }
      if (ace) this.particles.emit?.('sparkles', cupPos, { count: GOLF_JUICE.ACE_SPARKLES });
      if (ace) {
        this.ctx.hud.banner(t('mg.golf.ace'));
        this.gooby.setEmotion('ecstatic');
        this.gooby.play('happyBounce');
      } else if (this.strokes <= hole.par) {
        this.ctx.hud.banner(t('mg.golf.great', { n: points }));
        this.gooby.setEmotion('ecstatic');
        this.gooby.play('happyBounce');
      } else if (this.strokes === hole.par + 1) {
        this.ctx.hud.banner(t('mg.golf.okay', { n: points }));
        this.gooby.setEmotion('happy');
        this.gooby.play('wave');
      } else {
        this.ctx.hud.banner(t('mg.golf.done', { n: points }));
        this.gooby.setEmotion('sad');
        this.gooby.play('sadSlump');
      }
    } else {
      // §C1.2 #6: 10-stroke auto-advance (consolation +6, caddy facepalm)
      this.ctx.hud.banner(t('mg.golf.capped', { n: points }));
      this.gooby.setEmotion('sad');
      this.gooby.play('sadSlump');
    }
    if (this.autoplay) {
      console.log(`[miniGolf] hole ${this.holeIdx + 1} done — strokes ${this.strokes}, +${points}${ace ? ' (ACE)' : ''}, score ${this.score}`);
    }
    if (this.tune.ENDLESS && recordGolfHole(this.endlessState, this.strokes, hole.par)) {
      this.state = 'ending';
      this.stateT = 0;
      this.ctx.audio.play('ui.win');
      return;
    }
    this.state = 'celebrate';
    this.stateT = 0;
  },

  /** Greedy 2-putt bot (§C1.2 #6): waypoint/cup aim + power table + jitter. */
  autoplayTick(dt, elapsed) {
    if (this.state !== 'aim') return;
    this.botT -= dt;
    if (this.botT > 0) return;
    const hole = this.hole();
    const { rng } = this.ctx;
    // advance past reached waypoints
    while (
      this.wpIdx < hole.waypoints.length &&
      Math.hypot(hole.waypoints[this.wpIdx].x - this.ball.x, hole.waypoints[this.wpIdx].z - this.ball.z) < 0.45
    ) {
      this.wpIdx += 1;
    }
    const target = hole.waypoints[this.wpIdx] ?? hole.hole;
    const isCup = target === hole.hole;
    const dx = target.x - this.ball.x;
    const dz = target.z - this.ball.z;
    const dist = Math.hypot(dx, dz);
    let power = Math.min(
      GOLF.MAX_POWER,
      powerForDistance(dist * (isCup ? 1.02 : 0.95)) * hole.botPowerMul
    );
    // windmill: time the putt so the gate is open on arrival
    if (hole.windmill && this.ball.z < hole.windmill.gateZ - 0.1) {
      const tArr = rollTimeToDistance(power, hole.windmill.gateZ - this.ball.z);
      if (!Number.isFinite(tArr)) {
        power = Math.min(GOLF.MAX_POWER, power * 1.2);
      } else {
        const thetaArr = (elapsed + tArr) * OMEGA + hole.windmill.phase;
        if (windmillBlocked(thetaArr) || windmillBlocked(thetaArr + 0.12 * OMEGA) || windmillBlocked(thetaArr - 0.12 * OMEGA)) {
          this.botT = 0.12; // wait for the next open window
          return;
        }
      }
    }
    // human-ish slack: a touch of angle + power scatter
    const jitter = (rng() - 0.5) * 0.09;
    const cos = Math.cos(jitter);
    const sin = Math.sin(jitter);
    const ax = (dx / dist) * cos + (dz / dist) * sin;
    const az = -(dx / dist) * sin + (dz / dist) * cos;
    power *= 0.94 + rng() * 0.12;
    this.putt(ax, az, Math.min(GOLF.MAX_POWER, power));
    this.botT = 0.8 + rng() * 0.5;
  },

  update(dt, elapsed) {
    const ctx = this.ctx;
    this.theta = elapsed * OMEGA;
    this.gooby.update(dt);
    this.particles.update?.(dt);
    this.floats.update(dt); // V6/C4 juice
    this.bankSoundT = Math.max(0, this.bankSoundT - dt);
    ctx.hud.setTime(elapsed);

    // windmill blades spin in exact sync with the physics gate
    for (let i = 0; i < this.holeViews.length; i += 1) {
      const blades = this.holeViews[i].blades;
      if (blades) blades.rotation.z = -(this.theta + this.course[i].windmill.phase);
      const nougat = this.holeViews[i].nougat;
      if (nougat) {
        nougat.position.x = nougatXAt(this.course[i], this.theta);
        nougat.userData.update?.(dt);
      }
    }
    for (let i = 0; i < this.clouds.length; i += 1) {
      this.clouds[i].position.x += dt * (0.12 + (i % 3) * 0.05);
      if (this.clouds[i].position.x > this.offsetX(GOLF.HOLE_COUNT) + 6) this.clouds[i].position.x = -8;
    }

    if (this.state === 'ending') {
      this.stateT += dt;
      if (this.stateT >= 1.1 && this.state !== 'done') {
        this.state = 'done';
        ctx.onEnd({ score: this.score, meta: { strokes: this.totalStrokes, holeInOnes: this.holeInOnes } });
      }
      return;
    }
    if (this.state === 'celebrate') {
      this.stateT += dt;
      if (this.stateT >= 1.25) {
        if (
          !this.tune.ENDLESS &&
          this.holeIdx === GOLF.HOLE_COUNT - 1 &&
          this.course.length === GOLF.HOLE_COUNT &&
          qualifiesNougatLoop(this.holeResults)
        ) {
          const bonus = createNougatLoopHole(this.ctx.rng, this.tune);
          this.course.push(bonus);
          this.buildHoleView(bonus, GOLF.HOLE_COUNT, this.own);
          this.bonusUnlocked = true;
          this.ctx.hud.banner(t('v3.depth.golf.unlocked'));
          this.setupHole(GOLF.HOLE_COUNT, false);
        } else if (this.holeIdx + 1 >= this.course.length && this.tune.ENDLESS) {
          this.setupHole(0, false);
        } else if (this.holeIdx + 1 >= this.course.length) {
          this.state = 'ending';
          this.stateT = 0;
          ctx.audio.play('ui.win');
          this.gooby.setEmotion('ecstatic');
          if (this.autoplay) {
            console.log(
              `[miniGolf] round complete — strokes ${this.totalStrokes}, ` +
              `holeInOnes ${this.holeInOnes}, bonus ${this.bonusUnlocked}, score ${this.score}`
            );
          }
        } else {
          this.setupHole(this.holeIdx + 1, false);
        }
      }
      return;
    }

    if (this.autoplay) this.autoplayTick(dt, elapsed);

    if (this.state === 'rolling') {
      const hole = this.hole();
      const events = stepBall(hole, this.ball, dt, this.theta, this.tune);
      for (const ev of events) {
        if (ev === 'holed') {
          this.finishHole(true);
          break;
        }
        if ((ev === 'bank' || ev === 'windmill' || ev === 'bump' || ev === 'nougat') && this.bankSoundT <= 0) {
          this.bankSoundT = 0.15;
          ctx.audio.play(ev === 'bump' ? 'golf.bump' : 'golf.bank');
          // V4/GAME-POLISH-4: tiny sparkle ping so banks read visually too
          this.particles.emit?.('sparkles', this.ballMesh.position, { count: GOLF_JUICE.BANK_SPARKLES });
          this.flashBankRing(this.ballMesh.position); // V6/C4 juice (§C.4 #4)
        }
      }
      this.syncBall();
      // V6/C4 juice: roll sparkle trail on power shots (§C.4 #2) — count
      // halved under OS reduced motion rather than dropped (it's tiny).
      const rollSpeedNow = Math.hypot(this.ball.vx, this.ball.vz);
      if (this.state === 'rolling' && rollSpeedNow > GOLF_JUICE6.TRAIL_MIN_SPEED) {
        this.trailT -= dt;
        if (this.trailT <= 0) {
          this.trailT = GOLF_JUICE6.TRAIL_EVERY_SEC;
          const count = prefersReducedMotion()
            ? Math.ceil(GOLF_JUICE6.TRAIL_SPARKLES / 2)
            : GOLF_JUICE6.TRAIL_SPARKLES;
          this.particles.emit?.('sparkles', this.ballMesh.position, { count });
        }
      }
      if (this.state === 'rolling' && isStopped(hole, this.ball)) {
        this.ball.vx = 0;
        this.ball.vz = 0;
        if (this.strokes >= GOLF.MAX_STROKES) {
          this.finishHole(false); // §C1.2 #6: 10-stroke auto-advance
        } else {
          this.state = 'aim';
          this.stateT = 0;
        }
      }
    }
  },

  /** F6 §E8 hook: drop a mid-drag aim when the pause overlay opens. */
  onPause() {
    this.drag = null;
    this.hidePreview();
  },

  onResume() {},

  dispose() {
    this.offDragStart?.();
    this.offDrag?.();
    this.offDragEnd?.();
    this.particles?.dispose?.();
    this.gooby?.dispose();
    this.chip?.remove();
    this.chip = null;
    for (const geo of this.ownedGeos ?? []) geo.dispose();
    for (const mat of this.ownedMats ?? []) mat.dispose();
    for (const tex of this.ownedTexs ?? []) tex.dispose();
    // GLB tile clones share cached geometries/materials — the framework scene
    // sweep handles GPU frees; drop references only.
    this.ownedGeos = [];
    this.ownedMats = [];
    this.ownedTexs = [];
    this.holeViews = [];
    this.dots = [];
    for (const ring of this.cupRings ?? []) ring.tween?.cancel(); // V4/GAME-POLISH-4
    this.cupRings = [];
    for (const ring of this.bankRings ?? []) ring.tween?.cancel(); // V6/C4 juice
    this.bankRings = [];
    this.floats?.dispose(); // V6/C4 juice
    this.floats = null;
    this.ringGeo = null;
    this.clouds = [];
    this.course = null;
    this.holeResults = [];
    this.resourceTrack = null;
    this.tune = null;
    this.endlessState = null;
    this.own = null;
    this.ctx = null;
    this.gooby = null;
    this.particles = null;
    this.ballMesh = null;
  },
};
export const controls = Object.freeze({ invertible: false }); // V4/G57 (§G2.1 rule 4, §G3.3): positional/tap/semantic input — inverting is nonsense here
// V4/GAME-POLISH-4 orientation note: deliberately NO landscape export — the
// generated holes run away from the camera (long z-axis), so the portrait
// default frames the full course; landscape would crop the fairway.
