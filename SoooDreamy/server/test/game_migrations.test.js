import assert from 'node:assert/strict';
import test from 'node:test';
import { CURRENT_GAME_RULES_VERSION, migrateGameStore } from '../src/game-migrations.js';

function fixture(games) {
  let dirty = 0;
  const couple = {
    id: 'couple-migration',
    members: [{ id: 'member-a' }, { id: 'member-b' }],
    photos: [],
    games,
  };
  return {
    couple,
    store: {
      data: { couples: { [couple.id]: couple } },
      markDirty() { dirty += 1; },
    },
    dirtyCount: () => dirty,
  };
}

function move(id, memberId, data, second) {
  return {
    id,
    memberId,
    data,
    createdAt: `2026-08-10T05:00:0${second}.000Z`,
  };
}

test('migration replays valid open history and replaces a forged result canonically', () => {
  const game = {
    id: 'valid-old-game',
    type: 'movieroulette',
    state: 'active',
    createdBy: 'member-a',
    payload: { size: 1, custom: ['Us'], seed: 42, seedServer: true },
    result: { matches: 999, winner: 'attacker' },
    moves: [
      move('move-a', 'member-a', { kind: 'swipe', index: 0, like: true }, 1),
      move('move-b', 'member-b', { kind: 'swipe', index: 0, like: true }, 2),
    ],
  };
  const { store, dirtyCount } = fixture([game]);

  const report = migrateGameStore({ store });

  assert.deepEqual(report, { upgraded: 1, invalidated: 0, legacyEnded: 0, aggregatesSeeded: 1 });
  assert.equal(game.rulesVersion, CURRENT_GAME_RULES_VERSION);
  assert.equal(game.resultAuthority, 'server');
  assert.equal(game.state, 'ended');
  assert.deepEqual(game.result, { matchIndexes: [0], matches: 1 });
  assert.equal(dirtyCount(), 1);
});

test('migration never skips an unknown historic move to authorize continuation', () => {
  const game = {
    id: 'unknown-old-move',
    type: 'movieroulette',
    state: 'active',
    createdBy: 'member-a',
    payload: { size: 2, custom: [], seed: 43, seedServer: true },
    result: null,
    moves: [
      move('move-a', 'member-a', { kind: 'future_move', index: 0, like: true }, 1),
    ],
  };
  const { store } = fixture([game]);

  const report = migrateGameStore({ store });

  assert.equal(report.invalidated, 1);
  assert.equal(game.state, 'ended');
  assert.equal(game.resultAuthority, 'server-migration');
  assert.equal(game.result.invalidated, true);
  assert.equal(game.result.reason, 'rules_migration');
  assert.match(game.result.detail, /Movie roulette only accepts swipe actions/);
});

test('untouched lobbies are safely normalized, while ended legacy results stay labelled', () => {
  const lobby = {
    id: 'old-lobby',
    type: 'quiz',
    state: 'lobby',
    createdBy: 'member-a',
    payload: { rounds: 8, seed: 1 },
    result: null,
    moves: [],
  };
  const ended = {
    id: 'old-history',
    type: 'quiz',
    state: 'ended',
    createdBy: 'member-a',
    payload: { rounds: 2, seed: 2 },
    result: { scores: { 'member-a': 50, 'member-b': 0 } },
    moves: [],
  };
  const originalLegacyResult = structuredClone(ended.result);
  const { store } = fixture([lobby, ended]);

  const report = migrateGameStore({ store });

  assert.deepEqual(report, { upgraded: 1, invalidated: 0, legacyEnded: 1, aggregatesSeeded: 1 });
  assert.equal(lobby.rulesVersion, CURRENT_GAME_RULES_VERSION);
  assert.equal(lobby.payload.rounds, 8);
  assert.equal(lobby.payload.seedServer, true);
  assert.notEqual(lobby.payload.seed, 1);
  assert.equal(ended.rulesVersion, 3);
  assert.equal(ended.resultAuthority, 'legacy-client');
  assert.deepEqual(ended.result, originalLegacyResult);
});

