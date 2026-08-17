import {
  closeSync,
  fsyncSync,
  openSync,
  renameSync,
  writeSync,
} from 'node:fs';
import { mkdir, open, readFile, rename, unlink, readdir, stat, statfs } from 'node:fs/promises';
import path from 'node:path';
import { acquireDataDirLock } from './data-lock.js';
import { httpError, sha256Hex } from './util.js';

const DEBOUNCE_MS = 500;
const STORE_FORMAT = 'segmented-v1';
const SEGMENT_FORMAT = 'segment-v2';
const JOURNAL_FORMAT = 'wal-v1';
const JOURNAL_FILE = 'store.wal';
const JOURNAL_RECOVERY_RECORDS = 1_024;
const DEFAULT_MEDIA_QUOTA_BYTES = 2 * 1024 * 1024 * 1024;
// Disk guard rails: warn early, and refuse media writes before a full disk
// can corrupt the JSON store mid-write (DISK_WARN_MB / DISK_STOP_MB env).
const DEFAULT_DISK_WARN_BYTES = 2 * 1024 * 1024 * 1024; // 2 GB
const DEFAULT_DISK_STOP_BYTES = 500 * 1024 * 1024; // 500 MB

/**
 * In-memory document store with atomically persisted per-couple segments.
 * `store.json` is a small token/index manifest; each couple lives in its own
 * compact JSON file so one busy couple no longer rewrites every other couple.
 *
 * Corruption hardening (v6.1):
 * - every write is atomic (tmp + rename) and keeps the previous good file
 *   as `<file>.bak`, so a torn write can always fall back one generation
 * - segments carry a SHA-256 checksum envelope ({format:"segment-v2",
 *   sha256, couple}) that is verified on load (bit-rot / manual edits)
 * - unreadable files fall back to their `.bak`; if both are broken they are
 *   MOVED to `<dataDir>/quarantine/` (never deleted, never crash the boot)
 *   and the affected couple is reported via `quarantinedCoupleIds`
 * - a lost/corrupt manifest is rebuilt from the segment files (tokens are
 *   gone in that case — members re-attach via /api/couples/rejoin)
 *
 * Legacy single-file stores (v1.x) are migrated losslessly during startup.
 */
export class Store {
  constructor({
    dataDir,
    log = () => {},
    mediaQuotaBytes = DEFAULT_MEDIA_QUOTA_BYTES,
    diskWarnBytes = DEFAULT_DISK_WARN_BYTES,
    diskStopBytes = DEFAULT_DISK_STOP_BYTES,
    dataDirLock = null,
  }) {
    this.dataDir = dataDir;
    this.log = log;
    this.file = path.join(dataDir, 'store.json');
    this.journalFile = path.join(dataDir, JOURNAL_FILE);
    this.segmentsDir = path.join(dataDir, 'segments');
    this.quarantineDir = path.join(dataDir, 'quarantine');
    this.mediaQuotaBytes = mediaQuotaBytes;
    this.diskWarnBytes = diskWarnBytes;
    this.diskStopBytes = diskStopBytes;
    this.dataDirLock = dataDirLock;
    this.ownsDataDirLock = dataDirLock === null;
    this.data = { version: 2, couples: {}, tokens: {}, qrNonces: {}, linkCodes: {} };
    this.dirty = false;
    this.timer = null;
    this.writeChain = Promise.resolve();
    this.closed = false;
    this.journalFd = null;
    this.journalSeq = 0;
    this.journalEntries = [];
    this.journalCoupleFingerprints = new Map();
    this.journalRootFingerprint = '';
    this.segmentFingerprints = new Map();
    this.lastCompaction = null;
    this.statsCache = null;
    this.mediaBytesUsed = 0;
    this.mediaBytesReserved = 0;
    this.mediaSlotReservations = new Map();
    /** Couples whose segment data was unrecoverable and moved to quarantine. */
    this.quarantinedCoupleIds = new Set();
    /** Log of quarantined files: [{file, reason, at, coupleId}] */
    this.quarantined = [];
  }

  async init() {
    if (this.ownsDataDirLock) {
      this.dataDirLock = await acquireDataDirLock(this.dataDir, { log: this.log });
    }
    try {
      return await this.#initLocked();
    } catch (err) {
      if (this.ownsDataDirLock) await this.dataDirLock?.release().catch(() => {});
      this.dataDirLock = null;
      throw err;
    }
  }

