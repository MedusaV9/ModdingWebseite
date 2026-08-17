import { sleep } from './util.mjs';

/**
 * Scenario library — every scenario plays a REAL app flow over HTTP+WS the
 * way the iOS client does, asserts the documented contract inline (status
 * codes, duplicate:true idempotency, WS fanout) and leaves a trail for the
 * post-run invariant pass (world.scheduledPosts, couple.gameExpectations,
 * couple.listState, couple.canvasState, the global frame log).
 *
 * All randomness is seeded (lib/rng.mjs) — a run is reproducible per seed.
 */

const TOUCH_TYPES = ['heartbeat', 'kiss', 'hug', 'missyou', 'tickle', 'thinking', 'stolz', 'haltedurch'];
const PULSE_KINDS = ['thinking', 'goodnight', 'heartbeat', 'hug'];

function expectStatus(world, res, allowed, label, context = {}) {
  if (!allowed.includes(res.status)) {
    world.violations.add('unexpected_status', 'high',
      `${label}: expected ${allowed.join('/')}, got ${res.status}`,
      { ...context, body: res.body });
    return false;
  }
  return true;
}

/** All currently-connected devices of the OTHER member. */
function partnerDevices(couple, senderMi) {
  return couple.members[1 - senderMi].devices.filter((d) => d.sock.connected);
}

/** All currently-connected devices of the couple. */
function coupleDevices(couple) {
  return couple.members.flatMap((m) => m.devices.filter((d) => d.sock.connected));
}

/** Waits for a frame on every listed device; missing frame = violation. */
async function expectFrame(world, devices, type, pred, label, timeoutMs = 8_000) {
  await Promise.all(devices.map(async (device) => {
    try {
      await device.sock.waitFor(type, pred, timeoutMs);
    } catch {
      if (device.sock.connected && !world.expectDisconnects) {
        world.violations.add('missing_frame', 'high',
          `${label}: no "${type}" frame arrived on ${device.name}`, {});
      }
    }
  }));
}

function nextSeq(couple) {
  couple.seq += 1;
  return couple.seq;
}

// ---------------------------------------------------------------------------
// chat: message + idempotent retry + reaction (+ retry) + read receipt

export async function chatScenario(world, couple, rng) {
  world.bumpScenario('chat');
  const mi = rng.int(0, 1);
  const sender = rng.pick(couple.members[mi].devices.filter((d) => d.sock.connected))
    ?? couple.members[mi].devices[0];
  const seq = nextSeq(couple);
  const clientMessageId = `arena-${couple.key}-msg-${seq}`;
  const text = `${couple.marker} msg ${seq} von m${mi}`;

  const sent = await sender.http.post('/api/messages', {
    json: { type: 'text', text, clientMessageId },
  });
  if (!expectStatus(world, sent, [201], 'chat send', { couple: couple.ci })) return;
  const message = sent.body.message;
  couple.lastMessageId = message.id;

  // Idempotency (g): a lost-response retry with the same clientMessageId must
  // return the SAME message flagged duplicate:true — never a second message.
  if (rng.chance(0.5)) {
    const retry = await sender.http.post('/api/messages', {
      json: { type: 'text', text, clientMessageId },
    });
    if (expectStatus(world, retry, [200], 'chat retry', { couple: couple.ci })) {
      if (retry.body.duplicate !== true || retry.body.message?.id !== message.id) {
        world.violations.add('idempotency_broken', 'critical',
          'message retry did not return duplicate:true with the original id',
          { couple: couple.ci, original: message.id, retry: retry.body });
      }
    }
  }

  await expectFrame(world, partnerDevices(couple, mi), 'message',
    (f) => f.payload?.message?.id === message.id, `chat ${message.id}`);

  // Partner reacts (with a stable op id) and marks read.
  const reactor = rng.pick(partnerDevices(couple, mi));
  if (reactor) {
    const opId = `arena-${couple.key}-react-${seq}`;
    const reacted = await reactor.http.post(`/api/messages/${message.id}/reactions`, {
      json: { emoji: '❤️', clientOperationId: opId },
    });
    expectStatus(world, reacted, [200], 'reaction', { couple: couple.ci });
    if (rng.chance(0.5)) {
      const retry = await reactor.http.post(`/api/messages/${message.id}/reactions`, {
        json: { emoji: '❤️', clientOperationId: opId },
      });
      if (expectStatus(world, retry, [200], 'reaction retry', { couple: couple.ci })
        && retry.body.duplicate !== true) {
        world.violations.add('idempotency_broken', 'critical',
          'reaction retry with the same clientOperationId toggled again (no duplicate:true)',
          { couple: couple.ci, message: message.id });
      }
    }
    await expectFrame(world, coupleDevices(couple), 'message_updated',
      (f) => f.payload?.message?.id === message.id, `reaction ${message.id}`);
    const read = await reactor.http.post('/api/messages/read', { json: {} });
    expectStatus(world, read, [200], 'read receipt', { couple: couple.ci });
  }
}

