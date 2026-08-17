/**
 * File manager integration test: boots the real app and exercises the
 * AMP-class file operations end to end — same-directory rename (409 on
 * collision), copy/move with the " (2)" auto-suffix collision convention,
 * zip-from-selection, extract round-trips (content hash compare), zip-slip
 * and zip-bomb hardening, and the read-only-subuser permission wall.
 */
import { test, before, after } from 'node:test'
import assert from 'node:assert/strict'
import crypto from 'node:crypto'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { createApp, type BetweenApp } from '../../src/app.ts'
import { sleep } from '../../src/lib/util.ts'
import { crc32 } from '../../src/lib/zip.ts'

let app: BetweenApp
let base = ''
let cookie = ''
let dataDir = ''
let serverId = ''

async function req(
  method: string,
  urlPath: string,
  body?: unknown,
): Promise<{ status: number; json: Record<string, unknown> }> {
  const res = await fetch(`${base}${urlPath}`, {
    method,
    headers: {
      ...(body !== undefined ? { 'content-type': 'application/json' } : {}),
      ...(cookie ? { cookie } : {}),
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  })
  const setCookie = res.headers.get('set-cookie')
  if (setCookie) cookie = setCookie.split(';')[0]
  const text = await res.text()
  return { status: res.status, json: text ? (JSON.parse(text) as Record<string, unknown>) : {} }
}

async function listNames(dir: string): Promise<string[]> {
  const res = await req('GET', `/api/servers/${serverId}/files?path=${encodeURIComponent(dir)}`)
  assert.equal(res.status, 200)
  return (res.json.entries as { name: string }[]).map((e) => e.name)
}

async function writeFile(rel: string, content: string): Promise<void> {
  const res = await req('PUT', `/api/servers/${serverId}/files/content`, { path: rel, content })
  assert.equal(res.status, 200)
}

async function uploadRaw(name: string, data: Buffer): Promise<number> {
  const res = await fetch(`${base}/api/servers/${serverId}/files/upload?path=&name=${encodeURIComponent(name)}`, {
    method: 'PUT',
    headers: { cookie, 'content-type': 'application/octet-stream' },
    body: data,
  })
  await res.text()
  return res.status
}

async function downloadHash(rel: string): Promise<string> {
  const res = await fetch(`${base}/api/servers/${serverId}/files/download?path=${encodeURIComponent(rel)}`, {
    headers: { cookie },
  })
  assert.equal(res.status, 200)
  return crypto.createHash('sha256').update(Buffer.from(await res.arrayBuffer())).digest('hex')
}

/**
 * Hand-rolled zip bytes (stored entries, no descriptors) so tests can craft
 * archives the production writer refuses to produce: traversal names,
 * absolute names, and central directories that lie about uncompressed sizes.
 */
function craftZip(entries: { name: string; data?: Buffer; usize?: number }[]): Buffer {
  const parts: Buffer[] = []
  const central: Buffer[] = []
  let offset = 0
  for (const e of entries) {
    const data = e.data ?? Buffer.alloc(0)
    const name = Buffer.from(e.name, 'utf8')
    const crc = crc32(data)
    const usize = e.usize ?? data.length
    const local = Buffer.alloc(30)
    local.writeUInt32LE(0x04034b50, 0)
    local.writeUInt16LE(20, 4)
    local.writeUInt16LE(0, 6)
    local.writeUInt16LE(0, 8) // stored
    local.writeUInt16LE(0, 10)
    local.writeUInt16LE(0x21, 12)
    local.writeUInt32LE(crc, 14)
    local.writeUInt32LE(data.length, 18)
    local.writeUInt32LE(usize, 22)
    local.writeUInt16LE(name.length, 26)
    local.writeUInt16LE(0, 28)
    const cen = Buffer.alloc(46)
    cen.writeUInt32LE(0x02014b50, 0)
    cen.writeUInt16LE(0x031e, 4)
    cen.writeUInt16LE(20, 6)
    cen.writeUInt16LE(0, 8)
    cen.writeUInt16LE(0, 10) // stored
    cen.writeUInt16LE(0, 12)
    cen.writeUInt16LE(0x21, 14)
    cen.writeUInt32LE(crc, 16)
    cen.writeUInt32LE(data.length, 20)
    cen.writeUInt32LE(usize, 24)
    cen.writeUInt16LE(name.length, 28)
    cen.writeUInt16LE(0, 30)
    cen.writeUInt16LE(0, 32)
    cen.writeUInt16LE(0, 34)
    cen.writeUInt16LE(0, 36)
    cen.writeUInt32LE(0, 38)
    cen.writeUInt32LE(offset, 42)
    central.push(Buffer.concat([cen, name]))
    parts.push(local, name, data)
    offset += 30 + name.length + data.length
  }
  const cd = Buffer.concat(central)
  const eocd = Buffer.alloc(22)
  eocd.writeUInt32LE(0x06054b50, 0)
  eocd.writeUInt16LE(0, 4)
  eocd.writeUInt16LE(0, 6)
  eocd.writeUInt16LE(entries.length, 8)
  eocd.writeUInt16LE(entries.length, 10)
  eocd.writeUInt32LE(cd.length, 12)
  eocd.writeUInt32LE(offset, 16)
  eocd.writeUInt16LE(0, 20)
  return Buffer.concat([...parts, cd, eocd])
}

before(async () => {
  dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'between-files-'))
  app = createApp({ port: 0, host: '127.0.0.1', dataDir, webDistDir: path.join(dataDir, 'no-web') })
  const { port } = await app.start()
  base = `http://127.0.0.1:${port}`

  await req('POST', '/api/auth/setup', { username: 'admin', password: 'super-secret-1', panelName: 'Files E2E' })
  const created = await req('POST', '/api/servers', {
    name: 'Files Demo',
    blueprintId: 'demo-echo',
    variables: { SERVER_PORT: 28907 },
    autoStart: false,
    startAfterInstall: false,
  })
  assert.equal(created.status, 201)
  serverId = (created.json.server as { id: string }).id
  const start = Date.now()
  for (;;) {
    const res = await req('GET', `/api/servers/${serverId}`)
    if ((res.json.server as { status: string }).status === 'offline') break
    if (Date.now() - start > 15_000) throw new Error('timeout waiting for install')
    await sleep(250)
  }
})