test('first run seeds gamesAggregate from played history only, exactly once', () => {
  const played = {
    id: 'seed-played',
    type: 'quiz',
    state: 'ended',
    createdBy: 'member-a',
    rulesVersion: 3,
    resultAuthority: 'legacy-client',
    payload: { rounds: 1, seed: 5 },
    result: { scores: { 'member-a': 50, 'member-b': 0 } },
    moves: [],
  };
  const cancelled = {
    id: 'seed-cancelled',
    type: 'thisorthat',
    state: 'ended',
    createdBy: 'member-a',
    rulesVersion: 3,
    resultAuthority: 'legacy-client',
    payload: {},
    result: { cancelled: true, by: 'member-a' },
    moves: [],
  };
  const { couple, store } = fixture([played, cancelled]);

  const report = migrateGameStore({ store });
  assert.equal(report.aggregatesSeeded, 1);
  // The one shared isPlayedGame rule: the cancelled lobby stays out.
  assert.deepEqual(couple.gamesAggregate, { total: 1, perKind: { quiz: 1 } });

  // Second boot: the aggregate already exists — never re-seeded (a re-seed
  // from a LIMITS.games-capped list would erase evicted games from total).
  couple.gamesAggregate.total = 999;
  const second = migrateGameStore({ store });
  assert.equal(second.aggregatesSeeded, 0);
  assert.equal(couple.gamesAggregate.total, 999);
});

test('migration on a seeded store counts ended played sessions forward (Fix-Runde 3)', () => {
  // A RULES-version bump AFTER the first aggregate seed: every session the
  // migration ends must be written forward into the existing aggregate —
  // flipping `state='ended'` past it would silently undercount (the seed
  // only runs once). recordGameEnd is not reused: no legacy counter bump.
  const completed = {
    id: 'bump-completed',
    type: 'movieroulette',
    state: 'active',
    createdBy: 'member-a',
    payload: { size: 1, custom: ['Us'], seed: 42, seedServer: true },
    result: null,
    moves: [
      move('move-a', 'member-a', { kind: 'swipe', index: 0, like: true }, 1),
      move('move-b', 'member-b', { kind: 'swipe', index: 0, like: true }, 2),
    ],
  };
  const invalidatedWithMoves = {
    id: 'bump-invalidated-moves',
    type: 'kniffel',
    state: 'active',
    createdBy: 'member-a',
    payload: { seed: 7 }, // client seed + moves → invalidated
    result: null,
    moves: [move('roll', 'member-a', { kind: 'roll', held: [] }, 1)],
  };
  const invalidatedZeroMoves = {
    id: 'bump-invalidated-empty',
    type: 'futuregame', // unknown type, never played a move
    state: 'lobby',
    createdBy: 'member-a',
    payload: {},
    result: null,
    moves: [],
  };
  const { couple, store } = fixture([completed, invalidatedWithMoves, invalidatedZeroMoves]);
  couple.gamesAggregate = { total: 5, perKind: { quiz: 5 } };
  const counters = structuredClone(couple.counters ?? {});

  const report = migrateGameStore({ store });

  assert.equal(report.aggregatesSeeded, 0); // existing aggregate, no re-seed
  assert.equal(completed.state, 'ended');
  assert.equal(invalidatedWithMoves.result.invalidated, true);
  assert.equal(invalidatedZeroMoves.result.invalidated, true);
  // Forward-counted: the replay-completed roulette and the invalidated
  // session WITH real moves. The zero-move invalidation is administrative
  // noise (isPlayedGame) and stays out — no phantom Partie.
  assert.deepEqual(couple.gamesAggregate, {
    total: 7,
    perKind: { quiz: 5, movieroulette: 1, kniffel: 1 },
  });
  // No legacy side effects: counters untouched (migration ≠ play).
  assert.deepEqual(couple.counters ?? {}, counters);
});

test('moved history with a client-controlled seed is invalidated, not re-seeded', () => {
  const game = {
    id: 'untrusted-seed',
    type: 'kniffel',
    state: 'active',
    createdBy: 'member-a',
    payload: { seed: 7 },
    result: null,
    moves: [move('roll', 'member-a', { kind: 'roll', held: [] }, 1)],
  };
  const { store } = fixture([game]);

  migrateGameStore({ store });

  assert.equal(game.state, 'ended');
  assert.equal(game.result.invalidated, true);
  assert.match(game.result.detail, /trustworthy server seed/);
});
