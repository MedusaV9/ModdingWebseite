// Ranch-Multiplayer (RW-6, nach RANCH-DLC-IDEAS-4 §2): Besuch, gemeinsamer
// Ausritt und instanzierte 2–4-Spieler-Minispiele (Rennen/Fangen/Parcours)
// auf den generischen mg:-Räumen — plus REST für Ranch-Metadaten, Freundes-
// Bestenlisten und Geister-Ablage (Größenlimit + Prune).
//
// Autoritätsmodell (Doc §2.2, hybrid): Der Client simuliert sein Pferd,
// der Server ist autoritativ für Mitgliedschaft, Seed/Startzeit, Checkpoint-
// Reihenfolge, Zielzeit (Serveruhr!), Tag-Übergabe und Ergebnis/Reward.
// Plausibilitätsprüfung ist Crash-/Fehlerabwehr, KEIN Anti-Cheat: verdächtige
// Läufe werden `unranked`, die Freundesrunde läuft weiter.
//
// Zustellung: Ergebnisse folgen dem GoobyPal-Muster (pending + ACK,
// idempotente rewardId) — ein Crash/Reconnect verliert nie ein Resultat.

import crypto from 'node:crypto';
import express from 'express';
import { LIMITS } from './ratelimit.js';
import { monthKey } from './config.js';
import { areFriends, friendCodesOf } from './friends.js';
import { restAuth, FRIEND_CODE_RE } from './auth.js';

export const MODES = new Set(['besuch', 'ausritt', 'rennen', 'fangen', 'parcours']);
const MATCH_MODES = new Set(['rennen', 'fangen', 'parcours']);
const CAP_BY_MODE = { besuch: 2, ausritt: 4, rennen: 4, fangen: 4, parcours: 4 };

const INVITE_TTL_MS = 30_000;
// Max. plausible Bewegung: 16 m/s Galopp + 30 % Toleranz (Doc §2.2).
const MAX_SPEED = 16 * 1.3;
const TAG_IMMUNITY_MS = 2_000;
const MAX_GHOST_SAMPLES = 1_500;
const MAX_ZEIT_MS = 30 * 60_000;

// Kurs-Katalog — MUSS mit GOOBY-GODOT/scripts/ranch/mp/rmp_kurse.gd synchron
// bleiben (Client sendet kursHash in MG_READY; Mismatch → unranked, spielbar).
export const KURSE = {
  grasbahn: {
    mode: 'rennen',
    // Ovale Grasbahn im Weidetal (Zone-Rect [-660,-120,380,420]).
    checkpoints: [
      [-330, 60],
      [-356, 102],
      [-420, 120],
      [-484, 102],
      [-510, 60],
      [-484, 18],
      [-420, 0],
      [-356, 18],
    ],
    radius: 14,
    minSegmentMs: 900,
  },
  hof_parcours: {
    mode: 'parcours',
    // Slalom-Tore am Reitplatz des Hofs (Zone-Rect [-240,-190,480,380]).
    checkpoints: [
      [60, -40],
      [90, 0],
      [60, 40],
      [90, 80],
      [60, 120],
      [20, 150],
      [-20, 120],
      [-40, 80],
    ],
    radius: 10,
    minSegmentMs: 700,
    strafeMs: 2_000,
  },
  weide_fangen: {
    mode: 'fangen',
    checkpoints: [],
    arena: [-380, 90, 70],
    tagRadius: 3.0,
    minSegmentMs: 0,
  },
};
const DEFAULT_KURS = { rennen: 'grasbahn', parcours: 'hof_parcours', fangen: 'weide_fangen' };

export function kursHash(kursId) {
  const kurs = KURSE[kursId];
  if (!kurs) return '';
  return `${kursId}:v1:${kurs.checkpoints.length}`;
}

// Asynchrone RW-5-Wertungen (Freundes-Bestenlisten für ALLE Wettbewerbe von
// RW-5, RANCH-DLC-IDEAS-3 Kap. 5): richtung 'ab' = kleinerer Wert gewinnt
// (Zeit in ms), 'auf' = größerer (Punkte). MUSS mit comp_balance.json
// (disziplinen[].wertung) synchron bleiben — Test sichert das.
export const RW5_WERTUNGEN = {
  rw5_springen: 'auf',
  rw5_dressur: 'auf',
  rw5_gelaende: 'ab',
  rw5_rennen: 'ab',
  rw5_trail: 'auf',
  rw5_schau: 'auf',
  rw5_tonnen: 'ab',
  rw5_zeit: 'ab',
};

// Wertungsrichtung eines Bestenlisten-Schlüssels ('' = unbekannt).
export function richtungFuer(kursId) {
  if (KURSE[kursId] && KURSE[kursId].mode !== 'fangen') return 'ab';
  return RW5_WERTUNGEN[kursId] ?? '';
}

function scoresData(ctx) {
  // byKurs: { kursId: { friendCode: {zeitMs, at} } }
  return ctx.store.collection('ranchscores', { byKurs: {} });
}

function ghostsData(ctx) {
  // byKurs: { kursId: { friendCode: {zeitMs, sizeBytes, at, blob} } }
  return ctx.store.collection('ranchghosts', { byKurs: {} });
}

function ranchesData(ctx) {
  // friendCode -> {rev, sizeBytes, uploadedAt, blob}
  return ctx.store.collection('ranches', { ranches: {} });
}

function pendingData(ctx) {
  // Ergebnis-Zustellung: friendCode -> [result]
  return ctx.store.collection('ranchmp', { pending: {} });
}

