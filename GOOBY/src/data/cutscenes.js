// V6/A1 — authored cutscene scripts (PLAN6 Wave A/A1). PURE DATA — no
// DOM/three imports; node-tested by test/cutscene.test.js (every script must
// compile via systems/cutscene.js compileScript, and every clip/emotion/sfx/
// particle/caption id is validated against the real registries by the
// data-mirror test — the onboarding source scanner cannot see these
// data-driven ids).
//
// Script shape (validated by compileScript — see systems/cutscene.js):
//   { id, steps: [ { op, ...fields, keepOnSkip? } ] }
// Ops: camera(move,duration) · clip(clip) · emotion(emotion) ·
//   particles(type,count,anchor?) · caption(key) · captionClear · sfx(sfx) ·
//   prop(action,propId,model?,anchor?,offset?,scale?) · wait(duration) ·
//   tapWait(timeout) · sequence(steps) · parallel(steps)
// keepOnSkip:true ops still apply when the player skips — use it for
// final-state ops (closing emotion, reward stinger) so a skipped cutscene
// lands in the same end state as a watched one.
//
// Later waves (D1 vacation set pieces) append their scripts here — keep ids
// short, kebab-free and unique; CUTSCENE_IDS below bounds the persisted
// seen map, so removing an id silently drops its seen flag (by design).

/**
 * @typedef {{op: string, keepOnSkip?: boolean}} CutsceneStep
 * @typedef {{id: string, steps: CutsceneStep[]}} CutsceneScript
 */

