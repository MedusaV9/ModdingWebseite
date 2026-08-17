import fs from 'node:fs'
import path from 'node:path'
import type { Store, Collection } from '../lib/jsonstore.ts'
import type { Blueprint, ConsoleLine, GameServer, QueryResult, ResourceSnapshot, ServerDockerSettings, ServerStatus } from '../types.ts'
import { BlueprintRegistry } from '../blueprints/registry.ts'
import { SteamCmdManager } from '../steam/steamcmd.ts'
import { ServerInstance } from './instance.ts'
import { removeInstallLeftovers } from './runtime.ts'
import { buildVars, coerceVariables } from './vars.ts'
import { runInstall } from '../install/pipeline.ts'
import { applyProperties, applyIni, applyJson, applyKeyValue } from '../lib/configfiles.ts'
import { applyYaml } from '../lib/yaml.ts'
import { applyToml } from '../lib/toml.ts'
import { substituteVars, slugify, nowIso, sleep } from '../lib/util.ts'
import { safeJoin } from '../lib/paths.ts'
import { isValidImageRef } from '../lib/docker.ts'
import type { DockerService } from '../services/docker.ts'

export interface ManagerHooks {
  onStatus: (server: GameServer, status: ServerStatus, prev: ServerStatus) => void
  onConsole: (serverId: string, line: ConsoleLine) => void
  onResources: (serverId: string, snap: ResourceSnapshot) => void
  onQuery: (serverId: string, result: QueryResult) => void
  /** Receives the full (already removed) server so consumers can still check per-user visibility. */
  onRemoved?: (server: GameServer) => void
}

export interface CreateServerInput {
  name: string
  blueprintId: string
  ownerId: string
  variables: Record<string, unknown>
  autoStart?: boolean
  startAfterInstall?: boolean
  tags?: string[]
  runtime?: string
  docker?: unknown
}

/** Validate + clamp per-server docker settings from untrusted input. */
export function cleanDockerSettings(input: unknown): { settings: ServerDockerSettings; problems: string[] } {
  const problems: string[] = []
  const settings: ServerDockerSettings = {}
  if (typeof input !== 'object' || input === null) return { settings, problems }
  const raw = input as Record<string, unknown>
  if (raw.image !== undefined && raw.image !== null && raw.image !== '') {
    const image = String(raw.image).trim()
    if (!isValidImageRef(image)) problems.push(`invalid docker image reference: ${image.slice(0, 80)}`)
    else settings.image = image
  } else {
    settings.image = null
  }
  if (raw.memoryMb !== undefined && raw.memoryMb !== null && raw.memoryMb !== '') {
    const n = Number(raw.memoryMb)
    if (!Number.isFinite(n)) problems.push('docker memory limit must be a number (MiB)')
    else settings.memoryMb = Math.round(Math.min(1024 * 1024, Math.max(128, n)))
  } else {
    settings.memoryMb = null
  }
  if (raw.cpus !== undefined && raw.cpus !== null && raw.cpus !== '') {
    const n = Number(raw.cpus)
    if (!Number.isFinite(n)) problems.push('docker cpu limit must be a number (cores)')
    else settings.cpus = Math.min(256, Math.max(0.1, Math.round(n * 100) / 100))
  } else {
    settings.cpus = null
  }
  settings.networkMode = raw.networkMode === 'host' ? 'host' : 'bridge'
  return { settings, problems }
}

/**
 * Throttle pull progress so a big image doesn't flood the console buffer.
 * Mirrors throttledProgress in runtime.ts (not exported there on purpose —
 * it is private to the spawn path).
 */
function throttledPullProgress(onLine: (line: string) => void): (line: string) => void {
  let lastTs = 0
  let suppressed = 0
  return (line: string) => {
    const now = Date.now()
    const important = /^(Pulling|Status|Digest|Download complete|Pull complete|Already exists)/.test(line)
    if (!important && now - lastTs < 750) {
      suppressed++
      return
    }
    if (suppressed > 0) {
      onLine(`docker: … (${suppressed} progress updates)`)
      suppressed = 0
    }
    lastTs = now
    onLine(`docker: ${line}`)
  }
}

