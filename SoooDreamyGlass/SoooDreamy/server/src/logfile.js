import { appendFileSync, mkdirSync, readdirSync, unlinkSync } from 'node:fs';
import path from 'node:path';

const LOG_FILE_RE = /^server-\d{4}-\d{2}-\d{2}\.log$/;

/**
 * Built-in daily log rotation (`LOG_FILE=1`): a long-running service must not
 * depend on stdout being captured — after a crash the console is gone, and a
 * months-old redirect file eats the disk. One file per (UTC) day under
 * `<dataDir>/logs/`, the newest `keep` files survive. Synchronous appends keep
 * lines ordered and are cheap at this log volume; any I/O error is swallowed —
 * logging must never take the server down.
 */
export function createDailyLogWriter({ dir, keep = 14, now = () => new Date() }) {
  try {
    mkdirSync(dir, { recursive: true });
  } catch {}
  let currentDay = null;
  let currentFile = null;

  function prune() {
    let names;
    try {
      names = readdirSync(dir).filter((name) => LOG_FILE_RE.test(name)).sort();
    } catch {
      return;
    }
    for (const old of names.slice(0, Math.max(0, names.length - keep))) {
      try {
        unlinkSync(path.join(dir, old));
      } catch {}
    }
  }

  return {
    write(line) {
      try {
        const day = now().toISOString().slice(0, 10);
        const rolled = day !== currentDay;
        if (rolled) {
          currentDay = day;
          currentFile = path.join(dir, `server-${day}.log`);
        }
        appendFileSync(currentFile, `${line}\n`, 'utf8');
        if (rolled) prune();
      } catch {}
    },
    currentFile: () => currentFile,
  };
}
