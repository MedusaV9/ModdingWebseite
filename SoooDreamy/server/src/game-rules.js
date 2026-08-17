import { sha256Hex } from './util.js';
import {
  httpError,
  id,
  isValidDateKey,
  nextDateKey,
  nowIso,
  prevDateKey,
  todayKey,
} from './util.js';
import { BINGO_ACTIONS, WORD_CHAIN_WORDS, bingoCardIndexes } from './game-content-v51.js';

export const GAME_TYPES = Object.freeze([
  'quiz',
  'thisorthat',
  'wouldyourather',
  'truthordare',
  'questions36',
  'emojiriddle',
  'connectfour',
  'photomemory',
  'quizduel',
  'battleship',
  'pictionary',
  'kniffel',
  'movieroulette',
  'stadtlandfluss',
  'twotruths',
  'dailyquests',
  // v5.0 word & party games
  'wordleduo',
  'hangman',
  'rps',
  'story',
  'wordchain',
  'bingo',
  // W8C board & duel games
  'dame',
  'reversi',
  'kaesekaestchen',
  'gomoku',
  'mancala',
  'memoryduo',
]);

const KNiffel_CATEGORIES = Object.freeze([
  'ones', 'twos', 'threes', 'fours', 'fives', 'sixes',
  'three', 'four', 'full', 'small', 'large', 'kniffel', 'chance',
]);
const QUIZ_DUEL_CORRECT = Object.freeze([
  1, 0, 1, 0, 1, 1, 0, 0, 0, 0, 1, 1,
  0, 1, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0,
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
]);
const PICTURE_WORDS = Object.freeze({
  de: Object.freeze([
    'Herz', 'Regenbogen', 'Luftballon', 'Kaktus', 'Leuchtturm', 'Schneemann',
    'Pizza', 'Croissant', 'Spiegelei', 'Eiswaffel', 'Torte', 'Brezel',
    'Kaffeetasse', 'Teekanne', 'Picknick', 'Lagerfeuer', 'Zelt', 'Wohnmobil',
    'Fahrrad', 'Tandem', 'Heißluftballon', 'Riesenrad', 'Karussell', 'Achterbahn',
    'Katze', 'Hund', 'Pinguin', 'Faultier', 'Oktopus', 'Schmetterling',
    'Marienkäfer', 'Igel', 'Eule', 'Flamingo', 'Wal', 'Seepferdchen',
    'Sonnenblume', 'Kirschblüte', 'Palme', 'Pilz', 'Kleeblatt', 'Rose',
    'Gitarre', 'Klavier', 'Kopfhörer', 'Mikrofon', 'Plattenspieler', 'Trommel',
    'Brautkleid', 'Ehering', 'Liebesbrief', 'Kussmund', 'Umarmung', 'Händchenhalten',
    'Candle-Light-Dinner', 'Rosenstrauß', 'Pralinen', 'Teddybär', 'Fotoalbum', 'Spieluhr',
    'Strand', 'Vulkan', 'Wasserfall', 'Insel', 'Berge', 'Vollmond',
    'Sternschnuppe', 'Nordlicht', 'Gewitter', 'Regenschirm', 'Schaukel', 'Hängematte',
    'Badewanne', 'Dusche', 'Spiegel', 'Zahnbürste', 'Föhn', 'Lippenstift',
    'Sofa', 'Kamin', 'Bücherregal', 'Wecker', 'Lampe', 'Schlüssel',
    'Koffer', 'Flugzeug', 'Segelboot', 'U-Boot', 'Rakete', 'Ufo',
    'Ritterburg', 'Krone', 'Schatztruhe', 'Zauberstab', 'Drache', 'Einhorn',
    'Meerjungfrau', 'Pirat', 'Roboter', 'Astronaut', 'Clown', 'Zirkuszelt',
    'Popcorn', 'Kino', 'Fernbedienung', 'Konsole', 'Würfel', 'Puzzle',
    'Schaukelstuhl', 'Strickmütze', 'Wollsocken', 'Schlittschuhe', 'Schlitten', 'Iglu',
    'Grill', 'Wassermelone', 'Cocktail', 'Sonnenbrille', 'Flip-Flops', 'Sandburg',
  ]),
  en: Object.freeze([
    'Heart', 'Rainbow', 'Balloon', 'Cactus', 'Lighthouse', 'Snowman',
    'Pizza', 'Croissant', 'Fried egg', 'Ice cream cone', 'Cake', 'Pretzel',
    'Coffee cup', 'Teapot', 'Picnic', 'Campfire', 'Tent', 'Camper van',
    'Bicycle', 'Tandem', 'Hot air balloon', 'Ferris wheel', 'Carousel', 'Roller coaster',
    'Cat', 'Dog', 'Penguin', 'Sloth', 'Octopus', 'Butterfly',
    'Ladybug', 'Hedgehog', 'Owl', 'Flamingo', 'Whale', 'Seahorse',
    'Sunflower', 'Cherry blossom', 'Palm tree', 'Mushroom', 'Clover', 'Rose',
    'Guitar', 'Piano', 'Headphones', 'Microphone', 'Record player', 'Drum',
    'Wedding dress', 'Wedding ring', 'Love letter', 'Kiss', 'Hug', 'Holding hands',
    'Candlelight dinner', 'Bouquet', 'Chocolates', 'Teddy bear', 'Photo album', 'Music box',
    'Beach', 'Volcano', 'Waterfall', 'Island', 'Mountains', 'Full moon',
    'Shooting star', 'Northern lights', 'Thunderstorm', 'Umbrella', 'Swing', 'Hammock',
    'Bathtub', 'Shower', 'Mirror', 'Toothbrush', 'Hair dryer', 'Lipstick',
    'Sofa', 'Fireplace', 'Bookshelf', 'Alarm clock', 'Lamp', 'Key',
    'Suitcase', 'Airplane', 'Sailboat', 'Submarine', 'Rocket', 'UFO',
    'Castle', 'Crown', 'Treasure chest', 'Magic wand', 'Dragon', 'Unicorn',
    'Mermaid', 'Pirate', 'Robot', 'Astronaut', 'Clown', 'Circus tent',
    'Popcorn', 'Cinema', 'Remote control', 'Game console', 'Dice', 'Puzzle',
    'Rocking chair', 'Beanie', 'Wool socks', 'Ice skates', 'Sled', 'Igloo',
    'Barbecue', 'Watermelon', 'Cocktail', 'Sunglasses', 'Flip-flops', 'Sandcastle',
  ]),
});

const MASK_64 = (1n << 64n) - 1n;
const MIX_INC = 0x9e3779b97f4a7c15n;

function reject(code, message, status = 400) {
  throw httpError(status, code, message);
}

function integer(value, field, min, max) {
  if (!Number.isInteger(value) || value < min || value > max) {
    reject('invalid_game_move', `"${field}" must be an integer between ${min} and ${max}`);
  }
  return value;
}

function optionInteger(value, fallback, min, max) {
  return value === undefined ? fallback : integer(value, 'payload option', min, max);
}

function text(value, field, max, { allowEmpty = false } = {}) {
  if (typeof value !== 'string' || value.length > max || (!allowEmpty && value.trim().length === 0)) {
    reject('invalid_game_move', `"${field}" must be a${allowEmpty ? '' : ' non-empty'} string of at most ${max} characters`);
  }
  return value;
}

function boolean(value, field) {
  if (typeof value !== 'boolean') reject('invalid_game_move', `"${field}" must be a boolean`);
  return value;
}

function membersOf(couple) {
  return couple.members.map((member) => member.id).sort();
}

function opponent(members, memberId) {
  return members.find((id) => id !== memberId) ?? null;
}

function requirePair(couple) {
  const members = membersOf(couple);
  if (members.length !== 2) reject('partner_required', 'This game requires exactly two members', 409);
  return members;
}

function duplicate(game, memberId, kind, predicate = () => true) {
  return game.moves.some(
    (move) => move.memberId === memberId && move.data?.kind === kind && predicate(move.data),
  );
}

function seedGenerator(seed) {
  let state = (BigInt.asUintN(64, BigInt(seed)) + MIX_INC) & MASK_64;
  return (bound) => {
    if (bound <= 1) return 0;
    state = (state + MIX_INC) & MASK_64;
    let z = state;
    z = ((z ^ (z >> 30n)) * 0xbf58476d1ce4e5b9n) & MASK_64;
    z = ((z ^ (z >> 27n)) * 0x94d049bb133111ebn) & MASK_64;
    z ^= z >> 31n;
    return Number(z % BigInt(bound));
  };
}

function seededShuffle(values, seed) {
  const result = [...values];
  const next = seedGenerator(seed);
  for (let index = result.length - 1; index > 0; index -= 1) {
    const other = next(index + 1);
    [result[index], result[other]] = [result[other], result[index]];
  }
  return result;
}

function commitFor(game, memberId, data) {
  if (typeof data.commitId === 'string') {
    return game.moves.find(
      (move) => move.id === data.commitId && move.memberId === memberId && typeof move.data?.commit === 'string',
    );
  }
  return [...game.moves].reverse().find(
    (move) => move.memberId === memberId && typeof move.data?.commit === 'string',
  );
}

function verifiedReveal(game, memberId, data) {
  const reveal = text(data.reveal, 'reveal', 4_000, { allowEmpty: true });
  const salt = text(data.salt, 'salt', 256, { allowEmpty: true });
  const commit = commitFor(game, memberId, data);
  if (!commit || sha256Hex(reveal + salt) !== commit.data.commit.toLowerCase()) {
    reject('reveal_mismatch', 'Reveal does not match this member’s commitment', 409);
  }
  return {
    reveal,
    salt,
    ...(typeof data.commitId === 'string' ? { commitId: data.commitId } : {}),
    verified: true,
  };
}

export function prepareGamePayload(type, raw, couple) {
  const input = raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {};
  switch (type) {
    case 'quiz':
      return { rounds: optionInteger(input.rounds, 8, 1, 12) };
    case 'thisorthat':
    case 'wouldyourather':
      return { rounds: optionInteger(input.rounds, 12, 1, 30) };
    case 'truthordare':
      return {
        rounds: optionInteger(input.rounds, 10, 1, 30),
        spice: optionInteger(input.spice, 2, 1, 3),
      };
    case 'questions36':
      return { set: optionInteger(input.set, 1, 1, 3) };
    case 'emojiriddle':
      return {
        rounds: optionInteger(input.rounds, 10, 1, 30),
        cats: optionInteger(input.cats, 0, 0, 63),
      };
    case 'photomemory': {
      const ids = Array.isArray(input.photoIds) ? input.photoIds : [];
      const known = new Set(couple.photos.map((photo) => photo.id));
      const unique = [...new Set(ids.filter((value) => typeof value === 'string' && known.has(value)))].slice(0, 8);
      if (unique.length < 2) reject('not_enough_photos', 'Photo memory requires 2–8 photos from this couple', 409);
      return { photoIds: unique, pairCount: unique.length };
    }
    case 'quizduel':
      return { rounds: optionInteger(input.rounds, 8, 1, QUIZ_DUEL_CORRECT.length) };
    case 'pictionary':
      return {
        rounds: optionInteger(input.rounds, 6, 1, 20),
        secs: optionInteger(input.secs, 90, 15, 300),
        lang: input.lang === 'en' ? 'en' : 'de',
      };
    case 'movieroulette': {
      const custom = Array.isArray(input.custom)
        ? input.custom
            .filter((value) => typeof value === 'string' && value.trim().length > 0)
            .map((value) => value.trim().slice(0, 120))
            .slice(0, 20)
        : [];
      return {
        size: optionInteger(input.size, 20, 1, 40),
        custom,
      };
    }
    case 'stadtlandfluss': {
      const categories = Array.isArray(input.categories)
        ? input.categories
            .filter((value) => typeof value === 'string' && value.trim().length > 0)
            .map((value) => value.trim().slice(0, 40))
            .slice(0, 12)
        : [];
      return {
        rounds: optionInteger(input.rounds, 3, 1, 10),
        categories: categories.length > 0
          ? categories
          : ['Stadt', 'Land', 'Fluss', 'Kosename', 'Essen', 'Song'],
      };
    }
    case 'twotruths':
      return { rounds: optionInteger(input.rounds, 4, 1, 10) };
    case 'dailyquests':
      return { dateKey: input.dateKey };
    case 'wordleduo': {
      // Day-bound like daily quests: the shared target word is derived from
      // (coupleId, dateKey, lang) on both clients — the dateKey must be a
      // real date near the server date so nobody farms arbitrary days.
      const today = todayKey();
      const dateKey = input.dateKey === undefined ? today : input.dateKey;
      if (!isValidDateKey(dateKey) || ![prevDateKey(today), today, nextDateKey(today)].includes(dateKey)) {
        reject('bad_datekey', `"dateKey" must be within one day of the server date (${today})`);
      }
      return { dateKey, lang: input.lang === 'en' ? 'en' : 'de', maxRows: 6 };
    }
    case 'hangman': {
      const payload = { lang: input.lang === 'en' ? 'en' : 'de', maxWrong: 10 };
      if (input.commit !== undefined) {
        const commit = text(input.commit, 'commit', 64);
        if (!/^[0-9a-f]{64}$/i.test(commit)) {
          reject('invalid_game_move', 'Commit must be a SHA-256 hex digest');
        }
        payload.commit = commit.toLowerCase();
        payload.len = integer(input.len, 'len', 3, 24);
        payload.hint = input.hint === undefined
          ? ''
          : text(input.hint, 'hint', 60, { allowEmpty: true });
      }
      return payload;
    }
    case 'rps':
      return { target: optionInteger(input.target, 4, 1, 10) };
    case 'story':
      return {
        genre: optionInteger(input.genre, 0, 0, 7),
        sentences: optionInteger(input.sentences, 20, 6, 40),
        lang: input.lang === 'en' ? 'en' : 'de',
      };
    case 'wordchain': {
      const today = todayKey();
      const dateKey = input.dateKey === undefined ? today : input.dateKey;
      if (!isValidDateKey(dateKey) || ![prevDateKey(today), today, nextDateKey(today)].includes(dateKey)) {
        reject('bad_datekey', `"dateKey" must be within one day of the server date (${today})`);
      }
      return { lang: input.lang === 'en' ? 'en' : 'de', dateKey };
    }
    case 'bingo':
      return { weekKey: currentWeekKey(), size: 4 };
    // W8C board & duel games — options are validated bounds, everything else
    // is a fixed descriptive field so clients render from the payload alone.
    case 'dame':
      return { size: 8, drawPlies: optionInteger(input.drawPlies, 40, 10, 100) };
    case 'reversi':
      return { size: 8 };
    case 'kaesekaestchen':
      return { size: optionInteger(input.size, 5, 2, 6) };
    case 'gomoku':
      return { size: 15, winLength: 5 };
    case 'mancala':
      return { pits: 6, stones: optionInteger(input.stones, 4, 3, 6) };
    case 'memoryduo':
      return { pairs: 18, size: 6 };
    case 'connectfour':
    case 'battleship':
    case 'kniffel':
      return {};
    default:
      reject('invalid_type', `Unsupported game type: ${type}`);
  }
}

/** Adds fields that depend on the server-generated seed. */
export function finalizeGamePayload(type, payload) {
  if (type === 'bingo') {
    return { ...payload, cardIndexes: bingoCardIndexes(payload.seed, 16) };
  }
  return payload;
}

function quizState(game, couple) {
  const members = membersOf(couple);
  const rounds = game.payload.rounds;
  const state = Array.from({ length: rounds }, () => ({ answers: {}, verdict: null }));
  for (const move of game.moves) {
    const { data } = move;
    if (!Number.isInteger(data?.round) || !state[data.round]) continue;
    if (data.kind === 'answer' && state[data.round].answers[move.memberId] === undefined) {
      state[data.round].answers[move.memberId] = data.value;
    } else if (data.kind === 'verdict' && state[data.round].verdict === null) {
      state[data.round].verdict = data.value;
    }
  }
  const current = state.findIndex((round) => round.verdict === null);
  return { members, state, current: current === -1 ? rounds : current };
}

