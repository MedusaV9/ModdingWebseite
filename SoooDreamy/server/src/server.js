import os from 'node:os';
import { createApp, DEFAULT_DATA_DIR } from './app.js';

const PORT = Number(process.env.PORT ?? 4321);
const HOST = process.env.HOST ?? '0.0.0.0';
const DATA_DIR = process.env.DATA_DIR || DEFAULT_DATA_DIR;

const log = (...args) => console.log(new Date().toISOString(), ...args);

function lanAddress() {
  for (const addrs of Object.values(os.networkInterfaces())) {
    for (const addr of addrs ?? []) {
      if (addr.family === 'IPv4' && !addr.internal) return addr.address;
    }
  }
  return null;
}

const app = await createApp({ dataDir: DATA_DIR, log });

app.server.listen(PORT, HOST, () => {
  const { port } = app.server.address();
  const lan = lanAddress();
  console.log('');
  console.log(`  💌 SoooDreamy server ready`);
  console.log(`     Local:  http://localhost:${port}`);
  if (lan) console.log(`     LAN:    http://${lan}:${port}   ← enter this in the iOS app (Settings → Server)`);
  console.log(`     Data:   ${DATA_DIR}`);
  console.log('');
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
