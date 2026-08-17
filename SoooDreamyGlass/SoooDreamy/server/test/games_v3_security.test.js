import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple, wsOpen } from './helpers.js';
import { gameRulesInternals } from '../src/game-rules.js';

// v3.0.1 security regressions (EVAL-3.0 P0): game app events are derived
// SERVER-SIDE from verified moves and are idempotent — a forged or replayed
// event must never mint XP.

const todayKey = () => new Date().toISOString().slice(0, 10);
const eventXp = async (who) => (await who.api.get('/api/level')).body.breakdown.appEvents;

// ---------------------------------------------------------------------------
// movie_match: only both-liked cards, once per card

test('a forged match annotation without both likes emits NO movie_match and NO XP', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  await aSock.waitFor('welcome');

  const game = (await a.api.post('/api/games', {
    json: { type: 'movieroulette', payload: { size: 2 } },
  })).body.game;
  await b.api.post(`/api/games/${game.id}/join`, { json: {} });
  const xpBefore = await eventXp(a);

  // B invents a match for a card A never liked — stored as a move, but the
  // relay derives events from the persisted likes, not from client claims.
  await b.api.post(`/api/games/${game.id}/move`, {
    json: {
      data: { kind: 'swipe', index: 0, like: true, match: { cardIndex: 0, title: 'Cheat Film' } },
    },
  });
  await aSock.assertNone('app_event');
  assert.equal(await eventXp(a), xpBefore);

  // A match object alone (not even a like move) emits nothing either.
  const annotationOnly = await b.api.post(`/api/games/${game.id}/move`, {
    json: { data: { match: { cardIndex: 6, title: 'Noch ein Cheat' } } },
  });
  assert.equal(annotationOnly.status, 400);
  await aSock.assertNone('app_event');
  assert.equal(await eventXp(a), xpBefore);
});

test('a real both-liked card emits exactly ONE movie_match; replays never re-emit', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const aSock = await wsOpen(baseUrl, a.token, t);
  await aSock.waitFor('welcome');

  const game = (await a.api.post('/api/games', {
    json: { type: 'movieroulette', payload: { size: 2 } },
  })).body.game;
  await b.api.post(`/api/games/${game.id}/join`, { json: {} });
  const move = (who, data) => who.api.post(`/api/games/${game.id}/move`, { json: { data } });
  const xpBefore = await eventXp(a);

  await move(a, { kind: 'swipe', index: 0, like: true });
  await move(b, { kind: 'swipe', index: 0, like: true, match: { cardIndex: 0, title: 'La La Land' } });
  const frame = await aSock.waitFor('app_event', (m) => m.payload.event.type === 'movie_match');
  assert.deepEqual(frame.payload.event.data, { gameId: game.id, cardIndex: 0, title: 'La La Land' });

  // movie_match XP is explicit (15) — counted exactly once.
  assert.equal(await eventXp(a), xpBefore + 15);

  // Replaying the completing like (even with the annotation) is deduped.
  assert.equal((await move(b, {
    kind: 'swipe', index: 0, like: true, match: { cardIndex: 0, title: 'La La Land' },
  })).status, 409);
  assert.equal((await move(a, { kind: 'swipe', index: 0, like: true })).status, 409);
  await aSock.assertNone('app_event');
  assert.equal(await eventXp(a), xpBefore + 15);

  // A different card matched by both is a NEW event.
  await move(a, { kind: 'swipe', index: 1, like: true });
  await move(b, { kind: 'swipe', index: 1, like: true });
  const second = await aSock.waitFor('app_event', (m) => m.payload.event.type === 'movie_match');
  assert.equal(second.payload.event.data.cardIndex, 1);
  assert.equal(second.payload.event.data.title, null); // no annotation → no cosmetic title
  assert.equal(await eventXp(a), xpBefore + 30);
});

// ---------------------------------------------------------------------------
// quest_done: idempotent per (dateKey, questIndex) — across sessions too

