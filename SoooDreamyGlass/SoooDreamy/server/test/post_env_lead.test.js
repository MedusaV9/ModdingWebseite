import { test } from 'node:test';
import assert from 'node:assert/strict';

// Arena/Test override: POST_MIN_LEAD_SECONDS shrinks the 5-minute Zeitpost
// scheduling lead so live harnesses (tools/arena) can test REAL deliveries in
// seconds. The env var is read once at module load, and node's test runner
// isolates each test file in its own process — setting it here (BEFORE the
// dynamic imports below) affects only this file. Every other test file keeps
// the byte-identical shipped defaults.
process.env.POST_MIN_LEAD_SECONDS = '1';

const { POST_LIMITS, postDeliverySweep } = await import('../src/post.js');
const { makeApp, setupCouple } = await import('./helpers.js');

test('POST_MIN_LEAD_SECONDS override shrinks the minimum lead', () => {
  assert.equal(POST_LIMITS.minLeadMs, 1_000);
  // Everything else stays untouched.
  assert.equal(POST_LIMITS.maxLeadMs, 7 * 24 * 60 * 60_000);
  assert.equal(POST_LIMITS.leadGraceMs, 30_000);
});

test('with the override a seconds-ahead Zeitpost schedules and delivers exactly once', async (t) => {
  const ctx = await makeApp(t, { pushProvider: null, postDeliveryIntervalSeconds: 0 });
  const { a, b } = await setupCouple(ctx.baseUrl);

  // 2 s ahead — far below the shipped 5-minute lead, valid under the override.
  const deliverAt = new Date(Date.now() + 2_000).toISOString();
  const res = await a.api.post('/api/post/schedule', {
    json: { kind: 'touch', type: 'kiss', deliverAt },
  });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  const postId = res.body.post.id;

  const sweep = () => postDeliverySweep({
    store: ctx.app.store,
    realtime: ctx.app.realtime,
    push: ctx.app.push,
    now: new Date(Date.now() + 3_000),
  });
  assert.equal(sweep(), 1);
  // Re-sweeping never duplicates the artifact (stable post-derived id).
  assert.equal(sweep(), 0);

  const touches = await b.api.get('/api/touches/recent');
  const artifacts = touches.body.touches.filter((touch) => touch.id === `t_${postId}`);
  assert.equal(artifacts.length, 1);
  assert.equal(artifacts[0].viaPost, true);
});
