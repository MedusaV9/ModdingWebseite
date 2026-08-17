import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple } from './helpers.js';

test('repair conversation enforces uninterrupted mirrored turns and two agreements', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  const created = await a.api.post('/api/repair', { json: { promptId: 'listen-first' } });
  assert.equal(created.status, 201);
  const sessionId = created.body.session.id;
  assert.deepEqual(created.body.session.expected, { memberId: a.memberId, kind: 'feeling' });

  const feelingA = await a.api.post(`/api/repair/${sessionId}/turn`, {
    json: { kind: 'feeling', text: 'Ich fühle mich nicht gehört.' },
  });
  assert.equal(feelingA.status, 200);
  assert.deepEqual(feelingA.body.session.expected, { memberId: b.memberId, kind: 'mirror' });

  const interrupted = await a.api.post(`/api/repair/${sessionId}/turn`, {
    json: { kind: 'feeling', text: 'Noch etwas' },
  });
  assert.equal(interrupted.status, 409);
  assert.equal(interrupted.body.error, 'wrong_turn');

  const wrongStep = await b.api.post(`/api/repair/${sessionId}/turn`, {
    json: { kind: 'agreement', text: 'Zu früh' },
  });
  assert.equal(wrongStep.status, 409);
  assert.equal(wrongStep.body.error, 'wrong_step');

  const turns = [
    [b, 'mirror', 'Ich höre, dass du dich übergangen fühlst.'],
    [b, 'feeling', 'Ich war überfordert und wurde still.'],
    [a, 'mirror', 'Ich höre, dass du Ruhe brauchtest.'],
    [a, 'agreement', 'Wir sagen künftig kurz, wenn wir Pause brauchen.'],
    [b, 'agreement', 'Und wir kommen nach 20 Minuten zurück.'],
  ];
  let session;
  for (const [actor, kind, text] of turns) {
    const response = await actor.api.post(`/api/repair/${sessionId}/turn`, { json: { kind, text } });
    assert.equal(response.status, 200);
    session = response.body.session;
  }
  assert.equal(session.status, 'completed');
  assert.equal(session.entries.length, 6);
  assert.equal(session.expected, null);
});

test('repair cooldown blocks both partners until the server deadline', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  const created = await a.api.post('/api/repair', { json: { promptId: 'cool-down' } });
  const sessionId = created.body.session.id;

  const bad = await a.api.post(`/api/repair/${sessionId}/cooldown`, { json: { minutes: 0 } });
  assert.equal(bad.status, 400);
  assert.equal(bad.body.error, 'bad_minutes');

  const paused = await a.api.post(`/api/repair/${sessionId}/cooldown`, { json: { minutes: 5 } });
  assert.equal(paused.status, 200);
  assert.ok(Date.parse(paused.body.session.cooldownUntil) > Date.now());

  const blocked = await a.api.post(`/api/repair/${sessionId}/turn`, {
    json: { kind: 'feeling', text: 'Noch nicht' },
  });
  assert.equal(blocked.status, 409);
  assert.equal(blocked.body.error, 'cooldown_active');
});

test('consideration radar stores ciphertext only and pause is immediate', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const plaintextMarker = 'heute besonders lieb sein';
  const ciphertext = Buffer.from(`sealed:${plaintextMarker}:with-auth-tag`).toString('base64');

  const rejected = await a.api.post('/api/consideration', {
    json: { ciphertext, text: plaintextMarker },
  });
  assert.equal(rejected.status, 400);
  assert.equal(rejected.body.error, 'plaintext_forbidden');

  const created = await a.api.post('/api/consideration', {
    json: { ciphertext, visibility: 'gentle', hours: 12 },
  });
  assert.equal(created.status, 201);
  assert.equal(created.body.hint.ciphertext, ciphertext);
  assert.equal(JSON.stringify(app.store.data).includes(plaintextMarker), false);

  const visible = await b.api.get('/api/consideration');
  assert.equal(visible.body.hints.length, 1);
  assert.equal(visible.body.hints[0].ciphertext, ciphertext);

  const notYours = await b.api.del(`/api/consideration/${created.body.hint.id}`);
  assert.equal(notYours.status, 403);

  const paused = await a.api.del(`/api/consideration/${created.body.hint.id}`);
  assert.equal(paused.status, 200);
  assert.ok(paused.body.hint.pausedAt);
  const after = await b.api.get('/api/consideration');
  assert.deepEqual(after.body.hints, []);
});
