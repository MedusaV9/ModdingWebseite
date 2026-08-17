import { test } from 'node:test';
import assert from 'node:assert/strict';
import { client, makeApp, setupCouple, wsOpen } from './helpers.js';

/** Creates a couple and returns the raw create/join responses (incl. recovery keys). */
async function setupCoupleWithKeys(baseUrl) {
  const anon = client(baseUrl);
  const created = await anon.post('/api/couples', { json: { name: 'Mia', avatar: '🦊', color: '#FF5C8A' } });
  assert.equal(created.status, 201);
  const joined = await anon.post('/api/couples/join', {
    json: { code: created.body.couple.code, name: 'Ben', avatar: '🐻', color: '#4A90D9' },
  });
  assert.equal(joined.status, 200);
  return { code: created.body.couple.code, created, joined };
}

test('pairing responses hand out recovery keys (never serialized elsewhere)', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { created, joined } = await setupCoupleWithKeys(baseUrl);
  assert.match(created.body.recoveryKey, /^rec_[0-9a-f]{40}$/);
  assert.match(joined.body.recoveryKey, /^rec_[0-9a-f]{40}$/);
  assert.notEqual(created.body.recoveryKey, joined.body.recoveryKey);
  // The couple payload must never leak recovery material.
  const couple = await client(baseUrl, created.body.token).get('/api/couple');
  assert.equal(couple.status, 200);
  assert.equal(JSON.stringify(couple.body).includes('recovery'), false);
});

test('reinstalled device rejoins its OWN slot of a full couple via recovery key', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { code, created, joined } = await setupCoupleWithKeys(baseUrl);

  // Ben chats once, then "reinstalls the app": the device loses its token.
  const benOld = client(baseUrl, joined.body.token);
  await benOld.post('/api/messages', { json: { type: 'text', text: 'before the reinstall' } });

  // Plain join is still refused (the couple IS full for third parties) …
  const thirdParty = await client(baseUrl).post('/api/couples/join', { json: { code, name: 'Eve' } });
  assert.equal(thirdParty.status, 409);
  assert.equal(thirdParty.body.error, 'couple_full');
  assert.match(thirdParty.body.message, /rejoin/);

  // … but the recovery key re-attaches Ben to his own member slot.
  const miaSocket = await wsOpen(baseUrl, created.body.token, t);
  await miaSocket.waitFor('welcome');
  const rejoined = await client(baseUrl).post('/api/couples/rejoin', {
    json: { code, recoveryKey: joined.body.recoveryKey, deviceName: 'Bens neues iPhone' },
  });
  assert.equal(rejoined.status, 200);
  assert.equal(rejoined.body.rejoined, true);
  assert.equal(rejoined.body.method, 'recoveryKey');
  assert.equal(rejoined.body.memberId, joined.body.memberId, 'must land on the SAME member slot');
  assert.equal(rejoined.body.couple.members.length, 2, 'no third member is created');

  // Mia gets a heads-up frame, and Ben's history is fully intact.
  const frame = await miaSocket.waitFor('partner_rejoined');
  assert.equal(frame.payload.member.id, joined.body.memberId);
  const benNew = client(baseUrl, rejoined.body.token);
  const messages = await benNew.get('/api/messages');
  assert.equal(messages.status, 200);
  assert.equal(messages.body.messages.at(-1).text, 'before the reinstall');
});

test('an expired (but not revoked) old token is accepted as rejoin proof', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const pair = await setupCouple(baseUrl);

  // Simulate v-old sessions: Ben's token expired server-side.
  for (const record of Object.values(app.store.data.tokens)) {
    if (record.memberId === pair.b.memberId) {
      record.expiresAt = new Date(Date.now() - 1000).toISOString();
    }
  }
  assert.equal((await pair.b.api.get('/api/couple')).status, 401, 'expired token no longer authenticates');

  const rejoined = await client(baseUrl).post('/api/couples/rejoin', { json: { token: pair.b.token } });
  assert.equal(rejoined.status, 200);
  assert.equal(rejoined.body.method, 'token');
  assert.equal(rejoined.body.memberId, pair.b.memberId);
  const fresh = client(baseUrl, rejoined.body.token);
  assert.equal((await fresh.get('/api/couple')).status, 200);
});

