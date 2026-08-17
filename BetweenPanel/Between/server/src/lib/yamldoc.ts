/**
 * Whole-document YAML parser + dumper for *template files* (data/templates).
 *
 * This is deliberately separate from lib/yaml.ts: that module does surgical,
 * comment-preserving in-place edits of game config files and cannot represent
 * nested structures inside lists. Template files need the opposite — a full
 * parse of one document into plain JSON values (blueprints contain lists of
 * objects), with no need to preserve formatting.
 *
 * Supported (a pragmatic YAML subset, documented in docs/TEMPLATES.md):
 * - block mappings and nested mappings (space indentation; tabs are rejected)
 * - block sequences (`- item`), including inline mapping items (`- key: v`)
 *   with continuation lines, and nested blocks under a lone `-`
 * - scalars: double-quoted (with \" \\ \n \r \t escapes), single-quoted
 *   ('' = literal quote), and bare scalars with core-schema-ish typing
 *   (true/false, null/~, integers, floats — leading-zero numerals like `007`
 *   stay strings on purpose, so version-ish values survive)
 * - block scalars `|`, `|-`, `|+` (literal) and `>`, `>-` (folded)
 * - one-line flow collections `[a, b]` / `{k: v}`, nestable
 * - `#` comments (full-line and trailing), a single leading `---`
 *
 * Rejected with a clear error: anchors/aliases/tags (`&`, `*`, `!`),
 * multi-document files, tab indentation. Keys named __proto__/constructor/
 * prototype are rejected (prototype-pollution guard, same stance as
 * lib/toml.ts / lib/yaml.ts).
 */

export class YamlDocError extends Error {
  constructor(message: string, public line: number) {
    super(`line ${line}: ${message}`)
    this.name = 'YamlDocError'
  }
}

const DANGEROUS_KEYS = new Set(['__proto__', 'constructor', 'prototype'])

interface Line {
  /** 1-based line number in the source (for errors). */
  no: number
  text: string
  indent: number
}

function isBlank(text: string): boolean {
  const t = text.trim()
  return t === '' || t.startsWith('#')
}

/** Strip a trailing ` # comment` from an unquoted scalar remainder. */
function stripTrailingComment(raw: string): string {
  for (let i = 0; i < raw.length; i++) {
    if (raw[i] === '#' && (i === 0 || raw[i - 1] === ' ' || raw[i - 1] === '\t')) return raw.slice(0, i).trimEnd()
  }
  return raw.trimEnd()
}

function typedScalar(raw: string, lineNo: number): unknown {
  const t = raw.trim()
  if (t === '' || t === '~' || t === 'null' || t === 'Null' || t === 'NULL') return null
  if (t === 'true' || t === 'True' || t === 'TRUE') return true
  if (t === 'false' || t === 'False' || t === 'FALSE') return false
  if (t[0] === '&' || t[0] === '*' || t[0] === '!')
    throw new YamlDocError(`anchors/aliases/tags are not supported (got ${JSON.stringify(t.slice(0, 12))})`, lineNo)
  // Integers/floats — but keep leading-zero numerals ("007", "08") as strings.
  if (/^[+-]?\d+$/.test(t) && !/^[+-]?0\d/.test(t)) {
    const n = Number(t)
    if (Number.isSafeInteger(n)) return n
  }
  if (/^[+-]?(\d+\.\d*|\.\d+|\d+)(e[+-]?\d+)?$/i.test(t) && /[.e]/i.test(t) && !/^[+-]?0\d/.test(t)) {
    const n = Number(t)
    if (Number.isFinite(n)) return n
  }
  return t
}

// ---------------------------------------------------------------------------
// Quoted / flow scalars (shared by block + flow contexts)
// ---------------------------------------------------------------------------
/** Parse a quoted string starting at s[pos] (a quote char). Returns [value, next]. */
function parseQuoted(s: string, pos: number, lineNo: number): [string, number] {
  const quote = s[pos]
  let out = ''
  let i = pos + 1
  while (i < s.length) {
    const ch = s[i]
    if (quote === '"' && ch === '\\') {
      const next = s[i + 1]
      out += next === 'n' ? '\n' : next === 'r' ? '\r' : next === 't' ? '\t' : next === '"' ? '"' : next === '\\' ? '\\' : next ?? ''
      i += 2
      continue
    }
    if (ch === quote) {
      if (quote === "'" && s[i + 1] === "'") {
        out += "'"
        i += 2
        continue
      }
      return [out, i + 1]
    }
    out += ch
    i++
  }
  throw new YamlDocError(`unterminated ${quote === '"' ? 'double' : 'single'}-quoted string`, lineNo)
}

