import type { Store, Collection } from '../lib/jsonstore.ts'
import type { QueryResult, Schedule, ScheduleEventName, ScheduleTask, ScheduleTrigger, ServerStatus } from '../types.ts'
import type { ServerManager } from '../servers/manager.ts'
import type { ServerInstance } from '../servers/instance.ts'
import type { BackupService } from './backups.ts'
import type { Notifier } from './notify.ts'
import { parseCron, nextRun } from '../lib/cron.ts'
import { renderTemplate } from '../lib/template.ts'
import { nowIso } from '../lib/util.ts'

const MAX_TASKS = 10
const HISTORY = 20

export const SCHEDULE_EVENTS: readonly ScheduleEventName[] = [
  'server.running',
  'server.offline',
  'server.crashed',
  'player.joined',
  'player.left',
]

/**
 * Event-triggered runs are rate-limited per schedule: a crash-loop or a
 * flapping player count must not queue dozens of task-chain executions.
 * At most one event run per schedule per window; a suppressed event is
 * dropped (not queued) — the next event after the window fires normally.
 * Cron and manual runs are unaffected.
 */
export const EVENT_MIN_INTERVAL_MS = 30_000

/** What started a run — becomes the `source` field of the run-log entry. */
export type ScheduleRunSource = 'cron' | 'manual' | { event: ScheduleEventName; user?: string }

/** Documents created before event triggers existed carry only `cron`. */
export function triggerOf(schedule: Schedule): ScheduleTrigger {
  return schedule.trigger ?? { type: 'cron', expr: schedule.cron }
}

/**
 * Player join/leave tracking per running server. Two honesty tiers, decided
 * per poll from what the query layer actually delivered:
 * - Name diff, only when the reported name sample covers everyone (Minecraft
 *   caps its sample, A2S caps at the packet size) both now AND last poll —
 *   a rotating partial sample would fabricate joins/leaves.
 * - Count delta otherwise: one anonymous joined/left event per direction per
 *   poll ({user} stays empty).
 */
export interface PlayerTrack {
  names: Set<string>
  /** True when `names` is a complete roster (empty room counts as complete). */
  namesValid: boolean
  count: number
}

export function diffPlayerEvents(
  prev: PlayerTrack,
  result: QueryResult,
): { events: { event: 'player.joined' | 'player.left'; user?: string }[]; next: PlayerTrack } {
  const names = Array.isArray(result.players)
    ? result.players.map((p) => p.name).filter((n): n is string => typeof n === 'string' && n.length > 0)
    : null
  const count = result.playersOnline ?? names?.length
  if (count === undefined) return { events: [], next: prev }
  const complete = names !== null && names.length >= count
  if (complete && prev.namesValid) {
    const current = new Set(names)
    const events: { event: 'player.joined' | 'player.left'; user?: string }[] = []
    for (const name of current) if (!prev.names.has(name)) events.push({ event: 'player.joined', user: name })
    for (const name of prev.names) if (!current.has(name)) events.push({ event: 'player.left', user: name })
    return { events, next: { names: current, namesValid: true, count } }
  }
  // Count tier — also the recovery path after a partial-sample poll: adopt the
  // roster silently so name diffing resumes next poll without a mass-join.
  const events: { event: 'player.joined' | 'player.left'; user?: string }[] = []
  if (count > prev.count) events.push({ event: 'player.joined' })
  else if (count < prev.count) events.push({ event: 'player.left' })
  return { events, next: { names: complete ? new Set(names) : new Set(), namesValid: complete, count } }
}

