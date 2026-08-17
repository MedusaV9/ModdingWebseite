/**
 * Full-stack API integration test: boots the real app (random port, temp data
 * dir), then walks the primary user journey end to end with the built-in demo
 * blueprint — setup, auth, server create + install, power, console, files,
 * backups, schedules, users, api keys, audit — and shuts down cleanly.
 */
import { test, before, after } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { WebSocket } from 'ws'
import { createApp, type BetweenApp } from '../../src/app.ts'
import { sleep } from '../../src/lib/util.ts'
import { totpCode } from '../../src/lib/totp.ts'

let app: BetweenApp
let base = ''
let cookie = ''
let dataDir = ''
let serverId = ''
let backupId = ''

async function req(
  method: string,
  urlPath: string,
  body?: unknown,
  opts: { raw?: boolean } = {},
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
  if (opts.raw) return { status: res.status, json: {} }
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

before(async () => {
  dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'between-e2e-'))
  app = createApp({ port: 0, host: '127.0.0.1', dataDir, webDistDir: path.join(dataDir, 'no-web') })
  const { port } = await app.start()
  base = `http://127.0.0.1:${port}`
})

after(async () => {
  await app.stop()
  fs.rmSync(dataDir, { recursive: true, force: true })
})

test('meta reports setup required on fresh install', async () => {
  const res = await req('GET', '/api/meta')
  assert.equal(res.status, 200)
  assert.equal(res.json.setupRequired, true)
})

test('unauthenticated API access is denied', async () => {
  const res = await req('GET', '/api/servers')
  assert.equal(res.status, 401)
})

test('setup creates the first admin and signs in', async () => {
  const res = await req('POST', '/api/auth/setup', { username: 'admin', password: 'super-secret-1', panelName: 'E2E Panel' })
  assert.equal(res.status, 200)
  assert.equal((res.json.user as { role: string }).role, 'admin')
  assert.ok(cookie.includes('between_session='))
})

test('second setup attempt is rejected', async () => {
  const saved = cookie
  cookie = ''
  const res = await req('POST', '/api/auth/setup', { username: 'evil', password: 'super-secret-2' })
  assert.equal(res.status, 403)
  cookie = saved
})

test('me returns the session user, meta shows panel name', async () => {
  const me = await req('GET', '/api/auth/me')
  assert.equal((me.json.user as { username: string }).username, 'admin')
  const meta = await req('GET', '/api/meta')
  assert.equal(meta.json.panelName, 'E2E Panel')
  assert.equal(meta.json.setupRequired, false)
})

test('login rejects bad credentials', async () => {
  const saved = cookie
  cookie = ''
  const res = await req('POST', '/api/auth/login', { username: 'admin', password: 'wrong-password' })
  assert.equal(res.status, 401)
  cookie = saved
})

test('websocket rejects oversized frames without taking down the panel', async () => {
  const ws = new WebSocket(`${base.replace('http', 'ws')}/api/ws`, { headers: { cookie } })
  await new Promise<void>((resolve, reject) => {
    ws.once('open', resolve)
    ws.once('error', reject)
  })
  const closed = new Promise<void>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('oversized websocket stayed open')), 5000)
    ws.once('close', () => {
      clearTimeout(timer)
      resolve()
    })
  })
  ws.send(Buffer.alloc(64 * 1024 + 1))
  await closed
  assert.equal((await req('GET', '/api/meta')).status, 200, 'panel remains responsive')
})

test('logout revokes an already-open websocket', async () => {
  const ws = new WebSocket(`${base.replace('http', 'ws')}/api/ws`, { headers: { cookie } })
  await new Promise<void>((resolve, reject) => {
    ws.once('open', resolve)
    ws.once('error', reject)
  })
  const closed = new Promise<void>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('revoked websocket stayed open')), 5000)
    ws.once('close', () => {
      clearTimeout(timer)
      resolve()
    })
  })
  const logout = await req('POST', '/api/auth/logout')
  assert.equal(logout.status, 200)
  ws.send(JSON.stringify({ op: 'sub', channel: 'system' }))
  await closed

  const login = await req('POST', '/api/auth/login', { username: 'admin', password: 'super-secret-1' })
  assert.equal(login.status, 200)
})