function validateQuiz(game, couple, memberId, data) {
  const { members, state, current } = quizState(game, couple);
  if (current >= state.length) reject('game_complete', 'All quiz rounds are complete', 409);
  const round = integer(data.round, 'round', 0, state.length - 1);
  if (round !== current) reject('wrong_round', `The active round is ${current}`, 409);
  if (data.kind === 'answer') {
    if (state[round].answers[memberId] !== undefined) reject('duplicate_move', 'This member already answered', 409);
    return { kind: 'answer', round, value: text(data.value, 'value', 500) };
  }
  if (data.kind === 'verdict') {
    const subject = members[round % 2];
    if (memberId !== subject) reject('wrong_actor', 'Only the round subject may judge the answer', 403);
    if (!members.every((id) => state[round].answers[id] !== undefined)) {
      reject('wrong_phase', 'Both answers are required before the verdict', 409);
    }
    if (!['right', 'wrong'].includes(data.value)) reject('invalid_game_move', 'Verdict must be right or wrong');
    return { kind: 'verdict', round, value: data.value };
  }
  reject('invalid_game_move', 'Unsupported quiz action');
}

function choiceState(game, couple) {
  const members = membersOf(couple);
  const rounds = game.payload.rounds;
  const picks = Array.from({ length: rounds }, () => ({}));
  for (const move of game.moves) {
    if (move.data?.kind === 'pick' && picks[move.data.round] && picks[move.data.round][move.memberId] === undefined) {
      picks[move.data.round][move.memberId] = move.data.value;
    }
  }
  const current = picks.findIndex((round) => !members.every((id) => round[id] !== undefined));
  return { members, picks, current: current === -1 ? rounds : current };
}

function validateChoice(game, couple, memberId, data) {
  const { picks, current } = choiceState(game, couple);
  if (current >= picks.length) reject('game_complete', 'All choice rounds are complete', 409);
  if (data.kind !== 'pick') reject('invalid_game_move', 'Unsupported choice action');
  const round = integer(data.round, 'round', 0, picks.length - 1);
  if (round !== current) reject('wrong_round', `The active round is ${current}`, 409);
  if (picks[round][memberId] !== undefined) reject('duplicate_move', 'This member already picked', 409);
  if (!['a', 'b'].includes(data.value)) reject('invalid_game_move', 'Pick must be a or b');
  return { kind: 'pick', round, value: data.value };
}

function truthState(game, couple) {
  const members = membersOf(couple);
  const rounds = game.payload.rounds;
  const state = Array.from({ length: rounds }, () => ({ pick: null, claim: null }));
  for (const move of game.moves) {
    const round = state[move.data?.round];
    if (!round) continue;
    if (move.data.kind === 'pick' && round.pick === null) round.pick = move.data.value;
    if (move.data.kind === 'claim' && round.claim === null) round.claim = move.data.value;
  }
  const current = state.findIndex((round) => round.claim === null);
  return { members, state, current: current === -1 ? rounds : current };
}

function validateTruthOrDare(game, couple, memberId, data) {
  const { members, state, current } = truthState(game, couple);
  if (current >= state.length) reject('game_complete', 'All truth-or-dare rounds are complete', 409);
  const round = integer(data.round, 'round', 0, state.length - 1);
  if (round !== current) reject('wrong_round', `The active round is ${current}`, 409);
  const active = members[(game.payload.seed + round) % 2];
  if (memberId !== active) reject('wrong_actor', 'Only the active member may act', 403);
  if (data.kind === 'pick') {
    if (state[round].pick !== null) reject('duplicate_move', 'This round already has a card type', 409);
    if (!['truth', 'dare'].includes(data.value)) reject('invalid_game_move', 'Pick must be truth or dare');
    return { kind: 'pick', round, value: data.value };
  }
  if (data.kind === 'claim') {
    if (state[round].pick === null) reject('wrong_phase', 'Pick a card before closing the round', 409);
    if (state[round].claim !== null) reject('duplicate_move', 'This round is already closed', 409);
    if (!['done', 'skip'].includes(data.value)) reject('invalid_game_move', 'Claim must be done or skip');
    // Consent rule: skipping a card is always allowed — no quota. Nobody
    // should ever feel forced into a dare because the passes ran out.
    return { kind: 'claim', round, value: data.value };
  }
  reject('invalid_game_move', 'Unsupported truth-or-dare action');
}

function emojiState(game, couple) {
  const members = membersOf(couple);
  const rounds = game.payload.rounds;
  const state = Array.from({ length: rounds }, () => ({ guesses: {}, claims: {} }));
  for (const move of game.moves) {
    const round = state[move.data?.round];
    if (!round) continue;
    if (move.data.kind === 'guess' && round.guesses[move.memberId] === undefined) {
      round.guesses[move.memberId] = move.data.value;
    }
    if (move.data.kind === 'claim' && round.claims[move.memberId] === undefined) {
      round.claims[move.memberId] = move.data.value;
    }
  }
  const current = state.findIndex((round) => !members.every((id) => round.claims[id] !== undefined));
  return { members, state, current: current === -1 ? rounds : current };
}

function validateEmoji(game, couple, memberId, data) {
  const { members, state, current } = emojiState(game, couple);
  if (current >= state.length) reject('game_complete', 'All emoji rounds are complete', 409);
  const round = integer(data.round, 'round', 0, state.length - 1);
  if (round !== current) reject('wrong_round', `The active round is ${current}`, 409);
  if (data.kind === 'guess') {
    if (state[round].guesses[memberId] !== undefined) reject('duplicate_move', 'This member already guessed', 409);
    return { kind: 'guess', round, value: text(data.value, 'value', 200) };
  }
  if (data.kind === 'claim') {
    if (!members.every((id) => state[round].guesses[id] !== undefined)) {
      reject('wrong_phase', 'Both guesses are required before scoring', 409);
    }
    if (state[round].claims[memberId] !== undefined) reject('duplicate_move', 'This member already scored the round', 409);
    if (!['right', 'wrong'].includes(data.value)) reject('invalid_game_move', 'Claim must be right or wrong');
    return { kind: 'claim', round, value: data.value };
  }
  reject('invalid_game_move', 'Unsupported emoji-riddle action');
}

function connectState(game, couple) {
  const members = requirePair(couple);
  const starter = game.createdBy;
  const partner = opponent(members, starter);
  const columns = Array.from({ length: 7 }, () => []);
  let winner = null;
  let moveCount = 0;
  for (const move of game.moves) {
    if (move.data?.kind !== 'drop' || winner) continue;
    const column = move.data.column;
    if (!Number.isInteger(column) || column < 0 || column >= 7 || columns[column].length >= 6) continue;
    const actor = moveCount % 2 === 0 ? starter : partner;
    if (move.memberId !== actor) continue;
    columns[column].push(move.memberId);
    moveCount += 1;
    const row = columns[column].length - 1;
    if (connectWinner(columns, column, row, move.memberId)) winner = move.memberId;
  }
  return { members, starter, partner, columns, winner, moveCount, draw: !winner && moveCount === 42 };
}

function connectWinner(columns, column, row, memberId) {
  const owner = (col, line) => columns[col]?.[line];
  for (const [dx, dy] of [[1, 0], [0, 1], [1, 1], [1, -1]]) {
    let count = 1;
    for (const sign of [1, -1]) {
      let col = column + dx * sign;
      let line = row + dy * sign;
      while (owner(col, line) === memberId) {
        count += 1;
        col += dx * sign;
        line += dy * sign;
      }
    }
    if (count >= 4) return true;
  }
  return false;
}

function validateConnectFour(game, couple, memberId, data) {
  const state = connectState(game, couple);
  if (data.kind !== 'drop') reject('invalid_game_move', 'Connect Four only accepts drop actions');
  if (state.winner || state.draw) reject('game_complete', 'The board is already complete', 409);
  const expected = state.moveCount % 2 === 0 ? state.starter : state.partner;
  if (memberId !== expected) reject('wrong_turn', 'It is the other member’s turn', 409);
  const column = integer(data.column, 'column', 0, 6);
  if (state.columns[column].length >= 6) reject('column_full', 'That column is full', 409);
  return { kind: 'drop', column };
}

function memoryTiles(game) {
  const pairs = Math.max(2, Math.min(game.payload.pairCount, 8));
  return seededShuffle(Array.from({ length: pairs }, (_, index) => [index, index]).flat(), game.payload.seed);
}

function memoryState(game, couple) {
  const members = requirePair(couple);
  const starter = game.createdBy;
  const partner = opponent(members, starter);
  const tiles = memoryTiles(game);
  const matched = new Map();
  const scores = Object.fromEntries(members.map((id) => [id, 0]));
  let turn = starter;
  for (const move of game.moves) {
    if (move.data?.kind !== 'flip' || move.memberId !== turn) continue;
    const { first, second } = move.data;
    if (!tiles[first] && tiles[first] !== 0) continue;
    if (!tiles[second] && tiles[second] !== 0) continue;
    const left = tiles[first];
    const right = tiles[second];
    if (first === second || matched.has(left) || matched.has(right)) continue;
    if (left === right) {
      matched.set(left, move.memberId);
      scores[move.memberId] += 1;
    } else {
      turn = move.memberId === starter ? partner : starter;
    }
  }
  return { members, tiles, matched, scores, turn, complete: matched.size === new Set(tiles).size };
}

function validatePhotoMemory(game, couple, memberId, data) {
  const state = memoryState(game, couple);
  if (data.kind !== 'flip') reject('invalid_game_move', 'Photo memory only accepts flip actions');
  if (state.complete) reject('game_complete', 'Every pair is already matched', 409);
  if (memberId !== state.turn) reject('wrong_turn', 'It is the other member’s turn', 409);
  const first = integer(data.first, 'first', 0, state.tiles.length - 1);
  const second = integer(data.second, 'second', 0, state.tiles.length - 1);
  if (first === second) reject('invalid_game_move', 'A turn must reveal two different tiles');
  if (state.matched.has(state.tiles[first]) || state.matched.has(state.tiles[second])) {
    reject('already_matched', 'Matched tiles cannot be flipped again', 409);
  }
  return { kind: 'flip', first, second };
}

function quizDuelDeck(game) {
  return seededShuffle(QUIZ_DUEL_CORRECT, game.payload.seed).slice(0, game.payload.rounds);
}

function quizDuelState(game, couple) {
  const members = membersOf(couple);
  const deck = quizDuelDeck(game);
  const answers = Array.from({ length: deck.length }, () => ({}));
  const order = [];
  for (const move of game.moves) {
    const round = answers[move.data?.round];
    if (move.data?.kind !== 'answer' || !round || round[move.memberId] !== undefined) continue;
    round[move.memberId] = move.data.option;
    order.push(move);
  }
  const current = answers.findIndex((round) => !members.every((id) => round[id] !== undefined));
  return { members, deck, answers, order, current: current === -1 ? deck.length : current };
}

function validateQuizDuel(game, couple, memberId, data) {
  const state = quizDuelState(game, couple);
  if (data.kind !== 'answer') reject('invalid_game_move', 'Quiz duel only accepts answer actions');
  if (state.current >= state.deck.length) reject('game_complete', 'Every duel round is complete', 409);
  const round = integer(data.round, 'round', 0, state.deck.length - 1);
  if (round !== state.current) reject('wrong_round', `The active round is ${state.current}`, 409);
  if (state.answers[round][memberId] !== undefined) reject('duplicate_move', 'This member already answered', 409);
  return { kind: 'answer', round, option: integer(data.option, 'option', 0, 2) };
}

function pictionaryDeck(game) {
  return seededShuffle(PICTURE_WORDS[game.payload.lang], game.payload.seed).slice(0, game.payload.rounds);
}

function normalizeAnswer(value) {
  return value
    .toLocaleLowerCase('de-DE')
    .replaceAll('ß', 'ss')
    .normalize('NFKD')
    .replace(/[^\p{L}\p{N}]/gu, '');
}

function pictionaryState(game, couple, now = Date.now()) {
  const members = requirePair(couple);
  const starter = game.createdBy;
  const partner = opponent(members, starter);
  const deck = pictionaryDeck(game);
  const rounds = deck.map(() => ({ startedAt: null, solvedBy: null }));
  const scores = Object.fromEntries(members.map((id) => [id, 0]));
  for (const move of game.moves) {
    const round = rounds[move.data?.round];
    if (!round) continue;
    const artist = move.data.round % 2 === 0 ? starter : partner;
    if (move.data.kind === 'round_start' && !round.startedAt && move.memberId === artist) {
      const previous = rounds[move.data.round - 1];
      if (move.data.round === 0 || (previous?.solvedBy || Date.parse(move.createdAt) > previous.startedAt + game.payload.secs * 1000)) {
        round.startedAt = Date.parse(move.createdAt);
      }
    } else if (
      move.data.kind === 'guess'
      && round.startedAt
      && !round.solvedBy
      && move.memberId !== artist
      && Date.parse(move.createdAt) <= round.startedAt + game.payload.secs * 1000
      && normalizeAnswer(move.data.text) === normalizeAnswer(deck[move.data.round])
    ) {
      round.solvedBy = move.memberId;
      scores[move.memberId] += 1;
    }
  }
  let current = rounds.length;
  for (let index = 0; index < rounds.length; index += 1) {
    const round = rounds[index];
    if (!round.startedAt || (!round.solvedBy && now <= round.startedAt + game.payload.secs * 1000)) {
      current = index;
      break;
    }
  }
  const complete = rounds.length > 0 && rounds.every(
    (round) => round.startedAt && (round.solvedBy || now > round.startedAt + game.payload.secs * 1000),
  );
  return { members, starter, partner, deck, rounds, scores, current, complete };
}

function validatePictionary(game, couple, memberId, data, now) {
  const state = pictionaryState(game, couple, now);
  if (state.complete) reject('game_complete', 'Every drawing round is complete', 409);
  const round = integer(data.round, 'round', 0, state.rounds.length - 1);
  if (round !== state.current) reject('wrong_round', `The active round is ${state.current}`, 409);
  const artist = round % 2 === 0 ? state.starter : state.partner;
  const record = state.rounds[round];
  if (data.kind === 'round_start') {
    if (memberId !== artist) reject('wrong_actor', 'Only the artist may start this round', 403);
    if (record.startedAt) reject('duplicate_move', 'This round already started', 409);
    return { kind: 'round_start', round };
  }
  if (!record.startedAt) reject('wrong_phase', 'The artist must start the round first', 409);
  if (now > record.startedAt + game.payload.secs * 1000 || record.solvedBy) {
    reject('wrong_phase', 'This drawing round is already over', 409);
  }
  if (data.kind === 'stroke') {
    if (memberId !== artist) reject('wrong_actor', 'Only the artist may draw', 403);
    if (!Array.isArray(data.points) || data.points.length < 1 || data.points.length > 2_000) {
      reject('invalid_game_move', 'A stroke must contain 1–2000 points');
    }
    const points = data.points.map((point) => {
      if (!Array.isArray(point) || point.length < 2) reject('invalid_game_move', 'Each point needs x and y');
      const [x, y] = point;
      if (![x, y].every((value) => Number.isFinite(value) && value >= 0 && value <= 1)) {
        reject('invalid_game_move', 'Stroke coordinates must be between 0 and 1');
      }
      return [x, y];
    });
    const color = typeof data.color === 'string' && /^#[0-9a-f]{6}$/i.test(data.color) ? data.color : '#FFFFFF';
    const width = Number.isFinite(data.width) && data.width >= 1 && data.width <= 20 ? data.width : 4;
    return { kind: 'stroke', round, color, width, points };
  }
  if (data.kind === 'clear') {
    if (memberId !== artist) reject('wrong_actor', 'Only the artist may clear the board', 403);
    return { kind: 'clear', round };
  }
  if (data.kind === 'guess') {
    if (memberId === artist) reject('wrong_actor', 'The artist cannot guess their own word', 403);
    return { kind: 'guess', round, text: text(data.text, 'text', 200) };
  }
  reject('invalid_game_move', 'Unsupported pictionary action');
}

