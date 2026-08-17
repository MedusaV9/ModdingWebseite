import { Router } from 'express'
import fs from 'node:fs'
import path from 'node:path'
import type { AppContext } from '../context.ts'
import { requireAuth } from '../auth/service.ts'
import { asyncHandler, HttpError, intQuery, makeServerAccess, type ServerRequest } from './helpers.ts'
import { safeJoin } from '../lib/paths.ts'
import { downloadFile } from '../lib/download.ts'
import { getVersions, pickPrimaryFile, searchProjects } from '../lib/modrinth.ts'

interface ModsInfo {
  loader: 'paper' | 'fabric' | 'velocity'
  dir: string
  absDir: string
  mcVersion?: string
}

const JAR_RE = /\.jar$/i

export function modsRouter(ctx: AppContext): Router {
  const router = Router()
  const access = makeServerAccess(ctx.auth, ctx.manager, (id) => ctx.nodes.mirror(id))
  router.use(requireAuth)

  // Installs currently in flight (`serverId:fileName`) so double-clicks
  // cannot race the same download into the same destination.
  const installing = new Set<string>()

  /** Resolve the blueprint's mods block for the request's server (null = unsupported). */
  const modsInfo = (req: ServerRequest): ModsInfo | null => {
    // v1: the mod browser only operates on local servers (remote ones report
    // "unsupported" via GET and a clear 400 elsewhere through requireMods).
    if (ctx.gateway.isRemote(req.gameServer!)) return null
    const inst = ctx.manager.instance(req.gameServer!.id)
    const mods = inst.blueprint.mods
    if (!mods) return null
    let mcVersion: string | undefined
    if (mods.versionVariable) {
      const raw = String(inst.vars[mods.versionVariable] ?? '').trim()
      // Aliases like 'latest' are not real game versions and would match
      // nothing when passed as a Modrinth versions facet — skip the filter.
      if (/^\d+(\.\d+)*$/.test(raw)) mcVersion = raw
    }
    return { loader: mods.loader, dir: mods.dir, absDir: safeJoin(inst.serverDir, mods.dir), mcVersion }
  }

  const requireMods = (req: ServerRequest): ModsInfo => {
    const info = modsInfo(req)
    if (!info) throw new HttpError(400, 'this server does not support mods/plugins')
    return info
  }

  const listInstalled = (absDir: string): { fileName: string; sizeBytes: number; modifiedAt: string }[] => {
    let names: string[]
    try {
      names = fs.readdirSync(absDir)
    } catch {
      return [] // mods dir not created yet
    }
    const out: { fileName: string; sizeBytes: number; modifiedAt: string }[] = []
    for (const name of names) {
      if (!JAR_RE.test(name)) continue
      try {
        const stat = fs.statSync(path.join(absDir, name))
        if (stat.isFile()) out.push({ fileName: name, sizeBytes: stat.size, modifiedAt: stat.mtime.toISOString() })
      } catch {
        /* deleted mid-listing */
      }
    }
    return out.sort((a, b) => a.fileName.localeCompare(b.fileName))
  }

  router.get('/servers/:id/mods', access('server.files.read'), (req: ServerRequest, res) => {
    const info = modsInfo(req)
    if (!info) {
      res.json({ supported: false, installed: [] })
      return
    }
    res.json({
      supported: true,
      loader: info.loader,
      dir: info.dir,
      mcVersion: info.mcVersion,
      installed: listInstalled(info.absDir),
    })
  })

  router.get(
    '/servers/:id/mods/search',
    access('server.files.read'),
    asyncHandler(async (req: ServerRequest, res) => {
      const info = requireMods(req)
      const q = String(req.query.q ?? '').trim()
      if (q.length < 1 || q.length > 100) throw new HttpError(400, 'q must be 1-100 characters')
      const limit = intQuery(req.query.limit, 20, 1, 50)
      const hits = await searchProjects({ query: q, loader: info.loader, mcVersion: info.mcVersion, limit })
      res.json({ loader: info.loader, mcVersion: info.mcVersion, hits })
    }),
  )

  router.get(
    '/servers/:id/mods/versions',
    access('server.files.read'),
    asyncHandler(async (req: ServerRequest, res) => {
      const info = requireMods(req)
      const projectId = String(req.query.projectId ?? '').trim()
      if (projectId.length < 1 || projectId.length > 100) throw new HttpError(400, 'projectId required')
      const versions = await getVersions(projectId, { loader: info.loader, mcVersion: info.mcVersion })
      res.json({ versions })
    }),
  )

  router.post(
    '/servers/:id/mods/install',
    access('server.files.write'),
    asyncHandler(async (req: ServerRequest, res) => {
      const info = requireMods(req)
      const projectId = String(req.body?.projectId ?? '').trim()
      if (projectId.length < 1 || projectId.length > 100) throw new HttpError(400, 'projectId required')
      const versionId = req.body?.versionId === undefined ? undefined : String(req.body.versionId)

      // Newest compatible version first; a pinned versionId must be among them.
      const versions = await getVersions(projectId, { loader: info.loader, mcVersion: info.mcVersion })
      const version = versionId ? versions.find((v) => v.id === versionId) : versions[0]
      if (!version) throw new HttpError(404, versionId ? 'version not found or not compatible' : 'no compatible version found')
      const file = pickPrimaryFile(version)
      if (!file || !file.url) throw new HttpError(404, 'version has no downloadable file')

      const fileName = path.basename(file.filename.replace(/\\/g, '/'))
      if (!JAR_RE.test(fileName)) throw new HttpError(400, 'only .jar files are supported')
      const dest = safeJoin(info.absDir, fileName)
      if (fs.existsSync(dest) && req.body?.overwrite !== true) throw new HttpError(400, 'already installed')

      const key = `${req.gameServer!.id}:${fileName}`
      if (installing.has(key)) throw new HttpError(409, 'install already in progress')
      installing.add(key)
      try {
        fs.mkdirSync(info.absDir, { recursive: true })
        const { bytes } = await downloadFile(file.url, dest, { sha512: file.sha512, timeoutMs: 5 * 60 * 1000 })
        ctx.audit.log(req, 'server.mod_installed', {
          target: fileName,
          serverId: req.gameServer!.id,
          meta: { projectId, versionId: version.id, versionNumber: version.versionNumber },
        })
        res.json({ ok: true, fileName, sizeBytes: bytes })
      } finally {
        installing.delete(key)
      }
    }),
  )

  router.delete('/servers/:id/mods/:fileName', access('server.files.write'), (req: ServerRequest, res) => {
    const info = requireMods(req)
    const fileName = path.basename(String(req.params.fileName ?? '').replace(/\\/g, '/'))
    if (!JAR_RE.test(fileName)) throw new HttpError(400, 'only .jar files are supported')
    const target = safeJoin(info.absDir, fileName)
    let stat: fs.Stats
    try {
      stat = fs.statSync(target)
    } catch {
      throw new HttpError(404, 'file not found')
    }
    if (!stat.isFile()) throw new HttpError(404, 'file not found')
    fs.rmSync(target)
    ctx.audit.log(req, 'server.mod_removed', { target: fileName, serverId: req.gameServer!.id })
    res.json({ ok: true })
  })

  return router
}
