/**
 * HTTP client the panel uses to talk to one node agent. Hand-rolled on
 * global fetch — no dependencies. Every call carries the node's bearer token
 * and a hard 10s timeout via AbortController; for streaming transfers the
 * timeout only covers the handshake (headers), then the stream flows freely
 * and a dead node surfaces as a stream error on the pipe.
 *
 * SSRF stance (documented decision): node base URLs are admin-only
 * configuration, and pointing the panel at LAN/private addresses is the
 * PRIMARY use case (your second machine in the rack) — exactly like the
 * generic webhook URL in services/notify.ts. Validation is therefore
 * shape-only (http/https, parseable), NOT routed through nettrust.ts.
 */
import type { Readable } from 'node:stream'
import type { Backup, ConsoleLine, QueryResult, ResourceSnapshot, ServerStatus } from '../types.ts'

const REQUEST_TIMEOUT_MS = 10_000

/** status === null means the node was unreachable (network error / timeout). */
export class NodeRequestError extends Error {
  constructor(public status: number | null, message: string) {
    super(message)
    this.name = 'NodeRequestError'
  }
}

export interface NodeIdentity {
  between: string
  name: string
  version: string
  platform: string
  arch: string
}

/** Shape of one server as serialized by the agent's GET /api/servers. */
export interface RemoteServerSummary {
  id: string
  name: string
  blueprintId: string
  blueprintName: string
  icon: string
  color: string
  ownerId: string
  createdAt: string
  tags: string[]
  autoStart: boolean
  installed: boolean
  suspended: boolean
  status: ServerStatus
  uptimeS: number
  ports: { name: string; port: number; protocol: string }[]
  resources: ResourceSnapshot | null
  query: QueryResult | null
  memoryLimitMb: number | null
  installError: string | null
  runtime: string
  [key: string]: unknown
}

export interface RemoteSystemInfo {
  platform: string
  arch: string
  hostname: string
  panelVersion: string
  metrics: {
    cpuPct: number
    memUsedBytes: number
    memTotalBytes: number
    diskUsedBytes: number
    diskTotalBytes: number
  } | null
  [key: string]: unknown
}

export class RemoteNodeClient {
  private readonly base: string

  constructor(baseUrl: string, private token: string) {
    this.base = baseUrl.replace(/\/+$/, '')
  }

  private headers(extra: Record<string, string> = {}): Record<string, string> {
    return { authorization: `Bearer ${this.token}`, ...extra }
  }

  /** JSON request with a hard timeout; agent errors keep their HTTP status. */
  private async request<T>(method: string, path: string, body?: unknown): Promise<T> {
    const controller = new AbortController()
    const timeout = setTimeout(() => controller.abort(new Error('node request timed out')), REQUEST_TIMEOUT_MS)
    timeout.unref?.()
    let res: Response
    try {
      res = await fetch(`${this.base}${path}`, {
        method,
        headers: this.headers(body !== undefined ? { 'content-type': 'application/json' } : {}),
        body: body !== undefined ? JSON.stringify(body) : undefined,
        signal: controller.signal,
      })
    } catch (err) {
      throw new NodeRequestError(null, controller.signal.aborted ? 'node request timed out' : `node unreachable: ${(err as Error).message}`)
    } finally {
      clearTimeout(timeout)
    }
    const text = await res.text().catch(() => '')
    let json: Record<string, unknown> = {}
    try {
      json = text ? (JSON.parse(text) as Record<string, unknown>) : {}
    } catch {
      /* non-JSON error bodies fall through to the generic message */
    }
    if (!res.ok) throw new NodeRequestError(res.status, String(json.error ?? `node returned HTTP ${res.status}`))
    return json as T
  }

  // --- Identity / health -----------------------------------------------------
  identity(): Promise<NodeIdentity> {
    return this.request<NodeIdentity>('GET', '/api/node/identity')
  }

  system(): Promise<{ system: RemoteSystemInfo }> {
    return this.request('GET', '/api/system')
  }

  // --- Servers -----------------------------------------------------------------
  listServers(): Promise<{ servers: RemoteServerSummary[] }> {
    return this.request('GET', '/api/servers')
  }

  createServer(payload: Record<string, unknown>): Promise<{ server: RemoteServerSummary }> {
    return this.request('POST', '/api/servers', payload)
  }

  getDetail(id: string): Promise<{ server: RemoteServerSummary }> {
    return this.request('GET', `/api/servers/${encodeURIComponent(id)}`)
  }

  deleteServer(id: string, opts: { keepFiles?: boolean; deleteBackups?: boolean }): Promise<{ ok: boolean }> {
    return this.request('DELETE', `/api/servers/${encodeURIComponent(id)}`, {
      keepFiles: Boolean(opts.keepFiles),
      deleteBackups: Boolean(opts.deleteBackups),
    })
  }

  power(id: string, action: string): Promise<{ ok: boolean; status: ServerStatus }> {
    return this.request('POST', `/api/servers/${encodeURIComponent(id)}/power`, { action })
  }

  sendCommand(id: string, command: string): Promise<{ ok: boolean }> {
    return this.request('POST', `/api/servers/${encodeURIComponent(id)}/command`, { command })
  }

  consoleLog(id: string, limit: number): Promise<{ lines: ConsoleLine[]; status: ServerStatus }> {
    return this.request('GET', `/api/servers/${encodeURIComponent(id)}/console?limit=${limit}`)
  }

