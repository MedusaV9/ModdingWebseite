import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple, wsOpen } from './helpers.js';

test('events CRUD with broadcasts', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const created = await a.api.post('/api/events', {
    json: { title: 'Anniversary', emoji: '💍', date: '2026-11-07', repeatsYearly: true },
  });
  assert.equal(created.status, 201);
  const event = created.body.event;
  assert.match(event.id, /^ev_/);
  assert.equal(event.createdBy, a.memberId);
  assert.equal(event.repeatsYearly, true);
  const added = await bSock.waitFor('event_added');
  assert.deepEqual(added.payload.event, event);

  const patched = await b.api.patch(`/api/events/${event.id}`, { json: { title: 'Our Anniversary 🥂', date: '2026-11-08' } });
  assert.equal(patched.status, 200);
  assert.equal(patched.body.event.title, 'Our Anniversary 🥂');
  assert.equal(patched.body.event.date, '2026-11-08');
  const updated = await bSock.waitFor('event_updated');
  assert.equal(updated.payload.event.title, 'Our Anniversary 🥂');

  assert.equal((await a.api.post('/api/events', { json: { title: 'Bad', date: '07.11.2026' } })).status, 400);
  assert.equal((await a.api.patch('/api/events/ev_nope', { json: { title: 'x' } })).status, 404);

  const list = await a.api.get('/api/events');
  assert.equal(list.body.events.length, 1);

  const del = await a.api.del(`/api/events/${event.id}`);
  assert.equal(del.status, 200);
  const deleted = await bSock.waitFor('event_deleted');
  assert.deepEqual(deleted.payload, { id: event.id });
  assert.equal((await a.api.get('/api/events')).body.events.length, 0);
});

test('bucket CRUD with done/doneAt handling and broadcasts', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  await aSock.waitFor('welcome');

  const created = await b.api.post('/api/bucket', { json: { text: 'See the northern lights', emoji: '🌌' } });
  assert.equal(created.status, 201);
  const item = created.body.item;
  assert.equal(item.done, false);
  assert.equal(item.doneAt, null);
  const added = await aSock.waitFor('bucket_added');
  assert.deepEqual(added.payload.item, item);

  const done = await a.api.patch(`/api/bucket/${item.id}`, { json: { done: true } });
  assert.equal(done.body.item.done, true);
  assert.ok(done.body.item.doneAt);
  const updated = await aSock.waitFor('bucket_updated');
  assert.equal(updated.payload.item.done, true);

  const undone = await a.api.patch(`/api/bucket/${item.id}`, { json: { done: false, text: 'Northern lights in Norway' } });
  assert.equal(undone.body.item.done, false);
  assert.equal(undone.body.item.doneAt, null);
  assert.equal(undone.body.item.text, 'Northern lights in Norway');

  assert.equal((await a.api.get('/api/bucket')).body.items.length, 1);

  const del = await b.api.del(`/api/bucket/${item.id}`);
  assert.equal(del.status, 200);
  const deleted = await aSock.waitFor('bucket_deleted');
  assert.deepEqual(deleted.payload, { id: item.id });
  assert.equal((await a.api.get('/api/bucket')).body.items.length, 0);
  assert.equal((await a.api.patch(`/api/bucket/${item.id}`, { json: { done: true } })).status, 404);
});
