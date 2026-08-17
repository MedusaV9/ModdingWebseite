/**
 * Generic webhook notifier — full-stack integration: boots the real app plus
 * a tiny local HTTP receiver, then covers settings validation (including the
 * deliberate private/LAN allowance), the admin test endpoint, and real
 * power/crash/backup events end to end with the demo blueprint.
 */
import { test, before, after } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import http from 'node:http'
import os from 'node:os'
import path from 'node:path'
import { createApp, type BetweenApp } from '../../src/app.ts'
import { sleep } from '../../src/lib/util.ts'

let app: BetweenApp
let base = ''
let cookie = ''
let dataDir = ''
let serverId = ''

interface ReceivedHook {
  method: string
  headers: http.IncomingHttpHeaders
  body: {
    event: string
    timestamp: string
    panel: string
    server: { id: string; name: string; blueprintId: string } | null
    data: Record<string, unknown>
  }
}
let receiver: http.Server
let receiverUrl = ''
const received: ReceivedHook[] = []

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

async function waitForEvent(event: string, timeoutMs = 10_000): Promise<ReceivedHook> {
  const start = Date.now()
  for (;;) {
    const hit = received.find((r) => r.body.event === event)
    if (hit) return hit
    if (Date.now() - start >= timeoutMs) throw new Error(`timeout waiting for webhook event: ${event}`)
    await sleep(100)
  }
}

before(async () => {
  dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'between-webhook-'))
  app = createApp({ port: 0, host: '127.0.0.1', dataDir, webDistDir: path.join(dataDir, 'no-web') })
  const { port } = await app.start()
  base = `http://127.0.0.1:${port}`

  receiver = http.createServer((httpReq, httpRes) => {
    const chunks: Buffer[] = []
    httpReq.on('data', (c: Buffer) => chunks.push(c))
    httpReq.on('end', () => {
      const text = Buffer.concat(chunks).toString('utf8')
      received.push({
        method: httpReq.method ?? '',
        headers: httpReq.headers,
        body: JSON.parse(text) as ReceivedHook['body'],
      })
      httpRes.writeHead(200, { 'content-type': 'application/json' })
      httpRes.end('{"ok":true}')
    })
  })
  await new Promise<void>((resolve) => receiver.listen(0, '127.0.0.1', resolve))
  receiverUrl = `http://127.0.0.1:${(receiver.address() as { port: number }).port}/between-hook`
})

after(async () => {
  await app.stop()
  receiver.closeAllConnections()
  receiver.close()
  fs.rmSync(dataDir, { recursive: true, force: true })
})

test('setup creates the first admin', async () => {
  const res = await req('POST', '/api/auth/setup', { username: 'admin', password: 'super-secret-1', panelName: 'Webhook Panel' })
  assert.equal(res.status, 200)
})

test('webhook-test without a configured URL is rejected', async () => {
  const res = await req('POST', '/api/settings/webhook-test')
  assert.equal(res.status, 400)
  assert.match(String(res.json.error), /no webhook URL/)
})

test('webhook URL validation rejects malformed URLs', async () => {
  for (const bad of ['ftp://example.com/hook', 'not a url', 'javascript:alert(1)', `https://example.com/${'a'.repeat(500)}`]) {
    const res = await req('PATCH', '/api/settings', { webhookUrl: bad })
    assert.equal(res.status, 400, `expected 400 for ${bad.slice(0, 40)}`)
  }
  const settings = await req('GET', '/api/settings')
  assert.equal((settings.json.settings as { webhookUrl?: string | null }).webhookUrl ?? null, null)
})

test('private/LAN webhook URLs are accepted by design', async () => {
  // The receiver runs on 127.0.0.1 with a random high port — exactly the kind
  // of private endpoint a self-hosted panel must be able to notify.
  const res = await req('PATCH', '/api/settings', {
    webhookUrl: receiverUrl,
    webhookEvents: { crash: true, power: true, backup: true },
  })
  assert.equal(res.status, 200)
  const saved = res.json.settings as { webhookUrl: string; webhookEvents: Record<string, boolean> }
  assert.equal(saved.webhookUrl, receiverUrl)
  assert.deepEqual(saved.webhookEvents, { crash: true, power: true, backup: true })
})

