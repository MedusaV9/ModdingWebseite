/**
 * Pure helpers for driving an interactive `steamcmd +login <user>` session:
 * prompt detection on a raw output stream, result classification and secret
 * scrubbing. Kept side-effect free so the edge cases are unit-testable
 * without spawning anything.
 *
 * SteamCMD prints its prompts WITHOUT a trailing newline (`password: `,
 * `Steam Guard code: `, `Two-factor code: `), so detection must run on the
 * unterminated tail of the stream, not on completed lines. The real binary
 * also wraps its output in ANSI SGR codes — the password prompt arrives as
 * `password: \x1b[0m` — so everything is ANSI-stripped before matching.
 */

export type SteamPrompt = 'password' | 'guard'

/** Replacement for scrubbed secrets in any logged/streamed output. */
export const SECRET_MASK = '***'

// CSI escape sequences (colors/bold — steamcmd interleaves \x1b[1m/\x1b[0m).
// eslint-disable-next-line no-control-regex
const ANSI_RE = /\u001b\[[0-9;]*[A-Za-z]/g

/** Strip ANSI CSI sequences so prompt/outcome matching sees plain text. */
export function stripAnsi(text: string): string {
  return text.replace(ANSI_RE, '')
}

// Tail-anchored: the prompt is the last thing steamcmd wrote before blocking
// on stdin. "Steam Guard code" = e-mail guard, "Two-factor code" = mobile
// authenticator — both are answered the same way.
const PASSWORD_PROMPT_RE = /password\s*:\s*$/i
const GUARD_PROMPT_RE = /(steam guard code|two[- ]factor code|auth code)\s*:\s*$/i

/** Detect a pending interactive prompt at the end of the output stream. */
export function detectPrompt(tail: string): SteamPrompt | null {
  const plain = stripAnsi(tail)
  if (GUARD_PROMPT_RE.test(plain)) return 'guard'
  if (PASSWORD_PROMPT_RE.test(plain)) return 'password'
  return null
}

export type LoginOutcome = { type: 'success' } | { type: 'failure'; reason: string }

/**
 * Classify a completed output line. Success markers cover current and older
 * SteamCMD builds; failures come as `ERROR (Reason)` (current builds, e.g.
 * `ERROR (Invalid Password)`), `FAILED (Reason)`, `FAILED login with result
 * code ...` and `Login Failure: ...` (legacy).
 */
export function classifyLine(rawLine: string): LoginOutcome | null {
  const line = stripAnsi(rawLine)
  if (/logged in ok/i.test(line)) return { type: 'success' }
  if (/waiting for user info\s*\.*\s*ok/i.test(line)) return { type: 'success' }
  const failed = line.match(/(?:FAILED|ERROR)\s*\(([^)]+)\)/i)
  if (failed) return { type: 'failure', reason: failed[1].trim() }
  const resultCode = line.match(/FAILED login with result code\s+(.+)/i)
  if (resultCode) return { type: 'failure', reason: resultCode[1].trim() }
  const legacy = line.match(/login failure:\s*(.+)/i)
  if (legacy) return { type: 'failure', reason: legacy[1].trim() }
  return null
}

/** True when the failure reason means "correct password, guard code needed". */
export function isGuardFailure(reason: string): boolean {
  return /(guard|two[- ]factor|account logon denied)/i.test(reason)
}

/**
 * Remove secrets from a chunk of output before it is logged, streamed or
 * returned. SteamCMD never echoes typed input, so in practice this never
 * fires — it exists as defense in depth and is asserted in tests. Secrets
 * shorter than 3 chars are skipped (masking single letters would shred
 * unrelated text without hiding anything).
 */
export function scrubSecrets(text: string, secrets: (string | undefined | null)[]): string {
  let result = text
  for (const secret of secrets) {
    if (!secret || secret.length < 3) continue
    result = result.split(secret).join(SECRET_MASK)
  }
  return result
}
