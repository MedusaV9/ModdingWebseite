import { useCallback, useEffect, useRef, useState } from 'react'
import { Braces, CalendarClock, Check, Play, Plus, Trash2, X, Zap } from 'lucide-react'
import { api, ApiError } from '../../api/client.ts'
import type { ScheduleEventName, ScheduleInfo, ScheduleTask, ScheduleTrigger } from '../../api/types.ts'
import { useServer } from './ServerDetail.tsx'
import { useT } from '../../i18n/index.tsx'
import { useToast } from '../../state/ToastContext.tsx'
import { Badge, Button, Card, EmptyState, Field, IconButton, Input, SegmentedControl, Select, Spinner, Toggle } from '../../components/ui.tsx'
import { Modal, ConfirmModal } from '../../components/Modal.tsx'
import { formatDateTime, timeAgo } from '../../lib/format.ts'

const PRESETS = [
  { key: 'schedules.preset.daily4', cron: '0 4 * * *' },
  { key: 'schedules.preset.hourly', cron: '0 * * * *' },
  { key: 'schedules.preset.every15', cron: '*/15 * * * *' },
  { key: 'schedules.preset.weekly', cron: '0 5 * * 0' },
] as const

// Human labels for power actions in the task summary line (typed key map —
// `t` only accepts literal I18n keys).
const POWER_LABEL_KEY = {
  start: 'console.start',
  stop: 'console.stop',
  restart: 'console.restart',
  kill: 'console.kill',
} as const

const EVENT_LABEL_KEY = {
  'server.running': 'schedules.event.server.running',
  'server.offline': 'schedules.event.server.offline',
  'server.crashed': 'schedules.event.server.crashed',
  'player.joined': 'schedules.event.player.joined',
  'player.left': 'schedules.event.player.left',
} as const

const EVENT_NAMES = Object.keys(EVENT_LABEL_KEY) as ScheduleEventName[]

/** Template placeholders for command/backup tasks, rendered server-side at run time. */
const TEMPLATE_VARS = [
  { token: '{server}', key: 'schedules.var.server' },
  { token: '{state}', key: 'schedules.var.state' },
  { token: '{players}', key: 'schedules.var.players' },
  { token: '{maxPlayers}', key: 'schedules.var.maxPlayers' },
  { token: '{user}', key: 'schedules.var.user' },
  { token: '{time}', key: 'schedules.var.time' },
  { token: '{node}', key: 'schedules.var.node' },
] as const

/** Schedules stored before event triggers existed carry only `cron`. */
const triggerOf = (schedule: ScheduleInfo): ScheduleTrigger => schedule.trigger ?? { type: 'cron', expr: schedule.cron }

