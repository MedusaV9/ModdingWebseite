/**
 * Egg importer integration test: boots the real app, converts a Pterodactyl
 * egg via POST /api/blueprints/import-egg, saves the result as a custom
 * blueprint and reads it back. When a Docker daemon is reachable the test
 * goes all the way: it creates a server from an egg-imported blueprint whose
 * install script runs in a container (docker-script step) and verifies the
 * script's output landed in the server directory — then starts the server in
 * a container as a bonus round-trip.
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

let app: BetweenApp
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

before(async () => {
  dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'between-eggs-e2e-'))
  app = createApp({ port: 0, host: '127.0.0.1', dataDir, webDistDir: path.join(dataDir, 'no-web') })
  const { port } = await app.start()
  base = `http://127.0.0.1:${port}`
  await req('POST', '/api/auth/setup', { username: 'admin', password: 'hunter2hunter2' })
  await req('POST', '/api/auth/login', { username: 'admin', password: 'hunter2hunter2' })
})

after(async () => {
  if (serverId && !skip) {
    const entries = await docker.client.listByLabel(LABEL_SERVER_ID, serverId).catch(() => [])
    await Promise.allSettled(entries.map((e) => docker.client.removeContainer(e.Id, true)))
  }
  await app.stop()
  if (dataDir) fs.rmSync(dataDir, { recursive: true, force: true })
})

// ---------------------------------------------------------------------------
// Import + save flow (no Docker required)
// ---------------------------------------------------------------------------
const SMALL_EGG = {
  meta: { version: 'PTDL_v2' },
  name: 'Import Flow Egg',
  author: 'tests@example.com',
  description: 'Small egg used to exercise the import API.',
  docker_images: { 'Alpine 3': 'alpine:3' },
  startup: './run --port {{SERVER_PORT}} --key {{weird-key}}',
  config: { files: '{}', startup: '{"done": "up and running"}', logs: '{}', stop: 'quit' },
  scripts: { installation: { script: '', container: '', entrypoint: '' } },
  variables: [
    { name: 'Weird Key', env_variable: 'weird-key', default_value: 'abc', rules: 'required|string' },
  ],
}

let importedId = ''

test('POST /api/blueprints/import-egg converts and returns warnings without saving', async () => {
  const res = await req('POST', '/api/blueprints/import-egg', { egg: SMALL_EGG })
  assert.equal(res.status, 200, JSON.stringify(res.json))
  const blueprint = res.json.blueprint as {
    id: string
    name: string
    startCommand: string
    docker: { image: string }
    variables: { key: string }[]
  }
  const warnings = res.json.warnings as string[]
  importedId = blueprint.id
  assert.equal(blueprint.name, 'Import Flow Egg')
  assert.equal(blueprint.docker.image, 'alpine:3')
  assert.ok(blueprint.startCommand.includes('{{WEIRD_KEY}}'), 'sanitized key rewritten in startup')
  assert.ok(blueprint.variables.some((v) => v.key === 'WEIRD_KEY'))
  assert.ok(blueprint.variables.some((v) => v.key === 'SERVER_PORT'))
  assert.ok(warnings.some((w) => w.includes('weird-key')))

  // Nothing was saved: the id is not in the registry yet.
  const missing = await req('GET', `/api/blueprints/${blueprint.id}`)
  assert.equal(missing.status, 404)
})

test('import accepts a raw JSON string body and rejects junk with 400', async () => {
  const asString = await req('POST', '/api/blueprints/import-egg', { egg: JSON.stringify(SMALL_EGG) })
  assert.equal(asString.status, 200)

  const notJson = await req('POST', '/api/blueprints/import-egg', { egg: '{broken' })
  assert.equal(notJson.status, 400)
  assert.match(String(notJson.json.error), /not valid JSON/)

  const notEgg = await req('POST', '/api/blueprints/import-egg', { egg: { hello: 'world' } })
  assert.equal(notEgg.status, 400)
  assert.match(String(notEgg.json.error), /not a Pterodactyl egg/)
})

test('the converted blueprint saves via POST /api/blueprints and reads back', async () => {
  const converted = await req('POST', '/api/blueprints/import-egg', { egg: SMALL_EGG })
  const blueprint = converted.json.blueprint as { id: string }
  importedId = blueprint.id

  const saved = await req('POST', '/api/blueprints', { blueprint })
  assert.equal(saved.status, 201, JSON.stringify(saved.json))

  const fetched = await req('GET', `/api/blueprints/${importedId}`)
  assert.equal(fetched.status, 200)
  const bp = fetched.json.blueprint as { id: string; custom: boolean; readyRegex: string }
  assert.equal(bp.id, importedId)
  assert.equal(bp.custom, true)
  assert.equal(bp.readyRegex, 'up and running')
})

// ---------------------------------------------------------------------------
// Live Docker: egg install script runs in a container, then the server runs
// in a container too (both from the same imported egg)
// ---------------------------------------------------------------------------
const E2E_EGG = {
  meta: { version: 'PTDL_v2' },
  name: 'Egg Docker E2E',
  author: 'tests@example.com',
  description: 'Egg whose install script writes the run script consumed by startCommand.',
  docker_images: { 'Alpine 3': 'alpine:3' },
  startup: 'sh .between-egg-run.sh',
  config: { files: '{}', startup: '{"done": "egg server ready"}', logs: '{}', stop: '^C' },
  scripts: {
    installation: {
      script: [
        '#!/bin/ash',
        'cd /mnt/server',
        'echo "egg install says hello"',
        "cat > .between-egg-run.sh <<'EOF'",
        '#!/bin/sh',
        'echo "egg server ready"',
        'while :; do read line && echo "got: $line" || sleep 1; done',
        'EOF',
        'echo done > .egg-install-done',
      ].join('\n'),
      container: 'alpine:3',
      entrypoint: 'ash',
    },
  },
  variables: [],
}

test('egg install script runs in a container and writes into the server dir', { skip }, async () => {
  const converted = await req('POST', '/api/blueprints/import-egg', { egg: E2E_EGG })
  assert.equal(converted.status, 200, JSON.stringify(converted.json))
  const blueprint = converted.json.blueprint as { id: string; install: { type: string }[] }
  assert.equal(blueprint.install[0]?.type, 'docker-script')
  const saved = await req('POST', '/api/blueprints', { blueprint })
  assert.equal(saved.status, 201, JSON.stringify(saved.json))

  const created = await req('POST', '/api/servers', {
    name: 'Egg E2E',
    blueprintId: blueprint.id,
    runtime: 'docker',
    variables: {},
  })
  assert.equal(created.status, 201, JSON.stringify(created.json))
  serverId = (created.json.server as { id: string }).id

  // First run may pull alpine:3 — allow time for that.
  await waitFor(async () => (await serverStatus()) === 'offline', 120_000, 'egg install to finish')

  // The script's stdout streamed into the install console...
  const consoleRes = await req('GET', `/api/servers/${serverId}/console?limit=500`)
  const lines = (consoleRes.json.lines as { line: string }[]).map((l) => l.line)
  assert.ok(lines.some((l) => l.includes('egg install says hello')), `install echo missing in: ${lines.join(' | ')}`)

  // ...its artifacts landed in the server dir via the /mnt/server bind mount...
  const marker = await req('GET', `/api/servers/${serverId}/files/content?path=.egg-install-done`)
  assert.equal(marker.status, 200)
  assert.equal(String(marker.json.content).trim(), 'done')
  const runScript = await req('GET', `/api/servers/${serverId}/files/content?path=.between-egg-run.sh`)
  assert.equal(runScript.status, 200)

  // ...and the temporary install script was cleaned up afterwards.
  const leftover = await req('GET', `/api/servers/${serverId}/files/content?path=.between-install.sh`)
  assert.ok(leftover.status >= 400, 'install script must be removed after the install')

  // No install containers left behind.
  const husks = await docker.client.listByLabel('between.install', '1')
  assert.equal(husks.length, 0, 'install containers must be removed')
})

test('the imported egg server starts in docker and reaches ready via the done marker', { skip }, async () => {
  const start = await req('POST', `/api/servers/${serverId}/power`, { action: 'start' })
  assert.equal(start.status, 200, JSON.stringify(start.json))
  // Generous: a real image pull + install-script container + server start can
  // be slow when the shared daemon is under load from other suites.
  await waitFor(async () => (await serverStatus()) === 'running', 150_000, 'egg server to reach running (readyRegex)')

  const consoleRes = await req('GET', `/api/servers/${serverId}/console?limit=500`)
  const lines = (consoleRes.json.lines as { line: string }[]).map((l) => l.line)
  assert.ok(lines.some((l) => l.includes('egg server ready')))

  await req('POST', `/api/servers/${serverId}/power`, { action: 'kill' })
  await waitFor(async () => (await serverStatus()) === 'offline', 30_000, 'egg server to stop')
})
