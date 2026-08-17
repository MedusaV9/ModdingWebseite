// Sync contract e (FX-S) — the eval battery's LWW find: calendar PATCHes and
// list mutations from two offline devices silently overwrote each other.
// Calendar events and shared lists now carry `rev` (Int, starts at 1, +1 per
// mutation). Mutations may send `ifRev` — a mismatch answers
// 409 {error:"conflict", current:<resource>} WITHOUT applying anything, so
// the loser can merge instead of clobber. Without `ifRev` the old
// last-write-wins behavior stays (backward compatible with shipped clients).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple, wsOpen } from './helpers.js';

test('EVAL repro: two offline calendar edits — the second ifRev PATCH conflicts instead of clobbering', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  const created = await a.api.post('/api/events', {
    json: { title: 'Jahrestag', date: '2026-09-01', repeatsYearly: true },
  });
  assert.equal(created.status, 201);
  const event = created.body.event;
  assert.equal(event.rev, 1, 'events start at rev 1');

  // Both devices loaded rev 1, then edited offline. A's edit lands first.
  const first = await a.api.patch(`/api/events/${event.id}`, {
    json: { title: 'Jahrestag (Restaurant!)', ifRev: 1 },
  });
  assert.equal(first.status, 200);
  assert.equal(first.body.event.rev, 2);

  // B's stale edit: before the fix this silently reverted A's title.
  const stale = await b.api.patch(`/api/events/${event.id}`, {
    json: { date: '2026-09-02', ifRev: 1 },
  });
  assert.equal(stale.status, 409);
  assert.equal(stale.body.error, 'conflict');
  assert.equal(stale.body.current.rev, 2);
  assert.equal(stale.body.current.title, 'Jahrestag (Restaurant!)');

  // Nothing was applied — B merges against `current` and retries cleanly.
  const events = await b.api.get('/api/events');
  assert.equal(events.body.events[0].date, '2026-09-01');
  const merged = await b.api.patch(`/api/events/${event.id}`, {
    json: { date: '2026-09-02', ifRev: 2 },
  });
  assert.equal(merged.status, 200);
  assert.equal(merged.body.event.rev, 3);
  assert.equal(merged.body.event.title, 'Jahrestag (Restaurant!)');
  assert.equal(merged.body.event.date, '2026-09-02');
});

test('event PATCH without ifRev keeps last-write-wins but still bumps rev', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const created = await a.api.post('/api/events', { json: { title: 'Kino', date: '2026-08-20' } });
  const eventId = created.body.event.id;

  assert.equal((await a.api.patch(`/api/events/${eventId}`, { json: { title: 'Kino um 8' } })).body.event.rev, 2);
  const second = await b.api.patch(`/api/events/${eventId}`, { json: { title: 'Kino um 9' } });
  assert.equal(second.status, 200, 'old clients never see conflicts');
  assert.equal(second.body.event.rev, 3);
  assert.equal(second.body.event.title, 'Kino um 9');

  // ifRev must be a positive integer when present.
  const bad = await a.api.patch(`/api/events/${eventId}`, { json: { title: 'x', ifRev: 'drei' } });
  assert.equal(bad.status, 400);
  assert.equal(bad.body.error, 'invalid_request');
});

test('shared lists carry a list-level rev bumped by EVERY mutation', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  const created = await a.api.post('/api/lists', { json: { name: 'Einkauf', emoji: '🛒' } });
  assert.equal(created.status, 201);
  const list = created.body.list;
  assert.equal(list.rev, 1);

  const added = await a.api.post(`/api/lists/${list.id}/items`, { json: { text: 'Milch' } });
  assert.equal(added.status, 201);
  assert.equal(added.body.list.rev, 2, 'item add bumps');

  const itemId = added.body.item.id;
  const edited = await a.api.patch(`/api/lists/${list.id}/items/${itemId}`, { json: { done: true } });
  assert.equal(edited.body.list.rev, 3, 'item edit bumps');

  const renamed = await a.api.patch(`/api/lists/${list.id}`, { json: { name: 'Wocheneinkauf' } });
  assert.equal(renamed.body.list.rev, 4, 'rename bumps');

  assert.equal((await a.api.del(`/api/lists/${list.id}/items/${itemId}`)).status, 200);
  const fetched = (await a.api.get('/api/lists')).body.lists.find((l) => l.id === list.id);
  assert.equal(fetched.rev, 5, 'item delete bumps');
});

test('EVAL repro: concurrent list item edits — ifRev turns the silent overwrite into a 409 merge', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const created = await a.api.post('/api/lists', { json: { name: 'Packliste', emoji: '🎒' } });
  const listId = created.body.list.id;
  const added = await a.api.post(`/api/lists/${listId}/items`, { json: { text: 'Sonnencreme' } });
  const itemId = added.body.item.id;
  const rev = added.body.list.rev; // 2

  // Both partners loaded rev 2. A's edit wins the race …
  const first = await a.api.patch(`/api/lists/${listId}/items/${itemId}`, {
    json: { text: 'Sonnencreme LSF 50', ifRev: rev },
  });
  assert.equal(first.status, 200);

  // … so B's stale edit conflicts WITH the current list attached.
  const stale = await b.api.patch(`/api/lists/${listId}/items/${itemId}`, {
    json: { text: 'Sonnenmilch', ifRev: rev },
  });
  assert.equal(stale.status, 409);
  assert.equal(stale.body.error, 'conflict');
  assert.equal(stale.body.current.rev, 3);
  assert.equal(stale.body.current.items[0].text, 'Sonnencreme LSF 50');

  // Same guard on item ADD and list rename.
  const staleAdd = await b.api.post(`/api/lists/${listId}/items`, { json: { text: 'Hut', ifRev: rev } });
  assert.equal(staleAdd.status, 409);
  assert.equal(staleAdd.body.error, 'conflict');
  const staleRename = await b.api.patch(`/api/lists/${listId}`, { json: { name: 'Urlaub', ifRev: rev } });
  assert.equal(staleRename.status, 409);

  // No list_updated broadcast fired for any refused mutation.
  const finalList = (await a.api.get('/api/lists')).body.lists[0];
  assert.equal(finalList.items.length, 1);
  assert.equal(finalList.rev, 3);
});

test('pre-contract stores without rev default to 1 on the way out', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  const created = await a.api.post('/api/events', { json: { title: 'Alt', date: '2026-01-01' } });
  const list = await a.api.post('/api/lists', { json: { name: 'Alt', emoji: '📦' } });

  // Simulate records persisted before the contract shipped.
  const couple = Object.values(app.store.data.couples)[0];
  delete couple.events[0].rev;
  delete couple.lists.find((l) => l.id === list.body.list.id).rev;

  assert.equal((await a.api.get('/api/events')).body.events[0].rev, 1);
  assert.equal((await a.api.get('/api/lists')).body.lists[0].rev, 1);

  // The first mutation moves them to rev 2 — the counter picks up seamlessly.
  const patched = await a.api.patch(`/api/events/${created.body.event.id}`, { json: { title: 'Neu', ifRev: 1 } });
  assert.equal(patched.status, 200);
  assert.equal(patched.body.event.rev, 2);
});
