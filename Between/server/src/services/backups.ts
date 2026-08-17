import fs from 'node:fs'
import path from 'node:path'
import type { Store, Collection } from '../lib/jsonstore.ts'
import type { Backup, PanelSettings } from '../types.ts'
import type { ServerManager } from '../servers/manager.ts'
import type { AuditService } from './audit.ts'
import { zipDirectory, unzip } from '../lib/zip.ts'
import { nowIso } from '../lib/util.ts'

/** Convert a simple glob (supports ** and *) to a RegExp on forward-slash paths. */
export function globToRegex(glob: string): RegExp {
  let re = ''
  for (let i = 0; i < glob.length; i++) {
    const ch = glob[i]
    if (ch === '*') {
      if (glob[i + 1] === '*') {
        re += '.*'
        i++
        if (glob[i + 1] === '/') i++
      } else re += '[^/]*'
    } else if ('\\^$.|?+()[]{}'.includes(ch)) re += `\\${ch}`
    else if (ch === '/') re += '/'
    else re += ch
  }
  return new RegExp(`^${re}(/|$)`)
}

/**
 * Pure prune selection for the "keep the last N unlocked backups" policy:
 * returns the ids that fall out of the window, oldest first. Locked backups
 * are exempt twice over — they are never candidates AND they don't count
 * toward N. keep <= 0 (or non-finite) means unlimited: nothing is pruned.
 */
export function selectBackupsToPrune(
  backups: { id: string; createdAt: string; locked: boolean }[],
  keep: number,
): string[] {
  if (!Number.isFinite(keep) || keep <= 0) return []
  return backups
    .filter((b) => !b.locked)
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
    .slice(Math.floor(keep))
    .reverse()
    .map((b) => b.id)
}

export class BackupService {
  readonly backups: Collection<Backup>
  private root: string
  private running = new Set<string>()

  constructor(
    store: Store,
    private manager: ServerManager,
    dataDir: string,
    private settings: Collection<PanelSettings>,
    private audit: AuditService,
  ) {
    this.backups = store.collection<Backup>('backups')
    this.root = path.join(dataDir, 'backups')
    fs.mkdirSync(this.root, { recursive: true })
  }

