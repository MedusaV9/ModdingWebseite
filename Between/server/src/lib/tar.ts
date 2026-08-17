/**
 * Minimal streaming tar / tar.gz extractor (ustar + GNU long names + pax
 * path records). Preserves file modes (important: SteamCMD's `steamcmd.sh`
 * must stay executable). Symlinks and hardlinks are skipped for safety.
 * Extraction is bounded by a cumulative byte budget and an entry-count
 * budget (see extractlimits.ts) so crafted archives cannot exhaust disk,
 * memory or CPU.
 */
import fs from 'node:fs'
import path from 'node:path'
import zlib from 'node:zlib'
import { sanitizeEntryName, safeJoin } from './paths.ts'
import { EXTRACT_LIMITS, fmtBytes } from './extractlimits.ts'

const BLOCK = 512

function parseOctal(buf: Buffer): number {
  const str = buf.toString('ascii').replace(/\u0000/g, '').trim()
  if (str.length === 0) return 0
  // GNU base-256 encoding for very large values
  if (buf[0] & 0x80) {
    let value = 0
    for (let i = 1; i < buf.length; i++) value = value * 256 + buf[i]
    return value
  }
  return parseInt(str, 8) || 0
}

function parsePaxRecords(content: string): Record<string, string> {
  const out: Record<string, string> = {}
  let i = 0
  while (i < content.length) {
    const sp = content.indexOf(' ', i)
    if (sp < 0) break
    const len = parseInt(content.slice(i, sp), 10)
    if (!Number.isFinite(len) || len <= 0) break
    const record = content.slice(sp + 1, i + len - 1)
    const eq = record.indexOf('=')
    if (eq > 0) out[record.slice(0, eq)] = record.slice(eq + 1)
    i += len
  }
  return out
}

export interface TarExtractOptions {
  gzip?: boolean
  onProgress?: (info: { files: number; currentFile: string }) => void
  /** Override the cumulative uncompressed-byte budget (mainly for tests). */
  maxBytes?: number
  /** Override the entry-count budget (mainly for tests). */
  maxEntries?: number
}