function dicePips(seed, turn, roll) {
  const next = seedGenerator(seed + turn * 1_000_003 + roll * 10_007);
  return Array.from({ length: 5 }, () => 1 + next(6));
}

function scoreDice(category, dice) {
  const counts = new Map();
  for (const pip of dice) counts.set(pip, (counts.get(pip) ?? 0) + 1);
  const sum = dice.reduce((total, pip) => total + pip, 0);
  const upper = { ones: 1, twos: 2, threes: 3, fours: 4, fives: 5, sixes: 6 };
  if (upper[category]) return (counts.get(upper[category]) ?? 0) * upper[category];
  if (category === 'three') return [...counts.values()].some((count) => count >= 3) ? sum : 0;
  if (category === 'four') return [...counts.values()].some((count) => count >= 4) ? sum : 0;
  if (category === 'full') {
    const values = [...counts.values()].sort((a, b) => a - b);
    return JSON.stringify(values) === '[2,3]' || JSON.stringify(values) === '[5]' ? 25 : 0;
  }
  const unique = new Set(dice);
  const hasRun = (length) => {
    for (let start = 1; start <= 7 - length; start += 1) {
      if (Array.from({ length }, (_, index) => start + index).every((pip) => unique.has(pip))) return true;
    }
    return false;
  };
  if (category === 'small') return hasRun(4) ? 30 : 0;
  if (category === 'large') return hasRun(5) ? 40 : 0;
  if (category === 'kniffel') return [...counts.values()].some((count) => count >= 5) ? 50 : 0;
  return sum;
}

function kniffelState(game, couple) {
  const members = requirePair(couple);
  const starter = game.createdBy;
  const partner = opponent(members, starter);
  const cards = Object.fromEntries(members.map((id) => [id, {}]));
  let turn = 0;
  let rolls = 0;
  let dice = [];
  for (const move of game.moves) {
    if (turn >= 26) break;
    const actor = turn % 2 === 0 ? starter : partner;
    if (move.memberId !== actor) continue;
    if (move.data?.kind === 'roll' && rolls < 3) {
      const fresh = dicePips(game.payload.seed, turn, rolls);
      if (rolls === 0) dice = fresh;
      else {
        const held = new Set(move.data.held.filter((index) => Number.isInteger(index) && index >= 0 && index < 5));
        dice = fresh.map((pip, index) => (held.has(index) ? dice[index] : pip));
      }
      rolls += 1;
    } else if (
      move.data?.kind === 'score'
      && rolls > 0
      && KNiffel_CATEGORIES.includes(move.data.category)
      && cards[actor][move.data.category] === undefined
    ) {
      cards[actor][move.data.category] = scoreDice(move.data.category, dice);
      turn += 1;
      rolls = 0;
      dice = [];
    }
  }
  return { members, starter, partner, cards, turn, rolls, dice, complete: turn >= 26 };
}

function validateKniffel(game, couple, memberId, data) {
  const state = kniffelState(game, couple);
  if (state.complete) reject('game_complete', 'All Kniffel turns are complete', 409);
  const actor = state.turn % 2 === 0 ? state.starter : state.partner;
  if (memberId !== actor) reject('wrong_turn', 'It is the other member’s turn', 409);
  if (data.kind === 'roll') {
    if (state.rolls >= 3) reject('roll_quota', 'A turn allows at most three rolls', 409);
    if (!Array.isArray(data.held) || data.held.length > 5) reject('invalid_game_move', '"held" must be an array');
    const held = [...new Set(data.held.map((index) => integer(index, 'held index', 0, 4)))];
    return { kind: 'roll', held };
  }
  if (data.kind === 'score') {
    if (state.rolls === 0) reject('wrong_phase', 'Roll before choosing a score category', 409);
    if (!KNiffel_CATEGORIES.includes(data.category)) reject('invalid_game_move', 'Unknown score category');
    if (state.cards[memberId][data.category] !== undefined) reject('duplicate_move', 'That category is already used', 409);
    return { kind: 'score', category: data.category };
  }
  reject('invalid_game_move', 'Unsupported Kniffel action');
}

function movieState(game, couple) {
  const members = membersOf(couple);
  const size = game.payload.size;
  const swipes = Object.fromEntries(members.map((id) => [id, {}]));
  const matches = [];
  for (const move of game.moves) {
    if (move.data?.kind !== 'swipe' || !swipes[move.memberId]) continue;
    const { index, like } = move.data;
    if (!Number.isInteger(index) || index < 0 || index >= size || swipes[move.memberId][index] !== undefined) continue;
    swipes[move.memberId][index] = like;
    if (like && members.every((id) => swipes[id][index] === true)) matches.push(index);
  }
  return {
    members,
    size,
    swipes,
    matches,
    complete: members.every((id) => Object.keys(swipes[id]).length >= size),
  };
}

function validateMovie(game, couple, memberId, data) {
  const state = movieState(game, couple);
  if (data.kind !== 'swipe') reject('invalid_game_move', 'Movie roulette only accepts swipe actions');
  if (state.complete) reject('game_complete', 'Both members finished the deck', 409);
  const expected = Array.from({ length: state.size }, (_, index) => index)
    .find((index) => state.swipes[memberId][index] === undefined);
  const index = integer(data.index, 'index', 0, state.size - 1);
  if (index !== expected) reject('wrong_card', `The next card index is ${expected}`, 409);
  const normalized = { kind: 'swipe', index, like: boolean(data.like, 'like') };
  if (data.match && typeof data.match === 'object' && data.match.cardIndex === index) {
    normalized.match = {
      cardIndex: index,
      title: typeof data.match.title === 'string' ? data.match.title.slice(0, 200) : null,
    };
  }
  return normalized;
}

function battleshipLayout(value) {
  if (typeof value !== 'string') return null;
  const ships = value.split('|').map((part) => part.split(',').map(Number));
  if (ships.some((ship) => ship.length === 0 || ship.some((cell) => !Number.isInteger(cell)))) return null;
  return ships;
}

function validFleet(ships) {
  if (!ships || JSON.stringify(ships.map((ship) => ship.length).sort((a, b) => a - b)) !== '[2,3,3,4]') return false;
  const seen = new Set();
  for (const ship of ships) {
    const cells = [...ship].sort((a, b) => a - b);
    if (cells.some((cell) => cell < 0 || cell >= 64 || seen.has(cell)) || new Set(cells).size !== cells.length) return false;
    const rows = new Set(cells.map((cell) => Math.floor(cell / 8)));
    const columns = new Set(cells.map((cell) => cell % 8));
    const horizontal = rows.size === 1 && cells.at(-1) - cells[0] === cells.length - 1;
    const vertical = columns.size === 1 && cells.at(-1) - cells[0] === (cells.length - 1) * 8;
    if (!horizontal && !vertical) return false;
    cells.forEach((cell) => seen.add(cell));
  }
  return true;
}

function expectedReport(cells, ships, alreadyHit) {
  const occupied = new Set(ships.flat());
  const hits = cells.filter((cell) => occupied.has(cell));
  const total = new Set([...alreadyHit, ...hits]);
  const sunk = ships
    .filter((ship) => ship.every((cell) => total.has(cell)) && !ship.every((cell) => alreadyHit.has(cell)))
    .map((ship) => ship.length)
    .sort((a, b) => a - b);
  return { hits, sunk };
}

function battleshipState(game, couple) {
  const members = requirePair(couple);
  const starter = game.createdBy;
  const partner = opponent(members, starter);
  const commits = {};
  const salvos = [];
  const reports = {};
  const reveals = {};
  for (const move of game.moves) {
    const { data } = move;
    if (data?.kind === 'commit' && !commits[move.memberId]) commits[move.memberId] = data.commit;
    else if (data?.kind === 'salvo') salvos.push({ memberId: move.memberId, cells: data.cells });
    else if (data?.kind === 'report' && reports[data.index] === undefined) {
      reports[data.index] = { memberId: move.memberId, hits: data.hits, sunk: data.sunk };
    } else if (data?.kind === 'reveal' && !reveals[move.memberId]) {
      reveals[move.memberId] = { layout: data.reveal, ships: battleshipLayout(data.reveal) };
    }
  }
  const claimedHits = Object.fromEntries(members.map((id) => [id, 0]));
  for (let index = 0; index < salvos.length; index += 1) {
    claimedHits[salvos[index].memberId] += reports[index]?.hits.length ?? 0;
  }
  return { members, starter, partner, commits, salvos, reports, reveals, claimedHits };
}

function validateBattleship(game, couple, memberId, data) {
  const state = battleshipState(game, couple);
  if (data.kind === 'commit') {
    if (state.salvos.length > 0) reject('wrong_phase', 'Fleet setup is already over', 409);
    if (state.commits[memberId]) reject('duplicate_move', 'This member already committed a fleet', 409);
    const commit = text(data.commit, 'commit', 64);
    if (!/^[0-9a-f]{64}$/i.test(commit)) reject('invalid_game_move', 'Commit must be a SHA-256 hex digest');
    return { kind: 'commit', commit: commit.toLowerCase() };
  }
  if (!state.members.every((id) => state.commits[id])) reject('wrong_phase', 'Both fleets must be committed first', 409);
  if (data.kind === 'salvo') {
    const previous = state.salvos.length - 1;
    if (previous >= 0 && !state.reports[previous]) reject('wrong_phase', 'The previous salvo still needs a report', 409);
    const actor = state.salvos.length % 2 === 0 ? state.starter : state.partner;
    if (memberId !== actor) reject('wrong_turn', 'It is the other member’s turn', 409);
    if (!Array.isArray(data.cells) || data.cells.length < 1 || data.cells.length > 2) {
      reject('invalid_game_move', 'A salvo needs one or two cells');
    }
    const cells = [...new Set(data.cells.map((cell) => integer(cell, 'cell', 0, 63)))];
    if (cells.length !== data.cells.length) reject('duplicate_move', 'A salvo cannot repeat a cell');
    const previousCells = new Set(state.salvos.filter((salvo) => salvo.memberId === memberId).flatMap((salvo) => salvo.cells));
    if (cells.some((cell) => previousCells.has(cell))) reject('duplicate_move', 'That cell was already targeted', 409);
    return { kind: 'salvo', cells };
  }
  if (data.kind === 'report') {
    const index = integer(data.index, 'index', 0, state.salvos.length - 1);
    const salvo = state.salvos[index];
    if (!salvo || salvo.memberId === memberId) reject('wrong_actor', 'Only the defender may report this salvo', 403);
    if (state.reports[index]) reject('duplicate_move', 'This salvo already has a report', 409);
    const pending = state.salvos.findIndex((_, candidate) => !state.reports[candidate]);
    if (index !== pending) reject('wrong_phase', `Report salvo ${pending} first`, 409);
    const allowed = new Set(salvo.cells);
    const hits = Array.isArray(data.hits)
      ? [...new Set(data.hits.map((cell) => integer(cell, 'hit', 0, 63)))]
      : [];
    if (hits.some((cell) => !allowed.has(cell))) reject('invalid_game_move', 'Hits must belong to the reported salvo');
    const sunk = Array.isArray(data.sunk)
      ? data.sunk.map((size) => integer(size, 'sunk ship size', 2, 4))
      : [];
    return { kind: 'report', index, hits, sunk };
  }
  if (data.kind === 'reveal') {
    if (Math.max(...Object.values(state.claimedHits)) < 12) {
      reject('wrong_phase', 'Fleets are revealed only after a claimed win', 409);
    }
    if (state.reveals[memberId]) reject('duplicate_move', 'This member already revealed a fleet', 409);
    const reveal = verifiedReveal(game, memberId, data);
    if (!validFleet(battleshipLayout(reveal.reveal))) reject('invalid_fleet', 'Revealed fleet layout is invalid', 409);
    return { kind: 'reveal', ...reveal };
  }
  reject('invalid_game_move', 'Unsupported battleship action');
}

function slfState(game, couple) {
  const members = membersOf(couple);
  const rounds = Array.from(
    { length: game.payload.rounds },
    () => ({ commits: {}, reveals: {}, ratings: {} }),
  );
  for (const move of game.moves) {
    const round = rounds[move.data?.round];
    if (!round) continue;
    if (move.data.kind === 'commit' && !round.commits[move.memberId]) round.commits[move.memberId] = move;
    else if (move.data.kind === 'reveal' && !round.reveals[move.memberId]) round.reveals[move.memberId] = move.data.reveal;
    else if (move.data.kind === 'rate' && !round.ratings[move.memberId]) round.ratings[move.memberId] = move.data.verdicts;
  }
  const phase = (round) => {
    if (members.every((id) => round.ratings[id])) return 'done';
    if (members.every((id) => round.reveals[id] !== undefined)) return 'rating';
    if (members.every((id) => round.commits[id])) return 'revealing';
    return 'collecting';
  };
  const current = rounds.findIndex((round) => phase(round) !== 'done');
  return { members, rounds, phase, current: current === -1 ? rounds.length : current };
}

function validateStadtLandFluss(game, couple, memberId, data) {
  const state = slfState(game, couple);
  if (state.current >= state.rounds.length) reject('game_complete', 'Every word round is complete', 409);
  const roundIndex = integer(data.round, 'round', 0, state.rounds.length - 1);
  if (roundIndex !== state.current) reject('wrong_round', `The active round is ${state.current}`, 409);
  const round = state.rounds[roundIndex];
  const phase = state.phase(round);
  if (data.kind === 'commit') {
    if (phase !== 'collecting') reject('wrong_phase', 'Answer collection is closed', 409);
    if (round.commits[memberId]) reject('duplicate_move', 'This member already committed answers', 409);
    const commit = text(data.commit, 'commit', 64);
    if (!/^[0-9a-f]{64}$/i.test(commit)) reject('invalid_game_move', 'Commit must be a SHA-256 hex digest');
    return { kind: 'commit', round: roundIndex, commit: commit.toLowerCase() };
  }
  if (data.kind === 'reveal') {
    if (!['revealing', 'rating'].includes(phase)) reject('wrong_phase', 'Both members must commit before revealing', 409);
    if (round.reveals[memberId] !== undefined) reject('duplicate_move', 'This member already revealed answers', 409);
    const reveal = verifiedReveal(game, memberId, data);
    const parts = reveal.reveal.split('\u001f');
    if (parts.length > game.payload.categories.length || parts.some((part) => part.length > 120)) {
      reject('invalid_game_move', 'Revealed answers do not match the category count');
    }
    return { kind: 'reveal', round: roundIndex, ...reveal };
  }
  if (data.kind === 'rate') {
    if (phase !== 'rating') reject('wrong_phase', 'Both members must reveal before rating', 409);
    if (round.ratings[memberId]) reject('duplicate_move', 'This member already rated the round', 409);
    if (!Array.isArray(data.verdicts) || data.verdicts.length !== game.payload.categories.length
        || !data.verdicts.every((value) => typeof value === 'boolean')) {
      reject('invalid_game_move', 'Verdicts must contain one boolean per category');
    }
    return { kind: 'rate', round: roundIndex, verdicts: data.verdicts };
  }
  reject('invalid_game_move', 'Unsupported Stadt-Land-Fluss action');
}

function twoTruthsState(game, couple) {
  const members = requirePair(couple);
  const starter = game.createdBy;
  const partner = opponent(members, starter);
  const rounds = Array.from({ length: game.payload.rounds }, () => ({ statements: null, guess: null, reveal: null }));
  for (const move of game.moves) {
    const round = rounds[move.data?.round];
    if (!round) continue;
    if (move.data.kind === 'statements' && !round.statements) round.statements = move;
    else if (move.data.kind === 'guess' && round.guess === null) round.guess = move.data.pick;
    else if (move.data.kind === 'reveal' && round.reveal === null) round.reveal = Number(move.data.reveal);
  }
  const current = rounds.findIndex((round) => round.reveal === null);
  return { members, starter, partner, rounds, current: current === -1 ? rounds.length : current };
}

