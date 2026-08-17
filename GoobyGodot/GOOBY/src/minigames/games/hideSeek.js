// Hide & Seek — „Guck-guck-Garten" (PLAN5 §V5.2, agent V5/G06): cozy
// observation play. Critters hide behind a 3×4 garden grid (bushes, crates,
// flower pots) and periodically peek out; tap the right spot to find them.
// Clearing a whole wave before its timer pays a bonus. Pure rules live in
// hideSeek.logic.js (§B rule). Found critters stay sitting on their spot
// until the wave clears — the garden slowly fills with friends.
//
// Dev-only ?autoplay=1: a bot taps mostly-correct spots (with human-ish
// misses) for headless verification of the §V5.2 ~14c typical payout.

import * as THREE from 'three';
import { t } from '../../data/strings.js';
import { tween, easings } from '../../gfx/tween.js';
import { createParticles } from '../../gfx/particles.js';
import { createGooby } from '../../character/gooby.js';
import { applyEquippedOutfits } from '../../character/outfitAttach.js';
import { clampFloatTextToView } from '../framework.js';
import {
  SEEK,
  applyDifficulty,
  spotCount,
  waveSecFor,
  rollHiders,
  applyScore,
  endlessShouldEnd,
} from './hideSeek.logic.js';

/** Pastel critter fur colors (one per hider, cycled). */
const CRITTER_COLORS = [0xffa9c8, 0x7fd4c1, 0xffd97a, 0xb9a9ff, 0xffb08a];

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

