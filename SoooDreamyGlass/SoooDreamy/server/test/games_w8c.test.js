// W8C — six new server-authoritative two-player games: dame (checkers),
// reversi (Othello), kaesekaestchen (dots & boxes), gomoku, mancala
// (Kalaha) and memoryduo (hidden-deck pair memory). Contract in docs/API.md
// ("W8C board & duel games"). Depth mirrors the connectfour / battleship /
// kniffel suites: per game a legal run to the server-derived result, 3+
// illegal move classes, the special rules (Schlagzwang, pass duty, extra
// turn, capture, deck secrecy) and serialization checks.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  canonicalGameResult,
  gameRulesInternals,
  validateGameMove,
} from '../src/game-rules.js';
import { client, makeApp, setupCouple, wsOpen } from './helpers.js';

const internals = gameRulesInternals;

async function startGame(a, b, type, payload = {}) {
  const created = await a.api.post('/api/games', { json: { type, payload } });
  assert.equal(created.status, 201, JSON.stringify(created.body));
  const joined = await b.api.post(`/api/games/${created.body.game.id}/join`, { json: {} });
  assert.equal(joined.status, 200, JSON.stringify(joined.body));
  return joined.body.game;
}

function storeGame(app, coupleId, gameId) {
  const couple = app.store.data.couples[coupleId];
  return { couple, game: couple.games.find((candidate) => candidate.id === gameId) };
}

async function move(who, gameId, data) {
  return who.api.post(`/api/games/${gameId}/move`, { json: { data } });
}

async function assertMove(who, gameId, data) {
  const res = await move(who, gameId, data);
  assert.equal(res.status, 201, JSON.stringify(res.body));
  return res;
}

async function assertRefused(who, gameId, data, code) {
  const res = await move(who, gameId, data);
  assert.equal(res.body.error, code, JSON.stringify(res.body));
  return res;
}

// ---------------------------------------------------------------------------
// dame

// Scripted opening (verified against the engine): quiet development, then a
// forced single capture for A and a forced DOUBLE jump for B.
const DAME_OPENING = [
  ['a', [17, 24]], ['b', [40, 33]], ['a', [10, 17]], ['b', [33, 26]],
];

test('dame: create normalizes the payload and bounds the drawPlies option', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const outOfRange = await a.api.post('/api/games', {
    json: { type: 'dame', payload: { drawPlies: 5 } },
  });
  assert.equal(outOfRange.status, 400);
  assert.equal(outOfRange.body.error, 'invalid_game_move');

  const game = await startGame(a, b, 'dame');
  assert.equal(game.payload.size, 8);
  assert.equal(game.payload.drawPlies, 40);
  assert.ok(Number.isInteger(game.payload.seed), 'server seed present');
});

test('dame: turn, ownership and path-shape violations are rejected precisely', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'dame');

  await assertRefused(b, game.id, { kind: 'move', path: [40, 33] }, 'wrong_turn');
  await assertRefused(a, game.id, { kind: 'move', path: [40, 33] }, 'invalid_game_move'); // partner's piece
  await assertRefused(a, game.id, { kind: 'move', path: [16, 25] }, 'invalid_game_move'); // light square
  await assertRefused(a, game.id, { kind: 'move', path: [17, 19] }, 'invalid_game_move'); // not diagonal
  await assertRefused(a, game.id, { kind: 'move', path: [17] }, 'invalid_game_move'); // too short
  await assertRefused(a, game.id, { kind: 'flip', path: [17, 24] }, 'invalid_game_move'); // wrong kind
  await assertMove(a, game.id, { kind: 'move', path: [17, 24] });
});