test('a token beyond the 24-hour grace is destroyed and recovery needs a separate key', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const { code, created } = await setupCoupleWithKeys(baseUrl);
  const record = Object.values(app.store.data.tokens)
    .find((candidate) => candidate.memberId === created.body.memberId);
  record.expiresAt = new Date(Date.now() - 24 * 60 * 60 * 1000 - 1).toISOString();

  const expired = await client(baseUrl).post('/api/couples/rejoin', {
    json: { token: created.body.token },
  });
  assert.equal(expired.status, 403);
  assert.equal(expired.body.error, 'session_expired');
  const recovered = await client(baseUrl).post('/api/couples/rejoin', {
    json: { code, recoveryKey: created.body.recoveryKey },
  });
  assert.equal(recovered.status, 200);
});

test('revoked sessions and unknown tokens/keys are rejected with clear errors', async (t) => {
  const { baseUrl } = await makeApp(t);
  const pair = await setupCouple(baseUrl);

  // Revoked-by-choice sessions must NOT work as rejoin proof.
  const sessions = await pair.b.api.get('/api/sessions');
  const revoke = await pair.b.api.post(`/api/sessions/${sessions.body.sessions[0].id}/revoke`);
  assert.equal(revoke.status, 200);
  const revoked = await client(baseUrl).post('/api/couples/rejoin', { json: { token: pair.b.token } });
  assert.equal(revoked.status, 403);
  assert.equal(revoked.body.error, 'session_revoked');

  const unknownToken = await client(baseUrl).post('/api/couples/rejoin', { json: { token: 'tok_never_issued_0000000000' } });
  assert.equal(unknownToken.status, 403);
  assert.equal(unknownToken.body.error, 'unknown_session');

  const badKey = await client(baseUrl).post('/api/couples/rejoin', {
    json: { code: pair.code, recoveryKey: 'rec_ffffffffffffffffffffffffffffffffffffffff' },
  });
  assert.equal(badKey.status, 403);
  assert.equal(badKey.body.error, 'bad_recovery_key');

  const noProof = await client(baseUrl).post('/api/couples/rejoin', { json: { code: pair.code } });
  assert.equal(noProof.status, 400);
  assert.equal(noProof.body.error, 'missing_proof');
});

test('EVAL repro: a revoked token whose tombstone was pruned answers unknown_session — never a session', async (t) => {
  // Server half of the >24h revoke chain: the tombstone dies after the
  // retention window, so the old bearer degrades from `session_revoked` to
  // `unknown_session`. BOTH verdicts are refusals — the client treats both
  // as terminal (no silent recovery-key fallback re-admits the device).
  const { cleanupSessions } = await import('../src/security.js');
  const { baseUrl, app } = await makeApp(t);
  const pair = await setupCouple(baseUrl);

  // Ben revokes his own session from a signed-in device — the generic
  // lifecycle frame still reaches his devices (revoke fanout unaffected).
  const bSock = await wsOpen(baseUrl, pair.b.token, t);
  await bSock.waitFor('welcome');
  const sessions = await pair.b.api.get('/api/sessions');
  const own = sessions.body.sessions.find((s) => s.current);
  assert.equal((await pair.b.api.post(`/api/sessions/${own.id}/revoke`)).status, 200);
  const frame = await bSock.waitFor('sessions_changed');
  assert.equal(frame.payload.reason, 'revoked');

  // Fresh tombstone: the rejoin proof is refused with the explicit verdict.
  const early = await client(baseUrl).post('/api/couples/rejoin', { json: { token: pair.b.token } });
  assert.equal(early.status, 403);
  assert.equal(early.body.error, 'session_revoked');

  // >24 h later the cleanup sweep prunes the tombstone …
  for (const record of Object.values(app.store.data.tokens)) {
    if (record.revokedAt) {
      record.revokedAt = new Date(Date.now() - 25 * 60 * 60 * 1000).toISOString();
    }
  }
  cleanupSessions(app.store);

  // … and the old token is now simply UNKNOWN — still a refusal, still no
  // fresh session for the kicked device.
  const late = await client(baseUrl).post('/api/couples/rejoin', { json: { token: pair.b.token } });
  assert.equal(late.status, 403);
  assert.equal(late.body.error, 'unknown_session');
});

