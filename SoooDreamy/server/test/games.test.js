import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple, wsOpen } from './helpers.js';

test('game lifecycle: create → join → moves via WS → end with result', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await aSock.waitFor('welcome');
  await bSock.waitFor('welcome');

  const created = await a.api.post('/api/games', { json: { type: 'quiz', payload: { rounds: 5 } } });
  assert.equal(created.status, 201);
  const game = created.body.game;
  assert.equal(game.state, 'lobby');
  assert.equal(game.createdBy, a.memberId);
  assert.deepEqual(game.payload, { rounds: 5 });
  const createdFrame = await bSock.waitFor('game_created');
  assert.deepEqual(createdFrame.payload.game, game);

  // Moves before the game is active are rejected.
  assert.equal((await b.api.post(`/api/games/${game.id}/move`, { json: { data: { answer: 1 } } })).status, 409);

  const joined = await b.api.post(`/api/games/${game.id}/join`, { json: {} });
  assert.equal(joined.status, 200);
  assert.equal(joined.body.game.state, 'active');
  await aSock.waitFor('game_started');
  await bSock.waitFor('game_started');

  // Moves are relayed couple-wide.
  const move = await a.api.post(`/api/games/${game.id}/move`, { json: { data: { round: 1, answer: 'B' } } });
  assert.equal(move.status, 201);
  assert.equal(move.body.move.memberId, a.memberId);
  const moveFrame = await bSock.waitFor('game_move');
  assert.equal(moveFrame.payload.gameId, game.id);
  assert.deepEqual(moveFrame.payload.move, move.body.move);
  await aSock.waitFor('game_move');

  const ended = await b.api.post(`/api/games/${game.id}/end`, { json: { result: { winner: b.memberId, score: '3:2' } } });
  assert.equal(ended.status, 200);
  assert.equal(ended.body.game.state, 'ended');
  assert.deepEqual(ended.body.game.result, { winner: b.memberId, score: '3:2' });
  assert.equal(ended.body.game.moves.length, 1);
  const endedFrame = await aSock.waitFor('game_ended');
  assert.deepEqual(endedFrame.payload.game.result, { winner: b.memberId, score: '3:2' });

  assert.equal((await a.api.get('/api/games/active')).body.game, null);
});

test('creating a game auto-ends the previous non-ended game', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  const g1 = (await a.api.post('/api/games', { json: { type: 'thisorthat' } })).body.game;
  let active = await b.api.get('/api/games/active');
  assert.equal(active.body.game.id, g1.id);

  const g2 = (await b.api.post('/api/games', { json: { type: 'wouldyourather' } })).body.game;
  active = await a.api.get('/api/games/active');
  assert.equal(active.body.game.id, g2.id);

  // g1 must be ended now: after ending g2 there is no active game left.
  await a.api.post(`/api/games/${g2.id}/end`, { json: {} });
  active = await a.api.get('/api/games/active');
  assert.equal(active.body.game, null);
  assert.equal((await a.api.post(`/api/games/${g1.id}/join`, { json: {} })).status, 409);
});

test('game validation: unknown type / unknown id', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  assert.equal((await a.api.post('/api/games', { json: { type: 'chess' } })).status, 400);
  assert.equal((await a.api.post('/api/games/g_nope/join', { json: {} })).status, 404);
  assert.equal((await a.api.post('/api/games/g_nope/move', { json: { data: {} } })).status, 404);
});
