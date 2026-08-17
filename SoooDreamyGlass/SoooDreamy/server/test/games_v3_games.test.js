import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { makeApp, setupCouple, wsOpen } from './helpers.js';
import { gameRulesInternals } from '../src/game-rules.js';

// E2E protocol runs of the v3.0 games — each test plays a full (mini) match
// over the relay exactly the way the iOS reducers do, pinning the wire
// format both clients depend on.

const sha256 = (text) => createHash('sha256').update(text, 'utf8').digest('hex');

// ---------------------------------------------------------------------------
// 1. Schiffe versenken (battleship): commit → salvos + reports → reveal

test('battleship: full commit/salvo/report/reveal match over the relay', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  const game = (await a.api.post('/api/games', { json: { type: 'battleship' } })).body.game;
  await b.api.post(`/api/games/${game.id}/join`, { json: {} });
  const move = (who, data) => who.api.post(`/api/games/${game.id}/move`, { json: { data } });

  // Setup phase: both lock their fleet in as sha256(layout + salt).
  const fleetA = '0,1,2,3|16,24,32|40,41,42|54,55';
  const fleetB = '8,9,10,11|20,28,36|45,46,47|62,63';
  const saltA = 'salz-a';
  const saltB = 'salz-b';
  const commitA = (await move(a, { kind: 'commit', commit: sha256(fleetA + saltA) })).body.move;
  const commitB = (await move(b, { kind: 'commit', commit: sha256(fleetB + saltB) })).body.move;

  // Battle: A honestly hits all 12 cells of B's fleet. B alternates legal
  // salvos that miss A's fleet so every report can be verified after reveal.
  await move(a, { kind: 'salvo', cells: [8, 9] });
  await move(b, { kind: 'report', index: 0, hits: [8, 9], sunk: [] });
  await move(b, { kind: 'salvo', cells: [7, 15] });
  await move(a, { kind: 'report', index: 1, hits: [], sunk: [] });
  await move(a, { kind: 'salvo', cells: [10, 11] });
  await move(b, { kind: 'report', index: 2, hits: [10, 11], sunk: [4] });
  await move(b, { kind: 'salvo', cells: [23, 31] });
  await move(a, { kind: 'report', index: 3, hits: [], sunk: [] });
  await move(a, { kind: 'salvo', cells: [20, 28] });
  await move(b, { kind: 'report', index: 4, hits: [20, 28], sunk: [] });
  await move(b, { kind: 'salvo', cells: [39, 47] });
  await move(a, { kind: 'report', index: 5, hits: [], sunk: [] });
  await move(a, { kind: 'salvo', cells: [36, 45] });
  await move(b, { kind: 'report', index: 6, hits: [36, 45], sunk: [3] });
  await move(b, { kind: 'salvo', cells: [48, 49] });
  await move(a, { kind: 'report', index: 7, hits: [], sunk: [] });
  await move(a, { kind: 'salvo', cells: [46, 47] });
  await move(b, { kind: 'report', index: 8, hits: [46, 47], sunk: [3] });
  await move(b, { kind: 'salvo', cells: [56, 57] });
  await move(a, { kind: 'report', index: 9, hits: [], sunk: [] });
  await move(a, { kind: 'salvo', cells: [62, 63] });
  await move(b, { kind: 'report', index: 10, hits: [62, 63], sunk: [2] });

  // Endgame: both reveal — the server certifies commitments, reports and
  // winner. The second accepted reveal ends the game automatically.
  const revealA = (
    await move(a, { kind: 'reveal', reveal: fleetA, salt: saltA, commitId: commitA.id })
  ).body.move;
  assert.equal(revealA.data.verified, true);
  const finalReveal = await move(
    b,
    { kind: 'reveal', reveal: fleetB, salt: saltB, commitId: commitB.id },
  );
  const revealB = (
    finalReveal
  ).body.move;
  assert.equal(revealB.data.verified, true);
  assert.equal(finalReveal.body.game.state, 'ended');
  const finished = (await b.api.get(`/api/games/${game.id}`)).body.game;
  assert.equal(finished.state, 'ended');
  assert.equal(finished.moves.length, 26);
  assert.equal(finished.result.scores[a.memberId], 1);
  assert.equal(finished.result.integrity, true);
});

