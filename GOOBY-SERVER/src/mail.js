// Post/Mail (Doc C §3.7, P3 AP-1, W13B): Briefe + optionales Foto + optionales
// Item-Geschenk zwischen FREUNDEN. Brief-Text reist per WS (MAIL_SEND), Briefe
// MIT Foto per REST (POST /api/mail — 512-KB-Fotos passen nicht in den
// 16-KB-WS-Frame). Fotos liegen als Base64-TEXT-Blob unter data/mail/
// (store.putBlob schreibt utf8 — Base64 ist der binärsichere Weg über die
// bestehende Blob-Infrastruktur), Auslieferung lazy über GET /api/mail/blob/:id.
//
// Regeln (Auftrag W13B):
// - Quota: max 20 Briefe/Tag pro SENDER (dayKey in GOOBY_TZ, zeitinjiziert).
// - Postfach-Cap 50 pro Empfänger — der älteste GELESENE fliegt (Blob mit);
//   ist nichts gelesen → MAILBOX_FULL (fail-closed, nichts geht verloren).
// - Prune: gelesene Briefe fliegen 30 Tage NACH dem Lesen (readAt-basiert,
//   lazy bei jedem Postfach-Zugriff — kein Cron, ctx.clock testbar).
// - Idempotente Outbox-Retries: der Client schickt eine clientId mit; ein
//   Duplikat wird still als ok/dupe beantwortet (kein Doppel-Brief nach
//   Timeout-Retry). Zustellung: Push MAIL_NEW an Online-Empfänger, sonst
//   WELCOME.mailUnread beim nächsten Boot (Pull über MAIL_LIST).
// - Geschenk-Claim (MAIL_CLAIM) ist einmalig — der Client bucht die
//   Inventar-Gutschrift erst nach ok (Doppel-Gutschrift ausgeschlossen).

import crypto from 'node:crypto';
import express from 'express';
import { dayKey } from './config.js';
import { areFriends } from './friends.js';
import { restAuth, FRIEND_CODE_RE } from './auth.js';

export const TEXT_MAX = 500;
export const DAILY_LIMIT = 20; // Briefe/Tag pro Sender
export const MAILBOX_CAP = 50; // Briefe pro Postfach
export const PRUNE_READ_AFTER_MS = 30 * 24 * 3600_000;
export const GIFT_QTY_MAX = 99;

const ITEM_TYPES = new Set(['food', 'items']);
const ITEM_ID_RE = /^[a-zA-Z0-9._-]{1,40}$/;
const CLIENT_ID_RE = /^[A-Za-z0-9._-]{8,64}$/;
const CLIENT_ID_CAP = 40; // Dedupe-Fenster pro Sender (Outbox-Retries)
const PAGE_DEFAULT = 20;
const PAGE_MAX = 50;

export function mailData(ctx) {
  // boxes: friendCode -> [entry…]; senders: friendCode -> {dayKey, sent, recent:[clientId…]}
  return ctx.store.collection('mail', { boxes: {}, senders: {} });
}

function boxOf(data, code) {
  if (!Array.isArray(data.boxes[code])) data.boxes[code] = [];
  return data.boxes[code];
}

function senderOf(data, code) {
  if (!data.senders[code]) data.senders[code] = { dayKey: null, sent: 0, recent: [] };
  const s = data.senders[code];
  if (!Array.isArray(s.recent)) s.recent = [];
  return s;
}

function unreadCount(box) {
  return box.filter((e) => !e.readAt).length;
}

// Client-Sicht eines Briefs (interne Blob-Refs bleiben serverseitig).
function clientView(entry) {
  return {
    id: entry.id,
    from: entry.from,
    fromName: entry.fromName,
    fromGooby: entry.fromGooby,
    at: entry.at,
    text: entry.text,
    photoId: entry.photoId || '',
    item: entry.item || null,
    read: entry.readAt > 0,
    claimed: !!entry.claimed,
  };
}

function deleteEntryBlob(ctx, entry) {
  if (entry.photo) ctx.store.deleteBlob(entry.photo);
}

