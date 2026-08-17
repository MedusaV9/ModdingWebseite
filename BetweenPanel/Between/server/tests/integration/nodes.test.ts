/**
 * Multi-node integration test: boots TWO real in-process apps — the panel
 * (normal mode) and a node agent (BETWEEN_MODE=node equivalent via config
 * overrides: bearer-token auth, no users/sessions/web UI) — and walks the
 * full remote-server journey across the HTTP hop:
 *
 *   agent identity/auth → node registration (admin-only, token redacted) →
 *   health poll → connectivity test → remote create with embedded blueprint
 *   → install → start → command → console proxy → resources proxy → live
 *   console over the panel's OWN WebSocket (node stream bridge) → stop →
 *   delete → node-offline degradation (mirrored listing + 502s) → node
 *   removal cleanup.
 */
import { test, before, after } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { WebSocket } from 'ws'
import { createApp, type BetweenApp } from '../../src/app.ts'
import { sleep } from '../../src/lib/util.ts'

const NODE_TOKEN = 'integration-node-token-123456'
const WRONG_TOKEN = 'wrong-token-that-is-long-enough'

let agent: BetweenApp
let panel: BetweenApp
let agentBase = ''
let panelBase = ''
let agentDataDir = ''
let panelDataDir = ''
let cookie = ''
let memberCookie = ''
let nodeId = ''
let remoteId = ''
let probeId = ''

async function api(
  base: string,
  method: string,
  urlPath: string,
  body?: unknown,
  headers: Record<string, string> = {},
): Promise<{ status: number; json: Record<string, unknown> }> {
  const res = await fetch(`${base}${urlPath}`, {
    method,
    headers: { ...(body !== undefined ? { 'content-type': 'application/json' } : {}), ...headers },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  })
  const text = await res.text()
  return { status: res.status, json: text ? (JSON.parse(text) as Record<string, unknown>) : {} }
}

/** Panel request with the admin session cookie. */
async function preq(method: string, urlPath: string, body?: unknown, asCookie?: string) {
  const res = await fetch(`${panelBase}${urlPath}`, {
    method,
    headers: {
      ...(body !== undefined ? { 'content-type': 'application/json' } : {}),
      ...(asCookie ?? cookie ? { cookie: asCookie ?? cookie } : {}),
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  })
  const setCookie = res.headers.get('set-cookie')
  if (setCookie && !asCookie) cookie = setCookie.split(';')[0]
  const text = await res.text()
  return { status: res.status, json: text ? (JSON.parse(text) as Record<string, unknown>) : {} }
}

/** Agent request with the node bearer token. */
function areq(method: string, urlPath: string, body?: unknown, token: string = NODE_TOKEN) {
  return api(agentBase, method, urlPath, body, { authorization: `Bearer ${token}` })
}

async function waitFor(pred: () => Promise<boolean>, timeoutMs: number, label: string): Promise<void> {
  const start = Date.now()
  while (Date.now() - start < timeoutMs) {
    if (await pred()) return
    await sleep(250)
  }
  throw new Error(`timeout waiting for: ${label}`)
}

async function remoteDetail(id: string): Promise<Record<string, unknown>> {
  const res = await preq('GET', `/api/servers/${id}`)
  return res.json.server as Record<string, unknown>
}

before(async () => {
  agentDataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'between-agent-'))
  panelDataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'between-nodes-'))
  agent = createApp({
    mode: 'node',
    nodeToken: NODE_TOKEN,
    nodeName: 'test-node',
    port: 0,
    host: '127.0.0.1',
    dataDir: agentDataDir,
    webDistDir: path.join(agentDataDir, 'no-web'),
  })
  panel = createApp({
    mode: 'panel',
    nodeToken: null,
    port: 0,
    host: '127.0.0.1',
    dataDir: panelDataDir,
    webDistDir: path.join(panelDataDir, 'no-web'),
    nodePollMs: 1000,
  })
  const [a, p] = await Promise.all([agent.start(), panel.start()])
  agentBase = `http://127.0.0.1:${a.port}`
  panelBase = `http://127.0.0.1:${p.port}`
  await preq('POST', '/api/auth/setup', { username: 'admin', password: 'super-secret-1', panelName: 'Nodes E2E' })
})

after(async () => {
  await panel.stop()
  await agent.stop() // no-op if the offline test already stopped it
  fs.rmSync(agentDataDir, { recursive: true, force: true })
  fs.rmSync(panelDataDir, { recursive: true, force: true })
})

// --- Agent mode fundamentals ---------------------------------------------------

