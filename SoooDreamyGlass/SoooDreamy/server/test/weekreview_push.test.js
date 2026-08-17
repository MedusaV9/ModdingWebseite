import { test } from 'node:test';
import assert from 'node:assert/strict';
import { weekReviewArrivalSweep } from '../src/weekreview.js';
import { makeApp, setupCouple, client } from './helpers.js';

// Sunday-evening arrival push for „Eure Woche": both partners get the SAME
// push once the couple-local clock passes Sunday 19:00, deduped per ISO week.
// The sweep is a pure function of (store, now) — all times here are injected.

const TOKEN_A = 'aa'.repeat(32);
const TOKEN_B = 'bb'.repeat(32);

// 2026-08-16 and 2026-08-23 are Sundays.
const SUNDAY_1930_BERLIN = new Date('2026-08-16T17:30:00Z'); // UTC+2 in August
const SUNDAY_1859_BERLIN = new Date('2026-08-16T16:59:00Z');
const SATURDAY_2000_BERLIN = new Date('2026-08-15T18:00:00Z');
const NEXT_SUNDAY_1930_BERLIN = new Date('2026-08-23T17:30:00Z');
const SUNDAY_1930_NEW_YORK = new Date('2026-08-16T23:30:00Z'); // EDT = UTC-4

async function waitFor(check) {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    if (check()) return;
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
  assert.fail('timed out waiting for asynchronous push delivery');
}

async function arrivalCouple(t, timezone) {
  const deliveries = [];
  const provider = { async send(request) { deliveries.push(request); } };
  const { baseUrl, app } = await makeApp(t, { pushProvider: provider, weekReviewPushIntervalMinutes: 0 });
  const { a, b, coupleId } = await setupCouple(baseUrl);
  await a.api.post('/api/push-devices/current', {
    json: { apnsToken: TOKEN_A, environment: 'development', bundleId: 'app.sooodreamy.ios', language: 'en' },
  });
  await b.api.post('/api/push-devices/current', {
    json: { apnsToken: TOKEN_B, environment: 'development', bundleId: 'app.sooodreamy.ios', language: 'de' },
  });
  if (timezone) {
    const patched = await a.api.patch('/api/couple', { json: { timezone } });
    assert.equal(patched.status, 200);
    assert.equal(patched.body.couple.timezone, timezone);
  }
  const sweep = (now) => weekReviewArrivalSweep({ store: app.store, push: app.push, now });
  return { deliveries, app, a, b, coupleId, sweep };
}

test('Sunday 19:00 couple-local: BOTH partners get the localized arrival push once', async (t) => {
  const { deliveries, app, coupleId, sweep } = await arrivalCouple(t, 'Europe/Berlin');

  // Saturday evening and Sunday 18:59 local: still quiet.
  assert.equal(sweep(SATURDAY_2000_BERLIN), 0);
  assert.equal(sweep(SUNDAY_1859_BERLIN), 0);
  assert.equal(deliveries.length, 0);

  // Sunday 19:30 local: one queued couple, two devices, localized copy.
  assert.equal(sweep(SUNDAY_1930_BERLIN), 1);
  await waitFor(() => deliveries.length === 2);
  const byToken = Object.fromEntries(deliveries.map((d) => [d.token, d]));
  assert.equal(byToken[TOKEN_A].payload.aps.alert.title, 'Your week is ready ✨');
  assert.equal(byToken[TOKEN_B].payload.aps.alert.title, 'Eure Woche ist fertig ✨');
  for (const delivery of deliveries) {
    assert.equal(delivery.payload.type, 'weekreview');
    assert.equal(delivery.payload.link, 'sooodreamy://weekreview');
  }

  // Dedupe: later sweeps the same evening stay silent…
  assert.equal(sweep(new Date(SUNDAY_1930_BERLIN.getTime() + 60 * 60 * 1000)), 0);
  assert.equal(deliveries.length, 2);
  const couple = app.store.data.couples[coupleId];
  assert.ok(couple.weekReview.arrivalPush['2026-W33'], 'dedupe marker per ISO week');

  // …but NEXT Sunday announces the next issue.
  assert.equal(sweep(NEXT_SUNDAY_1930_BERLIN), 1);
  await waitFor(() => deliveries.length === 4);
  assert.ok(couple.weekReview.arrivalPush['2026-W34']);
});

test('timezone-fair: the same UTC instant is Sunday evening only where it IS Sunday evening', async (t) => {
  const berlin = await arrivalCouple(t, 'Europe/Berlin');
  const newYork = await arrivalCouple(t, 'America/New_York');

  // 17:30 UTC: 19:30 in Berlin (push), 13:30 in New York (nothing yet).
  assert.equal(berlin.sweep(SUNDAY_1930_BERLIN), 1);
  assert.equal(newYork.sweep(SUNDAY_1930_BERLIN), 0);

  // 23:30 UTC: New York reaches ITS 19:30.
  assert.equal(newYork.sweep(SUNDAY_1930_NEW_YORK), 1);
  await waitFor(() => newYork.deliveries.length === 2);
});

test('solo couples and unknown weeks stay silent; sweep survives a corrupt stored timezone', async (t) => {
  const deliveries = [];
  const provider = { async send(request) { deliveries.push(request); } };
  const { baseUrl, app } = await makeApp(t, { pushProvider: provider, weekReviewPushIntervalMinutes: 0 });
  const anon = client(baseUrl);
  const solo = await anon.post('/api/couples', { json: { name: 'Solo' } });
  assert.equal(solo.status, 201);

  // Solo couple: no shared ritual, no push, no marker.
  assert.equal(weekReviewArrivalSweep({ store: app.store, push: app.push, now: SUNDAY_1930_BERLIN, defaultTimezone: 'Europe/Berlin' }), 0);

  // A corrupt timezone written around the API must not kill the whole sweep.
  const { coupleId } = await setupCouple(baseUrl);
  app.store.data.couples[coupleId].timezone = 'Not/AZone';
  assert.equal(
    // UTC fallback: 17:30 UTC is Sunday but before 19:00 UTC → quiet, no crash.
    weekReviewArrivalSweep({ store: app.store, push: app.push, now: SUNDAY_1930_BERLIN }),
    0,
  );
});

test('PATCH /api/couple validates the timezone and null clears it', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);

  const bad = await a.api.patch('/api/couple', { json: { timezone: 'Mars/OlympusMons' } });
  assert.equal(bad.status, 400);
  assert.equal(bad.body.error, 'bad_timezone');

  const set = await a.api.patch('/api/couple', { json: { timezone: 'Europe/Berlin' } });
  assert.equal(set.status, 200);
  assert.equal(set.body.couple.timezone, 'Europe/Berlin');

  const cleared = await a.api.patch('/api/couple', { json: { timezone: null } });
  assert.equal(cleared.body.couple.timezone, null);
});
