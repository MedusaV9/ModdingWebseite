/**
 * Authenticated Steam login for SteamCMD (panel-level account, one per
 * machine).
 *
 * Security model:
 *   - Only the account NAME is persisted (panel settings `steamUser`). The
 *     password (and guard code) live for the duration of one login request:
 *     they are written to the steamcmd child's stdin when it prompts and are
 *     never put on a command line (process lists leak argv), never persisted
 *     and never logged — all captured output is passed through scrubSecrets
 *     before it leaves this module.
 *   - After one successful interactive login SteamCMD caches the session in
 *     its own dir (`config/config.vdf` + `ssfn*` sentry files under the
 *     panel's data/steamcmd). Subsequent `+login <user>` runs need no
 *     password — installs simply pass the user name (see installApp).
 *   - Logout deletes those cached-session files instead of running
 *     `+logout`: file removal is deterministic, works offline/with a broken
 *     steamcmd binary, and is the mechanism Valve's own docs point at for
 *     clearing cached credentials. (`+logout` additionally needs a full
 *     steamcmd boot and its behavior differs across builds.)
 *   - Session state is per MACHINE (each steamcmd home has its own cache):
 *     remote nodes are not covered by a panel-side login in v1.
 *
 * Status probe: `loggedIn` is determined by actually running
 * `steamcmd +login <user> +quit` without a password and watching whether it
 * succeeds or asks for one. That costs one steamcmd boot (a few seconds for
 * the real binary), so results are cached for STATUS_TTL_MS and refreshed
 * on demand (`?refresh=true`) or after login/logout.
 */
import fs from 'node:fs'
import path from 'node:path'
import { spawn } from 'node:child_process'
import type { Collection } from '../lib/jsonstore.ts'
import type { PanelSettings } from '../types.ts'
import type { SteamCmdManager } from './steamcmd.ts'
import { classifyLine, detectPrompt, isGuardFailure, scrubSecrets, stripAnsi } from './loginflow.ts'

const STATUS_TTL_MS = 5 * 60 * 1000
const LOGIN_TIMEOUT_MS = 120_000
const MAX_LOG_LINES = 80
const USERNAME_RE = /^[A-Za-z0-9_.\-@]{2,64}$/

export interface SteamLoginResult {
  ok: boolean
  /** Password was accepted but a Steam Guard code is required — retry with one. */
  needsGuard?: boolean
  error?: string
  /** Scrubbed steamcmd output for the UI (secrets masked before capture). */
  log: string[]
}

export interface SteamLoginStatus {
  user: string | null
  loggedIn: boolean
}

export class SteamLoginService {
  private cache: { loggedIn: boolean; ts: number } | null = null
  /** Serializes login/probe runs — two steamcmd processes sharing one home dir corrupt each other. */
  private chain: Promise<unknown> = Promise.resolve()

  constructor(
    private steam: SteamCmdManager,
    private settings: Collection<PanelSettings>,
  ) {}

  /** The configured panel Steam account name (null = feature unused). */
  get user(): string | null {
    return this.settings.all()[0]?.steamUser ?? null
  }

  private setUser(user: string | null): void {
    const doc = this.settings.all()[0]
    if (doc) this.settings.update(doc.id, { steamUser: user })
  }

  /** Queue an exclusive slot behind any in-flight login/probe. */
  private exclusive<T>(fn: () => Promise<T>): Promise<T> {
    const next = this.chain.then(fn, fn)
    this.chain = next.catch(() => undefined)
    return next
  }

  /**
   * Interactive login: `+login <user>` with the password/guard code answered
   * on stdin when (and only when) steamcmd asks for them.
   */
  login(username: string, password: string, guardCode?: string): Promise<SteamLoginResult> {
    const user = String(username ?? '').trim()
    if (!USERNAME_RE.test(user)) {
      return Promise.resolve({ ok: false, error: 'invalid Steam username', log: [] })
    }
    if (typeof password !== 'string' || password.length < 1 || password.length > 256) {
      return Promise.resolve({ ok: false, error: 'password required', log: [] })
    }
    const guard = guardCode === undefined || guardCode === null ? undefined : String(guardCode).trim()
    if (!this.steam.isInstalled()) {
      return Promise.resolve({ ok: false, error: 'SteamCMD is not installed yet — install it in the panel settings first', log: [] })
    }
    return this.exclusive(async () => {
      const result = await this.runInteractive(user, password, guard)
      if (result.ok) {
        this.setUser(user)
        this.cache = { loggedIn: true, ts: Date.now() }
      }
      return result
    })
  }

