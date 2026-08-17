import { test } from 'node:test';
import assert from 'node:assert/strict';
import { gameRulesInternals } from '../src/game-rules.js';
import { makeApp, setupCouple } from './helpers.js';

// Invitation + "your turn" pushes for the games routes: without them the
// whole invite flow dies as soon as the partner is offline (the socket
// broadcast reaches nobody). Contract pinned here:
//   - POST /api/games queues ONE invitation push to the partner (not for
//     `dailyquests`, which is a self-started shared checklist)
//   - the move route pushes only when the turn NEWLY switches to the partner
//     (previous last move was theirs / first move), never on the finishing
//     move, throttled to one push per game/recipient/hour
//   - payloads carry type "game" and a sooodreamy://game/<id> deep link and
//     never leak move data

const TOKEN_A = 'aa'.repeat(32);
const TOKEN_B = 'bb'.repeat(32);

async function waitFor(check) {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    if (check()) return;
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
  assert.fail('timed out waiting for asynchronous push delivery');
}

async function settle(ms = 50) {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

async function pushCouple(t) {
  const deliveries = [];
  const provider = { async send(request) { deliveries.push(request); } };
  const { baseUrl, app } = await makeApp(t, { pushProvider: provider });
  const { a, b } = await setupCouple(baseUrl);
  await a.api.post('/api/push-devices/current', {
    json: { apnsToken: TOKEN_A, environment: 'development', bundleId: 'app.sooodreamy.ios', language: 'en' },
  });
  await b.api.post('/api/push-devices/current', {
    json: { apnsToken: TOKEN_B, environment: 'development', bundleId: 'app.sooodreamy.ios', language: 'de' },
  });
  return { deliveries, app, a, b };
}

test('game invitation queues a push to the partner with a game deep link', async (t) => {
  const { deliveries, a } = await pushCouple(t);
  const created = await a.api.post('/api/games', { json: { type: 'story', payload: { genre: 2, sentences: 6, lang: 'de' } } });
  assert.equal(created.status, 201);
  const gameId = created.body.game.id;

  await waitFor(() => deliveries.length === 1);
  assert.equal(deliveries[0].token, TOKEN_B);
  assert.equal(deliveries[0].payload.type, 'game');
  assert.equal(deliveries[0].payload.link, `sooodreamy://game/${gameId}`);
  assert.match(deliveries[0].payload.aps.alert.title, /^Spiel-Einladung von Mia/);
});

test('turn handover pushes once per switch, throttled per game/recipient/hour', async (t) => {
  const { deliveries, app, a, b } = await pushCouple(t);
  const created = await a.api.post('/api/games', { json: { type: 'story', payload: { genre: 2, sentences: 6, lang: 'de' } } });
  const gameId = created.body.game.id;
  await b.api.post(`/api/games/${gameId}/join`, { json: {} });
  await waitFor(() => deliveries.length === 1); // invitation push
  const move = (who, index) =>
    who.api.post(`/api/games/${gameId}/move`, { json: { data: { kind: 'sentence', index, text: `Satz ${index}` } } });

  // First move by the creator → the partner is NEWLY awaiting → push to B.
  assert.equal((await move(a, 0)).status, 201);
  await waitFor(() => deliveries.length === 2);
  assert.equal(deliveries[1].token, TOKEN_B);
  assert.equal(deliveries[1].payload.type, 'game');
  assert.equal(deliveries[1].payload.link, `sooodreamy://game/${gameId}`);
  assert.match(deliveries[1].payload.aps.alert.title, /^Du bist dran/);
  assert.match(deliveries[1].payload.aps.alert.body, /Mia/);
  assert.equal(JSON.stringify(deliveries[1].payload).includes('Satz 0'), false);

  // B answers → the turn newly switches to A → push to A (English device).
  assert.equal((await move(b, 1)).status, 201);
  await waitFor(() => deliveries.length === 3);
  assert.equal(deliveries[2].token, TOKEN_A);
  assert.match(deliveries[2].payload.aps.alert.title, /^Your turn/);

  // Another handover within the hour: both recipients are throttled.
  assert.equal((await move(a, 2)).status, 201);
  assert.equal((await move(b, 3)).status, 201);
  await settle();
  assert.equal(deliveries.length, 3);

  // Rewind B's throttle two hours → the next handover to B pushes again.
  const couple = Object.values(app.store.data.couples)[0];
  const game = couple.games.find((g) => g.id === gameId);
  game.turnPushAt[b.memberId] = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString();
  assert.equal((await move(a, 4)).status, 201);
  await waitFor(() => deliveries.length === 4);
  assert.equal(deliveries[3].token, TOKEN_B);

  // The finishing move never pushes ("your turn" in an ended game is a lie).
  game.turnPushAt[a.memberId] = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString();
  const finish = await move(b, 5);
  assert.equal(finish.status, 201);
  assert.equal(finish.body.game.state, 'ended');
  await settle();
  assert.equal(deliveries.length, 4);

  // turnPushAt is internal throttle state — it never leaks into the API shape.
  const fetched = await a.api.get(`/api/games/${gameId}`);
  assert.equal('turnPushAt' in fetched.body.game, false);
});

test('dailyquests never push (self-started shared checklist, not an invite)', async (t) => {
  const { deliveries, app, a } = await pushCouple(t);
  const created = await a.api.post('/api/games', { json: { type: 'dailyquests' } });
  assert.equal(created.status, 201);
  const game = created.body.game;
  await a.api.post(`/api/games/${game.id}/join`, { json: {} });
  const coupleId = Object.keys(app.store.data.couples)[0];
  const [questIndex] = gameRulesInternals.dailyQuestIndexes(coupleId, game.payload.dateKey);
  const moved = await a.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'quest_done', questIndex } },
  });
  assert.equal(moved.status, 201);
  await settle();
  assert.equal(deliveries.length, 0);
});
