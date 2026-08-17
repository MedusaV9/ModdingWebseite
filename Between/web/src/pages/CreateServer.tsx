import { Fragment, useEffect, useMemo, useState } from 'react'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import { ArrowLeft, ArrowRight, Boxes, Check, Container, Monitor, Search } from 'lucide-react'
import { api, ApiError } from '../api/client.ts'
import type { Blueprint, NodeInfo, ServerDetail, ServerRuntime } from '../api/types.ts'
import { useT } from '../i18n/index.tsx'
import { useToast } from '../state/ToastContext.tsx'
import { Badge, Button, Card, Chip, Field, Input, PageHeader, Spinner, Toggle, cx } from '../components/ui.tsx'
import { GameIcon } from '../components/GameIcon.tsx'
import { VariablesForm, defaultsFor, type VarValues } from '../components/VariablesForm.tsx'
import { DockerSettingsFields, RuntimePicker, dockerFormToPayload, emptyDockerForm, type DockerFormValues } from '../components/RuntimePicker.tsx'

export function CreateServer() {
  const t = useT()
  const toast = useToast()
  const navigate = useNavigate()
  const [params] = useSearchParams()
  const [blueprints, setBlueprints] = useState<Blueprint[] | null>(null)
  const [hostPlatform, setHostPlatform] = useState('')
  const [dockerInfo, setDockerInfo] = useState<{ available: boolean; version: string | null }>({ available: false, version: null })
  const [step, setStep] = useState(0)
  const [selected, setSelected] = useState<Blueprint | null>(null)
  const [search, setSearch] = useState('')
  const [category, setCategory] = useState('all')
  const [name, setName] = useState('')
  const [values, setValues] = useState<VarValues>({})
  const [autoStart, setAutoStart] = useState(false)
  const [startAfterInstall, setStartAfterInstall] = useState(true)
  const [runtime, setRuntime] = useState<ServerRuntime>('process')
  const [dockerForm, setDockerForm] = useState<DockerFormValues>(emptyDockerForm())
  // Remote nodes ('' = this panel). Non-admins can't list nodes (403) — the
  // catch leaves the list empty and the picker absent, same as zero nodes.
  const [nodes, setNodes] = useState<NodeInfo[]>([])
  const [nodeId, setNodeId] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    void api
      .get<{ blueprints: Blueprint[]; platform: string; docker?: { available: boolean; version: string | null } }>('/api/blueprints')
      .then((res) => {
        setBlueprints(res.blueprints)
        setHostPlatform(res.platform)
        if (res.docker) setDockerInfo(res.docker)
        const preselect = params.get('blueprint')
        if (preselect) {
          const bp = res.blueprints.find((b) => b.id === preselect)
          if (bp) {
            setSelected(bp)
            setValues(defaultsFor(bp))
            // Same prefill as choose(): deep-linked flows must not land on an
            // empty required name (dead Next button).
            setName((n) => n || bp.name)
            setStep(1)
          }
        }
      })
      .catch((err) => setError((err as Error).message))
    void api
      .get<{ nodes: NodeInfo[] }>('/api/nodes')
      .then((res) => setNodes(res.nodes))
      .catch(() => undefined)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const categories = useMemo(() => {
    if (!blueprints) return []
    return ['all', ...new Set(blueprints.map((b) => b.category))]
  }, [blueprints])

  const filtered = useMemo(() => {
    if (!blueprints) return []
    const q = search.trim().toLowerCase()
    return blueprints.filter((b) => {
      if (category !== 'all' && b.category !== category) return false
      if (!q) return true
      return b.name.toLowerCase().includes(q) || b.description.toLowerCase().includes(q) || b.id.includes(q)
    })
  }, [blueprints, search, category])

  const choose = (bp: Blueprint) => {
    setSelected(bp)
    setValues(defaultsFor(bp))
    setRuntime('process')
    setDockerForm(emptyDockerForm())
    if (!name) setName(bp.name)
    setStep(1)
  }

  const remote = nodeId !== ''
  const targetNode = remote ? nodes.find((n) => n.id === nodeId) ?? null : null

  // Docker runtime is offered when the daemon is reachable and the blueprint
  // supports Linux (containers are Linux even on Windows/macOS hosts).
  // Remote nodes run host processes in this round — the panel can't probe a
  // node's Docker daemon yet, so it never offers an option it can't verify.
  const dockerSelectable = !remote && dockerInfo.available && Boolean(selected?.platforms.includes('linux'))
  const effectiveRuntime: ServerRuntime = remote ? 'process' : runtime
  const dockerImageMissing = effectiveRuntime === 'docker' && !selected?.docker?.image && dockerForm.image.trim() === ''

  const submit = async () => {
    if (!selected) return
    setBusy(true)
    setError(null)
    try {
      const res = await api.post<{ server: ServerDetail }>('/api/servers', {
        name,
        blueprintId: selected.id,
        variables: values,
        autoStart,
        startAfterInstall,
        runtime: effectiveRuntime,
        ...(effectiveRuntime === 'docker' ? { docker: dockerFormToPayload(dockerForm) } : {}),
        ...(remote ? { nodeId } : {}),
      })
      toast('success', t('toast.serverCreated'))
      navigate(`/servers/${res.server.id}`)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : String(err))
      setBusy(false)
    }
  }

  const steps = [t('create.step1'), t('create.step2'), t('create.step3')]

  return (
    <div className="fade-in-up">
      <PageHeader
        title={t('create.title')}
        actions={
          <Link to="/servers">
            <Button variant="ghost">
              <ArrowLeft size={15} />
              {t('common.back')}
            </Button>
          </Link>
        }
      />

      {/* Stepper: numbered circles + connector lines; done steps are clickable */}
      <div className="mb-6 flex items-center gap-2 sm:gap-3">
        {steps.map((label, i) => {
          const done = i < step
          const active = i === step
          return (
            <Fragment key={label}>
              {i > 0 && (
                <div
                  aria-hidden
                  className={cx(
                    'h-px min-w-4 flex-1 max-w-16 sm:max-w-24',
                    // Track fills up to the current step (connector i leads into step i).
                    i <= step
                      ? 'bg-[linear-gradient(90deg,color-mix(in_oklab,var(--t-accent)_60%,transparent),color-mix(in_oklab,var(--t-accent2)_60%,transparent))]'
                      : 'bg-line',
                  )}
                />
              )}
              <button
                onClick={() => done && setStep(i)}
                disabled={!done}
                aria-current={active ? 'step' : undefined}
                className={cx(
                  'pressable flex shrink-0 items-center gap-2.5 rounded-full',
                  'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40',
                  !done && 'cursor-default',
                )}
              >
                <span
                  className={cx(
                    'inline-flex h-8 w-8 items-center justify-center rounded-full text-[0.8125rem] font-bold',
                    active
                      ? 'btn-gradient glow-accent text-onaccent'
                      : done
                        ? 'sheen border border-success/40 bg-success/15 text-success'
                        : 'glass-subtle text-muted/70',
                  )}
                >
                  {done ? <Check size={14} /> : i + 1}
                </span>
                <span
                  className={cx(
                    'hidden text-xs font-semibold sm:block',
                    active ? 'text-text' : done ? 'text-text/80' : 'text-muted/60',
                  )}
                >
                  {label}
                </span>
              </button>
            </Fragment>
          )
        })}
      </div>

      {/* Step 1: blueprint picker */}
      {step === 0 && (
        <>
          <div className="mb-6 flex flex-wrap items-center gap-2">
            <div className="relative w-full max-w-xs">
              <Search size={14} className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-muted" />
              <Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder={t('create.blueprintSearch')} className="rounded-full pl-8" autoFocus />
            </div>
            <div className="flex flex-wrap items-center gap-1.5">
              {categories.map((cat) => (
                <Chip key={cat} active={category === cat} onClick={() => setCategory(cat)}>
                  {cat === 'all' ? t('create.categories.all') : cat}
                </Chip>
              ))}
            </div>
          </div>
          {!blueprints && <Spinner />}
          <div className="stagger grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            {filtered.map((bp) => {
              const supported = bp.platforms.includes(hostPlatform)
              return (
                <button
                  key={bp.id}
                  onClick={() => supported && choose(bp)}
                  disabled={!supported}
                  className={cx(
                    // Dense grid (70+ cards): blur-free glass tint keeps the frosted
                    // look without one backdrop-filter per card (perf budget).
                    'glass-subtle fade-in-up rounded-2xl p-4 text-left',
                    'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40',
                    supported ? 'pressable hover:border-accent/50 hover:bg-elevated/50' : 'opacity-45',
                    selected?.id === bp.id && 'ring-2 ring-accent',
                  )}
                >
                  <div className="flex items-center gap-3">
                    <GameIcon icon={bp.icon} color={bp.color} boxed size={20} />
                    <div className="min-w-0">
                      <div className="truncate font-display text-[0.875rem] font-semibold tracking-tight">{bp.name}</div>
                      <div className="text-[0.6875rem] capitalize text-muted">
                        {bp.category}
                        {bp.custom && <span className="ml-1 text-accent2">· {t('bp.custom')}</span>}
                      </div>
                    </div>
                  </div>
                  <p className="mt-2 line-clamp-2 text-xs leading-relaxed text-muted">{bp.description}</p>
                  {!supported && <p className="mt-2 text-[0.6875rem] font-medium text-warn">{t('create.notSupported')}</p>}
                </button>
              )
            })}
          </div>
        </>
      )}

      {/* Step 2: configure */}
      {step === 1 && selected && (
        <Card className="fade-in-up p-5">
          <div className="mb-5 flex items-center gap-3 border-b border-line/60 pb-4">
            <GameIcon icon={selected.icon} color={selected.color} boxed size={22} />
            <div>
              <div className="font-display text-lg font-semibold tracking-tight">{selected.name}</div>
              <div className="text-xs text-muted">{selected.description}</div>
            </div>
          </div>
          <div className="mb-5 grid gap-4 sm:grid-cols-2">
            <Field label={t('create.serverName')}>
              <Input value={name} onChange={(e) => setName(e.target.value)} placeholder={t('create.serverNamePh')} maxLength={60} autoFocus />
            </Field>
            <div className="flex flex-col justify-end gap-2.5 pb-1">
              <Toggle checked={startAfterInstall} onChange={setStartAfterInstall} label={t('create.startAfterInstall')} />
              <Toggle checked={autoStart} onChange={setAutoStart} label={t('create.autoStart')} />
            </div>
          </div>
          {/* Node picker — only rendered when at least one remote node exists;
              with zero nodes the flow is byte-identical to before. */}
          {nodes.length > 0 && (
            <div className="mb-5">
              <h3 className="microlabel mb-2">{t('create.node')}</h3>
              <div className="grid gap-2 sm:grid-cols-2">
                {[null, ...nodes].map((node) => {
                  const value = node?.id ?? ''
                  const active = nodeId === value
                  const online = node ? node.health.online : true
                  return (
                    <button
                      key={value || 'local'}
                      type="button"
                      onClick={() => online && setNodeId(value)}
                      disabled={!online}
                      aria-pressed={active}
                      className={cx(
                        'glass-subtle pressable relative flex items-start gap-3 rounded-xl p-3 pr-9 text-left',
                        'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40',
                        active && 'border-accent/60 bg-accent/10 ring-1 ring-accent/30',
                        online && !active && 'hover:border-accent/40',
                        !online && 'opacity-45 saturate-50',
                      )}
                    >
                      <span className={cx('mt-0.5 shrink-0 rounded-lg p-1.5', active ? 'bg-accent/20 text-accent' : 'bg-elevated/70 text-muted')}>
                        {node ? <Boxes size={18} /> : <Monitor size={18} />}
                      </span>
                      <span className="min-w-0">
                        <span className="flex items-center gap-1.5 text-sm font-semibold">
                          <span className="truncate">{node ? node.name : t('create.nodeLocal')}</span>
                          <span
                            aria-hidden
                            className={cx('h-1.5 w-1.5 shrink-0 rounded-full', online ? 'bg-success' : 'bg-danger')}
                          />
                        </span>
                        <span className="mt-0.5 block truncate font-mono text-[0.6875rem] leading-snug text-muted">
                          {node ? node.baseUrl : location.host}
                          {node && !online && <span className="ml-1.5 font-sans font-medium text-danger">{t('create.nodeOfflineChip')}</span>}
                        </span>
                      </span>
                      {active && (
                        <span aria-hidden className="scale-in absolute right-2.5 top-2.5 rounded-full bg-accent p-0.5 text-onaccent">
                          <Check size={11} strokeWidth={3} />
                        </span>
                      )}
                    </button>
                  )
                })}
              </div>
              <p className="mt-2 text-xs text-muted">{t('create.nodeHint')}</p>
            </div>
          )}
          {remote ? (
            <div className="mb-5">
              <h3 className="microlabel mb-2">{t('runtime.title')}</h3>
              <p className="glass-subtle rounded-xl px-3 py-2.5 text-xs text-muted">{t('create.nodeRuntimeHint')}</p>
            </div>
          ) : (
            <div className="mb-5">
              <h3 className="microlabel mb-2">{t('runtime.title')}</h3>
              <RuntimePicker
                runtime={runtime}
                onRuntimeChange={setRuntime}
                dockerAvailable={dockerSelectable}
                dockerVersion={dockerInfo.version}
              />
              {runtime === 'docker' && (
                <div className="glass-subtle mt-4 rounded-xl p-4">
                  <DockerSettingsFields blueprint={selected} values={dockerForm} onChange={setDockerForm} />
                </div>
              )}
            </div>
          )}
          <VariablesForm blueprint={selected} values={values} onChange={setValues} />
          <p className="mt-4 text-xs text-muted">{t('create.portHint')}</p>
          <div className="mt-5 flex justify-between gap-2 border-t border-line/60 pt-4">
            <Button variant="ghost" onClick={() => setStep(0)}>
              <ArrowLeft size={15} />
              {t('common.back')}
            </Button>
            <Button variant="primary" onClick={() => setStep(2)} disabled={!name.trim() || dockerImageMissing}>
              {t('common.next')}
              <ArrowRight size={15} />
            </Button>
          </div>
        </Card>
      )}

      {/* Step 3: review */}
      {step === 2 && selected && (
        <Card className="fade-in-up p-5">
          <div className="grid gap-5 sm:grid-cols-2">
            <div>
              <h3 className="microlabel mb-2">{t('create.review.blueprint')}</h3>
              <div className="glass-subtle flex items-center gap-3 rounded-xl p-3">
                <GameIcon icon={selected.icon} color={selected.color} boxed size={20} />
                <div>
                  <div className="font-semibold">{name}</div>
                  <div className="text-xs text-muted">{selected.name}</div>
                </div>
              </div>
              <div className="mt-3 flex flex-wrap gap-1.5">
                {targetNode && (
                  <Badge className="text-accent">
                    <Boxes size={11} className="mr-1 inline" />
                    {targetNode.name}
                  </Badge>
                )}
                {startAfterInstall && <Badge className="text-success">{t('create.startAfterInstall')}</Badge>}
                {autoStart && <Badge className="text-accent">{t('create.autoStart')}</Badge>}
                {effectiveRuntime === 'docker' && (
                  <Badge className="text-accent2">
                    <Container size={11} className="mr-1 inline" />
                    {dockerForm.image.trim() || selected.docker?.image || 'docker'}
                  </Badge>
                )}
              </div>
            </div>
            <div>
              <h3 className="microlabel mb-2">{t('create.review.variables')}</h3>
              <div className="glass-subtle max-h-64 space-y-1 overflow-y-auto rounded-xl p-3">
                {selected.variables.map((v) => (
                  <div key={v.key} className="flex justify-between gap-3 text-[0.8125rem]">
                    <span className="text-muted">{v.label}</span>
                    <span className="truncate font-mono">
                      {v.type === 'password' ? '••••••' : String(values[v.key] ?? v.default)}
                    </span>
                  </div>
                ))}
                {selected.variables.length === 0 && <p className="text-xs text-muted">{t('common.none')}</p>}
              </div>
            </div>
          </div>
          {error && <p className="mt-4 text-sm text-danger">{error}</p>}
          <div className="mt-5 flex justify-between gap-2 border-t border-line/60 pt-4">
            <Button variant="ghost" onClick={() => setStep(1)}>
              <ArrowLeft size={15} />
              {t('common.back')}
            </Button>
            <Button variant="primary" onClick={() => void submit()} loading={busy}>
              <Check size={16} />
              {t('create.submit')}
            </Button>
          </div>
        </Card>
      )}
    </div>
  )
}
