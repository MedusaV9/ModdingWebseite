/**
 * Parsers/serializers for common game config formats, used to sync blueprint
 * variables into real config files (server.properties, .ini, .json, .yml,
 * .toml, ...). All apply* functions update ONLY the given keys and preserve
 * every other line, comment and formatting detail.
 */
import { applyYaml, getYamlValue } from './yaml.ts'
import { applyToml, parseToml } from './toml.ts'
import type { ConfigFileSpec } from '../types.ts'

// --- .properties (Minecraft style: key=value, # comments) -------------------
export function parseProperties(text: string): Record<string, string> {
  const out: Record<string, string> = {}
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim()
    if (!line || line.startsWith('#') || line.startsWith('!')) continue
    const eq = line.indexOf('=')
    if (eq < 0) continue
    out[line.slice(0, eq).trim()] = line.slice(eq + 1).trim()
  }
  return out
}

export function applyProperties(text: string, updates: Record<string, string>): string {
  const remaining = new Map(Object.entries(updates))
  const lines = text.split(/\r?\n/).map((rawLine) => {
    const line = rawLine.trim()
    if (!line || line.startsWith('#') || line.startsWith('!')) return rawLine
    const eq = line.indexOf('=')
    if (eq < 0) return rawLine
    const key = line.slice(0, eq).trim()
    if (remaining.has(key)) {
      const value = remaining.get(key)!
      remaining.delete(key)
      return `${key}=${value}`
    }
    return rawLine
  })
  for (const [key, value] of remaining) lines.push(`${key}=${value}`)
  return lines.join('\n')
}

// --- .ini (sections, key=value) ---------------------------------------------
// Mapping keys may use "section.key" or plain "key" for the global section.
export function applyIni(text: string, updates: Record<string, string>): string {
  const remaining = new Map(Object.entries(updates))
  const lines = text.split(/\r?\n/)
  let section = ''
  const out: string[] = []
  // Position in `out` right after each section header, so new keys can be
  // inserted into an EXISTING section instead of emitting a duplicate
  // [section] header at the end (many game .ini parsers ignore duplicates).
  const sectionStart = new Map<string, number>([['', 0]])
  for (const rawLine of lines) {
    const line = rawLine.trim()
    const sectionMatch = line.match(/^\[(.+)\]$/)
    if (sectionMatch) {
      section = sectionMatch[1]
      out.push(rawLine)
      if (!sectionStart.has(section)) sectionStart.set(section, out.length)
      continue
    }
    if (!line || line.startsWith(';') || line.startsWith('#')) {
      out.push(rawLine)
      continue
    }
    const eq = line.indexOf('=')
    if (eq < 0) {
      out.push(rawLine)
      continue
    }
    const key = line.slice(0, eq).trim()
    const fullKey = section ? `${section}.${key}` : key
    if (remaining.has(fullKey)) {
      out.push(`${key}=${remaining.get(fullKey)!}`)
      remaining.delete(fullKey)
    } else if (!section && remaining.has(key)) {
      out.push(`${key}=${remaining.get(key)!}`)
      remaining.delete(key)
    } else {
      out.push(rawLine)
    }
  }
  // Group leftovers by target section
  const bySection = new Map<string, [string, string][]>()
  for (const [fullKey, value] of remaining) {
    const dot = fullKey.indexOf('.')
    const sec = dot > 0 ? fullKey.slice(0, dot) : ''
    const key = dot > 0 ? fullKey.slice(dot + 1) : fullKey
    const list = bySection.get(sec) ?? []
    list.push([key, value])
    bySection.set(sec, list)
  }
  // Insert into existing sections (descending positions so earlier splices
  // don't shift later ones); brand-new sections are appended at the end.
  const inserts: { at: number; kv: string[] }[] = []
  const appends: string[] = []
  for (const [sec, pairs] of bySection) {
    const kv = pairs.map(([key, value]) => `${key}=${value}`)
    const at = sectionStart.get(sec)
    if (at !== undefined) inserts.push({ at, kv })
    else appends.push(`[${sec}]`, ...kv)
  }
  inserts.sort((a, b) => b.at - a.at)
  for (const { at, kv } of inserts) out.splice(at, 0, ...kv)
  out.push(...appends)
  return out.join('\n')
}

// --- JSON with dot-path mapping ----------------------------------------------
// Keys that would mutate Object.prototype instead of the target object.
const UNSAFE_JSON_KEYS = new Set(['__proto__', 'constructor', 'prototype'])

export function applyJsonPath(obj: Record<string, unknown>, dotPath: string, value: unknown): void {
  const parts = dotPath.split('.')
  if (parts.some((p) => UNSAFE_JSON_KEYS.has(p))) return // never write through a prototype-polluting key
  let cursor: Record<string, unknown> = obj
  for (let i = 0; i < parts.length - 1; i++) {
    const part = parts[i]
    if (typeof cursor[part] !== 'object' || cursor[part] === null) cursor[part] = {}
    cursor = cursor[part] as Record<string, unknown>
  }
  cursor[parts[parts.length - 1]] = value
}