function validateTwoTruths(game, couple, memberId, data) {
  const state = twoTruthsState(game, couple);
  if (state.current >= state.rounds.length) reject('game_complete', 'Every two-truths round is complete', 409);
  const roundIndex = integer(data.round, 'round', 0, state.rounds.length - 1);
  if (roundIndex !== state.current) reject('wrong_round', `The active round is ${state.current}`, 409);
  const teller = roundIndex % 2 === 0 ? state.starter : state.partner;
  const round = state.rounds[roundIndex];
  if (data.kind === 'statements') {
    if (memberId !== teller) reject('wrong_actor', 'Only the teller may submit statements', 403);
    if (round.statements) reject('duplicate_move', 'Statements already exist for this round', 409);
    if (!Array.isArray(data.texts) || data.texts.length !== 3) {
      reject('invalid_game_move', 'Exactly three statements are required');
    }
    const texts = data.texts.map((value) => text(value, 'statement', 300));
    const commit = text(data.commit, 'commit', 64);
    if (!/^[0-9a-f]{64}$/i.test(commit)) reject('invalid_game_move', 'Commit must be a SHA-256 hex digest');
    return { kind: 'statements', round: roundIndex, texts, commit: commit.toLowerCase() };
  }
  if (data.kind === 'guess') {
    if (memberId === teller) reject('wrong_actor', 'The teller cannot guess', 403);
    if (!round.statements) reject('wrong_phase', 'Statements are required before guessing', 409);
    if (round.guess !== null) reject('duplicate_move', 'This round already has a guess', 409);
    return { kind: 'guess', round: roundIndex, pick: integer(data.pick, 'pick', 0, 2) };
  }
  if (data.kind === 'reveal') {
    if (memberId !== teller) reject('wrong_actor', 'Only the teller may reveal the lie', 403);
    if (round.guess === null) reject('wrong_phase', 'A guess is required before revealing', 409);
    if (round.reveal !== null) reject('duplicate_move', 'This round already has a reveal', 409);
    const reveal = verifiedReveal(game, memberId, data);
    integer(Number(reveal.reveal), 'reveal', 0, 2);
    return { kind: 'reveal', round: roundIndex, ...reveal };
  }
  reject('invalid_game_move', 'Unsupported two-truths action');
}

function dailyQuestIndexes(coupleId, dateKey, poolSize = 48) {
  let hash = 5381n;
  for (const scalar of `quests|${dateKey}|${coupleId}`) {
    hash = ((hash << 5n) + hash + BigInt(scalar.codePointAt(0))) & MASK_64;
  }
  const signed = BigInt.asIntN(64, hash);
  const next = seedGenerator(signed);
  const picked = [];
  while (picked.length < Math.min(3, poolSize)) {
    const index = next(poolSize);
    if (!picked.includes(index)) picked.push(index);
  }
  return picked;
}

function dailyState(game, couple) {
  const valid = dailyQuestIndexes(couple.id, game.payload.dateKey);
  const done = {};
  for (const move of game.moves) {
    const index = move.data?.questIndex;
    if (move.data?.kind === 'quest_done' && valid.includes(index) && done[index] === undefined) {
      done[index] = move.memberId;
    }
  }
  return { valid, done, complete: Object.keys(done).length === valid.length };
}

function validateDailyQuests(game, couple, memberId, data) {
  const state = dailyState(game, couple);
  if (data.kind !== 'quest_done') reject('invalid_game_move', 'Daily quests only accepts quest_done actions');
  if (state.complete) reject('game_complete', 'Every daily quest is complete', 409);
  const questIndex = integer(data.questIndex, 'questIndex', 0, 47);
  if (!state.valid.includes(questIndex)) reject('invalid_quest', 'That quest is not part of this day', 409);
  if (state.done[questIndex] !== undefined) reject('duplicate_move', 'That quest is already complete', 409);
  return { kind: 'quest_done', questIndex };
}

// ---------------------------------------------------------------------------
// v5.0 word & party games

const RPS_CHOICES = Object.freeze(['rock', 'paper', 'scissors']);
const RPS_BEATS = Object.freeze({ rock: 'scissors', paper: 'rock', scissors: 'paper' });

function isLetters(value) {
  return typeof value === 'string' && /^\p{L}+$/u.test(value);
}

/** Case-fold for word comparisons; keeps umlauts, folds ß → ss. */
function normalizeWord(value) {
  return value.toLocaleLowerCase('de-DE').replaceAll('ß', 'ss').trim();
}

function currentWeekKey(date = new Date()) {
  const value = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const day = value.getUTCDay() || 7;
  value.setUTCDate(value.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(value.getUTCFullYear(), 0, 1));
  const week = Math.ceil((((value - yearStart) / 86_400_000) + 1) / 7);
  return `${value.getUTCFullYear()}-W${String(week).padStart(2, '0')}`;
}

// --- Koop-Wordle "Duo" ------------------------------------------------------
// One shared six-row board, alternating guessers. Both clients derive the
// same daily target word from (coupleId, dateKey, lang); the creator seals it
// as a SHA-256 commit up front and reveals it at the end, so the recorded
// result is provably about the real word.

function wordleDuoState(game, couple) {
  const members = requirePair(couple);
  const starter = game.createdBy;
  const partner = opponent(members, starter);
  let commit = null;
  const guesses = [];
  let reveal = null;
  for (const move of game.moves) {
    const { data } = move;
    if (data?.kind === 'target' && !commit && move.memberId === starter) {
      commit = data.commit;
    } else if (data?.kind === 'guess' && commit && !reveal) {
      const expected = guesses.length % 2 === 0 ? starter : partner;
      if (move.memberId === expected && data.row === guesses.length) guesses.push(data.text);
    } else if (data?.kind === 'reveal' && !reveal && move.memberId === starter) {
      reveal = data.reveal;
    }
  }
  return { members, starter, partner, commit, guesses, reveal };
}

function validateWordleDuo(game, couple, memberId, data) {
  const state = wordleDuoState(game, couple);
  if (state.reveal !== null) reject('game_complete', 'This duo board is already revealed', 409);
  if (data.kind === 'target') {
    if (memberId !== state.starter) reject('wrong_actor', 'Only the creator seals the target word', 403);
    if (state.commit) reject('duplicate_move', 'The target word is already sealed', 409);
    const commit = text(data.commit, 'commit', 64);
    if (!/^[0-9a-f]{64}$/i.test(commit)) reject('invalid_game_move', 'Commit must be a SHA-256 hex digest');
    return { kind: 'target', commit: commit.toLowerCase() };
  }
  if (!state.commit) reject('wrong_phase', 'The target word must be sealed first', 409);
  if (data.kind === 'guess') {
    if (state.guesses.length >= game.payload.maxRows) {
      reject('wrong_phase', 'All rows are used — reveal the word', 409);
    }
    const expected = state.guesses.length % 2 === 0 ? state.starter : state.partner;
    if (memberId !== expected) reject('wrong_turn', 'It is the other member’s row', 409);
    const row = integer(data.row, 'row', 0, game.payload.maxRows - 1);
    if (row !== state.guesses.length) reject('wrong_round', `The active row is ${state.guesses.length}`, 409);
    const guess = text(data.text, 'text', 12);
    if (!isLetters(guess) || [...guess].length !== 5) {
      reject('invalid_game_move', 'A guess must be exactly five letters');
    }
    return { kind: 'guess', row, text: guess };
  }
  if (data.kind === 'reveal') {
    if (memberId !== state.starter) reject('wrong_actor', 'Only the creator may reveal the target word', 403);
    if (state.guesses.length === 0) reject('wrong_phase', 'Guess at least one row before revealing', 409);
    const reveal = verifiedReveal(game, memberId, data);
    if (!isLetters(reveal.reveal) || [...reveal.reveal].length !== 5) {
      reject('invalid_game_move', 'The revealed word must be exactly five letters');
    }
    // The board must actually be DONE: a guess hit the (commit-verified)
    // target, or every row is used. Without this guard the creator could
    // end the board after ONE arbitrary miss — the clients only reveal on
    // solved/exhausted boards, so an earlier reveal is always a bug or an
    // abort in disguise.
    const target = normalizeWord(reveal.reveal);
    const solved = state.guesses.some((guess) => normalizeWord(guess) === target);
    if (!solved && state.guesses.length < game.payload.maxRows) {
      reject('wrong_phase', 'The board is still in play — solve it or use every row first', 409);
    }
    return { kind: 'reveal', ...reveal };
  }
  reject('invalid_game_move', 'Unsupported duo-wordle action');
}

function wordleDuoResult(game, couple) {
  const state = wordleDuoState(game, couple);
  if (state.reveal === null) return { complete: false, result: null };
  const target = normalizeWord(state.reveal);
  const solvedRow = state.guesses.findIndex((guess) => normalizeWord(guess) === target);
  return {
    complete: true,
    result: {
      solved: solvedRow !== -1,
      rows: solvedRow !== -1 ? solvedRow + 1 : state.guesses.length,
      target: state.reveal,
      dateKey: game.payload.dateKey,
      lang: game.payload.lang,
    },
  };
}

// --- Galgenraten "Unser Wort" ------------------------------------------------
// The creator (setter) seals a personal word (commit + declared length +
// hint); the guesser picks letters, the setter answers with the positions.
// Instead of a gallows a heart flower wilts: ten wrong letters lose. The
// final verified reveal lets the server audit every position report —
// dishonest answers void the win (battleship integrity pattern).

function hangmanState(game, couple) {
  const members = requirePair(couple);
  const setter = game.createdBy;
  const guesser = opponent(members, setter);
  let setup = game.payload.commit
    ? { commit: game.payload.commit, len: game.payload.len, hint: game.payload.hint ?? '' }
    : null;
  const asked = [];
  let reveal = null;
  for (const move of game.moves) {
    const { data } = move;
    if (data?.kind === 'setup' && !setup && move.memberId === setter) {
      setup = { commit: data.commit, len: data.len, hint: data.hint };
    } else if (data?.kind === 'letter' && setup && !reveal && move.memberId === guesser) {
      const pending = asked.some((entry) => entry.positions === null);
      if (!pending && !asked.some((entry) => entry.letter === data.letter)) {
        asked.push({ letter: data.letter, positions: null });
      }
    } else if (data?.kind === 'positions' && setup && !reveal && move.memberId === setter) {
      const pending = asked.find((entry) => entry.positions === null);
      if (pending && pending.letter === data.letter) pending.positions = data.positions;
    } else if (data?.kind === 'reveal' && setup && !reveal && move.memberId === setter) {
      reveal = data.reveal;
    }
  }
  const found = new Set(asked.flatMap((entry) => entry.positions ?? []));
  const wrong = asked.filter((entry) => entry.positions !== null && entry.positions.length === 0).length;
  const solved = setup ? found.size >= setup.len : false;
  const lost = setup ? wrong >= game.payload.maxWrong : false;
  return { members, setter, guesser, setup, asked, reveal, found, wrong, solved, lost };
}

function validateHangman(game, couple, memberId, data) {
  const state = hangmanState(game, couple);
  if (state.reveal !== null) reject('game_complete', 'The word is already revealed', 409);
  if (data.kind === 'setup') {
    if (memberId !== state.setter) reject('wrong_actor', 'Only the creator sets the secret word', 403);
    if (state.setup) reject('duplicate_move', 'The word is already sealed', 409);
    const commit = text(data.commit, 'commit', 64);
    if (!/^[0-9a-f]{64}$/i.test(commit)) reject('invalid_game_move', 'Commit must be a SHA-256 hex digest');
    const len = integer(data.len, 'len', 3, 24);
    const hint = data.hint === undefined ? '' : text(data.hint, 'hint', 60, { allowEmpty: true });
    return { kind: 'setup', commit: commit.toLowerCase(), len, hint };
  }
  if (!state.setup) reject('wrong_phase', 'The secret word must be sealed first', 409);
  if (data.kind === 'letter') {
    if (memberId !== state.guesser) reject('wrong_actor', 'Only the guesser may pick letters', 403);
    if (state.solved || state.lost) reject('wrong_phase', 'The round is over — waiting for the reveal', 409);
    if (state.asked.some((entry) => entry.positions === null)) {
      reject('wrong_phase', 'The last letter still needs an answer', 409);
    }
    const letter = text(data.letter, 'letter', 2).toLocaleLowerCase('de-DE');
    if (!/^\p{L}$/u.test(letter)) reject('invalid_game_move', 'A guess must be a single letter');
    if (state.asked.some((entry) => entry.letter === letter)) {
      reject('duplicate_move', 'That letter was already guessed', 409);
    }
    return { kind: 'letter', letter };
  }
  if (data.kind === 'positions') {
    if (memberId !== state.setter) reject('wrong_actor', 'Only the setter answers letters', 403);
    const pending = state.asked.find((entry) => entry.positions === null);
    if (!pending) reject('wrong_phase', 'There is no unanswered letter', 409);
    if (data.letter !== pending.letter) reject('invalid_game_move', `Answer the pending letter "${pending.letter}"`);
    if (!Array.isArray(data.positions) || data.positions.length > state.setup.len) {
      reject('invalid_game_move', '"positions" must be an array of board indexes');
    }
    const positions = [...new Set(data.positions.map((value) => integer(value, 'position', 0, state.setup.len - 1)))]
      .sort((a, b) => a - b);
    if (positions.length !== data.positions.length) reject('duplicate_move', 'Positions cannot repeat', 409);
    const taken = new Set(state.asked.flatMap((entry) => entry.positions ?? []));
    if (positions.some((value) => taken.has(value))) {
      reject('invalid_game_move', 'A position was already revealed by an earlier letter');
    }
    return { kind: 'positions', letter: pending.letter, positions };
  }
  if (data.kind === 'reveal') {
    if (memberId !== state.setter) reject('wrong_actor', 'Only the setter may reveal the word', 403);
    if (!state.solved && !state.lost) {
      reject('wrong_phase', 'The word is revealed after a win or ten wrong letters', 409);
    }
    const reveal = verifiedReveal(game, memberId, data);
    if (!isLetters(reveal.reveal) || [...reveal.reveal].length !== state.setup.len) {
      reject('invalid_word', 'The revealed word does not match the sealed length', 409);
    }
    return { kind: 'reveal', ...reveal };
  }
  reject('invalid_game_move', 'Unsupported hangman action');
}

function hangmanResult(game, couple) {
  const state = hangmanState(game, couple);
  if (state.reveal === null) return { complete: false, result: null };
  const word = [...state.reveal.toLocaleLowerCase('de-DE')];
  let honest = word.length === state.setup.len;
  for (const entry of state.asked) {
    if (entry.positions === null) continue;
    const expected = word
      .map((chr, index) => (chr === entry.letter ? index : -1))
      .filter((index) => index !== -1);
    if (JSON.stringify(expected) !== JSON.stringify(entry.positions)) honest = false;
  }
  const winner = state.solved && !state.lost ? state.guesser : state.setter;
  const scores = Object.fromEntries(state.members.map((id) => [id, honest && winner === id ? 1 : 0]));
  return {
    complete: true,
    result: scoresResult(state.members, scores, {
      winner: honest ? winner : null,
      integrity: honest,
      word: state.reveal,
      wrong: state.wrong,
      solved: state.solved && !state.lost,
    }),
  };
}

// --- Schere-Stein-Papier: Best-of ---------------------------------------------
// Per round both members commit sha256(choice + salt), then both reveal;
// the server verifies every reveal against that member's round commit, so
// nobody can wait for the partner's choice. Ties replay; first to `target`
// round wins takes the duel.

