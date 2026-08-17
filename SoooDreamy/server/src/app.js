import http from 'node:http';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { Store } from './store.js';
import { Realtime } from './realtime.js';
import { createRouter } from './router.js';
import {
  cleanupSessions,
  RateLimiter,
  sanitizeLogValue,
  upgradeLegacyTokens,
} from './security.js';
import { ApnsProvider } from './apns.js';
import { PushService } from './push.js';
import { migrateGameStore } from './game-migrations.js';
import { startBackupScheduler } from './backup.js';
import { startWeekReviewArrivalScheduler } from './weekreview.js';
import { startPostDeliveryScheduler } from './post.js';
import { DEV_COCKPIT_HTML } from './dev-cockpit.js';
import { createAdminPanel } from './admin/admin.js';

const pkg = JSON.parse(await readFile(new URL('../package.json', import.meta.url), 'utf8'));

/** Default data dir: <server package dir>/data (independent of process.cwd()). */
export const DEFAULT_DATA_DIR = fileURLToPath(new URL('../data', import.meta.url));

export function transportSecurityFromEnv(env = process.env) {
  if (env.REQUIRE_HTTPS === '1') {
    return { allowInsecureHttp: false, allowInsecurePrivateLAN: false, mode: 'https-required' };
  }
  if (env.ALLOW_HTTP_PRIVATE_LAN === '1') {
    return { allowInsecureHttp: false, allowInsecurePrivateLAN: true, mode: 'private-http' };
  }
  return { allowInsecureHttp: true, allowInsecurePrivateLAN: false, mode: 'http-default' };
}

/**
 * Creates the SoooDreamy app: an http.Server (NOT yet listening) with the REST
 * router and the /ws WebSocket endpoint attached, backed by a JSON-file store.
 *
 * @param {{
 *   dataDir?: string,
 *   log?: (...args: unknown[]) => void,
 *   allowInsecureHttp?: boolean,
 *   allowInsecurePrivateLAN?: boolean,
 *   trustProxy?: boolean,
 *   rateLimiter?: RateLimiter,
 *   maxCouples?: number,
 *   mediaQuotaBytes?: number,
 *   pushProvider?: {send: (request: object) => Promise<void>} | null,
 *   pushRetryIntervalMs?: number,
 *   pushRetryBaseMs?: number,
 *   devCockpit?: boolean,
 * }} [options]
 * @returns {Promise<{server: import('node:http').Server, store: Store, realtime: Realtime, push: PushService, close: () => Promise<void>}>}
 */
