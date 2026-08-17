/**
 * Hand-rolled TOML subset for game server configs (Rust/Go servers, Velocity,
 * Factorio-adjacent tools, …). Deliberately NOT a full TOML 1.0
 * implementation — it covers the shapes game configs actually use, and the
 * apply path edits lines surgically instead of parse→re-dump so comments,
 * unrelated keys and table order survive byte-for-byte.
 *
 * Supported: top-level `key = value`, `[table]` / `[a.b]` sections, scalars
 * (basic and literal strings, integers, floats, booleans), `#` comments
 * (full-line and trailing). Mapping keys use dot-paths where the final
 * segment is the key and the preceding segments select the table
 * (`server.port` → `[server]` table, `port` key).
 *
 * Documented limitations:
 * - dotted keys on the left-hand side (`a.b = 1`) can be read by parseToml
 *   but not addressed by applyToml (dot-paths always select tables)
 * - arrays of tables (`[[x]]`) pass through untouched but cannot be edited;
 *   parseToml skips their contents
 * - inline tables (`{a = 1}`), multi-line strings and dates are treated as
 *   opaque scalar text
 * - quoted keys (`"a.b" = 1`) are not supported
 */

/** Keys that must never be written into a parsed object — they mutate
 * Object.prototype instead of the document (prototype pollution). */
const UNSAFE_KEYS = new Set(['__proto__', 'constructor', 'prototype'])

/** Split a dot-path into the table selector and the final key. */
function splitTableKey(dotPath: string): { table: string; key: string } {
  const dot = dotPath.lastIndexOf('.')
  if (dot <= 0) return { table: '', key: dotPath }
  return { table: dotPath.slice(0, dot), key: dotPath.slice(dot + 1) }
}

/** Normalise a `[ a . b ]` header body to a canonical dotted name. */
function normalizeTableName(inner: string): string {
  return inner
    .split('.')
    .map((p) => p.trim())
    .join('.')
}

