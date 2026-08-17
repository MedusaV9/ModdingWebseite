import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple } from './helpers.js';

function door(unlockAt, text, kind = 'prompt') {
  return { unlockAt, payload: { kind, text } };
}

test('season calendar keeps future doors server-locked and reveals one door at a time', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const past = new Date(Date.now() - 60_000).toISOString();
  const future = new Date(Date.now() + 86_400_000).toISOString();

  const created = await a.api.post('/api/season-calendars', {
    json: {
      title: 'Birthday week',
      emoji: '🎂',
      kind: 'birthday',
      doors: [
        door(future, 'A future surprise', 'letter'),
        door(past, 'Tell me your favorite memory'),
      ],
    },
  });
  assert.equal(created.status, 201);
  const calendarId = created.body.calendar.id;
  assert.equal(created.body.calendar.doors[0].payload.text, 'Tell me your favorite memory');

  const recipientList = await b.api.get('/api/season-calendars');
  assert.equal(recipientList.status, 200);
  assert.equal(recipientList.body.calendars[0].doors[0].payload, null);
  assert.equal(recipientList.body.calendars[0].doors[0].unlocked, true);
  assert.equal(recipientList.body.calendars[0].doors[1].payload, null);
  assert.equal(JSON.stringify(app.store.data).includes('A future surprise'), true);

  const authorCannotOpen = await a.api.post(`/api/season-calendars/${calendarId}/open`, {
    json: { doorId: created.body.calendar.doors[0].id },
  });
  assert.equal(authorCannotOpen.status, 403);
  assert.equal(authorCannotOpen.body.error, 'not_for_you');

  const opened = await b.api.post(`/api/season-calendars/${calendarId}/open`, {
    json: { doorId: created.body.calendar.doors[0].id },
  });
  assert.equal(opened.status, 200);
  assert.equal(opened.body.calendar.doors[0].payload.text, 'Tell me your favorite memory');
  assert.ok(opened.body.calendar.doors[0].openedAt);
  assert.equal(opened.body.calendar.doors[1].payload, null);

  const early = await b.api.post(`/api/season-calendars/${calendarId}/open`, {
    json: { doorId: created.body.calendar.doors[1].id },
  });
  assert.equal(early.status, 409);
  assert.equal(early.body.error, 'door_still_locked');

  const openedEvents = Object.values(app.store.data.couples)[0].appEvents
    .filter((event) => event.type === 'season_calendar_door_opened');
  assert.equal(openedEvents.length, 1);
});

test('season calendar validates authoring and preserves opened shared archives', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);
  const past = new Date(Date.now() - 60_000).toISOString();

  const invalid = await a.api.post('/api/season-calendars', {
    json: { title: 'Empty', kind: 'advent', doors: [] },
  });
  assert.equal(invalid.status, 400);
  assert.equal(invalid.body.error, 'bad_doors');

  const created = await a.api.post('/api/season-calendars', {
    json: {
      title: 'Anniversary',
      kind: 'anniversary',
      doors: [door(past, 'One small adventure', 'quest')],
    },
  });
  const calendarId = created.body.calendar.id;
  const doorId = created.body.calendar.doors[0].id;

  const partnerEdit = await b.api.patch(`/api/season-calendars/${calendarId}`, {
    json: { title: 'Nope' },
  });
  assert.equal(partnerEdit.status, 403);
  assert.equal((await a.api.patch(`/api/season-calendars/${calendarId}`, {
    json: { title: 'Our anniversary week' },
  })).body.calendar.title, 'Our anniversary week');

  assert.equal((await b.api.del(`/api/season-calendars/${calendarId}`)).status, 403);
  assert.equal((await b.api.post(`/api/season-calendars/${calendarId}/open`, {
    json: { doorId },
  })).status, 200);
  const protectedArchive = await a.api.del(`/api/season-calendars/${calendarId}`);
  assert.equal(protectedArchive.status, 409);
  assert.equal(protectedArchive.body.error, 'already_opened');

  const disposable = await a.api.post('/api/season-calendars', {
    json: {
      title: 'Countdown',
      kind: 'countdown',
      doors: [door(new Date(Date.now() + 60_000).toISOString(), 'Soon')],
    },
  });
  assert.equal((await a.api.del(`/api/season-calendars/${disposable.body.calendar.id}`)).status, 200);
});
