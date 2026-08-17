/**
 * Hand-rolled ZIP writer/reader on top of node:zlib (raw deflate).
 *
 * Writer streams entries with data descriptors (general purpose flag bit 3),
 * so arbitrarily large files never need to be buffered in memory. Empty
 * directories are preserved as explicit entries. UTF-8 names (flag bit 11).
 * Zip64 is intentionally not supported; clear errors are raised at 4 GiB /
 * 65535-entry limits.
 */
import fs from 'node:fs'
import path from 'node:path'
import zlib from 'node:zlib'
import { pipeline } from 'node:stream/promises'
import { Transform } from 'node:stream'
import { sanitizeEntryName, safeJoin } from './paths.ts'
import { EXTRACT_LIMITS, fmtBytes } from './extractlimits.ts'

// ---------------------------------------------------------------------------
// CRC32
// ---------------------------------------------------------------------------
const CRC_TABLE = (() => {
  const table = new Uint32Array(256)
  for (let n = 0; n < 256; n++) {
    let c = n
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
    table[n] = c >>> 0
  }
  return table
})()

export function crc32(buf: Buffer, seed = 0): number {
  let c = ~seed >>> 0
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8)
  return ~c >>> 0
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------
const SIG_LOCAL = 0x04034b50
const SIG_CENTRAL = 0x02014b50
const SIG_EOCD = 0x06054b50
const SIG_DESCRIPTOR = 0x08074b50
const MAX32 = 0xfffffffe
const FLAG_DESCRIPTOR = 0x0008
const FLAG_UTF8 = 0x0800

function dosDateTime(date: Date): { time: number; date: number } {
  const year = Math.max(1980, date.getFullYear())
  return {
    time: (date.getHours() << 11) | (date.getMinutes() << 5) | Math.floor(date.getSeconds() / 2),
    date: ((year - 1980) << 9) | ((date.getMonth() + 1) << 5) | date.getDate(),
  }
}

export class ZipLimitError extends Error {
  constructor(msg: string) {
    super(msg)
    this.name = 'ZipLimitError'
  }
}

interface CentralRecord {
  name: Buffer
  method: number
  crc: number
  csize: number
  usize: number
  time: number
  date: number
  offset: number
  isDir: boolean
  externalAttrs: number
}

// ---------------------------------------------------------------------------
// Writer
// ---------------------------------------------------------------------------
export interface ZipWriteOptions {
  /** Return true to skip a file/dir. Receives forward-slash relative path. */
  exclude?: (relPath: string, isDir: boolean) => boolean
  onProgress?: (info: { files: number; bytes: number; currentFile: string }) => void
}

class ByteCounter extends Transform {
  bytes = 0
  crc = 0
  _transform(chunk: Buffer, _enc: string, cb: (err?: Error | null, data?: Buffer) => void) {
    this.bytes += chunk.length
    this.crc = crc32(chunk, this.crc)
    cb(null, chunk)
  }
}

class OutCounter extends Transform {
  bytes = 0
  _transform(chunk: Buffer, _enc: string, cb: (err?: Error | null, data?: Buffer) => void) {
    this.bytes += chunk.length
    cb(null, chunk)
  }
}

function writeBuf(out: fs.WriteStream, buf: Buffer): Promise<void> {
  return new Promise((resolve, reject) => {
    out.write(buf, (err) => (err ? reject(err) : resolve()))
  })
}

/** Recursively collect entries of a directory (files and dirs), sorted for determinism. */
function walkDir(root: string, exclude?: ZipWriteOptions['exclude']): { rel: string; abs: string; isDir: boolean }[] {
  const out: { rel: string; abs: string; isDir: boolean }[] = []
  const walk = (dirAbs: string, dirRel: string) => {
    const entries = fs.readdirSync(dirAbs, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))
    for (const e of entries) {
      const rel = dirRel ? `${dirRel}/${e.name}` : e.name
      const abs = path.join(dirAbs, e.name)
      if (e.isSymbolicLink()) continue // never follow symlinks into archives
      const isDir = e.isDirectory()
      if (exclude?.(rel, isDir)) continue
      if (isDir) {
        out.push({ rel, abs, isDir: true })
        walk(abs, rel)
      } else if (e.isFile()) {
        out.push({ rel, abs, isDir: false })
      }
    }
  }
  walk(root, '')
  return out
}