export class ServerManager {
  readonly servers: Collection<GameServer>
  readonly instances = new Map<string, ServerInstance>()
  readonly serversRoot: string
  /**
   * Panel Steam account source for login-required steamcmd installs — wired
   * in app.ts to SteamLoginService.installAuth (kept as a provider so the
   * manager never sees credentials, only the name + a session check).
   */
  steamAuth: (() => { user: string | null; isLoggedIn: () => Promise<boolean> }) | null = null
  private shuttingDown = false
  private bootPromise: Promise<void> | null = null
  private autoStartTimers = new Set<ReturnType<typeof setTimeout>>()

  constructor(
    store: Store,
    readonly registry: BlueprintRegistry,
    readonly steam: SteamCmdManager,
    dataDir: string,
    private hooks: ManagerHooks,
    readonly docker: DockerService | null = null,
  ) {
    this.servers = store.collection<GameServer>('servers')
    this.serversRoot = path.join(dataDir, 'servers')
    fs.mkdirSync(this.serversRoot, { recursive: true })
  }

  // -------------------------------------------------------------------------
  dirOf(server: GameServer): string {
    return safeJoin(this.serversRoot, server.dirName)
  }

  instance(id: string): ServerInstance {
    const inst = this.instances.get(id)
    if (!inst) throw new Error(`server ${id} not found`)
    return inst
  }

  /**
   * Re-point cached instances at the latest blueprint after a custom blueprint
   * edit — otherwise changes (start command, stop strategy, rcon, …) would
   * silently only apply after a panel restart.
   */
  refreshBlueprint(blueprintId: string) {
    const bp = this.registry.get(blueprintId)
    if (!bp) return
    for (const inst of this.instances.values()) {
      if (inst.server.blueprintId === blueprintId) inst.blueprint = bp
    }
  }

  private makeInstance(server: GameServer): ServerInstance | null {
    const blueprint = this.registry.get(server.blueprintId)
    if (!blueprint) return null
    const inst = new ServerInstance(
      server,
      blueprint,
      this.dirOf(server),
      this.steam.dir,
      {
        onStatus: (instance, prev) => this.hooks.onStatus(instance.server, instance.status, prev),
        onConsole: (instance, line) => this.hooks.onConsole(instance.server.id, line),
        onResources: (instance, snap) => this.hooks.onResources(instance.server.id, snap),
        onQuery: (instance, result) => this.hooks.onQuery(instance.server.id, result),
      },
      this.docker,
    )
    this.instances.set(server.id, inst)
    return inst
  }

  boot(): void {
    for (const server of this.servers.all()) {
      const inst = this.makeInstance(server)
      if (!inst) {
        console.error(`[servers] blueprint ${server.blueprintId} missing for server "${server.name}" — server disabled`)
        continue
      }
      if (!server.installed) inst.setStatus('install_failed')
    }
    // Docker servers may still be running from before the panel restart —
    // re-adopt those containers first, then run the staggered auto-start for
    // everything that is actually down.
    this.bootPromise = this.reattachAndAutoStart()
      .catch((err) => console.error('[servers] boot reconciliation failed:', err))
      .finally(() => {
        this.bootPromise = null
      })
  }

