/**
 * Admin nodes page (/admin/nodes): AMP-"Spires"-style grid of machine cards —
 * the local panel host plus every registered remote node, each with live
 * health gauges (CPU/RAM/disk), latency, version and server count. The
 * add-node flow generates a join token client-side and shows the exact
 * command to boot the agent on the other machine.
 */
import { useCallback, useEffect, useRef, useState } from 'react'
import { Boxes, Check, Copy, Plus, Send, Trash2, TriangleAlert } from 'lucide-react'
import { api, ApiError } from '../api/client.ts'
import { wsClient } from '../api/ws.ts'
import type { HostSnapshot, NodeInfo, NodeTestResult, SystemInfo } from '../api/types.ts'
import { useT } from '../i18n/index.tsx'
import { useToast } from '../state/ToastContext.tsx'
import { Badge, Button, Card, Field, Input, PageHeader, Skeleton, cx } from '../components/ui.tsx'
import { Modal, ConfirmModal } from '../components/Modal.tsx'
import { ProgressBar } from '../components/Sparkline.tsx'
import { formatBytes, timeAgo } from '../lib/format.ts'

const POLL_MS = 5000

/** navigator.clipboard with the execCommand fallback for plain-http panels. */
async function copyText(text: string): Promise<void> {
  if (navigator.clipboard?.writeText) return navigator.clipboard.writeText(text)
  const ta = document.createElement('textarea')
  ta.value = text
  ta.style.position = 'fixed'
  ta.style.opacity = '0'
  document.body.appendChild(ta)
  ta.focus()
  ta.select()
  const ok = document.execCommand('copy')
  document.body.removeChild(ta)
  if (!ok) throw new Error('copy failed')
}

/** 32-char hex join token, generated client-side purely for convenience. */
function generateToken(): string {
  return crypto.randomUUID().replaceAll('-', '')
}

function Gauge({ label, pct, value }: { label: string; pct: number | null; value: string }) {
  return (
    <div>
      <div className="flex items-baseline justify-between gap-2">
        <span className="microlabel">{label}</span>
        <span className="tabular truncate text-xs font-semibold">{value}</span>
      </div>
      {/* Same min-width cap as the dashboard metric cards: tiny percentages
          stay a rounded sliver instead of collapsing to a dot. */}
      <ProgressBar pct={pct ?? 0} className="mt-1.5 [&>div]:min-w-3" />
    </div>
  )
}

function MetaStat({ label, value }: { label: string; value: string }) {
  return (
    <div className="min-w-0">
      <div className="microlabel">{label}</div>
      <div className="tabular mt-0.5 truncate text-[0.8125rem] font-semibold">{value}</div>
    </div>
  )
}

