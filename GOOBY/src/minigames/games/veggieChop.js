// Veggie Chop (PLAN2 §C1.2 #4, agent V2/G27): fruit-ninja-style swipe
// slicer in a kitchen cutting-board arena (§C1.3 — giant wooden board,
// pastel tile backsplash, counter props; NOT burgerBuild's diner checker).
// Veggies/fruits are lobbed up in arcs (1–3 at once, ramping); swipe through
// them to chop — each whole splits into its two food-kit half models with a
// juice splash (+2, +1 per extra in the same swipe). Soda cans and the boot
// are junk: chopping them costs −3 and a 0.5 s splash stun. 3 veggies fallen
// unchopped end the round early; otherwise 60 s. Swipe trail rendered as a
// fading ribbon. Pure arc/scoring logic in veggieChop.logic.js (§B rule).
// Dev-only ?autoplay=1: the bot synthesizes a swipe through each veggie at
// its arc apex and ignores junk (§C1.2), with a human-ish skip/aim error.

import * as THREE from 'three';
import { t, getLang } from '../../data/strings.js';
import { EN as GP2_EN, DE as GP2_DE } from '../../data/strings/v4-gpgroup2.js';
// V6/C4 (GAME-JUICE): frenzy float label rides the v6-juice module
import { EN as JUICE_EN, DE as JUICE_DE } from '../../data/strings/v6-juice.js';
import { createParticles } from '../../gfx/particles.js';
import { tween, easings } from '../../gfx/tween.js'; // V6/C4: half pop + shake + tint
import { prefersReducedMotion } from '../../ui/ui.js'; // V6/C4: gate shake/flash
import { createGooby } from '../../character/gooby.js';
import { applyEquippedOutfits } from '../../character/outfitAttach.js';
import { clampFloatTextToView } from '../framework.js';
import {
  CHOP,
  applyDifficulty,
  applyTurbo,
  VEGGIES,
  waveSizeAt,
  spawnIntervalAt,
  rollItem,
  rollVeggie,
  frenzySpawnInterval,
  frenzyCountAt,
  makeArc,
  arcPos,
  arcApex,
  chopPoints,
  comboAfterHit,
  applyPoints,
  finalScore,
  endlessShouldEnd,
  segmentHitsMovingCircle,
} from './veggieChop.logic.js';

/** GP2 local i18n: strings.js first, v4-gpgroup2.js fallback (G52 pattern).
 * V6/C4: also consults the v6-juice table (C3 commits the strings.js import). */
function tx(key, vars) {
  const global = t(key, vars);
  if (global !== key) return global;
  const de = getLang() === 'de';
  let text = (de ? GP2_DE : GP2_EN)[key] ?? (de ? JUICE_DE : JUICE_EN)[key] ?? key;
  if (vars) {
    for (const [name, value] of Object.entries(vars)) {
      text = text.replaceAll(`{${name}}`, String(value));
    }
  }
  return text;
}

const ITEM_SIZE = 0.62;
const HALF_SIZE = 0.5;
/** Swipe trail: max points kept / seconds a point stays visible. */
const TRAIL_MAX = 22;
const TRAIL_LIFE = 0.22;
const TRAIL_WIDTH = 0.15;

// ── V6/C4 (GAME-JUICE): chop-juice tuning — frozen module-local (§E0.1-3;
// veggieChop.logic.js is not owned by this pass). STRICTLY cosmetic: the
// frozen §C1.2 #4 CHOP scoring table (+2/+1/−3) is untouched — pinned by
// test/gamePolish6.test.js.
export const CHOP_JUICE6 = Object.freeze({
  /** Half pop-in: spawn scale + settle time (easeOutBack → 1, §C.6 #1). */
  HALF_POP_SCALE: 0.55,
  HALF_POP_SEC: 0.24,
  /** Tiny confetti puff riding the tinted juice spray per chop. */
  CHOP_CONFETTI: 3,
  /** Frenzy entrance: confetti burst + golden backdrop pulse (§C.6 #2). */
  FRENZY_CONFETTI: 16,
  FRENZY_TINT_SEC: 0.6,
  /** Junk-hit camera micro-shake: 0.2 s, tiny amplitude (§C.6 #3, RM-gated). */
  JUNK_SHAKE_SEC: 0.2,
  JUNK_SHAKE_AMP: 0.09,
});
// backdrop tint scratch colors (kitchen cream → frenzy gold)
const _BG_BASE = new THREE.Color('#F6E7CF');
const _BG_GOLD = new THREE.Color('#FFD98A');
// ── end V6/C4 ────────────────────────────────────────────────────────────────

/** Fit a GLB into a target size, centered in a wrapper group. */
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

