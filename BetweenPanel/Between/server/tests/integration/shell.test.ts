/**
 * Live web-shell integration test: boots the real app against the real Docker
 * daemon, starts a docker-runtime demo server (node:22-alpine) and opens the
 * interactive /shell WebSocket — a real `docker exec` /bin/sh TTY session.
 * Covers the happy path (command round-trip, shell state persisting across
 * commands, server-side close on `exit`) plus the gates: process-runtime
 * servers get a readable error frame instead of an exec, and unauthenticated
 * upgrades are refused with 401.
 *
 * Skipped automatically when no Docker daemon is reachable, so the suite
 * stays green on machines without Docker.
 */
import { test, before, after } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { WebSocket } from 'ws'
import { createApp, type BetweenApp } from '../../src/app.ts'
import { DockerService } from '../../src/services/docker.ts'
import { LABEL_SERVER_ID } from '../../src/servers/runtime.ts'
import { sleep } from '../../src/lib/util.ts'

const docker = new DockerService()
const dockerInfo = await docker.info()
const skip = dockerInfo.available ? false : `docker daemon not reachable (${dockerInfo.error ?? 'unknown'})`

const PORT = 28150

let app: BetweenApp | null = null
let base = ''
let cookie = ''
let dataDir = ''
let serverId = ''
let processServerId = ''

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

async function waitFor(pred: () => Promise<boolean> | boolean, timeoutMs: number, label: string): Promise<void> {
  const start = Date.now()
  while (Date.now() - start < timeoutMs) {
    if (await pred()) return
    await sleep(300)
  }
  throw new Error(`timeout waiting for: ${label}`)
}

async function serverStatus(id: string): Promise<string> {
  const res = await req('GET', `/api/servers/${id}`)
  return (res.json.server as { status: string }).status
}

function shellUrl(id: string): string {
  return `${base.replace('http', 'ws')}/api/servers/${id}/shell`
}

/** Open a shell ws and collect control frames + raw output separately. */
function openShell(id: string, withCookie = true, asCookie?: string) {
  const ws = new WebSocket(shellUrl(id), withCookie ? { headers: { cookie: asCookie ?? cookie } } : undefined)
  const state = { output: '', errors: [] as string[], ready: false }
  const closed = new Promise<void>((resolve) => ws.on('close', () => resolve()))
  ws.on('message', (raw) => {
    const text = String(raw)
    if (text.startsWith('{')) {
      try {
        const msg = JSON.parse(text) as { t?: string; message?: string }
        if (msg.t === 'ready') {
          state.ready = true
          return
        }
        if (msg.t === 'error') {
          state.errors.push(msg.message ?? '')
          return
        }
      } catch {
        /* raw output that merely looks like JSON */
      }
    }
    state.output += text
  })
  return { ws, state, closed }
}

before(async () => {
  if (skip) return
  dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'between-shell-e2e-'))
  app = createApp({ port: 0, host: '127.0.0.1', dataDir })
  const { port } = await app.start()
  base = `http://127.0.0.1:${port}`
  await req('POST', '/api/auth/setup', { username: 'admin', password: 'hunter2hunter2' })
  await req('POST', '/api/auth/login', { username: 'admin', password: 'hunter2hunter2' })
})

after(async () => {
  if (skip) return
  // Belt and braces: never leave containers behind, even on test failure.
  for (const id of [serverId, processServerId]) {
    if (!id) continue
    const entries = await docker.client.listByLabel(LABEL_SERVER_ID, id).catch(() => [])
    await Promise.allSettled(entries.map((e) => docker.client.removeContainer(e.Id, true)))
  }
  await app?.stop()
  if (dataDir) fs.rmSync(dataDir, { recursive: true, force: true })
})

test('create and start a docker-runtime demo server', { skip }, async () => {
  const res = await req('POST', '/api/servers', {
    name: 'Shell Demo',
    blueprintId: 'demo-echo',
    runtime: 'docker',
    variables: { SERVER_PORT: PORT },
  })
  assert.equal(res.status, 201, JSON.stringify(res.json))
  serverId = (res.json.server as { id: string }).id
  await waitFor(async () => (await serverStatus(serverId)) === 'offline', 30_000, 'install to finish')

  const start = await req('POST', `/api/servers/${serverId}/power`, { action: 'start' })
  assert.equal(start.status, 200, JSON.stringify(start.json))
  // First start may pull node:22-alpine — allow generous time.
  await waitFor(async () => (await serverStatus(serverId)) === 'running', 180_000, 'container to reach running')
})