/** @type {Readonly<Record<string, CutsceneScript>>} */
export const CUTSCENES = Object.freeze({
  // The harness demo (?cutscene=demo): Gooby at home — camera push-in, a
  // wave + happy beat with sparkles and a caption, a tap-to-continue pause,
  // then a hearts goodbye and the camera easing back. The closing emotion +
  // stinger are keepOnSkip so a skip still lands on a happy Gooby.
  demo: Object.freeze({
    id: 'demo',
    steps: Object.freeze([
      Object.freeze({ op: 'camera', move: 'pushIn', duration: 1.6 }),
      Object.freeze({
        op: 'parallel',
        steps: Object.freeze([
          Object.freeze({ op: 'emotion', emotion: 'happy' }),
          Object.freeze({ op: 'clip', clip: 'wave' }),
          Object.freeze({ op: 'sfx', sfx: 'gooby.squeakHappy' }),
          Object.freeze({ op: 'particles', type: 'sparkles', count: 12 }),
          Object.freeze({ op: 'caption', key: 'cutscene.demo.hello' }),
          Object.freeze({ op: 'wait', duration: 1.4 }),
        ]),
      }),
      Object.freeze({ op: 'tapWait', timeout: 8 }),
      Object.freeze({ op: 'caption', key: 'cutscene.demo.bye' }),
      Object.freeze({
        op: 'parallel',
        steps: Object.freeze([
          Object.freeze({ op: 'clip', clip: 'happyBounce' }),
          Object.freeze({ op: 'particles', type: 'hearts', count: 6 }),
          Object.freeze({ op: 'wait', duration: 1.2 }),
        ]),
      }),
      Object.freeze({ op: 'captionClear' }),
      Object.freeze({ op: 'camera', move: 'restore', duration: 1.0 }),
      Object.freeze({ op: 'emotion', emotion: 'happy', keepOnSkip: true }),
      Object.freeze({ op: 'sfx', sfx: 'jingle.short', keepOnSkip: true }),
    ]),
  }),

  // ── V6/D1 (PLAN6 Wave D/D1): vacation set pieces ──────────────────────────
  // Staged by src/vacation/vacationCinematic.js from the EXPLICIT user
  // actions in ui/airportScreen.js (book / pick up / pay taxi) — never from
  // phase observation, so none of these can replay on boot. Captions live in
  // strings/v6-vacation-scenes.js (EN+DE; import committed by D2). Props use
  // committed GLBs only: 'car-kit/taxi' (kenney), Tiny Treats
  // 'pleasant-picnic/picnic_basket_square' as Gooby's cute strap-case, and —
  // since no plane GLB exists on disk (verified) — the stylized
  // 'plane in the sky' beat spawns 'space-kit/craft_speederA' with a sparkle
  // trail.
  //
  // V6/FIX2 restaging (post-eval P1-1): every beat now SHOWS what its caption
  // narrates inside the 390×844 portrait frame, using the cutsceneView
  // staging capabilities (all compile-valid ops — systems/cutscene.js is
  // untouched):
  //   · 'cs:doorway'/'cs:sky' anchors — view-computed stage marks that exist
  //     in every room (the living room resolves its real frontDoor);
  //   · 'cam:*' propIds — virtual camera-rig cuts: spawn pans/dollies to the
  //     anchored point (scale = dolly fraction), despawn eases back;
  //   · re-spawning a live propId GLIDES it to the new mark (prop moves);
  //   · 'prop:<id>' particle anchors — sparkle trails track a gliding prop.
  // Gooby-relative offsets (no anchor) remain for the beats that play around
  // Gooby himself, so the staging still works in whichever room he idles.

  // The booking send-off, beat table (V6/FIX2):
  //   1 PACK    full room frame — suitcase plops down center-low by Gooby,
  //             happy bounce ("Suitcase packed!")
  //   2 TAXI    doorway vignette — camera pans to the front door, the taxi
  //             pulls up AT the doorway, doorbell + engine cues ("The taxi
  //             is here")
  //   3 WAVE    camera returns — Gooby waves while the suitcase glides over
  //             to the taxi ("Bye-bye!")
  //   4 DEPART  taxi + case vanish behind a whoosh + doorway sparkle burst
  //   5 SKY     camera tilts up the back wall — the tiny plane crosses the
  //             frame trailing sparkles ("up, up and away!" over a VISIBLE
  //             plane)
  //   6 POSTCARDS camera eases home, closing promise + stinger
  // Rewards/state are already committed by economy.bookVacation BEFORE this
  // plays (decoration only).
  vacDeparture: Object.freeze({
    id: 'vacDeparture',
    steps: Object.freeze([
      // 1 PACK — no push-in: the lease frame keeps Gooby AND the floor spot
      // in view; the case lands center-low, fully in frame.
      Object.freeze({
        op: 'parallel',
        steps: Object.freeze([
          Object.freeze({
            op: 'prop', action: 'spawn', propId: 'vacSuitcase',
            model: 'pleasant-picnic/picnic_basket_square',
            offset: Object.freeze([0.55, 0, 0.5]), scale: 0.5,
          }),
          Object.freeze({ op: 'sfx', sfx: 'ball.bounce' }),
          Object.freeze({ op: 'emotion', emotion: 'happy' }),
          Object.freeze({ op: 'clip', clip: 'happyBounce' }),
          Object.freeze({ op: 'particles', type: 'sparkles', count: 10 }),
          Object.freeze({ op: 'caption', key: 'cutscene.vac.depart.pack' }),
          Object.freeze({ op: 'wait', duration: 1.2 }),
        ]),
      }),
      Object.freeze({ op: 'tapWait', timeout: 6 }),
      // 2 TAXI — doorway vignette: rig cut to the door, taxi parked AT it.
      Object.freeze({
        op: 'parallel',
        steps: Object.freeze([
          Object.freeze({
            op: 'prop', action: 'spawn', propId: 'cam:door',
            model: 'virtual', anchor: 'cs:doorway',
            offset: Object.freeze([0, 0.85, 0]), scale: 0.42,
          }),
          Object.freeze({
            op: 'prop', action: 'spawn', propId: 'vacTaxi',
            model: 'car-kit/taxi', anchor: 'cs:doorway', scale: 0.5,
          }),
          Object.freeze({ op: 'sfx', sfx: 'tow' }),
          Object.freeze({ op: 'sfx', sfx: 'delivery.doorbell' }),
          Object.freeze({ op: 'particles', type: 'sparkles', count: 10, anchor: 'prop:vacTaxi' }),
          Object.freeze({ op: 'caption', key: 'cutscene.vac.depart.taxi' }),
          Object.freeze({ op: 'wait', duration: 1.5 }),
        ]),
      }),
      Object.freeze({ op: 'tapWait', timeout: 6 }),
      // 3 WAVE — camera eases home; the case glides over to the taxi.
      Object.freeze({
        op: 'parallel',
        steps: Object.freeze([
          Object.freeze({ op: 'prop', action: 'despawn', propId: 'cam:door' }),
          Object.freeze({ op: 'clip', clip: 'wave' }),
          Object.freeze({ op: 'sfx', sfx: 'gooby.squeakHappy' }),
          Object.freeze({
            op: 'prop', action: 'spawn', propId: 'vacSuitcase',
            model: 'pleasant-picnic/picnic_basket_square',
            anchor: 'cs:doorway', offset: Object.freeze([-0.15, 0, 0.35]), scale: 0.5,
          }),
          Object.freeze({ op: 'caption', key: 'cutscene.vac.depart.wave' }),
          Object.freeze({ op: 'wait', duration: 1.5 }),
        ]),
      }),
      // 4 DEPART — taxi + case vanish behind a whoosh + doorway burst.
      Object.freeze({
        op: 'parallel',
        steps: Object.freeze([
          Object.freeze({ op: 'prop', action: 'despawn', propId: 'vacSuitcase' }),
          Object.freeze({ op: 'prop', action: 'despawn', propId: 'vacTaxi' }),
          Object.freeze({ op: 'sfx', sfx: 'whoosh' }),
          Object.freeze({ op: 'particles', type: 'sparkles', count: 16, anchor: 'cs:doorway' }),
          Object.freeze({ op: 'wait', duration: 0.7 }),
        ]),
      }),
      // 5 SKY — tilt-up cutaway: the tiny plane CROSSES the upper frame
      // left→right with a sparkle trail riding its glide.
      Object.freeze({
        op: 'parallel',
        steps: Object.freeze([
          Object.freeze({
            op: 'prop', action: 'spawn', propId: 'cam:sky',
            model: 'virtual', anchor: 'cs:sky', scale: 0.3,
          }),
          Object.freeze({
            op: 'prop', action: 'spawn', propId: 'vacPlane',
            model: 'space-kit/craft_speederA',
            anchor: 'cs:sky', offset: Object.freeze([-1.0, -0.08, -0.1]), scale: 0.4,
          }),
          Object.freeze({ op: 'sfx', sfx: 'hop.flap' }),
          Object.freeze({ op: 'caption', key: 'cutscene.vac.depart.sky' }),
          Object.freeze({
            op: 'sequence',
            steps: Object.freeze([
              Object.freeze({ op: 'wait', duration: 0.5 }),
              Object.freeze({
                op: 'prop', action: 'spawn', propId: 'vacPlane',
                model: 'space-kit/craft_speederA',
                anchor: 'cs:sky', offset: Object.freeze([0.45, 0.15, -0.1]), scale: 0.4,
              }),
              Object.freeze({ op: 'wait', duration: 0.35 }),
              Object.freeze({ op: 'particles', type: 'sparkles', count: 8, anchor: 'prop:vacPlane' }),
              Object.freeze({ op: 'wait', duration: 0.35 }),
              Object.freeze({ op: 'particles', type: 'sparkles', count: 8, anchor: 'prop:vacPlane' }),
              Object.freeze({ op: 'wait', duration: 0.45 }),
              Object.freeze({ op: 'particles', type: 'sparkles', count: 10, anchor: 'prop:vacPlane' }),
            ]),
          }),
        ]),
      }),
      Object.freeze({ op: 'tapWait', timeout: 6 }),
      // 6 POSTCARDS — camera eases home under the closing promise.
      Object.freeze({
        op: 'parallel',
        steps: Object.freeze([
          Object.freeze({ op: 'prop', action: 'despawn', propId: 'vacPlane' }),
          Object.freeze({ op: 'prop', action: 'despawn', propId: 'cam:sky' }),
          Object.freeze({ op: 'particles', type: 'sparkles', count: 8 }),
          Object.freeze({ op: 'caption', key: 'cutscene.vac.depart.postcards' }),
          Object.freeze({ op: 'wait', duration: 0.9 }),
        ]),
      }),
      Object.freeze({ op: 'tapWait', timeout: 5 }),
      Object.freeze({ op: 'captionClear', keepOnSkip: true }),
      Object.freeze({ op: 'camera', move: 'restore', duration: 1.0 }),
      Object.freeze({ op: 'sfx', sfx: 'jingle.short', keepOnSkip: true }),
    ]),
  }),

  // The on-time reunion, beat table (V6/FIX2):
  //   1 ARRIVAL  doorway vignette — camera pans to the front door, the taxi
  //              pulls up AT it, doorbell rings ("A taxi pulls up...")
  //   2 ENTER    camera cuts back to the room — Gooby is there, leaping
  //              ecstatic (reads as "he just came in")
  //   3 HUG      dolly-in toward Gooby under the hearts burst (the beat the
  //              eval loved — kept verbatim)
  //   4 SOUVENIR coin stinger + authored 18-confetti beat + caption
  //   5 DEPART   taxi whooshes away, camera restores, happy stinger
  // Stats/souvenir were already paid by economy.pickupVacation BEFORE this
  // plays.
  vacReunionOnTime: Object.freeze({
    id: 'vacReunionOnTime',
    steps: Object.freeze([
      // 1 ARRIVAL — door-focused frame + doorbell cue.
      Object.freeze({
        op: 'parallel',
        steps: Object.freeze([
          Object.freeze({
            op: 'prop', action: 'spawn', propId: 'cam:door',
            model: 'virtual', anchor: 'cs:doorway',
            offset: Object.freeze([0, 0.85, 0]), scale: 0.42,
          }),
          Object.freeze({
            op: 'prop', action: 'spawn', propId: 'vacTaxi',
            model: 'car-kit/taxi', anchor: 'cs:doorway', scale: 0.5,
          }),
          Object.freeze({ op: 'sfx', sfx: 'whoosh' }),
          Object.freeze({ op: 'sfx', sfx: 'delivery.doorbell' }),
          Object.freeze({ op: 'caption', key: 'cutscene.vac.reunion.taxiBack' }),
          // Hold past the 0.9s rig cut so the settled door vignette READS.
          Object.freeze({ op: 'wait', duration: 2.6 }),
        ]),
      }),
      // 2 ENTER — cut back to the room: Gooby leaps out ecstatic.
      Object.freeze({
        op: 'parallel',
        steps: Object.freeze([
          Object.freeze({ op: 'prop', action: 'despawn', propId: 'cam:door' }),
          Object.freeze({ op: 'emotion', emotion: 'ecstatic' }),
          Object.freeze({ op: 'clip', clip: 'jump' }),
          Object.freeze({ op: 'sfx', sfx: 'gooby.giggle' }),
          Object.freeze({ op: 'particles', type: 'sparkles', count: 8 }),
          Object.freeze({ op: 'wait', duration: 0.9 }),
        ]),
      }),
      // 3 HUG — dolly-in toward Gooby while he bounces into the camera.
      Object.freeze({
        op: 'parallel',
        steps: Object.freeze([
          Object.freeze({ op: 'camera', move: 'pushIn', duration: 1.0 }),
          Object.freeze({ op: 'clip', clip: 'happyBounce' }),
          Object.freeze({ op: 'particles', type: 'hearts', count: 14 }),
          Object.freeze({ op: 'sfx', sfx: 'gooby.purr' }),
          Object.freeze({ op: 'caption', key: 'cutscene.vac.reunion.hug' }),
          Object.freeze({ op: 'wait', duration: 1.2 }),
        ]),
      }),
      Object.freeze({ op: 'tapWait', timeout: 6 }),
      // 4 SOUVENIR — the cutscene OWNS the celebration confetti beat
      // (airportScreen defers its toast until after playback — Sol P1-3).
      Object.freeze({
        op: 'parallel',
        steps: Object.freeze([
          Object.freeze({ op: 'sfx', sfx: 'coin.get' }),
          Object.freeze({ op: 'particles', type: 'confetti', count: 18 }),
          Object.freeze({ op: 'caption', key: 'cutscene.vac.reunion.souvenir' }),
          Object.freeze({ op: 'wait', duration: 0.8 }),
        ]),
      }),
      Object.freeze({ op: 'tapWait', timeout: 5 }),
      // 5 DEPART — taxi away, camera home, happy stinger.
      Object.freeze({
        op: 'parallel',
        steps: Object.freeze([
          Object.freeze({ op: 'prop', action: 'despawn', propId: 'vacTaxi' }),
          Object.freeze({ op: 'sfx', sfx: 'whoosh' }),
          Object.freeze({ op: 'wait', duration: 0.4 }),
        ]),
      }),
      Object.freeze({ op: 'captionClear', keepOnSkip: true }),
      Object.freeze({ op: 'camera', move: 'restore', duration: 0.9 }),
      Object.freeze({ op: 'emotion', emotion: 'happy', keepOnSkip: true }),
      Object.freeze({ op: 'sfx', sfx: 'jingle.short', keepOnSkip: true }),
    ]),
  }),

  // The late-pickup reunion: SAME skeleton and identical rewards/stats as
  // the on-time script (economy paths are frozen) — only the ACTING differs:
  // a slower taxi arrival, droopy sleepy ears, a tired stretch and a small
  // 'phew' beat before the warm turn. Never punishing — it still ends on a
  // hearts beat, the souvenir caption and a happy Gooby.
  vacReunionTaxi: Object.freeze({
    id: 'vacReunionTaxi',
    steps: Object.freeze([
      // 1 ARRIVAL — the same door-focused frame as the on-time reunion,
      // only slower: the tired taxi rolls up, the driver rings.
      Object.freeze({
        op: 'parallel',
        steps: Object.freeze([
          Object.freeze({
            op: 'prop', action: 'spawn', propId: 'cam:door',
            model: 'virtual', anchor: 'cs:doorway',
            offset: Object.freeze([0, 0.85, 0]), scale: 0.42,
          }),
          Object.freeze({
            op: 'prop', action: 'spawn', propId: 'vacTaxi',
            model: 'car-kit/taxi', anchor: 'cs:doorway', scale: 0.5,
          }),
          Object.freeze({ op: 'sfx', sfx: 'tow' }),
          Object.freeze({ op: 'sfx', sfx: 'delivery.doorbell' }),
          Object.freeze({ op: 'caption', key: 'cutscene.vac.late.taxi' }),
          // Hold past the 0.9s rig cut so the settled door vignette READS.
          Object.freeze({ op: 'wait', duration: 2.8 }),
        ]),
      }),
      // 2 ENTER — cut back to the room: droopy ears, a tired stretch.
      Object.freeze({
        op: 'parallel',
        steps: Object.freeze([
          Object.freeze({ op: 'prop', action: 'despawn', propId: 'cam:door' }),
          Object.freeze({ op: 'emotion', emotion: 'sleepy' }),
          Object.freeze({ op: 'clip', clip: 'stretch' }),
          Object.freeze({ op: 'sfx', sfx: 'gooby.yawn' }),
          Object.freeze({ op: 'wait', duration: 1.6 }),
        ]),
      }),
      // the small 'phew' beat — slow look around, sheepish sigh
      Object.freeze({
        op: 'parallel',
        steps: Object.freeze([
          Object.freeze({ op: 'clip', clip: 'lookAround' }),
          Object.freeze({ op: 'sfx', sfx: 'gooby.sigh' }),
          Object.freeze({ op: 'caption', key: 'cutscene.vac.late.phew' }),
          Object.freeze({ op: 'wait', duration: 1.8 }),
        ]),
      }),
      Object.freeze({ op: 'tapWait', timeout: 6 }),
      // the warm turn: slower dolly-in, fewer hearts, but still a hug beat
      Object.freeze({
        op: 'parallel',
        steps: Object.freeze([
          Object.freeze({ op: 'camera', move: 'pushIn', duration: 1.2 }),
          Object.freeze({ op: 'emotion', emotion: 'happy' }),
          Object.freeze({ op: 'clip', clip: 'happyBounce' }),
          Object.freeze({ op: 'particles', type: 'hearts', count: 8 }),
          Object.freeze({ op: 'sfx', sfx: 'gooby.purr' }),
          Object.freeze({ op: 'caption', key: 'cutscene.vac.late.warm' }),
          Object.freeze({ op: 'wait', duration: 1.4 }),
        ]),
      }),
      Object.freeze({ op: 'tapWait', timeout: 6 }),
      Object.freeze({
        op: 'parallel',
        steps: Object.freeze([
          Object.freeze({ op: 'sfx', sfx: 'coin.get' }),
          Object.freeze({ op: 'caption', key: 'cutscene.vac.late.souvenir' }),
          Object.freeze({ op: 'wait', duration: 0.8 }),
        ]),
      }),
      Object.freeze({ op: 'tapWait', timeout: 5 }),
      Object.freeze({
        op: 'parallel',
        steps: Object.freeze([
          Object.freeze({ op: 'prop', action: 'despawn', propId: 'vacTaxi' }),
          Object.freeze({ op: 'sfx', sfx: 'whoosh' }),
          Object.freeze({ op: 'wait', duration: 0.4 }),
        ]),
      }),
      Object.freeze({ op: 'captionClear', keepOnSkip: true }),
      Object.freeze({ op: 'camera', move: 'restore', duration: 0.9 }),
      Object.freeze({ op: 'emotion', emotion: 'happy', keepOnSkip: true }),
      Object.freeze({ op: 'sfx', sfx: 'jingle.short', keepOnSkip: true }),
    ]),
  }),
  // ── end V6/D1 ─────────────────────────────────────────────────────────────
});

/** @type {readonly string[]} the known ids — bounds the persisted seen map */
export const CUTSCENE_IDS = Object.freeze(Object.keys(CUTSCENES));

/**
 * @param {string} id
 * @returns {CutsceneScript|null}
 */
export function getCutscene(id) {
  return CUTSCENES[id] ?? null;
}
