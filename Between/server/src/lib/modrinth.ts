/**
 * Minimal Modrinth v2 API client (search + version listing) used by the mods
 * API. Uses global fetch only — no runtime dependencies.
 */

const DEFAULT_BASE = 'https://api.modrinth.com/v2'

/** Read lazily so tests can point the client at a local mock via env. */
export function apiBase(): string {
  return process.env.MODRINTH_API_BASE ?? DEFAULT_BASE
}

// Modrinth requires an identifying User-Agent on all API requests.
const USER_AGENT = 'between-panel/0.1 (github.com/MedusaV9/BiggerRepo)'
const TIMEOUT_MS = 15000
const MAX_LIMIT = 50

export interface ModrinthSearchHit {
  projectId: string
  slug: string
  title: string
  description: string
  downloads: number
  iconUrl: string | null
  projectType: string
}

export interface ModrinthVersionFile {
  url: string
  filename: string
  primary: boolean
  size: number
  sha512?: string
  sha1?: string
}

export interface ModrinthVersion {
  id: string
  name: string
  versionNumber: string
  gameVersions: string[]
  loaders: string[]
  datePublished: string
  files: ModrinthVersionFile[]
}

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v)
}

async function getJson(pathAndQuery: string, what: string): Promise<unknown> {
  let res: Response
  try {
    res = await fetch(`${apiBase()}${pathAndQuery}`, {
      signal: AbortSignal.timeout(TIMEOUT_MS),
      headers: { 'user-agent': USER_AGENT, accept: 'application/json' },
    })
  } catch (err) {
    throw new Error(`modrinth ${what} failed: ${err instanceof Error ? err.message : String(err)}`)
  }
  if (!res.ok) throw new Error(`modrinth ${what} failed: HTTP ${res.status}`)
  try {
    return await res.json()
  } catch {
    throw new Error(`modrinth ${what} failed: invalid JSON response`)
  }
}

/**
 * Search projects for a given loader (and optionally a Minecraft version).
 *
 * Facet syntax verified empirically against the live API (2026-07):
 *   facets=[["categories:paper"]]                        → Paper plugins
 *   facets=[["categories:fabric"],["versions:1.21.1"]]   → Fabric mods for MC 1.21.1
 *   facets=[["categories:velocity"]]                     → Velocity plugins
 * The "categories" facet holds loaders and the "versions" facet holds game
 * versions; inner arrays are OR'd, outer arrays are AND'd. No project_type
 * facet is needed — filtering on the loader already selects plugins
 * (paper/velocity) vs mods (fabric). Note that search hits report
 * `project_type: "mod"` even for plugins (`all_project_types` carries the
 * real list), so the mapped projectType is informational only.
 */
export async function searchProjects(opts: {
  query: string
  loader: string
  mcVersion?: string
  limit?: number
}): Promise<ModrinthSearchHit[]> {
  const facets: string[][] = [[`categories:${opts.loader}`]]
  if (opts.mcVersion) facets.push([`versions:${opts.mcVersion}`])
  const limit = Math.min(MAX_LIMIT, Math.max(1, Math.trunc(opts.limit ?? 20)))
  const params = new URLSearchParams({ query: opts.query, facets: JSON.stringify(facets), limit: String(limit) })
  const body = await getJson(`/search?${params}`, 'search')
  if (!isRecord(body) || !Array.isArray(body.hits)) throw new Error('modrinth search failed: unexpected response shape')
  return body.hits.filter(isRecord).map((h) => ({
    projectId: String(h.project_id ?? ''),
    slug: String(h.slug ?? ''),
    title: String(h.title ?? ''),
    description: String(h.description ?? ''),
    downloads: Number(h.downloads ?? 0),
    iconUrl: typeof h.icon_url === 'string' && h.icon_url.length > 0 ? h.icon_url : null,
    projectType: String(h.project_type ?? ''),
  }))
}

/** List a project's versions filtered by loader (and optionally MC version), newest first. */
export async function getVersions(projectId: string, opts: { loader: string; mcVersion?: string }): Promise<ModrinthVersion[]> {
  const params = new URLSearchParams({ loaders: JSON.stringify([opts.loader]) })
  if (opts.mcVersion) params.set('game_versions', JSON.stringify([opts.mcVersion]))
  const body = await getJson(`/project/${encodeURIComponent(projectId)}/version?${params}`, 'versions')
  if (!Array.isArray(body)) throw new Error('modrinth versions failed: unexpected response shape')
  return body.filter(isRecord).map((v) => {
    const files = Array.isArray(v.files) ? v.files.filter(isRecord) : []
    return {
      id: String(v.id ?? ''),
      name: String(v.name ?? ''),
      versionNumber: String(v.version_number ?? ''),
      gameVersions: Array.isArray(v.game_versions) ? v.game_versions.map(String) : [],
      loaders: Array.isArray(v.loaders) ? v.loaders.map(String) : [],
      datePublished: String(v.date_published ?? ''),
      files: files.map((f) => {
        const hashes = isRecord(f.hashes) ? f.hashes : {}
        return {
          url: String(f.url ?? ''),
          filename: String(f.filename ?? ''),
          primary: f.primary === true,
          size: Number(f.size ?? 0),
          sha512: typeof hashes.sha512 === 'string' ? hashes.sha512 : undefined,
          sha1: typeof hashes.sha1 === 'string' ? hashes.sha1 : undefined,
        }
      }),
    }
  })
}

/** The file marked primary, falling back to the first file. */
export function pickPrimaryFile(version: ModrinthVersion): ModrinthVersionFile | null {
  return version.files.find((f) => f.primary) ?? version.files[0] ?? null
}
