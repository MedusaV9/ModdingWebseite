import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple, wsOpen } from './helpers.js';

test('reactions: toggle on/off, both members on the same emoji, message_updated broadcasts', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await aSock.waitFor('welcome');
  await bSock.waitFor('welcome');

  const msg = (await a.api.post('/api/messages', { json: { type: 'text', text: 'react to me' } })).body.message;
  assert.equal(msg.reactions, null); // serialization includes the field from the start

  // A toggles ❤️ on.
  const on = await a.api.post(`/api/messages/${msg.id}/reactions`, { json: { emoji: '❤️' } });
  assert.equal(on.status, 200);
  assert.deepEqual(on.body.message.reactions, { '❤️': [a.memberId] });

  // Couple-wide broadcast — both members' sockets get the updated message.
  const aFrame = await aSock.waitFor('message_updated');
  const bFrame = await bSock.waitFor('message_updated');
  assert.deepEqual(aFrame.payload.message, on.body.message);
  assert.deepEqual(bFrame.payload.message, on.body.message);

  // B joins with the same emoji → both ids, in toggle order.
  const both = await b.api.post(`/api/messages/${msg.id}/reactions`, { json: { emoji: '❤️' } });
  assert.deepEqual(both.body.message.reactions, { '❤️': [a.memberId, b.memberId] });

  // A toggles off → only B remains; the emoji is trimmed before matching.
  const off = await a.api.post(`/api/messages/${msg.id}/reactions`, { json: { emoji: ' ❤️ ' } });
  assert.deepEqual(off.body.message.reactions, { '❤️': [b.memberId] });

  // B toggles off → empty emoji key removed, reactions back to null.
  const empty = await b.api.post(`/api/messages/${msg.id}/reactions`, { json: { emoji: '❤️' } });
  assert.equal(empty.body.message.reactions, null);

  // The list view agrees.
  const list = await a.api.get('/api/messages');
  assert.equal(list.body.messages.find((m) => m.id === msg.id).reactions, null);
});

test('reactions work on voice messages and multiple emoji keys coexist', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  const voice = (
    await a.api.post('/api/voice', { body: Buffer.from('audio'), headers: { 'content-type': 'audio/mp4' } })
  ).body.message;
  assert.equal(voice.reactions, null);

  await b.api.post(`/api/messages/${voice.id}/reactions`, { json: { emoji: '🔥' } });
  const res = await a.api.post(`/api/messages/${voice.id}/reactions`, { json: { emoji: '😂' } });
  assert.deepEqual(res.body.message.reactions, { '🔥': [b.memberId], '😂': [a.memberId] });
});

test('reactions validation: bad emoji → 400 bad_emoji, unknown message → 404', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  const msg = (await a.api.post('/api/messages', { json: { type: 'text', text: 'x' } })).body.message;

  for (const emoji of ['', '   ', 'x'.repeat(17), 42, null]) {
    const res = await a.api.post(`/api/messages/${msg.id}/reactions`, { json: { emoji } });
    assert.equal(res.status, 400, `emoji ${JSON.stringify(emoji)} should be rejected`);
    assert.equal(res.body.error, 'bad_emoji');
  }
  // 16 chars after trim is fine (multi-codepoint emoji are longer than 1 JS char).
  assert.equal(
    (await a.api.post(`/api/messages/${msg.id}/reactions`, { json: { emoji: ` ${'x'.repeat(16)} ` } })).status,
    200,
  );

  const unknown = await a.api.post('/api/messages/msg_nope/reactions', { json: { emoji: '❤️' } });
  assert.equal(unknown.status, 404);
  assert.equal(unknown.body.error, 'not_found');
});
