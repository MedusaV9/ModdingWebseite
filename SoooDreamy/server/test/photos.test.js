import { test } from 'node:test';
import assert from 'node:assert/strict';
import { access } from 'node:fs/promises';
import path from 'node:path';
import { makeApp, setupCouple, wsOpen, client } from './helpers.js';

const CAPTION = 'Sonnenuntergang über München 🌇 — schön wär\'s!';

test('photo upload with URI-encoded umlaut caption, list, raw fetch, delete', async (t) => {
  const { baseUrl, dataDir } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const jpeg = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.from('fake-jpeg-body'.repeat(50))]);
  const res = await a.api.post('/api/photos', {
    body: jpeg,
    headers: {
      'content-type': 'image/jpeg',
      'x-caption': encodeURIComponent(CAPTION),
      'x-width': '1920',
      'x-height': '1080',
    },
  });
  assert.equal(res.status, 201);
  const photo = res.body.photo;
  assert.equal(photo.caption, CAPTION);
  assert.equal(photo.width, 1920);
  assert.equal(photo.height, 1080);
  assert.equal(photo.uploaderId, a.memberId);
  assert.equal(photo.url, `/api/photos/${photo.id}/raw`);

  const added = await bSock.waitFor('photo_added');
  assert.deepEqual(added.payload.photo, photo);

  // File exists on disk.
  await access(path.join(dataDir, 'media', 'photos', `${photo.id}.jpg`));

  // List (newest first).
  await a.api.post('/api/photos', { body: jpeg, headers: { 'content-type': 'image/jpeg' } });
  const list = await b.api.get('/api/photos');
  assert.equal(list.body.photos.length, 2);
  assert.equal(list.body.photos[1].id, photo.id);
  assert.equal(list.body.photos[0].caption, null);

  // Raw bytes require header auth; URL credentials are rejected.
  const raw = await b.api.get(photo.url);
  assert.equal(raw.status, 200);
  assert.equal(raw.headers.get('content-type'), 'image/jpeg');
  assert.deepEqual(raw.body, jpeg);
  const rawQuery = await client(baseUrl).get(`${photo.url}?token=${a.token}`);
  assert.equal(rawQuery.status, 400);
  assert.equal(rawQuery.body.error, 'query_token_forbidden');
  assert.equal((await client(baseUrl).get(photo.url)).status, 401);

  // Delete: broadcast + metadata + file gone.
  const del = await a.api.del(`/api/photos/${photo.id}`);
  assert.equal(del.status, 200);
  const deleted = await bSock.waitFor('photo_deleted');
  assert.deepEqual(deleted.payload, { id: photo.id });
  assert.equal((await a.api.get(photo.url)).status, 404);
  await assert.rejects(access(path.join(dataDir, 'media', 'photos', `${photo.id}.jpg`)));
  assert.equal((await a.api.del(`/api/photos/${photo.id}`)).status, 404);
});

test('photo body over 15 MB → 413, empty body → 400', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  const huge = Buffer.alloc(15 * 1024 * 1024 + 1);
  const res = await a.api.post('/api/photos', { body: huge, headers: { 'content-type': 'image/jpeg' } });
  assert.equal(res.status, 413);
  assert.equal(res.body.error, 'too_large');

  const empty = await a.api.post('/api/photos', { headers: { 'content-type': 'image/jpeg' } });
  assert.equal(empty.status, 400);
});

test('global media byte quota is reserved before an upload is written', async (t) => {
  const { baseUrl } = await makeApp(t, { mediaQuotaBytes: 1 });
  const { a } = await setupCouple(baseUrl);
  const rejected = await a.api.post('/api/photos', {
    body: Buffer.alloc(10, 1),
    headers: { 'content-type': 'image/jpeg' },
  });
  assert.equal(rejected.status, 507);
  assert.equal(rejected.body.error, 'media_quota_exceeded');
  const health = await client(baseUrl).get('/api/health');
  assert.equal(health.body.storage.mediaBytes, 0);
});

test('photo albums: default null, PATCH caption/album by either partner, photo_updated broadcast', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a, b, coupleId } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  await aSock.waitFor('welcome');

  const up = await a.api.post('/api/photos', { body: Buffer.from('jpeg'), headers: { 'content-type': 'image/jpeg' } });
  const photo = up.body.photo;
  assert.equal(photo.album, null); // new photos start without an album

  // The NON-uploader may edit too (shared gallery, like delete).
  const patched = await b.api.patch(`/api/photos/${photo.id}`, { json: { caption: 'Our trip', album: ' Italy 2026 ' } });
  assert.equal(patched.status, 200);
  assert.equal(patched.body.photo.caption, 'Our trip');
  assert.equal(patched.body.photo.album, 'Italy 2026'); // trimmed
  const frame = await aSock.waitFor('photo_updated');
  assert.deepEqual(frame.payload.photo, patched.body.photo);

  // List includes the album.
  const list = (await a.api.get('/api/photos')).body.photos;
  assert.equal(list[0].album, 'Italy 2026');

  // null clears caption; empty-string album clears to null; omitted fields stay.
  const cleared = (await a.api.patch(`/api/photos/${photo.id}`, { json: { caption: null, album: '' } })).body.photo;
  assert.equal(cleared.caption, null);
  assert.equal(cleared.album, null);
  const untouched = (await a.api.patch(`/api/photos/${photo.id}`, { json: { album: 'Sommer' } })).body.photo;
  assert.equal(untouched.caption, null);
  assert.equal(untouched.album, 'Sommer');

  // Validation: album > 40 chars → album_too_long; unknown id → 404.
  const tooLong = await a.api.patch(`/api/photos/${photo.id}`, { json: { album: 'x'.repeat(41) } });
  assert.equal(tooLong.status, 400);
  assert.equal(tooLong.body.error, 'album_too_long');
  assert.equal((await a.api.patch(`/api/photos/${photo.id}`, { json: { album: 'x'.repeat(40) } })).status, 200);
  assert.equal((await a.api.patch('/api/photos/ph_nope', { json: { album: 'x' } })).status, 404);

  // Pre-v1.6 photos without the album key serialize album: null.
  delete app.store.data.couples[coupleId].photos[0].album;
  assert.equal((await b.api.get('/api/photos')).body.photos[0].album, null);
});

