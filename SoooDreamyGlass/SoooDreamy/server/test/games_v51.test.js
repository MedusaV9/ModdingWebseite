import { test } from 'node:test';
import assert from 'node:assert/strict';
import { emitAppEvent } from '../src/events.js';
import { BINGO_ACTIONS } from '../src/game-content-v51.js';
import { makeApp, setupCouple } from './helpers.js';

async function startGame(a, b, type, payload = {}) {
  const created = await a.api.post('/api/games', { json: { type, payload } });
  assert.equal(created.status, 201, JSON.stringify(created.body));
  const joined = await b.api.post(`/api/games/${created.body.game.id}/join`, { json: {} });
  assert.equal(joined.status, 200, JSON.stringify(joined.body));
  return joined.body.game;
}

test('wordchain is daily, dictionary-backed, and server-authoritative', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'wordchain', { lang: 'en' });
  assert.match(game.payload.dateKey, /^\d{4}-\d{2}-\d{2}$/);

  const unknown = await a.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'word', index: 0, text: 'Zorgle' } },
  });
  assert.equal(unknown.status, 409);
  assert.equal(unknown.body.error, 'unknown_word');

  assert.equal((await a.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'word', index: 0, text: 'Heart' } },
  })).status, 201);
  assert.equal((await b.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'word', index: 1, text: 'Tree' } },
  })).status, 201);
});

test('weekly bingo checks only canonical app events and ends on a line', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a, b, coupleId } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'bingo');
  assert.equal(game.payload.cardIndexes.length, 16);
  assert.equal(new Set(game.payload.cardIndexes).size, 16);

  const forged = await a.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'auto_check', cardIndex: 0 } },
  });
  assert.equal(forged.status, 409);
  assert.equal(forged.body.error, 'auto_checked_only');

  const couple = app.store.data.couples[coupleId];
  const firstRow = game.payload.cardIndexes.slice(0, 4);
  for (const [index, actionIndex] of firstRow.entries()) {
    const action = BINGO_ACTIONS[actionIndex];
    emitAppEvent({
      store: app.store,
      realtime: app.realtime,
      couple,
      type: action.eventType,
      memberId: index % 2 === 0 ? a.memberId : b.memberId,
      data: { test: true },
      dedupeKey: `bingo-test-${index}`,
    });
  }

  const completed = (await a.api.get(`/api/games/${game.id}`)).body.game;
  assert.equal(completed.state, 'ended');
  assert.equal(completed.result.bingo, true);
  assert.deepEqual(completed.result.line, [0, 1, 2, 3]);
  assert.equal(completed.moves.length, 4);
  assert.ok(completed.moves.every((move) => move.data.kind === 'auto_check'));
  assert.equal(completed.result.scores[a.memberId], 1);
  assert.equal(completed.result.scores[b.memberId], 1);
});