/** Recursive one-line flow parser: [a, b], {k: v}, nestable. Returns [value, next]. */
function parseFlow(s: string, pos: number, lineNo: number, depth: number): [unknown, number] {
  if (depth > 32) throw new YamlDocError('flow collection nested too deeply', lineNo)
  while (s[pos] === ' ') pos++
  const ch = s[pos]
  if (ch === '[') {
    const arr: unknown[] = []
    pos++
    for (;;) {
      while (s[pos] === ' ') pos++
      if (s[pos] === ']') return [arr, pos + 1]
      if (pos >= s.length) throw new YamlDocError('unterminated flow sequence (missing ])', lineNo)
      const [value, next] = parseFlow(s, pos, lineNo, depth + 1)
      arr.push(value)
      pos = next
      while (s[pos] === ' ') pos++
      if (s[pos] === ',') pos++
      else if (s[pos] !== ']') throw new YamlDocError('expected , or ] in flow sequence', lineNo)
    }
  }
  if (ch === '{') {
    const obj: Record<string, unknown> = {}
    pos++
    for (;;) {
      while (s[pos] === ' ') pos++
      if (s[pos] === '}') return [obj, pos + 1]
      if (pos >= s.length) throw new YamlDocError('unterminated flow mapping (missing })', lineNo)
      let key: string
      if (s[pos] === '"' || s[pos] === "'") {
        const [k, next] = parseQuoted(s, pos, lineNo)
        key = k
        pos = next
      } else {
        let end = pos
        while (end < s.length && s[end] !== ':' && s[end] !== ',' && s[end] !== '}') end++
        key = s.slice(pos, end).trim()
        pos = end
      }
      while (s[pos] === ' ') pos++
      if (s[pos] !== ':') throw new YamlDocError('expected : in flow mapping', lineNo)
      pos++
      const [value, next] = parseFlow(s, pos, lineNo, depth + 1)
      if (DANGEROUS_KEYS.has(key)) throw new YamlDocError(`key "${key}" is not allowed`, lineNo)
      else obj[key] = value
      pos = next
      while (s[pos] === ' ') pos++
      if (s[pos] === ',') pos++
      else if (s[pos] !== '}') throw new YamlDocError('expected , or } in flow mapping', lineNo)
    }
  }
  if (ch === '"' || ch === "'") {
    const [value, next] = parseQuoted(s, pos, lineNo)
    return [value, next]
  }
  // bare flow scalar: up to , ] } (no comments inside flow)
  let end = pos
  while (end < s.length && s[end] !== ',' && s[end] !== ']' && s[end] !== '}') end++
  return [typedScalar(s.slice(pos, end), lineNo), end]
}

/** Parse the value part after `key:` or `- ` when it is on the same line. */
function parseInlineScalar(raw: string, lineNo: number): unknown {
  const t = raw.trim()
  if (t[0] === '[' || t[0] === '{') {
    const [value, next] = parseFlow(t, 0, lineNo, 0)
    const rest = t.slice(next).trim()
    if (rest !== '' && !rest.startsWith('#')) throw new YamlDocError(`unexpected content after flow collection: ${JSON.stringify(rest)}`, lineNo)
    return value
  }
  if (t[0] === '"' || t[0] === "'") {
    const [value, next] = parseQuoted(t, 0, lineNo)
    const rest = t.slice(next).trim()
    if (rest !== '' && !rest.startsWith('#')) throw new YamlDocError(`unexpected content after quoted string: ${JSON.stringify(rest)}`, lineNo)
    return value
  }
  return typedScalar(stripTrailingComment(t), lineNo)
}

// ---------------------------------------------------------------------------
// Block parser
// ---------------------------------------------------------------------------
class Parser {
  private lines: Line[] = []
  private pos = 0
  /** All source lines (1-based via index+1) — block scalars read from here so
   * comment-looking and blank lines inside them survive verbatim. */
  private raw: string[]

  constructor(text: string) {
    this.raw = text.replace(/^\uFEFF/, '').split(/\r\n|\r|\n/)
    for (let i = 0; i < this.raw.length; i++) {
      const no = i + 1
      const line = this.raw[i]
      if (i === 0 && line.trim() === '---') continue
      if (line.trim() === '---') throw new YamlDocError('multi-document YAML is not supported', no)
      if (isBlank(line)) continue
      const indentMatch = /^[ ]*/.exec(line)![0]
      if (line[indentMatch.length] === '\t' || /\t/.test(indentMatch))
        throw new YamlDocError('tab indentation is not allowed in YAML', no)
      this.lines.push({ no, text: line, indent: indentMatch.length })
    }
  }

  parse(): unknown {
    if (this.lines.length === 0) return null
    const value = this.parseNode(this.lines[0].indent)
    if (this.pos < this.lines.length)
      throw new YamlDocError(`unexpected content at indentation ${this.lines[this.pos].indent}`, this.lines[this.pos].no)
    return value
  }

