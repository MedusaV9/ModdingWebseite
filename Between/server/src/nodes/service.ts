/**
 * Panel-side registry of remote nodes plus the background loop that keeps
 * them fresh: every node is health-polled (agent /api/system) and its server
 * list reconciled into a lightweight local mirror (collection
 * `remote_servers`). The AGENT owns the authoritative server records and the
 * files; the mirror only carries what the panel needs for permission checks,
 * merged listings and offline display.
 *
 * Lifecycle invariants (AGENTS.md): the poll interval and the debounced
 * reconcile timer are owned here and cleared by stop(); poll runs never
 * overlap (in-flight join) and contain their rejections; stop() joins the
 * in-flight poll so shutdown never races a half-applied reconcile.
 */
import type { Store, Collection } from '../lib/jsonstore.ts'
import type { GameServer, NodeHealth, PanelNode } from '../types.ts'
import { NODE_TOKEN_MIN_LENGTH } from '../config.ts'
import { nowIso } from '../lib/util.ts'
import { NodeRequestError, RemoteNodeClient, type NodeIdentity, type RemoteServerSummary } from './client.ts'

/** Panel-side mirror of a server that lives on a remote node. */
export interface RemoteServerMirror extends GameServer {
  nodeId: string
  /** Display cache from the last successful reconcile (for offline listings). */
  blueprintName?: string
  icon?: string
  color?: string
}

const OFFLINE_HEALTH: NodeHealth = {
  online: false,
  lastSeen: null,
  latencyMs: null,
  cpuPct: null,
  memUsedBytes: null,
  memTotalBytes: null,
  diskUsedBytes: null,
  diskTotalBytes: null,
  version: null,
  error: null,
}

export interface NodeInput {
  name: string
  baseUrl: string
  token: string
}

/**
 * Validate admin-supplied node registration input. Base URLs are shape-only
 * validated (http/https, no credentials, no query/hash) — private/LAN hosts
 * are allowed BY DESIGN, see the SSRF note in client.ts.
 */
export function validateNodeInput(input: unknown): { problems: string[]; value?: NodeInput } {
  const problems: string[] = []
  const raw = (typeof input === 'object' && input !== null ? input : {}) as Record<string, unknown>
  const name = String(raw.name ?? '').trim()
  if (name.length < 1 || name.length > 60) problems.push('node name must be 1-60 characters')
  const token = String(raw.token ?? '')
  if (token.length < NODE_TOKEN_MIN_LENGTH) problems.push(`node token must be at least ${NODE_TOKEN_MIN_LENGTH} characters`)
  if (token.length > 500) problems.push('node token is too long (max 500 characters)')
  let baseUrl = ''
  let url: URL | null = null
  try {
    url = new URL(String(raw.baseUrl ?? ''))
  } catch {
    problems.push('base URL is not a valid URL')
  }
  if (url) {
    if (url.protocol !== 'http:' && url.protocol !== 'https:') problems.push('base URL must use http:// or https://')
    else if (url.username || url.password) problems.push('base URL must not contain credentials')
    else if (url.search || url.hash) problems.push('base URL must not contain a query string or fragment')
    else if (url.pathname !== '/' && url.pathname !== '') problems.push('base URL must not contain a path — point it at the agent root')
    else baseUrl = url.origin
  }
  if (problems.length > 0) return { problems }
  return { problems: [], value: { name, baseUrl, token } }
}

export class NodeService {
  readonly nodes: Collection<PanelNode>
  readonly mirrors: Collection<RemoteServerMirror>
  /** Called after node add/remove so the WS bridge can adjust connections. */
  onChanged: (() => void) | null = null

  private health = new Map<string, NodeHealth>()
  private summaries = new Map<string, RemoteServerSummary>()
  private clients = new Map<string, RemoteNodeClient>()
  private timer: ReturnType<typeof setInterval> | null = null
  private reconcileTimer: ReturnType<typeof setTimeout> | null = null
  private inFlight: Promise<void> | null = null
  private stopped = false

  constructor(store: Store, private pollMs: number) {
    this.nodes = store.collection<PanelNode>('nodes')
    this.mirrors = store.collection<RemoteServerMirror>('remote_servers')
  }

  // --- Lookup helpers ----------------------------------------------------------
  get(nodeId: string): PanelNode | undefined {
    return this.nodes.get(nodeId)
  }

  mirror(serverId: string): RemoteServerMirror | undefined {
    return this.mirrors.get(serverId)
  }

  healthOf(nodeId: string): NodeHealth {
    return this.health.get(nodeId) ?? OFFLINE_HEALTH
  }

  summaryOf(serverId: string): RemoteServerSummary | undefined {
    return this.summaries.get(serverId)
  }