test('2FA recovery code flow: enable, login, regenerate, disable', async () => {
  const created = await req('POST', '/api/users', { username: 'recovery', password: 'recovery-pass-1', role: 'user' })
  assert.equal(created.status, 201)

  const adminCookie = cookie
  cookie = ''
  const login = await req('POST', '/api/auth/login', { username: 'recovery', password: 'recovery-pass-1' })
  assert.equal(login.status, 200)

  // Regenerating recovery codes requires 2FA to be enabled
  const early = await req('POST', '/api/auth/totp/recovery-codes', { code: '0000000' })
  assert.equal(early.status, 403)

  const start = await req('POST', '/api/auth/totp/start')
  const secret = start.json.secret as string
  const enable = await req('POST', '/api/auth/totp/enable', { code: totpCode(secret) })
  assert.equal(enable.status, 200)
  const codes = enable.json.recoveryCodes as string[]
  assert.equal(codes.length, 10)

  const me = await req('GET', '/api/auth/me')
  assert.equal(me.json.recoveryCodesRemaining, 10)
  assert.equal((me.json.user as Record<string, unknown>).recoveryCodes, undefined, 'hashes never leave the server')

  // A recovery code replaces the TOTP code at login and is single-use
  cookie = ''
  const viaRecovery = await req('POST', '/api/auth/login', { username: 'recovery', password: 'recovery-pass-1', totp: codes[0] })
  assert.equal(viaRecovery.status, 200)
  const meAfter = await req('GET', '/api/auth/me')
  assert.equal(meAfter.json.recoveryCodesRemaining, 9)

  // Regeneration needs a valid current TOTP code and replaces the set
  const badRegen = await req('POST', '/api/auth/totp/recovery-codes', { code: '0000000' })
  assert.equal(badRegen.status, 400)
  const regen = await req('POST', '/api/auth/totp/recovery-codes', { code: totpCode(secret) })
  assert.equal(regen.status, 200)
  assert.equal((regen.json.recoveryCodes as string[]).length, 10)

  // Disabling 2FA clears recovery codes; me no longer reports a count
  const disable = await req('POST', '/api/auth/totp/disable', { code: totpCode(secret) })
  assert.equal(disable.status, 200)
  const meFinal = await req('GET', '/api/auth/me')
  assert.equal(meFinal.json.recoveryCodesRemaining, undefined)

  cookie = adminCookie
})

test('blueprints include the demo server', async () => {
  const res = await req('GET', '/api/blueprints')
  assert.equal(res.status, 200)
  const blueprints = res.json.blueprints as { id: string }[]
  assert.ok(blueprints.length >= 40)
  assert.ok(blueprints.some((b) => b.id === 'demo-echo'))
})

test('create server from demo blueprint and wait for install', async () => {
  const res = await req('POST', '/api/servers', {
    name: 'E2E Demo',
    blueprintId: 'demo-echo',
    variables: { SERVER_PORT: 28899 },
    autoStart: false,
    startAfterInstall: false,
  })
  assert.equal(res.status, 201)
  const server = res.json.server as { id: string; status: string; runtime: string; blueprint: { platforms: string[] } }
  serverId = server.id
  // The detail payload must carry the blueprint platforms + runtime — the
  // Settings runtime card reads blueprint.platforms and crashed without it.
  assert.ok(Array.isArray(server.blueprint.platforms) && server.blueprint.platforms.includes('linux'))
  assert.equal(server.runtime, 'process')
  await waitFor(async () => (await serverStatus()) === 'offline', 15_000, 'install to finish')
})

test('port conflict is rejected on second server', async () => {
  const res = await req('POST', '/api/servers', {
    name: 'Conflict',
    blueprintId: 'demo-echo',
    variables: { SERVER_PORT: 28899 },
  })
  assert.equal(res.status, 400)
  assert.match(String(res.json.error), /port/i)
})

test('start server and reach running state', async () => {
  const res = await req('POST', `/api/servers/${serverId}/power`, { action: 'start' })
  assert.equal(res.status, 200)
  await waitFor(async () => (await serverStatus()) === 'running', 20_000, 'server running')
})

