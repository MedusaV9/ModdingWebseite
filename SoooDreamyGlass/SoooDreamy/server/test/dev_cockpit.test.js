import { test } from 'node:test';
import assert from 'node:assert/strict';
import { dateKeyDaysAgo, makeApp, setupCouple } from './helpers.js';

test('dev cockpit is disabled by default', async (t) => {
  const { baseUrl } = await makeApp(t);
  const response = await fetch(`${baseUrl}/dev/cockpit`);
  assert.equal(response.status, 404);
});

test('dev cockpit serves the dependency-free two-member QA surface when enabled', async (t) => {
  const { baseUrl } = await makeApp(t, { devCockpit: true });
  const response = await fetch(`${baseUrl}/dev/cockpit`);
  const html = await response.text();

  assert.equal(response.status, 200);
  assert.match(response.headers.get('content-type'), /^text\/html/);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.match(html, /SoooDreamy Dev Cockpit/);
  assert.match(html, /Mia/);
  assert.match(html, /Ben/);
  assert.match(html, /\/api\/touches/);
  assert.match(html, /\/api\/daily\//);
  assert.match(html, /\/api\/games/);
  assert.doesNotMatch(html, /https?:\/\/[^'"]+\.(js|css)/);
});

test('the cockpit pair → touch → daily → game-move flow succeeds end to end', async (t) => {
  const { baseUrl } = await makeApp(t, { devCockpit: true });
  const { a, b } = await setupCouple(baseUrl);

  assert.equal((await a.api.post('/api/touches', { json: { type: 'heartbeat' } })).status, 201);

  const today = dateKeyDaysAgo(0);
  assert.equal((await a.api.post(`/api/daily/${today}`, {
    json: { questionId: 42, text: 'Mias Cockpit-Antwort' },
  })).status, 200);
  const revealed = await b.api.post(`/api/daily/${today}`, {
    json: { questionId: 42, text: 'Bens cockpit answer' },
  });
  assert.equal(revealed.status, 200);
  assert.equal(revealed.body.bothAnswered, true);

  const created = await a.api.post('/api/games', {
    json: { type: 'connectfour', payload: {} },
  });
  assert.equal(created.status, 201);
  assert.equal((await b.api.post(`/api/games/${created.body.game.id}/join`)).status, 200);
  const move = await a.api.post(`/api/games/${created.body.game.id}/move`, {
    json: { data: { kind: 'drop', column: 0 } },
  });
  assert.equal(move.status, 201);
  assert.equal(move.body.move.data.column, 0);
});