  private async reattachAndAutoStart(): Promise<void> {
    // A panel crash mid-install can leave a root install container running —
    // no install survives a restart, so anything with the label is stale.
    if (this.docker) {
      await this.docker
        .info()
        .then((info) => (info.available ? removeInstallLeftovers(this.docker!.client) : undefined))
        .catch(() => {})
    }
    await Promise.allSettled(
      [...this.instances.values()]
        .filter((inst) => inst.runtime === 'docker' && inst.server.installed)
        .map((inst) => inst.tryReattachDocker()),
    )
    if (this.shuttingDown) return
    let delay = 1000
    for (const inst of this.instances.values()) {
      if (inst.server.autoStart && inst.server.installed && !inst.server.suspended && !inst.active) {
        const timer = setTimeout(() => {
          this.autoStartTimers.delete(timer)
          if (inst.active || this.shuttingDown) return
          inst.pushLine('system', 'Auto-starting on panel boot.')
          inst.start().catch((err) => inst.pushLine('system', `Auto-start failed: ${(err as Error).message}`))
        }, delay)
        timer.unref?.()
        this.autoStartTimers.add(timer)
        delay += 2000
      }
    }
  }

  async shutdownAll(): Promise<void> {
    this.shuttingDown = true
    for (const timer of this.autoStartTimers) clearTimeout(timer)
    this.autoStartTimers.clear()
    for (const inst of this.instances.values()) inst.installController?.abort()
    // A Docker adoption already in flight must finish before we enumerate
    // handles to shut down; otherwise it can attach after shutdownAll returns.
    await this.bootPromise?.catch(() => {})
    await Promise.allSettled([...this.instances.values()].map((inst) => inst.shutdown()))
  }

  // -------------------------------------------------------------------------
  // Create / install / delete
  // -------------------------------------------------------------------------
  /** Throws with a human-readable reason when the docker runtime cannot be used right now. */
  async assertDockerUsable(): Promise<void> {
    if (!this.docker) throw new Error('docker support is not initialised')
    const info = await this.docker.info()
    if (!info.available) throw new Error(`docker daemon not reachable at ${info.socketPath}${info.error ? ` (${info.error})` : ''}`)
  }

  async create(input: CreateServerInput): Promise<{ server?: GameServer; problems: string[] }> {
    const blueprint = this.registry.get(input.blueprintId)
    if (!blueprint) return { problems: [`blueprint ${input.blueprintId} not found`] }

    const runtime = input.runtime === 'docker' ? 'docker' : 'process'
    let dockerSettings: ServerDockerSettings | undefined
    if (runtime === 'docker') {
      // Containers are Linux regardless of the host OS (Docker Desktop runs a
      // Linux VM), so the blueprint must support Linux — not the host platform.
      if (!blueprint.platforms.includes('linux'))
        return { problems: [`blueprint ${blueprint.name} has no Linux support — required for the docker runtime`] }
      try {
        await this.assertDockerUsable()
      } catch (err) {
        return { problems: [(err as Error).message] }
      }
      const { settings, problems: dockerProblems } = cleanDockerSettings(input.docker)
      if (dockerProblems.length > 0) return { problems: dockerProblems }
      if (!settings.image && !blueprint.docker?.image)
        return { problems: [`blueprint ${blueprint.name} has no default docker image — choose one explicitly`] }
      dockerSettings = settings
    } else if (!blueprint.platforms.includes(process.platform as Blueprint['platforms'][number])) {
      return { problems: [`blueprint ${blueprint.name} does not support this host platform (${process.platform})`] }
    }

    const name = String(input.name ?? '').trim()
    if (name.length < 1 || name.length > 60) return { problems: ['server name must be 1-60 characters'] }

    const { values, problems } = coerceVariables(blueprint, input.variables ?? {})
    if (problems.length > 0) return { problems }

    const portProblems = this.portAllocationProblems(blueprint, values)
    if (portProblems.length > 0) return { problems: portProblems }

    const id = crypto.randomUUID()
    const dirName = `${slugify(name)}-${id.slice(0, 8)}`
    const server = this.servers.insert({
      id,
      name,
      blueprintId: blueprint.id,
      ownerId: input.ownerId,
      createdAt: nowIso(),
      dirName,
      variables: values,
      tags: (input.tags ?? []).slice(0, 10).map((t) => String(t).slice(0, 24)),
      autoStart: Boolean(input.autoStart),
      restartPolicy: { enabled: true, maxRetries: 3, backoffS: 10 },
      installed: false,
      installedAt: null,
      memoryLimitMb: typeof values.MEMORY_MB === 'number' ? (values.MEMORY_MB as number) : null,
      runtime,
      ...(dockerSettings ? { docker: dockerSettings } : {}),
    })
    const inst = this.makeInstance(server)!
    inst.installPromise = this.runInstallFlow(inst, Boolean(input.startAfterInstall))
    return { server, problems: [] }
  }

