#!/usr/bin/env node
/**
 * fake-steamcmd — a tiny stand-in for Valve's SteamCMD, for developing and
 * testing Between's authenticated Steam login flow without a real Steam
 * account. Point BETWEEN_STEAMCMD_BIN at this script (or a thin wrapper that
 * execs it) and the panel talks to it exactly like the real binary.
 *
 * Emulated behavior (byte sequences mirror REAL SteamCMD output, verified
 * against version 1785799152 — including the ANSI SGR codes it interleaves
 * and the missing newline after prompts):
 *   - `+login anonymous`                → connects without prompts
 *   - `+login <user>` w/ cached session → succeeds without prompts (sentry)
 *   - `+login <user>` w/o session       → prints `password: \x1b[0m` (ANSI
 *     reset, NO newline!) and reads the password from stdin; wrong →
 *     `ERROR (Invalid Password)` (current builds say ERROR, older FAILED)
 *   - Steam Guard: when FAKE_STEAMCMD_GUARD is set, a correct password is
 *     followed by a `Two-factor code:` prompt; wrong code →
 *     `ERROR (Two-factor code mismatch)`
 *   - successful login writes a session cache the same way the real steamcmd
 *     does (`config/config.vdf` + an `ssfn*` sentry file in its home dir),
 *     so Between's logout (which deletes those files) works against the fake
 *   - `+app_update <id> [-beta b] [validate]` creates
 *     `<force_install_dir>/fake-app-<id>.txt` recording which login was used;
 *     apps listed in FAKE_STEAMCMD_LOGIN_APPS refuse anonymous installs with
 *     `ERROR! Failed to install app '<id>' (No subscription)`
 *
 * Config (env):
 *   FAKE_STEAMCMD_HOME        session/sentry dir (default: cwd — Between runs
 *                             steamcmd with cwd = its steamcmd data dir)
 *   FAKE_STEAMCMD_USER        the one valid account name   (default: demo)
 *   FAKE_STEAMCMD_PASS        its password                 (default: hunter22)
 *   FAKE_STEAMCMD_GUARD       expected Steam Guard code ('' = guard disabled)
 *   FAKE_STEAMCMD_LOGIN_APPS  comma-separated app ids that require a login
 */
import fs from 'node:fs'
import path from 'node:path'
import readline from 'node:readline'

const HOME = process.env.FAKE_STEAMCMD_HOME || process.cwd()
const VALID_USER = process.env.FAKE_STEAMCMD_USER || 'demo'
const VALID_PASS = process.env.FAKE_STEAMCMD_PASS || 'hunter22'
const GUARD_CODE = process.env.FAKE_STEAMCMD_GUARD || ''
const LOGIN_APPS = new Set(
  (process.env.FAKE_STEAMCMD_LOGIN_APPS || '').split(',').map((s) => s.trim()).filter(Boolean),
)

const configFile = path.join(HOME, 'config', 'config.vdf')
const sentryFile = (user) => path.join(HOME, `ssfn_fake_${user.toLowerCase()}`)

function hasCachedSession(user) {
  if (!fs.existsSync(sentryFile(user)) || !fs.existsSync(configFile)) return false
  return fs.readFileSync(configFile, 'utf8').includes(`"${user.toLowerCase()}"`)
}

function writeSession(user) {
  fs.mkdirSync(path.dirname(configFile), { recursive: true })
  fs.writeFileSync(configFile, `"InstallConfigStore"\n{\n\t"ConnectCache"\n\t{\n\t\t"${user.toLowerCase()}"\t\t"fake"\n\t}\n}\n`)
  fs.writeFileSync(sentryFile(user), 'fake-sentry')
}

const rl = readline.createInterface({ input: process.stdin, terminal: false })
const pendingLines = []
const waiters = []
rl.on('line', (line) => {
  const waiter = waiters.shift()
  if (waiter) waiter(line)
  else pendingLines.push(line)
})
rl.on('close', () => {
  // stdin EOF (e.g. spawned with stdin=/dev/null): every outstanding and
  // future prompt read fails like the real steamcmd giving up on the login.
  while (waiters.length > 0) waiters.shift()(null)
  stdinClosed = true
})
let stdinClosed = false

function readLine() {
  if (pendingLines.length > 0) return Promise.resolve(pendingLines.shift())
  if (stdinClosed) return Promise.resolve(null)
  return new Promise((resolve) => waiters.push(resolve))
}