  private peek(): Line | null {
    return this.pos < this.lines.length ? this.lines[this.pos] : null
  }

  /** Parse the node whose first line sits at exactly `indent`. */
  private parseNode(indent: number): unknown {
    const line = this.peek()
    if (!line || line.indent < indent) return null
    const body = line.text.slice(line.indent)
    if (body === '-' || body.startsWith('- ')) return this.parseSequence(indent)
    return this.parseMapping(indent)
  }

  private parseSequence(indent: number): unknown[] {
    const out: unknown[] = []
    for (;;) {
      const line = this.peek()
      if (!line || line.indent !== indent) break
      const body = line.text.slice(line.indent)
      if (body !== '-' && !body.startsWith('- ')) break
      if (body === '-') {
        this.pos++
        const next = this.peek()
        out.push(next && next.indent > indent ? this.parseNode(next.indent) : null)
        continue
      }
      // Inline content after the dash: re-anchor the line at the content
      // column so `- key: v` + continuation lines parse as one mapping.
      const restCol = line.indent + (body.length - body.slice(1).trimStart().length)
      const rest = line.text.slice(restCol)
      if (this.looksLikeMappingStart(rest)) {
        this.lines[this.pos] = { no: line.no, text: ' '.repeat(restCol) + rest, indent: restCol }
        out.push(this.parseMapping(restCol))
        continue
      }
      this.pos++
      if (rest === '|' || rest === '|-' || rest === '|+' || rest === '>' || rest === '>-') {
        out.push(this.parseBlockScalar(indent, rest, line.no))
      } else {
        const stripped = stripTrailingComment(rest)
        if (stripped === '') out.push(null)
        else out.push(parseInlineScalar(stripped, line.no))
      }
    }
    return out
  }

  /** `key:` or `key: value` where key is bare (no colon) or quoted. */
  private looksLikeMappingStart(rest: string): boolean {
    if (rest.startsWith('- ')) return false
    const key = this.tryReadKey(rest)
    return key !== null
  }