export function applyJson(text: string, updates: Record<string, string>): string {
  let obj: Record<string, unknown>
  try {
    obj = JSON.parse(text || '{}') as Record<string, unknown>
  } catch {
    obj = {}
  }
  for (const [dotPath, raw] of Object.entries(updates)) {
    let value: unknown = raw
    if (raw === 'true') value = true
    else if (raw === 'false') value = false
    else if (/^-?\d+(\.\d+)?$/.test(raw)) value = Number(raw)
    applyJsonPath(obj, dotPath, value)
  }
  return JSON.stringify(obj, null, 2)
}

// --- key value ("key value" lines, e.g. Source cfg) ---------------------------
export function applyKeyValue(text: string, updates: Record<string, string>): string {
  const remaining = new Map(Object.entries(updates))
  const lines = text.split(/\r?\n/).map((rawLine) => {
    const line = rawLine.trim()
    if (!line || line.startsWith('//') || line.startsWith('#')) return rawLine
    const m = line.match(/^(\S+)\s+(.*)$/)
    if (!m) return rawLine
    const key = m[1]
    if (remaining.has(key)) {
      const value = remaining.get(key)!
      remaining.delete(key)
      const quoted = /\s/.test(value) || value === '' ? `"${value}"` : value
      return `${key} ${quoted}`
    }
    return rawLine
  })
  for (const [key, value] of remaining) {
    const quoted = /\s/.test(value) || value === '' ? `"${value}"` : value
    lines.push(`${key} ${quoted}`)
  }
  return lines.join('\n')
}

// --- format dispatch -----------------------------------------------------------
// Shared by the config sync and the config-files API so both use the exact
// same engine per format. 'raw' has no key structure and is never applied here.
export type StructuredFormat = Exclude<ConfigFileSpec['format'], 'raw'>

export function isStructuredFormat(format: string): format is StructuredFormat {
  return ['properties', 'ini', 'json', 'keyvalue', 'yaml', 'toml'].includes(format)
}

/** Apply key updates to a config document using the engine for its format. */
export function applyConfigUpdates(format: StructuredFormat, text: string, updates: Record<string, string>): string {
  switch (format) {
    case 'properties':
      return applyProperties(text, updates)
    case 'ini':
      return applyIni(text, updates)
    case 'json':
      return applyJson(text, updates)
    case 'keyvalue':
      return applyKeyValue(text, updates)
    case 'yaml':
      return applyYaml(text, updates)
    case 'toml':
      return applyToml(text, updates)
  }
}

/** Walk a nested object along a dot-path; scalar leaves come back as strings. */
function scalarAtPath(obj: Record<string, unknown>, dotPath: string): string | undefined {
  let cursor: unknown = obj
  for (const part of dotPath.split('.')) {
    if (typeof cursor !== 'object' || cursor === null || Array.isArray(cursor)) return undefined
    cursor = (cursor as Record<string, unknown>)[part]
  }
  if (cursor === undefined || cursor === null) return undefined
  if (typeof cursor === 'object') return undefined
  return String(cursor)
}

/**
 * Read the current value of one config key from a document (for the config
 * read API). Best-effort: malformed documents yield undefined, never throw.
 */
export function getConfigValue(format: StructuredFormat, text: string, keyPath: string): string | undefined {
  switch (format) {
    case 'properties':
      return parseProperties(text)[keyPath]
    case 'ini': {
      // mapping keys use "section.key" or plain "key" for the global section
      const dot = keyPath.indexOf('.')
      const wantSection = dot > 0 ? keyPath.slice(0, dot) : ''
      const wantKey = dot > 0 ? keyPath.slice(dot + 1) : keyPath
      let section = ''
      for (const rawLine of text.split(/\r?\n/)) {
        const line = rawLine.trim()
        const sectionMatch = line.match(/^\[(.+)\]$/)
        if (sectionMatch) {
          section = sectionMatch[1]
          continue
        }
        if (!line || line.startsWith(';') || line.startsWith('#')) continue
        const eq = line.indexOf('=')
        if (eq < 0) continue
        if (section === wantSection && line.slice(0, eq).trim() === wantKey) return line.slice(eq + 1).trim()
      }
      return undefined
    }
    case 'json': {
      try {
        return scalarAtPath(JSON.parse(text || '{}') as Record<string, unknown>, keyPath)
      } catch {
        return undefined
      }
    }
    case 'keyvalue': {
      for (const rawLine of text.split(/\r?\n/)) {
        const line = rawLine.trim()
        if (!line || line.startsWith('//') || line.startsWith('#')) continue
        const m = line.match(/^(\S+)\s+(.*)$/)
        if (m && m[1] === keyPath) return m[2].replace(/^"(.*)"$/, '$1')
      }
      return undefined
    }
    case 'yaml':
      return getYamlValue(text, keyPath)
    case 'toml':
      return scalarAtPath(parseToml(text), keyPath)
  }
}
