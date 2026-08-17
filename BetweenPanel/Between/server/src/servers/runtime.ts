/**
 * Runtime abstraction: a started game server is a RuntimeHandle, either a
 * plain host process (classic Between) or a Docker container. The instance
 * lifecycle (console, ready detection, stop chains, crash handling) is
 * runtime-agnostic and lives in instance.ts; everything process/container
 * specific is behind this interface.
 */
import { spawn } from 'node:child_process'
import { killTree, sampleTree } from '../lib/proc.ts'
import { DockerClient, isValidImageRef, type DockerAttachment, type DockerStatsSample } from '../lib/docker.ts'

export type RuntimeKind = 'process' | 'docker'

export interface RuntimeSample {
  /** Direct percentage when the runtime computes it (docker); otherwise derived from cpuMs deltas. */
  cpuPct?: number
  /** Cumulative CPU time (host process trees). */
  cpuMs?: number
  memBytes: number
  processes: number
}

export interface RuntimeEvents {
  onData: (stream: 'stdout' | 'stderr', chunk: string) => void
  /** System messages produced while spawning (e.g. image pull progress). */
  onSystem: (line: string) => void
  /** Fired exactly once when the workload exits. */
  onExit: (info: { code: number | null; signal: string | null }) => void
}

export interface RuntimeHandle {
  readonly kind: RuntimeKind
  readonly pid?: number
  readonly containerId?: string
  readonly stdinWritable: boolean
  writeStdin(text: string): void
  signal(sig: 'SIGINT' | 'SIGTERM' | 'SIGKILL'): Promise<void>
  sample(): Promise<RuntimeSample | null>
  /**
   * Stop watching the workload without touching it. For processes this is a
   * no-op (children die with the panel anyway); for containers it detaches
   * streams and leaves the container running (it survives panel restarts).
   */
  detach(): void
}

// ---------------------------------------------------------------------------
// Host process runtime
// ---------------------------------------------------------------------------
export interface SpawnProcessOptions {
  command: string
  argv: string[]
  cwd: string
  env: Record<string, string>
  events: RuntimeEvents
}

export function spawnProcessHandle(opts: SpawnProcessOptions): RuntimeHandle {
  const useShell = process.platform === 'win32' && /\.(bat|cmd)(\s|$)/i.test(opts.argv[0])
  const child = useShell
    ? spawn(opts.command, { cwd: opts.cwd, env: opts.env, shell: true, stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true })
    : spawn(opts.argv[0], opts.argv.slice(1), {
        cwd: opts.cwd,
        env: opts.env,
        stdio: ['pipe', 'pipe', 'pipe'],
        detached: process.platform !== 'win32', // own process group → killable tree
        windowsHide: true,
      })

  let exited = false
  child.stdout?.on('data', (chunk: Buffer) => opts.events.onData('stdout', chunk.toString()))
  child.stderr?.on('data', (chunk: Buffer) => opts.events.onData('stderr', chunk.toString()))
  // Stream errors (especially stdin EPIPE during an exit race) are otherwise
  // unhandled EventEmitter errors and can crash the panel.
  child.stdin?.on('error', () => {})
  child.stdout?.on('error', (err) => opts.events.onSystem(`Process stdout error: ${err.message}`))
  child.stderr?.on('error', (err) => opts.events.onSystem(`Process stderr error: ${err.message}`))
  // `close` fires after stdout/stderr close; `exit` may run while trailing
  // output is still readable, causing instance cleanup to close/reopen logs.
  child.on('close', (code, signal) => {
    if (exited) return
    exited = true
    opts.events.onExit({ code, signal })
  })
  child.on('error', (err) => {
    opts.events.onSystem(`Process error: ${err.message}`)
    // 'exit' does not fire when the spawn itself failed (ENOENT etc.).
    if (!exited && child.pid === undefined) {
      exited = true
      opts.events.onExit({ code: -1, signal: null })
    }
  })

  return {
    kind: 'process',
    get pid() {
      return child.pid
    },
    get stdinWritable() {
      return !exited && Boolean(child.stdin?.writable && !child.stdin.destroyed)
    },
    writeStdin(text: string) {
      if (!exited && child.stdin?.writable && !child.stdin.destroyed) child.stdin.write(text)
    },
    async signal(sig) {
      if (child.pid) await killTree(child.pid, sig)
    },
    async sample() {
      if (!child.pid) return null
      const tree = await sampleTree(child.pid)
      if (!tree) return null
      return { cpuMs: tree.cpuMs, memBytes: tree.rssBytes, processes: tree.processes }
    },
    detach() {
      /* host processes die with the panel — nothing to detach */
    },
  }
}

