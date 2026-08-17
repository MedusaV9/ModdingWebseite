/**
 * Live console/stats bridging across the panel↔node hop: the panel keeps at
 * most ONE multiplexed WebSocket client per registered node (the same
 * /api/ws the browser uses, authenticated with the node token) and
 * re-broadcasts incoming events into the panel's own WsHub under the SAME
 * channel names — the frontend needs no changes to stream remote servers.
 *
 * Laziness: connections exist only while at least one browser client is
 * connected to the panel hub (woken by the hub's client-connected hook) and
 * are torn down by the periodic sync when the last browser leaves or a node
 * is deregistered. Console channels are subscribed on the node connection on
 * demand (browser sub) and unsubscribed when no panel subscriber remains.
 *
 * Invariants (AGENTS.md): every socket and timer is owned here and cleared
 * by stop(); reconnects use capped exponential backoff; inbound frames are
 * size-capped; outbound browser fan-out inherits WsHub's buffering caps; and
 * events are only accepted for servers actually mirrored to the sending
 * node (no cross-node spoofing).
 */
import { WebSocket } from 'ws'
import type { PanelNode, ServerStatus } from '../types.ts'
import type { WsHub } from '../ws/hub.ts'
import type { NodeService } from './service.ts'

const MAX_INBOUND_FRAME = 256 * 1024
const RECONNECT_MAX_MS = 30_000
const SYNC_INTERVAL_MS = 30_000

class NodeConnection {
  private ws: WebSocket | null = null
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null
  private attempts = 0
  private closed = false
  /** Console channels panel clients currently want from this node. */
  private wanted = new Set<string>()

  constructor(private node: PanelNode, private nodes: NodeService, private hub: WsHub) {
    this.connect()
  }

  private connect(): void {
    if (this.closed) return
    const url = `${this.node.baseUrl.replace(/^http/, 'ws')}/api/ws`
    const ws = new WebSocket(url, {
      headers: { authorization: `Bearer ${this.node.token}` },
      maxPayload: MAX_INBOUND_FRAME,
      handshakeTimeout: 10_000,
    })
    this.ws = ws
    ws.on('open', () => {
      this.attempts = 0
      for (const channel of this.wanted) ws.send(JSON.stringify({ op: 'sub', channel }))
    })
    ws.on('message', (raw) => this.onMessage(String(raw)))
    ws.on('error', () => {
      /* the close event always follows and owns the reconnect */
    })
    ws.on('close', () => {
      if (this.ws === ws) this.ws = null
      this.scheduleReconnect()
    })
  }

  private scheduleReconnect(): void {
    if (this.closed || this.reconnectTimer) return
    const delay = Math.min(RECONNECT_MAX_MS, 1000 * 2 ** Math.min(this.attempts++, 10))
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null
      this.connect()
    }, delay)
    this.reconnectTimer.unref?.()
  }

  private onMessage(raw: string): void {
    if (raw.length > MAX_INBOUND_FRAME) return
    let msg: { t?: string; serverId?: string; status?: string }
    try {
      msg = JSON.parse(raw) as typeof msg
    } catch {
      return
    }
    if (typeof msg.t !== 'string') return
    // Only re-broadcast events about servers this node actually hosts — the
    // mirror doubles as the visibility object for per-user WsHub checks.
    const serverId = typeof msg.serverId === 'string' ? msg.serverId : null
    const mirror = serverId ? this.nodes.mirror(serverId) : undefined
    switch (msg.t) {
      case 'console':
        if (!mirror || mirror.nodeId !== this.node.id) return
        this.hub.broadcast(`console:${serverId}`, msg as Record<string, unknown>, mirror, 'server.console')
        return
      case 'status':
        if (!mirror || mirror.nodeId !== this.node.id) return
        if (typeof msg.status === 'string') this.nodes.noteStatus(serverId!, msg.status as ServerStatus)
        this.hub.broadcast('servers', msg as Record<string, unknown>, mirror)
        return
      case 'stats':
      case 'query':
      case 'event':
        if (!mirror || mirror.nodeId !== this.node.id) return
        this.hub.broadcast('servers', msg as Record<string, unknown>, mirror)
        return
      case 'deleted':
        // Deleted out-of-band on the node: forward while the mirror still
        // exists, then let the reconcile poll drop it.
        if (mirror && mirror.nodeId === this.node.id) this.hub.broadcast('servers', msg as Record<string, unknown>, mirror)
        this.nodes.reconcileSoon()
        return
      default:
        // hello/sub-ok/metrics/audit from the agent are panel-internal noise here.
        return
    }
  }

  wantChannel(channel: string): void {
    if (this.wanted.has(channel)) return
    this.wanted.add(channel)
    if (this.ws?.readyState === WebSocket.OPEN) this.ws.send(JSON.stringify({ op: 'sub', channel }))
  }

  /** Unsubscribe console channels no panel client listens to anymore. */
  pruneChannels(): void {
    for (const channel of this.wanted) {
      if (this.hub.subscriberCount(channel) > 0) continue
      this.wanted.delete(channel)
      if (this.ws?.readyState === WebSocket.OPEN) this.ws.send(JSON.stringify({ op: 'unsub', channel }))
    }
  }

  close(): void {
    this.closed = true
    if (this.reconnectTimer) clearTimeout(this.reconnectTimer)
    this.reconnectTimer = null
    this.ws?.terminate()
    this.ws = null
    this.wanted.clear()
  }
}

export class NodeStreamBridge {
  private conns = new Map<string, NodeConnection>()
  private syncTimer: ReturnType<typeof setInterval> | null = null
  private stopped = false

  constructor(private nodes: NodeService, private hub: WsHub) {}

  start(): void {
    if (this.syncTimer) return
    this.stopped = false
    this.syncTimer = setInterval(() => this.sync(), SYNC_INTERVAL_MS)
    this.syncTimer.unref?.()
  }

  /**
   * Reconcile desired vs. actual node connections. Desired = one connection
   * per registered node while any browser client is connected to the hub.
   * Called on browser connect, node add/remove and every sync tick.
   */
  sync(): void {
    if (this.stopped) return
    const wantAny = this.hub.clientCount() > 0
    const registered = new Set(this.nodes.nodes.all().map((n) => n.id))
    for (const [nodeId, conn] of this.conns) {
      if (!wantAny || !registered.has(nodeId)) {
        conn.close()
        this.conns.delete(nodeId)
      } else {
        conn.pruneChannels()
      }
    }
    if (!wantAny) return
    for (const node of this.nodes.nodes.all()) {
      if (!this.conns.has(node.id)) this.conns.set(node.id, new NodeConnection(node, this.nodes, this.hub))
    }
  }

  /** Hub hook: a browser subscribed to a channel — wire remote console feeds through. */
  onPanelSubscribe(channel: string): void {
    if (this.stopped) return
    this.sync()
    const match = channel.match(/^console:(.+)$/)
    if (!match) return
    const mirror = this.nodes.mirror(match[1])
    if (!mirror) return
    this.conns.get(mirror.nodeId)?.wantChannel(channel)
  }

  stop(): void {
    this.stopped = true
    if (this.syncTimer) clearInterval(this.syncTimer)
    this.syncTimer = null
    for (const conn of this.conns.values()) conn.close()
    this.conns.clear()
  }
}
