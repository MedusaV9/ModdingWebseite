import { test } from 'node:test';
import assert from 'node:assert/strict';
import { access, rm } from 'node:fs/promises';
import path from 'node:path';
import { makeApp, setupCouple, wsOpen, client } from './helpers.js';

test('message overflow moves immutable chunks to paginable archives without deleting voice', async (t) => {
  const first = await makeApp(null);
  const pair = await setupCouple(first.baseUrl);
  const couple = first.app.store.data.couples[pair.coupleId];
  couple.messages = Array.from({ length: 5_000 }, (_, index) => ({
    id: `fixture-${String(index).padStart(5, '0')}`,
    senderId: pair.a.memberId,
    type: index === 0 ? 'voice' : 'text',
    text: index === 0 ? null : `message ${index}`,
    audioUrl: index === 0 ? '/api/voice/fixture-00000/raw' : null,
    createdAt: new Date(1_700_000_000_000 + index).toISOString(),
  }));
  couple.counters.messages = 5_000;
  await first.app.store.saveMedia('voice', 'fixture-00000.m4a', Buffer.from('archived voice'));

  const overflow = await pair.a.api.post('/api/messages', {
    json: { type: 'text', text: 'new hot message' },
  });
  assert.equal(overflow.status, 201);
  assert.equal(couple.messages.length, 4_501);
  assert.equal(couple.messageArchives.length, 1);
  assert.equal(couple.messageArchives[0].messages.length, 500);
  assert.equal(couple.messageArchives[0].messages[0].id, 'fixture-00000');
  await access(path.join(first.dataDir, 'media', 'voice', 'fixture-00000.m4a'));
  await first.close();

  const reopened = await makeApp(t, { dataDir: first.dataDir });
  t.after(() => rm(first.dataDir, { recursive: true, force: true }));
  const api = client(reopened.baseUrl, pair.a.token);
  const archivedPage = await api.get('/api/messages?before=fixture-00500&limit=200');
  assert.equal(archivedPage.status, 200);
  assert.equal(archivedPage.body.messages[0].id, 'fixture-00300');
  assert.equal(archivedPage.body.messages.at(-1).id, 'fixture-00499');
  const voice = await api.get('/api/voice/fixture-00000/raw');
  assert.equal(voice.status, 200);
  assert.deepEqual(voice.body, Buffer.from('archived voice'));
});

test('text + letter messages, WS broadcast to both members', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await aSock.waitFor('welcome');
  await bSock.waitFor('welcome');

  const text = await a.api.post('/api/messages', { json: { type: 'text', text: 'hi ❤️' } });
  assert.equal(text.status, 201);
  assert.equal(text.body.message.type, 'text');
  assert.equal(text.body.message.text, 'hi ❤️');
  assert.equal(text.body.message.title, null);
  assert.equal(text.body.message.audioUrl, null);

  // Couple-wide: the sender's sockets receive it too.
  const aFrame = await aSock.waitFor('message');
  const bFrame = await bSock.waitFor('message');
  assert.deepEqual(aFrame.payload.message, text.body.message);
  assert.deepEqual(bFrame.payload.message, text.body.message);

  const letter = await b.api.post('/api/messages', { json: { type: 'letter', text: 'Dear Mia…', title: 'For you' } });
  assert.equal(letter.status, 201);
  assert.equal(letter.body.message.type, 'letter');
  assert.equal(letter.body.message.title, 'For you');
});

test('message validation: bad type, missing/too-long text', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  assert.equal((await a.api.post('/api/messages', { json: { type: 'gif', text: 'x' } })).status, 400);
  assert.equal((await a.api.post('/api/messages', { json: { type: 'text' } })).status, 400);
  const tooLong = await a.api.post('/api/messages', { json: { type: 'text', text: 'x'.repeat(5001) } });
  assert.equal(tooLong.status, 400);
  assert.equal(tooLong.body.error, 'text_too_long');
  assert.equal((await a.api.post('/api/messages', { json: { type: 'text', text: 'x'.repeat(5000) } })).status, 201);
});