test('node mode refuses to boot without a strong token', () => {
  assert.throws(() => createApp({ mode: 'node', nodeToken: null, dataDir: agentDataDir }), /BETWEEN_NODE_TOKEN/)
  assert.throws(() => createApp({ mode: 'node', nodeToken: 'short', dataDir: agentDataDir }), /BETWEEN_NODE_TOKEN/)
})

test('agent root returns a tiny identity JSON without auth', async () => {
  const res = await api(agentBase, 'GET', '/')
  assert.equal(res.status, 200)
  assert.equal(res.json.between, 'node')
  assert.equal(res.json.name, 'test-node')
  assert.equal(typeof res.json.version, 'string')
})

test('agent rejects missing and wrong tokens with 401', async () => {
  assert.equal((await api(agentBase, 'GET', '/api/node/identity')).status, 401)
  assert.equal((await api(agentBase, 'GET', '/api/servers')).status, 401)
  assert.equal((await areq('GET', '/api/servers', undefined, WRONG_TOKEN)).status, 401)
})

test('agent accepts the token and reports its identity', async () => {
  const res = await areq('GET', '/api/node/identity')
  assert.equal(res.status, 200)
  assert.equal(res.json.name, 'test-node')
  assert.equal(res.json.platform, process.platform)
  assert.equal(res.json.arch, process.arch)
  const servers = await areq('GET', '/api/servers')
  assert.equal(servers.status, 200)
  assert.deepEqual(servers.json.servers, [])
})

test('agent has no user/session surface and serves no web UI', async () => {
  assert.equal((await areq('POST', '/api/auth/login', { username: 'a', password: 'b' })).status, 404)
  assert.equal((await areq('GET', '/api/users')).status, 404)
  assert.equal((await areq('GET', '/api/nodes')).status, 404)
  const root = await fetch(`${agentBase}/setup`)
  assert.equal(root.status, 404)
})

test('agent websocket handshake requires the bearer token', async () => {
  const ws = new WebSocket(`${agentBase.replace('http', 'ws')}/api/ws`)
  await new Promise<void>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('unauthenticated agent ws was not refused')), 5000)
    ws.once('error', () => {
      clearTimeout(timer)
      resolve()
    })
    ws.once('open', () => {
      clearTimeout(timer)
      reject(new Error('unauthenticated agent ws opened'))
    })
  })
})

// --- Node registration (panel) ---------------------------------------------------

test('node management is admin-only', async () => {
  assert.equal((await api(panelBase, 'GET', '/api/nodes')).status, 401)
  await preq('POST', '/api/users', { username: 'member', password: 'member-pass-123', role: 'user' })
  const login = await fetch(`${panelBase}/api/auth/login`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ username: 'member', password: 'member-pass-123' }),
  })
  memberCookie = (login.headers.get('set-cookie') ?? '').split(';')[0]
  assert.ok(memberCookie.includes('between_session='))
  assert.equal((await preq('GET', '/api/nodes', undefined, memberCookie)).status, 403)
  assert.equal((await preq('POST', '/api/nodes', { name: 'x', baseUrl: agentBase, token: NODE_TOKEN }, memberCookie)).status, 403)
})

test('node registration validates its input', async () => {
  assert.equal((await preq('POST', '/api/nodes', { name: 'bad', baseUrl: 'ftp://x', token: NODE_TOKEN })).status, 400)
  assert.equal((await preq('POST', '/api/nodes', { name: 'bad', baseUrl: agentBase, token: 'short' })).status, 400)
  assert.equal((await preq('POST', '/api/nodes', { name: '', baseUrl: agentBase, token: NODE_TOKEN })).status, 400)
})

test('registering the node succeeds and NEVER returns the token', async () => {
  const res = await preq('POST', '/api/nodes', { name: 'test-node', baseUrl: agentBase, token: NODE_TOKEN })
  assert.equal(res.status, 201)
  const node = res.json.node as Record<string, unknown>
  nodeId = String(node.id)
  assert.equal(node.name, 'test-node')
  assert.equal(node.baseUrl, agentBase)
  assert.ok(!('token' in node), 'token must be redacted')
  assert.ok(!JSON.stringify(res.json).includes(NODE_TOKEN))

  const list = await preq('GET', '/api/nodes')
  assert.equal(list.status, 200)
  assert.ok(!JSON.stringify(list.json).includes(NODE_TOKEN))

  const dup = await preq('POST', '/api/nodes', { name: 'again', baseUrl: agentBase, token: NODE_TOKEN })
  assert.equal(dup.status, 400)
})