test('interactive shell: round-trip, persistent session state, close on exit', { skip }, async () => {
  const { ws, state, closed } = openShell(serverId)
  await waitFor(() => state.ready || state.errors.length > 0, 30_000, 'shell ready frame')
  assert.deepEqual(state.errors, [], 'no error frame on the happy path')

  // Quotes keep the marker out of the TTY's echo of the typed command — the
  // match can only come from the executed echo's output.
  ws.send(JSON.stringify({ op: 'stdin', data: 'echo hello-from-"shell"\n' }))
  await waitFor(() => state.output.includes('hello-from-shell'), 20_000, 'echo output through the exec stream')

  // A real session: the cd must persist into the next command.
  ws.send(JSON.stringify({ op: 'stdin', data: 'cd /tmp\n' }))
  ws.send(JSON.stringify({ op: 'stdin', data: 'pwd\n' }))
  await waitFor(() => /^\/tmp$/m.test(state.output.replace(/\r/g, '')), 20_000, 'pwd reflects the earlier cd')

  // Resize + malformed frames are tolerated (no crash, session stays up).
  ws.send(JSON.stringify({ op: 'resize', cols: 120, rows: 30 }))
  ws.send('not json at all')
  ws.send(JSON.stringify({ op: 'stdin', data: 'echo still-"alive"\n' }))
  await waitFor(() => state.output.includes('still-alive'), 20_000, 'session survives malformed frames')

  // Exiting the shell must tear the session down from the server side.
  ws.send(JSON.stringify({ op: 'stdin', data: 'exit\n' }))
  await Promise.race([closed, sleep(15_000).then(() => Promise.reject(new Error('ws not closed after exit')))])
})

test('shell sessions do not disturb the running server', { skip }, async () => {
  assert.equal(await serverStatus(serverId), 'running')
  const entries = await docker.client.listByLabel(LABEL_SERVER_ID, serverId)
  assert.equal(entries.filter((e) => e.State === 'running').length, 1)
})

test('process-runtime server: readable error frame, no exec', { skip }, async () => {
  const res = await req('POST', '/api/servers', {
    name: 'Process Shell Probe',
    blueprintId: 'demo-echo',
    variables: { SERVER_PORT: PORT + 1 },
  })
  assert.equal(res.status, 201, JSON.stringify(res.json))
  processServerId = (res.json.server as { id: string }).id
  await waitFor(async () => (await serverStatus(processServerId)) === 'offline', 30_000, 'process install to finish')

  const { state, closed } = openShell(processServerId)
  await Promise.race([closed, sleep(15_000).then(() => Promise.reject(new Error('ws not closed after error')))])
  assert.equal(state.errors.length, 1)
  assert.match(state.errors[0], /docker-runtime/)
  assert.equal(state.ready, false, 'no ready frame — nothing was exec-ed')
  assert.equal(state.output, '')
})

test('shell upgrade without a session cookie is refused with 401', { skip }, async () => {
  await new Promise<void>((resolve, reject) => {
    const ws = new WebSocket(shellUrl(serverId))
    const timer = setTimeout(() => reject(new Error('no handshake response within 10s')), 10_000)
    ws.on('unexpected-response', (_req, res) => {
      clearTimeout(timer)
      try {
        assert.equal(res.statusCode, 401)
        resolve()
      } catch (err) {
        reject(err as Error)
      } finally {
        ws.terminate()
      }
    })
    ws.on('open', () => {
      clearTimeout(timer)
      reject(new Error('unauthenticated shell upgrade must not succeed'))
    })
    ws.on('error', () => {
      /* the refused handshake also emits an error — handled above */
    })
  })
})

test('malformed percent-escape in the server id is refused with 400', { skip }, async () => {
  await new Promise<void>((resolve, reject) => {
    const ws = new WebSocket(shellUrl('%zz'), { headers: { cookie } })
    const timer = setTimeout(() => reject(new Error('no handshake response within 10s')), 10_000)
    ws.on('unexpected-response', (_req, res) => {
      clearTimeout(timer)
      try {
        assert.equal(res.statusCode, 400)
        resolve()
      } catch (err) {
        reject(err as Error)
      } finally {
        ws.terminate()
      }
    })
    ws.on('open', () => {
      clearTimeout(timer)
      reject(new Error('malformed id must not open a shell'))
    })
    ws.on('error', () => {
      /* the refused handshake also emits an error — handled above */
    })
  })
})

