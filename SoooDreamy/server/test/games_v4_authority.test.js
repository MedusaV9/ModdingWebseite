import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import test from 'node:test';
import { gameRulesInternals } from '../src/game-rules.js';
import { makeApp, setupCouple } from './helpers.js';

const sha256 = (value) => createHash('sha256').update(value, 'utf8').digest('hex');

async function harness(t) {
  const { baseUrl } = await makeApp(t);
  const pair = await setupCouple(baseUrl);
  const create = async (type, payload = {}) => {
    const response = await pair.a.api.post('/api/games', { json: { type, payload } });
    assert.equal(response.status, 201, JSON.stringify(response.body));
    const game = response.body.game;
    const joined = await pair.b.api.post(`/api/games/${game.id}/join`, { json: {} });
    assert.equal(joined.status, 200, JSON.stringify(joined.body));
    return joined.body.game;
  };
  const move = (game, who, data, clientMoveId) => who.api.post(`/api/games/${game.id}/move`, {
    json: { data, ...(clientMoveId ? { clientMoveId } : {}) },
  });
  const fetchGame = async (game, who = pair.a) => (
    await who.api.get(`/api/games/${game.id}`)
  ).body.game;
  return { ...pair, create, move, fetchGame, baseUrl };
}

test('quiz and simultaneous choice games enforce actor, phase, duplicate and canonical result', async (t) => {
  const h = await harness(t);
  const quiz = await h.create('quiz', { rounds: 1 });
  const members = [h.a.memberId, h.b.memberId].sort();
  const subject = members[0];
  const guesser = members[1];
  const byId = { [h.a.memberId]: h.a, [h.b.memberId]: h.b };

  const forgedEnd = await h.a.api.post(`/api/games/${quiz.id}/end`, {
    json: { result: { scores: { [h.a.memberId]: 999 } } },
  });
  assert.equal(forgedEnd.status, 409);
  assert.equal(forgedEnd.body.error, 'game_incomplete');

  assert.equal((await h.move(quiz, byId[guesser], { kind: 'verdict', round: 0, value: 'right' })).status, 403);
  assert.equal((await h.move(quiz, h.a, { kind: 'answer', round: 0, value: 'mine' })).status, 201);
  const duplicate = await h.move(quiz, h.a, { kind: 'answer', round: 0, value: 'changed' });
  assert.equal(duplicate.status, 409);
  assert.equal(duplicate.body.error, 'duplicate_move');
  assert.equal((await h.move(quiz, h.b, { kind: 'answer', round: 0, value: 'theirs' })).status, 201);
  assert.equal((await h.move(quiz, byId[subject], { kind: 'verdict', round: 0, value: 'right' })).status, 201);
  const quizDone = await h.fetchGame(quiz);
  assert.equal(quizDone.state, 'ended');
  assert.deepEqual(quizDone.result.scores, { [members[0]]: 0, [members[1]]: 1 });

  for (const type of ['thisorthat', 'wouldyourather']) {
    const game = await h.create(type, { rounds: 1, ignored: 'not persisted' });
    assert.deepEqual(Object.keys(game.payload).sort(), ['rounds', 'seed', 'seedServer']);
    const first = await h.move(game, h.a, { kind: 'pick', round: 0, value: 'a' }, `idem-${type}`);
    assert.equal(first.status, 201);
    const replay = await h.move(game, h.a, { kind: 'pick', round: 0, value: 'b' }, `idem-${type}`);
    assert.equal(replay.status, 200);
    assert.equal(replay.body.duplicate, true);
    assert.equal(replay.body.move.id, first.body.move.id);
    assert.equal((await h.move(game, h.b, { kind: 'pick', round: 1, value: 'a' })).body.error, 'invalid_game_move');
    assert.equal((await h.move(game, h.b, { kind: 'pick', round: 0, value: 'a' })).status, 201);
    const done = await h.fetchGame(game);
    assert.equal(done.state, 'ended');
    assert.deepEqual(done.result, { matches: 1, rounds: 1 });
  }
});

