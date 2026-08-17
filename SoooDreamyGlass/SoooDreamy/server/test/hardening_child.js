import { createApp } from '../src/app.js';

const app = await createApp({
  dataDir: process.env.DATA_DIR,
  backupIntervalMinutes: 0,
  weekReviewPushIntervalMinutes: 0,
});

app.server.listen(0, '::1', () => {
  process.send?.({ type: 'ready', port: app.server.address().port });
});

let closing = false;
async function close() {
  if (closing) return;
  closing = true;
  await app.close();
  process.exit(0);
}

process.on('SIGINT', close);
process.on('SIGTERM', close);
