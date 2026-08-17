/**
 * Blueprint install pipeline: executes install steps sequentially inside the
 * server directory with template variable substitution and live output.
 */
import fs from 'node:fs'
import path from 'node:path'
import { spawn } from 'node:child_process'
import type { Blueprint, InstallStep } from '../types.ts'
import { substituteVars, humanBytes } from '../lib/util.ts'
import { safeJoin } from '../lib/paths.ts'
import { downloadFile } from '../lib/download.ts'
import { unzip } from '../lib/zip.ts'
import { extractTar } from '../lib/tar.ts'
import { resolvePaper, resolveVanilla, resolveFabric } from './resolvers.ts'
import type { SteamCmdManager } from '../steam/steamcmd.ts'
import type { BlueprintRegistry } from '../blueprints/registry.ts'
import type { DockerService } from '../services/docker.ts'
import { LABEL_INSTALL } from '../servers/runtime.ts'

export interface InstallContext {
  blueprint: Blueprint
  serverDir: string
  vars: Record<string, string | number | boolean>
  steam: SteamCmdManager
  registry: BlueprintRegistry
  onLine: (line: string) => void
  /** Aborts the install between steps and kills in-flight child processes/downloads. */
  signal?: AbortSignal
  /** Required by docker-script steps (Pterodactyl-style container installs). */
  docker?: DockerService | null
  /**
   * Panel Steam account for login-required steamcmd steps (see steam/login.ts).
   * Absent (e.g. on node agents without their own login) = anonymous only.
   */
  steamAuth?: { user: string | null; isLoggedIn: () => Promise<boolean> }
  /** Server-level override: run every steamcmd step as `+login <panel account>`. */
  useSteamLogin?: boolean
}

/**
 * Resolve which `+login` a steamcmd step must use, failing fast with an
 * actionable error when a login is needed but no signed-in panel account
 * exists — a doomed anonymous download of a login-gated app would only fail
 * minutes later with SteamCMD's cryptic "No subscription".
 */
async function resolveSteamLogin(step: { requiresLogin?: boolean }, ctx: InstallContext): Promise<string | undefined> {
  const wanted = step.requiresLogin === true || ctx.useSteamLogin === true
  if (!wanted) return undefined
  const why = step.requiresLogin ? 'this game cannot be downloaded anonymously' : 'this server is set to install with the panel Steam account'
  const user = ctx.steamAuth?.user
  if (!user) {
    throw new Error(`Steam login required (${why}) — sign in under Panel Settings → Steam on this machine first`)
  }
  if (!(await ctx.steamAuth!.isLoggedIn())) {
    throw new Error(`Steam login required (${why}) — the cached session for "${user}" is gone, sign in again under Panel Settings → Steam`)
  }
  return user
}

async function extractArchive(file: string, destDir: string, onLine: (l: string) => void): Promise<boolean> {
  if (/\.zip$/i.test(file)) {
    onLine(`Extracting ${path.basename(file)}...`)
    const res = await unzip(file, destDir, {
      onProgress: (p) => {
        if (p.files % 200 === 0) onLine(`  ...${p.files}/${p.totalFiles} files`)
      },
    })
    onLine(`Extracted ${res.files} files.`)
    return true
  }
  if (/\.(tar\.gz|tgz|tar)$/i.test(file)) {
    onLine(`Extracting ${path.basename(file)}...`)
    const res = await extractTar(file, destDir, {
      onProgress: (p) => {
        if (p.files % 200 === 0) onLine(`  ...${p.files} files`)
      },
    })
    onLine(`Extracted ${res.files} files.`)
    return true
  }
  return false
}

async function runCommandStep(command: string, cwd: string, onLine: (l: string) => void, signal?: AbortSignal): Promise<void> {
  onLine(`$ ${command}`)
  await new Promise<void>((resolve, reject) => {
    const child = spawn(command, { shell: true, cwd, stdio: ['ignore', 'pipe', 'pipe'], signal })
    let buf = ''
    const feed = (chunk: Buffer) => {
      buf += chunk.toString()
      const lines = buf.split(/\r?\n/)
      buf = lines.pop() ?? ''
      if (buf.length > 64 * 1024) {
        lines.push(buf)
        buf = ''
      }
      for (const line of lines) onLine(line)
    }
    child.stdout.on('data', feed)
    child.stderr.on('data', feed)
    child.stdout.on('error', reject)
    child.stderr.on('error', reject)
    child.on('error', reject)
    // Wait for stdio to close so the final output chunk is included.
    child.on('close', (code) => {
      if (buf.trim()) onLine(buf)
      if (code === 0) resolve()
      else reject(new Error(`install command failed with exit code ${code}`))
    })
  })
}