test('text message client ids make lost-response retries idempotent', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const body = { type: 'text', text: 'keep me offline', clientMessageId: 'device-a:message-1' };

  const first = await a.api.post('/api/messages', { json: body });
  assert.equal(first.status, 201);
  assert.equal(first.body.message.clientMessageId, body.clientMessageId);

  const retry = await a.api.post('/api/messages', {
    json: { ...body, text: 'a retry may not overwrite the accepted message' },
  });
  assert.equal(retry.status, 200);
  assert.equal(retry.body.duplicate, true);
  assert.equal(retry.body.message.id, first.body.message.id);
  assert.equal(retry.body.message.text, body.text);

  // Idempotency is scoped to the authenticated member.
  const partner = await b.api.post('/api/messages', { json: body });
  assert.equal(partner.status, 201);
  assert.notEqual(partner.body.message.id, first.body.message.id);

  const list = (await a.api.get('/api/messages')).body.messages;
  assert.equal(list.filter((message) => message.clientMessageId === body.clientMessageId).length, 2);
});

test('photo messages: reference a gallery photo, optional caption, WS broadcast, photoId serialized', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  // Either member's gallery photo may be referenced — b uploads, a sends.
  const photo = (
    await b.api.post('/api/photos', { body: Buffer.from('jpeg-bytes'), headers: { 'content-type': 'image/jpeg' } })
  ).body.photo;

  const res = await a.api.post('/api/messages', { json: { type: 'photo', photoId: photo.id } });
  assert.equal(res.status, 201);
  const msg = res.body.message;
  assert.equal(msg.type, 'photo');
  assert.equal(msg.photoId, photo.id);
  assert.equal(msg.text, null);
  assert.equal(msg.title, null);
  assert.equal(msg.audioUrl, null);

  const frame = await bSock.waitFor('message', (m) => m.payload.message.type === 'photo');
  assert.deepEqual(frame.payload.message, msg);

  // Optional caption rides along; blank captions are stored as null.
  const captioned = await a.api.post('/api/messages', { json: { type: 'photo', photoId: photo.id, text: 'us 🌇' } });
  assert.equal(captioned.status, 201);
  assert.equal(captioned.body.message.text, 'us 🌇');
  const blank = await a.api.post('/api/messages', { json: { type: 'photo', photoId: photo.id, text: '   ' } });
  assert.equal(blank.body.message.text, null);

  // Non-photo messages serialize photoId as null (incl. pre-v1.7 stored ones).
  const text = await a.api.post('/api/messages', { json: { type: 'text', text: 'hi' } });
  assert.equal(text.body.message.photoId, null);
  const list = (await a.api.get('/api/messages')).body.messages;
  assert.ok(list.every((m) => 'photoId' in m));
});

test('photo message validation: missing/bad/unknown/foreign photoId, over-long caption', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);

  const missing = await a.api.post('/api/messages', { json: { type: 'photo' } });
  assert.equal(missing.status, 400);
  assert.equal(missing.body.error, 'bad_photo');
  assert.equal((await a.api.post('/api/messages', { json: { type: 'photo', photoId: 42 } })).status, 400);
  assert.equal((await a.api.post('/api/messages', { json: { type: 'photo', photoId: '' } })).status, 400);

  const unknown = await a.api.post('/api/messages', { json: { type: 'photo', photoId: 'ph_nope' } });
  assert.equal(unknown.status, 404);
  assert.equal(unknown.body.error, 'unknown_photo');

  // A photoId from ANOTHER couple's gallery is just as unknown.
  const other = await setupCouple(baseUrl);
  const foreign = (
    await other.a.api.post('/api/photos', { body: Buffer.from('x'), headers: { 'content-type': 'image/jpeg' } })
  ).body.photo;
  assert.equal((await a.api.post('/api/messages', { json: { type: 'photo', photoId: foreign.id } })).status, 404);

  // Captions obey the same 5000-char text limit.
  const mine = (
    await a.api.post('/api/photos', { body: Buffer.from('y'), headers: { 'content-type': 'image/jpeg' } })
  ).body.photo;
  const tooLong = await a.api.post('/api/messages', {
    json: { type: 'photo', photoId: mine.id, text: 'x'.repeat(5001) },
  });
  assert.equal(tooLong.status, 400);
  assert.equal(tooLong.body.error, 'text_too_long');
});

