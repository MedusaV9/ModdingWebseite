/**
 * Minimal Docker Engine API client — hand-rolled, zero dependencies, speaking
 * HTTP over the local daemon socket (unix socket on Linux/macOS, named pipe on
 * Windows). Only the endpoints Between needs: ping/version, image inspect +
 * pull (with progress), container create/start/kill/wait/remove/inspect/list,
 * log fetch, a live stats stream and hijacked bidirectional attach/exec
 * streams (console I/O, web shell). Unversioned paths are used on purpose —
 * the daemon then serves its current API version, which keeps us compatible
 * with every non-ancient Docker/Podman.
 */
import http from 'node:http'
import net from 'node:net'

export function defaultDockerSocket(): string {
  if (process.env.BETWEEN_DOCKER_SOCKET) return process.env.BETWEEN_DOCKER_SOCKET
  return process.platform === 'win32' ? '\\\\.\\pipe\\docker_engine' : '/var/run/docker.sock'
}

export class DockerError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message)
  }
}

export interface DockerVersion {
  version: string
  apiVersion: string
  os: string
  arch: string
}

export interface ContainerPortSpec {
  /** Container (and host — published 1:1) port number. */
  port: number
  protocol: 'tcp' | 'udp'
}

export interface CreateContainerOptions {
  name: string
  image: string
  /** Command argv; the image entrypoint (if any) is preserved. */
  cmd: string[]
  /** Optional entrypoint override (install scripts); omitted = keep the image's. */
  entrypoint?: string[]
  env: Record<string, string>
  workdir: string
  /** Host directory bind-mounted at `workdir`. */
  bind: { hostDir: string; containerDir: string }
  ports: ContainerPortSpec[]
  labels: Record<string, string>
  /** Hard memory limit in bytes (0/undefined = unlimited). */
  memoryBytes?: number
  /** CPU limit in cores, e.g. 1.5 (0/undefined = unlimited). */
  cpus?: number
  networkMode: 'bridge' | 'host'
  /** Run as this uid:gid (Linux hosts) so bind-mounted files stay owned by the panel user. */
  user?: string
}

export interface DockerStatsSample {
  cpuPct: number
  memBytes: number
  processes: number
}

export interface AttachHandlers {
  onData: (stream: 'stdout' | 'stderr', chunk: Buffer) => void
  onClose: () => void
}

export interface DockerAttachment {
  write(text: string): void
  readonly writable: boolean
  close(): void
}

interface RequestResult {
  status: number
  body: Buffer
}

const QUICK_TIMEOUT_MS = 30_000
const MAX_RESPONSE_BYTES = 16 * 1024 * 1024
const MAX_PULL_LAYERS = 10_000

export class DockerClient {
  constructor(readonly socketPath: string = defaultDockerSocket()) {}

  // -------------------------------------------------------------------------
  // Plumbing
  // -------------------------------------------------------------------------
  private request(
    method: string,
    path: string,
    opts: {
      body?: unknown
      timeoutMs?: number
      signal?: AbortSignal
      /** Called with each chunk as it streams in; body in the result stays empty. */
      onChunk?: (chunk: Buffer) => void
      maxBodyBytes?: number
    } = {},
  ): Promise<RequestResult> {
    return new Promise((resolve, reject) => {
      const payload = opts.body !== undefined ? Buffer.from(JSON.stringify(opts.body)) : null
      const req = http.request(
        {
          socketPath: this.socketPath,
          path,
          method,
          headers: {
            Host: 'docker',
            ...(payload ? { 'Content-Type': 'application/json', 'Content-Length': payload.length } : {}),
          },
        },
        (res) => {
          const chunks: Buffer[] = []
          const maxBodyBytes = opts.maxBodyBytes ?? MAX_RESPONSE_BYTES
          let received = 0
          const declared = Number(res.headers['content-length'])
          if (!opts.onChunk && Number.isFinite(declared) && declared > maxBodyBytes) {
            res.destroy(new DockerError(0, `docker response too large (limit ${maxBodyBytes} bytes)`))
            return
          }
          res.on('data', (chunk: Buffer) => {
            if (opts.onChunk && (res.statusCode ?? 500) < 300) {
              try {
                opts.onChunk(chunk)
              } catch (err) {
                res.destroy(err as Error)
              }
              return
            }
            received += chunk.length
            if (received > maxBodyBytes) {
              res.destroy(new DockerError(0, `docker response too large (limit ${maxBodyBytes} bytes)`))
              return
            }
            chunks.push(chunk)
          })
          res.on('end', () => resolve({ status: res.statusCode ?? 0, body: Buffer.concat(chunks) }))
          res.on('error', reject)
        },
      )
      if (opts.timeoutMs) {
        req.setTimeout(opts.timeoutMs, () => req.destroy(new DockerError(0, `docker request timed out: ${method} ${path}`)))
      }
      // The error handler must be wired before any destroy() below — an
      // unhandled 'error' event on the request would crash the process.
      req.on('error', reject)
      if (opts.signal) {
        const onAbort = () => req.destroy(new DockerError(0, 'aborted'))
        if (opts.signal.aborted) return onAbort()
        opts.signal.addEventListener('abort', onAbort, { once: true })
        req.on('close', () => opts.signal?.removeEventListener('abort', onAbort))
      }
      req.end(payload ?? undefined)
    })
  }