// ---------------------------------------------------------------------------
// 2. Montagsmaler (pictionary): rounds, strokes over the relay, guesses

test('pictionary: round starts, strokes and guesses relay with server timestamps', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  const game = (
    await a.api.post('/api/games', {
      json: { type: 'pictionary', payload: { seed: 7, rounds: 2, secs: 90, lang: 'de' } },
    })
  ).body.game;
  assert.equal(game.payload.lang, 'de'); // deck language is shared via payload
  const words = gameRulesInternals.pictionaryDeck(game);
  await b.api.post(`/api/games/${game.id}/join`, { json: {} });
  const move = (who, data) => who.api.post(`/api/games/${game.id}/move`, { json: { data } });

  // Round 0: creator draws. The round_start's SERVER createdAt anchors the timer.
  const start = (await move(a, { kind: 'round_start', round: 0 })).body.move;
  assert.ok(!Number.isNaN(Date.parse(start.createdAt)));

  // Strokes ride the relay as moves (normalized points survive verbatim).
  const stroke = (
    await move(a, {
      kind: 'stroke',
      round: 0,
      color: '#2D2A32',
      width: 4,
      points: [[0.1, 0.2], [0.3, 0.42]],
    })
  ).body.move;
  assert.deepEqual(stroke.data.points, [[0.1, 0.2], [0.3, 0.42]]);
  await move(a, { kind: 'clear', round: 0 });

  // Guesses come from the partner; wrong then right.
  await move(b, { kind: 'guess', round: 0, text: 'definitely wrong' });
  await move(b, { kind: 'guess', round: 0, text: words[0] });

  // Round 1: roles swap — partner draws, creator guesses.
  await move(b, { kind: 'round_start', round: 1 });
  const finalGuess = await move(a, { kind: 'guess', round: 1, text: words[1] });
  assert.equal(finalGuess.body.game.state, 'ended');
  const finished = (await b.api.get(`/api/games/${game.id}`)).body.game;
  assert.equal(finished.state, 'ended');
  assert.equal(finished.moves.length, 7);
  // Move timestamps are monotonically usable for deadline math.
  const times = finished.moves.map((m) => Date.parse(m.createdAt));
  assert.ok(times.every((ts, i) => i === 0 || ts >= times[i - 1]));
});

// ---------------------------------------------------------------------------
// 3. Kniffel-Liebesedition: seeded dice — moves carry only held indexes

test('kniffel: rolls carry held dice only; the seed in the payload drives the pips', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  // No client seed → the server injects one (both clients derive dice from it).
  const game = (await a.api.post('/api/games', { json: { type: 'kniffel' } })).body.game;
  assert.ok(Number.isInteger(game.payload.seed) && game.payload.seed >= 1);
  await b.api.post(`/api/games/${game.id}/join`, { json: {} });
  const move = (who, data) => who.api.post(`/api/games/${game.id}/move`, { json: { data } });

  // Turn 0 (creator): roll, hold two dice, re-roll, bank a category.
  await move(a, { kind: 'roll', held: [] });
  const reroll = (await move(a, { kind: 'roll', held: [0, 2] })).body.move;
  assert.deepEqual(reroll.data.held, [0, 2]); // values live client-side, derived from the seed
  await move(a, { kind: 'score', category: 'chance' });

  // Turn 1 (partner).
  await move(b, { kind: 'roll', held: [] });
  await move(b, { kind: 'score', category: 'kniffel' });

  const fetched = (await a.api.get(`/api/games/${game.id}`)).body.game;
  assert.equal(fetched.moves.length, 5);
  assert.deepEqual(
    fetched.moves.map((m) => m.data.kind),
    ['roll', 'roll', 'score', 'roll', 'score'],
  );

  const forged = await a.api.post(`/api/games/${game.id}/end`, {
    json: { result: { scores: { [a.memberId]: 180, [b.memberId]: 168 } } },
  });
  assert.equal(forged.status, 409);

  // Complete all remaining turns so the persisted scorecard is derived from
  // the server's deterministic dice, never from the rejected client body.
  const categories = [
    'ones', 'twos', 'threes', 'fours', 'fives', 'sixes',
    'three', 'four', 'full', 'small', 'large', 'kniffel', 'chance',
  ];
  const remaining = new Map([
    [a.memberId, categories.filter((category) => category !== 'chance')],
    [b.memberId, categories.filter((category) => category !== 'kniffel')],
  ]);
  let finalScore;
  for (let turn = 2; turn < 26; turn += 1) {
    const who = turn % 2 === 0 ? a : b;
    await move(who, { kind: 'roll', held: [] });
    finalScore = await move(who, {
      kind: 'score',
      category: remaining.get(who.memberId).shift(),
    });
  }
  assert.equal(finalScore.body.game.state, 'ended');
  const done = (await b.api.get(`/api/games/${game.id}`)).body.game;
  assert.equal(done.moves.length, 53);
  assert.equal(typeof done.result.scores[a.memberId], 'number');
  assert.equal(typeof done.result.scores[b.memberId], 'number');
});