export function register(ctx) {
  const { hub, cfg } = ctx;
  scoresData(ctx);
  ghostsData(ctx);
  ranchesData(ctx);
  pendingData(ctx);

  // roomId -> Session {room, mode, kurs, host, codes:Set, players:[], match?}
  const sessions = new Map();
  // "<from>-><target>" -> {mode, kurs, at, room|null}
  const invites = new Map();

  const now = () => ctx.clock.now();
  const playerInfo = (code) => {
    const device = ctx.byCode.get(code);
    const player = device ? ctx.players[device] : null;
    return { friendCode: code, name: player?.name ?? '?', goobyName: player?.goobyName ?? 'Gooby' };
  };

  function broadcast(session, t, d, exceptCode = '') {
    for (const code of session.codes) {
      if (code === exceptCode) continue;
      const device = ctx.byCode.get(code);
      if (device) hub.sendToDevice(device, t, d);
    }
  }

  function cleanupSession(session) {
    const match = session.match;
    if (match) {
      for (const timer of match.rejoinTimers.values()) clearTimeout(timer);
      match.rejoinTimers.clear();
      if (match.endTimer) clearTimeout(match.endTimer);
    }
    sessions.delete(session.room);
    ctx.rooms.destroy(session.room);
  }

  function newMatch() {
    return {
      phase: 'lobby', // lobby → countdown → run → done
      ready: new Set(),
      unranked: new Set(),
      dnf: new Set(),
      seed: 0,
      startAt: 0,
      endsAt: 0,
      stateVersion: 0,
      next: new Map(), // code -> nächster Checkpoint-Index
      lastCpAt: new Map(),
      strafenMs: new Map(),
      strafGates: new Map(), // code -> Set(gate) — max 1 Strafe je Tor
      finish: new Map(), // code -> {timeMs, rank} (Einfüge-Reihenfolge = Platz)
      tag: { it: '', immunityUntil: 0, lastSwitchAt: 0, itMs: new Map() },
      disconnected: new Set(),
      rejoinTimers: new Map(),
      endTimer: null,
      rematch: new Set(),
    };
  }

  function createSession(mode, kurs, hostCode, memberCodes) {
    const room = `mg:${crypto.randomUUID()}`;
    const session = {
      room,
      mode,
      kurs,
      host: hostCode,
      codes: new Set(memberCodes),
      createdAt: now(),
      poses: new Map(), // code -> {seq, p, at} (auch Ausritt/Besuch)
      match: MATCH_MODES.has(mode) ? newMatch() : null,
    };
    ctx.rooms.ensure(room, { maxMembers: CAP_BY_MODE[mode], mode });
    sessions.set(room, session);
    return session;
  }

  function readyPayload(session, extra = {}) {
    return {
      room: session.room,
      mode: session.mode,
      kurs: session.kurs,
      host: session.host,
      players: [...session.codes].map(playerInfo),
      minSpieler: MATCH_MODES.has(session.mode) ? 2 : 1,
      maxSpieler: CAP_BY_MODE[session.mode],
      ...extra,
    };
  }

  // Nur eingeladene/zugelassene Codes dürfen in ihren mg:-Room (auch Rejoin).
  ctx.rooms.registerJoinGuard('mg', (conn, roomId) => {
    const session = sessions.get(roomId);
    if (!session || !session.codes.has(conn.friendCode)) return { ok: false, code: 'BAD_ROOM' };
    return { ok: true };
  });

  // ---- Einladungen -------------------------------------------------------

  hub.on('RANCH_INVITE', (conn, msg) => {
    if (!ctx.buckets.take(`rmpinv:${conn.deviceId}`, LIMITS.rmpInvite)) {
      return hub.sendError(conn, 'RATE_LIMIT', { re: msg.seq });
    }
    const mode = typeof msg.d.mode === 'string' ? msg.d.mode : '';
    if (!MODES.has(mode)) return hub.sendError(conn, 'BAD_MODE', { re: msg.seq });
    let kurs = typeof msg.d.kurs === 'string' ? msg.d.kurs : '';
    if (MATCH_MODES.has(mode)) {
      if (!kurs) kurs = DEFAULT_KURS[mode];
      if (!KURSE[kurs] || KURSE[kurs].mode !== mode) {
        return hub.sendError(conn, 'BAD_KURS', { re: msg.seq });
      }
    } else {
      kurs = '';
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
    // Nachladen in eine offene Gruppe (Ausritt jederzeit, Matches nur Lobby).
    let room = null;
    for (const session of sessions.values()) {
      if (!session.codes.has(conn.friendCode) || session.mode !== mode) continue;
      if (session.match && session.match.phase !== 'lobby') continue;
      if (session.codes.size >= CAP_BY_MODE[mode]) {
        return hub.sendError(conn, 'ROOM_FULL', { re: msg.seq });
      }
      room = session.room;
      kurs = session.kurs;
      break;
    }
    invites.set(`${conn.friendCode}->${target}`, { mode, kurs, at: now(), room });
    hub.send(conn, 'OK', {}, { re: msg.seq });
    hub.sendToDevice(targetDevice, 'RANCH_INVITED', {
      from: conn.friendCode,
      name: conn.name,
      goobyName: conn.goobyName,
      mode,
      kurs,
      expiresInMs: INVITE_TTL_MS,
    });
  });

  hub.on('RANCH_DECLINE', (conn, msg) => {
    const from = typeof msg.d.from === 'string' ? msg.d.from.toUpperCase() : '';
    if (invites.delete(`${from}->${conn.friendCode}`)) {
      const fromDevice = ctx.byCode.get(from);
      if (fromDevice) hub.sendToDevice(fromDevice, 'RANCH_DECLINED', { from: conn.friendCode });
    }
    hub.send(conn, 'OK', {}, { re: msg.seq });
  });

  hub.on('RANCH_ACCEPT', (conn, msg) => {
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

    let session = invite.room ? sessions.get(invite.room) : null;
    if (session) {
      if (session.codes.size >= CAP_BY_MODE[session.mode] || (session.match && session.match.phase !== 'lobby')) {
        return hub.sendError(conn, 'ROOM_FULL', { re: msg.seq });
      }
      session.codes.add(conn.friendCode);
    } else {
      session = createSession(invite.mode, invite.kurs, from, [from, conn.friendCode]);
    }
    const rev =
      session.mode === 'besuch' ? (ranchesData(ctx).ranches[session.host]?.rev ?? 0) : undefined;
    const ready = readyPayload(session, rev === undefined ? {} : { rev });
    hub.send(conn, 'RANCH_READY', ready, { re: msg.seq });
    broadcast(session, 'RANCH_READY', ready, conn.friendCode);
  });

  // ---- Match-Lobby & Start ----------------------------------------------

  function lobbyState(session) {
    const match = session.match;
    match.stateVersion += 1;
    return {
      room: session.room,
      players: [...session.codes].map(playerInfo),
      ready: [...match.ready],
      stateVersion: match.stateVersion,
    };
  }

  function tryStart(session) {
    const match = session.match;
    const room = ctx.rooms.get(session.room);
    if (!room || match.phase !== 'lobby') return;
    const present = [...session.codes].filter((code) => {
      const device = ctx.byCode.get(code);
      return device && room.members.has(device);
    });
    if (present.length < 2) return;
    if (!present.every((code) => match.ready.has(code))) return;
    match.phase = 'countdown';
    match.seed = crypto.randomBytes(4).readUInt32BE(0);
    match.startAt = now() + cfg.rmpCountdownMs;
    // Wer beim Start nicht im Raum ist, spielt nicht mit (Lobby-No-Show).
    session.codes = new Set(present);
    const start = {
      room: session.room,
      mode: session.mode,
      kurs: session.kurs,
      seed: match.seed,
      startAt: match.startAt,
      serverNow: now(),
      players: present.map(playerInfo),
    };
    if (session.mode === 'fangen') {
      match.endsAt = match.startAt + cfg.rmpFangenMs;
      match.tag.it = present[match.seed % present.length];
      match.tag.lastSwitchAt = match.startAt;
      start.endsAt = match.endsAt;
      start.it = match.tag.it;
      match.endTimer = setTimeout(() => finalize(session), match.endsAt - now());
      if (match.endTimer.unref) match.endTimer.unref();
    }
    broadcast(session, 'MG_START', start);
  }

  hub.on('MG_READY', (conn, msg) => {
    const session = sessions.get(typeof msg.d.room === 'string' ? msg.d.room : '');
    if (!session || !session.match || !session.codes.has(conn.friendCode)) {
      return hub.sendError(conn, 'NOT_IN_ROOM', { re: msg.seq });
    }
    const match = session.match;
    if (match.phase !== 'lobby') return hub.sendError(conn, 'GAME_RUNNING', { re: msg.seq });
    const clientHash = typeof msg.d.kursHash === 'string' ? msg.d.kursHash : '';
    if (clientHash !== kursHash(session.kurs)) match.unranked.add(conn.friendCode);
    if (msg.d.devSession === true) match.unranked.add(conn.friendCode);
    match.ready.add(conn.friendCode);
    hub.send(conn, 'OK', { ready: [...match.ready] }, { re: msg.seq });
    broadcast(session, 'MG_LOBBY', lobbyState(session));
    tryStart(session);
  });

  function maybeRun(match) {
    if (match.phase === 'countdown' && now() >= match.startAt) match.phase = 'run';
  }

  // ---- Pose-Relay (10 Hz, eigener Kanal — Doc §2.3/§2.4) ------------------

  hub.on('MG_POSE', (conn, msg) => {
    const roomId = typeof msg.d.room === 'string' ? msg.d.room : '';
    const session = sessions.get(roomId);
    const room = ctx.rooms.get(roomId);
    if (!session || !room || !room.members.has(conn.deviceId)) return; // still verwerfen
    if (!ctx.buckets.take(`mgpose:${conn.deviceId}:${roomId}`, LIMITS.mgPose)) return;
    const p = msg.d.p;
    if (!Array.isArray(p) || p.length < 3 || !p.every((v) => Number.isFinite(v))) return;
    const poseSeq = Number.isInteger(msg.d.poseSeq) ? msg.d.poseSeq : 0;
    const last = session.poses.get(conn.friendCode);
    if (last && poseSeq <= last.seq) return; // alt/dupliziert → wertlos
    const at = now();
    if (last && session.match && session.match.phase === 'run') {
      const dt = Math.max(50, at - last.at) / 1000;
      const dist = Math.hypot(p[0] - last.p[0], p[2] - last.p[2]);
      if (dist / dt > MAX_SPEED) session.match.unranked.add(conn.friendCode);
    }
    session.poses.set(conn.friendCode, { seq: poseSeq, p: [p[0], p[1], p[2]], at });
    const out = {
      room: roomId,
      from: conn.friendCode,
      p,
      yaw: Number.isFinite(msg.d.yaw) ? msg.d.yaw : 0,
      speed: Number.isFinite(msg.d.speed) ? msg.d.speed : 0,
      gait: Number.isInteger(msg.d.gait) ? msg.d.gait : 0,
      anim: typeof msg.d.anim === 'string' ? msg.d.anim.slice(0, 24) : 'idle',
      jump: msg.d.jump === true,
      poseSeq,
    };
    for (const memberId of room.members) {
      if (memberId === conn.deviceId) continue;
      hub.sendToDevice(memberId, 'MG_PEER_POSE', out);
    }
  });

  // ---- Match-Ereignisse (server-validiert, Doc §2.2) ----------------------

  function statePush(session, d) {
    const match = session.match;
    match.stateVersion += 1;
    broadcast(session, 'MG_STATE', { room: session.room, stateVersion: match.stateVersion, ...d });
  }

  function activeUnfinished(session) {
    const match = session.match;
    return [...session.codes].filter(
      (code) => !match.finish.has(code) && !match.dnf.has(code) && !match.disconnected.has(code)
    );
  }

  function maybeFinish(session) {
    const match = session.match;
    if (match.phase !== 'run' || session.mode === 'fangen') return;
    // Fertig, sobald niemand Aktives mehr unterwegs ist. Getrennte Spieler
    // halten das Match bis zum Ablauf ihres Rejoin-Fensters offen (fair).
    if (activeUnfinished(session).length > 0) return;
    if (match.disconnected.size > 0) return;
    finalize(session);
  }

  hub.on('MG_EVENT', (conn, msg) => {
    const session = sessions.get(typeof msg.d.room === 'string' ? msg.d.room : '');
    if (!session || !session.match || !session.codes.has(conn.friendCode)) {
      return hub.sendError(conn, 'NOT_IN_ROOM', { re: msg.seq });
    }
    if (!ctx.buckets.take(`mgevent:${conn.deviceId}:${session.room}`, LIMITS.mgEvent)) {
      return hub.sendError(conn, 'RATE_LIMIT', { re: msg.seq });
    }
    const match = session.match;
    maybeRun(match);
    if (match.phase !== 'run') return hub.sendError(conn, 'NOT_RUNNING', { re: msg.seq });
    const code = conn.friendCode;
    if (match.finish.has(code) || match.dnf.has(code)) {
      return hub.sendError(conn, 'ALREADY_DONE', { re: msg.seq });
    }
    const kind = typeof msg.d.kind === 'string' ? msg.d.kind : '';
    const kurs = KURSE[session.kurs];
    const at = now();

    if (kind === 'checkpoint' && session.mode !== 'fangen') {
      const idx = Number.isInteger(msg.d.idx) ? msg.d.idx : -1;
      const expected = match.next.get(code) ?? 0;
      if (idx !== expected || idx >= kurs.checkpoints.length) {
        return hub.sendError(conn, 'BAD_CHECKPOINT', { re: msg.seq });
      }
      // Mindestsegmentzeit + Pose-Nähe: Verstoß macht den Lauf unranked,
      // trennt aber nicht die Freundesrunde (Doc §2.2).
      const lastAt = match.lastCpAt.get(code) ?? match.startAt;
      if (at - lastAt < kurs.minSegmentMs) match.unranked.add(code);
      const pose = session.poses.get(code);
      if (pose) {
        const [cx, cz] = kurs.checkpoints[idx];
        if (Math.hypot(pose.p[0] - cx, pose.p[2] - cz) > kurs.radius * 2.5) {
          match.unranked.add(code);
        }
      }
      match.next.set(code, idx + 1);
      match.lastCpAt.set(code, at);
      hub.send(conn, 'OK', { next: idx + 1 }, { re: msg.seq });
      statePush(session, { progress: { [code]: idx + 1 } });
      return;
    }

    if (kind === 'strafe' && session.mode === 'parcours') {
      const gate = Number.isInteger(msg.d.gate) ? msg.d.gate : -1;
      if (gate < 0 || gate >= kurs.checkpoints.length) {
        return hub.sendError(conn, 'BAD_CHECKPOINT', { re: msg.seq });
      }
      let gates = match.strafGates.get(code);
      if (!gates) {
        gates = new Set();
        match.strafGates.set(code, gates);
      }
      if (!gates.has(gate)) {
        gates.add(gate);
        match.strafenMs.set(code, (match.strafenMs.get(code) ?? 0) + kurs.strafeMs);
      }
      hub.send(conn, 'OK', { strafenMs: match.strafenMs.get(code) }, { re: msg.seq });
      statePush(session, { strafe: { friendCode: code, gate, strafenMs: match.strafenMs.get(code) } });
      return;
    }

    if (kind === 'finish' && session.mode !== 'fangen') {
      if ((match.next.get(code) ?? 0) < kurs.checkpoints.length) {
        return hub.sendError(conn, 'BAD_CHECKPOINT', { re: msg.seq });
      }
      // Zielzeit ist SERVERZEIT (finishAt − startAt), nie die Client-Stoppuhr.
      const timeMs = at - match.startAt + (match.strafenMs.get(code) ?? 0);
      const rank = match.finish.size + 1;
      match.finish.set(code, { timeMs, rank });
      hub.send(conn, 'OK', { timeMs, rank }, { re: msg.seq });
      statePush(session, { finished: { friendCode: code, timeMs, rank } });
      maybeFinish(session);
      return;
    }

    if (kind === 'tag' && session.mode === 'fangen') {
      const target = typeof msg.d.target === 'string' ? msg.d.target.toUpperCase() : '';
      if (match.tag.it !== code) return hub.sendError(conn, 'NOT_IT', { re: msg.seq });
      if (at < match.tag.immunityUntil) return hub.sendError(conn, 'TAG_IMMUN', { re: msg.seq });
      if (!session.codes.has(target) || match.disconnected.has(target) || match.dnf.has(target)) {
        return hub.sendError(conn, 'NOT_FOUND', { re: msg.seq });
      }
      const a = session.poses.get(code);
      const b = session.poses.get(target);
      // Distanz mit letzter Pose + Lag-Toleranz 1 m (Doc §2.7).
      if (!a || !b || Math.hypot(a.p[0] - b.p[0], a.p[2] - b.p[2]) > kurs.tagRadius + 1.0) {
        return hub.sendError(conn, 'TAG_WEIT', { re: msg.seq });
      }
      const prevMs = match.tag.itMs.get(code) ?? 0;
      match.tag.itMs.set(code, prevMs + (at - match.tag.lastSwitchAt));
      match.tag.it = target;
      match.tag.lastSwitchAt = at;
      match.tag.immunityUntil = at + TAG_IMMUNITY_MS;
      hub.send(conn, 'OK', {}, { re: msg.seq });
      statePush(session, { tag: { it: target, immunityUntil: match.tag.immunityUntil } });
      return;
    }

    hub.sendError(conn, 'BAD_MESSAGE', { re: msg.seq });
  });

  // ---- Ergebnis (idempotent, pending + ACK — GoobyPal-Muster) --------------

  function buildResults(session) {
    const match = session.match;
    const matchId = session.room.slice('mg:'.length, 'mg:'.length + 8);
    const results = [];
    if (session.mode === 'fangen') {
      // Letzter Fänger sammelt seine Restzeit ein; Platz = wenigste Fänger-Zeit.
      if (match.tag.it) {
        const prevMs = match.tag.itMs.get(match.tag.it) ?? 0;
        const endAt = Math.min(now(), match.endsAt || now());
        match.tag.itMs.set(match.tag.it, prevMs + Math.max(0, endAt - match.tag.lastSwitchAt));
      }
      const codes = [...session.codes];
      codes.sort((x, y) => {
        const dx = match.dnf.has(x) || match.disconnected.has(x) ? 1 : 0;
        const dy = match.dnf.has(y) || match.disconnected.has(y) ? 1 : 0;
        if (dx !== dy) return dx - dy; // Getrennte fair ans Ende
        return (match.tag.itMs.get(x) ?? 0) - (match.tag.itMs.get(y) ?? 0);
      });
      codes.forEach((code, i) => {
        results.push({
          friendCode: code,
          rank: i + 1,
          zeitMs: match.tag.itMs.get(code) ?? 0,
          dnf: match.dnf.has(code) || match.disconnected.has(code),
        });
      });
    } else {
      const finishers = [...match.finish.entries()].sort((x, y) => x[1].rank - y[1].rank);
      for (const [code, fin] of finishers) {
        results.push({ friendCode: code, rank: fin.rank, zeitMs: fin.timeMs, dnf: false });
      }
      for (const code of session.codes) {
        if (!match.finish.has(code)) {
          results.push({ friendCode: code, rank: results.length + 1, zeitMs: 0, dnf: true });
        }
      }
    }
    for (const r of results) {
      r.rewardId = `rmp-${matchId}-${r.friendCode}`;
      r.ranked = !match.unranked.has(r.friendCode) && !r.dnf;
      r.mode = session.mode;
      r.kurs = session.kurs;
      r.room = session.room;
    }
    return results;
  }

  // Best-Only, richtungsbewusst: 'ab' = kleiner gewinnt, 'auf' = größer.
  function writeScore(ctxRef, kursId, code, wert) {
    const richtung = richtungFuer(kursId);
    const data = scoresData(ctxRef);
    if (!data.byKurs[kursId]) data.byKurs[kursId] = {};
    const prev = data.byKurs[kursId][code];
    if (prev && (richtung === 'ab' ? prev.wert <= wert : prev.wert >= wert)) return false;
    data.byKurs[kursId][code] = { wert, at: now() };
    ctxRef.store.markDirty('ranchscores');
    return true;
  }

  function finalize(session) {
    const match = session.match;
    if (!match || match.phase === 'done') return;
    match.phase = 'done';
    if (match.endTimer) {
      clearTimeout(match.endTimer);
      match.endTimer = null;
    }
    const results = buildResults(session);
    const pend = pendingData(ctx);
    for (const r of results) {
      // Ledger zuerst (append-only Audit), dann pending, DANN Versand.
      ctx.store.appendLine(`ledger/ranch-rewards-${monthKey(now(), cfg.tz)}.jsonl`, {
        at: now(),
        ...r,
      });
      if (!pend.pending[r.friendCode]) pend.pending[r.friendCode] = [];
      if (!pend.pending[r.friendCode].some((e) => e.rewardId === r.rewardId)) {
        pend.pending[r.friendCode].push(r);
      }
      if (r.ranked && session.mode !== 'fangen' && KURSE[session.kurs]) {
        writeScore(ctx, session.kurs, r.friendCode, r.zeitMs);
      }
    }
    ctx.store.flushNow('ranchmp');
    for (const r of results) {
      const device = ctx.byCode.get(r.friendCode);
      if (device) hub.sendToDevice(device, 'MG_RESULT', { ...r, results });
    }
    // Sind alle schon aus dem Raum (Timer-Ende nach Massen-Abriss), gibt es
    // keinen Leave mehr, der aufräumt — Session hier entsorgen.
    const room = ctx.rooms.get(session.room);
    if (!room || room.members.size === 0) cleanupSession(session);
  }

  hub.addWelcomeProvider((conn) => {
    const pend = pendingData(ctx);
    return { rmpPending: (pend.pending[conn.friendCode] ?? []).slice() };
  });

  hub.on('MG_RESULT_ACK', (conn, msg) => {
    const rewardId = typeof msg.d.rewardId === 'string' ? msg.d.rewardId : '';
    const pend = pendingData(ctx);
    const list = pend.pending[conn.friendCode] ?? [];
    const idx = list.findIndex((e) => e.rewardId === rewardId);
    if (idx >= 0) {
      list.splice(idx, 1);
      if (list.length === 0) delete pend.pending[conn.friendCode];
      ctx.store.markDirty('ranchmp');
    }
    hub.send(conn, 'OK', {}, { re: msg.seq });
  });

  // ---- Rejoin / Snapshot ---------------------------------------------------

  function snapshot(session) {
    const match = session.match;
    const d = {
      room: session.room,
      mode: session.mode,
      kurs: session.kurs,
      host: session.host,
      players: [...session.codes].map(playerInfo),
      serverNow: now(),
    };
    if (match) {
      maybeRun(match);
      d.phase = match.phase;
      d.seed = match.seed;
      d.startAt = match.startAt;
      d.endsAt = match.endsAt;
      d.stateVersion = match.stateVersion;
      d.ready = [...match.ready];
      d.progress = Object.fromEntries(match.next);
      d.strafenMs = Object.fromEntries(match.strafenMs);
      d.finished = Object.fromEntries(
        [...match.finish.entries()].map(([code, f]) => [code, { timeMs: f.timeMs, rank: f.rank }])
      );
      d.dnf = [...match.dnf];
      if (session.mode === 'fangen') {
        d.tag = { it: match.tag.it, immunityUntil: match.tag.immunityUntil };
      }
    }
    return d;
  }

  hub.on('MG_RESUME', (conn, msg) => {
    const session = sessions.get(typeof msg.d.room === 'string' ? msg.d.room : '');
    if (!session || !session.codes.has(conn.friendCode)) {
      return hub.sendError(conn, 'NOT_FOUND', { re: msg.seq });
    }
    hub.send(conn, 'MG_SNAPSHOT', snapshot(session), { re: msg.seq });
  });

  ctx.rooms.onJoin((conn, room) => {
    const session = sessions.get(room.id);
    if (!session) return;
    const match = session.match;
    if (match && match.disconnected.has(conn.friendCode)) {
      match.disconnected.delete(conn.friendCode);
      const timer = match.rejoinTimers.get(conn.friendCode);
      if (timer) {
        clearTimeout(timer);
        match.rejoinTimers.delete(conn.friendCode);
      }
      hub.send(conn, 'MG_SNAPSHOT', snapshot(session));
      broadcast(session, 'MG_PEER_UP', { room: room.id, friendCode: conn.friendCode }, conn.friendCode);
      maybeFinish(session);
    }
  });

  // ---- Verlassen / Verbindungsabriss ---------------------------------------

  ctx.rooms.onLeave((conn, roomId, { disconnect }) => {
    const session = sessions.get(roomId);
    if (!session) return;
    const code = conn.friendCode;

    if (session.mode === 'besuch') {
      // Besuch endet, sobald eine Seite geht (Muster visits.js).
      broadcast(session, 'RANCH_ENDED', { room: roomId, by: code }, code);
      for (const member of session.codes) {
        const device = ctx.byCode.get(member);
        const memberConn = device ? hub.connFor(device) : null;
        if (memberConn && memberConn !== conn) ctx.rooms.leave(memberConn, roomId);
      }
      cleanupSession(session);
      return;
    }

    if (session.mode === 'ausritt') {
      if (!disconnect) session.codes.delete(code);
      session.poses.delete(code);
      const room = ctx.rooms.get(roomId);
      if (!room || room.members.size === 0) cleanupSession(session);
      return;
    }

    const match = session.match;
    if (match.phase === 'lobby') {
      session.codes.delete(code);
      match.ready.delete(code);
      session.poses.delete(code);
      const room = ctx.rooms.get(roomId);
      if (!room || room.members.size === 0) {
        cleanupSession(session);
        return;
      }
      broadcast(session, 'MG_LOBBY', lobbyState(session));
      tryStart(session);
      return;
    }

    if (match.phase === 'done') {
      if (match.rematch.size > 0 && !match.rematch.has(code)) {
        broadcast(session, 'RMP_REMATCH_DECLINED', { room: roomId, friendCode: code }, code);
      }
      match.rematch.delete(code);
      session.codes.delete(code);
      const room = ctx.rooms.get(roomId);
      if (!room || room.members.size === 0) cleanupSession(session);
      return;
    }

    // countdown/run
    if (!disconnect) {
      // Bewusst gegangen → sofort DNF, Spiel läuft für den Rest weiter.
      match.dnf.add(code);
      statePush(session, { dnf: { friendCode: code } });
      maybeFinish(session);
      return;
    }
    // Abriss → Rejoin-Fenster (Doc §2.6): Platz bleibt reserviert, Uhr läuft.
    match.disconnected.add(code);
    broadcast(session, 'MG_PEER_DOWN', { room: roomId, friendCode: code, waitMs: cfg.rmpRejoinMs }, code);
    const timer = setTimeout(() => {
      match.rejoinTimers.delete(code);
      if (!match.disconnected.has(code)) return;
      match.disconnected.delete(code);
      match.dnf.add(code);
      statePush(session, { dnf: { friendCode: code } });
      const room = ctx.rooms.get(roomId);
      if (!room || room.members.size === 0) {
        finalize(session);
        cleanupSession(session);
        return;
      }
      maybeFinish(session);
    }, cfg.rmpRejoinMs);
    if (timer.unref) timer.unref();
    match.rejoinTimers.set(code, timer);
  });

  // ---- Revanche (Muster boardgames.js BOARD_REMATCH) -----------------------

  hub.on('RMP_REMATCH', (conn, msg) => {
    const session = sessions.get(typeof msg.d.room === 'string' ? msg.d.room : '');
    if (!session || !session.match || !session.codes.has(conn.friendCode)) {
      return hub.sendError(conn, 'NOT_FOUND', { re: msg.seq });
    }
    const match = session.match;
    if (match.phase !== 'done') return hub.sendError(conn, 'GAME_RUNNING', { re: msg.seq });
    const room = ctx.rooms.get(session.room);
    const present = room
      ? [...session.codes].filter((code) => {
          const device = ctx.byCode.get(code);
          return device && room.members.has(device);
        })
      : [];
    if (present.length < 2) return hub.sendError(conn, 'OFFLINE_TARGET', { re: msg.seq });
    match.rematch.add(conn.friendCode);
    if (![...present].every((code) => match.rematch.has(code))) {
      hub.send(conn, 'OK', { waiting: true }, { re: msg.seq });
      broadcast(session, 'RMP_REMATCH_WAIT', { room: session.room, friendCode: conn.friendCode }, conn.friendCode);
      return;
    }
    const fresh = createSession(session.mode, session.kurs, session.host, present);
    cleanupSession(session);
    const ready = readyPayload(fresh, { rematch: true });
    hub.send(conn, 'RANCH_READY', ready, { re: msg.seq });
    broadcast(fresh, 'RANCH_READY', ready, conn.friendCode);
  });

  // ---- REST: Ranch-Metadaten (Ausbau/Pferde/Trophäen für den Besuch) -------

  ctx.app.put('/api/ranch', express.json({ limit: cfg.limits.ranchMetaBytes }), (req, res) => {
    const auth = restAuth(ctx, req);
    if (!auth) return res.status(401).json({ ok: false, code: 'AUTH_FAIL' });
    const meta = req.body;
    if (typeof meta !== 'object' || meta === null || Array.isArray(meta)) {
      return res.status(400).json({ ok: false, code: 'BAD_META' });
    }
    const text = JSON.stringify(meta);
    if (Buffer.byteLength(text, 'utf8') > cfg.limits.ranchMetaBytes) {
      return res.status(413).json({ ok: false, code: 'PAYLOAD_TOO_LARGE' });
    }
    const code = auth.player.friendCode;
    const data = ranchesData(ctx);
    const entry = data.ranches[code] || { rev: 0 };
    entry.rev += 1;
    entry.sizeBytes = Buffer.byteLength(text, 'utf8');
    entry.uploadedAt = now();
    entry.blob = ctx.store.putBlob('blobs', `ranch-${code}.json`, text, cfg.limits.ranchMetaBytes);
    data.ranches[code] = entry;
    ctx.store.markDirty('ranches');
    res.json({ ok: true, rev: entry.rev });
  });

  ctx.app.get('/api/ranch/:friendCode', (req, res) => {
    const auth = restAuth(ctx, req);
    if (!auth) return res.status(401).json({ ok: false, code: 'AUTH_FAIL' });
    const code = String(req.params.friendCode || '').toUpperCase();
    if (!FRIEND_CODE_RE.test(code) || !ctx.byCode.has(code)) {
      return res.status(404).json({ ok: false, code: 'NOT_FOUND' });
    }
    const me = auth.player.friendCode;
    if (me !== code && !areFriends(ctx, me, code)) {
      return res.status(403).json({ ok: false, code: 'NOT_FRIENDS' });
    }
    const entry = ranchesData(ctx).ranches[code];
    const blob = entry ? ctx.store.readBlob(entry.blob) : null;
    if (!blob) return res.status(404).json({ ok: false, code: 'NOT_FOUND' });
    res.json({ ok: true, rev: entry.rev, meta: JSON.parse(blob.toString('utf8')) });
  });

  // ---- REST: Bestenliste + asynchrone Bestzeiten ---------------------------

  function minZeitMs(kurs) {
    return Math.max(1_000, kurs.minSegmentMs * Math.max(1, kurs.checkpoints.length));
  }

  // Plausibles Wert-Fenster je Bestenliste: Live-Kurse haben eine physikalische
  // Mindestzeit; RW-5-Zeiten mind. 3 s; RW-5-Punkte 1..100000.
  function wertOk(kursId, wert) {
    if (!Number.isInteger(wert)) return false;
    const kurs = KURSE[kursId];
    if (kurs) return wert >= minZeitMs(kurs) && wert <= MAX_ZEIT_MS;
    if (RW5_WERTUNGEN[kursId] === 'ab') return wert >= 3_000 && wert <= MAX_ZEIT_MS;
    return wert >= 1 && wert <= 100_000;
  }

  ctx.app.post('/api/rmp/score', express.json({ limit: 4 * 1024 }), (req, res) => {
    const auth = restAuth(ctx, req);
    if (!auth) return res.status(401).json({ ok: false, code: 'AUTH_FAIL' });
    if (!ctx.buckets.take(`rmpscore:${auth.deviceId}`, LIMITS.rmpScore)) {
      return res.status(429).json({ ok: false, code: 'RATE_LIMIT' });
    }
    const kursId = String(req.body?.kurs || '');
    if (!richtungFuer(kursId)) return res.status(400).json({ ok: false, code: 'BAD_KURS' });
    // Live-Kurse melden zeitMs, RW-5 einen generischen wert — beides erlaubt.
    const wert = Number.isInteger(req.body?.wert) ? req.body.wert : req.body?.zeitMs;
    if (!wertOk(kursId, wert)) return res.status(400).json({ ok: false, code: 'BAD_ZEIT' });
    if (req.body?.devSession === true) {
      return res.json({ ok: true, ranked: false, verbessert: false });
    }
    const code = auth.player.friendCode;
    const verbessert = writeScore(ctx, kursId, code, wert);
    const best = scoresData(ctx).byKurs[kursId]?.[code]?.wert ?? wert;
    res.json({ ok: true, ranked: true, verbessert, best });
  });

  ctx.app.get('/api/rmp/leaderboard/:kurs', (req, res) => {
    const auth = restAuth(ctx, req);
    if (!auth) return res.status(401).json({ ok: false, code: 'AUTH_FAIL' });
    const kursId = String(req.params.kurs || '');
    const richtung = richtungFuer(kursId);
    if (!richtung) return res.status(404).json({ ok: false, code: 'BAD_KURS' });
    const me = auth.player.friendCode;
    const circle = new Set([me, ...friendCodesOf(ctx, me)]);
    const scores = scoresData(ctx).byKurs[kursId] ?? {};
    const ghosts = ghostsData(ctx).byKurs[kursId] ?? {};
    const entries = [];
    for (const code of circle) {
      const s = scores[code];
      if (!s) continue;
      entries.push({ ...playerInfo(code), wert: s.wert, at: s.at, hatGhost: !!ghosts[code] });
    }
    entries.sort((a, b) => (richtung === 'ab' ? a.wert - b.wert : b.wert - a.wert));
    res.json({ ok: true, kurs: kursId, richtung, me, entries });
  });

  // ---- REST: Geister-Ablage (nur bester Lauf, Größenlimit + Prune) ---------

  // Ghost-Nutzlast prüfen. Zwei Formate: Live-Kurse schicken {rateHz, samples}
  // (Positions-Paare), RW-5 schickt {b64} — das G5-Binärformat aus
  // comp_ghost.gd (Magic 0x47 0x35), Base64-verpackt.
  function ghostBodyOk(kursId, body) {
    if (KURSE[kursId]) {
      const { rateHz, samples } = body ?? {};
      return (
        Number.isFinite(rateHz) &&
        rateHz >= 1 &&
        rateHz <= 15 &&
        Array.isArray(samples) &&
        samples.length > 0 &&
        samples.length <= MAX_GHOST_SAMPLES &&
        samples.every((s) => Array.isArray(s) && s.length >= 2 && s.every((v) => Number.isFinite(v)))
      );
    }
    const b64 = body?.b64;
    if (typeof b64 !== 'string' || b64.length === 0) return false;
    let raw;
    try {
      raw = Buffer.from(b64, 'base64');
    } catch {
      return false;
    }
    return raw.length >= 16 && raw[0] === 0x47 && raw[1] === 0x35;
  }

  ctx.app.put('/api/rmp/ghost/:kurs', express.json({ limit: cfg.limits.ghostBytes }), (req, res) => {
    const auth = restAuth(ctx, req);
    if (!auth) return res.status(401).json({ ok: false, code: 'AUTH_FAIL' });
    if (!ctx.buckets.take(`rmpscore:${auth.deviceId}`, LIMITS.rmpScore)) {
      return res.status(429).json({ ok: false, code: 'RATE_LIMIT' });
    }
    const kursId = String(req.params.kurs || '');
    const richtung = richtungFuer(kursId);
    if (!richtung || KURSE[kursId]?.mode === 'fangen') {
      return res.status(404).json({ ok: false, code: 'BAD_KURS' });
    }
    if (req.body?.devSession === true) {
      return res.status(403).json({ ok: false, code: 'DEV_SESSION' });
    }
    const wert = Number.isInteger(req.body?.wert) ? req.body.wert : req.body?.zeitMs;
    if (!wertOk(kursId, wert) || !ghostBodyOk(kursId, req.body)) {
      return res.status(400).json({ ok: false, code: 'BAD_GHOST' });
    }
    const code = auth.player.friendCode;
    const data = ghostsData(ctx);
    if (!data.byKurs[kursId]) data.byKurs[kursId] = {};
    const prev = data.byKurs[kursId][code];
    // Pro Spieler + Kurs GENAU EIN bester Ghost (Doc §2.5).
    if (prev && (richtung === 'ab' ? prev.wert <= wert : prev.wert >= wert)) {
      return res.json({ ok: true, gespeichert: false, best: prev.wert });
    }
    const payload = KURSE[kursId]
      ? { v: 1, kurs: kursId, wert, rateHz: req.body.rateHz, samples: req.body.samples }
      : { v: 1, kurs: kursId, wert, b64: req.body.b64 };
    const text = JSON.stringify(payload);
    if (Buffer.byteLength(text, 'utf8') > cfg.limits.ghostBytes) {
      return res.status(413).json({ ok: false, code: 'PAYLOAD_TOO_LARGE' });
    }
    const blob = ctx.store.putBlob('blobs', `rmp-ghost-${kursId}-${code}.json`, text, cfg.limits.ghostBytes);
    data.byKurs[kursId][code] = {
      wert,
      sizeBytes: Buffer.byteLength(text, 'utf8'),
      at: now(),
      blob,
    };
    // Prune: pro Kurs höchstens ghostsPerKurs Einträge — die Schlechtesten
    // fliegen (richtungsbewusst).
    const all = Object.entries(data.byKurs[kursId]).sort((a, b) =>
      richtung === 'ab' ? a[1].wert - b[1].wert : b[1].wert - a[1].wert
    );
    for (const [dropCode, entry] of all.slice(cfg.limits.ghostsPerKurs)) {
      ctx.store.deleteBlob(entry.blob);
      delete data.byKurs[kursId][dropCode];
    }
    ctx.store.markDirty('ranchghosts');
    res.json({ ok: true, gespeichert: true, best: wert });
  });

  ctx.app.get('/api/rmp/ghost/:kurs/:friendCode', (req, res) => {
    const auth = restAuth(ctx, req);
    if (!auth) return res.status(401).json({ ok: false, code: 'AUTH_FAIL' });
    const kursId = String(req.params.kurs || '');
    const code = String(req.params.friendCode || '').toUpperCase();
    if (!richtungFuer(kursId) || !FRIEND_CODE_RE.test(code)) {
      return res.status(404).json({ ok: false, code: 'NOT_FOUND' });
    }
    const me = auth.player.friendCode;
    if (me !== code && !areFriends(ctx, me, code)) {
      return res.status(403).json({ ok: false, code: 'NOT_FRIENDS' });
    }
    const entry = ghostsData(ctx).byKurs[kursId]?.[code];
    const blob = entry ? ctx.store.readBlob(entry.blob) : null;
    if (!blob) return res.status(404).json({ ok: false, code: 'NOT_FOUND' });
    res.json({ ok: true, ...JSON.parse(blob.toString('utf8')) });
  });

  // Fürs Panel-Dashboard / Tests.
  ctx.ranchSessions = sessions;
}
