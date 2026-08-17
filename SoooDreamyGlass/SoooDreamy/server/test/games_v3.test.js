import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { makeApp, setupCouple, wsOpen } from './helpers.js';
import { gameRulesInternals } from '../src/game-rules.js';

const sha256 = (text) => createHash('sha256').update(text, 'utf8').digest('hex');

// ---------------------------------------------------------------------------
// v3.0 infra a — parallel sessions

test('parallel sessions: different game types stay open side by side', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  const ship = (await a.api.post('/api/games', { json: { type: 'battleship' } })).body.game;
  const dice = (await b.api.post('/api/games', { json: { type: 'kniffel' } })).body.game;
  const draw = (await a.api.post('/api/games', { json: { type: 'pictionary' } })).body.game;

  // All three are open at once — creating one no longer kills the others.
  const open = (await a.api.get('/api/games/open')).body.games;
  assert.deepEqual(open.map((g) => g.id), [draw.id, dice.id, ship.id]); // newest first
  assert.ok(open.every((g) => g.state === 'lobby'));

  // The battleship lobby is still joinable although two games were created after it.
  assert.equal((await b.api.post(`/api/games/${ship.id}/join`, { json: {} })).status, 200);

  // A member cannot replace the partner's lobby; its creator may replace it.
  assert.equal((await a.api.post('/api/games', { json: { type: 'kniffel' } })).status, 409);
  const dice2 = (await b.api.post('/api/games', { json: { type: 'kniffel' } })).body.game;
  const open2 = (await a.api.get('/api/games/open')).body.games;
  assert.deepEqual(open2.map((g) => g.id), [dice2.id, draw.id, ship.id]);
  assert.equal((await b.api.post(`/api/games/${dice.id}/join`, { json: {} })).status, 409);
});

test('GET /api/games/open is empty once everything ended; /active keeps legacy semantics', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);

  assert.deepEqual((await a.api.get('/api/games/open')).body, { games: [] });

  const g1 = (await a.api.post('/api/games', { json: { type: 'twotruths' } })).body.game;
  const g2 = (await a.api.post('/api/games', { json: { type: 'battleship' } })).body.game;

  // /active = latest open session (pre-v3.0 clients keep working).
  assert.equal((await a.api.get('/api/games/active')).body.game.id, g2.id);

  await a.api.post(`/api/games/${g2.id}/end`, { json: {} });
  assert.equal((await a.api.get('/api/games/active')).body.game.id, g1.id);
  await a.api.post(`/api/games/${g1.id}/end`, { json: {} });
  assert.deepEqual((await a.api.get('/api/games/open')).body, { games: [] });
  assert.equal((await a.api.get('/api/games/active')).body.game, null);
});

test('GET /api/games/:id fetches one session (replay/spectator); 404 for unknown ids', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = (await a.api.post('/api/games', { json: { type: 'connectfour' } })).body.game;
  await b.api.post(`/api/games/${game.id}/join`, { json: {} });
  await a.api.post(`/api/games/${game.id}/move`, { json: { data: { kind: 'drop', column: 3 } } });
  assert.equal((await a.api.post(`/api/games/${game.id}/end`, {
    json: { result: { scores: { [a.memberId]: 999 } } },
  })).status, 409);
  await a.api.post(`/api/games/${game.id}/end`, { json: { forfeit: true } });

  const fetched = (await b.api.get(`/api/games/${game.id}`)).body.game;
  assert.equal(fetched.id, game.id);
  assert.equal(fetched.state, 'ended');
  assert.equal(fetched.moves.length, 1);
  assert.equal(fetched.moves[0].data.column, 3);

  assert.equal((await a.api.get('/api/games/g_nope')).status, 404);
});

// ---------------------------------------------------------------------------
// v3.0 infra c/d — server seed + commit-reveal helper

test('the seed is ALWAYS server-generated — a client-provided seed is discarded (v3.0.1)', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  const injected = (await a.api.post('/api/games', { json: { type: 'stadtlandfluss' } })).body.game;
  assert.ok(Number.isInteger(injected.payload.seed));
  assert.ok(injected.payload.seed >= 1);

  // A client "choosing" seed 42 would know the Kniffel dice in advance —
  // the server must overwrite it (other payload options survive).
  const overwritten = (
    await a.api.post('/api/games', { json: { type: 'pictionary', payload: { seed: 42, rounds: 3 } } })
  ).body.game;
  assert.notEqual(overwritten.payload.seed, 42);
  assert.ok(Number.isInteger(overwritten.payload.seed) && overwritten.payload.seed >= 1);
  assert.equal(overwritten.payload.rounds, 3);
  assert.equal(overwritten.payload.seedServer, true);

  // The seed stays stable through join for post-3.0.1 sessions.
  const joined = (await b.api.post(`/api/games/${overwritten.id}/join`, { json: {} })).body.game;
  assert.equal(joined.payload.seed, overwritten.payload.seed);
});

