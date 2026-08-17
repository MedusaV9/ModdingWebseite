import os from 'node:os';
import path from 'node:path';
import { format } from 'node:util';
import QRCode from 'qrcode';
import { createApp, DEFAULT_DATA_DIR, transportSecurityFromEnv } from './app.js';
import { createDailyLogWriter } from './logfile.js';

try { process.loadEnvFile?.(); } catch {}

const PORT = Number(process.env.PORT ?? 4321);
const HOST = process.env.HOST ?? '0.0.0.0';
const DATA_DIR = process.env.DATA_DIR || DEFAULT_DATA_DIR;

// LOG_FILE=1: additionally write logs to DATA_DIR/logs/server-YYYY-MM-DD.log
// (daily rotation, newest 14 kept) — see src/logfile.js.
const fileLog = process.env.LOG_FILE === '1'
  ? createDailyLogWriter({ dir: path.join(DATA_DIR, 'logs') })
  : null;

const log = (...args) => {
  console.log(new Date().toISOString(), ...args);
  fileLog?.write(`${new Date().toISOString()} ${format(...args)}`);
};

function lanAddress() {
  for (const addrs of Object.values(os.networkInterfaces())) {
    for (const addr of addrs ?? []) {
      if (addr.family === 'IPv4' && !addr.internal) return addr.address;
    }
  }
  return null;
}

const transport = transportSecurityFromEnv();
const app = await createApp({
  dataDir: DATA_DIR,
  log,
  allowInsecureHttp: transport.allowInsecureHttp,
  allowInsecurePrivateLAN: transport.allowInsecurePrivateLAN,
});

/** Prints a framed box; the admin password must be easy to spot in the console. */
function printBox(lines) {
  const width = Math.max(...lines.map((line) => line.length));
  console.log(`  ╭─${'─'.repeat(width)}─╮`);
  for (const line of lines) console.log(`  │ ${line.padEnd(width)} │`);
  console.log(`  ╰─${'─'.repeat(width)}─╯`);
}

app.server.listen(PORT, HOST, async () => {
  const { port } = app.server.address();
  const lan = lanAddress();
  console.log('');
  console.log(`  💌 SoooDreamy server ready`);
  console.log(`     Local:  http://localhost:${port}`);
  if (lan) console.log(`     LAN:    http://${lan}:${port}   ← enter this in the iOS app (Settings → Server)`);
  console.log(`     Data:   ${DATA_DIR}`);
  if (transport.mode === 'http-default') {
    console.log('     Mode:   HTTP allowed — trusted networks only; traffic and tokens are not encrypted');
  } else if (transport.mode === 'private-http') {
    console.log('     Mode:   HTTP limited to loopback/private/Tailscale source addresses');
  } else {
    console.log('     Mode:   HTTPS required — expose this port only through a trusted TLS reverse proxy');
  }
  console.log('');
  printBox([
    'SoooDreamy Admin-Panel',
    '',
    `URL       http://localhost:${port}/admin`,
    ...(lan ? [`LAN       http://${lan}:${port}/admin`] : []),
    `Passwort  ${app.admin.password}`,
    '',
    'Wird bei jedem Serverstart neu generiert und nur hier angezeigt.',
    'Regenerated on every server start and shown only here.',
  ]);
  console.log('');
  // Phone-camera onboarding: scan → Safari opens the URL → copy it into the
  // app (Settings → Server). NO_QR=1 keeps log files clean.
  if (process.env.NO_QR !== '1') {
    const url = `http://${lan ?? 'localhost'}:${port}`;
    try {
      const qr = await QRCode.toString(url, { type: 'terminal', small: true });
      console.log(qr.replace(/^/gm, '  '));
      console.log(`  ↑ Mit der Handy-Kamera scannen → ${url} (ausblenden: NO_QR=1)`);
      console.log('');
    } catch {
      // A failed QR render must never block the start banner.
    }
  }
});

app.server.on('error', (err) => {
  console.error('Server error:', err.message);
  process.exit(1);
});

let shuttingDown = false;
async function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log(`\n${signal} received — flushing data and shutting down…`);
  try {
    await app.close();
    console.log('Data flushed. Bye! 💌');
    process.exit(0);
  } catch (err) {
    console.error('Error during shutdown:', err);
    process.exit(1);
  }
}
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));

// Never let a stray error take the whole server (and the couple's data) down.
process.on('uncaughtException', (err) => log('uncaughtException', err));
process.on('unhandledRejection', (err) => log('unhandledRejection', err));