function rpsState(game, couple) {
  const members = requirePair(couple);
  const target = game.payload.target;
  const rounds = [];
  const roundOf = (index) => {
    while (rounds.length <= index) rounds.push({ commits: {}, reveals: {} });
    return rounds[index];
  };
  for (const move of game.moves) {
    const { data } = move;
    if (!Number.isInteger(data?.round) || data.round < 0) continue;
    const round = roundOf(data.round);
    if (data.kind === 'commit' && round.commits[move.memberId] === undefined) {
      round.commits[move.memberId] = data.commit;
    } else if (data.kind === 'reveal' && round.reveals[move.memberId] === undefined) {
      round.reveals[move.memberId] = data.reveal;
    }
  }
  const scores = Object.fromEntries(members.map((id) => [id, 0]));
  let winner = null;
  let current = 0;
  for (let index = 0; index < rounds.length; index += 1) {
    const round = rounds[index];
    if (!members.every((id) => round.reveals[id] !== undefined)) break;
    const [a, b] = members;
    if (round.reveals[a] !== round.reveals[b]) {
      const roundWinner = RPS_BEATS[round.reveals[a]] === round.reveals[b] ? a : b;
      scores[roundWinner] += 1;
      if (!winner && scores[roundWinner] >= target) winner = roundWinner;
    }
    current = index + 1;
  }
  return { members, target, rounds, scores, winner, current };
}

function validateRps(game, couple, memberId, data) {
  const state = rpsState(game, couple);
  if (state.winner) reject('game_complete', 'This duel already has a winner', 409);
  const round = integer(data.round, 'round', 0, 1000);
  if (round !== state.current) reject('wrong_round', `The active round is ${state.current}`, 409);
  const record = state.rounds[round] ?? { commits: {}, reveals: {} };
  if (data.kind === 'commit') {
    if (record.commits[memberId] !== undefined) reject('duplicate_move', 'This member already committed this round', 409);
    const commit = text(data.commit, 'commit', 64);
    if (!/^[0-9a-f]{64}$/i.test(commit)) reject('invalid_game_move', 'Commit must be a SHA-256 hex digest');
    return { kind: 'commit', round, commit: commit.toLowerCase() };
  }
  if (data.kind === 'reveal') {
    if (!state.members.every((id) => record.commits[id] !== undefined)) {
      reject('wrong_phase', 'Both members must commit before revealing', 409);
    }
    if (record.reveals[memberId] !== undefined) reject('duplicate_move', 'This member already revealed this round', 409);
    const reveal = text(data.reveal, 'reveal', 20, { allowEmpty: true });
    const salt = text(data.salt, 'salt', 256, { allowEmpty: true });
    if (!RPS_CHOICES.includes(reveal)) reject('invalid_game_move', 'Reveal must be rock, paper or scissors');
    if (sha256Hex(reveal + salt) !== record.commits[memberId]) {
      reject('reveal_mismatch', 'Reveal does not match this member’s commitment', 409);
    }
    return { kind: 'reveal', round, reveal, salt, verified: true };
  }
  reject('invalid_game_move', 'Unsupported rock-paper-scissors action');
}

// --- Fortsetzungsgeschichte ---------------------------------------------------
// Alternating sentences onto one shared story; genre + twist positions come
// deterministically from the payload seed (client content). Purely
// cooperative — the finished story is the prize.

function storyState(game, couple) {
  const members = requirePair(couple);
  const starter = game.createdBy;
  const partner = opponent(members, starter);
  const sentences = [];
  for (const move of game.moves) {
    const { data } = move;
    if (data?.kind !== 'sentence' || data.index !== sentences.length) continue;
    const expected = sentences.length % 2 === 0 ? starter : partner;
    if (move.memberId !== expected) continue;
    sentences.push(data.text);
  }
  return {
    members,
    starter,
    partner,
    sentences,
    total: game.payload.sentences,
    complete: sentences.length >= game.payload.sentences,
  };
}

function validateStory(game, couple, memberId, data) {
  const state = storyState(game, couple);
  if (data.kind !== 'sentence') reject('invalid_game_move', 'A story only accepts sentence actions');
  if (state.complete) reject('game_complete', 'The story is finished', 409);
  const index = integer(data.index, 'index', 0, state.total - 1);
  if (index !== state.sentences.length) reject('wrong_round', `The next sentence index is ${state.sentences.length}`, 409);
  const expected = index % 2 === 0 ? state.starter : state.partner;
  if (memberId !== expected) reject('wrong_turn', 'It is the other member’s sentence', 409);
  return { kind: 'sentence', index, text: text(data.text, 'text', 200) };
}

// --- Wortkette-Blitz ------------------------------------------------------------
// Cooperative chain: every word must start with the last letter of the
// previous one (ß folds to s), no repeats. The member whose turn it is may
// end the chain — the shared score is its length.

function lastChainLetter(word) {
  const normalized = normalizeWord(word);
  return normalized[normalized.length - 1];
}

function wordchainState(game, couple) {
  const members = requirePair(couple);
  const starter = game.createdBy;
  const partner = opponent(members, starter);
  const words = [];
  let finished = false;
  for (const move of game.moves) {
    const { data } = move;
    if (finished) break;
    if (data?.kind === 'word' && data.index === words.length) {
      const expected = words.length % 2 === 0 ? starter : partner;
      if (move.memberId === expected) words.push(data.text);
    } else if (data?.kind === 'finish') {
      finished = true;
    }
  }
  return { members, starter, partner, words, finished };
}

function validateWordchain(game, couple, memberId, data) {
  const state = wordchainState(game, couple);
  if (state.finished) reject('game_complete', 'This chain is finished', 409);
  const expected = state.words.length % 2 === 0 ? state.starter : state.partner;
  if (data.kind === 'word') {
    if (memberId !== expected) reject('wrong_turn', 'It is the other member’s word', 409);
    const index = integer(data.index, 'index', 0, 10_000);
    if (index !== state.words.length) reject('wrong_round', `The next word index is ${state.words.length}`, 409);
    const word = text(data.text, 'text', 40).trim();
    if (!isLetters(word) || [...word].length < 2) {
      reject('invalid_game_move', 'A chain word needs at least two letters (letters only)');
    }
    const normalized = normalizeWord(word);
    if (!WORD_CHAIN_WORDS[game.payload.lang].has(word.toLocaleLowerCase('de-DE'))) {
      reject('unknown_word', 'That word is not in the validated chain dictionary', 409);
    }
    if (state.words.some((existing) => normalizeWord(existing) === normalized)) {
      reject('duplicate_move', 'That word was already used', 409);
    }
    if (state.words.length > 0) {
      const required = lastChainLetter(state.words.at(-1));
      if (!normalized.startsWith(required)) {
        reject('wrong_letter', `The next word must start with "${required.toUpperCase()}"`, 409);
      }
    }
    return { kind: 'word', index, text: word };
  }
  if (data.kind === 'finish') {
    if (memberId !== expected) reject('wrong_actor', 'Only the member whose turn it is may end the chain', 403);
    if (state.words.length === 0) reject('wrong_phase', 'Play at least one word first', 409);
    return { kind: 'finish' };
  }
  reject('invalid_game_move', 'Unsupported word-chain action');
}

// --- Paar-Bingo ---------------------------------------------------------------
// The client cannot check tiles. Validated app events are converted into
// synthetic `auto_check` moves by `applyBingoAppEvent` below.

const BINGO_LINES = Object.freeze([
  [0, 1, 2, 3], [4, 5, 6, 7], [8, 9, 10, 11], [12, 13, 14, 15],
  [0, 4, 8, 12], [1, 5, 9, 13], [2, 6, 10, 14], [3, 7, 11, 15],
  [0, 5, 10, 15], [3, 6, 9, 12],
]);

function bingoState(game, couple) {
  const members = requirePair(couple);
  const checked = {};
  for (const move of game.moves) {
    const index = move.data?.cardIndex;
    if (move.data?.kind === 'auto_check'
        && Number.isInteger(index)
        && index >= 0
        && index < 16
        && checked[index] === undefined) {
      checked[index] = {
        memberId: move.memberId,
        appEventId: move.data.appEventId,
      };
    }
  }
  const completedLine = BINGO_LINES.find((line) => line.every((index) => checked[index])) ?? null;
  return { members, checked, completedLine };
}

function validateBingo() {
  reject('auto_checked_only', 'Bingo tiles are checked only by validated app events', 409);
}

// ---------------------------------------------------------------------------
// Played-game semantics + persistent aggregates (re-eval 2, Spieltisch
// Befunde 8 + 9; Fix-Runde 3, Befunde 5 + 6)

/**
 * `capList(couple.games, …)` cap — lives HERE (not only in the router's
 * LIMITS table) because the aggregate seed below needs it to mark a
 * seed taken from an already-capped list as a lower bound. The router's
 * `LIMITS.games` reads this constant, so the two can never drift.
 */
export const GAMES_LIST_LIMIT = 1000;

/**
 * The ONE "played game" rule (Befund 8), mirrored VERBATIM client-side by
 * `PlayHubCuration.isPlayedGame` (LogicTest-pinned): a session was PLAYED
 * when it ended with recorded moves or a real result. Administrative ends
 * are noise — a cancelled or declined lobby, a rules-migration
 * invalidation without a single move (Fix-Runde 3, Befund 5), or an empty
 * result object carrying no outcome at all — and must never inflate the
 * couple's biography numbers or the "recently played" history.
 */
export function isPlayedGame(game) {
  if (game?.state !== 'ended') return false;
  if (Array.isArray(game.moves) && game.moves.length > 0) return true;
  const result = game.result;
  if (!result || typeof result !== 'object') return false;
  if (result.cancelled === true || result.declined === true) return false;
  // A zero-move session the rules migration had to invalidate was a
  // lobby that never saw play — administrative, not a Partie.
  if (result.invalidated === true) return false;
  // An empty `{}` result proves nothing was played either (real results
  // always carry data: scores/winner, matches, completedBy, …).
  if (Object.keys(result).length === 0) return false;
  return true;
}

/**
 * Fresh aggregate counted from the (possibly already capped) stored list.
 * A list AT the cap has (in all likelihood) already evicted history the
 * seed can no longer see — the aggregate carries `seededFromCapped` then,
 * and the stats endpoint surfaces it as `lowerBound` so clients can label
 * the numbers honestly ("{n}+") instead of presenting a floor as a total
 * (Fix-Runde 3, Befund 6).
 */
export function seededGamesAggregate(couple) {
  const aggregate = { total: 0, perKind: {} };
  for (const game of couple.games ?? []) {
    if (!isPlayedGame(game)) continue;
    aggregate.total += 1;
    aggregate.perKind[game.type] = (aggregate.perKind[game.type] ?? 0) + 1;
  }
  if ((couple.games?.length ?? 0) >= GAMES_LIST_LIMIT) {
    aggregate.seededFromCapped = true;
  }
  return aggregate;
}

/**
 * Persistent whole-life aggregate (Befund 9): `capList(couple.games,
 * LIMITS.games)` evicts the oldest sessions, so counting the list undercounts
 * a long couple's life. The aggregate is written forward on every finish and
 * initialised ONCE from the stored history — at startup for existing couples
 * (game-migrations.js) and lazily here as a safety net for stores written by
 * a pre-aggregate server mid-flight.
 */
export function ensureGamesAggregate(couple) {
  if (!couple.gamesAggregate) {
    couple.gamesAggregate = seededGamesAggregate(couple);
  }
  return couple.gamesAggregate;
}

/**
 * The ONE way a session ends (router `finishGame` and the bingo auto-end
 * both come through here): flips the state, counts the legacy
 * `counters.gamesPlayed`, and writes the persistent aggregate forward for
 * PLAYED games — BEFORE eviction can ever touch the entry. Idempotent:
 * an already-ended session never double-counts.
 */
export function recordGameEnd(couple, game) {
  if (game.state === 'ended') return;
  // Seed from the list BEFORE the flip so the seed cannot already
  // contain the game this call is about to count.
  const aggregate = ensureGamesAggregate(couple);
  if (game.state === 'active') couple.counters.gamesPlayed += 1;
  game.state = 'ended';
  if (isPlayedGame(game)) {
    aggregate.total += 1;
    aggregate.perKind[game.type] = (aggregate.perKind[game.type] ?? 0) + 1;
  }
}

/**
 * Applies one canonical app event to every active weekly bingo board.
 * Returns changes so events.js can broadcast them after persistence.
 */
export function applyBingoAppEvent(couple, event) {
  const changes = [];
  for (const game of couple.games ?? []) {
    if (game.type !== 'bingo' || game.state !== 'active') continue;
    if (game.payload?.weekKey !== currentWeekKey(new Date(event.createdAt))) continue;
    const state = bingoState(game, couple);
    const position = (game.payload.cardIndexes ?? []).findIndex((actionIndex, cardIndex) => (
      !state.checked[cardIndex]
      && BINGO_ACTIONS[actionIndex]?.eventType === event.type
    ));
    if (position === -1) continue;
    const actor = event.memberId ?? game.createdBy ?? couple.members[0]?.id;
    const move = {
      id: id('mv'),
      memberId: actor,
      clientMoveId: null,
      data: {
        kind: 'auto_check',
        cardIndex: position,
        actionIndex: game.payload.cardIndexes[position],
        appEventId: event.id,
        eventType: event.type,
      },
      createdAt: nowIso(),
    };
    game.moves.push(move);
    const resolution = canonicalGameResult({ game, couple });
    if (resolution.complete) {
      game.result = resolution.result;
      // Through the shared end path so the persistent games aggregate is
      // written forward for the auto-ended board too.
      recordGameEnd(couple, game);
    }
    changes.push({ game, move, ended: resolution.complete });
  }
  return changes;
}

// ---------------------------------------------------------------------------
// W8C board & duel games
//
// All six follow the v4 authority pattern: state is reduced ONLY from
// accepted moves (reducers skip malformed history defensively), the
// validator rejects everything the reducer would skip, and the result is
// derived server-side in canonicalGameResult. The board index convention is
// always `index = row * size + col`, row 0 = the CREATOR's back row.

// --- Dame (Checkers, 8×8, international simplified) --------------------------
// Creator's men start on rows 0–2 and move toward higher rows; the partner's
// men mirror that. Playable squares are the dark ones ((row+col) % 2 === 1).
// Men step diagonally forward, kings (Dame) step in all four diagonals —
// no flying kings (deliberate simplification). Captures jump 2 diagonal
// squares in ANY direction (international style, men included), captured
// pieces cannot be jumped twice, and a jump sequence in ONE move (`path`)
// must continue while further jumps are available. Capturing is mandatory
// (`capture_required`). A man promotes only when the move ENDS on the back
// row. Draw after `drawPlies` consecutive capture-free half-moves.

const DAME_DIAGONALS = Object.freeze([[1, 1], [1, -1], [-1, 1], [-1, -1]]);

function dameRow(index) {
  return Math.floor(index / 8);
}

function dameCol(index) {
  return index % 8;
}

function damePlayable(index) {
  return Number.isInteger(index) && index >= 0 && index < 64
    && (dameRow(index) + dameCol(index)) % 2 === 1;
}

function dameJumpsFrom(board, index, owner, captured = new Set()) {
  const jumps = [];
  const row = dameRow(index);
  const col = dameCol(index);
  for (const [dr, dc] of DAME_DIAGONALS) {
    const toRow = row + 2 * dr;
    const toCol = col + 2 * dc;
    if (toRow < 0 || toRow > 7 || toCol < 0 || toCol > 7) continue;
    const mid = (row + dr) * 8 + (col + dc);
    const to = toRow * 8 + toCol;
    const victim = board[mid];
    if (!victim || victim.owner === owner || captured.has(mid)) continue;
    if (board[to]) continue;
    jumps.push({ to, mid });
  }
  return jumps;
}

function dameStepsFrom(board, index, king, forward) {
  const steps = [];
  const row = dameRow(index);
  const col = dameCol(index);
  for (const [dr, dc] of DAME_DIAGONALS) {
    if (!king && dr !== forward) continue;
    const toRow = row + dr;
    const toCol = col + dc;
    if (toRow < 0 || toRow > 7 || toCol < 0 || toCol > 7) continue;
    const to = toRow * 8 + toCol;
    if (!board[to]) steps.push(to);
  }
  return steps;
}