  private parseError(result: RequestResult, fallback: string): DockerError {
    try {
      const parsed = JSON.parse(result.body.toString('utf8')) as { message?: string }
      return new DockerError(result.status, parsed.message || fallback)
    } catch {
      return new DockerError(result.status, fallback)
    }
  }

  private async json<T>(method: string, path: string, opts: { body?: unknown; timeoutMs?: number } = {}): Promise<T> {
    const result = await this.request(method, path, { timeoutMs: opts.timeoutMs ?? QUICK_TIMEOUT_MS, body: opts.body })
    if (result.status >= 300) throw this.parseError(result, `${method} ${path} failed (HTTP ${result.status})`)
    const text = result.body.toString('utf8')
    return (text ? JSON.parse(text) : {}) as T
  }

  // -------------------------------------------------------------------------
  // Daemon
  // -------------------------------------------------------------------------
  async ping(timeoutMs = 1500): Promise<boolean> {
    try {
      const result = await this.request('GET', '/_ping', { timeoutMs })
      return result.status === 200
    } catch {
      return false
    }
  }

  async version(): Promise<DockerVersion> {
    const v = await this.json<{ Version: string; ApiVersion: string; Os: string; Arch: string }>('GET', '/version', {
      timeoutMs: 5000,
    })
    return { version: v.Version, apiVersion: v.ApiVersion, os: v.Os, arch: v.Arch }
  }

  // -------------------------------------------------------------------------
  // Images
  // -------------------------------------------------------------------------
  async imageExists(image: string): Promise<boolean> {
    const result = await this.request('GET', `/images/${encodeURIComponent(image)}/json`, { timeoutMs: QUICK_TIMEOUT_MS })
    if (result.status === 200) return true
    if (result.status === 404) return false
    throw this.parseError(result, `image inspect failed (HTTP ${result.status})`)
  }

  /**
   * Pull an image, reporting progress lines (throttled by the caller). The
   * docker daemon streams ndjson: {status, id?, progress?, error?}.
   */
  async pullImage(image: string, onProgress: (line: string) => void, signal?: AbortSignal): Promise<void> {
    const [name, tag] = splitImageTag(image)
    const path = `/images/create?fromImage=${encodeURIComponent(name)}&tag=${encodeURIComponent(tag)}`
    let buffer = ''
    let pullError: string | null = null
    const seen = new Map<string, string>()
    const result = await this.request('POST', path, {
      signal,
      onChunk: (chunk) => {
        buffer += chunk.toString('utf8')
        // The last line may be incomplete — keep it in the buffer.
        const lines = buffer.split('\n')
        buffer = lines.pop() ?? ''
        // Defensive: progress lines are tiny; never let a broken stream that
        // stops sending newlines grow the buffer without bound.
        if (buffer.length > 1024 * 1024) buffer = ''
        for (const raw of lines) {
          if (!raw.trim()) continue
          try {
            const msg = JSON.parse(raw) as { status?: string; id?: string; progress?: string; error?: string }
            if (msg.error) {
              pullError = msg.error
              continue
            }
            if (!msg.status) continue
            const key = msg.id ? `${msg.id}` : '_global'
            // Only surface per-layer *state transitions* plus global messages —
            // raw byte progress would flood the console.
            if (!seen.has(key) && seen.size >= MAX_PULL_LAYERS) seen.clear()
            if (seen.get(key) !== msg.status) {
              seen.set(key, msg.status)
              onProgress(msg.id ? `${msg.status} ${msg.id}` : msg.status)
            }
          } catch {
            /* tolerate partial json */
          }
        }
      },
    })
    if (pullError) throw new DockerError(500, `image pull failed: ${pullError}`)
    if (result.status >= 300) throw this.parseError(result, `image pull failed (HTTP ${result.status})`)
  }