test('console command roundtrip', async () => {
  const send = await req('POST', `/api/servers/${serverId}/command`, { command: 'say hello-e2e' })
  assert.equal(send.status, 200)
  await waitFor(async () => {
    const res = await req('GET', `/api/servers/${serverId}/console?limit=200`)
    const lines = res.json.lines as { line: string }[]
    return lines.some((l) => l.line.includes('hello-e2e'))
  }, 10_000, 'console echo')
})

test('resources are sampled while running', async () => {
  await waitFor(async () => {
    const res = await req('GET', `/api/servers/${serverId}/resources`)
    const snapshot = res.json.resources as { memBytes: number } | null
    return snapshot !== null && snapshot.memBytes > 0
  }, 15_000, 'resource sample')
})

test('file manager: list, write, read, mkdir, rename, move, delete', async () => {
  const list = await req('GET', `/api/servers/${serverId}/files?path=`)
  assert.equal(list.status, 200)
  const entries = list.json.entries as { name: string }[]
  assert.ok(entries.some((e) => e.name === 'demo-server.cjs'))

  const write = await req('PUT', `/api/servers/${serverId}/files/content`, { path: 'notes.txt', content: 'hello files' })
  assert.equal(write.status, 200)
  const read = await req('GET', `/api/servers/${serverId}/files/content?path=notes.txt`)
  assert.equal(read.json.content, 'hello files')

  await req('POST', `/api/servers/${serverId}/files/mkdir`, { path: 'plugins' })
  const rename = await req('POST', `/api/servers/${serverId}/files/rename`, { path: 'notes.txt', newName: 'notes-renamed.txt' })
  assert.equal(rename.status, 200)
  const move = await req('POST', `/api/servers/${serverId}/files/move`, { path: 'notes-renamed.txt', toDir: 'plugins' })
  assert.equal(move.status, 200)
  const inPlugins = await req('GET', `/api/servers/${serverId}/files?path=plugins`)
  assert.ok((inPlugins.json.entries as { name: string }[]).some((e) => e.name === 'notes-renamed.txt'))

  const del = await req('POST', `/api/servers/${serverId}/files/delete`, { paths: ['plugins'] })
  assert.equal(del.status, 200)
})

test('path traversal is blocked', async () => {
  const res = await req('GET', `/api/servers/${serverId}/files/content?path=../../secrets`)
  assert.ok(res.status >= 400)
})

