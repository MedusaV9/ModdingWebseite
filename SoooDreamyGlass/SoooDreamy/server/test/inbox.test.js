import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple, dateKeyDaysAgo } from './helpers.js';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

test('inbox aggregates everything created strictly after since', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  // Everything before `since` must be invisible.
  await a.api.post('/api/messages', { json: { type: 'text', text: 'old news' } });
  await a.api.post('/api/touches', { json: { type: 'kiss' } });
  await sleep(5);
  const since = new Date().toISOString();
  await sleep(5);

  const empty = (await b.api.get(`/api/inbox?since=${encodeURIComponent(since)}`)).body;
  assert.equal(empty.messages.count, 0);
  assert.equal(empty.messages.last, null);
  assert.equal(empty.touches.count, 0);
  assert.equal(empty.touches.last, null);
  assert.equal(empty.photos.count, 0);
  assert.equal(empty.photos.last, null);
  assert.equal(empty.couponsForMe.count, 0);
  assert.equal(empty.couponsForMe.last, null);
  assert.equal(empty.songs.count, 0);
  assert.equal(empty.dailyPartnerAnswered, false);
  assert.equal(empty.canvasStrokes.count, 0);
  assert.ok(empty.serverTime);

  // Now a burst of activity after `since`.
  await a.api.post('/api/messages', { json: { type: 'text', text: 'first' } });
  const longText = 'x'.repeat(200);
  const last = (await a.api.post('/api/messages', { json: { type: 'text', text: longText } })).body.message;
  const partnerTouch = (await a.api.post('/api/touches', { json: { type: 'hug' } })).body.touch;
  await b.api.post('/api/touches', { json: { type: 'kiss' } }); // b's own — must not count for b
  const photo = (
    await a.api.post('/api/photos', {
      body: Buffer.from('jpeg'),
      headers: { 'content-type': 'image/jpeg', 'x-caption': encodeURIComponent('new pic') },
    })
  ).body.photo;
  const coupon = (await a.api.post('/api/coupons', { json: { title: 'For you', emoji: '🎁' } })).body.coupon;
  await b.api.post('/api/coupons', { json: { title: 'From me — must not count', emoji: '🙃' } });
  await a.api.post('/api/songs', { json: { title: 'New tune' } });
  await a.api.post('/api/canvas/strokes', { json: { points: [[0.1, 0.2]] } });
  await a.api.post('/api/canvas/strokes', { json: { points: [[0.3, 0.4]] } });
  await a.api.post(`/api/daily/${dateKeyDaysAgo(0)}`, { json: { questionId: 1, text: 'my answer' } });

  const inbox = (await b.api.get(`/api/inbox?since=${encodeURIComponent(since)}`)).body;
  assert.equal(inbox.messages.count, 2);
  // Teaser: last message with text truncated to 80 chars.
  assert.deepEqual(inbox.messages.last, {
    id: last.id,
    senderId: a.memberId,
    kind: 'text',
    text: 'x'.repeat(80),
    createdAt: last.createdAt,
  });
  // Buckets are partner-only: b's own kiss is invisible to b, and the last
  // touch teaser is the newest PARTNER touch (a's hug), not b's own.
  assert.equal(inbox.touches.count, 1);
  assert.deepEqual(inbox.touches.last, partnerTouch);
  assert.equal(inbox.photos.count, 1);
  assert.deepEqual(inbox.photos.last, { id: photo.id, caption: 'new pic' });
  // couponsForMe: only coupons made FOR me by my partner.
  assert.equal(inbox.couponsForMe.count, 1);
  assert.deepEqual(inbox.couponsForMe.last, coupon);
  assert.equal(inbox.songs.count, 1);
  // Partner (a) answered today's daily question after `since`.
  assert.equal(inbox.dailyPartnerAnswered, true);
  assert.equal(inbox.canvasStrokes.count, 2);
  assert.ok(inbox.serverTime >= since);

  // From a's perspective: partner (b) has NOT answered; the coupon a created
  // is not "for me"; a's own messages/photos/songs/strokes never count.
  const aInbox = (await a.api.get(`/api/inbox?since=${encodeURIComponent(since)}`)).body;
  assert.equal(aInbox.dailyPartnerAnswered, false);
  assert.equal(aInbox.couponsForMe.count, 1); // the one b created for a
  assert.equal(aInbox.messages.count, 0); // both messages are a's own
  assert.equal(aInbox.messages.last, null);
  assert.equal(aInbox.touches.count, 1); // only b's kiss
  assert.equal(aInbox.photos.count, 0);
  assert.equal(aInbox.photos.last, null);
  assert.equal(aInbox.songs.count, 0);
  assert.equal(aInbox.canvasStrokes.count, 0);

  // A fresh `since` after the burst → everything quiet again, except the daily
  // answer which is keyed by answeredAt (still before this new since).
  await sleep(5);
  const later = new Date().toISOString();
  const quiet = (await b.api.get(`/api/inbox?since=${encodeURIComponent(later)}`)).body;
  assert.equal(quiet.messages.count, 0);
  assert.equal(quiet.dailyPartnerAnswered, false);
});

test('inbox validation: since is required and must be a valid timestamp', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  for (const path of ['/api/inbox', '/api/inbox?since=', '/api/inbox?since=yesterday']) {
    const res = await a.api.get(path);
    assert.equal(res.status, 400);
    assert.equal(res.body.error, 'bad_since');
  }
  // Any parseable timestamp works (normalized internally).
  assert.equal((await a.api.get('/api/inbox?since=2020-01-01T00:00:00Z')).status, 200);
});
