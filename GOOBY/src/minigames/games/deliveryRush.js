// Delivery Rush — „Liefer-Blitz" (PLAN2 §C1.2 #5, §C9.4, agent V2/G28): the
// city earns its keep as a game board. Gooby's van (car-kit `delivery`)
// starts at the shop parking with 3 parcels; a seeded sequence of 3 distinct
// destinations out of the 6 city landmarks is guided leg-by-leg with the v1
// arrow + route-line system; driving into the glowing 4 m drop ring delivers
// (+50, confetti, doorbell). Traffic/crash rules match cityDrive except the
// tow rule: crashes only cost time and −5 (floor 0) — no tow, no fail. After
// the 3rd drop a time bonus of +max(0, 120 − elapsedSec) lands, then the
// round ends. Score ≈ 170–190 → ~24c (§C1.1 row 8/5/32, energy 6).
//
// Distinct look (§C1.3, binding): the city ALWAYS at the DUSK band — warm
// low sun over the same streets that cityDrive shows under the live clock.
// City assembly, dusk band table and route guides are consumed from
// cityDrive.js (its marked V2/G28 export line) — zero duplication.
//
// Pure rules (destination pick, score math, BFS road legs) live in
// deliveryRush.logic.js. Dev-only ?autoplay=1 drives the cityDrive pilot
// along each leg's lane polyline.

import * as THREE from 'three';
import { DRIVE_TUNING, DAYNIGHT } from '../../data/constants.js';
import { t, getLang } from '../../data/strings.js'; // V4/GAME-POLISH-5: + getLang (tx fallback)
// V4/GAME-POLISH-5: strings.js is frozen (PLAN4 §E0.1-8) — new juice strings
// ride the versioned module through the local tx() fallback below.
import { EN as GP5_EN, DE as GP5_DE } from '../../data/strings/v4-gpgroup5.js';
// V6/C4 (GAME-JUICE): delivered/tip float strings ride the v6-juice module
import { EN as JUICE_EN, DE as JUICE_DE } from '../../data/strings/v6-juice.js';
import {
  generateCityLayout,
  layoutColliders,
  tileToWorld,
  worldToTile,
  laneOffsetPolyline,
  polylineLength,
  pointAtLength,
  distanceToPolyline,
  CITY_ASSET_KEYS,
  landmarksInRange,
} from '../../city/cityBuilder.js';
import { createCarController, wrapAngle, ensureWheels } from '../../city/carController.js';
import { createTraffic, separateFromHit, TRAFFIC_ASSET_KEYS } from '../../city/traffic.js';
import { buildVetClinic, buildLandmarkDressing, VET_CLINIC_ASSET_KEYS } from '../../city/vetClinic.js';
// V6/C4: createFloatTexts rides the same V2/G28 sharing channel as the rest
import { CITY_BANDS, buildCity, buildRouteGuides, hideNearbyArrows, createFloatTexts } from './cityDrive.js';
import { createGooby } from '../../character/gooby.js';
import { applyEquippedOutfits } from '../../character/outfitAttach.js';
import { createParticles } from '../../gfx/particles.js';
// V4/GAME-POLISH-5: pooled streaks, parcel-pop tween + reduced-motion gate
import { streakRate, createSpeedLines } from '../../gfx/speedLines.js';
import { tween, easings } from '../../gfx/tween.js';
import { prefersReducedMotion } from '../../ui/ui.js';
import {
  DELIVERY,
  DELIVERY_FX, // V4/GAME-POLISH-5
  parcelArcPos, // V4/GAME-POLISH-5
  applyDifficulty,
  withDeliveryCoinRate,
  createDeliveryEndlessState,
  recordDeliveryExpiry,
  parcelExpired,
  pickDeliveries,
  pickFragileParcel,
  fragileCrashPenalty,
  fragileDeliveryBonus,
  applyDrop,
  applyCrash,
  timeBonus,
  dropPoint,
  segmentHitsDrop,
  nearestRoadTile,
  roadPathBetween,
} from './deliveryRush.logic.js';

const T = DRIVE_TUNING;

/** V4/GAME-POLISH-5: t() first, then the v4-gpgroup5 EN/DE fallback.
 * V6/C4: also consults the v6-juice table (C3 commits the strings.js import). */
function tx(key, vars) {
  const global = t(key, vars);
  if (global !== key) return global;
  const de = getLang() === 'de';
  let text = (de ? GP5_DE : GP5_EN)[key] ?? (de ? JUICE_DE : JUICE_EN)[key] ?? key;
  if (vars) {
    for (const [name, value] of Object.entries(vars)) {
      text = text.replaceAll(`{${name}}`, String(value));
    }
  }
  return text;
}

// V4/GAME-POLISH-5: hoisted per-frame scratch (guidance/juice below)
const _Y_AXIS = new THREE.Vector3(0, 1, 0);
const _guideDir = new THREE.Vector3();
const _dustPos = new THREE.Vector3();
const _nearPos = new THREE.Vector3();
const _popFrom = new THREE.Vector3();
const _floatPos = new THREE.Vector3(); // V6/C4: coin/delivery float spawn temp

