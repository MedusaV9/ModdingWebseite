import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple, wsOpen } from './helpers.js';
import { RateLimiter } from '../src/security.js';

test('game lifecycle: create → join → validated moves → canonical result via WS', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await aSock.waitFor('welcome');
  await bSock.waitFor('welcome');

  const created = await a.api.post('/api/games', { json: { type: 'quiz', payload: { rounds: 1 } } });
  assert.equal(created.status, 201);
  const game = created.body.game;
  assert.equal(game.state, 'lobby');
  assert.equal(game.createdBy, a.memberId);
  assert.equal(game.payload.rounds, 1);
  assert.ok(Number.isInteger(game.payload.seed)); // v3.0: server injects a shared seed
  const createdFrame = await bSock.waitFor('game_created');
  assert.deepEqual(createdFrame.payload.game, game);

  // Moves before the game is active are rejected.
  assert.equal((await b.api.post(`/api/games/${game.id}/move`, { json: { data: { answer: 1 } } })).status, 409);

  const joined = await b.api.post(`/api/games/${game.id}/join`, { json: {} });
  assert.equal(joined.status, 200);
  assert.equal(joined.body.game.state, 'active');
  await aSock.waitFor('game_started');
  await bSock.waitFor('game_started');

  // Accepted moves are relayed couple-wide.
  const move = await a.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'answer', round: 0, value: 'B' } },
  });
  assert.equal(move.status, 201);
  assert.equal(move.body.move.memberId, a.memberId);
  const moveFrame = await bSock.waitFor('game_move');
  assert.equal(moveFrame.payload.gameId, game.id);
  assert.deepEqual(moveFrame.payload.move, move.body.move);
  await aSock.waitFor('game_move');

  // Free-form client results cannot end an incomplete game.
  const forged = await b.api.post(`/api/games/${game.id}/end`, {
    json: { result: { winner: b.memberId, score: '999:0' } },
  });
  assert.equal(forged.status, 409);

  await b.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'answer', round: 0, value: 'A' } },
  });
  const ordered = [a.memberId, b.memberId].sort();
  const subject = ordered[0] === a.memberId ? a : b;
  const completed = await subject.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'verdict', round: 0, value: 'right' } },
  });
  assert.equal(completed.status, 201);
  assert.equal(completed.body.game.state, 'ended');
  assert.deepEqual(completed.body.game.result, {
    scores: { [ordered[0]]: 0, [ordered[1]]: 1 },
  });
  assert.equal(completed.body.game.moves.length, 3);
  const endedFrame = await aSock.waitFor('game_ended');
  assert.deepEqual(endedFrame.payload.game.result, completed.body.game.result);

  assert.equal((await a.api.get('/api/games/active')).body.game, null);
});

test('only a creator may replace their own untouched same-type lobby', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  const g1 = (await a.api.post('/api/games', { json: { type: 'thisorthat' } })).body.game;
  let active = await b.api.get('/api/games/active');
  assert.equal(active.body.game.id, g1.id);

  assert.equal((await b.api.post('/api/games', { json: { type: 'thisorthat' } })).status, 409);
  const g2 = (await a.api.post('/api/games', { json: { type: 'thisorthat' } })).body.game;
  active = await a.api.get('/api/games/active');
  assert.equal(active.body.game.id, g2.id);

  // g1 was cancelled by its creator; the creator may also cancel g2.
  assert.equal((await a.api.get(`/api/games/${g1.id}`)).body.game.state, 'ended');
  assert.equal((await a.api.post(`/api/games/${g2.id}/end`, { json: {} })).status, 200);
  active = await a.api.get('/api/games/active');
  assert.equal(active.body.game, null);
  assert.equal((await a.api.post(`/api/games/${g1.id}/join`, { json: {} })).status, 409);
});