test('dame: capturing is mandatory (Schlagzwang) and removes the victim', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a, b, coupleId } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'dame');
  const who = { a, b };
  for (const [side, path] of DAME_OPENING) {
    await assertMove(who[side], game.id, { kind: 'move', path });
  }
  // B's man sits on 26 — A must jump it; every quiet move is refused.
  await assertRefused(a, game.id, { kind: 'move', path: [21, 28] }, 'capture_required');
  const capture = await assertMove(a, game.id, { kind: 'move', path: [17, 35] });
  assert.deepEqual(capture.body.move.data.captures, [26]);
  const { couple, game: raw } = storeGame(app, coupleId, game.id);
  const state = internals.dameState(raw, couple);
  assert.equal(state.board[26], null, 'the captured man is off the board');
  assert.equal(state.counts[b.memberId], 11);
});

test('dame: a multi-jump travels as ONE path and may not stop early', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'dame');
  const who = { a, b };
  for (const [side, path] of DAME_OPENING) {
    await assertMove(who[side], game.id, { kind: 'move', path });
  }
  await assertMove(a, game.id, { kind: 'move', path: [17, 35] });
  // B can now double-jump over 35 and 19 — stopping after one hop is refused.
  await assertRefused(b, game.id, { kind: 'move', path: [42, 28] }, 'capture_required');
  const double = await assertMove(b, game.id, { kind: 'move', path: [42, 28, 10] });
  assert.deepEqual(double.body.move.data.captures, [35, 19]);
});

test('dame: a deterministic full game ends server-side with a winner', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a, b, coupleId } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'dame');
  const { couple, game: raw } = storeGame(app, coupleId, game.id);
  const byId = { [a.memberId]: a, [b.memberId]: b };
  let plies = 0;
  while (raw.state === 'active' && plies < 400) {
    const state = internals.dameState(raw, couple);
    const paths = internals.dameLegalPaths(state);
    paths.sort((x, y) => (y.length - x.length) || (JSON.stringify(x) < JSON.stringify(y) ? -1 : 1));
    await assertMove(byId[state.turn], game.id, { kind: 'move', path: paths[0] });
    plies += 1;
  }
  assert.equal(raw.state, 'ended', 'the game ends without any /end call');
  assert.equal(raw.result.winner, b.memberId);
  assert.equal(raw.result.scores[b.memberId], 1);
  assert.equal(raw.result.draw, false);
  assert.ok(raw.moves.some((m) => m.data.captures.length >= 2), 'multi-jumps occurred');
  assert.ok(raw.moves.some((m) => m.data.promoted === true), 'a promotion occurred');
  // A forged client result on /end is ignored — the canonical result stays.
  const ended = await a.api.post(`/api/games/${game.id}/end`, {
    json: { result: { winner: a.memberId } },
  });
  assert.equal(ended.body.game.result.winner, b.memberId);
});

test('dame: capture-free plies drain into a draw (drawPlies option)', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'dame', { drawPlies: 10 });
  assert.equal(game.payload.drawPlies, 10);
  const line = [
    ['a', [17, 26]], ['b', [42, 35]], ['a', [8, 17]], ['b', [46, 39]],
    ['a', [1, 8]], ['b', [49, 42]], ['a', [19, 28]], ['b', [53, 46]],
    ['a', [10, 19]], ['b', [39, 30]],
  ];
  const who = { a, b };
  let last = null;
  for (const [side, path] of line) {
    last = await assertMove(who[side], game.id, { kind: 'move', path });
  }
  assert.equal(last.body.game.state, 'ended');
  assert.equal(last.body.game.result.draw, true);
  assert.equal(last.body.game.result.winner, null);
  assert.deepEqual(last.body.game.result.pieces, { [a.memberId]: 12, [b.memberId]: 12 });
});

// ---------------------------------------------------------------------------
// reversi

test('reversi: placement legality — occupied, no-flip, pass duty and turn order', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'reversi');
  assert.equal(game.payload.size, 8);

  await assertRefused(b, game.id, { kind: 'place', index: 19 }, 'wrong_turn');
  await assertRefused(a, game.id, { kind: 'place', index: 27 }, 'duplicate_move'); // occupied
  await assertRefused(a, game.id, { kind: 'place', index: 0 }, 'no_flip'); // flips nothing
  await assertRefused(a, game.id, { kind: 'pass' }, 'pass_not_allowed'); // legal moves exist
  await assertRefused(a, game.id, { kind: 'place', index: 64 }, 'invalid_game_move');
  await assertRefused(a, game.id, { kind: 'swap' }, 'invalid_game_move');
});

