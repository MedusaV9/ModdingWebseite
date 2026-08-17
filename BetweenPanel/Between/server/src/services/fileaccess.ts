/**
 * File access over a standard protocol (SFTP) — config model + provider seam.
 *
 * How the established panels do it (documented in AMP_PARITY_PLAN.md §4):
 * - **Pterodactyl**: the Wings daemon embeds its own SFTP server (default
 *   port 2022, no OpenSSH involved). Login is `panelUsername.serverShortId`
 *   with the panel password (or per-user SSH keys); every session is jailed
 *   to that one server's directory and the panel's permission model is
 *   enforced per operation.
 * - **AMP**: each instance's application process embeds an SFTP-over-SSH
 *   listener on its own port; AMP panel credentials log in directly and see
 *   only that instance's root.
 *
 * Between follows the same pattern in a later wave: ONE embedded, dependency
 * free SFTP listener per panel/agent process, credentials scoped per
 * user × server, sessions sandboxed through the exact same `safeJoin` root
 * as the web file manager, and `server.files.read` / `server.files.write`
 * re-checked on every operation (a revoked subuser must lose an open
 * session, like the WebSocket hubs do).
 *
 * This module ships the stable seam now:
 * - `FileAccessConfig` — persisted in PanelSettings (`settings.sftp`),
 * - `FileAccessProvider` — the interface the real listener will implement,
 * - `SftpPlaceholderProvider` — honest stand-in: it reports
 *   `implemented: false` and refuses to enable, instead of pretending.
 *
 * The API surface (`GET/PATCH /api/fileaccess`) and the shutdown wiring in
 * app.ts stay byte-identical when the real provider lands — only the
 * provider instance changes.
 */
import type { Collection } from '../lib/jsonstore.ts'
import type { PanelSettings } from '../types.ts'

export interface FileAccessConfig {
  /** Master switch — refused by the placeholder provider (v1). */
  enabled: boolean
  /** Listen port. 2022 mirrors the Pterodactyl/Wings convention. */
  port: number
  /** Bind address; 0.0.0.0 = all interfaces (panels usually sit on a LAN). */
  bind: string
}

export const FILE_ACCESS_DEFAULTS: Readonly<FileAccessConfig> = Object.freeze({
  enabled: false,
  port: 2022,
  bind: '0.0.0.0',
})

export interface FileAccessStatus {
  protocol: 'sftp'
  /** False while only the placeholder provider ships. */
  implemented: boolean
  running: boolean
  config: FileAccessConfig
  /** Human-readable explanation when not running. */
  reason?: string
}

/**
 * What a concrete protocol listener must provide. `start` receives the full
 * config and must be idempotent per running state; `stop` must release the
 * port and terminate open sessions (shutdown-invariant: every background
 * resource needs an owner and a stop path).
 */
export interface FileAccessProvider {
  readonly protocol: 'sftp'
  readonly implemented: boolean
  start(config: FileAccessConfig): Promise<void>
  stop(): Promise<void>
  running(): boolean
}

/** Honest placeholder until the embedded SFTP listener lands (wave 2). */
export class SftpPlaceholderProvider implements FileAccessProvider {
  readonly protocol = 'sftp' as const
  readonly implemented = false

  start(): Promise<void> {
    return Promise.reject(new Error('SFTP support is not implemented yet — it arrives in a later wave'))
  }

  stop(): Promise<void> {
    return Promise.resolve()
  }

  running(): boolean {
    return false
  }
}

export class FileAccessService {
  constructor(
    private settings: Collection<PanelSettings>,
    private provider: FileAccessProvider = new SftpPlaceholderProvider(),
  ) {}

  /** Effective config: persisted values over defaults (missing = defaults). */
  config(): FileAccessConfig {
    const stored = this.settings.all()[0]?.sftp
    return { ...FILE_ACCESS_DEFAULTS, ...(stored ?? {}) }
  }

  status(): FileAccessStatus {
    const config = this.config()
    const running = this.provider.running()
    let reason: string | undefined
    if (!this.provider.implemented) reason = 'SFTP support arrives in a later wave — the web file manager covers all file operations today'
    else if (!config.enabled) reason = 'disabled in the panel settings'
    return { protocol: this.provider.protocol, implemented: this.provider.implemented, running, config, ...(reason ? { reason } : {}) }
  }

  /**
   * Validate + persist a config patch, then reconcile the provider (start,
   * stop or restart). Returns problems instead of throwing so the API can
   * 400 without persisting anything.
   */
  async applyConfig(patch: Partial<FileAccessConfig>): Promise<{ ok: boolean; problems: string[] }> {
    const problems: string[] = []
    const next = { ...this.config() }
    if (patch.enabled !== undefined) next.enabled = Boolean(patch.enabled)
    if (patch.port !== undefined) {
      const port = Number(patch.port)
      if (!Number.isInteger(port) || port < 1 || port > 65535) problems.push('port must be an integer between 1 and 65535')
      else next.port = port
    }
    if (patch.bind !== undefined) {
      const bind = String(patch.bind).trim()
      // Shape-only on purpose (admin-only setting, LAN binds are the point).
      if (!bind || bind.length > 64 || /\s/.test(bind)) problems.push('bind must be a host address without whitespace (max 64 chars)')
      else next.bind = bind
    }
    if (next.enabled && !this.provider.implemented)
      problems.push('SFTP support is not implemented yet — it arrives in a later wave')
    if (problems.length > 0) return { ok: false, problems }

    const settings = this.settings.all()[0]
    if (settings) this.settings.update(settings.id, { sftp: next })

    // Reconcile the provider with the persisted config.
    if (this.provider.running()) await this.provider.stop()
    if (next.enabled) await this.provider.start(next)
    return { ok: true, problems: [] }
  }

  /** Shutdown path — owned by app.stop(), joins open sessions. */
  async stop(): Promise<void> {
    await this.provider.stop()
  }
}
