import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { makeApp, setupCouple, wsOpen, client } from './helpers.js';
import { postDeliverySweep, startPostDeliveryScheduler, POST_LIMITS } from '../src/post.js';

// FullRelease P6-B „Post-Station": scheduled deliveries (Zeitpost), echo
// replies and the shared journal. The delivery sweep is a pure function of
// (store, now) — due times are injected, the interval scheduler is disabled.

const TOKEN_A = 'aa'.repeat(32);
const TOKEN_B = 'bb'.repeat(32);

const MIN = 60_000;

function inMinutes(minutes) {
  return new Date(Date.now() + minutes * MIN).toISOString();
}

async function waitFor(check) {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    if (check()) return;
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
  assert.fail('timed out waiting for asynchronous delivery');
}

async function postApp(t, options = {}) {
  const deliveries = [];
  const provider = { async send(request) { deliveries.push(request); } };
  const ctx = await makeApp(t, {
    pushProvider: provider,
    postDeliveryIntervalSeconds: 0,
    ...options,
  });
  const pair = await setupCouple(ctx.baseUrl);
  const sweep = (now) => postDeliverySweep({
    store: ctx.app.store, realtime: ctx.app.realtime, push: ctx.app.push, now,
  });
  return { ...ctx, ...pair, deliveries, sweep };
}

// ---------------------------------------------------------------------------
// scheduling

test('schedule: sender-only visibility — the partner never sees a pending post', async (t) => {
  const { a, b } = await postApp(t);
  const res = await a.api.post('/api/post/schedule', {
    json: { kind: 'touch', type: 'kiss', deliverAt: inMinutes(10) },
  });
  assert.equal(res.status, 201);
  assert.match(res.body.post.id, /^zp_/);
  assert.equal(res.body.post.kind, 'touch');
  assert.equal(res.body.post.type, 'kiss');
  assert.equal(res.body.post.senderId, a.memberId);

  const mine = await a.api.get('/api/post/scheduled');
  assert.equal(mine.body.posts.length, 1);
  assert.equal(mine.body.posts[0].id, res.body.post.id);

  // Surprise contract: partner list is empty, partner cancel probes get 404.
  const theirs = await b.api.get('/api/post/scheduled');
  assert.deepEqual(theirs.body.posts, []);
  const probe = await b.api.del(`/api/post/scheduled/${res.body.post.id}`);
  assert.equal(probe.status, 404);
});

test('schedule validation: bad_deliver_at for past, near, far and malformed times', async (t) => {
  const { a } = await postApp(t);
  for (const deliverAt of [
    inMinutes(-10),                    // in the past
    inMinutes(2),                      // below the 5-minute lead
    inMinutes(8 * 24 * 60),            // beyond 7 days
    'tomorrow-ish',                    // not a timestamp
  ]) {
    const res = await a.api.post('/api/post/schedule', {
      json: { kind: 'note', note: 'Hallo du', deliverAt },
    });
    assert.equal(res.status, 400, `deliverAt=${deliverAt}`);
    assert.equal(res.body.error, 'bad_deliver_at');
  }
  // R1-C strictness: Date.parse alone would swallow all of these — RFC-1123
  // dates, zone-less local times and bare dates must be an honest 400, never
  // a silent server-local guess.
  const inTenMinutes = new Date(Date.now() + 10 * MIN);
  for (const deliverAt of [
    inTenMinutes.toUTCString(),                     // RFC-1123 ("Sat, 15 Aug 2026 …")
    inTenMinutes.toISOString().slice(0, 19),        // no timezone designator
    inTenMinutes.toISOString().slice(0, 10),        // bare date, no time
    `${inTenMinutes.toISOString().slice(0, 19)}+0200`, // offset without colon
  ]) {
    const res = await a.api.post('/api/post/schedule', {
      json: { kind: 'note', note: 'Hallo du', deliverAt },
    });
    assert.equal(res.status, 400, `deliverAt=${deliverAt}`);
    assert.equal(res.body.error, 'bad_deliver_at');
  }
  // … while proper RFC-3339 with explicit offset or fraction stays welcome.
  for (const deliverAt of [
    new Date(Date.now() + 10 * MIN).toISOString(),  // 2026-…T…Z (fractional)
    new Date(Date.now() + 10 * MIN).toISOString().replace('Z', '+00:00'),
  ]) {
    const res = await a.api.post('/api/post/schedule', {
      json: { kind: 'note', note: 'Hallo du', deliverAt },
    });
    assert.equal(res.status, 201, `deliverAt=${deliverAt}`);
  }
  // Payload validation: overlong note, unknown kind, unknown touch type.
  const longNote = await a.api.post('/api/post/schedule', {
    json: { kind: 'note', note: 'x'.repeat(POST_LIMITS.note + 1), deliverAt: inMinutes(10) },
  });
  assert.equal(longNote.status, 400);
  const badKind = await a.api.post('/api/post/schedule', {
    json: { kind: 'letter', deliverAt: inMinutes(10) },
  });
  assert.equal(badKind.status, 400);
  const badType = await a.api.post('/api/post/schedule', {
    json: { kind: 'touch', type: 'slap', deliverAt: inMinutes(10) },
  });
  assert.equal(badType.status, 400);
});