// ── V6/C4 (GAME-JUICE): delivery-juice tuning — frozen module-local
// (§E0.1-3; deliveryRush.logic.js's DELIVERY score table is not touched —
// test/gamePolish6.test.js pins it). Per the PLAN4 §C7.2/§G4.8 ruling the
// drive pair adds NO camera shake: floats, hearts, the door glow and audio
// are the whole budget.
export const DELIVERY_JUICE6 = Object.freeze({
  /** Warm door glow at the drop anchor: peak world scale + life (s). */
  DOOR_GLOW_SCALE: 5.5,
  DOOR_GLOW_SEC: 0.85,
  /** Hearts burst from the delivered household. */
  DELIVER_HEARTS: 6,
});
// ── end V6/C4 ────────────────────────────────────────────────────────────────

/** V6/C4: soft warm radial glow texture for the door light-up beat. */
function makeGlowTexture() {
  const canvas = document.createElement('canvas');
  canvas.width = 128;
  canvas.height = 128;
  const g = canvas.getContext('2d');
  const grad = g.createRadialGradient(64, 64, 4, 64, 64, 62);
  grad.addColorStop(0, 'rgba(255,224,150,0.95)');
  grad.addColorStop(0.55, 'rgba(255,196,110,0.45)');
  grad.addColorStop(1, 'rgba(255,180,90,0)');
  g.fillStyle = grad;
  g.fillRect(0, 0, 128, 128);
  return new THREE.CanvasTexture(canvas);
}