  /**
   * Reject when a declared port collides with a port already allocated to
   * another server (running or not) — double allocations are almost always a
   * mistake and fail confusingly at start time.
   */
  private portAllocationProblems(blueprint: Blueprint, values: Record<string, string | number | boolean>): string[] {
    const wanted = (blueprint.ports ?? [])
      .map((p) => Number(values[p.variable]))
      .filter((n) => Number.isFinite(n) && n > 0)
    for (const other of this.instances.values()) {
      for (const op of other.ports) {
        if (wanted.includes(op.port)) return [`port ${op.port} is already allocated to "${other.server.name}"`]
      }
    }
    return []
  }

  /**
   * Duplicate an existing (stopped) server: same blueprint and settings,
   * fresh id/directory. With copyFiles the source directory is copied as-is
   * (minus panel metadata) and the clone is immediately startable; without,
   * the clone runs a fresh blueprint install like a newly created server.
   */
  clone(
    sourceId: string,
    newName: string,
    opts: { copyFiles: boolean; variables?: Record<string, unknown> },
  ): { server?: GameServer; problems: string[] } {
    const source = this.servers.get(sourceId)
    const sourceInst = this.instances.get(sourceId)
    if (!source || !sourceInst) return { problems: [`server ${sourceId} not found`] }
    if (!['offline', 'crashed', 'install_failed'].includes(sourceInst.status))
      return { problems: ['server must be stopped to clone'] }
    const blueprint = this.registry.get(source.blueprintId)
    if (!blueprint) return { problems: [`blueprint ${source.blueprintId} not found`] }
    const name = String(newName ?? '').trim()
    if (name.length < 1 || name.length > 60) return { problems: ['server name must be 1-60 characters'] }

    const { values, problems } = coerceVariables(blueprint, { ...source.variables, ...(opts.variables ?? {}) })
    if (problems.length > 0) return { problems }

    const portProblems = this.portAllocationProblems(blueprint, values)
    if (portProblems.length > 0) return { problems: portProblems }

    const id = crypto.randomUUID()
    const dirName = `${slugify(name)}-${id.slice(0, 8)}`
    const server = this.servers.insert({
      id,
      name,
      blueprintId: source.blueprintId,
      ownerId: source.ownerId,
      createdAt: nowIso(),
      dirName,
      variables: values,
      tags: [...source.tags],
      notes: source.notes,
      // Deliberate: two auto-starting copies of the same server is rarely intended.
      autoStart: false,
      restartPolicy: { ...source.restartPolicy },
      startCommandOverride: source.startCommandOverride ?? null,
      steamAutoUpdate: Boolean(source.steamAutoUpdate),
      useSteamLogin: Boolean(source.useSteamLogin),
      installed: opts.copyFiles,
      installedAt: opts.copyFiles ? nowIso() : null,
      memoryLimitMb: typeof values.MEMORY_MB === 'number' ? (values.MEMORY_MB as number) : (source.memoryLimitMb ?? null),
      runtime: source.runtime ?? 'process',
      ...(source.docker ? { docker: { ...source.docker } } : {}),
    })
    if (opts.copyFiles) {
      fs.cpSync(this.dirOf(source), this.dirOf(server), {
        recursive: true,
        // Panel metadata (console logs, …) belongs to the source server only.
        filter: (src) => path.basename(src) !== '.between',
      })
    }
    const inst = this.makeInstance(server)!
    if (opts.copyFiles) {
      // Copied config files still carry the source values (ports!) — re-sync.
      this.syncConfigFiles(id)
      inst.pushLine('system', `Cloned from "${source.name}" (files copied).`)
    } else {
      inst.pushLine('system', `Cloned from "${source.name}" — running a fresh install.`)
      inst.installPromise = this.runInstallFlow(inst, false)
    }
    return { server, problems: [] }
  }

