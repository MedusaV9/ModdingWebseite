// Brettspiele M1: Schiffe versenken (Doc C §3.5 + Plan-Entscheidung W3c).
// Server = Turn-Relay + Turn-Ownership, KEINE Spielregeln (Treffer-Logik ist Client-Sache).
// Ausnahme mit Server-Regel: TOMATO max 1×/Spieler/Runde (sonst Spam).
// Disconnect: Room bleibt rejoinMs (120 s) reserviert → BOARD_RESUME {history}; danach Forfeit.
// FIX-6 (MP-Härtung):
// - BOARD_REMATCH: nach GAME_OVER wünschen sich beide Spieler eine Revanche →
//   neues BOARD_START (neuer Room, neuer Seed, der andere beginnt); einseitiger
//   Wunsch pusht BOARD_REMATCH_WAIT an den Gegner, Verlassen pusht
//   BOARD_REMATCH_DECLINED an den Wartenden.
// - BOARD_PEER_DOWN/-UP: Der verbliebene Spieler erfährt SOFORT vom Disconnect
//   des Gegners (inkl. waitMs des Rejoin-Fensters) und von dessen Rückkehr.
// - Beendete Spiele (over=true) werden aufgeräumt, sobald der Room leer ist
//   (vorher leakte jede Vollpartie einen games-Eintrag bis zum Prozessende).

import crypto from 'node:crypto';
import { areFriends } from './friends.js';
import { FRIEND_CODE_RE } from './auth.js';

const GAMES = new Set(['battleship']);
const HISTORY_KINDS = new Set(['SHOT', 'SHOT_RESULT', 'EMOTE', 'TOMATO', 'GAME_OVER']);

