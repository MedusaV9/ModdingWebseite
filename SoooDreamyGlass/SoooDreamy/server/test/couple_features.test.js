import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple, wsOpen, client } from './helpers.js';

function todayKey() {
  return new Date().toISOString().slice(0, 10);
}

// --- check-ins ------------------------------------------------------------------------------

test('check-ins: morning/night taps, idempotent, streak counts both-member days', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const first = await a.api.post('/api/checkins', { json: { kind: 'morning' } });
  assert.equal(first.status, 200);
  assert.equal(first.body.streak, 0, 'one member alone earns no streak');
  assert.ok(first.body.day.morning[a.memberId]);

  const frame = await bSock.waitFor('checkin');
  assert.equal(frame.payload.memberId, a.memberId);
  assert.equal(frame.payload.kind, 'morning');

  // Re-tap keeps the original timestamp (idempotent, no second WS frame).
  const originalAt = first.body.day.morning[a.memberId];
  const again = await a.api.post('/api/checkins', { json: { kind: 'morning' } });
  assert.equal(again.body.day.morning[a.memberId], originalAt);
  await bSock.assertNone('checkin');

  // Partner checks in too (night counts as well) → streak 1.
  const partner = await b.api.post('/api/checkins', { json: { kind: 'night' } });
  assert.equal(partner.status, 200);
  assert.equal(partner.body.streak, 1);

  const list = await a.api.get('/api/checkins');
  assert.equal(list.status, 200);
  assert.equal(list.body.streak, 1);
  assert.equal(list.body.days[0].dateKey, todayKey());

  const badKind = await a.api.post('/api/checkins', { json: { kind: 'brunch' } });
  assert.equal(badKind.status, 400);
  const badDate = await a.api.post('/api/checkins', { json: { kind: 'morning', dateKey: '2000-01-01' } });
  assert.equal(badDate.status, 400);
  assert.equal(badDate.body.error, 'bad_datekey');
});

// --- shared lists ----------------------------------------------------------------------------

test('lists: create → add/check/delete items → partner sees every change live', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const created = await a.api.post('/api/lists', { json: { name: 'Einkauf', emoji: '🛒' } });
  assert.equal(created.status, 201);
  const listId = created.body.list.id;
  assert.match(listId, /^l_/);
  await bSock.waitFor('list_added');

  const item = await a.api.post(`/api/lists/${listId}/items`, { json: { text: 'Erdbeeren' } });
  assert.equal(item.status, 201);
  assert.equal(item.body.item.done, false);
  const updated = await bSock.waitFor('list_updated');
  assert.equal(updated.payload.list.items.length, 1);

  // Partner checks the item off — doneAt set once, kept on re-check.
  const itemId = item.body.item.id;
  const checked = await b.api.patch(`/api/lists/${listId}/items/${itemId}`, { json: { done: true } });
  assert.equal(checked.status, 200);
  assert.ok(checked.body.item.doneAt);
  await bSock.waitFor('list_updated');

  const renamed = await b.api.patch(`/api/lists/${listId}`, { json: { name: 'Wocheneinkauf' } });
  assert.equal(renamed.status, 200);
  assert.equal(renamed.body.list.name, 'Wocheneinkauf');
  await bSock.waitFor('list_updated');

  const removeItem = await a.api.del(`/api/lists/${listId}/items/${itemId}`);
  assert.equal(removeItem.status, 200);
  await bSock.waitFor('list_updated', (m) => m.payload.list.items.length === 0);

  const removed = await a.api.del(`/api/lists/${listId}`);
  assert.equal(removed.status, 200);
  const gone = await bSock.waitFor('list_deleted');
  assert.equal(gone.payload.id, listId);

  const empty = await a.api.get('/api/lists');
  assert.deepEqual(empty.body.lists, []);
});

test('lists: caps — at most 20 lists, at most 200 items per list', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  for (let i = 0; i < 20; i++) {
    const res = await a.api.post('/api/lists', { json: { name: `Liste ${i}` } });
    assert.equal(res.status, 201);
  }
  const overflow = await a.api.post('/api/lists', { json: { name: 'Eine zu viel' } });
  assert.equal(overflow.status, 413);
  assert.equal(overflow.body.error, 'too_many_lists');
});

// --- hug queue -------------------------------------------------------------------------------