test('reversi: placements flip discs server-side and the flips are stored', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a, b, coupleId } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'reversi');
  const { couple, game: raw } = storeGame(app, coupleId, game.id);
  const first = await assertMove(a, game.id, { kind: 'place', index: 19 });
  assert.deepEqual(first.body.move.data.flips, [27]);
  assert.equal(internals.reversiState(raw, couple).board[27], a.memberId,
    'the flipped disc changed owner');
  // B's reply flips the very same disc back (diagonal through 18–27–36).
  const second = await assertMove(b, game.id, { kind: 'place', index: 18 });
  assert.deepEqual(second.body.move.data.flips, [27]);
  assert.equal(internals.reversiState(raw, couple).board[27], b.memberId,
    'the disc flipped back to B');
});

test('reversi: a full game passes when stuck and ends by disc count', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a, b, coupleId } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'reversi');
  const { couple, game: raw } = storeGame(app, coupleId, game.id);
  const byId = { [a.memberId]: a, [b.memberId]: b };
  let passes = 0;
  let plies = 0;
  while (raw.state === 'active' && plies < 130) {
    const state = internals.reversiState(raw, couple);
    const legal = internals.reversiLegalMoves(state.board, state.turn);
    if (legal.length === 0) {
      await assertMove(byId[state.turn], game.id, { kind: 'pass' });
      passes += 1;
    } else {
      await assertMove(byId[state.turn], game.id, { kind: 'place', index: legal[0] });
    }
    plies += 1;
  }
  assert.equal(raw.state, 'ended');
  assert.ok(passes >= 1, 'at least one mid-game pass was required and accepted');
  const scores = raw.result.scores;
  assert.equal(scores[a.memberId] + scores[b.memberId], 64, 'the board is full');
  assert.equal(raw.result.winner, b.memberId);
  assert.equal(scores[b.memberId], 45);
});

// ---------------------------------------------------------------------------
// kaesekaestchen

// 2×2 board: 12 edges (h 0–5, v 6–11); B closes three boxes, A one.
const KAESE_SCRIPT = [
  ['a', 0, 0], ['b', 1, 0], ['a', 2, 0], ['b', 3, 0], ['a', 6, 0],
  ['b', 7, 1], ['b', 8, 1], ['b', 4, 0], ['a', 9, 0], ['b', 10, 1],
  ['b', 5, 0], ['a', 11, 1],
];

test('kaesekaestchen: the size option is bounded and shapes the edge space', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const tooBig = await a.api.post('/api/games', {
    json: { type: 'kaesekaestchen', payload: { size: 7 } },
  });
  assert.equal(tooBig.status, 400);
  assert.equal(tooBig.body.error, 'invalid_game_move');

  const game = await startGame(a, b, 'kaesekaestchen');
  assert.equal(game.payload.size, 5);
  await assertRefused(a, game.id, { kind: 'edge', edge: 60 }, 'invalid_game_move'); // 5×5 has 60 edges (0–59)
});

test('kaesekaestchen: closing a box scores it and grants an extra turn', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'kaesekaestchen', { size: 2 });
  const who = { a, b };
  for (const [side, edge, boxes] of KAESE_SCRIPT.slice(0, 6)) {
    const res = await assertMove(who[side], game.id, { kind: 'edge', edge });
    assert.equal(res.body.move.data.boxes.length, boxes, `edge ${edge} closes ${boxes} box(es)`);
  }
  // B just closed box 0 — the turn stays with B, A is refused.
  await assertRefused(a, game.id, { kind: 'edge', edge: 8 }, 'wrong_turn');
  const chain = await assertMove(b, game.id, { kind: 'edge', edge: 8 });
  assert.deepEqual(chain.body.move.data.boxes, [1], 'the follow-up closes box 1');
});

