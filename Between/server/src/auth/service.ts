import crypto from 'node:crypto'
import type { Request, Response, NextFunction } from 'express'
import type { Store, Collection } from '../lib/jsonstore.ts'
import type { ApiKey, GameServer, ServerPermission, Session, Subuser, User } from '../types.ts'
import { SERVER_PERMISSIONS } from '../types.ts'
import { hashPassword, verifyPassword, randomToken, sha256 } from '../lib/passwords.ts'
import { verifyTotp } from '../lib/totp.ts'
import { nowIso } from '../lib/util.ts'

export const SESSION_COOKIE = 'between_session'
const USERNAME_RE = /^[a-zA-Z0-9_.-]{3,32}$/
const MAX_LOGIN_ATTEMPT_IPS = 10_000

const RECOVERY_CODE_COUNT = 10
/** Characters per code, displayed grouped as xxxx-xxxx-xxxx. */
const RECOVERY_CODE_LENGTH = 12
/** Lowercase base32-ish alphabet without the ambiguous chars 0/o and 1/l. */
const RECOVERY_ALPHABET = 'abcdefghijkmnpqrstuvwxyz23456789'

/** Canonical form used for hashing and comparison: lowercase, no dashes/spaces. */
function normalizeRecoveryCode(input: string): string {
  return input.trim().toLowerCase().replace(/[\s-]/g, '')
}

export interface AuthedRequest extends Request {
  user?: User
  session?: Session
  apiKey?: ApiKey
}

export function parseCookies(header: string | undefined): Record<string, string> {
  const out: Record<string, string> = {}
  if (!header) return out
  for (const part of header.split(';')) {
    const eq = part.indexOf('=')
    if (eq < 0) continue
    const raw = part.slice(eq + 1).trim()
    let value = raw
    try {
      value = decodeURIComponent(raw)
    } catch {
      // Malformed percent-escapes (e.g. "%zz") must never throw — fall back
      // to the raw value; the session lookup will simply not match.
    }
    out[part.slice(0, eq).trim()] = value
  }
  return out
}

export class AuthService {
  readonly users: Collection<User>
  readonly sessions: Collection<Session>
  readonly apiKeys: Collection<ApiKey>
  readonly subusers: Collection<Subuser>
  private loginAttempts = new Map<string, { count: number; resetAt: number }>()

  constructor(store: Store, private sessionTtlDays: number) {
    this.users = store.collection<User>('users')
    this.sessions = store.collection<Session>('sessions')
    this.apiKeys = store.collection<ApiKey>('apikeys')
    this.subusers = store.collection<Subuser>('subusers')
  }

  setupRequired(): boolean {
    return this.users.size() === 0
  }

  createUser(username: string, password: string, role: User['role']): { user?: User; problems: string[] } {
    const problems: string[] = []
    if (!USERNAME_RE.test(username)) problems.push('username must be 3-32 chars (letters, digits, _.-)')
    if (typeof password !== 'string' || password.length < 8) problems.push('password must be at least 8 characters')
    if (this.users.find((u) => u.username.toLowerCase() === username.toLowerCase())) problems.push('username already taken')
    if (problems.length > 0) return { problems }
    const user = this.users.insert({
      username,
      passwordHash: hashPassword(password),
      role,
      createdAt: nowIso(),
      totpSecret: null,
      totpEnabled: false,
      prefs: {},
    })
    return { user, problems: [] }
  }

  rateLimitLogin(ip: string): boolean {
    const now = Date.now()
    const entry = this.loginAttempts.get(ip)
    if (!entry || now > entry.resetAt) {
      if (!entry && this.loginAttempts.size >= MAX_LOGIN_ATTEMPT_IPS) {
        // A distributed spray must not grow this process-lifetime map without
        // bound. Reclaim expired windows first; if every slot is still active,
        // fail closed for a previously unseen address until a window expires.
        for (const [knownIp, attempt] of this.loginAttempts) {
          if (now > attempt.resetAt) this.loginAttempts.delete(knownIp)
        }
        if (this.loginAttempts.size >= MAX_LOGIN_ATTEMPT_IPS) return false
      }
      this.loginAttempts.set(ip, { count: 1, resetAt: now + 5 * 60 * 1000 })
      return true
    }
    entry.count++
    return entry.count <= 10
  }

