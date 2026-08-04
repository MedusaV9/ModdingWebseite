import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple, wsOpen, client } from './helpers.js';

test('coupon lifecycle: create for partner, newest-first list, redeem, broadcasts', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const res = await a.api.post('/api/coupons', {
    json: { title: 'Breakfast in bed', emoji: '🥞', note: 'redeem on a lazy Sunday' },
  });
  assert.equal(res.status, 201);
  const coupon = res.body.coupon;
  assert.match(coupon.id, /^cp_/);
  assert.equal(coupon.title, 'Breakfast in bed');
  assert.equal(coupon.emoji, '🥞');
  assert.equal(coupon.note, 'redeem on a lazy Sunday');
  assert.equal(coupon.createdBy, a.memberId);
  assert.equal(coupon.forMember, b.memberId); // receiver is ALWAYS the partner
  assert.equal(coupon.redeemedAt, null);

  const added = await bSock.waitFor('coupon_added');
  assert.deepEqual(added.payload.coupon, coupon);

  // note is optional; list is newest first.
  const second = (await b.api.post('/api/coupons', { json: { title: 'Movie night', emoji: '🎬' } })).body.coupon;
  assert.equal(second.note, null);
  assert.equal(second.forMember, a.memberId);
  const list = await a.api.get('/api/coupons');
  assert.deepEqual(list.body.coupons.map((cp) => cp.id), [second.id, coupon.id]);

  // Redeem by the receiver.
  const redeemed = await b.api.post(`/api/coupons/${coupon.id}/redeem`);
  assert.equal(redeemed.status, 200);
  assert.ok(redeemed.body.coupon.redeemedAt);
  const redeemFrame = await bSock.waitFor('coupon_redeemed');
  assert.deepEqual(redeemFrame.payload.coupon, redeemed.body.coupon);

  // Delete an unredeemed coupon by its creator.
  const del = await b.api.del(`/api/coupons/${second.id}`);
  assert.deepEqual(del.body, { ok: true });
  const delFrame = await bSock.waitFor('coupon_deleted');
  assert.deepEqual(delFrame.payload, { id: second.id });
  assert.deepEqual((await a.api.get('/api/coupons')).body.coupons.map((cp) => cp.id), [coupon.id]);
});

test('coupon permission matrix: no_partner, wrong redeemer, double redeem, wrong deleter, delete redeemed', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  // A fresh single-member couple cannot create coupons.
  const solo = await client(baseUrl).post('/api/couples', { json: { name: 'Solo' } });
  const soloApi = client(baseUrl, solo.body.token);
  const noPartner = await soloApi.post('/api/coupons', { json: { title: 'For no one', emoji: '👻' } });
  assert.equal(noPartner.status, 409);
  assert.equal(noPartner.body.error, 'no_partner');

  const coupon = (await a.api.post('/api/coupons', { json: { title: 'Massage', emoji: '💆' } })).body.coupon;

  // The creator cannot redeem their own gift.
  const wrongRedeemer = await a.api.post(`/api/coupons/${coupon.id}/redeem`);
  assert.equal(wrongRedeemer.status, 403);
  assert.equal(wrongRedeemer.body.error, 'not_yours');

  // The receiver cannot delete it (only the creator can).
  const wrongDeleter = await b.api.del(`/api/coupons/${coupon.id}`);
  assert.equal(wrongDeleter.status, 403);
  assert.equal(wrongDeleter.body.error, 'not_yours');

  // Redeem once → ok; twice → 409.
  assert.equal((await b.api.post(`/api/coupons/${coupon.id}/redeem`)).status, 200);
  const twice = await b.api.post(`/api/coupons/${coupon.id}/redeem`);
  assert.equal(twice.status, 409);
  assert.equal(twice.body.error, 'already_redeemed');

  // Redeemed coupons cannot be deleted, not even by the creator.
  const delRedeemed = await a.api.del(`/api/coupons/${coupon.id}`);
  assert.equal(delRedeemed.status, 409);
  assert.equal(delRedeemed.body.error, 'already_redeemed');

  // Unknown ids → 404; empty title → 400.
  assert.equal((await a.api.post('/api/coupons/cp_nope/redeem')).status, 404);
  assert.equal((await a.api.del('/api/coupons/cp_nope')).status, 404);
  assert.equal((await a.api.post('/api/coupons', { json: { title: '  ', emoji: '🎟' } })).status, 400);
});

