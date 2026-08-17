/**
 * SteamCMD manager: downloads/updates SteamCMD itself per platform and runs
 * app installs/updates with live output. `force_install_dir` is always set
 * BEFORE `login` (required by current SteamCMD versions).
 */
import fs from 'node:fs'
import path from 'node:path'
import { spawn } from 'node:child_process'
import { downloadFile } from '../lib/download.ts'
import { extractTar } from '../lib/tar.ts'
import { unzip } from '../lib/zip.ts'

const STEAMCMD_LINUX_URL = 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz'
const STEAMCMD_WINDOWS_URL = 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip'
const STEAMCMD_MACOS_URL = 'https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz'

export type LineSink = (line: string) => void

export class SteamCmdManager {
  /**
   * @param binOverride BETWEEN_STEAMCMD_BIN — use this executable instead of
   * downloading/bootstrapping the bundled SteamCMD (tests point it at
   * scripts/fake-steamcmd.mjs). `baseDir` stays the working/session dir.
   */
  constructor(private baseDir: string, private binOverride: string | null = null) {}

  get dir(): string {
    return this.baseDir
  }

  get executable(): string {
    if (this.binOverride) return this.binOverride
    if (process.platform === 'win32') return path.join(this.baseDir, 'steamcmd.exe')
    return path.join(this.baseDir, 'steamcmd.sh')
  }

  isInstalled(): boolean {
    return fs.existsSync(this.executable)
  }

  async ensureInstalled(onLine: LineSink, signal?: AbortSignal): Promise<void> {
    if (this.binOverride) {
      if (!fs.existsSync(this.binOverride)) throw new Error(`BETWEEN_STEAMCMD_BIN not found: ${this.binOverride}`)
      fs.mkdirSync(this.baseDir, { recursive: true })
      return
    }
    if (this.isInstalled()) return
    fs.mkdirSync(this.baseDir, { recursive: true })
    const platform = process.platform
    onLine(`Downloading SteamCMD for ${platform}...`)
    if (platform === 'win32') {
      const zipFile = path.join(this.baseDir, 'steamcmd.zip')
      await downloadFile(STEAMCMD_WINDOWS_URL, zipFile, { signal })
      await unzip(zipFile, this.baseDir)
      fs.rmSync(zipFile, { force: true })
    } else {
      const url = platform === 'darwin' ? STEAMCMD_MACOS_URL : STEAMCMD_LINUX_URL
      const tarFile = path.join(this.baseDir, 'steamcmd.tar.gz')
      await downloadFile(url, tarFile, { signal })
      await extractTar(tarFile, this.baseDir)
      fs.rmSync(tarFile, { force: true })
      try {
        fs.chmodSync(this.executable, 0o755)
      } catch { /* mode came from tar */ }
    }
    onLine('SteamCMD downloaded.')
  }

  /**
   * Run steamcmd with the given +commands. Returns the exit code.
   * SteamCMD self-updates on first run, which is expected and can be slow.
   */
  run(commands: string[], onLine: LineSink, signal?: AbortSignal): Promise<number> {
    return new Promise((resolve, reject) => {
      const child = spawn(this.executable, commands, {
        cwd: this.baseDir,
        stdio: ['ignore', 'pipe', 'pipe'],
        env: { ...process.env, HOME: process.env.HOME ?? this.baseDir },
        signal,
      })
      let buffer = ''
      const feed = (chunk: Buffer) => {
        buffer += chunk.toString()
        // steamcmd uses \r for progress updates
        const lines = buffer.split(/\r?\n|\r/)
        buffer = lines.pop() ?? ''
        if (buffer.length > 64 * 1024) {
          lines.push(buffer)
          buffer = ''
        }
        for (const line of lines) if (line.trim()) onLine(line)
      }
      child.stdout.on('data', feed)
      child.stderr.on('data', feed)
      child.stdout.on('error', reject)
      child.stderr.on('error', reject)
      child.on('error', reject)
      // `close` waits for both output pipes, so the final progress/error line
      // cannot arrive after this promise has already resolved.
      child.on('close', (code) => {
        if (buffer.trim()) onLine(buffer)
        resolve(code ?? -1)
      })
    })
  }

  /**
   * Install or update an app into `installDir` using anonymous login, or
   * `+login <user>` when `loginUser` is set. No password is ever passed:
   * an authenticated install relies on the session SteamCMD cached during
   * the interactive panel login (see steam/login.ts) — with no cached
   * session the child reads EOF at the password prompt and fails cleanly.
   * Exit codes 0 and 6/7 variants are treated as success when the manifest
   * exists; SteamCMD is notoriously loose with exit codes.
   */
  async installApp(
    opts: {
      appId: string | number
      installDir: string
      betaBranch?: string
      validate?: boolean
      platformOverride?: 'windows' | 'linux'
      /** Steam account name for `+login <user>` (cached session required). */
      loginUser?: string
      signal?: AbortSignal
    },
    onLine: LineSink,
  ): Promise<void> {
    await this.ensureInstalled(onLine, opts.signal)
    fs.mkdirSync(opts.installDir, { recursive: true })
    const commands: string[] = []
    if (opts.platformOverride) commands.push('+@sSteamCmdForcePlatformType', opts.platformOverride)
    commands.push('+force_install_dir', opts.installDir)
    commands.push('+login', opts.loginUser ?? 'anonymous')
    const update = ['+app_update', String(opts.appId)]
    if (opts.betaBranch && opts.betaBranch.trim()) update.push('-beta', opts.betaBranch.trim())
    if (opts.validate !== false) update.push('validate')
    commands.push(...update, '+quit')

    const asUser = opts.loginUser ? ` as ${opts.loginUser}` : ''
    onLine(`Running SteamCMD: app_update ${opts.appId}${opts.betaBranch ? ` (beta ${opts.betaBranch})` : ''}${asUser}...`)
    const code = await this.run(commands, onLine, opts.signal)
    if (code !== 0) {
      if (opts.signal?.aborted) throw new Error('install aborted')
      // Retry once — steamcmd frequently fails transiently on first self-update.
      onLine(`SteamCMD exited with code ${code}, retrying once...`)
      const retry = await this.run(commands, onLine, opts.signal)
      if (retry !== 0) throw new Error(`SteamCMD failed with exit code ${retry} (app ${opts.appId})`)
    }
    onLine(`SteamCMD finished for app ${opts.appId}.`)
  }
}
