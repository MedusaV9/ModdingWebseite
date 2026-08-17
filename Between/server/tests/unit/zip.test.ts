import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { zipDirectory, unzip, listZip, crc32 } from '../../src/lib/zip.ts'

function tmpDir(): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'between-zip-'))
}

test('crc32 known value', () => {
  // CRC-32 of "123456789" is 0xCBF43926
  assert.equal(crc32(Buffer.from('123456789', 'ascii')), 0xcbf43926)
})

test('zip + unzip roundtrip preserves contents and structure', async () => {
  const src = tmpDir()
  const out = tmpDir()
  const dest = tmpDir()
  fs.mkdirSync(path.join(src, 'sub/deep'), { recursive: true })
  fs.writeFileSync(path.join(src, 'hello.txt'), 'Hello Between!')
  fs.writeFileSync(path.join(src, 'sub', 'näme-ütf8.txt'), 'umlauts')
  fs.writeFileSync(path.join(src, 'sub/deep', 'data.bin'), Buffer.from([0, 1, 2, 250, 251]))
  const big = Buffer.alloc(256 * 1024)
  for (let i = 0; i < big.length; i++) big[i] = i % 251
  fs.writeFileSync(path.join(src, 'big.dat'), big)

  const zipFile = path.join(out, 'test.zip')
  const result = await zipDirectory(src, zipFile)
  assert.equal(result.files, 4)

  const entries = listZip(zipFile)
  const names = entries.map((e) => e.name).sort()
  assert.ok(names.includes('hello.txt'))
  assert.ok(names.includes('sub/näme-ütf8.txt'))
  assert.ok(names.includes('sub/deep/data.bin'))

  const extracted = await unzip(zipFile, dest)
  assert.equal(extracted.files, 4)
  assert.equal(fs.readFileSync(path.join(dest, 'hello.txt'), 'utf8'), 'Hello Between!')
  assert.equal(fs.readFileSync(path.join(dest, 'sub', 'näme-ütf8.txt'), 'utf8'), 'umlauts')
  assert.deepEqual(fs.readFileSync(path.join(dest, 'sub/deep', 'data.bin')), Buffer.from([0, 1, 2, 250, 251]))
  assert.deepEqual(fs.readFileSync(path.join(dest, 'big.dat')), big)

  for (const dir of [src, out, dest]) fs.rmSync(dir, { recursive: true, force: true })
})

test('zipDirectory honors exclude filter', async () => {
  const src = tmpDir()
  const out = tmpDir()
  fs.writeFileSync(path.join(src, 'keep.txt'), 'keep')
  fs.mkdirSync(path.join(src, 'cache'))
  fs.writeFileSync(path.join(src, 'cache', 'skip.txt'), 'skip')

  const zipFile = path.join(out, 'filtered.zip')
  await zipDirectory(src, zipFile, { exclude: (rel) => rel === 'cache' || rel.startsWith('cache/') })
  const names = listZip(zipFile).map((e) => e.name)
  assert.deepEqual(names, ['keep.txt'])

  for (const dir of [src, out]) fs.rmSync(dir, { recursive: true, force: true })
})

test('zipDirectory removes its partial archive when zipping fails mid-way', async () => {
  const src = tmpDir()
  const out = tmpDir()
  fs.writeFileSync(path.join(src, 'a.txt'), 'content that gets written before the failure')

  // Force a failure AFTER the output stream exists and entry data was
  // written: onProgress fires per completed file inside the write loop, so a
  // throwing callback is a deterministic mid-archive error on any platform.
  const zipFile = path.join(out, 'partial.zip')
  await assert.rejects(
    () =>
      zipDirectory(src, zipFile, {
        onProgress: () => {
          throw new Error('boom mid-archive')
        },
      }),
    /boom mid-archive/,
  )
  assert.ok(!fs.existsSync(zipFile), 'partial archive must be cleaned up on failure')

  // Control: without the failure the same call leaves a valid archive.
  const okFile = path.join(out, 'ok.zip')
  await zipDirectory(src, okFile)
  assert.ok(fs.existsSync(okFile))
  assert.deepEqual(listZip(okFile).map((e) => e.name), ['a.txt'])

  for (const dir of [src, out]) fs.rmSync(dir, { recursive: true, force: true })
})

test('unzip refuses traversal entries silently (sanitized)', async () => {
  const src = tmpDir()
  const out = tmpDir()
  const dest = tmpDir()
  fs.writeFileSync(path.join(src, 'ok.txt'), 'fine')
  const zipFile = path.join(out, 't.zip')
  await zipDirectory(src, zipFile)
  await unzip(zipFile, dest)
  assert.ok(fs.existsSync(path.join(dest, 'ok.txt')))
  for (const dir of [src, out, dest]) fs.rmSync(dir, { recursive: true, force: true })
})