export function register(ctx) {
  const { hub, cfg } = ctx;
  // roomId -> Spielzustand
  const games = new Map();
  // "<from>-><to>" -> {game, at}
  const invites = new Map();

  function gameFor(room) {
    return games.get(typeof room === 'string' ? room : room.id) || null;
  }

  function otherPlayer(game, friendCode) {
    return game.players.find((p) => p.friendCode !== friendCode) || null;
  }

  function endGame(roomId) {
    const game = games.get(roomId);
    if (game?.rejoinTimer) clearTimeout(game.rejoinTimer);
    games.delete(roomId);
    ctx.rooms.destroy(roomId);
  }

  // Nur eingeladene Spieler dürfen in ihren board:-Room (auch beim Rejoin).
  ctx.rooms.registerJoinGuard('board', (conn, roomId) => {
    const game = games.get(roomId);
    if (!game) return { ok: false, code: 'BAD_ROOM' };
    if (!game.players.some((p) => p.friendCode === conn.friendCode)) {
      return { ok: false, code: 'BAD_ROOM' };
    }
    return { ok: true };
  });

  // Rejoin nach Disconnect → Verlauf nachliefern (+ Gegner informieren).
  ctx.rooms.onJoin((conn, room) => {
    const game = gameFor(room);
    if (!game) return;
    if (game.disconnected.has(conn.friendCode)) {
      game.disconnected.delete(conn.friendCode);
      if (game.rejoinTimer && game.disconnected.size === 0) {
        clearTimeout(game.rejoinTimer);
        game.rejoinTimer = null;
      }
      hub.send(conn, 'BOARD_RESUME', {
        room: room.id,
        game: game.game,
        history: game.history,
        turn: game.turn,
        n: game.n,
      });
      const other = otherPlayer(game, conn.friendCode);
      if (other) {
        hub.sendToDevice(ctx.byCode.get(other.friendCode), 'BOARD_PEER_UP', {
          room: room.id,
          friendCode: conn.friendCode,
        });
      }
    }
  });

  ctx.rooms.onLeave((conn, roomId, { disconnect }) => {
    const game = games.get(roomId);
    if (!game) return;
    if (game.over) {
      // FIX-6: Verlassen nach Spielende — offenen Revanche-Wunsch des
      // Gegners beantworten und leere Räume endgültig aufräumen.
      if (game.rematch.size > 0 && !game.rematch.has(conn.friendCode)) {
        const waiting = otherPlayer(game, conn.friendCode);
        if (waiting && game.rematch.has(waiting.friendCode)) {
          hub.sendToDevice(ctx.byCode.get(waiting.friendCode), 'BOARD_REMATCH_DECLINED', {
            room: roomId,
            friendCode: conn.friendCode,
          });
        }
      }
      game.rematch.delete(conn.friendCode);
      const room = ctx.rooms.get(roomId);
      if (!room || room.members.size === 0) endGame(roomId);
      return;
    }
    if (!disconnect) {
      // Bewusst gegangen → sofort Forfeit an den Verbliebenen.
      const winner = otherPlayer(game, conn.friendCode);
      if (winner) {
        hub.sendToDevice(ctx.byCode.get(winner.friendCode), 'BOARD_FORFEIT', {
          room: roomId,
          winner: winner.friendCode,
        });
      }
      endGame(roomId);
      return;
    }
    // Disconnect → 120-s-Rejoin-Fenster (Doc C §3.5); Gegner sofort informieren.
    game.disconnected.add(conn.friendCode);
    const stayer = otherPlayer(game, conn.friendCode);
    if (stayer && !game.disconnected.has(stayer.friendCode)) {
      hub.sendToDevice(ctx.byCode.get(stayer.friendCode), 'BOARD_PEER_DOWN', {
        room: roomId,
        friendCode: conn.friendCode,
        waitMs: cfg.boardRejoinMs,
      });
    }
    if (!game.rejoinTimer) {
      game.rejoinTimer = setTimeout(() => {
        const gone = [...game.disconnected];
        const stayed = game.players.filter((p) => !gone.includes(p.friendCode));
        for (const p of stayed) {
          hub.sendToDevice(ctx.byCode.get(p.friendCode), 'BOARD_FORFEIT', {
            room: roomId,
            winner: p.friendCode,
          });
        }
        endGame(roomId);
      }, cfg.boardRejoinMs);
      if (game.rejoinTimer.unref) game.rejoinTimer.unref();
    }
  });

  hub.on('BOARD_INVITE', (conn, msg) => {
    const target = typeof msg.d.target === 'string' ? msg.d.target.toUpperCase() : '';
    const game = msg.d.game;
    if (!GAMES.has(game)) return hub.sendError(conn, 'BAD_MESSAGE', { re: msg.seq });
    if (!FRIEND_CODE_RE.test(target) || !ctx.byCode.has(target)) {
      return hub.sendError(conn, 'NOT_FOUND', { re: msg.seq });
    }
    if (target === conn.friendCode) return hub.sendError(conn, 'SELF', { re: msg.seq });
    if (!areFriends(ctx, conn.friendCode, target)) {
      return hub.sendError(conn, 'NOT_FRIENDS', { re: msg.seq });
    }
    const targetDevice = ctx.byCode.get(target);
    if (!hub.isOnline(targetDevice)) return hub.sendError(conn, 'OFFLINE_TARGET', { re: msg.seq });
    invites.set(`${conn.friendCode}->${target}`, { game, at: ctx.clock.now() });
    hub.send(conn, 'OK', {}, { re: msg.seq });
    hub.sendToDevice(targetDevice, 'BOARD_INVITED', {
      from: conn.friendCode,
      name: conn.name,
      goobyName: conn.goobyName,
      game,
    });
  });

  hub.on('BOARD_DECLINE', (conn, msg) => {
    const from = typeof msg.d.from === 'string' ? msg.d.from.toUpperCase() : '';
    if (invites.delete(`${from}->${conn.friendCode}`)) {
      const fromDevice = ctx.byCode.get(from);
      if (fromDevice) hub.sendToDevice(fromDevice, 'BOARD_DECLINED', { from: conn.friendCode });
    }
    hub.send(conn, 'OK', {}, { re: msg.seq });
  });

  // Gemeinsamer Spielstart (BOARD_ACCEPT + BOARD_REMATCH): legt den
  // Spielzustand an und liefert das BOARD_START-Payload.
  function createGame(gameId, players, firstCode) {
    const roomId = `board:${crypto.randomUUID()}`;
    games.set(roomId, {
      game: gameId,
      players,
      first: firstCode,
      turn: firstCode,
      n: 1, // erwartete Zugnummer
      phase: 'shot', // 'shot' → 'result' → Zugwechsel
      exchanges: 0, // abgeschlossene SHOT/SHOT_RESULT-Paare
      tomatoRound: new Map(), // friendCode -> Runde des letzten Tomatenwurfs
      history: [],
      disconnected: new Set(),
      rejoinTimer: null,
      rematch: new Set(), // friendCodes mit Revanche-Wunsch (nach over)
      over: false,
      createdAt: ctx.clock.now(),
    });
    return {
      room: roomId,
      game: gameId,
      seed: crypto.randomBytes(4).readUInt32BE(0),
      first: firstCode,
      players,
    };
  }

  hub.on('BOARD_ACCEPT', (conn, msg) => {
    const from = typeof msg.d.from === 'string' ? msg.d.from.toUpperCase() : '';
    const invite = invites.get(`${from}->${conn.friendCode}`);
    if (!invite) return hub.sendError(conn, 'NOT_FOUND', { re: msg.seq });
    invites.delete(`${from}->${conn.friendCode}`);
    const inviterDevice = ctx.byCode.get(from);
    const inviter = ctx.players[inviterDevice];
    const players = [
      { friendCode: from, name: inviter.name, goobyName: inviter.goobyName },
      { friendCode: conn.friendCode, name: conn.name, goobyName: conn.goobyName },
    ];
    const start = createGame(invite.game, players, from); // der Einladende beginnt
    hub.send(conn, 'BOARD_START', start, { re: msg.seq });
    hub.sendToDevice(inviterDevice, 'BOARD_START', start);
  });

  // FIX-6: Revanche nach Spielende — beide müssen wollen, dann startet ein
  // FRISCHES Spiel (neuer Room/Seed); diesmal beginnt der ANDERE.
  hub.on('BOARD_REMATCH', (conn, msg) => {
    const roomId = typeof msg.d.room === 'string' ? msg.d.room : '';
    const game = games.get(roomId);
    if (!game || !game.players.some((p) => p.friendCode === conn.friendCode)) {
      return hub.sendError(conn, 'NOT_FOUND', { re: msg.seq });
    }
    if (!game.over) return hub.sendError(conn, 'GAME_RUNNING', { re: msg.seq });
    const other = otherPlayer(game, conn.friendCode);
    const otherDevice = other ? ctx.byCode.get(other.friendCode) : null;
    if (!other || !hub.isOnline(otherDevice)) {
      return hub.sendError(conn, 'OFFLINE_TARGET', { re: msg.seq });
    }
    game.rematch.add(conn.friendCode);
    if (game.rematch.size < game.players.length) {
      hub.send(conn, 'OK', { waiting: true }, { re: msg.seq });
      hub.sendToDevice(otherDevice, 'BOARD_REMATCH_WAIT', {
        room: roomId,
        friendCode: conn.friendCode,
      });
      return;
    }
    // Rollentausch: wer letztes Mal NICHT anfing, beginnt die Revanche.
    const firstCode = game.first === conn.friendCode ? other.friendCode : conn.friendCode;
    const start = createGame(game.game, game.players, firstCode);
    endGame(roomId);
    hub.send(conn, 'BOARD_START', start, { re: msg.seq });
    hub.sendToDevice(otherDevice, 'BOARD_START', start);
  });

  // Runde = beide Spieler haben je ein SHOT/SHOT_RESULT-Paar abgeschlossen.
  const currentRound = (game) => Math.floor(game.exchanges / 2);

  function record(game, conn, kind, body) {
    if (HISTORY_KINDS.has(kind)) {
      game.history.push({ kind, body, from: conn.friendCode });
    }
  }

  // Turn-Ownership: SHOT nur wer dran ist, SHOT_RESULT nur vom Beschossenen, n exakt.
  ctx.rooms.registerKindHook('SHOT', (conn, room, body) => {
    const game = gameFor(room);
    if (!game || game.over) return { ok: false, code: 'BAD_ROOM' };
    if (game.phase !== 'shot' || game.turn !== conn.friendCode) {
      return { ok: false, code: 'NOT_YOUR_TURN' };
    }
    if (body.n !== game.n) return { ok: false, code: 'BAD_TURN_N' };
    game.phase = 'result';
    record(game, conn, 'SHOT', body);
    return { ok: true };
  });

  ctx.rooms.registerKindHook('SHOT_RESULT', (conn, room, body) => {
    const game = gameFor(room);
    if (!game || game.over) return { ok: false, code: 'BAD_ROOM' };
    if (game.phase !== 'result' || game.turn === conn.friendCode) {
      return { ok: false, code: 'NOT_YOUR_TURN' };
    }
    if (body.n !== game.n) return { ok: false, code: 'BAD_TURN_N' };
    game.phase = 'shot';
    game.n += 1;
    game.exchanges += 1;
    game.turn = otherPlayer(game, game.turn).friendCode;
    record(game, conn, 'SHOT_RESULT', body);
    return { ok: true };
  });

  // DIE Server-Regel: Tomate max 1×/Spieler/Runde (Doc C §3.5).
  ctx.rooms.registerKindHook('TOMATO', (conn, room, body) => {
    const game = gameFor(room);
    if (!game || game.over) return { ok: false, code: 'BAD_ROOM' };
    const round = currentRound(game);
    if (game.tomatoRound.get(conn.friendCode) === round) {
      return { ok: false, code: 'TOMATO_LIMIT' };
    }
    game.tomatoRound.set(conn.friendCode, round);
    record(game, conn, 'TOMATO', body);
    return { ok: true };
  });

  ctx.rooms.registerKindHook('GAME_OVER', (conn, room, body) => {
    const game = gameFor(room);
    if (!game) return { ok: false, code: 'BAD_ROOM' };
    game.over = true;
    record(game, conn, 'GAME_OVER', body);
    return { ok: true };
  });

  // EMOTE in board:-Räumen mit in die History nehmen (Rejoin sieht auch Emotes).
  ctx.rooms.registerKindHook('EMOTE', (conn, room, body) => {
    const game = gameFor(room);
    if (game) record(game, conn, 'EMOTE', body);
    return { ok: true }; // in Nicht-Board-Räumen einfach relayen
  });

  // Fürs Panel-Dashboard.
  ctx.boardGames = games;
}