/** Shared card shell for the local machine and remote nodes. */
function MachineCard({
  name,
  sub,
  online,
  errorTooltip,
  badge,
  cpuPct,
  memUsed,
  memTotal,
  diskUsed,
  diskTotal,
  meta,
  footer,
}: {
  name: string
  sub: string
  online: boolean
  errorTooltip?: string | null
  badge?: React.ReactNode
  cpuPct: number | null
  memUsed: number | null
  memTotal: number | null
  diskUsed: number | null
  diskTotal: number | null
  meta: { label: string; value: string }[]
  footer?: React.ReactNode
}) {
  const t = useT()
  const pctOf = (used: number | null, total: number | null) =>
    used != null && total != null && total > 0 ? (used / total) * 100 : null
  const usedOf = (used: number | null, total: number | null) =>
    used != null && total != null && total > 0 ? `${formatBytes(used)} / ${formatBytes(total)}` : '—'
  return (
    <Card className="fade-in-up flex flex-col p-4">
      <div className="flex items-start gap-3">
        <span className="glass-subtle inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-xl text-accent">
          <Boxes size={17} />
        </span>
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <span className="truncate font-display text-[0.9375rem] font-semibold tracking-tight">{name}</span>
            {badge}
          </div>
          <div className="mt-0.5 truncate font-mono text-[0.6875rem] text-muted">{sub}</div>
        </div>
        <span
          className="glass-subtle inline-flex shrink-0 items-center gap-1.5 rounded-full px-2.5 py-1 text-[0.6875rem] font-medium"
          title={errorTooltip ?? undefined}
        >
          <span
            className={cx('h-1.5 w-1.5 rounded-full', online ? 'bg-success glow-success pulse-dot' : 'bg-danger')}
          />
          <span className={online ? 'text-success' : 'text-danger'}>{online ? t('nodes.online') : t('nodes.offline')}</span>
        </span>
      </div>

      <div className="mt-4 space-y-3">
        <Gauge label="CPU" pct={cpuPct} value={cpuPct != null ? `${cpuPct.toFixed(0)}%` : '—'} />
        <Gauge label="RAM" pct={pctOf(memUsed, memTotal)} value={usedOf(memUsed, memTotal)} />
        <Gauge label={t('nodes.disk')} pct={pctOf(diskUsed, diskTotal)} value={usedOf(diskUsed, diskTotal)} />
      </div>

      <div className="mt-4 grid flex-1 grid-cols-2 gap-x-3 gap-y-2.5 border-t border-line/60 pt-3 sm:grid-cols-4">
        {meta.map((m) => (
          <MetaStat key={m.label} label={m.label} value={m.value} />
        ))}
      </div>

      {footer && <div className="mt-4 border-t border-line/60 pt-3">{footer}</div>}
    </Card>
  )
}

function NodeCard({
  node,
  onRemove,
}: {
  node: NodeInfo
  onRemove: (node: NodeInfo) => void
}) {
  const t = useT()
  const h = node.health
  const [testing, setTesting] = useState(false)
  const [result, setResult] = useState<NodeTestResult | null>(null)

  const runTest = async () => {
    setTesting(true)
    setResult(null)
    try {
      setResult(await api.post<NodeTestResult>(`/api/nodes/${node.id}/test`))
    } catch (err) {
      setResult({ ok: false, error: err instanceof ApiError ? err.message : String(err) })
    } finally {
      setTesting(false)
    }
  }

  return (
    <MachineCard
      name={node.name}
      sub={node.baseUrl}
      online={h.online}
      errorTooltip={h.error}
      cpuPct={h.cpuPct}
      memUsed={h.memUsedBytes}
      memTotal={h.memTotalBytes}
      diskUsed={h.diskUsedBytes}
      diskTotal={h.diskTotalBytes}
      meta={[
        { label: t('nodes.latency'), value: h.latencyMs != null ? `${h.latencyMs} ms` : '—' },
        { label: t('nodes.version'), value: h.version ? `v${h.version}` : '—' },
        { label: t('nodes.serversOn'), value: String(node.serverCount) },
        { label: t('nodes.lastSeen'), value: h.lastSeen ? timeAgo(h.lastSeen, t) : t('common.never') },
      ]}
      footer={
        <div className="space-y-2.5">
          <div className="flex flex-wrap items-center gap-2">
            <Button size="sm" variant="secondary" onClick={() => void runTest()} loading={testing}>
              <Send size={12} />
              {t('nodes.test')}
            </Button>
            <Button
              size="sm"
              variant="ghost"
              className="ml-auto hover:bg-danger/15 hover:text-danger"
              onClick={() => onRemove(node)}
            >
              <Trash2 size={12} />
              {t('nodes.remove')}
            </Button>
          </div>
          {/* Inline diagnostic result — same treatment as the webhook test. */}
          {result &&
            (result.ok ? (
              <p className="flex items-start gap-1.5 text-xs font-medium text-success">
                <Check size={13} className="mt-px shrink-0" />
                <span className="tabular min-w-0 break-words">
                  {t('nodes.testOk', {
                    name: result.identity?.name ?? '?',
                    version: result.identity?.version ?? '?',
                    platform: result.identity?.platform ?? '?',
                    arch: result.identity?.arch ?? '?',
                    ms: result.latencyMs ?? '?',
                  })}
                </span>
              </p>
            ) : (
              <p className="break-words text-xs font-medium text-danger">
                {t('nodes.testFail', { error: result.error ?? '?' })}
              </p>
            ))}
        </div>
      }
    />
  )
}

