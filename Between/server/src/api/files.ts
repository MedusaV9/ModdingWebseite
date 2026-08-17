import { Router } from 'express'
import fs from 'node:fs'
import path from 'node:path'
import { Readable, Transform } from 'node:stream'
import { pipeline } from 'node:stream/promises'
import type { AppContext } from '../context.ts'
import { requireAuth } from '../auth/service.ts'
import { asyncHandler, HttpError, makeServerAccess, type ServerRequest } from './helpers.ts'
import * as files from '../services/files.ts'
import { safeJoin } from '../lib/paths.ts'
import { zipDirectory } from '../lib/zip.ts'

const MAX_UPLOAD = 4 * 1024 * 1024 * 1024 // 4 GiB

export function filesRouter(ctx: AppContext): Router {
  const router = Router()
  const access = makeServerAccess(ctx.auth, ctx.manager, (id) => ctx.nodes.mirror(id))
  router.use(requireAuth)

  const dirOf = (req: ServerRequest) => ctx.manager.instance(req.gameServer!.id).serverDir
  const isRemote = (req: ServerRequest) => ctx.gateway.isRemote(req.gameServer!)

  router.get(
    '/servers/:id/files',
    access('server.files.read'),
    asyncHandler(async (req: ServerRequest, res) => {
      const rel = String(req.query.path ?? '')
      if (isRemote(req)) {
        res.json(await ctx.gateway.proxy(req.gameServer!, (client) => client.listFiles(req.gameServer!.id, rel)))
        return
      }
      res.json({ path: rel, entries: files.listDir(dirOf(req), rel) })
    }),
  )

  router.get(
    '/servers/:id/files/content',
    access('server.files.read'),
    asyncHandler(async (req: ServerRequest, res) => {
      const rel = String(req.query.path ?? '')
      if (!rel) throw new HttpError(400, 'path required')
      if (isRemote(req)) {
        res.json(await ctx.gateway.proxy(req.gameServer!, (client) => client.readFile(req.gameServer!.id, rel)))
        return
      }
      res.json({ path: rel, ...files.readTextFile(dirOf(req), rel) })
    }),
  )

  router.put(
    '/servers/:id/files/content',
    access('server.files.write'),
    asyncHandler(async (req: ServerRequest, res) => {
      const { path: rel, content } = req.body ?? {}
      if (!rel) throw new HttpError(400, 'path required')
      if (typeof content !== 'string') throw new HttpError(400, 'content must be a string')
      if (content.length > 10 * 1024 * 1024) throw new HttpError(400, 'file too large for the editor')
      if (isRemote(req)) {
        await ctx.gateway.proxy(req.gameServer!, (client) => client.writeFile(req.gameServer!.id, String(rel), content))
      } else {
        files.writeTextFile(dirOf(req), String(rel), content)
      }
      ctx.audit.log(req, 'files.write', { target: String(rel), serverId: req.gameServer!.id })
      res.json({ ok: true })
    }),
  )

  router.post(
    '/servers/:id/files/mkdir',
    access('server.files.write'),
    asyncHandler(async (req: ServerRequest, res) => {
      const rel = String(req.body?.path ?? '')
      if (!rel) throw new HttpError(400, 'path required')
      if (isRemote(req)) {
        await ctx.gateway.proxy(req.gameServer!, (client) => client.mkdir(req.gameServer!.id, rel))
      } else {
        files.makeDir(dirOf(req), rel)
      }
      res.json({ ok: true })
    }),
  )

  // Validate a plain file/folder name (single path segment, no traversal).
  const entryName = (value: unknown, what: string): string => {
    const name = String(value ?? '').trim()
    if (!name) throw new HttpError(400, `${what} required`)
    if (name.length > 255) throw new HttpError(400, `${what} too long (max 255 characters)`)
    if (!files.isValidEntryName(name)) throw new HttpError(400, `${what} must not contain path separators or be "." / ".."`)
    return name
  }

  // Same-directory rename only; moving between folders is /files/move.
  router.post('/servers/:id/files/rename', access('server.files.write'), (req: ServerRequest, res) => {
    ctx.gateway.assertLocal(req.gameServer!, 'renaming files')
    const rel = String(req.body?.path ?? '')
    if (!rel) throw new HttpError(400, 'path required')
    const newName = entryName(req.body?.newName, 'newName')
    let renamed: { rel: string }
    try {
      renamed = files.renameWithin(dirOf(req), rel, newName)
    } catch (err) {
      if (err instanceof files.FileConflictError) throw new HttpError(409, err.message)
      throw err
    }
    ctx.audit.log(req, 'files.rename', { target: `${rel} → ${newName}`, serverId: req.gameServer!.id })
    res.json({ ok: true, path: renamed.rel })
  })

  // Copy/move a file or directory into another directory. Name collisions
  // auto-suffix " (2)", " (3)", … before the extension (never a 409).
  router.post('/servers/:id/files/copy', access('server.files.write'), (req: ServerRequest, res) => {
    ctx.gateway.assertLocal(req.gameServer!, 'copying files')
    const { path: rel, toDir } = req.body ?? {}
    if (!rel) throw new HttpError(400, 'path required')
    const out = files.copyInto(dirOf(req), String(rel), String(toDir ?? ''))
    ctx.audit.log(req, 'files.copy', { target: `${rel} → ${toDir || '/'}`, serverId: req.gameServer!.id, meta: { as: out.name } })
    res.json({ ok: true, name: out.name })
  })

  router.post('/servers/:id/files/move', access('server.files.write'), (req: ServerRequest, res) => {
    ctx.gateway.assertLocal(req.gameServer!, 'moving files')
    const { path: rel, toDir } = req.body ?? {}
    if (!rel) throw new HttpError(400, 'path required')
    const out = files.moveInto(dirOf(req), String(rel), String(toDir ?? ''))
    ctx.audit.log(req, 'files.move', { target: `${rel} → ${toDir || '/'}`, serverId: req.gameServer!.id, meta: { as: out.name } })
    res.json({ ok: true, name: out.name })
  })

  router.post(
    '/servers/:id/files/delete',
    access('server.files.write'),
    asyncHandler(async (req: ServerRequest, res) => {
      const paths = Array.isArray(req.body?.paths) ? req.body.paths.map(String) : []
      if (paths.length === 0) throw new HttpError(400, 'paths required')
      let count: number
      if (isRemote(req)) {
        count = (await ctx.gateway.proxy(req.gameServer!, (client) => client.deleteFiles(req.gameServer!.id, paths))).deleted
      } else {
        count = files.deleteEntries(dirOf(req), paths)
      }
      ctx.audit.log(req, 'files.delete', { target: paths.slice(0, 5).join(', '), serverId: req.gameServer!.id, meta: { count } })
      res.json({ ok: true, deleted: count })
    }),
  )

  // Zip a selection (all entries of one directory) into archiveName in that
  // same directory. 409 when the archive name is already taken.
  router.post(
    '/servers/:id/files/zip',
    access('server.files.write'),
    asyncHandler(async (req: ServerRequest, res) => {
      ctx.gateway.assertLocal(req.gameServer!, 'compressing files')
      const paths = Array.isArray(req.body?.paths) ? req.body.paths.map(String) : []
      if (paths.length === 0) throw new HttpError(400, 'paths required')
      let archiveName = entryName(req.body?.archiveName, 'archiveName')
      if (!/\.zip$/i.test(archiveName)) archiveName += '.zip'
      const dirs = new Set<string>()
      const names: string[] = []
      for (const p of paths) {
        const clean = p.replace(/\\/g, '/').replace(/\/+$/, '')
        dirs.add(path.posix.dirname(clean))
        names.push(entryName(path.posix.basename(clean), 'path'))
      }
      if (dirs.size !== 1) throw new HttpError(400, 'all paths must be in the same folder')
      const dirRel = [...dirs][0] === '.' ? '' : [...dirs][0]
      let result: { files: number; bytes: number }
      try {
        result = await files.zipSelection(dirOf(req), dirRel, names, archiveName)
      } catch (err) {
        if (err instanceof files.FileConflictError) throw new HttpError(409, err.message)
        throw err
      }
      const dest = dirRel ? `${dirRel}/${archiveName}` : archiveName
      ctx.audit.log(req, 'files.zip', { target: dest, serverId: req.gameServer!.id, meta: { files: result.files } })
      res.json({ ok: true, dest, files: result.files })
    }),
  )

  // Extract a .zip / .tar.gz / .tgz / .tar archive; toDir defaults to the
  // archive's own directory. Zip-slip-proof (every entry through safeJoin),
  // symlink entries skipped, entry-count + uncompressed-size caps enforced.
  router.post(
    '/servers/:id/files/extract',
    access('server.files.write'),
    asyncHandler(async (req: ServerRequest, res) => {
      ctx.gateway.assertLocal(req.gameServer!, 'extracting archives')
      const { path: rel, toDir } = req.body ?? {}
      if (!rel) throw new HttpError(400, 'path required')
      const cleanRel = String(rel).replace(/\\/g, '/')
      const fallbackDir = path.posix.dirname(cleanRel)
      const dest = String(toDir ?? (fallbackDir === '.' ? '' : fallbackDir))
      const result = await files.extractArchive(dirOf(req), cleanRel, dest)
      ctx.audit.log(req, 'files.extract', { target: cleanRel, serverId: req.gameServer!.id, meta: { files: result.files, toDir: dest || '/' } })
      res.json({ ok: true, files: result.files })
    }),
  )

  router.get(
    '/servers/:id/files/download',
    access('server.files.read'),
    asyncHandler(async (req: ServerRequest, res) => {
      const rel = String(req.query.path ?? '')
      if (!rel) throw new HttpError(400, 'path required')
      if (isRemote(req)) {
        // Stream-proxy: relay headers and pipe the node's body through
        // without buffering the file in panel memory.
        const upstream = await ctx.gateway.proxy(req.gameServer!, (client) => client.openDownload(req.gameServer!.id, rel))
        for (const header of ['content-type', 'content-disposition', 'content-length'] as const) {
          const value = upstream.headers.get(header)
          if (value) res.setHeader(header, value)
        }
        if (upstream.body) {
          await pipeline(Readable.fromWeb(upstream.body as import('node:stream/web').ReadableStream), res)
        } else {
          res.end()
        }
        return
      }
      const abs = safeJoin(dirOf(req), rel)
      const stat = fs.statSync(abs)
      if (stat.isDirectory()) {
        // Stream the directory as a zip built into a temp file first (bounded, simple)
        const tmp = path.join(ctx.config.dataDir, 'tmp', `dl-${Date.now()}.zip`)
        await zipDirectory(abs, tmp)
        res.setHeader('content-type', 'application/zip')
        res.setHeader('content-disposition', `attachment; filename="${path.basename(abs) || 'folder'}.zip"`)
        await pipeline(fs.createReadStream(tmp), res)
        fs.rmSync(tmp, { force: true })
        return
      }
      res.setHeader('content-type', 'application/octet-stream')
      res.setHeader('content-disposition', `attachment; filename="${encodeURIComponent(path.basename(abs))}"`)
      res.setHeader('content-length', String(stat.size))
      await pipeline(fs.createReadStream(abs), res)
    }),
  )

  // Raw streaming upload: PUT body → file at ?path=<dir>&name=<filename>
  router.put(
    '/servers/:id/files/upload',
    access('server.files.write'),
    asyncHandler(async (req: ServerRequest, res) => {
      const dirRel = String(req.query.path ?? '')
      const name = path.basename(String(req.query.name ?? ''))
      if (!name) throw new HttpError(400, 'name required')
      const declared = Number(req.headers['content-length'] ?? 0)
      if (declared > MAX_UPLOAD) throw new HttpError(413, 'file too large (max 4 GiB)')
      if (isRemote(req)) {
        // Stream-proxy with the same 4 GiB cap enforced panel-side while the
        // bytes flow through (the agent independently enforces its own).
        let counted = 0
        const counter = new Transform({
          transform(chunk: Buffer, _enc, cb) {
            counted += chunk.length
            if (counted > MAX_UPLOAD) cb(new Error('file too large'))
            else cb(null, chunk)
          },
        })
        const out = await ctx.gateway.proxy(req.gameServer!, (client) =>
          client.uploadStream(
            req.gameServer!.id,
            dirRel,
            name,
            req.pipe(counter),
            typeof req.headers['content-length'] === 'string' ? req.headers['content-length'] : undefined,
          ),
        )
        ctx.audit.log(req, 'files.upload', { target: name, serverId: req.gameServer!.id, meta: { bytes: out.bytes } })
        res.json(out)
        return
      }
      const target = safeJoin(dirOf(req), path.posix.join(dirRel.replace(/\\/g, '/'), name))
      fs.mkdirSync(path.dirname(target), { recursive: true })
      let received = 0
      req.on('data', (chunk: Buffer) => {
        received += chunk.length
        if (received > MAX_UPLOAD) req.destroy(new Error('file too large'))
      })
      await pipeline(req, fs.createWriteStream(target))
      ctx.audit.log(req, 'files.upload', { target: name, serverId: req.gameServer!.id, meta: { bytes: received } })
      res.json({ ok: true, bytes: received })
    }),
  )

  return router
}