  private async runInstallFlow(inst: ServerInstance, startAfter: boolean): Promise<void> {
    const { server, blueprint } = inst
    inst.installError = null
    inst.setStatus('installing')
    const controller = new AbortController()
    inst.installController = controller
    try {
      await runInstall({
        blueprint,
        serverDir: inst.serverDir,
        vars: buildVars(server, blueprint, { serverDir: inst.serverDir, steamcmdDir: this.steam.dir }),
        steam: this.steam,
        registry: this.registry,
        signal: controller.signal,
        docker: this.docker,
        steamAuth: this.steamAuth?.(),
        useSteamLogin: Boolean(server.useSteamLogin),
        onLine: (line) => inst.pushLine('install', line),
      })
      // The server may have been deleted while installing — never resurrect it.
      if (controller.signal.aborted || !this.servers.get(server.id)) return
      this.servers.update(server.id, { installed: true, installedAt: nowIso() })
      server.installed = true
      this.syncConfigFiles(server.id)
      inst.setStatus('offline')
      inst.pushLine('system', 'Installation complete. Server is ready to start.')
      if (startAfter) {
        await inst.start()
      }
    } catch (err) {
      if (controller.signal.aborted || !this.servers.get(server.id)) return
      inst.installError = (err as Error).message
      inst.pushLine('system', `Installation failed: ${(err as Error).message}`)
      inst.setStatus('install_failed')
    } finally {
      if (inst.installController === controller) inst.installController = null
      inst.installPromise = null
    }
  }

  async reinstall(id: string): Promise<void> {
    const inst = this.instance(id)
    if (inst.installController) throw new Error('an install is already running for this server')
    if (inst.active) await inst.stop()
    this.servers.update(id, { installed: false })
    inst.server.installed = false
    const flow = this.runInstallFlow(inst, false)
    inst.installPromise = flow
    await flow
  }

  /** Re-run only the steamcmd steps (game update) without touching other files. */
  async steamUpdate(id: string): Promise<void> {
    const inst = this.instance(id)
    const steps = inst.blueprint.install.filter((s) => s.type === 'steamcmd')
    if (steps.length === 0) throw new Error('this server is not installed via SteamCMD')
    if (inst.active) throw new Error('stop the server before updating')
    if (inst.installController) throw new Error('an install is already running for this server')
    inst.setStatus('updating')
    const controller = new AbortController()
    inst.installController = controller
    try {
      await runInstall({
        blueprint: { ...inst.blueprint, install: steps },
        serverDir: inst.serverDir,
        // Installs always run on the host — host paths, not container paths.
        vars: inst.hostVars,
        steam: this.steam,
        registry: this.registry,
        signal: controller.signal,
        docker: this.docker,
        steamAuth: this.steamAuth?.(),
        useSteamLogin: Boolean(inst.server.useSteamLogin),
        onLine: (line) => inst.pushLine('install', line),
      })
      inst.pushLine('system', 'Game update finished.')
      inst.setStatus('offline')
    } catch (err) {
      if (!this.servers.get(id)) return
      inst.pushLine('system', `Game update failed: ${(err as Error).message}`)
      inst.setStatus('offline')
      throw err
    } finally {
      if (inst.installController === controller) inst.installController = null
    }
  }