  async #initLocked() {
    await mkdir(this.dataDir, { recursive: true });
    await mkdir(this.segmentsDir, { recursive: true });
    await mkdir(path.join(this.dataDir, 'media', 'photos'), { recursive: true });
    await mkdir(path.join(this.dataDir, 'media', 'videos'), { recursive: true });
    await mkdir(path.join(this.dataDir, 'media', 'voice'), { recursive: true });
    await mkdir(path.join(this.dataDir, 'media', 'vault'), { recursive: true });
    this.mediaBytesUsed = (await directoryStats(path.join(this.dataDir, 'media'))).bytes;

    const manifest = await this.#loadManifest();
    let needsRewrite = false;
    this.recoveryMode = Boolean(manifest?.recovered);
    if (manifest?.format === STORE_FORMAT) {
      const couples = {};
      for (const [coupleId, segmentName] of Object.entries(manifest.couples ?? {})) {
        const safeName = path.basename(String(segmentName));
        const segment = await this.#loadSegment(safeName, coupleId);
        if (segment === null) {
          this.quarantinedCoupleIds.add(coupleId);
          this.recoveryMode = true;
          continue;
        }
        couples[coupleId] = segment.couple;
        if (segment.recovered) {
          needsRewrite = true;
          this.recoveryMode = true;
        } else this.segmentFingerprints.set(coupleId, segment.serialized);
      }
      this.data = {
        version: 2,
        couples,
        tokens: manifest.tokens ?? {},
        qrNonces: manifest.qrNonces ?? {},
        linkCodes: manifest.linkCodes ?? {},
      };
      if (this.recoveryMode) {
        needsRewrite ||= await this.#recoverUnindexedSegments(couples, manifest.couples ?? {});
      } else {
        await this.#removeOrphanSegments(new Set(Object.values(manifest.couples ?? {}).map(String)));
      }
      needsRewrite ||= Boolean(manifest.recovered || manifest.needsChecksum);
      this.journalSeq = Number.isSafeInteger(manifest.journalSeq) && manifest.journalSeq >= 0
        ? manifest.journalSeq
        : 0;
    } else if (manifest !== null) {
      // v1 stored every couple inline. Keep the exact logical objects and
      // compact them into v2 segments before serving the first request.
      this.data = {
        version: 2,
        couples: manifest.couples ?? {},
        tokens: manifest.tokens ?? {},
        qrNonces: {},
        linkCodes: {},
      };
      needsRewrite = true;
    }