  clientFor(node: PanelNode): RemoteNodeClient {
    let client = this.clients.get(node.id)
    if (!client) {
      client = new RemoteNodeClient(node.baseUrl, node.token)
      this.clients.set(node.id, client)
    }
    return client
  }

  // --- CRUD ----------------------------------------------------------------------
  addNode(input: unknown): { node?: PanelNode; problems: string[] } {
    const { problems, value } = validateNodeInput(input)
    if (!value) return { problems }
    if (this.nodes.find((n) => n.baseUrl === value.baseUrl)) return { problems: ['a node with this base URL is already registered'] }
    const node = this.nodes.insert({ ...value, createdAt: nowIso() })
    this.reconcileSoon()
    this.onChanged?.()
    return { node, problems: [] }
  }

  /**
   * Deregister a node. Its mirrored servers disappear from the panel (the
   * agent keeps running them untouched) — this is also the admin escape hatch
   * for zombie mirrors of a permanently dead node.
   */
  removeNode(nodeId: string): boolean {
    const removed = this.nodes.remove(nodeId)
    if (!removed) return false
    for (const mirror of this.mirrors.filter((m) => m.nodeId === nodeId)) {
      this.mirrors.remove(mirror.id)
      this.summaries.delete(mirror.id)
    }
    this.health.delete(nodeId)
    this.clients.delete(nodeId)
    this.onChanged?.()
    return true
  }

  /** Connectivity test: agent identity + round-trip latency. */
  async testNode(node: PanelNode): Promise<{ ok: boolean; identity?: NodeIdentity; latencyMs?: number; error?: string }> {
    const started = Date.now()
    try {
      const identity = await this.clientFor(node).identity()
      return { ok: true, identity, latencyMs: Date.now() - started }
    } catch (err) {
      return { ok: false, error: err instanceof NodeRequestError ? err.message : (err as Error).message }
    }
  }

  // --- Serialization ---------------------------------------------------------------
  /**
   * List/detail shape for a mirrored server — same fields as
   * serializeServer() plus nodeId/nodeName/nodeOnline. While the node is
   * reachable this reflects the poll cache (fresh agent serialization); when
   * it is not, a degraded record with status 'node-offline' is served from
   * the persisted mirror.
   */
  serializeRemote(mirror: RemoteServerMirror): Record<string, unknown> {
    const node = this.nodes.get(mirror.nodeId)
    const health = this.healthOf(mirror.nodeId)
    const summary = this.summaries.get(mirror.id)
    const nodeName = node?.name ?? '(removed node)'
    if (node && health.online && summary) {
      // ownerId is panel-side data — the agent only knows its token principal.
      return { ...summary, ownerId: mirror.ownerId, nodeId: mirror.nodeId, nodeName, nodeOnline: true }
    }
    return {
      id: mirror.id,
      name: mirror.name,
      blueprintId: mirror.blueprintId,
      blueprintName: mirror.blueprintName ?? mirror.blueprintId,
      icon: mirror.icon ?? 'server',
      color: mirror.color ?? '#6366f1',
      ownerId: mirror.ownerId,
      createdAt: mirror.createdAt,
      tags: mirror.tags,
      autoStart: mirror.autoStart,
      installed: mirror.installed,
      suspended: Boolean(mirror.suspended),
      status: 'node-offline',
      uptimeS: 0,
      ports: [],
      resources: null,
      query: null,
      memoryLimitMb: mirror.memoryLimitMb ?? null,
      installError: null,
      runtime: mirror.runtime === 'docker' ? 'docker' : 'process',
      nodeId: mirror.nodeId,
      nodeName,
      nodeOnline: false,
    }
  }

  /** Store the mirror for a server just created on a node (panel user owns it). */
  adoptCreated(nodeId: string, summary: RemoteServerSummary, ownerId: string): RemoteServerMirror {
    this.summaries.set(summary.id, summary)
    const existing = this.mirrors.get(summary.id)
    if (existing) return existing
    return this.mirrors.insert(this.mirrorFromSummary(nodeId, summary, ownerId))
  }

  /** Drop a mirror after a successful remote delete (agent broadcast may lag). */
  forgetServer(serverId: string): void {
    this.mirrors.remove(serverId)
    this.summaries.delete(serverId)
  }

  /** Live status pushed through the WS bridge between reconcile polls. */
  noteStatus(serverId: string, status: RemoteServerSummary['status']): void {
    const summary = this.summaries.get(serverId)
    if (summary) summary.status = status
  }

  // --- Poll / reconcile ---------------------------------------------------------------
  start(): void {
    if (this.timer) return
    this.stopped = false
    void this.pollAll()
    this.timer = setInterval(() => void this.pollAll(), this.pollMs)
    this.timer.unref?.()
  }

