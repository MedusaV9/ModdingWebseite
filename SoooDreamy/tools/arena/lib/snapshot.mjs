/**
 * GET-based couple state snapshots for the persistence invariant (i):
 * state before a server crash must equal state after the restart, modulo
 * volatile presence fields and Zeitposts that legitimately became due while
 * the server was down (verified separately by the delivery transform in
 * checks.mjs).
 */

function normalizeMember(member) {
  const { online, lastSeenAt, mood, moodUpdatedAt, moodNote, nowPlaying, energy, presence, ...stable } = member ?? {};
  return stable;
}

function normalizeCouple(body) {
  const couple = body?.couple ?? {};
  return {
    id: couple.id,
    name: couple.name,
    code: couple.code,
    anniversary: couple.anniversary,
    members: (couple.members ?? []).map(normalizeMember),
  };
}

function normalizeGame(game) {
  return {
    id: game.id,
    type: game.type,
    state: game.state,
    result: game.result,
    turnMemberId: game.turnMemberId,
    moveCount: game.moves?.length ?? 0,
    moveIds: (game.moves ?? []).map((m) => m.id),
  };
}

export async function snapshotCouple(couple) {
  const a = couple.members[0].devices[0];
  const b = couple.members[1].devices[0];
  const get = async (device, path) => {
    const res = await device.http.get(path);
    if (res.status !== 200) throw new Error(`snapshot GET ${path} → ${res.status}`);
    return res.body;
  };
  const [
    coupleView, messages, touches, journal, games, lists, canvas, events,
    scheduledA, scheduledB, pulsesA, pulsesB, dailyA, dailyB,
  ] = await Promise.all([
    get(a, '/api/couple'),
    get(a, '/api/messages?limit=50'),
    get(a, '/api/touches/recent?limit=30'),
    get(a, '/api/post/journal?limit=300'),
    get(a, '/api/games?limit=50'),
    get(a, '/api/lists'),
    get(a, '/api/canvas'),
    get(a, '/api/events'),
    get(a, '/api/post/scheduled'),
    get(b, '/api/post/scheduled'),
    get(a, '/api/pulses'),
    get(b, '/api/pulses'),
    get(a, '/api/daily?limit=10'),
    get(b, '/api/daily?limit=10'),
  ]);
  return {
    at: Date.now(),
    couple: normalizeCouple(coupleView),
    messages: messages.messages,
    touches: touches.touches,
    journal: journal.entries,
    games: (games.games ?? []).map(normalizeGame),
    lists: lists.lists,
    canvas: { generation: canvas.generation, strokeIds: (canvas.strokes ?? []).map((s) => s.id) },
    events: events.events,
    scheduled: { a: scheduledA.posts, b: scheduledB.posts },
    pulses: { a: pulsesA.pulses, b: pulsesB.pulses },
    daily: { a: dailyA.entries, b: dailyB.entries },
  };
}