  /**
   * Pull/refresh the server's container image on demand (docker runtime only).
   * A pull never touches the workload: a running container keeps the image it
   * was created from, so the fresh image only takes effect on the NEXT
   * container start — the status is deliberately left alone.
   */
  async pullDockerImage(id: string): Promise<void> {
    const inst = this.instance(id)
    if (inst.runtime !== 'docker') throw new Error('this server does not use the docker runtime')
    if (!this.docker) throw new Error('docker support is not initialised')
    const image = inst.dockerImage
    if (!image) throw new Error('no docker image configured — set one in Settings → Runtime')
    if (inst.installController) throw new Error('an install or update is already running for this server')
    // Claim installController synchronously: the existing abort paths (server
    // delete, panel shutdown) and the install/update concurrency guards then
    // cover the pull without extra wiring.
    const controller = new AbortController()
    inst.installController = controller
    // The daemon reports the outcome in its final global status line; track it
    // in a mutable box because the assignment happens inside the callback.
    const outcome = { value: null as 'updated' | 'current' | null }
    const flow = (async () => {
      await this.assertDockerUsable()
      inst.pushLine('install', `Pulling image ${image}...`)
      const progress = throttledPullProgress((line) => inst.pushLine('install', line))
      await this.docker!.client.pullImage(
        image,
        (line) => {
          if (line.startsWith('Status: Downloaded newer image')) outcome.value = 'updated'
          else if (line.startsWith('Status: Image is up to date')) outcome.value = 'current'
          progress(line)
        },
        controller.signal,
      )
      inst.pushLine('install', outcome.value === 'current' ? `Image ${image} is up to date.` : `Image ${image} updated.`)
      if (inst.active) inst.pushLine('install', 'The running server keeps its current image — the new one applies on the next start.')
    })()
    // Expose the flow so remove() can wait for the pull to unwind after abort.
    inst.installPromise = flow
    try {
      await flow
    } catch (err) {
      if (controller.signal.aborted || !this.servers.get(id)) return
      inst.pushLine('install', `Image pull failed: ${(err as Error).message}`)
      throw err
    } finally {
      if (inst.installController === controller) inst.installController = null
      if (inst.installPromise === flow) inst.installPromise = null
    }
  }

  async remove(id: string, keepFiles = false): Promise<void> {
    const inst = this.instances.get(id)
    if (inst?.active) await inst.kill()
    // Abort an in-flight install and wait for it to unwind, so its child
    // processes/downloads cannot recreate the directory after deletion.
    if (inst?.installController) {
      const flow = inst.installPromise
      inst.installController.abort()
      if (flow) await Promise.race([flow.catch(() => undefined), sleep(15_000)])
    }
    // Cancel any pending auto-restart/query timers so a crashed instance can't
    // resurrect itself after removal.
    inst?.dispose()
    // Containers (running or stopped husks) must not outlive the server.
    if (inst?.runtime === 'docker') await inst.removeDockerArtifacts()
    const server = this.servers.get(id)
    this.instances.delete(id)
    this.servers.remove(id)
    if (server && !keepFiles) {
      const dir = this.dirOf(server)
      if (dir.startsWith(this.serversRoot)) fs.rmSync(dir, { recursive: true, force: true })
    }
    if (server) this.hooks.onRemoved?.(server)
  }

  // -------------------------------------------------------------------------
  // Power / commands
  // -------------------------------------------------------------------------
  async power(id: string, action: 'start' | 'stop' | 'restart' | 'kill'): Promise<void> {
    const inst = this.instance(id)
    // A schedule or auto-restart racing with panel shutdown must never spawn
    // a new process that nothing would clean up afterwards.
    if (this.shuttingDown && (action === 'start' || action === 'restart')) throw new Error('panel is shutting down')
    switch (action) {
      case 'start': {
        const conflicts = this.portConflicts(inst)
        if (conflicts.length > 0) throw new Error(`port conflict: ${conflicts.join(', ')}`)
        await this.autoUpdateBeforeStart(inst)
        inst.resetCrashCounter()
        await inst.start()
        break
      }
      case 'stop':
        await inst.stop()
        break
      case 'restart': {
        const conflicts = this.portConflicts(inst)
        if (conflicts.length > 0 && !inst.active) throw new Error(`port conflict: ${conflicts.join(', ')}`)
        await inst.restart()
        break
      }
      case 'kill':
        await inst.kill()
        break
    }
  }