test('truth-or-dare and emoji riddle enforce round ownership and score only accepted claims', async (t) => {
  const h = await harness(t);
  const invalidSetup = await h.a.api.post('/api/games', {
    json: { type: 'truthordare', payload: { rounds: 1, spice: 99 } },
  });
  assert.equal(invalidSetup.status, 400);
  const truth = await h.create('truthordare', { rounds: 1, spice: 3 });
  assert.equal(truth.payload.spice, 3);
  const members = [h.a.memberId, h.b.memberId].sort();
  const activeId = members[truth.payload.seed % 2];
  const active = activeId === h.a.memberId ? h.a : h.b;
  const idle = active === h.a ? h.b : h.a;
  assert.equal((await h.move(truth, idle, { kind: 'pick', round: 0, value: 'truth' })).status, 403);
  assert.equal((await h.move(truth, active, { kind: 'claim', round: 0, value: 'done' })).status, 409);
  await h.move(truth, active, { kind: 'pick', round: 0, value: 'truth' });
  await h.move(truth, active, { kind: 'claim', round: 0, value: 'done' });
  const truthDone = await h.fetchGame(truth);
  assert.equal(truthDone.result.scores[activeId], 1);
  assert.equal(truthDone.result.scores[idle.memberId], 0);

  const emoji = await h.create('emojiriddle', { rounds: 1 });
  await h.move(emoji, h.a, { kind: 'guess', round: 0, value: 'answer a' });
  assert.equal((await h.move(emoji, h.a, { kind: 'claim', round: 0, value: 'right' })).status, 409);
  await h.move(emoji, h.b, { kind: 'guess', round: 0, value: 'answer b' });
  await h.move(emoji, h.a, { kind: 'claim', round: 0, value: 'right' });
  await h.move(emoji, h.b, { kind: 'claim', round: 0, value: 'wrong' });
  const emojiDone = await h.fetchGame(emoji);
  assert.deepEqual(emojiDone.result, {
    scores: { [h.a.memberId]: 1, [h.b.memberId]: 0 },
    scoring: 'self_claimed',
  });
});

test('Connect Four and photo memory reject out-of-turn/range/repeated actions and derive winners', async (t) => {
  const h = await harness(t);
  const connect = await h.create('connectfour');
  assert.equal((await h.move(connect, h.b, { kind: 'drop', column: 3 })).body.error, 'wrong_turn');
  assert.equal((await h.move(connect, h.a, { kind: 'drop', column: 7 })).body.error, 'invalid_game_move');
  for (const [who, column] of [
    [h.a, 3], [h.b, 4], [h.a, 3], [h.b, 4], [h.a, 3], [h.b, 4], [h.a, 3],
  ]) {
    assert.equal((await h.move(connect, who, { kind: 'drop', column })).status, 201);
  }
  const connectDone = await h.fetchGame(connect);
  assert.equal(connectDone.state, 'ended');
  assert.equal(connectDone.result.winner, h.a.memberId);
  assert.deepEqual(connectDone.result.scores, { [h.a.memberId]: 1, [h.b.memberId]: 0 });

  for (let index = 0; index < 2; index += 1) {
    const upload = await h.a.api.post('/api/photos', {
      body: Buffer.from(`jpeg-${index}`),
      headers: { 'content-type': 'image/jpeg' },
    });
    assert.equal(upload.status, 201);
  }
  const photos = (await h.a.api.get('/api/photos')).body.photos.map((photo) => photo.id);
  const memory = await h.create('photomemory', { photoIds: photos });
  const tiles = gameRulesInternals.memoryTiles(memory);
  const pairCells = [...new Set(tiles)].map((pair) => (
    tiles.map((value, index) => (value === pair ? index : -1)).filter((index) => index >= 0)
  ));
  assert.equal((await h.move(memory, h.b, { kind: 'flip', first: pairCells[0][0], second: pairCells[0][1] })).body.error, 'wrong_turn');
  await h.move(memory, h.a, { kind: 'flip', first: pairCells[0][0], second: pairCells[0][1] });
  assert.equal((await h.move(memory, h.a, { kind: 'flip', first: pairCells[0][0], second: pairCells[0][1] })).body.error, 'already_matched');
  await h.move(memory, h.a, { kind: 'flip', first: pairCells[1][0], second: pairCells[1][1] });
  const memoryDone = await h.fetchGame(memory);
  assert.equal(memoryDone.state, 'ended');
  assert.deepEqual(memoryDone.result.scores, { [h.a.memberId]: 2, [h.b.memberId]: 0 });
});

