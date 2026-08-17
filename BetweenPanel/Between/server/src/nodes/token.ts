/**
 * Bearer-token auth for node agent mode (BETWEEN_MODE=node).
 *
 * A node agent has no users, sessions or setup wizard — the ONLY credential
 * is the shared token from BETWEEN_NODE_TOKEN, presented by the panel as
 * `Authorization: Bearer <token>` on every request. This applies to the REST
 * API and to the WebSocket handshake alike (the same Authorization header —
 * deliberately NOT a `?token=` query parameter, so the secret never lands in
 * access logs or proxy URLs). A valid token grants admin-equivalent access:
 * the node trusts the panel; per-user permission checks stay panel-side.
 */
import crypto from 'node:crypto'
import type { NextFunction, Response } from 'express'
import type { AuthedRequest } from '../auth/service.ts'
import type { User } from '../types.ts'

/**
 * Fixed id for the synthetic agent principal. Real user ids are always
 * randomUUID(), so this can never collide with a stored account — and the
 * token paths that special-case it are only active when a node token is
 * configured (i.e. never in panel mode).
 */
export const NODE_AGENT_USER_ID = 'node-agent'

/** Synthetic admin-equivalent principal a valid node token authenticates as. */
export const NODE_AGENT_USER: User = {
  id: NODE_AGENT_USER_ID,
  username: 'panel',
  passwordHash: '',
  role: 'admin',
  createdAt: new Date(0).toISOString(),
  prefs: {},
}

/**
 * Constant-time token comparison. Hashing both sides first equalizes the
 * buffer lengths (timingSafeEqual throws on length mismatch, and the length
 * itself must not leak), so neither content nor length of the stored token
 * can be probed through timing.
 */
export function tokenEquals(presented: string, expected: string): boolean {
  if (typeof presented !== 'string' || typeof expected !== 'string' || expected.length === 0) return false
  const a = crypto.createHash('sha256').update(presented).digest()
  const b = crypto.createHash('sha256').update(expected).digest()
  return crypto.timingSafeEqual(a, b)
}

/** Extract the bearer token from an Authorization header value (null = absent/malformed). */
export function bearerToken(header: string | undefined): string | null {
  if (typeof header !== 'string') return null
  if (!header.startsWith('Bearer ')) return null
  const token = header.slice('Bearer '.length).trim()
  return token.length > 0 ? token : null
}

/**
 * Node-mode replacement for makeAuthMiddleware: a matching bearer token
 * authenticates the request as the synthetic admin principal; anything else
 * stays unauthenticated and falls into requireAuth's 401. No sessions, no
 * cookies, no login rate limiting (there is no password to brute-force).
 */
export function makeNodeAuthMiddleware(expectedToken: string) {
  return (req: AuthedRequest, _res: Response, next: NextFunction) => {
    const token = bearerToken(req.headers.authorization)
    if (token && tokenEquals(token, expectedToken)) req.user = NODE_AGENT_USER
    next()
  }
}
