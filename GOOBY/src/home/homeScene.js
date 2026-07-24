// Persistent home scene (§C2, §D3, §D4): the 4-room apartment, its lighting
// rig, room navigation and Gooby living in the active room. Registered as
// scene id 'home' in main.js with HOME_ASSET_KEYS preloaded.
//
// ── API for sibling agents (G5 interactions, G6 sleep, G11 decor) ──────────
// The §E1 lifecycle instance returned by createHomeScene ALSO carries:
//   getGooby()        → the live createGooby() rig (§D2.3 API) or null
//   getRoomManager()  → the live roomManager (events/anchors — see its JSDoc)
//   setNight(on)      → bedroom night mode (§D4 lighting lerp + window sky)
//   isNight()         → current night-mode target
//
// The same four functions are exported at module level and resolve to the
// currently active home scene instance (null/no-op when the home scene is not
// active), so G5/G6 can simply:
//
//   import { getGooby, getRoomManager, setNight } from '../home/homeScene.js';
//   getRoomManager()?.on('tap:fridge', ({ point }) => { … });
//
// Gooby taps: getRoomManager().on('tap:gooby', ({ hit }) => …) — pass `hit`
// to getGooby().regionAt(hit) for the touched region (head/belly/feet).

import * as THREE from 'three';
import { ROOMS, DAYNIGHT } from '../data/constants.js'; // V2/G26: + DAYNIGHT (§C10.2)
import { now } from '../core/clock.js';
import { currentMood } from '../systems/sleep.js';
import { createGooby } from '../character/gooby.js';
import { createEmotionMachine } from '../character/emotions.js';
import { createParticles } from '../gfx/particles.js';
import { createHomeLights } from '../gfx/lights.js';
import { createRoomManager, NAV_ORDER } from './roomManager.js';
import { createRoomNav } from '../ui/roomNav.js';
// V2/G26 (§C10/§C11): band/weather ambience — engines + animated weather FX
import { bandAt } from '../systems/dayNight.js';
import { weatherAt } from '../systems/weather.js';
import { mountGardenRain, mountGardenClouds, updateWeatherFx } from '../gfx/weatherFx.js';
import { createAmbientLife } from './ambientLife.js'; // V6/A3: batched room ambient life
// V6/F2: living-world reactions — the transient garden bird + the pure
// watch/hum decision logic (all tuning/tests live in ambientLife.data.js)
import { createAmbientVisitors } from './ambientVisitors.js';
import {
  watchTarget,
  createWatchState,
  isHummingMood,
  humDelaySec,
  humNoteCount,
  HUM,
} from './ambientLife.data.js';
import { prefersReducedMotion } from '../ui/ui.js'; // V6/F2: hum notes are motion
import {
  disableGyro,
  isGyroEnabled,
  setGyroSceneActive,
  syncGyroSetting,
  updateGyroParallax,
} from '../systems/gyroParallax.js';

export { HOME_ASSET_KEYS } from './roomManager.js';

/** Backdrop behind/around the room shells (warm pastel, §D5 vibes). */
const BACKDROP_DAY = '#F3DFC8';
const BACKDROP_NIGHT = '#232A44';

// --- V2/G26 (§C10.2): backdrop tone per band × weather -----------------------
// The scene.background peeks around the room shells; it follows the band
// (sleep night-mode still forces BACKDROP_NIGHT — §B3 override wins) and
// darkens slightly under cloud/rain like the garden grass tint does.
const BACKDROP_BAND = Object.freeze({
  day: BACKDROP_DAY,
  dawn: '#F6E4CB',
  dusk: '#DEBBAE',
  night: BACKDROP_NIGHT,
});
const BACKDROP_WEATHER_MULT = Object.freeze({ clear: 1, cloudy: 0.93, rain: 0.86 });
/** Pre-mixed backdrop colors (band:weather → THREE.Color, no per-frame alloc). */
const BACKDROP_COLORS = (() => {
  const map = new Map();
  for (const [band, hex] of Object.entries(BACKDROP_BAND)) {
    for (const [wx, mult] of Object.entries(BACKDROP_WEATHER_MULT)) {
      map.set(`${band}:${wx}`, new THREE.Color(hex).multiplyScalar(mult));
    }
  }
  map.set('sleep', new THREE.Color(BACKDROP_NIGHT));
  return map;
})();