/** Zip a whole directory into outFile. Returns bytes written and file count. */
export async function zipDirectory(
  srcDir: string,
  outFile: string,
  opts: ZipWriteOptions = {},
): Promise<{ files: number; bytes: number }> {
  const entries = walkDir(srcDir, opts.exclude)
  if (entries.length >= 0xffff) throw new ZipLimitError(`too many entries for zip (${entries.length} >= 65535)`)

  fs.mkdirSync(path.dirname(outFile), { recursive: true })
  // A failure mid-archive must not leave a partial file behind: callers pick
  // collision-free names (BackupService's suffix loop), so an orphan would be
  // walked around forever and never cleaned up. Only remove what THIS call
  // created — a pre-existing outFile is the caller's to manage.
  const existedBefore = fs.existsSync(outFile)
  const out = fs.createWriteStream(outFile)
  try {
    return await writeZipTo(out, entries, opts)
  } catch (err) {
    out.destroy()
    if (!existedBefore) {
      try {
        fs.rmSync(outFile, { force: true })
      } catch {
        /* best-effort */
      }
    }
    throw err
  }
}

async function writeZipTo(
  out: fs.WriteStream,
  entries: { rel: string; abs: string; isDir: boolean }[],
  opts: ZipWriteOptions,
): Promise<{ files: number; bytes: number }> {
  const central: CentralRecord[] = []
  let offset = 0
  let fileCount = 0

  const header = Buffer.alloc(30)
  for (const entry of entries) {
    const stat = fs.statSync(entry.abs)
    const { time, date } = dosDateTime(stat.mtime)
    const nameStr = entry.isDir ? `${entry.rel}/` : entry.rel
    const name = Buffer.from(nameStr, 'utf8')
    const method = entry.isDir ? 0 : 8
    const flags = FLAG_UTF8 | (entry.isDir ? 0 : FLAG_DESCRIPTOR)

    header.writeUInt32LE(SIG_LOCAL, 0)
    header.writeUInt16LE(20, 4) // version needed
    header.writeUInt16LE(flags, 6)
    header.writeUInt16LE(method, 8)
    header.writeUInt16LE(time, 10)
    header.writeUInt16LE(date, 12)
    header.writeUInt32LE(0, 14) // crc (in descriptor)
    header.writeUInt32LE(0, 18) // csize (in descriptor)
    header.writeUInt32LE(0, 22) // usize (in descriptor)
    header.writeUInt16LE(name.length, 26)
    header.writeUInt16LE(0, 28) // extra len
    const localOffset = offset
    await writeBuf(out, Buffer.concat([Buffer.from(header), name]))
    offset += 30 + name.length

    let crc = 0
    let csize = 0
    let usize = 0
    if (!entry.isDir) {
      const counter = new ByteCounter()
      const outCounter = new OutCounter()
      const deflate = zlib.createDeflateRaw({ level: 6 })
      // Consume the compressed stream via writeBuf instead of piping into
      // `out`: pipeline(..., out, { end: false }) leaves its error/close
      // listeners attached forever, accumulating one set per archive entry.
      await pipeline(fs.createReadStream(entry.abs), counter, deflate, outCounter, async (source: AsyncIterable<Buffer>) => {
        for await (const chunk of source) await writeBuf(out, chunk)
      })
      crc = counter.crc >>> 0
      usize = counter.bytes
      csize = outCounter.bytes
      if (usize > MAX32 || csize > MAX32) throw new ZipLimitError(`file too large for zip: ${entry.rel}`)
      offset += csize

      const desc = Buffer.alloc(16)
      desc.writeUInt32LE(SIG_DESCRIPTOR, 0)
      desc.writeUInt32LE(crc, 4)
      desc.writeUInt32LE(csize, 8)
      desc.writeUInt32LE(usize, 12)
      await writeBuf(out, desc)
      offset += 16
      fileCount++
      opts.onProgress?.({ files: fileCount, bytes: offset, currentFile: entry.rel })
    }

    if (localOffset > MAX32) throw new ZipLimitError('archive exceeds 4 GiB offset limit')
    const unixMode = entry.isDir ? 0o40755 : (stat.mode & 0o777) | 0o100000
    central.push({
      name,
      method,
      crc,
      csize,
      usize,
      time,
      date,
      offset: localOffset,
      isDir: entry.isDir,
      externalAttrs: (unixMode << 16) >>> 0,
    })
  }

  // Central directory
  const centralStart = offset
  for (const rec of central) {
    const c = Buffer.alloc(46)
    c.writeUInt32LE(SIG_CENTRAL, 0)
    c.writeUInt16LE(0x031e, 4) // made by: unix, spec 3.0
    c.writeUInt16LE(20, 6)
    c.writeUInt16LE(FLAG_UTF8 | (rec.isDir ? 0 : FLAG_DESCRIPTOR), 8)
    c.writeUInt16LE(rec.method, 10)
    c.writeUInt16LE(rec.time, 12)
    c.writeUInt16LE(rec.date, 14)
    c.writeUInt32LE(rec.crc, 16)
    c.writeUInt32LE(rec.csize, 20)
    c.writeUInt32LE(rec.usize, 24)
    c.writeUInt16LE(rec.name.length, 28)
    c.writeUInt16LE(0, 30) // extra
    c.writeUInt16LE(0, 32) // comment
    c.writeUInt16LE(0, 34) // disk
    c.writeUInt16LE(0, 36) // internal attrs
    c.writeUInt32LE(rec.externalAttrs, 38)
    c.writeUInt32LE(rec.offset, 42)
    await writeBuf(out, Buffer.concat([c, rec.name]))
    offset += 46 + rec.name.length
  }

  const eocd = Buffer.alloc(22)
  eocd.writeUInt32LE(SIG_EOCD, 0)
  eocd.writeUInt16LE(0, 4)
  eocd.writeUInt16LE(0, 6)
  eocd.writeUInt16LE(central.length, 8)
  eocd.writeUInt16LE(central.length, 10)
  eocd.writeUInt32LE(offset - centralStart, 12)
  eocd.writeUInt32LE(centralStart, 16)
  eocd.writeUInt16LE(0, 20)
  await writeBuf(out, eocd)

  await new Promise<void>((resolve, reject) => {
    out.end(() => resolve())
    out.on('error', reject)
  })
  return { files: fileCount, bytes: offset + 22 }
}

