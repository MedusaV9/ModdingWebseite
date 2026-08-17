// Account-Umzug (Doc C §7, Backlog "Transfer-Code im Panel generierbar" → W13-C):
// Das Panel erzeugt für einen Spieler einen EINMALIGEN 8-Zeichen-Code (24 h
// gültig, zeitinjiziert über ctx.clock). Das NEUE Gerät löst ihn per WS
// MOVE_REDEEM ein und übernimmt die SERVERSEITIGE Identität (deviceId des
// Alt-Accounts + frisch ROTIERTES deviceSecret — TOFU-Key-Rotation, s.
// auth.js: gespeichert wird nur der Hash). Damit hängen FriendCode,
// Freundesliste, Pal-Historie und Presence sofort am neuen Gerät; das alte
// Gerät ist ausgesperrt (AUTH_FAIL). Der LOKALE Spielstand zieht bewusst
// NICHT um — das hier ist ein Server-Identitäts-Umzug, kein Save-Transfer.
// Einlösung ist atomar: players + movecodes werden synchron geflusht, BEVOR
// der Client die neue Identität sieht (E13-P1-1-Muster).

import crypto from 'node:crypto';
import { monthKey } from './config.js';
import { hashSecret, CODE_ALPHABET } from './auth.js';

export const MOVE_CODE_TTL_MS = 24 * 3600_000;
export const MOVE_CODE_LEN = 8;
export const MOVE_CODE_RE = /^[A-HJ-NP-Z2-9]{8}$/;

// Brute-Force-Bremse: 5 Einlöse-Versuche / 15 min pro IP (Panel-Login-Muster).
const REDEEM_LIMIT = { capacity: 5, refillPerSec: 5 / 900 };

export function moveData(ctx) {
  // codes: code -> {deviceId, friendCode, createdAt, expiresAt,
  //                 usedAt|null, usedBy|null, supersededAt|null}
  return ctx.store.collection('movecodes', { codes: {} });
}

function newMoveCode(existing) {
  for (;;) {
    let code = '';
    const bytes = crypto.randomBytes(MOVE_CODE_LEN);
    for (let i = 0; i < MOVE_CODE_LEN; i++) code += CODE_ALPHABET[bytes[i] % 32];
    if (!existing[code]) return code;
  }
}

function auditLine(ctx, entry) {
  ctx.store.appendLine(`ledger/moves-${monthKey(entry.at, ctx.cfg.tz)}.jsonl`, entry);
}

// Panel-Aktion: Umzugs-Code für einen Spieler erzeugen. Pro Account ist immer
// nur der JÜNGSTE Code gültig (ältere unbenutzte werden supersedet).
export function createMoveCode(ctx, deviceId) {
  const player = ctx.players[deviceId];
  if (!player) return { ok: false, code: 'NOT_FOUND' };
  const now = ctx.clock.now();
  const data = moveData(ctx);
  for (const entry of Object.values(data.codes)) {
    if (entry.deviceId === deviceId && !entry.usedAt && !entry.supersededAt) {
      entry.supersededAt = now;
    }
  }
  const code = newMoveCode(data.codes);
  data.codes[code] = {
    deviceId,
    friendCode: player.friendCode,
    createdAt: now,
    expiresAt: now + MOVE_CODE_TTL_MS,
    usedAt: null,
    usedBy: null,
    supersededAt: null,
  };
  ctx.store.flushNow('movecodes');
  auditLine(ctx, {
    at: now,
    action: 'create',
    code,
    deviceId,
    friendCode: player.friendCode,
    by: 'panel',
  });
  return { ok: true, code, expiresAt: now + MOVE_CODE_TTL_MS, friendCode: player.friendCode };
}

export function register(ctx) {
  const { hub } = ctx;
  moveData(ctx); // Collection früh laden.

  // Client (NEUES Gerät, nach normalem Guest-HELLO): Code einlösen.
  // Antwort MOVE_RESULT {ok, code?, identity?} — Fehlercodes bewusst grob
  // (INVALID_CODE deckt unbekannt/benutzt/supersedet ab, kein Orakel),
  // nur EXPIRED ist eigenständig (der Client erklärt die 24-h-Frist).
  hub.on('MOVE_REDEEM', (conn, msg) => {
    const reply = (d) => hub.send(conn, 'MOVE_RESULT', d, { re: msg.seq });
    if (!ctx.buckets.take(`move:${conn.ip}`, REDEEM_LIMIT)) {
      return reply({ ok: false, code: 'RATE_LIMIT' });
    }
    const code = typeof msg.d.code === 'string' ? msg.d.code.trim().toUpperCase() : '';
    if (!MOVE_CODE_RE.test(code)) return reply({ ok: false, code: 'INVALID_CODE' });
    const data = moveData(ctx);
    const entry = data.codes[code];
    if (!entry || entry.usedAt || entry.supersededAt) {
      return reply({ ok: false, code: 'INVALID_CODE' });
    }
    const now = ctx.clock.now();
    if (now > entry.expiresAt) return reply({ ok: false, code: 'EXPIRED' });
    const target = ctx.players[entry.deviceId];
    // Gebannte Accounts sind nicht umziehbar (sonst "umzieht" man sich um den Ban).
    if (!target || target.banned) return reply({ ok: false, code: 'INVALID_CODE' });

    // --- Atomare Übernahme -------------------------------------------------
    // 1) TOFU-Key-Rotation: frisches Secret, nur der Hash bleibt beim Server.
    const newSecret = crypto.randomBytes(32).toString('hex');
    target.secretHash = hashSecret(newSecret);
    target.movedAt = now;
    // 2) Code entwerten (einmalig).
    entry.usedAt = now;
    entry.usedBy = conn.deviceId;
    // 3) Wegwerf-Guest-Account des neuen Geräts aufräumen (das Gerät meldet
    //    sich gleich mit der übernommenen Identität neu an).
    const guest = conn.deviceId !== entry.deviceId ? ctx.players[conn.deviceId] : null;
    if (guest) {
      ctx.byCode.delete(guest.friendCode);
      delete ctx.players[conn.deviceId];
    }
    // 4) SYNCHRON persistieren, BEVOR der Client die Identität sieht — ein
    //    Crash direkt nach der Antwort lässt nie beide Secrets gültig zurück.
    ctx.store.flushNow('players');
    ctx.store.flushNow('movecodes');
    auditLine(ctx, {
      at: now,
      action: 'redeem',
      code,
      deviceId: entry.deviceId,
      friendCode: target.friendCode,
      redeemedByDevice: conn.deviceId,
    });

    reply({
      ok: true,
      identity: {
        deviceId: entry.deviceId,
        deviceSecret: newSecret,
        friendCode: target.friendCode,
        name: target.name,
        goobyName: target.goobyName,
      },
    });
    // 5) Altes Gerät (falls gerade online) höflich abmelden.
    const oldConn = hub.connFor(entry.deviceId);
    if (oldConn) {
      hub.send(oldConn, 'GOING_DOWN', { reason: 'MOVED' });
      oldConn.replaced = true;
      oldConn.ws.close(4008, 'MOVED');
    }
    // 6) Die einlösende Verbindung gehört noch zum (gelöschten) Guest —
    //    sauber schließen; der Client verbindet sich mit der neuen Identität.
    hub.send(conn, 'GOING_DOWN', { reason: 'MOVED' });
    conn.replaced = true;
    conn.ws.close(4008, 'MOVED');
  });
}
