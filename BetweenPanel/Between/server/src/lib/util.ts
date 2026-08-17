export function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

export function clamp(n: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, n))
}

export function humanBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes < 0) return '0 B'
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB']
  let i = 0
  let v = bytes
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024
    i++
  }
  return `${v.toFixed(v >= 100 || i === 0 ? 0 : 1)} ${units[i]}`
}

/** Substitute {{KEY}} placeholders. Unknown keys are left untouched. */
export function substituteVars(template: string, vars: Record<string, string | number | boolean>): string {
  return template.replace(/\{\{\s*([A-Za-z0-9_]+)\s*\}\}/g, (match, key: string) => {
    if (key in vars) return String(vars[key])
    return match
  })
}

/** Strip characters that are dangerous to render or log. Keeps ANSI escapes out. */
export function sanitizeLine(line: string, maxLen = 4000): string {
  let s = line.length > maxLen ? line.slice(0, maxLen) + '…' : line
  // Remove all C0 control chars except tab; ANSI colors are parsed client-side
  // from \u001b sequences we deliberately keep.
  s = s.replace(/[\u0000-\u0008\u000b-\u001a\u001c-\u001f\u007f]/g, '')
  return s
}

export function nowIso(): string {
  return new Date().toISOString()
}

export function isValidName(name: string): boolean {
  return typeof name === 'string' && name.trim().length >= 1 && name.length <= 80
}

/** Simple slug for directory names. */
export function slugify(name: string): string {
  return (
    name
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .slice(0, 40) || 'server'
  )
}

export function pick<T extends object, K extends keyof T>(obj: T, keys: K[]): Pick<T, K> {
  const out = {} as Pick<T, K>
  for (const k of keys) if (k in obj) out[k] = obj[k]
  return out
}
