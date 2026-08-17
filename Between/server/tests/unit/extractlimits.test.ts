/**
 * Archive-extraction safety limits: zip/tar bombs, entry floods and oversized
 * tar metadata records must abort extraction instead of exhausting disk,
 * memory or CPU. Limits are overridden to small values so tests stay fast.
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import zlib from 'node:zlib'
import { zipDirectory, unzip } from '../../src/lib/zip.ts'
import { extractTar } from '../../src/lib/tar.ts'

const MIB = 1024 * 1024

function tmpDir(): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'between-bomb-'))
}

// ---------------------------------------------------------------------------
// zip
// ---------------------------------------------------------------------------

/** Build a zip of `count` files with `size` zero-bytes each (compresses tiny). */
async function makeZip(count: number, size: number): Promise<{ zipFile: string; cleanup: () => void }> {
  const src = tmpDir()
  const out = tmpDir()
  for (let i = 0; i < count; i++) fs.writeFileSync(path.join(src, `f${i}.bin`), Buffer.alloc(size))
  const zipFile = path.join(out, 'a.zip')
  await zipDirectory(src, zipFile)
  return { zipFile, cleanup: () => [src, out].forEach((d) => fs.rmSync(d, { recursive: true, force: true })) }
}

/** Rewrite every central-directory `usize` so the archive under-declares itself. */
function patchDeclaredSizes(zipFile: string, fakeUsize: number) {
  const buf = fs.readFileSync(zipFile)
  let eocd = -1
  for (let i = buf.length - 22; i >= 0; i--) {
    if (buf.readUInt32LE(i) === 0x06054b50) {
      eocd = i
      break
    }
  }
  assert.ok(eocd >= 0, 'EOCD record found')
  let p = buf.readUInt32LE(eocd + 16)
  while (p < eocd && buf.readUInt32LE(p) === 0x02014b50) {
    buf.writeUInt32LE(fakeUsize, p + 24)
    p += 46 + buf.readUInt16LE(p + 28) + buf.readUInt16LE(p + 30) + buf.readUInt16LE(p + 32)
  }
  fs.writeFileSync(zipFile, buf)
}

test('zip: honestly-declared bomb is rejected before writing anything', async () => {
  const { zipFile, cleanup } = await makeZip(3, MIB) // declares 3 MiB total
  const dest = tmpDir()
  await assert.rejects(() => unzip(zipFile, dest, { maxBytes: 2 * MIB }), /too large/)
  assert.equal(fs.readdirSync(dest).length, 0, 'nothing extracted')
  cleanup()
  fs.rmSync(dest, { recursive: true, force: true })
})

test('zip: bomb with lying size metadata is caught while streaming', async () => {
  const { zipFile, cleanup } = await makeZip(1, 4 * MIB)
  patchDeclaredSizes(zipFile, 100) // claims 100 B, actually inflates to 4 MiB
  const dest = tmpDir()
  await assert.rejects(() => unzip(zipFile, dest, { maxBytes: MIB }), /too large/)
  assert.ok(!fs.existsSync(path.join(dest, 'f0.bin')), 'partial file removed')
  cleanup()
  fs.rmSync(dest, { recursive: true, force: true })
})

test('zip: entry flood is rejected', async () => {
  const { zipFile, cleanup } = await makeZip(25, 4)
  const dest = tmpDir()
  await assert.rejects(() => unzip(zipFile, dest, { maxEntries: 10 }), /too many entries/)
  cleanup()
  fs.rmSync(dest, { recursive: true, force: true })
})

/** Turn every entry into a stored (method 0) empty entry in the central dir. */
function forceStoredEmpty(zipFile: string) {
  const buf = fs.readFileSync(zipFile)
  let eocd = -1
  for (let i = buf.length - 22; i >= 0; i--) {
    if (buf.readUInt32LE(i) === 0x06054b50) {
      eocd = i
      break
    }
  }
  let p = buf.readUInt32LE(eocd + 16)
  while (p < eocd && buf.readUInt32LE(p) === 0x02014b50) {
    buf.writeUInt16LE(0, p + 10) // method = stored
    buf.writeUInt32LE(0, p + 20) // csize = 0
    buf.writeUInt32LE(0, p + 24) // usize = 0
    p += 46 + buf.readUInt16LE(p + 28) + buf.readUInt16LE(p + 30) + buf.readUInt16LE(p + 32)
  }
  fs.writeFileSync(zipFile, buf)
}

test('zip: empty entry colliding with an existing directory rejects instead of crashing', async () => {
  // Regression: the csize===0 branch used to end() an unawaited write stream
  // with no error handler; an EISDIR collision surfaced as an uncaughtException
  // and killed the process. It must now reject cleanly and keep the directory.
  const src = tmpDir()
  const out = tmpDir()
  fs.writeFileSync(path.join(src, 'foo'), '') // empty file entry named "foo"
  const zipFile = path.join(out, 'collide.zip')
  await zipDirectory(src, zipFile)
  forceStoredEmpty(zipFile)

  const dest = tmpDir()
  fs.mkdirSync(path.join(dest, 'foo')) // a directory already occupies "foo"
  await assert.rejects(() => unzip(zipFile, dest), /EISDIR|directory/)
  assert.ok(fs.statSync(path.join(dest, 'foo')).isDirectory(), 'pre-existing directory preserved')
  for (const d of [src, out, dest]) fs.rmSync(d, { recursive: true, force: true })
})

