import { ID_RE, MARKER_RE, collectStrings, deepEqual, firstDiff } from './util.mjs';

/**
 * Post-run invariant pass. Runs over the COMPLETE evidence of a run — the
 * frame log, the id-ownership registry, tracked scenario expectations and
 * fresh final GETs — so violations that live checks could not see yet
 * (e.g. an id that was registered only after a frame arrived) are caught.
 */

const ARTIFACT_PREFIX = { touch: 't', pulse: 'pl', note: 'pn' };

// --- (a) cross-couple isolation --------------------------------------------

export function checkFrameOwnership(world) {
  for (const entry of world.frameLog) {
    for (const str of collectStrings(entry.frame)) {
      if (ID_RE.test(str)) {
        const owner = world.idOwner.get(str);
        if (owner !== undefined && owner !== entry.coupleIdx) {
          world.violations.add('cross_couple_frame', 'critical',
            `device ${entry.device} (couple ${entry.coupleIdx}) received a "${entry.frame.type}" frame containing id ${str} of couple ${owner}`,
            { frameType: entry.frame.type, id: str });
        }
      }
      for (const match of str.matchAll(MARKER_RE)) {
        const markedCouple = Number(match[1]);
        if (markedCouple !== entry.coupleIdx) {
          world.violations.add('cross_couple_marker', 'critical',
            `device ${entry.device} (couple ${entry.coupleIdx}) received content marked for couple ${markedCouple}`,
            { frameType: entry.frame.type, text: str.slice(0, 120) });
        }
      }
    }
  }
}

// --- Zeitpost surprise + pulse fanout audits over the frame log ------------

export function checkFanout(world) {
  for (const entry of world.frameLog) {
    const { frame } = entry;
    if (frame.type === 'post_scheduled' || frame.type === 'post_canceled') {
      // Surprise contract: these frames may ONLY reach the scheduling
      // member's own devices.
      if (frame.origin?.memberId && frame.origin.memberId !== entry.memberId) {
        world.violations.add('zeitpost_surprise_leak', 'critical',
          `"${frame.type}" frame reached ${entry.device}, a device of the PARTNER`,
          { frame });
      }
    }
    if (frame.type === 'pulse') {
      const pulse = frame.payload?.pulse;
      // Live pulses go to the recipient only; Zeitpost pulse deliveries
      // (viaPost) legitimately broadcast to the whole couple.
      if (pulse && pulse.viaPost !== true && pulse.senderId === entry.memberId) {
        world.violations.add('pulse_self_fanout', 'medium',
          `live pulse ${pulse.id} echoed back to a device of its sender (${entry.device})`,
          { pulse });
      }
    }
    if (frame.type === 'game_lease') {
      // Lease frames are member-only: the partner has no business knowing
      // which of my devices drives.
      const leaseMember = frame.payload?.memberId;
      if (leaseMember && leaseMember !== entry.memberId) {
        world.violations.add('lease_fanout_leak', 'high',
          `game_lease for member ${leaseMember} reached partner device ${entry.device}`,
          { frame });
      }
    }
  }
}

// --- (c) Zeitpost exactly-once ----------------------------------------------

/**
 * For every tracked scheduled post: canceled → no artifact; due → EXACTLY one
 * artifact under the stable post-derived id, visible in the journal.
 * `graceMs` shields posts whose deliverAt is too close to run end to judge.
 */
export async function checkZeitpostDelivery(world, { graceMs = 4_000 } = {}) {
  const now = Date.now();
  for (const couple of world.couples) {
    const posts = world.scheduledPosts.filter((p) => p.ci === couple.ci);
    if (posts.length === 0) continue;
    const device = couple.members[0].devices[0];
    const journalRes = await device.http.get('/api/post/journal?limit=300');
    const touchesRes = await device.http.get('/api/touches/recent?limit=500');
    if (journalRes.status !== 200 || touchesRes.status !== 200) {
      world.violations.add('zeitpost_check_failed', 'high',
        `final journal/touches fetch failed for couple ${couple.ci}`, {});
      continue;
    }
    const journal = journalRes.body.entries;
    for (const post of posts) {
      const artifactId = `${ARTIFACT_PREFIX[post.kind]}_${post.postId}`;
      const inJournal = journal.filter((e) => e.id === artifactId);
      if (post.canceled) {
        if (inJournal.length !== 0) {
          world.violations.add('zeitpost_canceled_delivered', 'critical',
            `CANCELED post ${post.postId} still produced artifact ${artifactId}`,
            { couple: couple.ci, entries: inJournal });
        }
        continue;
      }
      const due = post.deliverAtMs <= now - graceMs;
      if (!due) continue; // too close to the end to judge
      if (inJournal.length !== 1) {
        world.violations.add('zeitpost_exactly_once', 'critical',
          `due post ${post.postId} has ${inJournal.length} journal artifacts (expected exactly 1: ${artifactId})`,
          { couple: couple.ci, kind: post.kind, deliverAt: new Date(post.deliverAtMs).toISOString() });
        continue;
      }
      if (inJournal[0].viaPost !== true || inJournal[0].senderId !== post.senderId) {
        world.violations.add('zeitpost_artifact_shape', 'high',
          `artifact ${artifactId} is missing viaPost:true or has the wrong sender`,
          { couple: couple.ci, entry: inJournal[0] });
      }
      if (post.kind === 'touch') {
        const inTouches = touchesRes.body.touches.filter((t) => t.id === artifactId);
        if (inTouches.length !== 1) {
          world.violations.add('zeitpost_exactly_once', 'critical',
            `due touch post ${post.postId}: ${inTouches.length} entries in /api/touches/recent (expected 1)`,
            { couple: couple.ci });
        }
      }
    }
  }
}

