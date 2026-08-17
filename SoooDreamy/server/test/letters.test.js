import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple, wsOpen } from './helpers.js';

test('openWhen is stored (trimmed) and echoed for letters, in list and WS broadcast', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const res = await a.api.post('/api/messages', {
    json: { type: 'letter', text: 'Dear Ben…', title: 'Open later', openWhen: '  on our anniversary  ' },
  });
  assert.equal(res.status, 201);
  assert.equal(res.body.message.openWhen, 'on our anniversary');

  const frame = await bSock.waitFor('message');
  assert.deepEqual(frame.payload.message, res.body.message);

  const list = await b.api.get('/api/messages');
  assert.equal(list.body.messages.at(-1).openWhen, 'on our anniversary');

  // Letters without openWhen carry null.
  const plain = await a.api.post('/api/messages', { json: { type: 'letter', text: 'no seal' } });
  assert.equal(plain.body.message.openWhen, null);
});

test('openWhen is silently ignored for text messages and absent (null) on voice', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);

  const text = await a.api.post('/api/messages', {
    json: { type: 'text', text: 'hi', openWhen: 'x'.repeat(500) }, // even over-long values are ignored for text
  });
  assert.equal(text.status, 201);
  assert.equal(text.body.message.openWhen, null);

  const voice = await a.api.post('/api/voice', {
    body: Buffer.from('audio-bytes'),
    headers: { 'content-type': 'audio/mp4', 'x-duration-sec': '1.5' },
  });
  assert.equal(voice.status, 201);
  assert.equal(voice.body.message.openWhen, null);

  const list = await a.api.get('/api/messages');
  assert.ok(list.body.messages.every((m) => m.openWhen === null));
});

test('openWhen longer than 64 chars (after trim) → 400 openwhen_too_long', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);

  const tooLong = await a.api.post('/api/messages', {
    json: { type: 'letter', text: 'x', openWhen: 'w'.repeat(65) },
  });
  assert.equal(tooLong.status, 400);
  assert.equal(tooLong.body.error, 'openwhen_too_long');

  const maxed = await a.api.post('/api/messages', {
    json: { type: 'letter', text: 'x', openWhen: `  ${'w'.repeat(64)}  ` }, // 64 after trim is fine
  });
  assert.equal(maxed.status, 201);
  assert.equal(maxed.body.message.openWhen, 'w'.repeat(64));

  // Whitespace-only collapses to null; non-string → 400.
  const blank = await a.api.post('/api/messages', { json: { type: 'letter', text: 'x', openWhen: '   ' } });
  assert.equal(blank.body.message.openWhen, null);
  assert.equal((await a.api.post('/api/messages', { json: { type: 'letter', text: 'x', openWhen: 42 } })).status, 400);
});
