/**
 * One running (or stopped) game server: lifecycle, console ring buffer, ready
 * detection, graceful stop chains, crash detection with auto-restart +
 * circuit breaker, resource sampling and game queries. Runtime-agnostic —
 * the workload runs either as a host process or a docker container behind
 * the RuntimeHandle abstraction (see runtime.ts).
 */
import fs from 'node:fs'
import path from 'node:path'
import type { Blueprint, ConsoleLine, GameServer, QueryResult, ResourceSnapshot, ServerStatus } from '../types.ts'
import { tokenize } from '../lib/shellwords.ts'
import { sanitizeLine, substituteVars } from '../lib/util.ts'
import { RingBuffer } from '../lib/ringbuffer.ts'
import { rconExec } from '../lib/rcon.ts'
import { queryMinecraft } from '../query/minecraft.ts'
import { querySource, querySourcePlayers } from '../query/source.ts'
import { buildVars } from './vars.ts'
import {
  CONTAINER_MOUNT,
  reattachDockerHandle,
  removeContainersForServer,
  spawnDockerHandle,
  spawnProcessHandle,
  type RuntimeEvents,
  type RuntimeHandle,
} from './runtime.ts'
import type { DockerService } from '../services/docker.ts'

const CONSOLE_BUFFER_LINES = 2000
const RESOURCE_BUFFER = 360 // ~15 min at 2.5s
const CRASH_WINDOW_MS = 5 * 60 * 1000
const READY_TIMEOUT_MS = 180_000
const MAX_PARTIAL_LINE = 64 * 1024
const LOG_IDLE_CLOSE_MS = 10_000

export interface InstanceHooks {
  onStatus: (instance: ServerInstance, previous: ServerStatus) => void
  onConsole: (instance: ServerInstance, line: ConsoleLine) => void
  onResources: (instance: ServerInstance, snap: ResourceSnapshot) => void
  onQuery: (instance: ServerInstance, result: QueryResult) => void
}

export class ServerInstance {
  status: ServerStatus = 'offline'
  handle: RuntimeHandle | null = null
  consoleBuffer: ConsoleLine[] = []
  /**
   * Recent resource samples. Deliberately NOT cleared on exit/restart: the
   * ring lives as long as the instance (i.e. until server deletion or panel
   * shutdown), so charts can be seeded across game-server restarts.
   */
  readonly resources = new RingBuffer<ResourceSnapshot>(RESOURCE_BUFFER)
  lastQuery: QueryResult | null = null
  startedAt: number | null = null
  crashTimestamps: number[] = []
  installError: string | null = null
  /** Set while an install/update flow is running; aborting kills its children. */
  installController: AbortController | null = null
  installPromise: Promise<void> | null = null

  private sampler: ReturnType<typeof setInterval> | null = null
  private queryTimer: ReturnType<typeof setInterval> | null = null
  private initialQueryTimer: ReturnType<typeof setTimeout> | null = null
  private refreshQueryTimer: ReturnType<typeof setTimeout> | null = null
  private pollQuery: (() => Promise<void>) | null = null
  private readyTimer: ReturnType<typeof setTimeout> | null = null
  private restartTimer: ReturnType<typeof setTimeout> | null = null
  private sampleInFlight = false
  private queryInFlight = false
  private samplingGeneration = 0
  private queryGeneration = 0
  private lastCpuMs = 0
  private lastSampleTs = 0
  private stopRequested = false
  private logStream: fs.WriteStream | null = null
  private logIdleTimer: ReturnType<typeof setTimeout> | null = null
  private logBackpressured = false
  private droppedLogLines = 0
  private lineSeq = 0
  /** Ready-marker matcher, compiled once per start (see armReadyDetection). */
  private readyRe: RegExp | null = null
  private partial: Record<'stdout' | 'stderr', string> = { stdout: '', stderr: '' }
  private exitWaiters = new Set<() => void>()
  /** Aborts a docker spawn that is still pulling/creating (delete during start). */
  private startAbort: AbortController | null = null

  constructor(
    public server: GameServer,
    public blueprint: Blueprint,
    public serverDir: string,
    private steamcmdDir: string,
    private hooks: InstanceHooks,
    private docker: DockerService | null = null,
  ) {
    this.status = server.installed ? 'offline' : 'installing'
  }