/** @type {object} §E8 plugin */
export default {
  id: 'hideSeek',
  assetKeys: [],
  /** V3/G32 §B2.3: warm the recorded cues used every few seconds. */
  sfx: ['hop.bell', 'jingle.short', 'ui.win', 'ui.tap'],

  /** @param {object} ctx §E8 game context */
  init(ctx) {
    this.ctx = ctx;
    this.tune = applyDifficulty(SEEK, ctx.params?.difficulty ?? 'normal');
    this.autoplay =
      import.meta.env?.DEV && new URLSearchParams(location.search).get('autoplay') === '1';

    this.phase = 'play'; // 'play' | 'serve' | 'ending' | 'done'
    this.score = 0;
    this.wave = 0;
    this.expired = 0;
    this.waveT = 0;
    this.waveSec = 1;
    this.serveT = 0;
    this.autoT = 1.0;
    this.emotionT = 0;
    this.elapsed = 0;
    /** @type {Set<number>} spot indices still hiding a critter */
    this.hidden = new Set();
    /** @type {Map<number, object>} spotIdx → critter rig (this wave) */
    this.critters = new Map();

    const camera = ctx.camera;
    camera.position.set(0, 0, 10);
    camera.lookAt(0, 0, 0);
    this.halfH = Math.tan(THREE.MathUtils.degToRad(camera.fov / 2)) * 10;
    this.halfW = this.halfH * (innerWidth / innerHeight);

    const scene = ctx.scene;
    scene.background = new THREE.Color('#D7EFC9'); // fresh meadow morning

    /** @type {THREE.BufferGeometry[]} */
    this.ownedGeos = [];
    /** @type {THREE.Material[]} */
    this.ownedMats = [];
    const own = (mesh) => {
      this.ownedGeos.push(mesh.geometry);
      this.ownedMats.push(mesh.material);
      return mesh;
    };

    scene.add(new THREE.HemisphereLight(0xfff8ee, 0xa8d59a, 1.15));
    const dir = new THREE.DirectionalLight(0xfff2dd, 0.8);
    dir.position.set(3, 5, 5);
    scene.add(dir);

    // --- backdrop: sky band + sun + clouds ---
    const sky = own(new THREE.Mesh(
      new THREE.PlaneGeometry(this.halfW * 2 + 2, 2.4),
      new THREE.MeshBasicMaterial({ color: 0xbfe6f5 })
    ));
    sky.position.set(0, this.halfH - 1.1, -3);
    scene.add(sky);
    const sun = own(new THREE.Mesh(
      new THREE.CircleGeometry(0.7, 32),
      new THREE.MeshBasicMaterial({ color: 0xffd166 })
    ));
    sun.position.set(-this.halfW + 1.0, this.halfH - 1.0, -2.8);
    scene.add(sun);
    const cloudMat = new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.8 });
    const cloudGeo = new THREE.CircleGeometry(0.4, 20);
    this.ownedMats.push(cloudMat);
    this.ownedGeos.push(cloudGeo);
    for (const [x, y, s] of [[0.6, this.halfH - 0.8, 1.2], [1.9, this.halfH - 1.3, 0.9]]) {
      const cloud = new THREE.Mesh(cloudGeo, cloudMat);
      cloud.position.set(x, y, -2.7);
      cloud.scale.set(s * 1.6, s, 1);
      scene.add(cloud);
    }

    // --- wave timer bar (under the sky band) ---
    this.timerMat = new THREE.MeshBasicMaterial({ color: 0x59c9b9 });
    this.ownedMats.push(this.timerMat);
    this.timerBar = new THREE.Mesh(new THREE.PlaneGeometry(this.halfW * 1.6, 0.12), this.timerMat);
    this.ownedGeos.push(this.timerBar.geometry);
    this.timerBar.position.set(0, this.halfH - 2.3, 2); // in front of the spots
    scene.add(this.timerBar);

    // --- particles / floats / Gooby cameo (bottom LEFT — the pause button
    // owns the bottom-right corner) ---
    this.particles = createParticles(scene);
    this.floats = createFloatTexts(scene, ctx.camera);
    this.gooby = createGooby({ particles: this.particles });
    applyEquippedOutfits(this.gooby);
    this.gooby.group.scale.setScalar(0.6);
    this.gooby.group.position.set(-this.halfW + 0.8, -this.halfH + 0.42, 1.2);
    this.gooby.setEmotion('happy');
    scene.add(this.gooby.group);

    // --- the hiding-spot grid (3 × 4, three cozy spot styles) ---
    this.raycaster = new THREE.Raycaster();
    this.hitMat = new THREE.MeshBasicMaterial({
      transparent: true, opacity: 0, depthWrite: false, colorWrite: false,
    });
    this.ownedMats.push(this.hitMat);
    const hitGeo = new THREE.SphereGeometry(0.85, 12, 10);
    this.ownedGeos.push(hitGeo);
    /** @type {Array<{grp: THREE.Group, hit: THREE.Mesh, top: number, shakeT: number}>} */
    this.spots = [];
    const cols = this.tune.COLS;
    const rows = this.tune.ROWS;
    const gridTop = this.halfH - 2.9;
    const gridBottom = -this.halfH + 1.5;
    for (let i = 0; i < spotCount(this.tune); i += 1) {
      const col = i % cols;
      const row = Math.floor(i / cols);
      const x = -this.halfW + 1.15 + (col / (cols - 1)) * (this.halfW * 2 - 2.3);
      const y = gridTop - (row / (rows - 1)) * (gridTop - gridBottom);
      const grp = new THREE.Group();
      grp.position.set(x, y, row * 0.05); // lower rows render slightly in front
      const style = i % 3;
      if (style === 0) this.buildBush(grp, own);
      else if (style === 1) this.buildCrate(grp, own);
      else this.buildPot(grp, own);
      const hit = new THREE.Mesh(hitGeo, this.hitMat);
      hit.userData.spot = i;
      grp.add(hit);
      scene.add(grp);
      this.spots.push({ grp, hit, top: 0.55, shakeT: 0 });
    }

    // --- critter pool (pastel bunnies, one per possible hider) ---
    /** @type {object[]} */
    this.critterPool = [];
    for (let i = 0; i < this.tune.WAVE_HIDERS_MAX; i += 1) {
      this.critterPool.push(this.buildCritter(CRITTER_COLORS[i % CRITTER_COLORS.length]));
    }

    // --- input: tap a spot to peek behind it ---
    this.onPointerDown = (e) => {
      if (this.phase !== 'play' || this.autoplay) return;
      const ndc = new THREE.Vector2(
        (e.clientX / innerWidth) * 2 - 1,
        -(e.clientY / innerHeight) * 2 + 1
      );
      this.raycaster.setFromCamera(ndc, this.ctx.camera);
      const hits = this.raycaster.intersectObjects(this.spots.map((s) => s.hit), false);
      if (hits.length > 0) this.tapSpot(hits[0].object.userData.spot);
    };
    ctx.renderer.domElement.addEventListener('pointerdown', this.onPointerDown);

    this.startWave(0);
    ctx.hud.setScore(0);
    ctx.hud.setTime(this.tune.ENDLESS ? 0 : this.tune.DURATION_SEC);
  },

  /** Bush: two flattened spheres + tiny flowers. */
  buildBush(grp, own) {
    const big = own(new THREE.Mesh(
      new THREE.SphereGeometry(0.62, 18, 14),
      new THREE.MeshStandardMaterial({ color: 0x69b45e, roughness: 0.85 })
    ));
    big.scale.set(1.15, 0.8, 0.9);
    grp.add(big);
    const small = own(new THREE.Mesh(
      new THREE.SphereGeometry(0.4, 16, 12),
      new THREE.MeshStandardMaterial({ color: 0x83c977, roughness: 0.85 })
    ));
    small.position.set(0.4, 0.22, 0.15);
    small.scale.set(1, 0.75, 0.9);
    grp.add(small);
    const flowerGeo = new THREE.SphereGeometry(0.06, 8, 6);
    this.ownedGeos.push(flowerGeo);
    for (const [fx, fy, c] of [[-0.35, 0.3, 0xff9bbd], [0.15, 0.44, 0xffd166], [0.55, 0.1, 0xfff4e4]]) {
      const mat = new THREE.MeshBasicMaterial({ color: c });
      this.ownedMats.push(mat);
      const flower = new THREE.Mesh(flowerGeo, mat);
      flower.position.set(fx, fy, 0.5);
      grp.add(flower);
    }
  },

  /** Crate: warm wooden box with a lighter lid. */
  buildCrate(grp, own) {
    const box = own(new THREE.Mesh(
      new THREE.BoxGeometry(1.05, 0.85, 0.8),
      new THREE.MeshStandardMaterial({ color: 0xc89b6c, roughness: 0.8 })
    ));
    box.position.y = -0.05;
    grp.add(box);
    const lid = own(new THREE.Mesh(
      new THREE.BoxGeometry(1.15, 0.14, 0.9),
      new THREE.MeshStandardMaterial({ color: 0xe0b98a, roughness: 0.75 })
    ));
    lid.position.y = 0.44;
    grp.add(lid);
  },

  /** Flower pot with a leafy plant crown. */
  buildPot(grp, own) {
    const pot = own(new THREE.Mesh(
      new THREE.CylinderGeometry(0.42, 0.3, 0.62, 16),
      new THREE.MeshStandardMaterial({ color: 0xd98868, roughness: 0.75 })
    ));
    pot.position.y = -0.2;
    grp.add(pot);
    const crown = own(new THREE.Mesh(
      new THREE.SphereGeometry(0.42, 14, 10),
      new THREE.MeshStandardMaterial({ color: 0x74c26a, roughness: 0.85 })
    ));
    crown.position.y = 0.3;
    crown.scale.set(1.1, 0.85, 1);
    grp.add(crown);
  },

  /** Pastel bunny critter rig (procedural, pooled across waves). */
  buildCritter(color) {
    const grp = new THREE.Group();
    const furMat = new THREE.MeshStandardMaterial({ color, roughness: 0.7 });
    this.ownedMats.push(furMat);
    const body = new THREE.Mesh(new THREE.SphereGeometry(0.26, 16, 12), furMat);
    this.ownedGeos.push(body.geometry);
    body.scale.y = 1.1;
    grp.add(body);
    const earGeo = new THREE.CapsuleGeometry(0.06, 0.24, 4, 8);
    this.ownedGeos.push(earGeo);
    for (const sx of [-1, 1]) {
      const ear = new THREE.Mesh(earGeo, furMat);
      ear.position.set(sx * 0.11, 0.38, 0);
      ear.rotation.z = -sx * 0.18;
      grp.add(ear);
    }
    const eyeGeo = new THREE.SphereGeometry(0.035, 8, 6);
    const eyeMat = new THREE.MeshBasicMaterial({ color: 0x30263d });
    this.ownedGeos.push(eyeGeo);
    this.ownedMats.push(eyeMat);
    for (const sx of [-1, 1]) {
      const eye = new THREE.Mesh(eyeGeo, eyeMat);
      eye.position.set(sx * 0.1, 0.12, 0.22);
      grp.add(eye);
    }
    const nose = new THREE.Mesh(eyeGeo, new THREE.MeshBasicMaterial({ color: 0xff7ba9 }));
    this.ownedMats.push(nose.material);
    nose.position.set(0, 0.04, 0.25);
    nose.scale.setScalar(0.8);
    grp.add(nose);
    grp.visible = false;
    this.ctx.scene.add(grp);
    return { grp, peekT: 0, nextPeekAt: 0, found: false, spot: -1 };
  },

  /** Start (or restart after expiry) the given 0-based wave. */
  startWave(wave) {
    this.wave = wave;
    this.waveSec = waveSecFor(wave, this.tune);
    this.waveT = 0;
    this.hidden.clear();
    this.critters.clear();
    const spotsIdx = rollHiders(this.ctx.rng, wave, this.tune);
    for (let i = 0; i < spotsIdx.length; i += 1) {
      const spot = spotsIdx[i];
      const critter = this.critterPool[i];
      const spotRig = this.spots[spot];
      critter.found = false;
      critter.spot = spot;
      critter.peekT = 0;
      critter.nextPeekAt = this.elapsed + 0.6 + this.ctx.rng() * this.tune.PEEK_EVERY_SEC;
      critter.grp.visible = false;
      critter.grp.position.set(spotRig.grp.position.x, spotRig.grp.position.y - 0.15, spotRig.grp.position.z - 0.3);
      critter.grp.scale.setScalar(1);
      this.hidden.add(spot);
      this.critters.set(spot, critter);
    }
    if (wave > 0) {
      this.ctx.hud.banner(t('mg.seek.waveNew', { n: spotsIdx.length }));
    }
  },

  /** Tap on a hiding spot (§V5.2 rules). */
  tapSpot(spot) {
    if (this.phase !== 'play') return;
    const rig = this.spots[spot];
    rig.shakeT = 0.35;
    const pos = rig.grp.position.clone().add(new THREE.Vector3(0, 0.6, 0.6));
    if (this.hidden.has(spot)) {
      const critter = this.critters.get(spot);
      this.hidden.delete(spot);
      critter.found = true;
      // pop up on top of the spot and stay there, cheering
      critter.grp.visible = true;
      const topY = rig.grp.position.y + rig.top;
      const grp = critter.grp;
      tween({
        from: rig.grp.position.y - 0.15, to: topY + 0.25, duration: 0.3, ease: easings.easeOutBack,
        onUpdate: (v) => { grp.position.y = v; },
      });
      grp.position.z = rig.grp.position.z + 0.35;
      const prev = this.score;
      this.score = applyScore(this.score, this.tune.FIND_PTS);
      if (this.score !== prev) this.ctx.onScore(this.score - prev);
      this.ctx.audio.play('hop.bell');
      this.ctx.audio.play('gooby.giggle');
      this.particles.emit('hearts', pos, { count: 4 });
      this.particles.emit('sparkles', pos, { count: 6 });
      this.floats.spawn(`+${this.tune.FIND_PTS} ${t('mg.seek.found')}`, pos, '#2E8B57');
      this.reactGooby('ecstatic', 'happyBounce');
      if (this.hidden.size === 0) this.clearWave();
    } else {
      this.ctx.audio.play('ui.tap');
      this.particles.emit('bubbles', pos, { count: 3 });
      this.floats.spawn(t('mg.seek.empty'), pos, '#8A7FA8');
    }
  },

  /** All hiders found before the timer — bonus + fresh wave. */
  clearWave() {
    const prev = this.score;
    this.score = applyScore(this.score, this.tune.WAVE_BONUS);
    if (this.score !== prev) this.ctx.onScore(this.score - prev);
    this.ctx.audio.play('jingle.short');
    this.ctx.hud.banner(t('mg.seek.waveClear', { n: this.tune.WAVE_BONUS }));
    const center = new THREE.Vector3(0, 0, 1);
    this.particles.emit('confetti', center, { count: 12 });
    // found critters hop away (scale out), then the next wave hides
    for (const critter of this.critters.values()) {
      const grp = critter.grp;
      tween({
        from: 1, to: 0.01, duration: 0.4, ease: easings.easeInCubic,
        onUpdate: (v) => grp.scale.setScalar(v),
        onComplete: () => { grp.visible = false; },
      });
    }
    this.phase = 'serve';
    this.serveT = this.tune.SERVE_SEC;
  },

  /** Wave timer expired — the critters re-hide (Endlos counts strikes). */
  expireWave() {
    this.expired += 1;
    this.ctx.audio.play('gooby.sigh');
    this.ctx.hud.banner(t('mg.seek.expired'));
    this.reactGooby('sad', 'refuse');
    for (const critter of this.critters.values()) critter.grp.visible = false;
    if (this.tune.ENDLESS && endlessShouldEnd(this.expired, this.tune)) {
      this.finishRound();
      return;
    }
    this.phase = 'serve';
    this.serveT = this.tune.SERVE_SEC;
  },

  finishRound() {
    if (this.phase === 'ending' || this.phase === 'done') return;
    this.phase = 'ending';
    this.serveT = 1.3;
    this.ctx.audio.play('ui.win');
    this.gooby.setEmotion('ecstatic');
    this.gooby.play('happyBounce');
    this.particles.emit('confetti', this.gooby.group.position.clone().add(new THREE.Vector3(0, 1.0, 0)), { count: 16 });
  },

  /** Brief Gooby reaction. */
  reactGooby(emotion, clip) {
    this.gooby.setEmotion(emotion);
    this.emotionT = 1.1;
    if (!this.gooby.isPlaying(clip)) this.gooby.play(clip);
  },

  /** Dev autoplay: seek mostly-correct spots with human-ish misses. */
  autoplayTick(dt) {
    this.autoT -= dt;
    if (this.autoT > 0 || this.phase !== 'play') return;
    const { rng } = this.ctx;
    this.autoT = this.tune.AUTOPLAY_TAP_SEC * (0.85 + rng() * 0.3);
    const hiddenSpots = [...this.hidden];
    if (hiddenSpots.length === 0) return;
    if (rng() < this.tune.AUTOPLAY_FIND_RATE) {
      this.tapSpot(hiddenSpots[Math.floor(rng() * hiddenSpots.length)]);
    } else {
      const empty = this.spots.map((_, i) => i).filter((i) => !this.hidden.has(i));
      if (empty.length > 0) this.tapSpot(empty[Math.floor(rng() * empty.length)]);
    }
  },

  update(dt, elapsed) {
    const ctx = this.ctx;
    this.elapsed = elapsed;
    this.gooby.update(dt);
    this.particles.update(dt);
    this.floats.update(dt);

    if (this.emotionT > 0) {
      this.emotionT -= dt;
      if (this.emotionT <= 0) this.gooby.setEmotion('happy');
    }

    // spot shake + idle sway
    for (let i = 0; i < this.spots.length; i += 1) {
      const rig = this.spots[i];
      if (rig.shakeT > 0) {
        rig.shakeT -= dt;
        rig.grp.rotation.z = Math.sin(rig.shakeT * 36) * 0.12 * Math.max(0, rig.shakeT / 0.35);
      } else {
        rig.grp.rotation.z = Math.sin(elapsed * 1.1 + i * 1.7) * 0.015;
      }
    }

    if (this.phase === 'ending') {
      this.serveT -= dt;
      if (this.serveT <= 0 && this.phase !== 'done') {
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
        console.log(`[hideSeek] autoplay run ended — score ${this.score}, waves ${this.wave + 1}, expired ${this.expired}`);
      }
      return;
    }

    if (this.phase === 'serve') {
      this.serveT -= dt;
      if (this.serveT <= 0) {
        this.phase = 'play';
        this.startWave(this.wave + 1);
      }
      return;
    }

    // wave timer + bar (teal → coral as it runs out)
    this.waveT += dt;
    const frac = Math.max(0, 1 - this.waveT / this.waveSec);
    this.timerBar.scale.x = Math.max(0.001, frac);
    this.timerMat.color.setHex(frac < 0.3 ? 0xf58c6e : 0x59c9b9);
    if (this.waveT >= this.waveSec) {
      this.expireWave();
      return;
    }

    if (this.autoplay) this.autoplayTick(dt);

    // peek scheduling: hidden critters pop up briefly above their spot
    for (const critter of this.critters.values()) {
      if (critter.found || !this.hidden.has(critter.spot)) continue;
      const rig = this.spots[critter.spot];
      if (critter.peekT > 0) {
        critter.peekT -= dt;
        const k = Math.sin(Math.PI * Math.max(0, 1 - critter.peekT / this.tune.PEEK_DURATION_SEC));
        critter.grp.visible = true;
        critter.grp.position.y = rig.grp.position.y + 0.1 + k * (rig.top - 0.05);
        if (critter.peekT <= 0) {
          critter.grp.visible = false;
          critter.nextPeekAt = elapsed + this.tune.PEEK_EVERY_SEC * (0.75 + this.ctx.rng() * 0.5);
        }
      } else if (elapsed >= critter.nextPeekAt) {
        critter.peekT = this.tune.PEEK_DURATION_SEC;
        this.ctx.audio.play('says.pad1');
      }
    }
  },

  dispose() {
    this.ctx?.renderer?.domElement?.removeEventListener('pointerdown', this.onPointerDown);
    this.floats?.dispose();
    this.particles?.dispose();
    this.gooby?.dispose();
    for (const geo of this.ownedGeos ?? []) geo.dispose();
    for (const mat of this.ownedMats ?? []) mat.dispose();
    this.ownedGeos = [];
    this.ownedMats = [];
    this.spots = [];
    this.critterPool = [];
    this.critters = null;
    this.hidden = null;
    this.timerBar = null;
    this.timerMat = null;
    this.raycaster = null;
    this.tune = null;
    this.gooby = null;
    this.particles = null;
    this.floats = null;
    this.ctx = null;
  },
};
export const controls = Object.freeze({ invertible: false }); // V5/G06 (§G2.1 rule 4): positional tap input — inverting is nonsense here
