/**
 * Outbound notifications — Discord webhook embeds and a generic JSON webhook
 * (n8n / Zapier / custom receivers) for server events.
 * Fire-and-forget with basic rate limiting; failures never break the panel.
 */
import type { Collection } from '../lib/jsonstore.ts'
import type { PanelSettings } from '../types.ts'
import { PANEL_VERSION } from '../config.ts'

const COLORS = { crash: 0xef4444, power: 0x6366f1, backup: 0x22c55e, info: 0x94a3b8 }
const WEBHOOK_TIMEOUT_MS = 10_000
const MAX_WEBHOOK_URL_LENGTH = 500

export type NotifyKind = 'crash' | 'power' | 'backup'

/** Optional structured context for an event — carried by the generic webhook. */
export interface NotifyMeta {
  server?: { id: string; name: string; blueprintId: string } | null
  data?: Record<string, unknown>
}

/**
 * Generic webhook payload — a STABLE contract for external receivers. Only
 * make additive changes; never rename or remove fields.
 *   event      'crash' | 'power' | 'backup' | 'test'
 *   timestamp  ISO 8601, when the event fired
 *   panel      the configured panel name
 *   server     { id, name, blueprintId } or null for panel-level events
 *   data       event details; always includes human-readable title + message
 */
export interface WebhookPayload {
  event: string
  timestamp: string
  panel: string
  server: { id: string; name: string; blueprintId: string } | null
  data: Record<string, unknown>
}

/**
 * Validate an admin-supplied generic webhook URL; returns an error message or
 * null when acceptable. Deliberately shape-only (parseable, http/https,
 * length cap): private/LAN receivers (e.g. http://192.168.1.10:5678/webhook
 * for n8n) are the primary use case on a self-hosted panel, so unlike
 * nettrust.ts this must NOT reject private hosts or non-standard ports. The
 * setting is admin-only — the same trust level as the Discord webhook URL.
 */
export function validateWebhookUrl(raw: string): string | null {
  if (raw.length > MAX_WEBHOOK_URL_LENGTH) return `webhook URL is too long (max ${MAX_WEBHOOK_URL_LENGTH} characters)`
  let url: URL
  try {
    url = new URL(raw)
  } catch {
    return 'invalid webhook URL'
  }
  if (url.protocol !== 'http:' && url.protocol !== 'https:') return 'webhook URL must use http:// or https://'
  return null
}

export class Notifier {
  private lastSent = 0
  private queue: { title: string; description: string; kind: keyof typeof COLORS }[] = []
  private flushing = false
  private webhookQueue: WebhookPayload[] = []
  private webhookFlushing = false
  private stopped = false
  private stopController = new AbortController()
  private readonly webhookTimeoutMs: number

  constructor(
    private settings: Collection<PanelSettings>,
    opts: { webhookTimeoutMs?: number } = {},
  ) {
    this.webhookTimeoutMs = opts.webhookTimeoutMs ?? WEBHOOK_TIMEOUT_MS
  }

  private config(): PanelSettings | undefined {
    return this.settings.all()[0]
  }

  notify(kind: NotifyKind, title: string, description: string, meta: NotifyMeta = {}) {
    if (this.stopped) return
    const cfg = this.config()
    if (cfg?.discordWebhookUrl) {
      const events = cfg.discordEvents ?? { crash: true, power: false, backup: false }
      if (events[kind]) {
        this.queue.push({ kind, title, description })
        if (this.queue.length > 20) this.queue.splice(0, this.queue.length - 20)
        void this.flush()
      }
    }
    if (cfg?.webhookUrl) {
      const events = cfg.webhookEvents ?? { crash: true, power: false, backup: false }
      if (events[kind]) {
        this.webhookQueue.push(this.buildPayload(kind, title, description, meta))
        if (this.webhookQueue.length > 20) this.webhookQueue.splice(0, this.webhookQueue.length - 20)
        void this.flushWebhook()
      }
    }
  }