test('recovery keys can be issued for legacy members and rotate atomically', async (t) => {
  const { baseUrl } = await makeApp(t);
  const pair = await setupCouple(baseUrl);

  // setupCouple ignores the pairing response keys — treat Ben as legacy by wiping his.
  const status = await pair.b.api.get('/api/recovery-key');
  assert.equal(status.status, 200);
  assert.equal(status.body.configured, true); // issued at join time

  const first = await pair.b.api.post('/api/recovery-key');
  assert.equal(first.status, 200);
  assert.equal(first.body.rotated, true);
  const second = await pair.b.api.post('/api/recovery-key');
  assert.equal(second.body.rotated, true);
  assert.notEqual(first.body.recoveryKey, second.body.recoveryKey);

  // Only the newest key works.
  const oldKey = await client(baseUrl).post('/api/couples/rejoin', {
    json: { code: pair.code, recoveryKey: first.body.recoveryKey },
  });
  assert.equal(oldKey.status, 403);
  const newKey = await client(baseUrl).post('/api/couples/rejoin', {
    json: { code: pair.code, recoveryKey: second.body.recoveryKey },
  });
  assert.equal(newKey.status, 200);
  assert.equal(newKey.body.memberId, pair.b.memberId);
});

test('partner-approved replace flow hands the lost slot to a new device', async (t) => {
  const { baseUrl } = await makeApp(t);
  const pair = await setupCouple(baseUrl);
  await pair.b.api.post('/api/messages', { json: { type: 'text', text: 'history stays' } });

  // Ben lost EVERYTHING (no token, no recovery key). Mia approves a replace.
  const replace = await pair.a.api.post('/api/couples/replace-partner');
  assert.equal(replace.status, 201);
  assert.match(replace.body.replaceCode, /^[A-Z2-9]{8}$/);
  assert.equal(replace.body.target.id, pair.b.memberId);

  const miaSocket = await wsOpen(baseUrl, pair.a.token, t);
  await miaSocket.waitFor('welcome');

  const rejoined = await client(baseUrl).post('/api/couples/rejoin', {
    json: {
      code: pair.code,
      replaceCode: replace.body.replaceCode,
      name: 'Ben (neues Handy)',
      deviceName: 'iPhone 17',
    },
  });
  assert.equal(rejoined.status, 200);
  assert.equal(rejoined.body.method, 'replaceCode');
  assert.equal(rejoined.body.memberId, pair.b.memberId, 'slot (and history) is preserved');
  const frame = await miaSocket.waitFor('partner_replaced');
  assert.equal(frame.payload.member.name, 'Ben (neues Handy)');

  // Old device sessions are dead, new session sees the shared history.
  assert.equal((await pair.b.api.get('/api/couple')).status, 401);
  const benNew = client(baseUrl, rejoined.body.token);
  const messages = await benNew.get('/api/messages');
  assert.equal(messages.body.messages.at(-1).text, 'history stays');

  // The code is single-use.
  const reuse = await client(baseUrl).post('/api/couples/rejoin', {
    json: { code: pair.code, replaceCode: replace.body.replaceCode },
  });
  assert.equal(reuse.status, 403);
  assert.equal(reuse.body.error, 'bad_replace_code');
});

test('simultaneous partner replacement requests use CAS semantics', async (t) => {
  const { baseUrl } = await makeApp(t);
  const pair = await setupCouple(baseUrl);
  const attempts = await Promise.all([
    pair.a.api.post('/api/couples/replace-partner'),
    pair.b.api.post('/api/couples/replace-partner'),
  ]);
  assert.deepEqual(attempts.map((attempt) => attempt.status).sort(), [201, 409]);
  assert.equal(attempts.find((attempt) => attempt.status === 409).body.error, 'replace_already_pending');
});