test('photo messages and gallery photos have independent lifetimes', async (t) => {
  const { baseUrl, dataDir } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  const photo = (
    await a.api.post('/api/photos', { body: Buffer.from('jpeg'), headers: { 'content-type': 'image/jpeg' } })
  ).body.photo;
  const file = path.join(dataDir, 'media', 'photos', `${photo.id}.jpg`);

  // Deleting the photo MESSAGE keeps the gallery photo (list + file).
  const msg = (await a.api.post('/api/messages', { json: { type: 'photo', photoId: photo.id } })).body.message;
  assert.equal((await a.api.del(`/api/messages/${msg.id}`)).status, 200);
  assert.ok((await a.api.get('/api/photos')).body.photos.some((p) => p.id === photo.id));
  await access(file);

  // Deleting the PHOTO keeps the message; its photoId simply dangles
  // (clients get a 404 for the media, like any deleted photo).
  const msg2 = (await a.api.post('/api/messages', { json: { type: 'photo', photoId: photo.id } })).body.message;
  assert.equal((await a.api.del(`/api/photos/${photo.id}`)).status, 200);
  await assert.rejects(access(file));
  const list = (await a.api.get('/api/messages')).body.messages;
  assert.ok(list.some((m) => m.id === msg2.id && m.photoId === photo.id));
});

test('pagination with before pages older messages in ascending order', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  const ids = [];
  for (let i = 1; i <= 5; i++) {
    const res = await a.api.post('/api/messages', { json: { type: 'text', text: `m${i}` } });
    ids.push(res.body.message.id);
  }

  const page1 = await a.api.get('/api/messages?limit=2');
  assert.deepEqual(page1.body.messages.map((m) => m.text), ['m4', 'm5']);

  const page2 = await a.api.get(`/api/messages?limit=2&before=${page1.body.messages[0].id}`);
  assert.deepEqual(page2.body.messages.map((m) => m.text), ['m2', 'm3']);

  const page3 = await a.api.get(`/api/messages?limit=50&before=${page2.body.messages[0].id}`);
  assert.deepEqual(page3.body.messages.map((m) => m.text), ['m1']);

  assert.equal((await a.api.get('/api/messages?before=msg_nope')).status, 404);
});

test('voice upload: raw body → message, media auth via bearer header only', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const bytes = Buffer.from('fake-mp4-audio-bytes-'.repeat(100));
  const res = await a.api.post('/api/voice', {
    body: bytes,
    headers: { 'content-type': 'audio/mp4', 'x-duration-sec': '12.4' },
  });
  assert.equal(res.status, 201);
  const msg = res.body.message;
  assert.equal(msg.type, 'voice');
  assert.equal(msg.durationSec, 12.4);
  assert.equal(msg.text, null);
  assert.equal(msg.audioUrl, `/api/voice/${msg.id}/raw`);

  const frame = await bSock.waitFor('message', (m) => m.payload.message.type === 'voice');
  assert.equal(frame.payload.message.id, msg.id);

  // Fetch bytes back with Authorization; query credentials are rejected.
  const raw = await b.api.get(msg.audioUrl);
  assert.equal(raw.status, 200);
  assert.equal(raw.headers.get('content-type'), 'audio/mp4');
  assert.deepEqual(raw.body, bytes);
  const queryDenied = await client(baseUrl).get(`${msg.audioUrl}?token=${b.token}`);
  assert.equal(queryDenied.status, 400);
  assert.equal(queryDenied.body.error, 'query_token_forbidden');

  // Without any token → 401.
  const denied = await client(baseUrl).get(msg.audioUrl);
  assert.equal(denied.status, 401);
  assert.equal(denied.body.error, 'invalid_token');

  assert.equal((await a.api.get('/api/voice/msg_nope/raw')).status, 404);
});