// ---------------------------------------------------------------------------
// touch + echo: window/uniqueness contract (invariant b)

export async function touchEchoScenario(world, couple, rng) {
  world.bumpScenario('touchEcho');
  const mi = rng.int(0, 1);
  const sender = rng.pick(couple.members[mi].devices.filter((d) => d.sock.connected))
    ?? couple.members[mi].devices[0];
  const seq = nextSeq(couple);
  const type = rng.pick(TOUCH_TYPES);
  const opId = `arena-${couple.key}-touch-${seq}`;

  const sent = await sender.http.post('/api/touches', { json: { type, clientOperationId: opId } });
  if (!expectStatus(world, sent, [201], 'touch send', { couple: couple.ci })) return;
  const touch = sent.body.touch;

  if (rng.chance(0.4)) {
    const retry = await sender.http.post('/api/touches', { json: { type, clientOperationId: opId } });
    if (expectStatus(world, retry, [200], 'touch retry', { couple: couple.ci })
      && (retry.body.duplicate !== true || retry.body.touch?.id !== touch.id)) {
      world.violations.add('idempotency_broken', 'critical',
        'touch retry did not return duplicate:true with the original touch',
        { couple: couple.ci, touch: touch.id, retry: retry.body });
    }
  }

  const receivers = partnerDevices(couple, mi);
  await expectFrame(world, receivers, 'touch',
    (f) => f.payload?.touch?.id === touch.id, `touch ${touch.id}`);

  // Echo back once — a second echo (any device) must be refused (echo_taken),
  // echoing your OWN touch must be a 400.
  const echoDevice = rng.pick(receivers);
  if (!echoDevice) return;
  const echoed = await echoDevice.http.post(`/api/touches/${touch.id}/echo`, {
    json: { clientOperationId: `arena-${couple.key}-echo-${seq}` },
  });
  if (!expectStatus(world, echoed, [201], 'echo', { couple: couple.ci, touch: touch.id })) return;
  const echoTouch = echoed.body.touch;
  if (echoTouch.echo !== true || echoTouch.echoOf !== touch.id) {
    world.violations.add('echo_shape', 'high',
      'echo touch is missing echo:true/echoOf', { couple: couple.ci, echo: echoTouch });
  }
  const secondDevice = rng.pick(coupleDevices(couple).filter((d) => d.mi === echoDevice.mi)) ?? echoDevice;
  const second = await secondDevice.http.post(`/api/touches/${touch.id}/echo`, { json: {} });
  if (second.status !== 409 || second.body?.error !== 'echo_taken') {
    world.violations.add('echo_uniqueness', 'critical',
      `second echo of ${touch.id} was not refused with 409 echo_taken`,
      { couple: couple.ci, status: second.status, body: second.body });
  }
  // Echoing an ECHO is refused too (one bounce per touch, R1-C).
  const bounce = await sender.http.post(`/api/touches/${echoTouch.id}/echo`, { json: {} });
  if (bounce.status !== 409 || bounce.body?.error !== 'echo_taken') {
    world.violations.add('echo_uniqueness', 'critical',
      `echoing the echo ${echoTouch.id} was not refused with 409 echo_taken`,
      { couple: couple.ci, status: bounce.status, body: bounce.body });
  }
  // Echoing your own touch → 400.
  const own = await sender.http.post(`/api/touches/${touch.id}/echo`, { json: {} });
  if (own.status !== 400) {
    world.violations.add('echo_own_touch', 'high',
      `echoing the own touch ${touch.id} was not a 400`,
      { couple: couple.ci, status: own.status, body: own.body });
  }
  await expectFrame(world, partnerDevices(couple, echoDevice.mi), 'touch',
    (f) => f.payload?.touch?.id === echoTouch.id, `echo ${echoTouch.id}`);
}