  private buildPayload(event: string, title: string, message: string, meta: NotifyMeta): WebhookPayload {
    return {
      event,
      timestamp: new Date().toISOString(),
      panel: this.config()?.panelName ?? 'Between',
      server: meta.server ?? null,
      // Titles/descriptions carry Discord **markdown** — strip it for plain receivers.
      data: { title, message: message.replace(/\*\*/g, ''), ...meta.data },
    }
  }

  /** POST one payload — hard timeout, aborted on panel shutdown, no retry. */
  private async postWebhook(url: string, payload: WebhookPayload): Promise<Response> {
    return await fetch(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'user-agent': `Between-Panel/${PANEL_VERSION}` },
      body: JSON.stringify(payload),
      signal: AbortSignal.any([this.stopController.signal, AbortSignal.timeout(this.webhookTimeoutMs)]),
    })
  }

  /** Deliver a `test` event to the configured webhook URL (admin test button). */
  async sendTestWebhook(): Promise<{ ok: boolean; status?: number; error?: string }> {
    const url = this.config()?.webhookUrl
    if (!url) return { ok: false, error: 'no webhook URL configured' }
    const payload = this.buildPayload('test', 'Test notification', 'The Between webhook is configured correctly.', {})
    try {
      const res = await this.postWebhook(url, payload)
      await res.body?.cancel()
      if (!res.ok) return { ok: false, status: res.status, error: `HTTP ${res.status}` }
      return { ok: true, status: res.status }
    } catch (err) {
      return { ok: false, error: (err as Error).message }
    }
  }

  /** Sequential generic-webhook delivery — bounded queue, one error line per failure. */
  private async flushWebhook() {
    if (this.webhookFlushing) return
    this.webhookFlushing = true
    try {
      while (!this.stopped && this.webhookQueue.length > 0) {
        const payload = this.webhookQueue.shift()!
        const url = this.config()?.webhookUrl
        if (!url) return
        try {
          const res = await this.postWebhook(url, payload)
          await res.body?.cancel()
          if (!res.ok && !this.stopped) console.error(`[notify] generic webhook failed: HTTP ${res.status}`)
        } catch (err) {
          if (!this.stopped) console.error('[notify] generic webhook failed:', (err as Error).message)
        }
      }
    } finally {
      this.webhookFlushing = false
    }
  }

  private async flush() {
    if (this.flushing) return
    this.flushing = true
    try {
      while (!this.stopped && this.queue.length > 0) {
        const wait = Math.max(0, this.lastSent + 2000 - Date.now())
        if (wait > 0) await this.wait(wait)
        if (this.stopped) return
        const item = this.queue.shift()!
        const url = this.config()?.discordWebhookUrl
        if (!url) return
        this.lastSent = Date.now()
        try {
          await fetch(url, {
            method: 'POST',
            headers: { 'content-type': 'application/json' },
            body: JSON.stringify({
              username: 'Between',
              embeds: [
                {
                  title: item.title.slice(0, 250),
                  description: item.description.slice(0, 2000),
                  color: COLORS[item.kind],
                  timestamp: new Date().toISOString(),
                  footer: { text: 'Between Panel' },
                },
              ],
            }),
            signal: AbortSignal.any([this.stopController.signal, AbortSignal.timeout(WEBHOOK_TIMEOUT_MS)]),
          })
        } catch (err) {
          if (!this.stopped) console.error('[notify] discord webhook failed:', (err as Error).message)
        }
      }
    } finally {
      this.flushing = false
    }
  }

  private async wait(ms: number): Promise<void> {
    const signal = this.stopController.signal
    if (signal.aborted) return
    await new Promise<void>((resolve) => {
      const timer = setTimeout(done, ms)
      timer.unref?.()
      const onAbort = () => {
        clearTimeout(timer)
        done()
      }
      function done() {
        signal.removeEventListener('abort', onAbort)
        resolve()
      }
      signal.addEventListener('abort', onAbort, { once: true })
    })
  }

  stop(): void {
    this.stopped = true
    this.queue = []
    this.webhookQueue = []
    this.stopController.abort()
  }
}