// Lazy-Prune: gelesene Briefe > 30 Tage nach dem Lesen fliegen (Blob mit).
function pruneBox(ctx, code) {
  const data = mailData(ctx);
  const box = boxOf(data, code);
  const now = ctx.clock.now();
  let dirty = false;
  for (let i = box.length - 1; i >= 0; i--) {
    const entry = box[i];
    if (entry.readAt > 0 && now - entry.readAt > PRUNE_READ_AFTER_MS) {
      deleteEntryBlob(ctx, entry);
      box.splice(i, 1);
      dirty = true;
    }
  }
  if (dirty) ctx.store.markDirty('mail');
  return box;
}

function validItem(item) {
  if (item === null || item === undefined) return null;
  if (typeof item !== 'object' || Array.isArray(item)) return false;
  const typ = item.typ;
  const id = item.id;
  const menge = item.menge === undefined ? 1 : item.menge;
  if (!ITEM_TYPES.has(typ)) return false;
  if (typeof id !== 'string' || !ITEM_ID_RE.test(id)) return false;
  if (!Number.isInteger(menge) || menge < 1 || menge > GIFT_QTY_MAX) return false;
  return { typ, id, menge };
}

// Kern: validieren, Quota/Cap, persistieren, Push. sender = {code, name, gooby},
// photo = {buf}|null (bereits magic-geprüft). Liefert {ok,…}|{ok:false, code}.
function deliverMail(ctx, sender, { to, text, item, clientId }, photo) {
  const data = mailData(ctx);
  const now = ctx.clock.now();
  const today = dayKey(now, ctx.cfg.tz);
  const quota = senderOf(data, sender.code);
  if (quota.dayKey !== today) {
    quota.dayKey = today;
    quota.sent = 0;
  }
  const base = { sentToday: quota.sent, dailyLimit: DAILY_LIMIT };
  const fail = (code) => ({ ok: false, code, ...base });

  const target = typeof to === 'string' ? to.toUpperCase() : '';
  if (!FRIEND_CODE_RE.test(target) || !ctx.byCode.has(target)) return fail('NOT_FOUND');
  if (target === sender.code) return fail('SELF');
  if (!areFriends(ctx, sender.code, target)) return fail('NOT_FRIENDS');

  const cleanText = typeof text === 'string' ? text : '';
  if (cleanText.length > TEXT_MAX) return fail('TEXT_TOO_LONG');
  const gift = validItem(item);
  if (gift === false) return fail('BAD_ITEM');
  if (cleanText.trim() === '' && !photo && !gift) return fail('BAD_MAIL');

  const cleanClientId =
    typeof clientId === 'string' && CLIENT_ID_RE.test(clientId) ? clientId : '';
  if (cleanClientId && quota.recent.includes(cleanClientId)) {
    // Outbox-Retry nach Timeout: schon zugestellt → still ok, kein Doppel-Brief.
    return { ok: true, id: '', dupe: true, ...base };
  }

  if (quota.sent >= DAILY_LIMIT) return fail('DAILY_LIMIT');

  const box = pruneBox(ctx, target);
  if (box.length >= MAILBOX_CAP) {
    // Ältester GELESENER fliegt; ungelesene sind heilig (fail-closed).
    let evict = -1;
    for (let i = 0; i < box.length; i++) {
      if (box[i].readAt > 0 && (evict < 0 || box[i].at < box[evict].at)) evict = i;
    }
    if (evict < 0) return fail('MAILBOX_FULL');
    deleteEntryBlob(ctx, box[evict]);
    box.splice(evict, 1);
  }

  const entry = {
    id: `mail-${crypto.randomBytes(8).toString('hex')}`,
    from: sender.code,
    fromName: sender.name,
    fromGooby: sender.gooby,
    to: target,
    at: now,
    text: cleanText,
    photo: null,
    photoId: '',
    item: gift,
    readAt: 0,
    claimed: false,
  };
  if (photo) {
    entry.photoId = `mailp-${crypto.randomBytes(8).toString('hex')}`;
    // Base64-TEXT-Blob: binärsicher über die bestehende utf8-Blob-Schicht;
    // Größe wurde bereits am DEKODIERTEN Foto geprüft.
    entry.photo = ctx.store.putBlob(
      'mail',
      entry.photoId,
      photo.buf.toString('base64'),
      Math.ceil((ctx.cfg.maxPhotoKb * 1024 * 4) / 3) + 8
    );
  }
  box.push(entry);
  quota.sent += 1;
  if (cleanClientId) {
    quota.recent.push(cleanClientId);
    while (quota.recent.length > CLIENT_ID_CAP) quota.recent.shift();
  }
  // Kritische Bestätigung (E13 P1-1): erst persistieren, dann ok melden.
  ctx.store.flushNow('mail');

  const targetDevice = ctx.byCode.get(target);
  ctx.hub.sendToDevice(targetDevice, 'MAIL_NEW', {
    mail: clientView(entry),
    unread: unreadCount(box),
  });
  return { ok: true, id: entry.id, sentToday: quota.sent, dailyLimit: DAILY_LIMIT };
}