  login(
    username: string,
    password: string,
    totpCode?: string,
  ): { user?: User; problems: string[]; totpRequired?: boolean } {
    const user = this.users.find((u) => u.username.toLowerCase() === String(username).toLowerCase())
    if (!user || !verifyPassword(String(password), user.passwordHash)) return { problems: ['invalid credentials'] }
    if (user.suspended) return { problems: ['account is suspended'] }
    if (user.totpEnabled && user.totpSecret) {
      if (!totpCode) return { problems: [], totpRequired: true }
      const code = String(totpCode)
      if (!verifyTotp(user.totpSecret, code) && !this.consumeRecoveryCode(user, code))
        return { problems: ['invalid 2FA code'] }
    }
    return { user, problems: [] }
  }

  // --- 2FA recovery codes ------------------------------------------------------
  /**
   * Replaces any existing recovery codes with a fresh set. Only sha256 hashes
   * of the normalized (dashless) codes are persisted — the returned plaintext
   * codes are shown to the user exactly once.
   */
  generateRecoveryCodes(userId: string): string[] {
    const codes: string[] = []
    for (let i = 0; i < RECOVERY_CODE_COUNT; i++) {
      // 32-char alphabet: `byte & 31` takes 5 bits per byte without modulo bias.
      const raw = [...crypto.randomBytes(RECOVERY_CODE_LENGTH)].map((b) => RECOVERY_ALPHABET[b & 31]).join('')
      codes.push(`${raw.slice(0, 4)}-${raw.slice(4, 8)}-${raw.slice(8, 12)}`)
    }
    this.users.update(userId, { recoveryCodes: codes.map((c) => sha256(normalizeRecoveryCode(c))) })
    return codes
  }

  recoveryCodesRemaining(user: User): number {
    return user.recoveryCodes?.length ?? 0
  }

  /**
   * Redeem a one-time recovery code in place of a TOTP code. Matching is
   * case-insensitive and tolerates missing/extra dashes or whitespace; a match
   * removes the stored hash so every code works exactly once. Only reachable
   * from the 2FA branch of login() — codes are inert while 2FA is disabled.
   */
  private consumeRecoveryCode(user: User, input: string): boolean {
    const hashes = user.recoveryCodes
    if (!hashes || hashes.length === 0) return false
    const normalized = normalizeRecoveryCode(input)
    if (normalized.length !== RECOVERY_CODE_LENGTH) return false
    const hash = sha256(normalized)
    if (!hashes.includes(hash)) return false
    this.users.update(user.id, { recoveryCodes: hashes.filter((h) => h !== hash) })
    return true
  }

  createSession(user: User, ip?: string, userAgent?: string): { session: Session; token: string } {
    const token = randomToken(32)
    const session = this.sessions.insert({
      token: sha256(token),
      userId: user.id,
      createdAt: nowIso(),
      expiresAt: new Date(Date.now() + this.sessionTtlDays * 24 * 3600 * 1000).toISOString(),
      ip,
      userAgent: userAgent?.slice(0, 200),
    })
    this.pruneSessions()
    return { session, token }
  }

  resolveSession(token: string): { session: Session; user: User } | null {
    const hashed = sha256(token)
    const session = this.sessions.find((s) => s.token === hashed)
    if (!session) return null
    if (!this.sessionUser(session.id, session.userId)) return null
    const user = this.users.get(session.userId)
    if (!user) return null
    return { session, user }
  }

  /**
   * Revalidate a long-lived connection against the session collection.
   * WebSockets cannot rely on the user snapshot captured at handshake time:
   * logout, session revocation and expiry must end an already-open stream.
   */
  sessionUser(sessionId: string, expectedUserId?: string): User | null {
    const session = this.sessions.get(sessionId)
    if (!session || (expectedUserId !== undefined && session.userId !== expectedUserId)) return null
    if (new Date(session.expiresAt).getTime() < Date.now()) {
      this.sessions.remove(session.id)
      return null
    }
    const user = this.users.get(session.userId)
    return user && !user.suspended ? user : null
  }

  revokeSession(id: string) {
    this.sessions.remove(id)
  }

  revokeAllSessions(userId: string, exceptSessionId?: string) {
    this.sessions.removeWhere((s) => s.userId === userId && s.id !== exceptSessionId)
  }

  private pruneSessions() {
    const now = Date.now()
    this.sessions.removeWhere((s) => new Date(s.expiresAt).getTime() < now)
  }