after(async () => {
  await app.stop()
  fs.rmSync(dataDir, { recursive: true, force: true })
})

test('rename: same-directory rename, 409 on collision, invalid names rejected', async () => {
  await writeFile('r1.txt', 'one')
  await writeFile('r2.txt', 'two')

  const ok = await req('POST', `/api/servers/${serverId}/files/rename`, { path: 'r1.txt', newName: 'r1-new.txt' })
  assert.equal(ok.status, 200)
  const names = await listNames('')
  assert.ok(names.includes('r1-new.txt') && !names.includes('r1.txt'))

  const conflict = await req('POST', `/api/servers/${serverId}/files/rename`, { path: 'r2.txt', newName: 'r1-new.txt' })
  assert.equal(conflict.status, 409)

  const slash = await req('POST', `/api/servers/${serverId}/files/rename`, { path: 'r2.txt', newName: 'sub/r2.txt' })
  assert.equal(slash.status, 400)
  const dots = await req('POST', `/api/servers/${serverId}/files/rename`, { path: 'r2.txt', newName: '..' })
  assert.equal(dots.status, 400)
  const backslash = await req('POST', `/api/servers/${serverId}/files/rename`, { path: 'r2.txt', newName: 'a\\b' })
  assert.equal(backslash.status, 400)

  const traversal = await req('POST', `/api/servers/${serverId}/files/rename`, { path: '../outside.txt', newName: 'x.txt' })
  assert.equal(traversal.status, 400)
  const missing = await req('POST', `/api/servers/${serverId}/files/rename`, { path: 'nope.txt', newName: 'x.txt' })
  assert.equal(missing.status, 404)
})