function AddNodeModal({
  open,
  onClose,
  onAdded,
}: {
  open: boolean
  onClose: () => void
  onAdded: () => void
}) {
  const t = useT()
  const toast = useToast()
  const [token, setToken] = useState(generateToken)
  const [name, setName] = useState('')
  const [baseUrl, setBaseUrl] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [created, setCreated] = useState<NodeInfo | null>(null)
  const [testResult, setTestResult] = useState<NodeTestResult | null>(null)
  const [copied, setCopied] = useState(false)
  const copiedTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined)

  // Fresh token + clean form per open — a join token is single-purpose.
  useEffect(() => {
    if (open) {
      setToken(generateToken())
      setName('')
      setBaseUrl('')
      setError(null)
      setCreated(null)
      setTestResult(null)
    }
  }, [open])

  useEffect(() => () => clearTimeout(copiedTimer.current), [])

  const command = `BETWEEN_MODE=node BETWEEN_NODE_TOKEN=${token} BETWEEN_PORT=8485 npm start`

  const copyCommand = async () => {
    try {
      await copyText(command)
      setCopied(true)
      clearTimeout(copiedTimer.current)
      copiedTimer.current = setTimeout(() => setCopied(false), 1500)
    } catch {
      toast('error', t('common.copyFailed'))
    }
  }

  const save = async () => {
    setSaving(true)
    setError(null)
    try {
      const res = await api.post<{ node: NodeInfo }>('/api/nodes', { name, baseUrl, token })
      setCreated(res.node)
      onAdded()
      // Auto-test the fresh registration so the admin immediately sees
      // whether panel → agent connectivity actually works.
      try {
        setTestResult(await api.post<NodeTestResult>(`/api/nodes/${res.node.id}/test`))
      } catch (err) {
        setTestResult({ ok: false, error: err instanceof ApiError ? err.message : String(err) })
      }
    } catch (err) {
      setError(err instanceof ApiError ? err.message : String(err))
    } finally {
      setSaving(false)
    }
  }

  const dirty = !created && (name.trim() !== '' || baseUrl.trim() !== '')

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={t('nodes.add')}
      dirty={dirty}
      footer={
        created ? (
          <Button variant="primary" onClick={onClose}>
            {t('common.close')}
          </Button>
        ) : (
          <>
            <Button variant="ghost" onClick={onClose}>
              {t('common.cancel')}
            </Button>
            <Button
              variant="primary"
              onClick={() => void save()}
              loading={saving}
              disabled={!name.trim() || !baseUrl.trim() || !token.trim()}
            >
              <Plus size={14} />
              {t('nodes.connect')}
            </Button>
          </>
        )
      }
    >
      <div className="space-y-5">
        <section>
          <h4 className="microlabel mb-2">1 · {t('nodes.step1')}</h4>
          <p className="text-xs leading-relaxed text-muted">{t('nodes.step1Hint')}</p>
          <div className="glass-subtle mt-2.5 flex items-start gap-2 rounded-xl p-3">
            <code className="min-w-0 flex-1 break-all font-mono text-xs leading-relaxed text-text/90">{command}</code>
            <button
              type="button"
              onClick={() => void copyCommand()}
              aria-label={copied ? t('common.copied') : t('nodes.copyCmd')}
              title={copied ? t('common.copied') : t('nodes.copyCmd')}
              className="pressable shrink-0 rounded-lg p-1.5 text-muted hover:bg-elevated/70 hover:text-text focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40"
            >
              {copied ? <Check size={14} className="text-success" /> : <Copy size={14} />}
            </button>
          </div>
          <p className="mt-2 flex items-start gap-1.5 text-xs font-medium text-warn">
            <TriangleAlert size={13} className="mt-px shrink-0" />
            {t('nodes.tokenWarning')}
          </p>
        </section>

        <section className="border-t border-line/60 pt-4">
          <h4 className="microlabel mb-3">2 · {t('nodes.step2')}</h4>
          <div className="space-y-4">
            <div className="grid gap-4 sm:grid-cols-2">
              <Field label={t('common.name')}>
                <Input value={name} onChange={(e) => setName(e.target.value)} placeholder={t('nodes.namePh')} maxLength={60} disabled={created !== null} />
              </Field>
              <Field label={t('nodes.baseUrl')}>
                <Input
                  value={baseUrl}
                  onChange={(e) => setBaseUrl(e.target.value)}
                  placeholder="http://192.168.x.x:8485"
                  spellCheck={false}
                  disabled={created !== null}
                  className="font-mono text-xs"
                />
              </Field>
            </div>
            <Field label={t('nodes.token')} hint={t('nodes.tokenHint')}>
              <Input
                value={token}
                onChange={(e) => setToken(e.target.value)}
                spellCheck={false}
                disabled={created !== null}
                className="font-mono text-xs"
              />
            </Field>
          </div>
          {error && <p className="mt-3 text-sm text-danger">{error}</p>}
          {created && (
            <div className="glass-subtle mt-4 rounded-xl border-success/30 bg-success/10 p-3">
              <p className="flex items-center gap-1.5 text-sm font-medium text-success">
                <Check size={14} />
                {t('nodes.added')}
              </p>
              {testResult && (
                <p className={cx('tabular mt-1.5 break-words text-xs font-medium', testResult.ok ? 'text-success' : 'text-danger')}>
                  {testResult.ok
                    ? t('nodes.testOk', {
                        name: testResult.identity?.name ?? '?',
                        version: testResult.identity?.version ?? '?',
                        platform: testResult.identity?.platform ?? '?',
                        arch: testResult.identity?.arch ?? '?',
                        ms: testResult.latencyMs ?? '?',
                      })
                    : t('nodes.testFail', { error: testResult.error ?? '?' })}
                </p>
              )}
            </div>
          )}
        </section>
      </div>
    </Modal>
  )
}