/** @type {object} §E8 plugin */
export default {
  id: 'deliveryRush',
  assetKeys: [
    ...CITY_ASSET_KEYS,
    ...TRAFFIC_ASSET_KEYS, // includes car-kit/delivery — the player van
    ...VET_CLINIC_ASSET_KEYS,
    'car-kit/sedan', // carController's body (hidden under the van shell)
  ],

  /** @param {object} ctx §E8 game context */
  init(ctx) {
    this.ctx = ctx;
    const modifier = ctx.params?.modifier ?? {};
    this.tune = withDeliveryCoinRate(
      applyDifficulty(DELIVERY, ctx.params?.difficulty ?? 'normal'),
      modifier.coinRate ?? 1
    );
    this.coinRainActive = modifier.type === 'muenzregen' && this.tune.COIN_RATE > 1;
    this.endlessState = createDeliveryEndlessState(this.tune.ENDLESS_EXPIRED_LIMIT);
    this.autoplay =
      import.meta.env?.DEV && new URLSearchParams(location.search).get('autoplay') === '1';
    // V4/GAME-POLISH-5: §E9 test surface (cityDrive __drive convention) —
    // lets CDP proofs read run/juice state without scraping the HUD.
    if (import.meta.env?.DEV) window.__delivery = { game: this };

    this.layout = generateCityLayout(T.CITY_SEED);
    const layout = this.layout;

    // --- scene dressing: ALWAYS the dusk band (§C1.3 distinct look) --------
    const { scene, camera } = ctx;
    const cityBand = CITY_BANDS.dusk;
    const bandCfg = DAYNIGHT.dusk ?? DAYNIGHT.day;
    scene.background = new THREE.Color(cityBand.sky);
    scene.fog = new THREE.Fog(cityBand.sky, cityBand.fogFrom, cityBand.fogTo);
    scene.add(new THREE.HemisphereLight(bandCfg.hemiSky, bandCfg.hemiGround, cityBand.hemiIntensity));
    const dir = new THREE.DirectionalLight(bandCfg.dirColor, cityBand.dirIntensity);
    dir.position.set(40, 60, -30);
    scene.add(dir);

    buildCity(scene, ctx.assets, layout);
    buildVetClinic(scene, ctx.assets, layout);
    buildLandmarkDressing(scene, ctx.assets, layout);
    this.particles = createParticles(scene);
    this.coinGeo = new THREE.CylinderGeometry(0.42, 0.42, 0.12, 18);
    this.coinMat = new THREE.MeshStandardMaterial({
      color: '#FFD34D', emissive: '#6B4D00', metalness: 0.45, roughness: 0.3,
    });

    // --- the delivery run (§C9.4: shop start, landmark curbside drops) -----
    this.deliveries = pickDeliveries(ctx.rng, layout.landmarks.map((l) => l.id));
    this.fragileParcel = pickFragileParcel(ctx.rng);
    this.fragileDamaged = false;
    this.drops = 0;
    this.score = 0;
    this.crashes = 0;
    this.invuln = 0;
    this.shake = 0;
    this.emotionT = 0;
    this.phase = 'drive'; // 'drive' | 'rescue' | 'fanfare' | 'done'
    this.phaseT = 0;
    this.rescueDone = false;
    this.drawLogT = 0;
    this.landmarksHit = new Set();
    this.distanceM = 0;
    this.distanceSent = false;
    this.legElapsed = 0;
    this.batchElapsed = 0;
    this.coinT = this.tune.COIN_INTERVAL_SEC;
    this.coinPickups = [];

    // curbside drop points (§C9.4): anchors pushed out of building colliders
    // so the 4 m ring is always reachable (sticker triggers keep the anchors)
    this.colliders = layoutColliders(layout);
    this.dropAnchors = new Map(
      layout.landmarks.map((l) => [l.id, dropPoint({ x: l.x, z: l.z }, this.colliders)])
    );

    // --- player van + Gooby --------------------------------------------------
    const spawn = { x: layout.shop.parking.x, z: layout.shop.parking.z, heading: Math.PI / 2 };
    this.lastPos = { x: spawn.x, z: spawn.z };
    this.car = createCarController({
      scene,
      assets: ctx.assets,
      uiRoot: document.getElementById('ui') ?? document.body,
      spawn,
      colliders: this.colliders,
      onWallHit: () => ctx.audio.play('bump'),
      onStuck: () => this.startRescue(),
    });
    // van shell: hide the controller's sedan meshes, parent the car-kit
    // delivery van under the same node so it inherits scale + body roll.
    const body = this.car.group.children[0];
    body.traverse((o) => {
      if (o.isMesh) o.visible = false;
    });
    const van = ctx.assets.getModel('car-kit/delivery');
    this.vanWheels = ensureWheels(van, ctx.assets);
    body.add(van);

    this.gooby = createGooby();
    applyEquippedOutfits(this.gooby);
    this.gooby.group.scale.setScalar(1.15);
    // V4/FIX-3D: seat 2.6 / z 0.55 — the delivery cab roof tops out ≈ 2.88
    // car-local (1.6 native × CAR_SCALE 1.8), so the old 2.15 buried him with
    // only ear tips clipping through; 2.6 pokes head + ears out like the
    // sedan's 2.05-under-2.34 seat, centered on the cab (z ≈ 0..1.1)
    this.gooby.group.position.set(0, 2.6, 0.55);
    this.car.group.add(this.gooby.group);
    this.gooby.setEmotion('happy');
    this.gooby.play('sitDrive');

    // parcel stack on the roof — one box hops off per delivery (juice)
    this.parcels = [];
    for (let i = 0; i < DELIVERY.PARCELS; i += 1) {
      const box = ctx.assets.getModel('car-kit/box');
      box.scale.setScalar(1.1);
      // V4/FIX-3D: y 2.98 (was 2.45) — the cargo roof tops out at 2.97
      // car-local (1.65 native × CAR_SCALE 1.8) and the box origin is its
      // bottom face, so 2.45 sank the parcels ~2/3 into the van
      box.position.set((i - 1) * 0.62, 2.98, -0.75);
      box.rotation.y = (i - 1) * 0.35;
      this.car.group.add(box);
      this.parcels.push(box);
    }
    const fragileBox = this.parcels[DELIVERY.PARCELS - 1 - this.fragileParcel];
    this.fragileStrapGeos = [];
    this.fragileStrapMat = null;
    if (fragileBox) {
      const strapMat = new THREE.MeshBasicMaterial({ color: '#FF4F81' });
      const strapGeoA = new THREE.BoxGeometry(0.08, 0.08, 0.8);
      const strapGeoB = new THREE.BoxGeometry(0.8, 0.08, 0.08);
      this.fragileStrapGeos.push(strapGeoA, strapGeoB);
      this.fragileStrapMat = strapMat;
      const strapA = new THREE.Mesh(strapGeoA, strapMat);
      const strapB = new THREE.Mesh(strapGeoB, strapMat);
      strapA.position.y = 0.35;
      strapB.position.y = 0.35;
      fragileBox.add(strapA, strapB);
      fragileBox.userData.fragile = true;
    }

    this.traffic = createTraffic({ scene, assets: ctx.assets, layout, rng: ctx.rng });

    // ── V4/GAME-POLISH-5: speed-feel + close-call juice state ───────────────
    // Camera-local streak ring (cityDrive/toyRacer recipe — the chase cam
    // roams the whole city). scene.add(camera) so its children render.
    scene.add(camera);
    this.speedLines = createSpeedLines(camera, {
      pool: DELIVERY_FX.STREAK_POOL,
      radius: DELIVERY_FX.STREAK_RADIUS,
      ahead: DELIVERY_FX.STREAK_AHEAD,
      size: DELIVERY_FX.STREAK_SIZE,
      forwardZ: -1, // camera space: ahead = −z
      rng: ctx.rng,
    });
    this.prevHeading = this.car.heading();
    this.dustT = 0;
    this.nearBannerT = 0;
    this.reduceMotion = prefersReducedMotion();
    /** @type {Array<{cancel: () => void, restore: () => void}>} live parcel pops */
    this.popAnims = [];
    // ── end V4/GAME-POLISH-5 ─────────────────────────────────────────────────

    // ── V6/C4 (GAME-JUICE): delivery float texts + door-glow sprite ──────────
    // (cityDrive's shared float pool; chase cam → spawns clamp into view.
    // NO camera shake added — §C7.2 drive-pair ruling.)
    this.floats = createFloatTexts(scene, camera);
    this.glowTex = makeGlowTexture();
    this.glowMat = new THREE.SpriteMaterial({
      map: this.glowTex, transparent: true, opacity: 0, depthWrite: false,
      blending: THREE.AdditiveBlending,
    });
    this.doorGlow = new THREE.Sprite(this.glowMat);
    this.doorGlow.visible = false;
    scene.add(this.doorGlow);
    this.glowTween = null;
    // ── end V6/C4 ─────────────────────────────────────────────────────────────

    // --- delivery ticket chip (📦 n/3 → next stop) ---------------------------
    this.chip = document.createElement('div');
    this.chip.className = 'mg-pill';
    this.chip.style.cssText =
      'position:absolute;top:calc(64px + var(--safe-top));left:50%;transform:translateX(-50%);z-index:35;white-space:nowrap;';
    (document.getElementById('ui') ?? document.body).appendChild(this.chip);

    this.guides = null;
    this.buildLeg();

    ctx.hud.setScore(0);
    ctx.hud.setTime(this.tune.ENDLESS ? 0 : this.tune.TIME_BONUS_FROM_SEC);
    this.car.updateChaseCam(camera, 10);
  },

  /**
   * Current destination ({id, x, z} = the reachable curbside DROP point, not
   * necessarily the raw sticker anchor) or null once all delivered.
   */
  destination() {
    const id = this.deliveries[this.drops];
    if (!id) return null;
    const drop = this.dropAnchors.get(id);
    return { id, x: drop.x, z: drop.z };
  },

  /**
   * Build the guided leg to the current destination: BFS road tiles from the
   * van to the landmark's nearest road tile, lane-offset the centerline, then
   * run the v1 arrow/route-line/drop-ring guides over it (§C1.2 #5 reuse).
   */
  buildLeg() {
    this.disposeGuides();
    const dest = this.destination();
    if (!dest) return;
    const grid = this.layout.grid;
    const p = this.car.position;
    const fromTile = worldToTile(p.x, p.z);
    const from = nearestRoadTile(grid, fromTile.r, fromTile.c);
    const destTile = worldToTile(dest.x, dest.z);
    const to = nearestRoadTile(grid, destTile.r, destTile.c);
    const tiles = roadPathBetween(grid, from, to) ?? [from, to];
    const center = tiles.map(({ r, c }) => tileToWorld(r, c));
    const lane = [
      { x: p.x, z: p.z },
      ...(center.length > 1 ? laneOffsetPolyline(center, T.LANE_OFFSET_M) : center),
      { x: dest.x, z: dest.z },
    ];
    this.legLayout = {
      lane,
      laneLength: polylineLength(lane),
      shop: { parking: { x: dest.x, z: dest.z } }, // ring = the 4 m drop ring
    };
    this.progress = 0;
    this.legElapsed = 0;
    this.guides = buildRouteGuides(this.ctx.scene, this.legLayout);
    // Audit fix: route ribbon sits nearly coplanar with the road. Polygon
    // offset + render order removes dusk-road z-fighting without touching the
    // shared cityDrive guide builder.
    const ribbon = this.guides.group.children[0];
    if (ribbon?.material) {
      ribbon.material.polygonOffset = true;
      ribbon.material.polygonOffsetFactor = -2;
      ribbon.material.polygonOffsetUnits = -2;
      ribbon.renderOrder = 2;
    }
    this.updateChip();
  },

  /** Drop the current leg's guides (ribbon/arrows/ring/helper) cleanly. */
  disposeGuides() {
    if (!this.guides) return;
    this.guides.group.traverse((o) => {
      o.geometry?.dispose?.();
      if (o.material) {
        for (const m of Array.isArray(o.material) ? o.material : [o.material]) m.dispose?.();
      }
    });
    this.ctx.scene.remove(this.guides.group);
    this.guides = null;
  },

  updateChip() {
    if (!this.chip) return;
    const dest = this.destination();
    const ticket = t('mg.delivery.ticket', { n: this.drops, max: DELIVERY.PARCELS });
    const fragile = this.drops === this.fragileParcel
      ? ` · ${t(this.fragileDamaged ? 'v3.depth.delivery.damaged' : 'v3.depth.delivery.fragile')}`
      : '';
    this.chip.textContent = dest
      ? `${ticket}${fragile} → ${t(`sticker.landmarks.${dest.id}.name`)}`
      : `${ticket}${fragile}`;
  },

  /** Track score with the §C1.2 #5 floor and mirror it into the HUD. */
  setScore(next) {
    const delta = next - this.score;
    this.score = next;
    if (delta !== 0) this.ctx.onScore(delta);
  },

  /** §C1.2 #5 crash: −5 (floor 0) + shake — no tow rule, never a fail. */
  crash() {
    if (this.invuln > 0 || this.phase !== 'drive') return;
    this.crashes += 1;
    this.invuln = T.CRASH_INVULN_SEC;
    this.shake = 1;
    this.car.applyCrashPenalty();
    const protectedCrash = this.crashes <= this.tune.CRASH_ALLOWANCE;
    if (!protectedCrash) this.setScore(applyCrash(this.score));
    const fragilePenalty = fragileCrashPenalty(
      this.fragileParcel,
      this.drops,
      this.fragileDamaged
    );
    if (fragilePenalty > 0 && !protectedCrash) {
      this.fragileDamaged = true;
      this.setScore(Math.max(0, this.score - fragilePenalty));
      this.ctx.hud.banner(t('v3.depth.delivery.broken', { n: fragilePenalty }));
      this.updateChip();
    }
    this.ctx.audio.play('crash');
    if (fragilePenalty === 0) this.ctx.hud.banner(t('trip.crash'));
    this.gooby.setEmotion('dizzy');
    this.emotionT = 1.5;
  },

  /** A parcel lands (§C1.2 #5): +50, confetti, doorbell, next leg or bonus. */
  deliver(elapsed) {
    const dest = this.destination();
    if (!dest) return;
    const deliveredParcel = this.drops;
    const scoreBefore = this.score; // V6/C4: the float reports the real delta
    this.drops += 1;
    this.setScore(applyDrop(this.score));
    const fragileBonus = fragileDeliveryBonus(
      this.fragileParcel,
      deliveredParcel,
      this.fragileDamaged
    );
    if (fragileBonus > 0) {
      this.setScore(this.score + fragileBonus);
      this.ctx.hud.banner(t('v3.depth.delivery.clean', { n: fragileBonus }));
    }
    this.ctx.audio.play('delivery.doorbell');
    this.ctx.audio.play('delivery.drop'); // G29's confetti pop rides the burst
    this.particles.emit?.('confetti', new THREE.Vector3(dest.x, T.ROAD_Y + 3, dest.z), { count: 22 });
    // V6/C4 juice (§C.5 #2): the drop finally SAYS what it paid — stacked
    // "Delivered!" + "+{n}" floats at the ring, a hearts puff from the happy
    // household, and a warm door glow at the curbside anchor (RM-gated).
    this.floats.spawn(tx('v6.juice.delivered'), _floatPos.set(dest.x, T.ROAD_Y + 4.6, dest.z), '#D6428A');
    this.floats.spawn(`+${this.score - scoreBefore}`, _floatPos.set(dest.x, T.ROAD_Y + 3.1, dest.z), '#D69A28');
    this.particles.emit?.('hearts', _floatPos.set(dest.x, T.ROAD_Y + 2.2, dest.z), {
      count: DELIVERY_JUICE6.DELIVER_HEARTS,
    });
    this.flashDoorGlow(dest);
    this.gooby.setEmotion('ecstatic');
    this.emotionT = 1.6;
    const parcel = this.parcels[DELIVERY.PARCELS - this.drops];
    if (parcel) this.popParcel(parcel, dest); // V4/GAME-POLISH-5: visible hop-off arc
    if (this.drops < DELIVERY.PARCELS) {
      if (fragileBonus === 0) this.ctx.hud.banner(t('mg.delivery.delivered'));
      this.buildLeg();
      if (this.autoplay) console.log(`[deliveryRush] drop ${this.drops} at ${dest.id} — score ${this.score}`);
      return;
    }
    // 3rd drop: time bonus + fanfare → results (§C1.2 #5)
    const bonus = timeBonus(this.tune.ENDLESS ? this.batchElapsed : elapsed, this.tune);
    if (bonus > 0) {
      this.setScore(this.score + bonus);
      this.ctx.hud.banner(t('mg.delivery.timeBonus', { n: bonus }));
    } else {
      this.ctx.hud.banner(t('mg.delivery.allDone'));
    }
    this.updateChip();
    this.disposeGuides();
    if (this.tune.ENDLESS) {
      this.resetDeliveryBatch();
      return;
    }
    this.phase = 'fanfare';
    this.phaseT = 0;
    this.car.setFrozen(true);
    this.ctx.audio.play('jingle.arrival');
    if (this.autoplay) {
      console.log(`[deliveryRush] run complete — drops 3, crashes ${this.crashes}, bonus ${bonus}, score ${this.score}`);
    }
  },

  /**
   * V6/C4 juice: warm door light-up at the drop anchor (§C.5 #2). The city
   * buildings render as shared InstancedMesh (buildCity), so ONE house can't
   * tint in place — a warm additive glow sprite at the curbside anchor sells
   * the door opening instead. Flash ⇒ reduced-motion gated (doorbell +
   * confetti + floats still carry the beat).
   * @param {{x: number, z: number}} dest drop anchor
   */
  flashDoorGlow(dest) {
    if (this.reduceMotion || !this.doorGlow) return;
    this.glowTween?.cancel();
    this.doorGlow.position.set(dest.x, T.ROAD_Y + 1.6, dest.z);
    this.doorGlow.visible = true;
    this.glowTween = tween({
      from: 0, to: 1, duration: DELIVERY_JUICE6.DOOR_GLOW_SEC, ease: easings.easeOutQuad,
      onUpdate: (v) => {
        if (!this.doorGlow) return;
        this.doorGlow.scale.setScalar(1.5 + (DELIVERY_JUICE6.DOOR_GLOW_SCALE - 1.5) * v);
        this.glowMat.opacity = 0.95 * (1 - v);
      },
      onComplete: () => {
        if (this.doorGlow) this.doorGlow.visible = false;
        this.glowTween = null;
      },
    });
  },

  // ── V4/GAME-POLISH-5: parcel pop — the roof box visibly hops off in an
  // arc to the drop ring (spin + apex lift from parcelArcPos), then hides
  // and re-attaches with its original local transform so the batch resets
  // cleanly. Reduced motion keeps the old instant hide. Cosmetic only.
  popParcel(parcel, dest) {
    if (this.reduceMotion) {
      parcel.visible = false;
      return;
    }
    const scene = this.ctx.scene;
    const origPos = parcel.position.clone();
    const origQuat = parcel.quaternion.clone();
    const origParent = parcel.parent;
    parcel.getWorldPosition(_popFrom);
    const from = { x: _popFrom.x, y: _popFrom.y, z: _popFrom.z };
    const to = { x: dest.x, y: T.ROAD_Y + 0.3, z: dest.z };
    scene.attach(parcel); // keep the world transform, leave the van
    const spin0 = parcel.rotation.y;
    let done = false;
    const restore = () => {
      if (done) return;
      done = true;
      parcel.visible = false;
      origParent?.add(parcel);
      parcel.position.copy(origPos);
      parcel.quaternion.copy(origQuat);
    };
    const anim = tween({
      duration: DELIVERY_FX.POP_SEC,
      ease: easings.linear, // the sin() lift already shapes the arc
      onUpdate: (v) => {
        const p = parcelArcPos(from, to, v);
        parcel.position.set(p.x, p.y, p.z);
        parcel.rotation.y = spin0 + v * DELIVERY_FX.POP_SPIN_RAD;
      },
      onComplete: restore,
    });
    this.popAnims.push({ cancel: anim.cancel, restore });
  },

  /** Settle any in-flight parcel pops NOW (batch reset / dispose). */
  finishPops() {
    for (const pop of this.popAnims ?? []) {
      pop.cancel();
      pop.restore();
    }
    this.popAnims = [];
  },
  // ── end V4/GAME-POLISH-5 ────────────────────────────────────────────────

  /** Endlos chains delivery batches; regular arcade still ends after parcel 3. */
  resetDeliveryBatch() {
    this.deliveries = pickDeliveries(this.ctx.rng, this.layout.landmarks.map((l) => l.id));
    this.drops = 0;
    this.batchElapsed = 0;
    this.fragileParcel = pickFragileParcel(this.ctx.rng);
    this.fragileDamaged = false;
    this.finishPops(); // V4/GAME-POLISH-5: settle in-flight pops BEFORE the re-show
    for (const parcel of this.parcels) parcel.visible = true;
    this.car.setFrozen(false);
    this.phase = 'drive';
    this.buildLeg();
  },

  expireParcel() {
    if (!this.tune.ENDLESS || this.phase !== 'drive') return;
    const parcel = this.parcels[DELIVERY.PARCELS - this.drops - 1];
    if (parcel) parcel.visible = false;
    this.drops += 1;
    const ended = recordDeliveryExpiry(this.endlessState);
    this.ctx.audio.play('delivery.drop');
    if (ended) {
      this.disposeGuides();
      this.phase = 'fanfare';
      this.phaseT = 0;
      this.car.setFrozen(true);
      return;
    }
    if (this.drops >= this.tune.PARCELS) this.resetDeliveryBatch();
    else this.buildLeg();
  },

  spawnCoinPickup() {
    if (!this.coinRainActive || !this.legLayout) return;
    const q = pointAtLength(
      this.legLayout.lane,
      Math.min(this.legLayout.laneLength, this.progress + 16 + this.ctx.rng() * 12)
    );
    const mesh = new THREE.Mesh(this.coinGeo, this.coinMat);
    mesh.rotation.z = Math.PI / 2;
    mesh.position.set(q.x, T.ROAD_Y + 1.1, q.z);
    this.ctx.scene.add(mesh);
    this.coinPickups.push(mesh);
  },

  /** F4 P1-1 pattern: wedged off-road → veil dip + teleport back to the leg. */
  startRescue() {
    if (this.phase !== 'drive') return;
    this.phase = 'rescue';
    this.phaseT = 0;
    this.rescueDone = false;
    this.car.setFrozen(true);
    this.ctx.audio.play('tow');
    this.gooby.setEmotion('dizzy');
    this.emotionT = 1.5;
    this.veil = document.createElement('div');
    this.veil.style.cssText = 'position:fixed;inset:0;background:#000;opacity:0;pointer-events:none;z-index:45;';
    document.body.appendChild(this.veil);
  },

  /** §C9.3 camera-flash gag — plays once per first-time landmark sticker. */
  cameraFlash() {
    const el = document.createElement('div');
    el.style.cssText =
      'position:fixed;inset:0;background:#fff;opacity:0.85;pointer-events:none;z-index:44;transition:opacity 0.45s ease-out;';
    document.body.appendChild(el);
    requestAnimationFrame(() => {
      el.style.opacity = '0';
    });
    setTimeout(() => el.remove(), 520);
  },

  /** Dev autopilot: steer along the current leg lane (cityDrive's pilot). */
  drivePilot() {
    const leg = this.legLayout;
    if (!leg) return;
    const p = this.car.position;
    const target = pointAtLength(leg.lane, Math.min(leg.laneLength, this.progress + 11));
    const desired = Math.atan2(target.x - p.x, target.z - p.z);
    const err = wrapAngle(desired - this.car.heading());
    this.car.setSteer(Math.max(-1, Math.min(1, -err * 2.4))); // V4/G57 (§G3.1-a): setSteer(v>0)=screen-right ⇒ heading −, so the heading-error command is negated
    this.car.setBrake(Math.abs(err) > 0.85 && this.car.speed() > 7);
  },

  /**
   * @param {number} dt seconds (framework skips pauses)
   * @param {number} elapsed running seconds
   */
  update(dt, elapsed) {
    const { ctx } = this;
    this.invuln = Math.max(0, this.invuln - dt);
    this.shake = Math.max(0, this.shake - dt * 2.2);

    // V4/GAME-POLISH-5: streaks tick every frame (leftovers decay through
    // rescue/fanfare); spawning only while actually driving fast.
    if (this.speedLines) {
      const vanSpeed = this.car.speed();
      this.speedLines.update(dt, {
        speed: vanSpeed,
        rate: this.phase === 'drive' && !this.reduceMotion
          ? streakRate(vanSpeed, DELIVERY_FX.STREAK_RATE)
          : 0,
        originX: 0, // camera-local ring: centred on the view axis
        originY: 0,
      });
    }

    this.gooby.update(dt);
    this.floats.update(dt); // V6/C4 juice: floats ride through every phase
    if (this.emotionT > 0) {
      this.emotionT -= dt;
      if (this.emotionT <= 0) this.gooby.setEmotion('happy');
    }

    if (this.phase === 'fanfare') {
      this.phaseT += dt;
      this.car.update(dt);
      this.particles.update?.(dt);
      this.car.updateChaseCam(ctx.camera, dt, 0);
      if (this.phaseT >= 1.7 && this.phase !== 'done') {
        this.phase = 'done';
        ctx.onEnd({ score: this.score, meta: this.buildMeta() });
      }
      return;
    }
    if (this.phase === 'rescue') {
      this.phaseT += dt;
      this.traffic.update(dt);
      this.particles.update?.(dt);
      if (this.veil) {
        this.veil.style.opacity = String(
          this.phaseT < 0.45
            ? Math.min(1, this.phaseT / 0.45)
            : Math.max(0, 1 - (this.phaseT - 0.45) / 0.55)
        );
      }
      if (!this.rescueDone && this.phaseT >= 0.45) {
        this.rescueDone = true;
        const leg = this.legLayout;
        const q = pointAtLength(leg.lane, Math.min(leg.laneLength, this.progress));
        this.car.teleport(q.x, q.z, Math.atan2(q.dx, q.dz));
        this.lastPos.x = q.x;
        this.lastPos.z = q.z;
        this.invuln = T.CRASH_INVULN_SEC;
        this.car.updateChaseCam(ctx.camera, 10);
      }
      if (this.phaseT >= 1.05) {
        this.veil?.remove();
        this.veil = null;
        this.car.setFrozen(false);
        this.phase = 'drive';
        this.phaseT = 0;
      }
      return;
    }
    if (this.phase !== 'drive') return;

    // --- driving --------------------------------------------------------------
    this.legElapsed += dt;
    this.batchElapsed += dt;
    if (parcelExpired(this.legElapsed, this.tune)) {
      this.expireParcel();
      return;
    }
    if (this.autoplay) this.drivePilot();
    const frameStart = { x: this.car.position.x, z: this.car.position.z };
    this.car.update(dt * this.tune.SPEED_MULT);
    this.traffic.update(dt * this.tune.TRAFFIC_DENSITY_MULT);
    this.particles.update?.(dt);
    const wheelOmega = (this.car.speed() / T.CAR_SCALE / 0.3) * dt;
    for (const w of this.vanWheels) w.rotation.x += wheelOmega;

    // leg progress (monotonic arc-length projection — cityDrive recipe)
    const leg = this.legLayout;
    const p = this.car.position;
    let bestS = this.progress;
    let bestD = Infinity;
    for (let s = this.progress; s <= Math.min(leg.laneLength, this.progress + 26); s += 2) {
      const q = pointAtLength(leg.lane, s);
      const d = Math.hypot(q.x - p.x, q.z - p.z);
      if (d < bestD) {
        bestD = d;
        bestS = s;
      }
    }
    if (bestD < T.OFF_ROUTE_M) this.progress = bestS;

    // traffic crashes (§C4.5 rules, forgiving 70% AABBs — no tow here)
    if (this.invuln <= 0) {
      const hit = this.traffic.checkHit(this.car.aabb(T.TRAFFIC_HITBOX_SCALE));
      if (hit) {
        // V4/FIX-3D: same body-overlap resolve as cityDrive (positional only)
        separateFromHit(this.car.position, this.car.aabb(), hit);
        this.crash();
      }
    }

    // ── V4/GAME-POLISH-5: cosmetic close-call sparkle + drift dust ──────────
    // Runs AFTER checkHit so a real crash this frame voids the pass. Score/
    // crash/fragile beats above are untouched (§C1.2 #5 certification).
    {
      const speed = this.car.speed();
      this.nearBannerT = Math.max(0, this.nearBannerT - dt);
      const nm = this.traffic.checkNearMiss?.(this.car.aabb(), speed);
      if (nm) {
        ctx.audio.play('combo.up');
        _nearPos.set((p.x + nm.x) / 2, T.ROAD_Y + 1.6, (p.z + nm.z) / 2);
        this.particles.emit?.('sparkles', _nearPos, { count: 8 });
        if (this.nearBannerT <= 0) {
          this.nearBannerT = DELIVERY_FX.NEAR_BANNER_COOLDOWN_SEC;
          ctx.hud.banner(tx('gp5.drive.nearMiss'));
        }
      }
      // drift dust at the rear bumper while the tires visibly work
      const h = this.car.heading();
      const yawRate = Math.abs(wrapAngle(h - this.prevHeading)) / Math.max(1e-4, dt);
      this.prevHeading = h;
      this.dustT -= dt;
      if (!this.reduceMotion && speed > DELIVERY_FX.DUST_MIN_SPEED
        && yawRate > DELIVERY_FX.DUST_MIN_YAW_RATE && this.dustT <= 0) {
        this.dustT = DELIVERY_FX.DUST_INTERVAL_SEC;
        _dustPos.set(p.x - Math.sin(h) * 1.7, T.ROAD_Y + 0.18, p.z - Math.cos(h) * 1.7);
        this.particles.emit?.('crumbs', _dustPos, { count: 2 });
      }
    }
    // ── end V4/GAME-POLISH-5 ─────────────────────────────────────────────────

    // landmark stickers + odometer (§C9.3/§C12.1 — same bridge as cityDrive)
    const step = Math.hypot(p.x - this.lastPos.x, p.z - this.lastPos.z);
    if (step < 15) this.distanceM += step;
    this.lastPos.x = p.x;
    this.lastPos.z = p.z;
    for (const id of landmarksInRange(this.layout.landmarks, p.x, p.z)) {
      if (this.landmarksHit.has(id)) continue;
      this.landmarksHit.add(id);
      const ev = new CustomEvent('gooby:landmark', { detail: { id, first: false } });
      window.dispatchEvent(ev);
      if (ev.detail.first) this.cameraFlash();
    }

    // drop ring (§C1.2 #5: radius 4 m around the landmark curbside anchor)
    const dest = this.destination();
    if (dest && segmentHitsDrop(frameStart, p, dest)) {
      this.deliver(elapsed);
      if (this.phase !== 'drive') return;
    }

    if (this.coinRainActive) {
      this.coinT -= dt;
      if (this.coinT <= 0) {
        this.coinT = this.tune.COIN_INTERVAL_SEC;
        this.spawnCoinPickup();
      }
      for (let i = this.coinPickups.length - 1; i >= 0; i -= 1) {
        const coin = this.coinPickups[i];
        coin.rotation.y += dt * 4;
        if (Math.hypot(coin.position.x - p.x, coin.position.z - p.z) < 2.5) {
          this.setScore(this.score + this.tune.COIN_POINTS);
          this.particles.emit?.('sparkles', coin.position, { count: 7 });
          // V6/C4 juice (§C.5 #1): the Münzregen pickup was silent AND
          // unlabelled — coin.get ding + a "+{n}" float name the tip.
          this.ctx.audio.play('coin.get');
          this.floats.spawn(
            `+${this.tune.COIN_POINTS}`,
            _floatPos.set(coin.position.x, T.ROAD_Y + 2.3, coin.position.z),
            '#D69A28'
          );
          this.ctx.scene.remove(coin);
          this.coinPickups.splice(i, 1);
        }
      }
    }

    // --- guidance (arrow/route-line reuse) -------------------------------------
    if (this.guides) {
      hideNearbyArrows(this.guides, p.x, p.z);
      this.guides.arrows.position.y = Math.sin(elapsed * 2) * 0.3;
      this.guides.ribbonMat.opacity = 0.45 + Math.sin(elapsed * 3) * 0.12;
      this.guides.ring.scale.setScalar(1 + Math.sin(elapsed * 3.2) * 0.07);
      const offRoute = distanceToPolyline(leg.lane, p.x, p.z) > T.OFF_ROUTE_M;
      this.guides.guide.visible = offRoute;
      if (offRoute) {
        const target = pointAtLength(leg.lane, this.progress + 8);
        _guideDir.set(target.x - p.x, 0, target.z - p.z).normalize(); // V4/GAME-POLISH-5: hoisted
        this.guides.guide.position.set(p.x, T.ROAD_Y + 5.4, p.z);
        this.guides.guide.quaternion.setFromUnitVectors(_Y_AXIS, _guideDir);
      }
    }

    // HUD countdown = the §C1.2 #5 time-bonus window (0 = bonus gone)
    ctx.hud.setTime(
      this.tune.ENDLESS ? elapsed : Math.max(0, this.tune.TIME_BONUS_FROM_SEC - elapsed)
    );

    // --- camera + §E10 budget log ----------------------------------------------
    this.car.updateChaseCam(ctx.camera, dt, this.shake);
    if (import.meta.env?.DEV) {
      this.drawLogT += dt;
      if (this.drawLogT > 3) {
        this.drawLogT = 0;
        const calls = ctx.renderer?.info?.render?.calls ?? 0;
        console.info(`[deliveryRush] draw calls: ${calls} (budget ≤ ${T.DRAW_CALL_BUDGET})`);
      }
    }
  },

  /** §B3 meta: {landmarks, crashes, distanceM, deliveries} (G23 forwards). */
  buildMeta() {
    this.sendDistance();
    return {
      landmarks: [...this.landmarksHit],
      crashes: this.crashes,
      distanceM: Math.round(this.distanceM),
      deliveries: this.drops,
      fragileClean: !this.fragileDamaged,
    };
  },

  /** §C12.1 profile.distanceM feed — one idempotent event per run (G21 bridge). */
  sendDistance() {
    if (this.distanceSent || !(this.distanceM > 0)) return;
    this.distanceSent = true;
    window.dispatchEvent(
      new CustomEvent('gooby:driveDistance', { detail: { meters: Math.round(this.distanceM) } })
    );
  },

  dispose() {
    this.sendDistance(); // quit-from-pause still books the odometer
    this.finishPops(); // V4/GAME-POLISH-5: cancel in-flight parcel arcs
    this.speedLines?.dispose(); // V4/GAME-POLISH-5
    this.speedLines = null;
    this.disposeGuides();
    for (const geo of this.fragileStrapGeos ?? []) geo.dispose();
    this.fragileStrapMat?.dispose();
    this.car?.dispose();
    this.traffic?.dispose();
    this.gooby?.dispose();
    this.particles?.dispose?.();
    // V6/C4 juice teardown
    this.floats?.dispose();
    this.floats = null;
    this.glowTween?.cancel();
    this.glowTween = null;
    this.doorGlow?.parent?.remove(this.doorGlow);
    this.doorGlow = null;
    this.glowMat?.dispose();
    this.glowMat = null;
    this.glowTex?.dispose();
    this.glowTex = null;
    for (const coin of this.coinPickups ?? []) coin.parent?.remove(coin);
    this.coinGeo?.dispose();
    this.coinMat?.dispose();
    this.chip?.remove();
    this.chip = null;
    this.veil?.remove();
    this.veil = null;
    this.ctx = null;
    this.layout = null;
    this.legLayout = null;
    this.landmarksHit = null;
    this.parcels = null;
    this.vanWheels = null;
    this.dropAnchors = null;
    this.colliders = null;
    this.fragileParcel = null;
    this.fragileStrapGeos = [];
    this.fragileStrapMat = null;
    this.coinPickups = [];
    this.tune = null;
    this.endlessState = null;
  },
};
export const controls = Object.freeze({ invertible: true }); // V4/G57 (§G2.1 rule 4, §G3.3): global „Steuerung invertieren“ applies (G56 proxy / carController invertSteer param)
