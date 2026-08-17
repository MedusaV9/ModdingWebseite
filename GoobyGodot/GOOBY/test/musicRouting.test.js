// GOOBY V4/POLISH-G — real recorded music per scene (PLAN4 §B2.4):
//   1. trackFor() coverage: every WIRED context (rooms, locations, arcade,
//      the per-game tracks) resolves a real manifest track — the fallback
//      medley must be unreachable in normal play.
//   2. Source pins for the scene hooks: roomManager streams `room:<id>`,
//      shop/vet/city stream their Location tracks, arcade/pregame the
//      ArcadeUI track, and every game WITH a manifest Game track calls
//      radio.playContext('game:<id>') at init (purblePlace convention,
//      incl. the dispose restore).
//   3. The musicDirector fallback gate: contexts with real tracks never
//      start the medley; a null resolver (missing track) re-enables it.
// Pure node tests — no DOM/three; the director runs against stub deps.

import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { trackFor, CONTEXT_ALIASES } from '../src/systems/musicRegistry.js';
import { MEDLEY_CONTEXTS } from '../src/audio/musicDirector.js';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const src = (p) => fs.readFileSync(path.join(ROOT, 'src', p), 'utf8');

// ---------------------------------------------------------------- trackFor

/** Every context the V4/POLISH-G scene hooks wire to a REAL recorded track. */
const WIRED_SCENE_CONTEXTS = [
  'room:kitchen', 'room:living', 'room:bathroom', 'room:bedroom', 'room:garden',
  'location:city', 'location:shop', 'location:vet', 'arcade',
];

/** The manifest's per-game tracks (§C-SYS1.2 Game category, 7 on day one). */
const WIRED_GAME_CONTEXTS = [
  'game:harborHopper', 'game:ghostHunt', 'game:purblePlace', 'game:shoppingSurf',
  'game:toyRacer', 'game:goobyWelt', 'game:starHopper',
];

test('POLISH-G: every wired scene/game context resolves a real manifest track', () => {
  for (const context of [...WIRED_SCENE_CONTEXTS, ...WIRED_GAME_CONTEXTS]) {
    const track = trackFor(context);
    assert.ok(track, `trackFor('${context}') resolves`);
    assert.equal(typeof track.file, 'string');
    assert.ok(track.durationSec > 10, `'${context}' is a real track, not a stinger`);
  }
  // bedroom carries BOTH variants
  assert.equal(trackFor('room:bedroom').variant, 'awake');
  assert.equal(trackFor('room:bedroom', { sleeping: true }).variant, 'sleeping');
});

test('POLISH-G: every §C3.3 medley context is backed by a real track (medley = fallback only)', () => {
  for (const ctxId of MEDLEY_CONTEXTS) {
    assert.ok(trackFor(ctxId), `trackFor('${ctxId}') resolves through the aliases`);
    assert.ok(CONTEXT_ALIASES[ctxId], `'${ctxId}' has an alias row`);
  }
  assert.equal(trackFor('game:doesNotExist'), null, 'unknown contexts still fall back');
});

// ---------------------------------------------------------------- source pins

test('POLISH-G wiring: scene hooks stream the real tracks (source pins)', () => {
  const rm = src('home/roomManager.js');
  assert.match(rm, /playContext\?\.\(`room:\$\{roomId\}`\)/, 'roomManager streams room:<id>');
  assert.match(rm, /import radioPlayer from '\.\.\/audio\/radioPlayer\.js'/);

  const shop = src('ui/shopScreen.js');
  assert.match(shop, /playContext\?\.\('location:shop'\)/, 'shopScreen streams the IKEA track');
  assert.match(shop, /context === 'location:shop'/, 'shop unmount hands the element back');

  const vet = src('ui/vetPanel.js');
  assert.match(vet, /playContext\?\.\('location:vet'\)/, 'vetPanel streams the clinic track');
  assert.match(vet, /context === 'location:vet'/, 'vet unmount hands the element back');

  const city = src('minigames/games/cityDrive.js');
  assert.match(city, /playContext\?\.\('location:city'\)/, 'cityDrive streams the city track');

  const pregame = src('ui/pregameScreen.js');
  assert.match(pregame, /playContext\?\.\('arcade'\)/, 'arcade holder streams the ArcadeUI track');
  assert.match(pregame, /gameLaunching = true/, 'launches ride the ArcadeUI loop into the game');
});

test('POLISH-G wiring: every game with a manifest Game track plays it (source pins)', () => {
  for (const context of WIRED_GAME_CONTEXTS) {
    const id = context.slice('game:'.length);
    const game = src(`minigames/games/${id}.js`);
    assert.match(
      game,
      new RegExp(`playContext\\?\\.\\('game:${id}'\\)`),
      `${id} plays its real track at init`
    );
    // purblePlace convention is `musicContextOn`; goobyWelt (pre-G) kept its
    // own `radioTrack` handle — both gate the dispose restore.
    assert.match(game, /musicContextOn|radioTrack/, `${id} tracks the context for the dispose restore`);
    assert.match(
      game,
      /wish\?\.playing === true\) (?:this\.)?radio\??\.start/,
      `${id} dispose restores the persisted radio wish`
    );
  }
});

// ------------------------------------------------- director fallback gate

test('POLISH-G: the director gates the medley behind resolveRealTrack (stub deps)', async () => {
  const { default: director, setTrackResolver } = await import('../src/audio/musicDirector.js');
  const ctx = {
    currentTime: 0,
    created: 0,
    createGain() {
      this.created += 1;
      return {
        gain: {
          value: 1,
          setValueAtTime() {}, linearRampToValueAtTime() {},
          setValueCurveAtTime() {}, cancelScheduledValues() {},
          exponentialRampToValueAtTime() {},
        },
        connect(n) { return n; },
        disconnect() {},
      };
    },
    createOscillator() {
      this.created += 1;
      return {
        type: 'sine', frequency: { value: 0 },
        connect(n) { return n; }, start() {}, stop() {},
      };
    },
    createBufferSource() {
      this.created += 1;
      return { buffer: null, connect(n) { return n; }, start() {}, stop() {}, onended: null };
    },
  };
  const deps = {
    ctx,
    dest: ctx.createGain(),
    loadBuffer: () => Promise.resolve(null),
    getCachedBuffer: () => null,
  };
  try {
    director.attach(deps);
    director.setContext('home'); // real track exists → the medley must NOT start
    let stats = director.getStats();
    assert.equal(stats.context, null, 'no live medley player');
    assert.equal(stats.wantContext, 'home', 'the wish is kept');
    assert.equal(stats.realTrack, true, 'gate reports the real track');
    const before = ctx.created;
    await new Promise((r) => setTimeout(r, 450)); // >2 scheduler ticks
    assert.equal(ctx.created, before, 'ZERO nodes (no glue-bed oscillator) with a real track');
    setTrackResolver(() => null); // the track vanishes → fallback medley starts
    stats = director.getStats();
    assert.equal(stats.context, 'home', 'medley falls back when no real track resolves');
    setTrackResolver(null); // registry default again → gated once more
    assert.equal(director.getStats().context, null);
  } finally {
    setTrackResolver(null);
    director.reset();
  }
});