/** Mount point for the server directory inside install containers (Pterodactyl convention). */
const INSTALL_MOUNT = '/mnt/server'
const INSTALL_SCRIPT_NAME = '.between-install.sh'

/**
 * Run an egg-style install script inside a throwaway container: the server
 * directory is bind-mounted at /mnt/server, the script runs as root (install
 * scripts apt/apk their dependencies) and its output streams to the console.
 */
async function runDockerScriptStep(
  step: Extract<InstallStep, { type: 'docker-script' }>,
  ctx: InstallContext,
): Promise<void> {
  const docker = ctx.docker
  const info = docker ? await docker.info() : null
  if (!docker || !info?.available)
    throw new Error('this blueprint needs Docker for its install script — no docker daemon reachable')
  const client = docker.client

  if (!(await client.imageExists(step.image))) {
    ctx.onLine(`Pulling install image ${step.image}...`)
    await client.pullImage(step.image, (line) => ctx.onLine(`  ${line}`), ctx.signal)
  }
  if (ctx.signal?.aborted) throw new Error('install aborted')

  const scriptPath = path.join(ctx.serverDir, INSTALL_SCRIPT_NAME)
  fs.writeFileSync(scriptPath, step.script, { mode: 0o755 })

  const env: Record<string, string> = {}
  for (const [key, value] of Object.entries(ctx.vars)) env[key] = String(value)
  env.HOME = INSTALL_MOUNT

  const entrypoint = step.entrypoint?.trim() || 'bash'
  ctx.onLine(`Running install script in ${step.image} (${entrypoint})...`)
  const containerId = await client.createContainer({
    name: `between-install-${crypto.randomUUID().slice(0, 8)}`,
    image: step.image,
    cmd: [],
    entrypoint: [entrypoint, `${INSTALL_MOUNT}/${INSTALL_SCRIPT_NAME}`],
    env,
    workdir: INSTALL_MOUNT,
    bind: { hostDir: path.resolve(ctx.serverDir), containerDir: INSTALL_MOUNT },
    ports: [],
    labels: { [LABEL_INSTALL]: '1' },
    networkMode: 'bridge',
  })

  // Deleting the server (or panel shutdown) mid-install must not leave the
  // script running — the container is killed, the finally block removes it.
  const onAbort = () => void client.killContainer(containerId, 'SIGKILL').catch(() => {})
  ctx.signal?.addEventListener('abort', onAbort, { once: true })

  const partial: Record<'stdout' | 'stderr', string> = { stdout: '', stderr: '' }
  const feed = (stream: 'stdout' | 'stderr', chunk: Buffer) => {
    let buf = partial[stream] + chunk.toString('utf8')
    const lines = buf.split(/\r?\n/)
    buf = lines.pop() ?? ''
    if (buf.length > 64 * 1024) {
      lines.push(buf)
      buf = ''
    }
    partial[stream] = buf
    for (const line of lines) if (line.length > 0) ctx.onLine(line)
  }

  let attachment: Awaited<ReturnType<typeof client.attachContainer>> | null = null
  try {
    // Attach before start so no output is missed; start the wait before start
    // too (condition=next-exit) so an instantly-exiting script cannot race it.
    attachment = await client.attachContainer(containerId, { onData: feed, onClose: () => {} })
    const waitPromise = client.waitContainer(containerId, ctx.signal)
    waitPromise.catch(() => {}) // surfaced via await below; never unhandled
    await client.startContainer(containerId)
    const exitCode = await waitPromise
    for (const stream of ['stdout', 'stderr'] as const) {
      if (partial[stream].trim()) ctx.onLine(partial[stream])
    }
    if (ctx.signal?.aborted) throw new Error('install aborted')
    if (exitCode !== 0) throw new Error(`install script failed (exit code ${exitCode})`)
    ctx.onLine('Install script finished.')
  } finally {
    ctx.signal?.removeEventListener('abort', onAbort)
    attachment?.close()
    await client.removeContainer(containerId, true).catch(() => {})
    fs.rmSync(scriptPath, { force: true })
  }
}