  // -------------------------------------------------------------------------
  // Containers
  // -------------------------------------------------------------------------
  async createContainer(opts: CreateContainerOptions): Promise<string> {
    const exposed: Record<string, Record<string, never>> = {}
    const bindings: Record<string, { HostPort: string }[]> = {}
    if (opts.networkMode !== 'host') {
      for (const p of opts.ports) {
        const key = `${p.port}/${p.protocol}`
        exposed[key] = {}
        bindings[key] = [{ HostPort: String(p.port) }]
      }
    }
    const body = {
      Image: opts.image,
      Cmd: opts.cmd,
      ...(opts.entrypoint ? { Entrypoint: opts.entrypoint } : {}),
      Env: Object.entries(opts.env).map(([k, v]) => `${k}=${v}`),
      WorkingDir: opts.workdir,
      OpenStdin: true,
      StdinOnce: false,
      Tty: false,
      Labels: opts.labels,
      ExposedPorts: exposed,
      ...(opts.user ? { User: opts.user } : {}),
      HostConfig: {
        Binds: [`${opts.bind.hostDir}:${opts.bind.containerDir}`],
        PortBindings: bindings,
        NetworkMode: opts.networkMode,
        ...(opts.memoryBytes ? { Memory: opts.memoryBytes, MemorySwap: opts.memoryBytes } : {}),
        ...(opts.cpus ? { NanoCpus: Math.round(opts.cpus * 1e9) } : {}),
        // tini as PID 1: forwards signals to the game and reaps zombies.
        Init: true,
      },
    }
    const res = await this.json<{ Id: string }>('POST', `/containers/create?name=${encodeURIComponent(opts.name)}`, { body })
    return res.Id
  }

  async startContainer(id: string): Promise<void> {
    const result = await this.request('POST', `/containers/${encodeURIComponent(id)}/start`, { timeoutMs: QUICK_TIMEOUT_MS })
    if (result.status >= 300 && result.status !== 304) throw this.parseError(result, `container start failed (HTTP ${result.status})`)
  }

  async killContainer(id: string, signal: string): Promise<void> {
    const result = await this.request('POST', `/containers/${encodeURIComponent(id)}/kill?signal=${encodeURIComponent(signal)}`, {
      timeoutMs: QUICK_TIMEOUT_MS,
    })
    // 409 = container not running — treat as success (it is already down).
    if (result.status >= 300 && result.status !== 409 && result.status !== 404)
      throw this.parseError(result, `container kill failed (HTTP ${result.status})`)
  }

  async removeContainer(id: string, force = true): Promise<void> {
    const result = await this.request('DELETE', `/containers/${encodeURIComponent(id)}?force=${force ? 'true' : 'false'}&v=false`, {
      timeoutMs: QUICK_TIMEOUT_MS,
    })
    if (result.status >= 300 && result.status !== 404 && result.status !== 409)
      throw this.parseError(result, `container remove failed (HTTP ${result.status})`)
  }

  async inspectContainer(id: string): Promise<ContainerInspect | null> {
    const result = await this.request('GET', `/containers/${encodeURIComponent(id)}/json`, { timeoutMs: QUICK_TIMEOUT_MS })
    if (result.status === 404) return null
    if (result.status >= 300) throw this.parseError(result, `container inspect failed (HTTP ${result.status})`)
    return JSON.parse(result.body.toString('utf8')) as ContainerInspect
  }

  /** List containers (including stopped) filtered by label. */
  async listByLabel(label: string, value: string): Promise<ContainerListEntry[]> {
    const filters = encodeURIComponent(JSON.stringify({ label: [`${label}=${value}`] }))
    return this.json<ContainerListEntry[]>('GET', `/containers/json?all=true&filters=${filters}`)
  }