function dameSideHasCapture(board, owner) {
  return board.some((piece, index) =>
    piece && piece.owner === owner && dameJumpsFrom(board, index, owner).length > 0);
}

function dameSideHasMove(board, owner, forward) {
  return board.some((piece, index) => {
    if (!piece || piece.owner !== owner) return false;
    return dameStepsFrom(board, index, piece.king, forward).length > 0
      || dameJumpsFrom(board, index, owner).length > 0;
  });
}

/**
 * Checks one move path against the board. Returns `{to, captures}` for a
 * legal move, `{error}` for a rule refusal the validator names precisely
 * (`capture_required` / `capture_incomplete`), or null for anything
 * malformed. Captured pieces stay on the board during the walk (official
 * rule: they are lifted at the end, cannot be jumped twice, and block
 * landing squares); the moving piece leaves its origin immediately, so a
 * circular capture may return to it.
 */
function dameTracePath(board, path, owner, forward) {
  if (!Array.isArray(path) || path.length < 2 || path.length > 13) return null;
  if (!path.every((square) => damePlayable(square))) return null;
  if (new Set(path.slice(1)).size !== path.length - 1) return null;
  const from = path[0];
  const piece = board[from];
  if (!piece || piece.owner !== owner) return null;
  const sim = board.slice();
  sim[from] = null;
  if (path.length === 2) {
    const dr = dameRow(path[1]) - dameRow(from);
    const dc = dameCol(path[1]) - dameCol(from);
    if (Math.abs(dr) === 1 && Math.abs(dc) === 1) {
      if (sim[path[1]] || (!piece.king && dr !== forward)) return null;
      if (dameSideHasCapture(board, owner)) return { error: 'capture_required' };
      return { to: path[1], captures: [] };
    }
  }
  const captured = new Set();
  let at = from;
  for (let step = 1; step < path.length; step += 1) {
    const to = path[step];
    const dr = dameRow(to) - dameRow(at);
    const dc = dameCol(to) - dameCol(at);
    if (Math.abs(dr) !== 2 || Math.abs(dc) !== 2) return null;
    const mid = (dameRow(at) + dr / 2) * 8 + (dameCol(at) + dc / 2);
    const victim = sim[mid];
    if (!victim || victim.owner === owner || captured.has(mid)) return null;
    if (sim[to]) return null;
    captured.add(mid);
    at = to;
  }
  if (dameJumpsFrom(sim, at, owner, captured).length > 0) return { error: 'capture_incomplete' };
  return { to: at, captures: [...captured] };
}

function dameState(game, couple) {
  const members = requirePair(couple);
  const starter = game.createdBy;
  const partner = opponent(members, starter);
  const forwardOf = { [starter]: 1, [partner]: -1 };
  const board = new Array(64).fill(null);
  for (let index = 0; index < 64; index += 1) {
    if (!damePlayable(index)) continue;
    const row = dameRow(index);
    if (row <= 2) board[index] = { owner: starter, king: false };
    else if (row >= 5) board[index] = { owner: partner, king: false };
  }
  let turn = starter;
  let quietPlies = 0;
  for (const move of game.moves) {
    if (move.data?.kind !== 'move' || move.memberId !== turn) continue;
    const traced = dameTracePath(board, move.data.path, turn, forwardOf[turn]);
    if (!traced || traced.error) continue;
    const piece = board[move.data.path[0]];
    board[move.data.path[0]] = null;
    for (const mid of traced.captures) board[mid] = null;
    const backRow = forwardOf[turn] === 1 ? 7 : 0;
    board[traced.to] = { owner: turn, king: piece.king || dameRow(traced.to) === backRow };
    quietPlies = traced.captures.length > 0 ? 0 : quietPlies + 1;
    turn = opponent(members, turn);
  }
  const counts = Object.fromEntries(members.map((id) => [
    id,
    board.filter((piece) => piece?.owner === id).length,
  ]));
  return { members, starter, partner, forwardOf, board, turn, quietPlies, counts };
}

function dameStatus(state, drawPlies) {
  for (const member of state.members) {
    if (state.counts[member] === 0) {
      return { complete: true, winner: opponent(state.members, member), draw: false };
    }
  }
  if (state.quietPlies >= drawPlies) return { complete: true, winner: null, draw: true };
  if (!dameSideHasMove(state.board, state.turn, state.forwardOf[state.turn])) {
    return { complete: true, winner: opponent(state.members, state.turn), draw: false };
  }
  return { complete: false, winner: null, draw: false };
}

function validateDame(game, couple, memberId, data) {
  const state = dameState(game, couple);
  if (data.kind !== 'move') reject('invalid_game_move', 'Dame only accepts move actions');
  if (dameStatus(state, game.payload.drawPlies).complete) {
    reject('game_complete', 'This board is already decided', 409);
  }
  if (memberId !== state.turn) reject('wrong_turn', 'It is the other member’s turn', 409);
  if (!Array.isArray(data.path) || data.path.length < 2 || data.path.length > 13) {
    reject('invalid_game_move', '"path" must list 2–13 board squares');
  }
  const path = data.path.map((square) => integer(square, 'path square', 0, 63));
  if (!path.every((square) => damePlayable(square))) {
    reject('invalid_game_move', 'Dame is played on the dark squares only');
  }
  const traced = dameTracePath(state.board, path, memberId, state.forwardOf[memberId]);
  if (traced?.error === 'capture_required') {
    reject('capture_required', 'A capture is available and must be taken', 409);
  }
  if (traced?.error === 'capture_incomplete') {
    reject('capture_required', 'The jump sequence must continue while captures are available', 409);
  }
  if (!traced) reject('invalid_game_move', 'That is not a legal Dame move');
  const backRow = state.forwardOf[memberId] === 1 ? 7 : 0;
  const promoted = !state.board[path[0]].king && dameRow(traced.to) === backRow;
  return { kind: 'move', path, captures: traced.captures, promoted };
}

function dameResult(game, couple) {
  const state = dameState(game, couple);
  const status = dameStatus(state, game.payload.drawPlies);
  // The very first status of an untouched board is "incomplete" by
  // construction (both sides have moves), so this never ends a fresh game.
  if (!status.complete || game.moves.length === 0) return { complete: false, result: null };
  const scores = Object.fromEntries(state.members.map((id) => [id, status.winner === id ? 1 : 0]));
  return {
    complete: true,
    result: scoresResult(state.members, scores, {
      winner: status.winner,
      draw: status.draw,
      pieces: state.counts,
    }),
  };
}

/** Every legal move for the side to move: full capture paths, else steps. */
function dameLegalPaths(state) {
  const captures = [];
  const steps = [];
  state.board.forEach((piece, index) => {
    if (!piece || piece.owner !== state.turn) return;
    const sim = state.board.slice();
    sim[index] = null;
    const walk = (at, captured, path) => {
      const jumps = dameJumpsFrom(sim, at, state.turn, captured);
      if (jumps.length === 0) {
        if (path.length > 1) captures.push(path);
        return;
      }
      for (const jump of jumps) {
        walk(jump.to, new Set([...captured, jump.mid]), [...path, jump.to]);
      }
    };
    walk(index, new Set(), [index]);
    for (const to of dameStepsFrom(state.board, index, piece.king, state.forwardOf[state.turn])) {
      steps.push([index, to]);
    }
  });
  return captures.length > 0 ? captures : steps;
}

// --- Reversi (Othello, 8×8) ---------------------------------------------------
// The creator plays first and owns the initial discs on 28/35, the partner
// owns 27/36. A placement must flip at least one enemy disc (`no_flip`),
// passing is allowed ONLY without a legal placement (`pass_not_allowed`).
// The game ends when the board is full or both members pass back-to-back;
// the disc counts are the scores.

const REVERSI_DIRECTIONS = Object.freeze([
  [0, 1], [0, -1], [1, 0], [-1, 0], [1, 1], [1, -1], [-1, 1], [-1, -1],
]);

function reversiFlips(board, index, owner) {
  if (!Number.isInteger(index) || index < 0 || index >= 64 || board[index]) return [];
  const row = Math.floor(index / 8);
  const col = index % 8;
  const flips = [];
  for (const [dr, dc] of REVERSI_DIRECTIONS) {
    const line = [];
    let r = row + dr;
    let c = col + dc;
    while (r >= 0 && r < 8 && c >= 0 && c < 8) {
      const at = r * 8 + c;
      if (!board[at]) break;
      if (board[at] === owner) {
        flips.push(...line);
        break;
      }
      line.push(at);
      r += dr;
      c += dc;
    }
  }
  return flips;
}

function reversiLegalMoves(board, owner) {
  const moves = [];
  for (let index = 0; index < 64; index += 1) {
    if (!board[index] && reversiFlips(board, index, owner).length > 0) moves.push(index);
  }
  return moves;
}

function reversiState(game, couple) {
  const members = requirePair(couple);
  const starter = game.createdBy;
  const partner = opponent(members, starter);
  const board = new Array(64).fill(null);
  board[27] = partner;
  board[36] = partner;
  board[28] = starter;
  board[35] = starter;
  let turn = starter;
  let passes = 0;
  let placed = 4;
  for (const move of game.moves) {
    if (move.memberId !== turn) continue;
    if (move.data?.kind === 'pass') {
      if (reversiLegalMoves(board, turn).length > 0) continue;
      passes += 1;
      turn = opponent(members, turn);
    } else if (move.data?.kind === 'place') {
      const flips = reversiFlips(board, move.data.index, turn);
      if (flips.length === 0) continue;
      board[move.data.index] = turn;
      for (const flip of flips) board[flip] = turn;
      placed += 1;
      passes = 0;
      turn = opponent(members, turn);
    }
  }
  const counts = Object.fromEntries(members.map((id) => [
    id,
    board.filter((disc) => disc === id).length,
  ]));
  return {
    members, starter, partner, board, turn, counts,
    complete: placed === 64 || passes >= 2,
  };
}

function validateReversi(game, couple, memberId, data) {
  const state = reversiState(game, couple);
  if (state.complete) reject('game_complete', 'The board is already complete', 409);
  if (memberId !== state.turn) reject('wrong_turn', 'It is the other member’s turn', 409);
  if (data.kind === 'place') {
    const index = integer(data.index, 'index', 0, 63);
    if (state.board[index]) reject('duplicate_move', 'That square is already taken', 409);
    const flips = reversiFlips(state.board, index, memberId);
    if (flips.length === 0) reject('no_flip', 'A placement must flip at least one disc', 409);
    return { kind: 'place', index, flips };
  }
  if (data.kind === 'pass') {
    if (reversiLegalMoves(state.board, memberId).length > 0) {
      reject('pass_not_allowed', 'Passing is only allowed without a legal placement', 409);
    }
    return { kind: 'pass' };
  }
  reject('invalid_game_move', 'Unsupported Reversi action');
}

function reversiResult(game, couple) {
  const state = reversiState(game, couple);
  if (!state.complete) return { complete: false, result: null };
  const [a, b] = state.members;
  const winner = state.counts[a] === state.counts[b] ? null : (state.counts[a] > state.counts[b] ? a : b);
  return {
    complete: true,
    result: scoresResult(state.members, state.counts, { winner, draw: winner === null }),
  };
}

// --- Käsekästchen (Dots & Boxes) ------------------------------------------------
// `size`×`size` boxes on a (size+1)² dot grid. Edge indexes: horizontal
// edges first (row-major, `row * size + col`, row 0..size, col 0..size-1),
// then vertical edges (`size*(size+1) + row * (size+1) + col`, row
// 0..size-1, col 0..size). Closing at least one box scores it and grants
// another turn; the game ends when every edge is drawn.

function kaeseEdgeCount(size) {
  return 2 * size * (size + 1);
}

function kaeseBoxEdges(size, box) {
  const row = Math.floor(box / size);
  const col = box % size;
  const vBase = size * (size + 1);
  return [
    row * size + col,
    (row + 1) * size + col,
    vBase + row * (size + 1) + col,
    vBase + row * (size + 1) + col + 1,
  ];
}

function kaeseClosedBoxes(size, drawn, owners, edge) {
  const closed = [];
  for (let box = 0; box < size * size; box += 1) {
    if (owners[box] !== null) continue;
    const edges = kaeseBoxEdges(size, box);
    if (edges.includes(edge) && edges.every((candidate) => drawn.has(candidate))) closed.push(box);
  }
  return closed;
}

function kaeseState(game, couple) {
  const members = requirePair(couple);
  const starter = game.createdBy;
  const partner = opponent(members, starter);
  const size = game.payload.size;
  const edgeCount = kaeseEdgeCount(size);
  const drawn = new Set();
  const owners = new Array(size * size).fill(null);
  const scores = Object.fromEntries(members.map((id) => [id, 0]));
  let turn = starter;
  for (const move of game.moves) {
    if (move.data?.kind !== 'edge' || move.memberId !== turn) continue;
    const edge = move.data.edge;
    if (!Number.isInteger(edge) || edge < 0 || edge >= edgeCount || drawn.has(edge)) continue;
    drawn.add(edge);
    const closed = kaeseClosedBoxes(size, drawn, owners, edge);
    for (const box of closed) owners[box] = turn;
    scores[turn] += closed.length;
    if (closed.length === 0) turn = opponent(members, turn);
  }
  return {
    members, starter, partner, size, edgeCount, drawn, owners, scores, turn,
    complete: drawn.size === edgeCount,
  };
}

function validateKaesekaestchen(game, couple, memberId, data) {
  const state = kaeseState(game, couple);
  if (data.kind !== 'edge') reject('invalid_game_move', 'Käsekästchen only accepts edge actions');
  if (state.complete) reject('game_complete', 'Every edge is already drawn', 409);
  if (memberId !== state.turn) reject('wrong_turn', 'It is the other member’s turn', 409);
  const edge = integer(data.edge, 'edge', 0, state.edgeCount - 1);
  if (state.drawn.has(edge)) reject('duplicate_move', 'That edge is already drawn', 409);
  const drawn = new Set(state.drawn);
  drawn.add(edge);
  const boxes = kaeseClosedBoxes(state.size, drawn, state.owners, edge);
  return { kind: 'edge', edge, boxes };
}

function kaeseResult(game, couple) {
  const state = kaeseState(game, couple);
  if (!state.complete) return { complete: false, result: null };
  const [a, b] = state.members;
  const winner = state.scores[a] === state.scores[b] ? null : (state.scores[a] > state.scores[b] ? a : b);
  return {
    complete: true,
    result: scoresResult(state.members, state.scores, {
      winner,
      draw: winner === null,
      boxes: state.size * state.size,
    }),
  };
}

// --- Gomoku (five in a row, 15×15) ----------------------------------------------
// Alternating placements, creator first. EXACTLY five contiguous stones win —
// an overline of six or more does not (renju-style, both colors). Full board
// without a winner is a draw.

function gomokuExactFive(board, index, owner) {
  const size = 15;
  const row = Math.floor(index / size);
  const col = index % size;
  for (const [dr, dc] of [[0, 1], [1, 0], [1, 1], [1, -1]]) {
    let count = 1;
    for (const sign of [1, -1]) {
      let r = row + dr * sign;
      let c = col + dc * sign;
      while (r >= 0 && r < size && c >= 0 && c < size && board[r * size + c] === owner) {
        count += 1;
        r += dr * sign;
        c += dc * sign;
      }
    }
    if (count === 5) return true;
  }
  return false;
}

function gomokuState(game, couple) {
  const members = requirePair(couple);
  const starter = game.createdBy;
  const partner = opponent(members, starter);
  const board = new Array(225).fill(null);
  let turn = starter;
  let winner = null;
  let placed = 0;
  for (const move of game.moves) {
    if (move.data?.kind !== 'place' || move.memberId !== turn || winner) continue;
    const index = move.data.index;
    if (!Number.isInteger(index) || index < 0 || index >= 225 || board[index]) continue;
    board[index] = turn;
    placed += 1;
    if (gomokuExactFive(board, index, turn)) winner = turn;
    turn = opponent(members, turn);
  }
  return {
    members, starter, partner, board, turn, winner, placed,
    draw: !winner && placed === 225,
  };
}