// ---------------------------------------------------------------------------
// Reader
// ---------------------------------------------------------------------------
export interface ZipEntry {
  name: string
  isDir: boolean
  method: number
  csize: number
  usize: number
  offset: number
}

export function listZip(file: string): ZipEntry[] {
  const fd = fs.openSync(file, 'r')
  try {
    const size = fs.fstatSync(fd).size
    const tailLen = Math.min(size, 22 + 0xffff)
    const tail = Buffer.alloc(tailLen)
    fs.readSync(fd, tail, 0, tailLen, size - tailLen)
    let eocdPos = -1
    for (let i = tail.length - 22; i >= 0; i--) {
      if (tail.readUInt32LE(i) === SIG_EOCD) {
        eocdPos = i
        break
      }
    }
    if (eocdPos < 0) throw new Error('not a zip file (no end-of-central-directory)')
    const count = tail.readUInt16LE(eocdPos + 10)
    const cdSize = tail.readUInt32LE(eocdPos + 12)
    const cdOffset = tail.readUInt32LE(eocdPos + 16)
    if (cdOffset === 0xffffffff) throw new ZipLimitError('zip64 archives are not supported')

    const cd = Buffer.alloc(cdSize)
    fs.readSync(fd, cd, 0, cdSize, cdOffset)
    const entries: ZipEntry[] = []
    let p = 0
    for (let i = 0; i < count; i++) {
      if (cd.readUInt32LE(p) !== SIG_CENTRAL) throw new Error('corrupt central directory')
      const method = cd.readUInt16LE(p + 10)
      const csize = cd.readUInt32LE(p + 20)
      const usize = cd.readUInt32LE(p + 24)
      const nameLen = cd.readUInt16LE(p + 28)
      const extraLen = cd.readUInt16LE(p + 30)
      const commentLen = cd.readUInt16LE(p + 32)
      const offset = cd.readUInt32LE(p + 42)
      const name = cd.subarray(p + 46, p + 46 + nameLen).toString('utf8')
      if (csize === 0xffffffff || usize === 0xffffffff || offset === 0xffffffff)
        throw new ZipLimitError('zip64 entries are not supported')
      entries.push({ name, isDir: name.endsWith('/'), method, csize, usize, offset })
      p += 46 + nameLen + extraLen + commentLen
    }
    return entries
  } finally {
    fs.closeSync(fd)
  }
}