function TaskEditor({ task, onChange, onRemove }: { task: ScheduleTask; onChange: (t: ScheduleTask) => void; onRemove: () => void }) {
  const t = useT()
  const [varsOpen, setVarsOpen] = useState(false)
  // The Input primitive types plain InputHTMLAttributes (no ref prop) — reach
  // the element through its wrapper instead of changing the primitive.
  const commandWrapRef = useRef<HTMLDivElement | null>(null)

  const insertVar = (token: string) => {
    if (task.type !== 'command') return
    const el = commandWrapRef.current?.querySelector('input')
    const start = el?.selectionStart ?? task.command.length
    const end = el?.selectionEnd ?? start
    onChange({ type: 'command', command: task.command.slice(0, start) + token + task.command.slice(end) })
    // Restore focus + caret after the controlled re-render.
    requestAnimationFrame(() => {
      el?.focus()
      el?.setSelectionRange(start + token.length, start + token.length)
    })
  }

  return (
    // Width overrides via className are unreliable on Input/Select (base
    // w-full wins by stylesheet order) — size them with wrapper divs instead.
    // The remove ✕ lives in a fixed top-right slot (pr-10 reserves its lane)
    // so all four task types share one silhouette.
    <div className="glass-subtle relative flex flex-wrap items-center gap-2 rounded-xl py-2 pl-3 pr-10">
      <div className="w-40 shrink-0">
        <Select
          value={task.type}
          onChange={(e) => {
            const type = e.target.value as ScheduleTask['type']
            if (type === 'power') onChange({ type, action: 'restart' })
            else if (type === 'command') onChange({ type, command: '' })
            else if (type === 'backup') onChange({ type, note: '' })
            else onChange({ type: 'wait', seconds: 10 })
          }}
        >
          <option value="power">{t('schedules.task.power')}</option>
          <option value="command">{t('schedules.task.command')}</option>
          <option value="backup">{t('schedules.task.backup')}</option>
          <option value="wait">{t('schedules.task.wait')}</option>
        </Select>
      </div>
      {task.type === 'power' && (
        <div className="w-32 shrink-0">
          <Select value={task.action} onChange={(e) => onChange({ type: 'power', action: e.target.value as 'start' })}>
            <option value="start">{t('console.start')}</option>
            <option value="stop">{t('console.stop')}</option>
            <option value="restart">{t('console.restart')}</option>
            <option value="kill">{t('console.kill')}</option>
          </Select>
        </div>
      )}
      {task.type === 'command' && (
        <>
          <div ref={commandWrapRef} className="min-w-40 flex-1">
            <Input
              value={task.command}
              onChange={(e) => onChange({ type: 'command', command: e.target.value })}
              placeholder={t('schedules.commandPh')}
              className="font-mono text-xs"
            />
          </div>
          <IconButton
            size="sm"
            label={t('schedules.variables')}
            aria-expanded={varsOpen}
            onClick={() => setVarsOpen((v) => !v)}
            className={varsOpen ? 'bg-accent/15 text-accent' : undefined}
          >
            <Braces size={13} />
          </IconButton>
          {varsOpen && (
            <div className="scale-in basis-full rounded-xl bg-elevated/60 p-2.5">
              <span className="microlabel">{t('schedules.variables')}</span>
              <div className="mt-1.5 grid gap-0.5 sm:grid-cols-2">
                {TEMPLATE_VARS.map((v) => (
                  <button
                    key={v.token}
                    type="button"
                    onClick={() => insertVar(v.token)}
                    className="pressable flex items-baseline gap-2 rounded-lg px-2 py-1 text-left hover:bg-accent/10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40"
                  >
                    <code className="shrink-0 font-mono text-xs text-accent">{v.token}</code>
                    <span className="text-[0.6875rem] leading-snug text-muted">{t(v.key)}</span>
                  </button>
                ))}
              </div>
              <p className="mt-1.5 text-[0.6875rem] leading-snug text-muted/80">{t('schedules.varHint')}</p>
            </div>
          )}
        </>
      )}
      {task.type === 'backup' && (
        <div className="min-w-40 flex-1">
          <Input
            value={task.note ?? ''}
            onChange={(e) => onChange({ type: 'backup', note: e.target.value })}
            placeholder={t('backups.notePh')}
          />
        </div>
      )}
      {task.type === 'wait' && (
        <div className="w-24 shrink-0">
          <Input
            type="number"
            value={String(task.seconds)}
            min={1}
            max={3600}
            onChange={(e) => onChange({ type: 'wait', seconds: Number(e.target.value) || 1 })}
          />
        </div>
      )}
      <button
        onClick={onRemove}
        title={t('common.delete')}
        aria-label={t('common.delete')}
        className="pressable absolute right-2 top-2 rounded-lg p-1.5 text-muted hover:bg-danger/20 hover:text-danger focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40"
      >
        <X size={14} />
      </button>
    </div>
  )
}