test('health poll marks the node online with system metrics fields', async () => {
  await waitFor(async () => {
    const res = await preq('GET', '/api/nodes')
    const node = (res.json.nodes as Record<string, unknown>[]).find((n) => n.id === nodeId)
    return Boolean((node?.health as Record<string, unknown>)?.online)
  }, 10_000, 'node health to come online')
  const res = await preq('GET', '/api/nodes')
  const node = (res.json.nodes as Record<string, unknown>[]).find((n) => n.id === nodeId)!
  const health = node.health as Record<string, unknown>
  assert.equal(health.online, true)
  assert.equal(typeof health.lastSeen, 'string')
  assert.equal(typeof health.latencyMs, 'number')
  assert.equal(typeof health.version, 'string')
})

test('connectivity test returns identity and latency', async () => {
  const res = await preq('POST', `/api/nodes/${nodeId}/test`)
  assert.equal(res.status, 200)
  assert.equal(res.json.ok, true)
  assert.equal((res.json.identity as Record<string, unknown>).name, 'test-node')
  assert.equal(typeof res.json.latencyMs, 'number')
})

test('connectivity test surfaces a wrong token as a diagnostic failure', async () => {
  // Same agent, but registered via the localhost alias (different origin
  // string) with a WRONG token — the duplicate-baseUrl guard stays intact.
  const alias = agentBase.replace('127.0.0.1', 'localhost')
  const res = await preq('POST', '/api/nodes', { name: 'impostor', baseUrl: alias, token: WRONG_TOKEN })
  assert.equal(res.status, 201)
  const impostorId = String((res.json.node as Record<string, unknown>).id)
  const probe = await preq('POST', `/api/nodes/${impostorId}/test`)
  assert.equal(probe.status, 200)
  assert.equal(probe.json.ok, false)
  assert.equal(typeof probe.json.error, 'string')
  assert.equal((await preq('DELETE', `/api/nodes/${impostorId}`)).status, 200)
})

// --- Remote server lifecycle ------------------------------------------------------

test('create rejects an unknown node id', async () => {
  const res = await preq('POST', '/api/servers', { name: 'Nope', blueprintId: 'demo-echo', nodeId: 'no-such-node' })
  assert.equal(res.status, 400)
})

test('create a demo-echo server ON the node (embedded blueprint)', async () => {
  const res = await preq('POST', '/api/servers', {
    name: 'Remote Echo',
    blueprintId: 'demo-echo',
    nodeId,
    variables: { SERVER_PORT: 27811 },
  })
  assert.equal(res.status, 201)
  const server = res.json.server as Record<string, unknown>
  remoteId = String(server.id)
  assert.equal(server.nodeId, nodeId)
  assert.equal(server.nodeName, 'test-node')
  assert.equal(server.nodeOnline, true)

  // The agent owns the record — verify directly with the token.
  const onAgent = await areq('GET', `/api/servers/${remoteId}`)
  assert.equal(onAgent.status, 200)
  assert.equal((onAgent.json.server as Record<string, unknown>).name, 'Remote Echo')
})

test('panel server list merges the mirrored remote server', async () => {
  const res = await preq('GET', '/api/servers')
  const entry = (res.json.servers as Record<string, unknown>[]).find((s) => s.id === remoteId)
  assert.ok(entry, 'remote server appears in the merged list')
  assert.equal(entry!.nodeId, nodeId)
  assert.equal(entry!.nodeName, 'test-node')
  assert.equal(entry!.nodeOnline, true)
})

test('remote install completes and the server starts', async () => {
  await waitFor(async () => (await remoteDetail(remoteId)).installed === true, 20_000, 'remote install')
  const power = await preq('POST', `/api/servers/${remoteId}/power`, { action: 'start' })
  assert.equal(power.status, 200)
  await waitFor(async () => (await remoteDetail(remoteId)).status === 'running', 20_000, 'remote server running')
})

test('command and console log proxy across the hop', async () => {
  const cmd = await preq('POST', `/api/servers/${remoteId}/command`, { command: 'say hello-from-panel' })
  assert.equal(cmd.status, 200)
  await waitFor(async () => {
    const res = await preq('GET', `/api/servers/${remoteId}/console?limit=200`)
    const lines = (res.json.lines as { line: string }[] | undefined) ?? []
    return lines.some((l) => l.line.includes('[Server] hello-from-panel'))
  }, 10_000, 'echoed console line via proxy')
})

test('resources/history endpoint proxies', async () => {
  const res = await preq('GET', `/api/servers/${remoteId}/resources`)
  assert.equal(res.status, 200)
  assert.ok(Array.isArray(res.json.history))
  assert.equal(res.json.status, 'running')
})

