// GoobyPal (Doc C §3.3): Coin-Transfers zwischen Freunden — das EINZIGE server-autoritative
// Ökonomie-Feature (deshalb online-only). Tageslimit pro ABSENDER (default 250) mit dayKey
// in GOOBY_TZ. Ledger: JSONL append-only (auditierbar) + kurze History im Player-Record.
// Zustellung (E13 P1-2): JEDE Gutschrift wird als Pending mit Zustell-Id persistiert,
// BEVOR der Absender ok sieht — Socket-Queueing zählt NIE als Zustellbestätigung.
// Der Empfänger bekommt sie live (PAL_RECEIVED) und/oder beim nächsten Connect
// (WELCOME.palPending) und räumt sie erst per PAL_ACK ab; der Client dedupet über die Id.

import crypto from 'node:crypto';
import { LIMITS } from './ratelimit.js';
import { dayKey, monthKey } from './config.js';
import { areFriends } from './friends.js';
import { FRIEND_CODE_RE } from './auth.js';

const HISTORY_CAP = 30;

function palState(player) {
  if (!player.pal) player.pal = { dayKey: null, sent: 0, history: [], pending: [] };
  return player.pal;
}

function newDeliveryId() {
  return `pal-${crypto.randomBytes(8).toString('hex')}`;
}

function pushHistory(pal, entry) {
  pal.history.push(entry);
  if (pal.history.length > HISTORY_CAP) pal.history.splice(0, pal.history.length - HISTORY_CAP);
}

export function register(ctx) {
  const { hub, cfg } = ctx;

  // Offline-Gutschriften beim Boot abholen — NICHT leeren: Pending bleibt,
  // bis der Client per PAL_ACK bestätigt (Zustellung überlebt so verlorene
  // WELCOMEs, Disconnect-Races und Server-Neustarts). Alt-Einträge ohne Id
  // werden migriert, damit der Client acken/dedupen kann.
  hub.addWelcomeProvider((conn) => {
    const pal = palState(ctx.players[conn.deviceId]);
    let migrated = false;
    for (const p of pal.pending) {
      if (!p.id) {
        p.id = newDeliveryId();
        migrated = true;
      }
    }
    if (migrated) ctx.store.markDirty('players');
    return { palPending: pal.pending.slice() };
  });

  // Empfangs-Bestätigung des Clients: erst JETZT ist die Gutschrift zugestellt.
  hub.on('PAL_ACK', (conn, msg) => {
    const pal = palState(ctx.players[conn.deviceId]);
    const id = typeof msg.d.id === 'string' ? msg.d.id : '';
    const idx = pal.pending.findIndex((p) => p.id === id);
    if (idx >= 0) {
      pal.pending.splice(idx, 1);
      ctx.store.markDirty('players');
    }
    hub.send(conn, 'OK', {}, { re: msg.seq });
  });

  hub.on('PAL_SEND', (conn, msg) => {
    const now = ctx.clock.now();
    const today = dayKey(now, cfg.tz);
    const sender = ctx.players[conn.deviceId];
    const pal = palState(sender);
    if (pal.dayKey !== today) {
      pal.dayKey = today;
      pal.sent = 0;
    }
    const reply = (d) => hub.send(conn, 'PAL_RESULT', d, { re: msg.seq });
    const fail = (code) =>
      reply({ ok: false, code, sentToday: pal.sent, dailyLimit: cfg.palDailyLimit });

    if (!ctx.buckets.take(`pal:${conn.deviceId}`, LIMITS.palSend)) return fail('RATE_LIMIT');

    const to = typeof msg.d.to === 'string' ? msg.d.to.toUpperCase() : '';
    const amount = msg.d.amount;
    if (!FRIEND_CODE_RE.test(to) || !ctx.byCode.has(to)) return fail('NOT_FOUND');
    if (!Number.isInteger(amount) || amount < 1 || amount > cfg.palDailyLimit) {
      return fail('BAD_AMOUNT');
    }
    if (!areFriends(ctx, conn.friendCode, to)) return fail('NOT_FRIENDS');
    if (pal.sent + amount > cfg.palDailyLimit) return fail('DAILY_LIMIT');

    // Autoritativ verbuchen.
    pal.sent += amount;
    pushHistory(pal, { dir: 'out', peer: to, amount, at: now });
    const targetDevice = ctx.byCode.get(to);
    const receiver = ctx.players[targetDevice];
    const rPal = palState(receiver);
    pushHistory(rPal, { dir: 'in', peer: conn.friendCode, amount, at: now });
    // E13 P1-1/P1-2: Pending IMMER persistieren (synchron, atomar), BEVOR
    // der Absender ok sieht — ein Disconnect-Race oder Crash direkt nach der
    // Antwort verliert die Gutschrift damit nie. Abgeräumt wird per PAL_ACK.
    const delivery = { id: newDeliveryId(), from: conn.friendCode, amount, at: now };
    rPal.pending.push(delivery);
    ctx.store.flushNow('players');
    // Append-only-Ledger (Audit, Doc C §2.5), monatlich rotiert.
    ctx.store.appendLine(`ledger/transfers-${monthKey(now, cfg.tz)}.jsonl`, {
      at: now,
      from: conn.friendCode,
      to,
      amount,
      dayKey: today,
    });
    reply({ ok: true, sentToday: pal.sent, dailyLimit: cfg.palDailyLimit });
    // Live-Zustellung ist nur Beschleunigung — die Wahrheit liegt im Pending.
    hub.sendToDevice(targetDevice, 'PAL_RECEIVED', delivery);
  });

  hub.on('PAL_HISTORY', (conn, msg) => {
    const now = ctx.clock.now();
    const pal = palState(ctx.players[conn.deviceId]);
    const sentToday = pal.dayKey === dayKey(now, cfg.tz) ? pal.sent : 0;
    hub.send(
      conn,
      'PAL_HISTORY_STATE',
      { entries: pal.history.slice(-HISTORY_CAP), sentToday, dailyLimit: cfg.palDailyLimit },
      { re: msg.seq }
    );
  });
}
