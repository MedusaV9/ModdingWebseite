/**
 * Authenticated Steam login integration test: boots the real app against
 * scripts/fake-steamcmd.mjs (via the BETWEEN_STEAMCMD_BIN override) and
 * walks the whole credential lifecycle end to end — admin gating, fail-fast
 * install without a session, wrong password, the two-step Steam Guard flow,
 * the cached-session probe, login-required + override installs, logout, and
 * the "password never appears anywhere" guarantee (grep-asserted against
 * every API response, the audit log and the install console).
 */
import { test, before, after } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { createApp, type BetweenApp } from '../../src/app.ts'
import { sleep } from '../../src/lib/util.ts'

const STEAM_USER = 'panel-demo'
const STEAM_PASS = 'sup3r-Secret.Pw!'
// Non-hex letters on purpose: the final leak sweep greps every response body,
// and a hex-only code could legitimately appear inside a random UUID.
const GUARD_CODE = 'R2X7KQ'
/** App id the fake refuses to install anonymously ("No subscription"). */
const LOGIN_APP = '4242'
/** App id that installs fine anonymously. */
const FREE_APP = '5151'

let app: BetweenApp
let base = ''
let cookie = ''
let userCookie = ''
let dataDir = ''
let loginServerId = ''
let freeServerId = ''
/** Every response body seen by this test — swept for secrets at the end. */
const seenBodies: string[] = []

async function reqAs(
  jar: 'admin' | 'user',
  method: string,
  urlPath: string,
  body?: unknown,
): Promise<{ status: number; json: Record<string, unknown> }> {
  const current = jar === 'admin' ? cookie : userCookie
  const res = await fetch(`${base}${urlPath}`, {
    method,
    headers: {
      ...(body !== undefined ? { 'content-type': 'application/json' } : {}),
      ...(current ? { cookie: current } : {}),
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  })
  const setCookie = res.headers.get('set-cookie')
  if (setCookie) {
    if (jar === 'admin') cookie = setCookie.split(';')[0]
    else userCookie = setCookie.split(';')[0]
  }
  const text = await res.text()
  seenBodies.push(text)
  return { status: res.status, json: text ? (JSON.parse(text) as Record<string, unknown>) : {} }
}

const req = (method: string, urlPath: string, body?: unknown) => reqAs('admin', method, urlPath, body)

async function waitForStatus(serverId: string, wanted: string[], timeoutMs = 15_000): Promise<string> {
  const start = Date.now()
  for (;;) {
    const res = await req('GET', `/api/servers/${serverId}`)
    const status = (res.json.server as { status: string }).status
    if (wanted.includes(status)) return status
    if (Date.now() - start > timeoutMs) throw new Error(`timeout waiting for ${wanted.join('|')} (still ${status})`)
    await sleep(200)
  }
}

function steamBlueprint(id: string, appId: string, requiresLogin: boolean) {
  return {
    id,
    name: `Fake Steam Game ${appId}`,
    category: 'steam',
    description: 'test blueprint',
    platforms: ['linux', 'win32', 'darwin'],
    install: [{ type: 'steamcmd', appId, validate: false, ...(requiresLogin ? { requiresLogin: true } : {}) }],
    startCommand: 'node -e "setInterval(() => {}, 1000)"',
    stop: { type: 'signal', signal: 'SIGTERM' },
    variables: [],
  }
}

before(async () => {
  dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'between-steam-'))
  // Thin executable wrapper around the fake so BETWEEN_STEAMCMD_BIN works
  // regardless of the repo file's exec bit / host platform.
  const fake = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', 'scripts', 'fake-steamcmd.mjs')
  let bin: string
  if (process.platform === 'win32') {
    bin = path.join(dataDir, 'fake-steamcmd.cmd')
    fs.writeFileSync(bin, `@echo off\r\n"${process.execPath}" "${fake}" %*\r\n`)
  } else {
    bin = path.join(dataDir, 'fake-steamcmd')
    fs.writeFileSync(bin, `#!/bin/sh\nexec "${process.execPath}" "${fake}" "$@"\n`, { mode: 0o755 })
  }
  // The fake's account database + gating (inherited by spawned children).
  process.env.FAKE_STEAMCMD_USER = STEAM_USER
  process.env.FAKE_STEAMCMD_PASS = STEAM_PASS
  process.env.FAKE_STEAMCMD_GUARD = '' // guard turned on later in the flow
  process.env.FAKE_STEAMCMD_LOGIN_APPS = LOGIN_APP

  app = createApp({ port: 0, host: '127.0.0.1', dataDir, webDistDir: path.join(dataDir, 'no-web'), steamcmdBin: bin })
  const { port } = await app.start()
  base = `http://127.0.0.1:${port}`
  await req('POST', '/api/auth/setup', { username: 'admin', password: 'super-secret-1', panelName: 'Steam E2E' })
})

