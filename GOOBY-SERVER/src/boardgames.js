// Brettspiele M1: Schiffe versenken (Doc C §3.5 + Plan-Entscheidung W3c).
// Server = Turn-Relay + Turn-Ownership, KEINE Spielregeln (Treffer-Logik ist Client-Sache).
// Ausnahme mit Server-Regel: TOMATO max 1×/Spieler/Runde (sonst Spam).
// Disconnect: Room bleibt rejoinMs (120 s) reserviert → BOARD_RESUME {history}; danach Forfeit.

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

  // Rejoin nach Disconnect → Verlauf nachliefern.
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
    }
  });

  ctx.rooms.onLeave((conn, roomId, { disconnect }) => {
    const game = games.get(roomId);
    if (!game || game.over) return;
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
    // Disconnect → 120-s-Rejoin-Fenster (Doc C §3.5).
    game.disconnected.add(conn.friendCode);
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

  hub.on('BOARD_ACCEPT', (conn, msg) => {
    const from = typeof msg.d.from === 'string' ? msg.d.from.toUpperCase() : '';
    const invite = invites.get(`${from}->${conn.friendCode}`);
    if (!invite) return hub.sendError(conn, 'NOT_FOUND', { re: msg.seq });
    invites.delete(`${from}->${conn.friendCode}`);
    const roomId = `board:${crypto.randomUUID()}`;
    const inviterDevice = ctx.byCode.get(from);
    const inviter = ctx.players[inviterDevice];
    const players = [
      { friendCode: from, name: inviter.name, goobyName: inviter.goobyName },
      { friendCode: conn.friendCode, name: conn.name, goobyName: conn.goobyName },
    ];
    games.set(roomId, {
      game: invite.game,
      players,
      first: from, // der Einladende beginnt
      turn: from,
      n: 1, // erwartete Zugnummer
      phase: 'shot', // 'shot' → 'result' → Zugwechsel
      exchanges: 0, // abgeschlossene SHOT/SHOT_RESULT-Paare
      tomatoRound: new Map(), // friendCode -> Runde des letzten Tomatenwurfs
      history: [],
      disconnected: new Set(),
      rejoinTimer: null,
      over: false,
      createdAt: ctx.clock.now(),
    });
    const start = {
      room: roomId,
      game: invite.game,
      seed: crypto.randomBytes(4).readUInt32BE(0),
      first: from,
      players,
    };
    hub.send(conn, 'BOARD_START', start, { re: msg.seq });
    hub.sendToDevice(inviterDevice, 'BOARD_START', start);
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