test('re-checking the same daily quest never emits a second quest_done or XP', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b, coupleId } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const day = todayKey();
  const game = (await a.api.post('/api/games', { json: { type: 'dailyquests', payload: { dateKey: day } } }))
    .body.game;
  await a.api.post(`/api/games/${game.id}/join`, { json: {} });
  const move = (who, data) => who.api.post(`/api/games/${game.id}/move`, { json: { data } });
  const xpBefore = await eventXp(b);
  const indexes = gameRulesInternals.dailyQuestIndexes(coupleId, day);

  await move(a, { kind: 'quest_done', questIndex: indexes[0] });
  const frame = await bSock.waitFor('app_event', (m) => m.payload.event.type === 'quest_done');
  assert.deepEqual(frame.payload.event.data, { gameId: game.id, dateKey: day, questIndex: indexes[0] });
  assert.equal(await eventXp(b), xpBefore + 10); // explicit quest_done XP

  // The same box again — by either member — is stored as a move but never re-emits.
  assert.equal((await move(a, { kind: 'quest_done', questIndex: indexes[0] })).status, 409);
  assert.equal((await move(b, { kind: 'quest_done', questIndex: indexes[0] })).status, 409);
  await bSock.assertNone('app_event');
  assert.equal(await eventXp(b), xpBefore + 10);

  // A NEW session of the SAME day cannot farm the same quest either.
  assert.equal((await a.api.post(`/api/games/${game.id}/end`, {
    json: { forfeit: true },
  })).status, 200);
  const game2 = (await b.api.post('/api/games', { json: { type: 'dailyquests', payload: { dateKey: day } } }))
    .body.game;
  await b.api.post(`/api/games/${game2.id}/join`, { json: {} });
  await b.api.post(`/api/games/${game2.id}/move`, {
    json: { data: { kind: 'quest_done', questIndex: indexes[0] } },
  });
  await bSock.assertNone('app_event');
  assert.equal(await eventXp(b), xpBefore + 10);

  // A different quest of the day is a legitimate new event.
  await b.api.post(`/api/games/${game2.id}/move`, {
    json: { data: { kind: 'quest_done', questIndex: indexes[1] } },
  });
  const other = await bSock.waitFor('app_event', (m) => m.payload.event.type === 'quest_done');
  assert.equal(other.payload.event.data.questIndex, indexes[1]);
  assert.equal(await eventXp(b), xpBefore + 20);
});

test('dailyquests dateKeys are validated: invented day strings cannot dodge the dedupe', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a } = await setupCouple(baseUrl);

  // Non-date and far-away dateKeys are rejected at create.
  const junk = await a.api.post('/api/games', { json: { type: 'dailyquests', payload: { dateKey: 'x1' } } });
  assert.equal(junk.status, 400);
  const farAway = await a.api.post('/api/games', {
    json: { type: 'dailyquests', payload: { dateKey: '2020-01-01' } },
  });
  assert.equal(farAway.status, 400);
  assert.equal(farAway.body.error, 'bad_datekey');

  // Omitting the dateKey defaults to the server date.
  const defaulted = (await a.api.post('/api/games', { json: { type: 'dailyquests' } })).body.game;
  assert.equal(defaulted.payload.dateKey, todayKey());
});

// ---------------------------------------------------------------------------
// Film-Roulette → Wochenplan: the exact server chain the iOS 1-tap CTA uses

test('movie match → app-event feed → 1-tap week-plan slot (client flow end-to-end)', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  // 1. Both swipe right on card 1 → the relay derives movie_match.
  const game = (await a.api.post('/api/games', {
    json: { type: 'movieroulette', payload: { size: 1 } },
  })).body.game;
  await b.api.post(`/api/games/${game.id}/join`, { json: {} });
  await a.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'swipe', index: 0, like: true } },
  });
  await b.api.post(`/api/games/${game.id}/move`, {
    json: { data: { kind: 'swipe', index: 0, like: true, match: { cardIndex: 0, title: 'Notting Hill' } } },
  });

  // 2. The week-plan banner reads the typed app-event feed.
  const feed = (await a.api.get('/api/app-events?type=movie_match&limit=10')).body.events;
  assert.equal(feed.length, 1);
  assert.equal(feed[0].data.title, 'Notting Hill');

  // 3. The 1-tap CTA creates a REAL movie slot for a nearby day…
  const dateKey = new Date(Date.now() + 2 * 86_400_000).toISOString().slice(0, 10);
  const slot = (
    await a.api.post('/api/weekplan/slots', {
      json: { title: 'Notting Hill', emoji: '🍿', kind: 'movie', dateKey },
    })
  ).body.slot;
  assert.equal(slot.kind, 'movie');

  // …which lands on the board and in the milestone log (weekplan_slot_created).
  const plan = (await b.api.get('/api/weekplan')).body;
  assert.ok(plan.days.some((d) => d.slots.some((s) => s.id === slot.id)));
  const slotEvents = (await b.api.get('/api/app-events?type=weekplan_slot_created')).body.events;
  assert.ok(slotEvents.some((ev) => ev.data.slotId === slot.id));
});

test('quest_done with an out-of-range questIndex emits nothing', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const bSock = await wsOpen(baseUrl, b.token, t);
  await bSock.waitFor('welcome');

  const game = (await a.api.post('/api/games', { json: { type: 'dailyquests' } })).body.game;
  await a.api.post(`/api/games/${game.id}/join`, { json: {} });
  const move = (data) => a.api.post(`/api/games/${game.id}/move`, { json: { data } });
  const xpBefore = await eventXp(a);

  await move({ kind: 'quest_done', questIndex: -1 });
  await move({ kind: 'quest_done', questIndex: 1000 });
  await move({ kind: 'quest_done', questIndex: 1.5 });
  await move({ kind: 'quest_done' });
  await bSock.assertNone('app_event');
  assert.equal(await eventXp(a), xpBefore);
});
