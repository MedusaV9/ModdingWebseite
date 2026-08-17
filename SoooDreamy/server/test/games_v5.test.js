import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { makeApp, setupCouple } from './helpers.js';

// E2E protocol runs of the v5.0 word & party games (wordleduo, hangman,
// rps, story, wordchain) — each test plays a full match over the relay the
// way the iOS reducers do, pinning the wire format both clients depend on,
// plus the adversarial rejections that keep the games server-authoritative.

const sha256 = (text) => createHash('sha256').update(text, 'utf8').digest('hex');

async function startGame(a, b, type, payload = {}) {
  const created = await a.api.post('/api/games', { json: { type, payload } });
  assert.equal(created.status, 201, JSON.stringify(created.body));
  const game = created.body.game;
  const joined = await b.api.post(`/api/games/${game.id}/join`, { json: {} });
  assert.equal(joined.status, 200);
  return game;
}

const mover = (game) => (who, data) => who.api.post(`/api/games/${game.id}/move`, { json: { data } });

// ---------------------------------------------------------------------------
// 1. Koop-Wordle "Duo" (wordleduo)

test('wordleduo: sealed target, alternating rows, verified reveal and coop result', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'wordleduo', { lang: 'de' });
  assert.equal(game.payload.lang, 'de');
  assert.equal(game.payload.maxRows, 6);
  assert.match(game.payload.dateKey, /^\d{4}-\d{2}-\d{2}$/);
  const move = mover(game);

  const salt = 'duo-salz';
  // Guessing before the target is sealed is rejected.
  const early = await move(a, { kind: 'guess', row: 0, text: 'TRAUM' });
  assert.equal(early.status, 409);
  assert.equal(early.body.error, 'wrong_phase');

  // Only the creator seals the target.
  const wrongSealer = await move(b, { kind: 'target', commit: sha256('HERZE' + salt) });
  assert.equal(wrongSealer.status, 403);
  assert.equal((await move(a, { kind: 'target', commit: sha256('HERZE' + salt) })).status, 201);

  // Rows alternate: creator row 0, partner row 1, …
  const wrongTurn = await move(b, { kind: 'guess', row: 0, text: 'TRAUM' });
  assert.equal(wrongTurn.status, 409);
  assert.equal(wrongTurn.body.error, 'wrong_turn');
  assert.equal((await move(a, { kind: 'guess', row: 0, text: 'TRAUM' })).status, 201);
  const badWord = await move(b, { kind: 'guess', row: 1, text: 'XY' });
  assert.equal(badWord.status, 400);
  assert.equal((await move(b, { kind: 'guess', row: 1, text: 'herze' })).status, 201);

  // A forged reveal is rejected outright (not stored as unverified).
  const forged = await move(a, { kind: 'reveal', reveal: 'BLUME', salt });
  assert.equal(forged.status, 409);
  assert.equal(forged.body.error, 'reveal_mismatch');

  const final = await move(a, { kind: 'reveal', reveal: 'HERZE', salt });
  assert.equal(final.status, 201);
  assert.equal(final.body.game.state, 'ended');
  const result = final.body.game.result;
  assert.equal(result.solved, true);
  assert.equal(result.rows, 2); // solved in the partner's row (case-folded)
  assert.equal(result.target, 'HERZE');
});

test('wordleduo: reveal is rejected while the board is still in play (FXD-1 Fund 5)', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'wordleduo', { lang: 'de' });
  const move = mover(game);
  const salt = 'duo-salz';
  assert.equal((await move(a, { kind: 'target', commit: sha256('HERZE' + salt) })).status, 201);

  // One miss is NOT "done": the old guard allowed a reveal after ANY
  // single guess, ending the shared board mid-play.
  assert.equal((await move(a, { kind: 'guess', row: 0, text: 'TRAUM' })).status, 201);
  const early = await move(a, { kind: 'reveal', reveal: 'HERZE', salt });
  assert.equal(early.status, 409, JSON.stringify(early.body));
  assert.equal(early.body.error, 'wrong_phase');

  // Still in play after more misses — only a hit or a FULL board unlocks.
  const misses = [
    ['b', 1, 'BLUME'], ['a', 2, 'LICHT'], ['b', 3, 'MONDE'], ['a', 4, 'STERN'],
  ];
  for (const [player, row, text] of misses) {
    assert.equal((await move(player === 'a' ? a : b, { kind: 'guess', row, text })).status, 201);
    const still = await move(a, { kind: 'reveal', reveal: 'HERZE', salt });
    assert.equal(still.status, 409);
    assert.equal(still.body.error, 'wrong_phase');
  }

  // Sixth miss exhausts the board → the reveal is due and accepted.
  assert.equal((await move(b, { kind: 'guess', row: 5, text: 'WOLKE' })).status, 201);
  const final = await move(a, { kind: 'reveal', reveal: 'HERZE', salt });
  assert.equal(final.status, 201, JSON.stringify(final.body));
  assert.equal(final.body.game.state, 'ended');
  assert.equal(final.body.game.result.solved, false);
  assert.equal(final.body.game.result.rows, 6);
  // (The solved-early case — reveal permitted mid-board after a hit — is
  // pinned by the happy-path test above: solved in row 2 of 6.)
});

