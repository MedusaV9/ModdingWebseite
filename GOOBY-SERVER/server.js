// GOOBY-SERVER Entry (Doc C §2.1): EIN Node-Prozess, EIN Port — express (REST + Panel)
// und ws (Lobby-Protokoll auf /ws) teilen denselben HTTP-Listener. Kein Cluster, kein
// Docker, kein zweiter Port: AMP "Node.js App Runner" startet `node server.js`, fertig.
// Graceful Shutdown auf SIGTERM/SIGINT: Sockets bekommen GOING_DOWN, Storage flusht.

import http from 'node:http';
import { pathToFileURL } from 'node:url';
import express from 'express';
import { loadConfig } from './src/config.js';
import { Storage } from './src/storage.js';
import { Buckets } from './src/ratelimit.js';
import { Hub } from './src/ws.js';
import { MODULES } from './src/modules.js';
import { register as registerPanel } from './webpanel/index.js';

export function createServer(env = process.env, overrides = {}) {
  const cfg = { ...loadConfig(env), ...overrides.cfg };
  const clock = overrides.clock || { now: () => Date.now() };
  const store = new Storage(cfg.dataDir, { flushMs: overrides.flushMs ?? 10_000 });

  const app = express();
  app.disable('x-powered-by');
  // Bewusst KEINE CORS-Header: Clients sind Godot/Node, kein Browser-Cross-Origin nötig.

  const ctx = {
    cfg,
    clock,
    store,
    app,
    buckets: new Buckets(() => clock.now()),
    players: store.collection('players', {}),
    byCode: new Map(),
    hub: null,
    rooms: null,
    log: console,
    startedAt: clock.now(),
  };
  for (const [deviceId, p] of Object.entries(ctx.players)) {
    ctx.byCode.set(p.friendCode, deviceId);
  }

  ctx.hub = new Hub(ctx);

  app.get('/health', (req, res) => {
    res.json({
      ok: true,
      uptime: Math.round((clock.now() - ctx.startedAt) / 1000),
      clients: ctx.hub.conns.size,
    });
  });

  // Panel zuerst (fail-closed-Gate), dann Feature-Module (REST + WS-Handler).
  registerPanel(ctx);
  for (const mod of MODULES) mod.register(ctx);

  app.use((req, res) => res.status(404).json({ ok: false, code: 'NOT_FOUND' }));
  // Fehler-Handler: nie Stacktraces an Clients leaken.
  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, next) => {
    if (err?.type === 'entity.too.large') {
      return res.status(413).json({ ok: false, code: 'PAYLOAD_TOO_LARGE' });
    }
    if (err?.type?.startsWith?.('entity') || err?.status === 400) {
      return res.status(400).json({ ok: false, code: 'BAD_BODY' });
    }
    ctx.log.error('[http]', err);
    res.status(500).json({ ok: false, code: 'INTERNAL' });
  });

  const httpServer = http.createServer(app);
  ctx.hub.attach(httpServer);

  return {
    ctx,
    httpServer,
    listen(port = cfg.port, host) {
      return new Promise((resolve) => {
        httpServer.listen(port, host, () => resolve(httpServer.address().port));
      });
    },
    async stop() {
      ctx.hub.closeAll('SHUTDOWN');
      // Kurze Gnadenfrist, damit GOING_DOWN + Close-Frames noch rausgehen.
      await new Promise((resolve) => setTimeout(resolve, 50));
      httpServer.closeAllConnections?.();
      await new Promise((resolve) => httpServer.close(resolve));
      store.close();
    },
  };
}

const isMain =
  process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;

if (isMain) {
  const srv = createServer();
  const { cfg } = srv.ctx;
  srv.listen().then((port) => {
    console.log(`[gooby-server] läuft auf Port ${port} (http + ws unter /ws)`);
    console.log(`[gooby-server] Daten: ${srv.ctx.store.dataDir}`);
    console.log(
      cfg.adminPassword
        ? `[gooby-server] Panel: http://localhost:${port}/panel/`
        : '[gooby-server] Panel: DEAKTIVIERT (GOOBY_ADMIN_PASSWORD fehlt)'
    );
  });
  let stopping = false;
  const shutdown = (signal) => {
    if (stopping) return;
    stopping = true;
    console.log(`[gooby-server] ${signal} — fahre herunter (Storage-Flush, GOING_DOWN)…`);
    srv.stop().then(() => process.exit(0));
    setTimeout(() => process.exit(0), 3000).unref();
  };
  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
}
