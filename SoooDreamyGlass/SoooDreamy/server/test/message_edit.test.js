import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple, wsOpen } from './helpers.js';

test('message edit: sender rewrites text, editedAt set, message_updated broadcast to both', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await aSock.waitFor('welcome');
  await bSock.waitFor('welcome');

  const msg = (await a.api.post('/api/messages', { json: { type: 'text', text: 'helo ❤️' } })).body.message;
  assert.equal(msg.editedAt, null); // serialization includes the field from the start

  const res = await a.api.patch(`/api/messages/${msg.id}`, { json: { text: 'hello ❤️' } });
  assert.equal(res.status, 200);
  const edited = res.body.message;
  assert.equal(edited.id, msg.id);
  assert.equal(edited.text, 'hello ❤️');
  assert.equal(edited.createdAt, msg.createdAt); // order stays put
  assert.match(edited.editedAt, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/);

  // Couple-wide broadcast — both members' sockets get the updated message.
  const aFrame = await aSock.waitFor('message_updated');
  const bFrame = await bSock.waitFor('message_updated');
  assert.deepEqual(aFrame.payload.message, edited);
  assert.deepEqual(bFrame.payload.message, edited);

  // The list view agrees, and a second edit moves editedAt forward (or keeps it).
  const list = (await b.api.get('/api/messages')).body.messages;
  assert.deepEqual(list.find((m) => m.id === msg.id), edited);
  const again = await a.api.patch(`/api/messages/${msg.id}`, { json: { text: 'hello again' } });
  assert.equal(again.body.message.text, 'hello again');
  assert.ok(again.body.message.editedAt >= edited.editedAt);
});

test('message edit: letters editable (title/openWhen untouched), reactions survive', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  const letter = (
    await a.api.post('/api/messages', {
      json: { type: 'letter', text: 'Dear Ben…', title: 'For you', openWhen: 'someday' },
    })
  ).body.message;
  await b.api.post(`/api/messages/${letter.id}/reactions`, { json: { emoji: '💌' } });

  const res = await a.api.patch(`/api/messages/${letter.id}`, { json: { text: 'Dear Ben — rewritten' } });
  assert.equal(res.status, 200);
  assert.equal(res.body.message.text, 'Dear Ben — rewritten');
  assert.equal(res.body.message.title, 'For you');
  assert.equal(res.body.message.openWhen, 'someday');
  assert.deepEqual(res.body.message.reactions, { '💌': [b.memberId] });
});

test('message edit: sender only, text/letter only, unknown ids 404', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  const msg = (await a.api.post('/api/messages', { json: { type: 'text', text: 'mine' } })).body.message;
  const denied = await b.api.patch(`/api/messages/${msg.id}`, { json: { text: 'not yours' } });
  assert.equal(denied.status, 403);
  assert.equal(denied.body.error, 'not_yours');
  assert.equal((await a.api.get('/api/messages')).body.messages.find((m) => m.id === msg.id).text, 'mine');

  // Voice and photo messages are not editable.
  const voice = (
    await a.api.post('/api/voice', { body: Buffer.from('audio'), headers: { 'content-type': 'audio/mp4' } })
  ).body.message;
  const voiceRes = await a.api.patch(`/api/messages/${voice.id}`, { json: { text: 'nope' } });
  assert.equal(voiceRes.status, 400);
  assert.equal(voiceRes.body.error, 'not_editable');

  const photo = (
    await a.api.post('/api/photos', { body: Buffer.from('jpeg'), headers: { 'content-type': 'image/jpeg' } })
  ).body.photo;
  const photoMsg = (await a.api.post('/api/messages', { json: { type: 'photo', photoId: photo.id } })).body.message;
  const photoRes = await a.api.patch(`/api/messages/${photoMsg.id}`, { json: { text: 'nope' } });
  assert.equal(photoRes.status, 400);
  assert.equal(photoRes.body.error, 'not_editable');

  assert.equal((await a.api.patch('/api/messages/msg_nope', { json: { text: 'x' } })).status, 404);
});

test('message edit validation: missing/empty/too-long text', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  const msg = (await a.api.post('/api/messages', { json: { type: 'text', text: 'ok' } })).body.message;

  assert.equal((await a.api.patch(`/api/messages/${msg.id}`, { json: {} })).status, 400);
  assert.equal((await a.api.patch(`/api/messages/${msg.id}`, { json: { text: '   ' } })).status, 400);
  const tooLong = await a.api.patch(`/api/messages/${msg.id}`, { json: { text: 'x'.repeat(5001) } });
  assert.equal(tooLong.status, 400);
  assert.equal(tooLong.body.error, 'text_too_long');
  assert.equal((await a.api.patch(`/api/messages/${msg.id}`, { json: { text: 'x'.repeat(5000) } })).status, 200);
});
