// GOB-NOM-Netz-Coop (W15, Doc C §3.8 / Doc G §5.4 M2): 2-Spieler-Lockstep-
// Relay auf eigenen `gobnom:`-Räumen (max 2, nur Freunde) — Kopiervorlage
// waren die mg:-Räume (ranchmp.js) + das Turn-Relay (boardgames.js).
//
// Autoritätsmodell: Die Sim (GobnomLogic, Godot) ist deterministisch — der
// Server kennt KEINE Spielregeln. Er ist autoritativ für Mitgliedschaft,
// Seiten (Einladender = 'a', Annehmender = 'b'), Level-Handshake (beide
// bestätigen dasselbe Level), Start-Seed, Input-Frame-Ordnung (n monoton),
// Rejoin-Replay (kompletter Frame-Puffer, 120-s-Fenster wie Battleship)
// und das idempotente Ergebnis (pending + ACK, GoobyPal-Muster).
//
// Desync-Wächter: Clients melden alle `hashEveryTicks` Ticks ihren
// State-Hash (GN_HASH). Der Server vergleicht beide Seiten pro Tick und
// bricht bei Abweichung höflich ab (GOBNOM_DESYNC an beide) — zusätzlich
// wird der Hash relayt, damit die Clients selbst vergleichen können.
//
// PROTOKOLL-VERTRAG v1 (GvZ-PvP nutzt dieses Muster später als Vorlage):
//   Hub-Events: GOBNOM_INVITE/_DECLINE/_ACCEPT → GOBNOM_READY,
//     GOBNOM_LEVEL → GOBNOM_LEVEL_STATE / GOBNOM_START,
//     GOBNOM_RESULT (+_ACK) → GOBNOM_RESULT-Push, GOBNOM_RESUME → _SNAPSHOT.
//   ROOM_MSG-Kinds: GN_INPUT {n, upTo, a:[{t,do,id,v?}]}, GN_HASH {t,h},
//     GN_CURSOR {x,y} (12 Hz, flüchtig).
//   Pushes: GOBNOM_PEER_DOWN/_UP, GOBNOM_DESYNC, GOBNOM_ABORTED.

import crypto from 'node:crypto';
import { LIMITS } from './ratelimit.js';
import { areFriends } from './friends.js';
import { restAuth, FRIEND_CODE_RE } from './auth.js';

const INVITE_TTL_MS = 30_000;
const LEVEL_MIN = 1;
const LEVEL_MAX = 10; // 10 Coop-Level (gobnom_levels.json, Doc G §5.4)
// Lockstep-Parameter — Teil des Start-Payloads, damit beide Clients (und
// spätere Konsumenten des Vertrags) dieselben Werte fahren.
const INPUT_DELAY_TICKS = 4; // Standard-Lockstep-Fenster (3–5 Ticks)
const HASH_EVERY_TICKS = 60; // Desync-Check 1×/Sekunde (60-Hz-Sim)
// Missbrauchs-/Speicher-Deckel für den Rejoin-Puffer: 10-Hz-Fences über
// ~30 Minuten. Überlauf bricht die Session ab (kein stiller Datenverlust).
const MAX_FRAMES_PER_SIDE = 18_000;
const MAX_ACTIONS_PER_FRAME = 16;
const ACTION_DOS = new Set(['cut', 'pop', 'puff', 'fan', 'slide']);

