/**
 * File manager operations, always sandboxed to a server's directory via
 * safeJoin (path traversal is structurally impossible).
 */
import fs from 'node:fs'
import path from 'node:path'
import { safeJoin } from '../lib/paths.ts'
import { zipDirectory, unzip, listZip } from '../lib/zip.ts'
import { extractTar } from '../lib/tar.ts'
import { EXTRACT_LIMITS, fmtBytes } from '../lib/extractlimits.ts'

const MAX_EDIT_SIZE = 5 * 1024 * 1024 // 5 MiB in the editor

export interface FileEntry {
  name: string
  isDir: boolean
  size: number
  mtimeMs: number
  mode: string
}

export function listDir(rootDir: string, rel: string): FileEntry[] {
  const dir = safeJoin(rootDir, rel)
  if (!fs.existsSync(dir)) return []
  const entries = fs.readdirSync(dir, { withFileTypes: true })
  const out: FileEntry[] = []
  for (const entry of entries) {
    try {
      const stat = fs.statSync(path.join(dir, entry.name))
      out.push({
        name: entry.name,
        isDir: stat.isDirectory(),
        size: stat.size,
        mtimeMs: stat.mtimeMs,
        mode: (stat.mode & 0o777).toString(8),
      })
    } catch {
      /* vanished or unreadable */
    }
  }
  return out.sort((a, b) => (a.isDir === b.isDir ? a.name.localeCompare(b.name) : a.isDir ? -1 : 1))
}

export function readTextFile(rootDir: string, rel: string): { content: string; truncated: boolean; binary: boolean; size: number } {
  const file = safeJoin(rootDir, rel)
  const stat = fs.statSync(file)
  if (stat.isDirectory()) throw new Error('is a directory')
  const size = stat.size
  const fd = fs.openSync(file, 'r')
  try {
    const len = Math.min(size, MAX_EDIT_SIZE)
    const buf = Buffer.alloc(len)
    fs.readSync(fd, buf, 0, len, 0)
    const binary = buf.subarray(0, 8000).includes(0)
    return { content: binary ? '' : buf.toString('utf8'), truncated: size > MAX_EDIT_SIZE, binary, size }
  } finally {
    fs.closeSync(fd)
  }
}

export function writeTextFile(rootDir: string, rel: string, content: string): void {
  const file = safeJoin(rootDir, rel)
  fs.mkdirSync(path.dirname(file), { recursive: true })
  fs.writeFileSync(file, content)
}

export function makeDir(rootDir: string, rel: string): void {
  fs.mkdirSync(safeJoin(rootDir, rel), { recursive: true })
}

/** True for a plain file/folder name that stays inside its directory. */
export function isValidEntryName(name: string): boolean {
  if (!name || name.length > 255) return false
  if (name === '.' || name === '..') return false
  return !/[/\\]/.test(name)
}

export class FileConflictError extends Error {
  constructor(name: string) {
    super(`"${name}" already exists`)
    this.name = 'FileConflictError'
  }
}

