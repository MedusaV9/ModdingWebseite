import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple, wsOpen } from './helpers.js';

test('PATCH /api/me updates profile + mood and broadcasts member_updated', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const res = await a.api.patch('/api/me', { json: { name: 'Mimi', mood: '🥰', moodNote: 'miss you' } });
  assert.equal(res.status, 200);
  assert.equal(res.body.member.name, 'Mimi');
  assert.equal(res.body.member.mood, '🥰');
  assert.equal(res.body.member.moodNote, 'miss you');
  assert.ok(res.body.member.moodUpdatedAt);

  const frame = await bSock.waitFor('member_updated', (m) => m.payload.member.id === a.memberId);
  assert.equal(frame.payload.member.name, 'Mimi');
  assert.equal(frame.payload.member.mood, '🥰');

  // mood: null clears mood, note and timestamp
  const cleared = await a.api.patch('/api/me', { json: { mood: null } });
  assert.equal(cleared.body.member.mood, null);
  assert.equal(cleared.body.member.moodNote, null);
  assert.equal(cleared.body.member.moodUpdatedAt, null);
  await bSock.waitFor('member_updated', (m) => m.payload.member.mood === null);
});

test('PATCH /api/couple sets anniversary/name and broadcasts couple_updated', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const res = await a.api.patch('/api/couple', { json: { name: 'Mia & Ben', anniversary: '2023-11-07' } });
  assert.equal(res.status, 200);
  assert.equal(res.body.couple.name, 'Mia & Ben');
  assert.equal(res.body.couple.anniversary, '2023-11-07');

  const frame = await bSock.waitFor('couple_updated');
  assert.equal(frame.payload.couple.anniversary, '2023-11-07');

  const bad = await a.api.patch('/api/couple', { json: { anniversary: 'next tuesday' } });
  assert.equal(bad.status, 400);

  const fetched = await b.api.get('/api/couple');
  assert.equal(fetched.status, 200);
  assert.equal(fetched.body.couple.anniversary, '2023-11-07');
  assert.equal(fetched.body.me, b.memberId);
});

test('presence: online on first socket, offline (with lastSeenAt) after the last closes', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  await aSock.waitFor('welcome');

  // B opens two sockets — only the first should trigger a presence broadcast.
  const bSock1 = await wsOpen(baseUrl, b.token, t);
  const online = await aSock.waitFor('presence', (m) => m.payload.memberId === b.memberId);
  assert.equal(online.payload.online, true);
  const bSock2 = await wsOpen(baseUrl, b.token, t);
  const welcome2 = await bSock2.waitFor('welcome');
  assert.equal(welcome2.payload.partnerOnline, true);
  await aSock.assertNone('presence');

  // Multiple sockets per member: both of B's sockets receive couple-wide broadcasts.
  await a.api.post('/api/messages', { json: { type: 'text', text: 'hi you two (devices)' } });
  await bSock1.waitFor('message');
  await bSock2.waitFor('message');

  // Closing only one of B's sockets must NOT mark B offline.
  bSock1.close();
  await bSock1.closed();
  await aSock.assertNone('presence');

  bSock2.close();
  await bSock2.closed();
  const offline = await aSock.waitFor('presence', (m) => m.payload.memberId === b.memberId);
  assert.equal(offline.payload.online, false);
  assert.ok(offline.payload.lastSeenAt);

  const coupleRes = await a.api.get('/api/couple');
  const bMember = coupleRes.body.couple.members.find((m) => m.id === b.memberId);
  assert.equal(bMember.online, false);
  assert.equal(bMember.lastSeenAt, offline.payload.lastSeenAt);
});

test('typing is forwarded to the partner only', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await aSock.waitFor('welcome');
  await bSock.waitFor('welcome');

  aSock.send({ type: 'typing', payload: { isTyping: true } });
  const frame = await bSock.waitFor('typing');
  assert.deepEqual(frame.payload, { memberId: a.memberId, isTyping: true });
  await aSock.assertNone('typing');
});
