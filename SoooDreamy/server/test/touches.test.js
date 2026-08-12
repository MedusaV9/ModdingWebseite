import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple, wsOpen } from './helpers.js';

test('touch reaches the partner via WS but never the sender', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await aSock.waitFor('welcome');
  await bSock.waitFor('welcome');

  const res = await a.api.post('/api/touches', { json: { type: 'kiss' } });
  assert.equal(res.status, 201);
  assert.match(res.body.touch.id, /^t_/);
  assert.equal(res.body.touch.type, 'kiss');
  assert.equal(res.body.touch.senderId, a.memberId);

  const frame = await bSock.waitFor('touch');
  assert.deepEqual(frame.payload.touch, res.body.touch);
  await aSock.assertNone('touch');
});

test('invalid touch type → 400', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  const res = await a.api.post('/api/touches', { json: { type: 'slap' } });
  assert.equal(res.status, 400);
  assert.equal(res.body.error, 'invalid_type');
});

test('recent touches list is newest-first and respects limit', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  for (const type of ['kiss', 'hug', 'missyou']) {
    await a.api.post('/api/touches', { json: { type } });
  }
  await b.api.post('/api/touches', { json: { type: 'tickle' } });

  const res = await a.api.get('/api/touches/recent?limit=3');
  assert.equal(res.status, 200);
  assert.equal(res.body.touches.length, 3);
  assert.deepEqual(
    res.body.touches.map((x) => x.type),
    ['tickle', 'missyou', 'hug'],
  );

  const all = await a.api.get('/api/touches/recent');
  assert.equal(all.body.touches.length, 4);
});