  list(serverId: string): Backup[] {
    return this.backups
      .filter((b) => b.serverId === serverId)
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt))
  }

  fileOf(backup: Backup): string {
    return path.join(this.root, backup.serverId, backup.fileName)
  }

  isBusy(serverId: string): boolean {
    return this.running.has(serverId)
  }

  /** Effective "keep last N unlocked" for a server: per-server override, else panel default. 0 = unlimited. */
  effectiveRetention(serverId: string): number {
    const perServer = this.manager.servers.get(serverId)?.backupRetention
    if (typeof perServer === 'number' && Number.isFinite(perServer)) return perServer
    return this.settings.all()[0]?.defaultBackupRetention ?? 10
  }

  async create(serverId: string, note: string, opts: { auto?: boolean; protectId?: string } = {}): Promise<Backup> {
    if (this.running.has(serverId)) throw new Error('a backup is already running for this server')
    const inst = this.manager.instance(serverId)
    this.running.add(serverId)
    try {
      const excludes = [...(inst.blueprint.backupExcludes ?? []), '.between/logs/**'].map(globToRegex)
      const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19)
      // The stamp has second precision — two backups within one second (e.g.
      // a schedule with two backup tasks) must not share an archive, or
      // pruning one would silently destroy the other's file.
      let fileName = `${stamp}.zip`
      let dest = path.join(this.root, serverId, fileName)
      for (let i = 2; fs.existsSync(dest); i++) {
        fileName = `${stamp}-${i}.zip`
        dest = path.join(this.root, serverId, fileName)
      }
      inst.pushLine('system', `Creating backup${note ? ` "${note}"` : ''}...`)
      const result = await zipDirectory(inst.serverDir, dest, {
        exclude: (rel) => excludes.some((re) => re.test(rel)),
      })
      const backup = this.backups.insert({
        serverId,
        fileName,
        note: String(note ?? '').slice(0, 200),
        sizeBytes: result.bytes,
        createdAt: nowIso(),
        locked: false,
        auto: Boolean(opts.auto),
      })
      inst.pushLine('system', `Backup complete: ${fileName} (${result.files} files).`)
      // Retention must never fail an otherwise successful backup.
      try {
        this.enforceRetention(serverId, opts.protectId)
      } catch (err) {
        inst.pushLine('system', `Backup retention check failed: ${(err as Error).message}`)
      }
      return backup
    } finally {
      this.running.delete(serverId)
    }
  }

  /**
   * Enforce "keep the last N unlocked backups" after every successful create —
   * the single choke point shared by manual, scheduled and pre-restore safety
   * backups. `protectId` shields the backup currently being restored from the
   * safety backup it triggered (excluded from candidates AND from the count
   * for this round, like a locked backup). Per-file failures log and continue.
   */
  private enforceRetention(serverId: string, protectId?: string) {
    const keep = this.effectiveRetention(serverId)
    if (keep <= 0) return
    const candidates = this.list(serverId).filter((b) => b.id !== protectId)
    const pruneIds = new Set(selectBackupsToPrune(candidates, keep))
    if (pruneIds.size === 0) return
    const inst = this.manager.instances.get(serverId)
    for (const old of candidates.filter((b) => pruneIds.has(b.id))) {
      try {
        fs.rmSync(this.fileOf(old), { force: true })
        this.backups.remove(old.id)
        this.audit.log(null, 'backup.pruned', {
          target: old.fileName,
          serverId,
          meta: { backupId: old.id, keep },
        })
        inst?.pushLine('system', `Backup retention: removed ${old.fileName} (keeping the last ${keep} unlocked).`)
      } catch (err) {
        inst?.pushLine('system', `Backup retention: could not remove ${old.fileName}: ${(err as Error).message}`)
      }
    }
  }

  async restore(serverId: string, backupId: string, opts: { wipe?: boolean; safetyBackup?: boolean } = {}): Promise<void> {
    const inst = this.manager.instance(serverId)
    if (inst.active) throw new Error('stop the server before restoring a backup')
    const backup = this.backups.get(backupId)
    if (!backup || backup.serverId !== serverId) throw new Error('backup not found')
    const file = this.fileOf(backup)
    if (!fs.existsSync(file)) throw new Error('backup archive is missing on disk')

    if (opts.safetyBackup !== false) {
      await this.create(serverId, `pre-restore safety (${backup.fileName})`, { auto: true, protectId: backup.id })
    }
    if (opts.wipe) {
      for (const entry of fs.readdirSync(inst.serverDir)) {
        if (entry === '.between') continue
        fs.rmSync(path.join(inst.serverDir, entry), { recursive: true, force: true })
      }
      inst.pushLine('system', 'Server directory wiped for clean restore.')
    }
    inst.pushLine('system', `Restoring backup ${backup.fileName}...`)
    const res = await unzip(file, inst.serverDir)
    inst.pushLine('system', `Restore complete (${res.files} files).`)
  }

  remove(serverId: string, backupId: string): void {
    const backup = this.backups.get(backupId)
    if (!backup || backup.serverId !== serverId) throw new Error('backup not found')
    if (backup.locked) throw new Error('backup is locked')
    fs.rmSync(this.fileOf(backup), { force: true })
    this.backups.remove(backupId)
  }

  setLocked(serverId: string, backupId: string, locked: boolean): Backup {
    const backup = this.backups.get(backupId)
    if (!backup || backup.serverId !== serverId) throw new Error('backup not found')
    return this.backups.update(backupId, { locked: Boolean(locked) })!
  }

  removeAllForServer(serverId: string): void {
    this.backups.removeWhere((b) => b.serverId === serverId)
    fs.rmSync(path.join(this.root, serverId), { recursive: true, force: true })
  }
}