test('post_limit: at most 5 open posts per person — the partner keeps their own 5', async (t) => {
  const { a, b } = await postApp(t);
  for (let i = 0; i < POST_LIMITS.maxOpen; i += 1) {
    const res = await a.api.post('/api/post/schedule', {
      json: { kind: 'touch', type: 'hug', deliverAt: inMinutes(10 + i) },
    });
    assert.equal(res.status, 201);
  }
  const sixth = await a.api.post('/api/post/schedule', {
    json: { kind: 'touch', type: 'hug', deliverAt: inMinutes(30) },
  });
  assert.equal(sixth.status, 409);
  assert.equal(sixth.body.error, 'post_limit');

  // The limit is per member, not per couple.
  const partners = await b.api.post('/api/post/schedule', {
    json: { kind: 'pulse', pulseKind: 'goodnight', deliverAt: inMinutes(10) },
  });
  assert.equal(partners.status, 201);
});

test('cancel: own post disappears; cancelling twice → 404', async (t) => {
  const { a } = await postApp(t);
  const res = await a.api.post('/api/post/schedule', {
    json: { kind: 'note', note: 'Bis gleich', deliverAt: inMinutes(10) },
  });
  const canceled = await a.api.del(`/api/post/scheduled/${res.body.post.id}`);
  assert.equal(canceled.status, 200);
  assert.deepEqual((await a.api.get('/api/post/scheduled')).body.posts, []);
  const again = await a.api.del(`/api/post/scheduled/${res.body.post.id}`);
  assert.equal(again.status, 404);
});

test('schedule idempotency: same clientOperationId → duplicate with the ORIGINAL post', async (t) => {
  const { a } = await postApp(t);
  const json = {
    kind: 'touch', type: 'missyou', deliverAt: inMinutes(10), clientOperationId: 'op-zeitpost-1',
  };
  const first = await a.api.post('/api/post/schedule', { json });
  assert.equal(first.status, 201);
  const retry = await a.api.post('/api/post/schedule', { json });
  assert.equal(retry.status, 200);
  assert.equal(retry.body.duplicate, true);
  assert.equal(retry.body.post.id, first.body.post.id);
  assert.equal((await a.api.get('/api/post/scheduled')).body.posts.length, 1);
});

// ---------------------------------------------------------------------------
// delivery sweep