  async stop(): Promise<void> {
    this.stopped = true
    if (this.timer) clearInterval(this.timer)
    this.timer = null
    if (this.reconcileTimer) clearTimeout(this.reconcileTimer)
    this.reconcileTimer = null
    await this.inFlight?.catch(() => {})
  }

  /** Debounced one-shot poll (node added, deletion event seen, …). */
  reconcileSoon(delayMs = 250): void {
    if (this.stopped) return
    if (this.reconcileTimer) clearTimeout(this.reconcileTimer)
    this.reconcileTimer = setTimeout(() => {
      this.reconcileTimer = null
      void this.pollAll()
    }, delayMs)
    this.reconcileTimer.unref?.()
  }

  /** Poll every node once; overlapping calls join the run already in flight. */
  pollAll(): Promise<void> {
    if (this.inFlight) return this.inFlight
    const run = (async () => {
      try {
        await Promise.all(this.nodes.all().map((node) => this.pollNode(node)))
      } finally {
        this.inFlight = null
      }
    })()
    this.inFlight = run
    return run
  }

  /** One node: health snapshot + server-list reconcile. Never throws. */
  private async pollNode(node: PanelNode): Promise<void> {
    const client = this.clientFor(node)
    const started = Date.now()
    try {
      const { system } = await client.system()
      const { servers } = await client.listServers()
      if (this.stopped || !this.nodes.get(node.id)) return
      this.health.set(node.id, {
        online: true,
        lastSeen: nowIso(),
        latencyMs: Date.now() - started,
        cpuPct: system.metrics?.cpuPct ?? null,
        memUsedBytes: system.metrics?.memUsedBytes ?? null,
        memTotalBytes: system.metrics?.memTotalBytes ?? null,
        diskUsedBytes: system.metrics?.diskUsedBytes ?? null,
        diskTotalBytes: system.metrics?.diskTotalBytes ?? null,
        version: system.panelVersion ?? null,
        error: null,
      })
      this.applyServerList(node.id, servers)
    } catch (err) {
      if (this.stopped || !this.nodes.get(node.id)) return
      const prev = this.health.get(node.id)
      this.health.set(node.id, {
        ...OFFLINE_HEALTH,
        lastSeen: prev?.lastSeen ?? null,
        version: prev?.version ?? null,
        error: (err as Error).message,
      })
    }
  }

  private applyServerList(nodeId: string, servers: RemoteServerSummary[]): void {
    const seen = new Set<string>()
    for (const summary of servers) {
      if (!summary || typeof summary.id !== 'string') continue
      seen.add(summary.id)
      this.summaries.set(summary.id, summary)
      const existing = this.mirrors.get(summary.id)
      if (existing) {
        this.mirrors.update(summary.id, {
          nodeId,
          name: summary.name,
          blueprintId: summary.blueprintId,
          tags: Array.isArray(summary.tags) ? summary.tags : [],
          autoStart: Boolean(summary.autoStart),
          installed: Boolean(summary.installed),
          suspended: Boolean(summary.suspended),
          memoryLimitMb: summary.memoryLimitMb ?? null,
          runtime: summary.runtime === 'docker' ? 'docker' : 'process',
          blueprintName: summary.blueprintName,
          icon: summary.icon,
          color: summary.color,
        })
      } else {
        // Adopted out-of-band server: no panel owner — visible to admins only.
        this.mirrors.insert(this.mirrorFromSummary(nodeId, summary, ''))
      }
    }
    for (const mirror of this.mirrors.filter((m) => m.nodeId === nodeId)) {
      if (!seen.has(mirror.id)) {
        this.mirrors.remove(mirror.id)
        this.summaries.delete(mirror.id)
      }
    }
  }

  private mirrorFromSummary(nodeId: string, summary: RemoteServerSummary, ownerId: string): RemoteServerMirror {
    return {
      id: summary.id,
      nodeId,
      name: summary.name,
      blueprintId: summary.blueprintId,
      ownerId,
      createdAt: summary.createdAt ?? nowIso(),
      dirName: '',
      variables: {},
      tags: Array.isArray(summary.tags) ? summary.tags : [],
      autoStart: Boolean(summary.autoStart),
      restartPolicy: { enabled: true, maxRetries: 3, backoffS: 10 },
      installed: Boolean(summary.installed),
      suspended: Boolean(summary.suspended),
      memoryLimitMb: summary.memoryLimitMb ?? null,
      runtime: summary.runtime === 'docker' ? 'docker' : 'process',
      blueprintName: summary.blueprintName,
      icon: summary.icon,
      color: summary.color,
    }
  }
}
