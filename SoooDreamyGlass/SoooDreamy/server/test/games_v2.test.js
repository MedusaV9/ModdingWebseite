import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple, wsOpen } from './helpers.js';

// v2.0 realtime game compatibility on the v4 authoritative protocol.

test('connect four: valid drops relay and the server persists the winner', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const created = await a.api.post('/api/games', {
    json: { type: 'connectfour', payload: { seed: 42 } },
  });
  assert.equal(created.status, 201);
  assert.equal(created.body.game.type, 'connectfour');
  assert.equal(created.body.game.state, 'lobby');
  await bSock.waitFor('game_created');

  const joined = await b.api.post(`/api/games/${created.body.game.id}/join`);
  assert.equal(joined.body.game.state, 'active');
  await bSock.waitFor('game_started');

  // Alternating column drops are validated and resolved by the server.
  const drops = [
    [a, 3], [b, 4], [a, 3], [b, 4], [a, 3], [b, 4], [a, 3],
  ];
  for (const [who, col] of drops) {
    const res = await who.api.post(`/api/games/${created.body.game.id}/move`, {
      json: { data: { kind: 'drop', column: col } },
    });
    assert.equal(res.status, 201);
    assert.equal(res.body.move.data.column, col);
  }
  for (let i = 0; i < drops.length; i++) await bSock.waitFor('game_move');

  // The final drop already ended the game. A later forged result is ignored.
  const ended = await a.api.post(`/api/games/${created.body.game.id}/end`, {
    json: { result: { winner: b.memberId, reason: 'forged' } },
  });
  assert.equal(ended.body.game.state, 'ended');
  assert.equal(ended.body.game.result.winner, a.memberId);
  assert.equal(ended.body.game.result.draw, false);

  const history = await b.api.get('/api/games?limit=1');
  assert.equal(history.body.games[0].type, 'connectfour');
  assert.equal(history.body.games[0].moves.length, 7);
});

test('photo memory: payload keeps only authenticated couple photo ids', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const photoIds = [];
  for (let index = 0; index < 8; index += 1) {
    const uploaded = await a.api.post('/api/photos', {
      body: Buffer.from(`photo-${index}`),
      headers: { 'content-type': 'image/jpeg' },
    });
    photoIds.push(uploaded.body.photo.id);
  }
  const created = await a.api.post('/api/games', {
    json: { type: 'photomemory', payload: { seed: 7, photoIds } },
  });
  assert.equal(created.status, 201);
  assert.deepEqual(created.body.game.payload.photoIds, photoIds);

  // The partner reads the same payload back (deck derivation must match).
  // v3.0.1: the seed is server-generated (client seeds are discarded), but
  // both members see the identical value.
  const active = await b.api.get('/api/games/active');
  assert.deepEqual(active.body.game.payload.photoIds, photoIds);
  assert.equal(active.body.game.payload.seed, created.body.game.payload.seed);
  assert.ok(Number.isInteger(active.body.game.payload.seed));
});

test('quiz duel: buzzer moves keep server arrival order', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const created = await a.api.post('/api/games', {
    json: { type: 'quizduel', payload: { seed: 99, rounds: 5 } },
  });
  await b.api.post(`/api/games/${created.body.game.id}/join`);

  // b buzzes first, then a — order in the stored move list must match.
  await b.api.post(`/api/games/${created.body.game.id}/move`, {
    json: { data: { kind: 'answer', round: 0, option: 2 } },
  });
  await a.api.post(`/api/games/${created.body.game.id}/move`, {
    json: { data: { kind: 'answer', round: 0, option: 2 } },
  });

  const active = await a.api.get('/api/games/active');
  const moves = active.body.game.moves;
  assert.equal(moves.length, 2);
  assert.equal(moves[0].memberId, b.memberId);
  assert.equal(moves[1].memberId, a.memberId);
  assert.ok(moves[0].createdAt <= moves[1].createdAt);
});

test('unknown game type is still rejected', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  const res = await a.api.post('/api/games', { json: { type: 'chess' } });
  assert.equal(res.status, 400);
  assert.equal(res.body.error, 'invalid_type');
});

test('an active v2 game must be resolved before creating the same type', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const first = await a.api.post('/api/games', {
    json: { type: 'connectfour', payload: { seed: 1 } },
  });
  await b.api.post(`/api/games/${first.body.game.id}/join`);
  const conflict = await a.api.post('/api/games', {
    json: { type: 'connectfour', payload: { seed: 2 } },
  });
  assert.equal(conflict.status, 409);

  assert.equal((await b.api.post(`/api/games/${first.body.game.id}/end`, {
    json: { forfeit: true },
  })).status, 200);
  const second = await a.api.post('/api/games', {
    json: { type: 'connectfour', payload: { seed: 2 } },
  });
  assert.equal(second.status, 201);

  const active = await b.api.get('/api/games/active');
  assert.equal(active.body.game.id, second.body.game.id);
  const history = await a.api.get('/api/games?limit=5');
  const old = history.body.games.find((g) => g.id === first.body.game.id);
  assert.equal(old.state, 'ended');
});
