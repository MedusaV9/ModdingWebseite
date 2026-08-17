import path from 'node:path'

export class PathTraversalError extends Error {
  constructor(public rel: string) {
    super(`path escapes the allowed root: ${rel}`)
    this.name = 'PathTraversalError'
  }
}

/**
 * Resolve `relPath` inside `baseDir`, guaranteeing the result cannot escape
 * `baseDir` (used by the file manager, archive extraction and backups).
 */
export function safeJoin(baseDir: string, relPath: string): string {
  const base = path.resolve(baseDir)
  // Treat backslashes as separators on every platform so Windows-style input
  // cannot smuggle `..\` segments (or literal `a\b` filenames) past the check.
  const cleaned = String(relPath ?? '')
    .replace(/\\/g, '/')
    .replace(/^\/+/, '')
  const target = path.resolve(base, cleaned)
  const rel = path.relative(base, target)
  if (rel === '') return target
  if (rel.startsWith('..') || path.isAbsolute(rel)) throw new PathTraversalError(relPath)
  return target
}

/** Validate an archive entry name (zip/tar) before extraction. */
export function sanitizeEntryName(name: string): string | null {
  if (!name) return null
  const normalized = name.replace(/\\/g, '/')
  if (normalized.startsWith('/') || /^[A-Za-z]:/.test(normalized)) return null
  const parts = normalized.split('/').filter((p) => p.length > 0)
  if (parts.some((p) => p === '..')) return null
  if (parts.length === 0) return null
  return parts.join('/')
}