async function runStep(step: InstallStep, ctx: InstallContext): Promise<void> {
  const sub = (s: string) => substituteVars(s, ctx.vars)
  switch (step.type) {
    case 'steamcmd': {
      const appId = sub(String(step.appId)).trim()
      if (!appId) throw new Error('steamcmd step: empty app id')
      const betaBranch = step.betaBranch ? sub(step.betaBranch) : String(ctx.vars.BETA_BRANCH ?? '')
      const loginUser = await resolveSteamLogin(step, ctx)
      await ctx.steam.installApp(
        {
          appId,
          installDir: ctx.serverDir,
          betaBranch: betaBranch || undefined,
          validate: step.validate,
          platformOverride: step.platformOverride,
          loginUser,
          signal: ctx.signal,
        },
        ctx.onLine,
      )
      break
    }
    case 'download': {
      const url = sub(step.url).trim()
      if (!url) {
        ctx.onLine('Skipping optional download (no URL configured).')
        break
      }
      const target = safeJoin(ctx.serverDir, sub(step.target))
      ctx.onLine(`Downloading ${url}`)
      const res = await downloadFile(url, target, {
        sha256: step.sha256,
        signal: ctx.signal,
        onProgress: (p) => {
          if (p.pct !== null) ctx.onLine(`  ...${p.pct}% (${humanBytes(p.bytes)})`)
          else ctx.onLine(`  ...${humanBytes(p.bytes)}`)
        },
      })
      ctx.onLine(`Downloaded ${humanBytes(res.bytes)}.`)
      if (step.extract) {
        const extracted = await extractArchive(target, ctx.serverDir, ctx.onLine)
        if (extracted) fs.rmSync(target, { force: true })
        else ctx.onLine(`Note: ${path.basename(target)} is not an archive, keeping as-is.`)
      }
      break
    }
    case 'paper': {
      const version = String(ctx.vars[step.versionVar ?? 'MC_VERSION'] ?? 'latest')
      const resolved = await resolvePaper(step.project ?? 'paper', version)
      ctx.onLine(`Resolved ${resolved.label}`)
      const target = safeJoin(ctx.serverDir, sub(step.target ?? 'server.jar'))
      await downloadFile(resolved.url, target, {
        sha256: resolved.sha256,
        signal: ctx.signal,
        onProgress: (p) => p.pct !== null && ctx.onLine(`  ...${p.pct}% (${humanBytes(p.bytes)})`),
      })
      ctx.onLine(`Downloaded ${path.basename(target)}${resolved.sha256 ? ' (sha256 verified)' : ''}.`)
      break
    }
    case 'vanilla-minecraft': {
      const version = String(ctx.vars[step.versionVar ?? 'MC_VERSION'] ?? 'latest')
      const resolved = await resolveVanilla(version)
      ctx.onLine(`Resolved ${resolved.label}`)
      const target = safeJoin(ctx.serverDir, sub(step.target ?? 'server.jar'))
      await downloadFile(resolved.url, target, {
        signal: ctx.signal,
        onProgress: (p) => p.pct !== null && ctx.onLine(`  ...${p.pct}% (${humanBytes(p.bytes)})`),
      })
      ctx.onLine(`Downloaded ${path.basename(target)}.`)
      break
    }
    case 'fabric': {
      const version = String(ctx.vars[step.versionVar ?? 'MC_VERSION'] ?? 'latest')
      const resolved = await resolveFabric(version)
      ctx.onLine(`Resolved ${resolved.label}`)
      const target = safeJoin(ctx.serverDir, sub(step.target ?? 'server.jar'))
      await downloadFile(resolved.url, target, {
        signal: ctx.signal,
        onProgress: (p) => p.pct !== null && ctx.onLine(`  ...${p.pct}% (${humanBytes(p.bytes)})`),
      })
      ctx.onLine(`Downloaded ${path.basename(target)}.`)
      break
    }
    case 'writeFile': {
      const target = safeJoin(ctx.serverDir, sub(step.path))
      let content = step.content
      if (content.startsWith('@asset:')) content = ctx.registry.resolveAsset(content.slice('@asset:'.length))
      fs.mkdirSync(path.dirname(target), { recursive: true })
      fs.writeFileSync(target, sub(content))
      ctx.onLine(`Wrote ${sub(step.path)}`)
      break
    }
    case 'mkdir': {
      const target = safeJoin(ctx.serverDir, sub(step.path))
      fs.mkdirSync(target, { recursive: true })
      ctx.onLine(`Created directory ${sub(step.path)}`)
      break
    }
    case 'command': {
      await runCommandStep(sub(step.command), ctx.serverDir, ctx.onLine, ctx.signal)
      break
    }
    case 'docker-script': {
      await runDockerScriptStep(step, ctx)
      break
    }
  }
}

export async function runInstall(ctx: InstallContext): Promise<void> {
  fs.mkdirSync(ctx.serverDir, { recursive: true })
  const steps = ctx.blueprint.install
  ctx.onLine(`Installing "${ctx.blueprint.name}" (${steps.length} steps)...`)
  const startedAt = Date.now()
  for (let i = 0; i < steps.length; i++) {
    if (ctx.signal?.aborted) throw new Error('install aborted')
    ctx.onLine(`— Step ${i + 1}/${steps.length}: ${steps[i].type}`)
    await runStep(steps[i], ctx)
  }
  if (ctx.signal?.aborted) throw new Error('install aborted')
  ctx.onLine(`Install finished in ${((Date.now() - startedAt) / 1000).toFixed(1)}s.`)
}