test('delivery: a due touch becomes a normal touch event + WS fanout + partner push', async (t) => {
  const { a, b, baseUrl, deliveries, sweep, app, coupleId } = await postApp(t);
  await a.api.post('/api/push-devices/current', {
    json: { apnsToken: TOKEN_A, environment: 'development', bundleId: 'app.sooodreamy.ios', language: 'de' },
  });
  await b.api.post('/api/push-devices/current', {
    json: { apnsToken: TOKEN_B, environment: 'development', bundleId: 'app.sooodreamy.ios', language: 'de' },
  });
  const aSock = await wsOpen(baseUrl, a.token, t);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await aSock.waitFor('welcome');
  await bSock.waitFor('welcome');

  const scheduled = await a.api.post('/api/post/schedule', {
    json: { kind: 'touch', type: 'stolz', deliverAt: inMinutes(6) },
  });
  assert.equal(scheduled.status, 201);

  // Before the due time nothing moves (the surprise stays a surprise).
  assert.equal(sweep(new Date()), 0);
  await bSock.assertNone('touch');
  assert.equal(deliveries.length, 0);

  // Past due: exactly one delivery, then the open list is empty.
  assert.equal(sweep(new Date(Date.now() + 7 * MIN)), 1);
  const frame = await bSock.waitFor('touch');
  assert.equal(frame.payload.touch.type, 'stolz');
  assert.equal(frame.payload.touch.senderId, a.memberId);
  assert.equal(frame.payload.touch.viaPost, true);
  // The sender's devices converge on the delivered artifact too.
  const own = await aSock.waitFor('touch');
  assert.equal(own.payload.touch.id, frame.payload.touch.id);
  assert.deepEqual((await a.api.get('/api/post/scheduled')).body.posts, []);

  // Push goes to the PARTNER only, with the Zeitpost copy.
  await waitFor(() => deliveries.length === 1);
  assert.equal(deliveries[0].token, TOKEN_B);
  assert.equal(deliveries[0].payload.aps.alert.body, 'Eine Zeitpost von deinem Schatz ist angekommen. 💌');

  // The delivered touch is a NORMAL touch: history + counters.
  const recent = await b.api.get('/api/touches/recent?limit=1');
  assert.equal(recent.body.touches[0].type, 'stolz');
  const couple = app.store.data.couples[coupleId];
  assert.equal(couple.counters.touches[a.memberId].byType.stolz, 1);

  // Sweeping again delivers nothing (at-most-once).
  assert.equal(sweep(new Date(Date.now() + 8 * MIN)), 0);
});

test('delivery: notes arrive as post_note frames, pulses join the unfelt queue', async (t) => {
  const { a, b, baseUrl, sweep } = await postApp(t);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  await a.api.post('/api/post/schedule', {
    json: { kind: 'note', note: 'Denk an dich, kleiner Bär', deliverAt: inMinutes(6) },
  });
  await a.api.post('/api/post/schedule', {
    json: { kind: 'pulse', pulseKind: 'goodnight', deliverAt: inMinutes(6) },
  });
  assert.equal(sweep(new Date(Date.now() + 7 * MIN)), 2);

  const noteFrame = await bSock.waitFor('post_note');
  assert.equal(noteFrame.payload.note.text, 'Denk an dich, kleiner Bär');
  assert.equal(noteFrame.payload.note.senderId, a.memberId);
  const pulseFrame = await bSock.waitFor('pulse');
  assert.equal(pulseFrame.payload.pulse.kind, 'goodnight');
  assert.equal(pulseFrame.payload.pulse.viaPost, true);

  // A delivered pulse behaves like a live one an offline partner missed.
  const unfelt = await b.api.get('/api/pulses');
  assert.equal(unfelt.body.pulses.length, 1);
  assert.equal(unfelt.body.pulses[0].kind, 'goodnight');
});

