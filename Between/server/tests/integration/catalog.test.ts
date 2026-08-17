/**
 * Game Library catalog integration test: boots the real app and walks the
 * catalog API — listing entries with installed-state, one-click add of a
 * builtin entry (no duplicate created), permission checks, and the SSRF
 * guard on the import-egg URL path. Deliberately network-free: egg-url adds
 * fetch from real community repos, so only their guard rails are asserted
 * here (the fetch+convert happy path is unit-tested in tests/unit/catalog).
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

interface ApiCatalogEntry {
  id: string
  name: string
  category: string
  description: string
  blueprintId: string
  source: { type: string; blueprintId?: string; url?: string }
}

before(async () => {
  dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'between-catalog-e2e-'))
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

// ---------------------------------------------------------------------------
// Listing
// ---------------------------------------------------------------------------
test('GET /api/catalog requires auth', async () => {
  const saved = cookie
  cookie = ''
  const res = await req('GET', '/api/catalog')
  assert.equal(res.status, 401)
  cookie = saved
})

test('GET /api/catalog returns entries with resolved blueprint ids and installed state', async () => {
  const res = await req('GET', '/api/catalog')
  assert.equal(res.status, 200, JSON.stringify(res.json))
  const entries = res.json.entries as ApiCatalogEntry[]
  const installed = res.json.installedBlueprintIds as string[]
  assert.ok(Array.isArray(entries) && entries.length >= 30, `expected a populated catalog, got ${entries.length}`)
  assert.ok(Array.isArray(installed))

  for (const entry of entries) {
    assert.ok(entry.id && entry.name && entry.category && entry.description, `entry ${entry.id} incomplete`)
    assert.ok(entry.source.type === 'builtin' || entry.source.type === 'egg-url', `entry ${entry.id} bad source`)
    assert.ok(typeof entry.blueprintId === 'string' && entry.blueprintId.length > 0)
  }

  // Builtin entries ship with the panel — they are installed out of the box.
  const builtins = entries.filter((e) => e.source.type === 'builtin')
  assert.ok(builtins.length > 0)
  for (const entry of builtins) assert.ok(installed.includes(entry.blueprintId), `builtin ${entry.id} should be installed`)

  // Egg-url entries are not installed on a fresh panel.
  const eggUrls = entries.filter((e) => e.source.type === 'egg-url')
  assert.ok(eggUrls.length > 0)
  for (const entry of eggUrls) assert.ok(!installed.includes(entry.blueprintId), `egg-url ${entry.id} should not be installed yet`)
})

// ---------------------------------------------------------------------------
// Adding
// ---------------------------------------------------------------------------
test('POST /api/catalog/:id/add for a builtin entry returns it without creating a duplicate', async () => {
  const catalog = await req('GET', '/api/catalog')
  const entry = (catalog.json.entries as ApiCatalogEntry[]).find((e) => e.source.type === 'builtin')
  assert.ok(entry, 'catalog has no builtin entries')

  const countBefore = ((await req('GET', '/api/blueprints')).json.blueprints as unknown[]).length
  const res = await req('POST', `/api/catalog/${entry!.id}/add`)
  assert.equal(res.status, 200, JSON.stringify(res.json))
  const blueprint = res.json.blueprint as { id: string; custom?: boolean }
  assert.equal(blueprint.id, entry!.blueprintId)
  assert.ok(!blueprint.custom, 'builtin blueprint must not be duplicated as a custom one')
  assert.deepEqual(res.json.warnings, [])

  const countAfter = ((await req('GET', '/api/blueprints')).json.blueprints as unknown[]).length
  assert.equal(countAfter, countBefore, 'adding a builtin entry must not create a new blueprint')
})

test('POST /api/catalog/:id/add rejects unknown entries and non-admins', async () => {
  const unknown = await req('POST', '/api/catalog/definitely-not-a-game/add')
  assert.equal(unknown.status, 404)

  await req('POST', '/api/users', { username: 'player', password: 'player-pass-1', role: 'user' })
  const adminCookie = cookie
  cookie = ''
  await req('POST', '/api/auth/login', { username: 'player', password: 'player-pass-1' })

  // Browsing is for everyone, adding is admin-only.
  const browse = await req('GET', '/api/catalog')
  assert.equal(browse.status, 200)
  const catalog = browse.json.entries as ApiCatalogEntry[]
  const entry = catalog.find((e) => e.source.type === 'egg-url')
  assert.ok(entry)
  const add = await req('POST', `/api/catalog/${entry!.id}/add`)
  assert.equal(add.status, 403)

  cookie = adminCookie
})

// ---------------------------------------------------------------------------
// import-egg from URL: SSRF guard (no real network fetches in tests — public
// URLs like raw.githubusercontent.com work in production, loopback must not)
// ---------------------------------------------------------------------------
test('POST /api/blueprints/import-egg rejects non-http(s) and private URLs with 400', async () => {
  const fileUrl = await req('POST', '/api/blueprints/import-egg', { url: 'file:///etc/passwd' })
  assert.equal(fileUrl.status, 400)
  assert.match(String(fileUrl.json.error), /only http/)

  const loopback = await req('POST', '/api/blueprints/import-egg', { url: 'http://127.0.0.1/x' })
  assert.equal(loopback.status, 400)
  assert.match(String(loopback.json.error), /private or loopback/)

  const localhost = await req('POST', '/api/blueprints/import-egg', { url: 'http://localhost/x' })
  assert.equal(localhost.status, 400)
  assert.match(String(localhost.json.error), /local hostname/)

  const metadata = await req('POST', '/api/blueprints/import-egg', { url: 'http://169.254.169.254/latest/meta-data' })
  assert.equal(metadata.status, 400)
  assert.match(String(metadata.json.error), /private or loopback/)

  const weirdPort = await req('POST', '/api/blueprints/import-egg', { url: 'https://example.com:6379/x' })
  assert.equal(weirdPort.status, 400)
  assert.match(String(weirdPort.json.error), /non-standard port/)

  const notAString = await req('POST', '/api/blueprints/import-egg', { url: 123 })
  assert.equal(notAString.status, 400)
  assert.match(String(notAString.json.error), /non-empty string/)
})

test('import-egg object and string paths still work alongside the url path', async () => {
  const egg = {
    meta: { version: 'PTDL_v2' },
    name: 'Catalog Suite Egg',
    startup: './run --port {{SERVER_PORT}}',
    config: { files: '{}', startup: '{"done": "ready"}', logs: '{}', stop: 'stop' },
    scripts: { installation: { script: '', container: '', entrypoint: '' } },
    variables: [],
  }
  const asObject = await req('POST', '/api/blueprints/import-egg', { egg })
  assert.equal(asObject.status, 200, JSON.stringify(asObject.json))
  const asString = await req('POST', '/api/blueprints/import-egg', { egg: JSON.stringify(egg) })
  assert.equal(asString.status, 200)
})