test('kaesekaestchen: illegal classes — taken edge, range, kind, turn', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'kaesekaestchen', { size: 2 });
  await assertMove(a, game.id, { kind: 'edge', edge: 0 });
  await assertRefused(b, game.id, { kind: 'edge', edge: 0 }, 'duplicate_move');
  await assertRefused(b, game.id, { kind: 'edge', edge: 12 }, 'invalid_game_move');
  await assertRefused(b, game.id, { kind: 'box', edge: 1 }, 'invalid_game_move');
  await assertRefused(a, game.id, { kind: 'edge', edge: 1 }, 'wrong_turn');
});

test('kaesekaestchen: the full 2×2 game ends with server-derived box scores', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'kaesekaestchen', { size: 2 });
  const who = { a, b };
  let last = null;
  for (const [side, edge, boxes] of KAESE_SCRIPT) {
    last = await assertMove(who[side], game.id, { kind: 'edge', edge });
    assert.equal(last.body.move.data.boxes.length, boxes);
  }
  assert.equal(last.body.game.state, 'ended');
  assert.equal(last.body.game.result.scores[b.memberId], 3);
  assert.equal(last.body.game.result.scores[a.memberId], 1);
  assert.equal(last.body.game.result.winner, b.memberId);
  assert.equal(last.body.game.result.boxes, 4);
});

test('kaesekaestchen: the persisted move list replays into the stored result', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'kaesekaestchen', { size: 2 });
  const who = { a, b };
  for (const [side, edge] of KAESE_SCRIPT) {
    await assertMove(who[side], game.id, { kind: 'edge', edge });
  }
  // Replay contract: the serialized session (payload + ordered moves) fed
  // back through the shared reducer reproduces the canonical result.
  const fetched = (await b.api.get(`/api/games/${game.id}`)).body.game;
  const replayCouple = { members: [{ id: a.memberId }, { id: b.memberId }] };
  const replayed = canonicalGameResult({ game: fetched, couple: replayCouple });
  assert.equal(replayed.complete, true);
  assert.deepEqual(replayed.result, fetched.result);
});

// ---------------------------------------------------------------------------
// gomoku

test('gomoku: exactly five in a row wins with a server-derived result', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'gomoku');
  assert.equal(game.payload.size, 15);
  assert.equal(game.payload.winLength, 5);
  const script = [
    ['a', 0], ['b', 100], ['a', 1], ['b', 101], ['a', 2], ['b', 102],
    ['a', 3], ['b', 103],
  ];
  const who = { a, b };
  for (const [side, index] of script) {
    await assertMove(who[side], game.id, { kind: 'place', index });
  }
  const winning = await assertMove(a, game.id, { kind: 'place', index: 4 });
  assert.equal(winning.body.game.state, 'ended');
  assert.equal(winning.body.game.result.winner, a.memberId);
  assert.equal(winning.body.game.result.scores[a.memberId], 1);
  assert.equal(winning.body.game.result.draw, false);
  const late = await move(b, game.id, { kind: 'place', index: 104 });
  assert.equal(late.body.error, 'game_not_active');
});

test('gomoku: an overline of six or more does NOT win', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'gomoku');
  const script = [
    ['a', 0], ['b', 196], ['a', 1], ['b', 198], ['a', 2], ['b', 200],
    ['a', 3], ['b', 202], ['a', 5], ['b', 204], ['a', 6], ['b', 206],
  ];
  const who = { a, b };
  for (const [side, index] of script) {
    await assertMove(who[side], game.id, { kind: 'place', index });
  }
  // Filling the gap makes SEVEN contiguous stones — not a win.
  const overline = await assertMove(a, game.id, { kind: 'place', index: 4 });
  assert.equal(overline.body.game, undefined, 'the game continues');
  // A clean exact five (column 0, rows 2–6) still wins later.
  const finish = [
    ['b', 208], ['a', 30], ['b', 210], ['a', 45], ['b', 212], ['a', 60],
    ['b', 214], ['a', 75], ['b', 182],
  ];
  for (const [side, index] of finish) {
    await assertMove(who[side], game.id, { kind: 'place', index });
  }
  const winning = await assertMove(a, game.id, { kind: 'place', index: 90 });
  assert.equal(winning.body.game.state, 'ended');
  assert.equal(winning.body.game.result.winner, a.memberId);
});