// ---------------------------------------------------------------------------
// 4. Film-Roulette: seeded deck via payload, swipes, match annotation

test('movieroulette: swipe flow with custom deck entries and a match result', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  const game = (
    await a.api.post('/api/games', {
      json: { type: 'movieroulette', payload: { seed: 11, size: 3, custom: ['Unser Film'] } },
    })
  ).body.game;
  assert.deepEqual(game.payload.custom, ['Unser Film']); // custom entries ride the payload
  await b.api.post(`/api/games/${game.id}/join`, { json: {} });
  const move = (who, data) => who.api.post(`/api/games/${game.id}/move`, { json: { data } });

  // Both swipe the same indexed deck; index 1 becomes the match — the
  // COMPLETING swipe carries the annotation (relay emits movie_match).
  await move(a, { kind: 'swipe', index: 0, like: false });
  await move(a, { kind: 'swipe', index: 1, like: true });
  await move(a, { kind: 'swipe', index: 2, like: false });
  await move(b, { kind: 'swipe', index: 0, like: true });
  const matching = (
    await move(b, {
      kind: 'swipe', index: 1, like: true,
      match: { cardIndex: 1, title: 'Unser Film' },
    })
  ).body.move;
  assert.equal(matching.data.match.cardIndex, 1);
  await move(b, { kind: 'swipe', index: 2, like: false });

  // Completion is automatic and server-derived; a later client result body
  // cannot replace the canonical match indexes.
  await a.api.post(`/api/games/${game.id}/end`, {
    json: { result: { matches: ['forged client result'] } },
  });
  const done = (await a.api.get(`/api/games/${game.id}`)).body.game;
  assert.equal(done.moves.length, 6);
  assert.deepEqual(done.result, { matchIndexes: [1], matches: 1 });
});

// ---------------------------------------------------------------------------
// 5. Stadt-Land-Fluss: anti-spoiler commit → reveal (verified) → mutual rating

test('stadtlandfluss: commit/reveal round with custom categories and mutual rating', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  const categories = ['Stadt', 'Land', 'Fluss', 'Kosename'];
  const game = (
    await a.api.post('/api/games', {
      json: { type: 'stadtlandfluss', payload: { seed: 9, rounds: 1, categories } },
    })
  ).body.game;
  assert.deepEqual(game.payload.categories, categories);
  const letter = gameRulesInternals.seededShuffle(
    [...`ABCDEFGHIJKLMNOPRSTUVWZ`],
    game.payload.seed,
  )[0];
  await b.api.post(`/api/games/${game.id}/join`, { json: {} });
  const move = (who, data) => who.api.post(`/api/games/${game.id}/move`, { json: { data } });

  // Both seal their answers first — plaintext is NOT on the wire yet.
  const joinedA = categories.map((_, index) => `${letter}A${index}`).join('\u001f');
  const joinedB = categories.map((_, index) => `${letter}B${index}`).join('\u001f');
  const commitA = (await move(a, { kind: 'commit', round: 0, commit: sha256(joinedA + 's1') }))
    .body.move;
  const commitB = (await move(b, { kind: 'commit', round: 0, commit: sha256(joinedB + 's2') }))
    .body.move;

  // Reveals are certified against the commits by the relay.
  const revealA = (
    await move(a, { kind: 'reveal', round: 0, reveal: joinedA, salt: 's1', commitId: commitA.id })
  ).body.move;
  const revealB = (
    await move(b, { kind: 'reveal', round: 0, reveal: joinedB, salt: 's2', commitId: commitB.id })
  ).body.move;
  assert.equal(revealA.data.verified, true);
  assert.equal(revealB.data.verified, true);

  // Mutual rating closes the round.
  await move(a, { kind: 'rate', round: 0, verdicts: [true, true, true, true] });
  const completed = await move(
    b,
    { kind: 'rate', round: 0, verdicts: [true, true, true, true] },
  );
  assert.equal(completed.body.game.state, 'ended');

  const forged = await a.api.post(`/api/games/${game.id}/end`, {
    json: { result: { scores: { [a.memberId]: 45, [b.memberId]: 15 } } },
  });
  assert.equal(forged.status, 200);
  const done = (await b.api.get(`/api/games/${game.id}`)).body.game;
  assert.equal(done.moves.length, 6);
  assert.deepEqual(done.result.scores, { [a.memberId]: 40, [b.memberId]: 40 });
});