test('message delete: sender only, voice file removed, message_deleted broadcast', async (t) => {
  const { baseUrl, dataDir } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const msg = (await a.api.post('/api/messages', { json: { type: 'text', text: 'oops, typo' } })).body.message;

  // Only the sender may delete.
  const denied = await b.api.del(`/api/messages/${msg.id}`);
  assert.equal(denied.status, 403);
  assert.equal(denied.body.error, 'not_yours');

  const del = await a.api.del(`/api/messages/${msg.id}`);
  assert.equal(del.status, 200);
  assert.deepEqual(del.body, { ok: true });
  const frame = await bSock.waitFor('message_deleted');
  assert.deepEqual(frame.payload, { id: msg.id });
  assert.ok(!(await a.api.get('/api/messages')).body.messages.some((m) => m.id === msg.id));

  // Deleted / unknown ids → 404.
  assert.equal((await a.api.del(`/api/messages/${msg.id}`)).status, 404);
  assert.equal((await a.api.del('/api/messages/msg_nope')).status, 404);

  // Deleting a voice message also removes its media file.
  const voice = (
    await a.api.post('/api/voice', { body: Buffer.from('bytes'), headers: { 'content-type': 'audio/mp4' } })
  ).body.message;
  const file = path.join(dataDir, 'media', 'voice', `${voice.id}.m4a`);
  await access(file);
  assert.equal((await a.api.del(`/api/messages/${voice.id}`)).status, 200);
  await assert.rejects(access(file));
  assert.equal((await a.api.get(`/api/voice/${voice.id}/raw`)).status, 404);
});

test('read receipts: POST /api/messages/read sets lastReadAt, broadcasts message_read, shows on members', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a, b, coupleId } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await aSock.waitFor('welcome');
  await bSock.waitFor('welcome');

  // Default: never read anything (also for members stored before v1.6).
  delete app.store.data.couples[coupleId].members[0].lastReadAt;
  let members = (await a.api.get('/api/couple')).body.couple.members;
  assert.deepEqual(members.map((m) => m.lastReadAt), [null, null]);

  // Empty body → "read right now".
  const now = await a.api.post('/api/messages/read');
  assert.equal(now.status, 200);
  assert.equal(now.body.memberId, a.memberId);
  assert.ok(now.body.at);
  // Broadcast goes to the whole couple (sender's other devices included).
  const aFrame = await aSock.waitFor('message_read');
  const bFrame = await bSock.waitFor('message_read');
  assert.deepEqual(aFrame.payload, { memberId: a.memberId, at: now.body.at });
  assert.deepEqual(bFrame.payload, { memberId: a.memberId, at: now.body.at });

  // Explicit at → normalized ISO, visible on the member in couple responses.
  const explicit = await b.api.post('/api/messages/read', { json: { at: '2026-08-01T10:00:00Z' } });
  assert.equal(explicit.body.at, '2026-08-01T10:00:00.000Z');
  members = (await a.api.get('/api/couple')).body.couple.members;
  const byId = Object.fromEntries(members.map((m) => [m.id, m.lastReadAt]));
  assert.equal(byId[a.memberId], now.body.at);
  assert.equal(byId[b.memberId], '2026-08-01T10:00:00.000Z');

  // Invalid at → 400 bad_at.
  const bad = await a.api.post('/api/messages/read', { json: { at: 'gestern' } });
  assert.equal(bad.status, 400);
  assert.equal(bad.body.error, 'bad_at');
});

test('voice upload over 15 MB → 413 too_large', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  const huge = Buffer.alloc(15 * 1024 * 1024 + 1);
  const res = await a.api.post('/api/voice', { body: huge, headers: { 'content-type': 'audio/mp4' } });
  assert.equal(res.status, 413);
  assert.equal(res.body.error, 'too_large');
});
