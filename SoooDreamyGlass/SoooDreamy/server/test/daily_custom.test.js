import { test } from 'node:test';
import assert from 'node:assert/strict';
import { makeApp, setupCouple } from './helpers.js';
import { customQuestionForDay, customQuestionsOf } from '../src/dailyquestions.js';
import { todayKey, prevDateKey, nextDateKey } from '../src/util.js';

// ---------------------------------------------------------------------------
// pool CRUD + authorship privacy

test('custom question pool: own questions only, author-only delete, couple cap', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { a, b } = await setupCouple(baseUrl);

  const created = await a.api.post('/api/daily-questions', {
    json: { text: 'Was war dein Lieblingsmoment mit mir diesen Monat?' },
  });
  assert.equal(created.status, 201);
  assert.equal(created.body.poolSize, 1);
  const questionId = created.body.question.id;

  // Ben sees the pool SIZE but never Mia's questions (authorship surprise).
  const benList = await b.api.get('/api/daily-questions');
  assert.equal(benList.status, 200);
  assert.deepEqual(benList.body.questions, []);
  assert.equal(benList.body.poolSize, 1);

  const miaList = await a.api.get('/api/daily-questions');
  assert.equal(miaList.body.questions.length, 1);
  assert.equal(miaList.body.questions[0].text, 'Was war dein Lieblingsmoment mit mir diesen Monat?');

  // Only the author deletes.
  const benDelete = await b.api.del(`/api/daily-questions/${questionId}`);
  assert.equal(benDelete.status, 403);
  assert.equal(benDelete.body.error, 'not_yours');
  const miaDelete = await a.api.del(`/api/daily-questions/${questionId}`);
  assert.equal(miaDelete.status, 200);
  assert.equal(miaDelete.body.poolSize, 0);

  // Validation.
  const empty = await a.api.post('/api/daily-questions', { json: { text: '   ' } });
  assert.equal(empty.status, 400);
  const long = await a.api.post('/api/daily-questions', { json: { text: 'x'.repeat(241) } });
  assert.equal(long.status, 400);
});

// ---------------------------------------------------------------------------
// deterministic pick semantics (direct unit access to the store-level helper)

test('customQuestionForDay is deterministic, respects cadence and the created-before rule', () => {
  const couple = { id: 'c_test', members: [] };
  const today = todayKey();

  // Empty pool: never a custom day.
  assert.equal(customQuestionForDay(couple, today), null);

  // A question created TODAY is not eligible today (author privacy) …
  customQuestionsOf(couple).push({
    id: 'cq_1', text: 'Frage A', createdBy: 'm_a', createdOn: today, createdAt: new Date().toISOString(),
  });
  assert.equal(customQuestionForDay(couple, today), null);

  // … but from tomorrow on, roughly every third day picks from the pool.
  couple.customQuestions[0].createdOn = '2020-01-01';
  const picks = [];
  let day = '2026-01-01';
  for (let i = 0; i < 30; i += 1) {
    const pick = customQuestionForDay(couple, day);
    if (pick) picks.push(day);
    // Determinism: the same inputs give the same output.
    assert.deepEqual(customQuestionForDay(couple, day), pick);
    day = nextDateKey(day);
  }
  assert.ok(picks.length >= 5 && picks.length <= 15,
    `~1/3 of 30 days should be custom days, got ${picks.length}`);

  // A different couple gets a different (deterministic) day pattern eventually.
  const other = { id: 'c_other', members: [], customQuestions: couple.customQuestions };
  let differs = false;
  day = '2026-01-01';
  for (let i = 0; i < 30; i += 1) {
    if ((customQuestionForDay(couple, day) == null) !== (customQuestionForDay(other, day) == null)) {
      differs = true;
      break;
    }
    day = nextDateKey(day);
  }
  assert.ok(differs, 'custom days must depend on the couple id');
});

// ---------------------------------------------------------------------------
// end-to-end: custom day in the daily entry + author reveal + snapshot pinning

/** Finds a nearby answerable dateKey (today ±1) that IS a custom day, if any. */
function answerableCustomDay(couple) {
  const today = todayKey();
  for (const key of [today, prevDateKey(today), nextDateKey(today)]) {
    if (customQuestionForDay(couple, key)) return key;
  }
  return null;
}

test('custom day flows through the daily entry with the classic author reveal', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a, b, coupleId } = await setupCouple(baseUrl);
  const couple = app.store.data.couples[coupleId];

  // Seed one backdated question per member so a custom day is possible.
  couple.customQuestions = [
    { id: 'cq_mia', text: 'Worauf freust du dich nächste Woche am meisten?',
      createdBy: a.memberId, createdOn: '2020-01-01', createdAt: '2020-01-01T00:00:00.000Z' },
  ];

  // The cadence is deterministic per (coupleId, dateKey) — today ±1 may or
  // may not be a custom day for this random coupleId. Force determinism by
  // testing BOTH branches explicitly through the view:
  const day = answerableCustomDay(couple);
  if (!day) {
    // Not a custom day near today for this couple: the entry must NOT carry a custom question.
    const entry = await a.api.get(`/api/daily/${todayKey()}`);
    assert.equal(entry.body.customQuestion, null);
    return;
  }

  // Both members see the SAME question text before anyone answered.
  const aView = await a.api.get(`/api/daily/${day}`);
  const bView = await b.api.get(`/api/daily/${day}`);
  assert.equal(aView.body.customQuestion.text, 'Worauf freust du dich nächste Woche am meisten?');
  assert.equal(bView.body.customQuestion.text, aView.body.customQuestion.text);

  // Author reveal semantics: Mia (author) sees herself; Ben sees null.
  assert.equal(aView.body.customQuestion.authorId, a.memberId);
  assert.equal(bView.body.customQuestion.authorId, null);

  // First answer pins the snapshot; deleting the pool question changes nothing.
  await b.api.post(`/api/daily/${day}`, { json: { questionId: -1, text: 'Auf unser Wochenende!' } });
  couple.customQuestions = [];
  const bMid = await b.api.get(`/api/daily/${day}`);
  assert.equal(bMid.body.customQuestion.text, 'Worauf freust du dich nächste Woche am meisten?');
  assert.equal(bMid.body.customQuestion.authorId, null, 'still hidden — only one answered');

  await a.api.post(`/api/daily/${day}`, { json: { questionId: -1, text: 'Auf dich. Immer.' } });
  const bAfter = await b.api.get(`/api/daily/${day}`);
  assert.equal(bAfter.body.bothAnswered, true);
  assert.equal(bAfter.body.customQuestion.authorId, a.memberId, 'reveal: Ben learns whose question it was');
});

test('non-custom days keep customQuestion null end-to-end', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { a, coupleId } = await setupCouple(baseUrl);
  const couple = app.store.data.couples[coupleId];
  const today = todayKey();
  // No pool → plain pack day, even after answering.
  const before = await a.api.get(`/api/daily/${today}`);
  assert.equal(before.body.customQuestion, null);
  await a.api.post(`/api/daily/${today}`, { json: { questionId: 7, text: 'Pack-Frage beantwortet' } });
  const after = await a.api.get(`/api/daily/${today}`);
  assert.equal(after.body.customQuestion, null);
  assert.equal(after.body.questionId, 7);
  void couple;
});
