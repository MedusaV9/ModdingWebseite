import { Router } from 'express'
import type { AppContext } from '../context.ts'
import { requireAdmin, type AuthedRequest } from '../auth/service.ts'
import { safeUser, HttpError } from './helpers.ts'
import { hashPassword } from '../lib/passwords.ts'

export function usersRouter(ctx: AppContext): Router {
  const router = Router()
  // Scope to /users only — an unscoped router.use() would intercept every
  // /api/* request that flows through this router and 403 non-admins.
  router.use('/users', requireAdmin)

  router.get('/users', (_req, res) => {
    res.json({ users: ctx.auth.users.all().map(safeUser) })
  })

  router.post('/users', (req: AuthedRequest, res) => {
    const { username, password, role } = req.body ?? {}
    const { user, problems } = ctx.auth.createUser(
      String(username ?? ''),
      String(password ?? ''),
      role === 'admin' ? 'admin' : 'user',
    )
    if (!user) throw new HttpError(400, problems.join('; '))
    ctx.audit.log(req, 'user.created', { target: user.username })
    res.status(201).json({ user: safeUser(user) })
  })

  router.patch('/users/:userId', (req: AuthedRequest, res) => {
    const user = ctx.auth.users.get(req.params.userId)
    if (!user) throw new HttpError(404, 'user not found')
    const { role, suspended, password } = req.body ?? {}
    if (user.id === req.user!.id && (role === 'user' || suspended === true))
      throw new HttpError(400, 'you cannot demote or suspend yourself')
    const patch: Partial<typeof user> = {}
    if (role !== undefined) {
      if (role !== 'admin' && role !== 'user') throw new HttpError(400, 'invalid role')
      patch.role = role
    }
    if (suspended !== undefined) patch.suspended = Boolean(suspended)
    if (password !== undefined) {
      if (typeof password !== 'string' || password.length < 8) throw new HttpError(400, 'password must be at least 8 characters')
      patch.passwordHash = hashPassword(password)
      ctx.auth.revokeAllSessions(user.id)
    }
    const updated = ctx.auth.users.update(user.id, patch)!
    ctx.audit.log(req, 'user.updated', { target: user.username, meta: { role, suspended, passwordReset: password !== undefined } })
    res.json({ user: safeUser(updated) })
  })

  router.delete('/users/:userId', (req: AuthedRequest, res) => {
    const user = ctx.auth.users.get(req.params.userId)
    if (!user) throw new HttpError(404, 'user not found')
    if (user.id === req.user!.id) throw new HttpError(400, 'you cannot delete yourself')
    const ownedServers = ctx.manager.servers.filter((s) => s.ownerId === user.id)
    if (ownedServers.length > 0)
      throw new HttpError(400, `user still owns ${ownedServers.length} server(s) — delete or transfer them first`)
    ctx.auth.users.remove(user.id)
    ctx.auth.revokeAllSessions(user.id)
    ctx.auth.subusers.removeWhere((s) => s.userId === user.id)
    ctx.auth.apiKeys.removeWhere((k) => k.userId === user.id)
    ctx.audit.log(req, 'user.deleted', { target: user.username })
    res.json({ ok: true })
  })

  return router
}
