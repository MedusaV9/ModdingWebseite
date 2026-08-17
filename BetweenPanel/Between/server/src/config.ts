import path from 'node:path'
import fs from 'node:fs'
import os from 'node:os'
import { fileURLToPath } from 'node:url'

export const PANEL_VERSION = '0.1.0'

/** Minimum length for a node agent token — anything shorter is guessable. */
export const NODE_TOKEN_MIN_LENGTH = 16

const here = path.dirname(fileURLToPath(import.meta.url))

export interface PanelConfig {
  port: number
  host: string
  dataDir: string
  sessionTtlDays: number
  /** Where the built web UI lives (served in production). */
  webDistDir: string
  /**
   * Express `trust proxy` value. Default 'loopback' trusts X-Forwarded-For only
   * from a local reverse proxy, so a directly-connecting client cannot spoof
   * its IP to bypass IP-based login rate limiting.
   */
  trustProxy: boolean | number | string
  /**
   * 'panel' (default) = the full web panel. 'node' (BETWEEN_MODE=node) = a
   * headless agent managing game servers on a remote machine for a panel:
   * same REST/WS surface, but auth is a single bearer token
   * (BETWEEN_NODE_TOKEN), there are no users/sessions/setup and no web UI.
   */
  mode: 'panel' | 'node'
  /** Shared secret for node mode (BETWEEN_NODE_TOKEN). Required when mode==='node'. */
  nodeToken: string | null
  /** Display name this node reports to the panel (BETWEEN_NODE_NAME, default hostname). */
  nodeName: string
  /** Panel-side: how often registered nodes are health-polled/reconciled (ms). */
  nodePollMs: number
  /**
   * Override the SteamCMD executable (BETWEEN_STEAMCMD_BIN). When set, the
   * bundled download/bootstrap is skipped and this binary is used as-is —
   * used by tests to point at scripts/fake-steamcmd.mjs and by hosts that
   * ship a system-wide steamcmd.
   */
  steamcmdBin: string | null
}

function parseTrustProxy(raw: string | undefined): boolean | number | string {
  if (raw === undefined || raw.trim() === '') return 'loopback'
  const v = raw.trim()
  if (v === 'true') return true
  if (v === 'false') return false
  const n = Number(v)
  return Number.isInteger(n) && n >= 0 ? n : v
}

function intEnv(name: string, fallback: number): number {
  const v = process.env[name]
  if (!v) return fallback
  const n = parseInt(v, 10)
  return Number.isFinite(n) ? n : fallback
}

export function loadConfig(): PanelConfig {
  const dataDir = path.resolve(process.env.BETWEEN_DATA ?? path.join(here, '..', '..', 'data'))
  fs.mkdirSync(dataDir, { recursive: true })
  return {
    port: intEnv('BETWEEN_PORT', 8484),
    host: process.env.BETWEEN_HOST ?? '0.0.0.0',
    dataDir,
    sessionTtlDays: intEnv('BETWEEN_SESSION_TTL_DAYS', 7),
    webDistDir: path.resolve(process.env.BETWEEN_WEB_DIST ?? path.join(here, '..', '..', 'web', 'dist')),
    trustProxy: parseTrustProxy(process.env.BETWEEN_TRUST_PROXY),
    mode: process.env.BETWEEN_MODE === 'node' ? 'node' : 'panel',
    nodeToken: process.env.BETWEEN_NODE_TOKEN?.trim() || null,
    nodeName: process.env.BETWEEN_NODE_NAME?.trim() || os.hostname(),
    nodePollMs: Math.max(1000, intEnv('BETWEEN_NODE_POLL_MS', 10_000)),
    steamcmdBin: process.env.BETWEEN_STEAMCMD_BIN?.trim() || null,
  }
}
