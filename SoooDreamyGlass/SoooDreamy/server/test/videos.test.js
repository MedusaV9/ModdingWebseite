import { test } from 'node:test';
import assert from 'node:assert/strict';
import { access } from 'node:fs/promises';
import path from 'node:path';
import { makeApp, setupCouple, wsOpen, client } from './helpers.js';

const MP4 = Buffer.concat([
  Buffer.from([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70]), // ftyp box header
  Buffer.from('isommp42-fake-video-payload-'.repeat(64)),
]);

test('video upload with caption/dimensions/duration, list, ws broadcast, delete', async (t) => {
  const { baseUrl, dataDir } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const res = await a.api.post('/api/videos', {
    body: MP4,
    headers: {
      'content-type': 'video/mp4',
      'x-caption': encodeURIComponent('Unser Strand-Tag 🏖️'),
      'x-width': '1280',
      'x-height': '720',
      'x-duration': '12.34',
    },
  });
  assert.equal(res.status, 201);
  const video = res.body.video;
  assert.equal(video.caption, 'Unser Strand-Tag 🏖️');
  assert.equal(video.width, 1280);
  assert.equal(video.height, 720);
  assert.equal(video.duration, 12.3); // rounded to 0.1s
  assert.equal(video.bytes, MP4.length);
  assert.equal(video.uploaderId, a.memberId);
  assert.equal(video.url, `/api/videos/${video.id}/raw`);
  assert.equal(video.thumbUrl, null);
  assert.deepEqual(video.favorites, []);

  const added = await bSock.waitFor('video_added');
  assert.deepEqual(added.payload.video, video);
  await access(path.join(dataDir, 'media', 'videos', `${video.id}.mp4`));

  // List is newest-first.
  await a.api.post('/api/videos', { body: MP4, headers: { 'content-type': 'video/mp4' } });
  const list = await b.api.get('/api/videos');
  assert.equal(list.body.videos.length, 2);
  assert.equal(list.body.videos[1].id, video.id);

  // Delete by the NON-uploader (shared gallery) removes file + broadcasts.
  const del = await b.api.del(`/api/videos/${video.id}`);
  assert.equal(del.status, 200);
  const deleted = await bSock.waitFor('video_deleted');
  assert.deepEqual(deleted.payload, { id: video.id });
  await assert.rejects(access(path.join(dataDir, 'media', 'videos', `${video.id}.mp4`)));
  assert.equal((await a.api.get(video.url)).status, 404);
});

test('video streaming honors Range requests (206, content-range, 416)', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const up = await a.api.post('/api/videos', { body: MP4, headers: { 'content-type': 'video/mp4' } });
  const video = up.body.video;

  // Full fetch.
  const full = await b.api.get(video.url);
  assert.equal(full.status, 200);
  assert.equal(full.headers.get('content-type'), 'video/mp4');
  assert.equal(full.headers.get('accept-ranges'), 'bytes');
  assert.deepEqual(full.body, MP4);

  // Middle range — exactly what AVPlayer sends when seeking.
  const mid = await b.api.get(video.url, { headers: { range: 'bytes=10-25' } });
  assert.equal(mid.status, 206);
  assert.equal(mid.headers.get('content-range'), `bytes 10-25/${MP4.length}`);
  assert.equal(Number(mid.headers.get('content-length')), 16);
  assert.deepEqual(mid.body, MP4.subarray(10, 26));

  // Open-ended and suffix ranges.
  const tail = await b.api.get(video.url, { headers: { range: `bytes=${MP4.length - 5}-` } });
  assert.equal(tail.status, 206);
  assert.deepEqual(tail.body, MP4.subarray(MP4.length - 5));
  const suffix = await b.api.get(video.url, { headers: { range: 'bytes=-4' } });
  assert.equal(suffix.status, 206);
  assert.deepEqual(suffix.body, MP4.subarray(MP4.length - 4));

  // Unsatisfiable range → 416 with the total size.
  const bad = await b.api.get(video.url, { headers: { range: `bytes=${MP4.length + 10}-` } });
  assert.equal(bad.status, 416);
  assert.equal(bad.headers.get('content-range'), `bytes */${MP4.length}`);

  // URL credentials are forbidden; AVPlayer uses an authenticated URLRequest.
  const rawQuery = await client(baseUrl).get(`${video.url}?token=${b.token}`);
  assert.equal(rawQuery.status, 400);
  assert.equal(rawQuery.body.error, 'query_token_forbidden');
  assert.equal((await client(baseUrl).get(video.url)).status, 401);
});