test('re-sweep idempotency (R1-C): an existing artifact is never minted twice — only its fanout is redone', async (t) => {
  const { a, b, baseUrl, deliveries, sweep, app, coupleId } = await postApp(t);
  await b.api.post('/api/push-devices/current', {
    json: { apnsToken: TOKEN_B, environment: 'development', bundleId: 'app.sooodreamy.ios', language: 'de' },
  });
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const scheduled = await a.api.post('/api/post/schedule', {
    json: { kind: 'touch', type: 'hug', deliverAt: inMinutes(6) },
  });
  const couple = app.store.data.couples[coupleId];
  const openPost = { ...couple.post.scheduled[0] };
  assert.equal(sweep(new Date(Date.now() + 7 * MIN)), 1);

  // The artifact id is STABLE — derived from the post id, not random.
  const first = await bSock.waitFor('touch');
  assert.equal(first.payload.touch.id, `t_${scheduled.body.post.id}`);
  const minted = () => couple.touches.filter((x) => x.postId === scheduled.body.post.id);
  assert.equal(minted().length, 1);
  const hugsAfterFirst = couple.counters.touches[a.memberId].byType.hug;
  await waitFor(() => deliveries.length === 1);

  // Simulate the crash-recovery state the stable id exists for: the post is
  // back in the open list (lost removal / regressed generation) while its
  // artifact already exists. The re-sweep must NOT mint a second artifact or
  // bump counters again — it only redoes the fanout (at-least-once notify).
  couple.post.scheduled.push(openPost);
  assert.equal(sweep(new Date(Date.now() + 8 * MIN)), 1);
  assert.equal(couple.post.scheduled.length, 0);
  assert.equal(minted().length, 1, 'no double artifact');
  assert.equal(couple.counters.touches[a.memberId].byType.hug, hugsAfterFirst, 'no double counter bump');
  const second = await bSock.waitFor('touch');
  assert.equal(second.payload.touch.id, first.payload.touch.id, 'the redone fanout carries the SAME artifact');
  await waitFor(() => deliveries.length === 2);
});

test('push privacy regression: the note text NEVER appears anywhere in the push payload', async (t) => {
  const { a, b, deliveries, sweep } = await postApp(t);
  await b.api.post('/api/push-devices/current', {
    json: { apnsToken: TOKEN_B, environment: 'development', bundleId: 'app.sooodreamy.ios', language: 'de' },
  });
  const secret = 'Geheime Zeile nur fuer dich 4711';
  await a.api.post('/api/post/schedule', {
    json: { kind: 'note', note: secret, deliverAt: inMinutes(6) },
  });
  assert.equal(sweep(new Date(Date.now() + 7 * MIN)), 1);
  await waitFor(() => deliveries.length === 1);
  // Assert on the COMPLETE provider request JSON — not just alert.body: the
  // text must not leak via title, link, type or any future payload field.
  const raw = JSON.stringify(deliveries[0]);
  assert.equal(raw.includes(secret), false);
  assert.equal(raw.includes('4711'), false);
  assert.equal(deliveries[0].payload.aps.alert.body, 'Eine kleine Notiz ist für dich angekommen. 💌');
});

// ---------------------------------------------------------------------------
// scheduler lifecycle (R1-C)

test('scheduler lifecycle: the interval delivers each due post exactly once, stop() halts it, double-stop is safe', async (t) => {
  const { a, app, coupleId } = await postApp(t); // app-level scheduler disabled (0)
  const couple = () => app.store.data.couples[coupleId];
  const stop = startPostDeliveryScheduler({
    store: app.store, realtime: app.realtime, push: app.push, intervalSeconds: 0.05,
  });

  await a.api.post('/api/post/schedule', {
    json: { kind: 'note', note: 'Tick eins', deliverAt: inMinutes(6) },
  });
  couple().post.scheduled[0].deliverAt = new Date(Date.now() - 1000).toISOString();
  await waitFor(() => couple().post.notes.length === 1);
  // Several more ticks pass: still exactly one artifact, the open list empty.
  await new Promise((resolve) => setTimeout(resolve, 200));
  assert.equal(couple().post.notes.length, 1);
  assert.equal(couple().post.scheduled.length, 0);

  stop();
  await a.api.post('/api/post/schedule', {
    json: { kind: 'note', note: 'Tick zwei', deliverAt: inMinutes(6) },
  });
  couple().post.scheduled[0].deliverAt = new Date(Date.now() - 1000).toISOString();
  await new Promise((resolve) => setTimeout(resolve, 250)); // 5 would-be ticks
  // Also proves no second (app-level) scheduler was ever started alongside.
  assert.equal(couple().post.notes.length, 1, 'a stopped scheduler must not deliver');
  assert.equal(couple().post.scheduled.length, 1);
  stop(); // double-stop is a harmless no-op

  // intervalSeconds 0 disables: the returned stop is a no-op, no timer runs.
  const noop = startPostDeliveryScheduler({
    store: app.store, realtime: app.realtime, push: app.push, intervalSeconds: 0,
  });
  noop();
  await new Promise((resolve) => setTimeout(resolve, 120));
  assert.equal(couple().post.notes.length, 1);
});

