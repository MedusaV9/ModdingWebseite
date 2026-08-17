/**
 * File-template (generic instance template) integration test: boots the real
 * app with a data dir whose templates/ folder contains YAML + JSON drop-ins,
 * then walks the whole path — boot-time loading, parity with the builtin the
 * YAML was exported from, creating and starting a REAL server from a file
 * template (demo-echo based, no network), the rescan endpoint, per-file error
 * isolation, id-collision rejection and the read-only API guarantees.
 */
import { test, before, after } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { createApp, type BetweenApp } from '../../src/app.ts'
import { BlueprintRegistry } from '../../src/blueprints/registry.ts'
import { stringifyYamlDoc } from '../../src/lib/yamldoc.ts'
import type { Blueprint, InstallStep } from '../../src/types.ts'

const here = path.dirname(fileURLToPath(import.meta.url))
const shippedTemplatesDir = path.join(here, '..', '..', '..', 'templates')

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

/** Build a self-contained demo-echo template (assets inlined) with a new id. */
function demoTemplate(newId: string): Blueprint {
  const registry = new BlueprintRegistry()
  const bp = JSON.parse(JSON.stringify(registry.get('demo-echo'))) as Blueprint
  bp.id = newId
  bp.name = 'Demo From Template'
  delete bp.custom
  for (const step of bp.install as InstallStep[]) {
    if (step.type === 'writeFile' && step.content.startsWith('@asset:'))
      step.content = registry.resolveAsset(step.content.slice('@asset:'.length))
  }
  return bp
}

before(async () => {
  dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'between-templates-e2e-'))
  const tplDir = path.join(dataDir, 'templates')
  fs.mkdirSync(tplDir, { recursive: true })

  // 1. A shipped example (YAML export of the valheim builtin).
  fs.copyFileSync(path.join(shippedTemplatesDir, 'valheim.yaml'), path.join(tplDir, 'valheim.yaml'))
  // 2. A startable no-network template, as YAML.
  fs.writeFileSync(path.join(tplDir, 'demo.yaml'), stringifyYamlDoc(demoTemplate('tpl-demo')))
  // 3. The same format as JSON.
  fs.writeFileSync(path.join(tplDir, 'demo-json.json'), JSON.stringify(demoTemplate('tpl-demo-json'), null, 2))
  // 4. A broken file — must not affect the others.
  fs.writeFileSync(path.join(tplDir, 'broken.yaml'), 'id: [unterminated\n')
  // 5. An id collision with a builtin — must be rejected with a per-file error.
  fs.writeFileSync(path.join(tplDir, 'collide.json'), JSON.stringify({ ...demoTemplate('tpl-x'), id: 'demo-echo' }))

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

test('every shipped example template in Between/templates parses and validates', async () => {
  const { parseYamlDoc } = await import('../../src/lib/yamldoc.ts')
  const { validateBlueprint } = await import('../../src/blueprints/schema.ts')
  const registry = new BlueprintRegistry()
  const files = fs.readdirSync(shippedTemplatesDir).filter((f) => /\.(json|ya?ml)$/i.test(f)).sort()
  assert.ok(files.length >= 10, `expected at least 10 shipped templates, found ${files.length}`)
  for (const file of files) {
    const text = fs.readFileSync(path.join(shippedTemplatesDir, file), 'utf8')
    const doc = /\.json$/i.test(file) ? JSON.parse(text) : parseYamlDoc(text)
    const problems = validateBlueprint(doc)
    assert.deepEqual(problems, [], `${file}: ${problems.join('; ')}`)
    const id = (doc as { id: string }).id
    assert.equal(registry.isBuiltin(id), false, `${file}: id ${id} collides with a builtin`)
  }
})

test('boot loads valid template files and isolates broken/colliding ones', async () => {
  const res = await req('GET', '/api/templates')
  assert.equal(res.status, 200, JSON.stringify(res.json))
  const scan = res.json.scan as { loaded: { id: string; file: string }[]; errors: { file: string; problems: string[] }[]; dir: string }
  assert.deepEqual(scan.loaded.map((t) => t.id).sort(), ['tpl-demo', 'tpl-demo-json', 'tpl-valheim'])
  const errorFiles = scan.errors.map((e) => e.file).sort()
  assert.deepEqual(errorFiles, ['broken.yaml', 'collide.json'])
  const collision = scan.errors.find((e) => e.file === 'collide.json')!
  assert.match(collision.problems.join(' '), /collides with a builtin/)
})

