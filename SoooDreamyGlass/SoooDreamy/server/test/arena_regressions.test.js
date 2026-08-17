import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple } from './helpers.js';
import { postDeliverySweep } from '../src/post.js';

// Regression tests for findings of the live multi-couple arena
// (tools/arena — seeded HTTP+WS runs against a real server process).

async function pulseApp(t) {
  const ctx = await makeApp(t, { pushProvider: null, postDeliveryIntervalSeconds: 0 });
  const pair = await setupCouple(ctx.baseUrl);
  const sweep = (now) => postDeliverySweep({
    store: ctx.app.store, realtime: ctx.app.realtime, push: ctx.app.push, now,
  });
  return { ...ctx, ...pair, sweep };
}

function inMinutes(minutes) {
  return new Date(Date.now() + minutes * 60_000).toISOString();
}

// Arena finding (6-couple live run, seed 7): a delivered Zeitpost pulse lands
// in couple.pulses with createdAt = DELIVERY time and the sender's id — the
// live-pulse cooldown then judged the sender by the delivery timestamp and
// refused a legitimate live pulse with a surprise 429 too_soon (plus a
// retry-after countdown the user never started). The cooldown must count
// LIVE sends only; viaPost artifacts are server events, not send actions.
test('pulse cooldown: a Zeitpost pulse delivery does not restart the sender cooldown', async (t) => {
  const { a, sweep } = await pulseApp(t);

  const scheduled = await a.api.post('/api/post/schedule', {
    json: { kind: 'pulse', pulseKind: 'heartbeat', deliverAt: inMinutes(6) },
  });
  assert.equal(scheduled.status, 201);

  // Deliver the Zeitpost NOW (sweep clock jumps past deliverAt; the minted
  // artifact's createdAt is the real wall clock — i.e. "just delivered").
  assert.equal(sweep(new Date(Date.now() + 7 * 60_000)), 1);

  // A live pulse right after the delivery must be accepted — before the fix
  // this was a 429 too_soon triggered by the server's own delivery.
  const live = await a.api.post('/api/pulses', { json: { kind: 'thinking' } });
  assert.equal(live.status, 201, `live pulse right after a Zeitpost delivery: ${JSON.stringify(live.body)}`);

  // The LIVE cooldown itself stays fully intact.
  const second = await a.api.post('/api/pulses', { json: { kind: 'hug' } });
  assert.equal(second.status, 429);
  assert.equal(second.body.error, 'too_soon');
  assert.ok(Number(second.headers.get?.('retry-after') ?? second.headers['retry-after']) >= 1);
});

test('pulse cooldown: live sends still throttle each other (guard for the fix above)', async (t) => {
  const { b } = await pulseApp(t);
  const first = await b.api.post('/api/pulses', { json: { kind: 'goodnight' } });
  assert.equal(first.status, 201);
  const second = await b.api.post('/api/pulses', { json: { kind: 'goodnight' } });
  assert.equal(second.status, 429);
  assert.equal(second.body.error, 'too_soon');
});