  /**
   * "Auto-update before start": runs the SteamCMD update (same flow as the
   * manual update action, status transitions included) before a panel- or
   * schedule-initiated start. Update failures never block the start —
   * availability beats freshness. The crash auto-restart path in instance.ts
   * bypasses this on purpose to stay fast.
   */
  private async autoUpdateBeforeStart(inst: ServerInstance): Promise<void> {
    if (!inst.server.steamAutoUpdate) return
    if (!inst.blueprint.install.some((s) => s.type === 'steamcmd')) return
    if (inst.status !== 'offline' && inst.status !== 'crashed') return
    // An install/update already in flight owns the instance — never double-run.
    if (inst.active || inst.installController) return
    inst.pushLine('system', 'Auto-update before start: running SteamCMD update...')
    try {
      await this.steamUpdate(inst.server.id)
    } catch (err) {
      inst.pushLine('system', `Auto-update failed: ${(err as Error).message} — starting anyway.`)
    }
  }

  sendCommand(id: string, command: string): void {
    this.instance(id).sendCommand(command)
  }

  private portConflicts(inst: ServerInstance): string[] {
    const mine = inst.ports
    const conflicts: string[] = []
    for (const other of this.instances.values()) {
      if (other === inst) continue
      if (!other.active) continue
      for (const otherPort of other.ports) {
        for (const port of mine) {
          if (port.port === otherPort.port) {
            conflicts.push(`port ${port.port} is in use by "${other.server.name}"`)
          }
        }
      }
    }
    return conflicts
  }

  // -------------------------------------------------------------------------
  // Variables + config sync
  // -------------------------------------------------------------------------
  setVariables(id: string, input: Record<string, unknown>): { problems: string[] } {
    const inst = this.instance(id)
    const { values, problems } = coerceVariables(inst.blueprint, { ...inst.server.variables, ...input })
    if (problems.length > 0) return { problems }
    this.servers.update(id, { variables: values })
    inst.server.variables = values
    if (typeof values.MEMORY_MB === 'number') {
      this.servers.update(id, { memoryLimitMb: values.MEMORY_MB as number })
      inst.server.memoryLimitMb = values.MEMORY_MB as number
    }
    this.syncConfigFiles(id)
    inst.pushLine('system', 'Variables updated. Config files synced — restart the server to apply.')
    return { problems: [] }
  }

  syncConfigFiles(id: string): void {
    const inst = this.instance(id)
    const specs = inst.blueprint.configFiles ?? []
    const vars = inst.vars
    for (const spec of specs) {
      try {
        const file = safeJoin(inst.serverDir, substituteVars(spec.path, vars))
        if (spec.template) {
          fs.mkdirSync(path.dirname(file), { recursive: true })
          fs.writeFileSync(file, substituteVars(spec.template, vars))
          continue
        }
        if (!spec.mappings || !fs.existsSync(file)) continue
        const updates: Record<string, string> = {}
        for (const [varKey, configKey] of Object.entries(spec.mappings)) {
          if (varKey in vars) updates[configKey] = String(vars[varKey])
        }
        const text = fs.readFileSync(file, 'utf8')
        let next = text
        if (spec.format === 'properties') next = applyProperties(text, updates)
        else if (spec.format === 'ini') next = applyIni(text, updates)
        else if (spec.format === 'json') next = applyJson(text, updates)
        else if (spec.format === 'keyvalue') next = applyKeyValue(text, updates)
        else if (spec.format === 'yaml') next = applyYaml(text, updates)
        else if (spec.format === 'toml') next = applyToml(text, updates)
        if (next !== text) fs.writeFileSync(file, next)
      } catch (err) {
        inst.pushLine('system', `Config sync failed for ${spec.path}: ${(err as Error).message}`)
      }
    }
  }

