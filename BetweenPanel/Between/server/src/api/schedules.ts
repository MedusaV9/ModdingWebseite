import { Router } from 'express'
import type { AppContext } from '../context.ts'
import { requireAuth } from '../auth/service.ts'
import { asyncHandler, HttpError, makeServerAccess, type ServerRequest } from './helpers.ts'
import { nextRun, parseCron } from '../lib/cron.ts'
import type { ServerPermission } from '../types.ts'

/** Permission a schedule task type effectively wields when it runs. */
const TASK_PERMISSION: Record<string, ServerPermission> = {
  power: 'server.power',
  command: 'server.command',
  backup: 'server.backups',
}

export function schedulesRouter(ctx: AppContext): Router {
  const router = Router()
  const access = makeServerAccess(ctx.auth, ctx.manager, (id) => ctx.nodes.mirror(id))
  router.use(requireAuth)

  // `server.schedules` alone must not become a backdoor to power/command/backup:
  // a task may only be created or run by someone who also holds the permission
  // that task exercises. Owners/admins pass every check.
  const ensureTaskPermissions = (req: ServerRequest, tasks: unknown): void => {
    if (!Array.isArray(tasks)) return
    for (const task of tasks) {
      const type = (task as { type?: string } | null)?.type
      const perm = type ? TASK_PERMISSION[type] : undefined
      if (perm && !ctx.auth.canAccessServer(req.user!, req.gameServer!, perm))
        throw new HttpError(403, `schedule task "${type}" requires the ${perm} permission`)
    }
  }

  const serialize = (id: string) => {
    const schedule = ctx.schedules.schedules.get(id)!
    return { ...schedule, nextRunAt: ctx.schedules.nextRunOf(id) }
  }

  router.get('/servers/:id/schedules', access('server.schedules'), (req: ServerRequest, res) => {
    const schedules = ctx.schedules.schedules
      .filter((s) => s.serverId === req.gameServer!.id)
      .map((s) => serialize(s.id))
    res.json({ schedules })
  })

  router.post('/servers/:id/schedules', access('server.schedules'), (req: ServerRequest, res) => {
    // Schedules execute against the local manager/backup service — remote
    // servers get schedules in a follow-up (either agent-side or via gateway).
    ctx.gateway.assertLocal(req.gameServer!, 'creating schedules')
    const { name, cron, trigger, tasks, enabled, onlyIfRunning } = req.body ?? {}
    ensureTaskPermissions(req, tasks)
    const { schedule, problems } = ctx.schedules.create({
      serverId: req.gameServer!.id,
      name: String(name ?? ''),
      // `trigger` (cron/event union) wins; a plain `cron` string stays valid.
      cron: cron === undefined ? undefined : String(cron),
      trigger,
      tasks,
      enabled,
      onlyIfRunning,
    })
    if (!schedule) throw new HttpError(400, problems.join('; '))
    ctx.audit.log(req, 'schedule.created', { target: schedule.name, serverId: req.gameServer!.id })
    res.status(201).json({ schedule: serialize(schedule.id) })
  })

  router.post('/schedules/preview', (req, res) => {
    try {
      const spec = parseCron(String(req.body?.cron ?? ''))
      const runs: number[] = []
      let from = new Date()
      for (let i = 0; i < 5; i++) {
        const next = nextRun(spec, from)
        if (!next) break
        runs.push(next.getTime())
        from = next
      }
      res.json({ valid: true, nextRuns: runs })
    } catch (err) {
      res.json({ valid: false, error: (err as Error).message })
    }
  })

  router.patch('/servers/:id/schedules/:sid', access('server.schedules'), (req: ServerRequest, res) => {
    const existing = ctx.schedules.schedules.get(req.params.sid)
    if (!existing || existing.serverId !== req.gameServer!.id) throw new HttpError(404, 'schedule not found')
    if (req.body?.tasks !== undefined) ensureTaskPermissions(req, req.body.tasks)
    const { schedule, problems } = ctx.schedules.update(req.params.sid, req.body ?? {})
    if (!schedule) throw new HttpError(400, problems.join('; '))
    res.json({ schedule: serialize(schedule.id) })
  })

  router.delete('/servers/:id/schedules/:sid', access('server.schedules'), (req: ServerRequest, res) => {
    const existing = ctx.schedules.schedules.get(req.params.sid)
    if (!existing || existing.serverId !== req.gameServer!.id) throw new HttpError(404, 'schedule not found')
    ctx.schedules.remove(req.params.sid)
    ctx.audit.log(req, 'schedule.deleted', { target: existing.name, serverId: req.gameServer!.id })
    res.json({ ok: true })
  })

  router.post(
    '/servers/:id/schedules/:sid/run',
    access('server.schedules'),
    asyncHandler(async (req: ServerRequest, res) => {
      const existing = ctx.schedules.schedules.get(req.params.sid)
      if (!existing || existing.serverId !== req.gameServer!.id) throw new HttpError(404, 'schedule not found')
      // Triggering an existing schedule runs its tasks as the caller — re-check
      // so a schedules-only subuser can't fire a power/command task via /run.
      ensureTaskPermissions(req, existing.tasks)
      void ctx.schedules.execute(existing.id, 'manual')
      res.json({ ok: true })
    }),
  )

  return router
}