    const replay = await this.#replayJournal(this.recoveryMode ? 0 : this.journalSeq);
    for (const coupleId of this.quarantinedCoupleIds) {
      if (this.data.couples[coupleId]) this.quarantinedCoupleIds.delete(coupleId);
    }
    this.#seedJournalFingerprints();
    this.#openJournal();
    if (replay.journalWasQuarantined) this.#appendJournalSnapshot({ force: true });
    if (needsRewrite || replay.applied > 0) {
      this.#scheduleCompaction();
      // Startup migration/recovery is complete only after the validated state
      // has reached the checksummed manifest and segment files. This keeps
      // Store.init() truthful for CLI callers and avoids serving through a
      // transient legacy/recovery layout.
      await this.flush();
    }
    return this;
  }

  #rootData() {
    return Object.fromEntries(Object.entries(this.data).filter(([key]) => key !== 'couples'));
  }

  #seedJournalFingerprints() {
    this.journalCoupleFingerprints = new Map(
      Object.entries(this.data.couples).map(([coupleId, couple]) => [coupleId, JSON.stringify(couple)]),
    );
    this.journalRootFingerprint = JSON.stringify(this.#rootData());
  }

  #openJournal() {
    if (this.journalFd !== null) return;
    try {
      this.journalFd = openSync(this.journalFile, 'a');
    } catch (err) {
      throw new Error(`store: cannot open write-ahead journal ${this.journalFile}: ${err.message}`, { cause: err });
    }
    fsyncSync(this.journalFd);
    // Persist the directory entry as well as the file. Repeating this on an
    // existing journal is cheap and makes the durability contract explicit.
    fsyncDirectorySync(this.dataDir);
  }

  async #replayJournal(baseSeq = this.journalSeq) {
    const nextSequenceBase = this.journalSeq;
    let raw;
    try {
      raw = await readFile(this.journalFile, 'utf8');
    } catch (err) {
      if (err.code === 'ENOENT') return { applied: 0, journalWasQuarantined: false };
      throw err;
    }
    let applied = 0;
    let journalWasQuarantined = false;
    const entries = [];
    let previousSeq = 0;
    for (const [index, line] of raw.split('\n').entries()) {
      if (line.length === 0) continue;
      try {
        const envelope = JSON.parse(line);
        validateJournalEnvelope(envelope);
        if (envelope.data.seq <= previousSeq) throw new Error('journal sequence is not strictly increasing');
        previousSeq = envelope.data.seq;
        entries.push(envelope);
      } catch (err) {
        this.log(`store: journal record ${index + 1} is invalid (${err.message}); preserving valid prefix`);
        await this.#quarantineFile(this.journalFile, `invalid write-ahead journal record ${index + 1}: ${err.message}`);
        journalWasQuarantined = true;
        break;
      }
    }

    this.journalSeq = Math.max(nextSequenceBase, ...entries.map((entry) => entry.data.seq), 0);
    for (const envelope of entries) {
      if (envelope.data.seq <= baseSeq) continue;
      const root = structuredClone(envelope.data.root);
      this.data = { ...root, couples: this.data.couples };
      for (const [coupleId, couple] of Object.entries(envelope.data.couples)) {
        if (couple === null) delete this.data.couples[coupleId];
        else this.data.couples[coupleId] = structuredClone(couple);
      }
      applied += 1;
    }
    this.journalEntries = journalWasQuarantined ? [] : entries;
    if (applied > 0) {
      this.log(`store: replayed ${applied} durable write-ahead journal record(s)`);
    }
    return { applied, journalWasQuarantined };
  }

  /**
   * Loads the manifest (or a legacy v1 inline store): store.json first, then
   * store.json.bak, then — as a last resort — an index rebuilt from the
   * segment files themselves (sessions are lost then; members re-attach via
   * /api/couples/rejoin). Returns null only for a truly fresh data dir;
   * broken files are quarantined, never deleted.
   */
  async #loadManifest() {
    let mainError = null;
    try {
      return parseManifest(await readFile(this.file, 'utf8'));
    } catch (err) {
      mainError = err;
    }
    const missing = mainError.code === 'ENOENT';
    if (!missing) {
      this.log(`store: ${this.file} unreadable (${mainError.message}); trying store.json.bak`);
    }
    let backupError = null;
    try {
      const parsed = parseManifest(await readFile(`${this.file}.bak`, 'utf8'));
      if (!missing) {
        await this.#quarantineFile(
          this.file,
          `invalid manifest (${mainError.message}); recovered from .bak`,
        );
      }
      this.log('store: manifest recovered from store.json.bak');
      return { ...parsed, recovered: true };
    } catch (err) {
      backupError = err;
    }
    const backupMissing = backupError?.code === 'ENOENT';
    if (!missing) await this.#quarantineFile(this.file, `invalid manifest (${mainError.message})`);
    if (!backupMissing) {
      await this.#quarantineFile(
        `${this.file}.bak`,
        `invalid manifest backup (${backupError?.message ?? 'unknown error'})`,
      );
    }
    if (missing && backupMissing && !(await this.#hasSegmentCandidates())) return null;
    this.log('store: rebuilding manifest from validated segment files and write-ahead journal');
    return {
      version: 2,
      format: STORE_FORMAT,
      couples: {},
      tokens: {},
      qrNonces: {},
      linkCodes: {},
      journalSeq: 0,
      recovered: true,
    };
  }

  async #hasSegmentCandidates() {
    try {
      return (await readdir(this.segmentsDir, { withFileTypes: true }))
        .some((entry) => entry.isFile() && /\.json(?:\.bak)?$/u.test(entry.name));
    } catch {
      return false;
    }
  }

  /**
   * Recovery is additive and non-destructive: inspect every segment and its
   * backup, adopt checksum-valid unindexed couples, and quarantine conflicts.
   */
  async #recoverUnindexedSegments(couples, indexed) {
    let entries;
    try {
      entries = await readdir(this.segmentsDir, { withFileTypes: true });
    } catch {
      return false;
    }
    const preferred = new Set(Object.values(indexed).map(String));
    const bases = [...new Set(entries
      .filter((entry) => entry.isFile() && /\.json(?:\.bak)?$/u.test(entry.name))
      .map((entry) => entry.name.endsWith('.bak')
        ? entry.name.slice(0, -'.bak'.length)
        : entry.name))]
      .sort((left, right) => Number(preferred.has(right)) - Number(preferred.has(left))
        || left.localeCompare(right));
    let changed = false;
    for (const base of bases) {
      const segment = await this.#loadSegment(base, null);
      if (!segment) {
        changed = true;
        continue;
      }
      const coupleId = segment.couple.id;
      const existing = couples[coupleId];
      if (!existing) {
        couples[coupleId] = segment.couple;
        this.segmentFingerprints.set(coupleId, segment.serialized);
        this.log(`store: recovered unindexed couple ${coupleId} from ${base}`);
        changed = true;
        continue;
      }
      if (JSON.stringify(existing) === segment.serialized) continue;
      const reason = `conflicting valid segment for couple ${coupleId}; indexed generation kept`;
      await this.#quarantineFile(path.join(this.segmentsDir, base), reason, coupleId);
      await this.#quarantineFile(`${path.join(this.segmentsDir, base)}.bak`, reason, coupleId);
      changed = true;
    }
    return changed;
  }

  /**
   * Loads one segment file with checksum verification and `.bak` fallback.
   * Returns {couple, serialized, recovered} or null (both copies broken →
   * moved to quarantine/).
   */
  async #loadSegment(name, coupleId) {
    const file = path.join(this.segmentsDir, name);
    const attempts = [
      { file, label: name },
      { file: `${file}.bak`, label: `${name}.bak` },
    ];
    const failures = [];
    for (let i = 0; i < attempts.length; i++) {
      const attempt = attempts[i];
      try {
        const raw = await readFile(attempt.file, 'utf8');
        const { couple, serialized } = parseSegment(raw, coupleId);
        if (i > 0) {
          this.log(`store: segment ${name} recovered from ${attempt.label}`);
          // The broken main copy must not shadow the good backup on the next
          // write cycle — move it out of the way, keep it for forensics.
          await this.#quarantineFile(file, failures[0] ?? 'unreadable segment', coupleId);
        }
        return { couple, serialized, recovered: i > 0 };
      } catch (err) {
        if (err.code !== 'ENOENT') failures.push(`${attempt.label}: ${err.message}`);
      }
    }
    if (failures.length === 0) return null; // both files simply do not exist
    this.log(`store: ${coupleId ? `couple ${coupleId}` : `segment ${name}`} unrecoverable `
      + `(${failures.join('; ')}) — quarantining`);
    await this.#quarantineFile(file, failures[0], coupleId);
    await this.#quarantineFile(`${file}.bak`, 'backup of quarantined segment', coupleId);
    return null;
  }

  /** Moves a broken file into quarantine/ (never deletes data). */
  async #quarantineFile(file, reason, coupleId = null) {
    try {
      await mkdir(this.quarantineDir, { recursive: true });
      const target = path.join(this.quarantineDir, `${Date.now()}-${path.basename(file)}`);
      await rename(file, target);
      this.quarantined.push({ file: path.basename(target), reason, at: new Date().toISOString(), coupleId });
      this.log(`store: quarantined ${path.basename(file)} → quarantine/${path.basename(target)} (${reason})`);
    } catch (err) {
      if (err.code !== 'ENOENT') this.log(`store: could not quarantine ${file}`, err);
    }
  }

  /**
   * Commits the current logical mutation to the fsynced write-ahead journal
   * before the route can send its 2xx response. The timer only compacts that
   * already-durable state into the human-readable manifest/segments.
   */
  markDirty() {
    if (this.closed) throw new Error('store is closed');
    this.#appendJournalSnapshot();
    this.dirty = true;
    this.#scheduleCompaction();
  }

  #scheduleCompaction() {
    this.dirty = true;
    if (this.closed || this.timer) return;
    this.timer = setTimeout(() => {
      this.timer = null;
      this.flush().catch((err) => this.log('store: background save failed', err));
    }, DEBOUNCE_MS);
    this.timer.unref?.();
  }

  #appendJournalSnapshot({ force = false } = {}) {
    if (this.journalFd === null) throw new Error('store write-ahead journal is not open');
    const changedCouples = {};
    const coupleFingerprints = new Map();
    const coupleIds = new Set([
      ...this.journalCoupleFingerprints.keys(),
      ...Object.keys(this.data.couples),
    ]);
    for (const coupleId of coupleIds) {
      const couple = this.data.couples[coupleId];
      if (couple === undefined) {
        if (this.journalCoupleFingerprints.has(coupleId)) changedCouples[coupleId] = null;
        continue;
      }
      const serialized = JSON.stringify(couple);
      coupleFingerprints.set(coupleId, serialized);
      if (force || this.journalCoupleFingerprints.get(coupleId) !== serialized) {
        changedCouples[coupleId] = JSON.parse(serialized);
      }
    }
    const rootSerialized = JSON.stringify(this.#rootData());
    const rootChanged = force || rootSerialized !== this.journalRootFingerprint;
    if (!rootChanged && Object.keys(changedCouples).length === 0) return false;

    const data = {
      seq: this.journalSeq + 1,
      at: new Date().toISOString(),
      root: JSON.parse(rootSerialized),
      couples: changedCouples,
    };
    const envelope = {
      format: JOURNAL_FORMAT,
      sha256: sha256Hex(JSON.stringify(data)),
      data,
    };
    const bytes = Buffer.from(`${JSON.stringify(envelope)}\n`);
    try {
      writeAllSync(this.journalFd, bytes);
      fsyncSync(this.journalFd);
      fsyncDirectorySync(this.dataDir);
    } catch (err) {
      throw new Error(`store: durable journal commit failed: ${err.message}`, { cause: err });
    }

    this.journalSeq = data.seq;
    this.journalEntries.push(envelope);
    this.journalCoupleFingerprints = coupleFingerprints;
    this.journalRootFingerprint = rootSerialized;
    return true;
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

  /** Atomic write keeping the previous good version as `<file>.bak`. */
  async #writeAtomic(file, contents) {
    const tmp = `${file}.tmp`;
    const handle = await open(tmp, 'w');
    try {
      await handle.writeFile(contents, 'utf8');
      await handle.sync();
    } finally {
      await handle.close();
    }
    try {
      await rename(file, `${file}.bak`);
      fsyncDirectorySync(path.dirname(file));
    } catch (err) {
      if (err.code !== 'ENOENT') throw err;
    }
    await rename(tmp, file);
    fsyncDirectorySync(path.dirname(file));
  }

  #replaceJournal(entries) {
    const tmp = `${this.journalFile}.tmp`;
    const contents = entries.length > 0
      ? `${entries.map((entry) => JSON.stringify(entry)).join('\n')}\n`
      : '';
    if (this.journalFd !== null) {
      closeSync(this.journalFd);
      this.journalFd = null;
    }
    let tmpFd = null;
    try {
      tmpFd = openSync(tmp, 'w');
      writeAllSync(tmpFd, Buffer.from(contents));
      fsyncSync(tmpFd);
      closeSync(tmpFd);
      tmpFd = null;
      renameSync(tmp, this.journalFile);
      fsyncDirectorySync(this.dataDir);
      this.journalEntries = entries;
    } finally {
      if (tmpFd !== null) closeSync(tmpFd);
      this.#openJournal();
    }
  }

  async #writeNow() {
    const snapshot = structuredClone(this.data);
    const compactedJournalSeq = this.journalSeq;
    const index = {};
    for (const [coupleId, couple] of Object.entries(snapshot.couples)) {
      const segmentName = `${encodeURIComponent(coupleId)}.json`;
      const serialized = JSON.stringify(couple);
      index[coupleId] = segmentName;
      if (this.segmentFingerprints.get(coupleId) === serialized) continue;
      await this.#writeAtomic(
        path.join(this.segmentsDir, segmentName),
        `{"format":"${SEGMENT_FORMAT}","sha256":"${sha256Hex(serialized)}","couple":${serialized}}`,
      );
      this.segmentFingerprints.set(coupleId, serialized);
    }
    const manifestPayload = {
      ...Object.fromEntries(Object.entries(snapshot).filter(([key]) => key !== 'couples')),
      format: STORE_FORMAT,
      couples: index,
      journalSeq: compactedJournalSeq,
      compactedAt: new Date().toISOString(),
    };
    const manifest = JSON.stringify({
      ...manifestPayload,
      sha256: sha256Hex(JSON.stringify(manifestPayload)),
    });
    await this.#writeAtomic(this.file, manifest);
    const wasRecovery = this.recoveryMode;
    if (!wasRecovery) await this.#removeOrphanSegments(new Set(Object.values(index)));
    this.lastCompaction = {
      at: new Date().toISOString(),
      couples: Object.keys(index).length,
      manifestBytes: Buffer.byteLength(manifest),
    };
    this.statsCache = null;
    const history = this.journalEntries
      .filter((entry) => entry.data.seq <= compactedJournalSeq)
      .slice(-JOURNAL_RECOVERY_RECORDS);
    const pending = this.journalEntries
      .filter((entry) => entry.data.seq > compactedJournalSeq);
    this.#replaceJournal([...history, ...pending]);
    this.recoveryMode = false;
  }

  async compact({ reason = 'manual' } = {}) {
    await this.#writeNow();
    this.lastCompaction = { ...this.lastCompaction, reason };
    return this.lastCompaction;
  }

  async #removeOrphanSegments(expected) {
    for (const entry of await readdir(this.segmentsDir, { withFileTypes: true })) {
      if (!entry.isFile()) continue;
      if (entry.name.endsWith('.tmp')) {
        await unlink(path.join(this.segmentsDir, entry.name));
        continue;
      }
      const base = entry.name.endsWith('.bak') ? entry.name.slice(0, -'.bak'.length) : entry.name;
      if (expected.has(base)) continue;
      // Segments of quarantined couples were already MOVED away; anything
      // else without an index entry is a leftover of a dissolved couple.
      await unlink(path.join(this.segmentsDir, entry.name));
      for (const [coupleId] of this.segmentFingerprints) {
        if (`${encodeURIComponent(coupleId)}.json` === base) this.segmentFingerprints.delete(coupleId);
      }
    }
  }

  async storageStats() {
    const now = Date.now();
    if (this.statsCache && now - this.statsCache.at < 5_000) return this.statsCache.value;
    const [manifest, segments, media, quarantine] = await Promise.all([
      fileStats(this.file),
      // Live segments only — .bak generations and stray .tmp files are
      // bookkeeping, not payload.
      directoryStats(this.segmentsDir, (name) => !name.endsWith('.bak') && !name.endsWith('.tmp')),
      directoryStats(path.join(this.dataDir, 'media')),
      directoryStats(this.quarantineDir),
    ]);
    const value = {
      format: STORE_FORMAT,
      couples: Object.keys(this.data.couples).length,
      manifestBytes: manifest.bytes,
      segmentBytes: segments.bytes,
      segmentFiles: segments.files,
      mediaBytes: media.bytes,
      mediaFiles: media.files,
      mediaQuotaBytes: this.mediaQuotaBytes,
      mediaQuotaUsed: this.mediaQuotaBytes > 0
        ? Number((media.bytes / this.mediaQuotaBytes).toFixed(6))
        : null,
      quarantine: {
        files: quarantine.files,
        bytes: quarantine.bytes,
        couples: this.quarantinedCoupleIds.size,
      },
      lastCompaction: this.lastCompaction,
    };
    this.statsCache = { at: now, value };
    return value;
  }

  async close() {
    if (this.closed) return;
    this.closed = true;
    try {
      await this.flush();
    } finally {
      if (this.journalFd !== null) {
        closeSync(this.journalFd);
        this.journalFd = null;
      }
      if (this.ownsDataDirLock) {
        await this.dataDirLock?.release();
        this.dataDirLock = null;
      }
    }
  }

  mediaPath(kind, filename) {
    return path.join(this.dataDir, 'media', kind, filename);
  }

  /**
   * Free/total bytes of the filesystem holding the data dir, plus the guard
   * verdicts (`warn` under diskWarnBytes, `stop` under diskStopBytes).
   * Returns null where statfs is unavailable — the guard then stays open.
   */
  async diskStatus() {
    try {
      const fs = await statfs(this.dataDir);
      const freeBytes = fs.bavail * fs.bsize;
      const totalBytes = fs.blocks * fs.bsize;
      return {
        freeBytes,
        totalBytes,
        warn: freeBytes < this.diskWarnBytes,
        stop: freeBytes < this.diskStopBytes,
      };
    } catch {
      return null;
    }
  }

  async saveMedia(kind, filename, buf, suppliedReservation = null) {
    // Refuse new media before a genuinely full disk can corrupt the JSON
    // store mid-write. 507 tells clients honestly what is going on.
    const disk = await this.diskStatus();
    if (disk?.stop) {
      throw httpError(
        507,
        'disk_full',
        `Server disk almost full (${Math.round(disk.freeBytes / 1024 / 1024)} MB free) — ask the server owner to free up space`,
      );
    }
    const reservation = suppliedReservation ?? this.reserveMedia({ bytes: buf.length });
    const file = this.mediaPath(kind, filename);
    try {
      let previousBytes = 0;
      try {
        previousBytes = (await stat(file)).size;
      } catch (err) {
        if (err.code !== 'ENOENT') throw err;
      }
      const handle = await open(file, 'w');
      try {
        await handle.writeFile(buf);
        await handle.sync();
      } finally {
        await handle.close();
      }
      fsyncDirectorySync(path.dirname(file));
      reservation.recordWrite(buf.length - previousBytes);
    } catch (err) {
      reservation.release();
      throw err;
    }
    if (suppliedReservation === null) reservation.release();
    this.statsCache = null;
  }

  /**
   * Atomically reserves global media bytes and, for collection uploads, one
   * count slot. The reservation spans asynchronous file I/O until metadata is
   * journaled, preventing concurrent requests from all passing a stale count.
   */
  reserveMedia({
    bytes,
    coupleId = null,
    collection = null,
    currentCount = 0,
    limit = Number.POSITIVE_INFINITY,
    limitCode = 'too_many_items',
    limitMessage = 'Media collection limit reached',
  }) {
    if (!Number.isSafeInteger(bytes) || bytes < 0) {
      throw new TypeError('media reservation bytes must be a non-negative safe integer');
    }
    const slotKey = coupleId && collection ? `${coupleId}\0${collection}` : null;
    const slotsReserved = slotKey ? (this.mediaSlotReservations.get(slotKey) ?? 0) : 0;
    if (currentCount + slotsReserved >= limit) {
      throw httpError(413, limitCode, limitMessage);
    }
    if (this.mediaQuotaBytes > 0
      && this.mediaBytesUsed + this.mediaBytesReserved + bytes > this.mediaQuotaBytes) {
      throw httpError(
        507,
        'media_quota_exceeded',
        `Server media quota exceeded (${this.mediaBytesUsed} of ${this.mediaQuotaBytes} bytes used)`,
      );
    }
    this.mediaBytesReserved += bytes;
    if (slotKey) this.mediaSlotReservations.set(slotKey, slotsReserved + 1);

    let bytesReserved = true;
    let slotReserved = Boolean(slotKey);
    return {
      recordWrite: (delta) => {
        if (bytesReserved) {
          this.mediaBytesReserved = Math.max(0, this.mediaBytesReserved - bytes);
          bytesReserved = false;
        }
        this.mediaBytesUsed = Math.max(0, this.mediaBytesUsed + delta);
      },
      release: () => {
        if (bytesReserved) {
          this.mediaBytesReserved = Math.max(0, this.mediaBytesReserved - bytes);
          bytesReserved = false;
        }
        if (slotReserved) {
          const left = Math.max(0, (this.mediaSlotReservations.get(slotKey) ?? 1) - 1);
          if (left === 0) this.mediaSlotReservations.delete(slotKey);
          else this.mediaSlotReservations.set(slotKey, left);
          slotReserved = false;
        }
      },
    };
  }

  async deleteMedia(kind, filename) {
    let bytes = 0;
    try {
      bytes = (await stat(this.mediaPath(kind, filename))).size;
    } catch (err) {
      if (err.code !== 'ENOENT') throw err;
    }
    try {
      await unlink(this.mediaPath(kind, filename));
      fsyncDirectorySync(path.dirname(this.mediaPath(kind, filename)));
      this.mediaBytesUsed = Math.max(0, this.mediaBytesUsed - bytes);
    } catch (err) {
      if (err.code !== 'ENOENT') this.log(`store: could not delete media ${kind}/${filename}`, err);
    }
    this.statsCache = null;
  }
}