function NodesSkeleton() {
  return (
    <div className="stagger grid gap-4 md:grid-cols-2 xl:grid-cols-3" aria-busy="true">
      {[0, 1].map((i) => (
        <div key={i} className="glass fade-in-up rounded-2xl p-4">
          <div className="flex items-center gap-3">
            <Skeleton className="h-9 w-9" />
            <div className="flex-1">
              <Skeleton className="h-4.5 w-32 rounded-full" />
              <Skeleton className="mt-1.5 h-3 w-44 rounded-full" />
            </div>
            <Skeleton className="h-6 w-16 rounded-full" />
          </div>
          <div className="mt-4 space-y-3">
            {[0, 1, 2].map((j) => (
              <div key={j}>
                <Skeleton className="h-3 w-full max-w-40 rounded-full" />
                <Skeleton className="mt-1.5 h-2 w-full rounded-full" />
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  )
}

export function NodesPage() {
  const t = useT()
  const toast = useToast()
  const [nodes, setNodes] = useState<NodeInfo[] | null>(null)
  const [system, setSystem] = useState<SystemInfo | null>(null)
  const [addOpen, setAddOpen] = useState(false)
  const [removeTarget, setRemoveTarget] = useState<NodeInfo | null>(null)
  const [removing, setRemoving] = useState(false)

  const load = useCallback(async () => {
    try {
      const res = await api.get<{ nodes: NodeInfo[] }>('/api/nodes')
      setNodes(res.nodes)
    } catch {
      /* transient poll failure — keep the last known state */
    }
  }, [])

  useEffect(() => {
    void load()
    void api.get<{ system: SystemInfo }>('/api/system').then((r) => setSystem(r.system)).catch(() => undefined)
    // Node health refreshes server-side on its own poll loop; mirror it here
    // so offline nodes surface without a manual reload.
    const timer = setInterval(() => void load(), POLL_MS)
    // The local card rides the existing host-metrics WS stream (5s cadence).
    const off = wsClient.onMessage((msg) => {
      if (msg.t === 'metrics') setSystem((prev) => (prev ? { ...prev, metrics: msg.snap as HostSnapshot } : prev))
    })
    return () => {
      clearInterval(timer)
      off()
    }
  }, [load])

  const remove = async () => {
    if (!removeTarget) return
    setRemoving(true)
    try {
      await api.del(`/api/nodes/${removeTarget.id}`)
      setRemoveTarget(null)
      await load()
    } catch (err) {
      toast('error', err instanceof ApiError ? err.message : String(err))
    } finally {
      setRemoving(false)
    }
  }

  const m = system?.metrics ?? null

  return (
    <div className="fade-in-up">
      <PageHeader
        title={t('nodes.title')}
        subtitle={t('nodes.subtitle')}
        actions={
          <Button variant="primary" onClick={() => setAddOpen(true)}>
            <Plus size={15} />
            {t('nodes.add')}
          </Button>
        }
      />

      {!nodes && <NodesSkeleton />}

      {nodes && (
        <div className="stagger grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {/* The panel machine itself, so this page reads as "all the machines
              your servers run on" — clearly badged as local. */}
          <MachineCard
            name={t('nodes.thisPanel')}
            sub={system ? `${system.hostname} · ${system.platform}/${system.arch}` : '…'}
            online
            badge={<Badge className="shrink-0 border-accent/30 bg-accent/10 text-accent">{t('nodes.localBadge')}</Badge>}
            cpuPct={m?.cpuPct ?? null}
            memUsed={m?.memUsedBytes ?? null}
            memTotal={m?.memTotalBytes ?? null}
            diskUsed={m && m.diskTotalBytes > 0 ? m.diskUsedBytes : null}
            diskTotal={m && m.diskTotalBytes > 0 ? m.diskTotalBytes : null}
            meta={[
              { label: t('nodes.latency'), value: '—' },
              { label: t('nodes.version'), value: system ? `v${system.panelVersion}` : '—' },
              { label: t('nodes.serversOn'), value: system ? String(system.serverCount) : '—' },
              { label: t('nodes.lastSeen'), value: t('time.justNow') },
            ]}
          />

          {nodes.map((node) => (
            <NodeCard key={node.id} node={node} onRemove={setRemoveTarget} />
          ))}

          {nodes.length === 0 && (
            <button
              onClick={() => setAddOpen(true)}
              className={cx(
                'glass-subtle card-hover pressable fade-in-up flex min-h-56 flex-col items-center justify-center gap-3 rounded-2xl p-6 text-center',
                'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40',
              )}
            >
              <span className="glass-subtle rounded-2xl p-3 text-accent">
                <Plus size={22} />
              </span>
              <span>
                <span className="block font-display text-[0.9375rem] font-semibold tracking-tight">{t('nodes.add')}</span>
                <span className="mx-auto mt-1 block max-w-60 text-xs leading-relaxed text-muted">{t('nodes.emptyInvite')}</span>
              </span>
            </button>
          )}
        </div>
      )}

      <AddNodeModal open={addOpen} onClose={() => setAddOpen(false)} onAdded={() => void load()} />

      <ConfirmModal
        open={removeTarget !== null}
        onClose={() => setRemoveTarget(null)}
        onConfirm={() => void remove()}
        title={t('nodes.remove')}
        message={t('nodes.removeConfirm', { name: removeTarget?.name ?? '' })}
        danger
        loading={removing}
        confirmLabel={t('nodes.remove')}
      />
    </div>
  )
}
