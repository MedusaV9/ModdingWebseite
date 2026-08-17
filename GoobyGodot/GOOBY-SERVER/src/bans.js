// Ban-Verwaltung (W13-C, Befund P3): Panel-gesteuertes, ECHTES Server-Gate.
// Das HELLO-Gate (höfliche BANNED-Ablehnung + Close 4005) und das restAuth-Gate
// (Bearer eines gebannten Spielers → null) existieren bereits in ws.js/auth.js —
// hier leben Store + Audit-Log + die Aktionen (Ban trennt bestehende Sessions),
// plus eine /api-Middleware, die gebannten (aber korrekt signierten) Geräten
// ein explizites 403 BANNED gibt statt eines verwirrenden 401.
// Pflicht-Begründung: ohne "warum" gibt es keinen Audit-Eintrag und keinen Ban.

import { validDeviceId, validSecret, secretMatches } from './auth.js';

const AUDIT_CAP = 500;
const REASON_MAX = 200;

export function bansData(ctx) {
  // audit: append-only (gedeckelt), neueste am Ende — {action, deviceId,
  // friendCode, name, reason, by, at}. Der Ban-Zustand selbst lebt als
  // player.banned im Player-Record (ws.js/auth.js prüfen genau dieses Feld).
  return ctx.store.collection('bans', { audit: [] });
}

function writeAudit(ctx, entry) {
  const data = bansData(ctx);
  data.audit.push(entry);
  if (data.audit.length > AUDIT_CAP) data.audit.splice(0, data.audit.length - AUDIT_CAP);
  ctx.store.flushNow('bans');
  // Zusätzlich append-only JSONL (Doc C §2.5-Muster), monatlich rotiert.
  ctx.store.appendLine(
    `ledger/moderation-${new Date(entry.at).toISOString().slice(0, 7)}.jsonl`,
    entry
  );
}

// Panel-Aktion: Spieler bannen. reason ist PFLICHT (Audit "wer/wann/warum").
export function banPlayer(ctx, deviceId, reason, by = 'panel') {
  const player = ctx.players[deviceId];
  if (!player) return { ok: false, code: 'NOT_FOUND' };
  const cleanReason = String(reason ?? '').trim().slice(0, REASON_MAX);
  if (!cleanReason) return { ok: false, code: 'REASON_REQUIRED' };
  if (player.banned) return { ok: false, code: 'ALREADY_BANNED' };
  const now = ctx.clock.now();
  player.banned = true;
  player.bannedAt = now;
  player.bannedReason = cleanReason;
  ctx.store.flushNow('players');
  writeAudit(ctx, {
    action: 'ban',
    deviceId,
    friendCode: player.friendCode,
    name: player.name,
    reason: cleanReason,
    by,
    at: now,
  });
  // Bestehende Session höflich trennen: GOING_DOWN + Close. Der Client zeigt
  // seinen Offline-Chip; jeder Reconnect endet am HELLO-Gate (BANNED, 4005).
  const conn = ctx.hub.connFor(deviceId);
  if (conn) {
    ctx.hub.send(conn, 'GOING_DOWN', { reason: 'BANNED' });
    conn.ws.close(4005, 'BANNED');
  }
  return { ok: true, friendCode: player.friendCode, name: player.name };
}

// Panel-Aktion: Ban aufheben. Auch hier Pflicht-Begründung (Audit-Symmetrie).
export function unbanPlayer(ctx, deviceId, reason, by = 'panel') {
  const player = ctx.players[deviceId];
  if (!player) return { ok: false, code: 'NOT_FOUND' };
  const cleanReason = String(reason ?? '').trim().slice(0, REASON_MAX);
  if (!cleanReason) return { ok: false, code: 'REASON_REQUIRED' };
  if (!player.banned) return { ok: false, code: 'NOT_BANNED' };
  const now = ctx.clock.now();
  player.banned = false;
  delete player.bannedAt;
  delete player.bannedReason;
  ctx.store.flushNow('players');
  writeAudit(ctx, {
    action: 'unban',
    deviceId,
    friendCode: player.friendCode,
    name: player.name,
    reason: cleanReason,
    by,
    at: now,
  });
  return { ok: true, friendCode: player.friendCode, name: player.name };
}

export function register(ctx) {
  bansData(ctx); // Collection früh laden (Bestand nach Neustart).

  // REST-Gate: ein gebannter Spieler mit KORREKTEM Secret bekommt ein
  // eindeutiges 403 BANNED (statt 401 der normalen restAuth-Ablehnung).
  // Falsches/fehlendes Secret fällt bewusst zum einheitlichen 401 durch
  // (kein Enumeration-Orakel: "gebannt" verrät sich nur Berechtigten).
  // Registrierung VOR den Feature-Modulen (modules.js: bans an Position 1),
  // damit die Middleware im Express-Stack vor allen /api-Routen liegt.
  ctx.app.use('/api', (req, res, next) => {
    const header = req.headers.authorization || '';
    if (!header.startsWith('Bearer ')) return next();
    const idx = header.indexOf(':');
    if (idx < 0) return next();
    const deviceId = header.slice('Bearer '.length, idx).trim();
    const secret = header.slice(idx + 1).trim();
    if (!validDeviceId(deviceId) || !validSecret(secret)) return next();
    const player = ctx.players[deviceId];
    if (player?.banned && secretMatches(secret, player.secretHash)) {
      return res.status(403).json({ ok: false, code: 'BANNED' });
    }
    next();
  });
}
