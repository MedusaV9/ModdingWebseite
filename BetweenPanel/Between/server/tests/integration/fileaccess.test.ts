/**
 * File-access (SFTP seam) API integration test: GET/PATCH /api/fileaccess
 * against the real app — honest placeholder status, config persistence,
 * refusal to enable in v1, and admin gating.
 */
import { test, before, after } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { createApp, type BetweenApp } from '../../src/app.ts'

let app: BetweenApp
let base = ''
let cookie = ''
let dataDir = ''

async function req(method: string, urlPath: string, body?: unknown): Promise<{ status: number; json: Record<string, unknown> }> {
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

before(async () => {
  dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'between-fileaccess-e2e-'))
  app = createApp({ port: 0, host: '127.0.0.1', dataDir, webDistDir: path.join(dataDir, 'no-web') })
  const { port } = await app.start()
  base = `http://127.0.0.1:${port}`
  await req('POST', '/api/auth/setup', { username: 'admin', password: 'hunter2hunter2' })
  await req('POST', '/api/auth/login', { username: 'admin', password: 'hunter2hunter2' })
})

after(async () => {
  await app.stop()
  if (dataDir) fs.rmSync(dataDir, { recursive: true, force: true })
})

test('status reports the honest placeholder state with defaults', async () => {
  const res = await req('GET', '/api/fileaccess')
  assert.equal(res.status, 200, JSON.stringify(res.json))
  const sftp = res.json.sftp as { protocol: string; implemented: boolean; running: boolean; config: Record<string, unknown>; reason?: string }
  assert.equal(sftp.protocol, 'sftp')
  assert.equal(sftp.implemented, false)
  assert.equal(sftp.running, false)
  assert.deepEqual(sftp.config, { enabled: false, port: 2022, bind: '0.0.0.0' })
  assert.match(sftp.reason ?? '', /later wave/)
})

test('port/bind config persists; enabling is refused in v1', async () => {
  const patch = await req('PATCH', '/api/fileaccess', { port: 2222, bind: '127.0.0.1' })
  assert.equal(patch.status, 200, JSON.stringify(patch.json))
  const after = await req('GET', '/api/fileaccess')
  assert.deepEqual((after.json.sftp as { config: unknown }).config, { enabled: false, port: 2222, bind: '127.0.0.1' })

  const enable = await req('PATCH', '/api/fileaccess', { enabled: true })
  assert.equal(enable.status, 400)
  assert.match(String(enable.json.error), /not implemented/)

  const badPort = await req('PATCH', '/api/fileaccess', { port: 70000 })
  assert.equal(badPort.status, 400)
})

test('file-access endpoints are admin-only', async () => {
  await req('POST', '/api/users', { username: 'pleb', password: 'hunter2hunter2', role: 'user' })
  const adminCookie = cookie
  cookie = ''
  await req('POST', '/api/auth/login', { username: 'pleb', password: 'hunter2hunter2' })
  assert.equal((await req('GET', '/api/fileaccess')).status, 403)
  assert.equal((await req('PATCH', '/api/fileaccess', { port: 2222 })).status, 403)
  cookie = adminCookie
})