  // -------------------------------------------------------------------------
  // Console
  // -------------------------------------------------------------------------
  pushLine(stream: ConsoleLine['stream'], raw: string) {
    const line: ConsoleLine = { ts: Date.now(), stream, line: sanitizeLine(raw), seq: ++this.lineSeq }
    this.consoleBuffer.push(line)
    if (this.consoleBuffer.length > CONSOLE_BUFFER_LINES) this.consoleBuffer.splice(0, this.consoleBuffer.length - CONSOLE_BUFFER_LINES)
    this.hooks.onConsole(this, line)
    this.appendLog(line)
  }

  private appendLog(line: ConsoleLine) {
    try {
      if (!this.logStream) {
        const logDir = path.join(this.serverDir, '.between', 'logs')
        fs.mkdirSync(logDir, { recursive: true })
        const file = path.join(logDir, `console-${new Date().toISOString().slice(0, 10)}.log`)
        const stream = fs.createWriteStream(file, { flags: 'a' })
        // Write-stream failures are asynchronous and cannot be caught by this
        // method's try/catch. Without an error listener, ENOSPC/EACCES crashes
        // the whole panel.
        stream.on('error', (err) => {
          if (this.logStream === stream) {
            this.logStream = null
            this.logBackpressured = false
            this.droppedLogLines = 0
          }
          console.error(`[server:${this.server.id}] console log write failed:`, err.message)
        })
        stream.on('drain', () => {
          if (this.logStream !== stream) return
          this.logBackpressured = false
          const dropped = this.droppedLogLines
          this.droppedLogLines = 0
          if (dropped > 0) {
            const summary = `${new Date().toISOString()} [system] ${dropped} log lines dropped due to disk backpressure\n`
            if (!stream.write(summary)) this.logBackpressured = true
          }
        })
        this.logStream = stream
      }
      this.armLogIdleClose()
      if (this.logBackpressured) {
        this.droppedLogLines++
        return
      }
      if (!this.logStream.write(`${new Date(line.ts).toISOString()} [${line.stream}] ${line.line}\n`)) {
        this.logBackpressured = true
      }
    } catch (err) {
      console.error(`[server:${this.server.id}] console log write failed:`, (err as Error).message)
      /* logging must never break the server */
    }
  }

  private armLogIdleClose() {
    if (this.logIdleTimer) clearTimeout(this.logIdleTimer)
    this.logIdleTimer = setTimeout(() => this.closeLogStream(), LOG_IDLE_CLOSE_MS)
    this.logIdleTimer.unref?.()
  }

  private closeLogStream() {
    if (this.logIdleTimer) clearTimeout(this.logIdleTimer)
    this.logIdleTimer = null
    const stream = this.logStream
    this.logStream = null
    this.logBackpressured = false
    this.droppedLogLines = 0
    stream?.end()
  }

  setStatus(status: ServerStatus) {
    if (this.status === status) return
    const prev = this.status
    this.status = status
    this.hooks.onStatus(this, prev)
  }

  get uptimeS(): number {
    return this.startedAt ? Math.floor((Date.now() - this.startedAt) / 1000) : 0
  }

  /** Which runtime this server uses (docker only when configured AND compiled in). */
  get runtime(): 'process' | 'docker' {
    return this.server.runtime === 'docker' ? 'docker' : 'process'
  }

  /** True while a workload (process or container) is attached. */
  get active(): boolean {
    return this.handle !== null
  }

  /**
   * Variables as the *game* sees them: in docker mode the server directory is
   * mounted at CONTAINER_MOUNT, so SERVER_DIR must point there. Config files
   * are also read inside the container, so config templates use these too.
   */
  get vars(): Record<string, string | number | boolean> {
    const serverDir = this.runtime === 'docker' ? CONTAINER_MOUNT : this.serverDir
    return buildVars(this.server, this.blueprint, { serverDir, steamcmdDir: this.steamcmdDir })
  }

  /** Variables with host paths — for install pipelines, which always run on the host. */
  get hostVars(): Record<string, string | number | boolean> {
    return buildVars(this.server, this.blueprint, { serverDir: this.serverDir, steamcmdDir: this.steamcmdDir })
  }

  /** Port values used by this server, per blueprint port declarations. */
  get ports(): { name: string; port: number; protocol: string }[] {
    const vars = this.vars
    return (this.blueprint.ports ?? [])
      .map((p) => ({ name: p.name, port: Number(vars[p.variable]), protocol: p.protocol }))
      .filter((p) => Number.isFinite(p.port) && p.port > 0)
  }