test('gomoku: illegal classes — occupied stone, range, kind, turn', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'gomoku');
  await assertMove(a, game.id, { kind: 'place', index: 112 });
  await assertRefused(b, game.id, { kind: 'place', index: 112 }, 'duplicate_move');
  await assertRefused(b, game.id, { kind: 'place', index: 225 }, 'invalid_game_move');
  await assertRefused(b, game.id, { kind: 'drop', index: 0 }, 'invalid_game_move');
  await assertRefused(a, game.id, { kind: 'place', index: 0 }, 'wrong_turn');
  const second = await a.api.post('/api/games', { json: { type: 'gomoku' } });
  assert.equal(second.status, 409);
  assert.equal(second.body.error, 'game_in_progress');
});

// ---------------------------------------------------------------------------
// mancala

test('mancala: the stones option is bounded and the payload is descriptive', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const tooMany = await a.api.post('/api/games', {
    json: { type: 'mancala', payload: { stones: 7 } },
  });
  assert.equal(tooMany.status, 400);
  assert.equal(tooMany.body.error, 'invalid_game_move');

  const game = await startGame(a, b, 'mancala', { stones: 3 });
  assert.equal(game.payload.pits, 6);
  assert.equal(game.payload.stones, 3);
});

test('mancala: an own-store landing grants an extra turn', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'mancala');
  await assertMove(a, game.id, { kind: 'sow', pit: 0 });
  await assertMove(b, game.id, { kind: 'sow', pit: 0 });
  // Pit 1 now holds 5 stones — the last one lands exactly in A's store.
  const extra = await assertMove(a, game.id, { kind: 'sow', pit: 1 });
  assert.equal(extra.body.move.data.extraTurn, true);
  await assertRefused(b, game.id, { kind: 'sow', pit: 1 }, 'wrong_turn');
  const followUp = await assertMove(a, game.id, { kind: 'sow', pit: 2 });
  assert.equal(followUp.body.move.data.extraTurn, false);
});

test('mancala: sowing skips the opponent store (13-cell track)', () => {
  // Rule-level check with a synthetic session: 6 stones per pit, A sows
  // pit 0 (lands in the store — extra turn), then sows pit 5 whose seven
  // stones would cross the opponent store if it were on the track.
  const A = 'm_aaa';
  const B = 'm_bbb';
  const couple = { members: [{ id: A }, { id: B }] };
  const game = { type: 'mancala', createdBy: A, payload: { pits: 6, stones: 6 }, moves: [] };
  const first = validateGameMove({ game, couple, memberId: A, data: { kind: 'sow', pit: 0 } });
  assert.equal(first.extraTurn, true);
  game.moves.push({ memberId: A, data: first });
  const second = validateGameMove({ game, couple, memberId: A, data: { kind: 'sow', pit: 5 } });
  game.moves.push({ memberId: A, data: second });
  const state = internals.mancalaState(game, couple);
  assert.equal(state.stores[A], 2, 'own store fed on both passes');
  assert.equal(state.stores[B], 0, 'the opponent store is skipped');
  assert.deepEqual(state.pits[B], [7, 7, 7, 7, 7, 7], 'six of the seven stones crossed into the opponent row');
});