test('zip: empty entry extracts as an empty file when there is no collision', async () => {
  const src = tmpDir()
  const out = tmpDir()
  fs.writeFileSync(path.join(src, 'empty.txt'), '')
  const zipFile = path.join(out, 'e.zip')
  await zipDirectory(src, zipFile)
  forceStoredEmpty(zipFile)

  const dest = tmpDir()
  const res = await unzip(zipFile, dest)
  assert.equal(res.files, 1)
  assert.equal(fs.readFileSync(path.join(dest, 'empty.txt'), 'utf8'), '')
  for (const d of [src, out, dest]) fs.rmSync(d, { recursive: true, force: true })
})

// ---------------------------------------------------------------------------
// tar
// ---------------------------------------------------------------------------

function tarHeader(name: string, size: number, typeflag = '0'): Buffer {
  const b = Buffer.alloc(512)
  b.write(name, 0, 'utf8')
  b.write('0000644\0', 100, 'ascii')
  b.write('0000000\0', 108, 'ascii')
  b.write('0000000\0', 116, 'ascii')
  b.write(`${size.toString(8).padStart(11, '0')}\0`, 124, 'ascii')
  b.write('00000000000\0', 136, 'ascii')
  b.write('        ', 148, 'ascii')
  b.write(typeflag, 156, 'ascii')
  b.write('ustar\0', 257, 'ascii')
  b.write('00', 263, 'ascii')
  let sum = 0
  for (const byte of b) sum += byte
  b.write(`${sum.toString(8).padStart(6, '0')}\0 `, 148, 'ascii')
  return b
}

function makeTar(entries: { name: string; body?: Buffer; typeflag?: string }[]): Buffer {
  const parts: Buffer[] = []
  for (const e of entries) {
    const body = e.body ?? Buffer.alloc(0)
    parts.push(tarHeader(e.name, body.length, e.typeflag ?? '0'))
    if (body.length > 0) {
      parts.push(body)
      const pad = (512 - (body.length % 512)) % 512
      if (pad > 0) parts.push(Buffer.alloc(pad))
    }
  }
  parts.push(Buffer.alloc(1024)) // end-of-archive marker
  return Buffer.concat(parts)
}

function writeTar(entries: { name: string; body?: Buffer; typeflag?: string }[], gz = false): { file: string; dir: string } {
  const dir = tmpDir()
  const raw = makeTar(entries)
  const file = path.join(dir, gz ? 'a.tar.gz' : 'a.tar')
  fs.writeFileSync(file, gz ? zlib.gzipSync(raw) : raw)
  return { file, dir }
}

test('tar: byte budget aborts extraction and removes the partial file', async () => {
  const { file, dir } = writeTar([{ name: 'huge.bin', body: Buffer.alloc(3 * MIB) }])
  const dest = tmpDir()
  await assert.rejects(() => extractTar(file, dest, { maxBytes: MIB }), /too large/)
  assert.ok(!fs.existsSync(path.join(dest, 'huge.bin')), 'partial file removed')
  for (const d of [dir, dest]) fs.rmSync(d, { recursive: true, force: true })
})

test('tar.gz: gzip bomb hits the same byte budget', async () => {
  const { file, dir } = writeTar([{ name: 'huge.bin', body: Buffer.alloc(3 * MIB) }], true)
  assert.ok(fs.statSync(file).size < 16 * 1024, 'bomb is tiny on disk')
  const dest = tmpDir()
  await assert.rejects(() => extractTar(file, dest, { maxBytes: MIB }), /too large/)
  for (const d of [dir, dest]) fs.rmSync(d, { recursive: true, force: true })
})

test('tar: entry flood is rejected', async () => {
  const entries = Array.from({ length: 30 }, (_, i) => ({ name: `f${i}.txt`, body: Buffer.from('x') }))
  const { file, dir } = writeTar(entries)
  const dest = tmpDir()
  await assert.rejects(() => extractTar(file, dest, { maxEntries: 10 }), /too many entries/)
  for (const d of [dir, dest]) fs.rmSync(d, { recursive: true, force: true })
})

test('tar: oversized pax/long-name metadata records are rejected', async () => {
  const paxBody = Buffer.alloc(2 * MIB) // > 1 MiB metadata cap
  const { file, dir } = writeTar([
    { name: 'pax', body: paxBody, typeflag: 'x' },
    { name: 'after.txt', body: Buffer.from('never reached') },
  ])
  const dest = tmpDir()
  await assert.rejects(() => extractTar(file, dest), /too large/)

  const { file: fileL, dir: dirL } = writeTar([{ name: 'long', body: Buffer.alloc(2 * MIB), typeflag: 'L' }])
  await assert.rejects(() => extractTar(fileL, dest), /too large/)
  for (const d of [dir, dirL, dest]) fs.rmSync(d, { recursive: true, force: true })
})

test('tar: unsafe and non-regular entries are skipped without derailing the stream', async () => {
  // 2 MiB bodies on skipped entries must be streamed past (not buffered) and
  // the following legitimate file must still extract with correct content.
  const { file, dir } = writeTar([
    { name: '../evil.bin', body: Buffer.alloc(2 * MIB) },
    { name: 'dev', body: Buffer.alloc(MIB), typeflag: '3' },
    { name: 'after.txt', body: Buffer.from('still fine') },
  ])
  const dest = tmpDir()
  const res = await extractTar(file, dest)
  assert.equal(res.files, 1)
  assert.equal(fs.readFileSync(path.join(dest, 'after.txt'), 'utf8'), 'still fine')
  assert.ok(!fs.existsSync(path.join(dest, 'evil.bin')), 'unsafe entry not written')
  assert.ok(!fs.existsSync(path.join(dest, 'dev')), 'device entry not written')
  for (const d of [dir, dest]) fs.rmSync(d, { recursive: true, force: true })
})
