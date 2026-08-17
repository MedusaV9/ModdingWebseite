import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { existsSync, rmSync, mkdirSync } from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { sleep } from './util.mjs';

const execFileAsync = promisify(execFile);

const TMUX_CONF = '/exec-daemon/tmux.portal.conf';
const SERVER_DIR = path.resolve(fileURLToPath(new URL('.', import.meta.url)), '../../../server');

function tmuxArgs(args) {
  return existsSync(TMUX_CONF) ? ['-f', TMUX_CONF, ...args] : args;
}

async function tmux(...args) {
  return execFileAsync('tmux', tmuxArgs(args));
}

async function tmuxSafe(...args) {
  try {
    return await tmux(...args);
  } catch {
    return null;
  }
}

/**
 * Controls the DEDICATED arena server in tmux session `arena-server`
 * (port 4399, DATA_DIR /tmp/arena-data by default) so restarts and crashes
 * can be simulated freely without touching the long-lived dev server on 4321.
 *
 * The pane runs `exec env … node src/server.js`, so the pane PID *is* the
 * node PID — `crash()` can SIGKILL it precisely (no pkill, no name matching).
 */
export class ServerControl {
  constructor({
    session = 'arena-server',
    port = 4399,
    dataDir = '/tmp/arena-data',
    minLeadSeconds = 2,
    sweepSeconds = 1,
  } = {}) {
    this.session = session;
    this.port = port;
    this.dataDir = dataDir;
    this.minLeadSeconds = minLeadSeconds;
    this.sweepSeconds = sweepSeconds;
    this.baseUrl = `http://127.0.0.1:${port}`;
    this.logFile = path.join(dataDir, 'arena-server.log');
  }

  /** Wipes DATA_DIR (fresh world) and (re)creates the tmux session. */
  async startFresh() {
    // '=': EXACT session match — without it tmux falls back to prefix
    // matching and `kill-session -t arena-server` would happily kill a
    // parallel `arena-server-b` when its own session is already gone.
    await tmuxSafe('kill-session', '-t', `=${this.session}`);
    rmSync(this.dataDir, { recursive: true, force: true });
    mkdirSync(this.dataDir, { recursive: true });
    await this.start();
  }

  /** Starts the server in tmux (existing DATA_DIR kept — restart semantics). */
  async start() {
    await tmuxSafe('kill-session', '-t', `=${this.session}`);
    const env = [
      `PORT=${this.port}`,
      'HOST=127.0.0.1',
      `DATA_DIR=${this.dataDir}`,
      'NO_QR=1',
      'LOG_FILE=0',
      'BACKUP_INTERVAL_MINUTES=0',
      `POST_MIN_LEAD_SECONDS=${this.minLeadSeconds}`,
      `POST_DELIVERY_INTERVAL_SECONDS=${this.sweepSeconds}`,
    ].join(' ');
    const command = `exec env ${env} node src/server.js >> ${this.logFile} 2>&1`;
    await tmux('new-session', '-d', '-s', this.session, '-c', SERVER_DIR, command);
    await this.waitHealthy();
  }

  /** Hard-kills the node process (SIGKILL) — simulates a crash/power loss. */
  async crash() {
    const { stdout } = await tmux('list-panes', '-t', `=${this.session}`, '-F', '#{pane_pid}');
    const pid = Number(stdout.trim().split('\n')[0]);
    if (!Number.isInteger(pid) || pid <= 1) throw new Error(`refusing to kill pid "${stdout.trim()}"`);
    process.kill(pid, 'SIGKILL');
    // The pane dies with its process; the session follows (single window).
    await this.waitDown();
  }

  async health() {
    return new Promise((resolve) => {
      const req = http.get({ host: '127.0.0.1', port: this.port, path: '/api/health', timeout: 2_000 }, (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => {
          try {
            resolve({ status: res.statusCode, body: JSON.parse(Buffer.concat(chunks).toString('utf8')) });
          } catch {
            resolve({ status: res.statusCode, body: null });
          }
        });
      });
      req.on('timeout', () => { req.destroy(); resolve(null); });
      req.on('error', () => resolve(null));
    });
  }

  async waitHealthy(timeoutMs = 20_000) {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      const res = await this.health();
      if (res?.status === 200 && res.body?.ok === true) return res.body;
      await sleep(250);
    }
    throw new Error(`arena server on :${this.port} did not become healthy within ${timeoutMs} ms`);
  }

  async waitDown(timeoutMs = 10_000) {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      const res = await this.health();
      if (res === null) return;
      await sleep(150);
    }
    throw new Error('arena server still answering after crash()');
  }

  async stop() {
    await tmuxSafe('kill-session', '-t', `=${this.session}`);
  }
}
