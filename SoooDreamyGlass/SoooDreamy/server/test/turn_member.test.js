// Sync contract c (FX-S) — `serializeGame` carries a server-authoritative
// `turnMemberId` for EVERY type (null when ended / in the lobby / not
// applicable), and the "Du bist dran" surfaces (turn push, inbox games
// bucket) use it. The eval battery's repro: the old code derived "whose turn"
// from the LAST mover, so extra moves (Mancala store landing, Käsekästchen
// box, Memory match) pushed the WRONG member.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple, wsOpen } from './helpers.js';
import { gameRulesInternals } from '../src/game-rules.js';

const TOKEN_A = 'aa'.repeat(32);
const TOKEN_B = 'bb'.repeat(32);

async function startGame(a, b, type, payload = {}) {
  const created = await a.api.post('/api/games', { json: { type, payload } });
  assert.equal(created.status, 201, JSON.stringify(created.body));
  const joined = await b.api.post(`/api/games/${created.body.game.id}/join`, { json: {} });
  assert.equal(joined.status, 200, JSON.stringify(joined.body));
  return { created: created.body.game, game: joined.body.game };
}

async function move(who, gameId, data) {
  const res = await who.api.post(`/api/games/${gameId}/move`, { json: { data } });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  return res;
}

async function waitFor(check) {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    if (check()) return;
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
  assert.fail('timed out waiting for asynchronous push delivery');
}

async function settle(ms = 50) {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

async function pushCouple(t) {
  const deliveries = [];
  const provider = { async send(request) { deliveries.push(request); } };
  const { baseUrl, app } = await makeApp(t, { pushProvider: provider });
  const { a, b } = await setupCouple(baseUrl);
  await a.api.post('/api/push-devices/current', {
    json: { apnsToken: TOKEN_A, environment: 'development', bundleId: 'app.sooodreamy.ios', language: 'en' },
  });
  await b.api.post('/api/push-devices/current', {
    json: { apnsToken: TOKEN_B, environment: 'development', bundleId: 'app.sooodreamy.ios', language: 'de' },
  });
  return { deliveries, app, a, b };
}

test('serializeGame carries turnMemberId through the whole Gomoku lifecycle', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const { created, game } = await startGame(a, b, 'gomoku');

  assert.equal(created.turnMemberId, null, 'lobby games have no turn yet');
  assert.equal(game.turnMemberId, a.memberId, 'the creator opens');

  await move(a, game.id, { kind: 'place', index: 0 });
  // Both the single fetch and the history list agree the partner is up.
  assert.equal((await b.api.get(`/api/games/${game.id}`)).body.game.turnMemberId, b.memberId);
  const listed = (await a.api.get('/api/games')).body.games.find((g) => g.id === game.id);
  assert.equal(listed.turnMemberId, b.memberId);

  const script = [
    ['b', 100], ['a', 1], ['b', 101], ['a', 2], ['b', 102], ['a', 3], ['b', 103],
  ];
  const who = { a, b };
  for (const [player, index] of script) await move(who[player], game.id, { kind: 'place', index });
  const winning = await move(a, game.id, { kind: 'place', index: 4 });
  assert.equal(winning.body.game.state, 'ended');
  assert.equal(winning.body.game.turnMemberId, null, 'ended games have no turn');
});

test('EVAL repro: a Mancala store landing keeps turnMemberId with the mover (extra move)', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const { game } = await startGame(a, b, 'mancala');

  const fetchTurn = async () => (await a.api.get(`/api/games/${game.id}`)).body.game.turnMemberId;
  await move(a, game.id, { kind: 'sow', pit: 0 });
  await move(b, game.id, { kind: 'sow', pit: 0 });
  // Pit 1 now holds 5 stones — the last one lands exactly in A's store.
  const extra = await move(a, game.id, { kind: 'sow', pit: 1 });
  assert.equal(extra.body.move.data.extraTurn, true);
  assert.equal(await fetchTurn(), a.memberId, 'the extra move keeps A up');

  // The follow-up sow passes normally.
  const followUp = await move(a, game.id, { kind: 'sow', pit: 2 });
  assert.equal(followUp.body.move.data.extraTurn, false);
  assert.equal(await fetchTurn(), b.memberId);
});

test('turnMemberId survives a Käsekästchen box chain and is null for dailyquests', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const { game } = await startGame(a, b, 'kaesekaestchen', { size: 2 });
  const who = { a, b };
  // Verified opening on the 2×2 board: B's sixth edge (7) closes box 0.
  const script = [['a', 0], ['b', 1], ['a', 2], ['b', 3], ['a', 6]];
  for (const [player, edge] of script) await move(who[player], game.id, { kind: 'edge', edge });
  const boxed = await move(b, game.id, { kind: 'edge', edge: 7 });
  assert.equal(boxed.body.move.data.boxes.length, 1);
  const after = (await a.api.get(`/api/games/${game.id}`)).body.game;
  assert.equal(after.turnMemberId, b.memberId, 'closing a box keeps B up');

  // Checklist types have no turn — dailyquests always serializes null.
  const quests = await a.api.post('/api/games', { json: { type: 'dailyquests' } });
  await a.api.post(`/api/games/${quests.body.game.id}/join`, { json: {} });
  const fetched = await a.api.get(`/api/games/${quests.body.game.id}`);
  assert.equal(fetched.body.game.turnMemberId, null);
});