test('copy: file with auto-suffix collision convention, recursive directory copy', async () => {
  await writeFile('dup.txt', 'dup content')

  const first = await req('POST', `/api/servers/${serverId}/files/copy`, { path: 'dup.txt', toDir: '' })
  assert.equal(first.status, 200)
  assert.equal(first.json.name, 'dup (2).txt')
  const second = await req('POST', `/api/servers/${serverId}/files/copy`, { path: 'dup.txt', toDir: '' })
  assert.equal(second.json.name, 'dup (3).txt')
  const read = await req('GET', `/api/servers/${serverId}/files/content?path=${encodeURIComponent('dup (2).txt')}`)
  assert.equal(read.json.content, 'dup content')

  await writeFile('cdir/inner/f.txt', 'deep file')
  await req('POST', `/api/servers/${serverId}/files/mkdir`, { path: 'ctarget' })
  const dirCopy = await req('POST', `/api/servers/${serverId}/files/copy`, { path: 'cdir', toDir: 'ctarget' })
  assert.equal(dirCopy.status, 200)
  assert.equal(dirCopy.json.name, 'cdir')
  const deep = await req('GET', `/api/servers/${serverId}/files/content?path=${encodeURIComponent('ctarget/cdir/inner/f.txt')}`)
  assert.equal(deep.json.content, 'deep file')

  const intoSelf = await req('POST', `/api/servers/${serverId}/files/copy`, { path: 'cdir', toDir: 'cdir' })
  assert.equal(intoSelf.status, 400)
  const traversal = await req('POST', `/api/servers/${serverId}/files/copy`, { path: 'dup.txt', toDir: '../../' })
  assert.equal(traversal.status, 400)
})

test('move: file and directory, same-folder and own-subtree rejected, collision suffixed', async () => {
  await writeFile('mv.txt', 'move me')
  await req('POST', `/api/servers/${serverId}/files/mkdir`, { path: 'mdest' })

  const mv = await req('POST', `/api/servers/${serverId}/files/move`, { path: 'mv.txt', toDir: 'mdest' })
  assert.equal(mv.status, 200)
  assert.equal(mv.json.name, 'mv.txt')
  const root = await listNames('')
  assert.ok(!root.includes('mv.txt'))
  assert.ok((await listNames('mdest')).includes('mv.txt'))

  // Collision on move: the incoming file is suffixed, the existing one untouched.
  await writeFile('mv.txt', 'second one')
  const collide = await req('POST', `/api/servers/${serverId}/files/move`, { path: 'mv.txt', toDir: 'mdest' })
  assert.equal(collide.status, 200)
  assert.equal(collide.json.name, 'mv (2).txt')

  const sameDir = await req('POST', `/api/servers/${serverId}/files/move`, { path: 'mdest/mv.txt', toDir: 'mdest' })
  assert.equal(sameDir.status, 400)

  await writeFile('mdir/sub/keep.txt', 'x')
  const ownSubtree = await req('POST', `/api/servers/${serverId}/files/move`, { path: 'mdir', toDir: 'mdir/sub' })
  assert.equal(ownSubtree.status, 400)
  const dirMove = await req('POST', `/api/servers/${serverId}/files/move`, { path: 'mdir', toDir: 'mdest' })
  assert.equal(dirMove.status, 200)
  assert.ok((await listNames('mdest/mdir/sub')).includes('keep.txt'))
})

