// JSON-File-Storage (Doc C §2.2): bewusst KEINE Datenbank.
// - Collections (players.json, friends.json, codes.json, events.json, houses.json, analytics.json):
//   komplette In-Memory-Objekte, Write-behind-Snapshot (dirty + Intervall) — atomar via
//   write tmp → rename. Passt locker in RAM (Freundeskreis-Skala).
// - Append-Logs (sessions/*.jsonl, ledger/*.jsonl): eine Zeile pro Event, monatlich rotiert.
// - Blobs (Haus-Snapshots, später Fotos): einzelne Dateien unter data/blobs bzw. data/mail,
//   NUR server-generierte IDs (kein Pfad-Traversal), Größenlimit erzwungen.
// Interface klein halten, damit ein späterer node:sqlite-Swap eine 1-Datei-Änderung bleibt.

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const SAFE_NAME = /^[a-zA-Z0-9._-]+$/;

export class Storage {
  constructor(dataDir, { flushMs = 10_000 } = {}) {
    this.dataDir = path.resolve(dataDir);
    this.collections = new Map(); // name -> object (live reference)
    this.dirty = new Set();
    fs.mkdirSync(this.dataDir, { recursive: true });
    fs.mkdirSync(path.join(this.dataDir, 'sessions'), { recursive: true });
    fs.mkdirSync(path.join(this.dataDir, 'ledger'), { recursive: true });
    fs.mkdirSync(path.join(this.dataDir, 'blobs'), { recursive: true });
    fs.mkdirSync(path.join(this.dataDir, 'mail'), { recursive: true });
    this.timer = setInterval(() => this.flush(), flushMs);
    if (this.timer.unref) this.timer.unref();
  }

  _file(name) {
    if (!SAFE_NAME.test(name)) throw new Error(`unsafe collection name: ${name}`);
    return path.join(this.dataDir, `${name}.json`);
  }

  // Liefert die LIVE-Referenz der Collection (mutieren + markDirty()).
  collection(name, def = {}) {
    if (!this.collections.has(name)) {
      const file = this._file(name);
      let value = def;
      if (fs.existsSync(file)) {
        try {
          value = JSON.parse(fs.readFileSync(file, 'utf8'));
        } catch (err) {
          // Korrupte Datei nie stumpf überschreiben: beiseitelegen und frisch starten.
          const bak = `${file}.corrupt-${Date.now()}`;
          fs.renameSync(file, bak);
          console.error(`[storage] ${name}.json korrupt → ${path.basename(bak)}:`, err.message);
          value = structuredClone(def);
        }
      } else {
        value = structuredClone(def);
      }
      this.collections.set(name, value);
    }
    return this.collections.get(name);
  }

  markDirty(name) {
    this.dirty.add(name);
  }

  // Atomar: tmp schreiben → fsync → rename. Ein Crash hinterlässt nie halbe JSONs.
  _writeAtomic(file, text) {
    const tmp = `${file}.tmp-${process.pid}-${crypto.randomBytes(4).toString('hex')}`;
    const fd = fs.openSync(tmp, 'w');
    try {
      fs.writeFileSync(fd, text);
      fs.fsyncSync(fd);
    } finally {
      fs.closeSync(fd);
    }
    fs.renameSync(tmp, file);
  }

  flush() {
    for (const name of this.dirty) {
      const value = this.collections.get(name);
      if (value === undefined) continue;
      this._writeAtomic(this._file(name), JSON.stringify(value, null, 1));
    }
    this.dirty.clear();
  }

  // Kritische Bestätigungen (Code-Redeem, Pal-Transfer, Analytics-Ingest):
  // Collection SOFORT synchron+atomar persistieren, BEVOR ok gemeldet wird —
  // Write-behind-Fenster = 0 für diese Klasse (E13 P1-1). Ein Crash direkt
  // nach der Antwort rollt den bestätigten Zustand damit nie mehr zurück.
  flushNow(name) {
    const value = this.collections.get(name);
    if (value === undefined) return;
    this._writeAtomic(this._file(name), JSON.stringify(value, null, 1));
    this.dirty.delete(name);
  }

  // JSONL-Append (relPath z. B. "sessions/sessions-2026-07.jsonl").
  appendLine(relPath, obj) {
    const file = this._resolveRel(relPath);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.appendFileSync(file, `${JSON.stringify(obj)}\n`);
  }

  readLines(relPath) {
    const file = this._resolveRel(relPath);
    if (!fs.existsSync(file)) return [];
    return fs
      .readFileSync(file, 'utf8')
      .split('\n')
      .filter(Boolean)
      .map((line) => {
        try {
          return JSON.parse(line);
        } catch {
          return null; // halbe letzte Zeile nach Crash → überspringen
        }
      })
      .filter(Boolean);
  }

  // Blobs: ID wird IMMER server-seitig erzeugt; maxBytes wird hart erzwungen.
  putBlob(dir, id, buf, maxBytes) {
    if (!SAFE_NAME.test(dir) || !SAFE_NAME.test(id)) throw new Error('unsafe blob id');
    if (!Buffer.isBuffer(buf)) buf = Buffer.from(buf);
    if (buf.length > maxBytes) {
      const err = new Error(`blob too large: ${buf.length} > ${maxBytes}`);
      err.code = 'BLOB_TOO_LARGE';
      throw err;
    }
    const file = path.join(this.dataDir, dir, id);
    this._writeAtomic(file, buf.toString('utf8'));
    return `${dir}/${id}`;
  }

  readBlob(ref) {
    const file = this._resolveRel(ref);
    if (!fs.existsSync(file)) return null;
    return fs.readFileSync(file);
  }

  // Blob löschen (Ghost-Prune, RW-6) — best effort, Pfad-Traversal-sicher.
  deleteBlob(ref) {
    try {
      fs.rmSync(this._resolveRel(ref), { force: true });
    } catch {
      /* best effort */
    }
  }

  _resolveRel(relPath) {
    const file = path.resolve(this.dataDir, relPath);
    if (!file.startsWith(this.dataDir + path.sep)) throw new Error('path escape');
    return file;
  }

  // Für Panel-Dashboard: Größe des Datenverzeichnisses (best effort).
  dataSizeBytes() {
    let total = 0;
    const walk = (dir) => {
      for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
        const full = path.join(dir, entry.name);
        if (entry.isDirectory()) walk(full);
        else if (entry.isFile()) total += fs.statSync(full).size;
      }
    };
    try {
      walk(this.dataDir);
    } catch {
      /* best effort */
    }
    return total;
  }

  close() {
    clearInterval(this.timer);
    this.flush();
  }
}
