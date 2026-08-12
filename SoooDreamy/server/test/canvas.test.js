import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple, wsOpen } from './helpers.js';

test('strokes: create, broadcast, list ascending, clear with broadcast', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const first = await a.api.post('/api/canvas/strokes', {
    json: { color: '#FF5C8A', width: 4, tool: 'pen', points: [[0.1, 0.2], [0.11, 0.22]] },
  });
  assert.equal(first.status, 201);
  const stroke = first.body.stroke;
  assert.match(stroke.id, /^s_/);
  assert.equal(stroke.memberId, a.memberId);
  assert.deepEqual(stroke.points, [[0.1, 0.2], [0.11, 0.22]]);

  const frame = await bSock.waitFor('canvas_stroke');
  assert.deepEqual(frame.payload.stroke, stroke);

  await b.api.post('/api/canvas/strokes', { json: { points: [[0.5, 0.5]] } });
  const list = await a.api.get('/api/canvas');
  assert.equal(list.body.strokes.length, 2);
  assert.equal(list.body.strokes[0].id, stroke.id); // ascending

  const clear = await b.api.del('/api/canvas');
  assert.equal(clear.status, 200);
  const cleared = await bSock.waitFor('canvas_clear');
  assert.deepEqual(cleared.payload, {});
  assert.equal((await a.api.get('/api/canvas')).body.strokes.length, 0);
});

test('GET /api/canvas?limit=N returns the last N strokes, still ascending', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  const ids = [];
  for (let i = 0; i < 4; i++) {
    const res = await a.api.post('/api/canvas/strokes', { json: { points: [[i / 10, 0.5]] } });
    assert.equal(res.status, 201);
    ids.push(res.body.stroke.id);
  }

  const limited = await a.api.get('/api/canvas?limit=2');
  assert.equal(limited.status, 200);
  assert.deepEqual(limited.body.strokes.map((s) => s.id), ids.slice(-2)); // last two, ascending

  // No limit → everything; a limit larger than the list is harmless.
  assert.deepEqual((await a.api.get('/api/canvas')).body.strokes.map((s) => s.id), ids);
  assert.deepEqual((await a.api.get('/api/canvas?limit=500')).body.strokes.map((s) => s.id), ids);
  assert.deepEqual((await a.api.get('/api/canvas?limit=1')).body.strokes.map((s) => s.id), ids.slice(-1));

  assert.equal((await a.api.get('/api/canvas?limit=nope')).status, 400);
});

test('stroke with more than 2000 points → 400 too_many_points', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  const tooMany = Array.from({ length: 2001 }, (_, i) => [i / 2001, 0.5]);
  const res = await a.api.post('/api/canvas/strokes', { json: { points: tooMany } });
  assert.equal(res.status, 400);
  assert.equal(res.body.error, 'too_many_points');

  const okMany = Array.from({ length: 2000 }, (_, i) => [i / 2000, 0.5]);
  assert.equal((await a.api.post('/api/canvas/strokes', { json: { points: okMany } })).status, 201);

  assert.equal((await a.api.post('/api/canvas/strokes', { json: { points: [] } })).status, 400);
  assert.equal((await a.api.post('/api/canvas/strokes', { json: { points: [[0.1, 'x']] } })).status, 400);
});