test('scheduler close integration: app.close() stops the sweep — nothing fires afterwards', async (t) => {
  const logLines = [];
  const ctx = await makeApp(t, {
    postDeliveryIntervalSeconds: 0.05,
    log: (...values) => logLines.push(values.join(' ')),
  });
  const pair = await setupCouple(ctx.baseUrl);
  await pair.a.api.post('/api/post/schedule', {
    json: { kind: 'note', note: 'Nach dem Close', deliverAt: inMinutes(6) },
  });
  const couple = ctx.app.store.data.couples[pair.coupleId];
  await ctx.close();

  // Make the post due only AFTER close. A leaked interval would sweep now,
  // hit the closed store's markDirty and log 'post: delivery failed'.
  couple.post.scheduled[0].deliverAt = new Date(Date.now() - 1000).toISOString();
  await new Promise((resolve) => setTimeout(resolve, 250));
  assert.equal(couple.post.scheduled.length, 1, 'no sweep may run after close()');
  assert.equal(couple.post.notes.length, 0);
  assert.ok(!logLines.some((line) => line.includes('post: delivery')));
});

test('persistence roundtrip: a scheduled post survives a full server restart', async () => {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'sooodreamy-post-'));
  let second = null;
  try {
    const first = await makeApp(null, { dataDir: dir, postDeliveryIntervalSeconds: 0 });
    const pair = await setupCouple(first.baseUrl);
    const scheduled = await pair.a.api.post('/api/post/schedule', {
      json: { kind: 'note', note: 'Neustart-fest 💌', deliverAt: inMinutes(6) },
    });
    assert.equal(scheduled.status, 201);
    await first.close();

    second = await makeApp(null, { dataDir: dir, postDeliveryIntervalSeconds: 0 });
    const api = client(second.baseUrl, pair.a.token);
    const reloaded = await api.get('/api/post/scheduled');
    assert.equal(reloaded.body.posts.length, 1);
    assert.equal(reloaded.body.posts[0].id, scheduled.body.post.id);

    const delivered = postDeliverySweep({
      store: second.app.store,
      realtime: second.app.realtime,
      push: second.app.push,
      now: new Date(Date.now() + 7 * MIN),
    });
    assert.equal(delivered, 1);
    const journal = await api.get('/api/post/journal');
    assert.equal(journal.body.entries[0].kind, 'note');
    assert.equal(journal.body.entries[0].note, 'Neustart-fest 💌');
  } finally {
    await second?.close();
    await rm(dir, { recursive: true, force: true });
  }
});

test('multi-device: post_scheduled/post_canceled reach ONLY the sender´s other devices', async (t) => {
  const { a, b, baseUrl } = await postApp(t);
  // Attach a second device to Mia via link code.
  const issued = await a.api.post('/api/sessions/link-code');
  assert.equal(issued.status, 201);
  const linked = await client(baseUrl).post('/api/couples/link', {
    json: { code: issued.body.linkCode, deviceName: 'Mias iPad', deviceId: 'mia-ipad-0001' },
  });
  assert.equal(linked.status, 200);

  const aPhone = await wsOpen(baseUrl, a.token, t);
  const aPad = await wsOpen(baseUrl, linked.body.token, t);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await aPhone.waitFor('welcome');
  await aPad.waitFor('welcome');
  await bSock.waitFor('welcome');

  const res = await a.api.post('/api/post/schedule', {
    json: { kind: 'touch', type: 'kiss', deliverAt: inMinutes(10) },
  });
  const padFrame = await aPad.waitFor('post_scheduled');
  assert.equal(padFrame.payload.post.id, res.body.post.id);
  await aPhone.assertNone('post_scheduled'); // the calling session already knows
  await bSock.assertNone('post_scheduled');  // the partner must NEVER know

  await a.api.del(`/api/post/scheduled/${res.body.post.id}`);
  const gone = await aPad.waitFor('post_canceled');
  assert.equal(gone.payload.id, res.body.post.id);
  await bSock.assertNone('post_canceled');
});