after(async () => {
  await app.stop()
  fs.rmSync(dataDir, { recursive: true, force: true })
})

test('fresh panel: no Steam account configured, not logged in', async () => {
  const status = await req('GET', '/api/steam/status')
  assert.equal(status.status, 200)
  assert.equal(status.json.installed, true) // bin override counts as installed
  assert.equal(status.json.loginConfigured, false)
  const login = await req('GET', '/api/steam/login')
  assert.equal(login.status, 200)
  assert.deepEqual(login.json, { user: null, loggedIn: false })
})

test('steam login endpoints are admin-only', async () => {
  await req('POST', '/api/users', { username: 'pleb', password: 'user-password-1', role: 'user' })
  const login = await reqAs('user', 'POST', '/api/auth/login', { username: 'pleb', password: 'user-password-1' })
  assert.equal(login.status, 200)
  assert.equal((await reqAs('user', 'GET', '/api/steam/login')).status, 403)
  assert.equal((await reqAs('user', 'POST', '/api/steam/login', { username: 'x', password: 'y' })).status, 403)
  assert.equal((await reqAs('user', 'POST', '/api/steam/logout')).status, 403)
})

test('install of a requiresLogin blueprint fails fast without a session', async () => {
  const bp = await req('POST', '/api/blueprints', { blueprint: steamBlueprint('fake-login-game', LOGIN_APP, true) })
  assert.equal(bp.status, 201)
  const created = await req('POST', '/api/servers', {
    name: 'Login Game',
    blueprintId: 'fake-login-game',
    variables: {},
    autoStart: false,
    startAfterInstall: false,
  })
  assert.equal(created.status, 201)
  loginServerId = (created.json.server as { id: string }).id
  await waitForStatus(loginServerId, ['install_failed'])
  const detail = await req('GET', `/api/servers/${loginServerId}`)
  const err = String((detail.json.server as { installError: string }).installError)
  assert.match(err, /Steam login required/i)
  assert.match(err, /Panel Settings/i)
  // Fail-fast means steamcmd never ran — no app file, no session artifacts.
  const serverDir = fs.readdirSync(path.join(dataDir, 'servers'))[0]
  assert.ok(!fs.existsSync(path.join(dataDir, 'servers', serverDir, `fake-app-${LOGIN_APP}.txt`)))
})

test('wrong password surfaces a clean error and never echoes the password', async () => {
  const res = await req('POST', '/api/steam/login', { username: STEAM_USER, password: 'not-the-password' })
  assert.equal(res.status, 200)
  assert.equal(res.json.ok, false)
  assert.equal(res.json.needsGuard, undefined)
  assert.match(String(res.json.error), /Invalid Password/i)
  assert.ok(!JSON.stringify(res.json).includes('not-the-password'))
  // Still not configured after a failed attempt.
  const status = await req('GET', '/api/steam/status')
  assert.equal(status.json.loginConfigured, false)
})

test('Steam Guard: first call reports needsGuard, second call with the code signs in', async () => {
  process.env.FAKE_STEAMCMD_GUARD = GUARD_CODE
  const first = await req('POST', '/api/steam/login', { username: STEAM_USER, password: STEAM_PASS })
  assert.equal(first.json.ok, false)
  assert.equal(first.json.needsGuard, true)

  const wrongCode = await req('POST', '/api/steam/login', { username: STEAM_USER, password: STEAM_PASS, guardCode: '000000' })
  assert.equal(wrongCode.json.ok, false)
  assert.match(String(wrongCode.json.error), /Two-factor/i)

  const second = await req('POST', '/api/steam/login', { username: STEAM_USER, password: STEAM_PASS, guardCode: GUARD_CODE })
  assert.equal(second.json.ok, true, JSON.stringify(second.json))

  // SteamCMD cached the session in its home dir (the panel's steamcmd dir).
  assert.ok(fs.existsSync(path.join(dataDir, 'steamcmd', 'config', 'config.vdf')))
  assert.ok(fs.readdirSync(path.join(dataDir, 'steamcmd')).some((f) => f.startsWith('ssfn')))
  const status = await req('GET', '/api/steam/status')
  assert.equal(status.json.loginConfigured, true)
})