test('webhook-test delivers the stable JSON payload with the right headers', async () => {
  const res = await req('POST', '/api/settings/webhook-test')
  assert.equal(res.status, 200)
  assert.equal(res.json.ok, true)
  assert.equal(res.json.status, 200)

  const hook = await waitForEvent('test')
  assert.equal(hook.method, 'POST')
  assert.match(String(hook.headers['content-type']), /application\/json/)
  assert.match(String(hook.headers['user-agent']), /^Between-Panel\//)
  assert.ok(Number.isFinite(Date.parse(hook.body.timestamp)), 'timestamp is ISO 8601')
  assert.equal(hook.body.panel, 'Webhook Panel')
  assert.equal(hook.body.server, null)
  assert.equal(typeof hook.body.data.title, 'string')
  assert.equal(typeof hook.body.data.message, 'string')
})

test('a real power event reaches the webhook with server context', async () => {
  const create = await req('POST', '/api/servers', {
    name: 'Webhook Demo',
    blueprintId: 'demo-echo',
    variables: { SERVER_PORT: 28755 },
    autoStart: false,
    startAfterInstall: false,
  })
  assert.equal(create.status, 201)
  serverId = (create.json.server as { id: string }).id
  await waitFor(async () => (await serverStatus()) === 'offline', 15_000, 'install to finish')

  const power = await req('POST', `/api/servers/${serverId}/power`, { action: 'start' })
  assert.equal(power.status, 200)
  const hook = await waitForEvent('power')
  assert.equal(hook.body.panel, 'Webhook Panel')
  assert.deepEqual(hook.body.server, { id: serverId, name: 'Webhook Demo', blueprintId: 'demo-echo' })
  assert.equal(hook.body.data.action, 'start')
  assert.equal(hook.body.data.by, 'admin')
  await waitFor(async () => (await serverStatus()) === 'running', 20_000, 'server running')
})

test('a real crash event reaches the webhook', async () => {
  const patched = await req('PATCH', `/api/servers/${serverId}`, { restartPolicy: { enabled: false, maxRetries: 3, backoffS: 5 } })
  assert.equal(patched.status, 200)
  await req('POST', `/api/servers/${serverId}/command`, { command: 'crash' })
  await waitFor(async () => (await serverStatus()) === 'crashed', 15_000, 'crash detected')

  const hook = await waitForEvent('crash')
  assert.equal(hook.body.server?.id, serverId)
  assert.match(String(hook.body.data.message), /Webhook Demo/)
  // Discord markdown is stripped from the generic payload.
  assert.ok(!String(hook.body.data.message).includes('**'))
})

test('disabled event kinds are filtered out', async () => {
  const res = await req('PATCH', '/api/settings', { webhookEvents: { crash: true, power: false, backup: true } })
  assert.equal(res.status, 200)
  received.length = 0

  // Power is now off — starting must not enqueue anything. The backup that
  // follows acts as the positive control: delivery still works, and since the
  // queue is FIFO a suppressed power event could not sneak in behind it.
  await req('POST', `/api/servers/${serverId}/power`, { action: 'start' })
  await waitFor(async () => (await serverStatus()) === 'running', 20_000, 'server running again')
  const backup = await req('POST', `/api/servers/${serverId}/backups`, { note: 'webhook e2e' })
  assert.equal(backup.status, 201)

  const hook = await waitForEvent('backup')
  assert.equal(hook.body.server?.id, serverId)
  assert.equal(typeof hook.body.data.fileName, 'string')
  assert.ok(!received.some((r) => r.body.event === 'power'), 'suppressed power event must not be delivered')
})

test('a schedule-triggered backup notifies the webhook with schedule context', async () => {
  const created = await req('POST', `/api/servers/${serverId}/schedules`, {
    name: 'nightly backup',
    cron: '0 3 * * *',
    tasks: [{ type: 'backup', note: 'from schedule' }],
    enabled: true,
    onlyIfRunning: false,
  })
  assert.equal(created.status, 201)
  const scheduleId = (created.json.schedule as { id: string }).id

  received.length = 0
  const run = await req('POST', `/api/servers/${serverId}/schedules/${scheduleId}/run`)
  assert.equal(run.status, 200)

  // Same payload shape as a manual backup, plus the additive schedule field
  // (no user acted, so the schedule name carries the "who").
  const hook = await waitForEvent('backup')
  assert.deepEqual(hook.body.server, { id: serverId, name: 'Webhook Demo', blueprintId: 'demo-echo' })
  assert.equal(typeof hook.body.data.fileName, 'string')
  assert.equal(hook.body.data.schedule, 'nightly backup')
  assert.match(String(hook.body.data.message), /schedule "nightly backup"/)
  assert.ok(!String(hook.body.data.message).includes('**'), 'markdown stripped for the generic payload')
})
