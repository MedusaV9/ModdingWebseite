/**
 * Single multiplexed WebSocket per client: console streams, server status /
 * stats / query events, host metrics and toast-worthy panel events.
 */
import type { IncomingMessage } from 'node:http'
import type { Duplex } from 'node:stream'
import { WebSocketServer, WebSocket } from 'ws'
import { AuthService, parseCookies, SESSION_COOKIE } from '../auth/service.ts'
import type { ServerManager } from '../servers/manager.ts'
import type { GameServer, User, ServerPermission } from '../types.ts'
import { bearerToken, NODE_AGENT_USER, tokenEquals } from '../nodes/token.ts'

interface ClientState {
  user: User
  sessionId: string
  subs: Set<string>
  alive: boolean
  /**
   * Node-agent mode: this client authenticated with the process-lifetime
   * BETWEEN_NODE_TOKEN instead of a session. There is nothing to revalidate
   * per message — the token cannot be revoked without restarting the agent
   * (which terminates the socket anyway) — so authorization short-circuits
   * to admin-equivalent. Never set in panel mode.
   */
  tokenAuth: boolean
}

export interface WsHubOptions {
  /** Set in node-agent mode: the ONLY accepted WS credential (Authorization: Bearer). */
  nodeToken?: string | null
  /** Panel mode: resolve mirrored remote servers for channel authorization + broadcasts. */
  remoteLookup?: (id: string) => GameServer | undefined
  /** Panel mode: notify the node stream bridge about a fresh (allowed) subscription. */
  onSubscribe?: (channel: string) => void
  /** Panel mode: a browser client connected (wakes the node stream bridge). */
  onClientConnected?: () => void
}

const MAX_MESSAGE_BYTES = 64 * 1024
const MAX_BUFFERED_OUTPUT = 4 * 1024 * 1024

export class WsHub {
  private wss = new WebSocketServer({ noServer: true, maxPayload: MAX_MESSAGE_BYTES })
  private clients = new Map<WebSocket, ClientState>()
  private pingTimer: ReturnType<typeof setInterval>

  constructor(private auth: AuthService, private manager: ServerManager, private opts: WsHubOptions = {}) {
    this.pingTimer = setInterval(() => {
      for (const [ws, state] of this.clients) {
        if (!state.alive || !this.sessionUser(state)) {
          ws.terminate()
          this.clients.delete(ws)
          continue
        }
        state.alive = false
        ws.ping()
      }
    }, 30_000)
    this.pingTimer.unref?.()
  }

  /** Number of connected clients (drives lazy node bridge connections). */
  clientCount(): number {
    return this.clients.size
  }

  /** Number of clients subscribed to a channel (bridge unsubscribes idle console feeds). */
  subscriberCount(channel: string): number {
    let n = 0
    for (const state of this.clients.values()) if (state.subs.has(channel)) n++
    return n
  }

  handleUpgrade(req: IncomingMessage, socket: Duplex, head: Buffer) {
    let user: User
    let sessionId = ''
    const tokenAuth = Boolean(this.opts.nodeToken)
    if (this.opts.nodeToken) {
      // Node-agent mode: bearer token in the Authorization header only (a
      // ?token= query parameter would leak the secret into logs/proxies).
      const presented = bearerToken(req.headers.authorization)
      if (!presented || !tokenEquals(presented, this.opts.nodeToken)) {
        socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n')
        socket.destroy()
        return
      }
      user = NODE_AGENT_USER
    } else {
      const token = parseCookies(req.headers.cookie)[SESSION_COOKIE]
      const resolved = token ? this.auth.resolveSession(token) : null
      if (!resolved) {
        socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n')
        socket.destroy()
        return
      }
      user = resolved.user
      sessionId = resolved.session.id
    }
    this.wss.handleUpgrade(req, socket, head, (ws) => {
      const state: ClientState = {
        user,
        sessionId,
        subs: new Set(['servers', 'system']),
        alive: true,
        tokenAuth,
      }
      this.clients.set(ws, state)
      this.opts.onClientConnected?.()
      ws.on('pong', () => (state.alive = true))
      ws.on('close', () => this.clients.delete(ws))
      ws.on('error', () => {
        this.clients.delete(ws)
        ws.terminate()
      })
      ws.on('message', (raw) => {
        if (!this.sessionUser(state)) {
          this.clients.delete(ws)
          ws.terminate()
          return
        }
        try {
          const msg = JSON.parse(String(raw)) as { op?: string; channel?: string }
          if (typeof msg.channel !== 'string' || msg.channel.length > 100) return
          if (msg.op === 'sub') {
            if (this.allowChannel(state.user, msg.channel, state.tokenAuth)) {
              state.subs.add(msg.channel)
              ws.send(JSON.stringify({ t: 'sub-ok', channel: msg.channel }))
              this.opts.onSubscribe?.(msg.channel)
            } else {
              ws.send(JSON.stringify({ t: 'sub-denied', channel: msg.channel }))
            }
          } else if (msg.op === 'unsub') {
            state.subs.delete(msg.channel)
          }
        } catch {
          /* ignore malformed frames */
        }
      })
      ws.send(JSON.stringify({ t: 'hello', user: state.user.username }))
    })
  }

