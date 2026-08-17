import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { makeApp, setupCouple, client } from './helpers.js';
import { RateLimiter } from '../src/security.js';
import {
  GAMES_LIST_LIMIT,
  isPlayedGame,
  recordGameEnd,
  seededGamesAggregate,
} from '../src/game-rules.js';

// GET /api/games/stats — aggregated biography numbers (Spieltisch eval S2;
// re-eval 2 Befunde 8 + 9): every number counts PLAYED games only (the one
// shared `isPlayedGame` rule — cancelled/declined lobbies are out), and
// total/perKind come from the persistent `couple.gamesAggregate` so
// `capList(couple.games, LIMITS.games)` eviction can never shrink them.

// --- the pure rule (Befund 8), pinned directly -----------------------------

test('isPlayedGame: ended with moves or a real result; cancelled/declined out', () => {
  // Not ended yet — invisible regardless of content.
  assert.equal(isPlayedGame({ state: 'lobby', moves: [], result: null }), false);
  assert.equal(isPlayedGame({ state: 'active', moves: [{}], result: null }), false);
  // Ended with recorded moves — played, even without a result object.
  assert.equal(isPlayedGame({ state: 'ended', moves: [{}], result: null }), true);
  // Ended without moves but with a real result (e.g. questions36 completion).
  assert.equal(isPlayedGame({ state: 'ended', moves: [], result: { completedBy: 'm1' } }), true);
  // Administrative ends: cancelled/declined lobbies are NOT partie.
  assert.equal(isPlayedGame({ state: 'ended', moves: [], result: { cancelled: true, by: 'm1' } }), false);
  assert.equal(isPlayedGame({ state: 'ended', moves: [], result: { declined: true, by: 'm2' } }), false);
  // Ended with neither moves nor result — nothing was played.
  assert.equal(isPlayedGame({ state: 'ended', moves: [], result: null }), false);
});

test('isPlayedGame: zero-move invalidations and empty results are administrative (Fix-Runde 3)', () => {
  // The migration invalidated a lobby that never saw a move — noise.
  assert.equal(isPlayedGame({
    state: 'ended',
    moves: [],
    result: { invalidated: true, reason: 'rules_migration', detail: 'x' },
  }), false);
  // Invalidated AFTER real play: the moves prove the Partie — counted.
  assert.equal(isPlayedGame({
    state: 'ended',
    moves: [{}],
    result: { invalidated: true, reason: 'rules_migration', detail: 'x' },
  }), true);
  // An empty `{}` result without moves carries no outcome — not played.
  assert.equal(isPlayedGame({ state: 'ended', moves: [], result: {} }), false);
  // Missing moves array (corrupt legacy entry): the result decides alone.
  assert.equal(isPlayedGame({ state: 'ended', result: { completedBy: 'm1' } }), true);
  assert.equal(isPlayedGame({ state: 'ended', result: {} }), false);
});

test('seededGamesAggregate: a seed from a capped list is marked as a lower bound', () => {
  const playedGame = (i) => ({
    id: `g${i}`,
    type: 'quiz',
    state: 'ended',
    moves: [],
    result: { scores: { a: 1, b: 0 } },
  });
  // UNDER the cap: the seed saw the whole life — a true total, no mark.
  const under = { games: Array.from({ length: GAMES_LIST_LIMIT - 1 }, (_, i) => playedGame(i)) };
  assert.deepEqual(seededGamesAggregate(under), {
    total: GAMES_LIST_LIMIT - 1,
    perKind: { quiz: GAMES_LIST_LIMIT - 1 },
  });
  // AT the cap: eviction may already have eaten history — honest floor.
  const capped = { games: Array.from({ length: GAMES_LIST_LIMIT }, (_, i) => playedGame(i)) };
  const seeded = seededGamesAggregate(capped);
  assert.equal(seeded.seededFromCapped, true);
  assert.equal(seeded.total, GAMES_LIST_LIMIT);
});

test('recordGameEnd: writes the aggregate forward once, idempotently', () => {
  const couple = { counters: { gamesPlayed: 0 }, games: [] };
  const played = { type: 'quiz', state: 'active', moves: [{}], result: { scores: { a: 1, b: 0 } } };
  const noise = { type: 'thisorthat', state: 'lobby', moves: [], result: { declined: true } };
  couple.games.push(played, noise);

  recordGameEnd(couple, played);
  recordGameEnd(couple, played); // already ended — never double-counts
  recordGameEnd(couple, noise);

  assert.deepEqual(couple.gamesAggregate, { total: 1, perKind: { quiz: 1 } });
  assert.equal(couple.counters.gamesPlayed, 1); // legacy counter: active ends only
  assert.equal(played.state, 'ended');
  assert.equal(noise.state, 'ended');
  // Seeding from the same list agrees with the forward-written aggregate.
  assert.deepEqual(seededGamesAggregate(couple), couple.gamesAggregate);
});

