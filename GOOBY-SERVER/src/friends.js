// Freunde (Doc C §3.2): Request per friendCode ODER (eindeutigem) Namen, Accept/Decline/
// Remove, Liste mit Presence + Coins-Anzeige-Cache. Persistenz: friends.json
// {edges:[{a,b,since}], requests:[{from,to,at}]} — a/b/from/to sind friendCodes.

import { LIMITS } from './ratelimit.js';
import { FRIEND_CODE_RE } from './auth.js';

export function friendsData(ctx) {
  return ctx.store.collection('friends', { edges: [], requests: [] });
}

export function areFriends(ctx, codeA, codeB) {
  return friendsData(ctx).edges.some(
    (e) => (e.a === codeA && e.b === codeB) || (e.a === codeB && e.b === codeA)
  );
}

export function friendCodesOf(ctx, code) {
  const out = [];
  for (const e of friendsData(ctx).edges) {
    if (e.a === code) out.push(e.b);
    else if (e.b === code) out.push(e.a);
  }
  return out;
}

function deviceByCode(ctx, code) {
  return ctx.byCode.get(code) || null;
}

function requestExists(ctx, from, to) {
  return friendsData(ctx).requests.some((r) => r.from === from && r.to === to);
}

function removeRequest(ctx, from, to) {
  const data = friendsData(ctx);
  data.requests = data.requests.filter((r) => !(r.from === from && r.to === to));
  ctx.store.markDirty('friends');
}

// Aktivität für die Freunde-Liste: live von der Verbindung (presence.js setzt conn.presence).
export function activityFor(ctx, deviceId) {
  const conn = ctx.hub.connFor(deviceId);
  if (!conn) return null;
  return conn.presence || { kind: 'online', label: 'ist online' };
}

function friendEntry(ctx, code) {
  const deviceId = deviceByCode(ctx, code);
  const p = deviceId ? ctx.players[deviceId] : null;
  if (!p) return null;
  return {
    friendCode: code,
    name: p.name,
    goobyName: p.goobyName,
    online: ctx.hub.isOnline(deviceId),
    activity: activityFor(ctx, deviceId),
    coins: p.coins,
    coinsUpdatedAt: p.coinsUpdatedAt,
    lastSeenAt: p.lastSeenAt,
  };
}

export function friendsState(ctx, conn) {
  return {
    friends: friendCodesOf(ctx, conn.friendCode)
      .map((code) => friendEntry(ctx, code))
      .filter(Boolean),
    requests: pendingRequestsFor(ctx, conn.friendCode),
  };
}

export function pendingRequestsFor(ctx, code) {
  return friendsData(ctx)
    .requests.filter((r) => r.to === code)
    .map((r) => {
      const deviceId = deviceByCode(ctx, r.from);
      const p = deviceId ? ctx.players[deviceId] : null;
      return p ? { from: r.from, name: p.name, goobyName: p.goobyName, at: r.at } : null;
    })
    .filter(Boolean);
}

function makeFriends(ctx, codeA, codeB) {
  const data = friendsData(ctx);
  data.edges.push({ a: codeA, b: codeB, since: ctx.clock.now() });
  data.requests = data.requests.filter(
    (r) =>
      !(r.from === codeA && r.to === codeB) &&
      !(r.from === codeB && r.to === codeA)
  );
  ctx.store.markDirty('friends');
  for (const [me, other] of [
    [codeA, codeB],
    [codeB, codeA],
  ]) {
    const deviceId = deviceByCode(ctx, me);
    if (!deviceId) continue;
    const entry = friendEntry(ctx, other);
    if (entry) ctx.hub.sendToDevice(deviceId, 'FRIEND_ADDED', entry);
  }
}

// Ziel auflösen: {target:"GOOBY-XXXX"} oder {targetName:"Lena"} (eindeutig, sonst AMBIGUOUS).
function resolveTarget(ctx, d) {
  if (typeof d.target === 'string') {
    const code = d.target.toUpperCase();
    if (!FRIEND_CODE_RE.test(code)) return { code: 'NOT_FOUND' };
    if (!deviceByCode(ctx, code)) return { code: 'NOT_FOUND' };
    return { target: code };
  }
  if (typeof d.targetName === 'string') {
    const wanted = d.targetName.trim().toLowerCase();
    const matches = Object.values(ctx.players).filter(
      (p) => p.name && p.name.toLowerCase() === wanted
    );
    if (matches.length === 0) return { code: 'NOT_FOUND' };
    if (matches.length > 1) return { code: 'AMBIGUOUS' };
    return { target: matches[0].friendCode };
  }
  return { code: 'NOT_FOUND' };
}

