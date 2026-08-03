import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { Store } from './store.js';
import { Realtime } from './realtime.js';
import { createRouter } from './router.js';

const pkg = JSON.parse(await readFile(new URL('../package.json', import.meta.url), 'utf8'));

/** Default data dir: <server package dir>/data (independent of process.cwd()). */
export const DEFAULT_DATA_DIR = fileURLToPath(new URL('../data', import.meta.url));

/**
 * Creates the SoooDreamy app: an http.Server (NOT yet listening) with the REST
 * router and the /ws WebSocket endpoint attached, backed by a JSON-file store.
 *
 * @param {{dataDir?: string, log?: (...args: unknown[]) => void}} [options]
 * @returns {Promise<{server: import('node:http').Server, store: Store, realtime: Realtime, close: () => Promise<void>}>}
 */
export async function createApp({ dataDir = DEFAULT_DATA_DIR, log = () => {} } = {}) {
  const store = await new Store({ dataDir, log }).init();
  const realtime = new Realtime({ store, log });
  const handle = createRouter({ store, realtime, log, config: { name: 'SoooDreamy', version: pkg.version } });

  const server = http.createServer((req, res) => {
    // handle() catches everything itself; this is a last-resort safety net.
    handle(req, res).catch((err) => {
      log('http: fatal handler error', err);
      res.destroy();
    });
  });
  realtime.attach(server);

  let closed = false;
  async function close() {
    if (closed) return;
    closed = true;
    realtime.close();
    if (server.listening) {
      server.closeAllConnections?.();
      await new Promise((resolve) => server.close(() => resolve()));
    }
    await store.close();
  }

  return { server, store, realtime, close };
}
