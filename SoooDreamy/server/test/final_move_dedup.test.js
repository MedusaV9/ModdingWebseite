// Sync contract b (FX-S) — the clientMoveId duplicate search runs BEFORE the
// game-state check in POST /api/games/:id/move. The eval battery's repro: the
// response of a WINNING Gomoku stone gets lost, the client retries — the game
// is 'ended' by then, and the old order answered 409 game_not_active instead
// of the stored duplicate. The duplicate answer is 200 {duplicate:true, move,
// game} (the serialized game rides along so the retrying client converges on
// the final state in one round trip).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple } from './helpers.js';

async function startGame(a, b, type) {
  const created = await a.api.post('/api/games', { json: { type } });
  assert.equal(created.status, 201, JSON.stringify(created.body));
  const joined = await b.api.post(`/api/games/${created.body.game.id}/join`, { json: {} });
  assert.equal(joined.status, 200, JSON.stringify(joined.body));
  return joined.body.game;
}

async function move(who, gameId, data, clientMoveId) {
  return who.api.post(`/api/games/${gameId}/move`, {
    json: { data, ...(clientMoveId ? { clientMoveId } : {}) },
  });
}

/** Plays Gomoku up to A's match point: A holds 0..3, B holds 100..103. */
async function playToMatchPoint(a, b, gameId) {
  const script = [
    ['a', 0], ['b', 100], ['a', 1], ['b', 101], ['a', 2], ['b', 102],
    ['a', 3], ['b', 103],
  ];
  const who = { a, b };
  for (const [player, index] of script) {
    const res = await move(who[player], gameId, { kind: 'place', index });
    assert.equal(res.status, 201, JSON.stringify(res.body));
  }
}

test('EVAL repro: retrying the WINNING Gomoku move returns the duplicate, not 409 game_not_active', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'gomoku');
  await playToMatchPoint(a, b, game.id);

  // The winning stone (fifth in a row) — sent with a stable clientMoveId.
  const winning = await move(a, game.id, { kind: 'place', index: 4 }, 'win-stone');
  assert.equal(winning.status, 201);
  assert.equal(winning.body.game.state, 'ended');
  assert.equal(winning.body.game.result.winner, a.memberId);

  // The response got lost — the outbox retries the SAME move on the now-ended
  // game. Before the fix this bounced with 409 game_not_active.
  const retry = await move(a, game.id, { kind: 'place', index: 4 }, 'win-stone');
  assert.equal(retry.status, 200, JSON.stringify(retry.body));
  assert.equal(retry.body.duplicate, true);
  assert.deepEqual(retry.body.move, winning.body.move);
  assert.equal(retry.body.game.state, 'ended');
  assert.deepEqual(retry.body.game.result, winning.body.game.result);
  assert.equal(retry.body.game.turnMemberId, null, 'ended games have no turn');

  // The move list did NOT grow — the retry stored nothing.
  const fetched = await a.api.get(`/api/games/${game.id}`);
  assert.equal(fetched.body.game.moves.length, 9);
});

test('a genuinely NEW move on the ended game still refuses with game_not_active', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'gomoku');
  await playToMatchPoint(a, b, game.id);
  assert.equal((await move(a, game.id, { kind: 'place', index: 4 }, 'win-stone')).status, 201);

  const late = await move(b, game.id, { kind: 'place', index: 104 }, 'late-stone');
  assert.equal(late.status, 409);
  assert.equal(late.body.error, 'game_not_active');
});

test('the dedup is per member: the partner reusing the id is not a duplicate', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'gomoku');

  assert.equal((await move(a, game.id, { kind: 'place', index: 0 }, 'shared-id')).status, 201);
  // Same clientMoveId, OTHER member: a real move, not a duplicate replay.
  const other = await move(b, game.id, { kind: 'place', index: 100 }, 'shared-id');
  assert.equal(other.status, 201);
  assert.equal(other.body.duplicate, undefined);
});

test('duplicate on a still-active game also answers 200 {duplicate, move, game}', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'gomoku');

  const first = await move(a, game.id, { kind: 'place', index: 7 }, 'mid-game');
  assert.equal(first.status, 201);
  const retry = await move(a, game.id, { kind: 'place', index: 7 }, 'mid-game');
  assert.equal(retry.status, 200);
  assert.equal(retry.body.duplicate, true);
  assert.deepEqual(retry.body.move, first.body.move);
  assert.equal(retry.body.game.state, 'active');
  assert.equal(retry.body.game.turnMemberId, b.memberId, 'the stored move already passed the turn');
});