const KEY_LINE = /^(\s*)([A-Za-z0-9_-]+)(\s*=\s*)(.*)$/
const TABLE_LINE = /^\s*\[([^[\]]+)\]\s*(#.*)?$/

/**
 * Find where the scalar value ends inside `rest` (string-aware) and return
 * value + trailing comment suffix (kept verbatim for edits).
 */
function splitValueComment(rest: string): { value: string; comment: string } {
  const first = rest.trimStart()[0]
  let scanFrom = 0
  if (first === '"' || first === "'") {
    const open = rest.indexOf(first)
    let close = -1
    for (let i = open + 1; i < rest.length; i++) {
      if (first === '"' && rest[i] === '\\') {
        i++
        continue
      }
      if (rest[i] === first) {
        close = i
        break
      }
    }
    if (close < 0) return { value: rest.trim(), comment: '' }
    scanFrom = close + 1
  }
  for (let i = scanFrom; i < rest.length; i++) {
    if (rest[i] === '#') {
      let start = i
      while (start > 0 && (rest[start - 1] === ' ' || rest[start - 1] === '\t')) start--
      return { value: rest.slice(0, start).trim(), comment: rest.slice(start) }
    }
  }
  return { value: rest.trim(), comment: '' }
}

/** Booleans and plain numbers stay bare; everything else becomes a "…" string. */
function formatTomlValue(raw: string): string {
  if (raw === 'true' || raw === 'false') return raw
  // Only emit a bare number when it reparses to the identical string. This
  // rejects leading zeros (which are invalid TOML integers, e.g. "08") and
  // lossy forms ("3.0" would read back as 3) — those are quoted as strings.
  if ((/^-?\d+$/.test(raw) || /^-?\d+\.\d+$/.test(raw)) && String(Number(raw)) === raw) return raw
  let escaped = ''
  for (const ch of raw) {
    if (ch === '\\') escaped += '\\\\'
    else if (ch === '"') escaped += '\\"'
    else if (ch === '\n') escaped += '\\n'
    else if (ch === '\r') escaped += '\\r'
    else if (ch === '\t') escaped += '\\t'
    // remaining control chars are rare but must not break the document
    else if (ch.charCodeAt(0) < 0x20) escaped += `\\u${ch.charCodeAt(0).toString(16).padStart(4, '0')}`
    else escaped += ch
  }
  return `"${escaped}"`
}

/**
 * Surgically set values at dot-paths (see header for table selection).
 * Existing `key = value` lines are rewritten in place (spacing and trailing
 * comments kept); missing keys are inserted right after their table header
 * (mirroring applyIni); missing tables are appended at the end.
 */
export function applyToml(text: string, updates: Record<string, string>): string {
  const remaining = new Map<string, string>()
  for (const [dotPath, value] of Object.entries(updates)) {
    const { table, key } = splitTableKey(dotPath)
    remaining.set(`${table}\u0000${key}`, value)
  }
  const lines = String(text ?? '').split(/\r?\n/)
  const out: string[] = []
  // Position right after each table header, so new keys land inside an
  // EXISTING table instead of a duplicate [table] header at the end.
  const tableStart = new Map<string, number>([['', 0]])
  let table = ''
  for (const rawLine of lines) {
    if (/^\s*\[\[/.test(rawLine)) {
      // array-of-tables: keys inside must never be matched or edited
      table = '\u0000array-of-tables'
      out.push(rawLine)
      continue
    }
    const tableMatch = rawLine.match(TABLE_LINE)
    if (tableMatch) {
      table = normalizeTableName(tableMatch[1])
      out.push(rawLine)
      if (!tableStart.has(table)) tableStart.set(table, out.length)
      continue
    }
    const keyMatch = rawLine.match(KEY_LINE)
    if (!keyMatch || rawLine.trimStart().startsWith('#')) {
      out.push(rawLine)
      continue
    }
    const mapKey = `${table}\u0000${keyMatch[2]}`
    if (remaining.has(mapKey)) {
      const { comment } = splitValueComment(keyMatch[4])
      out.push(`${keyMatch[1]}${keyMatch[2]}${keyMatch[3]}${formatTomlValue(remaining.get(mapKey)!)}${comment}`)
      remaining.delete(mapKey)
    } else {
      out.push(rawLine)
    }
  }
  // Group leftovers by target table (same strategy as applyIni)
  const byTable = new Map<string, [string, string][]>()
  for (const [mapKey, value] of remaining) {
    const [tbl, key] = mapKey.split('\u0000')
    const list = byTable.get(tbl) ?? []
    list.push([key, value])
    byTable.set(tbl, list)
  }
  const inserts: { at: number; kv: string[] }[] = []
  const appends: string[] = []
  for (const [tbl, pairs] of byTable) {
    const kv = pairs.map(([key, value]) => `${key} = ${formatTomlValue(value)}`)
    const at = tableStart.get(tbl)
    if (at !== undefined) inserts.push({ at, kv })
    else appends.push(`[${tbl}]`, ...kv)
  }
  inserts.sort((a, b) => b.at - a.at)
  for (const { at, kv } of inserts) out.splice(at, 0, ...kv)
  out.push(...appends)
  return out.join('\n')
}

/** Parse one scalar value; unknown shapes come back as their raw text. */
function parseTomlScalar(value: string): unknown {
  if (value === 'true') return true
  if (value === 'false') return false
  if (/^[+-]?\d+$/.test(value)) return Number(value)
  if (/^[+-]?\d+\.\d+([eE][+-]?\d+)?$/.test(value)) return Number(value)
  if (value.length >= 2 && value[0] === '"' && value[value.length - 1] === '"') {
    return value
      .slice(1, -1)
      .replace(/\\u([0-9a-fA-F]{4})/g, (_m, hex: string) => String.fromCharCode(parseInt(hex, 16)))
      .replace(/\\(["\\nrtbf])/g, (_m, c: string) =>
        c === 'n' ? '\n' : c === 'r' ? '\r' : c === 't' ? '\t' : c === 'b' ? '\b' : c === 'f' ? '\f' : c,
      )
  }
  if (value.length >= 2 && value[0] === "'" && value[value.length - 1] === "'") return value.slice(1, -1)
  if (value.length >= 2 && value[0] === '[' && value[value.length - 1] === ']') {
    // simple one-line arrays of scalars; anything fancier stays raw text
    const inner = value.slice(1, -1).trim()
    if (inner === '') return []
    if (!/[[\]{}]/.test(inner)) return inner.split(',').map((item) => parseTomlScalar(splitValueComment(item.trim()).value))
  }
  return value
}

/**
 * Parse tables + scalars into a nested object for the read API. Best-effort
 * and lossy for exotic TOML (see header) — never throws on malformed input.
 */
export function parseToml(text: string): Record<string, unknown> {
  const root: Record<string, unknown> = {}
  try {
    let current: Record<string, unknown> | null = root
    for (const rawLine of String(text ?? '').split(/\r?\n/)) {
      const line = rawLine.trim()
      if (line === '' || line.startsWith('#')) continue
      if (/^\[\[/.test(line)) {
        current = null // arrays of tables are skipped entirely
        continue
      }
      const tableMatch = rawLine.match(TABLE_LINE)
      if (tableMatch) {
        current = root
        for (const part of normalizeTableName(tableMatch[1]).split('.')) {
          if (UNSAFE_KEYS.has(part)) {
            current = null // never descend through a prototype-polluting table name
            break
          }
          if (typeof current[part] !== 'object' || current[part] === null || Array.isArray(current[part])) current[part] = {}
          current = current[part] as Record<string, unknown>
        }
        continue
      }
      if (!current) continue
      // dotted bare keys nest (a.b = 1 → { a: { b: 1 } })
      const keyMatch = rawLine.match(/^\s*([A-Za-z0-9_.-]+)\s*=\s*(.*)$/)
      if (!keyMatch) continue
      const parts = keyMatch[1].split('.').filter((p) => p.length > 0)
      if (parts.length === 0) continue
      if (parts.some((p) => UNSAFE_KEYS.has(p))) continue // block prototype pollution via dotted keys
      const { value } = splitValueComment(keyMatch[2])
      let cursor = current
      for (let i = 0; i < parts.length - 1; i++) {
        if (typeof cursor[parts[i]] !== 'object' || cursor[parts[i]] === null || Array.isArray(cursor[parts[i]])) cursor[parts[i]] = {}
        cursor = cursor[parts[i]] as Record<string, unknown>
      }
      cursor[parts[parts.length - 1]] = parseTomlScalar(value)
    }
  } catch {
    // malformed input → best-effort partial result
  }
  return root
}