test('EVAL repro (no-turn reconnect): dailyquests serializes an EXPLICIT null after the partner moved', async (t) => {
  // The client reconciles via REST after every socket-welcome and reads the
  // fetched sessions' three-state turnMemberId. On a checklist where the
  // PARTNER made the last move, the key must be PRESENT with an explicit
  // null — a missing key would let the client fall back to the last-mover
  // heuristic and resurrect "du bist dran" on a game that awaits nobody.
  const { baseUrl } = await makeApp(t);
  const { a, b, coupleId } = await setupCouple(baseUrl);
  const today = new Date().toISOString().slice(0, 10);
  const created = await a.api.post('/api/games', { json: { type: 'dailyquests', payload: { dateKey: today } } });
  const gameId = created.body.game.id;
  await b.api.post(`/api/games/${gameId}/join`, { json: {} });

  // The PARTNER (B) checks a quest — the last move is not A's.
  const questIndex = gameRulesInternals.dailyQuestIndexes(coupleId, today)[0];
  const moved = await b.api.post(`/api/games/${gameId}/move`, {
    json: { data: { kind: 'quest_done', questIndex } },
  });
  assert.equal(moved.status, 201, JSON.stringify(moved.body));
  assert.ok('turnMemberId' in moved.body, 'the move response names the verdict');
  assert.equal(moved.body.turnMemberId, null);

  // A's reconnect reconcile: both the single fetch and the open list carry
  // the key EXPLICITLY (null value, never absent).
  const fetched = (await a.api.get(`/api/games/${gameId}`)).body.game;
  assert.ok('turnMemberId' in fetched, 'single fetch: key present');
  assert.equal(fetched.turnMemberId, null);
  const listed = (await a.api.get('/api/games')).body.games.find((g) => g.id === gameId);
  assert.ok('turnMemberId' in listed, 'list fetch: key present');
  assert.equal(listed.turnMemberId, null);

  // And the digest agrees: nobody is awaited on a checklist.
  const since = new Date(Date.now() - 60_000).toISOString();
  const inboxA = (await a.api.get(`/api/inbox?since=${encodeURIComponent(since)}`)).body.games;
  assert.equal(inboxA.count, 0, 'the partner’s checklist move must not summon A');
});

test('EVAL repro: the Mancala extra move pushes "your turn" to the SAME member, the handover to the other', async (t) => {
  const { deliveries, app, a, b } = await pushCouple(t);
  const created = await a.api.post('/api/games', { json: { type: 'mancala' } });
  const gameId = created.body.game.id;
  await b.api.post(`/api/games/${gameId}/join`, { json: {} });
  await waitFor(() => deliveries.length === 1); // invitation push to B

  // A opens → B is newly awaited → push to B.
  await move(a, gameId, { kind: 'sow', pit: 0 });
  await waitFor(() => deliveries.length === 2);
  assert.equal(deliveries[1].token, TOKEN_B);

  // B answers → handover to A → push to A.
  await move(b, gameId, { kind: 'sow', pit: 0 });
  await waitFor(() => deliveries.length === 3);
  assert.equal(deliveries[2].token, TOKEN_A);

  // Rewind A's hourly throttle, then sow pit 1: the last stone lands in A's
  // store — EXTRA MOVE. The old last-mover heuristic pushed B here ("your
  // turn" for a turn B never got); the contract pushes A ("you're up again").
  const couple = Object.values(app.store.data.couples)[0];
  const game = couple.games.find((g) => g.id === gameId);
  game.turnPushAt[a.memberId] = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString();
  const extra = await move(a, gameId, { kind: 'sow', pit: 1 });
  assert.equal(extra.body.move.data.extraTurn, true);
  await waitFor(() => deliveries.length === 4);
  assert.equal(deliveries[3].token, TOKEN_A, 'the extra move pushes the MOVER, not the partner');
  assert.match(deliveries[3].payload.aps.alert.title, /^Your turn/);
  assert.match(deliveries[3].payload.aps.alert.body, /Extra move/);

  // The follow-up sow hands over normally → push to B (throttle rewound).
  game.turnPushAt[b.memberId] = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString();
  await move(a, gameId, { kind: 'sow', pit: 2 });
  await waitFor(() => deliveries.length === 5);
  assert.equal(deliveries[4].token, TOKEN_B);
  assert.match(deliveries[4].payload.aps.alert.body, /Mia/);
  await settle();
  assert.equal(deliveries.length, 5);
});