  /** Effective docker image (server override, then blueprint default). */
  get dockerImage(): string | null {
    return this.server.docker?.image?.trim() || this.blueprint.docker?.image || null
  }

  // -------------------------------------------------------------------------
  // Start
  // -------------------------------------------------------------------------
  async start(): Promise<void> {
    if (this.handle) throw new Error('server is already running')
    if (!this.server.installed) throw new Error('server is not installed yet')
    if (this.server.suspended) throw new Error('server is suspended')
    if (this.status === 'installing' || this.status === 'updating') throw new Error(`cannot start while ${this.status}`)

    this.stopRequested = false
    if (this.restartTimer) {
      clearTimeout(this.restartTimer)
      this.restartTimer = null
    }

    const vars = this.vars
    const rawCommand = this.server.startCommandOverride?.trim() || this.blueprint.startCommand
    const command = substituteVars(rawCommand, vars)
    const argv = tokenize(command)
    if (argv.length === 0) throw new Error('empty start command')

    this.setStatus('starting')
    this.startedAt = Date.now()

    // A container can exit so fast that the daemon reports the exit before
    // the start call even returns — buffer such an exit until the handle is
    // installed, otherwise handleExit runs against a half-initialised
    // instance and the assignment below would resurrect a dead handle.
    let handleInstalled = false
    const pendingExits: { code: number | null; signal: string | null }[] = []
    const events: RuntimeEvents = {
      onData: (stream, chunk) => this.feedChunk(stream, chunk),
      onSystem: (line) => this.pushLine('system', line),
      onExit: (info) => {
        if (!handleInstalled) {
          pendingExits.push(info)
          return
        }
        this.handleExit(info.code, info.signal)
      },
    }

    try {
      if (this.runtime === 'docker') {
        this.handle = await this.startDocker(command, argv, vars, events)
      } else {
        this.pushLine('system', `Starting server: ${command}`)
        const env: Record<string, string> = { ...(process.env as Record<string, string>) }
        for (const [key, value] of Object.entries(vars)) env[key] = String(value)
        this.handle = spawnProcessHandle({ command, argv, cwd: this.serverDir, env, events })
      }
    } catch (err) {
      this.startedAt = null
      this.setStatus('crashed')
      this.pushLine('system', `Failed to start: ${(err as Error).message}`)
      throw err
    }

    this.armReadyDetection()
    this.startSampling()
    this.startQueryPolling()
    handleInstalled = true
    for (const exit of pendingExits) this.handleExit(exit.code, exit.signal)
  }

  private async startDocker(
    command: string,
    argv: string[],
    vars: Record<string, string | number | boolean>,
    events: RuntimeEvents,
  ): Promise<RuntimeHandle> {
    if (!this.docker) throw new Error('docker support is not initialised')
    const info = await this.docker.info()
    if (!info.available) throw new Error(`docker daemon not reachable (${info.error ?? 'unknown error'})`)
    const image = this.dockerImage
    if (!image) throw new Error('no docker image configured — set one in Settings → Runtime')

    this.pushLine('system', `Starting container (${image}): ${command}`)
    const env: Record<string, string> = {}
    for (const [key, value] of Object.entries(vars)) env[key] = String(value)

    const controller = new AbortController()
    this.startAbort = controller
    try {
      const handle = await spawnDockerHandle({
        client: this.docker.client,
        serverId: this.server.id,
        containerName: `between-${this.server.dirName}`.slice(0, 63),
        image,
        argv,
        env,
        hostDir: this.serverDir,
        ports: (this.blueprint.ports ?? [])
          .map((p) => ({ port: Number(vars[p.variable]), protocol: p.protocol }))
          .filter((p) => Number.isFinite(p.port) && p.port > 0),
        memoryMb: this.server.docker?.memoryMb ?? null,
        cpus: this.server.docker?.cpus ?? null,
        networkMode: this.server.docker?.networkMode === 'host' ? 'host' : 'bridge',
        signal: controller.signal,
        events,
      })
      // Deleted/killed while the spawn was in flight (e.g. right after the
      // container started): never install the handle — tear the container
      // down instead, so nothing outlives the abort.
      if (controller.signal.aborted) {
        handle.detach()
        await removeContainersForServer(this.docker.client, this.server.id).catch(() => {})
        throw new Error('start aborted')
      }
      return handle
    } finally {
      this.startAbort = null
    }
  }