/**
 * Prompt WITHOUT a trailing newline but WITH the trailing ANSI reset,
 * exactly like the real steamcmd (`password: \x1b[0m`).
 */
function prompt(text) {
  process.stdout.write(text + '\u001b[0m')
  return readLine()
}

function out(line) {
  process.stdout.write(line + '\n')
}

function fail(reason, code = 5) {
  out(`ERROR (${reason})\u001b[0m`)
  process.exit(code)
}

// ---------------------------------------------------------------------------
// Parse the +command argv into steamcmd-style commands
// ---------------------------------------------------------------------------
const argv = process.argv.slice(2)
const commands = []
for (let i = 0; i < argv.length; i++) {
  if (argv[i].startsWith('+')) {
    const cmd = { name: argv[i].slice(1), args: [] }
    while (i + 1 < argv.length && !argv[i + 1].startsWith('+')) cmd.args.push(argv[++i])
    commands.push(cmd)
  }
}

let loggedInAs = null // 'anonymous' | username
let installDir = null

out('Redirecting stderr to fake_logs/stderr.txt')
out('[  0%] Checking for available updates...')
out('[----] Verifying installation...')
out('Steam Console Client (c) Valve Corporation - version fake-1')
out('Loading Steam API...OK')

async function doLogin(user, passArg) {
  if (user === 'anonymous') {
    out('Connecting anonymously to Steam Public...OK')
    out('Waiting for client config...OK')
    out('Waiting for user info...OK')
    loggedInAs = 'anonymous'
    return
  }
  out(`Logging in user '${user}' to Steam Public...`)
  if (hasCachedSession(user)) {
    out('OK')
    out('Waiting for client config...OK')
    out('Waiting for user info...OK')
    loggedInAs = user
    return
  }
  let password = passArg
  if (password === undefined) {
    // Real chunk: "\x1b[1mCached credentials not found.\n\x1b[0m\npassword: \x1b[0m"
    process.stdout.write('\u001b[1mCached credentials not found.\n\u001b[0m\n')
    password = await prompt('password: ')
    if (password === null) fail('Login Denied — no password on stdin')
    process.stdout.write('\u001b[1m\nProceeding with login using username/password.\n\u001b[0m')
  }
  if (user.toLowerCase() !== VALID_USER.toLowerCase() || password !== VALID_PASS) {
    fail('Invalid Password')
  }
  if (GUARD_CODE) {
    out('This account is protected by a Steam Guard mobile authenticator.')
    const code = await prompt('Two-factor code: ')
    if (code === null) fail('Two-factor code mismatch')
    if (code.trim() !== GUARD_CODE) fail('Two-factor code mismatch')
  }
  writeSession(user)
  out('Logged in OK')
  out('Waiting for client config...OK')
  out('Waiting for user info...OK')
  loggedInAs = user
}

function doAppUpdate(args) {
  const appId = args[0]
  if (!loggedInAs) fail('Not logged on', 2)
  if (LOGIN_APPS.has(appId) && loggedInAs === 'anonymous') {
    out(` ERROR! Failed to install app '${appId}' (No subscription)`)
    process.exit(5)
  }
  const dir = installDir || path.join(HOME, 'steamapps')
  fs.mkdirSync(dir, { recursive: true })
  const beta = args.includes('-beta') ? args[args.indexOf('-beta') + 1] : ''
  out(` Update state (0x61) downloading, progress: 42.00 (fake)`)
  fs.writeFileSync(path.join(dir, `fake-app-${appId}.txt`), `login=${loggedInAs}\nbeta=${beta}\n`)
  out(`Success! App '${appId}' fully installed.`)
}

for (const cmd of commands) {
  switch (cmd.name) {
    case 'login':
      await doLogin(cmd.args[0] ?? 'anonymous', cmd.args[1])
      break
    case 'force_install_dir':
      installDir = cmd.args[0]
      break
    case 'app_update':
      doAppUpdate(cmd.args)
      break
    case 'logout':
      loggedInAs = null
      out('Logging out user')
      break
    case '@sSteamCmdForcePlatformType':
      break // accepted, irrelevant for the fake
    case 'quit':
      process.exit(0)
      break
    default:
      out(`Unknown command "${cmd.name}"`)
  }
}
process.exit(0)
