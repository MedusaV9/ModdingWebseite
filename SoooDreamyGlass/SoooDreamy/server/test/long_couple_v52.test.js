import { performance } from 'node:perf_hooks';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple } from './helpers.js';

test('two-year 10k-message fixture keeps bounded reads fast and correctly paginated', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a, b, coupleId } = await setupCouple(baseUrl);
  const couple = app.store.data.couples[coupleId];
  const start = Date.parse('2024-01-01T00:00:00.000Z');
  couple.messages = Array.from({ length: 10_000 }, (_, index) => ({
    id: `fixture-${String(index).padStart(5, '0')}`,
    senderId: index % 2 === 0 ? a.memberId : b.memberId,
    type: 'text',
    text: `bounded fixture ${index}`,
    title: null,
    openWhen: null,
    photoId: null,
    effect: null,
    clientMessageId: `fixture-client-${index}`,
    audioUrl: null,
    durationSec: null,
    createdAt: new Date(start + index * 6_300_000).toISOString(),
  }));
  couple.counters.messages = 10_000;
  app.store.markDirty();
  await app.store.flush();

  const durations = [];
  for (let index = 0; index < 20; index += 1) {
    const before = performance.now();
    const response = await a.api.get('/api/messages?limit=50');
    durations.push(performance.now() - before);
    assert.equal(response.status, 200);
    assert.equal(response.body.messages.length, 50);
    assert.equal(response.body.messages.at(-1).id, 'fixture-09999');
  }
  durations.sort((x, y) => x - y);
  const p95 = durations[Math.ceil(durations.length * 0.95) - 1];
  assert.ok(p95 < 250, `p95 ${p95.toFixed(1)} ms exceeded the shared-CI guardrail`);

  const firstPage = await a.api.get('/api/messages?limit=50&before=fixture-09950');
  assert.equal(firstPage.status, 200);
  assert.equal(firstPage.body.messages[0].id, 'fixture-09900');
  assert.equal(firstPage.body.messages.at(-1).id, 'fixture-09949');
  assert.equal((await a.api.get('/api/stats')).body.messages, 10_000);
});
