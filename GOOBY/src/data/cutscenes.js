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
  // 'plane in the sky' beat spawns 'space-kit/craft_speederA' high above
  // with a sparkle trail. Offsets are GOOBY-RELATIVE (no anchor) so the
  // staging works in whichever room Gooby currently idles.

  // The booking send-off: taxi pulls up, suitcase plops down, Gooby bounces
  // happily, waves goodbye, the taxi departs and a tiny plane crosses the
  // sky trailing sparkles. Rewards/state are already committed by
  // economy.bookVacation BEFORE this plays (decoration only).
  vacDeparture: Object.freeze({
    id: 'vacDeparture',
    steps: Object.freeze([
      Object.freeze({ op: 'camera', move: 'pushIn', duration: 1.2 }),
      Object.freeze({
        op: 'parallel',
        steps: Object.freeze([
          Object.freeze({
            op: 'prop', action: 'spawn', propId: 'vacTaxi',
            model: 'car-kit/taxi', offset: Object.freeze([0.9, 0, -0.55]), scale: 0.5,
          }),
          Object.freeze({ op: 'sfx', sfx: 'whoosh' }),
          Object.freeze({ op: 'particles', type: 'sparkles', count: 10 }),
          Object.freeze({ op: 'caption', key: 'cutscene.vac.depart.taxi' }),
          Object.freeze({ op: 'wait', duration: 1.0 }),
        ]),
      }),
      Object.freeze({
        op: 'prop', action: 'spawn', propId: 'vacSuitcase',
        model: 'pleasant-picnic/picnic_basket_square',
        offset: Object.freeze([-0.6, 0, 0.35]), scale: 0.5,
      }),
      Object.freeze({ op: 'sfx', sfx: 'ball.bounce' }),
      Object.freeze({
        op: 'parallel',
        steps: Object.freeze([
          Object.freeze({ op: 'emotion', emotion: 'happy' }),
          Object.freeze({ op: 'clip', clip: 'happyBounce' }),
          Object.freeze({ op: 'sfx', sfx: 'gooby.squeakHappy' }),
          Object.freeze({ op: 'caption', key: 'cutscene.vac.depart.pack' }),
          Object.freeze({ op: 'wait', duration: 1.0 }),
        ]),
      }),
      Object.freeze({ op: 'tapWait', timeout: 6 }),
      Object.freeze({
        op: 'parallel',
        steps: Object.freeze([
          Object.freeze({ op: 'clip', clip: 'wave' }),
          Object.freeze({ op: 'caption', key: 'cutscene.vac.depart.wave' }),
          Object.freeze({ op: 'wait', duration: 1.2 }),
        ]),
      }),
      // drive-away: taxi + case vanish behind a whoosh + sparkle burst
      Object.freeze({
        op: 'parallel',
        steps: Object.freeze([
          Object.freeze({ op: 'prop', action: 'despawn', propId: 'vacSuitcase' }),
          Object.freeze({ op: 'prop', action: 'despawn', propId: 'vacTaxi' }),
          Object.freeze({ op: 'sfx', sfx: 'whoosh' }),
          Object.freeze({ op: 'particles', type: 'sparkles', count: 16 }),
          Object.freeze({ op: 'wait', duration: 0.6 }),
        ]),
      }),
      // stylized plane-in-the-sky lift-off beat (no plane GLB on disk)
      Object.freeze({
        op: 'parallel',
        steps: Object.freeze([
          Object.freeze({
            op: 'prop', action: 'spawn', propId: 'vacPlane',
            model: 'space-kit/craft_speederA',
            offset: Object.freeze([-0.5, 2.1, -1.0]), scale: 0.45,
          }),
          Object.freeze({ op: 'sfx', sfx: 'hop.flap' }),
          Object.freeze({ op: 'particles', type: 'sparkles', count: 14 }),
          Object.freeze({ op: 'caption', key: 'cutscene.vac.depart.sky' }),
          Object.freeze({ op: 'wait', duration: 1.4 }),
        ]),
      }),
      Object.freeze({ op: 'tapWait', timeout: 6 }),
      Object.freeze({
        op: 'parallel',
        steps: Object.freeze([
          Object.freeze({ op: 'prop', action: 'despawn', propId: 'vacPlane' }),
          Object.freeze({ op: 'particles', type: 'sparkles', count: 8 }),
          Object.freeze({ op: 'caption', key: 'cutscene.vac.depart.postcards' }),
          Object.freeze({ op: 'wait', duration: 0.8 }),
        ]),
      }),
      Object.freeze({ op: 'tapWait', timeout: 5 }),
      Object.freeze({ op: 'captionClear', keepOnSkip: true }),
      Object.freeze({ op: 'camera', move: 'restore', duration: 1.0 }),
      Object.freeze({ op: 'sfx', sfx: 'jingle.short', keepOnSkip: true }),
    ]),
  }),

  // The on-time reunion: taxi pulls up, Gooby leaps out ecstatic, a
  // run-to-camera hug beat (camera dolly-in) under a hearts burst, then the
  // souvenir-coins caption with confetti. Stats/souvenir were already paid
  // by economy.pickupVacation BEFORE this plays.
  vacReunionOnTime: Object.freeze({
    id: 'vacReunionOnTime',
    steps: Object.freeze([
      Object.freeze({
        op: 'parallel',
        steps: Object.freeze([
          Object.freeze({
            op: 'prop', action: 'spawn', propId: 'vacTaxi',
            model: 'car-kit/taxi', offset: Object.freeze([0.9, 0, -0.55]), scale: 0.5,
          }),
          Object.freeze({ op: 'sfx', sfx: 'whoosh' }),
          Object.freeze({ op: 'caption', key: 'cutscene.vac.reunion.taxiBack' }),
          Object.freeze({ op: 'wait', duration: 1.0 }),
        ]),
      }),
      Object.freeze({ op: 'sfx', sfx: 'ball.bounce' }),
      Object.freeze({
        op: 'parallel',
        steps: Object.freeze([
          Object.freeze({ op: 'emotion', emotion: 'ecstatic' }),
          Object.freeze({ op: 'clip', clip: 'jump' }),
          Object.freeze({ op: 'sfx', sfx: 'gooby.giggle' }),
          Object.freeze({ op: 'particles', type: 'sparkles', count: 8 }),
          Object.freeze({ op: 'wait', duration: 0.7 }),
        ]),
      }),
      // hug beat: dolly-in toward Gooby while he bounces into the camera
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
      Object.freeze({
        op: 'parallel',
        steps: Object.freeze([
          Object.freeze({
            op: 'prop', action: 'spawn', propId: 'vacTaxi',
            model: 'car-kit/taxi', offset: Object.freeze([0.9, 0, -0.55]), scale: 0.5,
          }),
          Object.freeze({ op: 'sfx', sfx: 'tow' }),
          Object.freeze({ op: 'caption', key: 'cutscene.vac.late.taxi' }),
          Object.freeze({ op: 'wait', duration: 1.4 }),
        ]),
      }),
      Object.freeze({ op: 'sfx', sfx: 'ball.bounce' }),
      Object.freeze({
        op: 'parallel',
        steps: Object.freeze([
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