test('hugs: queue → partner opens → sender is notified; only recipient may open', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await aSock.waitFor('welcome');
  await bSock.waitFor('welcome');

  const queued = await a.api.post('/api/hugs', { json: { note: 'Für nach deiner Schicht 🌙' } });
  assert.equal(queued.status, 201);
  assert.equal(queued.body.hug.to, b.memberId);
  assert.equal(queued.body.hug.emoji, '🫂');
  assert.equal(queued.body.hug.openedAt, null);
  await bSock.waitFor('hug_queued');

  const hugId = queued.body.hug.id;
  const senderOpen = await a.api.post(`/api/hugs/${hugId}/open`);
  assert.equal(senderOpen.status, 403, 'sender must not open their own hug');

  const opened = await b.api.post(`/api/hugs/${hugId}/open`);
  assert.equal(opened.status, 200);
  assert.ok(opened.body.hug.openedAt);
  const frame = await aSock.waitFor('hug_opened');
  assert.equal(frame.payload.hug.id, hugId);

  const twice = await b.api.post(`/api/hugs/${hugId}/open`);
  assert.equal(twice.status, 409);
  assert.equal(twice.body.error, 'already_opened');

  const list = await b.api.get('/api/hugs');
  assert.equal(list.body.hugs.length, 1);
});

test('hugs: need a partner', async (t) => {
  const { baseUrl } = await makeApp(t);
  const anon = client(baseUrl);
  const created = await anon.post('/api/couples', { json: { name: 'Solo' } });
  const solo = client(baseUrl, created.body.token);
  const res = await solo.post('/api/hugs', { json: {} });
  assert.equal(res.status, 409);
  assert.equal(res.body.error, 'no_partner');
});

// --- photo of the day --------------------------------------------------------------------------

test('potd: submit gallery photo for today, replace own pick, partner sees it', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const photo1 = await a.api.post('/api/photos', { body: Buffer.from('jpeg-1'), headers: { 'content-type': 'image/jpeg' } });
  const photo2 = await a.api.post('/api/photos', { body: Buffer.from('jpeg-2'), headers: { 'content-type': 'image/jpeg' } });
  assert.equal(photo1.status, 201);
  assert.equal(photo2.status, 201);
  await bSock.waitFor('photo_added');
  await bSock.waitFor('photo_added');

  const key = todayKey();
  const submitted = await a.api.post(`/api/potd/${key}`, { json: { photoId: photo1.body.photo.id } });
  assert.equal(submitted.status, 200);
  assert.equal(submitted.body.day.entries[a.memberId].photoId, photo1.body.photo.id);
  const frame = await bSock.waitFor('potd_submitted');
  assert.equal(frame.payload.photoId, photo1.body.photo.id);

  // Replacing your own pick for the same day is allowed.
  const replaced = await a.api.post(`/api/potd/${key}`, { json: { photoId: photo2.body.photo.id } });
  assert.equal(replaced.body.day.entries[a.memberId].photoId, photo2.body.photo.id);
  await bSock.waitFor('potd_submitted');

  const days = await b.api.get('/api/potd');
  assert.equal(days.body.days.length, 1);
  assert.equal(days.body.days[0].dateKey, key);

  const unknownPhoto = await a.api.post(`/api/potd/${key}`, { json: { photoId: 'p_nope' } });
  assert.equal(unknownPhoto.status, 404);
  const staleDay = await a.api.post('/api/potd/2020-01-01', { json: { photoId: photo1.body.photo.id } });
  assert.equal(staleDay.status, 400);
  assert.equal(staleDay.body.error, 'bad_datekey');
});

// --- now playing -------------------------------------------------------------------------------

test('now playing: set → visible on the member + WS, clear → null', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const set = await a.api.put('/api/nowplaying', { json: { title: 'Ivy', artist: 'Frank Ocean' } });
  assert.equal(set.status, 200);
  assert.equal(set.body.nowPlaying.title, 'Ivy');
  const frame = await bSock.waitFor('now_playing');
  assert.equal(frame.payload.memberId, a.memberId);
  assert.equal(frame.payload.nowPlaying.artist, 'Frank Ocean');

  // Partner sees it on the serialized member.
  const couple = await b.api.get('/api/couple');
  const partnerView = couple.body.couple.members.find((m) => m.id === a.memberId);
  assert.equal(partnerView.nowPlaying.title, 'Ivy');

  const cleared = await a.api.del('/api/nowplaying');
  assert.equal(cleared.status, 200);
  const clearedFrame = await bSock.waitFor('now_playing', (m) => m.payload.nowPlaying === null);
  assert.equal(clearedFrame.payload.memberId, a.memberId);

  const missingTitle = await a.api.put('/api/nowplaying', { json: { artist: 'Nur Artist' } });
  assert.equal(missingTitle.status, 400);
});

