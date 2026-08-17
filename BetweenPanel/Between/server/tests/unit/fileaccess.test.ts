/**
 * FileAccessService unit tests — the SFTP config model + provider seam.
 * v1 ships a placeholder provider, so the contract under test is: honest
 * "not implemented" status, refusing to enable, persisting valid config,
 * rejecting invalid config, and (via a fake implemented provider) the exact
 * start/stop/reconcile lifecycle the real listener will inherit.
 */
import { test, before, after } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { Store, type Collection } from '../../src/lib/jsonstore.ts'
import {
  FileAccessService,
  FILE_ACCESS_DEFAULTS,
  SftpPlaceholderProvider,
  type FileAccessConfig,
  type FileAccessProvider,
} from '../../src/services/fileaccess.ts'
import type { PanelSettings } from '../../src/types.ts'

let dir = ''
let storeSeq = 0

before(() => {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), 'between-fileaccess-'))
})

after(() => {
  fs.rmSync(dir, { recursive: true, force: true })
})

function freshSettings(): Collection<PanelSettings> {
  const store = new Store(path.join(dir, `db-${storeSeq++}`))
  const col = store.collection<PanelSettings>('settings')
  col.insert({
    panelName: 'Unit Panel',
    defaultBackupRetention: 10,
    portRangeStart: 25565,
    portRangeEnd: 29000,
  } as PanelSettings)
  return col
}

/** Minimal implemented provider so the reconcile lifecycle is provable now. */
class FakeSftpProvider implements FileAccessProvider {
  readonly protocol = 'sftp' as const
  readonly implemented = true
  starts: FileAccessConfig[] = []
  stops = 0
  private up = false

  start(config: FileAccessConfig): Promise<void> {
    this.starts.push({ ...config })
    this.up = true
    return Promise.resolve()
  }

  stop(): Promise<void> {
    if (this.up) this.stops++
    this.up = false
    return Promise.resolve()
  }

  running(): boolean {
    return this.up
  }
}

test('defaults: disabled, port 2022, all-interfaces bind', () => {
  const svc = new FileAccessService(freshSettings())
  assert.deepEqual(svc.config(), { ...FILE_ACCESS_DEFAULTS })
  const status = svc.status()
  assert.equal(status.protocol, 'sftp')
  assert.equal(status.implemented, false)
  assert.equal(status.running, false)
  assert.match(status.reason ?? '', /later wave/)
})

test('placeholder provider refuses to enable and never starts', async () => {
  const svc = new FileAccessService(freshSettings())
  const res = await svc.applyConfig({ enabled: true })
  assert.equal(res.ok, false)
  assert.match(res.problems.join(' '), /not implemented/)
  // Nothing persisted — config still shows the defaults.
  assert.equal(svc.config().enabled, false)
  assert.equal(new SftpPlaceholderProvider().running(), false)
})

test('valid port/bind changes persist across service instances', async () => {
  const settings = freshSettings()
  const svc = new FileAccessService(settings)
  const res = await svc.applyConfig({ port: 2222, bind: '127.0.0.1' })
  assert.equal(res.ok, true, res.problems.join('; '))
  const reread = new FileAccessService(settings)
  assert.deepEqual(reread.config(), { enabled: false, port: 2222, bind: '127.0.0.1' })
})

test('invalid config is rejected without persisting anything', async () => {
  const svc = new FileAccessService(freshSettings())
  for (const bad of [{ port: 0 }, { port: 65536 }, { port: 1.5 }, { bind: '' }, { bind: 'has space' }, { bind: 'x'.repeat(65) }]) {
    const res = await svc.applyConfig(bad as Partial<FileAccessConfig>)
    assert.equal(res.ok, false, JSON.stringify(bad))
  }
  assert.deepEqual(svc.config(), { ...FILE_ACCESS_DEFAULTS })
})

test('implemented provider: enable starts, config change restarts, disable stops', async () => {
  const provider = new FakeSftpProvider()
  const svc = new FileAccessService(freshSettings(), provider)

  assert.equal((await svc.applyConfig({ enabled: true, port: 2222 })).ok, true)
  assert.equal(provider.running(), true)
  assert.deepEqual(provider.starts.at(-1), { enabled: true, port: 2222, bind: '0.0.0.0' })
  assert.equal(svc.status().running, true)
  assert.equal(svc.status().reason, undefined)

  // Port change while running → stop + start with the new config.
  assert.equal((await svc.applyConfig({ port: 2323 })).ok, true)
  assert.equal(provider.stops, 1)
  assert.deepEqual(provider.starts.at(-1), { enabled: true, port: 2323, bind: '0.0.0.0' })

  assert.equal((await svc.applyConfig({ enabled: false })).ok, true)
  assert.equal(provider.running(), false)
  assert.match(svc.status().reason ?? '', /disabled/)
})

test('service stop() joins the provider (app shutdown path)', async () => {
  const provider = new FakeSftpProvider()
  const svc = new FileAccessService(freshSettings(), provider)
  await svc.applyConfig({ enabled: true })
  await svc.stop()
  assert.equal(provider.running(), false)
})
