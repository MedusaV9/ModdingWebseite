/**
 * Hand-rolled YAML subset for game/plugin configs (bukkit.yml, Paper/plugin
 * config.yml, bot configs, …). This is deliberately NOT a YAML 1.2
 * implementation — it covers what game configs actually use, and the apply
 * path edits lines surgically instead of parse→re-dump so comments, blank
 * lines, list items and unrelated keys survive byte-for-byte.
 *
 * Supported: block-style mappings (`key: value`, `key:` + indented children)
 * at any consistent indentation, lists of scalars (`- item`), `#` comments
 * (full-line and trailing), single/double-quoted scalars; block scalars
 * (`|`/`>`) are recognised and skipped so their content is never misread as
 * keys.
 *
 * Documented limitations:
 * - dot-paths split on `.`, so mapping keys that themselves contain a dot
 *   cannot be addressed
 * - flow collections (`[a, b]`, `{a: 1}`) are treated as opaque scalar text
 * - anchors/aliases/tags (`&`, `*`, `!!`) and multi-document files (`---`)
 *   pass through untouched but cannot be edited
 * - mappings nested inside list items are preserved but not addressable
 * - setting a scalar on a path whose current value is a mapping with children
 *   replaces the `key:` line and leaves the children behind (don't do that)
 */

interface MappingLine {
  index: number
  indent: number
  key: string
  /** Text after the colon, leading whitespace stripped ('' when blank). */
  rest: string
  /** Effective scalar value with any trailing comment removed. */
  value: string
  /** Exact source text up to and including the colon (preserved on edits). */
  head: string
}

/** Number of leading spaces (tabs count as one column — good enough here). */
function indentOf(line: string): number {
  let n = 0
  while (n < line.length && (line[n] === ' ' || line[n] === '\t')) n++
  return n
}

function isBlankOrComment(line: string): boolean {
  const t = line.trim()
  return t === '' || t.startsWith('#')
}