  private sessionUser(state: ClientState): User | null {
    // Token clients have no session — the static token was verified at the
    // handshake and lives exactly as long as the agent process (see ClientState).
    if (state.tokenAuth) return state.user
    return this.auth.sessionUser(state.sessionId, state.user.id)
  }

  private allowChannel(user: User, channel: string, tokenAuth = false): boolean {
    if (tokenAuth) return true // the panel token is admin-equivalent on an agent
    if (channel === 'servers' || channel === 'system') return true
    // Global audit stream mirrors the admin-only REST endpoint.
    if (channel === 'audit') return this.auth.users.get(user.id)?.role === 'admin'
    const consoleMatch = channel.match(/^console:(.+)$/)
    if (consoleMatch) return this.canAccess(user, consoleMatch[1], 'server.console')
    return false
  }

  private canAccess(user: User, serverId: string, perm: ServerPermission): boolean {
    // Mirrored remote servers are authorized with the same panel-side
    // permission model as local ones (the mirror carries ownerId; subusers
    // reference the same server id).
    const server = this.manager.servers.get(serverId) ?? this.opts.remoteLookup?.(serverId)
    if (!server) return false
    return this.canAccessServer(user, server, perm)
  }

  private canAccessServer(user: User, server: GameServer, perm: ServerPermission, tokenAuth = false): boolean {
    if (tokenAuth) return true
    const fresh = this.auth.users.get(user.id)
    if (!fresh) return false
    return this.auth.canAccessServer(fresh, server, perm)
  }

  /**
   * Broadcast to a channel; passing a server (or its id) triggers per-user
   * visibility checks. Events about already-deleted servers MUST pass the full
   * object — an id lookup would fail and silently drop the event for everyone.
   */
  broadcast(channel: string, payload: Record<string, unknown>, server?: string | GameServer, perm: ServerPermission = 'server.view') {
    const target = typeof server === 'string' ? this.manager.servers.get(server) ?? this.opts.remoteLookup?.(server) : server
    if (server && !target) return
    const message = JSON.stringify(payload)
    for (const [ws, state] of this.clients) {
      if (ws.readyState !== WebSocket.OPEN) continue
      if (!state.subs.has(channel)) continue
      // Long-lived sockets must not survive logout/session revocation, and
      // channel authorization (notably admin-only audit) can change at runtime.
      const freshUser = this.sessionUser(state)
      if (!freshUser || !this.allowChannel(freshUser, channel, state.tokenAuth)) {
        this.clients.delete(ws)
        ws.terminate()
        continue
      }
      // Re-check access on every message (not just at subscribe time) so a
      // revoked permission stops delivery immediately for an open socket.
      if (target && !this.canAccessServer(freshUser, target, perm, state.tokenAuth)) continue
      // ws queues sends in process memory when a client stops reading. A busy
      // game console must not be able to grow that queue until the panel dies.
      if (ws.bufferedAmount > MAX_BUFFERED_OUTPUT) {
        this.clients.delete(ws)
        ws.terminate()
        continue
      }
      try {
        ws.send(message)
      } catch {
        this.clients.delete(ws)
        ws.terminate()
      }
    }
  }

  close() {
    clearInterval(this.pingTimer)
    // Shutdown must not wait for clients that ignore the close handshake.
    for (const ws of this.clients.keys()) ws.terminate()
    this.clients.clear()
    this.wss.close()
  }
}
