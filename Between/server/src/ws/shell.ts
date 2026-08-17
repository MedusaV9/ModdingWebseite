/**
 * Interactive shell sessions into running docker-runtime containers: one
 * WebSocket per session, bridged to a `docker exec` TTY running /bin/sh.
 * Gated on 'server.config' — a shell is arbitrary-code-equivalent, the same
 * trust level as the start-command override. Never exposes a host shell.
 */
import type { IncomingMessage } from 'node:http'
import type { Duplex } from 'node:stream'
import { StringDecoder } from 'node:string_decoder'
import { WebSocketServer, WebSocket } from 'ws'
import { AuthService, parseCookies, SESSION_COOKIE } from '../auth/service.ts'
import type { ServerManager } from '../servers/manager.ts'
import type { DockerService } from '../services/docker.ts'
import type { DockerAttachment } from '../lib/docker.ts'

export const SHELL_PATH_RE = /^\/api\/servers\/([^/]+)\/shell$/

/**
 * Disconnect a client whose socket has this much unsent shell output queued —
 * a container can emit output (`yes`) far faster than a slow client reads it,
 * and ws buffers the backlog in panel memory without any bound of its own.
 */
const MAX_BUFFERED_OUTPUT = 4 * 1024 * 1024
/** Stdin frames are keystrokes/pastes — reject anything absurdly large. */
const MAX_MESSAGE_BYTES = 4 * 1024 * 1024

interface ShellSession {
  attachment: DockerAttachment | null
  alive: boolean
  sessionId: string
  userId: string
  serverId: string
}

export class ShellHub {
  private wss = new WebSocketServer({ noServer: true, maxPayload: MAX_MESSAGE_BYTES })
  private sessions = new Map<WebSocket, ShellSession>()
  private pingTimer: ReturnType<typeof setInterval>

  constructor(
    private auth: AuthService,
    private manager: ServerManager,
    private docker: DockerService,
  ) {
    this.pingTimer = setInterval(() => {
      for (const [ws, session] of this.sessions) {
        // Reap dead sockets AND sessions whose permission was revoked — a
        // shell must not outlive its authorization (mirrors the console
        // hub's per-message re-validation).
        if (!session.alive || !this.allowed(session)) {
          session.attachment?.close()
          this.sessions.delete(ws)
          ws.terminate()
          continue
        }
        session.alive = false
        ws.ping()
      }
    }, 30_000)
    this.pingTimer.unref?.()
  }

  /** Re-checked while a session lives: user still exists, is not suspended and still holds server.config. */
  private allowed(session: ShellSession): boolean {
    const user = this.auth.sessionUser(session.sessionId, session.userId)
    const server = this.manager.servers.get(session.serverId)
    if (!user || !server) return false
    return this.auth.canAccessServer(user, server, 'server.config')
  }

  handleUpgrade(req: IncomingMessage, socket: Duplex, head: Buffer) {
    const token = parseCookies(req.headers.cookie)[SESSION_COOKIE]
    const resolved = token ? this.auth.resolveSession(token) : null
    if (!resolved) {
      socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n')
      socket.destroy()
      return
    }
    const match = (req.url ?? '').split('?')[0].match(SHELL_PATH_RE)
    if (!match) {
      socket.write('HTTP/1.1 400 Bad Request\r\n\r\n')
      socket.destroy()
      return
    }
    let serverId: string
    try {
      serverId = decodeURIComponent(match[1])
    } catch {
      // Malformed percent-escapes ("%zz") must get a readable refusal, not
      // fall through to the process-level catch-all.
      socket.write('HTTP/1.1 400 Bad Request\r\n\r\n')
      socket.destroy()
      return
    }
    const server = this.manager.servers.get(serverId)
    if (!server || !this.auth.canAccessServer(resolved.user, server, 'server.config')) {
      socket.write('HTTP/1.1 403 Forbidden\r\n\r\n')
      socket.destroy()
      return
    }
    // Runtime/running preconditions are checked *after* the upgrade so the UI
    // receives a readable {t:'error'} instead of a bare failed handshake.
    this.wss.handleUpgrade(req, socket, head, (ws) => {
      // The app-level upgrade guard cannot see async rejections — a reject
      // escaping here would crash the process, so terminate the session instead.
      this.startSession(ws, serverId, resolved.user.id, resolved.session.id).catch((err) => {
        console.error('[shell] session setup failed:', err)
        this.sessions.get(ws)?.attachment?.close()
        this.sessions.delete(ws)
        ws.terminate()
      })
    })
  }