test('mancala: illegal classes — empty pit, range, kind, turn', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'mancala');
  await assertRefused(b, game.id, { kind: 'sow', pit: 0 }, 'wrong_turn');
  await assertRefused(a, game.id, { kind: 'sow', pit: 6 }, 'invalid_game_move');
  await assertRefused(a, game.id, { kind: 'harvest', pit: 0 }, 'invalid_game_move');
  await assertMove(a, game.id, { kind: 'sow', pit: 0 });
  await assertMove(b, game.id, { kind: 'sow', pit: 0 });
  await assertRefused(a, game.id, { kind: 'sow', pit: 0 }, 'empty_pit');
});

test('mancala: captures land in the store and the end sweep decides the game', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'mancala');
  // Deterministic script (greedy lowest pit): A's last sow drops its final
  // stone into A's emptied pit 0 opposite B's loaded pit 5 — capture — and
  // empties A's row, so B sweeps the rest.
  const script = [
    ['a', 0], ['b', 0], ['a', 1], ['a', 2], ['b', 0], ['a', 3], ['b', 0],
    ['a', 4], ['b', 0],
  ];
  const who = { a, b };
  for (const [side, pit] of script) {
    await assertMove(who[side], game.id, { kind: 'sow', pit });
  }
  const final = await assertMove(a, game.id, { kind: 'sow', pit: 5 });
  assert.equal(final.body.move.data.captured, 7, 'the capture took the opposite pit');
  assert.equal(final.body.game.state, 'ended');
  assert.deepEqual(final.body.game.result.scores, {
    [a.memberId]: 12,
    [b.memberId]: 36,
  });
  assert.equal(final.body.game.result.winner, b.memberId);
});

// ---------------------------------------------------------------------------
// memoryduo

test('memoryduo: the deck seed never reaches a client view', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a, b, coupleId } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const created = await a.api.post('/api/games', { json: { type: 'memoryduo' } });
  assert.equal(created.status, 201);
  assert.deepEqual(
    Object.keys(created.body.game.payload).sort(),
    ['pairs', 'seedServer', 'size'],
    'the create response carries no seed and no deck',
  );
  assert.equal(created.body.game.payload.pairs, 18);
  assert.equal(created.body.game.payload.size, 6);

  const frame = await bSock.waitFor('game_created');
  assert.equal(frame.payload.game.payload.seed, undefined, 'the broadcast is redacted too');

  await b.api.post(`/api/games/${created.body.game.id}/join`, { json: {} });
  const fetched = await b.api.get(`/api/games/${created.body.game.id}`);
  assert.equal(fetched.body.game.payload.seed, undefined);

  // The store itself keeps the seed — the redaction is a view concern.
  const { game: raw } = storeGame(app, coupleId, created.body.game.id);
  assert.ok(Number.isInteger(raw.payload.seed));
  const deck = internals.memoryduoDeck(raw);
  assert.equal(deck.length, 36);
  assert.equal(new Set(deck).size, 18, '18 distinct faces, two cards each');
});

test('memoryduo: flips reveal faces server-side; a match scores and keeps the turn', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a, b, coupleId } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'memoryduo');
  const { game: raw } = storeGame(app, coupleId, game.id);
  const deck = internals.memoryduoDeck(raw);
  const pairOf = (face) => deck.flatMap((value, index) => (value === face ? [index] : []));
  const [first, second] = pairOf(deck[0]);

  const flip1 = await assertMove(a, game.id, { kind: 'flip', index: first });
  assert.equal(flip1.body.move.data.face, deck[first], 'the server injects the face');
  const flip2 = await assertMove(a, game.id, { kind: 'flip', index: second });
  assert.equal(flip2.body.move.data.match, true);
  assert.equal(flip2.body.move.data.first, first);

  // Match ⇒ extra turn: B is still locked out, A mismatches, then B moves.
  await assertRefused(b, game.id, { kind: 'flip', index: 30 }, 'wrong_turn');
  const remaining = deck.map((_, index) => index).filter((i) => i !== first && i !== second);
  const misA = remaining[0];
  const misB = remaining.find((i) => deck[i] !== deck[misA]);
  await assertMove(a, game.id, { kind: 'flip', index: misA });
  const miss = await assertMove(a, game.id, { kind: 'flip', index: misB });
  assert.equal(miss.body.move.data.match, false);
  await assertRefused(a, game.id, { kind: 'flip', index: 0 }, 'wrong_turn');
  await assertMove(b, game.id, { kind: 'flip', index: misA });
});

