/**
 * Metrics history integration test: boots the real app and exercises the two
 * in-memory sample rings that seed the UI charts — the host ring behind
 * GET /api/system/metrics and the per-server ring behind
 * GET /api/servers/:id/resources. Covers payload shape, the ?limit= trim,
 * ring retention across a game-server restart (while the panel runs), and
 * auth (401 unauthenticated, 403 without permission).
 */
import { test, before, after } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { createApp, type BetweenApp } from '../../src/app.ts'
import { sleep } from '../../src/lib/util.ts'

let app: BetweenApp
let base = ''
let cookie = ''
let dataDir = ''
let serverId = ''

interface HostSample {
  ts: number
  cpuPct: number
  memUsedBytes: number
  memTotalBytes: number
}

interface ResourceSample {
  ts: number
  cpuPct: number
  memBytes: number
  uptimeS: number
}

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

async function waitFor(pred: () => Promise<boolean>, timeoutMs: number, label: string): Promise<void> {
  const start = Date.now()
  while (Date.now() - start < timeoutMs) {
    if (await pred()) return
    await sleep(250)
  }
  throw new Error(`timeout waiting for: ${label}`)
}

async function serverStatus(): Promise<string> {
  const res = await req('GET', `/api/servers/${serverId}`)
  return (res.json.server as { status: string }).status
}

async function resourceHistory(query = ''): Promise<ResourceSample[]> {
  const res = await req('GET', `/api/servers/${serverId}/resources${query}`)
  assert.equal(res.status, 200)
  return res.json.history as ResourceSample[]
}

before(async () => {
  dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'between-metrics-'))
  app = createApp({ port: 0, host: '127.0.0.1', dataDir, webDistDir: path.join(dataDir, 'no-web') })
  const { port } = await app.start()
  base = `http://127.0.0.1:${port}`
})

after(async () => {
  await app.stop()
  fs.rmSync(dataDir, { recursive: true, force: true })
})

test('history endpoints require a session (401 unauthenticated)', async () => {
  assert.equal((await req('GET', '/api/system/metrics')).status, 401)
  assert.equal((await req('GET', '/api/servers/some-id/resources')).status, 401)
})

test('setup creates the first admin', async () => {
  const res = await req('POST', '/api/auth/setup', { username: 'admin', password: 'metrics-secret-1' })
  assert.equal(res.status, 200)
})

test('host metrics history is populated and has the expected shape', async () => {
  // The host sampler starts with the app and takes an immediate first sample.
  await waitFor(async () => {
    const res = await req('GET', '/api/system/metrics')
    return (res.json.history as HostSample[]).length >= 1
  }, 10_000, 'first host sample')

  const res = await req('GET', '/api/system/metrics')
  assert.equal(res.status, 200)
  const history = res.json.history as HostSample[]
  for (const snap of history) {
    assert.equal(typeof snap.ts, 'number')
    assert.equal(typeof snap.cpuPct, 'number')
    assert.ok(snap.memUsedBytes > 0)
    assert.ok(snap.memTotalBytes >= snap.memUsedBytes)
  }

  // ?limit=1 trims to exactly the newest sample.
  const limited = await req('GET', '/api/system/metrics?limit=1')
  const trimmed = limited.json.history as HostSample[]
  assert.equal(trimmed.length, 1)
  assert.equal(trimmed[0].ts, history[history.length - 1].ts)
})

test('per-server resource history accumulates while running', async () => {
  const created = await req('POST', '/api/servers', {
    name: 'Metrics Demo',
    blueprintId: 'demo-echo',
    variables: { SERVER_PORT: 28920 },
  })
  assert.equal(created.status, 201)
  serverId = (created.json.server as { id: string }).id
  await waitFor(async () => (await serverStatus()) === 'offline', 15_000, 'install to finish')

  // Before the first start the ring is empty but the shape is already there.
  assert.deepEqual(await resourceHistory(), [])

  const start = await req('POST', `/api/servers/${serverId}/power`, { action: 'start' })
  assert.equal(start.status, 200)
  await waitFor(async () => (await serverStatus()) === 'running', 20_000, 'server running')

  // 2.5s cadence on POSIX — two samples land well within the timeout.
  await waitFor(async () => (await resourceHistory()).length >= 2, 20_000, 'two resource samples')

  const history = await resourceHistory()
  for (const snap of history) {
    assert.equal(typeof snap.ts, 'number')
    assert.equal(typeof snap.cpuPct, 'number')
    assert.ok(snap.memBytes > 0)
    assert.equal(typeof snap.uptimeS, 'number')
  }
  for (let i = 1; i < history.length; i++) assert.ok(history[i].ts > history[i - 1].ts, 'samples are time-ordered')

  // ?limit=1 trims to the newest sample; `resources` mirrors it.
  const limitedRes = await req('GET', `/api/servers/${serverId}/resources?limit=1`)
  const limited = limitedRes.json.history as ResourceSample[]
  assert.equal(limited.length, 1)
  assert.equal(limited[0].ts, (limitedRes.json.resources as ResourceSample).ts)
})

test('resource history survives a server restart while the panel runs', async () => {
  const beforeStop = await resourceHistory()
  assert.ok(beforeStop.length >= 2)

  const stop = await req('POST', `/api/servers/${serverId}/power`, { action: 'stop' })
  assert.equal(stop.status, 200)
  await waitFor(async () => (await serverStatus()) === 'offline', 20_000, 'server offline')

  // The ring belongs to the instance, not to a single run.
  const afterStop = await resourceHistory()
  assert.ok(afterStop.length >= beforeStop.length, 'history retained after stop')
  assert.equal(afterStop[0].ts, beforeStop[0].ts)
})

test('per-server history is denied without permission (403)', async () => {
  const created = await req('POST', '/api/users', { username: 'bystander', password: 'bystander-pass-1', role: 'user' })
  assert.equal(created.status, 201)

  const adminCookie = cookie
  cookie = ''
  const login = await req('POST', '/api/auth/login', { username: 'bystander', password: 'bystander-pass-1' })
  assert.equal(login.status, 200)

  const res = await req('GET', `/api/servers/${serverId}/resources`)
  assert.equal(res.status, 403)

  // The host ring only needs a session — any logged-in user may read it.
  const host = await req('GET', '/api/system/metrics')
  assert.equal(host.status, 200)

  cookie = adminCookie
})

test('cleanup: delete the demo server', async () => {
  const del = await req('DELETE', `/api/servers/${serverId}`, { deleteBackups: true })
  assert.equal(del.status, 200)
})