export function SchedulesTab() {
  const { server } = useServer()
  const t = useT()
  const toast = useToast()
  const [schedules, setSchedules] = useState<ScheduleInfo[] | null>(null)
  const [editorOpen, setEditorOpen] = useState(false)
  const [editing, setEditing] = useState<ScheduleInfo | null>(null)
  const [name, setName] = useState('')
  const [triggerType, setTriggerType] = useState<'cron' | 'event'>('cron')
  const [eventName, setEventName] = useState<ScheduleEventName>('server.running')
  const [cron, setCron] = useState('0 4 * * *')
  const [enabled, setEnabled] = useState(true)
  const [onlyIfRunning, setOnlyIfRunning] = useState(false)
  const [tasks, setTasks] = useState<ScheduleTask[]>([{ type: 'power', action: 'restart' }])
  const [preview, setPreview] = useState<{ valid: boolean; nextRuns: number[] } | null>(null)
  const [saving, setSaving] = useState(false)
  const [deleteTarget, setDeleteTarget] = useState<ScheduleInfo | null>(null)
  const [busy, setBusy] = useState(false)
  const [initialDraft, setInitialDraft] = useState('')
  const reloadTimers = useRef(new Set<ReturnType<typeof setTimeout>>())

  // Player events need the query layer — without a query block the panel never
  // learns who is online, so those triggers would silently never fire.
  const hasQuery = Boolean(server.blueprint?.query && server.blueprint.query.type !== 'none')

  const draftOf = (n: string, tt: 'cron' | 'event', ev: ScheduleEventName, c: string, e: boolean, o: boolean, ts: ScheduleTask[]) =>
    JSON.stringify({ n, tt, ev, c, e, o, ts })
  const editorDirty = editorOpen && draftOf(name, triggerType, eventName, cron, enabled, onlyIfRunning, tasks) !== initialDraft

  const load = useCallback(async () => {
    try {
      const res = await api.get<{ schedules: ScheduleInfo[] }>(`/api/servers/${server.id}/schedules`)
      setSchedules(res.schedules)
    } catch (err) {
      toast('error', (err as Error).message)
    }
  }, [server.id, toast])

  useEffect(() => {
    void load()
  }, [load])

  useEffect(
    () => () => {
      for (const timer of reloadTimers.current) clearTimeout(timer)
      reloadTimers.current.clear()
    },
    [],
  )

  // Live cron preview
  useEffect(() => {
    const handle = setTimeout(() => {
      void api
        .post<{ valid: boolean; nextRuns: number[] }>(`/api/schedules/preview`, { cron })
        .then(setPreview)
        .catch(() => setPreview(null))
    }, 300)
    return () => clearTimeout(handle)
  }, [cron])

  const openCreate = () => {
    setEditing(null)
    setName('')
    setTriggerType('cron')
    setEventName('server.running')
    setCron('0 4 * * *')
    setEnabled(true)
    setOnlyIfRunning(false)
    const initialTasks: ScheduleTask[] = [{ type: 'power', action: 'restart' }]
    setTasks(initialTasks)
    setInitialDraft(draftOf('', 'cron', 'server.running', '0 4 * * *', true, false, initialTasks))
    setEditorOpen(true)
  }

  const openEdit = (schedule: ScheduleInfo) => {
    const trigger = triggerOf(schedule)
    const event = trigger.type === 'event' ? trigger.event : 'server.running'
    const expr = trigger.type === 'cron' ? trigger.expr : '0 4 * * *'
    setEditing(schedule)
    setName(schedule.name)
    setTriggerType(trigger.type)
    setEventName(event)
    setCron(expr)
    setEnabled(schedule.enabled)
    setOnlyIfRunning(schedule.onlyIfRunning)
    setTasks(schedule.tasks)
    setInitialDraft(draftOf(schedule.name, trigger.type, event, expr, schedule.enabled, schedule.onlyIfRunning, schedule.tasks))
    setEditorOpen(true)
  }

  const save = async () => {
    // Validate on click with visible feedback instead of a silently
    // disabled button (users cannot tell WHY a disabled button is dead).
    if (!name.trim()) {
      toast('error', t('common.nameRequired'))
      return
    }
    if (triggerType === 'cron' && preview && !preview.valid) {
      toast('error', t('schedules.invalidCron'))
      return
    }
    if (tasks.length === 0) {
      toast('error', t('schedules.tasksRequired'))
      return
    }
    setSaving(true)
    try {
      const trigger: ScheduleTrigger = triggerType === 'cron' ? { type: 'cron', expr: cron } : { type: 'event', event: eventName }
      const body = { name: name.trim(), trigger, tasks, enabled, onlyIfRunning }
      if (editing) await api.patch(`/api/servers/${server.id}/schedules/${editing.id}`, body)
      else await api.post(`/api/servers/${server.id}/schedules`, body)
      setEditorOpen(false)
      await load()
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    } finally {
      setSaving(false)
    }
  }

  const runNow = async (schedule: ScheduleInfo) => {
    try {
      await api.post(`/api/servers/${server.id}/schedules/${schedule.id}/run`)
      toast('success', t('schedules.runNowToast', { name: schedule.name }))
      const timer = setTimeout(() => {
        reloadTimers.current.delete(timer)
        void load()
      }, 1500)
      reloadTimers.current.add(timer)
    } catch (err) {
      toast('error', (err as Error).message)
    }
  }

  const toggleEnabled = async (schedule: ScheduleInfo) => {
    try {
      await api.patch(`/api/servers/${server.id}/schedules/${schedule.id}`, { enabled: !schedule.enabled })
      await load()
    } catch (err) {
      toast('error', (err as Error).message)
    }
  }

  const remove = async () => {
    if (!deleteTarget) return
    setBusy(true)
    try {
      await api.del(`/api/servers/${server.id}/schedules/${deleteTarget.id}`)
      setDeleteTarget(null)
      await load()
    } catch (err) {
      toast('error', (err as Error).message)
    } finally {
      setBusy(false)
    }
  }

  const describeTask = (task: ScheduleTask): string => {
    if (task.type === 'power') return `${t('schedules.task.power')}: ${t(POWER_LABEL_KEY[task.action])}`
    if (task.type === 'command') return `${t('schedules.task.command')}: ${task.command.slice(0, 30)}`
    if (task.type === 'backup') return t('schedules.task.backup')
    // Summary-only label — the editor label "Wait (seconds)" would repeat the
    // unit ("Wait (seconds): 30s"), so the meta line uses "Wait: 30 s".
    return t('schedules.summary.wait', { s: task.seconds })
  }

  // The runner records machine tokens ("ok: command, wait:30s, power:restart").
  // Present them through the same labels as the task chain above; anything
  // unrecognized (error/skip messages) stays verbatim. Callers keep the raw
  // message in `title`.
  const describeRun = (message: string): string => {
    const ok = /^ok:\s*(.+)$/.exec(message)
    if (!ok) return message
    return ok[1]
      .split(',')
      .map((token) => {
        const part = token.trim()
        if (part === 'command') return t('schedules.task.command')
        if (part === 'backup') return t('schedules.task.backup')
        const power = /^power:(start|stop|restart|kill)$/.exec(part)
        if (power) return `${t('schedules.task.power')}: ${t(POWER_LABEL_KEY[power[1] as keyof typeof POWER_LABEL_KEY])}`
        const wait = /^wait:(\d+)s$/.exec(part)
        if (wait) return t('schedules.summary.wait', { s: wait[1] })
        return part
      })
      .filter(Boolean)
      .join(' → ')
  }

  // Run-log source tag: 'cron' | 'manual' | 'event:<name>' (absent on old records).
  const describeSource = (source: string): string => {
    if (source === 'cron') return t('schedules.source.cron')
    if (source === 'manual') return t('schedules.source.manual')
    const event = source.startsWith('event:') ? source.slice(6) : null
    if (event && event in EVENT_LABEL_KEY) return t(EVENT_LABEL_KEY[event as ScheduleEventName])
    return source
  }

  return (
    <div className="space-y-3">
      <div className="flex justify-end">
        <Button variant="primary" onClick={openCreate}>
          <Plus size={14} />
          {t('schedules.create')}
        </Button>
      </div>

      <Card className="overflow-hidden">
        {!schedules && <Spinner />}
        {schedules && schedules.length === 0 && <EmptyState icon={<CalendarClock size={36} />} title={t('schedules.empty')} />}
        {schedules && schedules.length > 0 && (
          <div className="divide-y divide-line/50">
            {schedules.map((schedule) => (
              <div key={schedule.id} className="px-4 py-3 transition-colors hover:bg-elevated/40">
                <div className="flex flex-wrap items-center gap-3">
                  <Toggle
                    checked={schedule.enabled}
                    onChange={() => void toggleEnabled(schedule)}
                    aria-label={`${t('common.enabled')}: ${schedule.name}`}
                  />
                  <button
                    onClick={() => openEdit(schedule)}
                    className="min-w-0 flex-1 basis-52 rounded-lg text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40"
                  >
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="truncate font-semibold">{schedule.name}</span>
                      {triggerOf(schedule).type === 'event' ? (
                        <Badge className="border-accent/30 bg-accent/10 text-accent">
                          <Zap size={10} />
                          {t(EVENT_LABEL_KEY[(triggerOf(schedule) as { event: ScheduleEventName }).event])}
                        </Badge>
                      ) : (
                        <Badge className="tabular font-mono">{schedule.cron}</Badge>
                      )}
                      {schedule.onlyIfRunning && <Badge className="border-accent/30 bg-accent/10 text-accent">{t('schedules.onlyIfRunning')}</Badge>}
                    </div>
                    <div className="mt-0.5 text-xs text-muted">
                      {triggerOf(schedule).type === 'event'
                        ? t('schedules.runsOnEvent')
                        : `${t('schedules.nextRun')}: ${schedule.enabled && schedule.nextRunAt ? formatDateTime(schedule.nextRunAt) : '—'}`}
                      <span className="ml-2 text-muted/70">{schedule.tasks.map(describeTask).join(' → ')}</span>
                    </div>
                  </button>
                  <div className="flex items-center gap-1">
                    <Button size="sm" variant="secondary" onClick={() => void runNow(schedule)}>
                      <Play size={12} />
                      {t('schedules.runNow')}
                    </Button>
                    <IconButton size="sm" onClick={() => setDeleteTarget(schedule)} label={t('common.delete')} className="hover:bg-danger/15 hover:text-danger">
                      <Trash2 size={13} className="text-danger/80" />
                    </IconButton>
                  </div>
                </div>
                {schedule.lastRuns.length > 0 && (
                  <div className="mt-2 flex flex-wrap gap-2 pl-12 text-[0.6875rem] text-muted">
                    <span className="font-semibold">{t('schedules.lastRuns')}:</span>
                    {schedule.lastRuns.slice(-3).map((run, i) => (
                      <span key={i} title={run.message} className={run.ok ? 'text-success/90' : 'text-danger/90'}>
                        {run.ok ? <Check size={10} className="mr-0.5 inline" /> : <X size={10} className="mr-0.5 inline" />}
                        {timeAgo(run.ts, t)}
                        {run.source ? ` · ${describeSource(run.source)}` : ''} — {describeRun(run.message).slice(0, 60)}
                      </span>
                    ))}
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </Card>

      {/* Editor */}
      <Modal
        open={editorOpen}
        onClose={() => setEditorOpen(false)}
        title={editing ? `${t('common.edit')}: ${editing.name}` : t('schedules.create')}
        wide
        dirty={editorDirty}
        footer={
          <>
            <Button variant="ghost" onClick={() => setEditorOpen(false)}>
              {t('common.cancel')}
            </Button>
            <Button variant="primary" onClick={() => void save()} loading={saving}>
              {t('common.save')}
            </Button>
          </>
        }
      >
        <div className="space-y-4">
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label={t('common.name')}>
              <Input value={name} onChange={(e) => setName(e.target.value)} autoFocus placeholder={t('schedules.namePh')} maxLength={60} />
            </Field>
            <Field label={t('schedules.when')}>
              <SegmentedControl
                size="sm"
                aria-label={t('schedules.when')}
                options={[
                  { value: 'cron', label: t('schedules.trigger.cron'), icon: <CalendarClock size={13} /> },
                  { value: 'event', label: t('schedules.trigger.event'), icon: <Zap size={13} /> },
                ]}
                value={triggerType}
                onChange={setTriggerType}
              />
            </Field>
          </div>

          {triggerType === 'cron' && (
            <>
              <Field
                label={t('schedules.cron')}
                hint={t('schedules.cronHint')}
                error={preview?.valid === false ? t('schedules.invalidCron') : undefined}
              >
                <Input value={cron} onChange={(e) => setCron(e.target.value)} className="font-mono" />
              </Field>

              <div className="flex flex-wrap items-center gap-1.5">
                <span className="microlabel">{t('schedules.presets')}:</span>
                {PRESETS.map((preset) => (
                  <button
                    key={preset.cron}
                    onClick={() => setCron(preset.cron)}
                    className="glass-subtle pressable rounded-full px-2.5 py-1 text-xs text-muted hover:border-accent/50 hover:text-accent focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40"
                  >
                    {t(preset.key)}
                  </button>
                ))}
              </div>

              {preview?.valid && preview.nextRuns.length > 0 && (
                <div className="glass-subtle tabular rounded-xl px-3.5 py-2.5 text-xs text-muted">
                  {t('schedules.nextRun')}: {preview.nextRuns.slice(0, 3).map((ts) => formatDateTime(ts)).join(' · ')}
                </div>
              )}
            </>
          )}

          {triggerType === 'event' && (
            <Field
              label={t('schedules.trigger.event')}
              hint={eventName.startsWith('player.') ? t('schedules.eventHint.player') : t('schedules.eventHint.status')}
            >
              <Select value={eventName} onChange={(e) => setEventName(e.target.value as ScheduleEventName)}>
                {EVENT_NAMES.map((event) => (
                  <option key={event} value={event} disabled={event.startsWith('player.') && !hasQuery}>
                    {t(EVENT_LABEL_KEY[event])}
                    {event.startsWith('player.') && !hasQuery ? ` — ${t('schedules.eventNoQuery')}` : ''}
                  </option>
                ))}
              </Select>
            </Field>
          )}

          <div className="flex gap-5">
            <Toggle checked={enabled} onChange={setEnabled} label={t('common.enabled')} />
            <Toggle checked={onlyIfRunning} onChange={setOnlyIfRunning} label={t('schedules.onlyIfRunning')} />
          </div>

          <div>
            <div className="mb-2 flex items-center justify-between">
              <span className="microlabel">{t('schedules.tasks')}</span>
              <Button
                size="sm"
                variant="secondary"
                onClick={() => setTasks((prev) => [...prev, { type: 'command', command: '' }])}
                disabled={tasks.length >= 10}
              >
                <Plus size={12} />
                {t('schedules.addTask')}
              </Button>
            </div>
            <div className="space-y-2">
              {tasks.map((task, i) => (
                <TaskEditor
                  key={i}
                  task={task}
                  onChange={(next) => setTasks((prev) => prev.map((p, j) => (j === i ? next : p)))}
                  onRemove={() => setTasks((prev) => prev.filter((_, j) => j !== i))}
                />
              ))}
            </div>
          </div>
        </div>
      </Modal>

      <ConfirmModal
        open={deleteTarget !== null}
        onClose={() => setDeleteTarget(null)}
        onConfirm={() => void remove()}
        message={t('schedules.deleteConfirm')}
        danger
        loading={busy}
        confirmLabel={t('common.delete')}
      />
    </div>
  )
}