test('memoryduo: illegal classes — matched card, open card, range, kind', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a, b, coupleId } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'memoryduo');
  const { game: raw } = storeGame(app, coupleId, game.id);
  const deck = internals.memoryduoDeck(raw);
  const [first, second] = deck.flatMap((value, index) => (value === deck[0] ? [index] : []));

  await assertRefused(a, game.id, { kind: 'flip', index: 36 }, 'invalid_game_move');
  await assertRefused(a, game.id, { kind: 'peek', index: 0 }, 'invalid_game_move');
  await assertMove(a, game.id, { kind: 'flip', index: first });
  await assertRefused(a, game.id, { kind: 'flip', index: first }, 'invalid_game_move'); // already open
  await assertMove(a, game.id, { kind: 'flip', index: second });
  await assertRefused(a, game.id, { kind: 'flip', index: first }, 'already_matched');
});

test('memoryduo: clientMoveId retries never double-flip', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'memoryduo');
  const body = { data: { kind: 'flip', index: 7 }, clientMoveId: 'flip-7' };
  const first = await a.api.post(`/api/games/${game.id}/move`, { json: body });
  assert.equal(first.status, 201);
  const retry = await a.api.post(`/api/games/${game.id}/move`, { json: body });
  assert.equal(retry.status, 200);
  assert.equal(retry.body.duplicate, true);
  assert.equal(retry.body.move.id, first.body.move.id);
  const fetched = await b.api.get(`/api/games/${game.id}`);
  assert.equal(fetched.body.game.moves.length, 1, 'the retry stored nothing new');
  assert.equal(fetched.body.game.moves[0].data.face, first.body.move.data.face,
    'revealed faces stay visible to both members');
});

test('memoryduo: a perfect run chains extra turns to an 18:0 result', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a, b, coupleId } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'memoryduo');
  const { game: raw } = storeGame(app, coupleId, game.id);
  const deck = internals.memoryduoDeck(raw);
  const byFace = new Map();
  deck.forEach((face, index) => byFace.set(face, [...(byFace.get(face) ?? []), index]));
  let last = null;
  for (const [first, second] of byFace.values()) {
    await assertMove(a, game.id, { kind: 'flip', index: first });
    last = await assertMove(a, game.id, { kind: 'flip', index: second });
    assert.equal(last.body.move.data.match, true);
  }
  assert.equal(last.body.game.state, 'ended');
  assert.equal(last.body.game.result.scores[a.memberId], 18);
  assert.equal(last.body.game.result.scores[b.memberId], 0);
  assert.equal(last.body.game.result.winner, a.memberId);
  assert.equal(last.body.game.result.pairs, 18);
  assert.equal(last.body.game.payload.seed, undefined, 'the ended view stays redacted');
});

// ---------------------------------------------------------------------------
// cross-cutting: registration, normalization, replay, lease (12.0), season

test('all six new types are registered end-to-end (create, echo, decline)', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  for (const type of ['dame', 'reversi', 'kaesekaestchen', 'gomoku', 'mancala', 'memoryduo']) {
    const created = await a.api.post('/api/games', { json: { type } });
    assert.equal(created.status, 201, `${type}: ${JSON.stringify(created.body)}`);
    assert.equal(created.body.game.type, type);
    assert.equal(created.body.game.rulesVersion, 5);
    assert.equal(created.body.game.resultAuthority, 'server');
    const declined = await b.api.post(`/api/games/${created.body.game.id}/end`, { json: {} });
    assert.equal(declined.status, 200);
    assert.equal(declined.body.game.result.declined, true);
  }
});

