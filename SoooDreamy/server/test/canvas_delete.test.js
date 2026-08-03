import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple, wsOpen } from './helpers.js';

test('author deletes own stroke: removed from list, canvas_stroke_deleted broadcast couple-wide', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await aSock.waitFor('welcome');
  await bSock.waitFor('welcome');

  const mine = (await a.api.post('/api/canvas/strokes', { json: { points: [[0.1, 0.1]] } })).body.stroke;
  const other = (await a.api.post('/api/canvas/strokes', { json: { points: [[0.9, 0.9]] } })).body.stroke;

  const res = await a.api.del(`/api/canvas/strokes/${mine.id}`);
  assert.equal(res.status, 200);
  assert.deepEqual(res.body, { ok: true });

  // Couple-wide: the author's own sockets get the frame too.
  const aFrame = await aSock.waitFor('canvas_stroke_deleted');
  const bFrame = await bSock.waitFor('canvas_stroke_deleted');
  assert.deepEqual(aFrame.payload, { id: mine.id });
  assert.deepEqual(bFrame.payload, { id: mine.id });

  const list = await b.api.get('/api/canvas');
  assert.deepEqual(list.body.strokes.map((s) => s.id), [other.id]);

  // Deleting it again → 404.
  assert.equal((await a.api.del(`/api/canvas/strokes/${mine.id}`)).status, 404);
});

test("deleting the partner's stroke → 403 not_yours, unknown stroke → 404 not_found", async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const stroke = (await a.api.post('/api/canvas/strokes', { json: { points: [[0.5, 0.5]] } })).body.stroke;

  const denied = await b.api.del(`/api/canvas/strokes/${stroke.id}`);
  assert.equal(denied.status, 403);
  assert.equal(denied.body.error, 'not_yours');
  // The stroke survives.
  assert.equal((await a.api.get('/api/canvas')).body.strokes.length, 1);

  const unknown = await a.api.del('/api/canvas/strokes/s_nope');
  assert.equal(unknown.status, 404);
  assert.equal(unknown.body.error, 'not_found');
});