test('status probe re-validates the cached session without a password', async () => {
  // refresh=true bypasses the TTL cache and runs a real +login <user> probe.
  const probed = await req('GET', '/api/steam/login?refresh=true')
  assert.deepEqual(probed.json, { user: STEAM_USER, loggedIn: true })
})

test('requiresLogin install succeeds once a session exists', async () => {
  assert.equal((await req('POST', `/api/servers/${loginServerId}/reinstall`)).status, 200)
  await waitForStatus(loginServerId, ['offline'])
  const detail = await req('GET', `/api/servers/${loginServerId}`)
  const dirName = fs.readdirSync(path.join(dataDir, 'servers')).find((d) => d.startsWith('login-game'))!
  const marker = fs.readFileSync(path.join(dataDir, 'servers', dirName, `fake-app-${LOGIN_APP}.txt`), 'utf8')
  assert.match(marker, new RegExp(`login=${STEAM_USER}`))
  assert.equal((detail.json.server as { installed: boolean }).installed, true)
})

test('server-level useSteamLogin override switches an anonymous game to +login', async () => {
  const bp = await req('POST', '/api/blueprints', { blueprint: steamBlueprint('fake-free-game', FREE_APP, false) })
  assert.equal(bp.status, 201)
  const created = await req('POST', '/api/servers', {
    name: 'Free Game',
    blueprintId: 'fake-free-game',
    variables: {},
    autoStart: false,
    startAfterInstall: false,
  })
  assert.equal(created.status, 201)
  freeServerId = (created.json.server as { id: string }).id
  await waitForStatus(freeServerId, ['offline'])
  const dirName = fs.readdirSync(path.join(dataDir, 'servers')).find((d) => d.startsWith('free-game'))!
  const markerPath = path.join(dataDir, 'servers', dirName, `fake-app-${FREE_APP}.txt`)
  assert.match(fs.readFileSync(markerPath, 'utf8'), /login=anonymous/)

  // Flip the per-server override and re-run the steam update.
  const patched = await req('PATCH', `/api/servers/${freeServerId}`, { useSteamLogin: true })
  assert.equal((patched.json.server as { useSteamLogin: boolean }).useSteamLogin, true)
  assert.equal((await req('POST', `/api/servers/${freeServerId}/steam-update`)).status, 200)
  await waitForStatus(freeServerId, ['offline'])
  const start = Date.now()
  for (;;) {
    if (fs.readFileSync(markerPath, 'utf8').includes(`login=${STEAM_USER}`)) break
    if (Date.now() - start > 10_000) assert.fail(`marker still: ${fs.readFileSync(markerPath, 'utf8')}`)
    await sleep(200)
  }
})

test('logout clears the cached session and the account', async () => {
  assert.equal((await req('POST', '/api/steam/logout')).status, 200)
  const login = await req('GET', '/api/steam/login')
  assert.deepEqual(login.json, { user: null, loggedIn: false })
  assert.ok(!fs.existsSync(path.join(dataDir, 'steamcmd', 'config', 'config.vdf')))
  assert.ok(!fs.readdirSync(path.join(dataDir, 'steamcmd')).some((f) => f.startsWith('ssfn')))
  assert.equal((await req('GET', '/api/steam/status')).json.loginConfigured, false)
})

test('after logout, login-required installs fail fast again', async () => {
  assert.equal((await req('POST', `/api/servers/${loginServerId}/reinstall`)).status, 200)
  await waitForStatus(loginServerId, ['install_failed'])
  const detail = await req('GET', `/api/servers/${loginServerId}`)
  assert.match(String((detail.json.server as { installError: string }).installError), /Steam login required/i)
})

test('secrets never appear in any API response, the audit log or the console', async () => {
  const audit = await req('GET', '/api/audit?limit=200')
  const auditDump = JSON.stringify(audit.json)
  // The audit trail records outcomes (with the account name) but no secrets.
  assert.match(auditDump, /steam\.login_failed/)
  assert.match(auditDump, /"steam\.login"/)
  assert.match(auditDump, /steam\.logout/)
  assert.match(auditDump, new RegExp(STEAM_USER))
  const console1 = await req('GET', `/api/servers/${loginServerId}/console?limit=2000`)
  const console2 = await req('GET', `/api/servers/${freeServerId}/console?limit=2000`)
  for (const dump of [auditDump, JSON.stringify(console1.json), JSON.stringify(console2.json), ...seenBodies]) {
    assert.ok(!dump.includes(STEAM_PASS), 'password leaked')
    assert.ok(!dump.includes('not-the-password'), 'wrong-attempt password leaked')
    assert.ok(!dump.includes(GUARD_CODE), 'guard code leaked')
  }
})