export interface UnzipOptions {
  onProgress?: (info: { files: number; totalFiles: number; currentFile: string }) => void
  /** Override the cumulative uncompressed-byte budget (mainly for tests). */
  maxBytes?: number
  /** Override the entry-count budget (mainly for tests). */
  maxEntries?: number
}

/** Counts bytes flowing through and fails once the shared budget is spent. */
function budgetGuard(budget: { used: number }, maxBytes: number, entryName: string): Transform {
  return new Transform({
    transform(chunk: Buffer, _enc, cb) {
      budget.used += chunk.length
      if (budget.used > maxBytes) {
        cb(new ZipLimitError(`archive too large: extraction exceeds ${fmtBytes(maxBytes)} (at ${entryName})`))
        return
      }
      cb(null, chunk)
    },
  })
}

/** Extract a zip into destDir, with strict path sanitization and bomb limits. */
export async function unzip(file: string, destDir: string, opts: UnzipOptions = {}): Promise<{ files: number }> {
  const maxBytes = opts.maxBytes ?? EXTRACT_LIMITS.maxBytes
  const maxEntries = opts.maxEntries ?? EXTRACT_LIMITS.maxEntries
  const entries = listZip(file)
  if (entries.length > maxEntries)
    throw new ZipLimitError(`archive has too many entries (${entries.length}, limit ${maxEntries})`)
  // The central directory catches honestly-declared bombs before any byte is
  // written; the streaming guard below catches archives whose headers lie
  // (deflate output is not bounded by the declared uncompressed size).
  let declaredTotal = 0
  for (const e of entries) declaredTotal += e.usize
  if (declaredTotal > maxBytes)
    throw new ZipLimitError(`archive too large: declares ${fmtBytes(declaredTotal)} extracted (limit ${fmtBytes(maxBytes)})`)
  const budget = { used: 0 }

  const fd = fs.openSync(file, 'r')
  let done = 0
  try {
    for (const entry of entries) {
      const clean = sanitizeEntryName(entry.name)
      if (!clean) continue
      const target = safeJoin(destDir, clean)
      if (entry.isDir) {
        fs.mkdirSync(target, { recursive: true })
        continue
      }
      fs.mkdirSync(path.dirname(target), { recursive: true })
      // Local header: name/extra lengths may differ from central directory.
      const local = Buffer.alloc(30)
      fs.readSync(fd, local, 0, 30, entry.offset)
      if (local.readUInt32LE(0) !== SIG_LOCAL) throw new Error(`corrupt local header for ${entry.name}`)
      const nameLen = local.readUInt16LE(26)
      const extraLen = local.readUInt16LE(28)
      const dataStart = entry.offset + 30 + nameLen + extraLen
      if (entry.method !== 0 && entry.method !== 8)
        throw new Error(`unsupported compression method ${entry.method} for ${entry.name}`)

      try {
        if (entry.csize > 0) {
          const src = fs.createReadStream(file, { start: dataStart, end: dataStart + entry.csize - 1, autoClose: true })
          const dest = fs.createWriteStream(target)
          if (entry.method === 8) {
            await pipeline(src, zlib.createInflateRaw(), budgetGuard(budget, maxBytes, clean), dest)
          } else {
            await pipeline(src, budgetGuard(budget, maxBytes, clean), dest)
          }
        } else {
          // Empty entry: create it synchronously so a name colliding with an
          // existing directory (e.g. a crafted `foo/` dir entry followed by a
          // stored empty `foo` file entry) throws EISDIR *here* and is caught
          // below, instead of surfacing as an async 'error' on an unawaited
          // stream — which would crash the whole process (uncaughtException).
          fs.closeSync(fs.openSync(target, 'w'))
        }
      } catch (err) {
        // Drop a half-written file so an aborted extraction (bomb, corrupt
        // data, collision) leaves no truncated artifact. Never touch a
        // pre-existing directory: guard on isFile so the best-effort cleanup
        // can't delete a real directory the archive collided with.
        try {
          if (fs.statSync(target).isFile()) fs.rmSync(target, { force: true })
        } catch {
          /* best effort */
        }
        throw err
      }
      done++
      opts.onProgress?.({ files: done, totalFiles: entries.length, currentFile: clean })
    }
    return { files: done }
  } finally {
    fs.closeSync(fd)
  }
}
