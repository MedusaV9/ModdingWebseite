import { test } from 'node:test';
import assert from 'node:assert/strict';
import { access } from 'node:fs/promises';
import path from 'node:path';
import { makeApp, setupCouple, wsOpen, client } from './helpers.js';

const JPEG = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.from('full-size-jpeg'.repeat(40))]);
const THUMB = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.from('tiny-thumb-jpeg')]);

async function uploadPhoto(who) {
  const res = await who.api.post('/api/photos', { body: JPEG, headers: { 'content-type': 'image/jpeg' } });
  assert.equal(res.status, 201);
  return res.body.photo;
}

test('thumb upload: sets thumbUrl, broadcasts photo_updated, raw fetch via header and ?token=', async (t) => {
  const { baseUrl, dataDir } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const photo = await uploadPhoto(a);
  assert.equal(photo.thumbUrl, null); // photo_added / create response includes the field

  const res = await a.api.post(`/api/photos/${photo.id}/thumb`, {
    body: THUMB,
    headers: { 'content-type': 'image/jpeg' },
  });
  assert.equal(res.status, 200);
  assert.equal(res.body.photo.id, photo.id);
  assert.equal(res.body.photo.thumbUrl, `/api/photos/${photo.id}/thumb/raw`);

  const updated = await bSock.waitFor('photo_updated');
  assert.deepEqual(updated.payload.photo, res.body.photo);

  // Thumb file lives next to the photo in the same media dir.
  await access(path.join(dataDir, 'media', 'photos', `${photo.id}.thumb.jpg`));

  // Listing now reports the thumbUrl.
  const list = await b.api.get('/api/photos');
  assert.equal(list.body.photos.find((p) => p.id === photo.id).thumbUrl, `/api/photos/${photo.id}/thumb/raw`);

  // Raw bytes via Authorization header and via ?token= (AsyncImage style), none → 401.
  const raw = await b.api.get(photo.thumbUrl ?? res.body.photo.thumbUrl);
  assert.equal(raw.status, 200);
  assert.equal(raw.headers.get('content-type'), 'image/jpeg');
  assert.deepEqual(raw.body, THUMB);
  const rawQuery = await client(baseUrl).get(`${res.body.photo.thumbUrl}?token=${b.token}`);
  assert.equal(rawQuery.status, 200);
  assert.deepEqual(rawQuery.body, THUMB);
  assert.equal((await client(baseUrl).get(res.body.photo.thumbUrl)).status, 401);
});

test('thumb errors: partner upload → 403 not_yours, unknown photo → 404, no thumb → 404 no_thumb, > 2 MB → 413', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const photo = await uploadPhoto(a);

  // Only the uploader may attach a thumb.
  const denied = await b.api.post(`/api/photos/${photo.id}/thumb`, {
    body: THUMB,
    headers: { 'content-type': 'image/jpeg' },
  });
  assert.equal(denied.status, 403);
  assert.equal(denied.body.error, 'not_yours');

  const unknown = await a.api.post('/api/photos/ph_nope/thumb', {
    body: THUMB,
    headers: { 'content-type': 'image/jpeg' },
  });
  assert.equal(unknown.status, 404);
  assert.equal(unknown.body.error, 'not_found');

  // No thumb uploaded yet → 404 no_thumb (photo itself exists).
  const missing = await b.api.get(`/api/photos/${photo.id}/thumb/raw`);
  assert.equal(missing.status, 404);
  assert.equal(missing.body.error, 'no_thumb');
  assert.equal((await a.api.get('/api/photos/ph_nope/thumb/raw')).status, 404);

  const huge = Buffer.alloc(2 * 1024 * 1024 + 1);
  const tooBig = await a.api.post(`/api/photos/${photo.id}/thumb`, {
    body: huge,
    headers: { 'content-type': 'image/jpeg' },
  });
  assert.equal(tooBig.status, 413);
  assert.equal(tooBig.body.error, 'too_large');

  const empty = await a.api.post(`/api/photos/${photo.id}/thumb`, { headers: { 'content-type': 'image/jpeg' } });
  assert.equal(empty.status, 400);
});

test('deleting a photo removes its thumb file; couple dissolve wipes thumbs too', async (t) => {
  const { baseUrl, dataDir } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);

  const doomed = await uploadPhoto(a);
  await a.api.post(`/api/photos/${doomed.id}/thumb`, { body: THUMB, headers: { 'content-type': 'image/jpeg' } });
  const doomedThumb = path.join(dataDir, 'media', 'photos', `${doomed.id}.thumb.jpg`);
  await access(doomedThumb);

  assert.equal((await a.api.del(`/api/photos/${doomed.id}`)).status, 200);
  await assert.rejects(access(doomedThumb));
  assert.equal((await a.api.get(`/api/photos/${doomed.id}/thumb/raw`)).status, 404);

  // Dissolve: remaining photo + thumb files are wiped from the media dir.
  const survivor = await uploadPhoto(a);
  await a.api.post(`/api/photos/${survivor.id}/thumb`, { body: THUMB, headers: { 'content-type': 'image/jpeg' } });
  const survivorFile = path.join(dataDir, 'media', 'photos', `${survivor.id}.jpg`);
  const survivorThumb = path.join(dataDir, 'media', 'photos', `${survivor.id}.thumb.jpg`);
  await access(survivorFile);
  await access(survivorThumb);
  assert.equal((await a.api.del('/api/couple')).status, 200);
  await assert.rejects(access(survivorFile));
  await assert.rejects(access(survivorThumb));
});