// --- the endpoint -----------------------------------------------------------

test('games stats: requires auth like its neighbors', async (t) => {
  const { baseUrl } = await makeApp(t);
  const anon = client(baseUrl);
  assert.equal((await anon.get('/api/games/stats')).status, 401);
});

test('games stats: empty store yields all-zero aggregate', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  assert.deepEqual((await a.api.get('/api/games/stats')).body, {
    total: 0,
    perKind: {},
    lowerBound: false,
    decided: 0,
    draws: 0,
    replayable: 0,
  });
});

/** Plays one full quiz to its canonical end. Every round: both answer,
 *  then the round subject (members[round % 2], sorted ids) judges with
 *  the given verdict — 'right' scores for the OTHER member. */
async function playQuiz(a, b, verdicts) {
  const game = (
    await a.api.post('/api/games', { json: { type: 'quiz', payload: { rounds: verdicts.length } } })
  ).body.game;
  assert.equal((await b.api.post(`/api/games/${game.id}/join`, { json: {} })).status, 200);
  const ordered = [a.memberId, b.memberId].sort();
  const byId = (id) => (id === a.memberId ? a : b);
  for (let round = 0; round < verdicts.length; round++) {
    for (const player of [a, b]) {
      const answered = await player.api.post(`/api/games/${game.id}/move`, {
        json: { data: { kind: 'answer', round, value: `answer ${round}` } },
      });
      assert.equal(answered.status, 201);
    }
    const judged = await byId(ordered[round % 2]).api.post(`/api/games/${game.id}/move`, {
      json: { data: { kind: 'verdict', round, value: verdicts[round] } },
    });
    assert.equal(judged.status, 201);
  }
  return game;
}

test('games stats: cancelled and declined lobbies never inflate the numbers', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  // One decided quiz (0:1) and one drawn quiz (1:1 — round 0 scores for
  // members[1], round 1 for members[0]).
  await playQuiz(a, b, ['right']);
  await playQuiz(a, b, ['right', 'right']);
  // A declined lobby (partner passes) and a cancelled lobby (creator gives
  // up): both END the session but neither was ever PLAYED — they must not
  // appear anywhere in the biography numbers.
  const passed = (await a.api.post('/api/games', { json: { type: 'thisorthat' } })).body.game;
  assert.equal((await b.api.post(`/api/games/${passed.id}/end`, { json: {} })).status, 200);
  const regretted = (await a.api.post('/api/games', { json: { type: 'thisorthat' } })).body.game;
  assert.equal((await a.api.post(`/api/games/${regretted.id}/end`, { json: {} })).status, 200);
  // One still-open lobby: not ended, so entirely invisible to the stats.
  assert.equal((await a.api.post('/api/games', { json: { type: 'quiz' } })).status, 201);

  const stats = (await a.api.get('/api/games/stats')).body;
  assert.deepEqual(stats, {
    total: 2,
    perKind: { quiz: 2 },
    lowerBound: false,
    decided: 1,
    draws: 1,
    replayable: 2,
  });

  // Both partners read the same couple-wide aggregate.
  assert.deepEqual((await b.api.get('/api/games/stats')).body, stats);
});

test('games stats: match-verdict games count like the Bilanz page lists them (R5)', async (t) => {
  const app = await makeApp(t);
  const { a, b, coupleId } = await setupCouple(app.baseUrl);

  // A finished match game stores result.matches/rounds instead of
  // scores — the Bilanz page LISTS it, so decided/draws must count it.
  // The end route rightly refuses free-form results (409), so the two
  // server-authored match verdicts are laid into the store directly
  // (eviction-test pattern). Decided analog: unequal halves (2 of 3);
  // draw analog: the exact half (2 of 4).
  const couple = app.app.store.data.couples[coupleId];
  const matchGame = (id, matches, rounds, minutesAgo) => ({
    id,
    type: 'thisorthat',
    state: 'ended',
    createdBy: a.memberId,
    payload: {},
    result: { matches, rounds },
    moves: [],
    rulesVersion: 5,
    resultAuthority: 'server',
    createdAt: new Date(Date.now() - minutesAgo * 60_000).toISOString(),
  });
  couple.games.push(matchGame('match_won', 2, 3, 2), matchGame('match_tied', 2, 4, 1));
  delete couple.gamesAggregate;
  app.app.store.markDirty();

  const stats = (await a.api.get('/api/games/stats')).body;
  assert.equal(stats.total, 2);
  assert.equal(stats.decided, 1);
  assert.equal(stats.draws, 1);
  // Both partners read the same verdict.
  assert.deepEqual((await b.api.get('/api/games/stats')).body, stats);
});