/** §C10.3: night yawns every 45 ± 15 s (while awake, outside sleep mode). */
const NIGHT_YAWN_BASE_SEC = 45;
const NIGHT_YAWN_JITTER_SEC = 15;
/** §C10.3: night eyelid bias. */
const NIGHT_LIDS_BIAS = 0.3;
/** §C10.2 lamp table value (0.5) × the §D4 physical point-light scale (14). */
const LAMP_PHYS_SCALE = 14;
// --- end V2/G26 ---------------------------------------------------------------

/** @type {ReturnType<typeof createHomeScene>|null} live instance (module accessors) */
let activeInstance = null;

/** @returns {object|null} the live Gooby rig (§D2.3) — null outside the home scene */
export function getGooby() {
  return activeInstance?.getGooby() ?? null;
}

/** @returns {object|null} the live room manager — null outside the home scene */
export function getRoomManager() {
  return activeInstance?.getRoomManager() ?? null;
}

/** @returns {THREE.PerspectiveCamera|null} the live home camera — null outside the home scene */
export function getCamera() {
  return activeInstance?.camera ?? null;
}

/**
 * Toggle bedroom night mode (§D4). No-op outside the home scene.
 * @param {boolean} on
 */
export function setNight(on) {
  activeInstance?.setNight(on);
}

/** @returns {boolean} current night-mode target (false outside the home scene) */
export function isNight() {
  return activeInstance?.isNight() ?? false;
}

/**
 * §E1 scene factory for the persistent home.
 * @param {{renderer: THREE.WebGLRenderer, assets: object, input: object, audio: object, store: object, ui: object}} ctx
 */
