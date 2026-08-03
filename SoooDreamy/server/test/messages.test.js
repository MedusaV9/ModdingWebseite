import { test } from 'node:test';
import assert from 'node:assert/strict';
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

test('voice upload over 15 MB → 413 too_large', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  const huge = Buffer.alloc(15 * 1024 * 1024 + 1);
  const res = await a.api.post('/api/voice', { body: huge, headers: { 'content-type': 'audio/mp4' } });
  assert.equal(res.status, 413);
  assert.equal(res.body.error, 'too_large');
});
