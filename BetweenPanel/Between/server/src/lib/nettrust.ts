/**
 * SSRF-hardened outbound HTTP for URLs supplied by (admin) users — e.g. the
 * "import egg from URL" flow. Hand-rolled on global fetch + node:dns, no deps.
 *
 * Defense layers:
 *  1. assertPublicHttpUrl() — synchronous: only http:/https:, only standard
 *     ports, no localhost-ish hostnames, no private/loopback/link-local/
 *     reserved IP literals (IPv4 + IPv6, incl. v4-mapped).
 *  2. fetchPublicJson() — resolves the hostname via DNS and rejects when any
 *     resolved address is non-public, follows redirects manually so every hop
 *     is re-validated, enforces a hard timeout and a response size cap.
 */
import dns from 'node:dns/promises'

/** Standard web ports only — egg links live on public HTTPS hosts. */
const ALLOWED_PORTS = new Set(['', '80', '443'])

function parseIpv4(host: string): number[] | null {
  const m = host.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/)
  if (!m) return null
  const octets = m.slice(1).map(Number)
  return octets.every((o) => o <= 255) ? octets : null
}

function isPrivateIpv4(octets: number[]): boolean {
  const [a, b] = octets
  if (a === 0) return true // 0.0.0.0/8 ("this network")
  if (a === 10) return true // 10/8
  if (a === 100 && b >= 64 && b <= 127) return true // 100.64/10 (CGNAT)
  if (a === 127) return true // 127/8 loopback
  if (a === 169 && b === 254) return true // 169.254/16 link-local (cloud metadata!)
  if (a === 172 && b >= 16 && b <= 31) return true // 172.16/12
  if (a === 192 && b === 0) return true // 192.0.0/24 + 192.0.2/24 (IETF/TEST-NET)
  if (a === 192 && b === 168) return true // 192.168/16
  if (a === 198 && (b === 18 || b === 19)) return true // 198.18/15 benchmarking
  if (a >= 224) return true // multicast + 240/4 reserved + broadcast
  return false
}

function isPrivateIpv6(host: string): boolean {
  const ip = host.toLowerCase()
  if (ip === '::' || ip === '::1') return true // unspecified + loopback
  // v4-mapped/translated (::ffff:1.2.3.4 or ::ffff:0102:0304) — check the embedded IPv4.
  const mapped = ip.match(/^::ffff:(.+)$/)
  if (mapped) {
    const v4 = parseIpv4(mapped[1])
    if (v4) return isPrivateIpv4(v4)
    return true // hex-encoded mapped form — reject rather than decode
  }
  const first = parseInt(ip.split(':')[0] || '0', 16)
  if ((first & 0xfe00) === 0xfc00) return true // fc00::/7 unique-local
  if ((first & 0xffc0) === 0xfe80) return true // fe80::/10 link-local
  if ((first & 0xff00) === 0xff00) return true // ff00::/8 multicast
  return false
}

/** True when the address (IPv4 dotted or IPv6) must not be fetched from. */
export function isPrivateAddress(address: string): boolean {
  const v4 = parseIpv4(address)
  if (v4) return isPrivateIpv4(v4)
  if (address.includes(':')) return isPrivateIpv6(address)
  return true // neither IPv4 nor IPv6 — not an address we can vouch for
}

/**
 * Validate that a user-supplied URL is a plausible public http(s) endpoint.
 * Synchronous checks only (scheme, port, hostname shape, IP literals) — DNS
 * resolution happens in fetchPublicJson. Throws with a clear message.
 */
export function assertPublicHttpUrl(rawUrl: string): URL {
  let url: URL
  try {
    url = new URL(String(rawUrl))
  } catch {
    throw new Error('not a valid URL')
  }
  if (url.protocol !== 'http:' && url.protocol !== 'https:')
    throw new Error(`only http:// and https:// URLs are allowed (got ${url.protocol.replace(/:$/, '')})`)
  if (!ALLOWED_PORTS.has(url.port)) throw new Error(`non-standard port ${url.port} is not allowed`)
  if (url.username || url.password) throw new Error('URLs with credentials are not allowed')

  const host = url.hostname.replace(/^\[|\]$/g, '') // strip IPv6 brackets
  if (host.length === 0) throw new Error('not a valid URL')
  if (host === 'localhost' || host.endsWith('.localhost') || host.endsWith('.local'))
    throw new Error('local hostnames are not allowed')
  // Single-label hostnames only resolve on intranets — a public egg URL always
  // has a registrable domain.
  if (!host.includes('.') && !host.includes(':')) throw new Error('hostname must be fully qualified')
  const v4 = parseIpv4(host)
  if (v4 && isPrivateIpv4(v4)) throw new Error('private or loopback addresses are not allowed')
  if (host.includes(':') && isPrivateIpv6(host)) throw new Error('private or loopback addresses are not allowed')
  return url
}