test('multi-byte output split across stream chunks arrives intact', { skip }, async () => {
  const { ws, state } = openShell(serverId)
  await waitFor(() => state.ready, 30_000, 'utf8 shell ready')
  // 300k 3-byte € (~900 KB) guarantees stream-chunk boundaries that fall in
  // the middle of a code point — the bridge must never emit U+FFFD for them.
  ws.send(
    JSON.stringify({
      op: 'stdin',
      data: `awk 'BEGIN{for(i=0;i<300000;i++)printf "\\xe2\\x82\\xac"; print ""}'; echo TRANSFER-"DONE"\n`,
    }),
  )
  await waitFor(() => state.output.includes('TRANSFER-DONE'), 30_000, 'utf8 flood to finish')
  assert.equal((state.output.match(/\uFFFD/g) ?? []).length, 0, 'no replacement chars from split code points')
  const euros = (state.output.match(/€/g) ?? []).length
  assert.ok(euros >= 300_000, `every euro sign survives the chunk boundaries (got ${euros})`)
  ws.close()
})

test('a slow client is disconnected instead of buffering unbounded output', { skip }, async () => {
  const { ws, state, closed } = openShell(serverId)
  await waitFor(() => state.ready, 30_000, 'flood shell ready')
  // Simulate a stalled browser: stop reading, then flood stdout forever. The
  // panel must cut the session once its send buffer passes the cap — well
  // before the 30s ping reaper could (the paused client still pongs on resume).
  const raw = (ws as unknown as { _socket: { pause(): void; resume(): void } })._socket
  raw.pause()
  ws.send(JSON.stringify({ op: 'stdin', data: 'yes flood\n' }))
  await sleep(6000)
  raw.resume()
  await Promise.race([closed, sleep(15_000).then(() => Promise.reject(new Error('slow consumer was not disconnected')))])
  assert.equal(await serverStatus(serverId), 'running', 'the flood must only kill the session, not the server')
})

test('revoking server.config closes the session and blocks further input', { skip }, async () => {
  await req('POST', '/api/users', { username: 'revokee', password: 'hunter2hunter2', role: 'user' })
  const sub = await req('POST', `/api/servers/${serverId}/subusers`, { username: 'revokee', permissions: ['server.config'] })
  assert.equal(sub.status, 201, JSON.stringify(sub.json))
  const subId = (sub.json.subuser as { id: string }).id
  // Log in out-of-band so the admin cookie used by req() stays untouched.
  const login = await fetch(`${base}/api/auth/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ username: 'revokee', password: 'hunter2hunter2' }),
  })
  assert.equal(login.status, 200)
  const revokeeCookie = login.headers.get('set-cookie')!.split(';')[0]

  const { ws, state, closed } = openShell(serverId, true, revokeeCookie)
  await waitFor(() => state.ready, 30_000, 'revokee shell ready')
  ws.send(JSON.stringify({ op: 'stdin', data: 'echo before-"revoke"\n' }))
  await waitFor(() => state.output.includes('before-revoke'), 20_000, 'echo while still permitted')

  const del = await req('DELETE', `/api/servers/${serverId}/subusers/${subId}`)
  assert.equal(del.status, 200, JSON.stringify(del.json))
  // The next input must be rejected and tear the session down instead of
  // reaching the shell.
  ws.send(JSON.stringify({ op: 'stdin', data: 'echo after-"revoke"\n' }))
  await Promise.race([closed, sleep(15_000).then(() => Promise.reject(new Error('revoked session not closed')))])
  assert.ok(!state.output.includes('after-revoke'), 'input after revocation must never reach the shell')
})

test('stopping the server closes cleanly with a shell attached', { skip }, async () => {
  const { state, closed } = openShell(serverId)
  await waitFor(() => state.ready, 30_000, 'second shell ready')
  const res = await req('POST', `/api/servers/${serverId}/power`, { action: 'stop' })
  assert.equal(res.status, 200, JSON.stringify(res.json))
  await waitFor(async () => (await serverStatus(serverId)) === 'offline', 60_000, 'server to stop')
  // Container gone → exec stream dies → the ws must close, not linger.
  await Promise.race([closed, sleep(15_000).then(() => Promise.reject(new Error('shell ws not closed after server stop')))])
})
