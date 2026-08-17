import { Router } from 'express'
import type { AppContext } from '../context.ts'
import { currentSettings } from '../context.ts'
import { PANEL_VERSION } from '../config.ts'
import { requireAuth, SESSION_COOKIE, type AuthedRequest } from '../auth/service.ts'
import { asyncHandler, safeUser, HttpError } from './helpers.ts'
import { verifyPassword, hashPassword } from '../lib/passwords.ts'
import { generateTotpSecret, otpauthUri, verifyTotp } from '../lib/totp.ts'

const COOKIE_OPTS = 'Path=/; HttpOnly; SameSite=Lax'

export function authRouter(ctx: AppContext): Router {
  const router = Router()

  router.get('/meta', (req, res) => {
    const settings = currentSettings(ctx)
    res.json({
      panelName: settings.panelName,
      version: PANEL_VERSION,
      setupRequired: ctx.auth.setupRequired(),
      defaultTheme: settings.defaultTheme ?? 'between-dark',
    })
  })

  router.post(
    '/auth/setup',
    asyncHandler(async (req, res) => {
      if (!ctx.auth.setupRequired()) throw new HttpError(403, 'setup already completed')
      const { username, password, panelName } = req.body ?? {}
      const { user, problems } = ctx.auth.createUser(String(username ?? ''), String(password ?? ''), 'admin')
      if (!user) throw new HttpError(400, problems.join('; '))
      if (panelName && String(panelName).trim()) {
        const settings = currentSettings(ctx)
        ctx.settings.update(settings.id, { panelName: String(panelName).trim().slice(0, 40) })
      }
      const { token } = ctx.auth.createSession(user, req.ip, req.headers['user-agent'])
      res.setHeader('Set-Cookie', `${SESSION_COOKIE}=${token}; ${COOKIE_OPTS}; Max-Age=${ctx.config.sessionTtlDays * 86400}`)
      ctx.audit.log(req, 'auth.setup', { target: user.username })
      res.json({ user: safeUser(user) })
    }),
  )

  router.post(
    '/auth/login',
    asyncHandler(async (req, res) => {
      if (!ctx.auth.rateLimitLogin(req.ip ?? 'unknown')) throw new HttpError(429, 'too many login attempts, wait 5 minutes')
      const { username, password, totp } = req.body ?? {}
      const result = ctx.auth.login(String(username ?? ''), String(password ?? ''), totp ? String(totp) : undefined)
      if (result.totpRequired) {
        res.status(401).json({ error: '2FA code required', totpRequired: true })
        return
      }
      if (!result.user) {
        ctx.audit.log(req, 'auth.login_failed', { target: String(username ?? '') })
        throw new HttpError(401, result.problems.join('; ') || 'invalid credentials')
      }
      const { token } = ctx.auth.createSession(result.user, req.ip, req.headers['user-agent'])
      res.setHeader('Set-Cookie', `${SESSION_COOKIE}=${token}; ${COOKIE_OPTS}; Max-Age=${ctx.config.sessionTtlDays * 86400}`)
      ctx.audit.log({ ...req, user: result.user } as AuthedRequest, 'auth.login')
      res.json({ user: safeUser(result.user) })
    }),
  )

  router.post('/auth/logout', requireAuth, (req: AuthedRequest, res) => {
    if (req.session) ctx.auth.revokeSession(req.session.id)
    res.setHeader('Set-Cookie', `${SESSION_COOKIE}=; ${COOKIE_OPTS}; Max-Age=0`)
    ctx.audit.log(req, 'auth.logout')
    res.json({ ok: true })
  })

  router.get('/auth/me', requireAuth, (req: AuthedRequest, res) => {
    const user = req.user!
    res.json({
      user: safeUser(user),
      // Count only — safeUser must never expose the stored recovery code hashes.
      ...(user.totpEnabled ? { recoveryCodesRemaining: ctx.auth.recoveryCodesRemaining(user) } : {}),
    })
  })

  router.patch('/auth/prefs', requireAuth, (req: AuthedRequest, res) => {
    const { theme, language, accent } = req.body ?? {}
    const prefs = { ...(req.user!.prefs ?? {}) }
    if (theme !== undefined) prefs.theme = String(theme).slice(0, 40)
    if (language !== undefined) prefs.language = ['en', 'de'].includes(String(language)) ? String(language) : 'en'
    if (accent !== undefined) prefs.accent = String(accent).slice(0, 20)
    ctx.auth.users.update(req.user!.id, { prefs })
    res.json({ ok: true, prefs })
  })

  router.post(
    '/auth/password',
    requireAuth,
    asyncHandler(async (req: AuthedRequest, res) => {
      const { current, next } = req.body ?? {}
      if (!verifyPassword(String(current ?? ''), req.user!.passwordHash)) throw new HttpError(400, 'current password is wrong')
      if (typeof next !== 'string' || next.length < 8) throw new HttpError(400, 'new password must be at least 8 characters')
      ctx.auth.users.update(req.user!.id, { passwordHash: hashPassword(next) })
      ctx.auth.revokeAllSessions(req.user!.id, req.session?.id)
      ctx.audit.log(req, 'auth.password_changed')
      res.json({ ok: true })
    }),
  )

  // --- TOTP 2FA ---------------------------------------------------------------
  router.post('/auth/totp/start', requireAuth, (req: AuthedRequest, res) => {
    const secret = generateTotpSecret()
    ctx.auth.users.update(req.user!.id, { totpSecret: secret, totpEnabled: false })
    res.json({ secret, uri: otpauthUri(secret, req.user!.username, currentSettings(ctx).panelName) })
  })

  router.post('/auth/totp/enable', requireAuth, (req: AuthedRequest, res) => {
    const user = ctx.auth.users.get(req.user!.id)!
    if (!user.totpSecret) throw new HttpError(400, 'start 2FA setup first')
    if (!verifyTotp(user.totpSecret, String(req.body?.code ?? ''))) throw new HttpError(400, 'invalid 2FA code')
    ctx.auth.users.update(user.id, { totpEnabled: true })
    const recoveryCodes = ctx.auth.generateRecoveryCodes(user.id)
    ctx.audit.log(req, 'auth.totp_enabled')
    res.json({ ok: true, recoveryCodes })
  })

  router.post('/auth/totp/disable', requireAuth, (req: AuthedRequest, res) => {
    const user = ctx.auth.users.get(req.user!.id)!
    if (user.totpEnabled && user.totpSecret && !verifyTotp(user.totpSecret, String(req.body?.code ?? '')))
      throw new HttpError(400, 'invalid 2FA code')
    ctx.auth.users.update(user.id, { totpEnabled: false, totpSecret: null, recoveryCodes: [] })
    ctx.audit.log(req, 'auth.totp_disabled')
    res.json({ ok: true })
  })

  router.post('/auth/totp/recovery-codes', requireAuth, (req: AuthedRequest, res) => {
    const user = ctx.auth.users.get(req.user!.id)!
    if (!user.totpEnabled || !user.totpSecret) throw new HttpError(403, '2FA is not enabled')
    if (!verifyTotp(user.totpSecret, String(req.body?.code ?? ''))) throw new HttpError(400, 'invalid 2FA code')
    const recoveryCodes = ctx.auth.generateRecoveryCodes(user.id)
    ctx.audit.log(req, 'auth.recovery_codes_regenerated')
    res.json({ recoveryCodes })
  })

  // --- Sessions ----------------------------------------------------------------
  router.get('/auth/sessions', requireAuth, (req: AuthedRequest, res) => {
    const sessions = ctx.auth.sessions
      .filter((s) => s.userId === req.user!.id)
      .map((s) => ({
        id: s.id,
        createdAt: s.createdAt,
        expiresAt: s.expiresAt,
        ip: s.ip,
        userAgent: s.userAgent,
        current: s.id === req.session?.id,
      }))
    res.json({ sessions })
  })

  router.delete('/auth/sessions/:sessionId', requireAuth, (req: AuthedRequest, res) => {
    const session = ctx.auth.sessions.get(req.params.sessionId)
    if (!session || session.userId !== req.user!.id) throw new HttpError(404, 'session not found')
    ctx.auth.revokeSession(session.id)
    res.json({ ok: true })
  })

  return router
}