test('invited partner may decline a lobby; creator cancel stays distinct', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  await aSock.waitFor('welcome');

  // B declines A's invitation → ended with decline attribution (28#5).
  const invited = (await a.api.post('/api/games', { json: { type: 'quiz' } })).body.game;
  const declined = await b.api.post(`/api/games/${invited.id}/end`, { json: {} });
  assert.equal(declined.status, 200);
  assert.equal(declined.body.game.state, 'ended');
  assert.deepEqual(declined.body.game.result, { declined: true, by: b.memberId });
  const endedFrame = await aSock.waitFor('game_ended');
  assert.deepEqual(endedFrame.payload.game.result, { declined: true, by: b.memberId });

  // The creator's own lobby end keeps the classic cancel result.
  const mine = (await a.api.post('/api/games', { json: { type: 'quiz' } })).body.game;
  const cancelled = await a.api.post(`/api/games/${mine.id}/end`, { json: {} });
  assert.deepEqual(cancelled.body.game.result, { cancelled: true, by: a.memberId });

  // Declining frees the open-session slot for a fresh invitation.
  assert.equal((await b.api.post('/api/games', { json: { type: 'quiz' } })).status, 201);
});

test('game validation: unknown type / unknown id', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  assert.equal((await a.api.post('/api/games', { json: { type: 'chess' } })).status, 400);
  assert.equal((await a.api.post('/api/games/g_nope/join', { json: {} })).status, 404);
  assert.equal((await a.api.post('/api/games/g_nope/move', { json: { data: {} } })).status, 404);
});

test('games list: newest first with result/state/type and cursor pagination', async (t) => {
  // This test exercises storage pagination rather than production throttling.
  const { baseUrl } = await makeApp(t, { rateLimiter: new RateLimiter({ policies: {} }) });
  const { a } = await setupCouple(baseUrl);

  assert.deepEqual((await a.api.get('/api/games')).body, {
    games: [],
    nextCursor: null,
    total: 0,
  });

  const ids = [];
  for (let i = 0; i < 35; i++) {
    const game = (
      await a.api.post('/api/games', {
        json: { type: 'quiz', payload: { rounds: (i % 12) + 1 } },
      })
    ).body.game;
    ids.push(game.id);
  }
  // The creator cancels the newest lobby; prior lobbies were server-cancelled
  // when their creator replaced them.
  assert.equal((await a.api.post(`/api/games/${ids[34]}/end`, { json: {} })).status, 200);

  const firstResponse = (await a.api.get('/api/games')).body;
  const page = firstResponse.games;
  assert.equal(page.length, 30); // default limit
  assert.equal(firstResponse.nextCursor, '30');
  assert.equal(firstResponse.total, 35);
  assert.equal(page[0].id, ids[34]); // newest first
  assert.equal(page[0].type, 'quiz');
  assert.equal(page[0].state, 'ended');
  assert.deepEqual(page[0].result, { cancelled: true, by: a.memberId });
  assert.equal(page[0].payload.rounds, 11);
  assert.equal(page[29].id, ids[5]);
  assert.deepEqual(page[1].result, { cancelled: true, replacedBy: a.memberId });

  const two = (await a.api.get('/api/games?limit=2')).body.games;
  assert.deepEqual(two.map((g) => g.id), [ids[34], ids[33]]);

  const second = (await a.api.get('/api/games?cursor=30')).body;
  assert.deepEqual(second.games.map((game) => game.id), ids.slice(0, 5).reverse());
  assert.equal(second.nextCursor, null);

  // limit is clamped to 1..200 (no 400s), so huge values return everything stored.
  const all = (await a.api.get('/api/games?limit=1000')).body.games;
  assert.equal(all.length, 35);
});

test('emojiriddle is an accepted game type', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  const res = await a.api.post('/api/games', { json: { type: 'emojiriddle', payload: { riddleId: 7 } } });
  assert.equal(res.status, 201);
  assert.equal(res.body.game.type, 'emojiriddle');
  assert.equal((await a.api.get('/api/games?limit=1')).body.games[0].type, 'emojiriddle');
});