test('games stats: 55 real completions count, interleaved aborts do not', async (t) => {
  // Storage aggregation, not production throttling (games.test.js pattern).
  const { baseUrl } = await makeApp(t, { rateLimiter: new RateLimiter({ policies: {} }) });
  const { a, b } = await setupCouple(baseUrl);

  // 55 quizzes played to their canonical end (one 'right' round each —
  // decided 0:1, with moves), plus an abort every 5th lap: alternating a
  // creator-cancelled and a partner-declined thisorthat lobby.
  for (let i = 0; i < 55; i++) {
    await playQuiz(a, b, ['right']);
    if (i % 5 === 0) {
      const lobby = (await a.api.post('/api/games', { json: { type: 'thisorthat' } })).body.game;
      const ender = i % 10 === 0 ? a : b; // cancel vs decline
      assert.equal((await ender.api.post(`/api/games/${lobby.id}/end`, { json: {} })).status, 200);
    }
  }

  const stats = (await a.api.get('/api/games/stats')).body;
  assert.deepEqual(stats, {
    total: 55,
    perKind: { quiz: 55 },
    lowerBound: false,
    decided: 55,
    draws: 0,
    replayable: 55,
  });

  // The paged list a client reads first says less — the aggregate is the
  // honest biography number (55 played + 11 aborted = 66 stored, page 50).
  assert.equal((await a.api.get('/api/games?limit=50')).body.games.length, 50);
});

// --- LIMITS.games eviction + restart persistence (Befund 9) ----------------

test('games stats: total survives LIMITS.games eviction and a server restart', async (t) => {
  const dataDir = await mkdtemp(path.join(os.tmpdir(), 'sooodreamy-games-stats-'));
  t.after(() => rm(dataDir, { recursive: true, force: true }));

  // --- first app lifetime: a long couple whose store predates aggregates ---
  const first = await makeApp(t, {
    dataDir,
    rateLimiter: new RateLimiter({ policies: {} }),
  });
  const { a, b, coupleId } = await setupCouple(first.baseUrl);
  await playQuiz(a, b, ['right']);
  await playQuiz(a, b, ['right']);

  // Simulate the store a pre-aggregate server wrote: LIMITS.games (1000)
  // legacy played sessions in front of the two real quizzes, and no
  // `gamesAggregate` yet — the endpoint's lazy seed must count all 1002.
  const couple = first.app.store.data.couples[coupleId];
  const legacy = Array.from({ length: 1000 }, (_, i) => ({
    id: `legacy_g${i}`,
    type: 'thisorthat',
    state: 'ended',
    createdBy: a.memberId,
    payload: {},
    result: { scores: { [a.memberId]: 1, [b.memberId]: 0 } },
    moves: [],
    rulesVersion: 5,
    resultAuthority: 'server',
    createdAt: new Date(Date.now() - (1000 - i) * 60_000).toISOString(),
  }));
  couple.games.splice(0, 0, ...legacy);
  delete couple.gamesAggregate;
  first.app.store.markDirty();

  // Lazy seed over a list AT the cap: the totals are honest FLOORS now
  // (evicted history is unprovable) — the endpoint says so.
  const seededStats = (await a.api.get('/api/games/stats')).body;
  assert.equal(seededStats.total, 1002);
  assert.equal(seededStats.lowerBound, true);

  // One more played quiz pushes the list PAST the cap: creating it evicts
  // the oldest legacy sessions (capList → exactly 1000 stored), yet the
  // aggregate keeps counting forward — 1003, not the list's 1000.
  await playQuiz(a, b, ['right']);
  const stats = (await a.api.get('/api/games/stats')).body;
  assert.equal(stats.total, 1003);
  assert.deepEqual(stats.perKind, { quiz: 3, thisorthat: 1000 });
  assert.equal(stats.lowerBound, true); // the capped-seed mark sticks
  assert.equal((await a.api.get('/api/games?limit=1')).body.total, 1000);

  await first.close(); // flush-on-close (persistence.test.js contract)

  // --- second app lifetime: same DATA_DIR ---
  // A reboot must read the PERSISTED aggregate; re-seeding from the capped
  // list would collapse total back to 1000 and silently erase the evicted
  // games from the couple's biography.
  const second = await makeApp(t, { dataDir });
  const aApi = client(second.baseUrl, a.token);
  const revived = (await aApi.get('/api/games/stats')).body;
  assert.equal(revived.total, 1003);
  assert.deepEqual(revived.perKind, { quiz: 3, thisorthat: 1000 });
  assert.equal(revived.lowerBound, true); // persisted with the aggregate
});
