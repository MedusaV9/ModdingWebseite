/**
 * HTTP(S) download helper built on global fetch, streaming to disk with
 * progress callbacks. Follows redirects, supports checksum verification.
 */
import fs from 'node:fs'
import path from 'node:path'
import crypto from 'node:crypto'
import { Readable } from 'node:stream'
import { pipeline } from 'node:stream/promises'
import { Transform } from 'node:stream'

export interface DownloadOptions {
  onProgress?: (info: { bytes: number; totalBytes: number | null; pct: number | null }) => void
  sha256?: string
  /** Takes precedence over sha256 when both are given. */
  sha512?: string
  timeoutMs?: number
  headers?: Record<string, string>
  /** External abort (e.g. server deleted mid-install). */
  signal?: AbortSignal
}

export async function downloadFile(url: string, destFile: string, opts: DownloadOptions = {}): Promise<{ bytes: number }> {
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(new Error('download timed out')), opts.timeoutMs ?? 30 * 60 * 1000)
  timeout.unref?.()
  const signal = opts.signal ? AbortSignal.any([controller.signal, opts.signal]) : controller.signal
  const tmp = `${destFile}.part`
  try {
    const res = await fetch(url, {
      redirect: 'follow',
      signal,
      headers: { 'user-agent': 'Between-Panel/0.1 (+https://github.com)', ...opts.headers },
    })
    if (!res.ok || !res.body) throw new Error(`download failed: HTTP ${res.status} ${res.statusText} for ${url}`)
    const totalBytes = res.headers.get('content-length') ? parseInt(res.headers.get('content-length')!, 10) : null

    fs.mkdirSync(path.dirname(destFile), { recursive: true })
    const expectedHash = opts.sha512 ?? opts.sha256
    const hash = crypto.createHash(opts.sha512 ? 'sha512' : 'sha256')
    let bytes = 0
    let lastReport = 0
    const counter = new Transform({
      transform(chunk: Buffer, _enc, cb) {
        bytes += chunk.length
        hash.update(chunk)
        const now = Date.now()
        if (now - lastReport > 500) {
          lastReport = now
          opts.onProgress?.({
            bytes,
            totalBytes,
            pct: totalBytes ? Math.round((bytes / totalBytes) * 100) : null,
          })
        }
        cb(null, chunk)
      },
    })
    await pipeline(Readable.fromWeb(res.body as import('stream/web').ReadableStream), counter, fs.createWriteStream(tmp), { signal })
    if (expectedHash) {
      const digest = hash.digest('hex')
      if (digest.toLowerCase() !== expectedHash.toLowerCase()) {
        throw new Error(`checksum mismatch for ${url}: expected ${expectedHash}, got ${digest}`)
      }
    }
    fs.renameSync(tmp, destFile)
    opts.onProgress?.({ bytes, totalBytes, pct: 100 })
    return { bytes }
  } catch (err) {
    // Never leave partial .part files behind on failed/aborted downloads.
    try {
      fs.rmSync(tmp, { force: true })
    } catch {
      /* best effort */
    }
    throw err
  } finally {
    clearTimeout(timeout)
  }
}

export async function fetchJson<T = unknown>(url: string, timeoutMs = 30000): Promise<T> {
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(new Error('request timed out')), timeoutMs)
  timeout.unref?.()
  try {
    const res = await fetch(url, {
      signal: controller.signal,
      headers: { 'user-agent': 'Between-Panel/0.1', accept: 'application/json' },
    })
    if (!res.ok) throw new Error(`HTTP ${res.status} ${res.statusText} for ${url}`)
    return (await res.json()) as T
  } finally {
    clearTimeout(timeout)
  }
}