test('wordleduo: dateKey must be near the server date', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);
  const bad = await a.api.post('/api/games', {
    json: { type: 'wordleduo', payload: { dateKey: '2020-01-01' } },
  });
  assert.equal(bad.status, 400);
  assert.equal(bad.body.error, 'bad_datekey');
});

// ---------------------------------------------------------------------------
// 2. Galgenraten "Unser Wort" (hangman)

test('hangman: honest match — guesser wins with server-audited positions', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'hangman', {});
  const move = mover(game);

  const word = 'rom';
  const salt = 'galgen-salz';
  assert.equal(
    (await move(a, { kind: 'setup', commit: sha256(word + salt), len: 3, hint: 'Unser erster Städtetrip' })).status,
    201,
  );

  // Only the guesser picks letters; the setter answers the pending letter.
  const setterGuess = await move(a, { kind: 'letter', letter: 'r' });
  assert.equal(setterGuess.status, 403);
  assert.equal((await move(b, { kind: 'letter', letter: 'r' })).status, 201);
  const impatient = await move(b, { kind: 'letter', letter: 'o' });
  assert.equal(impatient.status, 409); // pending answer first
  assert.equal((await move(a, { kind: 'positions', letter: 'r', positions: [0] })).status, 201);

  assert.equal((await move(b, { kind: 'letter', letter: 'x' })).status, 201);
  assert.equal((await move(a, { kind: 'positions', letter: 'x', positions: [] })).status, 201);

  const repeat = await move(b, { kind: 'letter', letter: 'r' });
  assert.equal(repeat.status, 409);
  assert.equal(repeat.body.error, 'duplicate_move');

  assert.equal((await move(b, { kind: 'letter', letter: 'o' })).status, 201);
  assert.equal((await move(a, { kind: 'positions', letter: 'o', positions: [1] })).status, 201);
  assert.equal((await move(b, { kind: 'letter', letter: 'm' })).status, 201);
  assert.equal((await move(a, { kind: 'positions', letter: 'm', positions: [2] })).status, 201);

  const final = await move(a, { kind: 'reveal', reveal: word, salt });
  assert.equal(final.status, 201);
  assert.equal(final.body.game.state, 'ended');
  const result = final.body.game.result;
  assert.equal(result.integrity, true);
  assert.equal(result.winner, b.memberId);
  assert.equal(result.scores[b.memberId], 1);
  assert.equal(result.word, word);
  assert.equal(result.wrong, 1);
});

test('hangman: dishonest position reports void the win after the reveal audit', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'hangman', {});
  const move = mover(game);

  const word = 'eis';
  const salt = 'salz';
  await move(a, { kind: 'setup', commit: sha256(word + salt), len: 3, hint: '' });
  // The setter lies: "e" is at position 0, but they claim it missed.
  await move(b, { kind: 'letter', letter: 'e' });
  await move(a, { kind: 'positions', letter: 'e', positions: [] });
  // Nine more lies drive the guesser to the 10-wrong loss.
  for (const letter of ['a', 'b', 'c', 'd', 'f', 'g', 'h', 'j', 'k']) {
    await move(b, { kind: 'letter', letter });
    await move(a, { kind: 'positions', letter, positions: [] });
  }
  const final = await move(a, { kind: 'reveal', reveal: word, salt });
  assert.equal(final.status, 201);
  const result = final.body.game.result;
  assert.equal(result.integrity, false);
  assert.equal(result.winner, null);
  assert.equal(result.scores[a.memberId], 0);
  assert.equal(result.scores[b.memberId], 0);
});

// ---------------------------------------------------------------------------
// 3. Schere-Stein-Papier (rps)

