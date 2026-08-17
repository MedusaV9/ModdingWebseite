/**
 * Unit tests for the interactive SteamCMD login flow helpers: prompt
 * detection on unterminated stream tails, output line classification and
 * secret scrubbing (the never-log-the-password guarantee).
 */
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { classifyLine, detectPrompt, isGuardFailure, scrubSecrets, stripAnsi, SECRET_MASK } from '../../src/steam/loginflow.ts'

// ---------------------------------------------------------------------------
// detectPrompt — prompts arrive WITHOUT trailing newline, so detection runs
// on the raw stream tail
// ---------------------------------------------------------------------------
test('detectPrompt finds the password prompt at the stream tail', () => {
  assert.equal(detectPrompt('password: '), 'password')
  assert.equal(detectPrompt('password:'), 'password')
  assert.equal(detectPrompt('PASSWORD: '), 'password')
  assert.equal(detectPrompt("Logging in user 'x' to Steam Public...\nCached credentials not found.\npassword: "), 'password')
})

test('detectPrompt finds Steam Guard prompts (email + mobile authenticator wording)', () => {
  assert.equal(detectPrompt('Steam Guard code: '), 'guard')
  assert.equal(detectPrompt('Two-factor code: '), 'guard')
  assert.equal(detectPrompt('Two factor code:'), 'guard')
  assert.equal(detectPrompt('Enter the current code from your Steam Guard Mobile Authenticator app\nTwo-factor code: '), 'guard')
  // The guard prompt also says "code:", so guard must win over password.
  assert.equal(detectPrompt('password ok\nSteam Guard code: '), 'guard')
})

test('detectPrompt ignores partial and mid-line matches', () => {
  assert.equal(detectPrompt('passwo'), null)
  assert.equal(detectPrompt(''), null)
  assert.equal(detectPrompt('password: retry later'), null)
  assert.equal(detectPrompt('Loading Steam API...OK'), null)
  assert.equal(detectPrompt('type your password: then press enter later'), null)
})

test('detectPrompt sees through ANSI codes (real steamcmd wraps prompts in SGR)', () => {
  // Byte-exact chunk observed from steamcmd version 1785799152:
  assert.equal(detectPrompt('\u001b[1mCached credentials not found.\n\u001b[0m\npassword: \u001b[0m'), 'password')
  assert.equal(detectPrompt('password: \u001b[0m'), 'password')
  assert.equal(detectPrompt('\u001b[1mTwo-factor code:\u001b[0m '), 'guard')
  // ANSI mid-text must not create a false prompt.
  assert.equal(detectPrompt('\u001b[0mLoading Steam API...OK'), null)
})

// ---------------------------------------------------------------------------
// classifyLine
// ---------------------------------------------------------------------------
test('classifyLine recognizes success markers across steamcmd versions', () => {
  assert.deepEqual(classifyLine('Logged in OK'), { type: 'success' })
  assert.deepEqual(classifyLine('Waiting for user info...OK'), { type: 'success' })
  assert.deepEqual(classifyLine('Waiting for user info ... OK'), { type: 'success' })
})

test('classifyLine recognizes failure variants and extracts the reason', () => {
  // Current real builds report ERROR (...) — observed live from version 1785799152.
  assert.deepEqual(classifyLine('ERROR (Invalid Password)'), { type: 'failure', reason: 'Invalid Password' })
  assert.deepEqual(classifyLine('ERROR (Invalid Password)\u001b[0m'), { type: 'failure', reason: 'Invalid Password' })
  assert.deepEqual(classifyLine('FAILED (Invalid Password)'), { type: 'failure', reason: 'Invalid Password' })
  assert.deepEqual(classifyLine('FAILED (Two-factor code mismatch)'), { type: 'failure', reason: 'Two-factor code mismatch' })
  assert.deepEqual(classifyLine('FAILED (Rate Limit Exceeded)'), { type: 'failure', reason: 'Rate Limit Exceeded' })
  assert.deepEqual(classifyLine('FAILED login with result code 5'), { type: 'failure', reason: '5' })
  assert.deepEqual(classifyLine('Login Failure: Invalid Password'), { type: 'failure', reason: 'Invalid Password' })
})

test('classifyLine returns null for boot noise and unrelated OK lines', () => {
  assert.equal(classifyLine('Loading Steam API...OK'), null)
  assert.equal(classifyLine('Connecting anonymously to Steam Public...OK'), null)
  assert.equal(classifyLine('Waiting for client config...OK'), null)
  assert.equal(classifyLine('[  0%] Checking for available updates...'), null)
  assert.equal(classifyLine(''), null)
})

test('stripAnsi removes CSI sequences and leaves plain text alone', () => {
  assert.equal(stripAnsi('\u001b[1mbold\u001b[0m plain'), 'bold plain')
  assert.equal(stripAnsi('no ansi here'), 'no ansi here')
  assert.equal(stripAnsi('\u001b[0m'), '')
})

test('isGuardFailure only matches guard-related reasons', () => {
  assert.equal(isGuardFailure('Two-factor code mismatch'), true)
  assert.equal(isGuardFailure('Account Logon Denied'), true) // email guard pending
  assert.equal(isGuardFailure('Invalid Password'), false)
  assert.equal(isGuardFailure('Rate Limit Exceeded'), false)
})

// ---------------------------------------------------------------------------
// scrubSecrets — defense in depth: even if steamcmd echoed input, nothing
// secret may reach logs, consoles or API responses
// ---------------------------------------------------------------------------
test('scrubSecrets masks every occurrence of every secret', () => {
  const out = scrubSecrets('pw=hunter22 again hunter22 code 424242', ['hunter22', '424242'])
  assert.equal(out, `pw=${SECRET_MASK} again ${SECRET_MASK} code ${SECRET_MASK}`)
  assert.ok(!out.includes('hunter22'))
})

test('scrubSecrets skips empty/short/absent secrets without shredding text', () => {
  assert.equal(scrubSecrets('nothing to hide', []), 'nothing to hide')
  assert.equal(scrubSecrets('a b abc', ['', null, undefined, 'abc']), 'a b ***')
  // 1-2 char "secrets" would mask random letters — they are skipped.
  assert.equal(scrubSecrets('same text', ['e', 'ab']), 'same text')
})

test('scrubSecrets handles secrets containing regex metacharacters', () => {
  assert.equal(scrubSecrets('pass p4$$.w(or)d end', ['p4$$.w(or)d']), `pass ${SECRET_MASK} end`)
})
