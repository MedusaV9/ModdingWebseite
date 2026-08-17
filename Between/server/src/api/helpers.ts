import type { NextFunction, Request, Response } from 'express'
import type { AuthedRequest, AuthService } from '../auth/service.ts'
import type { ServerManager } from '../servers/manager.ts'
import type { GameServer, ServerPermission, User } from '../types.ts'

export function asyncHandler(fn: (req: AuthedRequest, res: Response, next: NextFunction) => Promise<unknown>) {
  return (req: Request, res: Response, next: NextFunction) => {
    fn(req as AuthedRequest, res, next).catch(next)
  }
}

export function safeUser(user: User) {
  return {
    id: user.id,
    username: user.username,
    role: user.role,
    createdAt: user.createdAt,
    totpEnabled: Boolean(user.totpEnabled),
    prefs: user.prefs ?? {},
    suspended: Boolean(user.suspended),
  }
}

export interface ServerRequest extends AuthedRequest {
  gameServer?: GameServer
}

/**
 * Middleware factory: resolves :id to a server and checks the given
 * permission for the current user (admin and owner always pass). The
 * optional remote lookup resolves panel-side mirrors of servers living on
 * remote nodes — permission checks are identical (mirrors carry ownerId and
 * share their id with panel-side subuser records).
 */
export function makeServerAccess(auth: AuthService, manager: ServerManager, remote?: (id: string) => GameServer | undefined) {
  return (permission: ServerPermission) =>
    (req: ServerRequest, res: Response, next: NextFunction) => {
      if (!req.user) {
        res.status(401).json({ error: 'authentication required' })
        return
      }
      const server = manager.servers.get(req.params.id) ?? remote?.(req.params.id)
      if (!server) {
        res.status(404).json({ error: 'server not found' })
        return
      }
      if (!auth.canAccessServer(req.user, server, permission)) {
        res.status(403).json({ error: `missing permission ${permission}` })
        return
      }
      req.gameServer = server
      next()
    }
}

export class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message)
  }
}

/**
 * Parse a numeric query parameter with clamping. Non-numeric input falls back
 * to the default instead of silently degrading to NaN behavior.
 */
export function intQuery(value: unknown, def: number, min: number, max: number): number {
  const n = Number(value ?? def)
  if (!Number.isFinite(n)) return def
  return Math.min(max, Math.max(min, Math.trunc(n)))
}

export function errorMiddleware(err: Error, _req: Request, res: Response, _next: NextFunction) {
  if (res.headersSent) return
  if (err instanceof HttpError) {
    res.status(err.status).json({ error: err.message })
    return
  }
  const message = err?.message ?? 'internal error'
  // Validation-ish errors surface as 400, unexpected ones as 500
  const status =
    err.name === 'PathTraversalError'
      ? 400
      : /not found/i.test(message)
        ? 404
        : /required|invalid|must be|conflict|already|cannot|before|empty|unsupported|locked|in use|too (large|long|many)|escapes/i.test(message)
          ? 400
          : 500
  if (status === 500) console.error('[api]', err)
  res.status(status).json({ error: message })
}
