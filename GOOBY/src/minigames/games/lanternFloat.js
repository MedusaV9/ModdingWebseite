// Star Lantern — „Sternenlaterne" (PLAN5 §3 / PLAN6 Wave C/C1, agent V6/C1):
// a chill night flight over the garden. Gooby releases a warm paper lantern
// from the garden hill; it auto-rises through the starry sky while a
// horizontal drag steers it through silver star rings (+2, every 5th golden
// +5), past curious fireflies (+1), telegraphed wind gusts that shove it
// sideways and soft cloud bumps (timed −3 · Endlos: the 3rd bump ends the
// run). Pure rules live in lanternFloat.logic.js (§B rule). Distinct look:
// deep indigo night dome, moonlit hills with village lights, one glowing
// lantern — starHopper starfield technique + teaParty float-text recipe.
//
// Dev-only ?autoplay=1: a ring-chasing bot (dodges clouds) for headless
// verification. Dev-only ?lanternskip=N: offsets the round clock N seconds
// (screenshot/results probing).

import * as THREE from 'three';
import { t, getLang } from '../../data/strings.js';
import { tween, easings } from '../../gfx/tween.js';
import { createParticles } from '../../gfx/particles.js';
import { createGooby } from '../../character/gooby.js';
import { applyEquippedOutfits } from '../../character/outfitAttach.js';
import { clampFloatTextToView } from '../framework.js';
import { prefersReducedMotion } from '../../ui/ui.js';
import {
  LANTERN,
  applyDifficulty,
  steerTargetFrom,
  clampLanternX,
  ringSpacingAt,
  rollRing,
  ringHit,
  gustPhaseAt,
  rollCloud,
  cloudHit,
  applyScore,
  endlessShouldEnd,
} from './lanternFloat.logic.js';

// V6/C1 (§E0.1-11 same-wave i18n): local fallback until C3's v6-games.js is
// spread into strings.js — t() wins the moment it lands (dormant after).
const LFX_EN = {
  'mg.lantern.hint': 'Drag to steer · fly through the rings',
  'mg.lantern.launch': 'Fly, little lantern!',
  'mg.lantern.gold': 'Golden ring!',
  'mg.lantern.gust': 'Wind gust!',
  'mg.lantern.bump': 'Cloud bump!',
  'mg.lantern.bumps': 'Bump {n}/{max}',
};
const LFX_DE = {
  'mg.lantern.hint': 'Ziehen zum Lenken · flieg durch die Ringe',
  'mg.lantern.launch': 'Flieg, kleine Laterne!',
  'mg.lantern.gold': 'Goldener Ring!',
  'mg.lantern.gust': 'Windböe!',
  'mg.lantern.bump': 'Wolken-Rempler!',
  'mg.lantern.bumps': 'Rempler {n}/{max}',
};
function tx(key, vars) {
  const global = t(key, vars);
  if (global !== key) return global;
  let text = (getLang() === 'de' ? LFX_DE : LFX_EN)[key] ?? key;
  if (vars) {
    for (const [name, value] of Object.entries(vars)) {
      text = text.replaceAll(`{${name}}`, String(value));
    }
  }
  return text;
}

/** View-only look tuning (world layout, pools, launch cameo beats). */
const LOOK = Object.freeze({
  /** Lantern flight height (field wu). */
  LANTERN_Y: -1.35,
  /** Rings materialize this far above the visible field edge (field wu). */
  SPAWN_MARGIN: 2.6,
  /** The first ring reaches the lantern after ~this long (s). */
  FIRST_RING_LEAD_SEC: 3.2,
  /** Pool sizes (cover a portrait viewport's full runway at min spacing). */
  RING_POOL: 8,
  FIREFLY_POOL: 6,
  CLOUD_POOL: 4,
  /** Launch cameo: lantern rise time + garden slide-away delay/time (s). */
  LAUNCH_RISE_SEC: 2.0,
  GARDEN_LEAVE_DELAY: 1.4,
  GARDEN_LEAVE_SEC: 1.6,
  /** End-of-round beat before onEnd (s). */
  ENDING_SEC: 1.5,
});

// ---------------------------------------------------------- canvas textures