  // --- API keys --------------------------------------------------------------
  createApiKey(userId: string, name: string, scopes: string[]): { apiKey: ApiKey; secret: string } {
    const secret = `btw_${randomToken(24)}`
    const apiKey = this.apiKeys.insert({
      userId,
      name: String(name ?? 'api key').slice(0, 60),
      keyHash: sha256(secret),
      prefix: secret.slice(0, 10),
      scopes: scopes.filter((s) => typeof s === 'string').slice(0, 20),
      createdAt: nowIso(),
      lastUsedAt: null,
    })
    return { apiKey, secret }
  }

  resolveApiKey(secret: string): { apiKey: ApiKey; user: User } | null {
    const hashed = sha256(secret)
    const apiKey = this.apiKeys.find((k) => k.keyHash === hashed)
    if (!apiKey) return null
    const user = this.users.get(apiKey.userId)
    if (!user || user.suspended) return null
    this.apiKeys.update(apiKey.id, { lastUsedAt: nowIso() })
    return { apiKey, user }
  }

  // --- Permissions -------------------------------------------------------------
  canAccessServer(user: User, server: GameServer, permission: ServerPermission): boolean {
    if (user.role === 'admin') return true
    if (server.ownerId === user.id) return true
    const sub = this.subusers.find((s) => s.serverId === server.id && s.userId === user.id)
    if (!sub) return false
    if (permission === 'server.view') return true
    return sub.permissions.includes(permission)
  }

  /**
   * Effective permission list for a user on a server, so the UI can hide
   * actions the user cannot perform. Admins/owners additionally get the
   * pseudo-permission 'owner' (danger zone: delete, suspend, …).
   */
  effectivePermissions(user: User, server: GameServer): string[] {
    if (user.role === 'admin' || server.ownerId === user.id) return ['owner', ...SERVER_PERMISSIONS]
    const sub = this.subusers.find((s) => s.serverId === server.id && s.userId === user.id)
    if (!sub) return []
    return ['server.view', ...sub.permissions.filter((p) => p !== 'server.view')]
  }

  visibleServers(user: User, servers: GameServer[]): GameServer[] {
    if (user.role === 'admin') return servers
    const subIds = new Set(this.subusers.filter((s) => s.userId === user.id).map((s) => s.serverId))
    return servers.filter((s) => s.ownerId === user.id || subIds.has(s.id))
  }
}

// -----------------------------------------------------------------------------
// Express middleware
// -----------------------------------------------------------------------------
/** A key is read-only if it carries the 'read' scope and no write/admin scope. */
export function isReadOnlyKey(scopes: string[] | undefined): boolean {
  if (!scopes || scopes.length === 0) return false
  return scopes.includes('read') && !scopes.includes('write') && !scopes.includes('admin') && !scopes.includes('*')
}

const SAFE_METHODS = new Set(['GET', 'HEAD', 'OPTIONS'])

export function makeAuthMiddleware(auth: AuthService) {
  return (req: AuthedRequest, res: Response, next: NextFunction) => {
    const bearer = req.headers.authorization
    if (bearer?.startsWith('Bearer btw_')) {
      const resolved = auth.resolveApiKey(bearer.slice('Bearer '.length).trim())
      if (resolved) {
        // Enforce the key's scope: a read-only key may only issue safe methods.
        // Scope-less keys keep full access (they act as the owning user).
        if (isReadOnlyKey(resolved.apiKey.scopes) && !SAFE_METHODS.has(req.method)) {
          res.status(403).json({ error: 'this API key is read-only' })
          return
        }
        req.user = resolved.user
        req.apiKey = resolved.apiKey
      }
      return next()
    }
    const cookies = parseCookies(req.headers.cookie)
    const token = cookies[SESSION_COOKIE]
    if (token) {
      const resolved = auth.resolveSession(token)
      if (resolved) {
        req.user = resolved.user
        req.session = resolved.session
      }
    }
    next()
  }
}

export function requireAuth(req: AuthedRequest, res: Response, next: NextFunction) {
  if (!req.user) {
    res.status(401).json({ error: 'authentication required' })
    return
  }
  next()
}

export function requireAdmin(req: AuthedRequest, res: Response, next: NextFunction) {
  if (!req.user) {
    res.status(401).json({ error: 'authentication required' })
    return
  }
  if (req.user.role !== 'admin') {
    res.status(403).json({ error: 'admin access required' })
    return
  }
  next()
}
