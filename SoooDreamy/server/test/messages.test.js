import { test } from 'node:test';
import assert from 'node:assert/strict';
import { access } from 'node:fs/promises';
import path from 'node:path';
import { makeApp, setupCouple, wsOpen, client } from './helpers.js';

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

test('voice upload: raw body → message, media auth via ?token=', async (t) => {
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

  // Fetch bytes back with ?token= (no Authorization header — AVPlayer style).
  const raw = await client(baseUrl).get(`${msg.audioUrl}?token=${b.token}`);
  assert.equal(raw.status, 200);
  assert.equal(raw.headers.get('content-type'), 'audio/mp4');
  assert.deepEqual(raw.body, bytes);

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