/**
 * Parses a segment file: either a `segment-v2` checksum envelope or a legacy
 * raw couple object (pre-6.1 segments have no checksum). Throws on invalid
 * JSON, wrong shape, or checksum mismatch.
 */
function parseManifest(raw) {
  const parsed = JSON.parse(raw);
  if (!isRecord(parsed)) throw new Error('manifest is not a JSON object');
  if (parsed.format === STORE_FORMAT) {
    if (parsed.version !== 2 || !isRecord(parsed.couples) || !isRecord(parsed.tokens)) {
      throw new Error('segmented manifest has an invalid schema');
    }
    for (const [coupleId, segmentName] of Object.entries(parsed.couples)) {
      if (coupleId.length === 0 || typeof segmentName !== 'string'
        || segmentName !== path.basename(segmentName) || !segmentName.endsWith('.json')) {
        throw new Error('segmented manifest has an invalid couple index');
      }
    }
    for (const record of Object.values(parsed.tokens)) {
      if (!isRecord(record)) throw new Error('segmented manifest has an invalid token record');
    }
    if (parsed.qrNonces !== undefined && !isRecord(parsed.qrNonces)) {
      throw new Error('segmented manifest has an invalid QR nonce index');
    }
    for (const record of Object.values(parsed.qrNonces ?? {})) {
      if (!isRecord(record) || typeof record.coupleId !== 'string'
        || typeof record.memberId !== 'string' || typeof record.expiresAt !== 'string'
        || (record.consumedAt !== null && typeof record.consumedAt !== 'string')) {
        throw new Error('segmented manifest has an invalid QR nonce record');
      }
    }
    if (parsed.linkCodes !== undefined && !isRecord(parsed.linkCodes)) {
      throw new Error('segmented manifest has an invalid link code index');
    }
    for (const record of Object.values(parsed.linkCodes ?? {})) {
      if (!isRecord(record) || typeof record.coupleId !== 'string'
        || typeof record.memberId !== 'string' || typeof record.expiresAt !== 'string'
        || (record.consumedAt !== null && typeof record.consumedAt !== 'string')) {
        throw new Error('segmented manifest has an invalid link code record');
      }
    }
    const { sha256, ...payload } = parsed;
    if (sha256 !== undefined && (typeof sha256 !== 'string'
      || sha256 !== sha256Hex(JSON.stringify(payload)))) {
      throw new Error('manifest checksum mismatch');
    }
    return { ...parsed, needsChecksum: sha256 === undefined };
  }
  if (parsed.format !== undefined || parsed.version !== 1
    || !isRecord(parsed.couples) || !isRecord(parsed.tokens)) {
    throw new Error('unrecognized manifest format or legacy version');
  }
  for (const [coupleId, couple] of Object.entries(parsed.couples)) {
    validateCouple(couple, coupleId, { legacy: true });
  }
  return parsed;
}

