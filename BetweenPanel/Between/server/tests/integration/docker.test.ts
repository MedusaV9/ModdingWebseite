/**
 * Live docker-runtime integration test: boots the real app against the real
 * local Docker daemon, runs the built-in demo server inside a container
 * (node:22-alpine), drives it through the HTTP API (create → install → start
 * → console → stop), then proves the panel-restart survival story: the
 * container keeps running while the app restarts and is re-adopted.
 *
 * Skipped automatically when no Docker daemon is reachable, so the suite
 * stays green on machines without Docker.
 */
import { test, before, after } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { createApp, type BetweenApp } from '../../src/app.ts'
import { DockerService } from '../../src/services/docker.ts'
import { LABEL_SERVER_ID } from '../../src/servers/runtime.ts'
import { sleep } from '../../src/lib/util.ts'

const docker = new DockerService()
const dockerInfo = await docker.info()
const skip = dockerInfo.available ? false : `docker daemon not reachable (${dockerInfo.error ?? 'unknown'})`

const PORT = 28123

let app: BetweenApp | null = null
let base = ''
let cookie = ''
let dataDir = ''
let serverId = ''

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
    await sleep(300)
  }
  throw new Error(`timeout waiting for: ${label}`)
}

async function serverStatus(): Promise<string> {
  const res = await req('GET', `/api/servers/${serverId}`)
  return (res.json.server as { status: string }).status
}

async function startApp(): Promise<void> {
  app = createApp({ port: 0, host: '127.0.0.1', dataDir })
  const { port } = await app.start()
  base = `http://127.0.0.1:${port}`
}

before(async () => {
  if (skip) return
  dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'between-docker-e2e-'))
  await startApp()
  await req('POST', '/api/auth/setup', { username: 'admin', password: 'hunter2hunter2' })
  await req('POST', '/api/auth/login', { username: 'admin', password: 'hunter2hunter2' })
})

after(async () => {
  if (skip) return
  if (serverId) {
    // Belt and braces: never leave containers behind, even on test failure.
    const entries = await docker.client.listByLabel(LABEL_SERVER_ID, serverId).catch(() => [])
    await Promise.allSettled(entries.map((e) => docker.client.removeContainer(e.Id, true)))
  }
  await app?.stop()
  if (dataDir) fs.rmSync(dataDir, { recursive: true, force: true })
})

test('GET /api/docker/status reports the live daemon', { skip }, async () => {
  const res = await req('GET', '/api/docker/status')
  assert.equal(res.status, 200)
  assert.equal(res.json.available, true)
  assert.ok(res.json.version)
})

test('create a docker-runtime demo server (validates image + runtime)', { skip }, async () => {
  // Unknown image ref is rejected up front
  const bad = await req('POST', '/api/servers', {
    name: 'Bad Image',
    blueprintId: 'demo-echo',
    runtime: 'docker',
    docker: { image: 'not valid!!' },
    variables: { SERVER_PORT: PORT },
  })
  assert.equal(bad.status, 400)

  const res = await req('POST', '/api/servers', {
    name: 'Container Demo',
    blueprintId: 'demo-echo',
    runtime: 'docker',
    docker: { memoryMb: 256, cpus: 1 },
    variables: { SERVER_PORT: PORT },
  })
  assert.equal(res.status, 201, JSON.stringify(res.json))
  const server = res.json.server as { id: string; runtime: string; memoryLimitMb: number }
  serverId = server.id
  assert.equal(server.runtime, 'docker')
  // The hard container limit doubles as the display limit.
  assert.equal(server.memoryLimitMb, 256)
  await waitFor(async () => (await serverStatus()) === 'offline', 30_000, 'install to finish')

  // Clear the limits again via PATCH (also keeps this test portable: nested
  // sandboxes often lack the cgroup delegation needed to enforce them).
  const patched = await req('PATCH', `/api/servers/${serverId}`, { docker: { memoryMb: null, cpus: null } })
  assert.equal(patched.status, 200, JSON.stringify(patched.json))
  assert.equal((patched.json.server as { memoryLimitMb: number | null }).memoryLimitMb, null)
})

test('POST /servers/:id/docker/pull pulls the image with console progress', { skip }, async () => {
  // Precondition failures must surface as a 4xx, not a fire-and-forget 200.
  const proc = await req('POST', '/api/servers', {
    name: 'Process Demo',
    blueprintId: 'demo-echo',
    variables: { SERVER_PORT: PORT + 1 },
  })
  assert.equal(proc.status, 201, JSON.stringify(proc.json))
  const procId = (proc.json.server as { id: string }).id
  try {
    const refused = await req('POST', `/api/servers/${procId}/docker/pull`)
    assert.equal(refused.status, 400)
    assert.match(String(refused.json.error), /docker runtime/)
  } finally {
    await req('DELETE', `/api/servers/${procId}`, {})
  }

  const res = await req('POST', `/api/servers/${serverId}/docker/pull`)
  assert.equal(res.status, 200, JSON.stringify(res.json))
  // Progress + completion stream in as install lines; the first pull may
  // actually download node:22-alpine — allow generous time.
  await waitFor(async () => {
    const consoleRes = await req('GET', `/api/servers/${serverId}/console?limit=2000`)
    const lines = consoleRes.json.lines as { stream: string; line: string }[]
    return (
      lines.some((l) => l.stream === 'install' && l.line.includes('Pulling image node:22-alpine')) &&
      lines.some((l) => l.stream === 'install' && /^Image node:22-alpine (is up to date|updated)\./.test(l.line))
    )
  }, 180_000, 'pull progress + completion in the console')
  assert.equal(await docker.client.imageExists('node:22-alpine'), true, 'the image must be present after the pull')
})