  /**
   * Re-adopt a container that survived a panel restart (docker runtime only).
   * Returns true when a running container was found and adopted.
   */
  async tryReattachDocker(): Promise<boolean> {
    if (this.runtime !== 'docker' || !this.docker || this.handle) return false
    const info = await this.docker.info()
    if (!info.available) return false
    try {
      // Same guard as start(): the container can exit during adoption (or
      // while the console backlog is fetched below) — buffer the exit until
      // the handle is installed so the instance never ends up "running"
      // with a dead handle attached.
      let handleInstalled = false
      const pendingExits: { code: number | null; signal: string | null }[] = []
      const events: RuntimeEvents = {
        onData: (stream, chunk) => this.feedChunk(stream, chunk),
        onSystem: (line) => this.pushLine('system', line),
        onExit: (info) => {
          if (!handleInstalled) {
            pendingExits.push(info)
            return
          }
          this.handleExit(info.code, info.signal)
        },
      }
      const adopted = await reattachDockerHandle({ client: this.docker.client, serverId: this.server.id, events })
      if (!adopted) return false
      // Rehydrate recent console output so the terminal is not empty.
      try {
        const logs = await this.docker.client.containerLogs(adopted.handle.containerId!, 100)
        for (const entry of logs) {
          for (const line of entry.text.split(/\r?\n/)) {
            if (line.length > 0) this.pushLine(entry.stream, line)
          }
        }
      } catch {
        /* backlog is cosmetic */
      }
      this.handle = adopted.handle
      this.startedAt = adopted.startedAt
      this.stopRequested = false
      this.pushLine('system', `Re-attached to running container (${adopted.image}) — it survived the panel restart.`)
      this.setStatus('running')
      this.startSampling()
      this.startQueryPolling()
      handleInstalled = true
      for (const exit of pendingExits) this.handleExit(exit.code, exit.signal)
      return true
    } catch (err) {
      this.pushLine('system', `Container re-attach failed: ${(err as Error).message}`)
      return false
    }
  }

  /** Line assembly shared by both runtimes (chunk streams → console lines). */
  private feedChunk(stream: 'stdout' | 'stderr', chunk: string) {
    let buf = this.partial[stream] + chunk
    const lines = buf.split(/\r?\n/)
    buf = lines.pop() ?? ''
    // A workload that never emits newlines must not grow the accumulator
    // without bound — force-flush oversized partial lines.
    if (buf.length > MAX_PARTIAL_LINE) {
      lines.push(buf)
      buf = ''
    }
    this.partial[stream] = buf
    for (const line of lines) {
      if (line.length === 0) continue
      this.pushLine(stream, line)
      this.checkReady(line)
    }
  }

  private handleExit(code: number | null, signal: string | null) {
    const expected = this.stopRequested || this.status === 'stopping'
    this.cleanupAfterExit()
    this.pushLine('system', `Process exited with ${signal ? `signal ${signal}` : `code ${code}`}.`)
    if (expected || code === 0) {
      this.setStatus('offline')
    } else {
      this.setStatus('crashed')
      this.registerCrash()
    }
    for (const waiter of this.exitWaiters) waiter()
    this.exitWaiters.clear()
  }

  private armReadyDetection() {
    // Compile the ready regex once per start instead of on every console line
    // (a busy server emits thousands of lines/s — recompiling each time is pure
    // waste and, with a pathological pattern, a per-line CPU sink).
    this.readyRe = null
    if (this.blueprint.readyRegex) {
      try {
        this.readyRe = new RegExp(this.blueprint.readyRegex)
      } catch {
        /* invalid regex guarded at validation — fall back to the timeout */
      }
    }
    if (this.readyRe) {
      this.readyTimer = setTimeout(() => {
        this.readyTimer = null
        if (this.status === 'starting') {
          this.pushLine('system', 'Ready marker not seen yet — marking as running anyway.')
          this.setStatus('running')
        }
      }, READY_TIMEOUT_MS)
      this.readyTimer.unref?.()
    } else {
      this.readyTimer = setTimeout(() => {
        this.readyTimer = null
        if (this.status === 'starting' && this.handle) this.setStatus('running')
      }, 1500)
      this.readyTimer.unref?.()
    }
  }