  /**
   * Long-poll until the container's NEXT exit; resolves with the exit code.
   * condition=next-exit makes this safe to call on a created-but-not-yet
   * started container (the default 'not-running' would resolve immediately).
   * Abort via signal when detaching (panel shutdown).
   */
  async waitContainer(id: string, signal?: AbortSignal): Promise<number> {
    const result = await this.request('POST', `/containers/${encodeURIComponent(id)}/wait?condition=next-exit`, { signal })
    if (result.status >= 300) throw this.parseError(result, `container wait failed (HTTP ${result.status})`)
    const parsed = JSON.parse(result.body.toString('utf8')) as { StatusCode: number }
    return parsed.StatusCode
  }

  /** Fetch recent log lines (demuxed) — used when re-attaching to a survivor container. */
  async containerLogs(id: string, tail: number): Promise<{ stream: 'stdout' | 'stderr'; text: string }[]> {
    const result = await this.request('GET', `/containers/${encodeURIComponent(id)}/logs?stdout=true&stderr=true&tail=${Math.floor(tail)}`, {
      timeoutMs: QUICK_TIMEOUT_MS,
    })
    if (result.status >= 300) throw this.parseError(result, `container logs failed (HTTP ${result.status})`)
    const out: { stream: 'stdout' | 'stderr'; text: string }[] = []
    const demux = new StreamDemuxer((stream, chunk) => out.push({ stream, text: chunk.toString('utf8') }))
    demux.push(result.body)
    return out
  }

  /**
   * Live resource stats. Opens the streaming stats endpoint (1 sample/s from
   * the daemon) and invokes onSample with computed values. Returns a stop fn.
   */
  statsStream(id: string, onSample: (sample: DockerStatsSample) => void): () => void {
    const controller = new AbortController()
    let buffer = ''
    this.request('GET', `/containers/${encodeURIComponent(id)}/stats?stream=true`, {
      signal: controller.signal,
      onChunk: (chunk) => {
        buffer += chunk.toString('utf8')
        const lines = buffer.split('\n')
        buffer = lines.pop() ?? ''
        // Defensive: a stats frame is ~2 KiB; never let a broken stream grow the buffer.
        if (buffer.length > 1024 * 1024) buffer = ''
        for (const raw of lines) {
          if (!raw.trim()) continue
          try {
            const sample = computeStats(JSON.parse(raw))
            if (sample) onSample(sample)
          } catch {
            /* tolerate malformed frames */
          }
        }
      },
    }).catch(() => {
      /* stream ended (container stopped / abort) */
    })
    return () => controller.abort()
  }

