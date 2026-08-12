import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple } from './helpers.js';

// Mood entries are ordered by createdAt (ms precision) — space requests out a bit.
const tick = () => new Promise((r) => setTimeout(r, 5));

test('mood history: accumulation across both members, newest-first merge, moodNote pairing', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  assert.deepEqual((await a.api.get('/api/moods')).body, { moods: [] });

  await a.api.patch('/api/me', { json: { mood: '🥰', moodNote: 'miss you' } });
  await tick();
  await b.api.patch('/api/me', { json: { mood: '😴' } }); // no note in this request
  await tick();
  await a.api.patch('/api/me', { json: { mood: '🤒', moodNote: null } }); // explicit null note

  const res = await b.api.get('/api/moods');
  assert.equal(res.status, 200);
  const moods = res.body.moods;
  assert.equal(moods.length, 3);

  // Newest first, both members merged.
  assert.deepEqual(moods.map((m) => m.mood), ['🤒', '😴', '🥰']);
  assert.deepEqual(moods.map((m) => m.memberId), [a.memberId, b.memberId, a.memberId]);
  assert.ok(moods[0].createdAt >= moods[1].createdAt && moods[1].createdAt >= moods[2].createdAt);

  // The note is only paired when it was set in the same request.
  assert.equal(moods[2].moodNote, 'miss you');
  assert.equal(moods[1].moodNote, null);
  assert.equal(moods[0].moodNote, null);

  // MoodEntry shape.
  for (const entry of moods) {
    assert.deepEqual(Object.keys(entry).sort(), ['createdAt', 'id', 'memberId', 'mood', 'moodNote']);
    assert.match(entry.id, /^md_/);
  }
});

test('mood history: clearing mood or patching only the note does NOT append', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);

  await a.api.patch('/api/me', { json: { mood: '🥰', moodNote: 'first' } });
  await a.api.patch('/api/me', { json: { mood: null } }); // clear — no entry
  await a.api.patch('/api/me', { json: { name: 'Mimi' } }); // unrelated patch — no entry
  await a.api.patch('/api/me', { json: { mood: '🌈' } });
  await a.api.patch('/api/me', { json: { moodNote: 'note-only update' } }); // note-only — no entry

  const moods = (await a.api.get('/api/moods')).body.moods;
  assert.equal(moods.length, 2);
  assert.deepEqual(moods.map((m) => m.mood).sort(), ['🌈', '🥰'].sort());
  // A later note-only patch does not rewrite history: the 🌈 entry keeps moodNote null.
  assert.equal(moods.find((m) => m.mood === '🌈').moodNote, null);
});

test('mood history is capped at 60 per member; ?limit is honored and capped at 200', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);

  for (let i = 0; i <= 60; i++) {
    const res = await a.api.patch('/api/me', { json: { mood: `mood-${i}` } });
    assert.equal(res.status, 200);
  }

  const all = (await a.api.get('/api/moods?limit=200')).body.moods;
  assert.equal(all.length, 60); // 61 appends, oldest dropped
  assert.equal(all[0].mood, 'mood-60');
  assert.equal(all[59].mood, 'mood-1');
  assert.ok(!all.some((m) => m.mood === 'mood-0'));

  const limited = (await a.api.get('/api/moods?limit=5')).body.moods;
  assert.equal(limited.length, 5);
  assert.equal(limited[0].mood, 'mood-60');

  // Default limit is 80; bogus limit values → 400.
  assert.equal((await a.api.get('/api/moods')).body.moods.length, 60);
  assert.equal((await a.api.get('/api/moods?limit=nope')).status, 400);
});
