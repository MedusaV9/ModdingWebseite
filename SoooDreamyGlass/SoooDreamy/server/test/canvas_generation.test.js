// Sync contract f (FX-S) — the eval battery's find: a clear races in-flight
// and retried strokes, so dead ink resurrected on the wiped board. The board
// now carries `generation` (Int, starts at 1, +1 per clear). Stroke commits
// may send their generation — a stale one answers 409 stale_generation and
// stores NOTHING. Without `generation` in the body the old behavior stays.
// `canvas_live` relays and `canvas_clear`/`canvas_stroke` broadcasts carry
// the current generation so receivers can drop wiped-board ink.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple, wsOpen } from './helpers.js';

test('EVAL repro: a stroke retry from before the clear answers stale_generation and stores nothing', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  const board = await a.api.get('/api/canvas');
  assert.equal(board.body.generation, 1, 'boards start at generation 1');

  // A draws on generation 1 (the client tags its outbox with the generation).
  const first = await a.api.post('/api/canvas/strokes', {
    json: { points: [[0.1, 0.2]], generation: 1 },
  });
  assert.equal(first.status, 201);
  assert.equal(first.body.generation, 1);

  // B wipes the board — generation 2.
  const clear = await b.api.del('/api/canvas');
  assert.equal(clear.status, 200);
  assert.equal(clear.body.generation, 2);

  // A's queued retry of a generation-1 stroke: before the fix it resurrected
  // dead ink on the wiped board. Now: 409 with the CURRENT generation.
  const stale = await a.api.post('/api/canvas/strokes', {
    json: { points: [[0.3, 0.4]], generation: 1 },
  });
  assert.equal(stale.status, 409);
  assert.equal(stale.body.error, 'stale_generation');
  assert.equal(stale.body.generation, 2);
  assert.equal((await a.api.get('/api/canvas')).body.strokes.length, 0, 'the board stays wiped');

  // A fresh stroke tagged with the current generation lands normally.
  const fresh = await a.api.post('/api/canvas/strokes', {
    json: { points: [[0.5, 0.6]], generation: 2 },
  });
  assert.equal(fresh.status, 201);
  assert.equal(fresh.body.generation, 2);
});

test('strokes without generation keep the old behavior; validation rejects junk', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  await b.api.del('/api/canvas'); // board is at generation 2 now

  // Shipped clients do not send generation — they always commit (LWW as before).
  const untagged = await a.api.post('/api/canvas/strokes', { json: { points: [[0.1, 0.1]] } });
  assert.equal(untagged.status, 201);

  const junk = await a.api.post('/api/canvas/strokes', { json: { points: [[0.1, 0.1]], generation: 'neu' } });
  assert.equal(junk.status, 400);
  assert.equal(junk.body.error, 'invalid_request');
  assert.equal((await a.api.post('/api/canvas/strokes', { json: { points: [[0.1, 0.1]], generation: 0 } })).status, 400);
});

test('every clear bumps the generation; broadcasts and GET expose it', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  assert.equal((await a.api.del('/api/canvas')).body.generation, 2);
  assert.equal((await bSock.waitFor('canvas_clear')).payload.generation, 2);
  assert.equal((await a.api.del('/api/canvas')).body.generation, 3);
  assert.equal((await bSock.waitFor('canvas_clear')).payload.generation, 3);
  assert.equal((await b.api.get('/api/canvas')).body.generation, 3);

  // The canvas_stroke broadcast carries the generation the stroke landed on.
  const stroke = await a.api.post('/api/canvas/strokes', { json: { points: [[0.2, 0.2]] } });
  assert.equal(stroke.status, 201);
  const frame = await bSock.waitFor('canvas_stroke');
  assert.equal(frame.payload.generation, 3);
});

test('canvas_live relays carry the current generation so live ink dies with the clear', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await aSock.waitFor('welcome');
  await bSock.waitFor('welcome');

  aSock.send({ type: 'canvas_live', payload: { phase: 'draw', points: [[0.1, 0.2]] } });
  assert.equal((await bSock.waitFor('canvas_live')).payload.generation, 1);

  assert.equal((await b.api.del('/api/canvas')).status, 200);
  await aSock.waitFor('canvas_clear');

  aSock.send({ type: 'canvas_live', payload: { phase: 'draw', points: [[0.3, 0.4]] } });
  assert.equal((await bSock.waitFor('canvas_live')).payload.generation, 2);
});