  // -------------------------------------------------------------------------
  // Attach / exec (hijacked bidirectional streams)
  // -------------------------------------------------------------------------
  /**
   * Hijack a connection-upgrading endpoint (attach, exec start). Speaks raw
   * HTTP/1.1 on the socket because these endpoints take over the connection
   * (Upgrade: tcp) — node's http client cannot express that cleanly. With
   * raw:false the stream carries multiplexed frames (Tty=false) and is
   * demuxed into stdout/stderr callbacks; with raw:true (Tty mode) bytes
   * pass straight through as 'stdout'.
   */
  private hijack(
    path: string,
    body: string | null,
    handlers: AttachHandlers,
    opts: { raw: boolean; op: string },
  ): Promise<DockerAttachment> {
    return new Promise((resolve, reject) => {
      const socket = net.connect(this.socketPath)
      let headerBuf = Buffer.alloc(0)
      let upgraded = false
      let closed = false
      const demux = opts.raw ? null : new StreamDemuxer((stream, chunk) => handlers.onData(stream, chunk))
      const sink = (chunk: Buffer) => (demux ? demux.push(chunk) : handlers.onData('stdout', chunk))

      const fail = (err: Error) => {
        if (closed) return
        closed = true
        socket.destroy()
        reject(err)
      }

      socket.on('connect', () => {
        // Callers encodeURIComponent ids into the path, which also keeps the
        // hand-written request line intact (an id containing CR/LF or spaces
        // could otherwise corrupt it).
        socket.write(
          `POST ${path} HTTP/1.1\r\n` +
            'Host: docker\r\nConnection: Upgrade\r\nUpgrade: tcp\r\n' +
            (body !== null ? `Content-Type: application/json\r\nContent-Length: ${Buffer.byteLength(body)}\r\n` : '') +
            '\r\n' +
            (body ?? ''),
        )
      })
      socket.on('data', (chunk: Buffer) => {
        if (upgraded) {
          sink(chunk)
          return
        }
        headerBuf = Buffer.concat([headerBuf, chunk])
        const headerEnd = headerBuf.indexOf('\r\n\r\n')
        if (headerEnd === -1) {
          if (headerBuf.length > 64 * 1024) fail(new DockerError(0, `${opts.op}: response headers too large`))
          return
        }
        const head = headerBuf.subarray(0, headerEnd).toString('utf8')
        const statusMatch = head.match(/^HTTP\/1\.[01] (\d{3})/)
        const status = statusMatch ? Number(statusMatch[1]) : 0
        // 101 = hijacked upgrade (normal); 200 = older daemons stream directly.
        if (status !== 101 && status !== 200) {
          fail(new DockerError(status, `${opts.op} failed (HTTP ${status})`))
          return
        }
        upgraded = true
        const rest = headerBuf.subarray(headerEnd + 4)
        headerBuf = Buffer.alloc(0)
        if (rest.length > 0) sink(rest)
        resolve({
          write(text: string) {
            if (!closed) socket.write(text)
          },
          get writable() {
            return !closed && socket.writable
          },
          close() {
            if (closed) return
            closed = true
            socket.destroy()
          },
        })
      })
      socket.on('error', (err) => {
        if (!upgraded) fail(new DockerError(0, `${opts.op} failed: ${err.message}`))
        else if (!closed) {
          closed = true
          handlers.onClose()
        }
      })
      socket.on('close', () => {
        if (!upgraded) fail(new DockerError(0, `${opts.op} failed: connection closed`))
        else if (!closed) {
          closed = true
          handlers.onClose()
        }
      })
    })
  }

  /**
   * Attach to a container's stdio. Output arrives in multiplexed frames
   * (Tty=false) and is demuxed into stdout/stderr callbacks.
   */
  attachContainer(id: string, handlers: AttachHandlers): Promise<DockerAttachment> {
    return this.hijack(
      `/containers/${encodeURIComponent(id)}/attach?stream=1&stdin=1&stdout=1&stderr=1`,
      null,
      handlers,
      { raw: false, op: 'attach' },
    )
  }

  /** Create an interactive TTY exec inside a running container; returns the exec id. */
  async execCreate(containerId: string, cmd: string[]): Promise<string> {
    const res = await this.json<{ Id: string }>('POST', `/containers/${encodeURIComponent(containerId)}/exec`, {
      body: { AttachStdin: true, AttachStdout: true, AttachStderr: true, Tty: true, Cmd: cmd },
    })
    return res.Id
  }

  /** Start a created exec and hijack its stream (Tty mode = single raw stream). */
  execStart(execId: string, handlers: { onData: (chunk: Buffer) => void; onClose: () => void }): Promise<DockerAttachment> {
    return this.hijack(
      `/exec/${encodeURIComponent(execId)}/start`,
      JSON.stringify({ Detach: false, Tty: true }),
      { onData: (_stream, chunk) => handlers.onData(chunk), onClose: handlers.onClose },
      { raw: true, op: 'exec start' },
    )
  }