test('dame: stored moves carry only the normalized server shape', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'dame');
  const res = await assertMove(a, game.id, {
    kind: 'move', path: [17, 24], cheat: true, captures: [40], promoted: true,
  });
  assert.deepEqual(res.body.move.data, {
    kind: 'move', path: [17, 24], captures: [], promoted: false,
  }, 'client-claimed fields are discarded, derived fields recomputed');
});

test('reversi: the initial board and turn follow the documented contract', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a, b, coupleId } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'reversi');
  const { couple, game: raw } = storeGame(app, coupleId, game.id);
  const state = internals.reversiState(raw, couple);
  assert.equal(state.board[28], a.memberId);
  assert.equal(state.board[35], a.memberId);
  assert.equal(state.board[27], b.memberId);
  assert.equal(state.board[36], b.memberId);
  assert.equal(state.turn, a.memberId, 'the creator opens');
  assert.equal(state.board.filter(Boolean).length, 4);
});

test('gomoku: the persisted move list replays into the stored result', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'gomoku');
  const script = [
    ['a', 0], ['b', 100], ['a', 1], ['b', 101], ['a', 2], ['b', 102],
    ['a', 3], ['b', 103], ['a', 4],
  ];
  const who = { a, b };
  for (const [side, index] of script) {
    await assertMove(who[side], game.id, { kind: 'place', index });
  }
  const fetched = (await b.api.get(`/api/games/${game.id}`)).body.game;
  const replayed = canonicalGameResult({
    game: fetched,
    couple: { members: [{ id: a.memberId }, { id: b.memberId }] },
  });
  assert.equal(replayed.complete, true);
  assert.deepEqual(replayed.result, fetched.result);
});

test('memoryduo: a forfeit ends the game with the partner as winner', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'memoryduo');
  await assertMove(a, game.id, { kind: 'flip', index: 0 });
  const surrendered = await b.api.post(`/api/games/${game.id}/end`, { json: { forfeit: true } });
  assert.equal(surrendered.status, 200);
  assert.equal(surrendered.body.game.state, 'ended');
  assert.equal(surrendered.body.game.result.winner, a.memberId);
  assert.equal(surrendered.body.game.result.forfeitBy, b.memberId);
  assert.equal(surrendered.body.game.payload.seed, undefined, 'still redacted after forfeit');
});

test('input lease guards the new games: second device refused, takeover flips it', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const issued = await a.api.post('/api/sessions/link-code');
  assert.equal(issued.status, 201);
  const linked = await client(baseUrl).post('/api/couples/link', {
    json: { code: issued.body.linkCode, deviceName: 'Mias iPad', deviceId: 'mia-ipad-01' },
  });
  assert.equal(linked.status, 200);
  const ipad = client(baseUrl, linked.body.token);

  const game = await startGame(a, b, 'gomoku');
  await assertMove(a, game.id, { kind: 'place', index: 0 });
  await assertMove(b, game.id, { kind: 'place', index: 100 });

  const refused = await ipad.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'place', index: 1 } },
  });
  assert.equal(refused.status, 409);
  assert.equal(refused.body.error, 'game_lease_held');
  assert.equal(refused.body.details.gameId, game.id);
  assert.ok(refused.body.details.lease.sessionSuffix, 'the holder is attached');

  const takeover = await ipad.post(`/api/games/${game.id}/takeover`);
  assert.equal(takeover.status, 200);
  const moved = await ipad.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'place', index: 1 } },
  });
  assert.equal(moved.status, 201);
});

test('new games feed the season ledger with their server scores', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'kaesekaestchen', { size: 2 });
  const who = { a, b };
  for (const [side, edge] of KAESE_SCRIPT) {
    await assertMove(who[side], game.id, { kind: 'edge', edge });
  }
  const season = await a.api.get('/api/games/season');
  const match = season.body.matches.find((entry) => entry.id === game.id);
  assert.ok(match, 'the ended session appears in the ledger');
  assert.equal(match.type, 'kaesekaestchen');
  assert.equal(match.scores[b.memberId], 3);
  assert.equal(match.scores[a.memberId], 1);
});
