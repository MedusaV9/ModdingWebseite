/**
 * Panel-wide Docker availability: one shared client plus a cached probe.
 * Docker is strictly optional — when the daemon is unreachable the panel
 * behaves exactly like before (process runtime only).
 */
import { DockerClient, defaultDockerSocket } from '../lib/docker.ts'

export interface DockerInfo {
  available: boolean
  version?: string
  apiVersion?: string
  socketPath: string
  error?: string
}

const PROBE_TTL_MS = 15_000

export class DockerService {
  readonly client: DockerClient
  private cached: DockerInfo | null = null
  private cachedAt = 0
  private probing: Promise<DockerInfo> | null = null

  constructor(socketPath: string = defaultDockerSocket()) {
    this.client = new DockerClient(socketPath)
  }

  /** Cached availability probe (15s TTL) — cheap enough for request paths. */
  async info(force = false): Promise<DockerInfo> {
    const now = Date.now()
    if (!force && this.cached && now - this.cachedAt < PROBE_TTL_MS) return this.cached
    if (this.probing) return this.probing
    this.probing = this.probe().finally(() => {
      this.probing = null
    })
    return this.probing
  }

  /** Last cached result without touching the daemon (may be null before first probe). */
  get lastInfo(): DockerInfo | null {
    return this.cached
  }

  private async probe(): Promise<DockerInfo> {
    let info: DockerInfo
    try {
      if (await this.client.ping()) {
        const v = await this.client.version()
        info = { available: true, version: v.version, apiVersion: v.apiVersion, socketPath: this.client.socketPath }
      } else {
        info = { available: false, socketPath: this.client.socketPath, error: 'daemon not reachable' }
      }
    } catch (err) {
      info = { available: false, socketPath: this.client.socketPath, error: (err as Error).message }
    }
    this.cached = info
    this.cachedAt = Date.now()
    return info
  }
}