test('quiz duel and pictionary use server seed/content to calculate objective scores', async (t) => {
  const h = await harness(t);
  const duel = await h.create('quizduel', { rounds: 1 });
  const correct = gameRulesInternals.quizDuelDeck(duel)[0];
  assert.equal((await h.move(duel, h.a, { kind: 'answer', round: 0, option: 3 })).body.error, 'invalid_game_move');
  await h.move(duel, h.b, { kind: 'answer', round: 0, option: correct });
  await h.move(duel, h.a, { kind: 'answer', round: 0, option: correct });
  const duelDone = await h.fetchGame(duel);
  assert.deepEqual(duelDone.result.scores, { [h.a.memberId]: 1, [h.b.memberId]: 2 });

  const picture = await h.create('pictionary', { rounds: 1, secs: 90, lang: 'de' });
  const word = gameRulesInternals.pictionaryDeck(picture)[0];
  assert.equal((await h.move(picture, h.b, { kind: 'round_start', round: 0 })).status, 403);
  await h.move(picture, h.a, { kind: 'round_start', round: 0 });
  assert.equal((await h.move(picture, h.b, {
    kind: 'stroke', round: 0, color: '#ffffff', width: 4, points: [[0.1, 0.2]],
  })).status, 403);
  await h.move(picture, h.a, {
    kind: 'stroke', round: 0, color: '#ffffff', width: 4, points: [[0.1, 0.2], [0.4, 0.5]],
  });
  await h.move(picture, h.b, { kind: 'guess', round: 0, text: word });
  const pictureDone = await h.fetchGame(picture);
  assert.equal(pictureDone.state, 'ended');
  assert.deepEqual(pictureDone.result.scores, { [h.a.memberId]: 0, [h.b.memberId]: 1 });
});

test('Kniffel validates all 26 turns and calculates deterministic scorecards server-side', async (t) => {
  const h = await harness(t);
  const game = await h.create('kniffel');
  const categories = [
    'ones', 'twos', 'threes', 'fours', 'fives', 'sixes',
    'three', 'four', 'full', 'small', 'large', 'kniffel', 'chance',
  ];
  assert.equal((await h.move(game, h.b, { kind: 'roll', held: [] })).body.error, 'wrong_turn');
  for (let turn = 0; turn < 26; turn += 1) {
    const who = turn % 2 === 0 ? h.a : h.b;
    const category = categories[Math.floor(turn / 2)];
    assert.equal((await h.move(game, who, { kind: 'roll', held: [] })).status, 201);
    assert.equal((await h.move(game, who, { kind: 'score', category })).status, 201);
  }
  const done = await h.fetchGame(game);
  assert.equal(done.state, 'ended');
  assert.equal(typeof done.result.scores[h.a.memberId], 'number');
  assert.equal(typeof done.result.scores[h.b.memberId], 'number');
  const forged = await h.a.api.post(`/api/games/${game.id}/end`, {
    json: { result: { scores: { [h.a.memberId]: 99999 } } },
  });
  assert.deepEqual(forged.body.game.result, done.result);
});