  resources(
    id: string,
    limit?: number,
  ): Promise<{ resources: ResourceSnapshot | null; history: ResourceSnapshot[]; status: ServerStatus; uptimeS: number }> {
    const qs = limit !== undefined ? `?limit=${limit}` : ''
    return this.request('GET', `/api/servers/${encodeURIComponent(id)}/resources${qs}`)
  }

  size(id: string): Promise<{ sizeBytes: number }> {
    return this.request('GET', `/api/servers/${encodeURIComponent(id)}/size`)
  }

  // --- Files -------------------------------------------------------------------
  listFiles(id: string, rel: string): Promise<{ path: string; entries: unknown[] }> {
    return this.request('GET', `/api/servers/${encodeURIComponent(id)}/files?path=${encodeURIComponent(rel)}`)
  }

  readFile(id: string, rel: string): Promise<Record<string, unknown>> {
    return this.request('GET', `/api/servers/${encodeURIComponent(id)}/files/content?path=${encodeURIComponent(rel)}`)
  }

  writeFile(id: string, rel: string, content: string): Promise<{ ok: boolean }> {
    return this.request('PUT', `/api/servers/${encodeURIComponent(id)}/files/content`, { path: rel, content })
  }

  deleteFiles(id: string, paths: string[]): Promise<{ ok: boolean; deleted: number }> {
    return this.request('POST', `/api/servers/${encodeURIComponent(id)}/files/delete`, { paths })
  }

  mkdir(id: string, rel: string): Promise<{ ok: boolean }> {
    return this.request('POST', `/api/servers/${encodeURIComponent(id)}/files/mkdir`, { path: rel })
  }

  /**
   * Open a streaming download from the node. The timeout covers the
   * handshake only — the caller pipes res.body without buffering the file.
   */
  async openDownload(id: string, rel: string): Promise<Response> {
    return this.openStream('GET', `/api/servers/${encodeURIComponent(id)}/files/download?path=${encodeURIComponent(rel)}`)
  }

  /**
   * Stream an upload through to the node without buffering the body in panel
   * memory (fetch with a Node Readable requires half-duplex mode). No fixed
   * deadline here on purpose — fetch() only resolves after the whole body is
   * consumed, so a 10s abort would kill every large upload; a dead node or a
   * vanished browser surfaces as a stream/socket error instead.
   */
  async uploadStream(id: string, dirRel: string, name: string, body: Readable, contentLength?: string): Promise<{ ok: boolean; bytes: number }> {
    let res: Response
    try {
      res = await fetch(
        `${this.base}/api/servers/${encodeURIComponent(id)}/files/upload?path=${encodeURIComponent(dirRel)}&name=${encodeURIComponent(name)}`,
        {
          method: 'PUT',
          headers: this.headers(contentLength ? { 'content-length': contentLength } : {}),
          body: body as unknown as RequestInit['body'],
          // Node's fetch requires half-duplex for streaming request bodies.
          duplex: 'half',
        } as RequestInit,
      )
    } catch (err) {
      throw new NodeRequestError(null, `node unreachable: ${(err as Error).message}`)
    }
    const json = (await res.json().catch(() => ({}))) as Record<string, unknown>
    if (!res.ok) throw new NodeRequestError(res.status, String(json.error ?? `node returned HTTP ${res.status}`))
    return json as { ok: boolean; bytes: number }
  }

  private async openStream(method: string, path: string): Promise<Response> {
    const controller = new AbortController()
    const timeout = setTimeout(() => controller.abort(new Error('node request timed out')), REQUEST_TIMEOUT_MS)
    timeout.unref?.()
    let res: Response
    try {
      res = await fetch(`${this.base}${path}`, { method, headers: this.headers(), signal: controller.signal })
    } catch (err) {
      throw new NodeRequestError(null, controller.signal.aborted ? 'node request timed out' : `node unreachable: ${(err as Error).message}`)
    } finally {
      // Headers arrived — from here the body streams without a deadline.
      clearTimeout(timeout)
    }
    if (!res.ok) {
      const text = await res.text().catch(() => '')
      let message = `node returned HTTP ${res.status}`
      try {
        message = String((JSON.parse(text) as { error?: string }).error ?? message)
      } catch {
        /* keep generic */
      }
      throw new NodeRequestError(res.status, message)
    }
    return res
  }

  // --- Backups -------------------------------------------------------------------
  listBackups(id: string): Promise<{ backups: Backup[]; busy: boolean; retention: number }> {
    return this.request('GET', `/api/servers/${encodeURIComponent(id)}/backups`)
  }

  createBackup(id: string, note: string): Promise<{ backup: Backup }> {
    return this.request('POST', `/api/servers/${encodeURIComponent(id)}/backups`, { note })
  }

  restoreBackup(id: string, backupId: string, opts: { wipe?: boolean; safetyBackup?: boolean }): Promise<{ ok: boolean }> {
    return this.request('POST', `/api/servers/${encodeURIComponent(id)}/backups/${encodeURIComponent(backupId)}/restore`, opts)
  }

  deleteBackup(id: string, backupId: string): Promise<{ ok: boolean }> {
    return this.request('DELETE', `/api/servers/${encodeURIComponent(id)}/backups/${encodeURIComponent(backupId)}`)
  }
}
