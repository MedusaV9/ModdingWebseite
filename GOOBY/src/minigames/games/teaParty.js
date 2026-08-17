// Tea Party — „Teestube" (PLAN5 §V5.1, agent V5/G06): hold-to-pour precision.
// A glass teacup slides in with a marked target band; press-and-hold tilts
// the teapot and pours, releasing inside the band scores (perfect +6 /
// good +3), overflowing or under-pouring spills. Every 3rd consecutive
// perfect pays a streak bonus. Pure rules live in teaParty.logic.js (§B
// rule). Gooby watches from the left, cheering perfects and going dizzy on
// spills.
//
// Dev-only ?autoplay=1: a bot pours toward the band center (with human-ish
// release error) for headless verification of the §V5.1 ~17c typical payout.

import * as THREE from 'three';
import { t } from '../../data/strings.js';
import { tween, easings } from '../../gfx/tween.js';
import { createParticles } from '../../gfx/particles.js';
import { createGooby } from '../../character/gooby.js';
import { applyEquippedOutfits } from '../../character/outfitAttach.js';
import { clampFloatTextToView } from '../framework.js';
import { prefersReducedMotion } from '../../ui/ui.js';
import {
  TEA,
  applyDifficulty,
  rollBand,
  fillAfter,
  pourResult,
  streakBonusAt,
  serveIntervalAt,
  applyScore,
  endlessShouldEnd,
} from './teaParty.logic.js';