test('replace codes expire, can be cancelled, and require an existing partner', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const pair = await setupCouple(baseUrl);

  // Expiry.
  const expired = await pair.a.api.post('/api/couples/replace-partner');
  app.store.data.couples[pair.coupleId].partnerReplace.expiresAt = new Date(Date.now() - 1).toISOString();
  const late = await client(baseUrl).post('/api/couples/rejoin', {
    json: { code: pair.code, replaceCode: expired.body.replaceCode },
  });
  assert.equal(late.status, 403);

  // Cancel.
  const second = await pair.a.api.post('/api/couples/replace-partner');
  const cancel = await pair.a.api.del('/api/couples/replace-partner');
  assert.equal(cancel.status, 200);
  assert.equal(cancel.body.cancelled, true);
  const cancelled = await client(baseUrl).post('/api/couples/rejoin', {
    json: { code: pair.code, replaceCode: second.body.replaceCode },
  });
  assert.equal(cancelled.status, 403);

  // Solo couples have no partner slot to replace.
  const solo = await client(baseUrl).post('/api/couples', { json: { name: 'Solo' } });
  const noPartner = await client(baseUrl, solo.body.token).post('/api/couples/replace-partner');
  assert.equal(noPartner.status, 409);
  assert.equal(noPartner.body.error, 'no_partner');
});

test('replacing a slot kills the old recovery key with it', async (t) => {
  const { baseUrl } = await makeApp(t);
  const { code, created, joined } = await setupCoupleWithKeys(baseUrl);
  const mia = client(baseUrl, created.body.token);

  const replace = await mia.post('/api/couples/replace-partner');
  const taken = await client(baseUrl).post('/api/couples/rejoin', {
    json: { code, replaceCode: replace.body.replaceCode },
  });
  assert.equal(taken.status, 200);

  // Ben's ORIGINAL recovery key must no longer re-attach (his slot was
  // deliberately handed over) — the new device issues its own key instead.
  const oldOwners = await client(baseUrl).post('/api/couples/rejoin', {
    json: { code, recoveryKey: joined.body.recoveryKey },
  });
  assert.equal(oldOwners.status, 403);
  const newKey = await client(baseUrl, taken.body.token).post('/api/recovery-key');
  assert.equal(newKey.status, 200);
  assert.equal(newKey.body.rotated, false);
});

test('a member with replaceCodeDigest can rejoin directly using their custom replace code', async (t) => {
  const { baseUrl, app } = await makeApp(t);
  const pair = await setupCouple(baseUrl);
  const crypto = await import('node:crypto');

  // Set individual replace codes directly on both members.
  const couple = app.store.data.couples[pair.coupleId];
  couple.members[0].replaceCodeDigest = crypto.createHash('sha256').update('VNCRNT11').digest('hex');
  couple.members[1].replaceCodeDigest = crypto.createHash('sha256').update('VNCRNT22').digest('hex');

  const wrongProofType = await client(baseUrl).post('/api/couples/rejoin', {
    json: { code: pair.code, recoveryKey: 'VNCRNT11' },
  });
  assert.equal(wrongProofType.status, 403);
  assert.equal(wrongProofType.body.error, 'bad_recovery_key');

  // Sophie rejoins with VNCRNT11.
  const sophieRejoin = await client(baseUrl).post('/api/couples/rejoin', {
    json: { code: pair.code, replaceCode: 'VNCRNT11' },
  });
  assert.equal(sophieRejoin.status, 200);
  assert.equal(sophieRejoin.body.memberId, couple.members[0].id);
  assert.equal((await client(baseUrl).post('/api/couples/rejoin', {
    json: { code: pair.code, replaceCode: 'VNCRNT11' },
  })).status, 403, 'replace code is consumed exactly once');

  // Vincent rejoins with VNCRNT22.
  const vincentRejoin = await client(baseUrl).post('/api/couples/rejoin', {
    json: { code: pair.code, replaceCode: 'VNCRNT22' },
  });
  assert.equal(vincentRejoin.status, 200);
  assert.equal(vincentRejoin.body.memberId, couple.members[1].id);
});