test('zip selection → archive in the listing; duplicate archive name is 409', async () => {
  await writeFile('ziptest/a.txt', 'alpha')
  await writeFile('ziptest/nested/b.txt', 'beta')
  await writeFile('ziptest/loose.txt', 'gamma')

  const zip = await req('POST', `/api/servers/${serverId}/files/zip`, {
    paths: ['ziptest/a.txt', 'ziptest/nested'],
    archiveName: 'picked',
  })
  assert.equal(zip.status, 200)
  assert.equal(zip.json.dest, 'ziptest/picked.zip')
  assert.ok((await listNames('ziptest')).includes('picked.zip'))

  const again = await req('POST', `/api/servers/${serverId}/files/zip`, {
    paths: ['ziptest/a.txt'],
    archiveName: 'picked.zip',
  })
  assert.equal(again.status, 409)

  const mixedDirs = await req('POST', `/api/servers/${serverId}/files/zip`, {
    paths: ['ziptest/a.txt', 'ziptest/nested/b.txt'],
    archiveName: 'nope',
  })
  assert.equal(mixedDirs.status, 400)

  // Selection semantics: entries are relative to the selection's folder and
  // unselected siblings (loose.txt) stay out.
  await req('POST', `/api/servers/${serverId}/files/mkdir`, { path: 'zipout' })
  const extract = await req('POST', `/api/servers/${serverId}/files/extract`, { path: 'ziptest/picked.zip', toDir: 'zipout' })
  assert.equal(extract.status, 200)
  const out = await listNames('zipout')
  assert.ok(out.includes('a.txt') && out.includes('nested') && !out.includes('loose.txt'))
})

test('extract round-trip: zip a dir, extract elsewhere, file hashes match', async () => {
  const payload = crypto.randomBytes(2048)
  const up = await uploadRaw('blob.bin', payload)
  assert.equal(up, 200)
  await req('POST', `/api/servers/${serverId}/files/mkdir`, { path: 'rt-src' })
  const moved = await req('POST', `/api/servers/${serverId}/files/move`, { path: 'blob.bin', toDir: 'rt-src' })
  assert.equal(moved.status, 200)
  await writeFile('rt-src/text.txt', 'round trip text')

  const zip = await req('POST', `/api/servers/${serverId}/files/zip`, { paths: ['rt-src'], archiveName: 'rt' })
  assert.equal(zip.status, 200)
  assert.equal(zip.json.files, 2)

  await req('POST', `/api/servers/${serverId}/files/mkdir`, { path: 'rt-out' })
  const extract = await req('POST', `/api/servers/${serverId}/files/extract`, { path: 'rt.zip', toDir: 'rt-out' })
  assert.equal(extract.status, 200)
  assert.equal(extract.json.files, 2)

  assert.equal(await downloadHash('rt-out/rt-src/blob.bin'), await downloadHash('rt-src/blob.bin'))
  const text = await req('GET', `/api/servers/${serverId}/files/content?path=${encodeURIComponent('rt-out/rt-src/text.txt')}`)
  assert.equal(text.json.content, 'round trip text')
})

test('extract defaults to the archive directory when toDir is omitted', async () => {
  await writeFile('inplace/src/one.txt', 'in place')
  const zip = await req('POST', `/api/servers/${serverId}/files/zip`, { paths: ['inplace/src'], archiveName: 'here' })
  assert.equal(zip.status, 200)
  await req('POST', `/api/servers/${serverId}/files/delete`, { paths: ['inplace/src'] })
  const extract = await req('POST', `/api/servers/${serverId}/files/extract`, { path: 'inplace/here.zip' })
  assert.equal(extract.status, 200)
  const back = await req('GET', `/api/servers/${serverId}/files/content?path=${encodeURIComponent('inplace/src/one.txt')}`)
  assert.equal(back.json.content, 'in place')
})