export async function createApp({
  dataDir = DEFAULT_DATA_DIR,
  log = () => {},
  allowInsecureHttp,
  allowInsecurePrivateLAN,
  trustProxy = process.env.TRUST_PROXY === '1',
  rateLimiter = new RateLimiter(),
  maxCouples = Number.isInteger(Number(process.env.MAX_COUPLES))
    ? Math.max(1, Number(process.env.MAX_COUPLES))
    : undefined,
  mediaQuotaBytes = Number.isFinite(Number(process.env.MEDIA_QUOTA_BYTES))
    ? Math.max(0, Number(process.env.MEDIA_QUOTA_BYTES))
    : undefined,
  pushProvider,
  pushRetryIntervalMs = Number(process.env.PUSH_RETRY_INTERVAL_MS) > 0
    ? Number(process.env.PUSH_RETRY_INTERVAL_MS)
    : 10_000,
  pushRetryBaseMs = Number(process.env.PUSH_RETRY_BASE_MS) > 0
    ? Number(process.env.PUSH_RETRY_BASE_MS)
    : 5_000,
  devCockpit = process.env.SOOODREAMY_DEV_COCKPIT === '1',
  backupIntervalMinutes = Number.isFinite(Number(process.env.BACKUP_INTERVAL_MINUTES))
    ? Math.max(0, Number(process.env.BACKUP_INTERVAL_MINUTES))
    : 60,
  backupIncludeMedia = process.env.BACKUP_INCLUDE_MEDIA !== '0',
  weekReviewPushIntervalMinutes = Number.isFinite(Number(process.env.WEEKREVIEW_PUSH_INTERVAL_MINUTES))
    ? Math.max(0, Number(process.env.WEEKREVIEW_PUSH_INTERVAL_MINUTES))
    : 5,
  postDeliveryIntervalSeconds = Number.isFinite(Number(process.env.POST_DELIVERY_INTERVAL_SECONDS))
    ? Math.max(0, Number(process.env.POST_DELIVERY_INTERVAL_SECONDS))
    : 30,
  auditMaxBytes = Number(process.env.AUDIT_MAX_BYTES) > 0
    ? Number(process.env.AUDIT_MAX_BYTES)
    : 5 * 1024 * 1024,
  auditRetentionFiles = Number(process.env.AUDIT_RETENTION_FILES) > 0
    ? Math.floor(Number(process.env.AUDIT_RETENTION_FILES))
    : 30,
} = {}) {
  if (allowInsecureHttp === undefined && allowInsecurePrivateLAN === undefined) {
    ({ allowInsecureHttp, allowInsecurePrivateLAN } = transportSecurityFromEnv());
  } else {
    allowInsecureHttp ??= false;
    allowInsecurePrivateLAN ??= false;
  }
  // Ring buffer feeding the admin panel's log tail (last 200 lines shown).
  const logBuffer = [];
  const safeLog = (...values) => {
    const clean = values.map(sanitizeLogValue);
    logBuffer.push({ at: new Date().toISOString(), line: clean.join(' ') });
    if (logBuffer.length > 500) logBuffer.splice(0, logBuffer.length - 500);
    log(...clean);
  };
  const store = await new Store({
    dataDir,
    log: safeLog,
    mediaQuotaBytes,
    diskWarnBytes: Number(process.env.DISK_WARN_MB) > 0
      ? Number(process.env.DISK_WARN_MB) * 1024 * 1024
      : undefined,
    diskStopBytes: Number(process.env.DISK_STOP_MB) > 0
      ? Number(process.env.DISK_STOP_MB) * 1024 * 1024
      : undefined,
  }).init();
  const upgradedLegacyTokens = upgradeLegacyTokens(store);
  if (upgradedLegacyTokens > 0) {
    safeLog(`security: upgraded ${upgradedLegacyTokens} legacy session proof(s)`);
  }
  const cleanSecurityRecords = () => {
    const removed = cleanupSessions(store);
    if (removed > 0) safeLog(`security: removed ${removed} expired or excess session proof(s)`);
  };
  cleanSecurityRecords();
  const sessionCleanupTimer = setInterval(cleanSecurityRecords, 15 * 60_000);
  sessionCleanupTimer.unref?.();
  migrateGameStore({ store, log: safeLog });

  // Full disks kill JSON stores silently — warn at boot and hourly, long
  // before store.saveMedia starts refusing uploads (507 disk_full).
  const diskCheck = async () => {
    const disk = await store.diskStatus();
    if (!disk?.warn) return;
    const freeMb = Math.round(disk.freeBytes / 1024 / 1024);
    safeLog(
      disk.stop
        ? `⚠️  disk: only ${freeMb} MB free — media uploads are PAUSED (507 disk_full) until space is freed`
        : `⚠️  disk: only ${freeMb} MB free on the data-dir filesystem — time to clean up or grow the disk`,
    );
  };
  void diskCheck();
  const diskTimer = setInterval(() => { void diskCheck(); }, 60 * 60_000);
  diskTimer.unref?.();
  const security = { allowInsecurePrivateLAN, allowInsecureHttp, trustProxy };
  const realtime = new Realtime({ store, log: safeLog, security });
  const provider = pushProvider === undefined
    ? await ApnsProvider.fromEnvironment({ log: safeLog })
    : pushProvider;
  const push = new PushService({ provider, log: safeLog, retryBaseMs: pushRetryBaseMs });
  push.start({ store, intervalMs: pushRetryIntervalMs });
  // v10.1 operator web panel at /admin: per-boot password (console only),
  // cookie sessions, audit log — see src/admin/admin.js + docs/ADMIN-PANEL.md.
  const admin = createAdminPanel({
    store,
    realtime,
    push,
    rateLimiter,
    log: safeLog,
    logBuffer,
    config: {
      name: 'SoooDreamy',
      version: pkg.version,
      ...security,
      backupIntervalMinutes,
      backupIncludeMedia,
      auditMaxBytes,
      auditRetentionFiles,
    },
  });
  const handle = createRouter({
    store,
    realtime,
    push,
    admin,
    log: safeLog,
    rateLimiter,
    config: {
      name: 'SoooDreamy',
      version: pkg.version,
      ...security,
      maxCouples,
    },
  });

  // Sunday-evening „Eure Woche ist fertig ✨" arrival push, couple-local
  // (couple.timezone / server clock), deduped per ISO week. 0 minutes disables.
  const stopWeekReviewPush = startWeekReviewArrivalScheduler({
    store,
    push,
    log: safeLog,
    intervalMinutes: weekReviewPushIntervalMinutes,
  });

  // FullRelease P6-B: Zeitpost delivery sweep — due scheduled posts become
  // normal touch/pulse/note events + push + WS fanout. 0 seconds disables.
  const stopPostDelivery = startPostDeliveryScheduler({
    store,
    realtime,
    push,
    log: safeLog,
    intervalSeconds: postDeliveryIntervalSeconds,
  });

  // v6.1: rotating on-server backups (docs/BACKUP.md). 0 minutes disables.
  const stopBackups = startBackupScheduler({
    store,
    dataDir,
    intervalMinutes: backupIntervalMinutes,
    keepLast: Number(process.env.BACKUP_KEEP_LAST) > 0 ? Number(process.env.BACKUP_KEEP_LAST) : 10,
    keepHourly: Number(process.env.BACKUP_KEEP_HOURLY) > 0 ? Number(process.env.BACKUP_KEEP_HOURLY) : 48,
    keepDaily: Number(process.env.BACKUP_KEEP_DAILY) > 0 ? Number(process.env.BACKUP_KEEP_DAILY) : 14,
    includeMedia: backupIncludeMedia,
    log: safeLog,
  });

  const server = http.createServer((req, res) => {
    const path = new URL(req.url ?? '/', 'http://localhost').pathname;
    if (req.method === 'GET' && path === '/dev/cockpit' && devCockpit) {
      const body = Buffer.from(DEV_COCKPIT_HTML);
      res.writeHead(200, {
        'content-type': 'text/html; charset=utf-8',
        'content-length': body.length,
        'cache-control': 'no-store',
        'content-security-policy': "default-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'",
        'x-content-type-options': 'nosniff',
      });
      res.end(body);
      return;
    }
    // handle() catches everything itself; this is a last-resort safety net.
    handle(req, res).catch((err) => {
      safeLog('http: fatal handler error', err);
      res.destroy();
    });
  });
  realtime.attach(server);

  let closed = false;
  async function close() {
    if (closed) return;
    closed = true;
    clearInterval(diskTimer);
    clearInterval(sessionCleanupTimer);
    stopWeekReviewPush();
    stopPostDelivery();
    await stopBackups();
    realtime.close();
    if (server.listening) {
      server.closeAllConnections?.();
      await new Promise((resolve) => server.close(() => resolve()));
    }
    await admin.close();
    await push.close();
    await store.close();
  }

  return { server, store, realtime, push, admin, close };
}