test('video thumbnail: uploader-only, raw fetch, video_updated broadcast', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  await aSock.waitFor('welcome');

  const up = await a.api.post('/api/videos', { body: MP4, headers: { 'content-type': 'video/mp4' } });
  const video = up.body.video;

  // Non-uploader may not attach a thumbnail.
  const forbidden = await b.api.post(`/api/videos/${video.id}/thumb`, {
    body: Buffer.from('jpg'), headers: { 'content-type': 'image/jpeg' },
  });
  assert.equal(forbidden.status, 403);

  const jpeg = Buffer.from('fake-thumb-jpeg');
  const ok = await a.api.post(`/api/videos/${video.id}/thumb`, {
    body: jpeg, headers: { 'content-type': 'image/jpeg' },
  });
  assert.equal(ok.status, 200);
  assert.equal(ok.body.video.thumbUrl, `/api/videos/${video.id}/thumb/raw`);
  const updated = await aSock.waitFor('video_updated');
  assert.deepEqual(updated.payload.video, ok.body.video);

  const raw = await b.api.get(ok.body.video.thumbUrl);
  assert.equal(raw.status, 200);
  assert.equal(raw.headers.get('content-type'), 'image/jpeg');
  assert.deepEqual(raw.body, jpeg);
});

test('video favorite toggle, caption PATCH by either partner, stats count', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  const up = await a.api.post('/api/videos', { body: MP4, headers: { 'content-type': 'video/mp4' } });
  const video = up.body.video;

  // Favorite toggle on/off.
  const fav = await b.api.post(`/api/videos/${video.id}/favorite`);
  assert.deepEqual(fav.body.video.favorites, [b.memberId]);
  const unfav = await b.api.post(`/api/videos/${video.id}/favorite`);
  assert.deepEqual(unfav.body.video.favorites, []);

  // Either partner may edit the caption; null clears it.
  const patched = await b.api.patch(`/api/videos/${video.id}`, { json: { caption: 'Filmabend 🎬' } });
  assert.equal(patched.status, 200);
  assert.equal(patched.body.video.caption, 'Filmabend 🎬');
  const cleared = await a.api.patch(`/api/videos/${video.id}`, { json: { caption: null } });
  assert.equal(cleared.body.video.caption, null);

  // Stats include the video count.
  const stats = await a.api.get('/api/stats');
  assert.equal(stats.body.videos, 1);
});

test('video limits: empty body 400, over-limit 413, count cap, cross-couple 404', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a, coupleId } = await setupCouple(baseUrl);

  const empty = await a.api.post('/api/videos', { headers: { 'content-type': 'video/mp4' } });
  assert.equal(empty.status, 400);
  assert.equal(empty.body.error, 'empty_body');

  // Count cap: fill the metadata list directly (uploading 60 real bodies is slow).
  const couple = app.store.data.couples[coupleId];
  couple.videos = Array.from({ length: 60 }, (_, i) => ({
    id: `vd_fill${i}`, uploaderId: a.memberId, caption: null,
    url: `/api/videos/vd_fill${i}/raw`, thumbUrl: null,
    width: null, height: null, duration: null, bytes: 1, createdAt: new Date().toISOString(),
  }));
  const capped = await a.api.post('/api/videos', { body: MP4, headers: { 'content-type': 'video/mp4' } });
  assert.equal(capped.status, 413);
  assert.equal(capped.body.error, 'too_many_videos');
  couple.videos = [];

  // Other couples cannot see the video.
  const up = await a.api.post('/api/videos', { body: MP4, headers: { 'content-type': 'video/mp4' } });
  const stranger = await setupCouple(baseUrl);
  assert.equal((await stranger.a.api.get(up.body.video.url)).status, 404);
  assert.equal((await stranger.a.api.del(`/api/videos/${up.body.video.id}`)).status, 404);
});

test('video upload queues a localized partner push (same courtesy as photos)', async (t) => {
  const deliveries = [];
  const provider = { async send(request) { deliveries.push(request); } };
  const { baseUrl } = await makeApp(t, { pushProvider: provider });
  const { a, b } = await setupCouple(baseUrl);
  await b.api.post('/api/push-devices/current', {
    json: { apnsToken: 'bb'.repeat(32), environment: 'development', bundleId: 'app.sooodreamy.ios', language: 'de' },
  });

  const secretCaption = 'geheime Beschreibung, gehört nicht in APNs';
  const up = await a.api.post('/api/videos', {
    body: MP4,
    headers: { 'content-type': 'video/mp4', 'x-caption': encodeURIComponent(secretCaption) },
  });
  assert.equal(up.status, 201);
  for (let attempt = 0; deliveries.length === 0 && attempt < 100; attempt += 1) {
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
  assert.equal(deliveries.length, 1);
  assert.equal(deliveries[0].token, 'bb'.repeat(32));
  assert.equal(deliveries[0].payload.type, 'video');
  assert.equal(deliveries[0].payload.link, 'sooodreamy://videos');
  assert.match(deliveries[0].payload.aps.alert.title, /^Video von Mia/);
  assert.equal(JSON.stringify(deliveries[0].payload).includes(secretCaption), false);
});

test('pre-2.0 stores without videos array serialize fine and accept uploads', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a, coupleId } = await setupCouple(baseUrl);
  delete app.store.data.couples[coupleId].videos; // simulate old store.json
  const list = await a.api.get('/api/videos');
  assert.equal(list.status, 200);
  assert.deepEqual(list.body.videos, []);
  const up = await a.api.post('/api/videos', { body: MP4, headers: { 'content-type': 'video/mp4' } });
  assert.equal(up.status, 201);
});