  private async startSession(ws: WebSocket, serverId: string, userId: string, sessionId: string) {
    const session: ShellSession = { attachment: null, alive: true, sessionId, userId, serverId }
    this.sessions.set(ws, session)
    ws.on('pong', () => (session.alive = true))
    ws.on('close', () => {
      this.sessions.get(ws)?.attachment?.close()
      this.sessions.delete(ws)
    })
    ws.on('error', () => {
      this.sessions.get(ws)?.attachment?.close()
      this.sessions.delete(ws)
    })

    const fail = (message: string) => {
      if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ t: 'error', message }))
      ws.close()
    }

    const instance = this.manager.instances.get(serverId)
    if (!instance) return fail('server not found')
    if (instance.runtime !== 'docker') return fail('the shell is only available for docker-runtime servers')
    const containerId = instance.handle?.containerId
    if (!containerId || !['starting', 'running', 'stopping'].includes(instance.status))
      return fail('server is not running — start it first')

    let execId: string
    let attachment: DockerAttachment
    // Per-session decoder: a multi-byte UTF-8 char split across stream chunks
    // must not turn into replacement chars at the chunk boundary.
    const decoder = new StringDecoder('utf8')
    try {
      execId = await this.docker.client.execCreate(containerId, ['/bin/sh'])
      attachment = await this.docker.client.execStart(execId, {
        onData: (chunk) => {
          if (ws.readyState !== WebSocket.OPEN) return
          const text = decoder.write(chunk)
          if (text) ws.send(text)
          // Backpressure: ws buffers unsent output in panel memory without
          // bound — drop the session instead of buffering a runaway flood.
          if (ws.bufferedAmount > MAX_BUFFERED_OUTPUT) ws.terminate()
        },
        onClose: () => ws.close(),
      })
    } catch {
      return fail('could not open a shell — no /bin/sh in this image?')
    }
    // The client may have vanished while the exec was being set up.
    if (!this.sessions.has(ws) || ws.readyState !== WebSocket.OPEN) {
      attachment.close()
      return
    }
    session.attachment = attachment

    ws.on('message', (raw) => {
      try {
        const msg = JSON.parse(String(raw)) as { op?: string; data?: unknown; cols?: unknown; rows?: unknown }
        if (msg.op === 'stdin' && typeof msg.data === 'string') {
          // The reaper sweeps revoked sessions every 30s, but input must stop
          // immediately once server.config is taken away.
          if (!this.allowed(session)) return ws.close()
          attachment.write(msg.data)
        } else if (msg.op === 'resize') {
          if (!this.allowed(session)) return ws.close()
          const cols = Number(msg.cols)
          const rows = Number(msg.rows)
          if (Number.isInteger(cols) && Number.isInteger(rows) && cols > 0 && rows > 0 && cols <= 1000 && rows <= 1000) {
            void this.docker.client.execResize(execId, rows, cols)
          }
        }
      } catch {
        /* ignore malformed frames */
      }
    })
    ws.send(JSON.stringify({ t: 'ready' }))
  }

  close() {
    clearInterval(this.pingTimer)
    for (const [ws, session] of this.sessions) {
      session.attachment?.close()
      ws.terminate()
    }
    this.sessions.clear()
    this.wss.close()
  }
}