test('movie, daily quests and no-action sessions cannot skip, duplicate, or forge results', async (t) => {
  const h = await harness(t);
  const movie = await h.create('movieroulette', { size: 2, custom: ['Us'] });
  assert.equal((await h.move(movie, h.a, { kind: 'swipe', index: 1, like: true })).body.error, 'wrong_card');
  await h.move(movie, h.a, { kind: 'swipe', index: 0, like: true });
  assert.equal((await h.move(movie, h.a, { kind: 'swipe', index: 0, like: false })).body.error, 'wrong_card');
  await h.move(movie, h.a, { kind: 'swipe', index: 1, like: false });
  await h.move(movie, h.b, { kind: 'swipe', index: 0, like: true });
  await h.move(movie, h.b, { kind: 'swipe', index: 1, like: true });
  const movieDone = await h.fetchGame(movie);
  assert.deepEqual(movieDone.result, { matchIndexes: [0], matches: 1 });

  const day = new Date().toISOString().slice(0, 10);
  const quests = await h.create('dailyquests', { dateKey: day });
  const dailyIndexes = gameRulesInternals.dailyQuestIndexes(h.coupleId, day);
  const invalidIndex = Array.from({ length: 48 }, (_, index) => index)
    .find((index) => !dailyIndexes.includes(index));
  assert.equal((await h.move(quests, h.a, { kind: 'quest_done', questIndex: invalidIndex }))
    .body.error, 'invalid_quest');
  await h.move(quests, h.a, { kind: 'quest_done', questIndex: dailyIndexes[0] });
  assert.equal((await h.move(quests, h.b, { kind: 'quest_done', questIndex: dailyIndexes[0] })).body.error, 'duplicate_move');
  await h.move(quests, h.b, { kind: 'quest_done', questIndex: dailyIndexes[1] });
  await h.move(quests, h.a, { kind: 'quest_done', questIndex: dailyIndexes[2] });
  const questsDone = await h.fetchGame(quests);
  assert.deepEqual(questsDone.result, { done: 3, total: 3, dateKey: day });

  const questions = await h.create('questions36', { set: 2 });
  assert.equal((await h.move(questions, h.a, { kind: 'answer', round: 0 })).body.error, 'no_realtime_actions');
  assert.equal((await h.a.api.post(`/api/games/${questions.id}/end`, { json: { result: { winner: 'fake' } } })).status, 409);
  const completed = await h.a.api.post(`/api/games/${questions.id}/end`, { json: { complete: true } });
  assert.equal(completed.status, 200);
  assert.deepEqual(completed.body.game.result, { completedBy: h.a.memberId });
});

test('commit-reveal games reject wrong phase/actor/secrets and derive signed results', async (t) => {
  const h = await harness(t);

  const truths = await h.create('twotruths', { rounds: 1 });
  const secret = '2';
  const salt = 'truth-salt';
  assert.equal((await h.move(truths, h.b, {
    kind: 'statements', round: 0, texts: ['a', 'b', 'c'], commit: sha256(secret + salt),
  })).status, 403);
  const statement = await h.move(truths, h.a, {
    kind: 'statements',
    round: 0,
    texts: ['I climbed a volcano', 'I hate chocolate', 'I juggle'],
    commit: sha256(secret + salt),
  });
  await h.move(truths, h.b, { kind: 'guess', round: 0, pick: 2 });
  const badReveal = await h.move(truths, h.a, {
    kind: 'reveal', round: 0, reveal: '1', salt, commitId: statement.body.move.id,
  });
  assert.equal(badReveal.status, 409);
  assert.equal(badReveal.body.error, 'reveal_mismatch');
  await h.move(truths, h.a, {
    kind: 'reveal', round: 0, reveal: secret, salt, commitId: statement.body.move.id,
  });
  const truthsDone = await h.fetchGame(truths);
  assert.deepEqual(truthsDone.result.scores, { [h.a.memberId]: 0, [h.b.memberId]: 1 });

  const slf = await h.create('stadtlandfluss', { rounds: 1, categories: ['Stadt'] });
  const letter = gameRulesInternals.seededShuffle([...`ABCDEFGHIJKLMNOPRSTUVWZ`], slf.payload.seed)[0];
  const answerA = `${letter}stadt`;
  const answerB = `${letter}burg`;
  const saltA = 'a';
  const saltB = 'b';
  const commitA = await h.move(slf, h.a, { kind: 'commit', round: 0, commit: sha256(answerA + saltA) });
  assert.equal((await h.move(slf, h.a, {
    kind: 'reveal', round: 0, reveal: answerA, salt: saltA, commitId: commitA.body.move.id,
  })).status, 409);
  const commitB = await h.move(slf, h.b, { kind: 'commit', round: 0, commit: sha256(answerB + saltB) });
  await h.move(slf, h.a, {
    kind: 'reveal', round: 0, reveal: answerA, salt: saltA, commitId: commitA.body.move.id,
  });
  await h.move(slf, h.b, {
    kind: 'reveal', round: 0, reveal: answerB, salt: saltB, commitId: commitB.body.move.id,
  });
  await h.move(slf, h.a, { kind: 'rate', round: 0, verdicts: [true] });
  await h.move(slf, h.b, { kind: 'rate', round: 0, verdicts: [true] });
  const slfDone = await h.fetchGame(slf);
  assert.deepEqual(slfDone.result.scores, { [h.a.memberId]: 10, [h.b.memberId]: 10 });
});