test('config files API: list managed keys, targeted PUT, path safety', async () => {
  // The demo blueprint declares no config files — the listing is just empty
  const empty = await req('GET', `/api/servers/${serverId}/configfiles`)
  assert.equal(empty.status, 200)
  assert.deepEqual(empty.json.files, [])

  // Custom blueprint with a yaml config file: the template makes the file
  // exist right after install, the mappings drive the managed-keys view.
  const bp = await req('POST', '/api/blueprints', {
    blueprint: {
      id: 'e2e-yaml-config',
      name: 'E2E Yaml Config',
      category: 'custom',
      description: 'config files API test',
      platforms: ['linux', 'win32', 'darwin'],
      install: [],
      startCommand: 'node -v',
      stop: { type: 'signal', signal: 'SIGTERM' },
      variables: [
        { key: 'MOTD', label: 'Motd', type: 'string', default: 'hello world' },
        { key: 'GAME_PORT', label: 'Port', type: 'number', default: 28905 },
      ],
      configFiles: [
        {
          path: 'config/settings.yml',
          format: 'yaml',
          template: '# generated by e2e\nserver:\n  motd: {{MOTD}}\n  port: {{GAME_PORT}}\nfeatures:\n  pvp: true\n',
          mappings: { MOTD: 'server.motd', GAME_PORT: 'server.port' },
        },
      ],
    },
  })
  assert.equal(bp.status, 201)

  const created = await req('POST', '/api/servers', { name: 'E2E Config', blueprintId: 'e2e-yaml-config', variables: {} })
  assert.equal(created.status, 201)
  const configServerId = (created.json.server as { id: string }).id
  const configStatus = async () => {
    const res = await req('GET', `/api/servers/${configServerId}`)
    return (res.json.server as { status: string }).status
  }
  await waitFor(async () => (await configStatus()) === 'offline', 15_000, 'config server install')

  // GET returns the declared file with the current on-disk values per mapping
  const list = await req('GET', `/api/servers/${configServerId}/configfiles`)
  assert.equal(list.status, 200)
  const files = list.json.files as {
    path: string
    format: string
    exists: boolean
    managed: { varKey: string; configKey: string; value: string | null; varValue: string | null }[]
  }[]
  assert.equal(files.length, 1)
  assert.equal(files[0].path, 'config/settings.yml')
  assert.equal(files[0].format, 'yaml')
  assert.equal(files[0].exists, true)
  const motd = files[0].managed.find((m) => m.varKey === 'MOTD')!
  assert.equal(motd.configKey, 'server.motd')
  assert.equal(motd.value, 'hello world')
  assert.equal(motd.varValue, 'hello world')
  const port = files[0].managed.find((m) => m.varKey === 'GAME_PORT')!
  assert.equal(port.value, '28905')

  // PUT edits mapped and unmapped keys through the format engine
  const put = await req('PUT', `/api/servers/${configServerId}/configfiles`, {
    path: 'config/settings.yml',
    values: { 'server.motd': 'updated via api', 'features.pvp': 'false' },
  })
  assert.equal(put.status, 200)
  const after = await req('GET', `/api/servers/${configServerId}/configfiles`)
  const managedAfter = (after.json.files as typeof files)[0].managed
  assert.equal(managedAfter.find((m) => m.varKey === 'MOTD')!.value, 'updated via api')

  // The edit was surgical: comments and unrelated keys survive on disk
  const content = await req('GET', `/api/servers/${configServerId}/files/content?path=config/settings.yml`)
  assert.match(String(content.json.content), /# generated by e2e/)
  assert.match(String(content.json.content), /pvp: false/)
  assert.match(String(content.json.content), /port: 28905/)

  // Only declared paths are writable; traversal is rejected outright
  const undeclared = await req('PUT', `/api/servers/${configServerId}/configfiles`, {
    path: 'other.yml',
    values: { a: 'b' },
  })
  assert.equal(undeclared.status, 400)
  const traversal = await req('PUT', `/api/servers/${configServerId}/configfiles`, {
    path: '../../evil.yml',
    values: { a: 'b' },
  })
  assert.equal(traversal.status, 400)
  const noValues = await req('PUT', `/api/servers/${configServerId}/configfiles`, { path: 'config/settings.yml', values: {} })
  assert.equal(noValues.status, 400)

  // Clean up so the remaining journey still sees exactly one server
  const del = await req('DELETE', `/api/servers/${configServerId}`)
  assert.equal(del.status, 200)
  const delBp = await req('DELETE', '/api/blueprints/e2e-yaml-config')
  assert.equal(delBp.status, 200)
})

test('stop server gracefully', async () => {
  const res = await req('POST', `/api/servers/${serverId}/power`, { action: 'stop' })
  assert.equal(res.status, 200)
  await waitFor(async () => (await serverStatus()) === 'offline', 20_000, 'server offline')
})

test('clone: port conflict, variables override, files copied, clone starts', async () => {
  // Cloning with the source's ports collides just like creating would.
  const conflict = await req('POST', `/api/servers/${serverId}/clone`, { name: 'E2E Clone', copyFiles: true })
  assert.equal(conflict.status, 400)
  assert.match(String(conflict.json.error), /port/i)

  // With a port override the clone succeeds, copies files and is startable.
  const created = await req('POST', `/api/servers/${serverId}/clone`, {
    name: 'E2E Clone',
    copyFiles: true,
    variables: { SERVER_PORT: 28901 },
  })
  assert.equal(created.status, 201)
  const clone = created.json.server as {
    id: string
    installed: boolean
    autoStart: boolean
    variables: Record<string, unknown>
  }
  assert.notEqual(clone.id, serverId)
  assert.equal(clone.installed, true)
  assert.equal(clone.autoStart, false)
  assert.equal(clone.variables.SERVER_PORT, 28901)

  const cloneStatus = async () => {
    const res = await req('GET', `/api/servers/${clone.id}`)
    return (res.json.server as { status: string }).status
  }

  // A known source file made it into the clone's directory.
  const read = await req('GET', `/api/servers/${clone.id}/files/content?path=README.txt`)
  assert.equal(read.status, 200)

  const start = await req('POST', `/api/servers/${clone.id}/power`, { action: 'start' })
  assert.equal(start.status, 200)
  await waitFor(async () => (await cloneStatus()) === 'running', 20_000, 'clone running')
  await req('POST', `/api/servers/${clone.id}/power`, { action: 'stop' })
  await waitFor(async () => (await cloneStatus()) === 'offline', 20_000, 'clone offline')

  // Clean up so the remaining journey still sees exactly one server.
  const del = await req('DELETE', `/api/servers/${clone.id}`)
  assert.equal(del.status, 200)
})

test('backup create, list, lock, restore', async () => {
  const created = await req('POST', `/api/servers/${serverId}/backups`, { note: 'e2e backup' })
  assert.equal(created.status, 201)
  backupId = (created.json.backup as { id: string }).id

  const list = await req('GET', `/api/servers/${serverId}/backups`)
  const backups = list.json.backups as { id: string; note: string }[]
  assert.ok(backups.some((b) => b.id === backupId && b.note === 'e2e backup'))

  const lock = await req('POST', `/api/servers/${serverId}/backups/${backupId}/lock`, { locked: true })
  assert.equal(lock.status, 200)
  const delLocked = await req('DELETE', `/api/servers/${serverId}/backups/${backupId}`)
  assert.ok(delLocked.status >= 400) // locked backups cannot be deleted
  await req('POST', `/api/servers/${serverId}/backups/${backupId}/lock`, { locked: false })

  // Delete a file, restore, verify it is back
  await req('POST', `/api/servers/${serverId}/files/delete`, { paths: ['README.txt'] })
  const restore = await req('POST', `/api/servers/${serverId}/backups/${backupId}/restore`, { wipe: false, safetyBackup: false })
  assert.equal(restore.status, 200)
  const read = await req('GET', `/api/servers/${serverId}/files/content?path=README.txt`)
  assert.equal(read.status, 200)
})

test('schedules: create, preview, run now', async () => {
  const preview = await req('POST', '/api/schedules/preview', { cron: '*/5 * * * *' })
  assert.equal(preview.json.valid, true)
  assert.ok((preview.json.nextRuns as number[]).length > 0)

  const bad = await req('POST', '/api/schedules/preview', { cron: 'not a cron' })
  assert.equal(bad.json.valid, false)

  const created = await req('POST', `/api/servers/${serverId}/schedules`, {
    name: 'E2E backup schedule',
    cron: '0 4 * * *',
    tasks: [{ type: 'backup', note: 'from schedule' }],
    enabled: true,
    onlyIfRunning: false,
  })
  assert.equal(created.status, 201)
  const scheduleId = (created.json.schedule as { id: string }).id

  const run = await req('POST', `/api/servers/${serverId}/schedules/${scheduleId}/run`)
  assert.equal(run.status, 200)
  await waitFor(async () => {
    const list = await req('GET', `/api/servers/${serverId}/backups`)
    return (list.json.backups as { note: string }[]).some((b) => b.note === 'from schedule')
  }, 15_000, 'scheduled backup')
})

test('users + subusers + permissions', async () => {
  const created = await req('POST', '/api/users', { username: 'helper', password: 'helper-pass-1', role: 'user' })
  assert.equal(created.status, 201)

  const sub = await req('POST', `/api/servers/${serverId}/subusers`, {
    username: 'helper',
    permissions: ['server.view', 'server.console'],
  })
  assert.equal(sub.status, 201)

  // Sign in as helper in a parallel cookie jar
  const adminCookie = cookie
  cookie = ''
  const login = await req('POST', '/api/auth/login', { username: 'helper', password: 'helper-pass-1' })
  assert.equal(login.status, 200)

  const visible = await req('GET', '/api/servers')
  assert.equal((visible.json.servers as unknown[]).length, 1)

  // helper lacks server.power
  const power = await req('POST', `/api/servers/${serverId}/power`, { action: 'start' })
  assert.equal(power.status, 403)

  // helper cannot access admin endpoints
  const users = await req('GET', '/api/users')
  assert.equal(users.status, 403)

  cookie = adminCookie
})

test('subuser with server.users cannot escalate permissions', async () => {
  const adminCookie = cookie
  await req('POST', '/api/users', { username: 'granter', password: 'granter-pass-1', role: 'user' })
  await req('POST', '/api/users', { username: 'victim', password: 'victim-pass-1', role: 'user' })
  const addGranter = await req('POST', `/api/servers/${serverId}/subusers`, {
    username: 'granter',
    permissions: ['server.view', 'server.users'],
  })
  assert.equal(addGranter.status, 201)

  cookie = ''
  const login = await req('POST', '/api/auth/login', { username: 'granter', password: 'granter-pass-1' })
  assert.equal(login.status, 200)

  // Granting a permission the granter doesn't hold (power/config) must be stripped.
  const addVictim = await req('POST', `/api/servers/${serverId}/subusers`, {
    username: 'victim',
    permissions: ['server.view', 'server.power', 'server.config'],
  })
  assert.equal(addVictim.status, 201)
  const victimPerms = (addVictim.json.subuser as { permissions: string[] }).permissions
  assert.ok(!victimPerms.includes('server.power'), 'server.power must be clamped away')
  assert.ok(!victimPerms.includes('server.config'), 'server.config must be clamped away')

  // Editing one's own subuser row is forbidden outright.
  const list = await req('GET', `/api/servers/${serverId}/subusers`)
  const granterSub = (list.json.subusers as { id: string; username: string }[]).find((s) => s.username === 'granter')!
  const selfPatch = await req('PATCH', `/api/servers/${serverId}/subusers/${granterSub.id}`, {
    permissions: ['server.view', 'server.users', 'server.power'],
  })
  assert.equal(selfPatch.status, 403)

  cookie = adminCookie
})

test('schedule tasks require the matching permission', async () => {
  const adminCookie = cookie
  await req('POST', '/api/users', { username: 'sched', password: 'sched-pass-1', role: 'user' })
  const addSched = await req('POST', `/api/servers/${serverId}/subusers`, {
    username: 'sched',
    permissions: ['server.view', 'server.schedules'],
  })
  assert.equal(addSched.status, 201)

  // Admin creates a backup schedule; the schedules-only subuser must not be able to /run it.
  const adminSchedule = await req('POST', `/api/servers/${serverId}/schedules`, {
    name: 'admin backup', cron: '0 5 * * *', tasks: [{ type: 'backup', note: 'x' }],
  })
  assert.equal(adminSchedule.status, 201)
  const adminScheduleId = (adminSchedule.json.schedule as { id: string }).id

  cookie = ''
  await req('POST', '/api/auth/login', { username: 'sched', password: 'sched-pass-1' })

  const powerTask = await req('POST', `/api/servers/${serverId}/schedules`, {
    name: 'sneaky', cron: '0 6 * * *', tasks: [{ type: 'power', action: 'start' }],
  })
  assert.equal(powerTask.status, 403)
  const cmdTask = await req('POST', `/api/servers/${serverId}/schedules`, {
    name: 'sneaky2', cron: '0 6 * * *', tasks: [{ type: 'command', command: 'op me' }],
  })
  assert.equal(cmdTask.status, 403)
  const waitOk = await req('POST', `/api/servers/${serverId}/schedules`, {
    name: 'ok wait', cron: '0 6 * * *', tasks: [{ type: 'wait', seconds: 5 }],
  })
  assert.equal(waitOk.status, 201)
  const run = await req('POST', `/api/servers/${serverId}/schedules/${adminScheduleId}/run`)
  assert.equal(run.status, 403)

  cookie = adminCookie
})

test('read-only api key cannot perform writes', async () => {
  const created = await req('POST', '/api/apikeys', { name: 'ro-key', scopes: ['read'] })
  assert.equal(created.status, 201)
  const secret = created.json.secret as string

  const get = await fetch(`${base}/api/servers`, { headers: { authorization: `Bearer ${secret}` } })
  assert.equal(get.status, 200)

  const post = await fetch(`${base}/api/servers`, {
    method: 'POST',
    headers: { authorization: `Bearer ${secret}`, 'content-type': 'application/json' },
    body: JSON.stringify({ name: 'x', blueprintId: 'demo-echo', variables: {} }),
  })
  assert.equal(post.status, 403)
})

test('api keys authenticate requests', async () => {
  const created = await req('POST', '/api/apikeys', { name: 'e2e-key' })
  assert.equal(created.status, 201)
  const secret = created.json.secret as string
  assert.ok(secret.length > 20)

  const res = await fetch(`${base}/api/servers`, { headers: { authorization: `Bearer ${secret}` } })
  assert.equal(res.status, 200)

  const bad = await fetch(`${base}/api/servers`, { headers: { authorization: 'Bearer between_invalid' } })
  assert.equal(bad.status, 401)
})

test('audit log recorded the journey', async () => {
  const res = await req('GET', '/api/audit?limit=100')
  assert.equal(res.status, 200)
  const actions = (res.json.entries as { action: string }[]).map((e) => e.action)
  for (const expected of ['auth.setup', 'server.created', 'server.cloned', 'server.power.start', 'backup.created', 'user.created']) {
    assert.ok(actions.includes(expected), `audit contains ${expected}`)
  }
})

test('crash detection flags an unexpected exit', async () => {
  // disable auto-restart first (steamAutoUpdate rides along to cover the PATCH whitelist round-trip)
  const patched = await req('PATCH', `/api/servers/${serverId}`, {
    restartPolicy: { enabled: false, maxRetries: 3, backoffS: 5 },
    steamAutoUpdate: true,
  })
  assert.equal(patched.status, 200)
  assert.equal((patched.json.server as { steamAutoUpdate: boolean }).steamAutoUpdate, true)
  const detail = await req('GET', `/api/servers/${serverId}`)
  assert.equal((detail.json.server as { steamAutoUpdate: boolean }).steamAutoUpdate, true)
  await req('POST', `/api/servers/${serverId}/power`, { action: 'start' })
  await waitFor(async () => (await serverStatus()) === 'running', 20_000, 'server running again')
  await req('POST', `/api/servers/${serverId}/command`, { command: 'crash' })
  await waitFor(async () => (await serverStatus()) === 'crashed', 15_000, 'crash detected')
})

test('event schedules: validation, event firing, template rendering, debounce', async () => {
  // --- Trigger validation ----------------------------------------------------
  const badEvent = await req('POST', `/api/servers/${serverId}/schedules`, {
    name: 'bad event', trigger: { type: 'event', event: 'server.exploded' }, tasks: [{ type: 'wait', seconds: 1 }],
  })
  assert.equal(badEvent.status, 400)
  assert.match(String(badEvent.json.error), /unknown event/)
  const badType = await req('POST', `/api/servers/${serverId}/schedules`, {
    name: 'bad type', trigger: { type: 'lunar-phase' }, tasks: [{ type: 'wait', seconds: 1 }],
  })
  assert.equal(badType.status, 400)
  assert.match(String(badType.json.error), /unknown type/)
  const badCronTrigger = await req('POST', `/api/servers/${serverId}/schedules`, {
    name: 'bad cron', trigger: { type: 'cron', expr: 'not a cron' }, tasks: [{ type: 'wait', seconds: 1 }],
  })
  assert.equal(badCronTrigger.status, 400)

  // --- Create event schedules (server is currently crashed from the previous test)
  const onRunning = await req('POST', `/api/servers/${serverId}/schedules`, {
    name: 'On running',
    trigger: { type: 'event', event: 'server.running' },
    tasks: [{ type: 'command', command: 'say up {server} is {state} with {players} players' }],
  })
  assert.equal(onRunning.status, 201)
  const onRunningSchedule = onRunning.json.schedule as { id: string; trigger: unknown; nextRunAt: number | null; cron: string }
  assert.deepEqual(onRunningSchedule.trigger, { type: 'event', event: 'server.running' })
  assert.equal(onRunningSchedule.nextRunAt, null, 'event schedules have no cron next-run')

  const onCrash = await req('POST', `/api/servers/${serverId}/schedules`, {
    name: 'On crash',
    trigger: { type: 'event', event: 'server.crashed' },
    tasks: [
      { type: 'power', action: 'start' },
      { type: 'command', command: 'say recovered-{server}' },
    ],
  })
  assert.equal(onCrash.status, 201)
  const onCrashId = (onCrash.json.schedule as { id: string }).id

  const runsOf = async (sid: string): Promise<{ ts: string; ok: boolean; message: string; source?: string }[]> => {
    const list = await req('GET', `/api/servers/${serverId}/schedules`)
    const schedule = (list.json.schedules as { id: string; lastRuns: { ts: string; ok: boolean; message: string; source?: string }[] }[])
      .find((s) => s.id === sid)
    return schedule?.lastRuns ?? []
  }
  const consoleHas = async (needle: string): Promise<boolean> => {
    const res = await req('GET', `/api/servers/${serverId}/console?limit=400`)
    return (res.json.lines as { line: string }[]).some((l) => l.line.includes(needle))
  }

  // --- server.running fires on start, command template renders at run time ---
  await req('POST', `/api/servers/${serverId}/power`, { action: 'start' })
  await waitFor(async () => (await serverStatus()) === 'running', 20_000, 'server running for event test')
  await waitFor(async () => (await runsOf(onRunningSchedule.id)).length === 1, 10_000, 'server.running schedule ran')
  const runningRun = (await runsOf(onRunningSchedule.id))[0]
  assert.equal(runningRun.ok, true)
  assert.equal(runningRun.source, 'event:server.running')
  // demo-echo echoes `say X` as `[Server] X`; no query block → {players} = 0.
  await waitFor(async () => consoleHas('up E2E Demo is running with 0 players'), 10_000, 'rendered say line in console')

  // --- server.crashed fires, task chain recovers the server ------------------
  await req('POST', `/api/servers/${serverId}/command`, { command: 'crash' })
  await waitFor(async () => (await runsOf(onCrashId)).length === 1, 15_000, 'server.crashed schedule ran')
  const crashRun = (await runsOf(onCrashId))[0]
  assert.equal(crashRun.source, 'event:server.crashed')
  assert.equal(crashRun.ok, true)
  assert.equal(crashRun.message, 'ok: power:start, command')
  await waitFor(async () => consoleHas('recovered-E2E Demo'), 10_000, 'rendered recovery line in console')
  await waitFor(async () => (await serverStatus()) === 'running', 20_000, 'server recovered by schedule')

  // The recovery start was a second server.running within the 30s window —
  // the "On running" schedule must have been debounced.
  assert.equal((await runsOf(onRunningSchedule.id)).length, 1, 'server.running debounced during recovery')

  // --- Debounce: an immediate second crash must not queue another run --------
  await req('POST', `/api/servers/${serverId}/command`, { command: 'crash' })
  await waitFor(async () => (await serverStatus()) === 'crashed', 15_000, 'second crash detected')
  await sleep(1500)
  assert.equal((await runsOf(onCrashId)).length, 1, 'crash-loop debounced (min interval)')

  // --- Editing between trigger types round-trips ----------------------------
  const toCron = await req('PATCH', `/api/servers/${serverId}/schedules/${onCrashId}`, {
    trigger: { type: 'cron', expr: '0 4 * * *' },
  })
  assert.equal(toCron.status, 200)
  const patched = toCron.json.schedule as { trigger: unknown; cron: string; nextRunAt: number | null }
  assert.deepEqual(patched.trigger, { type: 'cron', expr: '0 4 * * *' })
  assert.equal(patched.cron, '0 4 * * *')
  assert.ok(patched.nextRunAt !== null, 'cron trigger regains a next-run time')
})

test('server deletion removes files and broadcasts a deleted event', async () => {
  // Subscribe over WS first: the deleted event must reach clients even though
  // the server is already gone from the store when the broadcast fires.
  const ws = new WebSocket(`${base.replace('http', 'ws')}/api/ws`, { headers: { cookie } })
  const deletedEvent = new Promise<string>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('no deleted event within 10s')), 10_000)
    ws.on('message', (raw) => {
      const msg = JSON.parse(String(raw)) as { t?: string; serverId?: string }
      if (msg.t === 'deleted') {
        clearTimeout(timer)
        resolve(msg.serverId ?? '')
      }
    })
    ws.on('error', reject)
  })
  await new Promise<void>((resolve, reject) => {
    ws.once('open', resolve)
    ws.once('error', reject)
  })

  const del = await req('DELETE', `/api/servers/${serverId}`, { deleteBackups: true })
  assert.equal(del.status, 200)
  assert.equal(await deletedEvent, serverId)
  ws.close()

  const list = await req('GET', '/api/servers')
  assert.equal((list.json.servers as unknown[]).length, 0)
  const serversDir = path.join(dataDir, 'servers')
  const left = fs.existsSync(serversDir) ? fs.readdirSync(serversDir) : []
  assert.equal(left.length, 0)
})