  /** Returns [key, remainder-after-colon] or null when `rest` is not a `key:` line. */
  private tryReadKey(rest: string): [string, string] | null {
    if (rest[0] === '"' || rest[0] === "'") {
      try {
        const [key, next] = parseQuoted(rest, 0, 0)
        const after = rest.slice(next)
        if (after.startsWith(':') && (after.length === 1 || after[1] === ' ')) return [key, after.slice(1)]
      } catch {
        return null
      }
      return null
    }
    // Bare key: everything before the first `: ` or a trailing `:`; keys with
    // colons inside URLs etc. must be quoted.
    const m = /^([^:#]+?):(?: (.*))?$/.exec(rest)
    if (!m) return null
    return [m[1].trim(), m[2] ?? '']
  }

  private parseMapping(indent: number): Record<string, unknown> {
    const out: Record<string, unknown> = {}
    for (;;) {
      const line = this.peek()
      if (!line || line.indent !== indent) break
      const body = line.text.slice(line.indent)
      if (body === '-' || body.startsWith('- ')) break
      const kv = this.tryReadKey(body)
      if (!kv) throw new YamlDocError(`expected "key: value" (got ${JSON.stringify(body.slice(0, 40))})`, line.no)
      const [key, restRaw] = kv
      if (DANGEROUS_KEYS.has(key)) throw new YamlDocError(`key "${key}" is not allowed`, line.no)
      if (Object.hasOwn(out, key)) throw new YamlDocError(`duplicate key "${key}"`, line.no)
      this.pos++
      const rest = restRaw.trim()
      if (rest === '' || rest.startsWith('#')) {
        const next = this.peek()
        if (next && next.indent > indent) out[key] = this.parseNode(next.indent)
        else out[key] = null
      } else if (rest === '|' || rest === '|-' || rest === '|+' || rest === '>' || rest === '>-') {
        out[key] = this.parseBlockScalar(indent, rest, line.no)
      } else {
        out[key] = parseInlineScalar(rest, line.no)
      }
    }
    return out
  }

  private parseBlockScalar(parentIndent: number, header: string, headerLine: number): string {
    const folded = header[0] === '>'
    const chomp = header.endsWith('-') ? 'strip' : header.endsWith('+') ? 'keep' : 'clip'
    // Read from the RAW source: inside a block scalar, `# comment`-looking and
    // blank lines are literal content and must survive verbatim.
    const collected: string[] = []
    let blockIndent = -1
    let rawIdx = headerLine // 0-based index of the first line after the header
    let lastConsumedNo = headerLine
    const pendingBlanks: string[] = []
    while (rawIdx < this.raw.length) {
      const line = this.raw[rawIdx]
      if (line.trim() === '') {
        pendingBlanks.push('')
        rawIdx++
        continue
      }
      const indent = /^[ ]*/.exec(line)![0].length
      if (blockIndent === -1) {
        if (indent <= parentIndent) break // empty block
        blockIndent = indent
      }
      if (indent < blockIndent) break
      // Interior blank lines belong to the block; trailing ones are chomped below.
      collected.push(...pendingBlanks.splice(0))
      collected.push(line.slice(blockIndent))
      lastConsumedNo = rawIdx + 1
      rawIdx++
    }
    // Skip every significant line the block consumed.
    while (this.pos < this.lines.length && this.lines[this.pos].no <= lastConsumedNo) this.pos++
    let content: string
    if (folded) {
      const outLines: string[] = []
      let paragraphOpen = false
      for (const l of collected) {
        if (l === '') {
          outLines.push('')
          paragraphOpen = false
        } else if (paragraphOpen) {
          outLines[outLines.length - 1] += ' ' + l
        } else {
          outLines.push(l)
          paragraphOpen = true
        }
      }
      content = outLines.join('\n')
    } else {
      content = collected.join('\n')
    }
    if (chomp === 'strip') return content.replace(/\n+$/, '')
    if (chomp === 'keep') return content + '\n'
    const clipped = content.replace(/\n+$/, '')
    return clipped === '' ? '' : clipped + '\n'
  }
}

/** Parse one YAML document into plain JSON values. Throws YamlDocError. */
export function parseYamlDoc(text: string): unknown {
  return new Parser(text).parse()
}

// ---------------------------------------------------------------------------
// Dumper (used by scripts/export-template.ts and tests)
// ---------------------------------------------------------------------------
const BARE_SAFE = /^[A-Za-z0-9_][A-Za-z0-9_ .\-/]*$/

function scalarNeedsQuoting(s: string): boolean {
  if (s === '') return true
  if (!BARE_SAFE.test(s)) return true
  if (s !== s.trim()) return true
  // Would be re-typed on parse (bool/null/number-looking, incl. leading zeros).
  if (/^(true|false|null|~|True|False|Null|TRUE|FALSE|NULL)$/.test(s)) return true
  if (/^[+-]?[\d.]/.test(s) && /^[+-]?(\d+\.?\d*|\.\d+)(e[+-]?\d+)?$/i.test(s)) return true
  return false
}

function dumpScalar(v: unknown, indent: string): string {
  if (v === null || v === undefined) return 'null'
  if (typeof v === 'number' || typeof v === 'boolean') return JSON.stringify(v)
  const s = String(v)
  if (s.includes('\n')) {
    const body = s
      .replace(/\n$/, '')
      .split('\n')
      .map((l) => (l === '' ? '' : indent + '  ' + l))
      .join('\n')
    return (s.endsWith('\n') ? '|\n' : '|-\n') + body
  }
  return scalarNeedsQuoting(s) ? JSON.stringify(s) : s
}

function dumpNode(v: unknown, indent: string): string {
  if (Array.isArray(v)) {
    if (v.length === 0) return '[]'
    return v
      .map((item) => {
        if (item !== null && typeof item === 'object') {
          const body = dumpNode(item, indent + '  ')
          // Fold the first line of a mapping onto the dash.
          const lines = body.split('\n')
          return `${indent}- ${lines[0].trimStart()}${lines.length > 1 ? '\n' + lines.slice(1).join('\n') : ''}`
        }
        return `${indent}- ${dumpScalar(item, indent)}`
      })
      .join('\n')
  }
  if (v !== null && typeof v === 'object') {
    const entries = Object.entries(v as Record<string, unknown>)
    if (entries.length === 0) return '{}'
    return entries
      .map(([key, value]) => {
        const k = BARE_SAFE.test(key) && !scalarNeedsQuoting(key) ? key : JSON.stringify(key)
        if (Array.isArray(value)) {
          if (value.length === 0) return `${indent}${k}: []`
          return `${indent}${k}:\n${dumpNode(value, indent + '  ')}`
        }
        if (value !== null && typeof value === 'object') {
          const obj = value as Record<string, unknown>
          if (Object.keys(obj).length === 0) return `${indent}${k}: {}`
          return `${indent}${k}:\n${dumpNode(value, indent + '  ')}`
        }
        return `${indent}${k}: ${dumpScalar(value, indent)}`
      })
      .join('\n')
  }
  return indent + dumpScalar(v, indent)
}

/** Serialize plain JSON values to a YAML document parseable by parseYamlDoc. */
export function stringifyYamlDoc(value: unknown): string {
  return dumpNode(value, '') + '\n'
}