  private checkReady(line: string) {
    if (this.status !== 'starting' || !this.readyRe) return
    if (this.readyRe.test(line)) {
      if (this.readyTimer) clearTimeout(this.readyTimer)
      this.readyTimer = null
      this.setStatus('running')
      this.pushLine('system', `Server is ready (took ${((Date.now() - (this.startedAt ?? Date.now())) / 1000).toFixed(1)}s).`)
    }
  }

  // -------------------------------------------------------------------------
  // Stop / kill / restart / command
  // -------------------------------------------------------------------------
  async stop(): Promise<void> {
    const handle = this.handle
    if (!handle) {
      this.setStatus('offline')
      return
    }
    this.stopRequested = true
    this.setStatus('stopping')

    const stop = this.blueprint.stop
    const timeoutS = stop.timeoutS ?? 30

    if (stop.type === 'command' && handle.stdinWritable) {
      this.pushLine('system', `Sending stop command: ${stop.command}`)
      handle.writeStdin(substituteVars(stop.command, this.vars) + '\n')
    } else if (stop.type === 'rcon') {
      const rcon = this.rconEndpoint()
      if (rcon) {
        this.pushLine('system', `Sending stop command via RCON: ${stop.command}`)
        try {
          await rconExec({ ...rcon, timeoutMs: 5000 }, substituteVars(stop.command, this.vars))
        } catch (err) {
          this.pushLine('system', `RCON stop failed (${(err as Error).message}) — sending SIGTERM instead.`)
          await handle.signal('SIGTERM')
        }
      } else {
        this.pushLine('system', 'RCON not configured — sending SIGTERM...')
        await handle.signal('SIGTERM')
      }
    } else {
      const signal = stop.type === 'signal' ? stop.signal : 'SIGTERM'
      this.pushLine('system', `Sending ${signal}...`)
      await handle.signal(signal)
    }

    const exited = await this.waitForExit(timeoutS * 1000)
    if (exited) return
    this.pushLine('system', `Still running after ${timeoutS}s — escalating to SIGTERM.`)
    await handle.signal('SIGTERM')
    if (await this.waitForExit(10_000)) return
    this.pushLine('system', 'Force killing.')
    await handle.signal('SIGKILL')
    await this.waitForExit(5_000)
  }

  async kill(): Promise<void> {
    this.startAbort?.abort()
    const handle = this.handle
    if (!handle) {
      this.setStatus('offline')
      return
    }
    this.stopRequested = true
    this.pushLine('system', 'Force killing.')
    await handle.signal('SIGKILL')
    await this.waitForExit(5_000)
  }

  async restart(): Promise<void> {
    if (this.handle) await this.stop()
    await this.start()
  }

  /**
   * RCON endpoint, if the blueprint declares one AND the password variable is
   * non-empty (srcds-family games ship with an empty password = RCON off).
   */
  private rconEndpoint(): { host: string; port: number; password: string } | null {
    const rcon = this.blueprint.rcon
    if (!rcon) return null
    const vars = this.vars
    const port = Number(vars[rcon.portVariable])
    const password = String(vars[rcon.passwordVariable] ?? '')
    if (!Number.isFinite(port) || port <= 0 || password.length === 0) return null
    return { host: '127.0.0.1', port, password }
  }

  /** Whether console commands are delivered via RCON instead of stdin. */
  get commandTransport(): 'rcon' | 'stdin' {
    return this.rconEndpoint() ? 'rcon' : 'stdin'
  }

  sendCommand(command: string): void {
    const handle = this.handle
    if (!handle) throw new Error('server is not running')
    const rcon = this.rconEndpoint()
    if (rcon) {
      // srcds-family games ignore stdin — deliver via RCON. Fire-and-forget:
      // the response is appended to the console when it arrives.
      this.pushLine('input', `> ${command}`)
      rconExec({ ...rcon, timeoutMs: 5000 }, command)
        .then((response) => {
          const lines = response.split(/\r?\n/).filter((l) => l.trim().length > 0)
          for (const line of lines.slice(0, 50)) this.pushLine('stdout', line)
          if (lines.length > 50) this.pushLine('system', `(RCON response truncated — ${lines.length - 50} more lines)`)
        })
        .catch((err) => this.pushLine('system', `RCON: ${(err as Error).message}`))
      this.refreshQuerySoon()
      return
    }
    if (!handle.stdinWritable) throw new Error('server is not running')
    this.pushLine('input', `> ${command}`)
    handle.writeStdin(command + '\n')
    this.refreshQuerySoon()
  }

