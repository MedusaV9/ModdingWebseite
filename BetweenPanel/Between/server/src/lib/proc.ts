/**
 * Cross-platform process-tree utilities: kill a whole tree and sample
 * CPU/memory of a tree. Linux uses /proc directly; Windows uses
 * taskkill/PowerShell; other unixes fall back to ps/kill.
 */
import fs from 'node:fs'
import { execFile } from 'node:child_process'

export interface TreeSample {
  /** Cumulative CPU time of the whole tree, in milliseconds. */
  cpuMs: number
  /** Resident set size of the whole tree, in bytes. */
  rssBytes: number
  processes: number
}

interface ProcRow {
  pid: number
  ppid: number
  cpuMs: number
  rssBytes: number
}

function listProcessesLinux(): ProcRow[] {
  const rows: ProcRow[] = []
  let names: string[]
  try {
    names = fs.readdirSync('/proc')
  } catch {
    return rows
  }
  const pageSize = 4096
  const hz = 100 // USER_HZ is 100 on virtually all Linux systems
  for (const name of names) {
    if (!/^\d+$/.test(name)) continue
    try {
      const stat = fs.readFileSync(`/proc/${name}/stat`, 'utf8')
      // comm can contain spaces/parens; fields resume after the LAST ')'
      const close = stat.lastIndexOf(')')
      const rest = stat.slice(close + 2).split(' ')
      const ppid = parseInt(rest[1], 10)
      const utime = parseInt(rest[11], 10)
      const stime = parseInt(rest[12], 10)
      const rssPages = parseInt(rest[21], 10)
      rows.push({
        pid: parseInt(name, 10),
        ppid,
        cpuMs: ((utime + stime) / hz) * 1000,
        rssBytes: rssPages * pageSize,
      })
    } catch {
      /* process vanished */
    }
  }
  return rows
}

function listProcessesPs(): Promise<ProcRow[]> {
  return new Promise((resolve) => {
    execFile('ps', ['-axo', 'pid=,ppid=,rss=,time='], { timeout: 4000 }, (err, stdout) => {
      if (err) return resolve([])
      const rows: ProcRow[] = []
      for (const line of stdout.split('\n')) {
        const m = line.trim().match(/^(\d+)\s+(\d+)\s+(\d+)\s+(\S+)$/)
        if (!m) continue
        const [, pid, ppid, rssKb, time] = m
        // time format: [[dd-]hh:]mm:ss
        let cpuS = 0
        const t = time.replace('-', ':').split(':').map(Number)
        for (const part of t) cpuS = cpuS * 60 + part
        rows.push({ pid: +pid, ppid: +ppid, cpuMs: cpuS * 1000, rssBytes: +rssKb * 1024 })
      }
      resolve(rows)
    })
  })
}

function listProcessesWindows(): Promise<ProcRow[]> {
  const cmd =
    'Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId,WorkingSetSize,UserModeTime,KernelModeTime | ConvertTo-Json -Compress'
  return new Promise((resolve) => {
    execFile('powershell', ['-NoProfile', '-Command', cmd], { timeout: 10000, maxBuffer: 16 * 1024 * 1024 }, (err, stdout) => {
      if (err) return resolve([])
      try {
        const arr = JSON.parse(stdout)
        const list = Array.isArray(arr) ? arr : [arr]
        resolve(
          list.map((p: Record<string, number>) => ({
            pid: p.ProcessId,
            ppid: p.ParentProcessId,
            // UserModeTime/KernelModeTime are in 100ns units
            cpuMs: ((p.UserModeTime ?? 0) + (p.KernelModeTime ?? 0)) / 10000,
            rssBytes: p.WorkingSetSize ?? 0,
          })),
        )
      } catch {
        resolve([])
      }
    })
  })
}

function collectTree(rows: ProcRow[], rootPid: number): ProcRow[] {
  const byParent = new Map<number, ProcRow[]>()
  for (const row of rows) {
    const list = byParent.get(row.ppid) ?? []
    list.push(row)
    byParent.set(row.ppid, list)
  }
  const result: ProcRow[] = []
  const rootRow = rows.find((r) => r.pid === rootPid)
  if (!rootRow) return result
  const queue = [rootRow]
  const seen = new Set<number>()
  while (queue.length) {
    const row = queue.pop()!
    if (seen.has(row.pid)) continue
    seen.add(row.pid)
    result.push(row)
    for (const child of byParent.get(row.pid) ?? []) queue.push(child)
  }
  return result
}

export async function sampleTree(rootPid: number): Promise<TreeSample | null> {
  let rows: ProcRow[]
  if (process.platform === 'linux') rows = listProcessesLinux()
  else if (process.platform === 'win32') rows = await listProcessesWindows()
  else rows = await listProcessesPs()
  const tree = collectTree(rows, rootPid)
  if (tree.length === 0) return null
  return {
    cpuMs: tree.reduce((a, r) => a + r.cpuMs, 0),
    rssBytes: tree.reduce((a, r) => a + r.rssBytes, 0),
    processes: tree.length,
  }
}

export function isAlive(pid: number): boolean {
  try {
    process.kill(pid, 0)
    return true
  } catch {
    return false
  }
}

/**
 * Kill an entire process tree with the given signal. On unix the child is
 * spawned detached (its own process group), so we signal the group; on
 * Windows unix signals are not deliverable — taskkill /T is used, with /F
 * only for SIGKILL (everything else maps to a graceful close request).
 */
export async function killTree(rootPid: number, signal: NodeJS.Signals = 'SIGTERM'): Promise<void> {
  if (process.platform === 'win32') {
    await new Promise<void>((resolve) => {
      const args = ['/pid', String(rootPid), '/t']
      if (signal === 'SIGKILL') args.push('/f')
      execFile('taskkill', args, { timeout: 10000 }, () => resolve())
    })
    return
  }
  let groupKilled = false
  try {
    process.kill(-rootPid, signal)
    groupKilled = true
  } catch {
    /* no such group (not detached or already gone) */
  }
  if (!groupKilled) {
    const rows = process.platform === 'linux' ? listProcessesLinux() : await listProcessesPs()
    const tree = collectTree(rows, rootPid)
    for (const row of tree.reverse()) {
      try {
        process.kill(row.pid, signal)
      } catch {
        /* already gone */
      }
    }
  }
}