// ---------------------------------------------------------------------------
// 6. Zwei Wahrheiten, eine Lüge: statements+commit → guess → reveal per round

test('twotruths: lie index is sealed with the statements and certified on reveal', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  const game = (
    await a.api.post('/api/games', { json: { type: 'twotruths', payload: { rounds: 2 } } })
  ).body.game;
  await b.api.post(`/api/games/${game.id}/join`, { json: {} });
  const move = (who, data) => who.api.post(`/api/games/${game.id}/move`, { json: { data } });

  // Round 0: A tells. The lie's index (2) is committed IN the statements move,
  // so it provably cannot be switched after B's guess.
  const statements = (
    await move(a, {
      kind: 'statements',
      round: 0,
      texts: ['Ich war auf einem Vulkan', 'Ich hasse Schokolade', 'Ich kann jonglieren'],
      commit: sha256('2' + 'salz-a'),
    })
  ).body.move;
  await move(b, { kind: 'guess', round: 0, pick: 1 });
  const reveal = (
    await move(a, { kind: 'reveal', round: 0, reveal: '2', salt: 'salz-a', commitId: statements.id })
  ).body.move;
  assert.equal(reveal.data.verified, true);

  // A switched lie is rejected and never enters the history.
  const forged = await move(
    a,
    { kind: 'reveal', round: 0, reveal: '1', salt: 'salz-a', commitId: statements.id },
  );
  assert.equal(forged.status, 409);
  assert.equal(forged.body.error, 'wrong_round');

  // Round 1: roles alternate — B tells, A guesses right.
  const statements2 = (
    await move(b, {
      kind: 'statements',
      round: 1,
      texts: ['Ich mag Regen', 'Ich hatte mal blaue Haare', 'Ich koche gern'],
      commit: sha256('0' + 'salz-b'),
    })
  ).body.move;
  await move(a, { kind: 'guess', round: 1, pick: 0 });
  const finalReveal = await move(b, {
    kind: 'reveal',
    round: 1,
    reveal: '0',
    salt: 'salz-b',
    commitId: statements2.id,
  });
  const reveal2 = finalReveal.body.move;
  assert.equal(reveal2.data.verified, true);
  assert.equal(finalReveal.body.game.state, 'ended');

  // Round 0: B guessed 1, lie was 2 → teller A scores. Round 1: A guessed
  // the lie (0) → guesser A scores again. 2:0 for A.
  const done = (await b.api.get(`/api/games/${game.id}`)).body.game;
  assert.equal(done.state, 'ended');
  assert.equal(done.moves.length, 6); // rejected forged reveal is not persisted
  assert.equal(done.result.scores[a.memberId], 2);
});

// ---------------------------------------------------------------------------
// 7. Paar-Tagesquests: one session per day, shared checkboxes, streak history