  // -------------------------------------------------------------------------
  updateServer(
    id: string,
    patch: Partial<
      Pick<
        GameServer,
        | 'name'
        | 'tags'
        | 'notes'
        | 'autoStart'
        | 'restartPolicy'
        | 'startCommandOverride'
        | 'memoryLimitMb'
        | 'backupRetention'
        | 'suspended'
        | 'steamAutoUpdate'
        | 'useSteamLogin'
        | 'runtime'
        | 'docker'
      >
    >,
  ): GameServer {
    const inst = this.instance(id)
    const clean: Partial<GameServer> = {}
    if (patch.runtime !== undefined) {
      const runtime = patch.runtime === 'docker' ? 'docker' : 'process'
      if (runtime !== inst.runtime) {
        if (inst.active) throw new Error('stop the server before switching its runtime')
        if (runtime === 'docker') {
          if (!this.docker?.lastInfo?.available)
            throw new Error(`docker daemon not reachable${this.docker?.lastInfo?.error ? ` (${this.docker.lastInfo.error})` : ''}`)
          if (!inst.blueprint.platforms.includes('linux'))
            throw new Error('this blueprint has no Linux support — required for the docker runtime')
        }
      }
      clean.runtime = runtime
    }
    if (patch.docker !== undefined) {
      const { settings, problems } = cleanDockerSettings(patch.docker)
      if (problems.length > 0) throw new Error(problems.join('; '))
      const effectiveRuntime = clean.runtime ?? inst.runtime
      if (effectiveRuntime === 'docker' && !settings.image && !inst.blueprint.docker?.image)
        throw new Error('this blueprint has no default docker image — set one explicitly')
      clean.docker = settings
    }
    if (patch.name !== undefined) {
      const name = String(patch.name).trim()
      if (name.length < 1 || name.length > 60) throw new Error('server name must be 1-60 characters')
      clean.name = name
    }
    if (patch.tags !== undefined) clean.tags = patch.tags.slice(0, 10).map((t) => String(t).slice(0, 24))
    if (patch.notes !== undefined) clean.notes = String(patch.notes).slice(0, 2000)
    if (patch.autoStart !== undefined) clean.autoStart = Boolean(patch.autoStart)
    if (patch.steamAutoUpdate !== undefined) clean.steamAutoUpdate = Boolean(patch.steamAutoUpdate)
    if (patch.useSteamLogin !== undefined) clean.useSteamLogin = Boolean(patch.useSteamLogin)
    if (patch.suspended !== undefined) clean.suspended = Boolean(patch.suspended)
    if (patch.memoryLimitMb !== undefined) {
      // A non-numeric value must never persist as NaN (breaks the gauge + JSON).
      const n = Number(patch.memoryLimitMb)
      clean.memoryLimitMb = patch.memoryLimitMb === null || !Number.isFinite(n) ? null : Math.max(64, n)
    }
    if (patch.backupRetention !== undefined) {
      // "Keep last N unlocked backups": null = panel default, 0 = unlimited.
      const v = patch.backupRetention
      if (v === null) clean.backupRetention = null
      else if (typeof v === 'number' && Number.isInteger(v) && v >= 0 && v <= 50) clean.backupRetention = v
      else throw new Error('backupRetention must be an integer between 0 and 50 (or null for the panel default)')
    }
    if (patch.startCommandOverride !== undefined)
      clean.startCommandOverride = patch.startCommandOverride ? String(patch.startCommandOverride).slice(0, 1000) : null
    if (patch.restartPolicy !== undefined) {
      clean.restartPolicy = {
        enabled: Boolean(patch.restartPolicy.enabled),
        maxRetries: Math.max(0, Math.min(20, Number(patch.restartPolicy.maxRetries ?? 3))),
        backoffS: Math.max(1, Math.min(600, Number(patch.restartPolicy.backoffS ?? 10))),
      }
    }
    const updated = this.servers.update(id, clean)!
    Object.assign(inst.server, clean)
    return updated
  }
}