/** Cup body dimensions at the play plane (wu). */
const CUP = Object.freeze({ R_TOP: 0.78, R_BOT: 0.6, H: 1.5, Y: -1.15 });

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
  id: 'teaParty',
  assetKeys: [],
  /** V3/G32 §B2.3: warm the recorded cues used every few seconds. */
  sfx: ['hop.bell', 'bubble.pop', 'combo.up', 'ui.win', 'jingle.short'],

  /** @param {object} ctx §E8 game context */
  init(ctx) {
    this.ctx = ctx;
    this.tune = applyDifficulty(TEA, ctx.params?.difficulty ?? 'normal');
    this.autoplay =
      import.meta.env?.DEV && new URLSearchParams(location.search).get('autoplay') === '1';

    this.phase = 'serve'; // 'serve' | 'ready' | 'pour' | 'rate' | 'ending' | 'done'
    this.score = 0;
    this.level = 0;
    this.streak = 0;
    this.spills = 0;
    this.cupsServed = 0;
    this.phaseT = 0;
    this.emotionT = 0;
    this.shakeT = 0;
    this.elapsed = 0;
    this.band = null;
    this.pouring = false;
    this.autoTargetLevel = 0;

    const camera = ctx.camera;
    camera.position.set(0, 0, 10);
    camera.lookAt(0, 0, 0);
    this.halfH = Math.tan(THREE.MathUtils.degToRad(camera.fov / 2)) * 10;
    this.halfW = this.halfH * (innerWidth / innerHeight);

    const scene = ctx.scene;
    scene.background = new THREE.Color('#F7E8D4'); // warm tearoom afternoon

    /** @type {THREE.BufferGeometry[]} */
    this.ownedGeos = [];
    /** @type {THREE.Material[]} */
    this.ownedMats = [];
    const own = (mesh) => {
      this.ownedGeos.push(mesh.geometry);
      this.ownedMats.push(mesh.material);
      return mesh;
    };

    scene.add(new THREE.HemisphereLight(0xfff6e8, 0xd9bfa8, 1.1));
    const dir = new THREE.DirectionalLight(0xfff0d8, 0.9);
    dir.position.set(2.5, 5, 6);
    scene.add(dir);

    // --- backdrop: lamp glow + bunting + table ---
    const glow = own(new THREE.Mesh(
      new THREE.CircleGeometry(1.6, 40),
      new THREE.MeshBasicMaterial({ color: 0xffd9a0, transparent: true, opacity: 0.5 })
    ));
    glow.position.set(this.halfW - 1.4, this.halfH - 1.6, -3);
    scene.add(glow);
    const buntingGeo = new THREE.CircleGeometry(0.22, 3);
    this.ownedGeos.push(buntingGeo);
    const buntingColors = [0xff7ba9, 0x59c9b9, 0xffd166, 0x9b8cff];
    for (let i = 0; i < 7; i += 1) {
      const mat = new THREE.MeshBasicMaterial({ color: buntingColors[i % buntingColors.length] });
      this.ownedMats.push(mat);
      const flag = new THREE.Mesh(buntingGeo, mat);
      const x = -this.halfW + ((i + 0.5) / 7) * this.halfW * 2;
      flag.position.set(x, this.halfH - 0.65 - Math.sin((i / 6) * Math.PI) * 0.35, -2.5);
      flag.rotation.z = Math.PI; // point down
      scene.add(flag);
    }
    const table = own(new THREE.Mesh(
      new THREE.CylinderGeometry(this.halfW + 1.2, this.halfW + 1.2, 0.5, 36),
      new THREE.MeshStandardMaterial({ color: 0xc98a5b, roughness: 0.8 })
    ));
    table.position.set(0, CUP.Y - CUP.H / 2 - 0.32, -0.6);
    table.scale.z = 0.55;
    scene.add(table);
    const doily = own(new THREE.Mesh(
      new THREE.CircleGeometry(1.15, 40),
      new THREE.MeshBasicMaterial({ color: 0xfff4e4 })
    ));
    doily.position.set(0, CUP.Y - CUP.H / 2 - 0.16, -0.35);
    doily.rotation.x = -Math.PI / 2.6;
    doily.scale.y = 0.32;
    scene.add(doily);

    // --- Gooby (left, sitting ON the table so it visibly watches the pours) ---
    this.particles = createParticles(scene);
    this.floats = createFloatTexts(scene, ctx.camera);
    this.gooby = createGooby({ particles: this.particles });
    applyEquippedOutfits(this.gooby);
    this.gooby.group.scale.setScalar(0.62);
    this.gooby.group.position.set(-this.halfW + 0.8, CUP.Y - CUP.H / 2 - 0.12, 0.4);
    this.gooby.setEmotion('happy');
    scene.add(this.gooby.group);

    // --- glass cup (fill level visible through the body) ---
    this.cupGroup = new THREE.Group();
    this.cupGroup.position.set(0, CUP.Y, 0);
    scene.add(this.cupGroup);
    const glassMat = new THREE.MeshStandardMaterial({
      color: 0xdfefff, transparent: true, opacity: 0.32, roughness: 0.1, metalness: 0.05,
      depthWrite: false, side: THREE.DoubleSide,
    });
    const cupGeo = new THREE.CylinderGeometry(CUP.R_TOP, CUP.R_BOT, CUP.H, 28, 1, true);
    this.ownedGeos.push(cupGeo);
    this.ownedMats.push(glassMat);
    this.cupGroup.add(new THREE.Mesh(cupGeo, glassMat));
    const rim = own(new THREE.Mesh(
      new THREE.TorusGeometry(CUP.R_TOP, 0.035, 10, 36),
      new THREE.MeshStandardMaterial({ color: 0xfff4e4, roughness: 0.4 })
    ));
    rim.position.y = CUP.H / 2;
    rim.rotation.x = Math.PI / 2;
    this.cupGroup.add(rim);
    const base = own(new THREE.Mesh(
      new THREE.CylinderGeometry(CUP.R_BOT + 0.06, CUP.R_BOT + 0.14, 0.1, 28),
      new THREE.MeshStandardMaterial({ color: 0xfff4e4, roughness: 0.4 })
    ));
    base.position.y = -CUP.H / 2 - 0.05;
    this.cupGroup.add(base);
    const handle = own(new THREE.Mesh(
      new THREE.TorusGeometry(0.3, 0.07, 10, 24, Math.PI * 1.25),
      new THREE.MeshStandardMaterial({ color: 0xfff4e4, roughness: 0.4 })
    ));
    handle.position.set(CUP.R_TOP + 0.1, 0, 0);
    handle.rotation.z = Math.PI / 2 + 0.4;
    this.cupGroup.add(handle);
    // tea liquid: a cylinder scaled by the fill level
    this.teaGeo = new THREE.CylinderGeometry(CUP.R_TOP - 0.12, CUP.R_BOT - 0.08, 1, 24);
    this.teaMat = new THREE.MeshStandardMaterial({ color: 0xc9803c, roughness: 0.35 });
    this.ownedGeos.push(this.teaGeo);
    this.ownedMats.push(this.teaMat);
    this.tea = new THREE.Mesh(this.teaGeo, this.teaMat);
    this.tea.scale.y = 0.001;
    this.cupGroup.add(this.tea);
    // target band: translucent teal sleeve + gold perfect ring, per-cup height
    this.bandMat = new THREE.MeshBasicMaterial({
      color: 0x59c9b9, transparent: true, opacity: 0.38, depthWrite: false, side: THREE.DoubleSide,
    });
    this.ownedMats.push(this.bandMat);
    this.bandSleeve = new THREE.Mesh(new THREE.CylinderGeometry(1, 1, 1, 28, 1, true), this.bandMat);
    this.ownedGeos.push(this.bandSleeve.geometry);
    this.cupGroup.add(this.bandSleeve);
    this.perfectRing = own(new THREE.Mesh(
      new THREE.TorusGeometry(1, 0.022, 8, 40),
      new THREE.MeshBasicMaterial({ color: 0xffb628 })
    ));
    this.perfectRing.rotation.x = Math.PI / 2;
    this.cupGroup.add(this.perfectRing);

    // --- teapot (top right, tilts while pouring) ---
    this.pot = new THREE.Group();
    this.pot.position.set(1.55, CUP.Y + CUP.H / 2 + 2.05, 0);
    scene.add(this.pot);
    const potMat = new THREE.MeshStandardMaterial({ color: 0xff9bbd, roughness: 0.45 });
    this.ownedMats.push(potMat);
    const potBody = new THREE.Mesh(new THREE.SphereGeometry(0.62, 24, 18), potMat);
    this.ownedGeos.push(potBody.geometry);
    potBody.scale.y = 0.82;
    this.pot.add(potBody);
    const lid = own(new THREE.Mesh(
      new THREE.SphereGeometry(0.12, 14, 10),
      new THREE.MeshStandardMaterial({ color: 0xfff4e4, roughness: 0.4 })
    ));
    lid.position.y = 0.56;
    this.pot.add(lid);
    const spout = new THREE.Mesh(new THREE.CylinderGeometry(0.06, 0.14, 0.75, 12), potMat);
    this.ownedGeos.push(spout.geometry);
    spout.position.set(-0.62, 0.05, 0);
    spout.rotation.z = 0.9;
    this.pot.add(spout);
    const potHandle = new THREE.Mesh(new THREE.TorusGeometry(0.3, 0.06, 8, 20, Math.PI * 1.2), potMat);
    this.ownedGeos.push(potHandle.geometry);
    potHandle.position.set(0.6, 0.05, 0);
    potHandle.rotation.z = -Math.PI / 2 + 0.5;
    this.pot.add(potHandle);
    /** Spout tip in pot-local space — the stream hangs from here. */
    this.spoutTip = new THREE.Vector3(-0.95, 0.35, 0);
    // pour stream: thin scaled cylinder, hidden unless pouring
    this.streamMat = new THREE.MeshBasicMaterial({ color: 0xd28c46, transparent: true, opacity: 0.85 });
    this.ownedMats.push(this.streamMat);
    this.stream = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.07, 1, 10), this.streamMat);
    this.ownedGeos.push(this.stream.geometry);
    this.stream.visible = false;
    scene.add(this.stream);

    // --- input: hold anywhere to pour, release to serve. A press during the
    // cup swap is BUFFERED (pointerHeld) and starts pouring the moment the
    // cup is ready — eager fingers never get eaten (comfy §G2 feel rule).
    this.pointerHeld = false;
    this.onPointerDown = () => {
      if (this.autoplay) return;
      this.pointerHeld = true;
      this.startPour();
    };
    this.onPointerUp = () => {
      if (this.autoplay) return;
      this.pointerHeld = false;
      this.releasePour();
    };
    const el = ctx.renderer.domElement;
    el.addEventListener('pointerdown', this.onPointerDown);
    el.addEventListener('pointerup', this.onPointerUp);
    el.addEventListener('pointercancel', this.onPointerUp);
    el.addEventListener('pointerleave', this.onPointerUp);

    this.serveCup(true);
    ctx.hud.setScore(0);
    ctx.hud.setTime(this.tune.ENDLESS ? 0 : this.tune.DURATION_SEC);
  },

  /** Slide a fresh cup in and roll its band. */
  serveCup(first = false) {
    this.band = rollBand(this.ctx.rng, this.tune);
    this.level = 0;
    this.tea.scale.y = 0.001;
    this.tea.position.y = -CUP.H / 2;
    // place band sleeve + perfect ring at the rolled fill window
    const yOf = (frac) => -CUP.H / 2 + frac * CUP.H;
    const rAt = (frac) => CUP.R_BOT + (CUP.R_TOP - CUP.R_BOT) * frac;
    const bandH = this.band.half * 2 * CUP.H;
    this.bandSleeve.scale.set(rAt(this.band.center) + 0.06, bandH, rAt(this.band.center) + 0.06);
    this.bandSleeve.position.y = yOf(this.band.center);
    this.perfectRing.scale.setScalar(rAt(this.band.center) + 0.08);
    this.perfectRing.position.y = yOf(this.band.center);
    this.phase = 'serve';
    this.phaseT = first ? 0.45 : serveIntervalAt(this.elapsed, this.tune.DURATION_SEC, this.tune);
    // slide-in bounce
    const grp = this.cupGroup;
    grp.position.x = this.halfW + 1.5;
    tween({
      from: this.halfW + 1.5, to: 0, duration: Math.min(0.5, this.phaseT), ease: easings.easeOutBack,
      onUpdate: (v) => { grp.position.x = v; },
    });
    this.cupsServed += 1;
    if (this.autoplay) {
      const err = (this.ctx.rng() * 2 - 1) * this.tune.AUTOPLAY_AIM_ERR;
      this.autoTargetLevel = this.band.center + err;
    }
  },

  /** Begin pouring (hold started). */
  startPour() {
    if (this.phase !== 'ready' || this.pouring) return;
    this.pouring = true;
    this.ctx.audio.play('garden.water');
    tween({
      from: this.pot.rotation.z, to: -0.55, duration: 0.18, ease: easings.easeOutCubic,
      onUpdate: (v) => { this.pot.rotation.z = v; },
    });
  },

  /** Release: rate the cup against its band (§V5.1 rules via pourResult). */
  releasePour(forcedOverflow = false) {
    if (this.phase !== 'ready' || (!this.pouring && !forcedOverflow)) return;
    this.pouring = false;
    this.stream.visible = false;
    tween({
      from: this.pot.rotation.z, to: 0, duration: 0.22, ease: easings.easeOutCubic,
      onUpdate: (v) => { this.pot.rotation.z = v; },
    });
    if (this.level <= 0.01 && !forcedOverflow) return; // tap without tea — no cup wasted
    const res = pourResult(this.level, this.band, this.tune);
    const prev = this.score;
    this.score = applyScore(this.score, res.points);
    if (this.score !== prev) this.ctx.onScore(this.score - prev);
    const cupTop = new THREE.Vector3(0, CUP.Y + CUP.H / 2 + 0.35, 0.5);

    if (res.result === 'perfect') {
      this.streak += 1;
      this.ctx.audio.play('hop.bell');
      this.particles.emit('sparkles', cupTop, { count: 10 });
      this.floats.spawn(`+${res.points} ${t('mg.tea.perfect')}`, cupTop, '#2E8B57');
      this.reactGooby('ecstatic', 'happyBounce');
      const bonus = streakBonusAt(this.streak, this.tune);
      if (bonus > 0) {
        const before = this.score;
        this.score = applyScore(this.score, bonus);
        if (this.score !== before) this.ctx.onScore(this.score - before);
        this.ctx.audio.play('combo.up');
        this.ctx.hud.banner(t('mg.tea.streak', { n: this.streak, b: bonus }));
        this.particles.emit('confetti', cupTop, { count: 10 });
      }
    } else if (res.result === 'good') {
      this.streak = 0;
      this.ctx.audio.play('bubble.pop');
      this.particles.emit('bubbles', cupTop, { count: 5 });
      this.floats.spawn(`+${res.points} ${t('mg.tea.good')}`, cupTop, '#C98A00');
      this.reactGooby('happy', 'wave');
    } else {
      this.streak = 0;
      this.spills += 1;
      this.ctx.audio.play('wash.splash');
      this.particles.emit('bubbles', cupTop, { count: 8 });
      this.floats.spawn(t(res.overflow ? 'mg.tea.overflow' : 'mg.tea.miss'), cupTop, '#D64570');
      if (!prefersReducedMotion()) this.shakeT = 0.25;
      this.reactGooby('dizzy', 'dizzy');
      this.particles.emit('dizzyStars', this.gooby.group.position.clone().add(new THREE.Vector3(0, 1.0, 0)));
      if (this.tune.ENDLESS) {
        this.ctx.hud.banner(t('mg.tea.spills', { n: this.spills, max: this.tune.ENDLESS_MAX_SPILLS }));
        if (endlessShouldEnd(this.spills, this.tune)) {
          this.finishRound();
          return;
        }
      }
    }
    // rate beat, then slide out + serve the next cup
    this.phase = 'rate';
    this.phaseT = 0.55;
  },

  finishRound() {
    if (this.phase === 'ending' || this.phase === 'done') return;
    this.phase = 'ending';
    this.phaseT = 1.3;
    this.pouring = false;
    this.stream.visible = false;
    this.shakeT = 0;
    this.ctx.camera.position.set(0, 0, 10);
    this.ctx.audio.play('ui.win');
    this.gooby.setEmotion('ecstatic');
    this.gooby.play('happyBounce');
    this.particles.emit('confetti', this.gooby.group.position.clone().add(new THREE.Vector3(0, 1.2, 0)), { count: 16 });
  },

  /** Brief Gooby reaction. */
  reactGooby(emotion, clip) {
    this.gooby.setEmotion(emotion);
    this.emotionT = 1.1;
    if (clip === 'dizzy' || !this.gooby.isPlaying(clip)) this.gooby.play(clip);
  },

  update(dt, elapsed) {
    const ctx = this.ctx;
    this.elapsed = elapsed;
    this.gooby.update(dt);
    this.particles.update(dt);
    this.floats.update(dt);

    // micro-shake on spills
    if (this.shakeT > 0) {
      this.shakeT -= dt;
      const k = Math.max(0, this.shakeT / 0.25) * 0.06;
      ctx.camera.position.set((ctx.rng() - 0.5) * k, (ctx.rng() - 0.5) * k, 10);
      if (this.shakeT <= 0) ctx.camera.position.set(0, 0, 10);
    }

    if (this.emotionT > 0) {
      this.emotionT -= dt;
      if (this.emotionT <= 0) {
        this.gooby.setEmotion('happy');
        this.gooby.lookAt(null);
      }
    }

    if (this.phase === 'ending') {
      this.phaseT -= dt;
      if (this.phaseT <= 0 && this.phase !== 'done') {
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
        console.log(`[teaParty] autoplay run ended — score ${this.score}, cups ${this.cupsServed}, spills ${this.spills}`);
      }
      return;
    }

    // phase timers: serve → ready · rate → swap (slide out) → serve fresh
    if (this.phase === 'serve') {
      this.phaseT -= dt;
      if (this.phaseT <= 0) this.phase = 'ready';
    } else if (this.phase === 'rate') {
      this.phaseT -= dt;
      if (this.phaseT <= 0) {
        const grp = this.cupGroup;
        tween({
          from: 0, to: -(this.halfW + 1.6), duration: 0.28, ease: easings.easeInCubic,
          onUpdate: (v) => { grp.position.x = v; },
        });
        this.phase = 'swap';
        this.phaseT = 0.3;
      }
    } else if (this.phase === 'swap') {
      this.phaseT -= dt;
      if (this.phaseT <= 0) this.serveCup();
    } else if (this.phase === 'ready') {
      if ((this.autoplay || this.pointerHeld) && !this.pouring) this.startPour();
      if (this.pouring) {
        this.level = fillAfter(this.level, dt, this.tune);
        // liquid rises
        const h = Math.min(1, this.level) * CUP.H;
        this.tea.scale.y = Math.max(0.001, h);
        this.tea.position.y = -CUP.H / 2 + h / 2;
        // stream from spout to tea surface
        const tip = this.spoutTip.clone().applyMatrix4(this.pot.matrixWorld);
        const surfaceY = this.cupGroup.position.y - CUP.H / 2 + h;
        this.stream.visible = true;
        const len = Math.max(0.1, tip.y - surfaceY);
        this.stream.scale.y = len;
        this.stream.position.set(tip.x * 0.15, surfaceY + len / 2, 0.1);
        if (this.autoplay && this.level >= this.autoTargetLevel) this.releasePour();
        if (this.level >= this.tune.OVERFLOW_LEVEL) {
          this.pouring = true; // overflow rates the cup even mid-hold
          this.releasePour(true);
        }
      }
    }
    // teapot idle bob + steam
    this.pot.position.y += Math.sin(elapsed * 2.2) * dt * 0.03;
    if (Math.floor(elapsed * 2) !== Math.floor((elapsed - dt) * 2) && this.ctx.rng() < 0.3) {
      this.particles.emit('bubbles', this.pot.position.clone().add(new THREE.Vector3(0, 0.7, 0)), { count: 1 });
    }
  },

  dispose() {
    const el = this.ctx?.renderer?.domElement;
    el?.removeEventListener('pointerdown', this.onPointerDown);
    el?.removeEventListener('pointerup', this.onPointerUp);
    el?.removeEventListener('pointercancel', this.onPointerUp);
    el?.removeEventListener('pointerleave', this.onPointerUp);
    this.floats?.dispose();
    this.particles?.dispose();
    this.gooby?.dispose();
    for (const geo of this.ownedGeos ?? []) geo.dispose();
    for (const mat of this.ownedMats ?? []) mat.dispose();
    this.ownedGeos = [];
    this.ownedMats = [];
    this.cupGroup = null;
    this.pot = null;
    this.stream = null;
    this.tea = null;
    this.bandSleeve = null;
    this.perfectRing = null;
    this.band = null;
    this.tune = null;
    this.gooby = null;
    this.particles = null;
    this.floats = null;
    this.ctx = null;
  },
};
export const controls = Object.freeze({ invertible: false }); // V5/G06 (§G2.1 rule 4): hold/release timing input — inverting is nonsense here