/** Tiny floating score text (canvas sprites, self-disposing). */
function createFloatTexts(scene, camera) {
  const active = new Set();
  return {
    spawn(text, pos, color = '#4A3B36') {
      const canvas = document.createElement('canvas');
      canvas.width = 200;
      canvas.height = 80;
      const g = canvas.getContext('2d');
      g.font = '900 42px system-ui, sans-serif';
      g.textAlign = 'center';
      g.textBaseline = 'middle';
      g.lineWidth = 8;
      g.strokeStyle = 'rgba(255,255,255,0.92)';
      g.strokeText(text, 100, 40);
      g.fillStyle = color;
      g.fillText(text, 100, 40);
      const tex = new THREE.CanvasTexture(canvas);
      const mat = new THREE.SpriteMaterial({ map: tex, transparent: true, depthWrite: false });
      const sprite = new THREE.Sprite(mat);
      sprite.position.copy(clampFloatTextToView(pos.clone(), camera, { halfW: 0.65, halfH: 0.26 }));
      sprite.scale.set(1.3, 0.52, 1);
      scene.add(sprite);
      active.add({ sprite, mat, tex, age: 0, life: 0.85 });
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

/** Pastel kitchen tile backsplash as a CanvasTexture (§C1.3 look). */
function makeTileTexture() {
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = 256;
  const g = canvas.getContext('2d');
  const tiles = ['#DCEFEA', '#E8F3EE', '#D5EAE6', '#E3F0E4'];
  const size = 64;
  for (let ty = 0; ty < 4; ty += 1) {
    for (let tx = 0; tx < 4; tx += 1) {
      g.fillStyle = tiles[(tx + ty * 3) % tiles.length];
      g.fillRect(tx * size, ty * size, size, size);
    }
  }
  g.strokeStyle = 'rgba(255,255,255,0.85)';
  g.lineWidth = 5;
  for (let i = 0; i <= 4; i += 1) {
    g.beginPath();
    g.moveTo(i * size, 0);
    g.lineTo(i * size, 256);
    g.stroke();
    g.beginPath();
    g.moveTo(0, i * size);
    g.lineTo(256, i * size);
    g.stroke();
  }
  const tex = new THREE.CanvasTexture(canvas);
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.repeat.set(3, 2);
  return tex;
}

/** Pooled juice-splash droplets (sprite dots tinted per veggie). */
function createJuice(scene) {
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = 32;
  const g = canvas.getContext('2d');
  g.fillStyle = '#FFFFFF';
  g.beginPath();
  g.arc(16, 16, 14, 0, Math.PI * 2);
  g.fill();
  const tex = new THREE.CanvasTexture(canvas);
  /** @type {Array<{sprite: THREE.Sprite, mat: THREE.SpriteMaterial, vel: THREE.Vector3, age: number, life: number, size: number, active: boolean}>} */
  const pool = [];
  for (let i = 0; i < 42; i += 1) {
    const mat = new THREE.SpriteMaterial({ map: tex, transparent: true, depthWrite: false });
    const sprite = new THREE.Sprite(mat);
    sprite.visible = false;
    scene.add(sprite);
    pool.push({ sprite, mat, vel: new THREE.Vector3(), age: 0, life: 0.5, size: 0.1, active: false });
  }
  return {
    emit(pos, colorHex, count = 7, rng = Math.random) {
      let n = 0;
      for (const p of pool) {
        if (n >= count) break;
        if (p.active) continue;
        p.active = true;
        p.age = 0;
        p.life = 0.35 + rng() * 0.3;
        p.size = 0.07 + rng() * 0.09;
        const a = rng() * Math.PI * 2;
        const v = 1.2 + rng() * 1.8;
        p.vel.set(Math.cos(a) * v, Math.abs(Math.sin(a)) * v * 0.9 + 0.6, 0);
        p.sprite.position.copy(pos);
        p.sprite.visible = true;
        p.mat.color.set(colorHex);
        p.mat.opacity = 1;
        n += 1;
      }
    },
    update(dt) {
      for (const p of pool) {
        if (!p.active) continue;
        p.age += dt;
        p.vel.y -= 7 * dt;
        p.sprite.position.addScaledVector(p.vel, dt);
        const k = p.age / p.life;
        p.mat.opacity = 1 - k * k;
        p.sprite.scale.setScalar(p.size * (1 - k * 0.4));
        if (p.age >= p.life) {
          p.active = false;
          p.sprite.visible = false;
        }
      }
    },
    dispose() {
      for (const p of pool) {
        p.sprite.parent?.remove(p.sprite);
        p.mat.dispose();
      }
      tex.dispose();
      pool.length = 0;
    },
  };
}

/** @type {object} §E8 plugin */
export default {
  id: 'veggieChop',
  assetKeys: [
    ...VEGGIES.map((v) => `food-kit/${v.key}`),
    ...VEGGIES.map((v) => `food-kit/${v.half}`),
    'food-kit/soda',
    'kaykit-restaurant/cuttingboard',
    'food-kit/frying-pan',
    'food-kit/mug',
  ],

  /** @param {object} ctx §E8 game context */
  init(ctx) {
    this.ctx = ctx;
    this.autoplay =
      import.meta.env?.DEV && new URLSearchParams(location.search).get('autoplay') === '1';
    this.difficulty = ['easy', 'normal', 'hard', 'endless'].includes(ctx.params?.difficulty)
      ? ctx.params.difficulty
      : 'normal';
    const modifier = ctx.params?.modifier?.type === 'turbo'
      ? {
        speedMult: ctx.params.modifier.speedMult,
        scoreMult: ctx.params.modifier.scoreMult,
      }
      : {};
    this.tune = applyTurbo(applyDifficulty(CHOP, this.difficulty), modifier);

    this.phase = 'play'; // 'play' | 'ending' | 'done'
    this.score = 0;
    this.misses = 0;
    this.junkHits = 0;
    this.stunT = 0;
    this.endT = 0;
    this.spawnT = 0.7; // head start before the first lob
    this.swipeChops = 0; // veggies chopped by the CURRENT swipe (combo)
    this.itemSeq = 0;
    this.frenzyCount = 0;
    this.frenzy = null;
    this.propLogged = false;
    this.bgTween = null; // V6/C4: frenzy backdrop pulse
    this.shakeTween = null; // V6/C4: junk micro-shake

    const camera = ctx.camera;
    camera.position.set(0, 0, 10);
    camera.lookAt(0, 0, 0);
    this.halfH = Math.tan(THREE.MathUtils.degToRad(camera.fov / 2)) * 10;
    this.halfW = this.halfH * (innerWidth / innerHeight);
    this.launchY = -this.halfH - 0.6;

    const scene = ctx.scene;
    scene.background = new THREE.Color('#F6E7CF'); // warm kitchen cream

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

    scene.add(new THREE.HemisphereLight(0xfff6e8, 0xd9c2a8, 1.15));
    const dir = new THREE.DirectionalLight(0xfff0da, 0.9);
    dir.position.set(2.5, 6, 5);
    scene.add(dir);

    // --- kitchen backdrop: tile backsplash strip + counter + giant board ---
    const tileTex = makeTileTexture();
    this.ownedTexs.push(tileTex);
    const splash = own(new THREE.Mesh(
      new THREE.PlaneGeometry(this.halfW * 2 + 2, 3.4),
      new THREE.MeshBasicMaterial({ map: tileTex })
    ));
    splash.position.set(0, this.halfH - 1.2, -3);
    scene.add(splash);
    const counter = own(new THREE.Mesh(
      new THREE.PlaneGeometry(this.halfW * 2 + 2, 2.6),
      new THREE.MeshBasicMaterial({ color: '#C98A4B' })
    ));
    counter.position.set(0, -this.halfH + 0.9, -2.6);
    scene.add(counter);
    // the arena: a giant cutting board leaning against the backsplash (§C1.3)
    // V3/G45 §C11.1: the one-mesh Restaurant-Bits board replaces the
    // food-kit stand-in; gameplay arcs/hit radii remain data-driven.
    // V4/GAME-POLISH-2: the old mount stood the board portrait at z -1.6 —
    // a full-screen brown wall that hid the counter/backsplash (CDP shot).
    // Now it leans landscape against the wall like a real board: local X
    // (long edge) → screen X, local Y (board normal) → camera + easel tilt.
    this.board = fitModel(ctx.assets.getModel('kaykit-restaurant/cuttingboard'), 5.6);
    this.board.rotation.set(Math.PI / 2 - 0.16, Math.PI, 0); // Ry(π): handle notch up
    this.board.position.set(0, -1.35, -2.2);
    scene.add(this.board);
    // counter props: frying pan bottom-right (Gooby moved to bottom-left so
    // the HUD pause button no longer covers him), mug beside Gooby
    const pan = fitModel(ctx.assets.getModel('food-kit/frying-pan'), 1.15);
    pan.position.set(this.halfW - 0.9, -this.halfH + 0.75, -1.2);
    scene.add(pan);
    const mug = fitModel(ctx.assets.getModel('food-kit/mug'), 0.6);
    mug.position.set(-this.halfW + 1.7, -this.halfH + 0.72, -1.2);
    scene.add(mug);

    // --- miss pips: 3 little tomatoes, greyed as veggies drop (§C1.2) ---
    /** @type {THREE.MeshBasicMaterial[]} */
    this.missMats = [];
    for (let i = 0; i < CHOP.MAX_MISSES; i += 1) {
      const mat = new THREE.MeshBasicMaterial({ color: '#E8523F' });
      const pip = new THREE.Mesh(new THREE.CircleGeometry(0.13, 20), mat);
      pip.position.set(-0.45 + i * 0.45, this.halfH - 1.75, -0.5);
      this.ownedGeos.push(pip.geometry);
      this.ownedMats.push(mat);
      this.missMats.push(mat);
      scene.add(pip);
    }

    // --- chef Gooby watching from the counter corner ---
    this.particles = createParticles(scene);
    this.floats = createFloatTexts(scene, camera);
    this.juice = createJuice(scene);
    this.gooby = createGooby({ particles: this.particles });
    applyEquippedOutfits(this.gooby);
    this.gooby.group.scale.setScalar(0.62);
    // V4/GAME-POLISH-2: bottom-LEFT corner — the framework pause button sits
    // bottom-right and used to cover chef Gooby entirely (CDP shot)
    this.gooby.group.position.set(-this.halfW + 0.85, -this.halfH + 0.55, 0.4);
    this.gooby.setEmotion('happy');
    this.gooby.lookAt(new THREE.Vector3(0, 0.5, 5));
    scene.add(this.gooby.group);

    // --- swipe trail ribbon (§C1.2: trail rendered) ---
    /** @type {Array<{x: number, y: number, age: number}>} */
    this.trail = [];
    this.trailGeo = new THREE.BufferGeometry();
    this.trailGeo.setAttribute(
      'position',
      new THREE.BufferAttribute(new Float32Array(TRAIL_MAX * 2 * 3), 3)
    );
    this.trailGeo.setIndex(new THREE.BufferAttribute(new Uint16Array((TRAIL_MAX - 1) * 6), 1));
    this.trailMat = new THREE.MeshBasicMaterial({
      color: '#FFFFFF', transparent: true, opacity: 0.9, depthWrite: false, side: THREE.DoubleSide,
    });
    this.ownedGeos.push(this.trailGeo);
    this.ownedMats.push(this.trailMat);
    this.trailMesh = new THREE.Mesh(this.trailGeo, this.trailMat);
    this.trailMesh.renderOrder = 5;
    this.trailMesh.frustumCulled = false;
    scene.add(this.trailMesh);

    // --- flying items (pooled per asset key) + loose halves ---
    /** @type {Array<object>} */
    this.items = [];
    /** @type {Array<object>} */
    this.halves = [];
    /** @type {Map<string, THREE.Group[]>} */
    this.pool = new Map();
    this.bootMat = new THREE.MeshStandardMaterial({ color: 0x3d2c22, roughness: 0.85 });
    this.ownedMats.push(this.bootMat);

    // --- input: drag = swipe; each dragstart begins a new combo window ---
    this.lastDrag = null;
    this.offStart = ctx.input.on('dragstart', (p) => {
      if (this.autoplay || this.phase !== 'play') return;
      this.swipeChops = 0;
      this.lastDrag = { x: p.nx * this.halfW, y: p.ny * this.halfH };
    });
    this.offDrag = ctx.input.on('drag', (p) => {
      if (this.autoplay || this.phase !== 'play') return;
      const pt = { x: p.nx * this.halfW, y: p.ny * this.halfH };
      if (this.lastDrag && this.stunT <= 0) {
        this.chopSegment(this.lastDrag.x, this.lastDrag.y, pt.x, pt.y);
        this.pushTrail(pt.x, pt.y);
      }
      this.lastDrag = pt;
    });
    this.offEnd = ctx.input.on('dragend', () => {
      this.lastDrag = null;
      this.swipeChops = 0;
    });

    ctx.hud.setScore(0);
    ctx.hud.setTime(this.tune.ENDLESS ? 0 : this.tune.DURATION_SEC);
    if (this.autoplay && ctx.params?.modifier?.type === 'turbo') {
      console.log(`[veggieChop] turbo speedMult=${this.tune.SPEED_MULT} scoreMult=${this.tune.SCORE_MULT}`);
    }
  },

  /** Take (or build) a model holder for an item key. */
  takeModel(key) {
    const free = this.pool.get(key);
    if (free && free.length > 0) return free.pop();
    if (key === 'boot') {
      // procedural junk boot (same recipe family as fishingPond's)
      const holder = new THREE.Group();
      const shaftGeo = new THREE.BoxGeometry(0.26, 0.44, 0.18);
      const footGeo = new THREE.BoxGeometry(0.44, 0.2, 0.18);
      this.ownedGeos.push(shaftGeo, footGeo);
      const shaft = new THREE.Mesh(shaftGeo, this.bootMat);
      shaft.position.set(-0.07, 0.13, 0);
      const foot = new THREE.Mesh(footGeo, this.bootMat);
      foot.position.set(0.08, -0.16, 0);
      holder.add(shaft, foot);
      return holder;
    }
    const size = key.endsWith('-half') || key.endsWith('-slice') ? HALF_SIZE : ITEM_SIZE;
    return fitModel(this.ctx.assets.getModel(`food-kit/${key}`), size);
  },

  returnModel(key, holder) {
    holder.visible = false;
    this.ctx.scene.remove(holder);
    if (!this.pool.has(key)) this.pool.set(key, []);
    this.pool.get(key).push(holder);
  },

  /** Lob a wave of 1–3 items (§C1.2), planning the bot swipes at apex. */
  spawnWave(elapsed, { size: forcedSize = null, veggieOnly = false, quiet = false } = {}) {
    const { rng } = this.ctx;
    const size = forcedSize ?? waveSizeAt(rng, elapsed);
    for (let i = 0; i < size; i += 1) {
      const roll = veggieOnly ? rollVeggie(rng) : rollItem(rng, elapsed, this.tune);
      const arc = makeArc(rng, this.halfW, this.launchY);
      const holder = this.takeModel(roll.key);
      holder.position.set(arc.x0, arc.y0, 0);
      holder.visible = true;
      this.ctx.scene.add(holder);
      const apex = arcApex(arc);
      const item = {
        id: (this.itemSeq += 1),
        kind: roll.kind,
        key: roll.key,
        half: roll.half,
        juice: roll.juice,
        arc,
        t: -i * 0.14, // stagger the wave slightly
        holder,
        prevX: arc.x0,
        prevY: arc.y0,
        spinX: (rng() - 0.5) * 3.2,
        spinZ: (rng() - 0.5) * 2.2,
        active: true,
        // dev bot plan (§C1.2: swipe at apex, ignore junk; human-ish skips)
        botAt: (
          (roll.kind === 'veggie' && rng() < this.tune.AUTOPLAY_CHOP_RATE)
          || (roll.kind === 'junk' && this.tune.ENDLESS && rng() < this.tune.ENDLESS_BOT_JUNK_RATE)
        )
          ? apex.t + (rng() - 0.5) * 0.12
          : -1,
      };
      this.items.push(item);
    }
    if (!quiet) this.ctx.audio.play('chop.lob');
  },

  /** Start one 8-veggie / 3-second no-junk frenzy (§C10.2). */
  startFrenzy() {
    this.frenzy = { remaining: CHOP.FRENZY_ITEMS, spawnT: 0 };
    this.spawnT = Math.max(this.spawnT, CHOP.FRENZY_DURATION_SEC);
    this.ctx.hud.banner(t('mg.chop.frenzy'));
    if (this.autoplay) {
      console.log(`[veggieChop] frenzy ${this.frenzyCount} — ${CHOP.FRENZY_ITEMS} veggies/${CHOP.FRENZY_DURATION_SEC}s, junk 0`);
    }
    this.ctx.audio.play('combo.up');
    this.gooby.play('happyBounce');
    // V4/GAME-POLISH-2 juice: Gooby rides the frenzy hype
    this.gooby.setEmotion('ecstatic');
    this.emotionT = CHOP.FRENZY_DURATION_SEC;
    // V6/C4 juice (§C.6 #2): the frenzy ENTERS instead of state-flipping —
    // confetti burst + float at the arena + a golden backdrop pulse (flash ⇒
    // reduced-motion gated; the banner + combo.up still carry it).
    this.particles.emit('confetti', new THREE.Vector3(0, 1.1, 0.5), { count: CHOP_JUICE6.FRENZY_CONFETTI });
    this.floats.spawn(tx('v6.juice.frenzy'), new THREE.Vector3(0, 0.4, 0.5), '#D69A28');
    if (!prefersReducedMotion()) {
      this.bgTween?.cancel();
      this.bgTween = tween({
        from: 0, to: 1, duration: CHOP_JUICE6.FRENZY_TINT_SEC, ease: easings.linear,
        onUpdate: (v) => {
          const bg = this.ctx?.scene?.background;
          if (bg?.isColor) bg.copy(_BG_BASE).lerp(_BG_GOLD, Math.sin(v * Math.PI));
        },
        onComplete: () => { this.bgTween = null; },
      });
    }
  },

  /** Add a point to the swipe-trail ribbon. */
  pushTrail(x, y) {
    this.trail.push({ x, y, age: 0 });
    if (this.trail.length > TRAIL_MAX) this.trail.shift();
  },

  /** Rebuild the trail ribbon mesh from the aged point list. */
  updateTrail(dt) {
    for (const p of this.trail) p.age += dt;
    while (this.trail.length > 0 && this.trail[0].age > TRAIL_LIFE) this.trail.shift();
    const pts = this.trail;
    const pos = this.trailGeo.attributes.position;
    const index = this.trailGeo.index;
    if (pts.length < 2) {
      this.trailGeo.setDrawRange(0, 0);
      return;
    }
    for (let i = 0; i < pts.length; i += 1) {
      const p = pts[i];
      const q = pts[Math.min(pts.length - 1, i + 1)];
      const o = pts[Math.max(0, i - 1)];
      let dx = q.x - o.x;
      let dy = q.y - o.y;
      const len = Math.hypot(dx, dy) || 1;
      dx /= len;
      dy /= len;
      const w = TRAIL_WIDTH * (1 - p.age / TRAIL_LIFE) * (0.35 + 0.65 * (i / pts.length));
      pos.setXYZ(i * 2, p.x - dy * w, p.y + dx * w, 0.5);
      pos.setXYZ(i * 2 + 1, p.x + dy * w, p.y - dx * w, 0.5);
    }
    for (let i = 0; i < pts.length - 1; i += 1) {
      const a = i * 2;
      index.setX(i * 6, a);
      index.setX(i * 6 + 1, a + 1);
      index.setX(i * 6 + 2, a + 2);
      index.setX(i * 6 + 3, a + 1);
      index.setX(i * 6 + 4, a + 3);
      index.setX(i * 6 + 5, a + 2);
    }
    pos.needsUpdate = true;
    index.needsUpdate = true;
    this.trailGeo.setDrawRange(0, (pts.length - 1) * 6);
  },

  /** Test one swipe segment against every airborne item (§C1.2 chop). */
  chopSegment(ax, ay, bx, by) {
    for (const item of this.items) {
      if (!item.active || item.t < 0) continue;
      const p = item.holder.position;
      if (!segmentHitsMovingCircle(
        ax, ay, bx, by,
        item.prevX ?? p.x, item.prevY ?? p.y,
        p.x, p.y,
        this.tune.HIT_RADIUS
      )) continue;
      if (item.kind === 'veggie') this.chopVeggie(item);
      else {
        this.chopJunk(item);
        break; // junk ends the combo/stroke immediately (§C10.2 audit)
      }
    }
  },

  /** A clean chop: split into the two half models + juice, score the combo. */
  chopVeggie(item) {
    const pos = item.holder.position.clone();
    item.active = false;
    this.returnModel(item.key, item.holder);
    this.swipeChops = comboAfterHit(this.swipeChops, 'veggie');
    const pts = chopPoints(this.swipeChops);
    this.score = applyPoints(this.score, pts);
    this.ctx.onScore(pts);
    this.ctx.audio.play('chop.slice');
    this.juice.emit(pos, item.juice, 8, this.ctx.rng);
    this.floats.spawn(`+${pts}`, pos, this.swipeChops > 1 ? '#D6428A' : '#2E8B57');
    if (this.swipeChops === 2) {
      this.ctx.audio.play('chop.combo');
      this.ctx.hud.banner(t('mg.chop.combo'));
      this.gooby.play('happyBounce');
    } else if (this.swipeChops === 3) {
      // V4/GAME-POLISH-2 juice: 3 in one stroke — banner + sparkles + ecstatic
      this.ctx.audio.play('combo.up');
      this.ctx.hud.banner(tx('gp2.chop.triple'));
      this.particles.emit('sparkles', pos, { count: 5 });
      this.gooby.setEmotion('ecstatic');
      this.emotionT = 1.1;
    } else if (this.swipeChops > 3) {
      this.particles.emit('sparkles', pos, { count: 5 });
    }
    // V6/C4 juice (§C.6 #1): a tiny confetti puff rides the tinted spray
    this.particles.emit('confetti', pos, { count: CHOP_JUICE6.CHOP_CONFETTI });
    // the two halves tumble apart under gravity
    const { rng } = this.ctx;
    for (const side of [-1, 1]) {
      const holder = this.takeModel(item.half);
      holder.position.copy(pos);
      holder.visible = true;
      this.ctx.scene.add(holder);
      // V6/C4 juice (§C.6 #1): the halves POP apart (easeOutBack settle to 1
      // — the pooled holder's rest scale) instead of just appearing. The
      // 0.24 s tween finishes long before the ~1 s fall returns the holder
      // to the pool. RM-gated; the tumble physics below are untouched.
      if (!prefersReducedMotion()) {
        holder.scale.setScalar(CHOP_JUICE6.HALF_POP_SCALE);
        tween({
          from: CHOP_JUICE6.HALF_POP_SCALE, to: 1, duration: CHOP_JUICE6.HALF_POP_SEC,
          ease: easings.easeOutBack,
          onUpdate: (s) => holder.scale.setScalar(s),
        });
      }
      this.halves.push({
        key: item.half,
        holder,
        vx: item.arc.vx * 0.4 + side * (1.1 + rng() * 0.7),
        vy: 1.6 + rng() * 1.2,
        spin: side * (3 + rng() * 3),
        age: 0,
      });
    }
  },

  /** Chopped junk (§C1.2): −3, splash stun 0.5 s, grumpy Gooby. */
  chopJunk(item) {
    const pos = item.holder.position.clone();
    item.active = false;
    this.returnModel(item.key, item.holder);
    this.score = applyPoints(this.score, this.tune.JUNK_PTS);
    this.ctx.onScore(this.tune.JUNK_PTS);
    this.ctx.hud.setScore(this.score);
    this.stunT = this.tune.STUN_SEC;
    this.junkHits += 1;
    this.swipeChops = comboAfterHit(this.swipeChops, 'junk');
    this.trail.length = 0;
    this.lastDrag = null;
    this.ctx.audio.play('chop.junk');
    this.juice.emit(pos, '#8A7A5C', 10, this.ctx.rng);
    this.particles.emit('dizzyStars', pos);
    this.floats.spawn(`${this.tune.JUNK_PTS}`, pos, '#D64570');
    // V6/C4 juice (§C.6 #3): 0.2 s camera micro-shake sells the splash —
    // gated behind OS reduced motion (chop.junk + dizzyStars still carry it).
    if (!prefersReducedMotion()) {
      this.shakeTween?.cancel();
      const cam = this.ctx.camera;
      this.shakeTween = tween({
        from: 1, to: 0, duration: CHOP_JUICE6.JUNK_SHAKE_SEC, ease: easings.easeOutQuad,
        onUpdate: (k) => {
          cam.position.x = Math.sin(k * 43) * CHOP_JUICE6.JUNK_SHAKE_AMP * k;
          cam.position.y = Math.cos(k * 31) * CHOP_JUICE6.JUNK_SHAKE_AMP * k;
        },
        onComplete: () => {
          cam.position.x = 0;
          cam.position.y = 0;
          this.shakeTween = null;
        },
      });
    }
    this.ctx.hud.banner(t('mg.chop.junk'));
    this.gooby.setEmotion('dizzy');
    this.gooby.play('dizzy', { speed: 2.0 / this.tune.STUN_SEC });
    this.emotionT = 0.9;
    if (endlessShouldEnd(this.junkHits, this.tune)) this.endRound();
  },

  /** A veggie fell unchopped: miss pip out, 3 misses end early (§C1.2). */
  missVeggie(item) {
    item.active = false;
    this.returnModel(item.key, item.holder);
    this.misses += 1;
    this.ctx.audio.play('chop.miss');
    if (this.missMats[this.misses - 1]) this.missMats[this.misses - 1].color.set('#B9A88F');
    this.gooby.setEmotion('sad');
    this.emotionT = 0.8;
    if (!this.tune.ENDLESS && this.misses >= this.tune.MAX_MISSES) {
      this.ctx.hud.banner(t('mg.chop.over'));
      this.endRound();
    } else {
      this.ctx.hud.banner(t('mg.chop.miss', { n: Math.max(0, this.tune.MAX_MISSES - this.misses) }));
    }
  },

  endRound() {
    if (this.phase !== 'play') return;
    const scored = finalScore(this.score, this.tune);
    const bonus = scored - this.score;
    this.score = scored;
    if (bonus !== 0) this.ctx.onScore(bonus);
    this.ctx.hud.setScore(this.score);
    this.phase = 'ending';
    this.endT = 0;
    this.ctx.audio.play('ui.win');
    this.gooby.setEmotion(this.score >= 50 ? 'ecstatic' : 'happy');
    this.gooby.play('happyBounce');
    this.particles.emit('confetti', this.gooby.group.position.clone().add(new THREE.Vector3(0, 1.2, 0)), { count: 14 });
    if (this.autoplay) console.log(`[veggieChop] autoplay run ended — score ${this.score} (misses ${this.misses})`);
  },

  /** Dev bot: synthesize an apex swipe through a veggie (§C1.2). */
  botSwipe(item) {
    if (this.stunT > 0) return; // splashed — sits the swipe out
    const { rng } = this.ctx;
    const p = item.holder.position;
    const err = (rng() - 0.5) * 2 * CHOP.AUTOPLAY_AIM_ERR;
    const ax = p.x - 0.55 + err;
    const bx = p.x + 0.55 + err;
    const ay = p.y - 0.4 + err * 0.5;
    const by = p.y + 0.42 + err * 0.5;
    this.swipeChops = 0; // each synthetic swipe is its own combo window
    // draw the bot's stroke so autoplay footage shows the trail
    for (let i = 0; i <= 6; i += 1) {
      const k = i / 6;
      this.pushTrail(ax + (bx - ax) * k, ay + (by - ay) * k);
    }
    this.chopSegment(ax, ay, bx, by);
  },

  update(dt, elapsed) {
    const ctx = this.ctx;
    const gdt = dt * this.tune.SPEED_MULT;
    this.gooby.update(gdt);
    this.particles.update(gdt);
    this.floats.update(dt);
    this.juice.update(gdt);
    this.updateTrail(gdt);

    if (this.emotionT > 0) {
      this.emotionT -= dt;
      if (this.emotionT <= 0) this.gooby.setEmotion('happy');
    }

    // loose halves tumble off under gravity
    for (const h of this.halves) {
      h.age += gdt;
      h.vy -= this.tune.GRAVITY * 0.8 * gdt;
      h.holder.position.x += h.vx * gdt;
      h.holder.position.y += h.vy * gdt;
      h.holder.rotation.z += h.spin * gdt;
      if (h.holder.position.y < this.launchY - 0.6) {
        this.returnModel(h.key, h.holder);
        h.done = true;
      }
    }
    this.halves = this.halves.filter((h) => !h.done);

    if (this.phase === 'ending') {
      this.endT += dt;
      if (this.endT >= 1.4 && this.phase !== 'done') {
        this.phase = 'done';
        ctx.onEnd({ score: this.score });
      }
      return;
    }
    if (this.phase !== 'play') return;

    const remaining = this.tune.DURATION_SEC - elapsed;
    ctx.hud.setTime(this.tune.ENDLESS ? elapsed : remaining);
    if (this.autoplay && !this.propLogged && elapsed > 0.5) {
      this.propLogged = true;
      console.log(`[veggieChop] prop kaykit-restaurant/cuttingboard — drawCalls ${ctx.renderer.info.render.calls}`);
    }
    if (this.stunT > 0) this.stunT -= dt;

    // V3/G45 frenzy every 25 s: exactly 8 veggies across 3 s, never junk.
    const reachedFrenzies = frenzyCountAt(elapsed);
    if (reachedFrenzies > this.frenzyCount && remaining > CHOP.FRENZY_DURATION_SEC) {
      this.frenzyCount = reachedFrenzies;
      this.startFrenzy();
    }
    if (this.frenzy) {
      this.frenzy.spawnT -= gdt;
      const cadence = frenzySpawnInterval();
      while (this.frenzy.spawnT <= 0 && this.frenzy.remaining > 0) {
        this.spawnWave(elapsed, { size: 1, veggieOnly: true, quiet: true });
        this.frenzy.remaining -= 1;
        this.frenzy.spawnT += cadence;
      }
      if (this.frenzy.remaining <= 0) {
        this.frenzy = null;
        this.ctx.audio.play('chop.lob');
      }
    } else {
      // normal wave cadence (§C1.2: arcs of 1–3, ramping)
      this.spawnT -= gdt;
      if (this.spawnT <= 0 && remaining > 1.2) {
        this.spawnWave(elapsed);
        this.spawnT = spawnIntervalAt(elapsed, this.tune.DURATION_SEC, this.tune);
      }
    }

    // flying items along their arcs
    for (const item of this.items) {
      if (!item.active) continue;
      item.t += gdt;
      if (item.t < 0) continue; // wave stagger
      const p = arcPos(item.arc, item.t, this.tune.GRAVITY);
      item.prevX = item.holder.position.x;
      item.prevY = item.holder.position.y;
      item.holder.position.set(p.x, p.y, 0);
      item.holder.rotation.x += item.spinX * gdt;
      item.holder.rotation.z += item.spinZ * gdt;
      if (this.autoplay && item.botAt >= 0 && item.t >= item.botAt) {
        item.botAt = -1;
        this.botSwipe(item);
        if (this.phase !== 'play') break;
        if (!item.active) continue;
      }
      // fell past the launch line on the way down
      if (item.t > item.arc.vy / this.tune.GRAVITY && p.y < this.launchY - 0.3) {
        if (item.kind === 'veggie') {
          this.missVeggie(item);
          if (this.phase !== 'play') break;
        } else {
          item.active = false;
          this.returnModel(item.key, item.holder);
        }
      }
    }
    this.items = this.items.filter((i) => i.active);

    if (!this.tune.ENDLESS && remaining <= 0) this.endRound();
  },

  dispose() {
    this.offStart?.();
    this.offDrag?.();
    this.offEnd?.();
    // V6/C4 juice teardown: settle the camera + stop the backdrop pulse
    if (this.shakeTween) {
      this.shakeTween.cancel();
      this.shakeTween = null;
      this.ctx?.camera?.position.set(0, 0, 10);
    }
    this.bgTween?.cancel();
    this.bgTween = null;
    this.floats?.dispose();
    this.juice?.dispose();
    this.particles?.dispose();
    this.gooby?.dispose();
    for (const geo of this.ownedGeos ?? []) geo.dispose();
    for (const mat of this.ownedMats ?? []) mat.dispose();
    for (const tex of this.ownedTexs ?? []) tex.dispose();
    // GLB clones share cached geometries/materials — the framework scene
    // sweep handles GPU frees; drop references only.
    this.items = [];
    this.halves = [];
    this.pool = null;
    this.trail = [];
    this.trailGeo = null;
    this.trailMat = null;
    this.trailMesh = null;
    this.missMats = [];
    this.bootMat = null;
    this.board = null;
    this.frenzy = null;
    this.ctx = null;
    this.gooby = null;
    this.particles = null;
    this.floats = null;
    this.juice = null;
    this.ownedGeos = [];
    this.ownedMats = [];
    this.ownedTexs = [];
    this.tune = null;
  },
};
export const controls = Object.freeze({ invertible: false }); // V4/G57 (§G2.1 rule 4, §G3.3): positional/tap/semantic input — inverting is nonsense here
