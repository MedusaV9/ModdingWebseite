// Schneckenpost — „Snail Mail" (PLAN6 Wave C, agent C2; concept PLAN5 §6):
// cozy PATH-DRAWING deliveries. A garden-path diorama: draw a glitter trail
// with your finger from the red post box to the glowing target house or
// burrow, and the little courier snail follows it at constant speed —
// consuming the dotted ribbon, picking flowers for bonus points and (oops)
// splashing into puddles, which sends it into its shell for 2 s and forfeits
// the dry bonus. Pure rules live in snailMail.logic.js (§B rule; spline
// toolkit reused from goobyWelt.logic.js). Gooby cheers from the bottom-left
// corner; the snail's shell shimmers one hue brighter per delivered letter.
//
// Dev-only ?autoplay=1: a bot draws the reference auto-route (progressively
// revealed dots) and the snail delivers it — headless demo/verification.
//
// Strings ride the same-wave tx() fallback (framework.js G52 pattern) until
// C3 spreads v6-games.js into strings.js — key list + EN/DE handed off in
// /tmp/gooby-v6-handoffs/C2-strings-for-C3.txt.

import * as THREE from 'three';
import { t, getLang } from '../../data/strings.js';
import { tween, easings } from '../../gfx/tween.js';
import { createParticles } from '../../gfx/particles.js';
import { createGooby } from '../../character/gooby.js';
import { applyEquippedOutfits } from '../../character/outfitAttach.js';
import { clampFloatTextToView } from '../framework.js';
import { prefersReducedMotion } from '../../ui/ui.js';
import {
  SNAIL,
  applyDifficulty,
  generateLevel,
  autoRoute,
  smoothPath,
  followInto,
  advanceArc,
  puddleHitAt,
  startsAtPost,
  endHouse,
  doorOf,
  applyScore,
  endlessShouldEnd,
} from './snailMail.logic.js';

// --- C2 same-wave i18n fallback (EN/DE handed to C3 for v6-games.js) ---
const SNAIL_EN = {
  'snail.drawHint': 'Draw a path from the mailbox!',
  'snail.startAtPost': 'Start at the mailbox!',
  'snail.wrongHouse': 'To the glowing house!',
  'snail.go': "Off you go, little snail!",
  'snail.delivered': 'Delivered!',
  'snail.dry': 'Dry delivery! +{n}',
  'snail.flower': 'Flower!',
  'snail.splash': 'Splash! Into the shell...',
  'snail.splashes': 'Splash {n}/{max}',
};
const SNAIL_DE = {
  'snail.drawHint': 'Zeichne einen Weg vom Briefkasten!',
  'snail.startAtPost': 'Starte am Briefkasten!',
  'snail.wrongHouse': 'Zum leuchtenden Haus!',
  'snail.go': 'Los geht’s, kleine Schnecke!',
  'snail.delivered': 'Zugestellt!',
  'snail.dry': 'Trocken zugestellt! +{n}',
  'snail.flower': 'Blume!',
  'snail.splash': 'Platsch! Ab ins Haus…',
  'snail.splashes': 'Platscher {n}/{max}',
};

/** @param {string} key @param {Record<string, string|number>} [vars] */
function tx(key, vars) {
  const global = t(key, vars);
  if (global !== key) return global;
  let text = (getLang() === 'de' ? SNAIL_DE : SNAIL_EN)[key] ?? key;
  if (vars) {
    for (const [name, value] of Object.entries(vars)) {
      text = text.replaceAll(`{${name}}`, String(value));
    }
  }
  return text;
}

/** Glitter-ribbon dot budget (one InstancedMesh — a single draw call). */
const MAX_DOTS = 96;
/** Dot spacing along the smoothed path (wu, logic space). */
const DOT_SPACING = 0.18;
/** Pastel house palette (body colors cycled over the three slots). */
const HOUSE_COLORS = [0xffb3c7, 0xbfe3ff, 0xffe2a9];