test('X-Taken-At: EXIF capture time is stored normalized, listed, bad values ignored', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a, b, coupleId } = await setupCouple(baseUrl);
  const jpeg = Buffer.from('jpeg');

  const res = await a.api.post('/api/photos', {
    body: jpeg,
    headers: { 'content-type': 'image/jpeg', 'x-taken-at': '2024-07-15T14:30:00+02:00' },
  });
  assert.equal(res.status, 201);
  assert.equal(res.body.photo.takenAt, '2024-07-15T12:30:00.000Z'); // normalized to UTC ISO
  // Upload responses carry the gallery fill level so clients can warn early.
  assert.equal(res.body.galleryCount, 1);
  assert.equal(res.body.galleryLimit, 2000);

  // Unparseable header must not fail the upload — takenAt just stays null.
  const bad = await a.api.post('/api/photos', {
    body: jpeg,
    headers: { 'content-type': 'image/jpeg', 'x-taken-at': 'gestern nachmittag' },
  });
  assert.equal(bad.status, 201);
  assert.equal(bad.body.photo.takenAt, null);

  // Missing header → null; GET serializes takenAt for every photo + the cap.
  await a.api.post('/api/photos', { body: jpeg, headers: { 'content-type': 'image/jpeg' } });
  const list = await b.api.get('/api/photos');
  assert.equal(list.body.limit, 2000);
  assert.deepEqual(
    list.body.photos.map((p) => p.takenAt),
    [null, null, '2024-07-15T12:30:00.000Z'],
  );

  // Capture times beyond the 24 h clock-skew allowance are ignored.
  const future = await a.api.post('/api/photos', {
    body: jpeg,
    headers: {
      'content-type': 'image/jpeg',
      'x-taken-at': new Date(Date.now() + 48 * 60 * 60_000).toISOString(),
    },
  });
  assert.equal(future.status, 201);
  assert.equal(future.body.photo.takenAt, null);

  // Legacy entries missing derived/default fields are healed on serialization.
  const legacy = app.store.data.couples[coupleId].photos.find((photo) => photo.id === res.body.photo.id);
  delete legacy.takenAt;
  delete legacy.url;
  const healed = (await b.api.get('/api/photos')).body.photos.find((photo) => photo.id === legacy.id);
  assert.equal(healed.takenAt, null);
  assert.equal(healed.url, `/api/photos/${legacy.id}/raw`);
});

test('photo cap: upload past 2000 per couple → 413 too_many_photos', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a, coupleId } = await setupCouple(baseUrl);
  const couple = app.store.data.couples[coupleId];
  // Fill to one below the cap with metadata-only entries (no media files needed).
  for (let i = couple.photos.length; i < 1999; i++) {
    couple.photos.push({
      id: `ph_fill${i}`,
      uploaderId: a.memberId,
      caption: null,
      url: `/api/photos/ph_fill${i}/raw`,
      thumbUrl: null,
      width: null,
      height: null,
      album: null,
      createdAt: '2026-01-01T00:00:00.000Z',
    });
  }
  const jpeg = Buffer.from('jpeg');
  const raced = await Promise.all(Array.from({ length: 10 }, () =>
    a.api.post('/api/photos', { body: jpeg, headers: { 'content-type': 'image/jpeg' } })));
  assert.equal(raced.filter((result) => result.status === 201).length, 1);
  assert.equal(raced.filter((result) => result.status === 413).length, 9);
  assert.ok(raced.filter((result) => result.status === 413)
    .every((result) => result.body.error === 'too_many_photos'));
  assert.equal((await a.api.get('/api/photos')).body.photos.length, 2000);
});

test('photos of another couple are not accessible', async (t) => {
  const { baseUrl } = await makeApp(t);
  const couple1 = await setupCouple(baseUrl);
  const couple2 = await setupCouple(baseUrl);
  const jpeg = Buffer.from('jpeg');
  const up = await couple1.a.api.post('/api/photos', { body: jpeg, headers: { 'content-type': 'image/jpeg' } });
  const res = await couple2.a.api.get(up.body.photo.url);
  assert.equal(res.status, 404);
});