test('zip-slip: traversal and absolute entries never land outside the target', async () => {
  const evil = craftZip([
    { name: '../../../evil-escape.txt', data: Buffer.from('pwned') },
    { name: '/abs-escape.txt', data: Buffer.from('pwned') },
    { name: 'ok.txt', data: Buffer.from('benign') },
  ])
  assert.equal(await uploadRaw('evil.zip', evil), 200)
  await req('POST', `/api/servers/${serverId}/files/mkdir`, { path: 'sliptest' })
  const extract = await req('POST', `/api/servers/${serverId}/files/extract`, { path: 'evil.zip', toDir: 'sliptest' })
  assert.equal(extract.status, 200)
  assert.equal(extract.json.files, 1, 'only the benign entry is written')

  // Server dirs are named by dirName (slug), not id — discover the only one.
  const serversRoot = path.join(dataDir, 'servers')
  const serverDir = path.join(serversRoot, fs.readdirSync(serversRoot)[0])
  // The write must land nowhere outside sliptest/: probe every level the
  // crafted `../` chain could have reached, plus the filesystem root names.
  for (const escaped of [
    path.join(dataDir, 'evil-escape.txt'),
    path.join(dataDir, 'servers', 'evil-escape.txt'),
    path.join(serverDir, 'evil-escape.txt'),
    path.join(serverDir, 'abs-escape.txt'),
    '/abs-escape.txt',
    '/evil-escape.txt',
  ]) {
    assert.ok(!fs.existsSync(escaped), `escaped file must not exist: ${escaped}`)
  }
  assert.ok(fs.existsSync(path.join(serverDir, 'sliptest', 'ok.txt')))
  assert.ok(!fs.existsSync(path.join(serverDir, 'sliptest', 'evil-escape.txt')))
})

test('zip bomb: archive declaring more than the extraction budget is rejected', async () => {
  const bomb = craftZip(
    Array.from({ length: 17 }, (_, i) => ({
      name: `f${i}.bin`,
      data: Buffer.from('tiny'),
      usize: 0xfffffff0, // central directory lies: ~4 GiB × 17 > 64 GiB budget
    })),
  )
  assert.equal(await uploadRaw('bomb.zip', bomb), 200)
  await req('POST', `/api/servers/${serverId}/files/mkdir`, { path: 'bombout' })
  const extract = await req('POST', `/api/servers/${serverId}/files/extract`, { path: 'bomb.zip', toDir: 'bombout' })
  assert.equal(extract.status, 400)
  assert.match(String(extract.json.error), /too large/i)
  assert.deepEqual(await listNames('bombout'), [], 'nothing may be written before the budget check')
})

test('extract rejects unsupported archive formats', async () => {
  await writeFile('not-an-archive.txt', 'plain text')
  const res = await req('POST', `/api/servers/${serverId}/files/extract`, { path: 'not-an-archive.txt' })
  assert.equal(res.status, 400)
  assert.match(String(res.json.error), /unsupported/i)
})

test('read-only subuser: listing works, every mutation is 403', async () => {
  await req('POST', '/api/users', { username: 'reader', password: 'reader-pass-1', role: 'user' })
  const sub = await req('POST', `/api/servers/${serverId}/subusers`, {
    username: 'reader',
    permissions: ['server.view', 'server.files.read'],
  })
  assert.equal(sub.status, 201)

  const adminCookie = cookie
  cookie = ''
  const login = await req('POST', '/api/auth/login', { username: 'reader', password: 'reader-pass-1' })
  assert.equal(login.status, 200)

  const list = await req('GET', `/api/servers/${serverId}/files?path=`)
  assert.equal(list.status, 200)

  const mutations: [string, string, unknown][] = [
    ['POST', 'rename', { path: 'r1-new.txt', newName: 'stolen.txt' }],
    ['POST', 'copy', { path: 'r1-new.txt', toDir: 'mdest' }],
    ['POST', 'move', { path: 'r1-new.txt', toDir: 'mdest' }],
    ['POST', 'zip', { paths: ['r1-new.txt'], archiveName: 'nope' }],
    ['POST', 'extract', { path: 'rt.zip' }],
    ['POST', 'delete', { paths: ['r1-new.txt'] }],
    ['POST', 'mkdir', { path: 'readonly-dir' }],
  ]
  for (const [method, op, body] of mutations) {
    const res = await req(method, `/api/servers/${serverId}/files/${op}`, body)
    assert.equal(res.status, 403, `files/${op} must be denied for a read-only subuser`)
  }
  const write = await req('PUT', `/api/servers/${serverId}/files/content`, { path: 'x.txt', content: 'x' })
  assert.equal(write.status, 403)
  assert.equal(await uploadRaw('x.bin', Buffer.from('x')), 403)

  cookie = adminCookie
})