function findMail(ctx, code, id) {
  const box = pruneBox(ctx, code);
  const entry = box.find((e) => e.id === id);
  return { box, entry };
}

// Magic-Bytes-Check (Doc C §3.7): nur JPEG (FF D8 FF) und PNG (89 50 4E 47).
function isImage(buf) {
  if (buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return true;
  return (
    buf.length >= 4 && buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4e && buf[3] === 0x47
  );
}

export function register(ctx) {
  const { hub, cfg } = ctx;
  mailData(ctx);

  const wsSender = (conn) => ({ code: conn.friendCode, name: conn.name, gooby: conn.goobyName });

  // Boot-Pull: Anzahl ungelesener Briefe (Liste holt der Client per MAIL_LIST).
  hub.addWelcomeProvider((conn) => ({
    mailUnread: unreadCount(pruneBox(ctx, conn.friendCode)),
  }));

  // Brief OHNE Foto (Text + optionales Geschenk) — der WS-Weg der Client-Outbox.
  hub.on('MAIL_SEND', (conn, msg) => {
    const result = deliverMail(ctx, wsSender(conn), msg.d, null);
    hub.send(conn, 'MAIL_RESULT', result, { re: msg.seq });
  });

  // Postfach-Pull: ungelesen zuerst, dann jüngste zuerst; simple Pagination.
  hub.on('MAIL_LIST', (conn, msg) => {
    const box = pruneBox(ctx, conn.friendCode);
    const sorted = box
      .slice()
      .sort((a, b) => (a.readAt > 0) - (b.readAt > 0) || b.at - a.at);
    const offset = Number.isInteger(msg.d.offset) && msg.d.offset > 0 ? msg.d.offset : 0;
    const limitRaw = Number.isInteger(msg.d.limit) ? msg.d.limit : PAGE_DEFAULT;
    const limit = Math.min(Math.max(limitRaw, 1), PAGE_MAX);
    hub.send(
      conn,
      'MAIL_STATE',
      {
        mails: sorted.slice(offset, offset + limit).map(clientView),
        total: box.length,
        unread: unreadCount(box),
        offset,
      },
      { re: msg.seq }
    );
  });

  // Lesen/Ack — idempotent: readAt wird nur EINMAL gesetzt (Prune-Uhr läuft
  // ab dem ersten Lesen), jedes weitere Ack antwortet einfach ok.
  hub.on('MAIL_ACK', (conn, msg) => {
    const id = typeof msg.d.id === 'string' ? msg.d.id : '';
    const { box, entry } = findMail(ctx, conn.friendCode, id);
    if (!entry) return hub.sendError(conn, 'NOT_FOUND', { re: msg.seq });
    if (!entry.readAt) {
      entry.readAt = ctx.clock.now();
      ctx.store.markDirty('mail');
    }
    hub.send(conn, 'OK', { unread: unreadCount(box) }, { re: msg.seq });
  });

  // Geschenk annehmen — einmalig; der Client bucht die Inventar-Gutschrift
  // erst nach ok (verhindert Doppel-Gutschrift nach Reinstall/Reconnect).
  hub.on('MAIL_CLAIM', (conn, msg) => {
    const id = typeof msg.d.id === 'string' ? msg.d.id : '';
    const { entry } = findMail(ctx, conn.friendCode, id);
    if (!entry || !entry.item) return hub.sendError(conn, 'NOT_FOUND', { re: msg.seq });
    if (entry.claimed) return hub.sendError(conn, 'ALREADY_CLAIMED', { re: msg.seq });
    entry.claimed = true;
    ctx.store.flushNow('mail');
    hub.send(conn, 'OK', { item: entry.item }, { re: msg.seq });
  });

  // Löschen (idempotent — removed:false wenn schon weg). Blob fliegt mit.
  hub.on('MAIL_DELETE', (conn, msg) => {
    const id = typeof msg.d.id === 'string' ? msg.d.id : '';
    const { box, entry } = findMail(ctx, conn.friendCode, id);
    if (entry) {
      deleteEntryBlob(ctx, entry);
      box.splice(box.indexOf(entry), 1);
      ctx.store.markDirty('mail');
    }
    hub.send(conn, 'OK', { removed: !!entry, unread: unreadCount(box) }, { re: msg.seq });
  });

  // ---- REST: Brief MIT Foto (Base64-JSON — passt nicht in den WS-Frame) ----
  // Body-Limit: Base64 des Foto-Limits (×4/3) + Text + JSON-Rahmen.
  const bodyLimit = Math.ceil((cfg.maxPhotoKb * 1024 * 4) / 3) + TEXT_MAX * 4 + 4096;
  ctx.app.post('/api/mail', express.json({ limit: bodyLimit }), (req, res) => {
    const auth = restAuth(ctx, req);
    if (!auth) return res.status(401).json({ ok: false, code: 'AUTH_FAIL' });
    const body = typeof req.body === 'object' && req.body !== null ? req.body : {};
    let photo = null;
    if (typeof body.photoB64 === 'string' && body.photoB64 !== '') {
      let buf;
      try {
        buf = Buffer.from(body.photoB64, 'base64');
      } catch {
        return res.status(400).json({ ok: false, code: 'BAD_PHOTO' });
      }
      if (buf.length === 0 || !isImage(buf)) {
        return res.status(400).json({ ok: false, code: 'BAD_PHOTO' });
      }
      if (buf.length > cfg.maxPhotoKb * 1024) {
        return res.status(413).json({ ok: false, code: 'PHOTO_TOO_LARGE' });
      }
      photo = { buf };
    }
    const sender = {
      code: auth.player.friendCode,
      name: auth.player.name,
      gooby: auth.player.goobyName,
    };
    const result = deliverMail(ctx, sender, body, photo);
    if (result.ok) return res.json(result);
    const status =
      { NOT_FOUND: 404, NOT_FRIENDS: 403, DAILY_LIMIT: 429, MAILBOX_FULL: 409 }[result.code] ||
      400;
    res.status(status).json(result);
  });

  // Foto-Auslieferung: NUR der Empfänger (Brief liegt in SEINEM Postfach).
  ctx.app.get('/api/mail/blob/:id', (req, res) => {
    const auth = restAuth(ctx, req);
    if (!auth) return res.status(401).json({ ok: false, code: 'AUTH_FAIL' });
    const id = String(req.params.id || '');
    const box = pruneBox(ctx, auth.player.friendCode);
    const entry = box.find((e) => e.photoId === id);
    if (!entry || !entry.photo) return res.status(404).json({ ok: false, code: 'NOT_FOUND' });
    const blob = ctx.store.readBlob(entry.photo);
    if (!blob) return res.status(404).json({ ok: false, code: 'NOT_FOUND' });
    res.json({ ok: true, photoB64: blob.toString('utf8') });
  });
}