function parseSegment(raw, expectedCoupleId = null) {
  const parsed = JSON.parse(raw);
  if (!isRecord(parsed)) {
    throw new Error('segment is not a JSON object');
  }
  if (parsed.format === SEGMENT_FORMAT) {
    if (!isRecord(parsed.couple)) {
      throw new Error('segment envelope has no couple object');
    }
    validateCouple(parsed.couple, expectedCoupleId);
    const serialized = JSON.stringify(parsed.couple);
    if (sha256Hex(serialized) !== parsed.sha256) {
      throw new Error('segment checksum mismatch');
    }
    return { couple: parsed.couple, serialized };
  }
  if (parsed.format !== undefined) throw new Error('unrecognized segment format');
  validateCouple(parsed, expectedCoupleId, { legacy: true });
  return { couple: parsed, serialized: JSON.stringify(parsed) };
}

function validateCouple(couple, expectedCoupleId, { legacy = false } = {}) {
  if (!isRecord(couple) || typeof couple.id !== 'string' || couple.id.length === 0) {
    throw new Error('segment couple has no valid id');
  }
  if (expectedCoupleId !== null && couple.id !== expectedCoupleId) {
    throw new Error(`segment couple id ${couple.id} does not match manifest id ${expectedCoupleId}`);
  }
  if (legacy && (typeof couple.code !== 'string' || !Array.isArray(couple.members)
    || couple.members.length < 1 || couple.members.length > 2
    || couple.members.some((member) => !isRecord(member) || typeof member.id !== 'string'))) {
    throw new Error('legacy segment does not match the recognized couple schema');
  }
}