// ---------------------------------------------------------------------------
// Docker container runtime
// ---------------------------------------------------------------------------
export const CONTAINER_MOUNT = '/data'
export const LABEL_SERVER_ID = 'between.server.id'
export const LABEL_PANEL = 'between.panel'
export const LABEL_INSTALL = 'between.install'

export interface SpawnDockerOptions {
  client: DockerClient
  serverId: string
  containerName: string
  image: string
  argv: string[]
  env: Record<string, string>
  hostDir: string
  ports: { port: number; protocol: 'tcp' | 'udp' | 'both' }[]
  memoryMb?: number | null
  cpus?: number | null
  networkMode: 'bridge' | 'host'
  signal?: AbortSignal
  events: RuntimeEvents
}

class DockerHandle implements RuntimeHandle {
  readonly kind = 'docker' as const
  private lastStats: DockerStatsSample | null = null
  private stopStats: (() => void) | null = null
  private waitAbort = new AbortController()
  private attachment: DockerAttachment | null = null
  private detached = false
  private exitFired = false

  constructor(
    private client: DockerClient,
    readonly containerId: string,
    private events: RuntimeEvents,
  ) {}

  /** Guards against a rewatch spin loop when the daemon keeps flapping. */
  private rewatchCount = 0

  /** Wire attach + wait + stats. Called once right after construction. */
  async watch(): Promise<void> {
    this.attachment = await this.client.attachContainer(this.containerId, {
      onData: (stream, chunk) => this.events.onData(stream, chunk.toString('utf8')),
      onClose: () => {
        /* exit is signalled by waitContainer, not by the attach stream */
      },
    })
    // detach() may have raced the attach above — don't leak its socket.
    if (this.detached) {
      this.cleanupStreams()
      return
    }
    this.stopStats = this.client.statsStream(this.containerId, (sample) => {
      this.lastStats = sample
    })
    this.installWait()
  }

  private installWait(): void {
    void this.client
      .waitContainer(this.containerId, this.waitAbort.signal)
      .then((code) => this.fireExit(code))
      .catch((err: Error) => this.onWaitError(err))
  }

  /**
   * The exit long-poll failed. A broken poll is NOT proof the game died — a
   * transient daemon/connection hiccup would otherwise kill a perfectly
   * healthy container. Inspect the container first: only treat it as an exit
   * when it is actually gone/stopped; if it is still running, re-attach and
   * keep watching (bounded, so a flapping daemon cannot spin forever).
   */
  private async onWaitError(err: Error): Promise<void> {
    if (this.detached || this.exitFired) return
    const running = await this.probeRunning()
    if (this.detached || this.exitFired) return
    if (running === false) {
      // Container is stopped or already removed → a real exit.
      this.fireExit(null)
      return
    }
    if (running === null || this.rewatchCount >= 5) {
      // Daemon unreachable (or it keeps flapping): stop guessing so the panel
      // doesn't show a zombie "running" server forever.
      this.events.onSystem(`Lost connection to the container: ${err.message}`)
      this.fireExit(null)
      return
    }
    // Still running — the event stream just dropped. Rebuild attach + stats +
    // wait so console I/O and metrics recover without killing the game.
    this.rewatchCount++
    this.events.onSystem('Lost the container event stream — container is still running, re-attaching.')
    this.stopStats?.()
    this.stopStats = null
    this.attachment?.close()
    this.attachment = null
    try {
      const attachment = await this.client.attachContainer(this.containerId, {
        onData: (stream, chunk) => this.events.onData(stream, chunk.toString('utf8')),
        onClose: () => {},
      })
      if (this.detached || this.exitFired) {
        attachment.close()
        return
      }
      this.attachment = attachment
      this.stopStats = this.client.statsStream(this.containerId, (sample) => {
        this.lastStats = sample
      })
    } catch {
      /* re-attach failed — the next wait error resolves it (probe / give up) */
    }
    if (this.detached || this.exitFired) return
    this.installWait()
  }