// ---------------------------------------------------------------------------
// echoes

test('echo: a received touch bounces back once — echo_taken on the second try', async (t) => {
  const { a, b, baseUrl } = await postApp(t);
  const aSock = await wsOpen(baseUrl, a.token, t);
  await aSock.waitFor('welcome');

  const sent = await a.api.post('/api/touches', { json: { type: 'kiss' } });
  const echoed = await b.api.post(`/api/touches/${sent.body.touch.id}/echo`, { json: {} });
  assert.equal(echoed.status, 201);
  assert.equal(echoed.body.touch.type, 'kiss'); // same kind, mirrored
  assert.equal(echoed.body.touch.echo, true);
  assert.equal(echoed.body.touch.echoOf, sent.body.touch.id);
  assert.equal(echoed.body.touch.senderId, b.memberId);

  // The echo travels the normal touch fanout back to the original sender.
  const frame = await aSock.waitFor('touch');
  assert.equal(frame.payload.touch.echoOf, sent.body.touch.id);

  const second = await b.api.post(`/api/touches/${sent.body.touch.id}/echo`, { json: {} });
  assert.equal(second.status, 409);
  assert.equal(second.body.error, 'echo_taken');

  // R1-C: echoing an ECHO refuses too — one bounce per touch, no ping-pong
  // chains (the client never offered a counter-echo; server agrees now).
  const chained = await a.api.post(`/api/touches/${echoed.body.touch.id}/echo`, { json: {} });
  assert.equal(chained.status, 409);
  assert.equal(chained.body.error, 'echo_taken');
  assert.match(chained.body.message, /one bounce/);
});

test('echo guards: 10-minute window, own touches and unknown ids refuse', async (t) => {
  const { a, b, app, coupleId } = await postApp(t);
  const sent = await a.api.post('/api/touches', { json: { type: 'hug' } });

  // Own touch: the sender cannot echo themselves.
  const own = await a.api.post(`/api/touches/${sent.body.touch.id}/echo`, { json: {} });
  assert.equal(own.status, 400);

  // Age the touch past the window directly in the store.
  const couple = app.store.data.couples[coupleId];
  const touch = couple.touches.find((x) => x.id === sent.body.touch.id);
  touch.createdAt = new Date(Date.now() - (POST_LIMITS.echoWindowMs + MIN)).toISOString();
  const expired = await b.api.post(`/api/touches/${sent.body.touch.id}/echo`, { json: {} });
  assert.equal(expired.status, 409);
  assert.equal(expired.body.error, 'echo_expired');

  const unknown = await b.api.post('/api/touches/t_nope/echo', { json: {} });
  assert.equal(unknown.status, 404);
});

test('echo idempotency: a lost-response retry returns the ORIGINAL echo', async (t) => {
  const { a, b } = await postApp(t);
  const sent = await a.api.post('/api/touches', { json: { type: 'tickle' } });
  const json = { clientOperationId: 'op-echo-1' };
  const first = await b.api.post(`/api/touches/${sent.body.touch.id}/echo`, { json });
  assert.equal(first.status, 201);
  const retry = await b.api.post(`/api/touches/${sent.body.touch.id}/echo`, { json });
  assert.equal(retry.status, 200);
  assert.equal(retry.body.duplicate, true);
  assert.equal(retry.body.touch.id, first.body.touch.id);
});

// ---------------------------------------------------------------------------
// journal