function pendingData(ctx) {
  // Ergebnis-Zustellung: friendCode -> [result] (idempotent über rewardId).
  return ctx.store.collection('gobnommp', { pending: {} });
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
    const room = `gobnom:${crypto.randomUUID()}`;
    const session = {
      room,
      phase: 'lobby', // lobby → run → done | desync | aborted
      sides: new Map([
        [hostCode, 'a'],
        [guestCode, 'b'],
      ]),
      votes: new Map(), // code -> level
      level: 0,
      seed: 0,
      startedAt: 0,
      frames: { a: [], b: [] }, // Rejoin-Replay-Puffer (GN_INPUT-Bodies)
      lastFrameN: new Map(), // code -> letzte Frame-Nr (Ordnung!)
      hashes: new Map(), // tick -> { a?, b? }
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

  function otherCode(session, code) {
    for (const member of session.sides.keys()) {
      if (member !== code) return member;
    }
    return '';
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
      rejoinMs: cfg.boardRejoinMs,
    };
  }

  function abort(session, reason, byCode = '') {
    if (session.phase === 'done') {
      cleanupSession(session);
      return;
    }
    session.phase = 'aborted';
    broadcast(session, 'GOBNOM_ABORTED', { room: session.room, reason, by: byCode }, byCode);
    cleanupSession(session);
  }

  // Nur die beiden Session-Mitglieder dürfen in ihren Raum (auch Rejoin).
  ctx.rooms.registerJoinGuard('gobnom', (conn, roomId) => {
    const session = sessions.get(roomId);
    if (!session || !session.sides.has(conn.friendCode)) return { ok: false, code: 'BAD_ROOM' };
    return { ok: true };
  });

  // ---- Einladung (Muster BOARD_INVITE — nur Freunde, TTL, online) ----------

  hub.on('GOBNOM_INVITE', (conn, msg) => {
    if (!ctx.buckets.take(`gnominv:${conn.deviceId}`, LIMITS.rmpInvite)) {
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
    hub.sendToDevice(targetDevice, 'GOBNOM_INVITED', {
      from: conn.friendCode,
      name: conn.name,
      goobyName: conn.goobyName,
      expiresInMs: INVITE_TTL_MS,
    });
  });

  hub.on('GOBNOM_DECLINE', (conn, msg) => {
    const from = typeof msg.d.from === 'string' ? msg.d.from.toUpperCase() : '';
    if (invites.delete(`${from}->${conn.friendCode}`)) {
      const fromDevice = ctx.byCode.get(from);
      if (fromDevice) hub.sendToDevice(fromDevice, 'GOBNOM_DECLINED', { from: conn.friendCode });
    }
    hub.send(conn, 'OK', {}, { re: msg.seq });
  });

  hub.on('GOBNOM_ACCEPT', (conn, msg) => {
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
    hub.send(conn, 'GOBNOM_READY', ready, { re: msg.seq });
    hub.sendToDevice(inviterDevice, 'GOBNOM_READY', ready);
  });

  // ---- Level-Handshake: BEIDE bestätigen dasselbe Level → Start-Seed -------

  function tryStart(session) {
    if (session.phase !== 'lobby' || session.votes.size < 2) return;
    const levels = [...session.votes.values()];
    if (levels[0] !== levels[1]) return;
    const room = ctx.rooms.get(session.room);
    if (!room) return;
    for (const code of session.sides.keys()) {
      const device = ctx.byCode.get(code);
      if (!device || !room.members.has(device)) return; // beide müssen im Raum sein
    }
    session.phase = 'run';
    session.level = levels[0];
    session.seed = crypto.randomBytes(4).readUInt32BE(0) & 0x7fffffff;
    session.startedAt = now();
    broadcast(session, 'GOBNOM_START', {
      room: session.room,
      level: session.level,
      seed: session.seed,
      inputDelay: INPUT_DELAY_TICKS,
      hashEveryTicks: HASH_EVERY_TICKS,
      players: playersOf(session),
      serverNow: session.startedAt,
    });
  }

  hub.on('GOBNOM_LEVEL', (conn, msg) => {
    const session = sessions.get(typeof msg.d.room === 'string' ? msg.d.room : '');
    if (!session || !session.sides.has(conn.friendCode)) {
      return hub.sendError(conn, 'NOT_IN_ROOM', { re: msg.seq });
    }
    if (session.phase !== 'lobby') return hub.sendError(conn, 'GAME_RUNNING', { re: msg.seq });
    const level = Number.isInteger(msg.d.level) ? msg.d.level : -1;
    if (level < LEVEL_MIN || level > LEVEL_MAX) {
      return hub.sendError(conn, 'BAD_LEVEL', { re: msg.seq });
    }
    session.votes.set(conn.friendCode, level);
    const votes = Object.fromEntries(session.votes);
    hub.send(conn, 'OK', { level, votes }, { re: msg.seq });
    broadcast(session, 'GOBNOM_LEVEL_STATE', { room: session.room, votes }, conn.friendCode);
    tryStart(session);
  });

  // ---- Lockstep-Input-Relay (ROOM_MSG-Kinds, Muster boardgames.js) ---------

  function frameActionsOk(actions) {
    if (!Array.isArray(actions) || actions.length > MAX_ACTIONS_PER_FRAME) return false;
    return actions.every(
      (a) =>
        a !== null &&
        typeof a === 'object' &&
        Number.isInteger(a.t) &&
        a.t >= 0 &&
        ACTION_DOS.has(a.do) &&
        Number.isInteger(a.id) &&
        (a.v === undefined || Number.isFinite(a.v))
    );
  }

  ctx.rooms.registerKindHook('GN_INPUT', (conn, room, body) => {
    const session = sessions.get(room.id);
    if (!session || !session.sides.has(conn.friendCode)) return { ok: false, code: 'BAD_ROOM' };
    if (session.phase !== 'run') return { ok: false, code: 'NOT_RUNNING' };
    const n = Number.isInteger(body.n) ? body.n : -1;
    const upTo = Number.isInteger(body.upTo) ? body.upTo : -1;
    if (n <= (session.lastFrameN.get(conn.friendCode) ?? 0) || upTo < 0) {
      return { ok: false, code: 'BAD_TURN_N' }; // Ordnung: n strikt monoton
    }
    if (!frameActionsOk(body.a ?? [])) return { ok: false, code: 'BAD_MESSAGE' };
    const side = session.sides.get(conn.friendCode);
    const buffer = session.frames[side];
    if (buffer.length >= MAX_FRAMES_PER_SIDE) {
      abort(session, 'overflow');
      return { ok: false, code: 'PAYLOAD_TOO_LARGE' };
    }
    session.lastFrameN.set(conn.friendCode, n);
    buffer.push({ n, upTo, a: body.a ?? [] });
    return { ok: true };
  });

  ctx.rooms.registerKindHook('GN_HASH', (conn, room, body) => {
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
    if (entry.a !== undefined && entry.b !== undefined) {
      if (entry.a !== entry.b) {
        // Höflicher Abbruch statt Weiterspielen auf divergenten Welten.
        session.phase = 'desync';
        broadcast(session, 'GOBNOM_DESYNC', { room: session.room, tick });
      }
      session.hashes.delete(tick);
    }
    return { ok: true };
  });

  // Partner-Cursor: flüchtig, 12 Hz, still verwerfen (Muster MG_POSE/POS).
  ctx.rooms.registerKindHook('GN_CURSOR', (conn, room, body) => {
    const session = sessions.get(room.id);
    if (!session || !session.sides.has(conn.friendCode)) return { ok: false, code: 'BAD_ROOM' };
    if (!ctx.buckets.take(`gncur:${conn.deviceId}:${room.id}`, LIMITS.mgPose)) {
      return { ok: true, suppressRelay: true };
    }
    if (!Number.isFinite(body.x) || !Number.isFinite(body.y)) {
      return { ok: true, suppressRelay: true };
    }
    return { ok: true };
  });

  // ---- Ergebnis (idempotent, pending + ACK — GoobyPal-Muster) ---------------

  hub.on('GOBNOM_RESULT', (conn, msg) => {
    const session = sessions.get(typeof msg.d.room === 'string' ? msg.d.room : '');
    if (!session || !session.sides.has(conn.friendCode)) {
      return hub.sendError(conn, 'NOT_IN_ROOM', { re: msg.seq });
    }
    if (session.phase !== 'run' && session.phase !== 'done') {
      return hub.sendError(conn, 'NOT_RUNNING', { re: msg.seq });
    }
    if (!session.result) {
      const outcome = msg.d.outcome === 'won' ? 'won' : 'lost';
      const jars = Number.isInteger(msg.d.jars) ? Math.min(3, Math.max(0, msg.d.jars)) : 0;
      const matchId = session.room.slice('gobnom:'.length, 'gobnom:'.length + 8);
      session.result = {
        matchId,
        level: session.level,
        outcome,
        jars,
        stars: outcome === 'won' ? jars : 0,
        tick: Number.isInteger(msg.d.tick) ? msg.d.tick : 0,
        at: now(),
      };
      session.phase = 'done';
      const pend = pendingData(ctx);
      for (const code of session.sides.keys()) {
        const result = { ...session.result, rewardId: `gnom-${matchId}-${code}`, room: session.room };
        if (!pend.pending[code]) pend.pending[code] = [];
        if (!pend.pending[code].some((e) => e.rewardId === result.rewardId)) {
          pend.pending[code].push(result);
        }
        const device = ctx.byCode.get(code);
        if (device) hub.sendToDevice(device, 'GOBNOM_RESULT', result);
      }
      ctx.store.flushNow('gobnommp');
    }
    // Zweiter/wiederholter Report: identische, idempotente Antwort.
    hub.send(
      conn,
      'OK',
      { ...session.result, rewardId: `gnom-${session.result.matchId}-${conn.friendCode}` },
      { re: msg.seq }
    );
  });

  hub.addWelcomeProvider((conn) => {
    const pend = pendingData(ctx);
    return { gnomPending: (pend.pending[conn.friendCode] ?? []).slice() };
  });

  hub.on('GOBNOM_RESULT_ACK', (conn, msg) => {
    const rewardId = typeof msg.d.rewardId === 'string' ? msg.d.rewardId : '';
    const pend = pendingData(ctx);
    const list = pend.pending[conn.friendCode] ?? [];
    const idx = list.findIndex((e) => e.rewardId === rewardId);
    if (idx >= 0) {
      list.splice(idx, 1);
      if (list.length === 0) delete pend.pending[conn.friendCode];
      ctx.store.markDirty('gobnommp');
    }
    hub.send(conn, 'OK', {}, { re: msg.seq });
  });

  // ---- Rejoin / Snapshot (120-s-Fenster wie Battleship) ---------------------

  function snapshot(session) {
    return {
      room: session.room,
      phase: session.phase,
      level: session.level,
      seed: session.seed,
      inputDelay: INPUT_DELAY_TICKS,
      hashEveryTicks: HASH_EVERY_TICKS,
      players: playersOf(session),
      votes: Object.fromEntries(session.votes),
      // Kompletter Frame-Puffer beider Seiten: der Rückkehrer replayt
      // deterministisch aus Seed + Input-Strom (Solver-Beweis, README M2).
      frames: { a: session.frames.a.slice(), b: session.frames.b.slice() },
      result: session.result,
      serverNow: now(),
    };
  }

  hub.on('GOBNOM_RESUME', (conn, msg) => {
    const session = sessions.get(typeof msg.d.room === 'string' ? msg.d.room : '');
    if (!session || !session.sides.has(conn.friendCode)) {
      return hub.sendError(conn, 'NOT_FOUND', { re: msg.seq });
    }
    hub.send(conn, 'GOBNOM_SNAPSHOT', snapshot(session), { re: msg.seq });
  });

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
      hub.send(conn, 'GOBNOM_SNAPSHOT', snapshot(session));
      broadcast(
        session,
        'GOBNOM_PEER_UP',
        { room: room.id, friendCode: conn.friendCode },
        conn.friendCode
      );
    }
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
      // Bewusst gegangen: Coop kennt keinen Forfeit-Sieger — Session endet.
      abort(session, 'left', code);
      return;
    }

    // Abriss → Rejoin-Fenster: Platz bleibt reserviert (Doc C §3.5-Muster).
    session.disconnected.add(code);
    broadcast(
      session,
      'GOBNOM_PEER_DOWN',
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

  ctx.app.get('/api/gobnom/pending', (req, res) => {
    const auth = restAuth(ctx, req);
    if (!auth) return res.status(401).json({ ok: false, code: 'AUTH_FAIL' });
    const pend = pendingData(ctx);
    res.json({ ok: true, pending: pend.pending[auth.player.friendCode] ?? [] });
  });

  // Fürs Panel-Dashboard / Tests.
  ctx.gobnomSessions = sessions;
}
