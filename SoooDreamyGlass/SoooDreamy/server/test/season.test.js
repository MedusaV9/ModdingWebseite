import { test } from 'node:test';
import assert from 'node:assert/strict';
import { aggregateSeason } from '../src/season.js';
import { makeApp, setupCouple } from './helpers.js';

test('season aggregate handles 250 sessions plus bilingual Wordle without truncation', () => {
  const couple = {
    members: [{ id: 'mia' }, { id: 'ben' }],
    games: Array.from({ length: 250 }, (_, index) => ({
      id: `g-${index}`,
      type: index % 2 ? 'connectfour' : 'questions36',
      state: 'ended',
      createdAt: `2026-${index < 125 ? '06' : '07'}-${String((index % 28) + 1).padStart(2, '0')}T12:00:00.000Z`,
      result: index % 2
        ? { scores: { mia: index % 5, ben: (index + 1) % 5 } }
        : { completedBy: 'mia' },
    })),
    wordle: {
      '2026-07-20': {
        de: {
          mia: { memberId: 'mia', rows: 2, win: true },
          ben: { memberId: 'ben', rows: 4, win: true },
        },
        en: {
          mia: { memberId: 'mia', rows: 6, win: false },
          ben: { memberId: 'ben', rows: 3, win: true },
        },
      },
    },
  };

  const all = aggregateSeason(couple);
  assert.equal(all.total, 252);
  assert.deepEqual(all.months, ['2026-07', '2026-06']);
  assert.equal(all.matches.filter((match) => match.source === 'wordle').length, 2);

  const july = aggregateSeason(couple, '2026-07');
  assert.equal(july.total, 127);
  assert.ok(july.matches.every((match) => match.monthKey === '2026-07'));
  assert.deepEqual(
    july.matches.find((match) => match.id === 'wordle-2026-07-20-de').scores,
    { mia: 5, ben: 3 },
  );
});

test('season endpoint is authenticated, validates month, and returns canonical shape', async (t) => {
  const { baseUrl } = await makeApp(t);
  const anonymous = await fetch(`${baseUrl}/api/games/season`);
  assert.equal(anonymous.status, 401);

  const { a } = await setupCouple(baseUrl);
  assert.equal((await a.api.get('/api/games/season?month=2026-13')).status, 400);
  const response = await a.api.get('/api/games/season');
  assert.equal(response.status, 200);
  assert.deepEqual(response.body, { month: null, matches: [], months: [], total: 0 });
});