test('EVAL repro (two devices): the game_move frame carries turnMemberId through a Mancala extra move', async (t) => {
  // Re-Eval Runde 2, Fund 4: the live fanout used to carry only gameId+move,
  // so every connected device fell back to the "last mover" heuristic — and
  // showed the WRONG turn after an extra move. The frame now carries the
  // server verdict (additive). Two devices listen: A's second device and B.
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSecond = await wsOpen(baseUrl, a.token, t);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await aSecond.waitFor('welcome');
  await bSock.waitFor('welcome');
  const { game } = await startGame(a, b, 'mancala');

  // Opening sows: normal handovers — the frame says so on BOTH devices.
  const opened = await move(a, game.id, { kind: 'sow', pit: 0 });
  assert.equal(opened.body.turnMemberId, b.memberId, 'the 201 carries the verdict too');
  for (const sock of [aSecond, bSock]) {
    const frame = await sock.waitFor('game_move');
    assert.equal(frame.payload.gameId, game.id);
    assert.equal(frame.payload.turnMemberId, b.memberId);
  }
  await move(b, game.id, { kind: 'sow', pit: 0 });
  for (const sock of [aSecond, bSock]) {
    assert.equal((await sock.waitFor('game_move')).payload.turnMemberId, a.memberId);
  }

  // The extra move (store landing): the verdict STAYS with A — the exact
  // case the last-mover fallback got wrong on live frames.
  const extra = await move(a, game.id, { kind: 'sow', pit: 1 });
  assert.equal(extra.body.move.data.extraTurn, true);
  assert.equal(extra.body.turnMemberId, a.memberId);
  for (const sock of [aSecond, bSock]) {
    assert.equal((await sock.waitFor('game_move')).payload.turnMemberId, a.memberId);
  }

  // The follow-up sow hands over normally.
  await move(a, game.id, { kind: 'sow', pit: 2 });
  for (const sock of [aSecond, bSock]) {
    assert.equal((await sock.waitFor('game_move')).payload.turnMemberId, b.memberId);
  }
});

test('the finishing move broadcasts an explicit null verdict (and the duplicate replay carries one)', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');
  const { game } = await startGame(a, b, 'gomoku');

  const script = [
    ['a', 0], ['b', 100], ['a', 1], ['b', 101], ['a', 2], ['b', 102], ['a', 3], ['b', 103],
  ];
  const who = { a, b };
  for (const [player, index] of script) await move(who[player], game.id, { kind: 'place', index });
  const winning = await a.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'place', index: 4 }, clientMoveId: 'final-stone' },
  });
  assert.equal(winning.status, 201);
  assert.equal(winning.body.turnMemberId, null, 'a finished board awaits nobody');
  const finalFrame = await bSock.waitFor('game_move', (m) => m.payload.move.data.index === 4);
  assert.equal(finalFrame.payload.turnMemberId, null,
    'the frame must say "nobody" EXPLICITLY — a missing field would trigger the last-mover fallback');

  // Retry contract (sync contract b): the duplicate replay agrees.
  const replay = await a.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'place', index: 4 }, clientMoveId: 'final-stone' },
  });
  assert.equal(replay.status, 200);
  assert.equal(replay.body.duplicate, true);
  assert.equal(replay.body.turnMemberId, null);
});

test('EVAL repro: the inbox games bucket follows turnMemberId through a Mancala extra move', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const since = new Date(Date.now() - 60_000).toISOString();
  const inbox = (who) => who.api.get(`/api/inbox?since=${encodeURIComponent(since)}`).then((r) => r.body.games);
  const { game } = await startGame(a, b, 'mancala');

  await move(a, game.id, { kind: 'sow', pit: 0 });
  await move(b, game.id, { kind: 'sow', pit: 0 });
  assert.deepEqual(await inbox(a), { count: 1, awaitingMe: [{ gameId: game.id, type: 'mancala' }] });
  assert.equal((await inbox(b)).count, 0);

  // The extra move: A is STILL the awaited member — the old last-mover
  // heuristic flipped the badge to B here.
  await move(a, game.id, { kind: 'sow', pit: 1 });
  assert.deepEqual(await inbox(a), { count: 1, awaitingMe: [{ gameId: game.id, type: 'mancala' }] });
  assert.equal((await inbox(b)).count, 0);

  // The follow-up hands over → the badge moves to B.
  await move(a, game.id, { kind: 'sow', pit: 2 });
  assert.equal((await inbox(a)).count, 0);
  assert.deepEqual(await inbox(b), { count: 1, awaitingMe: [{ gameId: game.id, type: 'mancala' }] });
});
