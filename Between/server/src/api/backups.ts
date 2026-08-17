import { Router } from 'express'
import fs from 'node:fs'
import { pipeline } from 'node:stream/promises'
import type { AppContext } from '../context.ts'
import { requireAuth } from '../auth/service.ts'
import { asyncHandler, HttpError, makeServerAccess, type ServerRequest } from './helpers.ts'

export function backupsRouter(ctx: AppContext): Router {
  const router = Router()
  const access = makeServerAccess(ctx.auth, ctx.manager, (id) => ctx.nodes.mirror(id))
  router.use(requireAuth)

  const isRemote = (req: ServerRequest) => ctx.gateway.isRemote(req.gameServer!)

  router.get(
    '/servers/:id/backups',
    access('server.backups'),
    asyncHandler(async (req: ServerRequest, res) => {
      if (isRemote(req)) {
        // Backup archives live on the node alongside the server files.
        res.json(await ctx.gateway.proxy(req.gameServer!, (client) => client.listBackups(req.gameServer!.id)))
        return
      }
      res.json({
        backups: ctx.backups.list(req.gameServer!.id),
        busy: ctx.backups.isBusy(req.gameServer!.id),
        // Effective "keep last N unlocked" policy (0 = unlimited) — drives the UI hint.
        retention: ctx.backups.effectiveRetention(req.gameServer!.id),
      })
    }),
  )

  router.post(
    '/servers/:id/backups',
    access('server.backups'),
    asyncHandler(async (req: ServerRequest, res) => {
      const note = String(req.body?.note ?? '')
      const backup = isRemote(req)
        ? (await ctx.gateway.proxy(req.gameServer!, (client) => client.createBackup(req.gameServer!.id, note))).backup
        : await ctx.backups.create(req.gameServer!.id, note)
      ctx.audit.log(req, 'backup.created', { target: backup.fileName, serverId: req.gameServer!.id })
      ctx.notifier.notify('backup', 'Backup created', `**${req.gameServer!.name}** — ${backup.fileName}`, {
        server: { id: req.gameServer!.id, name: req.gameServer!.name, blueprintId: req.gameServer!.blueprintId },
        data: { fileName: backup.fileName },
      })
      res.status(201).json({ backup })
    }),
  )

  router.post(
    '/servers/:id/backups/:bid/restore',
    access('server.backups'),
    asyncHandler(async (req: ServerRequest, res) => {
      const opts = { wipe: Boolean(req.body?.wipe), safetyBackup: req.body?.safetyBackup !== false }
      if (isRemote(req)) {
        await ctx.gateway.proxy(req.gameServer!, (client) => client.restoreBackup(req.gameServer!.id, req.params.bid, opts))
      } else {
        await ctx.backups.restore(req.gameServer!.id, req.params.bid, opts)
      }
      ctx.audit.log(req, 'backup.restored', { serverId: req.gameServer!.id, meta: { backupId: req.params.bid } })
      res.json({ ok: true })
    }),
  )

  router.post('/servers/:id/backups/:bid/lock', access('server.backups'), (req: ServerRequest, res) => {
    ctx.gateway.assertLocal(req.gameServer!, 'locking backups')
    const backup = ctx.backups.setLocked(req.gameServer!.id, req.params.bid, Boolean(req.body?.locked))
    res.json({ backup })
  })

  router.delete(
    '/servers/:id/backups/:bid',
    access('server.backups'),
    asyncHandler(async (req: ServerRequest, res) => {
      if (isRemote(req)) {
        await ctx.gateway.proxy(req.gameServer!, (client) => client.deleteBackup(req.gameServer!.id, req.params.bid))
      } else {
        ctx.backups.remove(req.gameServer!.id, req.params.bid)
      }
      ctx.audit.log(req, 'backup.deleted', { serverId: req.gameServer!.id, meta: { backupId: req.params.bid } })
      res.json({ ok: true })
    }),
  )

  router.get(
    '/servers/:id/backups/:bid/download',
    access('server.backups'),
    asyncHandler(async (req: ServerRequest, res) => {
      ctx.gateway.assertLocal(req.gameServer!, 'downloading backups')
      const backup = ctx.backups.backups.get(req.params.bid)
      if (!backup || backup.serverId !== req.gameServer!.id) throw new HttpError(404, 'backup not found')
      const file = ctx.backups.fileOf(backup)
      if (!fs.existsSync(file)) throw new HttpError(404, 'backup archive missing on disk')
      res.setHeader('content-type', 'application/zip')
      res.setHeader('content-disposition', `attachment; filename="${backup.fileName}"`)
      res.setHeader('content-length', String(fs.statSync(file).size))
      await pipeline(fs.createReadStream(file), res)
    }),
  )

  return router
}