test('coupon expiry: expiresAt stored (normalized ISO), broadcast, expired redeem → 409 expired', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  // Future expiry: stored, normalized to ISO with milliseconds, redeemable.
  const res = await a.api.post('/api/coupons', {
    json: { title: 'Spa day', emoji: '🧖', expiresAt: '2030-06-01T12:00:00Z' },
  });
  assert.equal(res.status, 201);
  assert.equal(res.body.coupon.expiresAt, '2030-06-01T12:00:00.000Z');
  const added = await bSock.waitFor('coupon_added');
  assert.deepEqual(added.payload.coupon, res.body.coupon);
  const redeemed = await b.api.post(`/api/coupons/${res.body.coupon.id}/redeem`);
  assert.equal(redeemed.status, 200);
  assert.equal(redeemed.body.coupon.expiresAt, '2030-06-01T12:00:00.000Z');
  assert.ok(redeemed.body.coupon.redeemedAt);

  // No / null expiresAt → null.
  const plain = (await a.api.post('/api/coupons', { json: { title: 'No expiry', emoji: '♾️' } })).body.coupon;
  assert.equal(plain.expiresAt, null);
  const explicit = (await a.api.post('/api/coupons', { json: { title: 'Null expiry', emoji: '🫥', expiresAt: null } }))
    .body.coupon;
  assert.equal(explicit.expiresAt, null);

  // Past expiry: creating is allowed, redeeming is not.
  const past = new Date(Date.now() - 60_000).toISOString();
  const stale = (await a.api.post('/api/coupons', { json: { title: 'Too late', emoji: '⌛', expiresAt: past } })).body
    .coupon;
  const denied = await b.api.post(`/api/coupons/${stale.id}/redeem`);
  assert.equal(denied.status, 409);
  assert.equal(denied.body.error, 'expired');
  // Expired coupons stay listed (and deletable by the creator).
  assert.ok((await b.api.get('/api/coupons')).body.coupons.some((cp) => cp.id === stale.id));
  assert.deepEqual((await a.api.del(`/api/coupons/${stale.id}`)).body, { ok: true });

  // Invalid expiresAt → 400 bad_expiry.
  for (const bad of ['not-a-date', 42, true]) {
    const invalid = await a.api.post('/api/coupons', { json: { title: 'Bad', emoji: '❓', expiresAt: bad } });
    assert.equal(invalid.status, 400);
    assert.equal(invalid.body.error, 'bad_expiry');
  }
});

test('pre-v1.6 coupons without expiresAt serialize expiresAt: null', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a, b, coupleId } = await setupCouple(baseUrl);
  // A coupon exactly as a v1.5 server stored it: no expiresAt key at all.
  app.store.data.couples[coupleId].coupons.push({
    id: 'cp_legacy',
    title: 'From the old days',
    emoji: '📼',
    note: null,
    createdBy: a.memberId,
    forMember: b.memberId,
    redeemedAt: null,
    createdAt: '2025-01-01T00:00:00.000Z',
  });
  const list = (await b.api.get('/api/coupons')).body.coupons;
  assert.equal(list[0].id, 'cp_legacy');
  assert.equal(list[0].expiresAt, null);
  // Redeeming the legacy coupon works (no expiry ⇒ never expired).
  const redeemed = await b.api.post('/api/coupons/cp_legacy/redeem');
  assert.equal(redeemed.status, 200);
  assert.equal(redeemed.body.coupon.expiresAt, null);
});

test('coupon list caps at 200: oldest redeemed pruned first (with coupon_deleted broadcast), then oldest overall', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const ids = [];
  for (let i = 0; i < 200; i++) {
    const res = await a.api.post('/api/coupons', { json: { title: `coupon ${i}`, emoji: '🎟' } });
    assert.equal(res.status, 201);
    ids.push(res.body.coupon.id);
  }
  // Redeem #5 — it becomes the prune victim despite not being the oldest.
  await b.api.post(`/api/coupons/${ids[5]}/redeem`);

  const overflow1 = (await a.api.post('/api/coupons', { json: { title: 'overflow 1', emoji: '🎟' } })).body.coupon;
  // The cap eviction is announced like a normal delete.
  const evicted1 = await bSock.waitFor('coupon_deleted');
  assert.deepEqual(evicted1.payload, { id: ids[5] });
  let list = (await a.api.get('/api/coupons')).body.coupons;
  assert.equal(list.length, 200);
  assert.ok(!list.some((cp) => cp.id === ids[5])); // redeemed one went first
  assert.ok(list.some((cp) => cp.id === ids[0])); // oldest unredeemed survived

  // No redeemed coupons left → now the oldest overall is pruned (and broadcast).
  const overflow2 = (await a.api.post('/api/coupons', { json: { title: 'overflow 2', emoji: '🎟' } })).body.coupon;
  const evicted2 = await bSock.waitFor('coupon_deleted');
  assert.deepEqual(evicted2.payload, { id: ids[0] });
  list = (await a.api.get('/api/coupons')).body.coupons;
  assert.equal(list.length, 200);
  assert.ok(!list.some((cp) => cp.id === ids[0]));
  assert.equal(list[0].id, overflow2.id);
  assert.equal(list[1].id, overflow1.id);
});