  /** Cached-with-TTL login status; `refresh` forces a new probe. */
  status(refresh = false): Promise<SteamLoginStatus> {
    const user = this.user
    if (!user) return Promise.resolve({ user: null, loggedIn: false })
    if (!refresh && this.cache && Date.now() - this.cache.ts < STATUS_TTL_MS) {
      return Promise.resolve({ user, loggedIn: this.cache.loggedIn })
    }
    if (!this.steam.isInstalled()) return Promise.resolve({ user, loggedIn: false })
    return this.exclusive(async () => {
      // Re-check inside the slot: a login that just finished already knows.
      if (!refresh && this.cache && Date.now() - this.cache.ts < STATUS_TTL_MS) {
        return { user, loggedIn: this.cache.loggedIn }
      }
      const probe = await this.runInteractive(user, null, undefined)
      this.cache = { loggedIn: probe.ok, ts: Date.now() }
      return { user, loggedIn: probe.ok }
    })
  }

  /** For the install pipeline: current user + cheap (cached) session check. */
  installAuth(): { user: string | null; isLoggedIn: () => Promise<boolean> } {
    return {
      user: this.user,
      isLoggedIn: async () => (await this.status()).loggedIn,
    }
  }

  /**
   * Clear the cached SteamCMD session: delete `config/config.vdf` (cached
   * credentials) and `ssfn*` sentry files from the steamcmd dir, then forget
   * the account name. See the module header for why files beat `+logout`.
   */
  logout(): Promise<void> {
    return this.exclusive(async () => {
      const dir = this.steam.dir
      fs.rmSync(path.join(dir, 'config', 'config.vdf'), { force: true })
      let entries: string[] = []
      try {
        entries = fs.readdirSync(dir)
      } catch { /* steamcmd dir may not exist yet */ }
      for (const entry of entries) {
        if (entry.toLowerCase().startsWith('ssfn')) fs.rmSync(path.join(dir, entry), { force: true })
      }
      this.setUser(null)
      this.cache = { loggedIn: false, ts: Date.now() }
    })
  }

  /**
   * Drive one `steamcmd +login <user> +quit` run. `password === null` is
   * probe mode: any interactive prompt means "no cached session" and ends
   * the run. Output is scrubbed before capture; each secret is written to
   * stdin at most once (a re-prompt means it was wrong).
   */
  private runInteractive(user: string, password: string | null, guardCode: string | undefined): Promise<SteamLoginResult> {
    return new Promise((resolve) => {
      // First login can precede the first install — the session/home dir must exist.
      fs.mkdirSync(this.steam.dir, { recursive: true })
      const child = spawn(this.steam.executable, ['+login', user, '+quit'], {
        cwd: this.steam.dir,
        stdio: ['pipe', 'pipe', 'pipe'],
        env: { ...process.env, HOME: process.env.HOME ?? this.steam.dir },
      })
      const secrets = [password, guardCode]
      const log: string[] = []
      let tail = ''
      let sentPassword = false
      let sentGuard = false
      let settled = false

      const finish = (result: Omit<SteamLoginResult, 'log'>, kill = false) => {
        if (settled) return
        settled = true
        clearTimeout(timer)
        if (kill) child.kill('SIGKILL')
        resolve({ ...result, log: log.slice(-MAX_LOG_LINES) })
      }
      const timer = setTimeout(() => finish({ ok: false, error: 'steamcmd login timed out' }, true), LOGIN_TIMEOUT_MS)
      timer.unref?.()

      // Exit-race EPIPE: steamcmd may die between prompt detection and our answer.
      child.stdin.on('error', () => {})

      const answer = (value: string) => {
        try {
          child.stdin.write(value + '\n')
        } catch { /* EPIPE handled above */ }
      }

      const feed = (chunk: Buffer) => {
        tail += scrubSecrets(chunk.toString('utf8'), secrets)
        const lines = tail.split(/\r?\n|\r/)
        tail = lines.pop() ?? ''
        for (const rawLine of lines) {
          const line = stripAnsi(rawLine)
          if (!line.trim()) continue
          if (log.length < MAX_LOG_LINES * 2) log.push(line)
          const outcome = classifyLine(line)
          if (outcome?.type === 'success') return finish({ ok: true })
          if (outcome?.type === 'failure') {
            if (isGuardFailure(outcome.reason) && !guardCode) return finish({ ok: false, needsGuard: true }, true)
            return finish({ ok: false, error: outcome.reason }, true)
          }
        }
        const prompt = detectPrompt(tail)
        if (!prompt) return
        if (prompt === 'password') {
          if (password === null || sentPassword) return finish({ ok: false, error: 'no cached Steam session' }, true)
          sentPassword = true
          answer(password)
        } else {
          if (!guardCode) return finish({ ok: false, needsGuard: true }, true)
          if (sentGuard) return finish({ ok: false, error: 'Steam Guard code rejected' }, true)
          sentGuard = true
          answer(guardCode)
        }
        tail = ''
      }

      child.stdout.on('data', feed)
      child.stderr.on('data', feed)
      child.on('error', (err) => finish({ ok: false, error: `could not run steamcmd: ${err.message}` }))
      child.on('close', (code) => {
        const rest = stripAnsi(tail)
        if (rest.trim() && log.length < MAX_LOG_LINES * 2) log.push(rest)
        finish(code === 0 ? { ok: true } : { ok: false, error: `steamcmd exited with code ${code}` })
      })
    })
  }
}
