// GoobyPal (Doc C §3.3): Coin-Transfers zwischen Freunden — das EINZIGE server-autoritative
// Ökonomie-Feature (deshalb online-only). Tageslimit pro ABSENDER (default 250) mit dayKey
// in GOOBY_TZ. Ledger: JSONL append-only (auditierbar) + kurze History im Player-Record.
// Empfänger offline → Gutschrift landet in der Pull-Queue (WELCOME.palPending).

import { LIMITS } from './ratelimit.js';
import { dayKey, monthKey } from './config.js';
import { areFriends } from './friends.js';
import { FRIEND_CODE_RE } from './auth.js';

const HISTORY_CAP = 30;

function palState(player) {
  if (!player.pal) player.pal = { dayKey: null, sent: 0, history: [], pending: [] };
  return player.pal;
}

function pushHistory(pal, entry) {
  pal.history.push(entry);
  if (pal.history.length > HISTORY_CAP) pal.history.splice(0, pal.history.length - HISTORY_CAP);
}

export function register(ctx) {
  const { hub, cfg } = ctx;

  // Offline-Gutschriften beim Boot abholen (und leeren).
  hub.addWelcomeProvider((conn) => {
    const pal = palState(ctx.players[conn.deviceId]);
    const pending = pal.pending;
    pal.pending = [];
    if (pending.length) ctx.store.markDirty('players');
    return { palPending: pending };
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
    const delivery = { from: conn.friendCode, amount, at: now };
    const online = hub.sendToDevice(targetDevice, 'PAL_RECEIVED', delivery);
    if (!online) rPal.pending.push(delivery);
    ctx.store.markDirty('players');
    // Append-only-Ledger (Audit, Doc C §2.5), monatlich rotiert.
    ctx.store.appendLine(`ledger/transfers-${monthKey(now, cfg.tz)}.jsonl`, {
      at: now,
      from: conn.friendCode,
      to,
      amount,
      dayKey: today,
    });
    reply({ ok: true, sentToday: pal.sent, dailyLimit: cfg.palDailyLimit });
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