/** Same-directory rename. The caller validates newName; collision throws FileConflictError (→ 409). */
export function renameWithin(rootDir: string, rel: string, newName: string): { rel: string } {
  const from = safeJoin(rootDir, rel)
  if (!fs.existsSync(from)) throw new Error('file not found')
  const to = path.join(path.dirname(from), newName)
  if (fs.existsSync(to)) throw new FileConflictError(newName)
  fs.renameSync(from, to)
  return { rel: path.posix.join(path.posix.dirname(rel.replace(/\\/g, '/')), newName).replace(/^\.\//, '') }
}

/**
 * Collision convention (documented, applies to copy AND move): the target
 * keeps its name when free, otherwise ` (2)`, ` (3)`, … is inserted before
 * the file extension ("world.zip" → "world (2).zip"). Never a 409.
 */
function freeName(destDirAbs: string, name: string): string {
  if (!fs.existsSync(path.join(destDirAbs, name))) return name
  const dot = name.lastIndexOf('.')
  const stem = dot > 0 ? name.slice(0, dot) : name
  const ext = dot > 0 ? name.slice(dot) : ''
  for (let i = 2; i <= 1000; i++) {
    const candidate = `${stem} (${i})${ext}`
    if (!fs.existsSync(path.join(destDirAbs, candidate))) return candidate
  }
  throw new Error('too many name collisions')
}

/**
 * Budget check for recursive copies, reusing the archive-extraction caps
 * (a copy doubles disk usage exactly like an extraction writes new bytes).
 */
function assertCopyBudget(src: string, stat: fs.Stats): void {
  const { maxBytes, maxEntries } = EXTRACT_LIMITS
  if (!stat.isDirectory()) {
    if (stat.size > maxBytes) throw new Error(`too large to copy (limit ${fmtBytes(maxBytes)})`)
    return
  }
  let bytes = 0
  let entries = 0
  const walk = (dir: string) => {
    let list: fs.Dirent[]
    try {
      list = fs.readdirSync(dir, { withFileTypes: true })
    } catch {
      return
    }
    for (const e of list) {
      if (++entries > maxEntries) throw new Error(`too many files to copy (limit ${maxEntries})`)
      const p = path.join(dir, e.name)
      try {
        if (e.isDirectory()) walk(p)
        else if (e.isFile()) bytes += fs.statSync(p).size
      } catch {
        /* vanished */
      }
      if (bytes > maxBytes) throw new Error(`too large to copy (limit ${fmtBytes(maxBytes)})`)
    }
  }
  walk(src)
}

function assertNotIntoOwnSubtree(src: string, destDir: string, verb: string): void {
  const relFromSrc = path.relative(src, destDir)
  if (relFromSrc === '' || (!relFromSrc.startsWith('..') && !path.isAbsolute(relFromSrc)))
    throw new Error(`cannot ${verb} a folder into itself`)
}

function resolveTransfer(rootDir: string, rel: string, toDirRel: string) {
  const src = safeJoin(rootDir, rel)
  if (!fs.existsSync(src)) throw new Error('file not found')
  const destDir = safeJoin(rootDir, toDirRel)
  if (!fs.existsSync(destDir) || !fs.statSync(destDir).isDirectory()) throw new Error('destination folder not found')
  return { src, destDir, stat: fs.statSync(src) }
}

/** Copy a file or directory (recursive) into another directory. */
export function copyInto(rootDir: string, rel: string, toDirRel: string): { name: string } {
  const { src, destDir, stat } = resolveTransfer(rootDir, rel, toDirRel)
  if (stat.isDirectory()) assertNotIntoOwnSubtree(src, destDir, 'copy')
  assertCopyBudget(src, stat)
  const name = freeName(destDir, path.basename(src))
  fs.cpSync(src, path.join(destDir, name), { recursive: true, errorOnExist: true, force: false })
  return { name }
}

/** Move a file or directory into another directory (rename; copy+delete across filesystems). */
export function moveInto(rootDir: string, rel: string, toDirRel: string): { name: string } {
  const { src, destDir, stat } = resolveTransfer(rootDir, rel, toDirRel)
  if (path.dirname(src) === destDir) throw new Error('already in that folder')
  if (stat.isDirectory()) assertNotIntoOwnSubtree(src, destDir, 'move')
  const name = freeName(destDir, path.basename(src))
  const target = path.join(destDir, name)
  try {
    fs.renameSync(src, target)
  } catch (err) {
    // Same-filesystem rename is the norm inside a server dir; EXDEV can still
    // happen with mounted subfolders — fall back to a budgeted copy+delete.
    if ((err as NodeJS.ErrnoException).code !== 'EXDEV') throw err
    assertCopyBudget(src, stat)
    fs.cpSync(src, target, { recursive: true, errorOnExist: true, force: false })
    fs.rmSync(src, { recursive: true, force: true })
  }
  return { name }
}

export function deleteEntries(rootDir: string, rels: string[]): number {
  let count = 0
  for (const rel of rels) {
    const target = safeJoin(rootDir, rel)
    if (path.resolve(target) === path.resolve(rootDir)) continue // never delete the root
    if (fs.existsSync(target)) {
      fs.rmSync(target, { recursive: true, force: true })
      count++
    }
  }
  return count
}

/**
 * Zip a selection of entries (files/dirs, all direct children of dirRel) into
 * `archiveName` inside that same directory. Entry paths in the archive are
 * relative to dirRel. Inherits zipDirectory's entry-count limit and
 * partial-file cleanup semantics.
 */
export async function zipSelection(
  rootDir: string,
  dirRel: string,
  names: string[],
  archiveName: string,
): Promise<{ files: number; bytes: number }> {
  const base = safeJoin(rootDir, dirRel)
  const dest = path.join(base, archiveName)
  if (fs.existsSync(dest)) throw new FileConflictError(archiveName)
  for (const name of names) {
    if (!fs.existsSync(path.join(base, name))) throw new Error(`file not found: ${name}`)
  }
  const selection = new Set(names)
  return zipDirectory(base, dest, {
    exclude: (rel) => !selection.has(rel.split('/')[0]),
  })
}

export async function extractArchive(rootDir: string, rel: string, destRel: string): Promise<{ files: number }> {
  const file = safeJoin(rootDir, rel)
  const dest = safeJoin(rootDir, destRel)
  fs.mkdirSync(dest, { recursive: true })
  if (/\.zip$/i.test(file)) return unzip(file, dest)
  if (/\.(tar\.gz|tgz|tar)$/i.test(file)) return extractTar(file, dest)
  throw new Error('unsupported archive type (zip, tar.gz, tgz, tar)')
}

export function archiveContents(rootDir: string, rel: string): { name: string; size: number }[] {
  const file = safeJoin(rootDir, rel)
  if (!/\.zip$/i.test(file)) throw new Error('only zip archives can be listed')
  return listZip(file).map((e) => ({ name: e.name, size: e.usize }))
}

export function statEntry(rootDir: string, rel: string): FileEntry & { rel: string } {
  const target = safeJoin(rootDir, rel)
  const stat = fs.statSync(target)
  return {
    rel,
    name: path.basename(target),
    isDir: stat.isDirectory(),
    size: stat.size,
    mtimeMs: stat.mtimeMs,
    mode: (stat.mode & 0o777).toString(8),
  }
}

export function dirSize(dir: string, maxEntries = 200_000): number {
  let total = 0
  let seen = 0
  const walk = (d: string) => {
    let entries: fs.Dirent[]
    try {
      entries = fs.readdirSync(d, { withFileTypes: true })
    } catch {
      return
    }
    for (const entry of entries) {
      if (++seen > maxEntries) return
      const p = path.join(d, entry.name)
      try {
        if (entry.isDirectory()) walk(p)
        else if (entry.isFile()) total += fs.statSync(p).size
      } catch {
        /* ignore */
      }
    }
  }
  walk(dir)
  return total
}
