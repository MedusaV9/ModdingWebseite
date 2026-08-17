/**
 * Singleton multiplexed WebSocket with auto-reconnect and channel re-subscribe.
 */
export type WsMessage = {
  t: string
  serverId?: string
  [key: string]: unknown
}

type Handler = (msg: WsMessage) => void

class WsClient {
  private ws: WebSocket | null = null
  private channels = new Set<string>(['servers', 'system'])
  private handlers = new Set<Handler>()
  private reconnectDelay = 1000
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null
  private closedByUs = false
  private connecting = false
  connected = false

  connect() {
    if (this.ws || this.connecting) return
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = null
    }
    this.connecting = true
    this.closedByUs = false
    const proto = location.protocol === 'https:' ? 'wss' : 'ws'
    const ws = new WebSocket(`${proto}://${location.host}/api/ws`)
    this.ws = ws
    ws.onopen = () => {
      this.connecting = false
      this.connected = true
      this.reconnectDelay = 1000
      for (const channel of this.channels) ws.send(JSON.stringify({ op: 'sub', channel }))
      this.emit({ t: '_open' })
    }
    ws.onmessage = (event) => {
      try {
        this.emit(JSON.parse(event.data as string) as WsMessage)
      } catch {
        /* ignore */
      }
    }
    ws.onclose = () => {
      this.ws = null
      this.connecting = false
      if (this.connected) this.emit({ t: '_close' })
      this.connected = false
      if (!this.closedByUs) {
        this.reconnectTimer = setTimeout(() => {
          this.reconnectTimer = null
          this.connect()
        }, this.reconnectDelay)
        this.reconnectDelay = Math.min(this.reconnectDelay * 1.8, 12_000)
      }
    }
    ws.onerror = () => ws.close()
  }

  disconnect() {
    this.closedByUs = true
    // Also cancel a pending backoff reconnect — otherwise logging out during
    // the backoff window would spawn an unauthenticated reconnect loop.
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer)
      this.reconnectTimer = null
    }
    const ws = this.ws
    if (ws) {
      // Detach handlers before closing: a socket closed while still CONNECTING
      // fires onclose asynchronously, and letting it run would either leave
      // `connecting` stuck (dropping the next connect()) or emit a spurious
      // reconnect. Clearing them makes disconnect fully synchronous.
      ws.onopen = ws.onmessage = ws.onclose = ws.onerror = null
      try {
        ws.close()
      } catch {
        /* ignore */
      }
    }
    this.ws = null
    this.connecting = false
    this.connected = false
  }

  subscribe(channel: string) {
    if (this.channels.has(channel)) return
    this.channels.add(channel)
    if (this.ws?.readyState === WebSocket.OPEN) this.ws.send(JSON.stringify({ op: 'sub', channel }))
  }

  unsubscribe(channel: string) {
    if (!this.channels.delete(channel)) return
    if (this.ws?.readyState === WebSocket.OPEN) this.ws.send(JSON.stringify({ op: 'unsub', channel }))
  }

  onMessage(handler: Handler): () => void {
    this.handlers.add(handler)
    return () => this.handlers.delete(handler)
  }

  private emit(msg: WsMessage) {
    for (const handler of this.handlers) handler(msg)
  }
}

export const wsClient = new WsClient()
