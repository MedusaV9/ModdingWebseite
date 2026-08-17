/**
 * Built-in "Game Library" catalog: a curated list of popular games an admin
 * can add with one click. Entries either reference a blueprint that already
 * ships with Between (`builtin`) or a community Pterodactyl/Pelican egg
 * (`egg-url`) that is fetched from its public repo and converted on add.
 *
 * NOTE: egg URLs point at community sources (raw.githubusercontent.com —
 * pelican-eggs / parkervcp repos). They are fetched on demand, never bundled;
 * if an upstream file moves, the add action surfaces the fetch error and the
 * rest of the catalog keeps working.
 *
 * The JSON data file is shape-checked at module load so a malformed entry
 * fails loudly at boot; the unit test additionally asserts every `builtin`
 * entry references a real builtin blueprint id.
 */
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { assertPublicHttpUrl } from '../lib/nettrust.ts'

export type CatalogSource = { type: 'builtin'; blueprintId: string } | { type: 'egg-url'; url: string }

export interface CatalogEntry {
  id: string
  name: string
  category: string
  description: string
  icon?: string
  color?: string
  source: CatalogSource
}

const ID_RE = /^[a-z0-9][a-z0-9-]{1,63}$/

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v)
}

function validateEntry(entry: unknown, i: number): CatalogEntry {
  if (!isRecord(entry)) throw new Error(`catalog[${i}]: not an object`)
  const where = `catalog[${i}] (${String(entry.id)})`
  if (typeof entry.id !== 'string' || !ID_RE.test(entry.id)) throw new Error(`${where}: id must match ${ID_RE}`)
  if (typeof entry.name !== 'string' || entry.name.trim().length === 0) throw new Error(`${where}: missing name`)
  if (typeof entry.category !== 'string' || entry.category.trim().length === 0) throw new Error(`${where}: missing category`)
  if (typeof entry.description !== 'string' || entry.description.trim().length === 0) throw new Error(`${where}: missing description`)
  if (entry.icon !== undefined && typeof entry.icon !== 'string') throw new Error(`${where}: icon must be a string`)
  if (entry.color !== undefined && typeof entry.color !== 'string') throw new Error(`${where}: color must be a string`)
  const source = entry.source
  if (!isRecord(source)) throw new Error(`${where}: missing source`)
  if (source.type === 'builtin') {
    if (typeof source.blueprintId !== 'string' || source.blueprintId.length === 0)
      throw new Error(`${where}: builtin source needs a blueprintId`)
  } else if (source.type === 'egg-url') {
    if (typeof source.url !== 'string') throw new Error(`${where}: egg-url source needs a url`)
    try {
      assertPublicHttpUrl(source.url)
    } catch (err) {
      throw new Error(`${where}: bad egg url — ${(err as Error).message}`)
    }
  } else {
    throw new Error(`${where}: unknown source type ${JSON.stringify(source.type)}`)
  }
  return entry as unknown as CatalogEntry
}

function loadCatalog(): CatalogEntry[] {
  const here = path.dirname(fileURLToPath(import.meta.url))
  const raw = JSON.parse(fs.readFileSync(path.join(here, 'catalog.json'), 'utf8')) as unknown
  if (!Array.isArray(raw)) throw new Error('catalog.json: expected an array')
  const entries = raw.map(validateEntry)
  const ids = new Set<string>()
  for (const entry of entries) {
    if (ids.has(entry.id)) throw new Error(`catalog: duplicate entry id ${entry.id}`)
    ids.add(entry.id)
  }
  return entries
}

/** The bundled catalog — validated once at module load. */
export const catalogEntries: CatalogEntry[] = loadCatalog()

export function getCatalogEntry(id: string): CatalogEntry | undefined {
  return catalogEntries.find((entry) => entry.id === id)
}

/**
 * The blueprint id a catalog entry maps to: builtin entries use the shipped
 * blueprint id; egg-url entries get a deterministic id so "already added"
 * detection and re-adds work without extra bookkeeping.
 */
export function catalogBlueprintId(entry: CatalogEntry): string {
  return entry.source.type === 'builtin' ? entry.source.blueprintId : `catalog-${entry.id}`
}