function isRecord(value) {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function validateJournalEnvelope(envelope) {
  if (!envelope || typeof envelope !== 'object' || Array.isArray(envelope)
    || envelope.format !== JOURNAL_FORMAT) {
    throw new Error(`journal record must use format "${JOURNAL_FORMAT}"`);
  }
  const { data } = envelope;
  if (!data || typeof data !== 'object' || Array.isArray(data)
    || !Number.isSafeInteger(data.seq) || data.seq <= 0
    || !data.root || typeof data.root !== 'object' || Array.isArray(data.root)
    || !data.root.tokens || typeof data.root.tokens !== 'object' || Array.isArray(data.root.tokens)
    || !data.couples || typeof data.couples !== 'object' || Array.isArray(data.couples)) {
    throw new Error('journal record has an invalid schema');
  }
  for (const couple of Object.values(data.couples)) {
    if (couple !== null && (!couple || typeof couple !== 'object' || Array.isArray(couple))) {
      throw new Error('journal record contains an invalid couple change');
    }
  }
  if (typeof envelope.sha256 !== 'string'
    || envelope.sha256 !== sha256Hex(JSON.stringify(data))) {
    throw new Error('journal record checksum mismatch');
  }
}

function writeAllSync(fd, bytes) {
  let offset = 0;
  while (offset < bytes.length) {
    offset += writeSync(fd, bytes, offset, bytes.length - offset);
  }
}

function fsyncDirectorySync(directory) {
  let fd;
  try {
    fd = openSync(directory, 'r');
    fsyncSync(fd);
  } finally {
    if (fd !== undefined) closeSync(fd);
  }
}

async function fileStats(file) {
  try {
    const info = await stat(file);
    return { bytes: info.size, files: 1 };
  } catch (err) {
    if (err.code === 'ENOENT') return { bytes: 0, files: 0 };
    throw err;
  }
}

async function directoryStats(directory, includeFile = () => true) {
  let bytes = 0;
  let files = 0;
  let entries;
  try {
    entries = await readdir(directory, { withFileTypes: true });
  } catch (err) {
    if (err.code === 'ENOENT') return { bytes: 0, files: 0 };
    throw err;
  }
  for (const entry of entries) {
    const target = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      const nested = await directoryStats(target, includeFile);
      bytes += nested.bytes;
      files += nested.files;
    } else if (entry.isFile() && includeFile(entry.name)) {
      const info = await stat(target);
      bytes += info.size;
      files += 1;
    }
  }
  return { bytes, files };
}
