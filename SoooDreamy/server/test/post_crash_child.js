import { createApp } from '../src/app.js';
import { postDeliverySweep } from '../src/post.js';

/**
 * Child process for post_crash.test.js (FullRelease R1-C): a real app on
 * DATA_DIR whose delivery sweep is driven via IPC, with an injectable crash
 * point. `{type:'sweep', nowMs, crashPoint?}` runs one sweep; when the sweep
 * reaches `crashPoint` ('before-persist' | 'after-persist') the process
 * SIGKILLs ITSELF — an uncatchable, un-flushed death exactly inside the
 * delivery transition, precisely the window the fault-injection eval hit.
 */
const app = await createApp({
  dataDir: process.env.DATA_DIR,
  backupIntervalMinutes: 0,
  weekReviewPushIntervalMinutes: 0,
  postDeliveryIntervalSeconds: 0,
  pushProvider: null,
});

app.server.listen(0, '::1', () => {
  process.send?.({ type: 'ready', port: app.server.address().port });
});

process.on('message', (message) => {
  if (message?.type !== 'sweep') return;
  const delivered = postDeliverySweep({
    store: app.store,
    realtime: app.realtime,
    push: app.push,
    now: new Date(message.nowMs ?? Date.now()),
    testCrashPoint: message.crashPoint
      ? (phase) => {
        if (phase === message.crashPoint) process.kill(process.pid, 'SIGKILL');
      }
      : null,
  });
  process.send?.({ type: 'swept', delivered });
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
