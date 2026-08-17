import {
  canonicalGameResult,
  finalizeGamePayload,
  GAME_TYPES,
  isPlayedGame,
  prepareGamePayload,
  seededGamesAggregate,
  validateGameMove,
} from './game-rules.js';
import { isValidDateKey, newSeed, nextDateKey, nowIso, prevDateKey, todayKey } from './util.js';

export const CURRENT_GAME_RULES_VERSION = 5;
const GAME_TYPE_SET = new Set(GAME_TYPES);

function invalidate(game, reason) {
  game.state = 'ended';
  game.rulesVersion = CURRENT_GAME_RULES_VERSION;
  game.resultAuthority = 'server-migration';
  game.result = {
    invalidated: true,
    reason: 'rules_migration',
    detail: reason,
    migratedAt: nowIso(),
  };
}

/**
 * Aggregate forward-count for the two migration end paths (Fix-Runde 3,
 * Befund 7): they flip `state = 'ended'` directly — `recordGameEnd` is
 * deliberately NOT reused here because a migration is not a play (its
 * legacy `counters.gamesPlayed` bump would lie). On a store whose
 * aggregate is already seeded, a later RULES-version bump would otherwise
 * end played sessions PAST the aggregate — a silent undercount. Before
 * the first seed (aggregate still absent) the couple-level seeding at the
 * end of the loop counts these ends instead, so nothing double-counts.
 */
function countMigratedEnd(couple, game) {
  const aggregate = couple.gamesAggregate;
  if (!aggregate || !isPlayedGame(game)) return;
  aggregate.total += 1;
  aggregate.perKind[game.type] = (aggregate.perKind[game.type] ?? 0) + 1;
}

function normalizedPayload(game, couple) {
  const payload = prepareGamePayload(game.type, game.payload, couple);
  if (game.type === 'dailyquests') {
    const today = todayKey();
    const dateKey = payload.dateKey;
    if (!isValidDateKey(dateKey)
        || ![prevDateKey(today), today, nextDateKey(today)].includes(dateKey)) {
      throw new Error('legacy daily-quest date is outside the accepted server window');
    }
  }
  const hasMoves = Array.isArray(game.moves) && game.moves.length > 0;
  if (hasMoves && (
    game.payload?.seedServer !== true
    || !Number.isInteger(game.payload?.seed)
    || game.payload.seed < 1
    || game.payload.seed > 2_147_483_646
  )) {
    throw new Error('moved game has no trustworthy server seed');
  }
  payload.seed = hasMoves ? game.payload.seed : newSeed();
  payload.seedServer = true;
  return finalizeGamePayload(game.type, payload);
}

/**
 * Replays every move in an open pre-v4 game through the current validator.
 *
 * Reducers intentionally tolerate old/malformed history for read-only replay,
 * but continuation cannot: silently skipping an unknown move would derive a
 * false turn/phase and authorize the next action. Open sessions that cannot be
 * replayed exactly are closed with an explicit migration result. Ended legacy
 * sessions remain fetchable but are labelled `legacy-client`, never upgraded
 * to server authority retroactively.
 */
export function migrateGameStore({ store, log = () => {} }) {
  const report = { upgraded: 0, invalidated: 0, legacyEnded: 0, aggregatesSeeded: 0 };
  let changed = false;
  for (const couple of Object.values(store.data.couples)) {
    if (!Array.isArray(couple.games)) continue;
    for (const game of couple.games) {
      if (game.state === 'ended') {
        if (game.rulesVersion == null) {
          game.rulesVersion = 3;
          game.resultAuthority = game.resultAuthority ?? 'legacy-client';
          report.legacyEnded += 1;
          changed = true;
        }
        continue;
      }
      if (game.rulesVersion === CURRENT_GAME_RULES_VERSION) continue;
      try {
        if (!GAME_TYPE_SET.has(game.type)) throw new Error('unknown game type');
        if (!couple.members.some((member) => member.id === game.createdBy)) {
          throw new Error('creator is not a current couple member');
        }
        if (!Array.isArray(game.moves)) throw new Error('moves is not an array');
        const replay = {
          ...game,
          payload: normalizedPayload(game, couple),
          moves: [],
          result: null,
        };
        for (const historic of game.moves) {
          if (!historic || !couple.members.some((member) => member.id === historic.memberId)) {
            throw new Error('move actor is not a current couple member');
          }
          const timestamp = Date.parse(historic.createdAt);
          const data = validateGameMove({
            game: replay,
            couple,
            memberId: historic.memberId,
            data: historic.data,
            now: Number.isFinite(timestamp) ? timestamp : Date.now(),
          });
          replay.moves.push({ ...historic, data });
        }
        const resolution = canonicalGameResult({ game: replay, couple });
        game.payload = replay.payload;
        game.moves = replay.moves;
        game.rulesVersion = CURRENT_GAME_RULES_VERSION;
        game.resultAuthority = 'server';
        game.result = resolution.complete ? resolution.result : null;
        if (resolution.complete) {
          game.state = 'ended';
          countMigratedEnd(couple, game);
        }
        report.upgraded += 1;
        changed = true;
      } catch (error) {
        invalidate(game, error?.message ?? error?.code ?? 'unrecognized history');
        countMigratedEnd(couple, game);
        report.invalidated += 1;
        changed = true;
        log('games: invalidated legacy open session', game.id, game.type,
          error?.code ?? error?.message ?? 'unknown');
      }
    }
    // First run after the aggregate deploy (re-eval 2, Befund 9): seed the
    // persistent played-game counts ONCE from the stored history (after the
    // per-game upgrades above, so migration-ended sessions count too).
    // From here on `recordGameEnd` writes the aggregate forward — eviction
    // via LIMITS.games can no longer shrink the whole-life numbers.
    if (!couple.gamesAggregate) {
      couple.gamesAggregate = seededGamesAggregate(couple);
      report.aggregatesSeeded += 1;
      changed = true;
    }
  }
  if (changed) store.markDirty();
  return report;
}
