import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { Storage } from '../src/storage.js';

function tempDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'gooby-store-'));
}

test('Storage: Collection schreiben → atomar, parsebar, keine tmp-Leichen', (t) => {
  const dir = tempDir();
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const store = new Storage(dir, { flushMs: 60_000 });
  t.after(() => store.close());
  const players = store.collection('players', {});
  players['gd-1'] = { name: 'Anna', coins: 5 };
  store.markDirty('players');
  for (let i = 0; i < 20; i++) {
    players['gd-1'].coins = i;
    store.markDirty('players');
    store.flush();
  }
  const onDisk = JSON.parse(fs.readFileSync(path.join(dir, 'players.json'), 'utf8'));
  assert.equal(onDisk['gd-1'].coins, 19);
  const leftovers = fs.readdirSync(dir).filter((f) => f.includes('.tmp-'));
  assert.deepEqual(leftovers, [], 'keine tmp-Dateien nach flush');
});

test('Storage: Neustart liest denselben Zustand (Roundtrip)', (t) => {
  const dir = tempDir();
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const s1 = new Storage(dir, { flushMs: 60_000 });
  s1.collection('codes', { codes: {} }).codes.ABC = { uses: 3 };
  s1.markDirty('codes');
  s1.close(); // close flusht
  const s2 = new Storage(dir, { flushMs: 60_000 });
  assert.equal(s2.collection('codes', { codes: {} }).codes.ABC.uses, 3);
  s2.close();
});

test('Storage: korrupte Collection wird beiseitegelegt statt zu crashen', (t) => {
  const dir = tempDir();
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  fs.writeFileSync(path.join(dir, 'players.json'), '{halb kaputt');
  const store = new Storage(dir, { flushMs: 60_000 });
  t.after(() => store.close());
  const players = store.collection('players', {});
  assert.deepEqual(players, {});
  const corrupt = fs.readdirSync(dir).filter((f) => f.startsWith('players.json.corrupt-'));
  assert.equal(corrupt.length, 1, 'Original als .corrupt-* gesichert');
});

test('Storage: JSONL-Append + Read (inkl. halber Crash-Zeile)', (t) => {
  const dir = tempDir();
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const store = new Storage(dir, { flushMs: 60_000 });
  t.after(() => store.close());
  store.appendLine('sessions/sessions-2026-07.jsonl', { a: 1 });
  store.appendLine('sessions/sessions-2026-07.jsonl', { a: 2 });
  // Simulierter Crash: halbe Zeile hinten dran.
  fs.appendFileSync(path.join(dir, 'sessions/sessions-2026-07.jsonl'), '{"a":3');
  const lines = store.readLines('sessions/sessions-2026-07.jsonl');
  assert.deepEqual(lines.map((l) => l.a), [1, 2]);
});

test('Storage: Blob-Größenlimit (512 KB Fotos) wird erzwungen', (t) => {
  const dir = tempDir();
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const store = new Storage(dir, { flushMs: 60_000 });
  t.after(() => store.close());
  const limit = 512 * 1024;
  store.putBlob('blobs', 'ok.bin', Buffer.alloc(limit), limit);
  assert.throws(() => store.putBlob('blobs', 'big.bin', Buffer.alloc(limit + 1), limit), /BLOB_TOO_LARGE|too large/);
});

test('Storage: Pfad-Traversal ist unmöglich (unsafe ids/relPaths werfen)', (t) => {
  const dir = tempDir();
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const store = new Storage(dir, { flushMs: 60_000 });
  t.after(() => store.close());
  assert.throws(() => store.putBlob('blobs', '../evil.txt', Buffer.from('x'), 100));
  assert.throws(() => store.putBlob('../blobs', 'x', Buffer.from('x'), 100));
  assert.throws(() => store.readLines('../../etc/passwd'));
  assert.throws(() => store.collection('../evil'));
});
