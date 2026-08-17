// GvZ-Netz-PvP (G7, Doc G §4.5 / Doc C §3.8): 2-Spieler-Lockstep-Relay auf
// eigenen `gvz:`-Räumen (max 2, nur Freunde) — Kopiervorlage war das
// GOB-NOM-Coop-Modul (gobnommp.js, PROTOKOLL-VERTRAG v1). Client-Gegenstück:
// GOOBY-GODOT scripts/minigames/games/gvz/pvp_netz/gvz_net_session.gd.
//
// Autoritätsmodell: Die Sim (GvzPvpLockstep, Godot) ist deterministisch —
// der Server kennt KEINE Spielregeln. Er ist autoritativ für Mitgliedschaft,
// Seiten (Einladender = 'gooby' verteidigt, Annehmender = 'zombie' schickt
// Wellen), Start-Handshake (BEIDE senden GVZ_START_REQ), den Start-Seed,
// Input-Frame-Ordnung (n monoton) und das idempotente Ergebnis (pending +
// ACK, GoobyPal-Muster) inkl. kleinem Münz-Reward.
//
// BEWUSST OHNE Rejoin-Snapshot/Frame-Puffer (Unterschied zu GOB-NOM):
// PvP-Matches sind kurz — bei Abriss wartet der Partner die Frist ab
// (GVZ_PEER_DOWN/„waitMs“), Rückkehr in den Raum meldet GVZ_PEER_UP,
// Fristablauf oder bewusstes ROOM_LEAVE bricht ab (GVZ_ABORTED).
//
// Desync-Wächter: Clients melden alle `hashEveryTicks` Ticks ihren
// State-Hash (GP_HASH). Der Server vergleicht beide Seiten pro Tick und
// bricht bei Abweichung höflich ab (GVZ_DESYNC an beide) — zusätzlich
// wird der Hash relayt, damit die Clients selbst vergleichen können.
//
// PROTOKOLL-VERTRAG v1 (Spiegel von gobnommp.js):
//   Hub-Events: GVZ_INVITE/_DECLINE/_ACCEPT → GVZ_READY,
//     GVZ_START_REQ (beide) → GVZ_START {seed VOM SERVER},
//     GVZ_RESULT (+_ACK) → GVZ_RESULT-Push (rewardId + coins).
//   ROOM_MSG-Kinds: GP_INPUT {n, upTo, a:[{t,do,…}]}, GP_HASH {t,h}.
//   Pushes: GVZ_INVITED, GVZ_DECLINED, GVZ_PEER_DOWN/_UP, GVZ_DESYNC,
//     GVZ_ABORTED. WELCOME-Feld: gvzPending (offene Ergebnisse).

import crypto from 'node:crypto';
import { LIMITS } from './ratelimit.js';
import { areFriends } from './friends.js';
import { restAuth, FRIEND_CODE_RE } from './auth.js';

const INVITE_TTL_MS = 30_000;
const SIDE_GOOBY = 'gooby'; // Einladender — verteidigt das Haus
const SIDE_ZOMBIE = 'zombie'; // Annehmender — schickt die Wellen
// Lockstep-Parameter — Teil des Ready-/Start-Payloads, damit beide Clients
// dieselben Werte fahren (GvzPvpLockstep.INPUT_DELAY/HASH_TICKS).
const INPUT_DELAY_TICKS = 4; // Standard-Lockstep-Fenster (3–5 Ticks)
const HASH_EVERY_TICKS = 60; // Desync-Check alle 3 s (20-Hz-Sim)
const MAX_ACTIONS_PER_FRAME = 16;
// Aktions-Whitelist der PvP-Sim (GvzPvpLockstep._dispatch): Gooby pflanzt/
// schaufelt/sammelt, Zombie beschwört — das Seiten-Gate sitzt im Client-
// Dispatch (deterministisch), der Server prüft nur die Form.
const ACTION_DOS = new Set(['place', 'shovel', 'collect', 'spawn']);
// Kleines Münz-Reward (idempotent über rewardId, gobnom-Muster): Beträge an
// der GvZ-Kampagnen-Coin-Row orientiert (Doc G §4.4: max 30 pro Levelsieg) —
// der Verlierer bekommt einen Trostbetrag, damit die Revanche süß bleibt.
const WINNER_COINS = 30;
const LOSER_COINS = 10;