export function register(ctx) {
  const { hub } = ctx;
  friendsData(ctx); // Collection früh laden

  hub.addWelcomeProvider((conn) => ({
    friendRequests: pendingRequestsFor(ctx, conn.friendCode),
  }));

  hub.on('FRIEND_REQUEST', (conn, msg) => {
    if (!ctx.buckets.take(`freq:${conn.deviceId}`, LIMITS.friendRequest)) {
      hub.sendError(conn, 'RATE_LIMIT', { re: msg.seq });
      return;
    }
    const res = resolveTarget(ctx, msg.d);
    if (res.code) {
      hub.sendError(conn, res.code, { re: msg.seq });
      return;
    }
    const target = res.target;
    const me = conn.friendCode;
    if (target === me) return hub.sendError(conn, 'SELF', { re: msg.seq });
    if (areFriends(ctx, me, target)) return hub.sendError(conn, 'ALREADY_FRIENDS', { re: msg.seq });
    if (requestExists(ctx, me, target)) return hub.sendError(conn, 'DUPLICATE', { re: msg.seq });
    // Gegenrichtung offen? → auto-accept (beide wollten es).
    if (requestExists(ctx, target, me)) {
      makeFriends(ctx, me, target);
      hub.send(conn, 'OK', { autoAccepted: true }, { re: msg.seq });
      return;
    }
    const data = friendsData(ctx);
    data.requests.push({ from: me, to: target, at: ctx.clock.now() });
    ctx.store.markDirty('friends');
    hub.send(conn, 'OK', {}, { re: msg.seq });
    const targetDevice = deviceByCode(ctx, target);
    if (targetDevice) {
      hub.sendToDevice(targetDevice, 'FRIEND_REQUEST_INCOMING', {
        from: me,
        name: conn.name,
        goobyName: conn.goobyName,
        at: ctx.clock.now(),
      });
    }
  });

  hub.on('FRIEND_ACCEPT', (conn, msg) => {
    const from = typeof msg.d.target === 'string' ? msg.d.target.toUpperCase() : '';
    if (!requestExists(ctx, from, conn.friendCode)) {
      hub.sendError(conn, 'NOT_FOUND', { re: msg.seq });
      return;
    }
    makeFriends(ctx, from, conn.friendCode);
    hub.send(conn, 'OK', {}, { re: msg.seq });
  });

  hub.on('FRIEND_DECLINE', (conn, msg) => {
    const from = typeof msg.d.target === 'string' ? msg.d.target.toUpperCase() : '';
    removeRequest(ctx, from, conn.friendCode);
    hub.send(conn, 'OK', {}, { re: msg.seq }); // leise — kein Push an den Requester
  });

  hub.on('FRIEND_REMOVE', (conn, msg) => {
    const target = typeof msg.d.target === 'string' ? msg.d.target.toUpperCase() : '';
    if (!areFriends(ctx, conn.friendCode, target)) {
      hub.sendError(conn, 'NOT_FRIENDS', { re: msg.seq });
      return;
    }
    const data = friendsData(ctx);
    data.edges = data.edges.filter(
      (e) =>
        !(
          (e.a === conn.friendCode && e.b === target) ||
          (e.a === target && e.b === conn.friendCode)
        )
    );
    ctx.store.markDirty('friends');
    hub.send(conn, 'OK', {}, { re: msg.seq });
    const targetDevice = deviceByCode(ctx, target);
    if (targetDevice) {
      hub.sendToDevice(targetDevice, 'FRIEND_REMOVED', { friendCode: conn.friendCode });
    }
    hub.send(conn, 'FRIEND_REMOVED', { friendCode: target });
  });

  hub.on('FRIENDS_LIST', (conn, msg) => {
    hub.send(conn, 'FRIENDS_STATE', friendsState(ctx, conn), { re: msg.seq });
  });
}