// ---------------------------------------------------------------------------
// pulse: 30 s cooldown + exactly-once retries + partner-only fanout

export async function pulseScenario(world, couple, rng) {
  world.bumpScenario('pulse');
  const mi = rng.int(0, 1);
  const member = couple.members[mi];
  const sender = rng.pick(member.devices.filter((d) => d.sock.connected)) ?? member.devices[0];
  const seq = nextSeq(couple);
  const kind = rng.pick(PULSE_KINDS);
  const opId = `arena-${couple.key}-pulse-${seq}`;
  const lastAt = couple.lastPulseAt instanceof Map
    ? couple.lastPulseAt.get(mi) ?? 0
    : 0;
  if (!(couple.lastPulseAt instanceof Map)) couple.lastPulseAt = new Map();
  const sinceLast = Date.now() - lastAt;

  const sent = await sender.http.post('/api/pulses', { json: { kind, clientOperationId: opId } });
  if (sinceLast < 31_500 && lastAt > 0) {
    // Inside the cooldown a NEW pulse must be a 429 too_soon with retry-after.
    // 29–31.5 s is a measurement gray zone (we time the SEND, the server
    // times the stored createdAt) — both outcomes are legitimate there.
    if (sent.status === 201) {
      if (sinceLast < 29_000) {
        world.violations.add('pulse_cooldown', 'high',
          `pulse accepted ${Math.round(sinceLast / 1000)}s after the previous one (cooldown is 30s)`,
          { couple: couple.ci });
      }
      couple.lastPulseAt.set(mi, Date.now());
    } else if (sent.status !== 429 || sent.body?.error !== 'too_soon' || !sent.headers['retry-after']) {
      world.violations.add('pulse_cooldown', 'medium',
        'cooldown refusal is not a 429 too_soon with retry-after',
        { couple: couple.ci, status: sent.status, body: sent.body });
    }
    return;
  }
  if (!expectStatus(world, sent, [201], 'pulse send', { couple: couple.ci })) return;
  couple.lastPulseAt.set(mi, Date.now());
  const pulse = sent.body.pulse;

  // Retry of the ACCEPTED pulse: duplicate:true, not a misleading 429.
  const retry = await sender.http.post('/api/pulses', { json: { kind, clientOperationId: opId } });
  if (expectStatus(world, retry, [200], 'pulse retry', { couple: couple.ci })
    && (retry.body.duplicate !== true || retry.body.pulse?.id !== pulse.id)) {
    world.violations.add('idempotency_broken', 'critical',
      'pulse retry did not return duplicate:true with the original pulse',
      { couple: couple.ci, pulse: pulse.id, retry: retry.body });
  }
  // A NEW pulse right behind it must hit the cooldown.
  const tooSoon = await sender.http.post('/api/pulses', {
    json: { kind, clientOperationId: `${opId}-second` },
  });
  if (tooSoon.status !== 429 || tooSoon.body?.error !== 'too_soon') {
    world.violations.add('pulse_cooldown', 'high',
      'second NEW pulse within the 30s cooldown was not refused with 429 too_soon',
      { couple: couple.ci, status: tooSoon.status, body: tooSoon.body });
  }

  await expectFrame(world, partnerDevices(couple, mi), 'pulse',
    (f) => f.payload?.pulse?.id === pulse.id, `pulse ${pulse.id}`);

  // Receiver marks pulses felt → the sender gets the pulse_felt receipt.
  if (rng.chance(0.6)) {
    const receiver = rng.pick(partnerDevices(couple, mi));
    if (receiver) {
      const seen = await receiver.http.post('/api/pulses/seen');
      expectStatus(world, seen, [200], 'pulses seen', { couple: couple.ci });
      if (seen.body?.count > 0) {
        await expectFrame(world, member.devices.filter((d) => d.sock.connected), 'pulse_felt',
          (f) => f.payload?.memberId === receiver.memberId, `pulse_felt ${pulse.id}`);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Zeitpost: schedule (+ retry), optional cancel, partner-invisibility probes.
// Delivery exactly-once is verified in the post-run pass (checks.mjs).

export async function zeitpostScenario(world, couple, rng, { deliverInMs = null } = {}) {
  world.bumpScenario('zeitpost');
  const mi = rng.int(0, 1);
  const member = couple.members[mi];
  const sender = rng.pick(member.devices.filter((d) => d.sock.connected)) ?? member.devices[0];
  const openNow = world.scheduledPosts.filter((p) => p.ci === couple.ci && p.senderMi === mi
    && !p.canceled && p.deliverAtMs > Date.now() - 15_000).length;
  if (openNow >= 4) return; // stay under the 5-open cap

  const seq = nextSeq(couple);
  const kind = rng.weighted([
    { weight: 4, value: 'touch' },
    { weight: 4, value: 'note' },
    { weight: 2, value: 'pulse' },
  ]);
  const deliverAtMs = Date.now() + (deliverInMs ?? rng.int(4_000, 9_000));
  const body = { kind, deliverAt: new Date(deliverAtMs).toISOString(), clientOperationId: `arena-${couple.key}-zp-${seq}` };
  if (kind === 'touch') body.type = rng.pick(TOUCH_TYPES);
  else if (kind === 'pulse') body.pulseKind = rng.pick(PULSE_KINDS);
  else body.note = `${couple.marker} zeitpost ${seq}`;

  const scheduled = await sender.http.post('/api/post/schedule', { json: body });
  if (!expectStatus(world, scheduled, [201], 'zeitpost schedule', { couple: couple.ci, body })) return;
  const post = scheduled.body.post;
  const record = {
    ci: couple.ci, postId: post.id, kind, senderMi: mi, senderId: sender.memberId,
    deliverAtMs: Date.parse(post.deliverAt), canceled: false,
    touchType: body.type ?? null, pulseKind: body.pulseKind ?? null, note: body.note ?? null,
  };
  world.scheduledPosts.push(record);

  // Retry → duplicate:true with the original post (invariant g).
  const retry = await sender.http.post('/api/post/schedule', { json: body });
  if (expectStatus(world, retry, [200], 'zeitpost retry', { couple: couple.ci })
    && (retry.body.duplicate !== true || retry.body.post?.id !== post.id)) {
    world.violations.add('idempotency_broken', 'critical',
      'zeitpost schedule retry did not return duplicate:true with the original post',
      { couple: couple.ci, post: post.id, retry: retry.body });
  }

  // Surprise contract: the partner must never see the pending post.
  const probe = rng.pick(partnerDevices(couple, mi));
  if (probe) {
    const list = await probe.http.get('/api/post/scheduled');
    if (list.status === 200 && list.body.posts?.some((p) => p.id === post.id)) {
      world.violations.add('zeitpost_surprise_leak', 'critical',
        `partner GET /api/post/scheduled lists the pending post ${post.id}`,
        { couple: couple.ci });
    }
    // A partner's cancel probe must be an indistinguishable 404.
    const foreignCancel = await probe.http.del(`/api/post/scheduled/${post.id}`);
    if (foreignCancel.status !== 404) {
      world.violations.add('zeitpost_surprise_leak', 'critical',
        `partner DELETE of the pending post ${post.id} answered ${foreignCancel.status} instead of 404`,
        { couple: couple.ci, body: foreignCancel.body });
    }
  }

  // Sometimes cancel the post before it is due — canceled posts must never
  // produce an artifact (post-run check).
  if (deliverInMs === null && rng.chance(0.25) && record.deliverAtMs - Date.now() > 2_500) {
    const canceled = await sender.http.del(`/api/post/scheduled/${post.id}`);
    if (expectStatus(world, canceled, [200], 'zeitpost cancel', { couple: couple.ci })) {
      record.canceled = true;
    }
  }
  return record;
}

// ---------------------------------------------------------------------------
// daily: the pin race (two devices, divergent question ids) + reveal check

export async function dailyPinRaceScenario(world, couple, rng) {
  world.bumpScenario('dailyPinRace');
  const dateKey = new Date().toISOString().slice(0, 10);
  const a = couple.members[0].devices[0];
  const b = couple.members[1].devices[0];
  const qA = rng.int(1, 400);
  let qB = rng.int(1, 400);
  if (qB === qA) qB += 1;
  const seq = nextSeq(couple);

  // Both members answer AT THE SAME TIME with divergent question ids —
  // exactly one id may win the pin, the loser must get the authoritative id.
  const [resA, resB] = await Promise.all([
    a.http.post(`/api/daily/${dateKey}`, {
      json: {
        questionId: qA, text: `${couple.marker} daily A ${seq}`,
        questionText: { de: `Frage ${qA} de`, en: `Frage ${qA} en` },
        clientOperationId: `arena-${couple.key}-daily-a-${seq}`,
      },
    }),
    b.http.post(`/api/daily/${dateKey}`, {
      json: {
        questionId: qB, text: `${couple.marker} daily B ${seq}`,
        questionText: { de: `Frage ${qB} de`, en: `Frage ${qB} en` },
        clientOperationId: `arena-${couple.key}-daily-b-${seq}`,
      },
    }),
  ]);
  const results = [{ res: resA, q: qA, dev: a, text: `${couple.marker} daily A ${seq}` },
    { res: resB, q: qB, dev: b, text: `${couple.marker} daily B ${seq}` }];
  const winners = results.filter((r) => r.res.status === 200);
  const losers = results.filter((r) => r.res.status === 409);
  if (winners.length !== 1 || losers.length !== 1) {
    world.violations.add('daily_pin_race', 'critical',
      `pin race did not resolve to exactly one winner (statuses ${resA.status}/${resB.status})`,
      { couple: couple.ci, a: resA.body, b: resB.body });
    return;
  }
  const pinned = winners[0].res.body.questionId;
  const loser = losers[0];
  if (loser.res.body?.error !== 'daily_question_mismatch'
    || loser.res.body?.details?.questionId !== pinned) {
    world.violations.add('daily_pin_race', 'critical',
      'race loser did not get 409 daily_question_mismatch with the authoritative questionId',
      { couple: couple.ci, loser: loser.res.body, pinned });
    return;
  }
  // Loser re-answers with the pinned id (what the app does after the 409).
  const retry = await loser.dev.http.post(`/api/daily/${dateKey}`, {
    json: { questionId: pinned, text: loser.text },
  });
  expectStatus(world, retry, [200], 'daily loser retry', { couple: couple.ci });

  // Both member views must agree: ONE pinned questionId, both answers visible.
  const [viewA, viewB] = await Promise.all([
    a.http.get(`/api/daily/${dateKey}`),
    b.http.get(`/api/daily/${dateKey}`),
  ]);
  if (viewA.status !== 200 || viewB.status !== 200
    || viewA.body.questionId !== pinned || viewB.body.questionId !== pinned) {
    world.violations.add('daily_pin_divergence', 'critical',
      'the two member views disagree about the pinned questionId',
      { couple: couple.ci, a: viewA.body, b: viewB.body, pinned });
  }
  if (viewA.body.bothAnswered !== true || viewB.body.bothAnswered !== true
    || !viewA.body.partnerAnswer || !viewB.body.partnerAnswer) {
    world.violations.add('daily_reveal', 'high',
      'after both answered the reveal is incomplete',
      { couple: couple.ci, a: viewA.body, b: viewB.body });
  }
  // Post-reveal edits must be refused.
  const sealed = await a.http.post(`/api/daily/${dateKey}`, {
    json: { questionId: pinned, text: 'edit after reveal' },
  });
  if (sealed.status !== 409 || sealed.body?.error !== 'daily_revealed') {
    world.violations.add('daily_reveal', 'high',
      'editing a revealed answer was not refused with 409 daily_revealed',
      { couple: couple.ci, status: sealed.status, body: sealed.body });
  }
  couple.dailyPinned = { dateKey, questionId: pinned };
}

// ---------------------------------------------------------------------------
// game: gomoku with input lease, takeover, wrong-turn, duplicate clientMoveId

export async function gameScenario(world, couple, rng) {
  world.bumpScenario('game');
  const creatorMi = rng.int(0, 1);
  const creator = couple.members[creatorMi];
  const partner = couple.members[1 - creatorMi];
  const cDev0 = creator.devices[0];
  const pDev0 = partner.devices[0];
  const seq = nextSeq(couple);

  const created = await cDev0.http.post('/api/games', { json: { type: 'gomoku' } });
  if (!expectStatus(world, created, [201], 'game create', { couple: couple.ci })) return;
  const gameId = created.body.game.id;
  await expectFrame(world, partnerDevices(couple, creatorMi), 'game_created',
    (f) => f.payload?.game?.id === gameId, `game_created ${gameId}`);

  const joined = await pDev0.http.post(`/api/games/${gameId}/join`);
  if (!expectStatus(world, joined, [200], 'game join', { couple: couple.ci })) return;

  // Scripted win for the creator: row 0 cells 0..4 vs partner row 1 cells 15..18.
  // Expected stored sequence (memberId, index):
  const script = [];
  for (let i = 0; i < 4; i += 1) {
    script.push({ member: creator, index: i });
    script.push({ member: partner, index: 15 + i });
  }
  script.push({ member: creator, index: 4 }); // winning stone
  const expectedMoves = [];
  let moveNo = 0;

  for (const step of script) {
    moveNo += 1;
    const isCreator = step.member === creator;
    const mover = step.member;
    const other = isCreator ? partner : creator;
    let device = mover.currentGameDevice ?? mover.devices[0];

    // Out-of-turn probe: the OTHER member fires a move → 409 wrong_turn.
    if (moveNo === 2 || (moveNo === 5 && rng.chance(0.7))) {
      const wrong = await (other.devices[0]).http.post(`/api/games/${gameId}/move`, {
        json: { data: { kind: 'place', index: 200 }, clientMoveId: `arena-${couple.key}-g${seq}-wrong-${moveNo}` },
      });
      if (wrong.status !== 409 || wrong.body?.error !== 'wrong_turn') {
        world.violations.add('game_turn_authority', 'critical',
          `out-of-turn move was not refused with 409 wrong_turn (got ${wrong.status})`,
          { couple: couple.ci, game: gameId, body: wrong.body });
      }
    }

    // Input lease: on the mover's 2nd move, the spectator device tries a
    // FRESH move (409 game_lease_held), then takes over and plays it.
    if (moveNo === 3 && mover.devices.length > 1) {
      const spectator = mover.devices[1];
      const blocked = await spectator.http.post(`/api/games/${gameId}/move`, {
        json: { data: { kind: 'place', index: step.index }, clientMoveId: `arena-${couple.key}-g${seq}-spect-${moveNo}` },
      });
      if (blocked.status !== 409 || blocked.body?.error !== 'game_lease_held') {
        world.violations.add('game_lease', 'critical',
          `spectator device move was not refused with 409 game_lease_held (got ${blocked.status})`,
          { couple: couple.ci, game: gameId, body: blocked.body });
      }
      const takeover = await spectator.http.post(`/api/games/${gameId}/takeover`);
      if (expectStatus(world, takeover, [200], 'game takeover', { couple: couple.ci, game: gameId })) {
        await expectFrame(world,
          mover.devices.filter((d) => d.sock.connected), 'game_lease',
          (f) => f.payload?.gameId === gameId && f.payload?.reason === 'takeover',
          `game_lease takeover ${gameId}`);
        mover.currentGameDevice = spectator;
        device = spectator;
      }
    }

    const clientMoveId = `arena-${couple.key}-g${seq}-m${moveNo}`;
    const payload = { data: { kind: 'place', index: step.index }, clientMoveId };
    let response;
    if (moveNo === 6) {
      // Parallel double-send with the SAME clientMoveId from the same device:
      // exactly one stored move (one 201, one 200 duplicate:true).
      const [r1, r2] = await Promise.all([
        device.http.post(`/api/games/${gameId}/move`, { json: payload }),
        device.http.post(`/api/games/${gameId}/move`, { json: payload }),
      ]);
      const statuses = [r1.status, r2.status].sort();
      const okPair = statuses[0] === 200 && statuses[1] === 201;
      const dup = r1.status === 200 ? r1 : r2;
      if (!okPair || dup.body?.duplicate !== true) {
        world.violations.add('game_move_dedup', 'critical',
          `parallel same-clientMoveId sends did not resolve to 201+200(duplicate) — got ${r1.status}/${r2.status}`,
          { couple: couple.ci, game: gameId, r1: r1.body, r2: r2.body });
      }
      response = r1.status === 201 ? r1 : r2;
    } else {
      response = await device.http.post(`/api/games/${gameId}/move`, { json: payload });
    }
    if (!expectStatus(world, response, [201], `game move ${moveNo}`, { couple: couple.ci, game: gameId })) return;
    expectedMoves.push({ memberId: mover.devices[0].memberId, index: step.index });

    // Server-authoritative turn: after a non-final move the OTHER member is
    // up; the decisive move carries an explicit null.
    const isFinal = moveNo === script.length;
    const expectedTurn = isFinal ? null : other.devices[0].memberId;
    if (response.body.turnMemberId !== expectedTurn) {
      world.violations.add('game_turn_authority', 'critical',
        `turnMemberId after move ${moveNo} is ${response.body.turnMemberId}, expected ${expectedTurn}`,
        { couple: couple.ci, game: gameId });
    }
    if (isFinal) {
      const result = response.body.game?.result;
      if (!result || result.winner !== creator.devices[0].memberId) {
        world.violations.add('game_result', 'critical',
          'five in a row did not end the game with the creator as winner',
          { couple: couple.ci, game: gameId, result });
      }
      await expectFrame(world, coupleDevices(couple), 'game_ended',
        (f) => f.payload?.game?.id === gameId, `game_ended ${gameId}`);
    }
  }

  // A late duplicate retry of the FINAL move must return the stored duplicate
  // even though the game has ended (retry contract b).
  const lateRetry = await (creator.currentGameDevice ?? cDev0).http.post(`/api/games/${gameId}/move`, {
    json: { data: { kind: 'place', index: 4 }, clientMoveId: `arena-${couple.key}-g${seq}-m${script.length}` },
  });
  if (lateRetry.status !== 200 || lateRetry.body?.duplicate !== true) {
    world.violations.add('game_move_dedup', 'critical',
      `retry of the final move on the ended game did not return the stored duplicate (got ${lateRetry.status})`,
      { couple: couple.ci, game: gameId, body: lateRetry.body });
  }

  creator.currentGameDevice = null;
  if (!couple.gameExpectations) couple.gameExpectations = [];
  couple.gameExpectations.push({ gameId, expectedMoves });
}

// ---------------------------------------------------------------------------
// lists + canvas: parallel writes from both members

export async function listsCanvasScenario(world, couple, rng) {
  world.bumpScenario('listsCanvas');
  const seq = nextSeq(couple);
  const a = rng.pick(couple.members[0].devices.filter((d) => d.sock.connected)) ?? couple.members[0].devices[0];
  const b = rng.pick(couple.members[1].devices.filter((d) => d.sock.connected)) ?? couple.members[1].devices[0];

  if (!couple.listState) {
    const createdList = await a.http.post('/api/lists', {
      json: { name: `Arena ${couple.marker}`, emoji: '🧪' },
    });
    if (!expectStatus(world, createdList, [201], 'list create', { couple: couple.ci })) return;
    couple.listState = { listId: createdList.body.list.id, itemIds: new Set() };
  }
  const { listId } = couple.listState;

  // Both members add items CONCURRENTLY (no ifRev — last-write-wins adds).
  const [itemA, itemB] = await Promise.all([
    a.http.post(`/api/lists/${listId}/items`, { json: { text: `${couple.marker} item A${seq}` } }),
    b.http.post(`/api/lists/${listId}/items`, { json: { text: `${couple.marker} item B${seq}` } }),
  ]);
  for (const res of [itemA, itemB]) {
    if (expectStatus(world, res, [201], 'list item add', { couple: couple.ci })) {
      couple.listState.itemIds.add(res.body.item.id);
    }
  }
  // Optimistic concurrency: a deliberately STALE ifRev must be a 409 conflict
  // carrying the current list.
  if (rng.chance(0.5)) {
    const stale = await a.http.post(`/api/lists/${listId}/items`, {
      json: { text: `${couple.marker} stale ${seq}`, ifRev: 1 },
    });
    if (stale.status === 201) {
      couple.listState.itemIds.add(stale.body.item.id); // rev 1 only right after create
    } else if (stale.status !== 409 || stale.body?.error !== 'conflict' || !stale.body?.current) {
      world.violations.add('list_ifrev', 'high',
        'stale ifRev add was neither applied nor refused as 409 conflict with current',
        { couple: couple.ci, status: stale.status, body: stale.body });
    }
  }

  // Canvas: both members draw CONCURRENTLY, tagged with the current generation.
  if (!couple.canvasState) couple.canvasState = { generation: 1, strokeIds: new Set() };
  const mkStroke = (mi) => ({
    color: mi === 0 ? '#FF5C8A' : '#4A90D9',
    width: 4,
    tool: 'pen',
    generation: couple.canvasState.generation,
    points: [[rng.next(), rng.next()], [rng.next(), rng.next()], [rng.next(), rng.next()]],
  });
  const [strokeA, strokeB] = await Promise.all([
    a.http.post('/api/canvas/strokes', { json: mkStroke(0) }),
    b.http.post('/api/canvas/strokes', { json: mkStroke(1) }),
  ]);
  for (const res of [strokeA, strokeB]) {
    if (res.status === 201) {
      couple.canvasState.strokeIds.add(res.body.stroke.id);
      if (res.body.generation !== couple.canvasState.generation) {
        couple.canvasState.generation = res.body.generation;
      }
    } else if (res.status === 409 && res.body?.error === 'stale_generation') {
      couple.canvasState.generation = res.body.generation; // legitimate race with a clear
    } else {
      expectStatus(world, res, [201], 'canvas stroke', { couple: couple.ci });
    }
  }
  // Stroke delete (undo) — author-only.
  if (rng.chance(0.3) && strokeA.status === 201) {
    const foreign = await b.http.del(`/api/canvas/strokes/${strokeA.body.stroke.id}`);
    if (foreign.status !== 403) {
      world.violations.add('canvas_authorship', 'high',
        `deleting the partner's stroke was not refused with 403 (got ${foreign.status})`,
        { couple: couple.ci, body: foreign.body });
    }
    const undone = await a.http.del(`/api/canvas/strokes/${strokeA.body.stroke.id}`);
    if (expectStatus(world, undone, [200], 'canvas stroke delete', { couple: couple.ci })) {
      couple.canvasState.strokeIds.delete(strokeA.body.stroke.id);
    }
  }
  // Rare board clear: stale-generation strokes must then be refused.
  if (rng.chance(0.08)) {
    const staleGen = couple.canvasState.generation;
    const cleared = await a.http.del('/api/canvas');
    if (expectStatus(world, cleared, [200], 'canvas clear', { couple: couple.ci })) {
      couple.canvasState.generation = cleared.body.generation;
      couple.canvasState.strokeIds = new Set();
      const stale = await b.http.post('/api/canvas/strokes', {
        json: { ...mkStroke(1), generation: staleGen },
      });
      if (stale.status !== 409 || stale.body?.error !== 'stale_generation') {
        world.violations.add('canvas_generation', 'high',
          `stroke tagged with the wiped generation was not refused (got ${stale.status})`,
          { couple: couple.ci, body: stale.body });
      }
    }
  }
}

// ---------------------------------------------------------------------------
// reconnect storm: drop a device's socket, reconnect, verify welcome+catchup

export async function reconnectScenario(world, couple, rng) {
  world.bumpScenario('reconnect');
  const devices = coupleDevices(couple);
  if (devices.length <= 1) return;
  const device = rng.pick(devices);
  device.sock.close({ expected: true });
  await sleep(rng.int(150, 900));
  try {
    await device.sock.connect();
  } catch (err) {
    if (!world.expectDisconnects) {
      world.violations.add('reconnect_failed', 'high',
        `device ${device.name} could not reconnect: ${err.message}`, {});
    }
    return;
  }
  const welcome = await device.sock.waitFor('welcome').catch(() => null);
  if (!welcome) {
    world.violations.add('reconnect_failed', 'high',
      `device ${device.name} got no welcome frame after reconnect`, {});
    return;
  }
  if (welcome.payload?.memberId !== device.memberId || welcome.payload?.coupleId !== device.coupleId) {
    world.violations.add('welcome_identity', 'critical',
      `welcome frame identifies the wrong member/couple on ${device.name}`,
      { payload: welcome.payload });
  }
  // Catch-up: whatever the device missed while offline must be reachable via
  // REST — the couple's newest message id has to be in GET /api/messages.
  if (couple.lastMessageId) {
    const messages = await device.http.get('/api/messages?limit=50');
    if (messages.status === 200
      && !messages.body.messages.some((m) => m.id === couple.lastMessageId)) {
      world.violations.add('catchup_gap', 'high',
        `after reconnect GET /api/messages is missing the newest message ${couple.lastMessageId}`,
        { couple: couple.ci, device: device.name });
    }
  }
}