test('pre-3.0.1 lobbies without the seedServer marker are re-seeded once on join (migration)', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a, b, coupleId } = await setupCouple(baseUrl);

  const game = (await a.api.post('/api/games', { json: { type: 'kniffel' } })).body.game;
  // Simulate a legacy store entry: client-chosen seed, no server marker.
  const stored = app.store.data.couples[coupleId].games.find((g) => g.id === game.id);
  stored.payload = { seed: 7 };

  const joined = (await b.api.post(`/api/games/${game.id}/join`, { json: {} })).body.game;
  assert.notEqual(joined.payload.seed, 7);
  assert.ok(Number.isInteger(joined.payload.seed) && joined.payload.seed >= 1);
  assert.equal(joined.payload.seedServer, true);
});

test('commit-reveal: relay verifies a reveal against the sender\'s latest commit', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const game = (await a.api.post('/api/games', { json: { type: 'twotruths' } })).body.game;
  await b.api.post(`/api/games/${game.id}/join`, { json: {} });

  const secret = '2';
  const salt = 'pepper🌶';
  const commit = sha256(secret + salt);
  await a.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'statements', round: 0, texts: ['A', 'B', 'C'], commit } },
  });
  await b.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'guess', round: 0, pick: 1 } },
  });

  const reveal = await a.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'reveal', round: 0, reveal: secret, salt } },
  });
  assert.equal(reveal.status, 201);
  assert.equal(reveal.body.move.data.verified, true);

  // The verified flag is broadcast to the partner as part of the move.
  const frame = await bSock.waitFor('game_move', (m) => m.payload.move.data.kind === 'reveal');
  assert.equal(frame.payload.move.data.verified, true);
});

test('commit-reveal: wrong secret/salt, missing phase, and cross-actor reveals are rejected', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = (await a.api.post('/api/games', {
    json: { type: 'twotruths', payload: { rounds: 1 } },
  })).body.game;
  await b.api.post(`/api/games/${game.id}/join`, { json: {} });

  // Reveal without statements/guess is a phase error, never a stored false claim.
  const noCommit = await b.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'reveal', round: 0, reveal: '1', salt: 's' } },
  });
  assert.equal(noCommit.status, 403);

  // The teller commits three statements; the partner guesses.
  const commitMove = (
    await a.api.post(`/api/games/${game.id}/move`, {
      json: {
        data: {
          kind: 'statements',
          round: 0,
          texts: ['one', 'two', 'three'],
          commit: sha256('2' + 'n1'),
        },
      },
    })
  ).body.move;
  await b.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'guess', round: 0, pick: 1 } },
  });

  // Lying about the committed secret is rejected and not stored.
  const lie = await a.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'reveal', round: 0, reveal: '1', salt: 'n1' } },
  });
  assert.equal(lie.status, 409);
  assert.equal(lie.body.error, 'reveal_mismatch');

  // Explicit commitId verifies against the teller's own statements commit.
  const targeted = await a.api.post(`/api/games/${game.id}/move`, {
    json: {
      data: {
        kind: 'reveal', round: 0, reveal: '2', salt: 'n1', commitId: commitMove.id,
      },
    },
  });
  assert.equal(targeted.body.move.data.verified, true);

  // A non-teller can never reveal, even with the teller's commit id.
  const cross = await b.api.post(`/api/games/${game.id}/move`, {
    json: {
      data: {
        kind: 'reveal', round: 0, reveal: '2', salt: 'n1', commitId: commitMove.id,
      },
    },
  });
  assert.equal(cross.status, 409); // the accepted teller reveal already ended the game
});

// ---------------------------------------------------------------------------
// v3.0 infra b — inbox "games" bucket