test('battleship verifies both fleets and every report before awarding a winner', async (t) => {
  const h = await harness(t);
  const game = await h.create('battleship');
  const fleetA = [[0, 1, 2, 3], [16, 24, 32], [40, 41, 42], [54, 55]];
  const fleetB = [[8, 9, 10, 11], [20, 28, 36], [45, 46, 47], [62, 63]];
  const encode = (fleet) => fleet.map((ship) => [...ship].sort((a, b) => a - b))
    .sort((a, b) => a[0] - b[0]).map((ship) => ship.join(',')).join('|');
  const layoutA = encode(fleetA);
  const layoutB = encode(fleetB);
  const commitA = await h.move(game, h.a, { kind: 'commit', commit: sha256(layoutA + 'salt-a') });
  const commitB = await h.move(game, h.b, { kind: 'commit', commit: sha256(layoutB + 'salt-b') });

  const reportFor = (cells, fleet, prior) => {
    const occupied = new Set(fleet.flat());
    const hits = cells.filter((cell) => occupied.has(cell));
    const total = new Set([...prior, ...hits]);
    const sunk = fleet.filter(
      (ship) => ship.every((cell) => total.has(cell)) && !ship.every((cell) => prior.has(cell)),
    ).map((ship) => ship.length).sort((a, b) => a - b);
    hits.forEach((cell) => prior.add(cell));
    return { hits, sunk };
  };
  const targetsA = fleetB.flat();
  const targetsB = fleetA.flat().slice(0, 10);
  const hitA = new Set();
  const hitB = new Set();
  let salvoIndex = 0;
  for (let round = 0; round < 6; round += 1) {
    const cellsA = targetsA.slice(round * 2, round * 2 + 2);
    await h.move(game, h.a, { kind: 'salvo', cells: cellsA });
    const reportA = reportFor(cellsA, fleetB, hitA);
    await h.move(game, h.b, { kind: 'report', index: salvoIndex, ...reportA });
    salvoIndex += 1;
    if (round < 5) {
      const cellsB = targetsB.slice(round * 2, round * 2 + 2);
      await h.move(game, h.b, { kind: 'salvo', cells: cellsB });
      const reportB = reportFor(cellsB, fleetA, hitB);
      await h.move(game, h.a, { kind: 'report', index: salvoIndex, ...reportB });
      salvoIndex += 1;
    }
  }
  const bad = await h.move(game, h.a, {
    kind: 'reveal', reveal: layoutA, salt: 'wrong', commitId: commitA.body.move.id,
  });
  assert.equal(bad.body.error, 'reveal_mismatch');
  await h.move(game, h.a, {
    kind: 'reveal', reveal: layoutA, salt: 'salt-a', commitId: commitA.body.move.id,
  });
  await h.move(game, h.b, {
    kind: 'reveal', reveal: layoutB, salt: 'salt-b', commitId: commitB.body.move.id,
  });
  const done = await h.fetchGame(game);
  assert.equal(done.state, 'ended');
  assert.equal(done.result.integrity, true);
  assert.equal(done.result.winner, h.a.memberId);
  assert.deepEqual(done.result.scores, { [h.a.memberId]: 1, [h.b.memberId]: 0 });
});