export async function extractTar(file: string, destDir: string, opts: TarExtractOptions = {}): Promise<{ files: number }> {
  const gzip = opts.gzip ?? /\.(tgz|tar\.gz)$/i.test(file)
  const maxBytes = opts.maxBytes ?? EXTRACT_LIMITS.maxBytes
  const maxEntries = opts.maxEntries ?? EXTRACT_LIMITS.maxEntries
  fs.mkdirSync(destDir, { recursive: true })

  let files = 0
  let buffer: Buffer = Buffer.alloc(0)
  let remaining = 0 // bytes left of current file body (incl. padding handling)
  let padding = 0
  let totalBody = 0 // cumulative uncompressed body bytes (bomb budget)
  let entryCount = 0
  let outFd: number | null = null
  let outPath: string | null = null
  let pendingLongName: string | null = null
  let paxPath: string | null = null
  // 'discard' consumes a body without buffering it (skipped/unsafe entries) —
  // buffering those would let one crafted entry hold gigabytes in memory.
  let collecting: { kind: 'longname' | 'pax' | 'discard'; chunks: Buffer[]; size: number } | null = null
  let sawEnd = false

  const closeOut = () => {
    if (outFd !== null) {
      fs.closeSync(outFd)
      outFd = null
    }
    outPath = null
  }

  const processHeader = (block: Buffer) => {
    if (block.every((b) => b === 0)) {
      sawEnd = true
      return
    }
    entryCount++
    if (entryCount > maxEntries) throw new Error(`archive has too many entries (limit ${maxEntries})`)
    const typeflag = String.fromCharCode(block[156])
    const size = parseOctal(block.subarray(124, 136))

    if (typeflag === 'L') {
      if (size > EXTRACT_LIMITS.maxMetaBytes)
        throw new Error(`tar long-name record too large (${fmtBytes(size)}, limit ${fmtBytes(EXTRACT_LIMITS.maxMetaBytes)})`)
      collecting = { kind: 'longname', chunks: [], size }
      remaining = size
      padding = (BLOCK - (size % BLOCK)) % BLOCK
      return
    }
    if (typeflag === 'x' || typeflag === 'g') {
      if (size > EXTRACT_LIMITS.maxMetaBytes)
        throw new Error(`tar pax record too large (${fmtBytes(size)}, limit ${fmtBytes(EXTRACT_LIMITS.maxMetaBytes)})`)
      collecting = { kind: 'pax', chunks: [], size }
      remaining = size
      padding = (BLOCK - (size % BLOCK)) % BLOCK
      return
    }

    let name = block.subarray(0, 100).toString('utf8').replace(/\u0000.*$/, '')
    const prefix = block.subarray(345, 500).toString('utf8').replace(/\u0000.*$/, '')
    if (prefix) name = `${prefix}/${name}`
    if (pendingLongName) {
      name = pendingLongName
      pendingLongName = null
    }
    if (paxPath) {
      name = paxPath
      paxPath = null
    }
    const mode = parseOctal(block.subarray(100, 108)) & 0o7777

    const clean = sanitizeEntryName(name)
    remaining = size
    padding = (BLOCK - (size % BLOCK)) % BLOCK

    if (!clean) {
      collecting = { kind: 'discard', chunks: [], size }
      return
    }

    if (typeflag === '5') {
      fs.mkdirSync(safeJoin(destDir, clean), { recursive: true })
      return
    }
    if (typeflag === '0' || typeflag === '\0' || typeflag === '') {
      const target = safeJoin(destDir, clean)
      fs.mkdirSync(path.dirname(target), { recursive: true })
      outFd = fs.openSync(target, 'w', process.platform === 'win32' ? undefined : mode || 0o644)
      outPath = target
      files++
      opts.onProgress?.({ files, currentFile: clean })
      if (size === 0) closeOut()
      return
    }
    // Symlinks ('2'), hardlinks ('1'), devices etc.: skip content safely.
    collecting = size > 0 ? { kind: 'discard', chunks: [], size } : null
  }

  try {
    await new Promise<void>((resolve, reject) => {
      const src = fs.createReadStream(file)
      const stream = gzip ? src.pipe(zlib.createGunzip()) : src
      src.on('error', reject)
      stream.on('error', reject)
      stream.on('data', (chunk: Buffer) => {
        try {
          buffer = buffer.length === 0 ? chunk : Buffer.concat([buffer, chunk])
          let pos = 0
          while (true) {
            if (remaining > 0 || padding > 0) {
              const want = remaining + padding
              const avail = buffer.length - pos
              const take = Math.min(want, avail)
              if (take <= 0) break
              const bodyTake = Math.min(remaining, take)
              if (bodyTake > 0) {
                // Budget covers every body byte (written or skipped): bounds
                // disk usage and stops gzip bombs from spinning the CPU forever.
                totalBody += bodyTake
                if (totalBody > maxBytes)
                  throw new Error(`archive too large: extraction exceeds ${fmtBytes(maxBytes)}`)
                const slice = buffer.subarray(pos, pos + bodyTake)
                if (collecting) {
                  if (collecting.kind !== 'discard') collecting.chunks.push(Buffer.from(slice))
                } else if (outFd !== null) {
                  fs.writeSync(outFd, slice)
                }
                remaining -= bodyTake
              }
              const padTake = take - bodyTake
              padding -= padTake
              pos += take
              if (remaining === 0 && padding === 0) {
                if (collecting) {
                  if (collecting.kind === 'longname') {
                    pendingLongName = Buffer.concat(collecting.chunks).toString('utf8').replace(/\u0000.*$/, '')
                  } else if (collecting.kind === 'pax') {
                    const records = parsePaxRecords(Buffer.concat(collecting.chunks).toString('utf8'))
                    if (records.path) paxPath = records.path
                  }
                  collecting = null
                }
                closeOut()
              }
              continue
            }
            if (buffer.length - pos < BLOCK) break
            const block = buffer.subarray(pos, pos + BLOCK)
            pos += BLOCK
            processHeader(block)
          }
          buffer = pos > 0 ? buffer.subarray(pos) : buffer
        } catch (err) {
          stream.removeAllListeners('data')
          src.destroy()
          reject(err)
        }
      })
      stream.on('end', () => {
        closeOut()
        if (!sawEnd && remaining > 0) reject(new Error('unexpected end of tar archive'))
        else resolve()
      })
    })
  } catch (err) {
    // Corrupt/truncated archive: close the leaked fd and remove the
    // half-written file so repeated failed extractions can't exhaust fds.
    const partial = outPath
    closeOut()
    if (partial) {
      try {
        fs.rmSync(partial, { force: true })
      } catch {
        /* best effort */
      }
    }
    throw err
  }

  return { files }
}