test('journal: one merged 30-day chronology — newest first, echo chain, Zeitpost flag', async (t) => {
  const { a, b, app, coupleId, sweep } = await postApp(t);
  const sent = await a.api.post('/api/touches', { json: { type: 'kiss' } });
  const echoed = await b.api.post(`/api/touches/${sent.body.touch.id}/echo`, { json: {} });
  await b.api.post('/api/pulses', { json: { kind: 'heartbeat' } });
  await a.api.post('/api/post/schedule', {
    json: { kind: 'note', note: 'Kleine Zeitkapsel', deliverAt: inMinutes(6) },
  });

  // Undelivered posts are invisible — for BOTH partners.
  for (const who of [a, b]) {
    const before = await who.api.get('/api/post/journal');
    assert.ok(!before.body.entries.some((e) => e.kind === 'note'));
  }
  sweep(new Date(Date.now() + 7 * MIN));

  // Pin deterministic timestamps so the expected order is exact.
  const couple = app.store.data.couples[coupleId];
  const at = (minutesAgo) => new Date(Date.now() - minutesAgo * MIN).toISOString();
  couple.touches.find((x) => x.id === sent.body.touch.id).createdAt = at(9);
  couple.touches.find((x) => x.id === echoed.body.touch.id).createdAt = at(8);
  couple.pulses[0].createdAt = at(7);
  couple.post.notes[0].createdAt = at(6);

  const journal = await b.api.get('/api/post/journal');
  assert.deepEqual(journal.body.entries.map((e) => e.kind), ['note', 'pulse', 'touch', 'touch']);
  const [note, pulse, echo, original] = journal.body.entries;
  assert.equal(note.viaPost, true);
  assert.equal(note.note, 'Kleine Zeitkapsel');
  assert.equal(note.senderId, a.memberId);
  assert.equal(pulse.pulseKind, 'heartbeat');
  assert.equal(echo.echo, true);
  assert.equal(echo.echoOf, original.id); // the chain is walkable
  assert.equal(original.echo, false);

  // limit= caps the slice; entries older than 30 days fall out entirely.
  const limited = await b.api.get('/api/post/journal?limit=2');
  assert.equal(limited.body.entries.length, 2);
  couple.touches.find((x) => x.id === sent.body.touch.id).createdAt = at(31 * 24 * 60);
  const pruned = await b.api.get('/api/post/journal');
  assert.ok(!pruned.body.entries.some((e) => e.id === sent.body.touch.id));
});

// ---------------------------------------------------------------------------
// new touch kinds + old clients

test('new touch kinds: stolz and haltedurch are first-class touches', async (t) => {
  const { a, b, baseUrl } = await postApp(t);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  for (const type of ['stolz', 'haltedurch']) {
    const res = await a.api.post('/api/touches', { json: { type } });
    assert.equal(res.status, 201, type);
    const frame = await bSock.waitFor('touch', (m) => m.payload.touch.type === type);
    assert.equal(frame.payload.touch.senderId, a.memberId);
  }
  const recent = await a.api.get('/api/touches/recent?limit=2');
  assert.deepEqual(recent.body.touches.map((x) => x.type), ['haltedurch', 'stolz']);
});

test('old clients: unknown fields on the touch wire shape are additive only', async (t) => {
  // Old clients decode {id, type, senderId, createdAt} — the P6-B additions
  // (echo/echoOf/viaPost) must be EXTRA fields on top, never a reshaping.
  const { a, b, sweep } = await postApp(t);
  const plain = await a.api.post('/api/touches', { json: { type: 'kiss' } });
  for (const key of ['id', 'type', 'senderId', 'createdAt']) {
    assert.ok(plain.body.touch[key], `plain touch keeps ${key}`);
  }
  assert.equal(plain.body.touch.echo, undefined); // plain sends stay lean

  const echoed = await b.api.post(`/api/touches/${plain.body.touch.id}/echo`, { json: {} });
  await a.api.post('/api/post/schedule', {
    json: { kind: 'touch', type: 'thinking', deliverAt: inMinutes(6) },
  });
  sweep(new Date(Date.now() + 7 * MIN));
  const recent = await a.api.get('/api/touches/recent?limit=3');
  for (const touch of recent.body.touches) {
    for (const key of ['id', 'type', 'senderId', 'createdAt']) {
      assert.ok(touch[key], `touch ${touch.id} keeps ${key}`);
    }
  }
  const echoWire = recent.body.touches.find((x) => x.id === echoed.body.touch.id);
  assert.equal(echoWire.echo, true);
  const delivered = recent.body.touches.find((x) => x.viaPost);
  assert.equal(delivered.type, 'thinking');
});