// --- year review -------------------------------------------------------------------------------

test('year review: aggregates the current year across features', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  await a.api.post('/api/touches', { json: { type: 'kiss' } });
  await a.api.post('/api/touches', { json: { type: 'kiss' } });
  await a.api.post('/api/touches', { json: { type: 'hug' } });
  await b.api.post('/api/touches', { json: { type: 'heartbeat' } });
  await a.api.post('/api/messages', { json: { type: 'text', text: 'Hi ❤️' } });
  await a.api.post('/api/photos', { body: Buffer.from('jpeg'), headers: { 'content-type': 'image/jpeg' } });
  await a.api.post('/api/checkins', { json: { kind: 'morning' } });
  await b.api.post('/api/checkins', { json: { kind: 'morning' } });
  const hug = await a.api.post('/api/hugs', { json: {} });
  await b.api.post(`/api/hugs/${hug.body.hug.id}/open`);

  // One server-resolved game with a clear winner. A client-supplied result is
  // never accepted; B's explicit forfeit makes A the canonical winner.
  const game = await a.api.post('/api/games', { json: { type: 'connectfour', payload: { seed: 1 } } });
  await b.api.post(`/api/games/${game.body.game.id}/join`);
  await b.api.post(`/api/games/${game.body.game.id}/end`, {
    json: { forfeit: true },
  });

  const review = await a.api.get('/api/yearreview');
  assert.equal(review.status, 200);
  assert.equal(review.body.year, new Date().getUTCFullYear());
  assert.equal(review.body.touchesByMember[a.memberId], 3);
  assert.equal(review.body.touchesByMember[b.memberId], 1);
  assert.equal(review.body.topTouchType[a.memberId], 'kiss');
  assert.equal(review.body.messagesByMember[a.memberId], 1);
  assert.equal(review.body.photosAdded, 1);
  assert.equal(review.body.checkinDaysBoth, 1);
  assert.equal(review.body.checkinStreak, 1);
  assert.equal(review.body.hugsSent, 1);
  assert.equal(review.body.hugsOpened, 1);
  assert.equal(review.body.gamesPlayed, 1);
  assert.equal(review.body.gameWins[a.memberId], 1);
  assert.equal(review.body.gameWins[b.memberId], 0);

  // An empty year reports zeros, not errors.
  const empty = await a.api.get('/api/yearreview?year=2001');
  assert.equal(empty.status, 200);
  assert.equal(empty.body.gamesPlayed, 0);
  assert.equal(empty.body.photosAdded, 0);
});

// --- persistence -------------------------------------------------------------------------------

test('couple features survive a server restart', async (t) => {
  const { baseUrl, dataDir, close } = await makeApp(null);
  const { a, b } = await setupCouple(baseUrl);
  await a.api.post('/api/checkins', { json: { kind: 'morning' } });
  const list = await a.api.post('/api/lists', { json: { name: 'Filme', emoji: '🎬' } });
  await a.api.post(`/api/lists/${list.body.list.id}/items`, { json: { text: 'Notting Hill' } });
  await a.api.post('/api/hugs', { json: { note: 'Bis morgen!' } });
  await a.api.put('/api/nowplaying', { json: { title: 'Dreams' } });
  await close();

  const second = await makeApp(t, { dataDir });
  const api = client(second.baseUrl, b.token);
  const checkins = await api.get('/api/checkins');
  assert.ok(checkins.body.days[0].morning[a.memberId]);
  const lists = await api.get('/api/lists');
  assert.equal(lists.body.lists[0].name, 'Filme');
  assert.equal(lists.body.lists[0].items[0].text, 'Notting Hill');
  const hugs = await api.get('/api/hugs');
  assert.equal(hugs.body.hugs[0].note, 'Bis morgen!');
  const couple = await api.get('/api/couple');
  const partner = couple.body.couple.members.find((m) => m.id === a.memberId);
  assert.equal(partner.nowPlaying.title, 'Dreams');
});