test('dailyquests: self-activated day sessions, shared checks and history for streaks', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b, coupleId } = await setupCouple(baseUrl);
  // v3.0.1 validates the dateKey (±1 day of server date) → use real dates.
  const yesterday = new Date(Date.now() - 86_400_000).toISOString().slice(0, 10);
  const today = new Date().toISOString().slice(0, 10);

  // The creator activates the checklist alone — no lobby ceremony needed.
  const day1 = (
    await a.api.post('/api/games', {
      json: { type: 'dailyquests', payload: { dateKey: yesterday } },
    })
  ).body.game;
  const joined = (await a.api.post(`/api/games/${day1.id}/join`, { json: {} })).body.game;
  assert.equal(joined.state, 'active');

  // Shared checkboxes: BOTH partners check quests of the same day.
  const move = (who, questIndex) =>
    who.api.post(`/api/games/${day1.id}/move`, { json: { data: { kind: 'quest_done', questIndex } } });
  const indexes = gameRulesInternals.dailyQuestIndexes(coupleId, yesterday);
  await move(a, indexes[0]);
  await move(b, indexes[1]);
  const completion = await move(b, indexes[2]);
  assert.equal(completion.body.game.state, 'ended');
  assert.deepEqual(completion.body.game.result, {
    done: 3,
    total: 3,
    dateKey: yesterday,
  });

  // Next morning: today's session replaces yesterday's (same-type lifecycle);
  // an UNFINISHED day would be auto-ended by that create.
  const day2 = (
    await b.api.post('/api/games', {
      json: { type: 'dailyquests', payload: { dateKey: today } },
    })
  ).body.game;
  await b.api.post(`/api/games/${day2.id}/join`, { json: {} });

  // Streak sources read the history: both days present, day 1 complete.
  const history = (await a.api.get('/api/games?limit=50')).body.games.filter(
    (g) => g.type === 'dailyquests',
  );
  assert.equal(history.length, 2);
  const finished = history.find((g) => g.payload.dateKey === yesterday);
  assert.equal(finished.state, 'ended');
  assert.equal(finished.result.done, 3);
  assert.equal(finished.moves.length, 3);
  const open = history.find((g) => g.payload.dateKey === today);
  assert.equal(open.state, 'active');
});

// ---------------------------------------------------------------------------
// 8. Turnier-Modus: season tables derive from the plain games history —
// this pins the fields (type, createdAt, result.scores) both clients
// aggregate into identical monthly tables (no new realtime protocol).

test('season source: history keeps type, createdAt and result.scores of ended matches', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  const play = async (type, forfeiter) => {
    const game = (await a.api.post('/api/games', { json: { type } })).body.game;
    await b.api.post(`/api/games/${game.id}/join`, { json: {} });
    const ended = await forfeiter.api.post(`/api/games/${game.id}/end`, {
      json: { forfeit: true },
    });
    assert.equal(ended.status, 200);
    return game.id;
  };
  await play('kniffel', a);
  await play('battleship', b);
  await play('twotruths', a);

  const history = (await b.api.get('/api/games?limit=100')).body.games;
  const ended = history.filter((g) => g.state === 'ended');
  assert.equal(ended.length, 3);
  for (const game of ended) {
    assert.ok(['kniffel', 'battleship', 'twotruths'].includes(game.type));
    assert.ok(typeof game.createdAt === 'string' && game.createdAt.includes('T'));
    assert.equal(typeof game.result.scores[a.memberId], 'number');
    assert.equal(typeof game.result.scores[b.memberId], 'number');
  }
});

// ---------------------------------------------------------------------------
// 9. Replay & Zuschauer-Modus: a SECOND device of the same member receives
// every game_move / game_ended frame (spectator contract), and finished
// sessions keep the full ordered move list incl. createdAt (replay source).

test('spectator: a second device of the mover gets game_move and game_ended frames', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  // A's iPad — same member, second socket, purely watching.
  const ipad = await wsOpen(baseUrl, a.token, t);
  await ipad.waitFor('welcome');

  const game = (await a.api.post('/api/games', { json: { type: 'connectfour' } })).body.game;
  await b.api.post(`/api/games/${game.id}/join`, { json: {} });
  await a.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'drop', column: 3 } },
  });

  const frame = await ipad.waitFor('game_move');
  assert.equal(frame.payload.gameId, game.id);
  assert.equal(frame.payload.move.memberId, a.memberId);
  assert.equal(frame.payload.move.data.column, 3);
  assert.ok(typeof frame.payload.move.createdAt === 'string');

  await b.api.post(`/api/games/${game.id}/end`, { json: { forfeit: true } });
  const ended = await ipad.waitFor('game_ended');
  assert.equal(ended.payload.game.id, game.id);

  // Replay source: the persisted session returns the ordered move list.
  const replay = (await a.api.get(`/api/games/${game.id}`)).body.game;
  assert.equal(replay.state, 'ended');
  assert.equal(replay.moves.length, 1);
  assert.ok(replay.moves.every((m) => typeof m.createdAt === 'string'));
});