// --- (f) journal ordering ---------------------------------------------------

export async function checkJournalOrder(world) {
  for (const couple of world.couples) {
    const device = couple.members[0].devices[0];
    const res = await device.http.get('/api/post/journal?limit=300');
    if (res.status !== 200) continue;
    const entries = res.body.entries;
    for (let i = 1; i < entries.length; i += 1) {
      const prev = entries[i - 1];
      const cur = entries[i];
      const ordered = prev.createdAt > cur.createdAt
        || (prev.createdAt === cur.createdAt && prev.id > cur.id);
      if (!ordered) {
        world.violations.add('journal_order', 'high',
          `journal of couple ${couple.ci} is out of order at index ${i}`,
          { prev: { id: prev.id, createdAt: prev.createdAt }, cur: { id: cur.id, createdAt: cur.createdAt } });
      }
    }
    // (b) one echo per original, journal-wide.
    const echoCounts = new Map();
    for (const entry of entries) {
      if (entry.echo && entry.echoOf) {
        echoCounts.set(entry.echoOf, (echoCounts.get(entry.echoOf) ?? 0) + 1);
      }
    }
    for (const [original, count] of echoCounts) {
      if (count > 1) {
        world.violations.add('echo_uniqueness', 'critical',
          `touch ${original} of couple ${couple.ci} has ${count} echoes in the journal (max 1)`,
          {});
      }
    }
  }
}

// --- (e) game move-list integrity -------------------------------------------

export async function checkGameIntegrity(world) {
  for (const couple of world.couples) {
    for (const expectation of couple.gameExpectations ?? []) {
      const device = couple.members[0].devices[0];
      const res = await device.http.get(`/api/games/${expectation.gameId}`);
      if (res.status !== 200) {
        world.violations.add('game_fetch_failed', 'high',
          `final GET of game ${expectation.gameId} failed (${res.status})`, { couple: couple.ci });
        continue;
      }
      const stored = res.body.game.moves.map((m) => ({ memberId: m.memberId, index: m.data?.index }));
      const expected = expectation.expectedMoves;
      const matches = stored.length === expected.length
        && stored.every((m, i) => m.memberId === expected[i].memberId && m.index === expected[i].index);
      if (!matches) {
        world.violations.add('game_move_list', 'critical',
          `stored move list of game ${expectation.gameId} diverges from the scripted sequence (stored ${stored.length}, expected ${expected.length}) — duplicate or lost moves`,
          { couple: couple.ci, stored, expected });
      }
      const moveIds = res.body.game.moves.map((m) => m.id);
      if (new Set(moveIds).size !== moveIds.length) {
        world.violations.add('game_move_list', 'critical',
          `game ${expectation.gameId} contains duplicate move ids`, { couple: couple.ci });
      }
    }
  }
}

// --- lists + canvas final consistency ----------------------------------------