function pendingData(ctx) {
  // Ergebnis-Zustellung: friendCode -> [result] (idempotent über rewardId).
  return ctx.store.collection('gvzmp', { pending: {} });
}

export function register(ctx) {
  const { hub, cfg } = ctx;
  pendingData(ctx);

  // roomId -> Session
  const sessions = new Map();
  // "<from>-><target>" -> {at}
  const invites = new Map();

  const now = () => ctx.clock.now();
  const playerInfo = (code, side) => {
    const device = ctx.byCode.get(code);
    const player = device ? ctx.players[device] : null;
    return {
      friendCode: code,
      side,
      name: player?.name ?? '?',
      goobyName: player?.goobyName ?? 'Gooby',
    };
  };

  function sessionFor(code) {
    for (const session of sessions.values()) {
      if (session.sides.has(code)) return session;
    }
    return null;
  }

  function createSession(hostCode, guestCode) {
    const room = `gvz:${crypto.randomUUID()}`;
    const session = {
      room,
      phase: 'lobby', // lobby → run → done | desync | aborted
      sides: new Map([
        [hostCode, SIDE_GOOBY],
        [guestCode, SIDE_ZOMBIE],
      ]),
      startReq: new Set(), // Codes, die GVZ_START_REQ gesendet haben
      seed: 0,
      startedAt: 0,
      lastFrameN: new Map(), // code -> letzte Frame-Nr (Ordnung!)
      hashes: new Map(), // tick -> { gooby?, zombie? }
      result: null,
      disconnected: new Set(),
      rejoinTimers: new Map(),
      createdAt: now(),
    };
    ctx.rooms.ensure(room, { maxMembers: 2 });
    sessions.set(room, session);
    return session;
  }

  function cleanupSession(session) {
    for (const timer of session.rejoinTimers.values()) clearTimeout(timer);
    session.rejoinTimers.clear();
    sessions.delete(session.room);
    ctx.rooms.destroy(session.room);
  }

  function broadcast(session, t, d, exceptCode = '') {
    for (const code of session.sides.keys()) {
      if (code === exceptCode) continue;
      const device = ctx.byCode.get(code);
      if (device) hub.sendToDevice(device, t, d);
    }
  }

  function playersOf(session) {
    return [...session.sides.entries()].map(([code, side]) => playerInfo(code, side));
  }

  function lobbyPayload(session) {
    return {
      room: session.room,
      players: playersOf(session),
      inputDelay: INPUT_DELAY_TICKS,
      hashEveryTicks: HASH_EVERY_TICKS,
    };
  }

  function abort(session, reason, byCode = '') {
    if (session.phase === 'done') {
      cleanupSession(session);
      return;
    }
    session.phase = 'aborted';
    broadcast(session, 'GVZ_ABORTED', { room: session.room, reason, by: byCode }, byCode);
    cleanupSession(session);
  }

  // Nur die beiden Session-Mitglieder dürfen in ihren Raum (auch Rückkehr).
  ctx.rooms.registerJoinGuard('gvz', (conn, roomId) => {
    const session = sessions.get(roomId);
    if (!session || !session.sides.has(conn.friendCode)) return { ok: false, code: 'BAD_ROOM' };
    return { ok: true };
  });

  // ---- Einladung (Muster GOBNOM_INVITE — nur Freunde, TTL, online) ----------

  hub.on('GVZ_INVITE', (conn, msg) => {
    if (!ctx.buckets.take(`gvzinv:${conn.deviceId}`, LIMITS.rmpInvite)) {
      return hub.sendError(conn, 'RATE_LIMIT', { re: msg.seq });
    }
    const target = typeof msg.d.target === 'string' ? msg.d.target.toUpperCase() : '';
    if (!FRIEND_CODE_RE.test(target) || !ctx.byCode.has(target)) {
      return hub.sendError(conn, 'NOT_FOUND', { re: msg.seq });
    }
    if (target === conn.friendCode) return hub.sendError(conn, 'SELF', { re: msg.seq });
    if (!areFriends(ctx, conn.friendCode, target)) {
      return hub.sendError(conn, 'NOT_FRIENDS', { re: msg.seq });
    }
    const targetDevice = ctx.byCode.get(target);
    if (!hub.isOnline(targetDevice)) return hub.sendError(conn, 'OFFLINE_TARGET', { re: msg.seq });
    if (sessionFor(conn.friendCode) || sessionFor(target)) {
      return hub.sendError(conn, 'GAME_RUNNING', { re: msg.seq });
    }
    invites.set(`${conn.friendCode}->${target}`, { at: now() });
    hub.send(conn, 'OK', {}, { re: msg.seq });
    hub.sendToDevice(targetDevice, 'GVZ_INVITED', {
      from: conn.friendCode,
      name: conn.name,
      goobyName: conn.goobyName,
      expiresInMs: INVITE_TTL_MS,
    });
  });

  hub.on('GVZ_DECLINE', (conn, msg) => {
    const from = typeof msg.d.from === 'string' ? msg.d.from.toUpperCase() : '';
    if (invites.delete(`${from}->${conn.friendCode}`)) {
      const fromDevice = ctx.byCode.get(from);
      if (fromDevice) hub.sendToDevice(fromDevice, 'GVZ_DECLINED', { from: conn.friendCode });
    }
    hub.send(conn, 'OK', {}, { re: msg.seq });
  });

  hub.on('GVZ_ACCEPT', (conn, msg) => {
    const from = typeof msg.d.from === 'string' ? msg.d.from.toUpperCase() : '';
    const key = `${from}->${conn.friendCode}`;
    const invite = invites.get(key);
    if (!invite || now() - invite.at > INVITE_TTL_MS) {
      invites.delete(key);
      return hub.sendError(conn, 'NOT_FOUND', { re: msg.seq });
    }
    invites.delete(key);
    const inviterDevice = ctx.byCode.get(from);
    if (!hub.isOnline(inviterDevice)) return hub.sendError(conn, 'OFFLINE_TARGET', { re: msg.seq });
    if (sessionFor(conn.friendCode) || sessionFor(from)) {
      return hub.sendError(conn, 'GAME_RUNNING', { re: msg.seq });
    }
    const session = createSession(from, conn.friendCode);
    const ready = lobbyPayload(session);
    hub.send(conn, 'GVZ_READY', ready, { re: msg.seq });
    hub.sendToDevice(inviterDevice, 'GVZ_READY', ready);
  });

  // ---- Start-Handshake: BEIDE senden GVZ_START_REQ → Start mit Server-Seed --

  function tryStart(session) {
    if (session.phase !== 'lobby' || session.startReq.size < 2) return;
    const room = ctx.rooms.get(session.room);
    if (!room) return;
    for (const code of session.sides.keys()) {
      const device = ctx.byCode.get(code);
      if (!device || !room.members.has(device)) return; // beide müssen im Raum sein
    }
    session.phase = 'run';
    session.seed = crypto.randomBytes(4).readUInt32BE(0) & 0x7fffffff;
    session.startedAt = now();
    broadcast(session, 'GVZ_START', {
      room: session.room,
      seed: session.seed,
      inputDelay: INPUT_DELAY_TICKS,
      hashEveryTicks: HASH_EVERY_TICKS,
      players: playersOf(session),
      serverNow: session.startedAt,
    });
  }

  hub.on('GVZ_START_REQ', (conn, msg) => {
    const session = sessions.get(typeof msg.d.room === 'string' ? msg.d.room : '');
    if (!session || !session.sides.has(conn.friendCode)) {
      return hub.sendError(conn, 'NOT_IN_ROOM', { re: msg.seq });
    }
    if (session.phase !== 'lobby') return hub.sendError(conn, 'GAME_RUNNING', { re: msg.seq });
    session.startReq.add(conn.friendCode);
    hub.send(conn, 'OK', { waiting: session.startReq.size < 2 }, { re: msg.seq });
    tryStart(session);
  });

  // ---- Lockstep-Input-Relay (ROOM_MSG-Kinds, Muster GN_INPUT/GN_HASH) -------

  function frameActionsOk(actions) {
    if (!Array.isArray(actions) || actions.length > MAX_ACTIONS_PER_FRAME) return false;
    return actions.every(
      (a) =>
        a !== null &&
        typeof a === 'object' &&
        Number.isInteger(a.t) &&
        a.t >= 0 &&
        ACTION_DOS.has(a.do) &&
        (a.type === undefined || (typeof a.type === 'string' && a.type.length <= 32)) &&
        (a.lane === undefined || Number.isInteger(a.lane)) &&
        (a.col === undefined || Number.isInteger(a.col)) &&
        (a.id === undefined || Number.isInteger(a.id))
    );
  }

  ctx.rooms.registerKindHook('GP_INPUT', (conn, room, body) => {
    const session = sessions.get(room.id);
    if (!session || !session.sides.has(conn.friendCode)) return { ok: false, code: 'BAD_ROOM' };
    if (session.phase !== 'run') return { ok: false, code: 'NOT_RUNNING' };
    const n = Number.isInteger(body.n) ? body.n : -1;
    const upTo = Number.isInteger(body.upTo) ? body.upTo : -1;
    if (n <= (session.lastFrameN.get(conn.friendCode) ?? 0) || upTo < 0) {
      return { ok: false, code: 'BAD_TURN_N' }; // Ordnung: n strikt monoton
    }
    if (!frameActionsOk(body.a ?? [])) return { ok: false, code: 'BAD_MESSAGE' };
    session.lastFrameN.set(conn.friendCode, n);
    // Kein Rejoin-Replay-Puffer (bewusst, s. Kopf) — nur relayen.
    return { ok: true };
  });

  ctx.rooms.registerKindHook('GP_HASH', (conn, room, body) => {
    const session = sessions.get(room.id);
    if (!session || !session.sides.has(conn.friendCode)) return { ok: false, code: 'BAD_ROOM' };
    if (session.phase !== 'run') return { ok: false, code: 'NOT_RUNNING' };
    const tick = Number.isInteger(body.t) ? body.t : -1;
    if (tick < 0 || typeof body.h !== 'string' || body.h.length > 64) {
      return { ok: false, code: 'BAD_MESSAGE' };
    }
    const side = session.sides.get(conn.friendCode);
    const entry = session.hashes.get(tick) ?? {};
    entry[side] = body.h;
    session.hashes.set(tick, entry);
    if (entry[SIDE_GOOBY] !== undefined && entry[SIDE_ZOMBIE] !== undefined) {
      if (entry[SIDE_GOOBY] !== entry[SIDE_ZOMBIE]) {
        // Höflicher Abbruch statt Weiterspielen auf divergenten Welten.
        session.phase = 'desync';
        broadcast(session, 'GVZ_DESYNC', { room: session.room, tick });
      }
      session.hashes.delete(tick);
    }
    return { ok: true };
  });

  // ---- Ergebnis (idempotent, pending + ACK — GoobyPal-Muster) ---------------

  // Personalisiertes Ergebnis: Sieg hängt an der SEITE des Empfängers.
  function resultFor(session, code) {
    const side = session.sides.get(code);
    const won = side === session.result.winner;
    return {
      ...session.result,
      room: session.room,
      rewardId: `gvz-${session.result.matchId}-${code}`,
      side,
      won,
      coins: won ? WINNER_COINS : LOSER_COINS,
    };
  }

  hub.on('GVZ_RESULT', (conn, msg) => {
    const session = sessions.get(typeof msg.d.room === 'string' ? msg.d.room : '');
    if (!session || !session.sides.has(conn.friendCode)) {
      return hub.sendError(conn, 'NOT_IN_ROOM', { re: msg.seq });
    }
    if (session.phase !== 'run' && session.phase !== 'done') {
      return hub.sendError(conn, 'NOT_RUNNING', { re: msg.seq });
    }
    if (!session.result) {
      const winner = msg.d.winner === SIDE_ZOMBIE ? SIDE_ZOMBIE : SIDE_GOOBY;
      const matchId = session.room.slice('gvz:'.length, 'gvz:'.length + 8);
      session.result = {
        matchId,
        winner,
        tick: Number.isInteger(msg.d.tick) ? msg.d.tick : 0,
        at: now(),
      };
      session.phase = 'done';
      const pend = pendingData(ctx);
      for (const code of session.sides.keys()) {
        const result = resultFor(session, code);
        if (!pend.pending[code]) pend.pending[code] = [];
        if (!pend.pending[code].some((e) => e.rewardId === result.rewardId)) {
          pend.pending[code].push(result);
        }
        const device = ctx.byCode.get(code);
        if (device) hub.sendToDevice(device, 'GVZ_RESULT', result);
      }
      ctx.store.flushNow('gvzmp');
    }
    // Zweiter/wiederholter Report: identische, idempotente Antwort.
    hub.send(conn, 'OK', resultFor(session, conn.friendCode), { re: msg.seq });
  });

  hub.addWelcomeProvider((conn) => {
    const pend = pendingData(ctx);
    return { gvzPending: (pend.pending[conn.friendCode] ?? []).slice() };
  });

  hub.on('GVZ_RESULT_ACK', (conn, msg) => {
    const rewardId = typeof msg.d.rewardId === 'string' ? msg.d.rewardId : '';
    const pend = pendingData(ctx);
    const list = pend.pending[conn.friendCode] ?? [];
    const idx = list.findIndex((e) => e.rewardId === rewardId);
    if (idx >= 0) {
      list.splice(idx, 1);
      if (list.length === 0) delete pend.pending[conn.friendCode];
      ctx.store.markDirty('gvzmp');
    }
    hub.send(conn, 'OK', {}, { re: msg.seq });
  });

  // ---- Rückkehr in den Raum (KEIN Snapshot — nur PEER_UP an den Partner) ----

  ctx.rooms.onJoin((conn, room) => {
    const session = sessions.get(room.id);
    if (!session) return;
    if (session.disconnected.has(conn.friendCode)) {
      session.disconnected.delete(conn.friendCode);
      const timer = session.rejoinTimers.get(conn.friendCode);
      if (timer) {
        clearTimeout(timer);
        session.rejoinTimers.delete(conn.friendCode);
      }
      broadcast(
        session,
        'GVZ_PEER_UP',
        { room: room.id, friendCode: conn.friendCode },
        conn.friendCode
      );
    }
    // Falls beide Start-Wünsche schon vor dem letzten Raum-Beitritt da waren.
    tryStart(session);
  });

  // ---- Verlassen / Verbindungsabriss ----------------------------------------

  ctx.rooms.onLeave((conn, roomId, { disconnect }) => {
    const session = sessions.get(roomId);
    if (!session) return;
    const code = conn.friendCode;

    if (session.phase === 'done' || session.phase === 'desync' || session.phase === 'aborted') {
      const room = ctx.rooms.get(roomId);
      if (!room || room.members.size === 0) cleanupSession(session);
      return;
    }

    if (!disconnect) {
      // Bewusst gegangen: kein Forfeit-Sieger — Session endet (Revanche über
      // das wieder freie Panel, s. gvz_net_session.gd leave()).
      abort(session, 'left', code);
      return;
    }

    // Abriss → Warte-Frist: Platz bleibt reserviert (Doc C §3.5-Muster),
    // aber OHNE Snapshot — kommt der Peer nicht zurück, bricht das Match ab.
    session.disconnected.add(code);
    broadcast(
      session,
      'GVZ_PEER_DOWN',
      { room: roomId, friendCode: code, waitMs: cfg.boardRejoinMs },
      code
    );
    const timer = setTimeout(() => {
      session.rejoinTimers.delete(code);
      if (!session.disconnected.has(code)) return;
      abort(session, 'timeout', code);
    }, cfg.boardRejoinMs);
    if (timer.unref) timer.unref();
    session.rejoinTimers.set(code, timer);
  });

  // ---- REST: offene Ergebnisse (Debug/Panel) --------------------------------

  ctx.app.get('/api/gvz/pending', (req, res) => {
    const auth = restAuth(ctx, req);
    if (!auth) return res.status(401).json({ ok: false, code: 'AUTH_FAIL' });
    const pend = pendingData(ctx);
    res.json({ ok: true, pending: pend.pending[auth.player.friendCode] ?? [] });
  });

  // Fürs Panel-Dashboard / Tests.
  ctx.gvzSessions = sessions;
}