/** Tiny floating score text (canvas sprites, self-disposing). */
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
      const mat = new THREE.SpriteMaterial({ map: tex, transparent: true, depthWrite: false });
      const sprite = new THREE.Sprite(mat);
      sprite.position.copy(clampFloatTextToView(pos.clone(), camera, { halfW: 0.75, halfH: 0.25 }));
      sprite.scale.set(1.5, 0.5, 1);
      scene.add(sprite);
      active.add({ sprite, mat, tex, age: 0, life: 0.9 });
    },
    update(dt) {
      for (const f of active) {
        f.age += dt;
        f.sprite.position.y += dt * 1.1;
        f.mat.opacity = 1 - (f.age / f.life) ** 2;
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

/** Wrap a GLB clone so its bbox center sits at the wrapper origin. */
function fitModel(model, targetSize) {
  const box = new THREE.Box3().setFromObject(model);
  const size = box.getSize(new THREE.Vector3());
  const s = targetSize / (Math.max(size.x, size.y, size.z) || 1);
  model.scale.setScalar(s);
  box.setFromObject(model);
  const center = box.getCenter(new THREE.Vector3());
  model.position.sub(center);
  const holder = new THREE.Group();
  holder.add(model);
  return holder;
}

/** @type {object} §E8 plugin */
export default {
  id: 'snailMail',
  assetKeys: [
    'nature-kit/fence_simple',
    'nature-kit/flower_redA',
    'nature-kit/flower_yellowA',
    'nature-kit/flower_purpleA',
    'nature-kit/crop_carrot',
  ],
  /** V3/G32 §B2.3: warm the recorded cues used every few seconds. */
  sfx: ['jingle.short', 'delivery.doorbell', 'hop.bell', 'combo.up', 'ui.win'],

  /** @param {object} ctx §E8 game context */
  init(ctx) {
    this.ctx = ctx;
    this.tune = applyDifficulty(SNAIL, ctx.params?.difficulty ?? 'normal');
    this.autoplay =
      import.meta.env?.DEV && new URLSearchParams(location.search).get('autoplay') === '1';
    if (import.meta.env?.DEV) window.__snail = this; // CDP probe (dev-only, V4/G67 pattern)

    this.phase = 'draw'; // 'draw' | 'follow' | 'rate' | 'ending' | 'done'
    this.score = 0;
    this.round = 0;
    this.deliveries = 0;
    this.splashes = 0;
    this.elapsed = 0;
    this.emotionT = 0;
    this.shakeT = 0;
    this.rateT = 0;
    this.retreatT = 0;
    this.immunePuddle = -1;
    this.wet = false;
    this.drawing = false;
    /** @type {{x:number,y:number}[]} raw pointer stroke (logic space) */
    this.rawPts = [];
    /** @type {ReturnType<typeof smoothPath>|null} the path being followed */
    this.path = null;
    this.arcS = 0;
    this.pose = { x: 0, y: 0, angle: Math.PI / 2 };
    this.snailAngle = Math.PI / 2;
    /** @type {number[]} arc positions of the laid glitter dots */
    this.dotArcs = [];
    this.dotCount = 0;
    this.nextDot = 0;
    /** @type {Array<{arc:number,idx:number,done:boolean}>} flower triggers */
    this.flowerTriggers = [];
    this.autoT = 0;
    /** @type {ReturnType<typeof autoRoute>|null} */
    this.autoRouteCache = null;
    this.reducedMotion = prefersReducedMotion();

    const camera = ctx.camera;
    camera.position.set(0, 0, 10);
    camera.lookAt(0, 0, 0);
    this.halfH = Math.tan(THREE.MathUtils.degToRad(camera.fov / 2)) * 10;
    this.halfW = this.halfH * (innerWidth / innerHeight);

    const scene = ctx.scene;
    scene.background = new THREE.Color('#CFEBBB'); // fresh garden morning

    /** @type {THREE.BufferGeometry[]} */
    this.ownedGeos = [];
    /** @type {THREE.Material[]} */
    this.ownedMats = [];
    const own = (mesh) => {
      this.ownedGeos.push(mesh.geometry);
      this.ownedMats.push(mesh.material);
      return mesh;
    };
    this.own = own;

    scene.add(new THREE.HemisphereLight(0xfff8ec, 0x9fcf8e, 1.15));
    const dir = new THREE.DirectionalLight(0xfff2dd, 0.85);
    dir.position.set(3, 5, 6);
    scene.add(dir);

    // --- sky band + sun + cloud (screen space, behind the garden) ---
    const sky = own(new THREE.Mesh(
      new THREE.PlaneGeometry(this.halfW * 2 + 2, 2.6),
      new THREE.MeshBasicMaterial({ color: 0xc3e7f7 })
    ));
    sky.position.set(0, this.halfH - 1.15, -3);
    scene.add(sky);
    const sun = own(new THREE.Mesh(
      new THREE.CircleGeometry(0.6, 28),
      new THREE.MeshBasicMaterial({ color: 0xffd166 })
    ));
    sun.position.set(this.halfW - 1.0, this.halfH - 0.85, -2.8);
    scene.add(sun);
    this.cloud = own(new THREE.Mesh(
      new THREE.CircleGeometry(0.38, 18),
      new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.85 })
    ));
    this.cloud.position.set(-this.halfW + 1.2, this.halfH - 1.2, -2.7);
    this.cloud.scale.set(1.7, 1, 1);
    scene.add(this.cloud);

    // --- the garden field group (logic space, uniformly scaled to fit) ---
    const ySpan = this.tune.FIELD_Y_MAX - this.tune.FIELD_Y_MIN;
    this.fieldScale = Math.min(
      (this.halfW * 2 - 0.55) / (this.tune.FIELD_HALF_W * 2),
      (this.halfH * 2 - 2.7) / ySpan
    );
    this.field = new THREE.Group();
    this.field.scale.setScalar(this.fieldScale);
    this.field.position.set(0, -0.3, 0);
    scene.add(this.field);

    // lawn
    const lawn = own(new THREE.Mesh(
      new THREE.PlaneGeometry(this.tune.FIELD_HALF_W * 2 + 0.7, ySpan + 0.9),
      new THREE.MeshBasicMaterial({ color: 0xa9d886 })
    ));
    lawn.position.set(0, (this.tune.FIELD_Y_MAX + this.tune.FIELD_Y_MIN) / 2, -0.6);
    this.field.add(lawn);

    // fence line behind the houses + carrot-patch corners (committed GLBs)
    this.buildDressing();

    // --- post box (red, with the springy delivery flag) ---
    this.buildPostBox();

    // --- houses / burrow / puddles / flowers (pooled, laid out per round) ---
    this.buildHouses();
    this.buildPuddles();
    this.buildFlowers();

    // target highlight: glow disc + bouncing arrow
    this.glowMat = new THREE.MeshBasicMaterial({
      color: 0xfff0a8, transparent: true, opacity: 0.55, depthWrite: false,
    });
    this.ownedMats.push(this.glowMat);
    this.glow = new THREE.Mesh(new THREE.CircleGeometry(0.55, 26), this.glowMat);
    this.ownedGeos.push(this.glow.geometry);
    this.glow.position.z = -0.5;
    this.field.add(this.glow);
    this.arrow = own(new THREE.Mesh(
      new THREE.CircleGeometry(0.17, 3),
      new THREE.MeshBasicMaterial({ color: 0xff7ba9 })
    ));
    this.arrow.rotation.z = Math.PI; // point down
    this.field.add(this.arrow);

    // --- glitter ribbon (single instanced draw call) ---
    this.dotGeo = new THREE.CircleGeometry(0.055, 10);
    this.dotMat = new THREE.MeshBasicMaterial({
      color: 0xfffbe8, transparent: true, opacity: 0.95, depthWrite: false,
    });
    this.ownedGeos.push(this.dotGeo);
    this.ownedMats.push(this.dotMat);
    this.dots = new THREE.InstancedMesh(this.dotGeo, this.dotMat, MAX_DOTS);
    this.dots.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    this.field.add(this.dots);
    this._m4 = new THREE.Matrix4();
    this._v3 = new THREE.Vector3();
    this._q = new THREE.Quaternion();
    this._s3 = new THREE.Vector3(1, 1, 1);
    this.clearDots();

    // --- the courier snail (procedural, top-view — rotates to any heading) ---
    this.buildSnail();

    // --- particles / floats / Gooby cameo (bottom LEFT; pause owns the right) ---
    this.particles = createParticles(scene);
    this.floats = createFloatTexts(scene, ctx.camera);
    this.gooby = createGooby({ particles: this.particles });
    applyEquippedOutfits(this.gooby);
    this.gooby.group.scale.setScalar(0.55);
    this.gooby.group.position.set(-this.halfW + 0.72, -this.halfH + 0.78, 1.4);
    this.gooby.setEmotion('happy');
    scene.add(this.gooby.group);

    // --- input: draw the delivery path with the finger ---
    const el = ctx.renderer.domElement;
    this.onPointerDown = (e) => {
      if (this.autoplay || this.phase !== 'draw') return;
      const p = this.toLogic(e);
      if (!startsAtPost(p, this.tune)) {
        this.floats.spawn(tx('snail.startAtPost'), this.fieldToWorld(this.tune.POST_X, this.tune.POST_Y + 0.7), '#8A7FA8');
        this.wigglePost();
        return;
      }
      this.drawing = true;
      this.rawPts.length = 0;
      this.rawPts.push({ x: this.tune.POST_X, y: this.tune.POST_Y });
      this.clearDots();
      this.pushStrokePoint(p);
      this.ctx.audio.play('ui.tap');
    };
    this.onPointerMove = (e) => {
      if (!this.drawing || this.phase !== 'draw') return;
      this.pushStrokePoint(this.toLogic(e));
    };
    this.onPointerUp = () => {
      if (!this.drawing || this.phase !== 'draw') return;
      this.drawing = false;
      this.releaseStroke();
    };
    el.addEventListener('pointerdown', this.onPointerDown);
    el.addEventListener('pointermove', this.onPointerMove);
    el.addEventListener('pointerup', this.onPointerUp);
    el.addEventListener('pointercancel', this.onPointerUp);
    el.addEventListener('pointerleave', this.onPointerUp);

    this.startRound(true);
    ctx.hud.setScore(0);
    ctx.hud.setTime(this.tune.ENDLESS ? 0 : this.tune.DURATION_SEC);
    ctx.hud.banner(tx('snail.drawHint'));
  },

  // ------------------------------------------------------------ coordinates

  /** Pointer event → logic-space point. */
  toLogic(e) {
    const wx = ((e.clientX / innerWidth) * 2 - 1) * this.halfW;
    const wy = (-(e.clientY / innerHeight) * 2 + 1) * this.halfH;
    return {
      x: (wx - this.field.position.x) / this.fieldScale,
      y: (wy - this.field.position.y) / this.fieldScale,
    };
  },

  /** Logic-space point → world Vector3 (fresh — event use only). */
  fieldToWorld(x, y, z = 0.8) {
    return new THREE.Vector3(
      x * this.fieldScale + this.field.position.x,
      y * this.fieldScale + this.field.position.y,
      z
    );
  },

  // ------------------------------------------------------------ build rigs

  /** nature-kit dressing: fence line + carrot patches (matte clay clones). */
  buildDressing() {
    const tint = (holder) => {
      holder.traverse((obj) => {
        if (!obj.isMesh || !obj.material) return;
        const clone = obj.material.clone();
        if ('metalness' in clone) clone.metalness = 0;
        if ('roughness' in clone) clone.roughness = 0.9;
        obj.material = clone;
        this.ownedMats.push(clone);
      });
      return holder;
    };
    for (let i = 0; i < 3; i += 1) {
      const fence = tint(fitModel(this.ctx.assets.getModel('nature-kit/fence_simple'), 1.35));
      fence.position.set(-1.5 + i * 1.5, this.tune.FIELD_Y_MAX + 0.28, -0.5);
      this.field.add(fence);
    }
    for (const [cx, cy] of [[-this.tune.FIELD_HALF_W + 0.28, -1.15], [this.tune.FIELD_HALF_W - 0.28, -0.35]]) {
      const carrot = tint(fitModel(this.ctx.assets.getModel('nature-kit/crop_carrot'), 0.5));
      carrot.position.set(cx, cy, -0.35);
      this.field.add(carrot);
    }
  },

  /** Red post box on a wooden pole, with the springy flag. */
  buildPostBox() {
    const own = this.own;
    this.post = new THREE.Group();
    this.post.position.set(this.tune.POST_X, this.tune.POST_Y, 0.1);
    this.field.add(this.post);
    const pole = own(new THREE.Mesh(
      new THREE.CylinderGeometry(0.045, 0.055, 0.5, 10),
      new THREE.MeshStandardMaterial({ color: 0x9c7a52, roughness: 0.85 })
    ));
    pole.position.y = -0.28;
    this.post.add(pole);
    const boxMat = new THREE.MeshStandardMaterial({ color: 0xe3554f, roughness: 0.5 });
    this.ownedMats.push(boxMat);
    const box = new THREE.Mesh(new THREE.BoxGeometry(0.52, 0.36, 0.34), boxMat);
    this.ownedGeos.push(box.geometry);
    box.position.y = 0.06;
    this.post.add(box);
    const roof = new THREE.Mesh(new THREE.CylinderGeometry(0.17, 0.17, 0.53, 12, 1, false, 0, Math.PI), boxMat);
    this.ownedGeos.push(roof.geometry);
    roof.rotation.z = Math.PI / 2;
    roof.position.y = 0.24;
    this.post.add(roof);
    const slot = own(new THREE.Mesh(
      new THREE.PlaneGeometry(0.26, 0.05),
      new THREE.MeshBasicMaterial({ color: 0x4a3b36 })
    ));
    slot.position.set(0, 0.08, 0.18);
    this.post.add(slot);
    this.flag = own(new THREE.Mesh(
      new THREE.PlaneGeometry(0.2, 0.13),
      new THREE.MeshBasicMaterial({ color: 0xffd166, side: THREE.DoubleSide })
    ));
    this.flag.geometry.translate(0.1, 0, 0); // hinge at the box corner
    this.flag.position.set(0.26, 0.16, 0.05);
    this.flag.rotation.z = -0.25; // resting: lazily down
    this.post.add(this.flag);
  },

  /** Three pooled house/burrow rigs (slot kinds: house · burrow · house). */
  buildHouses() {
    const own = this.own;
    /** @type {Array<{grp: THREE.Group, kind: string, baseY: number}>} */
    this.houseRigs = [];
    for (let i = 0; i < 3; i += 1) {
      const grp = new THREE.Group();
      const kind = i === 1 ? 'burrow' : 'house';
      if (kind === 'house') {
        const body = own(new THREE.Mesh(
          new THREE.BoxGeometry(0.72, 0.5, 0.4),
          new THREE.MeshStandardMaterial({ color: HOUSE_COLORS[i], roughness: 0.7 })
        ));
        body.position.y = 0.02;
        grp.add(body);
        const roof = own(new THREE.Mesh(
          new THREE.ConeGeometry(0.56, 0.4, 4),
          new THREE.MeshStandardMaterial({ color: 0xc96f52, roughness: 0.65 })
        ));
        roof.rotation.y = Math.PI / 4;
        roof.position.y = 0.44;
        grp.add(roof);
        const door = own(new THREE.Mesh(
          new THREE.CircleGeometry(0.13, 18),
          new THREE.MeshBasicMaterial({ color: 0x6b4a35 })
        ));
        door.scale.y = 1.35;
        door.position.set(0, -0.12, 0.21);
        grp.add(door);
        const window = own(new THREE.Mesh(
          new THREE.CircleGeometry(0.08, 14),
          new THREE.MeshBasicMaterial({ color: 0xfff4c9 })
        ));
        window.position.set(0.2, 0.1, 0.21);
        grp.add(window);
      } else {
        const mound = own(new THREE.Mesh(
          new THREE.SphereGeometry(0.4, 18, 12, 0, Math.PI * 2, 0, Math.PI / 2),
          new THREE.MeshStandardMaterial({ color: 0xb08a5e, roughness: 0.9 })
        ));
        mound.scale.set(1.1, 0.85, 0.9);
        mound.position.y = -0.18;
        grp.add(mound);
        const hole = own(new THREE.Mesh(
          new THREE.CircleGeometry(0.14, 18),
          new THREE.MeshBasicMaterial({ color: 0x4a3325 })
        ));
        hole.scale.y = 1.2;
        hole.position.set(0, -0.1, 0.36);
        grp.add(hole);
        const tuft = own(new THREE.Mesh(
          new THREE.SphereGeometry(0.11, 10, 8),
          new THREE.MeshStandardMaterial({ color: 0x74c26a, roughness: 0.9 })
        ));
        tuft.scale.set(1.3, 0.7, 1);
        tuft.position.set(-0.22, 0.16, 0.1);
        grp.add(tuft);
      }
      this.field.add(grp);
      this.houseRigs.push({ grp, kind, baseY: 0 });
    }
  },

  /** Puddle pool: water ellipse + highlight, scaled per round. */
  buildPuddles() {
    const waterMat = new THREE.MeshBasicMaterial({
      color: 0x7fc3e8, transparent: true, opacity: 0.85, depthWrite: false,
    });
    const shineMat = new THREE.MeshBasicMaterial({
      color: 0xcdeafb, transparent: true, opacity: 0.8, depthWrite: false,
    });
    this.ownedMats.push(waterMat, shineMat);
    const circleGeo = new THREE.CircleGeometry(1, 24);
    this.ownedGeos.push(circleGeo);
    this.puddleMat = waterMat;
    /** @type {Array<{grp: THREE.Group}>} */
    this.puddleRigs = [];
    for (let i = 0; i < this.tune.PUDDLES_MAX; i += 1) {
      const grp = new THREE.Group();
      const water = new THREE.Mesh(circleGeo, waterMat);
      water.scale.set(1, 0.72, 1);
      grp.add(water);
      const shine = new THREE.Mesh(circleGeo, shineMat);
      shine.scale.set(0.32, 0.18, 1);
      shine.position.set(-0.25, 0.18, 0.01);
      grp.add(shine);
      grp.position.z = -0.45;
      grp.visible = false;
      this.field.add(grp);
      this.puddleRigs.push({ grp });
    }
  },

  /** Flower pool: three nature-kit blossoms, repositioned per round. */
  buildFlowers() {
    /** @type {Array<{grp: THREE.Group, picked: boolean}>} */
    this.flowerRigs = [];
    for (const key of ['flower_redA', 'flower_yellowA', 'flower_purpleA']) {
      const holder = fitModel(this.ctx.assets.getModel(`nature-kit/${key}`), 0.52);
      holder.traverse((obj) => {
        if (!obj.isMesh || !obj.material) return;
        const clone = obj.material.clone();
        if ('metalness' in clone) clone.metalness = 0;
        if ('roughness' in clone) clone.roughness = 0.85;
        obj.material = clone;
        this.ownedMats.push(clone);
      });
      holder.visible = false;
      this.field.add(holder);
      this.flowerRigs.push({ grp: holder, picked: false });
    }
  },

  /** The adorable courier snail — top-view rig, big eyes on stalks. */
  buildSnail() {
    const own = this.own;
    this.snail = new THREE.Group();
    this.snail.position.z = 0.35;
    this.field.add(this.snail);
    // body: soft peach foot lying along +x
    this.bodyGrp = new THREE.Group();
    this.snail.add(this.bodyGrp);
    const bodyMat = new THREE.MeshStandardMaterial({ color: 0xf5c98e, roughness: 0.6 });
    this.ownedMats.push(bodyMat);
    const body = new THREE.Mesh(new THREE.CapsuleGeometry(0.105, 0.34, 6, 12), bodyMat);
    this.ownedGeos.push(body.geometry);
    body.rotation.z = Math.PI / 2; // long axis along +x
    body.scale.z = 0.75;
    this.bodyGrp.add(body);
    const head = new THREE.Mesh(new THREE.SphereGeometry(0.115, 14, 10), bodyMat);
    this.ownedGeos.push(head.geometry);
    head.position.set(0.24, 0, 0.03);
    this.bodyGrp.add(head);
    // eye stalks with BIG friendly eyes
    const stalkGeo = new THREE.CylinderGeometry(0.016, 0.02, 0.16, 8);
    const eyeGeo = new THREE.SphereGeometry(0.052, 12, 10);
    const pupilGeo = new THREE.SphereGeometry(0.024, 8, 6);
    const eyeMat = new THREE.MeshBasicMaterial({ color: 0xffffff });
    const pupilMat = new THREE.MeshBasicMaterial({ color: 0x30263d });
    this.ownedGeos.push(stalkGeo, eyeGeo, pupilGeo);
    this.ownedMats.push(eyeMat, pupilMat);
    this.stalks = [];
    for (const side of [-1, 1]) {
      const stalk = new THREE.Group();
      stalk.position.set(0.3, side * 0.055, 0.05);
      const stem = new THREE.Mesh(stalkGeo, bodyMat);
      stem.rotation.z = -side * 0.5;
      stem.rotation.x = -0.25;
      stem.position.set(0.045, side * 0.03, 0.05);
      stalk.add(stem);
      const eye = new THREE.Mesh(eyeGeo, eyeMat);
      eye.position.set(0.1, side * 0.065, 0.12);
      stalk.add(eye);
      const pupil = new THREE.Mesh(pupilGeo, pupilMat);
      pupil.position.set(0.14, side * 0.065, 0.135);
      stalk.add(pupil);
      this.bodyGrp.add(stalk);
      this.stalks.push(stalk);
    }
    // shell: pink dome + cream spiral rim, shimmering brighter per delivery
    this.shellMat = new THREE.MeshStandardMaterial({ color: 0xff9bbd, roughness: 0.4 });
    this.ownedMats.push(this.shellMat);
    this.shell = new THREE.Group();
    this.shell.position.set(-0.1, 0, 0.12);
    this.snail.add(this.shell);
    const dome = new THREE.Mesh(new THREE.SphereGeometry(0.155, 18, 14), this.shellMat);
    this.ownedGeos.push(dome.geometry);
    dome.scale.z = 0.8;
    this.shell.add(dome);
    const rim = own(new THREE.Mesh(
      new THREE.TorusGeometry(0.105, 0.032, 8, 22),
      new THREE.MeshStandardMaterial({ color: 0xfff4e4, roughness: 0.45 })
    ));
    rim.position.z = 0.06;
    this.shell.add(rim);
    const swirl = own(new THREE.Mesh(
      new THREE.SphereGeometry(0.045, 10, 8),
      new THREE.MeshStandardMaterial({ color: 0xfff4e4, roughness: 0.45 })
    ));
    swirl.position.z = 0.13;
    this.shell.add(swirl);
    // the envelope riding on the shell
    this.envelope = new THREE.Group();
    this.envelope.position.set(-0.1, 0, 0.28);
    this.envelope.rotation.z = -0.15;
    this.snail.add(this.envelope);
    const paper = own(new THREE.Mesh(
      new THREE.PlaneGeometry(0.24, 0.16),
      new THREE.MeshBasicMaterial({ color: 0xfffdf4, side: THREE.DoubleSide })
    ));
    this.envelope.add(paper);
    const seal = own(new THREE.Mesh(
      new THREE.CircleGeometry(0.032, 10),
      new THREE.MeshBasicMaterial({ color: 0xe3554f })
    ));
    seal.position.z = 0.005;
    this.envelope.add(seal);
  },

  // ------------------------------------------------------------ dots ribbon

  clearDots() {
    this.dotCount = 0;
    this.nextDot = 0;
    this.dotArcs.length = 0;
    this._s3.setScalar(0.0001);
    this._q.identity();
    for (let i = 0; i < MAX_DOTS; i += 1) {
      this._v3.set(0, 0, -5);
      this._m4.compose(this._v3, this._q, this._s3);
      this.dots.setMatrixAt(i, this._m4);
    }
    this.dots.instanceMatrix.needsUpdate = true;
  },

  /** Place dot #i at a logic point (scale pop handled by uniform size). */
  placeDot(i, x, y, scale = 1) {
    this._v3.set(x, y, 0.2);
    this._q.identity();
    this._s3.setScalar(scale);
    this._m4.compose(this._v3, this._q, this._s3);
    this.dots.setMatrixAt(i, this._m4);
    this.dots.instanceMatrix.needsUpdate = true;
  },

  /** Hide dot #i (consumed by the snail / cleared). */
  hideDot(i) {
    this._v3.set(0, 0, -5);
    this._q.identity();
    this._s3.setScalar(0.0001);
    this._m4.compose(this._v3, this._q, this._s3);
    this.dots.setMatrixAt(i, this._m4);
    this.dots.instanceMatrix.needsUpdate = true;
  },

  /** Re-lay the ribbon uniformly along the smoothed path (follow phase). */
  layDotsAlongPath(path, revealFrac = 1) {
    this.clearDots();
    const n = Math.min(MAX_DOTS, Math.max(2, Math.floor(path.length / DOT_SPACING) + 1));
    const upto = Math.max(0, Math.min(n, Math.ceil(n * revealFrac)));
    const pose = this.pose;
    for (let i = 0; i < upto; i += 1) {
      const arc = (path.length * i) / (n - 1);
      followInto(path, arc, pose);
      this.placeDot(i, pose.x, pose.y);
      this.dotArcs.push(arc);
    }
    this.dotCount = upto;
    this.nextDot = 0;
  },

  // ------------------------------------------------------------ stroke input

  /** Append a stroke point (spacing-filtered) + drop a live glitter dot. */
  pushStrokePoint(p) {
    if (this.rawPts.length >= this.tune.MAX_INPUT_POINTS) return;
    const last = this.rawPts[this.rawPts.length - 1];
    if (last && Math.hypot(p.x - last.x, p.y - last.y) < this.tune.MIN_INPUT_SPACING) return;
    const x = Math.max(-this.tune.FIELD_HALF_W, Math.min(this.tune.FIELD_HALF_W, p.x));
    const y = Math.max(this.tune.FIELD_Y_MIN, Math.min(this.tune.FIELD_Y_MAX, p.y));
    this.rawPts.push({ x, y });
    if (this.dotCount < MAX_DOTS) {
      this.placeDot(this.dotCount, x, y);
      this.dotCount += 1;
    }
  },

  /** Finger lifted: validate the stroke and send the snail (or fizzle). */
  releaseStroke() {
    const path = this.rawPts.length >= 2 ? smoothPath(this.rawPts, this.tune) : null;
    const target = path ? endHouse(path, this.level, this.tune) : -1;
    if (!path || target !== this.level.targetIdx) {
      // comfy fizzle — no penalty, just try again
      const tip = this.rawPts[this.rawPts.length - 1] ?? { x: this.tune.POST_X, y: this.tune.POST_Y };
      this.floats.spawn(tx('snail.wrongHouse'), this.fieldToWorld(tip.x, tip.y + 0.3), '#8A7FA8');
      this.particles.emit('bubbles', this.fieldToWorld(tip.x, tip.y), { count: 3 });
      this.clearDots();
      this.rawPts.length = 0;
      return;
    }
    this.beginFollow(path);
  },

  /** Start the snail along a validated path. */
  beginFollow(path) {
    this.path = path;
    this.arcS = 0;
    this.wet = false;
    this.immunePuddle = -1;
    this.retreatT = 0;
    this.phase = 'follow';
    this.rawPts.length = 0;
    this.layDotsAlongPath(path);
    // flower trigger arcs: first waypoint within pick radius of each flower
    this.flowerTriggers.length = 0;
    for (let f = 0; f < this.level.flowers.length; f += 1) {
      if (this.flowerRigs[f]?.picked) continue;
      const fl = this.level.flowers[f];
      for (let i = 0; i < path.pts.length; i += 1) {
        const pt = path.pts[i];
        if (Math.hypot(pt.x - fl.x, pt.y - fl.y) <= this.tune.FLOWER_PICK_RADIUS) {
          this.flowerTriggers.push({ arc: path.cum[i], idx: f, done: false });
          break;
        }
      }
    }
    this.ctx.audio.play('bubble.pop');
    this.floats.spawn(tx('snail.go'), this.fieldToWorld(this.tune.POST_X, this.tune.POST_Y + 0.75), '#2E8B57');
    this.envelope.visible = true;
    // snail hops onto the path start
    const grp = this.snail;
    grp.position.set(this.tune.POST_X, this.tune.POST_Y, 0.35);
    tween({
      from: 0.6, to: 1, duration: 0.22, ease: easings.easeOutBack,
      onUpdate: (v) => grp.scale.setScalar(v),
    });
  },

  // ------------------------------------------------------------ rounds

  /** Generate + lay out a fresh delivery round. */
  startRound(first = false) {
    this.level = generateLevel(this.ctx.rng, this.round, this.tune);
    this.phase = 'draw';
    this.drawing = false;
    this.path = null;
    this.rawPts.length = 0;
    this.clearDots();
    this.autoRouteCache = null;
    this.autoT = 0;
    // houses slide/bounce to their round spots
    for (let i = 0; i < this.houseRigs.length; i += 1) {
      const rig = this.houseRigs[i];
      const h = this.level.houses[i];
      rig.grp.position.set(h.x, h.y, 0);
      rig.baseY = h.y;
      if (!this.reducedMotion) {
        const grp = rig.grp;
        tween({
          from: 0.5, to: 1, duration: 0.35, ease: easings.easeOutBack,
          onUpdate: (v) => grp.scale.setScalar(v),
        });
      }
    }
    // puddles
    for (let i = 0; i < this.puddleRigs.length; i += 1) {
      const rig = this.puddleRigs[i];
      const p = this.level.puddles[i];
      if (!p) {
        rig.grp.visible = false;
        continue;
      }
      rig.grp.visible = true;
      rig.grp.position.set(p.x, p.y, -0.45);
      const target = p.r;
      if (this.reducedMotion) {
        rig.grp.scale.setScalar(target);
      } else {
        const grp = rig.grp;
        tween({
          from: 0.01, to: target, duration: 0.4, ease: easings.easeOutCubic,
          onUpdate: (v) => grp.scale.setScalar(v),
        });
      }
    }
    // flowers
    for (let i = 0; i < this.flowerRigs.length; i += 1) {
      const rig = this.flowerRigs[i];
      const f = this.level.flowers[i];
      rig.picked = false;
      if (!f) {
        rig.grp.visible = false;
        continue;
      }
      rig.grp.visible = true;
      rig.grp.position.set(f.x, f.y, -0.1);
      if (!this.reducedMotion) {
        const grp = rig.grp;
        tween({
          from: 0.01, to: 1, duration: 0.3, ease: easings.easeOutBack,
          onUpdate: (v) => grp.scale.setScalar(v),
        });
      } else {
        rig.grp.scale.setScalar(1);
      }
    }
    // target highlight
    const door = doorOf(this.level.houses[this.level.targetIdx], this.tune);
    this.glow.position.set(door.x, door.y - 0.05, -0.5);
    this.arrowBaseY = this.level.houses[this.level.targetIdx].y + 0.75;
    this.arrow.position.set(this.level.houses[this.level.targetIdx].x, this.arrowBaseY, 0.3);
    // post flag rests down, snail waits BESIDE the post box with the letter
    // (offset right so the little courier and the red box both read clearly;
    // beginFollow hops it onto the path start = the post itself)
    this.flag.rotation.z = -0.25;
    this.snail.position.set(this.tune.POST_X + 0.48, this.tune.POST_Y - 0.06, 0.35);
    this.snail.scale.setScalar(1);
    this.snailAngle = Math.PI / 2;
    this.snail.rotation.z = 0; // rig faces +x; heading applied as angle − π/2 later
    this.envelope.visible = true;
    this.bodyGrp.scale.setScalar(1);
    if (!first && this.autoplay) this.prepareAutoplayRound();
    if (this.autoplay && first) this.prepareAutoplayRound();
  },

  /** Autoplay: cache the reference route; dots reveal over BOT_DRAW_SEC. */
  prepareAutoplayRound() {
    this.autoRouteCache = autoRoute(this.level, this.tune);
    this.autoT = 0;
  },

  /** Mailbox says "start here" (denied-start wiggle). */
  wigglePost() {
    if (this.reducedMotion) return;
    const post = this.post;
    tween({
      from: 0.16, to: 0, duration: 0.4, ease: easings.easeOutCubic,
      onUpdate: (v) => { post.rotation.z = Math.sin(v * 40) * v; },
    });
  },

  // ------------------------------------------------------------ deliver / splash

  /** The snail reached the door — score the delivery and celebrate. */
  deliver() {
    const target = this.level.houses[this.level.targetIdx];
    const door = doorOf(target, this.tune);
    const doorPos = this.fieldToWorld(door.x, door.y + 0.2);
    // base points (+ dry bonus) — flower points were paid live along the path
    const prev = this.score;
    this.score = applyScore(this.score, this.tune.DELIVER_PTS);
    if (this.score !== prev) this.ctx.onScore(this.score - prev);
    this.ctx.audio.play('jingle.short');
    this.ctx.audio.play('delivery.doorbell');
    this.floats.spawn(`+${this.tune.DELIVER_PTS} ${tx('snail.delivered')}`, doorPos, '#2E8B57');
    // burst sizes budgeted: pooled sprites cost 1 draw call each and the
    // delivery beat is the frame-cost peak (≤100 total with the diorama)
    this.particles.emit('hearts', doorPos, { count: 5 });
    this.particles.emit('sparkles', doorPos, { count: 4 });
    if (!this.wet) {
      const before = this.score;
      this.score = applyScore(this.score, this.tune.DRY_BONUS);
      if (this.score !== before) this.ctx.onScore(this.score - before);
      this.ctx.audio.play('combo.up');
      this.ctx.hud.banner(tx('snail.dry', { n: this.tune.DRY_BONUS }));
    }
    this.reactGooby('ecstatic', 'happyBounce');
    // mailbox flag springs up + envelope handed over
    this.envelope.visible = false;
    const flag = this.flag;
    tween({
      from: -0.25, to: 1.15, duration: 0.3, ease: easings.easeOutBack,
      onUpdate: (v) => { flag.rotation.z = v; },
    });
    // the shell shimmers one hue brighter per delivered letter
    this.deliveries += 1;
    this.shellMat.color.setHSL((0.93 + this.deliveries * 0.045) % 1, 0.72, 0.72);
    this.round += 1;
    this.phase = 'rate';
    this.rateT = this.tune.ROUND_BEAT_SEC;
  },

  /** Splash! The snail hides in its shell for RETREAT_SEC. */
  splash(puddleIdx) {
    this.retreatT = this.tune.RETREAT_SEC;
    this.immunePuddle = puddleIdx;
    this.ctx.audio.play('wash.splash');
    const pos = this.fieldToWorld(this.pose.x, this.pose.y + 0.25);
    this.particles.emit('bubbles', pos, { count: 6 });
    this.particles.emit('dizzyStars', pos, { count: 3 });
    this.floats.spawn(tx('snail.splash'), pos, '#D64570');
    if (!this.reducedMotion) this.shakeT = 0.22;
    this.reactGooby('dizzy', 'dizzy');
    // hide: head + foot tuck under the shell
    const bodyGrp = this.bodyGrp;
    tween({
      from: 1, to: 0.06, duration: 0.18, ease: easings.easeOutCubic,
      onUpdate: (v) => bodyGrp.scale.setScalar(Math.max(0.06, v)),
    });
    if (!this.wet) {
      this.wet = true;
      if (this.tune.ENDLESS) {
        this.splashes += 1;
        this.ctx.hud.banner(tx('snail.splashes', { n: this.splashes, max: this.tune.ENDLESS_MAX_SPLASHES }));
        if (endlessShouldEnd(this.splashes, this.tune)) {
          this.finishRound();
        }
      }
    }
  },

  /** Peek back out of the shell after a retreat. */
  emergeFromShell() {
    const bodyGrp = this.bodyGrp;
    tween({
      from: 0.06, to: 1, duration: 0.25, ease: easings.easeOutBack,
      onUpdate: (v) => bodyGrp.scale.setScalar(v),
    });
    this.ctx.audio.play('gooby.giggle');
  },

  finishRound() {
    if (this.phase === 'ending' || this.phase === 'done') return;
    this.phase = 'ending';
    this.rateT = 1.3;
    this.drawing = false;
    this.shakeT = 0;
    this.ctx.camera.position.set(0, 0, 10);
    this.ctx.audio.play('ui.win');
    this.gooby.setEmotion('ecstatic');
    this.gooby.play('happyBounce');
    this.particles.emit('confetti', this.gooby.group.position.clone().add(new THREE.Vector3(0, 1.0, 0)), { count: 10 });
  },

  /** Brief Gooby reaction. */
  reactGooby(emotion, clip) {
    this.gooby.setEmotion(emotion);
    this.emotionT = 1.1;
    if (clip === 'dizzy' || !this.gooby.isPlaying(clip)) this.gooby.play(clip);
  },

  // ------------------------------------------------------------ update loop

  update(dt, elapsed) {
    const ctx = this.ctx;
    this.elapsed = elapsed;
    this.gooby.update(dt);
    this.particles.update(dt);
    this.floats.update(dt);

    // micro-shake on splashes (reduced-motion gated at the trigger)
    if (this.shakeT > 0) {
      this.shakeT -= dt;
      const k = Math.max(0, this.shakeT / 0.22) * 0.05;
      ctx.camera.position.set((ctx.rng() - 0.5) * k, (ctx.rng() - 0.5) * k, 10);
      if (this.shakeT <= 0) ctx.camera.position.set(0, 0, 10);
    }
    if (this.emotionT > 0) {
      this.emotionT -= dt;
      if (this.emotionT <= 0) this.gooby.setEmotion('happy');
    }

    // idle life: everything breathes (transform-only, no allocations)
    this.cloud.position.x += dt * 0.02;
    if (this.cloud.position.x > this.halfW + 1) this.cloud.position.x = -this.halfW - 1;
    this.arrow.position.y = this.arrowBaseY + Math.abs(Math.sin(elapsed * 2.4)) * 0.14;
    this.glowMat.opacity = 0.4 + Math.sin(elapsed * 2.2) * 0.15;
    this.post.rotation.z = Math.sin(elapsed * 1.1) * 0.02;
    for (let i = 0; i < this.houseRigs.length; i += 1) {
      this.houseRigs[i].grp.rotation.z = Math.sin(elapsed * 1.2 + i * 2.1) * 0.012;
    }
    for (let i = 0; i < this.flowerRigs.length; i += 1) {
      if (this.flowerRigs[i].grp.visible) {
        this.flowerRigs[i].grp.rotation.z = Math.sin(elapsed * 1.6 + i * 1.3) * 0.06;
      }
    }
    for (let i = 0; i < this.stalks.length; i += 1) {
      this.stalks[i].rotation.z = Math.sin(elapsed * 3.1 + i * Math.PI) * 0.09;
    }

    if (this.phase === 'ending') {
      this.rateT -= dt;
      if (this.rateT <= 0 && this.phase !== 'done') {
        this.phase = 'done';
        ctx.onEnd({ score: this.score });
      }
      return;
    }
    if (this.phase === 'done') return;

    const remaining = this.tune.DURATION_SEC - elapsed;
    ctx.hud.setTime(this.tune.ENDLESS ? elapsed : remaining);
    if (!this.tune.ENDLESS && remaining <= 0) {
      this.finishRound();
      if (this.autoplay) {
        console.log(`[snailMail] autoplay run ended — score ${this.score}, deliveries ${this.deliveries}, splashes ${this.splashes}`);
      }
      return;
    }

    if (this.phase === 'rate') {
      this.rateT -= dt;
      if (this.rateT <= 0) this.startRound();
      return;
    }

    if (this.phase === 'draw') {
      // gentle waiting bob beside the post box
      this.snail.position.y = this.tune.POST_Y - 0.06 + Math.sin(elapsed * 2.4) * 0.02;
      if (this.autoplay && this.autoRouteCache?.ok) {
        this.autoT += dt;
        const frac = Math.min(1, this.autoT / this.tune.BOT_DRAW_SEC);
        this.layDotsAlongPath(this.autoRouteCache.smooth, frac);
        if (frac >= 1) this.beginFollow(this.autoRouteCache.smooth);
      }
      return;
    }

    // ---- follow phase ----
    if (this.retreatT > 0) {
      this.retreatT -= dt;
      this.shell.rotation.z = Math.sin(this.retreatT * 18) * 0.12 * Math.min(1, this.retreatT);
      if (this.retreatT <= 0) {
        this.shell.rotation.z = 0;
        this.emergeFromShell();
      }
      return;
    }
    const path = this.path;
    if (!path) return;
    this.arcS = advanceArc(this.arcS, dt, path.length, this.tune);
    followInto(path, this.arcS, this.pose);
    this.snail.position.x = this.pose.x;
    this.snail.position.y = this.pose.y;
    // heading: rig faces +x — rotate by the shortest arc toward pose.angle
    let diff = this.pose.angle - this.snailAngle;
    while (diff > Math.PI) diff -= Math.PI * 2;
    while (diff < -Math.PI) diff += Math.PI * 2;
    this.snailAngle += diff * Math.min(1, dt * 10);
    this.snail.rotation.z = this.snailAngle;
    // envelope bob
    this.envelope.position.z = 0.28 + Math.sin(elapsed * 5) * 0.01;
    // consume glitter dots behind the snail
    while (this.nextDot < this.dotCount && this.dotArcs[this.nextDot] <= this.arcS) {
      this.hideDot(this.nextDot);
      this.nextDot += 1;
    }
    // flower pickups (arc-triggered)
    for (const trigger of this.flowerTriggers) {
      if (trigger.done || trigger.arc > this.arcS) continue;
      trigger.done = true;
      const rig = this.flowerRigs[trigger.idx];
      if (rig && !rig.picked) {
        rig.picked = true;
        const prev = this.score;
        this.score = applyScore(this.score, this.tune.FLOWER_PTS);
        if (this.score !== prev) this.ctx.onScore(this.score - prev);
        this.ctx.audio.play('hop.bell');
        const pos = this.fieldToWorld(this.level.flowers[trigger.idx].x, this.level.flowers[trigger.idx].y + 0.25);
        this.particles.emit('sparkles', pos, { count: 4 });
        this.floats.spawn(`+${this.tune.FLOWER_PTS} ${tx('snail.flower')}`, pos, '#C98A00');
        const grp = rig.grp;
        tween({
          from: 1, to: 0.01, duration: 0.3, ease: easings.easeInCubic,
          onUpdate: (v) => grp.scale.setScalar(v),
          onComplete: () => { grp.visible = false; },
        });
      }
    }
    // puddle splash (immune to the one just splashed until it is left behind)
    const hit = puddleHitAt(this.pose.x, this.pose.y, this.level.puddles, this.tune);
    if (hit >= 0 && hit !== this.immunePuddle) {
      this.splash(hit);
      return;
    }
    if (hit < 0) this.immunePuddle = -1;
    // arrived?
    if (this.arcS >= path.length) {
      this.deliver();
    }
  },

  dispose() {
    if (import.meta.env?.DEV && window.__snail === this) delete window.__snail; // CDP probe
    const el = this.ctx?.renderer?.domElement;
    el?.removeEventListener('pointerdown', this.onPointerDown);
    el?.removeEventListener('pointermove', this.onPointerMove);
    el?.removeEventListener('pointerup', this.onPointerUp);
    el?.removeEventListener('pointercancel', this.onPointerUp);
    el?.removeEventListener('pointerleave', this.onPointerUp);
    this.floats?.dispose();
    this.particles?.dispose();
    this.gooby?.dispose();
    this.dots?.dispose(); // InstancedMesh frees its instance buffers
    for (const geo of this.ownedGeos ?? []) geo.dispose();
    for (const mat of this.ownedMats ?? []) mat.dispose();
    this.ownedGeos = [];
    this.ownedMats = [];
    this.field = null;
    this.post = null;
    this.flag = null;
    this.houseRigs = [];
    this.puddleRigs = [];
    this.flowerRigs = [];
    this.snail = null;
    this.bodyGrp = null;
    this.shell = null;
    this.shellMat = null;
    this.envelope = null;
    this.stalks = [];
    this.dots = null;
    this.dotGeo = null;
    this.dotMat = null;
    this.glow = null;
    this.glowMat = null;
    this.arrow = null;
    this.cloud = null;
    this.level = null;
    this.path = null;
    this.autoRouteCache = null;
    this.tune = null;
    this.gooby = null;
    this.particles = null;
    this.floats = null;
    this.ctx = null;
  },
};
export const controls = Object.freeze({ invertible: false }); // V6/C2 (§G2.1 rule 4): positional path-drawing input — inverting is nonsense here