test('YAML template round-trips the builtin it was exported from', async () => {
  const registry = new BlueprintRegistry()
  const builtin = JSON.parse(JSON.stringify(registry.get('valheim'))) as Record<string, unknown>
  const res = await req('GET', '/api/blueprints/tpl-valheim')
  assert.equal(res.status, 200)
  const tpl = res.json.blueprint as Record<string, unknown>
  // Loader metadata + intentional differences aside, content must be identical.
  const strip = (bp: Record<string, unknown>) => {
    const { id: _i, custom: _c, templateFile: _t, ...rest } = bp
    return rest
  }
  builtin.custom = false
  assert.deepEqual(strip(tpl), strip(builtin))
  assert.equal(tpl.templateFile, 'valheim.yaml')
})

test('template blueprints appear in the blueprint listing alongside builtins', async () => {
  const res = await req('GET', '/api/blueprints')
  const all = res.json.blueprints as { id: string; templateFile?: string; custom?: boolean }[]
  const tpl = all.find((b) => b.id === 'tpl-demo')
  assert.ok(tpl, 'tpl-demo missing from listing')
  assert.equal(tpl!.templateFile, 'demo.yaml')
  assert.equal(tpl!.custom, false)
})

test('a server can be created, installed and started from a file template', async () => {
  const create = await req('POST', '/api/servers', {
    name: 'Template Smoke',
    blueprintId: 'tpl-demo',
    variables: { SERVER_PORT: 27891 },
  })
  assert.equal(create.status, 201, JSON.stringify(create.json))
  const id = (create.json.server as { id: string }).id

  // Install is synchronous-ish for writeFile steps; poll briefly.
  for (let i = 0; i < 50; i++) {
    const detail = await req('GET', `/api/servers/${id}`)
    if ((detail.json.server as { installed: boolean }).installed) break
    await new Promise((r) => setTimeout(r, 100))
  }
  const start = await req('POST', `/api/servers/${id}/power`, { action: 'start' })
  assert.equal(start.status, 200, JSON.stringify(start.json))
  let running = false
  for (let i = 0; i < 100; i++) {
    const detail = await req('GET', `/api/servers/${id}`)
    const status = (detail.json.server as { status: string }).status
    if (status === 'running') {
      running = true
      break
    }
    assert.notEqual(status, 'crashed', 'template server crashed during startup')
    await new Promise((r) => setTimeout(r, 100))
  }
  assert.ok(running, 'server from file template did not reach running')
  const stop = await req('POST', `/api/servers/${id}/power`, { action: 'stop' })
  assert.equal(stop.status, 200)
  for (let i = 0; i < 100; i++) {
    const detail = await req('GET', `/api/servers/${id}`)
    if ((detail.json.server as { status: string }).status === 'offline') break
    await new Promise((r) => setTimeout(r, 100))
  }
  await req('DELETE', `/api/servers/${id}`)
})

test('file templates are read-only via the blueprint API', async () => {
  const put = await req('PUT', '/api/blueprints/tpl-demo', { blueprint: demoTemplate('tpl-demo') })
  assert.equal(put.status, 400)
  assert.match(String(put.json.error), /read-only/)
  const del = await req('DELETE', '/api/blueprints/tpl-demo')
  assert.equal(del.status, 400)
  assert.match(String(del.json.error), /deleting the file/)
  // And custom blueprints cannot shadow a template id.
  const post = await req('POST', '/api/blueprints', { blueprint: demoTemplate('tpl-demo') })
  assert.equal(post.status, 400)
  assert.match(String(post.json.error), /collides with a template file/)
})

test('rescan picks up new files and drops deleted ones without a restart', async () => {
  const tplDir = path.join(dataDir, 'templates')
  fs.writeFileSync(path.join(tplDir, 'late.yaml'), stringifyYamlDoc(demoTemplate('tpl-late')))
  fs.rmSync(path.join(tplDir, 'demo-json.json'))
  const res = await req('POST', '/api/templates/rescan')
  assert.equal(res.status, 200)
  const scan = res.json.scan as { loaded: { id: string }[] }
  const ids = scan.loaded.map((t) => t.id).sort()
  assert.deepEqual(ids, ['tpl-demo', 'tpl-late', 'tpl-valheim'])
  const gone = await req('GET', '/api/blueprints/tpl-demo-json')
  assert.equal(gone.status, 404)
  const there = await req('GET', '/api/blueprints/tpl-late')
  assert.equal(there.status, 200)
})

test('template endpoints are admin-only', async () => {
  await req('POST', '/api/users', { username: 'pleb', password: 'hunter2hunter2', role: 'user' })
  const adminCookie = cookie
  cookie = ''
  await req('POST', '/api/auth/login', { username: 'pleb', password: 'hunter2hunter2' })
  const list = await req('GET', '/api/templates')
  assert.equal(list.status, 403)
  const rescan = await req('POST', '/api/templates/rescan')
  assert.equal(rescan.status, 403)
  cookie = adminCookie
})