/** Reject hostnames whose DNS answers include any private/reserved address. */
async function assertResolvesPublic(hostname: string): Promise<void> {
  const host = hostname.replace(/^\[|\]$/g, '')
  if (parseIpv4(host) || host.includes(':')) return // IP literal — already checked syntactically
  let addresses: { address: string }[]
  try {
    addresses = await dns.lookup(host, { all: true, verbatim: true })
  } catch {
    throw new Error(`could not resolve host ${host}`)
  }
  if (addresses.length === 0) throw new Error(`could not resolve host ${host}`)
  for (const { address } of addresses) {
    if (isPrivateAddress(address)) throw new Error(`host ${host} resolves to a private address — refusing to fetch`)
  }
}

export interface FetchPublicJsonOptions {
  /** Hard wall-clock limit for the whole fetch (default 10s). */
  timeoutMs?: number
  /** Response size cap in bytes (default 2 MiB — eggs are tiny). */
  maxBytes?: number
  /** TEST ONLY: skip the private-host checks so tests can use 127.0.0.1. */
  allowPrivateHosts?: boolean
}

const DEFAULT_TIMEOUT_MS = 10_000
const DEFAULT_MAX_BYTES = 2 * 1024 * 1024
const MAX_REDIRECTS = 5

/**
 * Fetch a small JSON document from a public http(s) URL with SSRF checks on
 * the initial URL and every redirect hop. Throws Error with a user-facing
 * message on any failure; callers map it to HttpError 400.
 */
export async function fetchPublicJson(rawUrl: string, opts: FetchPublicJsonOptions = {}): Promise<unknown> {
  const timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS
  const maxBytes = opts.maxBytes ?? DEFAULT_MAX_BYTES
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(new Error('request timed out')), timeoutMs)
  timeout.unref?.()
  try {
    let url = opts.allowPrivateHosts ? new URL(rawUrl) : assertPublicHttpUrl(rawUrl)
    let res: Response
    // Manual redirect loop: fetch(redirect:'follow') would happily follow a
    // public URL redirecting to 169.254.169.254 — validate every hop instead.
    for (let hop = 0; ; hop++) {
      if (!opts.allowPrivateHosts) await assertResolvesPublic(url.hostname)
      res = await fetch(url, {
        redirect: 'manual',
        signal: controller.signal,
        headers: { 'user-agent': 'Between-Panel/0.1', accept: 'application/json' },
      })
      if (res.status < 300 || res.status >= 400) break
      const location = res.headers.get('location')
      if (!location) throw new Error(`redirect without a Location header (HTTP ${res.status})`)
      if (hop >= MAX_REDIRECTS) throw new Error('too many redirects')
      await res.body?.cancel()
      const next = new URL(location, url)
      url = opts.allowPrivateHosts ? next : assertPublicHttpUrl(next.href)
    }
    if (!res.ok) throw new Error(`HTTP ${res.status} ${res.statusText}`.trim())

    const declared = Number(res.headers.get('content-length'))
    if (Number.isFinite(declared) && declared > maxBytes)
      throw new Error(`response is too large (${declared} bytes, limit ${maxBytes})`)

    // Stream with a byte cap — content-length can lie or be absent.
    let received = 0
    const chunks: Buffer[] = []
    if (res.body) {
      const reader = res.body.getReader()
      for (;;) {
        const { done, value } = await reader.read()
        if (done) break
        received += value.byteLength
        if (received > maxBytes) {
          await reader.cancel()
          throw new Error(`response is too large (limit ${maxBytes} bytes)`)
        }
        chunks.push(Buffer.from(value))
      }
    }
    const text = Buffer.concat(chunks).toString('utf8')
    try {
      return JSON.parse(text) as unknown
    } catch {
      throw new Error('response is not valid JSON')
    }
  } catch (err) {
    // Abort reasons surface as DOMException/AbortError — unwrap to our message.
    if (controller.signal.aborted) throw new Error('request timed out')
    throw err
  } finally {
    clearTimeout(timeout)
  }
}