/** Night dome: indigo gradient, baked stars, moonlit hills + village lights. */
function makeNightTexture() {
  const canvas = document.createElement('canvas');
  canvas.width = 256;
  canvas.height = 512;
  const g = canvas.getContext('2d');
  const grad = g.createLinearGradient(0, 0, 0, 512);
  grad.addColorStop(0, '#060A1E');
  grad.addColorStop(0.45, '#0E1533');
  grad.addColorStop(0.78, '#20264F');
  grad.addColorStop(1, '#3A3560');
  g.fillStyle = grad;
  g.fillRect(0, 0, 256, 512);
  // warm dusk afterglow hugging the horizon
  const dusk = g.createLinearGradient(0, 400, 0, 512);
  dusk.addColorStop(0, 'rgba(255,150,90,0)');
  dusk.addColorStop(1, 'rgba(255,150,90,0.16)');
  g.fillStyle = dusk;
  g.fillRect(0, 400, 256, 112);
  // baked far stars (upper sky)
  for (let i = 0; i < 130; i += 1) {
    g.fillStyle = `rgba(255,255,255,${0.12 + Math.random() * 0.4})`;
    const s = Math.random() < 0.12 ? 2 : 1;
    g.fillRect(Math.random() * 256, Math.random() * 360, s, s);
  }
  // distant garden hills (two soft silhouettes)
  g.fillStyle = '#0C1626';
  g.beginPath();
  g.moveTo(0, 512);
  g.quadraticCurveTo(70, 428, 160, 470);
  g.quadraticCurveTo(215, 494, 256, 480);
  g.lineTo(256, 512);
  g.closePath();
  g.fill();
  g.fillStyle = '#081020';
  g.beginPath();
  g.moveTo(0, 512);
  g.quadraticCurveTo(90, 466, 190, 500);
  g.lineTo(256, 496);
  g.lineTo(256, 512);
  g.closePath();
  g.fill();
  // tiny warm village windows on the hills
  for (const [x, y] of [[38, 476], [92, 470], [150, 484], [205, 494], [232, 488]]) {
    g.fillStyle = 'rgba(255,193,119,0.9)';
    g.fillRect(x, y, 2, 2);
    g.fillStyle = 'rgba(255,193,119,0.25)';
    g.fillRect(x - 1, y - 1, 4, 4);
  }
  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

/** Soft radial glow sprite texture (G42 recipe). */
function makeGlowTexture(inner, outer = 'rgba(0,0,0,0)') {
  const canvas = document.createElement('canvas');
  canvas.width = 64;
  canvas.height = 64;
  const g = canvas.getContext('2d');
  const grad = g.createRadialGradient(32, 32, 2, 32, 32, 30);
  grad.addColorStop(0, inner);
  grad.addColorStop(1, outer);
  g.fillStyle = grad;
  g.fillRect(0, 0, 64, 64);
  return new THREE.CanvasTexture(canvas);
}

/** Star ring: glowing circle with tiny 4-point stars riding the rim. */
function makeRingTexture(gold) {
  const canvas = document.createElement('canvas');
  canvas.width = 256;
  canvas.height = 256;
  const g = canvas.getContext('2d');
  const core = gold ? '#FFDF9A' : '#DCE8FF';
  const glow = gold ? 'rgba(255,183,77,0.9)' : 'rgba(150,190,255,0.85)';
  // faint dreamy haze inside the ring
  const haze = g.createRadialGradient(128, 128, 20, 128, 128, 92);
  haze.addColorStop(0, gold ? 'rgba(255,215,130,0.10)' : 'rgba(170,200,255,0.08)');
  haze.addColorStop(0.8, gold ? 'rgba(255,200,110,0.16)' : 'rgba(150,190,255,0.12)');
  haze.addColorStop(1, 'rgba(0,0,0,0)');
  g.fillStyle = haze;
  g.fillRect(0, 0, 256, 256);
  g.shadowColor = glow;
  g.shadowBlur = 26;
  g.strokeStyle = glow;
  g.lineWidth = 13;
  g.beginPath();
  g.arc(128, 128, 92, 0, Math.PI * 2);
  g.stroke();
  g.shadowBlur = 12;
  g.strokeStyle = core;
  g.lineWidth = 5;
  g.beginPath();
  g.arc(128, 128, 92, 0, Math.PI * 2);
  g.stroke();
  // little stars around the rim (a golden ring gets a denser crown)
  const n = gold ? 10 : 7;
  for (let i = 0; i < n; i += 1) {
    const a = (i / n) * Math.PI * 2;
    const x = 128 + Math.cos(a) * 92;
    const y = 128 + Math.sin(a) * 92;
    const r = i % 2 === 0 ? 10 : 6;
    g.fillStyle = i % 2 === 0 ? '#FFFDF2' : core;
    g.beginPath();
    for (let k = 0; k < 8; k += 1) {
      const rr = k % 2 === 0 ? r : r * 0.38;
      const aa = (k / 8) * Math.PI * 2 - Math.PI / 2;
      const px = x + Math.cos(aa) * rr;
      const py = y + Math.sin(aa) * rr;
      if (k === 0) g.moveTo(px, py);
      else g.lineTo(px, py);
    }
    g.closePath();
    g.fill();
  }
  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

/** Puffy moonlit night cloud (soft overlapping blobs). */
function makeCloudTexture() {
  const canvas = document.createElement('canvas');
  canvas.width = 256;
  canvas.height = 128;
  const g = canvas.getContext('2d');
  const blob = (x, y, r, a) => {
    const grad = g.createRadialGradient(x, y, 1, x, y, r);
    grad.addColorStop(0, `rgba(226,233,255,${a})`);
    grad.addColorStop(0.65, `rgba(196,208,242,${a * 0.75})`);
    grad.addColorStop(1, 'rgba(196,208,242,0)');
    g.fillStyle = grad;
    g.fillRect(0, 0, 256, 128);
  };
  blob(78, 78, 52, 0.95);
  blob(128, 60, 58, 0.98);
  blob(178, 80, 50, 0.92);
  blob(110, 92, 44, 0.85);
  blob(152, 94, 42, 0.85);
  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

/** Firefly: bright warm-chartreuse core in a soft halo. */
function makeFireflyTexture() {
  const canvas = document.createElement('canvas');
  canvas.width = 64;
  canvas.height = 64;
  const g = canvas.getContext('2d');
  const grad = g.createRadialGradient(32, 32, 1, 32, 32, 30);
  grad.addColorStop(0, '#FFFDE8');
  grad.addColorStop(0.25, '#EDFA9E');
  grad.addColorStop(0.55, 'rgba(196,232,90,0.5)');
  grad.addColorStop(1, 'rgba(196,232,90,0)');
  g.fillStyle = grad;
  g.fillRect(0, 0, 64, 64);
  return new THREE.CanvasTexture(canvas);
}

/** Warm rice-paper lantern skin with rib lines. */
function makeLanternTexture() {
  const canvas = document.createElement('canvas');
  canvas.width = 128;
  canvas.height = 128;
  const g = canvas.getContext('2d');
  const grad = g.createLinearGradient(0, 0, 0, 128);
  grad.addColorStop(0, '#FFCE7E');
  grad.addColorStop(0.45, '#FFB65C');
  grad.addColorStop(1, '#F2913D');
  g.fillStyle = grad;
  g.fillRect(0, 0, 128, 128);
  // vertical paper ribs
  g.strokeStyle = 'rgba(178,94,32,0.5)';
  g.lineWidth = 2;
  for (let i = 0; i <= 8; i += 1) {
    const x = (i / 8) * 128;
    g.beginPath();
    g.moveTo(x, 0);
    g.lineTo(x, 128);
    g.stroke();
  }
  // inner-flame hot spot low in the belly
  const hot = g.createRadialGradient(64, 88, 2, 64, 88, 54);
  hot.addColorStop(0, 'rgba(255,246,214,0.9)');
  hot.addColorStop(1, 'rgba(255,246,214,0)');
  g.fillStyle = hot;
  g.fillRect(0, 0, 128, 128);
  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  return tex;
}

/** Tiny floating score text (canvas sprites, self-disposing) — G8 recipe. */
function createFloatTexts(scene, camera) {
  const active = new Set();
  return {
    spawn(text, pos, color = '#FFF4D9') {
      const canvas = document.createElement('canvas');
      canvas.width = 240;
      canvas.height = 80;
      const g = canvas.getContext('2d');
      g.font = '900 38px system-ui, sans-serif';
      g.textAlign = 'center';
      g.textBaseline = 'middle';
      g.lineWidth = 8;
      g.strokeStyle = 'rgba(8,12,36,0.92)';
      g.strokeText(text, 120, 40);
      g.fillStyle = color;
      g.fillText(text, 120, 40);
      const tex = new THREE.CanvasTexture(canvas);
      const mat = new THREE.SpriteMaterial({ map: tex, transparent: true, depthWrite: false });
      const sprite = new THREE.Sprite(mat);
      sprite.position.copy(clampFloatTextToView(pos.clone(), camera, { halfW: 0.75, halfH: 0.25 }));
      sprite.scale.set(1.5, 0.5, 1);
      scene.add(sprite);
      active.add({ sprite, mat, tex, age: 0, life: 0.95 });
    },
    update(dt) {
      for (const f of active) {
        f.age += dt;
        f.sprite.position.y += dt * 1.05;
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

/** @type {object} §E8 plugin */
export default {
  id: 'lanternFloat',
  assetKeys: [],
  /** V3/G32 §B2.3: warm the recorded cues used every few seconds. */
  sfx: ['hopper.star', 'hopper.gold', 'garden.harvestReady', 'rocket.wind', 'crash.soft', 'combo.up'],

  /** @param {object} ctx §E8 game context */
  init(ctx) {
    this.ctx = ctx;
    this.tune = applyDifficulty(LANTERN, ctx.params?.difficulty ?? 'normal');
    const q = import.meta.env?.DEV ? new URLSearchParams(location.search) : null;
    this.autoplay = q?.get('autoplay') === '1';
    /** Dev screenshot seam: pretend N seconds already played. */
    this.skipOffset = Math.max(0, Number(q?.get('lanternskip') ?? 0) || 0);

    this.phase = 'play'; // 'play' | 'ending' | 'done'
    this.score = 0;
    this.streak = 0;
    this.bumps = 0;
    this.hitsTotal = 0;
    this.fireflyCount = 0;
    this.invulnT = 0;
    this.ringIndex = 0;
    this.steerX = null; // manual steer target (field wu), null = coast
    this.lanternX = 0;
    this.vx = 0;
    this.lastGustKey = ''; // `${index}:${phase}` edge detector
    this.gustDir = 0;
    this.leafT = 0;
    this.launchT = LOOK.LAUNCH_RISE_SEC;
    this.endT = 0;
    this.elapsed = this.skipOffset;
    this.botAimX = 0;
    this.botRing = -1;
    this.reduceMotion = prefersReducedMotion();
    /** @type {Array<{cancel: () => void}>} juice tweens (cancelled on dispose) */
    this.fxTweens = [];
    /** Pre-allocated scratch (no per-frame allocations in update). */
    this._v3 = new THREE.Vector3();

    const camera = ctx.camera;
    camera.position.set(0, 0, 10);
    camera.lookAt(0, 0, 0);
    this.halfH = Math.tan(THREE.MathUtils.degToRad(camera.fov / 2)) * 10;
    this.halfW = this.halfH * (innerWidth / innerHeight);

    const scene = ctx.scene;
    scene.background = new THREE.Color('#060A1E');

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

    scene.add(new THREE.HemisphereLight(0xaec2ff, 0x1b2340, 0.75));
    const moonlight = new THREE.DirectionalLight(0xcfe0ff, 0.55);
    moonlight.position.set(-3, 6, 5);
    scene.add(moonlight);

    // --- backdrop (screen space): night dome, moon, two starfield layers ---
    // The camera sits at z=10 — a plane at depth z spans (10 − z)/10 of the
    // z=0 frustum, so every backdrop layer is sized at ITS depth (a z=−6
    // dome cut to z=0 extents leaves hard edges on wide viewports).
    const atDepth = (z) => (10 - z) / 10;
    this.nightTex = makeNightTexture();
    this.ownedTexs.push(this.nightTex);
    const domeScale = atDepth(-6);
    const dome = own(new THREE.Mesh(
      new THREE.PlaneGeometry(this.halfW * 2 * domeScale + 0.8, this.halfH * 2 * domeScale + 0.8),
      new THREE.MeshBasicMaterial({ map: this.nightTex, depthWrite: false })
    ));
    dome.position.set(0, 0, -6);
    scene.add(dome);

    const moonScale = atDepth(-5.5);
    // V6/FIX4 (P2-22): the SAME cratered cream moon as the garden dome
    // (gfx/sky.js §C10.2 — disc #F4EFD9 + the crater trio) — the old bare
    // CircleGeometry color disc read featureless next to it.
    const moonCanvas = document.createElement('canvas');
    moonCanvas.width = 128;
    moonCanvas.height = 128;
    const mg = moonCanvas.getContext('2d');
    const mr = 62;
    mg.fillStyle = '#F4EFD9';
    mg.beginPath();
    mg.arc(64, 64, mr, 0, Math.PI * 2);
    mg.fill();
    mg.fillStyle = 'rgba(160,160,190,0.35)';
    for (const [dx, dy, rr] of [[-0.3, -0.15, 0.22], [0.25, 0.3, 0.16], [0.05, -0.4, 0.12]]) {
      mg.beginPath();
      mg.arc(64 + dx * mr, 64 + dy * mr, rr * mr, 0, Math.PI * 2);
      mg.fill();
    }
    this.moonTex = new THREE.CanvasTexture(moonCanvas);
    this.ownedTexs.push(this.moonTex);
    const moon = own(new THREE.Mesh(
      new THREE.PlaneGeometry(0.8 * moonScale, 0.8 * moonScale),
      new THREE.MeshBasicMaterial({ map: this.moonTex, transparent: true, depthWrite: false })
    ));
    moon.position.set((-this.halfW + 0.72) * moonScale, (this.halfH - 1.05) * moonScale, -5.5);
    scene.add(moon);
    this.moonGlowTex = makeGlowTexture('rgba(244,238,218,0.85)');
    this.ownedTexs.push(this.moonGlowTex);
    this.moonGlowMat = new THREE.SpriteMaterial({
      map: this.moonGlowTex, transparent: true, opacity: 0.55, depthWrite: false,
    });
    this.ownedMats.push(this.moonGlowMat);
    const moonGlow = new THREE.Sprite(this.moonGlowMat);
    moonGlow.position.copy(moon.position);
    moonGlow.position.z = -5.6;
    moonGlow.scale.setScalar(2.6 * moonScale);
    scene.add(moonGlow);

    /** Star wrap extents at the starfield depth (z=−4). */
    this.starHalfW = this.halfW * atDepth(-4) + 1;
    this.starHalfH = this.halfH * atDepth(-4) + 1;
    /** @type {Array<{points: THREE.Points, speed: number, arr: Float32Array}>} */
    this.starLayers = [];
    for (const [count, size, speedMul, color] of [
      [90, 0.045, 0.22, '#9FB6E8'],
      [55, 0.08, 0.45, '#FFF6DE'],
    ]) {
      const arr = new Float32Array(count * 3);
      for (let i = 0; i < count; i += 1) {
        arr[i * 3] = (Math.random() * 2 - 1) * this.starHalfW;
        arr[i * 3 + 1] = (Math.random() * 2 - 1) * this.starHalfH;
        arr[i * 3 + 2] = -4;
      }
      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.BufferAttribute(arr, 3));
      const mat = new THREE.PointsMaterial({ color, size, transparent: true, opacity: 0.85, depthWrite: false });
      const points = new THREE.Points(geo, mat);
      this.ownedGeos.push(geo);
      this.ownedMats.push(mat);
      scene.add(points);
      this.starLayers.push({ points, speed: speedMul, arr });
    }

    // --- scaled playfield (fits the §C1 3.1-wu half-width on any aspect) ---
    this.fieldScale = Math.min(1, (this.halfW - 0.3) / (this.tune.HALF_W + 0.72));
    this.field = new THREE.Group();
    this.field.scale.setScalar(this.fieldScale);
    scene.add(this.field);
    this.spawnY = this.halfH / this.fieldScale + LOOK.SPAWN_MARGIN;
    /** Field y where the next ring materializes (walks down with the world). */
    this.nextRingY = LOOK.LANTERN_Y + LOOK.FIRST_RING_LEAD_SEC * this.tune.RISE_SPEED;

    // --- star ring pool (canvas plane + glow sprite each — 2 draw calls) ---
    this.ringTexSilver = makeRingTexture(false);
    this.ringTexGold = makeRingTexture(true);
    this.ownedTexs.push(this.ringTexSilver, this.ringTexGold);
    this.ringGlowTexGold = makeGlowTexture('rgba(255,183,77,0.75)');
    this.ringGlowTexSilver = makeGlowTexture('rgba(140,180,255,0.5)');
    this.ownedTexs.push(this.ringGlowTexGold, this.ringGlowTexSilver);
    const ringGeo = new THREE.PlaneGeometry(1.9, 1.9);
    this.ownedGeos.push(ringGeo);
    /** @type {Array<object>} pooled ring slots */
    this.rings = [];
    for (let i = 0; i < LOOK.RING_POOL; i += 1) {
      const mat = new THREE.MeshBasicMaterial({
        map: this.ringTexSilver, transparent: true, depthWrite: false,
      });
      this.ownedMats.push(mat);
      const mesh = new THREE.Mesh(ringGeo, mat);
      const glowMat = new THREE.SpriteMaterial({
        map: this.ringGlowTexSilver, transparent: true, opacity: 0.5, depthWrite: false,
      });
      this.ownedMats.push(glowMat);
      const glow = new THREE.Sprite(glowMat);
      glow.scale.setScalar(2.6);
      glow.position.z = -0.15;
      const group = new THREE.Group();
      group.add(glow);
      group.add(mesh);
      group.visible = false;
      this.field.add(group);
      this.rings.push({
        group, mesh, mat, glowMat, active: false, counted: false,
        x: 0, gold: false, points: 0, spin: i % 2 === 0 ? 0.35 : -0.3, pulse: i * 0.9,
      });
    }

    // --- firefly pool (one glowing sprite each) ---
    this.fireflyTex = makeFireflyTexture();
    this.ownedTexs.push(this.fireflyTex);
    /** @type {Array<object>} */
    this.fireflies = [];
    for (let i = 0; i < LOOK.FIREFLY_POOL; i += 1) {
      const mat = new THREE.SpriteMaterial({ map: this.fireflyTex, transparent: true, depthWrite: false });
      this.ownedMats.push(mat);
      const sprite = new THREE.Sprite(mat);
      sprite.scale.setScalar(0.66);
      sprite.visible = false;
      this.field.add(sprite);
      this.fireflies.push({ sprite, mat, active: false, counted: false, baseX: 0, phase: i * 1.7 });
    }

    // --- cloud pool (one puffy sprite each) ---
    this.cloudTex = makeCloudTexture();
    this.ownedTexs.push(this.cloudTex);
    /** @type {Array<object>} */
    this.clouds = [];
    for (let i = 0; i < LOOK.CLOUD_POOL; i += 1) {
      const mat = new THREE.SpriteMaterial({
        map: this.cloudTex, transparent: true, opacity: 0.96, depthWrite: false,
      });
      this.ownedMats.push(mat);
      const sprite = new THREE.Sprite(mat);
      sprite.scale.set(2.3, 1.15, 1);
      sprite.visible = false;
      this.field.add(sprite);
      this.clouds.push({ sprite, mat, active: false, bumped: false, x: 0, sway: i * 2.3 });
    }

    // --- the lantern (lathe paper body, warm glow, tassel, flame light) ---
    this.lantern = new THREE.Group();
    this.field.add(this.lantern);
    this.lanternTex = makeLanternTexture();
    this.ownedTexs.push(this.lanternTex);
    const profile = [
      new THREE.Vector2(0.16, -0.5),
      new THREE.Vector2(0.35, -0.36),
      new THREE.Vector2(0.45, -0.08),
      new THREE.Vector2(0.45, 0.14),
      new THREE.Vector2(0.34, 0.38),
      new THREE.Vector2(0.17, 0.5),
    ];
    this.lanternMat = new THREE.MeshStandardMaterial({
      map: this.lanternTex, emissive: 0xff9a3d, emissiveIntensity: 0.62,
      emissiveMap: this.lanternTex, roughness: 0.65,
    });
    this.ownedMats.push(this.lanternMat);
    const body = new THREE.Mesh(new THREE.LatheGeometry(profile, 20), this.lanternMat);
    this.ownedGeos.push(body.geometry);
    this.lantern.add(body);
    const capMat = new THREE.MeshStandardMaterial({ color: 0x7a4a2b, roughness: 0.7 });
    this.ownedMats.push(capMat);
    const capTop = new THREE.Mesh(new THREE.CylinderGeometry(0.2, 0.17, 0.08, 14), capMat);
    this.ownedGeos.push(capTop.geometry);
    capTop.position.y = 0.53;
    this.lantern.add(capTop);
    const capBot = new THREE.Mesh(new THREE.CylinderGeometry(0.17, 0.19, 0.07, 14), capMat);
    this.ownedGeos.push(capBot.geometry);
    capBot.position.y = -0.53;
    this.lantern.add(capBot);
    this.tassel = new THREE.Mesh(new THREE.CylinderGeometry(0.016, 0.016, 0.36, 6), capMat);
    this.ownedGeos.push(this.tassel.geometry);
    this.tassel.position.y = -0.74;
    this.lantern.add(this.tassel);
    const knot = new THREE.Mesh(new THREE.SphereGeometry(0.05, 10, 8), capMat);
    this.ownedGeos.push(knot.geometry);
    knot.position.y = -0.94;
    this.lantern.add(knot);
    this.lanternGlowTex = makeGlowTexture('rgba(255,182,92,0.9)', 'rgba(255,140,60,0)');
    this.ownedTexs.push(this.lanternGlowTex);
    this.lanternGlowMat = new THREE.SpriteMaterial({
      map: this.lanternGlowTex, transparent: true, opacity: 0.8,
      blending: THREE.AdditiveBlending, depthWrite: false,
    });
    this.ownedMats.push(this.lanternGlowMat);
    const lanternGlow = new THREE.Sprite(this.lanternGlowMat);
    lanternGlow.scale.setScalar(2.7);
    this.lantern.add(lanternGlow);
    this.flame = new THREE.PointLight(0xffb65c, 2.0, 8, 1.6);
    this.lantern.add(this.flame);

    // --- launch cameo: garden hill + Gooby releasing the lantern (root) ---
    this.particles = createParticles(scene);
    this.floats = createFloatTexts(scene, ctx.camera);
    this.garden = new THREE.Group();
    this.gardenY0 = -this.halfH + 0.35;
    this.garden.position.set(0, this.gardenY0, 1.2);
    scene.add(this.garden);
    const hill = own(new THREE.Mesh(
      new THREE.CircleGeometry(this.halfW + 1.6, 40),
      new THREE.MeshStandardMaterial({ color: 0x14281e, roughness: 0.95 })
    ));
    hill.scale.y = 0.34;
    hill.position.y = -this.halfW * 0.28;
    this.garden.add(hill);
    const bushMat = new THREE.MeshStandardMaterial({ color: 0x0e1d16, roughness: 0.95 });
    this.ownedMats.push(bushMat);
    for (const [bx, bs] of [[-1.35, 0.5], [1.5, 0.42]]) {
      const bush = new THREE.Mesh(new THREE.CircleGeometry(1, 22), bushMat);
      this.ownedGeos.push(bush.geometry);
      bush.scale.set(bs, bs * 0.7, 1);
      bush.position.set(bx, 0.32, -0.2);
      this.garden.add(bush);
    }
    this.gooby = createGooby({ particles: this.particles });
    applyEquippedOutfits(this.gooby);
    this.gooby.group.scale.setScalar(0.6);
    this.gooby.group.position.set(-0.45, 0.4, 0.3);
    this.gooby.setEmotion('happy');
    this.gooby.play('wave');
    this.garden.add(this.gooby.group);

    // lantern starts in Gooby's hands (garden space → field space), rises up
    const startX = (this.garden.position.x - 0.05) / this.fieldScale;
    const startY = (this.gardenY0 + 1.15) / this.fieldScale;
    this.lantern.position.set(startX, startY, 0);
    this.lanternX = 0;
    this.fxTweens.push(tween({
      from: startY, to: LOOK.LANTERN_Y, duration: LOOK.LAUNCH_RISE_SEC, ease: easings.easeOutCubic,
      onUpdate: (v) => { if (this.lantern) this.lantern.position.y = v; },
    }));
    this.fxTweens.push(tween({
      from: startX, to: 0, duration: LOOK.LAUNCH_RISE_SEC * 0.8, ease: easings.easeOutQuad,
      onUpdate: (v) => { if (this.phase === 'play' && this.steerX == null && !this.autoplay) this.lanternX = v; },
    }));
    // the garden drifts away below once the lantern is airborne
    this.gardenTween = tween({
      from: this.gardenY0, to: this.gardenY0 - 4.6,
      delay: LOOK.GARDEN_LEAVE_DELAY, duration: LOOK.GARDEN_LEAVE_SEC, ease: easings.easeInCubic,
      onUpdate: (v) => { if (this.garden) this.garden.position.y = v; },
      onComplete: () => { if (this.garden && this.phase === 'play') this.garden.visible = false; },
    });
    this.ctx.audio.play('jingle.short');
    ctx.hud.banner(tx('mg.lantern.launch'));

    // --- input: ONE §G3.1-c boundary — the framework's §G3.3 invert proxy
    // negates p.nx upstream, steerTargetFrom maps it into field x. Camera
    // looks down −z from +z, so world +x IS screen right (no chirality flip;
    // harborHopper's chase cam needs one, this front cam does not).
    this.offDrag = ctx.input.on('drag', (p) => {
      if (this.autoplay || this.phase !== 'play') return;
      this.steerX = steerTargetFrom(p.nx, this.tune);
    });
    this.offDragEnd = ctx.input.on('dragend', () => {
      this.steerX = null; // release: the lantern coasts on its momentum
    });

    ctx.hud.setScore(0);
    ctx.hud.setTime(this.tune.ENDLESS ? this.skipOffset : this.tune.DURATION_SEC - this.skipOffset);
    if (import.meta.env?.DEV) window.__lanternFloat = this;
  },

  /** Apply a score delta through the pure floor rule + framework HUD. */
  syncScore(delta) {
    const prev = this.score;
    this.score = applyScore(this.score, delta);
    if (this.score !== prev) this.ctx.onScore(this.score - prev);
  },

  /** Spawn the next ring row (ring + its gap's cloud/firefly slots). */
  spawnRow(y) {
    const tune = this.tune;
    const ring = rollRing(this.ctx.rng, this.ringIndex, tune);
    const spacing = ringSpacingAt(this.elapsed, tune);
    const slot = this.rings.find((r) => !r.active);
    if (slot) {
      slot.active = true;
      slot.counted = false;
      slot.x = ring.x;
      slot.gold = ring.gold;
      slot.points = ring.points;
      slot.mat.map = ring.gold ? this.ringTexGold : this.ringTexSilver;
      slot.mat.opacity = 1;
      slot.glowMat.map = ring.gold ? this.ringGlowTexGold : this.ringGlowTexSilver;
      slot.glowMat.opacity = ring.gold ? 0.85 : 0.45;
      slot.group.visible = true;
      slot.group.position.set(ring.x, y, -0.3);
      slot.group.scale.setScalar(ring.gold ? 1.16 : 1);
      slot.mesh.rotation.z = 0;
    }
    // gap slots above this ring (arrive between ring i and ring i+1)
    const cloud = rollCloud(this.ctx.rng, this.ringIndex, tune);
    if (cloud.present) {
      const cSlot = this.clouds.find((c) => !c.active);
      if (cSlot) {
        cSlot.active = true;
        cSlot.bumped = false;
        cSlot.x = cloud.x;
        cSlot.mat.opacity = 0.96;
        cSlot.sprite.visible = true;
        cSlot.sprite.position.set(cloud.x, y + spacing * 0.55, 0.25);
        cSlot.sprite.scale.set(2.3, 1.15, 1);
      }
    }
    if (this.ctx.rng() < tune.FIREFLY_CHANCE) {
      let fx = (this.ctx.rng() * 2 - 1) * (tune.HALF_W - tune.RING_MARGIN);
      if (cloud.present && Math.abs(fx - cloud.x) < 1.15) {
        fx = clampLanternX(cloud.x + (fx >= cloud.x ? 1.45 : -1.45), tune);
      }
      const fSlot = this.fireflies.find((f) => !f.active);
      if (fSlot) {
        fSlot.active = true;
        fSlot.counted = false;
        fSlot.baseX = fx;
        fSlot.mat.opacity = 1;
        fSlot.sprite.visible = true;
        fSlot.sprite.position.set(fx, y + spacing * 0.3, 0.1);
      }
    }
    this.ringIndex += 1;
  },

  /** Dev bot: chase the next ring center, sidestep clouds on the way. */
  botTargetX() {
    const tune = this.tune;
    let next = null;
    for (const r of this.rings) {
      if (!r.active || r.counted || r.group.position.y <= LOOK.LANTERN_Y) continue;
      if (next == null || r.group.position.y < next.group.position.y) next = r;
    }
    if (next == null) return this.lanternX;
    if (this.botRing !== next.x + next.group.position.y) {
      this.botRing = next.x + next.group.position.y;
      this.botAimX = (this.ctx.rng() * 2 - 1) * 0.2;
    }
    let aim = next.x + this.botAimX;
    for (const c of this.clouds) {
      if (!c.active || c.bumped) continue;
      const cy = c.sprite.position.y;
      if (cy <= LOOK.LANTERN_Y || cy > LOOK.LANTERN_Y + 2.4) continue;
      if (Math.abs(aim - c.x) < tune.CLOUD_HALF_W + 0.4) {
        aim = c.x + (next.x >= c.x ? 1 : -1) * (tune.CLOUD_HALF_W + 0.55);
      }
    }
    return clampLanternX(aim, tune);
  },

  /** A ring crossed the lantern line — score or let it drift by. */
  rateRing(slot) {
    slot.counted = true;
    const tune = this.tune;
    this._v3.set(this.lanternX, LOOK.LANTERN_Y + 0.6, 0.6).multiplyScalar(this.fieldScale);
    if (ringHit(this.lanternX, slot, tune)) {
      this.streak += 1;
      this.hitsTotal += 1;
      this.syncScore(slot.points);
      if (slot.gold) {
        this.ctx.audio.play('hopper.gold');
        this.ctx.hud.banner(tx('mg.lantern.gold'));
        this.floats.spawn(`+${slot.points}`, this._v3, '#FFD98A');
        this.particles.emit('confetti', this._v3, { count: this.reduceMotion ? 5 : 12 });
      } else {
        this.ctx.audio.play('hopper.star');
        this.floats.spawn(`+${slot.points}`, this._v3, '#CFE0FF');
      }
      this.particles.emit('sparkles', this._v3, { count: this.reduceMotion ? 3 : slot.gold ? 10 : 6 });
      if (this.streak > 0 && this.streak % 5 === 0) this.ctx.audio.play('combo.up');
      // pop: the ring swells and dissolves into the night
      const g = slot.group;
      const from = g.scale.x;
      this.fxTweens.push(tween({
        from, to: from * 1.45, duration: 0.32, ease: easings.easeOutCubic,
        onUpdate: (v, k) => {
          g.scale.setScalar(v);
          slot.mat.opacity = 1 - k;
          slot.glowMat.opacity = (slot.gold ? 0.85 : 0.45) * (1 - k);
        },
        onComplete: () => {
          slot.active = false;
          g.visible = false;
        },
      }));
    } else {
      this.streak = 0;
      slot.mat.opacity = 0.32;
      slot.glowMat.opacity = 0.12;
    }
  },

  /** Soft cloud bump: comfy penalty (timed) / one of three strikes (Endlos). */
  bumpCloud(cloud) {
    cloud.bumped = true;
    this.invulnT = this.tune.BUMP_INVULN_SEC;
    this.streak = 0;
    this.bumps += 1;
    this.ctx.audio.play('crash.soft');
    this.ctx.audio.play('gooby.gasp');
    this._v3.set(this.lanternX, LOOK.LANTERN_Y + 0.5, 0.7).multiplyScalar(this.fieldScale);
    this.floats.spawn(tx('mg.lantern.bump'), this._v3, '#FF9BB0');
    this.particles.emit('dizzyStars', this._v3, { count: this.reduceMotion ? 3 : 5 });
    // the puff shivers, the lantern wobbles (skipped under reduced motion)
    const sprite = cloud.sprite;
    this.fxTweens.push(tween({
      from: 1, to: 1.22, duration: 0.3, ease: easings.easeOutBack,
      onUpdate: (v) => sprite.scale.set(2.3 * v, 1.15 * v, 1),
    }));
    if (!this.reduceMotion) {
      const rot = this.lantern.rotation;
      this.fxTweens.push(tween({
        from: 0, to: 1, duration: 0.55,
        onUpdate: (v, k) => { rot.z += Math.sin(k * Math.PI * 4) * 0.09 * (1 - k); },
      }));
    }
    if (this.tune.ENDLESS) {
      this.ctx.hud.banner(tx('mg.lantern.bumps', { n: this.bumps, max: this.tune.ENDLESS_MAX_BUMPS }));
      if (endlessShouldEnd(this.bumps, this.tune)) this.finishRound();
    } else {
      this.syncScore(-this.tune.BUMP_PENALTY);
    }
  },

  finishRound() {
    if (this.phase === 'ending' || this.phase === 'done') return;
    this.phase = 'ending';
    this.endT = LOOK.ENDING_SEC;
    this.steerX = null;
    this.ctx.audio.play('ui.win');
    // Gooby's hill glides back up to greet the returning lantern
    this.gardenTween?.cancel();
    this.garden.visible = true;
    const fromY = this.garden.position.y;
    this.fxTweens.push(tween({
      from: fromY, to: this.gardenY0, duration: 0.7, ease: easings.easeOutCubic,
      onUpdate: (v) => { if (this.garden) this.garden.position.y = v; },
    }));
    this.gooby.setEmotion('ecstatic');
    this.gooby.play('happyBounce');
    this._v3.set(this.garden.position.x, this.gardenY0 + 1.4, 1.3);
    this.particles.emit('confetti', this._v3, { count: this.reduceMotion ? 8 : 16 });
    if (this.autoplay) {
      console.log(`[lanternFloat] autoplay run ended — score ${this.score}, rings hit ${this.hitsTotal}, `
        + `fireflies ${this.fireflyCount}, bumps ${this.bumps}, draw calls ${this.ctx.renderer.info.render.calls}`);
    }
  },

  update(dt, elapsed) {
    const ctx = this.ctx;
    const tune = this.tune;
    this.elapsed = elapsed + this.skipOffset;
    const played = this.elapsed;
    this.gooby.update(dt);
    this.particles.update(dt);
    this.floats.update(dt);

    // starfield parallax always drifts (even on the ending beat)
    const drop = tune.RISE_SPEED * dt;
    const windX = this.gustDir !== 0 ? this.gustDir : 0;
    for (const layer of this.starLayers) {
      const arr = layer.arr;
      const dy = drop * this.fieldScale * layer.speed;
      const dx = windX * layer.speed * dt * 0.9;
      for (let i = 0; i < arr.length; i += 3) {
        arr[i] += dx;
        if (arr[i] > this.starHalfW) arr[i] -= this.starHalfW * 2;
        if (arr[i] < -this.starHalfW) arr[i] += this.starHalfW * 2;
        arr[i + 1] -= dy;
        if (arr[i + 1] < -this.starHalfH) arr[i + 1] += this.starHalfH * 2;
      }
      layer.points.geometry.attributes.position.needsUpdate = true;
    }

    // lantern glow breathes; flame flickers (deterministic sines, no rng)
    this.lanternGlowMat.opacity = 0.72 + Math.sin(played * 2.6) * 0.1 + Math.sin(played * 7.3) * 0.04;
    this.flame.intensity = 1.9 + Math.sin(played * 9.1) * 0.18 + Math.sin(played * 3.7) * 0.12;

    if (this.phase === 'ending') {
      this.endT -= dt;
      if (this.endT <= 0 && this.phase !== 'done') {
        this.phase = 'done';
        ctx.onEnd({ score: this.score });
      }
      return;
    }
    if (this.phase === 'done') return;

    const remaining = tune.DURATION_SEC - played;
    ctx.hud.setTime(tune.ENDLESS ? played : remaining);
    if (!tune.ENDLESS && remaining <= 0) {
      this.finishRound();
      return;
    }

    // ---- wind gusts: telegraph (leaves drift in) → push (lantern shoved) ----
    const { gust, phase: gustPhase } = gustPhaseAt(played, tune);
    const gustKey = `${gust.index}:${gustPhase}`;
    if (gustKey !== this.lastGustKey) {
      this.lastGustKey = gustKey;
      if (gustPhase === 'telegraph') {
        ctx.hud.banner(tx('mg.lantern.gust'));
        ctx.audio.play('rocket.wind');
      }
    }
    this.gustDir = gustPhase === 'push' ? gust.dir : gustPhase === 'telegraph' ? gust.dir * 0.3 : 0;
    if (gustPhase !== 'idle') {
      this.leafT -= dt;
      if (this.leafT <= 0) {
        this.leafT = this.reduceMotion ? 0.4 : gustPhase === 'push' ? 0.1 : 0.2;
        this._v3.set(
          -gust.dir * (this.halfW - 0.3),
          LOOK.LANTERN_Y * this.fieldScale + (ctx.rng() * 2 - 1) * 2.2,
          0.5
        );
        this.particles.emit('crumbs', this._v3, { count: this.reduceMotion ? 1 : 2 });
      }
    }

    // ---- steering: drag target (or bot), gust push, gentle float easing ----
    const target = this.autoplay ? this.botTargetX() : this.steerX;
    const prevX = this.lanternX;
    if (target != null) {
      this.lanternX += (clampLanternX(target, tune) - this.lanternX) * Math.min(1, dt * 5);
    }
    if (gustPhase === 'push') this.lanternX += gust.dir * tune.GUST_FORCE * dt;
    this.lanternX = clampLanternX(this.lanternX, tune);
    const vNow = dt > 0 ? (this.lanternX - prevX) / dt : 0;
    this.vx += (vNow - this.vx) * Math.min(1, dt * 8);
    this.lantern.position.x = this.lanternX;
    if (this.launchT > 0) this.launchT -= dt;
    else this.lantern.position.y = LOOK.LANTERN_Y + Math.sin(played * 1.7) * 0.09;
    const lean = Math.max(-0.32, Math.min(0.32, -this.vx * 0.12)) + this.gustDir * -0.06;
    this.lantern.rotation.z += (lean - this.lantern.rotation.z) * Math.min(1, dt * 6);
    this.tassel.rotation.z = -this.lantern.rotation.z * 1.5;
    if (this.invulnT > 0) {
      this.invulnT -= dt;
      this.lantern.visible = Math.sin(played * 26) > -0.35;
      if (this.invulnT <= 0) this.lantern.visible = true;
    }

    // ---- world scroll + spawning (rings materialize above the field) ----
    this.nextRingY -= drop;
    while (this.nextRingY <= this.spawnY) {
      this.spawnRow(this.nextRingY);
      this.nextRingY += ringSpacingAt(played, tune);
    }
    const killY = -this.halfH / this.fieldScale - 2.2;

    for (const r of this.rings) {
      if (!r.active) continue;
      r.group.position.y -= drop;
      r.mesh.rotation.z += dt * r.spin;
      if (r.mat.opacity > 0.9) {
        const s = (r.gold ? 1.16 : 1) * (1 + Math.sin(played * 2.8 + r.pulse) * 0.035);
        r.group.scale.setScalar(s);
      }
      if (!r.counted && r.group.position.y <= LOOK.LANTERN_Y) this.rateRing(r);
      if (r.group.position.y < killY) {
        r.active = false;
        r.group.visible = false;
      }
    }

    for (const f of this.fireflies) {
      if (!f.active) continue;
      const s = f.sprite;
      s.position.y -= drop;
      s.position.x = f.baseX + Math.sin(played * 2.1 + f.phase) * 0.42;
      f.mat.opacity = 0.75 + Math.sin(played * 5.3 + f.phase) * 0.25;
      if (!f.counted && s.position.y <= LOOK.LANTERN_Y) {
        f.counted = true;
        if (Math.abs(s.position.x - this.lanternX) <= tune.FIREFLY_RADIUS) {
          this.fireflyCount += 1;
          this.syncScore(tune.FIREFLY_PTS);
          ctx.audio.play('garden.harvestReady');
          this._v3.copy(s.position).multiplyScalar(this.fieldScale);
          this.floats.spawn(`+${tune.FIREFLY_PTS}`, this._v3, '#E4FF9E');
          this.particles.emit('sparkles', this._v3, { count: this.reduceMotion ? 2 : 4 });
          f.active = false;
          s.visible = false;
        }
      }
      if (s.position.y < killY) {
        f.active = false;
        s.visible = false;
      }
    }

    for (const c of this.clouds) {
      if (!c.active) continue;
      const s = c.sprite;
      s.position.y -= drop;
      s.position.x = c.x + Math.sin(played * 0.7 + c.sway) * 0.16;
      if (!c.bumped && this.invulnT <= 0
        && Math.abs(s.position.y - LOOK.LANTERN_Y) < 0.55
        && cloudHit(this.lanternX, c, tune)) {
        this.bumpCloud(c);
        if (this.phase !== 'play') return;
      }
      if (s.position.y < killY) {
        c.active = false;
        s.visible = false;
      }
    }

    // dev heartbeat: prove the ≤100 draw-call budget while the bot flies
    if (this.autoplay && Math.floor(played / 5) !== Math.floor((played - dt) / 5)) {
      console.log(`[lanternFloat] t=${played.toFixed(1)}s score=${this.score} `
        + `drawCalls=${ctx.renderer.info.render.calls}`);
    }
  },

  dispose() {
    this.offDrag?.();
    this.offDragEnd?.();
    for (const tw of this.fxTweens ?? []) tw.cancel();
    this.fxTweens = [];
    this.gardenTween?.cancel();
    this.gardenTween = null;
    this.floats?.dispose();
    this.particles?.dispose();
    this.gooby?.dispose();
    for (const geo of this.ownedGeos ?? []) geo.dispose();
    for (const mat of this.ownedMats ?? []) mat.dispose();
    for (const tex of this.ownedTexs ?? []) tex.dispose();
    this.ownedGeos = [];
    this.ownedMats = [];
    this.ownedTexs = [];
    if (import.meta.env?.DEV && window.__lanternFloat === this) delete window.__lanternFloat;
    this.rings = [];
    this.fireflies = [];
    this.clouds = [];
    this.starLayers = [];
    this.lantern = null;
    this.tassel = null;
    this.flame = null;
    this.garden = null;
    this.field = null;
    this.tune = null;
    this.gooby = null;
    this.particles = null;
    this.floats = null;
    this.ctx = null;
  },
};
export const controls = Object.freeze({ invertible: true }); // V6/C1 (§G2.1 rule 4, §G3.3): analog drag steer — global „Steuerung invertieren" applies
