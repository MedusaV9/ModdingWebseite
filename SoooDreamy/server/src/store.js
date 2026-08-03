import { mkdir, readFile, writeFile, rename, unlink } from 'node:fs/promises';
import path from 'node:path';

const DEBOUNCE_MS = 500;

/**
 * Single-JSON-file store with debounced atomic writes (tmp file + rename)
 * plus a media directory for raw photo/voice files.
 *
 * store.json shape: { version, couples: {<coupleId>: {...}}, tokens: {<token>: {coupleId, memberId}} }
 */
export class Store {
  constructor({ dataDir, log = () => {} }) {
    this.dataDir = dataDir;
    this.log = log;
    this.file = path.join(dataDir, 'store.json');
    this.data = { version: 1, couples: {}, tokens: {} };
    this.dirty = false;
    this.timer = null;
    this.writeChain = Promise.resolve();
    this.closed = false;
  }

  async init() {
    await mkdir(path.join(this.dataDir, 'media', 'photos'), { recursive: true });
    await mkdir(path.join(this.dataDir, 'media', 'voice'), { recursive: true });
    try {
      const parsed = JSON.parse(await readFile(this.file, 'utf8'));
      this.data = { version: 1, couples: parsed.couples ?? {}, tokens: parsed.tokens ?? {} };
    } catch (err) {
      if (err.code !== 'ENOENT') {
        // Never overwrite an unreadable store silently — keep a backup around.
        const backup = `${this.file}.corrupt-${Date.now()}`;
        this.log(`store: ${this.file} unreadable (${err.message}); starting fresh, original kept at ${backup}`);
        try {
          await rename(this.file, backup);
        } catch {
          /* ignore */
        }
      }
    }
    return this;
  }

  /** Marks the store changed and schedules a debounced background save. */
  markDirty() {
    this.dirty = true;
    if (this.closed || this.timer) return;
    this.timer = setTimeout(() => {
      this.timer = null;
      this.flush().catch((err) => this.log('store: background save failed', err));
    }, DEBOUNCE_MS);
    this.timer.unref?.();
  }

  /** Writes pending changes immediately (used on shutdown). */
  async flush() {
    if (this.timer) {
      clearTimeout(this.timer);
      this.timer = null;
    }
    if (this.dirty) {
      this.dirty = false;
      this.writeChain = this.writeChain.catch(() => {}).then(() => this.#writeNow());
    }
    return this.writeChain;
  }

  async #writeNow() {
    const tmp = `${this.file}.tmp`;
    await writeFile(tmp, JSON.stringify(this.data, null, 2), 'utf8');
    await rename(tmp, this.file);
  }

  async close() {
    if (this.closed) return;
    this.closed = true;
    await this.flush();
  }

  mediaPath(kind, filename) {
    return path.join(this.dataDir, 'media', kind, filename);
  }

  async saveMedia(kind, filename, buf) {
    await writeFile(this.mediaPath(kind, filename), buf);
  }

  async deleteMedia(kind, filename) {
    try {
      await unlink(this.mediaPath(kind, filename));
    } catch (err) {
      if (err.code !== 'ENOENT') this.log(`store: could not delete media ${kind}/${filename}`, err);
    }
  }
}