  /** true = running, false = stopped/gone, null = couldn't determine after retries. */
  private async probeRunning(): Promise<boolean | null> {
    for (let attempt = 0; attempt < 3; attempt++) {
      if (this.detached) return null
      try {
        const info = await this.client.inspectContainer(this.containerId)
        if (info === null) return false // 404 → gone
        return info.State.Running
      } catch {
        await new Promise((r) => setTimeout(r, 300 * (attempt + 1)))
      }
    }
    return null
  }

  private fireExit(code: number | null) {
    if (this.exitFired || this.detached) return
    this.exitFired = true
    this.cleanupStreams()
    // Container is kept until the exit is observed, then removed so no
    // stopped husks pile up. Removal failures are non-fatal.
    void this.client.removeContainer(this.containerId, true).catch(() => {})
    this.events.onExit({ code, signal: null })
  }

  private cleanupStreams() {
    this.stopStats?.()
    this.stopStats = null
    this.attachment?.close()
    this.attachment = null
  }

  get stdinWritable(): boolean {
    return Boolean(this.attachment?.writable)
  }

  writeStdin(text: string): void {
    this.attachment?.write(text)
  }

  async signal(sig: 'SIGINT' | 'SIGTERM' | 'SIGKILL'): Promise<void> {
    await this.client.killContainer(this.containerId, sig)
  }

  async sample(): Promise<RuntimeSample | null> {
    const s = this.lastStats
    if (!s) return null
    return { cpuPct: s.cpuPct, memBytes: s.memBytes, processes: s.processes }
  }

  detach(): void {
    this.detached = true
    this.waitAbort.abort()
    this.cleanupStreams()
  }
}

/** Throttle pull progress so a big image doesn't flood the console buffer. */
function throttledProgress(onSystem: (line: string) => void): (line: string) => void {
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
      onSystem(`docker: … (${suppressed} progress updates)`)
      suppressed = 0
    }
    lastTs = now
    onSystem(`docker: ${line}`)
  }
}