  private waitForExit(ms: number): Promise<boolean> {
    return new Promise((resolve) => {
      if (!this.handle) return resolve(true)
      const timer = setTimeout(() => {
        this.exitWaiters.delete(onExit)
        resolve(false)
      }, ms)
      timer.unref?.()
      const onExit = () => {
        clearTimeout(timer)
        resolve(true)
      }
      this.exitWaiters.add(onExit)
    })
  }

  // -------------------------------------------------------------------------
  // Crash handling
  // -------------------------------------------------------------------------
  private registerCrash() {
    const now = Date.now()
    this.crashTimestamps.push(now)
    this.crashTimestamps = this.crashTimestamps.filter((t) => now - t < CRASH_WINDOW_MS)
    const policy = this.server.restartPolicy
    if (!policy?.enabled) return
    if (this.crashTimestamps.length > policy.maxRetries) {
      this.pushLine(
        'system',
        `Crash loop detected (${this.crashTimestamps.length} crashes in 5 min) — auto-restart disabled until manual start.`,
      )
      return
    }
    const delayS = Math.min(policy.backoffS * this.crashTimestamps.length, 300)
    this.pushLine('system', `Auto-restart in ${delayS}s (attempt ${this.crashTimestamps.length}/${policy.maxRetries})...`)
    this.restartTimer = setTimeout(() => {
      this.restartTimer = null
      if (this.status === 'crashed') {
        this.start().catch((err) => this.pushLine('system', `Auto-restart failed: ${(err as Error).message}`))
      }
    }, delayS * 1000)
    this.restartTimer.unref?.()
  }

  resetCrashCounter() {
    this.crashTimestamps = []
  }

  // -------------------------------------------------------------------------
  // Sampling / queries
  // -------------------------------------------------------------------------
  private startSampling() {
    const generation = ++this.samplingGeneration
    this.lastCpuMs = 0
    this.lastSampleTs = 0
    const interval = process.platform === 'win32' ? 5000 : 2500
    const sample = async () => {
      if (this.sampleInFlight) return
      this.sampleInFlight = true
      try {
        const handle = this.handle
        if (!handle) return
        const result = await handle.sample()
        if (generation !== this.samplingGeneration || this.handle !== handle) return
        if (!result) return
        const now = Date.now()
        let cpuPct = result.cpuPct ?? 0
        if (result.cpuPct === undefined && result.cpuMs !== undefined) {
          if (this.lastSampleTs > 0 && result.cpuMs >= this.lastCpuMs) {
            cpuPct = ((result.cpuMs - this.lastCpuMs) / (now - this.lastSampleTs)) * 100
          }
          this.lastCpuMs = result.cpuMs
          this.lastSampleTs = now
        }
        const snap: ResourceSnapshot = {
          ts: now,
          cpuPct: Math.round(cpuPct * 10) / 10,
          memBytes: result.memBytes,
          processes: result.processes,
          uptimeS: this.uptimeS,
        }
        this.resources.push(snap)
        this.hooks.onResources(this, snap)
      } catch {
        // Sampling is best-effort; a transient /proc or daemon failure must
        // not become an unhandled rejection from the interval callback.
      } finally {
        if (generation === this.samplingGeneration) this.sampleInFlight = false
      }
    }
    this.sampler = setInterval(() => void sample(), interval)
    this.sampler.unref?.()
  }

  private startQueryPolling() {
    const query = this.blueprint.query
    if (!query || query.type === 'none') return
    const generation = ++this.queryGeneration
    const poll = async () => {
      if (generation !== this.queryGeneration || this.status !== 'running' || this.queryInFlight) return
      this.queryInFlight = true
      try {
        const port = Number(this.vars[query.portVariable ?? 'SERVER_PORT'])
        if (!Number.isFinite(port)) return
        const result =
          query.type === 'minecraft' ? await queryMinecraft('127.0.0.1', port) : await querySource('127.0.0.1', port)
        // Minecraft delivers its player sample in the status response; Source
        // needs a second A2S_PLAYER round-trip. null = unknown, keep unset.
        if (query.type === 'source' && result.online) {
          const players = await querySourcePlayers('127.0.0.1', port)
          if (players) result.players = players
        }
        if (generation !== this.queryGeneration) return
        this.lastQuery = result
        this.hooks.onQuery(this, result)
      } catch {
        // Query transports are best-effort and run from timers. Keep a failed
        // poll contained so it cannot surface as an unhandled rejection.
      } finally {
        if (generation === this.queryGeneration) this.queryInFlight = false
      }
    }
    this.pollQuery = poll
    this.queryTimer = setInterval(() => void poll(), 30_000)
    this.queryTimer.unref?.()
    this.initialQueryTimer = setTimeout(() => {
      this.initialQueryTimer = null
      void poll()
    }, 8000)
    this.initialQueryTimer.unref?.()
  }

