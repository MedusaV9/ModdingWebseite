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