function validateGomoku(game, couple, memberId, data) {
  const state = gomokuState(game, couple);
  if (data.kind !== 'place') reject('invalid_game_move', 'Gomoku only accepts place actions');
  if (state.winner || state.draw) reject('game_complete', 'The board is already complete', 409);
  if (memberId !== state.turn) reject('wrong_turn', 'It is the other member’s turn', 409);
  const index = integer(data.index, 'index', 0, 224);
  if (state.board[index]) reject('duplicate_move', 'That intersection is already taken', 409);
  return { kind: 'place', index };
}

function gomokuResult(game, couple) {
  const state = gomokuState(game, couple);
  if (!state.winner && !state.draw) return { complete: false, result: null };
  const scores = Object.fromEntries(state.members.map((id) => [id, state.winner === id ? 1 : 0]));
  return {
    complete: true,
    result: scoresResult(state.members, scores, { winner: state.winner, draw: state.draw }),
  };
}

// --- Mancala (Kalaha, 6 pits + store) --------------------------------------------
// Each member owns pits 0–5 (sowing order) and one store. Sowing runs
// counter-clockwise (own pits ascending, own store, opponent pits ascending)
// and skips the opponent's store. Last stone in the own store grants
// another turn; last stone in an own EMPTY pit captures it plus the
// opposite pit (5 - pit) when that holds stones. When either side's pits
// are all empty after a move, the other side sweeps its remaining stones
// into its store and the stores are the final scores.

function mancalaSow(pits, stores, me, them, pit) {
  let hand = pits[me][pit];
  pits[me][pit] = 0;
  let position = pit;
  while (hand > 0) {
    position = (position + 1) % 13;
    if (position === 6) stores[me] += 1;
    else if (position < 6) pits[me][position] += 1;
    else pits[them][position - 7] += 1;
    hand -= 1;
  }
  const extraTurn = position === 6;
  let captured = 0;
  if (!extraTurn && position < 6 && pits[me][position] === 1 && pits[them][5 - position] > 0) {
    captured = pits[me][position] + pits[them][5 - position];
    stores[me] += captured;
    pits[me][position] = 0;
    pits[them][5 - position] = 0;
  }
  let swept = false;
  if (pits[me].every((count) => count === 0) || pits[them].every((count) => count === 0)) {
    for (const side of [me, them]) {
      stores[side] += pits[side].reduce((sum, count) => sum + count, 0);
      pits[side].fill(0);
    }
    swept = true;
  }
  return { extraTurn, captured, swept };
}

function mancalaState(game, couple) {
  const members = requirePair(couple);
  const starter = game.createdBy;
  const partner = opponent(members, starter);
  const stones = game.payload.stones;
  const pits = { [starter]: new Array(6).fill(stones), [partner]: new Array(6).fill(stones) };
  const stores = { [starter]: 0, [partner]: 0 };
  let turn = starter;
  let complete = false;
  for (const move of game.moves) {
    if (move.data?.kind !== 'sow' || move.memberId !== turn || complete) continue;
    const pit = move.data.pit;
    if (!Number.isInteger(pit) || pit < 0 || pit > 5 || pits[turn][pit] === 0) continue;
    const outcome = mancalaSow(pits, stores, turn, opponent(members, turn), pit);
    complete = outcome.swept;
    if (!outcome.extraTurn) turn = opponent(members, turn);
  }
  return { members, starter, partner, pits, stores, turn, complete };
}

function validateMancala(game, couple, memberId, data) {
  const state = mancalaState(game, couple);
  if (data.kind !== 'sow') reject('invalid_game_move', 'Mancala only accepts sow actions');
  if (state.complete) reject('game_complete', 'The board is already swept', 409);
  if (memberId !== state.turn) reject('wrong_turn', 'It is the other member’s turn', 409);
  const pit = integer(data.pit, 'pit', 0, 5);
  if (state.pits[memberId][pit] === 0) reject('empty_pit', 'That pit has no stones to sow', 409);
  const pits = { ...state.pits, [memberId]: [...state.pits[memberId]] };
  const other = opponent(state.members, memberId);
  pits[other] = [...state.pits[other]];
  const stores = { ...state.stores };
  const outcome = mancalaSow(pits, stores, memberId, other, pit);
  return { kind: 'sow', pit, extraTurn: outcome.extraTurn, captured: outcome.captured };
}

function mancalaResult(game, couple) {
  const state = mancalaState(game, couple);
  if (!state.complete) return { complete: false, result: null };
  const [a, b] = state.members;
  const winner = state.stores[a] === state.stores[b] ? null : (state.stores[a] > state.stores[b] ? a : b);
  return {
    complete: true,
    result: scoresResult(state.members, state.stores, { winner, draw: winner === null }),
  };
}

// --- Memory-Duo (6×6 pair memory, hidden deck) --------------------------------------
// The 36-card deck (18 pairs, face values 0–17) is shuffled from the
// server seed and NEVER serialized: `gamePayloadView` strips the seed from
// every memoryduo client view, so a face is only learned through an
// accepted flip move (the validator injects `face` server-side — the
// server-only-field counterpart of the commit-reveal pattern). Everything
// once flipped stays visible to both members via the move list; fairness
// across a member's own devices comes from the input lease. A turn is two
// flips: a match scores and keeps the turn, a miss passes it.

function memoryduoDeck(game) {
  const pairs = game.payload.pairs;
  return seededShuffle(Array.from({ length: pairs }, (_, face) => [face, face]).flat(), game.payload.seed);
}

function memoryduoState(game, couple) {
  const members = requirePair(couple);
  const starter = game.createdBy;
  const partner = opponent(members, starter);
  const deck = memoryduoDeck(game);
  const matched = new Array(deck.length).fill(null);
  const scores = Object.fromEntries(members.map((id) => [id, 0]));
  let turn = starter;
  let open = null;
  for (const move of game.moves) {
    if (move.data?.kind !== 'flip' || move.memberId !== turn) continue;
    const index = move.data.index;
    if (!Number.isInteger(index) || index < 0 || index >= deck.length) continue;
    if (matched[index] !== null || index === open) continue;
    if (open === null) {
      open = index;
      continue;
    }
    if (deck[open] === deck[index]) {
      matched[open] = turn;
      matched[index] = turn;
      scores[turn] += 1;
    } else {
      turn = opponent(members, turn);
    }
    open = null;
  }
  return {
    members, starter, partner, deck, matched, scores, turn, open,
    complete: matched.every((owner) => owner !== null),
  };
}

function validateMemoryduo(game, couple, memberId, data) {
  const state = memoryduoState(game, couple);
  if (data.kind !== 'flip') reject('invalid_game_move', 'Memory only accepts flip actions');
  if (state.complete) reject('game_complete', 'Every pair is already matched', 409);
  if (memberId !== state.turn) reject('wrong_turn', 'It is the other member’s turn', 409);
  const index = integer(data.index, 'index', 0, state.deck.length - 1);
  if (state.matched[index] !== null) reject('already_matched', 'Matched cards cannot be flipped again', 409);
  if (index === state.open) reject('invalid_game_move', 'That card is already face up in this turn');
  const face = state.deck[index];
  if (state.open === null) return { kind: 'flip', index, face };
  return { kind: 'flip', index, face, first: state.open, match: state.deck[state.open] === face };
}

function memoryduoResult(game, couple) {
  const state = memoryduoState(game, couple);
  if (!state.complete) return { complete: false, result: null };
  const [a, b] = state.members;
  const winner = state.scores[a] === state.scores[b] ? null : (state.scores[a] > state.scores[b] ? a : b);
  return {
    complete: true,
    result: scoresResult(state.members, state.scores, {
      winner,
      draw: winner === null,
      pairs: game.payload.pairs,
    }),
  };
}

/** The single member who has NOT acted yet, or null when both (or neither) still must. */
function soleActor(members, hasActed) {
  const waiting = members.filter((memberId) => !hasActed(memberId));
  return waiting.length === 1 ? waiting[0] : null;
}

/**
 * Server-authoritative "whose move is it" for one game (sync contract c).
 *
 * Returns the member id the session is CURRENTLY waiting on, or `null` when
 * nobody specific is up: non-active games, complete boards, simultaneous
 * phases where BOTH members still must act (quiz answers, RPS commits, …),
 * live realtime phases (a running Pictionary round), and types without
 * turns (`dailyquests` checklist, `bingo` auto-checks, `questions36`).
 *
 * Unlike the old "last mover" heuristic this derivation replays the REAL
 * rules state, so extra moves (Mancala store landing, Käsekästchen box,
 * Memory match) keep the turn with the same member instead of flipping it.
 */
export function gameTurnMemberId(game, couple, now = Date.now()) {
  if (game.state !== 'active') return null;
  try {
    return deriveTurnMemberId(game, couple, now);
  } catch {
    // Pair-required state on a single-member couple etc. — no turn derivable.
    return null;
  }
}

function deriveTurnMemberId(game, couple, now) {
  switch (game.type) {
    case 'quiz': {
      const { members, state, current } = quizState(game, couple);
      if (current >= state.length) return null;
      const round = state[current];
      if (!members.every((id) => round.answers[id] !== undefined)) {
        return soleActor(members, (id) => round.answers[id] !== undefined);
      }
      return members[current % 2]; // both answered → the round subject judges
    }
    case 'thisorthat':
    case 'wouldyourather': {
      const { members, picks, current } = choiceState(game, couple);
      if (current >= picks.length) return null;
      return soleActor(members, (id) => picks[current][id] !== undefined);
    }
    case 'truthordare': {
      const { state, current } = truthState(game, couple);
      if (current >= state.length) return null;
      return membersOf(couple)[(game.payload.seed + current) % 2]; // picks AND claims
    }
    case 'emojiriddle': {
      const { members, state, current } = emojiState(game, couple);
      if (current >= state.length) return null;
      const round = state[current];
      if (!members.every((id) => round.guesses[id] !== undefined)) {
        return soleActor(members, (id) => round.guesses[id] !== undefined);
      }
      return soleActor(members, (id) => round.claims[id] !== undefined);
    }
    case 'connectfour': {
      const state = connectState(game, couple);
      if (state.winner || state.draw) return null;
      return state.moveCount % 2 === 0 ? state.starter : state.partner;
    }
    case 'photomemory': {
      const state = memoryState(game, couple);
      return state.complete ? null : state.turn;
    }
    case 'quizduel': {
      const state = quizDuelState(game, couple);
      if (state.current >= state.deck.length) return null;
      return soleActor(state.members, (id) => state.answers[state.current][id] !== undefined);
    }
    case 'battleship': {
      const state = battleshipState(game, couple);
      if (!state.members.every((id) => state.commits[id])) {
        return soleActor(state.members, (id) => Boolean(state.commits[id]));
      }
      if (Math.max(...Object.values(state.claimedHits)) >= 12) {
        return soleActor(state.members, (id) => Boolean(state.reveals[id])); // reveal phase
      }
      const pending = state.salvos.length - 1;
      if (pending >= 0 && !state.reports[pending]) {
        return opponent(state.members, state.salvos[pending].memberId); // defender reports
      }
      return state.salvos.length % 2 === 0 ? state.starter : state.partner;
    }
    case 'pictionary': {
      const state = pictionaryState(game, couple, now);
      if (state.complete || state.current >= state.rounds.length) return null;
      if (!state.rounds[state.current].startedAt) {
        return state.current % 2 === 0 ? state.starter : state.partner; // artist starts
      }
      return null; // live round — artist draws while the guesser guesses
    }
    case 'kniffel': {
      const state = kniffelState(game, couple);
      if (state.complete) return null;
      return state.turn % 2 === 0 ? state.starter : state.partner;
    }
    case 'movieroulette': {
      const state = movieState(game, couple);
      if (state.complete) return null;
      return soleActor(state.members, (id) => Object.keys(state.swipes[id]).length >= state.size);
    }
    case 'stadtlandfluss': {
      const state = slfState(game, couple);
      if (state.current >= state.rounds.length) return null;
      const round = state.rounds[state.current];
      const phase = state.phase(round);
      if (phase === 'collecting') return soleActor(state.members, (id) => Boolean(round.commits[id]));
      if (phase === 'revealing') return soleActor(state.members, (id) => round.reveals[id] !== undefined);
      return soleActor(state.members, (id) => Boolean(round.ratings[id]));
    }
    case 'twotruths': {
      const state = twoTruthsState(game, couple);
      if (state.current >= state.rounds.length) return null;
      const teller = state.current % 2 === 0 ? state.starter : state.partner;
      const round = state.rounds[state.current];
      if (!round.statements) return teller;
      if (round.guess === null) return opponent(state.members, teller);
      return teller; // reveal closes the round
    }
    case 'wordleduo': {
      const state = wordleDuoState(game, couple);
      if (state.reveal !== null) return null;
      if (!state.commit) return state.starter; // target must be sealed first
      if (state.guesses.length >= game.payload.maxRows) return state.starter; // reveal due
      return state.guesses.length % 2 === 0 ? state.starter : state.partner;
    }
    case 'hangman': {
      const state = hangmanState(game, couple);
      if (state.reveal !== null) return null;
      if (!state.setup) return state.setter;
      if (state.solved || state.lost) return state.setter; // reveal due
      if (state.asked.some((entry) => entry.positions === null)) return state.setter;
      return state.guesser;
    }
    case 'rps': {
      const state = rpsState(game, couple);
      if (state.winner) return null;
      const record = state.rounds[state.current] ?? { commits: {}, reveals: {} };
      if (!state.members.every((id) => record.commits[id] !== undefined)) {
        return soleActor(state.members, (id) => record.commits[id] !== undefined);
      }
      return soleActor(state.members, (id) => record.reveals[id] !== undefined);
    }
    case 'story': {
      const state = storyState(game, couple);
      if (state.complete) return null;
      return state.sentences.length % 2 === 0 ? state.starter : state.partner;
    }
    case 'wordchain': {
      const state = wordchainState(game, couple);
      if (state.finished) return null;
      return state.words.length % 2 === 0 ? state.starter : state.partner;
    }
    case 'dame': {
      const state = dameState(game, couple);
      if (dameStatus(state, game.payload.drawPlies).complete) return null;
      return state.turn;
    }
    case 'reversi': {
      const state = reversiState(game, couple);
      return state.complete ? null : state.turn;
    }
    case 'kaesekaestchen': {
      const state = kaeseState(game, couple);
      return state.complete ? null : state.turn;
    }
    case 'gomoku': {
      const state = gomokuState(game, couple);
      return state.winner || state.draw ? null : state.turn;
    }
    case 'mancala': {
      const state = mancalaState(game, couple);
      return state.complete ? null : state.turn;
    }
    case 'memoryduo': {
      const state = memoryduoState(game, couple);
      return state.complete ? null : state.turn;
    }
    // dailyquests (shared checklist), bingo (auto-checked by app events),
    // questions36 (no server actions) — nobody's "turn".
    default:
      return null;
  }
}

/**
 * Client-visible payload view (used by the router's serializeGame). The
 * memoryduo deck derives from `payload.seed`, so that seed is a server-only
 * field: stripping it here keeps hidden cards unknowable until an accepted
 * flip reveals them. The view stays byte-identical for every couple device
 * (both members are equally blind — see the spoiler matrix in docs/API.md).
 */
export function gamePayloadView(game) {
  if (game.type === 'memoryduo' && game.payload && typeof game.payload === 'object') {
    const { seed, ...visible } = game.payload;
    return visible;
  }
  return game.payload;
}