test('start runs the demo inside a container; console works end to end', { skip }, async () => {
  const res = await req('POST', `/api/servers/${serverId}/power`, { action: 'start' })
  assert.equal(res.status, 200, JSON.stringify(res.json))
  // First start may pull node:22-alpine — allow generous time.
  await waitFor(async () => (await serverStatus()) === 'running', 180_000, 'container to reach running')

  // Exactly one container, labelled with our server id
  const entries = await docker.client.listByLabel(LABEL_SERVER_ID, serverId)
  assert.equal(entries.filter((e) => e.State === 'running').length, 1)

  // stdin via attach: say → echoed to stdout
  await req('POST', `/api/servers/${serverId}/command`, { command: 'say hello from docker' })
  await waitFor(async () => {
    const consoleRes = await req('GET', `/api/servers/${serverId}/console?limit=500`)
    const lines = consoleRes.json.lines as { line: string }[]
    return lines.some((l) => l.line.includes('hello from docker'))
  }, 15_000, 'console echo through the container attach stream')

  // Container stats flow into resource snapshots (memBytes may be 0 on hosts
  // without memory-cgroup delegation — presence of the sample is what counts)
  await waitFor(async () => {
    const resources = await req('GET', `/api/servers/${serverId}/resources`)
    const latest = resources.json.resources as { processes: number } | null
    return latest !== null && latest.processes >= 1
  }, 30_000, 'container stats sample')
})

test('pulling while the container runs leaves it untouched', { skip }, async () => {
  const before = (await docker.client.listByLabel(LABEL_SERVER_ID, serverId)).filter((e) => e.State === 'running')
  assert.equal(before.length, 1)
  // Completion lines from the earlier pull are still in the buffer — wait for
  // a NEW one instead of matching any.
  const doneCount = async () => {
    const consoleRes = await req('GET', `/api/servers/${serverId}/console?limit=2000`)
    const lines = consoleRes.json.lines as { line: string }[]
    return lines.filter((l) => /^Image node:22-alpine (is up to date|updated)\./.test(l.line)).length
  }
  const beforeCount = await doneCount()
  const res = await req('POST', `/api/servers/${serverId}/docker/pull`)
  assert.equal(res.status, 200, JSON.stringify(res.json))
  await waitFor(async () => (await doneCount()) > beforeCount, 120_000, 'second pull to finish')

  assert.equal(await serverStatus(), 'running', 'a pull must not touch the server status')
  const after = (await docker.client.listByLabel(LABEL_SERVER_ID, serverId)).filter((e) => e.State === 'running')
  assert.equal(after.length, 1)
  assert.equal(after[0].Id, before[0].Id, 'the running container must be left untouched')
  const consoleRes = await req('GET', `/api/servers/${serverId}/console?limit=2000`)
  assert.ok(
    (consoleRes.json.lines as { line: string }[]).some((l) => l.line.includes('the new one applies on the next start')),
    'the next-start caveat is surfaced in the console',
  )
})

test('panel restart: container survives and is re-adopted', { skip }, async () => {
  await app!.stop()
  // The workload must still be running without the panel.
  const survivors = await docker.client.listByLabel(LABEL_SERVER_ID, serverId)
  assert.equal(survivors.filter((e) => e.State === 'running').length, 1, 'container should survive panel shutdown')

  cookie = ''
  await startApp()
  await req('POST', '/api/auth/login', { username: 'admin', password: 'hunter2hunter2' })
  await waitFor(async () => (await serverStatus()) === 'running', 20_000, 're-adoption after panel restart')

  const consoleRes = await req('GET', `/api/servers/${serverId}/console?limit=500`)
  const lines = consoleRes.json.lines as { line: string }[]
  assert.ok(
    lines.some((l) => l.line.includes('Re-attached to running container')),
    'console should note the re-attach',
  )

  // Commands still work after re-adoption
  await req('POST', `/api/servers/${serverId}/command`, { command: 'say still alive' })
  await waitFor(async () => {
    const res = await req('GET', `/api/servers/${serverId}/console?limit=500`)
    return (res.json.lines as { line: string }[]).some((l) => l.line.includes('still alive'))
  }, 15_000, 'console echo after re-adoption')
})

test('graceful stop via stdin stop command; container is removed', { skip }, async () => {
  const res = await req('POST', `/api/servers/${serverId}/power`, { action: 'stop' })
  assert.equal(res.status, 200, JSON.stringify(res.json))
  await waitFor(async () => (await serverStatus()) === 'offline', 60_000, 'container to stop')
  await waitFor(async () => {
    const entries = await docker.client.listByLabel(LABEL_SERVER_ID, serverId)
    return entries.length === 0
  }, 15_000, 'container removal after exit')
})

test('deleting the server leaves no containers behind', { skip }, async () => {
  // Start again so deletion has a live container to clean up.
  await req('POST', `/api/servers/${serverId}/power`, { action: 'start' })
  await waitFor(async () => (await serverStatus()) === 'running', 60_000, 'second start')
  const del = await req('DELETE', `/api/servers/${serverId}`, {})
  assert.equal(del.status, 200)
  await waitFor(async () => {
    const entries = await docker.client.listByLabel(LABEL_SERVER_ID, serverId)
    return entries.length === 0
  }, 15_000, 'containers removed on server deletion')
  serverId = ''
})
