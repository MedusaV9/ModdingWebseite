import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple, wsOpen } from './helpers.js';

test('photo favorites: toggle on/off by both members with photo_updated broadcasts', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const photo = (
    await a.api.post('/api/photos', { body: Buffer.from('jpeg'), headers: { 'content-type': 'image/jpeg' } })
  ).body.photo;
  assert.deepEqual(photo.favorites, []); // serialization includes the field from the start

  // A favorites → broadcast carries the updated photo.
  const on = await a.api.post(`/api/photos/${photo.id}/favorite`);
  assert.equal(on.status, 200);
  assert.deepEqual(on.body.photo.favorites, [a.memberId]);
  const frame = await bSock.waitFor('photo_updated');
  assert.deepEqual(frame.payload.photo, on.body.photo);

  // Partner favorites too (favorites is not uploader-restricted).
  const both = await b.api.post(`/api/photos/${photo.id}/favorite`);
  assert.deepEqual(both.body.photo.favorites, [a.memberId, b.memberId]);
  await bSock.waitFor('photo_updated', (m) => m.payload.photo.favorites.length === 2);

  // Toggle off → back to empty; the listing agrees.
  await a.api.post(`/api/photos/${photo.id}/favorite`);
  const off = await b.api.post(`/api/photos/${photo.id}/favorite`);
  assert.deepEqual(off.body.photo.favorites, []);
  const list = await a.api.get('/api/photos');
  assert.deepEqual(list.body.photos[0].favorites, []);

  // Unknown photo → 404.
  assert.equal((await a.api.post('/api/photos/ph_nope/favorite')).status, 404);
});