test('remote console streams through the panel websocket bridge', async () => {
  const ws = new WebSocket(`${panelBase.replace('http', 'ws')}/api/ws`, { headers: { cookie } })
  const consoleLines: string[] = []
  let subOk = false
  ws.on('message', (raw) => {
    const msg = JSON.parse(String(raw)) as { t?: string; channel?: string; line?: { line?: string } }
    if (msg.t === 'sub-ok' && msg.channel === `console:${remoteId}`) subOk = true
    if (msg.t === 'console') consoleLines.push(msg.line?.line ?? '')
  })
  await new Promise<void>((resolve, reject) => {
    ws.once('open', resolve)
    ws.once('error', reject)
  })
  ws.send(JSON.stringify({ op: 'sub', channel: `console:${remoteId}` }))
  await waitFor(async () => subOk, 5000, 'console channel subscription ack')

  // The bridge dials the node lazily — resend until a line makes it through.
  const start = Date.now()
  let attempt = 0
  while (Date.now() - start < 20_000 && !consoleLines.some((l) => l.includes('ws-bridge-test'))) {
    await preq('POST', `/api/servers/${remoteId}/command`, { command: `say ws-bridge-test ${attempt++}` })
    await sleep(500)
  }
  ws.close()
  assert.ok(
    consoleLines.some((l) => l.includes('[Server] ws-bridge-test')),
    `expected a bridged console line, got: ${JSON.stringify(consoleLines.slice(-5))}`,
  )
})

test('operations v1 does not support remotely are rejected clearly', async () => {
  const patch = await preq('PATCH', `/api/servers/${remoteId}`, { name: 'Renamed' })
  assert.equal(patch.status, 400)
  assert.match(String(patch.json.error), /remote nodes/)
  const clone = await preq('POST', `/api/servers/${remoteId}/clone`, { name: 'Copy' })
  assert.equal(clone.status, 400)
})

test('stop and delete the remote server', async () => {
  const stop = await preq('POST', `/api/servers/${remoteId}/power`, { action: 'stop' })
  assert.equal(stop.status, 200)
  await waitFor(async () => (await remoteDetail(remoteId)).status === 'offline', 25_000, 'remote server stopped')
  const del = await preq('DELETE', `/api/servers/${remoteId}`)
  assert.equal(del.status, 200)
  const list = await preq('GET', '/api/servers')
  assert.ok(!(list.json.servers as Record<string, unknown>[]).some((s) => s.id === remoteId))
  const onAgent = await areq('GET', '/api/servers')
  assert.ok(!(onAgent.json.servers as Record<string, unknown>[]).some((s) => s.id === remoteId))
})

// --- Node-offline degradation ------------------------------------------------------

test('node going down degrades mirrors instead of breaking the panel', async () => {
  const created = await preq('POST', '/api/servers', { name: 'Offline Probe', blueprintId: 'demo-echo', nodeId })
  assert.equal(created.status, 201)
  probeId = String((created.json.server as Record<string, unknown>).id)

  await agent.stop()

  await waitFor(async () => {
    const res = await preq('GET', '/api/nodes')
    const node = (res.json.nodes as Record<string, unknown>[]).find((n) => n.id === nodeId)
    return (node?.health as Record<string, unknown>)?.online === false
  }, 10_000, 'node health to go offline')

  const list = await preq('GET', '/api/servers')
  const entry = (list.json.servers as Record<string, unknown>[]).find((s) => s.id === probeId)
  assert.ok(entry, 'mirrored server still listed while its node is down')
  assert.equal(entry!.status, 'node-offline')
  assert.equal(entry!.nodeOnline, false)
  assert.equal(entry!.nodeName, 'test-node')

  // Detail degrades to the persisted mirror instead of 500ing.
  const detail = await preq('GET', `/api/servers/${probeId}`)
  assert.equal(detail.status, 200)
  assert.equal((detail.json.server as Record<string, unknown>).status, 'node-offline')

  // Operations fail with a clear 502, not a timeout or a crash.
  const power = await preq('POST', `/api/servers/${probeId}/power`, { action: 'start' })
  assert.equal(power.status, 502)
  assert.match(String(power.json.error), /unreachable/)
  const del = await preq('DELETE', `/api/servers/${probeId}`)
  assert.equal(del.status, 502)

  const probe = await preq('POST', `/api/nodes/${nodeId}/test`)
  assert.equal(probe.json.ok, false)
})

test('removing the node cleans up its mirrored servers', async () => {
  const res = await preq('DELETE', `/api/nodes/${nodeId}`)
  assert.equal(res.status, 200)
  const list = await preq('GET', '/api/servers')
  assert.ok(!(list.json.servers as Record<string, unknown>[]).some((s) => s.id === probeId))
  const nodes = await preq('GET', '/api/nodes')
  assert.deepEqual(nodes.json.nodes, [])
})
