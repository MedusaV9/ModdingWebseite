/**
 * Backup retention integration test: boots the real app (random port, temp
 * data dir) and exercises the per-server "keep last N unlocked backups"
 * policy end to end — PATCH validation (400 on bad values), pruning on
 * manual create, locked backups surviving without counting toward N, the
 * schedule-triggered backup path sharing the same choke point, the
 * `backup.pruned` audit entry, 0 = unlimited, and null = panel default.
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

interface BackupRow {
  id: string
  fileName: string
  note: string
  locked: boolean
  createdAt: string
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

async function listBackups(): Promise<{ backups: BackupRow[]; retention: number }> {
  const res = await req('GET', `/api/servers/${serverId}/backups`)
  assert.equal(res.status, 200)
  return { backups: res.json.backups as BackupRow[], retention: res.json.retention as number }
}

async function createBackup(note: string): Promise<BackupRow> {
  const res = await req('POST', `/api/servers/${serverId}/backups`, { note })
  assert.equal(res.status, 201)
  // Distinct createdAt millis keep the prune ordering deterministic.
  await sleep(30)
  return res.json.backup as BackupRow
}

function zipsOnDisk(): string[] {
  const dir = path.join(dataDir, 'backups', serverId)
  return fs.existsSync(dir) ? fs.readdirSync(dir).sort() : []
}

before(async () => {
  dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'between-backups-'))
  app = createApp({ port: 0, host: '127.0.0.1', dataDir, webDistDir: path.join(dataDir, 'no-web') })
  const { port } = await app.start()
  base = `http://127.0.0.1:${port}`
  const res = await req('POST', '/api/auth/setup', { username: 'admin', password: 'backups-secret-1' })
  assert.equal(res.status, 200)

  const created = await req('POST', '/api/servers', {
    name: 'Retention Demo',
    blueprintId: 'demo-echo',
    variables: { SERVER_PORT: 28930 },
  })
  assert.equal(created.status, 201)
  serverId = (created.json.server as { id: string }).id
  await waitFor(async () => {
    const detail = await req('GET', `/api/servers/${serverId}`)
    return (detail.json.server as { status: string }).status === 'offline'
  }, 15_000, 'install to finish')
})

after(async () => {
  await app.stop()
  fs.rmSync(dataDir, { recursive: true, force: true })
})

test('backupRetention PATCH validation: 400 on bad values, accepts 0-50 and null', async () => {
  for (const bad of [-1, 51, 2.5, 'abc', true, {}]) {
    const res = await req('PATCH', `/api/servers/${serverId}`, { backupRetention: bad })
    assert.equal(res.status, 400, `backupRetention ${JSON.stringify(bad)} must be rejected`)
  }

  const ok = await req('PATCH', `/api/servers/${serverId}`, { backupRetention: 5 })
  assert.equal(ok.status, 200)
  assert.equal((ok.json.server as { backupRetention: number | null }).backupRetention, 5)

  const cleared = await req('PATCH', `/api/servers/${serverId}`, { backupRetention: null })
  assert.equal(cleared.status, 200)
  assert.equal((cleared.json.server as { backupRetention: number | null }).backupRetention, null)
})

test('unset per-server retention falls back to the panel default', async () => {
  // The seeded panel settings keep 10 per server — the effective value the
  // backups list reports when the server has no override of its own.
  const { retention } = await listBackups()
  assert.equal(retention, 10)
})

test('retention 2: the third backup prunes the oldest unlocked one', async () => {
  const set = await req('PATCH', `/api/servers/${serverId}`, { backupRetention: 2 })
  assert.equal(set.status, 200)

  const first = await createBackup('first')
  const second = await createBackup('second')
  const third = await createBackup('third')

  const { backups, retention } = await listBackups()
  assert.equal(retention, 2)
  assert.equal(backups.length, 2)
  const ids = backups.map((b) => b.id)
  assert.ok(!ids.includes(first.id), 'oldest backup was pruned')
  assert.ok(ids.includes(second.id) && ids.includes(third.id), 'newest two remain')

  // The pruned archive is gone from disk, the remaining two still exist.
  assert.deepEqual(zipsOnDisk(), [second.fileName, third.fileName].sort())
})

test('the prune is audit-logged as backup.pruned by system', async () => {
  const res = await req('GET', '/api/audit?limit=100')
  assert.equal(res.status, 200)
  const entries = res.json.entries as { action: string; target?: string; serverId?: string; username: string }[]
  const pruned = entries.filter((e) => e.action === 'backup.pruned')
  assert.equal(pruned.length, 1)
  assert.equal(pruned[0].serverId, serverId)
  assert.equal(pruned[0].username, 'system')
  assert.ok(pruned[0].target?.endsWith('.zip'), 'target is the pruned archive name')
})

test('locked backups survive pruning and do not count toward N', async () => {
  const { backups } = await listBackups()
  const oldest = backups[backups.length - 1]
  const lock = await req('POST', `/api/servers/${serverId}/backups/${oldest.id}/lock`, { locked: true })
  assert.equal(lock.status, 200)

  const fourth = await createBackup('fourth')
  const fifth = await createBackup('fifth')

  // 1 locked + keep-2 unlocked: the locked one is exempt from the count, so
  // three backups remain and the oldest *unlocked* one was pruned.
  const after = await listBackups()
  assert.equal(after.backups.length, 3)
  const ids = after.backups.map((b) => b.id)
  assert.ok(ids.includes(oldest.id), 'locked backup survives')
  assert.ok(ids.includes(fourth.id) && ids.includes(fifth.id))
  assert.equal(after.backups.filter((b) => !b.locked).length, 2)
})

test('schedule-triggered backups enforce the same retention', async () => {
  const created = await req('POST', `/api/servers/${serverId}/schedules`, {
    name: 'retention schedule',
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
    const { backups } = await listBackups()
    return backups.some((b) => b.note === 'from schedule')
  }, 15_000, 'scheduled backup')

  // Still 1 locked + exactly 2 unlocked — the scheduled create pruned too.
  const { backups } = await listBackups()
  assert.equal(backups.length, 3)
  assert.equal(backups.filter((b) => !b.locked).length, 2)
  assert.ok(backups.some((b) => b.note === 'from schedule'))
})

test('retention 0 = unlimited keeps everything', async () => {
  const set = await req('PATCH', `/api/servers/${serverId}`, { backupRetention: 0 })
  assert.equal(set.status, 200)

  await createBackup('unlimited-1')
  await createBackup('unlimited-2')

  const { backups, retention } = await listBackups()
  assert.equal(retention, 0)
  assert.equal(backups.length, 5) // 3 from before + 2 new, nothing pruned
})

test('restore at retention 1: the safety backup never prunes the backup being restored', async () => {
  const set = await req('PATCH', `/api/servers/${serverId}`, { backupRetention: 1 })
  assert.equal(set.status, 200)

  // The oldest unlocked backup is the one most at risk: without protectId the
  // pre-restore safety backup (keep=1) would prune it — including its archive
  // — before the restore ever unzips it.
  const { backups } = await listBackups()
  const target = [...backups].reverse().find((b) => !b.locked)!
  const res = await req('POST', `/api/servers/${serverId}/backups/${target.id}/restore`, {})
  assert.equal(res.status, 200)

  const after = await listBackups()
  const ids = after.backups.map((b) => b.id)
  assert.ok(ids.includes(target.id), 'restored backup survives its own safety-backup prune')
  assert.ok(zipsOnDisk().includes(target.fileName), 'restored archive still on disk')
  assert.ok(after.backups.some((b) => b.note.startsWith('pre-restore safety')), 'safety backup exists')
  // locked + protected target + fresh safety backup — every other unlocked one
  // fell out of the keep-1 window.
  assert.equal(after.backups.length, 3)
})

test('cleanup: delete the demo server with its backups', async () => {
  const del = await req('DELETE', `/api/servers/${serverId}`, { deleteBackups: true })
  assert.equal(del.status, 200)
})
