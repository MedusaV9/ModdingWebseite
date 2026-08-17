import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple, wsOpen } from './helpers.js';

test('songs: create with full model, song_added broadcast, list newest first', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const res = await a.api.post('/api/songs', {
    json: { title: '  Sooo Dreamy  ', artist: 'The Couple', note: 'our song 💞', link: ' https://example.com/song ' },
  });
  assert.equal(res.status, 201);
  const song = res.body.song;
  assert.match(song.id, /^sg_/);
  assert.equal(song.title, 'Sooo Dreamy'); // trimmed
  assert.equal(song.artist, 'The Couple');
  assert.equal(song.note, 'our song 💞');
  assert.equal(song.link, 'https://example.com/song'); // trimmed, otherwise untouched
  assert.equal(song.addedBy, a.memberId);
  assert.deepEqual(song.heartedBy, []);
  assert.ok(song.createdAt);

  const added = await bSock.waitFor('song_added');
  assert.deepEqual(added.payload.song, song);

  // Optional fields default to null; whitespace-only collapses to null.
  const bare = (await b.api.post('/api/songs', { json: { title: 'Bare', artist: '   ' } })).body.song;
  assert.equal(bare.artist, null);
  assert.equal(bare.note, null);
  assert.equal(bare.link, null);

  const list = await a.api.get('/api/songs');
  assert.deepEqual(list.body.songs.map((s) => s.id), [bare.id, song.id]); // newest first
});

test('songs validation: bad_title and too_long', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);

  for (const title of [undefined, null, '', '   ', 42, 'x'.repeat(121)]) {
    const res = await a.api.post('/api/songs', { json: { title } });
    assert.equal(res.status, 400, `title ${JSON.stringify(title)} should be rejected`);
    assert.equal(res.body.error, 'bad_title');
  }
  assert.equal((await a.api.post('/api/songs', { json: { title: 'x'.repeat(120) } })).status, 201);

  for (const [field, max] of [['artist', 120], ['note', 300], ['link', 500]]) {
    const res = await a.api.post('/api/songs', { json: { title: 'ok', [field]: 'x'.repeat(max + 1) } });
    assert.equal(res.status, 400, `${field} over ${max} should be rejected`);
    assert.equal(res.body.error, 'too_long');
    assert.equal((await a.api.post('/api/songs', { json: { title: 'ok', [field]: 'x'.repeat(max) } })).status, 201);
  }
});

test('song heart: toggled by both members independently, song_updated broadcasts', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  await aSock.waitFor('welcome');

  const song = (await a.api.post('/api/songs', { json: { title: 'Heartable' } })).body.song;

  const aHeart = await a.api.post(`/api/songs/${song.id}/heart`);
  assert.deepEqual(aHeart.body.song.heartedBy, [a.memberId]);
  const frame = await aSock.waitFor('song_updated');
  assert.deepEqual(frame.payload.song, aHeart.body.song);

  const bHeart = await b.api.post(`/api/songs/${song.id}/heart`);
  assert.deepEqual(bHeart.body.song.heartedBy, [a.memberId, b.memberId]);

  const aUnheart = await a.api.post(`/api/songs/${song.id}/heart`);
  assert.deepEqual(aUnheart.body.song.heartedBy, [b.memberId]);

  assert.equal((await a.api.post('/api/songs/sg_nope/heart')).status, 404);
});

test('song PATCH: adder only, partial updates, null clears optionals, title must stay', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const song = (
    await a.api.post('/api/songs', { json: { title: 'Original', artist: 'Old Artist', note: 'old', link: 'x' } })
  ).body.song;

  // Only the adder may edit.
  const denied = await b.api.patch(`/api/songs/${song.id}`, { json: { title: 'Hijacked' } });
  assert.equal(denied.status, 403);
  assert.equal(denied.body.error, 'not_yours');

  // Partial update + explicit null clears optionals; untouched fields stay.
  const patched = await a.api.patch(`/api/songs/${song.id}`, { json: { artist: null, note: 'new note' } });
  assert.equal(patched.status, 200);
  assert.equal(patched.body.song.title, 'Original');
  assert.equal(patched.body.song.artist, null);
  assert.equal(patched.body.song.note, 'new note');
  assert.equal(patched.body.song.link, 'x');
  const frame = await bSock.waitFor('song_updated');
  assert.deepEqual(frame.payload.song, patched.body.song);

  // Title can be changed but never cleared.
  assert.equal((await a.api.patch(`/api/songs/${song.id}`, { json: { title: 'Renamed' } })).body.song.title, 'Renamed');
  const cleared = await a.api.patch(`/api/songs/${song.id}`, { json: { title: null } });
  assert.equal(cleared.status, 400);
  assert.equal(cleared.body.error, 'bad_title');
  assert.equal((await a.api.patch(`/api/songs/${song.id}`, { json: { title: '  ' } })).status, 400);

  assert.equal((await a.api.patch('/api/songs/sg_nope', { json: { title: 'x' } })).status, 404);
});

test('song delete: adder only, song_deleted broadcast', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  await aSock.waitFor('welcome');

  const song = (await a.api.post('/api/songs', { json: { title: 'Doomed' } })).body.song;

  const denied = await b.api.del(`/api/songs/${song.id}`);
  assert.equal(denied.status, 403);
  assert.equal(denied.body.error, 'not_yours');

  const del = await a.api.del(`/api/songs/${song.id}`);
  assert.deepEqual(del.body, { ok: true });
  const frame = await aSock.waitFor('song_deleted');
  assert.deepEqual(frame.payload, { id: song.id });
  assert.equal((await a.api.get('/api/songs')).body.songs.length, 0);
  assert.equal((await a.api.del(`/api/songs/${song.id}`)).status, 404);
});

test('song list caps at 300: oldest evicted on create with song_deleted broadcast', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const ids = [];
  for (let i = 0; i < 300; i++) {
    const res = await a.api.post('/api/songs', { json: { title: `song ${i}` } });
    assert.equal(res.status, 201);
    ids.push(res.body.song.id);
  }

  const overflow = (await a.api.post('/api/songs', { json: { title: 'overflow' } })).body.song;
  const evicted = await bSock.waitFor('song_deleted');
  assert.deepEqual(evicted.payload, { id: ids[0] }); // oldest went first

  const list = (await a.api.get('/api/songs')).body.songs;
  assert.equal(list.length, 300);
  assert.equal(list[0].id, overflow.id);
  assert.ok(!list.some((s) => s.id === ids[0]));
  assert.ok(list.some((s) => s.id === ids[1]));
});