export async function checkCollections(world) {
  for (const couple of world.couples) {
    const device = couple.members[0].devices[0];
    if (couple.listState) {
      const res = await device.http.get('/api/lists');
      if (res.status === 200) {
        const list = res.body.lists.find((l) => l.id === couple.listState.listId);
        const storedIds = new Set((list?.items ?? []).map((i) => i.id));
        const expectedIds = couple.listState.itemIds;
        const missing = [...expectedIds].filter((id) => !storedIds.has(id));
        const extra = [...storedIds].filter((id) => !expectedIds.has(id));
        if (missing.length > 0 || extra.length > 0) {
          world.violations.add('list_divergence', 'critical',
            `list ${couple.listState.listId} of couple ${couple.ci} lost or invented items`,
            { missing, extra });
        }
      }
    }
    if (couple.canvasState) {
      const res = await device.http.get('/api/canvas');
      if (res.status === 200) {
        const storedIds = new Set(res.body.strokes.map((s) => s.id));
        const expectedIds = couple.canvasState.strokeIds;
        const missing = [...expectedIds].filter((id) => !storedIds.has(id));
        const extra = [...storedIds].filter((id) => !expectedIds.has(id));
        if (missing.length > 0 || extra.length > 0) {
          world.violations.add('canvas_divergence', 'critical',
            `canvas of couple ${couple.ci} diverges from the tracked stroke set`,
            { missing, extra, generation: res.body.generation });
        }
      }
    }
    // list rev monotonicity per device (frames arrive in order per socket).
    const revByDeviceList = new Map();
    for (const entry of world.frameLog) {
      if (entry.coupleIdx !== couple.ci || entry.frame.type !== 'list_updated') continue;
      const list = entry.frame.payload?.list;
      if (!list?.id) continue;
      const key = `${entry.device}:${list.id}:${entry.generation}`;
      const prev = revByDeviceList.get(key);
      if (prev !== undefined && list.rev < prev) {
        world.violations.add('list_rev_regression', 'high',
          `list_updated rev regressed on ${entry.device} (${prev} → ${list.rev})`,
          { listId: list.id });
      }
      revByDeviceList.set(key, list.rev);
    }
  }
}

// --- (i) persistence across restart ------------------------------------------

/**
 * Compares before/after snapshots around a server crash+restart.
 * Zeitposts due during the outage are the ONE legitimate difference; they are
 * transformed out: due scheduled entries must be GONE afterwards and their
 * artifact must exist EXACTLY once in the after-journal.
 */
export function verifyRestartPersistence(world, couple, before, after, { dueBeforeMs }) {
  const strictKeys = ['couple', 'messages', 'games', 'lists', 'canvas', 'events', 'daily'];
  for (const key of strictKeys) {
    if (!deepEqual(before[key], after[key])) {
      const diff = firstDiff(before[key], after[key]);
      world.violations.add('restart_persistence', 'critical',
        `couple ${couple.ci}: "${key}" changed across the crash+restart`,
        { path: diff?.path, before: diff?.before, after: diff?.after });
    }
  }
  // Scheduled posts: due ones must be delivered, later ones must survive.
  for (const memberKey of ['a', 'b']) {
    const beforePosts = before.scheduled[memberKey];
    const afterPosts = after.scheduled[memberKey];
    const afterIds = new Set(afterPosts.map((p) => p.id));
    for (const post of beforePosts) {
      const deliverAtMs = Date.parse(post.deliverAt);
      const artifactId = `${ARTIFACT_PREFIX[post.kind]}_${post.id}`;
      const artifacts = after.journal.filter((e) => e.id === artifactId);
      if (deliverAtMs <= dueBeforeMs) {
        // Definitely due during/after the outage: must be delivered exactly once.
        if (afterIds.has(post.id)) {
          world.violations.add('restart_delivery', 'critical',
            `couple ${couple.ci}: post ${post.id} was due during the outage but is still open after restart`,
            { post });
        } else if (artifacts.length !== 1) {
          world.violations.add('restart_delivery', 'critical',
            `couple ${couple.ci}: outage-due post ${post.id} has ${artifacts.length} artifacts after restart (expected exactly 1)`,
            { post });
        }
      } else if (deliverAtMs <= after.at) {
        // Gray zone (due within the sweep jitter around the after-snapshot):
        // open OR delivered are both fine — but never duplicated.
        if (!afterIds.has(post.id) && artifacts.length !== 1) {
          world.violations.add('restart_delivery', 'critical',
            `couple ${couple.ci}: gray-zone post ${post.id} is neither open nor delivered exactly once`,
            { post, artifacts: artifacts.length });
        }
      } else if (!afterIds.has(post.id)) {
        world.violations.add('restart_persistence', 'critical',
          `couple ${couple.ci}: NOT-yet-due post ${post.id} vanished across the restart`,
          { post });
      }
    }
    // No invented posts.
    const beforeIds = new Set(beforePosts.map((p) => p.id));
    for (const post of afterPosts) {
      if (!beforeIds.has(post.id)) {
        world.violations.add('restart_persistence', 'critical',
          `couple ${couple.ci}: post ${post.id} appeared out of nowhere after the restart`,
          { post });
      }
    }
  }
  // Journal: every pre-crash entry must survive (30-day window ≫ run length).
  const afterJournalIds = new Set(after.journal.map((e) => e.id));
  for (const entry of before.journal) {
    if (!afterJournalIds.has(entry.id)) {
      world.violations.add('restart_persistence', 'critical',
        `couple ${couple.ci}: journal entry ${entry.id} was lost across the restart`,
        { entry });
    }
  }
}