  /**
   * Schedule a one-shot query refresh shortly after a console command, so
   * player-affecting actions (kick/ban) show up without waiting for the next
   * 30s polling tick. Small delay gives the game time to apply the change.
   */
  refreshQuerySoon(delayMs = 1500) {
    if (!this.pollQuery) return
    if (this.refreshQueryTimer) clearTimeout(this.refreshQueryTimer)
    this.refreshQueryTimer = setTimeout(() => {
      this.refreshQueryTimer = null
      this.pollQuery?.().catch(() => {})
    }, delayMs)
    this.refreshQueryTimer.unref?.()
  }

  private cleanupAfterExit() {
    this.handle = null
    this.startedAt = null
    this.partial = { stdout: '', stderr: '' }
    if (this.sampler) clearInterval(this.sampler)
    if (this.queryTimer) clearInterval(this.queryTimer)
    if (this.initialQueryTimer) clearTimeout(this.initialQueryTimer)
    if (this.refreshQueryTimer) clearTimeout(this.refreshQueryTimer)
    if (this.readyTimer) clearTimeout(this.readyTimer)
    this.sampler = null
    this.queryTimer = null
    this.initialQueryTimer = null
    this.refreshQueryTimer = null
    this.pollQuery = null
    this.readyTimer = null
    this.samplingGeneration++
    this.queryGeneration++
    this.sampleInFlight = false
    this.queryInFlight = false
    this.lastQuery = null
    this.closeLogStream()
  }

  /**
   * Cancel every pending timer without needing a live workload. Used when a
   * server is deleted while offline/crashed so a queued auto-restart timer
   * cannot resurrect the instance (and, with keepFiles, spawn an untracked
   * process) after it has been removed from the manager.
   */
  dispose(): void {
    this.stopRequested = true
    this.startAbort?.abort()
    if (this.restartTimer) clearTimeout(this.restartTimer)
    if (this.sampler) clearInterval(this.sampler)
    if (this.queryTimer) clearInterval(this.queryTimer)
    if (this.initialQueryTimer) clearTimeout(this.initialQueryTimer)
    if (this.refreshQueryTimer) clearTimeout(this.refreshQueryTimer)
    if (this.readyTimer) clearTimeout(this.readyTimer)
    this.restartTimer = null
    this.sampler = null
    this.queryTimer = null
    this.initialQueryTimer = null
    this.refreshQueryTimer = null
    this.pollQuery = null
    this.readyTimer = null
    this.samplingGeneration++
    this.queryGeneration++
    this.sampleInFlight = false
    this.queryInFlight = false
    this.handle?.detach()
    this.handle = null
    this.closeLogStream()
  }

  /** Force-remove any containers belonging to this server (server deletion). */
  async removeDockerArtifacts(): Promise<void> {
    if (!this.docker) return
    const info = await this.docker.info()
    if (!info.available) return
    await removeContainersForServer(this.docker.client, this.server.id).catch(() => {})
  }

  /**
   * Called when the panel shuts down. Host processes are stopped gracefully
   * but quickly (they are our children and would die anyway); docker
   * containers are *detached* and keep running — they survive panel restarts
   * and are re-adopted on the next boot.
   */
  async shutdown(): Promise<void> {
    if (this.restartTimer) clearTimeout(this.restartTimer)
    const handle = this.handle
    if (!handle) return
    if (handle.kind === 'docker') {
      this.pushLine('system', 'Panel shutting down — container keeps running and will be re-adopted.')
      this.dispose()
      return
    }
    this.stopRequested = true
    const stop = this.blueprint.stop
    if (stop.type === 'command' && handle.stdinWritable) handle.writeStdin(substituteVars(stop.command, this.vars) + '\n')
    else await handle.signal(stop.type === 'signal' ? stop.signal : 'SIGTERM')
    if (!(await this.waitForExit(8000))) await handle.signal('SIGKILL')
  }
}