test('rps: commit-reveal rounds, tie replays, first to target wins', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'rps', { target: 2 });
  assert.equal(game.payload.target, 2);
  const move = mover(game);

  const play = async (round, choiceA, choiceB) => {
    assert.equal((await move(a, { kind: 'commit', round, commit: sha256(choiceA + 'sa') })).status, 201);
    // Revealing before both commits exist is rejected (anti-spoiler).
    const early = await move(a, { kind: 'reveal', round, reveal: choiceA, salt: 'sa' });
    assert.equal(early.status, 409);
    assert.equal(early.body.error, 'wrong_phase');
    assert.equal((await move(b, { kind: 'commit', round, commit: sha256(choiceB + 'sb') })).status, 201);
    assert.equal((await move(a, { kind: 'reveal', round, reveal: choiceA, salt: 'sa' })).status, 201);
    return move(b, { kind: 'reveal', round, reveal: choiceB, salt: 'sb' });
  };

  await play(0, 'rock', 'scissors'); // a 1:0
  // A reveal that does not match the sealed commitment is rejected.
  assert.equal((await move(a, { kind: 'commit', round: 1, commit: sha256('rock' + 'sa') })).status, 201);
  assert.equal((await move(b, { kind: 'commit', round: 1, commit: sha256('paper' + 'sb') })).status, 201);
  const forged = await move(a, { kind: 'reveal', round: 1, reveal: 'scissors', salt: 'sa' });
  assert.equal(forged.status, 409);
  assert.equal(forged.body.error, 'reveal_mismatch');
  assert.equal((await move(a, { kind: 'reveal', round: 1, reveal: 'rock', salt: 'sa' })).status, 201);
  assert.equal((await move(b, { kind: 'reveal', round: 1, reveal: 'paper', salt: 'sb' })).status, 201); // b 1:1
  await play(2, 'paper', 'paper'); // tie — replay
  const final = await play(3, 'scissors', 'paper'); // a 2:1 → wins
  assert.equal(final.status, 201);
  assert.equal(final.body.game.state, 'ended');
  assert.equal(final.body.game.result.winner, a.memberId);
  assert.equal(final.body.game.result.scores[a.memberId], 2);
  assert.equal(final.body.game.result.scores[b.memberId], 1);
});

// ---------------------------------------------------------------------------
// 4. Fortsetzungsgeschichte (story)

test('story: alternating sentences build one shared tale', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'story', { genre: 2, sentences: 6, lang: 'de' });
  assert.equal(game.payload.sentences, 6);
  const move = mover(game);

  const outOfTurn = await move(b, { kind: 'sentence', index: 0, text: 'Ich zuerst!' });
  assert.equal(outOfTurn.status, 409);
  assert.equal(outOfTurn.body.error, 'wrong_turn');

  const lines = [
    'Es war einmal ein Paar mit einer sehr klugen App.',
    'Die App konnte leider nur Konfetti kochen.',
    'Also kochten die beiden selbst — Konfetti-Suppe.',
    'Der Kater des Hauses war Feuer und Flamme.',
    'Er bestellte per Miau eine zweite Portion.',
    'Und wenn sie nicht aufgegessen haben, löffeln sie noch heute.',
  ];
  for (const [index, text] of lines.entries()) {
    const author = index % 2 === 0 ? a : b;
    const wrongIndex = await move(author, { kind: 'sentence', index: index + 1, text });
    assert.equal(wrongIndex.status, index + 1 >= 6 ? 400 : 409);
    const sent = await move(author, { kind: 'sentence', index, text });
    assert.equal(sent.status, 201);
  }
  const finished = (await a.api.get(`/api/games/${game.id}`)).body.game;
  assert.equal(finished.state, 'ended');
  assert.equal(finished.result.sentences, 6);
  assert.equal(finished.result.genre, 2);
  assert.equal(
    finished.moves.filter((m) => m.data.kind === 'sentence').map((m) => m.data.text).join(' '),
    lines.join(' '),
  );
});

// ---------------------------------------------------------------------------
// 5. Wortkette-Blitz (wordchain)

test('wordchain: chain letter rule, no repeats, coop length result', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const game = await startGame(a, b, 'wordchain', { lang: 'de' });
  const move = mover(game);

  assert.equal((await move(a, { kind: 'word', index: 0, text: 'Herz' })).status, 201);
  const wrongLetter = await move(b, { kind: 'word', index: 1, text: 'Traum' });
  assert.equal(wrongLetter.status, 409);
  assert.equal(wrongLetter.body.error, 'wrong_letter');
  assert.equal((await move(b, { kind: 'word', index: 1, text: 'Zelt' })).status, 201);
  const duplicate = await move(a, { kind: 'word', index: 2, text: 'zelt' });
  assert.equal(duplicate.status, 409);
  assert.equal(duplicate.body.error, 'duplicate_move');
  assert.equal((await move(a, { kind: 'word', index: 2, text: 'Tandem' })).status, 201);
  // ß folds to s: "Fuß" ends the chain letter on "s".
  assert.equal((await move(b, { kind: 'word', index: 3, text: 'Maßfuß' })).status, 201);
  const wrongFinisher = await move(b, { kind: 'finish' });
  assert.equal(wrongFinisher.status, 403);
  assert.equal((await move(a, { kind: 'word', index: 4, text: 'Sonnenblume' })).status, 201);
  const final = await move(b, { kind: 'finish' });
  assert.equal(final.status, 201);
  assert.equal(final.body.game.state, 'ended');
  assert.equal(final.body.game.result.length, 5);
  assert.equal(final.body.game.result.longestWord, 'Sonnenblume');
});