export function validateGameMove({ game, couple, memberId, data, now = Date.now() }) {
  if (!data || typeof data !== 'object' || Array.isArray(data) || typeof data.kind !== 'string') {
    reject('invalid_game_move', 'Game move data must be an object with a kind');
  }
  switch (game.type) {
    case 'quiz': return validateQuiz(game, couple, memberId, data);
    case 'thisorthat':
    case 'wouldyourather': return validateChoice(game, couple, memberId, data);
    case 'truthordare': return validateTruthOrDare(game, couple, memberId, data);
    case 'emojiriddle': return validateEmoji(game, couple, memberId, data);
    case 'connectfour': return validateConnectFour(game, couple, memberId, data);
    case 'photomemory': return validatePhotoMemory(game, couple, memberId, data);
    case 'quizduel': return validateQuizDuel(game, couple, memberId, data);
    case 'pictionary': return validatePictionary(game, couple, memberId, data, now);
    case 'kniffel': return validateKniffel(game, couple, memberId, data);
    case 'movieroulette': return validateMovie(game, couple, memberId, data);
    case 'battleship': return validateBattleship(game, couple, memberId, data);
    case 'stadtlandfluss': return validateStadtLandFluss(game, couple, memberId, data);
    case 'twotruths': return validateTwoTruths(game, couple, memberId, data);
    case 'dailyquests': return validateDailyQuests(game, couple, memberId, data);
    case 'wordleduo': return validateWordleDuo(game, couple, memberId, data);
    case 'hangman': return validateHangman(game, couple, memberId, data);
    case 'rps': return validateRps(game, couple, memberId, data);
    case 'story': return validateStory(game, couple, memberId, data);
    case 'wordchain': return validateWordchain(game, couple, memberId, data);
    case 'bingo': return validateBingo();
    case 'dame': return validateDame(game, couple, memberId, data);
    case 'reversi': return validateReversi(game, couple, memberId, data);
    case 'kaesekaestchen': return validateKaesekaestchen(game, couple, memberId, data);
    case 'gomoku': return validateGomoku(game, couple, memberId, data);
    case 'mancala': return validateMancala(game, couple, memberId, data);
    case 'memoryduo': return validateMemoryduo(game, couple, memberId, data);
    case 'questions36':
      reject('no_realtime_actions', '36 Questions has no server game actions', 409);
    default:
      reject('invalid_type', `Unsupported game type: ${game.type}`);
  }
}

function scoresResult(members, scores, extra = {}) {
  return {
    scores: Object.fromEntries(members.map((id) => [id, scores[id] ?? 0])),
    ...extra,
  };
}

function kniffelTotal(card) {
  const upper = ['ones', 'twos', 'threes', 'fours', 'fives', 'sixes']
    .reduce((sum, category) => sum + (card[category] ?? 0), 0);
  const lower = KNiffel_CATEGORIES
    .filter((category) => !['ones', 'twos', 'threes', 'fours', 'fives', 'sixes'].includes(category))
    .reduce((sum, category) => sum + (card[category] ?? 0), 0);
  return upper + lower + (upper >= 63 ? 35 : 0);
}

function slfResult(game, couple) {
  const state = slfState(game, couple);
  if (state.current < state.rounds.length) return { complete: false, result: null };
  const letters = seededShuffle([...`ABCDEFGHIJKLMNOPRSTUVWZ`], game.payload.seed).slice(0, game.payload.rounds);
  const scores = Object.fromEntries(state.members.map((id) => [id, 0]));
  const normalized = (value) => value.toLocaleLowerCase('de-DE').replaceAll('ß', 'ss').trim();
  state.rounds.forEach((round, roundIndex) => {
    const answers = Object.fromEntries(
      state.members.map((id) => [id, round.reveals[id].split('\u001f').slice(0, game.payload.categories.length)]),
    );
    game.payload.categories.forEach((_, category) => {
      for (const member of state.members) {
        const other = opponent(state.members, member);
        const mine = answers[member][category] ?? '';
        const theirs = answers[other][category] ?? '';
        const myValid = normalized(mine).startsWith(letters[roundIndex].toLowerCase())
          && round.ratings[other][category] === true;
        const theirValid = normalized(theirs).startsWith(letters[roundIndex].toLowerCase())
          && round.ratings[member][category] === true;
        if (!myValid) continue;
        scores[member] += !theirValid ? 20 : normalized(mine) === normalized(theirs) ? 5 : 10;
      }
    });
  });
  return { complete: true, result: scoresResult(state.members, scores) };
}

function battleshipResult(game, couple) {
  const state = battleshipState(game, couple);
  if (!state.members.every((id) => state.reveals[id])) return { complete: false, result: null };
  const honest = {};
  const actualHits = Object.fromEntries(state.members.map((id) => [id, 0]));
  let winner = null;
  for (const defender of state.members) {
    const ships = state.reveals[defender].ships;
    let previousHits = new Set();
    honest[defender] = true;
    state.salvos.forEach((salvo, index) => {
      if (salvo.memberId === defender) return;
      const expected = expectedReport(salvo.cells, ships, previousHits);
      const report = state.reports[index];
      if (!report
          || JSON.stringify([...report.hits].sort((a, b) => a - b)) !== JSON.stringify([...expected.hits].sort((a, b) => a - b))
          || JSON.stringify([...report.sunk].sort((a, b) => a - b)) !== JSON.stringify(expected.sunk)) {
        honest[defender] = false;
      }
      previousHits = new Set([...previousHits, ...expected.hits]);
      actualHits[salvo.memberId] += expected.hits.length;
      if (!winner && actualHits[salvo.memberId] >= 12) winner = salvo.memberId;
    });
  }
  const integrity = state.members.every((id) => honest[id]);
  const scores = Object.fromEntries(state.members.map((id) => [id, integrity && winner === id ? 1 : 0]));
  return {
    complete: true,
    result: scoresResult(state.members, scores, { winner: integrity ? winner : null, integrity, honest }),
  };
}

export function canonicalGameResult({ game, couple, now = Date.now() }) {
  switch (game.type) {
    case 'quiz': {
      const state = quizState(game, couple);
      if (state.current < state.state.length) return { complete: false, result: null };
      const scores = Object.fromEntries(state.members.map((id) => [id, 0]));
      state.state.forEach((round, index) => {
        if (round.verdict === 'right') scores[state.members[(index + 1) % 2]] += 1;
      });
      return { complete: true, result: scoresResult(state.members, scores) };
    }
    case 'thisorthat':
    case 'wouldyourather': {
      const state = choiceState(game, couple);
      if (state.current < state.picks.length) return { complete: false, result: null };
      const matches = state.picks.filter((round) => round[state.members[0]] === round[state.members[1]]).length;
      return { complete: true, result: { matches, rounds: state.picks.length } };
    }
    case 'truthordare': {
      const state = truthState(game, couple);
      if (state.current < state.state.length) return { complete: false, result: null };
      const scores = Object.fromEntries(state.members.map((id) => [id, 0]));
      state.state.forEach((round, index) => {
        if (round.claim === 'done') scores[state.members[(game.payload.seed + index) % 2]] += 1;
      });
      return { complete: true, result: scoresResult(state.members, scores) };
    }
    case 'emojiriddle': {
      const state = emojiState(game, couple);
      if (state.current < state.state.length) return { complete: false, result: null };
      const scores = Object.fromEntries(
        state.members.map((id) => [id, state.state.filter((round) => round.claims[id] === 'right').length]),
      );
      return { complete: true, result: scoresResult(state.members, scores, { scoring: 'self_claimed' }) };
    }
    case 'connectfour': {
      const state = connectState(game, couple);
      if (!state.winner && !state.draw) return { complete: false, result: null };
      const scores = Object.fromEntries(state.members.map((id) => [id, state.winner === id ? 1 : 0]));
      return { complete: true, result: scoresResult(state.members, scores, { winner: state.winner, draw: state.draw }) };
    }
    case 'photomemory': {
      const state = memoryState(game, couple);
      return { complete: state.complete, result: state.complete ? scoresResult(state.members, state.scores) : null };
    }
    case 'quizduel': {
      const state = quizDuelState(game, couple);
      if (state.current < state.deck.length) return { complete: false, result: null };
      const scores = Object.fromEntries(state.members.map((id) => [id, 0]));
      const correctTaken = new Set();
      state.order.forEach((move) => {
        const { round, option } = move.data;
        if (option !== state.deck[round]) return;
        scores[move.memberId] += correctTaken.has(round) ? 1 : 2;
        correctTaken.add(round);
      });
      return { complete: true, result: scoresResult(state.members, scores) };
    }
    case 'pictionary': {
      const state = pictionaryState(game, couple, now);
      return { complete: state.complete, result: state.complete ? scoresResult(state.members, state.scores) : null };
    }
    case 'kniffel': {
      const state = kniffelState(game, couple);
      if (!state.complete) return { complete: false, result: null };
      const scores = Object.fromEntries(state.members.map((id) => [id, kniffelTotal(state.cards[id])]));
      return { complete: true, result: scoresResult(state.members, scores) };
    }
    case 'movieroulette': {
      const state = movieState(game, couple);
      return {
        complete: state.complete,
        result: state.complete ? { matchIndexes: state.matches, matches: state.matches.length } : null,
      };
    }
    case 'battleship':
      return battleshipResult(game, couple);
    case 'stadtlandfluss':
      return slfResult(game, couple);
    case 'twotruths': {
      const state = twoTruthsState(game, couple);
      if (state.current < state.rounds.length) return { complete: false, result: null };
      const scores = Object.fromEntries(state.members.map((id) => [id, 0]));
      state.rounds.forEach((round, index) => {
        const teller = index % 2 === 0 ? state.starter : state.partner;
        const winner = round.guess === round.reveal ? opponent(state.members, teller) : teller;
        scores[winner] += 1;
      });
      return { complete: true, result: scoresResult(state.members, scores) };
    }
    case 'dailyquests': {
      const state = dailyState(game, couple);
      return {
        complete: state.complete,
        result: state.complete
          ? { done: state.valid.length, total: state.valid.length, dateKey: game.payload.dateKey }
          : null,
      };
    }
    case 'wordleduo':
      return wordleDuoResult(game, couple);
    case 'hangman':
      return hangmanResult(game, couple);
    case 'rps': {
      const state = rpsState(game, couple);
      if (!state.winner) return { complete: false, result: null };
      return {
        complete: true,
        result: scoresResult(state.members, state.scores, { winner: state.winner, target: state.target }),
      };
    }
    case 'story': {
      const state = storyState(game, couple);
      if (!state.complete) return { complete: false, result: null };
      return {
        complete: true,
        result: { sentences: state.total, genre: game.payload.genre, lang: game.payload.lang },
      };
    }
    case 'wordchain': {
      const state = wordchainState(game, couple);
      if (!state.finished) return { complete: false, result: null };
      const longest = state.words.reduce(
        (best, word) => ([...word].length > [...best].length ? word : best),
        state.words[0] ?? '',
      );
      return {
        complete: true,
        result: {
          length: state.words.length,
          longestWord: longest,
          dateKey: game.payload.dateKey,
        },
      };
    }
    case 'bingo': {
      const state = bingoState(game, couple);
      if (!state.completedLine) return { complete: false, result: null };
      const scores = Object.fromEntries(state.members.map((memberId) => [memberId, 1]));
      return {
        complete: true,
        result: scoresResult(state.members, scores, {
          bingo: true,
          line: state.completedLine,
          checked: Object.keys(state.checked).length,
          weekKey: game.payload.weekKey,
        }),
      };
    }
    case 'dame':
      return dameResult(game, couple);
    case 'reversi':
      return reversiResult(game, couple);
    case 'kaesekaestchen':
      return kaeseResult(game, couple);
    case 'gomoku':
      return gomokuResult(game, couple);
    case 'mancala':
      return mancalaResult(game, couple);
    case 'memoryduo':
      return memoryduoResult(game, couple);
    case 'questions36':
      return { complete: false, result: null };
    default:
      return { complete: false, result: null };
  }
}

export function forfeitResult(game, couple, memberId) {
  const members = requirePair(couple);
  const winner = opponent(members, memberId);
  return scoresResult(
    members,
    Object.fromEntries(members.map((id) => [id, id === winner ? 1 : 0])),
    { winner, forfeitBy: memberId },
  );
}

// ---------------------------------------------------------------------------
// Input lease (Welle 6 multi-device fairness)
//
// A member signed in on several devices may submit moves from only ONE of
// them per game session: the first device that moves holds the lease
// implicitly, every other own device is a spectator until an explicit
// takeover (POST /api/games/:id/takeover) or until the holding session dies
// (revoke / expiry / eviction) — a dead lease is inherited silently by the
// next mover. The lease NEVER changes whose turn it is (game rules stay
// authoritative); it only pins WHICH DEVICE of that member may act. State
// lives on the game as `inputLeases[memberId]` and persists with the store.

/** Couple-visible view of one lease — never exposes the full session id. */
export function gameLeaseView(lease) {
  if (!lease) return null;
  return {
    deviceId: lease.deviceId,
    deviceName: lease.deviceName,
    sessionSuffix: String(lease.sessionId ?? '').slice(-8),
    acquiredAt: lease.acquiredAt,
  };
}

/** All leases of a game in view form (keyed by memberId) — for serializeGame. */
export function gameLeasesView(game) {
  const leases = {};
  for (const [memberId, lease] of Object.entries(game.inputLeases ?? {})) {
    const view = gameLeaseView(lease);
    if (view) leases[memberId] = view;
  }
  return leases;
}

/**
 * The lease that BLOCKS `identity` ({memberId, sessionId, …}) from moving,
 * or null when the device may act. `isSessionLive(sessionId)` reports
 * whether the holding session can still authenticate — a dead holder never
 * blocks. Pure check: consulted BEFORE move validation so a spectator
 * device always hears `game_lease_held`, not move-validation noise.
 */
export function blockingGameLease(game, identity, isSessionLive) {
  const current = game.inputLeases?.[identity.memberId];
  if (current && current.sessionId !== identity.sessionId && isSessionLive(current.sessionId)) {
    return current;
  }
  return null;
}

/**
 * Acquires (or keeps) the member's lease for the calling session. Called
 * AFTER a move validated — an invalid move must never grab the lease.
 * Returns `{acquired, lease}`; `acquired` is true only on a fresh grab
 * (first move, or silent inheritance from a dead session).
 */
export function claimGameLease(game, identity, now = nowIso()) {
  if (!game.inputLeases) game.inputLeases = {};
  const current = game.inputLeases[identity.memberId];
  if (current && current.sessionId === identity.sessionId) {
    return { acquired: false, lease: current };
  }
  const lease = {
    sessionId: identity.sessionId,
    deviceId: identity.deviceId,
    deviceName: identity.deviceName,
    acquiredAt: now,
  };
  game.inputLeases[identity.memberId] = lease;
  return { acquired: true, lease };
}

/**
 * Explicit takeover: unconditionally moves the member's lease onto the
 * calling session. Returns `{changed, lease}` — `changed` is false when the
 * caller already held it (idempotent retry, no frame needed).
 */
export function takeoverGameLease(game, identity, now = nowIso()) {
  if (!game.inputLeases) game.inputLeases = {};
  const current = game.inputLeases[identity.memberId];
  if (current && current.sessionId === identity.sessionId) {
    return { changed: false, lease: current };
  }
  const lease = {
    sessionId: identity.sessionId,
    deviceId: identity.deviceId,
    deviceName: identity.deviceName,
    acquiredAt: now,
  };
  game.inputLeases[identity.memberId] = lease;
  return { changed: true, lease };
}

export const gameRulesInternals = Object.freeze({
  bingoState,
  currentWeekKey,
  dailyQuestIndexes,
  seededShuffle,
  memoryTiles,
  dicePips,
  pictionaryDeck,
  quizDuelDeck,
  // W8C board & duel games (test drivers)
  dameState,
  dameLegalPaths,
  reversiState,
  reversiLegalMoves,
  kaeseState,
  kaeseBoxEdges,
  gomokuState,
  mancalaState,
  memoryduoDeck,
  memoryduoState,
});