test('inbox games bucket: lobby invitations and last-mover turns land in awaitingMe', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const since = new Date(Date.now() - 60_000).toISOString();
  const inbox = (who) => who.api.get(`/api/inbox?since=${encodeURIComponent(since)}`).then((r) => r.body.games);

  // No games → empty bucket.
  assert.deepEqual(await inbox(a), { count: 0, awaitingMe: [] });

  // A creates a lobby → awaiting B (join me!), not A.
  const ship = (await a.api.post('/api/games', { json: { type: 'connectfour' } })).body.game;
  assert.deepEqual(await inbox(b), { count: 1, awaitingMe: [{ gameId: ship.id, type: 'connectfour' }] });
  assert.deepEqual(await inbox(a), { count: 0, awaitingMe: [] });

  // Joined but no moves yet → the server-authoritative turnMemberId already
  // knows the creator opens (sync contract c) — A is awaited, B is not.
  await b.api.post(`/api/games/${ship.id}/join`, { json: {} });
  assert.equal((await inbox(a)).count, 1);
  assert.equal((await inbox(b)).count, 0);

  // A moves → B is up; B moves → A is up.
  await a.api.post(`/api/games/${ship.id}/move`, { json: { data: { kind: 'drop', column: 0 } } });
  assert.deepEqual(await inbox(b), { count: 1, awaitingMe: [{ gameId: ship.id, type: 'connectfour' }] });
  assert.equal((await inbox(a)).count, 0);
  await b.api.post(`/api/games/${ship.id}/move`, { json: { data: { kind: 'drop', column: 1 } } });
  assert.deepEqual(await inbox(a), { count: 1, awaitingMe: [{ gameId: ship.id, type: 'connectfour' }] });

  // A second open game stacks up in the same bucket.
  const dice = (await b.api.post('/api/games', { json: { type: 'kniffel' } })).body.game;
  const forA = await inbox(a);
  assert.equal(forA.count, 2);
  assert.deepEqual(
    forA.awaitingMe.map((g) => g.gameId).sort(),
    [ship.id, dice.id].sort(),
  );

  // Ended games drop out immediately.
  await a.api.post(`/api/games/${ship.id}/end`, { json: { forfeit: true } });
  await b.api.post(`/api/games/${dice.id}/end`, { json: { forfeit: true } });
  assert.deepEqual(await inbox(a), { count: 0, awaitingMe: [] });
});

// ---------------------------------------------------------------------------
// v3.0 app-event hooks (events.js) — movie matches & daily quests

test('movieroulette match move emits a movie_match app event to both partners', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  await aSock.waitFor('welcome');

  const game = (await a.api.post('/api/games', {
    json: { type: 'movieroulette', payload: { size: 1 } },
  })).body.game;
  await b.api.post(`/api/games/${game.id}/join`, { json: {} });

  // A single like emits nothing — the relay waits for the partner's like.
  await a.api.post(`/api/games/${game.id}/move`, { json: { data: { kind: 'swipe', index: 0, like: true } } });
  await aSock.assertNone('app_event');

  // The second like completes the match — the SERVER derives the event from
  // the stored moves (the annotation only contributes the cosmetic title).
  await b.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'swipe', index: 0, like: true, match: { cardIndex: 0, title: 'La La Land' } } },
  });
  const frame = await aSock.waitFor('app_event');
  assert.equal(frame.payload.event.type, 'movie_match');
  assert.equal(frame.payload.event.memberId, null);
  assert.deepEqual(frame.payload.event.data, { gameId: game.id, cardIndex: 0, title: 'La La Land' });
});

test('dailyquests quest_done move emits a quest_done app event with the dateKey', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b, coupleId } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const today = new Date().toISOString().slice(0, 10);
  const game = (await a.api.post('/api/games', { json: { type: 'dailyquests', payload: { dateKey: today } } }))
    .body.game;
  await b.api.post(`/api/games/${game.id}/join`, { json: {} });
  const questIndex = gameRulesInternals.dailyQuestIndexes(coupleId, today)[0];
  await a.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'quest_done', questIndex } },
  });

  const frame = await bSock.waitFor('app_event');
  assert.equal(frame.payload.event.type, 'quest_done');
  assert.equal(frame.payload.event.memberId, a.memberId);
  assert.deepEqual(frame.payload.event.data, { gameId: game.id, dateKey: today, questIndex });
});

test('v3.0 game types are accepted by the relay', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  for (const type of ['battleship', 'pictionary', 'kniffel', 'movieroulette', 'stadtlandfluss', 'twotruths', 'dailyquests']) {
    const res = await a.api.post('/api/games', { json: { type } });
    assert.equal(res.status, 201, `type ${type} should be accepted`);
    assert.equal(res.body.game.type, type);
    await a.api.post(`/api/games/${res.body.game.id}/end`, { json: {} });
  }
  assert.equal((await a.api.post('/api/games', { json: { type: 'monopoly' } })).status, 400);
});
