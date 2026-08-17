/**
 * Version resolvers for direct-download server software (PaperMC projects,
 * vanilla Minecraft via Mojang's piston-meta, Fabric via the Fabric meta API).
 */
import { fetchJson } from '../lib/download.ts'

export interface ResolvedDownload {
  url: string
  version: string
  label: string
  sha256?: string
}

// --- PaperMC (paper, velocity, waterfall, folia) -----------------------------
// Uses the Fill v3 API (fill.papermc.io) — the old api.papermc.io/v2 API was
// sunset with HTTP 410 in 2025.
interface FillProject {
  versions: Record<string, string[]>
}
interface FillBuild {
  id: number
  channel: string
  downloads: Record<string, { name: string; url: string; checksums?: { sha256?: string } }>
}

const PRERELEASE_RE = /-(rc|pre|snapshot)/i

export async function resolvePaper(project: string, version: string): Promise<ResolvedDownload> {
  const base = 'https://fill.papermc.io/v3/projects'
  const projectInfo = await fetchJson<FillProject>(`${base}/${project}`)
  const families = Object.values(projectInfo.versions ?? {})
  const all = families.flat()
  if (all.length === 0) throw new Error(`PaperMC project ${project}: no versions`)
  let wanted: string
  if (!version || version === 'latest') {
    // Families and versions are ordered newest-first; skip pre-releases.
    wanted = all.find((v) => !PRERELEASE_RE.test(v)) ?? all[0]
  } else {
    if (!all.includes(version))
      throw new Error(`PaperMC ${project} has no version ${version}. Recent: ${all.slice(0, 8).join(', ')}`)
    wanted = version
  }
  const build = await fetchJson<FillBuild>(`${base}/${project}/versions/${wanted}/builds/latest`)
  const download = build.downloads?.['server:default'] ?? Object.values(build.downloads ?? {})[0]
  if (!download?.url) throw new Error(`PaperMC ${project} ${wanted}: build ${build.id} has no server download`)
  return {
    url: download.url,
    version: wanted,
    label: `${project} ${wanted} build ${build.id}`,
    sha256: download.checksums?.sha256,
  }
}

// --- Vanilla Minecraft --------------------------------------------------------
interface MojangManifest {
  latest: { release: string; snapshot: string }
  versions: { id: string; type: string; url: string }[]
}
interface MojangVersion {
  downloads: { server?: { url: string; sha1: string } }
}

export async function resolveVanilla(version: string): Promise<ResolvedDownload> {
  const manifest = await fetchJson<MojangManifest>('https://piston-meta.mojang.com/mc/game/version_manifest_v2.json')
  const wanted = !version || version === 'latest' ? manifest.latest.release : version
  const meta = manifest.versions.find((v) => v.id === wanted)
  if (!meta) throw new Error(`Minecraft version ${wanted} not found in Mojang manifest`)
  const detail = await fetchJson<MojangVersion>(meta.url)
  if (!detail.downloads.server) throw new Error(`Minecraft ${wanted} has no server download`)
  return { url: detail.downloads.server.url, version: wanted, label: `vanilla ${wanted}` }
}

// --- Fabric --------------------------------------------------------------------
interface FabricGameVersion {
  version: string
  stable: boolean
}
interface FabricLoader {
  loader: { version: string; stable: boolean }
}
interface FabricInstaller {
  version: string
  stable: boolean
}

export async function resolveFabric(version: string): Promise<ResolvedDownload> {
  const meta = 'https://meta.fabricmc.net/v2/versions'
  let wanted = version
  if (!wanted || wanted === 'latest') {
    const games = await fetchJson<FabricGameVersion[]>(`${meta}/game`)
    wanted = games.find((g) => g.stable)?.version ?? games[0]?.version
    if (!wanted) throw new Error('Fabric meta returned no game versions')
  }
  const loaders = await fetchJson<FabricLoader[]>(`${meta}/loader/${wanted}`)
  const loader = loaders.find((l) => l.loader.stable)?.loader.version ?? loaders[0]?.loader.version
  if (!loader) throw new Error(`Fabric has no loader for Minecraft ${wanted}`)
  const installers = await fetchJson<FabricInstaller[]>(`${meta}/installer`)
  const installer = installers.find((i) => i.stable)?.version ?? installers[0]?.version
  if (!installer) throw new Error('Fabric meta returned no installer versions')
  return {
    url: `${meta}/loader/${wanted}/${loader}/${installer}/server/jar`,
    version: wanted,
    label: `fabric ${wanted} (loader ${loader})`,
  }
}
