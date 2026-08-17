/**
 * Host-level metrics: CPU (via os.cpus() time deltas — cross-platform),
 * memory, disk (fs.statfs on the data dir) and load average.
 */
import os from 'node:os'
import fs from 'node:fs'
import { RingBuffer } from '../lib/ringbuffer.ts'

export interface HostSnapshot {
  ts: number
  cpuPct: number
  memUsedBytes: number
  memTotalBytes: number
  diskUsedBytes: number
  diskTotalBytes: number
  load1: number
  platform: string
}

const BUFFER = 720 // 1h at 5s

export class MetricsService {
  readonly history = new RingBuffer<HostSnapshot>(BUFFER)
  private prevCpu: { idle: number; total: number } | null = null
  private timer: ReturnType<typeof setInterval> | null = null
  private listeners = new Set<(snap: HostSnapshot) => void>()
  private sampling = false

  constructor(private dataDir: string) {}

  onSample(fn: (snap: HostSnapshot) => void): () => void {
    this.listeners.add(fn)
    return () => this.listeners.delete(fn)
  }

  private cpuTimes(): { idle: number; total: number } {
    let idle = 0
    let total = 0
    for (const cpu of os.cpus()) {
      idle += cpu.times.idle
      total += cpu.times.user + cpu.times.nice + cpu.times.sys + cpu.times.idle + cpu.times.irq
    }
    return { idle, total }
  }

  async sample(): Promise<HostSnapshot> {
    const cpu = this.cpuTimes()
    let cpuPct = 0
    if (this.prevCpu) {
      const totalDelta = cpu.total - this.prevCpu.total
      const idleDelta = cpu.idle - this.prevCpu.idle
      if (totalDelta > 0) cpuPct = Math.max(0, Math.min(100, ((totalDelta - idleDelta) / totalDelta) * 100))
    }
    this.prevCpu = cpu

    let diskUsed = 0
    let diskTotal = 0
    try {
      const stat = await fs.promises.statfs(this.dataDir)
      diskTotal = stat.blocks * stat.bsize
      diskUsed = diskTotal - stat.bfree * stat.bsize
    } catch {
      /* statfs unavailable */
    }

    const snap: HostSnapshot = {
      ts: Date.now(),
      cpuPct: Math.round(cpuPct * 10) / 10,
      memUsedBytes: os.totalmem() - os.freemem(),
      memTotalBytes: os.totalmem(),
      diskUsedBytes: diskUsed,
      diskTotalBytes: diskTotal,
      load1: os.loadavg()[0],
      platform: `${process.platform} ${os.release()}`,
    }
    this.history.push(snap)
    for (const fn of this.listeners) {
      try {
        fn(snap)
      } catch (err) {
        console.error('[metrics] sample listener failed:', err)
      }
    }
    return snap
  }

  start() {
    if (this.timer) return
    const run = async () => {
      if (this.sampling) return
      this.sampling = true
      try {
        await this.sample()
      } catch (err) {
        // Timer callbacks have no caller to observe a rejection.
        console.error('[metrics] host sample failed:', err)
      } finally {
        this.sampling = false
      }
    }
    void run()
    this.timer = setInterval(() => void run(), 5000)
    this.timer.unref?.()
  }

  stop() {
    if (this.timer) clearInterval(this.timer)
    this.timer = null
  }

  latest(): HostSnapshot | null {
    return this.history.last ?? null
  }
}