/** Strip surrounding quotes and unescape a scalar; bare scalars pass through. */
function unquoteScalar(raw: string): string {
  const t = raw.trim()
  if (t.length >= 2 && t[0] === '"' && t[t.length - 1] === '"') {
    return t
      .slice(1, -1)
      .replace(/\\(["\\nrt])/g, (_m, c: string) => (c === 'n' ? '\n' : c === 'r' ? '\r' : c === 't' ? '\t' : c))
  }
  if (t.length >= 2 && t[0] === "'" && t[t.length - 1] === "'") return t.slice(1, -1).replace(/''/g, "'")
  return t
}

/**
 * Split the text after `key:` into the value part and the trailing comment
 * suffix (kept verbatim, incl. its alignment whitespace) so edits can put the
 * comment back exactly where it was.
 */
function splitValueComment(rest: string): { value: string; comment: string } {
  if (rest === '') return { value: '', comment: '' }
  if (rest.startsWith('#')) return { value: '', comment: ` ${rest}` }
  const first = rest[0]
  let scanFrom = 0
  if (first === '"' || first === "'") {
    // Find the real closing quote first — a `#` inside quotes is not a comment
    let close = -1
    for (let i = 1; i < rest.length; i++) {
      if (first === '"' && rest[i] === '\\') {
        i++
        continue
      }
      if (rest[i] === first) {
        if (first === "'" && rest[i + 1] === "'") {
          i++ // '' escapes a quote inside single-quoted scalars
          continue
        }
        close = i
        break
      }
    }
    if (close < 0) return { value: rest.trim(), comment: '' }
    scanFrom = close + 1
  }
  // A `#` only starts a comment when preceded by whitespace (YAML rule)
  for (let i = Math.max(scanFrom, 1); i < rest.length; i++) {
    if (rest[i] === '#' && (rest[i - 1] === ' ' || rest[i - 1] === '\t')) {
      let start = i
      while (start > 0 && (rest[start - 1] === ' ' || rest[start - 1] === '\t')) start--
      return { value: rest.slice(0, start).trim(), comment: rest.slice(start) }
    }
  }
  return { value: rest.trim(), comment: '' }
}

/** Parse one line as a mapping entry (`key:` or `key: value`), else null. */
function parseMappingLine(line: string, index: number): MappingLine | null {
  const indent = indentOf(line)
  const body = line.slice(indent)
  if (body === '' || body.startsWith('#') || body.startsWith('- ') || body === '-') return null
  let key: string
  let colonAt: number
  if (body[0] === '"' || body[0] === "'") {
    const quote = body[0]
    let end = -1
    for (let i = 1; i < body.length; i++) {
      if (quote === '"' && body[i] === '\\') {
        i++
        continue
      }
      if (body[i] === quote) {
        end = i
        break
      }
    }
    if (end < 0) return null
    const m = body.slice(end + 1).match(/^\s*:/)
    if (!m) return null
    key = unquoteScalar(body.slice(0, end + 1))
    colonAt = end + m[0].length
  } else {
    // Split at the first `:` that is followed by whitespace or end-of-line —
    // colons inside values (URLs, timestamps) never match this way.
    colonAt = -1
    for (let i = 0; i < body.length; i++) {
      if (body[i] === ':' && (i + 1 >= body.length || body[i + 1] === ' ' || body[i + 1] === '\t')) {
        colonAt = i
        break
      }
    }
    if (colonAt <= 0) return null
    key = body.slice(0, colonAt).trim()
    if (!key) return null
  }
  const rest = body.slice(colonAt + 1).replace(/^[ \t]+/, '')
  const { value } = splitValueComment(rest)
  return { index, indent, key, rest, value, head: line.slice(0, indent + colonAt + 1) }
}

/** True when the value opens a block scalar (`|`, `>`, optional modifiers). */
function isBlockScalar(value: string): boolean {
  return /^[|>][+-]?\d*$/.test(value)
}

const YAML_AMBIGUOUS = /^(~|null|true|false|yes|no|on|off)$/i

/** Keys that must never be written into a parsed object — they mutate
 * Object.prototype instead of the document (prototype pollution). */
const UNSAFE_KEYS = new Set(['__proto__', 'constructor', 'prototype'])

/** Quote only when a bare scalar would change meaning or break parsing. */
function formatYamlScalar(raw: string): string {
  // Match applyJson: booleans and plain numbers become real YAML scalars
  if (raw === 'true' || raw === 'false') return raw
  // Only stay bare when the number reparses to the identical string. Leading
  // zeros ("007") would otherwise be read as octal by YAML 1.1 parsers such as
  // SnakeYAML (Bukkit/Spigot), and "3.0" would lose its trailing zero.
  if (/^-?\d+(\.\d+)?$/.test(raw) && String(Number(raw)) === raw) return raw
  const needsQuote =
    raw === '' ||
    /^\s|\s$/.test(raw) ||
    raw.includes(':') ||
    raw.includes('#') ||
    /^[!&*?|>%@`"'[\]{},]/.test(raw) ||
    raw === '-' ||
    raw.startsWith('- ') ||
    YAML_AMBIGUOUS.test(raw) ||
    /^[-+.]?\d/.test(raw) || // number-ish strings ("1.2.3", "08") must stay strings
    /[\n\r\t]/.test(raw)
  if (!needsQuote) return raw
  return `"${raw.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n').replace(/\r/g, '\\r').replace(/\t/g, '\\t')}"`
}

/**
 * Walk block-style mapping lines tracking the nesting path via indentation.
 * Block scalar bodies are skipped so their content is never mistaken for keys.
 */
function walkMappings(lines: string[], onEntry: (entry: MappingLine, path: string[]) => void): void {
  const stack: { indent: number; key: string }[] = []
  let skipBlockIndent = -1
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    if (skipBlockIndent >= 0) {
      if (line.trim() === '' || indentOf(line) > skipBlockIndent) continue
      skipBlockIndent = -1
    }
    if (isBlankOrComment(line)) continue
    const entry = parseMappingLine(line, i)
    if (!entry) continue // list items, document markers, flow content, …
    while (stack.length > 0 && stack[stack.length - 1].indent >= entry.indent) stack.pop()
    onEntry(entry, [...stack.map((s) => s.key), entry.key])
    if (entry.value === '') stack.push({ indent: entry.indent, key: entry.key })
    else if (isBlockScalar(entry.value)) skipBlockIndent = entry.indent
  }
}

/** Read the scalar at a nested `a.b.c` path; undefined when absent. */
export function getYamlValue(text: string, dotPath: string): string | undefined {
  const parts = dotPath.split('.')
  let found: string | undefined
  try {
    walkMappings(String(text ?? '').split(/\r?\n/), (entry, path) => {
      if (found !== undefined) return
      if (path.length !== parts.length || !path.every((p, i) => p === parts[i])) return
      found = unquoteScalar(entry.value)
    })
  } catch {
    return undefined
  }
  return found
}

/**
 * Surgically set scalars at nested dot-paths. Existing `key:` lines are
 * rewritten in place (indentation, key spelling and trailing comments kept);
 * a missing leaf is inserted after the parent's last child; missing
 * intermediate mappings are created using the surrounding indentation step.
 */
export function applyYaml(text: string, updates: Record<string, string>): string {
  let out = String(text ?? '')
  for (const [dotPath, value] of Object.entries(updates)) {
    try {
      out = applyOne(out, dotPath.split('.'), value)
    } catch {
      // never corrupt the file over one bad path — leave it as-is
    }
  }
  return out
}

function applyOne(text: string, parts: string[], value: string): string {
  const lines = text.split(/\r?\n/)
  let exact: MappingLine | null = null
  // Deepest existing ancestor of the target path (anchorDepth parts matched)
  let anchorDepth = 0
  let anchor: MappingLine | null = null
  let anchorChildIndent = -1
  let anchorLastChild = -1
  let rootLastLine = -1
  let rootChildIndent = -1
  walkMappings(lines, (entry, path) => {
    if (path.length === 1) {
      rootLastLine = entry.index
      if (rootChildIndent < 0) rootChildIndent = entry.indent
    }
    const isPrefix = path.length <= parts.length && path.every((p, i) => p === parts[i])
    if (isPrefix && path.length === parts.length) {
      if (!exact) exact = entry
      return
    }
    if (isPrefix && path.length > anchorDepth) {
      anchorDepth = path.length
      anchor = entry
      anchorChildIndent = -1
      anchorLastChild = entry.index
      return
    }
    // Track the anchor's block so new leaves land after the last sibling
    if (anchor && entry.index > anchor.index && entry.indent > anchor.indent) {
      const insideAnchor = path.length > anchorDepth && path.slice(0, anchorDepth).every((p, i) => p === parts[i])
      if (insideAnchor) {
        anchorLastChild = entry.index
        if (path.length === anchorDepth + 1 && anchorChildIndent < 0) anchorChildIndent = entry.indent
      }
    }
  })
  // casts: TS cannot see the assignments made inside the walker callback
  const e = exact as MappingLine | null
  if (e) {
    const { comment } = splitValueComment(e.rest)
    lines[e.index] = `${e.head} ${formatYamlScalar(value)}${comment}`
    return lines.join('\n')
  }
  const a = anchor as MappingLine | null
  let baseIndent: number
  let insertAfter: number
  if (a) {
    baseIndent = anchorChildIndent >= 0 ? anchorChildIndent : a.indent + 2
    insertAfter = anchorLastChild
    // The matched parent currently holds a scalar — it must become a mapping
    if (a.value !== '' && !isBlockScalar(a.value)) {
      const { comment } = splitValueComment(a.rest)
      lines[a.index] = `${a.head}${comment}`
    }
  } else {
    baseIndent = rootChildIndent >= 0 ? rootChildIndent : 0
    insertAfter = rootLastLine
    if (insertAfter < 0) {
      // No mapping entries at all — append after the last non-blank line
      insertAfter = lines.length - 1
      while (insertAfter >= 0 && lines[insertAfter].trim() === '') insertAfter--
    } else {
      // Skip past the last top-level key's block (children, blanks, comments)
      let i = insertAfter + 1
      while (i < lines.length && (lines[i].trim() === '' || lines[i].trim().startsWith('#') || indentOf(lines[i]) > baseIndent)) {
        if (lines[i].trim() !== '') insertAfter = i
        i++
      }
    }
  }
  const step = a && anchorChildIndent >= 0 ? Math.max(1, anchorChildIndent - a.indent) : 2
  const missing = parts.slice(anchorDepth)
  const inserted: string[] = []
  for (let i = 0; i < missing.length; i++) {
    const indent = ' '.repeat(baseIndent + i * step)
    inserted.push(i === missing.length - 1 ? `${indent}${missing[i]}: ${formatYamlScalar(value)}` : `${indent}${missing[i]}:`)
  }
  lines.splice(insertAfter + 1, 0, ...inserted)
  return lines.join('\n')
}

/** Coerce a bare scalar the way YAML readers do (best-effort, 1.1-ish). */
function coerceScalar(raw: string): unknown {
  const t = raw.trim()
  if (t === '' || t === '~' || /^null$/i.test(t)) return null
  if (t[0] === '"' || t[0] === "'") return unquoteScalar(t)
  if (/^true$/i.test(t)) return true
  if (/^false$/i.test(t)) return false
  if (/^-?\d+(\.\d+)?$/.test(t)) return Number(t)
  return t
}

/**
 * Parse block-style mappings + scalar/list values into a nested object.
 * Lossy for exotic YAML (flow collections stay raw strings, block scalar
 * bodies are dropped, mappings inside list items become plain strings) —
 * fine for the read API this feeds. Never throws on malformed input.
 */
export function parseYaml(text: string): Record<string, unknown> {
  const root: Record<string, unknown> = {}
  try {
    const lines = String(text ?? '').split(/\r?\n/)
    const stack: { indent: number; container: Record<string, unknown> }[] = [{ indent: -1, container: root }]
    // Last `key:` without a value — list items attach to it (YAML allows the
    // `-` at the same indent as the parent key, so plain > checks don't work)
    let pendingList: { indent: number; key: string; container: Record<string, unknown> } | null = null
    let skipBlockIndent = -1
    for (const line of lines) {
      if (skipBlockIndent >= 0) {
        if (line.trim() === '' || indentOf(line) > skipBlockIndent) continue
        skipBlockIndent = -1
      }
      if (isBlankOrComment(line)) continue
      const indent = indentOf(line)
      const body = line.slice(indent)
      if (body.startsWith('- ') || body === '-') {
        if (pendingList && indent >= pendingList.indent) {
          const existing = pendingList.container[pendingList.key]
          const arr: unknown[] = Array.isArray(existing) ? existing : []
          if (!Array.isArray(existing)) pendingList.container[pendingList.key] = arr
          arr.push(coerceScalar(splitValueComment(body === '-' ? '' : body.slice(1).replace(/^[ \t]+/, '')).value))
        }
        continue
      }
      const entry = parseMappingLine(line, 0)
      if (!entry) continue
      while (stack.length > 1 && stack[stack.length - 1].indent >= indent) stack.pop()
      const top = stack[stack.length - 1].container
      if (UNSAFE_KEYS.has(entry.key)) {
        // Discard dangerous keys (and any nested children) into a detached sink
        // so they never touch the real object's prototype.
        if (entry.value === '') stack.push({ indent, container: {} })
        else if (isBlockScalar(entry.value)) skipBlockIndent = indent
        pendingList = null
        continue
      }
      if (entry.value === '') {
        const child: Record<string, unknown> = {}
        top[entry.key] = child
        stack.push({ indent, container: child })
        pendingList = { indent, key: entry.key, container: top }
      } else if (isBlockScalar(entry.value)) {
        top[entry.key] = '' // block scalar content is not reconstructed
        skipBlockIndent = indent
        pendingList = null
      } else {
        top[entry.key] = coerceScalar(entry.value)
        pendingList = null
      }
    }
  } catch {
    // malformed input → best-effort partial result
  }
  return root
}