/** Local timestamp for the {time} template variable (ISO-style, no timezone suffix). */
function localTimestamp(d = new Date()): string {
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`
}

export class ScheduleService {
  readonly schedules: Collection<Schedule>
  private nextRuns = new Map<string, number>()
  private timer: ReturnType<typeof setInterval> | null = null
  private executing = new Map<string, Promise<void>>()
  private stopped = false
  private stopController = new AbortController()
  /** Debounce bookkeeping for event triggers (schedule id → last event-run ts). */
  private lastEventRun = new Map<string, number>()
  /** Player join/leave tracking, keyed by server id, alive while that server is running. */
  private playerTrack = new Map<string, PlayerTrack>()

  constructor(
    store: Store,
    private manager: ServerManager,
    private backups: BackupService,
    private notifier: Notifier,
    /** Rendered as the {node} template variable; null = the panel host ("local"). */
    private nodeName: string | null = null,
  ) {
    this.schedules = store.collection<Schedule>('schedules')
  }

  start() {
    if (this.timer) return
    this.stopped = false
    if (this.stopController.signal.aborted) this.stopController = new AbortController()
    for (const schedule of this.schedules.all()) this.computeNext(schedule)
    this.timer = setInterval(() => this.tick(), 20_000)
    this.timer.unref?.()
  }

  async stop(): Promise<void> {
    this.stopped = true
    this.stopController.abort()
    if (this.timer) clearInterval(this.timer)
    this.timer = null
    this.nextRuns.clear()
    this.lastEventRun.clear()
    this.playerTrack.clear()
    await Promise.allSettled([...this.executing.values()])
  }

  // ---------------------------------------------------------------------------
  // Event intake — fed by the local manager's hooks (app.ts). LOCAL servers
  // only by construction: remote mirrors stream through the node bridge and
  // never reach these hooks; fireEvent additionally asserts a local instance.
  // ---------------------------------------------------------------------------
  handleStatusChange(serverId: string, status: ServerStatus, prev: ServerStatus): void {
    if (this.stopped) return
    if (status === 'running') {
      // (Re)baseline player tracking: joins are diffed against an empty room
      // from the moment the server reports running.
      this.playerTrack.set(serverId, { names: new Set(), namesValid: true, count: 0 })
      this.fireEvent(serverId, 'server.running')
      return
    }
    // Leaving `running` drops the roster WITHOUT player.left events — the
    // server going down is its own event, not a wave of leaves.
    this.playerTrack.delete(serverId)
    if (status === 'crashed') this.fireEvent(serverId, 'server.crashed')
    // `offline` only counts as "server stopped" when a workload was actually
    // up — install completion and crashed→offline resets also land here.
    else if (status === 'offline' && (prev === 'running' || prev === 'stopping' || prev === 'starting'))
      this.fireEvent(serverId, 'server.offline')
  }

  handleQueryResult(serverId: string, result: QueryResult): void {
    if (this.stopped || !result.online) return
    const track = this.playerTrack.get(serverId)
    if (!track) return
    const { events, next } = diffPlayerEvents(track, result)
    this.playerTrack.set(serverId, next)
    for (const e of events) this.fireEvent(serverId, e.event, { user: e.user })
  }

  private fireEvent(serverId: string, event: ScheduleEventName, ctx: { user?: string } = {}): void {
    if (this.stopped) return
    // Local-only contract, asserted: only servers with a local instance may
    // execute task chains — a remote mirror id never matches.
    if (!this.manager.instances.has(serverId)) return
    const now = Date.now()
    for (const schedule of this.schedules.filter((s) => s.serverId === serverId && s.enabled)) {
      const trigger = triggerOf(schedule)
      if (trigger.type !== 'event' || trigger.event !== event) continue
      const last = this.lastEventRun.get(schedule.id) ?? 0
      if (now - last < EVENT_MIN_INTERVAL_MS) continue
      this.lastEventRun.set(schedule.id, now)
      void this.execute(schedule.id, { event, user: ctx.user })
    }
  }

  // ---------------------------------------------------------------------------
  // Cron engine
  // ---------------------------------------------------------------------------
  private computeNext(schedule: Schedule) {
    const trigger = triggerOf(schedule)
    if (trigger.type !== 'cron') {
      this.nextRuns.delete(schedule.id)
      return
    }
    try {
      const next = nextRun(parseCron(trigger.expr))
      if (next) this.nextRuns.set(schedule.id, next.getTime())
      else this.nextRuns.delete(schedule.id)
    } catch {
      this.nextRuns.delete(schedule.id)
    }
  }

  nextRunOf(id: string): number | null {
    return this.nextRuns.get(id) ?? null
  }

  private tick() {
    const now = Date.now()
    for (const schedule of this.schedules.all()) {
      if (!schedule.enabled) continue
      if (triggerOf(schedule).type !== 'cron') continue
      const due = this.nextRuns.get(schedule.id)
      if (due === undefined) {
        this.computeNext(schedule)
        continue
      }
      if (now >= due) {
        this.computeNext(schedule)
        void this.execute(schedule.id, 'cron')
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------
  validateTasks(tasks: unknown): { tasks: ScheduleTask[]; problems: string[] } {
    const problems: string[] = []
    const out: ScheduleTask[] = []
    if (!Array.isArray(tasks) || tasks.length === 0) return { tasks: [], problems: ['at least one task required'] }
    if (tasks.length > MAX_TASKS) return { tasks: [], problems: [`too many tasks (max ${MAX_TASKS})`] }
    for (const [i, t] of tasks.entries()) {
      if (typeof t !== 'object' || t === null) {
        problems.push(`task ${i + 1}: invalid`)
        continue
      }
      const task = t as Record<string, unknown>
      if (task.type === 'power' && ['start', 'stop', 'restart', 'kill'].includes(task.action as string)) {
        out.push({ type: 'power', action: task.action as 'start' })
      } else if (task.type === 'command' && typeof task.command === 'string' && task.command.trim()) {
        out.push({ type: 'command', command: String(task.command).slice(0, 500) })
      } else if (task.type === 'backup') {
        out.push({ type: 'backup', note: String(task.note ?? 'scheduled').slice(0, 100) })
      } else if (task.type === 'wait') {
        const seconds = Math.max(1, Math.min(300, Number(task.seconds)))
        if (!Number.isFinite(seconds)) problems.push(`task ${i + 1}: invalid wait seconds`)
        else out.push({ type: 'wait', seconds })
      } else {
        problems.push(`task ${i + 1}: unknown type`)
      }
    }
    return { tasks: out, problems }
  }

  /** Trigger union from untrusted input; a plain `cron` string stays valid (pre-trigger API payload). */
  private validateTrigger(input: { trigger?: unknown; cron?: unknown }): { trigger?: ScheduleTrigger; problems: string[] } {
    if (input.trigger !== undefined && input.trigger !== null) {
      if (typeof input.trigger !== 'object') return { problems: ['trigger: must be an object'] }
      const raw = input.trigger as Record<string, unknown>
      if (raw.type === 'cron') {
        const expr = String(raw.expr ?? '').trim()
        try {
          parseCron(expr)
        } catch (err) {
          return { problems: [`cron: ${(err as Error).message}`] }
        }
        return { trigger: { type: 'cron', expr }, problems: [] }
      }
      if (raw.type === 'event') {
        const event = String(raw.event ?? '')
        if (!SCHEDULE_EVENTS.includes(event as ScheduleEventName))
          return { problems: [`trigger: unknown event "${event.slice(0, 40)}"`] }
        return { trigger: { type: 'event', event: event as ScheduleEventName }, problems: [] }
      }
      return { problems: [`trigger: unknown type "${String(raw.type).slice(0, 40)}"`] }
    }
    const expr = String(input.cron ?? '').trim()
    try {
      parseCron(expr)
    } catch (err) {
      return { problems: [`cron: ${(err as Error).message}`] }
    }
    return { trigger: { type: 'cron', expr }, problems: [] }
  }

  // ---------------------------------------------------------------------------
  // CRUD
  // ---------------------------------------------------------------------------
  create(input: {
    serverId: string
    name: string
    cron?: string
    trigger?: unknown
    tasks: unknown
    enabled?: boolean
    onlyIfRunning?: boolean
  }): {
    schedule?: Schedule
    problems: string[]
  } {
    const problems: string[] = []
    const name = String(input.name ?? '').trim()
    if (!name || name.length > 60) problems.push('name must be 1-60 characters')
    const { trigger, problems: triggerProblems } = this.validateTrigger(input)
    problems.push(...triggerProblems)
    const { tasks, problems: taskProblems } = this.validateTasks(input.tasks)
    problems.push(...taskProblems)
    if (problems.length > 0 || !trigger) return { problems }
    const schedule = this.schedules.insert({
      serverId: input.serverId,
      name,
      cron: trigger.type === 'cron' ? trigger.expr : '',
      trigger,
      enabled: input.enabled !== false,
      onlyIfRunning: Boolean(input.onlyIfRunning),
      tasks,
      lastRuns: [],
      createdAt: nowIso(),
    })
    this.computeNext(schedule)
    return { schedule, problems: [] }
  }

  update(
    id: string,
    input: Partial<{ name: string; cron: string; trigger: unknown; tasks: unknown; enabled: boolean; onlyIfRunning: boolean }>,
  ): { schedule?: Schedule; problems: string[] } {
    const existing = this.schedules.get(id)
    if (!existing) return { problems: ['schedule not found'] }
    const problems: string[] = []
    const patch: Partial<Schedule> = {}
    if (input.name !== undefined) {
      const name = String(input.name).trim()
      if (!name || name.length > 60) problems.push('name must be 1-60 characters')
      else patch.name = name
    }
    if (input.trigger !== undefined || input.cron !== undefined) {
      const { trigger, problems: triggerProblems } = this.validateTrigger(input)
      problems.push(...triggerProblems)
      if (trigger) {
        patch.trigger = trigger
        patch.cron = trigger.type === 'cron' ? trigger.expr : ''
      }
    }
    if (input.tasks !== undefined) {
      const { tasks, problems: taskProblems } = this.validateTasks(input.tasks)
      problems.push(...taskProblems)
      if (taskProblems.length === 0) patch.tasks = tasks
    }
    if (input.enabled !== undefined) patch.enabled = Boolean(input.enabled)
    if (input.onlyIfRunning !== undefined) patch.onlyIfRunning = Boolean(input.onlyIfRunning)
    if (problems.length > 0) return { problems }
    const schedule = this.schedules.update(id, patch)!
    this.computeNext(schedule)
    return { schedule, problems: [] }
  }

  remove(id: string): boolean {
    this.nextRuns.delete(id)
    this.lastEventRun.delete(id)
    return this.schedules.remove(id)
  }

  removeAllForServer(serverId: string): void {
    for (const s of this.schedules.filter((s) => s.serverId === serverId)) this.remove(s.id)
  }

  // ---------------------------------------------------------------------------
  // Task runner
  // ---------------------------------------------------------------------------
  execute(id: string, source: ScheduleRunSource): Promise<void> {
    if (this.executing.has(id)) return Promise.resolve()
    const schedule = this.schedules.get(id)
    if (!schedule) return Promise.resolve()
    const execution = this.executeSchedule(schedule, source).finally(() => {
      this.executing.delete(id)
    })
    this.executing.set(id, execution)
    return execution
  }

  private async wait(ms: number): Promise<void> {
    const signal = this.stopController.signal
    if (signal.aborted) throw new Error('panel is shutting down')
    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => {
        signal.removeEventListener('abort', onAbort)
        resolve()
      }, ms)
      timer.unref?.()
      const onAbort = () => {
        clearTimeout(timer)
        reject(new Error('panel is shutting down'))
      }
      signal.addEventListener('abort', onAbort, { once: true })
    })
  }

  /**
   * Template variables for command/backup tasks, resolved when the TASK runs
   * (after earlier power/wait tasks) — {state} and {players} reflect what the
   * command will actually see, not the state at trigger time.
   */
  private templateVars(inst: ServerInstance, source: ScheduleRunSource): Record<string, string> {
    const query = inst.lastQuery
    return {
      server: inst.server.name,
      state: inst.status,
      players: String(query?.playersOnline ?? query?.players?.length ?? 0),
      maxPlayers: String(query?.playersMax ?? 0),
      user: typeof source === 'object' ? (source.user ?? '') : '',
      time: localTimestamp(),
      node: this.nodeName ?? 'local',
    }
  }

  private async executeSchedule(schedule: Schedule, source: ScheduleRunSource): Promise<void> {
    const id = schedule.id
    const manual = source === 'manual'
    const sourceLabel = typeof source === 'string' ? source : `event:${source.event}`
    const record = (ok: boolean, message: string) => {
      const runs = [{ ts: nowIso(), ok, message, source: sourceLabel }, ...(this.schedules.get(id)?.lastRuns ?? [])].slice(0, HISTORY)
      this.schedules.update(id, { lastRuns: runs })
    }
    try {
      const inst = this.manager.instances.get(schedule.serverId)
      if (!inst) throw new Error('server no longer exists')
      if (schedule.onlyIfRunning && inst.status !== 'running') {
        record(true, manual ? 'skipped: server not running' : 'skipped (server not running)')
        return
      }
      const startedSuffix = manual ? ' (manual run)' : typeof source === 'object' ? ` (event: ${source.event})` : ''
      inst.pushLine('system', `Schedule "${schedule.name}" started${startedSuffix}.`)
      const done: string[] = []
      for (const task of schedule.tasks) {
        // A long-running schedule (e.g. wait → start) must not act after the
        // panel began shutting down.
        if (this.stopped) throw new Error('panel is shutting down')
        switch (task.type) {
          case 'power':
            await this.manager.power(schedule.serverId, task.action)
            done.push(`power:${task.action}`)
            break
          case 'command':
            this.manager.sendCommand(schedule.serverId, renderTemplate(task.command, this.templateVars(inst, source)))
            done.push('command')
            break
          case 'backup': {
            const note = renderTemplate(task.note ?? 'scheduled', this.templateVars(inst, source)).slice(0, 100)
            const backup = await this.backups.create(schedule.serverId, note, { auto: true })
            // Same event kind + payload shape as the manual route; no user
            // acted (matching the `system` actor convention of backup.pruned),
            // so the schedule name carries the "who" — in the message for
            // Discord and as an additive data field for webhook receivers.
            const server = this.manager.servers.get(schedule.serverId)
            if (server) {
              this.notifier.notify('backup', 'Backup created', `**${server.name}** — ${backup.fileName} (schedule "${schedule.name}")`, {
                server: { id: server.id, name: server.name, blueprintId: server.blueprintId },
                data: { fileName: backup.fileName, schedule: schedule.name },
              })
            }
            done.push('backup')
            break
          }
          case 'wait':
            await this.wait(task.seconds * 1000)
            done.push(`wait:${task.seconds}s`)
            break
        }
      }
      record(true, `ok: ${done.join(', ')}`)
      inst.pushLine('system', `Schedule "${schedule.name}" finished.`)
    } catch (err) {
      record(false, (err as Error).message)
    }
  }
}