export async function spawnDockerHandle(opts: SpawnDockerOptions): Promise<RuntimeHandle> {
  const { client, events } = opts
  if (!isValidImageRef(opts.image)) throw new Error(`invalid docker image reference: ${JSON.stringify(opts.image)}`)

  if (!(await client.imageExists(opts.image))) {
    events.onSystem(`Pulling image ${opts.image} — first start may take a while...`)
    await client.pullImage(opts.image, throttledProgress(events.onSystem), opts.signal)
    events.onSystem(`Image ${opts.image} ready.`)
  }
  if (opts.signal?.aborted) throw new Error('start aborted')

  // A previous panel crash may have left a stopped container behind under our
  // name — clear it so create() cannot fail with a name conflict.
  await removeContainersForServer(client, opts.serverId).catch(() => {})

  const ports: { port: number; protocol: 'tcp' | 'udp' }[] = []
  for (const p of opts.ports) {
    if (p.protocol === 'both' || p.protocol === 'tcp') ports.push({ port: p.port, protocol: 'tcp' })
    if (p.protocol === 'both' || p.protocol === 'udp') ports.push({ port: p.port, protocol: 'udp' })
  }

  const env = { ...opts.env, HOME: CONTAINER_MOUNT }
  // Run as the panel's uid:gid on Linux so files written into the bind mount
  // stay editable by the panel (and the container never runs as root).
  const uid = typeof process.getuid === 'function' ? process.getuid() : undefined
  const gid = typeof process.getgid === 'function' ? process.getgid() : undefined
  const user = uid !== undefined && gid !== undefined ? `${uid}:${gid}` : undefined

  const hasLimits = Boolean(opts.memoryMb || opts.cpus)
  const containerId = await client.createContainer({
    name: opts.containerName,
    image: opts.image,
    cmd: opts.argv,
    env,
    workdir: CONTAINER_MOUNT,
    bind: { hostDir: opts.hostDir, containerDir: CONTAINER_MOUNT },
    ports,
    labels: { [LABEL_SERVER_ID]: opts.serverId, [LABEL_PANEL]: '1' },
    memoryBytes: opts.memoryMb ? Math.round(opts.memoryMb * 1024 * 1024) : undefined,
    cpus: opts.cpus ?? undefined,
    networkMode: opts.networkMode,
    user,
  })

  const handle = new DockerHandle(client, containerId, events)
  try {
    // The server may have been deleted while the container was created —
    // bail before starting it (the catch below removes it again).
    if (opts.signal?.aborted) throw new Error('start aborted')
    await handle.watch()
    await client.startContainer(containerId)
    if (opts.signal?.aborted) throw new Error('start aborted')
  } catch (err) {
    handle.detach()
    await client.removeContainer(containerId, true).catch(() => {})
    // Hosts with restricted cgroup delegation (nested containers, some VPSes)
    // cannot enforce limits — tell the user exactly what to change.
    if (hasLimits && /cgroup/i.test((err as Error).message)) {
      throw new Error(
        `${(err as Error).message} — this host's cgroup setup cannot enforce container resource limits; ` +
          'remove the CPU/memory limit in Settings → Runtime and start again',
      )
    }
    throw err
  }
  return handle
}

/**
 * Re-adopt a container that kept running while the panel was down.
 * Returns null when no running container exists for this server.
 */
export async function reattachDockerHandle(opts: {
  client: DockerClient
  serverId: string
  events: RuntimeEvents
}): Promise<{ handle: RuntimeHandle; startedAt: number; image: string } | null> {
  const entries = await opts.client.listByLabel(LABEL_SERVER_ID, opts.serverId)
  const running = entries.find((e) => e.State === 'running')
  // Stopped leftovers are useless — clean them up while we are here.
  for (const e of entries) {
    if (e.State !== 'running') void opts.client.removeContainer(e.Id, true).catch(() => {})
  }
  if (!running) return null
  const inspect = await opts.client.inspectContainer(running.Id)
  if (!inspect?.State.Running) return null
  const handle = new DockerHandle(opts.client, running.Id, opts.events)
  await handle.watch()
  const startedAt = Date.parse(inspect.State.StartedAt) || Date.now()
  return { handle, startedAt, image: running.Image }
}

/** Force-remove every container belonging to a server (deletion / stale cleanup). */
export async function removeContainersForServer(client: DockerClient, serverId: string): Promise<void> {
  const entries = await client.listByLabel(LABEL_SERVER_ID, serverId)
  await Promise.allSettled(entries.map((e) => client.removeContainer(e.Id, true)))
}

/**
 * Remove install containers left behind by a panel crash. Installs never
 * survive a restart (their in-memory state is gone), so at boot every
 * container carrying the install label is a stale root-privileged leftover
 * that nothing else would ever clean up.
 */
export async function removeInstallLeftovers(client: DockerClient): Promise<void> {
  const entries = await client.listByLabel(LABEL_INSTALL, '1')
  await Promise.allSettled(entries.map((e) => client.removeContainer(e.Id, true)))
}