export function createHomeScene(ctx) {
  const { renderer, assets, input, store, ui } = ctx;

  const scene = new THREE.Scene();
  scene.background = new THREE.Color(BACKDROP_DAY);

  const camera = new THREE.PerspectiveCamera(ROOMS.CAMERA_FOV, innerWidth / innerHeight, 0.1, 60);

  // Single 1024 px shadow map lives in the home scene only (§D4/§E10).
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;

  const lights = createHomeLights(scene);
  const particles = createParticles(scene);

  /** Built lazily in enter() — furniture GLBs must be preloaded first. */
  let rm = null;
  let gooby = null;
  let roomNav = null;

  // room-hop state (§C2: Gooby hops along on room change)
  let hopTimer = -1;
  // transient look-at release
  let lookTimer = 0;
  // day/night background blend (V2/G26: target follows the band table now)
  let night = false;

  // --- V2/G26: ambience state (§C10/§C11) -----------------------------------
  /** last applied band/weather (mirrors rm.getAmbience once rm exists) */
  const amb = { band: 'day', weather: 'clear' };
  /** @type {ReturnType<typeof createEmotionMachine>|null} for setNightBias */
  let ambMachine = null;
  /** dusk/night auto-on lamps (§C10.2: living + bedroom, #FFD9A0 × 0.5) */
  /** @type {THREE.PointLight[]} */
  const ambLamps = [];
  /** @type {ReturnType<typeof mountGardenRain>|null} */
  let rainFx = null;
  /** @type {ReturnType<typeof mountGardenClouds>|null} */
  let cloudFx = null;
  /** @type {ReturnType<typeof createAmbientLife>|null} V6/A3 ambient life */
  let ambient = null;
  /** @type {ReturnType<typeof createAmbientVisitors>|null} V6/F2 garden bird */
  let visitors = null;

  // --- V6/F2: Gooby watches the ambient life -------------------------------
  // Decision state for the pure watchTarget() hysteresis (ambientLife.data.js)
  // — evaluated on a fixed ~0.25 s cadence, not per frame.
  let watchState = createWatchState();
  let watchTick = 0;
  /** a watch target currently drives gooby.lookAt (release bookkeeping) */
  let watching = false;
  /** alternate the periodic happy beat: blink ↔ subtle ear/body twitch */
  let twitchFlip = false;
  /** >0 while the content-blink lids pulse runs (restores the night bias) */
  let blinkT = 0;
  const WATCH_TICK_SEC = 0.25;
  /** reused candidate list (entries are cached by their owners — no alloc) */
  const watchCandidates = [];
  const watchGoobyPos = new THREE.Vector3();

  // --- V6/F2: happy-idle humming --------------------------------------------
  /** seconds until the next hum (0 = scheduler idle, waits for a happy idle) */
  let humIn = 0;
  /** previous "happy + idle" sample — a fresh happy spell re-seeds sooner */
  let humWasHappy = false;
  /** notes still to emit for the current hum (staggered, melody-like) */
  let humNotesLeft = 0;
  let humNoteIn = 0;
  const humNotePos = new THREE.Vector3();
  /** §C10.3 night yawn countdown (0 = timer off) */
  let yawnIn = 0;
  /** §C11.2: Gooby is parked under the garden tree canopy during rain */
  let canopySitting = false;
  /** canopy set an emotion context we must clear on release */
  let canopyContext = false;

  const nextYawnIn = () =>
    NIGHT_YAWN_BASE_SEC + (Math.random() * 2 - 1) * NIGHT_YAWN_JITTER_SEC;

  /** night band + actually awake (sleep mode/state overrides — §C10.3) */
  function isNightAwake() {
    return amb.band === 'night' && !night && !store.get('sleep')?.sleeping;
  }

  /**
   * Apply the current band/weather everywhere: light rig, room manager
   * (window skies + garden dome/grass), backdrop target, lamps, weather FX,
   * ambient loops and Gooby's night presentation (§C10.2/§C10.3/§C11.2).
   * Runs on 'dayBandChanged'/'weatherChanged'/'sleepChanged', on room switch
   * and once at enter() (instant).
   * @param {{instant?: boolean}} [opts]
   */
  function applyAmbienceNow(opts = {}) {
    const ms = now();
    const bandInfo = bandAt(ms);
    const wx = weatherAt(ms);
    amb.band = bandInfo.band;
    amb.weather = wx.state;

    lights.applyAmbience({ band: amb.band, weather: amb.weather, blend: bandInfo.blend, instant: opts.instant });
    rm?.setAmbience({ band: amb.band, weather: amb.weather, blend: bandInfo.blend });
    if (opts.instant) scene.background.copy(backdropTarget());

    // §C10.2: warm lamps auto-on at dusk/night (sleep mode has its own lamp)
    const lampsOn = !!DAYNIGHT[amb.band]?.lampsOn && !night;
    for (const l of ambLamps) {
      l.visible = lampsOn;
      l.intensity = lampsOn ? (DAYNIGHT[amb.band].lampIntensity ?? 0.5) * LAMP_PHYS_SCALE : 0;
    }

    // §C11.2 weather FX fade in/out with their state
    rainFx?.setActive(amb.weather === 'rain');
    cloudFx?.setActive(amb.weather === 'cloudy');
    ambient?.setConditions(amb.band, amb.weather); // V6/A3: band/weather row swap
    visitors?.setConditions(amb.band, amb.weather); // V6/F2: bird visitor gates

    refreshAmbientAudio();

    // §C10.3 night presentation (no stat effect)
    const nightAwake = isNightAwake();
    gooby?.setLidsBias(nightAwake ? NIGHT_LIDS_BIAS : 0);
    ambMachine?.setNightBias(nightAwake);
    gooby?.setRainWatch?.(amb.weather === 'rain' && !night); // V2/G29 (§C11.2): rain-watching idle flavor
    if (nightAwake && yawnIn <= 0) yawnIn = nextYawnIn();
    if (!nightAwake) yawnIn = 0;
  }

  /** @returns {THREE.Color} the shared pre-mixed backdrop color target */
  function backdropTarget() {
    return (night ? BACKDROP_COLORS.get('sleep') : BACKDROP_COLORS.get(`${amb.band}:${amb.weather}`))
      ?? BACKDROP_COLORS.get('day:clear');
  }

  /** Rain loop + dawn birdsong live in the garden only (§C11.2/§C10.2). */
  function refreshAmbientAudio() {
    const inGarden = rm?.activeRoom() === 'garden';
    if (amb.weather === 'rain' && inGarden) ctx.audio?.play?.('ambience.rain');
    else ctx.audio?.stop?.('ambience.rain');
    if (amb.band === 'dawn' && inGarden && !night) ctx.audio?.play?.('ambience.birdsong');
    else ctx.audio?.stop?.('ambience.birdsong');
  }

  /**
   * §C11.2: while it rains and the garden is the active room, Gooby contently
   * sits under the tree canopy (pure coziness). Checked per-frame (cheap) so
   * it engages after the room-hop lands and releases when the rain block or
   * the room changes.
   */
  function refreshCanopy() {
    const want = amb.weather === 'rain'
      && rm?.activeRoom() === 'garden'
      && !rm.isPanning() && hopTimer <= 0
      && !!gooby && !store.get('sleep')?.sleeping;
    if (want && !canopySitting) {
      const at = rm.getAnchor('canopySit', 'garden');
      if (!at) return;
      canopySitting = true;
      gooby.group.position.copy(at);
      gooby.group.rotation.y = 0.3; // angled out from under the tree
      gooby.play('sitDrive'); // seated pose, holds until stop()
      if (ambMachine && ambMachine.getContext() == null) {
        ambMachine.setContext('happy'); // "contently"
        canopyContext = true;
      }
    } else if (!want && canopySitting) {
      canopySitting = false;
      gooby.stop('sitDrive');
      gooby.group.rotation.y = 0;
      if (canopyContext) {
        canopyContext = false;
        if (ambMachine?.getContext() === 'happy') ambMachine.setContext(null);
      }
      // rain ended while still gardening → back to the idle spot
      if (rm?.activeRoom() === 'garden' && !rm.isPanning()) placeGooby('garden');
    }
  }
  // --- end V2/G26 -------------------------------------------------------------

  // --- V6/F2: Gooby watches + hums (living-world micro-reactions) -------------

  /**
   * Gooby counts as ambient-idle when ONLY the auto-idle runs: not mid-hop or
   * mid-pan, no interaction clip (pet/tickle/eat/wash all replace 'idle'),
   * not sleeping, not parked under the rain canopy, and actually visible
   * (the vacation flow hides the group).
   */
  function goobyAmbientIdle() {
    return !!gooby && gooby.group.visible && gooby.isPlaying('idle')
      && !canopySitting && hopTimer <= 0 && !rm?.isPanning()
      && !store.get('sleep')?.sleeping;
  }

  /**
   * The periodic happy beat while a watch runs (WATCH.TWITCH_EVERY_SEC):
   * alternates a content squint-blink (lids pulse, max-combined so droopier
   * faces are untouched) with a subtle ear/body twitch (pokeWobble is an
   * overlay clip — the idle keeps running underneath).
   */
  function happyWatchBeat() {
    twitchFlip = !twitchFlip;
    if (twitchFlip) {
      blinkT = 0.14;
      gooby.setLidsBias(1.0);
    } else {
      gooby.play('pokeWobble', { dir: { x: 0.5, z: 0.25 } });
    }
  }

  /**
   * Fixed-cadence watch decision (V6/F2): collects the live candidates
   * (A3 flutter butterflies/bee + the F2 bird in its perch phase) and lets
   * the pure watchTarget() hysteresis drive the clamped gooby.lookAt().
   * Tap-look (lookTimer) always wins; any non-idle state releases instantly.
   */
  function updateWatch() {
    if (!goobyAmbientIdle() || lookTimer > 0) {
      if (watching) {
        watching = false;
        gooby?.lookAt(null);
      }
      watchState = createWatchState();
      return;
    }
    watchCandidates.length = 0;
    for (const w of ambient?.getWatchables() ?? []) watchCandidates.push(w);
    const birdWatch = visitors?.getWatchable();
    if (birdWatch) watchCandidates.push(birdWatch);
    watchGoobyPos.copy(gooby.group.position);
    watchGoobyPos.y += 0.5; // head height — good enough for radius checks
    const res = watchTarget(watchGoobyPos, watchCandidates, watchState, WATCH_TICK_SEC);
    watchState = res.state;
    if (res.target) {
      watching = true;
      gooby.lookAt(res.target.pos);
      if (res.twitched) happyWatchBeat();
    } else if (watching) {
      watching = false;
      gooby.lookAt(null);
    }
  }

  /**
   * Happy-idle hum scheduler (V6/F2): while the emotion machine sits in a
   * humming mood (happy/ecstatic — HUM.MOODS) AND Gooby is ambient-idle, a
   * soft 'gooby.purr' plays every HUM.DELAY range with 2–3 authored note
   * particles staggered above his head. Notes are motion → skipped entirely
   * under prefers-reduced-motion (the purr stays: audio isn't motion, and
   * the OS setting doesn't ask us to mute).
   */
  function updateHum(dt) {
    const happy = goobyAmbientIdle() && isHummingMood(ambMachine?.get?.() ?? '');
    if (happy && !humWasHappy) humIn = humDelaySec(Math.random, { first: true });
    humWasHappy = happy;
    if (happy) {
      humIn -= dt;
      if (humIn <= 0) {
        humIn = humDelaySec(Math.random);
        ctx.audio?.play?.('gooby.purr'); // the hum voice: soft content purr
        if (!prefersReducedMotion()) {
          humNotesLeft = humNoteCount(Math.random);
          humNoteIn = 0; // first note lands this frame
        }
      }
    }
    if (humNotesLeft > 0) {
      humNoteIn -= dt;
      if (humNoteIn <= 0) {
        humNoteIn = HUM.NOTE_SPACING_SEC;
        humNotesLeft -= 1;
        humNotePos.copy(gooby.group.position);
        humNotePos.y += 0.62; // just above the head
        humNotePos.x += (Math.random() - 0.5) * 0.14;
        humNotePos.z += 0.06;
        particles.emit('notes', humNotePos, { count: 1 });
      }
    }
  }
  // --- end V6/F2 ---------------------------------------------------------------

  /** @type {Array<() => void>} store/input unsubscribers */
  const subs = [];

  // --- V4/G60: home-only gyro/pointer camera parallax (§B8/§C-SYS8) --------
  // roomManager does not rewrite the settled camera every frame, so remove
  // exactly the offset applied on the previous frame before it updates/pans.
  // Adding the new offset AFTER rm.update preserves its fixed look-at rotation:
  // this is a pure translation, never a nausea-inducing camera rotation.
  let appliedParallaxX = 0;
  let appliedParallaxY = 0;

  function removeAppliedParallax() {
    if (appliedParallaxX === 0 && appliedParallaxY === 0) return;
    camera.position.x -= appliedParallaxX;
    camera.position.y -= appliedParallaxY;
    appliedParallaxX = 0;
    appliedParallaxY = 0;
  }

  function parallaxSuppressed() {
    if (ui.activeScreenId?.()) return true;
    if (ui.el?.querySelector?.('.panel-backdrop,.g23-ph-layer,.g5-wash,.g5-ghost')) return true;
    // Care walk-tos use jump/happyBounce in interactions.js; room pans also
    // force zero so camera motions never stack.
    return !!rm?.isPanning?.()
      || !!gooby?.isPlaying?.('jump')
      || !!gooby?.isPlaying?.('happyBounce');
  }

  function applyParallax(dt) {
    if (!isGyroEnabled()) return; // strict OFF: no DOM query / per-frame engine work
    const offset = updateGyroParallax(dt, parallaxSuppressed());
    camera.position.x += offset.x;
    camera.position.y += offset.y;
    appliedParallaxX = offset.x;
    appliedParallaxY = offset.y;
  }
  // --- end V4/G60 -----------------------------------------------------------

  // dev draw-call readout (§E10 budget check: home ≤ 120 calls)
  /** @type {HTMLElement|null} */
  let debugEl = null;
  let debugTimer = 0;
  let debugLogged = false;

  function placeGooby(roomId) {
    const at = rm.getAnchor('goobyIdle', roomId);
    if (at) gooby.group.position.copy(at);
    gooby.group.rotation.y = 0; // face the camera
  }

  function refreshEmotionInputs(machine) {
    const state = store.get();
    machine.setStats(state.stats);
    // currentMood (systems/sleep.js) is the canonical mood reader: it applies
    // the §C1.4 early-wake grumpy debuff (−15 while grumpyUntil is active) and
    // clamps to the valid 0–100 range.
    machine.setMood(currentMood(state, now()));
  }

  const api = {
    scene,
    camera,

    // --- sibling integration surface (see module JSDoc) ---
    getGooby: () => gooby,
    getRoomManager: () => rm,

    /**
     * Bedroom night mode (§D4): lerp the lighting rig, warm lamp point light,
     * night window sky and backdrop. G6's sleep flow calls this.
     * @param {boolean} on
     */
    setNight(on) {
      night = !!on;
      lights.setNight(night);
      rm?.setNightSky(night);
      applyAmbienceNow(); // V2/G26: lamps/backdrop/§C10.3 flags re-evaluate
    },

    /** @returns {boolean} */
    isNight: () => night,

    async enter(params = {}) {
      ctx.audio?.music?.('home'); // G14: lo-fi home loop (§D6; starts post-gesture)
      // V4/G60: strict feature-detect for the same-wave save slice. This
      // restore path never prompts; G58 calls enableGyro() in the toggle tap.
      setGyroSceneActive(true);
      let gyroSetting = store.get('settings.gyro') === true;
      syncGyroSetting(gyroSetting);
      subs.push(store.on('change', () => {
        const next = store.get('settings.gyro') === true;
        if (next === gyroSetting) return;
        gyroSetting = next;
        if (next) syncGyroSetting(true);
        else disableGyro();
      }));
      // --- build the rooms (models are preloaded by the scene manager) ---
      rm = createRoomManager({ scene, camera, assets, store });

      gooby = createGooby({ particles });
      // Real shadows in the home (§D4): Gooby casts, the blob shadow rests.
      gooby.group.traverse((obj) => {
        if (obj.isMesh && obj.name !== 'blobShadow') obj.castShadow = true;
        if (obj.name === 'blobShadow') obj.visible = false;
      });
      scene.add(gooby.group);
      rm.setGoobyTarget(gooby.group);

      // V2 fix: validate params.room against the 5-room NAV_ORDER (incl. the
      // garden) — the frozen v1 ROOMS.ORDER silently dropped ?room=garden.
      // goTo refuses a padlocked garden (§B6), so re-read the room it landed on.
      const wantRoom = NAV_ORDER.includes(params.room) ? params.room : ROOMS.DEFAULT;
      rm.goTo(wantRoom, { instant: true });
      const startRoom = rm.activeRoom();
      placeGooby(startRoom);
      lights.setFocus(rm.roomCenterX(startRoom));
      const lampAt = rm.getAnchor('lamp', 'bedroom');
      if (lampAt) lights.setLampPosition(lampAt);

      // --- V2/G26: ambience wiring (§C10.2/§C11.2) --------------------------
      // Warm dusk/night lamps (§C10.2: living + bedroom, #FFD9A0 0.5): the
      // living light sits at the floor-lamp decor spot, the bedroom one over
      // the nightstand lamp anchor. Off until applyAmbienceNow enables them.
      const lampSpecs = [
        // V6/FIX4 (P1-7): anchored under the living ceiling fixture
        // (rooms/living.js lampSquareCeiling at [0, 2.7, −0.18], with the
        // `ceilingLampGlow` dressing bulb at its shade mouth) — dead-center
        // of the portrait frame. The old spot (x −1.82, z −1.36) was the
        // pre-V4 floor-lamp corner — nothing stands there now, so the warm
        // pool read as floating on a bare wall.
        { x: rm.roomCenterX('living'), y: 2.3, z: -0.18 },
        lampAt ? { x: lampAt.x, y: lampAt.y + 0.35, z: lampAt.z + 0.25 } : null,
      ];
      for (const at of lampSpecs) {
        if (!at) continue;
        const l = new THREE.PointLight(DAYNIGHT.dusk.lampColor, 0, 4.5, 2);
        l.name = 'ambienceLamp';
        l.visible = false;
        l.position.set(at.x, at.y, at.z);
        scene.add(l);
        ambLamps.push(l);
      }
      // Garden weather FX (both ONE draw call each, invisible while inactive)
      const gardenGroup = rm.getRoomGroup('garden');
      if (gardenGroup) {
        rainFx = mountGardenRain(gardenGroup);
        cloudFx = mountGardenClouds(gardenGroup);
      }
      // --- end V2/G26 --------------------------------------------------------

      // ---- V6/A3: batched ambient life (≤4 draw batches per room) ----------
      // Mount/dispose per room rides rm's 'roomChanged' event internally;
      // band/weather gating arrives via the applyAmbienceNow() hook below
      // (first push happens at the instant applyAmbienceNow in this enter()).
      // No-op under reduced motion; ticked from update(dt) so it pauses with
      // the RAF loop.
      ambient = createAmbientLife({ rm });
      // ---- end V6/A3 ---------------------------------------------------------

      // ---- V6/F2: transient garden bird visitor ------------------------------
      // Clock-hashed schedule + garden/daytime/dry gates live in
      // ambientLife.data.js (VISITOR); the manager mounts the pretty-park
      // bird GLB only while a visit is live, despawns on room switch, and
      // no-ops under reduced motion. Same setConditions/update/dispose
      // cadence as ambient above.
      visitors = createAmbientVisitors({ rm });
      // ---- end V6/F2 ---------------------------------------------------------

      // --- emotion follows the store mood (§C1 bands via emotions.js) ---
      const machine = createEmotionMachine();
      machine.onChange((id) => gooby.setEmotion(id));
      refreshEmotionInputs(machine);
      // V2/G20: sick mood cap 39 (§C3.4) — health state feeds the machine
      machine.setHealth?.(store.get('health.state'));
      subs.push(store.on('healthChanged', (h) => machine.setHealth?.(h?.state)));
      // end V2/G20
      gooby.setEmotion(machine.get());
      ambMachine = machine; // V2/G26: night sleepy-tie bias hook (§C10.3)
      subs.push(store.on('statsChanged', () => refreshEmotionInputs(machine)));
      // sleep transitions set/clear grumpyUntil without touching stats — refresh
      // so the §C1.4 grumpy face shows immediately after an early wake.
      subs.push(store.on('sleepChanged', (sleep) => {
        refreshEmotionInputs(machine);
        // F6 (RE4): the sleep flow poses the 'sleepy' face DIRECTLY on the rig
        // (bypassing the machine), so onChange won't fire when the mood band
        // is unchanged across the nap — force-apply the machine's emotion on
        // wake so the sleepy face can never stick.
        if (!sleep?.sleeping) gooby.setEmotion(machine.get());
      }));

      // --- room navigation: arrows + dots (ui/roomNav.js) + swipe ---
      roomNav = createRoomNav({ onNavigate: (roomId) => api.goToRoom(roomId) });
      roomNav.mount(ui.el);
      roomNav.setActive(startRoom);
      subs.push(rm.on('roomChanged', ({ roomId }) => {
        roomNav.setActive(roomId);
        lights.setFocus(rm.roomCenterX(roomId));
        // Gooby hops along: hop out now, teleport mid-pan, land in the room.
        gooby.play('jump');
        hopTimer = ROOMS.PAN_SEC / 2;
      }));

      // --- V2/G26: ambience event wiring (§B4) -------------------------------
      // G20's 60 s timeEngine ticker emits these on band/weather changes (and
      // once at boot); room switches re-apply (garden-only audio/FX), and
      // sleep transitions re-evaluate the §C10.3 night-awake presentation.
      subs.push(store.on('dayBandChanged', () => applyAmbienceNow()));
      subs.push(store.on('weatherChanged', () => applyAmbienceNow()));
      subs.push(rm.on('roomChanged', () => applyAmbienceNow()));
      subs.push(store.on('sleepChanged', () => applyAmbienceNow()));
      applyAmbienceNow({ instant: true }); // first paint: no crossfade pop
      // --- end V2/G26 ---------------------------------------------------------

      // Swipe on empty space pans rooms (§C2). Swipes that start on Gooby are
      // reserved for G5's pet/tickle gestures.
      let swipeBlocked = false;
      subs.push(input.on('dragstart', (p) => {
        swipeBlocked = !!input.pick(camera, [gooby.group], p);
      }));
      subs.push(input.on('swipe', (p) => {
        if (swipeBlocked || rm.isPanning()) return;
        if (p.dir !== 'left' && p.dir !== 'right') return;
        const idx = ROOMS.ORDER.indexOf(rm.activeRoom()) + (p.dir === 'left' ? 1 : -1);
        if (idx >= 0 && idx < ROOMS.ORDER.length) api.goToRoom(ROOMS.ORDER[idx]);
      }));

      // Taps → fixed-interactable events (G5/G6 subscribe via getRoomManager).
      subs.push(input.on('tap', (p) => {
        rm.handleTap(p);
        // Gooby is alive: he watches where you touched for a moment.
        const at = new THREE.Vector3(p.nx, p.ny, 0.5).unproject(camera);
        gooby.lookAt(at);
        lookTimer = 1.4;
      }));

      // dev-only corner draw-call readout (§E10: home budget ≤ 120)
      if (import.meta.env?.DEV) {
        debugEl = document.createElement('div');
        // POLISH-F: var(--safe-top) (not raw env()) so the §B9 fake-notch
        // reaches it, and z below --z-hud (40) so it never paints over the
        // stat pills it used to cover at 320-375px widths.
        // V4/FIX-UI: z-below alone still BLED THROUGH the translucent --frost
        // stat pill at 320px — the throttled update() block below additionally
        // re-anchors the chip under the measured HUD top block, so it never
        // sits behind any stat/coin chrome at any scale/viewport.
        debugEl.style.cssText =
          'position:absolute;left:8px;top:calc(8px + var(--safe-top,0px));' +
          'z-index:calc(var(--z-hud) - 10);' +
          'font:700 11px system-ui;color:#4A3B36;background:rgba(255,255,255,.6);' +
          'padding:2px 7px;border-radius:8px;pointer-events:none;';
        ui.el.appendChild(debugEl);
      }
    },

    /**
     * Pan to a room (0.35 s ease — §C2). Delegates to the room manager.
     * @param {string} roomId
     * @param {{instant?: boolean}} [opts]
     */
    goToRoom(roomId, opts = {}) {
      rm?.goTo(roomId, opts);
      if (opts.instant && rm && gooby) placeGooby(roomId);
    },

    update(dt) {
      removeAppliedParallax(); // V4/G60: recover roomManager's base camera
      rm?.update(dt);
      applyParallax(dt); // V4/G60: home camera only; minigame cameras untouched
      lights.update(dt);
      particles.update(dt);
      updateWeatherFx(dt); // V2/G26 (§C11.2): rain/clouds/window streaks
      ambient?.update(dt); // V6/A3: ambient life (pauses with the RAF loop)
      visitors?.update(dt); // V6/F2: bird visitor poll (stateless wall-clock)

      if (gooby) {
        gooby.update(dt);
        if (hopTimer > 0) {
          hopTimer -= dt;
          if (hopTimer <= 0) placeGooby(rm.activeRoom());
        }
        if (lookTimer > 0) {
          lookTimer -= dt;
          if (lookTimer <= 0) gooby.lookAt(null);
        }

        // V6/F2: watch decision (fixed ~0.25 s cadence) + hum scheduler +
        // the content-blink release (restores the §C10.3 night lids bias)
        watchTick -= dt;
        if (watchTick <= 0) {
          watchTick = WATCH_TICK_SEC;
          updateWatch();
        }
        updateHum(dt);
        if (blinkT > 0) {
          blinkT -= dt;
          if (blinkT <= 0) gooby.setLidsBias(isNightAwake() ? NIGHT_LIDS_BIAS : 0);
        }

        // V2/G26 (§C10.3): night yawns every 45±15 s while awake + idle
        if (yawnIn > 0) {
          yawnIn -= dt;
          if (yawnIn <= 0) {
            yawnIn = nextYawnIn();
            if (isNightAwake() && gooby.isPlaying('idle') && !canopySitting) {
              gooby.play('wake'); // stretch + big yawn clip (§D2.4)
              ctx.audio?.play?.('gooby.yawn');
            }
          }
        }
        // V2/G26 (§C11.2): garden-rain canopy sit engages/releases here
        refreshCanopy();
      }

      // backdrop follows the band table + sleep night mode (V2/G26 §C10.2)
      scene.background.lerp(backdropTarget(), Math.min(1, dt * 3));

      if (debugEl) {
        debugTimer -= dt;
        if (debugTimer <= 0 && renderer.info.render.calls > 0) {
          debugTimer = 0.5;
          debugEl.textContent = `${renderer.info.render.calls} calls · ${Math.round(renderer.info.render.triangles / 1000)}k tris`;
          // V4/FIX-UI: anchor the chip just BELOW the HUD stat/coin chrome
          // (the coins+ring meta row — the last full-width top-block row) so
          // it can never bleed through the translucent pills — measured on
          // the same 0.5 s throttle, robust across uiScale/viewport/notch/
          // pill-wrap combinations. The centered g76 modifier row below it
          // starts well right of this left-edge chip, and the left room-nav
          // arrow (mid-screen) stays clear too.
          const hudMeta = ui.el.querySelector('.g5-hud:not(.g5-hud-hidden) .g5-hud-meta');
          if (hudMeta) {
            const uiTop = ui.el.getBoundingClientRect().top;
            debugEl.style.top = `${Math.round(hudMeta.getBoundingClientRect().bottom - uiTop) + 4}px`;
          }
          if (!debugLogged && renderer.info.render.calls > 0) {
            debugLogged = true;
            console.log(`[home] draw calls: ${renderer.info.render.calls}, triangles: ${renderer.info.render.triangles} (budget: 120 calls / 150k tris, §E10) @ ${new Date(now()).toISOString()}`);
          }
        }
      }
    },

    exit() {
      ctx.audio?.music?.(null); // G14: stop the home loop when leaving home
      removeAppliedParallax(); // V4/G60: never leak a translated camera
      setGyroSceneActive(false); // detaches listeners throughout minigames
      // V2/G26: ambient loops are home-scoped — stop them when leaving
      ctx.audio?.stop?.('ambience.rain');
      ctx.audio?.stop?.('ambience.birdsong');
      roomNav?.unmount();
      roomNav = null;
      debugEl?.remove();
      debugEl = null;
      for (const unsub of subs) unsub();
      subs.length = 0;
    },

    dispose() {
      if (activeInstance === api) activeInstance = null;
      renderer.shadowMap.enabled = false; // shadows are home-only (§D4)
      // V2/G26: weather FX + ambience lamps
      rainFx?.dispose();
      rainFx = null;
      cloudFx?.dispose();
      cloudFx = null;
      for (const l of ambLamps) {
        scene.remove(l);
        l.dispose();
      }
      ambLamps.length = 0;
      ambMachine = null;
      // end V2/G26
      // V6/A3: ambient life tears down before the room manager frees groups
      ambient?.dispose();
      ambient = null;
      // end V6/A3
      // V6/F2: bird visitor despawns before the room manager frees groups
      visitors?.dispose();
      visitors = null;
      // end V6/F2
      gooby?.dispose();
      gooby = null;
      particles.dispose();
      rm?.dispose();
      rm = null;
      lights.dispose();
    },
  };

  activeInstance = api;
  return api;
}
