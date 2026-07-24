// Webpanel-Routing + Auth (Doc C §4): Passwort-Login (ENV GOOBY_ADMIN_PASSWORD, Pflicht),
// Session-Cookie (httpOnly, SameSite=Lax, 12 h, in-memory — Neustart = neu einloggen),
// Login-Rate-Limit 5/15 min pro IP. FAIL-CLOSED: ohne Passwort ist ALLES unter /panel 503.
// Kein cookie-session-Paket nötig: zufälliges Session-Token in einer Map reicht für
// einen 1-Prozess-Server (deps bleiben express + ws).

import crypto from 'node:crypto';
import express from 'express';
import { LIMITS } from '../src/ratelimit.js';
import { loginPage, layout, esc } from './html.js';
import {
  dashboardPage,
  analyticsPage,
  codesPage,
  eventsPage,
  friendsPage,
  playersPage,
} from './pages.js';
import { createCode, deactivateCode } from '../src/codes.js';
import { triggerEvent } from '../src/events.js';

const SESSION_TTL_MS = 12 * 3600_000;
const COOKIE = 'gooby_panel';

function parseCookies(req) {
  const out = {};
  for (const part of (req.headers.cookie || '').split(';')) {
    const idx = part.indexOf('=');
    if (idx > 0) out[part.slice(0, idx).trim()] = part.slice(idx + 1).trim();
  }
  return out;
}

function passwordMatches(given, expected) {
  const a = crypto.createHash('sha256').update(String(given)).digest();
  const b = crypto.createHash('sha256').update(String(expected)).digest();
  return crypto.timingSafeEqual(a, b);
}

export function register(ctx) {
  const { app, cfg } = ctx;
  const sessions = new Map(); // token -> expiresAt
  ctx.panelSessions = sessions;

  const isAuthed = (req) => {
    const token = parseCookies(req)[COOKIE];
    if (!token) return false;
    const expires = sessions.get(token);
    if (!expires || expires < ctx.clock.now()) {
      sessions.delete(token);
      return false;
    }
    return true;
  };

  // FAIL-CLOSED: ohne GOOBY_ADMIN_PASSWORD ist das gesamte Panel hart deaktiviert.
  app.use('/panel', (req, res, next) => {
    if (!cfg.adminPassword) {
      res
        .status(503)
        .type('text/plain')
        .send('GOOBY Panel deaktiviert: GOOBY_ADMIN_PASSWORD ist nicht gesetzt (fail-closed).');
      return;
    }
    next();
  });

  app.get('/panel/login', (req, res) => {
    res.type('html').send(loginPage());
  });

  app.post('/panel/login', express.urlencoded({ extended: false, limit: '2kb' }), (req, res) => {
    if (!ctx.buckets.take(`panel:${req.socket.remoteAddress}`, LIMITS.panelLogin)) {
      res.status(429).type('html').send(loginPage({ error: 'Zu viele Versuche — 15 Minuten warten.' }));
      return;
    }
    if (!passwordMatches(req.body?.password ?? '', cfg.adminPassword)) {
      res.status(401).type('html').send(loginPage({ error: 'Falsches Passwort.' }));
      return;
    }
    const token = crypto.randomBytes(32).toString('hex');
    sessions.set(token, ctx.clock.now() + SESSION_TTL_MS);
    res.setHeader(
      'Set-Cookie',
      `${COOKIE}=${token}; HttpOnly; SameSite=Lax; Path=/panel; Max-Age=${SESSION_TTL_MS / 1000}`
    );
    res.redirect(303, '/panel/');
  });

  app.post('/panel/logout', (req, res) => {
    const token = parseCookies(req)[COOKIE];
    if (token) sessions.delete(token);
    res.setHeader('Set-Cookie', `${COOKIE}=; HttpOnly; SameSite=Lax; Path=/panel; Max-Age=0`);
    res.redirect(303, '/panel/login');
  });

  // Ab hier: nur mit Session.
  app.use('/panel', (req, res, next) => {
    if (!isAuthed(req)) {
      res.redirect(303, '/panel/login');
      return;
    }
    next();
  });

  app.get('/panel/', (req, res) => res.type('html').send(dashboardPage(ctx)));
  app.get('/panel/analytics', (req, res) => res.type('html').send(analyticsPage(ctx, req.query)));
  app.get('/panel/codes', (req, res) => res.type('html').send(codesPage(ctx)));
  app.get('/panel/events', (req, res) => res.type('html').send(eventsPage(ctx)));
  app.get('/panel/friends', (req, res) => res.type('html').send(friendsPage(ctx)));
  app.get('/panel/players', (req, res) => res.type('html').send(playersPage(ctx)));

  const form = express.urlencoded({ extended: false, limit: '8kb' });

  app.post('/panel/api/codes', form, (req, res) => {
    let reward;
    try {
      reward = JSON.parse(req.body?.reward ?? '');
    } catch {
      reward = null;
    }
    const validUntilRaw = (req.body?.validUntil || '').trim();
    const validUntil = validUntilRaw ? Date.parse(`${validUntilRaw}T23:59:59`) : null;
    const result = createCode(ctx, {
      code: req.body?.code,
      reward,
      maxUses: req.body?.maxUses ? Number.parseInt(req.body.maxUses, 10) : null,
      validUntil: Number.isFinite(validUntil) ? validUntil : null,
    });
    const flash = result.ok
      ? `<div class="notice">Code <code>${esc(result.name)}</code> angelegt.</div>`
      : `<div class="err">Fehler: ${esc(result.code)} (Code ungültig/doppelt oder Reward kein JSON-Objekt)</div>`;
    res.status(result.ok ? 200 : 400).type('html').send(codesPage(ctx, { flash }));
  });

  app.post('/panel/api/codes/deactivate', form, (req, res) => {
    const result = deactivateCode(ctx, req.body?.code);
    const flash = result.ok
      ? `<div class="notice">Code deaktiviert.</div>`
      : `<div class="err">Code nicht gefunden.</div>`;
    res.status(result.ok ? 200 : 404).type('html').send(codesPage(ctx, { flash }));
  });

  app.post('/panel/api/events', form, (req, res) => {
    let params;
    try {
      params = req.body?.params ? JSON.parse(req.body.params) : {};
    } catch {
      params = null;
    }
    let type = req.body?.type;
    if (type === 'CUSTOM' && params && typeof params.type === 'string') {
      type = params.type;
    }
    const result =
      params === null
        ? { ok: false, code: 'BAD_PARAMS' }
        : triggerEvent(ctx, {
            type,
            params,
            target: req.body?.target,
            ttlMin: Number.parseInt(req.body?.ttlMin ?? '', 10),
          });
    const flash = result.ok
      ? `<div class="notice">Event <code>${esc(result.id)}</code> gesendet — sofort zugestellt an ${result.pushed} Online-Client(s).</div>`
      : `<div class="err">Fehler: ${esc(result.code)}</div>`;
    res.status(result.ok ? 200 : 400).type('html').send(eventsPage(ctx, { flash }));
  });

  // Unbekannte Panel-Pfade → Dashboard (kein Leak über 404-Unterschiede).
  app.get('/panel/*', (req, res) => res.redirect(303, '/panel/'));
  ctx.log.info?.('[panel] Webpanel aktiv unter /panel (Login erforderlich)');
}

export { layout };