  /** Resize an exec's TTY — best-effort (a finished exec 404s; never surface it). */
  async execResize(execId: string, h: number, w: number): Promise<void> {
    await this.request('POST', `/exec/${encodeURIComponent(execId)}/resize?h=${Math.floor(h)}&w=${Math.floor(w)}`, {
      timeoutMs: QUICK_TIMEOUT_MS,
    }).catch(() => {})
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
export function splitImageTag(image: string): [name: string, tag: string] {
  // The tag is the part after the last ':' *unless* that colon belongs to a
  // registry port (contains '/') or a digest reference ('@').
  const at = image.indexOf('@')
  if (at !== -1) return [image.slice(0, at), image.slice(at + 1)]
  const colon = image.lastIndexOf(':')
  if (colon === -1 || image.indexOf('/', colon) !== -1) return [image, 'latest']
  return [image.slice(0, colon), image.slice(colon + 1)]
}

/** Loose image-reference validation: enough to catch typos and injection. */
export function isValidImageRef(image: string): boolean {
  return /^[a-z0-9][a-z0-9._\-/:@]{0,254}$/i.test(image) && !/\s/.test(image)
}

export interface ContainerInspect {
  Id: string
  State: { Status: string; Running: boolean; ExitCode: number; StartedAt: string; Pid?: number }
  Config?: { Image?: string; Labels?: Record<string, string> }
  Name?: string
}

export interface ContainerListEntry {
  Id: string
  Names: string[]
  State: string
  Status: string
  Labels: Record<string, string>
  Image: string
}

/**
 * Demultiplexer for docker's multiplexed stream framing (Tty=false):
 * 8-byte header [type, 0, 0, 0, size(u32 BE)] followed by `size` payload bytes.
 * type 1 = stdout, 2 = stderr.
 */
const MAX_BUFFERED_FRAME = 1024 * 1024

export class StreamDemuxer {
  private buffer: Buffer = Buffer.alloc(0)
  /** Remaining payload bytes of an oversized frame being streamed through. */
  private streamingRemaining = 0
  private streamingType = 1

  constructor(private emit: (stream: 'stdout' | 'stderr', chunk: Buffer) => void) {}

  push(chunk: Buffer): void {
    this.buffer = this.buffer.length === 0 ? chunk : Buffer.concat([this.buffer, chunk])
    for (;;) {
      if (this.streamingRemaining > 0) {
        if (this.buffer.length === 0) return
        const take = Math.min(this.streamingRemaining, this.buffer.length)
        const payload = this.buffer.subarray(0, take)
        this.buffer = this.buffer.subarray(take)
        this.streamingRemaining -= take
        this.emit(this.streamingType === 2 ? 'stderr' : 'stdout', payload)
        continue
      }
      if (this.buffer.length < 8) return
      const type = this.buffer[0]
      const size = this.buffer.readUInt32BE(4)
      if (this.buffer.length < 8 + size) {
        // A corrupt/hostile header can declare up to 4 GiB — never buffer a
        // whole oversized frame; stream its payload through as it arrives.
        if (size > MAX_BUFFERED_FRAME) {
          this.streamingType = type
          this.streamingRemaining = size
          this.buffer = this.buffer.subarray(8)
          continue
        }
        return
      }
      const payload = this.buffer.subarray(8, 8 + size)
      this.buffer = this.buffer.subarray(8 + size)
      if (size > 0) this.emit(type === 2 ? 'stderr' : 'stdout', payload)
    }
  }
}

/** Compute a resource sample from a daemon stats frame (cgroup v1 + v2 safe). */
export function computeStats(frame: unknown): DockerStatsSample | null {
  if (typeof frame !== 'object' || frame === null) return null
  const f = frame as {
    cpu_stats?: { cpu_usage?: { total_usage?: number }; system_cpu_usage?: number; online_cpus?: number }
    precpu_stats?: { cpu_usage?: { total_usage?: number }; system_cpu_usage?: number }
    memory_stats?: { usage?: number; stats?: { inactive_file?: number; cache?: number } }
    pids_stats?: { current?: number }
  }
  const cpuTotal = f.cpu_stats?.cpu_usage?.total_usage
  const preTotal = f.precpu_stats?.cpu_usage?.total_usage
  const sysTotal = f.cpu_stats?.system_cpu_usage
  const preSys = f.precpu_stats?.system_cpu_usage
  if (cpuTotal === undefined) return null
  // Hosts with restricted cgroup delegation may omit memory usage entirely —
  // still deliver the cpu/pids part of the sample.
  const memUsage = f.memory_stats?.usage ?? 0
  let cpuPct = 0
  if (preTotal !== undefined && sysTotal !== undefined && preSys !== undefined && sysTotal > preSys) {
    const cpus = f.cpu_stats?.online_cpus || 1
    cpuPct = ((cpuTotal - preTotal) / (sysTotal - preSys)) * cpus * 100
  }
  // Match `docker stats`: subtract page-cache-ish memory the kernel can reclaim.
  const reclaimable = f.memory_stats?.stats?.inactive_file ?? f.memory_stats?.stats?.cache ?? 0
  return {
    cpuPct: Math.max(0, Math.round(cpuPct * 10) / 10),
    memBytes: Math.max(0, memUsage - reclaimable),
    processes: f.pids_stats?.current ?? 1,
  }
}
